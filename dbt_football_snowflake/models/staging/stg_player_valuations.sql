with source as (

    select * from {{ source('football_raw', 'raw_player_valuations') }}

),

valuations as (

    select
        -- primary key
        -- we are using a combination of columns to make a unique key
        {{ dbt_utils.generate_surrogate_key(['player_id', 'date']) }}
            as player_valuation_sk,

        -- foreign key
        player_id,
        current_club_id,

        -- dimensions
        -- The date is a crucial dimension for tracking value over time
        cast(date as date) as valuation_date,

        -- facts
        -- Market value is the key metric here
        market_value_in_eur,

        -- metadata
        loaded_timestamp,
        source_file

    from source

)

select * from valuations
