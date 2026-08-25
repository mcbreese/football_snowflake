select
        -- Primary Key (grain: player_id, club_id, season, competition_name)
    {{
        dbt_utils.generate_surrogate_key(
            ['pl.player_id', 'pl.club_id', 'pl.season', 'pl.competition_name']
        )
    }}
        as player_performance_sk,
    -- Dimensions to Group By
    pl.player_id,
    pl.club_id,
    pl.season,
    pl.competition_name,
    -- Aggregate Metrics (Facts)
    COUNT(pl.player_appearance_sk) as total_appearances,
    SUM(pl.yellow_cards) as total_yellow_cards,
    SUM(pl.red_cards) as total_red_cards,
    SUM(pl.goals) as total_goals,
    SUM(pl.assists) as total_assists,
    SUM(pl.minutes_played) as total_minutes_played,
    -- NEW: Efficiency Metrics
    -- Avg Minutes per Appearance
    ROUND(SUM(pl.minutes_played) * 1.0 / COUNT(pl.player_appearance_sk), 0)
        as avg_mins_per_appearance,
    -- Avg Goals per 90 Minutes (Total Goals / Total Minutes * 90)
    ROUND((SUM(pl.goals) * 90.0) / SUM(pl.minutes_played), 1)
        as avg_goals_per_90_mins,
    -- Calculate Win/Loss/Draw Totals
    SUM(case when pl.player_win_loss = 'player_win' then 1 else 0 end)
        as games_won,
    SUM(case when pl.player_win_loss = 'player_loss' then 1 else 0 end)
        as games_lost,
    SUM(case when pl.player_win_loss = 'draw' then 1 else 0 end) as games_drawn,
    -- Metadata (Keeping one instance for lineage)
    MIN(pl.appearance_loaded_timestamp) as first_appearance_loaded_timestamp
from {{ ref('int_player_appearances') }} as pl
-- Ignore dq issues for project if we don't know when appearances were from
where pl.season is not null
-- Group by all non-aggregated columns (positional: player_id, club_id,
-- season, competition_name - matches the project's implicit GROUP BY style)
group by 2, 3, 4, 5
-- Ensure we don't divide by zero for goals per 90 mins
having SUM(pl.minutes_played) > 0
