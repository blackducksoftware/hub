# Black Duck Helm Chart

This chart bootstraps **Black Duck** deployment on a **Kubernetes** cluster using the **Helm** package manager. 

>NOTE: This document describes a **quickstart** process of installing a basic deployment. For more configuration options, please refer to the Kubernetes documentation.

## Prerequisites

* Kubernetes 1.16+
    * A `storageClass`[^1][^2] configured that allows persistent volumes. 
* Helm 3
* Adding the Synopsys repository to your local Helm repository:

```bash
$ helm repo add synopsys https://sig-repo.synopsys.com/artifactory/sig-cloudnative
```

## Installing the Chart

### Save the chart locally

To save the chart on your machine, run the following command

```bash
$ helm pull synopsys/blackduck -d <DESTINATION_FOLDER> --untar
```

This will extract the charts to the specified folder (as denoted by the `-d` flag in the above command), which contains the necessary files to deploy the application.

> NOTE: Deploying the application directly from the chart repository will result in the system being deployed without appropriate sizing files, therefore, it is recommended to deploy with the chart files saved locally.

### Create a Namespace

```bash
$ BD_NAME="bd"
$ kubectl create ns ${BD_NAME}
```

### Create a custom TLS Secret (Optional)

Note: It's common to provide a custom web server TLS secret before installing the Black Duck Helm chart. Create the secret with the command below:

```bash
$ BD_NAME="bd"
$ kubectl create secret generic ${BD_NAME}-blackduck-webserver-certificate -n ${BD_NAME} --from-file=WEBSERVER_CUSTOM_CERT_FILE=tls.crt --from-file=WEBSERVER_CUSTOM_KEY_FILE=tls.key
```

Next, update the following block in `values.yaml`, ensuring to uncomment the `tlsCertSecretName` value (tls.crt and tls.key files are required). If the value `tlsCertSecretName` is not provided then Black Duck will generate its own certificates.

```yaml
# TLS certificate for Black Duck
# create a generic secret using the following command
# kubectl create secret generic -n <namespace> <name>-blackduck-webserver-certificate --from-file=WEBSERVER_CUSTOM_CERT_FILE=tls.crt --from-file=WEBSERVER_CUSTOM_KEY_FILE=tls.key
tlsCertSecretName: ${BD_NAME}-blackduck-webserver-certificate
```

> NOTE: This step is not required where TLS termination is being handled upstream from the application (i.e. via an ingress resource).

## Configure your Black Duck Instance

### Choosing an appropriate deployment size

Black Duck provides several pre-configured **scans-per-hour** yaml files to help with sizing your deployment appropriately[^3]. These have been tested by our performance lab using real-world configurations. However, they are not "one size fits all", therefore, if you plan to run large amounts BDBA scans, snippet scans or reports, please reach out to your Synopsys CSM for assistance in determining a custom sizing tier.

As of 2024.4.x, GEN04 sizing files should be used
> NOTE: The 10sph.yaml files are not intended for production purposes and should **not** be deployed for anything outside of local testing.

### Configurating persistent storage

Black Duck requires certain data to be persisted to disk. Therefore, an appropriate `storageClass` should be utilized within your install[^1][^2]. If your cluster does not have a default `storageClass`, or you wish to override it, update the following parameters:

```yaml
# it will apply to all PVC's storage class but it can be override at container level
storageClass:
```

### Database Configuration

If you choose to use an external postgres instance (default configuration), you will need to configure the following parameters in values.yaml:

 ```yaml
 postgres.host: ""
 postgres.adminUsername: ""
 postgres.adminPassword: ""
 postgres.userUsername: ""
 postgres.userPassword: ""
``` 

> NOTE: it is important that the specificiations of the database deployment meets the appriopriate size tier. Some tuning parameters are available at the following [link]("https://sig-product-docs.synopsys.com/bundle/blackduck-compatibility/page/topics/Black-Duck-Hardware-Scaling-Guidelines.html")

If you choose to utilize the containerized PostgreSQL instance, set the following parameter to false:

```yaml
postgres.isExternal: true
```

> NOTE: Regardless of whatever database deployment method you choose, ensure that you regularly perform backups and periodically verify the integrity of those backups.


## Exposing the Black Duck User Interface (UI)

The Black Duck User Interface (UI) can be accessed via several methods, described below

### NodePort

`NodePort` is the default service type set in the values.yaml. If you want to use a **custom NodePort**, then you should set the following parameters in the values file to whatever port is to be used:

```yaml
# Expose Black Duck's User Interface
exposeui: true
# possible values are NodePort, LoadBalancer or OpenShift (in case of routes)
exposedServiceType: NodePort
# custom port to expose the NodePort service on
exposedNodePort: "<NODE_PORT_TO_BE_USED>"
```

You can access the Black Duck UI via `https://${NODE_IP}:${NODE_PORT}`

### Load balancer

Setting the `exposedServiceType` to LoadBalancer in the values.yaml, will instruct Kubernetes to deploy an external Load Balancer service

You can use the following command to get the external IP address of the Black Duck web server

```bash
$ kubectl get services ${BD_NAME}-blackduck-webserver-exposed -n ${BD_NAME}
``` 

