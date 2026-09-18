{{/*
device-stats fullname
*/}}
{{- define "uem.deviceStatsFullname" -}}
{{- printf " %s" "device-stats" }}
{{- end }}

{{/*
device-stats common labels
*/}}
{{- define "uem.deviceStatsLabels" -}}
{{ include "uem.labels" . }}
app.kubernetes.io/name: {{- include "uem.deviceStatsFullname" . }}
{{- end }}

{{/*
device-stats selector labels
*/}}
{{- define "uem.deviceStatsSelectorLabels" -}}
{{ include "uem.selectorLabels" . }}
app.kubernetes.io/name: {{ include "uem.deviceStatsFullname" . }}
{{- end }}