-- Snowflake account-level setup: raw CSV landing stage + file format for
-- RAW.FOOTBALL.
--
-- This is NOT run by dbt or CI - run manually via Snowsight/SnowSQL, same
-- as the other snowflake/*.sql scripts. Formalizes the manual-CSV-load
-- process as checked-in IaC (a named stage + file format) instead of
-- whatever ad-hoc method previously got the raw data loaded into the
-- wrong database (PRD_ANALYTICS) by mistake.
--
-- Prerequisite: RAW.FOOTBALL must exist (created by setup_ci_prod_roles.sql
-- section 3 - this script also creates it defensively via IF NOT EXISTS,
-- so it's safe to run either order).
--
-- After running this script, see the reload procedure (README-style
-- comment at the bottom) for actually getting data into RAW.FOOTBALL's
-- tables - table DDL isn't included here because it needs to match the
-- real CSV headers, which INFER_SCHEMA reads directly from the staged
-- files rather than guessing.

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

CREATE STAGE IF NOT EXISTS RAW.FOOTBALL.RAW_LANDING_STAGE
  FILE_FORMAT = RAW.FOOTBALL.CSV_STANDARD_FORMAT
  COMMENT = 'Upload target for manually-loaded raw CSVs, before COPY INTO into raw_* tables.';

-- =====================================================================
-- Reload procedure (run once per raw_* table, after this script):
--
-- 1. Upload the CSV to the stage. Easiest via Snowsight: open the
--    RAW_LANDING_STAGE object -> "+ Files" -> upload e.g. players.csv.
--    (Or via SnowSQL: `PUT file://path/to/players.csv @RAW.FOOTBALL.RAW_LANDING_STAGE;`)
--
-- 2. Infer the real column structure directly from the staged file - no
--    guessing column names/types by hand:
--
--      CREATE OR REPLACE TABLE RAW.FOOTBALL.raw_players
--      USING TEMPLATE (
--          SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) WITHIN GROUP (ORDER BY ORDER_ID)
--          FROM TABLE(
--              INFER_SCHEMA(
--                  LOCATION => '@RAW.FOOTBALL.RAW_LANDING_STAGE/players.csv',
--                  FILE_FORMAT => 'RAW.FOOTBALL.CSV_STANDARD_FORMAT'
--              )
--          )
--      );
--
-- 3. Add the lineage columns the staging models expect (see
--    models/staging/stg_*.sql - every raw table carries loaded_timestamp
--    + source_file, which aren't in the CSV itself):
--
--      ALTER TABLE RAW.FOOTBALL.raw_players
--          ADD COLUMN loaded_timestamp TIMESTAMP_NTZ,
--                     source_file VARCHAR;
--
-- 4. Load the data, populating the lineage columns per row:
--
--      COPY INTO RAW.FOOTBALL.raw_players
--      FROM (
--          SELECT s.*, CURRENT_TIMESTAMP(), METADATA$FILENAME
--          FROM @RAW.FOOTBALL.RAW_LANDING_STAGE/players.csv s
--      )
--      FILE_FORMAT = (FORMAT_NAME = 'RAW.FOOTBALL.CSV_STANDARD_FORMAT')
--      ON_ERROR = 'ABORT_STATEMENT';
--
-- Repeat steps 1-4 for each of the 7 source tables declared in
-- models/staging/sources/stg_sources.yml: raw_appearances, raw_clubs,
-- raw_competitions, raw_games, raw_player_valuations, raw_players,
-- raw_transfers. Swap the table name and staged filename each time -
-- exact local CSV filenames aren't assumed here, use whatever yours
-- actually are.
-- =====================================================================
