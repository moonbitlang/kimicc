#!/usr/bin/env bash
set -euo pipefail

fixture="${1:-test/e2e/strict_mir_codegen_test.mbt}"

if [[ ! -f "${fixture}" ]]; then
  echo "strict MIR interop fixture not found: ${fixture}" >&2
  exit 2
fi

missing="$(
  awk '
    /^fn strict_mir_[[:alnum:]_]+_source\(\) -> String/ {
      if (in_group && seen_test) {
        if (clang_driver_calls == 0) {
          print start_line ":" names
        }
        names = ""
        clang_driver_calls = 0
        seen_test = 0
        start_line = NR
      } else if (!in_group) {
        start_line = NR
      }

      name = $2
      sub(/\(.*/, "", name)
      names = names ? names "," name : name
      in_group = 1
    }

    /^test |^async test / {
      if (in_group) {
        seen_test = 1
      }
    }

    /run_strict_mir_with_clang_driver/ {
      if (in_group) {
        clang_driver_calls++
      }
    }

    END {
      if (in_group && seen_test && clang_driver_calls == 0) {
        print start_line ":" names
      }
    }
  ' "${fixture}"
)"

if [[ -n "${missing}" ]]; then
  echo "strict MIR fixture groups missing clang-driver interop coverage:" >&2
  while IFS= read -r line; do
    echo "  ${line}" >&2
  done <<< "${missing}"
  exit 1
fi

echo "strict MIR clang-driver interop fixture coverage is complete"
