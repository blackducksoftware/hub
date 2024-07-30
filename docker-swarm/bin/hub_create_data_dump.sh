#!/bin/bash

# Prerequisites:
#  1. The database container is running.
#  2. The database container has been properly initialized.

HUB_DATABASE_IMAGE_NAME=${HUB_DATABASE_IMAGE_NAME:-postgres}
HUB_POSTGRES_VERSION=${HUB_POSTGRES_VERSION:-14-1.25}
HUB_VERSION=${HUB_VERSION:-2024.7.0}
OPT_FORCE=
OPT_LIVE_SYSTEM=
OPT_MAX_CPU=${MAX_CPU:-1}
OPT_NO_STORAGE=${NO_STORAGE:-}
TIMEOUT=${TIMEOUT:-10}

database_name=
local_destination=
typeset -a container_id
typeset -a storage_id

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
    $(basename "$0") [ <option>* ] [ <db-name> ] <dest>

Supported options are:
    --force               Overwrite existing files in the destination
    --no-storage          Do not attempt to backup the storage service
    --max-cpu <n>         Number of parallel database jobs (see below!)
    --live-system         Backup even if not in dbMigrate mode.

This script tries to backup the running Black Duck database to a local
directory.  The database must be running in a local docker container.

Unless '--no-storage' is specified this command will also attempt to
backup any uploads to the storage system that are kept in local files.
The storage service must be running in a local docker container to do
that.

When '--max-cpu' (or '-j') is larger than 1 database dumps will be
done in parallel, which requires sufficient disk space in the database
container /tmp partition to store the entire dump temporarily,
typically around 10% of the size of the full database. By default
dumps are streamed directly to the local destination.

Unless '--live-system' is supplied this script will refuse to run if
system appears to be live, rather than in dbMigrate mode.  Backing up
a live system is discouraged; it will impact performance and might not
produce a fully self-consistent dump.

Command line options take precedence over environment variables.
Recognized environment variables:
    HUB_DATABASE_IMAGE_NAME  Expected postgres image name [$HUB_DATABASE_IMAGE_NAME]
    HUB_POSTGRES_VERSION     Expected postgres image version [$HUB_POSTGRES_VERSION]
    HUB_VERSION              Expected storage image version [$HUB_VERSION]
    MAX_CPU                  Number of parallel database threads to use [$OPT_MAX_CPU]
    NO_STORAGE               Skip storage service backup when non-empty [$OPT_NO_STORAGE]
    TIMEOUT                  Seconds to wait for postgresql startup [$TIMEOUT]
END
    exit 1
}

function process_args() {
    # Parse arguments.
    local arg_1=
    local arg_2=
    while [[ $# -gt 0 ]]; do
        case "$1" in
            '--no-storage' )
                OPT_NO_STORAGE=1 ;;
            '--max-cpu' | '-j' )
                shift; OPT_MAX_CPU="$1" ;;
            '--help' | '-h' )
                usage ;;
            '--force' | '-f' )
                OPT_FORCE=1 ;;
            '--live-system' )
                OPT_LIVE_SYSTEM=1 ;;
            *)
                if [[ -z "${arg_1}" ]]; then
                    arg_1="$1"
                elif [[ -z "${arg_2}" ]]; then
                    arg_2="$1"
                else
                    fail 12 "Unexpected argument '$1'"
                fi ;;
        esac
        shift       
    done

    # Validate arguments
    [[ -n "$arg_1" ]] || usage
    if [[ -z "$arg_2" ]]; then
        database_name="bds_hub"
        local_destination="$arg_1"
    else
        database_name="$arg_1"
        local_destination="$arg_2"
    fi

    [[ -d "$local_destination" ]] || fail 11 "Local destination must exist and be a directory: ${local_destination}"
    [[ -n "$OPT_FORCE" ]] || [[ -z "$(ls "$local_destination/")" ]] || fail 13 "Local destination directory is not empty: ${local_destination}"
    [[ "${database_name}" == "bds_hub" ]] || fail 10 "Database name must be bds_hub, but ${database_name} was specified."
}

function set_container_id() {
    container_id=( $(docker ps -q -f "label=com.blackducksoftware.hub.version=${HUB_POSTGRES_VERSION}" \
                                  -f "label=com.blackducksoftware.hub.image=${HUB_DATABASE_IMAGE_NAME}") )
    storage_id=( $(docker ps -q -f "volume=/tmp/uploads") $(docker ps -q -f "volume=/opt/blackduck/hub/uploads") )
    return 0
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
    until [ "$(docker exec "${container}" psql -U postgres -A -t -c "select count(*) from pg_database where datname = '${database}'" postgres 2> /dev/null)" -eq 1 ] ; do
         sleep_count=$(( sleep_count + 1 ))
         [[ ${sleep_count} -le "${TIMEOUT}" ]] || fail 7 "Database ${database} in container ${container} not ready after ${TIMEOUT} seconds."
         sleep 1
    done

    echo "Database is ready [Container: ${container} | Database: ${database}]."
    return 0
}

function create_globals() {
    local container=$1
    local host_path=$2

    echo "Attempting to create globals SQL file [Container: ${container} | Host path: ${host_path}]."
    
    docker exec "${container}" pg_dumpall -U blackduck -g > "${host_path}/globals.sql" || \
        fail 10 "Unable to create globals SQL file [Container: ${container} | Host path: ${host_path}]"

    echo "Created globals SQL file [Container: ${container} | Host path: ${host_path}]."
}

