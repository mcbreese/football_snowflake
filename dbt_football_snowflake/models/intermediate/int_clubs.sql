{{ config(
    materialized='view'
) }}

SELECT *
FROM {{ ref('stg_clubs') }} AS cl