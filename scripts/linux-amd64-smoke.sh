#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "${KIMICC_REPO:-$(pwd)}" && pwd)"
default_smoke_image="kimicc-linux-amd64-smoke:ubuntu24.04"
smoke_image="${KIMICC_LINUX_AMD64_SMOKE_IMAGE:-}"

host_os="$(uname -s)"
host_arch="$(uname -m)"
needs_docker=0
if [ "${KIMICC_LINUX_AMD64_SMOKE_FORCE_DOCKER:-0}" = "1" ]; then
  needs_docker=1
elif [ "$host_os" != "Linux" ] || { [ "$host_arch" != "x86_64" ] && [ "$host_arch" != "amd64" ]; }; then
  needs_docker=1
fi

if [ "$needs_docker" = "1" ] &&
  [ "${KIMICC_LINUX_AMD64_SMOKE_IN_DOCKER:-0}" != "1" ]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "linux-amd64 smoke requires Docker on non-linux/amd64 hosts or when forced" >&2
    exit 1
  fi
  if [ -z "$smoke_image" ]; then
    if docker image inspect "$default_smoke_image" >/dev/null 2>&1; then
      smoke_image="$default_smoke_image"
    elif [ "${KIMICC_LINUX_AMD64_SMOKE_BUILD_IMAGE:-0}" = "1" ]; then
      scripts/build-linux-amd64-smoke-image.sh
      smoke_image="$default_smoke_image"
    else
      smoke_image="ubuntu:24.04"
    fi
  fi
  exec docker run --rm --platform linux/amd64 \
    -e KIMICC_LINUX_AMD64_SMOKE_IN_DOCKER=1 \
    -e KIMICC_REPO=/work \
    -v "$repo:/work" \
    -w /work \
    "$smoke_image" \
    bash scripts/linux-amd64-smoke.sh
fi

workdir="$(mktemp -d /tmp/kimicc-linux-amd64.XXXXXX)"
trap 'rm -rf "$workdir"' EXIT

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

if ! command -v clang >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
    apt_install ca-certificates curl clang file git
  else
    echo "clang is required; install clang or run this script in the documented Ubuntu container" >&2
    exit 1
  fi
fi

if ! command -v git >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
    apt_install git
  else
    echo "git is required for moon update" >&2
    exit 1
  fi
fi

if ! command -v python3 >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
    apt_install python3
  else
    echo "python3 is required for the expected-failure smoke probe" >&2
    exit 1
  fi
fi

if ! command -v moon >/dev/null 2>&1; then
  if ! command -v curl >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
      apt_install ca-certificates curl
    else
      echo "curl is required to install MoonBit" >&2
      exit 1
    fi
  fi
  curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
  export PATH="$HOME/.moon/bin:$PATH"
fi

tar --exclude='.git' --exclude='_build' -cf - -C "$repo" . | tar -xf - -C "$workdir"
cd "$workdir"

moon update
moon build --target native
kimicc="./_build/native/debug/build/cmd/main/main.exe"
if [ ! -x "$kimicc" ]; then
  echo "expected built compiler at $kimicc" >&2
  exit 1
fi
moon test target --target native
moon test codegen --target native
moon test cmd/main --target native
moon test preprocessor --target native

expect_compile_failure() {
  local label="$1"
  local source="$2"
  rm -f "$bad_asm_path"
  set +e
  python3 - "$kimicc" "$bad_asm_path" "$source" "$bad_stdout_path" "$bad_stderr_path" <<'PY'
import subprocess
import sys

compiler, asm_path, source_path, stdout_path, stderr_path = sys.argv[1:]
with open(stdout_path, "wb") as stdout, open(stderr_path, "wb") as stderr:
    proc = subprocess.run(
        [compiler, "-S", "-target", "linux-amd64", "-o", asm_path, source_path],
        stdout=stdout,
        stderr=stderr,
    )
code = proc.returncode
if code < 0:
    code = 128 + (-code)
sys.exit(code)
PY
  compile_status=$?
  set -e
  if [ "$compile_status" -eq 0 ]; then
    echo "expected $label to fail compilation" >&2
    exit 1
  fi
  if [ -e "$bad_asm_path" ]; then
    echo "$label unexpectedly produced assembly" >&2
    exit 1
  fi
}

source_path="/tmp/kimicc-linux-amd64-smoke.c"
object_path="/tmp/kimicc-linux-amd64-smoke.o"
dependency_path="/tmp/kimicc-linux-amd64-smoke.d"
dependency_stdout_path="/tmp/kimicc-linux-amd64-smoke-mm.out"
binary_path="/tmp/kimicc-linux-amd64-smoke"
libc_runtime_source_path="/tmp/kimicc-linux-amd64-libc-runtime.c"
libc_runtime_binary_path="/tmp/kimicc-linux-amd64-libc-runtime"
pthread_source_path="/tmp/kimicc-linux-amd64-pthread.c"
pthread_binary_path="/tmp/kimicc-linux-amd64-pthread"
posix_runtime_source_path="/tmp/kimicc-linux-amd64-posix-runtime.c"
posix_runtime_binary_path="/tmp/kimicc-linux-amd64-posix-runtime"
ctor_source_path="/tmp/kimicc-linux-amd64-ctor.c"
ctor_binary_path="/tmp/kimicc-linux-amd64-ctor"
libm_source_path="/tmp/kimicc-linux-amd64-libm.c"
libm_binary_path="/tmp/kimicc-linux-amd64-libm"
dlfcn_source_path="/tmp/kimicc-linux-amd64-dlfcn.c"
dlfcn_binary_path="/tmp/kimicc-linux-amd64-dlfcn"
multi_main_source_path="/tmp/kimicc-linux-amd64-multi-main.c"
multi_helper_source_path="/tmp/kimicc-linux-amd64-multi-helper.c"
multi_main_object_path="/tmp/kimicc-linux-amd64-multi-main.o"
multi_helper_object_path="/tmp/kimicc-linux-amd64-multi-helper.o"
multi_main_dependency_path="/tmp/kimicc-linux-amd64-multi-main.d"
multi_helper_dependency_path="/tmp/kimicc-linux-amd64-multi-helper.d"
multi_binary_path="/tmp/kimicc-linux-amd64-multi"
multi_dependency_path="/tmp/kimicc-linux-amd64-multi.d"
extensionless_source_path="/tmp/kimicc-linux-amd64-extensionless"
asm_source_path="/tmp/kimicc-linux-amd64-asm.s"
asm_object_path="/tmp/kimicc-linux-amd64-asm.o"
asm_binary_path="/tmp/kimicc-linux-amd64-asm"
second_asm_source_path="/tmp/kimicc-linux-amd64-asm-second.s"
second_asm_object_path="/tmp/kimicc-linux-amd64-asm-second.o"
forced_asm_source_path="/tmp/kimicc-linux-amd64-forced-asm"
forced_asm_object_path="/tmp/kimicc-linux-amd64-forced-asm.o"
probe_include_dir="/tmp/kimicc-linux-amd64-include"
probe_after_include_dir="/tmp/kimicc-linux-amd64-include-after"
probe_prefix_dir="/tmp/kimicc-linux-amd64-prefix"
imacros_path="/tmp/kimicc-linux-amd64-imacros.h"
after_include_source_path="/tmp/kimicc-linux-amd64-include-after.c"
prefix_include_source_path="/tmp/kimicc-linux-amd64-prefix-include.c"
driver_stdout_path="/tmp/kimicc-linux-amd64-driver.out"
driver_stderr_path="/tmp/kimicc-linux-amd64-driver.err"
driver_query_path="/tmp/kimicc-linux-amd64-driver-query.out"
bad_source_path="/tmp/kimicc-linux-amd64-bad.c"
bad_asm_path="/tmp/kimicc-linux-amd64-bad.s"
bad_stdout_path="/tmp/kimicc-linux-amd64-bad.out"
bad_stderr_path="/tmp/kimicc-linux-amd64-bad.err"
link_fail_source_path="/tmp/kimicc-linux-amd64-link-fail.c"
link_fail_binary_path="/tmp/kimicc-linux-amd64-link-fail"
link_fail_stdout_path="/tmp/kimicc-linux-amd64-link-fail.out"
link_fail_stderr_path="/tmp/kimicc-linux-amd64-link-fail.err"
implicit_call_source_path="/tmp/kimicc-linux-amd64-implicit-call.c"
implicit_call_binary_path="/tmp/kimicc-linux-amd64-implicit-call"
old_source_path="/tmp/kimicc-linux-amd64-oldstyle.c"
old_helper_path="/tmp/kimicc-linux-amd64-oldstyle-helper.c"
old_object_path="/tmp/kimicc-linux-amd64-oldstyle.o"
old_helper_object_path="/tmp/kimicc-linux-amd64-oldstyle-helper.o"
old_binary_path="/tmp/kimicc-linux-amd64-oldstyle"
weak_source_path="/tmp/kimicc-linux-amd64-weak.c"
weak_helper_path="/tmp/kimicc-linux-amd64-weak-helper.c"
weak_object_path="/tmp/kimicc-linux-amd64-weak.o"
weak_helper_object_path="/tmp/kimicc-linux-amd64-weak-helper.o"
weak_binary_path="/tmp/kimicc-linux-amd64-weak"
ternary_source_path="/tmp/kimicc-linux-amd64-ternary.c"
ternary_binary_path="/tmp/kimicc-linux-amd64-ternary"
callee_saved_source_path="/tmp/kimicc-linux-amd64-callee-saved.c"
callee_saved_helper_path="/tmp/kimicc-linux-amd64-callee-saved-helper.s"
callee_saved_object_path="/tmp/kimicc-linux-amd64-callee-saved.o"
callee_saved_helper_object_path="/tmp/kimicc-linux-amd64-callee-saved-helper.o"
callee_saved_binary_path="/tmp/kimicc-linux-amd64-callee-saved"
int128_source_path="/tmp/kimicc-linux-amd64-int128.c"
int128_helper_path="/tmp/kimicc-linux-amd64-int128-helper.c"
int128_object_path="/tmp/kimicc-linux-amd64-int128.o"
int128_helper_object_path="/tmp/kimicc-linux-amd64-int128-helper.o"
int128_binary_path="/tmp/kimicc-linux-amd64-int128"
system_header_source_path="/tmp/kimicc-linux-amd64-system-headers.c"
system_header_preprocessed_path="/tmp/kimicc-linux-amd64-system-headers.i"
system_header_object_path="/tmp/kimicc-linux-amd64-system-headers.o"
system_header_binary_path="/tmp/kimicc-linux-amd64-system-headers"
header_syntax_source_path="/tmp/kimicc-linux-amd64-header-syntax.c"
va_list_source_path="/tmp/kimicc-linux-amd64-va-list.c"
va_list_binary_path="/tmp/kimicc-linux-amd64-va-list"
strict_mir_varargs_source_path="/tmp/kimicc-linux-amd64-strict-mir-varargs.c"
strict_mir_varargs_binary_path="/tmp/kimicc-linux-amd64-strict-mir-varargs"
strict_mir_returns_source_path="/tmp/kimicc-linux-amd64-strict-mir-returns.c"
strict_mir_returns_driver_path="/tmp/kimicc-linux-amd64-strict-mir-returns-driver.c"
strict_mir_returns_object_path="/tmp/kimicc-linux-amd64-strict-mir-returns.o"
strict_mir_returns_driver_object_path="/tmp/kimicc-linux-amd64-strict-mir-returns-driver.o"
strict_mir_returns_binary_path="/tmp/kimicc-linux-amd64-strict-mir-returns"
strict_mir_return_calls_source_path="/tmp/kimicc-linux-amd64-strict-mir-return-calls.c"
strict_mir_return_calls_binary_path="/tmp/kimicc-linux-amd64-strict-mir-return-calls"
strict_mir_return_args_source_path="/tmp/kimicc-linux-amd64-strict-mir-return-args.c"
strict_mir_return_args_binary_path="/tmp/kimicc-linux-amd64-strict-mir-return-args"
strict_mir_indirect_returns_source_path="/tmp/kimicc-linux-amd64-strict-mir-indirect-returns.c"
strict_mir_indirect_returns_binary_path="/tmp/kimicc-linux-amd64-strict-mir-indirect-returns"

mkdir -p "$probe_include_dir" "$probe_after_include_dir" "$probe_prefix_dir/headers"
cat > "$probe_include_dir/probe_header.h" <<'H'
#define KIMICC_PROBE_HEADER 1
H
cat > "$probe_after_include_dir/after_header.h" <<'H'
#define KIMICC_AFTER_HEADER 1
H
cat > "$probe_include_dir/pragma_once_header.h" <<'H'
#pragma once
int pragma_once_global = 7;
H
cat > "$probe_include_dir/base_file_header.h" <<'H'
const char *header_base_file = __BASE_FILE__;
const char *header_file_name = __FILE_NAME__;
int header_include_level = __INCLUDE_LEVEL__;
H
cat > "$probe_prefix_dir/headers/prefix_header.h" <<'H'
#define KIMICC_PREFIX_HEADER 7
H
cat > "$imacros_path" <<'H'
#define KIMICC_IMACROS_VALUE 37
int imacros_output_should_be_discarded = 1;
H

set +e
"$kimicc" >"$driver_stdout_path" 2>"$driver_stderr_path"
driver_status=$?
set -e
if [ "$driver_status" -eq 0 ]; then
  echo "expected no-input compiler invocation to fail" >&2
  exit 1
fi
if [ -s "$driver_stdout_path" ]; then
  echo "expected no-input compiler invocation to keep stdout empty" >&2
  exit 1
fi
grep -F 'error: no input file' "$driver_stderr_path" >/dev/null

"$kimicc" -v >"$driver_query_path"
grep -Fx 'kimicc 0.1.6' "$driver_query_path" >/dev/null
"$kimicc" --version >"$driver_query_path"
grep -Fx 'kimicc 0.1.6' "$driver_query_path" >/dev/null
"$kimicc" -target linux-amd64 -dumpmachine >"$driver_query_path"
grep -Fx 'x86_64-linux-gnu' "$driver_query_path" >/dev/null
"$kimicc" --target linux/amd64 --print-target-triple >"$driver_query_path"
grep -Fx 'x86_64-linux-gnu' "$driver_query_path" >/dev/null
"$kimicc" -target linux-amd64 -print-multiarch >"$driver_query_path"
grep -Fx 'x86_64-linux-gnu' "$driver_query_path" >/dev/null
"$kimicc" -target linux-amd64 -print-multi-directory >"$driver_query_path"
grep -Fx '.' "$driver_query_path" >/dev/null
"$kimicc" -target linux-amd64 -print-multi-os-directory >"$driver_query_path"
grep -Fx '../lib' "$driver_query_path" >/dev/null
set +e
"$kimicc" -target linux-amd64 -print-sysroot-headers-suffix \
  >"$driver_stdout_path" 2>"$driver_stderr_path"
driver_status=$?
set -e
if [ "$driver_status" -eq 0 ]; then
  echo "expected sysroot headers suffix query to fail without configured suffix" >&2
  exit 1
fi
if [ -s "$driver_stdout_path" ]; then
  echo "expected sysroot headers suffix failure to keep stdout empty" >&2
  exit 1
fi
grep -F 'not configured with sysroot headers suffix' "$driver_stderr_path" >/dev/null
"$kimicc" -target linux-amd64 -print-multi-lib >"$driver_query_path"
"$kimicc" -target linux-amd64 --print-file-name crt1.o >"$driver_query_path"
grep -F 'crt1.o' "$driver_query_path" >/dev/null
cat > "$source_path" <<'C'
#ifdef _REENTRANT
int threaded = _REENTRANT;
#else
int threaded = 0;
#endif
C
"$kimicc" -E -target linux-amd64 -pthread "$source_path" >"$driver_query_path"
grep -F 'int threaded=1;' "$driver_query_path" >/dev/null

cat > "$source_path" <<'C'
#ifdef __PIC__
int pic = __PIC__;
#else
int pic = 0;
#endif
#ifdef __PIE__
int pie = __PIE__;
#else
int pie = 0;
#endif
C
"$kimicc" -E -target linux-amd64 "$source_path" >"$driver_query_path"
grep -F 'int pic=2;' "$driver_query_path" >/dev/null
grep -F 'int pie=2;' "$driver_query_path" >/dev/null
"$kimicc" -E -target linux-amd64 -fPIE "$source_path" >"$driver_query_path"
grep -F 'int pic=2;' "$driver_query_path" >/dev/null
grep -F 'int pie=2;' "$driver_query_path" >/dev/null
"$kimicc" -E -target linux-amd64 -fPIE -fno-pie "$source_path" >"$driver_query_path"
grep -F 'int pic=0;' "$driver_query_path" >/dev/null
grep -F 'int pie=0;' "$driver_query_path" >/dev/null

cat > "$source_path" <<'C'
#ifdef __STDC_HOSTED__
int hosted = __STDC_HOSTED__;
#else
int hosted = -1;
#endif
C
"$kimicc" -E -target linux-amd64 -ffreestanding "$source_path" >"$driver_query_path"
grep -F 'int hosted=0;' "$driver_query_path" >/dev/null
"$kimicc" -E -target linux-amd64 -D__STDC_HOSTED__=9 -ffreestanding "$source_path" >"$driver_query_path"
grep -F 'int hosted=9;' "$driver_query_path" >/dev/null

cat > "$source_path" <<'C'
#ifdef __STDC_VERSION__
long version = __STDC_VERSION__;
#else
long version = 0;
#endif
#ifdef __STRICT_ANSI__
int strict = __STRICT_ANSI__;
#else
int strict = 0;
#endif
#ifdef __OPTIMIZE__
int optimize = __OPTIMIZE__;
#else
int optimize = 0;
#endif
#ifdef __FAST_MATH__
int fast = __FAST_MATH__;
#else
int fast = 0;
#endif
C
"$kimicc" -E -target linux-amd64 -std=c99 -O2 -ffast-math "$source_path" >"$driver_query_path"
grep -F 'long version=199901L;' "$driver_query_path" >/dev/null
grep -F 'int strict=1;' "$driver_query_path" >/dev/null
grep -F 'int optimize=1;' "$driver_query_path" >/dev/null
grep -F 'int fast=1;' "$driver_query_path" >/dev/null
"$kimicc" -E -target linux-amd64 -std=gnu89 -Ofast -O0 "$source_path" >"$driver_query_path"
grep -F 'long version=0;' "$driver_query_path" >/dev/null
grep -F 'int strict=0;' "$driver_query_path" >/dev/null
grep -F 'int optimize=0;' "$driver_query_path" >/dev/null
grep -F 'int fast=0;' "$driver_query_path" >/dev/null

cat > "$source_path" <<'C'
const char *source_file = __FILE__;
const char *source_file_name = __FILE_NAME__;
const char *base_file = __BASE_FILE__;
int include_level = __INCLUDE_LEVEL__;
#include "base_file_header.h"
#line 7 "/tmp/kimicc-linux-amd64/generated.h"
const char *line_file = __FILE__;
const char *line_file_name = __FILE_NAME__;
C
"$kimicc" -E -target linux-amd64 -fmacro-prefix-map=/tmp=/mapped \
  -ffile-prefix-map="$source_path"=/project/source.c \
  -I "$probe_include_dir" "$source_path" >"$driver_query_path"
