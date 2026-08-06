# bobzhang/kimicc

`kimicc` is a small C compiler written in MoonBit. The primary supported host
is native ARM64 macOS. It can preprocess and parse C source, lower the parsed
program to Darwin ARM64 assembly, emit a Mach-O relocatable object, and run
selected C functions in memory through the native `jit` package. It also has an
experimental Linux/amd64 assembly backend and driver target for smoke testing
System V x86-64 code generation.

## Package Layout

The module exports five public packages:

| Package | Purpose |
|---|---|
| `bobzhang/kimicc/target` | Names supported compiler output targets such as `darwin-arm64` and `linux-amd64`. |
| `bobzhang/kimicc/preprocessor` | Expands C preprocessing directives into ordinary C source. |
| `bobzhang/kimicc/parser` | Tokenizes and parses preprocessed C source into the public AST. |
| `bobzhang/kimicc/codegen` | Converts the parser AST into target assembly, Darwin ARM64 Mach-O object bytes, or a JIT image. |
| `bobzhang/kimicc/jit` | Native-only convenience API that compiles C source and calls `int` returning functions in memory. |

The root package `bobzhang/kimicc` intentionally exports no values.

## Target And Toolchain

Use the native target for builds and tests:

```bash
moon build --target native
moon test --target native
```

The command-line compiler behaves like a small compiler driver. By default it
compiles C source inputs with kimicc and delegates final linking to `clang`:

```bash
moon run cmd/main --target native -- input.c -o out
moon run cmd/main --target native -- main.c helper.c support.o -o out
./out
```

Use `-S` to write assembly, `-c` to write a relocatable object, `-E` to print
preprocessed source, and `--preprocessed` or `-fpreprocessed` when the input
has already been preprocessed. `.i` inputs are treated as preprocessed per
input path. `@response-file` arguments are expanded before option parsing:

```bash
moon run cmd/main --target native -- -E -D FEATURE=1 -I include input.c
moon run cmd/main --target native -- -E '-DADD(x,y)=((x)+(y))' input.c
moon run cmd/main --target native -- -S input.c
moon run cmd/main --target native -- -c input.c
moon run cmd/main --target native -- -fsyntax-only input.c
moon run cmd/main --target native -- -MM -MP input.c
moon run cmd/main --target native -- -c -MMD -MP -MF input.d input.c
moon run cmd/main --target native -- -S --preprocessed input.i -o out.s
moon run cmd/main --target native -- @args.rsp
moon run cmd/main --target native -- -dumpmachine
moon run cmd/main --target native -- -print-target-triple
moon run cmd/main --target native -- -print-resource-dir
moon run cmd/main --target native -- -target linux-amd64 -print-multiarch
moon run cmd/main --target native -- -target linux-amd64 -print-multi-os-directory
moon run cmd/main --target native -- -target linux-amd64 -print-multi-lib
moon run cmd/main --target native -- -print-libgcc-file-name
```

The short `-v` verbose flag is accepted without replacing compilation. Use
`--version` for the version banner and `-dumpversion` for the bare package
version; both are kept in sync with `moon.mod`.

Object, library, shared-library, and assembly inputs are delegated to the
platform toolchain for link-only flows. Compile-only assembly inputs are
delegated to `clang -c`, including multiple assembly inputs when kimicc can
choose per-input outputs. Use `-x c` for extensionless C inputs and `-x none`
before returning to extension-based input classification.
Common linker options such as `-L`, `-l`, `-Wl,`, `-Xlinker`, `-rpath PATH`,
and `-e SYMBOL` are preserved for the delegated link step. Darwin loader path
tokens such as `@rpath/...` remain literal linker arguments rather than
response-file references. Toolchain discovery options such as
`--gcc-toolchain=PATH`, `--gcc-install-dir=PATH`, and `-B PREFIX` are forwarded
to Clang; separated GCC-toolchain spellings are normalized to the joined form
Clang accepts.
Compile-style modes such as `-S`, `-c`, `-E`, `-M`/`-MM`, and
`-fsyntax-only` accept multiple C sources when kimicc can choose per-input
outputs; single-output forms such as `-c -o one.o a.c b.c` are rejected.

