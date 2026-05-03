///|
fn Parser::parse_expr(self : Parser) -> Expr {
  self.parse_comma()
}

///|
fn Parser::parse_comma(self : Parser) -> Expr {
  let mut left = self.parse_assign()
  while true {
    match self.token {
      Comma => {
        self.advance()
        left = Binary(",", left, self.parse_assign())
      }
      _ => break
    }
  }
  left
}

///|
fn Parser::parse_assign(self : Parser) -> Expr {
  let expr = self.parse_ternary()
  let op = match self.token {
    Assign => "="
    PlusEq => "+="
    MinusEq => "-="
    StarEq => "*="
    SlashEq => "/="
    PercentEq => "%="
    BitOrEq => "|="
    AmpersandEq => "&="
    BitXorEq => "^="
    LShiftEq => "<<="
    RShiftEq => ">>="
    _ => ""
  }
  if op != "" {
    self.advance()
    let rhs = self.parse_assign()
    if is_lvalue(expr) {
      if op == "=" {
        Assign(expr, rhs)
      } else {
        let base_op = match op {
          "+=" => "+"
          "-=" => "-"
          "*=" => "*"
          "/=" => "/"
          "%=" => "%"
          "|=" => "|"
          "&=" => "&"
          "^=" => "^"
          "<<=" => "<<"
          ">>=" => ">>"
          _ => ""
        }
        Assign(expr, Binary(base_op, expr, rhs))
      }
    } else {
      abort("Invalid assignment target")
    }
  } else {
    expr
  }
}

///|
fn Parser::parse_ternary(self : Parser) -> Expr {
  let cond = self.parse_logical_or()
  if self.token == Question {
    self.advance()
    let then_expr = self.parse_ternary()
    self.expect(Colon)
    let else_expr = self.parse_ternary()
    Ternary(cond, then_expr, else_expr)
  } else {
    cond
  }
}

///|
fn Parser::parse_logical_or(self : Parser) -> Expr {
  let mut left = self.parse_logical_and()
  while true {
    match self.token {
      Or => {
        self.advance()
        left = Binary("||", left, self.parse_logical_and())
      }
      _ => break
    }
  }
  left
}

///|
fn Parser::parse_logical_and(self : Parser) -> Expr {
  let mut left = self.parse_bitwise_or()
  while true {
    match self.token {
      And => {
        self.advance()
        left = Binary("&&", left, self.parse_bitwise_or())
      }
      _ => break
    }
  }
  left
}

///|
fn Parser::parse_bitwise_or(self : Parser) -> Expr {
  let mut left = self.parse_bitwise_xor()
  while true {
    match self.token {
      BitOr => {
        self.advance()
        left = Binary("|", left, self.parse_bitwise_xor())
      }
      _ => break
    }
  }
  left
}

///|
fn Parser::parse_bitwise_xor(self : Parser) -> Expr {
  let mut left = self.parse_bitwise_and()
  while true {
    match self.token {
      BitXor => {
        self.advance()
        left = Binary("^", left, self.parse_bitwise_and())
      }
      _ => break
    }
  }
  left
}

///|
fn Parser::parse_bitwise_and(self : Parser) -> Expr {
  let mut left = self.parse_equality()
  while true {
    match self.token {
      Ampersand => {
        self.advance()
        left = Binary("&", left, self.parse_equality())
      }
      _ => break
    }
  }
  left
}

///|
fn is_lvalue(expr : Expr) -> Bool {
  match expr {
    Var(_) => true
    MemberAccess(_, _) => true
    Deref(_) => true
    ArrayAccess(_, _) => true
    _ => false
  }
}

///|
fn Parser::parse_equality(self : Parser) -> Expr {
  let mut left = self.parse_relational()
  while true {
    match self.token {
      Eq => {
        self.advance()
        left = Binary("==", left, self.parse_relational())
      }
      Ne => {
        self.advance()
        left = Binary("!=", left, self.parse_relational())
      }
      _ => break
    }
  }
  left
}

///|
fn Parser::parse_relational(self : Parser) -> Expr {
  let mut left = self.parse_shift()
  while true {
    match self.token {
      Lt => {
        self.advance()
        left = Binary("<", left, self.parse_shift())
      }
      Le => {
        self.advance()
        left = Binary("<=", left, self.parse_shift())
      }
      Gt => {
        self.advance()
        left = Binary(">", left, self.parse_shift())
      }
      Ge => {
        self.advance()
        left = Binary(">=", left, self.parse_shift())
      }
      _ => break
    }
  }
  left
}

///|
fn Parser::parse_shift(self : Parser) -> Expr {
  let mut left = self.parse_additive()
  while true {
    match self.token {
      LShift => {
        self.advance()
        left = Binary("<<", left, self.parse_additive())
      }
      RShift => {
        self.advance()
        left = Binary(">>", left, self.parse_additive())
      }
      _ => break
    }
  }
  left
}

///|
fn Parser::parse_additive(self : Parser) -> Expr {
  let mut left = self.parse_multiplicative()
  while true {
    match self.token {
      Plus => {
        self.advance()
        left = Binary("+", left, self.parse_multiplicative())
      }
      Minus => {
        self.advance()
        left = Binary("-", left, self.parse_multiplicative())
      }
      _ => break
    }
  }
  left
}

///|
fn Parser::parse_multiplicative(self : Parser) -> Expr {
  let mut left = self.parse_unary()
  while true {
    match self.token {
      Star => {
        self.advance()
        left = Binary("*", left, self.parse_unary())
      }
      Slash => {
        self.advance()
        left = Binary("/", left, self.parse_unary())
      }
      Percent => {
        self.advance()
        left = Binary("%", left, self.parse_unary())
      }
      _ => break
    }
  }
  left
}

