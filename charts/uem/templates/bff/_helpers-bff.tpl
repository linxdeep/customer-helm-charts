{{/*
bff fullname
*/}}
{{ define "uem.bffFullname" -}}
{{- printf " %s" "bff" }}
{{- end }}

{{/*
bff common labels
*/}}
{{ define "uem.bffLabels" -}}
{{ include "uem.labels" . }}
app.kubernetes.io/name: {{- include "uem.bffFullname" . }}
{{- end }}

{{/*
bff selector labels
*/}}
{{ define "uem.bffSelectorLabels" -}}
{{ include "uem.selectorLabels" . }}
app.kubernetes.io/name: {{ include "uem.bffFullname" . }}
{{- end }}