Dependency flags `-M`, `-MM`, `-MD`, `-MMD`, `-MP`, `-MF`, `-MT`, and `-MQ`
are accepted. `-M`/`-MD` include system headers in generated Makefile rules,
while `-MM`/`-MMD` keep only the main source and user headers resolved by
kimicc's preprocessor. Repeated `-MT`/`-MQ` options add multiple rule targets;
`-MF -` writes the dependency rule to stdout, and Clang's
`-dependency-file PATH` is accepted as a depfile destination alias. In
dependency-only `-M`/`-MM` mode, `-o PATH` is accepted as a dependency output
path when `-MF` is absent.
For multiple compile-style inputs, dependency sidecars are per-input when
`-MF` is omitted; a single `-MF` path with multiple outputs is rejected.
In multi-source link mode, `-MD`/`-MMD` emit one dependency sidecar for the
linked output target using the union of dependencies from the compiled C inputs.
The driver also recognizes dependency, include, forced-include, and simple
macro options tunneled through `-Wp,` lists, such as `-Wp,-MMD,dep.d,-MP`,
and common `-Xpreprocessor` spellings such as `-Xpreprocessor -DVALUE=1` or
`-Xpreprocessor -D -Xpreprocessor VALUE=1`.
Diagnostic metadata and driver path options such as `-MJ PATH`,
`-serialize-diagnostics PATH`, `--config PATH`, `-dumpdir PATH`, and
`-dumpbase PATH` are accepted and ignored.

The default output target is `darwin-arm64`. Use `-target linux-amd64`, or the
Docker-style alias `-target linux/amd64`, to select the experimental
Linux/amd64 backend:

```bash
moon run cmd/main --target native -- -S -target linux-amd64 input.c -o out.s
moon run cmd/main --target native -- -c -target linux-amd64 input.c -o out.o
```

On ARM64 macOS, `-c -target linux-amd64` delegates assembly to Clang with
`-target x86_64-linux-gnu` and produces an ELF64 relocatable object when the
local Clang has that backend. Full Linux executable linking is best tested in an
amd64 Linux environment:

```bash
docker run --rm --platform linux/amd64 \
  -v "$PWD:/work" -w /work ubuntu:24.04 \
  bash scripts/linux-amd64-smoke.sh
```

For repeated local runs, build the cached smoke image once:

```bash
scripts/build-linux-amd64-smoke-image.sh
scripts/linux-amd64-smoke.sh
```

`scripts/linux-amd64-smoke.sh` automatically uses
`kimicc-linux-amd64-smoke:ubuntu24.04` when that image exists locally; set
`KIMICC_LINUX_AMD64_SMOKE_IMAGE` to use another image tag. Set
`KIMICC_LINUX_AMD64_SMOKE_REBUILD_IMAGE=1` when running the smoke script to
rebuild the cached image first, and combine it with
`KIMICC_LINUX_AMD64_SMOKE_NO_CACHE=1` to refresh the MoonBit toolchain layer.
On a Linux/amd64 host, set
`KIMICC_LINUX_AMD64_SMOKE_FORCE_DOCKER=1` to force the Docker path.

See [`docs/linux-amd64-target.md`](docs/linux-amd64-target.md) for current
coverage, gaps, and the Docker test workflow.

The CI parser tests use pinned external TinyCC and QuickJS snapshots. Regenerate
the matching preprocessed files locally with:

```bash
scripts/fetch-external-parser-fixtures.sh
moon test test/e2e/e2e_test.mbt --target native \
  --filter 'parse tinycc stripped'
moon test test/e2e/e2e_test.mbt --target native \
  --filter 'parse quickjs preprocessed'
```

Include search is explicit: quote includes search the including file directory
and `-I` paths, while angle includes search `-isystem` paths and then `-I`
paths. The driver also adds common macOS Command Line Tools include directories
by default so system headers such as `<stddef.h>` are available on the target
platform. `__has_include(...)` and `__has_include_next(...)` use the same search
rules. Headers may use `#pragma once` to suppress repeated inclusion. Use
`-nostdinc` to disable those built-in system include paths. Clang-style feature
probes are conservative: covered C feature probes, GNU `packed`/numeric
`aligned` attributes, C11/GNU alignment query operators, and parser-accepted
no-op GNU diagnostic, optimization, allocation, and sanitizer attributes report
true; unsupported feature/attribute/warning probes report false, and
`__is_identifier(name)` tracks parser-recognized keywords and extension tokens.
Variadic macros support
`__VA_ARGS__`, GNU comma-paste
elision, and `__VA_OPT__(...)`; `__COUNTER__`, `#elifdef`, and `#elifndef` are
supported for generated/config headers. `#line` updates the logical source
coordinates used by `__FILE__` and `__LINE__`; GCC-style linemarkers such as
`# 42 "file.c"` are accepted as line control too.

