# /fleece:smoke — Run Smoke Tests

Run the full smoke test suite against the running harness:

```bash
make smoke
```

This runs all checks in `golden-fleece/core/smoke/checks/`:
- **app-health** — health endpoint returns 200
- **registry** — registry is reachable
- **observability** — Prometheus, Loki, Tempo, Grafana, Alloy running + data queries
- **gitops** — ArgoCD server running

If any check fails, investigate and fix the issue.
Report the results clearly — what passed, what failed, what to do about failures.
