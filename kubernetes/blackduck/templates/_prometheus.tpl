{{- define "bd.prometheus.common.annotations" }}
{{- if .Values.metrics.enabled }}
prometheus.io/path: "/actuator/prometheus"
prometheus.io/port: "8081"
prometheus.io/scrape: "true"
{{- end }}
{{- end }}