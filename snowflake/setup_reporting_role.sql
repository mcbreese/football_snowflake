-- Snowflake account-level setup: read-only reporting role.
--
-- This is NOT run by dbt or CI. Run it manually in Snowflake (Snowsight
-- worksheet or SnowSQL) using a role that can create roles and manage
-- grants (e.g. SECURITYADMIN). It's checked into version control so the
-- role/grant model is auditable and reproducible rather than living only
-- as manual clicks in the Snowflake UI.
--
-- Why this exists: today the DATA_ENGINEER role (used by both local dev
-- and CI, per dbt_football_snowflake/profiles.yml) is the only role in
-- the project — it has full transform privileges (CREATE OR REPLACE
-- TABLE etc.) and would also be the role any BI/reporting consumer used,
-- since nothing else exists. FOOTBALL_REPORTING is scoped to read-only
-- SELECT on the gold layer only — not staging/intermediate, which can
-- carry known/unresolved data-quality issues (see stg_appearances /
-- stg_games) that a reporting consumer shouldn't be exposed to.

USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS FOOTBALL_REPORTING;

-- Reuses the existing dev warehouse rather than provisioning a new one.
-- A dedicated reporting warehouse would be the next step for genuine
-- compute cost isolation between transform and reporting workloads, but
-- that's a bigger change than role separation alone - not done here.
GRANT USAGE ON WAREHOUSE DEV_TRANSFORM_WH TO ROLE FOOTBALL_REPORTING;

GRANT USAGE ON DATABASE DEV_ANALYTICS TO ROLE FOOTBALL_REPORTING;
GRANT USAGE ON SCHEMA DEV_ANALYTICS.football_gold TO ROLE FOOTBALL_REPORTING;

-- Grants on what already exists in the gold schema...
GRANT SELECT ON ALL TABLES IN SCHEMA DEV_ANALYTICS.football_gold TO ROLE FOOTBALL_REPORTING;

-- ...and on anything added to it later (new dims/facts, the
-- dim_transfer_date seed), so this doesn't need re-running per model.
GRANT SELECT ON FUTURE TABLES IN SCHEMA DEV_ANALYTICS.football_gold TO ROLE FOOTBALL_REPORTING;

-- Assign the role to whichever user/service account will actually query
-- as a reporting consumer (e.g. a future BI tool's service user, or your
-- own user if you just want to test the role's access). Uncomment and
-- fill in before running:
-- GRANT ROLE FOOTBALL_REPORTING TO USER <your_reporting_or_bi_user>;
