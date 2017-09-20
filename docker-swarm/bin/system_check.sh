#!/usr/bin/env bash 

HUB_VERSION=${HUB_VERSION:-4.1.3}
OUTPUT_FILE=${SYSTEM_CHECK_OUTPUT_FILE:-"system_check.txt"}
CPUS_REQUIRED=4
# Our RAM requirements are as follows:
# Non-Swarm Install: 16GB
# Swarm Install with many nodes: 16GB per node
# Swarm Install with a single node: 20GB
# 
# The script plays some games here because linux never reports 100% of the physical memory on a system, 
# so the way this script checks memory linux will usually report 1GB less than the correct amount. 
#
RAM_REQUIRED_GB=15
RAM_REQUIRED_GB_SWARM=19
RAM_REQUIRED_PHYSICAL_DESCRIPTION="16GB Required"
RAM_REQUIRED_PHYSICAL_DESCRIPTION_SWARM="20 Required on Swarm Node if all BD Containers are on a single Node"

DISK_REQUIRED_MB=250000
MIN_DOCKER_VERSION=17.03
MIN_DOCKER_MAJOR_VERSION=17
MIN_DOCKER_MINOR_VERSION=03

printf "Writing System Check Report to: %s\n" "$OUTPUT_FILE"

check_user() {
  echo "Checking user..."
  id=`id -u`
  current_username=`id -un`
  if [ "$id" -ne 0 ] ; then
    echo "This script must be run as root for all features to work."
    is_root=FALSE
    return    
  fi
  is_root=TRUE
}

OS_UNKNOWN="unknown"
_SetOSName()
{
  echo "Checking OS..."
    # Set the PROP_OS_NAME variable to a short string identifying the
    # operating system version.  This string is also the path where we
    # store the 3rd-party rpms.
    #
    # Usage: _SetOSName 3rd-party-dir

    # Find the local release name.
    # See http://linuxmafia.com/faq/Admin/release-files.html for more ideas.

    IS_LINUX=TRUE
    command -v lsb_release > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
      PROP_HAVE_lsb_release=0
    else
      PROP_HAVE_lsb_release=1
    fi

    if [ "$PROP_HAVE_lsb_release" == 1 ]; then
        PROP_OS_NAME="`lsb_release -a ; echo ; echo -n uname -a:\  ; uname -a`"
    elif [ -e /etc/fedora-release ]; then
        PROP_OS_NAME="`cat /etc/fedora-release`"
    elif [ -e /etc/redhat-release ]; then
        PROP_OS_NAME="`cat /etc/redhat-release`"
    elif [ -e /etc/centos-release ]; then
        PROP_OS_NAME="`cat /etc/centos-release`"
    elif [ -e /etc/SuSE-release ]; then
        PROP_OS_NAME="`cat /etc/SuSE-release`"
    elif [ -e /etc/gentoo-release ]; then
        PROP_OS_NAME="`cat /etc/gentoo-release`"
    elif [ -e /etc/os-release ]; then
        PROP_OS_NAME="`cat /etc/os-release`"
    else
        PROP_OS_NAME="`echo -n uname -a:\  ; uname -a`"
        IS_LINUX=FALSE
    fi
}

CPUINFO_FILE="/proc/cpuinfo"
get_cpu_info() {
  echo "Checking CPU Information..."
   if [ -e "$CPUINFO_FILE" ] ; then 
    CPU_INFO=`cat $CPUINFO_FILE`
   else
    CPU_INFO="CPU Info Unavailable - non linux system"
   fi
}

check_cpu_count() {
  echo "Counting CPUs..."
  command -v lscpu > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    CPU_COUNT_INFO="Unable to Check # CPUS, lscpu not found"
    return
  fi

  CPU_COUNT=`lscpu -p=cpu | grep -v -c '#'`
  if [ "$CPU_COUNT" -lt "$CPUS_REQUIRED" ] ; then
    CPU_COUNT_INFO="CPU Count: FAILED ($CPUS_REQUIRED required)"
  else
    CPU_COUNT_INFO="CPU Count: PASSED"
  fi 

}

