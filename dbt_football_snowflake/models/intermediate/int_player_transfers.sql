{{ config(
    materialized='view'
) }}

WITH transfers AS (

    SELECT
        -- Transfer Keys and Facts
        tr.player_transfer_sk,
        tr.transfer_date,
        tr.transfer_season,
        tr.transfer_fee,
        tr.market_value_in_eur,

        -- Foreign Keys to Players and Clubs
        tr.player_id,
        tr.from_club_id,
        tr.to_club_id,

        -- Metadata
        tr.loaded_timestamp AS transfer_loaded_timestamp,
        tr.source_file AS transfer_source_file

    FROM {{ ref('stg_transfers') }} AS tr
),

joined AS (

    SELECT
        -- Primary Key
        tr.player_transfer_sk,
        -- Club Names
        from_club.name AS from_club_name,
        to_club.name AS to_club_name,

        -- Transfer Details (Facts)
        tr.transfer_date,
        tr.transfer_season,
        tr.transfer_fee,
        tr.market_value_in_eur,

        -- Player Details (Dimensions)
        pl.player_name,
        pl.nationality,
        pl.position,
        pl.sub_position,
        pl.foot,
        pl.height_in_cm,
        pl.date_of_birth,
        pl.age_in_years,
        pl.last_season,

        -- Foreign Keys
        tr.player_id,
        tr.from_club_id,
        tr.to_club_id,

        -- Metadata (Keeping only the transfer metadata)
        tr.transfer_loaded_timestamp,
        tr.transfer_source_file

    FROM transfers AS tr
    
    -- Join to Player Details
    LEFT JOIN {{ ref('stg_players') }} AS pl
        ON tr.player_id = pl.player_id
        
    -- Join to Club for 'From Club' Name
    LEFT JOIN {{ ref('stg_clubs') }} AS from_club
        ON tr.from_club_id = from_club.club_id
        
    -- Join to Club for 'To Club' Name
    LEFT JOIN {{ ref('stg_clubs') }} AS to_club
        ON tr.to_club_id = to_club.club_id
)

SELECT * 
FROM joined