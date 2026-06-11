# Extending the platform

The MockGenie / QuestDrive pattern keeps each extension to a small, local change.

## Add a new question type

E.g. `NUMERICAL`.

1. **Form trigger** → add 3 hidden fields: `EASY NUMERICAL`, `MEDIUM NUMERICAL`, `HARD NUMERICAL` with their prompts.
2. **`Generate 18 Question Prompts` (Code)** → in `const formats`, append `"NUMERICAL"`. Loop count becomes 21.
3. **`Loop Over 18 Items (Outer)`** → no change (it iterates over `levels`, count is still 3).
4. **Sub-workflow `Extract QuestionType`** → add a branch in the inference fallback if you ever skip explicit `questionType`.
5. **Sub-workflow `Parse LLM HTML`** → if the new type's output structure differs, add a parser branch (mirror the `parseWritten` / `parseMcqLike` / `parseCaseStudy` pattern).

No connections change. No Switch node to refactor.

## Add a new board

Just dropdown values:

1. `config/config.json#supported.boards` — append.
2. Form trigger → add to `Board` dropdown.

Prompts are board-agnostic in this build. If you want board-specific phrasing (e.g. ICSE markschemes), add an `Override Prompt by Board` Code node between `Pack Prompt + Drive ID` and `Call: QuestDrive Sub-Workflow` that swaps in the right text.

## Add a new subject (Physics, Biology)

Subjects diverge enough that the cleanest path is to **clone the main workflow** and rewrite the 18 hidden prompts. The sub-workflow stays as-is — it's subject-agnostic. Folder tree is identical.

## Add a new language (Hindi)

1. `config/config.json#supported.languages` — append `Hindi`.
2. **Form trigger** → add a visible `Language` dropdown.
3. **Hidden fields** → duplicate the 18 prompts as `EASY MCQ HI`, etc., with Hindi instructions and Devanagari output expectation.
4. **`Generate 18 Question Prompts`** → read the language and pick the matching field set.

## JEE / NEET mode

Add a visible `Exam Mode` dropdown (`BOARDS | JEE | NEET`) and three more prompt sets, or — simpler — append exam-specific extra rules at the end of every prompt via a Code node:

```js
const overlay = $json.examMode === 'JEE'
  ? '\nADDITIONAL RULES (JEE OVERLAY): multi-step numericals, IIT-style traps...'
  : '';
return [{ json: { ...$json, questionPrompt: $json.questionPrompt + overlay } }];
```

Insert it between `Pack Prompt + Drive ID` and `Call: QuestDrive Sub-Workflow`.

## Swap LLM provider

In the sub-workflow:
1. Replace `Qwen3-Instruct` with the provider's chat node (`anthropicChat`, `openAi`, etc.).
2. Bind the credential.
3. Done — the prompts are provider-neutral.

## Add a validator pass

In the sub-workflow, between `Parse LLM HTML` and `Convert to JSON File`:
1. Add an Agent node with a strict validator system prompt.
2. Add a Code node that drops `questionHtml` entries whose validator verdict was `valid:false`.

The shape that flows into `Convert to JSON File` is the same — no further changes.

## Add dedupe across runs

In the sub-workflow, before upload:
1. List the existing files in `$json.driveid` (Drive: list).
2. Download up to N recent ones.
3. Code node: trigram Jaccard ≥ 0.85 against `question_text`; drop matches.

## Multi-chapter / multi-concept

The form already accepts one PDF and one concept. For multi-concept generation:
1. Make `Reference Document` multi-file and `Concept Name / No` text-area accepting CSV.
2. Add a Code node after `On form submission` that splits into one item per (PDF, concept) pair.
3. The rest of the pipeline (folder creation, outer loop, sub-workflow) is unchanged — each pair lands in its own root folder.
