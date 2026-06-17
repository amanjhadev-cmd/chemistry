# Caching Strategy

## v1: workflow-static-data cache (current)

Agent 4 and Agent 7a cache the prompt-repo fetches in n8n's built-in
per-workflow KV (`$getWorkflowStaticData('global')`). This persists across
executions of the **same workflow** in the n8n database, with **zero new
infrastructure**.

### What gets cached

| Cache namespace | Key | TTL | Why |
|---|---|---|---|
| `manifest` | `<PROMPT_REPO_BASE>` | 5 min | Picks up template rollouts within minutes |
| `template` | path (e.g. `generators/cbse_mcq.v1.j2`) | 1 hour | Immutable per version — versioning makes this safe |
| `rubric` | interpolated path (e.g. `rubrics/difficulty/hard.v1.md`) | 1 hour | Immutable per version |
| `schema` | path (e.g. `schemas/output/mcq.v2.json`) | 1 hour | Immutable per version |

### Behaviour

On every run, each Code node:

1. Reads `static.prompt_repo_cache[kind][key]`.
2. If hit and `expires_at > now()` → use cached value, set `stats.{kind}_hit = true`.
3. If miss or expired → `httpRequest` to GitHub raw, then `cache.put` with TTL.
4. Returns `prompt_cache_stats` (Agent 4) / `validator_cache_stats` (Agent 7a) in the
   output JSON so downstream nodes + audit log can record cache effectiveness.

Expired entries are deleted on read (lazy eviction). The cache doesn't grow
unboundedly under normal traffic because the template + rubric + schema keys are
versioned — when a new version ships, the old key just stops being read and
ages out naturally.

### Latency win

Previous behaviour: every run hit GitHub raw for:
- 2× `manifest.json` (Agent 4 + Agent 7a)
- 1× generator template body
- 1× validator template body
- 0-3× rubric files
- 2× output schemas (one per AI call)

That's ~6-9 HTTPS round-trips per batch. With cache hits, **0 round-trips**
once warm. Cold-cache run still pays the original cost; subsequent runs within
the TTL window are cache-only.

### Important: test runs vs production runs

`$getWorkflowStaticData` mutations are **only persisted when the workflow runs
in production mode**. Manual "Execute Workflow" runs from the n8n UI **read**
the cache but don't write back. This means:

- A real production run populates the cache.
- A subsequent test run from the UI sees cached values.
- A test run executed BEFORE any production run sees an empty cache and fetches
  every time (which is the conservative behaviour — no surprise stale data).

For local development you can prime the cache by activating the workflow,
triggering it once, then deactivating.

### Inspecting + flushing the cache

Cache lives inside the workflow record. To inspect from the n8n UI:

1. Open the workflow → click any Code node → "Execute Node" with sample data.
2. The Code node has access to `$getWorkflowStaticData('global')`; add
   `return [{ json: $getWorkflowStaticData('global').prompt_repo_cache || {} }]`
   to a scratch Code node.

To flush: edit the workflow once (rename a sticky note for instance) and save —
n8n preserves static data across saves. To truly flush, the cleanest path is to
add a temporary Code node:

```js
const sd = $getWorkflowStaticData('global');
delete sd.prompt_repo_cache;
return [{ json: { flushed: true } }];
```

run it once in production mode, then remove it.

### Per-run cache stats in the output

Audit log payload (post-#15) will include `prompt_cache_stats` so you can
graph cache hit rate over time:

```sql
SELECT date_trunc('hour', created_at) AS hour,
       count(*) FILTER (WHERE payload->'prompt_cache_stats'->>'manifest_hit' = 'true') AS manifest_hits,
       count(*) AS total
FROM generation_audit_log
WHERE stage = 'complete'
GROUP BY 1
ORDER BY 1 DESC LIMIT 24;
```

## v2: real Redis (planned, not yet wired)

Static-data caching has two limitations that drive a Redis migration when scale
demands it:

1. **Per-workflow scope.** The main workflow and the error sub-workflow have
   separate static data. If we add more workflows that fetch the same prompts
   (e.g. a daily-regenerate-shortfall cron), each gets its own cache.
2. **n8n DB pressure.** Static data is stored as JSON in the workflow row.
   Under high-traffic loads with many templates, this becomes a hot path on
   the n8n Postgres write traffic.

When either bites, swap to Redis:

1. Stand up Redis (or a managed equivalent — Upstash, Memorystore, ElastiCache).
2. Replace the `cacheGet` / `cachePut` helpers inside Agent 4 + Agent 7a with
   calls to a Redis HTTP gateway (Upstash exposes one natively; for raw Redis,
   use a tiny FastAPI sidecar).
3. Keep the same TTL strategy and same key structure (`qgen:prompt:manifest:v1`,
   `qgen:prompt:body:{path}`, etc.) so the migration is a function-body swap,
   not a workflow restructure.

Curriculum rules caching is **not** included in v1 — they're a single fast
Postgres query and the latency isn't worth the staleness risk. Add Redis
caching for curriculum at the same time as the v2 Redis swap if needed.
