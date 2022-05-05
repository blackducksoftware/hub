/* This is the source of truth script, which is ported downstream for:
    1) Docker Swarm Managed Postgres Users (artifacted as part of documentation for manual setup of the Database)
    2) Kubernetes/OpenShift Managed Postgres Users (runs automatically as part of a Kubernetes Job)

    NOTE: in order to use this script, replace 'POSTGRESQL_USER' with the admin level user (used to be 'blackduck' by default);
          replace 'HUB_POSTGRES_USER' with the user you want containers to use (used to be 'blackduck_user' by default)
          and replace 'BLACKDUCK_USER_PASSWORD' with the password you want to set for user 'HUB_POSTGRES_USER'
 */

SELECT 'CREATE DATABASE bds_hub OWNER "POSTGRESQL_USER"'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'bds_hub')\gexec

SELECT 'CREATE DATABASE bds_hub_report OWNER "POSTGRESQL_USER"'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'bds_hub_report')\gexec

SELECT 'DROP DATABASE IF EXISTS bdio'\gexec

SELECT 'CREATE USER "HUB_POSTGRES_USER" WITH NOCREATEDB NOSUPERUSER NOREPLICATION NOBYPASSRLS'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'HUB_POSTGRES_USER')\gexec

ALTER USER "HUB_POSTGRES_USER" WITH password 'BLACKDUCK_USER_PASSWORD';
GRANT "HUB_POSTGRES_USER" to "POSTGRESQL_USER";

SELECT 'CREATE USER blackduck_reporter'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'blackduck_reporter')\gexec

\c bds_hub
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS st AUTHORIZATION "POSTGRESQL_USER";
GRANT USAGE ON SCHEMA st TO "HUB_POSTGRES_USER";
GRANT SELECT, INSERT, UPDATE, TRUNCATE, DELETE, REFERENCES ON ALL TABLES IN SCHEMA st TO "HUB_POSTGRES_USER";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA st to "HUB_POSTGRES_USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA st GRANT SELECT, INSERT, UPDATE, TRUNCATE, DELETE, REFERENCES ON TABLES TO "HUB_POSTGRES_USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA st GRANT ALL PRIVILEGES ON SEQUENCES TO "HUB_POSTGRES_USER";
REVOKE ALL ON SCHEMA st FROM blackduck_reporter;
ALTER DATABASE bds_hub SET standard_conforming_strings TO OFF;

\c bds_hub_report
GRANT SELECT ON ALL TABLES IN SCHEMA public TO blackduck_reporter;
ALTER DEFAULT PRIVILEGES FOR ROLE "POSTGRESQL_USER" IN SCHEMA public GRANT SELECT ON TABLES TO blackduck_reporter;
GRANT SELECT, INSERT, UPDATE, TRUNCATE, DELETE, REFERENCES ON ALL TABLES IN SCHEMA public TO "HUB_POSTGRES_USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, TRUNCATE, DELETE, REFERENCES ON TABLES TO "HUB_POSTGRES_USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO "HUB_POSTGRES_USER";
ALTER DATABASE bds_hub_report SET standard_conforming_strings TO OFF;

-- Stop here since cloud providers do not allow us to run ALTER SYSTEM
\q

ALTER SYSTEM SET autovacuum TO 'on';
ALTER SYSTEM SET autovacuum_max_workers TO '20';
ALTER SYSTEM SET autovacuum_vacuum_cost_limit TO '2000';
ALTER SYSTEM SET autovacuum_vacuum_cost_delay TO '10ms';
ALTER SYSTEM SET checkpoint_completion_target TO '0.8';
ALTER SYSTEM SET checkpoint_segments TO '256';
ALTER SYSTEM SET checkpoint_timeout TO '30min';
ALTER SYSTEM SET constraint_exclusion TO 'partition';
ALTER SYSTEM SET default_statistics_target TO '100';
ALTER SYSTEM SET effective_cache_size TO '256MB';
ALTER SYSTEM SET escape_string_warning TO 'off';
ALTER SYSTEM SET log_destination TO 'stderr';
ALTER SYSTEM SET log_directory TO 'pg_log';
ALTER SYSTEM SET log_filename TO 'postgresql_%a.log';
ALTER SYSTEM SET log_line_prefix TO '%m %p ';
ALTER SYSTEM SET log_rotation_age TO '1440';
ALTER SYSTEM SET log_truncate_on_rotation TO 'on';
ALTER SYSTEM SET logging_collector TO 'on';
ALTER SYSTEM SET maintenance_work_mem TO '32MB';
ALTER SYSTEM SET max_connections TO '300';
ALTER SYSTEM SET max_locks_per_transaction TO '256';
ALTER SYSTEM SET random_page_cost TO '4.0';
ALTER SYSTEM SET shared_buffers TO '1024MB';
ALTER SYSTEM SET ssl TO 'on';
ALTER SYSTEM SET ssl_ca_file TO 'root.crt';
ALTER SYSTEM SET ssl_cert_file TO 'hub-database.crt';
ALTER SYSTEM SET ssl_key_file TO 'hub-database.key';
ALTER SYSTEM SET standard_conforming_strings TO 'off';
ALTER SYSTEM SET temp_buffers TO '16MB';
ALTER SYSTEM SET work_mem TO '32MB';
