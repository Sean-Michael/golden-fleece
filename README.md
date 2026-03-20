# Golden Fleece

> Skills and sandbox harness that turns Claude Code into a CKA — bridging the
> gap between a containerized app and a production-ready Kubernetes application.

`golden-fleece` is a Claude Code plugin and development framework that gives
any project a fully local Kubernetes environment with safety guardrails,
composable stacks (Argo Workflows, LGTM, ArgoCD), and an agentic session
harness for autonomous k8s-native development.

## How It Works

You have a Docker Compose app. You want it running in Kubernetes — with a Helm
chart, proper health probes, resource limits, Argo Workflows integration, and
full observability. `golden-fleece` gives Claude Code everything it needs to
get you there autonomously:

1. **A local KIND cluster** with a private registry and your chosen stacks
2. **Safety guardrails** that physically prevent Claude from touching any
   cluster other than the local sandbox
3. **A SKILL.md** that encodes CKA-level k8s development patterns
4. **An AUTONOMOUS-SESSION.md** template where you describe the task — Claude
   does the rest

## Quick Start

```bash
# 1. Add golden-fleece to your project (as a git submodule or copy)
git submodule add https://github.com/your-handle/golden-fleece

# 2. Copy and fill in the config
cp golden-fleece/scaffold/templates/golden-fleece.yaml.tmpl golden-fleece.yaml
# edit golden-fleece.yaml

# 3. Scaffold harness files into your project
bash golden-fleece/scaffold/new-project.sh

# 4. Bring up the cluster and app
make up

# 5. Verify everything is healthy
make smoke

# 6. Describe your task in AUTONOMOUS-SESSION.md, then start Claude Code
make session   # prints the autonomous session prompt
claude --dangerously-skip-permissions
```

## Stacks

Enable stacks in `golden-fleece.yaml`:

| Stack | What it gives you |
| --- | --- |
| `argo-workflows` | Workflow execution engine, UI at localhost:2746 |
| `argocd` | GitOps CD, ApplicationSet support |
| `lgtm` | Loki + Grafana + Tempo + Mimir + Alloy (full observability) |
| `cert-manager` | TLS certificate management |
| `external-secrets` | Secrets from AWS/Azure/GCP vaults |

## Safety Model

`golden-fleece` enforces two layers of cluster safety:

1. **SKILL.md guidance** — Claude is instructed never to target non-sandbox clusters
2. **kubectl wrapper** (`core/safety/kubectl-wrapper`) — physically intercepts
   all `kubectl` calls and injects `--context kind-<cluster>`, blocking any
   other context at the OS level

The `lgtm-install.sh` and other stack scripts also contain EKS/GKE/AKS guard
clauses that abort if the context server URL looks like a cloud endpoint.

## Project Structure

```bash
golden-fleece/
  core/
    cluster/          # KIND cluster bootstrap (template + script)
    registry/         # Local container registry setup
    safety/           # Guard library + kubectl wrapper
    stacks/           # Composable stack installers
      argo-workflows/
      argocd/
      lgtm/
      cert-manager/
      external-secrets/
  scaffold/
    templates/        # Project template files (Makefile, CLAUDE.md, etc.)
    new-project.sh    # ck8s init — scaffold into an existing project
  agent/
    SKILL.md          # The Claude Code skill
    hooks/            # pre-session health check
    commands/         # slash command implementations
  docs/
```

## The Development Loop

```txt
Edit code → verify app health → make image → make helm-install → observe pods → make smoke → repeat
```

For pure app work (no k8s behavior): skip the image/helm steps — the app runs
on host with hot-reload.

## License

Apache 2.0
