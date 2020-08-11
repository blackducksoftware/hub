# Black Duck Helm Chart

> **Alpha Release**

This chart bootstraps **Black Duck** deployment on a **Kubernetes** cluster using **Helm** package manager.

## Prerequisites

* Kubernetes 1.9+
  * storageClass configured that allows persistent volumes.
* Helm2 or Helm3

## Quick Start Parameters

* `name`
* `namespace` -- usually the same as `name`
* `size`: one of: `small`, `medium`, `large`, `x-large`

## Installing the Chart -- Helm 3

### Create the Namespace

```bash
$ BD_NAME="bd"
$ kubectl create ns ${BD_NAME}
```

### Create the Custom TLS Secret (Optional)

Note: It's common to provide a custom webserver TLS secret before installing the Black Duck Helm chart. Create the secret with the command below **before** deploying and then set the value in the Helm Chart with `--set tlsCertSecretName=<secret_name>` during deployment (tls.crt and tls.key files are required). If the value `tlsCertSecretName` is not provided then Black Duck will generate its own certificates.  

```bash
$ BD_NAME="bd"
$ kubectl create secret generic ${BD_NAME}-blackduck-webserver-certificate -n ${BD_NAME} --from-file=WEBSERVER_CUSTOM_CERT_FILE=tls.crt --from-file=WEBSERVER_CUSTOM_KEY_FILE=tls.key
```

### Configure your Black Duck Instance

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

```bash
$ helm install ${BD_NAME} . --set tlsCertSecretName=${BD_NAME}-blackduck-webserver-certificate
```

Alternatively, a YAML file that specifies the values for the parameters can be provided while installing the chart. For example,

```bash
$ helm install ${BD_NAME} . -f my-values.yaml
```

If you're using an external postgres (default configuration) then you will need to set the postgres.host.

### Install the Black Duck Chart

```bash
$ BD_NAME="bd" && BD_SIZE="small"
$ helm install . --name ${BD_NAME} --namespace <namespace> -f ${BD_SIZE}.yaml --set tlsCertSecretName=${BD_NAME}-blackduck-webserver-certificate
```

> **Tip**: List all releases using `helm list` and list all specified values using `helm get values RELEASE_NAME`

## Exposing the Black Duck User Interface (UI)

The Black Duck User Interface (UI) can be exposed via NodePort/LoadBalancer/Routes(OpenShift)

```bash
$ export SERVICE_TYPE=NodePort # default
$ # export SERVICE_TYPE=LoadBalancer
$ # export SERVICE_TYPE=OpenShift
$ helm upgrade ${BD_NAME} . -n ${BD_NAME} --set exposedServiceType ${SERVICE_TYPE}
```

If you use NodePort then you must upgrade the Black Duck instance with the environ `PUBLIC_HUB_WEBSERVER_PORT`:

```bash
$ export NODEPORT=$(kubectl get -n ${BD_NAME} -o jsonpath="{.spec.ports[0].nodePort}" services ${BD_NAME}-blackduck-webserver-exposed)
$ helm upgrade ${BD_NAME} . --reuse-values -n ${BD_NAME} --set environs.PUBLIC_HUB_WEBSERVER_PORT=${NODEPORT}
```

The Black Duck User Interface (UI) can be accessed via

NodePort, you can use the following command to get the Node port of the Black Duck web server:
```bash
$ kubectl get services ${BD_NAME}-blackduck-webserver-exposed -n ${BD_NAME}
``` 

Load balancer, you can use the following command to get the external IP address and port of the Black Duck web server:

```bash
$ kubectl get services ${BD_NAME}-blackduck-webserver-exposed -n ${BD_NAME}
``` 

OpenShift, you can use the following command to get the routes:
```bash
$ oc get routes -n ${BD_NAME} 
``` 

## Uninstalling the Chart

To uninstall/delete the deployment:

