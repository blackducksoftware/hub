# Running Hub in Docker (Using Docker Compose)

This is the bundle for running with Docker Compose. 

## Contents

Here are the descriptions of the files in this distribution:

1. docker-compose.yml - This is the docker-compose file. 
2. hub-webserver.env - This contains an env. entry to set the host name of the main server so that the certificate name will match.
3. hub-proxy.env - This file container envvironment settings to to setup the proxy.

## Requirements

Hub has been tested on Docker 1.13.1. The minumum version of docker-compose to use this bundle must be able to read Docker Compose 2.1 files.

# Migrating DB Data from Hub/AppMgr

This section will describe the process of migrating DB data from a Hub instance installed with AppMgr to this new version of Hub. There are a couple of steps.

NOTE: Before running this restore process it's important that only a subset of the containers are initially started. Sections below will walk you through this.

## Prerequisites

Before beginning the database migration, you'll need to have a PosgteSQL Dump file containing the data from the previous Hub instance.

### Making the Postgre Dump File from an AppMgr Installation

These instructions require being on the same server that the Hub in installed.
Instructions can be found in the Hub install guide in Chapter 4, Installing the Hub AppMgr.

## Restoring the Data

### Starting Postgres

There is a separate compose file that will start postgres for this restore process. You can run this:

```
docker-compose -f docker-compose.dbmigrate.yml -p hub up -d 
```

Once this has brought up the DB container the next step is to restore the data.

### Restoring the DB Data

There is a script in './bin' that will restore the data from an existing DB Dump file.

```
./bin/hub_db_migrate.sh <path to dump file>
```

Once you run this, you'll be able to stop the existing containers and then run the full compose file.

### Stopping the Containers

```
docker-compose -f docker-compose.dbmigrate.yml -p hub stop
```

## Running 

Note: These command might require being run as either a root user, a user in the docker group, or with 'sudo'.

```
$ docker-compose -f docker-compose.yml -p hub up -d 
```

## Configuration

There are a couple of options that can be configured in this compose file. This section will conver these things:

### Web Server Settings

When the web server starts up, if it does not have certificates configured it will generate an HTTPS certificate. Configutation is needed to tell the web server which real hostname it will listening on so that the host names can match. Otherwise the certificate will only have the service name to use as the host name.

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

There are two methods for specifying a proxy password when using Docker Compose.

* Mount a directory that contains a file called 'HUB_PROXY_PASSWORD_FILE' to /run/secrets 
* Specify an environment variable called 'HUB_PROXY_PASSWORD' that contains the proxy password

There are the services that will require the proxy password:

* webapp
* registration
* jobrunner

