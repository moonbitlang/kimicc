# bobzhang/kimicc

`kimicc` is a small C compiler written in MoonBit. The project currently
targets native ARM64 macOS. It can parse C source, lower the parsed program to
Darwin ARM64 assembly, emit a Mach-O relocatable object, and run selected C
functions in memory through the native `jit` package.

The compiler does not include a C preprocessor. For real C programs, run the
source through an external preprocessor such as `clang -E` before passing it to
the parser, code generator, or JIT package.

## Package Layout

The module exports three public packages:

| Package | Purpose |
|---|---|
| `bobzhang/kimicc/parser` | Tokenizes and parses preprocessed C source into the public AST. |
| `bobzhang/kimicc/codegen` | Converts the parser AST into Darwin ARM64 assembly, Mach-O object bytes, or a JIT image. |
| `bobzhang/kimicc/jit` | Native-only convenience API that compiles C source and calls `int` returning functions in memory. |

The root package `bobzhang/kimicc` intentionally exports no values.

## Target And Toolchain

Use the native target for builds and tests:

```bash
moon build --target native
moon test --target native
```

The command-line compiler accepts one C source string as its first argument and
prints assembly:

```bash
moon run cmd/main --target native -- "$(cat input.c)" > out.s
clang -o out out.s
./out
```

For preprocessed source:

```bash
clang -E -P input.c > input.i
moon run cmd/main --target native -- "$(cat input.i)" > out.s
```

## Parser API

Import the parser package from `moon.pkg`:

```moonbit nocheck
import {
  "bobzhang/kimicc/parser"
}
```

The main entry point is:

```moonbit nocheck
@parser.parse(source : String) -> @parser.Program
```

`parse` consumes a complete C translation unit and returns a `Program`. It does
not return a recoverable error value. Invalid or unsupported C syntax aborts.
Callers that need fault isolation should run parsing in a separate process.

The parser exposes its AST so tests, tooling, and alternate backends can inspect
or transform it:

| Type | Meaning |
|---|---|
| `Program` | Top-level translation unit: struct or union declarations, global variables, and function declarations. |
| `FuncDecl` | Function declaration or definition. `body` is `None` for declarations without a body. |
| `GlobalDecl` | Global variable declaration or definition. `init` is `None` for declarations without an initializer. |
| `StructDecl` | Struct or union declaration. `is_union` distinguishes unions. |
| `Param` | Function parameter or aggregate field. `bit_width` is set for bit-fields. |
| `Type` | C type model used by the parser and code generator. |
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

```moonbit nocheck
import {
  "bobzhang/kimicc/parser",
  "bobzhang/kimicc/codegen",
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

```moonbit nocheck
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
- The parser expects preprocessed C source.
- Parser and codegen failures generally abort instead of returning structured
  diagnostics.
- The JIT public call surface currently covers only `int` returns with 0 to 3
  `int` arguments.
- The public AST is useful for tooling, but it is still compiler-internal in
  shape. Prefer high-level entry points unless you are building compiler tests
  or a backend.
