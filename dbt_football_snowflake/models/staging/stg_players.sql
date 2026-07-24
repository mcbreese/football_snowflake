with source as (

    select * from {{ source('football_raw', 'raw_players') }}

),

players as (

    select
        -- primary key
        {{ dbt_utils.generate_surrogate_key(['player_id']) }} as player_sk, -- create surrogate key
        player_id,
        -- foreign key
        current_club_id,
        -- dimensions
        name AS player_name,
        country_of_citizenship AS nationality,
        position,
        sub_position,
        COALESCE(foot, 'Unknown') AS foot,
        height_in_cm,
        -- The date_of_birth is already a date type, but we cast it here for explicitness
        -- to ensure consistency in our data contract.
        cast(date_of_birth as date) as date_of_birth,
        -- facts
        FLOOR(DATEDIFF(current_date(), date_of_birth) / 365.25) AS age_in_years,
        last_season,
        -- metadata
        loaded_timestamp,
        source_file

    from source

)

select * 
from players