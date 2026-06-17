-- Knowledge Base cache: skip Agent 3 PDF extraction on repeat submissions
-- of the same PDF (same sha256 hash + extractor version).

CREATE TABLE IF NOT EXISTS kb_cache (
  pdf_hash            TEXT        NOT NULL,
  extractor_version   TEXT        NOT NULL,
  chapter_knowledge   JSONB       NOT NULL,
  extraction_quality  NUMERIC,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (pdf_hash, extractor_version)
);

CREATE INDEX IF NOT EXISTS kb_cache_created_at_idx ON kb_cache (created_at);
