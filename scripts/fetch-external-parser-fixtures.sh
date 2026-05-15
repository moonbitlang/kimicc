#!/usr/bin/env bash
set -euo pipefail

tinycc_ref="${TINYCC_REF:-fad812360ba836b4ca6f52236d867476ff671633}"
tinycc_fetch_ref="${TINYCC_FETCH_REF:-mob}"
quickjs_ref="${QUICKJS_REF:-d7ae12ae71dfd6ab2997527d295014a8996fa0f9}"

tinycc_dir="${TINYCC_SOURCE_DIR:-/tmp/tinycc-src}"
quickjs_dir="${QUICKJS_SOURCE_DIR:-/tmp/quickjs-src}"
tinycc_output="${TINYCC_PREPROCESSED_OUTPUT:-/tmp/tinycc_stripped.c}"
quickjs_output="${QUICKJS_PREPROCESSED_OUTPUT:-/tmp/quickjs_preprocessed.c}"

fetch_ref() {
  local url="$1"
  local ref="$2"
  local dir="$3"
  local containing_ref="${4:-}"
  rm -rf "$dir"
  git init "$dir"
  git -C "$dir" remote add origin "$url"
  if git -C "$dir" fetch --depth=1 origin "$ref"; then
    git -C "$dir" checkout --detach FETCH_HEAD
  else
    if [ -z "$containing_ref" ]; then
      echo "failed to fetch $ref from $url" >&2
      exit 1
    fi
    echo "direct fetch of $ref failed; fetching containing ref $containing_ref" >&2
    git -C "$dir" fetch origin "$containing_ref"
    git -C "$dir" checkout --detach "$ref"
  fi
  test "$(git -C "$dir" rev-parse HEAD)" = "$ref"
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required to fetch external parser fixtures" >&2
    exit 1
  fi
}

require_tool git
require_tool clang
require_tool make

# tinycc preprocessed (used by test "parse tinycc stripped").
# configure + a partial build are required so that generated headers like
# tccdefs_.h exist before we preprocess tcc.c.
fetch_ref https://repo.or.cz/tinycc.git "$tinycc_ref" "$tinycc_dir" "$tinycc_fetch_ref"
(cd "$tinycc_dir" && ./configure --cc=clang && make tccdefs_.h)
clang -E -P -I"$tinycc_dir" "$tinycc_dir/tcc.c" > "$tinycc_output"

# quickjs preprocessed (used by test "parse quickjs preprocessed").
fetch_ref https://github.com/bellard/quickjs.git "$quickjs_ref" "$quickjs_dir"
clang -E -P -I"$quickjs_dir" \
  -DCONFIG_VERSION='"ci-snapshot"' \
  "$quickjs_dir/quickjs.c" > "$quickjs_output"

wc -l "$tinycc_output" "$quickjs_output"
