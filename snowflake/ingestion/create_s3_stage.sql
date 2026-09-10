-- Storage integration + external stage for S3-based raw CSV ingestion,
-- replacing the internal-stage manual-upload path documented in
-- setup_raw_stage.sql.
--
-- NOT run by dbt or CI - run manually via Snowsight/SnowSQL, same as the
-- other snowflake/*.sql scripts.
--
-- TEMPLATE FILE - <your-aws-iam-role-arn> and <your-s3-bucket-path>
-- below are placeholders, not real values. This keeps this account's AWS
-- topology (account ID, IAM role, bucket path) out of git. Before
-- running, fill them in locally with the real values, then never commit
-- the filled-in version - if you've lost track of the real values,
-- Snowflake itself still has them: `DESCRIBE STORAGE INTEGRATION
-- football_s3_int;` (STORAGE_AWS_ROLE_ARN, STORAGE_ALLOWED_LOCATIONS)
-- and `SHOW STAGES IN SCHEMA RAW.FOOTBALL;` (url column) both surface
-- the live values.
--
-- Both objects already exist live in the account as of 2026-09-10,
-- created before DIRECTORY was added below - the CREATE ... IF NOT
-- EXISTS statements are no-ops against that existing state; only the
-- ALTER STAGE / GRANT statements actually change anything on a re-run.
--
-- Prerequisite: run ../roles/setup_ingestion_role.sql first - the GRANT
-- at the bottom of this file targets RAW_INGESTION_ROLE, created there.

USE ROLE ACCOUNTADMIN;

-- Storage integrations can only be created, or have properties altered,
-- by ACCOUNTADMIN or a role holding the global CREATE INTEGRATION
-- privilege.
CREATE STORAGE INTEGRATION IF NOT EXISTS football_s3_int
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = '<your-aws-iam-role-arn>'
  STORAGE_ALLOWED_LOCATIONS = ('<your-s3-bucket-path>');

USE ROLE SYSADMIN;

-- DIRECTORY = (ENABLE = TRUE) is required for the DIRECTORY() table
-- function the ingestion procedure uses to list staged files (see
-- load_raw_football_procedure.sql) - without it, DIRECTORY() raises
-- "Directory table is not enabled".
CREATE STAGE IF NOT EXISTS RAW.FOOTBALL.football_s3_stage
  URL = '<your-s3-bucket-path>'
  STORAGE_INTEGRATION = football_s3_int
  FILE_FORMAT = RAW.FOOTBALL.CSV_STANDARD_FORMAT
  DIRECTORY = (ENABLE = TRUE);

-- Applies DIRECTORY to the stage if it already existed before the
-- CREATE STAGE above was updated to include it (CREATE STAGE IF NOT
-- EXISTS is a no-op against an already-existing stage, so it wouldn't
-- retroactively enable this on its own).
ALTER STAGE RAW.FOOTBALL.football_s3_stage SET DIRECTORY = (ENABLE = TRUE);

-- Refresh once so DIRECTORY() has something to list immediately, rather
-- than waiting on the procedure's own ALTER STAGE ... REFRESH.
ALTER STAGE RAW.FOOTBALL.football_s3_stage REFRESH;

-- =====================================================================
-- Grant USAGE on the integration to the ingestion role - a separate
-- privilege from USAGE on the stage (granted in
-- ../roles/setup_ingestion_role.sql), both are required. Integrations are
-- ACCOUNTADMIN-owned, so this grant has to live here rather than in the
-- role setup script, which only runs as SECURITYADMIN/SYSADMIN.
-- =====================================================================
USE ROLE SECURITYADMIN;

GRANT USAGE ON INTEGRATION football_s3_int TO ROLE RAW_INGESTION_ROLE;
