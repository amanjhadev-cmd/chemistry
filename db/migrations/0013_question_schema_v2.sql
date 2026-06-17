-- Question schema v2 - new output JSON shape requirements.
--
-- New fields on questions_master (and the two non-approved bucket tables):
--   chapter_no, chapter_uuid          - identifies the chapter at structured ids
--   concept_no, concept_uuid,         - the AI-mapped concept per question
--     concept_name
--   question_category                 - NUMERICAL | THEORETICAL
--   question_mark                     - proposed marks (integer)
--   bloom                             - array of {bloom_level, bloom_priority}
--                                       priority is 1 or 2 only
--   subject_code                      - canonical short code (MATHS, CHEM, ...)
--   subject_display_name              - friendly label (Maths, Chemistry, ...)
--   standard                          - e.g. "10th"
--   category_choices                  - e.g. "K-12", "Competitive"
--   generation_version                - prompt+pipeline generation version
--   final_answer_text                 - hint or exact answer text (HTML allowed)
--   question_diagram_url              - S3/Drive URL of attached diagram, if any
--   question_text_html                - rendered HTML with KaTeX (separate from
--                                       the raw question_text we already store)
--   correct_options                   - JSONB array, e.g. [{"option_number":"A"}]
--   question_no_in_batch              - sequence number within the batch (1..N)
--
-- All additions are nullable so existing rows survive untouched. Backfill is
-- only meaningful for new generations (v2+).

ALTER TABLE questions_master
  ADD COLUMN IF NOT EXISTS chapter_no             INT,
  ADD COLUMN IF NOT EXISTS chapter_uuid           TEXT,
  ADD COLUMN IF NOT EXISTS concept_no             INT,
  ADD COLUMN IF NOT EXISTS concept_uuid           TEXT,
  ADD COLUMN IF NOT EXISTS concept_name           TEXT,
  ADD COLUMN IF NOT EXISTS question_category      TEXT,
  ADD COLUMN IF NOT EXISTS question_mark          INT,
  ADD COLUMN IF NOT EXISTS bloom                  JSONB,
  ADD COLUMN IF NOT EXISTS subject_code           TEXT,
  ADD COLUMN IF NOT EXISTS subject_display_name   TEXT,
  ADD COLUMN IF NOT EXISTS standard               TEXT,
  ADD COLUMN IF NOT EXISTS category_choices       TEXT,
  ADD COLUMN IF NOT EXISTS generation_version     TEXT,
  ADD COLUMN IF NOT EXISTS final_answer_text      TEXT,
  ADD COLUMN IF NOT EXISTS question_diagram_url   TEXT,
  ADD COLUMN IF NOT EXISTS question_text_html     TEXT,
  ADD COLUMN IF NOT EXISTS correct_options        JSONB,
  ADD COLUMN IF NOT EXISTS question_no_in_batch   INT;

ALTER TABLE review_queue
  ADD COLUMN IF NOT EXISTS chapter_no             INT,
  ADD COLUMN IF NOT EXISTS chapter_uuid           TEXT,
  ADD COLUMN IF NOT EXISTS concept_no             INT,
  ADD COLUMN IF NOT EXISTS concept_uuid           TEXT,
  ADD COLUMN IF NOT EXISTS concept_name           TEXT,
  ADD COLUMN IF NOT EXISTS question_category      TEXT,
  ADD COLUMN IF NOT EXISTS question_mark          INT,
  ADD COLUMN IF NOT EXISTS bloom                  JSONB,
  ADD COLUMN IF NOT EXISTS subject_code           TEXT,
  ADD COLUMN IF NOT EXISTS subject_display_name   TEXT,
  ADD COLUMN IF NOT EXISTS standard               TEXT,
  ADD COLUMN IF NOT EXISTS category_choices       TEXT,
  ADD COLUMN IF NOT EXISTS generation_version     TEXT,
  ADD COLUMN IF NOT EXISTS final_answer_text      TEXT,
  ADD COLUMN IF NOT EXISTS question_diagram_url   TEXT,
  ADD COLUMN IF NOT EXISTS question_text_html     TEXT,
  ADD COLUMN IF NOT EXISTS correct_options        JSONB,
  ADD COLUMN IF NOT EXISTS question_no_in_batch   INT;

