with source as (
    select * from {{ source('football_raw', 'raw_appearances') }}
),

players as (

    select *
    from {{ source('football_raw', 'raw_players') }}

),


appearances as (
    select
            -- primary key
            -- we are using a combination of columns to make a unique key, this
            -- is a great way to handle source tables without a natural primary
            -- key
        {{
            dbt_utils.generate_surrogate_key(
                ['appearance_id', 'game_id', 'player_id']
            )
        }}
            as appearance_player_sk,
        -- foreign keys
        ap.appearance_id,
        ap.game_id,
        ap.player_id,
        COALESCE(player_club_id, 0) as player_club_id,
        ap.competition_id,
        -- dimensions
        ap.player_name,
        ap.date as appearance_date,
        -- facts
        ap.yellow_cards,
        ap.red_cards,
        ap.goals,
        ap.assists,
        ap.minutes_played,
        -- metadata
        ap.loaded_timestamp,
        ap.source_file
    from source as ap
    -- Got a lot of missing clubs in my fct data - use an exists as skipping
    -- dq issue for personal project
    where
        {{ exists_in_raw_clubs('COALESCE(ap.player_club_id,0)') }}
        and ap.player_id in (select pl.player_id from players as pl)
)

select *
from appearances
