///|
fn Parser::parse_stmt(self : Parser) -> Stmt {
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
    Int | Void | Char | Struct | Union | Signed | Unsigned | Short | Long | Float | Double | Enum => self.parse_var_decl_stmt()
    Ident(name) => {
      // Check if this is a label: name:
      let saved_pos = self.lexer.pos
      let saved_token = self.token
      self.advance()
      if self.token == Colon {
        self.advance()
        let stmt = self.parse_stmt()
        return Label(name, stmt)
      }
      self.lexer.pos = saved_pos
      self.token = saved_token
      // Check if this is a typedef'd type used for variable declaration
      if self.typedefs.contains(name) {
        // Peek: if next token after type parsing is an identifier, it's a declaration
        let saved_pos = self.lexer.pos
        let saved_token = self.token
        let _ty = self.parse_type()
        let is_decl = match self.token {
          Ident(_) => true
          Star => true
          _ => false
        }
        if is_decl {
          // Type already parsed, parse the rest of the declaration
          let ty = _ty
          let vname = match self.token {
            Ident(n) => { self.advance(); n }
            _ => abort("Expected variable name after typedef type")
          }
          let final_ty = if self.token == LBracket {
            self.advance()
            let size = match self.token {
              Number(n) => { self.advance(); n }
              _ => abort("Expected array size")
            }
            self.expect(RBracket)
            Array(ty, size)
          } else {
            ty
          }
          let init = if self.token == Assign {
            self.advance()
            Some(self.parse_expr())
          } else {
            None
          }
          self.expect(Semicolon)
          VarDecl(final_ty, vname, init)
        } else {
          self.lexer.pos = saved_pos
          self.token = saved_token
          self.parse_expr_stmt()
        }
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
            self.token == Struct || self.token == Union {
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
    let value = if self.token == Case {
      self.advance()
      match self.token {
        Number(n) => { self.advance(); Some(n) }
        _ => abort("Expected number in case label")
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
    cases.push((value, Compound(stmts)))
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
  let base_ty = self.parse_type()
  let decls = []
  // Parse first variable
  let name = match self.token {
    Ident(n) => { self.advance(); n }
    _ => abort("Expected variable name")
  }
  let final_ty = if self.token == LBracket {
    self.advance()
    let size_expr = self.parse_assign()
    self.expect(RBracket)
    let size = match fold_const(size_expr) {
      Some(n) => n
      None => 0
    }
    Array(base_ty, size)
  } else {
    base_ty
  }
  let init = if self.token == Assign {
    self.advance()
    Some(self.parse_expr())
  } else {
    None
  }
  decls.push(VarDecl(final_ty, name, init))
  // Parse additional variables: int a, *b, c[8];
  while self.token == Comma {
    self.advance()
    let mut vty = base_ty
    while self.token == Star {
      self.advance()
      vty = Pointer(vty)
    }
    let vname = match self.token {
      Ident(n) => { self.advance(); n }
      _ => abort("Expected variable name")
    }
    let vfinal_ty = if self.token == LBracket {
      self.advance()
      let size_expr = self.parse_assign()
      self.expect(RBracket)
      let size = match fold_const(size_expr) {
        Some(n) => n
        None => 0
      }
      Array(vty, size)
    } else {
      vty
    }
    let vinit = if self.token == Assign {
      self.advance()
      Some(self.parse_expr())
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
  self.expect(Semicolon)
  ExprStmt(expr)
}
