///|
/// Construction surface for building expression trees by hand.
///
/// A generator emitting numeric kernels -- the FFTW shape, thousands of
/// straight-line arithmetic statements -- writes math, and the API should
/// read like it: `t1 - t2` and `k * (t1 + t2)` rather than nested `Binary`
/// spellings. The operators build exactly the tree the parser would produce
/// from the printed text, so everything constructed here round-trips.
///
/// `==` is taken by structural equality and stays that way; comparisons are
/// the named methods below.
pub impl Add for Expr with fn add(self, other) {
  Binary("+", self, other)
}

///|
pub impl Sub for Expr with fn sub(self, other) {
  Binary("-", self, other)
}

///|
pub impl Mul for Expr with fn mul(self, other) {
  Binary("*", self, other)
}

///|
pub impl Div for Expr with fn div(self, other) {
  Binary("/", self, other)
}

///|
/// Negation as the parser records it: `-x` is the unary operator applied to
/// `x`, never a negative literal.
pub impl Neg for Expr with fn neg(self) {
  Unary("-", self)
}

///|
/// Indexing builds an `ArrayAccess`, so a strided load is spelled the way
/// the emitted C will read: `ri[rs * 2]`.
#alias("_[_]")
pub fn Expr::index(self : Expr, index : Expr) -> Expr {
  ArrayAccess(self, index)
}

///|
/// `self < other`.
pub fn Expr::lt(self : Expr, other : Expr) -> Expr {
  Binary("<", self, other)
}

///|
/// `self <= other`.
pub fn Expr::le(self : Expr, other : Expr) -> Expr {
  Binary("<=", self, other)
}

///|
/// `self > other`.
pub fn Expr::gt(self : Expr, other : Expr) -> Expr {
  Binary(">", self, other)
}

///|
/// `self >= other`.
pub fn Expr::ge(self : Expr, other : Expr) -> Expr {
  Binary(">=", self, other)
}

///|
/// `self == other` as a C expression; `==` itself is structural equality
/// on the AST.
pub fn Expr::eq_expr(self : Expr, other : Expr) -> Expr {
  Binary("==", self, other)
}

///|
/// `self != other` as a C expression.
pub fn Expr::ne_expr(self : Expr, other : Expr) -> Expr {
  Binary("!=", self, other)
}

///|
/// `self % other`.
pub fn Expr::rem(self : Expr, other : Expr) -> Expr {
  Binary("%", self, other)
}

///|
/// Builds a floating literal from a value, formatting text that survives a
/// round-trip.
///
/// The text is authoritative -- that is the settled design for floating
/// literals -- so the format must satisfy two masters: the C lexer must read
/// it as a *floating* constant, which "1" is not, and reading it back must
/// give exactly `value`, which MoonBit's shortest-round-trip formatting
/// guarantees. A trailing `.0` is added when the shortest form carries no
/// mark of floatness. Negative values canonicalize to `Unary("-", ...)`, the
/// only spelling the parser ever produces; non-finite values have no C
/// literal at all and abort.
pub fn double_literal(value : Double) -> Expr {
  if value != value ||
    value == @double.infinity ||
    value == @double.neg_infinity {
    abort("double_literal: non-finite values have no C literal")
  }
  // The sign bit, not the ordering: `-0.0 < 0.0` is false, yet the sign is
  // observable through `1.0 / value`, and bit-exact means keeping it.
  if value.reinterpret_as_int64() < 0L {
    return Unary("-", double_literal(-value))
  }
  let mut text = value.to_string()
  if !text.contains(".") && !text.contains("e") && !text.contains("E") {
    text = text + ".0"
  }
  FloatLiteral(text, Double)
}

///|
/// Builds a `float` literal -- single precision, `f`-suffixed -- from a
/// value, formatting text that survives a round-trip. Inference kernels and
/// single-precision codelets live in `float`; the suffix is what makes the
/// C type (and the arithmetic) 32-bit. Negatives canonicalize to
/// `Unary("-", ...)`; non-finite values have no C literal and abort.
pub fn float_literal(value : Float) -> Expr {
  let wide = value.to_double()
  if wide != wide || wide == @double.infinity || wide == @double.neg_infinity {
    abort("float_literal: non-finite values have no C literal")
  }
  if wide.reinterpret_as_int64() < 0L {
    return Unary("-", float_literal(-value))
  }
  // The text excludes the suffix: the type carries it, and the printer
  // restores `f` from `Float` -- the same split the lexer makes when it
  // reads a suffixed literal.
  let mut text = value.to_string()
  if !text.contains(".") && !text.contains("e") && !text.contains("E") {
    text = text + ".0"
  }
  FloatLiteral(text, Float)
}

///|
/// The declared type an initializer implies, applied the way the parser
/// applies it: an incomplete array completes from its brace count -- 
/// designators included -- and a `char` array completes from its string,
/// terminator included. Builders call this so a hand-built declaration
/// carries the same type its printed form parses back to.
pub fn infer_global_array_type(ty : Type, init : GlobalInit?) -> Type {
  match init {
    Some(Array(items)) =>
      local_init_infer_array_size(ty, initializer_element_count(items))
    Some(Scalar(String(text))) =>
      match ty.core_type() {
        Array(_, 0) =>
          local_init_infer_array_size(
            ty,
            @ctype.string_literal_array_length(text),
          )
        _ => ty
      }
    _ => ty
  }
}

///|
/// The local-declaration counterpart of `infer_global_array_type`: a local
/// initializer is an expression, with a brace list recorded as `Array`.
pub fn infer_local_array_type(ty : Type, init : Expr?) -> Type {
  match init {
    Some(Array(items)) =>
      local_init_infer_array_size(ty, initializer_element_count(items))
    Some(String(text)) =>
      match ty.core_type() {
        Array(_, 0) =>
          local_init_infer_array_size(
            ty,
            @ctype.string_literal_array_length(text),
          )
        _ => ty
      }
    _ => ty
  }
}
