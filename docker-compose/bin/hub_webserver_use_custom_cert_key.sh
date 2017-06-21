#!/bin/bash

set -e

TIMEOUT=${TIMEOUT:-10}
HUB_VERSION=${HUB_VERSION:-3.7.0}
HUB_WEBSERVER_IMAGE_NAME=${HUB_WEBSERVER_IMAGE_NAME:-webserver}
WEBSERVER_HOME=/opt/blackduck/hub/webserver

function fail() {
    message=$1
    exit_status=$2
    echo "${message}"
    exit ${exit_status}
}

function set_container_id() {
    container_id=( `docker ps -q -f label=com.blackducksoftware.hub.version=${HUB_VERSION} \
                                 -f label=com.blackducksoftware.hub.image=${HUB_WEBSERVER_IMAGE_NAME}` )
    return 0
}

# Check that valid inputs are supplied 
[ $# -ne "2" ] && fail "Usage:  $0 <crt-file-path> <key-file-path>" 1
certPath="$1"
keyPath="$2"
certFile=`basename "$certPath"`
keyFile=`basename "$keyPath"`
([[ "${certFile: -4}" != ".crt" && "${certFile: -4}" != ".pem" ]] || [[ "${keyFile: -4}" != ".key" ]]) && fail "Usage:  $0 <crt-file-path> <key-file-path>. Are you using the right file format in a correct order?" 2

# Check that docker is on our path
[ "$(type -p docker)" == "" ] && fail docker not found on the search path 3

# Check that we can contact the docker daemon
docker ps > /dev/null
success=$?
[ ${success} -ne 0 ] && fail "Could not contact docker daemon. Is DOCKER_HOST set correctly?" 4

# Find the webserver container ID(s); give the container a few seconds to start if necessary
sleep_count=0
until set_container_id && [ "${#container_id[*]}" -gt 0 ] ; do
    sleep_count=$(( ${sleep_count} + 1 ))
    [ ${sleep_count} -gt ${TIMEOUT} ] && fail "Webserver container not ready after ${TIMEOUT} seconds." 5
    sleep 1
done

# Check that exactly one instance of the database container is up and running
[ "${#container_id[*]}" -ne 1 ] && fail "${#container_id[*]} instances of the hub webserver container are running." 6


docker cp "$certPath" ${container_id}:$WEBSERVER_HOME/security && docker cp "$keyPath" ${container_id}:$WEBSERVER_HOME/security
copy_success=$?
[ ${copy_success} -ne 0 ] && fail "Failed copying in the files. Check if the container is running or the files are available" 7


docker exec -ti ${container_id} sed -i "s/ssl_certificate .*/ssl_certificate \/opt\/blackduck\/hub\/webserver\/security\/$certFile;/g; s/ssl_certificate_key.*/ssl_certificate_key \/opt\/blackduck\/hub\/webserver\/security\/$keyFile;/g" /etc/nginx/nginx.conf && docker kill -s HUP ${container_id} 

echo "Custom certificate-key pair added and being used [certificate file:" $certPath ", key file:" $keyPath "]"
