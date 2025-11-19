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
Set postgres version
*/}}
{{- define "waldur.postgresql.version" -}}
17
{{- end -}}

{{/*
Set postgres host
*/}}
{{- define "waldur.postgresql.host" -}}
{{- if .Values.externalDB.enabled -}}
{{ .Values.externalDB.serviceName }}
{{- else if .Values.postgresqlha.enabled -}}
"{{ .Release.Name }}-postgresqlha-pgpool"
{{- else if .Values.postgresql.enabled -}}
"{{ .Release.Name }}-postgresql"
{{- else -}}
"postgresql-waldur"
{{- end -}}
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
{{- if .Values.externalDB.enabled -}}
{{ .Values.externalDB.secretName }}
{{- else if .Values.postgresqlha.enabled -}}
"{{ .Release.Name }}-postgresqlha-postgresql"
{{- else if .Values.postgresql.enabled -}}
"{{ .Release.Name }}-postgresql"
{{- else -}}
"postgresql-waldur"
{{- end -}}
{{- end -}}

{{/*
Set postgres secret password key
*/}}
{{- define "waldur.postgresql.secret.passwordKey" -}}
"password"
{{- end -}}

{{/*
Set postgres database name
*/}}
{{- define "waldur.postgresql.dbname" -}}
{{- if .Values.postgresqlha.enabled -}}
{{ .Values.postgresqlha.postgresql.database | quote }}
{{- else if .Values.postgresql.enabled -}}
{{ .Values.postgresql.auth.database | quote }}
{{- else if and .Values.externalDB.enabled .Values.externalDB.database -}}
{{ .Values.externalDB.database | quote }}
{{- else -}}
"waldur"
{{- end -}}
{{- end -}}

{{/*
Set postgres user
*/}}
{{- define "waldur.postgresql.user" -}}
{{- if .Values.postgresqlha.enabled -}}
{{ .Values.postgresqlha.postgresql.username | quote }}
{{- else if .Values.postgresql.enabled -}}
{{ .Values.postgresql.auth.username | quote }}
{{- else if and .Values.externalDB.enabled .Values.externalDB.username -}}
{{ .Values.externalDB.username | quote }}
{{- else -}}
"waldur"
{{- end -}}
{{- end -}}

{{/*
Set rabbitmq host
*/}}
{{- define "waldur.rabbitmq.rmqHost" -}}
{{- $rmqHost := "" -}}
{{- if .Values.rabbitmq.enabled -}}
{{- $rmqHost = list .Release.Name "rabbitmq" | join "-" -}}
{{- else -}}
{{- $rmqHost = .Values.rabbitmq.host -}}
{{- end -}}
{{ $rmqHost }}
{{- end -}}


{{/*
Add environment variables to configure private database
*/}}
{{- define "waldur.env.initdb" -}}
- name: PGHOST
  value: {{ include "waldur.postgresql.host" . }}

- name: PGPORT
  value: {{ include "waldur.postgresql.port" . }}

- name: PGUSER
  value: {{ include "waldur.postgresql.user" . }}

- name: PGDATABASE
  value: {{ include "waldur.postgresql.dbname" . }}

- name: PGPASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "waldur.postgresql.secret" . }}
      key: {{ include "waldur.postgresql.secret.passwordKey" . }}
{{- end -}}

{{/*
Add environment variables to configure database values and Sentry environment
*/}}
{{- define "waldur.credentials" -}}
- name: GLOBAL_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.waldur.secretKeyExistingSecret.name | default "waldur-secret" }}
      key: {{ .Values.waldur.secretKeyExistingSecret.key | default "GLOBAL_SECRET_KEY" }}

- name: POSTGRESQL_HOST
  value: {{ include "waldur.postgresql.host" . }}

- name: POSTGRESQL_PORT
  value: {{ include "waldur.postgresql.port" . }}

- name: POSTGRESQL_USER
{{ if and .Values.externalDB.enabled (not .Values.externalDB.username) }}
  valueFrom:
    secretKeyRef:
      name: {{ include "waldur.postgresql.secret" . }}
      key: username
{{ else }}
  value: {{ include "waldur.postgresql.user" . }}
{{ end }}

- name: POSTGRESQL_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "waldur.postgresql.secret" . }}
      key: {{ include "waldur.postgresql.secret.passwordKey" . }}

- name: POSTGRESQL_NAME
  value: {{ include "waldur.postgresql.dbname" . }}

{{ if .Values.readonlyDB.enabled }}
- name: POSTGRESQL_READONLY_USER
  {{ if .Values.readonlyDB.username }}
  valueFrom:
    secretKeyRef:
      name: waldur-secret
      key: READONLY_DB_USERNAME
  {{ else }}
  value: {{ include "waldur.postgresql.user" . }}
  {{ end }}

- name: POSTGRESQL_READONLY_PASSWORD
  {{ if .Values.readonlyDB.password }}
  valueFrom:
    secretKeyRef:
      name: waldur-secret
      key: READONLY_DB_PASSWORD
  {{ else }}
  valueFrom:
    secretKeyRef:
      name: {{ include "waldur.postgresql.secret" . }}
      key: {{ include "waldur.postgresql.secret.passwordKey" . }}
  {{ end }}
{{ end }}

- name: EMAIL_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.waldur.mail.existingSecret.name | default "waldur-secret" }}
      key: {{ .Values.waldur.mail.existingSecret.userKey | default "MAIL_USER" }}

