# /fleece:adopt — Autonomous K8s Adoption

Take this project's `Dockerfile` and `compose.yaml` and produce the
Kubernetes that makes it work — shaped for the actual workload,
validated in the local sandbox, with a readiness report that
documents the production path.

Autonomous. Do not stop for human approval between phases. Diagnose
and fix problems; only escalate after investigation.

See `golden-fleece/agent/SKILL.md` for safety rules, the full workload
classification taxonomy, and observability query patterns.

## Phase 1: Detect

Read the repo — `Dockerfile`, `requirements.txt`/`go.mod`/`package.json`,
framework config, `compose.yaml`, `.env.example`, route definitions — and
write findings to `.golden-fleece/detection.yaml`: port, health path,
stateful?, inbound traffic?, dependencies, required/optional env vars,
OTLP instrumented?, startup time estimate.

Generate missing pieces: a Dockerfile for the detected language, a
`/healthz` route, an `.env.example` from observed env usage.

## Phase 2: Classify the Workload

Pick exactly one workload class and record it in `.golden-fleece/detection.yaml`
with a one-sentence reasoning:

```yaml
workload:
  class: stateless-http
  reasoning: >
    HTTP API with no disk writes, scales horizontally, exposes /healthz
    and /metrics on port 8000.
```

Classes (see SKILL.md for the full matrix):
- `stateless-http` — default for HTTP APIs
- `stateless-grpc` — gRPC server, protobuf
- `stateful` — writes to disk, needs stable identity
- `batch-job` — runs once, exits
- `scheduled` — cron-like periodic execution
- `event-consumer` — reads a queue/stream, no inbound traffic
- `no-ingress` — internal-only, no `Service`/`Ingress`

When in doubt, prefer the simpler class. You will use this decision in
Phase 5 to shape the chart and again in Phase 10 to justify choices.

## Phase 3: Configure

Generate `golden-fleece.yaml` at the project root using the detection
report. Defaults:

- **Registry**: enabled, port 5050
- **Observability (LGTM)**: enabled
- **GitOps (ArgoCD)**: **disabled** unless the user explicitly asked
  for it, or the project clearly targets GitOps-driven deployment
  (e.g. has an existing `argocd/` directory, `Application` manifests,
  or a git-driven CI/CD workflow). When enabled, the ArgoCD
  `Application` manifest becomes an artifact you shape in Phase 5.

Cluster name defaults to `<project>-dev`.

**Do not stop for approval.** Write the file and proceed. If the user
needs to change something, they will tell you afterward.

## Phase 4: Scaffold

```bash
bash golden-fleece/scaffold/new-project.sh
```

Generates the `Makefile`, the Helm chart at `chart/`, and the
`.golden-fleece/` directory.

## Phase 5: Shape the Chart

The scaffold's default chart is tuned for `stateless-http`. Now edit
`chart/` so it fits *this* app. Two passes: outer shape (workload
class) and inner details (compose → k8s). Log every edit with its
reason in a running notes buffer — you will surface these in the
readiness report.

### 5a. Outer shape — workload class

| Class             | Chart edits                                                                                          |
|-------------------|------------------------------------------------------------------------------------------------------|
| `stateless-http`  | No edits; default shape fits.                                                                        |
| `stateless-grpc`  | Change probes to `grpc:` type, adjust `Service` ports, swap `Ingress` for gRPC ingress (or remove). |
| `stateful`        | Replace `Deployment` with `StatefulSet`, add `volumeClaimTemplate`, use a headless `Service`, drop HPA. |
| `batch-job`       | Replace `Deployment` with `Job`, set `restartPolicy: Never`, add `backoffLimit`, drop `Service`/HPA/PDB/readiness probe. |
| `scheduled`       | Replace `Deployment` with `CronJob`, set schedule + `concurrencyPolicy`, drop `Service`/HPA/PDB/readiness probe. |
| `event-consumer`  | Keep `Deployment`, drop `Service`/`Ingress`, replace HPA with a KEDA `ScaledObject` stub, drop readiness probe. |
| `no-ingress`      | Drop `Service` (or keep ClusterIP-only), drop `Ingress`, remove NetworkPolicy ingress rules.         |

### 5b. Inner details — compose → k8s

When `compose.yaml` exists it is the source of truth for runtime
semantics. Apply the `SKILL.md` compose → k8s mapping: `environment`
splits into ConfigMap + Secret (anything that looks like a credential
goes in the Secret); volumes become PVCs or `emptyDir`; ports become
`Service` + optional `Ingress`; `healthcheck` becomes probes;
`deploy.resources` becomes requests/limits.

