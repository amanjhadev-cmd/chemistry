# Chemistry Question Generation Platform — Phase 1

**Phase 1 = Knowledge Extraction only.** No question generation, no validators, no question-side dedupe.

This phase turns a user-uploaded chemistry PDF into a structured `CHAPTER_KNOWLEDGE.json` saved at
`Question Bank/CBSE/<Class>/<Chapter>/Knowledge Base/<CHAPTER_CODE>_KNOWLEDGE.json` on Google Drive.

Later phases (2: prompt routing, 3: generation, 4: validation + dedupe, 5: per-(type × difficulty) bank store) will read this JSON as their input.

## Pipeline

```
Form Submission
  └─ Normalize Input
      └─ Extract PDF Text & Metadata
          └─ Clean PDF Text
              └─ AI: Structure Chapter Knowledge   (Haiku, T=0)
                  └─ Parse Knowledge JSON
                      └─ Validate Knowledge Schema
                          └─ Compose Final JSON
                              └─ Ensure Drive Folders
                                  └─ JSON → Binary
                                      └─ Upload Knowledge JSON to Drive
                                          └─ Log Phase 1 Summary
```

12 nodes, all linearly wired. Every node has one inbound and one outbound (except the form trigger and the log).

## Files

| Path | Purpose |
|---|---|
| `workflow/phase-1-knowledge-extraction.json` | The Phase 1 importable n8n workflow |
| `config/config.json` | Boards, classes, chapters, defaults — read by docs only, not by the workflow |
| `docs/phase-1-architecture.md` | Node-by-node spec (name, type, config, IO schema, errors) |
| `docs/data-contracts.md` | Form fields, intermediate envelope, output JSON |
| `docs/extending.md` | How to extend chapters / boards / languages later |
| `samples/sample-knowledge.json` | A representative `SOLUTIONS_KNOWLEDGE.json` |
| `IMPORT.md` | Step-by-step n8n import |

## Output JSON shape (this is the contract Phase 2 will read)

```json
{
  "board": "CBSE",
  "class": "Class XII",
  "chapter": "Solutions",
  "source_type": "NCERT",
  "pdf_metadata": { "num_pages": 32, "info": { /* ... */ }, "version": "1.7", "raw_chars": 84210 },
  "topics": ["Types of Solutions", "Concentration", "Raoult's Law", ...],
  "subtopics": [ { "topic": "Concentration", "name": "Molarity", "summary": "..." } ],
  "definitions": [ { "term": "molality", "definition": "...", "topic": "Concentration" } ],
  "formulae": [ { "name": "Raoult", "expression": "P = x_A·P°_A + x_B·P°_B", "variables": "...", "topic": "Raoult's Law" } ],
  "laws": [ { "name": "Henry's Law", "statement": "...", "topic": "..." } ],
  "principles": [ { "name": "...", "statement": "...", "topic": "..." } ],
  "reactions": [ { "name": "...", "equation": "...", "conditions": "...", "topic": "..." } ],
  "examples": [ { "title": "...", "summary": "...", "working": "...", "topic": "..." } ],
  "tables": [ { "label": "Table 1.1", "summary": "...", "rows": ["..."], "topic": "..." } ],
  "graph_references": [ { "label": "Fig 1.6", "describes": "...", "topic": "..." } ],
  "diagram_references": [ { "label": "Fig 1.2", "describes": "...", "topic": "..." } ],
  "important_facts": [ { "fact": "...", "topic": "..." } ],
  "exceptions": [ { "rule": "...", "exception": "...", "topic": "..." } ],
  "ncert_activities": [ { "label": "Activity 1.1", "summary": "...", "topic": "..." } ],
  "clean_text": "<full cleaned chapter text>",
  "form_inputs": {
    "board": "CBSE", "class": "Class XII", "chapter": "Solutions", "source_type": "NCERT",
    "question_type": "MCQ", "difficulty": "MEDIUM",
    "number_of_questions": 10, "include_visual_questions": false,
    "language": "English", "generate_explanation": true
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

Every required spec key is present. `form_inputs` and `meta` are additive so Phase 2 has all the context it needs without re-running the form.

## Drive layout

```
Question Bank/
  CBSE/
    Class XI/  ·  Class XII/
      <Chapter Name>/
        Knowledge Base/
          <CHAPTER_CODE>_KNOWLEDGE.json     ← Phase 1 output
        MCQ/     EASY/  MEDIUM/  HARD/      ← created by Phase 2+, not here
        VSA/     ...
        ...
```

Folders are created idempotently — re-running for the same chapter overwrites *only* the JSON file at the leaf (Drive will create a new revision with the same name).

## Import

See `IMPORT.md`. Two credentials (Anthropic + Google Drive OAuth2), one activate toggle.
