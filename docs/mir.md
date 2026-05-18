# MIR Architecture

`kimicc` currently has two assembly routes. The direct educational route is
`parser.Program -> codegen`, where the backend walks the C AST in one pass. The
modular route is `parser.Program -> MirModule -> mir_codegen`, where the backend
entry point receives only MIR declarations, layouts, globals, and lowered
bodies. MIR is still a target-sensitive semantic layer plus an emerging
function-body layer, not a full instruction-level machine IR.

## Current Shape

- `mir/` lowers a parsed C translation unit into reusable semantic facts:
  function signatures, selected global declarations, aggregate declarations,
  target-specific sizes/alignments, field layouts, expression types, and integer
  and floating constant folds.
- `Program::to_module` projects those facts into `MirModule`, a parser-AST-free
  backend-facing container for MIR declarations, layouts, globals, and lowered
  bodies. `Program` still carries parser source for transitional fallback
  consumers. `lower_to_module` is the direct parser-to-`MirModule` helper for
  callers that do not need the transitional `Program` wrapper.
- `Program.decls` stores MIR-owned function declaration metadata, including
  parameter facts, linkage-related attributes, aliases, lifecycle attributes,
  and whether a source body existed. Function body syntax is not stored there;
  supported bodies live in `Program.bodies`.
- `Program.global_decls` stores source-order MIR-owned global declaration
  metadata, including type, linkage-related attributes, visibility/section
  attributes, and whether an initializer existed. Initializer payload lowering
  has started for simple and constant-folded integer, string, and brace-list
  forms; unsupported initializer expressions are marked explicitly while data
  lowering migrates. The merged `Program.globals` lookup map also stores
  `MirGlobalDecl` records, so MIR type queries do not retain parser global
  declaration nodes.
- `Program.aggregate_decls` stores MIR-owned struct/union declaration metadata.
  Target-specific placement remains in `Program.layouts`, so source declaration
  facts and computed ABI/layout facts stay separated. MIR layout computation now
  uses this aggregate metadata instead of retaining parser `StructDecl` nodes.
- `Program.bodies` stores MIR-owned function bodies for the supported scalar
  subset. Body lowering assigns stable `MirLocal` IDs, records typed value and
  statement nodes, and deliberately omits functions that still need unsupported
  parser constructs. This gives later codegen a concrete layer to target without
  depending on parser statement/expression nodes.
- `Program::interpret_body_i64` executes those lowered MIR bodies directly. It
  currently covers integer locals, assignments, direct calls, returns, casts,
  unary/binary scalar operators, conditionals, `while`, `for`, `do while`,
  directly labeled scalar `switch`, simple labels/goto, local compound
  assignment, local postfix updates, scalar globals and initialized global arrays, scalar memory
  prefix/postfix updates, scalar and aggregate compound literals including
  address-taking through transparent casts,
  scalar `*&` / `&*` cancellation, transparent casted scalar address
  loads/stores, address-of aggregate member cancellation including transparent
  casts, simple scalar local/global pointer loads/stores,
  simple non-variadic indirect calls and function addresses, scalar local arrays
  including array-to-pointer decay in call arguments, string literal byte loads,
  simple local array initializers, local aggregate initializers with nested
  zero-fill, scalar-leaf struct copy initializers,
  ignored assignments from local objects and compound literals including
  scalar-field unions and nested scalar aggregate fields, fixed-size string
  array initialization, initializer side effects for unused unsupported local
  declarations, scalar aggregate fields including nested member access and
  scalar array field access, foldable
  `__builtin_constant_p`, literal `__builtin_strlen`, identity builtins such as
  `__builtin_expect` and `__builtin_assume_aligned` including their modeled
  hint-operand side effects,
  no-argument `__sync_synchronize`, atomic thread/signal fence builtins,
  frame/return-address nullness, memory builtin first-argument returns including
  selected checked variants, string destination builtin first-argument returns,
  checked `strlcpy`/`strlcat` literal lengths, runtime `__builtin_alloca`
  synthetic pointer values, and return-address transforms, no-op
  `__builtin_assume`, runtime `__builtin_prefetch` address evaluation, identity
  `__builtin_unpredictable`, `break`/`continue`, and ternaries. Missing bodies
  return `Err` instead of falling back to parser AST execution.
