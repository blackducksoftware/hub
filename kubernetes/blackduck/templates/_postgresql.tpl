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
HUB_POSTGRES_ENABLE_SSL_CERT_AUTH: "false"
{{- else -}}
HUB_POSTGRES_ENABLE_SSL: "false"
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
{{- end }}
