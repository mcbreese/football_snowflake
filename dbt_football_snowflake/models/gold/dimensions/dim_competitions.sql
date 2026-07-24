-- Refer to macro in macros folder
{{ materialization_config() }}

SELECT competition_sk
    , competition_id
    , name
    , type
    , sub_type
    , country_name
    , loaded_timestamp
FROM {{ ref('int_competitions') }} AS co
