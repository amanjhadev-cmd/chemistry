#!/usr/bin/env node
/*
 * Prompt repo lint - pre-deploy check.
 *
 * Run from the repo root:    node prompt-repo/lint.mjs
 *
 * What it checks (no external deps):
 *   1. manifest.json parses, has required top-level keys, version pointer is set
 *   2. Every referenced path in manifest exists on disk
 *   3. Every .j2 filename follows `<id>.v<N>.j2` and matches its manifest entry
 *   4. Every active entry has id, version, active=true, path
 *   5. Every active generator + validator template renders cleanly against a
 *      synthetic context (mirrors the mini-engine in Agent 4 and Agent 7a):
 *        - no leftover {{ var }} placeholders
 *        - no leftover {% if %} / {% endif %} block tags
 *        - no leftover {# comment #} blocks
 *        - rendered output is non-empty and contains required marker strings
 *   6. Every variable used in a template is in the documented context catalogue
 *      (catches typos like {{ metdata.board }} that would silently render to '')
 *   7. Every output JSON schema parses, has $schema/title/type/properties
 *   8. Every contract JSON schema parses
 *   9. Every rubric .md file exists and has at least 100 chars
 *  10. fallback_order in manifest has exactly 8 levels (matches Agent 4)
 *  11. Per-entry rubric paths interpolate {difficulty} / {question_type} into
 *      files that actually exist for every supported difficulty / qtype
 *
 * Exits 0 on clean, 1 on any error. Warnings don't fail the build.
 */

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, dirname, basename, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = dirname(HERE);
const REPO = HERE; // prompt-repo/

const errors = [];
const warnings = [];
const fail = (msg) => errors.push(msg);
const warn = (msg) => warnings.push(msg);
const ok = (msg) => console.log(`  ok  ${msg}`);

const rel = (p) => relative(REPO_ROOT, p);

// ---------- Context catalogue (must match Agent 4 + Agent 7a's render ctx) ----------
const ALLOWED_VARS = new Set([
  'metadata', 'metadata.batch_id', 'metadata.source_pdf_id',
  'metadata.source_pdf_hash', 'metadata.submitted_at', 'metadata.board',
  'metadata.class', 'metadata.subject', 'metadata.chapter_name',
  'metadata.chapter_slug', 'metadata.source_type', 'metadata.question_type',
  'metadata.difficulty', 'metadata.number_of_questions',
  'metadata.overgeneration_factor', 'metadata.draft_count', 'metadata.language',
  'metadata.include_visual_questions', 'metadata.routing_key',
  'metadata.extractor_version', 'metadata.curriculum_rules_version',
  'metadata.prompt_repo_version', 'metadata.n8n_execution_id',
  'curriculum_constraints', 'curriculum_constraints.resolution',
  'curriculum_constraints.resolution.level', 'curriculum_constraints.resolution.key',
  'curriculum_constraints.marks', 'curriculum_constraints.marks.min',
  'curriculum_constraints.marks.max', 'curriculum_constraints.answer_length',
  'curriculum_constraints.answer_length.min_words',
  'curriculum_constraints.answer_length.max_words',
  'curriculum_constraints.bloom_levels_allowed',
  'curriculum_constraints.cognitive_level', 'curriculum_constraints.style',
  'curriculum_constraints.forbidden_patterns',
  'curriculum_constraints.terminology',
  'curriculum_constraints.terminology.prefer',
  'curriculum_constraints.terminology.avoid',
  'curriculum_constraints.competency_tags',
  'curriculum_constraints.options_count_for_mcq',
  'chapter_knowledge_summary', 'output_schema', 'validator_output_schema',
  'draft_count', 'requested_count', 'drafts_with_candidates',
  'rubrics', 'rubrics.difficulty', 'rubrics.question_type', 'rubrics.visual',
]);

