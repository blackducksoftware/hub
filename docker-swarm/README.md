# Running Black Duck by Synopsys in Docker (Using Docker Swarm)

This is the bundle for running with Docker Swarm. 

## Important Upgrade Announcement
 
Customers upgrading from a version prior to 2018.12.0 will experience a longer than usual upgrade time due to a data migration needed to support new features in this release. Upgrade times will depend on the size of the Black Duck database. If you would like to monitor the process of the upgrade, please contact Synopsys Customer Support for instructions.
 
Customers upgrading from a version prior to 4.2, will need to perform a data migration as part of their upgrade process.  A high level description of the upgrade is located in the Important _Upgrade_Announcement.md file in the root directory of this package.  Detailed instructions to perform the data migration are located in the “Migrating Black Duck database data” listed below.

## Contents

Here are the descriptions of the files in this distribution:

1. docker-compose.yml - This is the swarm services file that includes a Postgresql database container.. 
2. docker-compose.dbmigrate.yml - Swarm services file *used one time only* for migrating DB data from another Black Duck instance.
3. docker-compose.externaldb.yml - Swarm services file to start Black Duck using an external PostgreSQL instance.
4. docker-compose.bdba.yml - Swarm services file to add if you've licensed Binary Analysis.
5. docker-compose.local-overrides.yml - YAML file that overrides any default settings.
6. docker-compose.readonly.yml - YAML file that declares file system as read-only for Swarm services.
7. hub-webserver.env - This contains an env. entry to set the host name of the main server so that the certificate name will match.
8. blackduck-config.env - This file contains general environment settings for all Black Duck containers.
9. hub-postgres.env - Contains database connection parameters when using an external PostgreSQL instance.
10. hub-bdba.env - Contains additional settings for binary analysis. This should not require any modification.


## Requirements

See the main README for software and hardware requirements.

## Restrictions

There are two general restrictions when using Black Duck in Docker Swarm. 

1. It is required that the PostgreSQL DB always runs on the same node so that data is not lost (hub-database service).
2. It is required that the webapp service and the logstash service run on the same host.

The second requirement is there so that the Black Duck webapp can access the logs to be downloaded.
There is a possibility that network volume mounts can overcome these limitations, but this has not been tested.
The performance of PostgreSQL might degrade if a network volume is used. This has also not been tested.

## Migrating Black Duck database data

----

It is necessary to migrate Black Duck data in the following scenarios:

1. A Hub deployment is being migrated from an AppMgr managed deployment to a Docker managed deployment.
2. A Black Duck deployment is being migrated from different Docker managed versions of Black Duck and a PostgreSQL version upgrade is included.  For example, upgrading
from a Black Duck version that uses PostgreSQL 9.4.x to another Black Duck version that uses PostgreSQL 9.6.x requires migration.

This section will describe the process of migrating Black Duck database data in these instances.

NOTE: Before running this restore process it's important that only a subset of the containers are initially started to ensure a proper migration.
Read through the migration sections below to completion before attempting the migration process.

### Prerequisites

Before beginning the database migration, a PostgreSQL dump file is needed that contains the data from the previous versioned Black Duck instance.  Different steps are required for creating the initial PostgreSQL dump file depending upon whether updating from an AppMgr managed version of Black Duck or a Docker managed version of Black Duck.

#### Creating the PostgreSQL dump file from Black Duck on AppMgr

A PostgreSQL dump file can be created from the Black Duck instance installed with AppMgr.   This can be done using tools on the Hub server itself.

Instructions can be found in the Black Duck install guide in Chapter 4, Installing the Black Duck AppMgr.

#### Creating the PostgreSQL dump file from Black Duck on Docker

A PostgreSQL dump file must be created from the previous versioned Black Duck instance installed with Docker.  This can be done using tools provided on the Docker host
along with a previous versioned and running 'hub-postgres' Docker container.

The following script can be executed against a previous versioned and running 'hub-postgres' Docker container from the Docker host:

```
./bin/hub_create_data_dump.sh <local_postgresql_dump_file_path>
```

This script creates a PostgreSQL dump file in the 'hub-postgres' container and then copies the dump file from the container to the local PostgreSQL dump file path.

### Restoring the Data

----

#### Starting PostgreSQL for data restoration

A migration-specific Docker compose file is required for the PostgreSQL data restore process.   This brings up a subset of Black Duck Docker containers for the migration process.

The following command can be executed:

```
docker stack deploy -c docker-compose.dbmigrate.yml hub
```

