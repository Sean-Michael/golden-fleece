#!/usr/bin/env bash
# golden-fleece/agent/commands/smoke.sh
# Run all smoke tests
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

GF_CONFIG="${GF_CONFIG}" bash "${GF_DIR}/core/smoke/lib.sh"
