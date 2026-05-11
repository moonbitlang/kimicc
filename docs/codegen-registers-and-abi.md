# Codegen Registers And ABI

`kimicc` emits target assembly directly from the parser AST. It does not lower
through a separate machine IR, and it does not have a general register
allocator. The Darwin ARM64 backend is built around a fixed scratch-register
discipline plus explicit Darwin ARM64 C ABI argument and return placement.

This document describes the current implementation contract. It is not a claim
of complete C ABI conformance for every C type or language feature. The accurate
claim is narrower: the backend is ABI-aware for the supported ARM64 macOS C
subset, and that subset is guarded by focused tests and Clang differentials.

## Register Discipline

Most C objects live in stack slots. Registers are transient codegen resources
used while evaluating one expression or crossing a function-call boundary.

| Register | Current role |
|---|---|
| `x0`-`x7` | Integer/pointer argument registers and integer return registers at ABI boundaries. |
| `s0`-`s7`, `d0`-`d7` | Floating-point argument registers and floating-point return registers at ABI boundaries. |
| `x8` | Hidden struct-return destination pointer for indirect aggregate returns. |
| `x9` | Primary expression result register and address result register. |
| `x10` | Secondary scalar register: right-hand operand, high half of `__int128`, or temporary value. |
| `x11`, `x12`, `x13` | Scratch temporaries for address arithmetic, bit-fields, atomics, copies, and masks. |
| `x15` | Saved indirect callee address before a `blr`. |
| `x16` | Large stack-frame adjustment scratch. |
| `x29`, `x30` | Frame pointer and link register, saved/restored in the normal prologue/epilogue. |
| `x18` | Reserved by Apple platforms; codegen does not use it. |
| `sp` | Evaluation spill stack, call temporary area, outgoing stack arguments, and local frame allocation. |

The generator avoids keeping user variables in registers across expressions.
This keeps correctness local and makes nested calls simple, at the cost of
extra loads and stores.

## Function Frames

`Codegen::gen_func` starts each function by clearing per-function state,
assigning stack slots to parameters, collecting all local declarations and
hidden temporaries, and rounding the frame to 16 bytes. It then emits:

```asm
stp x29, x30, [sp, #-16]!
mov x29, sp
sub sp, sp, #frame_size
```

Parameters are copied from ABI locations into their stack slots at function
entry. Integer and pointer parameters come from `x0`-`x7` or caller stack
slots. `float` and `double` parameters come from `s0`-`s7` / `d0`-`d7` or stack
slots. Aggregate parameters are copied according to their current size class.

After that entry copy, reads and writes of C locals normally go through
`emit_load_local`, `emit_store_local`, `gen_addr`, and typed load/store helpers.

## Expression Evaluation

`gen_expr` leaves scalar expression results in `x9`. Address-producing paths
also leave the address in `x9`.

Binary scalar expressions use a stack spill instead of allocating another live
register:

1. Evaluate the left operand into `x9`.
2. Spill `x9` to `[sp, #-16]!`.
3. Evaluate the right operand into `x9`.
4. Move the right result to `x10`.
5. Pop the left result back into `x9`.
6. Emit the operation using `x9` and `x10`.

`__int128` values use the pair `x9:x10`, with `x9` holding the low half and
`x10` holding the high half. Floating-point values are often carried as raw
bits in integer scratch registers between AST operations, then moved into
`sN`/`dN` registers for floating-point arithmetic, calls, or returns.
Covered conditional expressions compute a C result type for scalar, pointer,
and function-pointer branches, then convert only the selected arm to that type
before control flow rejoins.

## Calls

Calls have their own ABI placement pass. The backend first classifies each
argument, computes the needed temporary stack area, evaluates all arguments into
temporary stack slots, and only then reloads those saved values into ABI
locations. This avoids nested calls clobbering partially prepared argument
registers.

For non-variadic calls:

- integer and pointer arguments are assigned to `x0`-`x7`, with overflow in
  outgoing stack slots;
- `float` and `double` arguments are assigned to `s0`-`s7` / `d0`-`d7`, with
  overflow in outgoing stack slots;
- 128-bit integer arguments consume two integer slots;
- small struct/union arguments are copied into one or two integer slots;
- larger struct/union arguments are copied to a caller-owned temporary area and
  passed by pointer;
- indirect callees are evaluated and saved before argument reloading, then
  called with `blr x15`.

