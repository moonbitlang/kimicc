# Linux/amd64 Target

`linux-amd64` is an experimental second output target. It is intended to make
the target split real and testable without claiming full C ABI coverage yet.

## What Works

- `-target linux-amd64 -S` emits GNU assembler syntax with Intel operands.
  Common x86-64 Linux target spellings such as `linux/amd64`,
  `x86_64-linux-gnu`, `x86_64-pc-linux-gnu`, and
  `x86_64-unknown-linux-musl` are accepted and normalized to the same backend.
- External C symbols use ELF spelling, so `main` is emitted as `main`, not
  `_main`.
- The preprocessor seeds Linux/x86-64 target macros such as `__linux__`,
  `__gnu_linux__`, `__ELF__`, `__x86_64__`, `__amd64__`, `_LP64`, basic
  `__SIZEOF_*`/type/width/max-value/alignment macros, Clang/GCC compatibility
  version and literal-encoding macros, floating-point limit macros used by
  Clang's `<float.h>`, endian and floating-word-order constants, atomic
  memory-order constants, x86-64 small-code-model and GCC ABI identity macros,
  ELF empty label/register prefix macros, `__CHAR16_TYPE__`/`__CHAR32_TYPE__`,
  and the stdint/inttypes suffix and format helper macros used by libc headers.
  Linux header compatibility macros such as `__NO_MATH_INLINES` and the
  supported `__GCC_HAVE_SYNC_COMPARE_AND_SWAP_*` widths are also seeded, along
  with Clang's numeric floating-class, memory-scope, and cache-line interference
  constants.
  `__has_builtin(name)` reports true for the
  builtin functions and atomic intrinsics the Linux/amd64 lowering currently
  supports, and false for unsupported builtin names. `__has_attribute(name)`
  reports true for GNU `packed`/`__packed__`, numeric
  `aligned`/`__aligned__`, `weak`/`__weak__`, and Linux/amd64
  `alias`/`__alias__`, `section`/`__section__`, and
  `constructor`/`__constructor__`, `destructor`/`__destructor__`, and
  `visibility`/`__visibility__` attributes, matching the layout,
  symbol-binding, and lifecycle attributes the parser and backend currently
  honor, plus parser-accepted no-op GNU
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
  recorded parameter types, and calls to undeclared external names, also use
  default promotions for supplied arguments. Undeclared external calls are
  emitted as direct symbol calls, not as loads through the symbol address.
  `va_arg` supports scalar values plus the covered small and memory-class
  aggregate subset, including packed memory-class aggregates read from the
  overflow stack.
- Small scalar-field `struct`/`union` arguments and returns up to 16 bytes are
  recursively classified by eightbyte as integer or SSE, including nested
  structs/unions and arrays of supported scalar fields. Covered integer, pure
  SSE, and mixed integer/SSE aggregates use `rax`/`rdx`, `xmm0`/`xmm1`, `rdi`
  through `r9`, `xmm0` through `xmm7`, or the overflow stack area as required by
  the covered System V aggregate subset. Partial final eightbytes are loaded
  and stored at their actual object width when moving between memory, ABI
  registers, overflow-stack aggregate slots, and `va_arg` register-save scratch
  storage.
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
- Global floating and integer scalar constant initializers are folded through
  the source expression's C type before conversion to the destination object
  type, preserving integer subexpression semantics such as `1 / 2` and
  explicit or implicit floating-to-integer initializer conversions. Integer
  constant folding uses the covered usual arithmetic conversions, including
  unsigned division, modulo, right shifts, and relational comparisons.
- Initialized global arrays, structs, and unions are emitted with layout
  padding and designated-initializer holes for the covered aggregate cases,
  including mixed nested field/index designators, bit-field storage units that
  do not overlap earlier streamed scalar fields, and pointer/function-pointer
  relocations to globals, functions, and aggregate subobjects. Pointer
  arithmetic in global relocations is scaled by the effective pointer type,
  including casted pointer bases and address-of casted pointer subscripts.
- `__builtin_offsetof` folds simple, nested, and constant array-index member
  designators using the covered aggregate layout model.