- `mir_codegen/mir_body_codegen.mbt` is the first production backend consumer of
  `MirFuncBody`. It emits Darwin ARM64 and linux/amd64 assembly for
  integer-scalar MIR bodies with local variables, assignments, branches,
  `while`/`for`/`do while` loops, `break`/`continue`, ternaries, casts, direct
  calls to other MIR-bodied functions, declared non-variadic integer-scalar
  externs, or zero-argument implicit integer-scalar externs, directly labeled
  scalar `switch`, simple labels/goto, local compound
  assignment, local postfix updates, scalar globals and initialized global arrays, scalar memory
  prefix/postfix updates, scalar and aggregate compound literals including
  address-taking through transparent casts,
  scalar `*&` / `&*` cancellation, transparent casted scalar address
  loads/stores, address-of aggregate member cancellation including transparent
  casts, simple scalar local/global pointer loads/stores,
  simple non-variadic indirect calls and function addresses, scalar local arrays
  including array-to-pointer decay in call arguments, string literal byte loads,
  simple local array initializers, local aggregate initializers with nested
  zero-fill, scalar-leaf struct copy initializers,
  ignored assignments from local objects and compound literals including
  scalar-field unions and nested scalar aggregate fields, fixed-size string
  array initialization, direct local string-array element mutation, scalar
  aggregate fields including nested member access and scalar array field access,
  foldable
  `__builtin_constant_p`, literal `__builtin_strlen`, identity builtins such as
  `__builtin_expect` and `__builtin_assume_aligned` including their modeled
  hint-operand side effects,
  no-argument `__sync_synchronize`, atomic thread/signal fence builtins,
  trap/unreachable builtins, frame/return-address builtins, integer overflow
  builtins for non-128-bit result pointers, trivial variadic bodies with
  unobserved `__builtin_va_start`/`__builtin_va_copy`/`__builtin_va_end`,
  `__builtin_bzero` and selected memory/string builtin libcalls including
  string query calls, checked variants, checked `strlcpy`/`strlcat`, and
  checked `snprintf`/`sprintf`/`printf`, and runtime `__builtin_alloca` stack
  allocation,
  return-address transforms, no-op `__builtin_assume`, runtime
  `__builtin_prefetch` address evaluation, identity `__builtin_unpredictable`,
  and arithmetic/logical operators. Unsupported MIR bodies still fall back to
  the existing parser-AST codegen path.