```bash
$ helm delete ${BD_NAME} -n ${BD_NAME}
$ kubectl delete configmap -n ${BD_NAME} ${BD_NAME}-blackduck-postgres-init-config
$ kubectl delete configmap -n ${BD_NAME} ${BD_NAME}-blackduck-db-config
$ kubectl delete secret -n ${BD_NAME} ${BD_NAME}-blackduck-db-creds
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Upgrading the Chart

To upgrade the deployment:

```bash
$ helm upgrade ${BD_NAME} -n ${BD_NAME}
```

**Note**: You cannot upgrade your instance to enable Persistent Storage. You must delete the deployment and install it again.  

## Configuration

The following table lists the configurable parameters of the Black Duck chart and their default values.

**Note**: Do not set the following parameters in the environs flag. Instead, use their respective flags.

    Use dataRetentionInDays, enableSourceCodeUpload and maxTotalSourceSizeinMB for the following:
    * DATA_RETENTION_IN_DAYS
    * ENABLE_SOURCE_UPLOADS
    * MAX_TOTAL_SOURCE_SIZE_MB

    Use enableBinaryScanner for the following:
    * USE_BINARY_UPLOADS

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

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `registry` | Image repository | `docker.io/blackducksoftware` |
| `imageTag` | Version of Black Duck | `2020.6.2` |
| `imagePullSecrets` | Reference to one or more secrets to be used when pulling images | `[]` |
| `sealKey` | Seal key to encrypt the master key when Source code upload is enabled and it should be of length 32 | `abcdefghijklmnopqrstuvwxyz123456` |
| `tlsCertSecretName` | Name of Webserver TLS Secret containing Certificates (if not provided Certificates will be generated) | |
| `exposeui` | Enable Black Duck Web Server User Interface (UI) | `true` |
| `exposedServiceType` | Expose Black Duck Web Server Service Type  | `NodePort` |
| `enablePersistentStorage` | If true, Black Duck will have persistent storage | `true` |
|  `storageClass` | Global storage class to be used in all Persistent Volume Claim |  |
| `enableLivenessProbe` | If true, Black Duck will have liveness probe | `true` |
| `enableSourceCodeUpload` | If true, source code upload will be enabled by setting in the environment variable (this takes priority over environs flag values) | `false` |
| `dataRetentionInDays` | Source code upload's data retention in days | `180` |
| `maxTotalSourceSizeinMB` | Source code upload's maximum total source size in MB | `4000` |
| `enableBinaryScanner` | If true, binary analysis will be enabled by setting in the environment variable (this takes priority over environs flag values) | `false` |
| `enableAlert` | If true, the Black Duck Alert service will be added to the nginx configuration with the environ  `"HUB_ALERT_HOST:<blackduck_name>-alert.<blackduck_name>.svc` | `false` |
| `enableIPV6` | If true, IPV6 support will be enabled by setting in the environment variable (this takes priority over environs flag values) | `true` |
| `certAuthCACertSecretName` | Own Certificate Authority (CA) for Black Duck Certificate Authentication | `run this command "kubectl create secret generic -n <namespace> <name>-blackduck-auth-custom-ca --from-file=AUTH_CUSTOM_CA=ca.crt" and provide the secret name` |
| `proxyCertSecretName` | Black Duck proxy server’s Certificate Authority (CA) | `run this command "kubectl create secret generic -n <namespace> <name>-blackduck-proxy-certificate --from-file=HUB_PROXY_CERT_FILE=proxy.crt" and provide the secret name` |
| `environs` | environment variables that need to be added to Black Duck configuration | `map e.g. if you want to set PUBLIC_HUB_WEBSERVER_PORT, then it should be --set environs.PUBLIC_HUB_WEBSERVER_PORT=30269` |

### Postgres Pod Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `postgres.registry` | Image repository | `docker.io/centos` |
| `postgres.isExternal` | If true, External PostgreSQL will be used | `true` |
| `postgres.host` | PostgreSQL host (required only if external PostgreSQL is used) |  |
| `postgres.port` | PostgreSQL port | `5432` |
| `postgres.pathToPsqlInitScript` | Full file path of the PostgreSQL initialization script | `external-postgres-init.pgsql` |
| `postgres.ssl` | PostgreSQL SSL | `true` |
| `postgres.adminUserName` | PostgreSQL admin username | `blackduck` |
| `postgres.adminPassword` | PostgreSQL admin user password | `testPassword` |
| `postgres.userUserName` | PostgreSQL non admin username | `blackduck_user` |
| `postgres.userPassword` | PostgreSQL non admin user password | `testPassword` |
| `postgres.resources.requests.cpu` | PostgreSQL container CPU request (if external postgres is not used) | `1000m` |
| `postgres.resources.requests.memory` | PostgreSQL container Memory request (if external postgres is not used) | `3072Mi` |
| `postgres.persistentVolumeClaimName` | Point to an existing PostgreSQL Persistent Volume Claim (PVC) | |
| `postgres.claimSize` | PostgreSQL Persistent Volume Claim (PVC) claim size (if external postgres is not used) | `150Gi` |
| `postgres.storageClass` | PostgreSQL Persistent Volume Claim (PVC) storage class (if external postgres is not used) |  |
| `postgres.volumeName` | Point to an existing PostgreSQL Persistent Volume (PV)  |  |
| `postgres.nodeSelector` | PostgreSQL node labels for pod assignment | `{}` |
| `postgres.tolerations` | PostgreSQL node tolerations for pod assignment | `[]` |
| `postgres.affinity` | PostgreSQL node affinity for pod assignment | `{}` |
| `postgres.podSecurityContext` | PostgreSQL security context at pod level | `{}` |
| `postgres.securityContext` | PostgreSQL security context at container level | `{}` |

