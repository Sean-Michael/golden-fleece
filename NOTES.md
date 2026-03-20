# Implementation Notes

## Phase A decisions

### Config parsing backward compatibility
`guard.sh` and `kubectl-wrapper` both try the new schema (`target.cluster_name`) first,
then fall back to the old schema (`cluster.name`). This means existing `golden-fleece.yaml`
files from the first generation still work without changes.

### kind-config.yaml.tmpl was missing
DESIGN.md listed `core/cluster/kind-config.yaml.tmpl` as an existing file, but it wasn't
in the repo. Created it at `core/targets/kind/kind-config.yaml.tmpl` based on the standard
Kind cluster config pattern (containerd registry config patch + port mappings).

### Makefile stack detection
Using `awk` range patterns to parse YAML sections portably
(works on macOS BSD awk and GNU awk). Example:
`awk '/^  observability:/,/^  [a-z]/{if(/enabled:.*true/)exit 0}END{exit 1}'`

### Registry port parsing
The `setup.sh` parser greps for `port:` lines which is fragile with the deeper nesting.
Currently works because the registry port line is the most specific match, but this
should be made more robust in a future pass.

## Phase B decisions

### Alert rules are generic
Shipped alert rules use standard OTLP metric names (`http_server_request_duration_seconds`)
rather than project-specific ones. They fire for any app exporting OpenTelemetry HTTP metrics.
Project-specific alerts should be added via the `chart/` directory.

### Dashboard template vs project dashboards
The `app-overview.json.tmpl` renders with `{{PROJECT_NAME}}` and `{{PROJECT_NS}}` at install
time. Project-specific dashboards can be placed in `chart/dashboards/` and the install script
picks them up automatically.

### Grafana default password
Changed from `devops` (source repo) to `admin` for golden-fleece since it's project-agnostic.
Anonymous auth is enabled so the password rarely matters in local dev.

### Prometheus scrape config
Replaced hardcoded job names with annotation-based pod scraping
(`prometheus.io/scrape: "true"`). The deployment template sets these annotations
automatically, so any golden-fleece deployed app gets scraped without config changes.

## Phase D decisions

### Helm template rendering strategy
The `.tmpl` files in `scaffold/helm/base/templates/` use Helm's Go template syntax
(`{{ .Values.x }}`), not golden-fleece's `{{VAR}}` syntax. `new-project.sh` copies them
raw instead of rendering through `sed`. Only `Chart.yaml`, `values.yaml`, and
`values-dev.yaml` are rendered since they contain golden-fleece placeholders.

### /tmp volume mount
The deployment template mounts an emptyDir at `/tmp` because `readOnlyRootFilesystem: true`
prevents writes. Many frameworks (Python, Java) write temp files there.

## Phase F decisions

### ArgoCD local repo source
The application.yaml.tmpl uses `https://kubernetes.default.svc` as repoURL which is a
placeholder. For local Kind dev, ArgoCD needs the repo-server to mount the project
directory or use a Git init container. The `/fleece:adopt` flow (Phase 7) should handle
this wiring dynamically based on whether there's a remote Git URL available.

## Not yet built

These items from DESIGN.md are not implemented yet:
- `core/targets/k3d/` — k3d target driver (bootstrap + teardown)
- `core/targets/existing/connect.sh` — existing cluster connector
- `core/stacks/registry/external/connect.sh` — external registry connector
- `core/stacks/observability/external/connect.sh` — external observability connector
- `core/stacks/gitops/external/connect.sh` — external ArgoCD connector
- `core/targets/kind/teardown.sh` — Kind cluster teardown (currently in Makefile)
- `docs/` — reference documentation
