-- Extend review_queue + rejected_questions with the deterministic dedup
-- signatures so we can run cross-bucket duplicate analytics (e.g. "did this
-- upgrade-tagged question already exist as a rejected duplicate in a prior
-- batch?"). These columns mirror the existing ones on questions_master.

ALTER TABLE review_queue
  ADD COLUMN IF NOT EXISTS normalized_question_hash TEXT,
  ADD COLUMN IF NOT EXISTS simhash                  BIGINT,
  ADD COLUMN IF NOT EXISTS minhash_signature        BYTEA;

ALTER TABLE rejected_questions
  ADD COLUMN IF NOT EXISTS normalized_question_hash TEXT,
  ADD COLUMN IF NOT EXISTS simhash                  BIGINT,
  ADD COLUMN IF NOT EXISTS minhash_signature        BYTEA;

CREATE INDEX IF NOT EXISTS rq_norm_hash_idx  ON review_queue       (normalized_question_hash);
CREATE INDEX IF NOT EXISTS rq_simhash_idx    ON review_queue       (simhash);
CREATE INDEX IF NOT EXISTS rj_norm_hash_idx  ON rejected_questions (normalized_question_hash);
CREATE INDEX IF NOT EXISTS rj_simhash_idx    ON rejected_questions (simhash);
