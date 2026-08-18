-- Snowflake account-level setup: CI + Prod role/database separation for
-- state-based ("Slim") CI.
--
-- This is NOT run by dbt or CI. Run it manually in Snowflake (Snowsight
-- worksheet or SnowSQL) using roles that can manage roles/grants
-- (SECURITYADMIN) and create schemas (SYSADMIN, or whichever role owns
-- RAW today). It's checked into version control so the role/grant model
-- is auditable and reproducible, matching the convention set by
-- setup_reporting_role.sql.
--
-- Why this exists: today DATA_ENGINEER is the only transform role, shared
-- by local dev and CI alike, and CI runs a full `dbt build` against the
-- same DEV_ANALYTICS database dev uses (see dbt_test.yml / CLAUDE.md's CI
-- section). This introduces genuine environment separation:
--   - DEV_ROLE  (new) - equivalent access to what DATA_ENGINEER holds
--                today, local dev only. DATA_ENGINEER itself is left
--                untouched by this script - not renamed, not dropped. If
--                it's no longer needed once DEV_ROLE is in use, drop it
--                manually and separately; this script doesn't assume
--                anything about its fate.
--   - CI_ROLE   (new) - builds PR branches into their own throwaway flat
--                schema inside CI_ANALYTICS, reading unmodified state from
--                PRD_ANALYTICS via `--defer`.
--   - PROD_ROLE (new) - the only role with write access to PRD_ANALYTICS,
--                used exclusively by the new main-branch deploy workflow.
--
-- Database state this script assumes (see setup_databases.sql, which
-- establishes/no-ops on all of these):
--   - RAW           -> exists (renamed from DEV_RAW manually, outside this
--                      script). Its FOOTBALL schema is created fresh here
--                      (section 3) rather than renamed from PUBLIC - the
--                      raw data was never actually in RAW's default
--                      PUBLIC schema (it turned up loaded into
--                      PRD_ANALYTICS by mistake; see
--                      migrate_raw_data_from_prd_analytics.sql for
--                      recovering it into RAW.FOOTBALL, and
--                      setup_raw_stage.sql for future reloads). PUBLIC is
--                      left alone, harmless and unused - drop it later
--                      once you've confirmed nothing's in it.
--   - CI_ANALYTICS  -> exists (established directly by setup_databases.sql
--                      rather than renamed from STG_ANALYTICS here - if
--                      STG_ANALYTICS/STG_RAW still exist as leftovers,
--                      drop them manually once you've confirmed
--                      CI_ANALYTICS has everything it needs).
--
-- Prerequisite: run setup_databases.sql first.
--
-- Run top to bottom in a single worksheet session, in order - grants in
-- section 4 assume the roles/schema from sections 2-3 already exist.

-- =====================================================================
-- 1. Switch to SECURITYADMIN for role management.
-- =====================================================================
USE ROLE SECURITYADMIN;
-- =====================================================================
-- 2. Create the three roles fresh. DATA_ENGINEER is left as-is (see
--    header) - these are new roles, not renames, so section 4 grants
--    every privilege each one needs from scratch.
-- =====================================================================
CREATE ROLE IF NOT EXISTS DEV_ROLE;
CREATE ROLE IF NOT EXISTS CI_ROLE;
CREATE ROLE IF NOT EXISTS PROD_ROLE;
-- =====================================================================
-- 3. Ensure RAW.FOOTBALL exists - the schema the raw tables actually
--    live in (see header). CI_ANALYTICS is assumed to already exist via
--    setup_databases.sql, so there's nothing else to do here.
-- =====================================================================
USE ROLE SYSADMIN;

CREATE SCHEMA IF NOT EXISTS RAW.FOOTBALL;

-- =====================================================================
-- 4. Grants.
-- =====================================================================
USE ROLE SECURITYADMIN;

-- --- DEV_ROLE: privileges matching what DATA_ENGINEER holds today. -----
GRANT USAGE ON WAREHOUSE DEV_TRANSFORM_WH TO ROLE DEV_ROLE;

GRANT ALL ON DATABASE DEV_ANALYTICS TO ROLE DEV_ROLE;
GRANT ALL ON ALL SCHEMAS IN DATABASE DEV_ANALYTICS TO ROLE DEV_ROLE;
GRANT ALL ON FUTURE SCHEMAS IN DATABASE DEV_ANALYTICS TO ROLE DEV_ROLE;
GRANT ALL ON ALL TABLES IN DATABASE DEV_ANALYTICS TO ROLE DEV_ROLE;
GRANT ALL ON FUTURE TABLES IN DATABASE DEV_ANALYTICS TO ROLE DEV_ROLE;
GRANT ALL ON ALL VIEWS IN DATABASE DEV_ANALYTICS TO ROLE DEV_ROLE;
GRANT ALL ON FUTURE VIEWS IN DATABASE DEV_ANALYTICS TO ROLE DEV_ROLE;

