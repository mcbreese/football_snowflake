SELECT club_sk
    , club_id
    , name
    , loaded_timestamp
FROM {{ ref('int_clubs') }} AS cl
