# MIR Architecture

`kimicc` currently has two assembly routes. The direct educational route is
`parser.Program -> codegen`, where the backend walks the C AST in one pass. The
modular route is `parser.Program -> MirModule -> mir_codegen`, where the backend
entry point receives only MIR declarations, layouts, globals, and lowered
bodies. MIR is still a target-sensitive semantic layer plus an emerging
function-body layer, not a full instruction-level machine IR.

## Current Shape

- `ctype/` owns the parser-neutral C type vocabulary shared by parser, MIR,
  and backend-facing codegen APIs. `parser.Type` and
  `parser.OffsetDesignator` remain compatibility aliases for C AST users. It
  also owns parser-neutral builtin facts such as return-type rules, memory,
  string, and printf-family libcall lowering metadata, object-size values,
  generic selection compatibility, classify-type category codes, generic
  integer-builtin widths, and integer bit-operation helpers.
- `mir/` lowers a parsed C translation unit into reusable semantic facts:
  function signatures, selected global declarations, aggregate declarations,
  target-specific sizes/alignments, field layouts, expression types, and integer
  and floating constant folds.
- `Program::to_module` projects those facts into `MirModule`, a parser-AST-free
  backend-facing container for MIR declarations, layouts, globals, and lowered
  bodies. `Program` still carries private parser source for transitional
  parser-side consumers, but the source AST is not part of its exported record
  surface. `lower_to_module` is the direct parser-to-`MirModule` helper for
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
  directly labeled scalar `switch`, simple labels/goto, computed goto through
  label addresses and local/static label-address tables including
  range-designated static tables, local compound
  assignment, local postfix updates, scalar globals, initialized global arrays
  including string arrays, static nested arrays, aggregate elements, and
  casted/implicit global array decay, initialized global aggregates,
  global string, symbol, and label-address pointer initializers, scalar and
  pointer memory prefix/postfix updates, scalar and aggregate compound literals including
  nested local designator paths and address-taking through transparent casts,
  scalar `*&` / `&*` cancellation, scalar local addresses passed across direct
  calls, local array/aggregate/alloca object memory passed across direct calls,
  scaled local/global array element addresses including aggregate-array
  elements, transparent casted scalar address
  loads/stores, direct scalar byte-memory loads/stores through local/global
  objects, byte arrays, floating scalar arrays, local/global floating-field
  aggregate byte copies, union overlay byte memory, Darwin long-double byte
  memory, and aggregate fields,
  address-of aggregate member cancellation including transparent casts,
  aggregate member-address function tables, aggregate array element addresses,
  simple scalar local/global pointer loads/stores,
  simple non-variadic indirect calls and function addresses, scalar local arrays
  including local array compound literals and array-to-pointer decay in call
  arguments, string literal byte loads,
  simple local array initializers including range designators, local aggregate
  array initializers, local aggregate initializers with nested zero-fill,
  scalar-leaf struct copy initializers and recursive array-field copies
  including aggregate elements,
  ignored assignments from local objects and compound literals including
  scalar-field unions and nested scalar aggregate fields, aggregate assignment
  rvalue member reads including side-effecting ternary call-result RHS,
  aggregate ternary assignments, call arguments, local initializers, returns,
  and member reads including call-result and compound-literal branches,
  fixed-size string
  array initialization, initializer side effects for unused unsupported local
  declarations, scalar aggregate fields including nested member access,
  scalar array field access, and array-element aggregate field accesses, signed
  bit-field loads, object-size builtin facts
  lowered as constants, constant-query builtin facts lowered as constants,
  literal and known-string-pointer `__builtin_strlen`,
  runtime integer unary builtins such as `__builtin_abs`, `__builtin_ffs`,
  `__builtin_bswap`, `__builtin_popcount`, and `__builtin_parity`, runtime
  rotate builtins lowered to MIR rotate operations,
  switch case labels nested directly inside `if`/block/loop statements,
  identity builtins such as
  `__builtin_expect` and `__builtin_assume_aligned` including their modeled
  hint-operand side effects,
  no-argument `__sync_synchronize`, atomic thread/signal fence MIR operations,
  atomic load/store/read-modify-write/exchange MIR operations, frame/return-address
  nullness, memory builtin first-argument returns including selected checked
  variants, `mempcpy` end-pointer returns, string destination builtin
  first-argument and end-pointer returns, checked `strlcpy`/`strlcat`
  literal lengths, checked printf-family literal return lengths including
  dynamic `*` width/precision operands and `v*` forms that unpack same-function
  `va_list` cursor values, runtime `__builtin_alloca` and
  `__builtin_alloca_with_align` MIR allocation synthetic pointer values with
  direct, cross-call, and aggregate alloca load/store memory including
  aggregate pointers passed across direct and indirect calls, simple external
  and builtin
  `malloc`/`calloc`/`realloc` heap memory including heap-backed aggregate object
  fields and copies, `aligned_alloc` and `valloc` aligned heap memory, external
  and builtin `strdup`/`strndup` heap string copies, `posix_memalign` aligned
  heap output pointers, Darwin `malloc_size` heap-size queries, and exact-base
  external and builtin `free` invalidation, declared
  external memory/string and printf-family
  libcalls over modeled byte memory, aggregate direct call arguments and aggregate return call
  results, and
  scalar/aggregate `va_arg` reads including large aggregate pointer-slot
  variadic arguments and direct member reads from aggregate `va_arg` rvalues,
  with `va_start`/`va_copy` cursor tracking,
  return-address transforms, no-op
  `__builtin_assume`, runtime `__builtin_prefetch` address evaluation,
  no-op `__builtin___clear_cache`/`__builtin_clear_cache` operand evaluation,
  identity `__builtin_unpredictable`, floating scalar truth/arithmetic,
  `break`/`continue`, and ternaries.
  Missing bodies return `Err` instead of falling back to parser AST execution.
