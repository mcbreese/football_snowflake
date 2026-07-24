{{ config(
    materialized='view'
) }}

SELECT *
FROM {{ ref('stg_players') }} AS pl