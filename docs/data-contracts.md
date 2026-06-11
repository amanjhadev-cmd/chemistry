# Phase 1 — Data contracts

## 1. Form submission

| Field | Type | Required | Allowed values |
|---|---|---|---|
| Board | dropdown | yes | `CBSE` |
| Class | dropdown | yes | `Class XI`, `Class XII` |
| Chapter Name | dropdown | yes | see `config/config.json#chapters` |
| Source Type | dropdown | yes | `NCERT` / `Reference Book` / `Teacher Notes` / `PYQ Collection` / `Mixed` |
| Reference PDF | file | yes | `.pdf` |
| Question Type | dropdown | yes | `MCQ` / `VSA` / `SA` / `LA` / `AR` / `CASE_STUDY` *(stored for Phase 2)* |
| Difficulty | dropdown | yes | `EASY` / `MEDIUM` / `HARD` *(stored for Phase 2)* |
| Number of Questions | number | no | integer ≥ 1, default `10` *(stored for Phase 2)* |
| Include Visual Questions | dropdown | no | `YES` / `NO`, default `NO` *(stored for Phase 2)* |
| Language | dropdown | no | `English`, default `English` *(stored for Phase 2)* |
| Generate Explanation | dropdown | no | `YES` / `NO`, default `YES` *(stored for Phase 2)* |

**Hidden field:**
- `SYSTEM_STRUCTURER` — system prompt for the structurer LLM, set once on the form node.

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
  "chapter_code": "SOLUTIONS",
  "batch_id": "lz9k2r-7f3a1c",
  "started_at": "2026-06-11T09:00:00Z",
  "knowledge_file_name": "SOLUTIONS_KNOWLEDGE.json",
  "system_structurer": "You are a chemistry chapter structurer..."
}
```

After `Clean PDF Text` additionally:
```json
{
  "pdf_metadata": { "num_pages": 32, "info": {...}, "version": "1.7", "raw_chars": 84210 },
  "cleaned_text": "<full cleaned chapter>"
}
```

After `Parse Knowledge JSON`:
```json
{ "structured_knowledge": { /* per the structurer schema */ } }
```

After `Validate Knowledge Schema`:
```json
{ "validation": { "ok": true, "total_entries": 87 } }
```

After `Ensure Drive Folders`:
```json
{
  "drive_folder_trail": [
    { "name": "Question Bank", "id": "..." },
    { "name": "CBSE",          "id": "..." },
    { "name": "Class XII",     "id": "..." },
    { "name": "Solutions",     "id": "..." },
    { "name": "Knowledge Base","id": "..." }
  ],
  "target_folder_id": "<leaf folder id>"
}
```

## 3. Structurer LLM input

System prompt: contents of the hidden `SYSTEM_STRUCTURER` form field.

User message:
```
Board: CBSE
Class: Class XII
Chapter: Solutions
Source type: NCERT

