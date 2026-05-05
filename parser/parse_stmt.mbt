///|
fn Parser::skip_brace_initializer(self : Parser) -> Unit {
  if self.token == LBrace {
    let mut depth = 1
    self.advance()
    while depth > 0 && self.token != EOF {
      if self.token == LBrace {
        depth += 1
      } else if self.token == RBrace {
        depth -= 1
      }
      if depth > 0 {
        self.advance()
      } else {
        self.advance()
        break
      }
    }
  }
}

///|
/// Parse expressions inside a brace initializer: { expr1, expr2, ... }
fn Parser::parse_brace_init_exprs(
  self : Parser,
  flatten_nested? : Bool = false,
) -> Array[Expr] {
  let exprs = []
  self.expect(LBrace)
  while self.token != RBrace && self.token != EOF {
    if self.token == LBrace {
      if flatten_nested {
        // Recursively parse nested brace initializer and wrap as Expr::Array
        let nested = self.parse_brace_init_exprs(flatten_nested=true)
        exprs.push(Expr::Array(nested))
      } else {
        // Nested initializer: skip for now, treat as zero
        self.skip_brace_initializer()
        exprs.push(Expr::Number(0))
      }
    } else if self.token == LBracket || self.token == Dot {
      // Designated initializer ([index] = val or .field = val): skip rest
      self.skip_remaining_brace_initializer()
      break
    } else {
      exprs.push(self.parse_assign())
    }
    if self.token == Comma {
      self.advance()
    }
  }
  self.expect(RBrace)
  exprs
}

///|
/// Skip tokens until matching RBrace at current depth (does not consume RBrace)
fn Parser::skip_remaining_brace_initializer(self : Parser) -> Unit {
  let mut depth = 1
  while depth > 0 && self.token != EOF {
    self.advance()
    if self.token == LBrace {
      depth += 1
    } else if self.token == RBrace {
      depth -= 1
    }
  }
}

///|
fn Parser::parse_stmt(self : Parser) -> Stmt {
  // Skip __extension__ before statements
  while self.token == Ident("__extension__") {
    self.advance()
  }
  match self.token {
    If => self.parse_if_stmt()
    While => self.parse_while_stmt()
    For => self.parse_for_stmt()
    Do => self.parse_do_while_stmt()
    Switch => self.parse_switch_stmt()
    Break => self.parse_break_stmt()
    Continue => self.parse_continue_stmt()
    Goto => self.parse_goto_stmt()
    Return => self.parse_return_stmt()
    LBrace => self.parse_compound_stmt()
    Semicolon => {
      self.advance()
      ExprStmt(Expr::Number(0))
    }
    Int
    | Void
    | Char
    | Struct
    | Union
    | Signed
    | Unsigned
    | Short
    | Long
    | Float
    | Double
    | Bool
    | Enum
    | Const
    | Restrict
    | Volatile
    | Extern
    | Static
    | Inline
    | Register
    | Auto => self.parse_var_decl_stmt()
    Typedef => {
      self.parse_typedef()
      ExprStmt(Expr::Number(0))
    }
    Case => {
      self.advance()
      let expr = self.parse_assign()
      let value = match self.fold_const(expr) {
        Some(n) => n
        None =>
          match expr {
            Var(name) =>
              if self.enum_constants.contains(name) {
                self.enum_constants[name]
              } else {
                0
              }
            _ => 0
          }
      }
      self.expect(Colon)
      let stmt = self.parse_stmt()
      let label = self.fresh_case_label(value)
      Label(label, stmt)
    }
    Default => {
      self.advance()
      self.expect(Colon)
      let stmt = self.parse_stmt()
      let label = self.fresh_default_label()
      Label(label, stmt)
    }
    Ident(name) => {
      // Handle GCC inline assembly: asm volatile ("..." ::: "memory");
      if name == "asm" || name == "__asm__" || name == "__asm" {
        self.advance()
        // Skip optional volatile, goto, etc.
        while self.token == Volatile ||
              self.token == Ident("__volatile__") ||
              self.token == Ident("goto") {
          self.advance()
        }
        // Skip the asm body in parentheses
        if self.token == LParen {
          let mut depth = 1
          self.advance()
          while depth > 0 && self.token != EOF {
            if self.token == LParen {
              depth += 1
            } else if self.token == RParen {
              depth -= 1
            }
            if depth > 0 {
              self.advance()
            } else {
              self.advance()
              break
            }
          }
        }
        self.expect(Semicolon)
        return ExprStmt(Expr::Number(0))
      }
      // Handle __attribute__((...)); as a no-op statement
      if name == "__attribute__" || name == "__attribute" {
        self.advance()
        if self.token == LParen {
          let mut depth = 1
          self.advance()
          while depth > 0 && self.token != EOF {
            if self.token == LParen {
              depth += 1
            } else if self.token == RParen {
              depth -= 1
            }
            if depth > 0 {
              self.advance()
            } else {
              self.advance()
              break
            }
          }
        }
        self.expect(Semicolon)
        return ExprStmt(Expr::Number(0))
      }
      // Check if this is a label: name:
      let saved_pos = self.lexer.pos
      let saved_token = self.token
      self.advance()
      if self.token == Colon {
        self.advance()
        // If labeled statement is case/default, don't consume it
        // Let parse_switch_stmt handle it
        if self.token == Case || self.token == Default {
          return Label(name, ExprStmt(Expr::Number(0)))
        }
        let stmt = self.parse_stmt()
        return Label(name, stmt)
      }
      self.lexer.pos = saved_pos
      self.token = saved_token
      // Check if this is a typedef'd type used for variable declaration
      if self.typedefs.contains(name) {
        self.parse_var_decl_stmt()
      } else {
        self.parse_expr_stmt()
      }
    }
    _ => self.parse_expr_stmt()
  }
}

