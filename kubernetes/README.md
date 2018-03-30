# Black Duck Hub On Kubernetes

This is the bundle for running with Kubernetes.

## Contents

Here are the descriptions of the files in this distribution:

1. kubernetes-pre-db.yml - This creates Kubernetes deployments to run as part of database migration or for bootstrapping.
2. kubernetes-post-db.yml - This creates Kubernetes deployments to run after the above database migration.

## Requirements

Hub has been tested on Kubernetes 1.6.6 extensively (GCE as well as AWS EC2
kube-adm).  

It has been installed
successfully, with limited testing, on Kubernetes 1.5 (OpenShift) and 1.7 (GCE).

## Restrictions

There are two general restrictions when using Hub in Kubernetes.

1. It is required that the PostgreSQL DB always runs on the same node so that data is not lost (hub-database service).
This is accomplished by using a StatefulSet.
2. It is required that the hub-webapp service and the hub-logstash service run on the same pod for proper log integration.

The second requirement is there so that the Hub web app can access the logs to be downloaded.
There is a possibility that network volume mounts can overcome these limitations, but this has not been tested.
The performance of PostgreSQL might degrade if a network volume is used. This has also not been tested.

# Installing the Hub

## First, create a namespace for your Hub.

Any valid namespace is fine, so long as it doesn't already exist on your cluster
and you don't plan on running other apps in it.

For example:

`kubectl create ns my-company-blackduckhub`

### Create your hub-config configmap.

There are several environment variable settings which can be used with Kubernetes.

You can upload these environment variables as a config map for the Hub like so:

(make sure to set the namespace in env)
```
kubectl create -f hub-config.yml
```

Throughout this document, references will be made to pods.env, where all Hub configuration data is stored.

We choose to consolidate all information into one resources for simplicity of managing watches and configuration related

logic, but in any case, these files could be separated if a user wanted to hide environment variables from different pods.

other.env has a list of other environment variables, which you can toggle
inside of pods.env and creation yaml files when you create your config map.

## Second: If necessary, migrate DB Data from Hub/AppMgr

This section will describe the process of migrating DB data from a Hub instance installed with AppMgr to this new version of Hub. There are a couple of steps.

NOTE: Before running this restore process it's important that only a subset of the containers is initially started. Sections below will walk you through this.

Also for simplicity we don't declare a namespace here.  Please add a command line option such as `--namespace=hub` to every command below based on your administrators conventions.

If you do not do this, the Hub containers will still work, however, they will all be created in the default namespace.

## Restoring the Data

### Finding a home for Postgres

There is a separate yaml file that will start Postgres for this restore process. You can run this:

First, you want to define a node which will run Postgres.

This node should have a host directory corresponding to where all your Postgres data will live.

Label it like as follows, note the node name will be a node that you can see from running:

```
 kubectl get nodes
```

Once you've found the home you want Postgres to live on, label this node:

```
 kubectl label nodes node-name blackduck.hub.Postgres=true
```

Now, you if you have complete control of your cluster, you can SSH into this node, and create a directory where your data can live.

```
mkdir -p /var/lib/hub-postgreSQL/data && chmod -R 775 /var/lib/hub-postgreSQL/data
```

*HOWEVER*... in a production Kubernetes cluster, you may want to configure volumes differently, and

in so doing, you may want to change the hostPath volume definition in the postgres pod.  Consult with your

Kubernetes admin, or with Black Duck Customer Support, if you don't support hostPath volume mounts, or want a more sophisticated storage model.

Note that you can configure the volume for Postgres in a variety of different ways.

Its up to you to find out what works best for your organizations needs, and the local make directory default provided above is just a simplest way, most unopinionated way to accomplish the basic need of a

persistent home that is pod-schedulable inside of Kubernetes.

### Starting Postgres

```
kubectl create -f Kubernetes-pre-db.yml
```

Once this has brought up the DB container the next step is to restore the data.

Note that if you have trouble pulling images, you can inspect this at scheduling time, by looking at Kubernetes events:

```
kubectl get events
```

Once the data has been restored, the rest of the services can be brought up using the commands from
the 'Running' section below, the services that are currently running do not need to be stopped or removed.

### Understanding Postgres' security configuration

Postgres security is derived from CFSSL, which runs as a service inside your cluster.

If you want your Hub database to be secure:

