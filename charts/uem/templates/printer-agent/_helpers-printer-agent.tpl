{{/*
device-stats fullname
*/}}
{{- define "uem.printerAgentFullname" -}}
{{- printf " %s" "printer-agent" }}
{{- end }}

{{/*
device-stats common labels
*/}}
{{- define "uem.printerAgentLabels" -}}
{{ include "uem.labels" . }}
app.kubernetes.io/name: {{- include "uem.printerAgentFullname" . }}
{{- end }}

{{/*
device-stats selector labels
*/}}
{{- define "uem.printerAgentSelectorLabels" -}}
{{ include "uem.selectorLabels" . }}
app.kubernetes.io/name: {{ include "uem.printerAgentFullname" . }}
{{- end }}