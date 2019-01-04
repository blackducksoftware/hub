#!/bin/bash

# Prerequisites:
#  1. The database container is running.
#  2. The database container has been properly initialized.

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


# There should be two arguments: database name and destination of the path with the name of the dump file.
# If one argument is supplied, for backwards compatibility, assume database name is 'bds_hub'
if [ $# -eq "1" ];
then 
  database_name="bds_hub"
  local_dest_dump_file="$1"
elif [ $# -eq "2" ];
then
  database_name="$1"
  local_dest_dump_file="$2"
else
  fail "Usage: $0 <database_name> </local/full/path/to/dumpfile.dump>" 1
fi

# Check that the database name is bds_hub, bds_hub_report, or bdio
[ "${database_name}" != "bds_hub" ] && [ "${database_name}" != "bds_hub_report" ] && [ "${database_name}" != "bdio" ] && fail "${database_name} must be bds_hub, bds_hub_report, or bdio." 10

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
until docker exec -u postgres ${container_id} pg_isready -q ; do
	sleep_count=$(( ${sleep_count} + 1 ))
	[ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database server in container ${container_id} not ready after ${TIMEOUT} seconds." 6
	sleep 1
done

# Make sure that the database exists
sleep_count=0
until [ "$(docker exec -u postgres ${container_id} psql -A -t -c "select count(*) from pg_database where datname = '${database_name}'" postgres 2> /dev/null)" -eq 1 ] ; do
	sleep_count=$(( ${sleep_count} + 1 ))
	[ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database ${database_name} in container ${container_id} not ready after ${TIMEOUT} seconds." 7
	sleep 1
done

# Here we go...
echo Creating a dump from the container "${container_id}" '...'
docker exec ${container_id} pg_dump -U blackduck -Fc -f /tmp/${database_name}.dump ${database_name}
exitCode=$? 
[ ${exitCode} -ne 0 ] && fail "Cannot create the dump file from the container [Container Id: ${container_id}]" 8

# Create an absolute path to copy to, adds support for symbolic links
if [ ! -d "$local_dest_dump_file" ]; then
	cd `dirname $local_dest_dump_file`
	base_file=`basename $local_dest_dump_file`
	symlink_count=0
	while [ -L "$base_file" ]; do
		(( symlink_count++ ))
		if [ "$symlink_count" -gt 100 ]; then
			fail "MAXSYMLINK level reached." 1
		fi
		base_file=`readlink $base_file`
		cd `dirname $base_file`
		base_file=`basename $base_file`
	done
    present_dir=`pwd -P`
    local_absolute_path=$present_dir/$base_file
else
	local_absolute_path=${local_dest_dump_file}
fi

docker cp ${container_id}:/tmp/${database_name}.dump "${local_absolute_path}"
exitCode=$?
[ ${exitCode} -ne 0 ] && fail "Was not able to copy the dump file over [Container Id: ${container_id}]" 9

# After copy, remove the dump from the container.
docker exec ${container_id} rm /tmp/${database_name}.dump

echo Success with creating the dump and copying over to "[Destination Dir: $(dirname ${local_dest_dump_file})]" from the container: "[Container Id: ${container_id}]"
