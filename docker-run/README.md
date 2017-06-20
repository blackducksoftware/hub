# Running Hub in Docker (Using Docker Run)

This is the bundle for running with Docker Run and no additional orchestration 

## Contents

Here are the descriptions of the files in this distribution:

1. docker-hub.sh - This file is a multi-purpose orchestration script useful for starting, stopping, and tearing down the Hub using standard Docker CLI commands.
2. docker-run.sh - This file is useful for starting the Hub using the standard Docker CLI commands.
3. docker-stop.sh - This file is useful for stopping a running Hub instance using the standard Docker CLI commands.
4. hub-proxy.env - The default, empty Proxy configuration file.  This is required to exist, even if it is left blank.

## Requirements

Hub has been tested on Docker 17.03.x (ce/ee).  No additional installations are needed.

## Running 

Note: These command might require being run as either a root user, a user in the docker group, or with 'sudo'.

```
# Start the Hub using docker-run.sh
$ docker-run.sh 3.7.0

# Stop the Hub using docker-stop.sh
$ docker-stop.sh

# Migrate data from the PostgreSQL dump file using docker-hub.sh
$ docker-hub.sh -r 3.7.0 -m <path/to/dump/file>

# Start the Hub using docker-hub.sh
$ docker-hub.sh -r 3.7.0 -u

# Stop the Hub using docker-hub.sh
$ docker-hub.sh -s

# Tearing down the Hub using docker-hub.sh, but leaving Volumes in place
$ docker-hub.sh -d

# Tearing down the Hub using docker-hub.sh and removing Volumes (removes ALL data)
$ docker-hub.sh -d -v
```

### Full Usage Documentation

#### docker-run.sh
This script accepts one mandatory argument.  This argument is the version of the Hub which should be installed on the system.  This should come in the format of MM.mm.ff, i.e. 3.7.0.

#### docker-hub.sh
This script accepts several arguments.  Do note that some arguments are mutually exclusive, and cannot be run in combination.  Also note that the --volumes flag will DELETE DATA from the system, and this is irreversible. Please understand this before running the command.

```
$ docker-hub.sh --help
This should be started with the following options:
        -r | --release : The Hub version that should be deployed.  This field is mandatory when running --up.
        -m | --migrate : Migrates Hub data from the PostgreSQL dump file. Typically this is run only once and very first if data needs to be migrated.
        -s | --stop : Stops the containers, but leaves them on the system.  Does not affect volumes. 
        -u | --up : Starts the containers.  Creates volumes if they do not already exist. 
        -d | --down : Stops and removes the containers.  If --volumes is provided, it will remove volumes as well. 
        -v | --volumes : If provided with --down, this script will remove the volumes and all data stored within them. 
```

Note, you cannot run --up, --stop and --down in the same command.  Also, --volumes will not work with --up or --stop.  

Lastly, --release is **required** to be run with --up.

Error messages will be presented if these rules are broken, without affecting the running system.

## Configuration

The only configuration necessary for use with this manner of starting the Hub is for the Proxy settings.  

***** UPDATE ME ******

### Web Server Settings

When the web server starts up, if it does not have certificates configured it will generate an HTTPS certificate. Configuration is needed to tell the web server which real host name it will listening on so that the host names can match. Otherwise the certificate will only have the service name to use as the host name.

#### Steps

1. Edit the _hub-proxy.env_ file to fill in the host name

### Proxy Settings

There are currently three containers that need access to services hosted by Black Duck Software:

* registration
* jobrunner
* webapp

If a proxy is required for external internet access you'll need to configure it. 

#### Steps

1. Edit the file _hub-proxy.env_

# Connecting to Hub

Once all of the containers for Hub are up the web application for hub will be exposed on port 443 to the docker host. You'll be able to get to hub using:

```
https://hub.example.com/
```

# Hub Reporting Database

Hub 3.6 ships with a reporting database. The database port will be exposed to the docker host for connections to the reporting user and reporting database.

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


