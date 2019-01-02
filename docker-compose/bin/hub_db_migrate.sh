#!/bin/bash

# Prerequisites:
#  1. The database container is running.
#  2. The database container has been properly initialized.
#  3. For bds_hub, the "st" schema is present but empty (i.e., the schema has not been migrated).  
#     For bds_hub_report, the "public" schema is present but empty.
#     For bdio, the "public" schema is present but empty
#  4. docker is on the search path.
#  5. The user has suitable privileges for running docker.
#  6. The database container can be identified in the output of a locally run "docker ps".
#  7. A custom-format dump is locally accessible.
#  8. "docker exec -i -u postgres ..." works.

set -e

TIMEOUT=${TIMEOUT:-10}
HUB_DATABASE_IMAGE_NAME=${HUB_DATABASE_IMAGE_NAME:-postgres}

function fail() {
	message=$1
	exit_status=$2
	echo "${message}"
	exit ${exit_status}
}

function set_container_id() {
	container_id=( `docker ps -q -f label=com.blackducksoftware.hub.image=${HUB_DATABASE_IMAGE_NAME}` )
	return 0
}

# There should be one argument:  the dump file
[ $# -ne "2" ] && fail "Usage: $0 <database_name> </full/path/to/database.dump>" 1
database_name="$1"
dump_file="$2"

# Check that the database name is bds_hub, bds_hub_report, or bdio
[ "${database_name}" != "bds_hub" ] && [ "${database_name}" != "bds_hub_report" ] && [ "${database_name}" != "bdio" ] && fail "${database_name} must be bds_hub, bds_hub_report, or bdio." 2 

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

# Make sure that the database exists
sleep_count=0
until [ "$(docker exec -i -u postgres ${container_id} psql -A -t -c "select count(*) from pg_database where datname = '${database_name}'" postgres 2> /dev/null)" -eq 1 ] ; do
	sleep_count=$(( ${sleep_count} + 1 ))
	[ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database ${database_name} in container ${container_id} not ready after ${TIMEOUT} seconds." 8
	sleep 1
done

# Make sure that the database is empty
if [ "${database_name}" == "bds_hub" ]; 
then 
  table_count=`docker exec -i -u postgres ${container_id} psql -A -t -c "select count(*) from information_schema.tables where table_schema = 'st'" ${database_name}`
  [ "${table_count}" -ne 0 ] && fail "Database ${database_name} in container ${container_id} has already been populated" 9
else 
  table_count=`docker exec -i -u postgres ${container_id} psql -A -t -c "select count(*) from information_schema.tables where table_schema = 'public'" ${database_name}`
  [ "${table_count}" -ne 0 ] && fail "Database ${database_name} in container ${container_id} has already been populated" 9
fi

# Here we go...
echo Loading "${database_name}" dump from "${dump_file}" '...'
cat "${dump_file}" | docker exec -i -u postgres ${container_id} pg_restore -Fc --verbose --clean --if-exists -d ${database_name} || true

if [ "${database_name}" == "bds_hub" ]; 
then 
  # Clear the ETL jobs from bds_hub to bds_hub_report
  docker exec -i -u postgres ${container_id} psql -d ${database_name} << EOF 
UPDATE st.job_instances SET status='FAILED' where job_type='ReportingDatabaseTransferJob' and (status='SCHEDULED' or status='DISPATCHED' or status='RUNNING');
EOF
else
  # Grant permissions to blackduck_user for bds_hub_report and bdio
  docker exec -i -u postgres ${container_id} psql -d ${database_name} << EOF
GRANT CREATE, USAGE ON SCHEMA public TO blackduck_user;
EOF
fi
