#!/usr/bin/env bash
# golden-fleece/core/stacks/gitops/external/connect.sh
# Validate an existing ArgoCD instance and create a project for the app.
# Usage: GF_CONFIG=golden-fleece.yaml bash golden-fleece/core/stacks/gitops/external/connect.sh
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

source "${GF_DIR}/core/safety/guard.sh"
gf_require_context

PROJECT_NAME=$(_gf_get name)
PROJECT_NS=$(grep 'namespace:' "${GF_CONFIG}" 2>/dev/null | tail -1 \
  | sed 's/.*namespace:[[:space:]]*//' | tr -d '"' | tr -d "'")
PROJECT_NS="${PROJECT_NS:-${PROJECT_NAME}}"

# Parse external gitops config
ARGOCD_URL=$(grep -A10 'gitops:' "${GF_CONFIG}" | grep 'url:' | head -1 \
  | sed 's/.*url:[[:space:]]*//' | tr -d '"' | tr -d "'")
ARGOCD_PROJECT=$(grep -A10 'gitops:' "${GF_CONFIG}" | grep 'project:' | head -1 \
  | sed 's/.*project:[[:space:]]*//' | tr -d '"' | tr -d "'")
ARGOCD_PROJECT="${ARGOCD_PROJECT:-default}"

if [ -z "${ARGOCD_URL}" ]; then
  echo "ERROR: stacks.gitops.url not set in golden-fleece.yaml"
  exit 1
fi

echo "==> Connecting to external ArgoCD"
echo "    URL:     ${ARGOCD_URL}"
echo "    Project: ${ARGOCD_PROJECT}"

# ── Validate ArgoCD is reachable ──────────────────────────────────
if curl -sf "${ARGOCD_URL}/api/version" > /dev/null 2>&1 \
   || curl -sfk "${ARGOCD_URL}/api/version" > /dev/null 2>&1; then
  ARGO_VERSION=$(curl -sfk "${ARGOCD_URL}/api/version" 2>/dev/null \
    | grep -o '"Version":"[^"]*"' | head -1 || echo "unknown")
  echo "    ArgoCD is reachable (${ARGO_VERSION})"
else
  echo "    WARNING: Could not reach ${ARGOCD_URL}/api/version"
  echo "    ArgoCD may require auth — try 'argocd login' first"
fi

# ── Write config for other scripts ────────────────────────────────
mkdir -p "${PWD}/.golden-fleece"
cat > "${PWD}/.golden-fleece/gitops.env" <<EOF
GITOPS_TYPE=external
ARGOCD_URL=${ARGOCD_URL}
ARGOCD_PROJECT=${ARGOCD_PROJECT}
EOF
echo "    Wrote .golden-fleece/gitops.env"

echo ""
echo "To create the ArgoCD Application, ensure you're logged in:"
echo "  argocd login ${ARGOCD_URL#https://} --sso"
echo "  argocd app create ${PROJECT_NAME} \\"
echo "    --project ${ARGOCD_PROJECT} \\"
echo "    --repo <your-git-url> \\"
echo "    --path chart/ \\"
echo "    --dest-server https://kubernetes.default.svc \\"
echo "    --dest-namespace ${PROJECT_NS} \\"
echo "    --values values-dev.yaml \\"
echo "    --sync-policy automated"
