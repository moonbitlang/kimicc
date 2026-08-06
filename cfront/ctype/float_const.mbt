///|
/// Floating absolute value used by constant and modeled-runtime helpers.
///
/// This intentionally preserves the historical helper behavior for negative
/// zero: `-0.0` is returned unchanged because `-0.0 < 0.0` is false.
pub fn floating_abs(value : Double) -> Double {
  if value < 0.0 {
    -value
  } else {
    value
  }
}

///|
/// Returns the IEEE sign bit of a floating value.
///
/// This is true for negative numbers and, crucially, for negative zero, which a
/// plain `value < 0.0` test would miss. It models C's `signbit`.
pub fn floating_signbit(value : Double) -> Bool {
  let neg_inf = -(1.0 / 0.0)
  value < 0.0 || (value == 0.0 && 1.0 / value == neg_inf)
}

///|
/// Composes a value from the magnitude of one operand and the sign of another.
///
/// The result has `floating_abs(magnitude)` as its magnitude and takes its sign
/// from `floating_signbit(sign)`. This is the constant-folding approximation of
/// C's `copysign` and matches it for ordinary values, but note it inherits
/// `floating_abs`'s historical handling of `-0.0`: because `floating_abs`
/// returns `-0.0` unchanged, `copysign(-0.0, +x)` yields `-0.0` rather than the
/// `+0.0` true `copysign` would produce.
pub fn floating_copysign(magnitude : Double, sign : Double) -> Double {
  let value = floating_abs(magnitude)
  if floating_signbit(sign) {
    -value
  } else {
    value
  }
}

///|
/// Folds a binary floating arithmetic operator on two constant operands.
///
/// `op` is a source-level operator string. Returns `Some(result)` for `+`, `-`,
/// `*`, and `/`, and `None` for any operator this folder does not handle.
pub fn floating_constant_binary_arith(
  op : String,
  left : Double,
  right : Double,
) -> Double? {
  match op {
    "+" => Some(left + right)
    "-" => Some(left - right)
    "*" => Some(left * right)
    "/" => Some(left / right)
    _ => None
  }
}

///|
/// Folds a unary floating operator on a constant operand.
///
/// Returns `Some(value)` for unary `+`, `Some(-value)` for unary `-`, and
/// `None` for any other operator.
pub fn floating_constant_unary(op : String, value : Double) -> Double? {
  match op {
    "-" => Some(-value)
    "+" => Some(value)
    _ => None
  }
}

///|
/// Converts a stored integer constant value to its double value.
///
/// Constant evaluation keeps integers as `Int64`; this performs the numeric
/// `Int64 -> Double` conversion (not an IEEE bit reinterpretation) used when an
/// integer constant participates in floating arithmetic.
pub fn floating_constant_from_integer_bits(bits : Int64) -> Double {
  bits.to_double()
}

///|
/// Converts a double constant to the integer value used by constant evaluation.
///
/// This truncates toward zero through `Int`, mirroring C's float-to-integer
/// conversion for the constant folder (not an IEEE bit reinterpretation).
pub fn floating_constant_to_integer_bits(value : Double) -> Int64 {
  value.to_int().to_int64()
}

///|
/// Builds an integer constant of type `ty` from a double constant value.
///
/// Truncates `value` toward zero (via `floating_constant_to_integer_bits`) and
/// wraps the result as an `IntegerConstant` of the requested type, used when a
/// floating constant is cast or assigned to an integer in a constant context.
pub fn integer_constant_from_floating(
  value : Double,
  ty : Type,
) -> IntegerConstant {
  integer_constant(floating_constant_to_integer_bits(value), ty)
}

///|
/// Number of arguments a constant-foldable floating builtin expects.
///
/// Recognizes the `fabs`/`sqrt`/`copysign` math builtins and the
/// `nan`/`inf`/`huge_val` constant builtins (across their `f`/`l` suffixes),
/// returning their arity (`0`, `1`, or `2`). Returns `None` for names this
/// folder does not model. It gates `floating_builtin_constant_from_folded_args`.
pub fn floating_builtin_constant_arg_count(name : String) -> Int? {
  match name {
    "__builtin_fabs"
    | "__builtin_fabsf"
    | "__builtin_fabsl"
    | "__builtin_sqrt"
    | "__builtin_sqrtf"
    | "__builtin_sqrtl" => Some(1)
    "__builtin_copysign" | "__builtin_copysignf" | "__builtin_copysignl" =>
      Some(2)
    "__builtin_nan"
    | "__builtin_nanf"
    | "__builtin_nanl"
    | "__builtin_huge_val"
    | "__builtin_huge_valf"
    | "__builtin_huge_vall"
    | "__builtin_inf"
    | "__builtin_inff"
    | "__builtin_infl" => Some(0)
    _ => None
  }
}

