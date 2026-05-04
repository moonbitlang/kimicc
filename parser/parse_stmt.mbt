///|
fn Parser::skip_brace_initializer(self : Parser) -> Unit {
  if self.token == LBrace {
    let mut depth = 1
    self.advance()
    while depth > 0 && self.token != EOF {
      if self.token == LBrace { depth += 1 }
      else if self.token == RBrace { depth -= 1 }
      if depth > 0 { self.advance() } else { self.advance(); break }
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
    Semicolon => { self.advance(); ExprStmt(Expr::Number(0)) }
    Int | Void | Char | Struct | Union | Signed | Unsigned | Short | Long | Float | Double | Bool | Enum | Const | Restrict | Volatile | Extern | Static | Inline | Register | Auto => self.parse_var_decl_stmt()
    Typedef => { self.parse_typedef(); ExprStmt(Expr::Number(0)) }
    Case => {
      self.advance()
      let expr = self.parse_assign()
      let value = match fold_const(expr) {
        Some(n) => n
        None => match expr {
          Var(name) => if self.enum_constants.contains(name) {
            self.enum_constants[name]
          } else {
            0
          }
          _ => 0
        }
      }
      self.expect(Colon)
      let stmt = self.parse_stmt()
      Label("case_" + value.to_string(), stmt)
    }
    Default => {
      self.advance()
      self.expect(Colon)
      let stmt = self.parse_stmt()
      Label("default", stmt)
    }
    Ident(name) => {
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
  } else if self.token == Int || self.token == Void || self.token == Char ||
            self.token == Struct || self.token == Union || self.token == Signed ||
            self.token == Unsigned || self.token == Short || self.token == Long ||
            self.token == Float || self.token == Double || self.token == Bool ||
            self.token == Enum || self.token == Const || self.token == Restrict ||
            self.token == Volatile || self.token == Extern || self.token == Static ||
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
  let update = if self.token == RParen {
    None
  } else {
    Some(self.parse_expr())
  }
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
  // Post-process statements to group by case/default labels
  let cases = []
  let mut current_stmts = []
  let mut current_value = None
  fn flush_case(value : Int?, stmts : Array[Stmt]) -> Unit {
    if stmts.length() > 0 || value.is_some() {
      cases.push((value, Compound(stmts)))
    }
  }
  for stmt in stmts {
    match stmt {
      Label(name, body) => {
        if name.starts_with("case_") {
          flush_case(current_value, current_stmts)
          current_stmts = []
          let mut case_value = 0
          let mut negative = false
          for i = 5; i < name.length(); i = i + 1 {
            let ch = name[i]
            if ch >= '0' && ch <= '9' {
              case_value = case_value * 10 + (ch.to_int() - '0'.to_int())
            } else if ch == '-' && i == 5 {
              negative = true
            }
          }
          if negative { case_value = -case_value }
          current_value = Some(case_value)
          // The body of the case label is the first statement of the case
          current_stmts.push(body)
        } else if name == "default" {
          flush_case(current_value, current_stmts)
          current_stmts = []
          current_value = None
          current_stmts.push(body)
        } else {
          // Regular label inside a case
          current_stmts.push(stmt)
        }
      }
      _ => current_stmts.push(stmt)
    }
  }
  flush_case(current_value, current_stmts)
  Switch(expr, cases)
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
    let _ = self.parse_expr()
    self.expect(Semicolon)
    return Goto("*computed*")
  }
  let name = match self.token {
    Ident(n) => { self.advance(); n }
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
  self.expect(LBrace)
  let stmts = []
  while self.token != RBrace {
    stmts.push(self.parse_stmt())
  }
  self.expect(RBrace)
  Compound(stmts)
}

///|
fn Parser::parse_var_decl_stmt(self : Parser) -> Stmt {
  let spec = self.parse_decl_specifiers()
  // Local struct/union/enum definition without variable: struct Foo { ... };
  if self.token == Semicolon {
    self.advance()
    return ExprStmt(Expr::Number(0))
  }
  let decls = []
  // Parse first declarator
  let decl = self.parse_declarator(spec.base_type)
  // Local function prototype inside a function body: int foo(void);
  if decl.is_func_decl && self.token == Semicolon {
    self.expect(Semicolon)
    return ExprStmt(Expr::Number(0))
  }
  let init = if self.token == Assign {
    self.advance()
    if self.token == LBrace {
      self.skip_brace_initializer()
      Some(Expr::Number(0))
    } else {
      Some(self.parse_assign())
    }
  } else {
    None
  }
  decls.push(VarDecl(decl.ty, decl.name, init))
  // Parse additional variables: int a, *b, c[8], (*fp)(void);
  while self.token == Comma {
    self.advance()
    let extra_decl = self.parse_declarator(spec.base_type)
    let extra_init = if self.token == Assign {
      self.advance()
      if self.token == LBrace {
        self.skip_brace_initializer()
        Some(Expr::Number(0))
      } else {
        Some(self.parse_assign())
      }
    } else {
      None
    }
    decls.push(VarDecl(extra_decl.ty, extra_decl.name, extra_init))
  }
  self.expect(Semicolon)
  if decls.length() == 1 {
    decls[0]
  } else {
    Compound(decls)
  }
}

///|
fn Parser::parse_expr_stmt(self : Parser) -> Stmt {
  let expr = self.parse_expr()
  self.expect(Semicolon)
  ExprStmt(expr)
}
