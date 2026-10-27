#!/usr/bin/env sh
# Regenerates every derived file in the repo. Run after any chart change and
# commit the result; CI runs the same script and fails on a dirty tree.
#
#   charts/k8s-app/values.schema.json  common's schema (from the locked
#                                      dependency archive) + schemas/k8s-app.json
#   charts/k8s-app/README.md           values tables between <!-- values --> markers
#   charts/k8s-app/tests/snapshots/    helm template of examples/k8s-app per
#                                      environment, documents sorted by kind +
#                                      name, minus the helm.sh/chart label so
#                                      version bumps don't touch every snapshot,
#                                      and chart-default image tags replaced by
#                                      __DEFAULT_TAG__ so Renovate image bumps
#                                      don't either
#
# Needs: helm (with the bjw-s repo added), jq, yq.
set -eu
cd "$(dirname "$0")/.."
CHART=charts/k8s-app

helm dependency build "$CHART" >/dev/null

archive=$(ls "$CHART"/charts/common-*.tgz)
tar -xzOf "$archive" common/values.schema.json \
  | jq --slurpfile ext "$CHART/schemas/k8s-app.json" '
      .["$id"] = "https://github.com/TryGhost/pro-helm-charts/blob/main/charts/k8s-app/values.schema.json"
      | .title = "k8s-app values"
      | .description = "bjw-s common library values (embedded verbatim from the locked common dependency) plus the options k8s-app adds: secretsInjection, hotReload and previewDatabase."
      | .properties.route.additionalProperties.properties += $ext[0]["x-route-extensions"]
      | .properties += ($ext[0] | del(.["x-route-extensions"]))' > "$CHART/values.schema.json"

# README values tables: regenerate every <!-- values: <prefixes> [exclude=<paths>] --> block
md="$CHART/README.md" out="$md.tmp" skip=0
: > "$out"
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    "<!-- values: "*" -->")
      printf '%s\n' "$line" >> "$out"
      spec=${line#"<!-- values: "}; spec=${spec% -->}
      prefix=${spec%% *}; exclude=""
      case "$spec" in *" exclude="*) exclude=${spec#* exclude=} ;; esac
      jq -r --arg prefix "$prefix" --arg exclude "$exclude" -f scripts/values-reference.jq "$CHART/values.schema.json" >> "$out"
      skip=1 ;;
    "<!-- /values -->") skip=0; printf '%s\n' "$line" >> "$out" ;;
    *) [ "$skip" = 1 ] || printf '%s\n' "$line" >> "$out" ;;
  esac
done < "$md"
mv "$out" "$md"

EX=examples/k8s-app
# Chart-default images: every repository + tag map in values.yaml, so a new
# image is masked without touching this script. Only the default is masked: an
# image an example overrides still shows in full. '#' is the sed delimiter as
# it can't appear in an image reference.
esc() { printf '%s' "$1" | sed 's/[][\\.*^$]/\\&/g'; }
default_tags=""
nl='
'
for img in $(yq '.. | select(tag == "!!map" and has("repository") and has("tag")) | path | "." + join(".")' "$CHART/values.yaml"); do
  repo=$(yq "$img.repository" "$CHART/values.yaml")
  tag=$(yq "$img.tag" "$CHART/values.yaml")
  # image: repo:tag, optionally as a list item's first key and/or quoted
  default_tags="$default_tags${nl}s#^\\([[:space:]]*\\(- \\)\\{0,1\\}image:[[:space:]]*[\"']\\{0,1\\}$(esc "$repo")\\):$(esc "$tag")\\([\"']\\{0,1\\}\\)\$#\\1:__DEFAULT_TAG__\\3#"
done
render() { # <output name> <values files...>
  out=$1; shift
  # documents sorted by kind + name: the library's own emission order is not
  # stable between runs (ConfigMaps in particular), and a snapshot must be
  helm template myapp "$CHART" -n myapp -f "$EX/values.base.yaml" "$@" \
    | grep -v '^# Source: ' \
    | yq ea 'select(. != null) as $d ireduce ([]; . + [$d]) | sort_by(.kind, .metadata.name) | .[] | split_doc' \
    | grep -v '^\s*helm.sh/chart: ' \
    | sed "$default_tags" > "$CHART/tests/snapshots/$out.yaml"
}
for env in staging production; do
  render "$env" -f "$EX/values.$env.yaml"
done
# preview.prNumber is a Helm parameter set by the pull-request ApplicationSet
# ({{.number}}), never written by apps; the token stands in for it here.
render preview -f "$EX/values.preview.yaml" --set preview.prNumber=__GITHUB_PR_NUMBER__
echo "regenerated: $CHART/values.schema.json $CHART/README.md $CHART/tests/snapshots/"
