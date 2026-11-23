CREATE OR REFRESH MATERIALIZED VIEW merchants (
  merchant_id STRING COMMENT 'Merchant number. Unique key.',
  merchant_name STRING COMMENT 'Latest seen merchant trading name.',
  mcc STRING COMMENT 'Latest seen merchant category code.',
  merchant_country STRING COMMENT 'Latest seen merchant country (ISO 3166 alpha-2).',
  outlet_count BIGINT COMMENT 'Number of distinct outlets seen.',
  first_txn_date DATE COMMENT 'First authorisation date seen for the merchant.',
  last_txn_date DATE COMMENT 'Last authorisation date seen for the merchant.',
  CONSTRAINT merchant_id_present EXPECT (merchant_id IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Merchant dimension derived from transactions (latest attributes per merchant).'
TBLPROPERTIES (
  'quality' = 'silver',
  'data_classification' = 'internal'
)
AS SELECT
  merchant_id,
  max_by(merchant_name, auth_ts) AS merchant_name,
  max_by(mcc, auth_ts) AS mcc,
  max_by(merchant_country, auth_ts) AS merchant_country,
  CAST(count(DISTINCT outlet_id) AS BIGINT) AS outlet_count,
  min(auth_date) AS first_txn_date,
  max(auth_date) AS last_txn_date
FROM transactions
GROUP BY merchant_id;
