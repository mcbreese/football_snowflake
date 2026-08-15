WITH source
AS (
	select * from {{ source('football_raw', 'raw_clubs') }}
	),

clubs as (
    -- primary Key
    SELECT {{ dbt_utils.generate_surrogate_key(['club_id']) }} AS club_sk -- create surrogate key
        , club_id
    -- foreign Keys
        , domestic_competition_id
    --  dimensions
        , name
    -- facts
        , total_market_value
        , squad_size
        , average_age
        , foreigners_number
        , foreigners_percentage
        , national_team_players
        , stadium_name
        , stadium_seats
        , net_transfer_record
        , COALESCE(coach_name, 'Unknown') AS coach_name
        , last_season
    -- metadata
        , loaded_timestamp
        , source_file
        , url
    FROM source
)

SELECT *
FROM clubs