- `_Alignas` and numeric GNU `__attribute__((aligned(N)))`/`__aligned__(N)`
  are honored for x86-64 struct/union layout, ELF global alignment, and stack
  locals, including hidden aggregate return and `va_arg` scratch storage.
  Stack-passed `__int128` and over-aligned aggregate call arguments are padded
  to their required overflow-argument alignment for calls, parameter loads, and
  variadic overflow reads. Functions with locals requiring more than 16-byte
  alignment keep `rbp` as the incoming frame anchor and use an aligned
  local-frame base, preserving the callee-saved register used for that base
  before returning.
- GNU `__attribute__((mode(...)))` is honored for common scalar modes used by
  Linux headers, including `QI`, `HI`, `SI`, `DI`, `TI`, `word`, and
  `unwind_word`. This keeps ABI typedefs such as `register_t` and
  `fpu_control_t` at their Linux x86-64 widths instead of silently falling back
  to the spelling's nominal base type.
- GNU `__attribute__((packed))` on struct/union declarations is preserved for
  layout. Packed aggregates with unaligned fields are classified as System V
  memory-class arguments/returns, including non-packed outer aggregates that
  contain a packed member at an unaligned offset.
- GNU `__attribute__((weak))`/`__weak__` on Linux/amd64 function and global
  declarations or definitions emits ELF weak symbol bindings. Addresses of
  external function/global declarations are loaded through GOT relocations so
  undefined weak references remain PIE-linkable.
- GNU `__attribute__((alias("target")))`/`__alias__` on Linux/amd64 function
  and global declarations emits ELF symbol aliases with `.set`.
- GNU `__attribute__((section("name")))`/`__section__` on Linux/amd64 function
  and global declarations or definitions emits those symbols into the requested
  ELF section.
- GNU `__attribute__((constructor))` and `__attribute__((destructor))` on
  Linux/amd64 function definitions emit `.init_array` and `.fini_array`
  entries.
- GNU `__attribute__((visibility("hidden")))`,
  `visibility("protected")`, and `visibility("internal")` on Linux/amd64
  function and global declarations or definitions emit the corresponding ELF
  symbol visibility directives.
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
  `__builtin_unpredictable`, `__builtin_assume`,
  `__builtin_assume_aligned`, `__builtin_prefetch`, `__builtin_constant_p`,
  `__builtin_object_size`, `__builtin_is_aligned`, `__builtin_align_up`,
  `__builtin_align_down`,
  `__builtin_dynamic_object_size`,
  `__builtin_flt_rounds`,
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
  operands are folded to the covered parser type model's alignment. Linux
  `long double` layout constants use the SysV x86-64 size/alignment of 16
  bytes, and storage layout honors that size/alignment even though x87 value
  lowering is still unsupported. `_Float16` layout constants use the target
  size/alignment of 2 bytes, and Linux/amd64 can size zero-initialized storage
  for that placeholder type while still rejecting value lowering.
- glibc binary extended floating spellings used by headers are parsed as their
  covered ABI peers where that is correct for the current type model:
  `_Float32` as `float`, `_Float64` and `_Float32x` as `double`, and
  `_Float64x` as the existing SysV `long double` placeholder. Decimal/vendor
  spellings such as `_Decimal32`, `_Decimal64`, `_Decimal128`, `__bf16`, and
  `__ibm128` are rejected explicitly instead of being treated as identifiers.
- GNU `__has_attribute` reports true for semantic layout/type attributes that
  are implemented (`packed`, numeric `aligned`, common scalar `mode`, and
  `weak`) and for parser-accepted no-op
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
  `__sync_synchronize`, plus legacy `__sync_*` compare-and-swap,
  read-modify-write, signed/unsigned min/max, swap, and lock test/release
  builtins. Lock-free query
  builtins currently report true for the covered 1-, 2-, 4-, and 8-byte scalar
  widths.
- Covered same-width integer overflow builtins lower without external calls:
  `__builtin_add_overflow`, `__builtin_sub_overflow`, and
  `__builtin_mul_overflow`, plus the signed/unsigned typed spellings such as
  `__builtin_sadd_overflow`, `__builtin_uadd_overflow`,
  `__builtin_ssubll_overflow`, and `__builtin_umulll_overflow`. The current
  lowering covers integer result pointer types up to 64 bits.
