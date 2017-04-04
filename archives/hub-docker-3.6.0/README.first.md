# Running Hub in Docker

There are currently only docker compose Docker swarm and docker run will be coming soon. Instructions for running each can be found in:

* docker-compose - Instructions and files for running with Docker Compose

## Requirements

### Docker Version Requirements

Hub has been tested with Docker 1.13.1. 

### Hardware Requirements

This is the minimum hardware that is needed to run a single instance of each container. The sections below document the individual requirements for each container if they will be running on different machines or if more than one instance of a container will be run (right now only Job Runners support this)

* 4 cpus
* 16 GB RAM (or 15GB if you're constrained running on AWS or other cloud providers)

