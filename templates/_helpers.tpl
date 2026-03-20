{{- define "coprocessor.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "coprocessor.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "coprocessor.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "coprocessor.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "coprocessor.labels" -}}
helm.sh/chart: {{ include "coprocessor.chart" . }}
{{ include "coprocessor.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "coprocessor.selectorLabels" -}}
app.kubernetes.io/name: {{ include "coprocessor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "coprocessor.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "coprocessor.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "coprocessor.sqlConfigMapName" -}}
{{- default (printf "%s-sql" (include "coprocessor.fullname" .)) .Values.sql.existingConfigMap -}}
{{- end -}}

{{- define "coprocessor.connectConfigMapName" -}}
{{- default (printf "%s-connect" (include "coprocessor.fullname" .)) .Values.connect.existingConfigMap -}}
{{- end -}}

{{- define "coprocessor.secretName" -}}
{{- printf "%s-secret" (include "coprocessor.fullname" .) -}}
{{- end -}}

{{- define "coprocessor.headlessServiceName" -}}
{{- printf "%s-headless" (include "coprocessor.fullname" .) -}}
{{- end -}}

{{- define "coprocessor.annotations" -}}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end -}}
