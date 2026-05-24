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
pub fn floating_signbit(value : Double) -> Bool {
  let neg_inf = -(1.0 / 0.0)
  value < 0.0 || (value == 0.0 && 1.0 / value == neg_inf)
}

///|
pub fn floating_copysign(magnitude : Double, sign : Double) -> Double {
  let value = floating_abs(magnitude)
  if floating_signbit(sign) {
    -value
  } else {
    value
  }
}

///|
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
pub fn floating_constant_unary(op : String, value : Double) -> Double? {
  match op {
    "-" => Some(-value)
    "+" => Some(value)
    _ => None
  }
}

///|
pub fn floating_constant_from_integer_bits(bits : Int64) -> Double {
  bits.to_double()
}

///|
pub fn floating_constant_to_integer_bits(value : Double) -> Int64 {
  value.to_int().to_int64()
}

///|
pub fn integer_constant_from_floating(
  value : Double,
  ty : Type,
) -> IntegerConstant {
  integer_constant(floating_constant_to_integer_bits(value), ty)
}

///|
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
