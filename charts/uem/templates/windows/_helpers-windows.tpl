{{/*
windows fullname
*/}}
{{- define "uem.windowsFullname" -}}
{{- printf " %s" "windows" }}
{{- end }}

{{/*
windows common labels
*/}}
{{- define "uem.windowsLabels" -}}
{{ include "uem.labels" . }}
app.kubernetes.io/name: {{- include "uem.windowsFullname" . }}
{{- end }}

{{/*
windows selector labels
*/}}
{{- define "uem.windowsSelectorLabels" -}}
{{ include "uem.selectorLabels" . }}
app.kubernetes.io/name: {{ include "uem.windowsFullname" . }}
{{- end }}