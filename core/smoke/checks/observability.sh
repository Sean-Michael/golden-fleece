#!/usr/bin/env bash
# Smoke check: verify LGTM stack is receiving data
# Queries live Prometheus, Loki, and Tempo endpoints from inside the cluster.

MONITORING_NS="monitoring"
PROJECT_NAME=$(grep 'name:' "${GF_CONFIG}" 2>/dev/null | head -1 \
  | sed 's/.*name:[[:space:]]*//' | tr -d '"' | tr -d "'")

# Check if observability is enabled
OBS_ENABLED=$(awk '/^  observability:/,/^  [a-z]/{if(/enabled:.*true/)print "yes"}' "${GF_CONFIG}" 2>/dev/null)
if [ "${OBS_ENABLED}" != "yes" ]; then
  skip "observability stack not enabled"
  return 0 2>/dev/null || exit 0
fi

# Check if monitoring namespace has pods
if ! ${K} get namespace "${MONITORING_NS}" > /dev/null 2>&1; then
  fail "monitoring namespace does not exist"
  return 0 2>/dev/null || exit 0
fi

# ── Prometheus: verify it's running and accepting queries ─────────
PROM_READY=$(${K} get pods -n "${MONITORING_NS}" -l app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
if [ "${PROM_READY}" = "Running" ]; then
  pass "prometheus-server is running"
else
  fail "prometheus-server is not running (status: ${PROM_READY:-not found})"
fi

# Query Prometheus for app metrics (via kubectl exec into grafana pod)
if [ -n "${PROJECT_NAME}" ]; then
  PROM_RESULT=$(${K} exec -n "${MONITORING_NS}" deploy/grafana -- \
    curl -sG "http://prometheus-server/api/v1/query" \
    --data-urlencode "query=up{job=\"${PROJECT_NAME}\"}" 2>/dev/null | \
    grep -c '"result":\[{' 2>/dev/null || echo "0")
  if [ "${PROM_RESULT}" -gt 0 ]; then
    pass "app metrics found in prometheus (job=${PROJECT_NAME})"
  else
    skip "no app metrics in prometheus yet (job=${PROJECT_NAME}) — deploy the app first"
  fi
fi

# ── Loki: verify it's running ─────────────────────────────────────
LOKI_READY=$(${K} get pods -n "${MONITORING_NS}" -l app.kubernetes.io/name=loki \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
if [ "${LOKI_READY}" = "Running" ]; then
  pass "loki is running"
else
  fail "loki is not running (status: ${LOKI_READY:-not found})"
fi

# Query Loki for app logs
if [ -n "${PROJECT_NAME}" ]; then
  LOKI_RESULT=$(${K} exec -n "${MONITORING_NS}" deploy/grafana -- \
    curl -sG "http://loki:3100/loki/api/v1/query" \
    --data-urlencode "query={app=\"${PROJECT_NAME}\"}" 2>/dev/null | \
    grep -c '"result":\[{' 2>/dev/null || echo "0")
  if [ "${LOKI_RESULT}" -gt 0 ]; then
    pass "app logs found in loki (app=${PROJECT_NAME})"
  else
    skip "no app logs in loki yet (app=${PROJECT_NAME}) — deploy the app first"
  fi
fi

# ── Tempo: verify it's running ────────────────────────────────────
TEMPO_READY=$(${K} get pods -n "${MONITORING_NS}" -l app.kubernetes.io/name=tempo \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
if [ "${TEMPO_READY}" = "Running" ]; then
  pass "tempo is running"
else
  fail "tempo is not running (status: ${TEMPO_READY:-not found})"
fi

# Query Tempo for app traces
if [ -n "${PROJECT_NAME}" ]; then
  TEMPO_RESULT=$(${K} exec -n "${MONITORING_NS}" deploy/grafana -- \
    curl -s "http://tempo:3100/api/search?tags=service.name%3D${PROJECT_NAME}" 2>/dev/null | \
    grep -c '"traceID"' 2>/dev/null || echo "0")
  if [ "${TEMPO_RESULT}" -gt 0 ]; then
    pass "traces found in tempo (service.name=${PROJECT_NAME})"
  else
    skip "no traces in tempo yet (service.name=${PROJECT_NAME}) — send some requests first"
  fi
fi

# ── Grafana: verify it's running ──────────────────────────────────
GRAFANA_READY=$(${K} get pods -n "${MONITORING_NS}" -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
if [ "${GRAFANA_READY}" = "Running" ]; then
  pass "grafana is running"
else
  fail "grafana is not running (status: ${GRAFANA_READY:-not found})"
fi

# ── Alloy: verify it's running ────────────────────────────────────
ALLOY_READY=$(${K} get pods -n "${MONITORING_NS}" -l app.kubernetes.io/name=alloy \
  -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || true)
if [ "${ALLOY_READY}" = "true" ]; then
  pass "alloy is running"
else
  fail "alloy is not running (ready: ${ALLOY_READY:-not found})"
fi
