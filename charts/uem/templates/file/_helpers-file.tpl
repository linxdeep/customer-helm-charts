{{/*
file fullname
*/}}
{{- define "uem.fileFullname" -}}
{{- printf " %s" "file" }}
{{- end }}

{{/*
file common labels
*/}}
{{- define "uem.fileLabels" -}}
{{ include "uem.labels" . }}
app.kubernetes.io/name: {{- include "uem.fileFullname" . }}
{{- end }}

{{/*
file selector labels
*/}}
{{- define "uem.fileSelectorLabels" -}}
{{ include "uem.selectorLabels" . }}
app.kubernetes.io/name: {{ include "uem.fileFullname" . }}
{{- end }}