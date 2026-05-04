///|
fn fold_const(expr : Expr) -> Int64? {
  match expr {
    Number(n) => Some(n)
    Binary("+", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x + y)
        _ => None
      }
    Binary("-", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x - y)
        _ => None
      }
    Binary("*", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x * y)
        _ => None
      }
    Binary("/", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => if y != 0 { Some(x / y) } else { None }
        _ => None
      }
    Binary("%", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => if y != 0 { Some(x % y) } else { None }
        _ => None
      }
    Binary("|", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x | y)
        _ => None
      }
    Binary("&", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x & y)
        _ => None
      }
    Binary("^", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x ^ y)
        _ => None
      }
    Binary("<<", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x << y.to_int())
        _ => None
      }
    Binary(">>", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x >> y.to_int())
        _ => None
      }
    Ternary(cond, a, b) =>
      match fold_const(cond) {
        Some(0L) => fold_const(b)
        Some(_) => fold_const(a)
        None => None
      }
    Unary("-", e) =>
      match fold_const(e) {
        Some(x) => Some(-x)
        _ => None
      }
    Unary("~", e) =>
      match fold_const(e) {
        Some(x) => Some(x.lnot())
        _ => None
      }
    Unary("!", e) =>
      match fold_const(e) {
        Some(0L) => Some(1L)
        Some(_) => Some(0L)
        _ => None
      }
    Cast(_, e) => fold_const(e)
    Sizeof(ty) => Some(basic_type_size(ty).to_int64())
    SizeofExpr(e) => Some(basic_type_size(type_of_expr(e)).to_int64())
    _ => None
  }
}

///|
fn basic_type_size(ty : Type) -> Int {
  match ty {
    Void => 0
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt | Float => 4
    SLong | ULong | SLongLong | ULongLong | Double | Pointer(_) => 8
    Array(elem, n) => basic_type_size(elem) * n
    Struct(_) => 8 // unknown struct size, assume pointer-sized
    Union(_) => 8 // unknown union size, assume pointer-sized
    Atomic(inner) => basic_type_size(inner)
  }
}

///|
fn type_of_expr(expr : Expr) -> Type {
  match expr {
    Number(_) => SInt
    FloatLiteral(_) => Double
    String(_) => Pointer(SChar)
    Var(_) => SInt // unknown, assume int
    Binary(_, _, _) => SInt
    Unary(_, _) => SInt
    Call(_, _) => SInt
    Assign(_, rhs) => type_of_expr(rhs)
    MemberAccess(_, _) => SInt
    Deref(_) => SInt
    AddrOf(_) => Pointer(SInt)
    ArrayAccess(_, _) => SInt
    Sizeof(_) => SInt
    SizeofExpr(_) => SInt
    Cast(ty, _) => ty
    PrefixInc(_) => SInt
    PrefixDec(_) => SInt
    PostfixInc(_) => SInt
    PostfixDec(_) => SInt
    Ternary(_, a, _) => type_of_expr(a)
    LabelAddr(_) => Pointer(Void)
  }
}
