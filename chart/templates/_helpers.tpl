{{/*
Expand the name of the chart.
*/}}
{{- define "devolutions-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "devolutions-server.fullname" -}}
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
{{- define "devolutions-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "devolutions-server.labels" -}}
helm.sh/chart: {{ include "devolutions-server.chart" . }}
{{ include "devolutions-server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "devolutions-server.selectorLabels" -}}
{{- if .Values.selectorLabels }}
{{- toYaml .Values.selectorLabels }}
{{- else }}
app: {{ include "devolutions-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
{{- end }}

{{/*
Get the image tag to use
*/}}
{{- define "devolutions-server.imageTag" -}}
{{- .Values.image.tag | default .Chart.AppVersion }}
{{- end }}

{{/*
Get the migration image repository
*/}}
{{- define "devolutions-server.migration.imageRepository" -}}
{{- .Values.migration.image.repository | default .Values.image.repository }}
{{- end }}

{{/*
Get the migration image tag
*/}}
{{- define "devolutions-server.migration.imageTag" -}}
{{- .Values.migration.image.tag | default (include "devolutions-server.imageTag" .) }}
{{- end }}

{{/*
Get the certificate secret name
*/}}
{{- define "devolutions-server.certificateSecretName" -}}
{{- .Values.certificate.secretName | default (printf "%s-tls" (include "devolutions-server.fullname" .)) }}
{{- end }}

{{/*
Get the certificate resource name
Defaults to certificate.secretName if set, otherwise <release>-tls
*/}}
{{- define "devolutions-server.certificateName" -}}
{{- .Values.certificate.name | default .Values.certificate.secretName | default (printf "%s-tls" (include "devolutions-server.fullname" .)) }}
{{- end }}

{{/*
Get required DVLS hostname.
*/}}
{{- define "devolutions-server.hostname" -}}
{{- required "dvls.hostname is required" .Values.dvls.hostname }}
{{- end }}

{{/*
Get required database host.
*/}}
{{- define "devolutions-server.databaseHost" -}}
{{- required "database.host is required" .Values.database.host }}
{{- end }}

{{/*
Get required database name.
*/}}
{{- define "devolutions-server.databaseName" -}}
{{- required "database.name is required" .Values.database.name }}
{{- end }}

{{/*
Selector labels formatted for kubectl -l flag.
*/}}
{{- define "devolutions-server.kubectlSelector" -}}
{{- if .Values.selectorLabels -}}
{{- $parts := list -}}
{{- range $k, $v := .Values.selectorLabels -}}
{{- $parts = append $parts (printf "%s=%s" $k $v) -}}
{{- end -}}
{{- join "," $parts -}}
{{- else -}}
app={{ include "devolutions-server.name" . }}
{{- end -}}
{{- end }}

{{/*
Whether a TLS secret should be mounted.
*/}}
{{- define "devolutions-server.tlsSecretEnabled" -}}
{{- if or .Values.certificate.enabled .Values.certificate.secretName -}}
true
{{- end }}
{{- end }}
