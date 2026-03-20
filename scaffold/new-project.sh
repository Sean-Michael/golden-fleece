#!/usr/bin/env bash
# golden-fleece/scaffold/new-project.sh
# Scaffold golden-fleece harness files into an existing project.
# Usage: bash golden-fleece/scaffold/new-project.sh
#
# Reads golden-fleece.yaml from the project root (must exist).
# Generates: Makefile targets, CLAUDE.md additions, AGENTS.md, AUTONOMOUS-SESSION.md
set -euo pipefail

GF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GF_CONFIG="${GF_CONFIG:-${PWD}/golden-fleece.yaml}"
TEMPLATES="${GF_DIR}/scaffold/templates"

if [ ! -f "${GF_CONFIG}" ]; then
  echo "ERROR: golden-fleece.yaml not found at ${GF_CONFIG}"
  echo ""
  echo "Copy the template first:"
  echo "  cp golden-fleece/scaffold/templates/golden-fleece.yaml.tmpl golden-fleece.yaml"
  echo "  # edit golden-fleece.yaml with your project values"
  echo "  # then re-run this script"
  exit 1
fi

# ── Parse config values ─────────────────────────────────────────────

_get() {
  grep "${1}:" "${GF_CONFIG}" 2>/dev/null | head -1 | sed "s/.*${1}:[[:space:]]*//" | tr -d '"' | tr -d "'" || true
}

PROJECT_NAME=$(_get name)
DESCRIPTION=$(_get description)
LANGUAGE=$(_get language)
FRAMEWORK=$(_get framework)

# Cluster name: try new schema (target.cluster_name) then fall back
GF_CLUSTER_NAME=$(_get cluster_name)
if [ -z "${GF_CLUSTER_NAME}" ]; then
  GF_CLUSTER_NAME="${PROJECT_NAME}-dev"
fi

# Registry port: look under stacks.registry
REGISTRY_PORT=$(grep -A5 'registry:' "${GF_CONFIG}" | grep 'port:' | head -1 \
  | sed 's/.*port:[[:space:]]*//' | tr -d ' ')
REGISTRY_PORT="${REGISTRY_PORT:-5050}"

APP_START_CMD=$(_get start_cmd)
APP_HEALTH_URL=$(_get health_url)
# Parse app.port specifically from the app: section (not stacks.registry.port)
APP_PORT=$(awk '/^app:/,/^[a-z]/{if(/^  port:/)print}' "${GF_CONFIG}" \
  | head -1 | sed 's/.*port:[[:space:]]*//' | tr -d ' ')
APP_PORT="${APP_PORT:-8000}"
APP_HOST_PORT=$(grep 'hostPort:' "${GF_CONFIG}" | head -1 | sed 's/.*hostPort:[[:space:]]*//' | tr -d ' ')
ENV_FILE=$(_get env_file)
ENV_FILE="${ENV_FILE:-.env.dev}"
COMPOSE_FILE=$(grep -A3 'compose:' "${GF_CONFIG}" 2>/dev/null | grep 'file:' | head -1 \
  | sed 's/.*file:[[:space:]]*//' | tr -d '"' || true)
