# Linux/amd64 Target

`linux-amd64` is an experimental second output target. It is intended to make
the target split real and testable without claiming full C ABI coverage yet.

## What Works

- `-target linux-amd64 -S` emits GNU assembler syntax with Intel operands.
- External C symbols use ELF spelling, so `main` is emitted as `main`, not
  `_main`.
- The preprocessor seeds Linux/x86-64 target macros such as `__linux__`,
  `__gnu_linux__`, `__ELF__`, `__x86_64__`, `__amd64__`, `_LP64`, basic
  `__SIZEOF_*`/width/max-value macros, atomic memory-order constants, and ELF
  empty label/register prefix macros. `__has_builtin(name)` reports true for the
  builtin functions and atomic intrinsics the Linux/amd64 lowering currently
  supports, and false for unsupported builtin names. `__has_attribute(name)`
  reports true for GNU `packed`/`__packed__` and numeric
  `aligned`/`__aligned__` attributes, matching the layout attributes the
  parser and backend currently honor, plus parser-accepted no-op GNU
  diagnostic, optimization, allocation, and sanitizer attributes.
  Clang-style feature probes
  report true only for the covered `c_alignas`, `c_alignof`,
  `c_static_assert`, `c_atomic`, and `c_generic_selections` language features;
  unsupported feature, C attribute, declspec attribute, and warning probes
  report false.
  `__is_identifier(name)` reflects the parser's C keywords and recognized
  extension tokens. `__COUNTER__`
  increments on each macro expansion. Variadic macros support `__VA_ARGS__`,
  GNU comma-paste elision, and `__VA_OPT__(...)`. `#elifdef`/`#elifndef` are
  accepted in conditional groups. `#line` and GCC-style linemarkers such as
  `# 42 "file.c"` update the logical source coordinates used by `__FILE__`
  and `__LINE__`. `__has_include(...)` and `__has_include_next(...)` use the
  same explicit quote/system include search rules as `#include` and
  `#include_next`, and `#pragma once` suppresses repeated inclusion of the same
  resolved header path.
- Integer and pointer arguments use the first six System V registers:
  `rdi`, `rsi`, `rdx`, `rcx`, `r8`, and `r9`.
- `__int128` and `__uint128_t` values use two integer eightbytes for the
  covered load/store, parameter, return, call, and `va_arg` cases. `_Bool`,
  `if`, and `!` truth tests inspect both halves. Covered 128-bit arithmetic
  includes add, subtract, multiply, bitwise operations, shifts, comparisons,
  compound assignment, and division/remainder through the normal
  `__divti3`/`__udivti3`/`__modti3`/`__umodti3` helper calls.
- `float` and `double` arguments use `xmm0` through `xmm7`.
- Integer and pointer returns use `rax`.
- `float` and `double` returns use `xmm0`.
- Stack-passed scalar call arguments are copied into the System V overflow
  argument area, with the stack aligned before `call`.
- Direct variadic calls set `%al` to the number of used vector argument
  registers, and variadic callees save the System V register-save area for
  `__builtin_va_start`, `__builtin_va_arg`, `__builtin_va_copy`, and
  `__builtin_va_end`. Unnamed variadic arguments use C default argument
  promotions before ABI classification. Calls through declarations with no
  recorded parameter types also use default promotions for supplied arguments.
  `va_arg` supports scalar values plus the covered small and memory-class
  aggregate subset, including packed memory-class aggregates read from the
  overflow stack.
- Small scalar-field `struct`/`union` arguments and returns up to 16 bytes are
  recursively classified by eightbyte as integer or SSE, including nested
  structs/unions and arrays of supported scalar fields. Covered integer, pure
  SSE, and mixed integer/SSE aggregates use `rax`/`rdx`, `xmm0`/`xmm1`, `rdi`
  through `r9`, `xmm0` through `xmm7`, or the overflow stack area as required by
  the covered System V aggregate subset.
- Memory-class `struct`/`union` arguments are copied by value into the overflow
  stack argument area. Memory-class aggregate returns use the System V hidden
  result pointer in `rdi` and return that pointer in `rax`.
- Aggregate assignments, aggregate initializers, hidden-result copies, and
  `va_arg` overflow-stack scratch copies copy the exact C object size; ABI
  stack/register staging and overflow cursor movement still use the required
  rounded eightbyte slots internally.
- Local aggregate brace initializers and compound literals are lowered for the
  covered scalar, array, struct, union, nested-designator, and bit-field
  initializer cases. Compound literals use stack storage with block lifetime in
  the generated function.
