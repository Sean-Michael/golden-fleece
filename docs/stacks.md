# Stacks Reference

Stacks are composable cluster addons. Each can be installed by golden-fleece
or pointed at an existing instance.

## Registry

Get images built and pullable from inside the cluster.

### kind type (local)

```yaml
stacks:
  registry:
    enabled: true
    type: kind
    port: 5050
```

Runs `registry:2` as a Docker container on `localhost:<port>`, connects it
to the Kind Docker network, and patches containerd trust on each node.

- **Script:** `core/stacks/registry/kind/setup.sh`
- **Push to:** `localhost:<port>/<project>:dev`
- **Pods pull from:** `<cluster>-registry:5000/<project>:dev`

### external type

```yaml
stacks:
  registry:
    enabled: true
    type: external
    url: "harbor.company.com"
    secret: "harbor-pull-secret"
```

Validates the registry is reachable and writes connection config to
`.golden-fleece/registry.env`.

- **Script:** `core/stacks/registry/external/connect.sh`

## Observability

Validate the app is genuinely observable — logs, metrics, traces.

### lgtm type (full stack)

```yaml
stacks:
  observability:
    enabled: true
    type: lgtm
```

Installs the complete stack:
- **Loki** — logs, single binary mode
- **Tempo** — traces, single binary mode
- **Prometheus** — metrics, with remote-write receiver
- **Grafana** — visualization, pre-configured datasources
- **Alloy** — collector: OTLP receiver → Tempo + Prometheus, pod logs → Loki

**In-cluster endpoints:**

| Component  | Endpoint                              |
|-----------|---------------------------------------|
| Loki      | `loki.monitoring.svc:3100`            |
| Tempo     | `tempo.monitoring.svc:3100`           |
| Prometheus| `prometheus-server.monitoring.svc:80` |
| Grafana   | `grafana.monitoring.svc:3000`         |
| Alloy     | `alloy.monitoring.svc:4317/4318`      |

**Script:** `core/stacks/observability/lgtm/install.sh`

**App-side wiring** (injected by the Helm chart when `observability.enabled=true`):
```
OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy.monitoring.svc.cluster.local:4318
OTEL_SERVICE_NAME=<release-name>
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=<namespace>
```

### external type

```yaml
stacks:
  observability:
    enabled: true
    type: external
    grafana_url: "http://grafana.company.com"
    loki_url: "http://loki.company.com"
    prometheus_url: "http://prometheus.company.com"
    otlp_endpoint: "http://alloy.company.com:4318"
```

Validates each endpoint and writes config to `.golden-fleece/observability.env`.

- **Script:** `core/stacks/observability/external/connect.sh`

## GitOps (ArgoCD)

Validate the Helm chart is GitOps-compatible.

### argocd type (install)

```yaml
stacks:
  gitops:
    enabled: true
    type: argocd
```

Installs ArgoCD, exposes UI via NodePort (localhost:30443), creates a scoped
AppProject for the app. The ArgoCD Application is only created when a git
remote is detected (`git remote get-url origin`). Without a remote, local
dev uses `helm install` directly.

**Script:** `core/stacks/gitops/argocd/install.sh`

### external type

```yaml
stacks:
  gitops:
    enabled: true
    type: external
    url: "https://argocd.company.com"
    project: "default"
```

Validates ArgoCD is reachable, writes config to `.golden-fleece/gitops.env`.

- **Script:** `core/stacks/gitops/external/connect.sh`
