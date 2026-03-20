#!/usr/bin/env bash
# golden-fleece/core/cluster/bootstrap.sh
# Idempotent Kind cluster creation from golden-fleece.yaml config.
# Usage: bash golden-fleece/core/cluster/bootstrap.sh
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

source "${GF_DIR}/core/safety/guard.sh"

echo "==> golden-fleece cluster bootstrap"
echo "    Cluster: ${GF_CLUSTER_NAME}"
echo "    Context: ${GF_KIND_CONTEXT}"
echo "    Config:  ${GF_CONFIG}"

# ── Generate kind-config.yaml from template + golden-fleece.yaml ───

GENERATED_CONFIG="${PWD}/.golden-fleece/kind-config.yaml"
mkdir -p "$(dirname "${GENERATED_CONFIG}")"

# Build port mappings block from golden-fleece.yaml
PORT_MAPPINGS=""

# Always add Argo Workflows port if stack is enabled
ARGO_ENABLED=$(grep -A5 'stacks:' "${GF_CONFIG}" | grep 'argo-workflows:' | grep -c 'true' || true)
if [ "${ARGO_ENABLED}" -gt 0 ]; then
  PORT_MAPPINGS+="      - containerPort: 30746\n        hostPort: 2746\n        protocol: TCP\n"
fi

# Add project-defined ports
while IFS= read -r line; do
  PORT_MAPPINGS+="      ${line}\n"
done < <(python3 -c "
import sys, re
config = open('${GF_CONFIG}').read()
ports_section = re.search(r'ports:(.*?)(?=\n\S|\Z)', config, re.DOTALL)
if ports_section:
    print(ports_section.group(1).strip())
" 2>/dev/null || true)

# Render template
sed \
  -e "s/{{GF_CLUSTER_NAME}}/${GF_CLUSTER_NAME}/g" \
  -e "s/{{GF_PORT_MAPPINGS}}/${PORT_MAPPINGS}/g" \
  "${GF_DIR}/core/cluster/kind-config.yaml.tmpl" > "${GENERATED_CONFIG}"

# ── Create cluster if needed ────────────────────────────────────────

if kind get clusters 2>/dev/null | grep -qw "${GF_CLUSTER_NAME}"; then
  echo "==> Cluster '${GF_CLUSTER_NAME}' already exists — skipping create"
else
  echo "==> Creating Kind cluster '${GF_CLUSTER_NAME}'..."
  kind create cluster --config "${GENERATED_CONFIG}"
  echo "✓ Cluster created"
fi

gf_reject_cloud_context

echo "✓ Cluster '${GF_CLUSTER_NAME}' is ready (context: ${GF_KIND_CONTEXT})"
