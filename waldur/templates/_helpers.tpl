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
12
{{- end -}}

{{/*
Set postgres host
*/}}
{{- define "waldur.postgresql.host" -}}
{{- if .Values.postgresqlha.enabled -}}
"waldur-postgresqlha-pgpool"
{{- else if .Values.postgresql.enabled -}}
"waldur-postgresql"
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
{{- if .Values.postgresqlha.enabled -}}
"waldur-postgresqlha-postgresql"
{{- else if .Values.postgresql.enabled -}}
"waldur-postgresql"
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
{{- else -}}
"waldur"
{{- end -}}
{{- end -}}

{{/*
Set rabbitmq URL
*/}}
{{- define "waldur.rabbitmq.rmqUrl" -}}
{{- $rmqHost := "" -}}
{{- if .Values.rabbitmq.enabled -}}
{{- $rmqHost = list .Release.Name "rabbitmq" | join "-" -}}
{{- else -}}
{{- $rmqHost = .Values.rabbitmq.host -}}
{{- end -}}
{{- with .Values.rabbitmq -}}
amqp://{{ .auth.username }}:{{ .auth.password }}@{{ $rmqHost }}:{{ default 5672 .customAMQPPort }}
{{- end -}}
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
      name: waldur-secret
      key: GLOBAL_SECRET_KEY

- name: POSTGRESQL_HOST
  value: {{ include "waldur.postgresql.host" . }}

- name: POSTGRESQL_PORT
  value: {{ include "waldur.postgresql.port" . }}

- name: POSTGRESQL_USER
  value: {{ include "waldur.postgresql.user" . }}

- name: POSTGRESQL_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "waldur.postgresql.secret" . }}
      key: {{ include "waldur.postgresql.secret.passwordKey" . }}

- name: POSTGRESQL_NAME
  value: {{ include "waldur.postgresql.dbname" . }}

{{ if .Values.waldur.sentryDSN }}
- name: SENTRY_DSN
  value: {{ .Values.waldur.sentryDSN | quote }}

- name: SENTRY_ENVIRONMENT
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
{{ end }}

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

{{- define "waldur.env.whitelabeling" -}}

{{ if .Values.waldur.site.name }}
- name: SITE_NAME
  value: '{{ .Values.waldur.site.name }}'
{{ end }}

{{ if .Values.waldur.site.address }}
- name: SITE_ADDRESS
  value: '{{ .Values.waldur.site.address }}'
{{ end }}

{{ if .Values.waldur.site.email }}
- name: SITE_EMAIL
  value: '{{ .Values.waldur.site.email }}'
{{ end }}

{{ if .Values.waldur.site.phone }}
- name: SITE_PHONE
  value: '{{ .Values.waldur.site.phone }}'
{{ end }}

{{ if .Values.waldur.whitelabeling.shortPageTitle }}
- name: SHORT_PAGE_TITLE
  value: '{{ .Values.waldur.whitelabeling.shortPageTitle }}'
{{ end }}

{{ if .Values.waldur.whitelabeling.modePageTitle }}
- name: FULL_PAGE_TITLE
  value: '{{ .Values.waldur.whitelabeling.modePageTitle }}'
{{ end }}

{{ if .Values.waldur.whitelabeling.brandColor }}
- name: BRAND_COLOR
  value: '{{ .Values.waldur.whitelabeling.brandColor }}'
{{ end }}

{{ if .Values.waldur.whitelabeling.brandLabelColor }}
- name: BRAND_LABEL_COLOR
  value: '{{ .Values.waldur.whitelabeling.brandLabelColor }}'
{{ end }}

{{ if .Values.waldur.whitelabeling.heroLinkLabel }}
- name: HERO_LINK_LABEL
  value: '{{ .Values.waldur.whitelabeling.heroLinkLabel }}'
{{ end }}

{{ if .Values.waldur.whitelabeling.heroLinkUrl }}
- name: HERO_LINK_URL
  value: '{{ .Values.waldur.whitelabeling.heroLinkUrl }}'
{{ end }}

{{ if .Values.waldur.whitelabeling.siteDescription }}
- name: SITE_DESCRIPTION
  value: '{{ .Values.waldur.whitelabeling.siteDescription }}'
{{ end }}

{{ if .Values.waldur.currencyName }}
- name: CURRENCY_NAME
  value: '{{ .Values.waldur.currencyName }}'
{{ end }}

{{ if .Values.waldur.homeport.docsLink }}
- name: DOCS_URL
  value: '{{ .Values.waldur.homeport.docsLink }}'
{{ end }}

{{ if .Values.waldur.whitelabeling.supportPortalLink }}
- name: SUPPORT_PORTAL_URL
  value: '{{ .Values.waldur.whitelabeling.supportPortalLink }}'
{{ end }}

{{ if .Values.waldur.site.logo }}
- name: SITE_LOGO
  value: '{{ .Values.waldur.site.logo }}'
{{ end }}

{{ if .Values.waldur.whitelabeling.loginLogoPath }}
- name: LOGIN_LOGO
  value: '/etc/waldur/icons/login_logo.png'
{{ end }}

{{ if .Values.waldur.whitelabeling.sidebarLogoPath }}
- name: SIDEBAR_LOGO
  value: '/etc/waldur/icons/sidebar_logo.png'
{{ end }}

{{ if .Values.waldur.whitelabeling.poweredByLogoPath }}
- name: POWERED_BY_LOGO
  value: '/etc/waldur/icons/poweredby_logo.png'
{{ end }}

{{ if .Values.waldur.whitelabeling.faviconPath }}
- name: FAVICON
  value: '/etc/waldur/icons/favicon.ico'
{{ end }}

{{ if .Values.waldur.whitelabeling.heroImagePath }}
- name: HERO_IMAGE
  value: '/etc/waldur/icons/hero_image.jpg'
{{ end }}
{{- end -}}
