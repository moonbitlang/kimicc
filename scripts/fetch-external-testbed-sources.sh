#!/usr/bin/env bash
set -euo pipefail

selected="${KIMICC_EXTERNAL_TESTBED:-tarballs}"

usage() {
  cat <<'EOF'
usage: scripts/fetch-external-testbed-sources.sh [tarballs|all-supported|zlib|xxhash|cjson|inih|lua]

Fetches archive-backed external compiler testbed source trees into the /tmp
paths consumed by test/e2e/external_testbeds_test.mbt.

Supported selectors:
  tarballs       fetch zlib, xxHash, cJSON, inih, and Lua source trees
  all-supported  alias for tarballs
  zlib           fetch zlib 1.3.1 into /tmp/kimicc_zlib/zlib-1.3.1
  xxhash         fetch xxHash 0.8.2 into /tmp/kimicc_xxhash/xxHash-0.8.2
  cjson          fetch cJSON 1.7.18 into /tmp/kimicc_cjson/cJSON-1.7.18
  inih           fetch inih r58 into /tmp/kimicc_inih/inih-r58
  lua            fetch Lua 5.4.6 into /tmp/kimicc_lua/lua-5.4.6

QuickJS full-build fixtures, tree-sitter generated parser sources, and OCaml
ocamlyacc source trees require separate setup and are intentionally not
created by this script.
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

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required to fetch external testbed sources" >&2
    exit 1
  fi
}

require_tool curl
require_tool tar

temp_dirs=()

cleanup() {
  local dir
  if (( ${#temp_dirs[@]} == 0 )); then
    return
  fi
  for dir in "${temp_dirs[@]}"; do
    rm -rf "${dir}"
  done
}

trap cleanup EXIT

fetch_tarball() {
  local name="$1"
  local url="$2"
  local parent="$3"
  local top_dir="$4"
  local final="${parent}/${top_dir}"
  local tmp_dir
  local archive

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/kimicc_${name}.XXXXXX")"
  temp_dirs+=("${tmp_dir}")
  archive="${tmp_dir}/${name}.tar.gz"

  echo "fetching ${name} from ${url}"
  curl -fsSL --retry 3 --retry-delay 1 "${url}" -o "${archive}"
  tar -xzf "${archive}" -C "${tmp_dir}"

  if [[ ! -d "${tmp_dir}/${top_dir}" ]]; then
    echo "archive for ${name} did not contain expected top-level directory: ${top_dir}" >&2
    exit 1
  fi

  mkdir -p "${parent}"
  rm -rf "${final}"
  mv "${tmp_dir}/${top_dir}" "${final}"
  echo "${name} sources ready: ${final}"
}

fetch_zlib() {
  fetch_tarball \
    "zlib" \
    "https://zlib.net/fossils/zlib-1.3.1.tar.gz" \
    "/tmp/kimicc_zlib" \
    "zlib-1.3.1"
}

fetch_xxhash() {
  fetch_tarball \
    "xxhash" \
    "https://github.com/Cyan4973/xxHash/archive/refs/tags/v0.8.2.tar.gz" \
    "/tmp/kimicc_xxhash" \
    "xxHash-0.8.2"
}

fetch_cjson() {
  fetch_tarball \
    "cjson" \
    "https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.18.tar.gz" \
    "/tmp/kimicc_cjson" \
    "cJSON-1.7.18"
}

fetch_inih() {
  fetch_tarball \
    "inih" \
    "https://github.com/benhoyt/inih/archive/refs/tags/r58.tar.gz" \
    "/tmp/kimicc_inih" \
    "inih-r58"
}

fetch_lua() {
  fetch_tarball \
    "lua" \
    "https://www.lua.org/ftp/lua-5.4.6.tar.gz" \
    "/tmp/kimicc_lua" \
    "lua-5.4.6"
}

fetch_tarball_testbeds() {
  fetch_zlib
  fetch_xxhash
  fetch_cjson
  fetch_inih
  fetch_lua
}

case "${selected}" in
  tarballs|all-supported)
    fetch_tarball_testbeds
    ;;
  zlib)
    fetch_zlib
    ;;
  xxhash)
    fetch_xxhash
    ;;
  cjson)
    fetch_cjson
    ;;
  inih)
    fetch_inih
    ;;
  lua)
    fetch_lua
    ;;
  all|tinycc|quickjs|tree-sitter|ocamlyacc)
    echo "scripts/fetch-external-testbed-sources.sh cannot prepare KIMICC_EXTERNAL_TESTBED=${selected} completely." >&2
    echo "Use the tarballs selector for zlib, xxHash, cJSON, inih, and Lua only." >&2
    echo "Use scripts/fetch-external-parser-fixtures.sh for TinyCC parser fixtures." >&2
    echo "QuickJS full-build fixtures, tree-sitter generated parsers, and ocamlyacc require separate setup." >&2
    exit 2
    ;;
  *)
    echo "unknown external testbed source selector: ${selected}" >&2
    echo "expected one of: tarballs zlib xxhash cjson inih lua all-supported" >&2
    exit 2
    ;;
esac
