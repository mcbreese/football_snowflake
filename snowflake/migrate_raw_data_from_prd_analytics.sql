-- One-time recovery: move the raw CSV data that was mistakenly loaded
-- into PRD_ANALYTICS.FOOTBALL back to where it should have landed,
-- RAW.FOOTBALL.
--
-- Background: the manual CSV load process put this data into
-- PRD_ANALYTICS instead of DEV_RAW (now RAW) at some point before this
-- session - discovered while running setup_ci_prod_roles.sql, whose
-- `ALTER SCHEMA RAW.PUBLIC RENAME TO FOOTBALL` failed because the raw
-- data was never actually in RAW at all. All 10 tables (7 currently used
-- as dbt sources, plus raw_club_games/raw_game_events/raw_game_lineups
-- which aren't wired into stg_sources.yml yet but are part of the same
-- Transfermarkt dataset) are confirmed present in PRD_ANALYTICS.FOOTBALL.
--
-- Uses CREATE TABLE ... CLONE - zero-copy, no data re-upload, no compute
-- cost, preserves the loaded_timestamp/source_file lineage columns
-- exactly as they are.
--
-- NOT run by dbt or CI - run manually, same as the other snowflake/*.sql
-- scripts. Run this BEFORE the rest of setup_ci_prod_roles.sql if you
-- haven't finished it yet (RAW.FOOTBALL needs to exist first - either run
-- that script's section 3 up to `CREATE SCHEMA IF NOT EXISTS RAW.FOOTBALL`
-- first, or this script creates it defensively below too).
--
-- Run PHASE 1 first, verify row counts match, THEN run PHASE 2. Do not
-- run PHASE 2 until you've actually checked PHASE 1 worked - it drops the
-- only copy of this data outside of RAW.FOOTBALL.

USE ROLE SYSADMIN;

CREATE SCHEMA IF NOT EXISTS RAW.FOOTBALL;

-- =====================================================================
-- PHASE 1: clone into RAW.FOOTBALL (additive, non-destructive).
-- =====================================================================
CREATE TABLE RAW.FOOTBALL.RAW_APPEARANCES        CLONE PRD_ANALYTICS.FOOTBALL.RAW_APPEARANCES;
CREATE TABLE RAW.FOOTBALL.RAW_CLUBS              CLONE PRD_ANALYTICS.FOOTBALL.RAW_CLUBS;
CREATE TABLE RAW.FOOTBALL.RAW_CLUB_GAMES         CLONE PRD_ANALYTICS.FOOTBALL.RAW_CLUB_GAMES;
CREATE TABLE RAW.FOOTBALL.RAW_COMPETITIONS       CLONE PRD_ANALYTICS.FOOTBALL.RAW_COMPETITIONS;
CREATE TABLE RAW.FOOTBALL.RAW_GAMES              CLONE PRD_ANALYTICS.FOOTBALL.RAW_GAMES;
CREATE TABLE RAW.FOOTBALL.RAW_GAME_EVENTS        CLONE PRD_ANALYTICS.FOOTBALL.RAW_GAME_EVENTS;
CREATE TABLE RAW.FOOTBALL.RAW_GAME_LINEUPS       CLONE PRD_ANALYTICS.FOOTBALL.RAW_GAME_LINEUPS;
CREATE TABLE RAW.FOOTBALL.RAW_PLAYERS            CLONE PRD_ANALYTICS.FOOTBALL.RAW_PLAYERS;
CREATE TABLE RAW.FOOTBALL.RAW_PLAYER_VALUATIONS  CLONE PRD_ANALYTICS.FOOTBALL.RAW_PLAYER_VALUATIONS;
CREATE TABLE RAW.FOOTBALL.RAW_TRANSFERS          CLONE PRD_ANALYTICS.FOOTBALL.RAW_TRANSFERS;

-- --- Verify before proceeding to PHASE 2 --------------------------------
-- Row counts should match exactly between source and clone for every
-- table. Eyeball this output before running PHASE 2.
SELECT 'RAW_APPEARANCES' AS table_name,
       (SELECT COUNT(*) FROM PRD_ANALYTICS.FOOTBALL.RAW_APPEARANCES) AS prd_count,
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_APPEARANCES) AS raw_count
UNION ALL
SELECT 'RAW_CLUBS',
       (SELECT COUNT(*) FROM PRD_ANALYTICS.FOOTBALL.RAW_CLUBS),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_CLUBS)
UNION ALL
SELECT 'RAW_CLUB_GAMES',
       (SELECT COUNT(*) FROM PRD_ANALYTICS.FOOTBALL.RAW_CLUB_GAMES),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_CLUB_GAMES)
UNION ALL
SELECT 'RAW_COMPETITIONS',
       (SELECT COUNT(*) FROM PRD_ANALYTICS.FOOTBALL.RAW_COMPETITIONS),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_COMPETITIONS)
UNION ALL
SELECT 'RAW_GAMES',
       (SELECT COUNT(*) FROM PRD_ANALYTICS.FOOTBALL.RAW_GAMES),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_GAMES)
UNION ALL
SELECT 'RAW_GAME_EVENTS',
       (SELECT COUNT(*) FROM PRD_ANALYTICS.FOOTBALL.RAW_GAME_EVENTS),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_GAME_EVENTS)
UNION ALL
SELECT 'RAW_GAME_LINEUPS',
       (SELECT COUNT(*) FROM PRD_ANALYTICS.FOOTBALL.RAW_GAME_LINEUPS),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_GAME_LINEUPS)
UNION ALL
SELECT 'RAW_PLAYERS',
       (SELECT COUNT(*) FROM PRD_ANALYTICS.FOOTBALL.RAW_PLAYERS),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_PLAYERS)
UNION ALL
SELECT 'RAW_PLAYER_VALUATIONS',
       (SELECT COUNT(*) FROM PRD_ANALYTICS.FOOTBALL.RAW_PLAYER_VALUATIONS),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_PLAYER_VALUATIONS)
UNION ALL
SELECT 'RAW_TRANSFERS',
       (SELECT COUNT(*) FROM PRD_ANALYTICS.FOOTBALL.RAW_TRANSFERS),
       (SELECT COUNT(*) FROM RAW.FOOTBALL.RAW_TRANSFERS);

-- =====================================================================
-- PHASE 2: only after verifying the row counts above match exactly.
-- Drops the originals from PRD_ANALYTICS, then the now-empty schema -
-- PRD_ANALYTICS should only ever contain what `dbt build --target prod`
-- creates going forward, never manually-loaded data.
-- =====================================================================
-- DROP TABLE PRD_ANALYTICS.FOOTBALL.RAW_APPEARANCES;
-- DROP TABLE PRD_ANALYTICS.FOOTBALL.RAW_CLUBS;
-- DROP TABLE PRD_ANALYTICS.FOOTBALL.RAW_CLUB_GAMES;
-- DROP TABLE PRD_ANALYTICS.FOOTBALL.RAW_COMPETITIONS;
-- DROP TABLE PRD_ANALYTICS.FOOTBALL.RAW_GAMES;
-- DROP TABLE PRD_ANALYTICS.FOOTBALL.RAW_GAME_EVENTS;
-- DROP TABLE PRD_ANALYTICS.FOOTBALL.RAW_GAME_LINEUPS;
-- DROP TABLE PRD_ANALYTICS.FOOTBALL.RAW_PLAYERS;
-- DROP TABLE PRD_ANALYTICS.FOOTBALL.RAW_PLAYER_VALUATIONS;
-- DROP TABLE PRD_ANALYTICS.FOOTBALL.RAW_TRANSFERS;
-- DROP SCHEMA PRD_ANALYTICS.FOOTBALL;
