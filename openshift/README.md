# Running Hub

This is the bundle for running an Openshift cluster.

Note that the "kubectl" commands below will work interchangeably with the "oc"
command.

## Contents

- openshift.yml

## An extremely Quick Start to get a prototypical hub deployment on OpenShift

There are many options for running the hub on openshift, but to simplify things, we provide a canonical supported deployment of as follows.  Work with your administrator (and blackduck support) to evolve the configuration into something that matches your organizations database, orchestration, and storage needs over time.

So, to get started quickly with the hub on openshift using an 'external' postgres instance, run these commands.

*WARNING: DO NOT HARDCODE PASSWORDS IN PRODUCTION, USE SECRETS INSTEAD, THIS IS JUST FOR PEDAGOGICAL PURPOSES.*

- First, run `oc create -f db.yml`.
- Now run `oc exec -t -i $(oc get pods | grep postgres) /bin/sh`, to enter the database pod.
- Now, as you're inside the pod:
  - Run `createuser blackduck` inside the container (this might fail, if the user already exists, and thats ok).
  - Then `vi /tmp/init-db.sql`, copy the contents of external-postgres-init.pgsql into that file.
    - Additionally, add these two statements to the top of this file.
      - `ALTER USER blackduck_user WITH password 'blackduck' ;`
      - `ALTER USER blackduck WITH password 'blackduck' ;`
  - Now run the following command: `psql -a -f /tmp/init-db.sql ; psql -a -f /tmp/init-db.sql` .  
  - exit the container.
- At this point, the postgres database has been initialized.
- Now, modify `HUB_POSTGRES_HOST: blackduck123.rds.amazonaws.com` in openshift.yml to be `HUB_POSTGRES_HOST: postgres`, which is the service name of the pod in db.yml.
- Finally, run `oc create -f openshift.yml`
- The hub will eventually come up, and you can run 'oc get pods' to see all the containers running.

## Quick start FAQ


1) Is this an external database ?

Yes, in the sense that it is set up and maintained without using the default CFSSL based auth that other hub deployments use, and in that you configure it
yourself.

# Running Hub: Detailed instructions and reference.

The below instructions should be considered as reference information, which may
be unweildy to consume without a tragetted purpose.  If you want to get up and running,
try the quick start instructions above, first.  Afterwards, reading through
the below instructions will be much more intuitive for you.

## Configuration

There are various ways to customize the installation of the hub on openshift:

- Edit the versions in the YAML file of containers that are used.
- Edit the YAML file in other ways, i.e. change run commands or storage volumes.
- Edit the config map (pods.env).

The final option (config map) is the idiomatic way to modify the hubs behaviour
for your system, it is highly unlikely that you will want to modify the names of
the containers being used, or modify the docker run commands being invoked for
them.

Later on, once you read this document, you will want to create the config map
using the following command:

```
oc create -f pods.env
```

## Requirements

An openshift 3.5 or higher cluster.  Other clusters may also work with slight configuration changes.

Note: For Openshift 3.4 and lower, config map variables may need to be substituted with environment
variables.  This can be solved on a case-by-case basis for your cluster, based on what API features
are/aren't present.

## Restrictions

There are two general restrictions when using Hub in Kubernetes.

1. It is required that the PostgreSQL DB always runs on the same node so that data is not lost (hub-database service).
This is accomplished by using a StatefulSet.
2. It is required that the hub-webapp service and the hub-logstash service run on the same pod for proper log integration.

The second requirement is there so that the hub web app can access the logs to be downloaded.
There is a possibility that network volume mounts can overcome these limitations, but this has not been tested.
The performance of PostgreSQL might degrade if a network volume is used. This has also not been tested.

# Migrating DB Data from Hub/AppMgr

This section will describe the process of migrating DB data from a Hub instance installed with AppMgr to this new version of Hub. There are a couple of steps.

NOTE: Before running this restore process it's important that only a subset of the containers are initially started. Sections below will walk you through this.