1) Make sure the namespace you are running Postgres in is secure.

2) Make sure that you have control over the users starting containers in that namespace.

3) Make sure that the node which was labelled for Postgres is protected from SSH by untrusted users.

### Restoring the DB Data

There is a script in './bin' that will restore the data from an existing DB Dump file.

To use it, ssh into the NODE that is running Postgres, such that the
prerequisites for the script are all correct.  Then do the following:

```
./bin/hub_db_migrate.sh <path to dump file>
```

In order to ssh into the right node to run this command, you'll need to find the
corresponding node.

```
kubectl get nodes -l blackduck.hub.postgres=true
```

Note that you could also get this information by doing a query such as:

```
kubectl get pod postgres -o=jsonpath='{.spec.nodeName}'
```

Now that you know the hostname where postgres is running,

1. ssh into the machine provided from `kubectl get pod postgres -o=jsonpath='{.spec.nodeName}'`
2. run `./bin/hub_db_migrate.sh <path to dump file>` on that machine locally.

As mentioned at the top, make sure to include --namespace in the above argument as needed!

Once you run this, you'll be able to stop the existing containers and then run the full compose file.

When a dump file is restored from an AppMgr version of Hub, you might see a couple of errors like:

```
 ERROR:  role "blckdck" does not exist
```

Along with a few surrounding errors. At the end of the migration you might also see:

```
WARNING: errors ignored on restore: 7
```

This is OK and should not affect the data restoration.

### Removing the Services

Assuming all your containers are in the namespace `hub`, you can delete the Hub like so.
```
kubectl delete ns hub
```

## Running

```
kubectl create -f kubernetes-pre-db.yml
kubectl create -f kubernetes-post-db.yml
```

## Running with External PostgreSQL

Hub can be run using a PostgreSQL instance other than the provided hub-postgres docker image.

In order to do this, you need to modify the Postgres. variables in pods.env to reflect your external data source.

This is described later in this document.

## Configuration

There are several options that can be configured in the yml files for Kubernetes as described below.

### Web Server Settings

#### Host Name Modification

When the web server starts up, if it does not have certificates configured it will generate an HTTPS certificate.

Configuration is needed to tell the web server which real host name it listens on so that the host names can match.

Otherwise the certificate will only have the service name to use as the host name.

To modify the real host name, edit the pods.env file to update the desired host name value.

#### Port Modification

The web server is configured with a host to container port mapping.  If a port change is desired, the port mapping should be modified along with the associated configuration.

To modify the host port, edit the port mapping as well as the "hub webserver" section in the pods.env file to update the desired host and/or container port value.

If the container port is modified, any health check URL references should also be modified using the updated container port value.

### Proxy Settings

There are currently several services that need access to services hosted by Black Duck Software:

* authentication
* jobrunner
* registration
* scan
* webapp

If a proxy is required for external internet access, you'll need to configure it.

#### Steps

1. Edit the "hub proxy" section in pods.env
2. Add any of the required parameters for your proxy setup

#### Authenticated Proxy Password

*Note that '/run/secrets/' can be any directory, specifiable in the $RUN_SECRETS_DIR enviroment variable*

There are three methods for specifying a proxy password when using Docker

- add a Kubernetes secret called HUB_PROXY_PASSWORD_FILE

- mount a directory that contains a file called HUB_PROXY_PASSWORD_FILE to /run/secrets (better to use secrets here)

- specify an environment variable called 'HUB_PROXY_PASSWORD' that contains the proxy password

There are the services that will require the proxy password:

* authentication
* jobrunner
* registration
* scan
* webapp

#### LDAP Trust Store Password

There are two methods for specifying an LDAP trust store password when using Kubernetes.

* Mount a directory that contains a file called 'LDAP_TRUST_STORE_PASSWORD_FILE' to /run/secrets (better to use secrets here).
* Specify an environment variable called 'LDAP_TRUST_STORE_PASSWORD' that contains the password.

This configuration is only needed when adding a custom Hub web application trust store.

#### Adding the password secret

The password secret will need to be added to the services:

* authentication
* jobrunner
* registration
* scan
* webapp

In each of these pod specifications, you will need to add the secret injection
next to the image that is using them, for example:

```
        image: hub-webapp:4.2.0
        env:
            - name: HUB_PROXY_PASSWORD_FILE
              valueFrom:
              secretKeyRef:
                name: db_user
                key: password

```

