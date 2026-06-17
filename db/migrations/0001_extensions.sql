-- Question Generation v1.0 — required Postgres extensions.
-- Run once per database. Safe to re-run.

CREATE EXTENSION IF NOT EXISTS pgcrypto;     -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pg_trgm;      -- trigram similarity for deterministic dedup
CREATE EXTENSION IF NOT EXISTS unaccent;     -- accent-insensitive normalization
