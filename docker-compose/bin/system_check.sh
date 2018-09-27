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

readonly HUB_VERSION="${HUB_VERSION:-5.0.0}"
readonly OUTPUT_FILE="${SYSTEM_CHECK_OUTPUT_FILE:-$(date +"system_check_%Y%m%dT%H%M%S%z.txt")}"
readonly OUTPUT_FILE_TOC="$(mktemp -t "$(basename "${OUTPUT_FILE}").XXXXXXXXXX")"
trap 'rm -f "${OUTPUT_FILE_TOC}"' EXIT

# Our RAM requirements are as follows:
# Non-Swarm Install: 16GB
# Swarm Install with many nodes: 16GB per node
# Swarm Install with a single node: 20GB
#
# The script plays some games here because Linux never reports 100% of the physical memory on a system,
# usually reporting 1GB less than the correct amount.
#
readonly REQ_RAM_GB=15
readonly REQ_RAM_GB_SWARM=19
readonly REQ_RAM_TEXT="$((REQ_RAM_GB + 1))GB required"
readonly REQ_RAM_TEXT_SWARM="$((REQ_RAM_GB_SWARM + 1))GB required all containers are on a single swarm node including postgres"

readonly REQ_CPUS=4
readonly REQ_DISK_MB=250000
readonly REQ_DOCKER_VERSIONS="17.09.x 17.12.x 18.03.x 18.06.x"
readonly REQ_ENTROPY=100

readonly REQ_SYSCTL_KEEPALIVE_TIME=600
readonly REQ_SYSCTL_KEEPALIVE_INTERVAL=30
readonly REQ_SYSCTL_KEEPALIVE_PROBES=10

readonly TRUE="TRUE"
readonly FALSE="FALSE"
readonly UNKNOWN="UNKNOWN"  # Yay for tri-valued booleans!  Treated as $FALSE.

readonly PASS="PASS"
readonly WARN="WARNING"
readonly FAIL="FAIL"

# Controls a switch to turn network testing on/off for systems with no internet connectivity
USE_NETWORK_TESTS="TRUE"
readonly NETWORK_TESTS_SKIPPED="*** Network Tests Skipped at command line ***"

# Hostnames the hub uses within the docker network
HUB_RESERVED_HOSTNAMES="postgres authentication webapp scan jobrunner cfssl logstash \
registration zookeeper solr webserver documentation"

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
    # shellcheck disable=SC2128
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
    # shellcheck disable=SC2128
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
# Test whether we are running as root.  Prompt the user to
# abort if we are not.
#
# Globals:
#   IS_ROOT -- (out) TRUE/FALSE
#   CURRENT_USERNAME -- (out) user name.
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
            echo
            read -rp "Are you sure you want to proceed as a non-privileged user? [y/N]: "
            [[ "$REPLY" =~ ^[Yy] ]] || exit -1
            IS_ROOT="$FALSE"
            echo
        fi
        readonly IS_ROOT
        readonly CURRENT_USERNAME="$(id -un)"
    fi

    check_boolean "${IS_ROOT}"
}

################################################################
# Expose the running operating system name.  See also
# http://linuxmafia.com/faq/Admin/release-files.html
#
# Globals:
#   OS_NAME -- (out) operating system name
#   IS_LINUX -- (out) TRUE/FALSE
#   IS_MACOS -- (out) TRUE/FALSE.  macOS is not considered to be Linux.
#   IS_REDHAT -- (out) TRUE/FALSE
#   IS_RHEL -- (out) TRUE/FALSE
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
        IS_REDHAT="$FALSE"
        IS_RHEL="$FALSE"
        if have_command lsb_release ; then
            OS_NAME="$(lsb_release -a ; echo ; echo -n uname -a:\  ; uname -a)"
        elif [[ -e /etc/fedora-release ]]; then
            OS_NAME="$(cat /etc/fedora-release)"
        elif [[ -e /etc/redhat-release ]]; then
            OS_NAME="$(cat /etc/redhat-release)"
            IS_REDHAT="$TRUE"
            # shellcheck disable=SC2155
            local ENTERPRISE="$(cut -d' ' -f 3 < /etc/redhat-release)"
            if [[ "${ENTERPRISE}" == 'Enterprise' ]]; then
                IS_RHEL="$TRUE"                
            fi            
        elif [[ -e /etc/centos-release ]]; then
            OS_NAME="$(cat /etc/centos-release)"
        elif [[ -e /etc/SuSE-release ]]; then
            OS_NAME="$(cat /etc/SuSE-release)"
        elif [[ -e /etc/gentoo-release ]]; then
            OS_NAME="$(cat /etc/gentoo-release)"
        elif [[ -e /etc/os-release ]]; then
            OS_NAME="$(cat /etc/os-release)"
        elif have_command sw_vers ; then
            OS_NAME="$(sw_vers)"
            IS_LINUX="$FALSE"
            IS_MACOS="$TRUE"
        else
            OS_NAME="$(echo -n uname -a:\  ; uname -a)"
            IS_LINUX="$FALSE"
        fi
        readonly OS_NAME
        readonly IS_LINUX
        readonly IS_MACOS
        readonly IS_REDHAT
        readonly IS_RHEL
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
# Determine whether the current operating system is a Red Hat Linux
# variant. 
#
# Globals:
#   IS_REDHAT -- (out) TRUE/FALSE
# Arguments:
#   None
# Returns:
#   true if this is a Red Hat system
################################################################
is_redhat() { 
    [[ -n "${IS_REDHAT}" ]] || get_os_name
    check_boolean "${IS_REDHAT}"
}

