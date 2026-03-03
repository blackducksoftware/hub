{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "bd.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "bd.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
### NOT CONFIGURABLE
### Environs listed below are NOT CONFIGURABLE
# NOTE: if you change .Values.environs for these, they will be duplicated and may cause unwanted behavior
### END NOT CONFIGURABLE
*/}}
{{- define "bd.defaultNonConfigurableEnvirons" -}}
AUTHENTICATION_HOST: {{ .Release.Name }}-blackduck-authentication:8443
BLACKDUCK_CFSSL_HOST: {{ .Release.Name }}-blackduck-cfssl
BLACKDUCK_REDIS_HOST: {{ .Release.Name }}-blackduck-redis
BLACKDUCK_STORAGE_HOST: {{ .Release.Name }}-blackduck-storage
BLACKDUCK_STORAGE_PORT: "8443"
BROKER_URL: amqps://{{ .Release.Name }}-blackduck-rabbitmq/protecodesc
CFSSL: {{ .Release.Name }}-blackduck-cfssl:8888
CLIENT_CERT_CN: {{ .Release.Name }}-blackduck-binaryscanner
HUB_AUTHENTICATION_HOST: {{ .Release.Name }}-blackduck-authentication
HUB_CFSSL_HOST: {{ .Release.Name }}-blackduck-cfssl
HUB_DOC_HOST: {{ .Release.Name }}-blackduck-documentation
HUB_JOBRUNNER_HOST: {{ .Release.Name }}-blackduck-jobrunner
HUB_LOGSTASH_HOST: {{ .Release.Name }}-blackduck-logstash
HUB_MATCHENGINE_HOST: {{ .Release.Name }}-blackduck-matchengine
HUB_BOMENGINE_HOST: {{ .Release.Name }}-blackduck-bomengine
HUB_PRODUCT_NAME: BLACK_DUCK
HUB_REGISTRATION_HOST: {{ .Release.Name }}-blackduck-registration
HUB_SCAN_HOST: {{ .Release.Name }}-blackduck-scan
HUB_VERSION: {{ .Values.imageTag }}
HUB_WEBAPP_HOST: {{ .Release.Name }}-blackduck-webapp
HUB_WEBSERVER_HOST: {{ .Release.Name }}-blackduck-webserver
RABBIT_MQ_HOST: {{ .Release.Name }}-blackduck-rabbitmq
{{- if eq .Values.isKubernetes true }}
BLACKDUCK_ORCHESTRATION_TYPE: KUBERNETES
{{- else }}
BLACKDUCK_ORCHESTRATION_TYPE: OPENSHIFT
{{- end }}
{{- end -}}

{{- define "bd.environs" }}
{{- range $key, $value := .Values.environs }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "bd.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "bd.labels" -}}
helm.sh/chart: {{ include "bd.chart" . }}
{{ include "bd.selectorLabels" . }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "bd.selectorLabels" -}}
app: blackduck
name: {{ .Release.Name }}
version: {{ .Values.imageTag }}
{{- end -}}

{{/*
Common labels without version
*/}}
{{- define "bd.labelsWithoutVersion" -}}
helm.sh/chart: {{ include "bd.chart" . }}
{{ include "bd.selectorLabelsWithoutVersion" . }}
{{- end -}}

{{/*
Selector labels without version
*/}}
{{- define "bd.selectorLabelsWithoutVersion" -}}
app: blackduck
name: {{ .Release.Name }}
{{- end -}}

{{/*
Security Context if Kubernetes
*/}}
{{- define "bd.podSecurityContext" -}}
{{- if .Values.isKubernetes -}}
securityContext:
  fsGroup: 0
{{- end -}}
{{- end -}}

{{/*
Image pull secrets to pull the image
*/}}
{{- define "bd.imagePullSecrets" }}
{{- if .Values.imagePullSecrets -}}
imagePullSecrets:
{{- range .Values.imagePullSecrets }}
  - name: {{ . }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Enable Source Code upload
*/}}
{{- define "enableSourceCodeUpload" -}}
{{- if .Values.enableSourceCodeUpload -}}
DATA_RETENTION_IN_DAYS: "{{ .Values.dataRetentionInDays }}"
ENABLE_SOURCE_UPLOADS: "true"
MAX_TOTAL_SOURCE_SIZE_MB: "{{ .Values.maxTotalSourceSizeinMB }}"
{{- else -}}
ENABLE_SOURCE_UPLOADS: "false"
{{- end -}}
{{- end -}}

