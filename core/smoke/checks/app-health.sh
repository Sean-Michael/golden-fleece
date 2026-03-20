#!/usr/bin/env bash
# Smoke check: verify the app's health endpoint responds
APP_HEALTH_URL=$(grep 'health_url:' "${GF_CONFIG}" 2>/dev/null | head -1 \
  | sed 's/.*health_url:[[:space:]]*//' | tr -d '"' | tr -d "'")

if [ -z "${APP_HEALTH_URL}" ]; then
  skip "no health_url configured"
else
  if curl -sf "${APP_HEALTH_URL}" > /dev/null 2>&1; then
    pass "app healthy at ${APP_HEALTH_URL}"
  else
    fail "app not responding at ${APP_HEALTH_URL}"
  fi
fi
