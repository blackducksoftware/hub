# Containers

There are twelve containers that make up the Hub application. Here are quick descriptions for them.

## Web App Container (hub-webapp)

### Container Description

The Hub web application is the container that all Web/UI/API requests are made against. It will also process any UI requests. In the diagram above, the ports for the Hub Web App are not exposed outside of the Docker network. There is an NGinNX reverse proxy (mentioned below) will be be exposed outside of the Docker network instead.

### Scalability

There should only be a single instance of this container. It currently cannot be scaled.

### Links/Ports

This container will need to connect to these other containers/services:

* postgres
* solr
* zookeeper
* registration
* logstash
* cfssl

The container will need to expose port 8443 to other containers that will link to it.

### Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that it is useful to have host names set for these containers that are not the default that Docker Compose or Docker Swarm use. These environment variables can be set to override the default host names:

* postgres - $HUB_POSTGRES_HOST
* solr - This should be taken care of by ZooKeeper
* zookeeper - $HUB_ZOOKEEPER_HOST
* registration - $HUB_REGISTRATION_HOST
* logstash - $HUB_LOGSTASH_HOST
* cfssl - $HUB_CFSSL_HOST

### Constraints

* Default Max Java Heap Size: 2GB
* Container Memory: 2.5GB
* Container CPU: 1cpu

# Authentication Container (hub-authentication)

### Container Description

The Hub authentication service is the container that all authentication-related requests are made against.

### Scalability

There should only be a single instance of this container.  It currently cannot be scaled.

### Links/Ports

This container will need to connect to these other containers/services

* postgres
* cfssl
* logstash
* registration
* zookeeper
* webapp

The container will need to expose 8443 to other containers that will links to it.

### Alternate Host Name Environment Variables

* postgres - $HUB_POSTGRES_HOST
* cfssl - $HUB_CFSSL_HOST
* logstash - $HUB_LOGSTASH_HOST
* registration - $HUB_REGISTRATION_HOST
* zookeeper - $HUB_ZOOKEEPER_HOST
* webapp - $HUB_WEBAPP_HOST

### Constraints

* Default Max Java Heap Size: 512MB
* Container Memory: 1GB
* Container CPU: 1cpu

# Scan Container (hub-scan)

### Container Description

The Hub scan service is the container that all scan data requests are made against.  

### Scalability

This container can be scaled.

### Links/Ports

This container will need to connect to these other containers/services:

* postgres
* zookeeper
* registration
* logstash
* cfssl

This container will need to expose port 8443 to other containers that will link to it.

### Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that it is useful to have host names set for these containers that are not the default that Docker Compose or Docker Swarm use. These environment variables can be set to override the default host names:

* postgres - $HUB_POSTGRES_HOST
* zookeeper - $HUB_ZOOKEEPER_HOST
* registration - $HUB_REGISTRATION_HOST
* logstash - $HUB_LOGSTASH_HOST
* cfssl - $HUB_CFSSL_HOST

### Constraints

* Default Max Java Heap Size: 2GB
* Container Memory: 2.5GB
* Container CPU: 1cpu

## Job Runner App Container (hub-jobrunner)

### Container Description

The Job Runners will be the containers that are responsible for all of the Hub's job running. This includes matching, bom building, reports, data updates, etc. This container will not have any exposed ports. 

### Scalability

This container can be scaled. 

### Links/Ports

This container will need to connect to these other containers/services:

* postgres
* solr
* zookeeper
* registration
* logstash
* cfssl

### Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that any individual service name may be different.  For example:

- You may have an external postgres endpoint which is resolved through a different service name.

To support any such use case, these environment variables can be set to override the default service names:

* postgres - $HUB_POSTGRES_HOST
* solr - This should be taken care of by ZooKeeper
* zookeeper - $HUB_ZOOKEEPER_HOST
* registration - $HUB_REGISTRATION_HOST
* logstash - $HUB_LOGSTASH_HOST
* cfssl - $HUB_CFSSL_HOST

### Constraints

* Default Max Java Heap Size: 4GB
* Container Memory: 4GB
* Container CPU: 1cpu

## Solr Container (hub-solr)

### Container Description

This container will have Apache Solr running within it. There will likely be only a single instance of this container since it is not used very heavily at the moment. This will be running with a configuration of Solr Cloud that will support scaling if the need arises. Solr will expose ports internally to the Docker network, but not outside of the Docker network.

### Scalability

There should only be a single instance of this container. It currently cannot be scaled.

### Links/Ports

This container will need to access to these services:

* zookeeper
* logstash

The container will need to expose port 8443 to other containers that will link to it.

### Alternate Host Name Environment Variables


There are times when running in other types of orchestrations that any individual service name may be different.  For example:

- You may have an external logstash endpoint which is resolved through a different service name.

To support any such use case, these environment variables can be set to override the default service names:

