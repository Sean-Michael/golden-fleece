# The Adopt Flow

`/fleece:adopt` is the primary command. It takes any containerized
application and produces a Kubernetes deployment **shaped for that
specific workload**, running in a local sandbox that matches the shape
of production. The agent drives end-to-end — there is no human approval
gate.

The flow in one line:

```
detect → classify → configure → scaffold → shape → bootstrap → deploy → validate → smoke → report
```

The full command prompt lives at `.claude-plugin/commands/adopt.md` —
this doc is the reference walkthrough.

## Phase 1: Detect

The agent reads `Dockerfile`, `requirements.txt`/`go.mod`/`package.json`,
framework config, `compose.yaml`, `.env.example`, and route definitions,
then writes findings — port, health path, stateful?, inbound traffic?,
dependencies, env vars, OTLP instrumented?, startup time — to
`.golden-fleece/detection.yaml`.

Missing pieces are generated: a Dockerfile for the detected language,
a `/healthz` route, an `.env.example` from observed env usage.

## Phase 2: Classify the Workload

Before anything else, the agent picks one workload class and records
why. This is the decision that drives every downstream choice:

```yaml
workload:
  class: stateless-http
  reasoning: >
    HTTP API with no disk writes, scales horizontally, exposes /healthz
    and /metrics on port 8000.
```

| Class             | Indicators                                           | Shape                                          |
|-------------------|------------------------------------------------------|------------------------------------------------|
| `stateless-http`  | HTTP routes, no disk, horizontally scalable          | Deployment + Service + HPA + PDB + probes      |
| `stateless-grpc`  | gRPC server, protobuf                                | Deployment + headless Service + gRPC probes    |
| `stateful`        | Writes to disk, stable identity needed               | StatefulSet + PVC + headless Service           |
| `batch-job`       | Runs once, exits                                     | Job, no Service, no probes, no HPA             |
| `scheduled`       | Cron-like periodic execution                         | CronJob, no Service, no probes                 |
| `event-consumer`  | Reads a queue/stream, no HTTP                        | Deployment + KEDA ScaledObject, no Service     |
| `no-ingress`      | Internal-only, no inbound traffic                    | Deployment or CronJob, no Ingress              |

When in doubt, the agent prefers the simpler class. The classification
drives every downstream decision and shows up again in the readiness
report.

## Phase 3: Configure

The agent generates `golden-fleece.yaml` directly — no template copy,
no human approval. Defaults:

- Registry + observability (LGTM): **enabled**.
- GitOps (ArgoCD): **opt-in**, off by default. Enable when the ArgoCD
  `Application` manifest is itself a deliverable the agent should
  shape — i.e. when GitOps is the target production deployment method.

## Phase 4: Scaffold

```bash
bash golden-fleece/scaffold/new-project.sh
```

Generates:
- `Makefile` with the harness targets
- Helm chart at `chart/` with the default shape (tuned for `stateless-http`)
- `.golden-fleece/` directory (gitignored)

## Phase 5: Shape the Chart

Two passes — outer shape (workload class) and inner details
(compose → k8s). Every edit is logged with its reason so the
readiness report can justify it.

### Outer shape — workload class

- **batch-job** → `Deployment` → `Job`, drop `Service`/HPA/PDB/readiness probe
- **scheduled** → `Deployment` → `CronJob`, drop `Service`/HPA/PDB/readiness probe
- **stateful** → `Deployment` → `StatefulSet`, add `volumeClaimTemplate`, drop HPA
- **stateless-grpc** → HTTP probes → gRPC probes, swap `Ingress`
- **event-consumer** → drop `Service`/`Ingress`, HPA → KEDA `ScaledObject`
- **no-ingress** → drop `Service`/`Ingress`, remove NetworkPolicy ingress rules

### Inner details — compose → k8s

When `compose.yaml` exists, it is the source of truth for runtime
semantics. The mapping the agent applies (full table in `SKILL.md`):

