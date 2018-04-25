#!/bin/bash

# Prerequisites:
#  1. The database container is running.
#  2. The database container has been properly initialized.

set -e

TIMEOUT=${TIMEOUT:-10}
HUB_VERSION=${HUB_VERSION:-4.6.1}
HUB_DATABASE_IMAGE_NAME=${HUB_DATABASE_IMAGE_NAME:-postgres}

function fail() {
	message=$1
	exit_status=$2
	echo "${message}"
	exit ${exit_status}
}

function set_container_id() {
	container_id=( `docker ps -q -f label=com.blackducksoftware.hub.version=${HUB_VERSION} \
								 -f label=com.blackducksoftware.hub.image=${HUB_DATABASE_IMAGE_NAME}` )
	return 0
}

# There should be one argument: destination of the path with name of the file
[ $# -ne "1" ] && fail "Usage:  $0 </local/full/path/to/dumpfile.dump>" 1
local_dest_dump_file="$1"

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
[ "${#container_id[*]}" -ne 1 ] && fail "${#container_id[*]} instances of the hub database container are running." 5

# Make sure that postgres is ready
sleep_count=0
until docker exec -i -u postgres ${container_id} pg_isready -q ; do
	sleep_count=$(( ${sleep_count} + 1 ))
	[ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database server in container ${container_id} not ready after ${TIMEOUT} seconds." 6
	sleep 1
done

# Make sure that bds_hub exists
sleep_count=0
until [ "$(docker exec -i -u postgres ${container_id} psql -A -t -c "select count(*) from pg_database where datname = 'bds_hub'" postgres 2> /dev/null)" -eq 1 ] ; do
	sleep_count=$(( ${sleep_count} + 1 ))
	[ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database bds_hub in container ${container_id} not ready after ${TIMEOUT} seconds." 7
	sleep 1
done

# Here we go...
echo Creating a dump from the container "${container_id}" '...'
docker exec -i ${container_id} pg_dump -U blackduck -Fc -f /tmp/bds_hub.dump bds_hub
exitCode=$? 
[ ${exitCode} -ne 0 ] && fail "Cannot create the dump file from the container [Container Id: ${container_id}]" 8

docker cp ${container_id}:/tmp/bds_hub.dump ${local_dest_dump_file} 
exitCode=$?
[ ${exitCode} -ne 0 ] && fail "Was not able to copy the dump file over [Container Id: ${container_id}]" 9

# After copy, remove the dump from the container.
docker exec -it ${container_id} rm /tmp/bds_hub.dump

echo Success with creating the dump and copying over to "[Destination Dir: $(dirname ${local_dest_dump_file})]" from the container: "[Container Id: ${container_id}]"
