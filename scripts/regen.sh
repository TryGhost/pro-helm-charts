#!/usr/bin/env sh
# Regenerates every derived file in the repo. Run after any chart change and
# commit the result; CI runs the same script and fails on a dirty tree.
#
#   charts/k8s-app/values.schema.json  common's schema (from the locked
#                                      dependency archive) + schemas/k8s-app.json
#   charts/k8s-app/README.md           values tables between <!-- values --> markers
#   examples/rendered/*.yaml           helm template of every example, documents
#                                      sorted by kind + name, minus the
#                                      helm.sh/chart label so version bumps
#                                      don't touch every snapshot
#
# Needs: helm (with the bjw-s repo added), jq.
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
      | .properties += $ext[0]' > "$CHART/values.schema.json"

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

render() { # <output name> <release> <namespace> <values files...>
  out=$1 rel=$2 ns=$3; shift 3
  # documents sorted by kind + name: the library's own emission order is not
  # stable between runs (ConfigMaps in particular), and a snapshot must be
  helm template "$rel" "$CHART" -n "$ns" "$@" \
    | grep -v '^# Source: ' \
    | yq ea 'select(. != null) as $d ireduce ([]; . + [$d]) | sort_by(.kind, .metadata.name) | .[] | split_doc' \
    | grep -v '^\s*helm.sh/chart: ' > "examples/rendered/$out.yaml"
}
render minimal        app   app   -f examples/minimal.yaml
render app-secrets    app   app   -f examples/app-secrets.yaml
render app-db-secrets app   app   -f examples/app-db-secrets.yaml
for env in staging production; do
  render "myapp-$env" myapp myapp -f examples/myapp/values.base.yaml -f "examples/myapp/values.$env.yaml"
done
# preview.prNumber is a Helm parameter set by the pull-request ApplicationSet
# ({{.number}}), never written by apps; the token stands in for it here.
render myapp-preview myapp myapp -f examples/myapp/values.base.yaml -f examples/myapp/values.preview.yaml \
  --set preview.prNumber=__GITHUB_PR_NUMBER__
echo "regenerated: $CHART/values.schema.json $CHART/README.md examples/rendered/"
