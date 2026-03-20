#!/usr/bin/env bash
# golden-fleece/agent/commands/adopt.sh
# Entry point for the adopt flow. Mostly orchestrated by Claude via SKILL.md,
# but this script handles the mechanical parts.
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"

echo "==> golden-fleece adopt"
echo ""
echo "The adopt flow is primarily driven by Claude Code reading SKILL.md."
echo "Use /fleece:adopt in a Claude Code session to start the full flow."
echo ""
echo "Manual steps if running outside Claude:"
echo "  1. Create golden-fleece.yaml from the template"
echo "  2. bash golden-fleece/scaffold/new-project.sh"
echo "  3. make kind-up"
echo "  4. make image && make helm-install"
echo "  5. make smoke"
