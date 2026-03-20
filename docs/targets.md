# Deployment Targets

Golden-fleece supports three deployment target types, configured via
`target.type` in `golden-fleece.yaml`.

## kind (default)

Local Kubernetes cluster using [KIND](https://kind.sigs.k8s.io/).
Golden-fleece manages the full lifecycle.

```yaml
target:
  type: kind
  cluster_name: "my-app-dev"
  ports:
    - containerPort: 30800
      hostPort: 8080
      protocol: TCP
```

**Scripts:**
- `core/targets/kind/bootstrap.sh` — create cluster, render kind-config
- `core/targets/kind/teardown.sh` — delete cluster, clean registry container
- `core/targets/kind/kind-config.yaml.tmpl` — cluster template

**Context format:** `kind-<cluster_name>`

**Port mappings:** Defined in `target.ports`. Each mapping exposes a NodePort
on `localhost:<hostPort>`. The Argo Workflows port (30746→2746) is added
automatically when that stack is enabled.

## k3d

Local Kubernetes cluster using [k3d](https://k3d.io/). Not yet implemented —
the structure mirrors KIND.

```yaml
target:
  type: k3d
  cluster_name: "my-app-dev"
```

**Context format:** `k3d-<cluster_name>`

## existing

Connect to a cluster you already have. Golden-fleece only operates within
the configured namespace.

```yaml
target:
  type: existing
  context: "my-dev-cluster"
  namespace: "my-app-dev"
```

**Safety:** Golden-fleece never touches cluster-wide resources outside the
configured namespace. The kubectl-wrapper enforces the context, and
`guard.sh` rejects cloud contexts (EKS/GKE/AKS URLs).