################################################################
# Determine whether the current operating system is a Red Hat
# Enterprise Linux variant.
#
# Globals:
#   IS_RHEL -- (out) TRUE/FALSE
# Arguments:
#   None
# Returns:
#   true if this is a Red Hat Enterpise Linux system
################################################################
is_rhel() { 
    [[ -n "${IS_RHEL}" ]] || get_os_name
    check_boolean "${IS_RHEL}"
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
# Verify the kernel version.
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
            local -r have="$(echo ${OS_NAME})"  # Collapse to a single line
            case "$have" in
                # See https://access.redhat.com/articles/3078 and https://en.wikipedia.org/wiki/CentOS
                *Red\ Hat\ Enterprise\ *\ 7.6* | *CentOS\ *\ 7.6.*)     expect="";; # Future-proofing
                *Red\ Hat\ Enterprise\ *\ 7.5* | *CentOS\ *\ 7.5.1804*) expect="3.10.0-862";;
                *Red\ Hat\ Enterprise\ *\ 7.4* | *CentOS\ *\ 7.4.1708*) expect="3.10.0-693";;
                *Red\ Hat\ Enterprise\ *\ 7.3* | *CentOS\ *\ 7.3.1611*) expect="3.10.0-514";;
                *Red\ Hat\ Enterprise\ *\ 7.2* | *CentOS\ *\ 7.2.1511*) expect="3.10.0-327";;
                *Red\ Hat\ Enterprise\ *\ 7.1* | *CentOS\ *\ 7.1.1503*) expect="3.10.0-229";;
                *Red\ Hat\ Enterprise\ *\ 7*   | *CentOS\ *\ 7.0.1406*) expect="3.10.0-123";;
                # See https://www.suse.com/support/kb/doc/?id=3594951 and
                # https://wiki.microfocus.com/index.php/SUSE/SLES/Kernel_versions
                *SUSE\ Linux\ Enterprise\ Server\ 15\ SP*)  expect="";; # Future-proofing
                *SUSE\ Linux\ Enterprise\ Server\ 15*)      expect="4.12.(14-23|14-25)";;
                *SUSE\ Linux\ Enterprise\ Server\ 12\ SP4*) expect="";; # Future-proofing
                *SUSE\ Linux\ Enterprise\ Server\ 12\ SP3*)
                    expect="4.4.(73-5|82-6|92-6|103-6|114-94|120-94|126-94|131-94|132-94|138-94|140-94|143-94)";;
                *SUSE\ Linux\ Enterprise\ Server\ 12\ SP2*)
                    expect="4.4.(21-69|21-81|21-84|21-90|38-93|49-92|59-92|74-92|90-92|103-92|114-92|120-92|121-92)";;
                *SUSE\ Linux\ Enterprise\ Server\ 12\ SP1*)
                    expect="3.12.(49-11|51-60|53-60|57-60|59-60|62-60|67-60|69-60|74-60)";;
                *SUSE\ Linux\ Enterprise\ Server\ 12*)
                    expect="3.12.(28-4|32-33|36-38|38-44|39-47|43-5344-53|48-53|51-52|52-57|55-52|60-52|61-52)";;
                # See https://en.wikipedia.org/wiki/Darwin_(operating_system)
                *Mac\ OS\ X*10.13.7*)                        expect="";; # Future-proofing
                *Mac\ OS\ X*10.13.6*)                        expect="17.7.0";;
                *Mac\ OS\ X*10.13.5* | *Mac\ OS\ X*10.13.4*) expect="17.5.0";;
                *Mac\ OS\ X*10.13*)                          expect="17.0.0";;
                # We don't know...
                *) expect="";;
            esac
            if [[ -z "$expect" ]]; then
                readonly KERNEL_VERSION_STATUS="$WARN: Don't know what kernel version to expect for ${have}"
            elif echo "$kernel_version" | grep -qE "$expect" ; then
                readonly KERNEL_VERSION_STATUS="$PASS: Kernel version ${kernel_version}"
            else
                readonly KERNEL_VERSION_STATUS="$FAIL: Kernel version ${kernel_version} is unexpected"
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
            readonly CPU_INFO="$(system_profiler SPHardwareDataType | grep -E "Processor|Cores")"
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
#   CPU_COUNT_STATUS -- (out) PASS/FAIL status message
#   REQ_CPUS -- (in) required minimum CPU count
# Arguments:
#   None
# Returns:
#   true if minimum requirements are known to be met.
################################################################
# shellcheck disable=SC2155,SC2046
check_cpu_count() {
    if [[ -z "$CPU_COUNT_STATUS" ]]; then
        echo "Checking CPU count..."
        local -r CPUINFO_FILE="/proc/cpuinfo"
        if have_command lscpu ; then
            local cpu_count="$(lscpu -p=cpu | grep -v -c '#')"
            local status=$(echo_passfail $([[ "${cpu_count}" -ge "${REQ_CPUS}" ]]; echo "$?"))
            readonly CPU_COUNT_STATUS="CPU count $status.  ${cpu_count} found, ${REQ_CPUS} required."
        elif [[ -r "${CPUINFO_FILE}" ]]; then
            local cpu_count="$(grep -c '^processor' "${CPUINFO_FILE}")"
            local status=$(echo_passfail $([[ "${cpu_count}" -ge "${REQ_CPUS}" ]]; echo "$?"))
            readonly CPU_COUNT_STATUS="CPU count $status.  ${cpu_count} found, ${REQ_CPUS} required."
        elif have_command sysctl && is_macos ; then
            local cpu_count="$(sysctl -n hw.ncpu)"
            local status=$(echo_passfail $([[ "${cpu_count}" -ge "${REQ_CPUS}" ]]; echo "$?"))
            readonly CPU_COUNT_STATUS="CPU count $status.  ${cpu_count} found, ${REQ_CPUS} required."
        else
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
#   SUFFICIENT_RAM_STATUS -- (out) PASS/FAIL text status message
#   REQ_RAM_GB -- (in) int required memory in GB
#   REQ_RAM_GB_SWARM -- (in) int swarm required memory in GB
#   REQ_RAM_TEXT -- (in) text required memory message
#   REQ_RAM_TEXT_SWARM -- (in) text swarm required memory message
# Arguments:
#   None
# Returns:
#   true if minimum requirements are known to have been met.
################################################################
# shellcheck disable=SC2155,SC2046
check_sufficient_ram() {
    if [[ -z "${SUFFICIENT_RAM_STATUS}" ]]; then
        echo "Checking whether sufficient RAM is present..."

        local ram_requirement="$REQ_RAM_GB"
        local ram_description="$REQ_RAM_TEXT"
        if is_swarm_enabled && is_postgresql_container_running ; then 
            ram_requirement="$REQ_RAM_GB_SWARM"
            ram_description="$REQ_RAM_TEXT_SWARM"
        fi

        if have_command free ; then
            local -r total_ram_in_gb="$(free -g | grep 'Mem' | awk -F' ' '{print $2}')"
            local status="$(echo_passfail $([[ "${total_ram_in_gb}" -ge "${ram_requirement}" ]]; echo "$?"))"
            readonly SUFFICIENT_RAM_STATUS="Total RAM: $status. ${ram_description}."
        elif have_command sysctl && is_macos ; then
            local -r total_ram_in_gb="$(( $(sysctl -n hw.memsize) / 1073741824 ))"
            local status="$(echo_passfail $([[ "${total_ram_in_gb}" -ge "${ram_requirement}" ]]; echo "$?"))"
            readonly SUFFICIENT_RAM_STATUS="Total RAM: $status. ${ram_description}."
        else
            readonly SUFFICIENT_RAM_STATUS="Total RAM is $UNKNOWN. ${ram_description}"
        fi
    fi

    check_passfail "${SUFFICIENT_RAM_STATUS}"
}

################################################################
# Expose disk space summary.
#
# Globals:
#   DISK_SPACE -- (out) text disk summary
#   DISK_SPACE_STATUS -- (out) PASS/FAIL status message.
#   REQ_DISK_MB -- (in) int required disk space in megabytes
# Arguments:
#   None
# Returns:
#   true if disk space is known and meets minimum requirements
################################################################
# shellcheck disable=SC2155,SC2046
check_disk_space() {
    if [[ -z "${DISK_SPACE}" ]]; then
        echo "Checking disk space..."
        if have_command df ; then
            readonly DISK_SPACE="$(df -h)"
            local -r total="$(df -m --total | grep 'total' | awk -F' ' '{print $2}')"
            local status="$(echo_passfail $([[ "${total}" -ge "${REQ_DISK_MB}" ]]; echo "$?"))"
            readonly DISK_SPACE_STATUS="Disk space check $status. Found ${total}mb, require ${REQ_DISK_MB}mb."
        else
            readonly DISK_SPACE="Disk space is $UNKNOWN -- df not found."
            readonly DISK_SPACE_STATUS="Disk space check is $UNKNOWN -- df not found."
        fi
    fi

    check_passfail "${DISK_SPACE_STATUS}"
}

################################################################
# Get a list of installed packages.
#
# Globals:
#   PACKAGE_LIST -- (out) text package information or an error message.
# Arguments:
#   None
# Returns:
#   None
################################################################
# shellcheck disable=SC2155
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
            readonly PACKAGE_LIST="$(dpkg --get-selections | grep -v deinstall)"
        elif have_command apk ; then
            readonly PACKAGE_LIST="$(apk info -v | sort)"
        else
            readonly PACKAGE_LIST="Package list is $UNKNOWN -- could not determine package manager"
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
            readonly LISTEN_PORTS="$(netstat -ln)"
        else
            readonly LISTEN_PORTS="Network ports are $UNKNOWN -- netstat not found."
        fi
    fi
}