**Note:** If the external IP address is shown as `pending`, wait for a minute and enter the same command again.

You can access the Black Duck UI by `https://${EXTERNAL_IP}`

### Ingress

This is typically the most common method of exposing the application to users. Firstly, set `exposeui` in the values.yaml to `false` since the ingress will route to the service.

```yaml
# Expose Black Duck's User Interface
exposeui: false
```

A typical ingress manifest would be representative of the example below. Note, the configuration of the ingress controller and TLS certificates themselves are outside of the scope of this guide.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${BD_NAME}-blackduck-webserver-exposed
  namespace: ${BD_NAME}
spec:
  rules:
  - host: blackduck.foo.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${BD_NAME}-blackduck-webserver
            port:
              number: 443
  ingressClassName: nginx
```

Once deployed, the UI will be available on port 443 on the Public IP of your ingress controller.

### OpenShift

Setting the `exposedServiceType` to OpenShift in the values.yaml, will instruct OpenShift to deploy route service

```yaml
# Expose Black Duck's User Interface
exposeui: true
# possible values are NodePort, LoadBalancer or OpenShift (in case of routes)
exposedServiceType: OpenShift
```

you can use the following command to get the OpenShift routes

```bash
$ oc get routes ${BD_NAME}-blackduck -n ${BD_NAME} 
```

You can access the Black Duck UI by `https://${ROUTE_HOST}`

## Install the Black Duck Chart

```bash
$ BD_NAME="bd" && BD_SIZE="sizes-gen04/120sph" && BD_INSTALL_DIR="<DESTINATION_FOLDER>/blackduck/"
$ helm install ${BD_NAME} ${BD_INSTALL_DIR} --namespace ${BD_NAME} -f ${BD_INSTALL_DIR}/values.yaml -f ${BD_INSTALL_DIR}/${BD_SIZE}.yaml
```

> **Tip**: List all releases using `helm list` and list all specified values using `helm get values RELEASE_NAME`

> **Note**: You must not use the `--wait` flag when you install the Helm Chart. `--wait` waits for all pods to become Ready before marking the **Install** as
> done. However the pods will not become Ready until the postgres-init job is run during the **Post-Install**. Therefore the **Install** will never finish.

Alternatively, Black Duck can be deployed using `kubectl apply` by generating a dry run manifest from Helm

```bash
$ BD_NAME="bd" && BD_SIZE="sizes-gen04/120sph" && BD_INSTALL_DIR="<DESTINATION_FOLDER>/blackduck/"
$ helm install ${BD_NAME} ${BD_INSTALL_DIR} --namespace ${BD_NAME} -f ${BD_INSTALL_DIR}/values.yaml -f ${BD_INSTALL_DIR}/${BD_SIZE}.yaml --dry-run=client > ${BD_NAME}.yaml

# install the manifest
$ kubectl apply -f ${BD_NAME}.yaml --validate=false
```

## Uninstalling the Chart

To uninstall/delete the deployment:

```bash
$ helm uninstall ${BD_NAME} --namespace ${BD_NAME}
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

If you have used `kubectl` to install from a dry-run as shown above, the following command will remove the install

```bash
kubectl delete -f ${BD_NAME}.yaml
```

## Upgrading the Chart

Before upgrading to new version, please make sure to run the below command to pull the latest version of charts from chart museum

```bash
$ helm repo update