{{/*
Enable Binary Scanner
*/}}
{{- define "enableBinaryScanner" -}}
{{- end -}}

{{/*
Enable integration
*/}}
{{- define "enableIntegration" -}}
{{- if .Values.enableIntegration -}}
ENABLE_INTEGRATION_SERVICE: "true"
BLACKDUCK_INTEGRATION_HOST: {{ .Release.Name }}-blackduck-integration
{{- end -}}
{{- end -}}

{{/*
Enable Alert
*/}}
{{- define "enableAlert" -}}
{{- if .Values.enableAlert -}}
USE_ALERT: "1"
{{- if eq .Values.alertNamespace "" }}
HUB_ALERT_HOST: {{ required "use --set alertName to deploy with Alert" .Values.alertName }}
{{- else }}
HUB_ALERT_HOST: {{ required "use --set alertName to deploy with Alert" .Values.alertName }}.{{ .Values.alertNamespace }}.svc
{{- end }}
HUB_ALERT_PORT: "8443"
{{- else -}}
USE_ALERT: "0"
{{- end -}}
{{- end -}}

{{/*
Custom Node Port
*/}}
{{- define "customNodePort" -}}
{{- if and .Values.exposedNodePort (eq .Values.exposedServiceType "NodePort") }}
PUBLIC_HUB_WEBSERVER_PORT: {{ quote .Values.exposedNodePort }}
{{- end -}}
{{- end -}}

{{/*
Enable IPV6
*/}}
{{- define "enableIPV6" -}}
{{- if .Values.enableIPV6 -}}
IPV4_ONLY: "0"
{{- else -}}
IPV4_ONLY: "1"
{{- end -}}
{{- end -}}

{{/*
Custom Redis
*/}}
{{- define "customRedis" -}}
BLACKDUCK_REDIS_TLS_ENABLED: "{{ .Values.redis.tlsEnabled }}"
BLACKDUCK_REDIS_MAX_TOTAL_CONN: "{{ .Values.redis.maxTotal }}"
BLACKDUCK_REDIS_MAX_IDLE_CONN: "{{ .Values.redis.maxIdle }}"
{{- end -}}

{{/*
Common Volume mount
*/}}
{{- define "common.volume.mount" -}}
{{- with .Values.proxyCertSecretName }}
- mountPath: /tmp/secrets/HUB_PROXY_CERT_FILE
  name: proxy-certificate
  subPath: HUB_PROXY_CERT_FILE
{{- end }}
{{- with .Values.proxyPasswordSecretName }}
- mountPath: /tmp/secrets/HUB_PROXY_PASSWORD_FILE
  name: proxy-password
  subPath: HUB_PROXY_PASSWORD_FILE
{{- end }}
{{- with .Values.ldapPasswordSecretName }}
- mountPath: /tmp/secrets/LDAP_TRUST_STORE_PASSWORD_FILE
  name: ldap-password
  subPath: LDAP_TRUST_STORE_PASSWORD_FILE
{{- end }}
{{- with .Values.serviceAccPasswordsSecretName }}
- mountPath: /tmp/secrets/HUB_SERVICE_GENAI_OLD_PASSWORD_FILE
  name: service-acc-passwords
  subPath: HUB_SERVICE_GENAI_OLD_PASSWORD_FILE
- mountPath: /tmp/secrets/HUB_SERVICE_GENAI_CURRENT_PASSWORD_FILE
  name: service-acc-passwords
  subPath: HUB_SERVICE_GENAI_CURRENT_PASSWORD_FILE
{{- end }}
{{- with .Values.jwtKeyPairSecretName }}
- mountPath: /tmp/secrets/JWT_PUBLIC_KEY
  name: jwt-keypair
  subPath: JWT_PUBLIC_KEY
- mountPath: /tmp/secrets/JWT_PRIVATE_KEY
  name: jwt-keypair
  subPath: JWT_PRIVATE_KEY
{{- end }}
{{- end -}}