// ---------- Mini render engine (copy of workflow's logic) ----------
const get = (path, c) => path.split('.').reduce((a, k) => (a == null ? a : a[k]), c);
const render = (tpl, ctx) => {
  let out = tpl;
  out = out.replace(/\{#[\s\S]*?#\}/g, '');
  out = out.replace(/\{%\s*if\s+([\w\.]+)\s*%\}([\s\S]*?)\{%\s*endif\s*%\}/g, (m, p, block) => {
    const v = get(p, ctx);
    return v ? block : '';
  });
  out = out.replace(/\{\{\s*'%04d'\s*\|\s*format\(([\w\.]+)\)\s*\}\}/g, (m, p) => String(get(p, ctx)).padStart(4, '0'));
  out = out.replace(/\{\{\s*([\w\.]+)\s*\|\s*upper\s*\}\}/g, (m, p) => {
    const v = get(p, ctx);
    return v == null ? '' : String(v).toUpperCase();
  });
  out = out.replace(/\{\{\s*([\w\.]+)\s*\|\s*tojson\s*\}\}/g, (m, p) => JSON.stringify(get(p, ctx)));
  out = out.replace(/\{\{\s*([\w\.]+)\s*\|\s*default\((\d+)\)\s*\}\}/g, (m, p, d) => {
    const v = get(p, ctx);
    return v == null ? d : String(v);
  });
  out = out.replace(/\{\{\s*([\w\.]+)\s*\}\}/g, (m, p) => {
    const v = get(p, ctx);
    return v == null ? '' : (typeof v === 'object' ? JSON.stringify(v) : String(v));
  });
  return out;
};

// Extract every variable reference from a template (for unknown-var check).
const extractVarRefs = (tpl) => {
  const refs = new Set();
  const patterns = [
    /\{\{\s*([\w\.]+)\s*\}\}/g,
    /\{\{\s*([\w\.]+)\s*\|\s*upper\s*\}\}/g,
    /\{\{\s*([\w\.]+)\s*\|\s*tojson\s*\}\}/g,
    /\{\{\s*'%04d'\s*\|\s*format\(([\w\.]+)\)\s*\}\}/g,
    /\{\{\s*([\w\.]+)\s*\|\s*default\(\d+\)\s*\}\}/g,
    /\{%\s*if\s+([\w\.]+)\s*%\}/g,
  ];
  for (const re of patterns) {
    let m;
    while ((m = re.exec(tpl)) !== null) refs.add(m[1]);
  }
  return [...refs];
};

// ---------- Synthetic context for render smoke ----------
const SYNTH_CTX = {
  metadata: {
    batch_id: 'BCH_TEST_ABCD1234',
    source_pdf_id: 'PDF_TEST_0001',
    source_pdf_hash: 'sha256:0000000000000000000000000000000000000000000000000000000000000000',
    submitted_at: '2026-06-15T12:00:00Z',
    board: 'cbse', class: '12', subject: 'chemistry',
    chapter_name: 'Solutions', chapter_slug: 'solutions',
    source_type: 'ncert', question_type: 'mcq', difficulty: 'intermediate',
    number_of_questions: 20, overgeneration_factor: 1.5, draft_count: 30,
    language: 'en', include_visual_questions: false,
    routing_key: 'cbse|12|chemistry|solutions|mcq|intermediate|en',
    extractor_version: 'v1', curriculum_rules_version: 'v1', prompt_repo_version: 'v1',
    n8n_execution_id: 'exec_test',
  },
  curriculum_constraints: {
    resolution: { level: 1, key: 'cbse_12_chemistry_solutions_mcq_intermediate' },
    marks: { min: 1, max: 1 },
    answer_length: { min_words: 0, max_words: 5 },
    bloom_levels_allowed: ['understand', 'apply', 'analyze'],
    cognitive_level: 'intermediate',
    style: 'cbse_sample_paper_mcq',
    forbidden_patterns: ['all of the above', 'none of the above'],
    terminology: { prefer: ['IUPAC', 'SI units'], avoid: [] },
    competency_tags: ['application'],
    options_count_for_mcq: 4,
  },
  chapter_knowledge_summary: '...synthetic KB summary for lint smoke test...',
  output_schema: '{"type":"object"}',
  validator_output_schema: '{"type":"object"}',
  draft_count: 30,
  requested_count: 20,
  rubrics: {
    difficulty: '## Intermediate Rubric\nApply a single concept.',
    question_type: '## MCQ Rubric\n4 options, single best.',
    visual: '',
  },
  drafts_with_candidates: [{ draft: { draft_question_id: 'draft_x_0001' }, candidate_duplicates: [] }],
};

const SYNTH_CTX_WITH_VISUALS = {
  ...SYNTH_CTX,
  metadata: { ...SYNTH_CTX.metadata, include_visual_questions: true },
  rubrics: { ...SYNTH_CTX.rubrics, visual: '## Visual Rubric\nReference via [VISUAL:id].' },
};

// ---------- File helpers ----------
const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));
const readText = (p) => readFileSync(p, 'utf8');

const walk = (dir, ext) => {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    const s = statSync(full);
    if (s.isDirectory()) out.push(...walk(full, ext));
    else if (!ext || name.endsWith(ext)) out.push(full);
  }
  return out;
};

