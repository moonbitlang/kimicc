///|
/// Finds the first place a program would need the ABI of a `Named` type.
///
/// A named type is a spelling with no layout: anywhere a backend would
/// pass, return, store, or load one *by value*, the fallthrough would be
/// the integer register path -- silently wrong for the vector types
/// `Named` exists for. Behind a plain pointer the type is opaque data and
/// legal; but a function-pointer signature found there re-enters value
/// position, because an indirect call classifies its arguments and result
/// -- so `float32x4_t (**cb)(void)` is still a violation.
///
/// The walk covers every type a backend consumes: function signatures,
/// globals, aggregate fields, local declarations, and the types embedded
/// in expressions (casts, compound literals, `va_arg`). `sizeof` and
/// `_Alignof` over a named type are not violations here; the layout
/// queries already refuse them loudly.
///
/// Returns a description of the first violation, or `None` when the
/// program is safe to lower. Code generators call this once at entry and
/// abort with the description; keeping the walk a query keeps it
/// testable.
pub fn named_abi_violation(program : Program) -> String? {
  for s in program.structs {
    for field in s.fields {
      let what = "field `" + s.name + "." + field.name + "`"
      match named_abi_violation_in_type(field.ty, what, false) {
        Some(msg) => return Some(msg)
        None => ()
      }
    }
  }
  for g in program.globals {
    match named_abi_violation_in_type(g.ty, "global `" + g.name + "`", false) {
      Some(msg) => return Some(msg)
      None => ()
    }
    match g.init {
      Some(Scalar(expr)) =>
        match named_abi_violation_in_expr(expr) {
          Some(msg) => return Some(msg)
          None => ()
        }
      Some(Array(exprs)) =>
        for expr in exprs {
          match named_abi_violation_in_expr(expr) {
            Some(msg) => return Some(msg)
            None => ()
          }
        }
      None => ()
    }
  }
  for decl in program.decls {
    let what = "function `" + decl.name + "`"
    match named_abi_violation_in_type(decl.ret, what, false) {
      Some(msg) => return Some(msg)
      None => ()
    }
    for param in decl.params {
      match named_abi_violation_in_type(param.ty, what, false) {
        Some(msg) => return Some(msg)
        None => ()
      }
    }
    match decl.body {
      Some(body) =>
        match named_abi_violation_in_stmt(body) {
          Some(msg) => return Some(msg)
          None => ()
        }
      None => ()
    }
  }
  None
}

///|
/// The two-mode type walk behind `named_abi_violation`: `behind_pointer`
/// tracks whether the current position is opaque storage (legal for a
/// bare `Named`) or value position (a violation). Function-pointer
/// signatures re-enter value position on both sides of the call.
fn named_abi_violation_in_type(
  ty : @ctype.Type,
  what : String,
  behind_pointer : Bool,
) -> String? {
  match ty {
    Named(name) =>
      if behind_pointer {
        None
      } else {
        Some(
          what +
          " uses named type `" +
          name +
          "` by value; its ABI is unknown here",
        )
      }
    Pointer(inner) => named_abi_violation_in_type(inner, what, true)
    FuncPtr(ret, params, _) => {
      match named_abi_violation_in_type(ret, what, false) {
        Some(msg) => return Some(msg)
        None => ()
      }
      for p in params {
        match named_abi_violation_in_type(p, what, false) {
          Some(msg) => return Some(msg)
          None => ()
        }
      }
      None
    }
    Atomic(inner) | Aligned(inner, _) | Array(inner, _) =>
      named_abi_violation_in_type(inner, what, behind_pointer)
    _ => None
  }
}

