#!/usr/bin/env bash
#
# Copyright (C) 2018 Black Duck Software Inc.
# http://www.blackducksoftware.com/
# All rights reserved.
#
# This software is the confidential and proprietary information of
# Black Duck Software ("Confidential Information"). You shall not
# disclose such Confidential Information and shall use it only in
# accordance with the terms of the license agreement you entered into
# with Black Duck Software.

# Gather system and orchestration data to aide in problem diagnosis.
# This command should be run by "root" on the docker host, although
# limited information is still available if run by an unprivileged
# user.  The script will take several minutes to run.
#
# Output will be saved to ${SYSTEM_CHECK_OUTPUT_FILE}.
# A Java properties file with selected data will be saved to ${SYSTEM_CHECK_PROPERTIES_FILE}.
#
# Notes:
#  * Alpine ash has several incompatibilities with bash
#    - FUNCNAME is undefined, so ${FUNCNAME[0]} generates a syntax error.  Use $FUNCNAME instead,
#      even though it triggers spellcheck rule SC2128.
#    - Indirect expansion ("${!key}") generates a syntax error.  Use "$(eval echo \$${key})" instead.
#  * macOS distributes very old versions of some tools.
#    - /bin/bash is still version 3, which lacks associative arrays.
#    - /bin/df is a FreeBSD variant and lacks the GNU --total and -x options.
#  * "local foo=$(...)" and variations will mask the command substitution exit status.
#  * Using "curl -f" would require credentials.
#  * The documentation at https://github.com/koalaman/shellcheck includes a list of rules
#    mentioned in the ignore directives. https://www.shellcheck.net/ is the main project website.
#  * The docker client is hardwired to use the UTF-8 horizontal ellipsis character (…, 0xE280A6),
#    which looks bad in text files.  Replace it with '+' in tabular data and '...' elsewhere.

# Global shellcheck suppression
# shellcheck disable=SC2155 # We don't care about subshell exit status.

set -o noglob
#set -o xtrace

readonly NOW="$(date +"%Y%m%dT%H%M%S%z")"
readonly NOW_ZULU="$(date -u +"%Y%m%dT%H%M%SZ")"
readonly HUB_VERSION="${HUB_VERSION:-2024.7.3}"
readonly OUTPUT_FILE="${SYSTEM_CHECK_OUTPUT_FILE:-system_check_${NOW}.txt}"
readonly PROPERTIES_FILE="${SYSTEM_CHECK_PROPERTIES_FILE:-${OUTPUT_FILE%.txt}.properties}"
readonly SUMMARY_FILE="${SYSTEM_CHECK_SUMMARY_FILE:-${OUTPUT_FILE%.txt}_summary.properties}"
readonly OUTPUT_FILE_TOC="$(mktemp -t "$(basename "${OUTPUT_FILE}").XXXXXXXXXX")"
trap 'rm -f "${OUTPUT_FILE_TOC}"' EXIT

# Our RAM requirements are as follows:
#  Swarm Install with a single node (with internal postgresql): 26GB
#  Swarm Install with a single node and Binary Analysis: 30GB + 2GB per additional BDBA container
# An additional 3GB of memory is required for optimal Redis performance (BLACKDUCK_REDIS_MODE=sentinel).
#
# Note: The number of swarm nodes is not currently checked, so a single node is assumed to be safe.
# TODO: handle SPH sizing
#
readonly REQ_RAM_GB=23                  # Baseline memory requirement
readonly REQ_RAM_GB_POSTGRESQL=3        # Extra memory required for internal postgresql container
readonly REQ_RAM_GB_PER_BDBA=2          # The first container counts double.
readonly REQ_RAM_GB_REDIS_SENTINEL=3    # Additional memory required for redis sentinal mode

# Required container minimum memory limits, in MB.
# The _G3 and _G4 arrays are for scans-per-hour sizing
# The _G2 arrays are for enhanced scanning
# The _G1 arrays are for legacy scanning
declare -ar REQ_CONTAINER_SIZES_G4=(
    # "SERVICE=10sph 120sph 250sph 500sph 1000sph 1500sph 2000sph"
    "hub_alert=2560 2560 2560 2560 2560 2560 2560"
    "hub_alert_database=2560 2560 2560 2560 2560 2560 2560"
    "hub_authentication=1229 2048 2048 2048 2048 2048 3072"
    "hub_binaryscanner=4096 4096 4096 4096 4096 4096 4096"
    "hub_bomengine=4608 5600 5600 5120 5120 5120 5120"
    "hub_cfssl=260 260 260 512 1024 1024 1024"
    "hub_documentation=1024 1024 1024 1024 1536 1536 1536"
    "hub_jobrunner=4710 8192 8192 8192 8192 8192 8192"
    "hub_logstash=1229 2428 3072 3072 4096 4096 4096"
    "hub_matchengine=5120 8192 8192 8192 10240 10240 10240"
    "hub_postgres=8192 16384 24576 65536 90112 106496 131072"
    "hub_postgres-upgrader=4096 4096 4096 4096 4096 4096 4096"
    "hub_rabbitmq=512 512 512 1024 2048 3072 3072"
    "hub_redis=1024 1024 2048 4096 5120 8192 10240"
    "hub_redissentienl=32 32 32 32 32 32 32"
    "hub_redisslave=1024 1024 2048 4096 5120 8192 10240"
    "hub_registration=1024 1331 1331 2048 3072 3072 3072"
    "hub_scan=5120 10240 10240 10240 15360 15360 15360"
    "hub_storage=1024 2560 3072 4096 8192 8192 10240"
    "hub_uploadcache=512 512 512 1024 1536 2048 2048"
    "hub_webapp=3584 4048 5120 6144 20480 20480 20480"
    "hub_webserver=512 512 512 1024 2048 2048 2048"
)
declare -ar REQ_CONTAINER_SIZES_G3=(
    # "SERVICE=10sph 120sph 250sph 500sph 1000sph 1500sph 2000sph"
    "hub_alert=2560 2560 2560 2560 2560 2560 2560"
    "hub_alert_database=2560 2560 2560 2560 2560 2560 2560"
    "hub_authentication=1229 1638 1638 1638 2048 3072 3072"
    "hub_binaryscanner=4096 4096 4096 4096 4096 4096 4096"
    "hub_bomengine=4608 4608 4608 4608 4608 4608 4608"
    "hub_cfssl=260 260 260 512 1024 1024 1024"
    "hub_documentation=1024 1024 1024 1024 1536 1536 1536"
    "hub_jobrunner=4710 6451 6451 6451 6451 6451 6451"
    "hub_logstash=1229 1741 2048 4096 4096 5120 5120"
    "hub_matchengine=5120 6000 14436 10240 10240 10240 10240"
    "hub_postgres=8192 16384 24576 40960 65536 94208 139264"
    "hub_postgres-upgrader=4096 4096 4096 4096 4096 4096 4096"
    "hub_rabbitmq=512 512 512 1024 2048 4096 4096"
    "hub_redis=1024 1024 4096 14336 34816 40960 40960"
    "hub_redissentienl=32 32 32 32 32 32 32"
    "hub_redisslave=1024 1024 4096 14336 34816 40960 40960"
    "hub_registration=1024 1331 1331 2048 3072 3072 3072"
    "hub_scan=5120 9523 15360 15360 15360 15360 15360"
    "hub_storage=1024 1024 1024 1024 1024 1024 1024"
    "hub_webapp=3584 5120 8192 11264 15360 18432 18432"
    "hub_webserver=512 512 512 1024 2048 3072 3072"
)
declare -ar REQ_CONTAINER_SIZES_G2=(
    # "SERVICE=compose swarm kubernetes"
    "hub_alert=2560 2560 2560"
    "hub_alert_database=2560 2560 2560"
    "hub_authentication=1024 1024 1024"
    "hub_bomengine=2048 4608 4608"
    "hub_binaryscanner=2048 4096 4096"
    "hub_cfssl=512 640 640"
    "hub_documentation=512 512 512"
    "hub_integration=1024 1024 1024"
    "hub_jobrunner=3584 3584 3584"
    "hub_matchengine=4608 4608 4608"
    "hub_logstash=1024 1024 1024"
    "hub_postgres=3072 3072 3072"
    "hub_rabbitmq=1024 1024 1024"
    "hub_redis=1024 2048 2048"
    "hub_redissentienl=32 32 32"
    "hub_redisslave=1024 2048 2048"
    "hub_registration=640 640 1024"
    "hub_scan=2560 2560 2560"
    "hub_webapp=2560 2560 2560"
    "hub_webserver=640 512 512"
)
declare -ar REQ_CONTAINER_SIZES_G1=(
    # "SERVICE=compose swarm kubernetes"
    "hub_alert=2560 2560 2560"
    "hub_alert_database=2560 2560 2560"
    "hub_authentication=1024 1024 1024"
    "hub_bomengine=4608 4608 4608"
    "hub_binaryscanner=2048 4096 4096"
    "hub_cfssl=512 640 640"
    "hub_documentation=512 512 512"
    "hub_integration=1024 1024 1024"
    "hub_jobrunner=4608 4608 4608"
    "hub_matchengine=4608 4608 4608"
    "hub_logstash=1024 2560 2560"
    "hub_postgres=3072 3072 3072"
    "hub_rabbitmq=1024 1024 512"
    "hub_redis=1024 1024 1024"
    "hub_redissentienl=32 32 32"
    "hub_redisslave=1024 1024 1024"
    "hub_registration=640 640 1024"
    "hub_scan=2560 2560 2560"
    "hub_webapp=2560 2560 2560"
    "hub_webserver=640 512 512"
)

# The values below are small, medium, and large size HUB_MAX_MEMORY or
# BLACKDUCK_REDIS_MAXMEMORY settings (in MB) for each service, or the
# container size when there is no application memory limit control.
declare -ar SPH_MEM_SIZES_G4=(
    # "SERVICE=10sph 120sph 250sph 500sph 1000sph 1500sph 2000sph" # in MB
    "hub_authentication=1106 1843 1843 1843 1844 1844 2765"
    "hub_bomengine=4148 5000 5000 4608 4608 4608 4068"
    "hub_documentation=922 922 922 922 1383 1383 1383"
    "hub_integration=1024 1024 1024 1024 1024 1024 1024"
    "hub_jobrunner=4240 7373 7373 7373 7373 7373 7373"
    "hub_logstash=1106 2185 2765 2765 3687 3687 3687"
    "hub_matchengine=4608 7373 7373 7373 9216 9216 9216"
    "hub_redis=900 900 1844 3687 4608 7373 9216"
    "hub_registration=922 1200 1200 1844 2765 2765 2765"
    "hub_scan=4608 9216 9216 9216 13824 13824 13824"
    "hub_storage=512 1536 1996 3072 6554 6554 8192"
    "hub_webapp=3226 3608 4608 5530 18432 18432 18432"
)
declare -ar SPH_MEM_SIZES_G3=(
    # "SERVICE=10sph 120sph 250sph 500sph 1000sph 1500sph 2000sph" # in MB
    "hub_authentication=1106 1475 1475 1475 1844 2765 2765"
    "hub_bomengine=4148 4148 4148 4148 4148 4148 4148"
    "hub_documentation=922 922 922 922 1383 1383 1383"
    "hub_integration=1024 1024 1024 1024 1024 1024 1024"
    "hub_jobrunner=4240 5807 5807 5807 5807 5807 5807"
    "hub_logstash=1106 1567 1844 3687 3687 4608 4608"
    "hub_matchengine=4608 5400 12902 9216 9216 9216 9216"  # Higher ratings are smaller but have more replicas
    "hub_redis=900 900 3410 13312 31335 36864 36864"
    "hub_registration=922 1200 1200 1844 2765 2765 2765"
    "hub_scan=4608 8571 13824 13824 13824 13824 13824"
    "hub_storage=512 512 512 512 512 512 512"
    "hub_webapp=3226 4608 7373 10138 13824 16588 16588"
)
declare -ar TS_MEM_SIZES_G2=(
    # "SERVICE=small medium large" # in MB
    #"hub_authentication=1024 1024 1024"
    "hub_bomengine=4096 6144 12288"  # Stock docker-compose deployments are undersized
    "hub_jobrunner=3072 4608 10240"
    "hub_integration=1024 1024 1024"
    "hub_matchengine=4096 6144 12288"
    "hub_postgres=3072 8192 12288"
    "hub_redis=1700 3482 6092"  # BLACKDUCK_REDIS_MAXMEMORY settings are not documented.
    "hub_redisslave=900 3072 7168"
    "hub_registration=512 512 512"
    "hub_scan=2048 2048 8192"  # sic
    "hub_webapp=2048 4096 8192"
    "hub_webserver=512 2048 2048"
)
declare -ar TS_MEM_SIZES_G1=(
    # "SERVICE=small medium large" # in MB
    "hub_authentication=1024 1024 1024"
    "hub_bomengine=4096 7168 13824"
    "hub_jobrunner=4096 7168 13824"
    "hub_integration=1024 1024 1024"
    "hub_matchengine=4096 7168 13824"
    "hub_postgres=3072 8192 12288"
    "hub_registration=512 512 512"
    "hub_scan=2048 5120 9728"
    "hub_webapp=2048 6144 10752"
    "hub_webserver=512 2048 2048"
)

declare -ar SPH_REPLICA_COUNTS_G4=(
    # "SERVICE=10sph 120sph 250sph 500sph 1000sph 1500sph 2000sph"
    "hub_bomengine=1 1 1 2 7 8 10"
    "hub_jobrunner=1 1 2 3 5 6 8"
    "hub_matchengine=1 2 3 4 9 12 15"
    "hub_scan=1 1 2 4 10 13 16"
)
declare -ar SPH_REPLICA_COUNTS_G3=(
    # "SERVICE=10sph 120sph 250sph 500sph 1000sph 1500sph 2000sph"
    "hub_bomengine=1 1 1 2 4 6 6"
    "hub_jobrunner=1 1 1 2 4 6 6"
    "hub_matchengine=1 2 3 6 12 18 18"
    "hub_scan=1 1 3 6 12 18 18"
)
declare -ar TS_REPLICA_COUNTS_G2=(
    # "SERVICE=small medium large"
    "hub_bomengine=1 2 4"
    "hub_jobrunner=1 2 3"
    "hub_matchengine=1 4 6"
    "hub_scan=1 2 3"
)
declare -ar TS_REPLICA_COUNTS_G1=(
    # "SERVICE=small medium large"
    "hub_bomengine=1 2 4"
    "hub_jobrunner=1 4 6"
    "hub_scan=1 2 3"
)

declare -ar SPH_PG_SETTINGS_G4=(
    # "SERVICE=10sph 120sph 250sph 500sph 1000sph 1500sph 2000sph"
    "shared_buffers=2653 5336 8016 21439 29502 34878 42974"
    "effective_cache_size=3185 6404 9619 25727 35403 41854 51569"
)
declare -ar SPH_PG_SETTINGS_G3=(
    # "SERVICE=10sph 120sph 250sph 500sph 1000sph 1500sph 2000sph"
    "shared_buffers=2653 5336 8016 21439 29502 34878 42974"
    "effective_cache_size=3185 6404 9619 25727 35403 41854 51569"
)

declare -ar SPH_SIZE_SCALE=("an UNDERSIZED" "10" "120" "250" "500" "1000" "1500" "2000" "2000+")
declare -ar TS_SIZE_SCALE=("an UNDERSIZED" "a small" "a medium" "a large" "an extra-large")

# Our CPU requirements are as follows:
# Swarm Install: 6
# Swarm Install with Binary Analysis: 7
readonly REQ_CPUS=5
readonly REQ_CPUS_POSTGRESQL=1
readonly REQ_CPUS_PER_BDBA=1

readonly REQ_DISK_GB=250
readonly REQ_DISK_GB_PER_BDBA=100

readonly REQ_DOCKER_VERSIONS="20.10.x"
readonly REQ_ENTROPY=100

readonly REQ_MIN_SYSCTL_KEEPALIVE_TIME=600
readonly REQ_MAX_SYSCTL_KEEPALIVE_TIME=899

readonly TRUE="TRUE"
readonly FALSE="FALSE"
readonly UNKNOWN="UNKNOWN"  # Yay for tri-valued booleans!  Treated as $FALSE.

readonly PASS="PASS"
readonly WARN="WARNING"
readonly FAIL="FAIL"
readonly NOTE="NOTE"

# See https://sig-confluence.internal.synopsys.com/display/SIGBD/Architecture+Overview
declare -ar REPLICABLE=(
    # "SERVICE=status"
    "hub_alert=$WARN"
    "hub_alert_database=$FAIL"
    "hub_authentication=$FAIL"
    #"hub_binaryscanner=$PASS"
    #"hub_bomengine=$PASS"
    "hub_cfssl=$FAIL"
    "hub_documentation=$WARN"
    #"hub_integration=$PASS"
    #"hub_jobrunner=$PASS"
    "hub_logstash=$FAIL"
    #"hub_matchengine=$PASS"
    "hub_postgres=$FAIL"
    "hub_rabbitmq=$FAIL"
    "hub_redis=$FAIL"
    "hub_redissentinel=$FAIL"
    #"hub_redisslave=$PASS"
    "hub_registration=$FAIL"
    #"hub_scan=$PASS"
    "hub_storage=$FAIL"
    "hub_webapp=$FAIL"
    "hub_webserver=$WARN"
)

readonly MB=1048576
readonly GB=$((MB * 1024))

readonly DOCKER_COMMUNITY_EDITION="Community"
readonly DOCKER_ENTERPRISE_EDITION="Enterprise"
readonly DOCKER_LEGACY_EDITION="legacy"

readonly SCHEMA_NAME=${HUB_POSTGRES_SCHEMA:-st}

# Controls installation sizing estimation.
SCAN_SIZING="gen04"

# Controls a switch to turn network testing on/off for systems with no internet connectivity
USE_NETWORK_TESTS="$TRUE"
readonly NETWORK_TESTS_SKIPPED="*** Network Tests Skipped at command line ***"

# Hostnames Black Duck uses within the docker network
readonly HUB_RESERVED_HOSTNAMES="postgres postgres-upgrader postgres-waiter authentication webapp scan jobrunner cfssl logstash \
registration webserver documentation redis bomengine rabbitmq matchengine integration"

readonly CONTAINERS_WITHOUT_CURL="nginx|postgres|postgres-upgrader|postgres-waiter|alert-database|cadvisor"

# Versioned (not "1.0.x") blackducksoftware images
readonly VERSIONED_HUB_IMAGES="blackduck-authentication|blackduck-bomengine|blackduck-documentation|blackduck-jobrunner|blackduck-matchengine|blackduck-redis|blackduck-registration|blackduck-scan|blackduck-storage|blackduck-webapp"
readonly VERSIONED_BDBA_IMAGES="bdba-worker"
readonly VERSIONED_ALERT_IMAGES="blackduck-alert"

# Anti-virus scanner package names.
declare -ar MALWARE_SCANNER_PACKAGES=(
    # "product_name=extended-regex"
    "Avast_Security=(avast|avast-fss|avast-proxy|com.avast.daemon)"
    # "Avira="
    "BitDefender_GravityZone=bitdefender"
    "chkrootkit=chkrootkit"
    "ClamAV=(clamav|clamd)"
    "Comodo_Anti_Virus_for_Linux=cav-linux"
    "Cylance_Protect=CylanceSvc"
    "ESET=(ESET|esets|efs-7)"  # Include efs version to avoid conflicts with AWS EFS.
    "Falcon_CrowdStrike=falcon-sensor"
    "FProt=fp-"
    "Kaspersky_Endpoint_Security=(kesl-|kesl_)"
    "Linux_Malware_Detect=(maldet-|maldetect-)"
    "McAfee=(MAProvision|MFEcma|MFErt)"
    "Rootkit_Hunter=rkhunter-"
    "Sophos=savinstpkg"
    "Symantec=(sep-|sepap-|sepui-|sav-|savap-|savui-|savjlu-)"
    "Trend_Micro=TmccMac"
)

# Anti-virus scanner process names.  See also https://github.com/CISOfy/lynis
declare -ar MALWARE_SCANNER_PROCESSES=(
    # "product_name=extended-regex"
    "Avast_Security=(avast|avast-fss|com.avast.daemon)"
    "Avira=avqmd"
    "BitDefender_GravityZone=(bdagentd|bdepsecd|epagd|bdsrvscand)"
    "chkrootkit=chkrootkit"
    "ClamAV=(clamconf|clamscan|clamd|freshclam)"
    "Comodo_Anti_Virus_for_Linux=(cavscan|cmdavd|cmgdaemon|cmdagent)"
    "Cylance_Protect=CylanceSvc"
    "ESET=esets_daemon"
    "Falcon_CrowdStrike=falcon-sensor"
    "FProt=fpscand"
    "Kaspersky_Endpoint_Security=(wdserver|klnagent)"
    "Linux_Malware_Detect=maldet"
    "McAfee=(cma|cmdagent)"
    "Rootkit_Hunter=rkhunter"
    "Sophos=(savscand|SophosScanD)"
    "Symantec=(symcfgd|rtvscand|smcd)"
    #"Trend_Micro="
)

################################################################
# Configure sizing data for the selected scan type.
#
# Globals:
#   SIZING -- (out) text description, e.g. 'enhanced scanning'
#   REQ_CONTAINER_SIZES -- (out) container sizing information
#   SIZE_SCALE -- (out) label for different sizes
#   MEM_SIZE_SCALE -- (out) memory sizing information
#   REPLICA_COUNT_SCALE -- (out) replica count information
#   PG_SETTINGS_SCALE -- (out) postgresql setting information
# Arguments:
#   None
# Returns:
#   None
################################################################
setup_sizing() {
    case "$SCAN_SIZING" in
        gen01)
            SIZING="legacy scanning"
            SIZE_SCALE=("${TS_SIZE_SCALE[@]}")
            REQ_CONTAINER_SIZES=("${REQ_CONTAINER_SIZES_G1[@]}")
            MEM_SIZE_SCALE=("${TS_MEM_SIZES_G1[@]}")
            REPLICA_COUNT_SCALE=("${TS_REPLICA_COUNTS_G1[@]}")
            PG_SETTINGS_SCALE=()
            ;;
        gen02)
            SIZING="enhanced scanning"
            SIZE_SCALE=("${TS_SIZE_SCALE[@]}")
            REQ_CONTAINER_SIZES=("${REQ_CONTAINER_SIZES_G2[@]}")
            MEM_SIZE_SCALE=("${TS_MEM_SIZES_G2[@]}")
            REPLICA_COUNT_SCALE=("${TS_REPLICA_COUNTS_G2[@]}")
            PG_SETTINGS_SCALE=()
            ;;
        gen03)
            SIZING="pre-2023.10.1 scans-per-hour"
            SIZE_SCALE=("${SPH_SIZE_SCALE[@]}")
            REQ_CONTAINER_SIZES=("${REQ_CONTAINER_SIZES_G3[@]}")
            MEM_SIZE_SCALE=("${SPH_MEM_SIZES_G3[@]}")
            REPLICA_COUNT_SCALE=("${SPH_REPLICA_COUNTS_G3[@]}")
            PG_SETTINGS_SCALE=("${SPH_PG_SETTINGS_G3[@]}")
            ;;
        gen04)
            SIZING="scans-per-hour"
            SIZE_SCALE=("${SPH_SIZE_SCALE[@]}")
            REQ_CONTAINER_SIZES=("${REQ_CONTAINER_SIZES_G4[@]}")
            MEM_SIZE_SCALE=("${SPH_MEM_SIZES_G4[@]}")
            REPLICA_COUNT_SCALE=("${SPH_REPLICA_COUNTS_G4[@]}")
            PG_SETTINGS_SCALE=("${SPH_PG_SETTINGS_G4[@]}")
            ;;
        *)
            error_exit "** Internal error: unexpected SCAN_SIZING '$SCAN_SIZING'"
            ;;
    esac
    readonly SIZING
    readonly SIZE_SCALE
    readonly REQ_CONTAINER_SIZES
    readonly MEM_SIZE_SCALE
    readonly REPLICA_COUNT_SCALE
    readonly PG_SETTINGS_SCALE
    echo "Configured for $SIZING ($SCAN_SIZING)"
}

################################################################
# Utility to simulate associative array lookup (a bash version 4
# feature) in bash v3, which is what Apple ships with macOS.
#
# Globals:
#   None
# Arguments:
#   $@ - array values and key, e.g. $(array_get "${data[@]}" "$key")
#      Array values should be of the form "key=value".  Values
#      may contain '=' characters too.  Whitespace is significant.
# Returns:
#   None.  Echoes the matched values to stdout.
################################################################
array_get() {
    local -a data=("$@")
    local -i last=$((${#data[@]} - 1))
    local key="${data[$last]}"
    # shellcheck disable=SC2184 # We did 'set -o noglob' already.
    unset data[$((last))]
    for entry in "${data[@]}"; do
        if [[ "${entry%%=*}" == "$key" ]]; then
            echo "${entry#*=}"
        fi
    done
}

################################################################
# Utility to test whether a command is available.
#
# Globals:
#   None
# Arguments:
#   Desired command name (without arguments)
# Returns:
#   true if the command is available
################################################################
have_command() {
    [[ "$#" -eq 1 ]] || error_exit "usage: have_command <cmd>"
    type "$1" > /dev/null 2>&1
}

################################################################
# Determine whether a check returned a successful status message
# ($PASS or $WARN)
#
# Globals:
#   None
# Arguments:
#   Check status message
# Returns:
#   true if the status message indicates success.
################################################################
check_passfail() {
    [[ "$*" =~ $PASS || "$*" =~ $WARN ]] && [[ ! "$*" =~ $FAIL ]]
}

################################################################
# Determine whether a check returned unknown status message
# ($UNKNOWN)
#
# Globals:
#   None
# Arguments:
#   Check status message
# Returns:
#   true if the status message indicates unknown results
################################################################
is_unknown() {
    [[ "$*" =~ $UNKNOWN ]] && [[ ! "$*" =~ $FAIL ]]
}

################################################################
# Echo PASS/FAIL depending on status
#
# Globals:
#   None
# Arguments:
#   $1 - int status; 0 -> PASS, others -> FAIL
# Returns:
#   true if $1 was 0
################################################################
echo_passfail() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash.
    [[ "$#" -eq 1 ]] || error_exit "usage: $FUNCNAME <cmd>"
    [[ "$1" -eq 0 ]] && echo "$PASS" || echo "$FAIL"

    [[ "$1" -eq 0 ]]
}

################################################################
# Determine whether boolean variable is TRUE
#
# Globals:
#   None
# Arguments:
#   Boolean variable
# Returns:
#   true if the variable is true
################################################################
check_boolean() {
    [[ "$*" =~ $TRUE ]] && [[ ! "$*" =~ $FALSE ]]
}

################################################################
# Echo TRUE/FALSE depending on status
#
# Globals:
#   None
# Arguments:
#   $1 - int exit code; 0 -> TRUE, others -> FALSE
# Returns:
#   true if $1 was 0
################################################################
echo_boolean() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -eq 1 ]] || error_exit "usage: $FUNCNAME <cmd>"
    [[ "$1" -eq 0 ]] && echo "$TRUE" || echo "$FALSE"

    [[ "$1" -eq 0 ]]
}

################################################################
# Print an error message to STDERR and exit
#
# Globals:
#   None
# Arguments:
#   $@ - error message
# Returns:
#   None
################################################################
error_exit() {
    echo "$@" >&2
    exit 1
}

