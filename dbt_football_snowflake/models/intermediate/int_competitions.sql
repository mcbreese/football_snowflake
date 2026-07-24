{{ config(
    materialized='view'
) }}

SELECT *
FROM {{ ref('stg_competitions') }} AS co