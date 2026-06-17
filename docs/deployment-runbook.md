# Deployment Runbook — Question Generation v1.0

The single page to follow before going live. Everything else in `docs/` is
reference material; this is the procedure.

## Pre-flight checklist (10 minutes)

Run these from a machine that has `psql` and the cloned repo:

- [ ] `node prompt-repo/lint.mjs` → must print `OK — 0 errors`
- [ ] `node samples/smoke_test/test_units.mjs` → must print `N passed, 0 failed`
- [ ] `psql "$DATABASE_URL" -c '\\dx'` → confirms `pgcrypto`, `pg_trgm`, `unaccent`
      extensions exist (or will be installed by migration 0001)
- [ ] You have:
  - An Anthropic API key with a budget set
  - A Postgres 14+ database, empty or upgrade-friendly
  - A Google Drive folder ID where the `QuestionBank/` tree will live
  - A running n8n instance (cloud or self-hosted) with credentials access
- [ ] Repo visibility decided:
  - **Public repo** → no extra config; default `PROMPT_REPO_BASE` points at
    `https://raw.githubusercontent.com/<owner>/<repo>/main/prompt-repo`
  - **Private repo** → you'll add `QGEN_PROMPT_REPO_AUTH` env var below

## Step 1 — Apply all 13 SQL migrations (5 min)

```bash
export DATABASE_URL='postgres://user:pass@host:5432/qgen?sslmode=require'

for f in 0001_extensions.sql \
         0002_kb_cache.sql \
         0003_curriculum_rules.sql \
         0004_questions_master.sql \
         0005_review_queue.sql \
         0006_rejected_questions.sql \
         0007_audit_and_coverage.sql \
         0008_seed_cbse_chemistry_curriculum.sql \
         0009_drive_folder_cache.sql \
         0010_extend_buckets_with_dedup_sigs.sql \
         0011_coverage_tracker_triggers.sql \
         0012_cost_tracking.sql \
         0013_question_schema_v2.sql; do
  psql "$DATABASE_URL" -f "db/migrations/$f" || exit 1
done
```

Verify:
```sql
SELECT count(*) FROM curriculum_rules;     -- expect >= 7
SELECT count(*) FROM chapter_concepts;      -- expect >= 10 (seed only)
SELECT count(*) FROM model_pricing;          -- expect >= 1
SELECT count(*) FROM subject_codes;          -- expect >= 7
```

## Step 2 — Seed your real concept catalogue (varies)

The seed in `0013_question_schema_v2.sql` only covers two example chapters.
For every chapter you'll actually generate against, insert rows:

```sql
INSERT INTO chapter_concepts
  (board, class, subject, chapter_slug, chapter_no, chapter_uuid,
   concept_no, concept_uuid, concept_name)
VALUES
  ('cbse', '10', 'maths', 'real-numbers', 1, 'chap-cbse-10-maths-realnum-uuid',
   1, 'concept-uuid-1', 'Irrational numbers'),
  ('cbse', '10', 'maths', 'real-numbers', 1, 'chap-cbse-10-maths-realnum-uuid',
   2, 'concept-uuid-2', 'Decimal expansion');
-- repeat per chapter
```

Without this, AI Call 1 falls back to a single "unmapped" concept and the
output JSON's `concept_*` fields will all carry the unmapped sentinel.

(Optional) Seed curriculum overrides for your boards beyond CBSE Chemistry —
see `db/migrations/0008_seed_cbse_chemistry_curriculum.sql` for the pattern.

## Step 3 — Deploy the extractor microservice (5 min)

```bash
cd extractor-svc
docker compose up -d --build
# Health check:
curl -fsS http://localhost:8001/readyz | jq .
```

Note the URL n8n will reach this from:
- Same host as n8n: `http://qgen-extractor:8000` (Docker network DNS)
- Different host: `http://<extractor-host>:8001`

(Optional) For an authenticated extractor, set `EXTRACTOR_BEARER_TOKEN`
in the compose env and add `Authorization: Bearer <token>` to Agent 3 in n8n.

## Step 4 — Configure n8n credentials + env vars (10 min)

In the n8n UI, **Credentials → New**:

| Credential name | Type | Notes |
|---|---|---|
| `Anthropic - Question Generation` | Anthropic API | Key with budget set |
| `Postgres - Master DB` | Postgres | Points at `$DATABASE_URL` |
| `Google Drive - QuestionBank` | Google Drive OAuth2 | Scope: drive.file (or full drive) |
| (optional) Form Trigger Basic Auth | HTTP Basic Auth | Username + password for form access |

