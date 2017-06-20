# Running Hub in Docker (Using Docker Swarm)

This is the bundle for running with Docker Swarm. 

## Contents

Here are the descriptions of the files in this distribution:

1. docker-compose.yml - This is the swarm services file. 
2. hub-webserver.env - This contains an env. entry to set the host name of the main server so that the certificate name will match.
3. hub-proxy.env - This file container environment settings to to setup the proxy.

## Requirements

Hub has been tested on Docker 17.03.x (ce/ee). 

## Restrictions

There are two general restrictions when using Hub in Docker Swarm. 

1. It is required that the PostgreSQL DB always runs on the same node so that data is not lost (hub-database service).
2. It is required that the hub-webapp service and the hub-logstash service run on the same host.

The second requirement is there so that the hub web app can access the logs to be downloaded.
There is a possibility that network volume mounts can overcome these limitations, but this has not been tested.
The performance of PostgreSQL might degrade if a network volume is used. This has also not been tested.

# Migrating DB Data from Hub/AppMgr

This section will describe the process of migrating DB data from a Hub instance installed with AppMgr to this new version of Hub. There are a couple of steps.

NOTE: Before running this restore process it's important that only a subset of the containers are initially started. Sections below will walk you through this.

## Prerequisites

Before beginning the database migration, you'll need to have a PostgreSQL Dump file containing the data from the previous Hub instance.

### Making the PostgreSQL Dump File from an AppMgr Installation

These instructions require being on the same server that the Hub in installed.
Instructions can be found in the Hub install guide in Chapter 4, Installing the Hub AppMgr.

### Making the PostgreSQL Dump File from an an Existing Hub Container

To make a PostgreSQL dump file from an existing Hub PostgreSQL container, you can use this command:

```
docker exec -it <containerid or name> pg_dump -U blackduck -Fc -f /tmp/bds_hub.dump bds_hub
```

### Copying the Dump out of a Container

If you're using the single-container AppMgr Hub, or if you're making a dump file for an existing 
Hub Container, you can copy the dump file out by using 'docker cp':

```
docker cp <containerid>:<path to dump file in container> .
```

## Restoring the Data

### Starting PostgreSQL

There is a separate compose file that will start PostgreSQL for this restore process. You can run this:

```
docker stack deploy -c docker-compose.dbmigrate.yml hub 
```

Once this has brought up the DB container the next step is to restore the data.

There are some versions of docker where if the images live in a private repository, docker stack will not pull
them unless this flag is added to the command above:

```
--with-registry-auth
```

### Restoring the DB Data

Once the data has been restored, the rest of the services can be brought up using the commands from 
the 'Running' section below, the services that are currently running do not need to be stopped or removed.

There is a script in './bin' that will restore the data from an existing DB Dump file.

```
./bin/hub_db_migrate.sh <path to dump file>
```

Once you run this, you'll be able to stop the existing containers and then run the full compose file.

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

## Configuration

There are a couple of options that can be configured in this compose file. This section will convert these things:

Note: Any of the steps below will require the containers to be restarted before the changes take effect.

### Web Server Settings

When the web server starts up, if it does not have certificates configured it will generate an HTTPS certificate. Configuration is needed to tell the web server which real host name it will listening on so that the host names can match. Otherwise the certificate will use localhost as the host name.

#### Steps

1. Edit the hub-webserver.env file to fill in the host name

### Proxy Settings

There are currently three containers that need access to services hosted by Black Duck Software:

* registration
* jobrunner
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

There are the services that will require the proxy password:

* webapp
* registration
* jobrunner

#### Adding the password secret

The password secret will need to be added to the services:

* webapp
* registration
* jobrunner

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

Hub allows users to use their own web server certificate-key pairs for establishing ssl connection.
You could do it in either way.

### If you already have the web server container running
 
#### Steps

1. Run the tool bin/hub_webserver_use_custom_cert_key.sh with custom certificate and key files. 

Example:

``` 
./hub_webserver_use_custom_cert_key cert.crt key.key
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

The Job Runner in the only service that is scalable. Job Runners can be scaled using:

```
docker service scale hub_jobrunner=2
```

This example will add a second Job Runner container. It is also possible to remove Job Runners by specifying a lower number than the current number of Job Runners. To return back to a single Job Runner:

```
docker service scale hub_jobrunner=1
```
