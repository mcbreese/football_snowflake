SELECT
    co.competition_sk,
    co.competition_id,
    co.country_id,
    co.domestic_league_code,
    co.name,
    co.type,
    co.sub_type,
    co.country_name,
    co.confederation,
    co.is_major_national_league,
    co.loaded_timestamp,
    co.source_file,
    co.url
FROM {{ ref('stg_competitions') }} AS co