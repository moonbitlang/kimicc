///|
// Parse variable declarations after a struct/union definition: struct Foo { ... } *ptr, arr[8];
fn Parser::parse_struct_vars(self : Parser, base_ty : Type) -> Unit {
  // Parse first declarator
  let decl = self.parse_declarator(base_ty)
  if decl.name != "" {
    let decl_ty = resolve_var_type(decl)
    let mut init : GlobalInit? = None
    if self.token == Assign {
      self.advance()
      if self.token == LBrace {
        let init_exprs = self.parse_brace_init_exprs()
        init = Some(Array(init_exprs))
      } else {
        init = Some(Scalar(self.parse_assign()))
      }
    }
    self.globals.push({
      ty: decl_ty,
      name: decl.name,
      init,
      is_static: false,
      is_extern: false,
    })
    self.remember_value_type(decl.name, decl_ty)
  }
  // Additional variables separated by comma
  while self.token == Comma {
    self.advance()
    let extra = self.parse_declarator(base_ty)
    if extra.name != "" {
      let extra_ty = resolve_var_type(extra)
      let mut extra_init : GlobalInit? = None
      if self.token == Assign {
        self.advance()
        if self.token == LBrace {
          let init_exprs = self.parse_brace_init_exprs()
          extra_init = Some(Array(init_exprs))
        } else {
          extra_init = Some(Scalar(self.parse_assign()))
        }
      }
      self.globals.push({
        ty: extra_ty,
        name: extra.name,
        init: extra_init,
        is_static: false,
        is_extern: false,
      })
      self.remember_value_type(extra.name, extra_ty)
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
    if self.is_static_assert_token() {
      self.parse_static_assert_decl()
    } else if self.token == Struct || self.token == Union {
      // Peek ahead to distinguish struct/union definition from function declaration
      let saved_pos = self.lexer.pos
      let saved_token = self.token
      let is_union = self.token == Union
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
            structs.push({ name, fields, is_union })
            self.struct_decls[name] = { name, fields, is_union }
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
  self.typedefs[decl.name] = apply_decl_align(decl.ty, spec.align)
  // Handle comma-separated typedef names: typedef int a, b, c;
  while self.token == Comma {
    self.advance()
    self.skip_attributes()
    self.skip_qualifiers()
    let extra_decl = self.parse_declarator(spec.base_type)
    self.skip_attributes()
    self.typedefs[extra_decl.name] = apply_decl_align(extra_decl.ty, spec.align)
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
  let mut next_value : Int64 = 0
  while self.token != RBrace {
    self.skip_attributes()
    let name = match self.token {
      Ident(n) => {
        self.advance()
        n
      }
      _ => abort("Expected enum constant name")
    }
    self.skip_attributes()
    let value = if self.token == Assign {
      self.advance()
      let expr = self.parse_assign()
      match self.fold_const(expr) {
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
      if self.token == RBrace {
        break
      }
    }
  }
  self.expect(RBrace)
  self.expect(Semicolon)
}
