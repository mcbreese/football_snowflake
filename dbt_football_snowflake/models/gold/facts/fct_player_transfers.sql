-- Refer to macro in macros folder
{{ materialization_config() }}

SELECT

    -- Foreign Keys (To join to future dimension tables)
    tr.player_id,
    tr.from_club_id,
    tr.to_club_id,

    -- Facts / Measures
    tr.transfer_fee,
    tr.market_value_in_eur,
    
    -- Date/Time Components
    tr.transfer_date,
    tr.transfer_season,

    -- Metadata
    tr.transfer_loaded_timestamp

FROM {{ ref('int_player_transfers') }} AS tr