grep -F 'const char*source_file="/project/source.c";' "$driver_query_path" >/dev/null
grep -F 'const char*source_file_name="kimicc-linux-amd64-smoke.c";' "$driver_query_path" >/dev/null
grep -F 'const char*base_file="/project/source.c";' "$driver_query_path" >/dev/null
grep -F 'int include_level=0;' "$driver_query_path" >/dev/null
grep -F 'const char*header_base_file="/project/source.c";' "$driver_query_path" >/dev/null
grep -F 'const char*header_file_name="base_file_header.h";' "$driver_query_path" >/dev/null
grep -F 'int header_include_level=1;' "$driver_query_path" >/dev/null
grep -F 'const char*line_file="/tmp/kimicc-linux-amd64/generated.h";' "$driver_query_path" >/dev/null
grep -F 'const char*line_file_name="generated.h";' "$driver_query_path" >/dev/null

cat > "$source_path" <<'C'
#define DUMPED 31
#undef __STDC_HOSTED__
int not_preprocessed_output = DUMPED;
C
"$kimicc" -E -dM -target linux-amd64 -DCLI_MACRO=17 "$source_path" >"$driver_query_path"
grep -F '#define CLI_MACRO 17' "$driver_query_path" >/dev/null
grep -F '#define DUMPED 31' "$driver_query_path" >/dev/null
grep -F '#define __x86_64__ 1' "$driver_query_path" >/dev/null
grep -F '#define __CHAR16_TYPE__ unsigned short' "$driver_query_path" >/dev/null
grep -F '#define __GCC_HAVE_SYNC_COMPARE_AND_SWAP_8 1' "$driver_query_path" >/dev/null
grep -F '#define __INT64_FMTd__ "ld"' "$driver_query_path" >/dev/null
grep -F '#define __UINT64_C_SUFFIX__ UL' "$driver_query_path" >/dev/null
grep -F '#define __SIZE_FMTu__ "lu"' "$driver_query_path" >/dev/null
if grep -F '#define __STDC_HOSTED__' "$driver_query_path" >/dev/null; then
  echo "expected -dM to honor source undefinition of __STDC_HOSTED__" >&2
  exit 1
fi
if grep -F 'not_preprocessed_output' "$driver_query_path" >/dev/null; then
  echo "expected -dM to suppress normal preprocessed source output" >&2
  exit 1
fi
printf '#define STDIN_MACRO 23\n' |
  "$kimicc" -E -dM -target linux-amd64 - >"$driver_query_path"
grep -F '#define STDIN_MACRO 23' "$driver_query_path" >/dev/null
printf '#define USER_UNDEF_MACRO 29\n' |
  "$kimicc" -E -dM -undef -target linux-amd64 -DCLI_MACRO=17 - >"$driver_query_path"
grep -F '#define CLI_MACRO 17' "$driver_query_path" >/dev/null
grep -F '#define USER_UNDEF_MACRO 29' "$driver_query_path" >/dev/null
grep -F '#define __STDC__ 1' "$driver_query_path" >/dev/null
if grep -F '#define __x86_64__' "$driver_query_path" >/dev/null; then
  echo "expected -undef to suppress target predefined macros" >&2
  exit 1
fi
cat > "$source_path" <<'C'
#ifdef KIMICC_IMACROS_VALUE
int imacros_value = KIMICC_IMACROS_VALUE;
#else
int imacros_value = 0;
#endif
C
"$kimicc" -E -target linux-amd64 -imacros "$imacros_path" "$source_path" >"$driver_query_path"
grep -F 'int imacros_value=37;' "$driver_query_path" >/dev/null
if grep -F 'imacros_output_should_be_discarded' "$driver_query_path" >/dev/null; then
  echo "expected -imacros to discard ordinary output from the macro file" >&2
  exit 1
fi
cat > "$source_path" <<'C'
#include "generated/config.h"
#include <generated/system.h>
int generated_dependency_probe = 1;
C
"$kimicc" -M -MG -target linux-amd64 "$source_path" >"$driver_query_path"
grep -F 'generated/config.h' "$driver_query_path" >/dev/null
grep -F 'generated/system.h' "$driver_query_path" >/dev/null
set +e
"$kimicc" -MD -MG -target linux-amd64 "$source_path" \
  >"$driver_stdout_path" 2>"$driver_stderr_path"
driver_status=$?
set -e
if [ "$driver_status" -eq 0 ]; then
  echo "expected -MG with -MD to fail outside dependency-only mode" >&2
  exit 1
fi
grep -F "option '-MG' requires '-M' or '-MM'" "$driver_stderr_path" >/dev/null

cat > "$bad_source_path" <<'C'
_Static_assert(0, "linux smoke expects this failure");
int main(void) { return 0; }
C
expect_compile_failure "invalid C smoke source" "$bad_source_path"

cat > "$bad_source_path" <<'C'
_Float16 unsupported_half;
int main(void) { return unsupported_half == (_Float16)0; }
C
expect_compile_failure "unsupported _Float16 value smoke source" "$bad_source_path"

cat > "$bad_source_path" <<'C'
__float128 unsupported_quad;
int main(void) { return unsupported_quad == 0; }
C
expect_compile_failure "unsupported __float128 smoke source" "$bad_source_path"

cat > "$bad_source_path" <<'C'
_Complex double unsupported_complex;
int main(void) { return 0; }
C
expect_compile_failure "unsupported _Complex smoke source" "$bad_source_path"

cat > "$bad_source_path" <<'C'
_BitInt(17) unsupported_bitint;
int main(void) { return 0; }
C
expect_compile_failure "unsupported _BitInt smoke source" "$bad_source_path"

cat > "$bad_source_path" <<'C'
_Decimal32 unsupported_decimal32;
int main(void) { return 0; }
C
expect_compile_failure "unsupported _Decimal32 smoke source" "$bad_source_path"

cat > "$bad_source_path" <<'C'
typedef float v4f __attribute__((vector_size(16)));
int main(void) { return 0; }
C
expect_compile_failure "unsupported vector_size smoke source" "$bad_source_path"

cat > "$bad_source_path" <<'C'
typedef float v4f __attribute__((mode(V4SF)));
int main(void) { return 0; }
C
expect_compile_failure "unsupported vector mode smoke source" "$bad_source_path"

cat > "$bad_source_path" <<'C'
long double unsupported_long_double;
int main(void) { return unsupported_long_double == 0.0L; }
C
expect_compile_failure "unsupported long double smoke source" "$bad_source_path"

cat > "$link_fail_source_path" <<'C'
int missing(void);
int main(void) { return missing(); }
C
rm -f "$link_fail_binary_path"
set +e
"$kimicc" -target linux-amd64 -o "$link_fail_binary_path" "$link_fail_source_path" \
  >"$link_fail_stdout_path" 2>"$link_fail_stderr_path"
link_status=$?
set -e
if [ "$link_status" -eq 0 ]; then
  echo "expected unresolved symbol smoke source to fail linking" >&2
  exit 1
fi
if [ -s "$link_fail_stdout_path" ]; then
  echo "expected unresolved symbol smoke source to keep stdout empty" >&2
  exit 1
fi
grep -F 'error: link failed with code 1' "$link_fail_stderr_path" >/dev/null

cat > "$implicit_call_source_path" <<'C'
int main(void) { return atoi("42"); }
C

"$kimicc" -target linux-amd64 -o "$implicit_call_binary_path" \
  "$implicit_call_source_path"
set +e
"$implicit_call_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected implicit external call smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$source_path" <<'C'
#include "pragma_once_header.h"
#include "pragma_once_header.h"

typedef __builtin_va_list va_list;

struct Pair {
  long a;
  long b;
};

struct DPair {
  double a;
  double b;
};

struct Mix {
  long a;
  double b;
};

struct RevMix {
  double a;
  long b;
};

struct Big {
  long a;
  long b;
  long c;
};

struct IArray {
  int v[2];
};

struct DArray {
  double v[2];
};

struct Nine {
  char v[9];
};

struct F3 {
  float v[3];
};

struct Inner {
  long a;
};

struct NestedMix {
  struct Inner i;
  double d;
};

struct AlignedBytes {
  char a;
  _Alignas(16) char b;
  char c;
};

_Alignas(32) long global_aligned = 1;

struct BigAligned {
  _Alignas(32) long a;
  long b;
  long c;
};

struct GnuAlignedBytes {
  char a;
  char b __attribute__((aligned(16)));
  char c;
};

long gnu_global_aligned __attribute__((aligned(32))) = 1;

struct GlobalInner {
  char c;
  int x;
};

struct GlobalOuter {
  char tag;
  struct GlobalInner inner;
  int tail;
};

struct GlobalBits {
  unsigned a : 3;
  signed b : 4;
  unsigned c : 5;
};

struct GlobalRefs {
  int *first;
  int *tail;
  int (*fn)(int);
};

struct GlobalNode {
  int value;
  struct GlobalNode *next;
};

union GlobalUnion {
  int i;
  char c[4];
};

union GlobalBitUnion {
  unsigned a : 3;
  signed b : 4;
};

union GlobalBox {
  double d;
  long l;
};

struct GlobalNested {
  union GlobalBox box;
  int tag;
  int arr[3];
};

struct GlobalPair {
  int a;
  int b;
};

int global_add1(int x) { return x + 1; }

int global_arr[5] = { 1, [3] = 4 };
int *global_ptr = global_arr + 3;
char *global_byte_ptr = (char *)global_arr + 12;
int *global_cast_ptr = (int *)((char *)global_arr + 12);
char *global_byte_subscript_ptr = &((char *)global_arr)[12];
int *global_cast_subscript_ptr = &((int *)((char *)global_arr + 8))[1];
int *global_addr = &global_arr[4];
int (*global_fp)(int) = global_add1;
int *global_ptrs[3] = { global_arr, global_arr + 2, &global_arr[4] };
struct GlobalOuter global_outer = { .tail = 9, .inner = { .x = 7, .c = 2 }, .tag = 1 };
struct GlobalBits global_bits = { .a = 5, .b = -3, .c = 17 };
struct GlobalRefs global_refs = { .tail = global_arr + 4, .fn = global_add1, .first = &global_arr[1] };
int *global_member = &global_outer.inner.x;
int *global_member_next = &global_outer.inner.x + 1;
struct GlobalNode global_node2 = { 2, 0 };
struct GlobalNode global_node1 = { .next = &global_node2, .value = 1 };
struct GlobalNode *global_nodes[2] = { &global_node1, &global_node2 };
union GlobalUnion global_union = { .c = { 65, 66, 0, 0 } };
union GlobalBitUnion global_bit_union = { .b = -3 };
struct GlobalNested global_nested = { .box.d = 1.5, .tag = 7, .arr[2] = 35 };
struct GlobalPair global_pairs[2] = { [1].b = 5, [0].a = 37 };
char global_string[6] = "hey";
double global_int_div = 1 / 2;
double global_fp_div = (double)1 / 2;
double global_cast_int_fp = (int)1.75;
int global_int_from_float = (int)1.75;
int global_fp_expr_to_int = (double)3 / 2;
unsigned long global_unsigned_div = (unsigned long)-1 / 2;
unsigned long global_unsigned_mod = (unsigned long)-1 % 2;
int global_unsigned_gt = (unsigned long)-1 > 1;
int global_unsigned_lt = (unsigned long)-1 < 1;
unsigned int global_unsigned_wrap = (unsigned int)-1 + 1;
unsigned int global_unsigned_shift = (unsigned int)-1 >> 31;
int global_unary_plus = +1;
int global_unary_plus_unsigned = +(unsigned int)-1 > 0;

int seventh(int a, int b, int c, int d, int e, int f, int g) { return g; }
double ninth(double a, double b, double c, double d, double e, double f, double g, double h, double i) { return i; }

struct Pair make_pair(long a, long b) {
  struct Pair p;
  p.a = a;
  p.b = b;
  return p;
}

int pair_sum(struct Pair p) { return (int)(p.a + p.b); }
int pair_tail(int a, int b, int c, int d, int e, int f, struct Pair p) { return (int)(p.a + p.b); }

struct DPair make_dpair(double a, double b) {
  struct DPair p;
  p.a = a;
  p.b = b;
  return p;
}

int dpair_sum(struct DPair p) { return (int)(p.a + p.b); }
int dpair_tail(double a, double b, double c, double d, double e, double f, double g, double h, struct DPair p) {
  return (int)(p.a + p.b);
}

struct Mix make_mix(long a, double b) {
  struct Mix m;
  m.a = a;
  m.b = b;
  return m;
}

int mix_sum(struct Mix m) { return (int)m.a + (int)m.b; }
int mix_tail(int a, int b, int c, int d, int e, int f, struct Mix m) { return (int)m.a + (int)m.b; }
int mix_tail_then_double(int a, int b, int c, int d, int e, int f, struct Mix m, double z) {
  return (int)m.a + (int)m.b + (int)z;
}

struct RevMix make_rmix(double a, long b) {
  struct RevMix m;
  m.a = a;
  m.b = b;
  return m;
}

int rmix_sum(struct RevMix m) { return (int)m.a + (int)m.b; }
int rmix_tail(double a, double b, double c, double d, double e, double f, double g, double h, struct RevMix m) {
  return (int)m.a + (int)m.b;
}

struct Big make_big(long a, long b, long c) {
  struct Big p;
  p.a = a;
  p.b = b;
  p.c = c;
  return p;
}

int big_sum(struct Big p) { return (int)(p.a + p.b + p.c); }
int big_tail(int a, int b, int c, int d, int e, int f, struct Big p) { return big_sum(p); }

struct IArray make_iarray(int a, int b) {
  struct IArray p;
  p.v[0] = a;
  p.v[1] = b;
  return p;
}

int iarray_sum(struct IArray p) { return p.v[0] + p.v[1]; }

struct DArray make_darray(double a, double b) {
  struct DArray p;
  p.v[0] = a;
  p.v[1] = b;
  return p;
}

double darray_sum(struct DArray p) { return p.v[0] + p.v[1]; }

struct NestedMix make_nested(long a, double b) {
  struct NestedMix p;
  p.i.a = a;
  p.d = b;
  return p;
}

int nested_sum(struct NestedMix p) { return (int)p.i.a + (int)p.d; }

struct Nine make_nine(char tail) {
  struct Nine n;
  n.v[0] = 3;
  n.v[1] = 4;
  n.v[2] = 5;
  n.v[3] = 6;
  n.v[4] = 7;
  n.v[5] = 8;
  n.v[6] = 9;
  n.v[7] = 10;
  n.v[8] = tail;
  return n;
}

int nine_sum(struct Nine n) { return n.v[0] + n.v[8]; }

struct F3 make_f3(float a, float b, float c) {
  struct F3 f;
  f.v[0] = a;
  f.v[1] = b;
  f.v[2] = c;
  return f;
}

float f3_sum(struct F3 f) { return f.v[0] + f.v[1] + f.v[2]; }

int nine_tail(int a, int b, int c, int d, int e, int f, struct Nine n) {
  return nine_sum(n);
}

float f3_tail(
  double a, double b, double c, double d,
  double e, double f, double g, double h,
  struct F3 p
) {
  return f3_sum(p);
}

int var_nine(int tag, ...) {
  va_list ap;
  struct Nine n;
  __builtin_va_start(ap, tag);
  n = __builtin_va_arg(ap, struct Nine);
  __builtin_va_end(ap);
  return nine_sum(n);
}

int var_f3(int tag, ...) {
  va_list ap;
  struct F3 f;
  __builtin_va_start(ap, tag);
  f = __builtin_va_arg(ap, struct F3);
  __builtin_va_end(ap);
  return (int)f3_sum(f);
}

int partial_aggregate_eightbytes(void) {
  struct Nine n = make_nine(39);
  struct F3 f = make_f3(1.0f, 2.0f, 39.0f);
  if (n.v[0] != 3 || n.v[8] != 39) return 585;
  if (nine_sum(n) != 42) return 586;
  if ((int)f.v[2] != 39) return 587;
  if ((int)f3_sum(f) != 42) return 588;
  if (var_nine(0, n) != 42) return 589;
  if (var_f3(0, f) != 42) return 590;
  if (nine_tail(1, 2, 3, 4, 5, 6, n) != 42) return 591;
  if ((int)f3_tail(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, f) != 42) {
    return 592;
  }
  return 0;
}

int aligned_offset(void) { return __builtin_offsetof(struct AlignedBytes, c); }
int aligned_global(void) { return (int)global_aligned; }
int gnu_aligned_offset(void) { return __builtin_offsetof(struct GnuAlignedBytes, c); }
int gnu_aligned_global(void) { return (int)gnu_global_aligned; }

struct BigAligned make_big_aligned(long value) {
  struct BigAligned p;
  p.a = value;
  p.b = 1;
  p.c = 2;
  return p;
}

int var_big_aligned(int tag, ...) {
  va_list ap;
  int value;
  __builtin_va_start(ap, tag);
  value = (int)__builtin_va_arg(ap, struct BigAligned).a;
  __builtin_va_end(ap);
  return value;
}

int aligned_aggregate_scratch(void) {
  struct BigAligned p = make_big_aligned(19);
  if ((int)make_big_aligned(23).a != 23) return 596;
  if (var_big_aligned(0, p) != 19) return 597;
  return 0;
}

int offsetof_designators(void) {
  if (__builtin_offsetof(struct NestedMix, i.a) != 0) return 556;
  if (__builtin_offsetof(struct IArray, v[1]) != 4) return 557;
  if (__builtin_offsetof(struct GlobalOuter, inner.x) != 8) return 558;
  return 0;
}

int global_cast_pointer_initializers(void) {
  if (*global_cast_ptr != 4) return 599;
  if (global_byte_ptr - (char *)global_arr != 12) return 600;
  if (*global_cast_subscript_ptr != 4) return 601;
  if (global_byte_subscript_ptr - (char *)global_arr != 12) return 602;
  if (global_int_div != 0.0) return 603;
  if (global_fp_div != 0.5) return 604;
  if (global_cast_int_fp != 1.0) return 605;
  if (global_int_from_float != 1) return 606;
  if (global_fp_expr_to_int != 1) return 607;
  if (global_unsigned_div != 9223372036854775807UL) return 608;
  if (global_unsigned_mod != 1UL) return 609;
  if (global_unsigned_gt != 1) return 610;
  if (global_unsigned_lt != 0) return 611;
  if (global_unsigned_wrap != 0U) return 612;
  if (global_unsigned_shift != 1U) return 613;
  if (global_unary_plus != 1) return 614;
  if (global_unary_plus_unsigned != 1) return 615;
  return 0;
}

int aligned_local(void) {
  _Alignas(32) char buf[32];
  long p;
  buf[0] = 1;
  p = (long)&buf[0];
  return (int)((p & 31) + buf[0] - 1);
}

