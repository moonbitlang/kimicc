#!/bin/sh
# Optional check, not part of `moon test`: compile programs printed from the
# quickcheck generators with a real C compiler (default `cc`; set CC to
# override). Run from anywhere:
#
#   sh cfront/qc_test/cc_check.sh
#
# Exits nonzero if the compiler rejects any program, printing the first
# diagnostics of each rejected one.
set -eu
module_dir=$(cd "$(dirname "$0")/.." && pwd)
cc=${CC:-cc}
work=$(mktemp -d "${TMPDIR:-/tmp}/cfront-qc-cc.XXXXXX")
trap 'rm -rf "$work"' EXIT
(cd "$module_dir" && MOON_WORK=off moon test --target native \
  qc_test/cc_emit_test.mbt --include-skipped) > "$work/emitted.txt"
awk -v dir="$work" '
  $0 == "/*@@cfront-qc@@*/" { n++; file = sprintf("%s/p%04d.c", dir, n); next }
  n && file != "" { print > file }
' "$work/emitted.txt"
total=0
failed=0
for program in "$work"/p*.c; do
  # The final marker opens an empty file for the test summary; skip it.
  grep -q "typedef" "$program" || continue
  total=$((total + 1))
  # `a < b < c` is valid C, but recent Clang makes it an error by default
  # (-Wparentheses); the printer emits the minimal parentheses, so allow it.
  if ! "$cc" -std=gnu11 -fsyntax-only -w -Wno-error=parentheses \
    "$program" 2> "$program.err"; then
    failed=$((failed + 1))
    echo "rejected: $(basename "$program")"
    head -n 5 "$program.err"
  fi
done
echo "$cc accepted $((total - failed)) of $total printed programs"
[ "$failed" -eq 0 ]
