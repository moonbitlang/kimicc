///|
fn Parser::parse_func_decl(self : Parser) -> FuncDecl {
  self.skip_attributes()
  while self.token == Inline {
    self.advance()
    self.skip_attributes()
    self.skip_qualifiers()
  }
  let spec = self.parse_decl_specifiers()
  let decl = self.parse_declarator(spec.base_type)
  // If no name and no function suffix, skip to semicolon
  if decl.name == "" && decl.func_params.is_none() {
    while self.token != Semicolon && self.token != EOF {
      self.advance()
    }
    if self.token == Semicolon {
      self.advance()
    }
    return { ret: Void, name: "", params: [], body: None }
  }
  // Function declaration or definition
  if decl.is_func_decl {
    let params = decl.func_params.unwrap()
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
    let ret_ty = match decl.func_ret_ty {
      Some(rt) => rt
      None => spec.base_type
    }
    return { ret: ret_ty, name: decl.name, params, body }
  }
  // Variable declaration (including function pointer variables)
  if self.token == Semicolon || self.token == Assign || self.token == Comma ||
     self.token == LBracket {
    self.parse_global_var_tail(spec, decl)
    return { ret: Void, name: "", params: [], body: None }
  }
  // Skip anything else to next semicolon
  while self.token != Semicolon && self.token != EOF {
    self.advance()
  }
  if self.token == Semicolon {
    self.advance()
  }
  { ret: Void, name: "", params: [], body: None }
}

///|
fn Parser::parse_global_var_tail(self : Parser, spec : DeclSpec, decl : DeclaratorResult) -> Unit {
  let ty = decl.ty
  let name = decl.name
  // Skip initializer for first variable
  if self.token == Assign {
    self.advance()
    if self.token == LBrace {
      self.skip_balanced_braces()
    } else {
      let _ = self.parse_expr()
    }
  }
  self.globals.push((ty, name))
  // Handle additional variables separated by comma
  while self.token == Comma {
    self.advance()
    let extra_decl = self.parse_declarator(spec.base_type)
    let extra_ty = extra_decl.ty
    if self.token == Assign {
      self.advance()
      if self.token == LBrace {
        self.skip_balanced_braces()
      } else {
        let _ = self.parse_expr()
      }
    }
    self.globals.push((extra_ty, extra_decl.name))
  }
  self.expect(Semicolon)
}

///|
fn Parser::parse_param(self : Parser) -> Param {
  if self.token == Ellipsis {
    self.advance()
    return { ty: Void, name: "..." }
  }
  let spec = self.parse_decl_specifiers()
  let decl = self.parse_declarator(spec.base_type)
  self.skip_attributes()
  { ty: decl.ty, name: decl.name }
}