################################################################
# Test whether arguments might contain shell wildcard characters.
# Does NOT handle escaped wildcards properly.
#
# Globals:
#   None
# Arguments:
#   $@ - pathnames to test
# Returns:
#   true if any path contains wildcards
################################################################
is_glob() {
    # shellcheck disable=SC2049 # We really do want a literal '*'
    [[ "$*" =~ \* ]] || [[ "$*" =~ \? ]] || [[ "$*" =~ \[ ]]
}

################################################################
# Test whether we are running as root.  Prompt the user to
# abort if we are not.
#
# Globals:
#   IS_ROOT -- (out) TRUE/FALSE
#   CURRENT_USERNAME -- (out) user name.
#   FORCE -- (in) proceed without prompting for confirmation
# Arguments:
#   None
# Returns:
#   true if running as root.
################################################################
is_root() {
    if [[ -z "${IS_ROOT}" ]]; then
        IS_ROOT="$TRUE"
        if [[ "$(id -u)" -ne 0 ]]; then
            echo "This script must be run as root for all features to work.  It will"
            echo "gather a reduced set of information if run this way, but you will"
            echo "likely be asked by Black Duck support to re-run the script with root"
            echo "privileges."
            if ! check_boolean "$FORCE" ; then
                echo
                read -rp "Are you sure you want to proceed as a non-privileged user? [y/N]: "
                [[ "$REPLY" =~ ^[Yy] ]] || exit 1
            fi
            IS_ROOT="$FALSE"
            echo
        fi
        readonly IS_ROOT
        readonly CURRENT_USERNAME="$(id -un)"
    fi

    check_boolean "${IS_ROOT}"
}

################################################################
# Test whether we are running on a laptop.
#
# Globals:
#   IS_LAPTOP -- (out) TRUE/FALSE/UNKNOWN
#   CHASSIS_TYPE -- (out) text chassis description, if known.
# Arguments:
#   None
# Returns:
#   true if running on a laptop
################################################################
is_laptop() {
    if [[ -z "${IS_LAPTOP}" ]]; then
        if have_command laptop-detect ; then
            readonly CHASSIS_TYPE="$(laptop-detect 2>&1)"
            readonly IS_LAPTOP="$(echo_boolean "$?")"
        elif is_root && have_command dmidecode ; then
            # See https://docs.microsoft.com/en-us/previous-versions/tn-archive/ee156537(v=technet.10)
            readonly CHASSIS_TYPE="$(dmidecode --string chassis-type)"
            case "$CHASSIS_TYPE" in
                Portable|Laptop|Notebook|Hand\ Held) readonly IS_LAPTOP="$TRUE";;
                *)                                   readonly IS_LAPTOP="$FALSE";;
            esac
        elif [[ -r "/sys/devices/virtual/dmi/id/chassis_type" ]]; then
            # See https://docs.microsoft.com/en-us/previous-versions/tn-archive/ee156537(v=technet.10)
            readonly CHASSIS_TYPE="$(cat /sys/devices/virtual/dmi/id/chassis_type)"
            case "$CHASSIS_TYPE" in
                8|9|10|11) readonly IS_LAPTOP="$TRUE";;
                *)         readonly IS_LAPTOP="$FALSE";;
            esac
        elif [[ -r "/etc/machine-info" ]] && grep -aFq 'CHASSIS=' /etc/machine-info ; then
            readonly CHASSIS_TYPE="$(grep -aF 'CHASSIS=' /etc/machine-info | cut -d= -f2-)"
            case "$CHASSIS_TYPE" in
                laptop|tablet|convertible) readonly IS_LAPTOP="$TRUE";;
                *)                         readonly IS_LAPTOP="$FALSE";;
            esac
        elif [[ -e "/proc/acpi/button/lid" ]]; then
            # If the system has a lid it's probably a laptop?
            readonly IS_LAPTOP="$TRUE"
            readonly CHASSIS_TYPE=""
        else
            readonly IS_LAPTOP="$UNKNOWN"
            readonly CHASSIS_TYPE=""
        fi
    fi

    check_boolean "${IS_LAPTOP}"
}

################################################################
# Expose the running operating system name.  See also
# http://linuxmafia.com/faq/Admin/release-files.html
#
# Globals:
#   OS_NAME -- (out) operating system name
#   OS_NAME_SHORT -- (out) brief operating system name
#   IS_LINUX -- (out) TRUE/FALSE
#   IS_MACOS -- (out) TRUE/FALSE.  macOS is not considered to be Linux.
# Arguments:
#   None
# Returns:
#   true if this is a Linux system
################################################################
get_os_name() {
    if [[ -z "${OS_NAME}" ]]; then
        echo "Getting operating system name..."

        # Find the local release name.
        IS_LINUX="$TRUE"
        IS_MACOS="$FALSE"
        if have_command lsb_release ; then
            OS_NAME="$(lsb_release -a ; echo ; echo -n uname -a:\  ; uname -a)"
            OS_NAME_SHORT="$(lsb_release -ds | tr -d '"')"
        elif [[ -e /etc/fedora-release ]]; then
            OS_NAME="$(cat /etc/fedora-release)"
            OS_NAME_SHORT="$(head -1 /etc/fedora-release)"
        elif [[ -e /etc/oracle-release ]]; then
            OS_NAME="$(cat /etc/oracle-release)"
            OS_NAME_SHORT="$(head -1 /etc/oracle-release)"
        elif [[ -e /etc/centos-release ]]; then
            OS_NAME="$(cat /etc/centos-release)"
            OS_NAME_SHORT="$(head -1 /etc/centos-release)"
        elif [[ -e /etc/redhat-release ]]; then
            OS_NAME="$(cat /etc/redhat-release)"
            OS_NAME_SHORT="$(head -1 /etc/redhat-release)"
        elif [[ -e /etc/SuSE-release ]]; then
            OS_NAME="$(cat /etc/SuSE-release)"
            OS_NAME_SHORT="$(sed -e '/^#/d' -e '/VERSION/d' -e 's/PATCHLEVEL = /SP/' /etc/SuSE-release | tr '\n' ' ')"
        elif [[ -e /etc/gentoo-release ]]; then
            OS_NAME="$(cat /etc/gentoo-release)"
            OS_NAME_SHORT="$(head -1 /etc/gentoo-release)"
        elif [[ -e /etc/os-release ]]; then
            OS_NAME="$(cat /etc/os-release)"
            OS_NAME_SHORT="$(grep -aF PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
        elif [[ -e /usr/lib/os-release ]]; then
            OS_NAME="$(cat /usr/lib/os-release)"
            OS_NAME_SHORT="$(grep -aF PRETTY_NAME /usr/lib/os-release | cut -d'"' -f2)"
        elif have_command sw_vers ; then
            OS_NAME="$(sw_vers)"
            OS_NAME_SHORT="$(sw_vers -productName) $(sw_vers -productVersion)"
            IS_LINUX="$FALSE"
            IS_MACOS="$TRUE"
        else
            OS_NAME="$(echo -n uname -a:\  ; uname -a)"
            OS_NAME_SHORT="$(uname -a)"
            IS_LINUX="$FALSE"
        fi
        readonly OS_NAME
        readonly OS_NAME_SHORT
        readonly IS_LINUX
        readonly IS_MACOS
    fi

    check_boolean "${IS_LINUX}"
}

################################################################
# Determine whether the current operating system is a Linux
# variant.  macOS is _not_ considered to be Linux.
#
# Globals:
#   IS_LINUX -- (out) TRUE/FALSE
# Arguments:
#   None
# Returns:
#   true if this is a Linux system
################################################################
is_linux() {
    [[ -n "${IS_LINUX}" ]] || get_os_name
    check_boolean "${IS_LINUX}"
}

################################################################
# Expose the running operating system name.  See also
# http://linuxmafia.com/faq/Admin/release-files.html
#
# Globals:
#   IS_MACOS -- (out) TRUE/FALSE
# Arguments:
#   None
# Returns:
#   true if this is a macOS system
################################################################
is_macos() {
    [[ -n "${IS_MACOS}" ]] || get_os_name
    check_boolean "${IS_MACOS}"
}

################################################################
# Verify the kernel version.  A common reason for check failure
# is applying patches without restarting the system, which
# causes /proc/version to /etc/release to disagree.
#
# Globals:
#   KERNEL_VERSION_STATUS -- (out) PASS/FAIL status message.
#   OS_NAME -- (in) running operating system
# Arguments:
#   None
# Returns:
#   true if the kernel version is plausible for this OS.
################################################################
# shellcheck disable=SC2155,SC2046
check_kernel_version() {
    if [[ -z "$KERNEL_VERSION_STATUS" ]]; then
        echo "Checking kernel version..."
        local -r KERNEL_VERSION_FILE="/proc/version"
        if have_command uname ; then
            local -r kernel_version="$(uname -r)"
        elif [[ -r "${KERNEL_VERSION_FILE}" ]]; then
            local -r kernel_version="$(cat "${KERNEL_VERSION_FILE}")"
        else
            local -r kernel_version=""
        fi

        if [[ -z "${kernel_version}" ]]; then
            readonly KERNEL_VERSION_STATUS="$WARN: Kernel version is $UNKNOWN"
        else
            [[ -n "${OS_NAME}" ]] || get_os_name
            local expect;
            # shellcheck disable=SC2116 # Deliberate extra echo to collapse lines
            local -r have="$(echo "${OS_NAME}")"
            case "$have" in
                # See https://wiki.centos.org/Manuals/ReleaseNotes/CentOSStream#Differences_in_CentOS_Stream_from_CentOS_Linux_8.0.1905
                *CentOS\ Stream\ release\ 8*) expect="4.18.0";; # It changes too often to track at a finer level.
                # See https://access.redhat.com/articles/3078 and https://en.wikipedia.org/wiki/CentOS
                *Red\ Hat\ Enterprise\ *\ 8.5* | *CentOS\ *\ 8.5.2111*) expect="4.18.0-348";;
                *Red\ Hat\ Enterprise\ *\ 8.4* | *CentOS\ *\ 8.4.2105*) expect="4.18.0-305";;
                *Red\ Hat\ Enterprise\ *\ 8.3* | *CentOS\ *\ 8.3.2011*) expect="4.18.0-240";;
                *Red\ Hat\ Enterprise\ *\ 8.2* | *CentOS\ *\ 8.2.2004*) expect="4.18.0-193";;
                *Red\ Hat\ Enterprise\ *\ 8.1* | *CentOS\ *\ 8.1.1911*) expect="4.18.0-147";;
                *Red\ Hat\ Enterprise\ *\ 8.0* | *CentOS\ *\ 8.0.1905*) expect="4.18.0-80";;
                *Red\ Hat\ Enterprise\ *\ 7.9* | *CentOS\ *\ 7.9.2009*) expect="3.10.0-1160";;
                *Red\ Hat\ Enterprise\ *\ 7.8* | *CentOS\ *\ 7.8.2003*) expect="3.10.0-1127";;
                *Red\ Hat\ Enterprise\ *\ 7.7* | *CentOS\ *\ 7.7.1908*) expect="3.10.0-1062";;
                *Red\ Hat\ Enterprise\ *\ 7.6* | *CentOS\ *\ 7.6.1810*) expect="3.10.0-957";;
                *Red\ Hat\ Enterprise\ *\ 7.5* | *CentOS\ *\ 7.5.1804*) expect="3.10.0-862";;
                *Red\ Hat\ Enterprise\ *\ 7.4* | *CentOS\ *\ 7.4.1708*) expect="3.10.0-693";;
                *Red\ Hat\ Enterprise\ *\ 7.3* | *CentOS\ *\ 7.3.1611*) expect="3.10.0-514";;
                *Red\ Hat\ Enterprise\ *\ 7.2* | *CentOS\ *\ 7.2.1511*) expect="3.10.0-327";;
                *Red\ Hat\ Enterprise\ *\ 7.1* | *CentOS\ *\ 7.1.1503*) expect="3.10.0-229";;
                *Red\ Hat\ Enterprise\ *\ 7.0* | *CentOS\ *\ 7.0.1406*) expect="3.10.0-123";;
                # See https://blogs.oracle.com/scoter/oracle-linux-and-unbreakable-enterprise-kernel-uek-releases
                # I didn't find an authoritative reference for Oracle Linux, but these match the iso images.
                # UEK was not available until Oracle Linux 8.2 was released.
                *Oracle\ Linux\ Server\ release\ 8.5*)  expect="(5.4.17-2136.*.el8uek|4.18.0-248.*.el8_5)";;
                *Oracle\ Linux\ Server\ release\ 8.4*)  expect="(5.4.17-2102.*.el8uek|4.18.0-305.*.el8_4)";;
                *Oracle\ Linux\ Server\ release\ 8.3*)  expect="(5.4.17-2011.*.el8uek|5.4.17-2036.*.el8uek|4.18.0-240.*.el8_3)";;
                *Oracle\ Linux\ Server\ release\ 8.2*)  expect="(5.4.17-2011.*.el8uek|4.18.0-193.*.el8_2)";;
                *Oracle\ Linux\ Server\ release\ 8.1*)  expect="(4.18.0-147.*.el8_1)";;
                *Oracle\ Linux\ Server\ release\ 8.0*)  expect="(4.18.0-80.*.el8_0)";;
                *Oracle\ Linux\ Server\ release\ 7.9*)  expect="(5.4.17-2011.*.el7uek|5.4.17-2036.*.el7uek|3.10.0-1160.el7)";;
                *Oracle\ Linux\ Server\ release\ 7.8*)  expect="(4.14.35-1902.*.el7uek|3.10.0-1127.el7)";;
                *Oracle\ Linux\ Server\ release\ 7.7*)  expect="(4.14.35-1902.*.el7uek|3.10.0-1062.el7)";;
                *Oracle\ Linux\ Server\ release\ 7.6*)  expect="(4.14.35-1818.*.el7uek|3.10.0-957.el7)";;
                *Oracle\ Linux\ Server\ release\ 7.5*)  expect="(4.1.12-112.*.el7uek|3.10.0-862.el7)";;
                *Oracle\ Linux\ Server\ release\ 7.4*)  expect="(4.1.12-94.*.el7uek|3.10.0-693.el7)";;
                *Oracle\ Linux\ Server\ release\ 7.3*)  expect="(4.1.12-61.*.el7uek|3.10.0-514.el7)";;
                *Oracle\ Linux\ Server\ release\ 7.2*)  expect="(3.8.13-98.*.el7uek|3.10.0-327.el7)";;
                *Oracle\ Linux\ Server\ release\ 7.1*)  expect="(3.8.13-55.*.el7uek|3.10.0-229.el7)";;
                *Oracle\ Linux\ Server\ release\ 7.0*)  expect="(3.8.13-35.*.el7uek|3.10.0-123.el7)";;
                # See https://www.suse.com/support/kb/doc/?id=000019587
                *SUSE\ Linux\ Enterprise\ Server\ 15\ SP[3-9]*) expect="";; # Future-proofing
                *SUSE\ Linux\ Enterprise\ Server\ 15\ SP2)      expect="5.3.18-(22|24)";;
                *SUSE\ Linux\ Enterprise\ Server\ 15\ SP1)      expect="4.12.(14-195|14-197)";;
                *SUSE\ Linux\ Enterprise\ Server\ 15*)          expect="4.12.(14-23|14-25|14-150)";;
                *SUSE\ Linux\ Enterprise\ Server\ 12\ SP[6-9]*) expect="";; # Future-proofing
                *SUSE\ Linux\ Enterprise\ Server\ 12\ SP5*)     expect="4.12.(14-120|14-122)";;
                *SUSE\ Linux\ Enterprise\ Server\ 12\ SP4*)     expect="4.12.(14-94|14-95|14-120|14-122)";;
                *SUSE\ Linux\ Enterprise\ Server\ 12\ SP3*)
                    expect="4.4.(73-5|82-6|92-6|103-6|114-94|120-94|126-94|131-94|132-94|138-94|140-94|143-94|155-94|156-94|162-94|175-94|176-94|178-94|180-94)";;
                *SUSE\ Linux\ Enterprise\ Server\ 12\ SP2*)
                    expect="4.4.(21-69|21-81|21-84|21-90|38-93|49-92|59-92|74-92|90-92|103-92|114-92|120-92|121-92)";;
                *SUSE\ Linux\ Enterprise\ Server\ 12\ SP1*)
                    expect="3.12.(49-11|51-60|53-60|57-60|59-60|62-60|67-60|69-60|74-60)";;
                *SUSE\ Linux\ Enterprise\ Server\ 12*)
                    expect="3.12.(28-4|32-33|36-38|38-44|39-47|43-5344-53|48-53|51-52|52-57|55-52|60-52|61-52)";;
                # See https://en.wikipedia.org/wiki/MacOS_Monterey
                *macOS*12.[23456789].*)    expect="";; # Future-proofing
                *macOS*12.1.*)             expect="21.2.0";;
                *macOS*12.0.*)             expect="(21.0.1|21.1.0)";;
                # See https://en.wikipedia.org/wiki/MacOS_Big_Sur
                *macOS*11.[789].*)         expect="";; # Future-proofing
                *macOS*11.6.*)             expect="20.6.0";;
                *macOS*11.5.*)             expect="20.6.0";;
                *macOS*11.4.*)             expect="20.5.0";;
                *macOS*11.3.*)             expect="20.4.0";;
                *macOS*11.2.*)             expect="20.3.0";;
                *macOS*11.1.*)             expect="20.2.0";;
                *macOS*11.0.*)             expect="20.1.0";;
                # See https://en.wikipedia.org/wiki/MacOS_Catalina
                *Mac\ OS\ X*10.15.[89]*)   expect="";; # Future-proofing
                *Mac\ OS\ X*10.15.[67]*)   expect="19.6.0";;
                *Mac\ OS\ X*10.15.5*)      expect="19.5.0";;
                *Mac\ OS\ X*10.15.4*)      expect="19.4.0";;
                *Mac\ OS\ X*10.15.3*)      expect="19.3.0";;
                *Mac\ OS\ X*10.15.2*)      expect="19.2.0";;
                *Mac\ OS\ X*10.15.1*)      expect="19.0.0";;
                *Mac\ OS\ X*10.15*)        expect="19.0.0";;
                # See https://en.wikipedia.org/wiki/MacOS_Mojave
                *Mac\ OS\ X*10.14.[789]*)  expect="";; # Future-proofing
                *Mac\ OS\ X*10.14.6*)      expect="18.7.0";;
                *Mac\ OS\ X*10.14.5*)      expect="18.6.0";;
                *Mac\ OS\ X*10.14.4*)      expect="18.5.0";;
                *Mac\ OS\ X*10.14.[123]*)  expect="18.2.0";;
                *Mac\ OS\ X*10.14*)        expect="18.0.0";;
                # See https://en.wikipedia.org/wiki/Darwin_(operating_system)
                *Mac\ OS\ X*10.13.[789]*) expect="";; # Future-proofing
                *Mac\ OS\ X*10.13.6*)     expect="17.7.0";;
                *Mac\ OS\ X*10.13.[45]*)  expect="17.5.0";;
                *Mac\ OS\ X*10.13*)       expect="17.0.0";;
                # See https://askubuntu.com/questions/517136/list-of-ubuntu-versions-with-corresponding-linux-kernel-version
                *Ubuntu\ 16.04*) expect="4.4.";;
                *Ubuntu\ 18.04*) expect="4.15.";;
                *Ubuntu\ 20.04*) expect="5.4.";;
                # We don't know...
                *) expect="";;
            esac
            [[ "$expect" =~ \| ]] && grepStyle=E || grepStyle=F
            if [[ -z "$expect" ]]; then
                readonly KERNEL_VERSION_STATUS="$WARN: Don't know what kernel version to expect for ${OS_NAME_SHORT}"
            elif echo "$kernel_version" | grep -aq"$grepStyle" "$expect" ; then
                readonly KERNEL_VERSION_STATUS="$PASS: Kernel version ${kernel_version}"
            else
                readonly KERNEL_VERSION_STATUS="$WARN: Kernel version ${kernel_version} is unexpected"
            fi
        fi
    fi

    check_passfail "${KERNEL_VERSION_STATUS}"
}

################################################################
# Expose CPU information in envronment variables.
#
# Globals:
#   CPU_INFO -- (out) /proc/cpuinfo or an error message.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_cpu_info() {
    if [[ -z "${CPU_INFO}" ]]; then
        echo "Getting CPU information..."
        local -r CPUINFO_FILE="/proc/cpuinfo"
        if have_command system_profiler ; then
            readonly CPU_INFO="$(system_profiler SPHardwareDataType | grep -aE "Processor|Cores")"
        elif [[ -r "${CPUINFO_FILE}" ]]; then
            readonly CPU_INFO="$(cat ${CPUINFO_FILE})"
        elif [[ ! -e "${CPUINFO_FILE}" ]]; then
            readonly CPU_INFO="CPU info is $UNKNOWN -- ${CPUINFO_FILE} not found."
        else
            readonly CPU_INFO="CPU info is $UNKNOWN -- ${CPUINFO_FILE} is not readable."
        fi
    fi
}

################################################################
# Expose a CPU count.
#
# Globals:
#   CPU_COUNT -- (out) CPU count
#   CPU_COUNT_STATUS -- (out) PASS/FAIL status message
#   REQ_CPUS -- (in) baseline minimum CPU count
#   REQ_CPUS_POSTGRESQL -- (in) additional required CPUs for internal postgresql.
#   REQ_CPUS_PER_BDBA -- (in) for BDBA, the first container counts double.
# Arguments:
#   None
# Returns:
#   true if minimum requirements are known to be met.
################################################################
# shellcheck disable=SC2155,SC2046
check_cpu_count() {
    if [[ -z "$CPU_COUNT" ]]; then
        echo "Checking CPU count..."

        local -i cpu_requirement="$REQ_CPUS"
        if is_postgresql_container_running ; then
            cpu_requirement+="$REQ_CPUS_POSTGRESQL"
        fi
        if is_binary_scanner_container_running ; then
            # Use '$' to avoid https://github.com/koalaman/shellcheck/issues/1705
            cpu_requirement+="$REQ_CPUS_PER_BDBA * $BINARY_SCANNER_CONTAINER_COUNT"
        fi

        local -r CPUINFO_FILE="/proc/cpuinfo"
        if have_command lscpu ; then
            readonly CPU_COUNT="$(lscpu -p=cpu | grep -aFvc '#')"
            local status=$(echo_passfail $([[ "${CPU_COUNT}" -ge "${cpu_requirement}" ]]; echo "$?"))
            readonly CPU_COUNT_STATUS="CPU count $status.  ${CPU_COUNT} found, ${cpu_requirement} required."
        elif [[ -r "${CPUINFO_FILE}" ]]; then
            readonly CPU_COUNT="$(grep -ac '^processor' "${CPUINFO_FILE}")"
            local status=$(echo_passfail $([[ "${CPU_COUNT}" -ge "${cpu_requirement}" ]]; echo "$?"))
            readonly CPU_COUNT_STATUS="CPU count $status.  ${CPU_COUNT} found, ${cpu_requirement} required."
        elif have_command sysctl && is_macos ; then
            readonly CPU_COUNT="$(sysctl -n hw.ncpu)"
            local status=$(echo_passfail $([[ "${CPU_COUNT}" -ge "${cpu_requirement}" ]]; echo "$?"))
            readonly CPU_COUNT_STATUS="CPU count $status.  ${CPU_COUNT} found, ${cpu_requirement} required."
        else
            readonly CPU_COUNT="$UNKNOWN"
            readonly CPU_COUNT_STATUS="CPU count is $UNKNOWN"
        fi
    fi

    check_passfail "${CPU_COUNT_STATUS}"
}

################################################################
# Expose physical memory information.
#
# Globals:
#   MEMORY_INFO -- (out) text memory summary or an error message
# Arguments:
#   None
# Returns:
#   None
################################################################
get_memory_info() {
    if [[ -z "${MEMORY_INFO}" ]]; then
        echo "Retrieving memory information..."
        if have_command free ; then
            readonly MEMORY_INFO="$(free -h)"
        elif have_command sysctl && is_macos ; then
            readonly MEMORY_INFO="$(sysctl -n hw.memsize)"
        else
            readonly MEMORY_INFO="Memory information is $UNKNOWN -- free not found."
        fi
    fi
}

################################################################
# Check whether sufficient memory is available on this host.
#
# Globals:
#   SUFFICIENT_RAM -- (out) system memory in GB
#   SUFFICIENT_RAM_STATUS -- (out) PASS/FAIL text status message
#   REQ_RAM_GB -- (in) int baseline required memory in GB
#   REQ_RAM_GB_POSTGRESQL -- (in) int additional memory for database
#   REQ_RAM_GB_PER_BDBA -- (in) int BDBA memory for each container
#   REQ_RAM_GB_REDIS_SENTINEL -- (in) additional mem for sentinal mode
# Arguments:
#   None
# Returns:
#   true if minimum requirements are known to have been met.
################################################################
# shellcheck disable=SC2155,SC2046
check_sufficient_ram() {
    if [[ -z "${SUFFICIENT_RAM}" ]]; then
        echo "Checking whether sufficient RAM is present..."

        local -i required="$REQ_RAM_GB"
        local description=
        if is_postgresql_container_running ; then
            required+="$REQ_RAM_GB_POSTGRESQL"
            description="an internal postgresql instance"
        fi
        if is_binary_scanner_container_running ; then
            # Use '$' to avoid https://github.com/koalaman/shellcheck/issues/1705
            required+="$REQ_RAM_GB_PER_BDBA * ($BINARY_SCANNER_CONTAINER_COUNT + 1)"
            description+="${description:+, }Binary Analysis enabled"
        fi
        if is_redis_sentinel_mode_enabled ; then
            required+="$REQ_RAM_GB_REDIS_SENTINEL"
            description+="${description:+ and }Redis sentinel mode selected"
        fi
        description="required when all containers are on a single node${description:+ with $description}."

        if have_command free ; then
            # free usually under-reports physical memory by 1GB
            readonly SUFFICIENT_RAM="$(free -g | grep -aF 'Mem' | awk -F' ' '{print $2 + 1}')"
            local status="$(echo_passfail $([[ "${SUFFICIENT_RAM}" -ge "${required}" ]]; echo "$?"))"
            readonly SUFFICIENT_RAM_STATUS="Total RAM: $status. ${required}GB ${description}"
        elif have_command sysctl && is_macos ; then
            readonly SUFFICIENT_RAM="$(( $(sysctl -n hw.memsize) / 1073741824 ))"
            local status="$(echo_passfail $([[ "${SUFFICIENT_RAM}" -ge "${required}" ]]; echo "$?"))"
            readonly SUFFICIENT_RAM_STATUS="Total RAM: $status. ${required}GB ${description}"
        else
            readonly SUFFICIENT_RAM="$UNKNOWN"
            readonly SUFFICIENT_RAM_STATUS="Total RAM is $UNKNOWN. ${required}GB ${description}"
        fi
    fi

    check_passfail "${SUFFICIENT_RAM_STATUS}"
}

################################################################
# Hint about potential performance problems caused by I/O
# scheduling.
#
# Globals:
#   IOSCHED_STATUS -- (out) PASS/FAIL status message
#   IOSCHED_INFO -- (out) I/O scheduler information
#   IOSCHED_DESCRIPTION -- (out) explanation of I/O schedulng
# Arguments:
#   None
# Returns:
#   None
################################################################
check_iosched() {
    if [[ -z "${IOSCHED_STATUS}" ]]; then
        echo "Checking I/O scheduling..."
        readonly IOSCHED_INFO="$(set +o noglob; grep '' /sys/block/*/queue/scheduler 2>/dev/null | sed -e 's/^/ - /' -e 's/:/: /')"
        if [[ -n "$IOSCHED_INFO" ]]; then
            if echo "$IOSCHED_INFO" | grep -aFq '[cfq]'; then
                readonly IOSCHED_STATUS="$WARN: the cfq scheduler is in use somewhere.  See 'I/O_SCHEDULING' below."
            else
                readonly IOSCHED_STATUS="$UNKNOWN: no obvious I/O scheduler problems detected, but see 'IO_SCHEDULING' below."
            fi

            # I/O scheduling exists on this system.  Give some general advice,
            # a la https://access.redhat.com/solutions/5427
            readonly IOSCHED_DESCRIPTION=$(cat <<'EOF'
I/O_SCHEDULING: Although no one setting is best for everyone, some
  Linux I/O schedulers perform better than others for our product.
  Please review your system to see whether the schedulers used for
  Black Duck container storage are appropriate for your hardware,
  particularly for the postgres, redis, and rabbitmq services.  If you
  have HDD storage you might want to use the 'deadline' scheduler
  rather than the 'cfq' scheduler, and for SSDs we recommend the
  'noop' scheduler.  Your operating system and hardware vendors should
  by able to give more detailed guidelines.

  Note that some virtual machines and very fast devices bypass kernel
  I/O scheduling entirely and use 'none' to submit requests directly
  to the device.  Do not change those settings!
EOF
)
        else
            readonly IOSCHED_STATUS="$UNKNOWN: no /sys/block/*/queue/scheduler files found."
            readonly IOSCHED_DESCRIPTION=
        fi
    fi
}

