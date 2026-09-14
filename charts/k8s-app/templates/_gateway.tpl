{{/*
Gateway attachment.

Every route selects its gateway with `route.<id>.gateway`:

  shared-internal (default) | shared-external | dedicated-internal | dedicated-external

or states `parentRefs` explicitly (the escape hatch; gaps are filled with
namespace `default` and sectionName `https`). `shared-*` resolves to the
terraform-managed per-cluster Gateways named in `gateway.shared`.
`dedicated-*` resolves to a Gateway rendered by this chart in the release
namespace — one per referenced network, each its own DO load balancer —
together with a cert-manager Certificate for the attached routes' hostnames
and a catch-all HTTP->HTTPS redirect (see gateway.yaml,
gateway-certificate.yaml, gateway-redirect.yaml).

The helpers derive everything from the route values alone (never from
mutated state), so templates/common.yaml and the gateway-* manifests agree
regardless of render order.
*/}}

{{- define "k8s-app.gateway.selectors" -}}
shared-internal shared-external dedicated-internal dedicated-external
{{- end -}}

{{/* The route's gateway selector, validated. ctx: dict id, route */}}
{{- define "k8s-app.gateway.selectorFor" -}}
{{- $s := .route.gateway | default "shared-internal" -}}
{{- if not (has $s (splitList " " (include "k8s-app.gateway.selectors" .))) -}}
  {{- fail (printf "route '%s': gateway '%s' is not one of: %s" .id $s (include "k8s-app.gateway.selectors" .)) -}}
{{- end -}}
{{- $s -}}
{{- end -}}

{{/* ctx: dict rootContext, network */}}
{{- define "k8s-app.gateway.dedicatedName" -}}
{{- printf "%s-gateway-%s" .rootContext.Release.Namespace .network -}}
{{- end -}}

{{/* Whether a route entry is enabled (bjw-s semantics: default true). */}}
{{- define "k8s-app.gateway.routeEnabled" -}}
{{- if kindIs "map" . -}}
  {{- if hasKey . "enabled" -}}{{ .enabled }}{{- else -}}true{{- end -}}
{{- else -}}false{{- end -}}
{{- end -}}

{{/*
Networks ("internal"/"external") for which a dedicated Gateway must be
rendered: one per network referenced by an enabled route's selector.
Rendered as a JSON array. rootContext as context.
*/}}
{{- define "k8s-app.gateway.dedicatedNetworks" -}}
{{- $nets := list -}}
{{- range $id, $route := (.Values.route | default dict) -}}
  {{- if eq (include "k8s-app.gateway.routeEnabled" $route) "true" -}}
    {{- $s := include "k8s-app.gateway.selectorFor" (dict "id" $id "route" $route) -}}
    {{- if hasPrefix "dedicated-" $s -}}
      {{- $nets = append $nets (trimPrefix "dedicated-" $s) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $nets | uniq | toJson -}}
{{- end -}}

{{/*
Hostnames of the enabled routes attached to a dedicated network, for its
Certificate. ctx: dict rootContext, network. Rendered as a JSON array.
*/}}
{{- define "k8s-app.gateway.dedicatedHostnames" -}}
{{- $ctx := . -}}
{{- $hosts := list -}}
{{- range $id, $route := ($ctx.rootContext.Values.route | default dict) -}}
  {{- if eq (include "k8s-app.gateway.routeEnabled" $route) "true" -}}
    {{- if eq (include "k8s-app.gateway.selectorFor" (dict "id" $id "route" $route)) (printf "dedicated-%s" $ctx.network) -}}
      {{- range ($route.hostnames | default list) -}}
        {{- $hosts = append $hosts . -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $hosts | uniq | toJson -}}
{{- end -}}

{{/*
Fill each route's parentRefs before the common library renders it. Explicit
parentRefs win (gaps filled: namespace "default", sectionName "https" — the
shared-Gateway conventions); otherwise the route's selector resolves to one
ref. Dedicated refs carry no namespace: same-namespace attachment. The
library itself defaults group/kind on emission. Mutates .Values.route in
place; rootContext as context.
*/}}
{{- define "k8s-app.gateway.applyRouteDefaults" -}}
{{- $root := . -}}
{{- range $id, $route := (.Values.route | default dict) -}}
  {{- if kindIs "map" $route -}}
    {{- if empty (dig "parentRefs" list $route) -}}
      {{- $s := include "k8s-app.gateway.selectorFor" (dict "id" $id "route" $route) -}}
      {{- $ref := dict "sectionName" "https" -}}
      {{- if hasPrefix "shared-" $s -}}
        {{- $shared := index $root.Values.gateway.shared (trimPrefix "shared-" $s) -}}
        {{- $_ := set $ref "name" $shared.name -}}
        {{- $_ := set $ref "namespace" $shared.namespace -}}
      {{- else -}}
        {{- $_ := set $ref "name" (include "k8s-app.gateway.dedicatedName" (dict "rootContext" $root "network" (trimPrefix "dedicated-" $s))) -}}
      {{- end -}}
      {{- $_ := set $route "parentRefs" (list $ref) -}}
    {{- else -}}
      {{- range $route.parentRefs -}}
        {{- if not (hasKey . "namespace") }}{{ $_ := set . "namespace" "default" }}{{ end -}}
        {{- if not (hasKey . "sectionName") }}{{ $_ := set . "sectionName" "https" }}{{ end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