ALTER TABLE rejected_questions
  ADD COLUMN IF NOT EXISTS chapter_no             INT,
  ADD COLUMN IF NOT EXISTS chapter_uuid           TEXT,
  ADD COLUMN IF NOT EXISTS concept_no             INT,
  ADD COLUMN IF NOT EXISTS concept_uuid           TEXT,
  ADD COLUMN IF NOT EXISTS concept_name           TEXT,
  ADD COLUMN IF NOT EXISTS question_category      TEXT,
  ADD COLUMN IF NOT EXISTS question_mark          INT,
  ADD COLUMN IF NOT EXISTS bloom                  JSONB,
  ADD COLUMN IF NOT EXISTS subject_code           TEXT,
  ADD COLUMN IF NOT EXISTS subject_display_name   TEXT,
  ADD COLUMN IF NOT EXISTS standard               TEXT,
  ADD COLUMN IF NOT EXISTS category_choices       TEXT,
  ADD COLUMN IF NOT EXISTS generation_version     TEXT,
  ADD COLUMN IF NOT EXISTS final_answer_text      TEXT,
  ADD COLUMN IF NOT EXISTS question_diagram_url   TEXT,
  ADD COLUMN IF NOT EXISTS question_text_html     TEXT,
  ADD COLUMN IF NOT EXISTS correct_options        JSONB,
  ADD COLUMN IF NOT EXISTS question_no_in_batch   INT;

-- Indexes for the new identifier columns we'll search by.
CREATE INDEX IF NOT EXISTS qm_concept_idx  ON questions_master   (concept_uuid);
CREATE INDEX IF NOT EXISTS qm_chapter_idx  ON questions_master   (chapter_uuid);
CREATE INDEX IF NOT EXISTS rvq_concept_idx ON review_queue       (concept_uuid);
CREATE INDEX IF NOT EXISTS rjq_concept_idx ON rejected_questions (concept_uuid);


-- ---- chapter_concepts: the pre-defined concept catalogue ----
--
-- Operators load (board, class, subject, chapter) tuples with their concepts
-- here. The workflow's `Load Chapter Concepts` node selects the matching
-- concept list, passes it to AI Call 1 as part of the generator prompt, and
-- AI Call 1 returns each draft with the concept_no it mapped to.

CREATE TABLE IF NOT EXISTS chapter_concepts (
  id              BIGSERIAL   PRIMARY KEY,
  board           TEXT        NOT NULL,
  class           TEXT        NOT NULL,
  subject         TEXT        NOT NULL,
  chapter_slug    TEXT        NOT NULL,
  chapter_no      INT,
  chapter_uuid    TEXT        NOT NULL,
  concept_no      INT         NOT NULL,
  concept_uuid    TEXT        NOT NULL,
  concept_name    TEXT        NOT NULL,
  notes           TEXT,
  active          BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (board, class, subject, chapter_slug, concept_no),
  UNIQUE (concept_uuid)
);

CREATE INDEX IF NOT EXISTS cc_scope_idx ON chapter_concepts (board, class, subject, chapter_slug) WHERE active;


-- Example seed: ICSE Class 10 Maths "Real Numbers" with 3 concepts, mirroring
-- the user's reference JSON. Real deployments will INSERT many more rows.

INSERT INTO chapter_concepts
  (board, class, subject, chapter_slug, chapter_no, chapter_uuid,
   concept_no, concept_uuid, concept_name)
