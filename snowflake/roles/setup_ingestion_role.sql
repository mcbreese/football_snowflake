-- Snowflake account-level setup: dedicated role for the RAW.FOOTBALL
-- ingestion procedure, replacing the ad-hoc worksheet's SYSADMIN.
--
-- NOT run by dbt or CI - run manually via Snowsight/SnowSQL, same as the
-- other snowflake/*.sql scripts. Run this BEFORE finishing
-- ../ingestion/create_s3_stage.sql (which grants this role USAGE on the
-- storage integration) and before
-- ../ingestion/load_raw_football_procedure.sql (owned by this role).
--
-- Why a dedicated role instead of SYSADMIN: every other piece of access
-- in this project (DEV_ROLE/CI_ROLE/PROD_ROLE, CLAUDE_READONLY_ROLE,
-- CLAUDE_MCP_ROLE, FOOTBALL_REPORTING) is scoped to exactly what it
-- needs, not a broad built-in role - see setup_reporting_role.sql /
-- setup_claude_readonly_role.sql for the established pattern. This is a
-- solo project with one real operator running this procedure manually,
-- so the practical blast-radius difference vs. SYSADMIN is small today;
-- the value is not leaving SYSADMIN as the one remaining unscoped path
-- into RAW.FOOTBALL.
--
-- Prerequisite: RAW.FOOTBALL and CSV_STANDARD_FORMAT must already exist
-- (../ingestion/setup_raw_stage.sql). football_s3_stage doesn't need to
-- exist yet - the USAGE grant on it below just needs to run after
-- ../ingestion/create_s3_stage.sql creates it.

USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS RAW_INGESTION_ROLE
  COMMENT = 'Runs the RAW.FOOTBALL load procedure from the S3 external stage. Manual invocation only - no task, no schedule.';

-- The ad-hoc worksheet this replaces used DEV_LOADING_WH, not
-- DEV_TRANSFORM_WH (the dbt transform warehouse) - reusing it here
-- rather than creating a new one, per the existing cost-capped XSMALL
-- sizing.
GRANT USAGE ON WAREHOUSE DEV_LOADING_WH TO ROLE RAW_INGESTION_ROLE;

GRANT USAGE ON DATABASE RAW TO ROLE RAW_INGESTION_ROLE;
GRANT USAGE ON SCHEMA RAW.FOOTBALL TO ROLE RAW_INGESTION_ROLE;

-- Needed to (re)create the raw_* tables from INFER_SCHEMA and to create
-- the procedure itself.
GRANT CREATE TABLE ON SCHEMA RAW.FOOTBALL TO ROLE RAW_INGESTION_ROLE;
GRANT CREATE PROCEDURE ON SCHEMA RAW.FOOTBALL TO ROLE RAW_INGESTION_ROLE;

-- No table-level SELECT/INSERT grants needed - this role owns every
-- raw_* table it creates (CREATE OR REPLACE TABLE runs as this role),
-- and Snowflake automatically grants full privileges on an object to
-- its owner.

GRANT USAGE ON STAGE RAW.FOOTBALL.football_s3_stage TO ROLE RAW_INGESTION_ROLE;
GRANT USAGE ON FILE FORMAT RAW.FOOTBALL.CSV_STANDARD_FORMAT TO ROLE RAW_INGESTION_ROLE;
-- USAGE ON INTEGRATION football_s3_int is granted in
-- ../ingestion/create_s3_stage.sql (ACCOUNTADMIN-owned object, granted
-- under SECURITYADMIN there rather than duplicated here).

-- Same solo-project, multi-role pattern as every other role here (see
-- setup_reporting_role.sql) - one user holding several roles, switched
-- via USE ROLE.
GRANT ROLE RAW_INGESTION_ROLE TO USER MCBREESE;