CLEANED CHAPTER TEXT (use ONLY this content):
<cleaned_text>
```

## 4. Structurer LLM output (parsed into `structured_knowledge`)

```json
{
  "chapter_title": "Solutions",
  "topics": ["Types of Solutions", "Concentration", "Raoult's Law", "Colligative Properties", "Abnormal Molar Masses"],
  "subtopics": [{ "topic": "Concentration", "name": "Molarity", "summary": "..." }],
  "definitions": [{ "term": "molality", "definition": "...", "topic": "Concentration" }],
  "formulae": [{ "name": "Raoult", "expression": "P = x_A·P°_A + x_B·P°_B", "variables": "...", "topic": "Raoult's Law" }],
  "laws": [{ "name": "Henry's Law", "statement": "...", "topic": "..." }],
  "principles": [{ "name": "...", "statement": "...", "topic": "..." }],
  "reactions": [{ "name": "...", "equation": "...", "conditions": "...", "topic": "..." }],
  "examples": [{ "title": "...", "summary": "...", "working": "...", "topic": "..." }],
  "tables": [{ "label": "Table 1.1", "summary": "...", "rows": ["..."], "topic": "..." }],
  "graph_references": [{ "label": "Fig 1.6", "describes": "...", "topic": "..." }],
  "diagram_references": [{ "label": "Fig 1.2", "describes": "...", "topic": "..." }],
  "important_facts": [{ "fact": "...", "topic": "..." }],
  "exceptions": [{ "rule": "...", "exception": "...", "topic": "..." }],
  "ncert_activities": [{ "label": "Activity 1.1", "summary": "...", "topic": "..." }]
}
```

Empty arrays are legal — but the keys must all exist.

## 5. Final JSON uploaded to Drive

Filename: `<CHAPTER_CODE>_KNOWLEDGE.json` (e.g. `SOLUTIONS_KNOWLEDGE.json`).

```json
{
  "board": "CBSE",
  "class": "Class XII",
  "chapter": "Solutions",
  "source_type": "NCERT",

  "pdf_metadata": {...},

  "topics": [...],
  "subtopics": [...],
  "definitions": [...],
  "formulae": [...],
  "laws": [...],
  "principles": [...],
  "reactions": [...],
  "examples": [...],
  "tables": [...],
  "graph_references": [...],
  "diagram_references": [...],
  "important_facts": [...],
  "exceptions": [...],
  "ncert_activities": [...],

  "clean_text": "<full cleaned chapter>",

  "form_inputs": {
    "board": "CBSE",
    "class": "Class XII",
    "chapter": "Solutions",
    "source_type": "NCERT",
    "question_type": "MCQ",
    "difficulty": "MEDIUM",
    "number_of_questions": 10,
    "include_visual_questions": false,
    "language": "English",
    "generate_explanation": true
  },

  "meta": {
    "phase": 1,
    "schema_version": "1.0.0",
    "chapter_code": "SOLUTIONS",
    "batch_id": "lz9k2r-7f3a1c",
    "generated_at": "2026-06-11T09:01:24Z",
    "total_structured_entries": 87
  }
}
```

All required spec keys (`board`, `class`, `chapter`, `source_type`, `pdf_metadata`, `topics`, `subtopics`, `definitions`, `formulae`, `laws`, `principles`, `reactions`, `examples`, `tables`, `graph_references`, `diagram_references`, `important_facts`, `exceptions`, `clean_text`) are present at the top level. `form_inputs` and `meta` are additive and Phase-2-facing.

## 6. Drive path & filename

```
Question Bank/CBSE/<Class>/<Chapter Name>/Knowledge Base/<CHAPTER_CODE>_KNOWLEDGE.json
```

- `<Chapter Name>` = exact dropdown value (spaces, apostrophes preserved).
- `<CHAPTER_CODE>` = uppercase `[A-Z0-9_]` derived from `Chapter Name`, max 24 chars (e.g. `SOLUTIONS`, `STRUCTURE_OF_ATOM`, `THE_D_AND_F_BLOCK_ELEME`).
- The folder tree is created lazily — missing levels are inserted on the first run, subsequent runs reuse them.

## 7. Audit record from `Log Phase 1 Summary`

```json
{
  "status": "OK",
  "phase": 1,
  "batch_id": "lz9k2r-7f3a1c",
  "chapter": "Solutions",
  "chapter_code": "SOLUTIONS",
  "saved_file": "SOLUTIONS_KNOWLEDGE.json",
  "drive_file_id": "1aBc...",
  "drive_web_view_link": "https://drive.google.com/file/d/.../view",
  "drive_folder_trail": [{"name":"Question Bank","id":"..."}, ...],
  "pdf_pages": 32,
  "total_structured_entries": 87,
  "finished_at": "2026-06-11T09:01:25Z"
}
```

This is the seam to pipe into Slack / BigQuery / a status board.
