# Black Duck Hub On Kubernetes / Openshift.

## Existing hub customers: Migrating to a new version.

### First: 4.6 and earlier, postgres migration required if you have data you need to keep .
If you have a previous version of the hub (4.6 or earlier), migrate your postgres data on your storage mount, so that it
lives underneath a directory matching the value of the subPath clause in your postgres database.

### Second: bring down the hub, and bring it back up.

- Stop all containers for the hub.  You can do this by deleting the deployments, make sure you dont lose any data in the process.
- Follow the directions in this respository, replacing the volume mounts with your original mounts in your old hub.

At this point, your hub should be happily deployed.  Expose its webserver service (or deployment controller) if you havent already, and you can begin scanning.

## Requirements

The hub is extensively tested on kubernetes 1.8 / openshift 3.6.

Other versions are supported as well, so long as all the API constructs in these YAMLs are supported in the corresponding orchestration version.

### Installing the Hub quickly.

All below commands assume:
- you are using the namespace (or openshift project name) 'myhub'.
- you have a cluster with at least 10 cores / 20GB of allocatable memory.
- you have administrative access to your cluster.

### Hub setup instructions

#### If you're in a hurry, skip to the quickstart section:

The quickstart section shows how to quickly get a prototypical hub up and running.

#### Before you start:

Clone this repository, and cd to `install/hub` to run these commands, so the files are local.

#### Step 0:

Make a namespaces/project for your hub:

- For openshift:`oc new-project myhub`
- For kubernetes:`kubectl create ns myhub`

#### Step 1: Setting up service accounts (if you need them).

This may not be necessary for some users, feel free to skip to the *next* section
if you think you don't need to setup any special service accounts (i.e. if you're
running in a namespace that has administrative capabilities).

- First create your service account (Openshift users, use `oc`):
```
kubectl create serviceaccount postgresapp -n myhub
```

 - For openshift: You need to create a service account for the hub, and allow that
user to run processes as user 70.  A generic version of these steps which may
work for you is defined below:
```
oc adm policy add-scc-to-user anyuid system:serviceaccount:myhub:postgres
```

 - *Optional for kubernetes*: You may need to create RBAC bindings with your cluster administrator that allow pods to run as any uid.  Consult with your kubernetes administrator and show them your installation workflow (as defined below) to determine if this is necessary in your cluster.


#### Step 2: Create your cfssl container, and the core hub config map.

Note we may edit the configmap later for external postgres or other settings.  For now, leave it as it is by default, and run these commands (openshift users: use `oc` instead of `kubectl`).

```
kubectl create -f 1-cfssl.yml -n myhub
kubectl create -f 1-cm-hub.yml -n myhub
```

#### Step 3: Choose your postgres database type, and then setup your postgres database

There are two ways to run the hub's postgres database, and we refer to them as *internal*, or *external*.  

Choose internal if you don't care about maintaining your own databse, and are able to run containers as any user in your cluster.

Otherwise, choose external.

*Note: Obviously, you only need to do ONE of the two below steps, before moving on to step 3 ~ choose EITHER Internal OR External database setup!*.

##### Step 3 (INTERNAL database setup option)

If you are okay using an internal database, and are able to run containers as user 70, then you can (in most cases) just start the hub using the snippet of kubectl create statements below.

- Note: the default yaml files don't have persistent volumes.  You will need to replace all emptyDir volumes with a persistentVolumeClaim (or Volume) of your choosing.  1G is enough for all volumes other than postgres.  Postgres should have 100G, to ensure it will have plenty of storage even if you do thousands of scans early on.

- Note: before doing this, there is an initPod that runs as user 0 to set storage permissions.  If you don't want to run it as user 0, and are sure your storage will be writeable by the postgres user, delete that initPod clause entirely.

```
kubectl create -f 2-postgres-db-internal.yml -n myhub
```

That's it, now, skip ahead to step 4!

##### Step 3 (EXTERNAL database setup option)

Note that if you did the internal database setup step, this obviously is not needed.  For a concrete example of this, check the quickstart external db example.

- Note that by 'external' we mean, any postgres other then the official `hub-postgres` image which ships with the blackduck containers.  Our official hub-postgres image bootstraps its own schema, and uses CFSSL for authentication.  In this case, you will have to setup auth and the schema yourself.

- For simplicity, we use an example password below (blackduck123).

So, now lets do our external database setup, in two steps:

1) First lets make sure we create secrets which will match our passwords that we will set in the external database.

```
kubectl create secret generic db-creds --from-literal=blackduck=blackduck123 --from-literal=blackduck_user=blackduck123 -n myhub
```

2) Then, create the `blackduck` and `blackduck_user` users in the database, set their passwords to the ones above, and run the external-postgres-init script on your database to set up the schema.  

3) Finally, edit the `HUB_POSTGRES_HOST` field in the `hub-db-config` configmap to match the DNS name or IP address of your external postgres host (alternatively, use a headless service for advanced users).  Use `kubectl edit cm` or `oc edit cm` to do this.