int indirect_calls(void) {
  int (*ps)(struct Pair) = pair_sum;
  int (*ds)(struct DPair) = dpair_sum;
  struct Pair (*mk)(long, long) = make_pair;
  return (*ps)(mk(0, 1)) + ds(make_dpair(0.5, 0.5)) - 2;
}

struct Bits {
  unsigned int a : 3;
  int b : 4;
  unsigned int c : 5;
};

int bitfields(void) {
  struct Bits bits;
  bits.a = 5;
  bits.b = -3;
  bits.c = 17;
  bits.a += 1;
  bits.c >>= 1;
  if (bits.a != 6 || bits.b != -3 || bits.c != 8) return 64;
  bits.a = 2.9;
  bits.a *= 1.9;
  if (bits.a != 3) return 65;
  bits.b += 1.5;
  if (bits.b != -1) return 66;
  bits.c = 0;
  {
    float factor = 3.5f;
    bits.c += factor;
  }
  if (bits.c != 3) return 67;
  bits.a = 1;
  bits.a /= -1;
  if (bits.a != 7) return 68;
  bits.c = 2;
  bits.c %= -2;
  if (bits.c != 0) return 69;
  return 0;
}

int unsigned_ops(void) {
  unsigned int max = 4294967295U;
  unsigned int wrap = max + 1U;
  unsigned long one = 1;
  unsigned long hi = one << 63;
  return wrap == 0U &&
             max / 2U == 2147483647U &&
             max % 2U == 1U &&
             max > 1U &&
             !(max < 1U) &&
             max == -1 &&
             (max >> 31) == 1U &&
             hi > 1UL
           ? 0
           : 128;
}

_Bool truthy(long x) { return x; }
double takes_double(double x) { return x; }
int takes_int(int x) { return x; }
_Bool takes_bool(_Bool x) { return x; }
int takes_schar(signed char x) { return x; }
_Bool returns_bool(void) { return 256; }
signed char returns_schar(void) { return (signed char)255; }
unsigned char returns_uchar(void) { return (unsigned char)-1; }
short returns_short(void) { return (short)65535; }
unsigned short returns_ushort(void) { return (unsigned short)-1; }
unsigned int returns_uint(void) { return 4294967295U; }

int scalar_conversions(void) {
  _Bool b = 256;
  _Bool from_fp = 0.5;
  _Bool zero_fp = 0.0;
  signed char c = (signed char)255;
  unsigned char u = (unsigned char)-1;
  short s = (short)65535;
  if (!b) return 256;
  if (!from_fp) return 257;
  if (zero_fp) return 258;
  if (c != -1) return 259;
  if (u != 255) return 260;
  if (s != -1) return 261;
  if ((unsigned char)300 != 44) return 262;
  if (!truthy(256)) return 263;
  if ((int)takes_double(42) != 42) return 264;
  if (takes_int(42.9) != 42) return 265;
  if (!takes_bool(256)) return 266;
  if (takes_schar(255) != -1) return 267;
  if (!returns_bool()) return 268;
  if (returns_schar() != -1) return 269;
  if (returns_uchar() != 255) return 270;
  if (returns_short() != -1) return 271;
  if (returns_ushort() != 65535) return 272;
  if (!(returns_uint() > 0U)) return 273;
  {
    unsigned long one = 1;
    unsigned long hi = one << 63;
    unsigned long just_above_hi = hi + 4096UL;
    double d = (double)hi;
    double above = (double)just_above_hi;
    float f = (float)hi;
    if (!(d > 0.0)) return 274;
    if (!(f > 0.0f)) return 275;
    if ((unsigned long)d != hi) return 276;
    if ((unsigned long)f != hi) return 277;
    if ((unsigned long)above != just_above_hi) return 278;
    {
      unsigned long acc = 0;
      int signed_scale = 2;
      unsigned int unsigned_scale = 2;
      float factor = 1.9f;
      acc += above;
      signed_scale *= 1.9;
      unsigned_scale *= factor;
      if (acc != just_above_hi) return 279;
      if (signed_scale != 3) return 280;
      if (unsigned_scale != 3U) return 281;
    }
  }
  return 0;
}

int floating_inc_dec(void) {
  double d = 1.5;
  double old_d = d++;
  float f = 3.5f;
  float new_f = --f;
  double d_compound = 2.0;
  float f_compound = 2.0f;
  if ((int)(old_d * 10.0) != 15) return 574;
  if ((int)(d * 10.0) != 25) return 575;
  if ((int)(new_f * 10.0f) != 25) return 576;
  if ((int)(f * 10.0f) != 25) return 577;
  d_compound += 0.5;
  d_compound *= 2.0;
  d_compound /= 5.0;
  d_compound -= 0.5;
  if ((int)(d_compound * 10.0) != 5) return 578;
  f_compound += 0.25f;
  f_compound *= 4.0f;
  f_compound /= 3.0f;
  f_compound -= 1.0f;
  if ((int)(f_compound * 100.0f) != 200) return 579;
  return 0;
}

int pointer_compound_assign(void) {
  int values[5] = {1, 2, 3, 4, 5};
  char bytes[4] = {7, 8, 9, 10};
  int *p = values;
  char *c = bytes;
  void *v = bytes;
  p += 3;
  if (*p != 4) return 580;
  p -= 2;
  if (*p != 2) return 581;
  if (p - values != 1) return 582;
  c += 2;
  if (*c != 9) return 583;
  c -= 1;
  if (*c != 8) return 584;
  v += 3;
  if ((char*)v - bytes != 3) return 593;
  v = 2 + v;
  if ((char*)v - bytes != 5) return 594;
  v--;
  if (v - (void*)bytes != 4) return 595;
  return 0;
}

int var_pair(int tag, ...) {
  va_list ap;
  struct Pair p;
  __builtin_va_start(ap, tag);
  p = __builtin_va_arg(ap, struct Pair);
  __builtin_va_end(ap);
  return pair_sum(p);
}

int var_dpair(int tag, ...) {
  va_list ap;
  struct DPair p;
  __builtin_va_start(ap, tag);
  p = __builtin_va_arg(ap, struct DPair);
  __builtin_va_end(ap);
  return dpair_sum(p);
}

int var_big(int tag, ...) {
  va_list ap;
  struct Big p;
  __builtin_va_start(ap, tag);
  p = __builtin_va_arg(ap, struct Big);
  __builtin_va_end(ap);
  return big_sum(p);
}

int var_pair_stack(int a, int b, int c, int d, int e, ...) {
  va_list ap;
  struct Pair p;
  __builtin_va_start(ap, e);
  p = __builtin_va_arg(ap, struct Pair);
  __builtin_va_end(ap);
  return pair_sum(p);
}

int isum(int n, ...) {
  va_list ap;
  int total = 0;
  int i;
  __builtin_va_start(ap, n);
  for (i = 0; i < n; i = i + 1) {
    total = total + __builtin_va_arg(ap, int);
  }
  __builtin_va_end(ap);
  return total;
}

double dsum(int n, ...) {
  va_list ap;
  double total = 0.0;
  int i;
  __builtin_va_start(ap, n);
  for (i = 0; i < n; i = i + 1) {
    total = total + __builtin_va_arg(ap, double);
  }
  __builtin_va_end(ap);
  return total;
}

int default_promotions(void) {
  float f = 1.5f;
  signed char c = 2;
  if ((int)dsum(1, f) != 1) return 274;
  if (isum(1, c) != 2) return 275;
  return 0;
}

int target_predefines(void) {
#if defined(__gnu_linux__) && defined(__linux__) && defined(__ELF__) && defined(__x86_64__) && defined(__amd64__) && defined(_LP64) && defined(__code_model_small__)
  int target = 0;
#else
  return 509;
#endif
#if __GXX_ABI_VERSION == 1002
  target = target + 0;
#else
  return 582;
#endif
#if __SIZEOF_POINTER__ == 8 && __SIZEOF_LONG__ == 8 && __CHAR_BIT__ == 8
  target = target + 0;
#else
  return 510;
#endif
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__ && __FLOAT_WORD_ORDER__ == __ORDER_LITTLE_ENDIAN__ && __ORDER_PDP_ENDIAN__ == 3412
  target = target + 0;
#else
  return 574;
#endif
#if __BIGGEST_ALIGNMENT__ == 16 && __SIZEOF_LONG_DOUBLE__ == 16
  target = target + 0;
#else
  return 577;
#endif
#if __SIZE_MAX__ == 18446744073709551615UL && __UINTPTR_MAX__ == 18446744073709551615UL && __PTRDIFF_MAX__ == 9223372036854775807L
  target = target + 0;
#else
  return 512;
#endif
#if __WCHAR_WIDTH__ == 32 && __WINT_WIDTH__ == 32 && __WINT_UNSIGNED__ == 1 && __SIG_ATOMIC_WIDTH__ == 32 && __SIG_ATOMIC_MAX__ == 2147483647
  target = target + 0;
#else
  return 578;
#endif
#if defined(__NO_MATH_INLINES) && __NO_MATH_INLINES == 1
  target = target + 0;
#else
  return 579;
#endif
#if __ATOMIC_SEQ_CST == 5 && __GCC_ATOMIC_POINTER_LOCK_FREE == 2
  target = target + 0;
#else
  return 511;
#endif
#if defined(__clang__) && __clang_major__ == 18 && __clang_minor__ == 1 && __clang_patchlevel__ == 3
  target = target + 0;
#else
  return 575;
#endif
  const char *clang_version = __clang_version__;
  const char *compiler_version = __VERSION__;
  const char *literal_encoding = __clang_literal_encoding__;
  const char *wide_literal_encoding = __clang_wide_literal_encoding__;
  if (!clang_version[0] || !compiler_version[0]) return 576;
  if (literal_encoding[0] != 'U' || literal_encoding[4] != '8') return 580;
  if (wide_literal_encoding[0] != 'U' || wide_literal_encoding[4] != '3') return 581;
#if __has_builtin(__builtin_memcpy) && __has_builtin(__builtin_return_address) && __has_builtin(__builtin_dynamic_object_size) && __has_builtin(__builtin_flt_rounds) && __has_builtin(__builtin_unpredictable) && __has_builtin(__builtin_is_aligned) && __has_builtin(__builtin_align_up) && __has_builtin(__builtin_align_down) && __has_builtin(__atomic_load_n) && __has_builtin(__sync_bool_compare_and_swap) && __has_builtin(__sync_val_compare_and_swap) && __has_builtin(__sync_fetch_and_max) && __has_builtin(__sync_fetch_and_min) && __has_builtin(__sync_fetch_and_umax) && __has_builtin(__sync_fetch_and_umin) && __has_builtin(__builtin_choose_expr) && __has_builtin(__builtin_types_compatible_p) && __has_builtin(__builtin_classify_type)
  target = target + 0;
#else
  return 513;
#endif
#if __has_builtin(__builtin_mempcpy) && __has_builtin(__builtin___mempcpy_chk) && __has_builtin(__builtin_stpcpy) && __has_builtin(__builtin___stpncpy_chk)
  target = target + 0;
#else
  return 573;
#endif
#if __has_builtin(__builtin_unsupported_vector_thing)
  return 514;
#endif
#if __has_attribute(packed) && __has_attribute(__packed__)
  target = target + 0;
#else
  return 515;
#endif
#if __has_attribute(aligned) && __has_attribute(__aligned__)
  target = target + 0;
#else
  return 516;
#endif
#if __has_attribute(mode) && __has_attribute(__mode__)
  target = target + 0;
#else
  return 607;
#endif
#if __has_attribute(weak) && __has_attribute(__weak__)
  target = target + 0;
#else
  return 608;
#endif
#if __has_attribute(alias) && __has_attribute(__alias__)
  target = target + 0;
#else
  return 610;
#endif
#if __has_attribute(section) && __has_attribute(__section__)
  target = target + 0;
#else
  return 611;
#endif
#if __has_attribute(constructor) && __has_attribute(__destructor__)
  target = target + 0;
#else
  return 612;
#endif
#if __has_attribute(visibility) && __has_attribute(__visibility__)
  target = target + 0;
#else
  return 609;
#endif
#if __has_attribute(unused) && __has_attribute(__unused__) && __has_attribute(fallthrough) && __has_attribute(__fallthrough__)
  target = target + 0;
#else
  return 535;
#endif
#if __has_attribute(noreturn) && __has_attribute(__noreturn__) && __has_attribute(noinline) && __has_attribute(__always_inline__)
  target = target + 0;
#else
  return 559;
#endif
#if __has_attribute(format) && __has_attribute(__format__) && __has_attribute(nonnull) && __has_attribute(warn_unused_result)
  target = target + 0;
#else
  return 560;
#endif
#if __has_attribute(malloc) && __has_attribute(alloc_size) && __has_attribute(alloc_align)
  target = target + 0;
#else
  return 561;
#endif
#if __has_attribute(no_sanitize_thread) && __has_attribute(__no_sanitize_address__)
  target = target + 0;
#else
  return 562;
#endif
#if __has_attribute(vector_size) || __has_attribute(__vector_size__) || __has_attribute(ext_vector_type) || __has_attribute(__ext_vector_type__)
  return 606;
#endif
#if __has_include("probe_header.h")
  target = target + 0;
#else
  return 517;
#endif
#if __has_include("missing_probe_header.h")
  return 518;
#endif
#if __has_feature(c_static_assert) && __has_extension(c_alignas) && __has_feature(c_alignof) && __has_feature(c_atomic)
  target = target + 0;
#else
  return 520;
#endif
#if __has_feature(c_generic_selections)
  target = target + 0;
#else
  return 521;
#endif
#if __is_identifier(kimicc_probe_identifier) && !__is_identifier(int) && !__is_identifier(_Static_assert) && !__is_identifier(__typeof__) && !__is_identifier(__auto_type) && !__is_identifier(_Alignof) && !__is_identifier(__alignof__)
  target = target + 0;
#else
  return 522;
#endif
#if __has_c_attribute(deprecated) || __has_declspec_attribute(dllexport) || __has_warning("-Wunknown")
  return 523;
#endif
#if 0
  return 524;
#elifdef __linux__
  target = target + 0;
#else
  return 525;
#endif
#if 0
  return 526;
#elifndef KIMICC_MISSING_PREDEFINE
  target = target + 0;
#else
  return 527;
#endif
  int counter_a = __COUNTER__;
  int counter_b = __COUNTER__;
  if (counter_a != 0 || counter_b != 1) return 528;
#define VAOPT_SUM(base, ...) (base __VA_OPT__(+ __VA_ARGS__))
#define VAOPT_NAMED(base, rest...) (base __VA_OPT__(+ rest))
  if (VAOPT_SUM(7) != 7 || VAOPT_SUM(7, 5) != 12) return 529;
  if (VAOPT_NAMED(9) != 9 || VAOPT_NAMED(9, 2) != 11) return 530;
#line 700 "kimicc-line-probe.c"
  if (__LINE__ != 700) return 531;
  const char *line_file = __FILE__;
  if (line_file[0] != 'k' || line_file[7] != 'l') return 532;
# 900 "kimicc-marker-probe.c" 1 3
  if (__LINE__ != 900) return 533;
  const char *marker_file = __FILE__;
  if (marker_file[0] != 'k' || marker_file[7] != 'm') return 534;
  int prefix = __USER_LABEL_PREFIX__ 0;
  __WINT_TYPE__ wint_value = 0;
  if (prefix != 0 || wint_value != 0) return 512;
  return target;
}

int memory_builtins(void) {
  char src[4];
  char dst[4];
  src[0] = 1;
  src[1] = 2;
  src[2] = 3;
  src[3] = 0;
  __builtin_memcpy(dst, src, 4);
  __builtin_memset(src, 0, 4);
  if (src[2] != 0) return 276;
  __builtin_memmove(src, dst, 4);
  if (src[0] != 1 || src[2] != 3) return 277;
  __builtin_bzero(dst, 4);
  if (dst[0] != 0 || dst[2] != 0) return 278;
  return 0;
}

int scalar_hint_builtins(void) {
  int x = 41;
  if (__builtin_expect(x, 1) != 41) return 279;
  __builtin_assume(x);
  __builtin_prefetch(&x, 0, 3);
  if (__builtin_constant_p(x) != 0) return 280;
  if (__builtin_object_size(&x, 0) != sizeof(x)) return 281;
  if (__builtin_dynamic_object_size(&x, 0) != sizeof(x)) return 559;
  if (__builtin_frame_address(1) != 0) return 282;
  if (__builtin_frame_address(0) == 0) return 283;
  if (__builtin_assume_aligned(&x, 16) != &x) return 434;
  if (__builtin_expect_with_probability(x, 41, 0.9) != 41) return 435;
  if (__builtin_unpredictable(x) != 41) return 628;
  if (!__builtin_is_aligned(32, 16)) return 629;
  if (__builtin_is_aligned(34, 16)) return 630;
  if (__builtin_align_up(33, 16) != 48) return 631;
  if (__builtin_align_down(47, 16) != 32) return 632;
  void *ra = __builtin_return_address(0);
  if (ra == 0) return 505;
  if (__builtin_return_address(1) != 0) return 506;
  if (__builtin_extract_return_addr(ra) != ra) return 507;
  if (__builtin_frob_return_addr(ra) != ra) return 508;
  if (__builtin_flt_rounds() != 1) return 560;
  return 0;
}

int string_builtins(void) {
  char dst[16];
  char small[4];
  char cat[8];
  char copy[16];
  __builtin_strcpy(dst, "ab");
  __builtin___strcat_chk(dst, "c", 16);
  if (__builtin_strlen(dst) != 3) return 284;
  if (__builtin_strcmp(dst, "abc") != 0) return 285;
  __builtin___strncpy_chk(dst, "xyzz", 2, 16);
  dst[2] = 0;
  __builtin___strncat_chk(dst, "pq", 1, 16);
  if (__builtin_strcmp(dst, "xyp") != 0) return 286;
  if (__builtin_strncmp(dst, "xyq", 2) != 0) return 421;
  if (__builtin_memcmp(dst, "xyp", 3) != 0) return 422;
  if (__builtin_strchr(dst, 121) != dst + 1) return 423;
  if (__builtin_strrchr(dst, 112) != dst + 2) return 424;
  if (__builtin_strstr(dst, "yp") != dst + 1) return 425;
  if (__builtin_memchr(dst, 112, 3) != dst + 2) return 426;
  if (__builtin___strlcpy_chk(small, "abcdef", 4, 4) != 6) return 501;
  if (__builtin_strcmp(small, "abc") != 0) return 502;
  __builtin_strcpy(cat, "ab");
  if (__builtin___strlcat_chk(cat, "cdef", 8, 8) != 6) return 503;
  if (__builtin_strcmp(cat, "abcdef") != 0) return 504;
  if (__builtin_mempcpy(copy, "uv", 2) != copy + 2) return 566;
  if (__builtin___mempcpy_chk(copy + 2, "wx", 2, 14) != copy + 4) return 567;
  if (__builtin_memcmp(copy, "uvwx", 4) != 0) return 568;
  if (__builtin_stpcpy(copy, "hi") != copy + 2) return 569;
  if (__builtin___stpcpy_chk(copy, "ok", 16) != copy + 2) return 570;
  if (__builtin_stpncpy(copy, "ab", 2) != copy + 2) return 571;
  if (__builtin___stpncpy_chk(copy, "cd", 2, 16) != copy + 2) return 572;
  return 0;
}

