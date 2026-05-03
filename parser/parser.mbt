///|
pub struct Parser {
  lexer : Lexer
  mut token : Token
  typedefs : Map[String, Type]
  anonymous_structs : Array[StructDecl]
  mut anon_counter : Int
}

///|
pub fn Parser::new(lexer : Lexer) -> Parser {
  let p = { lexer, token: EOF, typedefs: {}, anonymous_structs: [], anon_counter: 0 }
  p.advance()
  p
}

///|
fn Parser::advance(self : Parser) -> Unit {
  self.token = self.lexer.next_token()
}

///|
fn Parser::expect(self : Parser, t : Token) -> Unit {
  if self.token != t {
    abort("Expected " + t.to_string() + " but got " + self.token.to_string())
  }
  self.advance()
}

///|
pub fn parse(input : String) -> Program {
  let lexer = Lexer::new(input)
  let parser = Parser::new(lexer)
  parser.parse_program()
}

///|
fn Parser::parse_program(self : Parser) -> Program {
  let structs = []
  let decls = []
  while self.token != EOF {
    self.skip_attributes()
    self.skip_qualifiers()
    while self.token == Inline {
      self.advance()
      self.skip_attributes()
      self.skip_qualifiers()
    }
    if self.token == Struct || self.token == Union {
      // Peek ahead to distinguish struct/union definition from function declaration
      let saved_pos = self.lexer.pos
      let saved_token = self.token
      self.advance() // past struct/union
      match self.token {
        Ident(name) => {
          self.advance()
          if self.token == LBrace {
            // Struct/union definition
            self.expect(LBrace)
            let fields = []
            while self.token != RBrace {
              self.skip_attributes()
              self.skip_qualifiers()
              fields.push(self.parse_param())
              self.expect(Semicolon)
            }
            self.expect(RBrace)
            self.expect(Semicolon)
            structs.push({ name, fields })
          } else if self.token == Semicolon {
            // Forward struct declaration: struct Foo;
            self.advance()
            // Just ignore it
          } else {
            // Function declaration with struct/union return type
            self.lexer.pos = saved_pos
            self.token = saved_token
            let decl = self.parse_func_decl()
            if decl.name != "" {
              decls.push(decl)
            }
          }
        }
        _ => {
          self.lexer.pos = saved_pos
          self.token = saved_token
          let decl = self.parse_func_decl()
          if decl.name != "" {
            decls.push(decl)
          }
        }
      }
    } else if self.token == Typedef {
      self.parse_typedef()
    } else {
      let decl = self.parse_func_decl()
      if decl.name != "" {
        decls.push(decl)
      }
    }
  }
  // Prepend anonymous structs
  let all_structs = self.anonymous_structs
  for s in structs {
    all_structs.push(s)
  }
  { structs: all_structs, decls }
}

///|
fn Parser::parse_struct_decl(self : Parser) -> StructDecl {
  self.advance() // struct/union
  let name = match self.token {
    Ident(n) => {
      self.advance()
      n
    }
    _ => abort("Expected struct/union name")
  }
  self.expect(LBrace)
  let fields = []
  while self.token != RBrace {
    self.skip_attributes()
    self.skip_qualifiers()
    fields.push(self.parse_param())
    self.expect(Semicolon)
  }
  self.expect(RBrace)
  self.expect(Semicolon)
  { name, fields }
}

///|
fn Parser::skip_qualifiers(self : Parser) -> Unit {
  while self.token == Const || self.token == Restrict || self.token == Extern ||
        self.token == Static || self.token == Volatile {
    self.advance()
  }
}

