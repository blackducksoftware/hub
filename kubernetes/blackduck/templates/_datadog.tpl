{{- define "bd.datadog.java.env" }}
{{- if .Values.datadog.enabled }}
- name: NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
- name: DD_APM_JAVA_OPTS
  value: -javaagent:/mnt/datadog/dd-java-agent.jar
- name: DD_SERVICE_NAME
  value: {{ .Release.Name }}-$(NAMESPACE)-{{ .serviceName}}
- name: DD_TRACE_ENABLED
  value: "true"
- name: DD_PROFILING_ENABLED
  value: "false"
- name: DD_JMXFETCH_ENABLED
  value: "true"
- name: DD_JMXFETCH_STATSD_PORT
  value: '8125'
- name: DD_TRACE_ANALYTICS_ENABLED
  value: "true"
- name: DD_INSTRUMENTATION_TELEMETRY_ENABLED
  {{- if .Values.datadog.telemetry }}
  value: "{{ .Values.datadog.telemetry.enabled | default false }}"
  {{- else }}
  value: "false"
  {{- end }}
- name: DD_TRACE_GLOBAL_TAGS
  value: env:{{ .Release.Name }}-$(NAMESPACE),service:$(DD_SERVICE_NAME)
- name: DD_LOGS_INJECTION
  value: "true"
- name: DD_AGENT_HOST
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: status.hostIP
- name: DOGSTATSD_HOST_IP
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: status.hostIP
- name: DD_ENTITY_ID
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: metadata.uid
{{- end }}
{{- end }}

{{- define "bd.datadog.client_token" }}
{{- if .Values.datadog.enabled }}
- name: DD_CLIENT_TOKEN
  value: {{ .client_token }}
{{- end }}
{{- end }}

{{- define "bd.datadog.java.volume" }}
{{- if .Values.datadog.enabled }}
- name: datadog-java-agent
  emptyDir: {}
{{- end }}
{{- end }}

{{- define "bd.datadog.java.volumemount" }}
{{- if .Values.datadog.enabled }}
- name: datadog-java-agent
  mountPath: /mnt/datadog
{{- end }}
{{- end }}

{{- define "bd.datadog.java.initcontainer" }}
{{- if .Values.datadog.enabled }}
- name: datadog-init
  {{- if .Values.datadog.registry }}
  image: {{ .Values.datadog.registry }}/blackduck-datadog:{{ .Values.datadog.imageTag }}
  {{- else }}
  image: {{ .Values.registry }}/blackduck-datadog:{{ .Values.datadog.imageTag }}
  {{- end}}
  imagePullPolicy: {{ .Values.datadog.imagePullPolicy }}
  volumeMounts:
  {{- include "bd.datadog.java.volumemount" . | indent 2 }}
{{- end }}
{{- end }}

