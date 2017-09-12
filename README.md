# Hub Docker Orchestration Files/Documentation

This repository will contain orchestration files and documentation for using the collection of Docker containers that make up Black Duck Hub . 
At the moment only the archives of the orchestration/documentation will be added here. Over the next releases the actual 
content will also live here.

## Location of hub-docker 4.1.2 archive: 

https://github.com/blackducksoftware/hub/raw/master/archives/hub-docker-4.1.2.tar

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

Currently, Swarm, Compose, and run are supported.  Support for Kubernetes and OpenShift will be availab. Inle in 4.2.0.  Instructions for running each can be found in the archive bundle.

## Requirements

### Docker Version Requirements

Hub has been tested with Docker17.03.x (ce/ee).

### Hardware Requirements

This is the minimum hardware that is needed to run a single instance of each container. The sections below document the individual requirements for each container if they will be running on different machines or if more than one instance of a container will be run (right now only Job Runners support this)

* 4 CPUs
* 16 GB RAM (or 15GB if you're constrained running on AWS or other cloud providers)