$ helm pull synopsys/blackduck -d <DESTINATION_FOLDER> --untar
```

## Updating the Chart

To update the deployment:

```bash
$ BD_NAME="bd" && BD_SIZE="sizes-gen04/120sph"
$ helm upgrade ${BD_NAME} ${BD_INSTALL_DIR} --namespace ${BD_NAME} -f ${BD_INSTALL_DIR}/values.yaml -f ${BD_INSTALL_DIR}/${BD_SIZE}.yaml
```

if you have used `kubectl apply` as shown above to perform the initial install, re-run the command with the newly generated dry-run yaml.

## Configuration

The following table lists the configurable parameters of the Black Duck chart and their default values.

**Note**: Do not set the following parameters in the environs flag. Instead, use their respective flags.

    Use dataRetentionInDays, enableSourceCodeUpload and maxTotalSourceSizeinMB for the following:
    * DATA_RETENTION_IN_DAYS
    * ENABLE_SOURCE_UPLOADS
    * MAX_TOTAL_SOURCE_SIZE_MB

    Use enableAlert, alertName and alertNamespace for the following:
    * USE_ALERT
    * HUB_ALERT_HOST
    * HUB_ALERT_PORT

    Use exposedNodePort and exposedServiceType for the following:
    * PUBLIC_HUB_WEBSERVER_PORT

    Use postgres.isExternal and postgres.ssl for the following:
    * HUB_POSTGRES_ENABLE_SSL
    * HUB_POSTGRES_ENABLE_SSL_CERT_AUTH

    Use enableIPV6 for the following:
    * IPV4_ONLY

### Common Configuration

| Parameter                  | Description                                                                                                                                                    | Default                                                                                                                                                                                    |
|----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `registry`                 | Image repository                                                                                                                                               | `docker.io/blackducksoftware`                                                                                                                                                              |
| `imageTag`                 | Version of Black Duck                                                                                                                                          | `2024.7.0`                                                                                                                                                                                |
| `imagePullSecrets`         | Reference to one or more secrets to be used when pulling images                                                                                                | `[]`                                                                                                                                                                                       |
| `tlsCertSecretName`        | Name of Webserver TLS Secret containing Certificates (if not provided Certificates will be generated)                                                          |                                                                                                                                                                                            |
| `exposeui`                 | Enable Black Duck Web Server User Interface (UI)                                                                                                               | `true`                                                                                                                                                                                     |
| `exposedServiceType`       | Expose Black Duck Web Server Service Type                                                                                                                      | `NodePort`                                                                                                                                                                                 |
| `enablePersistentStorage`  | If true, Black Duck will have persistent storage                                                                                                               | `true`                                                                                                                                                                                     |
| `storageClass`             | Global storage class to be used in all Persistent Volume Claim                                                                                                 |                                                                                                                                                                                            |
| `enableLivenessProbe`      | If true, Black Duck will have liveness probe                                                                                                                   | `true`                                                                                                                                                                                     |
| `enableInitContainer`      | If true, Black Duck will initialize the required databases                                                                                                     | `true`                                                                                                                                                                                     |
| `enableSourceCodeUpload`   | If true, source code upload will be enabled by setting in the environment variable (this takes priority over environs flag values)                             | `false`                                                                                                                                                                                    |
| `dataRetentionInDays`      | Source code upload's data retention in days                                                                                                                    | `180`                                                                                                                                                                                      |
| `maxTotalSourceSizeinMB`   | Source code upload's maximum total source size in MB                                                                                                           | `4000`                                                                                                                                                                                     |
| `enableBinaryScanner`      | If true, binary analysis will be enabled by deploying the binary scan worker                                                                                   | `false`                                                                                                                                                                                    |
| `enableIntegration`        | If true, blackduck integration will be enabled by setting in the environment variable (this takes priority over environs flag values)                          | `false`                                                                                                                                                                                    |
| `enableAlert`              | If true, the Black Duck Alert service will be added to the nginx configuration with the environ  `"HUB_ALERT_HOST:<blackduck_name>-alert.<blackduck_name>.svc` | `false`                                                                                                                                                                                    |
| `enableIPV6`               | If true, IPV6 support will be enabled by setting in the environment variable (this takes priority over environs flag values)                                   | `true`                                                                                                                                                                                     |
| `certAuthCACertSecretName` | Own Certificate Authority (CA) for Black Duck Certificate Authentication                                                                                       | `run this command "kubectl create secret generic -n <namespace> <name>-blackduck-auth-custom-ca --from-file=AUTH_CUSTOM_CA=ca.crt" and provide the secret name`                            |
| `proxyCertSecretName`      | Black Duck proxy server’s Certificate Authority (CA)                                                                                                           | `run this command "kubectl create secret generic -n <namespace> <name>-blackduck-proxy-certificate --from-file=HUB_PROXY_CERT_FILE=proxy.crt" and provide the secret name`                 |
| `proxyPasswordSecretName`  | Black Duck proxy password secret                                                                                                                               | `run this command "kubectl create secret generic -n <namespace> <name>-blackduck-proxy-password --from-file=HUB_PROXY_PASSWORD_FILE=proxy_password_file" and provide the secret name`      |
| `ldapPasswordSecretName`   | Black Duck LDAP password secret                                                                                                                                | `run this command "kubectl create secret generic -n <namespace> <name>-blackduck-ldap-password --from-file=LDAP_TRUST_STORE_PASSWORD_FILE=ldap_password_file" and provide the secret name` |
| `environs`                 | environment variables that need to be added to Black Duck configuration                                                                                        | `map e.g. if you want to set PUBLIC_HUB_WEBSERVER_PORT, then it should be --set environs.PUBLIC_HUB_WEBSERVER_PORT=30269`                                                                  |

### Postgres Pod Configuration