This secret references a db_user secret that would be created beforehand, like so:

```
kubectl create secret generic db_user --from-file=./username.txt --from-file=./password.txt
```

# Connecting to Hub

Once all of the containers for Hub are up the web application for Hub will be exposed on port 443 to the docker host. You'll be able to get to Hub using:

```
https://hub.example.com/
```

## Using a Custom web server certificate-key pair

Hub allows users to use their own web server certificate-key pairs for establishing ssl connection.

* Create a Kubernetes secret each called 'WEBSERVER_CUSTOM_CERT_FILE' and 'WEBSERVER_CUSTOM_KEY_FILE' with the custom certificate and custom key in your namespace.

You can do so by

```
kubectl secret create WEBSERVER_CUSTOM_CERT_FILE --from-file=<certificate file>
kubectl secret create WEBSERVER_CUSTOM_KEY_FILE --from-file=<key file>
```

For the webserver service, add secrets by copying their values into 'env'
values for the pod specifications in the webserver.


# Hub Reporting Database

Hub ships with a reporting database. The database port will be exposed to the Kubernetes network

for connections to the reporting user and reporting database.

Details:

* Exposed Port: 55436
* Reporting User Name: blackduck_reporter
* Reporting Database: bds_hub_report
* Reporting User Password: initially unset

Before connecting to the reporting database you'll need to set the password for the reporting user. There is a script included in './bin' of the docker-compose directory called 'hub_reportdb_changepassword.sh'.

To run this script, you must:

* Be on the Kubernetes node that is running the PostgreSQL database container
* Be able to run 'docker' commands. This might require being 'root' or in the 'docker' group depending on your docker setup.

To run the change password command:

```
./bin/hub_reportdb_changepassword.sh blackduck
```

Where 'blackduck' is the new password. This script can also be used to change the password for the reporting user after it has been set.

Once the password is set you should now be able to connect to the reporting database. An example of this with 'psql' is:

```
kubectl get service postgres -o wide
```

The above command will give you all the information about the internal and external IP for your postgres service.

Then you can take the external IP (if your Postgres client is outside the cluster)

and run a command such as:

```
psql -U blackduck_reporter -p 55436 -h $external_ip_from_above -W bds_hub_report
```

#### Scaling Hub

The Job Runner and scan pods are the only services that are scalable.

They can be scaled up or down using:

```
kubectl scale dc jobrunner --replicas=2
kubectl scale dc hub-scan --replicas=2
```

#### External PostgreSQL Settings

The external PostgreSQL instance needs to be initialized by creating users, databases, etc., and connection information must be provided to the _authentication_, _jobrunner_, _scan_, and _webapp_ and containers.

#### Steps

1. Create a database user named _blackduck_ with administrator privileges.  (On Amazon RDS, do this by setting the "Master User" to "blackduck" when creating the RDS instance.)
2. Run the _external-postgres-init.pgsql_ script to create users, databases, etc.; for example,
   ```
   psql -U blackduck -h <hostname> -p <port> -f external_postgres_init.pgsql postgres
   ```
