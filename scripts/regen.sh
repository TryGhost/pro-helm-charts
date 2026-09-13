#!/usr/bin/env sh
# Regenerates every derived file in the repo. Run after any chart change and
# commit the result; CI runs the same script and fails on a dirty tree.
#
#   charts/k8s-app/values.schema.json  common's schema (from the locked
#                                      dependency archive) + schemas/k8s-app.json
#   examples/rendered/*.yaml           helm template of every example, minus
#                                      the helm.sh/chart label so version bumps
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

render() { # <output name> <release> <namespace> <values files...>
  out=$1 rel=$2 ns=$3; shift 3
  helm template "$rel" "$CHART" -n "$ns" "$@" | grep -v '^\s*helm.sh/chart: ' > "examples/rendered/$out.yaml"
}
render minimal        app   app   -f examples/minimal.yaml
render app-secrets    app   app   -f examples/app-secrets.yaml
render app-db-secrets app   app   -f examples/app-db-secrets.yaml
for env in staging production preview; do
  render "myapp-$env" myapp myapp -f examples/myapp/values.yaml -f "examples/myapp/values.$env.yaml"
done
echo "regenerated: $CHART/values.schema.json examples/rendered/"
