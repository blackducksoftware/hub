#!/usr/bin/env bash
#
# Copyright (C) 2021 Black Duck Software, Inc.
# http://www.blackduck.com/
# All rights reserved.
#
# This software is the confidential and proprietary information of
# Black Duck ("Confidential Information"). You shall not
# disclose such Confidential Information and shall use it only in
# accordance with the terms of the license agreement you entered into
# with Black Duck.
#
# Gather system and orchestration data to aide in problem diagnosis.
# This command should be run by a user with "kubectl" configured.
#
# Output will be saved to ${SYSTEM_CHECK_OUTPUT_FILE}.
#
# Notes:
#  * Alpine ash has several incompatibilities with bash
#    - FUNCNAME is undefined, so ${FUNCNAME[0]} generates a syntax error.  Use $FUNCNAME instead,
#      even though it triggers spellcheck rule SC2128.
#    - Indirect expansion ("${!key}") generates a syntax error.  Use "$(eval echo \$${key})" instead.
#  * "local foo=$(...)" and variations will mask the command substitution exit status.
#  * Using "curl -f" would require credentials.
#  * The documentation at https://github.com/koalaman/shellcheck includes a list of rules
#    mentioned in the ignore directives. https://www.shellcheck.net/ is the main project website.
set -o noglob
#set -o xtrace

# Set during command line parsing.
NAMESPACE=
NAME=
FILTERS=
FILTER_NS=
FILTER_LABEL=

readonly NOW="$(date +"%Y%m%dT%H%M%S%z")"
readonly NOW_ZULU="$(date -u +"%Y%m%dT%H%M%SZ")"
readonly OUTPUT_FILE="${SYSTEM_CHECK_OUTPUT_FILE:-system_check_${NOW}.txt}"
readonly OUTPUT_FILE_TOC="$(mktemp -t "$(basename "${OUTPUT_FILE}").XXXXXXXXXX")"
trap 'rm -f "${OUTPUT_FILE_TOC}"' EXIT

readonly SCRIPT_VERSION="2021.6.0"

readonly TRUE="TRUE"
readonly FALSE="FALSE"
readonly UNKNOWN="UNKNOWN"  # Yay for tri-valued booleans!  Treated as $FALSE.

readonly PASS="PASS"
readonly WARN="WARNING"
readonly FAIL="FAIL"

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
    exit -1
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
# Find a working kubectl command
#
# Globals:
#   KUBECTL -- (out) control program
# Arguments:
#   None
# Returns:
#   true if Kubernetes is reachable
################################################################
get_kubectl() {
    if [[ -z "${KUBECTL}" ]]; then
        # Let stderr show to the caller
        for probe in kubectl oc ; do
            echo -n "Checking $probe... "
            if ! have_command "$probe"; then
                echo "not found"
            elif "$probe" version >/dev/null; then
                echo "found"
                KUBECTL="$probe"
            fi
        done
        echo
        readonly KUBECTL
    fi

    [[ -n "$KUBECTL" ]]
}

################################################################
# Find a working helm command
#
# Globals:
#   HELM -- (out) helm command
# Arguments:
#   None
# Returns:
#   true if helm command is available
################################################################
get_helm() {
    if [[ -z "${HELM}" ]]; then
        probe=helm
        echo -n "Checking $probe... "
        if ! have_command helm; then
            echo "not found"
        elif "$probe" version >/dev/null; then
            echo "found"
            HELM="$probe"
        fi
        echo
        readonly HELM
    fi

    [[ -n "$HELM" ]]
}

################################################################
# Get the running Black Duck version
#
# Globals:
#   RUNNING_HUB_VERSION -- (out) running Black Duck version.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_running_hub_version() {
    if [[ -z "${RUNNING_HUB_VERSION}" ]]; then
        # Find blackducksoftware image versions, discarding 1.x versions
        local -r result="$($KUBECTL $FILTERS get pods -o template --template '{{range .items}}{{range .spec.containers}}{{.image}}{{"\n"}}{{end}}{{end}}' | grep -aF blackducksoftware | cut -d: -f2 | grep -av '^1\.' | sort | uniq | tr '\n' ' ' | sed -e 's/ *$//')"
        readonly RUNNING_HUB_VERSION="${result:-none}"
    fi
}

