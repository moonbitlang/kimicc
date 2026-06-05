///|
/// Parser-neutral integer constant value used by constant-folding helpers.
///
/// `bits` carries the value in the same `Int64` two's-complement form used by
/// the parser, MIR, and direct codegen constant folders.
pub(all) struct IntegerConstant {
  bits : Int64
  ty : Type
} derive(Eq)

///|
/// Constructs an integer constant normalized to the destination C type.
pub fn integer_constant(bits : Int64, ty : Type) -> IntegerConstant {
  let core_ty = ty.core_type()
  { bits: core_ty.cast_integer_bits(bits), ty: core_ty }
}

///|
/// Builds an `int`-typed integer constant from a boolean.
///
/// `true` becomes `1` and `false` becomes `0`, both typed `SInt`, matching the
/// `int` result type of C relational and logical operators.
pub fn integer_constant_bool(value : Bool) -> IntegerConstant {
  integer_constant(if value { 1L } else { 0L }, SInt)
}

///|
/// Reinterprets this constant's value into another integer type.
///
/// The bits are re-normalized to `ty` (truncated and sign/zero-extended to the
/// destination width), modeling a C integer conversion in a constant context.
///
/// # Example
///
/// ```moonbit check
/// test {
///   // 256 cast to unsigned char wraps to 0.
///   let big = @ctype.integer_constant(256L, @ctype.Type::SInt)
///   inspect(big.cast(@ctype.Type::UChar).bits, content="0")
/// }
/// ```
pub fn IntegerConstant::cast(
  self : IntegerConstant,
  ty : Type,
) -> IntegerConstant {
  integer_constant(self.bits, ty)
}

///|
/// Applies the usual arithmetic conversions to a pair of integer constants.
///
/// Computes the common type of the two operands (`integer_common_type`), casts
/// both to it, and returns the converted operands together with that result
/// type. This is the shared promotion step every binary integer fold runs
/// first.
pub fn integer_constant_apply_binary_type(
  left : IntegerConstant,
  right : IntegerConstant,
) -> (IntegerConstant, IntegerConstant, Type) {
  let ty = integer_common_type(left.ty, right.ty)
  (left.cast(ty), right.cast(ty), ty)
}

///|
/// Folds a non-dividing binary integer operator on two constants.
///
/// Promotes the operands to their common type, then evaluates `+`, `-`, `*`,
/// `|`, `&`, or `^`, returning the result in that type. Division and remainder
/// are handled separately by `integer_constant_divide`; shifts by
/// `integer_constant_shift`. Returns `None` for any other operator.
///
/// # Example
///
/// ```moonbit check
/// test {
///   let a = @ctype.integer_constant(20L, @ctype.Type::SInt)
///   let b = @ctype.integer_constant(22L, @ctype.Type::SInt)
///   inspect(
///     @ctype.integer_constant_binary_arith("+", a, b).unwrap().bits,
///     content="42",
///   )
/// }
/// ```
pub fn integer_constant_binary_arith(
  op : String,
  left : IntegerConstant,
  right : IntegerConstant,
) -> IntegerConstant? {
  let (x, y, ty) = integer_constant_apply_binary_type(left, right)
  let bits = match op {
    "+" => x.bits + y.bits
    "-" => x.bits - y.bits
    "*" => x.bits * y.bits
    "|" => x.bits | y.bits
    "&" => x.bits & y.bits
    "^" => x.bits ^ y.bits
    _ => return None
  }
  Some(integer_constant(bits, ty))
}

///|
/// Tests two integer constants for equality after the usual conversions.
///
/// Both operands are promoted to their common type before comparing bits, so
/// values of different source types compare as C would. Sign- and
/// width-independent (`==`/`!=` give the same answer either way), so this does
/// not branch on signedness like `integer_constant_rel_compare`.
pub fn integer_constant_equal_compare(
  left : IntegerConstant,
  right : IntegerConstant,
) -> Bool {
  let (x, y, _) = integer_constant_apply_binary_type(left, right)
  x.bits == y.bits
}

