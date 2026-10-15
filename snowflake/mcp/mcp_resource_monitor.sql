-- ============================================================
-- football_snowflake: hard credit cap on MCP_QUERY_WH
-- (the warehouse used by the Claude.ai connector and the eval runner).
--
-- NOT run by dbt or CI. Run manually in Snowsight as ACCOUNTADMIN:
-- only ACCOUNTADMIN can create resource monitors.
--
-- Why this file exists: on 15 Oct 2026 the agent's role saw no
-- resource monitor attached to MCP_QUERY_WH (SHOW WAREHOUSES ->
-- resource_monitor = null), although the Notion checklist had "resource
-- monitor with a hard credit cap" ticked. Either it was set at account
-- level, or never attached here. Run STEP 0 first to find out. Either way,
-- this file is now the versioned record of the cap.
--
-- What a resource monitor does and doesn't cover:
--   - Covers: warehouse compute credits on the warehouses it's assigned to.
--   - Doesn't cover: serverless features (Cortex AI functions, Snowpipe,
--     automatic clustering, etc.), cloud services charges beyond the daily
--     adjustment, or storage. Those need a Snowflake Budget if they're ever
--     used. Not needed today: the MCP server runs SQL on this warehouse.
--   - It isn't real-time: credit usage is checked periodically, so a burst
--     can overshoot the quota slightly before suspension takes effect.
--
-- Sizing: MCP_QUERY_WH is X-Small (1 credit per hour of running time,
-- billed per second with a 60-second minimum per resume) with 60-second
-- auto-suspend. A full eval baseline (33 trials) runs a few minutes of
-- compute. 5 credits a month is generous headroom for chat plus evals, and
-- small enough that a runaway loop costs little. Adjust CREDIT_QUOTA to
-- taste.
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- ========================================
-- STEP 0: What exists today? (read-only, run first)
-- ========================================
-- SHOW RESOURCE MONITORS;                        -- any account-level monitor?
-- SHOW WAREHOUSES LIKE 'MCP_QUERY_WH';           -- resource_monitor column
-- If an account-level monitor exists, it caps the whole account, not this
-- warehouse specifically. Keep it as a backstop; this warehouse-level one
-- is the cap that matters for agent and eval spend.

-- ========================================
-- STEP 1: The monitor
--   FREQUENCY = MONTHLY       quota resets at the start of each month
--   NOTIFY at 50% / 80%       email warning (to account admins with a
--                             verified email address)
--   SUSPEND at 100%           lets running queries finish, then suspends
--   SUSPEND_IMMEDIATE at 110% kills running queries too: the hard stop
-- ========================================
CREATE RESOURCE MONITOR IF NOT EXISTS MCP_QUERY_WH_MONITOR
    WITH CREDIT_QUOTA = 5
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 50 PERCENT DO NOTIFY
        ON 80 PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND
        ON 110 PERCENT DO SUSPEND_IMMEDIATE;

-- ========================================
-- STEP 2: Attach it to the warehouse
-- A warehouse can have only one monitor; this replaces any existing one.
-- ========================================
ALTER WAREHOUSE MCP_QUERY_WH SET RESOURCE_MONITOR = MCP_QUERY_WH_MONITOR;

-- ============================================================
-- CHECK AFTERWARDS
-- ============================================================
-- SHOW RESOURCE MONITORS LIKE 'MCP_QUERY_WH_MONITOR';  -- quota, used, remaining
-- SHOW WAREHOUSES LIKE 'MCP_QUERY_WH';                 -- resource_monitor = MCP_QUERY_WH_MONITOR

-- ============================================================
-- IF IT TRIPS
-- ============================================================
-- The warehouse suspends and stays suspended until the next monthly reset,
-- the quota is raised, or the monitor is removed. Agent and eval queries
-- fail with a warehouse-suspended error, which is the point. Before raising
-- the quota, check what used the credits:
-- select user_name, count(*) as queries, sum(total_elapsed_time) / 1000 as seconds
-- from snowflake.account_usage.query_history
-- where warehouse_name = 'MCP_QUERY_WH'
--   and start_time >= date_trunc('month', current_date)
-- group by user_name
-- order by seconds desc;
-- ALTER RESOURCE MONITOR MCP_QUERY_WH_MONITOR SET CREDIT_QUOTA = 10;

-- ============================================================
-- TEARDOWN
-- ============================================================
-- ALTER WAREHOUSE MCP_QUERY_WH UNSET RESOURCE_MONITOR;
-- DROP RESOURCE MONITOR MCP_QUERY_WH_MONITOR;
