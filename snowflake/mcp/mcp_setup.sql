-- ============================================================
-- football_snowflake — MCP setup script
-- Connects Claude.ai (and later Claude Code) to the gold layer
-- via a dedicated, read-only, cost-capped service account.
--
-- Target: PRD_ANALYTICS.FOOTBALL_GOLD (modelled gold layer,
-- NOT the raw landing schema — this is deliberate, so Claude
-- queries clean facts/dimensions, not unprocessed CSV loads).
-- ============================================================

-- ========================================
-- STEP 1: Dedicated, tightly-capped warehouse
-- Isolated from your other warehouses so its cost and usage
-- can be tracked/killed independently. XSMALL + 60s auto-suspend
-- means it's never running (and never billing) when idle.
-- ========================================
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS MCP_QUERY_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Dedicated warehouse for Claude MCP querying — isolated for monitoring/cost control';

-- ========================================
-- STEP 2: Read-only role, least privilege
-- SELECT only, and only on the gold layer. This role can never
-- INSERT/UPDATE/DELETE/DROP anything, regardless of what any
-- MCP client asks it to do — the safety boundary lives here,
-- not just in the tool config in Step 3.
-- ========================================
USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS CLAUDE_MCP_ROLE
    COMMENT = 'Read-only role for Claude MCP access to football_snowflake gold layer';

GRANT USAGE ON WAREHOUSE MCP_QUERY_WH TO ROLE CLAUDE_MCP_ROLE;
GRANT USAGE ON DATABASE PRD_ANALYTICS TO ROLE CLAUDE_MCP_ROLE;
GRANT USAGE ON SCHEMA PRD_ANALYTICS.FOOTBALL_GOLD TO ROLE CLAUDE_MCP_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA PRD_ANALYTICS.FOOTBALL_GOLD TO ROLE CLAUDE_MCP_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA PRD_ANALYTICS.FOOTBALL_GOLD TO ROLE CLAUDE_MCP_ROLE;

-- ========================================
-- STEP 3: The MCP server object
--
-- This is a declarative YAML spec (like a dbt YAML config),
-- not imperative code — you're describing an object, not
-- writing logic. Snowflake creates and manages the object
-- itself once this runs.
--
--   tools:            a list — one server can expose up to 50
--                      tools, we're only defining one here
--   type:              SYSTEM_EXECUTE_SQL = "run arbitrary SQL",
--                      as opposed to e.g. CORTEX_ANALYST_MESSAGE
--                      (a Cortex semantic-view tool) or
--                      CORTEX_SEARCH_SERVICE_QUERY (a search tool)
--   config.read_only:  a hard constraint enforced by Snowflake
--                      itself at execution time — blocks DML
--                      even if the calling role somehow had
--                      write access. A second safety net on
--                      top of CLAUDE_MCP_ROLE's grants.
--   config.warehouse:  which warehouse actually executes the
--                      query when this tool is invoked — ties
--                      every MCP query to MCP_QUERY_WH, so cost
--                      is always capped and attributable
--   query_timeout:     seconds before Snowflake kills a runaway
--                      query started via this tool
-- ========================================
USE ROLE SYSADMIN;

CREATE OR REPLACE MCP SERVER PRD_ANALYTICS.FOOTBALL_GOLD.FOOTBALL_MCP_SERVER
  FROM SPECIFICATION $$
  tools:
    - title: "Football DW SQL Query"
      name: "sql_exec_tool"
      type: "SYSTEM_EXECUTE_SQL"
      description: "Executes read-only SQL queries against the football_snowflake gold layer."
      config:
        read_only: true
        query_timeout: 60
        warehouse: "MCP_QUERY_WH"
  $$;

-- ========================================
-- STEP 4: Dedicated service user for MCP
-- A separate Snowflake user, not your personal login. Keeps
-- your own DEFAULT_ROLE/DEFAULT_WAREHOUSE untouched — you log
-- into Snowsight day-to-day exactly as before. This user exists
-- solely so Claude (via OAuth) has its own identity to log in as.
-- ========================================
USE ROLE USERADMIN;

CREATE USER IF NOT EXISTS CLAUDE_MCP_USER
    PASSWORD = '<choose a strong password>'
    DEFAULT_ROLE = 'CLAUDE_MCP_ROLE'
    DEFAULT_WAREHOUSE = 'MCP_QUERY_WH'
    MUST_CHANGE_PASSWORD = FALSE
    COMMENT = 'Service account for Claude MCP connections — not a personal login';

