# blackduck-helm [alpha]
Helm Charts for Black Duck

**Alpha Release**  
* This helm chart is in early testing and is not fully supported.  
* Some testing has been performed with Helm 2 releases. 

## Prerequisites

- Kubernetes 1.9+
- Helm2 or Helm3

## Parameters

 - `name`
 - `namespace` -- usually the same as `name`
 - `size`: one of: `small`, `medium`, `large`, `x-large`

## Installing the Chart -- Helm 2

#### Create the Namespace and TLS Secrets
Note: You MUST create the namespace and webserver TLS secrets (tls.crt and tls.key need to be provided) **before** installing the Black Duck Helm chart
```console
$ kubectl create ns <namespace>
$ kubectl create secret generic <name>-blackduck-webserver-certificate --from-file=WEBSERVER_CUSTOM_CERT_FILE=tls.crt --from-file=WEBSERVER_CUSTOM_KEY_FILE=tls.key -n <namespace>
```
#### Configure your Black Duck Instance
Modify the values.yaml file or pass in values to `helm intsall` with --set.  
If you're using an external postgres (default configuration) then you will need to set the postgres.host.

#### Install the Black Duck Chart
```
$ helm install . --name <name> --namespace <namespace> -f <size>.yaml --set tlsCertSecretName=<name>-blackduck-webserver-certificate 
```

> **Tip**: List all releases using `helm list`


## Installing the Chart -- Helm 3

#### Create the Namespace and TLS Secrets
Note: You MUST create the namespace and webserver TLS secrets (tls.crt and tls.key need to be provided) **before** installing the Black Duck Helm chart
```console
$ kubectl create ns <namespace>
$ kubectl create secret generic <name>-blackduck-webserver-certificate --from-file=WEBSERVER_CUSTOM_CERT_FILE=tls.crt --from-file=WEBSERVER_CUSTOM_KEY_FILE=tls.key -n <namespace>
```
#### Configure your Black Duck Instance
Modify the values.yaml file or pass in values to `helm intsall` with --set.  
If you're using an external postgres (default configuration) then you will need to set the postgres.host.

#### Install the Black Duck Chart
```
$ helm install <name> . --namespace <namespace> -f <size>.yaml --set tlsCertSecretName=<name>-blackduck-webserver-certificate 
```

## Quick Start with Helm 3
#### Step 1
Navigate to the blackduck-helm chart repository in your terminal
```
$ cd <path>/blackduck-helm
```

#### Step 2
Put the tls.crt and tls.key in your current directory

#### Step 3
```
$ kubectl create ns myblackduck
```

#### Step 4
```
$ kubectl create secret generic myblackduck-blackduck-webserver-certificate --from-file=WEBSERVER_CUSTOM_CERT_FILE=tls.crt --from-file=WEBSERVER_CUSTOM_KEY_FILE=tls.key -n myblackduck
```

#### Step 5
Deploy Black Duck with internal postgres, no ssl for postgres, and no persistent storage (this is not suited for a production environment)
```
$ helm install myblackduck . --namespace myblackduck -f small.yaml --set tlsCertSecretName=myblackduck-blackduck-webserver-certificate --set enablePersistentStorage=false --set postgres.isExternal=false --set postgres.ssl=false
```

## Exposing the Black Duck User Interface (UI)

The Black Duck User Interface (UI) can be exposed via NODEPORT/LOADBALANCER

```console
$ kubectl expose deployment -n <namespace> <name>-blackduck-webserver --name <name>-blackduck-webserver-exposed --type <NodePort/LoadBalancer>
```  

If you use NodePort then you must upgrade the Black Duck instance with the environ `PUBLIC_HUB_WEBSERVER_PORT`.  
You need to set the flag as  

```console
environs.PUBLIC_HUB_WEBSERVER_PORT=<nodeport> 
```

Then upgrade the chart (see below). 

## Upgrading the Chart

```console
$ helm upgrade <name> . --namespace <namespace> -f values.yaml -f <size>.yaml --set tlsCertSecretName=<name>-blackduck-webserver-certificate 
```