| Parameter                                | Description                                                                                                    | Default                        |
|------------------------------------------|----------------------------------------------------------------------------------------------------------------|--------------------------------|
| `postgres.registry`                      | Image repository                                                                                               | `docker.io/centos`             |
| `postgres.isExternal`                    | If true, External PostgreSQL will be used                                                                      | `true`                         |
| `postgres.host`                          | PostgreSQL host (required only if external PostgreSQL is used)                                                 |                                |
| `postgres.port`                          | PostgreSQL port                                                                                                | `5432`                         |
| `postgres.pathToPsqlInitScript`          | Full file path of the PostgreSQL initialization script                                                         | `external-postgres-init.pgsql` |
| `postgres.ssl`                           | PostgreSQL SSL                                                                                                 | `true`                         |
| `postgres.adminUserName`                 | PostgreSQL admin username                                                                                      | `postgres`                     |
| `postgres.adminPassword`                 | PostgreSQL admin user password                                                                                 | `testPassword`                 |
| `postgres.userUserName`                  | PostgreSQL non admin username                                                                                  | `blackduck_user`               |
| `postgres.userPassword`                  | PostgreSQL non admin user password                                                                             | `testPassword`                 |
| `postgres.resources.requests.cpu`        | PostgreSQL container CPU request (if external postgres is not used)                                            | `1000m`                        |
| `postgres.resources.requests.memory`     | PostgreSQL container Memory request (if external postgres is not used)                                         | `3072Mi`                       |
| `postgres.persistentVolumeClaimName`     | Point to an existing PostgreSQL Persistent Volume Claim (PVC) (if external postgres is not used)               |                                |
| `postgres.claimSize`                     | PostgreSQL Persistent Volume Claim (PVC) claim size (if external postgres is not used)                         | `150Gi`                        |
| `postgres.storageClass`                  | PostgreSQL Persistent Volume Claim (PVC) storage class (if external postgres is not used)                      |                                |
| `postgres.volumeName`                    | Point to an existing PostgreSQL Persistent Volume (PV) (if external postgres is not used)                      |                                |
| `postgres.confPersistentVolumeClaimName` | Point to an existing PostgreSQL configuration Persistent Volume Claim (PVC) (if external postgres is not used) |                                |
| `postgres.confClaimSize`                 | PostgreSQL configuration Persistent Volume Claim (PVC) claim size (if external postgres is not used)           | `5Mi`                          |
| `postgres.confStorageClass`              | PostgreSQL configuration Persistent Volume Claim (PVC) storage class (if external postgres is not used)        |                                |
| `postgres.confVolumeName`                | Point to an existing PostgreSQL configuration Persistent Volume (PV) (if external postgres is not used)        |                                |
| `postgres.nodeSelector`                  | PostgreSQL node labels for pod assignment                                                                      | `{}`                           |
| `postgres.tolerations`                   | PostgreSQL node tolerations for pod assignment                                                                 | `[]`                           |
| `postgres.affinity`                      | PostgreSQL node affinity for pod assignment                                                                    | `{}`                           |
| `postgres.podSecurityContext`            | PostgreSQL security context at pod level                                                                       | `{}`                           |
| `postgres.securityContext`               | PostgreSQL security context at container level                                                                 | `{}`                           |

### Postgres Upgrade Job Configuration

| Parameter                             | Description                                           | Default |
|---------------------------------------|-------------------------------------------------------|---------|
| `postgresUpgrader.registry`           | Image repository                                      |         |
| `postgresUpgrader.podSecurityContext` | Postgres upgrader security context at job level       | `{}`    |
| `postgresUpgrader.securityContext`    | Postgres upgrader security context at container level | `{}`    |

### Postgres Readiness Check Init Container Configuration

| Parameter                           | Description                                            | Default |
|-------------------------------------|--------------------------------------------------------|---------|
| `postgresWaiter.registry`           | Image repository                                       |         |
| `postgresWaiter.podSecurityContext` | Postgres readiness check security context at pod level | `{}`    |
| `postgresWaiter.securityContext`    | Postgres readiness check context at container level    | `{}`    |

### Authentication Pod Configuration

| Parameter                                  | Description                                                       | Default  |
|--------------------------------------------|-------------------------------------------------------------------|----------|
| `authentication.registry`                  | Image repository to be override at container level                |          |
| `authentication.resources.limits.memory`   | Authentication container Memory Limit                             | `1024Mi` |
| `authentication.resources.requests.memory` | Authentication container Memory request                           | `1024Mi` |
| `authentication.maxRamPercentage`          | Authentication container maximum heap size                        | `90`     |
| `authentication.persistentVolumeClaimName` | Point to an existing Authentication Persistent Volume Claim (PVC) |          |
| `authentication.claimSize`                 | Authentication Persistent Volume Claim (PVC) claim size           | `2Gi`    |
| `authentication.storageClass`              | Authentication Persistent Volume Claim (PVC) storage class        |          |
| `authentication.volumeName`                | Point to an existing Authentication Persistent Volume (PV)        |          |
| `authentication.nodeSelector`              | Authentication node labels for pod assignment                     | `{}`     |
| `authentication.tolerations`               | Authentication node tolerations for pod assignment                | `[]`     |
| `authentication.affinity`                  | Authentication node affinity for pod assignment                   | `{}`     |
| `authentication.podSecurityContext`        | Authentication security context at pod level                      | `{}`     |
| `authentication.securityContext`           | Authentication security context at container level                | `{}`     |

### BOM Engine Pod Configuration

| Parameter                             | Description                                        | Default  |
|---------------------------------------|----------------------------------------------------|----------|
| `bomengine.registry`                  | Image repository to be override at container level |          |
| `bomengine.resources.limits.memory`   | BOM Engine container Memory Limit                  | `1024Mi` |
| `bomengine.resources.requests.memory` | BOM Engine container Memory request                | `1024Mi` |
| `bomengine.maxRamPercentage`          | BOM Engine container maximum heap size             | `90`     |
| `bomengine.nodeSelector`              | BOM Engine node labels for pod assignment          | `{}`     |
| `bomengine.tolerations`               | BOM Engine node tolerations for pod assignment     | `[]`     |
| `bomengine.affinity`                  | BOM Engine node affinity for pod assignment        | `{}`     |
| `bomengine.podSecurityContext`        | BOM Engine security context at pod level           | `{}`     |
| `bomengine.securityContext`           | BOM Engine security context at container level     | `{}`     |

### Binary Scanner Pod Configuration