################################################################
# Get information about helm charts
#
# Globals:
#   HELM_STATUS -- (out) display the status of the named release
#   HELM_HISTORY -- (out) fetch release history
#   HELM_VALUES -- (out) return the values file for a named release
# Arguments:
#   None
# Returns:
#   None
################################################################
get_helm_info() {
    if [[ -z "${HELM_STATUS}" ]]; then
        if [[ -z "$NAME" ]]; then
            release="$($HELM list -n "$NAMESPACE" | grep -av 'NAME' | awk '{print $1; exit}')"
        else
            release=$NAME
        fi

        if [[ -z "$release" ]]; then
            error_exit "Unable to fetch helm release name"
        fi

        readonly HELM_STATUS="$($HELM status "$release" -n "$NAMESPACE")"
        readonly HELM_HISTORY="$($HELM history "$release" -n "$NAMESPACE")"
        readonly HELM_VALUES="$($HELM get values "$release" -n "$NAMESPACE")"
    fi
}

################################################################
# Get information about the cluster.
#
# Globals:
#   CLUSTER_INFO -- (out) cluster information
# Arguments:
#   None
# Returns:
#   None
################################################################
get_cluster_info() {
    if [[ -z "${CLUSTER_INFO}" ]]; then
        case "$KUBECTL" in
            kubectl* ) readonly CLUSTER_INFO="$($KUBECTL cluster-info | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g')";;
            oc* )      readonly CLUSTER_INFO="$($KUBECTL cluster status)";;
            mini* )    readonly CLUSTER_INFO="$($KUBECTL status)";;
            *)         readonly CLUSTER_INFO="$UNKNOWN ($KUBECTL)";;
        esac
    fi
}

################################################################
# Get pod information
#
# Globals:
#   PODS -- (out) pod information summary
#   POD_STATUS -- (out) pass/fail status message
#   POD_DETAILS -- (out) detailed inspection of each pod
# Arguments:
#   None
# Returns:
#   None
################################################################
get_pods() {
    if [[ -z "${PODS}" ]]; then
        readonly PODS="$($KUBECTL $FILTERS get pods -o wide 2>&1)"

        # shellcheck disable=SC2034 # misc is deliberately unused, and captures the remaining words.
        local -r result=$($KUBECTL $FILTERS get pods 2>/dev/null | tail -n +2 | while read -r id ready status misc ; do
                if [[ "$status" != "Running" ]]; then
                    # shellcheck disable=SC2155 # We don't care about the subcommand exit status.
                    local reason="$($KUBECTL $FILTER_NS get pod "$id" -o template --template '{{range .status.containerStatuses}}{{range .lastState}}{{.reason}} at {{.finishedAt}}{{"\n"}}{{end}}{{end}}')"
                    echo "$FAIL: pod $id is not running. $reason"
                elif [[ "${ready%/*}" == "0" ]]; then
                    echo "$FAIL: pod $id is not deployed."
                elif [[ "${ready#*/}" != "${ready%/*}" ]]; then
                    echo "$WARN: pod $id is not fully deployed."
                fi
        done)
        readonly POD_STATUS="${result:-$PASS: All pods are fully deployed and running.}"

        readonly POD_DETAILS=$(for pod in $($KUBECTL $FILTERS get pods -o jsonpath='{..metadata.name}') ; do
                echo "------------------------------------------"
                echo
                echo "# $KUBECTL -n '$NAMESPACE' describe pod '$pod'"
                $KUBECTL $FILTER_NS describe pod "$pod"
                echo
            done
        )
    fi
}

################################################################
# Get replication controller information
#
# Globals:
#   RCS -- (out) replication controller information summary
#   RC_STATUS -- (out) pass/fail status message
#   RC_DETAILS -- (out) detailed inspection of each rc
# Arguments:
#   None
# Returns:
#   None
################################################################
get_rcs() {
    # Is this ever useful given that we query pods too?
    if [[ -z "${RCS}" ]]; then
        readonly RCS="$($KUBECTL $FILTERS get rc -o wide 2>&1)"

        # shellcheck disable=SC2034 # age is deliberately unused, and captures the remaining words.
        local -r result=$($KUBECTL $FILTERS get rc 2>/dev/null | tail -n +2 | while read -r id desired current ready age ; do
                if [[ "$ready" == "0" ]]; then
                    echo "$FAIL: no replication controller $id pods are ready"
                elif [[ "${ready}" != "${current}" ]]; then
                    echo "$WARN: replication controller $id is not fully deployed."
                elif [[ "${desired}" != "${current}" ]]; then
                    echo "$WARN: replication controller $id is not fully scaled out."
                fi
        done)
        readonly RC_STATUS="${result:-$PASS: All replication controllers are fully deployed and ready.}"

        readonly RC_DETAILS=$(for rc in $($KUBECTL $FILTERS get rc -o jsonpath='{..metadata.name}') ; do
                echo "------------------------------------------"
                echo
                echo "# $KUBECTL -n '$NAMESPACE' describe rc '$rc'"
                $KUBECTL $FILTER_NS describe rc "$rc"
                echo
            done
        )
    fi
}

