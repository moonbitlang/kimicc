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
        CompoundAssign(base_op, expr, rhs)
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
    let then_expr = self.parse_expr()
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
  // Skip __extension__ before expressions
  while self.token == Ident("__extension__") {
    self.advance()
  }
  match self.token {
    Minus => {
      self.advance()
      Unary("-", self.parse_unary())
    }
    Plus => {
      self.advance()
      // Unary + is a no-op
      self.parse_unary()
    }
    PlusPlus => {
      self.advance()
      let expr = self.parse_unary()
      if is_lvalue(expr) {
        PrefixInc(expr)
      } else {
        abort("++ requires an lvalue")
      }
    }
    MinusMinus => {
      self.advance()
      let expr = self.parse_unary()
      if is_lvalue(expr) {
        PrefixDec(expr)
      } else {
        abort("-- requires an lvalue")
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
          | Volatile => true
          Ident("__typeof") => true
          Ident("__typeof__") => true
          Ident("typeof") => true
          Ident("_Atomic") => true
          Ident("_Alignas") => true
          Ident("alignas") => true
          Ident(name) => self.typedefs.contains(name)
          _ => false
        }
        if is_type {
          let ty = self.parse_type_name()
          if self.token == RParen {
            self.advance()
            Sizeof(ty)
          } else {
            // Not a type after all, restore and parse as unary-expression
            self.lexer.pos = saved_pos
            self.token = saved_token
            SizeofExpr(self.parse_unary())
          }
        } else {
          // sizeof unary-expression
          self.lexer.pos = saved_pos
          self.token = saved_token
          SizeofExpr(self.parse_unary())
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
        | Static
        | Extern
        | Inline => true
        Ident("_Float16") => true
        Ident("__int128") => true
        Ident("__int128_t") => true
        Ident("__uint128_t") => true
        Ident("_Atomic") => true
        Ident("_Alignas") => true
        Ident("alignas") => true
        Ident("__typeof") => true
        Ident("__typeof__") => true
        Ident("typeof") => true
        Ident(name) => self.typedefs.contains(name)
        _ => false
      }
      if is_cast {
        let ty = self.parse_type_name()
        if self.token == RParen {
          self.advance() // past )
          if self.token == LBrace {
            // Compound literal: (Type){ ... }
            let init_exprs = self.parse_compound_literal_init_exprs()
            let id = self.compound_literal_counter
            self.compound_literal_counter += 1
            self.apply_postfix(CompoundLiteral(ty, init_exprs, id))
          } else {
            self.apply_postfix(Cast(ty, self.parse_unary()))
          }
        } else {
          // Not a valid cast, restore and parse as parenthesized expr
          self.lexer.pos = saved_pos
          self.token = saved_token
          self.advance() // past (
          let expr = self.parse_expr()
          self.expect(RParen)
          self.apply_postfix(expr)
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
          _ =>
            abort("Expected field name after ., got " + self.token.to_string())
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
      PlusPlus => {
        self.advance()
        if is_lvalue(expr) {
          expr = PostfixInc(expr)
        } else {
          abort("++ requires an lvalue")
        }
      }
      MinusMinus => {
        self.advance()
        if is_lvalue(expr) {
          expr = PostfixDec(expr)
        } else {
          abort("-- requires an lvalue")
        }
      }
      LParen => {
        // Function call through expression: (expr)(args)
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
        expr = Call(expr, args)
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
fn generic_strip_type(ty : Type) -> Type {
  match ty {
    Aligned(inner, _) => generic_strip_type(inner)
    _ => ty
  }
}

///|
fn generic_control_type(ty : Type) -> Type {
  match generic_strip_type(ty) {
    Array(elem, _) => Pointer(elem)
    other => other
  }
}

///|
fn generic_types_compatible(control_ty : Type, assoc_ty : Type) -> Bool {
  generic_strip_type(control_ty) == generic_strip_type(assoc_ty)
}

///|
fn Parser::parse_generic_selection(self : Parser) -> Expr {
  self.expect(LParen)
  let control = self.parse_assign()
  let control_ty = generic_control_type(self.const_expr_type(control))
  let mut selected : Expr? = None
  let mut default_expr : Expr? = None
  while self.token == Comma {
    self.advance()
    match self.token {
      Default => {
        self.advance()
        self.expect(Colon)
        let expr = self.parse_assign()
        default_expr = Some(expr)
      }
      _ => {
        let assoc_ty = self.parse_type_name()
        self.expect(Colon)
        let expr = self.parse_assign()
        if selected is None && generic_types_compatible(control_ty, assoc_ty) {
          selected = Some(expr)
        }
      }
    }
  }
  self.expect(RParen)
  match selected {
    Some(expr) => expr
    None =>
      match default_expr {
        Some(expr) => expr
        None => abort("_Generic selection has no matching association")
      }
  }
}

///|
fn Parser::parse_builtin_choose_expr(self : Parser) -> Expr {
  self.expect(LParen)
  let cond = self.parse_assign()
  self.expect(Comma)
  let then_expr = self.parse_assign()
  self.expect(Comma)
  let else_expr = self.parse_assign()
  self.expect(RParen)
  match self.fold_const(cond) {
    Some(n) => if n != 0 { then_expr } else { else_expr }
    None => abort("__builtin_choose_expr condition must be constant")
  }
}

///|
fn Parser::parse_builtin_types_compatible_p(self : Parser) -> Expr {
  self.expect(LParen)
  let lhs_ty = self.parse_type_name()
  self.expect(Comma)
  let rhs_ty = self.parse_type_name()
  self.expect(RParen)
  if generic_types_compatible(lhs_ty, rhs_ty) {
    Number(1)
  } else {
    Number(0)
  }
}

///|
fn classify_type_code(ty : Type) -> Int64 {
  match generic_strip_type(ty) {
    Atomic(inner) => classify_type_code(inner)
    Void => 0
    Bool => 4
    Float | Double => 8
    Pointer(_) | Array(_, _) | FuncPtr(_, _, _) => 5
    Struct(_) => 12
    Union(_) => 13
    SChar
    | UChar
    | SShort
    | UShort
    | SInt
    | UInt
    | SLong
    | ULong
    | SLongLong
    | ULongLong
    | SInt128
    | UInt128 => 1
    Aligned(inner, _) => classify_type_code(inner)
  }
}

///|
fn Parser::parse_builtin_classify_type(self : Parser) -> Expr {
  self.expect(LParen)
  let expr = self.parse_assign()
  self.expect(RParen)
  Number(classify_type_code(self.const_expr_type(expr)))
}

///|
fn Parser::parse_primary(self : Parser) -> Expr {
  match self.token {
    Number(n) => {
      self.advance()
      Number(n)
    }
    FloatLiteral(v) => {
      self.advance()
      FloatLiteral(v)
    }
    String(s) => {
      self.advance()
      String(s)
    }
    Ident(name) => {
      self.advance()
      let resolved_name = if self.static_locals.contains(name) {
        self.static_locals[name]
      } else {
        name
      }
      if self.token == LParen {
        if name == "_Generic" {
          self.parse_generic_selection()
        } else if name == "__builtin_choose_expr" {
          self.parse_builtin_choose_expr()
        } else if name == "__builtin_types_compatible_p" {
          self.parse_builtin_types_compatible_p()
        } else if name == "__builtin_classify_type" {
          self.parse_builtin_classify_type()
        } else {
          self.advance()
          if name == "__builtin_va_arg" {
            // Parse __builtin_va_arg(ap, type)
            let ap_expr = self.parse_assign()
            self.expect(Comma)
            let ty = self.parse_type_name()
            self.expect(RParen)
            VaArg(ap_expr, ty)
          } else if name == "__builtin_offsetof" {
            // Parse __builtin_offsetof(type, field)
            let ty = self.parse_type_name()
            self.expect(Comma)
            let field_name = match self.token {
              Ident(n) => {
                self.advance()
                n
              }
              _ => {
                self.advance()
                ""
              }
            }
            self.expect(RParen)
            OffsetOf(ty, field_name)
          } else {
            let args = []
            if self.token != RParen {
              args.push(self.parse_assign())
              while self.token == Comma {
                self.advance()
                args.push(self.parse_assign())
              }
            }
            self.expect(RParen)
            Call(Var(resolved_name), args)
          }
        }
      } else if name == "__func__" || name == "__FUNCTION__" {
        if self.current_func_name != "" {
          String(self.current_func_name)
        } else {
          Var(resolved_name)
        }
      } else if self.enum_constants.contains(name) {
        Number(self.enum_constants[name])
      } else {
        Var(resolved_name)
      }
    }
    LParen => {
      self.advance()
      let expr = self.parse_expr()
      self.expect(RParen)
      expr
    }
    And => {
      // GCC extension: computed goto &&label
      self.advance()
      let label_name = match self.token {
        Ident(name) => {
          self.advance()
          name
        }
        _ => ""
      }
      LabelAddr(label_name)
    }
    _ => abort("Unexpected token in primary: " + self.token.to_string())
  }
}