- `-target linux-amd64 -c` writes assembly and delegates object assembly to
  `clang -target x86_64-linux-gnu`, producing an ELF64 relocatable object when
  the local Clang supports that target. Compile-only assembly inputs, including
  extensionless inputs selected with `-x assembler`, are delegated to Clang,
  with multiple assembly inputs accepted when kimicc can choose per-input
  outputs.
- Compile-style modes such as `-S`, `-c`, `-E`, `-M`/`-MM`, and
  `-fsyntax-only` accept multiple C sources when kimicc can choose per-input
  outputs. A lone `-` is treated as stdin for the primary C input, which keeps
  probes such as `cc -E -dM -` usable. Default link mode accepts one or more C
  source inputs, emits temporary assembly for each input, and delegates the
  final Linux/amd64 link to Clang. Common linker options such as `-L`, `-l`,
  `-Wl,`, `-Xlinker`,
  `-rpath PATH`, and `-e SYMBOL` are preserved for that delegated link step.
  `-pthread` is also preserved for link delegation and seeds `_REENTRANT=1`
  before preprocessing, matching the build-system contract projects expect from
  Clang/GCC-style drivers. Linux/amd64 preprocessing seeds the default
  `__PIC__`, `__pic__`, `__PIE__`, and `__pie__` value `2`, matching Clang's
  default PIE driver contract for this target. PIC and PIE driver flags then
  update that contract in command-line order: `-fpic`/`-fpie` define value `1`,
  `-fPIC`/`-fPIE` define value `2`, and the `-fno-*` variants clear the PIC/PIE
  macros. `-ffreestanding` and `-fhosted` select the
  predefined `__STDC_HOSTED__` value before user `-D`/`-U` macro overrides.
  Common `-std=`/`--std=` values and `-ansi` update `__STDC_VERSION__` and
  `__STRICT_ANSI__` for preprocessing probes, without enforcing a separate
  parser dialect. Common `-O*` optimization spellings update the matching
  optimization predefined macros such as `__NO_INLINE__`, `__OPTIMIZE__`,
  `__OPTIMIZE_SIZE__`, and `__FAST_MATH__`; explicit `-ffast-math` and
  `-fno-fast-math` update the fast-math macros in command-line order. This is
  a preprocessor contract, not a separate optimization pipeline. `-dM -E`
  dumps the final macro table after processing command-line definitions,
  forced includes, source definitions, and undefinitions. `-undef` keeps the
  standard predefined macro baseline while suppressing target and driver-owned
  predefined macros; user `-D`/`-U` operations still apply.
- `--sysroot` and `-isysroot` add target-specific system include roots for
  preprocessing and are forwarded to Clang for object assembly and linking.
  Toolchain discovery options such as `--gcc-toolchain=PATH` and
  `--gcc-install-dir=PATH`, plus `-B PREFIX`, are forwarded to Clang; separated
  GCC-toolchain spellings are normalized to the joined form accepted by Clang.
  User include path spellings include `-I`, `--include-directory`,
  `-isystem`, `--isystem`, `-isystem-after`, `-iquote`, and `-idirafter`.
  The `-isystem-after` and `-idirafter` paths are searched after the configured
  target system directories. `-iprefix` is applied to later
  `-iwithprefixbefore` user include paths and `-iwithprefix` system include
  paths. `-imacros FILE` processes macro definitions from a file before forced
  includes while discarding ordinary output from that macro file.
  `-fmacro-prefix-map=OLD=NEW` and `-ffile-prefix-map=OLD=NEW` remap the
  physical source path used by `__FILE__`; the longest matching prefix wins,
  and logical filenames introduced by `#line` are left as written.
  `__BASE_FILE__` expands to the remapped main translation-unit filename, and
  `__FILE_NAME__` expands to the basename of the current logical or physical
  filename without applying prefix maps. `__INCLUDE_LEVEL__` expands to the
  current include nesting depth.
