/* This is the source of truth script, which is ported downstream for:
    1) Docker Swarm Managed Postgres Users (artifacted as part of documentation for manual setup of the Database)
    2) Kubernetes/OpenShift Managed Postgres Users (runs automatically as part of a Kubernetes Job)

    NOTE: in order to use this script, replace 'POSTGRESQL_USER' with the admin level user (used to be 'blackduck' by default);
          replace 'HUB_POSTGRES_USER' with the user you want containers to use (used to be 'blackduck_user' by default)
          and replace 'BLACKDUCK_USER_PASSWORD' with the password you want to set for user 'HUB_POSTGRES_USER'
 */

SELECT 'CREATE DATABASE bds_hub OWNER "POSTGRESQL_USER"'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'bds_hub')\gexec

SELECT 'DROP DATABASE IF EXISTS bdio'\gexec

SELECT 'CREATE USER "HUB_POSTGRES_USER" WITH NOCREATEDB NOSUPERUSER NOREPLICATION NOBYPASSRLS'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'HUB_POSTGRES_USER')\gexec

ALTER USER "HUB_POSTGRES_USER" WITH password 'BLACKDUCK_USER_PASSWORD';
GRANT "HUB_POSTGRES_USER" to "POSTGRESQL_USER";

SELECT 'CREATE USER blackduck_reporter'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'blackduck_reporter')\gexec

\c bds_hub
CREATE SCHEMA IF NOT EXISTS st AUTHORIZATION "POSTGRESQL_USER";
CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA st;
GRANT USAGE ON SCHEMA st TO "HUB_POSTGRES_USER";
GRANT SELECT, INSERT, UPDATE, TRUNCATE, DELETE, REFERENCES ON ALL TABLES IN SCHEMA st TO "HUB_POSTGRES_USER";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA st to "HUB_POSTGRES_USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA st GRANT SELECT, INSERT, UPDATE, TRUNCATE, DELETE, REFERENCES ON TABLES TO "HUB_POSTGRES_USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA st GRANT ALL PRIVILEGES ON SEQUENCES TO "HUB_POSTGRES_USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA st GRANT ALL PRIVILEGES ON FUNCTIONS TO "HUB_POSTGRES_USER";
REVOKE ALL ON SCHEMA st FROM blackduck_reporter;
ALTER DATABASE bds_hub SET standard_conforming_strings TO OFF;
