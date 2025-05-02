# Black Duck Docker Orchestration Files/Documentation

This repository contains orchestration files and documentation for deploying Black Duck Docker containers.

## Location of Black Duck 2025.1.1 archive:

https://github.com/blackducksoftware/hub/archive/v2025.1.1.tar.gz

NOTE:

Customers upgrading from a version prior to 2018.12.0 will experience a longer than usual upgrade time due to a data migration needed to support new features in
subsequent releases. Upgrade times will depend on the size of the Black Duck database. If you would like to monitor the process of the upgrade, please contact
Black Duck Customer Support for instructions.

Customers upgrading from a version prior to 2022.2.0 will have their PostgreSQL data volume automatically migrated from PostgreSQL 9.6.x to PostgreSQL 11.x.

## Previous Versions

Previous versions of Black Duck orchestration files can be found on the 'releases' page:

https://github.com/blackducksoftware/hub/releases

## Location of Black Duck Docker images:

* https://hub.docker.com/r/blackducksoftware/blackduck-authentication/
* https://hub.docker.com/r/blackducksoftware/blackduck-bomengine/
* https://hub.docker.com/r/blackducksoftware/blackduck-cfssl/
* https://hub.docker.com/r/blackducksoftware/blackduck-documentation/
* https://hub.docker.com/r/blackducksoftware/blackduck-integration
* https://hub.docker.com/r/blackducksoftware/blackduck-jobrunner/
* https://hub.docker.com/r/blackducksoftware/blackduck-logstash/
* https://hub.docker.com/r/blackducksoftware/blackduck-nginx/
* https://hub.docker.com/r/blackducksoftware/blackduck-postgres/
* https://hub.docker.com/r/blackducksoftware/blackduck-postgres-upgrader/
* https://hub.docker.com/r/blackducksoftware/blackduck-postgres-waiter/
* https://hub.docker.com/r/blackducksoftware/blackduck-registration/
* https://hub.docker.com/r/blackducksoftware/blackduck-scan/
* https://hub.docker.com/r/blackducksoftware/blackduck-storage/
* https://hub.docker.com/r/blackducksoftware/blackduck-webapp/
* https://hub.docker.com/r/blackducksoftware/blackduck-redis/
* https://hub.docker.com/r/blackducksoftware/blackduck-matchengine/
* https://hub.docker.com/r/blackducksoftware/bdba-worker/
* https://hub.docker.com/r/blackducksoftware/rabbitmq/
* https://hub.docker.com/r/blackducksoftware/rl-service/

# Running Black Duck in Docker

Swarm (mode), Kubernetes, and OpenShift are supported as of Black Duck (Hub) 4.2.0. Instructions for running each can be found in the archive bundle:

* docker-swarm - Instructions and files for running Black Duck with 'docker swarm mode'
* kubernetes - Instructions and files for running Black Duck with Kubernetes and OpenShift

## Requirements

* Refer to the Black Duck 'Installing Black Duck Using Docker Swarm' document for complete, up-to-date requirements information for orchestrating Black Duck
  using Docker Swarm.
* Refer to the Black Duck 'Installing Black Duck Using Kubernetes' document for complete, up-to-date requirements information for orchestrating Black Duck using
  Kubernetes.
* Refer to the Black Duck 'Installing Black Duck Using OpenShift' document for complete, up-to-date requirements information for orchestrating Black Duck using
  OpenShift.


