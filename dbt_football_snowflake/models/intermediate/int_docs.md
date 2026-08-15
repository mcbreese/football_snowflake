# Intermediate (INT) Layer Documentation Summary

This Markdown file serves as a high-level overview of the Intermediate data layer.

## Purpose of the Intermediate Layer

The **Intermediate (INT) layer** is responsible for cleaning, standardising, and aggregating data from the Staging (STG) layer before it is moved to the final Gold layer dimensions and facts.

Models in this layer perform key tasks such as:
* Standardising formats and applying type conversions.
* Generating initial surrogate keys (`SK`).
* Performing complex lookups and joins (e.g., linking transfers to club history).
* Creating aggregated summaries that will form the basis of the Gold layer facts.

## Documentation and Contract Structure

For maintainability and granular control, the column definitions, documentation tags, and data contracts for models in this layer are **not** contained in this file.

### Where to find model documentation:

1.  **Model-Specific YAML Files:** Look for a corresponding `.yml` file next to the model's SQL file (e.g., `int_player_transfers.yml` next to `int_player_transfers.sql`).
2.  **Data Contracts:** Data contracts are enforced via the `contract: enforced: true` setting in the model's YAML configuration, ensuring schema and type integrity before data is consumed by the Gold layer.

**If you need column descriptions, data types, or test definitions for an INT model, please consult the relevant `.yml` file.**

***

## Model Descriptions

{% docs int_players_model_description %}
Pass-through of `stg_players`, contract-enforced as the intermediate-layer interface for player data consumed by the Gold layer.
{% enddocs %}

{% docs int_competitions_model_description %}
Pass-through of `stg_competitions`, contract-enforced as the intermediate-layer interface for competition data consumed by the Gold layer.
{% enddocs %}

{% docs int_clubs_model_description %}
Pass-through of `stg_clubs`, contract-enforced as the intermediate-layer interface for club data consumed by the Gold layer.
{% enddocs %}

{% docs int_player_transfers_model_description %}
Joins `stg_transfers` to `stg_players` and `stg_clubs` (twice, for the from/to club) to enrich each transfer event with player and club names ahead of the Gold fact layer.
{% enddocs %}

{% docs int_player_appearances_model_description %}
Joins `stg_players` to `stg_appearances`, `stg_clubs`, `stg_competitions`, and `stg_games` to build one row per player appearance, enriched with the player's age at the appearance date, match outcome, and win/loss result, ahead of the Gold fact layer (`fct_player_performance_per_season_competition`).
{% enddocs %}

## Column Definitions (not already documented in the Staging layer)

{% docs from_club_name %}
The name of the club the player was transferred *from*, resolved by joining `stg_transfers.from_club_id` to `stg_clubs`.
{% enddocs %}

{% docs to_club_name %}
The name of the club the player was transferred *to*, resolved by joining `stg_transfers.to_club_id` to `stg_clubs`.
{% enddocs %}

{% docs transfer_source_file %}
The name or path of the raw file the transfer record was extracted from (data lineage/audit column, aliased from `stg_transfers.source_file`).
{% enddocs %}

{% docs player_appearance_sk %}
**Surrogate Key (SK).** Generated via `dbt_utils.generate_surrogate_key(['player_id', 'appearance_id'])`, uniquely identifying one player's participation in one appearance.
{% enddocs %}

{% docs appearance_age_in_years %}
The player's age, in whole years, at the date of the appearance (`DATEDIFF(YEAR, date_of_birth, appearance_date)`) — distinct from `age_in_years`, which is the player's age as of the latest data snapshot.
{% enddocs %}

{% docs home_away %}
Whether the player's club was the `home` or `away` side for this appearance, derived by comparing `stg_appearances.player_club_id` to `stg_games.home_club_id`.
{% enddocs %}

{% docs outcome %}
The result of the match from a neutral perspective: `home`, `away`, or `draw`, derived from comparing `stg_games.home_club_goals` to `away_club_goals`.
{% enddocs %}

{% docs player_win_loss %}
The match result from the appearing player's perspective — `player_win`, `player_loss`, or `draw` — derived by comparing `home_away` to `outcome`.
{% enddocs %}

{% docs competition_name %}
The human-readable name of the competition the appearance took place in (e.g., "Premier League"), resolved by joining `stg_appearances.competition_id` to `stg_competitions`.
{% enddocs %}