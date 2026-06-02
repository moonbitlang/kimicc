#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sqlite_test="${repo_root}/test/e2e/sqlite_test.mbt"
plan="${repo_root}/docs/sqlite-conformance-plan.md"

extract_string_array() {
  local function_name="$1"
  awk -v fn="${function_name}" '
    $0 == "fn " fn "() -> Array[String] {" {
      in_function = 1
      next
    }
    in_function && $0 == "}" {
      exit
    }
    in_function {
      line = $0
      while (match(line, /"[^"]+"/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "${sqlite_test}"
}

check_plan_mentions_array() {
  local label="$1"
  local function_name="$2"
  local status=0
  local found=0

  while IFS= read -r path; do
    found=1
    if ! grep -Fq "${path}" "${plan}"; then
      echo "${label} path missing from docs/sqlite-conformance-plan.md: ${path}" >&2
      status=1
    fi
  done < <(extract_string_array "${function_name}")

  if [[ "${found}" -eq 0 ]]; then
    echo "could not extract ${label} paths from ${function_name}" >&2
    status=1
  fi

  return "${status}"
}

status=0

check_plan_mentions_array \
  "SQLite public smoke" \
  "sqlite_public_smoke_script_paths" || status=1

check_plan_mentions_array \
  "SQLite residual" \
  "sqlite_residual_script_paths" || status=1

check_plan_mentions_array \
  "SQLite release gate" \
  "sqlite_release_gate_script_paths" || status=1

if [[ "${status}" -ne 0 ]]; then
  exit "${status}"
fi

echo "sqlite conformance plan script paths are documented"