Also for simplicity we don't declare a namespace here.  Please add a command line option such as `--namespace=hub` to every command below based on your administrators conventions.

If you do not do this, the hub containers will  still work, however, they will all be created in the default namespace.

## Create a new hub instance on openshift

First, pick a namespace (i.e. hub) for blackduck's hub to run in.  Note you
will need a large amount of memory to run the hub, so pick a namespace that
isn't constrainted in any uncommon way.  You should have Greater then 4 cores
and schedulable 16GB of memory to run the hub.

Now, run

```
  oc new-project hub
```

### Removing the hub from openshift

Later, if you want to remove the hub, assuming all your containers are in the namespace `hub`, you can delete the hub like so.
```
oc delete project hub
```

### Setup PostgreSQL on RDS

Hub can be run using a PostgreSQL instance other than the provided hub-postgres docker image.

For OpenShift, we run Postgres outside of the cluster because the currently
published, standard postgres containers do not support a cloud-native
functionality - that is - they expect certain things of the underlying OS, such
as user name and/or escalated permissions.

In order to do this, you need to modify the postgres. variables in pods.env to reflect your external data source.

1. Create a database user named _blackduck_ with admisitrator privileges.  (On
   Amazon RDS, do this by setting the "Master User" to "blackduck" when creating
   the RDS instance.)
