#!/usr/bin/env bash
# golden-fleece/core/stacks/observability/external/connect.sh
# Validate external observability endpoints and write config.
# Usage: GF_CONFIG=golden-fleece.yaml bash golden-fleece/core/stacks/observability/external/connect.sh
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

source "${GF_DIR}/core/safety/guard.sh"
gf_require_context

# Parse external observability config
GRAFANA_URL=$(grep -A15 'observability:' "${GF_CONFIG}" | grep 'grafana_url:' | head -1 \
  | sed 's/.*grafana_url:[[:space:]]*//' | tr -d '"' | tr -d "'")
LOKI_URL=$(grep -A15 'observability:' "${GF_CONFIG}" | grep 'loki_url:' | head -1 \
  | sed 's/.*loki_url:[[:space:]]*//' | tr -d '"' | tr -d "'")
PROMETHEUS_URL=$(grep -A15 'observability:' "${GF_CONFIG}" | grep 'prometheus_url:' | head -1 \
  | sed 's/.*prometheus_url:[[:space:]]*//' | tr -d '"' | tr -d "'")
OTLP_ENDPOINT=$(grep -A15 'observability:' "${GF_CONFIG}" | grep 'otlp_endpoint:' | head -1 \
  | sed 's/.*otlp_endpoint:[[:space:]]*//' | tr -d '"' | tr -d "'")

echo "==> Connecting to external observability stack"
FAIL=0

# ── Validate each endpoint ────────────────────────────────────────
_check() {
  local name="$1" url="$2" path="$3"
  if [ -z "${url}" ]; then
    echo "    SKIP: ${name} — not configured"
    return
  fi
  if curl -sf "${url}${path}" > /dev/null 2>&1; then
    echo "    OK:   ${name} at ${url}"
  else
    echo "    FAIL: ${name} at ${url}${path} — not reachable"
    FAIL=1
  fi
}

_check "Grafana"    "${GRAFANA_URL}"    "/api/health"
_check "Loki"       "${LOKI_URL}"       "/ready"
_check "Prometheus" "${PROMETHEUS_URL}"  "/-/ready"
_check "OTLP"       "${OTLP_ENDPOINT}"  ""

if [ "${FAIL}" -gt 0 ]; then
  echo ""
  echo "WARNING: Some endpoints are not reachable. Check URLs and network access."
fi

# ── Write config for other scripts ────────────────────────────────
mkdir -p "${PWD}/.golden-fleece"
cat > "${PWD}/.golden-fleece/observability.env" <<EOF
OBSERVABILITY_TYPE=external
GRAFANA_URL=${GRAFANA_URL}
LOKI_URL=${LOKI_URL}
PROMETHEUS_URL=${PROMETHEUS_URL}
OTLP_ENDPOINT=${OTLP_ENDPOINT}
EOF
echo ""
echo "    Wrote .golden-fleece/observability.env"

if [ -n "${OTLP_ENDPOINT}" ]; then
  echo ""
  echo "Update chart/values-dev.yaml:"
  echo "  observability:"
  echo "    enabled: true"
  echo "    otlpEndpoint: \"${OTLP_ENDPOINT}\""
fi
