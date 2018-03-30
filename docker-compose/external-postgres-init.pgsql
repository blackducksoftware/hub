CREATE DATABASE bds_hub owner blackduck ;
CREATE DATABASE bds_hub_report owner blackduck;
CREATE DATABASE bdio owner blackduck;

CREATE USER blackduck_user;

CREATE USER blackduck_reporter;

\c bds_hub
CREATE EXTENSION pgcrypto;
CREATE SCHEMA st AUTHORIZATION blackduck;
GRANT USAGE ON SCHEMA st TO blackduck_user ;
GRANT SELECT, INSERT, UPDATE, TRUNCATE, DELETE, REFERENCES ON ALL TABLES IN SCHEMA st TO blackduck_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA st to blackduck_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA st GRANT SELECT, INSERT, UPDATE, TRUNCATE, DELETE, REFERENCES ON TABLES TO blackduck_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA st GRANT ALL PRIVILEGES ON SEQUENCES TO blackduck_user;

\c bds_hub_report
GRANT SELECT ON ALL TABLES IN SCHEMA public TO blackduck_reporter;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO blackduck_reporter;
GRANT SELECT, INSERT, UPDATE, TRUNCATE, DELETE, REFERENCES ON ALL TABLES IN SCHEMA public TO blackduck_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, TRUNCATE, DELETE, REFERENCES ON TABLES TO blackduck_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO blackduck_user;

\c bdio
GRANT ALL PRIVILEGES ON DATABASE bdio TO blackduck_user;

-- Stop here since Amazon RDS does not allow us to run ALTER SYSTEM
\q

ALTER SYSTEM SET autovacuum TO 'on';
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
