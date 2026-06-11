# Architecture

Single workflow, linear pipeline with a back-edge for regeneration. Twenty-one nodes, all connected.

## Envelope

A single `$json` object flows through every node. Each Code node reads from `$json`, computes its delta, and returns `{...$json, <new fields>}`. There is one source of truth.

```
board, class_name, chapter, source_type,
question_type ("A&R" form-facing), question_type_folder ("AR" disk-facing),
difficulty, number_of_questions, include_visual_questions, language,
generate_explanation, prompt_key, chapter_code, difficulty_code, batch_id,
selected_prompt, system_generator, system_structurer, system_validator,
cleaned_text, chapter_knowledge, target_folder_id, drive_folder_trail,
existing_stems, prompt_user_message, attempt,
generated_questions, validated_questions, unique_questions, kept_questions,
rejected, dropped_duplicates, validator_verdict,
final_payload, file_name
```

## Node-by-node

| # | Node | Type | Role |
|---|---|---|---|
| 1 | On form submission | formTrigger | 11 visible + 18 hidden prompts + 3 hidden system prompts |
| 2 | Normalize Input | code | Coerces types, builds `batch_id` / `chapter_code` / `difficulty_code` / `prompt_key`; resolves `PROMPT_${type}_${diff}` from hidden form fields into `selected_prompt`; carries forward the 3 system prompts |
| 3 | Extract PDF Text | extractFromFile | PDF → joined text |
| 4 | Clean PDF Text | code | Strips page numbers, repeated headers/footers (lines appearing >5×), de-hyphenates line breaks, drops URL/email lines, collapses duplicate paragraphs |
| 5 | Structure Chapter Knowledge | anthropic (Haiku, T=0) | Cleaned text → structured `chapter_knowledge` JSON |
| 6 | Attach Knowledge Object | code | Parses the structurer JSON and merges into envelope |
| 7 | Ensure Drive Folders | code (Drive REST) | `findOrCreate` for `Question Bank / CBSE / <Class> / <Chapter> / <Type> / <Difficulty>`; returns `target_folder_id` + `drive_folder_trail` |
| 8 | Load Existing Bank Stems | code (Drive REST) | Lists ≤20 recent JSON files in `target_folder_id`, downloads them, extracts question stems (incl. CASE_STUDY `passage` and `sub_questions[].question`) |
| 9 | Build Prompt | code | Interpolates `{{n}}` (deficit on regen passes), injects `chapter_knowledge` and `existing_stems` into the user message, increments `attempt` |
| 10 | AI: Generate Questions | anthropic (Sonnet, T=0.4) | Strict-JSON generator |
| 11 | Parse Generation | code | Parses generator output, validates non-empty `questions[]` |
| 12 | AI: Validate Questions | anthropic (Haiku, T=0) | Per-question 9-check verdict |
| 13 | Filter Valid Questions | code | Drops items not marked `valid: true`; accumulates `rejected[]` |
| 14 | Deduplicate vs Bank | code | Trigram-Jaccard ≥ 0.85 against `existing_stems` and within batch; accumulates `dropped_duplicates[]` |
| 15 | Need Regeneration? | if | `(kept + unique) < requested AND attempt < 3` |
| 16 | Prepare Regeneration | code | Carries forward kept items; appends their stems to `existing_stems` so the next generation pass avoids them |
| 17 | Finalize JSON | code | Re-IDs sequentially, drops any last intra-batch duplicate, composes the spec-shaped payload + filename |
| 18 | JSON → Binary | code | Wraps payload as `application/json` binary |
| 19 | Upload to Google Drive | googleDrive | Lands the file inside `target_folder_id` |
| 20 | Log Run Summary | code | Final telemetry item (batch id, counts, attempts) |

## Connections (all wired)

```
On form submission → Normalize Input → Extract PDF Text → Clean PDF Text
→ Structure Chapter Knowledge → Attach Knowledge Object → Ensure Drive Folders
→ Load Existing Bank Stems → Build Prompt → AI: Generate Questions
→ Parse Generation → AI: Validate Questions → Filter Valid Questions
→ Deduplicate vs Bank → Need Regeneration?
        (true) → Prepare Regeneration → Build Prompt   [back-edge]
        (false) → Finalize JSON → JSON → Binary → Upload to Google Drive → Log Run Summary
```

Every node has at least one inbound and one outbound connection except the trigger (no inbound) and `Log Run Summary` (no outbound).

## Key design choices

### Single-workflow prompt routing

The spec mandates one workflow. Routing is achieved by:
- 18 hidden form fields keyed `PROMPT_<TYPE>_<DIFFICULTY>`.
- `Normalize Input` reads `form[PROMPT_${typeKey}_${diff}]` and writes it to `selected_prompt`.
- A missing key throws immediately (`Missing hidden prompt field: ...`) — there is no silent fallback that could mask a bug.

### Structurer pass before generation

Raw PDF text is 20-40 pages of mostly prose. Feeding it directly to the generator wastes tokens and invites hallucination. Instead:
- One cheap Haiku call extracts `chapter_knowledge` once.
- Generator and validator both see only this object — common ground truth.
- Net token spend drops ~70% per regeneration attempt.

### Validator as a second LLM call

Self-review by the same generator on the same context window is theatre. The validator is a separate Haiku call at T=0 that returns nine booleans per question. Only `valid: true` items pass.

### Trigram-Jaccard dedupe

Two passes — within batch (Set lookup on normalised text), and against the existing bank (Jaccard ≥ 0.85 over trigram sets). Reads only the 20 most recent files in the target folder; full-bank reads do not scale and are not needed.

Swap-out point: replace the body of `Deduplicate vs Bank` with vector lookups. Inputs and outputs are unchanged.

### Regeneration loop

Bounded by `attempt < 3` and `(kept + unique) < requested`. On each loop:
- Kept items are carried forward (no re-validation cost).
- Their stems are appended to `existing_stems` so the generator avoids producing them again.
- `Build Prompt` re-renders with `n = deficit` so we don't pay for over-generation.

### Folder creation

`Ensure Drive Folders` is a Code node walking the path with `findOrCreate` per segment via the Drive REST API. Idempotent; one `files.list` per level on subsequent runs.

### A&R aliasing

The spec's UI dropdown uses `AR`. The output JSON uses `A&R` per readability. The Drive folder uses `AR` because `&` in folder names is awkward. `Normalize Input` keeps both `question_type` (`A&R`) and `question_type_folder` (`AR`) on the envelope; downstream nodes use whichever they need.

## Error / retry behaviour

- Strict JSON parsing in `Attach Knowledge Object`, `Parse Generation`, `Filter Valid Questions` — malformed LLM output fails loudly rather than silently producing zero questions.
- `Ensure Drive Folders` retries via the Drive REST credential's built-in OAuth refresh; n8n's per-node retry handles 5xx.
- Regeneration loop has a hard cap (3 attempts) so a stubborn LLM cannot infinite-loop.
- The `IF` node's false branch is the success path — there is no "swallowed error" branch.

## What is intentionally not here

- **No per-question Drive upload.** The spec's output JSON groups all questions in one file per (chapter × type × difficulty). One upload per submission keeps the bank tidy and the dedupe lookup cheap.
- **No analytics writes.** `Log Run Summary` is the seam; pipe it to wherever fits your stack.
- **No PDF page-splitting.** CBSE chapters fit comfortably in the structurer's context window. Add splitting only when a real chapter doesn't fit.
