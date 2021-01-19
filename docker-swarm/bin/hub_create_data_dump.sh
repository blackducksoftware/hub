#!/bin/bash

# Prerequisites:
#  1. The database container is running.
#  2. The database container has been properly initialized.

set -e

TIMEOUT=${TIMEOUT:-10}
HUB_POSTGRES_VERSION=${HUB_POSTGRES_VERSION:-1.0.16}
HUB_DATABASE_IMAGE_NAME=${HUB_DATABASE_IMAGE_NAME:-postgres}

database_name=""
local_destination=""

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

function determine_database_readiness() {
    container=$1
    database=$2

    echo "Attempting to determine database readiness [Container: ${container} | Database: ${database}]."

    # Determine if a specific database is ready.
    sleep_count=0
    until [ "$(docker exec -i -u postgres ${container} psql -A -t -c "select count(*) from pg_database where datname = '${database}'" postgres 2> /dev/null)" -eq 1 ] ; do
         sleep_count=$(( ${sleep_count} + 1 ))
         [ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database ${database} in container ${container} not ready after ${TIMEOUT} seconds." 7
         sleep 1
    done

    echo "Database is ready [Container: ${container} | Database: ${database}]."
}

function create_globals() {
    container=$1
    host_path=$2

    echo "Attempting to create globals SQL file [Container: ${container} | Host path: ${host_path}]."
    
    docker exec -i ${container} pg_dumpall -U blackduck -g > ${host_path}/globals.sql
    exitCode=$?
    [ ${exitCode} -ne 0 ] && fail "Unable to create globals SQL file [Container: ${container} | Host path: ${host_path}]" 10 

    echo "Created globals SQL file [Container: ${container} | Host path: ${host_path}]."
}

function create_dump() {
    container=$1
    host_path=$2
    database=$3

    echo "Attempting to create database dump [Container: ${container} | Host path: ${host_path} | Database: ${database}]."
    
    docker exec -i ${container} pg_dump -U blackduck -Fc ${database} > ${host_path}/${database}.dump
    exitCode=$?
    [ ${exitCode} -ne 0 ] && fail "Unable to create database dump [Container: ${container} | Host path: ${host_path} | Database: ${database}]" 8

    echo "Created database dump [Container: ${container} | Host path: ${host_path} | Database: ${database}]."
}

function manage_all_databases() {
    container=$1
    local_path=$2

    echo "Attempting to manage all databases [Container: ${container} | Path: ${local_path}]."

    manage_globals ${container} ${local_path}
    manage_database ${container} "bds_hub" ${local_path}
    manage_database ${container} "bds_hub_report" ${local_path}

    echo "Managed all databases [Container: ${container} | Path: ${local_path}]."
}

function manage_globals() {
    container=$1
    local_path=$2

    echo "Attempting to manage globals [Container: ${container} | Path: ${local_path}]."

    create_globals ${container} ${local_path}

    echo "Managed globals [Container: ${container} | Path: ${local_path}]."
}

function manage_database() {
    container=$1
    database=$2
    local_path=$3

    echo "Attempting to manage database [Container: ${container} | Database: ${database} | Path: ${local_path}]."

    determine_database_readiness ${container} ${database}
    create_dump ${container} ${local_path} ${database}

    echo "Managed database [Container: ${container} | Database: ${database} | Path: ${local_path}]."
}

# There should be two arguments: database name and destination of the path with the name of the dump file.
# Previously, if one argument was supplied, the script assumed the target database is 'bds_hub' for backwards-compatibility purposes.  However, to support 
# a simpler management structure for users, this was deprecated and replaced with the default behavior being management of all databases to enable 
# a reduction of manual user steps.
if [ $# -eq "1" ];
then 
    database_name="all"
    local_destination="$1"
elif [ $# -eq "2" ];
then
    database_name="$1"
    local_destination="$2"
 
    # Check that the database name is bds_hub, bds_hub_report
    [ "${database_name}" != "bds_hub" ] && [ "${database_name}" != "bds_hub_report" ] && fail "${database_name} must be bds_hub, bds_hub_report." 10
else
    fail "Usage: $0 </local/directory/path>" 1
fi

# Verify the local destination is a present directory.
[ ! -d "${local_destination}" ] && fail "Local destination must exist and be a directory: ${local_destination}" 11

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
until docker exec -i -u postgres ${container_id} pg_isready -q ; do
    sleep_count=$(( ${sleep_count} + 1 ))
    [ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database server in container ${container_id} not ready after ${TIMEOUT} seconds." 6
    sleep 1
done

# Create an absolute path to copy to, adds support for symbolic links
if [ ! -d "$local_destination" ]; then
    cd `dirname $local_destination`
    base_file=`basename $local_destination`
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
    local_absolute_path=${local_destination}
fi

# Database existence checks
if [ "${database_name}" == "all" ];
then
    # Manage all databases
    echo "Attempting to manage all databases."
    
    manage_all_databases ${container_id} ${local_absolute_path}

    echo "Successfully created all database files."
    echo "Globals SQL file: ${local_absolute_path}/globals.sql"
    echo "bds_hub database dump file: ${local_absolute_path}/bds_hub.dump"
    echo "bds_hub_report database dump file: ${local_absolute_path}/bds_hub_report.dump"
else 
    # Manage a specific database
    echo "Attempting to manage a specific database: ${database_name}."

    manage_database ${container_id} ${database_name} ${local_absolute_path}

    echo "Successfully created database dump file: ${local_absolute_path}/${database_name}.dump"
fi