- Initialized global arrays, structs, and unions are emitted with layout
  padding and designated-initializer holes for the covered aggregate cases,
  including bit-field storage units that do not overlap earlier streamed
  scalar fields and pointer/function-pointer relocations to globals, functions,
  and aggregate subobjects.
- `__builtin_offsetof` folds simple, nested, and constant array-index member
  designators using the covered aggregate layout model.
- `_Alignas` and numeric GNU `__attribute__((aligned(N)))`/`__aligned__(N)`
  are honored for x86-64 struct/union layout, ELF global alignment, and stack
  locals. Functions with locals requiring more than 16-byte alignment keep
  `rbp` as the incoming frame anchor and use an aligned local-frame base.
- GNU `__attribute__((packed))` on struct/union declarations is preserved for
  layout. Packed aggregates with unaligned fields are classified as System V
  memory-class arguments/returns, including non-packed outer aggregates that
  contain a packed member at an unaligned offset.
- Integer bit-fields use packed storage-unit layout for the covered struct/union
  cases and support read, write, compound assignment, and increment/decrement.
- Local variables live in stack slots under a 16-byte aligned stack frame, or an
  explicitly realigned local frame when required by `_Alignas`.
- Common memory builtins `__builtin_memcpy`, `__builtin_memmove`,
  `__builtin_memset`, their checked variants, and `__builtin_bzero` lower to
  the corresponding Linux libc calls.
- Common string and memory query builtins `__builtin_strlen`,
  `__builtin_strcmp`, `__builtin_strncmp`, `__builtin_strchr`,
  `__builtin_strrchr`, `__builtin_strstr`, `__builtin_memcmp`,
  `__builtin_memchr`, plus `__builtin_strcpy`, `__builtin_strcat`,
  `__builtin_strncpy`, `__builtin_strncat`, GNU `__builtin_mempcpy`,
  `__builtin_stpcpy`, `__builtin_stpncpy`, and their covered checked variants
  lower to the corresponding Linux libc calls with fortify object-size operands
  dropped.
- Fortified BSD string builtins `__builtin___strlcpy_chk` and
  `__builtin___strlcat_chk` drop the object-size argument and lower to
  `strlcpy` and `strlcat`.
- Fortified formatted-output builtins `__builtin___snprintf_chk`,
  `__builtin___vsnprintf_chk`, `__builtin___sprintf_chk`,
  `__builtin___vsprintf_chk`, `__builtin___printf_chk`,
  `__builtin___fprintf_chk`, and `__builtin___vfprintf_chk` drop the fortify
  metadata arguments and lower to the corresponding Linux libc calls.
- Common scalar hint/query builtins lower without external calls:
  `__builtin_expect`, `__builtin_expect_with_probability`,
  `__builtin_assume`, `__builtin_assume_aligned`, `__builtin_prefetch`,
  `__builtin_constant_p`, `__builtin_object_size`,
  `__builtin_dynamic_object_size`,
  `__builtin_frame_address`, `__builtin_return_address`,
  `__builtin_extract_return_addr`, `__builtin_frob_return_addr`,
  `__builtin_trap`, and `__builtin_unreachable`.
- Common signed integer absolute-value builtins lower without external calls:
  `__builtin_abs`, `__builtin_labs`, and `__builtin_llabs`.
- Common bit-manipulation builtins lower without external calls:
  `__builtin_clz*`, `__builtin_ctz*`, `__builtin_ffs*`,
  `__builtin_bswap*`, `__builtin_rotateleft*`, `__builtin_rotateright*`,
  `__builtin_popcount*`, and `__builtin_parity*`, including the covered
  unsuffixed `bswap`/`rotate` spellings.
- `__builtin_alloca` lowers to a 16-byte-aligned dynamic stack allocation that
  is released by the normal function epilogue.
- Common floating builtins lower without external calls:
  `__builtin_fabs*`, `__builtin_copysign*`, `__builtin_sqrt*`, `__builtin_nan*`,
  `__builtin_huge_val*`, `__builtin_inf*`, and ordered/unordered comparison
  predicates
  `__builtin_isgreater`, `__builtin_isgreaterequal`, `__builtin_isless`,
  `__builtin_islessequal`, `__builtin_islessgreater`, and
  `__builtin_isunordered`, plus floating classification predicates
  `__builtin_isnan*`, `__builtin_isinf*`, `__builtin_isfinite*`,
  `__builtin_isnormal*`, and `__builtin_signbit*`.
