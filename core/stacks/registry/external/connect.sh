#!/usr/bin/env bash
# golden-fleece/core/stacks/registry/external/connect.sh
# Validate an external container registry and create imagePullSecret.
# Usage: GF_CONFIG=golden-fleece.yaml bash golden-fleece/core/stacks/registry/external/connect.sh
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

source "${GF_DIR}/core/safety/guard.sh"
gf_require_context

PROJECT_NAME=$(_gf_get name)
PROJECT_NS=$(grep 'namespace:' "${GF_CONFIG}" 2>/dev/null | tail -1 \
  | sed 's/.*namespace:[[:space:]]*//' | tr -d '"' | tr -d "'")
PROJECT_NS="${PROJECT_NS:-${PROJECT_NAME}}"

# Parse external registry config
REGISTRY_URL=$(grep -A10 'registry:' "${GF_CONFIG}" | grep 'url:' | head -1 \
  | sed 's/.*url:[[:space:]]*//' | tr -d '"' | tr -d "'")
REGISTRY_SECRET=$(grep -A10 'registry:' "${GF_CONFIG}" | grep 'secret:' | head -1 \
  | sed 's/.*secret:[[:space:]]*//' | tr -d '"' | tr -d "'")
REGISTRY_SECRET="${REGISTRY_SECRET:-registry-pull-secret}"

if [ -z "${REGISTRY_URL}" ]; then
  echo "ERROR: stacks.registry.url not set in golden-fleece.yaml"
  exit 1
fi

echo "==> Connecting to external registry"
echo "    URL:       ${REGISTRY_URL}"
echo "    Secret:    ${REGISTRY_SECRET}"
echo "    Namespace: ${PROJECT_NS}"

# ── Validate registry is reachable ────────────────────────────────
echo "==> Validating registry endpoint..."
if curl -sf "https://${REGISTRY_URL}/v2/" > /dev/null 2>&1 \
   || curl -sf "http://${REGISTRY_URL}/v2/" > /dev/null 2>&1; then
  echo "    Registry is reachable"
else
  echo "WARNING: Could not reach ${REGISTRY_URL}/v2/ — registry may require auth for catalog"
  echo "         Continuing anyway (push/pull will validate further)"
fi

# ── Check if imagePullSecret exists ───────────────────────────────
${K} create namespace "${PROJECT_NS}" --dry-run=client -o yaml | ${K} apply -f -

if ${K} get secret "${REGISTRY_SECRET}" -n "${PROJECT_NS}" > /dev/null 2>&1; then
  echo "    imagePullSecret '${REGISTRY_SECRET}' already exists"
else
  echo ""
  echo "    imagePullSecret '${REGISTRY_SECRET}' not found in namespace '${PROJECT_NS}'."
  echo "    Create it with:"
  echo ""
  echo "    kubectl create secret docker-registry ${REGISTRY_SECRET} \\"
  echo "      -n ${PROJECT_NS} \\"
  echo "      --docker-server=${REGISTRY_URL} \\"
  echo "      --docker-username=<user> \\"
  echo "      --docker-password=<token>"
  echo ""
fi

# ── Write config for other scripts ────────────────────────────────
mkdir -p "${PWD}/.golden-fleece"
cat > "${PWD}/.golden-fleece/registry.env" <<EOF
REGISTRY_TYPE=external
REGISTRY_URL=${REGISTRY_URL}
REGISTRY_SECRET=${REGISTRY_SECRET}
IMAGE_PREFIX=${REGISTRY_URL}/${PROJECT_NAME}
EOF
echo "    Wrote .golden-fleece/registry.env"

echo ""
echo "External registry configured. Update chart/values-dev.yaml:"
echo "  image.repository: ${REGISTRY_URL}/${PROJECT_NAME}"