In the n8n UI, **Settings → Environment Variables** (or your container env):

| Env var | Required? | Purpose |
|---|---|---|
| `QGEN_PROMPT_REPO_BASE` | Recommended | Raw URL of `prompt-repo/`. Default: `https://raw.githubusercontent.com/amanjhadev-cmd/chemistry/main/prompt-repo`. **Change this if you fork.** |
| `QGEN_PROMPT_REPO_AUTH` | If repo private | E.g. `token ghp_xxx` for GitHub. Sent as `Authorization` header. |
| `QGEN_INSTANCE_FILTER` | Per-vertical only | E.g. `subject=chemistry,board=cbse` to restrict the form to one vertical. |
| `EXTRACTOR_BEARER_TOKEN` | If you set one | Sent by Agent 3 — wire in the HTTP node credentials |

## Step 5 — Open the workflow and fix the placeholders (5 min)

Workflow URL: https://devvrat.app.n8n.cloud/workflow/HKYbMEHdN2034xxM

Visit each node listed below and replace the placeholder value:

| Node | Placeholder | Replace with |
|---|---|---|
| `Drive Folder Resolver` | `PLACEHOLDER_DRIVE_ROOT_FOLDER_ID` (inside the Code) | Your real Drive folder id |
| `Agent 3 - Non-AI PDF Extract` | `https://extract.internal.placeholder/extract` | Your extractor URL from Step 3 |
| `Notify Operators (Slack)` (in the **error** workflow `teW9SmrspnNlsNuT`) | `https://hooks.slack.placeholder/services/REPLACE_ME` | Your Slack incoming webhook |

Then **link the error workflow**: open the main workflow → gear icon →
Settings → **Error Workflow** → select `Question Generation v1.0 - Error
Handler` → Save.

## Step 6 — Activate + grab the form URL (1 min)

Toggle the main workflow to **Active**. Click the form trigger node →
copy the **Production URL** (looks like `/form/<uuid>`).

If you enabled basic auth on the form, the URL will require a username/password.

## Step 7 — Live smoke test (10 min)

```bash
export N8N_BASE_URL='https://devvrat.app.n8n.cloud'
export N8N_FORM_PATH='/form/<your-uuid>'
# If basic auth:
export N8N_BASIC_AUTH='user:pass'

# Patch submit.sh to add basic auth header if needed:
# (or use curl -u "$N8N_BASIC_AUTH" -X POST ... )

./samples/smoke_test/submit.sh
# Note the batch_id printed.

export DATABASE_URL='postgres://...'
export BATCH='BCH_XXXX_XXXXXXXX'
./samples/smoke_test/verify.sh
```

The three bucket-invariant lines must all return `0`. The cost row must show
nonzero token counts. The Drive folder must contain `Q01.json`, `Q02.json`,
... matching your platform schema exactly.

## Step 8 — Watch the first batch end-to-end (5 min)

In the n8n UI, **Executions** → open the running execution → expand each node.
What to look for at each lane:

- **Ingress → Knowledge**: `Knowledge Cache Lookup` should miss on first run,
  then PDF Extract should succeed, then `KB Cache Write` should INSERT.
  Second run with the same PDF: cache HIT, extract skipped.
- **Curriculum**: `Curriculum - Resolve` should emit `resolution.level` matching
  your most-specific seed (often 1 for CBSE 12 Chem Solutions; 6 for unseeded).
- **Concepts**: `Load Chapter Concepts` should return N rows (your seeded count).
- **Generation**: `AI CALL 1` returns; `Parse + Validate Draft JSON` should
  log `_concept_mapping_warning` for any draft that mis-typed a concept.
- **Validation**: `AI CALL 2` returns; `Parse Re-Tag` outputs N validated rows.
  Inspect their `platform_json` field — it should match your schema.
- **Persistence**: 4 Drive uploads succeed (bucket files), then N more
  per-question Q01.json…QN.json. Then 3 PG inserts succeed.
- **Cost**: `cost_per_batch` row exists; sanity-check `total_cost_usd` against
  Anthropic's billing dashboard within the first hour.

## Step 9 — Stand up monitoring (10 min, optional but recommended)

```bash
cd metrics
export DATABASE_URL='postgres://...'
docker compose up -d
# Prometheus: http://localhost:9090
# Grafana:    http://localhost:3001
```

