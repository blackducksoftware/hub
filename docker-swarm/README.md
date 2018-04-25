# Running Hub in Docker (Using Docker Swarm)

This is the bundle for running with Docker Swarm. 

## Important Upgrade Announcement
 
Customers upgrading from a version prior to 4.2, will need to perform a data migration as part of their upgrade process.  A high level description of the upgrade is located in the Important _Upgrade_Announcement.md file in the root directory of this package.  Detailed instructions to perform the data migration are located in the “Migrating Hub database data” listed below.

## Contents

Here are the descriptions of the files in this distribution:

1. docker-compose.yml - This is the swarm services file. 
2. docker-compose.dbmigrate.yml - Swarm services file *used one time only* for migrating DB data from another Hub instance.
3. docker-compose.externaldb.yml - Swarm services file to start Hub using an external PostgreSQL instance.
4. hub-webserver.env - This contains an env. entry to set the host name of the main server so that the certificate name will match.
5. hub-proxy.env - This file container environment settings to to setup the proxy.
6. hub-postgres.env - Contains database connection parameters when using an external PostgreSQL instance.

## Requirements

See the main README for software and hardware requirements.

## Restrictions

There are two general restrictions when using Hub in Docker Swarm. 

1. It is required that the PostgreSQL DB always runs on the same node so that data is not lost (hub-database service).
2. It is required that the hub-webapp service and the hub-logstash service run on the same host.

The second requirement is there so that the hub web app can access the logs to be downloaded.
There is a possibility that network volume mounts can overcome these limitations, but this has not been tested.
The performance of PostgreSQL might degrade if a network volume is used. This has also not been tested.

## Migrating Hub database data

----

It is necessary to migrate Hub data in the following scenarios:

1. A Hub deployment is being migrated from an AppMgr managed deployment to a Docker managed deployment.
2. A Hub deployment is being migrated from different Docker managed versions of Hub and a PostgreSQL version upgrade is included.  For example, upgrading
from a Hub version that uses PostgreSQL 9.4.x to another Hub version that uses PostgreSQL 9.6.x requires migration.

This section will describe the process of migrating Hub database data in these instances.

NOTE: Before running this restore process it's important that only a subset of the containers are initially started to ensure a proper migration.
Read through the migration sections below to completion before attempting the migration process.

### Prerequisites

Before beginning the database migration, a PostgreSQL dump file is needed that contains the data from the previous versioned Hub instance.  Different steps are required for creating the initial PostgreSQL dump file depending upon whether updating from an AppMgr managed version of Hub or a Docker managed version of Hub.

#### Creating the PostgreSQL dump file from Hub on AppMgr

A PostgreSQL dump file can be created from the Hub instance installed with AppMgr.   This can be done using tools on the Hub server itself.

Instructions can be found in the Hub install guide in Chapter 4, Installing the Hub AppMgr.

#### Creating the PostgreSQL dump file from Hub on Docker

A PostgreSQL dump file must be created from the previous versioned Hub instance installed with Docker.  This can be done using tools provided on the Docker host
along with a previous versioned and running 'hub-postgres' Docker container.

The following script can be executed against a previous versioned and running 'hub-postgres' Docker container from the Docker host:

```
./bin/hub_create_data_dump.sh <local_postgresql_dump_file_path>
```

This script creates a PostgreSQL dump file in the 'hub-postgres' container and then copies the dump file from the container to the local PostgreSQL dump file path.

### Restoring the Data

----

#### Starting PostgreSQL for data restoration

A migration-specific Docker compose file is required for the PostgreSQL data restore process.   This brings up a subset of Hub Docker containers for the migration process.

The following command can be executed:

```
docker stack deploy -c docker-compose.dbmigrate.yml hub
```

Once the operation is complete, the subset of Hub Docker containers will be up and the data can be restored.

There are some versions of docker where if the images live in a private repository, docker stack will not pull
them unless this flag is added to the command above:

```
--with-registry-auth
```

#### Restoring the PostgreSQL data

The previously created PostgreSQL dump file can now be used to restore data to the current version of Hub.

The following script can be executed against the current versioned and running 'hub-postgres' Docker container from the Docker host:

```
./bin/hub_db_migrate.sh <local_postgresql_dump_file_path>
```

This script restores a local PostgreSQL dump file into the running PostgreSQL instance within the Docker container.   When complete, the existing, running Hub Docker
containers can be stopped and the full compose file can be used to bring up the full Hub Docker deployment.

