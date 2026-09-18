{{/*
www fullname
*/}}
{{- define "uem.wwwFullname" -}}
{{- printf " %s" "www" }}
{{- end }}

{{/*
www common labels
*/}}
{{- define "uem.wwwLabels" -}}
{{ include "uem.labels" . }}
app.kubernetes.io/name: {{- include "uem.wwwFullname" . }}
{{- end }}

{{/*
www selector labels
*/}}
{{- define "uem.wwwSelectorLabels" -}}
{{ include "uem.selectorLabels" . }}
app.kubernetes.io/name: {{ include "uem.wwwFullname" . }}
{{- end }}