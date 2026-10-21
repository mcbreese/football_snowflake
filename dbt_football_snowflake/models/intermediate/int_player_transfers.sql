with transfers as (

    select
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
        tr.loaded_timestamp as transfer_loaded_timestamp,
        tr.source_file as transfer_source_file

    from {{ ref('stg_transfers') }} as tr
),

joined as (

    select
        -- Primary Key
        tr.player_transfer_sk,
        -- Club Names
        from_club.name as from_club_name,
        to_club.name as to_club_name,

        -- Transfer Details (Facts)
        tr.transfer_date,
        tr.transfer_season,
        tr.transfer_fee,
        tr.market_value_in_eur,

        -- Age at the transfer date, not today. Other player attributes
        -- are current-state only and belong in dim_players.
        {{ age_at_date('pl.date_of_birth', 'tr.transfer_date') }}
            as transfer_age_in_years,

        -- Foreign Keys
        tr.player_id,
        tr.from_club_id,
        tr.to_club_id,

        -- Metadata (Keeping only the transfer metadata)
        tr.transfer_loaded_timestamp,
        tr.transfer_source_file

    from transfers as tr

    -- Join to Player for date_of_birth only (age at transfer)
    left join {{ ref('stg_players') }} as pl
        on tr.player_id = pl.player_id

    -- Join to Club for 'From Club' Name
    left join {{ ref('stg_clubs') }} as from_club
        on tr.from_club_id = from_club.club_id

    -- Join to Club for 'To Club' Name
    left join {{ ref('stg_clubs') }} as to_club
        on tr.to_club_id = to_club.club_id
)

select *
from joined
