///|
// Parse variable declarations after a struct/union definition: struct Foo { ... } *ptr, arr[8];
fn Parser::parse_struct_vars(self : Parser, base_ty : Type) -> Unit {
  // Parse first declarator
  let decl = self.parse_declarator(base_ty)
  if decl.name != "" {
    if self.token == Assign {
      self.advance()
      if self.token == LBrace {
        self.skip_brace_initializer()
      } else {
        let _ = self.parse_expr()
      }
    }
    self.globals.push((decl.ty, decl.name))
  }
  // Additional variables separated by comma
  while self.token == Comma {
    self.advance()
    let extra = self.parse_declarator(base_ty)
    if extra.name != "" {
      if self.token == Assign {
        self.advance()
        if self.token == LBrace {
          self.skip_brace_initializer()
        } else {
          let _ = self.parse_expr()
        }
      }
      self.globals.push((extra.ty, extra.name))
    }
  }
  self.expect(Semicolon)
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
            let fields = self.parse_struct_body()
            self.expect(RBrace)
            self.skip_attributes()
            // Handle struct definition followed by variable declarations: struct Foo { ... } *ptr;
            if self.token != Semicolon {
              self.parse_struct_vars(Struct(name))
            } else {
              self.expect(Semicolon)
            }
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
    } else if self.token == Semicolon {
      self.advance()
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
fn Parser::parse_typedef(self : Parser) -> Unit {
  self.expect(Typedef)
  self.skip_attributes()
  self.skip_qualifiers()
  let spec = self.parse_decl_specifiers()
  self.skip_attributes()
  // Parse first typedef declarator
  let decl = self.parse_declarator(spec.base_type)
  self.skip_attributes()
  self.typedefs[decl.name] = decl.ty
  // Handle comma-separated typedef names: typedef int a, b, c;
  while self.token == Comma {
    self.advance()
    self.skip_attributes()
    self.skip_qualifiers()
    let extra_decl = self.parse_declarator(spec.base_type)
    self.skip_attributes()
    self.typedefs[extra_decl.name] = extra_decl.ty
  }
  self.expect(Semicolon)
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
    self.skip_attributes()
    let name = match self.token {
      Ident(n) => { self.advance(); n }
      _ => abort("Expected enum constant name")
    }
    self.skip_attributes()
    let value = if self.token == Assign {
      self.advance()
      let expr = self.parse_assign()
      match fold_const(expr) {
        Some(n) => n
        None => next_value
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
