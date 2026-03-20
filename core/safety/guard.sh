#!/usr/bin/env bash
# golden-fleece/core/safety/guard.sh
# Source this in any script that touches kubectl or helm.
# Provides: gf_require_context, gf_reject_cloud_context, K (kubectl alias), H (helm alias)
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/../../core/safety/guard.sh"
#   gf_require_context
#   ${K} get pods -n my-namespace

set -euo pipefail

# ── Resolve config ─────────────────────────────────────────────────
GF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

# Parse values from golden-fleece.yaml (simple grep, no yq dependency)
_gf_get() {
  grep "${1}:" "${GF_CONFIG}" 2>/dev/null | head -1 \
    | sed "s/.*${1}:[[:space:]]*//" | tr -d '"' | tr -d "'"
}

_gf_target_type() {
  local t
  t=$(grep -A1 '^target:' "${GF_CONFIG}" 2>/dev/null | grep 'type:' | head -1 \
    | sed 's/.*type:[[:space:]]*//' | tr -d '"' | tr -d "'")
  echo "${t:-kind}"
}

_gf_cluster_name() {
  # Try new schema (target.cluster_name) first, fall back to old (cluster.name)
  local name
  name=$(grep 'cluster_name:' "${GF_CONFIG}" 2>/dev/null | head -1 \
    | sed 's/.*cluster_name:[[:space:]]*//' | tr -d '"' | tr -d "'")
  if [ -z "${name}" ]; then
    name=$(grep -A1 'cluster:' "${GF_CONFIG}" 2>/dev/null | grep 'name:' | head -1 \
      | sed "s/.*name:[[:space:]]*//" | tr -d '"')
  fi
  echo "${name}"
}

_gf_resolve_context() {
  local target_type="$1" cluster_name="$2"
  case "${target_type}" in
    kind)     echo "kind-${cluster_name}" ;;
    k3d)      echo "k3d-${cluster_name}" ;;
    existing)
      # For existing clusters, read the context name directly from config
      local ctx
      ctx=$(grep -A5 '^target:' "${GF_CONFIG}" 2>/dev/null | grep 'context:' | head -1 \
        | sed 's/.*context:[[:space:]]*//' | tr -d '"' | tr -d "'")
      echo "${ctx:-${cluster_name}}"
      ;;
    *)        echo "kind-${cluster_name}" ;;
  esac
}

GF_TARGET_TYPE="${GF_TARGET_TYPE:-$(_gf_target_type)}"
GF_CLUSTER_NAME="${GF_CLUSTER_NAME:-$(_gf_cluster_name)}"
GF_CONTEXT="${GF_CONTEXT:-$(_gf_resolve_context "${GF_TARGET_TYPE}" "${GF_CLUSTER_NAME}")}"
# Keep GF_KIND_CONTEXT as alias for backward compat
GF_KIND_CONTEXT="${GF_CONTEXT}"

# ── Safety gates ───────────────────────────────────────────────────

# Abort if the required context doesn't exist
gf_require_context() {
  if ! kubectl config get-contexts "${GF_CONTEXT}" > /dev/null 2>&1; then
    echo "ERROR: kubectl context '${GF_CONTEXT}' not found."
    echo "       Run: ck8s up   (or: make kind-up)"
    exit 1
  fi
}

# Abort if the context points to a cloud cluster
gf_reject_cloud_context() {
  local server
  server=$(kubectl config view --context "${GF_CONTEXT}" \
    -o jsonpath="{.clusters[?(@.name==\"${GF_CONTEXT}\")].cluster.server}" 2>/dev/null || true)

  if echo "${server}" | grep -qiE "eks|amazonaws|azmk8s|googleapis|gke"; then
    echo "FATAL: Context '${GF_CONTEXT}' points to a cloud cluster (${server}). Aborting."
    echo "       golden-fleece refuses to target managed cloud clusters."
    exit 1
  fi
}

# ── Context-pinned aliases ─────────────────────────────────────────
# Use these in all scripts instead of bare kubectl/helm:
#   ${K} get pods -n argo
#   ${H} upgrade --install ...

K="kubectl --context ${GF_CONTEXT}"
H="helm --kube-context ${GF_CONTEXT}"

export GF_TARGET_TYPE GF_CLUSTER_NAME GF_CONTEXT GF_KIND_CONTEXT K H