- name: EMAIL_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.waldur.mail.existingSecret.name | default "waldur-secret"}}
      key: {{ .Values.waldur.mail.existingSecret.passwordKey | default "MAIL_PASSWORD"}}

- name: RABBITMQ_HOSTNAME
  value: {{ include "waldur.rabbitmq.rmqHost" . | quote }}
- name: RABBITMQ_USERNAME
  {{ if and .Values.rabbitmq.secret.name .Values.rabbitmq.secret.usernameKey }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.rabbitmq.secret.name }}
      key: {{ .Values.rabbitmq.secret.usernameKey }}
  {{ else if and (hasKey .Values.rabbitmq.auth "existingSecret") .Values.rabbitmq.auth.existingSecret.name }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.rabbitmq.auth.existingSecret.name }}
      key: {{ .Values.rabbitmq.auth.existingSecret.usernameKey }}
  {{ else }}
  valueFrom:
    secretKeyRef:
      name: "waldur-secret"
      key: "RABBITMQ_USER"
  {{ end }}
- name: RABBITMQ_PASSWORD
  {{ if and .Values.rabbitmq.secret.name .Values.rabbitmq.secret.passwordKey }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.rabbitmq.secret.name }}
      key: {{ .Values.rabbitmq.secret.passwordKey }}
  {{ else if and (hasKey .Values.rabbitmq.auth "existingSecret") .Values.rabbitmq.auth.existingSecret.name }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.rabbitmq.auth.existingSecret.name }}
      key: {{ .Values.rabbitmq.auth.existingSecret.passwordKey }}
  {{ else }}
  valueFrom:
    secretKeyRef:
      name: "waldur-secret"
      key: "RABBITMQ_PASSWORD"
  {{ end }}

{{ if .Values.waldur.sentryDSN }}
- name: SENTRY_DSN
  value: {{ .Values.waldur.sentryDSN | quote }}

- name: SENTRY_ENVIRONMENT
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
{{ end }}

{{- if .Values.waldur.remoteEduteams.existingSecret.name -}}
- name: REMOTE_EDUTEAMS_REFRESH_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ .Values.waldur.remoteEduteams.existingSecret.name }}
      key: {{ .Values.waldur.remoteEduteams.existingSecret.refreshTokenKey }}
- name: REMOTE_EDUTEAMS_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ .Values.waldur.remoteEduteams.existingSecret.name }}
      key: {{ .Values.waldur.remoteEduteams.existingSecret.clientIDKey }}
- name: REMOTE_EDUTEAMS_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ .Values.waldur.remoteEduteams.existingSecret.name }}
      key: {{ .Values.waldur.remoteEduteams.existingSecret.clientSecretKey }}
- name: REMOTE_EDUTEAMS_USERINFO_URL
  valueFrom:
    secretKeyRef:
      name: {{ .Values.waldur.remoteEduteams.existingSecret.name }}
      key: {{ .Values.waldur.remoteEduteams.existingSecret.userinfoUrlKey }}
- name: REMOTE_EDUTEAMS_TOKEN_URL
  valueFrom:
    secretKeyRef:
      name: {{ .Values.waldur.remoteEduteams.existingSecret.name }}
      key: {{ .Values.waldur.remoteEduteams.existingSecret.tokenUrlKey }}
- name: REMOTE_EDUTEAMS_SSH_API_URL
  valueFrom:
    secretKeyRef:
      name: {{ .Values.waldur.remoteEduteams.existingSecret.name }}
      key: {{ .Values.waldur.remoteEduteams.existingSecret.sshApiUrlKey }}
- name: REMOTE_EDUTEAMS_SSH_API_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ .Values.waldur.remoteEduteams.existingSecret.name }}
      key: {{ .Values.waldur.remoteEduteams.existingSecret.sshApiUsernameKey }}
- name: REMOTE_EDUTEAMS_SSH_API_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.waldur.remoteEduteams.existingSecret.name }}
      key: {{ .Values.waldur.remoteEduteams.existingSecret.sshApiPasswordKey }}
{{- end -}}

{{- if .Values.waldur.ldap.passwordExistingSecret.name -}}
- name: AUTH_LDAP_BIND_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.waldur.ldap.passwordExistingSecret.name }}
      key: {{ .Values.waldur.ldap.passwordExistingSecret.key }}
{{- end -}}

{{- if .Values.waldur.freeipa.passwordExistingSecret.name -}}
- name: FREEIPA_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.waldur.freeipa.passwordExistingSecret.name }}
      key: {{ .Values.waldur.freeipa.passwordExistingSecret.key }}
{{- end -}}

{{- if .Values.waldur.paypal.existingSecret.name -}}
- name: PAYPAL_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ .Values.waldur.paypal.existingSecret.name }}
      key: {{ .Values.waldur.paypal.existingSecret.secretKey }}
{{- end -}}

{{ if .Values.proxy.httpsProxy }}
- name: https_proxy
  value: {{ .Values.proxy.httpsProxy | quote }}
{{ end }}

{{ if .Values.proxy.httpProxy }}
- name: http_proxy
  value: {{ .Values.proxy.httpProxy | quote }}
{{ end }}

{{ if .Values.proxy.noProxy }}
- name: no_proxy
  value: {{ .Values.proxy.noProxy | quote }}
{{ end }}
{{- end -}}
