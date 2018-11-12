# Containers
----

There are fifteen containers that make up the application. Here are quick descriptions for them.


# Web App Container (blackduck-webapp)
----

## Container Description

The web application is the container that all Web/UI/API requests are made against. It will also process any UI requests. The ports for the Web App are not exposed outside of the Docker 
network. There is an NGiNX reverse proxy (mentioned below) will be be exposed outside of the Docker network instead.

## Scalability

There should only be a single instance of this container. It currently cannot be scaled.

## Links/Ports

This container will need to connect to these other containers/services:

* postgres
* solr
* zookeeper
* registration
* logstash
* cfssl

The container will need to expose port 8443 to other containers that will link to it.

## Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that it is useful to have host names set for these containers that are not the default that Docker Compose or Docker Swarm use. These environment variables can be set to override the default host names:

* postgres - $HUB_POSTGRES_HOST
* solr - This should be taken care of by ZooKeeper
* zookeeper - $HUB_ZOOKEEPER_HOST
* registration - $HUB_REGISTRATION_HOST
* logstash - $HUB_LOGSTASH_HOST
* cfssl - $HUB_CFSSL_HOST

## Resources/Constraints

* Default Max Java Heap Size: 2GB
* Container Memory: 2.5GB
* Container CPU: 1cpu

## Users/Groups

This container runs as UID 8080. If the container is started as UID 0 (root) then the user will be switched to UID 8080:root before executing it's main process.
This container is also able to be started as a random UID as long as it is also started within the root group (GID/fsGroup 0).


# Authentication Container (blackduck-authentication)
----

## Container Description

The authentication service is the container that all authentication-related requests are made against.

## Scalability

There should only be a single instance of this container.  It currently cannot be scaled.

## Links/Ports

This container will need to connect to these other containers/services

* postgres
* cfssl
* logstash
* registration
* zookeeper
* webapp

The container will need to expose 8443 to other containers that will links to it.

## Alternate Host Name Environment Variables

* postgres - $HUB_POSTGRES_HOST
* cfssl - $HUB_CFSSL_HOST
* logstash - $HUB_LOGSTASH_HOST
* registration - $HUB_REGISTRATION_HOST
* zookeeper - $HUB_ZOOKEEPER_HOST
* webapp - $HUB_WEBAPP_HOST

## Resources/Constraints

* Default Max Java Heap Size: 512MB
* Container Memory: 1GB
* Container CPU: 1cpu

## Users/Groups

This container runs as UID 100. If the container is started as UID 0 (root) then the user will be switched to UID 100:root before executing it's main process.
This container is also able to be started as a random UID as long as it is also started within the root group (GID/fsGroup 0).


# Scan Container (blackduck-scan)
----

## Container Description

The scan service is the container that all scan data requests are made against.  

## Scalability

This container can be scaled.

## Links/Ports

This container will need to connect to these other containers/services:

* postgres
* zookeeper
* registration
* logstash
* cfssl

This container will need to expose port 8443 to other containers that will link to it.

## Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that it is useful to have host names set for these containers that are not the default that Docker Compose or Docker Swarm use. These environment variables can be set to override the default host names:

* postgres - $HUB_POSTGRES_HOST
* zookeeper - $HUB_ZOOKEEPER_HOST
* registration - $HUB_REGISTRATION_HOST
* logstash - $HUB_LOGSTASH_HOST
* cfssl - $HUB_CFSSL_HOST

## Resources/Constraints

* Default Max Java Heap Size: 2GB
* Container Memory: 2.5GB
* Container CPU: 1cpu

## Users/Groups

This container runs as UID 8080. If the container is started as UID 0 (root) then the user will be switched to UID 8080:root before executing it's main process.
This container is also able to be started as a random UID as long as it is also started within the root group (GID/fsGroup 0).



# Job Runner Container (blackduck-jobrunner)
----

## Container Description

The Job Runners will be the containers that are responsible for all of the application's job running. This includes matching, bom building, reports, data updates, etc. This container will not have any exposed ports. 

## Scalability

This container can be scaled. 

## Links/Ports