## Uninstalling the Chart

To uninstall/delete the deployment:

```console
$ helm delete <name> 
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Configuration

The following table lists the configurable parameters of the Black Duck chart and their default values.

#### Common Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `registry` | Image repository | `docker.io/blackducksoftware` |
| `imageTag` | Version of Black Duck | `2019.12.0` |
| `imagePullSecrets` | Reference to one or more secrets to be used when pulling images | `[]` |
| `sealKey` | Seal key to encrypt the master key when Source code upload is enabled and it should be of length 32 | `abcdefghijklmnopqrstuvwxyz123456` | 
| `enablePersistentStorage` | If true, Black Duck will have persistent storage | `true` |
|  `storageClass` | Global storage class to be used in all Persistent Volume Claim |  |
| `enableLivenessProbe` | If true, Black Duck will have liveness probe | `true` |
| `enableSourceCodeUpload` | If true, source code upload will be enabled by setting in the environment variable (this takes priority over environs flag values) | `false` |
| `dataRetentionInDays` | Source code upload's data retention in days | `180` |
| `maxTotalSourceSizeinMB` | Source code upload's maximum total source size in MB | `4000` |
| `enableBinaryScanner` | If true, binary analysis will be enabled by setting in the environment variable (this takes priority over environs flag values) | `false` |
| `enableAlert` | If true, the Black Duck Alert service will be added to the nginx configuration with the environ  `"HUB_ALERT_HOST:<blackduck_name>-alert.<blackduck_name>.svc` | `false` |
| `enableIPV6` | If true, IPV6 support will be enabled by setting in the environment variable (this takes priority over environs flag values) | `false` |
| `certAuthCACertSecretName` | Own Certificate Authority (CA) for Black Duck Certificate Authentication | `run this command "kubectl create secret generic -n <namespace> <name>-blackduck-auth-custom-ca --from-file=AUTH_CUSTOM_CA=ca.crt" and provide the secret name` |
| `proxyCertSecretName` | Black Duck proxy server’s Certificate Authority (CA) | `run this command "kubectl create secret generic -n <namespace> <name>-blackduck-proxy-certificate --from-file=HUB_PROXY_CERT_FILE=proxy.crt" and provide the secret name` |
| `environs` | environment variables that need to be added to Black Duck configuration | `map e.g. if you want to set PUBLIC_HUB_WEBSERVER_PORT, then it should be --set environs.PUBLIC_HUB_WEBSERVER_PORT=30269` |

#### Postgres Pod Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `postgres.registry` | Image repository | `registry.access.redhat.com/rhscl` |
| `postgres.isExternal` | If true, External PostgreSQL will be used | `true` |
| `postgres.host` | PostgreSQL host (required only if external PostgreSQL is used) |  |
| `postgres.port` | PostgreSQL port | `5432` |
| `postgres.ssl` | PostgreSQL SSL | `true` |
| `postgres.adminUserName` | PostgreSQL admin username | `blackduck` |
| `postgres.adminPassword` | PostgreSQL admin user password | `testPassword` |
| `postgres.userUserName` | PostgreSQL non admin username | `blackduck_user` |
| `postgres.userPassword` | PostgreSQL non admin user password | `testPassword` |
| `postgres.postgresPassword` | PostgreSQL postgres user password (required only if external PostgreSQL is not used) | `testPassword` |
| `postgres.requestCpu` | PostgreSQL container CPU request (if external postgres is not used) | `1000m` |
| `postgres.requestMemory` | PostgreSQL container Memory request (if external postgres is not used) | `3072Mi` |
| `postgres.claimSize` | PostgreSQL Persistent Volume Claim (PVC) claim size (if external postgres is not used) | `150Gi` |
| `postgres.storageClass` | PostgreSQL Persistent Volume Claim (PVC) storage class (if external postgres is not used) |  |
| `postgres.nodeSelector` | PostgreSQL node labels for pod assignment | `{}` |
| `postgres.tolerations` | PostgreSQL node tolerations for pod assignment | `[]` |
| `postgres.affinity` | PostgreSQL node affinity for pod assignment | `{}` |
| `postgres.podSecurityContext.runAsUser` | PostgreSQL security context user ID at pod level | `26` |
| `postgres.podSecurityContext.fsGroup` | PostgreSQL security context volume permission (fsGroup) at pod level | `26` |
| `postgres.podSecurityContext.runAsGroup` | PostgreSQL security context group ID at pod level | `26` |