################################################################
# Probe iptables for specific ports that are important to Hub.
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
echo_port_status() {
    # shellcheck disable=SC2128
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

    local -r non_nat_rule_results="$(iptables --list -n | grep "$port")"
    local -r non_nat_result_found="$(echo_boolean "$([[ -n "${non_nat_rule_results}" ]]; echo "$?")")"

    local -r nat_rule_results="$(iptables -t nat --list -n | grep "$port")"
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
# Check critical IPV4 syctl values on linux
#
# Globals:
# SYSCTL_KEEPALIVE_TIME -- (out) - The current keepalive time
# SYSCTL_KEEPALIVE_INTERVAL -- (out) - The current keepalive interval
# SYSCTL_KEEPALIVE_PROBES -- (out) - The current # of keepalive probes
# SYSCTL_KEEPALIVE_TIME_MEETS_RECOMMENDATIONS -- (out) TRUE/FALSE
# SYSCTL_KEEPALIVE_INTERVAL_MEETS_RECOMMENDATIONS -- (out) TRUE/FALSE
# SYSCTL_KEEPALIVE_PROBES_MEETS_RECOMMENDATIONS -- (out) TRUE/FALSE
#  
#
################################################################
get_sysctl_keepalive() { 

    if [[ -z "${SYSCTL_KEEPALIVE_TIME_MEETS_RECOMMENDATIONS}" ]] ; then 

        if ! is_linux ; then
            readonly SYSCTL_KEEPALIVE_TIME="Can't check sysctl keepalive on non-linux system."
            readonly SYSCTL_KEEPALIVE_INTERVAL="Can't check sysctl keepalive on non-linux system."
            readonly SYSCTL_KEEPALIVE_PROBES="Can't check sysctl keepalive on non-linux system."
            readonly SYSCTL_KEEPALIVE_TIME_MEETS_RECOMMENDATIONS="UNKNOWN"
            readonly SYSCTL_KEEPALIVE_INTERVAL_MEETS_RECOMMENDATIONS="UNKNOWN"
            readonly SYSCTL_KEEPALIVE_PROBES_MEETS_RECOMMENDATIONS="UNKNOWN"
            return -1
        fi

        if ! have_command sysctl ; then
            readonly SYSCTL_KEEPALIVE_TIME="Can't check sysctl keepalive, sysctl not found."
            readonly SYSCTL_KEEPALIVE_INTERVAL="Can't check sysctl keepalive on non-linux system."
            readonly SYSCTL_KEEPALIVE_PROBES="Can't check sysctl keepalive on non-linux system."
            readonly SYSCTL_KEEPALIVE_TIME_MEETS_RECOMMENDATIONS="UNKNOWN"
            readonly SYSCTL_KEEPALIVE_INTERVAL_MEETS_RECOMMENDATIONS="UNKNOWN"
            readonly SYSCTL_KEEPALIVE_PROBES_MEETS_RECOMMENDATIONS="UNKNOWN"
            return -1
        fi

        echo "Checking sysctl keepalive parameters..."
        readonly SYSCTL_KEEPALIVE_TIME=$(sysctl net.ipv4.tcp_keepalive_time | awk -F' = ' '{print $2}')
        readonly SYSCTL_KEEPALIVE_INTERVAL=$(sysctl net.ipv4.tcp_keepalive_intvl | awk -F' = ' '{print $2}')
        readonly SYSCTL_KEEPALIVE_PROBES=$(sysctl net.ipv4.tcp_keepalive_probes | awk -F' = ' '{print $2}')

        SYSCTL_KEEPALIVE_TIME_MEETS_RECOMMENDATIONS="TRUE"
        SYSCTL_KEEPALIVE_INTERVAL_MEETS_RECOMMENDATIONS="TRUE"
        SYSCTL_KEEPALIVE_PROBES_MEETS_RECOMMENDATIONS="TRUE"

        if [[ "${SYSCTL_KEEPALIVE_TIME}" -lt "${REQ_SYSCTL_KEEPALIVE_TIME}" ]] ; then 
            SYSCTL_KEEPALIVE_TIME_MEETS_RECOMMENDATIONS="FALSE"
        fi

        if [[ "${SYSCTL_KEEPALIVE_INTERVAL}" -lt "${REQ_SYSCTL_KEEPALIVE_INTERVAL}" ]] ; then 
            SYSCTL_KEEPALIVE_INTERVAL_MEETS_RECOMMENDATIONS="FALSE"
        fi

        if [[ "${SYSCTL_KEEPALIVE_PROBES}" -lt "${REQ_SYSCTL_KEEPALIVE_PROBES}" ]] ; then 
            SYSCTL_KEEPALIVE_PROBES_MEETS_RECOMMENDATIONS="FALSE"
        fi

        readonly SYSCTL_KEEPALIVE_TIME_MEETS_RECOMMENDATIONS
        readonly SYSCTL_KEEPALIVE_INTERVAL_MEETS_RECOMMENDATIONS
        readonly SYSCTL_KEEPALIVE_PROBES_MEETS_RECOMMENDATIONS

    fi



}


################################################################
# Get a list of running processes.
#
# Globals:
#   RUNNING_PROCESSES -- (out) text process list, or an error message.
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
# Check whether a supported version of docker is installed
#
# Globals:
#   DOCKER_VERSION -- (out) docker version.
#   DOCKER_EDITION -- (out) ee/ce for enterprise/consumer
#   DOCKER_VERSION_CHECK -- (out) PASS/FAIL docker version is supported.
#   REQ_DOCKER_VERSIONS -- (in) supported docker versions.
# Arguments:
#   None
# Returns:
#   true if a supported version of docker is installed.
################################################################
# shellcheck disable=SC2155
check_docker_version() {
    if [[ -z "${DOCKER_VERSION_CHECK}" ]]; then
        if ! is_docker_present ; then
            readonly DOCKER_VERSION_CHECK="No docker version -- docker is not installed."
            return 1
        fi

        # Read the docker version strings and parse them
        # The string will look something like this:
        # "Docker version 18.03.1-ce, build 9ee9f40"
        # 3rd field based on cutting by " " is the version string
        # 2nd field based on cutting by "-" is the edition with a comma on the end
        # 1st field based on cutting with "," will be the edition without the comma
        # edition is "ee" for Enterprise and "ce" for community
        echo "Checking docker version..."
        readonly DOCKER_VERSION="$(docker --version)"
        readonly DOCKER_EDITION="$(docker --version | cut -d' ' -f3 | cut -d- -f2 | cut -d, -f1)"
        local docker_base_version="$(docker --version | cut -d' ' -f3 | cut -d. -f1-2)"


        if [[ ! "${REQ_DOCKER_VERSIONS}" =~ ${docker_base_version}.x ]]; then
            readonly DOCKER_VERSION_CHECK="$FAIL. Running ${DOCKER_VERSION}, supported versions are: ${REQ_DOCKER_VERSIONS}"
        else
            readonly DOCKER_VERSION_CHECK="$PASS. ${DOCKER_VERSION} installed."
        fi

    fi

    check_passfail "${DOCKER_VERSION_CHECK}"
}


################################################################
# Check whether a supported version of docker is installed
#
# Globals:
#   DOCKER_VERSION -- (out) docker version.
#   DOCKER_EDITION -- (out) ee/ce for enterprise/consumer
#   DOCKER_VERSION_CHECK -- (out) PASS/FAIL docker version is supported.
#   REQ_DOCKER_VERSIONS -- (in) supported docker versions.
# Arguments:
#   None
# Returns:
#   true if a supported version of docker is installed.
################################################################
is_docker_ee() { 
    if [[ -z "${IS_DOCKER_EE}" ]] ; then 
        if [[ -z "${DOCKER_EDITION}" ]]; then 
            check_docker_version
        fi

        IS_DOCKER_EE="$FALSE"
        if [[ "${DOCKER_EDITION}" == "ee" ]]; then
            IS_DOCKER_EE="$TRUE"
        fi

        readonly IS_DOCKER_EE
    fi

    check_boolean "${IS_DOCKER_EE}"
}

################################################################
# Check whether the version of docker installed is supported for the OS 
# version that was detected
#
# Globals:
#   DOCKER_OS_COMPAT -- Information on OS/Docker compatibility
#   DOCKER_OS_COMPAT_CHECK -- (out) PASS/FAIL docker version is supported on the OS
# Arguments:
#   None
# Returns:
#   true if a supported version of docker is installed.
################################################################
check_docker_os_compatibility() { 
    if [[ -z "${DOCKER_OS_COMPAT}" ]] ; then 

        if [[ -z "${DOCKER_VERSION_CHECK}" ]]; then 
            check_docker_version
        fi

        if [[ -z "${OS_NAME}" ]]; then 
            get_os_name
        fi

        DOCKER_OS_COMPAT_CHECK="$PASS"
        DOCKER_OS_COMPAT="No Compatibility problems between OS and Docker"

        if is_rhel && is_docker_ee ; then
            DOCKER_OS_COMPAT_CHECK="$FAIL"
            DOCKER_OS_COMPAT="Docker EE on Red Hat Enterprise Linux is not supported."
        fi

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
        if is_docker_compose_present ; then
            echo "Checking docker-compose version..."
            readonly DOCKER_COMPOSE_VERSION="$(docker-compose --version)"
        else
            readonly DOCKER_COMPOSE_VERSION="docker-compose not found."
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
            systemctl list-unit-files 'docker*' | grep -q enabled >/dev/null 2>&1
            status="$(echo_passfail "$?")"
        elif have_command rc-update ; then
            rc-update show -v -a | grep docker | grep -q boot >/dev/null 2>&1
            status="$(echo_passfail "$?")"
        elif have_command chkconfig ; then
            chkconfig --list docker | grep -q "2:on" >/dev/null 2>&1
            status="$(echo_passfail "$?")"
        fi

        if [[ -z "$status" ]]; then
            readonly DOCKER_STARTUP_INFO="Docker startup status is $UNKNOWN."
        elif check_passfail "$status" ; then
            readonly DOCKER_STARTUP_INFO="Docker startup check $PASS. Enabled at startup."
        else
            readonly DOCKER_STARTUP_INFO="Docker startup check $FAIL. Disabled at startup."
        fi
    fi

    check_passfail "${DOCKER_STARTUP_INFO}"
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
        elif ! is_root ; then
            readonly DOCKER_IMAGES="Docker images are $UNKNOWN -- requires root access."
            readonly DOCKER_IMAGE_INSPECTION="Docker image details are $UNKNOWN -- requires root access."
            return
        fi

        echo "Checking docker images..."
        readonly DOCKER_IMAGES=$(
            while read -r repo tag ; do
                printf "%-40s %s\\n" "$repo" "$tag"
            done <<< "$(docker images --format "{{.Repository}} {{.Tag}}" | sort)"
        )
        readonly DOCKER_IMAGE_INSPECTION="$(docker image ls -aq | xargs docker image inspect)"
    fi
}

################################################################
# Get detailed information about all docker containers.
#
# Globals:
#   DOCKER_CONTAINERS -- (out) list of docker constanters
#   DOCKER_CONTAINER_INSPECTION -- (out) container inspection and diff.
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
            return
        elif ! is_root ; then
            readonly DOCKER_CONTAINERS="Docker containers are $UNKNOWN -- requires root access"
            readonly DOCKER_CONTAINER_INSPECTION="Docker container details are $UNKNOWN -- requires root access."
            return
        fi

        echo "Checking Docker Containers and Taking Diffs..."
        readonly DOCKER_CONTAINERS="$(docker container ls)"
        # shellcheck disable=SC2155
        local container_ids="$(docker container ls -aq)"
        readonly DOCKER_CONTAINER_INSPECTION=$(
            while read -r cur_container_id ; do
                echo "------------------------------------------"
                docker container ls -a --filter "id=${cur_container_id}" --format "{{.ID}} {{.Image}}"
                docker inspect "${cur_container_id}"
                docker container diff "${cur_container_id}"
            done <<< "${container_ids}"
        )
    fi
}