Once the operation is complete, the subset of Black Duck Docker containers will be up and the data can be restored.

There are some versions of docker where if the images live in a private repository, docker stack will not pull
them unless this flag is added to the command above:

```
--with-registry-auth
```

#### Restoring the PostgreSQL data

The previously created PostgreSQL dump file can now be used to restore data to the current version of Black Duck.

The following script can be executed against the current versioned and running 'hub-postgres' Docker container from the Docker host:

```
./bin/hub_db_migrate.sh <local_postgresql_dump_file_path>
```

This script restores a local PostgreSQL dump file into the running PostgreSQL instance within the Docker container.   When complete, the existing, running Black Duck Docker
containers can be stopped and the full compose file can be used to bring up the full Black Duck Docker deployment.

##### Possible Errors

When an dump file is restored from an AppMgr version of Black Duck, you might see a couple of errors like:

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

ATTENTION: The usage of multiple 'yml' files requires Docker version 18.03 or later.  If you are unable to upgrade
then you may simply use docker-compose to feed Swarm as the example below shows:

```
docker-compose -f docker-compose.yml -f docker-compose.bdba.yml config \
| docker stack deploy -c - hub
```


Note: These command might require being run as either a root user, a user in the docker group, or with 'sudo'.

```
docker stack deploy -c docker-compose.yml hub 
```

There are some versions of docker where if the images live in a private repository, docker stack will not pull
them unless this flag is added to the command above:

```
--with-registry-auth
```

## Supply overrides

If any settings need to be customized, you should add those settings to the docker-compose.local-overrides.yml 
file and supply that as the last yml file entered.

## Running with Binary Analysis Enabled

Note: These command might require being run as either a root user, a user in the docker group, or with 'sudo'.

```
docker stack deploy --compose-file docker-compose.yml -c docker-compose.bdba.yml hub
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

### Binary Analysis with External Postgres

These instructions are the same as above, except the compose file that you should use:

```
docker stack deploy --compose-file docker-compose.externaldb.yml -c docker-compose.bdba.yml hub 
```

## Running with read-only file system

Black Duck can be started with read-only file system and additional persisted volumes.

```
docker stack deploy --compose-file docker-compose.yml -c docker-compose.readonly.yml hub
```

# Overriding defaults

Sometimes it is necessary to override the defaults settings contained within Black Duck by Synopsys.  In order to perserve 
these from version to version a file called "docker-compose.local-overrides.yml" has been provided.  The sections below 
describe how to change this file for a variety of circumstances.  In all cases, this file is appended as the last yml file used
in the docker stack command.  For instance, the "Binary Analysis with External Postgres" command just above would be:

```
     docker stack deploy --compose-file docker-compose.externaldb.yml -c docker-compose.bdba.yml -c docker-compose.local-overrides.yml hub
```


## Changing Default Memory Limits

There are a few containers that could require higher than default memory limits depending on the load placed on Black Duck.
The default memory limits should never be decreased, this will cause Black Duck to not function correctly.

Here is how to update each of the container memory limits that might require higher settings:

### Changing the default Web App Memory Limits

ATTENTION: Any and all changes that override the default behavior should use the docker-compose.local-overrides.yml file.  This file can then be easily ported to subsequent versions.

There are three memory settings for this container. The first is the max java heap size. This is controlled by setting the
environment variable: HUB_MAX_MEMORY. The second and third are the limit that docker will use to schedule the limit the overall 
memory of the container. These settings are: reservations memory and limits memory. The setting for each of these memory
values must be higher than the max Java heap size. If updating the Java heap size we recommend setting the memory values to at 
least 1GB higher than the max heap size. Both of these memory values should be set to the same value.

This example will change the max java heap size for the webapp container to 4GB and the resources to
5GB. These configuration values can be changed in the 'docker-compose.local-overrides.yml' under 
the 'webapp' service section:


Added into webapp service definition:

```
  webapp:
    environment: {HUB_MAX_MEMORY: 4096m}
    deploy:
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
the Docker memory limit and Docker memory reservation configuration values are increased as well.  These configuration values can be changed in the 'docker-compose.local-overrides.yml' under 
the 'scan' service section:

Added definitions:

```
  scan:
    environment: {HUB_MAX_MEMORY: 4096m}
    deploy:
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
the Docker memory limit and Docker memory reservation configuration values are increased as well.  These configuration values can be changed in the 'docker-compose.local-overrides.yml' under the 'jobrunner' service section:

Added definition:

```
  jobrunner:
    environment: {HUB_MAX_MEMORY: 8192m}
    deploy:
      resources:
        limits: {cpus: '1', memory: 9216M}
        reservations: {cpus: '1', memory: 9216M}
