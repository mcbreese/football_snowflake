-- Monthly credit cap on MCP_QUERY_WH (Claude.ai connector and eval runs).
-- Run manually in Snowsight as ACCOUNTADMIN.
-- Covers warehouse compute only, not serverless features (e.g. Cortex) or storage.

USE ROLE ACCOUNTADMIN;

-- Check first: on 15 Oct 2026 no monitor was attached to this warehouse.
-- SHOW RESOURCE MONITORS;
-- SHOW WAREHOUSES LIKE 'MCP_QUERY_WH';

CREATE RESOURCE MONITOR IF NOT EXISTS MCP_QUERY_WH_MONITOR
    WITH CREDIT_QUOTA = 5
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 50 PERCENT DO NOTIFY
        ON 80 PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND
        ON 110 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE MCP_QUERY_WH SET RESOURCE_MONITOR = MCP_QUERY_WH_MONITOR;

-- If it trips, see who used the credits before raising the quota:
-- select user_name, sum(total_elapsed_time) / 1000 as seconds
-- from snowflake.account_usage.query_history
-- where warehouse_name = 'MCP_QUERY_WH' and start_time >= date_trunc('month', current_date)
-- group by 1 order by 2 desc;