int formatted_builtins(void) {
  char dst[64];
  int n = __builtin___snprintf_chk(dst, 64, 0, 64, "%d-%s", 12, "xy");
  if (n != 5) return 417;
  if (__builtin_strcmp(dst, "12-xy") != 0) return 418;
  n = __builtin___sprintf_chk(dst, 0, 64, "%s:%d", "ok", 7);
  if (n != 4) return 419;
  if (__builtin_strcmp(dst, "ok:7") != 0) return 420;
  return 0;
}

int bit_builtins(void) {
  if (__builtin_clz(1u) != 31) return 287;
  if (__builtin_clzl(1ul) != 63) return 288;
  if (__builtin_clzll(1ull) != 63) return 289;
  if (__builtin_ctz(8u) != 3) return 290;
  if (__builtin_ctzl(16ul) != 4) return 291;
  if (__builtin_ctzll(32ull) != 5) return 292;
  if (__builtin_ffs(0u) != 0) return 427;
  if (__builtin_ffs(8u) != 4) return 428;
  if (__builtin_ffsl(16ul) != 5) return 429;
  if (__builtin_ffsll(32ull) != 6) return 430;
  if ((__builtin_bswap16(0x0102u) & 255) != 1) return 293;
  if ((__builtin_bswap32(0x01020304u) & 255) != 1) return 294;
  if ((__builtin_bswap64(0x0102030405060708ull) & 255) != 1) return 295;
  if ((__builtin_bswap(0x01020304u) & 255) != 1) return 461;
  if ((__builtin_bswap(0x0102030405060708ull) & 255) != 1) return 462;
  if (__builtin_rotateleft32(0x12345678u, 8) != 0x34567812u) return 296;
  if ((__builtin_rotateright32(0x12345678u, 8) & 255) != 0x56) return 297;
  if ((__builtin_rotateleft64(0x0123456789abcdefull, 16) & 255) != 0x23) return 298;
  if ((__builtin_rotateright64(0x0123456789abcdefull, 16) & 255) != 0xab) return 299;
  if (__builtin_rotateleft(0x12345678u, 8) != 0x34567812u) return 463;
  if ((__builtin_rotateright(0x0123456789abcdefull, 16) & 255) != 0xab) return 464;
  if (__builtin_popcount(0xf0f0u) != 8) return 300;
  if (__builtin_popcountl(0x0f0f0f0f0f0f0f0ful) != 32) return 301;
  if (__builtin_popcountll(0x0f0f0f0f0f0f0f0full) != 32) return 302;
  if (__builtin_parity(0xf0f1u) != 1) return 431;
  if (__builtin_parityl(0x0f0f0f0f0f0f0f0ful) != 0) return 432;
  if (__builtin_parityll(0x0f0f0f0f0f0f0f0eull) != 1) return 433;
  return 0;
}

int touch_alloca(char *p) { return p[0] + p[31]; }

int alloca_builtin(void) {
  int n = 31;
  char *p = __builtin_alloca(n + 1);
  char *q;
  p[0] = 3;
  p[31] = 4;
  q = __builtin_alloca(5);
  q[0] = 5;
  q[4] = 6;
  if (((long)p & 15) != 0) return 303;
  if (((long)q & 15) != 0) return 304;
  if (p[0] != 3 || p[31] != 4) return 305;
  if (q[0] != 5 || q[4] != 6) return 306;
  if (touch_alloca(p) != 7) return 307;
  return 0;
}

int atomic_builtins(void) {
  unsigned char b = 0;
  unsigned char flag = 0;
  unsigned short h = 0;
  unsigned int w = 5;
  unsigned long x = 0;
  int sw = -3;
  unsigned int uw = 10;
  _Atomic(unsigned int) a = 5;
  unsigned int expected = 11;
  unsigned int expected_w = 31;
  unsigned int loaded = 0;
  unsigned int desired = 29;
  unsigned int old = 0;
  unsigned int expected_ptr = 31;
  __sync_synchronize();
  __atomic_thread_fence(5);
  __atomic_signal_fence(5);
  __c11_atomic_thread_fence(5);
  __c11_atomic_signal_fence(5);
  if (!__atomic_always_lock_free(1, &w)) return 436;
  if (!__atomic_always_lock_free(2, &w)) return 437;
  if (!__atomic_is_lock_free(4, &w)) return 438;
  if (!__c11_atomic_is_lock_free(8)) return 439;
  if (__atomic_always_lock_free(16, &w)) return 440;
  __atomic_store_n(&b, 1, 5);
  __atomic_store_n(&h, 2, 5);
  __atomic_store_n(&w, 5, 5);
  __atomic_store_n(&x, 36, 5);
  __atomic_load(&w, &loaded, 5);
  if (loaded != 5) return 410;
  __atomic_store(&w, &desired, 5);
  if (w != 29) return 411;
  desired = 31;
  __atomic_exchange(&w, &desired, &old, 5);
  if (old != 29) return 412;
  desired = 37;
  if (!__atomic_compare_exchange(&w, &expected_ptr, &desired, 0, 5, 5)) return 413;
  if (w != 37) return 414;
  expected_ptr = 31;
  desired = 41;
  if (__atomic_compare_exchange(&w, &expected_ptr, &desired, 0, 5, 5)) return 415;
  if (expected_ptr != 37 || w != 37) return 416;
  __atomic_store_n(&w, 5, 5);
  if (__atomic_test_and_set(&flag, 5)) return 406;
  if (!flag) return 407;
  if (!__atomic_test_and_set(&flag, 5)) return 408;
  __atomic_clear(&flag, 5);
  if (flag) return 409;
  if (__atomic_load_n(&b, 5) != 1) return 308;
  if (__atomic_load_n(&h, 5) != 2) return 309;
  if (__atomic_load_n(&w, 5) != 5) return 310;
  if ((int)__atomic_load_n(&x, 5) != 36) return 311;
  if (__atomic_add_fetch(&w, 3, 5) != 8) return 312;
  if (__atomic_sub_fetch(&w, 1, 5) != 7) return 313;
  if (__atomic_fetch_or(&w, 16, 5) != 7) return 314;
  if (w != 23) return 315;
  if (__atomic_fetch_xor(&w, 3, 5) != 23) return 316;
  if (w != 20) return 317;
  if (__atomic_exchange_n(&w, 31, 5) != 20) return 394;
  if (!__atomic_compare_exchange_n(&w, &expected_w, 37, 0, 5, 5)) return 395;
  if (w != 37) return 396;
  expected_w = 31;
  if (__atomic_compare_exchange_n(&w, &expected_w, 41, 1, 5, 5)) return 397;
  if (expected_w != 37) return 398;
  if (__atomic_and_fetch(&w, 15, 5) != 5) return 399;
  if (__atomic_or_fetch(&w, 32, 5) != 37) return 400;
  if (__atomic_xor_fetch(&w, 7, 5) != 34) return 401;
  if (__atomic_exchange_n(&w, 10, 5) != 34) return 402;
  if (__atomic_fetch_nand(&w, 15, 5) != 10) return 403;
  if (w != ~10u) return 404;
  __atomic_store_n(&w, 10, 5);
  if (__atomic_nand_fetch(&w, 15, 5) != ~10u) return 405;
  __atomic_store_n(&w, 10, 5);
  if (!__sync_bool_compare_and_swap(&w, 10u, 12u)) return 445;
  if (w != 12u) return 446;
  if (__sync_bool_compare_and_swap(&w, 10u, 14u)) return 447;
  if (__sync_val_compare_and_swap(&w, 12u, 17u) != 12u) return 448;
  if (w != 17u) return 449;
  if (__sync_val_compare_and_swap(&w, 12u, 19u) != 17u) return 450;
  if (w != 17u) return 451;
  __atomic_store_n(&w, 1, 5);
  if (__sync_fetch_and_add(&w, 2u) != 1u) return 452;
  if (__sync_add_and_fetch(&w, 4u) != 7u) return 453;
  if (__sync_fetch_and_or(&w, 8u) != 7u) return 454;
  if (__sync_and_and_fetch(&w, 6u) != 6u) return 455;
  if (__sync_fetch_and_xor(&w, 3u) != 6u) return 456;
  if (__sync_sub_and_fetch(&w, 2u) != 3u) return 457;
  if (__sync_fetch_and_nand(&w, 15u) != 3u) return 458;
  __atomic_store_n(&w, 10, 5);
  if (__sync_nand_and_fetch(&w, 15u) != ~10u) return 459;
  if (__sync_fetch_and_max(&sw, -1) != -3) return 620;
  if (sw != -1) return 621;
  if (__sync_fetch_and_min(&sw, -7) != -1) return 622;
  if (sw != -7) return 623;
  if (__sync_fetch_and_umax(&uw, 12u) != 10u) return 624;
  if (uw != 12u) return 625;
  if (__sync_fetch_and_umin(&uw, 7u) != 12u) return 626;
  if (uw != 7u) return 627;
  __atomic_store_n(&w, 21, 5);
  if (__sync_swap(&w, 22u) != 21u) return 460;
  if (__sync_lock_test_and_set(&w, 23u) != 22u) return 461;
  __sync_lock_release(&w);
  if (w != 0u) return 462;
  if (__c11_atomic_fetch_add(&a, 3, 5) != 5) return 318;
  if (a != 8) return 319;
  if (__c11_atomic_fetch_sub(&a, 1, 5) != 8) return 320;
  if (__c11_atomic_fetch_or(&a, 16, 5) != 7) return 321;
  if (__c11_atomic_fetch_and(&a, 23, 5) != 23) return 322;
  if (__c11_atomic_fetch_xor(&a, 3, 5) != 23) return 323;
  if (__c11_atomic_exchange(&a, 11, 5) != 20) return 324;
  if (!__c11_atomic_compare_exchange_strong(&a, &expected, 19, 5, 5)) return 325;
  if (a != 19) return 326;
  expected = 11;
  if (__c11_atomic_compare_exchange_strong(&a, &expected, 21, 5, 5)) return 327;
  if (expected != 19) return 328;
  if (__c11_atomic_load(&a, 5) != 19) return 329;
  __c11_atomic_store(&a, 42, 5);
  if (a != 42) return 330;
  expected = 42;
  if (!__c11_atomic_compare_exchange_weak(&a, &expected, 44, 5, 5)) return 441;
  if (a != 44) return 442;
  expected = 42;
  if (__c11_atomic_compare_exchange_weak(&a, &expected, 45, 5, 5)) return 443;
  if (expected != 44 || a != 44) return 444;
  return 0;
}

int overflow_builtins(void) {
  long long s = 9223372036854775807LL;
  long long out = 0;
  long lout = 0;
  unsigned long long ull = 0;
  unsigned int u = 0;
  int i = 0;
  if (!__builtin_add_overflow(s, 1LL, &out)) return 445;
  if (out != (-9223372036854775807LL - 1LL)) return 446;
  if (__builtin_add_overflow(40LL, 2LL, &out)) return 447;
  if (out != 42) return 448;
  s = -9223372036854775807LL - 1LL;
  if (!__builtin_sub_overflow(s, 1LL, &out)) return 449;
  if (out != 9223372036854775807LL) return 450;
  if (!__builtin_sub_overflow(0u, 1u, &u)) return 451;
  if (u != 0xffffffffu) return 452;
  if (!__builtin_add_overflow(0xffffffffu, 1u, &u)) return 453;
  if (u != 0) return 454;
  if (!__builtin_mul_overflow(2000000000, 2, &i)) return 455;
  if ((unsigned int)i != 4000000000u) return 456;
  if (__builtin_mul_overflow(1000, 2, &i)) return 457;
  if (i != 2000) return 458;
  if (!__builtin_mul_overflow(0xffffffffu, 2u, &u)) return 459;
  if (u != 0xfffffffeu) return 460;
  if (!__builtin_sadd_overflow(2147483647, 1, &i)) return 476;
  if (i != (-2147483647 - 1)) return 477;
  if (!__builtin_saddl_overflow(9223372036854775807L, 1L, &lout)) return 478;
  if (lout != (-9223372036854775807L - 1L)) return 479;
  if (!__builtin_saddll_overflow(9223372036854775807LL, 1LL, &out)) return 480;
  if (out != (-9223372036854775807LL - 1LL)) return 481;
  if (!__builtin_uadd_overflow(0xffffffffu, 1u, &u)) return 482;
  if (u != 0) return 483;
  if (!__builtin_uaddll_overflow(0xffffffffffffffffull, 1ull, &ull)) return 484;
  if (ull != 0) return 485;
  if (!__builtin_ssub_overflow(-2147483647 - 1, 1, &i)) return 486;
  if (i != 2147483647) return 487;
  if (!__builtin_ssubll_overflow(-9223372036854775807LL - 1LL, 1LL, &out)) return 488;
  if (out != 9223372036854775807LL) return 489;
  if (!__builtin_usub_overflow(0u, 1u, &u)) return 490;
  if (u != 0xffffffffu) return 491;
  if (!__builtin_usubll_overflow(0ull, 1ull, &ull)) return 492;
  if (ull != 0xffffffffffffffffull) return 493;
  if (!__builtin_smul_overflow(2000000000, 2, &i)) return 494;
  if ((unsigned int)i != 4000000000u) return 495;
  if (!__builtin_smulll_overflow(3037000500LL, 3037000500LL, &out)) return 496;
  if (!__builtin_umul_overflow(0xffffffffu, 2u, &u)) return 497;
  if (u != 0xfffffffeu) return 498;
  if (!__builtin_umulll_overflow(0xffffffffffffffffull, 2ull, &ull)) return 499;
  if (ull != 0xfffffffffffffffeull) return 500;
  return 0;
}

int integer_abs_builtins(void) {
  if (__builtin_abs(-7) != 7) return 472;
  if (__builtin_abs(5) != 5) return 473;
  if (__builtin_labs(-1234567890123L) != 1234567890123L) return 474;
  if (__builtin_llabs(-900000000000000000LL) != 900000000000000000LL) return 475;
  return 0;
}

double fabs_double(double x) { return __builtin_fabs(x); }
float fabs_float(float x) { return __builtin_fabsf(x); }

int floating_builtins(void) {
  double nanv = __builtin_nan("");
  float nanf = __builtin_nanf("");
  double inf = __builtin_huge_val();
  float inff = __builtin_inff();
  if ((int)fabs_double(-4.5) != 4) return 331;
  if ((int)fabs_float(-3.5f) != 3) return 332;
  if (!(inf > 1000000.0)) return 333;
  if (!(inff > 1000000.0f)) return 334;
  if (nanv == nanv) return 335;
  if (nanf == nanf) return 336;
  if (!(nanv != nanv)) return 345;
  if (!nanv) return 346;
  if (!nanf) return 347;
  if (nanv) { } else { return 348; }
  if (!__builtin_isgreater(3.0, 2.0)) return 337;
  if (!__builtin_isgreaterequal(3.0, 3.0)) return 338;
  if (!__builtin_isless(2.0, 3.0)) return 339;
  if (!__builtin_islessequal(3.0, 3.0)) return 340;
  if (!__builtin_islessgreater(2.0, 3.0)) return 341;
  if (!__builtin_isunordered(nanv, 1.0)) return 342;
  if (__builtin_isless(nanv, 1.0)) return 343;
  if (__builtin_isgreater(nanv, 1.0)) return 344;
  if (!__builtin_isnan(nanv)) return 349;
  if (!__builtin_isnanf(nanf)) return 350;
  if (!__builtin_isinf(inf)) return 351;
  if (!__builtin_isinff(inff)) return 352;
  if (!__builtin_isfinite(4.0)) return 353;
  if (__builtin_isfinite(inf)) return 354;
  if (!__builtin_isnormal(4.0)) return 355;
  if (__builtin_isnormal(0.0)) return 356;
  if (!__builtin_signbit(-0.0)) return 357;
  if (__builtin_signbit(1.0)) return 358;
  if (!__builtin_signbitf(-0.0f)) return 359;
  if ((int)__builtin_copysign(3.0, -1.0) != -3) return 465;
  if ((int)__builtin_copysign(-3.0, 1.0) != 3) return 466;
  if ((int)__builtin_copysignf(2.0f, -1.0f) != -2) return 467;
  if (!__builtin_signbit(__builtin_copysign(0.0, -1.0))) return 468;
  if ((int)__builtin_sqrt(81.0) != 9) return 469;
  if ((int)__builtin_sqrtf(25.0f) != 5) return 470;
  if (!__builtin_isnan(__builtin_sqrt(-1.0))) return 471;
  return 0;
}

struct TinyCopy {
  char c;
};

struct TinyCopyWrap {
  struct TinyCopy t;
  char guard;
};

struct TwelveCopy {
  int a;
  int b;
  char c;
};

struct TwelveCopyWrap {
  struct TwelveCopy t;
  char guard;
};

struct TinyCopy make_tiny_copy(char c) {
  struct TinyCopy t;
  t.c = c;
  return t;
}

struct TwelveCopy make_twelve_copy(int a, int b, char c) {
  struct TwelveCopy t;
  t.a = a;
  t.b = b;
  t.c = c;
  return t;
}

int aggregate_object_copies(void) {
  struct TinyCopyWrap tiny_wrap;
  struct TinyCopy tiny;
  struct TwelveCopyWrap twelve_wrap;
  struct TwelveCopy twelve;
  tiny_wrap.t.c = 1;
  tiny_wrap.guard = 77;
  tiny.c = 2;
  tiny_wrap.t = tiny;
  if (tiny_wrap.guard != 77) return 349;
  if (tiny_wrap.t.c != 2) return 350;
  tiny_wrap.t = make_tiny_copy(3);
  if (tiny_wrap.guard != 77) return 351;
  if (tiny_wrap.t.c != 3) return 352;
  twelve_wrap.t.a = 0;
  twelve_wrap.t.b = 0;
  twelve_wrap.t.c = 0;
  twelve_wrap.guard = 88;
  twelve.a = 1;
  twelve.b = 2;
  twelve.c = 3;
  twelve_wrap.t = twelve;
  if (twelve_wrap.guard != 88) return 353;
  if (twelve_wrap.t.a + twelve_wrap.t.b + twelve_wrap.t.c != 6) return 354;
  twelve_wrap.t = make_twelve_copy(4, 5, 6);
  if (twelve_wrap.guard != 88) return 355;
  if (twelve_wrap.t.a + twelve_wrap.t.b + twelve_wrap.t.c != 15) return 356;
  return 0;
}

typedef union InitUnion {
  int int32;
  void *ptr;
} InitUnion;

typedef struct InitValue {
  InitUnion u;
  long tag;
} InitValue;

