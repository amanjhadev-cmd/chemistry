# Question Schema v2 (output JSON v3)

The workflow now emits questions in your platform's canonical shape and
writes one JSON file per approved question to Drive (in addition to the
bucket JSON files).

## The shape (one file per question)

`QuestionBank/{board}/{class}/{subject}/{chapter}/{qtype}/{difficulty}/{batch_id}/Q01.json`,
`Q02.json`, ... — exactly matching:

```json
{
  "metadata": {
    "board": "ICSE",
    "category_choices": "K-12",
    "chapter_name": "Real Numbers",
    "chapter_no": 1,
    "chapter_uuid": "chapter-real-numbers-icse-10-v1",
    "concept_name": "Irrational numbers",
    "concept_no": 1,
    "concept_uuid": "concept-irrational-numbers-v1",
    "question_level": "LEVEL_EASY",
    "question_type": "TRUE_FALSE",
    "question_category": "THEORETICAL",
    "standard": "10th",
    "subject_code": "MATHS",
    "subject_name": "Maths",
    "question_mark": 1,
    "bloom": [
      { "bloom_level": "REMEMBER",   "bloom_priority": 1 },
      { "bloom_level": "UNDERSTAND", "bloom_priority": 2 }
    ],
    "generation_version": "v2"
  },
  "question": {
    "final_answer": {
      "correct_options": [{ "option_number": "A" }],
      "answer_text": ""
    },
    "options": [
      { "option_number": "A", "option_text": "True" },
      { "option_number": "B", "option_text": "False" }
    ],
    "question_no": 1,
    "question_text": "<p>The decimal expansion of an irrational number never terminates and never repeats.</p>",
    "question_diagram_url": ""
  }
}
```

JSON Schema: `prompt-repo/schemas/output/question.v3.json` (per-question).
AI Call 1 draft schema (what the generator returns): `draft.v3.json`.

## Enums

| Field | Allowed values |
|---|---|
| `question_type` | `MULTIPLE_CHOICE`, `ASSERTION_REASONING`, `MULTI_STATEMENT_MCQ`, `VERY_SHORT_ANSWER`, `SHORT_ANSWER`, `FILL_IN_THE_BLANK`, `TRUE_FALSE`, `LONG_ANSWER`, `CASE_STUDY`, `MATCH_COLUMNS`, `SUBPART_BASED` |
| `question_level` | `LEVEL_EASY`, `LEVEL_MEDIUM`, `LEVEL_HARD` |
| `question_category` | `NUMERICAL`, `THEORETICAL` |
| `bloom_level` | `REMEMBER`, `UNDERSTAND`, `APPLY`, `ANALYZE`, `EVALUATE`, `CREATE` |
| `bloom_priority` | `1` (primary), `2` (secondary). Max 2 entries per question. |

`bloom_priority` is strictly 1 or 2 — enforced both by the v3 JSON Schema and
by the re-tag node's `buildRow` mapping (it always emits priority 1 for the
first bloom and 2 for the second, dropping anything beyond two).

## Concept mapping (new pipeline stage)

Operators **don't** type concept_name / concept_no / concept_uuid on the
form. Instead:

1. Load your concept catalogue once into the `chapter_concepts` table:

   ```sql
   INSERT INTO chapter_concepts
     (board, class, subject, chapter_slug, chapter_no, chapter_uuid,
      concept_no, concept_uuid, concept_name)
   VALUES
     ('icse','10','maths','real-numbers', 1, 'chapter-real-numbers-icse-10-v1',
      1, 'concept-irrational-numbers-v1', 'Irrational numbers');
   ```

   Migration `0013_question_schema_v2.sql` seeds rows for ICSE Class 10 Maths
   *Real Numbers* (3 concepts, mirroring your example) and CBSE Class 12
   Chemistry *Solutions* (7 concepts) as starting points.

2. The new **Load Chapter Concepts** Postgres node runs after Curriculum
   Resolve. It selects every active row for
   `(board, class, subject, chapter_slug)`. If the chapter isn't seeded the
   generator falls back to a single unmapped concept, and the question lands
   with `concept_uuid='concept-unmapped-fallback'` — a clear signal to
   backfill the catalogue.

3. **Agent 4** injects the catalogue into the generator prompt as a
   `CONCEPT CATALOGUE` block. The prompt mandates each draft pick exactly
   one `concept_no` from that list.

