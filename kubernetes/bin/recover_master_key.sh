#!/bin/bash

# Prerequisites:
#  1. The upload cache container is running.

set -e

TIMEOUT=${TIMEOUT:-10}
UPLOAD_CACHE_IMAGE_NAME=${UPLOAD_CACHE_IMAGE_NAME:-uploadcache}

function fail() {
    message=$1
    exit_status=$2

    echo "${message}"
    exit ${exit_status}
}

function isDockerAvailable(){
    # Check that docker is on our path
    [ "$(type -p docker)" == "" ] && fail "docker not found on the search path" 2

    # Check that we can contact the docker daemon
    docker ps > /dev/null
    success=$?
    [ ${success} -ne 0 ] && fail "Could not contact docker daemon. Is DOCKER_HOST set correctly?" 3
    return 0
}

function get_container_id() {
    container_id=( `docker ps -q -f label=com.blackducksoftware.hub.image=${UPLOAD_CACHE_IMAGE_NAME}` )
    echo ${container_id}
    return 0
}

function rotate_key() {
    container=$1
    seal_key=$2
    master_key=$3

    echo "Attempting to rotate the seal key [Container: ${container}]."

    docker exec -i ${container} \
    curl -X PUT --header "X-SEAL-KEY:$seal_key" -H "X-MASTER-KEY:$master_key" \
                           https://uploadcache:9444/api/internal/recovery \
                           --cert /opt/blackduck/hub/blackduck-upload-cache/security/blackduck-upload-cache-server.crt \
                           --key /opt/blackduck/hub/blackduck-upload-cache/security/blackduck-upload-cache-server.key \
                           --cacert /opt/blackduck/hub/blackduck-upload-cache/security/root.crt

    exitCode=$?
    [ ${exitCode} -ne 0 ] && fail "Unable to rotate the seal key [Container: ${container}]"
    return 0
}

# There should be two arguments: A new seal key that user provides for the upload cache service and the master key.
if [ $# -eq "2" ];
then
    seal_key_file="$1"
    base64_master_key=$(<"$2")
    base64_seal_key=(`base64 ${seal_key_file}`)
else
    fail "Usage: $0 <new_seal_key_file> $1 <master_key_file>" 1
fi

isDockerAvailable

# Find the upload cache container ID(s); give the container a few seconds to start if necessary
sleep_count=0
until get_container_id && [ "${#container_id[*]}" -gt 0 ] ; do
    sleep_count=$(( ${sleep_count} + 1 ))
    [ ${sleep_count} -gt ${TIMEOUT} ] && fail "Upload cache container not ready after ${TIMEOUT} seconds."
    sleep 1
done

# Check that exactly one instance of the upload cache container is up and running
[ "${#container_id[*]}" -ne 1 ] && fail "${#container_id[*]} instances of the Black Duck upload cache container are running." 4

echo "Attempting to rotate the seal key."

rotate_key ${container_id} ${base64_seal_key} ${base64_master_key}