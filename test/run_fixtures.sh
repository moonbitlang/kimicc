#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILER="$PROJECT_DIR/_build/native/debug/build/cmd/main/main.exe"
RUN_DIR="/tmp/kimicc_run_fixtures"

mkdir -p "$RUN_DIR"

PASS=0
FAIL=0

run_test() {
  local name="$1"
  local source_file="$2"
  local expected_exit="$3"

  local asm_file="$RUN_DIR/${name}.s"
  local bin_file="$RUN_DIR/${name}"

  "$COMPILER" "$(cat "$source_file")" > "$asm_file"
  clang -o "$bin_file" "$asm_file"

  set +e
  "$bin_file"
  local actual_exit=$?
  set -e

  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "PASS: $name (exit=$actual_exit)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name (expected exit=$expected_exit, got $actual_exit)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Running kimicc compile+run fixtures ==="

run_test "return_42"       "$SCRIPT_DIR/run_fixtures/return_42.c"       42
run_test "add"             "$SCRIPT_DIR/run_fixtures/add.c"             7
run_test "if_else"         "$SCRIPT_DIR/run_fixtures/if_else.c"         20
run_test "while_loop"      "$SCRIPT_DIR/run_fixtures/while_loop.c"      10
run_test "for_loop"        "$SCRIPT_DIR/run_fixtures/for_loop.c"        15
run_test "switch_case"     "$SCRIPT_DIR/run_fixtures/switch_case.c"     30
run_test "pointers"        "$SCRIPT_DIR/run_fixtures/pointers.c"        50
run_test "globals"         "$SCRIPT_DIR/run_fixtures/globals.c"         2
run_test "funcall"         "$SCRIPT_DIR/run_fixtures/funcall.c"         25
run_test "bitwise"         "$SCRIPT_DIR/run_fixtures/bitwise.c"         255
run_test "ternary"         "$SCRIPT_DIR/run_fixtures/ternary.c"         10
run_test "prepost"         "$SCRIPT_DIR/run_fixtures/prepost.c"         24
run_test "struct"          "$SCRIPT_DIR/run_fixtures/struct.c"          7
run_test "arrays"          "$SCRIPT_DIR/run_fixtures/arrays.c"          3
run_test "logic"           "$SCRIPT_DIR/run_fixtures/logic.c"           3

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
