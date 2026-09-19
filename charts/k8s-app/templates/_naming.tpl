{{/*
Resource naming guard.

The library names an item's resource <release> while it is the only enabled
one under its key and <release>-<identifier> once there are several, so a
chart-added item (the migrations Job, hot reload's known_hosts ConfigMap)
would rename the app's own resource out from under a running release —
ArgoCD then creates the new name and prunes the old. forceRename is the only
escape from that rule: pin the app's single item to the name it already has,
unless the app names it itself.

Returns a values fragment for the given key ("controllers", "configMaps", …),
empty when there is nothing to pin.
*/}}
{{- define "k8s-app.pinSingleItemName" -}}
{{- $items := (get .ctx.Values .key) | default dict -}}
{{- $enabled := list -}}
{{- range $name, $item := $items -}}
  {{- if (dig "enabled" true ($item | default dict)) -}}{{- $enabled = append $enabled $name -}}{{- end -}}
{{- end -}}
{{- $out := dict -}}
{{- if eq (len $enabled) 1 -}}
  {{- $item := (get $items (first $enabled)) | default dict -}}
  {{- if not (or (hasKey $item "forceRename") (hasKey $item "prefix") (hasKey $item "suffix")) -}}
    {{- $_ := set $out (first $enabled) (dict "forceRename" .ctx.Release.Name) -}}
  {{- end -}}
{{- end -}}
{{- dict .key $out | toYaml -}}
{{- end -}}