- `mir_codegen/mir_body_codegen.mbt` is the first production backend consumer of
  `MirFuncBody`. It emits Darwin ARM64 and linux/amd64 assembly for
  integer-scalar MIR bodies with local variables, assignments, branches,
  `while`/`for`/`do while` loops, `break`/`continue`, ternaries, casts, direct
  calls to other MIR-bodied functions, declared non-variadic integer-scalar
  externs, selected implicit scalar external calls with arguments, directly labeled
  scalar `switch`, simple labels/goto, computed goto through label addresses
  and local/static label-address tables including range-designated static
  tables, local compound
  assignment, local postfix updates, scalar globals, initialized global arrays
  including string arrays and aggregate elements, initialized global aggregates,
  global string, symbol, and label-address pointer initializers, scalar memory
  prefix/postfix updates, scalar and aggregate compound literals including
  nested local designator paths and address-taking through transparent casts,
  scalar `*&` / `&*` cancellation, scaled local/global array element addresses
  including aggregate-array elements, transparent casted scalar address
  loads/stores, direct scalar byte-memory loads/stores through local/global
  objects, byte arrays, floating scalar arrays, local/global floating-field
  aggregate byte copies, union overlay byte memory, Darwin long-double byte
  memory, and aggregate fields,
  address-of aggregate member cancellation including transparent casts, simple scalar local/global pointer loads/stores,
  simple non-variadic indirect calls and function addresses, scalar local arrays
  including local array compound literals and array-to-pointer decay in call
  arguments, string literal byte loads,
  simple local array initializers including range designators, local aggregate initializers with nested
  zero-fill, scalar-leaf struct copy initializers and recursive array-field
  copies including aggregate elements,
  ignored assignments from local objects and compound literals including
  scalar-field unions and nested scalar aggregate fields, aggregate assignment
  rvalue member reads including side-effecting ternary call-result RHS,
  aggregate ternary assignments, call arguments, local initializers, returns,
  and member reads including call-result and compound-literal branches,
  fixed-size string
  array initialization, direct local string-array element mutation, scalar
  aggregate fields including nested member access and scalar array field access,
  signed bit-field loads, object-size builtin facts lowered as constants,
  constant-query builtin facts lowered as constants, literal `__builtin_strlen`,
  runtime integer unary builtins such as `__builtin_abs`, `__builtin_ffs`,
  `__builtin_bswap`, `__builtin_popcount`, and `__builtin_parity`, runtime
  rotate MIR operations,
  switch case labels nested
  directly inside `if`/block/loop statements, identity builtins such as
  `__builtin_expect` and `__builtin_assume_aligned` including their modeled
  hint-operand side effects,
  no-argument `__sync_synchronize`, atomic thread/signal fence MIR operations,
  trap/unreachable MIR operations, frame/return-address MIR operations, integer
  overflow MIR operations for non-128-bit result pointers, variadic setup MIR
  operations including large aggregate pointer-slot arguments, scalar,
  `__int128`, and aggregate `va_arg` reads,
  atomic load/store/read-modify-write/exchange MIR operations, `bzero` MIR operations, and
  selected memory/string builtin libcalls including
  `strlen`/`strnlen`, `strcmp`/`strncmp`/`memcmp`/`bcmp`,
  `strchr`/`strrchr`/`strstr`/`memchr`/`memmem`,
  `strspn`/`strcspn`/`strpbrk`, `memcpy`/`memmove`/`memset`,
  `mempcpy`/`memccpy`, `stpcpy`/`stpncpy`, checked variants, checked
  `strlcpy`/`strlcat`, and plain and checked `snprintf`/`vsnprintf`/`sprintf`/
  `vsprintf`/`printf`/`vprintf`/`fprintf`/`vfprintf`, and runtime
  `__builtin_alloca`/`__builtin_alloca_with_align` MIR allocation stack
  adjustment,
  return-address transforms, no-op `__builtin_assume`, runtime
  `__builtin_prefetch` address evaluation, no-op `__builtin___clear_cache`
  operand evaluation, identity `__builtin_unpredictable`, and
  arithmetic/logical operators. Unsupported source builtin/atomic calls are
  rejected during MIR body lowering instead of being carried as ordinary direct
  calls into backend emission. Unsupported MIR bodies are rejected by the strict
  MIR-module backend; parser fallback exists only through the explicit
  compatibility wrapper.
