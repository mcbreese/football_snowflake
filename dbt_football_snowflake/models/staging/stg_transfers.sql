with source as (

    select * from {{ source('football_raw', 'raw_transfers') }}

),

players as (

    select
            -- primary key
            -- create surrogate key
        {{
            dbt_utils.generate_surrogate_key(
                ['player_id', 'transfer_date', 'to_club_id']
            )
        }}
            as player_transfer_sk,
        player_id,
        -- foreign key
        from_club_id,
        to_club_id,
        -- dimensions
        CAST(transfer_date as DATE) as transfer_date,
        transfer_season,
        -- facts
        transfer_fee,
        market_value_in_eur,
        -- metadata
        loaded_timestamp,
        source_file

    from source

)

select *
from players
