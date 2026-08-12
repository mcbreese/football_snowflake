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

1.  **Model-Specific YAML Files:** Look for a corresponding `.yml` file next to the model's SQL file (e.g., `int_player_transfers_with_value.yml` next to `int_player_transfers_with_value.sql`).
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