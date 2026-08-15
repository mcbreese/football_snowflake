SELECT player_sk
    , player_id
    , player_name
    , nationality
    , sub_position
    , foot
    , age_in_years
    , last_season
    , loaded_timestamp
FROM {{ ref('int_players') }} AS pl