#### Synopsys Init Container Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `init.registry` | Image repository to be override at container level |  |
| `init.imageTag` | Image tag to be override at container level | `1.0.0` |
| `init.securityContext` | Init security context at container level | `1000` |

#### Authentication Pod Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `authentication.registry` | Image repository to be override at container level |  |
| `authentication.limitMemory` | Authentication container Memory Limit | `1024Mi` |
| `authentication.requestMemory` | Authentication container Memory request | `1024Mi` |
| `authentication.hubMaxMemory` | Authentication container maximum heap size | `512m` |
| `authentication.claimSize` | Authentication Persistent Volume Claim (PVC) claim size | `2Gi` |
| `authentication.storageClass` | Authentication Persistent Volume Claim (PVC) storage class |  |
| `authentication.nodeSelector` | Authentication node labels for pod assignment | `{}` |
| `authentication.tolerations` | Authentication node tolerations for pod assignment | `[]` |
| `authentication.affinity` | Authentication node affinity for pod assignment | `{}` |
| `authentication.podSecurityContext.runAsUser` | Authentication security context user ID at pod level | `1000` |
| `authentication.podSecurityContext.fsGroup` | Authentication security context volume permission (fsGroup) at pod level | `1000` |
| `authentication.podSecurityContext.runAsGroup` | Authentication security context group ID at pod level | `1000` |
| `authentication.securityContext` | Authentication security context at container level | `{}` |

#### Binary Scanner Pod Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `binaryscanner.registry` | Image repository to be override at container level | `docker.io/sigsynopsys` |
| `binaryscanner.imageTag` | Image tag to be override at container level | `2019.09-2` |
| `binaryscanner.limitCpu` | Binary Scanner container CPU Limit | `1000m` |
| `binaryscanner.requestCpu` | Binary Scanner container CPU request | `1000m` |
| `binaryscanner.limitMemory` | Binary Scanner container Memory Limit | `2048Mi` |
| `binaryscanner.requestMemory` | Binary Scanner container Memory request | `2048Mi` |
| `binaryscanner.nodeSelector` | Binary Scanner node labels for pod assignment | `{}` |
| `binaryscanner.tolerations` | Binary Scanner node tolerations for pod assignment | `[]` |
| `binaryscanner.affinity` | Binary Scanner node affinity for pod assignment | `{}` |
| `binaryscanner.podSecurityContext.runAsUser` | Binary Scanner security context user ID at pod level | `1000` |
| `binaryscanner.podSecurityContext.fsGroup` | Binary Scanner security context volume permission (fsGroup) at pod level | `1000` |
| `binaryscanner.podSecurityContext.runAsGroup` | Binary Scanner security context group ID at pod level | `1000` |
| `binaryscanner.securityContext` | Binary Scanner security context at container level | `{}` |

#### CFSSL Pod Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `cfssl.registry` | Image repository to be override at container level |  |
| `cfssl.imageTag` | Image tag to be override at container level | `1.0.0` |
| `cfssl.limitMemory` | Cfssl container Memory Limit | `640Mi` |
| `cfssl.requestMemory` | Cfssl container Memory request | `640Mi` |
| `cfssl.claimSize` | Cfssl Persistent Volume Claim (PVC) claim size | `2Gi` |
| `cfssl.storageClass` | Cfssl Persistent Volume Claim (PVC) storage class |  |
| `cfssl.nodeSelector` | Cfssl node labels for pod assignment | `{}` |
| `cfssl.tolerations` | Cfssl node tolerations for pod assignment | `[]` |
| `cfssl.affinity` | Cfssl node affinity for pod assignment | `{}` |
| `cfssl.podSecurityContext.runAsUser` | Cfssl security context user ID at pod level | `1000` |
| `cfssl.podSecurityContext.fsGroup` | Cfssl security context volume permission (fsGroup) at pod level | `1000` |
| `cfssl.podSecurityContext.runAsGroup` | Cfssl security context group ID at pod level | `1000` |
| `cfssl.securityContext` | Cfssl security context at container level | `{}` |

