#!/usr/bin/env bash
set -euo pipefail

support_file="${1:-preprocessor/macro_expand.mbt}"
preprocessor_test="${2:-preprocessor/preprocessor_test.mbt}"
linux_smoke="${3:-scripts/linux-amd64-smoke.sh}"

for path in "${support_file}" "${preprocessor_test}" "${linux_smoke}"; do
  if [[ ! -f "${path}" ]]; then
    echo "linux has-builtin coverage input not found: ${path}" >&2
    exit 2
  fi
done

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

supported="${tmpdir}/supported"
preprocessor_covered="${tmpdir}/preprocessor-covered"
smoke_covered="${tmpdir}/smoke-covered"

perl -ne '
  if (/fn pp_linux_amd64_has_builtin/) {
    $in = 1;
  }
  next unless $in;
  while (/"([^"]+)"/g) {
    print "$1\n";
  }
  if (/=> true/) {
    exit;
  }
' "${support_file}" | sort -u > "${supported}"

perl -ne '
  while (/__has_builtin\(([^)]+)\)/g) {
    print "$1\n";
  }
' "${preprocessor_test}" | sort -u > "${preprocessor_covered}"

perl -ne '
  while (/__has_builtin\(([^)]+)\)/g) {
    print "$1\n";
  }
' "${linux_smoke}" | sort -u > "${smoke_covered}"

status=0

missing_preprocessor="$(comm -23 "${supported}" "${preprocessor_covered}")"
if [[ -n "${missing_preprocessor}" ]]; then
  echo "preprocessor has-builtin test is missing supported Linux builtins:" >&2
  while IFS= read -r name; do
    echo "  ${name}" >&2
  done <<< "${missing_preprocessor}"
  status=1
fi

missing_smoke="$(comm -23 "${supported}" "${smoke_covered}")"
if [[ -n "${missing_smoke}" ]]; then
  echo "linux-amd64 smoke has-builtin gates are missing supported builtins:" >&2
  while IFS= read -r name; do
    echo "  ${name}" >&2
  done <<< "${missing_smoke}"
  status=1
fi

if [[ "${status}" -ne 0 ]]; then
  exit "${status}"
fi

echo "linux __has_builtin coverage is complete"