///|
/// Evaluates an ordering comparison on two integer constants.
///
/// Promotes the operands to their common type and compares with `<`, `>`, `<=`,
/// or `>=`. When the common type is unsigned the bits are compared as unsigned,
/// so `(unsigned)-1 > 0` holds. Returns `false` for an unrecognized operator.
pub fn integer_constant_rel_compare(
  op : String,
  left : IntegerConstant,
  right : IntegerConstant,
) -> Bool {
  let (left, right, ty) = integer_constant_apply_binary_type(left, right)
  if ty.const_is_unsigned() {
    let x = left.bits.reinterpret_as_uint64()
    let y = right.bits.reinterpret_as_uint64()
    match op {
      "<" => x < y
      ">" => x > y
      "<=" => x <= y
      ">=" => x >= y
      _ => false
    }
  } else {
    match op {
      "<" => left.bits < right.bits
      ">" => left.bits > right.bits
      "<=" => left.bits <= right.bits
      ">=" => left.bits >= right.bits
      _ => false
    }
  }
}

///|
/// Folds integer division or remainder on two constants.
///
/// Promotes the operands to their common type and evaluates `/` or `%`, using
/// unsigned arithmetic when that type is unsigned. Returns `None` for any other
/// operator and, importantly, for division by zero, so the caller leaves the
/// expression unfolded rather than trapping at compile time.
pub fn integer_constant_divide(
  op : String,
  left : IntegerConstant,
  right : IntegerConstant,
) -> IntegerConstant? {
  let (left, right, ty) = integer_constant_apply_binary_type(left, right)
  if op != "/" && op != "%" {
    return None
  }
  if right.bits == 0L {
    return None
  }
  if ty.const_is_unsigned() {
    let x = left.bits.reinterpret_as_uint64()
    let y = right.bits.reinterpret_as_uint64()
    let result = if op == "/" { x / y } else { x % y }
    Some(integer_constant(result.reinterpret_as_int64(), ty))
  } else {
    let result = if op == "/" {
      left.bits / right.bits
    } else {
      left.bits % right.bits
    }
    Some(integer_constant(result, ty))
  }
}

///|
/// Folds a left or right shift on integer constants.
///
/// Unlike the other binary folds, a shift does not convert to a common type:
/// each operand is integer-promoted independently and the result takes the
/// promoted type of the left operand. `>>` is arithmetic for signed left
/// operands and logical for unsigned ones. Returns `None` for any operator
/// other than `<<` and `>>`.
pub fn integer_constant_shift(
  op : String,
  left : IntegerConstant,
  right : IntegerConstant,
) -> IntegerConstant? {
  let lhs_ty = left.ty.integer_promote()
  let x = left.cast(lhs_ty)
  let y = right.cast(right.ty.integer_promote())
  let shift = y.bits.to_int()
  if op == "<<" {
    Some(integer_constant(x.bits << shift, lhs_ty))
  } else if op == ">>" && lhs_ty.const_is_unsigned() {
    Some(
      integer_constant(
        (x.bits.reinterpret_as_uint64() >> shift).reinterpret_as_int64(),
        lhs_ty,
      ),
    )
  } else if op == ">>" {
    Some(integer_constant(x.bits >> shift, lhs_ty))
  } else {
    None
  }
}

///|
/// Folds a unary integer operator on a constant.
///
/// Handles arithmetic negation `-`, unary plus `+`, and bitwise complement `~`
/// (each on the integer-promoted operand type) as well as logical negation `!`
/// (yielding an `int` `0`/`1`). Returns `None` for any other operator.
pub fn integer_constant_unary(
  op : String,
  value : IntegerConstant,
) -> IntegerConstant? {
  match op {
    "-" => {
      let ty = value.ty.integer_promote()
      Some(integer_constant(-value.bits, ty))
    }
    "+" => {
      let ty = value.ty.integer_promote()
      Some(integer_constant(value.bits, ty))
    }
    "~" => {
      let ty = value.ty.integer_promote()
      Some(integer_constant(value.bits.lnot(), ty))
    }
    "!" => Some(integer_constant_bool(value.bits == 0L))
    _ => None
  }
}