///|
fn Parser::skip_attributes(self : Parser) -> Unit {
  while self.token == Ident("__attribute__") || self.token == Ident("__asm") {
    self.advance()
    self.expect(LParen)
    // Skip until balanced RParen
    let mut depth = 1
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
}

///|
fn Parser::parse_typedef(self : Parser) -> Unit {
  self.expect(Typedef)
  self.skip_attributes()
  self.skip_qualifiers()
  let base_ty = self.parse_type()
  let name = match self.token {
    Ident(n) => {
      self.advance()
      n
    }
    _ => abort("Expected typedef name")
  }
  // Handle typedef with array suffix: typedef int foo[10];
  let ty = if self.token == LBracket {
    self.advance()
    let size = match self.token {
      Number(n) => { self.advance(); n }
      _ => abort("Expected array size in typedef")
    }
    self.expect(RBracket)
    Array(base_ty, size)
  } else {
    base_ty
  }
  self.skip_attributes()
  self.expect(Semicolon)
  self.typedefs[name] = ty
}

///|
fn Parser::parse_func_decl(self : Parser) -> FuncDecl {
  while self.token == Inline {
    self.advance()
    self.skip_attributes()
    self.skip_qualifiers()
  }
  let ret = self.parse_type()
  self.skip_attributes()
  self.skip_qualifiers()
  let name = match self.token {
    Ident(n) => {
      self.advance()
      n
    }
    _ => abort("Expected function name, got " + self.token.to_string())
  }
  self.skip_attributes()
  // Check if this is a variable declaration (not a function)
  if self.token == Semicolon || self.token == Assign || self.token == Comma ||
     self.token == LBracket {
    // Skip variable declaration
    while self.token != Semicolon && self.token != EOF {
      self.advance()
    }
    self.expect(Semicolon)
    return { ret: Void, name: "", params: [], body: None }
  }
  self.expect(LParen)
  let params = []
  if self.token != RParen {
    params.push(self.parse_param())
    while self.token == Comma {
      self.advance()
      params.push(self.parse_param())
    }
  }
  self.expect(RParen)
  self.skip_attributes()
  let body = if self.token == LBrace {
    Some(self.parse_compound_stmt())
  } else {
    self.expect(Semicolon)
    None
  }
  { ret, name, params, body }
}

///|
fn Parser::parse_param(self : Parser) -> Param {
  if self.token == Ellipsis {
    self.advance()
    return { ty: Void, name: "..." }
  }
  let ty = self.parse_type()
  // Handle function pointer: type (*name)(...)
  if self.token == LParen {
    self.expect(LParen)
    self.expect(Star)
    // Skip qualifiers like _Nullable, const, restrict
    while self.token == Ident("_Nullable") || self.token == Const ||
          self.token == Restrict || self.token == Volatile {
      self.advance()
    }
    let fname = match self.token {
      Ident(n) => { self.advance(); n }
      RParen => ""
      _ => abort("Expected function pointer name")
    }
    self.expect(RParen)
    self.expect(LParen)
    // Skip parameter list
    let mut depth = 1
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
    return { ty: Pointer(Void), name: fname }
  }
  // Skip qualifiers after pointer: const, restrict, volatile
  self.skip_qualifiers()
  let name = match self.token {
    Ident(n) => {
      self.advance()
      n
    }
    // Parameter name is optional in function prototypes
    _ => ""
  }
  // Handle int a[] as pointer
  if self.token == LBracket {
    self.advance()
    if self.token == RBracket {
      self.advance()
    } else {
      let _ = self.parse_expr()
      self.expect(RBracket)
    }
    { ty: Pointer(ty), name }
  } else {
    { ty, name }
  }
}

///|
fn Parser::parse_type(self : Parser) -> Type {
  // Skip type qualifiers (const, restrict, extern, static, volatile)
  self.skip_qualifiers()
  // Handle type modifiers (signed, unsigned, short, long)
  let has_modifier = self.token == Signed || self.token == Unsigned ||
                     self.token == Short || self.token == Long
  if has_modifier {
    // Consume all consecutive modifiers: "unsigned short", "long long", etc.
    while self.token == Signed || self.token == Unsigned ||
          self.token == Short || self.token == Long {
      self.advance()
    }
    // After modifiers, the base type may be implicit or explicit
    self.skip_qualifiers()
    if self.token == Int || self.token == Char || self.token == Void {
      let base = match self.token {
        Int => { self.advance(); Type::Int }
        Char => { self.advance(); Type::Char }
        Void => { self.advance(); Type::Void }
        _ => Type::Int
      }
      self.skip_qualifiers()
      return self.parse_type_suffix(base)
    }
    // Modifier without explicit base type → int
    return self.parse_type_suffix(Type::Int)
  }
  let base = match self.token {
    Int => {
      self.advance()
      Type::Int
    }
    Void => {
      self.advance()
      Type::Void
    }
    Char => {
      self.advance()
      Type::Char
    }
    Struct => {
      self.advance()
      match self.token {
        Ident(n) => {
          self.advance()
          // Named struct with inline body: struct Name { ... }
          if self.token == LBrace {
            self.expect(LBrace)
            let fields = []
            while self.token != RBrace {
              self.skip_attributes()
              self.skip_qualifiers()
              fields.push(self.parse_param())
              self.expect(Semicolon)
            }
            self.expect(RBrace)
            self.anonymous_structs.push({ name: n, fields })
          }
          Type::Struct(n)
        }
        LBrace => {
          // Anonymous struct: parse body inline
          self.expect(LBrace)
          let fields = []
          while self.token != RBrace {
            self.skip_attributes()
            self.skip_qualifiers()
            fields.push(self.parse_param())
            self.expect(Semicolon)
          }
          self.expect(RBrace)
          let name = "__anon_struct_" + self.anon_counter.to_string()
          self.anon_counter += 1
          self.anonymous_structs.push({ name, fields })
          Type::Struct(name)
        }
        _ => abort("Expected struct name or {")
      }
    }
    Union => {
      self.advance()
      match self.token {
        Ident(n) => {
          self.advance()
          Type::Struct(n)
        }
        LBrace => {
          // Anonymous union: parse body inline, treat as struct
          self.expect(LBrace)
          let fields = []
          while self.token != RBrace {
            self.skip_attributes()
            self.skip_qualifiers()
            fields.push(self.parse_param())
            self.expect(Semicolon)
          }
          self.expect(RBrace)
          let name = "__anon_union_" + self.anon_counter.to_string()
          self.anon_counter += 1
          self.anonymous_structs.push({ name, fields })
          Type::Struct(name)
        }
        _ => abort("Expected union name or {")
      }
    }
    Ident(name) => {
      if self.typedefs.contains(name) {
        self.advance()
        self.typedefs[name]
      } else if name == "__builtin_va_list" {
        self.advance()
        // va_list is typically a char* or void* array on ARM64
        Pointer(Char)
      } else {
        abort("Expected type, got identifier: " + name)
      }
    }
    _ => abort("Expected type, got " + self.token.to_string())
  }
  self.skip_qualifiers()
  self.parse_type_suffix(base)
}

///|
fn Parser::parse_type_suffix(self : Parser, base : Type) -> Type {
  let mut ty = base
  while self.token == Star {
    self.advance()
    ty = Pointer(ty)
  }
  ty
}

///|
fn Parser::parse_stmt(self : Parser) -> Stmt {
  match self.token {
    If => self.parse_if_stmt()
    While => self.parse_while_stmt()
    Return => self.parse_return_stmt()
    LBrace => self.parse_compound_stmt()
    Int | Void | Char | Struct | Union => self.parse_var_decl_stmt()
    Ident(name) => {
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
  let ty = self.parse_type()
  let name = match self.token {
    Ident(n) => {
      self.advance()
      n
    }
    _ => abort("Expected variable name")
  }
  // Handle array declaration: int a[8];
  let final_ty = if self.token == LBracket {
    self.advance()
    let size = match self.token {
      Number(n) => {
        self.advance()
        n
      }
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
  VarDecl(final_ty, name, init)
}

///|
fn Parser::parse_expr_stmt(self : Parser) -> Stmt {
  let expr = self.parse_expr()
  self.expect(Semicolon)
  ExprStmt(expr)
}

///|
fn Parser::parse_expr(self : Parser) -> Expr {
  self.parse_assign()
}

///|
fn Parser::parse_assign(self : Parser) -> Expr {
  let expr = self.parse_logical_or()
  if self.token == Assign {
    self.advance()
    let rhs = self.parse_assign()
    if is_lvalue(expr) {
      Assign(expr, rhs)
    } else {
      abort("Invalid assignment target")
    }
  } else {
    expr
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
  let mut left = self.parse_equality()
  while true {
    match self.token {
      And => {
        self.advance()
        left = Binary("&&", left, self.parse_equality())
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
  let mut left = self.parse_additive()
  while true {
    match self.token {
      Lt => {
        self.advance()
        left = Binary("<", left, self.parse_additive())
      }
      Le => {
        self.advance()
        left = Binary("<=", left, self.parse_additive())
      }
      Gt => {
        self.advance()
        left = Binary(">", left, self.parse_additive())
      }
      Ge => {
        self.advance()
        left = Binary(">=", left, self.parse_additive())
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
        // Handle --x as -(-x) for now
        self.advance()
        Unary("-", Unary("-", self.parse_unary()))
      } else {
        Unary("-", self.parse_unary())
      }
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
      self.expect(LParen)
      let ty = self.parse_type()
      self.expect(RParen)
      Sizeof(ty)
    }
    LParen => {
      // Could be a cast: (type)expr or parenthesized expr: (expr)
      let saved_pos = self.lexer.pos
      let saved_token = self.token
      self.advance() // past (
      // Try to parse as type
      let is_cast = match self.token {
        Int | Void | Char | Struct | Union | Signed | Unsigned | Short | Long => true
        Ident(name) => self.typedefs.contains(name)
        _ => false
      }
      if is_cast {
        // It's a cast
        let _ty = self.parse_type()
        if self.token == RParen {
          self.advance() // past )
          // For now, ignore the cast and just return the operand
          self.parse_unary()
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
        expr
      }
    }
    _ => self.parse_postfix()
  }
}

///|
fn Parser::parse_postfix(self : Parser) -> Expr {
  let mut expr = self.parse_primary()
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
          // No-op for now
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
          // No-op for now
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
          args.push(self.parse_expr())
          while self.token == Comma {
            self.advance()
            args.push(self.parse_expr())
          }
        }
        self.expect(RParen)
        Call(name, args)
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
    _ => abort("Unexpected token: " + self.token.to_string())
  }
}
