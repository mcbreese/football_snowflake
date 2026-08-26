# Gold Layer Documentation

This file contains documentation blocks for models and columns specific to the final, aggregated Gold Layer fact tables (Marts).

***

## Model Descriptions

{% docs fct_performance_model_description %}
This model aggregates a player's full career performance metrics by **Player**, **Season**, and **Competition**. It provides key derived metrics such as goals per 90 minutes and win/loss/draw counts, designed for in-depth comparative player analysis.
{% enddocs %}

{% docs fct_transfers_model_description %}
A complete historical record of every player transfer event and the associated financial details, calculated market valuation changes, and market value vs. fee analysis.
{% enddocs %}

***

## Column Definitions (Derived Metrics & Aggregates)

{% docs player_performance_sk %}
**Surrogate Key (PK).** Generated via `dbt_utils.generate_surrogate_key(['player_id', 'club_id', 'season', 'competition_name'])`, uniquely identifying one row at this model's grain (one player, one club, one season, one competition).
{% enddocs %}

{% docs competition_name_fct %}
The human-readable name of the competition (e.g., "Premier League"), denormalised from the `dim_competitions` table for ease of reporting.
{% enddocs %}

{% docs total_appearances %}
The count of games the player participated in during the defined season and competition.
{% enddocs %}

{% docs total_yellow_cards %}
The total count of yellow cards received by the player.
{% enddocs %}

{% docs total_red_cards %}
The total count of red cards received by the player.
{% enddocs %}

{% docs total_goals %}
The total number of goals scored by the player during the defined season and competition.
{% enddocs %}

{% docs total_assists %}
The total number of assists recorded by the player during the defined season and competition.
{% enddocs %}

{% docs total_minutes_played %}
The total minutes the player was on the field during the defined season and competition.
{% enddocs %}

{% docs avg_mins_per_appearance %}
The average number of minutes played per game appearance (calculated: `total_minutes_played / total_appearances`).
{% enddocs %}

{% docs avg_goals_per_90_mins %}
The rate of goals scored per 90 minutes played (calculated: `total_goals / (total_minutes_played / 90)`). This is a standard scouting metric.
{% enddocs %}

{% docs games_won %}
The count of games the player's team won during the appearances.
{% enddocs %}

{% docs games_lost %}
The count of games the player's team lost during the appearances.
{% enddocs %}

{% docs games_drawn %}
The count of games that ended in a draw during the appearances.
{% enddocs %}

{% docs first_appearance_loaded_timestamp %}
The `loaded_timestamp` from the first appearance record used in the aggregation, used for lineage tracking.
{% enddocs %}

{% docs transfer_loaded_timestamp %}
The `loaded_timestamp` of the player transfer, used for lineage tracking.
{% enddocs %}