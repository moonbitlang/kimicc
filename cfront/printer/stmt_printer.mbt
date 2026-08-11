///|
/// Renders a statement as C source, starting at the left margin.
///
/// ```mbt check
/// test {
///   inspect(
///     @printer.print_stmt(Return(Some(@parser.int_literal(0, SInt)))),
///     content="return 0;",
///   )
/// }
/// ```
pub fn print_stmt(stmt : @parser.Stmt) -> String {
  let buf = StringBuilder::new()
  write_stmt(buf, stmt, 0)
  buf.to_string()
}

///|
/// Writes `indent` levels of two-space indentation.
fn write_indent(buf : StringBuilder, indent : Int) -> Unit {
  for _ in 0..<indent {
    buf.write_string("  ")
  }
}

///|
/// Writes a statement at the given indentation level, without a trailing
/// newline.
fn write_stmt(buf : StringBuilder, stmt : @parser.Stmt, indent : Int) -> Unit {
  match stmt {
    ExprStmt(expr) => {
      write_indent(buf, indent)
      buf.write_string(print_expr(expr))
      buf.write_string(";")
    }
    Return(value) => {
      write_indent(buf, indent)
      match value {
        Some(expr) => {
          buf.write_string("return ")
          buf.write_string(print_expr(expr))
        }
        None => buf.write_string("return")
      }
      buf.write_string(";")
    }
    If(cond, then_branch, else_branch) => {
      write_indent(buf, indent)
      buf.write_string("if (")
      buf.write_string(print_expr(cond))
      buf.write_string(") ")
      write_branch(buf, then_branch, indent)
      match else_branch {
        Some(alternative) => {
          buf.write_string(" else ")
          write_branch(buf, alternative, indent)
        }
        None => ()
      }
    }
    While(cond, body) => {
      write_indent(buf, indent)
      buf.write_string("while (")
      buf.write_string(print_expr(cond))
      buf.write_string(") ")
      write_branch(buf, body, indent)
    }
    DoWhile(cond, body) => {
      write_indent(buf, indent)
      buf.write_string("do ")
      write_branch(buf, body, indent)
      buf.write_string(" while (")
      buf.write_string(print_expr(cond))
      buf.write_string(");")
    }
    For(init, cond, step, body) => {
      write_indent(buf, indent)
      buf.write_string("for (")
      write_for_init(buf, init)
      buf.write_string(" ")
      buf.write_string(print_expr(cond))
      buf.write_string(";")
      match step {
        Some(expr) => {
          buf.write_string(" ")
          buf.write_string(print_expr(expr))
        }
        None => ()
      }
      buf.write_string(") ")
      write_branch(buf, body, indent)
    }
    Compound(body) => write_block(buf, body, indent)
    VarDecl(ty, name, init) => {
      write_indent(buf, indent)
      buf.write_string(print_declaration(ty, name))
      match init {
        Some(value) => {
          buf.write_string(" = ")
          buf.write_string(print_expr(value))
        }
        None => ()
      }
      buf.write_string(";")
    }
    Break => {
      write_indent(buf, indent)
      buf.write_string("break;")
    }
    Continue => {
      write_indent(buf, indent)
      buf.write_string("continue;")
    }
    Switch(subject, body) => {
      write_indent(buf, indent)
      buf.write_string("switch (")
      buf.write_string(print_expr(subject))
      buf.write_string(") ")
      match body {
        Compound(stmts) => write_block(buf, stmts, indent)
        other => write_branch(buf, other, indent)
      }
    }
    Goto(label) => {
      write_indent(buf, indent)
      buf.write_string("goto ")
      buf.write_string(label)
      buf.write_string(";")
    }
    ComputedGoto(target) => {
      write_indent(buf, indent)
      buf.write_string("goto *")
      buf.write_string(print_expr_at(target, PREC_UNARY))
      buf.write_string(";")
    }
    Case(value, body) =>
      write_label(buf, "case " + value.to_string() + ":", body, indent)
    Default(body) => write_label(buf, "default:", body, indent)
    Label(name, body) => write_label(buf, name + ":", body, indent)
  }
}

///|
/// Writes a label and the statement it labels, the label on its own line.
///
/// The labelled statement keeps the enclosing indentation rather than being
/// nested under the label, since a `case` clause reads as a peer of the
/// statements that follow it, not as a block.
fn write_label(
  buf : StringBuilder,
  label : String,
  body : @parser.Stmt,
  indent : Int,
) -> Unit {
  write_indent(buf, indent)
  buf.write_string(label)
  buf.write_string("\n")
  write_stmt(buf, body, indent)
}

///|
/// Writes a braced block containing `body`.
fn write_block(
  buf : StringBuilder,
  body : ArrayView[@parser.Stmt],
  indent : Int,
) -> Unit {
  if body.length() == 0 {
    buf.write_string("{}")
    return
  }
  buf.write_string("{\n")
  for stmt in body {
    write_stmt(buf, stmt, indent + 1)
    buf.write_string("\n")
  }
  write_indent(buf, indent)
  buf.write_string("}")
}

///|
/// Writes a statement in a position that expects a single substatement, such as
/// an `if` or loop body.
///
/// A compound body is written inline after the enclosing keyword; anything else
/// goes on its own indented line so that a bare `if (c) x = 1;` stays readable.
fn write_branch(buf : StringBuilder, stmt : @parser.Stmt, indent : Int) -> Unit {
  match stmt {
    Compound(body) => write_block(buf, body, indent)
    other => {
      buf.write_string("\n")
      write_stmt(buf, other, indent + 1)
    }
  }
}

///|
/// Writes a `for` initializer clause, including its terminating `;`.
///
/// C's `for` init is grammatically one declaration or one expression, but the
/// AST records `for (int i = 0, n = len; ...)` as one `VarDecl` per name, the
/// same as in a block. Rejoining them is this function's job: names sharing a
/// specifier are written as C writes them, and expressions are joined with the
/// comma operator, which is the other way C puts several things in this clause.
///
/// A group C has no spelling for -- names whose specifiers differ, or a mix of
/// declarations and expressions -- can only be built by hand, never parsed.
/// Each part is written in full so that what was built is visible, rather than
/// silently dropping the parts that do not fit.
fn write_for_init(buf : StringBuilder, init : Array[@parser.Stmt]) -> Unit {
  if init.length() == 0 {
    buf.write_string(";")
    return
  }
  let specifiers = []
  let declarators = []
  for stmt in init {
    match stmt {
      VarDecl(ty, name, value) => {
        let (specifier, declarator) = split_declaration(ty, name)
        specifiers.push(specifier)
        declarators.push(
          match value {
            Some(expr) => declarator + " = " + print_expr(expr)
            None => declarator
          },
        )
      }
      _ => ()
    }
  }
  if declarators.length() == init.length() &&
    specifiers.iter().all(specifier => specifier == specifiers[0]) {
    buf.write_string(specifiers[0])
    buf.write_string(" ")
    for i, declarator in declarators {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string(declarator)
    }
    buf.write_string(";")
    return
  }
  let exprs = []
  for stmt in init {
    match stmt {
      ExprStmt(expr) => exprs.push(expr)
      _ => ()
    }
  }
  if exprs.length() == init.length() {
    for i, expr in exprs {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string(print_expr(expr))
    }
    buf.write_string(";")
    return
  }
  for i, stmt in init {
    if i > 0 {
      buf.write_string(" ")
    }
    buf.write_string(print_stmt(stmt))
  }
}