///|
fn Parser::parse_if_stmt(self : Parser) -> Stmt {
  self.advance() // if
  self.expect(LParen)
  let cond = self.parse_expr()
  if self.token != RParen {

  }
  self.expect(RParen)
  let then_ = self.parse_stmt()
  let else_ = if self.token == Else {
    self.advance()
    Some(self.parse_stmt())
  } else {
    None
  }
  If(cond, then_, else_)
}

///|
fn Parser::parse_while_stmt(self : Parser) -> Stmt {
  self.advance() // while
  self.expect(LParen)
  let cond = self.parse_expr()
  self.expect(RParen)
  let body = self.parse_stmt()
  While(cond, body)
}

///|
fn Parser::parse_for_stmt(self : Parser) -> Stmt {
  self.advance() // for
  self.expect(LParen)
  // Parse init: can be empty, a declaration, or an expression
  let init = if self.token == Semicolon {
    self.advance()
    None
  } else if self.token == Int ||
    self.token == Void ||
    self.token == Char ||
    self.token == Struct ||
    self.token == Union ||
    self.token == Signed ||
    self.token == Unsigned ||
    self.token == Short ||
    self.token == Long ||
    self.token == Float ||
    self.token == Double ||
    self.token == Bool ||
    self.token == Enum ||
    self.token == Const ||
    self.token == Restrict ||
    self.token == Volatile ||
    self.token == Extern ||
    self.token == Static ||
    self.token == Inline {
    Some(self.parse_var_decl_stmt())
  } else {
    let is_typedef = match self.token {
      Ident(name) => self.typedefs.contains(name)
      _ => false
    }
    if is_typedef {
      Some(self.parse_var_decl_stmt())
    } else {
      let expr = self.parse_expr()
      self.expect(Semicolon)
      Some(ExprStmt(expr))
    }
  }
  // Parse condition
  let cond = if self.token == Semicolon {
    self.advance()
    Expr::Number(1) // always true
  } else {
    let expr = self.parse_expr()
    self.expect(Semicolon)
    expr
  }
  // Parse update
  let update = if self.token == RParen { None } else { Some(self.parse_expr()) }
  self.expect(RParen)
  let body = self.parse_stmt()
  For(init, cond, update, body)
}