///|
fn named_abi_violation_in_stmt(stmt : Stmt) -> String? {
  match stmt {
    ExprStmt(e) | ComputedGoto(e) => named_abi_violation_in_expr(e)
    Return(e) =>
      match e {
        Some(expr) => named_abi_violation_in_expr(expr)
        None => None
      }
    If(cond, then_branch, else_branch) => {
      match named_abi_violation_in_expr(cond) {
        Some(msg) => return Some(msg)
        None => ()
      }
      match named_abi_violation_in_stmt(then_branch) {
        Some(msg) => return Some(msg)
        None => ()
      }
      match else_branch {
        Some(s) => named_abi_violation_in_stmt(s)
        None => None
      }
    }
    While(cond, body) | DoWhile(cond, body) | Switch(cond, body) => {
      match named_abi_violation_in_expr(cond) {
        Some(msg) => return Some(msg)
        None => ()
      }
      named_abi_violation_in_stmt(body)
    }
    Compound(stmts) => {
      for s in stmts {
        match named_abi_violation_in_stmt(s) {
          Some(msg) => return Some(msg)
          None => ()
        }
      }
      None
    }
    VarDecl(ty, name, init) => {
      match named_abi_violation_in_type(ty, "local `" + name + "`", false) {
        Some(msg) => return Some(msg)
        None => ()
      }
      match init {
        Some(expr) => named_abi_violation_in_expr(expr)
        None => None
      }
    }
    For(init, cond, step, body) => {
      for s in init {
        match named_abi_violation_in_stmt(s) {
          Some(msg) => return Some(msg)
          None => ()
        }
      }
      match named_abi_violation_in_expr(cond) {
        Some(msg) => return Some(msg)
        None => ()
      }
      match step {
        Some(e) =>
          match named_abi_violation_in_expr(e) {
            Some(msg) => return Some(msg)
            None => ()
          }
        None => ()
      }
      named_abi_violation_in_stmt(body)
    }
    Case(_, body) | Default(body) | Label(_, body) =>
      named_abi_violation_in_stmt(body)
    Break | Continue | Goto(_) => None
  }
}

///|
fn named_abi_violation_in_expr(expr : Expr) -> String? {
  match expr {
    Number(_, _, _)
    | FloatLiteral(_, _)
    | String(_)
    | Var(_)
    | LabelAddr(_)
    | Sizeof(_)
    | Alignof(_)
    | OffsetOf(_, _) => None
    Cast(ty, inner) => {
      match named_abi_violation_in_type(ty, "cast", false) {
        Some(msg) => return Some(msg)
        None => ()
      }
      named_abi_violation_in_expr(inner)
    }
    VaArg(inner, ty) => {
      match named_abi_violation_in_type(ty, "va_arg", false) {
        Some(msg) => return Some(msg)
        None => ()
      }
      named_abi_violation_in_expr(inner)
    }
    CompoundLiteral(ty, exprs, _) => {
      match named_abi_violation_in_type(ty, "compound literal", false) {
        Some(msg) => return Some(msg)
        None => ()
      }
      for e in exprs {
        match named_abi_violation_in_expr(e) {
          Some(msg) => return Some(msg)
          None => ()
        }
      }
      None
    }
    Binary(_, l, r) | Assign(l, r) | CompoundAssign(_, l, r) => {
      match named_abi_violation_in_expr(l) {
        Some(msg) => return Some(msg)
        None => ()
      }
      named_abi_violation_in_expr(r)
    }
    ArrayAccess(l, r) => {
      match named_abi_violation_in_expr(l) {
        Some(msg) => return Some(msg)
        None => ()
      }
      named_abi_violation_in_expr(r)
    }
    Unary(_, e)
    | Deref(e)
    | AddrOf(e)
    | MemberAccess(e, _)
    | SizeofExpr(e)
    | AlignofExpr(e)
    | PrefixInc(e)
    | PrefixDec(e)
    | PostfixInc(e)
    | PostfixDec(e)
    | DesignatedField(_, e)
    | DesignatedIndex(_, e) => named_abi_violation_in_expr(e)
    DesignatedRange(_, _, e) => named_abi_violation_in_expr(e)
    Ternary(c, t, f) => {
      match named_abi_violation_in_expr(c) {
        Some(msg) => return Some(msg)
        None => ()
      }
      match named_abi_violation_in_expr(t) {
        Some(msg) => return Some(msg)
        None => ()
      }
      named_abi_violation_in_expr(f)
    }
    Call(callee, args) => {
      match named_abi_violation_in_expr(callee) {
        Some(msg) => return Some(msg)
        None => ()
      }
      for arg in args {
        match named_abi_violation_in_expr(arg) {
          Some(msg) => return Some(msg)
          None => ()
        }
      }
      None
    }
    Array(exprs) => {
      for e in exprs {
        match named_abi_violation_in_expr(e) {
          Some(msg) => return Some(msg)
          None => ()
        }
      }
      None
    }
  }
}