################################################################
# Hint about potential performance problems caused by hyperthreading
#
# Globals:
#   HYPERTHREADING_STATUS -- (out) untagged/WARN status message
#   HYPERTHREADING_INFO -- (out) hyperthreading information
#   HYPERTHREADING_DESCRIPTION -- (out) explanation of hyperthreading
# Arguments:
#   None
# Returns:
#   None
################################################################
check_hyperthreading() {
    if [[ -z "${HYPERTHREADING_STATUS}" ]]; then
        echo "Checking hyperthreading..."
        if have_command sysctl && is_macos; then
            readonly HYPERTHREADING_INFO="$(sysctl hw.physicalcpu hw.logicalcpu | sed -e 's/^/ - /')"
            # shellcheck disable=SC2155 # We don't care about the subcommand exit status.
            local physical="$(echo "$HYPERTHREADING_INFO" | grep -aF physical | cut -d' ' -f4)"
            # shellcheck disable=SC2155 # We don't care about the subcommand exit status.
            local logical="$(echo "$HYPERTHREADING_INFO" | grep -aF logical | cut -d' ' -f4)"
            if [[ "$logical" -le 0 ]] || [[ "$physical" -le 0 ]] ; then
                readonly HYPERTHREADING_STATUS="$UNKNOWN.  See 'HYPERTHREADING' below."
            elif [[ "$logical" -gt "$physical" ]] ; then
                readonly HYPERTHREADING_STATUS="$WARN: hyperthreading appears to be enabled.  See 'HYPERTHREADING' below."
            else
                readonly HYPERTHREADING_STATUS="hyperthreading does not appear to be enabled."
            fi
        elif [[ -r /sys/devices/system/cpu/smt/active ]]; then
            # shellcheck disable=SC2155 # We don't care about the subcommand exit status.
            local setting="$(cat /sys/devices/system/cpu/smt/active)"
            readonly HYPERTHREADING_INFO=" - /sys/devices/system/cpu/smt/active: $setting"
            if [[ "$setting" != "0" ]]; then
                readonly HYPERTHREADING_STATUS="$WARN: hyperthreading appears to be enabled.  See 'HYPERTHREADING' below."
            else
                readonly HYPERTHREADING_STATUS="hyperthreading does not appear to be enabled."
            fi
        elif is_root && have_command dmidecode; then
            # We can't tell whether HT is actually on, but we can tell if the processor supports it.
            # shellcheck disable=SC2155 # We don't care about the subcommand exit status.
            local setting="$(demidecode -t processor | grep -aF HTT | sed -e 's/^ *//' | uniq)"
            if [[ -n "$setting" ]]; then
                readonly HYPERTHREADING_STATUS="$UNKNOWN, but your hardware supports hyperthreading.  See 'HYPERTHREADING' below if it is enabled."
                readonly HYPERTHREADING_INFO=" = dmidecode -t processor: $setting"
            else
                readonly HYPERTHREADING_STATUS="your hardware does not appear to support hyperthreading."
                readonly HYPERTHREADING_INFO=""
            fi
        else
            readonly HYPERTHREADING_STATUS="$UNKNOWN: could not find processor information.  See 'HYPERTHREADING' below."
        fi

        if [[ "$HYPERTHREADING_STATUS" =~ HYPERTHREADING ]]; then
            readonly HYPERTHREADING_DESCRIPTION=$(cat <<'EOF'
HYPERTHREADING: Empirical testing has shown that Black Duck performs
  better on some systems when hyperthreading is disabled.  If you want
  to carefully tune your system to maximize performance you should
  test whether hyperthreading makes a significant difference in your
  environment with typical workloads.  Be sure to repeat the testing
  periodically with new Black Duck releases.
EOF
)
        else
            readonly HYPERTHREADING_DESCRIPTION=
        fi
    fi
}

################################################################
# Expose disk space summary.
#
# Globals:
#   DISK_SPACE -- (out) text full disk space usage report
#   DISK_SPACE_TOTAL -- (out) text local real disk space summary
#   DISK_SPACE_STATUS -- (out) PASS/FAIL status messages.
#   REQ_DISK_GB -- (in) int required disk space in gigabytes
#   REQ_DISK_GB_PER_BDBA -- (in) int disk space for each BDBA container
# Arguments:
#   None
# Returns:
#   true if disk space is known and meets minimum requirements
################################################################
# shellcheck disable=SC2155,SC2046
check_disk_space() {
    if [[ -z "${DISK_SPACE}" ]]; then
        echo "Checking disk space..."

        # Check total local space on the manager node (mostly for pre-installation checks)
        if have_command df ; then
            # This is unreliable because the customer can configure the docker volume drivers
            # to use remote storage, edit the yml files to use bind or tmpfs mounts, etc.
            # We're just measuring total local capacity, regardless of mount point or usage.
            local -i required="$REQ_DISK_GB"
            local description=""
            if is_binary_scanner_container_running ; then
                # Use '$' to avoid https://github.com/koalaman/shellcheck/issues/1705
                required+="$REQ_DISK_GB_PER_BDBA * $BINARY_SCANNER_CONTAINER_COUNT"
                description="when Binary Analysis is enabled"
            fi
            description="required${description:+ $description}."
            readonly DISK_SPACE="$(df -h)"
            if df --help 2>&1 | grep -aFq total ; then
                local -r df_cmd="df --total -l -x overlay -x tmpfs -x devtmpfs -x nullfs"
                readonly DISK_SPACE_TOTAL="$(${df_cmd} -h | grep -a '^total ')"
                local -r total="$(${df_cmd} -m | grep -a '^total ' | awk -F' ' '{print int($2/1024+.5)}')"
            else
                # This is a bit wrong for apfs volumes sharing the same container
                local df_cmd="df -T nooverlay,tmpfs,devtmpfs,nullfs,dev"
                if have_command lsvfs; then df_cmd+=,$(lsvfs | tail -n +3 | grep -vaF local | cut -d' ' -f1 | tr '\n' ','); fi
                readonly DISK_SPACE_TOTAL="$(${df_cmd} -m | awk -F' ' '{total=total+$2;used=used+$3;avail=avail+$4} END {printf ("total\t%dGi\t%dGi\t%dGi\t%d%%\n",int(total/1024+.5),int(used/1024+.5),int(avail/1024+.5),int(used*100/total+.5))}')"
                local -r total="$(${df_cmd} -m | awk -F' ' '{total=total+$2} END {print int(total/1024+.5)}')"
            fi
            local status="$(echo_passfail $([[ "${total}" -ge "${required}" ]]; echo "$?"))"
            DISK_SPACE_STATUS="Local disk space $status. Found ${total}GB in total, ${required}GB ${description}"
        else
            readonly DISK_SPACE="Disk space is $UNKNOWN -- df not found."
            readonly DISK_SPACE_TOTAL="$UNKNOWN"
            DISK_SPACE_STATUS="Local disk space check is $UNKNOWN -- df not found."
        fi

        # Check free space in local containers.  Don't go overboard checking all volumes,
        # as normally they are all mapped from the same filesystem on the host and will
        # just repeat the same result over and over.
        if is_docker_usable ; then
            local data
            data="$(echo_container_space "blackducksoftware/blackduck-postgres:" "Postgresql" 25 /bitnami/postgresql/data)"
            if [[ -n "$data" ]]; then
                DISK_SPACE_STATUS+=$'\n'"$data"
            fi

            data="$(echo_container_space "blackducksoftware/blackduck-logstash:" "Log" 10 /var/lib/logstash/data)"
            if [[ -n "$data" ]]; then
                DISK_SPACE_STATUS+=$'\n'"$data"
            fi

            data="$(echo_container_space "blackducksoftware/blackduck-registration:" "Registration" 1 /opt/blackduck/hub/hub-registration/config)"
            if [[ -n "$data" ]]; then
                DISK_SPACE_STATUS+=$'\n'"$data"
            fi

            data="$(echo_container_space "blackducksoftware/blackduck-storage:" "Storage" 10 /opt/blackduck/hub/uploads)"
            if [[ -n "$data" ]]; then
                DISK_SPACE_STATUS+=$'\n'"$data"
            fi
        fi
        readonly DISK_SPACE_STATUS
    fi

    check_passfail "${DISK_SPACE_STATUS}"
}

################################################################
# Check disk space in a container.  Echos status to stdout.
#
# Globals:
#   None
# Arguments:
#   $1 - image name or container id; regex and partial matches are allowed
#   $2 - pretty container name
#   $3 - minimum free space, in GB
#   $4 - path into partition of interest
# Returns:
#   None
################################################################
echo_container_space() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -eq 4 ]] || error_exit "usage: $FUNCNAME <pattern> <name> <min-avail> <path>"
    local -r image="$1"
    local -r name="$2"
    local -r min_avail="$3"
    local -r path="$4"
    local -r min_size="-1" # Not used yet

    is_docker_usable || return 1

    # shellcheck disable=SC2155 # We don't care about the subcommand exit status.
    local data="$(docker_exec "$image" sh -c "df -mP $path" | tail -n +2 | tail -1)"
    if [[ -n "$data" ]]; then
        # shellcheck disable=SC2034 # some of these variables are unused.
        read -r fs size used avail percent mount <<< "$data"
        size="$(( (size+512) / 1024 ))"
        used="$(( (used+512) / 1024 ))"
        avail="$(( (avail+512) / 1024 ))"
        if [[ "$avail" -lt "${min_avail}" ]]; then
            echo "$name container disk space $FAIL -- available free space ${avail}GB is less than ${min_avail}GB"
        elif [[ "${percent%\%}" -ge 95 ]]; then
            echo "$name container disk space $FAIL -- ${used}GB of ${size}GB used ($percent), ${avail}GB available"
        elif [[ "${percent%\%}" -ge 90 ]]; then
            echo "$name container disk space $WARN -- ${used}GB of ${size}GB used ($percent), ${avail}GB available"
        elif [[ "$min_size" -gt 0 ]] && [[ "$size" -lt "$min_size" ]]; then
            echo "$name container disk space $WARN -- total size ${used}GB is less than ${min_size}GB"
        else
            echo "$name container disk space $PASS -- ${used}GB of ${size}GB used ($percent), ${avail}GB available"
        fi
    fi
}

################################################################
# Execute a command in a container, echoing the results to
# stdout/stderr.  This is intended to extend "docker exec" to also
# accept a regex or partial match for the container's image name.
# Docker options should precede the image/container pattern.
#
# Globals:
#   None
# Arguments:
#   $@ - per "docker exec", but with a generalized container id.
# Returns:
#   Non-zero if the command could not be run, otherwise the
#   command's exit status.
################################################################
docker_exec() {
    # Parse options until we find the image pattern.
    local options=()
    local pattern=
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --detach-keys)  options+=("$1" "$2"); shift 2;;
            -e | --env)     options+=("$1" "$2"); shift 2;;
            -u | --user)    options+=("$1" "$2"); shift 2;;
            -w | --workdir) options+=("$1" "$2"); shift 2;;
            -*)             options+=("$1"); shift;;
            *)              pattern="$1"; shift; break;;
        esac
    done
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ -n "$pattern" && $# -gt 0 ]] || error_exit "usage: $FUNCNAME [<option> ...] <pattern> <command> [<arg> ...]"

    # Quit now if we can't run docker commands
    is_docker_usable || return 1

    # Get the first matching container's id.
    # shellcheck disable=SC2155 # We don't care about the subcommand exit status.
    local id="$(docker ps --format "{{.ID}} {{.Image}}" | grep -a "$pattern" | cut -d' ' -f1 | head -1)"
    [[ -n "$id" ]] || return 2

    # Execute the command.
    docker exec ${options[0]+"${options[@]}"} "$id" ${1+"$@"}
}

################################################################
# Get a list of installed packages.
#
# Globals:
#   PACKAGE_LIST -- (out) text package information or an error message.
#   ANTI_VIRUS_PACKAGE_STATUS -- (out) PASS/FAIL status message.
#   ANTI_VIRUS_PACKAGE_MESSAGE -- (out) text explanation of status.
# Arguments:
#   None
# Returns:
#   None
################################################################
# shellcheck disable=SC2155 # We don't care about the subcommand exit codes
get_package_list() {
    if [[ -z "${PACKAGE_LIST}" ]]; then
        echo "Getting installed package list..."

        # Try various known package maangers.
        if have_command pkgutil ; then
            readonly PACKAGE_LIST="$(pkgutil --pkgs | sort)"
        elif have_command rpm ; then
            readonly PACKAGE_LIST="$(rpm -qa | sort)"
        elif have_command apt ; then
            readonly PACKAGE_LIST="$(apt list --installed | sort)"
        elif have_command dpkg ; then
            readonly PACKAGE_LIST="$(dpkg --get-selections | grep -aFv deinstall)"
        elif have_command apk ; then
            readonly PACKAGE_LIST="$(apk info -v | sort)"
        else
            readonly PACKAGE_LIST="Package list is $UNKNOWN -- could not determine package manager"
        fi

        # Scan for known anti-virus packages.
        local avprods=
        local avpkgs=
        local matches
        for entry in "${MALWARE_SCANNER_PACKAGES[@]}"; do
            local product="${entry%%=*}"
            local regex="${entry#*=}"
            matches=$(echo "$PACKAGE_LIST" | grep -aE "^$regex")
            if [[ -n "$matches" ]]; then
                avprods+="${product//_/ } "
                avpkgs+="-- ${product//_/ }"$'\n'"$matches"$'\n'
            fi
        done
        if [[ -n "$avprods" ]]; then
            readonly ANTI_VIRUS_PACKAGE_STATUS="$WARN: anti-virus scanners detected.  See 'ANTIVIRUS_SCANNERS' below."
            readonly ANTI_VIRUS_PACKAGE_MESSAGE=$(cat <<END

ANTIVIRUS_SCANNERS: some anti-virus scanners can significantly reduce
  database performance or cause the system to run out of file
  descriptors.

RECOMMENDATION: verify that your anti-virus software is not scanning
  the postgresql data directory.  If you are having problems try
  disabling the anti-virus software temporarily.

DETAILS: $avprods
$avpkgs

------------------------------------------

END
)
        else
            readonly ANTI_VIRUS_PACKAGE_STATUS="$PASS: No anti-virus packages detected"
            readonly ANTI_VIRUS_PACKAGE_MESSAGE=""
        fi
    fi
}

################################################################
# Get information about network interfaces.
#
# Globals:
#   IFCONFIG_DATA -- (out) text interface data, or an error message.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_interface_info() {
    if [[ -z "${IFCONFIG_DATA}" ]]; then
        echo "Getting network interface configuration..."
        if have_command ifconfig ; then
            readonly IFCONFIG_DATA="$(ifconfig -a)"
        else
            readonly IFCONFIG_DATA="Network configuration is $UNKNOWN -- ifconfig not found."
        fi
    fi
}

################################################################
# Get IP routing information
#
# Globals:
#   ROUTING_TABLE -- (out) routing info or an error message.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_routing_info() {
    if [[ -z "${ROUTING_TABLE}" ]]; then
        echo "Getting IP routing table..."
        if have_command netstat ; then
            readonly ROUTING_TABLE="$(netstat -nr)"
        elif have_command ip ; then
            readonly ROUTING_TABLE="$(ip route list)"
        else
            readonly ROUTING_TABLE="IP routing information is $UNKNOWN"
        fi
    fi
}

################################################################
# Get network bridge information
#
# Globals:
#   BRIDGE_INFO -- (out) network bridge info, or an error message.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_bridge_info() {
    if [[ -z "${BRIDGE_INFO}" ]]; then
        echo "Getting network bridge information..."
        if have_command brctl && ! is_macos ; then
            readonly BRIDGE_INFO="$(brctl show)"
        elif have_command bridge ; then
            readonly BRIDGE_INFO="$(bridge link show)"
        else
            readonly BRIDGE_INFO="Network bridge information is $UNKNOWN"
        fi
    fi
}

################################################################
# Get a list of active network ports.
#
# Globals:
#   LISTEN_PORTS -- (out) text port info, or an error message.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_ports() {
    if [[ -z "${LISTEN_PORTS}" ]]; then
        echo "Getting network ports..."
        if have_command netstat ; then
            readonly LISTEN_PORTS="$(netstat -lnp 2>/dev/null || netstat -ln)"
        else
            readonly LISTEN_PORTS="Network ports are $UNKNOWN -- netstat not found."
        fi
    fi
}

################################################################
# Probe iptables for specific ports that are important to Black Duck.
#
# Globals:
#   SPECIFIC_PORT_RESULTS -- (out) text summary
# Arguments:
#   None
# Returns:
#   None
################################################################
get_specific_ports() {
    if [[ -z "${SPECIFIC_PORT_RESULTS}" ]]; then
        echo "Getting important port status..."
        readonly SPECIFIC_PORT_RESULTS="$(cat <<END
$(echo_port_status 443)
$(echo_port_status 8000)
$(echo_port_status 8888)
$(echo_port_status 8983)
$(echo_port_status 16543)
$(echo_port_status 16544)
$(echo_port_status 16545)
$(echo_port_status 17543)
$(echo_port_status 55436)
END
        )"
    fi
}

################################################################
# Get firewall rules for a port.  Results are echoed to stdout.
#
# Globals:
#   None
# Arguments:
#   $1 - port number
# Returns:
#   None
################################################################
# shellcheck disable=SC2155,SC2046
# shellcheck disable=SC2030,SC2031 # False positives; see https://github.com/koalaman/shellcheck/issues/1409
echo_port_status() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -eq 1 ]] || error_exit "usage: $FUNCNAME <port>"
    local -r port="$1"

    echo -n "${port}: "
    if ! have_command iptables ; then
        echo "Port $port status is $UNKNOWN -- iptables not found."
        return
    elif ! is_root ; then
        echo "Port $port status is $UNKNOWN -- requires root access."
        return
    fi

    local -r non_nat_rule_results="$(iptables --list -n | grep -a "$port")"
    local -r non_nat_result_found="$(echo_boolean "$([[ -n "${non_nat_rule_results}" ]]; echo "$?")")"

    local -r nat_rule_results="$(iptables -t nat --list -n | grep -a "$port")"
    local -r nat_result_found="$(echo_boolean "$([[ -n "${nat_rule_results}" ]]; echo "$?")")"

    if ! check_boolean "${non_nat_result_found}" && ! check_boolean "${nat_result_found}" ; then
        echo "no specific rules found in the NAT or regular chains."
        return
    fi

    # Check for Accept/Reject against the non nat result
    if check_boolean "${non_nat_result_found}"; then
        local non_nat_accept="$(echo_boolean $([[ "${non_nat_rule_results}" =~ ACCEPT ]]; echo "$?"))"
        local non_nat_reject="$(echo_boolean $([[ "${non_nat_rule_results}" =~ REJECT ]]; echo "$?"))"
        local non_nat_drop="$(echo_boolean $([[ "${non_nat_rule_results}" =~ DROP ]]; echo "$?"))"
        echo "non-NAT iptables entries found: ACCEPT: ${non_nat_accept}, REJECT: ${non_nat_reject}, DROP: ${non_nat_drop}"
    else
        echo "No non-NAT iptables entries found"
    fi
    if check_boolean "${nat_result_found}" ; then
        local nat_accept="$(echo_boolean $([[ "${nat_rule_results}" =~ ACCEPT ]]; echo "$?"))"
        local nat_reject="$(echo_boolean $([[ "${nat_rule_results}" =~ REJECT ]]; echo "$?"))"
        local nat_drop="$(echo_boolean $([[ "${nat_rule_results}" =~ DROP ]]; echo "$?"))"
        echo "NAT iptables entries found: ACCEPT: ${nat_accept}, REJECT: ${nat_reject}, DROP: ${nat_drop}"
    else
        echo "No NAT iptables entries found"
    fi
}

################################################################
# Check critical IPV4 sysctl values on linux
#
# Globals:
#   SYSCTL_IP_FORWARDING_STATUS -- (out) PASS/FAIL ip_forward status message
#   SYSCTL_KEEPALIVE_TIME -- (out) - The current keepalive time
#   SYSCTL_KEEPALIVE_INTERVAL -- (out) - The current keepalive interval
#   SYSCTL_KEEPALIVE_PROBES -- (out) - The current number of keepalive probes
#   SYSCTL_KEEPALIVE_TIME_STATUS -- (out) PASS/FAIL status message
#   IPVS_TIMEOUTS -- (out) The current IPVS timeout settings.
#   IPVS_TIMEOUT_STATUS -- (out) PASS/FAIL status message
#   TCP_KEEPALIVE_TIMEOUT_DESC -- (out) explanation of keepalive timeouts.
# Arguments:
#   None
# Returns:
#   None
################################################################
# shellcheck disable=SC2046,SC2155
get_sysctl_keepalive() {
    if [[ -z "${SYSCTL_KEEPALIVE_TIME_STATUS}" ]] ; then
        if ! is_linux ; then
            readonly SYSCTL_IP_FORWARDING_STATUS="$UNKNOWN -- non-linux system"
            readonly SYSCTL_KEEPALIVE_TIME="Can't check sysctl keepalive on non-linux system."
            readonly SYSCTL_KEEPALIVE_INTERVAL="Can't check sysctl keepalive on non-linux system."
            readonly SYSCTL_KEEPALIVE_PROBES="Can't check sysctl keepalive on non-linux system."
            readonly SYSCTL_KEEPALIVE_TIME_STATUS="$UNKNOWN -- non-linux system"
            readonly IPVS_TIMEOUTS="$UNKNOWN -- non-linux system"
            readonly IPVS_TIMEOUT_STATUS="$UNKNOWN -- non-linux system"
            readonly TCP_KEEPALIVE_TIMEOUT_DESC=
            return
        fi

        if ! have_command ipvsadm ; then
            readonly IPVS_TIMEOUTS="$UNKNOWN -- ipvsadm not found."
        elif ! is_root ; then
            readonly IPVS_TIMEOUTS="$UNKNOWN -- requires root access."
        else
            readonly IPVS_TIMEOUTS="$(ipvsadm -l --timeout)"
            local ipvs_tcp_timeout="$(ipvsadm -l --timeout | awk '{print $5}')"
        fi

        if ! have_command sysctl ; then
            readonly SYSCTL_IP_FORWARDING_STATUS="$UNKNOWN -- sysctl not found"
            readonly SYSCTL_KEEPALIVE_TIME="Can't check sysctl keepalive, sysctl not found."
            readonly SYSCTL_KEEPALIVE_INTERVAL="Can't check sysctl keepalive intervale, sysctl not found."
            readonly SYSCTL_KEEPALIVE_PROBES="Can't check sysctl keepalive count, sysctl not found."
            readonly SYSCTL_KEEPALIVE_TIME_STATUS="$UNKNOWN -- sysctl not found"
            readonly IPVS_TIMEOUT_STATUS="$UNKNOWN -- sysctl not found"
            readonly TCP_KEEPALIVE_TIMEOUT_DESC=
            return
        fi

        echo "Checking sysctl ip_forward parameter..."
        readonly ip_forward=$(sysctl net.ipv4.ip_forward | awk -F' = ' '{print $2}')
        if [[ "$ip_forward" -eq 0 ]]; then
            readonly SYSCTL_IP_FORWARDING_STATUS="$FAIL: net.ipv4.ip_forward is ${ip_forward}.  Docker will not be able to bind addresses."
        else
            readonly SYSCTL_IP_FORWARDING_STATUS="$PASS: net.ipv4.ip_forward is ${ip_forward}"
        fi

        echo "Checking sysctl keepalive parameters..."
        readonly SYSCTL_KEEPALIVE_TIME=$(sysctl net.ipv4.tcp_keepalive_time | awk -F' = ' '{print $2}')
        readonly SYSCTL_KEEPALIVE_INTERVAL=$(sysctl net.ipv4.tcp_keepalive_intvl | awk -F' = ' '{print $2}')
        readonly SYSCTL_KEEPALIVE_PROBES=$(sysctl net.ipv4.tcp_keepalive_probes | awk -F' = ' '{print $2}')

        if [[ "${SYSCTL_KEEPALIVE_TIME}" -lt "${REQ_MIN_SYSCTL_KEEPALIVE_TIME}" ]] || [[ "${SYSCTL_KEEPALIVE_TIME}" -gt "${REQ_MAX_SYSCTL_KEEPALIVE_TIME}" ]] ; then
            readonly SYSCTL_KEEPALIVE_TIME_STATUS="$WARN: tcp keepalive time ${SYSCTL_KEEPALIVE_TIME} should be between ${REQ_MIN_SYSCTL_KEEPALIVE_TIME} and ${REQ_MAX_SYSCTL_KEEPALIVE_TIME}.  See 'TCP_KEEPALIVE_TIMEOUTS' below."
        else
            readonly SYSCTL_KEEPALIVE_TIME_STATUS="$PASS"
        fi

        if [[ -z "${ipvs_tcp_timeout}" ]] ; then
            readonly IPVS_TIMEOUT_STATUS="$UNKNOWN.  See 'TCP_KEEPALIVE_TIMEOUTS' below."
        elif [[ "${SYSCTL_KEEPALIVE_TIME}" -lt "${ipvs_tcp_timeout}" ]] ; then
            readonly IPVS_TIMEOUT_STATUS="$PASS"
        elif is_swarm_enabled ; then
            readonly IPVS_TIMEOUT_STATUS="$FAIL: tcp keepalive time ${SYSCTL_KEEPALIVE_TIME} must be less than ipvs tcp timeout ${ipvs_tcp_timeout}.  See 'TCP_KEEPALIVE_TIMEOUTS' below."
        else
            readonly IPVS_TIMEOUT_STATUS="$WARN: tcp keepalive time ${SYSCTL_KEEPALIVE_TIME} should be less than ipvs tcp timeout ${ipvs_tcp_timeout}.  See 'TCP_KEEPALIVE_TIMEOUTS' below."
        fi

        if [[ "$IPVS_TIMEOUT_STATUS" != "$PASS" ]] || [[ "$SYSCTL_KEEPALIVE_TIME_STATUS" != "$PASS" ]]; then
            read -r -d '' TCP_KEEPALIVE_TIMEOUT_DESC <<'EOF'
TCP_KEEPALIVE_TIMEOUTS: Linux has two related timeouts.  The
  tcp_keepalive_time from /etc/sysctl.conf triggers application code
  to send something on live but idle TCP connections, while the IPVS
  timeout from 'ipvsadm -l --timeout' controls how long the kernel
  allows idle virtual sockets to exist.  Unfortunately the default
  values for the two are not coordinated.  The default
  tcp_keepalive_time of 7200 seconds is larger than the default IPVS
  timeout of 900 seconds, so in docker setups using overlay networks
  like docker swarm TCP connections that stall for more than 15
  minutes (e.g. very slow database queries) are broken prematurely
  by the kernel, resulting in 'Connection reset' errors.  To avoid
  this make the tcp_keepalive_time smaller than the IPVS timeout.
  Values between 600 and 800 seconds work well.
EOF
        fi
        readonly TCP_KEEPALIVE_TIMEOUT_DESC
    fi
}