struct InitPair {
  int a;
  int b;
};

struct InitWrap {
  struct InitPair pairs[2];
  int arr[3];
};

struct InitBits {
  unsigned a : 3;
  signed b : 4;
  unsigned c : 5;
};

int compound_literals_and_initializers(void) {
  InitValue v;
  struct InitPair p = { .b = 5, .a = 6 };
  struct InitWrap local = { .pairs[1].b = 5, .pairs[0].a = 37, .arr[2] = 35 };
  struct InitWrap literal = (struct InitWrap){ .pairs[0].b = 2, .arr[1] = 4 };
  int arr[5] = { 1, [3] = 4 };
  int *tmp = (int[5]){ 10, 20, [4] = 30 };
  int scalar = (int){ 3 };
  struct InitBits bits = { .a = 5, .b = -3, .c = 17 };
  v = (InitValue){ (InitUnion){ .int32 = 7 }, 4 };
  if (v.u.int32 != 7) return 370;
  if (v.tag != 4) return 371;
  if (p.a != 6 || p.b != 5) return 372;
  if (arr[0] != 1 || arr[1] != 0 || arr[2] != 0 || arr[3] != 4 || arr[4] != 0) {
    return 373;
  }
  if (tmp[0] != 10 || tmp[1] != 20 || tmp[2] != 0 || tmp[3] != 0 || tmp[4] != 30) {
    return 374;
  }
  if (scalar != 3) return 375;
  if (bits.a != 5 || bits.b != -3 || bits.c != 17) return 376;
  if (local.pairs[0].a != 37 || local.pairs[0].b != 0 || local.pairs[1].a != 0 || local.pairs[1].b != 5) {
    return 616;
  }
  if (local.arr[0] != 0 || local.arr[1] != 0 || local.arr[2] != 35) {
    return 617;
  }
  if (literal.pairs[0].a != 0 || literal.pairs[0].b != 2 || literal.pairs[1].a != 0 || literal.pairs[1].b != 0) {
    return 618;
  }
  if (literal.arr[0] != 0 || literal.arr[1] != 4 || literal.arr[2] != 0) {
    return 619;
  }
  return 0;
}

int switch_dispatch(void) {
  int r = 0;
  int x = 2;
  unsigned tag = 0xfffffff9u;
  switch (x) {
    default: r = 99; break;
    case 1: r = 10; break;
    case 2: r = 20; break;
  }
  if (r != 20) return 377;
  switch (tag) {
    case -7: r = 5; break;
    default: r = 6; break;
  }
  if (r != 5) return 378;
  switch (3) {
    case 1: r = 1; break;
    case 2: r = 2; break;
  }
  if (r != 5) return 379;
  switch (1) {
    case 1: r = 10;
    case 2: r += 20; break;
    default: r = 0; break;
  }
  if (r != 30) return 380;
  return 0;
}

int global_initializers(void) {
  if (global_arr[0] != 1 || global_arr[1] != 0 || global_arr[2] != 0 || global_arr[3] != 4 || global_arr[4] != 0) {
    return 381;
  }
  if (global_outer.tag != 1 || global_outer.inner.c != 2 || global_outer.inner.x != 7 || global_outer.tail != 9) {
    return 382;
  }
  if (global_bits.a != 5 || global_bits.b != -3 || global_bits.c != 17) {
    return 383;
  }
  if (global_bit_union.b != -3) {
    return 384;
  }
  if (global_union.c[0] != 65 || global_union.c[1] != 66 || global_union.c[2] != 0 || global_union.c[3] != 0) {
    return 385;
  }
  if (global_string[0] != 104 || global_string[1] != 101 || global_string[2] != 121 || global_string[3] != 0 || global_string[5] != 0) {
    return 386;
  }
  if (global_ptr != &global_arr[3] || *global_ptr != 4 || global_addr != &global_arr[4] || *global_addr != 0) {
    return 387;
  }
  if (global_fp(41) != 42) {
    return 388;
  }
  if (global_ptrs[0] != &global_arr[0] || global_ptrs[1] != &global_arr[2] || global_ptrs[2] != &global_arr[4]) {
    return 389;
  }
  if (global_refs.first != &global_arr[1] || global_refs.tail != &global_arr[4] || global_refs.fn(41) != 42) {
    return 390;
  }
  if (global_member != &global_outer.inner.x || *global_member != 7 || global_member_next != &global_outer.tail) {
    return 391;
  }
  if (global_node1.value != 1 || global_node1.next != &global_node2 || global_node1.next->value != 2 || global_node2.next != 0) {
    return 392;
  }
  if (global_nodes[0] != &global_node1 || global_nodes[1] != &global_node2) {
    return 393;
  }
  if (global_nested.box.d != 1.5 || global_nested.tag != 7 || global_nested.arr[0] != 0 || global_nested.arr[1] != 0 || global_nested.arr[2] != 35) {
    return 394;
  }
  if (global_pairs[0].a != 37 || global_pairs[0].b != 0 || global_pairs[1].a != 0 || global_pairs[1].b != 5) {
    return 395;
  }
  return 0;
}

struct __attribute__((packed)) PackedAggregate {
  char c;
  int x;
};

struct OuterPackedAggregate {
  char tag;
  struct PackedAggregate p;
};

int packed_sum(struct PackedAggregate p) {
  return p.c + p.x;
}

struct PackedAggregate make_packed(char c, int x) {
  struct PackedAggregate p;
  p.c = c;
  p.x = x;
  return p;
}

int packed_aggregates(void) {
  struct PackedAggregate p;
  if (__builtin_offsetof(struct PackedAggregate, x) != 1) return 357;
  if (sizeof(struct PackedAggregate) != 5) return 358;
  p = make_packed(4, 38);
  if (p.c != 4) return 359;
  if (p.x != 38) return 360;
  if (packed_sum(p) != 42) return 361;
  return 0;
}

int read_packed_stack(int a, int b, int c, int d, int e, int f, ...) {
  va_list ap;
  struct PackedAggregate p;
  __builtin_va_start(ap, f);
  p = __builtin_va_arg(ap, struct PackedAggregate);
  __builtin_va_end(ap);
  return p.c + p.x;
}

int packed_varargs(void) {
  struct PackedAggregate p = make_packed(7, 35);
  if (read_packed_stack(1, 2, 3, 4, 5, 6, p) != 42) return 362;
  if (read_packed_stack(1, 2, 3, 4, 5, 6, make_packed(8, 34)) != 42) {
    return 363;
  }
  return 0;
}

int outer_packed_sum(struct OuterPackedAggregate o) {
  return o.tag + o.p.c + o.p.x;
}

struct OuterPackedAggregate make_outer_packed(char tag, char c, int x) {
  struct OuterPackedAggregate o;
  o.tag = tag;
  o.p.c = c;
  o.p.x = x;
  return o;
}

int nested_packed_aggregates(void) {
  struct OuterPackedAggregate o;
  if (__builtin_offsetof(struct OuterPackedAggregate, p) != 1) return 364;
  if (sizeof(struct OuterPackedAggregate) != 6) return 365;
  o = make_outer_packed(1, 2, 39);
  if (o.tag != 1) return 366;
  if (o.p.c != 2) return 367;
  if (o.p.x != 39) return 368;
  if (outer_packed_sum(o) != 42) return 369;
  return 0;
}

int pragma_once_probe(void) {
  if (pragma_once_global != 7) return 519;
  return 0;
}

int generic_selection(void) {
  int x = 0;
  int arr[3];
  double d = 0.0;
  unsigned long u = 0;
  int score = 0;
  score = score + _Generic(x, int: 10, default: 100);
  score = score + _Generic(d, double: 20, default: 100);
  score = score + _Generic("x", char *: 12, char[2]: 100, default: 100);
  score = score + _Generic(arr, int *: 0, int[3]: 100, default: 100);
  score = score + _Generic(x++, int: 0, default: 100);
  score = score + _Generic((0, u), unsigned long: 0, default: 100);
  return score + x == 42 ? 0 : 535;
}

int compile_time_selection(void) {
  int selected = __builtin_choose_expr(
    __builtin_types_compatible_p(int, signed int),
    40,
    missing_compile_time_selection()
  );
  int fallback = __builtin_choose_expr(
    __builtin_types_compatible_p(int, unsigned int),
    missing_compile_time_selection(),
    2
  );
  return selected + fallback == 42 ? 0 : 536;
}

int gnu_typeof_selection(void) {
  int x = 0;
  __typeof__(x++) y = 40;
  typeof(unsigned long) z = 2;
  unsigned long *p = &z;
  __typeof__((void)0, *p) w = 0;
  return x + y + (int)z + (int)w == 42 ? 0 : 537;
}

int gnu_auto_type_selection(void) {
  unsigned long x = 40;
  __auto_type y = x;
  int bonus = 2;
  __auto_type p = &bonus;
  int total = 0;
  for (__auto_type i = 0; i < *p; i++) total = total + 1;
  return (int)y + total == 42 ? 0 : 538;
}

int gnu_classify_type_selection(void) {
  union ClassifyBits { int i; double d; };
  int x = 0;
  double d = 0.0;
  int a[2];
  struct Pair p;
  union ClassifyBits u;
  if (__builtin_classify_type(x++) != 1) return 539;
  if (x != 0) return 540;
  if (__builtin_classify_type((_Bool)0) != 4) return 541;
  if (__builtin_classify_type(d) != 8) return 542;
  if (__builtin_classify_type(&x) != 5) return 543;
  if (__builtin_classify_type(a) != 5) return 544;
  if (__builtin_classify_type("x") != 5) return 545;
  if (__builtin_classify_type(p) != 12) return 546;
  if (__builtin_classify_type(u) != 13) return 547;
  return 0;
}

__attribute__((format(printf, 1, 2)))
int attr_printf_like(const char *fmt, ...) { return fmt[0]; }

__attribute__((malloc, alloc_size(1), alloc_align(2)))
void *attr_alloc_like(unsigned long n, unsigned long align);

__attribute__((returns_nonnull, nonnull(1)))
char *attr_identity(char *p) { return p; }

__attribute__((always_inline, hot))
static inline int attr_inline(int x) { return x + 1; }

__attribute__((noinline, warn_unused_result, cold, no_sanitize_thread))
int attr_helper(void) { return attr_printf_like("*"); }

__attribute__((visibility("hidden")))
int hidden_attr_value(void) { return 42; }

int alias_attr_target(void) { return 42; }
extern int alias_attr_value(void) __attribute__((alias("alias_attr_target")));
int alias_global_target = 42;
extern int alias_global_value __attribute__((alias("alias_global_target")));

__attribute__((section(".text.kimicc_section")))
int section_attr_value(void) { return 40; }

int section_global_value __attribute__((section(".data.kimicc_section"))) = 2;

int gnu_noop_attributes(void) {
  __attribute__((unused)) int ignored = 3;
  char buf[1];
  if (attr_helper() != 42) return 563;
  if (attr_identity(buf) != buf) return 564;
  if (attr_inline(-1) != 0) return 565;
  if (hidden_attr_value() != 42) return 609;
  if (alias_attr_value() != 42 || alias_global_value != 42) return 610;
  if (section_attr_value() + section_global_value != 42) return 611;
  int x = 0;
  switch (x) {
  case 0:
    x = x + 1;
    __attribute__((fallthrough));
  case 1:
    return x == 1 ? 0 : 548;
  default:
    return 549;
  }
}

int alignof_selection(void) {
  struct AlignS { char c; int x; };
  union AlignU { char c; double d; };
  long y;
  int a[2];
  if (_Alignof(int) != 4) return 550;
  if (alignof(struct AlignS) != 4) return 551;
  if (__alignof__(union AlignU) != 8) return 552;
  if (__alignof__(y) != 8) return 553;
  if (__alignof__(a) != 4) return 554;
  if (__alignof__ y != 8) return 555;
  return 0;
}

int fp_take_int(int x) { return x == 42 ? 0 : 596; }
int fp_take_float(float x) { return x == 1.5f ? 0 : 597; }
int fp_take_double(double x) { return x == 2.25 ? 0 : 598; }

int function_pointer_param_conversions(void) {
  int (*ip)(int) = fp_take_int;
  int (*fp)(float) = fp_take_float;
  int (*dp)(double) = fp_take_double;
  float f = 2.25f;
  if (ip(42.9) != 0) return 596;
  if (fp(1.5) != 0) return 597;
  if (dp(f) != 0) return 598;
  return 0;
}

_Float32 add_float32_alias(_Float32 x) { return x + 0.5f; }
_Float64 add_float64_alias(_Float64 x) { return x + 0.75; }
_Float32x add_float32x_alias(_Float32x x) { return x + 1.25; }

int binary_float_aliases(void) {
  _Float32 f = 1.5f;
  _Float64 d = 2.25;
  _Float32x x = 3.5;
  if (sizeof(_Float32) != 4 || __alignof__(_Float32) != 4) return 599;
  if (sizeof(_Float64) != 8 || __alignof__(_Float64) != 8) return 600;
  if (sizeof(_Float32x) != 8 || __alignof__(_Float32x) != 8) return 601;
  if (add_float32_alias(f) != 2.0f) return 602;
  if (add_float64_alias(d) != 3.0) return 603;
  if (add_float32x_alias(x) != 4.75) return 604;
  return 0;
}

int unsupported_float_layout_constants(void) {
  if (sizeof(__float128) != 16 || __alignof__(_Float128) != 16) return 605;
  return 0;
}

int main(void) {
  struct Pair p;
  struct DPair q;
  struct Mix r;
  struct RevMix s;
  struct Big t;
  p = make_pair(0, 1);
  q = make_dpair(0.5, 0.5);
  r = make_mix(0, 1.0);
  s = make_rmix(1.0, 0);
  t = make_big(0, 1, 0);
  return seventh(1, 2, 3, 4, 5, 6, 7) +
         (int)ninth(1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 5.0) +
         isum(6, 1, 2, 3, 4, 5, 6) +
         (int)dsum(9, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0) +
         pair_sum(p) +
         pair_tail(1, 2, 3, 4, 5, 6, p) -
         2 +
         dpair_sum(q) +
         dpair_tail(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, q) -
         2 +
         mix_sum(r) +
         mix_tail(1, 2, 3, 4, 5, 6, r) -
         2 +
         mix_tail_then_double(1, 2, 3, 4, 5, 6, r, 5.0) -
         6 +
         rmix_sum(s) +
         rmix_tail(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, s) -
         2 +
         big_sum(t) +
         big_tail(1, 2, 3, 4, 5, 6, t) +
         big_sum(make_big(0, 1, 0)) -
         3 +
         iarray_sum(make_iarray(1, 0)) +
         (int)darray_sum(make_darray(0.5, 0.5)) +
         nested_sum(make_nested(0, 1.0)) -
         3 +
         partial_aggregate_eightbytes() +
         aligned_offset() +
         aligned_global() -
         18 +
         aligned_aggregate_scratch() +
         gnu_aligned_offset() +
         gnu_aligned_global() -
         18 +
         aligned_local() +
         indirect_calls() +
         bitfields() +
         unsigned_ops() +
         scalar_conversions() +
         floating_inc_dec() +
         pointer_compound_assign() +
         default_promotions() +
         target_predefines() +
         memory_builtins() +
         scalar_hint_builtins() +
         string_builtins() +
         formatted_builtins() +
         bit_builtins() +
         alloca_builtin() +
         atomic_builtins() +
         overflow_builtins() +
         integer_abs_builtins() +
         floating_builtins() +
         aggregate_object_copies() +
         compound_literals_and_initializers() +
         switch_dispatch() +
         global_initializers() +
         packed_aggregates() +
         packed_varargs() +
         nested_packed_aggregates() +
         pragma_once_probe() +
         generic_selection() +
         compile_time_selection() +
         gnu_typeof_selection() +
         gnu_auto_type_selection() +
         gnu_classify_type_selection() +
         gnu_noop_attributes() +
         alignof_selection() +
         function_pointer_param_conversions() +
         binary_float_aliases() +
         unsupported_float_layout_constants() +
         global_cast_pointer_initializers() +
         offsetof_designators() +
         var_pair(0, make_pair(0, 1)) +
         var_dpair(0, make_dpair(0.5, 0.5)) +
         var_big(0, make_big(0, 1, 0)) +
         var_pair_stack(1, 2, 3, 4, 5, make_pair(0, 1)) -
         4;
}
C

"$kimicc" -v -S -target linux-amd64 -I "$probe_include_dir" -o /tmp/kimicc-linux-amd64-smoke.s "$source_path"
grep -E '^[[:space:]]*\.hidden[[:space:]]+hidden_attr_value$' /tmp/kimicc-linux-amd64-smoke.s >/dev/null
grep -E '^[[:space:]]*\.set[[:space:]]+alias_attr_value,[[:space:]]*alias_attr_target$' /tmp/kimicc-linux-amd64-smoke.s >/dev/null
grep -E '^[[:space:]]*\.set[[:space:]]+alias_global_value,[[:space:]]*alias_global_target$' /tmp/kimicc-linux-amd64-smoke.s >/dev/null
grep -F $'\t.section\t.text.kimicc_section,"ax",@progbits' /tmp/kimicc-linux-amd64-smoke.s >/dev/null
grep -F $'\t.section\t.data.kimicc_section,"aw",@progbits' /tmp/kimicc-linux-amd64-smoke.s >/dev/null
"$kimicc" -c -target linux-amd64 -MMD -MP -MF "$dependency_path" -I "$probe_include_dir" -o "$object_path" "$source_path"
file "$object_path" | grep -E 'ELF 64-bit.*x86-64'
grep -F "$object_path: $source_path $probe_include_dir/pragma_once_header.h" "$dependency_path" >/dev/null
grep -F "$probe_include_dir/pragma_once_header.h:" "$dependency_path" >/dev/null
"$kimicc" -target linux-amd64 -MM -MP -I "$probe_include_dir" "$source_path" > "$dependency_stdout_path"
grep -F "$object_path: $source_path $probe_include_dir/pragma_once_header.h" "$dependency_stdout_path" >/dev/null
grep -F "$probe_include_dir/pragma_once_header.h:" "$dependency_stdout_path" >/dev/null

"$kimicc" -target linux-amd64 -I "$probe_include_dir" -o "$binary_path" "$source_path"
set +e
"$binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$libc_runtime_source_path" <<'C'
#include <ctype.h>
#include <errno.h>
#include <locale.h>
#include <math.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

static jmp_buf jb;
static volatile sig_atomic_t signal_seen = 0;

static int cmp_ints(const void *a, const void *b) {
  int av = *(const int *)a;
  int bv = *(const int *)b;
  return (av > bv) - (av < bv);
}

int jump_once(int n) {
  if (setjmp(jb) == 0) {
    longjmp(jb, n);
  }
  return n;
}

static void catch_signal(int signo) {
  signal_seen = signo;
}

static void exit_with_42(void) {
  _Exit(42);
}

