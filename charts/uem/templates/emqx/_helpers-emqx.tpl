{{/*
emqx fullname
*/}}
{{- define "uem.emqxFullname" -}}
{{- printf " %s" "emqx" }}
{{- end }}

{{/*
emqx common labels
*/}}
{{- define "uem.emqxLabels" -}}
{{ include "uem.labels" . }}
app.kubernetes.io/name: {{- include "uem.emqxFullname" . }}
{{- end }}

{{/*
emqx job labels
*/}}
{{- define "uem.emqxJobLabels" -}}
{{ include "uem.labels" . }}
batch.kubernetes.io/name: {{- include "uem.emqxFullname" . }}
{{- end }}

{{/*
emqx selector labels
*/}}
{{- define "uem.emqxSelectorLabels" -}}
{{ include "uem.selectorLabels" . }}
app.kubernetes.io/name: {{ include "uem.emqxFullname" . }}
{{- end }}