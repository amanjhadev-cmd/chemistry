# Chemistry Question Generation Platform

CBSE Chemistry mock-test generator built on top of the MockGenie / QuestDrive pattern:

- **One form** with all 18 prompts pre-loaded as hidden fields (3 difficulties × 6 question types).
- **One main workflow** creates the Drive folder tree and fans out per (level × type).
- **One sub-workflow** runs the LLM, parses HTML output into structured JSON, and uploads each question as its own file.

```
Form (visible fields + 18 hidden prompts)
  └─ Create Root Folder (under "Folder URL")
      └─ Generate 18 Question Prompts  ──▶  one item per level
          └─ Create Level Folder (EASY / MEDIUM / HARD)
              └─ Loop Over 18 Items (outer)
                  └─ Expand Level → 6 Types
                      └─ Create Type Folder (MCQ / VSA / SA / LA / AR / CASE_STUDY)
                          └─ Pack Prompt + Drive ID
                              └─ Call: QuestDrive Sub-Workflow ───┐
                                                                  │
                                            ┌─────────────────────┘
                                            ▼
                                    Sub-Workflow:
                                    Loop Over Items
                                      └─ Extract QuestionType
                                          └─ AI Agent (Qwen3 via OpenRouter)
                                              └─ Parse LLM HTML (one entry per Q)
                                                  └─ Convert to JSON File
                                                      └─ Upload to Drive
                                                          └─ Loop back

After all 18 items done:
  Aggregate ─▶ Send Completion Email
```

## Files

| Path | Purpose |
|---|---|
| `workflow/chemistry-question-generation.json` | Main workflow — form + folder tree + outer loop |
| `workflow/chemistry-question-generation-sub.json` | Sub-workflow — LLM + parser + uploader |
| `config/config.json` | Boards, classes, supported chapters, defaults, feature flags |
| `docs/architecture.md` | Node-by-node walkthrough |
| `docs/data-contracts.md` | Form fields, intermediate envelopes, final JSON per question |
| `docs/extending.md` | How to add boards, subjects, languages, JEE / NEET / HOTS |
| `samples/sample-output.json` | Representative final per-question JSON file |

## Form fields

**Visible (asked from the user):**

| Field | Type | Notes |
|---|---|---|
| Board | dropdown | CBSE / ICSE / ISC / MH |
| Class | dropdown | CLASS IX / X / XI / XII |
| Subject | dropdown | Chemistry (locked) |
| Chapter Name | text | |
| Chapter No (e.g. 1,2,3) | number | |
| Concept Name | text | |
| Concept No | number | |
| Reference Document | file | `.pdf` |
| Folder URL | text | Google Drive parent folder URL |

**Hidden (the 18 prompts — set once, never asked again):**

```
EASY MCQ          EASY VSA          EASY SA          EASY LA          EASY A&R          EASY CASE_STUDY
MEDIUM MCQ        MEDIUM VSA        MEDIUM SA        MEDIUM LA        MEDIUM A&R        MEDIUM CASE_STUDY
HARD MCQ          HARD VSA          HARD SA          HARD LA          HARD A&R          HARD CASE_STUDY
```

Each hidden field's `fieldValue` is the full prompt for that (level × type). They are read in the `Generate 18 Question Prompts` Code node, reshaped into `[{level, items:[{type, prompt}, ...]}]`, then fanned out.

## Drive layout

The main workflow appends:

```
<your-Folder-URL>/
  CBSE-CLASS XII-Chemistry-Ch-1-Solutions-Co-2-Raoult's Law/
    ├── EASY/
    │   ├── MCQ/        Q1.json … Q25.json
    │   ├── VSA/        Q1.json … Q25.json
    │   ├── SA/
    │   ├── LA/
    │   ├── AR/
    │   └── CASE_STUDY/
    ├── MEDIUM/  …same six type folders
    └── HARD/    …same six type folders
```

Note: the type folder for `A&R` is named `AR` on disk (Drive doesn't love special chars in folder names — the Code node maps `A&R → AR` at folder creation, but `question_type: "A&R"` is preserved inside the JSON).

## Why a sub-workflow

The reference pattern (and this build) splits the heavy lifting because:
- The outer loop is **18 iterations**; each iteration produces **25 questions**. Keeping both loops in the same workflow makes execution graphs unreadable and aborts halfway lose the whole batch.
- Splitting lets the sub-workflow be **retried independently** per (level × type) without re-creating folders or re-prompting Drive.
- The sub-workflow is the natural seam for swapping LLM providers — change one node, not the whole tree.

## Output JSON shape (per question)

```json
{
  "Metadata": {
    "board": "CBSE",
    "class": "CLASS XII",
    "subject": "Chemistry",
    "chapter_no": 1,
    "chapter_name": "Solutions",
    "concept_no": 2,
    "concept_name": "Raoult's Law",
    "question_level": "MEDIUM",
    "question_type": "MCQ"
  },
  "questionHtml": {
    "question_no": "Q1",
    "question_text": "<p>...</p>",
    "options": { "A": "...", "B": "...", "C": "...", "D": "..." },
    "final_answer": {
      "correct_option": "B,D",
      "model_answer":   null
    }
  }
}
```

For VSA / SA / LA, `options` is `{}` and `final_answer.model_answer` carries the text answer. For CASE_STUDY, the parser keeps the full HTML cluster in `questionHtml.question_text` plus the original block in `final_answer.model_answer`.

## See `IMPORT.md` for the step-by-step n8n import flow.
