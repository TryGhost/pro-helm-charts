# k8s-app

Ghost's application chart: [bjw-s `app-template`](https://bjw-s-labs.github.io/helm-charts/docs/app-template/)
semantics, provided by the unmodified upstream `common` library pinned in
`Chart.lock`, plus five option groups of our own (`preview`, `secretsInjection`,
`migrations`, `hotReload`, `previewDatabase`) and a few defaults every release gets.

This page documents every value the chart accepts. The prose explains what
each area renders and how the pieces fit; the tables under each section are
generated from `values.schema.json` by `scripts/regen.sh`, so they always
match the pinned `common` version. Descriptions in the tables are reproduced
from the upstream library (Apache-2.0, see `NOTICE`). Where an option is a raw
Kubernetes object (a `securityContext`, `resources`, `affinity`, a probe
`spec`), the table lists it once and links to the Kubernetes docs instead of
expanding every field; the schema still validates those fields.

Contents

- [Getting started](#getting-started)
- [How values become resources](#how-values-become-resources)
- [Chart-wide settings: `global`](#chart-wide-settings-global)
- [Pod defaults: `defaultPodOptions`](#pod-defaults-defaultpodoptions)
- [Workloads: `controllers`](#workloads-controllers)
  - [Pod options: `controllers.<id>.pod`](#pod-options-controllersidpod)
  - [Containers: `controllers.<id>.containers` and `initContainers`](#containers-controllersidcontainers-and-initcontainers)
- [Services: `service`](#services-service)
- [Gateway API routes: `route`](#gateway-api-routes-route)
- [Ingress: `ingress`](#ingress-ingress)
- [Storage and mounts: `persistence`](#storage-and-mounts-persistence)
- [ConfigMaps: `configMaps` and `configMapsFromFolder`](#configmaps-configmaps-and-configmapsfromfolder)
- [Secrets: `secrets` and `secretsFromFolder`](#secrets-secrets-and-secretsfromfolder)
- [Service accounts and RBAC: `serviceAccount`, `rbac`](#service-accounts-and-rbac-serviceaccount-rbac)
- [Network policies: `networkpolicies`](#network-policies-networkpolicies)
- [Prometheus monitors: `serviceMonitor`, `podMonitor`](#prometheus-monitors-servicemonitor-podmonitor)
- [Anything else: `rawResources`](#anything-else-rawresources)
- [k8s-app: preview facts `preview`](#k8s-app-preview-facts-preview)
- [k8s-app: secret injection `secretsInjection`](#k8s-app-secret-injection-secretsinjection)
- [k8s-app: migrations `migrations`](#k8s-app-migrations-migrations)
- [k8s-app: hot reload `hotReload`](#k8s-app-hot-reload-hotreload)
- [k8s-app: preview database `previewDatabase`](#k8s-app-preview-database-previewdatabase)
- [k8s-app: defaults applied to every release](#k8s-app-defaults-applied-to-every-release)
- [Upgrading](#upgrading)

## Getting started

An app ships a flat `.k8s/` directory: an umbrella `Chart.yaml` that pins
k8s-app, `values.base.yaml`, one `values.<env>.yaml` per environment and
`values.preview.yaml` for PR previews. No kustomize. gitops-sync snapshots
the directory into the k8s repo, fills `__IMAGE_SHA__` and
`__GITHUB_PR_NUMBER__`, wraps the values under the `k8s-app:` key (Helm scopes
subchart values under the dependency name) and ArgoCD renders the result with
plain Helm. The complete reference layout is
[`examples/k8s-app`](../../examples/k8s-app), and what it renders to per
environment is under [`tests/snapshots`](tests/snapshots).

```yaml
# .k8s/Chart.yaml
apiVersion: v2
name: myapp
version: 0.0.0
dependencies:
  - name: k8s-app
    repository: https://tryghost.github.io/pro-helm-charts
    version: 0.10.0
```

```yaml
# .k8s/values.base.yaml (the smallest useful app)
controllers:
  main:
    containers:
      main:
        image:
          repository: registry.digitalocean.com/ghost/myapp
          tag: __IMAGE_SHA__
service:
  main:
    controller: main
    ports:
      http:
        port: 3000
```

Outside gitops, the chart installs like any other:

```sh
helm repo add ghost https://tryghost.github.io/pro-helm-charts
helm install myapp ghost/k8s-app --version 0.10.0 -n myapp -f values.yaml
```

Every release bundles its `common` dependency, so consumers never add the
bjw-s repository.

## How values become resources

Almost every top-level key is a **map of identifiers**: `controllers.main`,
`service.main`, `persistence.data`, `configMaps.config`. The identifier is
yours; the chart names the Kubernetes object `<release>` when a key holds a
single enabled item and `<release>-<identifier>` when it holds several
(`global.alwaysAppendIdentifierToResourceName` forces the suffix always;
`forceRename`, `prefix` and `suffix` on any item override the rule). Items
refer to each other by identifier, not by name: a Service names its
`controller`, an `envFrom` names a ConfigMap by `identifier`, a mount names a
controller and container in `advancedMounts`.

Every item accepts `enabled: false`, `labels` and `annotations`. Most string
values accept Helm templates (`{{ .Release.Namespace }}`), which the schema
descriptions call out where they apply.

Values files are deep-merged in the order given, so an environment file only
states what differs from `values.base.yaml`; lists replace, maps merge. The
upstream docs for the library are the authoritative long form:
<https://bjw-s-labs.github.io/helm-charts/docs/app-template/>.

## Chart-wide settings: `global`

`nameOverride` defaults to the release name (this is the app-template
behaviour and what makes `<release>-<identifier>` naming work). A default
ServiceAccount named after the release is created unless you define your own
under `serviceAccount` or set `createDefaultServiceAccount: false`. Global
labels and annotations land on every resource; add
`propagateGlobalMetadataToPods: true` to put them on pods too.

<!-- values: global -->
| Key | Type | Default | Description |
|---|---|---|---|
| `global` | object |  | Allows for configuring chart-wide settings |
| `global.alwaysAppendIdentifierToResourceName` | boolean | `false` | Always append identifier slugs to resource names, regardless of the enabled resource count. |
| `global.annotations` | object / null |  | Set additional global annotations. Helm templates can be used. |
| `global.createDefaultServiceAccount` | boolean | `true` | When true (default), automatically create a dedicated ServiceAccount using the release name as the identifier if no serviceAccount is explicitly configured. If any serviceAccount entries are present, the default is not created and user configuration takes precedence. |
| `global.fullnameOverride` | string / null |  | Set the chart fullname definition |
| `global.labels` | object / null |  | Set additional global labels. Helm templates can be used. |
| `global.nameOverride` | string / null |  | Set the chart name |
| `global.propagateGlobalMetadataToPods` | boolean | `false` | Set to true to propagate global metadata to Pod labels. |
<!-- /values -->

## Pod defaults: `defaultPodOptions`

Everything a pod spec can carry, applied to every controller. A controller's
own `pod` block (next section) takes precedence per key when
`defaultPodOptionsStrategy` is `overwrite` (the default) or is deep-merged
when it is `merge`. This is where cluster-wide concerns live: node selectors,
tolerations, `securityContext.fsGroup`, `imagePullSecrets`. k8s-app defaults
`imagePullSecrets` to the DOKS registry integration's `ghost` secret when you
leave it empty; see [defaults](#k8s-app-defaults-applied-to-every-release).

```yaml
defaultPodOptions:
  securityContext:
    runAsNonRoot: true
  nodeSelector:
    kubernetes.io/arch: amd64
```

<!-- values: defaultPodOptionsStrategy,defaultPodOptions -->
| Key | Type | Default | Description |
|---|---|---|---|
| `defaultPodOptions` | object |  | Set default options for all controllers / pods here. Each of these options can be overridden on a controller level. Useful for setting node selectors, tolerations, security contexts, or service accounts that should apply to every pod. |
| `defaultPodOptions.affinity` | object |  | Set affinity constraint rules. Helm templates can be used. See https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity |
| `defaultPodOptions.annotations` | object / null |  | Annotations to set on the item. |
| `defaultPodOptions.automountServiceAccountToken` | boolean | `false` | Set to true to automatically mount the service account token. |
| `defaultPodOptions.dnsConfig` | object |  | Specifies the DNS parameters of a pod. Parameters specified here will be merged to the generated DNS configuration based on DNSPolicy. Configuring the `ndots` option may resolve nslookup issues on some Kubernetes setups. |
| `defaultPodOptions.dnsPolicy` | string |  | Configure the Pod DNS policy. Defaults to 'ClusterFirst' if hostNetwork is false and 'ClusterFirstWithHostNet' if hostNetwork is true. |
| `defaultPodOptions.enableServiceLinks` | boolean | `false` | Enable/disable the generation of environment variables for services. See https://kubernetes.io/docs/concepts/services-networking/connect-applications-service/#accessing-the-service |
| `defaultPodOptions.hostAliases` | array |  | Use hostAliases to add custom entries to /etc/hosts - mapping IP addresses to hostnames. See https://kubernetes.io/docs/concepts/services-networking/add-entries-to-pod-etc-hosts-with-host-aliases/ |
| `defaultPodOptions.hostIPC` | boolean | `false` | Set to true to use the host's ipc namespace. |
| `defaultPodOptions.hostNetwork` | boolean | `false` | Set to false to disable host networking on the Pod. When using hostNetwork, make sure you set dnsPolicy to 'ClusterFirstWithHostNet' |
| `defaultPodOptions.hostPID` | boolean | `false` | Set to true to use the host's pid namespace. |
| `defaultPodOptions.hostUsers` | boolean / null |  | Set to false to create a new userns for the Pod. (Requires Kubernetes 1.29 or newer) |
| `defaultPodOptions.hostname` | string |  | Set the Pod's hostname. |
| `defaultPodOptions.imagePullSecrets` | array |  | Set image pull secrets. |
| `defaultPodOptions.labels` | object / null |  | Labels to set on the item. |
| `defaultPodOptions.nodeSelector` | object |  | Node selection constraint. See https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector |
| `defaultPodOptions.priorityClassName` | string |  | Custom priority class for different treatment by the scheduler. |
| `defaultPodOptions.resizePolicy` | array |  | Pod-level resize policy for controlling container restart on resource resize. (Requires Kubernetes 1.36 or newer with InPlacePodLevelResourcesVerticalScaling enabled) |
| `defaultPodOptions.resourceClaims` | array |  | ResourceClaims defines which ResourceClaims must be allocated and reserved before the Pod is allowed to start. The resources will be made available to those containers which consume them by name. (Requires Kubernetes 1.32 or newer) |
| `defaultPodOptions.resources` | object |  | Set the resource requests / limits for the Pod. (Requires Kubernetes 1.32 or newer) |
| `defaultPodOptions.restartPolicy` | string |  | Set container restart policy. Defaults to 'Always'. When controller.type is 'cronjob' it defaults to 'Never'. |
| `defaultPodOptions.runtimeClassName` | string |  | Set a runtimeClassName other than the default one (ie: `nvidia`). |
| `defaultPodOptions.schedulerName` | string |  | Set a custom scheduler name. |
| `defaultPodOptions.schedulingGates` | array |  | SchedulingGates is an opaque list of values that if specified will block scheduling the pod. If schedulingGates is not empty, the pod will stay in the SchedulingGated state and the scheduler will not attempt to schedule the pod. See https://kubernetes.io/docs/concepts/scheduling-eviction/pod-scheduling-readiness/ |
| `defaultPodOptions.securityContext` | object |  | Configure the Security Context for the Pod. |
| `defaultPodOptions.shareProcessNamespace` | boolean / null | `false` | Allows sharing process namespace between containers in a Pod. See https://kubernetes.io/docs/tasks/configure-pod-container/share-process-namespace/ |
| `defaultPodOptions.terminationGracePeriodSeconds` | integer / null |  | Duration in seconds the pod needs to terminate gracefully. See https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#lifecycle |
| `defaultPodOptions.tolerations` | array |  | Specify taint tolerations. See https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/ |
| `defaultPodOptions.topologySpreadConstraints` | array |  | Defines topologySpreadConstraint rules. See https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/ |
| `defaultPodOptionsStrategy` | string (overwrite, merge) | `"overwrite"` | Set the strategy for the default pod options. Defaults to overwrite. overwrite: If pod-level options are set, use those instead of the defaults. merge: If pod-level options are set, merge them with the defaults. |
<!-- /values -->

## Workloads: `controllers`

A controller is one workload: `type` picks `deployment` (default),
`statefulset`, `daemonset`, `cronjob` or `job`, and the matching block
(`cronjob`, `job`, `statefulset`) carries the type-specific settings. Each
controller has its own `containers` and `initContainers` maps, an optional
`pod` block, `replicas`, `strategy` and `rollingUpdate`, a
`podDisruptionBudget`, a `horizontalPodAutoscaler` and a `serviceAccount`
reference. `defaultContainerOptions` sets image, env, resources or security
context once for every container in the controller
(`defaultContainerOptionsStrategy` decides overwrite vs merge, and
`applyDefaultContainerOptionsToInitContainers` whether init containers get
them too).

k8s-app changes one upstream default: deployments and statefulsets use
`strategy: RollingUpdate` unless you set `strategy` yourself, because the
upstream `Recreate` takes the whole workload down on every roll and rules out
multi-replica operation. Set `strategy: Recreate` explicitly for a workload
that cannot run two versions side by side (a single-writer volume, a
migration-on-start app).

```yaml
controllers:
  main:
    replicas: 2
    rollingUpdate:
      maxUnavailable: 0
    containers:
      main:
        image: {repository: registry.digitalocean.com/ghost/myapp, tag: __IMAGE_SHA__}
  nightly:
    type: cronjob
    cronjob:
      schedule: "0 3 * * *"
      timeZone: Etc/UTC
    containers:
      main:
        image: {repository: registry.digitalocean.com/ghost/myapp, tag: __IMAGE_SHA__}
        command: [node, scripts/nightly.js]
```

<!-- values: controllers exclude=controllers.<id>.pod,controllers.<id>.containers,controllers.<id>.initContainers -->
| Key | Type | Default | Description |
|---|---|---|---|
| `controllers` | object |  | Define the Pod controllers to be generated by the chart. Each key is a controller identifier. Supported types: deployment (default), statefulset, daemonset, cronjob, job. |
| `controllers.<id>.annotations` | object / null |  | Annotations to set on the item. |
| `controllers.<id>.applyDefaultContainerOptionsToInitContainers` | boolean | `true` | Apply defaultContainerOptions to initContainers. |
| `controllers.<id>.cronjob` | object |  | CronJob-specific options. |
| `controllers.<id>.cronjob.activeDeadlineSeconds` | integer |  |  |
| `controllers.<id>.cronjob.backoffLimit` | integer | `6` | Number of retries before marking the job as failed. |
| `controllers.<id>.cronjob.concurrencyPolicy` | string | `"Forbid"` | Valid values are Allow, Forbid or Replace. |
| `controllers.<id>.cronjob.failedJobsHistory` | integer | `1` | Number of failed finished jobs to retain. |
| `controllers.<id>.cronjob.parallelism` | integer |  | Maximum number of pods running at any given time. |
| `controllers.<id>.cronjob.schedule` | string |  | Cron schedule expression (e.g. '*/20 * * * *'). |
| `controllers.<id>.cronjob.startingDeadlineSeconds` | integer | `30` | Deadline in seconds for starting the job if it misses its scheduled time. |
| `controllers.<id>.cronjob.successfulJobsHistory` | integer | `1` | Number of successful finished jobs to retain. |
| `controllers.<id>.cronjob.suspend` | boolean | `false` | Suspend execution of the CronJob. See https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/#schedule-suspend for details. |
| `controllers.<id>.cronjob.timeZone` | string |  | IANA time zone name for CronJob schedule (e.g. 'Etc/UTC'). |
| `controllers.<id>.cronjob.ttlSecondsAfterFinished` | integer |  | Time in seconds after which a finished Job is eligible for automatic deletion. |
| `controllers.<id>.defaultContainerOptions` | object |  | Default options for all (init)Containers. Each can be overridden on a container level. |
| `controllers.<id>.defaultContainerOptions.args` | one of several shapes |  |  |
| `controllers.<id>.defaultContainerOptions.command` | one of several shapes |  |  |
| `controllers.<id>.defaultContainerOptions.env` | one of several shapes |  |  |
| `controllers.<id>.defaultContainerOptions.envFrom` | array |  |  |
| `controllers.<id>.defaultContainerOptions.image` | object |  |  |
| `controllers.<id>.defaultContainerOptions.image.digest` | string |  |  |
| `controllers.<id>.defaultContainerOptions.image.pullPolicy` | string (Always, IfNotPresent, Never) |  |  |
| `controllers.<id>.defaultContainerOptions.image.repository` | string |  |  |
| `controllers.<id>.defaultContainerOptions.image.tag` | string / number |  |  |
| `controllers.<id>.defaultContainerOptions.resources` | object |  | ResourceRequirements describes the compute resource requirements. |
| `controllers.<id>.defaultContainerOptions.securityContext` | object |  | SecurityContext holds security configuration that will be applied to a container. Some fields are present in both SecurityContext and PodSecurityContext.  When both are set, the values in SecurityContext take precedence. |
| `controllers.<id>.defaultContainerOptionsStrategy` | string (overwrite, merge) | `"overwrite"` | Strategy for default container options. overwrite: use container-level options if set. merge: merge container-level options with defaults. |
| `controllers.<id>.enabled` | boolean | `true` | Set to false to disable the controller. |
| `controllers.<id>.forceRename` | string |  | Override the default resource name. Mutually exclusive with prefix and suffix. |
| `controllers.<id>.horizontalPodAutoscaler` | object |  | HorizontalPodAutoscaler configuration for this controller. Only supported for deployment and statefulset types. See https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ for details. |
| `controllers.<id>.horizontalPodAutoscaler.annotations` | object / null |  | Annotations to set on the item. |
| `controllers.<id>.horizontalPodAutoscaler.behavior` | object |  | Scaling behavior configuration. Passed through directly to the autoscaling/v2 HPA spec. |
| `controllers.<id>.horizontalPodAutoscaler.labels` | object / null |  | Labels to set on the item. |
| `controllers.<id>.horizontalPodAutoscaler.maxReplicas` | integer |  | Maximum number of replicas. |
| `controllers.<id>.horizontalPodAutoscaler.metrics` | array |  | Metrics to use for scaling. Passed through directly to the autoscaling/v2 HPA spec. |
| `controllers.<id>.horizontalPodAutoscaler.minReplicas` | integer / null |  | Minimum number of replicas. Set to 0 to enable scale-to-zero when the HPAScaleToZero feature gate is enabled. |
| `controllers.<id>.job` | object |  | Job-specific options. |
| `controllers.<id>.job.activeDeadlineSeconds` | integer |  |  |
| `controllers.<id>.job.backoffLimit` | integer | `6` | Number of retries before marking the job as failed. |
| `controllers.<id>.job.completionMode` |  |  | Completion mode for the Job. |
| `controllers.<id>.job.completions` |  |  | Number of completions needed before the job is done. |
| `controllers.<id>.job.parallelism` | integer |  | Maximum number of pods running at any given time. |
| `controllers.<id>.job.suspend` | boolean | `false` | Suspend execution of the Job. See https://kubernetes.io/docs/concepts/workloads/controllers/job/#suspending-a-job for details. |
| `controllers.<id>.job.ttlSecondsAfterFinished` | integer |  | Time in seconds after which a finished Job is eligible for automatic deletion. |
| `controllers.<id>.labels` | object / null |  | Labels to set on the item. |
| `controllers.<id>.podDisruptionBudget` | object |  | PodDisruptionBudget Policy for this controller. |
| `controllers.<id>.podDisruptionBudget.maxUnavailable` | integer / string |  |  |
| `controllers.<id>.podDisruptionBudget.minAvailable` | integer / string |  |  |
| `controllers.<id>.prefix` | string | `""` | Prefix to prepend to the resource name. Mutually exclusive with forceRename. |
| `controllers.<id>.replicas` | integer / null | `1` | Number of desired pods. When a HorizontalPodAutoscaler is configured, `replicas` is automatically suppressed on the controller and propagated to HPA `minReplicas` if not explicitly set. |
| `controllers.<id>.revisionHistoryLimit` | integer |  | ReplicaSet revision history limit. |
| `controllers.<id>.rollingUpdate` | object |  | Rolling update options. Only valid when strategy is `RollingUpdate`. Both the shorthand keys (`surge`/`unavailable`) and the upstream Kubernetes keys (`maxSurge`/`maxUnavailable`) are accepted. When both are set, the Kubernetes key takes priority. The shorthand keys are deprecated and Will be removed in v6.0. |
| `controllers.<id>.rollingUpdate.maxSurge` | integer / string |  | Maximum number of pods that can be created over the desired replicas during the update. |
| `controllers.<id>.rollingUpdate.maxUnavailable` | integer / string |  | Maximum number of pods that can be unavailable during the update. |
| `controllers.<id>.rollingUpdate.partition` | integer | `0` | Partition for rolling update. When set, all pods with ordinal index < partition are updated; pods with ordinal >= partition are not touched. |
| `controllers.<id>.rollingUpdate.surge` | integer / string |  | Deprecated: use `maxSurge` instead. Will be removed in v6.0. Maximum number of pods that can be created over the desired replicas during the update. |
| `controllers.<id>.rollingUpdate.unavailable` | integer / string |  | Deprecated: use `maxUnavailable` instead. Will be removed in v6.0. Maximum number of pods that can be unavailable during the update. |
| `controllers.<id>.serviceAccount` | object |  | ServiceAccount used by the controller. Only use one of `name` or `identifier`. When both are specified, `identifier` takes priority. |
| `controllers.<id>.serviceAccount.identifier` | string |  | Reference a serviceAccount configured in this chart by its key. |
| `controllers.<id>.serviceAccount.name` | string |  | Reference a serviceAccount by its name. Helm templates are supported. |
| `controllers.<id>.statefulset` | object |  | StatefulSet-specific options. |
| `controllers.<id>.statefulset.persistentVolumeClaimRetentionPolicy` | object |  |  |
| `controllers.<id>.statefulset.persistentVolumeClaimRetentionPolicy.whenDeleted` | string (Delete, Retain) | `"Retain"` |  |
| `controllers.<id>.statefulset.persistentVolumeClaimRetentionPolicy.whenScaled` | string (Delete, Retain) | `"Retain"` |  |
| `controllers.<id>.statefulset.podManagementPolicy` | string |  | Pod management policy. Valid values are Parallel and OrderedReady (default). |
| `controllers.<id>.statefulset.serviceName` | one of several shapes |  |  |
| `controllers.<id>.statefulset.serviceName.identifier` | string |  |  |
| `controllers.<id>.statefulset.startOrdinal` | integer | `0` |  |
| `controllers.<id>.statefulset.volumeClaimTemplates` | array |  | Volume claim templates for the StatefulSet. Each entry creates a PVC per pod. |
| `controllers.<id>.strategy` | string (Recreate, RollingUpdate) | `"Recreate"` | Controller upgrade strategy. Valid values: `Recreate` or `RollingUpdate`. |
| `controllers.<id>.suffix` | string |  | Suffix to append to the resource name. Defaults to the resource identifier if there are multiple items, otherwise empty. Mutually exclusive with forceRename. |
| `controllers.<id>.type` | string (deployment, statefulset, daemonset, cronjob, job) | `"deployment"` | Controller type. Supported values: deployment, daemonset, statefulset, cronjob, job. |
<!-- /values -->

### Pod options: `controllers.<id>.pod`

The per-controller counterpart of `defaultPodOptions`, same keys. Use it when
one workload needs something the others do not (host networking for a
DaemonSet, a different `terminationGracePeriodSeconds` for a queue worker).
Remember the `defaultPodOptionsStrategy` rule: with the default `overwrite`,
setting `pod.securityContext` here replaces the whole default
`securityContext`, not just the keys you name.

<!-- values: controllers.<id>.pod -->
| Key | Type | Default | Description |
|---|---|---|---|
| `controllers.<id>.pod` | object |  | Pod-level options for this controller. |
| `controllers.<id>.pod.affinity` | object |  | Set affinity constraint rules. Helm templates can be used. See https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity |
| `controllers.<id>.pod.annotations` | object / null |  | Annotations to set on the item. |
| `controllers.<id>.pod.automountServiceAccountToken` | boolean | `false` | Set to true to automatically mount the service account token. |
| `controllers.<id>.pod.dnsConfig` | object |  | Specifies the DNS parameters of a pod. Parameters specified here will be merged to the generated DNS configuration based on DNSPolicy. Configuring the `ndots` option may resolve nslookup issues on some Kubernetes setups. |
| `controllers.<id>.pod.dnsPolicy` | string |  | Configure the Pod DNS policy. Defaults to 'ClusterFirst' if hostNetwork is false and 'ClusterFirstWithHostNet' if hostNetwork is true. |
| `controllers.<id>.pod.enableServiceLinks` | boolean | `false` | Enable/disable the generation of environment variables for services. See https://kubernetes.io/docs/concepts/services-networking/connect-applications-service/#accessing-the-service |
| `controllers.<id>.pod.hostAliases` | array |  | Use hostAliases to add custom entries to /etc/hosts - mapping IP addresses to hostnames. See https://kubernetes.io/docs/concepts/services-networking/add-entries-to-pod-etc-hosts-with-host-aliases/ |
| `controllers.<id>.pod.hostIPC` | boolean | `false` | Set to true to use the host's ipc namespace. |
| `controllers.<id>.pod.hostNetwork` | boolean | `false` | Set to false to disable host networking on the Pod. When using hostNetwork, make sure you set dnsPolicy to 'ClusterFirstWithHostNet' |
| `controllers.<id>.pod.hostPID` | boolean | `false` | Set to true to use the host's pid namespace. |
| `controllers.<id>.pod.hostUsers` | boolean / null |  | Set to false to create a new userns for the Pod. (Requires Kubernetes 1.29 or newer) |
| `controllers.<id>.pod.hostname` | string |  | Set the Pod's hostname. |
| `controllers.<id>.pod.imagePullSecrets` | array |  | Set image pull secrets. |
| `controllers.<id>.pod.labels` | object / null |  | Labels to set on the item. |
| `controllers.<id>.pod.nodeSelector` | object |  | Node selection constraint. See https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector |
| `controllers.<id>.pod.priorityClassName` | string |  | Custom priority class for different treatment by the scheduler. |
| `controllers.<id>.pod.resizePolicy` | array |  | Pod-level resize policy for controlling container restart on resource resize. (Requires Kubernetes 1.36 or newer with InPlacePodLevelResourcesVerticalScaling enabled) |
| `controllers.<id>.pod.resourceClaims` | array |  | ResourceClaims defines which ResourceClaims must be allocated and reserved before the Pod is allowed to start. The resources will be made available to those containers which consume them by name. (Requires Kubernetes 1.32 or newer) |
| `controllers.<id>.pod.resources` | object |  | Set the resource requests / limits for the Pod. (Requires Kubernetes 1.32 or newer) |
| `controllers.<id>.pod.restartPolicy` | string |  | Set container restart policy. Defaults to 'Always'. When controller.type is 'cronjob' it defaults to 'Never'. |
| `controllers.<id>.pod.runtimeClassName` | string |  | Set a runtimeClassName other than the default one (ie: `nvidia`). |
| `controllers.<id>.pod.schedulerName` | string |  | Set a custom scheduler name. |
| `controllers.<id>.pod.schedulingGates` | array |  | SchedulingGates is an opaque list of values that if specified will block scheduling the pod. If schedulingGates is not empty, the pod will stay in the SchedulingGated state and the scheduler will not attempt to schedule the pod. See https://kubernetes.io/docs/concepts/scheduling-eviction/pod-scheduling-readiness/ |
| `controllers.<id>.pod.securityContext` | object |  | Configure the Security Context for the Pod. |
| `controllers.<id>.pod.shareProcessNamespace` | boolean / null | `false` | Allows sharing process namespace between containers in a Pod. See https://kubernetes.io/docs/tasks/configure-pod-container/share-process-namespace/ |
| `controllers.<id>.pod.terminationGracePeriodSeconds` | integer / null |  | Duration in seconds the pod needs to terminate gracefully. See https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#lifecycle |
| `controllers.<id>.pod.tolerations` | array |  | Specify taint tolerations. See https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/ |
| `controllers.<id>.pod.topologySpreadConstraints` | array |  | Defines topologySpreadConstraint rules. See https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/ |
<!-- /values -->

### Containers: `controllers.<id>.containers` and `initContainers`

Both maps take the same container shape; init containers run before the app
in name order. The one container without `enabled: false` is the primary
container when only one exists, otherwise use `primary`-style selection via
the Service (see [Services](#services-service)). Notable fields:

- `image`: `repository`, `tag` (or `digest`) and `pullPolicy`. In gitops the
  tag is `__IMAGE_SHA__`, filled by gitops-sync.
- `env`: either a map (`NAME: value`, or `NAME: {valueFrom: ...}`) or a
  Kubernetes-style list. The map form is the readable one; the library emits
  it sorted, which matters for `$(VAR)` references (see
  [defaults](#k8s-app-defaults-applied-to-every-release)). `dependsOn`
  orders env entries that reference each other.
- `envFrom`: bulk-load a ConfigMap or Secret. Reference chart-managed ones by
  `identifier`, external ones by `name`.
- `probes`: `liveness`, `readiness`, `startup`, each with `enabled`,
  `type`/`path`/`port` for the generated form, or `custom: true` plus a raw
  `spec` when you want to write the probe yourself. Ports default to the
  primary Service port.
- `ports`: container ports; Services usually point at them by name.
- `resources`, `securityContext`, `lifecycle`: raw Kubernetes objects.
- `command`, `args`, `workingDir`, `stdin`, `tty`, `restartPolicy`
  (`Always` on an init container makes it a sidecar).

```yaml
controllers:
  main:
    containers:
      main:
        image: {repository: registry.digitalocean.com/ghost/myapp, tag: __IMAGE_SHA__}
        env:
          NODE_ENV: production
          DB_PASSWORD:
            valueFrom:
              secretKeyRef: {name: app-db-secrets, key: password}
        envFrom:
          - configMapRef: {identifier: config}
        probes:
          readiness:
            enabled: true
            custom: true
            spec:
              httpGet: {path: /readyz, port: 3000}
              periodSeconds: 15
        resources:
          requests: {cpu: 250m, memory: 256Mi}
          limits: {memory: 1Gi}
    initContainers:
      migrate:
        image: {repository: registry.digitalocean.com/ghost/myapp, tag: __IMAGE_SHA__}
        command: [./node_modules/.bin/knex, migrate:latest]
```

The table lists `containers`; `initContainers` accepts exactly the same keys.

<!-- values: controllers.<id>.containers -->
| Key | Type | Default | Description |
|---|---|---|---|
| `controllers.<id>.containers` | object |  | Containers as dictionary items. |
| `controllers.<id>.containers.<id>.args` | one of several shapes |  | Arguments for the container entrypoint. |
| `controllers.<id>.containers.<id>.command` | one of several shapes |  | Command for the container entrypoint. |
| `controllers.<id>.containers.<id>.dependsOn` | one of several shapes |  | Specify container dependencies to determine render order. |
| `controllers.<id>.containers.<id>.enabled` | boolean | `true` | Set to false to disable the container. |
| `controllers.<id>.containers.<id>.env` | one of several shapes |  | Environment variables for the container. Supports multiple syntax styles: simple map (key: value), list of K8s v1.EnvVar entries, and valueFrom references (configMapKeyRef, secretKeyRef, fieldRef, resourceFieldRef). Helm templates can be used in values. See the Environment Variables howto for detailed patterns and examples. |
| `controllers.<id>.containers.<id>.envFrom` | array |  | Secrets and/or ConfigMaps to load as environment variables in bulk. Each entry references either a ConfigMap (via `configMap` name or `configMapRef.identifier`) or a Secret (via `secret` name or `secretRef.identifier`), with optional `prefix`. See the Environment Variables howto for detailed patterns. |
| `controllers.<id>.containers.<id>.image` | object |  | Image configuration for the container. |
| `controllers.<id>.containers.<id>.image.digest` | string |  |  |
| `controllers.<id>.containers.<id>.image.pullPolicy` | string (Always, IfNotPresent, Never) |  |  |
| `controllers.<id>.containers.<id>.image.repository` | string |  |  |
| `controllers.<id>.containers.<id>.image.tag` | string / number |  |  |
| `controllers.<id>.containers.<id>.lifecycle` | object |  | Lifecycle event hooks (postStart, preStop) for the container. See https://kubernetes.io/docs/tasks/configure-pod-container/attach-handler-lifecycle-event/ and https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#lifecycle for details. |
| `controllers.<id>.containers.<id>.nameOverride` | string |  | Override the container name. |
| `controllers.<id>.containers.<id>.ports` | array |  | Ports to expose from the container. |
| `controllers.<id>.containers.<id>.probes` | object |  | Probe settings for the container. See https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/ for details. |
| `controllers.<id>.containers.<id>.probes.liveness` |  |  | Liveness probe configuration. |
| `controllers.<id>.containers.<id>.probes.liveness.custom` | boolean | `false` | Set to `true` to use the raw `spec` object as-is instead of deriving probe details from `type`/`path`/`port`. |
| `controllers.<id>.containers.<id>.probes.liveness.enabled` | boolean | `false` | Enable/disable this probe. |
| `controllers.<id>.containers.<id>.probes.liveness.path` | string |  | HTTP path for HTTP/HTTPS probes. |
| `controllers.<id>.containers.<id>.probes.liveness.port` | number / string |  | Port for the probe. Can be a port number or a named port. |
| `controllers.<id>.containers.<id>.probes.liveness.service` | string |  | Identifier of a container port or service to probe. When unset, the probe uses the container's primary port. |
| `controllers.<id>.containers.<id>.probes.liveness.spec` | object |  | Raw probe spec. When `custom: true`, this is used as-is. Otherwise merged with values derived from `type`/`path`/`port`. Typical fields include `initialDelaySeconds`, `periodSeconds`, `timeoutSeconds`, `failureThreshold`. |
| `controllers.<id>.containers.<id>.probes.liveness.type` | string (TCP, HTTP, HTTPS, GRPC, AUTO) |  | Probe type. Defaults to `TCP` for liveness, readiness and startup probes. `AUTO` attempts to infer the probe type from the container's ports. |
| `controllers.<id>.containers.<id>.probes.readiness` |  |  | Readiness probe configuration. |
| `controllers.<id>.containers.<id>.probes.readiness.custom` | boolean | `false` | Set to `true` to use the raw `spec` object as-is instead of deriving probe details from `type`/`path`/`port`. |
| `controllers.<id>.containers.<id>.probes.readiness.enabled` | boolean | `false` | Enable/disable this probe. |
| `controllers.<id>.containers.<id>.probes.readiness.path` | string |  | HTTP path for HTTP/HTTPS probes. |
| `controllers.<id>.containers.<id>.probes.readiness.port` | number / string |  | Port for the probe. Can be a port number or a named port. |
| `controllers.<id>.containers.<id>.probes.readiness.service` | string |  | Identifier of a container port or service to probe. When unset, the probe uses the container's primary port. |
| `controllers.<id>.containers.<id>.probes.readiness.spec` | object |  | Raw probe spec. When `custom: true`, this is used as-is. Otherwise merged with values derived from `type`/`path`/`port`. Typical fields include `initialDelaySeconds`, `periodSeconds`, `timeoutSeconds`, `failureThreshold`. |
| `controllers.<id>.containers.<id>.probes.readiness.type` | string (TCP, HTTP, HTTPS, GRPC, AUTO) |  | Probe type. Defaults to `TCP` for liveness, readiness and startup probes. `AUTO` attempts to infer the probe type from the container's ports. |
| `controllers.<id>.containers.<id>.probes.startup` |  |  | Startup probe configuration. |
| `controllers.<id>.containers.<id>.probes.startup.custom` | boolean | `false` | Set to `true` to use the raw `spec` object as-is instead of deriving probe details from `type`/`path`/`port`. |
| `controllers.<id>.containers.<id>.probes.startup.enabled` | boolean | `false` | Enable/disable this probe. |
| `controllers.<id>.containers.<id>.probes.startup.path` | string |  | HTTP path for HTTP/HTTPS probes. |
| `controllers.<id>.containers.<id>.probes.startup.port` | number / string |  | Port for the probe. Can be a port number or a named port. |
| `controllers.<id>.containers.<id>.probes.startup.service` | string |  | Identifier of a container port or service to probe. When unset, the probe uses the container's primary port. |
| `controllers.<id>.containers.<id>.probes.startup.spec` | object |  | Raw probe spec. When `custom: true`, this is used as-is. Otherwise merged with values derived from `type`/`path`/`port`. Typical fields include `initialDelaySeconds`, `periodSeconds`, `timeoutSeconds`, `failureThreshold`. |
| `controllers.<id>.containers.<id>.probes.startup.type` | string (TCP, HTTP, HTTPS, GRPC, AUTO) |  | Probe type. Defaults to `TCP` for liveness, readiness and startup probes. `AUTO` attempts to infer the probe type from the container's ports. |
| `controllers.<id>.containers.<id>.resizePolicy` | array |  | Configure whether the container should be restarted when resizing. This allows fine-grained control based on resource type (CPU or memory). |
| `controllers.<id>.containers.<id>.resources` | object |  | ResourceRequirements describes the compute resource requirements. |
| `controllers.<id>.containers.<id>.restartPolicy` | string |  | Restart policy for the container. |
| `controllers.<id>.containers.<id>.securityContext` | object |  | SecurityContext holds security configuration that will be applied to a container. Some fields are present in both SecurityContext and PodSecurityContext.  When both are set, the values in SecurityContext take precedence. |
| `controllers.<id>.containers.<id>.stdin` | boolean | `false` | Keep the standard input open on the container. |
| `controllers.<id>.containers.<id>.terminationMessagePath` | string |  | Path at which the file to which the container's termination message will be written is mounted into the container's filesystem. See https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#lifecycle for details. |
| `controllers.<id>.containers.<id>.terminationMessagePolicy` | string (File, FallbackToLogsOnError) |  | How the container's termination message should be populated. `File` will read the termination message from terminationMessagePath. `FallbackToLogsOnError` uses the last chunk of container log output if the termination message file is empty or the container errored. See https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#lifecycle for details. |
| `controllers.<id>.containers.<id>.tty` | boolean | `false` | Allocate a TTY for the container. |
| `controllers.<id>.containers.<id>.workingDir` | string |  | Working directory for the container. |
<!-- /values -->

## Services: `service`

A Service selects a controller's pods and exposes named ports. `ports.<name>`
needs at least `port`; `targetPort` defaults to the port, `protocol` to TCP.
When a controller has several Services, mark one `primary: true`; that is the
one probes and routes default to. `type` covers ClusterIP (default),
NodePort, LoadBalancer and ExternalName, with the usual traffic-policy knobs.

```yaml
service:
  main:
    controller: main
    ports:
      http:
        port: 3000
      metrics:
        port: 9090
```

<!-- values: service -->
| Key | Type | Default | Description |
|---|---|---|---|
| `service` | object |  | Kubernetes Service objects to be generated by the chart. Each key is a service identifier. |
| `service.<id>.allocateLoadBalancerNodePorts` | boolean |  |  |
| `service.<id>.annotations` | object / null |  | Annotations to set on the item. |
| `service.<id>.clusterIP` | string |  |  |
| `service.<id>.controller` | string |  | Controller this Service should target. |
| `service.<id>.enabled` | boolean | `true` | Set to false to disable the Service. |
| `service.<id>.externalIPs` | array |  |  |
| `service.<id>.externalName` | string |  |  |
| `service.<id>.externalTrafficPolicy` | string (Cluster, Local) |  | externalTrafficPolicy for the Service. Supported values: Cluster, Local. See https://kubernetes.io/docs/tutorials/services/source-ip/ |
| `service.<id>.extraSelectorLabels` |  |  | Additional match labels for the Service selector. |
| `service.<id>.forceRename` | string |  | Override the default resource name. Mutually exclusive with prefix and suffix. |
| `service.<id>.internalTrafficPolicy` | string (Cluster, Local) |  | internalTrafficPolicy for the Service. Supported values: Cluster, Local. See https://kubernetes.io/docs/concepts/services-networking/service-traffic-policy/ |
| `service.<id>.ipFamilies` | array |  | IP families for the Service. Supported values: IPv4, IPv6. |
| `service.<id>.ipFamilyPolicy` | string (SingleStack, PreferDualStack, RequireDualStack) |  | ipFamilyPolicy for the Service. Supported values: SingleStack, PreferDualStack, RequireDualStack. |
| `service.<id>.labels` | object / null |  | Labels to set on the item. |
| `service.<id>.loadBalancerClass` | string |  |  |
| `service.<id>.loadBalancerIP` | string |  |  |
| `service.<id>.loadBalancerSourceRanges` | array |  |  |
| `service.<id>.ports` | object |  | Service port(s) configuration. |
| `service.<id>.prefix` | string | `""` | Prefix to prepend to the resource name. Mutually exclusive with forceRename. |
| `service.<id>.primary` | boolean | `false` | Set to true to make this the primary Service for the controller (used in probes, notes, etc). Only one Service can be marked as primary. |
| `service.<id>.publishNotReadyAddresses` | boolean |  |  |
| `service.<id>.sessionAffinity` | string (None, ClientIP) |  |  |
| `service.<id>.sessionAffinityConfig` | object |  |  |
| `service.<id>.suffix` | string |  | Suffix to append to the resource name. Defaults to the resource identifier if there are multiple items, otherwise empty. Mutually exclusive with forceRename. |
| `service.<id>.trafficDistribution` | string (PreferClose, PreferSameZone, PreferSameNode) |  | trafficDistribution for the Service. Supported values: PreferClose, PreferSameZone, PreferSameNode. |
| `service.<id>.type` | string (ClusterIP, NodePort, LoadBalancer, ExternalName) |  | Service type. Supported values: ClusterIP, NodePort, LoadBalancer, ExternalName. |
<!-- /values -->

## Gateway API routes: `route`

An `HTTPRoute` (or GRPC/TCP/TLS/UDP route via `kind`) attached to a Gateway.
`rules` defaults to sending everything to the primary Service, and the chart
fills `parentRefs` from the route's `gateway` selector (see
[gateways](#k8s-app-gateways-gateway)), so a route usually needs only
`hostnames`. The convention is to declare routes only in the environments
that expose the app:

```yaml
# values.staging.yaml
route:
  main:
    hostnames: [myapp.ghostinfra.net]
    # gateway: shared-internal   (the default; see the gateways section)
```

A declared route is enabled by default; `enabled: false` switches one off
without deleting the block.

Explicit `parentRefs` remain the escape hatch and win over the selector
(missing `namespace`/`sectionName` are filled with the shared-Gateway
conventions `default`/`https`). Deploying the route into another namespace
(`namespaceOverride`) auto-generates the `ReferenceGrant` it needs.

<!-- values: route -->
| Key | Type | Default | Description |
|---|---|---|---|
| `route` | object |  | Kubernetes Gateway API *Route objects to be generated by the chart. Additional routes can be added by adding a dictionary key similar to the 'main' route. See https://gateway-api.sigs.k8s.io/references/spec/ for the Gateway API specification. |
| `route.<id>.annotations` | object / null |  | Annotations to set on the item. |
| `route.<id>.enabled` | boolean | `true` | Set to false to disable the Route. |
| `route.<id>.forceRename` | string |  | Override the default resource name. Mutually exclusive with prefix and suffix. |
| `route.<id>.gateway` | string (shared-internal, shared-external, dedicated-internal, dedicated-external) |  | Which gateway this route attaches to when parentRefs is not set: shared-internal (default), shared-external, dedicated-internal or dedicated-external. dedicated-* renders a per-app Gateway (its own DO load balancer) with certificate and HTTP->HTTPS redirect. |
| `route.<id>.hostnames` | array |  | Host addresses for the Route. Helm templates are supported. |
| `route.<id>.kind` | string (GRPCRoute, HTTPRoute, TCPRoute, TLSRoute, UDPRoute) |  | Route kind. Supported values: GRPCRoute, HTTPRoute, TCPRoute, TLSRoute, UDPRoute. |
| `route.<id>.labels` | object / null |  | Labels to set on the item. |
| `route.<id>.namespaceOverride` | string |  | Override the namespace the Route is deployed to. When set to a different namespace than the release namespace, a ReferenceGrant is automatically generated (unless disabled). |
| `route.<id>.parentRefs` | array |  | Resource the Route attaches to. |
| `route.<id>.prefix` | string | `""` | Prefix to prepend to the resource name. Mutually exclusive with forceRename. |
| `route.<id>.referenceGrant` | object | `{"enabled":true}` | ReferenceGrant auto-generation for cross-namespace backend references. When the Route is deployed to a different namespace than its backend Services, a ReferenceGrant is automatically generated in the Services' namespace (the release namespace). |
| `route.<id>.referenceGrant.enabled` | boolean | `true` | Set to false to disable automatic ReferenceGrant generation. |
| `route.<id>.rules` | array |  | Rules for routing. Defaults to the primary service. |
| `route.<id>.suffix` | string |  | Suffix to append to the resource name. Defaults to the resource identifier if there are multiple items, otherwise empty. Mutually exclusive with forceRename. |
<!-- /values -->

## Ingress: `ingress`

Classic Ingress for clusters without Gateway API. `hosts[].paths[]` point at
a Service by identifier (`service.identifier`) and port name; `tls` and
`className` as in Kubernetes. Prefer `route` on our clusters.

<!-- values: ingress -->
| Key | Type | Default | Description |
|---|---|---|---|
| `ingress` | object |  | Kubernetes Ingress objects to be generated by the chart. Each key is an ingress identifier. |
| `ingress.<id>.annotations` | object / null |  | Annotations to set on the item. |
| `ingress.<id>.className` | string |  | Set the ingressClass used for this Ingress. |
| `ingress.<id>.defaultBackend` | object |  | Set the defaultBackend for this Ingress. This disables any other rules. |
| `ingress.<id>.enabled` | boolean | `true` | Set to false to disable the Ingress. |
| `ingress.<id>.forceRename` | string |  | Override the default resource name. Mutually exclusive with prefix and suffix. |
| `ingress.<id>.hosts` | array |  | Configure the hosts for the Ingress. |
| `ingress.<id>.labels` | object / null |  | Labels to set on the item. |
| `ingress.<id>.prefix` | string | `""` | Prefix to prepend to the resource name. Mutually exclusive with forceRename. |
| `ingress.<id>.suffix` | string |  | Suffix to append to the resource name. Defaults to the resource identifier if there are multiple items, otherwise empty. Mutually exclusive with forceRename. |
| `ingress.<id>.tls` | array |  | Configure TLS for the Ingress. |
<!-- /values -->

## Storage and mounts: `persistence`

Each item is a volume; `type` selects the source and decides which other keys
apply:

| `type` | Source | Required keys |
|---|---|---|
| `persistentVolumeClaim` (default) | A PVC the chart creates, or `existingClaim` | `size`, `accessMode` (or `existingClaim`) |
| `emptyDir` | Scratch space, `medium: Memory` for tmpfs | |
| `configMap` | A ConfigMap, chart-managed via `identifier` or external via `name` | |
| `secret` | A Secret, same addressing; `items` projects single keys, `defaultMode` sets permissions | |
| `hostPath` | A path on the node | `hostPath` |
| `nfs` | An NFS export | `server`, `path` |
| `image` | An OCI artifact volume | `image` |
| `ephemeral` | A generic ephemeral volume | |
| `custom` | Anything, as a raw `volumeSpec` | `volumeSpec` |

Where it is mounted is a separate decision: `globalMounts` mounts the volume
into every container of every controller; `advancedMounts.<controller>.<container>`
mounts it only where named. Both take a list of `{path, subPath, readOnly}`.
A PVC that must survive `helm uninstall` sets `retain: true`.

```yaml
persistence:
  data:
    type: persistentVolumeClaim
    size: 10Gi
    accessMode: ReadWriteOnce
    globalMounts:
      - path: /data
  ssh-key:
    type: secret
    name: app-secrets
    defaultMode: 0440
    items:
      - key: myapp-git-sync-ssh
        path: ssh
    advancedMounts:
      main:
        git-sync:
          - path: /etc/git-secret
            readOnly: true
```

<!-- values: persistence -->
| Key | Type | Default | Description |
|---|---|---|---|
| `persistence` | object |  | Configure persistent storage and mount options. Each key is an identifier for a persistence item. Supported types: persistentVolumeClaim (default), configMap, secret, nfs, emptyDir, hostPath, image, custom. By default each item mounts to /<identifier>. Use globalMounts or advancedMounts to customize mount paths. |
| `persistence.<id>.accessMode` | string |  | AccessMode for the persistent volume. Make sure to select an access mode that is supported by your storage provider! See https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes |
| `persistence.<id>.advancedMounts` |  |  | Explicitly configure mounts for specific controllers and containers. Structure: advancedMounts.<controller_name>.<container_name>[].path Use this instead of globalMounts when different controllers need different mount configurations. |
| `persistence.<id>.advancedMounts.<id>.<id>.[].mountPropagation` | string |  |  |
| `persistence.<id>.advancedMounts.<id>.<id>.[].path` | string |  | The path where the volume should be mounted in the container. Helm templates are supported. If not specified, the mount path will be set to /<identifier_of_the_peristence_item>. |
| `persistence.<id>.advancedMounts.<id>.<id>.[].readOnly` | boolean |  |  |
| `persistence.<id>.advancedMounts.<id>.<id>.[].subPath` | string |  | The subPath within the volume to mount. Helm templates are supported. If not specified, the entire volume will be mounted. |
| `persistence.<id>.advancedMounts.<id>.<id>.[].subPathExpr` | string |  |  |
| `persistence.<id>.annotations` | object / null |  | Annotations to set on the item. |
| `persistence.<id>.dataSource` | object |  | The optional data source for the persistentVolumeClaim. See https://kubernetes.io/docs/concepts/storage/persistent-volumes/#volume-populators-and-data-sources |
| `persistence.<id>.dataSourceRef` | object |  | The optional volume populator for the persistentVolumeClaim. See https://kubernetes.io/docs/concepts/storage/persistent-volumes/#volume-populators-and-data-sources |
| `persistence.<id>.defaultMode` | integer |  |  |
| `persistence.<id>.enabled` | boolean | `true` | Set to false to disable the persistence item. |
| `persistence.<id>.existingClaim` | string |  | The name of an existing PersistentVolumeClaim to use. Helm templates are supported. This will not create a new PVC, but use the existing one instead. |
| `persistence.<id>.forceRename` | string |  | Override the default resource name. Mutually exclusive with prefix and suffix. |
| `persistence.<id>.globalMounts` | array |  | Mount the volume to all controllers and containers. Each entry specifies a mount point. |
| `persistence.<id>.globalMounts.[].mountPropagation` | string |  |  |
| `persistence.<id>.globalMounts.[].path` | string |  | The path where the volume should be mounted in the container. Helm templates are supported. If not specified, the mount path will be set to /<identifier_of_the_peristence_item>. |
| `persistence.<id>.globalMounts.[].readOnly` | boolean |  |  |
| `persistence.<id>.globalMounts.[].subPath` | string |  | The subPath within the volume to mount. Helm templates are supported. If not specified, the entire volume will be mounted. |
| `persistence.<id>.globalMounts.[].subPathExpr` | string |  |  |
| `persistence.<id>.hostPath` | string |  | Path on the host node to mount. |
| `persistence.<id>.hostPathType` | string |  | Type of the host path. Values: DirectoryOrCreate, Directory, FileOrCreate, File, Socket, CharDevice, BlockDevice. |
| `persistence.<id>.identifier` | string |  |  |
| `persistence.<id>.image` | one of several shapes |  | OCI artifact reference to be used. |
| `persistence.<id>.image.digest` | string |  |  |
| `persistence.<id>.image.repository` | string |  |  |
| `persistence.<id>.image.tag` | string / number |  |  |
| `persistence.<id>.items` | array |  |  |
| `persistence.<id>.labels` | object / null |  | Labels to set on the item. |
| `persistence.<id>.medium` | string |  | Storage medium. Set to 'Memory' for tmpfs (RAM-backed). Leave empty for node disk. |
| `persistence.<id>.name` | string |  |  |
| `persistence.<id>.path` | string |  | The NFS export path on the server. |
| `persistence.<id>.prefix` | string | `""` | Prefix to prepend to the resource name. Mutually exclusive with forceRename. |
| `persistence.<id>.pullPolicy` | string (Always, Never, IfNotPresent) |  | The image pull policy for the image persistence item. |
| `persistence.<id>.retain` | boolean |  | Set to true to retain the PVC upon helm uninstall. |
| `persistence.<id>.server` | string |  | The NFS server hostname or IP address. |
| `persistence.<id>.size` | string |  | The amount of storage that is requested for the persistent volume. |
| `persistence.<id>.sizeLimit` | string |  | Maximum size of the volume (e.g. '1Gi'). Only enforced for tmpfs. |
| `persistence.<id>.storageClass` | string |  | Storage Class for the config volume. If set to '-', dynamic provisioning is disabled. If set to something else, the given storageClass is used. If undefined (the default) or set to null, no storageClassName spec is set, choosing the default provisioner. |
| `persistence.<id>.suffix` | string |  | Suffix to append to the resource name. Defaults to the resource identifier if there are multiple items, otherwise empty. Mutually exclusive with forceRename. |
| `persistence.<id>.type` |  |  |  |
| `persistence.<id>.volumeName` | string |  |  |
| `persistence.<id>.volumeSpec` | object |  | Raw Kubernetes volume specification. Passed through directly to the pod spec volumes list. |
<!-- /values -->

## ConfigMaps: `configMaps` and `configMapsFromFolder`

`configMaps.<id>.data` renders a ConfigMap; values support Helm templates.
Containers reference it by identifier in `envFrom` or mount it with a
`persistence` item of `type: configMap`. Every chart-managed ConfigMap is
hashed into the pod template annotation (`includeInChecksum`), so changing
its data rolls the pods. `configMapsFromFolder` builds ConfigMaps from files
under `basePath` in the chart directory, one ConfigMap per subfolder; it is
of limited use with the umbrella-chart layout because the files would have to
ship inside k8s-app itself.

```yaml
configMaps:
  config:
    data:
      NODE_ENV: production
      db__client: mysql2
```

<!-- values: configMaps,configMapsFromFolder -->
| Key | Type | Default | Description |
|---|---|---|---|
| `configMaps` | object |  | Kubernetes ConfigMaps to be generated by the chart. Additional ConfigMaps can be added by adding a dictionary key similar to the 'config' object. |
| `configMaps.<id>.annotations` | object / null |  | Annotations to set on the item. |
| `configMaps.<id>.binaryData` | object |  | ConfigMap binaryData content. |
| `configMaps.<id>.data` | object |  | ConfigMap data content. Helm templates are supported. |
| `configMaps.<id>.enabled` | boolean | `true` | Set to false to disable the ConfigMap. |
| `configMaps.<id>.forceRename` | string |  | Override the default resource name. Mutually exclusive with prefix and suffix. |
| `configMaps.<id>.includeChecksumInControllers` | array |  | Specify a list of controller identifiers for which to include this ConfigMap in the checksum calculation for rolling updates. |
| `configMaps.<id>.includeInChecksum` | boolean | `true` | Set to true to include this ConfigMap in the checksum calculation for rolling updates. |
| `configMaps.<id>.labels` | object / null |  | Labels to set on the item. |
| `configMaps.<id>.prefix` | string | `""` | Prefix to prepend to the resource name. Mutually exclusive with forceRename. |
| `configMaps.<id>.suffix` | string |  | Suffix to append to the resource name. Defaults to the resource identifier if there are multiple items, otherwise empty. Mutually exclusive with forceRename. |
| `configMapsFromFolder` | object |  | Generate ConfigMaps from files in the chart filesystem |
| `configMapsFromFolder.autoDetectBinary` | boolean | `false` |  |
| `configMapsFromFolder.basePath` | string |  | Base path containing configmap subfolders |
| `configMapsFromFolder.configMapsOverrides` | object |  |  |
| `configMapsFromFolder.configMapsOverrides.<id>.annotations` | object / null |  | Annotations to set on the item. |
| `configMapsFromFolder.configMapsOverrides.<id>.fileAttributeOverrides` | object |  |  |
| `configMapsFromFolder.configMapsOverrides.<id>.forceRename` | string / null |  |  |
| `configMapsFromFolder.configMapsOverrides.<id>.labels` | object / null |  | Labels to set on the item. |
| `configMapsFromFolder.enabled` | boolean | `false` |  |
<!-- /values -->

## Secrets: `secrets` and `secretsFromFolder`

Same shape as ConfigMaps with `stringData` and `type`. The values are stored
in plain text in git, so on our clusters application secrets come from
Secret Manager through [`secretsInjection`](#k8s-app-secret-injection-secretsinjection)
instead; use `secrets` only for non-sensitive material that needs to be a
Secret for API reasons.

<!-- values: secrets,secretsFromFolder -->
| Key | Type | Default | Description |
|---|---|---|---|
| `secrets` | object |  | Kubernetes Secrets to be generated by the chart. Be aware that these values are not encrypted by default, and could therefore be visible to anybody with access to the values.yaml file. Additional Secrets can be added by adding a dictionary key similar to the 'secret' object. |
| `secrets.<id>.annotations` | object / null |  | Annotations to set on the item. |
| `secrets.<id>.enabled` | boolean | `true` | Set to false to disable the Secret. |
| `secrets.<id>.forceRename` | string |  | Override the default resource name. Mutually exclusive with prefix and suffix. |
| `secrets.<id>.includeChecksumInControllers` | array |  | Specify a list of controller identifiers for which to include this Secret in the checksum calculation for rolling updates. |
| `secrets.<id>.includeInChecksum` | boolean | `true` | Set to true to include this Secret in the checksum calculation for rolling updates. |
| `secrets.<id>.labels` | object / null |  | Labels to set on the item. |
| `secrets.<id>.prefix` | string | `""` | Prefix to prepend to the resource name. Mutually exclusive with forceRename. |
| `secrets.<id>.stringData` | object |  | Secret stringData content. Helm templates are supported. |
| `secrets.<id>.suffix` | string |  | Suffix to append to the resource name. Defaults to the resource identifier if there are multiple items, otherwise empty. Mutually exclusive with forceRename. |
| `secrets.<id>.type` | string |  | Secret type. |
| `secretsFromFolder` | object |  | Generate Secrets from files in the chart filesystem |
| `secretsFromFolder.basePath` | string |  | Base path containing secret subfolders |
| `secretsFromFolder.enabled` | boolean | `false` |  |
| `secretsFromFolder.overrides` | object |  |  |
| `secretsFromFolder.overrides.<id>.annotations` | object / null |  | Annotations to set on the item. |
| `secretsFromFolder.overrides.<id>.fileAttributeOverrides` | object |  |  |
| `secretsFromFolder.overrides.<id>.forceRename` | string / null |  |  |
| `secretsFromFolder.overrides.<id>.labels` | object / null |  | Labels to set on the item. |
<!-- /values -->

## Service accounts and RBAC: `serviceAccount`, `rbac`

Without any configuration each release gets a ServiceAccount named after the
release and every pod uses it. Define entries under `serviceAccount` to
create your own (and point controllers at them with
`controllers.<id>.serviceAccount.identifier`), or reference an existing one
by `name`. `rbac.roles` and `rbac.bindings` create (Cluster)Roles and
(Cluster)RoleBindings; a binding's `subjects` can reference a chart-managed
ServiceAccount by identifier.

```yaml
serviceAccount:
  main: {}
rbac:
  roles:
    leases:
      type: Role
      rules:
        - apiGroups: [coordination.k8s.io]
          resources: [leases]
          verbs: [get, create, update]
  bindings:
    leases:
      type: RoleBinding
      roleRef: {identifier: leases}
      subjects:
        - identifier: main
```

<!-- values: serviceAccount,rbac -->
| Key | Type | Default | Description |
|---|---|---|---|
| `rbac` | object |  | Configure the Roles and Role Bindings for the chart here |
| `rbac.bindings` | object |  | (Cluster)RoleBinding objects to be generated by the chart |
| `rbac.bindings.<id>.annotations` | object / null |  | Annotations to set on the item. |
| `rbac.bindings.<id>.enabled` | boolean | `true` | Set to false to disable the RoleBinding or ClusterRoleBinding. |
| `rbac.bindings.<id>.forceRename` | string |  | Override the default resource name. Mutually exclusive with prefix and suffix. |
| `rbac.bindings.<id>.labels` | object / null |  | Labels to set on the item. |
| `rbac.bindings.<id>.prefix` | string | `""` | Prefix to prepend to the resource name. Mutually exclusive with forceRename. |
| `rbac.bindings.<id>.roleRef` | object |  | Reference the Role or ClusterRole to bind to. |
| `rbac.bindings.<id>.subjects` | array |  | Set the subjects for the RoleBinding or ClusterRoleBinding. |
| `rbac.bindings.<id>.suffix` | string |  | Suffix to append to the resource name. Defaults to the resource identifier if there are multiple items, otherwise empty. Mutually exclusive with forceRename. |
| `rbac.bindings.<id>.type` | string (RoleBinding, ClusterRoleBinding) | `"RoleBinding"` | Set the type of RBAC binding. Supported values: RoleBinding, ClusterRoleBinding. |
| `rbac.roles` | object |  | (Cluster)Role objects to be generated by the chart |
| `rbac.roles.<id>.annotations` | object / null |  | Annotations to set on the item. |
| `rbac.roles.<id>.enabled` | boolean | `true` | Set to false to disable the Role or ClusterRole. |
| `rbac.roles.<id>.forceRename` | string |  | Override the default resource name. Mutually exclusive with prefix and suffix. |
| `rbac.roles.<id>.labels` | object / null |  | Labels to set on the item. |
| `rbac.roles.<id>.prefix` | string | `""` | Prefix to prepend to the resource name. Mutually exclusive with forceRename. |
| `rbac.roles.<id>.rules` | array |  | Set the rules for the Role or ClusterRole. |
| `rbac.roles.<id>.suffix` | string |  | Suffix to append to the resource name. Defaults to the resource identifier if there are multiple items, otherwise empty. Mutually exclusive with forceRename. |
| `rbac.roles.<id>.type` | string (Role, ClusterRole) | `"Role"` | Set the type of RBAC resource. Supported values: Role, ClusterRole. |
| `serviceAccount` | object |  | Kubernetes serviceAccount objects to be generated by the chart |
| `serviceAccount.<id>.annotations` | object / null |  | Annotations to set on the item. |
| `serviceAccount.<id>.automountServiceAccountToken` | boolean |  | Set to false to prevent the ServiceAccount token from being automatically mounted. |
| `serviceAccount.<id>.enabled` | boolean | `true` | Set to false to disable the ServiceAccount. |
| `serviceAccount.<id>.forceRename` | string |  | Override the default resource name. Mutually exclusive with prefix and suffix. |
| `serviceAccount.<id>.labels` | object / null |  | Labels to set on the item. |
| `serviceAccount.<id>.prefix` | string | `""` | Prefix to prepend to the resource name. Mutually exclusive with forceRename. |
| `serviceAccount.<id>.staticToken` | boolean | `false` | Set to true to create a long-lived static token for the ServiceAccount. |
| `serviceAccount.<id>.suffix` | string |  | Suffix to append to the resource name. Defaults to the resource identifier if there are multiple items, otherwise empty. Mutually exclusive with forceRename. |
<!-- /values -->

## Network policies: `networkpolicies`

A NetworkPolicy targeting a controller's pods (`controller`) or an explicit
`podSelector`, with `policyTypes` and `rules.ingress` / `rules.egress` in
Kubernetes form. An entry of `{}` in a rule list allows all traffic in that
direction.

<!-- values: networkpolicies -->
| Key | Type | Default | Description |
|---|---|---|---|
| `networkpolicies` | object |  | networkPolicy objects to be generated by the chart. Additional networkPolicies can be added by adding a dictionary key similar to the 'main' networkPolicy. |
| `networkpolicies.<id>.annotations` | object / null |  | Annotations to set on the item. |
| `networkpolicies.<id>.controller` | string |  | Controller this NetworkPolicy should target. |
| `networkpolicies.<id>.enabled` | boolean | `true` | Set to false to disable the NetworkPolicy. |
| `networkpolicies.<id>.extraSelectorLabels` | object |  | Additional match labels to add to the pod selector. These are merged with labels derived from the controller identifier. |
| `networkpolicies.<id>.forceRename` | string |  | Override the default resource name. Mutually exclusive with prefix and suffix. |
| `networkpolicies.<id>.labels` | object / null |  | Labels to set on the item. |
| `networkpolicies.<id>.podSelector` |  |  | Custom podSelector for the NetworkPolicy. Takes precedence over targeting a controller via the controller identifier. |
| `networkpolicies.<id>.policyTypes` | array |  | Policy types for the NetworkPolicy. |
| `networkpolicies.<id>.prefix` | string | `""` | Prefix to prepend to the resource name. Mutually exclusive with forceRename. |
| `networkpolicies.<id>.rules` | object |  | Ingress and egress rules for the NetworkPolicy. See https://kubernetes.io/docs/concepts/services-networking/network-policies/#networkpolicy-resource for details. Use `- {}` as an item to allow all traffic for that direction. |
| `networkpolicies.<id>.suffix` | string |  | Suffix to append to the resource name. Defaults to the resource identifier if there are multiple items, otherwise empty. Mutually exclusive with forceRename. |
<!-- /values -->

## Prometheus monitors: `serviceMonitor`, `podMonitor`

Prometheus Operator objects. A `serviceMonitor` scrapes a chart-managed
Service by identifier (`service.identifier`) on the named `endpoints`; a
`podMonitor` scrapes a controller's pods directly.

```yaml
serviceMonitor:
  main:
    service:
      identifier: main
    endpoints:
      - port: metrics
        interval: 30s
```

<!-- values: serviceMonitor,podMonitor -->
| Key | Type | Default | Description |
|---|---|---|---|
| `podMonitor` | object |  | podMonitor objects to be generated by the chart. Additional PodMonitors can be added by adding a dictionary key similar to the 'main' PodMonitor. |
| `podMonitor.<id>.annotations` | object / null |  | Annotations to set on the item. |
| `podMonitor.<id>.controller` | object |  | Controller whose pods to monitor. |
| `podMonitor.<id>.controller.identifier` | string |  | Reference a controller identifier defined within the chart values. |
| `podMonitor.<id>.enabled` | boolean | `true` | Set to false to disable the PodMonitor. |
| `podMonitor.<id>.forceRename` | string |  | Override the default resource name. Mutually exclusive with prefix and suffix. |
| `podMonitor.<id>.jobLabel` | string | `"app.kubernetes.io/name"` | The label to use to retrieve the job name from the target pod's metadata. Defaults to 'app.kubernetes.io/name'. Helm templates can be used. |
| `podMonitor.<id>.labels` | object / null |  | Labels to set on the item. |
| `podMonitor.<id>.podMetricsEndpoints` | array |  | Pod metrics endpoints allowed as part of this PodMonitor. Typical fields per endpoint include `port`, `scheme`, `path`, `interval`, `scrapeTimeout`. See https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api-reference/api.md#podmetricsendpoint for the full schema. |
| `podMonitor.<id>.podTargetLabels` | array |  | Transfers labels from the Kubernetes Pod onto the created metrics. See https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api-reference/api.md#podmonitorspec for details. |
| `podMonitor.<id>.prefix` | string | `""` | Prefix to prepend to the resource name. Mutually exclusive with forceRename. |
| `podMonitor.<id>.selector` | object |  | Selector to select Pod objects. |
| `podMonitor.<id>.suffix` | string |  | Suffix to append to the resource name. Defaults to the resource identifier if there are multiple items, otherwise empty. Mutually exclusive with forceRename. |
| `serviceMonitor` | object |  | serviceMonitor objects to be generated by the chart. Additional ServiceMonitors can be added by adding a dictionary key similar to the 'main' ServiceMonitor. |
| `serviceMonitor.<id>.annotations` | object / null |  | Annotations to set on the item. |
| `serviceMonitor.<id>.enabled` | boolean | `true` | Set to false to disable the ServiceMonitor. |
| `serviceMonitor.<id>.endpoints` | array |  | Endpoints allowed as part of this ServiceMonitor. |
| `serviceMonitor.<id>.forceRename` | string |  | Override the default resource name. Mutually exclusive with prefix and suffix. |
| `serviceMonitor.<id>.jobLabel` | string | `"app.kubernetes.io/name"` | The label to use to retrieve the job name from the target service's metadata. Defaults to 'app.kubernetes.io/name'. Helm templates can be used. |
| `serviceMonitor.<id>.labels` | object / null |  | Labels to set on the item. |
| `serviceMonitor.<id>.prefix` | string | `""` | Prefix to prepend to the resource name. Mutually exclusive with forceRename. |
| `serviceMonitor.<id>.selector` | object |  | Selector to select Endpoints objects. |
| `serviceMonitor.<id>.service` | one of several shapes |  | Service to monitor. Either 'serviceName' or 'service' must be specified. |
| `serviceMonitor.<id>.service.identifier` | string |  |  |
| `serviceMonitor.<id>.service.name` | string |  |  |
| `serviceMonitor.<id>.serviceName` | string |  | Reference to a Service name to monitor. Helm templates are supported. Deprecated in favor of 'service'. |
| `serviceMonitor.<id>.suffix` | string |  | Suffix to append to the resource name. Defaults to the resource identifier if there are multiple items, otherwise empty. Mutually exclusive with forceRename. |
| `serviceMonitor.<id>.targetLabels` | array |  | Transfers labels from the Kubernetes Service onto the created metrics. See https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api-reference/api.md#servicemonitorspec for details. |
<!-- /values -->

## Anything else: `rawResources`

For a resource the chart has no template for (an `ExternalSecret` with a
custom shape, a CNPG cluster, a Gateway). `manifest` is rendered as-is under
the chart's naming and labelling rules; `apiVersion` and `kind` are required.

```yaml
rawResources:
  cache:
    manifest:
      apiVersion: v1
      kind: ConfigMap
      data:
        key: value
```

<!-- values: rawResources -->
| Key | Type | Default | Description |
|---|---|---|---|
| `rawResources` | object |  | Allows for the inclusion of raw Kubernetes resources that are not supported by the chart otherwise​ |
| `rawResources.<id>.enabled` | boolean | `true` | Set to false to disable the resource. |
| `rawResources.<id>.forceRename` | string |  | Override the default resource name. Mutually exclusive with prefix and suffix. |
| `rawResources.<id>.manifest` | object |  | The raw K8s resource manifest to be rendered. apiVersion and kind are required. |
| `rawResources.<id>.prefix` | string | `""` | Prefix to prepend to the resource name. Mutually exclusive with forceRename. |
| `rawResources.<id>.suffix` | string |  | Suffix to append to the resource name. Defaults to the resource identifier if there are multiple items, otherwise empty. Mutually exclusive with forceRename. |
<!-- /values -->

## k8s-app: preview facts `preview`

Facts about a PR preview that the platform knows and apps must not repeat.
The pull-request ApplicationSet passes `preview.prNumber` as a Helm parameter
(`k8s-app.preview.prNumber={{.number}}` on the umbrella chart); it drives the
injected `GITHUB_PR_NUMBER` env var, the `pull-request` pod label,
`hotReload`'s git ref and `previewDatabase`'s database name. `preview.gitRepo`
is derived from `preview.owner` and the release namespace (app name ==
namespace == repository name by convention) and only needs setting when the
repository name differs from the slug (`Daisy.js` vs `daisy-js`). Outside
previews the group is empty and nothing preview-specific renders.

<!-- values: preview -->
| Key | Type | Default | Description |
|---|---|---|---|
| `preview` | object |  | Per-render preview facts. Set by the pull-request ApplicationSet as Helm parameters; apps never write them. Empty outside previews. |
| `preview.gitRepo` | string | `""` | SSH clone URL for hotReload. Empty = git@github.com:<owner>/<release namespace>.git. |
| `preview.owner` | string | `"TryGhost"` | GitHub owner used when deriving gitRepo. |
| `preview.prNumber` | string / integer | `""` | Pull request number (render-time literal). |
<!-- /values -->

## k8s-app: secret injection `secretsInjection`

Renders the `app-secrets` ExternalSecret (every Secret Manager secret
labelled `namespace=<release namespace>`, one key per secret, named verbatim)
and, with `database: true`, the `app-db-secrets` ExternalSecret (Terraform's
`<env>-<app>db` JSON secret exploded into `host`, `public_host`, `port`,
`user`, `password`, `database`, `uri`, `public_uri`, `ssl_ca`). Both sync
every `refreshInterval` from the named ClusterSecretStore, carry ArgoCD
sync-wave `-10` so the Secrets exist before anything reads them, and are marked
`Prune=false,Delete=false` because they are namespace-shared: previews can
bootstrap them, later releases co-manage them, and nothing in a preview's
lifecycle removes them.

`app-secrets` is created, not injected: map its keys explicitly with `env`,
`envFrom` or a `persistence` item, exactly as for any other Secret.

```yaml
secretsInjection:
  enabled: true
  database: true
controllers:
  main:
    containers:
      main:
        env:
          some_api__key:
            valueFrom:
              secretKeyRef: {name: app-secrets, key: some-api-key}
```

`app-db-secrets` is the exception. The apps read their configuration with
nconf, whose env provider maps `a__b__c` to `a.b.c`, so the MySQL connection
is the same handful of variables in every app — written out once in the
values and again in the migration initContainer. `database: true` fills them
in instead, in every container and initContainer of every controller:

| Env var | Value |
|---|---|
| `db__client` | `mysql2` |
| `db__connection__charset` | `utf8mb4` |
| `db__connection__database` | the release namespace (namespace == app name) |
| `db__connection__host` | `app-db-secrets` key `host` (the VPC hostname) |
| `db__connection__port` | `app-db-secrets` key `port` |
| `db__connection__user` | `app-db-secrets` key `user` |
| `db__connection__password` | `app-db-secrets` key `password` |
| `db__connection__ssl__ca` | `app-db-secrets` key `ssl_ca` |

There is nothing to configure: an app that wants something else declares that
env itself and wins, which is how a preview points at its per-PR database.

```yaml
controllers:
  main:
    containers:
      main:
        env:
          db__connection__database: $(APP_NAME)_preview_$(GITHUB_PR_NUMBER)
```

The fill happens before `hotReload`, so the credentials reach the app's own
containers and never the git-sync sidecars.

Assumes External Secrets Operator and the ClusterSecretStore exist in the
cluster. Example: [`examples/k8s-app/values.base.yaml`](../../examples/k8s-app/values.base.yaml);
the rendered ExternalSecrets are in [`tests/snapshots/staging.yaml`](tests/snapshots/staging.yaml).

<!-- values: secretsInjection -->
| Key | Type | Default | Description |
|---|---|---|---|
| `secretsInjection` | object |  | External Secrets injection (app-secrets / app-db-secrets ExternalSecrets). Requires External Secrets Operator and the referenced store to exist. |
| `secretsInjection.database` | boolean | `false` | Also create the app-db-secrets ExternalSecret and inject the nconf connection env that reads it (db__client, db__connection__charset/database/host/port/user/password/ssl__ca) into every container and initContainer. App-declared env wins. Only when enabled is true. |
| `secretsInjection.enabled` | boolean | `false` | Master switch: create the app-secrets ExternalSecret. |
| `secretsInjection.refreshInterval` | string | `"5m"` | ESO refresh interval for both ExternalSecrets. |
| `secretsInjection.store` | object |  | The (Cluster)SecretStore both ExternalSecrets read from. |
| `secretsInjection.store.kind` | string (ClusterSecretStore, SecretStore) | `"ClusterSecretStore"` | Kind of the store: ClusterSecretStore or SecretStore. |
| `secretsInjection.store.name` | string | `"gcp-secrets-manager"` | Name of the (Cluster)SecretStore to read from. |
<!-- /values -->

## k8s-app: migrations `migrations`

One Job, `<release>-migrations`, that runs `command` in the app's own image
before the workloads start. Its container is the container named by
`controller`/`container` (`main`/`main`) with `command` replaced: the same
image, `envFrom` and `env`, including the database variables the chart
injects and any override the environment adds, so migrations and the app
always read the same configuration. Probes, args and lifecycle are not
copied — they belong to the long-running container.

```yaml
migrations:
  enabled: true
  command: [./node_modules/.bin/knex, migrate:latest]
```

Ordering is by ArgoCD sync wave, one sync, no hooks:

| Wave | Resource |
|---|---|
| -10 | `app-secrets` / `app-db-secrets` ExternalSecrets — the Secrets exist and report Ready |
| -2 | `previewDatabase` create Job — the per-PR database exists |
| -1 | this Job — the schema is current |
| 0 | Deployments, Services, routes, everything else |

The app's own workload keeps its name: the library would otherwise rename it
from `<release>` to `<release>-main` now that `controllers` holds two items,
so the chart pins it with `forceRename` (unless the app already sets
`forceRename`, `prefix` or `suffix`, or declares more than one controller).

The Job is annotated `Force=true,Replace=true` because Jobs are immutable: a
new image sha recreates and re-runs it, an unchanged one stays completed and
ArgoCD keeps seeing it in sync. A failing migration fails the sync and the
old pods keep running, because the new Deployment is a later wave.

In a hot-reload preview the Job still runs the image's code, not the code
git-sync delivers — a preview whose migrations changed needs an image build.

<!-- values: migrations -->
| Key | Type | Default | Description |
|---|---|---|---|
| `migrations` | object |  | Database migrations Job: runs `command` in the app's own container (image, envFrom and env, including the injected database vars) at ArgoCD sync-wave -1, after the preview database (-2) and before the workloads (0). |
| `migrations.backoffLimit` | integer | `2` | Job retries before the sync fails. |
| `migrations.command` | array | `[]` | Command that runs the migrations, e.g. [./node_modules/.bin/knex, migrate:latest]. Required when enabled. |
| `migrations.container` | string | `"main"` | Container in that controller to copy image, envFrom and env from. |
| `migrations.controller` | string | `"main"` | Controller (under controllers) whose container the Job copies. |
| `migrations.enabled` | boolean | `false` | Render the migrations Job. |
<!-- /values -->

## k8s-app: hot reload `hotReload`

For PR previews: the image supplies the dependencies, git-sync supplies the
PR's latest code, and the app container runs a file-watching dev runner
instead of its normal command. Enabling it deep-merges these into your
values and touches nothing else (your env, envFrom and volumes stay as
declared):

- `initContainers.git-sync-init`: one-time clone of `preview.gitRepo` at
  `refs/pull/<preview.prNumber>/head` (`hotReload.repo` / `hotReload.ref`
  override).
- `containers.git-sync`: sidecar polling every `gitSync.period` (2s),
  publishing `/workspace/git/app` atomically and keeping stale worktrees for
  `gitSync.staleWorktreeTimeout` so the watcher can stop the old process.
- `containers.<hotReload.container>`: `command`/`args` replaced by
  `/sbin/tini -g -- sh -ec` running `ln -sfn <app.nodeModules> <workspace>/node_modules`
  then `exec <app.devCommand> --legacy-watch --watch <checkout> --exec 'sh -c "cd <checkout> && exec <app.run>"'`.
  The defaults suit a Node app whose image has `pnpm dev` (nodemon) with
  dependencies under `/app/node_modules`; set `app.args` to take over the
  script entirely.
- `configMaps.git-sync-hosts`: GitHub's published Ed25519 host key
  (`ssh.knownHosts`), mounted at `/etc/git-hosts/known_hosts` with host-key
  verification on. Pinned on purpose: pods boot with no call to GitHub's API,
  whose anonymous limit of 60 requests per hour is shared by every pod behind
  the cluster NAT.
- `persistence.workspace` (emptyDir), `persistence.git-sync-ssh` (only the
  `<namespace>-git-sync-ssh` key of `app-secrets`, mode `0440`, mounted only
  into the two git-sync containers) and `persistence.git-sync-hosts`.
- `defaultPodOptions.securityContext.fsGroup: 65533` so git-sync can read
  the key.

The deploy key is written to Secret Manager by the Terraform `argocd` module
and reaches `app-secrets` through `secretsInjection`, so hot reload needs
`secretsInjection.enabled: true` (or an equivalent Secret named in
`ssh.secretName`). A preview values file needs only:

```yaml
hotReload:
  enabled: true
```

Example: [`examples/k8s-app/values.preview.yaml`](../../examples/k8s-app/values.preview.yaml).

<!-- values: hotReload -->
| Key | Type | Default | Description |
|---|---|---|---|
| `hotReload` | object |  | git-sync based hot reload for PR previews. |
| `hotReload.app` | object |  | How the app container runs while hot reloading. |
| `hotReload.app.args` | array | `[]` | Args for the app container. Empty = generated script: ln -sfn <nodeModules> <workspace>/node_modules exec <devCommand> --legacy-watch --watch <checkout> --exec 'sh -c "cd <checkout> && exec <run>"' Set a non-empty list to take full control (command is used verbatim). |
| `hotReload.app.command` | array |  | Entrypoint for the app container while hot reloading. The default runs the generated args script under tini. |
| `hotReload.app.devCommand` | string | `"pnpm dev"` | Dev runner in the image (e.g. `pnpm dev` running nodemon). |
| `hotReload.app.nodeModules` | string | `"/app/node_modules"` | Dependencies directory baked into the image, symlinked into the workspace. |
| `hotReload.app.run` | string | `"node src/main.js"` | Command the runner (re)starts inside the synced checkout. |
| `hotReload.container` | string | `"main"` | Container in that controller whose command/args are replaced. |
| `hotReload.controller` | string | `"main"` | Controller (under `controllers`) to add git-sync to. |
| `hotReload.enabled` | boolean | `false` | Enable hot reload for this release (PR previews). |
| `hotReload.gitSync` | object |  | git-sync sidecar / init container settings. |
| `hotReload.gitSync.depth` | integer | `1` | Clone depth (git-sync --depth). |
| `hotReload.gitSync.extraArgs` | array | `[]` | Extra args appended to both git-sync containers. |
| `hotReload.gitSync.gid` | integer | `65533` | gid git-sync runs as; also the pod fsGroup so the mounted SSH key is readable. |
| `hotReload.gitSync.image` | object |  | git-sync image (repository + tag). |
| `hotReload.gitSync.image.repository` | string | `"registry.k8s.io/git-sync/git-sync"` |  |
| `hotReload.gitSync.image.tag` | string | `"v4.4.2"` |  |
| `hotReload.gitSync.link` | string | `"app"` | Symlink name under root that git-sync publishes atomically (--link). |
| `hotReload.gitSync.period` | string | `"2s"` | Polling interval for the sidecar. |
| `hotReload.gitSync.resources` | object |  | Resources for both git-sync containers. |
| `hotReload.gitSync.root` | string | `"/workspace/git"` | git-sync --root; the checkout is published at <root>/<link>. |
| `hotReload.gitSync.staleWorktreeTimeout` | string | `"5m"` | How long old worktrees are kept so the watcher can stop the old process. |
| `hotReload.gitSync.uid` | integer | `65533` | git-sync runs as this uid/gid; the pod's fsGroup is set to gid so the mounted SSH key is readable. |
| `hotReload.ref` | string | `""` | Git ref to follow (git-sync's GITSYNC_REF). Empty = derived at render time as refs/pull/<preview.prNumber>/head. Set explicitly (e.g. a branch) to override. |
| `hotReload.repo` | string | `""` | Git repository to sync (SSH form, git-sync's GITSYNC_REPO), e.g. git@github.com:TryGhost/Daisy.js.git. Empty = preview.gitRepo, itself defaulting to git@github.com:<preview.owner>/<release namespace>.git. |
| `hotReload.ssh` | object |  | SSH deploy key and host key settings. |
| `hotReload.ssh.key` | string | `""` | Key inside that Secret. Defaults to "<namespace>-git-sync-ssh" (namespace == app name by convention), matching the Terraform argocd module: per-PR preview releases are named <app>-<pr>, but the deploy key is provisioned per app, not per release. |
| `hotReload.ssh.knownHosts` | string | `"github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl\n"` | Pinned SSH host key(s) for the git host, rendered into a ConfigMap mounted at /etc/git-hosts/known_hosts (host-key verification on). No runtime lookups: pods boot without network calls to GitHub's API. https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints |
| `hotReload.ssh.secretName` | string | `"app-secrets"` | Secret holding the read-only deploy key (by convention the app-secrets Secret created by secretsInjection). |
| `hotReload.workspace` | string | `"/workspace"` | emptyDir mount path shared by git-sync and the app container. |
<!-- /values -->

## k8s-app: preview database `previewDatabase`

Gives each PR preview its own MySQL database on the app's managed cluster.
Two Jobs named `<release>-create-preview-db` and `<release>-drop-preview-db`
run `mysql:8.4` with `DB_HOST`/`DB_PORT`/`DB_USER`/`DB_PASS` from the
`app-db-secrets` Secret (so it pairs with `secretsInjection.database: true`),
`APP_NAME` (the namespace) and `GITHUB_PR_NUMBER` (`preview.prNumber`). The
database is `<namespace>_preview_<pr>`; a shell guard refuses a non-numeric
PR number.

- **create**: ArgoCD sync-wave -2 with `Force=true,Replace=true`, deliberately
  not a PreSync hook. It needs the `app-db-secrets` Secret, which the
  wave -10 ExternalSecret only materialises during the sync, so a PreSync hook
  would deadlock on a fresh namespace. Wave -2 puts it after the Secrets and
  before the migrations Job (-1) and the workloads (0).
  `CREATE DATABASE IF NOT EXISTS ...
  CHARACTER SET utf8mb4` is idempotent. It runs once per PR: the completed
  Job has no TTL, stays in the namespace, and ArgoCD keeps seeing it in sync.
- **drop**: `PostDelete` hook with `HookSucceeded` delete policy, runs
  `DROP DATABASE IF EXISTS` when ArgoCD deletes the preview Application.

Pointing the app at the database stays in the app's preview values, using
the injected variables:

```yaml
previewDatabase:
  enabled: true
controllers:
  main:
    containers:
      main:
        env:
          db__connection__database: $(APP_NAME)_preview_$(GITHUB_PR_NUMBER)
```

<!-- values: previewDatabase -->
| Key | Type | Default | Description |
|---|---|---|---|
| `previewDatabase` | object |  | Per-PR preview database: create (wave 0) and drop (PostDelete hook) Jobs against the app's managed MySQL. |
| `previewDatabase.backoffLimit` | integer | `2` | Job retries before giving up. |
| `previewDatabase.enabled` | boolean | `false` | Create the per-PR database Jobs. |
| `previewDatabase.image` | object |  | MySQL client image used by both Jobs. |
| `previewDatabase.image.repository` | string | `"mysql"` |  |
| `previewDatabase.image.tag` | string | `"8.4"` |  |
| `previewDatabase.keys` | object |  | Keys inside secretName holding host, port, user and password. |
| `previewDatabase.keys.host` | string | `"host"` |  |
| `previewDatabase.keys.password` | string | `"password"` |  |
| `previewDatabase.keys.port` | string | `"port"` |  |
| `previewDatabase.keys.user` | string | `"user"` |  |
| `previewDatabase.resources` | object | `{}` | Resources for the Job containers. |
| `previewDatabase.secretName` | string | `"app-db-secrets"` | Secret holding the MySQL connection details (pairs with secretsInjection.database, which creates app-db-secrets). |
<!-- /values -->

## k8s-app: gateways `gateway`

Every route attaches to a Gateway selected by `route.<id>.gateway`:

| selector | attaches to | load balancer |
|---|---|---|
| `shared-internal` (default) | the cluster's `shared-internal-gateway` | shared, VPC-only |
| `shared-external` | the cluster's `shared-gateway` | shared, public |
| `dedicated-internal` | a Gateway rendered by this chart | this app's own, VPC-only |
| `dedicated-external` | a Gateway rendered by this chart | this app's own, public |

`shared-*` needs nothing besides the selector: the Gateways, their wildcard
certificates and the HTTP->HTTPS redirect are cluster infrastructure
(terraform + cluster-addons).

`dedicated-*` renders, per referenced network, in the release namespace:

- a **Gateway** `<namespace>-gateway-<network>` (`gatewayClassName` from
  `gateway.dedicated.className`, DO load-balancer name pinned to the Gateway
  name, `INTERNAL` network annotation for `dedicated-internal`,
  `allowedRoutes` restricted to the release namespace);
- a cert-manager **Certificate** for the hostnames of the routes attached to
  it, against the `gateway.dedicated.issuer` ClusterIssuer (the shared
  wildcard certs do not apply to a dedicated Gateway) — the render fails if
  no attached route declares hostnames;
- a catch-all HTTP->HTTPS redirect **HTTPRoute** on its port-80 listener.

Each dedicated Gateway is a real DigitalOcean load balancer with its own
cost and IP, created when the first route references it and pruned when none
does (recreating one later gets a new IP; external-dns re-publishes DNS).
Renders with `preview.prNumber` set refuse dedicated gateways — a load
balancer per PR is never intended.

Mixing is per route: one route on `shared-external` and another on
`dedicated-external` renders one dedicated Gateway and attaches each route
where it asked.

```yaml
route:
  api:
    hostnames: [api.ghostinfra.com]
    gateway: shared-external
  partner:
    hostnames: [partner.ghostinfra.com]
    gateway: dedicated-external
```

`gateway` holds only platform facts (shared Gateway names) and dedicated
configuration; it selects nothing by itself:

<!-- values: gateway -->
| Key | Type | Default | Description |
|---|---|---|---|
| `gateway` | object |  | Gateway attachment: platform facts and dedicated-gateway configuration. Routes select their gateway via route.<id>.gateway; this key selects nothing by itself. |
| `gateway.dedicated` | object |  | Configuration for dedicated (per-app) Gateways, rendered when a route selects dedicated-internal or dedicated-external. Each is its own DO load balancer. |
| `gateway.dedicated.annotations` | object | `{}` | Extra infrastructure annotations (DO load-balancer annotations). |
| `gateway.dedicated.className` | string | `"cilium"` | GatewayClass for dedicated Gateways. |
| `gateway.dedicated.issuer` | string | `"letsencrypt-prod"` | ClusterIssuer for each dedicated Gateway's per-host certificate. |
| `gateway.shared` | object |  | The terraform-managed shared per-cluster Gateways. |
| `gateway.shared.external` | object |  | The shared public Gateway. |
| `gateway.shared.external.name` | string | `"shared-gateway"` | Name of the shared public Gateway. |
| `gateway.shared.external.namespace` | string | `"default"` | Namespace it lives in. |
| `gateway.shared.internal` | object |  | The shared internal (VPC-only) Gateway. |
| `gateway.shared.internal.name` | string | `"shared-internal-gateway"` | Name of the shared internal (VPC-only) Gateway. |
| `gateway.shared.internal.namespace` | string | `"default"` | Namespace it lives in. |
<!-- /values -->

## k8s-app: defaults applied to every release

- **Env injection**: every container and init container gets `APP_NAME` (the
  release namespace) and `GITHUB_PR_NUMBER` (`preview.prNumber`, empty
  outside previews) as literal env vars, so `$(APP_NAME)` and
  `$(GITHUB_PR_NUMBER)` can be referenced from your own env. The library
  emits env alphabetically and both names sort before lower-case keys, which
  is what makes the references resolve. Your own entry with the same name
  wins.
- **`pull-request` pod label** from `preview.prNumber`, for `kubectl -l` and
  log correlation.
- **`imagePullSecrets`**: `[{name: ghost}]` unless `defaultPodOptions.imagePullSecrets`
  is set. DOKS keeps that secret in every namespace but only attaches it to
  the default ServiceAccount, and the chart uses its own.
- **`strategy: RollingUpdate`** for deployments and statefulsets unless the
  controller sets `strategy`.
- **Route `parentRefs`** from each route's `gateway` selector
  (shared-internal by default); explicit parentRefs win, with missing
  `namespace`/`sectionName` filled as `default`/`https`.

## Upgrading

Releases are immutable and semver: patch for fixes, minor for compatible
additions, major when values or rendered resources change incompatibly.
Apps pin a version in their umbrella `Chart.yaml` and upgrade independently;
to roll back, pin the previous version. Renovate proposes bumps.

### From bjw-s app-template

k8s-app renders the same resources from the same values. Replace the
kustomize layout with the flat one from [Getting started](#getting-started),
switch the chart reference to k8s-app, and:

1. Remove the `app-secrets` / `app-db-secrets` Kustomize component references
   and add `secretsInjection: {enabled: true, database: true}` (`database`
   only for apps with a Terraform-managed MySQL).
2. Delete `values.hot-reload.yaml` and add `hotReload: {enabled: true}` to
   `values.preview.yaml`.
3. Remove the `db-previews` component reference and add
   `previewDatabase: {enabled: true}`; change the database name env to
   `$(APP_NAME)_preview_$(GITHUB_PR_NUMBER)` and drop the hand-written
   `APP_NAME`/`PR_NUMBER` `fieldRef` entries.
4. Remove the `gateway-api-name-refs` component reference; the ApplicationSet
   supplies it.
5. Check `strategy`: k8s-app defaults to `RollingUpdate`; set `Recreate` if
   the app needs it.

### 0.4.0

Preview facts became render-time values (`preview.prNumber`) instead of pod
metadata lookups; the ApplicationSet supplies them, apps write nothing.

### 0.7.0

`hotReload.knownHostsInit` (host keys fetched from the GitHub API at boot)
was replaced by the pinned `hotReload.ssh.knownHosts`.
`previewDatabase.ttlSecondsAfterFinished` was removed so the create Job runs
once per PR.

### 0.8.0

Routes attach to gateways via the `route.<id>.gateway` selector
(shared-internal default) or explicit `parentRefs`; the chart fills
`parentRefs` either way, so the base-values
`route: {main: {enabled: false, parentRefs: [...]}}` boilerplate can be
deleted — a route declared with only `hostnames` renders identically to the
old explicit form. `dedicated-*` selectors render a per-app Gateway (own DO
load balancer) with certificate and HTTP->HTTPS redirect; see
[gateways](#k8s-app-gateways-gateway).

### 0.9.0

`secretsInjection.database: true` now also fills the nconf MySQL connection
env, so the `db__client` / `db__connection__charset` /
`db__connection__database` entries in the ConfigMap and the five
`secretKeyRef` env entries (plus their copy in the migration initContainer)
can be deleted from app values. Keep any env the app overrides, such as a
preview's `db__connection__database`; anything an app still declares itself
wins over the injected value, so apps upgrade without touching their values
first.

### 0.10.0

`migrations.enabled: true` replaces the migration initContainer with a Job in
its own sync wave, so the migration runs once per sync instead of once per
pod and a failure stops the rollout instead of crash-looping it. Delete the
initContainer (and any anchors that existed only to feed it) and state the
command in the stanza. Sync waves moved with it: ExternalSecrets `-1` ->
`-10`, the preview database create Job `0` -> `-2`, migrations `-1`,
workloads `0`.
