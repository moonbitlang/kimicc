///|
/// One-step reductions of a generated program, so a falsifying case arrives
/// minimal: drop a declaration, drop a statement, unwrap a block, drop an
/// else, or replace an expression by one of its children. Each candidate
/// changes exactly one site; quickcheck iterates greedily.
fn shrink_program(program : @parser.Program) -> Array[@parser.Program] {
  let out : Array[@parser.Program] = []
  // Drop one global.
  for i in 0..<program.globals.length() {
    let globals = program.globals.copy()
    let _ = globals.remove(i)
    out.push(rebuild(globals, program.decls))
  }
  // Drop one function (keep at least one).
  if program.decls.length() > 1 {
    for i in 0..<program.decls.length() {
      let decls = program.decls.copy()
      let _ = decls.remove(i)
      out.push(rebuild(program.globals, decls))
    }
  }
  // Shrink inside one function body.
  for i in 0..<program.decls.length() {
    let decl = program.decls[i]
    match decl.body {
      Some(Compound(stmts)) =>
        for candidate in shrink_stmts(stmts) {
          let decls = program.decls.copy()
          decls[i] = { ..decl, body: Some(Compound(candidate)) }
          out.push(rebuild(program.globals, decls))
        }
      _ => ()
    }
  }
  out
}

///|
fn rebuild(
  globals : Array[@parser.GlobalDecl],
  decls : Array[@parser.FuncDecl],
) -> @parser.Program {
  let items : Array[@parser.TopLevel] = []
  for i in 0..<globals.length() {
    items.push(Global(i))
  }
  for i in 0..<decls.length() {
    items.push(Func(i))
  }
  { structs: [], globals, decls, items }
}

///|
/// Candidates for a statement list: drop one statement, or replace one with
/// a one-step reduction of itself.
fn shrink_stmts(stmts : Array[@parser.Stmt]) -> Array[Array[@parser.Stmt]] {
  let out : Array[Array[@parser.Stmt]] = []
  for i in 0..<stmts.length() {
    let dropped = stmts.copy()
    let _ = dropped.remove(i)
    out.push(dropped)
    for reduced in shrink_stmt(stmts[i]) {
      let replaced = stmts.copy()
      replaced[i] = reduced
      out.push(replaced)
    }
  }
  out
}

///|
/// An `If` whose then-branch is braced whenever the else demands it, per the
/// canonical form the generator documents.
fn canonical_if(
  cond : @parser.Expr,
  then_branch : @parser.Stmt,
  else_branch : @parser.Stmt?,
) -> @parser.Stmt {
  if else_branch is Some(_) && captures_else(then_branch) {
    If(cond, Compound([then_branch]), else_branch)
  } else {
    If(cond, then_branch, else_branch)
  }
}

///|
fn shrink_stmt(stmt : @parser.Stmt) -> Array[@parser.Stmt] {
  let out : Array[@parser.Stmt] = []
  match stmt {
    ExprStmt(expr) =>
      for reduced in shrink_expr(expr) {
        out.push(ExprStmt(reduced))
      }
    VarDecl(ty, name, Some(expr)) => {
      out.push(VarDecl(ty, name, None))
      for reduced in shrink_expr(expr) {
        out.push(VarDecl(ty, name, Some(reduced)))
      }
    }
    Return(Some(expr)) => {
      out.push(Return(None))
      for reduced in shrink_expr(expr) {
        out.push(Return(Some(reduced)))
      }
    }
    If(cond, then_branch, else_branch) => {
      out.push(then_branch)
      match else_branch {
        Some(alternative) => {
          out.push(If(cond, then_branch, None))
          out.push(alternative)
          for reduced in shrink_stmt(alternative) {
            out.push(canonical_if(cond, then_branch, Some(reduced)))
          }
        }
        None => ()
      }
      for reduced in shrink_expr(cond) {
        out.push(canonical_if(reduced, then_branch, else_branch))
      }
      // A reduced then-branch may have lost the braces the canonical form
      // requires -- unwrapping `Compound([If(.., None)])` yields the bare
      // else-capturing `if` -- so reconstruction re-canonicalizes rather
      // than emitting a candidate outside the parser's image, which would
      // fail the property for the known dangling-else reason and mask the
      // regression being shrunk.
      for reduced in shrink_stmt(then_branch) {
        out.push(canonical_if(cond, reduced, else_branch))
      }
    }
    While(cond, body) => {
      out.push(body)
      for reduced in shrink_expr(cond) {
        out.push(While(reduced, body))
      }
      for reduced in shrink_stmt(body) {
        out.push(While(cond, reduced))
      }
    }
    For(init, cond, step, body) => {
      out.push(body)
      if init.length() > 0 {
        out.push(For([], cond, step, body))
      }
      match step {
        Some(_) => out.push(For(init, cond, None, body))
        None => ()
      }
      for reduced in shrink_expr(cond) {
        out.push(For(init, reduced, step, body))
      }
      for reduced in shrink_stmt(body) {
        out.push(For(init, cond, step, reduced))
      }
    }
    Compound(stmts) => {
      // Unwrapping a singleton block is often the biggest single step.
      if stmts.length() == 1 {
        out.push(stmts[0])
      }
      for candidate in shrink_stmts(stmts) {
        out.push(Compound(candidate))
      }
    }
    _ => ()
  }
  out
}

///|
/// A child of each expression node, plus the literal `1` for anything that
/// is not already a plain literal or variable.
fn shrink_expr(expr : @parser.Expr) -> Array[@parser.Expr] {
  let out : Array[@parser.Expr] = []
  match expr {
    Number(_, _, _) | Var(_) => ()
    Binary(op, lhs, rhs) => {
      out.push(lhs)
      out.push(rhs)
      for reduced in shrink_expr(lhs) {
        out.push(Binary(op, reduced, rhs))
      }
      for reduced in shrink_expr(rhs) {
        out.push(Binary(op, lhs, reduced))
      }
    }
    Unary(_, operand) => out.push(operand)
    Ternary(cond, then_value, else_value) => {
      out.push(cond)
      out.push(then_value)
      out.push(else_value)
    }
    Assign(target, value) => {
      out.push(value)
      for reduced in shrink_expr(value) {
        out.push(Assign(target, reduced))
      }
    }
    _ => out.push(@parser.int_literal(1, SInt))
  }
  out
}
