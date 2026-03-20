# hello-fastapi — Agent Guide

## Project Map

| Area | Key files | What lives here |
|------|-----------|-----------------|
| App | `app/` | Application source code |
| Config | `golden-fleece.yaml` | Harness configuration |
| Chart | `chart/` | Helm chart (deployment, service, HPA, PDB, etc.) |
| Skill | `golden-fleece/agent/SKILL.md` | K8s development rules and iteration loop |
| Stacks | `golden-fleece/core/stacks/` | Observability, GitOps, registry installers |

## Operating Rules

1. Read `golden-fleece/agent/SKILL.md` before any kubectl/helm/image operation
2. Never run kubectl without the correct `--context`
3. Never modify `compose.yaml` or production configs
4. Never commit or push in an autonomous session unless instructed
5. If stuck, write to `NOTES.md` and stop

## Development Loop

```
Edit code → verify health → make image → make helm-install → verify pods → make smoke
```

## Key Endpoints

- App: http://localhost:8000/healthz
- Cluster: `hello-fastapi-dev` (context: `kind-hello-fastapi-dev`)
- Registry: `localhost:5050`