- Dependency flags `-M`, `-MM`, `-MD`, `-MMD`, `-MP`, `-MF`, `-MG`, `-MT`, and `-MQ`
  are handled by the driver using headers resolved by kimicc's preprocessor.
  Full dependency modes include system headers; `-MM` and `-MMD` keep only the
  main source and user headers. In dependency-only `-M`/`-MM` modes, `-MG`
  records missing include names as generated dependencies instead of failing.
  Repeated `-MT`/`-MQ` options add multiple rule targets, `-MF -` writes the
  dependency rule to stdout, Clang's
  `-dependency-file PATH` is accepted as a depfile destination alias, and
  dependency-only `-o PATH` is treated as a dependency output path when `-MF`
  is absent.
  Multiple compile-style inputs emit per-input dependency sidecars when `-MF`
  is omitted; a single `-MF` path with multiple outputs is rejected.
  Multi-source link mode with `-MD`/`-MMD` emits one dependency sidecar for the
  linked output target using the union of dependencies from all compiled C
  inputs.
  Dependency, include, forced-include, and simple macro options tunneled
  through `-Wp,` lists or common `-Xpreprocessor` spellings are also
  recognized. Diagnostic metadata and driver path options such as `-MJ PATH`,
  `-serialize-diagnostics PATH`, `--config PATH`, `-dumpdir PATH`, and
  `-dumpbase PATH` are accepted and ignored.
- GCC-style configure queries include `-dumpmachine`, `-print-target-triple`,
  `-print-sysroot`, `-print-multiarch`, `-print-multi-directory`,
  `-print-multi-os-directory`, `-print-multi-lib`,
  `-print-libgcc-file-name`, `-print-prog-name=NAME`, and
  `-print-file-name=NAME`, with long `--print-*` spellings accepted for the
  corresponding driver-owned queries. `-print-sysroot-headers-suffix` is
  recognized and exits nonzero because kimicc does not configure a sysroot
  headers suffix. The short `-v` verbose flag is accepted without replacing
  compilation; `--version` remains the version-only query.

The backend currently covers a practical scalar subset: signed and unsigned
integer arithmetic/comparisons, narrow integer and `_Bool` scalar conversions
for casts/initializers/assignments/returns, unsigned 64-bit integer to
`float`/`double` conversions, `float`/`double` to unsigned 64-bit integer
conversions, covered `__int128` ABI transport and arithmetic,
direct prototype call arguments,
typed function-pointer scalar call arguments,
unnamed variadic and unprototyped default promotions, direct calls to
undeclared external names, and call results,
floating-point arithmetic/comparisons, `float`/`double` compound assignments
and prefix/postfix increment/decrement, mixed integer/floating compound
assignments for non-`__int128` integer lvalues, mixed scalar ternary conversions,
local variables,
branches, loops, direct and indirect function-pointer calls, scalar and covered
aggregate varargs, small integer-class aggregate arguments/returns, small
SSE-class and mixed-class aggregate arguments/returns including nested
struct/array fields, memory-class aggregate arguments/returns, integer
bit-fields including promoted integer compound assignments and mixed floating
compound assignments, GNU packed aggregate layout, local aggregate initializers,
compound literals, initialized global arrays/structs/unions and covered global
bit-field storage units, global pointer/function-pointer address relocations,
`__builtin_offsetof` member designators, switch dispatch with
fallthrough/default behavior, scaled pointer arithmetic including pointer
compound assignments, GNU byte-sized `void *` arithmetic, pointers, arrays,
simple globals, string literals, covered C11 `_Generic` selections, GNU `typeof`
specifiers, GNU `__auto_type` locals, C11/GNU alignment query operators, GNU
compile-time selection builtins, GNU type-classification builtins,
parser-accepted no-op GNU attributes, and common
memory, string, bit-manipulation, dynamic stack allocation, integer atomic,
integer overflow-checking, fortified
formatted-output, and floating and scalar hint/query builtins.

## Register Allocation Model

The Linux/amd64 backend does not run a general-purpose register allocator. It
uses a fixed expression-lowering discipline:

- Scalar integer and pointer expression results are produced in `rax`.
- `float` and `double` expression results are produced in `xmm0`.
- `__int128` expression results use `rdx:rax`.
- Address-producing paths use `rax`, with aggregate-copy helpers using `r10`
  as the destination address and `r11` as the source address.
- Calls first evaluate arguments into a temporary stack area, then marshal those
  values into the System V argument registers or overflow stack slots. This
  keeps nested calls from clobbering already-evaluated arguments without needing
  live-range analysis.
