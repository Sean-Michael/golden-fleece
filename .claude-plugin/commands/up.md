# /fleece:up — Self-Healing Bring-Up

Check what's actually running, then bring up whatever is missing. Do NOT
reflexively run `make up` — that re-does work. Inspect first, act
surgically.

Read `golden-fleece.yaml` for the target cluster name, enabled stacks,
registry port, and namespace.

## Steps

1. **Cluster context** — does `kind-<cluster>` exist in `kubectl config get-contexts`?
   If missing → `GF_CONFIG=./golden-fleece.yaml bash golden-fleece/core/targets/kind/bootstrap.sh`

2. **Registry container** — does `docker ps --filter name=<cluster>-registry` show a running container?
   If missing → `GF_CONFIG=./golden-fleece.yaml bash golden-fleece/core/stacks/registry/kind/setup.sh`

3. **Observability stack** (if `stacks.observability.enabled: true`) — is `deploy/grafana -n monitoring` ready?
   If missing → `GF_CONFIG=./golden-fleece.yaml bash golden-fleece/core/stacks/observability/lgtm/install.sh`

4. **GitOps stack** (if `stacks.gitops.enabled: true`) — is `deploy/argocd-server -n argocd` ready?
   If missing → `GF_CONFIG=./golden-fleece.yaml bash golden-fleece/core/stacks/gitops/argocd/install.sh`

5. **App pod** — is the Helm release installed and pods ready in the project namespace?
   If missing or unhealthy → `make image && make helm-install`

6. **Verify** — run `make smoke`. Investigate and fix anything that fails.

## Notes

- Each script is idempotent. Re-running a healthy one is safe but wastes time.
- If `agent/hooks/pre-session.sh` has already been run, its status block
  tells you exactly which of the above are `OK` vs `MISSING` — use that
  instead of re-checking everything.
- Do not abort on a single failure. Diagnose, fix, retry, and keep going.
