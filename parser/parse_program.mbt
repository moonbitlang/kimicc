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
              let first_field = self.parse_param()
              // Skip bit-field width if present
              if self.token == Colon {
                self.advance()
                let _ = self.parse_expr()
              }
              fields.push(first_field)
              // Handle comma-separated fields
              while self.token == Comma {
                self.advance()
                let f = self.parse_param()
                if self.token == Colon {
                  self.advance()
                  let _ = self.parse_expr()
                }
                fields.push(f)
              }
              self.expect(Semicolon)
            }
            self.expect(RBrace)
            self.skip_attributes()
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
    } else if self.token == Enum {
      self.parse_enum()
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
  { structs: all_structs, globals: self.globals, decls }
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
    let first_field = self.parse_param()
    if self.token == Colon {
      self.advance()
      let _ = self.parse_assign()
    }
    fields.push(first_field)
    while self.token == Comma {
      self.advance()
      self.skip_qualifiers()
      let name = match self.token {
        Ident(n) => { self.advance(); n }
        _ => ""
      }
      let f = self.parse_type_suffixes(base_type(first_field.ty), name)
      if self.token == Colon {
        self.advance()
        let _ = self.parse_assign()
      }
      fields.push(f)
    }
    self.expect(Semicolon)
  }
  self.expect(RBrace)
  self.expect(Semicolon)
  { name, fields }
}

///|
fn Parser::parse_typedef(self : Parser) -> Unit {
  self.expect(Typedef)
  self.skip_attributes()
  self.skip_qualifiers()
  let base_ty = self.parse_type()
  self.skip_attributes()
  // Handle function pointer typedef: typedef int (*name)(...);
  let (name, _is_func_ptr) = if self.token == LParen {
    self.expect(LParen)
    self.expect(Star)
    self.skip_qualifiers()
    let fname = match self.token {
      Ident(n) => { self.advance(); n }
      _ => abort("Expected function pointer name in typedef")
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
    (fname, true)
  } else {
    let n = match self.token {
      Ident(name) => { self.advance(); name }
      _ => abort("Expected typedef name")
    }
    (n, false)
  }
  // Handle typedef with array suffix: typedef int foo[10];
  let ty = if self.token == LBracket {
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
  self.skip_attributes()
  self.expect(Semicolon)
  self.typedefs[name] = ty
}

///|
fn Parser::parse_enum(self : Parser) -> Unit {
  self.expect(Enum)
  // Optional enum name
  match self.token {
    Ident(_) => self.advance()
    _ => ()
  }
  self.expect(LBrace)
  let mut next_value = 0
  while self.token != RBrace {
    let name = match self.token {
      Ident(n) => { self.advance(); n }
      _ => abort("Expected enum constant name")
    }
    let value = if self.token == Assign {
      self.advance()
      match self.token {
        Number(n) => { self.advance(); n }
        _ => abort("Expected number in enum constant assignment")
      }
    } else {
      next_value
    }
    self.enum_constants[name] = value
    next_value = value + 1
    if self.token == Comma {
      self.advance()
    }
  }
  self.expect(RBrace)
  self.expect(Semicolon)
}
