{{/* vim: set filetype=mustache: */}}

{{/*
### CONFIGURABLE
# if environs HUB_POSTGRES_CONNECTION_ADMIN is provided, use that, otherwise use HUB_POSTGRES_CONNECTION_ADMIN = HUB_POSTGRES_ADMIN
### END CONFIGURABLE
*/}}
{{- define "bd.postgresConnectionAdmin" -}}
{{- if not (hasKey .Values.environs "HUB_POSTGRES_CONNECTION_ADMIN") -}}
HUB_POSTGRES_CONNECTION_ADMIN: {{ .Values.postgres.adminUserName }}
{{- end -}}
{{- end -}}

{{/*
### CONFIGURABLE
# if environs HUB_POSTGRES_CONNECTION_USER is provided, use that, otherwise use HUB_POSTGRES_CONNECTION_USER = HUB_POSTGRES_USER
### END CONFIGURABLE
*/}}
{{- define "bd.postgresConnectionUser" -}}
{{- if not (hasKey .Values.environs "HUB_POSTGRES_CONNECTION_USER") -}}
HUB_POSTGRES_CONNECTION_USER: {{ .Values.postgres.userUserName }}
{{- end -}}
{{- end -}}

{{/*
# Enable SSL for External Postgres
*/}}
{{- define "enableExternalPostgresSSL" -}}
{{- if and (eq .Values.postgres.isExternal true) (eq .Values.postgres.ssl true) -}}
HUB_POSTGRES_ENABLE_SSL: "true"
{{- else -}}
HUB_POSTGRES_ENABLE_SSL: "false"
{{- end -}}
{{- end -}}

{{/*
# Enable SSL_CERT_AUTH for External Postgres
*/}}
{{- define "enableExternalPostgresCertAuth" -}}
{{- if and (eq .Values.postgres.isExternal true) (eq .Values.postgres.ssl true) (eq .Values.postgres.customCerts.useCustomCerts true) -}}
HUB_POSTGRES_ENABLE_SSL_CERT_AUTH: "true"
{{- else -}}
HUB_POSTGRES_ENABLE_SSL_CERT_AUTH: "false"
{{- end -}}
{{- end -}}

{{/*
# Environment settings dependent upon external vs. internal PostgreSQL
*/}}
{{- define "bd.postgresql.internal.vs.external" -}}
{{- if .Values.postgres.isExternal -}}
HUB_POSTGRES_IS_EXTERNAL: "true"
HUB_POSTGRES_PARAMETER_LIMIT: {{ .Values.postgres.externalParameterLimit | quote }}
{{- else -}}
HUB_POSTGRES_IS_EXTERNAL: "false"
HUB_POSTGRES_PARAMETER_LIMIT: {{ .Values.postgres.internalParameterLimit | quote }}
{{- end -}}
{{- end -}}

{{/*
# Define HUB_POSTGRES_SSL_MODE for connecting to Postgres
*/}}
{{- define "bd.postgresql.ssl.mode" -}}
{{- if .Values.postgres.sslMode -}}
HUB_POSTGRES_SSL_MODE: {{ .Values.postgres.sslMode }}
{{- else -}}
HUB_POSTGRES_SSL_MODE: ""
{{- end -}}
{{- end -}}

{{/*
# Init container to wait for PostgreSQL to come up
*/}}
{{- define "bd.postgresql.up.check.initcontainer" }}
- name: {{ .Release.Name }}-blackduck-postgres-waiter
  {{- if .Values.postgresWaiter.registry }}
  image: {{ .Values.postgresWaiter.registry }}/blackduck-postgres-waiter:{{ .Values.postgresWaiter.imageTag }}
  {{- else }}
  image: {{ .Values.registry }}/blackduck-postgres-waiter:{{ .Values.postgresWaiter.imageTag }}
  {{- end}}
  envFrom:
  - configMapRef:
      name: {{ .Release.Name }}-blackduck-config
  env:
  - name: POSTGRES_HOST
    valueFrom:
      configMapKeyRef:
        key: HUB_POSTGRES_HOST
        name: {{ .Release.Name }}-blackduck-db-config
  - name: POSTGRES_PORT
    valueFrom:
      configMapKeyRef:
        key: HUB_POSTGRES_PORT
        name: {{ .Release.Name }}-blackduck-db-config
  - name: POSTGRES_USER
    valueFrom:
      configMapKeyRef:
        key: HUB_POSTGRES_USER
        name: {{ .Release.Name }}-blackduck-db-config
  {{- include "customImagePullPolicy" .Values.postgresWaiter | nindent 2 }}
  {{- with .Values.postgresWaiter.securityContext }}
  securityContext: {{ toJson . }}
  {{- end}}
  {{- with .Values.postgresWaiter.resources }}
  resources: {{ toJson . }}
  {{- end}}
{{- end}}

{{/*
# Pick the right postgres image
*/}}
{{- define "bd.postgresql.image" }}
{{- if .Values.postgres.registry }}
  {{- if .Values.postgres.imageTag }}