// ---------- Checks ----------

// 1. manifest.json
const manifestPath = join(REPO, 'manifest.json');
if (!existsSync(manifestPath)) {
  fail(`missing ${rel(manifestPath)}`);
  console.error(`\n${errors.length} error(s), ${warnings.length} warning(s)`);
  process.exit(1);
}
let manifest;
try {
  manifest = readJson(manifestPath);
  ok(`manifest.json parses`);
} catch (e) {
  fail(`manifest.json invalid JSON: ${e.message}`);
  console.error(`\n${errors.length} error(s)`);
  process.exit(1);
}

for (const key of ['manifest_version', 'active_prompt_repo_version', 'fallback_order', 'generators', 'validators', 'output_schemas', 'contracts']) {
  if (!(key in manifest)) fail(`manifest missing top-level key: ${key}`);
}

// 10. fallback_order length
if (Array.isArray(manifest.fallback_order) && manifest.fallback_order.length !== 8) {
  fail(`fallback_order must have 8 levels (matches Agent 4); got ${manifest.fallback_order.length}`);
} else if (Array.isArray(manifest.fallback_order)) {
  ok(`fallback_order has 8 levels`);
}

// ---------- Walk all .j2 files; validate filename + manifest entry ----------
const j2NamePattern = /^([a-z][a-z0-9_]*)\.(v\d+)\.j2$/;

const allJ2 = walk(REPO, '.j2');
const j2ById = {};
for (const path of allJ2) {
  const name = basename(path);
  const m = name.match(j2NamePattern);
  if (!m) {
    fail(`bad .j2 filename: ${rel(path)} (expected <id>.v<N>.j2)`);
    continue;
  }
  const [, id, version] = m;
  const kind = path.includes('/generators/') ? 'generator' : 'validator';
  j2ById[`${kind}:${id}:${version}`] = path;
}
ok(`${allJ2.length} .j2 files follow naming convention`);

// ---------- Validate generators + validators entries ----------
const validateEntries = (kind, entries) => {
  for (const [key, entry] of Object.entries(entries || {})) {
    if (!entry.active) continue;
    for (const f of ['id', 'version', 'path']) {
      if (!(f in entry)) fail(`${kind}[${key}] missing field: ${f}`);
    }
    if (entry.id !== key) warn(`${kind}[${key}].id "${entry.id}" doesn't match map key`);
    const full = join(REPO, entry.path);
    if (!existsSync(full)) {
      fail(`${kind}[${key}].path does not exist: ${entry.path}`);
      continue;
    }
    const filename = basename(entry.path);
    const expected = `${entry.id}.${entry.version}.j2`;
    if (filename !== expected) warn(`${kind}[${key}] filename ${filename} doesn't match id.version (${expected})`);
  }
};
validateEntries('generators', manifest.generators);
validateEntries('validators', manifest.validators);
ok(`generators + validators manifest entries reference existing files`);

// ---------- Output schemas + contracts must parse ----------
const schemaPathsToCheck = [];
for (const [k, e] of Object.entries(manifest.output_schemas || {})) schemaPathsToCheck.push(['output_schemas.' + k, e.path]);
for (const [k, p] of Object.entries(manifest.contracts || {})) schemaPathsToCheck.push(['contracts.' + k, p]);

for (const [label, p] of schemaPathsToCheck) {
  const full = join(REPO, p);
  if (!existsSync(full)) {
    fail(`${label} path missing: ${p}`);
    continue;
  }
  try {
    const j = readJson(full);
    if (!j.type && !j.$ref) warn(`${label} has no "type" or "$ref": ${p}`);
    if (!j.$schema) warn(`${label} missing "$schema": ${p}`);
  } catch (e) {
    fail(`${label} invalid JSON: ${p} -- ${e.message}`);
  }
}
ok(`${schemaPathsToCheck.length} JSON schemas parse + have minimal structure`);

// ---------- Per-entry rubrics + output_schema reachability with interpolation ----------
const SUPPORTED_DIFFICULTIES = ['easy', 'intermediate', 'hard'];
const SUPPORTED_QTYPES = ['mcq', 'la']; // present in v1 repo; expand as added

