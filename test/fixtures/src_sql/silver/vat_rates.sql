-- Silver VAT rates, read from Bronze vat_rates_raw (landing/reference/vat_rates.csv).
--
-- ILLUSTRATIVE ONLY. The real tax treatment of acquiring (parts are VAT-exempt) is an open
-- question for tax review.
--
-- The file is a single full snapshot rebuilt every run, so there is no dedup; no_overlapping_validity
-- still catches duplicate or overlapping rows inside it (same typing as lib.transforms.type_vat_rates).
--
-- Why a view: no_overlapping_validity needs a window (lead(valid_from) per country), and an
-- expectation can only see the columns of the dataset it is attached to. The helper column
-- next_valid_from lives on this view; the materialized view below selects only the declared
-- columns, so the helper never reaches the output. The Python pipeline uses the same shape.
-- CREATE TEMPORARY VIEW cannot carry CONSTRAINT clauses, hence CREATE LIVE VIEW.
CREATE LIVE VIEW vat_rates_checked (
  CONSTRAINT no_overlapping_validity EXPECT (next_valid_from IS NULL OR coalesce(valid_to < next_valid_from, false)) ON VIOLATION FAIL UPDATE
)
AS SELECT
  *,
  lead(valid_from) OVER (PARTITION BY country_code ORDER BY valid_from) AS next_valid_from
FROM (
  SELECT
    upper(trim(country_code)) AS country_code,
    try_cast(trim(vat_rate) AS DECIMAL(5,4)) AS vat_rate,
    try_cast(trim(valid_from) AS DATE) AS valid_from,
    try_cast(trim(valid_to) AS DATE) AS valid_to,
    trim(note) AS note
  FROM vat_rates_raw
);

CREATE OR REFRESH MATERIALIZED VIEW vat_rates (
  country_code STRING COMMENT 'ISO 3166 alpha-2 country.',
  vat_rate DECIMAL(5,4) COMMENT 'Standard VAT rate as a fraction (0.2000 = 20%). ILLUSTRATIVE ONLY.',
  valid_from DATE COMMENT 'First date the rate applies (inclusive).',
  valid_to DATE COMMENT 'Last date the rate applies (inclusive); NULL means still current.',
  note STRING COMMENT 'Free-text note about the rate.',
  CONSTRAINT rate_in_range EXPECT (vat_rate >= 0 AND vat_rate < 1) ON VIOLATION FAIL UPDATE,
  CONSTRAINT valid_range_ordered EXPECT (valid_to IS NULL OR valid_to >= valid_from) ON VIOLATION FAIL UPDATE
)
COMMENT 'VAT rates by country with validity dates. ILLUSTRATIVE seed data, not a tax position.'
TBLPROPERTIES (
  'quality' = 'silver',
  'data_classification' = 'internal'
)
AS SELECT country_code, vat_rate, valid_from, valid_to, note
FROM vat_rates_checked;