This container will need to connect to these other containers/services:

* postgres
* solr
* zookeeper
* registration
* logstash
* cfssl

## Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that any individual service name may be different.  For example:

- You may have an external postgres endpoint which is resolved through a different service name.

To support any such use case, these environment variables can be set to override the default service names:

* postgres - $HUB_POSTGRES_HOST
* solr - This should be taken care of by ZooKeeper
* zookeeper - $HUB_ZOOKEEPER_HOST
* registration - $HUB_REGISTRATION_HOST
* logstash - $HUB_LOGSTASH_HOST
* cfssl - $HUB_CFSSL_HOST

## Resources/Constraints

* Default Max Java Heap Size: 4GB
* Container Memory: 4.5GB
* Container CPU: 1cpu

## Users/Groups

This container runs as UID 100. If the container is started as UID 0 (root) then the user will be switched to UID 100:root before executing it's main process.
This container is also able to be started as a random UID as long as it is also started within the root group (GID/fsGroup 0).


# Solr Container (blackduck-solr)
----

## Container Description

This container will have Apache Solr running within it. There will likely be only a single instance of this container since it is not used very heavily at the moment. This will be running with a configuration of Solr Cloud that will support scaling if the need arises. Solr will expose ports internally to the Docker network, but not outside of the Docker network.

## Scalability

There should only be a single instance of this container. It currently cannot be scaled.

## Links/Ports

This container will need to access to these services:

* zookeeper
* logstash

The container will need to expose port 8983 to other containers that will link to it.

## Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that any individual service name may be different.  For example:

- You may have an external logstash endpoint which is resolved through a different service name.

To support any such use case, these environment variables can be set to override the default service names:

* zookeeper - $HUB_ZOOKEEPER_HOST
* logstash - $HUB_LOGSTASH_HOST

## Resources/Constraints

* Default Max Java Heap Size: 512MB
* Container Memory: 640MB
* Container CPU: unspecified

## Users/Groups

This container runs as UID 8983. If the container is started as UID 0 (root) then the user will be switched to UID 8983:root before executing it's main process.
This container is also able to be started as a random UID as long as it is also started within the root group (GID/fsGroup 0).


# Registration Container (blackduck-registration)
----

## Container Description

The container is a small service that will handle registration requests from the other containers. At periodic intervals this container will connect to the Black Duck Registration Service and obtain registration updates.

## Scalability

There should only be a single instance of this container. It currently cannot be scaled.

## Links/Ports

This container will need to connect to these other containers/services:

* logstash
* cfssl

The container will need to expose port 8443 to other containers that will link to it.

## Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that it is useful to have host names set for these containers that are not the default that Docker Compose or Docker Swarm use. These environment variables can be set to override the default host names:

* logstash - $HUB_LOGSTASH_HOST
* cfssl - $HUB_CFSSL_HOST

## Resources/Constraints

* Default Max Java Heap Size: 512MB
* Container Memory: 640MB
* Container CPU: unspecified

## Users/Groups

This container runs as UID 8080. If the container is started as UID 0 (root) then the user will be switched to UID 8080:root before executing it's main process.
This container is also able to be started as a random UID as long as it is also started within the root group (GID/fsGroup 0).


## DB Container (blackduck-postgres)
----

### Container Description

The DB container will hold the PostgreSQL database. At this point there will be a single instance of this container. This is where all of the application data will be stored. There will likely be two sets of ports for Postgres. One port will be exposed to containers within the Docker network. This is the connection that the application will use. This port will be secured via certificate authentication. There will be a second port that will be exposed outside of the Docker network. This will allow a read-only user to connect via a password set externally. This port and user can be used for reporting and data extraction.

### Scalability

There should only be a single instance of this container. It currently cannot be scaled.

### Links/Ports

This container will need to connect to these other containers/services:

* cfssl
* logstash

The container will need to expose port 5432 to other containers that will link to it.

### Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that any individual service name may be different.  For example:

- You may have an external logstash endpoint for your log sink.

In this case, these environment variables can be used to replace service names.

* logstash - $HUB_LOGSTASH_HOST
* cfssl - $HUB_CFSSL_HOST

