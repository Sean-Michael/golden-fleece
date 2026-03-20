#!/usr/bin/env bash
# golden-fleece/agent/commands/status.sh
# Quick status overview of the harness
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

source "${GF_DIR}/core/safety/guard.sh"

PROJECT_NAME=$(_gf_get name)
PROJECT_NS=$(grep 'namespace:' "${GF_CONFIG}" 2>/dev/null | tail -1 \
  | sed 's/.*namespace:[[:space:]]*//' | tr -d '"' | tr -d "'")
PROJECT_NS="${PROJECT_NS:-${PROJECT_NAME}}"

echo "==> golden-fleece status"
echo "    Project:   ${PROJECT_NAME}"
echo "    Target:    ${GF_TARGET_TYPE}"
echo "    Context:   ${GF_CONTEXT}"
echo ""

# Cluster
echo "── Cluster ──"
if kubectl config get-contexts "${GF_CONTEXT}" > /dev/null 2>&1; then
  echo "  Context: OK"
  ${K} get nodes 2>/dev/null || echo "  Nodes: not reachable"
else
  echo "  Context: NOT FOUND"
fi
echo ""

# App namespace pods
echo "── Pods (${PROJECT_NS}) ──"
${K} get pods -n "${PROJECT_NS}" 2>/dev/null || echo "  No pods or namespace not found"
echo ""

# Registry
REGISTRY_PORT=$(grep -A5 'registry:' "${GF_CONFIG}" | grep 'port:' | head -1 \
  | sed 's/.*port:[[:space:]]*//' | tr -d ' ')
REGISTRY_PORT="${REGISTRY_PORT:-5050}"
echo "── Registry ──"
if curl -sf "http://localhost:${REGISTRY_PORT}/v2/" > /dev/null 2>&1; then
  echo "  localhost:${REGISTRY_PORT}: OK"
else
  echo "  localhost:${REGISTRY_PORT}: NOT REACHABLE"
fi
echo ""

# Monitoring
echo "── Monitoring ──"
${K} get pods -n monitoring 2>/dev/null || echo "  Not installed"
echo ""

# ArgoCD
echo "── ArgoCD ──"
${K} get pods -n argocd -l app.kubernetes.io/name=argocd-server 2>/dev/null || echo "  Not installed"
echo ""