```

### Changing the default Binary Scanner Memory Limits

The only default memory size for the Binary Scanner container is the actual memory limit for the container.
Note that this will apply to all Binary Scanners if the Binary Scanner container is scaled.

The following configuration example will update the container memory limits from 2GB to 4GB. These configuration values can be changed 
in the 'docker-compose.local-overrides.yml'  under the 'binaryscanner' service section:


Added definition:

```
  binaryscanner:
    deploy:
      resources:
        limits: {cpus: '1', memory: 4096M}
        reservations: {cpus: '1', memory: 4096M}
```

## Configuration

There are several additional options that can be user-configured. This section describes these:

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
* bomengine
* jobrunner
* registration
* scan
* webapp
* kb

If a proxy is required for external internet access you'll need to configure it. 

#### Steps

1. Edit the file blackduck-config.env
2. Add any of the required parameters for your proxy setup

#### Authenticated Proxy Password

There are three methods for specifying a proxy password when using Docker Swarm.

* Add a 'docker secret' called 'HUB_PROXY_PASSWORD_FILE'
* Mount a directory that contains a file called 'HUB_PROXY_PASSWORD_FILE' to /run/secrets (better to use secrets here)
* Specify an environment variable called 'HUB_PROXY_PASSWORD' that contains the proxy password

There are several containers that will require the proxy password:

* authentication
* bomengine
* jobrunner
* registration
* scan
* webapp
* kb

#### LDAP Trust Store Password

There are two methods for specifying an LDAP trust store password when using Docker Swarm.

* Add a 'docker secret' called 'LDAP_TRUST_STORE_PASSWORD_FILE'.
* Mount a directory that contains a file called 'LDAP_TRUST_STORE_PASSWORD_FILE' to /run/secrets (better to use secrets here).

This configuration is only needed when adding a custom LDAP trust store to the Black Duck authentication service.

#### Adding the proxy password secret

The proxy password secret will need to be added to the services:

* authentication
* bomengine
* jobrunner
* registration
* scan
* webapp
* kb

In each of these service sections, you'll need to add:

```
secrets:
  - HUB_PROXY_PASSWORD_FILE
```

This must be the name of the secret. The name of the secret must also include the stack name. For instance, if your stack is named 'hub' as in the examples about, the secret would be added using:

```
docker secret create hub_HUB_PROXY_PASSWORD_FILE <file containing password>
```

# Connecting to Black Duck

Once all of the containers for Black Duck are up the web application will be exposed on port 443 to the docker host. You'll be able to get to Black Duck using:

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

For the webserver service, add secrets to service definitions within docker-compose.local-overrides.yml by

```
secrets:
  - WEBSERVER_CUSTOM_CERT_FILE
  - WEBSERVER_CUSTOM_KEY_FILE
```

Include the mapping at the bottom of docker-compose.local-overrides.yml:


```
secrets:
  WEBSERVER_CUSTOM_CERT_FILE:
    external:
      name: "hub_WEBSERVER_CUSTOM_CERT_FILE"
  WEBSERVER_CUSTOM_KEY_FILE:
    external:
      name: "hub_WEBSERVER_CUSTOM_KEY_FILE"
```

Finally, point the healthcheck property in the webserver service of docker-compose.local-overrides.yml file to the new certificate from the secret

```
webserver:
         healthcheck:
         test: [CMD, /usr/local/bin/docker-healthcheck.sh,
         'https://localhost:8443/health-checks/liveness',
         /run/secrets/WEBSERVER_CUSTOM_CERT_FILE]
```

## Support certificate authentication using custom CA

----

Black Duck  allows users to use their own CA for the certificate authentication. To enable this, users should add the volume mount to the webserver and the authentication service definitions in the docker-compose.local-overrides.yml file.

```
webserver:
    secrets:
      - AUTH_CUSTOM_CA
    
authentication:
    secrets:
    - AUTH_CUSTOM_CA

```
And define the top level secrets at the bottom of the docker-compose.yml file as:
```
secrets:
  AUTH_CUSTOM_CA:
    file: {path to the custom ca file on host machine}
