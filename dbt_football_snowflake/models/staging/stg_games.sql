with source as (

    select * from {{ source('football_raw', 'raw_games') }}

),

games as (

    select
        -- primary key
        -- game_id is the natural primary key for this table
        {{ dbt_utils.generate_surrogate_key(['game_id']) }} as game_sk,
        game_id,
        
        -- foreign keys
        competition_id,
        home_club_id,
        away_club_id,

        -- dimensions
        season,
        -- Cast the date to ensure it is in the correct format
        cast(date as date) as game_date,
        home_club_goals,
        away_club_goals,
        
        -- metadata
        loaded_timestamp,
        source_file

    from source gm
    -- Got a lot of missing clubs in my fct data - use an exists as skipping dq issue for personal project
    WHERE {{ exists_in_raw_clubs('gm.home_club_id') }}
    AND {{ exists_in_raw_clubs('gm.away_club_id') }}

)

select * from games