///|
fn Parser::parse_do_while_stmt(self : Parser) -> Stmt {
  self.advance() // do
  let body = self.parse_stmt()
  self.expect(While)
  self.expect(LParen)
  let cond = self.parse_expr()
  self.expect(RParen)
  self.expect(Semicolon)
  DoWhile(cond, body)
}

///|
fn Parser::parse_continue_stmt(self : Parser) -> Stmt {
  self.advance() // continue
  self.expect(Semicolon)
  Continue
}

///|
fn extract_case_value(name : String) -> Int64? {
  let prefix_len = if name.starts_with("__kimicc_case_") {
    "__kimicc_case_".length()
  } else if name.starts_with("case_") {
    5
  } else {
    return None
  }
  let mut case_value : Int64 = 0
  let mut negative = false
  let mut saw_digit = false
  for i = prefix_len; i < name.length(); i = i + 1 {
    let ch = name[i]
    if ch >= '0' && ch <= '9' {
      saw_digit = true
      case_value = case_value * 10 + (ch.to_int() - '0'.to_int()).to_int64()
    } else if ch == '-' && i == prefix_len {
      negative = true
    } else if saw_digit {
      break
    }
  }
  if negative {
    case_value = -case_value
  }
  Some(case_value)
}

///|
fn is_default_label(name : String) -> Bool {
  name == "default" || name.starts_with("__kimicc_default_")
}

///|
fn Parser::fresh_case_label(self : Parser, value : Int64) -> String {
  let label = "__kimicc_case_" +
    value.to_string() +
    "_" +
    self.case_label_counter.to_string()
  self.case_label_counter += 1
  label
}

///|
fn Parser::fresh_default_label(self : Parser) -> String {
  let label = "__kimicc_default_" + self.case_label_counter.to_string()
  self.case_label_counter += 1
  label
}

///|
fn collect_switch_cases(stmt : Stmt, cases : Array[(Int64?, String)]) -> Unit {
  match stmt {
    Label(name, body) => {
      match extract_case_value(name) {
        Some(value) => cases.push((Some(value), name))
        None => if is_default_label(name) { cases.push((None, name)) }
      }
      collect_switch_cases(body, cases)
    }
    Compound(stmts) | StmtList(stmts) =>
      for s in stmts {
        collect_switch_cases(s, cases)
      }
    If(_, then_, else_) => {
      collect_switch_cases(then_, cases)
      match else_ {
        Some(s) => collect_switch_cases(s, cases)
        None => ()
      }
    }
    While(_, body) | DoWhile(_, body) => collect_switch_cases(body, cases)
    For(init, _, _, body) => {
      match init {
        Some(s) => collect_switch_cases(s, cases)
        None => ()
      }
      collect_switch_cases(body, cases)
    }
    // A nested switch owns its own case/default labels.
    Switch(_, _, _) => ()
    _ => ()
  }
}

///|
fn Parser::parse_switch_stmt(self : Parser) -> Stmt {
  self.advance() // switch
  self.expect(LParen)
  let expr = self.parse_expr()
  self.expect(RParen)
  self.expect(LBrace)
  let stmts = []
  while self.token != RBrace {
    stmts.push(self.parse_stmt())
  }
  self.expect(RBrace)
  let body = Compound(stmts)
  let cases = []
  collect_switch_cases(body, cases)
  Switch(expr, body, cases)
}

///|
fn Parser::parse_break_stmt(self : Parser) -> Stmt {
  self.advance() // break
  self.expect(Semicolon)
  Break
}

///|
fn Parser::parse_goto_stmt(self : Parser) -> Stmt {
  self.advance() // goto
  if self.token == Star {
    // Computed goto: goto *expr;
    self.advance() // consume *
    let expr = self.parse_expr()
    self.expect(Semicolon)
    return ComputedGoto(expr)
  }
  let name = match self.token {
    Ident(n) => {
      self.advance()
      n
    }
    _ => abort("Expected label name after goto")
  }
  self.expect(Semicolon)
  Goto(name)
}