- `Program::interpret_i64` is an integer-only interpreter intended for
  compile-test oracles. It supports scalar functions, locals, globals, calls,
  casts, arithmetic, conditionals, loops, scalar switches, simple gotos, selected
  scalar builtin calls including direct-lvalue integer overflow helpers for
  non-128-bit result types, scalar compound literals, and scalar `*&` / `&*`
  cancellation that does
  not require modeling general memory. It also models narrow string-literal facts
  that are useful in compile tests: literal pointer non-nullness, literal byte
  access through transparent casts, constant/runtime pointer offsets, and
  pointer locals/globals initialized from string literals, global/local
  character arrays initialized from byte/string literals, element addresses
  inside those modeled byte objects, `sizeof`/`__alignof__` on string literals,
  literal `__builtin_strlen` through transparent casts, and literal-only string
  comparison/search builtins such as `__builtin_strcmp`,
  `__builtin_strncmp`, `__builtin_memcmp`, `__builtin_strchr`,
  `__builtin_strrchr`, `__builtin_strstr`, and `__builtin_memchr`. The pointer
  returning literal search builtins model returned offsets inside the synthetic
  literal pointer, but not general memory. Modeled C string lengths stop at the
  first embedded NUL byte, while `sizeof` still uses the full literal object.
  MIR and the parser also carry builtin return-type facts used by unevaluated
  expressions such as `sizeof`, including selected string/memory aliases and
  floating-point builtins, floating classification helpers, selected atomic
  helpers, scalar bit/count/rotation/alignment helpers, overflow helpers, void
  control/varargs helpers, and pointer-valued helpers such as
  `__builtin_alloca`. Runtime `__builtin_alloca` calls are modeled for argument
  side effects and distinct synthetic non-null pointer values; the allocated
  memory is not modeled.
  Floating comparison and classification builtins such as
  `__builtin_isgreater`, `__builtin_isunordered`, `__builtin_isnan`, and
  `__builtin_signbit` are modeled for operands covered by MIR floating
  constant folding, returning only their integer predicate result. Floating
  math builtins covered by MIR floating constant folding, including
  `__builtin_fabs`, `__builtin_copysign`, and `__builtin_sqrt`, can also feed
  integer casts and those folded predicates.
  Runtime `__builtin_va_start`, `__builtin_va_copy`, and `__builtin_va_end` are
  no-ops for scalar tests that do not inspect `va_list` contents.
  Runtime `__builtin_expect`, `__builtin_expect_with_probability`, and
  `__builtin_assume_aligned` return the value operand while preserving modeled
  side effects in ignored hint operands.
  Runtime `__builtin_prefetch` evaluates its address argument for side effects
  but does not model cache behavior; `__builtin_assume` remains a no-op and does
  not evaluate its predicate. Runtime `__builtin_constant_p` returns `1` for
  expressions covered by MIR integer constant folding and `0` otherwise, without
  evaluating the operand. The covered compile-time scalar builtin folds include
  absolute value, alignment predicates/helpers, bit counts, byte swaps, parity,
  first/leading/trailing set-bit queries, rotations, and `__builtin_flt_rounds`.
  MIR also folds the covered floating constant subset used by global
  initializers and compile-test predicates: floating literals,
  integer-to-floating and floating-to-integer cast paths, arithmetic, ternaries
  selected by integer constants, modeled NaN/infinity builtins, and foldable
  `__builtin_fabs`, `__builtin_copysign`, and `__builtin_sqrt` calls.
  Runtime `__builtin_object_size` and `__builtin_dynamic_object_size` model
  string-literal object sizes, direct named objects (`&x`), direct named arrays
  (`buf`), and direct aggregate member subobjects such as `&s.buf` or `s.buf`.
  Modes 0/2 report bytes remaining in the complete object, while modes 1/3
  report bytes remaining in the nearest modeled subobject. Constant
  array-element addresses and pointer offsets such as `&buf[3]` and `buf + 3`
  subtract target element bytes from those facts. Other objects use the C
  builtin unknown-size fallbacks (`-1` for modes 0/1, `0` for modes 2/3).
  `memcpy`/`memmove`/`memset` and their checked aliases model only the returned
  destination pointer; memory contents are not modeled.
  `mempcpy` and its checked alias model the returned `dest + n` pointer, with no
  memory-content modeling.
  `strcpy`/`strcat`/`strncpy`/`strncat` and checked destination-return aliases
  are modeled the same way.
  `stpcpy` and `stpncpy`, plus checked aliases, model returned end pointers for
  string-literal sources; destination contents are not modeled.
  Runtime `__builtin___strlcpy_chk` evaluates its arguments and models only the
  return value when the source is a string literal. Runtime
  `__builtin___strlcat_chk` is modeled only for zero destination size and a
  string-literal source, where the destination contents are not inspected.
  Runtime `__builtin___snprintf_chk` is modeled only for return length, with no
  output-content modeling, and a literal format string with `%c`,
  literal-string `%s`, decimal `%d`/`%i`,
  nonnegative `%u`/`%o`/`%x`/`%X`, optional integer length modifiers
  `l`/`ll`/`z`/`t`/`j`, simple numeric field widths with `0`/`-` flags,
  `+`/space sign flags for decimal `%d`/`%i`, `#` alternate form for
  nonnegative `%o`/`%x`/`%X`, simple numeric precision for literal-string
  `%s`, decimal `%d`/`%i`, and nonnegative `%u`/`%o`/`%x`/`%X`, or escaped
  `%%`.
  Runtime `__builtin___sprintf_chk` is modeled only for a literal format string
  with `%c`, literal-string `%s`, decimal `%d`/`%i`, nonnegative
  `%u`/`%o`/`%x`/`%X`, optional integer length modifiers `l`/`ll`/`z`/`t`/`j`,
  simple numeric field widths with `0`/`-` flags, `+`/space sign flags for
  decimal `%d`/`%i`, `#` alternate form for nonnegative `%o`/`%x`/`%X`, or
  simple numeric precision for literal-string `%s`, decimal `%d`/`%i`, and
  nonnegative `%u`/`%o`/`%x`/`%X`, or escaped `%%`; output contents are not
  modeled.
  Runtime `__builtin___printf_chk` is modeled with the same literal-format
  return-value restriction; output is not modeled.
  Runtime `__builtin_bzero` evaluates its arguments but does not model memory
  contents.
  Frame/return-address builtins are modeled only for nullness: depth 0 returns a
  synthetic non-null pointer, and nonzero depths return null. Tests should
  compare those values only against null or pass them through identity helpers,
  not inspect the synthetic address itself. Aggregate globals are retained as
  type-only declarations so compile tests can query object-size facts, but
  runtime aggregate reads still return `Err`. Unsupported local initializer
  values are not stored, but their side effects are evaluated before later reads
  of those locals return `Err`. The interpreter deliberately returns `Err` for
  general memory, aggregate values, indirect calls, floating point, computed
  goto, varargs, and other behavior that is not modeled yet.
