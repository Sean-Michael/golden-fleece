# /fleece:status — Show Harness Status

Show the current state of the golden-fleece harness at a glance.

Read `golden-fleece.yaml` for the project configuration, then check:

1. **Cluster**: Is the Kind/k3d context available? Any nodes NotReady?
2. **Registry**: Is the registry container running? Can we reach it?
3. **App**: Is the app process running? Health endpoint responding?
4. **Pods**: What's running in the project namespace?
5. **Observability**: Are monitoring pods healthy?
6. **GitOps**: Is ArgoCD running? What's the app sync status?

Use kubectl commands to check live state. Present results as a clear table.
