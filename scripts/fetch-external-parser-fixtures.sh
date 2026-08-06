#!/usr/bin/env bash
set -euo pipefail

tinycc_ref="${TINYCC_REF:-fad812360ba836b4ca6f52236d867476ff671633}"
tinycc_fetch_ref="${TINYCC_FETCH_REF:-mob}"
quickjs_ref="${QUICKJS_REF:-d7ae12ae71dfd6ab2997527d295014a8996fa0f9}"

tinycc_dir="${TINYCC_SOURCE_DIR:-/tmp/tinycc-src}"
quickjs_dir="${QUICKJS_SOURCE_DIR:-/tmp/quickjs-src}"
tinycc_output="${TINYCC_PREPROCESSED_OUTPUT:-/tmp/tinycc_stripped.c}"
quickjs_output="${QUICKJS_PREPROCESSED_OUTPUT:-/tmp/quickjs_preprocessed.c}"

# Network operations here fail transiently often enough to have broken CI on a
# commit that was green minutes earlier, so every one of them is retried.
fetch_attempts="${FIXTURE_FETCH_ATTEMPTS:-3}"

retry() {
  local attempts="$1"
  local description="$2"
  shift 2
  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if [ "${attempt}" -ge "${attempts}" ]; then
      echo "${description} failed after ${attempt} attempt(s)" >&2
      return 1
    fi
    local delay=$((attempt * 5))
    echo "${description} failed (attempt ${attempt}/${attempts}); retrying in ${delay}s" >&2
    sleep "${delay}"
    attempt=$((attempt + 1))
  done
}

have_commit() {
  git -C "$1" cat-file -e "${2}^{commit}" 2>/dev/null
}

fetch_ref() {
  local url="$1"
  local ref="$2"
  local dir="$3"
  local containing_ref="${4:-}"

  # Reuse a checkout that is already at the pinned commit. The fixtures never
  # move, so skipping the network entirely is the most reliable option there is.
  if [ -d "${dir}/.git" ] &&
    [ "$(git -C "${dir}" rev-parse HEAD 2>/dev/null || true)" = "${ref}" ]; then
    echo "reusing ${dir}, already at ${ref}" >&2
    return 0
  fi

  rm -rf "${dir}"
  git init -q "${dir}"
  git -C "${dir}" remote add origin "${url}"

  # Asking for the pinned commit directly is one round trip, but only works
  # when the server advertises unadvertised objects -- repo.or.cz intermittently
  # does not, which is what broke CI. Two attempts, then fall back rather than
  # burning the full retry budget on a server capability that will not change.
  if retry 2 "direct fetch of ${ref}" \
    git -C "${dir}" fetch --quiet --depth=1 origin "${ref}"; then
    git -C "${dir}" checkout -q --detach FETCH_HEAD
  elif [ -n "${containing_ref}" ]; then
    echo "falling back to containing ref ${containing_ref}" >&2
    # Deepen in stages instead of pulling the whole history up front: the pinned
    # commits are near the tip, so the first stage almost always suffices.
    local found=0
    for depth in 50 500 5000; do
      if retry "${fetch_attempts}" "fetch ${containing_ref} at depth ${depth}" \
          git -C "${dir}" fetch --quiet --depth="${depth}" origin "${containing_ref}" &&
        have_commit "${dir}" "${ref}"; then
        found=1
        break
      fi
    done
    if [ "${found}" -ne 1 ]; then
      retry "${fetch_attempts}" "full fetch of ${containing_ref}" \
        git -C "${dir}" fetch --quiet origin "${containing_ref}"
    fi
    git -C "${dir}" checkout -q --detach "${ref}"
  else
    echo "failed to fetch ${ref} from ${url}" >&2
    return 1
  fi

  test "$(git -C "${dir}" rev-parse HEAD)" = "${ref}"
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
