///|
fn fold_const(expr : Expr) -> Int? {
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
    Ternary(cond, a, b) =>
      match fold_const(cond) {
        Some(0) => fold_const(b)
        Some(_) => fold_const(a)
        None => None
      }
    Cast(_, e) => fold_const(e)
    Sizeof(ty) => Some(basic_type_size(ty))
    SizeofExpr(e) => Some(basic_type_size(type_of_expr(e)))
    _ => None
  }
}

///|
fn basic_type_size(ty : Type) -> Int {
  match ty {
    Int => 8
    Char => 1
    Void => 0
    Pointer(_) => 8
    Array(elem, n) => basic_type_size(elem) * n
    Struct(_) => 8 // unknown struct size, assume pointer-sized
  }
}

///|
fn type_of_expr(expr : Expr) -> Type {
  match expr {
    Number(_) => Int
    String(_) => Pointer(Char)
    Var(_) => Int // unknown, assume int
    Binary(_, _, _) => Int
    Unary(_, _) => Int
    Call(_, _) => Int
    Assign(_, rhs) => type_of_expr(rhs)
    MemberAccess(_, _) => Int
    Deref(_) => Int
    AddrOf(_) => Pointer(Int)
    ArrayAccess(_, _) => Int
    Sizeof(_) => Int
    SizeofExpr(_) => Int
    Cast(ty, _) => ty
    PrefixInc(_) => Int
    PrefixDec(_) => Int
    PostfixInc(_) => Int
    PostfixDec(_) => Int
    Ternary(_, a, _) => type_of_expr(a)
  }
}