- `test/e2e/mir_oracle_test.mbt` compares selected scalar compiled binaries
  against the MIR interpreter.
- `mir_codegen/semantic_facts_wbtest.mbt` checks that Darwin ARM64 and linux/amd64
  backend-local facts agree with MIR for representative scalar, aggregate,
  packed, union, bit-field, offsetof, expression type, global-expression type,
  builtin-return type, and integer and floating constant-folding cases. It also
  pins attached-backend semantic queries and scalar builtin constant-folding
  delegation to MIR without relying on pre-populated backend layout tables.

## Backend Sharing

`codegen.generate_assembly_for_target` is the direct C AST route. Its production
package imports `parser` and `target`, but not `mir` or `mir_codegen`. This is
the fast path used by default and is intentionally easy to read as a direct
AST-to-assembly compiler.

`mir_codegen.generate_assembly_from_mir_module` is the backend assembly entry
point for an already projected `MirModule`. It treats unsupported MIR coverage
as an error instead of consulting `Program.source`; the `MirModule` input has no
parser-source field. The strict checking contract is
`mir_codegen.generate_assembly_from_mir_module_strict`: it accepts a
`MirModule`, rejects modules that need unsupported MIR body or
global-initializer coverage, and emits through MIR-only backend paths when the
checks pass.

The command-line driver exposes `--strict-mir-codegen`
(`-fno-parser-codegen-fallback`) by parsing and validating C source, lowering it
to `MirModule`, and then calling the backend-facing strict API. This strict gate
does not yet mean every C source program can compile without fallback; it means
successful strict codegen does not carry the parser AST into backend emission.

Parser-facing transitional helpers live in `mir_codegen_compat`.
`generate_assembly_from_mir` projects transitional `Program` values to
`MirModule`, and the explicit parser-fallback helpers route unsupported MIR
coverage to the direct `codegen` package. This keeps fallback behavior out of
the backend-facing API while coverage continues to migrate.

Both MIR assembly backends seed their function return/parameter metadata from
`MirModule.decls`, not parser function declarations. The linux/amd64 backend
also emits function alias, weak declaration, visibility, constructor, and
destructor lifecycle directives from `MirModule.decls`, leaving parser function
declarations out of that metadata-only emission path. Supported MIR-body
function emission also uses `MirModule.decls` for function binding metadata.
Both backend global-symbol lookup maps are seeded from merged
`MirModule.global_decls`, so type and extern/alias questions during MIR emission
do not require parser global declaration records. Both backends also seed their
aggregate layout tables from `MirModule.layouts`.

The current modular boundary is C-AST independent, not fully parser-package
independent. `MirModule` still carries C types using `parser.Type`; removing
that remaining package-level dependency requires extracting the C type model
into a parser-neutral package.

Both backends can now emit the lowered MIR subset for simple scalar integer,
string, symbol-address, symbol-plus-offset, scalar array, and dense aggregate
global initializers. Unsupported initializer forms are rejected by the strict
MIR-module API and may use the direct `codegen` fallback only through
`mir_codegen_compat`.

## Why This Layer Is Useful

The two backends had started duplicating C semantic facts: scalar ABI layout,
aggregate layout, expression typing, and constant folding. Those facts are not
really target instruction selection. Keeping them in MIR makes backend behavior
easier to compare and gives compile tests a non-assembler oracle for scalar
program behavior.

## Remaining Migration Path

1. Expand MIR body lowering statement by statement, starting with general memory
   modeling, aggregate ABI values, and computed goto.
2. Keep `Program::interpret_body_i64` as the first consumer for each new body
   feature so unsupported behavior fails explicitly before codegen depends on
   it.
3. Extend MIR-body codegen from declared integer-scalar extern calls to builtin,
   variadic, and richer ABI calls that have explicit MIR semantics and tests.
4. Add backend differential tests that compare parser-AST codegen with MIR-body
   codegen as the supported subset expands.
5. Once both backends consume MIR bodies for ordinary scalar functions, remove
   duplicated backend statement walking for that subset and leave parser AST use
   in front-end-only lowering code.
6. Only after semantic/body sharing is stable, consider a real machine-level IR
   with explicit virtual registers, blocks, target lowering, and allocation.