///|
/// Folds a logical `&&`/`||` on two integer constants.
///
/// Each operand is treated as a truth value (nonzero is true) and the result is
/// an `int` `0`/`1`. Note this evaluates both operands; it does not model C's
/// short-circuit semantics, which is sound here because the operands are
/// already-folded constants with no side effects. Returns `None` for any other
/// operator.
pub fn integer_constant_logical(
  op : String,
  left : IntegerConstant,
  right : IntegerConstant,
) -> IntegerConstant? {
  match op {
    "&&" => Some(integer_constant_bool(left.bits != 0L && right.bits != 0L))
    "||" => Some(integer_constant_bool(left.bits != 0L || right.bits != 0L))
    _ => None
  }
}

///|
/// Parser-neutral result type for integer absolute-value builtins.
pub fn integer_abs_builtin_type(name : String) -> Type? {
  match name {
    "__builtin_abs" => Some(SInt)
    "__builtin_labs" => Some(SLong)
    "__builtin_llabs" => Some(SLongLong)
    _ => None
  }
}

///|
/// Parser-neutral operation class and bit width for integer count/query builtins.
pub fn integer_count_builtin_info(name : String) -> (String, Int)? {
  match name {
    "__builtin_clz" => Some(("clz", 32))
    "__builtin_clzl" | "__builtin_clzll" => Some(("clz", 64))
    "__builtin_ctz" => Some(("ctz", 32))
    "__builtin_ctzl" | "__builtin_ctzll" => Some(("ctz", 64))
    "__builtin_ffs" => Some(("ffs", 32))
    "__builtin_ffsl" | "__builtin_ffsll" => Some(("ffs", 64))
    "__builtin_popcount" => Some(("popcount", 32))
    "__builtin_popcountl" | "__builtin_popcountll" => Some(("popcount", 64))
    "__builtin_parity" => Some(("parity", 32))
    "__builtin_parityl" | "__builtin_parityll" => Some(("parity", 64))
    _ => None
  }
}

///|
/// Parser-neutral result type and bit width for integer byte-swap builtins.
pub fn integer_bswap_builtin_info(
  name : String,
  first_ty : Type,
) -> (Type, Int)? {
  match name {
    "__builtin_bswap16" => Some((UShort, 16))
    "__builtin_bswap32" => Some((UInt, 32))
    "__builtin_bswap64" => Some((ULongLong, 64))
    "__builtin_bswap" => {
      let ty = first_ty.core_type()
      Some((ty, ty.generic_builtin_bswap_width()))
    }
    _ => None
  }
}

///|
/// Parser-neutral result type, bit width, and direction for integer rotate builtins.
pub fn integer_rotate_builtin_info(
  name : String,
  first_ty : Type,
) -> (Type, Int, Bool)? {
  match name {
    "__builtin_rotateleft" =>
      Some(
        (first_ty.core_type(), first_ty.generic_builtin_rotate_width(), true),
      )
    "__builtin_rotateright" =>
      Some(
        (first_ty.core_type(), first_ty.generic_builtin_rotate_width(), false),
      )
    "__builtin_rotateleft32" => Some((UInt, 32, true))
    "__builtin_rotateright32" => Some((UInt, 32, false))
    "__builtin_rotateleft64" => Some((ULongLong, 64, true))
    "__builtin_rotateright64" => Some((ULongLong, 64, false))
    _ => None
  }
}

///|
/// Parser-neutral operation class and result type for integer alignment builtins.
pub fn integer_alignment_builtin_info(
  name : String,
  first_ty : Type,
) -> (String, Type)? {
  match name {
    "__builtin_is_aligned" => Some(("is_aligned", Bool))
    "__builtin_align_up" => Some(("align_up", first_ty))
    "__builtin_align_down" => Some(("align_down", first_ty))
    _ => None
  }
}

