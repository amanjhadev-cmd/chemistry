-- Append-only audit + coverage tracking. Written by every run, regardless of outcome.

CREATE TABLE IF NOT EXISTS generation_audit_log (
  log_id            BIGSERIAL   PRIMARY KEY,
  batch_id          TEXT,
  n8n_execution_id  TEXT,
  stage             TEXT,
  status            TEXT,
  payload           JSONB,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS gal_batch_idx
  ON generation_audit_log (batch_id, created_at);

CREATE INDEX IF NOT EXISTS gal_stage_status_idx
  ON generation_audit_log (stage, status, created_at);


CREATE TABLE IF NOT EXISTS error_audit (
  err_id          BIGSERIAL   PRIMARY KEY,
  batch_id        TEXT,
  error_code      TEXT,
  error_message   TEXT,
  node_name       TEXT,
  payload         JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ea_batch_idx
  ON error_audit (batch_id, created_at);

CREATE INDEX IF NOT EXISTS ea_code_idx
  ON error_audit (error_code, created_at);


-- Coverage rollup so we can see topic/subtopic/difficulty distribution at a glance.
CREATE TABLE IF NOT EXISTS coverage_tracker (
  board          TEXT NOT NULL,
  class          TEXT NOT NULL,
  subject        TEXT NOT NULL,
  chapter        TEXT NOT NULL DEFAULT '',
  topic          TEXT NOT NULL DEFAULT '',
  subtopic       TEXT NOT NULL DEFAULT '',
  question_type  TEXT NOT NULL,
  difficulty     TEXT NOT NULL,
  good_count     INT  NOT NULL DEFAULT 0,
  upgrade_count  INT  NOT NULL DEFAULT 0,
  bad_count      INT  NOT NULL DEFAULT 0,
  last_updated   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (board, class, subject, chapter, topic, subtopic, question_type, difficulty)
);
