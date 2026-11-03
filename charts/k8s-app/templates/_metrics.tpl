{{/*
k8s-app metrics port.

The PodMonitor (monitoring.yaml) selects its target by portNumber, and
prometheus-operator keeps only targets whose container declares that port, so
declare it on the `monitoring.metrics.container` container of each listed
controller. A container already declaring the port is left as is.
*/}}
{{- define "k8s-app.metrics.values" -}}
{{- $m := .Values.monitoring.metrics -}}
{{- $port := int $m.port -}}
{{- $ctrls := dict -}}
{{- range $cName := $m.controllers -}}
  {{- $c := get ($.Values.controllers | default dict) $cName | default dict -}}
  {{- $ct := get ($c.containers | default dict) $m.container -}}
  {{- if $ct -}}
    {{- $ports := $ct.ports | default list -}}
    {{- $declared := false -}}
    {{- range $ports -}}
      {{- if eq (int .containerPort) $port -}}
        {{- $declared = true -}}
      {{- else if eq (toString .name) "metrics" -}}
        {{- fail (printf "controllers.%s.containers.%s declares a port named metrics on %v, not monitoring.metrics.port %d" $cName $m.container .containerPort $port) -}}
      {{- end -}}
    {{- end -}}
    {{- if not $declared -}}
      {{- $ports = append $ports (dict "name" "metrics" "containerPort" $port "protocol" "TCP") -}}
      {{- $_ := set $ctrls $cName (dict "containers" (dict $m.container (dict "ports" $ports))) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- dict "controllers" $ctrls | toYaml -}}
{{- end -}}