### Resources/Constraints

* Default Max Java Heap Size: N/A
* Container Memory: 3GB
* Container CPU: 1cpu

## Users/Groups

This container runs as UID 70. If the container is started as UID 0 (root) then the user will be switched to UID 70:root before executing it's main process.
This container is not able to start with any other user id.


# Documentation Container (blackduck-documentation)
----

## Container Description

The Documentation container will serve documentation for the application.

## Scalability

There should only be a single instance of this container. It currently cannot be scaled.

## Links/Ports
This container will need to connect to these other containers/services:

* logstash
* cfssl

The container will need to expose port 8443 to other containers that will link to it.

## Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that it is useful to have host names set for these containers that are not the default that Docker Compose or Docker Swarm use. These environment variables can be set to override the default host names:

* logstash - $HUB_LOGSTASH_HOST
* cfssl - $HUB_CFSSL_HOST

## Resources/Constraints

* Default Max Java Heap Size: 512MB
* Container Memory: 512MB
* Container CPU: unspecified

## Users/Groups

This container runs as UID 8080. If the container is started as UID 0 (root) then the user will be switched to UID 8080:root before executing it's main process.
This container is also able to be started as a random UID as long as it is also started within the root group (GID/fsGroup 0).


# Web Server Container (blackduck-nginx)
----

## Container Description

The NGiNX container will be a reverse proxy for containers within the application. It will have ports exposed outside of the Docker network. This is the container that will be configured for HTTPS. There will be config volumes here to allow the configuration of HTTPS. 

## Scalability

There should only be a single instance of this container. It currently cannot be scaled.

## Links/Ports

This container will need to connect to these other containers/services:

* cfssl
* webapp
* documentation
* scan
* authentication
* upload cache (if binary analysis is enabled)

This container should expose port 443 outside of the docker network.

## Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that any individual service name may be different.  For example:

- You may have an external cfssl endpoint.

* webapp - $HUB_WEBAPP_HOST
* authentication - $HUB_AUTHENTICATION_HOST
* scan - $HUB_SCAN_HOST
* cfssl - $HUB_CFSSL_HOST
* documentation - $HUB_DOC_HOST
* upload cache - $HUB_UPLOAD_CACHE_HOST

## Resources/Constraints

* Default Max Java Heap Size: N/A
* Container Memory: 512MB
* Container CPU: unspecified

## Users/Groups

This container runs as UID 100. If the container is started as UID 0 (root) then the user will be switched to UID 100:root before executing it's main process.
This container is also able to be started as a random UID as long as it is also started within the root group (GID/fsGroup 0).


# ZooKeeper Container (blackduck-zookeeper)
----

## Container Description

This container will store data for the other containers. It will not need to connect to any other containers. It will expose ports within the Docker network, but not outside the Docker network.

## Scalability

There should only be a single instance of this container. It currently cannot be scaled.

## Links/Ports

This container will need to connect to these other containers/services:

* logstash

The container will need to expose port 2181 to other containers that will link to it.

## Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that any individual service name may be different.  For example, You may have an external logstash endpoint which is resolved through a different service name.

To support any such use case, these environment variables can be set to override the default service names:

* logstash - $HUB_LOGSTASH_HOST

## Resources/Constraints

* Default Max Java Heap Size: 256MB 
* Container Memory: 384MB
* Container CPU: unspecified

## Users/Groups

This container runs as UID 1000. If the container is started as UID 0 (root) then the user will be switched to UID 1000:root before executing it's main process.
This container is also able to be started as a random UID as long as it is also started within the root group (GID/fsGroup 0).


# LogStash  Container (blackduck-logstash)
----

## Container Description

The LogStash container will collect and store logs for all of the containers.

## Scalability

There should only be a single instance of this container. It currently cannot be scaled.

## Links/Ports

The container will need to expose port 5044 to other containers/services that will link to it.

## Resources/Constraints

* Default Max Java Heap Size: 1GB 
* Container Memory: 1GB
* Container CPU: unspecified

## Users/Groups

