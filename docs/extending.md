# Extending the platform

Each extension is a local change — the workflow graph stays the same.

## Add a new chapter

1. `config/config.json#chapters.<class>` → append the chapter.
2. Open `On form submission` → add the chapter to the `Chapter Name` dropdown.

No prompt edits, no graph surgery.

## Add a new question type

E.g. `NUMERICAL`.

1. Open `On form submission`:
   - Add `NUMERICAL` to the `Question Type` dropdown.
   - Add three hidden fields: `PROMPT_NUMERICAL_EASY`, `PROMPT_NUMERICAL_MEDIUM`, `PROMPT_NUMERICAL_HARD` with their prompt text.
2. `config/config.json#supported.question_types` → append `NUMERICAL`.
3. Drive layout — automatic. `Ensure Drive Folders` walks the path from the envelope.

`Normalize Input` already builds `PROMPT_${typeKey}_${diff}` so the new key is picked up with no code change.

## Add a new board (ICSE)

1. `config/config.json#supported.boards` → append `ICSE`.
2. Open `On form submission` → add `ICSE` to the `Board` dropdown.
3. If you need board-specific phrasing:
   - Add 18 more hidden fields suffixed `_ICSE` (`PROMPT_MCQ_EASY_ICSE`, etc.).
   - In `Normalize Input`, change the lookup to prefer the board-suffixed key when present:
     ```js
     const promptKey = `PROMPT_${typeKey}_${diff}`;
     const boardKey = `${promptKey}_${f['Board']}`;
     const selectedPrompt = f[boardKey] || f[promptKey];
     ```

## Add a new subject

Subjects diverge more than boards. Clone the workflow and swap:
- The chapter dropdown.
- The 18 hidden prompts.
- The 3 system prompts (especially `SYSTEM_GENERATOR` and `SYSTEM_VALIDATOR`).

The PDF → structure → generate → validate → dedupe → save pipeline is subject-agnostic.

## Add Hindi

1. `config/config.json#feature_flags.enable_hindi = true`.
2. Open `On form submission` → add `Hindi` to the `Language` dropdown.
3. Add 18 hidden fields suffixed `_HI` with Hindi instructions and Devanagari output expectations. Optionally add `SYSTEM_GENERATOR_HI`.
4. In `Normalize Input`:
   ```js
   const langSuffix = (f['Language'] || 'English') === 'Hindi' ? '_HI' : '';
   const selectedPrompt = f[`PROMPT_${typeKey}_${diff}${langSuffix}`] || f[`PROMPT_${typeKey}_${diff}`];
   const system_generator = f[`SYSTEM_GENERATOR${langSuffix}`] || f['SYSTEM_GENERATOR'];
   ```

## JEE / NEET / HOTS / Competency mode

The lightest-touch option:

1. Open `On form submission` → add `Exam Mode` dropdown (`BOARDS` default, plus `JEE`, `NEET`, `HOTS`, `COMPETENCY`).
2. Add hidden fields with overlay rule blocks: `OVERLAY_JEE`, `OVERLAY_NEET`, `OVERLAY_HOTS`, `OVERLAY_COMPETENCY`.
3. In `Build Prompt`, append the relevant overlay to `selected_prompt`:
   ```js
   const overlay = ctx[`overlay_${(ctx.exam_mode || 'BOARDS').toLowerCase()}`] || '';
   const body = [ctx.selected_prompt + (overlay ? '\nOVERLAY:\n' + overlay : ''), ...].join('\n');
   ```

Heavier option: add a separate prompt set per exam mode, suffix `_JEE`, `_NEET`, etc.

## Topic-wise generation

The form already accepts one chapter PDF. To restrict to one sub-topic within the chapter:

1. Add a `Sub-topic` text field on the form (optional).
2. In `Build Prompt`, prepend `Restrict all questions to sub_topic: ${ctx.sub_topic}` when present.

## Multi-chapter generation

1. Make `Reference PDF` multi-file (`multipleFiles: true`).
2. Add `Chapter Names` text/csv field instead of single dropdown.
3. After `Normalize Input`, add a SplitOut node that emits one item per (PDF, chapter) pair.
4. The rest of the pipeline runs per pair — each lands in its own folder via `Ensure Drive Folders`.

## Swap LLM provider

Swap the three `n8n-nodes-base.anthropic` nodes for the provider's equivalent:
- `Structure Chapter Knowledge` (cheap, T=0)
- `AI: Generate Questions` (good, T=0.4)
- `AI: Validate Questions` (cheap, T=0)

Adjust the response-path expression in `Attach Knowledge Object`, `Parse Generation`, and `Filter Valid Questions` (currently `$json.content[0].text`).

## Swap dedupe to embeddings

Replace the body of `Deduplicate vs Bank` with a call to a vector store. Inputs (`validated_questions`, `existing_stems`) and outputs (`unique_questions`, `dropped_duplicates`) are unchanged — nothing else needs to know.
