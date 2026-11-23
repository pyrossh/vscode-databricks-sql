-- Auto Loader ingest of landing/fx_hmrc/<batch_id>/*.csv, all columns as text.
-- Same options as src/lib/autoloader.py: strings only (typing happens in Silver), addNewColumns schema
-- evolution, rescued data column. read_files exposes the file path via _metadata.
CREATE OR REFRESH STREAMING TABLE fx_hmrc_raw
COMMENT 'Raw HMRC monthly exchange rates (units per GBP) as landed, normalised headers.'
TBLPROPERTIES (
  'quality' = 'bronze',
  'data_classification' = 'public'
)
AS SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at,
  regexp_extract(_metadata.file_path, '/fx_hmrc/([^/]+)/', 1) AS _batch_id
FROM STREAM read_files(
  '${merchant_monthly_totals.landing_root}/fx_hmrc/',
  format => 'csv',
  header => true,
  inferColumnTypes => false,
  schemaEvolutionMode => 'addNewColumns',
  rescuedDataColumn => '_rescued_data',
  pathGlobFilter => '*.csv'
);
