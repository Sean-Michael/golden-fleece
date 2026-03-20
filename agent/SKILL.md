---
name: golden-fleece-k8s-dev
description: >
  Load this skill when developing a Kubernetes-native application using the
  golden-fleece harness. Triggers when: the project has a golden-fleece.yaml,
  the task involves building/deploying to a local Kind cluster, working with
  Helm charts, pushing images to a local registry, or running /fleece commands.
---

# Golden Fleece — K8s Development Skill

You are operating inside a **golden-fleece** development harness. This gives
you a fully local Kubernetes environment to develop against. You have the
skills of a Certified Kubernetes Administrator (CKA) and should use them.

## Environment

Read `golden-fleece.yaml` in the project root to understand this project's
specific configuration: target type, cluster name, enabled stacks, registry
port, app start command, and health URL.

Standard endpoints (verify against golden-fleece.yaml):
- **App**: health URL from `app.health_url`
- **Registry**: `localhost:<stacks.registry.port>` (push here, pods pull from `<cluster>-registry:5000`)
- **Grafana**: port-forward `svc/grafana` in `monitoring` namespace
- **ArgoCD**: `https://localhost:30443` (if gitops stack enabled)
- **Alloy OTLP**: `alloy.monitoring.svc:4317` (gRPC), `:4318` (HTTP)

## Safety Rules — NON-NEGOTIABLE

These are hard rules, not suggestions:

1. **NEVER run `kubectl` without the correct `--context`** — use the `K=`
   variable from the Makefile which pre-pins this. In this session, `kubectl`
   on PATH is already wrapped to enforce the right context.

2. **NEVER modify `compose.yaml` or production configs** — only
   `compose.dev.yaml` and `golden-fleece.yaml` are safe to edit.

3. **NEVER `git push` or `git commit`** in an autonomous session unless
   explicitly instructed.

4. **NEVER target a cloud cluster** — if you see `eks`, `gke`, `aks`, or
   `amazonaws` in a cluster URL, stop immediately and report it.

5. **NEVER deploy to namespaces other than the project's namespace** (and
   `monitoring`, `argocd` for stack operations).

## The Adopt Flow

When running `/fleece:adopt`, follow these phases in order:

### Phase 0: Questions (3 max)
Ask:
1. Deployment target — local KIND (default) / k3d / existing cluster?
2. Stacks — install observability + GitOps? Or point at existing?
3. Anything special? (unusual port, health endpoint, etc.)

### Phase 1: App Detection
Read the repo and produce a detection report:
```yaml
detected:
  port: <from Dockerfile EXPOSE or framework config>
  health_path: <from route definitions or framework defaults>
  health_type: http | grpc | exec
  startup_time_s: <estimated from framework + app size>
  stateful: false
  dependencies: [postgres, redis, ...]
  env_vars:
    required: [DATABASE_URL, SECRET_KEY]
    optional: [LOG_LEVEL, DEBUG]
  otel_instrumented: false
  dockerfile: exists | generated
```

Sources to check: `Dockerfile`, `requirements.txt`/`go.mod`/`package.json`,
framework config, `docker-compose.yaml`, `.env.example`.

If missing: generate Dockerfile, add `/healthz` route, create `.env.example`.

Write findings to `.golden-fleece/detection.yaml`.

### Phase 2: Config Generation
Generate `golden-fleece.yaml` from detection + Phase 0 answers.
Show it to the user, wait for confirmation.

### Phase 3: Scaffold
```bash
bash golden-fleece/scaffold/new-project.sh
```
Generates: Helm chart, Makefile, AUTONOMOUS-SESSION.md, AGENTS.md.

### Phase 4: Cluster + Stacks
```bash
make kind-up
```
Monitors each step, fixes failures before proceeding.

### Phase 5: First Deploy
```bash
make image
make helm-install
```
Watch pods and actively fix issues:
- Probe failures → adjust `initialDelaySeconds` or `failureThreshold`
- Image pull errors → debug registry trust config
- CrashLoopBackOff → check logs for missing env var
- OOMKilled → increase memory limit

Iterate until pod is `1/1 Running`.

### Phase 6: Observability Validation
Validate each signal with live queries (see Observability Validation below).
If OTLP isn't wired, add the SDK, rebuild, redeploy, re-query.

### Phase 7: GitOps Deploy
Create ArgoCD Application and sync:
```bash
argocd app sync <project>
argocd app wait <project> --health --timeout 120
```

### Phase 8: Smoke Test
```bash
make smoke
```

### Phase 9: Readiness Report
Generate `k8s-readiness.md` from the template with observed values.

## Development Loop

The standard iteration cycle:

```
1. Edit source code
   ↓
2. Verify app is healthy (curl <health_url>)
   ↓  (if broken: check logs, fix, repeat)
3. make image          ← build + push to local registry
   ↓
4. make helm-install   ← Helm upgrade into Kind cluster
   ↓
5. Verify pod is running and healthy
   kubectl get pods -n <namespace>
   kubectl logs -n <namespace> -l app=<name> --tail=50
   ↓
6. Test the feature end-to-end
   ↓
7. make smoke          ← verify nothing regressed
   ↓
8. Repeat
```

For pure app development (not testing k8s behavior), steps 3-5 can be
skipped — the app runs on host with hot-reload.

## Observability Validation

Do NOT declare observability working until these queries return data:

### Metrics — verify app metrics are in Prometheus
```bash
kubectl exec -n monitoring deploy/grafana -- \
  curl -sG "http://prometheus-server/api/v1/query" \
  --data-urlencode "query=up{job=\"<project-name>\"}" | jq '.data.result'
```

### Logs — verify app logs are in Loki
```bash
kubectl exec -n monitoring deploy/grafana -- \
  curl -sG "http://loki:3100/loki/api/v1/query" \
  --data-urlencode 'query={app="<project-name>"}' | jq '.data.result[0]'
```

### Traces — verify traces are in Tempo
```bash
kubectl exec -n monitoring deploy/grafana -- \
  curl -s "http://tempo:3100/api/search?tags=service.name%3D<project-name>" \
  | jq '.traces[0]'
```

If any of these return empty results, the pipeline is not working.
Debug the specific segment (app → Alloy → backend).

## Helm Chart Standards

Every generated chart follows these standards:
- **Three probes**: startup (allows 5min), readiness (5s period), liveness (10s period)
- **Security context**: non-root (UID 1000), read-only rootfs, dropped ALL caps
- **Resources**: requests AND limits on both CPU and memory
- **HPA**: 2→10 replicas on CPU 70% (production), disabled locally
- **PDB**: minAvailable 1 (production), disabled locally
- **NetworkPolicy**: enabled in production, disabled locally
- **Secrets**: ExternalSecret stub in production, Opaque for dev
- **OTLP**: env vars injected when observability enabled

When editing the chart, always verify:
```bash
helm template <name> ./chart -f chart/values-dev.yaml | kubectl apply --dry-run=client -f -
```

## Image and Registry

- Push to: `localhost:<port>/<project>:dev`
- Pods pull from: `<cluster>-registry:5000/<project>:dev`
- `imagePullPolicy: Always` in `values-dev.yaml` ensures pods pick up new pushes

Quick image cycle:
```bash
make image
kubectl -n <namespace> rollout restart deployment/<name>
kubectl -n <namespace> rollout status deployment/<name>
```

## When Stuck

Write your concern to `NOTES.md`:
- What you were trying to do
- What went wrong
- What options you see

Then stop and wait for review. Do not hack around architectural issues.
Do not guess at cluster state — use `kubectl` to observe it directly.
