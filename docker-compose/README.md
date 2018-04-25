# Running Hub in Docker (Using Docker Compose)

This is the bundle for running with Docker Compose. 

## Important Upgrade Announcement
 
Customers upgrading from a version prior to 4.2, will need to perform a data migration as part of their upgrade process.  A high level description of the upgrade is located in the Important _Upgrade_Announcement.md file in the root directory of this package.  Detailed instructions to perform the data migration are located in the “Migrating Hub database data” listed below.

## Contents

Here are the descriptions of the files in this distribution:

1. docker-compose.yml - This is the primary docker-compose file.
2. docker-compose.dbmigrate.yml - Docker-compose file *used one time only* for migrating DB data from another Hub instance.
3. docker-compose.externaldb.yml - Docker-compose file to start Hub using an external PostgreSQL instance.
4. hub-webserver.env - This contains an env. entry to set the host name of the main server so that the certificate name will match as well as port definitions.
5. hub-proxy.env - This file container environment settings to to setup the proxy.
6. hub-postgres.env - Contains database connection parameters when using an external PostgreSQL instance.

## Requirements

See the main README for software and hardware requirements.

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

Before beginning the database migration, a PostgreSQL dump file is needed that contains the data from the previous versioned Hub instance.  Different steps 
are required for creating the initial PostgreSQL dump file depending upon whether updating from an AppMgr managed version of Hub or a Docker managed version 
of Hub.

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
docker-compose -f docker-compose.dbmigrate.yml -p hub up -d 
```

Once the operation is complete, the subset of Hub Docker containers will be up and the data can be restored.

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

#### Stopping the Containers

```
docker-compose -f docker-compose.dbmigrate.yml -p hub stop
```

## Running 

Note: These command might require being run as either a root user, a user in the docker group, or with 'sudo'.

```
docker-compose -f docker-compose.yml -p hub up -d 
```

## Running with External PostgreSQL

Hub can be run using a PostgreSQL instance other than the provided hub-postgres docker image.

```
     $ docker-compose -f docker-compose.externaldb.yml -p hub up -d 
```

This assumes that the external PostgreSQL instance has already been configured (see External PostgreSQL Settings below).

## Changing Default Memory Limits

There are a few containers that could require higher than default memory limits depending on the load place on Hub.
The default memory limits should never be decreased, this will cause Hub to not function correctly.

Here is how to update each of the container memory limits that might require higher settings:

### Changing the default Web App Memory Limits

There are two memory settings for this container. The first is the max java heap size. This is controlled by setting the
environment variable: HUB_MAX_MEMORY. The second is the limit that docker will use to schedule the limit the overall 
memory of the container. This is the setting: mem_limit. The setting for mem_limit must be higher than the max Java
heap size. If updating the Java heap size we recommend setting the mem_limit to at least 1GB higher than the max heap 
size.

This example will change the max java heap size for the webapp container to 4GB and the mem_limit to
5GB. In the 'docker-compose.yml' or 'docker-compose.externaldb.yml' that you are using, edit these lines
under the 'webapp' service description:

Original:

```
    environment: {HUB_MAX_MEMORY: 2048m}
    restart: always
    mem_limit: 2560M
```

Updated:

```
    environment: {HUB_MAX_MEMORY: 4096m}
    restart: always
    mem_limit: 5120M
```

### Changing the default Scan Service Memory Limits

There are two main memory settings to consider for this container - Maximum Java heap size and the Docker memory limit.  
The Docker memory limit must be higher than the maximum Java heap size.  If updating the maximum Java heap size, it is 
recommended to set the Docker memory limit to be at least 1GB higher than the maximum Java heap size.

Note that this will apply to all Scan Services if the Scan Service container is scaled.

The following configuration example will update the maximum Java heap size (HUB_MAX_MEMORY) from 2GB to 4GB.  Note how 
the Docker memory limit configuration value (mem_limit) is increased as well.  These configuration values can be changed 
in the 'docker-compose.yml' or 'docker-compose.externaldb.yml' files under the 'scan' service section:

 Original:

 ```
     environment: {HUB_MAX_MEMORY: 2048m}
     restart: always
     mem_limit: 2560M
 ```

 Updated:

 ```
     environment: {HUB_MAX_MEMORY: 4096m}
     restart: always
     mem_limit: 5120M
 ```

### Changing the default Job Runner Memory Limits

There are two main memory settings to consider for this container - Maximum Java heap size and the Docker memory limit.  
The Docker memory limit must be higher than the maximum Java heap size.  If updating the maximum Java heap size, it is 
recommended to set the Docker memory limit to be at least 1GB higher than the maximum Java heap size.

Note that this will apply to all Job Runners if the Job Runner container is scaled.

The following configuration example will update the maximum Java heap size (HUB_MAX_MEMORY) from 4GB to 8GB.  Note how 
the Docker memory limit configuration value (mem_limit) is increased as well.  These configuration values can be changed 
in the 'docker-compose.yml' or 'docker-compose.externaldb.yml' files under the 'jobrunner' service section:

Original:

```
    environment: {HUB_MAX_MEMORY: 4096m}
    restart: always
    mem_limit: 4608M
