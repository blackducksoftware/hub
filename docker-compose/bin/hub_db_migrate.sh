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
HUB_POSTGRES_VERSION=${HUB_POSTGRES_VERSION:-1.0.10}
HUB_DATABASE_IMAGE_NAME=${HUB_DATABASE_IMAGE_NAME:-postgres}
SCHEMA_NAME=${HUB_POSTGRES_SCHEMA:-st}
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

function determine_database_name_validity() {
    database=$1
  
    echo "Attempting to determine database name validity: ${database}."

    # Check that the database name is bds_hub, bds_hub_report, or bdio
    [ "${database}" != "bds_hub" ] && [ "${database}" != "bds_hub_report" ] && [ "${database}" != "bdio" ] && fail "${database_name} must be bds_hub, bds_hub_report, or bdio." 2

    echo "Determined database name validity: ${database}."
}

function determine_file_validity() {
    filepath=$1
  
    echo "Attempting to determine file validity [File: ${filepath}]."

    # Check that the dump file actually exists and is readable
    [ ! -f "${filepath}" ] && fail "${filepath} does not exist or is not a file" 2
    [ ! -r "${filepath}" ] && fail "${filepath} is not readable" 2

    echo "Determined file validity [File: ${filepath}]."
}

function determine_docker_path_validity() {
    echo "Attempting to determine Docker path validity."

    # Check that docker is on our path
    [ "$(type -p docker)" == "" ] && fail "docker not found on the search path" 3

    echo "Determined Docker path validity."
}

function determine_docker_daemon_validity() {
    echo "Attempting to determine Docker daemon validity."
    
    # Check that we can contact the docker daemon
    docker ps > /dev/null
    success=$?
    [ ${success} -ne 0 ] && fail "Could not contact docker daemon. Is DOCKER_HOST set correctly?" 4

    echo "Determined Docker daemon validity."
}

