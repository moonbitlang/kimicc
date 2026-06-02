#!/usr/bin/env bash
set -euo pipefail

selected="${KIMICC_EXTERNAL_TESTBED:-all}"
tinycc_fixture="${TINYCC_PREPROCESSED_OUTPUT:-/tmp/tinycc_stripped.c}"

missing=()

usage() {
  cat <<'EOF'
usage: KIMICC_EXTERNAL_TESTBED=<name|all-supported|all> scripts/check-external-testbed-assets.sh

Checks that the opt-in external compiler testbed sources expected by
test/e2e/external_testbeds_test.mbt are present under their documented /tmp
paths. This script verifies prerequisites only; it does not download sources.
EOF
}

if (( $# > 1 )); then
  usage >&2
  exit 2
elif (( $# == 1 )); then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      selected="$1"
      ;;
  esac
fi

require_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "${path}" ]]; then
    missing+=("${label}: ${path}")
  fi
}

require_nonempty_file() {
  local path="$1"
  local label="$2"
  if [[ ! -s "${path}" ]]; then
    missing+=("${label}: ${path}")
  fi
}

check_tinycc() {
  require_nonempty_file "${tinycc_fixture}" "TinyCC stripped preprocessed source"
}

check_quickjs() {
  local root="/tmp/kimicc_quickjs_build"
  local name
  for name in quickjs libregexp libunicode cutils quickjs-libc repl qjs dtoa; do
    require_nonempty_file "${root}/${name}.i" "QuickJS preprocessed ${name}.i"
  done
}

check_zlib() {
  local root="/tmp/kimicc_zlib/zlib-1.3.1"
  local name
  require_file "${root}/zlib.h" "zlib public header"
  for name in adler32 compress crc32 deflate infback inffast inflate inftrees trees uncompr zutil; do
    require_file "${root}/${name}.c" "zlib source ${name}.c"
  done
}

check_xxhash() {
  local root="/tmp/kimicc_xxhash/xxHash-0.8.2"
  require_file "${root}/xxhash.h" "xxHash public header"
  require_file "${root}/xxhash.c" "xxHash source"
}

check_cjson() {
  local root="/tmp/kimicc_cjson/cJSON-1.7.18"
  require_file "${root}/cJSON.h" "cJSON public header"
  require_file "${root}/cJSON.c" "cJSON source"
}

check_inih() {
  local root="/tmp/kimicc_inih/inih-r58"
  require_file "${root}/ini.h" "inih public header"
  require_file "${root}/ini.c" "inih source"
}

check_lua() {
  local root="/tmp/kimicc_lua/lua-5.4.6/src"
  local name
  for name in \
    lapi lcode lctype ldebug ldo ldump lfunc lgc llex lmem lobject lopcodes \
    lparser lstate lstring ltable ltm lundump lvm lzio lauxlib lbaselib \
    lcorolib ldblib liolib lmathlib loadlib loslib lstrlib ltablib lutf8lib \
    linit lua; do
    require_file "${root}/${name}.c" "Lua source ${name}.c"
  done
}

check_tree_sitter() {
  local root="/tmp/kimicc_tree_sitter"
  local name
  require_file "${root}/lib/include/tree_sitter/api.h" "tree-sitter public header"
  require_file "${root}/src/parser.c" "tree-sitter mini parser"
  for name in \
    alloc get_changed_ranges language lexer node parser point query stack subtree \
    tree tree_cursor wasm_store; do
    require_file "${root}/lib/src/${name}.c" "tree-sitter runtime ${name}.c"
  done
}

check_ocamlyacc() {
  local root="/tmp/kimicc_ocaml"
  local name
  require_file "${root}/testsuite/tests/tool-lexyacc/calc_parser.mly" "ocamlyacc calc grammar"
  require_file "${root}/testsuite/tests/tool-lexyacc/parsecheck.mly" "ocamlyacc parsecheck grammar"
  for name in mkpar skeleton lr0 warshall closure reader main error lalr verbose output symtab; do
    require_file "${root}/yacc/${name}.c" "ocamlyacc source ${name}.c"
  done
}

check_all_supported() {
  check_tinycc
  check_quickjs
  check_zlib
  check_xxhash
  check_cjson
  check_inih
  check_lua
}

check_one() {
  case "$1" in
    tinycc) check_tinycc ;;
    quickjs) check_quickjs ;;
    zlib) check_zlib ;;
    xxhash) check_xxhash ;;
    cjson) check_cjson ;;
    inih) check_inih ;;
    lua) check_lua ;;
    tree-sitter) check_tree_sitter ;;
    ocamlyacc) check_ocamlyacc ;;
    all-supported)
      check_all_supported
      ;;
    all)
      check_all_supported
      check_tree_sitter
      check_ocamlyacc
      ;;
    *)
      echo "unknown KIMICC_EXTERNAL_TESTBED value: $1" >&2
      echo "expected one of: tinycc quickjs zlib xxhash cjson inih lua tree-sitter ocamlyacc all-supported all" >&2
      exit 2
      ;;
  esac
}

check_one "${selected}"

if (( ${#missing[@]} > 0 )); then
  echo "missing external testbed assets for KIMICC_EXTERNAL_TESTBED=${selected}:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  echo >&2
  echo "For TinyCC parser fixtures, run scripts/fetch-external-parser-fixtures.sh." >&2
  echo "For QuickJS full-build fixtures, run scripts/fetch-external-testbed-sources.sh quickjs." >&2
  echo "For zlib, xxHash, cJSON, inih, and Lua sources, run scripts/fetch-external-testbed-sources.sh tarballs." >&2
  echo "For the automated subset, run both fetch scripts, then use KIMICC_EXTERNAL_TESTBED=all-supported." >&2
  echo "tree-sitter generated parsers and ocamlyacc require separate setup." >&2
  exit 1
fi

echo "external testbed assets are present for KIMICC_EXTERNAL_TESTBED=${selected}"