4. **Parse + Validate Draft JSON** maps each draft's `concept_no` (or
   `concept_uuid` as a fallback key) back to the catalogue row, attaching
   `concept_name` + `chapter_no` + `chapter_uuid` to the draft for the
   downstream re-tag stage. A mismatched concept reference is recorded in
   `_concept_mapping_warning` and forced to the first catalogue entry to
   keep the batch alive.

5. **Agent 7a** (validator prompt builder) passes the same catalogue to
   AI Call 2, which is instructed to flag concept_no/uuid mismatches as
   hallucinations.

## Per-question Drive files

After every successful run, the **Per-Question Splitter** Code node fans
out the good_questions array into N items. The **Drive - Write
Per-Question JSON** node then executes once per item, writing each `QN.json`
into the same batch folder as the bucket files. Each file carries
`appProperties.idempotencyKey = {batch_id}_Q{n}` so re-runs are
content-addressable.

```
QuestionBank/icse/10/maths/real-numbers/true_false/level_easy/BCH_XYZ/
  GOOD_QUESTIONS.json        ← bucket file (all good Qs in one array)
  UPGRADE_QUESTIONS.json     ← unchanged
  BAD_QUESTIONS.json         ← unchanged
  REPORTS_BUNDLE.json        ← unchanged
  Q01.json                   ← one file per good question, v3 schema
  Q02.json
  ...
```

## Form changes

The form trigger now:
- Uses the new uppercase enum values (`MULTIPLE_CHOICE`, `TRUE_FALSE`,
  `LEVEL_EASY`, etc.) so what you select on the form is exactly what
  appears in the output JSON.
- Adds `category_choices` dropdown (default `K-12`).
- Adds optional `standard` text field. If blank, it's auto-derived from
  Class with an ordinal suffix (`10` → `10th`, `12` → `12th`).
- Adds optional `question_mark_override` integer. If blank, the AI proposes
  per-question marks within the type's default (MCQ=1, SA=3, LA=5, …).

Internally, the workflow still uses lowercase routing keys (`multiple_choice`,
`level_easy` → `easy`, etc.) for prompt + curriculum lookups so existing
seeds continue to resolve. Translation happens at the I/O boundary only.

## Per-vertical deployment via `QGEN_INSTANCE_FILTER`

To deploy a "Chemistry only" instance, set the n8n env var:

```
QGEN_INSTANCE_FILTER=subject=chemistry
```

Agent 1 reads this on every run and rejects submissions where any
`key=value` pair doesn't match. Supported keys: `board`, `class`, `subject`,
`chapter_slug`, `question_type`, `difficulty`, `language`. Multiple filters
comma-separated:

```
QGEN_INSTANCE_FILTER=board=cbse,class=12,subject=chemistry
```

For a fully customised form (different dropdown choices per instance),
clone the workflow and edit the form trigger fields — the rest of the
pipeline is identical and resolves prompts/curriculum based on the
metadata submitted.

## DB columns added (migration 0013)

`questions_master`, `review_queue`, `rejected_questions` all gained:

| Column | Type | Notes |
|---|---|---|
| `chapter_no` | int | from chapter_concepts |
| `chapter_uuid` | text | from chapter_concepts |
| `concept_no` | int | AI-mapped |
| `concept_uuid` | text | AI-mapped, indexed |
| `concept_name` | text | from chapter_concepts |
| `question_category` | text | `NUMERICAL` or `THEORETICAL` |
| `question_mark` | int | 1..10 |
| `bloom` | jsonb | array of `{bloom_level, bloom_priority}` |
| `subject_code` | text | e.g. `MATHS`, `CHEM` |
| `subject_display_name` | text | e.g. `Maths` |
| `standard` | text | e.g. `10th` |
| `category_choices` | text | e.g. `K-12` |
| `generation_version` | text | `v2` for this generation |
| `final_answer_text` | text | hint or answer (HTML allowed) |
| `question_diagram_url` | text | S3/Drive URL or "" |
| `question_text_html` | text | rendered HTML with KaTeX |
| `correct_options` | jsonb | `[{option_number}]` |
| `question_no_in_batch` | int | 1..N |

## What didn't change

- The 2-AI-call budget still holds.
- The bucket invariant (`good`→`questions_master`, etc.) still holds.
- All seven existing migrations and the workflow's caching, dedup, cost
  tracking, error sub-workflow, and Drive folder resolver are unchanged.
- The existing `BCH_X/GOOD_QUESTIONS.json` bucket file is still emitted —
  the per-question files are additive.
