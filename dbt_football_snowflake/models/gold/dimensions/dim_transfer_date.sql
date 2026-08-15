-- Set your date range here. Start must cover the earliest real transfer_date
-- in the source data (currently 1993-07-01) with margin for future loads.
WITH date_range AS (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('1990-01-01' as date)",
        end_date="cast('2030-12-31' as date)"
    ) }}
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