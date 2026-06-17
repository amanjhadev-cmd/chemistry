# Deterministic Deduplication

The workflow uses **four** non-AI dedup signals, all computed in code before
AI Call 2 sees the candidate set. AI Call 2 only judges; it never retrieves.

## The four signals

| Signal | Where computed | Where used | Sensitivity |
|---|---|---|---|
| **Exact normalized hash** | `Compute Dedup Signatures` node — `sha256(normalize(question) + '|' + answer)` | `Agent 6` lookup: `WHERE normalized_question_hash = $1` | Catches verbatim repeats regardless of whitespace/casing/punctuation. Cheapest. |
| **SimHash 64-bit** | Same node — Hamming-comparable hash from 3-word shingles | `Agent 6` lookup: `WHERE bit_count(simhash # $1) <= 6` | Catches questions that differ in 1-2 words (e.g. molarity↔molality, NaCl↔KCl). |
| **Trigram (pg_trgm)** | Postgres, on demand | `Agent 6` lookup: `similarity(question_text, $1) > 0.4` | Catches paraphrases at the character level. Highest recall, noisiest. |
| **MinHash 128-perm** | `Compute Dedup Signatures` — stored as bytea on the row | (not yet used at retrieval — stored for future LSH bucketing) | Future: Jaccard similarity estimation for cross-batch fuzzy clustering. |

## Pipeline placement

```
Parse + Validate Draft JSON
   ↓
Compute Dedup Signatures            ← computes normalized_hash + simhash + minhash for every draft
   ↓
Agent 6 - Duplicate Candidates      ← runs 3 retrieval branches (hash + simhash + trigram), unions + dedupes
   ↓
Agent 7a - Build Validator Prompt   ← attaches candidates to each draft for AI Call 2
   ↓
AI CALL 2                           ← judges duplicate_status per draft from the candidate sets
   ↓
Parse Re-Tag                        ← writes simhash + minhash + normalized_hash onto the validated row
   ↓
PG Inserts                          ← persisted into questions_master / review_queue / rejected_questions
```

The signatures flow through every downstream node, so the row that lands in
Postgres carries the exact same signature the lookup used. Re-running the same
PDF deterministically reproduces the same canonical id + same simhash, which
is what makes `ON CONFLICT (canonical_question_id) DO NOTHING` safe.

## Agent 6 retrieval query

Three CTEs, one union, one `DISTINCT ON (draft_question_id, question_id)`
to dedupe across the three retrieval methods, then `jsonb_agg` per draft:

```sql
WITH input_drafts AS (
  SELECT (d->>'draft_question_id') AS draft_question_id,
         (d->>'normalized_question_text') AS norm_q,
         (d->>'simhash')::bigint AS simhash
  FROM jsonb_array_elements($1::jsonb) AS d
),
cands_trigram AS (
  SELECT i.draft_question_id, q.*, similarity(q.question_text, i.norm_q)::float AS score, 'trigram' AS method
  FROM input_drafts i CROSS JOIN LATERAL (
    SELECT question_id, question_text, answer, question_type, difficulty
    FROM questions_master
    WHERE board = $2 AND class = $3 AND subject = $4
      AND similarity(question_text, i.norm_q) > 0.4
    ORDER BY similarity(question_text, i.norm_q) DESC LIMIT 5
  ) q
),
cands_simhash AS (
  SELECT i.draft_question_id, q.*,
         (1.0 - (bit_count(q.simhash # i.simhash)::numeric / 64.0))::float AS score, 'simhash' AS method
  FROM input_drafts i CROSS JOIN LATERAL (
    SELECT question_id, question_text, answer, question_type, difficulty
    FROM questions_master
    WHERE board = $2 AND class = $3 AND subject = $4
      AND simhash IS NOT NULL AND bit_count(simhash # i.simhash) <= 6
    ORDER BY bit_count(simhash # i.simhash) ASC LIMIT 5
  ) q
),
cands_exact_hash AS (
  SELECT i.draft_question_id, q.*, 1.0::float AS score, 'exact_hash' AS method
  FROM jsonb_array_elements($1::jsonb) AS d
  CROSS JOIN LATERAL (
    SELECT question_id, question_text, answer, question_type, difficulty
    FROM questions_master
    WHERE normalized_question_hash = (d->>'normalized_question_hash')
      AND board = $2 AND class = $3 AND subject = $4
    LIMIT 1
  ) q
  JOIN input_drafts i ON i.draft_question_id = d->>'draft_question_id'
),
all_cands AS (
  SELECT * FROM cands_trigram UNION ALL
  SELECT * FROM cands_simhash UNION ALL
  SELECT * FROM cands_exact_hash
),
best_per_pair AS (
  SELECT DISTINCT ON (draft_question_id, question_id) *
  FROM all_cands
  ORDER BY draft_question_id, question_id, score DESC
)
SELECT i.draft_question_id,
       coalesce(jsonb_agg(jsonb_build_object(...) ORDER BY b.score DESC), '[]'::jsonb) AS candidates
FROM input_drafts i LEFT JOIN best_per_pair b USING (draft_question_id)
GROUP BY i.draft_question_id
```