################################################################
# Get node information
#
# Globals:
#   NODES -- (out) node information summary
#   NODE_STATUS -- (out) pass/fail status message
#   NODE_DETAILS -- (out) detailed inspection of each node
# Arguments:
#   None
# Returns:
#   None
################################################################
# shellcheck disable=SC2016 # '$x' is a script variable and should not be expanded.
get_nodes() {
    if [[ -z "${NODES}" ]]; then
        readonly NODES="$($KUBECTL get nodes -o wide 2>&1)"

        local -r result=$(for node in $($KUBECTL get nodes -o jsonpath='{..metadata.name}') ; do
                  # Check conditions. "Ready" should be true, all others should be false.
                  $KUBECTL get nodes -o template --template '{{range .items}}{{$x:=.metadata.name}}{{range .status.conditions}}{{if and (eq .status "True") (ne .type "Ready")}}{{println "'$WARN':" $x .message}}{{end}}{{end}}{{end}}'
                  $KUBECTL get nodes -o template --template '{{range .items}}{{$x:=.metadata.name}}{{range .status.conditions}}{{if and (eq .status "False") (eq .type "Ready")}}{{println "'$WARN':" $x .message}}{{end}}{{end}}{{end}}'
              done
        )
        readonly NODE_STATUS="${result:-$PASS: No node issues detected.}"

        readonly NODE_DETAILS=$(for node in $($KUBECTL get nodes -o jsonpath='{..metadata.name}') ; do
                echo "------------------------------------------"
                echo
                echo "# $KUBECTL describe node '$node'"
                $KUBECTL describe node "$node"
                echo
            done
        )
    fi
}