################################################################
# Get a list of docker processes
#
# Globals:
#   DOCKER_PROCESSES -- (out) text list of processes.
# Arguments:
#   None
# Returns:
#   None
################################################################
get_docker_processes() {
    if [[ -z "${DOCKER_PROCESSES}" ]]; then
        if ! is_docker_present ; then
            readonly DOCKER_PROCESSES="No docker processes -- docker not installed."
            return
        elif ! is_root ; then
            readonly DOCKER_PROCESSES="Docker processes are $UNKNOWN -- requires root access"
            return
        fi

        echo "Checking Current Docker Processes..."
        local -r all="$(docker ps)"
        local -r others="$(docker ps --format '{{.Image}}' | grep -F -v blackducksoftware)"
        if [[ -n "$others" ]]; then
            # shellcheck disable=SC2116,SC2086
            # Use embedded 'echo' to squash newlines.
            readonly DOCKER_PROCESSES="$WARN: foreign docker processes found: $(echo $others)

$all"
        else
            readonly DOCKER_PROCESSES="$all"
        fi
    fi
}

################################################################
# Check whether the Black Duck PostgreSQL container is running
#
# Globals:
#   IS_POSTGRESQL_CONTAINER_RUNNING -- (out) TRUE/FALSE result
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
           docker ps | grep blackducksoftware | grep -q postgres
           readonly IS_POSTGRESQL_CONTAINER_RUNNING="$(echo_boolean $?)"
       fi
    fi

    check_boolean "${IS_POSTGRESQL_CONTAINER_RUNNING}"
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
        elif ! is_root ; then
            readonly DOCKER_NETWORKS="Docker networks are $UNKNOWN -- requires root access"
            readonly DOCKER_NETWORK_INSPECTION="Docker network details are $UNKNOWN -- requires root access."
            return
        fi

        echo "Checking docker networks..."
        readonly DOCKER_NETWORKS="$(docker network ls)"
        readonly DOCKER_NETWORK_INSPECTION="$(docker network ls -q | xargs docker network inspect)"
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
        elif ! is_root ; then
            readonly DOCKER_VOLUMES="Docker volumes are $UNKNOWN -- requires root access"
            readonly DOCKER_VOLUME_INSPECTION="Docker volume details are $UNKNOWN -- requires root access."
            return
        fi

        echo "Checking docker volumes..."
        readonly DOCKER_VOLUMES="$(docker volume ls)"
        readonly DOCKER_VOLUME_INSPECTION="$(docker volume ls -q | xargs docker volume inspect)"
    fi
}

################################################################
# Check whether docker swarm mode is enabled.
#
# Globals:
#   IS_SWARM_ENABLED -- (out) TRUE/FALSE/UNKNOWN status
# Arguments:
#   None
# Returns:
#   true is swarm mode is known to be active
################################################################
is_swarm_enabled() {
    if [[ -z "${IS_SWARM_ENABLED}" ]]; then
        if ! is_docker_present ; then
            readonly IS_SWARM_ENABLED="$FALSE"
        elif ! is_root ; then
            readonly IS_SWARM_ENABLED="$UNKNOWN"
        else
            echo "Checking docker swarm mode..."
            docker node ls > /dev/null 2>&1
            readonly IS_SWARM_ENABLED="$(echo_boolean $?)"
        fi
    fi

    check_boolean "${IS_SWARM_ENABLED}"
}

################################################################
# Gather detailed information about docker swarm nodes.
#
# Globals:
#   DOCKER_NODES -- (out) text node list
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
            readonly DOCKER_NODE_INSPECTION="No docker swarm node details -- docker is not installed."
            return
        elif ! is_root ; then
            readonly DOCKER_NODES="Docker swarm nodes are $UNKNOWN -- requires root access"
            readonly DOCKER_NODE_INSPECTION="Docker swarm node details are $UNKNOWN -- requires root access"
            return
        fi

        echo "Checking docker swarms..."
        if ! docker node ls > /dev/null 2>&1 ; then
            readonly DOCKER_NODES="Machine is not part of a docker swarm or is not the manager"
            readonly DOCKER_NODE_INSPECTION="Machine is not part of a docker swarm or is not the manager"
            return
        fi

        readonly DOCKER_NODES="$(docker node ls)"
        readonly DOCKER_NODE_INSPECTION="$(docker node ls -q | xargs docker node inspect)"
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
            if ! systemctl -q is-enabled firewall.service ; then
                readonly FIREWALL_ENABLED="$FALSE"
                return
            fi

            readonly FIREWALL_ENABLED="$TRUE"
            readonly FIREWALL_INFO="Firewalld active zones: $(firewall-cmd --get-active-zones)
