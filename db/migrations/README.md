# Question Generation v1.0 — Database Migrations

Apply in order against your Postgres 14+ instance. All migrations are idempotent.

```bash
for f in 0001_extensions.sql \
         0002_kb_cache.sql \
         0003_curriculum_rules.sql \
         0004_questions_master.sql \
         0005_review_queue.sql \
         0006_rejected_questions.sql \
         0007_audit_and_coverage.sql; do
  psql "$DATABASE_URL" -f "db/migrations/$f"
done
```

## What each migration provides

| File | Purpose | Used by node(s) |
|---|---|---|
| `0001_extensions.sql` | `pgcrypto`, `pg_trgm`, `unaccent` | — |
| `0002_kb_cache.sql` | `kb_cache` — skip PDF extraction on repeat runs | `Knowledge Cache Lookup`, `KB Cache Write` |
| `0003_curriculum_rules.sql` | `curriculum_rules` + global default row | (future) `Agent 2 - Hash PDF + Resolve Curriculum` |
| `0004_questions_master.sql` | Approved bank, partitioned by board, with trigram/FTS/simhash indexes | `Agent 6 - Duplicate Candidates`, `PG - Insert GOOD into questions_master` |
| `0005_review_queue.sql` | `review_queue` for `upgrade`-tagged questions | `PG - Insert UPGRADE into review_queue` |
| `0006_rejected_questions.sql` | `rejected_questions` audit for `bad`-tagged questions | `PG - Insert BAD into rejected_questions` |
| `0007_audit_and_coverage.sql` | `generation_audit_log`, `error_audit`, `coverage_tracker` | `PG - Audit Log`, error workflow |

## Hard invariants enforced at the DB level

- `questions_master.validation_status` is constrained to `'good'` — bad/upgrade rows literally cannot be inserted into the production bank.
- `review_queue.validation_status` is constrained to `'upgrade'`.
- `rejected_questions.validation_status` is constrained to `'bad'`.
- `(board, canonical_question_id)` is the partition key + unique key on `questions_master` so retries are idempotent.

## Onboarding a new board

```sql
CREATE TABLE IF NOT EXISTS questions_master_<board>
  PARTITION OF questions_master FOR VALUES IN ('<board>');
```

Then add curriculum_rules rows at the relevant precedence levels — no workflow change needed.