2. Run the _external-postgres-init.pgsql_ script to create users, databases, etc.; for example,
```             
            psql -U blackduck -h <hostname> -p <port> -f
            external_postgres_init.pgsql postgres
```
3. Using your preferred PostgreSQL administration tool, set passwords for
the *blackduck* and *blackduck_user* database users (which were created by step #2 above).
4. Edit _hub-postgres.env_ to specify database connection parameters.
5. Supply passwords for the _blackduck_ and *blackduck_user* database users
through _one_ of the two methods below.

#### Modify public webserver host, and proxies according to your OpenShift endpoint.

In OpenShift you will likely be accessing the blackduck hub through an
intermediate loadbalancer which doesn't forward packets.  

To setup a proper hostname so that all hub services work from client side,
modify `PUBLIC_HUB_WEBSERVER_HOST`, as well as `PUBLIC_HUB_WEBSERVER_PORT` to
match the endpoint which you are using to access the hub.

A diagram of a typical set of environment variables that would be exported for
containers is shown below:

```
PUBLIC_HUB_WEBSERVER_HOST=hub.my.company
PUBLIC_HUB_WEBSERVER_PORT=14085
RUN_SECRETS_DIR=/var/mycompany/secrets
volumeMounts:
- mountPath: /var/mycompany/secrets
  name: dir-certs
+-----------------------+     
|                       |     
|    nginx (webserver)  |        HUB_PROXY_HOST=proxy.my.company HUB_PROXY_HOST=proxy.my.company
+-----------+-----------|        HUB_PROXY_PORT=8080             HUB_PROXY_PORT=8080
            |                    +-------------------+         +--------------+
            +--------------------+                   |         |   jobrunner  |
                                 |   webapp         |          +-+------------+
                                 |                   |           |
 HUB_PROXY_HOST=proxy.my.company +--------------------       +----
 HUB_PROXY_PORT=8080                  |                      |
      +---------------+               |                      |
      |  registration |               |   +------+           |
      +---------------+               +---+ psql +-----------+
                                          +------+
```

### Modify KB Egress Proxy Settings if you need to.

There are currently several services that need access to services hosted by Black
Duck Software, outside of your openshift cluster.

* authentication
* jobrunner
* registration
* scan
* webapp

If a proxy is required for external internet access you'll need to configure it.

1. Edit the "hub proxy" section in pods.env
2. Add any of the required parameters for your proxy setup

#### NGINX Configuration details.

NGINX will work out of the box, however, to access it from outside your router,
may want to either (1) use trusted certs , rather then default self-signed ones,
and (2) also you may need to export a custom hostname / port, which is necessary
if you're accessing nginx through a non default hostname / port.

Create a configmap/secret which can hold data necessary for injecting your organization's credentials into nginx.

```
apiVersion: v1
items:
- apiVersion: v1
  kind: ConfigMap
    metadata:
      name: certs
      namespace: customer1
  data:
    WEBSERVER_CUSTOM_CERT_FILE: |
      -----BEGIN CERTIFICATE-----
      ….. (insert organizations certs here)
      -----END CERTIFICATE-----
    WEBSERVER_CUSTOM_KEY_FILE: |
      -----BEGIN PRIVATE KEY-----
     …… (insert organizations SSL keys here)
      -----END PRIVATE KEY-----
```

Then create that config map:

```
kubectl create -f nginx.yml
```

And update the nginx pod segment for nginx, like so, adding the following volume/volume-mount pair:

Note that we mount those secrets to /run/secrets2 here, and we need to export `RUN_SECRETS_DIR`
as an environment variable, in the nginx container - such that its NOT = `/run/secrets`, because that default value is NOT writablbe in openshift (enterprise) clusters, due to its mount precedence
that comes from RHEL usage of this directory.

```
volumes
- configMap:
      defaultMode: 420
      name: certs
    name: dir-certs
...
volumeMounts:
### MAKE SURE YOU EXPORT RUN_SECRETS_DIR=/run/secrets2 in this pod !
- mountPath: /run/secrets2
  name: dir-certs
```

Ports:

Also, export HUB_PROXY_PORT and HUB_PROXY_HOST values, inside the nginx pod, as needed based on your openshift route / port.  Especially important to note if using hostnames and node ports that are (non 8443).

#### Authenticated Proxy Password

*Note that '/run/secrets/' can be any directory, specifiable in the $RUN_SECRETS_DIR enviroment variable*

There are three methods for specifying a proxy password when using Docker
- add a secret called HUB_PROXY_PASSWORD_FILE

- mount a directory that contains a file called HUB_PROXY_PASSWORD_FILE to /run/secrets (better to use secrets here)

- specify an environment variable called 'HUB_PROXY_PASSWORD' that contains the proxy password

There are the services that will require the proxy password:

* authentication
* jobrunner
* registration
* scan
* webapp

# Connecting to Hub

Once all of the containers for Hub are up the web application for hub will be
exposed on port 443 to the docker host. You'll be able to get to hub using:
https://PUBLIC_WEBSEVER_HOST:PUBLIC_WEBSERVER_PORT as defined above.

After you've made modifications to the ConfigMap and other sections.  In the file above.

oc create -f

# Scaling Hub

The Job Runner in the only service that is scalable. Job Runners can be scaled up or down using:

```
kubectl scale dc jobrunner --replicas=2
```

#### External PostgreSQL Settings

The external PostgreSQL instance needs to be initialized by creating users, databases, etc., and connection information must be provided to the _authentication_, _jobrunner_, _scan_, and _webapp_ containers.

#### Steps

1. Create a database user named _blackduck_ with admisitrator privileges.  (On Amazon RDS, do this by setting the "Master User" to "blackduck" when creating the RDS instance.)
2. Run the _external-postgres-init.pgsql_ script to create users, databases, etc.; for example,
   ```
   psql -U blackduck -h <hostname> -p <port> -f external_postgres_init.pgsql postgres
   ```
3. Using your preferred PostgreSQL administration tool, set passwords for the *blackduck* and *blackduck_user* database users (which were created by step #2 above).

And again, do the same changing HUB_POSTGRES_ADMIN_PASSWORD_FILE and hpup-admin
out with HUB_POSTGRES_USER_PASSWORD_FILE and hpup-*user* (this is demonstrated in
the kubernetes external rds exaxmple yaml).

- Modify the accompanying YAML file sections for the blackduck_user and blackduck passwords to match
what you have for your external database that you created.

- Note that, since you do not know before hand the IP that your containers will be connecting, if using a cloud postgres with a firewall, you need to allow
ingress from 'anywhere', or at least from a range of IPs that you allocate based on your network egress IP git information.
- Also, make sure that you set your blackduck_user password correctly, i.e.

```
ALTER ROLE blackduck_user WITH PASSWORD 'blackduck';
```

5. Supply passwords for the *blackduck* and *blackduck_user* database users.

##### Create OpenShift secrets

The password secrets will need to be added to the pod specifications for:

* authentication
* jobrunner
* scan
* webapp

For instance, given user password stored in user_pwd.txt, admin_pwd.txt - you

will add them like this:

```
kubectl create secret HUB_POSTGRES_USER_PASSWORD --from-file=user_pwd.txt
kubectl create secret HUB_POSTGRES_ADMIN_PASSWORD --from-file=admin_pwd.txt
```

Then, for your webapp, scan, and jobrunner pod specifications, modify the env. section as follows:
```
        image: hub-webapp:4.0.0
        env:
            - name: HUB_POSTGRES_USER_PASSWORD_FILE
              valueFrom:
              secretKeyRef:
                name: db_user
                key: password

```

### Finally expose your OpenShift service so you can login and use the hub:

Once everything is running, depending on your deployment, you can expose it to the outside world.

This is done using openshift routes, MAKE SURE that:

- Your administrator has setup openshift routers correctly, and that at least one router is available.
- You know the external IP address that is loadbalancing to the Routers.
- You record the hostname that you want to use to access an openshift router.

For example, if you know you want IP Address (a.b.c.d/hub) to route to your hub, make sure there
is a DNS record that reliably forwards a.b.c.d/hub to the exposed openshift router endpoint, whatver that may be, which you have set up.

Note that since openshift routers bind to the host network, this might be as easy as simply mapping a DNS entry to the openshift router pods host IP address.

For completeness, we note that another option here is to create  a service using `--type=NodePort`.  That would allow you to access the hub by going to any machine running openshift DNS on your cluster.

This option is not idiomatic to most production openshift environments - it is advised in stead to use routers and set them up with your administrators advice.

After creating the loadbalancer above, you can find its external endpoint:

#### Example workflow

- Record the external IP of one of your openshift routers.
- Create an Openshift route pointing to the nginx service.
- Set the URL to external-ip.xip.io (xip.io is a DNS Service that forwards to the IP address in the prefix.)
- Setup the TLS to passthrough.
- Deploy your router, and access the hub at https://external-ip.xip.io, for example 128.100.200.300.xip.io, if you have a router running on an exposed IP at 128.100.200.300.

```
oc get services -o wide
```

You will see a URL such as this:

```
nginx-gateway           10.99.200.3      a0145b939671d...   443:30475/TCP   2h
```

You can thus curl it:

```

ubuntu@ip-10-0-22-242:~$ curl --insecure https://PUBLIC_WEBSEVER_HOST:PUBLIC_WEBSERVER_PORT:443

```

And you should be able to see a result which includes an HTTP page.

```
 <!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta http-equiv="X-UA-Compatible" content="IE=edge"><meta name="viewport" content="width=device-width, initial-scale=1"><link rel="shortcut icon" type="image/ico" href="data:image/x-icon;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAACXBIWXMAAC4jAAAuIwF4pT92AAA5+mlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4KPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNS42LWMxMzIgNzkuMTU5Mjg0LCAyMDE2LzA0LzE5LTEzOjEzOjQwICAgICAgICAiPgogICA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPgogICAgICA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIgogICAgICAgICAgICB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iCiAgICAgICAgICAgIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyIKICAgICAgICAgICAgeG1sbnM6cGhvdG9zaG9wPSJodHRwOi8vbnMuYWRvYmUuY29tL3Bob3Rvc2hvcC8xLjAvIgogICAgICAgICAgICB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIKICAgICAgICAgICAgeG1sbnM6c3RFdnQ9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZUV2ZW50IyIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iCiAgICAgICAgICAgIHhtbG5zOmV4aWY9Imh0dHA6Ly9ucy5hZG9iZS5j
```