```

Updated:

```
    environment: {HUB_MAX_MEMORY: 8192m}
    restart: always
    mem_limit: 9216M
```

## Configuration

There are a couple of options that can be configured in this compose file. This section will convert these things:

Note: Any of the steps below will require the containers to be restarted before the changes take effect.

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

There are two methods for specifying a proxy password when using Docker Compose.

* Mount a directory that contains a text file called 'HUB_PROXY_PASSWORD_FILE' to /run/secrets 
* Specify an environment variable called 'HUB_PROXY_PASSWORD' that contains the proxy password

There are several services that will require the proxy password:

* authentication
* jobrunner
* registration
* scan
* webapp

#### Importing proxy certificate

* Mount a directory that contains a text file called 'HUB_PROXY_CERT_FILE' to /run/secrets
For each of the services mentioned above, add the secret by adding a volume mount string in docker-compose.yml,
such that for each services's volume section looks as follow.

```
service:
    image: blackducksoftware/hub-service:<hub_version>
    ...
    volumes: ['/directory/where/the/cert-folder/is:/run/secrets']
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
5. Create a file named 'HUB_POSTGRES_USER_PASSWORD_FILE' with the password for the *blackduck_user* user.
6. Create a file named 'HUB_POSTGRES_ADMIN_PASSWORD_FILE' with the password for the *blackduck* user.
7. Mount the directory containing 'HUB_POSTGRES_USER_PASSWORD_FILE' and 'HUB_POSTGRES_ADMIN_PASSWORD_FILE' to /run/secrets in both the _hub-webapp_, _hub-authentication_, _hub-scan_, and _hub-jobrunner_ containers.

#### Secure LDAP Trust Store Password

There are two methods for specifying an LDAP trust store password when using Docker Compose.

* Mount a directory that contains a text file called 'LDAP_TRUST_STORE_PASSWORD_FILE' to /run/secrets
* Specify an environment variable called 'LDAP_TRUST_STORE_PASSWORD' that contains the LDAP trust store password.

This configuration is only needed when adding a custom Hub web application trust store.

# Connecting to Hub

Once all of the containers for Hub are up the web application for hub will be exposed on port 443 to the docker host. You'll be able to get to hub using:

```
https://hub.example.com/
```

## Using Custom webserver certificate-key pair

* For the upgrading users from version < 4.0 : 'hub_webserver_use_custom_cert_key.sh' no longer exists so please follow the updated instruction below if you wish to use the custom webserver certificate.*

----

Hub allows users to use their own webserver certificate-key pairs for establishing ssl connection.
* Mount a directory that contains the custom certificate and key file each as 'WEBSERVER_CUSTOM_CERT_FILE' and 'WEBSERVER_CUSTOM_KEY_FILE' to /run/secrets 

In your docker-compose.yml, you can mount by adding to the volumes section:

```
webserver:
    image: blackducksoftware/hub-nginx:<hub_version>
    ports: ['443:443']
    env_file: hub-webserver.env
    links: [webapp, cfssl]
    volumes: ['webserver-volume:/opt/blackduck/hub/webserver/security', '/directory/where/the/cert-key/is:/run/secrets']
```

* Start the webserver container

## Hub Reporting Database

----

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
docker-compose -p hub scale jobrunner=2
```

This example will add a second Job Runner container. It is also possible to remove Job Runners by specifying a lower number than the current number of Job Runners. To return back to a single Job Runner:

```
docker-compose -p hub scale jobrunner=1
```

