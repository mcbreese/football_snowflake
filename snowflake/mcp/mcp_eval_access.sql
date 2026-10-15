-- ============================================================
-- football_snowflake: service user for scripted eval runs
-- (evals/run_evals.py, headless Claude Code -> Snowflake MCP server).
--
-- NOT run by dbt or CI. Run manually in Snowsight, top to bottom, same as
-- the other snowflake/*.sql scripts.
--
-- Why a separate user and not a token on CLAUDE_MCP_USER: one service user
-- per workload. The Claude.ai connector (CLAUDE_MCP_USER) logs in from
-- Anthropic's servers via browser OAuth; this script logs in from my laptop
-- with a programmatic access token (PAT). Snowflake requires a network
-- policy before a PAT works, and a network policy applies to the whole user,
-- so locking one user to my IP would break the connector. Both users share
-- CLAUDE_MCP_ROLE: same permissions, different identity.
--
-- Naming: SVC_<WORKLOAD>. Older users in this project (CLAUDE_SERVICE,
-- CLAUDE_MCP_USER) predate the convention and are left as they are.
--
-- Cost control: queries run on MCP_QUERY_WH, so the warehouse's existing
-- resource monitor (hard credit cap) covers eval runs too.
--
-- Verify against current Snowflake docs before running: PAT syntax
-- (ADD PROGRAMMATIC ACCESS TOKEN) and the network policy requirement are
-- recent features and could not be checked from the session that wrote
-- this file.
-- ============================================================

-- ========================================
-- STEP 1: The service user
-- TYPE = SERVICE: password and interactive logins are impossible; only
-- key-pair, PAT or OAuth work. No password is ever set.
-- ========================================
USE ROLE USERADMIN;

CREATE USER IF NOT EXISTS SVC_FOOTBALL_EVAL
    TYPE = SERVICE
    DEFAULT_ROLE = 'CLAUDE_MCP_ROLE'
    DEFAULT_WAREHOUSE = 'MCP_QUERY_WH'
    DEFAULT_NAMESPACE = 'PRD_ANALYTICS.FOOTBALL_GOLD'
    COMMENT = 'Owner: Tom Breese. Workload: scripted eval runs (evals/run_evals.py) via the Snowflake MCP server. PAT login from an allow-listed IP only.';

USE ROLE SECURITYADMIN;
-- The same role as the Claude.ai connector: SELECT on the gold layer, usage
-- on MCP_QUERY_WH and on FOOTBALL_MCP_SERVER (see mcp_setup.sql). Nothing
-- new is granted to the role itself.
GRANT ROLE CLAUDE_MCP_ROLE TO USER SVC_FOOTBALL_EVAL;

-- ========================================
-- STEP 2: Network policy (required before the PAT will work)
-- Network rules are schema objects, so they need a home. ADMIN.SECURITY
-- keeps account-level security objects out of the analytics databases.
-- Find your current public IP at e.g. https://ifconfig.me and put it below.
-- If your ISP changes it, update VALUE_LIST; runs fail with an auth error
-- until you do.
-- ========================================
USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS ADMIN
    COMMENT = 'Account administration objects (network rules etc.), not data';
CREATE SCHEMA IF NOT EXISTS ADMIN.SECURITY;
GRANT USAGE ON DATABASE ADMIN TO ROLE SECURITYADMIN;
GRANT USAGE ON SCHEMA ADMIN.SECURITY TO ROLE SECURITYADMIN;
GRANT CREATE NETWORK RULE ON SCHEMA ADMIN.SECURITY TO ROLE SECURITYADMIN;

USE ROLE SECURITYADMIN;

CREATE NETWORK RULE IF NOT EXISTS ADMIN.SECURITY.SVC_FOOTBALL_EVAL_INGRESS
    MODE = INGRESS
    TYPE = IPV4
    VALUE_LIST = ('<your.public.ip.address>/32')
    COMMENT = 'Tom''s home IP, for SVC_FOOTBALL_EVAL PAT logins';

CREATE NETWORK POLICY IF NOT EXISTS SVC_FOOTBALL_EVAL_POLICY
    ALLOWED_NETWORK_RULE_LIST = ('ADMIN.SECURITY.SVC_FOOTBALL_EVAL_INGRESS')
    COMMENT = 'Applied to SVC_FOOTBALL_EVAL only. Never apply at account level.';

ALTER USER SVC_FOOTBALL_EVAL SET NETWORK_POLICY = 'SVC_FOOTBALL_EVAL_POLICY';

-- ========================================
-- STEP 3: The token
-- ROLE_RESTRICTION: the token can only ever act as CLAUDE_MCP_ROLE, even if
-- the user is later granted something broader.
-- DAYS_TO_EXPIRY = 30: short-lived; rotate by adding a new token and
-- removing the old one (see ROTATE below).
--
-- The token is shown ONCE in the output. Copy it straight into
-- secrets/.env.eval as SNOWFLAKE_MCP_PAT (gitignored). Don't paste it into
-- chat, Notion or anywhere else.
-- ========================================
ALTER USER SVC_FOOTBALL_EVAL ADD PROGRAMMATIC ACCESS TOKEN eval_runner
    ROLE_RESTRICTION = 'CLAUDE_MCP_ROLE'
    DAYS_TO_EXPIRY = 30
    COMMENT = 'evals/run_evals.py';

-- ============================================================
-- CHECK AFTERWARDS
-- ============================================================
-- DESC USER SVC_FOOTBALL_EVAL;          -- TYPE = SERVICE, HAS_PAT = true, no password
-- SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER SVC_FOOTBALL_EVAL;   -- expiry date
-- SHOW GRANTS TO USER SVC_FOOTBALL_EVAL;                              -- CLAUDE_MCP_ROLE only
-- Then the pilot run: see evals/README.md.

-- ============================================================
-- ROTATE (before the 30 days are up)
-- ============================================================
-- ALTER USER SVC_FOOTBALL_EVAL ADD PROGRAMMATIC ACCESS TOKEN eval_runner_2
--     ROLE_RESTRICTION = 'CLAUDE_MCP_ROLE' DAYS_TO_EXPIRY = 30;
-- -- update secrets/.env.eval, check a pilot run works, then:
-- ALTER USER SVC_FOOTBALL_EVAL REMOVE PROGRAMMATIC ACCESS TOKEN eval_runner;

-- ============================================================
-- TEARDOWN
-- ============================================================
-- ALTER USER SVC_FOOTBALL_EVAL REMOVE PROGRAMMATIC ACCESS TOKEN eval_runner;
-- DROP USER SVC_FOOTBALL_EVAL;
-- DROP NETWORK POLICY SVC_FOOTBALL_EVAL_POLICY;
-- DROP NETWORK RULE ADMIN.SECURITY.SVC_FOOTBALL_EVAL_INGRESS;
