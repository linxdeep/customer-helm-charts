{{/*
Expand the name of the chart.
*/}}
{{ define "uem.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{ define "uem.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{ define "uem.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{ define "uem.labels" -}}
helm.sh/chart: {{ include "uem.chart" . }}
{{ include "uem.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{ define "uem.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{ define "uem.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "uem.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Container image with optional global registry prefix.
Expects a dict: (dict "root" $ "image" .Values.<svc>.image)
*/}}
{{- define "uem.image" -}}
{{- $tag := .image.tag | default .root.Chart.AppVersion -}}
{{- if .root.Values.global.imageRegistry -}}
{{ .root.Values.global.imageRegistry }}/{{ .image.repository }}:{{ $tag }}
{{- else -}}
{{ .image.repository }}:{{ $tag }}
{{- end -}}
{{- end -}}

{{/*
Image pull secrets, merging global and per-service entries.
Expects a dict: (dict "root" $ "imagePullSecrets" .Values.<svc>.imagePullSecrets)
*/}}
{{- define "uem.imagePullSecrets" -}}
{{- $secrets := concat (.root.Values.global.imagePullSecrets | default list) (.imagePullSecrets | default list) -}}
{{- if $secrets }}
imagePullSecrets:
{{- toYaml $secrets | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Wait for devices
*/}}
{{- define "wait-for-devices" -}}
{{- if .Values.devices.enabled }}
initContainers:
  - name: wait-for-core
    image: {{ .Values.global.waitForImage }}
    args: [ "pod", "-lapp.kubernetes.io/name=devices" ]
{{- end }}
{{- end -}}

{{/*
Wait for the emqx post-install configuration job to finish
*/}}
{{ define "wait-for-emqx" -}}
{{- if .Values.emqx.bootstrap.enabled }}
initContainers:
  - name: wait-for-emqx
    image: {{ .Values.global.waitForImage }}
    args: ["job", "-lbatch.kubernetes.io/name=emqx"]
{{- end }}
{{- end }}

{{/*
Wait for the uemctl initialization job to finish
*/}}
{{ define "wait-for-uemctl" -}}
{{- if .Values.uemctl.enabled }}
initContainers:
  - name: wait-for-uemctl
    image: {{ .Values.global.kubectlImage }}
    command:
      - /bin/sh
      - -c
      - |
        while ! kubectl get job uemctl >/dev/null 2>&1; do
          echo "Waiting for uemctl job to be created..."
          sleep 5
        done
        if kubectl wait --for=condition=complete job/uemctl --timeout=1800s; then
          exit 0
        else
          echo "uemctl job failed or timed out"
          exit 1
        fi
{{- end }}
{{- end }}

{{/*
PVC type
*/}}
{{- define "pvc" -}}
{{- if .Values.pvc.enabled }}
{{- if eq .Values.pvc.type "s3"}}
{{- else }}
persistentVolumeClaim:
  claimName: {{ .Release.Namespace }}-data
  readOnly: false
{{- end }}
{{- else }}
emptyDir: {}
{{- end }}
{{- end -}}

{{ define "middleware-config" -}}
  {{- $files := list "cassandra.yaml" "emqx.yaml" "http.yaml" "otel.yaml" "redis.yaml" "server.yaml" "search.yaml" "aws.yaml" "license.yaml" "email.yaml"}}
  {{- if .Values.kafka.enabled }}
  {{- $files = append $files "kafka.yaml" }}
  {{- end }}
  {{- range $files }}
  - name: middleware-config
    mountPath: /data/conf/{{ . }}
    subPath: {{ . }}
  {{- end }}
{{- end -}}
