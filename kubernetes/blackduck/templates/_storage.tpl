{{/*
Provider - Environment Variables
*/}}
{{- define "bd.storage.providers.environment.vars" -}}
{{- range .Values.storage.providers -}}
{{- if .enabled }}
- name: {{ printf "BLACKDUCK_STORAGE_PROVIDER_ENABLED_%v" .index | quote }}
  value: {{ .enabled | quote }}
- name: {{ printf "BLACKDUCK_STORAGE_PROVIDER_TYPE_%v" .index | quote }}
  value: {{ .type | quote }}
- name: {{ printf "BLACKDUCK_STORAGE_PROVIDER_PREFERENCE_%v" .index | quote }}
  value: {{ .preference | quote }}
{{/*
The settings readonly, migrationMode, and migrationTarget are optional and have reasonable defaults.
If provided, the appropriate env settings will be created for them
*/}}
{{- if .readonly }}
- name: {{ printf "BLACKDUCK_STORAGE_PROVIDER_READONLY_%v" .index | quote }}
  value: {{ .readonly | quote }}
{{- end }}
{{- if .migrationMode }}
- name: {{ printf "BLACKDUCK_STORAGE_PROVIDER_MIGRATION_MODE_%v" .index | quote }}
  value: {{ .migrationMode | quote }}
{{- end }}
{{- if .migrationTarget }}
- name: {{ printf "BLACKDUCK_STORAGE_PROVIDER_MIGRATION_TARGET_%v" .index | quote }}
  value: {{ .migrationTarget | quote }}
{{- end }}
{{- if eq .type "gcs" }}
- name: {{ printf "GCS_BUCKET_NAME_%v" .index | quote }}
  value: {{ required "The bucketName property is missing under provider section. Please provide a valid bucketName entry!" .bucketName | quote }}
{{- end }}
{{- if and (eq .type "gcs") (ne .storagePrefix "") }}
- name: {{ printf "GCS_STORAGE_PREFIX_%v" .index | quote }}
  value: {{ .storagePrefix | quote }}
{{- end }}
{{- end }}
{{- end }}
{{ end -}}

{{/*
Provider - Persistent Volume Claims
*/}}
{{- define "bd.storage.providers.pvcs" -}}
    {{- if gt (len .Values.storage.providers ) 0 }}
        {{- range .Values.storage.providers -}}
            {{- if eq .type "file" }}
                {{- if and .enabled (eq .existingPersistentVolumeClaimName "") }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    {{- include "bd.labelsWithoutVersion" $ | nindent 4 }}
    component: pvc
  name: {{ $.Release.Name }}-blackduck-storage-data-{{ .index }}
  namespace: {{ $.Release.Namespace }}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: {{ .pvc.size }}
  {{- if ne .pvc.existingPersistentVolumeName "" }}
  volumeName: {{ .pvc.existingPersistentVolumeName }}
  {{- end }}
  {{- if ne .pvc.storageClass "" }}
  storageClassName: {{ .pvc.storageClass }}
  {{- else if $.Values.storage.storageClass }}
  storageClassName: {{ $.Values.storage.storageClass }}
  {{- else if $.Values.storageClass }}
  storageClassName: {{ $.Values.storageClass }}
  {{- end }}
---
                {{- end }}
            {{- end }}
        {{- end }}
    {{- else -}}
{{ if and .Values.enablePersistentStorage (not .Values.storage.persistentVolumeClaimName) }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    {{- include "bd.labelsWithoutVersion" . | nindent 4 }}
    component: pvc
  name: {{ .Release.Name }}-blackduck-storage-v2-data
  namespace: {{ .Release.Namespace }}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: {{ .Values.storage.claimSize }}
  {{- if .Values.storage.storageClass }}
  storageClassName: {{ .Values.storage.storageClass }}
  {{- else if .Values.storageClass }}
  storageClassName: {{ .Values.storageClass }}
  {{- end }}
  {{- if .Values.storage.volumeName }}
  volumeName: {{ .Values.storage.volumeName }}
  {{- end -}}
{{ end }}
---
    {{- end }}
{{ end -}}

{{/*
Provider - Volumes
*/}}
{{- define "bd.storage.providers.volumes" -}}
{{- if .Values.enablePersistentStorage -}}
    {{- if gt (len .Values.storage.providers ) 0 }}
        {{- range .Values.storage.providers -}}
            {{- if and .enabled (eq .type "file") }}
- name: {{ $.Release.Name }}-blackduck-storage-data-{{ .index }}
  persistentVolumeClaim:
                {{- if eq .existingPersistentVolumeClaimName "" }}
    claimName: {{ $.Release.Name }}-blackduck-storage-data-{{ .index }}
                {{- else }}
    claimName: {{ .existingPersistentVolumeClaimName }}
                {{- end }}
            {{- end }}
        {{- end }}
    {{- else -}}
- name: {{ $.Release.Name }}-blackduck-storage-data
  persistentVolumeClaim:
    {{- if not .Values.storage.persistentVolumeClaimName }}
    claimName: {{ $.Release.Name }}-blackduck-storage-v2-data
    {{- else }}
    claimName: {{ .Values.storage.persistentVolumeClaimName }}
    {{- end }}
    {{- end }}
{{- else -}}
- emptyDir: {}
  name: dir-storage
{{- end -}}
{{ end -}}


{{/*
Provider - Volume Mounts
*/}}
{{- define "bd.storage.providers.volume.mounts" -}}
{{- if .Values.enablePersistentStorage -}}
    {{- if gt (len .Values.storage.providers ) 0 }}
        {{- range .Values.storage.providers -}}
            {{- if and .enabled (eq .type "file") }}
- name: {{ $.Release.Name }}-blackduck-storage-data-{{ .index }}
  mountPath: {{ .mountPath }}
            {{- end }}
        {{- end }}
    {{- else }}
- name: {{ $.Release.Name }}-blackduck-storage-data
  mountPath: "/opt/blackduck/hub/uploads"
    {{- end }}
{{- else -}}
- name: dir-storage
  mountPath: "/opt/blackduck/hub/uploads"
{{- end }}
{{ end -}}

