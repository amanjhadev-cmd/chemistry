# Data contracts

This file is the source of truth for what each interface accepts and emits.

## 1. Form submission

Field labels are the exact strings the form trigger emits.

| Field | Type | Required | Allowed values / format |
|---|---|---|---|
| Board | dropdown | yes | `CBSE` |
| Class | dropdown | yes | `Class XI`, `Class XII` |
| Chapter Name | dropdown | yes | see `config/config.json#chapters` |
| Source Type | dropdown | yes | `NCERT`, `Reference Book`, `Teacher Notes`, `PYQ Collection`, `Mixed` |
| Reference PDF | file | yes | `.pdf`, single file |
| Question Type | dropdown | yes | `MCQ`, `VSA`, `SA`, `LA`, `AR`, `CASE_STUDY` |
| Difficulty | dropdown | yes | `EASY`, `MEDIUM`, `HARD` |
| Number of Questions | number | no | integer ≥ 1, default `10` |
| Include Visual Questions | dropdown | no | `YES`, `NO`, default `NO` |
| Language | dropdown | no | `English`, default `English` |
| Generate Explanation | dropdown | no | `YES`, `NO`, default `YES` |

## 2. Internal envelope after `Normalize Input`

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
  "started_at": "2026-06-11T09:00:00Z"
}
```

## 3. `chapter_knowledge` (output of `Structure Chapter Knowledge`)

See `prompts/structurer.txt` for the canonical schema. All array fields are required; an empty array `[]` is legal.

## 4. Generator output

```json
{
  "questions": [
    {
      "question_id": "SOLUTIONS_MCQ_M_001",
      "question": "...",
      "options": { "A": "...", "B": "...", "C": "...", "D": "..." },
      "answer": "B",
      "explanation": "...",
      "difficulty": "MEDIUM",
      "source_topic": "Raoult's Law",
      "visual_required": false,
      "visual_type": null,
      "bloom_level": "Apply"
    }
  ]
}
```

For `VSA`, `SA`, `LA`: `options` is `null`, `answer` is the model answer text.
For `AR`: `options` is the standard 4-option map (A-D), `answer` is one of `A|B|C|D`.
For `CASE_STUDY`: each entry has a `passage` and a `sub_questions[]` array; each sub-question follows MCQ / VSA / SA shape.

## 5. Validator output

```json
{
  "results": [
    {
      "question_id": "SOLUTIONS_MCQ_M_001",
      "valid": true,
      "checks": {
        "scientifically_correct": true,
        "answer_matches_question": true,
        "options_well_formed": true,
        "ncert_aligned": true,
        "difficulty_aligned": true,
        "grammar_ok": true,
        "spelling_ok": true,
        "complete": true,
        "explanation_correct": true
      },
      "issues": [],
      "fix_hint": null
    }
  ]
}
```

A question is kept ⇔ `valid === true`. Anything else (including `undefined`) is dropped and the reason is captured in `rejected[]`.

## 6. Final payload (uploaded to Drive)

Matches the schema in the spec exactly:

```json
{
  "board": "CBSE",
  "class": "Class XII",
  "chapter": "Solutions",
  "source_type": "NCERT",
  "question_type": "MCQ",
  "difficulty": "MEDIUM",
  "language": "English",
  "include_visual_questions": false,
  "generate_explanation": true,
  "question_count": 10,
  "generated_at": "2026-06-11T09:01:24Z",
  "batch_id": "lz9k2r-7f3a1c",
  "questions": [ /* see §4 */ ]
}
```

Note the schema-superset: `language`, `include_visual_questions`, `generate_explanation`, `generated_at`, and `batch_id` are added on top of the spec for downstream traceability without breaking the spec's required keys.

## 7. Drive path

```
Question Bank /
  CBSE /
    <Class XI | Class XII> /
      <Chapter Name> /
        <MCQ | VSA | SA | LA | AR | CASE_STUDY> /
          <EASY | MEDIUM | HARD> /
            <chapter>_<question_type>_<difficulty>_<batch_id>.json
```

Folder names are exact strings — spaces preserved (e.g. `Class XII`, `Solutions`). The filename is sanitised: spaces and punctuation in the chapter become `_`.
