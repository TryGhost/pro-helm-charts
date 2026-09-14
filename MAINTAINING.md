# Maintaining pro-helm-charts

## Local development

```sh
helm repo add bjw-s https://bjw-s-labs.github.io/helm-charts
./scripts/regen.sh                            # dependency build + every derived file (see below)
helm lint --strict charts/k8s-app -f examples/k8s-app/values.base.yaml
helm template myapp charts/k8s-app -n myapp \
  -f examples/k8s-app/values.base.yaml -f examples/k8s-app/values.preview.yaml --set preview.prNumber=123
```

`charts/k8s-app/charts/` (downloaded archives) is git-ignored; `Chart.yaml`
and `Chart.lock` are committed. Use `helm dependency update` only when
changing `Chart.yaml` dependencies, and commit the new lock.

### Derived files

`scripts/regen.sh` rebuilds everything that is generated. Run it after any
chart change and commit the result; CI runs it and fails on a dirty tree.

| File | Built from |
|---|---|
| `charts/k8s-app/values.schema.json` | common's schema (from the locked archive) + `schemas/k8s-app.json` |
| `charts/k8s-app/README.md` values tables | `values.schema.json`, spliced between the `<!-- values: ... -->` markers by `scripts/values-reference.jq` |
| `charts/k8s-app/tests/snapshots/{staging,production,preview}.yaml` | `helm template` of `examples/k8s-app` per environment, documents sorted by kind and name (the library's emission order is not stable), minus the `helm.sh/chart` label so version bumps don't churn them |

The prose in `charts/k8s-app/README.md` is hand-written; only the tables
between markers are regenerated. Options k8s-app adds are documented in
`schemas/k8s-app.json` (descriptions and defaults), which is also what the
tables show; keep `values.yaml` comments and the schema in step.

### Schema

Helm validates only the top-level chart's `values.schema.json` against the
top-level values; a subchart's schema is checked against that subchart's own
values, which for a library dependency are empty. Upstream app-template solves
this by copying common's schema verbatim; k8s-app does the same and adds its
own properties. Unknown keys under the k8s-app groups and invalid bjw-s values
are both rejected.

## What CI checks

`.github/workflows/validate.yaml` runs on every PR and push, and as the first
job of every release:

- `helm dependency build` (fails if `Chart.yaml` and `Chart.lock` disagree).
- `helm lint --strict` with each environment of `examples/k8s-app`, and values the schema must reject.
- `scripts/regen.sh` leaves the tree clean (schema, README tables, snapshots).
  The snapshot diff in a PR is exactly the manifest change every app will see.
- Invariants a snapshot cannot express: no Kustomize placeholder, ESO
  `{{ (.db | fromJson).* }}` expressions untouched, nothing injected into
  containers by `secretsInjection`, hot reload leaving the app's env alone,
  the SSH key mounted only into git-sync, explicit overrides honoured.
- On PRs: `charts/k8s-app` changes require a new `version` that has not been
  released.

Snapshots prove the manifests are what we expect, not that the workloads
run. Verify ESO, git-sync and the dev runner on a staging or preview
deployment.

## Releases

Releases are immutable: a version, once published, is never rebuilt or
overwritten (the repository also has GitHub's immutable releases enabled).
Every releasable change to `charts/k8s-app` needs a new `version`; CI blocks
PRs without one or reusing a released one, and the release job skips versions
that already have a GitHub release.

Merging to `main` with a chart change runs `.github/workflows/release.yaml`:
validate, `helm dependency build` (bundling the locked common), `helm
package`, `gh release create k8s-app-<version>` with the `.tgz` attached
(assets are uploaded at creation, which is what immutable releases require and
why chart-releaser is not used), and `helm repo index --merge` into
`index.yaml` on `gh-pages`, pointing at the release asset. Old entries are
kept. Only `GITHUB_TOKEN` is used.

Repository settings this relies on:

- Public repository (GitHub Pages), Pages served from `gh-pages` / root.
- A ruleset on `main` requiring the `Lint and render` and `Chart version
  bumped` checks and a review. Without it the version-bump rule is advisory:
  direct pushes to `main` skip the PR-only check.
- Renovate installed on the repository.

## Renovate

`renovate.json`, native managers only, everything review-required:

- `helmv3` watches `Chart.yaml` for new `common` releases and refreshes
  `Chart.lock` (`helmUpdateSubChartArchives`). Minor/patch updates get an
  automatic k8s-app patch bump; majors get none plus the `breaking-upstream`
  label. Either way the PR needs `scripts/regen.sh` run and committed, and
  the snapshot diff is the review: it is the manifest change every app will
  get. For majors, read the upstream upgrade guide and either absorb the
  differences in `templates/` (minor bump) or release a k8s-app major with an
  entry under *Upgrading* in the chart README.
- `helm-values` bumps the images in `values.yaml` (git-sync, mysql). No
  digest pinning: tags render as `image:tag`. Needs regen and a patch bump.
- `github-actions` keeps the SHA pins.
