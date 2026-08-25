with source as (
    select * from {{ source('football_raw', 'raw_clubs') }}
),

clubs as (
    -- primary Key
    select
        -- create surrogate key
        -- create surrogate key
        {{ dbt_utils.generate_surrogate_key(['club_id']) }} as club_sk,
        club_id,
        -- foreign Keys
        domestic_competition_id,
        --  dimensions
        name,
        -- facts
        total_market_value,
        squad_size,
        average_age,
        foreigners_number,
        foreigners_percentage,
        national_team_players,
        stadium_name,
        stadium_seats,
        net_transfer_record,
        COALESCE(coach_name, 'Unknown') as coach_name,
        last_season,
        -- metadata
        loaded_timestamp,
        source_file,
        url
    from source
)

select *
from clubs