get_mem_info() {
  echo "Retrieving memory Information..."
  command -v free > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    # Free not available
    MEMORY_INFO="Unable to get memory information - non linux system."
  else
    MEMORY_INFO="`free -h`"
  fi
}

check_sufficient_ram() {
  echo "Checking if sufficient RAM is present..."
  command -v free > /dev/null 2>&1

  if [ $? -ne 0 ] ; then
    # Free not available
    SUFFICIENT_RAM_INFO="Unable to get memory information - non linux system."
    return
  fi

  SELECTED_RAM_REQUIREMENT=$RAM_REQUIRED_GB
  SELECTED_RAM_DESCRIPTION=$RAM_REQUIRED_PHYSICAL_DESCRIPTION
  
  if [ "$SWARM_ENABLED" == "TRUE" ] ; then 
    SELECTED_RAM_REQUIREMENT=$RAM_REQUIRED_GB_SWARM
    SELECTED_RAM_DESCRIPTION=$RAM_REQUIRED_PHYSICAL_DESCRIPTION_SWARM
  fi

  total_ram_in_gb=`free -g | grep 'Mem' | awk -F' ' '{print $2}'`
  if [ "$total_ram_in_gb" -lt "$SELECTED_RAM_REQUIREMENT" ] ; then
    SUFFICIENT_RAM_INFO="Total Ram: FAILED ($SELECTED_RAM_DESCRIPTION)"
  else
    SUFFICIENT_RAM_INFO="Total RAM: PASSED"
  fi
}

get_disk_info() {
  echo "Checking Disk Information..."
  command -v df > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    DISK_INFO="Unable to get Disk Info - df not present"
  else
    DISK_INFO="`df -h`"
    # Get disk space in human readable format with totals, select only the total line
    # select the 2nd column from that, then remove the last character to get rid of the "G" for 
    # gigabyte
    if [ "$IS_LINUX" != "TRUE" ] ; then 
      TOTAL_DISK_SPACE="Unknown"
      DISK_SPACE_MESSAGE="Cannot determine sufficient disk space on non linux system"
      return;
    fi

    TOTAL_DISK_SPACE=`df -m --total | grep 'total' | awk -F' ' '{print $2}'`
    if [ "$TOTAL_DISK_SPACE" -lt "$DISK_REQUIRED_MB" ] ; then 
      DISK_SPACE_MESSAGE="Insufficient Disk Space (found: ${TOTAL_DISK_SPACE}mb, required: ${DISK_REQUIRED_MB}mb)"
    else
      DISK_SPACE_MESSAGE="Sufficient Disk Space (found: ${TOTAL_DISK_SPACE}mb, required ${DISK_REQUIRED_MB}mb)"
    fi
  fi
}

# Check what ports are being listened on currently - may be useful for bind errors
check_ports() {
  echo "Checking Network Ports..."
  command -v netstat > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    listen_ports="Unable to run netstat - cannot list ports being listened on."
  else
    listen_ports=`netstat -ln`
  fi
}

get_processes() { 
  echo "Checking Running Processes..."
  RUNNING_PROCESSES=""
  command -v ps > /dev/null 2>&1
  if [ $? -ne 0 ] ; then 
    echo "Cannot Check Processes - ps not found"
    return
  fi

  RUNNING_PROCESSES=`ps aux`
}


# Check if Docker is installed
is_docker_present() {
  echo "Checking For Docker..."
  docker_installed=FALSE
  command -v docker > /dev/null 2>&1
  if [ $? -eq 0 ] ; then
      docker_installed=TRUE
  fi 
}

