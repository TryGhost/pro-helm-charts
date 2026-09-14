# pro-helm-charts

Ghost's Helm charts, published to the GitHub Pages Helm repository
`https://tryghost.github.io/pro-helm-charts`. ArgoCD and `helm` fetch it
anonymously; every release bundles its dependencies.

| Chart | What it is | Docs |
|---|---|---|
| [`charts/k8s-app`](charts/k8s-app) | Our application chart: [bjw-s `app-template`](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) semantics via the unmodified upstream `common` library, plus External Secrets injection, git-sync hot reload and per-PR preview databases. | [Manual](charts/k8s-app/README.md) |

Apps consume a chart as the single dependency of an umbrella chart in their
`.k8s/` directory; [`examples/k8s-app`](examples/k8s-app) is the reference
layout and [`charts/k8s-app/tests/snapshots`](charts/k8s-app/tests/snapshots)
what it renders to per environment.

```yaml
# .k8s/Chart.yaml
apiVersion: v2
name: myapp
version: 0.0.0
dependencies:
  - name: k8s-app
    repository: https://tryghost.github.io/pro-helm-charts
    version: 0.7.0
```

```sh
helm repo add ghost https://tryghost.github.io/pro-helm-charts
helm search repo ghost --versions
```

Working on the charts themselves (local checks, releases, Renovate, repository
settings): see [MAINTAINING.md](MAINTAINING.md).

This is a standalone repository, not a fork of bjw-s-labs/helm-charts.
Upstream code is used under Apache-2.0; see `charts/k8s-app/NOTICE`.
