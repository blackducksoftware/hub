#!/bin/bash

# Prerequisites:
#  1. The database container is running.
#  2. The database container has been properly initialized.
#  3. For bds_hub, the "st" schema is present but empty (i.e., the schema has not been migrated).  
#  4. docker is on the search path.
#  5. The user has suitable privileges for running docker.
#  6. The database container can be identified in the output of a locally run "docker ps".
#  7. A custom-format dump is locally accessible.
#  8. "docker exec -i -u postgres ..." works.

# Exit immediately if any simple command returns non-zero status
set -o errexit

HUB_DATABASE_IMAGE_NAME=${HUB_DATABASE_IMAGE_NAME:-postgres}
HUB_POSTGRES_VERSION=${HUB_POSTGRES_VERSION:-14-1.25}
OPT_MAX_CPU=${MAX_CPU:-1}
OPT_NO_DATABASE=${NO_DATABASE:-}
OPT_NO_STORAGE=${NO_STORAGE:-}
SCHEMA_NAME=${HUB_POSTGRES_SCHEMA:-st}
TIMEOUT=${TIMEOUT:-10}

directory_path=
database_name=
dump_file=
mount=
tar_file=
typeset -a container_id

function fail() {
    local -r code=$1
    shift

    for line in "$@"; do
        [[ -z "$line" ]] || echo "$line" >&2
    done
    exit "$code"
}

function usage() {
    # shellcheck disable=SC2155 # Ignore sub-command exit status
    cat <<END
Usage:
    $(basename "$0") [ <option>* ] ( <dir-path> | <db-name> <dumpfile> | <mount> <tarfile> )

Supported options are:
    --no-storage          Do not attempt to restore storage service backups
    --max-cpu <n>         Number of parallel database jobs (see below!)

This script tries to restore a Black Duck database and storage service
backup.  The database must be running in a local docker container.  If
no database name is given all information will be restored, including
global settings and storage service file provider backups.  If a
database name is given only that database will be restored.

When '--max-cpu' (or '-j') is larger than 1 database or when dumps
were created in parallel there must be sufficient disk space in the
database container /tmp partition to store the entire dump
temporarily. By default dumps are streamed directly to the local
destination and restored single-threaded.

To restore either a single storage service file provider backup or all
backups the storage service must be running in a local docker
container.  YOU MUST RESTART BLACKDUCK AFTER RESTORING UPLOADED FILES.

Command line options take precedence over environment variables.
Recognized environment variables:
    HUB_DATABASE_IMAGE_NAME  Expected postgres image name [$HUB_DATABASE_IMAGE_NAME]
    HUB_POSTGRES_VERSION     Expected postgres image version [$HUB_POSTGRES_VERSION]
    MAX_CPU                  Number of parallel database threads to use [$OPT_MAX_CPU]
    NO_STORAGE               Skip storage service restore when non-empty [$OPT_NO_STORAGE]
    TIMEOUT                  Seconds to wait for postgresql startup [$TIMEOUT]
END
    exit 1
}

function process_args() {
    # Parse arguments.
    while [[ $# -gt 0 ]]; do
        case "$1" in
            '--no-storage' )
                OPT_NO_STORAGE=1 ;;
            '--max-cpu' | '-j' )
                shift; OPT_MAX_CPU="$1" ;;
            '--help' | '-h' )
                usage ;;
            *)
                if [[ -z "${arg_1}" ]]; then
                    arg_1="$1"
                elif [[ -z "${arg_2}" ]]; then
                    arg_2="$1"
                else
                    fail 11 "Unexpected argument '$1'"
                fi ;;
        esac
        shift       
    done

    # Validate arguments
    [[ -n "$arg_1" ]] || usage
    if [[ -z "$arg_2" ]]; then
        # Restore everything
        directory_path="$arg_1"
        [[ -d "$directory_path" ]] || fail 12 "Local dump directory not found or not a directory: ${directory_path}"
    elif [[ "$arg_1" = bds_* ]]; then
        # Restore a database.  bds_hub is the only possibility.
        database_name="$arg_1"
        dump_file="$arg_2"
        [[ -e "$dump_file" ]] || fail 13 "Dump file or directory not found: ${dump_file}"
        [[ "${database_name}" == "bds_hub" ]] || fail 14 "Database name must be bds_hub, but ${database_name} was specified."
    elif [[ "$arg_1" = uploads* ]]; then
        # Restore a file storage provider
        mount="$arg_1"
        tar_file="$arg_2"
        [[ -f "$tar_file" ]] || fail 15 "Tar file not found or not a file: ${tar_file}"
    fi
}

function set_container_id() {
    container_id=( $(docker ps -q -f label=com.blackducksoftware.hub.version="${HUB_POSTGRES_VERSION}" \
                                  -f label=com.blackducksoftware.hub.image="${HUB_DATABASE_IMAGE_NAME}") )
    return 0
}

function determine_database_name_validity() {
    database=$1
  
    echo "Attempting to determine database name validity: ${database}."

    # Check that the database name is bds_hub
    [[ "${database}" == "bds_hub" ]] || fail 2 "Database name must be bds_hub."

    echo "Determined database name validity: ${database}."
}

