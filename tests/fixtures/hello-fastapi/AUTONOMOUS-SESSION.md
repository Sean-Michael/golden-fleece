# Autonomous Development Session — hello-fastapi

Use this prompt to start a `--dangerously-skip-permissions` Claude Code session
that develops and tests the application end-to-end against the local Kind cluster.

## Prerequisites

Before starting the session, run once manually:

```bash
make up    # starts app + Kind cluster + enabled stacks
make smoke # verify the harness is healthy
```

## The Prompt

Copy everything below the line and use it as your initial prompt:

---

You are working on **hello-fastapi**: Minimal FastAPI test app for golden-fleece e2e testing

The codebase is at the current working directory.

Read `AGENTS.md` first for the project map and operating rules.
Read `golden-fleece/agent/SKILL.md` for k8s development rules and the iteration loop.

## Environment

A local dev harness is already running:
- **App**: http://localhost:8000/healthz (hot-reloads on file changes)
- **Kind cluster**: `hello-fastapi-dev` (context: `kind-hello-fastapi-dev`)
- **Registry**: `localhost:5050` (push here, pods pull from `hello-fastapi-dev-registry:5000`)
- **Argo Workflows**: http://localhost:2746 (if enabled)
- **Config**: sourced from `.env.dev`

## Safety Rules

- **NEVER run kubectl without `--context kind-hello-fastapi-dev`**
- **NEVER modify compose.yaml or production configs**
- **NEVER commit or push** — this is a development session
- All Argo API calls must go to `http://localhost:2746` only
- If the app crashes after a code change, check `make logs` and fix before continuing

## Your Task

<!-- ================================================================
     PROJECT-SPECIFIC: Replace this section with your actual task.
     Describe what Claude should build, the development loop, and
     the success criteria. See AUTONOMOUS-SESSION.md in the
     devops-platform-api project for a complete example.
     ================================================================ -->

[Describe the feature or task here]

### Development Loop

1. Read the relevant code to understand the current architecture
2. Implement the feature
3. After each meaningful change, verify:
   - `curl -sf http://localhost:8000/healthz` returns ok
   - If crashed, run `make logs` and fix
4. Test end-to-end:
   ```bash
   # Add your test commands here
   ```
5. Run smoke test: `make smoke`
6. If deploying to Kind:
   ```bash
   make image         # build + push
   make helm-install  # deploy
   ```

### Success Criteria

- [ ] [Define your success criteria here]
- [ ] `make smoke` passes
- [ ] App is healthy after changes