# Check the version of docker
get_docker_version() {
  if [ "$docker_installed" == "TRUE" ] ; then
    echo "Checking Docker Version..."
    docker_version=`docker --version`

    docker_major_version=`docker --version | awk -F' ' '{print $3}' | awk -F'.' '{print $1}'`
    docker_minor_version=`docker --version | awk -F' ' '{print $3}' | awk -F'.' '{print $1}'`

    if [ "$docker_major_version" -lt "$MIN_DOCKER_MAJOR_VERSION" ] ; then
      docker_version_check="Docker Version Check - Failed: ($MIN_DOCKER_VERSION required)"
      return
    fi

    if [ "$docker_minor_version" -lt "$MIN_DOCKER_MINOR_VERSION" ] ; then
      docker_version_check="Docker Version Check - Failed: ($MIN_DOCKER_VERSION required)"
      return
    fi

    docker_version_check="Docker Version Check - Passed"
    return
  fi

  docker_version_check="Docker Version Check - Failed - Docker not present"

}

# Check if docker-compose is installed
check_docker_compose_installed() {
  echo "Checking For Docker Compose..."
  command -v docker-compose > /dev/null 2>&1
  if [ $? -eq 0 ] ; then
    docker_compose_installed=TRUE
  else
    docker_compose_installed=FALSE
  fi
}

find_docker_compose_version() {
  if [ "$docker_compose_installed" == "TRUE" ] ; then
    echo "Checking Docker Compose Version..."
    docker_compose_version=`docker-compose --version`
  else
    docker_compose_version="Not Installed"
  fi
}

check_docker_systemctl_status() {
  if [ "$docker_installed" == "FALSE" ] ; then
    docker_enabled_at_startup=FALSE
    return
  fi
  echo "Checking Systemd to determine if docker is enabled at boot..."
  command -v systemctl > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    docker_enabled_at_startup="Unable to determine - systemctl not found"
    return
  fi

  systemctl list-unit-files | grep enabled | grep docker > /dev/null 2>&1
  if [ $? -eq 0 ] ; then
    docker_enabled_at_startup=TRUE   
  else
    docker_enabled_at_startup=FALSE
  fi

}

check_docker_images() {
  if [ "$is_root" == "FALSE" ] ; then 
    bd_docker_images="Cannot list docker images without root access"
    return
  fi

  echo "Checking Docker Images Present..."

  if [ "$docker_installed" == "TRUE" ] ; then
    bd_docker_images=`docker images | awk -F' ' '{printf("%-80s%-80s\n",$1,$2);}' | sort`
  else
    bd_docker_images="Docker Not installed, no images present."
  fi
}

check_docker_processes() {
  if [ "$is_root" == "FALSE" ] ; then 
    docker_processes="Cannot list docker processes without root access"
    return
  fi

  if [ "$docker_installed" == "FALSE" ] ; then
    docker_processes="No Docker Processes - Docker not installed."
    return
  fi

  echo "Checking Current Docker Processes..."

  docker_processes=`docker ps`
}

inspect_docker_networks() {
  if [ "$is_root" == "FALSE" ] ; then 
    docker_networks="Cannot inspect docker networks without root access"
    return
  fi

  if [ "$docker_installed" == "FALSE" ] ; then
    docker_networks="No Docker Networks - Docker not installed."
    return 
  fi

  echo "Checking Docker Networks..."

  docker_networks=`docker network ls -q | xargs docker network inspect`
}

inspect_docker_volumes() {
  if [ "$is_root" == "FALSE" ] ; then 
    docker_volumes="Cannot inspect docker volumes without root access"
    return
  fi

  if [ "$docker_installed" == "FALSE" ] ; then
    docker_volumes="No Docker Networks - Docker not installed."
    return 
  fi

  echo "Checking Docker Volumes..."

  docker_volumes=`docker volume ls -q | xargs docker volume inspect`
}

