#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cat > /tmp/c4_minimal.c << 'INNEREOF'
#include "minimal_stubs.h"
INNEREOF

grep -v '#include' "$SCRIPT_DIR/c4.c" >> /tmp/c4_minimal.c

clang -E -P /tmp/c4_minimal.c > /tmp/c4_preprocessed.c

"$PROJECT_DIR/_build/native/debug/build/cmd/main/main.exe" "$(cat /tmp/c4_preprocessed.c)" > /tmp/c4_out.s

clang -o /tmp/c4_bin /tmp/c4_out.s

echo "SUCCESS: c4.c compiled and linked!"
echo "Binary: /tmp/c4_bin"