The **Question Generation - Overview** dashboard auto-provisions. The
**QgenAiCallBudgetLeak** alert is the most important one to wire into
PagerDuty/Slack — it fires when AI calls and cost capture diverge,
which is the canonical signal that the 2-AI-call invariant has broken.

## Rollback (if something is on fire)

| What broke | What to do |
|---|---|
| The whole workflow is failing | **Deactivate** the workflow in n8n UI. The form stops accepting submissions immediately. |
| One node is throwing | Pin the bad node to `onError: continueRegularOutput` in the UI as a hotfix, then `git revert` the offending commit and re-deploy. |
| Bad data landed in `questions_master` | `DELETE FROM questions_master WHERE batch_id = 'BCH_XXXX'`; the CHECK constraint will refuse re-inserts of the same canonical_question_id, so re-running the same batch is safe. |
| KB cache poisoned | `DELETE FROM kb_cache WHERE pdf_hash = 'sha256:...'`; next run will re-extract. |
| Curriculum picking the wrong rule | `UPDATE curriculum_rules SET active = FALSE WHERE id = N`; the resolver walks down to the next-most-specific active rule. |
| Concept catalogue wrong | `DELETE FROM chapter_concepts WHERE board=... AND chapter_slug=...; INSERT ... corrected rows`; next run picks up the new catalogue (no cache). |
| Workflow update broke everything | n8n keeps versionId on every save — restore the previous version from the UI's history. |

## What's deferred (#19–24 from the production checklist)

These were intentionally NOT done before deployment. Add them when usage
warrants:

- **More board seeds**: insert rows into `curriculum_rules` and
  `chapter_concepts` — no workflow change.
- **More validator/generator templates**: add `.v2.j2` files + register in
  `prompt-repo/manifest.json`; bump `pricing_version` if applicable.
- **More output schemas per question type**: `draft.v3.json` is generic
  enough for all 11 question types; add type-specific schemas only if you
  hit a structural mismatch.
- **Visual question pipeline end-to-end**: extractor already extracts images
  to `assets/`; wiring them through Agent 4 / AI Call 1 / Drive write is a
  follow-up day's work.
- **Multilingual rubrics**: workflow already accepts `language=hi`; add
  language-specific rubrics under `prompt-repo/rubrics/`.
- **Archival job for old rejected_questions**: write a monthly cron that
  moves rows older than 24 months to cold storage.

## Useful daily queries

```sql
-- Yesterday's spend
SELECT * FROM daily_cost_rollup WHERE day = current_date - 1;

-- Top 10 costliest batches in last 24h
SELECT batch_id, total_cost_usd, draft_count, good_count
FROM cost_per_batch
WHERE created_at > now() - interval '24 hours'
ORDER BY total_cost_usd DESC LIMIT 10;

-- Coverage gaps (cells with <5 good Qs)
SELECT * FROM coverage_gaps LIMIT 20;

-- Errors in last hour
SELECT created_at, error_code, error_message, node_name
FROM error_audit
WHERE created_at > now() - interval '1 hour'
ORDER BY created_at DESC;

-- Good ratio over last 7 days
SELECT date_trunc('day', created_at)::date AS day,
       round(sum(good_count)::numeric / NULLIF(sum(good_count+upgrade_count+bad_count),0) * 100, 1) AS good_pct
FROM cost_per_batch
WHERE created_at > now() - interval '7 days'
GROUP BY 1 ORDER BY 1;
```

## The two pre-existing validator warnings

You'll see these in every workflow validation output:

```
"AI CALL 1 - Question Generator": Missing discriminator "parameters.resource". Expected one of: "document", "file", "image", "prompt".
"AI CALL 2 - Validator + Dup Judge + Quality Tagger": Missing discriminator "parameters.resource". Expected one of: "document", "file", "image", "prompt".
```

**These are false positives** from a stale n8n MCP validator. The actual
Anthropic node `resource: 'text'` + `operation: 'message'` combination IS
in the documented discriminator list (we verified against `get_node_types`
in the SDK reference) — it just isn't in the *validator's hint string*.
The nodes execute correctly at runtime. Safe to ignore.

## Help

- Architecture: `docs/phase-1-architecture.md`, `docs/data-contracts.md`
- Deduplication: `docs/deduplication.md`
- Caching: `docs/caching.md`
- Cost tracking: `docs/cost-tracking.md`
- Drive layout: `docs/drive-storage.md`
- Error handling: `docs/error-handling.md`
- Observability: `docs/observability.md`
- Question schema v2: `docs/question-schema-v2.md`
- Original blueprint: see the assistant message in the session that produced this
