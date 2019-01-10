# Black Duck Docker Orchestration Files/Documentation

This repository will contain orchestration files and documentation for using the individual Black Duck Docker containers. 

## Location of Black Duck 2018.12.1 archive:

https://github.com/blackducksoftware/hub/archive/v2018.12.1.tar.gz

## Important Upgrade Announcement

Customers upgrading from a version prior to 2018.12.0 will experience a longer than usual upgrade time due to a data migration needed to support new features in this release. Upgrade times will depend on the size of the Black Duck database. If you would like to monitor the process of the upgrade, please contact Synopsys Customer Support for instructions.
 
Customers upgrading from a version prior to 4.2, will need to perform a data migration as part of their upgrade process.  A high level description of the upgrade is located in the Important_Upgrade_Announcement.md file in the root directory of this package.  Detailed instructions to perform the migration located in the individual README.md doc file in the directory for the each orchestration method folder.

## Previous Versions

Previous versions of Black Duck orchestration files can be found on the 'releases' page:

https://github.com/blackducksoftware/hub/releases

## Location of Black Duck Docker images:

* https://hub.docker.com/r/blackducksoftware/blackduck-authentication/
* https://hub.docker.com/r/blackducksoftware/blackduck-cfssl/ 
* https://hub.docker.com/r/blackducksoftware/blackduck-documentation/
* https://hub.docker.com/r/blackducksoftware/blackduck-jobrunner/
* https://hub.docker.com/r/blackducksoftware/blackduck-logstash/
* https://hub.docker.com/r/blackducksoftware/blackduck-nginx/
* https://hub.docker.com/r/blackducksoftware/blackduck-postgres/
* https://hub.docker.com/r/blackducksoftware/blackduck-registration/
* https://hub.docker.com/r/blackducksoftware/blackduck-scan/
* https://hub.docker.com/r/blackducksoftware/blackduck-solr/
* https://hub.docker.com/r/blackducksoftware/blackduck-webapp/
* https://hub.docker.com/r/blackducksoftware/blackduck-zookeeper/
* https://hub.docker.com/r/blackducksoftware/blackduck-upload-cache/
* https://hub.docker.com/r/blackducksoftware/appcheck-worker/
* https://hub.docker.com/r/blackducksoftware/rabbitmq/

# Running Black Duck in Docker

Swarm (mode), Compose, Kubernetes, and OpenShift are supported as of Black Duck (Hub) 4.2.0. Instructions for running each can be found in the archive bundle:

* docker-swarm - Instructions and files for running Black Duck with 'docker swarm mode'
* docker-compose - Instructions and files for running Black Duck with 'docker-compose'
* kubernetes - Instructions and files for running Black Duck with Kubernetes and OpenShift

## Requirements

### Orchestration Version Requirements

Black Duck will be supported on the following orchestrations:

* Docker 17.09.x
* Docker 17.12.x
* Docker 18.03.x
* Docker 18.06.x
* Docker 18.09.x
* Kubernetes 1.6
* Kubernetes 1.7
* Kubernetes 1.8
* Kubernetes 1.9
* RedHat Open Container Platform 3.6
* RedHat Open Container Platform 3.7
* RedHat Open Container Platform 3.8
* RedHat Open Container Platform 3.9

### Minimum Hardware Requirements (for Docker Compose)

This is the minimum hardware that is needed to run a single instance of each container. The sections below document the individual requirements for each container if they will be running on different machines or if more than one instance of a container will be run (right now only Job Runners support this).

* 4 CPUs
* 16 GB RAM

Please note there that these are the minimum hardware requirements. These will likely need to be increased with larger or multiple concurrent scans.

### Minimum Hardware Requirements (for Docker Swarm, Kubernetes, and OpenShift)

This is the minimum hardware that is needed to run a single instance of each container. The sections below document the individual requirements for each container if they will be running on different machines or if more than one instance of a container will be run (right now only Job Runners support this).

* 5 CPUs
* 20 GB RAM

Also note that these requirements are for Black Duck and do not include other resources that are required to run the cluster overall.
Please note there that these are the minimum hardware requirements. These will likely need to be increased with larger or multiple concurrent scans.

### Additional Resources when Binary Scanning is Enabled

There are variations of the orchestration files that will add in additional containers for use in Binary Scanning. If these additional containers
are added in then they will require additional resources:

* 1 CPU
* 4 GB RAM