function create_dump() {
    local container=$1
    local host_path=$2
    local database=$3

    echo "Attempting to create database dump [Container: ${container} | Host path: ${host_path} | Database: ${database}]."
    
    if [ "${OPT_MAX_CPU}" -gt 1 ]; then
        docker exec "${container}" pg_dump -U blackduck -Fd "-j${OPT_MAX_CPU}" "${database}" -f "/tmp/${database}.dump" || \
            fail 8 "Unable to create database dump [Container: ${container} | Host path: ${host_path} | Database: ${database}]"

        docker cp "${container}:/tmp/${database}.dump" "${host_path}/." || \
            fail 8 "Unable to copy database dump [Container: ${container} | Host path: ${host_path} | Database: ${database}]"

        docker exec "${container}" rm -rf "/tmp/${database}.dump" || \
            fail 8 "Unable to cleanup database dump [Container: ${container} | Host path: ${host_path} | Database: ${database}]"
    else
        docker exec "${container}" pg_dump -U blackduck -Fc "${database}" > "${host_path}/${database}.dump" || \
        fail 8 "Unable to create database dump [Container: ${container} | Host path: ${host_path} | Database: ${database}]"
    fi

    echo "Created database dump [Container: ${container} | Host path: ${host_path} | Database: ${database}]."
}

function manage_globals() {
    local container=$1
    local local_path=$2

    echo "Attempting to manage globals [Container: ${container} | Path: ${local_path}]."

    create_globals "${container}" "${local_path}"

    echo "Managed globals [Container: ${container} | Path: ${local_path}]."
}

# Returns
#   0 - database was dumped
#   1 - database was skipped
function manage_database() {
    local container=$1
    local database=$2
    local local_path=$3

    echo "Attempting to manage database [Container: ${container} | Database: ${database} | Path: ${local_path}]."

    if determine_database_readiness "${container}" "${database}" ; then
        create_dump "${container}" "${local_path}" "${database}"
        echo "Managed database [Container: ${container} | Database: ${database} | Path: ${local_path}]."
        return 0
    else
        echo "Skipped database [Container: ${container} | Database: ${database} | Path: ${local_path}]."
        return 1
    fi
}

function manage_storage() {
    local id="$1"
    local mnt="$2"
    local dir="$3"

    if [[ -n $(docker exec "$id" ls "$mnt/$dir/" 2>/dev/null) ]]; then
        echo "Attempting to backup storage [Container: $id | Mount: $mnt | Volume: $dir]."
        docker exec "$id" tar czf - -C "$mnt/$dir" . > "$local_absolute_path/$dir.tgz"
    fi
}

# --------------------------------------------------------------------------------

process_args "$@"

# Check that docker is on our path
[[ -n "$(type -p docker)" ]] || fail 2 "docker not found on the search path"

# Check that we can contact the docker daemon
docker ps > /dev/null || fail 3 "Could not contact docker daemon. Is DOCKER_HOST set correctly?"

# Find the database container ID(s); give the container a few seconds to start if necessary
sleep_count=0
until set_container_id && [ "${#container_id[*]}" -gt 0 ] ; do
    sleep_count=$(( sleep_count + 1 ))
    [[ ${sleep_count} -le "${TIMEOUT}" ]] || fail 4 "No ${HUB_DATABASE_IMAGE_NAME} ${HUB_POSTGRES_VERSION} container was ready after ${TIMEOUT} seconds."
    sleep 1
done

# Check that exactly one instance of the database container is up and running
[[ "${#container_id[*]}" -eq 1 ]] || fail 5 "${#container_id[*]} instances of the Black Duck database container are running."

# Make sure that postgres is ready
sleep_count=0
until docker exec "${container_id[0]}" pg_isready -U postgres -q ; do
    sleep_count=$(( sleep_count + 1 ))
    [[ ${sleep_count} -le "${TIMEOUT}" ]] || fail 6 "Database server in container ${container_id[0]} not ready after ${TIMEOUT} seconds."
    sleep 1
done

# Check that we're not accidentally trying to dump a live system.
if [[ -n "$(docker ps -q -f 'label=com.blackducksoftware.hub.image=webserver')" ]] && [[ -z "${OPT_LIVE_SYSTEM}" ]]; then
    echo "* This appears to be a live system -- re-invoke with '--live-system' to proceed anyway." 1>&2
    exit 1
fi

# Create an absolute path to copy to, adds support for symbolic links
if [ ! -d "$local_destination" ]; then
    cd "$(dirname "$local_destination")" || exit 1
    base_file=$(basename "$local_destination")
    symlink_count=0
    while [ -L "$base_file" ]; do
        (( symlink_count++ ))
        if [ "$symlink_count" -gt 100 ]; then
            fail 1 "MAXSYMLINK level reached."
        fi
        base_file=$(readlink "$base_file")
        cd "$(dirname "$base_file")" || exit 1
        base_file=$(basename "$base_file")
    done
    present_dir=$(pwd -P)
    local_absolute_path="$present_dir/$base_file"
else
    local_absolute_path="${local_destination}"
fi

# Manage all databases
echo "Attempting to manage all databases."
manage_globals "${container_id[0]}" "${local_absolute_path}"
manage_database "${container_id[0]}" "bds_hub" "${local_absolute_path}"
echo "Successfully created all database files."

# Dump all local storage service uploads
if [[ -z "$OPT_NO_STORAGE" ]]; then
    echo
    echo "Attempting to save storage service file provider uploads."

    # Backup each directory separately
    for dir in $(docker exec "${storage_id[0]}" ls /tmp/ | grep -F uploads); do
        manage_storage "${storage_id[0]}" "/tmp" "$dir"
    done
    for dir in $(docker exec "${storage_id[0]}" ls /opt/blackduck/hub/ | grep -F uploads); do
        manage_storage "${storage_id[0]}" "/opt/blackduck/hub" "$dir"
    done
fi