For variadic calls, the backend also builds the Darwin ARM64 unnamed-argument
stack area so `va_start`/`va_arg` can read variadic arguments from the expected
location. Known external variadic functions such as `printf`, `snprintf`,
`open`, `fcntl`, and `ioctl` are treated as variadic even when only an external
declaration is visible.

## Returns And Aggregates

Scalar returns are moved to ABI return registers:

- integer and pointer results use `x0`;
- `float` uses `s0`;
- `double` uses `d0`;
- `__int128` uses `x0:x1`.

Structs and unions are split into two current size classes:

- aggregates up to 16 bytes are register aggregates and are returned or passed
  through one or two integer slots;
- aggregates larger than 16 bytes are indirect aggregates and use caller-owned
  storage, with return destinations passed in hidden `x8`.

Assignments and initializers copy aggregate storage with explicit address-based
paths, and call results for register aggregates are materialized when a later
operation needs an address or field access.

## Global Initializers

Darwin ARM64 global scalar initializers are folded through the initializer
expression's C type before conversion to the destination object type. This keeps
integer subexpressions such as `1 / 2` in integer semantics when initializing
floating storage, preserves explicit floating-to-integer initializer
conversions, and applies the covered usual arithmetic conversions for unsigned
integer division, modulo, shifts, and comparisons.
Pointer and function-pointer global initializers can also emit relocations to
globals, functions, and aggregate subobjects. Pointer arithmetic in those
relocations is scaled by the effective pointer type, including casted pointer
bases and address-of casted pointer subscripts.
Global aggregate initializers emit layout padding and covered bit-field storage
units, including grouped struct bit-fields and designated union bit-fields.

## ABI Compliance Status

The backend is intended to match the Darwin ARM64 C ABI for the supported
feature set. Several high-risk ABI areas have focused tests, including:

- narrow scalar parameter signedness;
- prototype-driven scalar argument conversion;
- floating-point argument and return registers;
- mixed scalar conditional-expression conversions;
- conditional function-pointer calls preserving argument and return metadata;
- 16-byte aggregate pass/return behavior;
- large aggregate arguments and hidden result pointers;
- variadic calls and `va_arg` layout;
- global scalar constant initializers;
- global aggregate, pointer-relocation, and bit-field initializers;
- direct Mach-O object mode versus assembly mode.

The project also keeps broader Clang differential corpora and external-project
smoke gates. See `docs/sqlite-conformance-plan.md` for the evolving confidence
matrix and residual known failures.

Do not treat this as full ABI compliance yet. Known reasons include:

- there is no independent ABI classification table separate from codegen;
- `_Float16`, vector/SIMD C types, and HFA/HVA aggregate rules are not modeled
  as first-class supported types;
- unusual packing, alignment, and extension combinations need more differential
  coverage;
- the full C language and GNU/Clang extension surface is still growing.

In short: the current Darwin ARM64 backend is intentionally ABI-aware and
correct for the covered subset, but complete C ABI compliance remains a
conformance goal rather than a finished claim.

## Linux/amd64 Backend Status

The `linux-amd64` backend is separate from the Darwin ARM64 backend. It emits
GNU assembler syntax for the System V x86-64 ABI and uses a similar simple
model: C locals are stack slots, expression results use `rax`, and short-lived
temporaries use scratch registers such as `r10` and `r11`. Scalar integer
operations use signed or unsigned x86-64 instructions according to C's usual
arithmetic conversions for the covered integer subset. Narrow integer and
`_Bool` scalar casts, initializers, assignments, and returns are converted to
the destination type before storage or ABI return placement; unsigned 64-bit
integer to `float`/`double` conversions use an explicit high-bit path instead
of signed `cvtsi2s*`, and `float`/`double` to unsigned 64-bit integer
conversions use the corresponding high-bit split around `2^63`. Mixed scalar
ternary arms are converted to the selected conditional-expression result type
before control flow rejoins. Mixed integer/floating compound assignments for
non-`__int128` integer lvalues use floating arithmetic before converting back to
the lvalue type, including covered integer bit-field lvalues. Covered integer
bit-field compound assignments apply integer promotions before the arithmetic
operation and then store back through the bit-field mask. Direct calls use
declared parameter types to select scalar argument registers and conversions;
typed function-pointer calls preserve parsed parameter types and apply the same
scalar argument conversions before indirect calls.
Pointer `+`, `-`, `+=`, and `-=` scale integer operands by the pointed element
size for the covered object pointer cases.
Unnamed variadic call arguments use C default argument promotions before ABI
classification, and calls through declarations with no recorded parameter types
apply the same promotions to supplied arguments. Narrow integer call results are
normalized from their ABI return subregister before the value is used as an
expression.

