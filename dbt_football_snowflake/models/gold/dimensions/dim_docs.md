# Gold Layer Documentation

This file contains documentation blocks for models and columns specific to the final dimension tables.

## Model Descriptions

{% docs dim_clubs_model_description %}
A dimension table containing static and slowly changing attributes related to football clubs, used to join against fact tables for reporting.
{% enddocs %}

{% docs dim_competitions_model_description %}
A dimension table containing details about leagues and cups, including their type, country, and official identifier.
{% enddocs %}

{% docs dim_players_model_description %}
A dimension table containing player demographics and biographic details, such as name, nationality, primary position, and current age.
{% enddocs %}

{% docs dim_transfer_date_model_description %}
A date spine dimension covering 2000-01-01 through 2030-12-31, one row per calendar day, used to join fact tables to a `date_key` for calendar-based reporting (e.g. by transfer season).
{% enddocs %}


***
## Dimension Column Definitions

{% docs club_sk_pk %}
**Surrogate Key (PK).** A unique key for the club record, allowing for future historical tracking.
{% enddocs %}

{% docs club_name %}
The full, human-readable name of the football club.
{% enddocs %}

{% docs competition_sk_pk %}
**Surrogate Key (PK).** A unique key for the competition record, allowing for future historical tracking.
{% enddocs %}

{% docs competition_name_dim %}
The full, official name of the competition.
{% enddocs %}

{% docs competition_type %}
The type of competition (e.g., 'League', 'Cup').
{% enddocs %}

{% docs competition_sub_type %}
The sub-type of competition (e.g., 'Domestic', 'International').
{% enddocs %}

{% docs competition_country_name %}
The name of the primary country the competition operates in.
{% enddocs %}

{% docs player_sk_pk %}
**Surrogate Key (PK).** A unique key for the player record, allowing for future historical tracking.
{% enddocs %}

{% docs loaded_timestamp_dim %}
The timestamp when the dimensional record was last loaded or updated into the warehouse.
{% enddocs %}

{% docs date_key %}
**Surrogate Key (PK).** The calendar date in `YYYYMMDD` integer form (e.g. `20240315`), used as the join key from fact tables to `dim_transfer_date`.
{% enddocs %}

{% docs date_day %}
The calendar date this row represents, as an actual `DATE` value.
{% enddocs %}

{% docs transfer_season_dim %}
The transfer season this calendar date falls within (e.g. "2023/2024"), calculated from `date_day`: January–May counts as the second half of the season starting the prior year, June–December starts a new season.
{% enddocs %}