///|
fn integer_scalar_builtin_constant_needs_second_arg(name : String) -> Bool {
  match integer_alignment_builtin_info(name, UInt) {
    Some(_) => true
    None =>
      match integer_rotate_builtin_info(name, UInt) {
        Some(_) => true
        None => false
      }
  }
}

///|
/// Folds parser-neutral scalar integer builtin facts.
///
/// Callers still decide whether and how argument expressions are constant; this
/// helper only applies the shared builtin result rules to already-folded values.
pub fn integer_scalar_builtin_constant(
  name : String,
  arg0 : IntegerConstant?,
  arg1 : IntegerConstant?,
  first_ty : Type,
) -> IntegerConstant? {
  if name == "__builtin_flt_rounds" {
    return match arg0 {
      None => Some(integer_constant(1L, SInt))
      Some(_) => None
    }
  }
  match integer_abs_builtin_type(name) {
    Some(ty) =>
      return match arg0 {
        Some(arg) => {
          let value = arg.cast(ty).bits
          Some(integer_constant(if value < 0L { -value } else { value }, ty))
        }
        None => None
      }
    None => ()
  }
  match integer_alignment_builtin_info(name, first_ty) {
    Some((kind, result_ty)) =>
      return match (arg0, arg1) {
        (Some(value), Some(align)) =>
          if align.bits > 0L {
            match kind {
              "is_aligned" =>
                Some(
                  integer_constant_bool((value.bits & (align.bits - 1L)) == 0L),
                )
              "align_up" | "align_down" => {
                let adjusted = if kind == "align_up" {
                  value.bits + align.bits - 1L
                } else {
                  value.bits
                }
                Some(integer_constant(adjusted & -align.bits, result_ty))
              }
              _ => None
            }
          } else {
            None
          }
        _ => None
      }
    None => ()
  }
  match integer_count_builtin_info(name) {
    Some((kind, width)) =>
      return match arg0 {
        Some(arg) =>
          match kind {
            "clz" =>
              if mask_int_width(arg.bits, width) == 0L {
                None
              } else {
                Some(
                  integer_constant(
                    count_leading_zero_bits(arg.bits, width),
                    SInt,
                  ),
                )
              }
            "ctz" =>
              if mask_int_width(arg.bits, width) == 0L {
                None
              } else {
                Some(
                  integer_constant(
                    count_trailing_zero_bits(arg.bits, width),
                    SInt,
                  ),
                )
              }
            "ffs" =>
              Some(integer_constant(first_set_bit(arg.bits, width), SInt))
            "popcount" =>
              Some(integer_constant(count_one_bits(arg.bits, width), SInt))
            "parity" =>
              Some(integer_constant(count_one_bits(arg.bits, width) & 1L, SInt))
            _ => None
          }
        None => None
      }
    None => ()
  }
  match integer_bswap_builtin_info(name, first_ty) {
    Some((ty, width)) =>
      return match arg0 {
        Some(arg) => Some(integer_constant(byte_swap_bits(arg.bits, width), ty))
        None => None
      }
    None => ()
  }
  match integer_rotate_builtin_info(name, first_ty) {
    Some((ty, width, left)) =>
      return match (arg0, arg1) {
        (Some(value), Some(shift)) =>
          Some(
            integer_constant(
              rotate_bits(value.bits, shift.bits, width, left),
              ty,
            ),
          )
        _ => None
      }
    None => None
  }
}

///|
/// Applies scalar integer builtin folding to already-folded source operands.
///
/// `arg_count` is the number of source operands at the call site. It lets this
/// helper distinguish absent operands from present but non-foldable operands.
pub fn integer_scalar_builtin_constant_from_folded_args(
  name : String,
  arg_count : Int,
  arg0 : IntegerConstant?,
  arg1 : IntegerConstant?,
  first_ty : Type,
) -> IntegerConstant? {
  if arg_count > 0 && arg0 is None {
    return None
  }
  if arg_count > 1 &&
    integer_scalar_builtin_constant_needs_second_arg(name) &&
    arg1 is None {
    return None
  }
  integer_scalar_builtin_constant(name, arg0, arg1, first_ty)
}
