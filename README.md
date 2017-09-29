# Hub Docker Orchestration Files/Documentation

This repository will contain orchestration files and documentation for using the individual Hub Docker containers. 
At the moment only the archives of the orchestration/documentation will be added here. Over the next releases the actual 
content will also live here.

## Location of hub-docker 4.1.4 archive: 

https://github.com/blackducksoftware/hub/raw/master/archives/hub-docker-4.1.4.tar

## Location of Docker Hub images:

* https://hub.docker.com/r/blackducksoftware/hub-cfssl/ 
* https://hub.docker.com/r/blackducksoftware/hub-webapp/
* https://hub.docker.com/r/blackducksoftware/hub-registration/
* https://hub.docker.com/r/blackducksoftware/hub-solr/
* https://hub.docker.com/r/blackducksoftware/hub-logstash/
* https://hub.docker.com/r/blackducksoftware/hub-postgres/
* https://hub.docker.com/r/blackducksoftware/hub-zookeeper/
* https://hub.docker.com/r/blackducksoftware/hub-jobrunner/
* https://hub.docker.com/r/blackducksoftware/hub-nginx/
* https://hub.docker.com/r/blackducksoftware/hub-documentation/

# Running Hub in Docker

Swarm (mode), Compose, and 'docker run' are supported are supported in Hub 4.1.3. Support for Kubernetes and OpenShift will be available in Hub 4.2.0. Instructions for running each can be found in the archive bundle:

* docker-run - Instructions and files for running Hub with 'docker run'
* docker-swarm - Instructions and files for running Hub with 'docker swarm mode'
* docker-compose - Instructions and files for running Hub with 'docker-compose'

## Requirements

### Docker Version Requirements

Hub has been tested with Docker 17.03.x and Docker 17.06.x.

### Hardware Requirements

This is the minimum hardware that is needed to run a single instance of each container. The sections below document the individual requirements for each container if they will be running on different machines or if more than one instance of a container will be run (right now only Job Runners support this)

* 4 CPUs
* 16 GB RAM (20 GB if using Docker Swarm Mode)