- C11 `_Generic` selections are parsed and folded to the selected association
  expression using the covered parser type model; the controlling expression is
  not emitted or evaluated.
- GNU `__builtin_choose_expr` and `__builtin_types_compatible_p` are parsed and
  folded at compile time for the covered parser type model.
- GNU `typeof`, `__typeof`, and `__typeof__` type specifiers infer expression
  or type operands in the parser. Expression operands are parsed for type only
  and are not emitted or evaluated.
- GNU `__auto_type` local declarations infer the declared type from the
  initializer for the covered scalar and pointer expression types.
- C11 `_Alignof(type)` and GNU `alignof`/`__alignof__` type or expression
  operands are folded to the covered parser type model's alignment.
- GNU `__has_attribute` reports true for semantic layout attributes that are
  implemented (`packed` and numeric `aligned`) and for parser-accepted no-op
  diagnostic, optimization, allocation, and sanitizer attributes such as
  `format`, `nonnull`, `warn_unused_result`, `noreturn`, `noinline`,
  `always_inline`, `cold`, `hot`, `malloc`, `alloc_size`, `alloc_align`, and
  `no_sanitize_*`.
- GNU `__builtin_classify_type` is folded to GCC-compatible category codes for
  covered scalar, pointer, array, string, struct, and union expressions.
- Covered integer-width atomic builtins lower without external calls:
  `__atomic_load`, `__atomic_load_n`, `__atomic_store`,
  `__atomic_store_n`, `__atomic_exchange`, `__atomic_exchange_n`,
  `__atomic_compare_exchange`, `__atomic_compare_exchange_n`,
  `__atomic_add_fetch`, `__atomic_sub_fetch`, `__atomic_and_fetch`,
  `__atomic_or_fetch`, `__atomic_xor_fetch`, `__atomic_nand_fetch`,
  `__atomic_fetch_*`, `__atomic_test_and_set`, `__atomic_clear`,
  `__atomic_thread_fence`, `__atomic_signal_fence`,
  `__atomic_always_lock_free`, `__atomic_is_lock_free`,
  `__c11_atomic_load`, `__c11_atomic_store`, `__c11_atomic_fetch_*`,
  `__c11_atomic_exchange`, `__c11_atomic_compare_exchange_strong`,
  `__c11_atomic_compare_exchange_weak`, `__c11_atomic_thread_fence`,
  `__c11_atomic_signal_fence`, `__c11_atomic_is_lock_free`, and
  `__sync_synchronize`. Lock-free query builtins currently report true for the
  covered 1-, 2-, 4-, and 8-byte scalar widths.
- Covered same-width integer overflow builtins lower without external calls:
  `__builtin_add_overflow`, `__builtin_sub_overflow`, and
  `__builtin_mul_overflow`, plus the signed/unsigned typed spellings such as
  `__builtin_sadd_overflow`, `__builtin_uadd_overflow`,
  `__builtin_ssubll_overflow`, and `__builtin_umulll_overflow`. The current
  lowering covers integer result pointer types up to 64 bits.
- `-target linux-amd64 -c` writes assembly and delegates object assembly to
  `clang -target x86_64-linux-gnu`, producing an ELF64 relocatable object when
  the local Clang supports that target.
- Compile-style modes such as `-S`, `-c`, `-E`, `-M`/`-MM`, and
  `-fsyntax-only` accept multiple C sources when kimicc can choose per-input
  outputs. Default link mode accepts one or more C source inputs, emits
  temporary assembly for each input, and delegates the final Linux/amd64 link to
  Clang.
- `--sysroot` and `-isysroot` add target-specific system include roots for
  preprocessing and are forwarded to Clang for object assembly and linking.
- Dependency flags `-M`, `-MM`, `-MD`, `-MMD`, `-MP`, `-MF`, `-MT`, and `-MQ`
  are handled by the driver using headers resolved by kimicc's preprocessor.
  Full dependency modes include system headers; `-MM` and `-MMD` keep only the
  main source and user headers. Repeated `-MT`/`-MQ` options add multiple rule
  targets, `-MF -` writes the dependency rule to stdout, and dependency-only
  `-o PATH` is treated as a dependency output path when `-MF` is absent.
  Multiple compile-style inputs emit per-input dependency sidecars when `-MF`
  is omitted; a single `-MF` path with multiple outputs is rejected.
  Multi-source link mode with `-MD`/`-MMD` emits one dependency sidecar for the
  linked output target using the union of dependencies from all compiled C
  inputs.
  Dependency and simple macro options tunneled through `-Wp,` lists or common
  `-Xpreprocessor` spellings are also recognized.

