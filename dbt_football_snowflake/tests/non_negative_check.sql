-- This singular test checks the fct_player_performance_per_season_competition model
-- to ensure that key performance metrics (appearances, goals, assists) are never negative.

SELECT
    *
FROM
    {{ ref('fct_player_performance_per_season_competition') }}
WHERE
    total_appearances < 0 OR
    total_goals < 0 OR
    total_assists < 0