Firewalld all zones: $(firewall-cmd --list-all-zones)
Firewalld services: $(firewall-cmd --get-services)"
        elif have_command SuSEfirewall2 ; then
            readonly FIREWALL_CMD="SuSEfirewall2"
            if ! /sbin/rcSuSEfirewall2 status | grep -q running ; then
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

        echo "Checking IP Tables Rules..."
        readonly IPTABLES_ALL_RULES="$(iptables --list -v)"
        readonly IPTABLES_DB_RULES="$(iptables --list | grep '55436')"
        readonly IPTABLES_HTTPS_RULES="$(iptables --list | grep https)"
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
            echo "Checking Entropy..."
            local -r entropy="$(cat "${ENTROPY_FILE}")"
            # shellcheck disable=SC2046
            local -r status="$(echo_passfail $([[ "${entropy:-0}" -gt "${REQ_ENTROPY}" ]]; echo "$?"))"
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
# Helper method to ping a host.   A small (64 byte) and large
# (1500 byte) ping attempt will be made.
#
# Globals:
#   $2_REACHABLE_SMALL -- (out) PASS/FAIL/UNKNOWN
#   $2_REACHABLE_LARGE -- (out) PASS/FAIL/UNKNOWN
#   $2_PING_SMALL_DATA -- (out) ping data
#   $2_PING_LARGE_DATA -- (out) ping data
# Arguments:
#   $1 - Hostname to ping
#   $2 - Key to prefix result variables
#   $3 - Label (pretty host name) to use in messages
# Returns:
#   None
################################################################
ping_host() {
    # shellcheck disable=SC2128
    [[ "$#" -eq 3 ]] || error_exit "usage: $FUNCNAME <hostname> <key> <label>"
    local -r hostname="$1"
    local -r key="$2"
    local -r label="$3"

    local -r small_result_key="${key}_REACHABLE_SMALL"
    local -r small_data_key="${key}_PING_SMALL_DATA"
    local -r large_result_key="${key}_REACHABLE_LARGE"
    local -r large_data_key="${key}_PING_LARGE_DATA"

    if [[ -z "$(eval echo \$"${small_result_key}")" ]]; then
        if ! have_command ping ; then
            local -r ping_missing_message="$label connectivity is $UNKNOWN -- ping not found"
            eval "readonly ${small_result_key}=\"${ping_missing_message}\""
            eval "readonly ${large_result_key}=\"${ping_missing_message}\""
            eval "readonly ${small_data_key}=\"${ping_missing_message}\""
            eval "readonly ${large_data_key}=\"${ping_missing_message}\""
            return
        fi

        # Check small and large packets separately
        echo "Checking ping from docker host to ${label} with small packets... (this takes time)"
        local -r PING_SMALL_PACKET_SIZE=56
        local small_result; small_result="$(ping -c 3 -s ${PING_SMALL_PACKET_SIZE} "$hostname")"
        eval "readonly ${small_result_key}=\"ping $label (small packets) Exit code: "$?" - $(echo_passfail "$?")\""
        eval "readonly ${small_data_key}=\"${small_result}\""

        echo "Checking ping from docker host to ${label} with large packets... (this takes time)"
        local -r PING_LARGE_PACKET_SIZE=1492
        local large_result; large_result="$(ping -c 3 -s ${PING_LARGE_PACKET_SIZE} "$hostname")"
        eval "readonly ${large_result_key}=\"ping $label (large packets) Exit code: "$?" - $(echo_passfail "$?")\""
        eval "readonly ${large_data_key}=\"${large_result}\""
    fi
}

################################################################
# Helper method to ping a host from a docker container.  A
# small (64 byte) and large (1500 byte) ping attempt will be made.
# Status and ping output is echoed to stdout.
# 
# Globals:
#   None
# Arguments:
#   $1 - Container ID where the ping should originate
#   $2 - Container name
#   $3 - Hostname to ping
# Returns:
#   None
################################################################
echo_docker_ping_host() {
    # shellcheck disable=SC2128
    [[ "$#" -eq 3 ]] || error_exit "usage: $FUNCNAME <container_id> <container_name> <hostname>"
    local -r container_id="$1"
    local -r container_name="$2"
    local -r hostname="$3"

    # Check small and large packets separately
    echo ""
    local -r PING_SMALL_PACKET_SIZE=56
    docker exec -u root:root -i "${container_id}" ping -c 3 -s "${PING_SMALL_PACKET_SIZE}" "$hostname"
    echo -e "\\nping $hostname (small packets) from ${container_name}: Exit code: "$?" - $(echo_passfail "$?")"

    echo ""
    local -r PING_LARGE_PACKET_SIZE=1492
    docker exec -u root:root -i "${container_id}" ping -c 3 -s "${PING_LARGE_PACKET_SIZE}" "$hostname"
    echo -e "\\nping $hostname (large packets) from ${container_name}: Exit code: "$?" - $(echo_passfail "$?")"
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
    # shellcheck disable=SC2128
    [[ "$#" -eq 3 ]] || error_exit "usage: $FUNCNAME <container_id> <container_name> <url>"
    local -r container="$1"
    local -r name="$2"
    local -r url="$3"

    docker exec -u root:root -it "$container" curl -s -o /dev/null "$url" >/dev/null 2>&1
    echo "access $url from ${name}: $(echo_passfail "$?")"
}