Compose services that aren't the app (postgres, redis, a model
server) are real workloads, installed in Phase 6. The app chart
reads their connection info through ConfigMap/Secret env vars and
never hard-codes a hostname. Only install deps that are in compose
or that the user explicitly asked for; if it's ambiguous, ask.

### 5c. GitOps artifact (only if `stacks.gitops.enabled: true`)

Generate / tune the ArgoCD `Application` manifest as a deliverable.
Don't just accept whatever the install script creates. Shape:

- `syncPolicy.automated` vs manual (automated for MVPs, manual for
  stateful / production-critical)
- `prune` and `selfHeal` (usually both true for stateless, both false
  for stateful)
- `retry.backoff` (limit + duration)
- `ignoreDifferences` for fields a controller mutates (HPA replicas,
  injected annotations)
- `syncOptions`: `CreateNamespace=true`, `ServerSideApply=true`,
  `RespectIgnoreDifferences=true` as appropriate

Record each decision in the readiness report.

### Verify the shaped chart renders

```bash
helm template <project> ./chart -f chart/values-dev.yaml \
  | kubectl --context kind-<cluster> apply --dry-run=client -f -
```

## Phase 6: Bootstrap the Cluster + Stacks + Dependencies

```bash
make kind-up
```

Creates the Kind cluster, starts the local registry, and installs
whichever stacks `golden-fleece.yaml` enabled (observability by
default; gitops only if opted in).

If Phase 5b identified compose dependencies, install each as a
sibling Helm release in the project namespace (bitnami charts are
the default for dev), wait for the dep pods to be `Ready`, then wire
connection strings into the app's ConfigMap/Secret so Phase 7 picks
them up.

Diagnose and fix bootstrap failures — port conflicts, Helm timeouts,
missing deps — rather than aborting. Docker not running is outside
your control; tell the user.

## Phase 7: First Deploy

```bash
make image
make helm-install
```

Watch pods and iterate until `1/1 Running` with zero restarts — tune
probes, fix registry wiring, raise memory limits, add missing env
vars as problems appear.

For batch/scheduled workloads the healthy state is a successful Job
or at least one successful CronJob run (`$K get jobs -n <ns>`,
check `.status.succeeded`).

## Phase 8: Validate Observability

Run the three live queries from `SKILL.md` (Prometheus, Loki, Tempo).
If any return empty, fix the broken segment (scrape annotation, Alloy
ingestion, missing OTLP SDK) and re-query. Do not declare
observability working until the queries return data.

For `batch-job` / `scheduled` classes, metrics and traces may be
absent by design — verify logs only and note the skip in the
readiness report.

## Phase 9: Smoke Test

```bash
make smoke
```

Fix any failures and re-run until it passes clean. Smoke checks are
read-only — failures indicate real problems, not flakes.

## Phase 10: Readiness Report

Generate `k8s-readiness.md` at the project root. This is the critical
artifact — it is what makes adoption an MVP→prod on-ramp rather than a
working sandbox. Include:

1. **Workload class** and reasoning for the choice.
2. **Chart features included**, with justification — e.g., "HPA enabled
   because stateless HTTP; PDB enabled because minAvailable=1 prevents
   rolling-update outages."
3. **Chart features skipped**, with justification — e.g., "No StatefulSet:
   app has no persistent state. No Ingress: internal-only service."
4. **Observed values**: startup time, memory (p50/p99), CPU, replica count,
   and whether metrics/logs/traces are flowing.
5. **The production path**:
   - Values that change between `values-dev.yaml` and `values.yaml`
     (replicas, resources, HPA/PDB, NetworkPolicy, image pull policy).
   - External systems to wire up: real registry, real secrets
     backend, real DNS/TLS, real observability backends.
   - Every dependency you installed in dev and what it should be in
     prod (managed service? operator at production sizing? shared
     cluster instance?), plus any migration / seeding steps.
   - Manual prerequisites (DB migration, RBAC, namespace setup).
   - **Path to GitOps** — what the ArgoCD `Application` spec would
     look like pointing at `./chart`, which values are safe to commit,
     where secrets come from at sync time. Included even when GitOps
     is off in dev: it's a production decision the user will make
     later.

## Success Criteria

You are done when:
- Pod is `1/1 Running` (or Job `.status.succeeded: 1`) with no restarts
- Health endpoint returns 200 (for classes that have one)
- Metrics visible in Prometheus via live query (if applicable to the class)
- Logs visible in Loki via live query
- Traces visible in Tempo via live query (if OTLP instrumented)
- ArgoCD Application Healthy + Synced — only if gitops is enabled AND a git remote exists
- `make smoke` passes
- `k8s-readiness.md` is generated and justifies every chart decision
