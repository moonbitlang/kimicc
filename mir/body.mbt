///|
/// Stable reference to a lowered function-local C object.
///
/// Codegen-facing MIR should use this ID rather than parser AST variable names
/// so later passes do not need to recover binding information from source AST
/// nodes.
pub(all) struct MirLocal {
  id : Int
  name : String
  ty : @parser.Type
} derive(Eq)

///|
/// Integer/scalar MIR value expression.
///
/// This is intentionally smaller than the parser AST. Unsupported source
/// expressions simply keep the containing function out of `Program.bodies`
/// until the MIR layer learns that feature.
pub(all) enum MirValue {
  MirConst(Int64, @parser.Type)
  MirLocal(MirLocal)
  MirUnary(String, MirValue, @parser.Type)
  MirBinary(String, MirValue, MirValue, @parser.Type)
  MirCast(@parser.Type, MirValue)
  MirCall(String, Array[MirValue], @parser.Type)
  MirAssignLocal(MirLocal, MirValue)
  MirTernary(MirValue, MirValue, MirValue, @parser.Type)
} derive(Eq)

///|
/// Structured MIR statement subset used before CFG/block lowering.
pub(all) enum MirStmt {
  MirDeclare(MirLocal, MirValue?)
  MirExprStmt(MirValue)
  MirReturn(MirValue?)
  MirIf(MirValue, Array[MirStmt], Array[MirStmt])
  MirWhile(MirValue, Array[MirStmt])
  MirFor(Array[MirStmt], MirValue, MirValue?, Array[MirStmt])
  MirDoWhile(MirValue, Array[MirStmt])
  MirSwitch(MirValue, Array[(Int64?, String)], Array[MirStmt])
  MirLabel(String)
  MirGoto(String)
  MirBreak
  MirContinue
  MirBlock(Array[MirStmt])
} derive(Eq)

///|
/// MIR-owned function body. This is the boundary that lets later codegen stop
/// walking parser statements and expressions.
pub(all) struct MirFuncBody {
  name : String
  ret : @parser.Type
  params : Array[MirLocal]
  locals : Array[MirLocal]
  body : Array[MirStmt]
} derive(Eq)

///|
pub fn MirValue::ty(self : MirValue) -> @parser.Type {
  match self {
    MirConst(_, ty) => ty
    MirLocal(binding) => binding.ty
    MirUnary(_, _, ty) => ty
    MirBinary(_, _, _, ty) => ty
    MirCast(ty, _) => ty
    MirCall(_, _, ty) => ty
    MirAssignLocal(binding, _) => binding.ty
    MirTernary(_, _, _, ty) => ty
  }
}

///|
priv struct BodyLowerContext {
  scopes : Array[Map[String, MirLocal]]
  locals : Array[MirLocal]
  mut next_id : Int
  current_func : String
}

///|
fn BodyLowerContext::new(current_func : String) -> BodyLowerContext {
  { scopes: [{}], locals: [], next_id: 0, current_func }
}

///|
fn BodyLowerContext::scope(self : BodyLowerContext) -> Scope {
  let locals : Map[String, @parser.Type] = {}
  for binding in self.locals {
    match self.lookup_local(binding.name) {
      Some(active) =>
        if active.id == binding.id {
          locals[binding.name] = binding.ty
        }
      None => ()
    }
  }
  { locals, current_func: self.current_func }
}

///|
fn BodyLowerContext::push_scope(self : BodyLowerContext) -> Unit {
  self.scopes.push({})
}

///|
fn BodyLowerContext::pop_scope(self : BodyLowerContext) -> Unit {
  if self.scopes.length() > 1 {
    let _ = self.scopes.pop()
  }
}

///|
fn BodyLowerContext::declare_local(
  self : BodyLowerContext,
  name : String,
  ty : @parser.Type,
) -> MirLocal {
  let binding = { id: self.next_id, name, ty }
  self.next_id += 1
  self.locals.push(binding)
  let index = self.scopes.length() - 1
  self.scopes[index][name] = binding
  binding
}

///|
fn BodyLowerContext::lookup_local(
  self : BodyLowerContext,
  name : String,
) -> MirLocal? {
  for i = self.scopes.length() - 1; i >= 0; i = i - 1 {
    let scope = self.scopes[i]
    if scope.contains(name) {
      return Some(scope[name])
    }
  }
  None
}

