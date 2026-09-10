-- Rollback clone + before/after validation for cutting the RAW.FOOTBALL
-- load path over to load_raw_football_procedure.sql (S3 external stage).
--
-- NOT run by dbt or CI - run manually, same as the other snowflake/*.sql
-- scripts. Run PHASE 1, THEN run the procedure once
-- (CALL RAW.FOOTBALL.LOAD_RAW_FOOTBALL();), THEN run PHASE 2 to compare.
-- Don't drop RAW.FOOTBALL_ROLLBACK until you've checked PHASE 2's output
-- and are satisfied the new load matches.

USE ROLE SYSADMIN;
USE WAREHOUSE DEV_LOADING_WH;

CREATE SCHEMA IF NOT EXISTS RAW.FOOTBALL_ROLLBACK;

-- =====================================================================
-- PHASE 1: clone current state as a rollback point, before the first
-- real run of the new procedure. Zero-copy, no data re-upload, no
-- compute cost - same idiom already used in
-- ../migrations/migrate_raw_data_from_prd_analytics.sql.
-- =====================================================================
CREATE OR REPLACE TABLE RAW.FOOTBALL_ROLLBACK.RAW_APPEARANCES        CLONE RAW.FOOTBALL.RAW_APPEARANCES;
CREATE OR REPLACE TABLE RAW.FOOTBALL_ROLLBACK.RAW_CLUBS              CLONE RAW.FOOTBALL.RAW_CLUBS;
CREATE OR REPLACE TABLE RAW.FOOTBALL_ROLLBACK.RAW_CLUB_GAMES         CLONE RAW.FOOTBALL.RAW_CLUB_GAMES;
CREATE OR REPLACE TABLE RAW.FOOTBALL_ROLLBACK.RAW_COMPETITIONS       CLONE RAW.FOOTBALL.RAW_COMPETITIONS;
CREATE OR REPLACE TABLE RAW.FOOTBALL_ROLLBACK.RAW_GAMES              CLONE RAW.FOOTBALL.RAW_GAMES;
CREATE OR REPLACE TABLE RAW.FOOTBALL_ROLLBACK.RAW_GAME_EVENTS        CLONE RAW.FOOTBALL.RAW_GAME_EVENTS;
CREATE OR REPLACE TABLE RAW.FOOTBALL_ROLLBACK.RAW_GAME_LINEUPS       CLONE RAW.FOOTBALL.RAW_GAME_LINEUPS;
CREATE OR REPLACE TABLE RAW.FOOTBALL_ROLLBACK.RAW_PLAYERS            CLONE RAW.FOOTBALL.RAW_PLAYERS;
CREATE OR REPLACE TABLE RAW.FOOTBALL_ROLLBACK.RAW_PLAYER_VALUATIONS  CLONE RAW.FOOTBALL.RAW_PLAYER_VALUATIONS;
CREATE OR REPLACE TABLE RAW.FOOTBALL_ROLLBACK.RAW_TRANSFERS          CLONE RAW.FOOTBALL.RAW_TRANSFERS;

-- Leftover from the old worksheet's own ad-hoc test run (it ends with a
-- standalone COPY INTO RAW.FOOTBALL.RAW_TEST_TRANSFERS) - confirmed live
-- via SHOW TABLES, created 2026-08-26. Not part of the real dataset, so
-- it's dropped rather than cloned.
DROP TABLE IF EXISTS RAW.FOOTBALL.RAW_TEST_TRANSFERS;

-- =====================================================================
-- Now run the new procedure once, as RAW_INGESTION_ROLE (the procedure's
-- owner - SYSADMIN doesn't have EXECUTE on it):
--   USE ROLE RAW_INGESTION_ROLE;
--   USE WAREHOUSE DEV_LOADING_WH;
--   CALL RAW.FOOTBALL.LOAD_RAW_FOOTBALL();
-- Then switch back to SYSADMIN and continue to PHASE 2 below - it reads
-- RAW.FOOTBALL_ROLLBACK, which RAW_INGESTION_ROLE was never granted
-- access to.
--   USE ROLE SYSADMIN;
-- =====================================================================

-- =====================================================================
-- PHASE 2: compare the freshly-loaded tables against the PHASE 1 clone.
-- Row counts should match closely - this is a full-replace load against
-- the same snapshot data, not a delta, so an exact match is expected
-- unless the source CSVs in S3 genuinely changed since the clone.
-- =====================================================================
SELECT 'RAW_APPEARANCES' AS table_name,
       (SELECT COUNT(*) FROM RAW.FOOTBALL_ROLLBACK.RAW_APPEARANCES) AS rollback_count,
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_APPEARANCES) AS current_count
UNION ALL
SELECT 'RAW_CLUBS',
       (SELECT COUNT(*) FROM RAW.FOOTBALL_ROLLBACK.RAW_CLUBS),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_CLUBS)
UNION ALL
SELECT 'RAW_CLUB_GAMES',
       (SELECT COUNT(*) FROM RAW.FOOTBALL_ROLLBACK.RAW_CLUB_GAMES),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_CLUB_GAMES)
UNION ALL
SELECT 'RAW_COMPETITIONS',
       (SELECT COUNT(*) FROM RAW.FOOTBALL_ROLLBACK.RAW_COMPETITIONS),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_COMPETITIONS)
UNION ALL
SELECT 'RAW_GAMES',
       (SELECT COUNT(*) FROM RAW.FOOTBALL_ROLLBACK.RAW_GAMES),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_GAMES)
UNION ALL
SELECT 'RAW_GAME_EVENTS',
       (SELECT COUNT(*) FROM RAW.FOOTBALL_ROLLBACK.RAW_GAME_EVENTS),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_GAME_EVENTS)
UNION ALL
SELECT 'RAW_GAME_LINEUPS',
       (SELECT COUNT(*) FROM RAW.FOOTBALL_ROLLBACK.RAW_GAME_LINEUPS),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_GAME_LINEUPS)
UNION ALL
SELECT 'RAW_PLAYERS',
       (SELECT COUNT(*) FROM RAW.FOOTBALL_ROLLBACK.RAW_PLAYERS),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_PLAYERS)
UNION ALL
SELECT 'RAW_PLAYER_VALUATIONS',
       (SELECT COUNT(*) FROM RAW.FOOTBALL_ROLLBACK.RAW_PLAYER_VALUATIONS),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_PLAYER_VALUATIONS)
UNION ALL
SELECT 'RAW_TRANSFERS',
       (SELECT COUNT(*) FROM RAW.FOOTBALL_ROLLBACK.RAW_TRANSFERS),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_TRANSFERS);

-- Column-set diff - the row-count comparison above says nothing about
-- whether INFER_SCHEMA produced the same columns this run. A schema-
-- inferred table's shape is exactly what's most likely to silently
-- drift if a CSV's headers change between runs.
SELECT table_name,
       ARRAY_AGG(column_name) WITHIN GROUP (ORDER BY column_name) AS rollback_columns
FROM RAW.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'FOOTBALL_ROLLBACK'
GROUP BY table_name
ORDER BY table_name;

SELECT table_name,
       ARRAY_AGG(column_name) WITHIN GROUP (ORDER BY column_name) AS current_columns
FROM RAW.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'FOOTBALL'
  AND table_name LIKE 'RAW_%'
GROUP BY table_name
ORDER BY table_name;

-- =====================================================================
-- Once satisfied the comparison above looks right, drop the rollback
-- schema:
--   DROP SCHEMA RAW.FOOTBALL_ROLLBACK;
-- =====================================================================
