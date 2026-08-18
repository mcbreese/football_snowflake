{% macro drop_ci_schema() %}

    {#-
        Tears down a single PR's throwaway CI schema
        (CI_ANALYTICS.pr_<n>), invoked via
        `dbt run-operation drop_ci_schema --target ci` with DBT_CI_SCHEMA
        set to the same value used to build it. The target.name guard
        plus DBT_CI_SCHEMA having no default in profiles.yml makes it
        very hard for this to ever touch anything other than a CI
        scratch schema.
    -#}
    {%- if target.name != 'ci' -%}
        {{ exceptions.raise_compiler_error("drop_ci_schema can only be run against the `ci` target.") }}
    {%- endif -%}

    {% set drop_sql %}
        DROP SCHEMA IF EXISTS {{ target.database }}.{{ target.schema }} CASCADE
    {% endset %}

    {% do log("Dropping CI schema: " ~ target.database ~ "." ~ target.schema, info=True) %}
    {% do run_query(drop_sql) %}

{% endmacro %}