COMPOSE_SERVICES=$(python3 -c "
import re
config = open('${GF_CONFIG}').read()
m = re.search(r'services:\s*\[([^\]]*)\]', config)
if m:
    print(m.group(1).strip())
else:
    m = re.search(r'services:\s*\n((?:\s+-[^\n]+\n)+)', config)
    if m:
        services = re.findall(r'-\s+(\S+)', m.group(1))
        print(' '.join(services))
" 2>/dev/null || echo "")
HELM_CHART_DIR=$(_get chart_dir)
HELM_CHART_DIR="${HELM_CHART_DIR:-./chart}"
HELM_VALUES_DEV=$(_get values_dev)
HELM_VALUES_DEV="${HELM_VALUES_DEV:-chart/values-dev.yaml}"
TEST_CMD=$(_get test_cmd)
TEST_CMD="${TEST_CMD:-echo 'no test command configured'}"

echo "==> golden-fleece scaffold"
echo "    Project:  ${PROJECT_NAME}"
echo "    Cluster:  ${GF_CLUSTER_NAME}"
echo "    Registry: localhost:${REGISTRY_PORT}"

# ── Render a template file ──────────────────────────────────────────

render() {
  local src="$1" dst="$2"
  sed \
    -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
    -e "s|{{DESCRIPTION}}|${DESCRIPTION}|g" \
    -e "s|{{LANGUAGE}}|${LANGUAGE}|g" \
    -e "s|{{FRAMEWORK}}|${FRAMEWORK}|g" \
    -e "s|{{GF_CLUSTER_NAME}}|${GF_CLUSTER_NAME}|g" \
    -e "s|{{REGISTRY_PORT}}|${REGISTRY_PORT}|g" \
    -e "s|{{APP_START_CMD}}|${APP_START_CMD}|g" \
    -e "s|{{APP_HEALTH_URL}}|${APP_HEALTH_URL}|g" \
    -e "s|{{APP_PORT}}|${APP_PORT}|g" \
    -e "s|{{APP_HOST_PORT}}|${APP_HOST_PORT}|g" \
    -e "s|{{ENV_FILE}}|${ENV_FILE}|g" \
    -e "s|{{COMPOSE_FILE}}|${COMPOSE_FILE}|g" \
    -e "s|{{COMPOSE_SERVICES}}|${COMPOSE_SERVICES}|g" \
    -e "s|{{HELM_CHART_DIR}}|${HELM_CHART_DIR}|g" \
    -e "s|{{HELM_VALUES_DEV}}|${HELM_VALUES_DEV}|g" \
    -e "s|{{TEST_CMD}}|${TEST_CMD}|g" \
    -e "s|{{CLUSTER_NAME}}|${GF_CLUSTER_NAME}|g" \
    "${src}" > "${dst}"
  echo "  wrote: ${dst}"
}

# ── Scaffold Makefile harness section ──────────────────────────────

if [ -f "${PWD}/Makefile" ]; then
  if grep -q "golden-fleece" "${PWD}/Makefile"; then
    echo "==> Makefile already has golden-fleece targets — skipping"
  else
    echo "==> Appending golden-fleece targets to existing Makefile..."
    echo "" >> "${PWD}/Makefile"
    echo "# ── golden-fleece harness targets (generated) ──────────────────" >> "${PWD}/Makefile"
    render "${TEMPLATES}/Makefile.tmpl" ".gf-makefile-fragment"
    cat ".gf-makefile-fragment" >> "${PWD}/Makefile"
    rm ".gf-makefile-fragment"
    echo "  updated: Makefile"
  fi
else
  render "${TEMPLATES}/Makefile.tmpl" "${PWD}/Makefile"
fi

# ── Scaffold Helm chart ────────────────────────────────────────────

CHART_DST="${PWD}/${HELM_CHART_DIR}"
HELM_TEMPLATES="${GF_DIR}/scaffold/helm/base"

if [ -f "${CHART_DST}/Chart.yaml" ]; then
  echo "==> Helm chart already exists at ${HELM_CHART_DIR} — skipping"
else
  echo "==> Scaffolding Helm chart at ${HELM_CHART_DIR}..."
  mkdir -p "${CHART_DST}/templates"

  render "${HELM_TEMPLATES}/Chart.yaml.tmpl" "${CHART_DST}/Chart.yaml"
  render "${HELM_TEMPLATES}/values.yaml.tmpl" "${CHART_DST}/values.yaml"
  render "${HELM_TEMPLATES}/values-dev.yaml.tmpl" "${CHART_DST}/values-dev.yaml"

  # Template files are pure Helm Go templates — copy without rendering
  # (they use {{ .Values.x }} syntax which would conflict with our {{VAR}} rendering)
  for tmpl in "${HELM_TEMPLATES}/templates/"*.tmpl; do
    [ -f "${tmpl}" ] || continue
    dst_name=$(basename "${tmpl}" .tmpl)
    cp "${tmpl}" "${CHART_DST}/templates/${dst_name}"
    echo "  wrote: ${HELM_CHART_DIR}/templates/${dst_name}"
  done
fi

# ── Scaffold AUTONOMOUS-SESSION.md ─────────────────────────────────

if [ ! -f "${PWD}/AUTONOMOUS-SESSION.md" ]; then
  render "${TEMPLATES}/AUTONOMOUS-SESSION.md.tmpl" "${PWD}/AUTONOMOUS-SESSION.md"
else
  echo "  skipped: AUTONOMOUS-SESSION.md (already exists)"
fi

# ── Scaffold AGENTS.md ────────────────────────────────────────────

if [ ! -f "${PWD}/AGENTS.md" ]; then
  render "${TEMPLATES}/AGENTS.md.tmpl" "${PWD}/AGENTS.md"
else
  echo "  skipped: AGENTS.md (already exists)"
fi

# ── Link the skill into CLAUDE.md ──────────────────────────────────

SKILL_REF="Read golden-fleece/agent/SKILL.md before any kubectl, helm, image build, or k8s task."

if [ -f "${PWD}/CLAUDE.md" ]; then
  if ! grep -q "golden-fleece" "${PWD}/CLAUDE.md"; then
    echo "" >> "${PWD}/CLAUDE.md"
    echo "## golden-fleece K8s Harness" >> "${PWD}/CLAUDE.md"
    echo "" >> "${PWD}/CLAUDE.md"
    echo "${SKILL_REF}" >> "${PWD}/CLAUDE.md"
    echo "  updated: CLAUDE.md"
  else
    echo "  skipped: CLAUDE.md (already references golden-fleece)"
  fi
fi

# ── Create hack/ directory structure ───────────────────────────────

mkdir -p "${PWD}/hack/argo-templates"
if [ ! -f "${PWD}/hack/argo-templates/.gitkeep" ]; then
  touch "${PWD}/hack/argo-templates/.gitkeep"
  echo "  created: hack/argo-templates/ (place WorkflowTemplates here)"
fi

# ── Create .golden-fleece/ (generated artifacts, gitignored) ───────

mkdir -p "${PWD}/.golden-fleece"
if ! grep -q ".golden-fleece" "${PWD}/.gitignore" 2>/dev/null; then
  echo ".golden-fleece/" >> "${PWD}/.gitignore"
  echo ".gf-app.pid" >> "${PWD}/.gitignore"
  echo ".gf-app.log" >> "${PWD}/.gitignore"
fi

echo ""
echo "✓ golden-fleece scaffolded for '${PROJECT_NAME}'"
echo ""
echo "Next steps:"
echo "  1. Edit AUTONOMOUS-SESSION.md — describe what Claude should build"
echo "  2. make up     — bring up the cluster and app"
echo "  3. make smoke  — verify the harness is healthy"
echo "  4. make session — get the autonomous session prompt"
