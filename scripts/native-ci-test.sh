#!/usr/bin/env bash
set -euo pipefail

target="${MOON_TARGET:-native}"

core_packages=(
  target
  parser
  preprocessor
  codegen
  cmd/main
  jit
)

echo "==> moon test core packages (${target})"
moon test --target "${target}" "${core_packages[@]}"

echo "==> moon test e2e files individually (${target})"
while IFS= read -r test_file; do
  if [[ "${test_file}" == "test/e2e/harness_test.mbt" ]]; then
    continue
  fi
  echo "==> ${test_file}"
  moon test --target "${target}" "${test_file}"
done < <(find test/e2e -maxdepth 1 -name '*_test.mbt' | sort)
