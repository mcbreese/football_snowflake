select
    pl.player_sk,
    pl.player_id,
    pl.current_club_id,
    pl.player_name,
    pl.nationality,
    pl.position,
    pl.sub_position,
    pl.foot,
    pl.height_in_cm,
    pl.date_of_birth,
    pl.age_in_years,
    pl.last_season,
    pl.loaded_timestamp,
    pl.source_file
from {{ ref('stg_players') }} as pl