################################################################
# Check the event history
#
# Globals:
#   EVENTS -- (out) interesting system-level event summary
#   EVENTS_HUB -- (out) interesting hub event summary
#   EVENT_STATUS -- (out) pass/fail status message
# Arguments:
#   None
# Returns:
#   None
################################################################
get_events() {
    if [[ -z "${EVENTS}" ]]; then
        readonly EVENTS="$($KUBECTL get events -o wide 2>&1 | head -200)"
        readonly EVENTS_HUB="$($KUBECTL $FILTER_NS get events -o wide 2>&1)"

        typeset -a results=
        while IFS='' read -r line; do
            results+=("$line");
        done <<< "$($KUBECTL get events --field-selector 'type!=Normal' -o template --template '{{range .items}}{{println "'$WARN':" .lastTimestamp .message}}{{end}}' | grep -a "^$WARN:")"
        while IFS='' read -r line; do
            results+=("$line");
        done <<< "$($KUBECTL $FILTER_NS get events --field-selector 'type!=Normal' -o template --template '{{range .items}}{{println "'$WARN':" .lastTimestamp .message}}{{end}}' | grep -a "^$WARN:")"
        if [[ ${#results[@]} -gt 0 ]]; then
            readonly EVENT_STATUS=$(printf '%s\n' "${results[@]}")
        else
            readonly EVENT_STATUS="$PASS no abnormal events logged."
        fi
    fi
}

################################################################
# Check the persistent volumes
#
# Globals:
#   PV -- (out) persistent volume summary
#   PVC -- (out) persistent volume claim summary
#   PVC_STATUS -- (out) pass/fail status message
# Arguments:
#   None
# Returns:
#   None
################################################################
get_pvc() {
    if [[ -z "${PVC}" ]]; then
        readonly PV="$($KUBECTL $FILTER_NS get pv -o wide 2>&1)"
        readonly PVC="$($KUBECTL $FILTERS get pvc -o wide 2>&1)"
        
        # shellcheck disable=SC2034 # extra args are unused.
        local -r result=$($KUBECTL $FILTERS get pvc 2>/dev/null | tail -n +2 | while read -r name status volume capacity mode class age ; do
                if [[ "$status" == "Pending" ]]; then
                    echo "$FAIL: pvc claim for $name is pending."
                elif [[ "$status" != "Bound" ]]; then
                    echo "$WARN: pvc claim for $name is not bound."
                fi
        done)
        readonly PVC_STATUS="${result:-$PASS: All persistent volume claims are bound.}"
    fi
}

################################################################
# Get service information
#
# Globals:
#   SERVICES -- (out) service summary
# Arguments:
#   None
# Returns:
#   None
################################################################
get_services() {
    if [[ -z "${SERVICES}" ]]; then
        readonly SERVICES="$($KUBECTL $FILTERS get services -o wide 2>&1)"
    fi
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
# Save a full report to disk.
#
# Globals:
#   OUTPUT_FILE -- (in) default output file path.
#   FAILURES -- (out) list of failures reported.
#   WARNINGS -- (out) list of warnings reported.
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
Kubernetes system check version $SCRIPT_VERSION report for Black Duck ${RUNNING_HUB_VERSION}
  generated at $NOW for $NAMESPACE${NAME:+ ($NAME)} on $(hostname -f)
"
    local -r report=$(cat <<END
$(generate_report_section "Cluster information")

Control command: $KUBECTL
$($KUBECTL version 2>&1 | sed -e 's/^/  /')

Cluster information:

$CLUSTER_INFO

$(generate_report_section "Pods")

Namespace: $NAMESPACE
Name tag: $NAME

$POD_STATUS

$PODS

$(generate_report_section "Pod details")

$POD_DETAILS

$(generate_report_section "Nodes")

$NODE_STATUS

$NODES

$(generate_report_section "Replicaiton controllers")

$RC_STATUS

$RCS

$(generate_report_section "Replication controller details")

$RC_DETAILS

$(generate_report_section "Node details")

$NODE_DETAILS

$(generate_report_section "Events")

$EVENT_STATUS

Black Duck events:
------------------
$EVENTS_HUB

Recent cluster events:
----------------------
$EVENTS

$(generate_report_section "Persistent volumes")

$PVC_STATUS

Persistent volume claims:
$PVC

Persistent volumes:
$PV

$(generate_report_section "Services")

$SERVICES

$(generate_report_section "Helm charts")

$HELM_STATUS

$HELM_HISTORY

$HELM_VALUES

END
)

    # Filter out some false positives when looking for failures/warnings:
    # - The abrt-watch-log command line has args like 'abrt-watch-log -F BUG: WARNING: at WARNING: CPU:'
    readonly FAILURES="$(echo "$report" | grep -aF "$FAIL" | grep -avF abrt-watch-log | grep -avF "${FAIL}_")"
    readonly WARNINGS="$(echo "$report" | grep -aF "$WARN" | grep -avF abrt-watch-log | grep -avF "${WARN}_")"

    { echo "$header"; echo "Table of contents:"; echo; sort -n "${OUTPUT_FILE_TOC}"; echo; } > "${target}"
    cat >> "${target}" <<END
$(generate_report_section "Problems detected" 1)

${FAILURES:-No failures.}

${WARNINGS:-No warnings.}

END
    echo "$report" >> "${target}"
}

################################################################
#
# Print usage message
#
################################################################
usage() {
    readonly usage_message=$(cat <<END
Black Duck Kuberenetes System Check - Checks system information for compatibility and troubleshooting.

Usage:
    $(basename "$0") <options> NAMESPACE [ NAME ] 

Arguments:
    NAMESPACE - the namespace where Black Duck is running.
    NAME - name tag for a particular instance (optional)

Options:
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
            '--help' )
                usage
                exit
                ;;
            * )
                if [[ -z "$NAMESPACE" ]]; then
                    NAMESPACE="$1";
                    # Can we set a default NAME here?
                elif [[ -z "$NAME" ]]; then
                    NAME="$1";
                else
                    echo "$(basename "$0"): illegal option ${1}"
                    echo ""
                    usage
                    exit
                fi
                ;;
        esac
        shift
    done

    if [[ -z "$NAMESPACE" ]]; then
        usage "Missing required NAMESPACE argument."
        exit
    fi
    readonly NAMESPACE
    readonly NAME
    readonly LABEL="app=blackduck${NAME:+,name=$NAME}"
    readonly FILTER_NS="-n $NAMESPACE"
    readonly FILTER_LABEL="-l $LABEL"
    readonly FILTERS="$FILTER_NS $FILTER_LABEL"
}


main() {
    process_args "$@"

    # We require access to a running instance.
    get_kubectl || error_exit "kubernetes is not reachable"
    get_helm || error_exit "helm is not available"

    get_running_hub_version

    echo "Kubernetes system check version ${SCRIPT_VERSION} for Black Duck ${RUNNING_HUB_VERSION} at $NOW"
    echo "Writing report to: ${OUTPUT_FILE}"
    echo

    get_helm_info
    get_cluster_info
    get_pods
    get_rcs
    get_nodes
    get_events
    get_pvc
    get_services

    generate_report "${OUTPUT_FILE}"
}

[[ -n "${LOAD_ONLY}" ]] || main ${1+"$@"}
