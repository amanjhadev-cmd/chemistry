-- Cost tracking from Anthropic usage data.
--
-- IMPORTANT: pricing seed values are PLACEHOLDERS. Before relying on
-- total_cost_usd for real billing reconciliation, verify the rates in
-- model_pricing against current Anthropic pricing at
-- https://www.anthropic.com/pricing and bump the pricing_version.

-- ---- Pricing table ----

CREATE TABLE IF NOT EXISTS model_pricing (
  model                   TEXT        NOT NULL,
  pricing_version         TEXT        NOT NULL,
  active                  BOOLEAN     NOT NULL DEFAULT TRUE,
  input_per_million_usd   NUMERIC(12,6) NOT NULL,
  output_per_million_usd  NUMERIC(12,6) NOT NULL,
  effective_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  notes                   TEXT,
  PRIMARY KEY (model, pricing_version)
);

CREATE UNIQUE INDEX IF NOT EXISTS model_pricing_active_one_per_model
  ON model_pricing (model)
  WHERE active;

-- Seed pricing for the model the workflow currently uses.
-- VERIFY before production: Opus tier rates have varied over time.
INSERT INTO model_pricing (model, pricing_version, active, input_per_million_usd, output_per_million_usd, notes)
VALUES (
  'claude-opus-4-7',
  'placeholder_2026_06',
  TRUE,
  15.00,
  75.00,
  'PLACEHOLDER seed. Verify against https://www.anthropic.com/pricing before billing reconciliation.'
)
ON CONFLICT (model, pricing_version) DO NOTHING;

-- ---- Cost-per-batch table ----

CREATE TABLE IF NOT EXISTS cost_per_batch (
  batch_id                  TEXT        PRIMARY KEY,
  generator_model           TEXT,
  generator_input_tokens    INT         DEFAULT 0,
  generator_output_tokens   INT         DEFAULT 0,
  generator_cost_usd        NUMERIC(12,6) DEFAULT 0,
  validator_model           TEXT,
  validator_input_tokens    INT         DEFAULT 0,
  validator_output_tokens   INT         DEFAULT 0,
  validator_cost_usd        NUMERIC(12,6) DEFAULT 0,
  total_input_tokens        INT         DEFAULT 0,
  total_output_tokens       INT         DEFAULT 0,
  total_cost_usd            NUMERIC(12,6) DEFAULT 0,
  pricing_version           TEXT,
  draft_count               INT,
  good_count                INT,
  upgrade_count             INT,
  bad_count                 INT,
  shortfall                 BOOLEAN,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS cpb_created_at_idx ON cost_per_batch (created_at);
CREATE INDEX IF NOT EXISTS cpb_total_cost_idx ON cost_per_batch (total_cost_usd DESC);

-- ---- Reporting views ----

-- Daily cost rollup. Useful for cost monitoring dashboards.
CREATE OR REPLACE VIEW daily_cost_rollup AS
SELECT
  date_trunc('day', created_at)::date AS day,
  count(*)                            AS batches,
  sum(total_input_tokens)             AS input_tokens,
  sum(total_output_tokens)            AS output_tokens,
  sum(total_cost_usd)                 AS cost_usd,
  avg(total_cost_usd)                 AS avg_cost_per_batch_usd,
  count(*) FILTER (WHERE shortfall)   AS shortfall_batches
FROM cost_per_batch
GROUP BY 1
ORDER BY 1 DESC;

-- Top 50 most expensive batches in the last 30 days.
-- Used to spot prompt-template regressions that blow up token counts.
CREATE OR REPLACE VIEW top_cost_batches AS
SELECT
  cpb.batch_id,
  cpb.total_cost_usd,
  cpb.total_input_tokens,
  cpb.total_output_tokens,
  cpb.draft_count,
  cpb.good_count,
  cpb.shortfall,
  cpb.created_at,
  (cpb.total_cost_usd / NULLIF(cpb.good_count, 0))::numeric(12,6) AS cost_per_good_usd
FROM cost_per_batch cpb
WHERE cpb.created_at > now() - interval '30 days'
ORDER BY cpb.total_cost_usd DESC
LIMIT 50;
