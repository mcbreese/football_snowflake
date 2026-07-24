# football_snowflake
# ⚽ Transfer Market Data Platform: Project Logbook

This is my personal side project focused on building a solid data transformation pipeline using raw football transfer and performance statistics. The goal was to take source files, run them through an ETL process on Snowflake, and produce Gold-level fact tables that are actually usable for reporting—stuff like player performance metrics for transfer decision-making (though I haven't actually built the dashboard yet).

The main reason this project exists was to force myself to learn dbt Core. Every architectural choice, data contract, and test was done with the intent of practising proper dbt principles: modularity, testing, and documentation.

This section documents my journey building this analytics platform, highlighting technical decisions, encountered challenges, and successful implementations across the PySpark ETL and dbt transformation layers.

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