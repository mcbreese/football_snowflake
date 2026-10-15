-- Service user for headless eval runs (evals/run_evals.py).
-- Run manually in Snowsight, after mcp_resource_monitor.sql.
-- Separate from CLAUDE_MCP_USER: a PAT needs a network policy, which would
-- block the Claude.ai connector (it connects from Anthropic's servers).

USE ROLE USERADMIN;

CREATE USER IF NOT EXISTS SVC_FOOTBALL_EVAL
    TYPE = SERVICE
    DEFAULT_ROLE = 'CLAUDE_MCP_ROLE'
    DEFAULT_WAREHOUSE = 'MCP_QUERY_WH'
    DEFAULT_NAMESPACE = 'PRD_ANALYTICS.FOOTBALL_GOLD'
    COMMENT = 'Owner: Tom Breese. Automated eval runs against the football MCP server. Token login from allow-listed IP only.';

USE ROLE SECURITYADMIN;
GRANT ROLE CLAUDE_MCP_ROLE TO USER SVC_FOOTBALL_EVAL;

-- Network rules are schema objects; ADMIN.SECURITY keeps them out of the
-- analytics databases.
USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS ADMIN COMMENT = 'Account administration objects, not data';
CREATE SCHEMA IF NOT EXISTS ADMIN.SECURITY;
GRANT USAGE ON DATABASE ADMIN TO ROLE SECURITYADMIN;
GRANT USAGE ON SCHEMA ADMIN.SECURITY TO ROLE SECURITYADMIN;
GRANT CREATE NETWORK RULE ON SCHEMA ADMIN.SECURITY TO ROLE SECURITYADMIN;

USE ROLE SECURITYADMIN;

-- Your IPv4 from https://api.ipify.org. Update if your ISP changes it.
CREATE NETWORK RULE IF NOT EXISTS ADMIN.SECURITY.SVC_FOOTBALL_EVAL_INGRESS
    MODE = INGRESS
    TYPE = IPV4
    VALUE_LIST = ('<your.ip.address>/32')
    COMMENT = 'Allowed source IP for SVC_FOOTBALL_EVAL';

CREATE NETWORK POLICY IF NOT EXISTS SVC_FOOTBALL_EVAL_POLICY
    ALLOWED_NETWORK_RULE_LIST = ('ADMIN.SECURITY.SVC_FOOTBALL_EVAL_INGRESS')
    COMMENT = 'User-level policy for SVC_FOOTBALL_EVAL only';

ALTER USER SVC_FOOTBALL_EVAL SET NETWORK_POLICY = 'SVC_FOOTBALL_EVAL_POLICY';

-- Token is shown once: copy it straight into secrets/.env.eval as SNOWFLAKE_MCP_PAT.
ALTER USER SVC_FOOTBALL_EVAL ADD PROGRAMMATIC ACCESS TOKEN eval_runner
    ROLE_RESTRICTION = 'CLAUDE_MCP_ROLE'
    DAYS_TO_EXPIRY = 30
    COMMENT = 'Eval runner token';

-- Check:
-- DESC USER SVC_FOOTBALL_EVAL;
-- SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER SVC_FOOTBALL_EVAL;

-- Rotate: ADD a new token, update .env.eval, then:
-- ALTER USER SVC_FOOTBALL_EVAL REMOVE PROGRAMMATIC ACCESS TOKEN eval_runner;
