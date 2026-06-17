-- Curriculum rules engine: deterministic, config-driven lookup with hierarchical fallback.
-- Precedence levels (lower = more specific, wins first):
--   1 = board|class|subject|chapter|qtype|difficulty
--   2 = board|class|subject|qtype
--   3 = board|class|subject
--   4 = board|subject
--   5 = board
--   6 = global

CREATE TABLE IF NOT EXISTS curriculum_rules (
  id          BIGSERIAL    PRIMARY KEY,
  level       SMALLINT     NOT NULL CHECK (level BETWEEN 1 AND 6),
  match_key   TEXT         NOT NULL,
  version     INT          NOT NULL DEFAULT 1,
  active      BOOLEAN      NOT NULL DEFAULT TRUE,
  body        JSONB        NOT NULL,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE (match_key, version)
);

CREATE INDEX IF NOT EXISTS curriculum_rules_active_idx
  ON curriculum_rules (match_key)
  WHERE active;

CREATE INDEX IF NOT EXISTS curriculum_rules_level_idx
  ON curriculum_rules (level, active);

-- Global default rule so the workflow always resolves SOMETHING.
INSERT INTO curriculum_rules (level, match_key, version, active, body)
VALUES (
  6,
  'global',
  1,
  TRUE,
  jsonb_build_object(
    'resolution',           jsonb_build_object('level', 6, 'key', 'global'),
    'marks',                jsonb_build_object('min', 1, 'max', 5),
    'answer_length',        jsonb_build_object('min_words', 0, 'max_words', 200),
    'bloom_levels_allowed', jsonb_build_array('remember','understand','apply','analyze'),
    'cognitive_level',      'intermediate',
    'style',                'aligned',
    'forbidden_patterns',   jsonb_build_array('all of the above','none of the above'),
    'options_count_for_mcq', 4
  )
)
ON CONFLICT (match_key, version) DO NOTHING;
