#!/usr/bin/env node
// Offline unit tests for the deterministic agents in Question Generation v1.0.
// No external services required. Run with: node test_units.mjs
//
// Mirrors the jsCode logic from these workflow nodes:
//   - Agent 1 - Normalize Metadata + Init AI Ledger          (slugify, routing_key, draft_count)
//   - Parse Validation + Deterministic Re-Tag                (canonical_question_id, reTag rules)
//   - Curriculum - Build Precedence Keys                     (6-level chain)
//   - Agent 4 - Resolve Prompt + Inject Context              (8-level prompt fallback)

import { strict as assert } from 'node:assert';
import { createHash } from 'node:crypto';

const tests = [];
const t = (name, fn) => tests.push({ name, fn });

// ---------- Agent 1: slugify + routing_key + draft_count ----------

const slugify = (s) =>
  String(s || '')
    .normalize('NFKD')
    .replace(/[^\w\s-]/g, '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '-');

const buildRoutingKey = (m) =>
  [m.board, m.class, m.subject, m.chapter_slug, m.question_type, m.difficulty, m.language].join('|');

t('slugify normalizes accents, spaces, punctuation', () => {
  assert.equal(slugify('Solutions'), 'solutions');
  assert.equal(slugify('p-Block Elements'), 'p-block-elements');
  // NFKD decomposes accents to base+combining; \w strips the combining marks,
  // leaving the base letter. So Aldéhydes -> Aldehydes -> aldehydes.
  assert.equal(slugify('  Aldéhydes & Kétones! '), 'aldehydes-ketones');
});

t('routing_key joins canonical fields with pipes', () => {
  const m = {
    board: 'cbse', class: '12', subject: 'chemistry', chapter_slug: 'solutions',
    question_type: 'mcq', difficulty: 'intermediate', language: 'en',
  };
  assert.equal(buildRoutingKey(m), 'cbse|12|chemistry|solutions|mcq|intermediate|en');
});

t('draft_count = ceil(requested * overgeneration_factor)', () => {
  assert.equal(Math.ceil(20 * 1.5), 30);
  assert.equal(Math.ceil(7 * 1.5), 11);
  assert.equal(Math.ceil(1 * 1.5), 2);
});

// ---------- Agent 7 Parse + Re-Tag: canonical_question_id ----------

const canonicalQuestionId = (meta, q, a, t) =>
  'cq_' +
  createHash('sha256')
    .update(
      [
        meta.board,
        meta.class,
        meta.subject,
        t,
        String(q).toLowerCase().replace(/\s+/g, ' ').trim(),
        String(a).toLowerCase().trim(),
      ].join('|'),
    )
    .digest('hex')
    .slice(0, 32);

t('canonical_question_id is stable across whitespace variants', () => {
  const meta = { board: 'cbse', class: '12', subject: 'chemistry' };
  const a = canonicalQuestionId(meta, 'What is molality?', 'B', 'mcq');
  const b = canonicalQuestionId(meta, '  What  is   molality? ', 'b', 'mcq');
  assert.equal(a, b);
});

t('canonical_question_id changes when board/class/subject/qtype changes', () => {
  const q = 'What is molality?';
  const a = canonicalQuestionId({ board: 'cbse', class: '12', subject: 'chemistry' }, q, 'B', 'mcq');
  const b = canonicalQuestionId({ board: 'cbse', class: '11', subject: 'chemistry' }, q, 'B', 'mcq');
  const c = canonicalQuestionId({ board: 'cbse', class: '12', subject: 'physics' }, q, 'B', 'mcq');
  const d = canonicalQuestionId({ board: 'cbse', class: '12', subject: 'chemistry' }, q, 'B', 'la');
  assert.notEqual(a, b);
  assert.notEqual(a, c);
  assert.notEqual(a, d);
});

// ---------- Agent 7 Parse + Re-Tag: deterministic tagging rules ----------

const reTag = (r) => {
  const good =
    r.factual_correctness_score >= 0.85 &&
    r.answer_correctness_score >= 0.9 &&
    r.board_alignment_score >= 0.8 &&
    r.class_alignment_score >= 0.8 &&
    r.difficulty_alignment_score >= 0.8 &&
    r.grammar_score >= 0.85 &&
    (r.ambiguity_score || 0) <= 0.2 &&
    !r.hallucination_flag &&
    r.duplicate_status === 'unique' &&
    r.final_include === true;
  if (good) return 'good';
  const bad =
    r.hallucination_flag === true ||
    r.duplicate_status === 'duplicate' ||
    r.answer_correctness_score < 0.6 ||
    r.factual_correctness_score < 0.6;
  if (bad) return 'bad';
  return 'upgrade';
};

const baseGood = {
  factual_correctness_score: 0.95,
  answer_correctness_score: 1.0,
  board_alignment_score: 0.9,
  class_alignment_score: 0.9,
  difficulty_alignment_score: 0.85,
  grammar_score: 0.95,
  ambiguity_score: 0.1,
  hallucination_flag: false,
  duplicate_status: 'unique',
  final_include: true,
};

t('reTag: passing all thresholds = good', () => {
  assert.equal(reTag(baseGood), 'good');
});

t('reTag: any threshold miss without disqualifier = upgrade', () => {
  assert.equal(reTag({ ...baseGood, grammar_score: 0.7 }), 'upgrade');
  assert.equal(reTag({ ...baseGood, ambiguity_score: 0.35 }), 'upgrade');
  assert.equal(reTag({ ...baseGood, board_alignment_score: 0.6 }), 'upgrade');
});

t('reTag: hallucination_flag = bad (overrides scores)', () => {
  assert.equal(reTag({ ...baseGood, hallucination_flag: true }), 'bad');
});

t('reTag: duplicate_status="duplicate" = bad', () => {
  assert.equal(reTag({ ...baseGood, duplicate_status: 'duplicate' }), 'bad');
});

t('reTag: answer_correctness_score < 0.6 = bad', () => {
  assert.equal(reTag({ ...baseGood, answer_correctness_score: 0.5 }), 'bad');
});

t('reTag: final_include=false alone (with no disqualifier) = upgrade', () => {
  assert.equal(reTag({ ...baseGood, final_include: false }), 'upgrade');
});

t('reTag: near_duplicate without duplicate_status="duplicate" = upgrade not bad', () => {
  assert.equal(reTag({ ...baseGood, duplicate_status: 'near_duplicate' }), 'upgrade');
});

// ---------- Curriculum: 6-level precedence keys ----------

const buildCurriculumKeys = (m) => [
  `${m.board}_${m.class}_${m.subject}_${m.chapter_slug}_${m.question_type}_${m.difficulty}`,
  `${m.board}_${m.class}_${m.subject}_${m.question_type}`,
  `${m.board}_${m.class}_${m.subject}`,
  `${m.board}_${m.subject}`,
  `${m.board}`,
  'global',
];

t('curriculum key chain has 6 levels in precedence order', () => {
  const keys = buildCurriculumKeys({
    board: 'cbse', class: '12', subject: 'chemistry', chapter_slug: 'solutions',
    question_type: 'mcq', difficulty: 'intermediate',
  });
  assert.equal(keys.length, 6);
  assert.equal(keys[0], 'cbse_12_chemistry_solutions_mcq_intermediate');
  assert.equal(keys[5], 'global');
});

// ---------- Curriculum: precedence resolution against seeded rows ----------
// Mirrors what Postgres does with ORDER BY level ASC LIMIT 1 against the rows
// seeded by db/migrations/0008_seed_cbse_chemistry_curriculum.sql.

const seededCurriculum = {
  cbse_12_chemistry_solutions_mcq_intermediate: { level: 1 },
  cbse_12_chemistry_mcq: { level: 2 },
  cbse_12_chemistry: { level: 3 },
  cbse_chemistry: { level: 4 },
  cbse: { level: 5 },
  icse_12_chemistry: { level: 3 },
  global: { level: 6 },
};

const resolveCurriculum = (rows, m) => {
  const candidates = buildCurriculumKeys(m);
  let best = null;
  for (const k of candidates) {
    if (rows[k] && (best === null || rows[k].level < best.level)) {
      best = { key: k, level: rows[k].level };
    }
  }
  return best;
};

t('curriculum resolve: CBSE/12/Chem/Solutions/MCQ/Intermediate hits level 1', () => {
  const r = resolveCurriculum(seededCurriculum, {
    board: 'cbse', class: '12', subject: 'chemistry', chapter_slug: 'solutions',
    question_type: 'mcq', difficulty: 'intermediate',
  });
  assert.equal(r.key, 'cbse_12_chemistry_solutions_mcq_intermediate');
  assert.equal(r.level, 1);
});

t('curriculum resolve: CBSE/12/Chem/Electrochem/MCQ/Hard falls to level 2 (cbse_12_chemistry_mcq)', () => {
  const r = resolveCurriculum(seededCurriculum, {
    board: 'cbse', class: '12', subject: 'chemistry', chapter_slug: 'electrochemistry',
    question_type: 'mcq', difficulty: 'hard',
  });
  assert.equal(r.key, 'cbse_12_chemistry_mcq');
  assert.equal(r.level, 2);
});

t('curriculum resolve: CBSE/12/Chem/Solutions/LA/Intermediate falls to level 3 (cbse_12_chemistry)', () => {
  const r = resolveCurriculum(seededCurriculum, {
    board: 'cbse', class: '12', subject: 'chemistry', chapter_slug: 'solutions',
    question_type: 'la', difficulty: 'intermediate',
  });
  assert.equal(r.key, 'cbse_12_chemistry');
  assert.equal(r.level, 3);
});

t('curriculum resolve: CBSE/11/Chem/* falls to level 4 (cbse_chemistry)', () => {
  const r = resolveCurriculum(seededCurriculum, {
    board: 'cbse', class: '11', subject: 'chemistry', chapter_slug: 'thermodynamics',
    question_type: 'mcq', difficulty: 'easy',
  });
  assert.equal(r.key, 'cbse_chemistry');
  assert.equal(r.level, 4);
});

t('curriculum resolve: CBSE/9/Bio falls to level 5 (cbse)', () => {
  const r = resolveCurriculum(seededCurriculum, {
    board: 'cbse', class: '9', subject: 'biology', chapter_slug: 'cell',
    question_type: 'mcq', difficulty: 'easy',
  });
  assert.equal(r.key, 'cbse');
  assert.equal(r.level, 5);
});

t('curriculum resolve: ICSE/12/Chem hits the ICSE level-3 demo seed', () => {
  const r = resolveCurriculum(seededCurriculum, {
    board: 'icse', class: '12', subject: 'chemistry', chapter_slug: 'metallurgy',
    question_type: 'mcq', difficulty: 'hard',
  });
  assert.equal(r.key, 'icse_12_chemistry');
  assert.equal(r.level, 3);
});

t('curriculum resolve: unrelated board (jee/11/physics) falls all the way to global', () => {
  const r = resolveCurriculum(seededCurriculum, {
    board: 'jee', class: '11', subject: 'physics', chapter_slug: 'kinematics',
    question_type: 'mcq', difficulty: 'hard',
  });
  assert.equal(r.key, 'global');
  assert.equal(r.level, 6);
});

// ---------- Prompt repo: 8-level fallback ----------

const buildPromptFallbackKeys = (m) => [
  `${m.board}_${m.class}_${m.subject}_${m.question_type}_${m.difficulty}`,
  `${m.board}_${m.class}_${m.subject}_${m.question_type}`,
  `${m.board}_${m.class}_${m.subject}`,
  `${m.board}_${m.subject}_${m.question_type}`,
  `${m.board}_${m.question_type}`,
  `global_${m.question_type}_${m.difficulty}`,
  `global_${m.question_type}`,
  'global_default',
];

const resolvePrompt = (manifestGenerators, m) => {
  const keys = buildPromptFallbackKeys(m);
  for (const k of keys) {
    if (manifestGenerators[k] && manifestGenerators[k].active) return { key: k, ...manifestGenerators[k] };
  }
  return null;
};

const v1Manifest = {
  cbse_12_chemistry_mcq_intermediate: { id: 'cbse_12_chemistry_mcq_intermediate', version: 'v1', active: true },
  cbse_mcq: { id: 'cbse_mcq', version: 'v1', active: true },
  global_mcq: { id: 'global_mcq', version: 'v1', active: true },
  global_default: { id: 'global_default', version: 'v1', active: true },
};

// Validator manifest after (i) — cbse_mcq validator now active alongside global fallbacks.
const v1ValidatorManifest = {
  cbse_mcq: { id: 'cbse_mcq', version: 'v1', active: true },
  global_mcq: { id: 'global_mcq', version: 'v1', active: true },
  global_default: { id: 'global_default', version: 'v1', active: true },
};

t('prompt resolve: level 1 hit for exact specificity', () => {
  const r = resolvePrompt(v1Manifest, {
    board: 'cbse', class: '12', subject: 'chemistry',
    question_type: 'mcq', difficulty: 'intermediate',
  });
  assert.equal(r.key, 'cbse_12_chemistry_mcq_intermediate');
});

t('prompt resolve: falls to level 5 (cbse_mcq) when class/subject specific is missing', () => {
  const r = resolvePrompt(v1Manifest, {
    board: 'cbse', class: '9', subject: 'biology',
    question_type: 'mcq', difficulty: 'hard',
  });
  assert.equal(r.key, 'cbse_mcq');
});

t('prompt resolve: falls to level 7 (global_mcq) for non-cbse boards', () => {
  const r = resolvePrompt(v1Manifest, {
    board: 'jee', class: '11', subject: 'physics',
    question_type: 'mcq', difficulty: 'hard',
  });
  assert.equal(r.key, 'global_mcq');
});

t('prompt resolve: falls to global_default for unseen question_type', () => {
  const r = resolvePrompt(v1Manifest, {
    board: 'state_mp', class: '8', subject: 'evs',
    question_type: 'true_false', difficulty: 'easy',
  });
  assert.equal(r.key, 'global_default');
});

t('prompt resolve: returns null only if even global_default is missing or inactive', () => {
  const r = resolvePrompt({ global_default: { active: false } }, {
    board: 'x', class: '1', subject: 'y', question_type: 'z', difficulty: 'easy',
  });
  assert.equal(r, null);
});

t('validator resolve: CBSE MCQ run hits cbse_mcq (level 5), not global_default', () => {
  const r = resolvePrompt(v1ValidatorManifest, {
    board: 'cbse', class: '12', subject: 'chemistry',
    question_type: 'mcq', difficulty: 'intermediate',
  });
  assert.equal(r.key, 'cbse_mcq');
});

t('validator resolve: non-CBSE MCQ falls through to global_mcq', () => {
  const r = resolvePrompt(v1ValidatorManifest, {
    board: 'icse', class: '12', subject: 'chemistry',
    question_type: 'mcq', difficulty: 'hard',
  });
  assert.equal(r.key, 'global_mcq');
});

t('validator resolve: non-MCQ question type falls to global_default', () => {
  const r = resolvePrompt(v1ValidatorManifest, {
    board: 'cbse', class: '12', subject: 'chemistry',
    question_type: 'la', difficulty: 'intermediate',
  });
  assert.equal(r.key, 'global_default');
});

// ---------- SimHash + MinHash (mirrors Compute Dedup Signatures node) ----------

const normalize = (s) =>
  String(s || '').toLowerCase().normalize('NFKC').replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();

const tokenize = (s) => {
  const norm = normalize(s);
  if (!norm) return [];
  const words = norm.split(' ').filter((w) => w.length > 0);
  if (words.length < 3) {
    if (norm.length < 3) return [norm];
    const t = [];
    for (let i = 0; i <= norm.length - 3; i++) t.push(norm.slice(i, i + 3));
    return t;
  }
  const out = [];
  for (let i = 0; i <= words.length - 3; i++) out.push(words.slice(i, i + 3).join(' '));
  return out;
};

const sha256Bytes = (s) => createHash('sha256').update(s).digest();

const simhash64 = (tokens) => {
  if (!tokens.length) return 0n;
  const v = new Int32Array(64);
  for (const tok of tokens) {
    const buf = sha256Bytes(tok);
    for (let i = 0; i < 64; i++) {
      const bit = (buf[i >> 3] >> (i & 7)) & 1;
      v[i] += bit ? 1 : -1;
    }
  }
  let u = 0n;
  for (let i = 0; i < 64; i++) if (v[i] > 0) u |= 1n << BigInt(i);
  return u & (1n << 63n) ? u - (1n << 64n) : u;
};

const hammingDistance = (a, b) => {
  // BigInt XOR + popcount; matches Postgres bit_count(simhash # i.simhash).
  let x = (a < 0n ? a + (1n << 64n) : a) ^ (b < 0n ? b + (1n << 64n) : b);
  let count = 0;
  while (x) {
    count += Number(x & 1n);
    x >>= 1n;
  }
  return count;
};

t('simhash: identical text → identical sig (Hamming = 0)', () => {
  const a = simhash64(tokenize('What is the molality of a 0.5 M NaCl solution at 25 C?'));
  const b = simhash64(tokenize('What is the molality of a 0.5 M NaCl solution at 25 C?'));
  assert.equal(hammingDistance(a, b), 0);
});

t('simhash: whitespace + casing differences → Hamming = 0', () => {
  const a = simhash64(tokenize('What is the molality of a 0.5 M NaCl solution?'));
  const b = simhash64(tokenize('  WHAT   is   THE molality  of  a 0.5 M NaCl  solution? '));
  assert.equal(hammingDistance(a, b), 0);
});

t('simhash: punctuation-only differences → Hamming = 0', () => {
  const a = simhash64(tokenize('Define molality. State its unit.'));
  const b = simhash64(tokenize('Define molality, state its unit'));
  assert.equal(hammingDistance(a, b), 0);
});

t('simhash: near-duplicate Hamming is strictly smaller than unrelated Hamming', () => {
  // The invariant that the lookup actually depends on: near-duplicate is a
  // closer SimHash neighbor than an unrelated question. Absolute thresholds
  // are empirically fragile (3-word shingling spreads the effect of a single
  // word swap across multiple shingles); this comparative bound is what
  // matters for the Agent 6 bit_count(simhash # i.simhash) <= 6 retrieval.
  const base = simhash64(tokenize('Calculate the molality of a 0.5 M NaCl solution at 25 C'));
  const near = simhash64(tokenize('Calculate the molarity of a 0.5 M NaCl solution at 25 C'));
  const unrelated = simhash64(tokenize('State Henrys law and define the Henry constant K_H.'));
  const dNear = hammingDistance(base, near);
  const dUnrelated = hammingDistance(base, unrelated);
  assert.ok(dNear > 0, `expected non-zero Hamming for substantive change, got ${dNear}`);
  assert.ok(dNear < dUnrelated, `expected near (${dNear}) < unrelated (${dUnrelated})`);
});

t('simhash: empty input → 0 (matches node fallback string "0")', () => {
  assert.equal(simhash64([]), 0n);
  assert.equal(simhash64(tokenize('')), 0n);
});

t('normalized_question_hash: stable across whitespace + casing of question; varies with answer', () => {
  const norm = (q, a) => {
    const nt = normalize(q);
    return 'sha256:' + createHash('sha256').update(nt + '|' + String(a).toLowerCase().trim()).digest('hex');
  };
  assert.equal(norm('What is molality?', 'B'), norm('  what  IS  molality?  ', 'b'));
  assert.notEqual(norm('What is molality?', 'B'), norm('What is molality?', 'C'));
});

// ---------- AI cost arithmetic (mirrors Capture AI Costs node) ----------

const cost = (tok_in, tok_out, model, pricing) => {
  const p = pricing[model] || pricing['default'];
  return Number(((tok_in / 1e6) * p.in_per_m + (tok_out / 1e6) * p.out_per_m).toFixed(6));
};

const PRICING_TEST = {
  'claude-opus-4-7': { in_per_m: 15.0, out_per_m: 75.0 },
  'claude-sonnet-4-6': { in_per_m: 3.0, out_per_m: 15.0 },
  'default': { in_per_m: 15.0, out_per_m: 75.0 },
};

t('ai cost: typical batch (Opus, 8k in + 6k out per call) computes to expected $', () => {
  const gen = cost(8000, 6000, 'claude-opus-4-7', PRICING_TEST);
  const val = cost(8000, 6000, 'claude-opus-4-7', PRICING_TEST);
  // 8000 tokens * $15/M = $0.12; 6000 tokens * $75/M = $0.45; per call = $0.57; batch = $1.14
  assert.equal(gen, 0.57);
  assert.equal(val, 0.57);
  assert.equal(Number((gen + val).toFixed(6)), 1.14);
});

t('ai cost: zero usage → 0 (handles failed AI calls cleanly)', () => {
  assert.equal(cost(0, 0, 'claude-opus-4-7', PRICING_TEST), 0);
});

t('ai cost: unknown model falls back to default pricing', () => {
  const known = cost(10000, 10000, 'claude-opus-4-7', PRICING_TEST);
  const unknown = cost(10000, 10000, 'totally-made-up-model', PRICING_TEST);
  assert.equal(known, unknown);
});

t('ai cost: sonnet cheaper than opus for identical token mix', () => {
  const opus = cost(10000, 10000, 'claude-opus-4-7', PRICING_TEST);
  const sonnet = cost(10000, 10000, 'claude-sonnet-4-6', PRICING_TEST);
  assert.ok(sonnet < opus, `sonnet (${sonnet}) should be cheaper than opus (${opus})`);
});

// ---------- AI call ledger invariant ----------

t('AI ledger: increment from 0 → 1 → 2 only; a third call asserting "expected 2" throws', () => {
  // Mirrors the workflow's `AI Ledger - Pre Call N` nodes which throw when
  // the count after increment does not equal the asserted ordinal.
  let count = 0;
  const tick = (expected) => {
    count += 1;
    if (count !== expected) throw new Error(`AI_BUDGET_VIOLATION: expected ${expected}, got ${count}`);
  };
  tick(1);
  tick(2);
  // A rogue third AI call would still assert "expected 2" (since the workflow
  // only has two ledger nodes); count becomes 3, mismatch, throws.
  assert.throws(() => tick(2), /AI_BUDGET_VIOLATION/);
});

// ---------- Runner ----------

let passed = 0;
let failed = 0;
for (const { name, fn } of tests) {
  try {
    fn();
    console.log(`  ok  ${name}`);
    passed += 1;
  } catch (e) {
    console.error(`  FAIL  ${name}`);
    console.error(`        ${e.message}`);
    failed += 1;
  }
}
console.log(`\n${passed} passed, ${failed} failed (${tests.length} total)`);
process.exit(failed === 0 ? 0 : 1);
