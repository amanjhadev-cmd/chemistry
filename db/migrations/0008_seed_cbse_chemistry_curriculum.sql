-- Seed CBSE / Class 12 / Chemistry curriculum_rules overrides across 5 precedence
-- levels so the Curriculum - DB Lookup demonstrably resolves to the most specific
-- matching row instead of falling through to the global default.
--
-- Idempotent: ON CONFLICT (match_key, version) DO NOTHING.
--
-- After applying, a (cbse, 12, chemistry, solutions, mcq, intermediate) submission
-- will resolve at level 1 (`cbse_12_chemistry_solutions_mcq_intermediate`).
-- Removing that one row drops resolution to level 2 (cbse_12_chemistry_mcq),
-- and so on down the chain. This is how onboarding new boards/classes/subjects
-- works without touching the workflow.

-- Level 5 — `cbse` (any CBSE subject/class/qtype/difficulty)
INSERT INTO curriculum_rules (level, match_key, version, active, body) VALUES (
  5, 'cbse', 1, TRUE,
  jsonb_build_object(
    'marks',                jsonb_build_object('min', 1, 'max', 5),
    'answer_length',        jsonb_build_object('min_words', 0, 'max_words', 250),
    'bloom_levels_allowed', jsonb_build_array('remember','understand','apply','analyze'),
    'cognitive_level',      'intermediate',
    'style',                'ncert_aligned',
    'forbidden_patterns',   jsonb_build_array(
                              'all of the above',
                              'none of the above',
                              'both A and B',
                              'both A and C',
                              'A and B only',
                              'all of the following except'
                            ),
    'options_count_for_mcq', 4,
    'terminology', jsonb_build_object(
      'prefer', jsonb_build_array('SI units','NCERT terminology'),
      'avoid',  jsonb_build_array('CGS units','colloquial phrasing')
    ),
    'competency_tags', jsonb_build_array('conceptual_understanding','application'),
    'notes', 'CBSE board baseline. Follows NCERT textbook conventions.'
  )
)
ON CONFLICT (match_key, version) DO NOTHING;

-- Level 4 — `cbse_chemistry` (all CBSE Chemistry)
INSERT INTO curriculum_rules (level, match_key, version, active, body) VALUES (
  4, 'cbse_chemistry', 1, TRUE,
  jsonb_build_object(
    'marks',                jsonb_build_object('min', 1, 'max', 5),
    'answer_length',        jsonb_build_object('min_words', 0, 'max_words', 250),
    'bloom_levels_allowed', jsonb_build_array('remember','understand','apply','analyze'),
    'cognitive_level',      'intermediate',
    'style',                'ncert_aligned',
    'forbidden_patterns',   jsonb_build_array(
                              'all of the above','none of the above',
                              'both A and B','both A and C','A and B only',
                              'common name only when IUPAC differs'
                            ),
    'options_count_for_mcq', 4,
    'terminology', jsonb_build_object(
      'prefer', jsonb_build_array(
        'IUPAC nomenclature',
        'SI units (mol, kg, K, Pa)',
        'state symbols (s), (l), (g), (aq)',
        'chemical formula over common name'
      ),
      'avoid', jsonb_build_array(
        'trivial names without IUPAC equivalent',
        'colloquial chemistry terms'
      )
    ),
    'competency_tags', jsonb_build_array('chemical_reasoning','quantitative_chemistry','laboratory_intuition'),
    'notes', 'CBSE Chemistry. Always prefer IUPAC + SI. Show units in stems and options when numerical.'
  )
)
ON CONFLICT (match_key, version) DO NOTHING;

-- Level 3 — `cbse_12_chemistry` (CBSE Class 12 Chemistry, any chapter/qtype)
INSERT INTO curriculum_rules (level, match_key, version, active, body) VALUES (
  3, 'cbse_12_chemistry', 1, TRUE,
  jsonb_build_object(
    'marks',                jsonb_build_object('min', 1, 'max', 5),
    'answer_length',        jsonb_build_object('min_words', 0, 'max_words', 250),
    'bloom_levels_allowed', jsonb_build_array('understand','apply','analyze','evaluate'),
    'cognitive_level',      'intermediate',
    'style',                'ncert_class12_aligned',
    'forbidden_patterns',   jsonb_build_array(
                              'all of the above','none of the above',
                              'both A and B','both A and C','A and B only'
                            ),
    'options_count_for_mcq', 4,
    'terminology', jsonb_build_object(
      'prefer', jsonb_build_array(
        'IUPAC nomenclature','SI units',
        'NCERT Class 12 Chemistry (Parts 1 and 2) conventions'
      ),
      'avoid', jsonb_build_array('pre-Class-11 simplifications')
    ),
    'competency_tags', jsonb_build_array(
      'application','multi_step_reasoning','quantitative_chemistry','reaction_prediction'
    ),
    'syllabus_reference', 'NCERT Chemistry Class 12 Part 1 + Part 2 (2024-25)',
    'notes', 'Class 12 Chemistry. Drop pure-recall items, lean apply/analyze. Allow evaluate for HOTS.'
  )
)
ON CONFLICT (match_key, version) DO NOTHING;

