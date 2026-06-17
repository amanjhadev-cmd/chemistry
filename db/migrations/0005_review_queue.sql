-- Review queue: questions tagged 'upgrade' by AI Call 2.
-- Held for human review / regeneration. NEVER touch questions_master.

CREATE TABLE IF NOT EXISTS review_queue (
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

  validation_status        TEXT         NOT NULL DEFAULT 'upgrade'
                             CHECK (validation_status = 'upgrade'),
  validation_score         NUMERIC,
  validation_scores_detail JSONB,
  validation_reasons       JSONB,
  required_upgrades        JSONB,

  duplicate_status         TEXT,
  duplicate_score          NUMERIC,
  duplicate_candidate_ids  TEXT[],

  source_pdf_id            TEXT,
  source_pdf_hash          TEXT,
  source_pages             INT[],
  source_section_ids       TEXT[],
  bloom_level              TEXT,
  visual_metadata          JSONB,

  audit                    JSONB,
  reviewed                 BOOLEAN      NOT NULL DEFAULT FALSE,
  reviewer_decision        TEXT,
  reviewer_notes           TEXT,
  created_at               TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS rq_scope_idx
  ON review_queue (board, class, subject, chapter);

CREATE INDEX IF NOT EXISTS rq_batch_idx
  ON review_queue (batch_id);

CREATE INDEX IF NOT EXISTS rq_pending_idx
  ON review_queue (created_at)
  WHERE reviewed = FALSE;
