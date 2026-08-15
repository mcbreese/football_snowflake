-- Refer to macro in macros folder
{{ materialization_config() }}

SELECT
    -- Primary Key (grain: player_id, club_id, season, competition_name)
    {{ dbt_utils.generate_surrogate_key(['pl.player_id', 'pl.club_id', 'pl.season', 'pl.competition_name']) }} AS player_performance_sk,
    -- Dimensions to Group By
    pl.player_id,
    pl.club_id,
    pl.season,
    pl.competition_name,
    -- Aggregate Metrics (Facts)
    COUNT(pl.player_appearance_sk) AS total_appearances,
    SUM(pl.yellow_cards) AS total_yellow_cards,
    SUM(pl.red_cards) AS total_red_cards,
    SUM(pl.goals) AS total_goals,
    SUM(pl.assists) AS total_assists,
    SUM(pl.minutes_played) AS total_minutes_played,
    -- NEW: Efficiency Metrics
    -- Avg Minutes per Appearance
    ROUND(SUM(pl.minutes_played) * 1.0 / COUNT(pl.player_appearance_sk),0) AS avg_mins_per_appearance,
    -- Avg Goals per 90 Minutes (Total Goals / Total Minutes * 90)
    ROUND((SUM(pl.goals) * 90.0) / SUM(pl.minutes_played),1) AS avg_goals_per_90_mins,
    -- Calculate Win/Loss/Draw Totals
    SUM(CASE WHEN pl.player_win_loss = 'player_win' THEN 1 ELSE 0 END) AS games_won,
    SUM(CASE WHEN pl.player_win_loss = 'player_loss' THEN 1 ELSE 0 END) AS games_lost,
    SUM(CASE WHEN pl.player_win_loss = 'draw' THEN 1 ELSE 0 END) AS games_drawn,
    -- Metadata (Keeping one instance for lineage)
    MIN(pl.appearance_loaded_timestamp) AS first_appearance_loaded_timestamp
FROM {{ ref('int_player_appearances') }} AS pl
WHERE pl.season IS NOT NULL -- Ignore dq issues for project if we don't know when appearances were from
-- Group by all non-aggregated columns
GROUP BY pl.player_id
    , pl.club_id
    , pl.season
    , pl.competition_name
-- Ensure we don't divide by zero for goals per 90 mins
HAVING SUM(pl.minutes_played) > 0