///|
fn lower_mir_cancelled_local_lvalue(
  expr : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirLocal? {
  match expr {
    Var(name) => ctx.lookup_local(name)
    Deref(AddrOf(Var(name))) => ctx.lookup_local(name)
    _ => None
  }
}

///|
fn lower_mir_local_update(
  name : String,
  op : String,
  rhs : MirValue,
  ty : @parser.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  match ctx.lookup_local(name) {
    Some(binding) =>
      if binding.ty.is_integer() {
        Some(MirAssignLocal(binding, MirBinary(op, MirLocal(binding), rhs, ty)))
      } else {
        None
      }
    None => None
  }
}

///|
fn lower_mir_local_step(
  name : String,
  op : String,
  ty : @parser.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  lower_mir_local_update(name, op, MirConst(1L, SInt), ty, ctx)
}

///|
fn mir_stmts_have_direct_label(stmts : Array[MirStmt], name : String) -> Bool {
  for stmt in stmts {
    match stmt {
      MirLabel(label) if label == name => return true
      _ => ()
    }
  }
  false
}

///|
fn mir_switch_cases_are_direct(
  cases : Array[(Int64?, String)],
  body : Array[MirStmt],
) -> Bool {
  for c in cases {
    if !mir_stmts_have_direct_label(body, c.1) {
      return false
    }
  }
  true
}

///|
fn Program::lower_mir_expr(
  self : Program,
  expr : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirValue? {
  let scope = ctx.scope()
  let ty = self.expr_type(expr, scope)
  match expr {
    Number(value) => Some(MirConst(value, ty))
    Var(name) =>
      match ctx.lookup_local(name) {
        Some(binding) => Some(MirLocal(binding))
        None => None
      }
    Deref(AddrOf(Var(name))) =>
      match ctx.lookup_local(name) {
        Some(binding) => Some(MirLocal(binding))
        None => None
      }
    AddrOf(Deref(inner)) => self.lower_mir_expr(inner, ctx)
    Binary(op, lhs, rhs) =>
      match (self.lower_mir_expr(lhs, ctx), self.lower_mir_expr(rhs, ctx)) {
        (Some(left), Some(right)) => Some(MirBinary(op, left, right, ty))
        _ => None
      }
    Unary(op, inner) =>
      match self.lower_mir_expr(inner, ctx) {
        Some(value) => Some(MirUnary(op, value, ty))
        None => None
      }
    Cast(cast_ty, inner) =>
      match self.lower_mir_expr(inner, ctx) {
        Some(value) => Some(MirCast(cast_ty, value))
        None => None
      }
    Assign(lhs, rhs) =>
      match
        (
          lower_mir_cancelled_local_lvalue(lhs, ctx),
          self.lower_mir_expr(rhs, ctx),
        ) {
        (Some(binding), Some(value)) => Some(MirAssignLocal(binding, value))
        _ => None
      }
    CompoundAssign(op, lhs, rhs) =>
      match
        (
          lower_mir_cancelled_local_lvalue(lhs, ctx),
          self.lower_mir_expr(rhs, ctx),
        ) {
        (Some(binding), Some(value)) =>
          lower_mir_local_update(binding.name, op, value, ty, ctx)
        _ => None
      }
    PrefixInc(Var(name)) => lower_mir_local_step(name, "+", ty, ctx)
    PrefixDec(Var(name)) => lower_mir_local_step(name, "-", ty, ctx)
    Ternary(cond, then_, else_) =>
      match
        (
          self.lower_mir_expr(cond, ctx),
          self.lower_mir_expr(then_, ctx),
          self.lower_mir_expr(else_, ctx),
        ) {
        (Some(c), Some(t), Some(e)) => Some(MirTernary(c, t, e, ty))
        _ => None
      }
    Call(Var(name), args) => {
      let values : Array[MirValue] = []
      for arg in args {
        match self.lower_mir_expr(arg, ctx) {
          Some(value) => values.push(value)
          None => return None
        }
      }
      Some(MirCall(name, values, ty))
    }
    _ =>
      match self.fold_const(expr, scope) {
        Some(value) => Some(MirConst(value, ty))
        None => None
      }
  }
}

///|
fn Program::lower_mir_ignored_expr(
  self : Program,
  expr : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirValue? {
  let scope = ctx.scope()
  let ty = self.expr_type(expr, scope)
  match expr {
    PostfixInc(Var(name)) => lower_mir_local_step(name, "+", ty, ctx)
    PostfixDec(Var(name)) => lower_mir_local_step(name, "-", ty, ctx)
    _ => self.lower_mir_expr(expr, ctx)
  }
}

///|
fn Program::lower_mir_stmt(
  self : Program,
  stmt : @parser.Stmt,
  ctx : BodyLowerContext,
) -> Array[MirStmt]? {
  match stmt {
    ExprStmt(expr) =>
      match self.lower_mir_ignored_expr(expr, ctx) {
        Some(value) => Some([MirExprStmt(value)])
        None => None
      }
    Return(expr) =>
      match expr {
        Some(value_expr) =>
          match self.lower_mir_expr(value_expr, ctx) {
            Some(value) => Some([MirReturn(Some(value))])
            None => None
          }
        None => Some([MirReturn(None)])
      }
    If(cond, then_, else_) =>
      match (self.lower_mir_expr(cond, ctx), self.lower_mir_stmt(then_, ctx)) {
        (Some(cond_value), Some(then_body)) => {
          let else_body = match else_ {
            Some(stmt) =>
              match self.lower_mir_stmt(stmt, ctx) {
                Some(body) => body
                None => return None
              }
            None => []
          }
          Some([MirIf(cond_value, then_body, else_body)])
        }
        _ => None
      }
    While(cond, body) =>
      match (self.lower_mir_expr(cond, ctx), self.lower_mir_stmt(body, ctx)) {
        (Some(cond_value), Some(body_values)) =>
          Some([MirWhile(cond_value, body_values)])
        _ => None
      }
    For(init, cond, inc, body) => {
      ctx.push_scope()
      let init_values = match init {
        Some(init_stmt) =>
          match self.lower_mir_stmt(init_stmt, ctx) {
            Some(values) => values
            None => {
              ctx.pop_scope()
              return None
            }
          }
        None => []
      }
      let cond_value = match self.lower_mir_expr(cond, ctx) {
        Some(value) => value
        None => {
          ctx.pop_scope()
          return None
        }
      }
      let inc_value = match inc {
        Some(expr) =>
          match self.lower_mir_ignored_expr(expr, ctx) {
            Some(value) => Some(value)
            None => {
              ctx.pop_scope()
              return None
            }
          }
        None => None
      }
      let body_values = match self.lower_mir_stmt(body, ctx) {
        Some(values) => values
        None => {
          ctx.pop_scope()
          return None
        }
      }
      ctx.pop_scope()
      Some([MirFor(init_values, cond_value, inc_value, body_values)])
    }
    DoWhile(cond, body) =>
      match (self.lower_mir_expr(cond, ctx), self.lower_mir_stmt(body, ctx)) {
        (Some(cond_value), Some(body_values)) =>
          Some([MirDoWhile(cond_value, body_values)])
        _ => None
      }
    Switch(expr, body, cases) =>
      match (self.lower_mir_expr(expr, ctx), self.lower_mir_stmt(body, ctx)) {
        (Some(control), Some(body_values)) =>
          if mir_switch_cases_are_direct(cases, body_values) {
            Some([MirSwitch(control, cases, body_values)])
          } else {
            None
          }
        _ => None
      }
    Label(name, body) =>
      match self.lower_mir_stmt(body, ctx) {
        Some(body_values) => {
          let lowered : Array[MirStmt] = [MirLabel(name)]
          for value in body_values {
            lowered.push(value)
          }
          Some(lowered)
        }
        None => None
      }
    Goto(name) => Some([MirGoto(name)])
    Break => Some([MirBreak])
    Continue => Some([MirContinue])
    Compound(stmts) | StmtList(stmts) => {
      ctx.push_scope()
      let values : Array[MirStmt] = []
      for nested in stmts {
        match self.lower_mir_stmt(nested, ctx) {
          Some(lowered) =>
            for value in lowered {
              values.push(value)
            }
          None => {
            ctx.pop_scope()
            return None
          }
        }
      }
      ctx.pop_scope()
      Some(values)
    }
    VarDecl(ty, name, init) => {
      let init_value = match init {
        Some(expr) =>
          match self.lower_mir_expr(expr, ctx) {
            Some(value) => Some(value)
            None => return None
          }
        None => None
      }
      let binding = ctx.declare_local(name, ty)
      Some([MirDeclare(binding, init_value)])
    }
    _ => None
  }
}

///|
fn Program::lower_mir_func_body(
  self : Program,
  decl : @parser.FuncDecl,
) -> MirFuncBody? {
  match decl.body {
    Some(body) => {
      let ctx = BodyLowerContext::new(decl.name)
      let params : Array[MirLocal] = []
      for param in decl.params {
        let binding = ctx.declare_local(param.name, param.ty)
        params.push(binding)
      }
      match self.lower_mir_stmt(body, ctx) {
        Some(stmts) =>
          Some({
            name: decl.name,
            ret: decl.ret,
            params,
            locals: ctx.locals,
            body: stmts,
          })
        None => None
      }
    }
    None => None
  }
}