#### Documentation Pod Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `documentation.registry` | Image repository to be override at container level |  |
| `documentation.limitMemory` | Documentation container Memory Limit | `512Mi` |
| `documentation.requestMemory` | Documentation container Memory request | `512Mi` |
| `documentation.nodeSelector` | Documentation node labels for pod assignment | `{}` |
| `documentation.tolerations` | Documentation node tolerations for pod assignment | `[]` |
| `documentation.affinity` | Documentation node affinity for pod assignment | `{}` |
| `documentation.podSecurityContext.runAsUser` | Documentation security context user ID at pod level | `1000` |
| `documentation.podSecurityContext.fsGroup` | Documentation security context volume permission (fsGroup) at pod level | `1000` |
| `documentation.podSecurityContext.runAsGroup` | Documentation security context group ID at pod level | `1000` |
| `documentation.securityContext` | Documentation security context at container level | `{}` |

#### Job runner Pod Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `jobrunner.registry` | Image repository to be override at container level |  |
| `jobrunner.replicas` | Job runner Pod Replica Count | `1` |
| `jobrunner.limitCpu` | Job runner container CPU Limit | `1000m` |
| `jobrunner.requestCpu` | Job runner container CPU request | `1000m` |
| `jobrunner.limitMemory` | Job runner container Memory Limit | `4608Mi` |
| `jobrunner.requestMemory` | Job runner container Memory request | `4608Mi` |
| `jobrunner.hubMaxMemory` | Job runner container maximum heap size | `4096m` |
| `jobrunner.nodeSelector` | Job runner node labels for pod assignment | `{}` |
| `jobrunner.tolerations` | Job runner node tolerations for pod assignment | `[]` |
| `jobrunner.affinity` | Job runner node affinity for pod assignment | `{}` |
| `jobrunner.podSecurityContext.runAsUser` | Job runner security context user ID at pod level | `1000` |
| `jobrunner.podSecurityContext.fsGroup` | Job runner security context volume permission (fsGroup) at pod level | `1000` |
| `jobrunner.podSecurityContext.runAsGroup` | Job runner security context group ID at pod level | `1000` |
| `jobrunner.securityContext` | Job runner security context at container level | `{}` |

#### RabbitMQ Pod Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `rabbitmq.registry` | Image repository to be override at container level |  |
| `rabbitmq.imageTag` | Image tag to be override at container level | `1.0.3` |
| `rabbitmq.limitMemory` | RabbitMQ container Memory Limit | `1024Mi` |
| `rabbitmq.requestMemory` | RabbitMQ container Memory request | `1024Mi` |
| `rabbitmq.nodeSelector` | RabbitMQ node labels for pod assignment | `{}` |
| `rabbitmq.tolerations` | RabbitMQ node tolerations for pod assignment | `[]` |
| `rabbitmq.affinity` | RabbitMQ node affinity for pod assignment | `{}` |
| `rabbitmq.podSecurityContext.runAsUser` | RabbitMQ security context user ID at pod level | `1000` |
| `rabbitmq.podSecurityContext.fsGroup` | RabbitMQ security context volume permission (fsGroup) at pod level | `1000` |
| `rabbitmq.podSecurityContext.runAsGroup` | RabbitMQ security context group ID at pod level | `1000` |
| `rabbitmq.securityContext` | RabbitMQ security context at container level | `{}` |

