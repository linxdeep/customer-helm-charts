{{/*
devices fullname
*/}}
{{ define "uem.devicesFullname" -}}
{{- printf " %s" "devices" }}
{{- end }}

{{/*
devices common labels
*/}}
{{ define "uem.devicesLabels" -}}
{{ include "uem.labels" . }}
app.kubernetes.io/name: {{- include "uem.devicesFullname" . }}
{{- end }}

{{/*
devices selector labels
*/}}
{{ define "uem.devicesSelectorLabels" -}}
{{ include "uem.selectorLabels" . }}
app.kubernetes.io/name: {{ include "uem.devicesFullname" . }}
{{- end }}