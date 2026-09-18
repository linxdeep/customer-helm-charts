{{/*
cronjob fullname
*/}}
{{ define "uem.cronjobFullname" -}}
{{- printf " %s" "cronjob" }}
{{- end }}

{{/*
cronjob common labels
*/}}
{{ define "uem.cronjobLabels" -}}
{{ include "uem.labels" . }}
app.kubernetes.io/name: {{- include "uem.cronjobFullname" . }}
{{- end }}

{{/*
cronjob selector labels
*/}}
{{ define "uem.cronjobSelectorLabels" -}}
{{ include "uem.selectorLabels" . }}
app.kubernetes.io/name: {{ include "uem.cronjobFullname" . }}
{{- end }}