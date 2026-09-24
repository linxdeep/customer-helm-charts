{{/*
emqx fullname
*/}}
{{- define "uem.emqxFullname" -}}
{{- printf " %s" "emqx" }}
{{- end }}



{{/*
emqx job labels
*/}}
{{- define "uem.emqxJobLabels" -}}
{{ include "uem.labels" . }}
batch.kubernetes.io/name: {{- include "uem.emqxFullname" . }}
{{- end }}