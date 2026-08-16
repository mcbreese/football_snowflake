# CLAUDE.md

## Project

`dbt_football_snowflake` — a personal dbt Core project transforming football
transfer/performance data, built to production standards as a job-search
portfolio piece, not a throwaway learning repo. Treat it as if it runs
unattended in CI and is relied on by real stakeholders.

Currently mid-migration from Databricks to Snowflake (started 23/07/2026).
`databricks.yml` and the Databricks VS Code config are legacy. **Do not
reference, update, or "helpfully" restore Databricks config or tooling**,
even if you find it in the tree, it is being phased out, not the active
target.

## Running dbt

Project root is `dbt_football_snowflake/`, not the repo root. Run all dbt
commands from there, with `--profiles-dir .` (mirrors
`.github/workflows/dbt_test.yml`). Always invoke dbt via `uv run dbt ...`,
never bare `dbt` — a separate dbt Fusion preview binary also lives on this
machine's PATH ahead of the project's tools and will silently shadow the
pinned dbt-core/dbt-snowflake versions in `.venv` if invoked directly:

```
cd dbt_football_snowflake
uv run dbt debug --profiles-dir .
uv run dbt deps --profiles-dir .
uv run dbt test --profiles-dir .
```

## Architecture

Pipeline: raw CSV → manually loaded into Snowflake → dbt staging →
intermediate → gold, all within `dbt_football_snowflake/models/`. Per-layer
schema, materialization, and tags are configured in
`dbt_football_snowflake/dbt_project.yml`, read that file rather than
assuming layer config.

Model naming maps to layer: `stg_` (staging), `int_` (intermediate),
`dim_`/`fct_` (gold). This isn't linted, so respect it by convention when
adding models.

## Data contracts & sources

Each layer enforces its schema via a contracts file:
`models/staging/stg_data_contracts.yml`,
`models/gold/dimensions/dim_data_contracts.yml`,
`models/gold/facts/fct_data_contracts.yml`. Sources are declared in
`models/staging/sources/stg_sources.yml`, exposures in
`models/exposures.yml`. Check these files for current column/type
definitions rather than inferring schema from model SQL alone.

## Auth

Snowflake key-pair auth via `private_key_path` (`profiles.yml`, defaults to
`rsa_key.p8`). The key is never committed, CI materialises it at runtime
from `secrets.RSA_KEY_CONTENTS` (`.github/workflows/dbt_test.yml`). Don't
create or commit a real key file locally.

## Environment / target safety

Never run `dbt run`, `dbt build`, or `dbt test` against a production target
without explicit confirmation from me first, even if a production target is
configured in `profiles.yml`. Default to the dev target for anything you
run autonomously. There is only one target at the moment and it is a dev environment.

## CI

`.github/workflows/dbt_test.yml` is the source of truth for the test
pipeline (runs on push/PR to `main`).

## Conventions (judgement calls the contracts files can't express)

- Surrogate keys via `dbt_utils.generate_surrogate_key`, never natural keys
  alone, source data has had duplicate/inconsistent natural keys before.
- If a change would alter a gold-layer grain, flag it explicitly and
  explain the downstream impact before implementing, don't just update the
  contract file to match.
- New gold-layer columns need a test *and* a contract entry before being
  considered done, not just before commit.
- `meta.owner` values (`"Data Engineering"` on staging/intermediate,
  `"Analytics Department"` on gold dimensions, `"Analytics / Data
  Science"` on gold facts) are illustrative role labels standing in for
  what a real org's ownership model would look like — this is a solo
  project, so all three are currently the same person. Keep the labels
  consistent with this pattern when adding models; don't invent new ones
  without updating this note.

## Review Standard (senior DE lens)

When reviewing or writing code, check for:

- Does this scale? Flag full table scans, unnecessary cross joins, or
  anything that will degrade as source data grows past the current Kaggle
  snapshot size.
- Are nulls being coalesced or defaulted in a way that hides bad source
  data rather than surfacing it?
- Does this follow the layer conventions above, or does it quietly
  introduce a pattern (e.g. snowflaking a dimension) without a stated
  reason?
- Security/governance: no hardcoded credentials, no PII handling without
  flagging it explicitly, even though this dataset doesn't currently
  contain any.

## Important Rules

- Never commit `.env`, `profiles.yml` credentials, or Snowflake keys.
- If uncertain whether to proceed or ask, default to asking first. This is
  a solo repo with no one else to catch a wrong turn before it's merged, so
  a blocked question costs less than an unreviewed assumption. Proceeding
  without asking is only acceptable for small, easily-reversible changes
  (e.g. formatting, a missing test on an existing pattern) where the
  correct approach is genuinely unambiguous.