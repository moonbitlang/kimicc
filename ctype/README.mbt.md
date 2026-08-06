# bobzhang/kimicc/ctype

`ctype` is kimicc's foundational, parser-neutral model of the C type system and
the compiler's built-in knowledge about constants and standard-library
builtins. It has no dependencies and is shared by every later stage —
[`@parser`](../parser), [`@mir`](../mir), and the code generators all speak in
its `Type` enum.

The package collects three kinds of facts:

1. **The C type model** — the `Type` enum plus ABI-flavored helpers
   (`size`, `align`, `is_integer`, integer promotion and common-type rules).
2. **Constant folding** — `IntegerConstant` and the integer/floating fold
   helpers that evaluate constant expressions without a parser AST.
3. **Builtin lowering tables** — pure functions that describe how
   `__builtin_*` calls map to libc symbols, argument types, and constant
   results.

Because these are all pure, parser-free functions, they can be reused by the
parser's constant folder, the MIR lowering, and direct codegen alike.

## Importing

```
import {
  "bobzhang/kimicc/ctype"
}
```

## The `Type` model

`Type` is a flat enum over C's scalar, pointer, array, function-pointer, atomic,
and aligned types, with `Struct(name)`/`Union(name)` referring to aggregate
declarations by name. The ABI helpers assume the supported native ARM64 macOS
target.

```moonbit check
///|
test "type model and ABI helpers" {
  // Scalar facts.
  inspect(@ctype.Type::SInt.size(), content="4")
  inspect(@ctype.Type::SInt.align(), content="4")
  inspect(@ctype.Type::SInt.is_integer(), content="true")
  inspect(@ctype.Type::SInt.is_signed(), content="true")
  inspect(@ctype.Type::Double.is_floating(), content="true")

  // Pointers are 8 bytes on the supported target.
  inspect(@ctype.Type::Pointer(Void).size(), content="8")

  // Signed -> unsigned mapping.
  inspect(@ctype.Type::SInt.to_unsigned() == UInt, content="true")

  // Integer promotion: char promotes to int.
  inspect(@ctype.Type::SChar.integer_promote() == SInt, content="true")
}
```

`size`/`align` abort for a bare `Struct`/`Union`, because a `Type` alone does
not carry aggregate layout — use `@mir.Program::type_size` for those.

## Integer constant folding

`IntegerConstant` pairs an `Int64` value with its C `Type`. The `integer_*`
helpers implement the usual arithmetic conversions and operator semantics,
returning `None` (rather than trapping) for cases a compiler must leave
unfolded, such as division by zero.

```moonbit check
///|
test "integer constant folding" {
  let a = @ctype.integer_constant(20L, SInt)
  let b = @ctype.integer_constant(22L, SInt)

  // 20 + 22 == 42.
  inspect(
    @ctype.integer_constant_binary_arith("+", a, b).unwrap().bits,
    content="42",
  )

  // Division by zero is left unfolded.
  let zero = @ctype.integer_constant(0L, SInt)
  inspect(@ctype.integer_constant_divide("/", a, zero) is None, content="true")

  // Casting renormalizes to the destination width: 256 -> unsigned char -> 0.
  let big = @ctype.integer_constant(256L, SInt)
  inspect(big.cast(UChar).bits, content="0")

  // Unsigned comparison: (unsigned)-1 > 0.
  let neg = @ctype.integer_constant(-1L, UInt)
  inspect(
    @ctype.integer_constant_rel_compare(
      ">",
      neg,
      @ctype.integer_constant(0L, UInt),
    ),
    content="true",
  )
}
```

## Floating constant helpers

The `floating_*` helpers fold floating arithmetic, comparisons (including the
unordered relations), and classification predicates, with careful handling of
signed zero and NaN.

```moonbit check
///|
test "floating constant helpers" {
  // copysign carries the sign of negative zero.
  inspect(
    @ctype.floating_signbit(@ctype.floating_copysign(1.0, -0.0)),
    content="true",
  )

  // Arithmetic folding.
  inspect(
    @ctype.floating_constant_binary_arith("*", 6.0, 7.0).unwrap(),
    content="42",
  )

  // Classification: 1.0/0.0 is infinite, not finite.
  let inf = 1.0 / 0.0
  inspect(
    @ctype.floating_classify("isinf", inf, Double).unwrap(),
    content="true",
  )
}
```

## Builtin lowering tables

A large family of pure functions encodes how GCC/Clang `__builtin_*` calls
lower. The `_info` helpers map a builtin name plus argument count to a
`(libc_symbol, forwarded_arg_count)` pair (or `None` when it does not apply),
and the `_arg_type` helpers give the C type of each forwarded argument.

```moonbit check
///|
test "builtin libcall tables" {
  // __builtin_memcpy(dst, src, n) lowers to memcpy forwarding 3 arguments.
  let (symbol, argc) = @ctype.builtin_memory_libcall_info("__builtin_memcpy", 3).unwrap()
  inspect(symbol, content="memcpy")
  inspect(argc, content="3")

  // Wrong argument count does not match.
  inspect(
    @ctype.builtin_memory_libcall_info("__builtin_memcpy", 2) is None,
    content="true",
  )

  // __builtin_malloc lowers to malloc.
  inspect(
    @ctype.builtin_heap_libcall_info("__builtin_malloc", 1).unwrap().0,
    content="malloc",
  )
}
```

## String-literal sizing and offset paths

Helpers such as `string_literal_array_length` (object size including the NUL)
and `string_literal_c_length` (the `strlen` result) answer compile-time
questions about string literals. The `OffsetDesignator` enum
(`OffsetField`/`OffsetIndex`) describes member-access paths used by the layout
queries in [`@mir`](../mir) to implement `__builtin_offsetof`.

```moonbit check
///|
test "string literal sizing" {
  // "abc" occupies 4 bytes (3 chars + NUL); strlen is 3.
  inspect(@ctype.string_literal_array_length("abc"), content="4")
  inspect(@ctype.string_literal_c_length("abc"), content="3")
}
```
