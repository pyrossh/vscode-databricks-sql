-- HMRC monthly rates. Used only for the tax table: they are the rates HMRC expects.
CREATE OR REFRESH MATERIALIZED VIEW fx_rates_hmrc_monthly (
  period_month DATE COMMENT 'First day of the month the HMRC rate applies to.',
  currency STRING COMMENT 'ISO 4217 currency.',
  units_per_gbp DOUBLE COMMENT 'Currency units per 1 GBP, as published by HMRC for the month.',
  rate_source STRING COMMENT 'Source of the rate: HMRC_MONTHLY.',
  CONSTRAINT rate_positive EXPECT (units_per_gbp > 0) ON VIOLATION DROP ROW,
  CONSTRAINT period_present EXPECT (period_month IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'HMRC monthly exchange rates (units per GBP), used for the tax table.'
TBLPROPERTIES (
  'quality' = 'silver',
  'data_classification' = 'public'
)
AS
WITH parsed AS (
  SELECT
    try_cast(concat(period, '-01') AS DATE) AS period_month,
    upper(trim(currency_code)) AS currency,
    try_cast(units_per_gbp AS DOUBLE) AS units_per_gbp,
    _ingested_at
  FROM fx_hmrc_raw
),
-- Duplicate quotes (same month + currency landed twice) keep the latest ingest.
rates AS (
  SELECT period_month, currency, units_per_gbp
  FROM parsed
  WHERE period_month IS NOT NULL AND units_per_gbp > 0
  QUALIFY row_number() OVER (PARTITION BY period_month, currency ORDER BY _ingested_at DESC) = 1
)
SELECT period_month, currency, units_per_gbp, 'HMRC_MONTHLY' AS rate_source
FROM rates
WHERE currency <> 'GBP'
UNION ALL
SELECT DISTINCT period_month, 'GBP', 1.0, 'HMRC_MONTHLY' FROM rates;