function determine_file_validity() {
    local filepath=$1
  
    echo "Attempting to determine file validity [File: ${filepath}]."

    # Check that the dump file actually exists and is readable
    [[ -r "${filepath}" ]] || fail 2 "${filepath} is not readable"

    echo "Determined file validity [File: ${filepath}]."
}

function determine_docker_path_validity() {
    echo "Attempting to determine Docker path validity."

    # Check that docker is on our path
    [[ -n "$(type -p docker)" ]] || fail 3 "docker not found on the search path"

    echo "Determined Docker path validity."
}

function determine_docker_daemon_validity() {
    echo "Attempting to determine Docker daemon validity."
    
    # Check that we can contact the docker daemon
    docker ps > /dev/null || fail 4 "Could not contact docker daemon. Is DOCKER_HOST set correctly?"

    echo "Determined Docker daemon validity."
}

function determine_container_readiness() {
    echo "Attempting to determine Docker container readiness."

    # Find the database container ID(s); give the container a few seconds to start if necessary
    local -i sleep_count=0
    until set_container_id && [ "${#container_id[*]}" -gt 0 ] ; do
        sleep_count=$(( sleep_count + 1 ))
        [[ ${sleep_count} -le "${TIMEOUT}" ]] || fail 5 "Database container not ready after ${TIMEOUT} seconds."
        sleep 1
    done

    echo "Determined Docker container readiness."
}

function determine_singular_container() {
    echo "Attempting to determine singular Docker container."

    # Check that exactly one instance of the database container is up and running
    [[ "${#container_id[*]}" -eq 1 ]] || fail 6 "${#container_id[*]} instances of the Black Duck database container are running."

    echo "Determined singular Docker container."
}

function determine_postgresql_readiness() {
    local container=$1
   
    echo "Attempting to determine PostgreSQL readiness."

    # Make sure that postgres is ready
    local -i sleep_count=0
    until docker exec -i "${container}" pg_isready -U postgres -q ; do
        sleep_count=$(( sleep_count + 1 ))
        [[ ${sleep_count} -le "${TIMEOUT}" ]] || fail 7 "Database server in container ${container} not ready after ${TIMEOUT} seconds."
        sleep 1
    done

    echo "Determined PostgreSQL readiness."
}

# Returns
#   0 - database exists
#   7 - database doesn't exist
function determine_database_readiness() {
    local container=$1
    local database=$2

    echo "Attempting to determine database readiness [Container: ${container} | Database: ${database}]."

    # Determine if a specific database is ready.
    local -i sleep_count=0
    until [ "$(docker exec -i "${container}" psql -U postgres -A -t -c "select count(*) from pg_database where datname = '${database}'" postgres 2> /dev/null)" -eq 1 ] ; do
         sleep_count=$(( sleep_count + 1 ))
         if [ ${sleep_count} -gt "${TIMEOUT}" ] ; then
             fail 8 "Database ${database} in container ${container} not ready after ${TIMEOUT} seconds."
         fi
         sleep 1
    done

    echo "Database is ready [Container: ${container} | Database: ${database}]."
    return 0
}

function determine_database_emptiness() {
    local container=$1
    local database=$2

    echo "Attempting to determine database emptiness [Container: ${container} | Database: ${database}]."

    # Make sure that the database is empty
    local table_count
    if [ "${database}" == "bds_hub" ]; then 
        table_count=$(docker exec -i "${container}" psql -U postgres -A -t -c "select count(*) from information_schema.tables where table_schema = '${SCHEMA_NAME}'" "${database}")
    else
        table_count=$(docker exec -i "${container}" psql -U postgres -A -t -c "select count(*) from information_schema.tables where table_schema = 'public'" "${database}")
    fi
    [[ "${table_count}" -eq 0 ]] || fail 9 "Unable to migrate as database ${database} in container ${container} has already been populated"

    echo "Determined database emptiness [Container: ${container} | Database: ${database}]."
}

function determine_dbmigrate_mode() {
    # Check that we're not trying to restore to a live system.
    if [[ -n "$(docker ps -q -f 'label=com.blackducksoftware.hub.image=webserver')" ]] && [[ -z "${OPT_LIVE_SYSTEM}" ]]; then
        echo "* This appears to be a live system -- cannot proceed." 1>&2
        exit 1
    fi
}

function restore_globals() {
    local container=$1
    local sqlfile=$2

    echo "Attempting to restore globals [Container: ${container} | File: ${sqlfile}]."

    docker exec -i "${container}" psql -U postgres -d postgres -A -t < "$sqlfile" || \
        fail 10 "Unable to restore globals [Container: ${container} | File: ${sqlfile}]."

    echo "Restored globals [Container: ${container} | File: ${sqlfile}]."
}