################################################################
# Report login manager settings
#
# Globals:
#   LOGINCTL_STATUS -- (out) PASS/FAIL status message
#   LOGINCTL_RECOMMENDATION -- (out) recommended remediation steps
#   LOGINCTL_INFO -- (out) detailed setting information
# Arguments:
#   None
# Returns:
#   None
################################################################
# shellcheck disable=SC2155 # We don't care about the subcommand exit code
get_loginctl_settings() {
    if [[ -z "${LOGINCTL_STATUS}" ]]; then
        if ! have_command loginctl ; then
            readonly LOGINCTL_STATUS="${UNKNOWN}: loginctl not found."
            readonly LOGINCTL_RECOMMENDATION=""
            readonly LOGINCTL_INFO=""
            return
        fi

        readonly LOGINCTL_INFO="$(loginctl -a show-session)"
        local idleAction="$(echo "${LOGINCTL_INFO}" | grep -aF 'IdleAction=' | cut -d'=' -f2)"
        local handleLidSwitch="$(echo "${LOGINCTL_INFO}" | grep -aF 'HandleLidSwitch=' | cut -d'=' -f2)"
        if have_command systemctl && systemctl list-unit-files --state=masked suspend.target hibernate.target | grep -aqF '2 unit files' ; then
            # loginctl settings don't matter, sleep and hibernate are hard disbled.
            readonly LOGINCTL_STATUS="${PASS}: systemctl suspend and hibernate targets are masked"
        elif ! echo "$LOGINCTL_INFO" | grep -aFq 'IdleAction' ; then
            readonly LOGINCTL_STATUS="${UNKNOWN}: loginctl did not report IdleAction"
        elif [[ "$idleAction" != "ignore" ]]; then
            readonly LOGINCTL_STATUS="${FAIL}: loginctl IdleAction is '$idleAction'.  See 'DISABLE_HIBERNATE' below."
        elif is_laptop && echo "$LOGINCTL_INFO" | grep -aFq 'HandleLidSwitch' && [[ "$handleLidSwitch" != "ignore" ]]; then
            # handleLidSwitch=suspend is present even on systems without a lid, so try to detect laptops.
            readonly LOGINCTL_STATUS="${FAIL}: loginctl handleLidSwitch is '$handleLidSwitch'.  See 'DISABLE_HIBERNATE' below."
        else
            readonly LOGINCTL_STATUS="${PASS}"
        fi

        if check_passfail "$LOGINCTL_STATUS" ; then
            readonly LOGINCTL_RECOMMENDATION=""
        else
            read -r -d '' LOGINCTL_RECOMMENDATION <<'EOF'

DISABLE_HIBERNATE: Black Duck is a background service and will not
  function properly if your system sleeps or suspends itself when all
  console sessions are idle.  Some ways to prevent that are to run:

    systemctl mask --now suspend.target hibernate.target

  or edit /etc/systemd/logind.conf to set IdleAction (and the various
  HandleLidSwitch options if applicable, although we do not recommend
  installing the product on laptops) to 'ignore'.  If installed the
  desktop might also have an app for changing power management settings.

  See also 'HIBERNATING_CLIENTS'.
EOF
            readonly LOGINCTL_RECOMMENDATION
        fi
    fi
}

################################################################
# Get a list of running processes.
#
# Globals:
#   RUNNING_PROCESSES -- (out) text process list, or an error message.
#   ANTI_VIRUS_PROCESS_STATUS -- (out) PASS/FAIL status message.
#   ANTI_VIRUS_PROCESS_MESSAGE -- (out) text explanation of status.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_processes() {
    if [[ -z "${RUNNING_PROCESSES}" ]]; then
        echo "Getting running processes..."
        if have_command ps ; then
            readonly RUNNING_PROCESSES="$(ps aux)"
        else
            readonly RUNNING_PROCESSES="Processes list is $UNKNOWN -- ps not found."
        fi

        # Scan for some known anti-virus process names
        local avprods=
        local avprocs=
        local matches
        for entry in "${MALWARE_SCANNER_PROCESSES[@]}"; do
            local product="${entry%%=*}"
            local regex="${entry#*=}"
            matches=$(echo "$RUNNING_PROCESSES" | grep -aE "[ /]$regex")
            if [[ -n "$matches" ]]; then
                avprods+="${product//_/ } "
                avprocs+="-- ${product//_/ }"$'\n'"$matches"$'\n'
            fi
        done
        if [[ -n "$avprods" ]]; then
            readonly ANTI_VIRUS_PROCESS_STATUS="$WARN: anti-virus scanners detected.  See 'ANTIVIRUS_SCANNERS' below."
            readonly ANTI_VIRUS_PROCESS_MESSAGE=$(cat <<END

ANTIVIRUS_SCANNERS: some anti-virus scanners can significantly reduce
  database performance or cause the system to run out of file
  descriptors.

RECOMMENDATION: verify that your anti-virus software is not scanning
  the postgresql data directory.  If you are having problems try
  disabling the anti-virus software temporarily.

DETAILS: $avprods
$avprocs

------------------------------------------

END
)
        else
            readonly ANTI_VIRUS_PROCESS_STATUS="$PASS: No anti-virus processes detected"
            readonly ANTI_VIRUS_PROCESS_MESSAGE=""
        fi
    fi
}

################################################################
# Test whether docker is installed.
#
# Globals:
#   IS_DOCKER_PRESENT -- (out) TRUE/FALSE result.
# Arguments:
#   None
# Returns:
#   true if docker is present.
################################################################
is_docker_present() {
    if [[ -z "${IS_DOCKER_PRESENT}" ]]; then
        echo "Looking for docker..."
        readonly IS_DOCKER_PRESENT="$(echo_boolean "$(have_command docker ; echo "$?")")"
    fi

    check_boolean "${IS_DOCKER_PRESENT}"
}

################################################################
# Test whether we have access to docker.
#
# Globals:
#   IS_DOCKER_USABLE -- (out) TRUE/FALSE
# Arguments:
#   None
# Returns:
#   true if we can access docker
################################################################
is_docker_usable() {
    if [[ -z "${IS_DOCKER_USABLE}" ]]; then
        if is_docker_present && docker version >/dev/null 2>&1 ; then
            readonly IS_DOCKER_USABLE="$TRUE"
        else
            readonly IS_DOCKER_USABLE="$FALSE"
        fi
    fi

    check_boolean "${IS_DOCKER_USABLE}"
}

################################################################
# Check whether a supported version of docker is installed
#
# Globals:
#   DOCKER_VERSION -- (out) short docker client version.
#   DOCKER_EDITION -- (out) docker edition value, if known.
#   DOCKER_VERSION_INFO -- (out) full docker version information.
#   DOCKER_VERSION_CHECK -- (out) PASS/FAIL docker version is supported.
#   REQ_DOCKER_VERSIONS -- (in) supported docker versions.
# Arguments:
#   None
# Returns:
#   true if a supported version of docker is installed.
################################################################
# shellcheck disable=SC2155 # We don't care about the subcommand exit codes
check_docker_version() {
    if [[ -z "${DOCKER_VERSION_CHECK}" ]]; then
        if ! is_docker_present ; then
            readonly DOCKER_VERSION_CHECK="No docker version -- docker is not installed."
            return 1
        fi

        # Find the docker client version string.  Some possible outputs from "docker --version":
        #   "Docker version 18.03.1-ce, build 9ee9f40"
        #   "Docker version 18.09.4, build d14af54266"
        #   "Docker version 1.13.1, build b2f74b2/1.13.1"
        echo "Checking docker version..."
        readonly DOCKER_VERSION_INFO="$(docker version 2>/dev/null)"
        readonly DOCKER_VERSION="$(docker --version)"
        local docker_base_version="$(docker --version | cut -d' ' -f3 | cut -d. -f1-2)"
        if [[ ! "${REQ_DOCKER_VERSIONS}" =~ ${docker_base_version}.x ]]; then
            readonly DOCKER_VERSION_CHECK="$FAIL. Running ${DOCKER_VERSION}. Supported versions are: ${REQ_DOCKER_VERSIONS}"
        else
            readonly DOCKER_VERSION_CHECK="$PASS. ${DOCKER_VERSION} installed."
        fi

        # Try to find the edition.
        local edition="$(docker --version | cut -d' ' -f3 | cut -d- -f2 | cut -d, -f1)"
        if [[ "$edition" == "ee" ]] || [[ "$DOCKER_VERSION_INFO" =~ Enterprise ]] ; then
            readonly DOCKER_EDITION="$DOCKER_ENTERPRISE_EDITION"
        elif [[ "$edition" == "ce" ]] || [[ "$DOCKER_VERSION_INFO" =~ Community ]] ; then
            readonly DOCKER_EDITION="$DOCKER_COMMUNITY_EDITION"
        elif is_root && have_command rpm ; then
            local package="$(rpm -q --file "$(command -v docker)")"
            case "$package" in
                docker-ce-*)            readonly DOCKER_EDITION="$DOCKER_COMMUNITY_EDITION";;
                docker-ee-*)            readonly DOCKER_EDITION="$DOCKER_ENTERPRISE_EDITION";;
                docker-common-1.13.1-*) readonly DOCKER_EDITION="$DOCKER_LEGACY_EDITION";;
                *)                      readonly DOCKER_EDITION="$UNKNOWN ($package)";;
            esac
        else
            readonly DOCKER_EDITION="$UNKNOWN"
        fi
    fi

    check_passfail "${DOCKER_VERSION_CHECK}"
}

################################################################
# Check whether the version of docker installed is supported for the OS
# version that was detected
#
# For requirements see (under "Get Docker"):
#   https://docs.docker.com/install/linux/
#   https://docs.docker.com/docsarchive/
#   https://success.docker.com/article/compatibility-matrix
#
# Globals:
#   DOCKER_OS_COMPAT -- (out) PASS/FAIL Docker OS compatibility information
# Arguments:
#   None
# Returns:
#   true if a supported version of docker is installed.
################################################################
check_docker_os_compatibility() {
    if [[ -z "${DOCKER_OS_COMPAT}" ]] ; then
        [[ -n "${DOCKER_VERSION_CHECK}" ]] || check_docker_version
        [[ -n "${OS_NAME}" ]] || get_os_name

        DOCKER_OS_COMPAT="$PASS. No known compatibility problems detected for Docker ${DOCKER_EDITION} edition on ${OS_NAME_SHORT}"
        if [[ "${DOCKER_EDITION}" == "$DOCKER_COMMUNITY_EDITION" ]] ; then
            # shellcheck disable=SC2116 # Deliberate extra echo to collapse lines
            local -r have="$(echo "${OS_NAME}")"
            case "$have" in
                *Red\ Hat\ Enterprise*)
                    # Quoted from https://docs.docker.com/engine/install/rhel/
                    DOCKER_OS_COMPAT="$WARN: Docker currently only provide packages for RHEL on s390x (IBM Z). Other architectures are not yet supported for RHEL";;
                *CentOS\ Stream*)
                    if [[ ! "$have" =~ release\ [89] ]];  then
                        DOCKER_OS_COMPAT="$FAIL - unsupported OS version. To install Docker Engine, you need a maintained version of CentOS 7, CentOS 8 (stream), or CentOS 9 (stream). Archived versions aren’t supported or tested."
                    fi;;
                *CentOS*)
                    if [[ ! "$have" =~ release\ 7\. ]]; then
                        DOCKER_OS_COMPAT="$FAIL - unsupported OS version. To install Docker Engine, you need a maintained version of CentOS 7, CentOS 8 (stream), or CentOS 9 (stream). Archived versions aren’t supported or tested."
                    fi;;
                *Fedora\ release*)
                    # https://docs.docker.com/install/linux/docker-ce/fedora/#os-requirements lists
                    # specific 64-bit Fedora versions, but they change with each release.
                    local -r relnum="$(cut -d' ' -f3 < /etc/fedora-release)"
                    if have_command arch && [[ ! "$(arch)" == "x86_64" ]]; then
                        DOCKER_OS_COMPAT="$FAIL - unsupported arch $(arch). To install Docker, you need the 64-bit version of Fedora."
                    elif [[ "$relnum" =~ ^[0-9]+$ ]]; then
                        case "${DOCKER_VERSION}" in
                            *17.06*)
                                if [[ "$relnum" -lt 24 ]] || [[ "$relnum" -gt 25 ]]; then
                                    DOCKER_OS_COMPAT="$FAIL - unsupported OS version ${relnum}.  Docker CE 17.06 requires Fedora version 24 or 25."
                                fi;;
                            *17.09*)
                                if [[ "$relnum" -lt 25 ]] || [[ "$relnum" -gt 27 ]]; then
                                    DOCKER_OS_COMPAT="$FAIL - unsupported OS version ${relnum}.  Docker CE 17.09 requires Fedora version 25, 26, or 27."
                                fi;;
                            *17.12*)
                                if [[ "$relnum" -lt 26 ]] || [[ "$relnum" -gt 27 ]]; then
                                    DOCKER_OS_COMPAT="$FAIL - unsupported OS version ${relnum}.  Docker CE 17.12 requires Fedora version 26 or 27."
                                fi;;
                            *18.03* | *18.06* | *18.09*)
                                if [[ "$relnum" -lt 26 ]] || [[ "$relnum" -gt 28 ]]; then
                                    DOCKER_OS_COMPAT="$FAIL - unsupported OS version ${relnum}.  Docker CE 18.03 and later require Fedora version 26, 27, or 28."
                                fi;;
                        esac
                    fi;;
                *Oracle\ Linux*)
                    # See https://docs.docker.com/install/linux/docker-ee/oracle/
                    DOCKER_OS_COMPAT="$FAIL. Docker Community Edition (Docker CE) is not supported on Oracle Linux.";;
                *SUSE\ Linux\ Enterprise\ Server*)
                    DOCKER_OS_COMPAT="$FAIL. Docker Community Edition (Docker CE) is not supported on SLES.";;
            esac
        elif [[ "${DOCKER_EDITION}" == "$DOCKER_ENTERPRISE_EDITION" ]] ; then
            # shellcheck disable=SC2116 # Deliberate extra echo to collapse lines
            local -r have="$(echo "${OS_NAME}")"
            case "$have" in
                *Red\ Hat\ Enterprise*)
                    # See https://docs.docker.com/install/linux/docker-ee/rhel/
                    if [[ "$have" =~ 7\.0 ]] ; then
                        DOCKER_OS_COMPAT="$FAIL - unsupported o/s version. Docker EE supports RHEL 64-bit versions 7.1 and higher."
                    elif have_command arch && ! arch | grep -aE 'x86_64|s390x|ppc64le' ; then
                        DOCKER_OS_COMPAT="$FAIL - unsupported architecture $(arch). Docker EE supports RHEL x86_64, s390x, and ppc64le architectures."
                    elif is_docker_usable; then
                        local -r driver="$(docker info -f '{{.Driver}}')"
                        if [[ ! "$driver" == "devicemapper" ]] && [[ ! "$driver" == "overlay2" ]]; then
                            DOCKER_OS_COMPAT="$FAIL - unsupported storage driver ${driver}. Docker EE requires the use of the 'overlay2' or 'devicemapper' storage driver (in direct-lvm mode)."
                        elif [[ "$driver" == "devicemapper" ]] && docker info | grep -aqi 'Metadata file: ?.+$' ; then
                            # https://docs.docker.com/storage/storagedriver/device-mapper-driver/#configure-direct-lvm-mode-for-production
                            # says "Data file" and "Metadata file" will be empty in direct-lvm mode.
                            DOCKER_OS_COMPAT="$FAIL. Docker EE requires the 'devicemapper' storage driver to be in direct-lvm mode for production."
                        fi
                    fi;;
                *CentOS*)
                    # See https://docs.docker.com/install/linux/docker-ee/centos/
                    if [[ "$have" =~ 7\.0 ]]; then
                        DOCKER_OS_COMPAT="$FAIL - unsupported OS version. Docker EE supports Centos 64-bit, versions 7.1 and higher, running on x86_64."
                    elif have_command arch && [[ ! "$(arch)" == "x86_64" ]]; then
                        DOCKER_OS_COMPAT="$FAIL - architecture $(arch). Docker EE supports Centos 64-bit, versions 7.1 and higher, running on x86_64."
                    elif is_docker_usable; then
                        local -r driver="$(docker info -f '{{.Driver}}')"
                        if [[ ! "$driver" == "devicemapper" ]] && [[ ! "$driver" == "overlay2" ]]; then
                            DOCKER_OS_COMPAT="$FAIL - unsupported storage driver ${driver}. Docker EE requires the use of the 'overlay2' or 'devicemapper' storage driver (in direct-lvm mode)."
                        elif [[ "$driver" == "devicemapper" ]] && docker info | grep -aqi 'Metadata file: ?.+$' ; then
                            # https://docs.docker.com/storage/storagedriver/device-mapper-driver/#configure-direct-lvm-mode-for-production
                            # says "Data file" and "Metadata file" will be empty in direct-lvm mode.
                            DOCKER_OS_COMPAT="$FAIL. Docker EE requires the 'devicemapper' storage driver to be in direct-lvm mode for production."
                        fi
                    fi;;
                *Fedora\ release*)
                    DOCKER_OS_COMPAT="$FAIL. Docker EE is not supported on Fedora.";;
                *Oracle\ Linux*)
                    # See https://docs.docker.com/install/linux/docker-ee/oracle/
                    if [[ "$have" =~ 7\.[012]$ ]] ; then
                        DOCKER_OS_COMPAT="$FAIL - unsupported OS version. Docker EE supports Oracle Linux 64-bit, versions 7.3 and higher, running the Red Hat Compatible kernel (RHCK) 3.10.0-514 or higher. Older versions of Oracle Linux are not supported."
                    elif have_command uname && [[ "$(uname -r)" =~ uek ]]; then
                        # Docker does not support UEK, only RHCK.
                        DOCKER_OS_COMPAT="$FAIL - unsupported kernel. Docker EE supports Oracle Linux 64-bit, versions 7.3 and higher, running the Red Hat Compatible kernel (RHCK) 3.10.0-514 or higher."
                    elif is_docker_usable && [[ ! "$(docker info -f '{{.Driver}}')" == "devicemapper" ]] ; then
                        # Docker requires use of the devicemapper storage driver only on Oracle Linux.
                        DOCKER_OS_COMPAT="$FAIL. Docker EE requires the use of the 'devicemapper' storage driver on Oracle Linux."
                    elif is_docker_usable && docker info | grep -aqi 'Metadata file: ?.+$' ; then
                        # Docker requires the devicemapper storage driver to be in direct-lvm mode.
                        DOCKER_OS_COMPAT="$FAIL. Docker EE requires the 'devicemapper' storage driver do be in 'direct-lvm' mode on Oracle Linux."
                    fi;;
                *SUSE\ Linux\ Enterprise\ Server\ 12*)
                    if is_docker_usable && [[ ! "$(docker info -f '{{.Driver}}')" =~ [Bb]trfs ]] ; then
                        DOCKER_OS_COMPAT="$FAIL - unsupported storage driver $(docker info -f '{{.Driver}}'). The only supported storage driver for Docker EE on SLES is Btrfs."
                    elif have_command arch && ! arch | grep -aE 'x86_64|s390x|ppc64le' ; then
                        DOCKER_OS_COMPAT="$FAIL - unsupported architecture $(arch). Docker EE only supports the x86_64, s390x, and ppc64le architectures on the 64-bit version of SLES 12.x."
                    fi;;
                *SUSE\ Linux\ Enterprise\ Server*)
                    DOCKER_OS_COMPAT="$FAIL - unsupported o/s version. Docker EE only supports the x86_64, s390x, and ppc64le architectures on the 64-bit version of SLES 12.x.";;
                *openSUSE*)
                    # See https://docs.docker.com/install/linux/docker-ee/suse/#os-requirements
                    DOCKER_OS_COMPAT="$FAIL. Docker EE is not supported on OpenSUSE.";;
            esac
        else
            DOCKER_OS_COMPAT="$UNKNOWN. Requirements are not known for Docker $DOCKER_EDITION edition on $OS_NAME_SHORT"
        fi
        readonly DOCKER_OS_COMPAT
    fi

    check_passfail "${DOCKER_OS_COMPAT}"
}

################################################################
# Check whether docker-compose is installed.
#
# Globals:
#   IS_DOCKER_COMPOSE_PRESENT -- (out) TRUE/FALSE result
# Arguments:
#   None
# Returns:
#   true if docker-compose is installed.
################################################################
is_docker_compose_present() {
    if [[ -z "${IS_DOCKER_COMPOSE_PRESENT}" ]]; then
        echo "Looking for docker-compose..."
        readonly IS_DOCKER_COMPOSE_PRESENT="$(echo_boolean "$(have_command docker-compose ; echo "$?")")"
    fi

    check_boolean "${IS_DOCKER_COMPOSE_PRESENT}"
}

################################################################
# Get the version of docker-compose.
#
# Globals:
#   DOCKER_COMPOSE_VERSION -- (out) version string or status message.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_docker_compose_version() {
    if [[ -z "$DOCKER_COMPOSE_VERSION" ]]; then
        if ! is_docker_compose_present ; then
            readonly DOCKER_COMPOSE_VERSION="$UNKNOWN -- docker-compose not found."
        elif ! docker-compose --version 1>/dev/null 2>&1 ; then
            readonly DOCKER_COMPOSE_VERSION="$UNKNOWN -- docker-compose malfunctioned."
        else
            echo "Checking docker-compose version..."
            readonly DOCKER_COMPOSE_VERSION="$(docker-compose --version)"
        fi
    fi
}

################################################################
# Check whether docker is launched automatically at startup.
#
# Globals:
#   DOCKER_STARTUP_INFO -- (out) PASS/FAIL status message.
# Arguments:
#   None
# Returns:
#   true if docker is configured to launch at boot time.
################################################################
check_docker_startup_info() {
    if [[ -z "${DOCKER_STARTUP_INFO}" ]]; then
        if ! is_docker_present ; then
            readonly DOCKER_STARTUP_INFO="No docker startup setting -- docker not installed."
            return 1
        fi

        echo "Checking whether docker is enabled at boot time..."
        local status
        if have_command systemctl ; then
            systemctl list-unit-files 'docker*' | grep -aqF enabled >/dev/null 2>&1
            status="$(echo_passfail "$?")"
        elif have_command rc-update ; then
            rc-update show -v -a | grep -aF docker | grep -aqF boot >/dev/null 2>&1
            status="$(echo_passfail "$?")"
        elif have_command chkconfig ; then
            chkconfig --list docker | grep -aqF "2:on" >/dev/null 2>&1
            status="$(echo_passfail "$?")"
        fi

        if [[ -z "$status" ]]; then
            readonly DOCKER_STARTUP_INFO="Docker startup status is $UNKNOWN."
        elif check_passfail "$status" ; then
            readonly DOCKER_STARTUP_INFO="Docker startup check $PASS. Enabled at startup."
        else
            readonly DOCKER_STARTUP_INFO="Docker startup check $FAIL. The docker service is not enabled, and will not start automatically at boot time."
        fi
    fi

    check_passfail "${DOCKER_STARTUP_INFO}"
}

################################################################
# Gather docker system information.
#
# Globals:
#   DOCKER_SYSTEM_INFO -- (out) output from "docker system info"
#   DOCKER_SYSTEM_DF -- (out) output from "docker system df"
# Arguments:
#   None
# Returns:
#   None
################################################################
get_docker_system_info() {
    if [[ -z "$DOCKER_SYSTEM_INFO" ]]; then
        if ! is_docker_present ; then
            readonly DOCKER_SYSTEM_INFO="No docker system info -- docker is not installed."
            readonly DOCKER_SYSTEM_DF="No docker system df -- docker is not installed."
        elif ! is_docker_usable ; then
            readonly DOCKER_SYSTEM_INFO="Docker system info is $UNKNOWN -- cannot access docker."
            readonly DOCKER_SYSTEM_DF="Docker system df is $UNKNOWN -- cannot access docker."
        else
            echo "Getting docker system information..."
            readonly DOCKER_SYSTEM_INFO="$(docker system info)"
            readonly DOCKER_SYSTEM_DF="$(docker system df)"
        fi
    fi
}

################################################################
# Get a list of all docker images.
#
# Globals:
#   DOCKER_IMAGES -- (out) list of docker images, or a status message.
#   DOCKER_IMAGE_INSPECTION -- (out) details about all images.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_docker_images() {
    if [[ -z "${DOCKER_IMAGES}" ]]; then
        if ! is_docker_present ; then
            readonly DOCKER_IMAGES="No docker images -- docker not installed."
            readonly DOCKER_IMAGE_INSPECTION="No docker image details -- docker is not installed."
            return
        elif ! is_docker_usable ; then
            readonly DOCKER_IMAGES="Docker images are $UNKNOWN -- cannot access docker."
            readonly DOCKER_IMAGE_INSPECTION="Docker image details are $UNKNOWN -- cannot access docker."
            return
        fi

        echo "Checking docker images..."
        readonly DOCKER_IMAGES=$(docker image ls)
        readonly DOCKER_IMAGE_INSPECTION=$(for image in $(docker image ls -aq) ; do
                echo "------------------------------------------"
                echo
                echo "# docker image inspect '$image'"
                docker image inspect "$image"
                echo
            done
        )
    fi
}

################################################################
# Get detailed information about all docker containers.
#
# Globals:
#   DOCKER_CONTAINERS -- (out) list of docker constanters
#   DOCKER_CONTAINER_INSPECTION -- (out) container inspection and diff.
#   DOCKER_CONTAINER_ENVIRONMENT -- (out) container environment variable summary.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_docker_containers() {
    if [[ -z "${DOCKER_CONTAINERS}" ]]; then
        if ! is_docker_present ; then
            readonly DOCKER_CONTAINERS="No docker containers -- docker not installed."
            readonly DOCKER_CONTAINER_INSPECTION="No docker container details -- docker is not installed."
            readonly DOCKER_CONTAINER_ENVIRONMENT=
            return
        elif ! is_docker_usable ; then
            readonly DOCKER_CONTAINERS="Docker containers are $UNKNOWN -- cannot access docker"
            readonly DOCKER_CONTAINER_INSPECTION="Docker container details are $UNKNOWN -- cannot access docker."
            readonly DOCKER_CONTAINER_ENVIRONMENT=
            return
        fi

        echo "Checking docker containers and taking diffs..."
        readonly DOCKER_CONTAINERS="$(docker container ls | sed -e 's/\xE2\x80\xA6/+/')"
        # shellcheck disable=SC2155 # We don't care about the subcommand exit code
        local container_ids="$(docker container ls -aq)"
        if [[ -n "${container_ids}" ]]; then
            readonly DOCKER_CONTAINER_INSPECTION=$(
                while read -r cur_container_id ; do
                    echo "------------------------------------------"
                    docker container ls -a --filter "id=${cur_container_id}" --format "{{.ID}} {{.Image}}"
                    docker container inspect "${cur_container_id}" | sed -e 's/\(PASSWORD\)=.*/\1=.../'
                    docker container diff "${cur_container_id}"
                done <<< "${container_ids}"
            )

            # See also get_docker_services() below.  Containers have
            # lots of random environment variables; ignore the ones
            # that are unlikely to have been customized by users.
            local -r ignored="BLACKDUCK_DATA_DIR|BLACKDUCK_HOME|CATALINA_BASE|CATALINA_HOME|ELASTIC_CONTAINER|FILEBEAT_VERSION|GOPATH|GOSU_KEY|GOSU_VERSION|GPG_KEYS|HUB_APPLICATION_HOME|HUB_APPLICATION_NAME|JAVA_ALPINE_VERSION|JAVA_HOME|JAVA_VERSION|JOBRUNNER_HOME|LANG|LD_LIBRARY_PATH|NGINX_VERSION|PATH|PGDATA|PG_MAJOR|PG_SHA256|POSTGRES_DB|POSTGRES_INITDB_ARGS|SOLR_GID|SOLR_GROUP|SOLR_HOME|SOLR_KEYS|SOLR_SHA256|SOLR_UID|SOLR_URL|SOLR_USER|SOLR_VERSION|TOMCAT_ASC_URLS|TOMCAT_MAJOR|TOMCAT_NATIVE_LIBDIR|TOMCAT_SHA512|TOMCAT_TGZ_URLS|TOMCAT_VERSION|WEBSERVER_HOME|ZOOCFGDIR|ZOO_CONF_DIR|ZOO_DATA_DIR|ZOO_DATA_LOG_DIR|ZOO_INIT_LIMIT|ZOO_LOG4J_PROP|ZOO_LOG_DIR|ZOO_MAX_CLIENT_CNXNS|ZOO_PORT|ZOO_SYNC_LIMIT|ZOO_TICK_TIME|ZOO_USER"
            # shellcheck disable=SC2016,SC2086 # $x is not a shell variable, and let container_ids expand to multiple args.
            local -r vars="$(docker container inspect --format '{{$x:=.Name}}{{range .Config.Env}}{{println $x .}}{{end}}' $container_ids | sed -e 's/\(PASSWORD\)=.*/\1=.../' -e 's:^/::' -e '/^$/d' -e '/^[^=]*=$/d' | grep -Ev " ($ignored)=" | sort)"
            local -r grouped="$(echo "$vars" | cut -d' ' -f2- | sort | uniq -c)"
            # shellcheck disable=SC2155 # We don't care about the subcommand exit status.
            local -i max="$(echo "$grouped" | sort -nr | awk 'NR==1 {print $1}')"
            local -r regex="$(echo "$grouped" | awk '$1!='"$max"'{printf "%s|",substr($2,1,index($2,"=")-1)}' | sed -e 's/|$//')"
            readonly DOCKER_CONTAINER_ENVIRONMENT=$(
                echo "Common settings (present in $max containers):"
                echo "$grouped" | awk '$1=='"$max"'{$1=" ";print}'
                echo "$vars" | grep -aE "[^ ]* ($regex)=" | awk '$1!=name {name=$1; printf "\n%s:\n",name}; {$1=" ";print}'
            )
        else
            readonly DOCKER_CONTAINER_INSPECTION=
            readonly DOCKER_CONTAINER_ENVIRONMENT=
        fi
    fi
}

