# Observability

Prometheus + Grafana stack scraping the Question Generation v1.0 database
via `postgres_exporter` with a custom-queries file. **No changes to the n8n
workflow** — every metric is derived from rows already written by the
pipeline (`generation_audit_log`, `cost_per_batch`, `coverage_tracker`,
`error_audit`, `kb_cache`, `questions_master` / `review_queue` /
`rejected_questions`).

## Stack

```
   ┌──────────────────────────────────────┐
   │  Postgres (qgen master DB)           │
   │  generation_audit_log, cost_per_batch,│
   │  coverage_tracker, error_audit, kb…  │
   └────────────┬─────────────────────────┘
                │  custom SQL queries
                ▼
   ┌──────────────────────────────────────┐
   │  postgres_exporter :9187             │
   │  /metrics endpoint                   │
   └────────────┬─────────────────────────┘
                │ scrape every 30s
                ▼
   ┌──────────────────────────────────────┐
   │  Prometheus :9090                    │
   │  alerts.yml rules                    │
   └────────────┬─────────────────────────┘
                │
                ▼
   ┌──────────────────────────────────────┐
   │  Grafana :3001                       │
   │  qgen-overview dashboard auto-prov.  │
   └──────────────────────────────────────┘
```

## Run

```bash
cd metrics
export DATABASE_URL='postgres://user:pass@host:5432/db?sslmode=disable'
docker compose up -d

# Prometheus:  http://localhost:9090
# Grafana:     http://localhost:3001  (anonymous Viewer access enabled)
# Raw metrics: http://localhost:9187/metrics
```

## Metric catalogue

| Metric | Type | What it tells you |
|---|---|---|
| `qgen_batches_total{stage,status}` | counter | All-time audit log row counts by stage + status |
| `qgen_batches_last_24h_total{stage,status}` | gauge | Recent volume — rates of success/failure per stage |
| `qgen_questions_bucket_total{bucket}` | counter | All-time good / upgrade / bad counts |
| `qgen_questions_bucket_last_24h_total{bucket}` | gauge | Recent bucket fill rate |
| `qgen_ai_tokens_total_total{ordinal,direction}` | counter | Anthropic tokens consumed (cumulative) |
| `qgen_ai_cost_usd_total_total{model}` | counter | Cumulative USD spend per model |
| `qgen_ai_cost_usd_last_24h_{usd,tokens,batches}` | gauge | Last-24h spend snapshot |
| `qgen_ai_call_budget_divergence_divergence` | gauge | **Must be 0.** Non-zero = AI calls without cost capture, or vice versa |
| `qgen_shortfall_batches_last_24h_total` | gauge | Batches that returned fewer good than requested |
| `qgen_good_ratio_last_24h_ratio` | gauge | good / (good+upgrade+bad). <0.3 = prompt regression |
| `qgen_error_audit_total_total{error_code}` | counter | Errors caught by the error sub-workflow |
| `qgen_error_audit_last_1h_total` | gauge | Recent error rate |
| `qgen_kb_cache_{rows,avg_quality}` | gauge | KB cache size + extraction quality average |
| `qgen_coverage_gaps_total_total` | gauge | Syllabus cells with <5 good questions |
| `qgen_coverage_total_questions_{good,upgrade,bad}{board}` | gauge | Per-board bucket totals |
| `qgen_dedup_signals_populated_pct_{simhash,norm_hash,minhash}_pct` | gauge | % of approved rows with non-null dedup signatures (should be ≈100 post #13) |

Postgres-exporter auto-suffixes metric names with the column name when there
are multiple columns per query, hence the slightly-awkward `_total_total` /
`_pct_pct` doubles. The query file is named to make the source obvious;
rename in `postgres-exporter-queries.yml` if it bothers anyone.

## Alerts

`metrics/alerts.yml` ships with sensible defaults:

| Alert | Severity | Threshold | What to do |
|---|---|---|---|
| `QgenAiCallBudgetLeak` | critical | divergence > 0 for 10m | Check the last successful batches in `generation_audit_log` vs `cost_per_batch`. Cost capture node may have failed or a node is making rogue AI calls. |
| `QgenDailyCostHigh` | warning | >$100 / 24h for 30m | Check `top_cost_batches`. Usually a prompt regression inflating `draft_count`. Adjustable. |
| `QgenGoodRatioLow` | warning | <30% for 1h | Inspect `prompt_template_resolved_key` distribution + `validation_reasons` from `review_queue` to find the bad template/rubric. |
| `QgenShortfallRateHigh` | warning | >5 batches / 24h for 15m | Bump `overgeneration_factor` in Agent 1, or tighten the generator rubric so fewer drafts get tagged `upgrade`/`bad`. |
| `QgenErrorRateHigh` | warning | >5 errors / 1h for 5m | Read `error_audit` and the Slack notifications from the error sub-workflow. |
| `QgenSimhashNotPopulated` | warning | <95% for 30m | Compute Dedup Signatures node broke or `0010_extend_buckets_with_dedup_sigs.sql` not applied. |
| `QgenCoverageGapsGrowing` | info | +10 gaps / 24h | More syllabus cells under-served — queue backfill batches via the operator UI. |

Edit thresholds in `metrics/alerts.yml` to taste. Reload Prometheus with
`docker compose kill -s HUP prometheus`.

## Dashboard

The Grafana dashboard at `metrics/grafana/qgen-overview.json` is auto-provisioned
from the dashboards folder and lives in the **Question Generation** folder.

13 panels:

| Row | Panels |
|---|---|
| 1 | 24h cost • 24h batches • good ratio • AI budget divergence (single-value stat tiles) |
| 2 | Token rate per call/direction • Bucket counts last 24h |
| 3 | Errors per hour • Shortfall batches 24h • Coverage gaps total |
| 4 | Questions by board (table view) |
| 5 | SimHash coverage % • KB cache rows • KB avg extraction quality |

## Extending

To add a new metric:

1. Append a top-level entry to `postgres-exporter-queries.yml` with:
   - a SQL query that returns one or more numeric columns and optional label columns
   - `metrics:` block listing each column with `usage` (LABEL / COUNTER / GAUGE) + `description`
2. Restart postgres-exporter: `docker compose restart postgres-exporter`
3. Verify with `curl localhost:9187/metrics | grep <prefix>`
4. (Optional) Add an alert rule in `alerts.yml` and reload Prometheus.

## What's NOT in the metric set (and why)

- **Per-stage latency histograms.** n8n doesn't surface per-node execution
  timings to a place we can scrape. To add: instrument key nodes with
  `start = Date.now()` / `payload.stage_ms = Date.now() - start`, write into
  `generation_audit_log.payload`, then add a postgres-exporter query that
  averages or buckets them. Not done in v1; manageable when needed.

- **Per-batch traces.** Same reason. OpenTelemetry from n8n would need a
  custom integration. Defer until volume warrants it.

- **Extractor microservice metrics.** The `extractor-svc/` exposes `/healthz`
  but not `/metrics` yet. The Prometheus config has a commented stanza for
  scraping it once `prometheus-client` is wired in.
