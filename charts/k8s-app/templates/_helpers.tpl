{{/*
Labels for the resources k8s-app adds on top of the common library.
Helm renders templates in reverse alphabetical order, so files sorting after
common.yaml run before the library has merged its defaults into .Values;
.Values.global may therefore be absent here.
*/}}
{{- define "k8s-app.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ default .Release.Name (.Values.global | default dict).nameOverride }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Emit an External Secrets Operator (Go template) expression that reads a field
from the JSON blob under the "db" key, escaped so Helm passes it through
verbatim. Usage: {{ include "k8s-app.esoField" "private_host" }}
*/}}
{{- define "k8s-app.esoField" -}}
{{- printf "{{ (.db | fromJson).%s }}" . | squote -}}
{{- end -}}

{{/*
PriorityClass for a pod the chart emits, the one place the precedence lives:
a user-set defaultPodOptions.priorityClassName always wins; otherwise
long-running preview workloads get preview.priorityClassName and everything
else (Jobs, non-preview pods) gets none. Jobs stay out of the low class:
a preemption counts against backoffLimit (bjw-s cannot set podFailurePolicy
on the migrations Job), and the PostDelete drop Job must not depend on a
cluster-scoped PriorityClass existing at teardown.
Usage: {{ include "k8s-app.priorityClassName" (dict "ctx" $ "job" true) }}
*/}}
{{- define "k8s-app.priorityClassName" -}}
{{- $user := dig "priorityClassName" "" (.ctx.Values.defaultPodOptions | default dict) -}}
{{- if $user -}}
{{- $user -}}
{{- else if and (not .job) .ctx.Values.preview.prNumber -}}
{{- .ctx.Values.preview.priorityClassName -}}
{{- end -}}
{{- end -}}