///|
fn Parser::parse_return_stmt(self : Parser) -> Stmt {
  self.advance() // return
  let expr = if self.token == Semicolon {
    None
  } else {
    Some(self.parse_expr())
  }
  self.expect(Semicolon)
  Return(expr)
}

///|
fn Parser::parse_compound_stmt(self : Parser) -> Stmt {
  let saved_value_types = self.value_types.copy()
  self.expect(LBrace)
  let stmts = []
  while self.token != RBrace {
    stmts.push(self.parse_stmt())
  }
  self.expect(RBrace)
  self.value_types = saved_value_types
  Compound(stmts)
}

///|
/// Helper to register a function-local static variable as a global.
/// Returns the mangled global name and adds the mapping to static_locals.
fn Parser::register_static_local(self : Parser, name : String) -> String {
  let mangled = if self.current_func_name == "" {
    name
  } else {
    "_" + self.current_func_name + "_" + name
  }
  self.static_locals[name] = mangled
  mangled
}

///|
/// Helper to parse an initializer into GlobalInit for static locals.
fn Parser::parse_static_initializer(
  self : Parser,
  ty : Type,
) -> (Type, GlobalInit?) {
  if self.token == Assign {
    self.advance()
    if self.token == LBrace {
      let init_exprs = self.parse_brace_init_exprs(flatten_nested=true)
      let init_count = init_exprs.length()
      let final_ty = match ty {
        Array(elem_ty, 0) => Type::Array(elem_ty, init_count)
        other => other
      }
      (final_ty, Some(GlobalInit::Array(init_exprs)))
    } else {
      let expr = self.parse_assign()
      match (ty, expr) {
        (Array(elem_ty, 0), Expr::String(s)) => {
          let len = s.length()
          let arr_ty = Type::Array(elem_ty, len + 1)
          let init_exprs = Array::make(len + 1, Expr::Number(0))
          for i = 0; i < len; i = i + 1 {
            init_exprs[i] = Expr::Number(s[i].to_int().to_int64())
          }
          init_exprs[len] = Expr::Number(0)
          (arr_ty, Some(GlobalInit::Array(init_exprs)))
        }
        _ => (ty, Some(GlobalInit::Scalar(expr)))
      }
    }
  } else {
    (ty, None)
  }
}

///|
fn Parser::push_struct_init_assignments(
  self : Parser,
  stmts : Array[Stmt],
  target : Expr,
  ty : Type,
  init_exprs : Array[Expr],
) -> Unit {
  let struct_name = match ty {
    Struct(n) | Union(n) => n
    _ => return
  }
  let fields = if self.struct_decls.contains(struct_name) {
    self.struct_decls[struct_name].fields
  } else {
    []
  }
  for i = 0; i < init_exprs.length() && i < fields.length(); i = i + 1 {
    let field_target = Expr::MemberAccess(target, fields[i].name)
    match (fields[i].ty, init_exprs[i]) {
      (Struct(_) | Union(_), Expr::Array(field_exprs)) =>
        self.push_struct_init_assignments(
          stmts,
          field_target,
          fields[i].ty,
          field_exprs,
        )
      (Struct(_) | Union(_), Expr::Number(0)) => ()
      _ => stmts.push(ExprStmt(Expr::Assign(field_target, init_exprs[i])))
    }
  }
}

///|
fn Parser::push_array_init_assignments(
  self : Parser,
  stmts : Array[Stmt],
  name : String,
  ty : Type,
  init_exprs : Array[Expr],
) -> Unit {
  let elem_ty = match ty {
    Array(elem, _) => elem
    _ => return
  }
  for i = 0; i < init_exprs.length(); i = i + 1 {
    let elem = Expr::ArrayAccess(Expr::Var(name), Expr::Number(i.to_int64()))
    match (elem_ty, init_exprs[i]) {
      (Struct(_) | Union(_), Expr::Array(field_exprs)) =>
        self.push_struct_init_assignments(stmts, elem, elem_ty, field_exprs)
      (Struct(_) | Union(_), Expr::Number(0)) => ()
      _ => stmts.push(ExprStmt(Expr::Assign(elem, init_exprs[i])))
    }
  }
}

