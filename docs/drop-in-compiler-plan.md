# kimicc Drop-In Compiler Plan

This plan tracks the path from the current ARM64 macOS C compiler prototype to
a practical `cc`/`clang` replacement for supported programs. The near-term goal
is not to claim full C conformance; it is to make unsupported behavior explicit,
keep the compiler usable from ordinary build systems, and grow compliance with
repeatable gates.

## Baseline

- Target platform: native ARM64 macOS.
- Front end: `bobzhang/kimicc/preprocessor` expands C preprocessing directives;
  `bobzhang/kimicc/parser` consumes already preprocessed C translation units.
- Back end: Darwin ARM64 assembly, Mach-O relocatable objects, and native JIT
  images.
- Current external smoke gates include SQLite, QuickJS, TinyCC, and OCaml source
  units passing through kimicc's own preprocessor before parsing and codegen.

## Phase 1: Driver Compatibility

Make the command-line compiler usable as a build-system participant for the
compile-only modes that C projects normally use.

- Accept common compiler spellings: `-E`, `-S`, `-c`, `-o`, `-I`, `-isystem`,
  `-D`, `-U`, `-include`, `@response-file`, `--preprocessed`, and
  `-fpreprocessed`/`.i` preprocessed inputs, and `-nostdinc`.
- Tolerate common build flags that do not yet affect code generation:
  `-std=*`, `-O*`, `-g*`, `-W*`, `-f*`, `-m*`, dependency-output options, and
  target/architecture options. Preserve relevant driver-facing flags such as
  `-pthread` for preprocessing and link delegation.
- Write Makefile dependency output for `-M`/`-MM` and compile-style
  `-MD`/`-MMD` flows, honoring `-MF`, `-MT`, `-MQ`, and `-MP` with
  dependencies collected from headers that kimicc's preprocessor actually
  opens.
- Choose standard output names when `-o` is omitted: `<input>.s` for `-S`,
  `<input>.o` for `-c`, and `a.out` for link mode.
- Add macOS system include defaults for the local Command Line Tools SDK while
  preserving `-nostdinc` for reproducible preprocessing, and honor explicit
  Clang resource-directory overrides for builtin headers.
- Keep preprocessing, parsing, assembly emission, object emission, and link
  delegation separable inside the driver.

## Phase 2: Build-System Gates

Promote external project checks from ad hoc smoke tests to repeatable release
gates.

- SQLite: preprocess, parse, compile, link smoke binaries, and expand the public
  API smoke tests.
- QuickJS: cover the normal source units and document generated-file
  prerequisites such as `repl.c`.
- TinyCC: compile the configured one-source build and then broaden to more
  configured objects.
- OCaml: keep the `yacc/` C units green, then add more runtime and support
  translation units as parser/codegen coverage improves.
- Record exact upstream revisions, configure commands, and expected residual
  failures for every gate.

Current CI fixture pins:

- TinyCC parser fixture: `fad812360ba836b4ca6f52236d867476ff671633`, fetched
  from `https://repo.or.cz/tinycc.git`.
- QuickJS parser fixture: `d7ae12ae71dfd6ab2997527d295014a8996fa0f9`, fetched
  from `https://github.com/bellard/quickjs.git`.

Use `scripts/fetch-external-parser-fixtures.sh` to reproduce the CI parser
fixtures locally. It writes `/tmp/tinycc_stripped.c` and
`/tmp/quickjs_preprocessed.c` by default and accepts `TINYCC_REF` and
`QUICKJS_REF` overrides when intentionally refreshing the pins.

Native CI uses `scripts/native-ci-test.sh` for the MoonBit test pass. The
script runs ordinary package tests together, then runs each `test/e2e/*_test.mbt`
file as its own native test target. This keeps the external e2e coverage in CI
without building the entire e2e package as one large native blackbox bundle.

## Phase 3: Link Driver

Make default `kimicc input.c -o program` useful while still keeping native
kimicc code generation auditable.

- For C source inputs in link mode, generate temporary assembly or objects and
  delegate final linking to the platform toolchain.
- Preserve linker-facing arguments such as object files, libraries, frameworks,
  `-Wl,*`, and assembler-facing `-Wa,*`/`-Xassembler` options.
- Support link-only invocations by delegating directly to `clang` when no C
  translation unit is present, and delegate compile-only assembly inputs to
  `clang -c`.
- Emit nonzero process statuses for driver, preprocessing, parsing, codegen,
  assembler, and linker failures.

## Phase 4: Language And ABI Coverage

Drive missing C features from real project failures and conformance tests.

- Close parser gaps for common GNU/Clang extensions used by system headers and
  portable C projects.
- Expand C11 coverage around declarations, integer conversions, initializers,
  atomics syntax, `_Generic`, `_Static_assert`, and preprocessor corner cases.
- Strengthen Darwin ARM64 ABI behavior for aggregates, varargs, bit-fields,
  floating point, and symbol/linkage rules.
- Add differential tests against Clang where the C standard leaves behavior
  implementation-defined for this target.

## Phase 5: Compliance Matrix

Move from smoke confidence to a public support matrix.

- Maintain a C11 feature checklist tied to N1570 sections.
- Track GNU/Clang extension compatibility separately from ISO C.
- Publish release notes with external-project gates, conformance deltas, and
  known unsupported features.
- Treat every fixed external-project regression as a small permanent test.