Your external database is now set up.  Move on to step 4 to install the hub.

#### Step 4: Finally, create the hub app's containers.

You have now set up the main initial containers that the blackduck hub depends on, and set its database up; you can start the rest of the application.  As mentioned earlier, for fully production deployment, you'll want to replace emptyDir's with real storage directories based on your admin's recommendation.  Then all you have to do is create the 3rd yaml file, like so, and the hub will be up and running in a few minutes:

```
#### Done setting up the external DB.
kubectl create -f 3-hub.yml -n myhub
```

If all the above pods are properly scheduled and running, you can then
expose the webserver endpoint, and start using the hub to scan projects.

### Quick start examples: The easiest way to get a hub up and running on your Cloud Native environment.

The following two quick starts show how to get the hub up 'instantly' for a prototype configuration that you can evolve.  
- These are only examples, not 'installers', and should be leveraged by administrators who know what they are doing to quickly grok the hub setup process.  
- Do not assume that running these scripts is a replacement for actually understanding the hub setup/configuration process.
- Building on the points above: Make sure you make any production modifications (volumes, certificates, etc) that you need before running them.  Contact blackduck support if you have questions on how to adopt these scripts to match any special hub configurations you need.

That said: If you're just learning the hub for the first time, these are a great way to get started quickly.  So feel free to dive in and try the quick starts out to get the hub up and running quickly in your cloud native environment!

Openshift users: use `oc` instead of kubectl, and `project` instead of namespace.

#### Kubernetes Internal DB 'quick start' script:

Clone this repository , and cd to `install/hub` to run these commands, so the files are local !

```
#start quickstart-internal
kubectl create ns myhub
kubectl create serviceaccount postgresapp -n myhub
kubectl create -f 1-cfssl.yml -n myhub
kubectl create -f 1-cm-hub.yml -n myhub
kubectl create -f 2-postgres-db-internal.yml -n myhub
until kubectl get pods -n myhub | grep postgres | grep -q Running ; do
     echo "waiting for postgres"
     sleep 5
done
kubectl create -f 3-hub.yml -n myhub
#end quickstart-internal
```

#### External DB 'quick start' script:

Clone this repository , and cd to `install/hub` to run these commands, so the files are local !  Also make sure you can write to tmpfs if running this script.

```
#start quickstart-external
kubectl create ns myhub
kubectl create serviceaccount postgresapp -n myhub
kubectl create -f 1-cfssl.yml -n myhub
kubectl create -f 1-cm-hub.yml -n myhub
kubectl create -f 2-postgres-db-external.yml -n myhub

kubectl create secret generic db-creds --from-literal=blackduck=blackduck123 --from-literal=blackduck_user=blackduck123 -n myhub

# Wait for the pods to come up, you can poll them manually.
until kubectl get pods -n myhub | grep postgres | grep -q Running ; do
     echo "waiting for postgres"
     sleep 5
done
echo "... Postgres found ! Installing DB Schema in 10 seconds ..."
sleep 10
podname=$(kubectl get pods -n myhub | grep postgres | cut -d' ' -f 1)
kubectl get pods -n myhub
kubectl cp external-postgres-init.pgsql myhub/${podname}:/tmp/

#### Setup external db.  Just an example, replace this step with your own custom logic if you want,
cat << EOF > /tmp/pgsetup.sh
        export PATH=/opt/rh/rh-postgresql96/root/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/rh/rh-postgresql96/root/usr/bin/
        export LD_LIBRARY_PATH=/opt/rh/rh-postgresql96/root/usr/lib64
        # initialize the database: RDS or CloudSQL users will implement these steps in their own way.
        psql -a -f  /tmp/external-postgres-init.pgsql
        psql -c "ALTER USER blackduck_user WITH password 'blackduck123'"
        psql -c "ALTER USER blackduck WITH password 'blackduck123'"
EOF
kubectl cp /tmp/pgsetup.sh myhub/${podname}:/tmp/
kubectl exec -n myhub -t -i ${podname} -- sh /tmp/pgsetup.sh
sleep 2
kubectl create -f 3-hub.yml -n myhub
#end quickstart-external
```

### After deployment: Consider using Auto scaling.

- `kubectl create -f autoscale.yml` will ensure that you always have enough jobrunners and scan service runners to keep up with your dynamic workload.

### Fine tune your configuration

There are several ways to fine tune your configuration.  Some may be essential
to your organizations use of the hub (for example, external proxys might be needed).

- External databases: These are not necessary for any particular scenario, but
might be a preference.
- External proxies: For datacenters that are airgapped.
- Custom nginx certificates: So you can use trusted internal TLS certs to access the hub.
- Scaling to 100s, 1000s, or more of scans: configuration.

There are several options that can be configured in the yml files for Kubernetes/Openshift as described below.  We use kubernetes and openshift interchangeably for these, as the changes are agnostic to the underlying orchestration.

*We go through them below*

