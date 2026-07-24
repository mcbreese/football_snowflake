WITH source
AS (
	select * from {{ source('football_raw', 'raw_competitions') }}
	),

clubs as (
    -- primary Key
    SELECT 
        {{ dbt_utils.generate_surrogate_key(['competition_id']) }} as competition_sk
    -- foreign Keys
        , competition_id
        , country_id
        , domestic_league_code
    --  dimensions
        , name
        , type
        , sub_type
        , country_name
        , confederation
        , is_major_national_league
    -- facts

    -- metadata
        , loaded_timestamp
        , source_file
        , url
    FROM source
)

SELECT *
FROM clubs