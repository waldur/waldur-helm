{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "waldur.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "waldur.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "waldur.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "waldur.labels" -}}
app.kubernetes.io/name: {{ include "waldur.name" . }}
helm.sh/chart: {{ include "waldur.chart" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "waldur.postgresql.fullname" -}}
{{- if .Values.postgresql.fullnameOverride -}}
{{- .Values.postgresql.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.postgresql.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name "waldur-postgresql" | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- define "waldur.redis.fullname" -}}
{{- if .Values.redis.fullnameOverride -}}
{{- .Values.redis.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.redis.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name "waldur-redis" | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Set postgres teamId
*/}}
{{- define "waldur.postgresql.team" -}}
{{ .Values.postgresql.postgresqlHost | splitList "-" | first | quote }}
{{- end -}}

{{/*
Set postgres host
*/}}
{{- define "waldur.postgresql.host" -}}
{{ .Values.postgresql.postgresqlHost | quote }}
{{- end -}}

{{/*
Set postgres port
*/}}
{{- define "waldur.postgresql.port" -}}
"5432"
{{- end -}}

{{/*
Set postgres secret
*/}}
{{- define "waldur.postgresql.secret" -}}
{{ printf "%s.%s.credentials.postgresql.acid.zalan.do" .Values.postgresql.postgresqlUsername .Values.postgresql.postgresqlHost }}
{{- end -}}

{{/*
Set postgres database name
*/}}
{{- define "waldur.postgresql.dbname" -}}
{{ .Values.postgresql.postgresqlDatabase | quote }}
{{- end -}}

{{/*
Set postgres user
*/}}
{{- define "waldur.postgresql.user" -}}
{{ .Values.postgresql.postgresqlUsername | quote }}
{{- end -}}

{{/*
Set redis host
*/}}
{{- define "waldur.redis.host" -}}
{{- if .Values.redis.enabled -}}
{{- template "waldur.redis.fullname" . -}}-master
{{- else -}}
{{- .Values.redis.host | quote -}}
{{- end -}}
{{- end -}}

{{/*
Set redis secret
*/}}
{{- define "waldur.redis.secret" -}}
{{- if .Values.redis.enabled -}}
{{- template "waldur.redis.fullname" . -}}
{{- else -}}
{{- template "waldur.fullname" . -}}
{{- end -}}
{{- end -}}

{{/*
Set redis secretKey
*/}}
{{- define "waldur.redis.secretKey" -}}
{{- if .Values.redis.enabled -}}
"redis-password"
{{- else -}}
{{- default "redis-password" .Values.redis.existingSecretKey | quote -}}
{{- end -}}
{{- end -}}

{{/*
Set redis port
*/}}
{{- define "waldur.redis.port" -}}
{{- if .Values.redis.enabled -}}
    "6379"
{{- else -}}
{{- default "6379" .Values.redis.port | quote -}}
{{- end -}}
{{- end -}}