| Parameter                                 | Description                                        | Default                  |
|-------------------------------------------|----------------------------------------------------|--------------------------|
| `binaryscanner.registry`                  | Image repository to be override at container level | `docker.io/sigsynopsys`  |
| `binaryscanner.imageTag`                  | Image tag to be override at container level        | `2024.6.2` |
| `binaryscanner.resources.limits.Cpu`      | Binary Scanner container CPU Limit                 | `1000m`                  |
| `binaryscanner.resources.requests.Cpu`    | Binary Scanner container CPU request               | `1000m`                  |
| `binaryscanner.resources.limits.memory`   | Binary Scanner container Memory Limit              | `2048Mi`                 |
| `binaryscanner.resources.requests.memory` | Binary Scanner container Memory request            | `2048Mi`                 |
| `binaryscanner.nodeSelector`              | Binary Scanner node labels for pod assignment      | `{}`                     |
| `binaryscanner.tolerations`               | Binary Scanner node tolerations for pod assignment | `[]`                     |
| `binaryscanner.affinity`                  | Binary Scanner node affinity for pod assignment    | `{}`                     |
| `binaryscanner.podSecurityContext`        | Binary Scanner security context at pod level       | `{}`                     |
| `binaryscanner.securityContext`           | Binary Scanner security context at container level | `{}`                     |

### CFSSL Pod Configuration

| Parameter                         | Description                                              | Default          |
|-----------------------------------|----------------------------------------------------------|------------------|
| `cfssl.registry`                  | Image repository to be override at container level       |                  |
| `cfssl.imageTag`                  | Image tag to be override at container level              | `1.0.28` |
| `cfssl.resources.limits.memory`   | Cfssl container Memory Limit                             | `640Mi`          |
| `cfssl.resources.requests.memory` | Cfssl container Memory request                           | `640Mi`          |
| `cfssl.persistentVolumeClaimName` | Point to an existing Cfssl Persistent Volume Claim (PVC) |                  |
| `cfssl.claimSize`                 | Cfssl Persistent Volume Claim (PVC) claim size           | `2Gi`            |
| `cfssl.storageClass`              | Cfssl Persistent Volume Claim (PVC) storage class        |                  |
| `cfssl.volumeName`                | Point to an existing Cfssl Persistent Volume (PV)        |                  |
| `cfssl.nodeSelector`              | Cfssl node labels for pod assignment                     | `{}`             |
| `cfssl.tolerations`               | Cfssl node tolerations for pod assignment                | `[]`             |
| `cfssl.affinity`                  | Cfssl node affinity for pod assignment                   | `{}`             |
| `cfssl.podSecurityContext`        | Cfssl security context at pod level                      | `{}`             |
| `cfssl.securityContext`           | Cfssl security context at container level                | `{}`             |

### Documentation Pod Configuration

| Parameter                                 | Description                                        | Default |
|-------------------------------------------|----------------------------------------------------|---------|
| `documentation.registry`                  | Image repository to be override at container level |         |
| `documentation.resources.limits.memory`   | Documentation container Memory Limit               | `512Mi` |
| `documentation.resources.requests.memory` | Documentation container Memory request             | `512Mi` |
| `documentation.maxRamPercentage         ` | Documentation container Memory request             | `90` |
| `documentation.nodeSelector`              | Documentation node labels for pod assignment       | `{}`    |
| `documentation.tolerations`               | Documentation node tolerations for pod assignment  | `[]`    |
| `documentation.affinity`                  | Documentation node affinity for pod assignment     | `{}`    |
| `documentation.podSecurityContext`        | Documentation security context at pod level        | `{}`    |
| `documentation.securityContext`           | Documentation security context at container level  | `{}`    |

### Job runner Pod Configuration

| Parameter                             | Description                                        | Default  |
|---------------------------------------|----------------------------------------------------|----------|
| `jobrunner.registry`                  | Image repository to be override at container level |          |
| `jobrunner.replicas`                  | Job runner Pod Replica Count                       | `1`      |
| `jobrunner.resources.limits.cpu`      | Job runner container CPU Limit                     | `1000m`  |
| `jobrunner.resources.requests.cpu`    | Job runner container CPU request                   | `1000m`  |
| `jobrunner.resources.limits.memory`   | Job runner container Memory Limit                  | `4608Mi` |
| `jobrunner.resources.requests.memory` | Job runner container Memory request                | `4608Mi` |
| `jobrunner.maxRamPercentage`          | Job runner container maximum heap size             | `90`     |
| `jobrunner.nodeSelector`              | Job runner node labels for pod assignment          | `{}`     |
| `jobrunner.tolerations`               | Job runner node tolerations for pod assignment     | `[]`     |
| `jobrunner.affinity`                  | Job runner node affinity for pod assignment        | `{}`     |
| `jobrunner.podSecurityContext`        | Job runner security context at pod level           | `{}`     |
| `jobrunner.securityContext`           | Job runner security context at container level     | `{}`     |

### MATCH Engine Pod Configuration