- The backend treats normal scratch registers as caller-saved around calls. It
  only preserves callee-saved state that it explicitly uses, currently `r13`
  when a function needs a separate over-aligned local-frame base.
- Local C objects live in stack slots. The backend reloads from those slots
  rather than trying to keep variables resident in machine registers.

That fixed strategy is simple and slower than a real allocator, but it can still
emit ABI-correct code for the documented subset because ABI registers are chosen
at call/return boundaries, stack alignment is maintained there, and
callee-saved registers used by the backend are restored before return.

## Known Gaps

This is not complete Linux C ABI compliance yet. The new backend does not yet
handle vector or x87/complex ABI classes, direct ELF object writing, or a Linux
JIT loader. Variadic support is limited to
the compiler's `__builtin_va_*` lowering and is not a complete system-header
`va_list` interoperability claim. The system-header smoke proves that common
glibc typedefs and macros from the probed Ubuntu 24.04 headers can be
preprocessed and compiled, but it is not a complete libc compatibility claim.
The existing Darwin ARM64 Mach-O object writer and JIT remain Darwin-specific.
GNU/Clang vector type attributes such as `vector_size` and `ext_vector_type` are
rejected explicitly instead of being skipped as no-op attributes.

The Linux/amd64 preprocessor also intentionally does not seed Clang macros that
would advertise unsupported frontend or backend features. Current examples are
`__BITINT_MAXWIDTH__`, `_Float16`/`__float128` limit and size macros,
SSE/MMX/FXSR CPU feature macros, segment address-space macros such as
`__SEG_FS` and `__seg_fs`, LLVM identity macros, Objective-C/CFString macros,
C23 `#embed` result macros, and inline-assembly capability macros such as
`__GCC_ASM_FLAG_OUTPUTS__` and `__GCC_HAVE_DWARF2_CFI_ASM`.
Unsupported extension type spellings such as `_Float16` and `__float128`, and
unsupported ABI types such as SysV x86-64 `long double` and `_Float64x`, are
parsed as distinct types so external declarations in system headers do not
silently become `int` or `double`; code generation still fails if such a type
needs value operations or ABI lowering. `_Float16` has layout-only support for
`sizeof`, `alignof`, and zero storage on Linux/amd64, not arithmetic or ABI
transport. Unsupported decimal/vendor floating spellings are rejected
explicitly.

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

For repeated local runs, build `kimicc-linux-amd64-smoke:ubuntu24.04` once with
`scripts/build-linux-amd64-smoke-image.sh`; the smoke script automatically uses
that image when it exists locally. Alternatively, set
`KIMICC_LINUX_AMD64_SMOKE_BUILD_IMAGE=1` to build that image automatically if it
is missing. Set `KIMICC_LINUX_AMD64_SMOKE_IMAGE` to use a different image tag.
On a Linux/amd64 host, set
`KIMICC_LINUX_AMD64_SMOKE_FORCE_DOCKER=1` to force the Docker path, which is how
CI validates the cached image workflow.