## Preprocessor API

Import the preprocessor package from `moon.pkg`:

```
import {
  "bobzhang/kimicc/preprocessor"
}
```

The main entry point is:

```moonbit nocheck
@preprocessor.preprocess(
  source : String,
  options : @preprocessor.PreprocessOptions,
) -> Result[String, @preprocessor.PreprocessError]
```

`preprocess` expands macros, conditionals, and configured includes, returning
source text suitable for `@parser.parse`. The convenience
`@preprocessor.parse(source, options)` preprocesses and then parses, but callers
that need a strict phase boundary should call the two packages separately.
Use `@preprocessor.preprocess_with_dependencies(source, options)` when a caller
also needs the main file and resolved include paths read during preprocessing.

## Parser API

Import the parser package from `moon.pkg`:

```
import {
  "bobzhang/kimicc/parser"
}
```

The main entry point is:

```moonbit nocheck
@parser.parse(source : String) -> @parser.Program
```

`parse` consumes a complete, already preprocessed C translation unit and returns
a `Program`. It does not return a recoverable error value. Invalid or
unsupported C syntax aborts. Callers that need fault isolation should run
parsing in a separate process.

The parser exposes its AST so tests, tooling, and alternate backends can inspect
or transform it:

| Type | Meaning |
|---|---|
| `Program` | Top-level translation unit: struct or union declarations, global variables, and function declarations. |
| `FuncDecl` | Function declaration or definition. `body` is `None` for declarations without a body. |
| `GlobalDecl` | Global variable declaration or definition. `init` is `None` for declarations without an initializer. |
| `StructDecl` | Struct or union declaration. `is_union` distinguishes unions; `is_packed` records GNU packed layout attributes. |
| `Param` | Function parameter or aggregate field. `bit_width` is set for bit-fields. |
| `Type` | C type model used by the parser and code generator. `Aligned` records `_Alignas` and numeric GNU aligned attributes. |
| `Expr` | Expression tree. Operators are stored as source-level operator strings. |
| `Stmt` | Statement tree. |
| `GlobalInit` | Global initializer form. |
| `Token`, `Lexer`, `Parser` | Lower-level lexer/parser building blocks. Prefer `parse` unless you need token-level behavior. |

Example:

```moonbit nocheck
///|
let source = "int answer(void) { return 42; }"

///|
let program = @parser.parse(source)
```

### Type Helpers

`Type` has ABI-oriented helper methods:

```moonbit nocheck
ty.size() -> Int
ty.align() -> Int
ty.is_integer() -> Bool
ty.is_signed() -> Bool
ty.is_floating() -> Bool
ty.to_unsigned() -> @parser.Type
```

`size` and `align` are for the current ARM64 macOS ABI assumptions. They work
for scalar, pointer, function pointer, array, atomic, and aligned types. They
abort for `Struct(name)` and `Union(name)` because a bare `Type` does not carry
the declaration layout needed to compute aggregate size and alignment.

`fold_const(expr)` attempts to evaluate an integer constant expression:

```moonbit nocheck
@parser.fold_const(@parser.Expr::Number(42L))
```

It returns `Some(value)` only when the expression can be folded by the parser's
integer constant folder. It returns `None` for non-constant expressions,
floating-point expressions, aggregate literals, and operations it does not
understand.

## Codegen API

Import the parser and codegen packages:

```
import {
  "bobzhang/kimicc/parser",
  "bobzhang/kimicc/codegen",
  "bobzhang/kimicc/target",
}
```

The assembly API is:

```moonbit nocheck
///|
let program = @parser.parse(source)

///|
let assembly = @codegen.Codegen::new().generate(program)
```

`Codegen::generate` returns Darwin ARM64 assembly as a `String`. The assembly is
intended to be accepted by the macOS toolchain and can be linked with `clang`.
The source program must already be parsed; codegen does not preprocess or parse
text.

For target dispatch, use:

```moonbit nocheck
///|
let target = @target.Target::parse("linux-amd64").unwrap()

///|
let docker_style_target = @target.Target::parse("linux/amd64").unwrap()

///|
let assembly = @codegen.generate_assembly_for_target(program, target)
```

`generate_assembly_for_target` preserves the existing Darwin ARM64 output for
`darwin-arm64` and emits GNU assembler syntax for `linux-amd64`.

For the current fixed scratch-register discipline, call lowering, aggregate
rules, and ABI compliance status, see
[`docs/codegen-registers-and-abi.md`](docs/codegen-registers-and-abi.md).

