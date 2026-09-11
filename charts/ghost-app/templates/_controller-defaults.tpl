{{/*
ghost-app controller defaults.

The bjw-s common library defaults Deployment strategy to Recreate, which
takes the whole workload down on every image roll and rules out HPA /
multi-replica operation. Our apps are built to run multiple replicas
(DB-level job claiming), so default every deployment/statefulset controller
to RollingUpdate instead. User-declared strategy always wins.
*/}}
{{- define "ghost-app.controllerDefaults.values" -}}
{{- $ctrls := dict -}}
{{- range $cName, $c := (.Values.controllers | default dict) -}}
  {{- $type := (get ($c | default dict) "type") | default "deployment" -}}
  {{- if and (has $type (list "deployment" "statefulset")) (not (hasKey ($c | default dict) "strategy")) -}}
    {{- $_ := set $ctrls $cName (dict "strategy" "RollingUpdate") -}}
  {{- end -}}
{{- end -}}
{{- dict "controllers" $ctrls | toYaml -}}
{{- end -}}
