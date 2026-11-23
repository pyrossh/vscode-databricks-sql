-- Auto Loader ingest of landing/fx_ecb/<batch_id>/*.csv, all columns as text.
-- Same options as src/lib/autoloader.py: strings only (typing happens in Silver), addNewColumns schema
-- evolution, rescued data column. read_files exposes the file path via _metadata.
CREATE OR REFRESH STREAMING TABLE fx_ecb_raw
COMMENT 'Raw ECB euro foreign exchange reference rates (units per EUR) as landed.'
TBLPROPERTIES (
  'quality' = 'bronze',
  'data_classification' = 'public'
)
AS SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at,
  regexp_extract(_metadata.file_path, '/fx_ecb/([^/]+)/', 1) AS _batch_id
FROM STREAM read_files(
  '${merchant_monthly_totals.landing_root}/fx_ecb/',
  format => 'csv',
  header => true,
  inferColumnTypes => false,
  schemaEvolutionMode => 'addNewColumns',
  rescuedDataColumn => '_rescued_data',
  pathGlobFilter => '*.csv'
);
