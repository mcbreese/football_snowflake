#!/usr/bin/env bash
# Wrapper invoked by .pre-commit-config.yaml's sqlfluff-lint hook.
#
# Why this can't just be `entry: uv run sqlfluff lint` directly:
#
# 1. cwd: dbt_football_snowflake/.sqlfluff sets
#    [sqlfluff:templater:dbt] project_dir = . and profiles_dir = . - both
#    are resolved relative to whatever directory sqlfluff is *run from*,
#    not relative to the .sqlfluff file itself. pre-commit always invokes
#    hooks from the repo root (one level up from dbt_football_snowflake/),
#    so without an explicit `cd` those would resolve to the wrong
#    directory. CI's lint job (dbt_test.yml) sets
#    `working-directory: ./dbt_football_snowflake` for this exact reason -
#    this script is doing the same thing by hand.
#
# 2. paths: because .pre-commit-config.yaml lives at the repo root,
#    pre-commit hands this script staged file paths relative to the repo
#    root too (e.g. dbt_football_snowflake/models/staging/stg_clubs.sql).
#    Once we cd into dbt_football_snowflake/, sqlfluff needs those same
#    files addressed relative to *there* instead
#    (models/staging/stg_clubs.sql) - so the dbt_football_snowflake/
#    prefix has to be stripped before we hand them off.
set -euo pipefail

files=()
for f in "$@"; do
  files+=("${f#dbt_football_snowflake/}")
done

cd dbt_football_snowflake

# claude_readonly: the shared, read-only Snowflake credential CLAUDE.md
# documents as the sanctioned path for local sqlfluff/dbt tooling like
# this - not a real build, just compiling Jinja to lint the rendered SQL.
uv run --env-file ../secrets/.env.readonly sqlfluff lint "${files[@]}"