| Parameter                               | Description                                        | Default  |
|-----------------------------------------|----------------------------------------------------|----------|
| `matchengine.registry`                  | Image repository to be override at container level |          |
| `matchengine.resources.limits.memory`   | MATCH Engine container Memory Limit                | `4608Mi` |
| `matchengine.resources.requests.memory` | MATCH Engine container Memory request              | `4608Mi` |
| `matchengine.maxRamPercentage`          | MATCH Engine maximum heap size                     | `90`     |
| `matchengine.nodeSelector`              | MATCH Engine node labels for pod assignment        | `{}`     |
| `matchengine.tolerations`               | MATCH Engine node tolerations for pod assignment   | `[]`     |
| `matchengine.affinity`                  | MATCH Engine node affinity for pod assignment      | `{}`     |
| `matchengine.podSecurityContext`        | MATCH Engine security context at pod level         | `{}`     |
| `matchengine.securityContext`           | MATCH Engine security context at container level   | `{}`     |

### RabbitMQ Pod Configuration

| Parameter                            | Description                                        | Default             |
|--------------------------------------|----------------------------------------------------|---------------------|
| `rabbitmq.registry`                  | Image repository to be override at container level |                     |
| `rabbitmq.imageTag`                  | Image tag to be override at container level        | `1.2.39` |
| `rabbitmq.resources.limits.memory`   | RabbitMQ container Memory Limit                    | `1024Mi`            |
| `rabbitmq.resources.requests.memory` | RabbitMQ container Memory request                  | `1024Mi`            |
| `rabbitmq.nodeSelector`              | RabbitMQ node labels for pod assignment            | `{}`                |
| `rabbitmq.tolerations`               | RabbitMQ node tolerations for pod assignment       | `[]`                |
| `rabbitmq.affinity`                  | RabbitMQ node affinity for pod assignment          | `{}`                |
| `rabbitmq.podSecurityContext`        | RabbitMQ security context at pod level             | `{}`                |
| `rabbitmq.securityContext`           | RabbitMQ security context at container level       | `{}`                |

### Redis Pod Configuration

| Parameter                         | Description                                                                                                         | Default  |
|-----------------------------------|---------------------------------------------------------------------------------------------------------------------|----------|
| `redis.registry`                  | Image repository to be override at container level                                                                  |          |
| `redis.resources.limits.memory`   | Redis container Memory Limit                                                                                        | `1024Mi` |
| `redis.resources.requests.memory` | Redis container Memory request                                                                                      | `1024Mi` |
| `redis.tlsEnalbed`                | Enable TLS connections between client and Redis                                                                     | `false`  |
| `redis.maxTotal`                  | Maximum number of concurrent client connections that can be connected to Redis                                      | `128`    |
| `redis.maxIdle`                   | Maximum number of concurrent client connections that can remain idle in the pool, without extra ones being released | `128`    |
| `redis.nodeSelector`              | Redis node labels for pod assignment                                                                                | `{}`     |
| `redis.tolerations`               | Redis node tolerations for pod assignment                                                                           | `[]`     |
| `redis.affinity`                  | Redis node affinity for pod assignment                                                                              | `{}`     |
| `redis.podSecurityContext`        | Redis security context at pod level                                                                                 | `{}`     |
| `redis.securityContext`           | Redis security context at container level                                                                           | `{}`     |

### Registration Pod Configuration

| Parameter                                | Description                                                     | Default  |
|------------------------------------------|-----------------------------------------------------------------|----------|
| `registration.registry`                  | Image repository to be override at container level              |          |
| `registration.requestCpu`                | Registration container CPU request                              | `1000m`  |
| `registration.resources.limits.memory`   | Registration container Memory Limit                             | `1024Mi` |
| `registration.resources.requests.memory` | Registration container Memory request                           | `1024Mi` |
| `registration.maxRamPercentage`          | Registration container maximum heap size                        | `90`     |
| `registration.persistentVolumeClaimName` | Point to an existing Registration Persistent Volume Claim (PVC) |          |
| `registration.claimSize`                 | Registration Persistent Volume Claim (PVC) claim size           | `2Gi`    |
| `registration.storageClass`              | Registration Persistent Volume Claim (PVC) storage class        |          |
| `registration.volumeName`                | Point to an existing Registration Persistent Volume (PV)        |          |
| `registration.nodeSelector`              | Registration node labels for pod assignment                     | `{}`     |
| `registration.tolerations`               | Registration node tolerations for pod assignment                | `[]`     |
| `registration.affinity`                  | Registration node affinity for pod assignment                   | `{}`     |
| `registration.podSecurityContext`        | Registration security context at pod level                      | `{}`     |
| `registration.securityContext`           | Registration security context at container level                | `{}`     |

### Scan Pod Configuration

| Parameter                        | Description                                        | Default  |
|----------------------------------|----------------------------------------------------|----------|
| `scan.registry`                  | Image repository to be override at container level |          |
| `scan.replicas`                  | Scan Pod Replica Count                             | `1`      |
| `scan.resources.limits.memory`   | Scan container Memory Limit                        | `2560Mi` |
| `scan.resources.requests.memory` | Scan container Memory request                      | `2560Mi` |
| `scan.maxRamPercentage`          | Scan container maximum heap size                   | `90`     |
| `scan.nodeSelector`              | Scan node labels for pod assignment                | `{}`     |
| `scan.tolerations`               | Scan node tolerations for pod assignment           | `[]`     |
| `scan.affinity`                  | Scan node affinity for pod assignment              | `{}`     |
| `scan.podSecurityContext`        | Scan security context at pod level                 | `{}`     |
| `scan.securityContext`           | Scan security context at container level           | `{}`     |

