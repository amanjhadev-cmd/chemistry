# Architecture

## 1. Single-workflow design

The platform is one workflow with dynamic routing — not 18 sibling workflows.

The key trick is the **envelope object** that flows through every node:

```json
{
  "board": "CBSE",
  "class_name": "Class XII",
  "chapter": "Solutions",
  "source_type": "NCERT",
  "question_type": "MCQ",
  "difficulty": "MEDIUM",
  "number_of_questions": 10,
  "include_visual_questions": false,
  "language": "English",
  "generate_explanation": true,
  "prompt_key": "MCQ_MEDIUM",
  "chapter_code": "SOLUTIONS",
  "difficulty_code": "M",
  "batch_id": "lz9k2r-7f3a1c",
  "started_at": "2026-06-11T09:00:00Z",
  "cleaned_text": "...",
  "chapter_knowledge": { ... },
  "existing_stems": ["..."],
  "target_folder_id": "1aBc...",
  "drive_folder_trail": [ { "name": "Question Bank", "id": "..." }, ... ],
  "attempt": 1,
  "generated_questions": [...],
  "validated_questions": [...],
  "unique_questions": [...],
  "kept_questions": [...],
  "rejected": [...],
  "dropped_duplicates": [...],
  "final_payload": { ... },
  "file_name": "..."
}
```

Every Code node reads from `$json`, computes its delta, and returns `{...$json, <new fields>}`. There is one source of truth, no node knows about siblings.

## 2. Why an upstream "Structure Chapter Knowledge" step

Sending raw PDF text to the generator wastes tokens (CBSE chapters are 20-40 pages of mostly prose) and *invites hallucination* — the model fills gaps with plausible-but-wrong NCERT-adjacent facts.

The structurer call:
- Runs once per batch on the cheap model (Haiku).
- Returns a compact JSON of `summary / sub_topics / definitions / formulae / reactions / numerical_data / examples / diagram_refs`.
- The generator and the validator both receive **only** this object, so they share a common ground truth.

Net effect: generator prompts are ~70 % smaller and the validator can ground-truth check by looking at the same JSON.

## 3. Prompt routing

`Build Prompt` is a Code node — not a Switch. A Switch would force one branch per combination (18 branches, plus duplicates of every downstream node).

```js
const templates = JSON.parse($vars.PROMPT_TEMPLATES);
const entry = templates[ctx.prompt_key];   // "MCQ_MEDIUM" etc.
```

Adding a new question type means one PR that:
1. Adds the type to the form dropdown.
2. Adds three templates (`<TYPE>_EASY/MEDIUM/HARD`) to `prompts/templates.json`.
3. Adds the type to `config/config.json` and to the Drive folder list.

No workflow surgery.

## 4. Validation as a separate model call

A *second* LLM call (Haiku at temperature 0) validates the first one. We deliberately do not let the generator self-review — it's the same model, same context window, same blind spots.

The validator receives:
- The **chapter_knowledge** object (single source of truth)
- The expected type and difficulty
- The full generated batch

It returns per-question booleans for nine checks. Any `false` ⇒ question is dropped. The Code node `Filter Valid Questions` enforces this strictly.

## 5. Duplicate detection — two passes

**Within batch**: normalised stem lookup using a `Set`.
**Against existing bank**: trigram Jaccard similarity. A threshold of 0.85 catches paraphrases without flagging legitimately distinct questions on the same sub-topic.

The bank is sampled — up to 20 most recent files from the target folder (`DUP_LOOKBACK`). Reading the entire bank does not scale and is not needed; near-duplicates almost always originate in a recent generation run.

Why trigram Jaccard and not embeddings?
- Zero infrastructure (no vector DB).
- Deterministic and fast at the scales we care about (≤ 200 stems per check).
- Embeddings can be added later by swapping the body of the `Deduplicate vs Bank` Code node — no surrounding changes.

## 6. Regeneration loop

`Need Regeneration?` checks two conditions:
- `unique_questions.length < number_of_questions`
- `attempt < MAX_REGEN_ATTEMPTS` (default 3)

If both true, `Prepare Regeneration Context` keeps the questions we already validated, asks for just the deficit, and feeds the union of "already kept" and "bank" stems back into the prompt under `existing_question_stems`. The generator avoids regenerating what we already have.

`attempt` is incremented inside `Build Prompt` so the bound is enforced regardless of how the loop is wired.

## 7. Folder creation

`Ensure Drive Folders` is a Code node that walks the path `Question Bank / Board / Class / Chapter / Type / Difficulty`, doing `findOrCreate` at each level via the Drive REST API with the OAuth credential.

It returns the leaf `target_folder_id` *and* the full trail (handy for logging). Idempotent: re-running for the same path is a single `files.list` call per level.

## 8. Final filename

```
{chapter}_{question_type}_{difficulty}_{batch_id}.json
```

The `batch_id` (base36 timestamp + 6 random chars) guarantees uniqueness without coordination. It is also stamped inside the JSON payload so downstream tools can correlate.

## 9. Error handling

Three layers:

1. **Code-node validation** — every parsing step throws a descriptive `Error` if the upstream LLM returns malformed JSON. n8n surfaces these as failed executions.
2. **`continueOnFail` on the Drive list call** — a fresh folder with no existing files must not break the pipeline; the lister returns an empty set and dedupe sees no bank.
3. **Workflow-level Error Trigger** (operator action): wire a separate `errorTrigger`-style workflow that catches failures and posts the `Normalize Input` envelope to Slack/email. The `Error Branch` node in this workflow is the local catcher used when called via sub-workflow.

We deliberately do not silently swallow LLM errors — a malformed generator response should fail loudly so the operator can inspect the prompt.

## 10. Cost shape

| Stage | Model | Approx tokens (per batch of 10) | Why this model |
|---|---|---|---|
| Structure Chapter Knowledge | Haiku 4.5 | ~5k in / ~2k out | Once per batch, deterministic, cheap |
| Generator | Sonnet 4.6 | ~3k in / ~4k out | Quality matters more than cost; runs ~1.5 × on average due to validator drops |
| Validator | Haiku 4.5 | ~4k in / ~1k out | Mechanical check, no creativity needed |

Switching models is a one-line change in three node parameters — they are *not* hard-coded in Code nodes.

## 11. What is intentionally not in this workflow

- **No retries on Anthropic 5xx** — n8n's built-in node retry handles transient errors; do not re-implement in Code.
- **No analytics writes** — `Log Run Summary` is the seam; pipe it to wherever fits your stack.
- **No PDF page-by-page splitting** — chapters fit in the context window of both the structurer and the generator. Add it the day a textbook chapter genuinely doesn't fit, not before.
