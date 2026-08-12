-- Shared materialization config for gold-layer models.
{% macro materialization_config() %}
{{ config(
  materialized='table'
) }}
{% endmacro %}