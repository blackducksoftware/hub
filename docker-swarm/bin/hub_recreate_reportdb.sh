#!/bin/bash

# Prerequisites:
#  1. The database container is running.
#  2. The database container has been properly initialized.

set -e

TIMEOUT=${TIMEOUT:-10}
HUB_POSTGRES_VERSION=${HUB_POSTGRES_VERSION:-11-2.11}
HUB_DATABASE_IMAGE_NAME=${HUB_DATABASE_IMAGE_NAME:-postgres}


function fail() {
    message=$1
    exit_status=$2
    
    echo "${message}"
    exit ${exit_status}
}

function set_container_id() {
    container_id=( `docker ps -q -f label=com.blackducksoftware.hub.version=${HUB_POSTGRES_VERSION} \
                                 -f label=com.blackducksoftware.hub.image=${HUB_DATABASE_IMAGE_NAME}` )
    return 0
}

# Check that docker is on our path
[ "$(type -p docker)" == "" ] && fail docker not found on the search path 2

# Check that we can contact the docker daemon
docker ps > /dev/null
success=$?
[ ${success} -ne 0 ] && fail "Could not contact docker daemon. Is DOCKER_HOST set correctly?" 3

# Find the database container ID(s); give the container a few seconds to start if necessary
sleep_count=0
until set_container_id && [ "${#container_id[*]}" -gt 0 ] ; do
    sleep_count=$(( ${sleep_count} + 1 ))
    [ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database container not ready after ${TIMEOUT} seconds." 4
    sleep 1
done

# Check that exactly one instance of the database container is up and running
[ "${#container_id[*]}" -ne 1 ] && fail "${#container_id[*]} instances of the Black Duck database container are running." 5

# Make sure that postgres is ready
sleep_count=0
until docker exec -i ${container_id} pg_isready -U postgres -q ; do
    sleep_count=$(( ${sleep_count} + 1 ))
    [ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database server in container ${container_id} not ready after ${TIMEOUT} seconds." 6
    sleep 1
done

# Make sure that bds_hub_report does not already exist
if [ "$(docker exec -i ${container_id} psql -U postgres -A -t -c "select count(*) from pg_database where datname = 'bds_hub_report'" postgres 2> /dev/null)" != "0" ] ; then
	fail "bds_hub_report already exists" 2
fi

docker exec -i ${container_id} psql -U postgres -d postgres <<- EOF
	CREATE DATABASE bds_hub_report OWNER postgres ENCODING SQL_ASCII;
	\c bds_hub_report
	GRANT SELECT, INSERT, UPDATE, TRUNCATE, DELETE, REFERENCES ON ALL TABLES IN SCHEMA public TO blackduck_user;
	GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public to blackduck_user;
	ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, TRUNCATE, DELETE, REFERENCES ON TABLES TO blackduck_user;
	ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO blackduck_user;
	GRANT SELECT ON ALL TABLES IN SCHEMA public TO blackduck_reporter;
	ALTER DEFAULT PRIVILEGES FOR ROLE blackduck IN SCHEMA public GRANT SELECT ON TABLES TO blackduck_reporter;
	EOF
