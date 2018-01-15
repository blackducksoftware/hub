#!/usr/bin/env bash

HUB_VERSION=${HUB_VERSION:-4.4.0}
TIMESTAMP=`date`
YEAR=`echo $TIMESTAMP | awk -F' ' '{print $6}'`
MONTH=`echo $TIMESTAMP | awk -F' ' '{print $2}'`
DAY_OF_MONTH=`echo $TIMESTAMP | awk -F' ' '{print $3}'`
TIME_OF_DAY=`echo $TIMESTAMP | awk -F' ' '{print $4}'`
HR=`echo $TIME_OF_DAY | awk -F':' '{print $1}'`
MIN=`echo $TIME_OF_DAY | awk -F':' '{print $2}'`
SEC=`echo $TIME_OF_DAY | awk -F':' '{print $3}'`
OUTPUT_FILE=${SYSTEM_CHECK_OUTPUT_FILE:-"system_check_${YEAR}_${MONTH}_${DAY_OF_MONTH}_${HR}_${MIN}_${SEC}.txt"}
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
  ignored_user_prompt=FALSE
  id=`id -u`
  current_username=`id -un`
  if [ "$id" -ne 0 ] ; then
    echo "This script must be run as root for all features to work."
    
    echo "This script will gather a reduced set of information if run this way, but you will likely "
    echo "be asked by BlackDuck support to re-run the script with root privileges."
    echo -n "Are you sure you wish to proceed as a non-privileged user? [y/N]: "
    read proceed
    proceed_upper=`echo $proceed | awk '{print toupper($0)}'`
    if [ "$proceed_upper" != "Y" ] ; then 
      exit -1
    fi
    is_root=FALSE
    ignored_user_prompt=TRUE
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

get_package_list() { 
  if [ "$IS_LINUX" != "TRUE" ] ; then 
    PKG_LIST="Cannot retrieve package list - non linux system"
    return;
  fi

  PKG_LIST="Cannot Retrieve Package List - Could not determine package manager"

  # RPM - rpm -qa
  command -v rpm > /dev/null 2>&1
  if [ $? -eq 0 ] ; then
    PKG_LIST=`rpm -qa`
    return;
  fi

  # APT - apt list --installed
  command -v apt > /dev/null 2>&1
  if [ $? -eq 0 ] ; then
    PKG_LIST=`apt list --installed`
    return;
  fi

  # DPKG - dpkg --get-selections | grep -v deinstall
  command -v dpkg > /dev/null 2>&1
  if [ $? -eq 0 ] ; then
    PKG_LIST=`dpkg --get-selections | grep -v deinstall`
    return;
  fi


}

get_interface_info() { 
  
  echo "Checking Network interface configuration..."
  command -v ifconfig > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    ifconfig_data="Unable to run ifconfig - cannot list network interface configuration"
  else
    ifconfig_data=`ifconfig -a`
  fi

}

get_routing_info() { 
  echo "Checking Routing Table..."
  if [ "$IS_LINUX" != "TRUE" ] ; then 
      routing_table="Unable to check routing table - Non Linux System"
      return
  fi
  
  routing_table=`ip route list`
}

get_bridge_info() { 
  echo "Checking Network Bridge Information..."
  if [ "$IS_LINUX" != "TRUE" ] ; then 
    brctl_info="Unable to get Network Bridge Information, non-linux system."
    return
  fi

  command -v brctl > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    brctl_info="Unable to get Network Bridge Information, bridge-utils not installed."
    return
  fi

  brctl_info=`brctl show`

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
    bd_docker_images="Cannot list docker images without root access."
    docker_image_inspection="Cannot inspect docker images without root access."
    return
  fi

  echo "Checking Docker Images Present..."

  if [ "$docker_installed" == "TRUE" ] ; then
    bd_docker_images=`docker images | awk -F' ' '{printf("%-80s%-80s\n",$1,$2);}' | sort`
    docker_image_inspection=`docker image ls -aq | xargs docker image inspect`
  else
    bd_docker_images="Docker not installed, no images present."
    docker_image_inspection="Docker not installed, no images present."
  fi
}

