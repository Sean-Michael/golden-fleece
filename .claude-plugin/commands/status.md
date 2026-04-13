# /fleece:status — Show Harness Status

Show the current state of the harness at a glance. Read
`golden-fleece.yaml` first to know which stacks are enabled, then
check only those:

1. **Cluster** — is the Kind context available? Any nodes `NotReady`?
2. **Registry** — is the `<cluster>-registry` container running and reachable?
3. **App** — is the host app process running? Health endpoint responding?
4. **Pods** — what's running in the project namespace?
5. **Observability** (if enabled) — are pods in `monitoring` healthy?
6. **GitOps** (if enabled) — is ArgoCD running? App sync status?

Use `${K}` (or `kubectl --context kind-<cluster>`) for live checks.
Present the results as a compact table.
