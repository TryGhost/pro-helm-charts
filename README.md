# pro-helm-charts

Ghost's Helm charts, published from this repository as OCI artifacts to
GitHub Container Registry: `oci://ghcr.io/tryghost/charts/<chart>`. The
packages are public even though this repository is private, so ArgoCD and
`helm` pull them anonymously.

| Chart | What it is |
|---|---|
| [`charts/ghost-app`](charts/ghost-app) | Our replacement for [bjw-s `app-template`](https://bjw-s-labs.github.io/helm-charts/docs/app-template/): the upstream `common` library (unmodified, pinned in `Chart.lock`) plus optional External Secrets injection and git-sync hot reload. |

This is a standalone repository, not a fork of bjw-s-labs/helm-charts. Upstream
code is used under Apache-2.0; see `charts/ghost-app/NOTICE`.

## ghost-app

`ghost-app` accepts every top-level value bjw-s `app-template` accepts
(`controllers`, `service`, `persistence`, `configMaps`, `route`, ...) with the
same semantics, because it hands the values to the same `common` library the
same way app-template does (`templates/common.yaml` is adapted from
app-template's 13-line entry point). On top of that it adds two option groups,
both **disabled by default**:

```yaml
secretsInjection:
  enabled: false        # master switch: creates the app-secrets ExternalSecret
  database: false       # additionally creates app-db-secrets (needs enabled: true)
  refreshInterval: 5m
  store:
    name: gcp-secrets-manager
    kind: ClusterSecretStore

hotReload:
  enabled: false        # git-sync init container + sidecar, dev runner in the app container
  repo: ""              # required when enabled, e.g. git@github.com:TryGhost/Scheduler.git
  ref: ""               # required when enabled, e.g. refs/pull/__PR_NUMBER__/head
  # see charts/ghost-app/values.yaml for everything else
```

### Secret injection

`secretsInjection` is the Helm version of the k8s repo's
`components/app-secrets` and `components/app-db-secrets` Kustomize components.
The rendered `ExternalSecret`s are the same resources (same names,
`app-secrets` / `app-db-secrets` target Secrets, `5m` refresh, `-1` ArgoCD
sync-wave, namespace-label GCP selector, `^(stg|prd)-.+db$` name match and the
JSON-exploding ESO template) with one difference: the namespace selector is
filled from `.Release.Namespace` instead of Kustomize's namespace transformer,
so there is no `REPLACED-BY-KUSTOMIZE` placeholder to substitute. Render with
`-n <namespace>` (or `namespace:` on a kustomize `helmCharts` entry) equal to
the destination namespace.

It assumes External Secrets Operator and the referenced `ClusterSecretStore`
exist. It creates Secrets; it never mounts or injects them. Workloads keep
mapping keys explicitly exactly as before:

```yaml
secretsInjection:
  enabled: true
  database: true

controllers:
  main:
    containers:
      main:
        env:
          db__connection__host:
            valueFrom:
              secretKeyRef:
                name: app-db-secrets
                key: host
```

Full examples: [`examples/app-secrets.yaml`](examples/app-secrets.yaml),
[`examples/app-db-secrets.yaml`](examples/app-db-secrets.yaml).

### Hot reload (PR previews)

`hotReload` is the Helm version of Scheduler's `values.hot-reload.yaml`. When
enabled it deep-merges the following into your values before rendering, and
touches nothing else (env, envFrom and your own volumes are preserved):

- `controllers.<controller>.initContainers.git-sync-init`: one-time clone of `ref`.
- `controllers.<controller>.containers.git-sync`: sidecar polling every `2s`
  (`gitSync.period`), publishing `/workspace/git/app` with git-sync's atomic
  symlink contract and keeping stale worktrees for `5m`.
- `controllers.<controller>.containers.<container>`: `command`/`args` replaced by
  `/sbin/tini -g -- sh -ec` running
  `ln -sfn /app/node_modules /workspace/node_modules` then
  `exec pnpm dev --legacy-watch --watch /workspace/git/app --exec 'sh -c "cd /workspace/git/app && exec node src/main.js"'`.
  Change `hotReload.app.{devCommand,run,nodeModules}` for other apps, or set
  `hotReload.app.args` to take over the script entirely.
- `configMaps.git-sync-hosts` with GitHub's published Ed25519 host key,
  mounted at `/etc/git-hosts/known_hosts` (host-key verification on).
- `persistence.workspace` (emptyDir), `persistence.git-sync-ssh` (only the
  `<release>-git-sync-ssh` key of `app-secrets`, mode `0440`, mounted only into
  the two git-sync containers) and `persistence.git-sync-hosts`.
- `defaultPodOptions.securityContext.fsGroup: 65533` so git-sync can read the key.

The deploy key is written to Secret Manager by the Terraform `argocd` module
and reaches `app-secrets` through `secretsInjection`, so hot reload needs
`secretsInjection.enabled: true` (or an equivalent Secret named in
`hotReload.ssh.secretName`). `__PR_NUMBER__` is still substituted by
`gitops-sync` when it snapshots the preview branch. Example:
[`examples/scheduler/values.preview.yaml`](examples/scheduler/values.preview.yaml).

### Using the chart

```yaml
# kustomize helmCharts entry (ArgoCD with --enable-helm; OCI repos need kustomize >= 5.0)
helmCharts:
  - name: ghost-app
    repo: oci://ghcr.io/tryghost/charts
    version: 0.1.0
    releaseName: scheduler
    namespace: scheduler
    valuesFile: ../../base/values.yaml
    additionalValuesFiles:
      - values.staging.yaml
```

or plain Helm:

```sh
helm install scheduler oci://ghcr.io/tryghost/charts/ghost-app --version 0.1.0 -n scheduler -f values.yaml
helm show values oci://ghcr.io/tryghost/charts/ghost-app --version 0.1.0
```

Every published release bundles the `common` version from its `Chart.lock`, so
consumers never add the bjw-s repository. Releases are also listed on the
GitHub releases page as `ghost-app-<version>` with the `.tgz` attached.

## Local development

```sh
helm repo add bjw-s https://bjw-s-labs.github.io/helm-charts
helm dependency build charts/ghost-app          # fetches charts/common-<ver>.tgz from Chart.lock
helm lint --strict charts/ghost-app -f examples/minimal.yaml
helm template app charts/ghost-app -n app -f examples/app-db-secrets.yaml
helm template scheduler charts/ghost-app -n scheduler \
  -f examples/scheduler/values.yaml -f examples/scheduler/values.preview.yaml
```

`charts/ghost-app/charts/` (downloaded archives) is git-ignored; `Chart.yaml`
and `Chart.lock` are committed. Use `helm dependency update` only when changing
`Chart.yaml` dependencies, and commit the new lock.

### Validation

`.github/workflows/validate.yaml` runs on every PR and push, and again as the
first job of every release:

- `helm dependency build` (fails if `Chart.yaml` and `Chart.lock` disagree).
- `values.schema.json` must equal the locked common schema plus
  `schemas/ghost-app.json` (see *Updating common*).
- `helm lint --strict` with each example (minimal, app-secrets,
  app-db-secrets, Scheduler staging/production/preview) and a set of values the
  schema must reject.
- `helm template` with each example plus assertions on resource names, Secret
  and store references, namespace selectors, refresh interval, sync-wave
  annotation, the untouched `{{ (.db | fromJson).* }}` ESO expressions, the
  git-sync arguments (`--period=2s`, ref, repo), the `pnpm dev` command, and
  that the SSH key is projected only into git-sync containers.
- On PRs: `charts/ghost-app` changes require a new `version` that has not been
  released.

Rendering checks prove the manifests are what we expect, and the migrated
Scheduler overlays were diffed against the current app-template + Kustomize
render (only `helm.sh/chart` labels differ). They do not prove runtime
behaviour: ESO actually finding secrets, git-sync authenticating, nodemon
restarting. Verify those on a staging/preview deployment.

### Schema

Helm validates only the top-level chart's `values.schema.json` against the
top-level values; a subchart's schema is checked against that subchart's own
values, which for a library dependency are empty. Upstream app-template solves
this by copying common's schema verbatim, and ghost-app does the same and then
adds its own properties: `values.schema.json` = common's schema +
`schemas/ghost-app.json`. Unknown keys under `secretsInjection`/`hotReload`
and invalid bjw-s values are both rejected.

## Releases

Releases are immutable: a chart version, once published, is never rebuilt or
overwritten. Every releasable change to `charts/ghost-app` therefore needs a
new `version` in `Chart.yaml` (semver: patch for fixes, minor for backwards
compatible additions, major when values or rendered resources change
incompatibly). CI blocks PRs that change the chart without a bump or reuse a
released version, and the release job skips versions that already have a
GitHub release and refuses to push over an existing GHCR tag.

Merging to `main` with a chart change runs `.github/workflows/release.yaml`:
validate, `helm dependency build` (bundling the locked common), `helm package`,
`helm push` to `oci://ghcr.io/tryghost/charts`, and a GitHub release
`ghost-app-<version>` with the `.tgz` attached. Old versions stay on GHCR, so
apps can keep pinning them. The job authenticates with `GITHUB_TOKEN` only
(`packages: write`, `contents: write`); no PAT.

### Publishing the first release (one-time setup)

Prepared locally, nothing is pushed by this repository's tooling. To go live:

1. *Settings → Actions → General → Workflow permissions* can stay at the
   restrictive default: the workflows declare job-level permissions.
2. Ruleset / branch protection on `main`: require the `validate` checks
   (`Lint and render`, `Chart version bumped`) and a review. This is what
   makes the version-bump rule enforceable.
3. Push `main`. The release workflow publishes
   `ghcr.io/tryghost/charts/ghost-app:0.1.0` and the GitHub release
   `ghost-app-0.1.0`. The first push creates the package as **private**
   (inherited from the repository).
4. Make the package public, once: *TryGhost org → Packages → `charts/ghost-app`
   → Package settings → Danger zone → Change visibility → Public*. Also
   confirm the repository is linked to the package under *Manage Actions
   access* (it is, automatically, when pushed with `GITHUB_TOKEN`), so future
   workflow runs can keep pushing. Visibility persists for all later versions.
5. Verify anonymously:
   `helm show chart oci://ghcr.io/tryghost/charts/ghost-app --version 0.1.0`
   from a machine with no `helm registry login`.
6. Install [Renovate](https://github.com/apps/renovate) on the repository (the
   config is `renovate.json`).

No GitHub Pages, `gh-pages` branch or `index.yaml` is involved. ArgoCD needs
no access to this repository: `kustomize build --enable-helm` on the
repo-server runs a plain anonymous `helm pull` against GHCR.

## Updating common (Renovate)

Renovate's native `helmv3` manager watches `charts/ghost-app/Chart.yaml` and
opens a PR when bjw-s publishes a new `common`; `helmUpdateSubChartArchives`
makes it refresh `Chart.lock` too (archives stay git-ignored). No regex
manager is involved. Every Renovate PR is review-required; nothing automerges.

What Renovate cannot do is decide what the change means for ghost-app's
public API, so the PR body carries a checklist:

1. Regenerate the schema so CI passes:

   ```sh
   helm repo add bjw-s https://bjw-s-labs.github.io/helm-charts
   helm dependency build charts/ghost-app
   tar -xzOf charts/ghost-app/charts/common-*.tgz common/values.schema.json \
     | jq --slurpfile ext charts/ghost-app/schemas/ghost-app.json '
         .["$id"] = "https://github.com/TryGhost/pro-helm-charts/blob/main/charts/ghost-app/values.schema.json"
         | .title = "ghost-app values"
         | .description = "bjw-s common library values (embedded verbatim from the locked common dependency) plus the options ghost-app adds: secretsInjection and hotReload."
         | .properties += $ext[0]' > charts/ghost-app/values.schema.json
   ```

2. Pick the ghost-app version. For minor/patch common updates Renovate
   already bumps ghost-app's patch version (`bumpVersion: patch`); raise it to
   minor if the update exposes new features you want to advertise. For
   **major** common updates Renovate deliberately does not bump anything and
   labels the PR `breaking-upstream`: that PR is the compatibility PR. Read
   the upstream upgrade guide, render `examples/scheduler` against the old and
   new version, and either absorb small differences in `templates/` (minor
   bump) or release a new ghost-app major with migration notes in this README.
   The wrapper does not eliminate upstream breaking changes; it gives one
   place to handle them.

3. Merge; the release workflow publishes the new version.

The git-sync image (`hotReload.gitSync.image`) and the pinned GitHub Actions
are updated by Renovate the same way (review-required, patch bump reminder).

## Versioning and adoption

Apps pin a ghost-app version in their `helmCharts` entry and upgrade
independently; each release bundles its own common, so upgrading one app never
forces another. To roll back, set `version:` back to the previous release
(all versions remain on GHCR) and let ArgoCD sync.

## Migrating Scheduler from app-template

The migrated layout is in [`examples/scheduler`](examples/scheduler); it was
rendered through `kubectl kustomize --enable-helm` with the k8s repo's
components and diffed against the current app-template render: same resource
set in staging, production and preview, identical specs, only
`helm.sh/chart: ghost-app-0.1.0` labels and standard labels on the
ExternalSecrets differ.

In `Scheduler/.k8s`:

1. `base/kustomization.yaml`: remove the `components:` block referencing
   `components/app-secrets` and `components/app-db-secrets`. Keep
   `namespace: scheduler`.
2. `base/values.yaml`: add

   ```yaml
   secretsInjection:
     enabled: true
     database: true
   ```

3. Every overlay's `helmCharts` entry: `name: ghost-app`,
   `repo: oci://ghcr.io/tryghost/charts`, `version: 0.1.0`.
4. `overlays/preview`: delete `values.hot-reload.yaml` and its
   `additionalValuesFiles` entry; append to `values.preview.yaml`:

   ```yaml
   hotReload:
     enabled: true
     repo: git@github.com:TryGhost/Scheduler.git
     ref: refs/pull/__PR_NUMBER__/head
   ```

   `components/db-previews` and `components/gateway-api-name-refs` stay.

In the k8s repo, once no app references them, delete
`components/app-secrets` and `components/app-db-secrets`, and drop the
`REPLACED-BY-KUSTOMIZE` render check from `gitops-sync.yml` (or leave it: it
simply never matches). Update the README's secret convention sections to
point at `secretsInjection`.