################################################################
# Guess at the total installation size, being conservative.
#
# Globals:
#   INSTALLATION_SIZE -- (out) string estimation of the installation size.
#   INSTALLATION_SIZE_DETAILS -- (out) string explanation of size rating.
#   INSTALLATION_SIZE_MESSAGES -- (out) list of problems found during sizing.
#   _${service}_app_memory -- (out) HUB_MAX_MEMORY or BLACKDUCK_REDIS_MAXMEMORY in MB.
#   _${service}_container_memory -- (out) container resource limit in MB.
#   _${service}_replicas -- (out) container replica count
# Arguments:
#   None
# Returns:
#   None
################################################################
get_installation_size() {
    if [[ -z "${INSTALLATION_SIZE}" ]]; then
        if ! is_docker_present ; then
            readonly INSTALLATION_SIZE="$UNKNOWN -- docker not installed"
            readonly INSTALLATION_SIZE_DETAILS=
            return
        elif ! is_docker_usable ; then
            readonly INSTALLATION_SIZE="$UNKNOWN -- cannot access docker"
            readonly INSTALLATION_SIZE_DETAILS=
            return
        fi
    fi

    # Find the largest known configuration meeting all requiements.
    declare -i _size_bracket=100
    local -i settings_checked=0
    local -a size_messages
    declare -a _size_details
    local -i redis_size=0
    local -i redisslave_size=0
    echo "Checking service/container installation sizes..."
    while read -r service image memvar app_memory container_memory replicas ; do
        # Export settings for other uses.
        local hub_service="${service/#blackduck_/hub_}"
        local service_var=$(echo "$hub_service" | tr '-' '_')
        export "_${service_var}_app_memory=$app_memory"
        export "_${service_var}_container_memory=$container_memory"
        export "_${service_var}_replicas=$replicas"

        # -- Size based on container memory limit --
        local container_mem_steps=
        if [[ "$SCAN_SIZING" == "gen03" ]] || [[ "$SCAN_SIZING" == "gen04" ]]; then
            # shellcheck disable=SC2155 # We don't care about the array_get exit code
            container_mem_steps="$(array_get "${REQ_CONTAINER_SIZES[@]}" "$hub_service")"
            _adjust_size_bracket "$container_memory" "$service container size limit of $container_memory MB" "$container_mem_steps"
        fi

        # -- Size based on app memory allocation --
        local -i memory
        if [[ "$SCAN_SIZING" == "gen03" ]] || [[ "$SCAN_SIZING" == "gen04" ]]; then
            memory=$app_memory;
        else
            memory=$((app_memory > 0 ? app_memory : container_memory));
        fi
        # shellcheck disable=SC2155 # We don't care about the array_get exit code
        local app_mem_steps="$(array_get "${MEM_SIZE_SCALE[@]}" "$hub_service")"
        _adjust_size_bracket "$memory" "$service $memvar limit of $memory MB" "$app_mem_steps"

        # -- Size based on replica counts --
        # shellcheck disable=SC2155 # We don't care about the array_get exit code
        local replica_steps="$(array_get "${REPLICA_COUNT_SCALE[@]}" "$hub_service")"
        _adjust_size_bracket "$replicas" "$service replica count of $replicas" "$replica_steps"

        # Complain if the app and container memory settings are upside down or too tight. Expect 10% to 20% overhead.
        # Don't complain about the standard configurations; some of them rounded sizes or don't fit the forumula.
        if [[ "$container_memory" -gt 0 ]] && [[ "$app_memory" -gt 0 ]]; then
            local -i overhead=$((container_memory - app_memory))
            if [[ "$container_memory" -lt "$app_memory" ]]; then
                size_messages+=("$FAIL: $service $memvar setting of $app_memory MB exceeds the container memory limit of $container_memory MB")
            elif [[ "$overhead" -lt $((container_memory / 10)) ]] && \
                     ! _is_standard_config "$app_memory" "$app_mem_steps" "$container_memory" "$container_mem_steps" "$replicas" "$replica_steps"; then
                size_messages+=("$WARN: $service $memvar setting of $app_memory MB is close to the container memory limit of $container_memory MB")
            elif [[ "$overhead" -gt $((container_memory / 5)) ]] && [[ "$overhead" -gt 1024 ]]; then
                size_messages+=("$WARN: $service $memvar setting of $app_memory MB is much less than the container memory limit of $container_memory MB")
            fi
        fi

        # Complain if a non-horizontally scalable service has replicas.
        # shellcheck disable=SC2155 # We don't care about the array_get exit code
        local replicable="$(array_get "${REPLICABLE[@]}" "$hub_service")"
        if [[ -n "$replicable" ]] && [[ "$replicable" != "$PASS" ]] && [[ $replicas -gt 1 ]]; then
            size_messages+=("$replicable: $service has $replicas replicas")
        fi

        # -- Miscellaneous servicie-specific checks --
        # Complain if the redis containers have different sizes.
        if [[ "$hub_service" == "hub_redis" ]] && [[ $redis_size -ge 0 ]]; then
            redis_size=$container_memory
        elif [[ "$hub_service" == "hub_redisslave" ]] && [[ $redisslave_size -ge 0 ]]; then
            redisslave_size=$container_memory
        fi
        if [[ $redis_size -gt 0 ]] && [[ $redisslave_size -gt 0 ]] && [[ $redis_size -ne $redisslave_size ]]; then
            size_messages+=("$FAIL: redis and redisslave containers have different size ($redis_size MB vs. $redisslave_size MB)")
            redis_size=-1
            redisslave_size=-1
        fi
    done <<< "$(_get_container_size_info)"

    # Size based on postgresql settings.
    if is_postgresql_container_running && [[ ${#PG_SETTINGS_SCALE[@]} -gt 0 ]]; then
        local -r postgres_container_id=$(docker container ls --format '{{.ID}} {{.Image}}' | grep -aF "blackducksoftware/blackduck-postgres:" | cut -d' ' -f1)
        for settings in "${PG_SETTINGS_SCALE[@]}"; do
            local parameter="${settings%%=*}"
            local steps="${settings#*=}"
            local value="$(_size_to_mb "$(docker exec -i "$postgres_container_id" psql -U blackduck -A -t -d bds_hub -c "show $parameter")")"
            _adjust_size_bracket "$value" "hub_postgres $parameter setting of $value MB" "$steps"
        done
    fi

    # bom engines should not outnumber job runners for legacy scanning.
    # shellcheck disable=SC2154 # These variables are set in a sneaky way.
    if [[ "$_hub_bomengine_replicas" -gt "$_hub_jobrunner_replicas" ]] && [[ "$SCAN_SIZING" == "gen01" ]]; then
        size_messages+=("$WARN: there are ${_hub_bomengine_replicas} bomengine and ${_hub_jobrunner_replicas} jobrunner replicas.  There should be at least an equal number of job runners.")
    fi

    # Suggest that large installations consider using Redis Sentinel mode.
    if [[ $redisslave_size -eq 0 ]] && [[ $settings_checked -gt 0 ]] && [[ $_size_bracket -ge 3 ]]; then
        size_messages+=("$NOTE: some installations of this size use Redis Sentinel mode to increase robustness.")
    fi

    # Report the label for this size bracket.
    if [[ $settings_checked -le 0 ]] || [[ $_size_bracket -ge 100 ]]; then
        readonly INSTALLATION_SIZE="$UNKNOWN for $SIZING"
    elif [[ $_size_bracket -le 0 ]]; then
        readonly INSTALLATION_SIZE="UNDERSIZED for $SIZING"
        size_messages+=("$WARN: This configuration does not meet minimum standards for $SIZING.  See the 'Approximate installation size' details.")
    else
        readonly INSTALLATION_SIZE="$(echo -n "${SIZE_SCALE[$_size_bracket]}" | tr '[:lower:]' '[:upper:]' | sed -e 's/^.* //'; echo " $SIZING")"
    fi
    readonly INSTALLATION_SIZE_MESSAGES="$(IFS=$'\n'; echo "${size_messages[*]}")"
    readonly INSTALLATION_SIZE_DETAILS="$(IFS=$'\n'; echo "${_size_details[*]}" | sort)"
}

################################################################
# Helper method to find the matching sizing bracket for a particular setting
#
# Globals:
#   _size_bracket -- (in/out) largest bracket that meets all criteria
#   _size_details -- (in/out) array of messages giving details
# Arguments:
#   $1 - value
#   $2 - prefix for detail messages
#   $3 - space-separated list of sizing steps
# Returns:
#   None
################################################################
_adjust_size_bracket() {
    local -r value="$1"
    local -r prefix="$2"
    local -r steps="$3"

    if [[ -n "$steps" ]]; then
        ((settings_checked++))
        local plus=
        local -i min_bracket=0
        local -i max_bracket=0
        local last_bound=
        # shellcheck disable=SC2068 # We want to expand bounds into multiple tokens
        for bound in $steps; do
            if [[ $value -ge $bound ]]; then
                ((max_bracket++))
                if [[ -z $last_bound ]] || [[ $last_bound -lt $bound ]]; then min_bracket=$max_bracket; fi
                if [[ $value -gt $bound ]]; then plus="+"; else plus=; fi
            fi
            last_bound=$bound
        done
        if [[ -n "$last_bound" ]] && [[ $value -gt $last_bound ]]; then ((max_bracket++)); plus=; fi
        if [[ $min_bracket -gt 0 ]] && [[ $min_bracket -lt $max_bracket ]]; then
            _size_details+=(" - $prefix suggests ${SIZE_SCALE[$min_bracket]} to ${SIZE_SCALE[$max_bracket]}$plus $SIZING installation")
        else
            _size_details+=(" - $prefix suggests ${SIZE_SCALE[$max_bracket]}$plus $SIZING installation")
        fi
        [[ $_size_bracket -le $max_bracket ]] || _size_bracket=$max_bracket
    fi
}

# Determine whether the provided settings are an exact match for one of the standard configurations.
_is_standard_config() {
    local -i app_memory="$1"
    # shellcheck disable=SC2206 # We want word-splitting here.
    local -a app_mem_steps=($2)
    local -i container_memory="$3"
    # shellcheck disable=SC2206 # We want word-splitting here.
    local -a container_mem_steps=($4)
    local -i replicas="$5"
    # shellcheck disable=SC2206 # We want word-splitting here.
    local -a replica_steps=($6)

    # We need both app and container memory information to decide.
    local -i i=0
    while [[ $i -lt ${#app_mem_steps[@]} ]] && [[ $i -lt ${#app_mem_steps[@]} ]]; do
        if [[ $app_memory -eq ${app_mem_steps[$i]} ]] && [[ $container_memory -eq ${container_mem_steps[$i]} ]]; then
            # If we have replica count information it must match too.
            if [[ $i -ge ${#replica_steps[@]} ]] || [[ $replicas -eq ${replica_steps[$i]} ]]; then
                return 0
            fi
        fi
        ((i++))
    done
    return 1
}

# Echo "service image memvar app_memory container_memory replica_count" for all
# services/containers.  Sizes are in MB.  Unknown counts are 0.
_get_container_size_info() {
    if is_swarm_enabled; then
        # Probe services because the containers might be running remotely.
        while read -r service image ; do
            # Look for HUB_MAX_MEMORY or BLACKDUCK_REDIS_MAXMEMORY and convert to MB.
            local hub_service="${service/#blackduck_/hub_}"
            case "$hub_service" in
                (hub_redis*)
                    if [[ "$hub_service" == hub_redissentinel* ]]; then memvar="container_memory"; else memvar="BLACKDUCK_REDIS_MAXMEMORY"; fi;;
                (hub_postgres* | hub_cfssl | hub_rabbitmq | hub_webserver)
                    memvar="container_memory";;
                (*)
                    memvar="HUB_MAX_MEMORY";;
            esac
            # shellcheck disable=SC2155 # We don't care about the subcommand exit code
            local -i app_memory=$(_size_to_mb "$(docker service inspect "$service" --format '{{.Spec.TaskTemplate.ContainerSpec.Env}}' | tr ' ' '\n' | grep -a '^[\[]*'$memvar= | cut -d= -f2)")

            # Look for the container memory resource limit and convert to MB.
            # shellcheck disable=SC2155 # We don't care about the subcommand exit code
            local -i container_memory=$(docker service inspect "$service" --format '{{.Spec.TaskTemplate.Resources.Limits.MemoryBytes}}' 2>/dev/null)
            [[ "$container_memory" -le 0 ]] || container_memory=$((container_memory / MB))

            # shellcheck disable=SC2155 # We don't care about the subcommand exit code
            local -i replicas=$(docker service inspect "$service" --format '{{.Spec.Mode.Replicated.Replicas}}')

            # Collapse all the redis clones
            if [[ "$hub_service" == hub_redissentinel* ]]; then
                echo "hub_redissentinel $image $memvar $((app_memory)) $((container_memory)) $((replicas))"
            elif [[ "$hub_service" == hub_redisslave* ]]; then
                echo "hub_redisslave $image $memvar $((app_memory)) $((container_memory)) $((replicas))"
            else
                echo "$service $image $memvar $((app_memory)) $((container_memory)) $((replicas))"
            fi
        done <<< "$(docker service ls --format '{{.Name}} {{.Image}}')"
   else
        # Containers should be running locally.  Probe them for sizing information.
        local service
        while read -r id image names ; do
            # Unconventional leading parenthesis for each case to appease bash on macOS
            # Map image names to service names.
            local memvar="HUB_MAX_MEMORY"
            case "$image" in
                (blackducksoftware/blackduck-authentication*)
                    service="hub_authentication";;
                (blackducksoftware/blackduck-bomengine*)
                    service="hub_bomengine";;
                (sigsynopsys/bdba-worker*)
                    service="hub_binaryscanner";;
                (blackducksoftware/blackduck-cfssl*)
                    service="hub_cfssl"; memvar="container_memory";;
                (blackducksoftware/blackduck-documentation*)
                    service="hub_documentation";;
                (blackducksoftware/blackduck-integration*)
                    service="hub_integration";; 
                (blackducksoftware/blackduck-jobrunner*)
                    service="hub_jobrunner";;                                                                                                                                                                   
                (blackducksoftware/blackduck-logstash*)
                    service="hub_logstash";;
                (blackducksoftware/blackduck-postgres-exporter*)
                    service="hub_postgres-exporter"; memvar="container_memory";;
                (blackducksoftware/blackduck-postgres*)
                    service="hub_postgres"; memvar="container_memory";;
                (blackducksoftware/rabbitmq*)
                    service="hub_rabbitmq"; memvar="container_memory";;
                (blackducksoftware/blackduck-matchengine*)
                    service="hub_matchengine";;
                (blackducksoftware/blackduck-redis*)
                    if [[ "$names" == *sentinel* ]]; then service="hub_redissentinel";
                    elif [[ "$names" == *slave* ]]; then service="hub_redisslave"; memvar="BLACKDUCK_REDIS_MAXMEMORY";
                    else service="hub_redis"; memvar="BLACKDUCK_REDIS_MAXMEMORY";
                    fi;;
                (blackducksoftware/blackduck-registration*)
                    service="hub_registration";;
                (blackducksoftware/blackduck-scan*)
                    service="hub_scan";;
                (blackducksoftware/blackduck-storage*)
                    service="hub_storage";;
                (blackducksoftware/blackduck-webapp*)
                    service="hub_webapp";;
                (blackducksoftware/blackduck-nginx*)
                    service="hub_webserver"; memvar="container_memory";;
                (blackducksoftware/blackduck-alert*)
                    service="hub_alert";;  # Deploying Alert inside Hub is still supported.
                (blackducksoftware/alert-database*)
                    service="hub_alert_database";;
                (blackducksoftware/blackduck-grafana* | \
                 blackducksoftware/blackduck-prometheus* | \
                 blackducksoftware/blackduck-cadvisor* | \
                 blackducksoftware/kb_* | \
                 blackducksoftware/kbapi* | \
                 docker.elastic.co/kibana* | \
                 docker.elastic.co/elasticsearch*)
                    service="internal";;  # Used internally but not part of the product.
                (blackducksoftware/*)
                    service="unknown-blackduck";;
                (*)
                    service="unknown";; # Probably unusable
            esac

            # shellcheck disable=SC2155 # We don't care about the subcommand exit code
            local -i app_memory=$(_size_to_mb "$(docker container inspect "$id" --format '{{.Config.Env}}' | tr ' ' '\n' | grep -a '^[\[]*'$memvar= | cut -d= -f2)")
            # shellcheck disable=SC2155 # We don't care about the subcommand exit code
            local -i container_memory="$(docker container inspect "$id" --format '{{.HostConfig.Memory}}')"
            [[ "$container_memory" -le 0 ]] || container_memory=$((container_memory / MB))

            # Ignore service scale for docker-compose because I don't know how to query it
            # and docker-compose is deprecated anyway.
            echo "$service $image $memvar $((app_memory)) $((container_memory)) 0"
        done <<< "$(docker container ls --format '{{.ID}} {{.Image}} {{.Names}}')"
    fi
}

# Convert a size string to MB.
_size_to_mb() {
    local size="$1"
    [[ "$size" =~ .[bB]$ ]] && size="${size%?}"
    if [[ "$size" =~ ^[0-9]*$ ]]; then
        echo $((size / MB))
    elif [[ "$size" =~ ^[0-9]*[kK]$ ]]; then
        echo $((${size%?} / 1024))
    elif [[ "$size" =~ ^[0-9]*[mM]$ ]]; then
        echo "${size%?}"
    elif [[ "$size" =~ ^[0-9]*[gG]$ ]]; then
        echo $((${size%?} * 1024))
    elif [[ "$size" =~ ^[0-9]*[tT]$ ]]; then
        echo $((${size%?} * 1024 * 1024))
    else
        echo "** Internal error: could not convert '$size' to MB" 1>&2
        echo -1
    fi
}

################################################################
# Check that containers and services meet minimum required memory limits.
#
# Globals:
#   DOCKER_MEMORY_CHECKS -- (out) pass/fail status of service or container memory limits.
#   CONTAINER_OOM_CHECKS -- (out) pass/fail presence of oom-killed local containers.
# Arguments:
#   None
# Returns:
#   true if all local containers meet minimum memory requirements.
################################################################
check_container_memory() {
    if [[ -z "${DOCKER_MEMORY_CHECKS}" ]]; then
        if ! is_docker_present ; then
            readonly DOCKER_MEMORY_CHECKS="No docker containers/services -- docker not installed."
            return
        elif ! is_docker_usable ; then
            readonly DOCKER_MEMORY_CHECKS="Docker containers/services are $UNKNOWN -- cannot access docker"
            return
        fi

        echo "Checking container/service memory limits..."
        local -a results
        local -i index=$(if [[ "$SCAN_SIZING" == "gen03" ]] || [[ "$SCAN_SIZING" == "gen04" ]] || ! is_swarm_enabled; then echo 0; else echo 1; fi)
        while read -r service image memvar app_memory memory replicas ; do
            local hub_service="${service/#blackduck_/hub_}"
            if [[ "$hub_service" == unknown-blackduck ]]; then
                results+=("$UNKNOWN: unrecognized blackduck image $image")
            fi

            # shellcheck disable=SC2155 # We don't care about the subcommand exit code
            local sizes="$(array_get "${REQ_CONTAINER_SIZES[@]}" "$hub_service")"
            if [[ -n "$sizes" ]]; then
                IFS=" " read -r -a data <<< "$sizes"
                local -i required=${data[$index]}
                if [[ $memory -eq 0 ]]; then
                    results+=("$PASS: $service has no memory limit, minimum is $required MB for $SIZING")
                elif [[ $memory -ge $required ]]; then
                    results+=("$PASS: $service has $memory MB, minimum is $required MB for $SIZING")
                else
                    results+=("$FAIL: $service has $memory MB, minimum is $required MB for $SIZING")
                fi
            fi
        done <<< "$(_get_container_size_info)"
        [[ ${#results[0]} -gt 0 ]] || results+=("$WARN: unable to verify memory limits -- no data.")
        readonly DOCKER_MEMORY_CHECKS="$(IFS=$'\n'; echo "${results[*]}")"

        # Look for containers that were OOM-KILLED.
        # shellcheck disable=SC2155 # We don't care about the subcommand exit code
        local result=$(docker container ls -a --format '{{.ID}} {{.Image}} {{.Names}}' | while read -r id image names ; do
            if [[ "$(docker container inspect "$id" --format '{{.State.OOMKilled}}')" != "false" ]] && \
               [[ "$image" =~ blackducksoftware* || "$image" =~ sigsynopsys* ]]; then
                echo "$FAIL: container $id ($names) was killed because it ran out of memory"
            fi
        done)
        readonly CONTAINER_OOM_CHECKS="$result"
    fi

    check_passfail "${DOCKER_MEMORY_CHECKS} ${CONTAINER_OOM_CHECKS}"
}

################################################################
# Get the running Black Duck version
#
# Globals:
#   RUNNING_HUB_VERSION -- (out) running Black Duck version.
#   RUNNING_BDBA_VERSION -- (out) running BDBA version.
#   RUNNING_ALERT_VERSION -- (out) running Synopsys Alert version.
#   RUNNING_OTHER_VERSIONS -- (out) other Black Duck product versions.
#   RUNNING_VERSION_STATUS -- (out) pass/fail version check message.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_running_hub_version() {
    if [[ -z "${RUNNING_HUB_VERSION}" ]]; then
        if ! is_docker_present ; then
            readonly RUNNING_HUB_VERSION="none"
            return
        elif ! is_docker_usable ; then
            readonly RUNNING_HUB_VERSION="$UNKNOWN"
            return
        fi

        # Try to find all images on all nodes.
        local -a status
        local raw=
        if is_swarm_enabled ; then
            for stack in $(docker stack ls --format '{{.Name}}'); do
                raw+=$(docker stack ps "$stack" --filter 'desired-state=running' --format '{{.Image}}'; echo)
                if [[ "$(docker stack ps "$stack" --filter 'desired-state=running' --format '{{.Image}}' | grep -aE "$VERSIONED_HUB_IMAGES" | cut -d: -f2 | sort | uniq | wc -l)" -gt 1 ]]; then
                    status+="$FAIL: multiple Black Duck versions are running in stack $stack."
                fi
            done
        fi
        if [[ -z "$raw" ]]; then
            raw="$(docker ps --format '{{.Image}}')"
            if [[ "$(echo "$raw" | grep -aE "$VERSIONED_HUB_IMAGES" | cut -d: -f2 | sort | uniq | wc -l)" -gt 1 ]]; then
                status+="$FAIL: multiple Black Duck versions are running."
            fi
        fi
        local -r all="$(echo "$raw" | grep -aE '^sigsynopsys/|^blackducksoftware/' | grep -avF ':1.' | sort | uniq)"

        local -r hub_versions="$(echo "$all" | grep -aE "$VERSIONED_HUB_IMAGES" | cut -d: -f2 | sort | uniq | tr '\n' ' ' | sed -e 's/ *$//')"
        local -r bdba_versions="$(echo "$all" | grep -aE "$VERSIONED_BDBA_IMAGES" | cut -d: -f2 | sort | uniq | tr '\n' ' ' | sed -e 's/ *$//')"
        local -r alert_versions="$(echo "$all" | grep -aE "$VERSIONED_ALERT_IMAGES" | cut -d: -f2 | sort | uniq | tr '\n' ' ' | sed -e 's/ *$//')"
        local -r other_versions="$(echo "$all" | grep -avE "$VERSIONED_HUB_IMAGES|$VERSIONED_BDBA_IMAGES|$VERSIONED_ALERT_IMAGES" | cut -d: -f2 | sort | uniq | tr '\n' ' ' | sed -e 's/ *$//')"

        readonly RUNNING_HUB_VERSION="${hub_versions:-none}"
        readonly RUNNING_BDBA_VERSION="${bdba_versions:-none}"
        readonly RUNNING_ALERT_VERSION="${alert_versions:-none}"
        readonly RUNNING_OTHER_VERSIONS="${other_versions:-none}"
        readonly RUNNING_VERSION_STATUS="$(IFS=$'\n'; echo "${status[*]}")"
    fi
}

################################################################
# Get a list of docker processes
#
# Globals:
#   DOCKER_PROCESSES -- (out) text list of processes.
#   DOCKER_PROCESSES_UNFORMATTED -- (out) list of processes in an easily-consumable format
# Arguments:
#   None
# Returns:
#   None
################################################################
get_docker_processes() {
    if [[ -z "${DOCKER_PROCESSES}" ]]; then
        if ! is_docker_present ; then
            readonly DOCKER_PROCESSES="No docker processes -- docker not installed."
            readonly DOCKER_PROCESSES_UNFORMATTED="No docker processes -- docker not installed."
            return
        elif ! is_docker_usable ; then
            readonly DOCKER_PROCESSES="Docker processes are $UNKNOWN -- cannot access docker"
            readonly DOCKER_PROCESSES_UNFORMATTED="Docker processes are $UNKNOWN -- cannot access docker"
            return
        fi

        echo "Checking current docker processes..."
        local -r all="$(docker ps | sed -e 's/\xE2\x80\xA6/+/')"
        local -r others="$(docker ps --format '{{.Image}}' | grep -aFv blackducksoftware | grep -aFv sigsynopsys)"
        readonly DOCKER_PROCESSES_UNFORMATTED="$(docker ps --format '{{.ID}} {{.Image}} {{.Names}} {{.Status}}')"
        if [[ -n "$others" ]]; then
            # shellcheck disable=SC2116,SC2086 # Deliberate extra echo to collapse lines
            readonly DOCKER_PROCESSES="$WARN: foreign docker processes found: $(echo $others)

$all"
        else
            readonly DOCKER_PROCESSES="$all"
        fi
    fi
}

################################################################
# Check whether the Binary Scanner container is running.
#
# Globals:
#   IS_BINARY_SCANNER_CONTAINER_RUNNING -- (out) TRUE/FALSE result
#   BINARY_SCANNER_CONTAINER_COUNT -- (out) int count
#   DOCKER_PROCESSES_UNFORMATTED -- (in) list of processes in an easily-consumable format
# Arguments:
#   None
# Returns:
#   true if the binary scanner container is running.
################################################################
is_binary_scanner_container_running() {
    if [[ -z "${IS_BINARY_SCANNER_CONTAINER_RUNNING}" ]]; then
       if ! is_docker_present ; then
           readonly BINARY_SCANNER_CONTAINER_COUNT="0"
           readonly IS_BINARY_SCANNER_CONTAINER_RUNNING="$FALSE"
       else
           [[ -n "${DOCKER_PROCESSES_UNFORMATTED}" ]] || get_docker_processes
           readonly BINARY_SCANNER_CONTAINER_COUNT="$(echo "$DOCKER_PROCESSES_UNFORMATTED" | grep -aF sigsynopsys | grep -acF binaryscanner)"
           readonly IS_BINARY_SCANNER_CONTAINER_RUNNING="$(echo_boolean "$([[ "$BINARY_SCANNER_CONTAINER_COUNT" -gt 0 ]]; echo "$?")")"
       fi
    fi

    check_boolean "${IS_BINARY_SCANNER_CONTAINER_RUNNING}"
}

################################################################
# Check whether any Redis sentinels are running
#
# Globals:
#   IS_REDIS_SENTINEL_MODE_ENABLED -- (out) TRUE/FALSE result
#   DOCKER_PROCESSES_UNFORMATTED -- (in) list of processes in an easily-consumable format
# Arguments:
#   None
# Returns:
#   true if the binary scanner container is running.
################################################################
is_redis_sentinel_mode_enabled() {
    if [[ -z "${IS_REDIS_SENTINEL_MODE_ENABLED}" ]]; then
       if ! is_docker_present ; then
           readonly IS_REDIS_SENTINEL_MODE_ENABLED="$FALSE"
       else
           [[ -n "${DOCKER_PROCESSES_UNFORMATTED}" ]] || get_docker_processes
           local -r sentinel_container_count="$(echo "$DOCKER_PROCESSES_UNFORMATTED" | grep -aF blackducksoftware | grep -acF redissentinel)"
           readonly IS_REDIS_SENTINEL_MODE_ENABLED="$(echo_boolean "$([[ "$sentinel_container_count" -gt 0 ]]; echo "$?")")"
       fi
    fi

    check_boolean "${IS_REDIS_SENTINEL_MODE_ENABLED}"
}

################################################################
# Check whether the Black Duck PostgreSQL container is running
#
# Globals:
#   IS_POSTGRESQL_CONTAINER_RUNNING -- (out) TRUE/FALSE result
#   DOCKER_PROCESSES_UNFORMATTED -- (in) list of processes in an easily-consumable format
# Arguments:
#   None
# Returns:
#   true if the Black Duck postgresql container is running.
################################################################
is_postgresql_container_running() {
    if [[ -z "${IS_POSTGRESQL_CONTAINER_RUNNING}" ]]; then
       if ! is_docker_present ; then
           readonly IS_POSTGRESQL_CONTAINER_RUNNING="$FALSE"
       else
           [[ -n "${DOCKER_PROCESSES_UNFORMATTED}" ]] || get_docker_processes
           echo "$DOCKER_PROCESSES_UNFORMATTED" | grep -aF blackducksoftware | grep -aqF postgres:
           readonly IS_POSTGRESQL_CONTAINER_RUNNING="$(echo_boolean $?)"
       fi
    fi

    check_boolean "${IS_POSTGRESQL_CONTAINER_RUNNING}"
}

################################################################
# Echo the status of a docker container with a particular image name
#
# Globals:
#   DOCKER_PROCESSES_UNFORMATTED -- (in) list of processes in an easily-consumable format
# Arguments:
#   $1 - Image name for desired container
# Returns:
#   None
################################################################
get_container_status() {
    if ! is_docker_present ; then
        echo "Docker not installed."
        return
    elif ! is_docker_usable ; then
        echo "Docker not usable."
        return
    fi

    [[ -n "${DOCKER_PROCESSES_UNFORMATTED}" ]] || get_docker_processes
    echo "$DOCKER_PROCESSES_UNFORMATTED" | grep -a "$1:*" | cut -d' ' -f4- | tr '\n' ' '
}

################################################################
# Check that all local containers are currently healthy.
#
# Globals:
#   CONTAINER_HEALTH_CHECKS -- (out) pass/fail status of local container health.
#   DOCKER_PROCESSES_UNFORMATTED -- (in) list of processes in an easily-consumable format
# Arguments:
#   None
# Returns:
#   None
################################################################
get_container_health() {
    if [[ -z "${CONTAINER_HEALTH_CHECKS}" ]]; then
        if ! is_docker_present ; then
            readonly CONTAINER_HEALTH_CHECKS="No container health info -- docker not installed."
            return
        elif ! is_docker_usable ; then
            readonly CONTAINER_HEALTH_CHECKS="Container health is $UNKNOWN -- cannot access docker."
            return
        fi

        [[ -n "${DOCKER_PROCESSES_UNFORMATTED}" ]] || get_docker_processes
        local -r result=$(echo "$DOCKER_PROCESSES_UNFORMATTED" | while read -r id image names status ; do
                if [[ "$image" =~ blackducksoftware* || "$image" =~ sigsynopsys* ]] && [[ "$status" =~ \(unhealthy\)* ]]; then
                    echo "$FAIL: container $id ($names) is unhealthy."
                fi
        done)

        readonly CONTAINER_HEALTH_CHECKS="${result:-$PASS: All containers are healthy.}"
    fi
}

################################################################
# Get detailed information about docker networks.
#
# Globals:
#   DOCKER_NETWORKS -- (out) text docker network list
#   DOCKER_NETWORK_INSPECTION -- (out) text docker network details
# Arguments:
#   None
# Returns:
#   None
################################################################
get_docker_networks() {
    if [[ -z "${DOCKER_NETWORKS}" ]]; then
        if ! is_docker_present ; then
            readonly DOCKER_NETWORKS="No docker networks -- docker not installed."
            readonly DOCKER_NETWORK_INSPECTION="No docker network details -- docker is not installed."
            return
        elif ! is_docker_usable ; then
            readonly DOCKER_NETWORKS="Docker networks are $UNKNOWN -- cannot access docker"
            readonly DOCKER_NETWORK_INSPECTION="Docker network details are $UNKNOWN -- cannot access docker."
            return
        fi

        echo "Checking docker networks..."
        readonly DOCKER_NETWORKS="$(docker network ls)"
        readonly DOCKER_NETWORK_INSPECTION=$(for net in $(docker network ls -q) ; do
                echo "------------------------------------------"
                echo
                echo "# docker network inspect '$net'"
                docker network inspect "$net"
                echo
            done
        )
    fi
}

################################################################
# Get detailed information about docker volumes.
#
# Globals:
#   DOCKER_VOLUMES -- (out) text docker volume list.
#   DOCKER_VOLUME_INSPECTION -- (out) text docker volume information.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_docker_volumes() {
    if [[ -z "${DOCKER_VOLUMES}" ]]; then
        if ! is_docker_present ; then
            readonly DOCKER_VOLUMES="No docker volumes -- docker not installed."
            readonly DOCKER_VOLUME_INSPECTION="No docker volume details -- docker is not installed."
            return
        elif ! is_docker_usable ; then
            readonly DOCKER_VOLUMES="Docker volumes are $UNKNOWN -- cannot access docker"
            readonly DOCKER_VOLUME_INSPECTION="Docker volume details are $UNKNOWN -- cannot access docker."
            return
        fi

        echo "Checking docker volumes..."
        readonly DOCKER_VOLUMES="$(docker volume ls)"
        readonly DOCKER_VOLUME_INSPECTION=$(for vol in $(docker volume ls -q) ; do
                echo "------------------------------------------"
                echo
                echo "# docker volume inspect '$vol'"
                docker volume inspect "$vol"
                echo
            done
        )
    fi
}

################################################################
# Check whether docker swarm mode is enabled.
#
# Globals:
#   IS_SWARM_ENABLED -- (out) TRUE/FALSE/UNKNOWN status
#   DOCKER_ORCHESTRATOR -- (out) text orchestrator
# Arguments:
#   None
# Returns:
#   true is swarm mode is known to be active
################################################################
is_swarm_enabled() {
    if [[ -z "${IS_SWARM_ENABLED}" ]]; then
        if ! is_docker_present ; then
            readonly IS_SWARM_ENABLED="$FALSE"
            readonly DOCKER_ORCHESTRATOR="none"
        elif ! is_docker_usable ; then
            readonly IS_SWARM_ENABLED="$UNKNOWN"
            readonly DOCKER_ORCHESTRATOR="$UNKNOWN"
        else
            echo "Checking docker swarm mode..."
            if docker node ls > /dev/null 2>&1 ; then
                readonly IS_SWARM_ENABLED="$TRUE"
                readonly DOCKER_ORCHESTRATOR="swarm"
            else
                readonly IS_SWARM_ENABLED="$FALSE"
                readonly DOCKER_ORCHESTRATOR="compose"
            fi
        fi
    fi

    check_boolean "${IS_SWARM_ENABLED}"
}

################################################################
# Gather detailed information about docker swarm nodes.
#
# Globals:
#   DOCKER_NODES -- (out) text node list
#   DOCKER_NODE_COUNT -- (out) number of nodes
#   DOCKER_NODE_INSPECTION -- (out) text node report
# Arguments:
#   None
# Returns:
#   None
################################################################
get_docker_nodes() {
    if [[ -z "${DOCKER_NODES}" ]]; then
        if ! is_docker_present ; then
            readonly DOCKER_NODES="No docker swarm nodes -- docker is not installed."
            readonly DOCKER_NODE_COUNT="0"
            readonly DOCKER_NODE_INSPECTION="No docker swarm node details -- docker is not installed."
            return
        elif ! is_docker_usable ; then
            readonly DOCKER_NODES="Docker swarm nodes are $UNKNOWN -- cannot access docker"
            readonly DOCKER_NODE_COUNT="$UNKNOWN"
            readonly DOCKER_NODE_INSPECTION="Docker swarm node details are $UNKNOWN -- cannot access docker"
            return
        fi

        echo "Checking docker nodes..."
        if ! docker node ls > /dev/null 2>&1 ; then
            readonly DOCKER_NODES="Machine is not part of a docker swarm or is not the manager"
            readonly DOCKER_NODE_COUNT="$UNKNOWN"
            readonly DOCKER_NODE_INSPECTION="Machine is not part of a docker swarm or is not the manager"
            return
        fi

        readonly DOCKER_NODES="$(docker node ls)"
        readonly DOCKER_NODE_COUNT="$(docker node ls -q | wc -l)"
        readonly DOCKER_NODE_INSPECTION=$(for node in $(docker node ls -q) ; do
                echo "------------------------------------------"
                echo
                echo "# docker node inspect '$node'"
                docker node inspect "$node"
                echo
            done
        )
    fi
}

################################################################
# Gather detailed information about docker swarm services.
#
# Globals:
#   DOCKER_SERVICES -- (out) text service list
#   DOCKER_SERVICE_INFO -- (out) text service report
#   DOCKER_SERVICE_ENVIRONMENT -- (out) service environment summary
# Arguments:
#   None
# Returns:
#   None
################################################################
get_docker_services() {
    if [[ -z "${DOCKER_SERVICES}" ]]; then
        if ! is_docker_present ; then
            readonly DOCKER_SERVICES="No docker services -- docker is not installed."
            readonly DOCKER_SERVICE_INFO="No docker service details -- docker is not installed."
            readonly DOCKER_SERVICE_ENVIRONMENT=
            return
        elif ! is_docker_usable ; then
            readonly DOCKER_SERVICES="Docker services are $UNKNOWN -- cannot access docker"
            readonly DOCKER_SERVICE_INFO="Docker service details are $UNKNOWN -- cannot access docker"
            readonly DOCKER_SERVICE_ENVIRONMENT=
            return
        elif ! is_swarm_enabled ; then
            readonly DOCKER_SERVICES="Docker services are $UNKNOWN -- machine is not part of a docker swarm or is not the manager"
            readonly DOCKER_SERVICE_INFO="Docker service details are $UNKNOWN -- machine is not part of a docker swarm or is not the manager"
            readonly DOCKER_SERVICE_ENVIRONMENT=
            return
        fi

        echo "Getting docker service information..."
        readonly DOCKER_SERVICES="$(docker service ls)"
        readonly DOCKER_SERVICE_INFO=$(
            for service in $(docker service ls -q); do
                echo "------------------------------------------"
                docker service inspect --pretty "$service" | sed -e 's/\(PASSWORD\)=[^ ]*/\1=.../g'
                echo
            done
        )

        # Find service environment variables.  Group the most common
        # (likely from blackduck-config.env) and show service-specific
        # settings for the rest.  See also get_docker_containers() above.
        if [[ -n "$DOCKER_SERVICES" ]]; then
            # shellcheck disable=SC2016,SC2046 # $x is not a shell variable, and let service list expand to multiple args.
            local -r vars="$(docker service inspect --format '{{$x:=.Spec.Name}}{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println $x .}}{{end}}' $(docker service ls -q) | sed -e 's/\(PASSWORD\)=.*/\1=.../' -e '/^$/d' -e '/^[^=]*=$/d' | sort)"
            local -r grouped="$(echo "$vars" | cut -d' ' -f2- | sort | uniq -c)"
            # shellcheck disable=SC2155 # We don't care about the subcommand exit status.
            local -i max="$(echo "$grouped" | sort -nr | awk 'NR==1 {print $1}')"
            local -r regex="$(echo "$grouped" | awk '$1!='"$max"'{printf "%s|",substr($2,1,index($2,"=")-1)}' | sed -e 's/|$//')"
            readonly DOCKER_SERVICE_ENVIRONMENT=$(
                echo "Common settings (present in $max services):"
                echo "$grouped" | awk '$1=='"$max"'{$1=" ";print}'
                echo "$vars" | grep -aE "[^ ]* ($regex)=" | awk '$1!=name {name=$1; printf "\n%s:\n",name}; {$1=" ";print}'
            )
        else
            readonly DOCKER_SERVICE_ENVIRONMENT=
        fi
    fi
}

################################################################
# Gather detailed information about docker swarm stacks.
#
# Globals:
#   DOCKER_STACKS -- (out) text stack list
#   DOCKER_STACK_INFO -- (out) text stack report
# Arguments:
#   None
# Returns:
#   None
################################################################
get_docker_stacks() {
    if [[ -z "${DOCKER_STACKS}" ]]; then
        if ! is_docker_present ; then
            readonly DOCKER_STACKS="No docker stacks -- docker is not installed."
            readonly DOCKER_STACK_INFO="No docker stack details -- docker is not installed."
            return
        elif ! is_docker_usable ; then
            readonly DOCKER_STACKS="Docker stacks are $UNKNOWN -- cannot access docker"
            readonly DOCKER_STACK_INFO="Docker stack details are $UNKNOWN -- cannot access docker"
            return
        elif ! is_swarm_enabled ; then
            readonly DOCKER_STACKS="Docker stacks are $UNKNOWN -- machine is not part of a docker swarm or is not the manager"
            readonly DOCKER_STACK_INFO="Docker stack details are $UNKNOWN -- machine is not part of a docker swarm or is not the manager"
            return
        fi

        echo "Getting docker stack information..."
        readonly DOCKER_STACKS="$(docker stack ls)"
        readonly DOCKER_STACK_INFO=$(
            for stack in $(docker stack ls --format '{{.Name}}'); do
                echo "------------------------------------------"
                echo
                if docker stack ps "$stack" --filter 'desired-state=running' --format '{{.CurrentState}}' | grep -aFq Pending; then
                    echo "$FAIL: some containers in stack $stack are in the Pending state."
                    echo
                fi
                echo "# docker stack services '$stack'"
                docker stack services "$stack"
                echo
                echo "# docker stack ps '$stack'"
                docker stack ps "$stack" | sed -e 's/\xE2\x80\xA6/.../'
                echo
            done
        )
    fi
}

################################################################
# Gather information about firewall configuration.
#
# Globals:
#   FIREWALL_ENABLED -- (out) TRUE/FALSE is firewall active.
#   FIREWALL_CMD -- (out) firewall command
#   FIREWALL_INFO -- (out) text list firewall information.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_firewall_info() {
    if [[ -z "${FIREWALL_ENABLED}" ]]; then
        if ! is_root ; then
            readonly FIREWALL_ENABLED="Firewall status is $UNKNOWN -- requires root access"
            readonly FIREWALL_CMD=""
            readonly FIREWALL_INFO=""
            return
        fi

        echo "Checking firewall..."
        if have_command firewall-cmd ; then
            readonly FIREWALL_CMD="firewall-cmd"
            if ! firewall-cmd --state -q ; then
                readonly FIREWALL_ENABLED="$FALSE"
                readonly FIREWALL_INFO="$(firewall-cmd --state 2>&1)"
                return
            fi

            readonly FIREWALL_ENABLED="$TRUE"
            readonly FIREWALL_INFO="Firewalld active zones: $(firewall-cmd --get-active-zones)
Firewalld all zones: $(firewall-cmd --list-all-zones)
Firewalld services: $(firewall-cmd --get-services)"
        elif have_command SuSEfirewall2 ; then
            readonly FIREWALL_CMD="SuSEfirewall2"
            if ! /sbin/rcSuSEfirewall2 status | grep -aq '^running' ; then
                readonly FIREWALL_ENABLED="$FALSE"
                readonly FIREWALL_INFO="See iptables rules section."
                return
            fi

            readonly FIREWALL_ENABLED="$TRUE"
            # IPTABLES_ALL_RULES will show configuration info.
        else
            readonly FIREWALL_ENABLED="Firewall status is $UNKNOWN -- no recognized firewall command found"
            readonly FIREWALL_CMD=""
            readonly FIREWALL_INFO=""
            return
        fi
    fi
}

################################################################
# Get information about iptables configuration.
#
# Globals:
#   IPTABLES_ALL_RULES -- (out) all rules
#   IPTABLES_DB_RULES -- (out) db rules
#   IPTABLES_HTTPS_RULES -- (out) https rules
#   IPTABLES_NAT_RULES -- (out) NAT rules
# Arguments:
#   None
# Returns:
#   None
################################################################
get_iptables() {
    if [[ -z "${IPTABLES_ALL_RULES}" ]]; then
        if ! is_root ; then
            readonly IPTABLES_ALL_RULES="iptables rules are $UNKNOWN -- requires root access"
            readonly IPTABLES_DB_RULES="iptables db rules are $UNKNOWN -- requires root access"
            readonly IPTABLES_HTTPS_RULES="iptables https rules are $UNKNOWN -- requires root access"
            readonly IPTABLES_NAT_RULES="iptables nat rules are $UNKNOWN -- requires root access"
            return
        elif ! have_command iptables ; then
            readonly IPTABLES_ALL_RULES="iptables rules are $UNKNOWN -- iptables not found."
            readonly IPTABLES_DB_RULES="iptables db rules are $UNKNOWN -- iptables not found."
            readonly IPTABLES_HTTPS_RULES="iptables https rules are $UNKNOWN -- iptables not found."
            readonly IPTABLES_NAT_RULES="iptables nat rules are $UNKNOWN -- iptables not found."
            return
        fi

        echo "Checking IP tables rules..."
        readonly IPTABLES_ALL_RULES="$(iptables --list -v)"
        readonly IPTABLES_DB_RULES="$(iptables --list | grep -aF '55436')"
        readonly IPTABLES_HTTPS_RULES="$(iptables --list | grep -aF https)"
        readonly IPTABLES_NAT_RULES="$(iptables -t nat -L -v)"
    fi
}

################################################################
# Check system entropy data.
#
# Globals:
#   AVAILABLE_ENTROPY -- (out) PASS/FAIL available entropy status
#   REQ_ENTROPY -- (in) int required available entropy
# Arguments:
#   None
# Returns:
#   true if available entropy is known and adequate.
################################################################
check_entropy() {
    if [[ -z "${AVAILABLE_ENTROPY}" ]]; then
        local -r ENTROPY_FILE="/proc/sys/kernel/random/entropy_avail"
        if [[ -e "${ENTROPY_FILE}" ]]; then
            echo "Checking entropy..."
            local -r entropy="$(cat "${ENTROPY_FILE}")"
            local -r status="$(echo_passfail "$([[ "${entropy:-0}" -gt "${REQ_ENTROPY}" ]]; echo "$?")")"
            readonly AVAILABLE_ENTROPY="Available entropy check $status.  Current entropy is $entropy, ${REQ_ENTROPY} required."
        else
            readonly AVAILABLE_ENTROPY="Available entropy is $UNKNOWN -- ${ENTROPY_FILE} not found."
        fi
    fi

    check_passfail "${AVAILABLE_ENTROPY}"
}

################################################################
# Get the contents of /etc/hosts.
#
# Globals:
#   HOSTS_FILE_CONTENTS -- (out) /etc/hosts, or an error message.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_hosts_file() {
    if [[ -z "${HOSTS_FILE_CONTENTS}" ]]; then
        local -r HOSTS_FILE="/etc/hosts"
        echo "Checking $HOSTS_FILE..."
        if [[ ! -e "$HOSTS_FILE" ]]; then
            readonly HOSTS_FILE_CONTENTS="${HOSTS_FILE} not found."
        else
            readonly HOSTS_FILE_CONTENTS="$(cat "${HOSTS_FILE}")"
        fi
    fi
}

################################################################
# Fetch the scan info report
#
# Globals:
#   MAX_SCAN_SIZE_CHECK -- (out) PASS/FAIL largest recent scan size
#   SCAN_INFO_REPORT -- (out) pruned scan info report content
#   SCAN_SIZE_LIMIT -- (out) maximum scan size permitted, in GB
# Arguments:
#   None
# Returns:
#   None
################################################################
get_scan_info_report() {
    if [[ -z "${SCAN_INFO_REPORT}" ]]; then
        if ! is_docker_present ; then
            readonly SCAN_INFO_REPORT="Scan info report is unavailable -- docker is not installed."
            readonly MAX_SCAN_SIZE_CHECK="Max scan size is $UNKNOWN -- docker is not installed."
            readonly SCAN_SIZE_LIMIT=
        else
            # Customers are allowed to scan more than 5GB on suitably robust configurations.
            # Our only sizing datapoint is for a single-threaded 21GB scan.
            [[ -n "${INSTALLATION_SIZE}" ]] || get_installation_size
            # shellcheck disable=SC2154 # These variables were set in a sneaky way.
            if [[ "${_hub_logstash_container_memory}" -ge $(_size_to_mb "2G") ]] && \
                   [[ "${_hub_jobrunner_app_memory}" -ge $(_size_to_mb "40G") ]] && \
                   [[ "${_hub_scan_app_memory}" -ge $(_size_to_mb "20G") ]]; then
                scan_limit=$((21 * GB))
            else
                scan_limit=$((5 * GB))
            fi
            readonly SCAN_SIZE_LIMIT="$((scan_limit / GB))"

            # Look for the latest scaninfo report.
            echo "Checking scaninfo data..."
            local -r full_report="$(copy_from_logstash 'debug/scaninfo-*.txt' | tail -n +2 | grep -aFv ========)"
            readonly SCAN_INFO_REPORT="$(awk '/= Code/ {done=1}; {if (done!=1) print}' <<< "${full_report}")"
            local -r codelocs="$(awk '/= Code/ {echo=1; getline; getline; next}; /^$/ {echo=0}; {if (echo==1) print}' <<< "${full_report}")"
            local -i max=-1 oversized=0
            local max_pretty="No recent scans found" unparsed=""
            while read -r data ; do
                # shellcheck disable=SC2155 # We don't care about the subcommand exit code
                local pretty="$(echo "$data" | cut -d'|' -f2 | sed -e 's/^ *//' -e 's/ *$//')"
                read -r value units <<< "$pretty"
                case "$units" in
                    EB)    size=$((value<<60));; # bash has used signed 64-bit ints since v. 3.0 (c. 2002)
                    PB)    size=$((value<<50));;
                    TB)    size=$((value<<40));;
                    GB)    size=$((value<<30));;
                    MB)    size=$((value<<20));;
                    KB)    size=$((value<<10));;
                    bytes) size=$((value));;
                    *)     size=-1; unparsed="$data";;
                esac
                if [[ "$size" -gt "$scan_limit" ]]; then ((oversized++)); fi
                if [[ "$size" -gt "$max" ]]; then max="$size"; max_pretty="$pretty"; fi
            done <<< "${codelocs}"

            local -r limit_msg="scan limit for this configuration is ${SCAN_SIZE_LIMIT}GB"
            if [[ "$oversized" -gt 0 ]]; then
                readonly MAX_SCAN_SIZE_CHECK="$FAIL -- $max_pretty${unparsed:+ (plus some unparsed data)}, $limit_msg"
            elif [[ -n "$unparsed" ]]; then
                readonly MAX_SCAN_SIZE_CHECK="$UNKNOWN -- could not parse scaninfo, $limit_msg"
            else
                readonly MAX_SCAN_SIZE_CHECK="$PASS -- $max_pretty, $limit_msg"
            fi
        fi
    fi
}