### Storage Pod Configuration

| Parameter                           | Description                                                                                                              | Default  |
|-------------------------------------|--------------------------------------------------------------------------------------------------------------------------|----------|
| `storage.registry`                  | Image repository to be override at container level                                                                       |          |
| `storage.requestCpu`                | Storage container CPU request                                                                                            | `1000m`  |
| `storage.resources.limits.memory`   | Storage container Memory Limit                                                                                           | `2048Mi` |
| `storage.resources.requests.memory` | Storage container Memory request                                                                                         | `2048Mi` |
| `storage.maxRamPercentage         ` | Storage container maximum heap size                                                                                      | `60    ` |
| `storage.persistentVolumeClaimName` | Point to an existing Storage Persistent Volume Claim (PVC)                                                               |          |
| `storage.claimSize`                 | Storage Persistent Volume Claim (PVC) claim size                                                                         | `100Gi`  |
| `storage.storageClass`              | Storage Persistent Volume Claim (PVC) storage class                                                                      |          |
| `storage.volumeName`                | Point to an existing Storage Persistent Volume (PV)                                                                      |          |
| `storage.nodeSelector`              | Storage node labels for pod assignment                                                                                   | `{}`     |
| `storage.tolerations`               | Storage node tolerations for pod assignment                                                                              | `[]`     |
| `storage.affinity`                  | Storage node affinity for pod assignment                                                                                 | `{}`     |
| `storage.podSecurityContext`        | Storage security context at pod level                                                                                    | `{}`     |
| `storage.securityContext`           | Storage security context at container level                                                                              | `{}`     |
| `storage.providers`                 | Configuration to support multiple storage platforms. Please refer to *Storage Providers* section for additional details. | `[]`     |

#### Storage Providers

Provider in storage service refers to a persistence type and its configuration. Blackduck manages tools, application reports and other large blobs under storage
service. Currently, it supports only the filesystem as one of the provider.

Provider configuration,

```
storage:
  providers:
    - name: <name-for-the-provider> <String>
      enabled: <flag-to-enable/disable-provider> <Boolean>
      index: <index-value-for-the-provider> <Integer>
      type: <storage-type> <String>
      preference: <weightage-for-the-provider> <Integer>
      existingPersistentVolumeClaimName: <existing-persistence-volume-claim-name> <String>
      pvc:
        size: <size-of-the-persistence-disk> <String>
        storageClass: <storage-class-name> <String>
        existingPersistentVolumeName: <existing-persistence-volume-name> <String>
      mountPath: <mount-path-for-the-volume> <String>
```

| Parameter                           | Type      | Description                                                                                                                                                                                                       | Default |
|-------------------------------------|-----------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|
| `name`                              | `String`  | A name for the provider configuration. Eg. blackduck-file-storage                                                                                                                                                 |         |
| `enabled`                           | `Boolean` | A flag to control enabling/disabling of the provider instance                                                                                                                                                     | `false` |
| `index`                             | `Integer` | An index value for the provider configuration. Eg. 1,2,3.                                                                                                                                                         |         |
| `type`                              | `String`  | Storage type. Defaults to `file`.                                                                                                                                                                                 | `file`  |
| `preference`                        | `Integer` | A number denoting the weightage for the provider instance configuration. If multiple provider instances are configured, then this value is used to determine which provider to be used as default storage option. |         |
| `existingPersistentVolumeClaimName` | `String`  | An option to re-use existing persistent volume claim for the provider                                                                                                                                             |         |
| `pvc.size`                          | `String`  | The volume size to be used while creating persistent volume. A minimum size of `100Gi` is recommended for storage service.                                                                                        | `100Gi` |
| `pvc.storageClass`                  | `String`  | The storage class to be used for persistent volume                                                                                                                                                                |         |
| `pvc.existingPersistentVolumeName`  | `String`  | An option to re-use existing persistent volume for the provider                                                                                                                                                   |         |
| `mountPath`                         | `String`  | Path inside the container where the provider volume to be mounted                                                                                                                                                 |         |
| `readonly`                          | `Boolean` | If present allows you to mark a provider as read only                                                                                                                                                             | false   |
| `migrationMode`                     | `String`  | Indicates if a migration is configured. Values can be 'NONE', DRAIN', 'DELETE' or 'DUPLICATE'                                                                                                                     | 'NONE'  |

### Webapp Pod Configuration

