#!/bin/bash

# Prerequisites:
#  1. The database container is running.
#  2. The database container has been properly initialized.
#  3. The "st" schema in bds_hub is present but empty (i.e., the schema has not been migrated).
#  4. docker is on the search path.
#  5. The user has suitable privileges for running docker.
#  6. The database container can be identified in the output of a locally run "docker ps".
#  7. A custom-format dump of bds_hub is locally accessible.
#  8. "docker exec -i -u postgres ..." works.

set -e

TIMEOUT=${TIMEOUT:-10}
HUB_VERSION=${HUB_VERSION:-4.7.0}
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

# There should be one argument:  the dump file
[ $# -ne "1" ] && fail "Usage:  $0 </full/path/to/bds_hub.dump>" 1
dump_file="$1"

# Check that the dump file actually exists and is readable
[ ! -f "${dump_file}" ] && fail "${dump_file} does not exist or is not a file" 2
[ ! -r "${dump_file}" ] && fail "${dump_file} is not readable" 2

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
[ "${#container_id[*]}" -ne 1 ] && fail "${#container_id[*]} instances of the hub database container are running." 6

# Make sure that postgres is ready
sleep_count=0
until docker exec -i -u postgres ${container_id} pg_isready -q ; do
	sleep_count=$(( ${sleep_count} + 1 ))
	[ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database server in container ${container_id} not ready after ${TIMEOUT} seconds." 7
	sleep 1
done

# Make sure that bds_hub exists
sleep_count=0
until [ "$(docker exec -i -u postgres ${container_id} psql -A -t -c "select count(*) from pg_database where datname = 'bds_hub'" postgres 2> /dev/null)" -eq 1 ] ; do
	sleep_count=$(( ${sleep_count} + 1 ))
	[ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database bds_hub in container ${container_id} not ready after ${TIMEOUT} seconds." 8
	sleep 1
done

# Make sure that bds_hub is empty
table_count=`docker exec -i -u postgres ${container_id} psql -A -t -c "select count(*) from information_schema.tables where table_schema = 'st'" bds_hub`
[ "${table_count}" -ne 0 ] && fail "Database bds_hub in container ${container_id} has already been populated" 9

# Here we go...
echo Loading dump from "${dump_file}" '...'
cat "${dump_file}" | docker exec -i -u postgres ${container_id} pg_restore -Fc --verbose --clean --if-exists -d bds_hub || true
# mute the previous warnings and continue resetting the values to trigger report transfer job
docker exec -i -u postgres ${container_id} psql -d bds_hub << EOF 
DELETE from st.policy_setting WHERE policy_key='blackduck.reporting.database.transfer.last.end.time' OR policy_key='blackduck.reporting.database.transfer.last.id.processed';
UPDATE st.job_instances SET status='FAILED' where job_type='ReportingDatabaseTransferJob' and (status='SCHEDULED' or status='DISPATCHED' or status='RUNNING');
EOF