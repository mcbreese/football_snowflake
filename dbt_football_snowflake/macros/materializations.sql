-- Name of the macro, did this one as a test
{% macro materialization_config() %}
-- The config block instructs dbt to create a table in the database based on this statement
{{ config(
  materialized='table',
  file_format='delta'
) }}
{% endmacro %}