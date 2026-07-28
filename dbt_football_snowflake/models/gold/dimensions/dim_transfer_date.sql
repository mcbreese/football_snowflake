-- Refer to macro in macros folder
{{ materialization_config() }}
-- Set your date range here (e.g., from Jan 1, 2000, to Dec 31, 2030)
WITH date_range AS (
    SELECT DATEADD('day', SEQ4(), DATE '2000-01-01') AS DATE_DAY
    FROM TABLE(GENERATOR(ROWCOUNT => 11323)) -- 11,323 days between 2000-01-01 and 2030-12-31
    WHERE DATEADD('day', SEQ4(), DATE '2000-01-01') <= DATE '2030-12-31'
),

date_attributes AS (
    SELECT
        -- Primary Key: Date Key (YYYYMMDD)
        CAST(TO_CHAR(date_day, 'yyyyMMdd') AS INT) AS date_key,
        date_day,
        -- Calculated Attribute: Transfer Season (e.g., 2023/2024)
        CASE
            -- If the month is January through May (start of the year part of the season)
            WHEN MONTH(date_day) BETWEEN 1 AND 5 THEN
                CONCAT(CAST(YEAR(date_day) - 1 AS STRING), '/', CAST(YEAR(date_day) AS STRING))
            -- If the month is June through December (end of the year part of the season)
            ELSE
                CONCAT(CAST(YEAR(date_day) AS STRING), '/', CAST(YEAR(date_day) + 1 AS STRING))
        END AS transfer_season
    FROM date_range
)

SELECT * FROM date_attributes