```

* Start the webserver container, and the authentication service.

* Once the Black Duck services are all up, make an API request which would return the JWT(Json Web Token) with certificate key pair that was signed with the trusted CA. 

For example
```
curl https://localhost:443/jwt/token --cert user.crt --key user.key
```
Note: The username of the certificate used for authentication must exist in the Black Duck system as its _Common Name_.



# Black Duck Reporting Database

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

# Scaling Black Duck

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

The external PostgreSQL instance needs to initialized by creating users, databases, etc., and connection information must be provided to the _authentication_, _bomengine_, _jobrunner_, _scan_, _kb_ and _webapp_ containers.

#### Steps

1. Create a database user named _blackduck_ with administrator privileges.  (On Amazon RDS, do this by setting the "Master User" to "blackduck" when creating the RDS instance.)
2. In the script 'external-postgres-init.pgsql', replace 'POSTGRESQL_USER' with 'blackduck', replace 'HUB_POSTGRES_USER' with 'blackduck_user', and replace 'BLACKDUCK_USER_PASSWORD' with password you want to use for 'blackduck_user'
   ```bash
   export POSTGRESQL_USER=blackduck && export HUB_POSTGRES_USER=blackduck_user && export BLACKDUCK_USER_PASSWORD=CHANGEME123
   sed 's|POSTGRESQL_USER|'$POSTGRESQL_USER'|g; s|HUB_POSTGRES_USER|'$HUB_POSTGRES_USER'|g; s|BLACKDUCK_USER_PASSWORD|'$BLACKDUCK_USER_PASSWORD'|g' external-postgres-init.pgsql > external-postgres-init.pgsql
   ``` 
3. Run the modified _external-postgres-init.pgsql_ script to create users, databases, etc.; for example,
   ```
   psql -U blackduck -h <hostname> -p <port> -f external_postgres_init.pgsql postgres
   ```
4. Using your preferred PostgreSQL administration tool, set passwords for the *blackduck* and *blackduck_user* database users (which were created by step #2 above).
5. Edit _hub-postgres.env_ to specify database connection parameters.
6. Supply passwords for the _blackduck_ and *blackduck_user* database users through _one_ of the two methods below.

##### Mount files containing the passwords

1. Create a file named 'HUB_POSTGRES_USER_PASSWORD_FILE' with the password for the *blackduck_user* user.
2. Create a file named 'HUB_POSTGRES_ADMIN_PASSWORD_FILE' with the password for the *blackduck* user.
3. Mount the directory containing 'HUB_POSTGRES_USER_PASSWORD_FILE' and 'HUB_POSTGRES_ADMIN_PASSWORD_FILE' to /run/secrets in _authentication_, _bomengine_, _jobrunner_, _scan_, _kb_ and _webapp_ containers.

##### Create Docker secrets

The password secrets will need to be added to the services:

* authentication
* bomengine
* jobrunner
* scan
* webapp
* kb

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
* bomengine
* jobrunner
* scan
* webapp
* registration
* kb

```
secrets:
  - HUB_PROXY_CERT_FILE
```

# Source Upload Feature 

Source side by side view feature is included in 2019.04 release. In order to enable the feature, there are two steps need to be done before the deployment.

**1. The flag in blackduck-config.env should be set to true.** 
```
ENABLE_SOURCE_UPLOADS=true
```
**2. Seal Key creation.**

When source files are uploaded, they are stored encrypted in the container (upload cache service). 

Black Duck requires customers to provide their own seal key which is 32 bytes long in order to support the AES-256 encryption. And the seal key needs to be provided to the upload cache service. 

Under the uploadcache service configuration in docker-compose.yml, provide the location where you keep the file.

```
uploadcache:
    secrets:
      - SEAL_KEY
```
And define the top level secrets at the bottom of the docker-compose.yml file as:
```
secrets:
  SEAL_KEY:
   external: true
   name: "hub_SEAL_KEY"
```

**NOTE: If the seal key isn't provided, the source side by side view feature won't be available in Black Duck**


### Key recovery support

The upload cache service encrypts the file data with a root key. The root key is generated at the very first start of the application.
The key can only be retrieved with the seal key, thus the encrypted data cannot be decrypted when the seal key isn't available.

To protect the loss of file data, Black Duck supports the key recovery on demand. If customer wishes to retrieve the root key, they can do so by running the script as below.
The script requires two arguments, local destination where you wish to store the root key (**please make sure to place it in a secure location**) and a path where you keep the seal key.

```
./bin/bd_get_source_upload_master_key.sh <local_destination_directory_path> <seal_key_file_path>
```