check_docker_containers() { 
  if [ "$is_root" == "FALSE" ] ; then 
    bd_docker_containers="Cannot list docker containers without root access"
    container_diff_report="Cannot inspect docker containers without root access"
    return
  fi

  if [ "$docker_installed" == "TRUE" ] ; then
    bd_docker_containers=`docker container ls`
  else
    bd_docker_containers="Docker Not installed, no containers present."
    container_diff_report="Docker Not installed, no containers present."
    return
  fi
  echo "Checking Docker Containers and Taking Diffs..."
  container_ids=`docker container ls -aq`

  container_diff_report=$(
  while read -r cur_container_id ; 
    do
      echo "------------------------------------------"  
      docker container ls -a | grep "$cur_container_id" | awk -F' ' '{printf("%-20s%-80s\n",$1,$2);}'
      docker inspect "$cur_container_id"
      docker container diff "$cur_container_id"

    done <<< "$container_ids"
  )
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
    echo "Skipping IP Tables Check (Root access required)"
    iptables_https_rules="Cannot check iptables https rules without root access"
    iptables_all_rules="Cannot check iptables https rules without root access"
    iptables_db_rules="Cannot check iptables https rules without root access"
    iptables_nat_rules="Cannot check iptables https rules without root access"
    return
  fi

  echo "Checking IP Tables Rules..."

  command -v iptables > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    iptables_all_rules="Unable to Check iptables - iptables not found."
    iptables_https_rules="Unable to Check iptables - iptables not found."
    iptables_db_rules="Unable to Check iptables - iptables not found."
    iptables_nat_rules="Unable to Check iptables - iptables not found."
  else
    iptables_https_rules=`iptables --list | grep https`
    iptables_db_rules=`iptables --list | grep '55436'`
    iptables_all_rules=`iptables --list -v`
    iptables_nat_rules=`iptables -t nat -L -v`
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
    echo "Checking Ping Connectivity from Docker Host to ${label} via small packet ping... (this takes time)"
    eval "$small_data_key=\"`ping -c 3 -s $ping_small_packet_size $hostname`\""
    if [ $? -ne 0 ] ; then 
      eval "$small_result_key=\"FALSE\""
    else
      eval "$small_result_key=\"TRUE\""
    fi

    echo "Checking Ping Connectivity from Docker Host to ${label} via large packet ping... (this takes time)"
    eval "$large_data_key=\"`ping -c 3 -s $ping_large_packet_size $hostname`\""
    if [ $? -ne 0 ] ; then 
      eval "$large_result_key=\"FALSE\""
    else
      eval "$large_result_key=\"TRUE\""
    fi
  fi
}

