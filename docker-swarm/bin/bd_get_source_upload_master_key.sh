#!/bin/bash

# Prerequisites:
#  1. The upload cache container is running.
#  2. The upload cache container has been properly initialized.

set -e

TIMEOUT=${TIMEOUT:-10}
UPLOAD_CACHE_IMAGE_NAME=${UPLOAD_CACHE_IMAGE_NAME:-uploadcache}
MASTER_KEY_FILE_NAME=${MASTER_KEY_FILE_NAME:-UPLOAD_MASTER_KEY}


local_destination=""
seal_key=""

function fail() {
    message=$1
    exit_status=$2

    echo "${message}"
    exit ${exit_status}
}

function isDockerAvailable(){
    # Check that docker is on our path
    [ "$(type -p docker)" == "" ] && fail "docker not found on the search path" 3

    # Check that we can contact the docker daemon
    docker ps > /dev/null
    success=$?
    [ ${success} -ne 0 ] && fail "Could not contact docker daemon. Is DOCKER_HOST set correctly?" 4
    return 0
}

function get_container_id() {
    container_id=( `docker ps -q -f label=com.blackducksoftware.hub.image=${UPLOAD_CACHE_IMAGE_NAME}` )
    echo ${container_id}
    return 0
}

function get_master_key() {
    container=$1
    host_path=$2
    seal_key=$3

    echo "Attempting to retrieve the master key [Container: ${container} | Host path: ${host_path} ]."

    docker exec -i ${container} \
    curl -f --header "X-SEAL-KEY: $seal_key" \
                           https://uploadcache:9444/api/internal/master-key \
                           --cert /opt/blackduck/hub/blackduck-upload-cache/security/blackduck-upload-cache-server.crt \
                           --key /opt/blackduck/hub/blackduck-upload-cache/security/blackduck-upload-cache-server.key \
                           --cacert /opt/blackduck/hub/blackduck-upload-cache/security/root.crt \
                           > ${host_path}/${MASTER_KEY_FILE_NAME}

    exitCode=$?
    [ ${exitCode} -ne 0 ] && fail "Unable to get the master key [Container: ${container} | Host path: ${host_path}]"
    echo "Successfully imported master key of upload cache into a file.: ${local_absolute_path}/${MASTER_KEY_FILE_NAME}"
}

# There should be two arguments: seal key that user provided for the upload cache service and destination of where the raw encryption key will be stored.
if [ $# -eq "2" ];
then
    local_destination="$1"
    seal_key="$2"
    base64_seal_key=(`base64 ${seal_key}`)
else
    fail "Usage: $0 </local/directory/path> $1 <seal_key_file>" 1
fi

# Verify the local destination is a present directory.
[ ! -d "${local_destination}" ] && fail "Local destination must exist and be a directory: ${local_destination}" 2

isDockerAvailable

# Find the upload cache container ID(s); give the container a few seconds to start if necessary
sleep_count=0
until get_container_id && [ "${#container_id[*]}" -gt 0 ] ; do
    sleep_count=$(( ${sleep_count} + 1 ))
    [ ${sleep_count} -gt ${TIMEOUT} ] && fail "Upload cache container not ready after ${TIMEOUT} seconds."
    sleep 1
done

# Check that exactly one instance of the upload cache container is up and running
[ "${#container_id[*]}" -ne 1 ] && fail "${#container_id[*]} instances of the Black Duck upload cache container are running." 5

# Create an absolute path to copy to, adds support for symbolic links
if [ ! -d "$local_destination" ]; then
    cd `dirname $local_destination`
    base_file=`basename $local_destination`
    symlink_count=0
    while [ -L "$base_file" ]; do
        (( symlink_count++ ))
        if [ "$symlink_count" -gt 100 ]; then
            fail "MAXSYMLINK level reached." 6
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

echo "Attempting to get the master key."

get_master_key ${container_id} ${local_absolute_path} ${base64_seal_key}
