{{ config(
    materialized='incremental',
    unique_key='player_appearance_sk',
    incremental_strategy='merge',
    on_schema_change='append_new_columns'
) }}

WITH player_appearances AS (
    SELECT ap.appearance_player_sk,
        pl.player_name,
        COALESCE(cl.name, 'Unknown')  AS club_name,
        pl.date_of_birth,
        ap.appearance_date,
        -- facts
        DATEDIFF(YEAR, pl.date_of_birth, ap.appearance_date) AS appearance_age_in_years,
        gm.season,
        ap.yellow_cards,
        ap.red_cards,
        ap.goals,
        ap.assists,
        ap.minutes_played,
        gm.home_club_goals,
        gm.away_club_goals,
        CASE
            WHEN ap.player_club_id = gm.home_club_id THEN 'home'
            ELSE 'away'
        END AS home_away,
        CASE
            WHEN gm.home_club_goals > gm.away_club_goals THEN 'home'
            WHEN gm.home_club_goals < gm.away_club_goals THEN 'away'
            ELSE 'draw'
        END AS outcome,
        co.name AS competition_name,
        co.type AS competition_type,
        -- foreign keys
        pl.player_id,
        pl.current_club_id AS club_id,
        gm.game_id,
        ap.appearance_id,
        gm.home_club_id,
        gm.away_club_id,
        -- metdata
        ap.loaded_timestamp AS appearance_loaded_timestamp
	-- Ref downstream models for best practice build in sequence
    FROM {{ ref('stg_players') }} AS pl
    LEFT JOIN {{ ref('stg_appearances') }} AS ap
        ON pl.player_id = ap.player_id
    LEFT JOIN {{ ref('stg_clubs') }} AS cl
        ON ap.player_club_id = cl.club_id
    LEFT JOIN {{ ref('stg_competitions') }} AS co
        ON ap.competition_id = co.competition_id
    LEFT JOIN {{ ref('stg_games') }} AS gm
        ON ap.game_id = gm.game_id
    -- A player with no appearances still matches the LEFT JOIN above with every
    -- appearance-derived column NULL; this model is one row per appearance, so
    -- exclude those phantom rows rather than relying on a downstream filter.
    WHERE ap.appearance_id IS NOT NULL
    {% if is_incremental() %}
    AND ap.loaded_timestamp > (SELECT MAX(appearance_loaded_timestamp) FROM {{ this }})
    {% endif %}
)

SELECT
    -- primary key
    {{ dbt_utils.generate_surrogate_key(['player_id', 'appearance_id']) }} AS player_appearance_sk,
    player_name,
    club_name,
    date_of_birth,
    appearance_date,
    appearance_age_in_years,
    season,
    yellow_cards,
    red_cards,
    goals,
    assists,
    minutes_played,
    home_club_goals,
    away_club_goals,
    home_away,
    outcome,
    CASE
        WHEN outcome = 'draw' THEN 'draw'
        WHEN home_away = outcome THEN 'player_win'
        WHEN home_away <> outcome THEN 'player_loss'
        ELSE 'error'
    END AS player_win_loss,
    competition_name,
    competition_type,
    player_id,
    club_id,
    game_id,
    appearance_id,
    home_club_id,
    away_club_id,
    -- metdata
    appearance_loaded_timestamp
FROM player_appearances