### Synopsys Init Container Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `init.registry` | Image repository to be override at container level |  |
| `init.imageTag` | Image tag to be override at container level | `1.0.0` |
| `init.securityContext` | Init security context at container level | `1000` |

### Authentication Pod Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `authentication.registry` | Image repository to be override at container level |  |
| `authentication.resources.limits.memory` | Authentication container Memory Limit | `1024Mi` |
| `authentication.resources.requests.memory` | Authentication container Memory request | `1024Mi` |
| `authentication.hubMaxMemory` | Authentication container maximum heap size | `512m` |
| `authentication.persistentVolumeClaimName` | Point to an existing Authentication Persistent Volume Claim (PVC) | |
| `authentication.claimSize` | Authentication Persistent Volume Claim (PVC) claim size | `2Gi` |
| `authentication.storageClass` | Authentication Persistent Volume Claim (PVC) storage class |  |
| `authentication.volumeName` | Point to an existing Authentication Persistent Volume (PV)  |  |
| `authentication.nodeSelector` | Authentication node labels for pod assignment | `{}` |
| `authentication.tolerations` | Authentication node tolerations for pod assignment | `[]` |
| `authentication.affinity` | Authentication node affinity for pod assignment | `{}` |
| `authentication.podSecurityContext` | Authentication security context at pod level | `{}` |
| `authentication.securityContext` | Authentication security context at container level | `{}` |

### Binary Scanner Pod Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `binaryscanner.registry` | Image repository to be override at container level | `docker.io/sigsynopsys` |
| `binaryscanner.imageTag` | Image tag to be override at container level | `2020.03-1` |
| `binaryscanner.resources.limits.Cpu` | Binary Scanner container CPU Limit | `1000m` |
| `binaryscanner.resources.requests.Cpu` | Binary Scanner container CPU request | `1000m` |
| `binaryscanner.resources.limits.memory` | Binary Scanner container Memory Limit | `2048Mi` |
| `binaryscanner.resources.requests.memory` | Binary Scanner container Memory request | `2048Mi` |
| `binaryscanner.nodeSelector` | Binary Scanner node labels for pod assignment | `{}` |
| `binaryscanner.tolerations` | Binary Scanner node tolerations for pod assignment | `[]` |
| `binaryscanner.affinity` | Binary Scanner node affinity for pod assignment | `{}` |
| `binaryscanner.podSecurityContext` | Binary Scanner security context at pod level | `{}` |
| `binaryscanner.securityContext` | Binary Scanner security context at container level | `{}` |

### CFSSL Pod Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `cfssl.registry` | Image repository to be override at container level |  |
| `cfssl.imageTag` | Image tag to be override at container level | `1.0.1` |
| `cfssl.resources.limits.memory` | Cfssl container Memory Limit | `640Mi` |
| `cfssl.resources.requests.memory` | Cfssl container Memory request | `640Mi` |
| `cfssl.persistentVolumeClaimName` | Point to an existing Cfssl Persistent Volume Claim (PVC) | |
| `cfssl.claimSize` | Cfssl Persistent Volume Claim (PVC) claim size | `2Gi` |
| `cfssl.storageClass` | Cfssl Persistent Volume Claim (PVC) storage class |  |
| `cfssl.volumeName` | Point to an existing Cfssl Persistent Volume (PV)  |  |
| `cfssl.nodeSelector` | Cfssl node labels for pod assignment | `{}` |
| `cfssl.tolerations` | Cfssl node tolerations for pod assignment | `[]` |
| `cfssl.affinity` | Cfssl node affinity for pod assignment | `{}` |
| `cfssl.podSecurityContext` | Cfssl security context at pod level | `{}` |
| `cfssl.securityContext` | Cfssl security context at container level | `{}` |