The backend currently covers a practical scalar subset: signed and unsigned
integer arithmetic/comparisons, narrow integer and `_Bool` scalar conversions
for casts/initializers/assignments/returns, unsigned 64-bit integer to
`float`/`double` conversions, covered `__int128` ABI transport and arithmetic,
direct prototype call arguments,
unnamed variadic and unprototyped default promotions, and call results,
floating-point arithmetic/comparisons, local variables,
branches, loops, direct and indirect function-pointer calls, scalar and covered
aggregate varargs, small integer-class aggregate arguments/returns, small
SSE-class and mixed-class aggregate arguments/returns including nested
struct/array fields, memory-class aggregate arguments/returns, integer
bit-fields, GNU packed aggregate layout, local aggregate initializers,
compound literals, initialized global arrays/structs/unions and covered global
bit-field storage units, global pointer/function-pointer address relocations,
`__builtin_offsetof` member designators, switch dispatch with
fallthrough/default behavior, pointers, arrays, simple globals, string
literals, covered C11 `_Generic` selections, GNU `typeof`
specifiers, GNU `__auto_type` locals, C11/GNU alignment query operators, GNU
compile-time selection builtins, GNU type-classification builtins,
parser-accepted no-op GNU attributes, and common
memory, string, bit-manipulation, dynamic stack allocation, integer atomic,
integer overflow-checking, fortified
formatted-output, and floating and scalar hint/query builtins.

## Known Gaps

This is not complete Linux C ABI compliance yet. The new backend does not yet
handle vector or x87/complex ABI classes, direct ELF object writing, or a Linux
JIT loader. Variadic support is limited to
the compiler's `__builtin_va_*` lowering and is not a complete system-header
`va_list` interoperability claim. The system-header smoke proves that common
glibc typedefs and macros from the probed Ubuntu 24.04 headers can be
preprocessed and compiled, but it is not a complete libc compatibility claim.
Integer constants also still use the parser's signed `Int64` representation, so
unsigned max-value macros such as `UINTPTR_MAX` are not a reliable basis for
`_Static_assert` comparisons yet. The existing Darwin ARM64 Mach-O object writer
and JIT remain Darwin-specific.

## Local Smoke Test On ARM64 macOS

You can still test Linux object emission locally if Clang can assemble
`x86_64-linux-gnu` objects:

```bash
cat >/tmp/kimicc_linux_smoke.c <<'C'
int add(int a, int b) { return a + b; }
int main(void) { return add(19, 23); }
C

moon run cmd/main --target native -- \
  -S -target linux-amd64 -o /tmp/kimicc_linux_smoke.s \
  /tmp/kimicc_linux_smoke.c

moon run cmd/main --target native -- \
  -c -target linux-amd64 -o /tmp/kimicc_linux_smoke.o \
  /tmp/kimicc_linux_smoke.c

file /tmp/kimicc_linux_smoke.o
```

Expected object output includes `ELF 64-bit` and `x86-64`.

## Docker Desktop Test

Docker Desktop on Apple Silicon uses a Linux VM. With
`--platform linux/amd64`, it runs an amd64 Linux userspace through emulation
inside that VM, so the smoke binary can be linked and executed as an x86-64
Linux program even though the host Mac is ARM64.

```bash
docker run --rm --platform linux/amd64 \
  -v "$PWD:/work" -w /work ubuntu:24.04 \
  bash scripts/linux-amd64-smoke.sh
```

On a non-Linux/amd64 host with Docker installed, the same script can also be
run directly; it re-execs itself in the `ubuntu:24.04` amd64 container.

The script copies the repository to a temporary directory inside the container,
installs missing tools when needed, runs the target/codegen/driver/preprocessor
tests, then exercises the built native `cmd/main` executable directly. It emits
Linux assembly, assembles an ELF object, links a Linux executable, checks that
the executable exits with code 42, and compiles an additional common
system-header probe using the container's Linux include directories, including
typedefs and macros from `stddef.h`, `stdint.h`, `stdalign.h`, `stdbool.h`,
`stdarg.h`, and `limits.h`. Before compiling that probe, it also preprocesses
the same source and checks that libc typedefs such as `uint8_t`, `uintptr_t`,
`size_t`, `ptrdiff_t`, and `va_list` survived the Clang-resource
`#include_next` chain. The script also checks that the built compiler returns a
nonzero status for an invalid Linux/amd64 translation unit, so compiler
failures are not masked by the test harness.