function determine_container_readiness() {
    echo "Attempting to determine Docker container readiness."

    # Find the database container ID(s); give the container a few seconds to start if necessary
    sleep_count=0
    until set_container_id && [ "${#container_id[*]}" -gt 0 ] ; do
        sleep_count=$(( ${sleep_count} + 1 ))
        [ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database container not ready after ${TIMEOUT} seconds." 5
        sleep 1
    done

    echo "Determined Docker container readiness."
}

function determine_singular_container() {
    echo "Attempting to determine singular Docker container."

    # Check that exactly one instance of the database container is up and running
    [ "${#container_id[*]}" -ne 1 ] && fail "${#container_id[*]} instances of the Black Duck database container are running." 6

    echo "Determined singular Docker container."
}

function determine_postgresql_readiness() {
    container=$1
   
    echo "Attempting to determine PostgreSQL readiness."

    # Make sure that postgres is ready
    sleep_count=0
    until docker exec -i -u postgres ${container} pg_isready -q ; do
        sleep_count=$(( ${sleep_count} + 1 ))
        [ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database server in container ${container} not ready after ${TIMEOUT} seconds." 7
        sleep 1
    done

    echo "Determined PostgreSQL readiness."
}

function determine_database_readiness() {
    container=$1
    database=$2

    echo "Attempting to determine database readiness [Container: ${container} | Database: ${database}]."

    # Determine if a specific database is ready.
    sleep_count=0
    until [ "$(docker exec -i -u postgres ${container} psql -A -t -c "select count(*) from pg_database where datname = '${database}'" postgres 2> /dev/null)" -eq 1 ] ; do
        sleep_count=$(( ${sleep_count} + 1 ))
        [ ${sleep_count} -gt ${TIMEOUT} ] && fail "Database ${database} in container ${container} not ready after ${TIMEOUT} seconds." 8
        sleep 1
    done

    echo "Database is ready [Container: ${container} | Database: ${database}]."
}

function determine_database_emptiness() {
    container=$1
    database=$2

    echo "Attempting to determine database emptiness [Container: ${container} | Database: ${database}]."

    # Make sure that the database is empty
    if [ "${database}" == "bds_hub" ];
    then 
        table_count=`docker exec -i -u postgres ${container} psql -A -t -c "select count(*) from information_schema.tables where table_schema = '${SCHEMA_NAME}'" ${database}`
        [ "${table_count}" -ne 0 ] && fail "Unable to migrate as database ${database} in container ${container} has already been populated" 9
    else
        table_count=`docker exec -i -u postgres ${container} psql -A -t -c "select count(*) from information_schema.tables where table_schema = 'public'" ${database}`
        [ "${table_count}" -ne 0 ] && fail "Unable to migrate as database ${database} in container ${container} has already been populated" 9
    fi

    echo "Determined database emptiness [Container: ${container} | Database: ${database}]."
}

function restore_globals() {
    container=$1
    sqlfile=$2

    echo "Attempting to restore globals [Container: ${container} | File: ${sqlfile}]."

    cat "${sqlfile}" | docker exec -i -u postgres ${container} psql -d postgres -A -t || true
    exitCode=$?
    [ ${exitCode} -ne 0 ] && fail "Unable to restore globals [Container: ${container} | File: ${sqlfile}]." 10 

    echo "Restored globals [Container: ${container} | File: ${sqlfile}]."
}

function restore_database() {
    container=$1
    database=$2
    dump=$3

    echo "Attempting to restore database [Container: ${container} | Database: ${database} | Dump: ${dump}]."

    cat "${dump}" | docker exec -i -u postgres ${container} pg_restore -Fc --verbose --clean --if-exists -d ${database} || true

    echo "Restored database [Container: ${container} | Database: ${database} | Dump: ${dump}]."
}

function cleanup_database() {
    container=$1
    database=$2

    if [ "${database}" == "bds_hub" ];
    then
        # Clear the ETL jobs from bds_hub to bds_hub_report
        docker exec -i -u postgres ${container} psql -d ${database} << EOF
UPDATE ${SCHEMA_NAME}.job_instances SET status='FAILED' where job_type='ReportingDatabaseTransferJob' and (status='SCHEDULED' or status='DISPATCHED' or status='RUNNING');
EOF
    else
        # Grant permissions to blackduck_user for bds_hub_report and bdio
        docker exec -i -u postgres ${container} psql -d ${database} << EOF
GRANT CREATE, USAGE ON SCHEMA public TO blackduck_user;
EOF
    fi
}

function validate_database() {
    container=$1
    database=$2

    determine_database_readiness ${container} ${database}
    determine_database_emptiness ${container} ${database}
}

function migrate_database() {
    container=$1
    database=$2
    dump=$3

    restore_database ${container} ${database} ${dump}
    cleanup_database ${container} ${database}
}

function manage_all_databases() {
    container=$1
    directorypath=$2

    echo "Attempting to manage all databases [Container: ${container} | Directory path: ${directorypath}]." 

    validate_database ${container} "bds_hub"
    validate_database ${container} "bds_hub_report"
    validate_database ${container} "bdio"

    restore_globals ${container} "${directorypath}/globals.sql"

    migrate_database ${container} "bds_hub" "${directorypath}/bds_hub.dump"
    migrate_database ${container} "bds_hub_report" "${directorypath}/bds_hub_report.dump"
    migrate_database ${container} "bdio" "${directorypath}/bdio.dump"

    echo "Managed all databases [Container: ${container} | Directory path: ${directorypath}]."
}

function manage_database() {
    container=$1
    database=$2
    dump=$3

    echo "Attempting to manage database [Container: ${container} | Database: ${database} | Dump: ${dump}]."

    validate_database ${container} ${database}
    migrate_database ${container} ${database} ${dump}

    echo "Managed database [Container: ${container} | Database: ${database} | Dump: ${dump}]."
}

# There are two usage options.
# 
# Single argument option - Restore all databases.
# Restore globals.dump, bds_hub.dump, bds_hub_report.dump, bdio.dump automatically.  Files must be named appropriately and in the same directory.
# $0 <database_dump_directory>
#
# Two argument option - Restore a specific database.
# Restore bds_hub, bds_hub_report, or bdio databases.
# $0 <database_name> <database_dump_file>
if [ $# -eq "1" ];
then
    # All databases.
    directory_path="$1"

    determine_file_validity "${directory_path}/globals.sql"
    determine_file_validity "${directory_path}/bds_hub.dump"
    determine_file_validity "${directory_path}/bds_hub_report.dump"
    determine_file_validity "${directory_path}/bdio.dump"

    determine_docker_path_validity
    determine_docker_daemon_validity
    determine_container_readiness
    determine_singular_container
    determine_postgresql_readiness ${container_id}

    manage_all_databases ${container_id} ${directory_path}
elif [ $# -eq "2" ];
then 
    # Database and a database dump file.
    database_name="$1"
    dump_file="$2"

    determine_database_name_validity ${database_name}
    
    determine_file_validity ${dump_file}
    determine_docker_path_validity
    determine_docker_daemon_validity
    determine_container_readiness
    determine_singular_container
    determine_postgresql_readiness ${container_id}

    manage_database ${container_id} ${database_name} ${dump_file}
else
    # Invalid number of arguments.
    fail "Usage $0 </local/directory/path>" 1
fi

