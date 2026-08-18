-- Snowflake account-level setup: baseline databases for
-- dbt_football_snowflake, backdated as IaC.
--
-- These databases have only ever existed via manual creation in the
-- Snowflake UI - the same gap already flagged for DEV_TRANSFORM_WH in the
-- 16/08/2026 cost/governance review (see README logbook: warehouse sizing
-- confirmed but "the setting itself still lives only in the Snowflake UI,
-- not as a checked-in script"). This formalizes that baseline as
-- checked-in, reproducible SQL instead of leaving it undocumented.
--
-- CREATE DATABASE IF NOT EXISTS makes this safe to run regardless of which
-- of these already exist in the account. Note: DEV_RAW has already been
-- manually renamed to RAW (see setup_ci_prod_roles.sql), so this script
-- targets RAW directly rather than DEV_RAW - only relevant if you're
-- setting up a fresh account from scratch, where you'd create DEV_RAW
-- instead and let setup_ci_prod_roles.sql do the rename.
--
-- NOT run by dbt or CI - run manually, same as the other snowflake/*.sql
-- scripts. Run this BEFORE setup_ci_prod_roles.sql - that script renames
-- and drops these databases, and needs them to exist first.

USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS DEV_ANALYTICS
  COMMENT = 'dbt_football_snowflake - dev target output database (DEV_ROLE)';

CREATE DATABASE IF NOT EXISTS RAW
  COMMENT = 'dbt_football_snowflake - shared raw CSV landing zone (dev/ci/prod)';

CREATE DATABASE IF NOT EXISTS PRD_ANALYTICS
  COMMENT = 'dbt_football_snowflake - prod target output database (PROD_ROLE)';

CREATE DATABASE IF NOT EXISTS CI_ANALYTICS
  COMMENT = 'dbt_football_snowflake - ci target output database (CI_ROLE)';