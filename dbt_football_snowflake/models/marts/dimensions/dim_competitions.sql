select
    competition_sk,
    competition_id,
    name,
    type,
    sub_type,
    country_name,
    loaded_timestamp
from {{ ref('int_competitions') }}
