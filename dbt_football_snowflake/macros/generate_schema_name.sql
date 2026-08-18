{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {%- if target.name == 'ci' -%}

        {#-
            CI builds every model (staging/intermediate/gold alike) into
            a single flat per-PR schema, so a whole PR's build can be
            torn down with one `DROP SCHEMA ... CASCADE` (see
            drop_ci_schema.sql). Per-layer custom schemas (stg/int/gold,
            see dbt_project.yml) are intentionally ignored for this
            target. Model naming (stg_/int_/dim_/fct_ prefixes) is
            already unique project-wide, so there's no cross-layer name
            collision risk inside the flat schema.
        -#}
        {{ default_schema }}

    {%- elif custom_schema_name is none -%}

        {# Reproduces dbt-core's default behaviour unchanged for dev/prod. #}
        {{ default_schema }}

    {%- else -%}

        {{ default_schema }}_{{ custom_schema_name | trim }}

    {%- endif -%}

{%- endmacro %}
