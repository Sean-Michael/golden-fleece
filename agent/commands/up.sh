#!/usr/bin/env bash
# golden-fleece/agent/commands/up.sh
# Bring up the full harness: cluster + stacks + registry + app
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

if [ ! -f "${GF_CONFIG}" ]; then
  echo "ERROR: golden-fleece.yaml not found. Run the adopt flow first."
  exit 1
fi

echo "==> golden-fleece up"
make -f "${PWD}/Makefile" up GF_CONFIG="${GF_CONFIG}"