### Documentation Pod Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `documentation.registry` | Image repository to be override at container level |  |
| `documentation.resources.limits.memory` | Documentation container Memory Limit | `512Mi` |
| `documentation.resources.requests.memory` | Documentation container Memory request | `512Mi` |
| `documentation.nodeSelector` | Documentation node labels for pod assignment | `{}` |
| `documentation.tolerations` | Documentation node tolerations for pod assignment | `[]` |
| `documentation.affinity` | Documentation node affinity for pod assignment | `{}` |
| `documentation.podSecurityContext` | Documentation security context at pod level | `{}` |
| `documentation.securityContext` | Documentation security context at container level | `{}` |

### Job runner Pod Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `jobrunner.registry` | Image repository to be override at container level |  |
| `jobrunner.replicas` | Job runner Pod Replica Count | `1` |
| `jobrunner.resources.limits.cpu` | Job runner container CPU Limit | `1000m` |
| `jobrunner.resources.requests.cpu` | Job runner container CPU request | `1000m` |
| `jobrunner.resources.limits.memory` | Job runner container Memory Limit | `4608Mi` |
| `jobrunner.resources.requests.memory` | Job runner container Memory request | `4608Mi` |
| `jobrunner.hubMaxMemory` | Job runner container maximum heap size | `4096m` |
| `jobrunner.nodeSelector` | Job runner node labels for pod assignment | `{}` |
| `jobrunner.tolerations` | Job runner node tolerations for pod assignment | `[]` |
| `jobrunner.affinity` | Job runner node affinity for pod assignment | `{}` |
| `jobrunner.podSecurityContext` | Job runner security context at pod level | `{}` |
| `jobrunner.securityContext` | Job runner security context at container level | `{}` |

### RabbitMQ Pod Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `rabbitmq.registry` | Image repository to be override at container level |  |
| `rabbitmq.imageTag` | Image tag to be override at container level | `1.0.3` |
| `rabbitmq.resources.limits.memory` | RabbitMQ container Memory Limit | `1024Mi` |
| `rabbitmq.resources.requests.memory` | RabbitMQ container Memory request | `1024Mi` |
| `rabbitmq.nodeSelector` | RabbitMQ node labels for pod assignment | `{}` |
| `rabbitmq.tolerations` | RabbitMQ node tolerations for pod assignment | `[]` |
| `rabbitmq.affinity` | RabbitMQ node affinity for pod assignment | `{}` |
| `rabbitmq.podSecurityContext` | RabbitMQ security context at pod level | `{}` |
| `rabbitmq.securityContext` | RabbitMQ security context at container level | `{}` |

### Registration Pod Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `registration.registry` | Image repository to be override at container level |  |
| `registration.requestCpu` | Registration container CPU request | `1000m` |
| `registration.resources.limits.memory` | Registration container Memory Limit | `1024Mi` |
| `registration.resources.requests.memory` | Registration container Memory request | `1024Mi` |
| `registration.persistentVolumeClaimName` | Point to an existing Registration Persistent Volume Claim (PVC) | |
| `registration.claimSize` | Registration Persistent Volume Claim (PVC) claim size | `2Gi` |
| `registration.storageClass` | Registration Persistent Volume Claim (PVC) storage class |  |
| `registration.volumeName` | Point to an existing Registration Persistent Volume (PV)  |  |
| `registration.nodeSelector` | Registration node labels for pod assignment | `{}` |
| `registration.tolerations` | Registration node tolerations for pod assignment | `[]` |
| `registration.affinity` | Registration node affinity for pod assignment | `{}` |
| `registration.podSecurityContext` | Registration security context at pod level | `{}` |
| `registration.securityContext` | Registration security context at container level | `{}` |

### Scan Pod Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `scan.registry` | Image repository to be override at container level |  |
| `scan.replicas` | Scan Pod Replica Count | `1` |
| `scan.resources.limits.memory` | Scan container Memory Limit | `2560Mi` |
| `scan.resources.requests.memory` | Scan container Memory request | `2560Mi` |
| `scan.hubMaxMemory` | Scan container maximum heap size | `2048m` |
| `scan.nodeSelector` | Scan node labels for pod assignment | `{}` |
| `scan.tolerations` | Scan node tolerations for pod assignment | `[]` |
| `scan.affinity` | Scan node affinity for pod assignment | `{}` |
| `scan.podSecurityContext` | Scan security context at pod level | `{}` |
| `scan.securityContext` | Scan security context at container level | `{}` |