///|
/// Evaluates a constant-foldable floating builtin to a double.
///
/// Implements the constant results of `__builtin_fabs`, `__builtin_copysign`,
/// `__builtin_sqrt`, and the `nan`/`inf`/`huge_val` families (with their
/// `f`/`l` suffixes). `arg0`/`arg1` supply the operands a given builtin needs;
/// returns `None` when the name is unmodeled or a required operand is missing.
/// Prefer `floating_builtin_constant_from_folded_args`, which checks arity
/// first.
pub fn floating_builtin_constant(
  name : String,
  arg0 : Double?,
  arg1 : Double?,
) -> Double? {
  match name {
    "__builtin_fabs" | "__builtin_fabsf" | "__builtin_fabsl" =>
      match arg0 {
        Some(value) => Some(floating_abs(value))
        None => None
      }
    "__builtin_copysign" | "__builtin_copysignf" | "__builtin_copysignl" =>
      match (arg0, arg1) {
        (Some(magnitude), Some(sign)) =>
          Some(floating_copysign(magnitude, sign))
        _ => None
      }
    "__builtin_sqrt" | "__builtin_sqrtf" | "__builtin_sqrtl" =>
      match arg0 {
        Some(value) => Some(value.sqrt())
        None => None
      }
    "__builtin_nan" | "__builtin_nanf" | "__builtin_nanl" => Some(0.0 / 0.0)
    "__builtin_huge_val"
    | "__builtin_huge_valf"
    | "__builtin_huge_vall"
    | "__builtin_inf"
    | "__builtin_inff"
    | "__builtin_infl" => Some(1.0 / 0.0)
    _ => None
  }
}

///|
/// Applies floating builtin arity and result rules to already-folded operands.
pub fn floating_builtin_constant_from_folded_args(
  name : String,
  arg0 : Double?,
  arg1 : Double?,
) -> Double? {
  match floating_builtin_constant_arg_count(name) {
    Some(0) => floating_builtin_constant(name, None, None)
    Some(1) =>
      match arg0 {
        Some(value) => floating_builtin_constant(name, Some(value), None)
        None => None
      }
    Some(2) =>
      match (arg0, arg1) {
        (Some(left), Some(right)) =>
          floating_builtin_constant(name, Some(left), Some(right))
        _ => None
      }
    _ => None
  }
}

///|
/// Canonical result bits and execution type for immediate floating constants.
///
/// Long-double variants currently share the double representation used by the
/// MIR and direct assembly backends.
pub fn floating_builtin_constant_bits_info(name : String) -> (Int64, Type)? {
  match name {
    "__builtin_nanf" => Some((2143289344L, Float))
    "__builtin_nan" | "__builtin_nanl" => Some((9221120237041090560L, Double))
    "__builtin_huge_valf" | "__builtin_inff" => Some((2139095040L, Float))
    "__builtin_huge_val"
    | "__builtin_huge_vall"
    | "__builtin_inf"
    | "__builtin_infl" => Some((9218868437227405312L, Double))
    _ => None
  }
}

///|
fn floating_normal_min(ty : Type) -> Double {
  match ty.core_type() {
    Float => 1.1754943508222875e-38
    _ => 2.2250738585072014e-308
  }
}

///|
/// Evaluates a floating classification predicate on a constant value.
///
/// `kind` is one of `"isnan"`, `"isinf"`, `"isfinite"`, `"isnormal"`, or
/// `"signbit"`. `ty` selects the smallest-normal threshold for `"isnormal"`
/// (`Float` vs wider). Returns `Some(result)` for a known predicate or `None`
/// otherwise. This backs C's classification macros at constant-evaluation time.
pub fn floating_classify(kind : String, value : Double, ty : Type) -> Bool? {
  let nan = value != value
  let pos_inf = 1.0 / 0.0
  let neg_inf = -pos_inf
  let inf = !nan && (value == pos_inf || value == neg_inf)
  let finite = !nan && !inf
  match kind {
    "isnan" => Some(nan)
    "isinf" => Some(inf)
    "isfinite" => Some(finite)
    "isnormal" => Some(finite && floating_abs(value) >= floating_normal_min(ty))
    "signbit" => Some(floating_signbit(value))
    _ => None
  }
}