##### Possible Errors

When an dump file is restored from an AppMgr version of Hub, you might see a couple of errors like:

```
 ERROR:  role "blckdck" does not exist
```

Along with a few surrounding errors. At the end of the migration you might also see:

```
WARNING: errors ignored on restore: 7
```

This is OK and should not affect the data restoration.

### Removing the Services

```
docker stack rm hub
```

## Running 

Note: These command might require being run as either a root user, a user in the docker group, or with 'sudo'.

```
docker stack deploy -c docker-compose.yml hub 
```

There are some versions of docker where if the images live in a private repository, docker stack will not pull
them unless this flag is added to the command above:

```
--with-registry-auth
```

## Running with External PostgreSQL

Hub can be run using a PostgreSQL instance other than the provided hub-postgres docker image.

```
docker stack deploy -c docker-compose.externaldb.yml hub 
```

This assumes that the external PostgreSQL instance has already been configured (see External PostgreSQL Settings below).

## Changing Default Memory Limits

There are a few containers that could require higher than default memory limits depending on the load place on Hub.
The default memory limits should never be decreased, this will cause Hub to not function correctly.

Here is how to update each of the container memory limits that might require higher settings:

### Changing the default Web App Memory Limits

There are three memory settings for this container. The first is the max java heap size. This is controlled by setting the
environment variable: HUB_MAX_MEMORY. The second and third are the limit that docker will use to schedule the limit the overall 
memory of the container. These settings are: reservations memory and limits memory. The setting for each of these memory
values must be higher than the max Java heap size. If updating the Java heap size we recommend setting the memory values to at 
least 1GB higher than the max heap size. Both of these memory values should be set to the same value.

This example will change the max java heap size for the webapp container to 4GB and the mem_limit to
5GB. In the 'docker-compose.yml' or 'docker-compose.externaldb.yml' that you are using, edit these lines
under the 'webapp' service description:

Original:

```
    environment: {HUB_MAX_MEMORY: 2048m}
    deploy:
      mode: replicated
      restart_policy: {condition: on-failure, delay: 5s, window: 60s}
      resources:
        limits: {cpus: '1', memory: 2560M}
        reservations: {cpus: '1', memory: 2560M}
```

Updated:

```
    environment: {HUB_MAX_MEMORY: 4096m}
    deploy:
      mode: replicated
      restart_policy: {condition: on-failure, delay: 5s, window: 60s}
      resources:
        limits: {cpus: '1', memory: 5120M}
        reservations: {cpus: '1', memory: 5120M}

```

### Changing the default Scan Service Memory Limits

There are three main memory settings to consider for this container - Maximum Java heap size, the Docker memory limit, and 
the Docker memory reservation.  The Docker memory limit and Docker memory reservation must be higher than the maximum Java 
heap size.  If updating the maximum Java heap size, it is recommended to set the Docker memory limit and Docker memory 
reservation values to be at least 1GB higher than the maximum Java heap size.

Note that this will apply to all Scan Services if the Scan Service container is scaled.

The following configuration example will update the maximum Java heap size (HUB_MAX_MEMORY) from 2GB to 4GB.  Note how 
the Docker memory limit and Docker memory reservation configuration values are increased as well.  These configuration values 
can be changed in the 'docker-compose.yml' or 'docker-compose.externaldb.yml' files under the 'scan' service section:

Original:

```
    environment: {HUB_MAX_MEMORY: 2048m}
    deploy:
      mode: replicated
      restart_policy: {condition: on-failure, delay: 5s, window: 60s}
      resources:
        limits: {cpus: '1', memory: 2560M}
        reservations: {cpus: '1', memory: 2560M}
```

Updated:

```
    environment: {HUB_MAX_MEMORY: 4096m}
    deploy:
      mode: replicated
      restart_policy: {condition: on-failure, delay: 5s, window: 60s}
      resources:
        limits: {cpus: '1', memory: 5120M}
        reservations: {cpus: '1', memory: 5120M}
```

### Changing the default Job Runner Memory Limits

There are three main memory settings to consider for this container - Maximum Java heap size, the Docker memory limit, and
the Docker memory reservation.  The Docker memory limit and Docker memory reservation must be higher than the maximum Java
heap size.  If updating the maximum Java heap size, it is recommended to set the Docker memory limit and Docker memory
reservation values to be at least 1GB higher than the maximum Java heap size.

