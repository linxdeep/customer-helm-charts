{{/*
apple fullname
*/}}
{{- define "uem.appleFullname" -}}
{{- printf " %s" "apple" }}
{{- end }}

{{/*
apple common labels
*/}}
{{- define "uem.appleLabels" -}}
{{ include "uem.labels" . }}
app.kubernetes.io/name: {{- include "uem.appleFullname" . }}
{{- end }}

{{/*
apple selector labels
*/}}
{{- define "uem.appleSelectorLabels" -}}
{{ include "uem.selectorLabels" . }}
app.kubernetes.io/name: {{ include "uem.appleFullname" . }}
{{- end }}