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
    Int | Void | Char | Struct | Union | Signed | Unsigned | Short | Long | Float | Double | Bool | Enum | Const | Restrict | Volatile | Extern | Static | Inline => self.parse_var_decl_stmt()
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
    _ => {
      let pos = self.lexer.pos
      let near_end = @math.minimum(pos + 40, self.lexer.input.length())
      let near = self.lexer.input[pos:near_end].to_string()
      println("parse_stmt fallback: token=" + self.token.to_string() + " near=[" + near + "]")
      self.parse_expr_stmt()
    }
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
  let cases = []
  while self.token != RBrace {
    let pos = self.lexer.pos
    let near_end = @math.minimum(pos + 40, self.lexer.input.length())
    let near = self.lexer.input[pos:near_end].to_string()
    println("switch loop: token=" + self.token.to_string() + " near=[" + near + "]")
    // Handle labels that precede case/default (e.g., _default: default:)
    let label_name = if self.token is Ident(name) {
      let saved_pos = self.lexer.pos
      let saved_token = self.token
      self.advance()
      if self.token == Colon {
        self.advance()
        Some(name)
      } else {
        self.lexer.pos = saved_pos
        self.token = saved_token
        None
      }
    } else {
      None
    }
    let value = if self.token == Case {
      self.advance()
      let expr = self.parse_assign()
      match fold_const(expr) {
        Some(n) => Some(n)
        None => match expr {
          Var(name) => if self.enum_constants.contains(name) {
            Some(self.enum_constants[name])
          } else {
            let pos = self.lexer.pos
            let near_end = @math.minimum(pos + 40, self.lexer.input.length())
            let near = self.lexer.input[pos:near_end].to_string()
            abort("Expected constant in case label: " + name + " near=" + near)
          }
          _ => {
            let pos = self.lexer.pos
            let near_end = @math.minimum(pos + 40, self.lexer.input.length())
            let near = self.lexer.input[pos:near_end].to_string()
            abort("Expected constant in case label, got complex expr near=" + near)
          }
        }
      }
    } else if self.token == Default {
      self.advance()
      None
    } else {
      abort("Expected case or default in switch, got " + self.token.to_string())
    }
    self.expect(Colon)
    let stmts = []
    while self.token != Case && self.token != Default && self.token != RBrace {
      stmts.push(self.parse_stmt())
    }
    let body = Compound(stmts)
    let stmt = match label_name {
      Some(name) => Label(name, body)
      None => body
    }
    cases.push((value, stmt))
  }
  self.expect(RBrace)
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
  let pos = self.lexer.pos
  let near_end = @math.minimum(pos + 40, self.lexer.input.length())
  let near = self.lexer.input[pos:near_end].to_string()
  println("parse_var_decl_stmt: token=" + self.token.to_string() + " near=[" + near + "]")
  let base_ty = self.parse_type()
  let decls = []
  // Parse first variable
  let mut final_ty = base_ty
  let name = if self.token == LParen {
    // Function pointer declaration: int (*name)(...);
    let (fty, fname) = self.parse_func_ptr_decl()
    final_ty = fty
    fname
  } else {
    match self.token {
      Ident(n) => { self.advance(); n }
      _ => abort("Expected variable name")
    }
  }
  while self.token == LBracket {
    self.advance()
    if self.token == RBracket {
      self.advance()
      final_ty = Array(final_ty, 0)
    } else {
      let size_expr = self.parse_assign()
      self.expect(RBracket)
      let size = match fold_const(size_expr) {
        Some(n) => n
        None => 0
      }
      final_ty = Array(final_ty, size)
    }
  }
  // Local function declaration inside a function body: int foo(void);
  if self.token == LParen {
    let mut depth = 1
    self.advance()
    while depth > 0 && self.token != EOF {
      if self.token == LParen { depth += 1 }
      else if self.token == RParen { depth -= 1 }
      if depth > 0 { self.advance() } else { self.advance(); break }
    }
    self.skip_attributes()
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
  decls.push(VarDecl(final_ty, name, init))
  // Parse additional variables: int a, *b, c[8], (*fp)(void);
  while self.token == Comma {
    self.advance()
    let mut vty = base_ty
    let vname = if self.token == LParen {
      let (fty, fname) = self.parse_func_ptr_decl()
      vty = fty
      fname
    } else {
      while self.token == Star {
        self.advance()
        vty = Pointer(vty)
      }
      match self.token {
        Ident(n) => { self.advance(); n }
        _ => abort("Expected variable name")
      }
    }
    let mut vfinal_ty = vty
    while self.token == LBracket {
      self.advance()
      if self.token == RBracket {
        self.advance()
        vfinal_ty = Array(vfinal_ty, 0)
      } else {
        let size_expr = self.parse_assign()
        self.expect(RBracket)
        let size = match fold_const(size_expr) {
          Some(n) => n
          None => 0
        }
        vfinal_ty = Array(vfinal_ty, size)
      }
    }
    let vinit = if self.token == Assign {
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
    decls.push(VarDecl(vfinal_ty, vname, vinit))
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
  let pos = self.lexer.pos
  let near_end = @math.minimum(pos + 40, self.lexer.input.length())
  let near = self.lexer.input[pos:near_end].to_string()
  println("parse_expr_stmt: token=" + self.token.to_string() + " near=[" + near + "]")
  self.expect(Semicolon)
  ExprStmt(expr)
}
