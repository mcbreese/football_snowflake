select
    club_sk,
    club_id,
    name,
    loaded_timestamp
from {{ ref('int_clubs') }}