################################################################
# Get output similar to the System Information / Job page 30-day summary.
# Flag jobs with a high error rate.
#
# Globals:
#   JOB_INFO_STATUS -- (out) PASS/FAIL job inforation messages
#   JOB_INFO_REPORT -- (out) 30-day job completion summary
# Arguments:
#   None
# Returns:
#   None
################################################################
get_job_info_report() {
    if [[ -z "${JOB_INFO_STATUS}" ]]; then
        if ! is_docker_present ; then
            readonly JOB_INFO_STATUS="$UNKNOWN -- docker not installed."
            return
        elif ! is_docker_usable ; then
            readonly JOB_INFO_STATUS="$UNKNOWN -- cannot access docker."
            return
        elif ! is_postgresql_container_running ; then
            readonly JOB_INFO_STATUS="$UNKNOWN -- postgres container not found."
            return
        fi

        echo "Checking job execution status..."
        local -r postgres_container_id=$(docker container ls --format '{{.ID}} {{.Image}}' | grep -aF "blackducksoftware/blackduck-postgres:" | cut -d' ' -f1)
        local -r job_info_status="$(docker exec -i "$postgres_container_id" psql -U blackduck -A -t -d bds_hub <<EOF
            WITH data AS (
               SELECT
                  job_name,
                  SUM(job_count) AS job_count,
                  SUM(error_count) AS error_count
               FROM st.job_statistics
               WHERE name = 'DAY' AND sample_time::DATE >= now() - '30 days'::INTERVAL
               GROUP BY job_name
            )
            SELECT
               CASE WHEN error_count * 100.0 / job_count >= 10
                  THEN '$FAIL: excessive 30-day error rate '
                  ELSE '$WARN: high 30-day error rate '
               END || trim(to_char(error_count * 100.0 / job_count, '990D99%')) || ' for ' || job_name
            FROM data
            WHERE error_count * 100.0 / job_count >= 5
            ORDER BY job_name;
EOF
        )"
        readonly JOB_INFO_STATUS="${job_info_status:-$PASS}"
        readonly JOB_INFO_REPORT="$(docker exec -i "$postgres_container_id" psql -U blackduck -d bds_hub <<'EOF'
            WITH data AS (
               SELECT
                  job_name,
                  SUM(job_count) AS job_count,
                  SUM(error_count) AS error_count,
                  SUM(runtime_ms) AS runtime_ms,
                  MIN(min_runtime_ms) AS min_runtime_ms,
                  MAX(max_runtime_ms) AS max_runtime_ms
               FROM st.job_statistics
               WHERE name = 'DAY' AND sample_time::DATE >= now() - '30 days'::INTERVAL
               GROUP BY job_name
            )
            SELECT
               *,
               round(runtime_ms / job_count, 2) AS avg_runtime,
               to_char(error_count * 100.0 / job_count, '990D99%') AS error_rate
            FROM data
            ORDER BY job_name;
EOF
        )"
    fi
}

################################################################
# Helper method to see if a URL is reachable from a docker container.
# This just makes a simple web request and throws away the output.
# Status will be echoed to stdout.
#
# Globals:
#   None
# Arguments:
#   $1 - Container ID where the request should originate
#   $2 - URL to probe
#   $3 - Contiainer name
# Returns:
#   None
################################################################
echo_docker_access_url() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -eq 3 ]] || error_exit "usage: $FUNCNAME <container_id> <container_name> <url>"
    local -r container="$1"
    local -r name="$2"
    local -r url="$3"

    # Fetch proxy information and assemble the curl command options.
    # shellcheck disable=SC2046,SC2034 # Let the subcommand expand into multiple assignments.  Declare 'x' in case there are none.
    local x $(docker exec "$container" strings /proc/1/environ | sed -e 's/\(["'$'\t'\'' ]\)/\\\1/g' | grep -a '^HUB_[^=]*PROXY')
    local -a curlopts
    if [[ -n "$HUB_PROXY_HOST" ]]; then
        curlopts+=(--proxy "${HUB_PROXY_SCHEME:-http}://${HUB_PROXY_HOST}${HUB_PROXY_PORT:+:$HUB_PROXY_PORT}")
    fi
    if [[ -n "$HUB_PROXY_USER" ]]; then
        # TODO: what can we do with HUB_PROXY_WORKSTATION?
        curlopts+=(--proxy-user "$HUB_PROXY_USER${HUB_PROXY_DOMAIN:+\\$HUB_PROXY_DOMAIN}:${HUB_PROXY_PASSWORD}")
    fi
    if [[ -n "$HUB_PROXY_NON_PROXY_HOSTS" ]]; then
        curlopts+=(--noproxy "$HUB_PROXY_NON_PROXY_HOSTS")
    fi

    # Ignore bad URLs as long as the host is reachable.
    local -r msg="$(docker exec "$container" curl "${curlopts[@]}" -fsSo /dev/null "$url" 2>&1 | grep -aEv '(404 Not Found|error: 404)')"
    # shellcheck disable=SC2030,SC2031 # False positives; see https://github.com/koalaman/shellcheck/issues/1409
    echo "access $url from ${name}: $(echo_passfail "$([[ -z "$msg" ]]; echo "$?")")" "$msg"
}

