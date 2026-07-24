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