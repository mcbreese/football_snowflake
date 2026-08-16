# dbt_football_snowflake

The dbt Core project for the `football_snowflake` platform: staging,
intermediate, and gold-layer transformations over football transfer and
performance data, targeting Snowflake.

Project root for all dbt commands is this directory — see the repo root
[`README.md`](../README.md) for the project's background and logbook, and
[`CLAUDE.md`](../CLAUDE.md) for architecture, running instructions, and
conventions.

### Running

```
uv run dbt debug --profiles-dir .
uv run dbt deps --profiles-dir .
uv run dbt test --profiles-dir .
```
