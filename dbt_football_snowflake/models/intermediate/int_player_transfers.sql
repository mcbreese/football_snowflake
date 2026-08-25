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

    from transfers as tr

    -- Join to Player Details
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
