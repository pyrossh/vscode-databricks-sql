CREATE OR REFRESH MATERIALIZED VIEW transactions_gbp (
  txn_id STRING COMMENT 'Acquirer transaction reference.',
  merchant_id STRING COMMENT 'Merchant number.',
  txn_type STRING COMMENT 'SALE, REFUND or CHARGEBACK.',
  currency STRING COMMENT 'ISO 4217 transaction currency.',
  amount_minor BIGINT COMMENT 'Unsigned amount in currency minor units.',
  amount_major DECIMAL(20,4) COMMENT 'Unsigned amount in currency major units (minor / 10^exponent).',
  auth_date DATE COMMENT 'Authorisation date (FX rate date).',
  period_month DATE COMMENT 'First day of the authorisation month.',
  units_per_gbp DOUBLE COMMENT 'ECB-derived daily rate used; NULL when no rate was available.',
  fx_source_rate_date DATE COMMENT 'ECB publication date of the rate used.',
  fx_is_fallback BOOLEAN COMMENT 'True when an earlier business day\'s rate was used.',
  amount_gbp DECIMAL(18,2) COMMENT 'Unsigned amount converted to GBP; NULL when no rate was available.',
  signed_amount_gbp DECIMAL(18,2) COMMENT 'amount_gbp, negative for REFUND and CHARGEBACK.',
  CONSTRAINT has_daily_fx_rate EXPECT (units_per_gbp IS NOT NULL)
)
CLUSTER BY (period_month, merchant_id)
COMMENT 'Each transaction joined to its daily ECB-derived GBP rate.'
TBLPROPERTIES (
  'quality' = 'silver',
  'data_classification' = 'confidential'
)
AS
WITH converted AS (
  SELECT
    t.txn_id,
    t.merchant_id,
    t.txn_type,
    t.currency,
    t.amount_minor,
    -- minor -> major units: ISO 4217 exponents from src/lib/currencies.py (JPY 0, all others 2).
    CAST(CAST(t.amount_minor AS DECIMAL(20,0)) / power(10, element_at(map('GBP', 2, 'EUR', 2, 'USD', 2, 'CHF', 2, 'SEK', 2, 'NOK', 2, 'DKK', 2, 'PLN', 2, 'CAD', 2, 'AUD', 2, 'JPY', 0), t.currency)) AS DECIMAL(20,4)) AS amount_major,
    t.auth_date,
    trunc(t.auth_date, 'MONTH') AS period_month,
    fx.units_per_gbp,
    fx.source_rate_date AS fx_source_rate_date,
    fx.is_fallback AS fx_is_fallback
  FROM transactions t
  LEFT JOIN fx_rates_daily fx ON t.auth_date = fx.rate_date AND t.currency = fx.currency
),
gbp AS (
  SELECT *, CAST(round(amount_major / units_per_gbp, 2) AS DECIMAL(18,2)) AS amount_gbp FROM converted
)
SELECT
  txn_id,
  merchant_id,
  txn_type,
  currency,
  amount_minor,
  amount_major,
  auth_date,
  period_month,
  units_per_gbp,
  fx_source_rate_date,
  fx_is_fallback,
  amount_gbp,
  CAST(amount_gbp * CASE WHEN txn_type = 'SALE' THEN 1 ELSE -1 END AS DECIMAL(18,2)) AS signed_amount_gbp
FROM gbp;
