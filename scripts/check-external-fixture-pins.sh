#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fetch_script="${repo_root}/scripts/fetch-external-parser-fixtures.sh"
native_ci="${repo_root}/scripts/native-ci-test.sh"
workflow="${repo_root}/.github/workflows/ci.yml"
harness="${repo_root}/test/e2e/harness_test.mbt"
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

extract_fetch_output() {
  local name="$1"
  local env_name="$2"
  sed -nE "s/^${name}_output=\"\\\$\\{${env_name}:-([^\"]+)\\}\"$/\\1/p" "${fetch_script}"
}

extract_native_fixture() {
  local name="$1"
  local env_name="$2"
  sed -nE "s/^${name}_fixture=\"\\\$\\{${env_name}:-([^\"]+)\\}\"$/\\1/p" "${native_ci}"
}

extract_harness_default_path() {
  local function_name="$1"
  awk -v fn="${function_name}" '
    $0 == "fn " fn "() -> String {" {
      getline
      gsub(/^[[:space:]]*"/, "")
      gsub(/"$/, "")
      print
      exit
    }
  ' "${harness}"
}

extract_plan_ref() {
  local label="$1"
  sed -nE "s/^- ${label} parser fixture: \`([0-9a-f]+)\`.*/\\1/p" "${plan}"
}

extract_plan_tinycc_output() {
  awk '
    /^fixtures locally\. It writes / {
      match($0, /`[^`]+`/)
      if (RSTART) {
        print substr($0, RSTART + 1, RLENGTH - 2)
        exit
      }
    }
  ' "${plan}"
}

extract_plan_quickjs_output() {
  awk '
    /^`[^`]+` by default and accepts / {
      match($0, /`[^`]+`/)
      if (RSTART) {
        print substr($0, RSTART + 1, RLENGTH - 2)
        exit
      }
    }
  ' "${plan}"
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

check_output_path() {
  local label="$1"
  local fetch_path="$2"
  local native_path="$3"
  local harness_path="$4"
  local plan_path="$5"

  require_value "${label} fetch-script output path" "${fetch_path}"
  require_value "${label} native-ci output path" "${native_path}"
  require_value "${label} e2e harness output path" "${harness_path}"
  require_value "${label} plan output path" "${plan_path}"

  if [[ "${fetch_path}" != "${native_path}" ||
    "${fetch_path}" != "${harness_path}" ||
    "${fetch_path}" != "${plan_path}" ]]; then
    echo "${label} external parser fixture output path mismatch:" >&2
    echo "  scripts/fetch-external-parser-fixtures.sh: ${fetch_path}" >&2
    echo "  scripts/native-ci-test.sh: ${native_path}" >&2
    echo "  test/e2e/harness_test.mbt: ${harness_path}" >&2
    echo "  docs/drop-in-compiler-plan.md: ${plan_path}" >&2
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

check_output_path \
  "TinyCC" \
  "$(extract_fetch_output tinycc TINYCC_PREPROCESSED_OUTPUT)" \
  "$(extract_native_fixture tinycc TINYCC_PREPROCESSED_OUTPUT)" \
  "$(extract_harness_default_path tinycc_preprocessed_default_fixture_path)" \
  "$(extract_plan_tinycc_output)"

check_output_path \
  "QuickJS" \
  "$(extract_fetch_output quickjs QUICKJS_PREPROCESSED_OUTPUT)" \
  "$(extract_native_fixture quickjs QUICKJS_PREPROCESSED_OUTPUT)" \
  "$(extract_harness_default_path quickjs_preprocessed_default_fixture_path)" \
  "$(extract_plan_quickjs_output)"

echo "external parser fixture pins and output paths are consistent"
