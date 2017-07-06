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

### Running with External PostgreSQL

Hub can be run using a PostgreSQL instance other than the provided hub-postgres docker image.  This configuration can only be managed using the _docker-hub.sh_ script.  Invocation is as above, except with the addition of the _-e_ (_--externadb_) option:

```
# Start the Hub using docker-hub.sh
$ docker-hub.sh -r 3.7.0 -u -e

# Stop the Hub using docker-hub.sh
$ docker-hub.sh -s -e

# Tearing down the Hub using docker-hub.sh, but leaving Volumes in place
$ docker-hub.sh -d -e

# Tearing down the Hub using docker-hub.sh and removing Volumes (removes ALL docker-managed data; the external PostgreSQL instance is not affected)
$ docker-hub.sh -d -v -e
```

The _docker-hub.sh_ script does not attempt to manage the external PostgreSQL instance and assumes that it has already been configured (see External PostgreSQL Settings below).


### Full Usage Documentation

#### docker-run.sh
This script accepts one mandatory argument.  This argument is the version of the Hub which should be installed on the system.  This should come in the format of MM.mm.ff, i.e. 3.7.0.

#### docker-hub.sh
This script accepts several arguments.  Do note that some arguments are mutually exclusive, and cannot be run in combination.  Also note that the --volumes flag will DELETE DATA from the system, and this is irreversible.  Pleaes understand this before running the command.

```
$ docker-hub.sh --help
This should be started with the following options:
        -r | --release : The Hub version that should be deployed.  This field is mandatory when running --up.
        -m | --migrate : Migrates Hub data from the PostgreSQL dump file. Typically this is run only once and very first if data needs to be migrated.
        -s | --stop : Stops the containers, but leaves them on the system.  Does not affect volumes. 
        -u | --up : Starts the containers.  Creates volumes if they do not already exist. 
        -d | --down : Stops and removes the containers.  If --volumes is provided, it will remove volumes as well. 
        -v | --volumes : If provided with --down, this script will remove the volumes and all data stored within them. 
		-e | --externaldb : Use an external PostgreSQL instance rather than the default docker container; cannot be used with --migrate.
```

Note, you cannot run --up, --stop and --down in the same command.  Also, --volumes will not work with --up or --stop.  

Lastly, --release is **required** to be run with --up.

Error messages will be presented if these rules are broken, without affecting the running system.


## Configuration

Custom configuration may be necessary for host name, port, or proxy server management.

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

There are currently three containers that need access to services hosted by Black Duck Software:

* registration
* jobrunner
* webapp

If a proxy is required for external internet access you'll need to configure it. 

#### Steps

1. Edit the file _hub-proxy.env_

#### Authenticated Proxy Password

First, these are the services which require proxy password.
* webapp
* registration
* jobrunner

There are two methods for specifying a proxy password when using Docker run.

* Mount a directory that contains a text file called 'HUB_PROXY_PASSWORD_FILE' to /run/secrets 
You can mount the volume by editing the script docker-hub.sh. Add an option (-v) after 'docker run...' for the services mentioned right above
```
-v <Local Directory>:/run/secrets
```

OR

* Specify an environment variable called 'HUB_PROXY_PASSWORD' that contains the proxy password
```
-e HUB_PROXY_PASSWORD='PASSWORD'
```

### Using Custom web server certificate-key pair
*For the upgrading users from version < 4.0 : 'hub_webserver_use_custom_cert_key.sh' no longer exists so please follow the updated instruction below if you wish to use the custom webserver certificate.*
Hub allows users to use their own web server certificate-key pairs for establishing ssl connection.

* Mount a directory that contains the custom certificate and key file each as 'WEBSERVER_CUSTOM_CERT_FILE' and 'WEBSERVER_CUSTOM_KEY_FILE' to /run/secrets
You can mount the volume by editing the script docker-hub.sh. Add an option (-v) after 'docker run...' for the services mentioned right above
```
-v <Local Directory>:/run/secrets
```

### External PostgreSQL Settings

The external PostgreSQL instance needs to initialized by creating users, databases, etc., and connection information must be provided to the _webapp_ and _jobrunner_ containers.

#### Steps

1. Create a database user named _blackduck_ with admisitrator privileges.  (On Amazon RDS, do this by setting the "Master User" to "blackduck" when creating the RDS instance.)
2. Run the _external-postgres-init.pgsql_ script to create users, databases, etc.; for example,
   ```
   psql -U blackduck -h <hostname> -p <port> -f external_postgres_init.pgsql postgres
   ```
3. Using your preferred PostgreSQL administration tool, set passwords for the *blackduck* and *blackduck_user* database users (which were created by step #2 above).
4. Edit _hub-postgres.env_ to specify database connection parameters.
5. Create a file named 'HUB_POSTGRES_USER_PASSWORD_FILE' with the password for the *blackduck_user* user.
6. Create a file named 'HUB_POSTGRES_ADMIN_PASSWORD_FILE' with the password for the _blackduck_ user.
