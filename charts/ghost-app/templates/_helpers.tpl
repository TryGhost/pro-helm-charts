{{/*
Labels for the resources ghost-app adds on top of the common library.
*/}}
{{- define "ghost-app.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ default .Release.Name .Values.global.nameOverride }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Emit an External Secrets Operator (Go template) expression that reads a field
from the JSON blob under the "db" key, escaped so Helm passes it through
verbatim. Usage: {{ include "ghost-app.esoField" "private_host" }}
*/}}
{{- define "ghost-app.esoField" -}}
{{- printf "{{ (.db | fromJson).%s }}" . | squote -}}
{{- end -}}
