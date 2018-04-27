# Hub Docker Orchestration Files/Documentation

This repository will contain orchestration files and documentation for using the individual Hub Docker containers. 

## Location of hub 4.6.1 archive: 

https://github.com/blackducksoftware/hub/archive/v4.6.1.tar.gz

## Important Upgrade Announcement
 
Customers upgrading from a version prior to 4.2, will need to perform a data migration as part of their upgrade process.  A high level description of the upgrade is located in the Important_Upgrade_Announcement.md file in the root directory of this package.  Detailed instructions to perform the migration located in the individual README.md doc file in the directory for the each orchestration method folder.

## Previous Versions

Previous versions of Hub orchestration files can be found on the 'releases' page:

https://github.com/blackducksoftware/hub/releases

## Location of Docker Hub images:

* https://hub.docker.com/r/blackducksoftware/hub-authentication/
* https://hub.docker.com/r/blackducksoftware/hub-cfssl/ 
* https://hub.docker.com/r/blackducksoftware/hub-documentation/
* https://hub.docker.com/r/blackducksoftware/hub-jobrunner/
* https://hub.docker.com/r/blackducksoftware/hub-logstash/
* https://hub.docker.com/r/blackducksoftware/hub-nginx/
* https://hub.docker.com/r/blackducksoftware/hub-postgres/
* https://hub.docker.com/r/blackducksoftware/hub-registration/
* https://hub.docker.com/r/blackducksoftware/hub-scan/
* https://hub.docker.com/r/blackducksoftware/hub-solr/
* https://hub.docker.com/r/blackducksoftware/hub-webapp/
* https://hub.docker.com/r/blackducksoftware/hub-zookeeper/

# Running Hub in Docker

Swarm (mode), Compose, Kubernetes, and OpenShift are supported are supported in Hub 4.2.0. Instructions for running each can be found in the archive bundle:

* docker-swarm - Instructions and files for running Hub with 'docker swarm mode'
* docker-compose - Instructions and files for running Hub with 'docker-compose'
* kubernetes - Instructions and files for running Hub with Kubernetes
* openshift - Instructions and files for running Hub with OpenShift

## Requirements

### Orchestration Version Requirements

Hub will be supported on the following orchestrations:

* Docker 17.06.x
* Docker 17.09.x
* Docker 17.12.x
* Docker 18.03.x
* Kubernetes 1.6
* Kubernetes 1.7
* Kubernetes 1.8
* Kubernetes 1.9
* RedHat Open Container Platform 3.6
* RedHat Open Container Platform 3.7
* RedHat Open Container Platform 3.8
* RedHat Open Container Platform 3.9

### Minumum Hardware Requirements (for Docker Compose)

This is the minimum hardware that is needed to run a single instance of each container. The sections below document the individual requirements for each container if they will be running on different machines or if more than one instance of a container will be run (right now only Job Runners support this).

* 4 CPUs
* 16 GB RAM

Please note there that these are the minimum hardware requirements. These will likely need to be increased with larger or multiple concurrent scans.

### Minimum Hardware Requirements (for Docker Swarm, Kubernetes, and OpenShift)

This is the minimum hardware that is needed to run a single instance of each container. The sections below document the individual requirements for each container if they will be running on different machines or if more than one instance of a container will be run (right now only Job Runners support this).

* 5 CPUs
* 20 GB RAM

Also note that these requirements are for Hub and do not include other resources that are required to run the cluster overall.
Please note there that these are the minimum hardware requirements. These will likely need to be increased with larger or multiple concurrent scans.


