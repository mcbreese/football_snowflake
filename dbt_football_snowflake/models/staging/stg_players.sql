with source as (

    select * from {{ source('football_raw', 'raw_players') }}

),

players as (

    select
        -- primary key
        -- create surrogate key
        {{ dbt_utils.generate_surrogate_key(['player_id']) }} as player_sk,
        player_id,
        -- foreign key
        current_club_id,
        -- dimensions
        name as player_name,
        country_of_citizenship as nationality,
        position,
        sub_position,
        COALESCE(foot, 'Unknown') as foot,
        height_in_cm,
        -- The date_of_birth is already a date type, but we cast it here for explicitness
        -- to ensure consistency in our data contract.
        CAST(date_of_birth as date) as date_of_birth,
        -- facts
        DATEDIFF(year, date_of_birth, CURRENT_DATE()) as age_in_years,
        last_season,
        -- metadata
        loaded_timestamp,
        source_file

    from source

)

select *
from players
