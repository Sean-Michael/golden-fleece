#!/usr/bin/env bash
# golden-fleece/core/stacks/observability/lgtm/install.sh
# Install Grafana LGTM stack (Loki, Grafana, Tempo, Prometheus + Alloy) into the cluster.
# Idempotent — safe to re-run.
# Usage: GF_CONFIG=golden-fleece.yaml bash golden-fleece/core/stacks/observability/lgtm/install.sh
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

source "${GF_DIR}/core/safety/guard.sh"
gf_require_context
gf_reject_cloud_context

MONITORING_NS="${GF_MONITORING_NS:-monitoring}"
VALUES_DIR="${GF_DIR}/core/stacks/observability/lgtm/values"
DASHBOARDS_DIR="${GF_DIR}/core/stacks/observability/lgtm/dashboards"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"

# Parse project name for dashboard rendering
PROJECT_NAME=$(_gf_get name)
PROJECT_NS=$(grep 'namespace:' "${GF_CONFIG}" 2>/dev/null | tail -1 \
  | sed 's/.*namespace:[[:space:]]*//' | tr -d '"' | tr -d "'")
PROJECT_NS="${PROJECT_NS:-${PROJECT_NAME}}"

echo "==> Installing LGTM observability stack"
echo "    Context:   ${GF_CONTEXT}"
echo "    Namespace: ${MONITORING_NS}"
echo "    Project:   ${PROJECT_NAME}"

# ── Create namespace ──────────────────────────────────────────────
${K} create namespace "${MONITORING_NS}" --dry-run=client -o yaml | ${K} apply -f -

# ── Ensure helm repos ─────────────────────────────────────────────
echo "==> Adding helm repos..."
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update grafana prometheus-community

# ── Loki (logs) ───────────────────────────────────────────────────
echo ""
echo "==> Installing Loki (single binary mode)..."
${H} upgrade --install loki grafana/loki \
  --namespace "${MONITORING_NS}" \
  --values "${VALUES_DIR}/loki.yaml" \
  --wait --timeout 5m

# ── Tempo (traces) ────────────────────────────────────────────────
echo ""
echo "==> Installing Tempo (single binary mode)..."
${H} upgrade --install tempo grafana/tempo \
  --namespace "${MONITORING_NS}" \
  --values "${VALUES_DIR}/tempo.yaml" \
  --wait --timeout 3m

# ── Prometheus (metrics) ──────────────────────────────────────────
echo ""
echo "==> Installing Prometheus (with remote-write receiver)..."
${H} upgrade --install prometheus prometheus-community/prometheus \
  --namespace "${MONITORING_NS}" \
  --values "${VALUES_DIR}/prometheus.yaml" \
  --values "${VALUES_DIR}/alert-rules.yaml" \
  --wait --timeout 5m

# ── Dashboard ConfigMaps (for Grafana sidecar) ────────────────────
echo ""
echo "==> Creating dashboard ConfigMaps..."

# Render and load the generic app overview dashboard template
if [ -f "${DASHBOARDS_DIR}/app-overview.json.tmpl" ]; then
  RENDERED="${PWD}/.golden-fleece/app-overview.json"
  mkdir -p "$(dirname "${RENDERED}")"
  sed \
    -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
    -e "s|{{PROJECT_NS}}|${PROJECT_NS}|g" \
    "${DASHBOARDS_DIR}/app-overview.json.tmpl" > "${RENDERED}"

  ${K} create configmap "grafana-dashboard-${PROJECT_NAME}-overview" \
    --namespace "${MONITORING_NS}" \
    --from-file="app-overview.json=${RENDERED}" \
    --dry-run=client -o yaml \
    | ${K} label --local -f - grafana_dashboard=1 -o yaml \
    | ${K} apply -f -
  echo "    Created: grafana-dashboard-${PROJECT_NAME}-overview"
fi

# Load any project-specific dashboards from the project's chart dir
PROJECT_DASHBOARDS="${PWD}/chart/dashboards"
if [ -d "${PROJECT_DASHBOARDS}" ]; then
  for dashboard_file in "${PROJECT_DASHBOARDS}"/*.json; do
    [ -f "${dashboard_file}" ] || continue
    dashboard_name=$(basename "${dashboard_file}" .json)
    ${K} create configmap "grafana-dashboard-${dashboard_name}" \
      --namespace "${MONITORING_NS}" \
      --from-file="${dashboard_name}.json=${dashboard_file}" \
      --dry-run=client -o yaml \
      | ${K} label --local -f - grafana_dashboard=1 -o yaml \
      | ${K} apply -f -
    echo "    Created: grafana-dashboard-${dashboard_name}"
  done
fi

# ── Grafana (visualization) ───────────────────────────────────────
echo ""
echo "==> Installing Grafana..."
${H} upgrade --install grafana grafana/grafana \
  --namespace "${MONITORING_NS}" \
  --values "${VALUES_DIR}/grafana.yaml" \
  --wait --timeout 3m

# ── Alloy (collector + relay) ─────────────────────────────────────
echo ""
echo "==> Installing Grafana Alloy (logs + traces + metrics pipeline)..."
${H} upgrade --install alloy grafana/alloy \
  --namespace "${MONITORING_NS}" \
  --values "${VALUES_DIR}/alloy.yaml" \
  --wait --timeout 3m

# ── Verify ────────────────────────────────────────────────────────
echo ""
echo "==> Verifying pods in ${MONITORING_NS}..."
${K} get pods -n "${MONITORING_NS}"

echo ""
echo "============================================================"
echo "  LGTM Stack Ready"
echo "============================================================"
echo ""
echo "  Context:    ${GF_CONTEXT}"
echo "  Namespace:  ${MONITORING_NS}"
echo ""
echo "  Endpoints (in-cluster):"
echo "    Loki        loki.${MONITORING_NS}.svc:3100"
echo "    Tempo       tempo.${MONITORING_NS}.svc:3100  (OTLP: 4317/4318)"
echo "    Prometheus  prometheus-server.${MONITORING_NS}.svc:80"
echo "    Grafana     grafana.${MONITORING_NS}.svc:3000"
echo "    Alloy       alloy.${MONITORING_NS}.svc:4317/4318 (OTLP)"
echo ""
echo "  Access Grafana:"
echo "    ${K} port-forward -n ${MONITORING_NS} svc/grafana ${GRAFANA_PORT}:3000 &"
echo "    open http://localhost:${GRAFANA_PORT}"
echo "    Login: admin / admin"
echo ""
echo "  OTLP wiring (add to Helm values-dev.yaml):"
echo "    OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy.${MONITORING_NS}.svc.cluster.local:4318"
echo "    OTEL_SERVICE_NAME=${PROJECT_NAME}"
echo ""
