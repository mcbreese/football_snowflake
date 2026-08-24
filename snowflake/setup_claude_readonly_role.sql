-- Snowflake account-level setup: dedicated read-only service account for
-- Claude Code, genuinely separate from the personal MCBREESE login.
--
-- NOT run by dbt or CI - run manually via Snowsight/SnowSQL, same as the
-- other snowflake/*.sql scripts.
--
-- Why this exists: DEV_ROLE/CI_ROLE/PROD_ROLE are all granted to the same
-- personal Snowflake user (MCBREESE), which is also what Claude's local
-- investigation used until now. That meant "Claude only builds against
-- dev/ci, never prod without asking" was a convention Claude followed,
-- not something Snowflake itself enforced - the credential could, in
-- principle, `USE ROLE PROD_ROLE` since that user genuinely holds it.
--
-- This creates a real boundary instead: a new user that is NEVER granted
-- DEV_ROLE/CI_ROLE/PROD_ROLE, so it cannot issue a write/build no matter
-- what's asked of it - Snowflake rejects the role switch outright. Same
-- checked-in-role-script pattern as setup_reporting_role.sql /
-- setup_ci_prod_roles.sql.
--
-- The public key below is not sensitive (public keys are meant to be
-- shared) - safe to have committed here. Generated locally via:
--   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out claude_readonly_key.p8 -nocrypt
--   openssl rsa -in claude_readonly_key.p8 -pubout -out claude_readonly_key.pub
-- The private key stays local, gitignored, never committed - see
-- .claude/claude_readonly_key.p8.

USE ROLE SECURITYADMIN;

CREATE USER IF NOT EXISTS CLAUDE_SERVICE
  RSA_PUBLIC_KEY = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtPjCuhFkj9YIVIUpohd4feYZvTTDBaPyNJeiczXHW4nPMZKhFT1KPCL5YcQM2CeSN7MNuLEJSeWrtL0Cy1FKgAXvzYGWQ89t8uRf0NJpni3FqJEijQBAcUENcijX3McKkYW8yTq4ntg22955y6bjMt31OOEuZOJUF596wM+eu90pUzhbNKOFLFZIBcpiyPTijjbqFhHqhkEZxLSHT2A0MTshSOzj5IAyyHD2Vj6jpMZaJ+S0fgOjmFLSmnkdyCEAJ5Cfisg1ei3XkEvBjtcNOoXS18PzMESrTZXYmbmip0z/NUlmI8eWu9IaCxGaanPF1ay2TYY4VHAEJmJHxrm43QIDAQAB'
  DEFAULT_ROLE = CLAUDE_READONLY_ROLE
  DEFAULT_WAREHOUSE = DEV_TRANSFORM_WH
  COMMENT = 'Read-only service account for Claude Code local investigation. Never grant DEV_ROLE/CI_ROLE/PROD_ROLE to this user - the whole point is that it cannot write.';

CREATE ROLE IF NOT EXISTS CLAUDE_READONLY_ROLE;

GRANT USAGE ON WAREHOUSE DEV_TRANSFORM_WH TO ROLE CLAUDE_READONLY_ROLE;

-- Raw data - useful for the kind of real-data investigation that grounded
-- the numeric precision contract fix (checking actual min/max/decimal
-- places instead of guessing).
GRANT USAGE ON DATABASE RAW TO ROLE CLAUDE_READONLY_ROLE;
GRANT USAGE ON SCHEMA RAW.FOOTBALL TO ROLE CLAUDE_READONLY_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA RAW.FOOTBALL TO ROLE CLAUDE_READONLY_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW.FOOTBALL TO ROLE CLAUDE_READONLY_ROLE;

-- Dev output - read-only, so Claude can inspect built models without
-- being able to rebuild/modify them itself.
GRANT USAGE ON DATABASE DEV_ANALYTICS TO ROLE CLAUDE_READONLY_ROLE;
GRANT USAGE ON ALL SCHEMAS IN DATABASE DEV_ANALYTICS TO ROLE CLAUDE_READONLY_ROLE;
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE DEV_ANALYTICS TO ROLE CLAUDE_READONLY_ROLE;
GRANT SELECT ON ALL TABLES IN DATABASE DEV_ANALYTICS TO ROLE CLAUDE_READONLY_ROLE;
GRANT SELECT ON FUTURE TABLES IN DATABASE DEV_ANALYTICS TO ROLE CLAUDE_READONLY_ROLE;
GRANT SELECT ON ALL VIEWS IN DATABASE DEV_ANALYTICS TO ROLE CLAUDE_READONLY_ROLE;
GRANT SELECT ON FUTURE VIEWS IN DATABASE DEV_ANALYTICS TO ROLE CLAUDE_READONLY_ROLE;

-- Prod output - read-only, same read scope CI_ROLE already has (for
-- --defer resolution), so Claude can sanity-check prod state without any
-- write path to it at all.
GRANT USAGE ON DATABASE PRD_ANALYTICS TO ROLE CLAUDE_READONLY_ROLE;
GRANT USAGE ON ALL SCHEMAS IN DATABASE PRD_ANALYTICS TO ROLE CLAUDE_READONLY_ROLE;
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE PRD_ANALYTICS TO ROLE CLAUDE_READONLY_ROLE;
GRANT SELECT ON ALL TABLES IN DATABASE PRD_ANALYTICS TO ROLE CLAUDE_READONLY_ROLE;
GRANT SELECT ON FUTURE TABLES IN DATABASE PRD_ANALYTICS TO ROLE CLAUDE_READONLY_ROLE;
GRANT SELECT ON ALL VIEWS IN DATABASE PRD_ANALYTICS TO ROLE CLAUDE_READONLY_ROLE;
GRANT SELECT ON FUTURE VIEWS IN DATABASE PRD_ANALYTICS TO ROLE CLAUDE_READONLY_ROLE;

GRANT ROLE CLAUDE_READONLY_ROLE TO USER CLAUDE_SERVICE;