################################################################
# Probe a URL from within each Black Duck docker container that
# has external access.
#
# Globals:
#   $2_CONTAINER_WEB_REPORT -- (out) text data.
# Arguments:
#   $1 - URL to probe.
#   $2 - key to prefix the result variable
#   $3 - host name
# Returns:
#   None
################################################################
get_container_web_report() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -eq 3 ]] || error_exit "usage: $FUNCNAME <url> <key> <hostname>"
    local -r url="$1"
    local -r key="$2"
    local -r host="$3"

    local -r final_var_name="${key}_CONTAINER_WEB_REPORT"
    if [[ -z "$(eval echo \$"${final_var_name}")" ]]; then
        if ! is_docker_present ; then
            echo "Skipping web report via docker containers -- docker is not installed."
            eval "readonly ${final_var_name}=\"Cannot access web via docker containers -- docker is not installed.\""
            return
        elif ! is_docker_usable ; then
            echo "Skipping web report via docker containers -- cannot access docker."
            eval "readonly ${final_var_name}=\"Web access from containers is $UNKNOWN -- cannot access docker.\""
            return
        elif ! check_hostname_resolution "$host" "$key" && ! is_unknown "$(eval echo "\${${key}_RESOLVE_RESULT}")" ; then
            echo "Skipping web report via docker containers -- hostname cannot be resolved."
            eval "readonly ${final_var_name}=\"Web access from containers is $UNKNOWN -- hostname cannot be resolved.\""
            return
        fi

        echo "Checking web access from running Black Duck docker containers to ${url} ... "
        # shellcheck disable=SC2155 # We don't care about the subcommand exit code
        local container_ids="$(docker container ls | grep -aE "blackducksoftware|sigsynopsys" | grep -aEv "$CONTAINERS_WITHOUT_CURL" | cut -d' ' -f1)"
        # shellcheck disable=SC2155 # We don't care about the subcommand exit code
        local container_report=$(
            for cur_id in ${container_ids}; do
                echo "------------------------------------------"
                docker container ls -a --filter "id=${cur_id}" --format "{{.ID}} {{.Image}}"
                cur_image="$(docker container ls -a --filter "id=${cur_id}" --format "{{.Image}}")"
                echo_docker_access_url "${cur_id}" "${cur_image}" "${url}"
                echo ""
            done
        )

        eval "readonly ${final_var_name}=\"${container_report}\""
    fi
}

################################################################
# Helper method to see if a URL is reachable.  It just makes
# a simple web request and throws away the output.
#
# Globals:
#   $2_URL_REACHABLE -- (out) PASS/FAIL status message
# Arguments:
#   $1 - url to probe
#   $2 - key to prefix the output variable
#   $3 - label to use in messages instead of the url
# Returns:
#   true if the url is reachable.
################################################################
probe_url() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -eq 3 ]] || error_exit "usage: $FUNCNAME <url> <key> <label>"
    local -r url="$1"
    local -r key="$2"
    local -r label="$3"

    local -r reachable_key="${key}_URL_REACHABLE"
    if [[ -z "$(eval echo \$"${reachable_key}")" ]]; then
        if have_command curl ; then
            echo "Checking curl access to ${label}... (this might take some time)"
            curl -s -o /dev/null "$url"
            eval "readonly ${reachable_key}=\"access ${label}: $(echo_passfail "$?")\""
        elif have_command wget ; then
            echo "Checking wget access to ${label}... (this might take some time)"
            wget -q -O /dev/null "$url"
            eval "readonly ${reachable_key}=\"access ${label}: $(echo_passfail "$?")\""
        else
            eval "readonly ${reachable_key}=\"$UNKNOWN web request to $label -- curl and wget both missing\""
        fi
    fi

    check_passfail "$(eval echo \$"${reachable_key}")"
}

################################################################
# Resolve a host name.
#
# Globals:
#   $2_RESOLVE_RESULT -- (out) pass/fail resolution status
#   $2_RESOLVE_OUTPUT -- (out) output from the lookup command
# Arguments:
#   $1 - host to be reached
#   $2 - key to prepend to the status variable
# Returns:
#   true if the host name could be resolved
################################################################
check_hostname_resolution() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -eq 2 ]] || error_exit "usage: $FUNCNAME <url> <key>"
    local -r host="$1"
    local -r key="$2"

    local result_key="${key}_RESOLVE_RESULT"
    local output_key="${key}_RESOLVE_OUTPUT"
    if [[ -z "$(eval echo \$"${result_key}")" ]]; then
        if have_command nslookup ; then
            eval "readonly ${output_key}=\"$(nslookup "$host" 2>&1)\""
            eval "echo \${${output_key}}" | grep -aFq 'Name:'
            eval "readonly ${result_key}=\"nslookup ${host}: $(echo_passfail "$?")\""
        elif have_command dig ; then
            eval "readonly ${output_key}=\"$(dig "$host" 2>&1)\""
            eval "echo \${${output_key}}" | grep -aFq 'ANSWER SECTION'
            eval "readonly ${result_key}=\"dig ${host}: $(echo_passfail "$?")\""
        else
            eval "readonly ${result_key}=\"Resolution of $host is $UNKNOWN -- nslookup and dig both missing\""
            eval "readonly ${output_key}="
        fi
    fi

    check_passfail "$(eval echo "\${${result_key}}")"
}

################################################################
# Trace packet routing to a host.
#
# Globals:
#   $2_TRACEPATH_CMD - (out) command used to obtain result
#   $2_TRACEPATH_RESULT -- (out) route to $1
# Arguments:
#   $1 - host to be reached
#   $2 - key to prepend to the status variable
# Returns:
#   None
################################################################
tracepath_host() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -eq 2 ]] || error_exit "usage: $FUNCNAME <url> <key>"
    local -r host="$1"
    local -r key="$2"

    local results_key="${key}_TRACEPATH_RESULT"
    local command_key="${key}_TRACEPATH_CMD"
    if [[ -z "$(eval echo \$"${command_key}")" ]]; then
        # Prefer TCP probes when possible.  UDP and ICMP probes are more
        # likely to be blocked, so don't probe as deeply for them.
        local tracepath_cmd
        if is_root && have_command tcptraceroute ; then
            tracepath_cmd="tcptraceroute -m 30"
        elif have_command traceroute ; then
            if is_root && traceroute --help 2>&1 | grep -aFq tcp ; then
                tracepath_cmd="traceroute --tcp -m 30"
            else
                tracepath_cmd="traceroute -m 15"
            fi
        elif have_command tracepath ; then
            tracepath_cmd="tracepath -m 15"
        fi

        if ! check_hostname_resolution "$host" "$key" && ! is_unknown "$(eval echo "\${${key}_RESOLVE_RESULT}")" ; then
            eval "readonly ${command_key}=\"Route to $host is $UNKNOWN -- hostname cannot be resolved\""
            eval "readonly ${results_key}="
        elif [[ -z "${tracepath_cmd}" ]]; then
            eval "readonly ${command_key}=\"Route to $host is $UNKNOWN -- tracepath and traceroute both missing\""
            eval "readonly ${results_key}="
        else
            echo "Tracing path to $host... (this takes time)"
            eval "readonly ${command_key}=\"${tracepath_cmd} $host\""
            local result; result="$(${tracepath_cmd} "$host" 2>&1)"
            eval "readonly ${results_key}=\"$result\""
        fi
    fi
}

################################################################
# Test connectivity with the external KB services.
#
# Globals: (set indirectly)
#   KB_RESOLVE_RESULT, KB_RESOLVE_OUTPUT,
#   KB_TRACEPATH_RESULT, KB_TRACEPATH_CMD,
#   KB_URL_REACHABLE,
#   KB_CONTAINER_WEB_REPORT
# Arguments:
#   None
# Returns:
#   true if the service url is reachable from this host.
################################################################
check_kb_reachable() {
    if [[ -z "${KB_URL_REACHABLE}" ]]; then
        if ! check_boolean "${USE_NETWORK_TESTS}" ; then
            readonly KB_URL_REACHABLE="${NETWORK_TESTS_SKIPPED}"
            return 0
        fi

        local -r KB_HOST="kb.blackducksoftware.com"
        local -r KB_URL="https://${KB_HOST}/"
        tracepath_host "${KB_HOST}" "KB"
        probe_url "${KB_URL}" "KB" "${KB_URL}"
        get_container_web_report "${KB_URL}" "KB" "${KB_HOST}"
    fi

    check_passfail "${KB_URL_REACHABLE}"
}

################################################################
# Test connectivity with the external registration service.
#
# Globals: (set indirectly)
#   REG_RESOLVE_RESULT, REG_RESOLVE_OUTPUT,
#   REG_TRACEPATH_RESULT, REG_TRACEPATH_CMD,
#   REG_URL_REACHABLE,
#   REG_CONTAINER_WEB_REPORT
# Arguments:
#   None
# Returns:
#   true if the service url is reachable from this host.
################################################################
check_reg_server_reachable() {
    if [[ -z "${REG_URL_REACHABLE}" ]]; then
        if ! check_boolean "${USE_NETWORK_TESTS}" ; then
            readonly REG_URL_REACHABLE="${NETWORK_TESTS_SKIPPED}"
            return 0
        fi

        local -r REG_HOST="updates.suite.blackducksoftware.com"
        local -r REG_URL="https://${REG_HOST}/"
        tracepath_host "${REG_HOST}" "REG"
        probe_url "${REG_URL}" "REG" "${REG_URL}"
        get_container_web_report "${REG_URL}" "REG" "${REG_HOST}"
    fi

    check_passfail "${REG_URL_REACHABLE}"
}

################################################################
# Test connectivity with the Synopsys artifactory
#
# Globals: (set indirectly)
#   SIG_REPO_RESOLVE_RESULT, SIG_REPO_RESOLVE_OUTPUT,
#   SIG_REPO_TRACEPATH_RESULT, SIG_REPO_TRACEPATH_CMD,
#   SIG_REPO_URL_REACHABLE,
#   SIG_REPO_CONTAINER_WEB_REPORT
# Arguments:
#   None
# Returns:
#   true if the service url is reachable from this host.
################################################################
check_sig_repo_reachable() {
    if [[ -z "${SIG_REPO_URL_REACHABLE}" ]]; then
        if ! check_boolean "${USE_NETWORK_TESTS}" ; then
            readonly SIG_REPO_URL_REACHABLE="${NETWORK_TESTS_SKIPPED}"
            return 0
        fi

        local -r SIG_REPO_HOST="sig-repo.synopsys.com"
        local -r SIG_REPO_URL="https://${SIG_REPO_HOST}/"
        tracepath_host "${SIG_REPO_HOST}" "SIG_REPO"
        probe_url "${SIG_REPO_URL}" "SIG_REPO" "${SIG_REPO_URL}"
        get_container_web_report "${SIG_REPO_URL}" "SIG_REPO" "${SIG_REPO_HOST}"
    fi

    check_passfail "${SIG_REPO_URL_REACHABLE}"
}

################################################################
# Test connectivity with the external Black Duck Docker registry.
#
# Globals: (set indirectly)
#   DOCKER_HUB_RESOLVE_RESULT, DOCKER_HUB_RESOLVE_OUTPUT,
#   DOCKER_HUB_TRACEPATH_RESULT, DOCKER_HUB_TRACEPATH_CMD,
#   DOCKER_HUB_URL_REACHABLE,
#   DOCKER_HUB_CONTAINER_WEB_REPORT
# Arguments:
#   None
# Returns:
#   true if the service url is reachable from this host.
################################################################
check_docker_hub_reachable() {
    if [[ -z "${DOCKER_HUB_URL_REACHABLE}" ]]; then
        if ! check_boolean "${USE_NETWORK_TESTS}" ; then
            readonly DOCKER_HUB_URL_REACHABLE="${NETWORK_TESTS_SKIPPED}"
            return 0
        fi

        local -r DOCKER_HOST="hub.docker.com"
        local -r DOCKER_URL="https://${DOCKER_HOST}/u/blackducksoftware/"
        tracepath_host "${DOCKER_HOST}" "DOCKER_HUB"
        probe_url "${DOCKER_URL}" "DOCKER_HUB" "${DOCKER_URL}"
        get_container_web_report "${DOCKER_URL}" "DOCKER_HUB" "${DOCKER_HOST}"
    fi

    check_passfail "${DOCKER_HUB_URL_REACHABLE}"
}

################################################################
# Test connectivity with the external docker registry.
#
# Globals: (set indirectly)
#   DOCKERIO_RESOLVE_RESULT, DOCKERIO_RESOLVE_OUTPUT,
#   DOCKERIO_TRACEPATH_RESULT, DOCKERIO_TRACEPATH_CMD,
#   DOCKERIO_URL_REACHABLE,
#   DOCKERIO_CONTAINER_WEB_REPORT
# Arguments:
#   None
# Returns:
#   true if the service url is reachable from this host.
################################################################
check_dockerio_reachable() {
    if [[ -z "${DOCKERIO_URL_REACHABLE}" ]]; then
        if ! check_boolean "${USE_NETWORK_TESTS}" ; then
            readonly DOCKERIO_URL_REACHABLE="${NETWORK_TESTS_SKIPPED}"
            return 0
        fi

        local -r DOCKERIO_HOST="registry-1.docker.io"
        local -r DOCKERIO_URL="https://${DOCKERIO_HOST}/"
        tracepath_host "${DOCKERIO_HOST}" "DOCKERIO"
        probe_url "${DOCKERIO_URL}" "DOCKERIO" "${DOCKERIO_URL}"
        get_container_web_report "${DOCKERIO_URL}" "DOCKERIO" "${DOCKERIO_HOST}"
    fi

    check_passfail "${DOCKERIO_URL_REACHABLE}"
}

################################################################
# Test connectivity with the external docker auth service.
#
# Globals: (set indirectly)
#   DOCKERIO_AUTH_RESOLVE_RESULT, DOCKERIO_AUTH_RESOLVE_OUTPUT,
#   DOCKERIO_AUTH_TRACEPATH_RESULT, DOCKERIO_AUTH_TRACEPATH_CMD,
#   DOCKERIO_AUTH_URL_REACHABLE,
#   DOCKERIO_AUTH_CONTAINER_WEB_REPORT
# Arguments:
#   None
# Returns:
#   true if the service url is reachable from this host.
################################################################
check_dockerio_auth_reachable() {
    if [[ -z "${DOCKERIOAUTH_URL_REACHABLE}" ]]; then
        if ! check_boolean "${USE_NETWORK_TESTS}" ; then
            readonly DOCKERIOAUTH_URL_REACHABLE="${NETWORK_TESTS_SKIPPED}"
            return 0
        fi

        local -r DOCKERIO_AUTH_HOST="auth.docker.io"
        local -r DOCKERIO_AUTH_URL="https://${DOCKERIO_AUTH_HOST}/"
        tracepath_host "${DOCKERIO_AUTH_HOST}" "DOCKERIOAUTH"
        probe_url "${DOCKERIO_AUTH_URL}" "DOCKERIOAUTH" "${DOCKERIO_AUTH_URL}"
        get_container_web_report "${DOCKERIO_AUTH_URL}" "DOCKERIOAUTH" "${DOCKERIO_AUTH_HOST}"
    fi

    check_passfail "${DOCKERIOAUTH_URL_REACHABLE}"
}

################################################################
# Test connectivity with github.com.
#
# Globals: (set indirectly)
#   GITHUB_RESOLVE_RESULT, GITHUB_RESOLVE_OUTPUT,
#   GITHUB_TRACEPATH_RESULT, GITHUB_TRACEPATH_CMD,
#   GITHUB_URL_REACHABLE,
#   GITHUB_CONTAINER_WEB_REPORT
# Arguments:
#   None
# Returns:
#   true if the service url is reachable from this host.
################################################################
check_github_reachable() {
    if [[ -z "${GITHUB_URL_REACHABLE}" ]]; then
        if ! check_boolean "${USE_NETWORK_TESTS}" ; then
            readonly GITHUB_URL_REACHABLE="${NETWORK_TESTS_SKIPPED}"
            return 0
        fi

        local -r GITHUB_HOST="github.com"
        local -r GITHUB_URL="https://${GITHUB_HOST}/blackducksoftware/hub/"
        tracepath_host "${GITHUB_HOST}" "GITHUB"
        probe_url "${GITHUB_URL}" "GITHUB" "${GITHUB_URL}"
        get_container_web_report "${GITHUB_URL}" "GITHUB" "${GITHUB_HOST}"
    fi

    check_passfail "${GITHUB_URL_REACHABLE}"
}

################################################################
# Get the current user limits.
#
# Globals:
#   ULIMIT_RESULTS -- (out) text data, or an error message.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_ulimits() {
    echo "Getting ulimits..."
    if [[ -z "${ULIMIT_RESULTS}" ]]; then
        if ! have_command ulimit ; then
            readonly ULIMIT_RESULTS="User limits are $UNKNOWN -- ulimit not found"
        else
            # probably meaningless if running as root
            readonly ULIMIT_RESULTS="$(ulimit -a)"
        fi
    fi
}

################################################################
# Get the current SELinux status.
#
# Globals:
#   SELINUX_STATUS -- (out) text status, or an error message.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_selinux_status() {
    echo "Checking SELinux..."
    if [[ -z "${SELINUX_STATUS}" ]]; then
        if ! have_command sestatus ; then
            readonly SELINUX_STATUS="SELinux status is $UNKNOWN -- sestatus not found"
        else
            readonly SELINUX_STATUS="$(sestatus)"
        fi
    fi
}

################################################################
# Check that webapp, postgres, jobrunner, etc.. do not resolve
# in DNS on the host.   These should not resolve, so success
# means they are not found in DNS.
#
# Globals:
#   <hostname>_dns_status -- (out) PASS/FAIL status or an error message.
#     One global per each of the Black Duck container names,
#     uppercased and with '-' replaced by '_'.
#   INTERNAL_HOSTNAMES_DNS_STATUS -- (out) PASS/FAIL overall status.
# Arguments:
#   None
# Returns:
#   true if none of the Black Duck container names resolve.
################################################################
check_internal_hostnames_dns_status() {
    echo "Checking host names for DNS conflicts..."
    if [[ -z "${INTERNAL_HOSTNAMES_DNS_STATUS}" ]]; then
        local overall_status=${PASS}
        for cur_hostname in ${HUB_RESERVED_HOSTNAMES} ; do
            # shellcheck disable=SC2155 # We don't care about the subcommand exit code
            local cur_status=$(probe_dns_hostname "${cur_hostname}")
            # shellcheck disable=SC2155 # We don't care about the subcommand exit code
            local hostname_upper=$(echo "${cur_hostname}" | awk '{print toupper($0)}' | tr '-' '_')
            # shellcheck disable=SC2155 # We don't care about the subcommand exit code
            local cur_global_var_name="${hostname_upper}_DNS_STATUS"
            eval "export ${cur_global_var_name}=\"${cur_status}\""

            if ! check_passfail "${cur_status}" ; then
                overall_status=${FAIL}
            fi
        done

        readonly INTERNAL_HOSTNAMES_DNS_STATUS="${overall_status}"
    fi

    check_passfail "${INTERNAL_HOSTNAMES_DNS_STATUS}"
}

################################################################
# Helper to check that a host name does NOT resolve.
# - Assumed to be run in a subshell
# - echos its return value to stdout
#
# Arguments:
#   $1 - the hostname to check
# Returns:
#   None
################################################################
probe_dns_hostname() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -eq 1 ]] || error_exit "usage: $FUNCNAME <hostname>"
    local -r hostname="$1"

    if ! have_command nslookup ; then
        local -r dns_status="DNS resolution of '${hostname}' is $UNKNOWN -- nslookup not found."
    elif ! nslookup "${hostname}" >/dev/null 2>&1 ; then
        local -r dns_status="$PASS: hostname '${hostname}' does not resolve in this environment."
    else
        local -r dns_status="$WARN: hostname '${hostname}' resolved.  This could cause problems.  See 'RESERVED_HOSTNAMES' below."
    fi

    echo "${dns_status}"
}

################################################################
# Generate DNS check report section
# - echos the DNS status check information to stdout
#
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
################################################################
generate_dns_checks_report_section() {
    for cur_hostname in ${HUB_RESERVED_HOSTNAMES} ; do
        echo "Hostname \"${cur_hostname}\" DNS Status:"
        # shellcheck disable=SC2155 # We don't care about the subcommand exit code
        local cur_hostname_upper=$(echo "${cur_hostname}" | awk '{print toupper($0)}' | tr '-' '_')
        printenv "${cur_hostname_upper}_DNS_STATUS"
        echo ""
    done

    if ! check_passfail "${INTERNAL_HOSTNAMES_DNS_STATUS}" ; then
        cat <<'EOF'

RESERVED_HOSTNAMES: docker swarm services use virtual host names.  If
  service names are also valid host names race conditions in DNS
  lookup can cause internal requests to be routed incorrectly.

RECOMMENDATION: if traffic meant for docker services is being
  misdirected rename the external hosts with conflicting names.
EOF
    fi
}

################################################################
# Capture recent system logs
# - echos information to stdout
#
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
################################################################
generate_system_logs_report_section() {
    local -r maxlines=1000
    local docker_limited=
    for log in /var/log/messages /var/log/syslog /var/log/daemon.log /var/log/mcelog /var/log/system.log /var/log/kern.log ; do
        if [[ -r "$log" ]]; then
            echo "${log}:"
            echo "${log}:" | tr -c '\n' '-'
            # shellcheck disable=SC2155 # We don't care about the subcommand exit code
            local lines="$(wc -l "$log" | cut -d' ' -f1)"
            [[ "$lines" -le $maxlines ]] || echo "... skipping $((lines - maxlines)) lines"
            if tail -n $maxlines "$log" | grep -Fq 'https://www.docker.com/increase-rate-limit'; then docker_limited="$log"; fi
            tail -n $maxlines "$log"
            echo
        fi
    done

    if have_command "journalctl" ; then
        local -r cmd="journalctl -q -m --no-pager -n $maxlines -u docker"
        echo "${cmd}:"
        echo "${cmd}:" | tr -c '\n' '-'
        if $cmd 2>&1 | grep -Fq 'https://www.docker.com/increase-rate-limit'; then docker_limited="journalctl"; fi
        $cmd 2>&1
    fi

    if [[ -n "$docker_limited" ]]; then
        echo
        echo "$FAIL: $docker_limited shows that the docker image pull rate limit was hit."
    fi
}

################################################################
# Get count of any snippet_adjustment entries with an invalid basedir.
#
# Globals:
#   SNIPPET_BASEDIR_STATUS -- (out) pass/warn or error message.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_snippet_invalid_basedir_count() {
    if [[ -z "$SNIPPET_BASEDIR_STATUS" ]]; then
        if ! is_docker_present ; then
            readonly SNIPPET_BASEDIR_STATUS="$UNKNOWN -- docker not installed."
            return
        elif ! is_docker_usable ; then
            readonly SNIPPET_BASEDIR_STATUS="$UNKNOWN -- cannot access docker."
            return
        elif ! is_postgresql_container_running ; then
            readonly SNIPPET_BASEDIR_STATUS="$UNKNOWN -- postgres container not found."
            return
        fi

        local -r postgres_container_id=$(docker container ls --format '{{.ID}} {{.Image}}' | grep -aF "blackducksoftware/blackduck-postgres:" | cut -d' ' -f1)
        local -r num_invalid_entries=$(docker exec -i "$postgres_container_id" sh -c "psql -U blackduck -X -A -d bds_hub -t -c 'select count(*) from ${SCHEMA_NAME}.snippet_adjustment where basedir = uri' | tr -d '\r' 2>/dev/null" || echo "-1")

        if [[ "$num_invalid_entries" -eq -1 ]]; then
            readonly SNIPPET_BASEDIR_STATUS="$UNKNOWN -- failed to retrieve number of invalid base directories present for snippet adjustments."
        elif [[ "$num_invalid_entries" -gt 0 ]]; then
            readonly SNIPPET_BASEDIR_STATUS="$WARN: $num_invalid_entries invalid base directories present for snippet adjustments."
        else
            readonly SNIPPET_BASEDIR_STATUS="$PASS: No invalid base directories present for snippet adjustments."
        fi
    fi
}

################################################################
# Gather information about database table bloat.
#
# Globals:
#   DATABASE_BLOAT_INFO -- (out) database information message
# Arguments:
#   None
# Returns:
#   None
################################################################
get_database_bloat_info() {
    if [[ -z "$DATABASE_BLOAT_INFO" ]]; then
        if ! is_docker_present ; then
            readonly DATABASE_BLOAT_INFO="$UNKNOWN -- docker not installed."
            return
        elif ! is_docker_usable ; then
            readonly DATABASE_BLOAT_INFO="$UNKNOWN -- cannot access docker."
            return
        elif ! is_postgresql_container_running ; then
            readonly DATABASE_BLOAT_INFO="$UNKNOWN -- postgres container not found."
            return
        fi

        local -r postgres_container_id=$(docker container ls --format '{{.ID}} {{.Image}}' | grep -aF "blackducksoftware/blackduck-postgres:" | cut -d' ' -f1)
        readonly DATABASE_BLOAT_INFO=$(docker exec -i "$postgres_container_id" sh -c "psql -U blackduck -X -d bds_hub 2>&1" <<-'EOF'
        SELECT * FROM (
            SELECT
              current_database(), schemaname, tablename, reltuples::bigint, relpages::bigint,
              ROUND((CASE WHEN otta=0 THEN 0.0 ELSE sml.relpages::float/otta END)::numeric,1) AS tbloat,
              CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::BIGINT END AS wastedbytes
            FROM (
              SELECT
                schemaname, tablename, cc.reltuples, cc.relpages, bs,
                CEIL((cc.reltuples*((datahdr+ma- (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::float)) AS otta
              FROM (
                SELECT
                  ma,bs,schemaname,tablename,
                  (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
                  (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
                FROM (
                  SELECT
                    schemaname, tablename, hdr, ma, bs,
                    SUM((1-null_frac)*avg_width) AS datawidth,
                    MAX(null_frac) AS maxfracsum,
                    hdr+(
                      SELECT 1+count(*)/8
                      FROM pg_stats s2
                      WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
                    ) AS nullhdr
                  FROM pg_stats s, (
                    SELECT
                      (SELECT current_setting('block_size')::numeric) AS bs,
                      CASE WHEN substring(v,12,3) IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
                      CASE WHEN v ~ 'mingw32' THEN 8 ELSE 4 END AS ma
                    FROM (SELECT version() AS v) AS foo
                  ) AS constants
                  GROUP BY 1,2,3,4,5
                ) AS foo
              ) AS rs
              JOIN pg_class cc ON cc.relname = rs.tablename
              JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = rs.schemaname AND nn.nspname <> 'information_schema'
              WHERE cc.relkind IN ('r', 't')
            ) AS sml
        ) AS t
        WHERE wastedbytes > 0
        ORDER BY schemaname DESC, wastedbytes DESC;
EOF
                 )
    fi
}

################################################################
# Read a file from a local volume or container.
#
# Wildcards are allowed in the source path, but if it resolves
# to multiple files only the last one alphabetically is processed.
#
# Globals:
#   None
# Arguments:
#   $1 - source file relative path in the volume
#   $2 - target file
#   $3 - distinctive volume name fragment
#   $4 - distinctive image name fragment
#   $5 - volume mount point inside the container
# Returns:
#   None
################################################################
copy_from_docker() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -le 5 ]] || error_exit "usage: $FUNCNAME <source> <target> <volume> <image> <container_dir>"
    local -r source="$1"
    local -r target="$2"
    local -r volume="$3"
    local -r image="$4"
    local -r mount="$5"

    if is_docker_usable ; then
        local -r volume_dir="$(docker volume ls -f name=_"$volume"-volume --format '{{.Mountpoint}}')"
        local -r id="$(docker container ls | grep -aF "blackducksoftware/blackduck-${image}:" | cut -d' ' -f1)"
        if [[ -e "$volume_dir" ]]; then
            local path="${volume_dir}/$source"
            # shellcheck disable=SC2086,SC2012 # $source is unquoted so that wildcards will expand.  Use 'ls' instead of 'find'.
            if is_glob "$source"; then path="$(set +o noglob; \ls "${volume_dir}"/$source | tail -1; set -o noglob)"; fi
            if [[ "$target" == "-" ]]; then
                cat "$path" 2>/dev/null
            else
                cp "$path" "$target" 2>/dev/null
            fi
        elif [[ -n "$id" ]]; then
            # If we are running on a Mac the volume storage is not exposed on the host.
            # Try copying from a running container.
            local path="$source"
            if is_glob "$source" ; then
                # 'docker cp' does not support wildcards.  Try to expand them.
                path="$(docker exec "${id}" sh -c "ls $source" 2>/dev/null | tail -1)"
            fi
            [[ -z "${path}" ]] || docker cp "${id}:$mount/${path}" "$target" 2>/dev/null
        elif [[ -n "$volume_dir" ]]; then
            # No running container.  Try to make one.
            local -r tmp_run='docker run --rm -v /:/vols -u 0 -i alpine:edge'
            local path="$source"
            if is_glob "$source"; then path="$($tmp_run sh -c "cd /vols/${volume_dir} && ls $source 2>/dev/null | tail -1")"; fi
            if [[ "$target" == "-" ]]; then
                $tmp_run sh -c "cat /vols/${volume_dir}/$path" 2>/dev/null
            else
                $tmp_run sh -c "cat /vols/${volume_dir}/$path" >"$target" 2>/dev/null
            fi
        fi
    fi
}

################################################################
# Copy a file from the logstash volume if possible.
#
# Globals:
#   None
# Arguments:
#   $1 - source file path
#   $2 - output file name, defaults to stdout
# Returns:
#   None
################################################################
copy_from_logstash() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -eq 1 ]] || [[ "$#" -eq 2 ]] || error_exit "usage: $FUNCNAME <source> [ <target> ]"
    local -r source="$1"
    local -r target="${2:--}"
    copy_from_docker "$source" "$target" "log" "logstash" "/var/lib/logstash/data"
}

