{{/*
Automatic env injection.

"k8s-app.env.inject" is the shared mechanism: given a map of env entries
(scalar value, or a map such as {valueFrom: ...}), it returns a `controllers`
values fragment adding them to every container and initContainer of every
controller.

User-declared env always wins: for map-form env only missing keys are added
(deep merge), for list-form env the fragment rebuilds the full list with the
injected entries prepended only when absent (mergeOverwrite replaces lists).

"k8s-app.envInjection.values" is the always-on caller. Every container gets:

  APP_NAME          the release namespace (namespace == app name by convention)
  GITHUB_PR_NUMBER  preview.prNumber (set by gitops-sync on preview renders;
                    empty elsewhere)

so apps can reference $(APP_NAME) / $(GITHUB_PR_NUMBER) in their own env
(kubelet dependent expansion — the bjw-s library emits env alphabetically and
both names sort before lower-case vars, so references resolve) without
declaring downward-API boilerplate in their values.
*/}}
{{- define "k8s-app.env.inject" -}}
{{- $injected := .env -}}
{{- $ctrls := dict -}}
{{- range $cName, $c := (.ctx.Values.controllers | default dict) -}}
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
          {{- if not (has $k $names) -}}
            {{- $entry := ternary $v (dict "value" $v) (kindIs "map" $v) -}}
            {{- $new = append $new (merge (dict "name" $k) $entry) -}}
          {{- end -}}
        {{- end -}}
        {{- if $new -}}{{- $_ := set $gOut $name (dict "env" (concat $new $env)) -}}{{- end -}}
      {{- else -}}
        {{- $envMap := $env | default dict -}}
        {{- $add := dict -}}
        {{- range $k, $v := $injected -}}
          {{- if not (hasKey $envMap $k) -}}{{- $_ := set $add $k $v -}}{{- end -}}
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

{{- define "k8s-app.envInjection.values" -}}
{{- $injected := dict
      "APP_NAME" .Release.Namespace
      "GITHUB_PR_NUMBER" (.Values.preview.prNumber | default "" | toString) -}}
{{- include "k8s-app.env.inject" (dict "ctx" . "env" $injected) -}}
{{- end -}}
