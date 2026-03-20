#!/usr/bin/env bash
# golden-fleece/agent/hooks/pre-session.sh
# Run before starting an autonomous Claude Code session.
# Verifies the harness is up and healthy — fast-fails with clear errors.
# Usage: bash golden-fleece/agent/hooks/pre-session.sh
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

source "${GF_DIR}/core/safety/guard.sh"

red()   { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
blue()  { printf "\033[34m%s\033[0m\n" "$*"; }

fail() { red "✗ $1"; echo "  Run: make up"; exit 1; }
pass() { green "✓ $1"; }

blue "==> golden-fleece pre-session checks"
blue "    Project: $(grep '^  name:' "${GF_CONFIG}" | head -1 | sed 's/.*name:[[:space:]]*//' | tr -d '"')"
blue "    Cluster: ${GF_KIND_CONTEXT}"

# ── Kind cluster ────────────────────────────────────────────────────

kubectl config get-contexts "${GF_KIND_CONTEXT}" > /dev/null 2>&1 \
  || fail "Kind cluster context '${GF_KIND_CONTEXT}' not found"
pass "Kind cluster context exists"

gf_reject_cloud_context
pass "Context is local (not a cloud cluster)"

# ── App health ──────────────────────────────────────────────────────

APP_HEALTH_URL=$(grep 'health_url:' "${GF_CONFIG}" | head -1 | sed 's/.*health_url:[[:space:]]*//' | tr -d '"')
if [ -n "${APP_HEALTH_URL}" ]; then
  curl -sf "${APP_HEALTH_URL}" > /dev/null 2>&1 \
    || fail "App not healthy at ${APP_HEALTH_URL}"
  pass "App is healthy (${APP_HEALTH_URL})"
fi

# ── Argo Workflows (if enabled) ─────────────────────────────────────

ARGO_ENABLED=$(grep -A5 'stacks:' "${GF_CONFIG}" | grep 'argo-workflows:' | grep -c 'true' || true)
if [ "${ARGO_ENABLED}" -gt 0 ]; then
  curl -sf "http://localhost:2746/api/v1/info" > /dev/null 2>&1 \
    || fail "Argo Workflows not reachable at http://localhost:2746"
  pass "Argo Workflows is reachable"
fi

# ── Safety: PATH has kubectl wrapper ────────────────────────────────

KUBECTL_PATH=$(which kubectl)
if echo "${KUBECTL_PATH}" | grep -q "golden-fleece"; then
  pass "kubectl wrapper is on PATH (context-locked)"
else
  echo "  NOTE: kubectl wrapper not on PATH — add golden-fleece/core/safety/ to PATH"
  echo "        or use 'kubectl --context ${GF_KIND_CONTEXT}' explicitly"
fi

echo ""
green "══════════════════════════════════════════"
green "  Harness is healthy — safe to start session"
green "══════════════════════════════════════════"
echo ""
echo "  Start session with:"
echo "    claude --dangerously-skip-permissions"
echo ""
echo "  Use the prompt from:"
echo "    make session   (or: cat AUTONOMOUS-SESSION.md)"
echo ""