-- Level 2 — `cbse_12_chemistry_mcq` (CBSE Class 12 Chemistry MCQ specifically)
INSERT INTO curriculum_rules (level, match_key, version, active, body) VALUES (
  2, 'cbse_12_chemistry_mcq', 1, TRUE,
  jsonb_build_object(
    'marks',                jsonb_build_object('min', 1, 'max', 1),
    'answer_length',        jsonb_build_object('min_words', 0, 'max_words', 5),
    'bloom_levels_allowed', jsonb_build_array('understand','apply','analyze'),
    'cognitive_level',      'intermediate',
    'style',                'cbse_sample_paper_mcq',
    'forbidden_patterns',   jsonb_build_array(
                              'all of the above','none of the above',
                              'both A and B','both A and C','A and B only',
                              'A, B and C'
                            ),
    'options_count_for_mcq', 4,
    'distractor_strategy', jsonb_build_array(
      'common Class 12 misconception (e.g. molarity vs molality)',
      'wrong-unit version of the right answer',
      'result of using wrong formula',
      'sign or order-of-magnitude error'
    ),
    'terminology', jsonb_build_object(
      'prefer', jsonb_build_array('IUPAC','SI units','chemical formula'),
      'avoid',  jsonb_build_array('vague qualifiers like roughly, approximately')
    ),
    'competency_tags', jsonb_build_array('application','quantitative_chemistry'),
    'notes', 'CBSE Class 12 Chemistry MCQ. 1 mark, single best answer, 4 options, equal-length distractors.'
  )
)
ON CONFLICT (match_key, version) DO NOTHING;

-- Level 1 — `cbse_12_chemistry_solutions_mcq_intermediate` (full specificity, chapter-aware)
INSERT INTO curriculum_rules (level, match_key, version, active, body) VALUES (
  1, 'cbse_12_chemistry_solutions_mcq_intermediate', 1, TRUE,
  jsonb_build_object(
    'marks',                jsonb_build_object('min', 1, 'max', 1),
    'answer_length',        jsonb_build_object('min_words', 0, 'max_words', 5),
    'bloom_levels_allowed', jsonb_build_array('understand','apply','analyze'),
    'cognitive_level',      'intermediate',
    'style',                'cbse_solutions_chapter_intermediate',
    'forbidden_patterns',   jsonb_build_array(
                              'all of the above','none of the above',
                              'both A and B','both A and C','A and B only',
                              'pure recall of definitions'
                            ),
    'options_count_for_mcq', 4,
    'chapter_focus', jsonb_build_object(
      'chapter_name', 'Solutions',
      'expected_concepts', jsonb_build_array(
        'molality vs molarity (temperature dependence)',
        'mole fraction',
        'mass percentage',
        'Henrys law (K_H, partial pressure)',
        'Raoults law (ideal vs non-ideal)',
        'colligative properties (delta T_b, delta T_f, osmotic pressure)',
        'vant Hoff factor (association, dissociation)'
      ),
      'expected_numerical_skills', jsonb_build_array(
        '1-step calculation with single unit conversion',
        'apply a single colligative formula',
        'identify the right concentration unit for the question'
      )
    ),
    'item_shape', jsonb_build_array(
      'apply a 2-step concept (e.g. molality then boiling-point elevation)',
      '1-step numerical requiring one unit conversion OR one formula substitution',
      'compare two related quantities (e.g. which has higher delta T_b)'
    ),
    'reject_if', jsonb_build_array(
      'pure recall of a definition (too easy)',
      'requires 3+ reasoning steps (too hard)',
      'requires graphical interpretation unless visual is attached'
    ),
    'distractor_strategy', jsonb_build_array(
      'molarity instead of molality (or vice versa)',
      'forgetting to convert grams to mol',
      'forgetting the K_b / K_f value or applying wrong constant',
      'mixing up partial pressure and total pressure'
    ),
    'terminology', jsonb_build_object(
      'prefer', jsonb_build_array(
        'molality (mol/kg)','molarity (mol/L)','mole fraction (x)',
        'partial pressure (p)','Henry constant (K_H)',
        'ebullioscopic constant (K_b)','cryoscopic constant (K_f)',
        'vant Hoff factor (i)'
      ),
      'avoid', jsonb_build_array('strength','concentration without unit context')
    ),
    'competency_tags', jsonb_build_array(
      'colligative_reasoning','quantitative_chemistry','application'
    ),
    'syllabus_reference', 'NCERT Class 12 Chemistry Part 1, Chapter 1: Solutions',
    'notes', 'Most-specific CBSE Class 12 Chemistry Solutions intermediate MCQ. Resolves at level 1.'
  )
)
ON CONFLICT (match_key, version) DO NOTHING;

-- Bonus: a single ICSE Class 12 Chemistry level-3 seed so the precedence chain is
-- visibly demoable for a second board. Keeps the same NCERT-style core with an
-- ICSE-specific style marker.
INSERT INTO curriculum_rules (level, match_key, version, active, body) VALUES (
  3, 'icse_12_chemistry', 1, TRUE,
  jsonb_build_object(
    'marks',                jsonb_build_object('min', 1, 'max', 5),
    'answer_length',        jsonb_build_object('min_words', 0, 'max_words', 250),
    'bloom_levels_allowed', jsonb_build_array('understand','apply','analyze','evaluate'),
    'cognitive_level',      'intermediate',
    'style',                'icse_isc_aligned',
    'forbidden_patterns',   jsonb_build_array('all of the above','none of the above'),
    'options_count_for_mcq', 4,
    'terminology', jsonb_build_object(
      'prefer', jsonb_build_array('IUPAC nomenclature','SI units','ISC textbook conventions'),
      'avoid', jsonb_build_array()
    ),
    'syllabus_reference', 'ISC Class 12 Chemistry (CISCE)',
    'notes', 'ICSE/ISC Class 12 Chemistry baseline.'
  )
)
ON CONFLICT (match_key, version) DO NOTHING;
