# Data contracts

## 1. Form submission

### Visible fields

| Field | Type | Required | Allowed values |
|---|---|---|---|
| Board | dropdown | yes | `CBSE` |
| Class | dropdown | yes | `Class XI`, `Class XII` |
| Chapter Name | dropdown | yes | see `config/config.json#chapters` |
| Source Type | dropdown | yes | `NCERT` / `Reference Book` / `Teacher Notes` / `PYQ Collection` / `Mixed` |
| Reference PDF | file | yes | `.pdf` |
| Question Type | dropdown | yes | `MCQ` / `VSA` / `SA` / `LA` / `AR` / `CASE_STUDY` |
| Difficulty | dropdown | yes | `EASY` / `MEDIUM` / `HARD` |
| Number of Questions | number | no | integer ≥ 1, default `10` |
| Include Visual Questions | dropdown | no | `YES` / `NO`, default `NO` |
| Language | dropdown | no | `English`, default `English` |
| Generate Explanation | dropdown | no | `YES` / `NO`, default `YES` |

### Hidden fields (set once)

```
PROMPT_MCQ_EASY  PROMPT_MCQ_MEDIUM  PROMPT_MCQ_HARD
PROMPT_VSA_EASY  PROMPT_VSA_MEDIUM  PROMPT_VSA_HARD
PROMPT_SA_EASY   PROMPT_SA_MEDIUM   PROMPT_SA_HARD
PROMPT_LA_EASY   PROMPT_LA_MEDIUM   PROMPT_LA_HARD
PROMPT_AR_EASY   PROMPT_AR_MEDIUM   PROMPT_AR_HARD
PROMPT_CASE_STUDY_EASY  PROMPT_CASE_STUDY_MEDIUM  PROMPT_CASE_STUDY_HARD
SYSTEM_GENERATOR  SYSTEM_STRUCTURER  SYSTEM_VALIDATOR
```

## 2. Envelope after `Normalize Input`

```json
{
  "board": "CBSE",
  "class_name": "Class XII",
  "chapter": "Solutions",
  "source_type": "NCERT",
  "question_type": "MCQ",
  "question_type_folder": "MCQ",
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
  "selected_prompt": "TYPE=MCQ DIFFICULTY=MEDIUM | ...",
  "system_generator": "You are an expert CBSE Chemistry...",
  "system_structurer": "You are a chemistry chapter structurer...",
  "system_validator": "You are a strict CBSE Chemistry validator...",
  "attempt": 0
}
```

`question_type_folder` differs from `question_type` only for AR (folder `AR`, JSON `A&R`).

## 3. `chapter_knowledge` (output of Structurer)

```json
{
  "chapter": "Solutions",
  "class": "Class XII",
  "summary": "...",
  "sub_topics": [ { "name": "Raoult's Law", "key_ideas": ["...", "..."] } ],
  "definitions": [ { "term": "molality", "definition": "..." } ],
  "formulae": [ { "name": "Raoult", "expression": "P = x_A P°_A + x_B P°_B", "variables": "..." } ],
  "reactions": [ { "name": "...", "equation": "...", "conditions": "..." } ],
  "numerical_data": [ { "label": "Kb water", "value": "0.52", "units": "K kg mol⁻¹" } ],
  "examples": [ { "title": "...", "summary": "..." } ],
  "ncert_activities": [ "..." ],
  "diagram_refs": [ { "label": "Fig 2.3", "describes": "..." } ],
  "tables": [ { "label": "Table 1.1", "summary": "..." } ]
}
```

Empty arrays are legal.

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

- `options` is `null` for VSA / SA / LA.
- For `AR`, `options` is the 4 fixed labels and `answer ∈ {A,B,C,D}`.
- For `CASE_STUDY`, each `questions[]` entry is `{ passage, sub_questions: [ { question, options|null, answer, explanation|null, visual_required, visual_type|null } ] }`.

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

A question is kept ⇔ `valid === true`.

## 6. Final payload (matches the spec)

See `samples/sample-output.json`. Required spec keys: `board, class, chapter, source_type, question_type, difficulty, question_count, questions[]`. Additional keys are non-breaking.

## 7. Drive path & filename

```
Question Bank/CBSE/<Class>/<Chapter>/<Type>/<Difficulty>/<chapter>_<type_folder>_<difficulty>_<batchId>.json
```

- `<Chapter>` is the exact dropdown value (spaces, apostrophes preserved).
- `<Type>` is `MCQ` / `VSA` / `SA` / `LA` / `AR` / `CASE_STUDY` (note `AR`, not `A&R`).
- `<batchId>` is base36 timestamp + 6 random chars, unique without coordination.
