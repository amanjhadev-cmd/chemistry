# Smoke Test — Question Generation v1.0

Three things in here:

1. A sample chapter PDF (deterministic, generated from markdown).
2. A `curl` script that submits the PDF to the live n8n form trigger.
3. A `psql` script that verifies the batch landed in the right tables.
4. A pure-Node unit test suite for the deterministic agent logic (no
   external services required).

## Files

| File | Purpose |
|---|---|
| `chapter_solutions_source.md` | Source text for the sample PDF. Edit + regenerate the PDF. |
| `generate_sample_pdf.py` | Hand-rolled PDF 1.4 writer. No external deps. |
| `sample_chapter_solutions.pdf` | Generated artifact (4 pages, ~7KB). Checked in for convenience. |
| `submit.sh` | Multipart POST to the workflow's Form Trigger webhook. |
| `verify.sh` | Postgres queries to confirm bucket counts + audit + provenance. |
| `test_units.mjs` | 19 unit tests for slugify, canonical_question_id, re-tag rules, curriculum key chain, prompt fallback resolver, AI ledger invariant. |

## Quick start

### 0. (Optional) Regenerate the PDF

```bash
python3 generate_sample_pdf.py
```

### 1. Run the offline unit tests — no n8n, no DB needed

```bash
node test_units.mjs
```

Exit 0 means the deterministic agent logic is sound. **Run this in CI**.

### 2. Live smoke test against your n8n instance

Find the Form Trigger webhook URL: open the workflow, click the **Form -
Submit Generation Request** node, copy the "Production URL" (looks like
`/form/<uuid>`).

```bash
export N8N_BASE_URL="https://devvrat.app.n8n.cloud"
export N8N_FORM_PATH="/form/<your-uuid>"

./submit.sh
```

The script prints the response JSON and saves it to `/tmp/qgen_submit_response.json`.
Grab the `batch_id` from there.

### 3. Verify the batch landed correctly

```bash
export DATABASE_URL="postgres://user:pass@host:5432/dbname"
export BATCH="BCH_M7QJX9YZ_ABCDEF12"  # from step 2

./verify.sh
```

This prints:
- `questions_master` row count for the batch (should be ≈ requested count if all good)
- `review_queue` row count (upgrade-tagged)
- `rejected_questions` row count (bad-tagged)
- the full audit trail from `generation_audit_log`
- a sample of 3 good questions
- the **bucket invariant check** — three lines that must all return `0`
- provenance: prompt template id/version, curriculum rules version, generator + validator model

## What this proves end-to-end

A successful smoke test exercises every lane:

1. **Ingress** — form parses 11 fields + the binary PDF.
2. **Metadata** — slugify, routing_key, batch_id, source_pdf_id generated deterministically.
3. **Hash + Curriculum** — sha256 of PDF computed; curriculum_rules walked through 6-level chain.
4. **Knowledge** — first run = miss → extract via HTTP service → cache. Second run = hit → reuse.
5. **Prompt resolution** — manifest.json fetched from GitHub raw, 8-level fallback walked, generator template rendered.
6. **AI Call 1** — Anthropic generates `draft_count` drafts.
7. **Duplicate candidates** — Postgres trigram lookup against `questions_master`.
8. **AI Call 2** — Anthropic validates + judges duplicates + tags good/upgrade/bad in a single call.
9. **Persistence** — three Drive JSON files + three Postgres inserts, all idempotent on `canonical_question_id`.
10. **Response** — Form returns batch summary.

## Re-run safety

The smoke test is idempotent at the `canonical_question_id` level. Submitting
the same PDF + metadata twice produces a second batch_id but `ON CONFLICT DO
NOTHING` prevents duplicate rows in `questions_master`. The KB cache hit on
the second run will also skip the (slow) extraction microservice call.

## When the live smoke test will fail

| Symptom | Likely cause |
|---|---|
| 401/403 on submit | n8n form trigger has auth enabled — disable for testing, or pass creds |
| `relation "kb_cache" does not exist` | Run `db/migrations/000{1..7}*.sql` first |
| AI Call 1 hangs/times out | Anthropic credential missing or model id wrong on the workflow node |
| All questions `upgrade` with reason `validator_unreachable_for_this_draft` | AI Call 2 returned malformed JSON — check the workflow execution log |
| `PROMPT_REPO_NO_GENERATOR_FALLBACK` | Hardcoded `PROMPT_REPO_BASE` URL in Agent 4 doesn't resolve (e.g. branch renamed, repo private) |
| 0 rows in `questions_master`, non-zero in `review_queue` | Validator scored all drafts below `good` threshold — inspect `validation_scores_detail` |
| Drive upload fails | Replace `PLACEHOLDER_DRIVE_FOLDER_ID` on the 4 Drive nodes with a real folder ID |
