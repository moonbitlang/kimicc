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
    return {
      ret: Void,
      name: "",
      params: [],
      variadic: false,
      is_static: false,
      body: None,
    }
  }
  // Function declaration or definition
  if decl.is_func_decl {
    let params = decl.func_params.unwrap()
    // Detect variadic function and filter out the "..." parameter
    let mut variadic = false
    if params.length() > 0 && params[params.length() - 1].name == "..." {
      variadic = true
      let _ = params.pop()
    }
    // Filter out void parameters: int foo(void) -> no params
    let filtered_params = []
    for i = 0; i < params.length(); i = i + 1 {
      if params[i].ty != Void {
        filtered_params.push(params[i])
      }
    }
    let params = filtered_params
    // Apply array-to-pointer decay for function parameters
    for i = 0; i < params.length(); i = i + 1 {
      match params[i].ty {
        Array(elem, _) =>
          params[i] = {
            ty: Pointer(elem),
            name: params[i].name,
            bit_width: None,
          }
        _ => ()
      }
    }
    self.skip_attributes()
    self.current_func_name = decl.name
    self.static_locals = {}
    let body = if self.token == LBrace {
      Some(self.parse_compound_stmt())
    } else {
      self.expect(Semicolon)
      None
    }
    self.current_func_name = ""
    self.static_locals = {}
    let ret_ty = match decl.func_ret_ty {
      Some(rt) => rt
      None => spec.base_type
    }
    return {
      ret: ret_ty,
      name: decl.name,
      params,
      variadic,
      is_static: spec.is_static,
      body,
    }
  }
  // Variable declaration (including function pointer variables)
  if self.token == Semicolon ||
    self.token == Assign ||
    self.token == Comma ||
    self.token == LBracket {
    self.parse_global_var_tail(spec, decl)
    return {
      ret: Void,
      name: "",
      params: [],
      variadic: false,
      is_static: false,
      body: None,
    }
  }
  // Skip anything else to next semicolon
  while self.token != Semicolon && self.token != EOF {
    self.advance()
  }
  if self.token == Semicolon {
    self.advance()
  }
  {
    ret: Void,
    name: "",
    params: [],
    variadic: false,
    is_static: false,
    body: None,
  }
}

///|

///|
fn resolve_var_type(decl : DeclaratorResult) -> Type {
  // For function pointer variables like int (*fp)(int), decl.ty is Pointer(Void)
  // but func_ret_ty holds the actual wrapped type (e.g., Pointer(SInt)).
  match decl.func_ret_ty {
    Some(rt) => rt
    None => decl.ty
  }
}

///|
fn Parser::parse_global_var_tail(
  self : Parser,
  spec : DeclSpec,
  decl : DeclaratorResult,
) -> Unit {
  let mut ty = resolve_var_type(decl)
  let name = decl.name
  let mut init : GlobalInit? = None
  // Parse initializer for first variable
  if self.token == Assign {
    self.advance()
    if self.token == LBrace {
      let init_exprs = self.parse_brace_init_exprs(flatten_nested=true)
      let init_count = init_exprs.length()
      ty = match ty {
        Array(elem_ty, 0) => Type::Array(elem_ty, init_count)
        other => other
      }
      init = Some(GlobalInit::Array(init_exprs))
    } else {
      let expr = self.parse_expr()
      match (ty, expr) {
        (Array(elem_ty, 0), Expr::String(s)) => {
          ty = Type::Array(elem_ty, s.length() + 1)
          let char_exprs = Array::make(s.length() + 1, Expr::Number(0))
          for i = 0; i < s.length(); i = i + 1 {
            char_exprs[i] = Expr::Number(s[i].to_int().to_int64())
          }
          char_exprs[s.length()] = Expr::Number(0)
          init = Some(GlobalInit::Array(char_exprs))
        }
        _ => init = Some(GlobalInit::Scalar(expr))
      }
    }
  }
  self.globals.push({
    ty,
    name,
    init,
    is_static: spec.is_static,
    is_extern: spec.is_extern,
  })
  // Handle additional variables separated by comma
  while self.token == Comma {
    self.advance()
    let extra_decl = self.parse_declarator(spec.base_type)
    let mut extra_ty = resolve_var_type(extra_decl)
    let mut extra_init : GlobalInit? = None
    if self.token == Assign {
      self.advance()
      if self.token == LBrace {
        let init_exprs = self.parse_brace_init_exprs(flatten_nested=true)
        let init_count = init_exprs.length()
        extra_ty = match extra_ty {
          Array(elem_ty, 0) => Type::Array(elem_ty, init_count)
          other => other
        }
        extra_init = Some(GlobalInit::Array(init_exprs))
      } else {
        let expr = self.parse_expr()
        match (extra_ty, expr) {
          (Array(elem_ty, 0), Expr::String(s)) => {
            extra_ty = Type::Array(elem_ty, s.length() + 1)
            let char_exprs = Array::make(s.length() + 1, Expr::Number(0))
            for i = 0; i < s.length(); i = i + 1 {
              char_exprs[i] = Expr::Number(s[i].to_int().to_int64())
            }
            char_exprs[s.length()] = Expr::Number(0)
            extra_init = Some(GlobalInit::Array(char_exprs))
          }
          _ => extra_init = Some(GlobalInit::Scalar(expr))
        }
      }
    }
    self.globals.push({
      ty: extra_ty,
      name: extra_decl.name,
      init: extra_init,
      is_static: spec.is_static,
      is_extern: spec.is_extern,
    })
  }
  self.expect(Semicolon)
}

///|
fn Parser::parse_param(self : Parser) -> Param {
  if self.token == Ellipsis {
    self.advance()
    return { ty: Void, name: "...", bit_width: None }
  }
  let spec = self.parse_decl_specifiers()
  let decl = self.parse_declarator(spec.base_type)
  self.skip_attributes()
  { ty: decl.ty, name: decl.name, bit_width: None }
}