GRANT USAGE ON DATABASE RAW TO ROLE DEV_ROLE;
GRANT USAGE ON SCHEMA RAW.FOOTBALL TO ROLE DEV_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA RAW.FOOTBALL TO ROLE DEV_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW.FOOTBALL TO ROLE DEV_ROLE;

-- --- CI_ROLE -----------------------------------------------------------
-- Read raw (to build modified staging models fresh from source)...
GRANT USAGE ON WAREHOUSE DEV_TRANSFORM_WH TO ROLE CI_ROLE;
GRANT USAGE ON DATABASE RAW TO ROLE CI_ROLE;
GRANT USAGE ON SCHEMA RAW.FOOTBALL TO ROLE CI_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA RAW.FOOTBALL TO ROLE CI_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW.FOOTBALL TO ROLE CI_ROLE;

-- ...read all of prod, current + future, so `--defer` can resolve refs
-- to models this PR run didn't rebuild itself...
GRANT USAGE ON DATABASE PRD_ANALYTICS TO ROLE CI_ROLE;
GRANT USAGE ON ALL SCHEMAS IN DATABASE PRD_ANALYTICS TO ROLE CI_ROLE;
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE PRD_ANALYTICS TO ROLE CI_ROLE;
GRANT SELECT ON ALL TABLES IN DATABASE PRD_ANALYTICS TO ROLE CI_ROLE;
GRANT SELECT ON FUTURE TABLES IN DATABASE PRD_ANALYTICS TO ROLE CI_ROLE;
GRANT SELECT ON ALL VIEWS IN DATABASE PRD_ANALYTICS TO ROLE CI_ROLE;
GRANT SELECT ON FUTURE VIEWS IN DATABASE PRD_ANALYTICS TO ROLE CI_ROLE;

-- ...and full DDL scoped to its own database only. CI_ROLE never gets any
-- write grant on PRD_ANALYTICS or DEV_ANALYTICS. CREATE SCHEMA is the
-- single most important grant here - each PR run needs to create its own
-- flat schema on demand (CI_ANALYTICS.pr_123 etc); it's already covered
-- by the ALL grant below but called out explicitly since the whole
-- per-PR-schema design depends on it.
GRANT CREATE SCHEMA ON DATABASE CI_ANALYTICS TO ROLE CI_ROLE;
GRANT ALL ON DATABASE CI_ANALYTICS TO ROLE CI_ROLE;
GRANT ALL ON ALL SCHEMAS IN DATABASE CI_ANALYTICS TO ROLE CI_ROLE;
GRANT ALL ON FUTURE SCHEMAS IN DATABASE CI_ANALYTICS TO ROLE CI_ROLE;
GRANT ALL ON ALL TABLES IN DATABASE CI_ANALYTICS TO ROLE CI_ROLE;
GRANT ALL ON FUTURE TABLES IN DATABASE CI_ANALYTICS TO ROLE CI_ROLE;
GRANT ALL ON ALL VIEWS IN DATABASE CI_ANALYTICS TO ROLE CI_ROLE;
GRANT ALL ON FUTURE VIEWS IN DATABASE CI_ANALYTICS TO ROLE CI_ROLE;

-- --- PROD_ROLE -----------------------------------------------------------
GRANT USAGE ON WAREHOUSE DEV_TRANSFORM_WH TO ROLE PROD_ROLE;

GRANT USAGE ON DATABASE RAW TO ROLE PROD_ROLE;
GRANT USAGE ON SCHEMA RAW.FOOTBALL TO ROLE PROD_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA RAW.FOOTBALL TO ROLE PROD_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW.FOOTBALL TO ROLE PROD_ROLE;

GRANT ALL ON DATABASE PRD_ANALYTICS TO ROLE PROD_ROLE;
GRANT ALL ON ALL SCHEMAS IN DATABASE PRD_ANALYTICS TO ROLE PROD_ROLE;
GRANT ALL ON FUTURE SCHEMAS IN DATABASE PRD_ANALYTICS TO ROLE PROD_ROLE;
GRANT ALL ON ALL TABLES IN DATABASE PRD_ANALYTICS TO ROLE PROD_ROLE;
GRANT ALL ON FUTURE TABLES IN DATABASE PRD_ANALYTICS TO ROLE PROD_ROLE;
GRANT ALL ON ALL VIEWS IN DATABASE PRD_ANALYTICS TO ROLE PROD_ROLE;
GRANT ALL ON FUTURE VIEWS IN DATABASE PRD_ANALYTICS TO ROLE PROD_ROLE;

-- =====================================================================
-- 5. Grant all three roles to the existing solo-project user. Same
--    pattern as FOOTBALL_REPORTING in setup_reporting_role.sql: one user
--    holding multiple roles, switching via each dbt target's `role:`
--    field - no new Snowflake user needed.
-- =====================================================================
GRANT ROLE DEV_ROLE TO USER MCBREESE;
GRANT ROLE CI_ROLE TO USER MCBREESE;
GRANT ROLE PROD_ROLE TO USER MCBREESE;
