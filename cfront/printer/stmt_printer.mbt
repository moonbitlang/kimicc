///|
/// Renders a statement as C source, starting at the left margin.
///
/// ```mbt check
/// test {
///   inspect(@printer.print_stmt(Return(Some(Number(0)))), content="return 0;")
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
      match init {
        // The initializer is written inline, so its own indentation and
        // terminator are stripped by rendering it at level zero.
        Some(stmt) => buf.write_string(print_stmt(stmt))
        None => buf.write_string(";")
      }
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
    StmtList(body) => {
      // A statement list is a parser grouping with no braces of its own, so its
      // members are written at the enclosing level.
      let mut first = true
      for inner in body {
        if !first {
          buf.write_string("\n")
        }
        write_stmt(buf, inner, indent)
        first = false
      }
    }
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
    Switch(subject, body, _) => {
      // The case table is derived from the labels in the body, so printing the
      // body is enough for it to be rebuilt on reparse.
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
    Label(name, body) => {
      // Case and default labels are stored as synthetic label names; printing
      // them back as `case`/`default` is what makes the output ordinary C.
      write_indent(buf, indent)
      buf.write_string(label_syntax(name))
      buf.write_string("\n")
      write_stmt(buf, body, indent)
    }
  }
}

///|
/// Renders a label's leading syntax, translating the parser's synthetic case
/// and default label names back into `case N:` and `default:`.
fn label_syntax(name : String) -> String {
  match case_label_value(name) {
    Some(value) => "case " + value.to_string() + ":"
    None => if is_default_label_name(name) { "default:" } else { name + ":" }
  }
}

///|
/// Extracts the case value from a synthetic case label name.
///
/// The parser spells these `__kimicc_case_<value>_<counter>`, so the digits
/// before the final underscore are the case value.
fn case_label_value(name : String) -> Int64? {
  let prefix = "__kimicc_case_"
  guard name.has_prefix(prefix) else { return None }
  let mut value : Int64 = 0
  let mut negative = false
  let mut digits = 0
  for i = prefix.length(); i < name.length(); i = i + 1 {
    let ch = name[i]
    if ch is ('0'..='9') {
      value = value * 10L + (ch.to_int() - '0').to_int64()
      digits += 1
    } else if ch is '-' && digits == 0 && !negative {
      negative = true
    } else {
      break
    }
  }
  guard digits > 0 else { return None }
  Some(if negative { -value } else { value })
}

///|
/// Reports whether a label name is the parser's spelling of `default:`.
fn is_default_label_name(name : String) -> Bool {
  name is "default" || name.has_prefix("__kimicc_default_")
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
