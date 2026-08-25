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
        -- we are using a combination of columns to make a unique key, this is a great way to handle source tables without a natural primary key
        {{ dbt_utils.generate_surrogate_key(['appearance_id', 'game_id', 'player_id']) }}
            as appearance_player_sk,
        -- foreign keys
        appearance_id,
        game_id,
        player_id,
        COALESCE(player_club_id, 0) as player_club_id,
        competition_id
        ,
        -- dimensions
        player_name,
        date as appearance_date,
        -- facts
        yellow_cards,
        red_cards,
        goals,
        assists,
        minutes_played,
        -- metadata
        loaded_timestamp,
        source_file
    from source as ap
    -- Got a lot of missing clubs in my fct data - use an exists as skipping dq issue for personal project
    where                         {{ exists_in_raw_clubs('COALESCE(ap.player_club_id,0)') }}
        and exists (
            select * from players as pl
            where ap.player_id = pl.player_id
        )
)

select *
from appearances