///|
fn Parser::parse_unary(self : Parser) -> Expr {
  match self.token {
    Minus => {
      self.advance()
      if self.token == Minus {
        // Prefix --
        self.advance()
        let expr = self.parse_unary()
        if is_lvalue(expr) {
          PrefixDec(expr)
        } else {
          abort("-- requires an lvalue")
        }
      } else {
        Unary("-", self.parse_unary())
      }
    }
    Plus => {
      self.advance()
      if self.token == Plus {
        // Prefix ++
        self.advance()
        let expr = self.parse_unary()
        if is_lvalue(expr) {
          PrefixInc(expr)
        } else {
          abort("++ requires an lvalue")
        }
      } else {
        // Unary + is a no-op
        self.parse_unary()
      }
    }
    BitNot => {
      self.advance()
      Unary("~", self.parse_unary())
    }
    Not => {
      self.advance()
      Unary("!", self.parse_unary())
    }
    Star => {
      self.advance()
      Deref(self.parse_unary())
    }
    Ampersand => {
      self.advance()
      AddrOf(self.parse_unary())
    }
    Sizeof => {
      self.advance()
      if self.token == LParen {
        // Could be sizeof(type) or sizeof(expr)
        let saved_pos = self.lexer.pos
        let saved_token = self.token
        self.advance() // past (
        // Try to parse as type
        let is_type = match self.token {
          Int | Void | Char | Struct | Union | Signed | Unsigned | Short | Long | Const | Restrict | Volatile => true
          Ident(name) => self.typedefs.contains(name)
          _ => false
        }
        if is_type {
          let ty = self.parse_type()
          if self.token == RParen {
            self.advance()
            Sizeof(ty)
          } else {
            // Not a type after all, restore and parse as expression
            self.lexer.pos = saved_pos
            self.token = saved_token
            self.advance() // past (
            let expr = self.parse_expr()
            self.expect(RParen)
            SizeofExpr(expr)
          }
        } else {
          // sizeof(expr)
          let expr = self.parse_expr()
          self.expect(RParen)
          SizeofExpr(expr)
        }
      } else {
        // sizeof expr
        SizeofExpr(self.parse_unary())
      }
    }
    LParen => {
      // Could be a cast: (type)expr or parenthesized expr: (expr)
      let saved_pos = self.lexer.pos
      let saved_token = self.token
      self.advance() // past (
      // Try to parse as type
      let is_cast = match self.token {
        Int | Void | Char | Struct | Union | Signed | Unsigned | Short | Long | Const | Restrict | Volatile => true
        Ident(name) => self.typedefs.contains(name)
        _ => false
      }
      if is_cast {
        // It's a cast
        let ty = self.parse_type()
        if self.token == RParen {
          self.advance() // past )
          Cast(ty, self.parse_unary())
        } else {
          // Not a cast after all, restore and parse as parenthesized expr
          self.lexer.pos = saved_pos
          self.token = saved_token
          self.advance() // past (
          let expr = self.parse_expr()
          self.expect(RParen)
          expr
        }
      } else {
        // Parenthesized expression
        let expr = self.parse_expr()
        self.expect(RParen)
        self.apply_postfix(expr)
      }
    }
    _ => self.parse_postfix()
  }
}

///|
fn Parser::apply_postfix(self : Parser, expr_ : Expr) -> Expr {
  let mut expr = expr_
  while true {
    match self.token {
      LBracket => {
        self.advance()
        let index = self.parse_expr()
        self.expect(RBracket)
        expr = ArrayAccess(expr, index)
      }
      Dot => {
        self.advance()
        match self.token {
          Ident(name) => {
            self.advance()
            expr = MemberAccess(expr, name)
          }
          _ => abort("Expected field name after .")
        }
      }
      Arrow => {
        self.advance()
        match self.token {
          Ident(name) => {
            self.advance()
            expr = MemberAccess(Deref(expr), name)
          }
          _ => abort("Expected field name after ->")
        }
      }
      Plus => {
        // Handle postfix ++
        let saved_pos = self.lexer.pos
        let saved_token = self.token
        self.advance()
        if self.token == Plus {
          self.advance()
          if is_lvalue(expr) {
            expr = PostfixInc(expr)
          } else {
            abort("++ requires an lvalue")
          }
        } else {
          self.lexer.pos = saved_pos
          self.token = saved_token
          break
        }
      }
      Minus => {
        // Handle postfix --
        let saved_pos = self.lexer.pos
        let saved_token = self.token
        self.advance()
        if self.token == Minus {
          self.advance()
          if is_lvalue(expr) {
            expr = PostfixDec(expr)
          } else {
            abort("-- requires an lvalue")
          }
        } else {
          self.lexer.pos = saved_pos
          self.token = saved_token
          break
        }
      }
      _ => break
    }
  }
  expr
}

///|
fn Parser::parse_postfix(self : Parser) -> Expr {
  let expr = self.parse_primary()
  self.apply_postfix(expr)
}

///|
fn Parser::parse_primary(self : Parser) -> Expr {
  match self.token {
    Number(n) => {
      self.advance()
      Number(n)
    }
    String(s) => {
      self.advance()
      String(s)
    }
    Ident(name) => {
      self.advance()
      if self.token == LParen {
        self.advance()
        let args = []
        if self.token != RParen {
          args.push(self.parse_assign())
          while self.token == Comma {
            self.advance()
            args.push(self.parse_assign())
          }
        }
        self.expect(RParen)
        Call(name, args)
      } else if self.enum_constants.contains(name) {
        Number(self.enum_constants[name])
      } else {
        Var(name)
      }
    }
    LParen => {
      self.advance()
      let expr = self.parse_expr()
      self.expect(RParen)
      expr
    }
    _ => {
      abort("Unexpected token: " + self.token.to_string())
    }
  }
}
