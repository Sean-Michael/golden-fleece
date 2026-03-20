#!/usr/bin/env bash
# golden-fleece/core/stacks/argo-workflows/install.sh
# Installs Argo Workflows into the project's Kind cluster.
# Safe to re-run — idempotent.
# Usage: bash golden-fleece/core/stacks/argo-workflows/install.sh
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

source "${GF_DIR}/core/safety/guard.sh"
gf_require_context
gf_reject_cloud_context

ARGO_VERSION="${ARGO_VERSION:-v3.6.5}"
ARGO_NS="argo"

echo "==> Installing Argo Workflows ${ARGO_VERSION}"
echo "    Context: ${GF_KIND_CONTEXT}"
echo "    Namespace: ${ARGO_NS}"

# Namespace
${K} create namespace "${ARGO_NS}" --dry-run=client -o yaml | ${K} apply -f -

# Install
${K} apply -n "${ARGO_NS}" \
  -f "https://github.com/argoproj/argo-workflows/releases/download/${ARGO_VERSION}/quick-start-minimal.yaml"

echo "==> Waiting for argo-server..."
${K} -n "${ARGO_NS}" rollout status deployment/argo-server --timeout=120s

# Patch to NodePort 30746 (mapped to host:2746 in kind-config)
${K} -n "${ARGO_NS}" patch svc argo-server --type=json \
  -p='[
    {"op":"replace","path":"/spec/type","value":"NodePort"},
    {"op":"replace","path":"/spec/ports/0/nodePort","value":30746}
  ]'

# auth-mode=server, secure=false, fix readiness probe scheme
${K} -n "${ARGO_NS}" patch deployment argo-server --type=json \
  -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/args","value":["server","--auth-mode=server","--secure=false"]},
    {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/scheme","value":"HTTP"}
  ]'

${K} -n "${ARGO_NS}" rollout status deployment/argo-server --timeout=120s

# ── Project WorkflowTemplates ───────────────────────────────────────
# Projects place their templates in hack/argo-templates/ (same convention).
# golden-fleece also ships stub templates for common patterns.

TEMPLATES_DIR="${PWD}/hack/argo-templates"
GF_STUB_TEMPLATES="${GF_DIR}/core/stacks/argo-workflows/templates"

if [ -d "${TEMPLATES_DIR}" ]; then
  echo "==> Applying project WorkflowTemplates from ${TEMPLATES_DIR}..."
  ${K} apply -f "${TEMPLATES_DIR}/"
fi

if [ -d "${GF_STUB_TEMPLATES}" ]; then
  echo "==> Applying golden-fleece stub WorkflowTemplates..."
  ${K} apply -f "${GF_STUB_TEMPLATES}/"
fi

${K} -n "${ARGO_NS}" rollout restart deployment/workflow-controller
${K} -n "${ARGO_NS}" rollout status deployment/workflow-controller --timeout=60s

echo ""
echo "✓ Argo Workflows ready"
echo "  UI:  http://localhost:2746"
echo "  API: http://localhost:2746/api/v1"