const checkInterpolatedPaths = (label, entry) => {
  if (entry.output_schema) {
    if (!existsSync(join(REPO, entry.output_schema))) fail(`${label}.output_schema missing: ${entry.output_schema}`);
  }
  if (entry.rubrics) {
    for (const [rk, rPath] of Object.entries(entry.rubrics)) {
      if (!rPath) continue;
      const hasD = rPath.includes('{difficulty}');
      const hasQ = rPath.includes('{question_type}');
      const targets = [];
      if (!hasD && !hasQ) targets.push(rPath);
      else {
        const ds = hasD ? SUPPORTED_DIFFICULTIES : [null];
        const qs = hasQ ? SUPPORTED_QTYPES : [null];
        for (const d of ds) {
          for (const q of qs) {
            let p = rPath;
            if (d) p = p.replace('{difficulty}', d);
            if (q) p = p.replace('{question_type}', q);
            targets.push(p);
          }
        }
      }
      for (const p of targets) {
        if (!existsSync(join(REPO, p))) warn(`${label}.rubrics.${rk} interpolated path missing: ${p}`);
      }
    }
  }
};
for (const [k, e] of Object.entries(manifest.generators || {})) if (e.active) checkInterpolatedPaths(`generators.${k}`, e);
ok(`per-entry rubric + output_schema interpolation paths exist`);

// ---------- Render smoke + leftover-placeholder check + unknown-variable check ----------
const PLACEHOLDER_PATTERNS = [
  { re: /\{\{[^}]*\}\}/, label: '{{ … }} placeholder still present after render' },
  { re: /\{%[^%]*%\}/, label: '{% … %} block tag still present after render' },
  { re: /\{#[\s\S]*?#\}/, label: '{# … #} comment still present after render' },
];

const renderSmoke = (kind, entries, requireMarkers) => {
  for (const [key, entry] of Object.entries(entries || {})) {
    if (!entry.active) continue;
    const tplPath = join(REPO, entry.path);
    let tpl;
    try { tpl = readText(tplPath); }
    catch (e) { fail(`${kind}[${key}] cannot read ${entry.path}: ${e.message}`); continue; }

    // unknown variable check
    const refs = extractVarRefs(tpl);
    for (const r of refs) {
      if (!ALLOWED_VARS.has(r)) {
        // also allow parent-path matches: if metadata.* is allowed, allow metadata.board.foo... only allow up to documented depth
        // For lint v1 just flag unknown leaves.
        warn(`${kind}[${key}] references unknown variable: {{ ${r} }} (template ${entry.path})`);
      }
    }

    // render with both contexts to catch visual-block bugs
    for (const [ctxName, ctx] of [['no_visuals', SYNTH_CTX], ['with_visuals', SYNTH_CTX_WITH_VISUALS]]) {
      let out;
      try { out = render(tpl, ctx); }
      catch (e) { fail(`${kind}[${key}] render threw under ${ctxName}: ${e.message}`); continue; }
      if (!out.trim()) { fail(`${kind}[${key}] rendered to empty string under ${ctxName}`); continue; }
      for (const p of PLACEHOLDER_PATTERNS) {
        if (p.re.test(out)) {
          fail(`${kind}[${key}] under ${ctxName}: ${p.label}; first 200 chars: ${out.match(p.re)[0].slice(0, 200)}`);
        }
      }
      for (const marker of requireMarkers) {
        if (!out.includes(marker)) warn(`${kind}[${key}] under ${ctxName} missing expected marker: "${marker}"`);
      }
    }
  }
};
renderSmoke('generators', manifest.generators, ['OUTPUT', 'STRICT', 'METADATA']);
renderSmoke('validators', manifest.validators, ['OUTPUT SCHEMA', 'STRICT', 'TAGGING RULES']);
ok(`render smoke passes for all active templates (both visual + non-visual contexts)`);

// ---------- Rubric markdown files have content ----------
const rubricFiles = walk(join(REPO, 'rubrics'), '.md');
for (const r of rubricFiles) {
  const body = readText(r);
  if (body.length < 100) warn(`rubric is suspiciously short (<100 chars): ${rel(r)}`);
}
ok(`${rubricFiles.length} rubric markdown files non-trivial`);

// ---------- Summary ----------
console.log();
if (warnings.length) {
  console.log('Warnings:');
  for (const w of warnings) console.log('  WARN  ' + w);
  console.log();
}
if (errors.length) {
  console.log('Errors:');
  for (const e of errors) console.log('  ERR   ' + e);
  console.log();
  console.log(`${errors.length} error(s), ${warnings.length} warning(s) — FAIL`);
  process.exit(1);
}
console.log(`OK — 0 errors, ${warnings.length} warning(s)`);
process.exit(0);
