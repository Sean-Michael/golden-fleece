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

### ArgoCD local dev strategy
`install.sh` auto-detects `git remote get-url origin`. Application is only created when a
real remote URL exists. For local dev without a remote, ArgoCD installs (validating GitOps
readiness) but deploys happen via `helm install`.

## E2E test findings (hello-fastapi, 2026-03-20)

### Bug 1: `_get port` matches wrong port in new-project.sh
The `_get` function does `grep "${1}:" config | head -1` which matched `port: 5050`
(registry port) instead of `port: 8000` (app port) because registry comes first in the
file. Fixed: parse `app.port` using an awk range pattern scoped to the `app:` section.

### Bug 2: `_get test_cmd` kills script on missing key
With `set -euo pipefail`, `grep` exits 1 when no line matches. `_get test_cmd` on a
config without `test_cmd:` kills the whole script silently. Fixed: added `|| true` to
the `_get` function and `2>/dev/null` to the inner grep.

### Bug 3: kind-config.yaml port mappings malformed
The sed-based template rendering for port mappings produced broken YAML — `\n` in sed
replacement strings doesn't work as expected on macOS, and the python3 extraction
preserved wrong indentation. Fixed: rewrote bootstrap.sh to generate the entire Kind
config in a heredoc python3 script that outputs valid YAML directly.

### Bug 4: setup.sh registry port matches app port
Same root cause as Bug 1. `grep 'port:' | tail -1` matched the last `port:` line in
the file which was `app.port`, not `stacks.registry.port`. Fixed: use awk range pattern
scoped to the `registry:` section.

### Bug 5: duplicate prometheus scrape job name
The prometheus helm chart ships a built-in `kubernetes-pods` scrape job. Our
`extraScrapeConfigs` also used the name `kubernetes-pods`, causing a config parse
error on startup. Fixed: renamed to `golden-fleece-pods`.

### Bug 6: ((PASSED++)) kills script when PASSED=0
With `set -e`, `((PASSED++))` returns exit code 1 when PASSED is 0 (because `((0))`
is falsy in bash arithmetic). The smoke test runner dies on the first `pass` call.
Fixed: use `PASSED=$((PASSED + 1))` instead.

### Bug 7: awk range matches start line as end line
The awk pattern `/^  registry:/,/^  [a-z]/` — both patterns match the same line
(`  registry:` starts with two spaces + lowercase letter). The range is one line.
All smoke checks and Makefile stack detection were affected. Fixed: replaced with
`grep -A5 'section:' | grep -q 'enabled:.*true'` which is simpler and portable.

### Bug 8: grep -c returns multiline output from kubectl exec
`kubectl exec ... | grep -c` can produce `0\n0` (two zeros on separate lines) when
stderr from kubectl leaks into the pipe. `[ "0\n0" -gt 0 ]` fails with "integer
expression expected". Fixed: use `grep -q` with `&& echo found || echo empty`.

### Loki instant query doesn't work for logs
The DESIGN.md shows `curl loki:3100/loki/api/v1/query` for log queries, but Loki
rejects instant queries for log data. Must use `query_range` endpoint.

### Root cause
Most config-parsing bugs stem from flat `grep` against nested YAML. The config has
multiple `port:`, `name:`, etc. keys at different nesting levels. The fix pattern is
`grep -A<N> 'section:'` to scope to the right section before extracting.

## Not yet built

- `core/targets/k3d/` — k3d target driver (bootstrap + teardown)
- `core/targets/existing/connect.sh` — existing cluster connector
