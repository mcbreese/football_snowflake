-- Refer to macro in macros folder
{{ materialization_config() }}


SELECT club_sk
    , club_id
    , name
    , loaded_timestamp
FROM {{ ref('int_clubs') }} AS cl
