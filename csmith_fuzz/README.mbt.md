# Csmith Differential Fuzzing

This package drives Csmith-generated C programs through kimicc and clang, then
compares the runtime result. The generated programs are reduced to a profile
that kimicc can compile today. Every case is preprocessed independently by
kimicc and clang before each compiler sees its own input.

## Prerequisites

On macOS, install these tools before running the fuzzer:

```sh
brew install csmith coreutils
```

The required commands are:

- `csmith`, used to generate random C programs.
- `clang`, used as the reference preprocessor and compiler.
- `timeout` or `gtimeout`, used to cap compile/run time for every case.
- `moon`, used when `KIMICC_CSMITH_KIMICC` is not set.

If the Csmith include directory cannot be discovered automatically, set it
explicitly. For a Homebrew install on Apple Silicon this is usually:

```sh
export KIMICC_CSMITH_INCLUDE_ROOT=/opt/homebrew/opt/csmith/include/csmith-2.3.0
```

## Compile And Compare Scheme

Each fuzz case follows this automatic pipeline:

1. Generate C with Csmith using a deterministic seed.
2. Preprocess the generated source with kimicc:

   ```sh
   kimicc -E -DCSMITH_MINIMAL -I "$KIMICC_CSMITH_INCLUDE_ROOT" -include compat.h input.c -o kimicc.i
   ```

3. Preprocess the generated source separately with clang:

   ```sh
   clang -w -E -P -DCSMITH_MINIMAL -I "$KIMICC_CSMITH_INCLUDE_ROOT" -include compat.h input.c -o clang.i
   ```

4. Compile and run `clang.i` with clang first.
5. If the clang binary times out, discard the case. This means the reference
   program is not useful for differential testing, so it is recorded but not
   saved as a kimicc bug (CSmith does not promise to generate terminating programs)
6. Compile `kimicc.i` with kimicc directly to an executable.
7. Run the kimicc binary and compare exit code plus stdout against clang.
8. On a difference, save the kimicc-preprocessed program under `test/bugs/` and write
   the full record under the record root.

Runtime mismatch logs include the seed and both Csmith checksums, for example:

```text
csmith csmith_fuzz_0 seed=209 mismatch clang-checksum=6a43d8cf kimicc-checksum=6a409c84
```

## Standalone Runner

Build the native binaries first:

```sh
moon build --target native
```

Run the standalone fuzzer directly when you want streaming logs:

```sh
export KIMICC_CSMITH_KIMICC="$PWD/_build/native/debug/build/cmd/main/main.exe"
_build/native/debug/build/cmd/csmith_fuzz/csmith_fuzz.exe --seed 7 --count 20
```

`--seed` is the first seed in the batch. The runner uses:

```text
seed_for_case = first_seed + case_index * 101
```

`--count` is the number of cases to run. The default is `20`.

You can also run it through `moon`, but direct execution is preferred for long
runs because the log appears incrementally:

```sh
KIMICC_CSMITH_KIMICC="$PWD/_build/native/debug/build/cmd/main/main.exe" \
  moon run cmd/csmith_fuzz --target native -- --seed 7 --count 20
```

The process exits with code `0` if no kimicc abnormal case is found. It exits
with code `1` after saving any mismatch, kimicc timeout, or kimicc compile
failure.

## Outputs

The default bug directory is:

```text
test/bugs
```

Abnormal kimicc cases are saved as preprocessed C files:

```text
test/bugs/csmith_seed_<seed>_<stage>.c
```

These files are intentionally preprocessed so they can be compiled by kimicc
directly.

The default record root is:

```text
$TMPDIR/kimicc_csmith_records
```

Each record directory contains the original generated source, the preprocessed
inputs from both preprocessors, `compat.h`, `manifest.txt`, and relevant stdout
files such as `clang.out` and `kimicc.out`.

## Environment Variables

- `KIMICC_CSMITH`: Csmith command. Default: `csmith`.
- `KIMICC_CSMITH_CLANG`: clang command for reference preprocess/compile/run. Default:
  `clang`.
- `KIMICC_CSMITH_TIMEOUT`: timeout command. Default: auto-detect `timeout`,
  then `gtimeout`.
- `KIMICC_CSMITH_KIMICC`: kimicc command. For faster runs, set this to the
  native `cmd/main` binary.
- `KIMICC_CSMITH_INCLUDE_ROOT`: directory containing `csmith.h`.
- `KIMICC_CSMITH_RECORD_ROOT`: directory for full per-case records.
- `KIMICC_CSMITH_BUG_DIR`: directory for saved abnormal kimicc cases. Default:
  `test/bugs`.
- `KIMICC_EXTERNAL_TESTBED`: set to `csmith` or `all` to enable the opt-in e2e
  test.

## Manual Reproduction

To compile a saved bug with kimicc and compare it with clang:

```sh
moon build --target native

case_c=test/bugs/csmith_seed_209_runtime_mismatch.c

_build/native/debug/build/cmd/main/main.exe --preprocessed "$case_c" -o /tmp/kimicc_bug
/tmp/kimicc_bug

record_dir=$TMPDIR/kimicc_csmith_records/csmith_fuzz_0_209
clang -w -o /tmp/clang_bug "$record_dir/clang_preprocessed.i"
/tmp/clang_bug
```

The expected output shape is the Csmith checksum line:

```text
checksum = <hex>
```
