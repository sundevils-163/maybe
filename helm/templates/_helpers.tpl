{{/* Generate basic labels */}}
{{- define "maybe.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "maybe-worker.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}-worker
app.kubernetes.io/instance: {{ .Release.Name }}-worker
{{- end -}}