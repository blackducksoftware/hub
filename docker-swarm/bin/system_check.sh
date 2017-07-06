#!/usr/bin/env bash 

HUB_VERSION=${HUB_VERSION:-4.0.0}
OUTPUT_FILE=${SYSTEM_CHECK_OUTPUT_FILE:-"system_check.txt"}
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

get_mem_info() {
  echo "Checking memory Information..."
  command -v free > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    # Free not available
    MEMORY_INFO="Unable to get memory information - non linux system"
  else
    MEMORY_INFO="`free -h`"
  fi
}

get_disk_info() {
  echo "Checking Disk Information..."
  command -v df > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    DISK_INFO="Unable to get Disk Info - df not present"
  else
    DISK_INFO="`df -h`"
  fi
}

# Check what ports are being listened on currently - may be useful for bind errors
check_ports() {
  echo "Checking Network Ports..."
  command -v netstat > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    listen_ports="Unable to run netstat - cannot list ports being listened on"
  else
    listen_ports=`netstat -ln`
  fi
}


# Check if Docker is installed
is_docker_present() {
  echo "Checking For Docker..."
  command -v docker > /dev/null 2>&1
  if [ $? -eq 0 ] ; then
      docker_installed=TRUE
  else
      docker_installed=FALSE
  fi 

}

# Check the version of docker
get_docker_version() {
  if [ "$docker_installed" == "TRUE" ] ; then
    echo "Checking Docker Version..."
    docker_version=`docker --version`
  fi
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
    firewalld_enabled=FALSE
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
    iptables_https_rules="Unable to Check iptables - iptables not found."
  else
    iptables_https_rules=`iptables --list | grep https`
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

KB_HOST="kb.blackducksoftware.com"
check_kb_reachable() {
  echo "Checking For KB Access... (This takes a while)"

  command -v ping > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    kb_reachable_small="Unable to test KB connectivity - ping not found"
    kb_reachable_large="Unable to test KB connectivity - ping not found"
  else
    # Check Small and large packets separately
    kb_ping_small_data=`ping -c 3 $KB_HOST `
    if [ $? -ne 0 ] ; then 
      kb_reachable_small=FALSE
    else
      kb_reachable_small=TRUE
    fi

    kb_ping_large_data=`ping -c 3 -s 1500 $KB_HOST`
    if [ $? -ne 0 ] ; then 
      kb_reachable_large=FALSE
    else
      kb_reachable_large=TRUE
    fi
  fi
}

REG_HOST="registration.blackducksoftware.com"
check_reg_server_reachable() {
  echo "Checking for Registration Server Access.. (This takes a while)"

  command -v ping > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    reg_reachable_small="Unable to test Registration Server connectivity - ping not found"
    reg_reachable_large="Unable to test Registration Server connectivity - ping not found"
  else
    # Check Small and large packets separately
    reg_ping_small_data=`ping -c 3 $REG_HOST `
    if [ $? -ne 0 ] ; then 
      reg_reachable_small=FALSE
    else
      reg_reachable_small=TRUE
    fi

    reg_ping_large_data=`ping -c 3 -s 1500 $REG_HOST`
    if [ $? -ne 0 ] ; then 
      reg_reachable_large=FALSE
    else
      reg_reachable_large=TRUE
    fi
  fi
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
Hub Version: $HUB_VERSION
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
Memory Info:
$MEMORY_INFO

$SEPARATOR
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

$SEPARATOR
Firewalld:
Firewalld enabled: $firewalld_enabled
Firewalld Active Zones: $firewalld_active_zones
Firewalld All Zones: $firewalld_all_zones 
Firewalld Services: $firewalld_services 

$SEPARATOR
Docker Installed: $docker_installed
Docker Version: $docker_version 
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
Reachable (small data): $kb_reachable_small 
Reachable (large data): $kb_reachable_large
Ping Output (small data): $kb_ping_small_data 
Ping Output (large data): $kb_ping_large_data

$SEPARATOR
Black Duck Registration Connectivity:
Reachable (small data): $reg_reachable_small
Reachable (large data): $reg_reachable_large
Ping Output (small data): $reg_ping_small_data 
Ping Output (large data): $reg_ping_large_data
END
)

  echo "$REPORT" > $OUTPUT_FILE
}


main() {
  check_user
  check_ulimits
  _SetOSName
  check_selinux_status
  get_cpu_info
  get_mem_info
  get_disk_info
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
  check_firewalld
  check_iptables
  check_kb_reachable
  check_reg_server_reachable
  generate_report
} 

main