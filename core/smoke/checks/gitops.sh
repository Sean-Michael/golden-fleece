#!/usr/bin/env bash
# Smoke check: verify ArgoCD is running and app is synced

# Check if gitops is enabled
GITOPS_ENABLED=$(awk '/^  gitops:/,/^  [a-z]/{if(/enabled:.*true/)print "yes"}' "${GF_CONFIG}" 2>/dev/null)
if [ "${GITOPS_ENABLED}" != "yes" ]; then
  skip "gitops not enabled"
  return 0 2>/dev/null || exit 0
fi

ARGOCD_NS="argocd"

# Check ArgoCD server is running
if ${K} get namespace "${ARGOCD_NS}" > /dev/null 2>&1; then
  ARGOCD_READY=$(${K} get pods -n "${ARGOCD_NS}" -l app.kubernetes.io/name=argocd-server \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
  if [ "${ARGOCD_READY}" = "Running" ]; then
    pass "argocd-server is running"
  else
    fail "argocd-server is not running (status: ${ARGOCD_READY:-not found})"
  fi
else
  fail "argocd namespace does not exist"
fi