This container runs as UID 100. If the container is started as UID 0 (root) then the user will be switched to UID 100:root before executing it's main process.
This container is also able to be started as a random UID as long as it is also started within the root group (GID/fsGroup 0).


# CA  Container (blackduck-cfssl)
----

## Container Description

The CA container is currently using cfssl. This is used for certificate generation for postges, nginx, and clients that need to authenticate to postgres.
This container is also used to generate tls certificates for the internal containers that make up the application.

## Scalability

There should only be a single instance of this container. It currently cannot be scaled.

## Links/Ports

The container will need to expose port 8888 to other containers/services that will link to it.

## Resources/Constraints

* Default Max Java Heap Size: N/A
* Container Memory: 512MB
* Container CPU: unspecified

## Users/Groups

This container runs as UID 100. If the container is started as UID 0 (root) then the user will be switched to UID 100:root before executing it's main process.
This container is also able to be started as a random UID as long as it is also started within the root group (GID/fsGroup 0).


# RabbitMQ Container (rabbitmq)
----

## Container Description

This container will be used to facilitate upload information to the binary analysis worker. It will expose ports within the Docker network, but not outside the Docker network.
This container is currently only used if Binary Analysis is enabled.

## Scalability

There should only be a single instance of this container. It currently cannot be scaled.

## Links/Ports

This container will need to connect to these other containers/services:

* cfssl

The container will need to expose port 5671 to other containers that will link to it.

## Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that any individual service name may be different.  For example, You may have an external logstash endpoint which is resolved through a different service name.

To support any such use case, these environment variables can be set to override the default service names:

* cfssl - $HUB_CFSSL_HOST

## Resources/Constraints

* Default Max Java Heap Size: N/A
* Container Memory: 1GB
* Container CPU: unspecified

## Users/Groups

This container runs as UID 100. If the container is started as UID 0 (root) then the user will be switched to UID 100:root before executing it's main process.
This container is also able to be started as a random UID as long as it is also started within the root group (GID/fsGroup 0).


# Upload Cache Container (blackduck-upload-cache)
----

## Container Description

This container will be used to temporarily store uploads for binary analysis. It will expose ports within the Docker network, but not outside the Docker network.
This container is currently only used if Binary Analysis is enabled.

## Scalability

There should only be a single instance of this container. It currently cannot be scaled.

## Links/Ports

This container will need to connect to these other containers/services:

* cfssl
* rabbitmq
* logstash

The container will need to expose ports 9443 and 9444 to other containers that will link to it.

## Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that any individual service name may be different.  For example, You may have an external logstash endpoint which is resolved through a different service name.

To support any such use case, these environment variables can be set to override the default service names:

* cfssl - $HUB_CFSSL_HOST
* logstash - $HUB_LOGSTASH_HOST
* rabbitmq - $RABBIT_MQ_HOST

## Resources/Constraints

* Default Max Java Heap Size: N/A
* Container Memory: 512MB
* Container CPU: unspecified

## Users/Groups

This container runs as UID 100. If the container is started as UID 0 (root) then the user will be switched to UID 100:root before executing it's main process.
This container is also able to be started as a random UID as long as it is also started within the root group (GID/fsGroup 0).


# Binary Analysis Worker Container (appcheck-worker)
----

## Container Description

This container will analyze binary files.
This container is currently only used if Binary Analysis is enabled.

## Scalability

This container can be scaled.

## Links/Ports

This container will need to connect to these other containers/services:

* cfssl
* logstash
* rabbitmq
* webserver

The container will need to expose port 5671 to other containers that will link to it.

## Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that any individual service name may be different.  For example, You may have an external logstash endpoint which is resolved through a different service name.

To support any such use case, these environment variables can be set to override the default service names:

* cfssl - $HUB_CFSSL_HOST
* logstash - $HUB_LOGSTASH_HOST
* rabbitmq - $RABBIT_MQ_HOST
* webserver - $HUB_WEBSERVER_HOST

## Resources/Constraints

* Default Max Java Heap Size: N/A
* Container Memory: 2GB
* Container CPU: 1cpu

## Users/Groups

This container runs as UID 0.