- `Program::interpret_i64` is an integer-only interpreter intended for
  compile-test oracles. It supports scalar functions, locals, globals, calls,
  casts, arithmetic, conditionals, loops, scalar switches, simple gotos, selected
  scalar builtin calls including direct-lvalue integer overflow helpers for
  non-128-bit result types, scalar compound literals, and scalar `*&` / `&*`
  cancellation that does
  not require modeling general memory. It also models narrow string-literal facts
  that are useful in compile tests: literal pointer non-nullness, literal byte
  access through transparent casts, constant/runtime pointer offsets, and
  pointer locals/globals initialized from string literals, zero-initialized
  global character arrays, global/local character arrays initialized from
  byte/string literals, including array index/range designators and aligned
  array declarations, element addresses inside those modeled byte objects,
  `sizeof`/`__alignof__` on string
  literals,
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
  `__builtin_alloca`, `__builtin_alloca_with_align`, and selected heap
  allocation builtins. Runtime `__builtin_alloca` and
  `__builtin_alloca_with_align` lower to MIR allocation operations that model
  argument side effects, distinct synthetic non-null pointer values, and direct
  loads/stores through the allocated pointer inside the MIR body interpreter.
  The aligned form evaluates its alignment operand in bits and honors at least
  the target's 16-byte stack alignment in interpreters and strict backends.
  Alloca-backed aggregate field addresses canonicalize to the same modeled
  alloca bytes used by byte libcalls, so typed struct field stores, aggregate
  assignment, `memcpy`, and `memset` share one stack object view. Callees also
  canonicalize aggregate field addresses for caller-owned alloca objects passed
  across direct and indirect calls, and aggregate argument snapshots preserve
  alloca-backed floating and wider scalar fields as bytes when passing `*p` by
  value to fixed and variadic callees or returning it as an aggregate value.
  Simple external `malloc` and `calloc` calls, plus `__builtin_malloc` and
  `__builtin_calloc`, allocate modeled byte memory for the MIR body interpreter,
  `realloc` and `__builtin_realloc` preserve bytes from exact modeled heap
  allocation bases, and `free`/`__builtin_free` invalidate exact modeled heap
  allocation bases while leaving null frees harmless. Heap-backed aggregate
  field addresses canonicalize to the same modeled bytes used by byte libcalls,
  so typed struct field stores, aggregate assignment, `memcpy`, `memset`, and
  `realloc` preservation share one heap object view. Strict MIR backends emit
  the platform calls and ordinary pointer loads/stores operate on the returned
  memory at runtime.
  External `strdup`/`strndup` and their builtin forms similarly allocate modeled
  heap memory in the body interpreter and copy modeled C string bytes from
  caller-visible memory.
  External `aligned_alloc` allocates modeled heap memory at the requested
  alignment and returns the resulting pointer.
  External `valloc` allocates page-aligned modeled heap memory, and Darwin
  `malloc_size` returns the tracked modeled allocation size for exact heap
  allocation bases or zero for null.
  External `posix_memalign` allocates modeled heap memory at the requested
  alignment and stores the resulting pointer through caller-visible pointer
  memory for valid power-of-two alignments.
  Runtime `__builtin_strcmp`, `__builtin_strncmp`, `__builtin_memcmp`, and
  `__builtin_bcmp` lower to MIR libcalls; the body interpreter compares modeled
  byte memory for local arrays, global arrays, aggregates, and string literals.
  Runtime `__builtin_strlen`, `__builtin_strnlen`, `__builtin_strchr`,
  `__builtin_strrchr`, `__builtin_strstr`, `__builtin_memchr`,
  `__builtin_memmem`, `__builtin_strspn`, `__builtin_strcspn`,
  `__builtin_strpbrk`, and `__builtin_memccpy` also lower to MIR libcalls; the
  body interpreter uses modeled byte memory for lengths, searches, spans, and
  byte-copy side effects on the same memory classes.
  Floating comparison builtins such as `__builtin_isgreater`,
  `__builtin_islessgreater`, and `__builtin_isunordered` lower runtime scalar
  operands to strict MIR comparison predicates. Floating classification builtins
  such as `__builtin_isnan`, `__builtin_isfinite`, `__builtin_isnormal`, and
  `__builtin_signbit` lower runtime scalar operands to strict MIR predicate
  operations that preserve operand side effects and return integer predicate
  results. Floating math builtins such as `__builtin_fabs`,
  `__builtin_copysign`, and `__builtin_sqrt` lower runtime scalar operands to
  strict MIR operations while preserving operand side effects. Modeled NaN and
  infinity builtins remain constant-producing helpers.
  Runtime `__builtin_va_start`, `__builtin_va_copy`, and `__builtin_va_end`
  lower to MIR variadic setup operations. The MIR body interpreter tracks a
  simple `va_list` cursor for same-function scalar and aggregate `va_arg`
  reads, while strict backends materialize the target `va_list` state.
  Runtime `__builtin_expect`, `__builtin_expect_with_probability`, and
  `__builtin_assume_aligned` return the value operand while preserving modeled
  side effects in ignored hint operands.
  Runtime `__builtin_prefetch` evaluates its address argument for side effects
  but does not model cache behavior. Runtime `__builtin___clear_cache` and
  `__builtin_clear_cache` evaluate their operands for side effects but do not
  model instruction-cache behavior;
  `__builtin_assume` remains a no-op and does not evaluate its predicate.
  Runtime `__builtin_constant_p` lowers to a MIR constant, returning `1` for
  expressions covered by MIR integer constant
  folding and `0` otherwise, without evaluating the operand. Runtime
  `__builtin_flt_rounds` also lowers to a MIR constant with the current
  round-to-nearest result. The covered compile-time scalar builtin folds include
  absolute value, alignment predicates/helpers, bit counts, byte swaps, parity,
  first/leading/trailing set-bit queries, and rotations.
  Runtime `__sync_synchronize` and atomic thread/signal fences lower to MIR
  fence operations. Thread fences emit backend barriers, while signal fences
  evaluate their order operands for side effects and otherwise model no runtime
  state.
  Runtime `__atomic_load_n`, `__atomic_store_n`, generic pointer-form
  `__atomic_load`/`__atomic_store`, `__c11_atomic_load`, and
  `__c11_atomic_store` lower to MIR atomic load/store operations. Strict
  backends emit target atomic loads and stores, while the MIR body interpreter
  models them as ordinary scalar loads and stores after evaluating the order
  operand.
  Runtime `__atomic_is_lock_free` and `__c11_atomic_is_lock_free` lower dynamic
  size operands to MIR predicates for the modeled lock-free byte widths
  1/2/4/8, while `__atomic_always_lock_free` folds constant size operands to
  the same predicate without evaluating its pointer operand.
  Runtime atomic fetch/update, exchange, test-and-set, clear, compare-exchange,
  generic pointer-form `__atomic_exchange`/`__atomic_compare_exchange`, selected
  `__sync_*` exchange/update builtins, selected `__sync_*` compare-and-swap
  builtins, and selected `__sync_*` signed/unsigned min/max update builtins
  lower to MIR atomic read-modify-write operations. Strict
  backends emit target atomic loops/instructions, while the MIR body interpreter
  models single-threaded scalar behavior after evaluating the extra atomic
  operands.
  Runtime `__builtin_trap` and `__builtin_unreachable` lower to MIR trap
  operations. Strict backends emit target trap instructions, while the MIR body
  interpreter reports an explicit trap error if execution reaches one.
  Runtime alignment helpers lower dynamic scalar operands for
  `__builtin_is_aligned`, `__builtin_align_up`, and `__builtin_align_down` while
  preserving operand side effects.
  Runtime integer unary builtins model the absolute-value, first-set-bit,
  byte-swap, popcount, and parity builtin families for scalar operands. Runtime
  rotate builtins lower dynamic scalar operands while preserving operand side
  effects.
  Runtime integer overflow builtins lower to MIR overflow operations that store
  the converted arithmetic result through the result pointer and return the
  overflow predicate.
  MIR also folds the covered floating constant subset used by global
  initializers and compile-test predicates: floating literals,
  integer-to-floating and floating-to-integer cast paths, arithmetic, ternaries
  selected by integer constants, modeled NaN/infinity builtins, and foldable
  `__builtin_fabs`, `__builtin_copysign`, and `__builtin_sqrt` calls.
  Runtime `__builtin_object_size` and `__builtin_dynamic_object_size` lower to
  MIR constants for modeled facts: string-literal object sizes, direct named
  objects (`&x`), direct named arrays (`buf`), and direct aggregate member
  subobjects such as `&s.buf` or `s.buf`. Modes 0/2 report bytes remaining in
  the complete object, while modes 1/3 report bytes remaining in the nearest
  modeled subobject. Constant array-element addresses and pointer offsets such
  as `&buf[3]` and `buf + 3` subtract target element bytes from those facts.
  Other objects use the C builtin unknown-size fallbacks (`-1` for modes 0/1,
  `0` for modes 2/3). Object-size operands are not evaluated; if the mode
  operand is not constant, strict MIR uses mode 0 like the direct backend.
  `memcpy`/`memmove`/`memset` and their checked aliases lower to MIR libcalls.
  Strict backends call the platform routines, while the MIR body interpreter
  models direct byte effects on modeled memory, including integer, pointer,
  float, and double scalar local/global objects, floating scalar arrays,
  whole local/global floating-field aggregate copies, and scalar aggregate
  fields, and returns the destination pointer. Ordinary MIR scalar loads/stores
  also assemble or scatter bytes through that modeled memory for local/global
  scalar objects, byte arrays, floating scalar arrays, union overlay byte
  memory, whole local/global floating-field aggregate copies, and scalar
  aggregate fields.
  Runtime `__builtin_strlen` lowers to a MIR libc call to `strlen`. Strict
  backends call the platform routine, while the MIR body interpreter evaluates
  the argument and uses its modeled C string memory facts to compute the length.
  Declared external libc calls for `strlen`/`strnlen`,
  `strcmp`/`strncmp`/`strcasecmp`/`strncasecmp`/`memcmp`,
  `bcmp`, `strchr`/`strrchr`/`index`/`rindex`,
  `strstr`/`strcasestr`/`memchr`/`memmem`,
  `strspn`/`strcspn`/`strpbrk`,
  `strsep`/`strtok`,
  `memcpy`/`memmove`/`memset`, `mempcpy`/`memccpy`, `bcopy`/`bzero`,
  `strcpy`/`strcat`/`strncpy`/`strncat`, `stpcpy`/`stpncpy`, and
  `strlcpy`/`strlcat`, plus `strtol`/`strtoll`/`strtoul`/`strtoull`
  and `atoi`/`atol`/`atoll`, share the same MIR body interpreter byte-memory model;
  strict backends emit ordinary platform calls for those declarations.
  Declared case-insensitive calls use modeled C-locale ASCII byte folding.
  Declared `index`/`rindex` share the `strchr`/`strrchr` implementation.
  Declared `memmem` uses the same bounded byte search as modeled memory calls,
  including matches that cross embedded NUL bytes; empty-needle results follow
  the selected target libc behavior (`NULL` on Darwin, haystack on Linux).
  Declared `strspn`/`strcspn` and `strpbrk` scan modeled C strings against a
  modeled accept/reject byte set and return the span length or first matching
  pointer.
  Declared `strsep` reads and updates a modeled `char **`, splits the modeled
  string in place by writing a NUL delimiter byte, and returns the token start
  or null.
  Declared `strtok` keeps a modeled tokenizer cursor on the MIR body interpreter,
  skips leading delimiters, writes NUL delimiter bytes, and resets that cursor
  on a new non-null input string.
  Declared integer conversion calls skip modeled ASCII whitespace, accept an
  optional sign, support bases 0 and 2 through 36, handle `0` octal and
  `0x`/`0X` hexadecimal prefixes for `strto*` forms, consume modeled digits,
  and write modeled end pointers. The `ato*` shorthands use base 10.
  Declared `strnlen` uses the bounded modeled C-string length helper, while
  declared `memccpy` copies modeled bytes until the requested byte is copied or
  the length is exhausted and returns the modeled end pointer or null.
  `mempcpy` and its checked alias lower to a MIR libcall. Strict backends call
  the platform routine, while the MIR body interpreter models direct byte-copy
  effects on modeled memory and returns the `dest + n` pointer.
  `strcpy`/`strcat`/`strncpy`/`strncat` and checked destination-return aliases
  lower to MIR libcalls. Strict backends call the platform routines, while the
  MIR body interpreter models direct copy/append effects on modeled memory and
  returns the destination pointer.
  `stpcpy` and `stpncpy`, plus checked aliases, lower to MIR libcalls. Strict
  backends call the platform routines, while the MIR body interpreter models
  direct copy effects on modeled memory and returns end pointers for modeled C
  string sources.
  Runtime `__builtin___strlcpy_chk` lowers to a `strlcpy` MIR libcall, evaluates
  the checked object-size operand, models direct bounded copy effects on modeled
  memory, and returns the modeled C string source length. Runtime
  `__builtin___strlcat_chk` similarly lowers to a `strlcat` MIR libcall, models
  bounded append effects on modeled memory, and returns the modeled
  `min(strlen(dest), size) + strlen(src)` length.
  Runtime plain and checked printf-family builtins lower to canonical MIR
  libcalls (`snprintf`/`vsnprintf`/`sprintf`/`vsprintf`/`printf`/`vprintf`/
  `fprintf`/`vfprintf`) while preserving side effects from checked
  flag/object-size operands that are not passed to the platform routine. The MIR
  body interpreter models return lengths for the covered literal format subset
  and direct
  destination output bytes for buffer-producing forms in that same modeled
  subset. Declared external calls to the same printf-family routines share this
  MIR body interpreter model, including same-function `va_list` cursor updates
  for `v*` forms, while strict backends emit ordinary platform calls. The
  covered literal format subset includes `%c`, modeled C-string
  `%s`, modeled pointer `%p`, `%n` count stores, decimal `%d`/`%i`,
  nonnegative `%u`/`%o`/`%x`/`%X`, optional integer length modifiers
  `hh`/`h`/`l`/`ll`/`z`/`t`/`j`, finite fixed-decimal `%f`, finite scientific
  `%e`/`%E`, literal and dynamic `*` field widths with `0`/`-` flags,
  `+`/space sign flags for decimal `%d`/`%i` and finite `%f`/`%e`/`%E`,
  `#` alternate form for nonnegative
  `%o`/`%x`/`%X`, literal and dynamic `*` precision for modeled C-string
  `%s`, decimal `%d`/`%i`, finite `%f`/`%e`/`%E`, and nonnegative
  `%u`/`%o`/`%x`/`%X`, or escaped `%%`. `v*` forms unpack same-function
  `va_list` cursors for the same modeled scalar and C-string pointer subset.
  Runtime `__builtin_bzero` lowers to a MIR `bzero` operation. Strict backends
  call the platform `bzero` routine, while the MIR body interpreter models
  direct zero-fill effects on modeled byte memory, including local/global
  aggregate objects and aggregate array elements addressed through raw
  `&object` pointers. Declared external `bzero` shares that zero-fill model,
  while declared external `bcopy` and `bcmp` share the modeled byte-copy and
  byte-compare helpers.
  Darwin `__darwin_fd_set`, `__darwin_fd_clr`, and `__darwin_fd_isset` helpers
  lower to MIR scalar memory loads, stores, and bit operations, preserving the
  evaluated file-descriptor and `fd_set` operands without emitting unresolved
  helper calls in strict MIR codegen.
  Frame/return-address builtins lower to MIR operations modeled only for
  nullness: depth 0 returns a synthetic non-null pointer, and nonzero depths
  return null. Tests should
  compare those values only against null or pass them through identity helpers,
  not inspect the synthetic address itself. Aggregate globals are retained as
  type-only declarations so compile tests can query object-size facts, but
  runtime aggregate reads still return `Err`. Unsupported local initializer
  values are not stored, but their side effects, including writes to modeled
  character arrays, are evaluated before later reads of those locals return
  `Err`. The interpreter deliberately returns `Err` for
  general memory, aggregate values outside modeled copy/argument/return paths,
  and other behavior that is not modeled yet.