The script copies the repository to a temporary directory inside the container,
installs missing tools when needed, runs the target/codegen/driver/preprocessor
tests, then exercises the built native `cmd/main` executable directly. It emits
Linux assembly, assembles an ELF object, links a Linux executable, checks that
the executable exits with code 42, and compiles an additional common
system-header probe using the container's Linux include directories, including
typedefs and macros from `stddef.h`, `stdint.h`, `stdalign.h`, `stdbool.h`,
`stdarg.h`, `stdio.h`, `stdlib.h`, `string.h`, `unistd.h`, `errno.h`,
`fcntl.h`, `time.h`, `sys/types.h`, `sys/stat.h`, `sys/socket.h`, `sys/uio.h`,
`poll.h`, `signal.h`, `fpu_control.h`, `limits.h`, and `float.h`. Before
compiling that probe, it also preprocesses the same source and checks that
libc typedefs such as `uint8_t`, `uintptr_t`, `size_t`, `ptrdiff_t`, and
`va_list` survived the Clang-resource `#include_next` chain. The compiled probe
also checks representative unsigned max-value macros such as `UINTPTR_MAX` and
`SIZE_MAX`, common Linux macros such as `EINVAL`, `STDOUT_FILENO`, `F_GETFL`,
`AF_INET`, `POLLIN`, and `SIGTERM`, and representative complete system types
such as `struct stat`, `struct iovec`, and `struct pollfd` in `_Static_assert`
expressions. It also runs a syntax-only probe over a broader set of common
libc/POSIX headers such as `arpa/inet.h`, `assert.h`, `ctype.h`, `dirent.h`,
`fnmatch.h`, `glob.h`, `grp.h`, `inttypes.h`, `limits.h`, `locale.h`, `math.h`,
`netdb.h`, `netinet/in.h`, `pthread.h`, `pwd.h`, `regex.h`, `setjmp.h`,
`wchar.h`, `sys/epoll.h`, `sys/eventfd.h`, `sys/ioctl.h`, `sys/inotify.h`,
`sys/mman.h`, `sys/random.h`, `sys/resource.h`, `sys/select.h`,
`sys/sendfile.h`, `sys/statvfs.h`, `sys/syscall.h`, `sys/timerfd.h`,
`sys/times.h`, `sys/time.h`, `sys/utsname.h`, `sys/uio.h`, and `sys/wait.h`. A
separate linked probe passes the generated `va_list` state to glibc `vsnprintf`,
covering a real libc v-function smoke without claiming complete `va_list`
interoperability. Another linked libc runtime probe covers ordinary calls
through glibc declarations such as `strtol`, `isdigit`, `tolower`, `snprintf`,
`strerror`, `sqrt`, `setjmp`, `longjmp`, `setlocale`, `mbstowcs`, `wcstombs`,
`wcslen`, `btowc`, and `wctob`, plus `qsort`, `bsearch`, `signal`, `raise`,
`atexit`, `setenv`, `getenv`, and `unsetenv`; the `qsort`, `bsearch`, `signal`,
and `atexit` cases check glibc callbacks into kimicc-generated function
pointers. The same libc probe also calls `strlen` through a
kimicc-generated function pointer loaded from the external glibc declaration. A
pthread probe links with `-pthread`, starts a `pthread_create`
callback, joins it, and checks pointer/result transport through the libc thread
API. The main linked smoke source also checks that a hidden-visibility GNU
attribute, GNU function/global aliases, and GNU function/global sections are
reflected in emitted Linux/amd64 assembly. A POSIX runtime probe covers
`mkstemp`, `write`, `lseek`, `read`, `pread`, `pwrite`, `fstat`, `stat`,
`access`, `truncate`, `ftruncate`, `fsync`, `dup`, `fcntl`, `link`, `symlink`,
`readlink`, `rename`, `chmod`, `mkdir`, `mkdtemp`, `mkfifo`, `rmdir`, `lstat`,
`getcwd`, `chdir`, `utimes`, `utimensat`, `sysconf`, `pathconf`, `confstr`,
`clock_gettime`, `gettimeofday`, `time`, `uname`, `gethostname`, `getrusage`,
`getrlimit`, `umask`, `times`, `opendir`, `readdir`, `closedir`, `mmap`,
`munmap`, `pipe`, `poll`, `select`, `ioctl`, `readv`, `writev`, `sendfile`,
`socketpair`, `socket`, `setsockopt`, `bind`, `getsockname`, `inet_pton`,
`inet_ntop`, `getaddrinfo`, `freeaddrinfo`, `fnmatch`, `regcomp`, `regexec`,
`regfree`, `glob`, `globfree`, `getpwuid`, `getgrgid`, `statvfs`, `eventfd`,
`epoll_create1`, `epoll_ctl`, `epoll_wait`, `timerfd_create`, `inotify_init1`,
`syscall`, `getrandom`, `fork`, `_exit`, `execlp`, `waitpid`, `getpid`, `close`,
and `unlink` through the Ubuntu glibc declarations. A separate linked probe
checks that GNU constructor and
destructor functions run through `.init_array`/`.fini_array`. The
script also checks that a strong clang-built
function or global definition overrides a kimicc-built ELF weak definition at
link time, and that undefined weak function/global references link and resolve
to null in the generated PIE binary. It also
checks that the built compiler returns a nonzero status for an invalid
Linux/amd64 translation unit, so compiler failures are not masked by the test
harness.
