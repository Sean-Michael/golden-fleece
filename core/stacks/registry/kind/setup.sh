#!/usr/bin/env bash
# golden-fleece/core/stacks/registry/kind/setup.sh
# Idempotent local registry setup for any Kind cluster.
# Reads cluster name + registry port from golden-fleece.yaml.
# Usage: bash golden-fleece/core/stacks/registry/kind/setup.sh
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

source "${GF_DIR}/core/safety/guard.sh"
gf_require_context

# Parse registry port from config (default 5050)
REGISTRY_PORT=$(grep 'port:' "${GF_CONFIG}" | grep -v '#' | tail -1 \
  | sed 's/.*port:[[:space:]]*//' | tr -d ' ' || echo "5050")
REGISTRY_PORT="${REGISTRY_PORT:-5050}"
REGISTRY_NAME="${GF_CLUSTER_NAME}-registry"

echo "==> Setting up local registry"
echo "    Name:    ${REGISTRY_NAME}"
echo "    Port:    localhost:${REGISTRY_PORT}"
echo "    Cluster: ${GF_CLUSTER_NAME}"

# ── Start registry container ────────────────────────────────────────

if docker inspect "${REGISTRY_NAME}" >/dev/null 2>&1; then
  if [ "$(docker inspect -f '{{.State.Running}}' "${REGISTRY_NAME}" 2>/dev/null)" = "true" ]; then
    echo "==> Registry '${REGISTRY_NAME}' already running"
  else
    echo "==> Starting existing registry container..."
    docker start "${REGISTRY_NAME}"
  fi
else
  echo "==> Creating registry container on localhost:${REGISTRY_PORT}..."
  docker run -d \
    --restart=always \
    --name "${REGISTRY_NAME}" \
    -p "${REGISTRY_PORT}:5000" \
    registry:2
fi

# ── Connect to Kind network ─────────────────────────────────────────

if ! docker network inspect kind 2>/dev/null | grep -q "${REGISTRY_NAME}"; then
  echo "==> Connecting registry to Kind network..."
  docker network connect kind "${REGISTRY_NAME}" 2>/dev/null || true
fi

# ── Configure containerd trust on each node ─────────────────────────

echo "==> Configuring containerd registry trust on Kind nodes..."
NODES=$(kind get nodes --name "${GF_CLUSTER_NAME}" 2>/dev/null)
for NODE in ${NODES}; do
  docker exec "${NODE}" bash -c "
    mkdir -p /etc/containerd/certs.d/localhost:${REGISTRY_PORT}
    cat > /etc/containerd/certs.d/localhost:${REGISTRY_PORT}/hosts.toml <<TOML
[host.\"http://${REGISTRY_NAME}:5000\"]
  capabilities = [\"pull\", \"resolve\", \"push\"]
  skip_verify = true
TOML
    mkdir -p /etc/containerd/certs.d/${REGISTRY_NAME}:5000
    cat > /etc/containerd/certs.d/${REGISTRY_NAME}:5000/hosts.toml <<TOML
[host.\"http://${REGISTRY_NAME}:5000\"]
  capabilities = [\"pull\", \"resolve\", \"push\"]
  skip_verify = true
TOML
  "
done

# ── Restart containerd to pick up config ────────────────────────────

for NODE in ${NODES}; do
  docker exec "${NODE}" systemctl restart containerd
done

# ── Register with cluster via ConfigMap ─────────────────────────────

${K} apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REGISTRY_PORT}"
    hostFromClusterNetwork: "${REGISTRY_NAME}:5000"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

echo ""
echo "✓ Registry ready"
echo "  Push:  docker build -t localhost:${REGISTRY_PORT}/myapp:dev . && docker push localhost:${REGISTRY_PORT}/myapp:dev"
echo "  Pull:  (from Kind pods) image: ${REGISTRY_NAME}:5000/myapp:dev"
