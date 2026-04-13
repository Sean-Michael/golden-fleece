---
name: golden-fleece-k8s-dev
description: >
  Load this skill when developing a Kubernetes-native application using the
  golden-fleece harness. Triggers when: the project has a golden-fleece.yaml,
  the task involves building/deploying to a local Kind cluster, working with
  Helm charts, pushing images to a local registry, or running /fleece commands.
---

# Golden Fleece — K8s Development Skill

## Mission

Take a containerized application — `Dockerfile`, usually `compose.yaml`,
and the source around it — and produce a Helm chart that replicates the
runtime semantics in k8s-native ways. The workload's *shape* (stateless
HTTP, stateful, batch, cron, event consumer, gRPC) decides the outer
resource (Deployment, StatefulSet, Job, CronJob); compose decides the
inner details (`environment` → ConfigMap+Secret, `volumes` → PVC,
`healthcheck` → probes). You validate the result with live queries
against the running cluster and write a readiness report that justifies
every chart decision and documents the production path.

The harness (local KIND cluster, local registry, LGTM observability,
opt-in ArgoCD) exists so the chart behaves the same way in the sandbox
as it will in production.

For the full adopt flow, see `.claude-plugin/commands/adopt.md`.

## Safety Rules — NON-NEGOTIABLE

1. **NEVER run `kubectl` without the correct `--context`.** Use `${K}` from
   the Makefile (pre-pinned) or `kubectl --context kind-<cluster>` explicitly.
2. **NEVER modify `compose.yaml` or production configs.** Only
   `compose.dev.yaml` and `golden-fleece.yaml` are safe to edit.
3. **NEVER `git push` or `git commit`** in an autonomous session unless
   explicitly instructed.
4. **NEVER target a cloud cluster.** If you see `eks`, `gke`, `aks`, or
   `amazonaws` in a cluster URL, stop immediately and report it.
5. **NEVER deploy to namespaces other than the project's namespace** (and
   `monitoring`, `argocd` for stack operations).

## Self-Healing Principle

If a dependency isn't running, **bring it up**. Don't fail and tell the
human to run `make up`. Read `agent/hooks/pre-session.sh` output to see
what's missing, then call the right script:

- Missing cluster → `core/targets/kind/bootstrap.sh`
- Missing registry → `core/stacks/registry/kind/setup.sh`
- Missing observability (if enabled) → `core/stacks/observability/lgtm/install.sh`
- Missing gitops (if enabled) → `core/stacks/gitops/argocd/install.sh`
- App not deployed → `make image && make helm-install`

Diagnose root causes; don't hack around issues. Only escalate after you
have investigated and tried the obvious fixes.

## Workload Classification

Before scaffolding or shaping the chart, decide which class this app fits.
This drives every downstream choice.

| Class             | Indicators                                           | Include                                                   | Exclude                                          |
|-------------------|------------------------------------------------------|-----------------------------------------------------------|--------------------------------------------------|
| `stateless-http`  | HTTP routes, no disk, horizontal scaling ok          | Deployment, Service, HPA, PDB, HTTP probes, Ingress       | PVC, StatefulSet, ordered rollout                |
| `stateless-grpc`  | gRPC server (`grpc.Server`, protobuf), no disk       | Deployment, Service, **gRPC** probes, headless Service    | HTTP Ingress (use grpc-ingress), HTTP probes     |
| `stateful`        | Writes to disk, needs stable identity (DB, broker)   | StatefulSet, volumeClaimTemplate, headless Service, PDB   | HPA, rolling replace                             |
| `batch-job`       | Runs once, exits (ETL, migration, one-shot)          | Job, Never restart, backoffLimit, optional TTL            | Service, Ingress, HPA, PDB, readiness probe     |
| `scheduled`       | Cron-like, periodic execution                        | CronJob, concurrencyPolicy, history limits                | Service, Ingress, HPA, PDB, readiness probe     |
| `event-consumer`  | Reads queue/stream (Kafka, SQS, NATS), no HTTP       | Deployment, KEDA ScaledObject, no Service                 | Ingress, HPA (use KEDA), readiness probe         |
| `no-ingress`      | Internal-only side-car, utility, scheduled trigger   | Deployment or CronJob, ClusterIP-only or no Service       | Ingress, NetworkPolicy ingress rules             |

When in doubt between classes, prefer the simpler one (`stateless-http`
for HTTP APIs is the usual default). Record your choice and reasoning in
`.golden-fleece/detection.yaml` and again in `k8s-readiness.md`.

## Compose → K8s Mapping

When `compose.yaml` exists, treat it as the source of truth for the
app's runtime semantics. The workload class decides the outer resource
shape; compose decides the inner details.