3. Using your preferred PostgreSQL administration tool, set passwords for the *blackduck* and *blackduck_user* database users (which were created by step #2 above).
4. Add your passwords for the blackduck_user and the admin user to a configmap like so:

- Create a file, /tmp/password, for your USER, ADMIN password...

```
apiVersion: v1
data:
  HUB_POSTGRES_ADMIN_PASSWORD_FILE: |
    blackduck
kind: ConfigMap
metadata:
  name: hpup-admin
```

And again, do the same changing HUB_POSTGRES_ADMIN_PASSWORD_FILE and hpup-admin
out with HUB_POSTGRES_*USER*_PASSWORD_FILE and hpup-*user* (this is demonstrated in
the Kubernetes external rds example yaml).

- Use `kubectl create -f /tmp/password`
- Repeat the above step for the blackduck_user password.
- Use `kubectl edit configmap hub-config` to modify your hub-config map, so that SSL is disabled, and so that the Postgres host is used, like so:
```
    "apiVersion": "v1",
    "data": {
        "HUB_POSTGRES_ADMIN": "blackduck",
        "HUB_POSTGRES_ENABLE_SSL": "false",
        "HUB_POSTGRES_HOST": "blackduck1.cirglt6ozchh.us-east-1.rds.amazonaws.com",
        "HUB_POSTGRES_PORT": "5432",
        "HUB_POSTGRES_USER": "blackduck_user",
```

- Note that, since you do not know beforehand the IP that your containers will be connecting, if using a cloud Postgres with a firewall, you need to allow
ingress from 'anywhere', or at least from a range of IPs that you allocate based on your network egress IP git information.
- Also, make sure that you set your blackduck_user password correctly, i.e.

```
ALTER ROLE blackduck_user WITH PASSWORD 'blackduck';
```

5. Supply passwords for the _blackduck_ and *blackduck_user* database users.

##### Create Kubernetes secrets

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

Then, for your webapp and jobrunner pod specifications, modify the env. section as follows:
```
        image: hub-webapp:4.2.0
        env:
            - name: HUB_POSTGRES_USER_PASSWORD_FILE
              valueFrom:
              secretKeyRef:
                name: db_user
                key: password

```

### Finally expose your Kubernetes service so you can login and use the Hub:

Once everything is running, depending on your deployment, you can expose it to the outside world.

```
 kubectl expose --namespace=default deployment webserver --type=LoadBalancer --port=443 --target-port=8443 --name=nginx-gateway
```

Note that another option here is to use a `--type=NodePort`, which will allow you to access the service

at any port.

After creating the load balancer above, you can find its external endpoint:

```
kubectl get services -o wide
```

You will see a URL such as this:

```
nginx-gateway           10.99.200.3      a0145b939671d...   443:30475/TCP   2h
```

You can thus curl it:

```

ubuntu@ip-10-0-22-242:~$ curl --insecure https://a0145b939671d11e7a6ff12207729cdd-587604034.us-east-1.elb.amazonaws.com:443

```

And you should be able to see a result which includes an HTTP page.

```
 <!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta http-equiv="X-UA-Compatible" content="IE=edge"><meta name="viewport" content="width=device-width, initial-scale=1"><link rel="shortcut icon" type="image/ico" href="data:image/x-icon;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAACXBIWXMAAC4jAAAuIwF4pT92AAA5+mlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4KPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNS42LWMxMzIgNzkuMTU5Mjg0LCAyMDE2LzA0LzE5LTEzOjEzOjQwICAgICAgICAiPgogICA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPgogICAgICA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIgogICAgICAgICAgICB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iCiAgICAgICAgICAgIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyIKICAgICAgICAgICAgeG1sbnM6cGhvdG9zaG9wPSJodHRwOi8vbnMuYWRvYmUuY29tL3Bob3Rvc2hvcC8xLjAvIgogICAgICAgICAgICB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIKICAgICAgICAgICAgeG1sbnM6c3RFdnQ9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZUV2ZW50IyIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iCiAgICAgICAgICAgIHhtbG5zOmV4aWY9Imh0dHA6Ly9ucy5hZG9iZS5j
```

### Debugging a running deployment

The following exemplifies debugging of a deployment.  If you have any doubt that your cluster
is working properly, go through these steps and see where the divergence has occurred.

Find all the pods that are running: They all should be alive:

```
ubuntu@ip-10-0-22-242:~$ kubectl get pods
NAME                                     READY     STATUS    RESTARTS   AGE
cfssl-258485687-m3szc                    1/1       Running   0          3h
jobrunner-1397244634-xgcn2               1/1       Running   2          26m
nginx-webapp-2564656559-6fbq8   2/2       Running   0          26m
postgres-1794201949-tt4gj                1/1       Running   0          3h
registration-2718034894-7brjv            1/1       Running   0          26m
solr-1180309881-sscsl                    1/1       Running   0          26m
zookeeper-3368690434-rnz3m               1/1       Running   0          26m
...
```

Now jot those pods down, we will exec into them to confirm they are functioning properly.

Check the logs for the web app: They should be active over time:

```
kubectl logs nginx-webapp-2564656559-6fbq8 -c webapp
```

```
2017-07-12 18:13:12,064 [http-nio-8080-exec-4] INFO  com.blackducksoftware.core.regupdate.impl.RegistrationApi - Executing registration action [Action: check | Registration id: null | URL: http://registration:8080/registration/HubRegistration | Registration request: RegistrationRequest{attributeValues={MANAGED_CODEBASE_BYTES_NEW=0, CODE_LOCATION_BYTES_LIMIT=0, CUSTOM_PROJECT_LIMIT=0, USER_LIMIT=1, PROJECT_RELEASE_LIMIT=0, CODE_LOCATION_LIMIT=0, CODEBASE_MANAGED_LINES_OF_CODE=0}, dateTimeStatistics={}, longStatistics={scanCount=0}}]
2017-07-12 18:13:12,071 [http-nio-8080-exec-4] ERROR com.blackducksoftware.core.regupdate.impl.RegistrationApi - Unable to execute remote registration request [Action: check | Registration id: null | URL: http://registration:8080/registration/HubRegistration]: I/O error on POST request for "http://registration:8080/registration/HubRegistration?bdscode=1499883192064&action=check":registration: Name does not resolve; nested exception is java.net.UnknownHostException: registration: Name does not resolve
2017-07-12 18:25:42,596 [http-nio-8080-exec-1] INFO  com.blackducksoftware.usermgmt.sso.impl.BdsSAMLEntryPoint - Single Sign On is disabled by administrator.
2017-07-12 18:27:52,670 [scanProcessorTaskScheduler-1] INFO  com.blackducksoftware.scan.bom.scheduler.ScanPurgeJobMonitorSchedulingService - Skipping scan purge job, previous job is still in progress
2017-07-12 18:30:00,059 [job.engine-0] WARN  com.blackducksoftware.job.integration.handler.KbCacheUpdater - KB project update job will not be scheduled because a KB project, release, or vulnerability update job currently is scheduled or running.
```

If your web app is working, but you can't see it from outside the cluster, check that your load balancer works, after finding its pod, like so:

```
kubectl exec -t -i webserver-fj3882 cat /var/log/nginx/nginx-access.log
```

You should see something like this (assuming you used chrome, curl, and so on to try to access the site).

```
192.168.21.128 - - [12/Jul/2017:18:13:12 +0000] "GET /api/v1/registrations?summary=true&_=1499883191824 HTTP/1.1" 200 295 "https://a0145b939671d11e7a6ff12207729cdd-587604034.us-east-1.elb.amazonaws.com/" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.115 Safari/537.36" "-"
192.168.21.128 - - [12/Jul/2017:18:13:12 +0000] "GET /api/internal/logo.png HTTP/1.1" 200 7634 "https://a0145b939671d11e7a6ff12207729cdd-587604034.us-east-1.elb.amazonaws.com/" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.115 Safari/537.36" "-"
10.0.25.32 - - [12/Jul/2017:18:25:42 +0000] "GET / HTTP/1.1" 200 21384 "-" "curl/7.47.0" "-"
```

#### Exposing endpoints

Note that finally, you should make sure that you keep exposed the NGINX and Postgres
endpoints so external clients can access them as necessary.


#### NGINX Configuration details.

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

```
volumes
- configMap:
      defaultMode: 420
      name: certs
    name: dir-certs
...
volumeMounts:
- mountPath: /run/secrets
  name: dir-certs
```
#### Loadbalancer and Proxy settings.

Also, export HUB_PROXY_PORT and HUB_PROXY_HOST values, inside the nginx pod, as needed based on your load balancer host / port.  Especially important to note if using hostnames and node ports that are (non 8443).

A diagram of a typical set of envionrment variables that would be exported for
containers is shown below:

```
PUBLIC_HUB_WEBSERVER_HOST=hub.my.company
PUBLIC_HUB_WEBSERVER_PORT=14085
volumeMounts:
- mountPath: /run/secrets
  name: dir-certs
+-----------------------+     
|                       |     
|    nginx (webserver)  |        HUB_PROXY_HOST=proxy.my.company HUB_PROXY_HOST=proxy.my.company
+-----------+-----------|        HUB_PROXY_PORT=8080             HUB_PROXY_PORT=8080
            |                    +-------------------+         +--------------+
            +--------------------+                   |         |   jobrunner  |
                                 |   wwebapp         |         +-+------------+
                                 |                   |           |
 HUB_PROXY_HOST=proxy.my.company +--------------------       +----
 HUB_PROXY_PORT=8080                  |                      |
      +---------------+               |                      |
      |  registration |               |   +------+           |
      +---------------+               +---+ psql +-----------+
                                          +------+
```
