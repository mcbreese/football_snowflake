{#-
    This is a dbt "hook" macro: dbt looks for a macro with this exact
    name and, if one exists in the project, calls it automatically for
    EVERY model right before deciding which Snowflake schema to build
    that model into. Nothing in this project ever calls
    generate_schema_name() directly - dbt-core's internals do, once per
    model, during compilation. If this file didn't exist, dbt would fall
    back to its own built-in version of this macro (which is exactly
    what the dev/prod branches below reproduce, so those two targets
    behave identically to "no override file at all" - only `ci` diverges).

    dbt always calls it with two arguments:
      - custom_schema_name: whatever a model configured via `+schema:` in
        dbt_project.yml - e.g. staging models are configured
        `+schema: stg`, so custom_schema_name is the string "stg" for
        those. A model with no `+schema:` config gets Jinja's `none`
        (like Python's `None`).
      - node: the model being compiled. Unused here - the same schema
        logic applies to every model - but dbt always passes it, so the
        macro signature has to accept it even though we ignore it.

    Whitespace-control note for the `{%- ... -%}` dashes used throughout:
    a plain `{% if %}` leaves the newlines/indentation around it in the
    output; the `-` trims them. Since this macro's entire "output" is a
    single schema name (e.g. "football_stg"), stray whitespace would
    literally end up as part of that name - so every tag here uses `-`
    to keep the result clean.
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}

    {#-
        `target` is a built-in variable dbt injects into every macro -
        it's whichever profiles.yml target this compilation is running
        under (dev / ci / prod), with all of that target's config
        attached as properties. `target.schema` is the target's base
        `schema:` value from profiles.yml: the literal string "football"
        for dev and prod, or whatever the DBT_CI_SCHEMA environment
        variable resolves to (e.g. "pr_35") for ci - see the `schema:`
        line under the `ci:` block in profiles.yml.

        `{% set x = ... %}` is Jinja's variable assignment - equivalent
        to `x = ...` in Python. It doesn't print anything by itself.
    -#}
    {%- set default_schema = target.schema -%}

    {#-
        `target.name` is the target's own name - literally "dev", "ci",
        or "prod", matching the block names in profiles.yml. This is how
        the macro tells which environment it's running under.
    -#}
    {%- if target.name == 'ci' -%}

        {#-
            CI-only branch: return the base schema as-is, completely
            ignoring custom_schema_name. This is what makes every layer
            (staging/intermediate/gold) land in the SAME schema for a PR
            build - e.g. everything goes into CI_ANALYTICS.pr_35, instead
            of pr_35_stg / pr_35_int / pr_35_gold like dev/prod would get
            for the equivalent models. That's deliberate: a whole PR's
            build can then be torn down with one
            `DROP SCHEMA ... CASCADE` (see drop_ci_schema.sql) instead of
            three separate drops. It's safe to collapse everything into
            one schema because model names (stg_players, int_players,
            dim_players, ...) are already unique across the whole
            project - no two models in different layers ever share a
            name, so nothing collides once they're all sitting side by
            side in one schema.

            `{{ ... }}` (double curly braces) is Jinja's "print this
            value" syntax - as opposed to `{% ... %}` (statement, no
            output) used for `if`/`set`/etc. above. This line is the
            macro's actual return value for the ci branch.
        -#}
        {{ default_schema }}

    {%- elif custom_schema_name is none -%}

        {#-
            `is none` is a Jinja test - checks whether custom_schema_name
            is exactly `none` (dbt passes this when a model has no
            `+schema:` config). Everything from here down is dbt-core's
            own default schema logic, reproduced unchanged, so dev/prod
            behave EXACTLY as they would with no override file present.
            In this project every model DOES set a `+schema:`
            (dbt_project.yml configures it per-layer), so this branch is
            here for completeness/safety rather than something that
            actually fires today.
        -#}
        {{ default_schema }}

    {%- else -%}

        {#-
            The normal dev/prod case: a model set `+schema: stg` (or
            int/gold) - append it to the base schema with an underscore.
            `~` is Jinja's string-concatenation operator (like `+` in
            Python/JS - note it's specifically `~`, not `+`, because `+`
            is reserved for numeric addition in Jinja). `| trim` is a
            filter (piped values get transformed by whatever follows the
            `|`) that strips any accidental leading/trailing whitespace
            from the config value.

            This is why dev's schemas come out as "football_stg",
            "football_int", "football_gold": default_schema="football",
            custom_schema_name is "stg"/"int"/"gold" per model, joined
            with "_".
        -#}
        {{ default_schema }}_{{ custom_schema_name | trim }}

    {%- endif -%}

{%- endmacro %}