| Compose                         | K8s                                                              |
|---------------------------------|------------------------------------------------------------------|
| `services.<name>.image`         | `spec.template.spec.containers[].image`                          |
| `services.<name>.environment`   | ConfigMap (non-secrets) + Secret (credentials, tokens, keys)     |
| `services.<name>.ports`         | `Service` (ClusterIP) + optional `Ingress`                       |
| `services.<name>.volumes`       | PVC + `volumeMounts`; host binds become `emptyDir` or ConfigMaps |
| `services.<name>.healthcheck`   | `livenessProbe` / `readinessProbe` (use `httpGet` or `exec`)     |
| `services.<name>.depends_on`    | Readiness probe that retries the connection; an initContainer probe is a wait, not the dep itself |
| `services.<name>.restart`       | `restartPolicy` (Always for Deployment, Never/OnFailure for Job) |
| `services.<name>.deploy.resources` | `resources.requests` / `resources.limits`                     |
| `services.<name>.command`       | `spec.template.spec.containers[].command` / `args`               |
| `networks`                      | Usually nothing — pods share a flat network inside a namespace   |

Secrets split: anything that looks like a credential (`*_PASSWORD`,
`*_SECRET`, `*_TOKEN`, `*_KEY`, `DATABASE_URL` with a password) goes
into a `Secret`. Everything else goes into the `ConfigMap`.

## Dependencies

Compose services that aren't the app — postgres, redis, a model
server — are real workloads, not parts of the app's chart. Bring each
up as its own sibling release (upstream chart, operator, or an
`ExternalName` pointing at something already running), wire the
connection into the app via ConfigMap/Secret env vars, and never
hard-code a dep hostname in the chart templates.

Do this only when compose makes it obvious *or* the user asks for it.
When in doubt, stop and ask rather than spinning up infrastructure
the user didn't request.

The readiness report records, for each dep, what ran in dev and what
should run in prod (managed service, operator with production sizing,
shared cluster instance) — that decision is the point.

## Environment

Read `golden-fleece.yaml` for project-specific config: target type,
cluster name, enabled stacks, registry port, app start command, health URL.

Standard endpoints (verify against config):
- **App**: health URL from `app.health_url`
- **Registry**: `localhost:<stacks.registry.port>` (push here; pods pull from `<cluster>-registry:5000`)
- **Grafana**: port-forward `svc/grafana -n monitoring`
- **ArgoCD**: `https://localhost:30443` (if gitops enabled)
- **Alloy OTLP**: `alloy.monitoring.svc:4317` gRPC / `:4318` HTTP

## Development Loop

```
1. Edit code
2. Verify app healthy on host    (curl ${APP_HEALTH_URL})
3. make image                    (build + push to local registry)
4. make helm-install              (Helm upgrade into Kind)
5. Verify pod running              ($K get pods -n <ns>; $K logs ... --tail=50)
6. Test feature end-to-end
7. make smoke                    (verify nothing regressed)
```

For pure app work (no k8s behavior changes), steps 3–5 can be skipped —
the app runs on host with hot-reload.

## Observability Validation

Do NOT declare observability working until these queries return data.

**Metrics — Prometheus:**
```bash
${K} exec -n monitoring deploy/grafana -- \
  curl -sG "http://prometheus-server/api/v1/query" \
  --data-urlencode "query=up{job=\"<project-name>\"}" | jq '.data.result'
```

**Logs — Loki** (use `query_range`, not `query` — instant queries don't work for logs):
```bash
${K} exec -n monitoring deploy/grafana -- \
  curl -sG "http://loki:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={namespace="<project-name>"}' | jq '.data.result[0]'
```

**Traces — Tempo:**
```bash
${K} exec -n monitoring deploy/grafana -- \
  curl -s "http://tempo:3100/api/search?tags=service.name%3D<project-name>" \
  | jq '.traces[0]'
```

If any return empty, the pipeline is broken. Debug the specific segment
(app → Alloy → backend). If OTLP isn't wired in the app, add the SDK,
rebuild, redeploy, re-query.

## Helm Chart Standards (Default Shape)

The scaffold generates a chart tuned for `stateless-http`. You will
**edit it to match the workload class** — that's the point. Default shape:

- **Three probes**: startup (allows 5min), readiness (5s period), liveness (10s period)
- **Security context**: non-root (UID 1000), read-only rootfs, dropped ALL caps
- **Resources**: requests AND limits on CPU + memory
- **HPA**: 2→10 replicas on CPU 70% (prod), disabled locally
- **PDB**: minAvailable 1 (prod), disabled locally
- **NetworkPolicy**: enabled in prod, disabled locally
- **OTLP env vars**: injected when observability enabled
- **Secrets**: ExternalSecret stub in prod, Opaque for dev

When editing the chart, always verify before applying:
```bash
helm template <name> ./chart -f chart/values-dev.yaml \
  | ${K} apply --dry-run=client -f -
```

## GitOps as an Artifact (opt-in)

GitOps is off by default. Enable `stacks.gitops.enabled: true` in
`golden-fleece.yaml` only when the ArgoCD `Application` manifest is
itself a deliverable you want to develop — i.e. GitOps *is* the
deployment method you're targeting in production.

When enabled, treat the ArgoCD `Application` as a shaped artifact, not
just a thing the install script creates. Tune `syncPolicy`,
`retry.backoff`, `prune`, `selfHeal`, and `ignoreDifferences` to match
how the app actually behaves. Record the decisions in the readiness
report alongside the chart decisions.

When disabled (the default), the readiness report still documents the
**path to GitOps**: which values are safe to commit, where secrets
come from at sync time, what the `Application` spec would look like
for a production ArgoCD.
