# Running Hub in Docker

There are currently three supported ways to run Hub in Docker: Docker Compose, Docker Swarm, and Docker Run. Instructions for running each can be found in:

* docker-compose - Instructions and files for running with Docker Compose
* docker-swarm - Instructions and files for running with Docker Swarm
* docker-run - Instructions for how to use only 'docker run' without any other orchestration

To get started, pick one of those directories and follow the README you'll find there.

## Requirements

### Docker Version Requirements

Hub has been tested with Docker 17.03.x (ce/ee). 

### Hardware Requirements

This is the minimum hardware that is needed to run a single instance of each container. The sections below document the individual requirements for each container if they will be running on different machines or if more than one instance of a container will be run (right now only Job Runners support this)

* 4 CPUs
* 16 GB RAM (or 15GB if you're constrained running on AWS or other cloud providers)

