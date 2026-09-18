{{/*
remote-proxy fullname
*/}}
{{- define "uem.remoteProxyFullname" -}}
{{- printf " %s" "remote-proxy" }}
{{- end }}

{{/*
remote-proxy common labels
*/}}
{{- define "uem.remoteProxyLabels" -}}
{{ include "uem.labels" . }}
app.kubernetes.io/name: {{- include "uem.remoteProxyFullname" . }}
{{- end }}

{{/*
remote-proxy selector labels
*/}}
{{- define "uem.remoteProxySelectorLabels" -}}
{{ include "uem.selectorLabels" . }}
app.kubernetes.io/name: {{ include "uem.remoteProxyFullname" . }}
{{- end }}