int main(void) {
  char buf[64];
  char narrow[8];
  char *end = 0;
  int values[5] = { 5, 1, 4, 2, 3 };
  int key = 3;
  int *found;
  char *env;
  wchar_t wide[8];
  size_t (*strlen_ptr)(const char *) = strlen;
  long v = strtol("123x", &end, 10);
  if (v != 123 || *end != 'x') return 11;
  if (!isdigit('7') || tolower('A') != 'a') return 12;
  if (snprintf(buf, sizeof(buf), "%ld:%s", v, strerror(EINVAL)) <= 0) {
    return 13;
  }
  if (sqrt(81.0) != 9.0) return 14;
  if (jump_once(42) != 42) return 15;
  qsort(values, 5, sizeof(values[0]), cmp_ints);
  for (int i = 0; i < 5; i++) {
    if (values[i] != i + 1) return 16 + i;
  }
  found = bsearch(&key, values, 5, sizeof(values[0]), cmp_ints);
  if (!found || *found != 3) return 21;
  if (strlen_ptr("abcd") != 4) return 22;
  if (setenv("KIMICC_LINUX_AMD64_SMOKE_ENV", "ok", 1) != 0) return 23;
  env = getenv("KIMICC_LINUX_AMD64_SMOKE_ENV");
  if (!env || strcmp(env, "ok") != 0) return 24;
  if (unsetenv("KIMICC_LINUX_AMD64_SMOKE_ENV") != 0) return 25;
  if (getenv("KIMICC_LINUX_AMD64_SMOKE_ENV")) return 26;
  if (!setlocale(LC_ALL, "C")) return 27;
  if (mbstowcs(wide, "abc", 8) != 3) return 28;
  if (wcslen(wide) != 3) return 29;
  if (wide[0] != (wchar_t)'a' || wide[2] != (wchar_t)'c') return 30;
  if (wcstombs(narrow, wide, sizeof(narrow)) != 3) return 31;
  if (strcmp(narrow, "abc") != 0) return 32;
  if (btowc('Z') != (wint_t)'Z') return 33;
  if (wctob((wint_t)'Q') != 'Q') return 34;
  if (signal(SIGUSR1, catch_signal) == SIG_ERR) return 35;
  if (raise(SIGUSR1) != 0) return 36;
  if (signal_seen != SIGUSR1) return 37;
  if (signal(SIGUSR1, SIG_DFL) == SIG_ERR) return 38;
  if (atexit(exit_with_42) != 0) return 39;
  return 0;
}
C

"$kimicc" -target linux-amd64 -o "$libc_runtime_binary_path" \
  "$libc_runtime_source_path" -lm
set +e
"$libc_runtime_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected libc runtime smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$pthread_source_path" <<'C'
#include <pthread.h>
#include <sched.h>
#include <semaphore.h>

static int once_seen = 0;

static void mark_once(void) {
  once_seen++;
}

static void *worker(void *arg) {
  long *p = (long *)arg;
  *p = *p + 35;
  return arg;
}

int main(void) {
  pthread_t th;
  pthread_mutex_t mutex;
  pthread_cond_t cond;
  pthread_once_t once = PTHREAD_ONCE_INIT;
  pthread_key_t key;
  sem_t sem;
  long value = 7;
  void *ret = 0;
  if (pthread_mutex_init(&mutex, 0) != 0) return 21;
  if (pthread_mutex_lock(&mutex) != 0) return 22;
  value = value + 0;
  if (pthread_mutex_unlock(&mutex) != 0) return 23;
  if (pthread_cond_init(&cond, 0) != 0) return 24;
  if (pthread_cond_signal(&cond) != 0) return 25;
  if (pthread_once(&once, mark_once) != 0) return 26;
  if (pthread_once(&once, mark_once) != 0) return 27;
  if (once_seen != 1) return 28;
  if (pthread_key_create(&key, 0) != 0) return 29;
  if (pthread_setspecific(key, &value) != 0) return 30;
  if (pthread_getspecific(key) != &value) return 31;
  if (sem_init(&sem, 0, 0) != 0) return 32;
  if (sem_post(&sem) != 0) return 33;
  if (sem_wait(&sem) != 0) return 34;
  if (sched_yield() != 0) return 35;
  if (pthread_create(&th, 0, worker, &value) != 0) return 11;
  if (pthread_join(th, &ret) != 0) return 12;
  if (ret != &value) return 13;
  if (sem_destroy(&sem) != 0) return 36;
  if (pthread_key_delete(key) != 0) return 37;
  if (pthread_cond_destroy(&cond) != 0) return 38;
  if (pthread_mutex_destroy(&mutex) != 0) return 39;
  return (int)value;
}
C

"$kimicc" -target linux-amd64 -pthread -o "$pthread_binary_path" \
  "$pthread_source_path"
set +e
"$pthread_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected pthread smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$posix_runtime_source_path" <<'C'
#include <arpa/inet.h>
#include <dirent.h>
#include <fcntl.h>
#include <fnmatch.h>
#include <glob.h>
#include <grp.h>
#include <limits.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <pwd.h>
#include <regex.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/inotify.h>
#include <sys/mman.h>
#include <sys/random.h>
#include <sys/resource.h>
#include <sys/select.h>
#include <sys/sendfile.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/syscall.h>
#include <sys/timerfd.h>
#include <sys/times.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/utsname.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

