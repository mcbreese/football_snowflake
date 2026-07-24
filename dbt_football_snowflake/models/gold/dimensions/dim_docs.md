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


***
## Dimension Column Definitions

{% docs club_id_pk %}
**Primary Key (PK).** The unique identifier for the club.
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