VALUES
  ('icse','10','maths','real-numbers', 1, 'chapter-real-numbers-icse-10-v1',
   1, 'concept-irrational-numbers-v1',    'Irrational numbers'),
  ('icse','10','maths','real-numbers', 1, 'chapter-real-numbers-icse-10-v1',
   2, 'concept-decimal-expansion-v1',     'Decimal expansion of rationals'),
  ('icse','10','maths','real-numbers', 1, 'chapter-real-numbers-icse-10-v1',
   3, 'concept-euclids-division-lemma-v1','Euclid''s division lemma')
ON CONFLICT (board, class, subject, chapter_slug, concept_no) DO NOTHING;

-- A CBSE Class 12 Chemistry "Solutions" sample so the existing curriculum seeds
-- + smoke test stay functional with the new concept mapping.

INSERT INTO chapter_concepts
  (board, class, subject, chapter_slug, chapter_no, chapter_uuid,
   concept_no, concept_uuid, concept_name)
VALUES
  ('cbse','12','chemistry','solutions', 1, 'chapter-solutions-cbse-12-v1',
   1, 'concept-types-of-solutions-v1',         'Types of solutions'),
  ('cbse','12','chemistry','solutions', 1, 'chapter-solutions-cbse-12-v1',
   2, 'concept-concentration-expression-v1',   'Expressing concentration (molality, molarity, mole fraction)'),
  ('cbse','12','chemistry','solutions', 1, 'chapter-solutions-cbse-12-v1',
   3, 'concept-solubility-v1',                 'Solubility'),
  ('cbse','12','chemistry','solutions', 1, 'chapter-solutions-cbse-12-v1',
   4, 'concept-henrys-law-v1',                 'Henry''s law'),
  ('cbse','12','chemistry','solutions', 1, 'chapter-solutions-cbse-12-v1',
   5, 'concept-raoults-law-v1',                'Raoult''s law'),
  ('cbse','12','chemistry','solutions', 1, 'chapter-solutions-cbse-12-v1',
   6, 'concept-colligative-properties-v1',     'Colligative properties'),
  ('cbse','12','chemistry','solutions', 1, 'chapter-solutions-cbse-12-v1',
   7, 'concept-vant-hoff-factor-v1',           'van''t Hoff factor (abnormal molar masses)')
ON CONFLICT (board, class, subject, chapter_slug, concept_no) DO NOTHING;


-- ---- Rename existing curriculum 'intermediate' difficulty rows to 'medium' ----
-- The v2 schema uses LEVEL_MEDIUM. Internal routing keys use the lowercase
-- form; we rename the existing seed accordingly. Idempotent.

UPDATE curriculum_rules
SET match_key = replace(match_key, '_intermediate', '_medium')
WHERE match_key LIKE '%_intermediate'
  AND NOT EXISTS (
    SELECT 1 FROM curriculum_rules cr2
    WHERE cr2.match_key = replace(curriculum_rules.match_key, '_intermediate', '_medium')
  );

-- ---- subject_code lookup view ----
--
-- A simple mapping from our slugified subject ("chemistry") to the canonical
-- short code ("CHEM") and display name ("Chemistry"). Used by the workflow's
-- output formatter. Add rows here as new subjects are onboarded.

CREATE TABLE IF NOT EXISTS subject_codes (
  subject              TEXT PRIMARY KEY,
  subject_code         TEXT NOT NULL,
  subject_display_name TEXT NOT NULL
);

INSERT INTO subject_codes (subject, subject_code, subject_display_name) VALUES
  ('chemistry', 'CHEM',    'Chemistry'),
  ('maths',     'MATHS',   'Maths'),
  ('physics',   'PHYSICS', 'Physics'),
  ('biology',   'BIO',     'Biology'),
  ('english',   'ENG',     'English'),
  ('science',   'SCIENCE', 'Science'),
  ('evs',       'EVS',     'Environmental Studies')
ON CONFLICT (subject) DO NOTHING;