int main(void) {
  char path[] = "/tmp/kimicc-posix-runtime-XXXXXX";
  int fd = mkstemp(path);
  char buf[8];
  char cwd[PATH_MAX];
  char hard_path[PATH_MAX];
  char sym_path[PATH_MAX];
  char renamed_path[PATH_MAX];
  char dir_path[PATH_MAX];
  char temp_dir[PATH_MAX];
  char fifo_path[PATH_MAX];
  char conf_path[PATH_MAX];
  char glob_pattern[PATH_MAX];
  char link_buf[PATH_MAX];
  struct stat st;
  struct stat path_st;
  struct flock file_lock;
  struct statvfs vfs;
  struct timespec ts;
  struct timespec sleep_time;
  struct timeval now;
  struct timeval timeval_pair[2];
  struct rusage usage;
  struct rlimit limit;
  struct tms tmsbuf;
  struct timespec times_pair[2];
  struct utsname uts;
  regex_t regex;
  regmatch_t match[1];
  glob_t paths;
  struct passwd *pw;
  struct group *gr;
  time_t now_time;
  clock_t ticks;
  uint64_t event_value;
  ssize_t link_len;
  off_t send_offset = 0;
  size_t conf_len;
  size_t length = 4096;
  long page_size;
  long name_max;
  mode_t old_mask;
  void *mem;
  char *mapped;
  int fds[2];
  int spair[2];
  int net_fd;
  int event_fd;
  int epoll_fd;
  int timer_fd;
  int inotify_fd;
  int reuse_addr = 1;
  int dup_fd;
  int fd_flags;
  int lock_result;
  int available = 0;
  struct pollfd pfd;
  struct epoll_event ep_event;
  struct iovec iov[2];
  fd_set readfds;
  struct timeval tv;
  struct sockaddr_in addr;
  struct sockaddr_in bound_addr;
  socklen_t bound_len = sizeof(bound_addr);
  struct addrinfo hints;
  struct addrinfo *resolved = 0;
  pid_t child;
  int wait_status = 0;
  char c = 0;
  char a = 0;
  char b = 0;
  char random_bytes[4];
  char host[256];
  char ipbuf[INET_ADDRSTRLEN];
  DIR *dir;
  if (fd < 0) return 11;
  if (write(fd, "abc", 3) != 3) return 12;
  if (lseek(fd, 0, SEEK_SET) != 0) return 13;
  if (read(fd, buf, 3) != 3) return 14;
  buf[3] = 0;
  if (strcmp(buf, "abc") != 0) return 15;
  if (fstat(fd, &st) != 0 || st.st_size != 3) return 16;
  if (pwrite(fd, "Z", 1, 1) != 1) return 96;
  if (pread(fd, buf, 3, 0) != 3) return 97;
  buf[3] = 0;
  if (strcmp(buf, "aZc") != 0) return 98;
  if (ftruncate(fd, 2) != 0) return 99;
  if (stat(path, &path_st) != 0 || path_st.st_size != 2) return 100;
  if (truncate(path, 3) != 0) return 101;
  if (stat(path, &path_st) != 0 || path_st.st_size != 3) return 102;
  if (pwrite(fd, "b", 1, 1) != 1) return 103;
  if (pwrite(fd, "c", 1, 2) != 1) return 104;
  if (fsync(fd) != 0) return 105;
  memset(&file_lock, 0, sizeof(file_lock));
  file_lock.l_type = F_WRLCK;
  file_lock.l_whence = SEEK_SET;
  if (fcntl(fd, F_SETLK, &file_lock) != 0) return 179;
  file_lock.l_type = F_UNLCK;
  if (fcntl(fd, F_SETLK, &file_lock) != 0) return 180;
  lock_result = flock(fd, LOCK_EX | LOCK_NB);
  if (lock_result != 0) return 181;
  if (flock(fd, LOCK_UN) != 0) return 182;
  if (lockf(fd, F_TEST, 0) != 0) return 183;
  if (lockf(fd, F_LOCK, 0) != 0) return 184;
  if (lockf(fd, F_ULOCK, 0) != 0) return 185;
  if (!getcwd(cwd, sizeof(cwd))) return 64;
  if (access(path, F_OK) != 0) return 65;
  if (stat(path, &path_st) != 0 || path_st.st_size != 3) return 66;
  if (snprintf(hard_path, sizeof(hard_path), "%s.hard", path) <= 0) return 80;
  if (snprintf(sym_path, sizeof(sym_path), "%s.sym", path) <= 0) return 81;
  if (snprintf(renamed_path, sizeof(renamed_path), "%s.renamed", path) <= 0) {
    return 82;
  }
  if (snprintf(dir_path, sizeof(dir_path), "%s.dir", path) <= 0) return 83;
  if (snprintf(glob_pattern, sizeof(glob_pattern), "%s*", path) <= 0) {
    return 126;
  }
  if (link(path, hard_path) != 0) return 84;
  if (stat(hard_path, &path_st) != 0 || path_st.st_size != 3) return 85;
  if (symlink(path, sym_path) != 0) return 86;
  link_len = readlink(sym_path, link_buf, sizeof(link_buf) - 1);
  if (link_len <= 0) return 87;
  link_buf[link_len] = 0;
  if (strcmp(link_buf, path) != 0) return 88;
  if (rename(hard_path, renamed_path) != 0) return 89;
  if (access(renamed_path, F_OK) != 0) return 90;
  if (chmod(renamed_path, S_IRUSR | S_IWUSR) != 0) return 91;
  if (mkdir(dir_path, S_IRWXU) != 0) return 92;
  if (rmdir(dir_path) != 0) return 93;
  if (unlink(sym_path) != 0) return 94;
  if (unlink(renamed_path) != 0) return 95;
  if (fnmatch("kimicc-*.c", "kimicc-smoke.c", 0) != 0) return 127;
  if (regcomp(&regex, "^a[bc]c$", REG_EXTENDED) != 0) return 128;
  if (regexec(&regex, "abc", 1, match, 0) != 0) return 129;
  if (match[0].rm_so != 0 || match[0].rm_eo != 3) return 130;
  regfree(&regex);
  if (glob(glob_pattern, 0, 0, &paths) != 0) return 131;
  if (paths.gl_pathc < 1) return 132;
  globfree(&paths);
  pw = getpwuid(getuid());
  if (!pw || !pw->pw_name || !pw->pw_name[0]) return 133;
  gr = getgrgid(getgid());
  if (!gr || !gr->gr_name || !gr->gr_name[0]) return 134;
  if (statvfs("/tmp", &vfs) != 0 || vfs.f_bsize == 0) return 135;
  page_size = sysconf(_SC_PAGESIZE);
  if (page_size <= 0) return 164;
  name_max = pathconf("/tmp", _PC_NAME_MAX);
  if (name_max <= 0) return 165;
  conf_len = confstr(_CS_PATH, conf_path, sizeof(conf_path));
  if (conf_len == 0 || conf_len >= sizeof(conf_path)) return 166;
  if (!conf_path[0]) return 167;
  if (getrlimit(RLIMIT_NOFILE, &limit) != 0) return 168;
  if (limit.rlim_cur == 0 || limit.rlim_max == 0) return 169;
  old_mask = umask(077);
  umask(old_mask);
  if (snprintf(temp_dir, sizeof(temp_dir), "%s.mkdtemp.XXXXXX", path) <= 0) {
    return 170;
  }
  if (!mkdtemp(temp_dir)) return 171;
  if (snprintf(fifo_path, sizeof(fifo_path), "%s/fifo", temp_dir) <= 0) {
    return 172;
  }
  if (mkfifo(fifo_path, S_IRUSR | S_IWUSR) != 0) return 173;
  if (lstat(fifo_path, &path_st) != 0 || !S_ISFIFO(path_st.st_mode)) {
    return 174;
  }
  timeval_pair[0].tv_sec = 0;
  timeval_pair[0].tv_usec = 0;
  timeval_pair[1].tv_sec = 0;
  timeval_pair[1].tv_usec = 0;
  if (utimes(path, timeval_pair) != 0) return 175;
  times_pair[0].tv_sec = 0;
  times_pair[0].tv_nsec = 0;
  times_pair[1].tv_sec = 0;
  times_pair[1].tv_nsec = 0;
  if (utimensat(AT_FDCWD, path, times_pair, 0) != 0) return 176;
  if (unlink(fifo_path) != 0) return 177;
  if (rmdir(temp_dir) != 0) return 178;
  dup_fd = dup(fd);
  if (dup_fd < 0) return 67;
  if (lseek(dup_fd, 0, SEEK_SET) != 0) return 68;
  if (read(dup_fd, buf, 3) != 3) return 69;
  buf[3] = 0;
  if (strcmp(buf, "abc") != 0) return 70;
  fd_flags = fcntl(dup_fd, F_GETFD);
  if (fd_flags < 0) return 71;
  if (fcntl(dup_fd, F_SETFD, fd_flags | FD_CLOEXEC) != 0) return 72;
  fd_flags = fcntl(dup_fd, F_GETFD);
  if (fd_flags < 0 || !(fd_flags & FD_CLOEXEC)) return 73;
  if (close(dup_fd) != 0) return 74;
  if (chdir("/tmp") != 0) return 75;
  if (chdir(cwd) != 0) return 76;
  if (clock_gettime(CLOCK_REALTIME, &ts) != 0) return 17;
  if (clock_getres(CLOCK_MONOTONIC, &ts) != 0) return 196;
  sleep_time.tv_sec = 0;
  sleep_time.tv_nsec = 0;
  if (nanosleep(&sleep_time, 0) != 0) return 197;
  if (clock_nanosleep(CLOCK_MONOTONIC, 0, &sleep_time, 0) != 0) return 198;
  if (timespec_get(&ts, TIME_UTC) != TIME_UTC) return 199;
  if (gettimeofday(&now, 0) != 0) return 106;
  now_time = time(0);
  if (now_time == (time_t)-1) return 107;
  if (uname(&uts) != 0) return 108;
  if (!uts.sysname[0] || !uts.machine[0]) return 109;
  if (gethostname(host, sizeof(host)) != 0) return 110;
  host[sizeof(host) - 1] = 0;
  if (!host[0]) return 111;
  if (getrusage(RUSAGE_SELF, &usage) != 0) return 112;
  ticks = times(&tmsbuf);
  if (ticks == (clock_t)-1) return 113;
  if (syscall(SYS_getpid) != getpid()) return 162;
  if (getrandom(random_bytes, sizeof(random_bytes), 0) !=
      sizeof(random_bytes)) {
    return 163;
  }
  if (ftruncate(fd, length) != 0) return 186;
  mem = mmap(0, length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (mem == MAP_FAILED) return 187;
  mapped = (char *)mem;
  strcpy(mapped, "abc");
  if (msync(mem, length, MS_SYNC) != 0) return 188;
  if (munmap(mem, length) != 0) return 189;
  if (ftruncate(fd, 3) != 0) return 190;
  if (lseek(fd, 0, SEEK_SET) != 0) return 191;
  if (read(fd, buf, 3) != 3) return 192;
  buf[3] = 0;
  if (strcmp(buf, "abc") != 0) return 193;
  mem = mmap(0, length, PROT_READ | PROT_WRITE,
             MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (mem == MAP_FAILED) return 18;
  mapped = (char *)mem;
  strcpy(mapped, "abc");
  if (madvise(mem, length, MADV_NORMAL) != 0) return 194;
  if (mprotect(mem, length, PROT_READ) != 0) return 195;
  if (strcmp(mapped, "abc") != 0) return 19;
  if (munmap(mem, length) != 0) return 20;
  if (pipe(fds) != 0) return 21;
  if (write(fds[1], "z", 1) != 1) return 22;
  if (ioctl(fds[0], FIONREAD, &available) != 0) return 150;
  if (available != 1) return 151;
  pfd.fd = fds[0];
  pfd.events = POLLIN;
  pfd.revents = 0;
  if (poll(&pfd, 1, 0) != 1 || !(pfd.revents & POLLIN)) return 23;
  FD_ZERO(&readfds);
  FD_SET(fds[0], &readfds);
  tv.tv_sec = 0;
  tv.tv_usec = 0;
  if (select(fds[0] + 1, &readfds, 0, 0, &tv) != 1) return 24;
  if (!FD_ISSET(fds[0], &readfds)) return 25;
  if (read(fds[0], &c, 1) != 1 || c != 'z') return 26;
  iov[0].iov_base = &a;
  iov[0].iov_len = 1;
  iov[1].iov_base = &b;
  iov[1].iov_len = 1;
  if (write(fds[1], "xy", 2) != 2) return 152;
  if (readv(fds[0], iov, 2) != 2) return 153;
  if (a != 'x' || b != 'y') return 154;
  iov[0].iov_base = "m";
  iov[0].iov_len = 1;
  iov[1].iov_base = "n";
  iov[1].iov_len = 1;
  if (writev(fds[1], iov, 2) != 2) return 155;
  if (read(fds[0], buf, 2) != 2) return 156;
  buf[2] = 0;
  if (strcmp(buf, "mn") != 0) return 157;
  send_offset = 0;
  if (sendfile(fds[1], fd, &send_offset, 3) != 3) return 158;
  if (send_offset != 3) return 159;
  if (read(fds[0], buf, 3) != 3) return 160;
  buf[3] = 0;
  if (strcmp(buf, "abc") != 0) return 161;
  close(fds[0]);
  close(fds[1]);
  event_fd = eventfd(0, EFD_CLOEXEC);
  if (event_fd < 0) return 136;
  epoll_fd = epoll_create1(EPOLL_CLOEXEC);
  if (epoll_fd < 0) return 137;
  memset(&ep_event, 0, sizeof(ep_event));
  ep_event.events = EPOLLIN;
  ep_event.data.fd = event_fd;
  if (epoll_ctl(epoll_fd, EPOLL_CTL_ADD, event_fd, &ep_event) != 0) {
    return 138;
  }
  event_value = 1;
  if (write(event_fd, &event_value, sizeof(event_value)) !=
      sizeof(event_value)) {
    return 139;
  }
  memset(&ep_event, 0, sizeof(ep_event));
  if (epoll_wait(epoll_fd, &ep_event, 1, 0) != 1) return 140;
  if (!(ep_event.events & EPOLLIN) || ep_event.data.fd != event_fd) return 141;
  event_value = 0;
  if (read(event_fd, &event_value, sizeof(event_value)) !=
      sizeof(event_value)) {
    return 142;
  }
  if (event_value != 1) return 143;
  if (close(epoll_fd) != 0) return 144;
  if (close(event_fd) != 0) return 145;
  timer_fd = timerfd_create(CLOCK_MONOTONIC, TFD_CLOEXEC);
  if (timer_fd < 0) return 146;
  if (close(timer_fd) != 0) return 147;
  inotify_fd = inotify_init1(IN_CLOEXEC);
  if (inotify_fd < 0) return 148;
  if (close(inotify_fd) != 0) return 149;
  if (socketpair(AF_UNIX, SOCK_STREAM, 0, spair) != 0) return 27;
  if (write(spair[0], "q", 1) != 1) return 28;
  if (read(spair[1], &c, 1) != 1 || c != 'q') return 29;
  close(spair[0]);
  close(spair[1]);
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons(0);
  if (inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr) != 1) return 114;
  if (!inet_ntop(AF_INET, &addr.sin_addr, ipbuf, sizeof(ipbuf))) return 115;
  if (strcmp(ipbuf, "127.0.0.1") != 0) return 116;
  net_fd = socket(AF_INET, SOCK_STREAM, 0);
  if (net_fd < 0) return 117;
  if (setsockopt(net_fd, SOL_SOCKET, SO_REUSEADDR,
                 &reuse_addr, sizeof(reuse_addr)) != 0) {
    return 118;
  }
  if (bind(net_fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) return 119;
  if (getsockname(net_fd, (struct sockaddr *)&bound_addr, &bound_len) != 0) {
    return 120;
  }
  if (bound_addr.sin_family != AF_INET || bound_len < sizeof(bound_addr)) {
    return 121;
  }
  if (ntohs(bound_addr.sin_port) == 0) return 122;
  if (close(net_fd) != 0) return 123;
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  if (getaddrinfo("localhost", "80", &hints, &resolved) != 0) return 124;
  if (!resolved || resolved->ai_family != AF_INET) return 125;
  freeaddrinfo(resolved);
  child = fork();
  if (child < 0) return 30;
  if (child == 0) _exit(42);
  if (waitpid(child, &wait_status, 0) != child) return 31;
  if (!WIFEXITED(wait_status) || WEXITSTATUS(wait_status) != 42) return 32;
  child = fork();
  if (child < 0) return 33;
  if (child == 0) {
    execlp("sh", "sh", "-c", "exit 43", (char *)0);
    _exit(127);
  }
  if (waitpid(child, &wait_status, 0) != child) return 34;
  if (!WIFEXITED(wait_status) || WEXITSTATUS(wait_status) != 43) return 35;
  if (getpid() <= 1) return 36;
  dir = opendir("/tmp");
  if (!dir) return 37;
  if (!readdir(dir)) return 38;
  if (closedir(dir) != 0) return 39;
  close(fd);
  unlink(path);
  return 42;
}
C

"$kimicc" -target linux-amd64 -o "$posix_runtime_binary_path" \
  "$posix_runtime_source_path"
set +e
"$posix_runtime_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected POSIX runtime smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$ctor_source_path" <<'C'
#include <stdlib.h>

static int lifecycle_seen = 0;

__attribute__((constructor))
static void kimicc_ctor(void) {
  lifecycle_seen = 40;
}

__attribute__((destructor))
static void kimicc_dtor(void) {
  if (lifecycle_seen == 42) {
    _Exit(42);
  }
}

int main(void) {
  if (lifecycle_seen != 40) return 41;
  lifecycle_seen = 42;
  return 0;
}
C

"$kimicc" -target linux-amd64 -o "$ctor_binary_path" "$ctor_source_path"
set +e
"$ctor_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected constructor/destructor smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$libm_source_path" <<'C'
#include <math.h>
int main(void) { return cos(0.0) == 1.0 ? 0 : 1; }
C

"$kimicc" -target linux-amd64 --library-directory /usr/lib/x86_64-linux-gnu \
  -o "$libm_binary_path" "$libm_source_path" -l m
"$libm_binary_path"

cat > "$dlfcn_source_path" <<'C'
#include <dlfcn.h>
#include <unistd.h>

typedef pid_t (*getpid_fn)(void);

int main(void) {
  void *handle = dlopen("libc.so.6", RTLD_NOW);
  char *err;
  getpid_fn loaded_getpid;
  if (!handle) return 31;
  dlerror();
  loaded_getpid = (getpid_fn)dlsym(handle, "getpid");
  err = dlerror();
  if (err || !loaded_getpid) return 32;
  if (loaded_getpid() != getpid()) return 33;
  if (dlclose(handle) != 0) return 34;
  return 42;
}
C

"$kimicc" -target linux-amd64 --library-directory /usr/lib/x86_64-linux-gnu \
  -o "$dlfcn_binary_path" "$dlfcn_source_path" -l dl
set +e
"$dlfcn_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected dlfcn smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$extensionless_source_path" <<'C'
int main(void) { return 42; }
C
cat > "$after_include_source_path" <<'C'
#include <after_header.h>
#if KIMICC_AFTER_HEADER != 1
#error expected after include header
#endif
int after_include_probe(void) { return KIMICC_AFTER_HEADER; }
C
cat > "$prefix_include_source_path" <<'C'
#include <prefix_header.h>
#if KIMICC_PREFIX_HEADER != 7
#error expected prefixed include header
#endif
int prefix_include_probe(void) { return KIMICC_PREFIX_HEADER; }
C
"$kimicc" -fsyntax-only -target linux-amd64 -x c "$extensionless_source_path"
"$kimicc" -fsyntax-only --target x86_64-pc-linux-gnu -I "$probe_include_dir" "$source_path"
"$kimicc" -fsyntax-only -target linux/amd64 -I "$probe_include_dir" "$source_path"
"$kimicc" -fsyntax-only -target linux-amd64 --include-directory "$probe_include_dir" "$source_path"
"$kimicc" -fsyntax-only -target linux-amd64 -idirafter "$probe_after_include_dir" \
  "$after_include_source_path"
"$kimicc" -fsyntax-only -target linux-amd64 -iprefix "$probe_prefix_dir/" \
  -iwithprefixbefore headers "$prefix_include_source_path"

cat > "$multi_main_source_path" <<'C'
int helper(void);
int main(void) { return helper() + 2; }
C

cat > "$multi_helper_source_path" <<'C'
int helper(void) { return 40; }
C

"$kimicc" -c -target linux-amd64 -MMD -MP \
  "$multi_main_source_path" "$multi_helper_source_path"
file "$multi_main_object_path" "$multi_helper_object_path" | grep -E 'ELF 64-bit.*x86-64'
grep -F "$multi_main_object_path: $multi_main_source_path" "$multi_main_dependency_path" >/dev/null
grep -F "$multi_helper_object_path: $multi_helper_source_path" "$multi_helper_dependency_path" >/dev/null

"$kimicc" -target linux-amd64 -MMD -MP -MF "$multi_dependency_path" \
  -o "$multi_binary_path" \
  "$multi_main_source_path" "$multi_helper_source_path"
grep -F "$multi_binary_path: $multi_main_source_path $multi_helper_source_path" "$multi_dependency_path" >/dev/null
grep -F "$multi_helper_source_path:" "$multi_dependency_path" >/dev/null
set +e
"$multi_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected multi-source smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$asm_source_path" <<'ASM'
.intel_syntax noprefix
.globl main
main:
  mov eax, 42
  ret
.section .note.GNU-stack,"",@progbits
ASM
cp "$asm_source_path" "$forced_asm_source_path"
cp "$asm_source_path" "$second_asm_source_path"

"$kimicc" -c -target linux-amd64 -o "$asm_object_path" "$asm_source_path"
"$kimicc" -c -target linux-amd64 -x assembler \
  -o "$forced_asm_object_path" "$forced_asm_source_path"
file "$forced_asm_object_path" | grep -E 'ELF 64-bit.*x86-64'
clang -o "$asm_binary_path" "$asm_object_path"
set +e
"$asm_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected assembly smoke binary to exit 42, got $status" >&2
  exit 1
fi
"$kimicc" -c -target linux-amd64 "$asm_source_path" "$second_asm_source_path"
file "$asm_object_path" "$second_asm_object_path" | grep -E 'ELF 64-bit.*x86-64'

cat > "$system_header_source_path" <<'C'
#include <stddef.h>
#include <stdint.h>
#include <stdalign.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <poll.h>
#include <signal.h>
#include <fpu_control.h>
#include <limits.h>
#include <float.h>

struct HeaderPair {
  uint8_t tag;
  uintptr_t value;
};

_Static_assert(CHAR_BIT == 8, "char bit width");
_Static_assert(UINT8_MAX == 255, "stdint uint8 max");
_Static_assert(UINT32_MAX == (uint32_t)-1, "stdint uint32 max");
_Static_assert(UINT64_MAX > UINT32_MAX, "stdint uint64 max");
_Static_assert(UINT64_MAX == (uint64_t)-1, "stdint uint64 exact max");
_Static_assert(UINTPTR_MAX > PTRDIFF_MAX, "stdint uintptr max");
_Static_assert(SIZE_MAX > PTRDIFF_MAX, "stddef size max");
_Static_assert(FLT_EVAL_METHOD == 0, "float eval method");
_Static_assert(FLT_RADIX == 2, "float radix");
_Static_assert(FLT_MANT_DIG == 24, "float mantissa");
_Static_assert(DBL_MANT_DIG == 53, "double mantissa");
_Static_assert(LDBL_MANT_DIG == 64, "long double mantissa");
_Static_assert(DECIMAL_DIG == 21, "decimal digits");
_Static_assert(sizeof(long double) == 16, "long double width");
_Static_assert(alignof(long double) == 16, "long double alignment");
_Static_assert(sizeof(_Float16) == 2, "_Float16 width");
_Static_assert(alignof(_Float16) == 2, "_Float16 alignment");
_Static_assert(sizeof(uintptr_t) == 8, "stdint uintptr width");
_Static_assert(sizeof(int64_t) == 8, "stdint int64 width");
_Static_assert(sizeof(uint64_t) == 8, "stdint uint64 width");
_Static_assert(sizeof(size_t) == 8, "stddef size_t width");
_Static_assert(sizeof(ptrdiff_t) == 8, "stddef ptrdiff_t width");
_Static_assert(sizeof(register_t) == 8, "sys/types register_t width");
_Static_assert(sizeof(off_t) == 8, "sys/types off_t width");
_Static_assert(sizeof(time_t) == 8, "time_t width");
_Static_assert(sizeof(socklen_t) == 4, "socklen_t width");
_Static_assert(sizeof(FILE *) == 8, "stdio FILE pointer width");
_Static_assert(sizeof(struct stat) > 0, "sys/stat struct stat complete");
_Static_assert(sizeof(struct iovec) > 0, "sys/uio struct iovec complete");
_Static_assert(sizeof(struct pollfd) > 0, "poll struct pollfd complete");
_Static_assert(sizeof(fpu_control_t) == 2, "fpu_control_t width");
_Static_assert((int64_t)-1 < 0, "stdint int64 signedness");
_Static_assert((ptrdiff_t)-1 < 0, "stddef ptrdiff_t signedness");
_Static_assert(EINVAL > 0, "errno EINVAL");
_Static_assert(STDOUT_FILENO == 1, "unistd stdout fileno");
_Static_assert(F_GETFL >= 0, "fcntl command macro");
_Static_assert(AF_INET > 0, "socket AF_INET");
_Static_assert(POLLIN > 0, "poll POLLIN");
_Static_assert(SIGTERM > 0, "signal SIGTERM");
_Static_assert(alignof(unsigned long) == 8, "unsigned long alignment");
_Static_assert(offsetof(struct HeaderPair, value) == 8, "offsetof header pair");

int header_sum(int n, ...) {
  va_list ap;
  int total = 0;
  va_start(ap, n);
  for (int i = 0; i < n; i++) {
    total = total + va_arg(ap, int);
  }
  va_end(ap);
  return total;
}

int main(void) {
  alignas(16) uint8_t buf[16];
  uintptr_t addr = (uintptr_t)buf;
  bool ok = true;
  if ((addr & 15) != 0) return 31;
  if (!ok) return 32;
  if (FLT_ROUNDS != 1) return 33;
  return header_sum(4, 10, 20, 5, 7);
}
C

"$kimicc" -E -target linux-amd64 -o "$system_header_preprocessed_path" "$system_header_source_path"
grep -E 'typedef[[:space:]][^;]*[[:space:]]uint8_t;' "$system_header_preprocessed_path" >/dev/null
grep -E 'typedef[[:space:]][^;]*[[:space:]]uintptr_t;' "$system_header_preprocessed_path" >/dev/null
grep -E 'typedef[[:space:]][^;]*[[:space:]]size_t;' "$system_header_preprocessed_path" >/dev/null
grep -E 'typedef[[:space:]][^;]*[[:space:]]ptrdiff_t;' "$system_header_preprocessed_path" >/dev/null
grep -E 'typedef[[:space:]][^;]*[[:space:]]va_list;' "$system_header_preprocessed_path" >/dev/null
"$kimicc" -c -target linux-amd64 -o "$system_header_object_path" "$system_header_source_path"
clang -o "$system_header_binary_path" "$system_header_object_path"
set +e
"$system_header_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected system-header smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$header_syntax_source_path" <<'C'
#include <arpa/inet.h>
#include <assert.h>
#include <ctype.h>
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fnmatch.h>
#include <glob.h>
#include <grp.h>
#include <inttypes.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <netdb.h>
#include <netinet/in.h>
#include <pthread.h>
#include <pwd.h>
#include <regex.h>
#include <sched.h>
#include <semaphore.h>
#include <setjmp.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wchar.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/inotify.h>
#include <sys/mman.h>
#include <sys/random.h>
#include <sys/resource.h>
#include <sys/select.h>
#include <sys/sendfile.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/syscall.h>
#include <sys/timerfd.h>
#include <sys/times.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/utsname.h>
#include <sys/uio.h>
#include <sys/wait.h>
int main(void) {
  return sizeof(DIR *) + sizeof(FILE *) + sizeof(jmp_buf) +
    sizeof(pthread_t) + sizeof(sigset_t) + sizeof(fd_set) +
    sizeof(struct timeval) + sizeof(struct rusage) +
    sizeof(struct tms) + sizeof(struct utsname) +
    sizeof(struct addrinfo) + sizeof(struct sockaddr_in) +
    sizeof(regex_t) + sizeof(glob_t) + sizeof(struct passwd) +
    sizeof(struct group) + sizeof(struct statvfs) +
    sizeof(struct flock) + sizeof(struct epoll_event) + sizeof(struct iovec) +
    sizeof(sem_t) > 0;
}
C

"$kimicc" -fsyntax-only -target linux-amd64 "$header_syntax_source_path"

cat > "$va_list_source_path" <<'C'
#include <stdarg.h>
#include <stdio.h>

int render(char *buf, const char *fmt, ...) {
  va_list ap;
  int n;
  va_start(ap, fmt);
  n = vsnprintf(buf, 64, fmt, ap);
  va_end(ap);
  return n;
}

int main(void) {
  char buf[64];
  int n = render(buf, "i=%d s=%s f=%.1f", 7, "ok", 2.5);
  if (n != 14) return 40;
  if (buf[0] != 'i' || buf[2] != '7' || buf[6] != 'o') return 41;
  if (buf[9] != 'f' || buf[11] != '2' || buf[13] != '5') return 41;
  if (buf[14] != 0) return 41;
  return 42;
}
C

"$kimicc" -target linux-amd64 -o "$va_list_binary_path" "$va_list_source_path"
set +e
"$va_list_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected va_list interop smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$strict_mir_varargs_source_path" <<'C'
typedef __builtin_va_list va_list;

struct Pair {
  long a;
  long b;
};

struct DPair {
  double a;
  double b;
};

struct Big {
  long a;
  long b;
  long c;
};

int pair_sum(struct Pair p) { return (int)(p.a + p.b); }

int pair_tail(int a, int b, int c, int d, int e, int f, struct Pair p) {
  return (int)(p.a + p.b);
}

int dpair_sum(struct DPair p) { return (int)(p.a + p.b); }

int big_sum(struct Big p) { return (int)(p.a + p.b + p.c); }

int read_pair(int tag, ...) {
  va_list ap;
  struct Pair p;
  __builtin_va_start(ap, tag);
  p = __builtin_va_arg(ap, struct Pair);
  __builtin_va_end(ap);
  return tag + (int)p.a + (int)p.b;
}

int read_big(int tag, ...) {
  va_list ap;
  struct Big p;
  __builtin_va_start(ap, tag);
  p = __builtin_va_arg(ap, struct Big);
  __builtin_va_end(ap);
  return tag + (int)p.a + (int)p.b + (int)p.c;
}

int main(void) {
  struct Pair p;
  struct DPair d;
  struct Big b;
  p.a = 10;
  p.b = 20;
  d.a = 19.5;
  d.b = 22.5;
  b.a = 1;
  b.b = 2;
  b.c = 3;
  return pair_sum(p) + pair_tail(1, 2, 3, 4, 5, 6, p) + dpair_sum(d) +
         big_sum(b) + read_pair(4, p) + read_big(5, b);
}
C

"$kimicc" --strict-mir-codegen -target linux-amd64 -o "$strict_mir_varargs_binary_path" "$strict_mir_varargs_source_path"
set +e
"$strict_mir_varargs_binary_path"
status=$?
set -e
if [ "$status" -ne 153 ]; then
  echo "expected strict MIR aggregate varargs smoke binary to exit 153, got $status" >&2
  exit 1
fi

cat > "$strict_mir_returns_source_path" <<'C'
struct Pair {
  long a;
  long b;
};

struct DPair {
  double a;
  double b;
};

struct Mix {
  long a;
  double b;
};

struct Pair make_pair(long a, long b) {
  struct Pair p;
  p.a = a;
  p.b = b;
  return p;
}

struct DPair make_dpair(double a, double b) {
  struct DPair p;
  p.a = a;
  p.b = b;
  return p;
}

struct Mix make_mix(long a, double b) {
  struct Mix p;
  p.a = a;
  p.b = b;
  return p;
}
C

cat > "$strict_mir_returns_driver_path" <<'C'
struct Pair {
  long a;
  long b;
};

struct DPair {
  double a;
  double b;
};

struct Mix {
  long a;
  double b;
};

struct Pair make_pair(long, long);
struct DPair make_dpair(double, double);
struct Mix make_mix(long, double);

int main(void) {
  struct Pair p = make_pair(10, 20);
  struct DPair d = make_dpair(19.5, 22.5);
  struct Mix m = make_mix(5, 6.5);
  return (int)(p.a + p.b + d.a + d.b + m.a + m.b);
}
C

"$kimicc" --strict-mir-codegen -c -target linux-amd64 \
  -o "$strict_mir_returns_object_path" "$strict_mir_returns_source_path"
clang -target x86_64-linux-gnu -c -o "$strict_mir_returns_driver_object_path" \
  "$strict_mir_returns_driver_path"
clang -o "$strict_mir_returns_binary_path" "$strict_mir_returns_object_path" \
  "$strict_mir_returns_driver_object_path"
set +e
"$strict_mir_returns_binary_path"
status=$?
set -e
if [ "$status" -ne 83 ]; then
  echo "expected strict MIR aggregate returns smoke binary to exit 83, got $status" >&2
  exit 1
fi

cat > "$strict_mir_return_calls_source_path" <<'C'
struct Pair {
  long a;
  long b;
};

struct DPair {
  double a;
  double b;
};

struct Mix {
  long a;
  double b;
};

struct Pair make_pair(long a, long b) {
  struct Pair p;
  p.a = a;
  p.b = b;
  return p;
}

struct Pair forward_pair(long a, long b) {
  return make_pair(a, b);
}

struct DPair make_dpair(double a, double b) {
  struct DPair p;
  p.a = a;
  p.b = b;
  return p;
}

struct Mix make_mix(long a, double b) {
  struct Mix p;
  p.a = a;
  p.b = b;
  return p;
}

int main(void) {
  struct Pair p = forward_pair(10, 20);
  struct DPair d = make_dpair(19.5, 22.5);
  struct Mix m;
  m = make_mix(5, 6.5);
  return (int)(p.a + p.b + d.a + d.b + m.a + m.b);
}
C

"$kimicc" --strict-mir-codegen -target linux-amd64 \
  -o "$strict_mir_return_calls_binary_path" "$strict_mir_return_calls_source_path"
set +e
"$strict_mir_return_calls_binary_path"
status=$?
set -e
if [ "$status" -ne 83 ]; then
  echo "expected strict MIR aggregate return calls smoke binary to exit 83, got $status" >&2
  exit 1
fi

cat > "$strict_mir_return_args_source_path" <<'C'
typedef __builtin_va_list va_list;

struct Pair {
  long a;
  long b;
};

struct DPair {
  double a;
  double b;
};

struct Mix {
  long a;
  double b;
};

struct Pair make_pair(long a, long b) {
  struct Pair p;
  p.a = a;
  p.b = b;
  return p;
}

struct DPair make_dpair(double a, double b) {
  struct DPair p;
  p.a = a;
  p.b = b;
  return p;
}

struct Mix make_mix(long a, double b) {
  struct Mix p;
  p.a = a;
  p.b = b;
  return p;
}

int pair_sum(struct Pair p) { return (int)(p.a + p.b); }

int pair_tail(int a, int b, int c, int d, int e, int f, struct Pair p) {
  return (int)(p.a + p.b);
}

int dpair_sum(struct DPair p) { return (int)(p.a + p.b); }

int mix_sum(struct Mix p) { return (int)(p.a + p.b); }

int read_pair(int tag, ...) {
  va_list ap;
  __builtin_va_start(ap, tag);
  struct Pair p = __builtin_va_arg(ap, struct Pair);
  __builtin_va_end(ap);
  return tag + (int)p.a + (int)p.b;
}

int main(void) {
  return pair_sum(make_pair(10, 20)) +
         pair_tail(1, 2, 3, 4, 5, 6, make_pair(1, 2)) +
         dpair_sum(make_dpair(19.5, 22.5)) +
         mix_sum(make_mix(5, 6.5)) +
         read_pair(3, make_pair(4, 5));
}
C

"$kimicc" --strict-mir-codegen -target linux-amd64 \
  -o "$strict_mir_return_args_binary_path" "$strict_mir_return_args_source_path"
set +e
"$strict_mir_return_args_binary_path"
status=$?
set -e
if [ "$status" -ne 98 ]; then
  echo "expected strict MIR aggregate return args smoke binary to exit 98, got $status" >&2
  exit 1
fi

cat > "$strict_mir_indirect_returns_source_path" <<'C'
struct Pair {
  long a;
  long b;
};

struct DPair {
  double a;
  double b;
};

struct Pair make_pair(long a, long b) {
  struct Pair p;
  p.a = a;
  p.b = b;
  return p;
}

struct DPair make_dpair(double a, double b) {
  struct DPair p;
  p.a = a;
  p.b = b;
  return p;
}

int pair_sum(struct Pair p) { return (int)(p.a + p.b); }

int dpair_sum(struct DPair p) { return (int)(p.a + p.b); }

struct Pair forward_pair(long a, long b) {
  struct Pair (*fp)(long, long) = make_pair;
  return fp(a, b);
}

int main(void) {
  struct Pair (*fp)(long, long) = make_pair;
  struct DPair (*fd)(double, double) = make_dpair;
  struct Pair p = fp(10, 20);
  struct Pair q;
  q = fp(1, 2);
  struct DPair d = fd(19.5, 22.5);
  return pair_sum(fp(3, 4)) + pair_sum(p) + pair_sum(q) +
         pair_sum(forward_pair(5, 6)) + dpair_sum(d);
}
C

"$kimicc" --strict-mir-codegen -target linux-amd64 \
  -o "$strict_mir_indirect_returns_binary_path" "$strict_mir_indirect_returns_source_path"
set +e
"$strict_mir_indirect_returns_binary_path"
status=$?
set -e
if [ "$status" -ne 93 ]; then
  echo "expected strict MIR indirect aggregate returns smoke binary to exit 93, got $status" >&2
  exit 1
fi

cat > "$old_source_path" <<'C'
int old_mix();
float one(void) { return 1.5f; }
int main(void) {
  signed char c = 2;
  return old_mix(c, one());
}
C

cat > "$old_helper_path" <<'C'
int old_mix(int a, double b) { return a + (int)b + 39; }
C

"$kimicc" -c -target linux-amd64 -o "$old_object_path" "$old_source_path"
clang -target x86_64-linux-gnu -c -o "$old_helper_object_path" "$old_helper_path"
clang -o "$old_binary_path" "$old_object_path" "$old_helper_object_path"
set +e
"$old_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected old-style promotion smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$weak_source_path" <<'C'
__attribute__((weak)) int weak_answer(void) { return 1; }
int main(void) { return weak_answer(); }
C

cat > "$weak_helper_path" <<'C'
int weak_answer(void) { return 42; }
C

"$kimicc" -c -target linux-amd64 -o "$weak_object_path" "$weak_source_path"
clang -target x86_64-linux-gnu -c -o "$weak_helper_object_path" \
  "$weak_helper_path"
clang -o "$weak_binary_path" "$weak_object_path" "$weak_helper_object_path"
set +e
"$weak_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected weak symbol override smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$weak_source_path" <<'C'
extern int weak_missing(void) __attribute__((weak));
int main(void) { return weak_missing ? 1 : 42; }
C

"$kimicc" -target linux-amd64 -o "$weak_binary_path" "$weak_source_path"
set +e
"$weak_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected undefined weak symbol smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$weak_source_path" <<'C'
__attribute__((weak)) int weak_value = 1;
int main(void) { return weak_value; }
C

cat > "$weak_helper_path" <<'C'
int weak_value = 42;
C

"$kimicc" -c -target linux-amd64 -o "$weak_object_path" "$weak_source_path"
clang -target x86_64-linux-gnu -c -o "$weak_helper_object_path" \
  "$weak_helper_path"
clang -o "$weak_binary_path" "$weak_object_path" "$weak_helper_object_path"
set +e
"$weak_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected weak global override smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$weak_source_path" <<'C'
extern int weak_global_missing __attribute__((weak));
int main(void) { return &weak_global_missing ? 1 : 42; }
C

"$kimicc" -target linux-amd64 -o "$weak_binary_path" "$weak_source_path"
set +e
"$weak_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected undefined weak global smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$ternary_source_path" <<'C'
double choose_double(int flag) { return flag ? 1 : 2.5; }
int choose_int(int flag) { return flag ? 1.5 : 2; }
unsigned long choose_ulong(int flag) { return flag ? -1 : 2UL; }
int choose_ptr_zero_first(int flag) {
  int value = 42;
  int *p = flag ? 0 : &value;
  return p ? *p : 0;
}

int main(void) {
  if (choose_double(1) != 1.0) return 39;
  if (choose_double(0) != 2.5) return 40;
  if (choose_int(1) != 1) return 41;
  if (choose_int(0) != 2) return 41;
  if (choose_ulong(1) != (unsigned long)-1) return 41;
  if (choose_ulong(0) != 2UL) return 41;
  if (choose_ptr_zero_first(1) != 0) return 41;
  if (choose_ptr_zero_first(0) != 42) return 41;
  return 42;
}
C

"$kimicc" -target linux-amd64 -o "$ternary_binary_path" "$ternary_source_path"
set +e
"$ternary_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected mixed ternary smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$callee_saved_source_path" <<'C'
int check_r13_preserved(void);

int aligned_touch(void) {
  _Alignas(32) int slots[8];
  slots[0] = 42;
  slots[7] = 0;
  return slots[0] + slots[7];
}

int main(void) {
  if (aligned_touch() != 42) return 41;
  return check_r13_preserved() ? 42 : 40;
}
C

cat > "$callee_saved_helper_path" <<'ASM'
.intel_syntax noprefix
.text
.globl check_r13_preserved
.type check_r13_preserved, @function
check_r13_preserved:
  push rbp
  mov rbp, rsp
  push r13
  sub rsp, 8
  movabs r13, 0x1122334455667788
  call aligned_touch
  cmp eax, 42
  jne .Lbad_r13
  movabs rax, 0x1122334455667788
  cmp r13, rax
  sete al
  movzx eax, al
  jmp .Ldone_r13
.Lbad_r13:
  xor eax, eax
.Ldone_r13:
  add rsp, 8
  pop r13
  pop rbp
  ret
.size check_r13_preserved, .-check_r13_preserved
.section .note.GNU-stack,"",@progbits
ASM

"$kimicc" -c -target linux-amd64 -o "$callee_saved_object_path" "$callee_saved_source_path"
clang -target x86_64-linux-gnu -c -o "$callee_saved_helper_object_path" "$callee_saved_helper_path"
clang -o "$callee_saved_binary_path" "$callee_saved_object_path" "$callee_saved_helper_object_path"
set +e
"$callee_saved_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected callee-saved r13 smoke binary to exit 42, got $status" >&2
  exit 1
fi

cat > "$int128_source_path" <<'C'
typedef __builtin_va_list va_list;

__uint128_t make_u128(unsigned long hi, unsigned long lo);
int check_u128(__uint128_t x);
int check_parts(__uint128_t x, unsigned long hi, unsigned long lo);
int check_stack_after_scalar(long a, long b, long c, long d, long e, long f, long g, __uint128_t x);
int check_var_after_named(long a, long b, long c, long d, long e, long f, long g, __uint128_t named, ...);
int call_kimicc_stack_u128(__uint128_t x);

struct BigAlignedStack {
  _Alignas(32) long a;
  long b;
  long c;
};

int check_big_aligned_stack(long a, long b, long c, long d, long e, long f, long g, struct BigAlignedStack p);
int call_kimicc_big_aligned_stack(struct BigAlignedStack p);

__uint128_t id_u128(__uint128_t x) { return x; }

__uint128_t stack_u128(long a, long b, long c, long d, long e, __uint128_t x) {
  return x;
}

__uint128_t stack_u128_after_scalar(long a, long b, long c, long d, long e, long f, long g, __uint128_t x) {
  return x;
}

int kimicc_stack_u128(long a, long b, long c, long d, long e, long f, long g, __uint128_t x) {
  if (a != 1 || b != 2 || c != 3 || d != 4 || e != 5 || f != 6 || g != 7) return 0;
  return check_parts(x, 1, 41) ? 31 : 0;
}

int kimicc_big_aligned_stack(long a, long b, long c, long d, long e, long f, long g, struct BigAlignedStack p) {
  if (a != 1 || b != 2 || c != 3 || d != 4 || e != 5 || f != 6 || g != 7) return 0;
  return p.a == 33 && p.b == 34 && p.c == 35 ? 33 : 0;
}

int read_u128(int tag, ...) {
  va_list ap;
  __uint128_t x;
  __builtin_va_start(ap, tag);
  x = __builtin_va_arg(ap, __uint128_t);
  __builtin_va_end(ap);
  return check_u128(x);
}

int main(void) {
  __uint128_t x = id_u128(make_u128(1, 41));
  __uint128_t high_only = id_u128(make_u128(1, 0));
  __uint128_t zero = 0;
  _Bool high_bool = high_only;
  _Bool zero_bool = zero;
  if (check_u128(x) != 14) return 1;
  if (check_u128(stack_u128(1, 2, 3, 4, 5, x)) != 14) return 2;
  if (read_u128(0, x) != 14) return 3;
  if (check_u128(stack_u128_after_scalar(1, 2, 3, 4, 5, 6, 7, x)) != 14) return 29;
  if (check_stack_after_scalar(1, 2, 3, 4, 5, 6, 7, x) != 29) return 29;
  if (check_var_after_named(1, 2, 3, 4, 5, 6, 7, x, x) != 30) return 30;
  if (call_kimicc_stack_u128(x) != 31) return 31;
  struct BigAlignedStack p;
  p.a = 33;
  p.b = 34;
  p.c = 35;
  if (check_big_aligned_stack(1, 2, 3, 4, 5, 6, 7, p) != 32) return 32;
  if (call_kimicc_big_aligned_stack(p) != 33) return 33;
  if (!high_only) return 4;
  if (!high_bool) return 5;
  if (zero) return 6;
  if (zero_bool) return 7;
  if (!zero) {
  } else {
    return 8;
  }

  __uint128_t a = make_u128(1, 40);
  __uint128_t b = make_u128(0, 2);
  if (!check_parts(a + b, 1, 42)) return 9;
  if (!check_parts(a - b, 1, 38)) return 10;
  if (!check_parts(a * make_u128(0, 3), 3, 120)) return 11;
  if (!check_parts((a * make_u128(0, 3)) / make_u128(0, 3), 1, 40)) return 12;
  if (!check_parts(make_u128(0, 122) % make_u128(0, 5), 0, 2)) return 13;
  if (!check_parts(make_u128(0, 1) << 65, 2, 0)) return 14;
  if (!check_parts(make_u128(4, 0) >> 65, 0, 2)) return 15;
  if (!(make_u128(1, 0) > make_u128(0, 99))) return 16;
  if (make_u128(0, 99) >= make_u128(1, 0)) return 17;

  __int128_t signed_neg = -((__int128_t)1);
  if (!(signed_neg < 0)) return 18;
  if (signed_neg >= 0) return 19;
  if ((signed_neg >> 65) != signed_neg) return 20;
  if (((__int128_t)-12345 / (__int128_t)100) != (__int128_t)-123) return 25;
  if (((__int128_t)-12345 % (__int128_t)100) != (__int128_t)-45) return 26;
  __int128_t signed_compound = (__int128_t)-1000;
  signed_compound /= (__int128_t)7;
  if (signed_compound != (__int128_t)-142) return 27;
  signed_compound %= (__int128_t)11;
  if (signed_compound != (__int128_t)-10) return 28;

  unsigned long all = 0;
  all = ~all;
  if (!check_parts(~zero, all, all)) return 21;

  __uint128_t compound = make_u128(0, 1);
  compound += make_u128(1, 0);
  compound <<= 1;
  if (!check_parts(compound, 2, 2)) return 22;
  compound >>= 1;
  compound *= make_u128(0, 3);
  if (!check_parts(compound, 3, 3)) return 23;
  compound /= make_u128(0, 3);
  compound &= make_u128(0, 1);
  compound |= make_u128(2, 0);
  compound ^= make_u128(1, 0);
  if (!check_parts(compound, 3, 1)) return 24;
  return 42;
}
C

cat > "$int128_helper_path" <<'C'
#include <stdarg.h>

int check_parts(__uint128_t x, unsigned long expected_hi, unsigned long expected_lo);
int kimicc_stack_u128(long a, long b, long c, long d, long e, long f, long g, __uint128_t x);

struct BigAlignedStack {
  _Alignas(32) long a;
  long b;
  long c;
};

int kimicc_big_aligned_stack(long a, long b, long c, long d, long e, long f, long g, struct BigAlignedStack p);

__uint128_t make_u128(unsigned long hi, unsigned long lo) {
  return ((__uint128_t)hi << 64) | lo;
}

int check_u128(__uint128_t x) {
  return check_parts(x, 1, 41) ? 14 : 0;
}

int check_parts(__uint128_t x, unsigned long expected_hi, unsigned long expected_lo) {
  unsigned long actual_hi = (unsigned long)(x >> 64);
  unsigned long actual_lo = (unsigned long)x;
  return actual_hi == expected_hi && actual_lo == expected_lo;
}

int check_stack_after_scalar(long a, long b, long c, long d, long e, long f, long g, __uint128_t x) {
  if (a != 1 || b != 2 || c != 3 || d != 4 || e != 5 || f != 6 || g != 7) return 0;
  return check_parts(x, 1, 41) ? 29 : 0;
}

int check_var_after_named(long a, long b, long c, long d, long e, long f, long g, __uint128_t named, ...) {
  va_list ap;
  __uint128_t x;
  if (a != 1 || b != 2 || c != 3 || d != 4 || e != 5 || f != 6 || g != 7) return 0;
  if (!check_parts(named, 1, 41)) return 0;
  va_start(ap, named);
  x = va_arg(ap, __uint128_t);
  va_end(ap);
  return check_parts(x, 1, 41) ? 30 : 0;
}

int call_kimicc_stack_u128(__uint128_t x) {
  return kimicc_stack_u128(1, 2, 3, 4, 5, 6, 7, x);
}

int check_big_aligned_stack(long a, long b, long c, long d, long e, long f, long g, struct BigAlignedStack p) {
  if (a != 1 || b != 2 || c != 3 || d != 4 || e != 5 || f != 6 || g != 7) return 0;
  return p.a == 33 && p.b == 34 && p.c == 35 ? 32 : 0;
}

int call_kimicc_big_aligned_stack(struct BigAlignedStack p) {
  return kimicc_big_aligned_stack(1, 2, 3, 4, 5, 6, 7, p);
}
C

"$kimicc" -c -target linux-amd64 -o "$int128_object_path" "$int128_source_path"
clang -target x86_64-linux-gnu -c -o "$int128_helper_object_path" "$int128_helper_path"
clang -o "$int128_binary_path" "$int128_object_path" "$int128_helper_object_path"
set +e
"$int128_binary_path"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "expected int128 ABI smoke binary to exit 42, got $status" >&2
  exit 1
fi

echo "linux-amd64 smoke passed"
