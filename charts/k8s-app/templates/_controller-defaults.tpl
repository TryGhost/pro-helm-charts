{{/*
k8s-app controller defaults.

The bjw-s common library defaults Deployment strategy to Recreate, which
takes the whole workload down on every image roll and rules out HPA /
multi-replica operation. Our apps are built to run multiple replicas
(DB-level job claiming), so default every deployment/statefulset controller
to RollingUpdate instead. User-declared strategy always wins.
*/}}
{{- define "k8s-app.controllerDefaults.values" -}}
{{- $ctrls := dict -}}
{{- /* Previews are the first to go when a node is full: a low PriorityClass
       on each long-running preview controller lets other apps' pods preempt
       them. Per controller rather than defaultPodOptions so Jobs (migrations)
       stay out of it; see k8s-app.priorityClassName. A controller's own
       pod.priorityClassName or a user-set defaultPodOptions one wins (the
       latter is applied by the library itself). */ -}}
{{- $previewClass := "" -}}
{{- if not (dig "priorityClassName" "" (.Values.defaultPodOptions | default dict)) -}}
  {{- $previewClass = include "k8s-app.priorityClassName" (dict "ctx" . "job" false) -}}
{{- end -}}
{{- range $cName, $c := (.Values.controllers | default dict) -}}
  {{- $c = $c | default dict -}}
  {{- $type := (get $c "type") | default "deployment" -}}
  {{- $d := dict -}}
  {{- if and (has $type (list "deployment" "statefulset")) (not (hasKey $c "strategy")) -}}
    {{- $_ := set $d "strategy" "RollingUpdate" -}}
  {{- end -}}
  {{- if and $previewClass (has $type (list "deployment" "statefulset" "daemonset")) (not (dig "pod" "priorityClassName" "" $c)) -}}
    {{- $_ := set $d "pod" (dict "priorityClassName" $previewClass) -}}
  {{- end -}}
  {{- if $d -}}
    {{- $_ := set $ctrls $cName $d -}}
  {{- end -}}
{{- end -}}
{{- $out := dict "controllers" $ctrls -}}
{{- $dpo := dict -}}
{{- /* pull-request pod label from preview.prNumber, for `kubectl -l` selection
       and log correlation (user labels are deep-merged, so this only adds) */ -}}
{{- if .Values.preview.prNumber -}}
  {{- $_ := set $dpo "labels" (dict "pull-request" (.Values.preview.prNumber | toString)) -}}
{{- end -}}
{{- /* DO's DOKS registry integration maintains the `ghost` pull secret in
       every namespace but only attaches it to the default ServiceAccount;
       the chart uses its own SA, so attach it here. A user-set (non-empty)
       defaultPodOptions.imagePullSecrets wins — the common library defaults
       the key to [], so emptiness means "unset". */ -}}
{{- if empty (dig "imagePullSecrets" list (.Values.defaultPodOptions | default dict)) -}}
  {{- $_ := set $dpo "imagePullSecrets" (list (dict "name" "ghost")) -}}
{{- end -}}
{{- if $dpo -}}
  {{- $_ := set $out "defaultPodOptions" $dpo -}}
{{- end -}}
{{- $out | toYaml -}}
{{- end -}}
