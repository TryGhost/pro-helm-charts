{{/*
Automatic env injection.

Every container and initContainer of every controller gets:

  APP_NAME          the pod's namespace (namespace == app name by convention)
  GITHUB_PR_NUMBER  the pod's pull-request label (stamped by the pull-request
                    ApplicationSet on preview pods; empty elsewhere)

so apps can reference $(APP_NAME) / $(GITHUB_PR_NUMBER) in their own env
(kubelet dependent expansion — the bjw-s library emits env alphabetically and
both names sort before lower-case vars, so references resolve) without
declaring downward-API boilerplate in their values.

User-declared env always wins: for map-form env only missing keys are added
(deep merge), for list-form env the fragment rebuilds the full list with the
injected entries prepended only when absent (mergeOverwrite replaces lists).
*/}}
{{- define "ghost-app.envInjection.values" -}}
{{- $injected := dict
      "APP_NAME" (dict "valueFrom" (dict "fieldRef" (dict "fieldPath" "metadata.namespace")))
      "GITHUB_PR_NUMBER" (dict "valueFrom" (dict "fieldRef" (dict "fieldPath" "metadata.labels['pull-request']"))) -}}
{{- $ctrls := dict -}}
{{- range $cName, $c := (.Values.controllers | default dict) -}}
  {{- $cOut := dict -}}
  {{- range $kind := (list "containers" "initContainers") -}}
    {{- $group := (get ($c | default dict) $kind) | default dict -}}
    {{- $gOut := dict -}}
    {{- range $name, $ctr := $group -}}
      {{- $env := get ($ctr | default dict) "env" -}}
      {{- if kindIs "slice" $env -}}
        {{- $names := list -}}
        {{- range $env -}}{{- $names = append $names (get . "name") -}}{{- end -}}
        {{- $new := list -}}
        {{- range $k, $v := $injected -}}
          {{- if not (has $k $names) -}}{{- $new = append $new (merge (dict "name" $k) (deepCopy $v)) -}}{{- end -}}
        {{- end -}}
        {{- if $new -}}{{- $_ := set $gOut $name (dict "env" (concat $new $env)) -}}{{- end -}}
      {{- else -}}
        {{- $envMap := $env | default dict -}}
        {{- $add := dict -}}
        {{- range $k, $v := $injected -}}
          {{- if not (hasKey $envMap $k) -}}{{- $_ := set $add $k (deepCopy $v) -}}{{- end -}}
        {{- end -}}
        {{- if $add -}}{{- $_ := set $gOut $name (dict "env" $add) -}}{{- end -}}
      {{- end -}}
    {{- end -}}
    {{- if $gOut -}}{{- $_ := set $cOut $kind $gOut -}}{{- end -}}
  {{- end -}}
  {{- if $cOut -}}{{- $_ := set $ctrls $cName $cOut -}}{{- end -}}
{{- end -}}
{{- dict "controllers" $ctrls | toYaml -}}
{{- end -}}