Its current ABI coverage is intentionally narrower than the Darwin backend:
integer and pointer parameters use `rdi`, `rsi`, `rdx`, `rcx`, `r8`, and `r9`;
`float` and `double` parameters use `xmm0` through `xmm7`; integer and pointer
returns use `rax`; `__int128`/`__uint128_t` transport uses paired integer
eightbytes in `rdx:rax` for returns and two integer argument slots for calls,
parameters, and `va_arg`, with truth tests checking both halves. Covered
128-bit arithmetic includes add, subtract, multiply, bitwise operations,
shifts, comparisons, compound assignment, and division/remainder through the
normal `__divti3`/`__udivti3`/`__modti3`/`__umodti3` helper calls.
Floating-point returns use `xmm0`; ELF symbols do not use the Darwin leading
underscore; scalar overflow arguments are copied to the System V stack argument
area. Direct and indirect function-pointer calls use the same argument and
return placement. Direct variadic calls set `%al`, variadic callees save the
System V register-save area, and `__builtin_va_*` lowering is
implemented for scalar values plus the covered small and memory-class aggregate
`va_arg` subset. Common memory and string builtins are lowered to Linux libc
calls before normal x86-64 call lowering; fortified `strlcpy`/`strlcat`
checked builtins drop their object-size argument before the libc call. Common
scalar hint/query and bit-manipulation builtins lower directly without
external calls; object-size query builtins conservatively report unknown size.
`__builtin_flt_rounds` currently reports the default round-to-nearest mode.
`__builtin_frame_address` exposes `rbp`;
`__builtin_return_address(0)` loads `[rbp + 8]`, nonzero depths return null,
and return-address extract/frob helpers are identity operations on x86-64.
Common signed integer absolute-value builtins `__builtin_abs`,
`__builtin_labs`, and `__builtin_llabs` also lower directly at the target
result width.
`__builtin_alloca` dynamically subtracts a 16-byte-aligned size from `rsp` and
the function epilogue restores `rsp` from `rbp`. Common floating builtins
including `__builtin_fabs*`, `__builtin_nan*`, `__builtin_huge_val*`,
`__builtin_inf*`, `__builtin_copysign*`, `__builtin_sqrt*`, and the
ordered/unordered `__builtin_is*` predicates also lower directly; floating
comparisons explicitly account for unordered `NaN` conditions. `float` and
`double` compound assignments plus prefix/postfix increment/decrement keep
their arithmetic in SSE registers and store the converted result back through
the lvalue type. Covered
integer-width atomic
builtins lower directly: loads and stores use x86-64 scalar memory operations,
GNU and C11 exchange plus byte test-and-set/clear use `xchg`,
compare-exchange and read-modify-write operations, including `nand`, use
`lock cmpxchg`, C11 weak compare-exchange uses the same non-spurious lowering
as strong compare-exchange, thread fences and `__sync_synchronize` use
`mfence`, signal fences are no-ops in emitted code, and lock-free query
builtins report true for the covered 1-, 2-, 4-, and 8-byte scalar widths.
The common overflow-checking builtins `__builtin_add_overflow`,
`__builtin_sub_overflow`, and `__builtin_mul_overflow`, plus their signed and
unsigned typed spellings such as `__builtin_sadd_overflow` and
`__builtin_umulll_overflow`, lower directly for integer result pointer types up
to 64 bits, using x86-64 carry/overflow flags and storing the truncated result
through the supplied pointer.
The Docker smoke also verifies that common Ubuntu 24.04 system headers
preprocess far enough to expose glibc typedefs such as `uint8_t`, `uintptr_t`,
`size_t`, `ptrdiff_t`, and `va_list`, then compiles and links a small
Linux/amd64 executable using those typedefs. The compiled probe includes
representative unsigned max-value macro comparisons, including `UINTPTR_MAX`
and `SIZE_MAX`, in `_Static_assert` expressions. That is a targeted
system-header gate, not a complete libc or System V ABI conformance claim. A
separate smoke passes kimicc's generated `va_list` state to glibc `vsnprintf`,
which covers one real v-function interop path while leaving broader libc
`va_list` compatibility open.
Small scalar-field
`struct`/`union` arguments and returns up to 16 bytes are
classified recursively by eightbyte, including nested structs/unions and arrays
of supported scalar fields, and passed or returned in the covered integer, SSE,
mixed integer/SSE, and overflow-stack subset. When the final aggregate
eightbyte is only partially occupied, register loads and stores use that
partial object width rather than an unconditional 8-byte memory access,
including the scratch copy used for register-sourced aggregate `va_arg`.
Memory-class aggregate arguments are passed by value on the overflow stack, and
memory-class aggregate returns use the System V hidden result pointer.
Actual aggregate object copies and `va_arg` overflow-stack scratch copies use
the exact C object size so nested small struct assignments and packed varargs
do not overwrite following fields; only ABI staging areas and overflow cursor
movement are rounded to eightbyte slots.
Local aggregate brace initializers and compound literals are supported for the
covered scalar, array, struct, union, nested-designator, and bit-field
initializer cases; compound literals are materialized in stack storage.
Global floating and integer scalar constant initializers are folded through the
source expression's C type before conversion to the destination object type, so
integer subexpressions such as `1 / 2` keep integer-division semantics and
explicit or implicit floating-to-integer initializer conversions initialize
integer storage. Integer constant folding uses the covered usual arithmetic
conversions, including unsigned division, modulo, right shifts, and relational
comparisons.
Initialized global arrays, structs, and unions are emitted with layout padding
and designated-initializer holes for the covered aggregate cases, including
bit-field storage units that do not overlap earlier streamed scalar fields and
pointer/function-pointer relocations to globals, functions, and aggregate
subobjects. Pointer arithmetic in global relocations is scaled by the effective
pointer type, including casted pointer bases and address-of casted subscripts
such as `(char *)array + n` and `&((char *)array)[n]`.
`__builtin_offsetof` folds simple, nested, and constant array-index member
designators using the same covered aggregate layout model.
The shared frontend also folds covered C11 `_Generic` selections to the chosen
association expression before backend lowering; the controlling expression is
parsed for type selection but not emitted or evaluated.
GNU `typeof`/`__typeof__` type specifiers are similarly resolved in the parser;
expression operands are parsed only to infer their type.
GNU `__auto_type` locals are resolved in the parser from their initializer type
for covered scalar and pointer expressions.
C11 `_Alignof(type)` and GNU `alignof`/`__alignof__` type or expression
operands are folded to the covered parser type model's alignment.
GNU `__builtin_choose_expr` and `__builtin_types_compatible_p` are handled the
same way for the covered parser type model.
GNU `__builtin_classify_type` is also folded before backend lowering.
`_Alignas` and numeric GNU `__attribute__((aligned(N)))` participate in x86-64
aggregate layout, ELF global alignment, and stack-local frame realignment.
Functions that need a local frame alignment greater than 16 bytes save and
restore `r13` when using it as the aligned local-frame base. GNU
`__attribute__((packed))` participates in aggregate layout, and packed
aggregates with unaligned fields become System V memory-class arguments and
returns. The same unaligned-field rule is applied when a non-packed outer
aggregate contains a packed member at an unaligned offset. Integer bit-fields
use packed storage-unit layout for the covered cases and are lowered with
read-modify-write updates. Parser-accepted no-op GNU diagnostic, optimization,
allocation, and sanitizer attributes are ignored during lowering. Switch
dispatch emits explicit case comparisons, uses the promoted control expression
type, preserves default and fallthrough behavior, and compares 32-bit integer
switches through `eax`.
Vector, x87/complex, vector varargs, direct ELF object emission, and Linux JIT
loading are still future work. Complete libc `va_list` interoperability is also
open. See
[`docs/linux-amd64-target.md`](linux-amd64-target.md) for the current test
workflow.

## References

- Apple, ["Writing ARM64 code for Apple platforms"](https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms),
  especially the sections on reserved registers, stack alignment, small integer
  extension, and variadic argument stack slots.
- Arm, ["Procedure Call Standard for the Arm 64-bit Architecture (AAPCS64)"](https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst),
  for the generic AArch64 procedure-call baseline that Apple documents its
  platform differences against.