# Helper method to ping a host within a docker container.
# A small (64 byte) and large (1500 byte)
# ping attempt will be made
# Parameters:
#   $1 - Container ID to Execute the ping on
#   $2 - Hostname to ping
#  
#  example: 
#  ping_host 111111111 kb.blackducksoftware.com
#
#  This function just echos Reachable: TRUE/FALSE to stdout, it is intended to be used in a subshell
#  The output of ping is also included.
#
docker_ping_host() { 

  if [ "$#" -lt "2" ] ; then 
    echo "docker_ping_host: too few parameters."
    echo "usage: ping_host <container id> <hostname>"
    exit -1
  fi

  container_id=$1
  hostname=$2
  
  ping_missing_message="Unable to test $label connectivity - ping not found"
  ping_small_packet_size=56
  ping_large_packet_size=1492

    # Check Small and large packets separately
    echo ""
    docker exec -u root:root -i $container_id ping -c 3 -s $ping_small_packet_size $hostname
    echo ""
    if [ $? -ne 0 ] ; then 
      echo "$hostname Reachable (small data): FALSE"
    else
      echo "$hostname Reachable (small data): TRUE"
    fi

    echo ""

    docker exec -u root:root -i $container_id ping -c 3 -s $ping_large_packet_size $hostname
    echo ""
    if [ $? -ne 0 ] ; then 
      echo "$hostname Reachable (large data): FALSE"
    else
      echo "$hostname Reachable (large data): TRUE"
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
docker_curl_url() { 
  if [ "$#" -lt "2" ] ; then 
    echo "curl_host: too few parameters."
    echo "usage: curl_host <container> <url>"
    exit -1
  fi

  local container=$1
  local url=$2  
  
  docker exec -u root:root -it $container curl -s -o /dev/null $url > /dev/null 2>&1
  if [ $? -ne 0 ] ; then 
    echo "FALSE"
  else
    echo "TRUE"
  fi
}

# Curls a URL from each of the docker containers and stores all the results in a single easily
# discovered variable
curl_via_all_containers() { 

  if [ "$#" -lt "2" ] ; then 
    echo "curl_via_all_containers: too few parameters."
    echo "usage: curl_via_all_containers <url> <key>"
    exit -1
  fi

  local url=$1  
  local key=$2
  local final_var_name="${key}_container_curl_report"

  if [ "$is_root" == "FALSE" ] ; then 
    echo "Skipping curl via docker containers, root access required."
    container_curl_report="Cannot curl via docker containers, root access required."
    eval $final_var_name="\"$container_curl_report\""
    return
  fi

  if [ "$docker_installed" != "TRUE" ] ; then
    echo "Skipping curl via docker containers, docker is not installed."
    container_curl_report="Cannot curl via docker containers, docker is not installed."
    eval $final_var_name="\"$container_curl_report\""
    return
  fi

  echo "Checking HTTP Connectivity from within docker containers to ${url} ... "
  # Only running containers
  container_ids="$(docker container ls -q)"
  
  container_curl_report=$(
  for cur_container_id in $container_ids
  do
    echo "------------------------------------------"  
    docker container ls -a | grep "$cur_container_id" | awk -F' ' '{printf("%-20s%-80s\n",$1,$2);}'
    echo -n "HTTP Connectivity to ${url}  : "
    docker_curl_url $cur_container_id $url      
    echo ""
  done
  )

  eval $final_var_name="\"${container_curl_report}\""
}


# Pings a host from each of the docker containers and stores all the results in a single easily
# discovered variable
ping_via_all_containers() { 

  if [ "$#" -lt "2" ] ; then 
    echo "ping_via_all_containers: too few parameters."
    echo "usage: ping_via_all_containers <hostname> <key>"
    exit -1
  fi

  local hostname=$1
  local key=$2

  if [ "$is_root" == "FALSE" ] ; then 
    echo "Skipping ping via docker containers, root access required."
    container_ping_report="Cannot ping via docker containers, root access required."
    return
  fi

  if [ "$docker_installed" != "TRUE" ] ; then
    echo "Skipping ping via docker containers, docker is not installed."
    container_ping_report="Cannot ping via docker containers, docker is not installed."
    return
  fi

  echo "Checking Ping Connectivity from within Docker containers to ${hostname} ..."
  # Only running containers
  local container_ids="$(docker container ls -q)"
  
  local container_ping_report=$(
  for cur_container_id in $container_ids
  do
    echo "------------------------------------------"  
    docker container ls -a | grep "$cur_container_id" | awk -F' ' '{printf("%-20s%-80s\n",$1,$2);}'
    echo "Ping results: "
    docker_ping_host $cur_container_id $hostname      
  done
  )

  final_var_name="${key}_container_ping_report"
  eval "$final_var_name=\"$container_ping_report\""

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
    echo "Checking HTTP connectivity from Docker Host to ${label} ... (this takes time)"
    
    curl -s -o /dev/null $url
    if [ $? -ne 0 ] ; then 
      eval "$reachable_key=\"FALSE\""
    else
      eval "$reachable_key=\"TRUE\""
    fi

  fi
}

tracepath_host() { 
  if [ "$#" -lt "3" ] ; then 
    echo "curl_host: too few parameters."
    echo "usage: tracepath_host <url> <key> <label>"
    exit -1
  fi

  host=$1
  key=$2
  label=$3
  reachable_key=${key}_tracepath_reachable
  results_key=${key}_tracepath_result
  tracepath_missing_message="Cannot attempt to trace path to $label, tracepath & traceroute both missing"
  tracepath_found=FALSE

  command -v tracepath > /dev/null 2>&1
  if [ $? -eq 0 ] ; then 
    tracepath_found=TRUE
    tracepath_cmd="tracepath"
  fi

  if [ "$tracepath_found" == "FALSE" ] ; then 
    command -v traceroute > /dev/null 2>&1
    if [ $? -eq 0 ] ; then 
      tracepath_found=TRUE
      tracepath_cmd="traceroute -m 12"
    fi
  fi

  if [ "$tracepath_found" == "FALSE" ] ; then
    eval "$reachable_key=FALSE"
    eval "$results_key=$tracepath_missing_message"
  else
    echo "Tracing path from Docker Host to ${label} ... (this takes time)"
    
    eval "$results_key=\"`$tracepath_cmd $host`\""
    if [ $? -ne 0 ] ; then 
      eval "$reachable_key=\"FALSE\""      
    else
      eval "$reachable_key=\"TRUE\""

    fi
  fi
}


KB_HOST="kb.blackducksoftware.com"
KB_URL="https://$KB_HOST/"
check_kb_reachable() {
  ping_host "$KB_HOST" "kb" "$KB_HOST"
  ping_via_all_containers "$KB_HOST" "kb"
  tracepath_host "$KB_HOST" "kb" "Black Duck KB"
  curl_url "$KB_URL" "kb" "$KB_URL"
  curl_via_all_containers "$KB_URL" "kb"  

}


REG_HOST="updates.blackducksoftware.com"
REG_URL="https://$REG_HOST/"
check_reg_server_reachable() {
  ping_host "$REG_HOST" "reg" "$REG_HOST"
  ping_via_all_containers "$REG_HOST" "reg"
  tracepath_host "$REG_HOST" "reg" "Black Duck Registration"
  curl_url "$REG_URL" "reg" "$REG_URL"  
  curl_via_all_containers "$REG_URL" "reg"
}

DOCKER_HOST="hub.docker.com"
DOCKER_URL="https://${DOCKER_HOST}/u/blackducksoftware/"
check_docker_hub_reachable() {
  tracepath_host "$DOCKER_HOST" "docker" "docker"
  curl_url "$DOCKER_URL" "docker_hub" "$DOCKER_URL"
  curl_via_all_containers "$DOCKER_URL" "docker_hub"
}

DOCKERIO_HOST="registry-1.docker.io"
DOCKERIO_URL="https://${DOCKERIO_HOST}/"
check_dockerio_reachable() { 
  tracepath_host "$DOCKERIO_HOST" "dockerio" "dockerio"
  curl_url "$DOCKERIO_URL" "dockerio" "$DOCKERIO_URL"
  curl_via_all_containers "$DOCKERIO_URL" "dockerio"
}

DOCKERIO_AUTH_HOST="auth.docker.io"
DOCKERIO_AUTH_URL="https://${DOCKERIO_AUTH_HOST}/"
check_dockerio_auth_reachable() { 
  tracepath_host "$DOCKERIO_AUTH_HOST" "dockerioauth" "dockerioauth"
  curl_url "$DOCKERIO_AUTH_URL" "dockerioauth" "$DOCKERIO_AUTH_URL"
  curl_via_all_containers "$DOCKERIO_AUTH_URL" "dockerioauth"
}

GITHUB_HOST="github.com"
GITHUB_URL="https://${GITHUB_HOST}/blackducksoftware/hub/raw/master/archives/"
check_github_reachable() {
  tracepath_host "$GITHUB_HOST" "github" "github"
  curl_url "$GITHUB_URL" "github" "$GITHUB_URL"
  curl_via_all_containers "$GITHUB_URL" "github"
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
Package List:
$PKG_LIST

$SEPARATOR
Current user: $current_username
Ignored Prompt about User Privileges: $ignored_user_prompt
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
Network Interface Configuration:
$ifconfig_data

$SEPARATOR
Routing Table:
$routing_table

$SEPARATOR
Network Bridge Info:
$brctl_info

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

IP Tables NAT Rules:
$iptables_nat_rules

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
Docker Image Details:
$docker_image_inspection

$SEPARATOR
Docker Containers Present w/Diffs:
$container_diff_report

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

Trace Path Result: $kb_tracepath_reachable
Trace Path Output: $kb_tracepath_result

Ping Connectivity to Black Duck KB via Docker Containers:
$kb_container_ping_report

HTTP Connectivity to Black Duck KB via Docker Containers:
$kb_container_curl_report

$SEPARATOR
Black Duck Registration Connectivity:
HTTP Connectivity: $reg_http_reachable
Reachable via Ping (small data): $reg_reachable_small
Reachable via Ping (large data): $reg_reachable_large
Ping Output (small data): $reg_ping_small_data 
Ping Output (large data): $reg_ping_large_data

Trace Path Result: $reg_tracepath_reachable
Trace Path Output: $reg_tracepath_result

Connectivity to Black Duck Registration via Docker Containers:
$reg_container_ping_report

HTTP Connectivity to Black Duck Registration via Docker Containers:
$reg_container_curl_report

$SEPARATOR
Docker Hub Connectivity: 

Trace Path Result: $docker_tracepath_reachable
Trace Path Output: $docker_tracepath_result

HTTP Connectivity: $docker_hub_http_reachable

HTTP Connectivity to Docker Hub via Docker Containers:
$docker_hub_container_curl_report

$SEPARATOR
Docker IO Registry:

Trace Path Result: $dockerio_tracepath_reachable
Trace Path Output: $dockerio_tracepath_result

HTTP Connectivity: $dockerio_http_reachable

HTTP Connectivity to Docker IO Registry via Docker Containers:
$dockerio_container_curl_report

$SEPARATOR
Docker IO Auth: 

Trace Path Result: dockerioauth_tracepath_reachable
Trace Path Output: $dockerioauth_tracepath_result

HTTP Connectivity: $dockerioauth_http_reachable

HTTP Connectivity to Docker IO Auth Server via Docker Containers:
$dockerioauth_container_curl_report

$SEPARATOR
Github Connectivity: 

Trace Path Result: $github_tracepath_reachable
Trace Path Output: $github_tracepath_result

HTTP Connectivity: $github_http_reachable

HTTP Connectivity to Github via Docker Containers:
$github_container_curl_report

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
  get_package_list
  
  check_entropy
  get_interface_info
  get_routing_info
  get_bridge_info
  check_ports
  is_docker_present
  get_docker_version
  check_docker_compose_installed
  find_docker_compose_version
  check_docker_systemctl_status
  check_docker_images
  check_docker_containers
  check_docker_processes
  inspect_docker_networks
  inspect_docker_volumes
  inspect_docker_swarms

  # Ram check must happen after AWS check and after swarm check
  # since those effect required ram
  check_sufficient_ram  

  check_firewalld
  check_iptables

  #Black Duck Sites that need to be checked
  check_kb_reachable
  check_reg_server_reachable
  
  #External sites that need to be checked
  check_docker_hub_reachable
  check_dockerio_reachable
  check_dockerio_auth_reachable
  check_github_reachable
  
  generate_report
} 

main
