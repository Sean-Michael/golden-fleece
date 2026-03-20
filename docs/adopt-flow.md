# The Adopt Flow

`/fleece:adopt` is the primary command. It takes a working application and
makes it production-ready on Kubernetes in a local sandbox.

## Phases

### Phase 0: Questions (3 max)

Claude asks:
1. **Deployment target** — local KIND cluster (default) / k3d / existing?
2. **Stacks** — install observability + GitOps, or point at existing?
3. **Anything special?** — unusual port, health endpoint, etc.

Everything else Claude figures out by reading the repo.

### Phase 1: App Detection

Claude reads the repo and produces a detection report saved to
`.golden-fleece/detection.yaml`:

```yaml
detected:
  port: 8000
  health_path: /healthz
  health_type: http
  startup_time_s: 15
  stateful: false
  dependencies: [postgres, redis]
  env_vars:
    required: [DATABASE_URL, SECRET_KEY]
    optional: [LOG_LEVEL, DEBUG]
  otel_instrumented: false
  dockerfile: exists
```

Sources checked: `Dockerfile`, `requirements.txt`/`go.mod`/`package.json`,
framework config, `docker-compose.yaml`, `.env.example`.

If anything is missing, Claude creates it:
- No Dockerfile → generates one for the detected language/framework
- No health endpoint → adds `/healthz` route
- No `.env.example` → generates from detected env var usage

### Phase 2: Config Generation

Claude generates `golden-fleece.yaml` from the detection report and Phase 0
answers, then shows it for user confirmation before proceeding.

### Phase 3: Scaffold

```bash
bash golden-fleece/scaffold/new-project.sh
```

Generates:
- Full Helm chart in `chart/` with production defaults and dev overrides
- `Makefile` with all standard targets
- `AUTONOMOUS-SESSION.md` and `AGENTS.md` templates
- `hack/` directory structure

### Phase 4: Cluster + Stacks

```bash
make kind-up
```

Based on `golden-fleece.yaml`, this:
- Bootstraps the target (KIND/k3d/validates existing)
- Sets up the registry (local or connects external)
- Installs observability (LGTM stack or connects external)
- Installs GitOps (ArgoCD or connects external)

### Phase 5: First Deploy

```bash
make image
make helm-install
```

Claude watches pods and actively fixes issues:
- Probe failures → adjust thresholds
- Image pull errors → debug registry trust
- CrashLoopBackOff → check logs, fix missing config
- OOMKilled → increase memory limit

Iterates until pod is `1/1 Running`.

### Phase 6: Observability Validation

Claude validates each signal with live queries:
- **Metrics**: Prometheus query for `up{job="<app>"}` returns data
- **Logs**: Loki `query_range` for `{namespace="<app>"}` returns entries
- **Traces**: Tempo search for `service.name=<app>` returns traces

If OTLP isn't wired, Claude adds the SDK, rebuilds, and redeploys.

### Phase 7: GitOps Validation

ArgoCD is installed but the Application is only created when a git remote
exists. For local dev without a remote:
- Phase 5 deployed via `helm install` — the app is already running
- ArgoCD validates GitOps-readiness (project + RBAC configured)
- Readiness report notes ArgoCD sync as pending a real git remote

If a git remote IS available, Claude syncs the ArgoCD Application.

### Phase 8: Smoke Test

```bash
make smoke
```

Runs all checks: app health, registry, observability, gitops.

### Phase 9: Readiness Report

Claude generates `k8s-readiness.md` documenting:
- What's completed (with live verification)
- What's left before production
- Observed metrics (startup time, memory, CPU)
