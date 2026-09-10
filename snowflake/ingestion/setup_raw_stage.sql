-- Snowflake account-level setup: raw CSV landing stage + file format for
-- RAW.FOOTBALL.
--
-- This is NOT run by dbt or CI - run manually via Snowsight/SnowSQL, same
-- as the other snowflake/*.sql scripts. Formalizes the manual-CSV-load
-- process as checked-in IaC (a named stage + file format) instead of
-- whatever ad-hoc method previously got the raw data loaded into the
-- wrong database (PRD_ANALYTICS) by mistake.
--
-- Prerequisite: RAW.FOOTBALL must exist (created by
-- ../roles/setup_ci_prod_roles.sql section 3 - this script also creates
-- it defensively via IF NOT EXISTS, so it's safe to run either order).
--
-- The actual load path is now load_raw_football_procedure.sql, reading
-- from the S3 external stage in create_s3_stage.sql - see that file
-- for the current reload procedure. RAW_LANDING_STAGE below is kept for
-- CSV_STANDARD_FORMAT, which the external stage also reuses, but the
-- stage object itself is DEPRECATED: nothing loads through it anymore.
-- Not dropped yet - keeping it until the new S3-backed procedure has had
-- at least one confirmed successful real run. Once confirmed, drop it
-- with `DROP STAGE RAW.FOOTBALL.RAW_LANDING_STAGE;`.

USE ROLE SYSADMIN;

CREATE SCHEMA IF NOT EXISTS RAW.FOOTBALL;

-- SKIP_HEADER=1 + EMPTY_FIELD_AS_NULL: matches the standard shape of the
-- Transfermarkt Kaggle CSVs this project ingests (header row, quoted
-- strings, blank cells meaning NULL rather than empty string).
CREATE FILE FORMAT IF NOT EXISTS RAW.FOOTBALL.CSV_STANDARD_FORMAT
  TYPE = CSV
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL', 'null')
  EMPTY_FIELD_AS_NULL = TRUE
  COMMENT = 'Standard CSV format for manually-loaded raw football data.';

-- DEPRECATED - superseded by the S3 external stage (create_s3_stage.sql)
-- and load_raw_football_procedure.sql. Left in place, unused, until a
-- confirmed successful real run of the new procedure; see note above.
CREATE STAGE IF NOT EXISTS RAW.FOOTBALL.RAW_LANDING_STAGE
  FILE_FORMAT = RAW.FOOTBALL.CSV_STANDARD_FORMAT
  COMMENT = 'DEPRECATED - superseded by football_s3_stage. Was the upload target for manually-loaded raw CSVs.';