///|
fn Parser::parse_var_decl_stmt(self : Parser) -> Stmt {
  let spec = self.parse_decl_specifiers()
  // Local struct/union/enum definition without variable: struct Foo { ... };
  if self.token == Semicolon {
    self.advance()
    return ExprStmt(Expr::Number(0))
  }
  let stmts = []
  // Parse first declarator
  let decl = self.parse_declarator(spec.base_type)
  let decl_ty = resolve_var_type(decl)
  // Local function prototype inside a function body: int foo(void);
  if decl.is_func_decl && self.token == Semicolon {
    self.expect(Semicolon)
    return ExprStmt(Expr::Number(0))
  }
  // Handle static / extern locals: promote to globals
  if spec.is_static || spec.is_extern {
    let mangled = if spec.is_static {
      self.register_static_local(decl.name)
    } else {
      // extern local: refers to an external global with the same name
      self.static_locals[decl.name] = decl.name
      decl.name
    }
    let (final_ty, init) = self.parse_static_initializer(decl_ty)
    if spec.is_static {
      self.globals.push({
        ty: final_ty,
        name: mangled,
        init,
        is_static: true,
        is_extern: false,
      })
    }
    self.remember_value_type(mangled, final_ty)
    self.remember_value_type(decl.name, final_ty)
    // Parse additional static/extern variables
    while self.token == Comma {
      self.advance()
      let extra_decl = self.parse_declarator(spec.base_type)
      let extra_decl_ty = resolve_var_type(extra_decl)
      let extra_mangled = if spec.is_static {
        self.register_static_local(extra_decl.name)
      } else {
        self.static_locals[extra_decl.name] = extra_decl.name
        extra_decl.name
      }
      let (extra_ty, extra_init) = self.parse_static_initializer(extra_decl_ty)
      if spec.is_static {
        self.globals.push({
          ty: extra_ty,
          name: extra_mangled,
          init: extra_init,
          is_static: true,
          is_extern: false,
        })
      }
      self.remember_value_type(extra_mangled, extra_ty)
      self.remember_value_type(extra_decl.name, extra_ty)
    }
    self.expect(Semicolon)
    return ExprStmt(Expr::Number(0))
  }
  // Handle initializer
  let ty = if self.token == Assign {
    self.advance()
    if self.token == LBrace {
      // For struct/union types, skip the brace initializer entirely
      // (we don't support struct field initializers yet)
      let is_struct = match decl_ty {
        Struct(_) | Union(_) => true
        _ => false
      }
      if is_struct {
        // Parse brace initializer expressions and create field assignments
        let init_exprs = self.parse_brace_init_exprs()
        stmts.push(VarDecl(decl_ty, decl.name, Some(Expr::Number(0))))
        self.push_struct_init_assignments(
          stmts,
          Expr::Var(decl.name),
          decl_ty,
          init_exprs,
        )
        decl_ty
      } else {
        let init_exprs = self.parse_brace_init_exprs(flatten_nested=true)
        let init_count = init_exprs.length()
        // Update array type if size was inferred
        let ty = match decl_ty {
          Array(elem_ty, 0) => Type::Array(elem_ty, init_count)
          other => other
        }
        stmts.push(VarDecl(ty, decl.name, Some(Expr::Number(0))))
        self.push_array_init_assignments(stmts, decl.name, ty, init_exprs)
        ty
      }
    } else {
      let expr = self.parse_assign()
      // Handle string literal initializer for char arrays: char s[] = "abc"
      match (decl_ty, expr) {
        (Array(elem_ty, 0), Expr::String(s)) => {
          let len = s.length()
          let arr_ty = Type::Array(elem_ty, len + 1) // +1 for null terminator
          stmts.push(VarDecl(arr_ty, decl.name, None))
          for i = 0; i < len; i = i + 1 {
            let ch = s[i]
            stmts.push(
              ExprStmt(
                Expr::Assign(
                  Expr::ArrayAccess(
                    Expr::Var(decl.name),
                    Expr::Number(i.to_int64()),
                  ),
                  Expr::Number(ch.to_int().to_int64()),
                ),
              ),
            )
          }
          // Null terminator
          stmts.push(
            ExprStmt(
              Expr::Assign(
                Expr::ArrayAccess(
                  Expr::Var(decl.name),
                  Expr::Number(len.to_int64()),
                ),
                Expr::Number(0),
              ),
            ),
          )
          arr_ty
        }
        _ => {
          stmts.push(VarDecl(decl_ty, decl.name, Some(expr)))
          decl_ty
        }
      }
    }
  } else {
    stmts.push(VarDecl(decl_ty, decl.name, None))
    decl_ty
  }
  self.remember_value_type(decl.name, ty)
  // Parse additional variables: int a, *b, c[8], (*fp)(void);
  while self.token == Comma {
    self.advance()
    let extra_decl = self.parse_declarator(spec.base_type)
    let extra_decl_ty = resolve_var_type(extra_decl)
    let mut remembered_extra_ty = extra_decl_ty
    if self.token == Assign {
      self.advance()
      if self.token == LBrace {
        let is_struct = match extra_decl_ty {
          Struct(_) | Union(_) => true
          _ => false
        }
        if is_struct {
          stmts.push(
            VarDecl(extra_decl_ty, extra_decl.name, Some(Expr::Number(0))),
          )
          let init_exprs = self.parse_brace_init_exprs()
          self.push_struct_init_assignments(
            stmts,
            Expr::Var(extra_decl.name),
            extra_decl_ty,
            init_exprs,
          )
        } else {
          let init_exprs = self.parse_brace_init_exprs(flatten_nested=true)
          let init_count = init_exprs.length()
          let extra_ty = match extra_decl_ty {
            Array(elem_ty, 0) => Type::Array(elem_ty, init_count)
            other => other
          }
          remembered_extra_ty = extra_ty
          stmts.push(VarDecl(extra_ty, extra_decl.name, Some(Expr::Number(0))))
          self.push_array_init_assignments(
            stmts,
            extra_decl.name,
            extra_ty,
            init_exprs,
          )
        }
      } else {
        let expr = self.parse_assign()
        match (extra_decl_ty, expr) {
          (Array(elem_ty, 0), Expr::String(s)) => {
            let len = s.length()
            let arr_ty = Type::Array(elem_ty, len + 1)
            remembered_extra_ty = arr_ty
            stmts.push(VarDecl(arr_ty, extra_decl.name, None))
            for i = 0; i < len; i = i + 1 {
              let ch = s[i]
              stmts.push(
                ExprStmt(
                  Expr::Assign(
                    Expr::ArrayAccess(
                      Expr::Var(extra_decl.name),
                      Expr::Number(i.to_int64()),
                    ),
                    Expr::Number(ch.to_int().to_int64()),
                  ),
                ),
              )
            }
            stmts.push(
              ExprStmt(
                Expr::Assign(
                  Expr::ArrayAccess(
                    Expr::Var(extra_decl.name),
                    Expr::Number(len.to_int64()),
                  ),
                  Expr::Number(0),
                ),
              ),
            )
          }
          _ => stmts.push(VarDecl(extra_decl_ty, extra_decl.name, Some(expr)))
        }
      }
    } else {
      stmts.push(VarDecl(extra_decl_ty, extra_decl.name, None))
    }
    self.remember_value_type(extra_decl.name, remembered_extra_ty)
  }
  self.expect(Semicolon)
  if stmts.length() == 1 {
    stmts[0]
  } else {
    StmtList(stmts)
  }
}

///|
fn Parser::parse_expr_stmt(self : Parser) -> Stmt {
  let expr = self.parse_expr()
  self.expect(Semicolon)
  ExprStmt(expr)
}
