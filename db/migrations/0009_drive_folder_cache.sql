-- Drive folder ID cache.
--
-- The Drive Folder Resolver Code node creates the per-batch folder hierarchy
-- (QuestionBank/{board}/{class}/{subject}/{chapter_slug}/{question_type}/{difficulty}/{batch_id}/)
-- by walking and search-or-creating each segment via the Google Drive REST API.
--
-- v1 of the resolver does NOT use this cache yet — it's seeded for the v2
-- optimization where the resolver short-circuits known-path lookups (folders
-- like QuestionBank/cbse/12/chemistry/solutions/mcq/intermediate get reused
-- across batches; only the leaf {batch_id} folder is genuinely new).
--
-- Once wired in, the resolver should:
--   1. Try a single SELECT by `path` for the longest prefix it can find.
--   2. Walk only the un-cached tail segments via Drive API.
--   3. Insert each newly-created segment back into this table.
--   4. UPDATE last_used_at on every cache hit (cheap, helps eviction policy).

CREATE TABLE IF NOT EXISTS drive_folder_cache (
  path           TEXT        PRIMARY KEY,
  parent_id      TEXT,
  folder_id      TEXT        NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS dfc_last_used_idx ON drive_folder_cache (last_used_at);
CREATE INDEX IF NOT EXISTS dfc_parent_idx ON drive_folder_cache (parent_id);