- `test/e2e/mir_oracle_test.mbt` compares selected scalar compiled binaries
  against the MIR interpreter.
- `test/e2e/strict_mir_codegen_test.mbt` includes backend differential checks
  that run parser-AST codegen and strict MIR-body codegen as separate binaries
  and compare exit code plus stdout for shared supported cases, including
  generic selection, builtin compile-time choice lowering, and compile-time
  type fact lowering,
  computed goto through local label addresses and static/local label-address
  tables including range-designated static tables, checked printf formatting,
  clear-cache/no-op builtins, alignment and
  hint builtins, stack allocation builtins, object-size/constant query
  builtins, frame/return-address builtins, sync/atomic fence builtins, floating
  fabs/infinity, comparison,
  classification, and math builtins, integer count/unary/rotate builtins,
  `bzero`, Darwin fd helpers, builtin
  memory/string libcalls, modeled scalar object/byte memory and scalar
  aggregate-field memory libcalls, array-element aggregate field accesses,
  bit-field loads/stores and sign extension, int128 direct and stack-passed
  calls, stack-passed integer and floating direct/indirect calls,
  small/HFA/memory aggregate call
  results, aggregate compound literal returns and arguments, identity-cast
  aggregate returns and arguments, aggregate member returns, aggregate
  call-result member reads, aggregate ternary copies, aggregate ternary call
  arguments, aggregate call-result ternary assignments, local initializers,
  returns, arguments, and member reads, aggregate compound-literal ternary
  assignments, arguments, and returns, function-pointer aggregate returns,
  register, stack, indirect-register, indirect-stack, and large aggregate parameters,
  floating, stack-passed, and mixed integer/floating variadic libcalls,
  checked `vsnprintf` va_list libcalls, indirect variadic function-pointer
  calls, function-typedef pointer calls including explicit
  dereferenced calls, scalar `va_copy` plus scalar and aggregate `va_arg`
  cases including large aggregate direct/indirect variadic caller
  paths, alloca-backed aggregate variadic arguments, and alloca-backed
  aggregate returns, stack object pointers passed through direct and indirect
  calls,
  aggregate member-address function tables, aggregate array element addresses,
  pointer post-updates through pointer memory, globals arrays and structs,
  static nested arrays, nested switch case-label entry through `if`/loop/
  `do while` bodies, struct copies with bit-fields, local array pointer
  arithmetic and direct/ternary/member array decay, casted object byte offsets,
  compound memory updates preserving their LHS across RHS evaluation,
  pointer-memory updates preserving their LHS across RHS calls,
  local aggregate array initializers, local range initializers including local
  array compound literals, nested local compound-literal designators,
  local scalar brace initializers, global aggregate copies, member-array decay
  in pointer call arguments, atomic load/store operations, exchange-style
  atomics, sync compare-and-swap and min/max atomics, atomic RMW extra-operand
  side effects, integer overflow builtins, anonymous-union array member decay,
  local pointer updates, casted pointer dereferences, casted and implicit
  global array decay, aligned global/local arrays, over-aligned array fields,
  floating local casts, comparisons, ternaries, logical operators, compound
  updates, arithmetic, unary operators, floating array byte memory,
  local/global floating-field aggregate byte copies, union overlay byte memory,
  Darwin long-double byte memory, float direct/indirect calls, and
  indirect calls returning function pointers,
  global address-cancellation loads,
  TinyCC-style aggregate copies, comma aggregate assignments, aggregate
  assignment rvalue member reads, local aggregate array assignment rvalues,
  aggregate assignment ternary-call rvalues, bit-field compound updates,
  floating comma stores, scalar
  initialized global aggregate memory, global aggregate float arrays, global
  compound literals, exact-width global string aggregate fields, braced scalar
  and nested braced scalar global initializers, file-scope compound literal
  addresses, casted string-pointer global array initializers,
  atomic read-modify-write builtins, generic pointer-form atomic builtins, and
  bit-field postfix updates used as aggregate array indexes.
