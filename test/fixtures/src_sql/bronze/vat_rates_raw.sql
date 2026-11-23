-- Bronze VAT rates: a BATCH materialized view, not an Auto Loader streaming table.
-- The VAT file (landing/reference/vat_rates.csv) is always a single file holding the full current
-- set. A materialized view over files is fully recomputed on every run, so this table always
-- mirrors the current file. History lives in git (reference/vat_rates.csv), not in Bronze.
-- All columns as text (typing happens in Silver).
CREATE OR REFRESH MATERIALIZED VIEW vat_rates_raw
COMMENT 'Raw VAT rates by country with validity dates as landed. ILLUSTRATIVE seed data, not a tax position.'
TBLPROPERTIES (
  'quality' = 'bronze',
  'data_classification' = 'internal'
)
AS SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at,
  _metadata.file_modification_time AS _file_modified_at
FROM read_files(
  '${merchant_monthly_totals.landing_root}/reference/vat_rates.csv',
  format => 'csv',
  header => true,
  inferColumnTypes => false
);