################################################################
# Copy a file to a local volume or container.
#
# Globals:
#   None
# Arguments:
#   $1 - source file path
#   $2 - target file relative path in the volume
#   $3 - distinctive volume name fragment
#   $4 - distinctive image name fragment
#   $5 - volume mount point inside the container
# Returns:
#   None
################################################################
copy_to_docker() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -le 5 ]] || error_exit "usage: $FUNCNAME <source-path> <target-name> <volume> <image> <container_dir>"
    local -r source="$1"
    local -r target="$2"
    local -r volume="$3"
    local -r image="$4"
    local -r mount="$5"

    if is_docker_usable ; then
        local -r volume_dir="$(docker volume ls -f name=_"$volume"-volume --format '{{.Mountpoint}}')"
        local -r id="$(docker container ls | grep -aF "blackducksoftware/blackduck-${image}:" | cut -d' ' -f1)"
        if [[ -e "$volume_dir" ]]; then
            echo "Copying $source into the $volume volume."
            local -r owner=$(find "$volume_dir" -mindepth 1 -maxdepth 1 -exec stat -c '%u' '{}' \; -quit | tr -d '\r')
            cp "$source" "${volume_dir}/$target"
            chmod 664 "${volume_dir}/$target"
            chown "${owner:-root}":root "${volume_dir}/${target}"
        elif [[ -n "$id" ]]; then
            # If we are running on a Mac the volume storage is not exposed on the host.
            # Try copying into a running container.
            echo "Copying $source into the $image container."
            local -r owner=$(docker exec "$id" find "$mount" -mindepth 1 -maxdepth 1 -exec stat -c '%u' '{}' \; | head -1 | tr -d '\r')
            docker cp "$source" "${id}:$mount/$target"
            docker exec -u 0 "$id" chmod 664 "$mount/$target"
            docker exec -u 0 "$id" chown "${owner:-root}":root "$mount/$target"
        elif [[ -n "$volume_dir" ]]; then
            # No running container.  Try to make one.
            echo "Copying $source into a temporary container."
            local -r tmp_run='docker run --rm -v /:/vols -u 0 -i alpine:edge'
            local -r owner=$($tmp_run sh -c "find '/vols/${volume_dir}' -mindepth 1 -maxdepth 1 -exec stat -c '%u' '{}' \\; | head -1 | tr -d '\\r'")
            $tmp_run sh -c "cat > /vols/${volume_dir}/$target" < "$source"
            $tmp_run chmod 664 "/vols/${volume_dir}/$target"
            $tmp_run chown "${owner:-root}":root "/vols/${volume_dir}/$target"
        else
            echo "No local $volume volume or $image container found, skipping copy of $source"
        fi
    fi
}

################################################################
# Copy a file to the logstash volume if possible.
#
# Globals:
#   OUTPUT_FILE -- (in) default source file
# Arguments:
#   $1 - source file path, default "${OUTPUT_FILE}"
#   $2 - output file name, default "latest_system_check.txt"
# Returns:
#   None
################################################################
copy_to_logstash() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -le 2 ]] || error_exit "usage: $FUNCNAME [ <report-path> [ <copy-simple-name> ] ]"
    local -r source="${1:-$OUTPUT_FILE}"
    local -r target="${2:-latest_system_check.txt}"
    copy_to_docker "$source" "$target" "log" "logstash" "/var/lib/logstash/data"
}

################################################################
# Copy a file to the config volume if possible.  That will not
# be possible if the registration container is running on a
# different node.
#
# Globals:
#   PROPERTIES_FILE -- (in) default source file
# Arguments:
#   $1 - source file path, default "${PROPERTIES_FILE}"
#   $2 - output file name, default "latest_system_check.properties"
# Returns:
#   None
################################################################
copy_to_config() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -le 2 ]] || error_exit "usage: $FUNCNAME [ <file-path> [ <copy-simple-name> ] ]"
    local -r source="${1:-$PROPERTIES_FILE}"
    local -r target="${2:-latest_system_check.properties}"
    copy_to_docker "$source" "$target" "config" "registration" "/opt/blackduck/hub/hub-registration/config"
}

readonly REPORT_SEPARATOR='=============================================================================='

################################################################
# Echo a report section header to stdout and update the
# report table of contents file.
#
# Globals:
#   OUTPUT_FILE_TOC -- (in) temporary file storing the TOC.
# Arguments:
#   $1 - section title
#   $2 - count (optional)
# Returns:
#   None
################################################################
generate_report_section() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -le 2 ]] || error_exit "usage: $FUNCNAME <title> [ <count> ]"
    local -r title="$1"
    local -r count="${2:-$(( $(grep -ac . "${OUTPUT_FILE_TOC}") + 1 ))}"

    echo "${REPORT_SEPARATOR}"
    echo "${count}. ${title}" | tee -a "${OUTPUT_FILE_TOC}"
}

################################################################
# Save a full report to disk.  Assumes that all data has been
# collected and is available in global variables.
#
# Globals:
#   OUTPUT_FILE -- (in) default output file path.
#   FAILURES -- (out) list of failures reported.
#   WARNINGS -- (out) list of warnings reported.
#   ... -- (in) everything.
# Arguments:
#   $1 - output file path, default "${OUTPUT_FILE}"
# Returns:
#   None
################################################################
generate_report() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -le 1 ]] || error_exit "usage: $FUNCNAME [ <report-path> ]"
    local -r target="${1:-$OUTPUT_FILE}"

    # Reserve this section number; the body will be generated later.
    echo "1. Problems found" > "${OUTPUT_FILE_TOC}"

    local -r header="${REPORT_SEPARATOR}
System check version $HUB_VERSION report for Black Duck version ${RUNNING_HUB_VERSION}
  generated at $NOW on $(hostname -f)

Approximate installation size: ${INSTALLATION_SIZE}
"
    local -r report=$(cat <<END
$(generate_report_section "Operating System information")

Supported OS (Linux): ${IS_LINUX}

OS Info:
${OS_NAME}

Kernel version check: ${KERNEL_VERSION_STATUS}

Approximate installation size: ${INSTALLATION_SIZE}
${INSTALLATION_SIZE_DETAILS}

${INSTALLATION_SIZE_MESSAGES}

$(generate_report_section "Performance hints")

Hyperthreading: ${HYPERTHREADING_STATUS}
${HYPERTHREADING_INFO}

I/O scheduling: ${IOSCHED_STATUS}
${IOSCHED_INFO}

${HYPERTHREADING_DESCRIPTION}

${IOSCHED_DESCRIPTION}

HIBERNATING_CLIENTS: although it cannot be tested by this script,
  client systems that hibernate or sleep while scanning can severely
  impact scan performance.

$(generate_report_section "Package list")

Anti-virus package check: ${ANTI_VIRUS_PACKAGE_STATUS}
${ANTI_VIRUS_PACKAGE_MESSAGE}

${PACKAGE_LIST}

$(generate_report_section "User information")

Current user: ${CURRENT_USERNAME}

Current user limits:
${ULIMIT_RESULTS}

$(generate_report_section "SELinux")

${SELINUX_STATUS}

$(generate_report_section "CPU info")

${CPU_INFO}

CPU count:
${CPU_COUNT_STATUS}

$(generate_report_section "Memory info")

${MEMORY_INFO}

RAM check:
${SUFFICIENT_RAM_STATUS}

$(generate_report_section "Disk info")

Free disk space:
${DISK_SPACE_STATUS}

Disk info:
${DISK_SPACE}

$(generate_report_section "Available entropy")

Available entropy (0-100 - Problem Level, 100-200 Warning, 200+ OK):
$AVAILABLE_ENTROPY

$(generate_report_section "Network interface configuration")

${IFCONFIG_DATA}

$(generate_report_section "/etc/hosts")

${HOSTS_FILE_CONTENTS}

$(generate_report_section "IP routing")

${ROUTING_TABLE}

$(generate_report_section "Network bridge info")

${BRIDGE_INFO}

$(generate_report_section "Ports in use")

${LISTEN_PORTS}

$(generate_report_section "iptables rules")

HTTPS iptables rules:
${IPTABLES_HTTPS_RULES}

Black Duck DB port iptables rules:
${IPTABLES_DB_RULES}

All iptables rules:
${IPTABLES_ALL_RULES}

NAT iptables rules:
${IPTABLES_NAT_RULES}

Black Duck ports:
${SPECIFIC_PORT_RESULTS}

$(generate_report_section "Firewall")

Firewall enabled: ${FIREWALL_ENABLED}

Firewall type: ${FIREWALL_CMD}

Firewall information: ${FIREWALL_INFO}

$(generate_report_section "Sysctl Network Settings")

IP forwarding check ${SYSCTL_IP_FORWARDING_STATUS}

IPV4 Keepalive Time: ${SYSCTL_KEEPALIVE_TIME}
IPV4 Keepalive Time recommendation ${SYSCTL_KEEPALIVE_TIME_STATUS}

IPV4 Keepalive Interval: ${SYSCTL_KEEPALIVE_INTERVAL}
IPV4 Keepalive Probes: ${SYSCTL_KEEPALIVE_PROBES}

IPVS timeouts: ${IPVS_TIMEOUTS}
IPVS timeout check ${IPVS_TIMEOUT_STATUS}

${TCP_KEEPALIVE_TIMEOUT_DESC}

$(generate_report_section "Login manager settings")

Login manager settings: ${LOGINCTL_STATUS}

${LOGINCTL_INFO}

${LOGINCTL_RECOMMENDATION}

$(generate_report_section "Running processes")

Anti-virus process check: ${ANTI_VIRUS_PROCESS_STATUS}
${ANTI_VIRUS_PROCESS_MESSAGE}

${RUNNING_PROCESSES}

$(generate_report_section "Docker")

Docker installed: ${IS_DOCKER_PRESENT}
Docker version: ${DOCKER_VERSION}
Docker edition: ${DOCKER_EDITION}
Docker version check: ${DOCKER_VERSION_CHECK}
Docker versions supported: ${REQ_DOCKER_VERSIONS}
Docker compose installed: ${IS_DOCKER_COMPOSE_PRESENT}
Docker compose version: ${DOCKER_COMPOSE_VERSION}
Docker startup: ${DOCKER_STARTUP_INFO}
Docker OS Compatibility Check: ${DOCKER_OS_COMPAT}

${DOCKER_VERSION_INFO}

$(generate_report_section "Docker system information")

${DOCKER_SYSTEM_DF}

${DOCKER_SYSTEM_INFO}

$(generate_report_section "Docker overrides")

$(cat ../docker-compose.local-overrides.yml 2>/dev/null || echo "Overrides file not found.")

$(generate_report_section "Docker image list")

Running Black Duck versions: ${RUNNING_VERSION_STATUS}
  Black Duck version: ${RUNNING_HUB_VERSION}
  BDBA version: ${RUNNING_BDBA_VERSION}
  Alert version: ${RUNNING_ALERT_VERSION}
  other Black Duck products: ${RUNNING_OTHER_VERSIONS}

${DOCKER_IMAGES}

${DOCKER_IMAGE_INSPECTION}

$(generate_report_section "Docker container list")

${DOCKER_CONTAINERS}

$(generate_report_section "Docker container details")

Docker memory limit checks:

${DOCKER_MEMORY_CHECKS}

Local container health checks:

${CONTAINER_HEALTH_CHECKS}
${CONTAINER_OOM_CHECKS}

Local container details:

${DOCKER_CONTAINER_INSPECTION}

$(generate_report_section "Docker process list")

${DOCKER_PROCESSES}

$(generate_report_section "Docker network list")

${DOCKER_NETWORKS}

${DOCKER_NETWORK_INSPECTION}

$(generate_report_section "Docker volume list")

${DOCKER_VOLUMES}

${DOCKER_VOLUME_INSPECTION}

$(generate_report_section "Docker nodes")

${DOCKER_NODES}

${DOCKER_NODE_INSPECTION}

$(generate_report_section "Docker customizations")

Environment variables

${DOCKER_SERVICE_ENVIRONMENT:-$DOCKER_CONTAINER_ENVIRONMENT}

$(generate_report_section "Docker services")

${DOCKER_SERVICES}

${DOCKER_SERVICE_INFO}

$(generate_report_section "Docker stacks")

${DOCKER_STACKS}

${DOCKER_STACK_INFO}

$(generate_report_section "Black Duck KB services connectivity")

${KB_URL_REACHABLE}

Name resolution: ${KB_RESOLVE_RESULT}
${KB_RESOLVE_OUTPUT}

Path information: ${KB_TRACEPATH_CMD}
${KB_TRACEPATH_RESULT}

Web access to Black Duck KB via docker containers:
${KB_CONTAINER_WEB_REPORT}

$(generate_report_section "Black Duck registration server connectivity")

${REG_URL_REACHABLE}

Name resolution: ${REG_RESOLVE_RESULT}
${REG_RESOLVE_OUTPUT}

Path information: ${REG_TRACEPATH_CMD}
${REG_TRACEPATH_RESULT}

Web access to Black Duck registration service via docker containers:
${REG_CONTAINER_WEB_REPORT}

$(generate_report_section "Synopsys artifactory connectivity")

${SIG_REPO_URL_REACHABLE}

Name resolution: ${SIG_REPO_RESOLVE_RESULT}
${SIG_REPO_RESOLVE_OUTPUT}

Path information: ${SIG_REPO_TRACEPATH_CMD}
${SIG_REPO_TRACEPATH_RESULT}

Web access to Synopsys artifactory via docker containers:
${SIG_REPO_CONTAINER_WEB_REPORT}

$(generate_report_section "Black Duck Docker registry connectivity")

${DOCKER_HUB_URL_REACHABLE}

Name resolution: ${DOCKER_HUB_RESOLVE_RESULT}
${DOCKER_HUB_RESOLVE_OUTPUT}

Path information: ${DOCKER_HUB_TRACEPATH_CMD}
${DOCKER_HUB_TRACEPATH_RESULT}

Web access to Black Duck Docker registry via docker containers:
${DOCKER_HUB_CONTAINER_WEB_REPORT}

$(generate_report_section "Docker IO registry connectivity")

${DOCKERIO_URL_REACHABLE}

Name resolution: ${DOCKERIO_RESOLVE_RESULT}
${DOCKERIO_RESOLVE_OUTPUT}

Path information: ${DOCKERIO_TRACEPATH_CMD}
${DOCKERIO_TRACEPATH_RESULT}

Web access to Docker IO Registry via docker containers:
${DOCKERIO_CONTAINER_WEB_REPORT}

$(generate_report_section "Docker IO Auth connectivity")

${DOCKERIOAUTH_URL_REACHABLE}

Name resolution: ${DOCKERIOAUTH_RESOLVE_RESULT}
${DOCKERIOAUTH_RESOLVE_OUTPUT}

Path information: ${DOCKERIOAUTH_TRACEPATH_CMD}
${DOCKERIOAUTH_TRACEPATH_RESULT}

Web access to Docker IO Auth server via docker containers:
${DOCKERIOAUTH_CONTAINER_WEB_REPORT}

$(generate_report_section "GitHub connectivity")

${GITHUB_URL_REACHABLE}

Name resolution: ${GITHUB_RESOLVE_RESULT}
${GITHUB_RESOLVE_OUTPUT}

Path information: ${GITHUB_TRACEPATH_CMD}
${GITHUB_TRACEPATH_RESULT}

Web access to GitHub via docker containers:
${GITHUB_CONTAINER_WEB_REPORT}

$(generate_report_section "System logs")

$(generate_system_logs_report_section)

$(generate_report_section "Misc. DNS checks")

$(generate_dns_checks_report_section)

$(generate_report_section "Misc. DB checks")

Invalid base directories:
${SNIPPET_BASEDIR_STATUS}

Database bloat:
${DATABASE_BLOAT_INFO}

$(generate_report_section "Scan info report")

Max recent scan size: $MAX_SCAN_SIZE_CHECK

Scan info:
$SCAN_INFO_REPORT

$(generate_report_section "Job info report")

Job execution status: $JOB_INFO_STATUS

Completion status summary for the last 30 days:
$JOB_INFO_REPORT

${REPORT_SEPARATOR}
END
)

    # Filter out some false positives when looking for failures/warnings:
    # - The abrt-watch-log command line has args like 'abrt-watch-log -F BUG: WARNING: at WARNING: CPU:'
    # - Redis sentinel mode uses a BLACKDUCK_REDIS_SENTINEL_FAILOVER_TIMEOUT environment variable.
    # - The omiagent command line can have args like '--loglevel WARNING'
    readonly FAILURES="$(echo "$report" | grep -aF "$FAIL" | grep -avF abrt-watch-log | grep -avF "${FAIL}_" | grep -avF FAILOVER)"
    readonly WARNINGS="$(echo "$report" | grep -aF "$WARN" | grep -avF abrt-watch-log | grep -avF "${WARN}_" | grep -avF -e "--loglevel ${WARN}" | grep -av "${WARN}:[^ ]")"

    { echo "$header"; echo "Table of contents:"; echo; sort -n "${OUTPUT_FILE_TOC}"; echo; } > "${target}"
    cat >> "${target}" <<END
$(generate_report_section "Problems detected" 1)

${FAILURES:-No failures.}

${WARNINGS:-No warnings.}

END
    echo "$report" | cat -s >> "${target}"
}

################################################################
# Save a properties file to disk.  Assumes that generate_report
# has already been called to set failures and warnings.
#
# Globals:
#   PROPERTIES_FILE -- (in) default output file path.
#   FAILURES -- (in) list of failures reported.
#   WARNINGS -- (in) list of warnings reported.
# Arguments:
#   $1 - output file path, default "${PROPERTIES_FILE}"
# Returns:
#   None
################################################################
generate_properties() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -le 1 ]] || error_exit "usage: $FUNCNAME [ <report-path> ]"
    local -r target="${1:-$PROPERTIES_FILE}"
    # Note: reggie (which handles SalesForce integration) might depend on
    #    these properties.  Don't change existing ones without checking!
    # shellcheck disable=SC2116 # Deliberate extra echo to collapse lines
    cat >> "${target}" <<EOF
# System check properties ${target}
systemCheck.cpuCount=${CPU_COUNT}
systemCheck.dateCreated=${NOW_ZULU}
systemCheck.diskSpaceTotal=${DISK_SPACE_TOTAL}
systemCheck.dockerOrchestrator=${DOCKER_ORCHESTRATOR}
systemCheck.dockerVersion=${DOCKER_VERSION}
systemCheck.failures=$(echo "$FAILURES" | wc -l)
systemCheck.hostname=$(hostname -f)
systemCheck.hubVersion=${RUNNING_HUB_VERSION}
systemCheck.memory=${SUFFICIENT_RAM}
systemCheck.nodeCount=${DOCKER_NODE_COUNT}
systemCheck.osName=${OS_NAME_SHORT}
systemCheck.scriptVersion=${HUB_VERSION}
systemCheck.warnings=$(echo "$WARNINGS" | wc -l)
EOF
}

################################################################
# Save a summary of the output to disk.  Assumes that
# generate_report has already been called to set failures and
# warnings.
#
# Globals:
#   SUMMARY_FILE -- (in) default output file path.
#   FAILURES -- (in) list of failures reported.
#   WARNINGS -- (in) list of warnings reported.
# Arguments:
#   $1 - output file path, default "${SUMMARY_FILE}"
# Returns:
#   None
################################################################
generate_summary() {
    # shellcheck disable=SC2128 # $FUNCNAME[0] does not work in Alpine ash
    [[ "$#" -le 1 ]] || error_exit "usage: $FUNCNAME [ <report-path> ]"
    local -r target="${1:-$SUMMARY_FILE}"
    # shellcheck disable=SC2116
    cat >> "${target}" <<EOF
# System check summary ${target}
systemCheck.dateCreated=${NOW_ZULU}
systemCheck.cpuCount=${CPU_COUNT}
systemCheck.diskSpaceTotal=${DISK_SPACE_TOTAL}
systemCheck.memory=${SUFFICIENT_RAM}
systemCheck.scanSizeLimit=${SCAN_SIZE_LIMIT}
systemCheck.hostname=$(hostname -f)
systemCheck.osName=${OS_NAME_SHORT}
systemCheck.hubVersion=${RUNNING_HUB_VERSION}
systemCheck.scriptVersion=${HUB_VERSION}
systemCheck.dockerOrchestrator=${DOCKER_ORCHESTRATOR}
systemCheck.dockerVersion=${DOCKER_VERSION}
systemCheck.nodeCount=${DOCKER_NODE_COUNT}
systemCheck.container.authentication.status=$(get_container_status "blackducksoftware/blackduck-authentication:*")
systemCheck.container.binaryscanner.status=$(get_container_status "sigsynopsys/bdba-worker:*")
systemCheck.container.bomengine.status=$(get_container_status "blackducksoftware/blackduck-bomengine:*")
systemCheck.container.cfssl.status=$(get_container_status "blackducksoftware/blackduck-cfssl:*")
systemCheck.container.documentation.status=$(get_container_status "blackducksoftware/blackduck-documentation:*")
systemCheck.container.jobrunner.status=$(get_container_status "blackducksoftware/blackduck-jobrunner:*")
systemCheck.container.logstash.status=$(get_container_status "blackducksoftware/blackduck-logstash:*")
systemCheck.container.nginx.status=$(get_container_status "blackducksoftware/blackduck-nginx:*")
systemCheck.container.postgres.status=$(get_container_status "blackducksoftware/blackduck-postgres:*")
systemCheck.container.rabbitmq.status=$(get_container_status "blackducksoftware/rabbitmq:*")
systemCheck.container.registration.status=$(get_container_status "blackducksoftware/blackduck-registration:*")
systemCheck.container.scan.status=$(get_container_status "blackducksoftware/blackduck-scan:*")
systemCheck.container.webapp.status=$(get_container_status "blackducksoftware/blackduck-webapp:*")
systemCheck.failures.list=$(echo "$FAILURES" | ([[ -z "$FAILURES" ]] || sed -e 's/^/ - /' -e $'1 s/^/ \\\\\\\n/' -e 's/$/ \\/' -e '$s/ \\$//'))
systemCheck.warnings.list=$(echo "$WARNINGS" | ([[ -z "$WARNINGS" ]] || sed -e 's/^/ - /' -e $'1 s/^/ \\\\\\\n/' -e 's/$/ \\/' -e '$s/ \\$//'))
EOF
}

################################################################
#
# Print usage message
#
################################################################
usage() {
    readonly usage_message=$(cat <<END
Black Duck System Check - Checks system information for compatibility and troubleshooting.

Usage:
    $(basename "$0") <arguments>

Supported Arguments:
    --sizing gen01    Estimate installation size assuming that enhanced 
                      scanning is disabled.
    --sizing gen02    Estimate installation size assuming that enhanced 
                      scanning is enabled.
    --sizing gen03    Estimate installation size in terms of scans per hour (pre-2023.10.1).
    --sizing gen04    Estimate installation size in terms of scans per hour.
    --no-network      Do not use network tests, assume host has no connectivity
                      This can be useful as network tests can take a long time
                      on a system with no connectivity.
    --force           Do not prompt for confirmation or input.
    --help            Print this Help Message
END
)
    echo "$usage_message"
}

################################################################
#
# Check program arguments
#
################################################################
process_args() {
    while [[ $# -gt 0 ]] ; do
        case "$1" in
            '--sizing' )
                shift
                SCAN_SIZING="$1"
                shift
                case "$SCAN_SIZING" in
                    gen01) ;;
                    gen02) ;;
                    gen03) ;;
                    gen04) ;;
                    *)
                        echo "$(basename "$0"): unknown scan sizing value '$SCAN_SIZING'"
                        echo
                        usage
                        exit
                        ;;
                esac
                ;;
            '--no-network' )
                shift
                USE_NETWORK_TESTS="$FALSE"
                echo "*** Skipping Network Tests ***"
                ;;
            '--force' )
                shift
                FORCE="$TRUE"
                ;;
            '--dry-run' )
                shift
                DRY_RUN=1
                ;;
            '--help' )
                usage
                exit
                ;;
            * )
                echo "$(basename "$0"): illegal option ${1}"
                echo ""
                usage
                exit
                ;;
        esac
    done
}

main() {
    [[ $# -le 0 ]] || process_args "$@"
    setup_sizing

    is_root
    is_docker_usable
    get_running_hub_version

    echo "System check version ${HUB_VERSION} for Black Duck version ${RUNNING_HUB_VERSION} at $NOW"
    echo "Writing report to: ${OUTPUT_FILE}"
    echo "Writing properties to: ${PROPERTIES_FILE}"
    echo "Writing summary to: ${SUMMARY_FILE}"
    echo

    get_docker_processes
    get_ulimits
    get_os_name
    check_kernel_version
    get_selinux_status
    get_cpu_info
    check_cpu_count
    get_memory_info
    check_disk_space
    get_processes
    get_package_list
    get_sysctl_keepalive
    get_loginctl_settings

    check_hyperthreading
    check_iosched

    check_entropy
    get_interface_info
    get_routing_info
    get_bridge_info
    get_hosts_file
    get_ports
    get_specific_ports
    check_docker_version
    get_docker_system_info
    get_docker_compose_version
    check_docker_startup_info
    check_docker_os_compatibility
    get_docker_images
    get_docker_containers
    get_installation_size
    check_container_memory
    get_container_health
    get_docker_networks
    get_docker_volumes
    get_docker_nodes
    get_docker_services
    get_docker_stacks
    check_sufficient_ram

    get_firewall_info
    get_iptables

    # Black Duck sites that need to be checked
    check_kb_reachable
    check_sig_repo_reachable
    check_reg_server_reachable

    # External sites that need to be checked
    check_docker_hub_reachable
    check_dockerio_reachable
    check_dockerio_auth_reachable
    check_github_reachable

    # Check if DNS returns a result for webapp
    check_internal_hostnames_dns_status

    get_snippet_invalid_basedir_count
    get_database_bloat_info
    get_scan_info_report
    get_job_info_report

    generate_report "${OUTPUT_FILE}"
    [[ -n "$DRY_RUN" ]] || copy_to_logstash "${OUTPUT_FILE}"

    generate_properties "${PROPERTIES_FILE}"
    [[ -n "$DRY_RUN" ]] || copy_to_config "${PROPERTIES_FILE}"

    generate_summary "${SUMMARY_FILE}"
    [[ -n "$DRY_RUN" ]] || copy_to_logstash "${SUMMARY_FILE}" "latest_system_check_summary.properties"
}

[[ -n "${LOAD_ONLY}" ]] || main ${1+"$@"}
