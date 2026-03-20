# /fleece:adopt — Full Adoption Flow

You are running the golden-fleece adoption flow. This takes the current
project and makes it production-ready on Kubernetes — autonomously.

Read `golden-fleece/agent/SKILL.md` first for the full phase breakdown
and safety rules.

## Your Mission

Execute all 10 phases of the adopt flow in order:

0. **Questions** — Ask at most 3 questions (target, stacks, special notes)
1. **App Detection** — Read the repo, produce detection report
2. **Config Generation** — Generate `golden-fleece.yaml`, show for confirmation
3. **Scaffold** — Run `bash golden-fleece/scaffold/new-project.sh`
4. **Cluster + Stacks** — `make kind-up` (bootstrap + stacks)
5. **First Deploy** — `make image && make helm-install`, iterate until healthy
6. **Observability Validation** — Live Prometheus/Loki/Tempo queries
7. **GitOps Deploy** — ArgoCD sync (if enabled)
8. **Smoke Test** — `make smoke`
9. **Readiness Report** — Generate `k8s-readiness.md`

## Key Rules

- Do NOT skip phases. Each builds on the previous.
- Do NOT declare a phase complete until it actually passes.
- If a deploy fails, diagnose and fix before moving on.
- If observability queries return empty, the pipeline is broken — fix it.
- Write detection findings to `.golden-fleece/detection.yaml`.
- Show the user `golden-fleece.yaml` before proceeding past Phase 2.

## Success Criteria

You are done when:
- Pod is `1/1 Running` with no restarts
- Health endpoint returns 200
- Metrics visible in Prometheus (live query)
- Logs visible in Loki (live query)
- Traces visible in Tempo (live query) — if OTLP instrumented
- ArgoCD app is Healthy + Synced (if enabled)
- `make smoke` passes
- `k8s-readiness.md` is generated with observed values
