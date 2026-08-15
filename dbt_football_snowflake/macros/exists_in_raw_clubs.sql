{% macro exists_in_raw_clubs(club_id_expr) %}
EXISTS (
    SELECT 1
    FROM {{ source('football_raw', 'raw_clubs') }} AS cl
    WHERE cl.club_id = {{ club_id_expr }}
)
{% endmacro %}
