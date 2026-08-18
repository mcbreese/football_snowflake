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
`rsa_key.p8`). The key is never committed; each GitHub Actions workflow that
needs it (`dbt_test.yml`, `dbt_deploy.yml`, `dbt_ci_teardown.yml`)
materialises it at runtime from `secrets.RSA_KEY_CONTENTS`. Don't create or
commit a real key file locally.

## Environment / target safety

Three targets exist in `profiles.yml`: `dev` (local, `DEV_ROLE`), `ci`
(PR builds, `CI_ROLE`, throwaway per-PR schema in `CI_ANALYTICS`), and
`prod` (`PROD_ROLE`, writes to `PRD_ANALYTICS`). Never run `dbt run`, `dbt
build`, or `dbt test` against `--target prod` without explicit confirmation
from me first — that includes locally, not just suggesting CI changes.
Default to the dev target for anything you run autonomously. In CI, `prod`
is only ever invoked by `dbt_deploy.yml` (triggered on `push: main`, i.e.
only after a PR has already merged) — never add a `--target prod` build to
`dbt_test.yml` or any PR-triggered workflow.

## CI

Three workflows, each with a distinct role/target — see
`snowflake/setup_ci_prod_roles.sql` for the underlying Snowflake role/db
setup:

- `.github/workflows/dbt_test.yml` — PR checks against `--target ci`.
  Builds only `state:modified+` (changed models + downstream dependents),
  deferring unbuilt refs to the last successful prod state via `--defer
  --state`. Falls back to a full build if no prod manifest is available yet
  (first run, or an expired/missing artifact). Each PR gets its own flat
  scratch schema (`CI_ANALYTICS.pr_<n>`, see
  `macros/generate_schema_name.sql`).
- `.github/workflows/dbt_deploy.yml` — the actual prod deploy, triggered on
  `push: main` (i.e. only after a PR has already merged and passed
  `dbt_test.yml` — this doesn't double the per-merge build cost, it's doing
  a genuinely different thing: writing to `PRD_ANALYTICS` via `--target
  prod`, then publishing `target/manifest.json` as a `prod-manifest`
  artifact for `dbt_test.yml` to diff PRs against).
- `.github/workflows/dbt_ci_teardown.yml` — drops a PR's `CI_ANALYTICS`
  scratch schema on merge or close (`dbt run-operation drop_ci_schema
  --target ci`).

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