#### Registration Pod Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `registration.registry` | Image repository to be override at container level |  |
| `registration.requestCpu` | Registration container CPU request | `1000m` |
| `registration.limitMemory` | Registration container Memory Limit | `1024Mi` |
| `registration.requestMemory` | Registration container Memory request | `1024Mi` |
| `registration.claimSize` | Registration Persistent Volume Claim (PVC) claim size | `2Gi` |
| `registration.storageClass` | Registration Persistent Volume Claim (PVC) storage class |  |
| `registration.nodeSelector` | Registration node labels for pod assignment | `{}` |
| `registration.tolerations` | Registration node tolerations for pod assignment | `[]` |
| `registration.affinity` | Registration node affinity for pod assignment | `{}` |
| `registration.podSecurityContext.runAsUser` | Registration security context user ID at pod level | `1000` |
| `registration.podSecurityContext.fsGroup` | Registration security context volume permission (fsGroup) at pod level | `1000` 
| `registration.podSecurityContext.runAsGroup` | Registration security context group ID at pod level | `1000` |
| `registration.securityContext` | Registration security context at container level | `{}` |

#### Scan Pod Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `scan.registry` | Image repository to be override at container level |  |
| `scan.replicas` | Scan Pod Replica Count | `1` |
| `scan.limitMemory` | Scan container Memory Limit | `2560Mi` |
| `scan.requestMemory` | Scan container Memory request | `2560Mi` |
| `scan.hubMaxMemory` | Scan container maximum heap size | `2048m` |
| `scan.nodeSelector` | Scan node labels for pod assignment | `{}` |
| `scan.tolerations` | Scan node tolerations for pod assignment | `[]` |
| `scan.affinity` | Scan node affinity for pod assignment | `{}` |
| `scan.podSecurityContext.runAsUser` | Scan security context user ID at pod level | `1000` |
| `scan.podSecurityContext.fsGroup` | Scan security context volume permission (fsGroup) at pod level | `1000` |
| `scan.podSecurityContext.runAsGroup` | Scan security context group ID at pod level | `1000` |
| `scan.securityContext` | Scan security context at container level | `{}` |

#### Upload cache Pod Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `uploadcache.registry` | Image repository to be override at container level |  |
| `uploadcache.imageTag` | Image tag to be override at container level | `1.0.13` |
| `uploadcache.limitMemory` | Upload cache container Memory Limit | `512Mi` |
| `uploadcache.requestMemory` | Upload cache container Memory request | `512Mi` |
| `uploadcache.claimSize` | Upload cache Persistent Volume Claim (PVC) claim size | `100Gi` |
| `uploadcache.storageClass` | Upload cache Persistent Volume Claim (PVC) storage class |  |
| `uploadcache.nodeSelector` | Upload cache node labels for pod assignment | `{}` |
| `uploadcache.tolerations` | Upload cache node tolerations for pod assignment | `[]` |
| `uploadcache.affinity` | Upload cache node affinity for pod assignment | `{}` |
| `uploadcache.podSecurityContext.runAsUser` | Upload cache security context user ID at pod level | `1000` |
| `uploadcache.podSecurityContext.fsGroup` | Upload cache security context volume permission (fsGroup) at pod level | `1000` |
| `uploadcache.podSecurityContext.runAsGroup` | Upload cache security context group ID at pod level | `1000` |
| `uploadcache.securityContext` | Upload cache security context at container level | `{}` |

#### Webapp Pod Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `webapp.registry` | Image repository to be override at container level |  |
| `webapp.requestCpu` | Webapp container CPU request | `1000m` |
| `webapp.limitMemory` | Webapp container Memory Limit | `2560Mi` |
| `webapp.requestMemory` | Webapp container Memory request | `2560Mi` |
| `webapp.hubMaxMemory` | Webapp container maximum heap size | `2048m` |
| `webapp.claimSize` | Webapp Persistent Volume Claim (PVC) claim size | `2Gi` |
| `webapp.storageClass` | Webapp Persistent Volume Claim (PVC) storage class |  |
| `webapp.nodeSelector` | Webapp node labels for pod assignment | `{}` |
| `webapp.tolerations` | Webapp node tolerations for pod assignment | `[]` |
| `webapp.affinity` | Webapp node affinity for pod assignment | `{}` |
| `webapp.podSecurityContext.runAsUser` | Webapp and Logstash security context user ID at pod level | `1000` |
| `webapp.podSecurityContext.fsGroup` | Webapp and Logstash security context volume permission (fsGroup) at pod level | `1000` |
| `webapp.podSecurityContext.runAsGroup` | Webapp and Logstash security context group ID at pod level | `1000` |
| `webapp.securityContext` | Webapp security context at container level | `{}` |

