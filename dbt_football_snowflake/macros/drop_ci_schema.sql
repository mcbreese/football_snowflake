{#-
    Unlike generate_schema_name.sql, dbt never calls this one
    automatically - it's a plain macro you invoke yourself, on demand,
    via dbt's `run-operation` command:

        dbt run-operation drop_ci_schema --target ci

    `run-operation` is dbt's way of executing an arbitrary macro directly
    as a one-off command, instead of building models. dbt_ci_teardown.yml
    runs that exact command whenever a PR is merged or closed, to drop
    that PR's throwaway CI_ANALYTICS.pr_<n> schema. It takes no arguments
    (empty parens `()` below) - everything it needs (which schema, which
    database) comes from the `--target ci` connection context instead.
-#}
{% macro drop_ci_schema() %}

    {#-
        Safety check before doing anything destructive. `target` is the
        same built-in dbt variable used in generate_schema_name.sql -
        whichever `--target` flag this command was actually run with.
        `target.name` is that target's name as a plain string ("dev",
        "ci", or "prod"). If someone runs this against --target dev or
        --target prod by mistake, stop immediately instead of risking a
        DROP SCHEMA against a real database.

        `exceptions.raise_compiler_error(...)` is dbt's built-in way of
        failing fast with a custom message - the Jinja/dbt equivalent of
        `raise Exception(...)` in Python. It halts the macro (and the
        whole `run-operation` command) right there.

        Combined with DBT_CI_SCHEMA having no default value in
        profiles.yml (an unset env var makes the `ci` target fail to even
        connect, rather than silently resolving to some other schema),
        this guard makes it very hard for the DROP below to ever touch
        anything other than a genuine CI scratch schema.
    -#}
    {%- if target.name != 'ci' -%}
        {{ exceptions.raise_compiler_error("drop_ci_schema can only be run against the `ci` target.") }}
    {%- endif -%}

    {#-
        `{% set drop_sql %}...{% endset %}` is Jinja's "capture a block"
        form of `set` - instead of assigning a single expression (like
        `{% set x = target.schema %}`), it captures everything between
        the tags as a multi-line string and stores it in `drop_sql`.
        Nothing runs against Snowflake yet at this point - this only
        builds the SQL text.

        `target.database` / `target.schema` resolve to whichever
        CI_ANALYTICS / pr_<n> this `--target ci` run is configured for -
        the schema name specifically comes from the DBT_CI_SCHEMA
        environment variable (see the `ci:` block in profiles.yml).
        `IF EXISTS` makes the DROP a safe no-op if the PR's build never
        actually ran (nothing was ever created to drop), so teardown
        never fails just because a PR was closed without CI ever
        building anything. `CASCADE` drops every table/view inside the
        schema along with it, rather than erroring because the schema
        isn't empty.
    -#}
    {% set drop_sql %}
        DROP SCHEMA IF EXISTS {{ target.database }}.{{ target.schema }} CASCADE
    {% endset %}

    {#-
        Two `{% do ... %}` statements - `do` runs a Jinja expression for
        its side effects and discards any return value (needed here
        because both log() and run_query() return something, and we
        don't want that leaking into the macro's output).

        `log(..., info=True)` prints a message to the dbt run output
        (visible in the GitHub Actions log), so you can see exactly what
        got dropped and when. `~` again is string concatenation (see
        generate_schema_name.sql for why it's `~` and not `+`).

        `run_query(drop_sql)` is the one line that does real work -
        it actually sends the captured SQL string to Snowflake and
        executes it. Everything above this point only prepared for this
        moment; nothing was dropped until this line ran.
    -#}
    {% do log("Dropping CI schema: " ~ target.database ~ "." ~ target.schema, info=True) %}
    {% do run_query(drop_sql) %}

{% endmacro %}
