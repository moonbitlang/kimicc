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
  casts, arithmetic, conditionals, loops, scalar switches, simple gotos, and
  selected scalar builtin calls. It also models narrow string-literal facts that
  are useful in compile tests: literal pointer non-nullness, literal byte access,
  `sizeof`/`__alignof__` on string literals, literal `__builtin_strlen`, and
  literal-only `__builtin_strcmp`/`__builtin_memcmp`.
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

Darwin ARM64 still owns its existing layout/type helpers inside `Codegen`. That
keeps the public `Codegen` struct stable while MIR is still young.

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
