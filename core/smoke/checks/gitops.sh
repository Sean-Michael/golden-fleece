#!/usr/bin/env bash
# Smoke check: verify ArgoCD is running and app is synced (if Application exists)

# Check if gitops is enabled
GITOPS_ENABLED=$(awk '/^  gitops:/,/^  [a-z]/{if(/enabled:.*true/)print "yes"}' "${GF_CONFIG}" 2>/dev/null)
if [ "${GITOPS_ENABLED}" != "yes" ]; then
  skip "gitops not enabled"
  return 0 2>/dev/null || exit 0
fi

ARGOCD_NS="argocd"
PROJECT_NAME=$(grep 'name:' "${GF_CONFIG}" 2>/dev/null | head -1 \
  | sed 's/.*name:[[:space:]]*//' | tr -d '"' | tr -d "'")

# Check ArgoCD server is running
if ! ${K} get namespace "${ARGOCD_NS}" > /dev/null 2>&1; then
  fail "argocd namespace does not exist"
  return 0 2>/dev/null || exit 0
fi

ARGOCD_READY=$(${K} get pods -n "${ARGOCD_NS}" -l app.kubernetes.io/name=argocd-server \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
if [ "${ARGOCD_READY}" = "Running" ]; then
  pass "argocd-server is running"
else
  fail "argocd-server is not running (status: ${ARGOCD_READY:-not found})"
fi

# Check AppProject exists
if ${K} get appproject -n "${ARGOCD_NS}" "${PROJECT_NAME}" > /dev/null 2>&1; then
  pass "argocd project '${PROJECT_NAME}' exists"
else
  fail "argocd project '${PROJECT_NAME}' not found"
fi

# Check Application — it's expected to be missing when there's no git remote
if ${K} get application -n "${ARGOCD_NS}" "${PROJECT_NAME}" > /dev/null 2>&1; then
  APP_HEALTH=$(${K} get application -n "${ARGOCD_NS}" "${PROJECT_NAME}" \
    -o jsonpath='{.status.health.status}' 2>/dev/null || true)
  APP_SYNC=$(${K} get application -n "${ARGOCD_NS}" "${PROJECT_NAME}" \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
  if [ "${APP_HEALTH}" = "Healthy" ] && [ "${APP_SYNC}" = "Synced" ]; then
    pass "argocd app '${PROJECT_NAME}' is Healthy+Synced"
  else
    fail "argocd app '${PROJECT_NAME}' health=${APP_HEALTH:-unknown} sync=${APP_SYNC:-unknown}"
  fi
else
  skip "argocd application not created (no git remote — using helm install for local dev)"
fi
