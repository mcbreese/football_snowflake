{{ config(
    materialized='incremental',
    unique_key='player_appearance_sk',
    incremental_strategy='merge',
    on_schema_change='append_new_columns'
) }}

with player_appearances as (
    select
        ap.appearance_player_sk,
        pl.player_name,
        pl.date_of_birth,
        ap.appearance_date,
        gm.season,
        -- facts
        ap.yellow_cards,
        ap.red_cards,
        ap.goals,
        ap.assists,
        ap.minutes_played,
        gm.home_club_goals,
        gm.away_club_goals,
        co.name as competition_name,
        co.type as competition_type,
        pl.player_id,
        pl.current_club_id as club_id,
        gm.game_id,
        ap.appearance_id,
        -- foreign keys
        gm.home_club_id,
        gm.away_club_id,
        ap.loaded_timestamp as appearance_loaded_timestamp,
        COALESCE(cl.name, 'Unknown') as club_name,
        DATEDIFF(year, pl.date_of_birth, ap.appearance_date)
            as appearance_age_in_years,
        case
            when ap.player_club_id = gm.home_club_id then 'home'
            else 'away'
        end as home_away,
        -- metdata
        case
            when gm.home_club_goals > gm.away_club_goals then 'home'
            when gm.home_club_goals < gm.away_club_goals then 'away'
            else 'draw'
        end as outcome
    -- Ref downstream models for best practice build in sequence
    from {{ ref('stg_players') }} as pl
    left join {{ ref('stg_appearances') }} as ap
        on pl.player_id = ap.player_id
    left join {{ ref('stg_clubs') }} as cl
        on ap.player_club_id = cl.club_id
    left join {{ ref('stg_competitions') }} as co
        on ap.competition_id = co.competition_id
    left join {{ ref('stg_games') }} as gm
        on ap.game_id = gm.game_id
    -- A player with no appearances still matches the LEFT JOIN above with every
    -- appearance-derived column NULL; this model is one row per appearance, so
    -- exclude those phantom rows rather than relying on a downstream filter.
    where
        ap.appearance_id is not null
        {% if is_incremental() %}
            and ap.loaded_timestamp
            > (
                select
                    MAX(prev.appearance_loaded_timestamp)
                        as latest_loaded_timestamp
                from {{ this }} as prev
            )
        {% endif %}
)

select
    -- primary key
    {{ dbt_utils.generate_surrogate_key(['player_id', 'appearance_id']) }}
        as player_appearance_sk,
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
    case
        when outcome = 'draw' then 'draw'
        when home_away = outcome then 'player_win'
        when home_away <> outcome then 'player_loss'
        else 'error'
    end as player_win_loss,
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
from player_appearances
