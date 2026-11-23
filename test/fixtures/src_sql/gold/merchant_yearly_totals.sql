CREATE OR REFRESH MATERIALIZED VIEW merchant_yearly_totals (
  merchant_id STRING COMMENT 'Merchant number.',
  merchant_name STRING COMMENT 'Merchant trading name.',
  mcc STRING COMMENT 'Merchant category code.',
  merchant_country STRING COMMENT 'Merchant country (ISO 3166 alpha-2).',
  period_year INT COMMENT 'Reporting year.',
  months_active BIGINT COMMENT 'Number of months with at least one transaction.',
  txn_count BIGINT COMMENT 'Number of transactions of any type.',
  sale_count BIGINT COMMENT 'Number of SALE transactions.',
  refund_count BIGINT COMMENT 'Number of REFUND transactions.',
  chargeback_count BIGINT COMMENT 'Number of CHARGEBACK transactions.',
  gross_gbp DECIMAL(18,2) COMMENT 'Sum of SALE amounts in GBP.',
  refunds_gbp DECIMAL(18,2) COMMENT 'Sum of REFUND amounts in GBP.',
  chargebacks_gbp DECIMAL(18,2) COMMENT 'Sum of CHARGEBACK amounts in GBP.',
  net_gbp DECIMAL(18,2) COMMENT 'gross_gbp - refunds_gbp - chargebacks_gbp.',
  missing_fx_count BIGINT COMMENT 'Transactions excluded from GBP sums because no FX rate was available.',
  _refreshed_at TIMESTAMP COMMENT 'When this row was last recomputed.',
  CONSTRAINT net_reconciles EXPECT (net_gbp = gross_gbp - refunds_gbp - chargebacks_gbp) ON VIOLATION FAIL UPDATE
)
COMMENT 'Per-merchant yearly totals rolled up from merchant_monthly_totals.'
TBLPROPERTIES (
  'quality' = 'gold',
  'data_classification' = 'internal'
)
AS SELECT
  merchant_id,
  max_by(merchant_name, period_month) AS merchant_name,
  max_by(mcc, period_month) AS mcc,
  max_by(merchant_country, period_month) AS merchant_country,
  period_year,
  count(*) AS months_active,
  CAST(sum(txn_count) AS BIGINT) AS txn_count,
  CAST(sum(sale_count) AS BIGINT) AS sale_count,
  CAST(sum(refund_count) AS BIGINT) AS refund_count,
  CAST(sum(chargeback_count) AS BIGINT) AS chargeback_count,
  CAST(sum(gross_gbp) AS DECIMAL(18,2)) AS gross_gbp,
  CAST(sum(refunds_gbp) AS DECIMAL(18,2)) AS refunds_gbp,
  CAST(sum(chargebacks_gbp) AS DECIMAL(18,2)) AS chargebacks_gbp,
  CAST(sum(net_gbp) AS DECIMAL(18,2)) AS net_gbp,
  CAST(sum(missing_fx_count) AS BIGINT) AS missing_fx_count,
  current_timestamp() AS _refreshed_at
FROM merchant_monthly_totals
GROUP BY merchant_id, period_year;
