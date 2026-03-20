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

# Parse cluster name from golden-fleece.yaml (simple grep, no yq dependency)
_gf_cluster_name() {
  grep -A1 'cluster:' "${GF_CONFIG}" | grep 'name:' | head -1 | sed "s/.*name:[[:space:]]*//" | tr -d '"'
}

GF_CLUSTER_NAME="${GF_CLUSTER_NAME:-$(_gf_cluster_name)}"
GF_KIND_CONTEXT="kind-${GF_CLUSTER_NAME}"

# ── Safety gates ───────────────────────────────────────────────────

# Abort if the required Kind context doesn't exist
gf_require_context() {
  if ! kubectl config get-contexts "${GF_KIND_CONTEXT}" > /dev/null 2>&1; then
    echo "ERROR: kubectl context '${GF_KIND_CONTEXT}' not found."
    echo "       Run: ck8s up   (or: make kind-up)"
    exit 1
  fi
}

# Abort if the context points to a cloud cluster
gf_reject_cloud_context() {
  local server
  server=$(kubectl config view --context "${GF_KIND_CONTEXT}" \
    -o jsonpath="{.clusters[?(@.name==\"${GF_KIND_CONTEXT}\")].cluster.server}" 2>/dev/null || true)

  if echo "${server}" | grep -qiE "eks|amazonaws|azmk8s|googleapis|gke"; then
    echo "FATAL: Context '${GF_KIND_CONTEXT}' points to a cloud cluster. Aborting."
    echo "       golden-fleece only operates against local Kind clusters."
    exit 1
  fi
}

# ── Context-pinned aliases ─────────────────────────────────────────
# Use these in all scripts instead of bare kubectl/helm:
#   ${K} get pods -n argo
#   ${H} upgrade --install ...

K="kubectl --context ${GF_KIND_CONTEXT}"
H="helm --kube-context ${GF_KIND_CONTEXT}"

export GF_CLUSTER_NAME GF_KIND_CONTEXT K H
