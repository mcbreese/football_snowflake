-- Fails if an appearance's club_id is neither side of the game it was in,
-- e.g. if club_id is ever sourced from the player's current club again.

select
    player_appearance_sk,
    player_id,
    game_id,
    club_id,
    home_club_id,
    away_club_id
from {{ ref('int_player_appearances') }}
where club_id not in (home_club_id, away_club_id)
