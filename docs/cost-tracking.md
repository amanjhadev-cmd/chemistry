# Cost Tracking

Captures Anthropic token usage per batch, computes USD via a pricing table,
and persists to `cost_per_batch` for reporting and budget alerts.

## Pipeline

```
AI CALL 1 (Generator, simplify=false → response includes usage{input,output})
   ↓ (Parse + Validate Draft JSON: extracts text from content[] array)
…
AI CALL 2 (Validator, simplify=false → response includes usage)
   ↓ (Parse Re-Tag)
   ↓
Capture AI Costs (Code)        ← reads $('AI CALL 1').first().json.usage and $('AI CALL 2').first().json.usage
   ↓                              looks up pricing per model, computes per-call + total USD,
   ↓                              attaches as ai_costs onto the item
Agent 8 - Split Buckets        ← bakes ai_costs into GENERATION_METADATA.json artifact
   ↓
… Drive writes, PG inserts …
PG - Audit Log
   ↓
PG - Insert Cost Per Batch     ← UPSERTs cost_per_batch keyed by batch_id
   ↓
Response - Batch Summary       ← includes ai_costs in the form response
```

## ai_costs shape

```json
{
  "pricing_version": "placeholder_2026_06",
  "generator": {
    "model": "claude-opus-4-7",
    "input_tokens": 7843,
    "output_tokens": 5912,
    "cost_usd": 0.560175
  },
  "validator": {
    "model": "claude-opus-4-7",
    "input_tokens": 9221,
    "output_tokens": 4108,
    "cost_usd": 0.446415
  },
  "totals": {
    "input_tokens": 17064,
    "output_tokens": 10020,
    "cost_usd": 1.00659
  },
  "captured_at": "2026-06-15T19:00:00.000Z"
}
```

## ⚠️  Pricing is seeded with PLACEHOLDERS

`db/migrations/0012_cost_tracking.sql` seeds `model_pricing` with rates that
match historical Opus-tier pricing but **are not guaranteed to match current
Anthropic billing**. Before treating `cost_per_batch.total_cost_usd` as
authoritative for budget reconciliation:

1. Open https://www.anthropic.com/pricing
2. Compare to the seed values:
   - `claude-opus-4-7`: $15.00 in / $75.00 out per million tokens
3. If the rates differ, insert a new pricing version and flip `active`:

```sql
UPDATE model_pricing SET active = FALSE WHERE model = 'claude-opus-4-7';
INSERT INTO model_pricing (model, pricing_version, active, input_per_million_usd, output_per_million_usd, notes)
VALUES ('claude-opus-4-7', '2026_q3_official', TRUE, <REAL_IN>, <REAL_OUT>, 'Verified against anthropic.com/pricing 2026-07-01');
```

Then update the `PRICING` constant inside the `Capture AI Costs` Code node
to match — the workflow doesn't read pricing from the DB live (one extra
roundtrip per run), it uses the inline constant. To keep both in sync, the
inline map and the DB row should always carry the same `pricing_version`.

Why both? The DB table is the **source of truth for reporting** (handy for
historical re-computation if rates change). The Code-node inline copy is the
**runtime computation source** (avoids the PG roundtrip per run).

## Why simplify=false was set on both AI nodes

The Anthropic node defaults to `simplify: true`, which strips the response
down to just `{ content: '<merged text>' }` — handy but loses `usage`,
`model`, `id`, `stop_reason`. We need `usage` for cost capture, so both AI
nodes now run with `simplify: false`. The downstream parsers
(`Parse + Validate Draft JSON`, `Parse Validation + Deterministic Re-Tag`)
were updated to handle the array `content` shape that simplify=false returns:

```js
if (typeof aiOut.content === 'string') text = aiOut.content;
else if (Array.isArray(aiOut.content)) text = aiOut.content.filter(b => b.type === 'text').map(b => b.text).join('');
```

This is backward-compatible — if Anthropic ever returns content as a single
string again, it still works.

## Built-in reports

### Daily rollup (great for a "yesterday's spend" Slack post)

```sql
SELECT * FROM daily_cost_rollup WHERE day >= now() - interval '14 days';
```

Output: `day, batches, input_tokens, output_tokens, cost_usd, avg_cost_per_batch_usd, shortfall_batches`.

### Top expensive batches (catches prompt regressions)

```sql
SELECT * FROM top_cost_batches;
```

Surfaces the 50 most expensive batches in the last 30 days, with
`cost_per_good_usd` so you can see "we spent $4 to produce 2 good questions"
type outliers — a strong signal that the generator prompt is over-generating
or the validator is rejecting too aggressively.

### Total spend in last 7 days

```sql
SELECT
  sum(total_cost_usd)                 AS total_usd,
  sum(total_input_tokens)             AS input_tokens,
  sum(total_output_tokens)            AS output_tokens,
  sum(good_count)                     AS good_questions,
  (sum(total_cost_usd) / NULLIF(sum(good_count), 0))::numeric(12,6) AS avg_cost_per_good_usd
FROM cost_per_batch
WHERE created_at > now() - interval '7 days';
```

### Per-model breakdown

```sql
SELECT generator_model,
       count(*)              AS batches,
       sum(total_cost_usd)   AS total_usd,
       avg(total_cost_usd)   AS avg_usd_per_batch,
       sum(total_input_tokens + total_output_tokens) AS total_tokens
FROM cost_per_batch
WHERE created_at > now() - interval '30 days'
GROUP BY generator_model
ORDER BY total_usd DESC;
```

## Failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `cost_per_batch.total_cost_usd = 0` for runs that obviously cost money | Anthropic node still has `simplify: true` (returns no `usage`) | Verify `simplify: false` is set on both AI nodes |
| `generator_input_tokens IS NULL` on a row | AI Call 1 failed before returning a response | Expected — the workflow should also have written to `error_audit` |
| Reported costs are 2-3× what Anthropic invoiced | Pricing seed is stale | Update both the DB `model_pricing` and the inline `PRICING` constant in the Capture AI Costs Code node, then bump `pricing_version` |
| Same `batch_id` keeps appearing in `top_cost_batches` | Specific prompt template is over-generating; check `prompt_template_resolved_key` in audit | Reduce `draft_count` (lower `overgeneration_factor` in Agent 1) or tighten the generator prompt rubric |

## Future enhancements

- **Per-question cost**: divide `total_cost_usd` by `good_count` to get unit economics; already exposed as `cost_per_good_usd` in `top_cost_batches`.
- **Budget alerts**: a daily cron that queries `daily_cost_rollup` and pages if `cost_usd > $LIMIT`.
- **Cost-aware fallback**: when daily spend approaches budget, the workflow could downgrade `claude-opus-4-7` → `claude-sonnet-4-6` via a Switch node on Agent 5's model param. Not built yet; see #16 (Prometheus metrics) and #17 (form auth) before tackling this.
