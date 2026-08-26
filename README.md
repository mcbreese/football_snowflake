# football_snowflake
# ⚽ Transfer Market Data Platform: Project Logbook

This is my personal side project focused on building a solid data transformation pipeline using raw football transfer and performance statistics. The goal was to take source files, run them through an ETL process on Snowflake, and produce Gold-level fact tables that are actually usable for reporting—stuff like player performance metrics for transfer decision-making (though I haven't actually built the dashboard yet).

The main reason this project exists was to force myself to learn dbt Core. Every architectural choice, data contract, and test was done with the intent of practising proper dbt principles: modularity, testing, and documentation.

This section documents my journey building this analytics platform, highlighting technical decisions, encountered challenges, and successful implementations across the PySpark ETL and dbt transformation layers.

## Tech Stack

- **Transformation:** dbt Core, on Snowflake
- **Orchestration/CI-CD:** GitHub Actions (PR checks, prod deploy, scratch-schema teardown)
- **Quality:** dbt data contracts (schema enforced per model, not just gold), dbt tests, sqlfluff + black
- **Tooling:** Python 3.12, managed with `uv`
- **Infra-as-code:** Snowflake roles/databases provisioned via checked-in SQL (`snowflake/`), not click-ops

## Repository Structure

```
football_snowflake/
├── dbt_football_snowflake/        # the dbt project itself
│   ├── models/
│   │   ├── staging/                 # stg_  - one per source table, light cleaning
│   │   ├── intermediate/            # int_  - joins/business logic between staging models
│   │   ├── marts/
│   │   │   ├── dimensions/            # dim_ - gold-layer dimensions
│   │   │   └── facts/                 # fct_ - gold-layer fact tables
│   │   └── exposures.yml            # downstream consumers of the gold layer
│   ├── macros/, seeds/, snapshots/, tests/, analyses/
│   ├── dbt_project.yml              # per-layer schema/materialization/tags config
│   ├── profiles.yml                 # dev/ci/prod/claude_readonly connection profiles - references env vars, no secrets
│   └── .sqlfluff                    # SQL lint config (dbt templater)
├── .github/workflows/
│   ├── dbt_test.yml                 # PR checks - Slim CI (state:modified+ --defer) against a throwaway schema
│   ├── dbt_deploy.yml               # push:main - the real prod deploy, publishes the manifest PRs diff against
│   └── dbt_ci_teardown.yml          # drops a PR's scratch schema once it's merged or closed
├── snowflake/                      # checked-in SQL for account/role/database setup
├── profiling/                      # one-off data profiling scripts + generated ydata-profiling reports
├── main.py                         # entry point for the profiling scripts
├── pyproject.toml / uv.lock        # Python dependencies
└── CLAUDE.md                       # working agreement/conventions for AI-assisted development on this repo
```

Not committed, by design: `secrets/` and `rsa_key.p8` (real credentials/keys), `dbt_football_snowflake/{target,dbt_packages,logs,state}/` (generated at build/compile time), `.vscode/settings.json` (personal IDE credentials).

## How It Works

**Data flow:** raw Transfermarkt Kaggle CSVs → manually loaded into Snowflake (`RAW.FOOTBALL`) → dbt staging → intermediate → marts (gold). Every model — staging included, not just gold — has its schema enforced by a one-per-model data contract file (`models/<layer>/<model>.yml`).

**Environments:** four dbt targets in `profiles.yml`, each backed by its own Snowflake role: `dev` (interactive local development), `ci` (PR builds, a throwaway schema per PR), `prod` (the real deploy), and `claude_readonly` (a genuinely read-only role, enforced by Snowflake itself, for local linting/compiling — not just a convention).

**CI/CD**, all under `.github/workflows/`:
- Every PR runs `dbt_test.yml`, which builds only the models that changed plus their downstream dependents (dbt's `state:modified+`) against the last successful prod deploy's manifest, rather than rebuilding the whole project on every PR.
- Merging to `main` triggers `dbt_deploy.yml` — the actual write to production — which also publishes the manifest the next PR's Slim CI comparison needs.
- `dbt_ci_teardown.yml` drops a PR's scratch schema once it's merged or closed, so nothing lingers in Snowflake.

**Governance:** GitHub branch protection and Dependabot on `main`, CODEOWNERS, a dedicated read-only Snowflake role for reporting/BI use, and Snowflake role/database setup checked in as SQL (`snowflake/`) rather than configured by hand in the UI.

The timeline below is a running first-person log of how the project actually got here, warts and all — kept as a historical record rather than rewritten after the fact.

## Project Logbook Timeline

| **Date** | **Focus Area** | **Action & Outcome** | 
| :--- | :--- | :--- |
| **20/07/2025** | **Development Environment** | Established a dedicated Python virtual environment (`.venv`) and isolated project dependencies (`jupyterlab`, `pandas`, `dbt-core`) to ensure portability and prevent system conflicts. | 
| **21/07/2025** | **Initial Data Discovery** | Implemented a Python script using `ydata_profiling` to automatically iterate through raw CSV sources and generate comprehensive data quality reports, significantly accelerating the initial data interrogation phase. | 
| **29/07/2025** | **Platform Architecture** | Defined the raw data landing zone using Databricks Catalogs and Volumes (`learning_catalog.football_raw`). This establishes the Bronze layer foundation for subsequent transformations. | 
| **12/08/2025** | **Bronze Layer ELT** | Developed the PySpark ingestion job to load files into Delta tables. Implemented best practices including adding `source_file` and `loaded_timestamp` metadata columns to the raw data, enhancing lineage and auditability. | 
| **28/08/2025** | **DBT Integration** | Successfully installed `dbt-core` and `dbt-databricks` and **initialised** the dbt project. Initial attempts to deploy failed due to misconfiguration of the Databricks catalog link in the `profiles.yml`, which was quickly rectified. | 
| **02/09/2025** | **Testing Fundamentals** | Successfully deployed and executed initial dbt tests, focusing on `relationships` (foreign key checks) and validating source-to-target mapping logic. | 
| **09/09/2025** | **DBT Project Planning** | Formalised the data flow architecture: `Raw CSV -> PySpark Bronze -> DBT Staging -> Intermediate -> Gold`. Began staging model creation and outlined the high-level context and metrics required for the Gold layer. | 
| **10/09/2025** | **IDE Connectivity** | Installed the Databricks VS Code extension and generated a Personal Access Token (PAT) for remote connectivity. Core functionality was achieved, allowing SQL development alongside dbt templating. | 
| **16/09/2025** | **Staging Layer Best Practice** | Created core staging tables and **utilised** the `dbt_utils.surrogate_key` macro extensively to introduce standardised primary keys across all source tables. | 
| **16/09/2025** | **Workflow Friction** | Identified friction due to slow turnaround time for testing complex Jinja/SQL models. Implemented a temporary process of running `dbt compile` and testing the generated SQL in a Databricks scratchpad. | 
| **23/09/2025** | **Intermediate Model Complexity** | Successfully created the `int_player_appearances` model, combining logic from multiple staging tables and reinforcing the understanding of dependencies and data lineage. | 
| **30/09/2025** | **Architectural Review** | Completed `int_player_transfers`. Acknowledged and documented potential metric bias towards attacking roles. Read the dbt-blueprint by Alex Teodosiu to inform architectural decisions. | 
| **07/10/2025** | **dbt-blueprint Exploration** | Attempted to implement the dbt-blueprint by Alex Teodosiu but struggled to install the necessary dependencies. | 
| **21/10/2025** | **Configuration Research** | Researching how to make optimal `dbt_project.yml`, `sources.yml`, and `schema` or `data_contracts.yml`. | 
| **11/11/2025** | **Documentation and Standardization** | Focused heavily on **optimising** `dbt_project.yml` and creating comprehensive data contracts (`stg_data_contracts.yml`). Overcame compilation issues related to special characters in documentation files. | 
| **18/11/2025** | **Data Contract Implementation** | Implemented data contracts across Staging and Gold layers. **Decision Point:** Temporarily removed a `not_null` test on a club ID column due to known source data quality issues, prioritising pipeline completion for the portfolio while documenting the known data defect. | 
| **26/11/2025** | **Secure Credential Management** | Implemented environment variable injection for `profiles.yml` using **VS Code Workspace Settings (`.vscode/settings.json`)**. This secures sensitive Databricks tokens locally. | 
| **26/11/2025** | **Custom Data Quality Test** | Created a singular test in the `tests/` directory to explicitly check that `total_appearances`, `total_goals`, and `total_assists` are not below zero in the Gold fact table, ensuring logical data integrity. | 
| **26/11/2025** | **Security Posture** | Added the `.vscode/` directory to `.gitignore` and used `git rm --cached` to stop tracking, ensuring credentials stored in `settings.json` are never accidentally committed to the repository. |
| **11/12/2025** | **Refactoring for Production Readiness** | Refactored the initial Jupyter Notebook (`.ipynb`) used for prototyping into a modular, lightweight Python script (`load_raw_sources.py`), the preferred format for automated Databricks Jobs. | 
| **23/07/2026** | **Development Environment** | Migrating workflow to Snowflake. | 
| **11/08/2026** | **AI-Assisted Development** | Brought Claude Code in as a pair-programming assistant — helped explain the codebase, folder structure, and dbt pipeline architecture. |
| **16/08/2026** | **Bronze Layer Retirement** | Removed the Databricks-only PySpark bronze-ingestion script (`etl/`) — raw CSVs are now loaded into Snowflake manually, so the pipeline is `Raw CSV -> Manual Snowflake Load -> DBT Staging -> Intermediate -> Gold`. |
| **16/08/2026** | **Cost & Governance Review** | Confirmed `DEV_TRANSFORM_WH` is sized X-Small with a 60-second auto-suspend (configured directly in Snowflake, not managed via IaC). Also: enabled GitHub branch protection and Dependabot, added a `snowflake/setup_reporting_role.sql` read-only role script, converted `dim_transfer_date` to a seed, and made `int_player_appearances` incremental. |
| **18/08/2026** | **State-Based CI** | Split the single `DATA_ENGINEER` role/`dev` target into genuine `dev`/`ci`/`prod` environments — `DEV_ROLE`/`CI_ROLE`/`PROD_ROLE` (see `snowflake/setup_ci_prod_roles.sql`), a shared `RAW.FOOTBALL` raw database, and a repurposed `CI_ANALYTICS` database for throwaway per-PR schemas. Added a `push:main` prod-deploy workflow (`dbt_deploy.yml`) that publishes a `manifest.json` artifact, a PR-teardown workflow (`dbt_ci_teardown.yml`), and switched `dbt_test.yml` to dbt's Slim CI pattern (`state:modified+ --defer`) so PRs build only changed models plus dependents against real prod state instead of the full DAG. |
| **18/08/2026** | **State-Based CI — Recovery & Verification** | Mid-rollout, discovered the raw CSV data had been manually loaded into `PRD_ANALYTICS.FOOTBALL` instead of `DEV_RAW` at some earlier point — recovered via zero-copy `CLONE` into `RAW.FOOTBALL` (`snowflake/migrate_raw_data_from_prd_analytics.sql`), verified with matching row counts, no data lost. Fixed a first-PR chicken-and-egg bug where looking up `dbt_deploy.yml`'s run history 404s before that workflow exists on `main` (now falls back to a full build). Expanded the `generate_schema_name`/`drop_ci_schema` macros with line-by-line Jinja explanations. Verified the full mechanism end-to-end with two throwaway PRs: a macro-only change correctly selected zero models (nothing depends on those macros), and a `stg_appearances` comment correctly cascaded to its true downstream dependents (`int_player_appearances`, `fct_player_performance_per_season_competition`) while `--defer` resolved untouched refs (`dim_clubs`, `dim_players`) to their real `PRD_ANALYTICS` locations — confirmed directly against the downloaded `manifest.json`. |