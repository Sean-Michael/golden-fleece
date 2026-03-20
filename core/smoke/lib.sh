#!/usr/bin/env bash
# golden-fleece/core/smoke/lib.sh
# Composable smoke test runner. Runs all checks in core/smoke/checks/.
# Usage: GF_CONFIG=golden-fleece.yaml bash golden-fleece/core/smoke/lib.sh
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

source "${GF_DIR}/core/safety/guard.sh"

CHECKS_DIR="${GF_DIR}/core/smoke/checks"
FAILED=0
PASSED=0
SKIPPED=0

red()   { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }
blue()  { printf "\033[34m%s\033[0m\n" "$*"; }

pass() { green "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { red   "  FAIL: $1"; FAILED=$((FAILED + 1)); }
skip() { yellow "  SKIP: $1"; SKIPPED=$((SKIPPED + 1)); }

# Export for use by check scripts
export GF_DIR GF_CONFIG GF_CONTEXT GF_CLUSTER_NAME GF_TARGET_TYPE K H
export -f pass fail skip red green yellow blue

blue "==> golden-fleece smoke tests"
blue "    Context: ${GF_CONTEXT}"
echo ""

# ── Run each check script ─────────────────────────────────────────
for check in "${CHECKS_DIR}"/*.sh; do
  [ -f "${check}" ] || continue
  check_name=$(basename "${check}" .sh)
  blue "── ${check_name} ──"
  # Source the check so it can use pass/fail/skip
  source "${check}" || fail "${check_name} errored"
  echo ""
done

# ── Summary ───────────────────────────────────────────────────────
echo "════════════════════════════════════════"
if [ "${FAILED}" -gt 0 ]; then
  red   "  ${FAILED} FAILED, ${PASSED} passed, ${SKIPPED} skipped"
  exit 1
else
  green "  All ${PASSED} checks passed (${SKIPPED} skipped)"
fi
echo "════════════════════════════════════════"
