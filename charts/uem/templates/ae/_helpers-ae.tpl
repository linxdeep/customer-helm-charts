{{/*
ae fullname
*/}}
{{- define "uem.aeFullname" -}}
{{- printf " %s" "ae" }}
{{- end }}

{{/*
ae common labels
*/}}
{{- define "uem.aeLabels" -}}
{{ include "uem.labels" . }}
app.kubernetes.io/name: {{- include "uem.aeFullname" . }}
{{- end }}

{{/*
ae selector labels
*/}}
{{- define "uem.aeSelectorLabels" -}}
{{ include "uem.selectorLabels" . }}
app.kubernetes.io/name: {{- include "uem.aeFullname" . }}
{{- end }}