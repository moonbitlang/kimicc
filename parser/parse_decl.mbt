///|
fn Parser::parse_func_decl(self : Parser) -> FuncDecl {
  self.skip_attributes()
  while self.token == Inline {
    self.advance()
    self.skip_attributes()
    self.skip_qualifiers()
  }
  let pos = self.lexer.pos
  let near_end = @math.minimum(pos + 40, self.lexer.input.length())
  let near = self.lexer.input[pos:near_end].to_string()
  println("parse_func_decl start: token=" + self.token.to_string() + " near=[" + near + "]")
  let mut ret = self.parse_type()
  while true {
    self.skip_attributes()
    self.skip_qualifiers()
    if self.token == Star {
      self.advance()
      ret = Pointer(ret)
    } else {
      break
    }
  }
  self.skip_qualifiers()
  let name = match self.token {
    Ident(n) => {
      self.advance()
      n
    }
    _ => {
      // Not a normal function declaration (might be function pointer variable
      // or function returning function pointer)
      // Skip balanced parentheses and possibly a brace body
      let mut paren_depth = 0
      while self.token != Semicolon && self.token != EOF {
        if self.token == LParen {
          paren_depth += 1
        } else if self.token == RParen {
          paren_depth -= 1
        } else if self.token == LBrace && paren_depth == 0 {
          // Function body - skip it
          self.skip_brace_initializer()
          break
        }
        self.advance()
      }
      if self.token == Semicolon {
        self.expect(Semicolon)
      }
      return { ret: Void, name: "", params: [], body: None }
    }
  }
  println("parse_func_decl name=" + name + " next_token=" + self.token.to_string())
  self.skip_attributes()
  // Check if this is a variable declaration (not a function)
  if self.token == Semicolon || self.token == Assign || self.token == Comma ||
     self.token == LBracket {
    // Parse and record global variable declaration
    let mut final_ty = ret
    // Handle array suffix for first variable
    if self.token == LBracket {
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
    // Skip initializer for first variable
    if self.token == Assign {
      self.advance()
      if self.token == LBrace {
        let mut depth = 1
        self.advance()
        while depth > 0 && self.token != EOF {
          if self.token == LBrace { depth += 1 }
          else if self.token == RBrace { depth -= 1 }
          if depth > 0 { self.advance() } else { self.advance(); break }
        }
      } else {
        let _ = self.parse_expr()
      }
    }
    self.globals.push((final_ty, name))
    // Handle additional variables separated by comma
    while self.token == Comma {
      self.advance()
      let mut vty = ret
      while self.token == Star {
        self.advance()
        vty = Pointer(vty)
      }
      match self.token {
        Ident(vname) => {
          self.advance()
          if self.token == LBracket {
            self.advance()
            if self.token == RBracket {
              self.advance()
              vty = Array(vty, 0)
            } else {
              let size_expr = self.parse_assign()
              self.expect(RBracket)
              let size = match fold_const(size_expr) {
                Some(n) => n
                None => 0
              }
              vty = Array(vty, size)
            }
          }
          if self.token == Assign {
            self.advance()
            if self.token == LBrace {
              let mut depth = 1
              self.advance()
              while depth > 0 && self.token != EOF {
                if self.token == LBrace { depth += 1 }
                else if self.token == RBrace { depth -= 1 }
                if depth > 0 { self.advance() } else { self.advance(); break }
              }
            } else {
              let _ = self.parse_expr()
            }
          }
          self.globals.push((vty, vname))
        }
        _ => ()
      }
    }
    self.expect(Semicolon)
    return { ret: Void, name: "", params: [], body: None }
  }
  if self.token != LParen {
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
  if self.token != RParen {
  }
  // Apply array-to-pointer decay for function parameters
  for i = 0; i < params.length(); i = i + 1 {
    match params[i].ty {
      Array(elem, _) => params[i] = { ty: Pointer(elem), name: params[i].name }
      _ => ()
    }
  }
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
// Parse function pointer suffix: (*name)(params) after a base type has been parsed.
// Returns (type, name) where type is Pointer(Void).
fn Parser::parse_func_ptr_decl(self : Parser) -> (Type, String) {
  self.expect(LParen)
  // Consume all * and qualifiers for multiple indirection: (**name)
  while self.token == Star || self.token == BitXor {
    self.advance()
    self.skip_qualifiers()
  }
  while self.token == Ident("_Nullable") || self.token == Ident("_Nonnull") ||
        self.token == Ident("_Null_unspecified") || self.token == Const ||
        self.token == Restrict || self.token == Volatile {
    self.advance()
  }
  let fname = if self.token == LParen {
    // Nested function pointer declarator: type (*(*name)(inner))(outer)
    let (_, name) = self.parse_func_ptr_decl()
    self.expect(RParen)
    self.expect(LParen)
    let mut depth = 1
    while depth > 0 && self.token != EOF {
      if self.token == LParen { depth += 1 }
      else if self.token == RParen { depth -= 1 }
      if depth > 0 { self.advance() } else { self.advance(); break }
    }
    return (Pointer(Void), name)
  } else {
    match self.token {
      Ident(n) => { self.advance(); n }
      RParen => ""
      _ => abort("Expected function pointer name")
    }
  }
  self.expect(RParen)
  self.expect(LParen)
  let mut depth = 1
  while depth > 0 && self.token != EOF {
    if self.token == LParen { depth += 1 }
    else if self.token == RParen { depth -= 1 }
    if depth > 0 { self.advance() } else { self.advance(); break }
  }
  (Pointer(Void), fname)
}

///|
fn Parser::parse_param(self : Parser) -> Param {
  if self.token == Ellipsis {
    self.advance()
    return { ty: Void, name: "..." }
  }
  let ty = self.parse_type()
  // Handle function pointer: type (*name)(...) or type (^name)(...)
  if self.token == LParen {
    self.expect(LParen)
    // Consume all * and qualifiers for multiple indirection: (**name)
    while self.token == Star || self.token == BitXor {
      self.advance()
      self.skip_qualifiers()
    }
    // Skip qualifiers like _Nullable, _Nonnull, const, restrict
    while self.token == Ident("_Nullable") || self.token == Ident("_Nonnull") ||
          self.token == Ident("_Null_unspecified") || self.token == Const ||
          self.token == Restrict || self.token == Volatile {
      self.advance()
    }
    let fname = if self.token == LParen {
      // Nested function pointer declarator: type (*(*name)(inner))(outer)
      let (_, name) = self.parse_func_ptr_decl()
      self.expect(RParen)
      self.expect(LParen)
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
      self.skip_attributes()
      return { ty: Pointer(Void), name: name }
    } else {
      match self.token {
        Ident(n) => { self.advance(); n }
        RParen => ""
        _ => {
          let pos = self.lexer.pos
          let near_end = @math.minimum(pos + 40, self.lexer.input.length())
          let near = self.lexer.input[pos:near_end].to_string()
          abort("Expected function pointer name, got " + self.token.to_string() + " near=" + near)
        }
      }
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
    self.skip_attributes()
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
  self.parse_type_suffixes(ty, name)
}

///|
fn base_type(ty : Type) -> Type {
  match ty {
    Pointer(t) => base_type(t)
    Array(t, _) => base_type(t)
    _ => ty
  }
}

///|
fn Parser::parse_type_suffixes(self : Parser, ty : Type, name : String) -> Param {
  // Handle array suffixes: [n][m]...
  let mut final_ty = ty
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
        None => 0 // unknown constant expression
      }
      final_ty = Array(final_ty, size)
    }
  }
  self.skip_attributes()
  { ty: final_ty, name }
}
