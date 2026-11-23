-- ILLUSTRATIVE monthly VAT figures: HMRC monthly rate x VAT rate. Not a tax position.
--
-- Converts per (merchant, month, currency) group rather than per transaction: HMRC publishes one
-- rate per month, so the result is the same and cheaper.
CREATE OR REFRESH MATERIALIZED VIEW merchant_monthly_tax (
  merchant_id STRING COMMENT 'Merchant number.',
  merchant_name STRING COMMENT 'Merchant trading name.',
  merchant_country STRING COMMENT 'Merchant country (ISO 3166 alpha-2).',
  period_month DATE COMMENT 'First day of the reporting month.',
  net_gbp_hmrc DECIMAL(18,2) COMMENT 'Net volume converted at the HMRC monthly rate for the period.',
  missing_hmrc_rate_count BIGINT COMMENT 'Currency groups with no HMRC rate for the month (excluded).',
  vat_rate DECIMAL(5,4) COMMENT 'VAT rate applied (ILLUSTRATIVE).',
  illustrative_vat_gbp DECIMAL(18,2) COMMENT 'net_gbp_hmrc x vat_rate. ILLUSTRATIVE ONLY - not a tax position.',
  is_illustrative BOOLEAN COMMENT 'Always true: real tax treatment of acquiring is pending tax review.',
  fx_basis STRING COMMENT 'How amounts were converted to GBP.',
  _refreshed_at TIMESTAMP COMMENT 'When this row was last recomputed.',
  CONSTRAINT vat_rate_found EXPECT (vat_rate IS NOT NULL),
  CONSTRAINT all_currencies_have_hmrc_rate EXPECT (missing_hmrc_rate_count = 0)
)
COMMENT 'ILLUSTRATIVE per-merchant monthly VAT figures: net volume at HMRC monthly rate x VAT rate. Not a tax position.'
TBLPROPERTIES (
  'quality' = 'gold',
  'data_classification' = 'internal',
  'illustrative' = 'true'
)
AS
WITH signed AS (
  SELECT
    merchant_id,
    trunc(auth_date, 'MONTH') AS period_month,
    currency,
    CAST(CAST(amount_minor AS DECIMAL(20,0)) / power(10, element_at(map('GBP', 2, 'EUR', 2, 'USD', 2, 'CHF', 2, 'SEK', 2, 'NOK', 2, 'DKK', 2, 'PLN', 2, 'CAD', 2, 'AUD', 2, 'JPY', 0), currency)) AS DECIMAL(20,4))
      * CASE WHEN txn_type = 'SALE' THEN 1 ELSE -1 END AS signed_major
  FROM transactions
),
by_ccy AS (
  SELECT
    s.merchant_id,
    s.period_month,
    s.currency,
    h.units_per_gbp,
    sum(s.signed_major) / h.units_per_gbp AS net_gbp
  FROM signed s
  LEFT JOIN fx_rates_hmrc_monthly h ON s.period_month = h.period_month AND s.currency = h.currency
  GROUP BY s.merchant_id, s.period_month, s.currency, h.units_per_gbp
),
per_month AS (
  SELECT
    merchant_id,
    period_month,
    CAST(round(coalesce(sum(net_gbp), 0), 2) AS DECIMAL(18,2)) AS net_gbp_hmrc,
    count_if(units_per_gbp IS NULL) AS missing_hmrc_rate_count
  FROM by_ccy
  GROUP BY merchant_id, period_month
)
SELECT
  pm.merchant_id,
  m.merchant_name,
  m.merchant_country,
  pm.period_month,
  pm.net_gbp_hmrc,
  pm.missing_hmrc_rate_count,
  v.vat_rate,
  CAST(round(pm.net_gbp_hmrc * v.vat_rate, 2) AS DECIMAL(18,2)) AS illustrative_vat_gbp,
  true AS is_illustrative,
  'HMRC monthly exchange rate for the authorisation month' AS fx_basis,
  current_timestamp() AS _refreshed_at
FROM per_month pm
LEFT JOIN merchants m ON pm.merchant_id = m.merchant_id
LEFT JOIN vat_rates v
  ON m.merchant_country = v.country_code
  AND pm.period_month >= v.valid_from
  AND (v.valid_to IS NULL OR pm.period_month <= v.valid_to);
