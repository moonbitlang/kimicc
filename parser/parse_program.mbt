///|
// Parse variable declarations after a struct/union definition: struct Foo { ... } *ptr, arr[8];
fn Parser::parse_struct_vars(self : Parser, base_ty : Type) -> Unit {
  // First variable declarator
  let mut ty = base_ty
  while self.token == Star {
    self.advance()
    ty = Pointer(ty)
  }
  if self.token is Ident(name) {
    self.advance()
    while self.token == LBracket {
      self.advance()
      if self.token == RBracket {
        self.advance()
        ty = Array(ty, 0)
      } else {
        let size_expr = self.parse_assign()
        self.expect(RBracket)
        let size = match fold_const(size_expr) {
          Some(n) => n
          None => 0
        }
        ty = Array(ty, size)
      }
    }
    if self.token == Assign {
      self.advance()
      if self.token == LBrace {
        self.skip_brace_initializer()
      } else {
        let _ = self.parse_expr()
      }
    }
    self.globals.push((ty, name))
    // Additional variables separated by comma
    while self.token == Comma {
      self.advance()
      let mut vty = base_ty
      while self.token == Star {
        self.advance()
        vty = Pointer(vty)
      }
      if self.token is Ident(vname) {
        self.advance()
        while self.token == LBracket {
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
            self.skip_brace_initializer()
          } else {
            let _ = self.parse_expr()
          }
        }
        self.globals.push((vty, vname))
      }
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
            let fields = []
            while self.token != RBrace {
              self.skip_attributes()
              self.skip_qualifiers()
              let first_field = self.parse_param()
              // Skip bit-field width if present
              if self.token == Colon {
                self.advance()
                let _ = self.parse_assign()
              }
              fields.push(first_field)
              // Handle comma-separated fields
              while self.token == Comma {
                self.advance()
                self.skip_qualifiers()
                let mut vty = base_type(first_field.ty)
                while self.token == Star {
                  self.advance()
                  vty = Pointer(vty)
                }
                let fname = match self.token {
                  Ident(n) => { self.advance(); n }
                  _ => ""
                }
                let f = self.parse_type_suffixes(vty, fname)
                if self.token == Colon {
                  self.advance()
                  let _ = self.parse_assign()
                }
                fields.push(f)
              }
              self.expect(Semicolon)
            }
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
      let mut vty = base_type(first_field.ty)
      while self.token == Star {
        self.advance()
        vty = Pointer(vty)
      }
      let name = match self.token {
        Ident(n) => { self.advance(); n }
        _ => ""
      }
      let f = self.parse_type_suffixes(vty, name)
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
  // Handle function pointer typedef: typedef int (*name)(...); or typedef int (^name)(...);
  let (name, _is_func_ptr) = if self.token == LParen {
    self.expect(LParen)
    if self.token == Star || self.token == BitXor {
      self.advance()
    } else {
      abort("Expected * or ^ in function pointer typedef")
    }
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
    // Handle function type typedef without (*): typedef void *name(...);
    if self.token == LParen {
      self.expect(LParen)
      let mut depth = 1
      while depth > 0 && self.token != EOF {
        if self.token == LParen { depth += 1 }
        else if self.token == RParen { depth -= 1 }
        if depth > 0 { self.advance() } else { self.advance(); break }
      }
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
