-- Snowflake account-level setup: schema-level future grants on the two
-- gold schemas, for every role that would otherwise rely on a
-- database-level future grant there.
--
-- NOT run by dbt or CI - run manually via Snowsight/SnowSQL, same as the
-- other snowflake/*.sql scripts. Run it after setup_ci_prod_roles.sql,
-- setup_claude_readonly_role.sql, setup_reporting_role.sql and
-- ../mcp/mcp_setup.sql, and after both gold schemas exist (i.e. after the
-- first dev build and the first prod deploy). Idempotent - safe to re-run.
--
-- Why this exists - Snowflake's future-grant precedence rule:
--   When future grants exist for the same object type (TABLE, VIEW...)
--   at both the database level and the schema level, the schema-level
--   ones win and the database-level ones are IGNORED for objects created
--   in that schema. It is not additive.
--
--   setup_reporting_role.sql (FOOTBALL_REPORTING) and ../mcp/mcp_setup.sql
--   (CLAUDE_MCP_ROLE) each added a schema-level FUTURE TABLES grant on a
--   gold schema. From that point, the database-level FUTURE TABLES grants
--   that CI_ROLE and CLAUDE_READONLY_ROLE hold (setup_ci_prod_roles.sql,
--   setup_claude_readonly_role.sql) silently stopped applying to new gold
--   tables. dbt's table materialisation recreates every gold table on
--   every build, so each build stripped those roles' SELECT on gold.
--
-- The rule this file enforces: once ANY role has a schema-level future
-- grant on a gold schema, EVERY role that needs future access to that
-- schema must have one too, and it must live here. If you add a new
-- role with database-level future grants that should cover gold, add its
-- schema-level mirror below as well.
--
-- Roles deliberately NOT mirrored here:
--   - DEV_ROLE / PROD_ROLE: they create the gold tables, so they own them
--     and need no grant to read them.
--   - FOOTBALL_REPORTING / CLAUDE_MCP_ROLE: they already hold their own
--     schema-level grants in their own scripts (they're the reason this
--     file is needed).
--
-- Verify afterwards:
--   SHOW FUTURE GRANTS IN SCHEMA PRD_ANALYTICS.FOOTBALL_GOLD;
--   SHOW FUTURE GRANTS IN SCHEMA DEV_ANALYTICS.FOOTBALL_GOLD;
--   SHOW GRANTS ON TABLE PRD_ANALYTICS.FOOTBALL_GOLD.<any fct_ table>;

USE ROLE SECURITYADMIN;

-- =====================================================================
-- PRD_ANALYTICS.FOOTBALL_GOLD
-- Overridden by CLAUDE_MCP_ROLE's schema-level grants (../mcp/mcp_setup.sql).
-- =====================================================================

-- CI_ROLE: `--defer` resolves unbuilt refs against prod, so it must be
-- able to read any prod gold model a modified model depends on.
GRANT SELECT ON FUTURE TABLES IN SCHEMA PRD_ANALYTICS.FOOTBALL_GOLD TO ROLE CI_ROLE;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA PRD_ANALYTICS.FOOTBALL_GOLD TO ROLE CI_ROLE;

-- CLAUDE_READONLY_ROLE: read-only investigation of prod state.
GRANT SELECT ON FUTURE TABLES IN SCHEMA PRD_ANALYTICS.FOOTBALL_GOLD TO ROLE CLAUDE_READONLY_ROLE;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA PRD_ANALYTICS.FOOTBALL_GOLD TO ROLE CLAUDE_READONLY_ROLE;

-- One-off repair of tables built while the grants above were missing.
-- Future grants only apply to objects created after them, so without
-- this both roles stay locked out until the next prod build.
GRANT SELECT ON ALL TABLES IN SCHEMA PRD_ANALYTICS.FOOTBALL_GOLD TO ROLE CI_ROLE;
GRANT SELECT ON ALL VIEWS IN SCHEMA PRD_ANALYTICS.FOOTBALL_GOLD TO ROLE CI_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA PRD_ANALYTICS.FOOTBALL_GOLD TO ROLE CLAUDE_READONLY_ROLE;
GRANT SELECT ON ALL VIEWS IN SCHEMA PRD_ANALYTICS.FOOTBALL_GOLD TO ROLE CLAUDE_READONLY_ROLE;

-- =====================================================================
-- DEV_ANALYTICS.FOOTBALL_GOLD
-- Overridden by FOOTBALL_REPORTING's schema-level grant
-- (setup_reporting_role.sql).
-- =====================================================================

-- CLAUDE_READONLY_ROLE: read-only inspection of dev builds. CI_ROLE has
-- no dev access by design, so nothing to mirror for it here.
GRANT SELECT ON FUTURE TABLES IN SCHEMA DEV_ANALYTICS.FOOTBALL_GOLD TO ROLE CLAUDE_READONLY_ROLE;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA DEV_ANALYTICS.FOOTBALL_GOLD TO ROLE CLAUDE_READONLY_ROLE;

GRANT SELECT ON ALL TABLES IN SCHEMA DEV_ANALYTICS.FOOTBALL_GOLD TO ROLE CLAUDE_READONLY_ROLE;
GRANT SELECT ON ALL VIEWS IN SCHEMA DEV_ANALYTICS.FOOTBALL_GOLD TO ROLE CLAUDE_READONLY_ROLE;
