# Chemistry Question Generation Platform

A single, production-grade n8n workflow that turns a chapter PDF into a validated, deduplicated CBSE Chemistry question bank and stores it in a structured Google Drive tree.

```
PDF + form input  ──▶  Structured chapter knowledge  ──▶  Prompt-routed LLM generation
                                                              │
                                          Validator LLM ◀─────┘
                                                  │
                              Trigram-Jaccard dedupe vs existing bank
                                                  │
                                  Loop until quota met (≤ N attempts)
                                                  │
                       Google Drive: Board / Class / Chapter / Type / Difficulty
```

## Repository layout

| Path | Purpose |
|---|---|
| `workflow/chemistry-question-generation.json` | The importable n8n workflow (single workflow, 22 nodes) |
| `prompts/system-base.txt` | Shared generator system prompt |
| `prompts/structurer.txt` | Prompt that turns raw PDF text into a JSON knowledge object |
| `prompts/validator.txt` | Second-pass validation prompt |
| `prompts/templates.json` | 18 instruction templates keyed `<TYPE>_<DIFFICULTY>` |
| `config/config.json` | Boards, classes, chapters, models, thresholds, feature flags |
| `docs/architecture.md` | Detailed node-by-node walkthrough |
| `docs/data-contracts.md` | Input form schema, intermediate envelopes, final JSON |
| `docs/extending.md` | How to add boards / subjects / languages / JEE / NEET / HOTS |
| `samples/sample-output.json` | A representative final payload |

## Quick start

1. Import `workflow/chemistry-question-generation.json` into your n8n instance.
2. Create the two credentials referenced at the bottom of the workflow JSON:
   - `anthropicApi`
   - `googleDriveOAuth2Api` (scope `drive.file` is sufficient)
3. In **Settings → Variables**, paste the contents of the four prompt files plus the three scalar settings (see `_environment_variables_required` at the bottom of the workflow JSON).
4. Activate the workflow. Open the form URL and submit a chapter PDF.

The generated JSON lands at
`Question Bank/CBSE/<Class>/<Chapter>/<Type>/<Difficulty>/<chapter>_<type>_<difficulty>_<batchId>.json`.

## Why one workflow, not eighteen

Eighteen `(type × difficulty)` combinations would mean 18 near-identical workflows, 18 places to fix every bug, and 18 places to update when a new question type is added. Instead:

- The form normalises inputs into a single envelope.
- `prompt_key = "<TYPE>_<DIFFICULTY>"` selects a template from a JSON dictionary inside the `Build Prompt` Code node.
- New combinations are added by extending `prompts/templates.json` — no node changes.

The same principle extends to boards, subjects, and languages (see `docs/extending.md`).

## Pipeline at a glance

| # | Node | Role |
|---|---|---|
| 1 | Form: User Input | Collects 11 fields, accepts PDF upload |
| 2 | Normalize Input | Coerces types, generates `batch_id`, `chapter_code`, `prompt_key` |
| 3 | Extract PDF Text | `extractFromFile` over the uploaded binary |
| 4 | Clean PDF Text | Strips page numbers, repeated headers/footers, OCR artefacts |
| 5 | Structure Chapter Knowledge | Haiku call → JSON `{summary, sub_topics, definitions, formulae, reactions, ...}` |
| 6 | Attach Knowledge Object | Parses, attaches to envelope |
| 7 | Ensure Drive Folders | Idempotently creates `Question Bank/CBSE/<Class>/<Chapter>/<Type>/<Difficulty>` |
| 8 | Load Existing Question Bank | Lists files in the target folder |
| 9 | Collect Existing Stems | Downloads up to 20 recent files, extracts question stems |
| 10 | Build Prompt | Selects 1 of 18 templates, interpolates placeholders |
| 11 | AI: Generate Questions | Sonnet, temperature 0.4, JSON output |
| 12 | Parse Generation | Strict JSON parse |
| 13 | AI: Validate Questions | Haiku, temperature 0, returns per-question verdict |
| 14 | Filter Valid Questions | Drops anything not marked `valid: true` |
| 15 | Deduplicate vs Bank | Trigram Jaccard ≥ 0.85 against existing stems and within batch |
| 16 | Need Regeneration? | `unique < requested AND attempts < MAX` → loop |
| 17 | Prepare Regeneration Context | Carries forward kept questions, asks only for the deficit |
| 18 | Finalize JSON | Re-IDs sequentially, produces the schema in the spec |
| 19 | JSON → Binary | Wraps payload as a binary file for upload |
| 20 | Upload to Google Drive | Lands the file inside the target folder |
| 21 | Log Run Summary | Final telemetry item |
| 22 | Error Branch | Receives `workflow.errorTrigger` style failures (see `docs/architecture.md`) |

## Output schema (matches the spec)

```json
{
  "board": "CBSE",
  "class": "Class XII",
  "chapter": "Solutions",
  "source_type": "NCERT",
  "question_type": "MCQ",
  "difficulty": "MEDIUM",
  "question_count": 10,
  "questions": [
    {
      "question_id": "SOLUTIONS_MCQ_M_001",
      "question": "...",
      "options": { "A": "...", "B": "...", "C": "...", "D": "..." },
      "answer": "B",
      "explanation": "...",
      "difficulty": "MEDIUM",
      "source_topic": "Raoult's Law",
      "visual_required": false
    }
  ]
}
```

A full example is in `samples/sample-output.json`.

## Scalability

| Future requirement | How it lands |
|---|---|
| New board (ICSE, IB) | Append to `config.json` and to the Board dropdown; no node changes |
| New subject (Physics, Biology) | Clone the workflow, swap `system-base.txt` and `templates.json` — the structural pipeline is subject-agnostic |
| Hindi | Flip `feature_flags.enable_hindi`, add Hindi system prompt variant keyed by `language`, add `Hindi` to the dropdown |
| JEE / NEET mode | Add `exam_mode` field; `Build Prompt` selects an exam-overlay template that augments the difficulty rules |
| HOTS / competency-based | Add a new question_type value `COMPETENCY` and three templates `COMPETENCY_EASY/MEDIUM/HARD` |
| Multi-chapter / topic-wise | Form upload becomes multi-file; `Structure Chapter Knowledge` runs per file and merges; rest of the pipeline is unchanged |

See `docs/extending.md` for the exact diff each of these requires.