Note that this will apply to all Job Runners if the Job Runner container is scaled.

The following configuration example will update the maximum Java heap size (HUB_MAX_MEMORY) from 4GB to 8GB.  Note how
the Docker memory limit and Docker memory reservation configuration values are increased as well.  These configuration values
can be changed in the 'docker-compose.yml' or 'docker-compose.externaldb.yml' files under the 'jobrunner' service section:

Original:

```
    environment: {HUB_MAX_MEMORY: 4096m}
    deploy:
      mode: replicated
      restart_policy: {condition: on-failure, delay: 5s, window: 60s}
      resources:
        limits: {cpus: '1', memory: 4608M}
        reservations: {cpus: '1', memory: 4608M}
```

Updated:

```
    environment: {HUB_MAX_MEMORY: 8192m}
    deploy:
      mode: replicated
      restart_policy: {condition: on-failure, delay: 5s, window: 60s}
      resources:
        limits: {cpus: '1', memory: 9216M}
        reservations: {cpus: '1', memory: 9216M}
```

## Configuration

There are a couple of options that can be configured in this compose file. This section will conver these things:

### Web Server Settings

----

#### Host Name Modification

When the web server starts up, if it does not have certificates configured it will generate an HTTPS certificate.

Configuration is needed to tell the web server which real host name it will listening on so that the host names can match. Otherwise the certificate will only have the service name to use as the host name.

To modify the real host name, edit the hub-webserver.env file to update the desired host name value.

#### Port Modification

The web server is configured with a host to container port mapping.  If a port change is desired, the port mapping should be modified along with the associated configuration.

To modify the host port, edit the port mapping as well as the hub-webserver.env file to update the desired host and/or container port value.

If the container port is modified, any healthcheck URL references should also be modified using the updated container port value.

### Proxy Settings

There are currently several containers that need access to services hosted by Black Duck Software:

* authentication
* jobrunner
* registration
* scan
* webapp

If a proxy is required for external internet access you'll need to configure it. 

#### Steps

1. Edit the file hub-proxy.env
2. Add any of the required parameters for your proxy setup

#### Authenticated Proxy Password

There are three methods for specifying a proxy password when using Docker Swarm.

* Add a 'docker secret' called 'HUB_PROXY_PASSWORD_FILE'
* Mount a directory that contains a file called 'HUB_PROXY_PASSWORD_FILE' to /run/secrets (better to use secrets here)
* Specify an environment variable called 'HUB_PROXY_PASSWORD' that contains the proxy password

There are several containers that will require the proxy password:

* authentication
* jobrunner
* registration
* scan
* webapp

#### LDAP Trust Store Password

There are three methods for specifying an LDAP trust store password when using Docker Swarm.

* Add a 'docker secret' called 'LDAP_TRUST_STORE_PASSWORD_FILE'.
* Mount a directory that contains a file called 'LDAP_TRUST_STORE_PASSWORD_FILE' to /run/secrets (better to use secrets here).
* Specify an environment variable called 'LDAP_TRUST_STORE_PASSWORD' that contains the password.

This configuration is only needed when adding a custom Hub web application trust store.

#### Adding the proxy password secret

The proxy password secret will need to be added to the services:

* authentication
* jobrunner
* registration
* scan
* webapp

In each of these service sections, you'll need to add:

```
secrets:
  - HUB_PROXY_PASSWORD_FILE
```

This must be the name of the secret. The name of the secret must also include the stack name. For instance, if your stack is named 'hub' as in the examples about, the secret would be added using:

```
docker secret create hub_HUB_PROXY_PASSWORD_FILE <file containing password>
```

# Connecting to Hub

Once all of the containers for Hub are up the web application for hub will be exposed on port 443 to the docker host. You'll be able to get to hub using:

```
https://hub.example.com/
```

## Using Custom web server certificate-key pair
*For the upgrading users from version < 4.0 : 'hub_webserver_use_custom_cert_key.sh' no longer exists so please follow the updated instruction below if you wish to use the custom webserver certificate.*

Hub allows users to use their own web server certificate-key pairs for establishing ssl connection.

* Create docker secret each called '<stack name>_WEBSERVER_CUSTOM_CERT_FILE' and '<stack name>_WEBSERVER_CUSTOM_KEY_FILE' with the custom certificate and custom key
You can do so by

