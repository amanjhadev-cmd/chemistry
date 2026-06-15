#!/usr/bin/env bash
# Verify a Question Generation v1.0 batch landed correctly in Postgres.
#
# Required environment:
#   DATABASE_URL  e.g. postgres://user:pass@host:5432/dbname
#   BATCH         the batch_id returned by submit.sh (e.g. BCH_M7QJX9YZ_ABCDEF12)

set -euo pipefail

: "${DATABASE_URL:?Set DATABASE_URL}"
: "${BATCH:?Set BATCH=<batch_id from submit.sh response>}"

echo "Batch: ${BATCH}"
echo "=================================================="

echo
echo "[1/5] questions_master rows (good only — should be > 0 if AI calls succeeded):"
psql "$DATABASE_URL" -At -c \
  "SELECT count(*) FROM questions_master WHERE batch_id = '${BATCH}';"

echo
echo "[2/5] review_queue rows (upgrade tag):"
psql "$DATABASE_URL" -At -c \
  "SELECT count(*) FROM review_queue WHERE batch_id = '${BATCH}';"

echo
echo "[3/5] rejected_questions rows (bad tag):"
psql "$DATABASE_URL" -At -c \
  "SELECT count(*) FROM rejected_questions WHERE batch_id = '${BATCH}';"

echo
echo "[4/5] generation_audit_log entries:"
psql "$DATABASE_URL" -c \
  "SELECT stage, status, created_at FROM generation_audit_log WHERE batch_id = '${BATCH}' ORDER BY log_id;"

echo
echo "[5/5] sample of good questions (first 3):"
psql "$DATABASE_URL" -c \
  "SELECT canonical_question_id, question_type, difficulty,
          left(question_text, 80) AS question_preview,
          answer, validation_score
   FROM questions_master
   WHERE batch_id = '${BATCH}'
   LIMIT 3;"

echo
echo "Bucket invariant check (must all be 0):"
psql "$DATABASE_URL" -At -c \
  "SELECT count(*) FROM questions_master WHERE batch_id = '${BATCH}' AND validation_status <> 'good';"
psql "$DATABASE_URL" -At -c \
  "SELECT count(*) FROM review_queue       WHERE batch_id = '${BATCH}' AND validation_status <> 'upgrade';"
psql "$DATABASE_URL" -At -c \
  "SELECT count(*) FROM rejected_questions WHERE batch_id = '${BATCH}' AND validation_status <> 'bad';"

echo
echo "Curriculum + prompt provenance from the audit body:"
psql "$DATABASE_URL" -c \
  "SELECT audit->>'prompt_template_id' AS prompt_id,
          audit->>'prompt_template_version' AS prompt_v,
          audit->>'curriculum_rules_version' AS curr_v,
          audit->>'generator_model' AS gen_model,
          audit->>'validator_model' AS val_model
   FROM questions_master
   WHERE batch_id = '${BATCH}'
   LIMIT 1;"
