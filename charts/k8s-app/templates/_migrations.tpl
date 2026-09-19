{{/*
Migrations Job.

`migrations.enabled` renders one Job that runs `migrations.command` in the
app's own image, ordered by ArgoCD sync waves so it finishes before the
workloads start:

  -10  app-secrets / app-db-secrets ExternalSecrets (the Secrets exist)
   -2  previewDatabase create Job (the per-PR database exists)
   -1  this Job (the schema is current)
    0  Deployments and everything else

The Job's container is the app's own container (image, envFrom and env of
`migrations.controller` / `migrations.container`) with `command` replaced, so
it sees the same ConfigMap and the same injected database env — including a
preview's `db__connection__database` override. Nothing else is copied:
probes, args and lifecycle belong to the long-running container.

Rendered as a values fragment (a `type: job` controller), so the library
builds it and the chart's own env injection reaches it like any other
container. Jobs are immutable, hence Force=true,Replace=true: a new image sha
recreates and re-runs it, an unchanged one stays completed and ArgoCD sees it
in sync.
*/}}
{{- define "k8s-app.migrations.values" -}}
{{- $m := .Values.migrations -}}
{{- if not $m.command -}}
  {{- fail "migrations.enabled needs migrations.command: the command that runs the migrations (e.g. [./node_modules/.bin/knex, migrate:latest])" -}}
{{- end -}}
{{- $ctrl := get (.Values.controllers | default dict) $m.controller -}}
{{- if not $ctrl -}}
  {{- fail (printf "migrations.controller '%s' does not exist under controllers" $m.controller) -}}
{{- end -}}
{{- $src := get (($ctrl.containers) | default dict) $m.container -}}
{{- if not $src -}}
  {{- fail (printf "migrations.container '%s' does not exist under controllers.%s.containers" $m.container $m.controller) -}}
{{- end -}}
{{- $container := dict "command" $m.command -}}
{{- range $key := (list "image" "envFrom" "env") -}}
  {{- with (get $src $key) -}}
    {{- $_ := set $container $key . -}}
  {{- end -}}
{{- end -}}
{{- /* Adding this Job would rename the app's Deployment (see
k8s-app.pinSingleItemName), so pin it first. */ -}}
{{- $out := (include "k8s-app.pinSingleItemName" (dict "ctx" . "key" "controllers") | fromYaml).controllers -}}
{{- $_ := set $out "migrations" (dict
      "type" "job"
      "annotations" (dict
        "argocd.argoproj.io/sync-wave" "-1"
        "argocd.argoproj.io/sync-options" "Force=true,Replace=true")
      "job" (dict "backoffLimit" $m.backoffLimit)
      "pod" (dict "restartPolicy" "Never")
      "containers" (dict "main" $container)) -}}
{{- dict "controllers" $out | toYaml -}}
{{- end -}}

{{/*
Everything the migrations Job reads must exist before its wave.

ConfigMaps, Secrets and the ServiceAccount are wave 0 by default — the same
wave as the Deployment — so a Job at wave -1 starts before them and its pod
never gets created ("configmap ... not found", "serviceaccount ... not
found"), which stalls the sync. Move them to wave -3, ahead of the preview
database (-2) and the Job (-1). An item that sets its own sync-wave keeps it.
*/}}
{{- define "k8s-app.migrations.prerequisiteWaves" -}}
{{- $out := dict -}}
{{- range $key := (list "configMaps" "secrets" "serviceAccount") -}}
  {{- $items := (get $.Values $key) | default dict -}}
  {{- $keyOut := dict -}}
  {{- range $name, $item := $items -}}
    {{- $annotations := (dig "annotations" dict ($item | default dict)) -}}
    {{- if not (hasKey $annotations "argocd.argoproj.io/sync-wave") -}}
      {{- $_ := set $keyOut $name (dict "annotations" (dict "argocd.argoproj.io/sync-wave" "-3")) -}}
    {{- end -}}
  {{- end -}}
  {{- if $keyOut -}}{{- $_ := set $out $key $keyOut -}}{{- end -}}
{{- end -}}
{{- $out | toYaml -}}
{{- end -}}