#### I want to run the hub with no security context constraints.

Follow the "external configured database" directions above.  Use either your own
postgres, or, you can use any postgres container as exemplified.

#### I want custom hostnames, ports, and proxys for the hub-nginx container.

##### Host Name Modification

When the web server starts up, if it does not have certificates configured it will generate an HTTPS certificate.

Configuration is needed to tell the web server which real host name it listens on so that the host names can match.

Otherwise the certificate will only have the service name to use as the host name.

To modify the real host name, edit the pods.env file to update the desired host name value.

##### Port Modification

The web server is configured with a host to container port mapping.  If a port change is desired, the port mapping should be modified along with the associated configuration.

To modify the host port, edit the port mapping as well as the "hub webserver" section in the pods.env file to update the desired host and/or container port value.

If the container port is modified, any health check URL references should also be modified using the updated container port value.

#### Proxy Settings

There are currently several services that need access to services hosted by Black Duck Software:

* authentication
* jobrunner
* registration
* scan
* webapp

If a proxy is required for external internet access, you'll need to configure it.

1. Edit the "hub proxy" section in 2-cm-hub.yml.template
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

#### Using a Custom web server certificate-key pair

The Hub allows users to use their own web server certificate-key pairs for establishing ssl connection.

* Create a Kubernetes secret each called 'WEBSERVER_CUSTOM_CERT_FILE' and 'WEBSERVER_CUSTOM_KEY_FILE' with the custom certificate and custom key in your namespace.

You can do so by

```
kubectl secret create WEBSERVER_CUSTOM_CERT_FILE --from-file=<certificate file>
kubectl secret create WEBSERVER_CUSTOM_KEY_FILE --from-file=<key file>
```

For the webserver service, add secrets by copying their values into 'env'
values for the pod specifications in the webserver.

##### Hub Reporting Database

The Hub ships with a reporting database. The database port will be exposed to the Kubernetes network for connections to the reporting user and reporting database.

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
4. Add your passwords for the blackduck_user and the admin user to a secret like so (openshift users: kubectl and oc are interchangeable)

```
cat << EOF | kubectl -n myhub create -f -  
apiVersion: v1
data:
  HUB_POSTGRES_ADMIN_PASSWORD_FILE: |
    "$pg_pass_admin"
  HUB_POSTGRES_USER_PASSWORD_FILE: |
    "$pg_pass_user"
kind: Secret
metadata:
  name: postgres-secret
EOF
```

### How To Expose kubernetes/openshift Services

Your cluster administrator will have the final say in how you expose the hub to the outside world.

Some common patterns are listed below.

#### Cloud load balancers vs. NodePorts

The simplest way to expose the hub for a simple POC, or for a cloud based cluster, is via
a cloud load balancer.  

- `kubebctl expose --type=Loadbalancer` will work in a large cloud like GKE or certain AWS clusters.
- `kubectl expose --type=NodePort` is a good solution for small clusters: And you can use your
API Server's port to access the hubb.  IF you use this option, make sure to export `HUB_WEBSERVER_HOST` and
`HUB_WEBSERVER_PORT` as needed.

For example, a typical invocation to expose the hub might be:

```
 kubectl expose --namespace=default deployment webserver --type=LoadBalancer --port=443 --target-port=8443 --name=nginx-gateway
```

#### Openshift routers

Your administrator can help you define a route if you're using openshift.  Make sure to turn on TLS
passthrough if going down this road.  You will then likely access your cluster at a URL that openshift
defined for you, available in the `Routes` UI of your openshift console's webapp.

#### Testing an exposed hub

```
kubectl get services -o wide -n myhub
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


### More fine tuning

We conclude with more recipes for fine tuning your hub configuration.  Note that it's
advisable that you first get a simple hub up and running before adopting these tuning snippets.

#### NGINX TLS Configuration details.

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
containers is shown in the 2-cm-hub-yml file.

```
PUBLIC_HUB_WEBSERVER_HOST=hub.my.company
PUBLIC_HUB_WEBSERVER_PORT=14085
volumeMounts:
- mountPath: /run/secrets
  name: dir-certs
+-----------------------+            
|                       |        
|    nginx (webserver)  |        HUB_PROXY_SCHEME=https           
|                       |        HUB_PROXY_HOST=proxy.my.company  HUB_PROXY_SCHEME=https
+-----------+-----------|        HUB_PROXY_PORT=8080              HUB_PROXY_HOST=proxy.my.company
            |                    +-------------------+            HUB_PROXY_PORT=8080
            |                    |                   |         +--------------+
            +--------------------+                   |         |   jobrunner  |
                                 |   wwebapp         |         +-+------------+
                                 |                   |              |
 HUB_PROXY_HOST=proxy.my.company +--------------------       +------+
 HUB_PROXY_PORT=8080                  |                      |
      +---------------+               |                      |
      |  registration |               |   +------+           |
      +---------------+               +---+ psql +-----------+
                                          +------+
```