#### Logstash Pod Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `logstash.registry` | Image repository to be override at container level |  |
| `logstash.imageTag` | Image tag to be override at container level | `1.0.5` |
| `logstash.limitMemory` | Logstash container Memory Limit | `1024Mi` |
| `logstash.requestMemory` | Logstash container Memory request | `1024Mi` |
| `logstash.claimSize` | Logstash Persistent Volume Claim (PVC) claim size | `20Gi` |
| `logstash.storageClass` | Logstash Persistent Volume Claim (PVC) storage class |  |
| `logstash.nodeSelector` | Logstash node labels for pod assignment | `{}` |
| `logstash.tolerations` | Logstash node tolerations for pod assignment | `[]` |
| `logstash.affinity` | Logstash node affinity for pod assignment | `{}` |
| `logstash.securityContext` | Logstash security context at container level | `{}` |

#### Webserver Pod Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `webserver.registry` | Image repository to be override at container level |  |
| `webserver.imageTag` | Image tag to be override at container level | `1.0.18` |
| `webserver.limitMemory` | Webserver container Memory Limit | `512Mi` |
| `webserver.requestMemory` | Webserver container Memory request | `512Mi` |
| `webserver.nodeSelector` | Webserver node labels for pod assignment | `{}` |
| `webserver.tolerations` | Webserver node tolerations for pod assignment | `[]` |
| `webserver.affinity` | Webserver node affinity for pod assignment | `{}` |
| `webserver.podSecurityContext.runAsUser` | Webserver security context user ID at pod level | `1000` |
| `webserver.podSecurityContext.fsGroup` | Webserver security context volume permission (fsGroup) at pod level | `1000` |
| `webserver.podSecurityContext.runAsGroup` | Webserver security context group ID at pod level | `1000` |
| `webserver.securityContext` | Webserver security context at container level | `{}` |

#### Zookeeper Pod Configuration
| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `zookeeper.registry` | Image repository to be override at container level |  |
| `zookeeper.imageTag` | Image tag to be override at container level | `1.0.3` |
| `zookeeper.requestCpu` | Zookeeper container CPU request | `1000m` |
| `zookeeper.limitMemory` | Zookeeper container Memory Limit | `640Mi` |
| `zookeeper.requestMemory` | Zookeeper container Memory request | `640Mi` |
| `zookeeper.claimSize` | Zookeeper Persistent Volume Claim (PVC) claim size | `4Gi` |
| `zookeeper.storageClass` | Zookeeper Persistent Volume Claim (PVC) storage class |  |
| `zookeeper.nodeSelector` | Zookeeper node labels for pod assignment | `{}` |
| `zookeeper.tolerations` | Zookeeper node tolerations for pod assignment | `[]` |
| `zookeeper.affinity` | Zookeeper node affinity for pod assignment | `{}` |
| `zookeeper.podSecurityContext.runAsUser` | Zookeeper security context user ID at pod level | `1000` |
| `zookeeper.podSecurityContext.fsGroup` | Zookeeper security context volume permission (fsGroup) at pod level | `1000` |
| `zookeeper.podSecurityContext.runAsGroup` | Zookeeper security context group ID at pod level | `1000` |
| `zookeeper.securityContext` | Zookeeper security context at container level | `{}` |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`.

Alternatively, a YAML file that specifies the values for the above parameters can be provided while installing the chart. For example,

```console
$ helm install . --name <name> --namespace <namespace> -f <size>.yaml --set tlsCertSecretName=<name>-blackduck-webserver-certificate -f values.yaml
```
> **Tip**: You can use the default [values.yaml](values.yaml)
