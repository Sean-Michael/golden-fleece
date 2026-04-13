# /fleece:smoke — Run Smoke Tests

```bash
make smoke
```

Runs every check in `golden-fleece/core/smoke/checks/`. Each check
reads `golden-fleece.yaml` and skips cleanly if its stack is disabled.

- **app-health** — health endpoint returns 200
- **registry** — local registry responds on `/v2/`
- **observability** — Prometheus / Loki / Tempo / Grafana / Alloy running and returning data (skipped if `stacks.observability.enabled: false`)
- **gitops** — ArgoCD server + AppProject + Application healthy (skipped if `stacks.gitops.enabled: false`)

Investigate and fix any failures. Smoke checks are read-only — a
failure is a real problem, not a flake.
