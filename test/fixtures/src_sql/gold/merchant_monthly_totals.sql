-- UC-127 draft: per-merchant monthly totals in GBP. Contract: datacontract.yml
CREATE OR REFRESH MATERIALIZED VIEW merchant_monthly_totals (
  merchant_id STRING COMMENT 'Merchant number.',
  merchant_name STRING COMMENT 'Merchant trading name.',
  mcc STRING COMMENT 'Merchant category code.',
  merchant_country STRING COMMENT 'Merchant country (ISO 3166 alpha-2).',
  period_month DATE COMMENT 'First day of the reporting month (authorisation month).',
  period_year INT COMMENT 'Reporting year.',
  txn_count BIGINT COMMENT 'Number of transactions of any type.',
  sale_count BIGINT COMMENT 'Number of SALE transactions.',
  refund_count BIGINT COMMENT 'Number of REFUND transactions.',
  chargeback_count BIGINT COMMENT 'Number of CHARGEBACK transactions.',
  gross_gbp DECIMAL(18,2) COMMENT 'Sum of SALE amounts in GBP.',
  refunds_gbp DECIMAL(18,2) COMMENT 'Sum of REFUND amounts in GBP (positive number).',
  chargebacks_gbp DECIMAL(18,2) COMMENT 'Sum of CHARGEBACK amounts in GBP (positive number).',
  net_gbp DECIMAL(18,2) COMMENT 'gross_gbp - refunds_gbp - chargebacks_gbp.',
  missing_fx_count BIGINT COMMENT 'Transactions excluded from GBP sums because no FX rate was available.',
  fx_basis STRING COMMENT 'How amounts were converted to GBP.',
  _refreshed_at TIMESTAMP COMMENT 'When this row was last recomputed. Used for the freshness SLA.',
  CONSTRAINT net_reconciles EXPECT (net_gbp = gross_gbp - refunds_gbp - chargebacks_gbp) ON VIOLATION FAIL UPDATE,
  CONSTRAINT counts_reconcile EXPECT (txn_count = sale_count + refund_count + chargeback_count) ON VIOLATION FAIL UPDATE,
  CONSTRAINT merchant_known EXPECT (merchant_name IS NOT NULL),
  CONSTRAINT all_txns_converted EXPECT (missing_fx_count = 0)
)
CLUSTER BY (period_month, merchant_id)
COMMENT 'Per-merchant monthly transaction counts and GBP volumes (gross, refunds, chargebacks, net). Draft shape of the UC-127 HMRC merchant acquirer return.'
TBLPROPERTIES (
  'quality' = 'gold',
  'data_classification' = 'internal',
  'data_contract' = 'datacontract.yml'
)
AS
WITH agg AS (
  SELECT
    merchant_id,
    period_month,
    count(*) AS txn_count,
    count_if(txn_type = 'SALE') AS sale_count,
    count_if(txn_type = 'REFUND') AS refund_count,
    count_if(txn_type = 'CHARGEBACK') AS chargeback_count,
    CAST(coalesce(sum(CASE WHEN txn_type = 'SALE' THEN amount_gbp END), 0) AS DECIMAL(18,2)) AS gross_gbp,
    CAST(coalesce(sum(CASE WHEN txn_type = 'REFUND' THEN amount_gbp END), 0) AS DECIMAL(18,2)) AS refunds_gbp,
    CAST(coalesce(sum(CASE WHEN txn_type = 'CHARGEBACK' THEN amount_gbp END), 0) AS DECIMAL(18,2)) AS chargebacks_gbp,
    count_if(amount_gbp IS NULL) AS missing_fx_count
  FROM transactions_gbp
  GROUP BY merchant_id, period_month
)
SELECT
  a.merchant_id,
  m.merchant_name,
  m.mcc,
  m.merchant_country,
  a.period_month,
  year(a.period_month) AS period_year,
  a.txn_count,
  a.sale_count,
  a.refund_count,
  a.chargeback_count,
  a.gross_gbp,
  a.refunds_gbp,
  a.chargebacks_gbp,
  CAST(a.gross_gbp - a.refunds_gbp - a.chargebacks_gbp AS DECIMAL(18,2)) AS net_gbp,
  a.missing_fx_count,
  'ECB daily reference rate (GBP cross via EUR) on authorisation date; previous business day if none published' AS fx_basis,
  current_timestamp() AS _refreshed_at
FROM agg a
LEFT JOIN merchants m ON a.merchant_id = m.merchant_id;
