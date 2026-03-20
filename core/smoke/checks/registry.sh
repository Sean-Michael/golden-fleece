#!/usr/bin/env bash
# Smoke check: verify registry is reachable and functional

# Check if registry is enabled
REG_ENABLED=$(awk '/^  registry:/,/^  [a-z]/{if(/enabled:.*true/)print "yes"}' "${GF_CONFIG}" 2>/dev/null)
if [ "${REG_ENABLED}" != "yes" ]; then
  skip "registry not enabled"
  return 0 2>/dev/null || exit 0
fi

REGISTRY_PORT=$(grep -A5 'registry:' "${GF_CONFIG}" | grep 'port:' | head -1 \
  | sed 's/.*port:[[:space:]]*//' | tr -d ' ')
REGISTRY_PORT="${REGISTRY_PORT:-5050}"

# Check registry is responding
if curl -sf "http://localhost:${REGISTRY_PORT}/v2/" > /dev/null 2>&1; then
  pass "registry reachable at localhost:${REGISTRY_PORT}"
else
  fail "registry not reachable at localhost:${REGISTRY_PORT}"
fi
