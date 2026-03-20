# /fleece:up — Bring Up the Harness

Read `golden-fleece.yaml` and bring up everything it specifies:

1. Bootstrap the cluster target (kind/k3d/validate existing)
2. Set up the registry (if enabled)
3. Install observability stack (if enabled)
4. Install GitOps stack (if enabled)
5. Start the app (compose services + app process)

Run: `make up`

If any step fails, diagnose and fix before proceeding.
After everything is up, run `make smoke` to verify.