- `environment` → ConfigMap (non-secrets) + Secret (credentials)
- `volumes` → PVC + `volumeMounts`
- `ports` → `Service` + optional `Ingress`
- `healthcheck` → `livenessProbe` / `readinessProbe`
- `deploy.resources` → `resources.requests` / `limits`

### Dependencies

Compose services that are *not* the app — postgres, redis, a model
server — are real workloads, installed in Phase 6 as sibling Helm
releases (or operators, or `ExternalName` Services pointing at an
already-running instance). The app chart reads connection info from
ConfigMap/Secret env vars and never hard-codes a hostname. The
`depends_on` *wait* is the app's readiness probe retrying the
connection, or — if the app can't tolerate that — an initContainer
probe. An initContainer is a wait, not the dep itself.

The agent installs only the deps that are in compose or that the
user asked for. Phase 10 documents the prod-path decision for each
one.

### GitOps artifact (opt-in)

If `stacks.gitops.enabled: true`, the agent also shapes the ArgoCD
`Application` manifest: `syncPolicy`, `prune`, `selfHeal`, retry
backoff, `ignoreDifferences` for controller-mutated fields. Each
decision lands in the readiness report alongside the chart decisions.

The shaped chart is verified with a dry-run before the first deploy:

```bash
helm template <project> ./chart -f chart/values-dev.yaml \
  | kubectl --context kind-<cluster> apply --dry-run=client -f -
```

## Phase 6: Bootstrap the Cluster + Stacks + Dependencies

```bash
make kind-up
```

Creates the Kind cluster, starts the local registry, and installs
the enabled stacks (observability by default; gitops only if opted
in).

If Phase 5 identified compose dependencies, the agent installs each
one as a sibling Helm release in the project namespace, waits for
the pods to be `Ready`, and wires connection strings into the app's
ConfigMap/Secret so the first deploy (Phase 7) comes up against live
deps. Port conflicts and helm timeouts are diagnosed and fixed, not
cause for aborting.

## Phase 7: First Deploy

```bash
make image
make helm-install
```

The agent watches pods and fixes problems as they appear: probe
failures, image pull errors, CrashLoopBackOff (read logs), OOMKilled
(raise limits), missing env vars. It iterates until the pod is
`1/1 Running` with zero restarts — or, for batch/scheduled workloads,
until a Job reports `.status.succeeded`.

## Phase 8: Validate Observability

Live queries — not just "the pod is running":

- **Metrics**: `up{job="<project>"}` against Prometheus
- **Logs**: `{namespace="<project>"}` via Loki `query_range`
- **Traces**: `service.name=<project>` against Tempo

If any return empty, the pipeline is broken and the agent fixes the
specific segment (app → Alloy → backend). If the app isn't
OTLP-instrumented, the agent adds the SDK, rebuilds, redeploys, re-queries.

For `batch-job` / `scheduled` classes, metrics and traces may be absent
by design — the agent notes the skip in the readiness report.

## Phase 9: Smoke Test

```bash
make smoke
```

All checks must pass. Failures are investigated and fixed; they are
not flakes.

## Phase 10: Readiness Report

The agent generates `k8s-readiness.md` at the project root. This is
the critical artifact — it documents not just "what works" but the
**production path**. It includes:

1. **Workload class** and why.
2. **Chart features included**, with justification per feature.
3. **Chart features skipped**, with justification per skip.
4. **Observed values**: startup time, memory (p50/p99), CPU, replicas,
   which signals are flowing.
5. **Production path**:
   - Values that change between `values-dev.yaml` and `values.yaml`
   - External systems to wire up (real registry, secrets backend, DNS, TLS)
   - Every dependency: what the agent installed in dev and what it
     should be in prod (managed service? operator at production
     sizing? shared cluster instance?), plus any migration / seeding
     steps for the cutover
   - Manual prerequisites (DB migration, RBAC, namespace setup)
   - **Path to GitOps** — what the ArgoCD `Application` spec would
     look like, which values are safe to commit, where secrets come
     from at sync time. Included even when GitOps is off in dev:
     it's a production decision the user will make later.
