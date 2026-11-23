-- Rows that fail any rule in src/lib/rules.py (TXN_RULES). The failed_rules expression below is the
-- same text as the DROP ROW constraints on transactions_checked in silver/transactions.sql
-- (tests/test_sql_pipeline.py checks they agree), so a row is in exactly one of the two places.
-- Fully qualified into the restricted schema so analyst grants on the main schema never expose it.
CREATE OR REFRESH STREAMING TABLE ${merchant_monthly_totals.restricted_schema}.transactions_quarantine
COMMENT 'Transactions that failed one or more data quality rules. RESTRICTED: lives in the restricted schema.'
TBLPROPERTIES (
  'quality' = 'quarantine',
  'data_classification' = 'restricted'
)
AS SELECT
  *,
  current_timestamp() AS _quarantined_at
FROM (
  SELECT
    *,
    array_compact(array(
      CASE WHEN NOT (coalesce(trim(txn_id) <> '', false)) THEN 'txn_id_present' END,
      CASE WHEN NOT (coalesce(trim(merchant_id) <> '', false)) THEN 'merchant_id_present' END,
      CASE WHEN NOT (coalesce(try_cast(amount_minor AS BIGINT) > 0, false)) THEN 'amount_is_positive_integer' END,
      CASE WHEN NOT (coalesce(currency IN ('AUD', 'CAD', 'CHF', 'DKK', 'EUR', 'GBP', 'JPY', 'NOK', 'PLN', 'SEK', 'USD'), false)) THEN 'currency_supported' END,
      CASE WHEN NOT (coalesce(txn_type IN ('SALE', 'REFUND', 'CHARGEBACK'), false)) THEN 'txn_type_known' END,
      CASE WHEN NOT (try_cast(auth_ts AS TIMESTAMP) IS NOT NULL) THEN 'auth_ts_parses' END,
      CASE WHEN NOT (settle_date IS NULL OR coalesce(try_cast(settle_date AS DATE) >= to_date(try_cast(auth_ts AS TIMESTAMP)), false)) THEN 'settle_not_before_auth' END,
      CASE WHEN NOT (_rescued_data IS NULL) THEN 'no_rescued_data' END
    )) AS failed_rules
  FROM STREAM(transactions_raw)
)
WHERE size(failed_rules) > 0;
