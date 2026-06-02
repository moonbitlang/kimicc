#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fetch_script="${repo_root}/scripts/fetch-external-parser-fixtures.sh"
workflow="${repo_root}/.github/workflows/ci.yml"
plan="${repo_root}/docs/drop-in-compiler-plan.md"

extract_fetch_ref() {
  local name="$1"
  local env_name="$2"
  sed -nE "s/^${name}_ref=\"\\\$\\{${env_name}:-([0-9a-f]+)\\}\"$/\\1/p" "${fetch_script}"
}

extract_workflow_ref() {
  local env_name="$1"
  sed -nE "s/^[[:space:]]*${env_name}: ([0-9a-f]+)$/\\1/p" "${workflow}"
}

extract_plan_ref() {
  local label="$1"
  sed -nE "s/^- ${label} parser fixture: \`([0-9a-f]+)\`.*/\\1/p" "${plan}"
}

require_value() {
  local label="$1"
  local value="$2"
  if [[ -z "${value}" ]]; then
    echo "could not extract ${label}" >&2
    exit 1
  fi
}

check_pin() {
  local label="$1"
  local fetch_ref="$2"
  local workflow_ref="$3"
  local plan_ref="$4"

  require_value "${label} fetch-script ref" "${fetch_ref}"
  require_value "${label} workflow ref" "${workflow_ref}"
  require_value "${label} plan ref" "${plan_ref}"

  if [[ "${fetch_ref}" != "${workflow_ref}" || "${fetch_ref}" != "${plan_ref}" ]]; then
    echo "${label} external parser fixture pin mismatch:" >&2
    echo "  scripts/fetch-external-parser-fixtures.sh: ${fetch_ref}" >&2
    echo "  .github/workflows/ci.yml: ${workflow_ref}" >&2
    echo "  docs/drop-in-compiler-plan.md: ${plan_ref}" >&2
    exit 1
  fi
}

check_pin \
  "TinyCC" \
  "$(extract_fetch_ref tinycc TINYCC_REF)" \
  "$(extract_workflow_ref TINYCC_REF)" \
  "$(extract_plan_ref TinyCC)"

check_pin \
  "QuickJS" \
  "$(extract_fetch_ref quickjs QUICKJS_REF)" \
  "$(extract_workflow_ref QUICKJS_REF)" \
  "$(extract_plan_ref QuickJS)"

echo "external parser fixture pins are consistent"