################################################################
# Probe a URL from within each Black Duck docker container.
#
# Globals:
#   $2_CONTAINER_WEB_REPORT -- (out) text data.
# Arguments:
#   $1 - URL to probe.
#   $2 - key to prefix the result variable
# Returns:
#   None
################################################################
get_container_web_report() {
    # shellcheck disable=SC2128
    [[ "$#" -eq 2 ]] || error_exit "usage: $FUNCNAME <url> <key>"
    local -r url="$1"
    local -r key="$2"

    local -r final_var_name="${key}_CONTAINER_WEB_REPORT"
    if [[ -z "$(eval echo \$"${final_var_name}")" ]]; then
        if ! is_docker_present ; then
            echo "Skipping web report via docker containers -- docker is not installed."
            eval "readonly ${final_var_name}=\"Cannot access web via docker containers -- docker is not installed.\""
            return
        elif ! is_root ; then
            echo "Skipping web report via docker containers -- requires root access."
            eval "readonly ${final_var_name}=\"Web access from containers is $UNKNOWN -- requires root access.\""
            return
        fi

        echo "Checking web access from running Black Duck docker containers to ${url} ... "
        # shellcheck disable=SC2155
        local container_ids="$(docker container ls | grep -F blackducksoftware | grep -F -v zookeeper | cut -d' ' -f1)"
        # shellcheck disable=SC2155
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
# Ping a host from each of the Black Duck docker containers
#
# Globals:
#   $2_CONTAINER_PING_REPORT -- (out) text ping data
# Arguments:
#   $1 - hostname to ping
#   $2 - key to prefix output variable
# Returns:
#   None
################################################################
ping_via_all_containers() {
    # shellcheck disable=SC2128
    [[ "$#" -eq 2 ]] || error_exit "usage: $FUNCNAME <hostname> <key>"
    local -r hostname="$1"
    local -r key="$2"

    local final_var_name="${key}_CONTAINER_PING_REPORT"
    if [[ -z "$(eval echo \$"${final_var_name}")" ]]; then
        if ! is_docker_present ; then
            echo "Skipping ping via docker containers, docker is not installed."
            eval "readonly ${final_var_name}=\"Cannot ping via docker containers, docker is not installed.\""
            return
        elif ! is_root ; then
            echo "Skipping ping via docker containers -- requires root access"
            eval "readonly ${final_var_name}=\"ping from docker containers is $UNKNOWN -- requires root access\""
            return
        fi

        echo "Checking ping connectivity from running docker containers to ${hostname} ..."
        # shellcheck disable=SC2155
        local container_ids="$(docker container ls | grep -F blackducksoftware | grep -F -v zookeeper | cut -d' ' -f1)"
        # shellcheck disable=SC2155
        local container_ping_report=$(
            for cur_id in ${container_ids}; do
                echo "------------------------------------------"
                docker container ls -a --filter "id=${cur_id}" --format "{{.ID}} {{.Image}}"
                cur_image="$(docker container ls -a --filter "id=${cur_id}" --format "{{.Image}}")"
                echo "Ping results: "
                echo_docker_ping_host "${cur_id}" "${cur_image}" "$hostname"
            done
        )

        eval "readonly ${final_var_name}=\"$container_ping_report\""
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
    # shellcheck disable=SC2128
    [[ "$#" -eq 3 ]] || error_exit "usage: $FUNCNAME <url> <key> <label>"
    local -r url="$1"
    local -r key="$2"
    local -r label="$3"

    local -r reachable_key="${key}_URL_REACHABLE"
    if [[ -z "$(eval echo \$"${reachable_key}")" ]]; then
        if have_command curl ; then
            echo "Checking curl access from docker host to ${label} ... (this takes time)"
            curl -s -o /dev/null "$url"
            eval "readonly ${reachable_key}=\"access ${label}: $(echo_passfail "$?")\""
        elif have_command wget ; then
            echo "Checking wget access from docker host to ${label} ... (this takes time)"
            wget -q -O /dev/null "$url" 
            eval "readonly ${reachable_key}=\"access ${label}: $(echo_passfail "$?")\""
        else
            eval "readonly ${reachable_key}=\"Cannot attempt web request to $label\""
        fi
    fi

    check_passfail "$(eval echo \$"${reachable_key}")"
}

################################################################
# Trace packet routing to a host.
#
# Globals:
#   $2_TRACEPATH_RESULT -- (out) route to $1
#   $2_TRACEPATH_REACHABLE -- (out) PASS/FAIL reachability status
# Arguments:
#   $1 - host to be reached
#   $2 - key to prepend to the status variable
# Returns:
#   true if the host can be reached.
################################################################
tracepath_host() {
    # shellcheck disable=SC2128
    [[ "$#" -eq 2 ]] || error_exit "usage: $FUNCNAME <url> <key>"
    local -r host="$1"
    local -r key="$2"

    local reachable_key="${key}_TRACEPATH_REACHABLE"
    local results_key="${key}_TRACEPATH_RESULT"
    if [[ -z "$(eval echo \$"${reachable_key}")" ]]; then
        local tracepath_cmd
        if have_command tracepath ; then
            tracepath_cmd="tracepath"
        elif have_command traceroute ; then
            tracepath_cmd="traceroute -m 12"
        fi

        if [[ -z "${tracepath_cmd}" ]]; then
            eval "readonly ${reachable_key}=\"$UNKNOWN\""
            eval "readonly ${results_key}=\"Route to $host is $UNKNOWN -- tracepath and traceroute both missing\""
        else
            echo "Tracing path from docker host to ${host} ... (this takes time)"
            local result; result="$(${tracepath_cmd} "$host" 2>&1)"
            eval "readonly ${reachable_key}=\"route to ${host}: $(echo_passfail "$?")\""
            eval "readonly ${results_key}=\"$result\""
        fi
    fi

    check_passfail "$(eval echo \$"${reachable_key}")"
}

################################################################
# Test connectivity with the external KB services.
#
# Globals: (set indirectly)
#   KB_REACHABLE_SMALL, KB_REACHABLE_LARGE,
#     KB_PING_SMALL_DATA, KB_PING_LARGE_DATA,
#   KB_CONTAINER_PING_REPORT,
#   KB_TRACEPATH_RESULT, KB_TRACEPATH_REACHABLE,
#   KB_URL_REACHABLE,
#   KB_CONTAINER_WEB_REPORT
# Arguments:
#   None
# Returns:
#   true if the service url is reachable from this host.
################################################################
check_kb_reachable() {
    if [[ -z "${KB_TRACEPATH_REACHABLE}" ]]; then
        if ! check_boolean "${USE_NETWORK_TESTS}" ; then
            readonly KB_URL_REACHABLE="${NETWORK_TESTS_SKIPPED}"
            return 0
        fi

        local -r KB_HOST="kb.blackducksoftware.com"
        local -r KB_URL="https://${KB_HOST}/"
        ping_host "${KB_HOST}" "KB" "${KB_HOST}"
        ping_via_all_containers "${KB_HOST}" "KB"
        tracepath_host "${KB_HOST}" "KB"
        probe_url "${KB_URL}" "KB" "${KB_URL}"
        get_container_web_report "${KB_URL}" "KB"
    fi

    check_passfail "${KB_URL_REACHABLE}"
}

################################################################
# Test connectivity with the external registration service.
#
# Globals: (set indirectly)
#   REG_REACHABLE_SMALL, REG_REACHABLE_LARGE,
#     REG_PING_SMALL_DATA, REG_PING_LARGE_DATA,
#   REG_CONTAINER_PING_REPORT,
#   REG_TRACEPATH_RESULT, REG_TRACEPATH_REACHABLE,
#   REG_URL_REACHABLE,
#   REG_CONTAINER_WEB_REPORT
# Arguments:
#   None
# Returns:
#   true if the service url is reachable from this host.
################################################################
check_reg_server_reachable() {
    if [[ -z "${REG_TRACEPATH_REACHABLE}" ]]; then
        if ! check_boolean "${USE_NETWORK_TESTS}" ; then
            readonly REG_URL_REACHABLE="${NETWORK_TESTS_SKIPPED}"
            return 0
        fi

        local -r REG_HOST="updates.blackducksoftware.com"
        local -r REG_URL="https://${REG_HOST}/"
        ping_host "${REG_HOST}" "REG" "${REG_HOST}"
        ping_via_all_containers "${REG_HOST}" "REG"
        tracepath_host "${REG_HOST}" "REG"
        probe_url "${REG_URL}" "REG" "${REG_URL}"
        get_container_web_report "${REG_URL}" "REG"
    fi

    check_passfail "${REG_URL_REACHABLE}"
}

################################################################
# Test connectivity with the external hub docker registry.
#
# Globals: (set indirectly)
#   DOCKER_HUB_TRACEPATH_RESULT, DOCKER_HUB_TRACEPATH_REACHABLE,
#   DOCKER_HUB_URL_REACHABLE,
#   DOCKER_HUB_CONTAINER_WEB_REPORT
# Arguments:
#   None
# Returns:
#   true if the service url is reachable from this host.
################################################################
check_docker_hub_reachable() {
    if [[ -z "${DOCKER_HUB_TRACEPATH_REACHABLE}" ]]; then
        if ! check_boolean "${USE_NETWORK_TESTS}" ; then
            readonly DOCKER_HUB_URL_REACHABLE="${NETWORK_TESTS_SKIPPED}"
            return 0
        fi

        local -r DOCKER_HOST="hub.docker.com"
        local -r DOCKER_URL="https://${DOCKER_HOST}/u/blackducksoftware/"
        tracepath_host "${DOCKER_HOST}" "DOCKER_HUB"
        probe_url "${DOCKER_URL}" "DOCKER_HUB" "${DOCKER_URL}"
        get_container_web_report "${DOCKER_URL}" "DOCKER_HUB"
    fi

    check_passfail "${DOCKER_HUB_URL_REACHABLE}"
}

################################################################
# Test connectivity with the external docker registry.
#
# Globals: (set indirectly)
#   DOCKERIO_REACHABLE_SMALL, DOCKERIO_REACHABLE_LARGE,
#     DOCKERIO_PING_SMALL_DATA, DOCKERIO_PING_LARGE_DATA,
#   DOCKERIO_CONTAINER_PING_REPORT,
#   DOCKERIO_TRACEPATH_RESULT, DOCKERIO_TRACEPATH_REACHABLE,
#   DOCKERIO_URL_REACHABLE,
#   DOCKERIO_CONTAINER_WEB_REPORT
# Arguments:
#   None
# Returns:
#   true if the service url is reachable from this host.
################################################################
check_dockerio_reachable() {
    if [[ -z "${DOCKERIO_TRACEPATH_REACHABLE}" ]]; then
        if ! check_boolean "${USE_NETWORK_TESTS}" ; then
            readonly DOCKERIO_URL_REACHABLE="${NETWORK_TESTS_SKIPPED}"
            return 0
        fi

        local -r DOCKERIO_HOST="registry-1.docker.io"
        local -r DOCKERIO_URL="https://${DOCKERIO_HOST}/"
        tracepath_host "${DOCKERIO_HOST}" "DOCKERIO"
        probe_url "${DOCKERIO_URL}" "DOCKERIO" "${DOCKERIO_URL}"
        get_container_web_report "${DOCKERIO_URL}" "DOCKERIO"
    fi

    check_passfail "${DOCKERIO_URL_REACHABLE}"
}

################################################################
# Test connectivity with the external docker auth service.
#
# Globals: (set indirectly)
#   DOCKERIO_AUTH_TRACEPATH_RESULT, DOCKERIO_AUTH_TRACEPATH_REACHABLE,
#   DOCKERIO_AUTH_URL_REACHABLE,
#   DOCKERIO_AUTH_CONTAINER_WEB_REPORT
# Arguments:
#   None
# Returns:
#   true if the service url is reachable from this host.
################################################################
check_dockerio_auth_reachable() {
    if [[ -z "${DOCKERIOAUTH_TRACEPATH_REACHABLE}" ]]; then
        if ! check_boolean "${USE_NETWORK_TESTS}" ; then
            readonly DOCKERIOAUTH_URL_REACHABLE="${NETWORK_TESTS_SKIPPED}"
            return 0
        fi

        local -r DOCKERIO_AUTH_HOST="auth.docker.io"
        local -r DOCKERIO_AUTH_URL="https://${DOCKERIO_AUTH_HOST}/"
        tracepath_host "${DOCKERIO_AUTH_HOST}" "DOCKERIOAUTH"
        probe_url "${DOCKERIO_AUTH_URL}" "DOCKERIOAUTH" "${DOCKERIO_AUTH_URL}"
        get_container_web_report "${DOCKERIO_AUTH_URL}" "DOCKERIOAUTH"
    fi

    check_passfail "${DOCKERIOAUTH_URL_REACHABLE}"
}

################################################################
# Test connectivity with github.com.
#
# Globals: (set indirectly)
#   GITHUB_TRACEPATH_RESULT, GITHUB_TRACEPATH_REACHABLE,
#   GITHUB_URL_REACHABLE,
#   GITHUB_CONTAINER_WEB_REPORT
# Arguments:
#   None
# Returns:
#   true if the service url is reachable from this host.
################################################################
check_github_reachable() {
    if [[ -z "${GITHUB_TRACEPATH_REACHABLE}" ]]; then
        if ! check_boolean "${USE_NETWORK_TESTS}" ; then
            readonly GITHUB_URL_REACHABLE="${NETWORK_TESTS_SKIPPED}"
            return 0
        fi

        local -r GITHUB_HOST="github.com"
        local -r GITHUB_URL="https://${GITHUB_HOST}/blackducksoftware/hub/raw/master/archives/"
        tracepath_host "${GITHUB_HOST}" "GITHUB"
        probe_url "${GITHUB_URL}" "GITHUB" "${GITHUB_URL}"
        get_container_web_report "${GITHUB_URL}" "GITHUB"
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
#   - One global per each of the HUB container names
# Arguments:
#   None
# Returns:
#   true if none of the hub container names resolve.
################################################################
check_internal_hostnames_dns_status() {
    echo "Checking Hostnames for DNS conflicts..."
    overall_status=${PASS}
    for cur_hostname in ${HUB_RESERVED_HOSTNAMES}
    do
        local cur_status=$(probe_dns_hostname $cur_hostname)
        local hostname_upper=$(echo ${cur_hostname} | awk '{print toupper($0)}')        
        local cur_global_var_name="${hostname_upper}_DNS_STATUS"
        eval "export ${cur_global_var_name}=\"${cur_status}\""

        if ! check_passfail "${cur_status}" ; then
            overall_status=${FAIL}
        fi
    done

    check_passfail "${overall_status}"
}


################################################################
# Helper to check a hostname's DNS resolution
# - Assumed to be run in a subshell
# - echos it's return value to stdout
# Arguments: 
# <hostname> - The hostname to check
#
#
################################################################
probe_dns_hostname() { 
    [[ "$#" -eq 1 ]] || error_exit "usage: $FUNCNAME <hostname>"
    local -r hostname="$1"
    
    if ! have_command nslookup ; then
            readonly DNS_STATUS="DNS resolution of '${hostname}' is $UNKNOWN -- nslookup not found."
    else
        if ! nslookup "${hostname}" >/dev/null 2>&1 ; then
            readonly DNS_STATUS="$PASS: hostname '${hostname}' does not resolve in this environment."
        else
            readonly DNS_STATUS="$FAIL: hostname '${hostname}' resolved.  This could cause problems."
        fi
    fi
    
    echo "${DNS_STATUS}"
}

################################################################
#
# Generate DNS check report section
# - echos the DNS status check information to stdout
# 
generate_dns_checks_report_section() { 
    
    for cur_hostname in ${HUB_RESERVED_HOSTNAMES} 
    do
        echo "Hostname \"${cur_hostname}\" DNS Status:"
        local cur_hostname_upper=$(echo ${cur_hostname} | awk '{print toupper($0)}')
        printenv "${cur_hostname_upper}_DNS_STATUS"
        echo ""
    done
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
    # shellcheck disable=SC2128
    [[ "$#" -le 2 ]] || error_exit "usage: $FUNCNAME [ <report-path> [ <copy-simple-name> ] ]"
    local -r source="${1:-$OUTPUT_FILE}"
    local -r target="${2:-latest_system_check.txt}"

    if is_docker_present && is_root ; then
        local -r logstash_data_dir=$(docker volume ls -f name=_log-volume --format '{{.Mountpoint}}')
        if [[ -e "$logstash_data_dir" ]]; then
            local -r first_logstash_dir=$(find "$logstash_data_dir" -name "hub*" | head -n 1)
            local -r logstash_owner=$(ls -ld "${first_logstash_dir}" | awk '{print $3}')
            cp "${source}" "${logstash_data_dir}/${target}"
            chown "$logstash_owner":root "${logstash_data_dir}/${target}"
            chmod 664 "${logstash_data_dir}/${target}"
        fi
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
    # shellcheck disable=SC2128
    [[ "$#" -le 2 ]] || error_exit "usage: $FUNCNAME <title> [ <count> ]"
    local -r title="$1"
    local -r count="${2:-$(( $(grep -c . "${OUTPUT_FILE_TOC}") + 1 ))}"

    echo "${REPORT_SEPARATOR}"
    echo "${count}. ${title}" | tee -a "${OUTPUT_FILE_TOC}"
}

################################################################
# Save a full report to disk.
#
# Globals:
#   OUTPUT_FILE -- (in) default output file path.
# Arguments:
#   $1 - output file path, default "${OUTPUT_FILE}"
# Returns:
#   None
################################################################
generate_report() {
    # shellcheck disable=SC2128
    [[ "$#" -le 1 ]] || error_exit "usage: $FUNCNAME [ <report-path> ]"
    local -r target="${1:-$OUTPUT_FILE}"

    # Reserve this section number; the body will be generated later.
    echo "1. Problems found" > "${OUTPUT_FILE_TOC}"

    local -r header="${REPORT_SEPARATOR}
System check version $HUB_VERSION for Black Duck
"
    local -r report=$(cat <<END
$(generate_report_section "Operating System information")

Supported OS (Linux): ${IS_LINUX}

OS Info:
${OS_NAME}

Kernel version check: ${KERNEL_VERSION_STATUS}

$(generate_report_section "Package list")

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

$(generate_report_section "Sysctl Network Keepalive Settings")

IPV4 Keepalive Time: ${SYSCTL_KEEPALIVE_TIME}
IPV4 Keepalive Time Meets Recommendations: ${SYSCTL_KEEPALIVE_TIME_MEETS_RECOMMENDATIONS}

IPV4 Keepalive Interval: ${SYSCTL_KEEPALIVE_INTERVAL}
IPV4 Keepalive Interval Meets Recommendations: ${SYSCTL_KEEPALIVE_INTERVAL_MEETS_RECOMMENDATIONS}

IPV4 Keepalive Probes: ${SYSCTL_KEEPALIVE_PROBES}
IPV4 Keepalive Probes Meets Recommendations: ${SYSCTL_KEEPALIVE_PROBES_MEETS_RECOMMENDATIONS}

$(generate_report_section "Running processes")

${RUNNING_PROCESSES}

$(generate_report_section "Docker")

Docker installed: ${IS_DOCKER_PRESENT}
Docker version: ${DOCKER_VERSION}
Docker version check: ${DOCKER_VERSION_CHECK}
Docker versions supported: ${REQ_DOCKER_VERSIONS}
Docker compose installed: ${IS_DOCKER_COMPOSE_PRESENT}
Docker compose version: ${DOCKER_COMPOSE_VERSION}
Docker startup: ${DOCKER_STARTUP_INFO}
Docker OS Compatibility Check: ${DOCKER_OS_COMPAT_CHECK}
Docker OS Compatibility Status: ${DOCKER_OS_COMPAT}

$(generate_report_section "Docker image list")

${DOCKER_IMAGES}

$(generate_report_section "Docker image details")

${DOCKER_IMAGE_INSPECTION}

$(generate_report_section "Docker container list")

${DOCKER_CONTAINERS}

$(generate_report_section "Docker container details")

${DOCKER_CONTAINER_INSPECTION}

$(generate_report_section "Docker process list")

${DOCKER_PROCESSES}

$(generate_report_section "Docker network list")

${DOCKER_NETWORKS}

$(generate_report_section "Docker network details")

${DOCKER_NETWORK_INSPECTION}

$(generate_report_section "Docker volume list")

${DOCKER_VOLUMES}

$(generate_report_section "Docker volume details")

${DOCKER_VOLUME_INSPECTION}

$(generate_report_section "Docker swarm node list")

${DOCKER_NODES}

$(generate_report_section "Docker swarm node details")

${DOCKER_NODE_INSPECTION}

$(generate_report_section "Black Duck KB services connectivity")

${KB_URL_REACHABLE}

${KB_REACHABLE_SMALL}
${KB_PING_SMALL_DATA}

${KB_REACHABLE_LARGE}
${KB_PING_LARGE_DATA}

Trace path result: ${KB_TRACEPATH_REACHABLE}
Trace path output: ${KB_TRACEPATH_RESULT}

Ping connectivity to Black Duck KB via docker containers:
${KB_CONTAINER_PING_REPORT}

Web access to Black Duck KB via docker containers:
${KB_CONTAINER_WEB_REPORT}

$(generate_report_section "Black Duck registration server connectivity")

${REG_URL_REACHABLE}

${REG_REACHABLE_SMALL}
${REG_PING_SMALL_DATA}

${REG_REACHABLE_LARGE}
${REG_PING_LARGE_DATA}

Trace path result: ${REG_TRACEPATH_REACHABLE}
Trace path output: ${REG_TRACEPATH_RESULT}

Connectivity to Black Duck registration service via docker containers:
${REG_CONTAINER_PING_REPORT}

Web access to Black Duck registration service via docker containers:
${REG_CONTAINER_WEB_REPORT}

$(generate_report_section "Docker Hub registry connectivity")

Trace path result: ${DOCKER_HUB_TRACEPATH_REACHABLE}
Trace path output: ${DOCKER_HUB_TRACEPATH_RESULT}

${DOCKER_HUB_URL_REACHABLE}

Web access to Docker Hub via docker containers:
${DOCKER_HUB_CONTAINER_WEB_REPORT}

$(generate_report_section "Docker IO registry connectivity")

Trace path result: ${DOCKERIO_TRACEPATH_REACHABLE}
Trace path output: ${DOCKERIO_TRACEPATH_RESULT}

${DOCKERIO_URL_REACHABLE}

Web access to Docker IO Registry via docker containers:
${DOCKERIO_CONTAINER_WEB_REPORT}

$(generate_report_section "Docker IO Auth connectivity")

Trace path result: ${DOCKERIOAUTH_TRACEPATH_REACHABLE}
Trace path output: ${DOCKERIOAUTH_TRACEPATH_RESULT}

${DOCKERIOAUTH_URL_REACHABLE}

Web access to Docker IO Auth server via docker containers:
${DOCKERIOAUTH_CONTAINER_WEB_REPORT}

$(generate_report_section "GitHub connectivity")

Trace path result: ${GITHUB_TRACEPATH_REACHABLE}
Trace path output: ${GITHUB_TRACEPATH_RESULT}

${GITHUB_URL_REACHABLE}

Web access to GitHub via docker containers:
${GITHUB_CONTAINER_WEB_REPORT}

$(generate_report_section "Misc. DNS checks.")

$(generate_dns_checks_report_section)

END
)
    local -r failures="$(echo "$report" | grep $FAIL)"
    local -r warnings="$(echo "$report" | grep $WARN)"

    echo "$header" > "${target}"
    (echo "Table of contents:"; echo; sort -n "${OUTPUT_FILE_TOC}"; echo) >> "${target}"
    cat >> "${target}" <<END
$(generate_report_section "Problems detected" 1)

${failures:-No failures.}

${warnings:-No warnings.}

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
Black Duck System Check - Checks system information for compatibility and troubleshooting.

Usage:
    $(basename "$0") <arguments>

Supported Arguments:

    --no-network      Do not use network tests, assume host has no connectivity
                      This can be useful as network tests can take a long time 
                      on a system with no connectivity.
    
    --help            Print this Help Message

END
)
    echo "$usage_message"
}


################################################################
#
# Check program arguments
# 
#
################################################################
process_args() { 
    while [[ $# -gt 0 ]] ; do
        case "$1" in
            '--no-network' )
                shift
                USE_NETWORK_TESTS="FALSE"
                echo "*** Skipping Network Tests ***"
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

    is_root

    echo "System check version ${HUB_VERSION} for Black Duck"
    echo "Writing system check report to: ${OUTPUT_FILE}"
    echo

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

    check_entropy
    get_interface_info
    get_routing_info
    get_bridge_info
    get_hosts_file
    get_ports
    get_specific_ports
    check_docker_version
    get_docker_compose_version
    check_docker_startup_info
    check_docker_os_compatibility
    get_docker_images
    get_docker_containers
    get_docker_processes
    get_docker_networks
    get_docker_volumes
    get_docker_nodes
    check_sufficient_ram

    get_firewall_info
    get_iptables


    # Black Duck sites that need to be checked
    check_kb_reachable
    check_reg_server_reachable

    # External sites that need to be checked
    check_docker_hub_reachable
    check_dockerio_reachable
    check_dockerio_auth_reachable
    check_github_reachable

    # Check if DNS returns a result for webapp
    check_internal_hostnames_dns_status

    generate_report "${OUTPUT_FILE}"
    copy_to_logstash "${OUTPUT_FILE}"
}

[[ -n "${LOAD_ONLY}" ]] || main ${1+"$@"}
