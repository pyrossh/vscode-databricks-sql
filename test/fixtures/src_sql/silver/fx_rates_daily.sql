-- As-of daily GBP rates. ECB rates convert individual transactions (lib.transforms.ecb_gbp_cross + as_of_daily).
CREATE OR REFRESH MATERIALIZED VIEW fx_rates_daily (
  rate_date DATE COMMENT 'Calendar date the rate applies to (every day, including weekends and holidays).',
  currency STRING COMMENT 'ISO 4217 currency.',
  units_per_gbp DOUBLE COMMENT 'Currency units per 1 GBP (GBP cross computed from ECB EUR rates).',
  source_rate_date DATE COMMENT 'ECB publication date the rate was taken from.',
  is_fallback BOOLEAN COMMENT 'True when no ECB rate was published on rate_date and an earlier one was used.',
  fallback_days INT COMMENT 'Days between rate_date and source_rate_date.',
  rate_source STRING COMMENT 'Source of the rate: ECB_REFERENCE.',
  CONSTRAINT rate_positive EXPECT (units_per_gbp > 0),
  CONSTRAINT fallback_within_previous_business_day_window EXPECT (fallback_days <= 4)
)
COMMENT 'As-of daily GBP cross rates from ECB reference rates, with fallback to the previous published business day.'
TBLPROPERTIES (
  'quality' = 'silver',
  'data_classification' = 'public'
)
AS
WITH parsed AS (
  SELECT
    try_cast(TIME_PERIOD AS DATE) AS rate_date,
    upper(trim(CURRENCY)) AS currency,
    try_cast(OBS_VALUE AS DOUBLE) AS units_per_eur,
    CURRENCY_DENOM,
    _ingested_at
  FROM fx_ecb_raw
),
-- Duplicate quotes (same date + currency landed twice) keep the latest ingest.
quotes AS (
  SELECT rate_date, currency, units_per_eur
  FROM parsed
  WHERE rate_date IS NOT NULL AND units_per_eur > 0 AND CURRENCY_DENOM = 'EUR'
  QUALIFY row_number() OVER (PARTITION BY rate_date, currency ORDER BY _ingested_at DESC) = 1
),
gbp AS (
  SELECT rate_date, units_per_eur AS gbp_per_eur FROM quotes WHERE currency = 'GBP'
),
-- ECB quotes units per EUR; units per GBP = (units per EUR) / (GBP per EUR). Includes EUR and GBP itself.
crosses AS (
  SELECT q.rate_date AS source_rate_date, q.currency, q.units_per_eur / g.gbp_per_eur AS units_per_gbp
  FROM quotes q JOIN gbp g ON q.rate_date = g.rate_date
  WHERE q.currency <> 'GBP'
  UNION ALL
  SELECT rate_date, 'EUR', 1 / gbp_per_eur FROM gbp
  UNION ALL
  SELECT rate_date, 'GBP', 1.0 FROM gbp
),
bounds AS (
  SELECT min(source_rate_date) AS lo, greatest(max(source_rate_date), current_date()) AS hi FROM crosses
),
grid AS (
  SELECT cal.rate_date, c.currency
  FROM (SELECT explode(sequence(lo, hi)) AS rate_date FROM bounds) cal
  CROSS JOIN (SELECT DISTINCT currency FROM crosses) c
),
joined AS (
  SELECT g.rate_date, g.currency, x.units_per_gbp, x.source_rate_date AS src
  FROM grid g
  LEFT JOIN crosses x ON g.rate_date = x.source_rate_date AND g.currency = x.currency
),
-- Last published rate on or before each calendar day (weekends and TARGET holidays carry the previous one).
filled AS (
  SELECT
    rate_date,
    currency,
    last(units_per_gbp, true) OVER w AS units_per_gbp,
    last(src, true) OVER w AS source_rate_date
  FROM joined
  WINDOW w AS (PARTITION BY currency ORDER BY rate_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
-- No rate beyond 5 days from a publication: those days get no row, so transactions on them show up as
-- missing FX rather than silently using a stale rate.
SELECT
  rate_date,
  currency,
  units_per_gbp,
  source_rate_date,
  datediff(rate_date, source_rate_date) > 0 AS is_fallback,
  CAST(datediff(rate_date, source_rate_date) AS INT) AS fallback_days,
  'ECB_REFERENCE' AS rate_source
FROM filled
WHERE units_per_gbp IS NOT NULL AND datediff(rate_date, source_rate_date) <= 5;
