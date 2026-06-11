# Chemistry Question Generation Platform (CBSE)

A production-grade **single n8n workflow** that turns a chapter PDF into a validated, deduplicated, structured-JSON CBSE Chemistry question bank, stored in Drive under `Question Bank/CBSE/<Class>/<Chapter>/<Type>/<Difficulty>/`.

Built strictly to the platform spec (single workflow, 18 dynamic prompt templates, validator + dedupe + regen loop, structured JSON output). The MockGenie pattern contributed two ideas:

1. **All 18 prompts (plus the 3 system prompts) live as hidden form fields** — versioned with the workflow, editable in one place, never out of sync with code.
2. **Every node is wired end-to-end** — no orphan branches, no dangling error nodes.

```
Form (visible + 18 hidden prompts + 3 hidden system prompts)
  └─ Normalize Input            (resolves PROMPT_<TYPE>_<DIFF> from hidden fields)
      └─ Extract PDF Text
          └─ Clean PDF Text     (headers/footers/page-nums/OCR/dupes)
              └─ Structure Chapter Knowledge   (Haiku → JSON knowledge object)
                  └─ Attach Knowledge Object
                      └─ Ensure Drive Folders  (Question Bank/CBSE/.../<Diff>)
                          └─ Load Existing Bank Stems (up to 20 recent files)
                              └─ Build Prompt        ◀─────────┐
                                  └─ AI: Generate Questions    │
                                      └─ Parse Generation      │
                                          └─ AI: Validate      │
                                              └─ Filter Valid  │
                                                  └─ Deduplicate
                                                      └─ Need Regen?
                                                          ├─Yes─▶ Prepare Regen ─┘
                                                          └─No──▶ Finalize JSON
                                                                   └─ JSON → Binary
                                                                       └─ Upload to Drive
                                                                           └─ Log
```

## Files

| Path | Purpose |
|---|---|
| `workflow/chemistry-question-generation.json` | The single importable n8n workflow (21 nodes) |
| `config/config.json` | Supported enums + defaults + feature flags |
| `docs/architecture.md` | Node-by-node walkthrough and design choices |
| `docs/data-contracts.md` | Form, envelope, generator/validator, final JSON |
| `docs/extending.md` | Add boards / subjects / Hindi / JEE / NEET / HOTS / multi-chapter |
| `samples/sample-output.json` | A representative final payload |
| `IMPORT.md` | Step-by-step n8n import |

## Form (single submission = one (type × difficulty))

**Visible fields** (asked from user, per spec):

| Field | Type | Required | Notes |
|---|---|---|---|
| Board | dropdown | yes | `CBSE` |
| Class | dropdown | yes | `Class XI`, `Class XII` |
| Chapter Name | dropdown | yes | 19 NCERT chapters seeded; extend in form node |
| Source Type | dropdown | yes | `NCERT` / `Reference Book` / `Teacher Notes` / `PYQ Collection` / `Mixed` |
| Reference PDF | file | yes | `.pdf` |
| Question Type | dropdown | yes | `MCQ` / `VSA` / `SA` / `LA` / `AR` / `CASE_STUDY` |
| Difficulty | dropdown | yes | `EASY` / `MEDIUM` / `HARD` |
| Number of Questions | number | no | default `10` |
| Include Visual Questions | dropdown | no | `YES` / `NO` (default `NO`) |
| Language | dropdown | no | `English` (default) |
| Generate Explanation | dropdown | no | `YES` / `NO` (default `YES`) |

**Hidden fields** (set once, never asked again):

```
PROMPT_MCQ_EASY    PROMPT_MCQ_MEDIUM    PROMPT_MCQ_HARD
PROMPT_VSA_EASY    PROMPT_VSA_MEDIUM    PROMPT_VSA_HARD
PROMPT_SA_EASY     PROMPT_SA_MEDIUM     PROMPT_SA_HARD
PROMPT_LA_EASY     PROMPT_LA_MEDIUM     PROMPT_LA_HARD
PROMPT_AR_EASY     PROMPT_AR_MEDIUM     PROMPT_AR_HARD
PROMPT_CASE_STUDY_EASY  PROMPT_CASE_STUDY_MEDIUM  PROMPT_CASE_STUDY_HARD
SYSTEM_GENERATOR   SYSTEM_STRUCTURER    SYSTEM_VALIDATOR
```

`Normalize Input` reads `PROMPT_${question_type}_${difficulty}` from the form payload — that's the entire "prompt routing logic". One template add = one hidden field; no graph surgery.

## Output JSON (matches the spec verbatim)

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

The required spec keys (`board`, `class`, `chapter`, `source_type`, `question_type`, `difficulty`, `question_count`, `questions[]`) are exactly as specified. Additional keys (`language`, `include_visual_questions`, `generate_explanation`, `generated_at`, `batch_id`, `visual_type`, `bloom_level`) are additive, never replace required ones.

## Drive layout (matches the spec)

```
Question Bank/
  CBSE/
    Class XI/  ·  Class XII/
      <Chapter Name>/
        MCQ/   EASY/  MEDIUM/  HARD/
        VSA/   EASY/  MEDIUM/  HARD/
        SA/    EASY/  MEDIUM/  HARD/
        LA/    EASY/  MEDIUM/  HARD/
        AR/    EASY/  MEDIUM/  HARD/
        CASE_STUDY/  EASY/  MEDIUM/  HARD/
            <chapter>_<type>_<difficulty>_<batchId>.json
```

Folders are created idempotently — re-running for the same path is a single `files.list` per level.

## Why a single workflow

The spec is explicit: **"Do NOT create separate workflows."** Routing is achieved by:

- Hidden-field prompt store (18 prompts) read by `Normalize Input` via `PROMPT_${type}_${difficulty}`.
- One linear pipeline that handles any (type × difficulty); difficulty bands and type families are described inside each prompt template, so the same generator/validator/dedupe path serves all 18 combinations.
- Regeneration is a back-edge from `Need Regeneration?` (false branch flows forward; true branch flows back to `Build Prompt`) — bounded by `attempt < 3`.

## Scalability

| Future requirement | The change is |
|---|---|
| New chapter | Append to the `Chapter Name` dropdown |
| New board (e.g. ICSE) | Append to `Board` dropdown; if board-specific phrasing is needed, add a board-suffix on the prompt key (`PROMPT_MCQ_EASY_ICSE`) and tweak `Normalize Input` to prefer it when present |
| Hindi | Add `Hindi` to `Language` dropdown + 18 Hindi prompt variants + add `_HI` suffix logic in `Normalize Input` |
| JEE / NEET / HOTS / Competency | Add `Exam Mode` dropdown; add a Code node before `AI: Generate Questions` that appends an overlay rule list to `selected_prompt` based on mode |
| Multi-chapter | Make `Reference PDF` multi-file; split-out one item per PDF after `Normalize Input`; the rest of the pipeline runs per chapter; each lands in its own folder |

See `docs/extending.md` for the exact diff each requires.

## Import

See `IMPORT.md`.
