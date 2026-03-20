#!/usr/bin/env bash
# golden-fleece/core/targets/kind/teardown.sh
# Delete the Kind cluster and associated resources (registry container, docker network).
# Usage: GF_CONFIG=golden-fleece.yaml bash golden-fleece/core/targets/kind/teardown.sh
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

source "${GF_DIR}/core/safety/guard.sh"

echo "==> golden-fleece teardown"
echo "    Cluster: ${GF_CLUSTER_NAME}"

# ── Delete Kind cluster ───────────────────────────────────────────
if kind get clusters 2>/dev/null | grep -qw "${GF_CLUSTER_NAME}"; then
  echo "==> Deleting Kind cluster '${GF_CLUSTER_NAME}'..."
  kind delete cluster --name "${GF_CLUSTER_NAME}"
  echo "    Cluster deleted"
else
  echo "    Kind cluster '${GF_CLUSTER_NAME}' does not exist — nothing to delete"
fi

# ── Remove registry container ─────────────────────────────────────
REGISTRY_NAME="${GF_CLUSTER_NAME}-registry"
if docker inspect "${REGISTRY_NAME}" > /dev/null 2>&1; then
  echo "==> Removing registry container '${REGISTRY_NAME}'..."
  docker rm -f "${REGISTRY_NAME}" > /dev/null 2>&1 || true
  echo "    Registry removed"
fi

# ── Clean up generated artifacts ──────────────────────────────────
if [ -d "${PWD}/.golden-fleece" ]; then
  echo "==> Cleaning .golden-fleece/"
  rm -rf "${PWD}/.golden-fleece"
fi

echo ""
echo "Teardown complete. Run 'make kind-up' to recreate."
