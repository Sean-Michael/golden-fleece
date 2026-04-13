# Golden Fleece

A Claude Code plugin to go from a containerized app to a k8s deployment. This gives the agent a repeatable harness that closely mirrors a production k8s platform.

Agents can move fast, break things, and never have it leave your laptop. Discover your apps weaknesses before the platform team ever sees it.

## The Agentic Thesis

I got tired of spinning up the same infrastructure and instructing claude to use only my local cluster or build an image locally etc. I found that there was too much friction between the agent and safe local k8s development. 

The tools available for a local cluster are awesome, KIND is a great project and works flawlessly for this application. Combined with a local registry, the agent is now able to rapidly iterate on the source code + helm charts and deploy to a real Kubernetes cluster.

Another source of pain can be instrumentation, and this harness makes it easy by bundling the best (in my opinion) Observability solution out there: Grafana, with the full LGTM stack (Loki / Grafana / Tempo / Prometheus / Alloy) which enables the agent to live update and query the instrumented metrics.

Finally, it's helpful to know that your helm chart is setup in a way that allows for flexible deployment environments, with the full range of available Kubernetes patterns to take advantage of. The skills attempt to instill some best practices into the agent, so that a helm chart is not just generated, it's engineered for the specific app and deployment target.

## The Harness

- A local KIND cluster with a private registry and LGTM observability.
- A Helm chart the designed for the app's workload class.
- Live observability validation the agent queries Prometheus, Loki,
  and Tempo directly and won't declare the stack working until they
  return data.
- A `k8s-readiness.md` documents chart decisions and the
  production path: which values change between dev and prod, which
  external systems still need wiring, which prerequisites must exist
  before first deploy.
- **Opt-in ArgoCD**: enable when the `Application` manifest is itself
  an artifact you want to develop. Off by default.

## Install

I've set this up to follow the Claude plugin marketplace standards. 

After cloning the repository you may open claude code and run the following commands.

```
/plugin marketplace add Sean-Michael/golden-fleece
/plugin install golden-fleece@golden-fleece
/reload-plugins
```

Then in any project:

```
/fleece:adopt
```

## Commands

Here are the basic slash commands for your reference:

| Command          | What it does                                              |
| ---------------- | --------------------------------------------------------- |
| `/fleece:adopt`  | Full adoption: detect → classify → scaffold → shape → deploy → validate → report |
| `/fleece:up`     | Check what's running, bring up what's missing             |
| `/fleece:smoke`  | Run smoke checks (app health, registry, observability, and gitops if enabled) |
| `/fleece:status` | Show cluster, stacks, app, and observability status       |


More implementation details can be found in the docs:
 - [adopt-flow](docs/adopt-flow.md)
 - [stacks](docs/stacks.md)
 - [targets](docs/targets.md)

## Safety

Trust me when I say that I also get pretty queasy when I point an agent at anything 'infrastructure' especially cause my `kubectl` is usually pointed to something I wouldn't want ruined...

With that in mind I tried to make it clear to the agent that it should ONLY use the local context and make sure to explicitely state that for all of it's kubectl commands.

This is accomplished with two layers:

1. `agent/SKILL.md` instructs Claude never to target non-sandbox
   clusters and never to run `kubectl` without `--context`.
2. `core/safety/guard.sh` is sourced by every script. It pins
   `--context` to the Kind cluster from `golden-fleece.yaml` and
   hard-fails if the context server URL matches `eks`, `amazonaws`,
   `gke`, or `azmk8s`.

## License

Apache 2.0