- `mir_codegen/semantic_facts_wbtest.mbt` now uses hand-built parser-free
  `MirModule` values to pin Darwin ARM64 and linux/amd64 backend layout,
  offsetof, and global initializer emission through the backend-facing API.

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
`MirModule`, while the explicit parser-fallback helper accepts the original
`parser.Program` and routes unsupported MIR coverage to the direct `codegen`
package. This keeps fallback behavior out of the backend-facing API and avoids
exposing parser source through `mir.Program` while coverage continues to
migrate.

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

The production `mir_codegen` package no longer carries parser `Program`,
function declaration, global declaration, parameter, or statement nodes in its
MIR emission state. Legacy parser-facing fallback entry points live outside the
package in `mir_codegen_compat`.

The current `MirModule -> mir_codegen -> assembly` boundary is C-AST
independent and uses parser-neutral `ctype.Type` / `ctype.OffsetDesignator` for
MIR-facing type data. Fixed and argument-dependent builtin return-type
classifications now live in `ctype.builtin_return_rule`, with
`ctype.builtin_return_type` resolving those rules from parser-neutral argument
type facts and `ctype.builtin_return_condition_arg_index` describing the folded
constant operand needed by `__builtin_choose_expr`; the remaining direct
parser-AST backends call through the same helper instead of carrying their own
builtin return tables. Heap, memory/string,
string-length query, and printf-family builtin wrapper-to-libcall metadata plus
atomic read-modify-write operation/result-shape and extra-operand metadata and
overflow arithmetic builtin operator metadata also live in `ctype`. Runtime integer builtin metadata
for alignment queries/rounding, `abs`, `bswap`, rotate, `clz`, `ctz`, `ffs`,
`popcount`, and `parity` is shared there too, so MIR body lowering and the
direct parser-AST backends no longer carry private copies of those builtin
call-shape tables. Hint/identity builtin call-shape metadata for
`__builtin_expect`, `__builtin_assume_aligned`, `__builtin_unpredictable`, and
return-address transforms is centralized there as well, along with no-op
builtin operand-evaluation rules for `__builtin_assume`, `__builtin_prefetch`,
and clear-cache builtins. Frame/return-address query builtin metadata is shared
there too, as is trap-like builtin classification for `__builtin_trap` and
`__builtin_unreachable`. Sync and atomic fence builtin metadata is shared there
too, along with atomic lock-free query metadata and the modeled lock-free byte
width predicate, atomic load/store builtin call-shape metadata, atomic
zero-store helper metadata for `__atomic_clear` and `__sync_lock_release`,
atomic exchange/test-and-set and compare-exchange call-shape metadata,
fixed integer constant builtin metadata such as
`__builtin_flt_rounds`, stack-allocation builtin metadata for `__builtin_alloca`
and `__builtin_alloca_with_align`, variadic setup builtin metadata for
`__builtin_va_start`, `__builtin_va_copy`, and `__builtin_va_end`, Darwin
fd helper metadata for `__darwin_fd_set`, `__darwin_fd_clr`, and
`__darwin_fd_isset`, and zero-memory builtin metadata for `__builtin_bzero`.
Object-size and constant-query builtin call classification
for `__builtin_object_size`, `__builtin_dynamic_object_size`, and
`__builtin_constant_p` is shared there as well, including parser and MIR
constant-folding dispatch and parser-backed MIR interpreter dispatch. Stack
allocation, variadic setup, zero-memory, string-length, and runtime floating
classification/comparison interpreter dispatch use the same parser-neutral
metadata rather than local builtin-name tables. Parser-backed MIR interpreter
models for memory/string destination builtins, checked `strl*` builtins, and
checked `printf`-family length calculations also dispatch through the shared
libcall metadata. Literal string compare/search/span oracle models, including
`bcmp`, explicit-length `memmem`, and `strspn`/`strcspn`/`strpbrk`, are keyed
by the shared compare/search/span libcall metadata too. The
string-literal object-size and C-string length facts used by parser constants,
MIR lowering/interpreters, and direct parser-AST codegen live in `ctype` too. The
shared atomic builtin target-type rule plus integer literal and constant-token
type selection live in `ctype`;
integer constant signedness/width facts live on `ctype.Type`;
wrapper-stripping, pointer/array element queries, anonymous
aggregate detection, generic integer-builtin width selection, integer
promotion, common-type selection, scalar unary/binary/ternary and
pointer-aware binary expression result-type
selection shared by MIR lowering and direct parser-AST codegen, and integer
constant arithmetic/comparison/
division/shift/unary/logical helpers live in `ctype` too. Scalar integer
builtin constant facts such as absolute value, alignment, count/bit operations,
byte swaps, rotates, and folded-operand arity gating are centralized there as
well, and parser, MIR, and direct parser-AST codegen call through the same
folded-argument entry point. The parser constant folder now carries
`ctype.IntegerConstant` values directly instead of converting through a
parser-local integer constant wrapper, and the legacy standalone
`parser.fold_const(Expr)` entry point has been removed in favor of contextual
parser/MIR constant folders that carry target, layout, and scope facts. MIR's
parser-expression constant folder and both MIR interpreters also use
`ctype.IntegerConstant` directly instead of a MIR-local integer constant
wrapper, and both direct parser-AST codegen backends use the same representation
instead of backend-local integer constant wrappers.
Floating constant arithmetic, unary signs, NaN/infinity constants,
absolute-value, square-root, sign-bit, copy-sign, integer/floating conversion,
classification, and unordered comparison facts are also shared there, along
with floating builtin constant arity/result selection, runtime floating builtin
comparison/classification/math call-shape metadata used by folded MIR
classification/comparison dispatch, and canonical NaN/infinity result-bit
metadata for explicit MIR lowering and direct parser-AST backend dispatch.
MIR-codegen integer conversion decisions
now call through the same parser-neutral
integer promotion, common-type, signedness, and int128 classification helpers.
Shared `__builtin_object_size` mode, byte-offset, array-element, and
member-subobject arithmetic also live in `ctype.ObjectSizeFact`, including
mode-dependent result/fallback selection, so parser and MIR expression typing
share those parser-neutral C type facts. `MirModule.object_size_path_fact`
exposes the same object-size arithmetic from parser-free root types and
`ctype.OffsetDesignator` paths for MIR consumers that already know the object
path. Constant-query builtin result selection for `__builtin_constant_p` is
shared in `ctype` as well.
Remaining
parser-package coupling lives on the
`parser.Program -> MIR` side, especially transitional expression semantic
helpers that still reason about parser `Expr` values before those facts are
fully available as MIR-native values. Parser-expression type and constant-fold
queries are no longer part of the exported MIR API; backend-facing consumers
query `MirModule.globals`, `MirModule.field_layout`, `MirModule.type_size`,
`MirModule.offset_of_path`, and related parser-neutral layout facts instead.

Both backends can now emit the lowered MIR subset for scalar integer/floating
values, string pointers and arrays, symbol addresses, symbol-plus-offset
relocations, scalar and sparse arrays, dense and sparse aggregates, bit-field
aggregate slots, compound-literal global values, and braced scalar global
values. File-scope compound literals used by address are projected as generated
static MIR globals, with incomplete array compound literal types completed from
their initializer lists. Unsupported initializer forms are rejected by the
strict MIR-module API and may use the direct `codegen` fallback only through
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
5. Move the remaining parser expression helpers used for constant facts behind
   parser-neutral MIR APIs, now that the shared C type vocabulary lives in
   `ctype/`.
6. Only after semantic/body sharing is stable, consider a real machine-level IR
   with explicit virtual registers, blocks, target lowering, and allocation.
