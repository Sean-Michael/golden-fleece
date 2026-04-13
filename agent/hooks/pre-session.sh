#!/usr/bin/env bash
# golden-fleece/agent/hooks/pre-session.sh
# Advisory status check for the golden-fleece harness.
# Always exits 0 so the agent can read the status and self-heal — EXCEPT
# when the cluster context points at a cloud cluster (hard safety fail).
# Usage: bash golden-fleece/agent/hooks/pre-session.sh

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

# guard.sh sets `set -euo pipefail` when sourced. We need it for GF_CONTEXT
# resolution, but then we disable `-e` so individual check failures (missing
# context, curl non-zero) do NOT abort the script. Each check reports
# OK/MISSING/UNREACHABLE and the final status block is always printed.
# shellcheck source=../../core/safety/guard.sh
source "${GF_DIR}/core/safety/guard.sh"
set +e

red()    { printf "\033[31m%s\033[0m\n" "$*"; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
blue()   { printf "\033[34m%s\033[0m\n" "$*"; }

_project_name() {
  grep -A3 '^project:' "${GF_CONFIG}" 2>/dev/null | grep 'name:' | head -1 \
    | sed 's/.*name:[[:space:]]*//' | tr -d '"' | tr -d "'"
}

# Each check sets a status variable to one of the tokens in the status
# block (OK | MISSING | UNREACHABLE | DISABLED | N/A | BLOCKED | LOCAL |
# ON_PATH | NOT_ON_PATH).
CLUSTER_CONTEXT_STATUS="MISSING"
CLUSTER_CLOUD_STATUS="LOCAL"
APP_HEALTH_STATUS="N/A"
KUBECTL_WRAPPER_STATUS="NOT_ON_PATH"

PROJECT_NAME="$(_project_name)"

blue "==> golden-fleece pre-session status"
blue "    Project: ${PROJECT_NAME:-<unknown>}"
blue "    Context: ${GF_CONTEXT}"
echo ""

# ── Cluster context ────────────────────────────────────────────────
if kubectl config get-contexts "${GF_CONTEXT}" > /dev/null 2>&1; then
  CLUSTER_CONTEXT_STATUS="OK"
else
  CLUSTER_CONTEXT_STATUS="MISSING"
fi

# ── Cloud-cluster safety gate ──────────────────────────────────────
# This is the ONE hard fail in this script. Safety rule, not health check.
if [ "${CLUSTER_CONTEXT_STATUS}" = "OK" ]; then
  SERVER_URL=$(kubectl config view --context "${GF_CONTEXT}" \
    -o jsonpath="{.clusters[?(@.name==\"${GF_CONTEXT}\")].cluster.server}" 2>/dev/null || true)
  if echo "${SERVER_URL}" | grep -qiE "eks|amazonaws|azmk8s|googleapis|gke"; then
    CLUSTER_CLOUD_STATUS="BLOCKED"
    red "FATAL: Context '${GF_CONTEXT}' points to a cloud cluster (${SERVER_URL})."
    red "       golden-fleece refuses to target managed cloud clusters."
    exit 1
  fi
  CLUSTER_CLOUD_STATUS="LOCAL"
fi

# ── App health ─────────────────────────────────────────────────────
APP_HEALTH_URL=$(grep 'health_url:' "${GF_CONFIG}" 2>/dev/null | head -1 \
  | sed 's/.*health_url:[[:space:]]*//' | tr -d '"' | tr -d "'")
if [ -n "${APP_HEALTH_URL}" ]; then
  if curl -sf "${APP_HEALTH_URL}" > /dev/null 2>&1; then
    APP_HEALTH_STATUS="OK"
  else
    APP_HEALTH_STATUS="UNREACHABLE"
  fi
else
  APP_HEALTH_STATUS="N/A"
fi

# ── kubectl wrapper on PATH? ───────────────────────────────────────
KUBECTL_PATH=$(which kubectl 2>/dev/null || echo "")
if echo "${KUBECTL_PATH}" | grep -q "golden-fleece"; then
  KUBECTL_WRAPPER_STATUS="ON_PATH"
else
  KUBECTL_WRAPPER_STATUS="NOT_ON_PATH"
fi

# ── Derive overall status + next action ────────────────────────────
OVERALL_STATUS="READY"
NEXT_ACTION="ready"

if [ "${CLUSTER_CONTEXT_STATUS}" != "OK" ]; then
  OVERALL_STATUS="NEEDS_BOOTSTRAP"
  NEXT_ACTION="run /fleece:up (cluster missing)"
elif [ "${APP_HEALTH_STATUS}" = "UNREACHABLE" ]; then
  OVERALL_STATUS="NEEDS_DEPLOY"
  NEXT_ACTION="run /fleece:up (app not healthy)"
fi

# ── Colored helper for each line ──────────────────────────────────
_color_for() {
  case "$1" in
    OK|LOCAL|ON_PATH|DISABLED|N/A) green "$1" ;;
    MISSING|UNREACHABLE|BLOCKED|NOT_ON_PATH) yellow "$1" ;;
    *) echo "$1" ;;
  esac
}

printf "    cluster_context: %-40s [" "${GF_CONTEXT}"
_color_for "${CLUSTER_CONTEXT_STATUS}" | tr -d '\n'
echo "]"

printf "    cluster_cloud:   %-40s [" "-"
_color_for "${CLUSTER_CLOUD_STATUS}" | tr -d '\n'
echo "]"

printf "    app_health:      %-40s [" "${APP_HEALTH_URL:-<none>}"
_color_for "${APP_HEALTH_STATUS}" | tr -d '\n'
echo "]"

printf "    kubectl_wrapper: %-40s [" "${KUBECTL_PATH:-<none>}"
_color_for "${KUBECTL_WRAPPER_STATUS}" | tr -d '\n'
echo "]"

echo ""
case "${OVERALL_STATUS}" in
  READY)           green "    status: READY" ;;
  NEEDS_BOOTSTRAP) yellow "    status: NEEDS_BOOTSTRAP" ;;
  NEEDS_DEPLOY)    yellow "    status: NEEDS_DEPLOY" ;;
esac
echo   "    next:   ${NEXT_ACTION}"
echo ""

exit 0