inspect_docker_swarms() {
  SWARM_ENABLED=FALSE
  if [ "$is_root" == "FALSE" ] ; then 
    docker_swarm_data="Cannot inspect docker swarms without root access"
    return
  fi

  if [ "$docker_installed" == "FALSE" ] ; then
    docker_swarm_data="No Docker Swarms - Docker not installed."
    return 
  fi

  echo "Checking Docker Swarms..."

  docker_nodes=`docker node ls > /dev/null 2>&1`
  if [ "$?" -ne 0 ] ; then 
    docker_swarm_data="Machine is not part of a docker swarm or is not the manager"    
    return
  fi

  SWARM_ENABLED=TRUE
  docker_swarm_data=`docker node ls -q | xargs docker node inspect`

}

check_firewalld() {
  firewalld_enabled=FALSE
  firewalld_active_zones="N/A"
  firewalld_all_zones="N/A"
  firewalld_default_zone="N/A"
  firewalld_services="N/A"

  if [ "$is_root" == "FALSE" ] ; then 
    firewalld_enabled="Cannot check firewalld without root access"
    return
  fi

  command -v systemctl > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    firewalld_enabled="Unable to determine - systemctl not found"
    return
  fi

  echo "Checking Firewalld..."

  firewalld_enabled=`systemctl list-unit-files | grep enabled | grep firewalld.service`
  if [ "$?" -ne 0 ] ; then
    return
  fi

  firewalld_enabled=TRUE
  firewalld_active_zones=`firewall-cmd --get-active-zones`
  firewalld_all_zones=`firewall-cmd --list-all-zones`  
  firewalld_services=`firewall-cmd --get-services`
  firewalld_default_zone=`firewall-cmd --get-default-zone`

}

check_iptables() {
  if [ "$is_root" == "FALSE" ] ; then 
    iptables_https_rules="Cannot check iptables https rules without root access"
    return
  fi

  echo "Checking IP Tables Rules..."

  command -v iptables > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    iptables_all_rules="Unable to Check iptables - iptables not found."
    iptables_https_rules="Unable to Check iptables - iptables not found."
    iptables_db_rules="Unable to Check iptables - iptables not found."
  else
    iptables_https_rules=`iptables --list | grep https`
    iptables_db_rules=`iptables --list | grep '55436'`
    iptables_all_rules=`iptables --list`
  fi
}

# Only valid on linux
ENTROPY_FILE="/proc/sys/kernel/random/entropy_avail"
check_entropy() {

  if [ -e "$ENTROPY_FILE" ] ; then
    echo "Checking Entropy..."
    available_entropy=`cat $ENTROPY_FILE`
  else
    available_entropy="Cannot Determine Entropy on non linux system"
  fi
}

# Helper method to ping a host.   A small (64 byte) and large (1500 byte)
# ping attempt will be made
# Parameters:
#   $1 - Hostname to ping
#   $2 - Key to store the results in the ping_results associative array
#  
#  example: 
#  ping_host kb.blackducksoftware.com kb
#
#  Results will be stored like this:
#  ping_results["kb_reachable_small"]=FALSE or TRUE depending on result
#  ping_results["kb_reachable_large"]=FALSE or TRUE depending on result
#  ping_results["kb_ping_small_data"]= ping output
#  ping_results["kb_ping_large_data"]= ping output
#
ping_host() {

  if [ "$#" -lt "3" ] ; then 
    echo "ping_host: too few parameters."
    echo "usage: ping_host <hostname> <key> <label>"
    exit -1
  fi

  hostname=$1
  key=$2
  label=$3
  small_result_key="${key}_reachable_small"
  small_data_key="${key}_ping_small_data"
  large_result_key="${key}_reachable_large"
  large_data_key="${key}_ping_large_data"
  ping_missing_message="Unable to test $label connectivity - ping not found"
  ping_small_packet_size=56
  ping_large_packet_size=1492

  command -v ping > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    eval "$small_result_key=$ping_missing_message"
    eval "$large_result_key=$ping_missing_message"
    eval "$small_data_key=$ping_missing_message"
    eval "$large_data_key=$ping_missing_message"
  else
    # Check Small and large packets separately
    echo "Checking connectivity to $label via small packet ping... (this takes time)"
    eval "$small_data_key=\"`ping -c 3 -s $ping_small_packet_size $hostname`\""
    if [ $? -ne 0 ] ; then 
      eval "$small_result_key=\"FALSE\""
    else
      eval "$small_result_key=\"TRUE\""
    fi

    echo "Checking connectivity to $label via large packet ping... (this takes time)"
    eval "$large_data_key=\"`ping -c 3 -s $ping_large_packet_size $hostname`\""
    if [ $? -ne 0 ] ; then 
      eval "$large_result_key=\"FALSE\""
    else
      eval "$large_result_key=\"TRUE\""
    fi
  fi
}