```
docker secret create <stack name>_WEBSERVER_CUSTOM_CERT_FILE <certificate file>
docker secret create <stack name>_WEBSERVER_CUSTOM_KEY_FILE <key file>
```

For the webserver service, add secrets by
```
secrets:
  - WEBSERVER_CUSTOM_CERT_FILE
  - WEBSERVER_CUSTOM_KEY_FILE
```

# Hub Reporting Database

Hub ships with a reporting database. The database port will be exposed to the docker host for connections to the reporting user and reporting database.

Details:

* Exposed Port: 55436
* Reporting User Name: blackduck_reporter
* Reporting Database: bds_hub_report
* Reporting User Password: initially unset

Before connecting to the reporting database you'll need to set the password for the reporting user. There is a script included in './bin' of the docker-compose directory called 'hub_reportdb_changepassword.sh'. 

To run this script you must:

* Be on the docker host that is running the PostgreSQL database container
* Be able to run 'docker' commands. This might require being 'root' or in the 'docker' group depending on your docker setup.

To run the change password command:

```
./bin/hub_reportdb_changepassword.sh blackduck
```

Where 'blackduck' is the new password. This script can also be used to change the password for the reporting user after it has been set.

Once the password is set you should now be able to connect to the reporting database. An example of this with 'psql' is:

```
psql -U blackduck_reporter -p 55436 -h localhost -W bds_hub_report
```

This should also work for external connections to the database.

# Scaling Hub

The Job Runner and Scan Service containers support scaling.

As an example, the Job Runner container can be scaled using:

```
docker service scale hub_jobrunner=2
```

This example will add a second Job Runner container. It is also possible to remove Job Runners by specifying a lower number than the current number of Job Runners. To return back to a single Job Runner:

```
docker service scale hub_jobrunner=1
```

### External PostgreSQL Settings

The external PostgreSQL instance needs to initialized by creating users, databases, etc., and connection information must be provided to the _hub-webapp_, _hub-authentication_, _hub-scan_, and _hub-jobrunner_ containers.

#### Steps

1. Create a database user named _blackduck_ with admisitrator privileges.  (On Amazon RDS, do this by setting the "Master User" to "blackduck" when creating the RDS instance.)
2. Run the _external-postgres-init.pgsql_ script to create users, databases, etc.; for example,
   ```
   psql -U blackduck -h <hostname> -p <port> -f external_postgres_init.pgsql postgres
   ```
3. Using your preferred PostgreSQL administration tool, set passwords for the *blackduck* and *blackduck_user* database users (which were created by step #2 above).
4. Edit _hub-postgres.env_ to specify database connection parameters.
5. Supply passwords for the _blackduck_ and *blackduck_user* database users through _one_ of the two methods below.

##### Mount files containing the passwords

1. Create a file named 'HUB_POSTGRES_USER_PASSWORD_FILE' with the password for the *blackduck_user* user.
2. Create a file named 'HUB_POSTGRES_ADMIN_PASSWORD_FILE' with the password for the *blackduck* user.
3. Mount the directory containing 'HUB_POSTGRES_USER_PASSWORD_FILE' and 'HUB_POSTGRES_ADMIN_PASSWORD_FILE' to /run/secrets in both the _hub-webapp_, _hub-authentication_, _hub-scan_, and _hub-jobrunner_ containers.

##### Create Docker secrets

The password secrets will need to be added to the services:

* authentication
* jobrunner
* scan
* webapp

In each of these service sections, you'll need to add:

```
secrets:
  - HUB_POSTGRES_USER_PASSWORD_FILE
  - HUB_POSTGRES_ADMIN_PASSWORD_FILE
```

These must be the names of the secrets. The name of each secret must also include the stack name. For instance, if your stack is named 'hub' as in the examples above, the secrets would be added using:

```
docker secret create hub_HUB_POSTGRES_USER_PASSWORD_FILE <file containing password>
docker secret create hub_HUB_POSTGRES_ADMIN_PASSWORD_FILE <file containing password>
```

##### Importing a proxy certificate

Hub allows users to import the proxy certificate to work with the proxy.

* Create docker secret called '<stack name>_HUB_PROXY_CERT_FILE' with the proxy certificate file
You can do so by

```
docker secret create <stack name>_HUB_PROXY_CERT_FILE <certificate file>
```

For each of the services below, add the secret by

* authentication
* jobrunner
* scan
* webapp
* registration

```
secrets:
  - HUB_PROXY_CERT_FILE
```

