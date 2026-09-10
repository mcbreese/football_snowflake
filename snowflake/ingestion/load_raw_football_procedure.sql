-- Version-controlled replacement for the ad-hoc ingestion worksheet.
-- Loads every CSV currently staged in football_s3_stage into a matching
-- RAW.FOOTBALL.RAW_<NAME> table - full replace each run (snapshot data,
-- no incremental/dedup logic, see CLAUDE.md).
--
-- NOT run by dbt or CI - manual invocation only, no task/schedule.
-- USE WAREHOUSE has to happen in the calling session, not inside the
-- procedure body (Snowflake Scripting rejects USE statements inside a
-- procedure with STATEMENT_ERROR: "Unsupported statement type 'USE'") -
-- same reason the original worksheet ran it as a plain top-level
-- statement before its EXECUTE IMMEDIATE block, not inside it:
--   USE WAREHOUSE DEV_LOADING_WH;
--   CALL RAW.FOOTBALL.LOAD_RAW_FOOTBALL();
--
-- Supersedes the worksheet this project used before: same INFER_SCHEMA +
-- CREATE OR REPLACE TABLE + COPY INTO mechanics (IGNORE_CASE,
-- MATCH_BY_COLUMN_NAME, INCLUDE_METADATA for source_file/loaded_timestamp
-- all preserved as-is), now version-controlled and pointed at the S3
-- external stage instead of the internal upload stage. Test scaffolding
-- removed: the '%transfer%' RELATIVE_PATH filter, the RAW_TEST_ table
-- prefix, the RETURN that short-circuited the loop after the first file,
-- and the commented-out COPY.
--
-- Schema inference (INFER_SCHEMA) is deliberate, not a gap to fix here -
-- the data contract lives in the dbt staging layer, not in hand-written
-- RAW DDL. This procedure only formalizes load mechanics; it doesn't
-- change what RAW tables look like.
--
-- Runs EXECUTE AS OWNER (owned by RAW_INGESTION_ROLE - see
-- ../roles/setup_ingestion_role.sql, must be run first): needs CREATE TABLE,
-- ALTER STAGE, and COPY INTO inside RAW.FOOTBALL regardless of caller,
-- and with manual-invocation-only by a single operator, CALLER'S RIGHTS
-- would just re-impose "does my active role hold all these grants" on
-- every run for no real security benefit.
--
-- Not yet run against Snowflake by Claude - CLAUDE_READONLY_ROLE has no
-- write path, so this hasn't been execution-tested. Try
-- CALL RAW.FOOTBALL.LOAD_RAW_FOOTBALL(); as RAW_INGESTION_ROLE and debug
-- any Scripting syntax issues interactively before relying on it - see
-- cutover_validation.sql for the clone-first, compare-after safety net
-- to run alongside that first real invocation.

USE ROLE RAW_INGESTION_ROLE;

CREATE OR REPLACE PROCEDURE RAW.FOOTBALL.LOAD_RAW_FOOTBALL()
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  file_cursor CURSOR FOR
    SELECT RELATIVE_PATH AS file_path
    FROM DIRECTORY(@RAW.FOOTBALL.football_s3_stage)
    WHERE RELATIVE_PATH LIKE '%.csv';

  clean_table_name STRING;
  full_table_path  STRING;
  sql_create       STRING;
  sql_alter        STRING;
  sql_copy         STRING;
  rows_loaded      INTEGER;
  results          ARRAY DEFAULT ARRAY_CONSTRUCT();
BEGIN
  ALTER STAGE RAW.FOOTBALL.football_s3_stage REFRESH;

  FOR record IN file_cursor DO
    -- 'transfers.csv' -> 'RAW_TRANSFERS' (no RAW_TEST_ prefix, no
    -- '%transfer%' filter on the cursor above - every staged CSV is
    -- processed).
    clean_table_name := 'RAW_' || UPPER(REPLACE(record.file_path, '.csv', ''));
    full_table_path  := 'RAW.FOOTBALL.' || clean_table_name;

    -- 1. Infer schema directly from the staged file and (re)create the
    --    table - full replace, matching the snapshot/full-refresh load
    --    pattern this project uses everywhere.
    sql_create := 'CREATE OR REPLACE TABLE ' || full_table_path || '
      USING TEMPLATE (
        SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*))
        FROM TABLE(
          INFER_SCHEMA(
            LOCATION => ''@RAW.FOOTBALL.football_s3_stage/' || record.file_path || ''',
            FILE_FORMAT => ''RAW.FOOTBALL.CSV_STANDARD_FORMAT'',
            IGNORE_CASE => TRUE
          )
        )
      )';
    EXECUTE IMMEDIATE sql_create;

    -- 2. Add the lineage columns the staging models expect (see
    --    models/staging/stg_*.sql).
    sql_alter := 'ALTER TABLE ' || full_table_path || ' ADD COLUMN
      SOURCE_FILE STRING,
      LOADED_TIMESTAMP TIMESTAMP_NTZ';
    EXECUTE IMMEDIATE sql_alter;

    -- 3. Load the data, matching columns by header name and populating
    --    lineage columns from COPY's own metadata rather than a
    --    transformation subquery. This is now a real EXECUTE IMMEDIATE,
    --    not commented out, and runs for every file - no RETURN inside
    --    the loop cutting it short after the first.
    sql_copy := 'COPY INTO ' || full_table_path || '
      FROM @RAW.FOOTBALL.football_s3_stage/' || record.file_path || '
      FILE_FORMAT = (
        FORMAT_NAME = ''RAW.FOOTBALL.CSV_STANDARD_FORMAT''
      )
      MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
      INCLUDE_METADATA = (
        SOURCE_FILE = METADATA$FILENAME,
        LOADED_TIMESTAMP = METADATA$START_SCAN_TIME
      )';
    EXECUTE IMMEDIATE sql_copy;

    -- COPY INTO's own result set carries rows_loaded per file - pull it
    -- out so the final summary has real counts to verify a manual run
    -- against, instead of a fixed success string.
    SELECT SUM("rows_loaded") INTO :rows_loaded
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    results := ARRAY_APPEND(results, OBJECT_CONSTRUCT(
      'file', record.file_path,
      'table', full_table_path,
      'rows_loaded', rows_loaded
    ));
  END FOR;

  RETURN OBJECT_CONSTRUCT(
    'files_processed', ARRAY_SIZE(results),
    'tables_created', ARRAY_SIZE(results),
    'tables', results
  );
END;
$$;
