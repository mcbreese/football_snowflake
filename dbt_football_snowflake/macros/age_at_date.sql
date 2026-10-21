{#-
    Whole years between a date of birth and an event date, correct to the
    day. DATEDIFF(year, ...) alone counts calendar-year boundaries, so it
    overstates age by one until the birthday that year (born 1 Dec 2000,
    event 1 Jan 2018 -> 18, not 17). Subtracting 1 when the birthday hasn't
    happened yet fixes that. A 29 Feb birthday counts as reached on 28 Feb
    in non-leap years (Snowflake's DATEADD clamps to month end).
    A null on either side returns null, so missing data stays visible.
-#}
{% macro age_at_date(date_of_birth, event_date) %}
    datediff(year, {{ date_of_birth }}, {{ event_date }})
    - iff(
        dateadd(
            year,
            datediff(year, {{ date_of_birth }}, {{ event_date }}),
            {{ date_of_birth }}
        ) > {{ event_date }},
        1,
        0
    )
{% endmacro %}
