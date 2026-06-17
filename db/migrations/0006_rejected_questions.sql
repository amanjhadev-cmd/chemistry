-- Rejected audit table: questions tagged 'bad' by AI Call 2.
-- Retained for quality analysis, hallucination tracking, and future regeneration tuning.
-- NEVER touches questions_master.

CREATE TABLE IF NOT EXISTS rejected_questions (
  question_id              UUID         PRIMARY KEY,
  canonical_question_id    TEXT         NOT NULL UNIQUE,
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
  answer                   TEXT,
  explanation              TEXT,

  validation_status        TEXT         NOT NULL DEFAULT 'bad'
                             CHECK (validation_status = 'bad'),
  validation_score         NUMERIC,
  validation_scores_detail JSONB,
  validation_reasons       JSONB,

  duplicate_status         TEXT,
  duplicate_score          NUMERIC,
  duplicate_candidate_ids  TEXT[],
  hallucination_flag       BOOLEAN      DEFAULT FALSE,

  source_pdf_id            TEXT,
  source_pdf_hash          TEXT,
  source_pages             INT[],
  source_section_ids       TEXT[],
  bloom_level              TEXT,
  visual_metadata          JSONB,

  audit                    JSONB,
  created_at               TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS rj_scope_idx
  ON rejected_questions (board, class, subject, chapter);

CREATE INDEX IF NOT EXISTS rj_batch_idx
  ON rejected_questions (batch_id);

CREATE INDEX IF NOT EXISTS rj_halluc_idx
  ON rejected_questions (hallucination_flag, created_at)
  WHERE hallucination_flag;

CREATE INDEX IF NOT EXISTS rj_duplicate_idx
  ON rejected_questions (duplicate_status, created_at);
