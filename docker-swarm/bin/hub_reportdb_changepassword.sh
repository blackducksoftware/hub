#!/bin/bash

set -e

TIMEOUT=${TIMEOUT:-10}
HUB_POSTGRES_VERSION=${HUB_POSTGRES_VERSION:-15-1.11}
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

# There should be one argument: password
[ $# -ne "1" ] && fail "Usage:  $0 <new password>" 1
new_password="$1"

# Check that docker is on our path
[ "$(type -p docker)" == "" ] && fail "docker not found on the search path" 3

# Check that we can contact the docker daemon
docker ps > /dev/null
success=$?
[ ${success} -ne 0 ] && fail "Could not contact docker daemon. Is DOCKER_HOST set correctly?" 4

# Find the database container ID(s); give the container a few seconds to start if necessary
sleep_count=0
until set_container_id && [ "${#container_id[*]}" -gt 0 ] ; do
    sleep_count=$(( ${sleep_count} + 1 ))
    [ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database container not ready after ${TIMEOUT} seconds." 5
    sleep 1
done

# Check that exactly one instance of the database container is up and running
[ "${#container_id[*]}" -ne 1 ] && fail "${#container_id[*]} instances of the Black Duck database container are running." 6

# Make sure that postgres is ready
sleep_count=0
until docker exec -i ${container_id} pg_isready -U postgres -q ; do
    sleep_count=$(( ${sleep_count} + 1 ))
    [ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database server in container ${container_id} not ready after ${TIMEOUT} seconds." 7
    sleep 1
done

docker exec -i ${container_id} psql -U postgres -c "alter user blackduck_reporter password '$new_password'"

echo "Password changed"