{{/*
Common Volumes
*/}}
{{- define "common.volumes" -}}
{{- if .Values.proxyCertSecretName }}
- name: proxy-certificate
  secret:
    defaultMode: 420
    items:
    - key: HUB_PROXY_CERT_FILE
      mode: 420
      path: HUB_PROXY_CERT_FILE
    secretName: {{ .Values.proxyCertSecretName }}
{{- end }}
{{- if .Values.proxyPasswordSecretName }}
- name: proxy-password
  secret:
    defaultMode: 420
    items:
    - key: HUB_PROXY_PASSWORD_FILE
      mode: 420
      path: HUB_PROXY_PASSWORD_FILE
    secretName: {{ .Values.proxyPasswordSecretName }}
{{- end }}
{{- if .Values.ldapPasswordSecretName }}
- name: ldap-password
  secret:
    defaultMode: 420
    items:
    - key: LDAP_TRUST_STORE_PASSWORD_FILE
      mode: 420
      path: LDAP_TRUST_STORE_PASSWORD_FILE
    secretName: {{ .Values.ldapPasswordSecretName }}
{{- end }}
{{- if .Values.serviceAccPasswordsSecretName }}
- name: service-acc-passwords
  secret:
    defaultMode: 420
    secretName: {{ .Values.serviceAccPasswordsSecretName }}
{{- end }}
{{- if .Values.jwtKeyPairSecretName }}
- name: jwt-keypair
  secret:
    defaultMode: 420
    secretName: {{ .Values.jwtKeyPairSecretName }}
{{- end }}
{{- end -}}

{{/*
# Override imagePullPolicy.  Caller should pass in the .Values.<servicename> scope.
*/}}
{{- define "customImagePullPolicy" -}}
{{- if .imagePullPolicy }}
imagePullPolicy: {{ .imagePullPolicy }}
{{- else -}}
imagePullPolicy: IfNotPresent
{{- end -}}
{{- end -}}

{{/*
# ALE based secret volume mount and volume definitions
*/}}
{{- define "bd.ale.volumemounts" }}
{{- if .Values.enableApplicationLevelEncryption }}
- name: crypto-secrets
  mountPath: "/opt/crypto-framework/secrets"
  readOnly: true
{{- end -}}
{{- end -}}
{{- define "bd.ale.volumes" }}
{{- if .Values.enableApplicationLevelEncryption }}
- name: crypto-secrets
  projected:
    sources:
    - secret:
        name: crypto-root-seed
        items:
        - key: crypto-root-seed
          path: root/seed
    - secret:
        name: crypto-prev-seed
        optional: true
        items:
        - key: crypto-prev-seed
          path: prev/seed
    - secret:
        name: crypto-backup-seed
        optional: true
        items:
        - key: crypto-backup-seed
          path: backup/seed
{{- end -}}
{{- end -}}

{{/*
# Derive a value for HUB_MAX_MEMORY from .resources.limits.memory.
# The scope is expected to be one of the services; e.g., .Values.jobrunner.
*/}}
{{- define "computeHubMaxMemory" }}
{{- if (ne (dig "resources" "limits" "memory" "none" .) "none") }}
{{- $rawMemLimit := .resources.limits.memory | replace "i" "" -}}
{{- $memoryUnit := regexFind "[gmGM]" $rawMemLimit | upper -}}
{{- $numericMemLimit := trimSuffix $memoryUnit $rawMemLimit -}}
{{- $memLimitInMB := (mul $numericMemLimit (ternary 1024 1 (eq $memoryUnit "G"))) -}}
{{- $rawRamPercentage := coalesce .maxRamPercentage $.maxRamPercentage 90 -}}
{{- $maxRamPercentage := divf $rawRamPercentage 100.0 -}}
{{- if (lt (mulf $memLimitInMB $maxRamPercentage) 256.0) }}
{{- $maxRamPercentage := divf (subf $memLimitInMB 256.0) $memLimitInMB -}}
{{- end }}
{{- cat (round (mulf $memLimitInMB $maxRamPercentage) 0) "m" | nospace -}}
{{- else }}
{{- .hubMaxMemory }}
{{- end -}}
{{- end -}}