///|
/// Evaluates a `__builtin_is*`/`__builtin_signbit` classification on a constant.
///
/// Maps each classification builtin name (and its `f`/`l` suffix) to the
/// corresponding `floating_classify` predicate and execution type. Returns
/// `None` for names this folder does not model.
pub fn floating_builtin_classify(name : String, value : Double) -> Bool? {
  match name {
    "__builtin_isnan" => floating_classify("isnan", value, Double)
    "__builtin_isnanf" => floating_classify("isnan", value, Float)
    "__builtin_isnanl" => floating_classify("isnan", value, LongDouble)
    "__builtin_isinf" => floating_classify("isinf", value, Double)
    "__builtin_isinff" => floating_classify("isinf", value, Float)
    "__builtin_isinfl" => floating_classify("isinf", value, LongDouble)
    "__builtin_isfinite" => floating_classify("isfinite", value, Double)
    "__builtin_isfinitef" => floating_classify("isfinite", value, Float)
    "__builtin_isfinitel" => floating_classify("isfinite", value, LongDouble)
    "__builtin_isnormal" => floating_classify("isnormal", value, Double)
    "__builtin_isnormalf" => floating_classify("isnormal", value, Float)
    "__builtin_isnormall" => floating_classify("isnormal", value, LongDouble)
    "__builtin_signbit" => floating_classify("signbit", value, Double)
    "__builtin_signbitf" => floating_classify("signbit", value, Float)
    "__builtin_signbitl" => floating_classify("signbit", value, LongDouble)
    _ => None
  }
}

///|
/// Runtime classification operation and execution type for floating builtins.
///
/// Long-double variants currently share the double runtime path used by the
/// MIR and direct assembly backends.
pub fn floating_builtin_runtime_class_info(name : String) -> (String, Type)? {
  match name {
    "__builtin_isnanf" => Some(("isnan", Float))
    "__builtin_isnan" | "__builtin_isnanl" => Some(("isnan", Double))
    "__builtin_isinff" => Some(("isinf", Float))
    "__builtin_isinf" | "__builtin_isinfl" => Some(("isinf", Double))
    "__builtin_isfinitef" => Some(("isfinite", Float))
    "__builtin_isfinite" | "__builtin_isfinitel" => Some(("isfinite", Double))
    "__builtin_isnormalf" => Some(("isnormal", Float))
    "__builtin_isnormal" | "__builtin_isnormall" => Some(("isnormal", Double))
    "__builtin_signbitf" => Some(("signbit", Float))
    "__builtin_signbit" | "__builtin_signbitl" => Some(("signbit", Double))
    _ => None
  }
}

///|
/// Evaluates a floating comparison, including the unordered relations.
///
/// Handles the ordinary relational operators plus `"<>"` (less-or-greater,
/// false when either operand is NaN) and `"unordered"` (true when either is
/// NaN). Returns `None` for an unknown operator. This is the constant-fold and
/// modeled-runtime core behind `floating_builtin_compare`.
pub fn floating_compare(op : String, left : Double, right : Double) -> Bool? {
  let unordered = left != left || right != right
  match op {
    "==" => Some(left == right)
    "!=" => Some(left != right)
    "<" => Some(left < right)
    ">" => Some(left > right)
    "<=" => Some(left <= right)
    ">=" => Some(left >= right)
    "<>" => Some(!unordered && left != right)
    "unordered" => Some(unordered)
    _ => None
  }
}

///|
/// Runtime comparison operation for floating comparison builtins.
pub fn floating_builtin_compare_op(name : String) -> String? {
  match name {
    "__builtin_isgreater" => Some(">")
    "__builtin_isgreaterequal" => Some(">=")
    "__builtin_isless" => Some("<")
    "__builtin_islessequal" => Some("<=")
    "__builtin_islessgreater" => Some("<>")
    "__builtin_isunordered" => Some("unordered")
    _ => None
  }
}

///|
/// Evaluates a floating comparison builtin on two constant operands.
///
/// Resolves the builtin name to a comparison operator via
/// `floating_builtin_compare_op` and applies `floating_compare`. Returns `None`
/// for names this folder does not model.
pub fn floating_builtin_compare(
  name : String,
  left : Double,
  right : Double,
) -> Bool? {
  match floating_builtin_compare_op(name) {
    Some(op) => floating_compare(op, left, right)
    None => None
  }
}

///|
/// Runtime math operation, execution type, and source arity for floating
/// builtins with explicit MIR semantics.
pub fn floating_builtin_runtime_math_info(
  name : String,
) -> (String, Type, Int)? {
  match name {
    "__builtin_fabsf" => Some(("fabs", Float, 1))
    "__builtin_fabs" | "__builtin_fabsl" => Some(("fabs", Double, 1))
    "__builtin_sqrtf" => Some(("sqrt", Float, 1))
    "__builtin_sqrt" | "__builtin_sqrtl" => Some(("sqrt", Double, 1))
    "__builtin_copysignf" => Some(("copysign", Float, 2))
    "__builtin_copysign" | "__builtin_copysignl" =>
      Some(("copysign", Double, 2))
    _ => None
  }
}
