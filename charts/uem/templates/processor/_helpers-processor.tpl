{{/*
processor fullname
*/}}
{{ define "uem.processorFullname" -}}
{{- printf " %s" "processor" }}
{{- end }}

{{/*
processor common labels
*/}}
{{ define "uem.processorLabels" -}}
{{ include "uem.labels" . }}
app.kubernetes.io/name: {{- include "uem.processorFullname" . }}
{{- end }}

{{/*
processor selector labels
*/}}
{{ define "uem.processorSelectorLabels" -}}
{{ include "uem.selectorLabels" . }}
app.kubernetes.io/name: {{ include "uem.processorFullname" . }}
{{- end }}