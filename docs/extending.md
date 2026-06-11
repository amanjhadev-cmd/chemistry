# Extending the platform

Each extension below is intentionally a small, localised change — the workflow graph stays the same.

## Add a new chapter

1. `config/config.json#chapters.<class>` → append the chapter title.
2. Form trigger → add the chapter to the `Chapter Name` dropdown values.

No workflow surgery, no prompt changes.

## Add a new question type

E.g. `COMPETENCY`.

1. `config/config.json#supported.question_types` → append `COMPETENCY`.
2. Form trigger → add `COMPETENCY` to the `Question Type` dropdown.
3. `prompts/templates.json` → add three keys:
   - `COMPETENCY_EASY`
   - `COMPETENCY_MEDIUM`
   - `COMPETENCY_HARD`
4. Drive layout → the `Ensure Drive Folders` node walks the path from the envelope; the new folder will be created on first run automatically.

`prompt_key = `${question_type}_${difficulty}`` already includes the new value — no Code edits.

## Add a new board

E.g. `ICSE`.

1. `config/config.json#supported.boards` → append `ICSE`.
2. Form trigger → add to `Board` dropdown.
3. `prompts/templates.json` — *optional*: add ICSE-style overrides. The cleanest way is to keep CBSE templates as the default and add an `_overrides.ICSE` block looked up by `Build Prompt`:

   ```js
   const base = templates[ctx.prompt_key];
   const override = templates._overrides?.[ctx.board]?.[ctx.prompt_key];
   const entry = { ...base, ...(override || {}) };
   ```

4. The structurer is board-agnostic — no change.

## Add a new subject (Physics, Biology)

Subjects diverge much more than boards do. The right move is to clone the workflow and swap:

- `prompts/system-base.txt` — subject-specific authoring rules.
- `prompts/templates.json` — subject-specific instructions per (type × difficulty).
- `config/config.json#chapters` — subject's syllabus.
- Form trigger title and chapter dropdown.

The pipeline (PDF → clean → structure → route → generate → validate → dedupe → save) is unchanged.

## Add Hindi (or any other language)

1. `config/config.json#feature_flags.enable_hindi` → `true`.
2. `config/config.json#supported.languages` → append `Hindi`.
3. Form trigger → add `Hindi` to the `Language` dropdown.
4. `prompts/system-base.hi.txt` → Hindi translation of the system prompt, plus an instruction to emit Devanagari output.
5. `Build Prompt` → already injects `language` into the user message; extend it to switch system prompt by language:

   ```js
   const sys = ctx.language === 'Hindi' ? $vars.GENERATOR_SYSTEM_PROMPT_HI : $vars.GENERATOR_SYSTEM_PROMPT;
   return [{ json: { ...ctx, prompt_user_message: body, system_prompt: sys, attempt: ... } }];
   ```

   And on the AI nodes, change the `system` expression to `={{ $json.system_prompt }}`.

## JEE / NEET mode

These exams demand harder distractors, longer numerical chains, and out-of-NCERT-but-syllabus content.

1. Form trigger → add `Exam Mode` dropdown with `BOARDS` (default), `JEE`, `NEET`.
2. `prompts/templates.json` → add an `_exam_overlays` block:

   ```json
   {
     "JEE": { "MCQ_HARD": { "extra_rules": ["At least 2 multi-step numericals", "Use IIT-style distractor patterns"] } },
     "NEET": { "MCQ_HARD": { "extra_rules": ["Single-correct, fact-dense", "Stay within NEET syllabus"] } }
   }
   ```

3. `Build Prompt` — append `extra_rules` to the rules list when `exam_mode !== 'BOARDS'`.
4. `config/config.json#feature_flags.enable_jee_mode` / `enable_neet_mode`.

## HOTS / competency-based

Treat them as either a new question_type (recommended — clean Drive separation) or as a difficulty tier above `HARD`. The former is the smaller change.

## Multi-chapter / topic-wise

1. Form trigger → make `Reference PDF` multi-file and add `Topics` (free text).
2. After `Extract PDF Text`, add a Split-out / loop so each PDF gets cleaned and structured.
3. After `Attach Knowledge Object`, add a merge that combines the per-chapter knowledge objects.
4. The rest of the pipeline is unchanged.

## Swap LLM provider

Change `modelId` and the credential on the three AI nodes (`Structure Chapter Knowledge`, `AI: Generate Questions`, `AI: Validate Questions`). The prompts are provider-neutral.

## Swap dedupe to embeddings

Replace the body of `Deduplicate vs Bank` with embedding lookups against a vector store. Inputs and outputs (`unique_questions`, `dropped_duplicates`) stay the same, so nothing downstream changes.
