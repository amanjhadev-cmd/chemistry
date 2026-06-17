-- Production approved question bank.
-- ONLY 'good'-tagged questions land here.
-- Partitioned by board so each board can scale + reindex independently.

CREATE TABLE IF NOT EXISTS questions_master (
  question_id              UUID         NOT NULL,
  canonical_question_id    TEXT         NOT NULL,
  batch_id                 TEXT         NOT NULL,
  draft_question_id        TEXT,

  board                    TEXT         NOT NULL,
  class                    TEXT         NOT NULL,
  subject                  TEXT         NOT NULL,
  chapter                  TEXT,
  topic                    TEXT,
  subtopic                 TEXT,
  question_type            TEXT         NOT NULL,
  difficulty               TEXT         NOT NULL,
  language                 TEXT         NOT NULL,
  source_type              TEXT,

  question_text            TEXT         NOT NULL,
  options                  JSONB,
  answer                   TEXT         NOT NULL,
  explanation              TEXT,

  -- Deterministic dedup keys (populated by Agent 6 / Agent 7 stage prep).
  normalized_question_hash TEXT,
  simhash                  BIGINT,
  minhash_signature        BYTEA,

  -- AI Call 2 outputs.
  validation_status        TEXT         NOT NULL DEFAULT 'good'
                             CHECK (validation_status = 'good'),
  validation_score         NUMERIC,
  validation_scores_detail JSONB,
  validation_reasons       JSONB,
  required_upgrades        JSONB,

  duplicate_status         TEXT,
  duplicate_score          NUMERIC,
  duplicate_candidate_ids  TEXT[],
  hallucination_flag       BOOLEAN      DEFAULT FALSE,

  -- Provenance.
  source_pdf_id            TEXT,
  source_pdf_hash          TEXT,
  source_pages             INT[],
  source_section_ids       TEXT[],
  bloom_level              TEXT,
  competency_tags          TEXT[],
  learning_outcome_tags    TEXT[],
  board_taxonomy_tags      TEXT[],
  visual_metadata          JSONB,

  audit                    JSONB,
  created_at               TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ  NOT NULL DEFAULT now(),

  PRIMARY KEY (board, canonical_question_id)
) PARTITION BY LIST (board);

-- One partition per supported board. Add more via additional migrations.
CREATE TABLE IF NOT EXISTS questions_master_cbse
  PARTITION OF questions_master FOR VALUES IN ('cbse');
CREATE TABLE IF NOT EXISTS questions_master_icse
  PARTITION OF questions_master FOR VALUES IN ('icse');
CREATE TABLE IF NOT EXISTS questions_master_igcse
  PARTITION OF questions_master FOR VALUES IN ('igcse');
CREATE TABLE IF NOT EXISTS questions_master_ib
  PARTITION OF questions_master FOR VALUES IN ('ib');
CREATE TABLE IF NOT EXISTS questions_master_jee
  PARTITION OF questions_master FOR VALUES IN ('jee');
CREATE TABLE IF NOT EXISTS questions_master_neet
  PARTITION OF questions_master FOR VALUES IN ('neet');
-- Catch-all partition for boards not yet onboarded.
CREATE TABLE IF NOT EXISTS questions_master_default
  PARTITION OF questions_master DEFAULT;

-- Generated tsvector for full-text retrieval (used by dup candidate retriever).
ALTER TABLE questions_master
  ADD COLUMN IF NOT EXISTS tsv TSVECTOR
  GENERATED ALWAYS AS (to_tsvector('english', coalesce(question_text, ''))) STORED;

-- Indexes for the 4 deterministic dedup signals + scope filter.
CREATE INDEX IF NOT EXISTS qm_norm_hash_idx
  ON questions_master (normalized_question_hash);

CREATE INDEX IF NOT EXISTS qm_trgm_idx
  ON questions_master USING gin (question_text gin_trgm_ops);

CREATE INDEX IF NOT EXISTS qm_fts_idx
  ON questions_master USING gin (tsv);

CREATE INDEX IF NOT EXISTS qm_simhash_idx
  ON questions_master (simhash);

CREATE INDEX IF NOT EXISTS qm_scope_idx
  ON questions_master (board, class, subject, chapter);

CREATE INDEX IF NOT EXISTS qm_batch_idx
  ON questions_master (batch_id);

CREATE UNIQUE INDEX IF NOT EXISTS qm_canon_unique
  ON questions_master (canonical_question_id);
