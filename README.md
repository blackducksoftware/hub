# Black Duck Docker Orchestration Files/Documentation

This repository contains orchestration files and documentation for deploying Black Duck Docker containers. 

## Location of Black Duck 2019.4.2 archive:

https://github.com/blackducksoftware/hub/archive/v2019.4.2.tar.gz

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

Black Duck supports the following orchestration environments:

* Docker 17.09.x
* Docker 17.12.x
* Docker 18.03.x
* Docker 18.06.x
* Docker 18.09.x
* Kubernetes 1.6
* Kubernetes 1.7
* Kubernetes 1.8
* Kubernetes 1.9
* Kubernetes 1.10
* Red Hat OpenShift Container Platform 3.6
* Red Hat OpenShift Container Platform 3.7
* Red Hat OpenShift Container Platform 3.8
* Red Hat OpenShift Container Platform 3.9
* Red Hat OpenShift Container Platform 3.10

### Minimum Hardware Requirements

This is the minimum hardware that is needed to run a single instance of each container. The sections below document the individual requirements for each container if they will be running on different machines or if more than one instance of a container will be run (right now only Job Runners support this).

For Docker Compose:
* 4 CPUs
* 16 GB RAM

For Docker Swarm, Kubernetes, and OpenShift:
* 5 CPUs
* 20 GB RAM

Please note there that these are the minimum hardware requirements. These will likely need to be increased with larger or multiple concurrent scans.

Also, for Swarm, Kubernetes and OpenShift, note that these requirements are only for Black Duck itself and do not include other resources that are required to run the cluster overall.

### Additional Resources when Binary Scanning is Enabled

There are variations of the orchestration files that will add additional containers for use in Binary Scanning. If these additional containers
are added, then the following additional resources would be required:

* 1 CPU
* 4 GB RAM
