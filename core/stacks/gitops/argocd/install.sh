#!/usr/bin/env bash
# golden-fleece/core/stacks/gitops/argocd/install.sh
# Installs ArgoCD into the cluster and exposes the UI via NodePort.
# Creates the ArgoCD Application only if a git remote is available.
# Idempotent — safe to re-run.
# Usage: GF_CONFIG=golden-fleece.yaml bash golden-fleece/core/stacks/gitops/argocd/install.sh
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

source "${GF_DIR}/core/safety/guard.sh"
gf_require_context
gf_reject_cloud_context

ARGOCD_NS="argocd"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.14.11}"
ARGOCD_NODEPORT="${ARGOCD_NODEPORT:-30443}"

PROJECT_NAME=$(_gf_get name)
PROJECT_NS=$(grep 'namespace:' "${GF_CONFIG}" 2>/dev/null | tail -1 \
  | sed 's/.*namespace:[[:space:]]*//' | tr -d '"' | tr -d "'")
PROJECT_NS="${PROJECT_NS:-${PROJECT_NAME}}"
CHART_DIR=$(grep 'chart_dir:' "${GF_CONFIG}" 2>/dev/null | head -1 \
  | sed 's/.*chart_dir:[[:space:]]*//' | tr -d '"' | tr -d "'")
CHART_DIR="${CHART_DIR:-./chart}"

echo "==> Installing ArgoCD ${ARGOCD_VERSION}"
echo "    Context:   ${GF_CONTEXT}"
echo "    Namespace: ${ARGOCD_NS}"
echo "    Project:   ${PROJECT_NAME}"

# ── Install ArgoCD ────────────────────────────────────────────────
${K} create namespace "${ARGOCD_NS}" --dry-run=client -o yaml | ${K} apply -f -

echo "==> Applying ArgoCD manifests..."
${K} apply -n "${ARGOCD_NS}" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Waiting for argocd-server..."
${K} -n "${ARGOCD_NS}" rollout status deployment/argocd-server --timeout=180s

# ── Expose UI via NodePort ────────────────────────────────────────
echo "==> Patching argocd-server to NodePort ${ARGOCD_NODEPORT}..."
${K} -n "${ARGOCD_NS}" patch svc argocd-server --type=json \
  -p="[
    {\"op\":\"replace\",\"path\":\"/spec/type\",\"value\":\"NodePort\"},
    {\"op\":\"replace\",\"path\":\"/spec/ports/0/nodePort\",\"value\":${ARGOCD_NODEPORT}}
  ]"

# ── Disable TLS on argocd-server for local dev ────────────────────
${K} -n "${ARGOCD_NS}" patch deployment argocd-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]' \
  2>/dev/null || true
${K} -n "${ARGOCD_NS}" rollout status deployment/argocd-server --timeout=120s

# ── Create ArgoCD AppProject scoped to the app namespace ──────────
echo "==> Creating ArgoCD project '${PROJECT_NAME}'..."
${K} apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: ${PROJECT_NAME}
  namespace: ${ARGOCD_NS}
spec:
  description: "golden-fleece project for ${PROJECT_NAME}"
  sourceRepos:
    - '*'
  destinations:
    - namespace: ${PROJECT_NS}
      server: https://kubernetes.default.svc
    - namespace: ${ARGOCD_NS}
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
EOF

# ── Detect git remote for Application creation ────────────────────
REPO_URL=$(git remote get-url origin 2>/dev/null || true)

if [ -n "${REPO_URL}" ]; then
  echo "==> Git remote detected: ${REPO_URL}"
  echo "==> Creating ArgoCD application '${PROJECT_NAME}'..."
  TEMPLATE_FILE="${GF_DIR}/core/stacks/gitops/argocd/application.yaml.tmpl"
  sed \
    -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
    -e "s|{{PROJECT_NS}}|${PROJECT_NS}|g" \
    -e "s|{{CHART_DIR}}|${CHART_DIR}|g" \
    -e "s|{{ARGOCD_NS}}|${ARGOCD_NS}|g" \
    -e "s|{{REPO_URL}}|${REPO_URL}|g" \
    "${TEMPLATE_FILE}" | ${K} apply -f -
  ARGOCD_APP_STATUS="created (syncing from ${REPO_URL})"
else
  echo ""
  echo "    No git remote found — skipping ArgoCD Application creation."
  echo "    ArgoCD is installed and the project is configured."
  echo "    Use 'helm install' for local iteration."
  echo "    When you push to a remote, re-run this script to create the Application."
  ARGOCD_APP_STATUS="not created (no git remote — use helm install for local dev)"
fi

# ── Get initial admin password ────────────────────────────────────
ADMIN_PASS=$(${K} -n "${ARGOCD_NS}" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "<not yet available>")

echo ""
echo "============================================================"
echo "  ArgoCD Ready"
echo "============================================================"
echo ""
echo "  UI:       https://localhost:${ARGOCD_NODEPORT}"
echo "  Login:    admin / ${ADMIN_PASS}"
echo ""
echo "  Project:  ${PROJECT_NAME} (scoped to namespace ${PROJECT_NS})"
echo "  App:      ${ARGOCD_APP_STATUS}"
echo ""
echo "  CLI:"
echo "    argocd login localhost:${ARGOCD_NODEPORT} --insecure --username admin --password '${ADMIN_PASS}'"
echo "    argocd app get ${PROJECT_NAME}"
echo ""