| Parameter                          | Description                                               | Default  |
|------------------------------------|-----------------------------------------------------------|----------|
| `webapp.registry`                  | Image repository to be override at container level        |          |
| `webapp.resources.requests.cpu`    | Webapp container CPU request                              | `1000m`  |
| `webapp.resources.limits.memory`   | Webapp container Memory Limit                             | `2560Mi` |
| `webapp.resources.requests.memory` | Webapp container Memory request                           | `2560Mi` |
| `webapp.maxRamPercentage`          | Webapp container maximum heap size                        | `90`     |
| `webapp.persistentVolumeClaimName` | Point to an existing Webapp Persistent Volume Claim (PVC) |          |
| `webapp.claimSize`                 | Webapp Persistent Volume Claim (PVC) claim size           | `2Gi`    |
| `webapp.storageClass`              | Webapp Persistent Volume Claim (PVC) storage class        |          |
| `webapp.volumeName`                | Point to an existing Webapp Persistent Volume (PV)        |          |
| `webapp.nodeSelector`              | Webapp node labels for pod assignment                     | `{}`     |
| `webapp.tolerations`               | Webapp node tolerations for pod assignment                | `[]`     |
| `webapp.affinity`                  | Webapp node affinity for pod assignment                   | `{}`     |
| `webapp.podSecurityContext`        | Webapp and Logstash security context at pod level         | `{}`     |
| `webapp.securityContext`           | Webapp security context at container level                | `{}`     |

### Logstash Pod Configuration

| Parameter                            | Description                                                 | Default             |
|--------------------------------------|-------------------------------------------------------------|---------------------|
| `logstash.registry`                  | Image repository to be override at container level          |                     |
| `logstash.imageTag`                  | Image tag to be override at container level                 | `1.0.38` |
| `logstash.resources.limits.memory`   | Logstash container Memory Limit                             | `1024Mi`            |
| `logstash.resources.requests.memory` | Logstash container Memory request                           | `1024Mi`            |
| `logstash.maxRamPercentage`          | Logsash maximum heap size                                   | `90`                |
| `logstash.persistentVolumeClaimName` | Point to an existing Logstash Persistent Volume Claim (PVC) |                     |
| `logstash.claimSize`                 | Logstash Persistent Volume Claim (PVC) claim size           | `20Gi`              |
| `logstash.storageClass`              | Logstash Persistent Volume Claim (PVC) storage class        |                     |
| `logstash.volumeName`                | Point to an existing Logstash Persistent Volume (PV)        |                     |
| `logstash.nodeSelector`              | Logstash node labels for pod assignment                     | `{}`                |
| `logstash.tolerations`               | Logstash node tolerations for pod assignment                | `[]`                |
| `logstash.affinity`                  | Logstash node affinity for pod assignment                   | `{}`                |
| `logstash.securityContext`           | Logstash security context at container level                | `{}`                |

### Webserver Pod Configuration

| Parameter                             | Description                                        | Default          |
|---------------------------------------|----------------------------------------------------|------------------|
| `webserver.registry`                  | Image repository to be override at container level |                  |
| `webserver.imageTag`                  | Image tag to be override at container level        | `2024.7.0` |
| `webserver.resources.limits.memory`   | Webserver container Memory Limit                   | `512Mi`          |
| `webserver.resources.requests.memory` | Webserver container Memory request                 | `512Mi`          |
| `webserver.nodeSelector`              | Webserver node labels for pod assignment           | `{}`             |
| `webserver.tolerations`               | Webserver node tolerations for pod assignment      | `[]`             |
| `webserver.affinity`                  | Webserver node affinity for pod assignment         | `{}`             |
| `webserver.podSecurityContext`        | Webserver security context at pod level            | `{}`             |
| `webserver.securityContext`           | Webserver security context at container level      | `{}`             |

### Integration Pod Configuration

| Parameter                               | Description                                        | Default  |
|-----------------------------------------|----------------------------------------------------|----------|
| `integration.registry`                  | Image repository to be override at container level |          |
| `integration.replicas`                  | Integration Pod Replica Count                      | `1`      |
| `integration.resources.limits.cpu`      | Integration container CPU Limit                    | `1000m`  |
| `integration.resources.requests.cpu`    | Integration container CPU request                  | `500m`   |
| `integration.resources.limits.memory`   | Integration container Memory Limit                 | `5120Mi` |
| `integration.resources.requests.memory` | Integration container Memory request               | `5120Mi` |
| `integration.maxRamPercentage`          | Integration container maximum heap size            | `90`     |
| `integration.nodeSelector`              | Integration node labels for pod assignment         | `{}`     |
| `integration.tolerations`               | Integration node tolerations for pod assignment    | `[]`     |
| `integration.affinity`                  | Integration node affinity for pod assignment       | `{}`     |
| `integration.podSecurityContext`        | Integration security context at pod level          | `{}`     |
| `integration.securityContext`           | Integration security context at container level    | `{}`     |

### Datadog Pod Configuration

| Parameter                 | Description                                                                | Default            |
|---------------------------|----------------------------------------------------------------------------|--------------------|
| `datadog.enable`          | only true for hosted customers (Values.enableInitContainer should be true) | false              |
| `datadog.registry`        | Image repository to be override at container level                         |                    |
| `datadog.imageTag`        | Image tag to be override at container level                                | `1.0.15` |
| `datadog.imagePullPolicy` | Image pull policy                                                          | IfNotPresent       |


### Footnotes

[^1]: The `reclaimPolicy` of the `storageClass` in use should be set to `Retain` to ensure data persistence.
[^2]: AzureFile (non-CSI variant) requires a custom storage class for RabbitMQ due to it being treated as an SMB mount where file and directory permissions are immutable once mounted into a pod.
[^3]: See https://sig-product-docs.synopsys.com/bundle/blackduck-compatibility/page/topics/Black-Duck-Hardware-Scaling-Guidelines.html 