function restore_database() {
    local container=$1
    local database=$2
    local dump=$3

    echo "Attempting to restore database [Container: ${container} | Database: ${database} | Dump: ${dump}]."

    if [ -d "${dump}" ]; then
        # Restoring directory format dumps requires a copy inside the container.
        docker cp "${dump}" "${container}:/tmp/${database}"
        docker exec -u 0 "${container}" chmod -R a+rx "/tmp/${database}"
        docker exec -i "${container}" pg_restore -U blackduck -Fd "-j${OPT_MAX_CPU}" --verbose --clean --if-exists -d "${database}" "/tmp/${database}" || true
        docker exec -u 0 "${container}" rm -rf "/tmp/${database}"
    elif [ "${OPT_MAX_CPU}" -gt 1 ]; then
        # Parallel restore of file format dumps requires a copy inside the container.
        docker cp "${dump}" "${container}:/tmp/${database}"
        docker exec -u 0 "${container}" chmod -R a+rx "/tmp/${database}"
        docker exec "${container}" pg_restore -U blackduck -Fc "-j${OPT_MAX_CPU}" --verbose --clean --if-exists -d "${database}" "/tmp/${database}" || true
        docker exec -u 0 "${container}" rm -rf "/tmp/${database}"
    else
        # Single-threaded restore of a dump file can be streamed.
        docker exec -i "${container}" pg_restore -U blackduck -Fc --verbose --clean --if-exists -d "${database}" < "$dump" || true
    fi

    echo "Restored database [Container: ${container} | Database: ${database} | Dump: ${dump}]."
}

function migrate_database() {
    local container=$1
    local database=$2
    local dump=$3

    restore_database "${container}" "${database}" "${dump}"
}

function manage_database() {
    local container=$1
    local database=$2
    local dump=$3

    echo "Attempting to manage database [Container: ${container} | Database: ${database} | Dump: ${dump}]."

    if determine_database_readiness "${container}" "${database}" ; then
        determine_file_validity "${dump}"
        determine_database_emptiness "${container}" "${database}"
        migrate_database "${container}" "${database}" "${dump}"
        echo "Managed database [Container: ${container} | Database: ${database} | Dump: ${dump}]."
    else
        echo "Skipped database [Container: ${container} | Database: ${database} | Dump: ${dump}]."
    fi
}

function manage_storage_provider() {
    local id="$1"
    local dir="$2"
    local dump="$3"

    echo "Attempting to restore uploaded files [Container: $id | Mount: $dir | Dump: $dump]."

    # Check that the desired target is a mount point.
    docker exec "$id" ls -d "/tmp/$dir" >/dev/null 2>&1 || \
        fail 30 "$dir is not a mount point -- check the provider configurations."

    # Check that the desired target directory is empty.
    [[ -z "$(docker exec "$id" ls "/tmp/$dir/" 2>&1)" ]] || \
        fail 31 "$dir is not empty -- check the provider configurations."

    docker exec -u 0 -i "$id" tar xz -C "/tmp/$dir" -f - < "$dump"

    echo "Restored uploaded files [Container: $id | Mount: $dir | Dump: $dump]."
}

# --------------------------------------------------------------------------------

process_args "$@"

if [[ -n "$directory_path" ]]; then
    # Restore everything.
    determine_docker_path_validity
    determine_docker_daemon_validity

    if [[ -z "$OPT_NO_DATABASE" ]]; then
        determine_container_readiness
        determine_singular_container
        determine_postgresql_readiness "${container_id[0]}"
        determine_dbmigrate_mode

        echo "Attempting to manage all databases [Container: ${container_id[0]} | Directory path: ${directory_path}]." 
        determine_file_validity "${directory_path}/globals.sql"
        restore_globals "${container_id[0]}" "${directory_path}/globals.sql"

        manage_database "${container_id[0]}" "bds_hub" "${directory_path}/bds_hub.dump"
        echo "Managed all databases [Container: ${container_id[0]} | Directory path: ${directory_path}]."
    fi

    if [[ -z "$OPT_NO_STORAGE" ]]; then
        # We cannot start the real storage service because it needs database tables
        # to start, so temporarily mount the storage volumes elsewhere.
        echo
        echo "Attempting to restore all storage service file provider backups."
        if [[ "${#container_id[*]}" -eq 0 ]]; then
            determine_container_readiness
            determine_singular_container
            determine_dbmigrate_mode
        fi
        for tar in "${directory_path}"/upload*.tgz; do
            manage_storage_provider "${container_id[0]}" "$(basename "$tar" .tgz)" "$tar"
        done
        echo "Managed all storage service backups."
    fi

elif [[ -n "$database_name" ]] && [[ -n "$dump_file" ]]; then
    # Restore a specific database.
    determine_database_name_validity "${database_name}"
    
    determine_docker_path_validity
    determine_docker_daemon_validity
    determine_container_readiness
    determine_singular_container
    determine_postgresql_readiness "${container_id[0]}"
    determine_dbmigrate_mode

    manage_database "${container_id[0]}" "${database_name}" "${dump_file}"

elif [[ -n "$mount" ]] && [[ -n "$tar_file" ]]; then
    # Restore a specific storage service file provider.
    if [[ "${#container_id[*]}" -eq 0 ]]; then
        determine_container_readiness
        determine_singular_container
        determine_dbmigrate_mode
    fi
    manage_storage_provider "${container_id[0]}" "$mount" "$tar_file"

else
    # Invalid number of arguments.
    usage
fi