image: {{ .Values.postgres.registry }}/blackduck-postgres:{{ .Values.postgres.imageTag }}
  {{- else }}
image: {{ .Values.postgres.registry }}/blackduck-postgres:{{ .Values.imageTag }}
  {{- end}}
{{- else }}
  {{- if .Values.postgres.imageTag }}
image: {{ .Values.registry }}/blackduck-postgres:{{ .Values.postgres.imageTag }}
  {{- else }}
image: {{ .Values.registry }}/blackduck-postgres:{{ .Values.imageTag }}
  {{- end}}
{{- end}}
{{- end}}

{{/*
# Volume mounts for PostgreSQL secrets
*/}}
{{- define "bd.postgresql.secrets.volumemounts" }}
- mountPath: /tmp/secrets/HUB_POSTGRES_ADMIN_PASSWORD_FILE
  name: db-passwords
  subPath: HUB_POSTGRES_ADMIN_PASSWORD_FILE
- mountPath: /tmp/secrets/HUB_POSTGRES_USER_PASSWORD_FILE
  name: db-passwords
  subPath: HUB_POSTGRES_USER_PASSWORD_FILE
{{- if and (eq .Values.postgres.ssl true) (eq .Values.postgres.customCerts.useCustomCerts true) }}
{{- if .Values.postgres.customCerts.rootCAKeyName }}
- mountPath: /tmp/secrets/HUB_POSTGRES_CA
  name: db-certs
  subPath: {{ .Values.postgres.customCerts.rootCAKeyName }}
{{- end }}
{{- if .Values.postgres.customCerts.clientCertName }}
- mountPath: /tmp/secrets/HUB_POSTGRES_CRT
  name: db-certs
  subPath: {{ .Values.postgres.customCerts.clientCertName }}
{{- end }}
{{- if .Values.postgres.customCerts.clientKeyName }}
- mountPath: /tmp/secrets/HUB_POSTGRES_KEY
  name: db-certs
  subPath: {{ .Values.postgres.customCerts.clientKeyName }}
{{- end }}
{{- if .Values.postgres.customCerts.adminClientCertName }}
- mountPath: /tmp/secrets/HUB_ADMIN_POSTGRES_CRT
  name: db-certs
  subPath: {{ .Values.postgres.customCerts.adminClientCertName }}
{{- end }}
{{- if .Values.postgres.customCerts.adminClientKeyName }}
- mountPath: /tmp/secrets/HUB_ADMIN_POSTGRES_KEY
  name: db-certs
  subPath: {{ .Values.postgres.customCerts.adminClientKeyName }}
{{- end }}
{{- end }}
{{- end }}

{{/*
# Volumes for PostgreSQL secrets
*/}}
{{- define "bd.postgresql.secrets.volumes" }}
- name: db-passwords
  secret:
    defaultMode: 420
    items:
    - key: HUB_POSTGRES_ADMIN_PASSWORD_FILE
      mode: 420
      path: HUB_POSTGRES_ADMIN_PASSWORD_FILE
    - key: HUB_POSTGRES_USER_PASSWORD_FILE
      mode: 420
      path: HUB_POSTGRES_USER_PASSWORD_FILE
    secretName: {{ .Release.Name }}-blackduck-db-creds
{{- if and (eq .Values.postgres.ssl true) (eq .Values.postgres.customCerts.useCustomCerts true) }}
- name: db-certs
  secret:
    defaultMode: 0640
    items:
  {{- if .Values.postgres.customCerts.rootCAKeyName }}
    - key: {{ .Values.postgres.customCerts.rootCAKeyName }}
      mode: 0640
      path: HUB_POSTGRES_CA
  {{- end }}
  {{- if .Values.postgres.customCerts.clientCertName }}
    - key: {{ .Values.postgres.customCerts.clientCertName }}
      mode: 0640
      path: HUB_POSTGRES_CRT
  {{- end }}
  {{- if .Values.postgres.customCerts.clientKeyName }}
    - key: {{ .Values.postgres.customCerts.clientKeyName }}
      mode: 0640
      path: HUB_POSTGRES_KEY
  {{- end }}
  {{- if .Values.postgres.customCerts.adminClientCertName }}
    - key: {{ .Values.postgres.customCerts.adminClientCertName }}
      mode: 0640
      path: HUB_ADMIN_POSTGRES_CRT
  {{- end }}
  {{- if .Values.postgres.customCerts.adminClientKeyName }}
    - key: {{ .Values.postgres.customCerts.adminClientKeyName }}
      mode: 0640
      path: HUB_ADMIN_POSTGRES_KEY
  {{- end }}
    secretName: {{ .Values.postgres.customCerts.secretName }}
{{- end }}
{{- end }}

{{/*
# Environment variables for PostgreSQL
*/}}
{{- define "bd.postgresql.secrets.env" }}
- name: PGSSLMODE
  value: {{ .Values.postgres.sslMode }}
{{- end }}