Each candidate carries its **method** (`trigram` / `simhash` / `exact_hash`) so
AI Call 2 can weight the signal appropriately when judging duplicates. An
`exact_hash` candidate is essentially a forced "duplicate" verdict; the
validator should reject the draft as `bad` with `duplicate_status='duplicate'`.

## SimHash algorithm

Mirrored in `samples/smoke_test/test_units.mjs` (`simhash64`) and in the
workflow's `Compute Dedup Signatures` Code node:

1. **Normalize**: NFKC → lowercase → strip non-alphanumeric → collapse whitespace.
2. **Shingle**: 3-word sliding window. Falls back to 3-char shingles for very
   short text.
3. **For each shingle**: take `sha256(shingle)[0..7]` as a 64-bit token hash.
4. **Accumulator**: for each of 64 bit positions, `+1` if the bit is set in
   the token hash, `-1` otherwise. Summed across all shingles.
5. **Output**: bit_i of the SimHash = 1 if accumulator_i > 0, else 0.
6. **Stored as `BIGINT`** (signed two's complement) so Postgres `#` (XOR) +
   `bit_count` give Hamming distance directly.

Properties (verified by unit tests in `test_units.mjs`):
- Identical text → Hamming 0.
- Whitespace/casing/punctuation differences → Hamming 0.
- Near-duplicate (one word swap) → strictly smaller Hamming than unrelated.
- Empty input → 0 (matches the `'0'` string the node emits as fallback).

The retrieval threshold of `bit_count(...) <= 6` (~ 90% similar) was picked
empirically against the unit tests and is conservative — tighten to 4 if false
positives become a problem, loosen to 8 if recall is too low.

## MinHash algorithm (stored, not yet used at retrieval)

1. **Shingle**: same 3-word sliding window as SimHash.
2. **For each shingle**: take `sha256(shingle)[0..3]` as a 32-bit hash `h`.
3. **128 permutations**: for `i in 0..127`, compute `h_i = (a_i * h + b_i) mod P`
   with fixed `a_i = 2i+1`, `b_i = 3i+2`, `P = 4294967311` (prime > 2^32).
4. **Signature**: per permutation, take the minimum across all shingles.
5. **Stored as `BYTEA`** (128 × 4 = 512 bytes, base64-transferred to Postgres
   via `decode($N, 'base64')`).

Why store but not yet use: LSH bucketing on MinHash bands is the
industry-standard way to find near-duplicates at scale (millions of rows).
The current trigram + SimHash retrieval is sufficient for tens of thousands
of rows per `(board, subject)` partition. When a partition crosses ~1M rows,
add an LSH index over the stored MinHash signatures and replace the
`cands_simhash` CTE with an LSH lookup.

## Cross-bucket queries (after migration 0010)

The same three columns now exist on `questions_master`, `review_queue`,
`rejected_questions`. Cross-bucket queries become trivial:

```sql
-- Does an upgrade-tagged question match a previously-rejected one?
SELECT u.batch_id AS upgrade_batch, r.batch_id AS rejected_batch,
       u.question_text AS upgrade_q, r.question_text AS rejected_q,
       bit_count(u.simhash # r.simhash) AS hamming
FROM review_queue u
JOIN rejected_questions r ON r.board = u.board AND r.subject = u.subject
WHERE bit_count(u.simhash # r.simhash) <= 4
  AND u.created_at > now() - interval '7 days'
LIMIT 50;
```

```sql
-- How often is an "upgrade" question actually a near-duplicate of an
-- already-approved one (i.e. should have been tagged bad)?
SELECT count(*) AS leaked_duplicates
FROM review_queue u
JOIN questions_master m ON m.board = u.board AND m.subject = u.subject
WHERE u.normalized_question_hash = m.normalized_question_hash
  AND u.created_at > now() - interval '24 hours';
```