USE ROLE SECURITYADMIN;
-- USAGE on the MCP server object itself is a SEPARATE grant from
-- table access (Step 2) — both are required, one without the
-- other leaves the connection either invisible or toothless.
GRANT USAGE ON MCP SERVER PRD_ANALYTICS.FOOTBALL_GOLD.FOOTBALL_MCP_SERVER TO ROLE CLAUDE_MCP_ROLE;
GRANT ROLE CLAUDE_MCP_ROLE TO USER CLAUDE_MCP_USER;

-- ========================================
-- STEP 5: OAuth security integration
--
-- Standard OAuth 2.0 "confidential client" handshake — the same
-- pattern any third-party app uses to let a user log in and hand
-- over a token instead of a password.
--
--   OAUTH_CLIENT = CUSTOM        you're registering your own
--                                client, not using a Snowflake-
--                                prebuilt one
--   OAUTH_CLIENT_TYPE            'CONFIDENTIAL' = this client can
--                                safely hold a secret (vs. a
--                                'PUBLIC' client, e.g. a mobile
--                                app, which can't)
--   OAUTH_REDIRECT_URI /
--   OAUTH_ALTERNATE_REDIRECT_URIS  the exact URL(s) Snowflake is
--                                allowed to send the browser back
--                                to post-login — a security
--                                control so tokens can't be
--                                redirected somewhere malicious.
--                                Primary covers Claude.ai; the
--                                alternate is reserved for Claude
--                                Code's local callback later.
--   ALLOWED_ROLES_LIST           restricts this OAuth client to
--                                only ever requesting
--                                CLAUDE_MCP_ROLE, even if the
--                                logging-in user has other roles
--   OAUTH_ALLOW_NON_TLS_REDIRECT_URI  Snowflake requires TLS on
--                                redirect URIs by default. The
--                                localhost alternate above is
--                                plain http, which is a standard,
--                                accepted OAuth exception for
--                                loopback CLI callbacks (traffic
--                                never leaves your machine) — but
--                                Snowflake requires this flag to
--                                explicitly allow it rather than
--                                silently accepting it.
-- ========================================
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE SECURITY INTEGRATION FOOTBALL_MCP_OAUTH
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  ENABLED = TRUE
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  OAUTH_REDIRECT_URI = 'https://claude.ai/api/mcp/auth_callback'
  OAUTH_ALTERNATE_REDIRECT_URIS = ('http://localhost:8080/callback')
  OAUTH_ALLOW_NON_TLS_REDIRECT_URI = TRUE
  OAUTH_USE_SECONDARY_ROLES = NONE
  ALLOWED_ROLES_LIST = ('CLAUDE_MCP_ROLE');

-- ========================================
-- STEP 6: Get the client ID/secret for Claude.ai
-- Treat this output like a password — needed for the Claude.ai
-- custom connector form, don't paste it anywhere public.
-- ========================================
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('FOOTBALL_MCP_OAUTH');

-- ============================================================
-- INSPECT AFTERWARDS (all visible in Snowsight UI too)
-- ============================================================
-- SHOW MCP SERVERS IN ACCOUNT;
-- DESCRIBE MCP SERVER PRD_ANALYTICS.FOOTBALL_GOLD.FOOTBALL_MCP_SERVER;
-- -- Snowsight: Data > Databases > PRD_ANALYTICS > FOOTBALL_GOLD (object list)
-- -- Snowsight: Admin > Security > Security Integrations (OAuth config)
-- -- Snowsight: Admin > Users & Roles (CLAUDE_MCP_USER / CLAUDE_MCP_ROLE)

-- ============================================================
-- TEARDOWN (run any of these when you're done with the exercise)
-- ============================================================
-- Force compute off immediately (otherwise auto-suspends after 60s anyway):
-- ALTER WAREHOUSE MCP_QUERY_WH SUSPEND;

-- Disable OAuth without deleting config:
-- ALTER SECURITY INTEGRATION FOOTBALL_MCP_OAUTH SET ENABLED = FALSE;

-- Full teardown:
-- DROP SECURITY INTEGRATION FOOTBALL_MCP_OAUTH;
-- DROP MCP SERVER PRD_ANALYTICS.FOOTBALL_GOLD.FOOTBALL_MCP_SERVER;
-- DROP USER CLAUDE_MCP_USER;
-- DROP ROLE CLAUDE_MCP_ROLE;
-- DROP WAREHOUSE MCP_QUERY_WH;