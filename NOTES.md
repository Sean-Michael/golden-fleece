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
The old Makefile used simple `grep 'lgtm: true'` which matched the flat old schema. The new
nested schema (`stacks.observability.enabled: true` + `stacks.observability.type: lgtm`)
requires section-aware parsing. Using `awk` range patterns to read YAML sections portably
(works on macOS BSD awk and GNU awk).

### Registry port parsing
Old schema had `registry.port` at one nesting level. New schema nests it under
`stacks.registry.port`. The `setup.sh` parser greps for `port:` lines which is fragile
with the deeper nesting. Currently works because the registry port line is the most specific
match, but this should be made more robust in a future pass (e.g., use the guard.sh `_gf_get`
helper or a dedicated parser).

### Helm wrapper
DESIGN.md lists `core/safety/helm-wrapper` but it doesn't exist yet and nothing references
it in the current scripts. Not created in Phase A — should be added when helm-related commands
start enforcing context.

### Smoke test path
Makefile.tmpl previously referenced `golden-fleece/agent/hooks/smoke-test.sh` which never
existed. Updated to reference `$(GF_DIR)/core/smoke/lib.sh` per the DESIGN.md structure.
This file doesn't exist yet — it's a Phase B/C deliverable.

### Directories not yet populated
These directories from DESIGN.md exist only as part of the target structure and have no
files yet. They'll be populated in later phases:
- `core/targets/k3d/`
- `core/targets/existing/`
- `core/stacks/registry/external/`
- `core/stacks/observability/`
- `core/stacks/gitops/`
- `core/smoke/`
- `scaffold/helm/`
- `.claude-plugin/`
- `docs/`
