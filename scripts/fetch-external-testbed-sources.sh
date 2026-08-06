#!/usr/bin/env bash
set -euo pipefail

selected="${KIMICC_EXTERNAL_TESTBED:-tarballs}"
quickjs_ref="${QUICKJS_REF:-d7ae12ae71dfd6ab2997527d295014a8996fa0f9}"
quickjs_dir="${QUICKJS_SOURCE_DIR:-/tmp/quickjs-src}"
quickjs_build_dir="/tmp/kimicc_quickjs_build"

usage() {
  cat <<'EOF'
usage: scripts/fetch-external-testbed-sources.sh [all-supported|quickjs|tarballs|zlib|xxhash|cjson|inih|lua]

Fetches external compiler testbed source trees and generated fixtures into the
/tmp paths consumed by test/e2e/external_testbeds_test.mbt.

Supported selectors:
  all-supported  fetch QuickJS full-build fixtures plus tarball source trees
  quickjs        fetch pinned QuickJS and preprocess qjs build sources
  tarballs       fetch zlib, xxHash, cJSON, inih, and Lua source trees
  zlib           fetch zlib 1.3.1 into /tmp/kimicc_zlib/zlib-1.3.1
  xxhash         fetch xxHash 0.8.2 into /tmp/kimicc_xxhash/xxHash-0.8.2
  cjson          fetch cJSON 1.7.18 into /tmp/kimicc_cjson/cJSON-1.7.18
  inih           fetch inih r58 into /tmp/kimicc_inih/inih-r58
  lua            fetch Lua 5.4.6 into /tmp/kimicc_lua/lua-5.4.6

tree-sitter generated parser sources and OCaml ocamlyacc source trees require
separate setup and are intentionally not created by this script.
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

  require_tool curl
  require_tool tar

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

# Retried for the same reason as in fetch-external-parser-fixtures.sh: a
# transient fetch failure should not fail the run.
testbed_fetch_attempts="${FIXTURE_FETCH_ATTEMPTS:-3}"

retry_fetch() {
  local description="$1"
  shift
  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if [ "${attempt}" -ge "${testbed_fetch_attempts}" ]; then
      echo "${description} failed after ${attempt} attempt(s)" >&2
      return 1
    fi
    local delay=$((attempt * 5))
    echo "${description} failed (attempt ${attempt}/${testbed_fetch_attempts}); retrying in ${delay}s" >&2
    sleep "${delay}"
    attempt=$((attempt + 1))
  done
}

fetch_ref() {
  local url="$1"
  local ref="$2"
  local dir="$3"

  require_tool git

  # The refs are pinned, so an existing checkout at the same commit is still
  # valid and needs no network at all.
  if [ -d "${dir}/.git" ] &&
    [ "$(git -C "${dir}" rev-parse HEAD 2>/dev/null || true)" = "${ref}" ]; then
    echo "reusing ${dir}, already at ${ref}" >&2
    return 0
  fi

  rm -rf "${dir}"
  git init -q "${dir}"
  git -C "${dir}" remote add origin "${url}"
  retry_fetch "fetch of ${ref}" \
    git -C "${dir}" fetch --quiet --depth=1 origin "${ref}"
  git -C "${dir}" checkout -q --detach FETCH_HEAD
  test "$(git -C "${dir}" rev-parse HEAD)" = "${ref}"
}

fetch_quickjs() {
  local name
  local version

  require_tool clang
  require_tool make

  fetch_ref "https://github.com/bellard/quickjs.git" "${quickjs_ref}" "${quickjs_dir}"
  make -C "${quickjs_dir}" repl.c

  version="$(tr -d '\r\n' <"${quickjs_dir}/VERSION")"
  rm -rf "${quickjs_build_dir}"
  mkdir -p "${quickjs_build_dir}"
  for name in quickjs libregexp libunicode cutils quickjs-libc repl qjs dtoa; do
    clang -E -P \
      -I"${quickjs_dir}" \
      -D_GNU_SOURCE \
      -DCONFIG_VERSION="\"${version}\"" \
      -DCONFIG_CC="\"clang\"" \
      -DCONFIG_PREFIX="\"/usr/local\"" \
      "${quickjs_dir}/${name}.c" >"${quickjs_build_dir}/${name}.i"
  done
  echo "QuickJS full-build fixtures ready: ${quickjs_build_dir}"
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
  all-supported)
    fetch_quickjs
    fetch_tarball_testbeds
    ;;
  quickjs)
    fetch_quickjs
    ;;
  tarballs)
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
  all|tinycc|tree-sitter|ocamlyacc)
    echo "scripts/fetch-external-testbed-sources.sh cannot prepare KIMICC_EXTERNAL_TESTBED=${selected} completely." >&2
    echo "Use the quickjs selector for QuickJS full-build fixtures." >&2
    echo "Use the tarballs selector for zlib, xxHash, cJSON, inih, and Lua." >&2
    echo "Use scripts/fetch-external-parser-fixtures.sh for TinyCC parser fixtures." >&2
    echo "tree-sitter generated parsers and ocamlyacc require separate setup." >&2
    exit 2
    ;;
  *)
    echo "unknown external testbed source selector: ${selected}" >&2
    echo "expected one of: all-supported quickjs tarballs zlib xxhash cjson inih lua" >&2
    exit 2
    ;;
esac