# Helper method to see if a URL is reachable.
# This just makes a simple curl request and throws away the output.
# If curl returns 0 (success) then this will set a value based on 
# the key passed in:
#
# e.x. 
# curl_host http://foo.com foo foo_label
# Messages would use foo_label in output
# The result will be TRUE or FALSE and will be stored in foo_http_reachable
curl_url() { 
  if [ "$#" -lt "3" ] ; then 
    echo "curl_host: too few parameters."
    echo "usage: curl_host <url> <key> <label>"
    exit -1
  fi

  url=$1
  key=$2
  label=$3
  reachable_key=${key}_http_reachable
  curl_missing_message="Cannot attempt HTTP request to $label (${url}), curl is missing"

  command -v curl > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    eval "$reachable_key=$curl_missing_message"
    eval "$reachable_key=$curl_missing_message"
  else
    echo "Checking connectivity to $label via HTTP Request... (this takes time)"
    
    curl -s -o /dev/null $url
    if [ $? -ne 0 ] ; then 
      eval "$reachable_key=\"FALSE\""
    else
      eval "$reachable_key=\"TRUE\""
    fi

  fi
}


KB_HOST="kb.blackducksoftware.com"
KB_URL="http://$KB_HOST/"
check_kb_reachable() {
  ping_host "$KB_HOST" "kb" "$KB_HOST"
  curl_url "$KB_URL" "kb" "$KB_URL"
}

REG_HOST="registration.blackducksoftware.com"
REG_URL="http://$REG_HOST/"
check_reg_server_reachable() {
  ping_host "$REG_HOST" "reg" "$REG_HOST"
  curl_url "$REG_URL" "reg" "$REG_URL"
}

DOC_HOST="doc.blackducksoftware.com"
DOC_URL="http://$DOC_HOST/"
check_doc_server_reachable() {
  ping_host "$DOC_HOST" "doc" "$DOC_HOST"
  curl_url "$DOC_URL" "doc" "$DOC_URL"
}

DOCKER_URL="https://hub.docker.com/u/blackducksoftware/"
check_docker_hub_reachable() {
  curl_url "$DOCKER_URL" "docker_hub" "$DOCKER_URL"
}

GITHUB_URL="https://github.com/blackducksoftware/hub/raw/master/archives/"
check_github_reachable() {
  curl_url "$GITHUB_URL" "github" "$GITHUB_URL"
}

# Make sure the user running isn't limited excessively
check_ulimits() {
  echo "Checking ulimits..."

  command -v ulimit > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    ulimit_results="Cannot Check User limits - ulimit not found"
  else
    ulimit_results=`ulimit -a`
  fi
}

# Check SELinux status
check_selinux_status() {
  echo "Checking SELinux..."

  command -v sestatus > /dev/null 2>&1
  if [ $? -ne 0 ] ; then 
    selinux_status="Cannot Check SELinux Status - sestatus not found"
  else 
    selinux_status=`sestatus`
  fi
}

SEPARATOR='=============================================================================='

