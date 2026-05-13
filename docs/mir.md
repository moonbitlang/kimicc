# MIR Architecture

`kimicc` currently uses MIR as a target-sensitive semantic layer, not as a full
instruction-level machine IR. The parser AST remains the main representation
that both assembly backends walk.

## Current Shape

- `mir/` lowers a parsed C translation unit into reusable semantic facts:
  function signatures, selected global declarations, aggregate declarations,
  target-specific sizes/alignments, field layouts, expression types, and integer
  constant folds.
- `Program::interpret_i64` is an integer-only interpreter intended for
  compile-test oracles. It supports scalar functions, locals, globals, calls,
  casts, arithmetic, conditionals, loops, scalar switches, simple gotos, selected
  scalar builtin calls including direct-lvalue integer overflow helpers for
  non-128-bit result types, scalar compound literals, and scalar `*&` / `&*`
  cancellation that does
  not require modeling general memory. It also models narrow string-literal facts
  that are useful in compile tests: literal pointer non-nullness, literal byte
  access through transparent casts, `sizeof`/`__alignof__` on string literals,
  literal `__builtin_strlen` through transparent casts, and literal-only string
  comparison/search builtins such as `__builtin_strcmp`,
  `__builtin_strncmp`, `__builtin_memcmp`, `__builtin_strchr`,
  `__builtin_strrchr`, `__builtin_strstr`, and `__builtin_memchr`.
  MIR and the parser also carry builtin return-type facts used by unevaluated
  expressions such as `sizeof`, including selected string/memory aliases and
  floating-point builtins, floating classification helpers, selected atomic
  helpers, scalar bit/count/rotation/alignment helpers, overflow helpers, void
  control/varargs helpers, and pointer-valued helpers such as
  `__builtin_alloca`. Runtime `__builtin_alloca` calls are modeled for argument
  side effects and pointer nullness only; the allocated memory is not modeled.
  Runtime `__builtin_va_start`, `__builtin_va_copy`, and `__builtin_va_end` are
  no-ops for scalar tests that do not inspect `va_list` contents.
  `memcpy`/`memmove`/`memset` and their checked aliases model only the returned
  destination pointer; memory contents are not modeled.
  `strcpy`/`strcat`/`strncpy`/`strncat` and checked destination-return aliases
  are modeled the same way.
  Runtime `__builtin___strlcpy_chk` evaluates its arguments and models only the
  return value when the source is a string literal. Runtime
  `__builtin___strlcat_chk` is modeled only for zero destination size and a
  string-literal source, where the destination contents are not inspected.
  Runtime `__builtin___snprintf_chk` is modeled only for zero output size and a
  literal format string with no conversions.
  Runtime `__builtin_bzero` evaluates its arguments but does not model memory
  contents.
  Frame/return-address builtins are modeled only for nullness: depth 0 returns a
  synthetic non-null pointer, and nonzero depths return null. Tests should
  compare those values only against null or pass them through identity helpers,
  not inspect the synthetic address itself. The interpreter deliberately returns
  `Err` for general memory, aggregates, indirect calls, floating point, computed
  goto, varargs, and other behavior that is not modeled yet.
- `test/e2e/mir_oracle_test.mbt` compares selected scalar compiled binaries
  against the MIR interpreter.
- `codegen/semantic_facts_wbtest.mbt` checks that Darwin ARM64 and linux/amd64
  backend-local facts agree with MIR for representative scalar, aggregate,
  packed, union, bit-field, offsetof, global-expression type, and integer
  constant-folding cases.

## Backend Sharing

Darwin ARM64 attaches a lowered MIR program during assembly generation and
delegates size, alignment, field-layout, offsetof path, global-expression type,
and covered integer constant-folding queries to MIR when that lowered program is
present. Its older local semantic paths remain in place as fallbacks for direct
private construction in tests.

Linux/amd64 now receives a lowered MIR program through `generate_assembly_for_target`.
The private `X64Codegen` delegates size, alignment, field-layout, offsetof path,
global-expression type, and covered integer constant-folding queries to MIR when
that lowered program is present. Its older local semantic paths remain in place
for whitebox consistency tests and as fallbacks for direct private construction
in tests.

## Why This Layer Is Useful

The two backends had started duplicating C semantic facts: scalar ABI layout,
aggregate layout, expression typing, and constant folding. Those facts are not
really target instruction selection. Keeping them in MIR makes backend behavior
easier to compare and gives compile tests a non-assembler oracle for scalar
program behavior.

## Remaining Migration Path

1. Expand MIR facts only when a backend or test needs them.
2. Grow the MIR interpreter as a compile-test oracle before relying on it for
   broader conformance claims.
3. Move more backend semantic queries to MIR behind tests that compare old and
   new behavior.
4. Only after semantic sharing is stable, consider a real machine-level IR with
   explicit virtual registers, blocks, target lowering, and allocation.
