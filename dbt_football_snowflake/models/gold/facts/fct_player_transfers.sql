select

    -- Primary Key
    tr.player_transfer_sk,

    -- Foreign Keys (To join to future dimension tables)
    tr.player_id,
    tr.from_club_id,
    tr.to_club_id,
    CAST(TO_CHAR(tr.transfer_date, 'yyyyMMdd') as INT) as transfer_date_key,

    -- Facts / Measures
    tr.transfer_fee,
    tr.market_value_in_eur,

    -- Date/Time Components
    tr.transfer_date,
    tr.transfer_season,

    -- Metadata
    tr.transfer_loaded_timestamp

from {{ ref('int_player_transfers') }} as tr