### Upload cache Pod Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `uploadcache.registry` | Image repository to be override at container level |  |
| `uploadcache.imageTag` | Image tag to be override at container level | `1.0.14` |
| `uploadcache.resources.limits.memory` | Upload cache container Memory Limit | `512Mi` |
| `uploadcache.resources.requests.memory` | Upload cache container Memory request | `512Mi` |
| `uploadcache.persistentVolumeClaimName` | Point to an existing Upload cache Persistent Volume Claim (PVC) | |
| `uploadcache.claimSize` | Upload cache Persistent Volume Claim (PVC) claim size | `100Gi` |
| `uploadcache.storageClass` | Upload cache Persistent Volume Claim (PVC) storage class |  |
| `uploadcache.volumeName` | Point to an existing Upload cache Persistent Volume (PV)  |  |
| `uploadcache.nodeSelector` | Upload cache node labels for pod assignment | `{}` |
| `uploadcache.tolerations` | Upload cache node tolerations for pod assignment | `[]` |
| `uploadcache.affinity` | Upload cache node affinity for pod assignment | `{}` |
| `uploadcache.podSecurityContext` | Upload cache security context at pod level | `{}` |
| `uploadcache.securityContext` | Upload cache security context at container level | `{}` |

### Webapp Pod Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `webapp.registry` | Image repository to be override at container level |  |
| `webapp.resources.requests.cpu` | Webapp container CPU request | `1000m` |
| `webapp.resources.limits.memory` | Webapp container Memory Limit | `2560Mi` |
| `webapp.resources.requests.memory` | Webapp container Memory request | `2560Mi` |
| `webapp.hubMaxMemory` | Webapp container maximum heap size | `2048m` |
| `webapp.persistentVolumeClaimName` | Point to an existing Webapp Persistent Volume Claim (PVC) | |
| `webapp.claimSize` | Webapp Persistent Volume Claim (PVC) claim size | `2Gi` |
| `webapp.storageClass` | Webapp Persistent Volume Claim (PVC) storage class |  |
| `webapp.volumeName` | Point to an existing Webapp Persistent Volume (PV)  |  |
| `webapp.nodeSelector` | Webapp node labels for pod assignment | `{}` |
| `webapp.tolerations` | Webapp node tolerations for pod assignment | `[]` |
| `webapp.affinity` | Webapp node affinity for pod assignment | `{}` |
| `webapp.podSecurityContext` | Webapp and Logstash security context at pod level | `{}` |
| `webapp.securityContext` | Webapp security context at container level | `{}` |

### Logstash Pod Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `logstash.registry` | Image repository to be override at container level |  |
| `logstash.imageTag` | Image tag to be override at container level | `1.0.6` |
| `logstash.resources.limits.memory` | Logstash container Memory Limit | `1024Mi` |
| `logstash.resources.requests.memory` | Logstash container Memory request | `1024Mi` |
| `logstash.persistentVolumeClaimName` | Point to an existing Logstash Persistent Volume Claim (PVC) | |
| `logstash.claimSize` | Logstash Persistent Volume Claim (PVC) claim size | `20Gi` |
| `logstash.storageClass` | Logstash Persistent Volume Claim (PVC) storage class |  |
| `logstash.volumeName` | Point to an existing Logstash Persistent Volume (PV)  |  |
| `logstash.nodeSelector` | Logstash node labels for pod assignment | `{}` |
| `logstash.tolerations` | Logstash node tolerations for pod assignment | `[]` |
| `logstash.affinity` | Logstash node affinity for pod assignment | `{}` |
| `logstash.securityContext` | Logstash security context at container level | `{}` |

### Webserver Pod Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `webserver.registry` | Image repository to be override at container level |  |
| `webserver.imageTag` | Image tag to be override at container level | `1.0.25` |
| `webserver.resources.limits.memory` | Webserver container Memory Limit | `512Mi` |
| `webserver.resources.requests.memory` | Webserver container Memory request | `512Mi` |
| `webserver.nodeSelector` | Webserver node labels for pod assignment | `{}` |
| `webserver.tolerations` | Webserver node tolerations for pod assignment | `[]` |
| `webserver.affinity` | Webserver node affinity for pod assignment | `{}` |
| `webserver.podSecurityContext` | Webserver security context at pod level | `{}` |
| `webserver.securityContext` | Webserver security context at container level | `{}` |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`.

Alternatively, a YAML file that specifies the values for the above parameters can be provided while installing the chart. For example,

```console
$ helm install . --name ${BD_NAME} --namespace ${BD_NAME} -f <size>.yaml --set tlsCertSecretName=${BD_NAME}-blackduck-webserver-certificate -f values.yaml
```

> **Tip**: You can use the default [values.yaml](values.yaml)