* zookeeper - $HUB_ZOOKEEPER_HOST
* logstash - $HUB_LOGSTASH_HOST

### Constraints

* Default Max Java Heap Size: 512MB
* Container Memory: 512MB
* Container CPU: unspecified

## Registration Container (hub-registration)

### Container Description

The container is a small service that will handle registration requests from the other containers. At periodic intervals this container will connect to the Black Duck Registration Service and obtain registration updates.

### Scalability

There should only be a single instance of this container. It currently cannot be scaled.

### Links/Ports

This container will need to connect to these other containers/services:

* logstash

The container will need to expose port 8443 to other containers that will link to it.

### Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that it is useful to have host names set for these containers that are not the default that Docker Compose or Docker Swarm use. These environment variables can be set to override the default host names:

* logstash - $HUB_LOGSTASH_HOST

### Constraints

* Default Max Java Heap Size: 256MB
* Container Memory: 256MB
* Container CPU: unspecified

## DB Container (hub-postgres)

### Container Description

The DB container will hold the PostgreSQL database. At this point there will be a single instance of this container. This is where all of the Hub data will be stored. There will likely be two sets of ports for Postgres. One port will be exposed to containers within the Docker network. This is the connection that the Hub App, Job Runner, and potentially other containers will use. This port will be secured via certificate authentication. There will be a second port that will be exposed outside of the Docker network. This will allow a read-only user to connect via a password set externally. This port and user can be used for reporting and data extraction.

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

### Constraints

* Default Max Java Heap Size: N/A
* Container Memory: 3GB
* Container CPU: 1cpu

## Documentation Container (hub-documentation)

### Container Description

The Documentation container will serve a documentation for Hub.

### Scalability

There should only be a single instance of this container. It currently cannot be scaled.

### Links/Ports
This container will need to connect to these other containers/services:

* logstash

The container will need to expose port 8443 to other containers that will link to it.

### Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that it is useful to have host names set for these containers that are not the default that Docker Compose or Docker Swarm use. These environment variables can be set to override the default host names:

* logstash - $HUB_LOGSTASH_HOST

### Constraints

* Default Max Java Heap Size: 512MB
* Container Memory: 512MB
* Container CPU: unspecified

## Web Server Container (hub-nginx)

### Container Description

The NGiNX container will be a reverse proxy for the Hub Web App. It will have ports exposed outside of the Docker network. This is the container that will be configured for HTTPS. There will be config volumes here to allow the configuration of HTTPS. 

### Scalability

There should only be a single instance of this container. It currently cannot be scaled.

### Links/Ports

This container will need to connect to these other containers/services:

* cfssl
* webapp
* documentation
* scan
* authentication

This container should expose port 443 outside of the docker network.

### Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that any individual service name may be different.  For example:

- You may have an external cfssl endpoint.

* webapp - $HUB_WEBAPP_HOST
* authentication - $HUB_AUTHENTICATION_HOST
* scan - $HUB_SCAN_HOST
* cfssl - $HUB_CFSSL_HOST
* documentation - $HUB_DOC_HOST

### Constraints

* Default Max Java Heap Size: N/A
* Container Memory: 512MB
* Container CPU: unspecified

## ZooKeeper  Container (hub-zookeeper)

### Container Description

This container will store data for the Hub App, Job Runners, Solr, and potentially other containers. It will not need to connect to any other containers. It will expose ports within the Docker network, but not outside the Docker network.

### Scalability

There should only be a single instance of this container. It currently cannot be scaled.

### Links/Ports

This container will need to connect to these other containers/services:

* logstash

The container will need to expose port 2181 to other containers that will link to it.

### Alternate Host Name Environment Variables

There are times when running in other types of orchestrations that any individual service name may be different.  For example, You may have an external logstash endpoint which is resolved through a different service name.

To support any such use case, these environment variables can be set to override the default service names:

* logstash - $HUB_LOGSTASH_HOST

### Constraints

* Default Max Java Heap Size: 256MB 
* Container Memory: 256MB
* Container CPU: unspecified

## LogStash  Container (hub-logstash)

### Container Description

The LogStash container will collect and store logs for all of the containers.

### Scalability

There should only be a single instance of this container. It currently cannot be scaled.

### Links/Ports

The container will need to expose port 5044 to other containers/services that will link to it.

### Constraints

* Default Max Java Heap Size: 1GB 
* Container Memory: 1GB
* Container CPU: unspecified

## CA  Container (hub-cfssl)

### Container Description

The CA container is currently using cfssl. This is used for certificate generation for postges, nginx, and clients that need to authenticate to postgres.

### Scalability

There should only be a single instance of this container. It currently cannot be scaled.

### Links/Ports

The container will need to expose port 8888 to other containers/services that will link to it.

### Constraints

* Default Max Java Heap Size: N/A
* Container Memory: 512MB
* Container CPU: unspecified
