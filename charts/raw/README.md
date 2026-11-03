# raw

Renders every manifest in `resources` as-is. No templating, defaults or
labels are added.

```yaml
resources:
  - apiVersion: v1
    kind: Namespace
    metadata:
      name: example
```

Terraform's `argocd` module uses it to deliver objects it computes (team RBAC)
to every cluster: it passes them as `helm.valuesObject` of an ArgoCD
Application, so the hub's ArgoCD does the delivery.