For object emission:

```moonbit nocheck
///|
let object_bytes = @codegen.generate_macho_object(program)
```

`generate_macho_object` returns the bytes of a Mach-O relocatable object file
for ARM64 macOS. These bytes are suitable for writing to a `.o` file and linking
with the platform linker.

For JIT support:

```moonbit nocheck
///|
let image = @codegen.generate_jit_image(program)
```

`generate_jit_image` returns a `JitImage`, not a Mach-O file. It is a compact
loader-facing image used by `bobzhang/kimicc/jit`.

`JitImage` fields:

| Field | Meaning |
|---|---|
| `code` | Full in-memory image bytes. The executable region comes first, followed by writable data. |
| `executable_size` | Number of leading bytes that should be made executable. Bytes after this offset remain writable data. |
| `base_relocations` | Little-endian `u32` offsets of 64-bit slots that must be adjusted by the image base address. |
| `external_relocations` | Encoded external-symbol relocations resolved by the native JIT loader with `dlsym`. |
| `symbols` | Exported symbols and offsets into `code`. |

`JitSymbol` contains a `name` and an `offset`. Symbol names use Darwin spelling,
so C functions normally appear with a leading underscore, for example
`_answer`.

## JIT API

The JIT package is native-only and uses a small C FFI stub. Add it to
`moon.pkg` only for native builds:

```
import {
  "bobzhang/kimicc/jit"
}
```

Compile once and call by symbol:

```moonbit nocheck
let source = "int add(int x, int y) { return x + y; }"
match @jit.compile(source) {
  Some(module_) =>
    match module_.call_i32_2("add", 20, 22) {
      Some(value) => println(value.to_string())
      None => println("missing symbol or unsupported call")
    }
  None => println("compile or load failed")
}
```

`compile` expects already-preprocessed source. Use `compile_c(source, options)`
when the input may contain preprocessor directives.

Or use one-shot helpers that compile and call immediately:

```moonbit nocheck
@jit.call_i32_0(source, "answer")
@jit.call_i32_1(source, "negate", 42)
@jit.call_i32_2(source, "add", 20, 22)
@jit.call_i32_3(source, "mix", 5, 8, 2)
```

All `call_i32_N` APIs assume the target C function returns a 32-bit `int` and
takes exactly `N` 32-bit `int` arguments. Calling a symbol with the wrong
signature is undefined behavior at the native ABI level. The wrapper cannot
validate the C type signature.

`compile(source)` returns `None` when native memory mapping, relocation, or
external symbol resolution fails. External function and data relocations are
resolved with `dlsym(RTLD_DEFAULT, name)`. If a Darwin-style symbol begins with
`_`, the loader also retries without the leading underscore.

`Module::symbol_offset(name)` accepts either a C spelling (`"answer"`) or a
Darwin spelling (`"_answer"`). It returns the offset of the compiled symbol in
the image if present.

The one-shot helpers return `None` if compilation fails or the requested symbol
does not exist. They are convenient for tests. For repeated calls, prefer
`compile` once and call methods on the returned `Module` so the source is not
recompiled on every invocation.

## Current Limitations

- The project targets native ARM64 macOS.
- The parser expects preprocessed C source. Use the preprocessor package or CLI
  default mode for source containing directives.
- Parser and codegen failures generally abort instead of returning structured
  diagnostics.
- Codegen is ABI-aware for the supported native ARM64 macOS subset, but it does
  not yet implement a general register allocator or claim complete C ABI
  conformance.
- The Linux/amd64 backend is experimental and currently covers scalar calls,
  scalar varargs, floating-point arithmetic and lvalue mutations, small
  integer/SSE/mixed aggregate calls and returns,
  recursive nested/array aggregate classification in that small subset,
  memory-class aggregate calls and returns, covered aggregate initializers
  including mixed nested designators, ELF assembly emission, and
  Clang-delegated object emission. The shared parser also folds covered C11
  `_Generic` selections, GNU `typeof` specifiers, GNU `__auto_type` locals,
  and C11/GNU alignment query operators, `__builtin_offsetof` member
  designators, GNU compile-time selection and type-classification builtins
  before target code generation, and accepts covered no-op GNU attributes.
- The JIT public call surface currently covers only `int` returns with 0 to 3
  `int` arguments.
- The public AST is useful for tooling, but it is still compiler-internal in
  shape. Prefer high-level entry points unless you are building compiler tests
  or a backend.
