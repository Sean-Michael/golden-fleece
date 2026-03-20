---
name: golden-fleece-k8s-dev
description: >
  Load this skill when developing a Kubernetes-native application using the
  golden-fleece harness. Triggers when: the project has a golden-fleece.yaml,
  the task involves building/deploying to a local Kind cluster, working with
  Helm charts, pushing images to a local registry, or developing against Argo
  Workflows. Also triggers for any kubectl, helm, or container registry
  operations in a golden-fleece project.
---

# Golden Fleece — K8s Development Skill

You are operating inside a **golden-fleece** development harness. This gives
you a fully local Kubernetes environment to develop against. You have the
skills of a Certified Kubernetes Administrator (CKA) and should use them.

## Environment

Read `golden-fleece.yaml` in the project root to understand this project's
specific configuration: cluster name, enabled stacks, registry port, app
start command, and health URL.

The standard endpoints (verify against golden-fleece.yaml):
- **App**: `{{APP_HEALTH_URL}}` (hot-reloads on file changes)
- **Argo Workflows**: `http://localhost:2746` (if argo-workflows stack enabled)
- **Registry**: `localhost:{{REGISTRY_PORT}}` (push here, pods pull from `{{CLUSTER_NAME}}-registry:5000`)
- **Grafana**: port-forward `svc/grafana` in `monitoring` namespace (if lgtm stack enabled)

## Safety Rules — NON-NEGOTIABLE

These are hard rules, not suggestions:

1. **NEVER run `kubectl` without `--context kind-{{CLUSTER_NAME}}`** — or use
   the `K=` variable from the Makefile which pre-pins this. In this session,
   `kubectl` on PATH is already wrapped to enforce the right context.

2. **NEVER modify `compose.yaml` or production configs** — only `compose.dev.yaml`
   and `golden-fleece.yaml` are safe to edit.

3. **NEVER `git push` or `git commit`** in an autonomous session unless
   explicitly instructed.

4. **NEVER target a cloud cluster** — if you see `eks`, `gke`, `aks`, or
   `amazonaws` in a cluster URL, stop immediately and report it.

5. **ALL Argo API calls go to `http://localhost:2746`** — never a remote URL.

## Development Loop

This is the golden-fleece iteration cycle for k8s-native development:

```
1. Edit source code
   ↓
2. Verify app is healthy (curl {{APP_HEALTH_URL}})
   ↓  (if broken: check logs, fix, repeat)
3. make image          ← build + push to local registry
   ↓
4. make helm-install   ← Helm upgrade into Kind cluster
   ↓
5. Verify pod is running and healthy in cluster
   kubectl -n {{PROJECT_NAME}} get pods
   kubectl -n {{PROJECT_NAME}} logs -l app={{PROJECT_NAME}} --tail=50
   ↓
6. Test the feature end-to-end
   ↓
7. make smoke          ← verify nothing regressed
   ↓
8. Repeat
```

For pure app development (not testing k8s behavior), steps 3-5 can be skipped
— the app runs on host with hot-reload. Only go through the full loop when:
- Testing Helm chart changes
- Testing k8s-specific behavior (health probes, resource limits, env injection)
- Testing Argo Workflows integration
- Testing the deployed image specifically

## kubectl Patterns

Always use context-pinned kubectl. In scripts, use the `K` variable:
```bash
K="kubectl --context kind-{{CLUSTER_NAME}}"
${K} get pods -n {{PROJECT_NAME}}
${K} logs -n argo -l workflows.argoproj.io/workflow=<name>
${K} describe pod -n {{PROJECT_NAME}} <pod-name>
```

In ad-hoc commands during a session, `kubectl` on PATH is already wrapped —
you can use it directly.

## Helm Chart Conventions

The project Helm chart lives in `chart/`. Standard structure:
- `chart/Chart.yaml` — chart metadata
- `chart/values.yaml` — production defaults
- `chart/values-dev.yaml` — local Kind overrides (image from local registry,
  reduced resources, no TLS, debug flags)
- `chart/templates/` — k8s manifests

When editing the chart, always verify with:
```bash
helm template {{PROJECT_NAME}} ./chart -f chart/values-dev.yaml | kubectl apply --dry-run=client -f -
```

## Image and Registry

- Push to: `localhost:{{REGISTRY_PORT}}/{{PROJECT_NAME}}:dev`
- Pods pull from: `{{CLUSTER_NAME}}-registry:5000/{{PROJECT_NAME}}:dev`
- `imagePullPolicy: Always` in `values-dev.yaml` ensures pods pick up new pushes

Quick image cycle:
```bash
make image          # build + push
kubectl -n {{PROJECT_NAME}} rollout restart deployment/{{PROJECT_NAME}}
kubectl -n {{PROJECT_NAME}} rollout status deployment/{{PROJECT_NAME}}
```

## Argo Workflows (if enabled)

WorkflowTemplates live in `hack/argo-templates/`. Apply with:
```bash
make argo-templates   # or: ${K} apply -f hack/argo-templates/
```

Submit a workflow directly for testing:
```bash
curl -X POST http://localhost:2746/api/v1/workflows/<namespace>/submit \
  -H "Content-Type: application/json" \
  -d '{"resourceKind":"WorkflowTemplate","resourceName":"<name>","submitOptions":{"parameters":["key=value"]}}'
```

Check workflow status:
```bash
curl -s http://localhost:2746/api/v1/workflows/<namespace> | \
  python3 -c "import json,sys; [print(w['metadata']['name'], w['status'].get('phase','?')) for w in json.load(sys.stdin).get('items',[])]"
```

## When Stuck

Write your concern to `NOTES.md`:
- What you were trying to do
- What went wrong
- What options you see

Then stop and wait for review. Do not hack around architectural issues.
Do not guess at cluster state — use `kubectl` to observe it directly.
