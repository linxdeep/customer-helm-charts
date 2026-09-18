{{/*
proglove fullname
*/}}
{{ define "uem.progloveFullname" -}}
{{- printf " %s" "proglove" }}
{{- end }}

{{/*
proglove common labels
*/}}
{{ define "uem.progloveLabels" -}}
{{ include "uem.labels" . }}
app.kubernetes.io/name: {{- include "uem.progloveFullname" . }}
{{- end }}

{{/*
proglove selector labels
*/}}
{{ define "uem.progloveSelectorLabels" -}}
{{ include "uem.selectorLabels" . }}
app.kubernetes.io/name: {{ include "uem.progloveFullname" . }}
{{- end }}