#!/usr/bin/env bash
set -euo pipefail

target="${MOON_TARGET:-native}"
tinycc_fixture="${TINYCC_PREPROCESSED_OUTPUT:-/tmp/tinycc_stripped.c}"
quickjs_fixture="${QUICKJS_PREPROCESSED_OUTPUT:-/tmp/quickjs_preprocessed.c}"

ensure_external_parser_fixtures() {
  if [[ -s "${tinycc_fixture}" && -s "${quickjs_fixture}" ]]; then
    return
  fi

  echo "==> fetch external parser fixtures"
  scripts/fetch-external-parser-fixtures.sh
}

echo "==> check strict MIR clang-driver fixture coverage"
scripts/check-strict-mir-interop.sh

echo "==> check linux has-builtin coverage"
scripts/check-linux-has-builtin-coverage.sh

core_packages=(
  target
  parser
  preprocessor
  codegen
  mir_codegen
  cmd/main
  jit
)

echo "==> moon test core packages (${target})"
moon test --target "${target}" "${core_packages[@]}"

ensure_external_parser_fixtures

echo "==> moon test e2e files individually (${target})"
while IFS= read -r test_file; do
  if [[ "${test_file}" == "test/e2e/harness_test.mbt" ]]; then
    continue
  fi
  echo "==> ${test_file}"
  moon test --target "${target}" "${test_file}"
done < <(find test/e2e -maxdepth 1 -name '*_test.mbt' | sort)
