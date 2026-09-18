{{/*
uemctl fullname
*/}}
{{- define "uem.uemctlFullname" -}}
{{- printf " %s" "uemctl" }}
{{- end }}

{{/*
uemctl common labels
*/}}
{{- define "uem.uemctlLabels" -}}
{{ include "uem.labels" . }}
app.kubernetes.io/name: {{- include "uem.uemctlFullname" . }}
{{- end }}

{{/*
uemctl selector labels
*/}}
{{- define "uem.uemctlSelectorLabels" -}}
{{ include "uem.selectorLabels" . }}
app.kubernetes.io/name: {{ include "uem.uemctlFullname" . }}
{{- end }}