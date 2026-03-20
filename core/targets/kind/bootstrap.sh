#!/usr/bin/env bash
# golden-fleece/core/targets/kind/bootstrap.sh
# Idempotent Kind cluster creation from golden-fleece.yaml config.
# Usage: bash golden-fleece/core/targets/kind/bootstrap.sh
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

source "${GF_DIR}/core/safety/guard.sh"

echo "==> golden-fleece cluster bootstrap"
echo "    Cluster: ${GF_CLUSTER_NAME}"
echo "    Context: ${GF_KIND_CONTEXT}"
echo "    Config:  ${GF_CONFIG}"

# ── Generate kind-config.yaml from golden-fleece.yaml ─────────────

GENERATED_CONFIG="${PWD}/.golden-fleece/kind-config.yaml"
mkdir -p "$(dirname "${GENERATED_CONFIG}")"

# Use python3 to parse the ports section and generate valid Kind config YAML
python3 - "${GF_CONFIG}" "${GF_CLUSTER_NAME}" "${GENERATED_CONFIG}" <<'PYEOF'
import sys, re, os

config_path, cluster_name, output_path = sys.argv[1], sys.argv[2], sys.argv[3]
config = open(config_path).read()

# Parse port mappings from target.ports
port_lines = []

# Check for argo-workflows
if re.search(r'argo-workflows:\s*true', config):
    port_lines.append("      - containerPort: 30746")
    port_lines.append("        hostPort: 2746")
    port_lines.append("        protocol: TCP")

# Parse target.ports section
ports_match = re.search(r'^  ports:\s*\n((?:\s+-.*\n|\s+\w+.*\n)*)', config, re.MULTILINE)
if ports_match:
    ports_block = ports_match.group(1)
    # Find all port mapping entries
    entries = re.findall(
        r'-\s*containerPort:\s*(\d+)\s*\n\s*hostPort:\s*(\d+)(?:\s*\n\s*protocol:\s*(\w+))?',
        ports_block
    )
    for container_port, host_port, protocol in entries:
        protocol = protocol or "TCP"
        port_lines.append(f"      - containerPort: {container_port}")
        port_lines.append(f"        hostPort: {host_port}")
        port_lines.append(f"        protocol: {protocol}")

port_block = "\n".join(port_lines) if port_lines else "      []"

kind_config = f"""kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: {cluster_name}
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = "/etc/containerd/certs.d"
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
{port_block}
"""

with open(output_path, 'w') as f:
    f.write(kind_config)
PYEOF

echo "    Generated: ${GENERATED_CONFIG}"

# ── Create cluster if needed ────────────────────────────────────────

if kind get clusters 2>/dev/null | grep -qw "${GF_CLUSTER_NAME}"; then
  echo "==> Cluster '${GF_CLUSTER_NAME}' already exists — skipping create"
else
  echo "==> Creating Kind cluster '${GF_CLUSTER_NAME}'..."
  kind create cluster --config "${GENERATED_CONFIG}"
  echo "    Cluster created"
fi

gf_reject_cloud_context

echo "==> Cluster '${GF_CLUSTER_NAME}' is ready (context: ${GF_KIND_CONTEXT})"
