#!/usr/bin/env bash
# Wrapper invoked by .pre-commit-config.yaml's dbt-parse hook.
#
# `dbt parse` builds the whole manifest - refs, sources, contract yml,
# Jinja - but never compiles/executes SQL against the warehouse, so it's
# safe and cheap to run on every relevant commit. It still needs cwd =
# dbt_football_snowflake/ to find dbt_project.yml/profiles.yml, same
# reason as sqlfluff-lint.sh next to this file.
set -euo pipefail

cd dbt_football_snowflake

# claude_readonly: same shared read-only credential as sqlfluff-lint.sh
# (see CLAUDE.md's Auth section). `dbt parse` doesn't need a live query,
# but profiles.yml's env_var() calls still need real-looking values or it
# fails while rendering the profile, before parsing even starts.
uv run --env-file ../secrets/.env.readonly dbt parse --target claude_readonly --profiles-dir .