generate_report() {
  REPORT=$(cat <<END
$SEPARATOR
System Check for Black Duck Software Hub Version: $HUB_VERSION

$SEPARATOR
Supported OS (Linux):
$IS_LINUX

OS Info: 
$PROP_OS_NAME

$SEPARATOR
Current user: $current_username
Current user limits:
$ulimit_results

$SEPARATOR
SELinux:
$selinux_status

$SEPARATOR
CPU Info:
$CPU_INFO

$SEPARATOR
CPU Count:
$CPU_COUNT_INFO

$SEPARATOR
Memory Info:
$MEMORY_INFO

$SEPARATOR
RAM Check:
$SUFFICIENT_RAM_INFO

$SEPARATOR
Disk Space:
$DISK_SPACE_MESSAGE
Disk Info:
$DISK_INFO 

$SEPARATOR
Available Entropy: $available_entropy
Entropy Guide: 0-100 - Problem Level, 100-200 Warning, 200+ OK

$SEPARATOR
Ports in use: 
$listen_ports

$SEPARATOR
IP Tables Rules for HTTPS: 
$iptables_https_rules

IP Tables Rules for Black Duck DB Port:
$iptables_db_rules

All IP Tables Rules:
$iptables_all_rules

$SEPARATOR
Firewalld:
Firewalld enabled: $firewalld_enabled
Firewalld Active Zones: $firewalld_active_zones
Firewalld All Zones: $firewalld_all_zones 
Firewalld Services: $firewalld_services 

$SEPARATOR
Running Processes:
$RUNNING_PROCESSES

$SEPARATOR
Docker Installed: $docker_installed
Docker Version: $docker_version 
Docker Version Check: $docker_version_check
Docker Minimum Version Supported: $MIN_DOCKER_VERSION
Docker Compose Installed: $docker_compose_installed
Docker Compose Version: $docker_compose_version
Docker Enabled at Startup: $docker_enabled_at_startup

$SEPARATOR
Docker Images Present: 
$bd_docker_images

$SEPARATOR
Docker Processes: 
$docker_processes

$SEPARATOR
Docker Networks: 
$docker_networks

$SEPARATOR
Docker Volumes: 
$docker_volumes

$SEPARATOR
Docker Swarm:
$docker_swarm_data

$SEPARATOR
Black Duck KB Connectivity: 
HTTP Connectivity: $kb_http_reachable
Reachable via Ping (small data): $kb_reachable_small 
Reachable via Ping (large data): $kb_reachable_large
Ping Output (small data): $kb_ping_small_data 
Ping Output (large data): $kb_ping_large_data

$SEPARATOR
Black Duck Registration Connectivity:
HTTP Connectivity: $reg_http_reachable
Reachable via Ping (small data): $reg_reachable_small
Reachable via Ping (large data): $reg_reachable_large
Ping Output (small data): $reg_ping_small_data 
Ping Output (large data): $reg_ping_large_data

$SEPARATOR
Black Duck Doc Connectivity:
HTTP Connectivity: $doc_http_reachable
Reachable via Ping (small data): $doc_reachable_small
Reachable via Ping (large data): $doc_reachable_large
Ping Output (small data): $doc_ping_small_data
Ping Output (large data): $doc_ping_large_data

$SEPARATOR
Docker Hub Connectivity: 
HTTP Connectivity: $docker_hub_http_reachable

$SEPARATOR
Github Connectivity: 
HTTP Connectivity: $github_http_reachable

END
)

  echo "$REPORT" > $OUTPUT_FILE
}


main() {
  echo "System Check for Black Duck Software Hub version $HUB_VERSION"
  check_user
  check_ulimits
  _SetOSName
  check_selinux_status
  get_cpu_info
  check_cpu_count
  get_mem_info
  get_disk_info
  get_processes
  
  check_entropy
  check_ports
  is_docker_present
  get_docker_version
  check_docker_compose_installed
  find_docker_compose_version
  check_docker_systemctl_status
  check_docker_images
  check_docker_processes
  inspect_docker_networks
  inspect_docker_volumes
  inspect_docker_swarms

  # Ram check must happen after AWS check and after swarm check
  # since those effect required ram
  check_sufficient_ram  

  check_firewalld
  check_iptables
  check_kb_reachable
  check_reg_server_reachable
  check_doc_server_reachable
  check_docker_hub_reachable
  check_github_reachable
  generate_report
} 

main
