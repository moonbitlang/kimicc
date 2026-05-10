///|
fn Parser::parse_func_decl(self : Parser) -> FuncDecl {
  self.skip_attributes()
  let mut leading_inline = false
  while self.token == Inline {
    leading_inline = true
    self.advance()
    self.skip_attributes()
    self.skip_qualifiers()
  }
  let spec = self.parse_decl_specifiers()
  if leading_inline {
    spec.is_inline = true
  }
  let decl = self.parse_declarator(spec.base_type)
  let post_decl_align = self.skip_attributes_align()
  // If no name and no function suffix, skip to semicolon
  if decl.name == "" && decl.func_params is None {
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
      is_inline: false,
      body: None,
    }
  }
  // Function declaration or definition
  if decl.is_func_decl {
    if self.token == Comma {
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
        is_inline: false,
        body: None,
      }
    }
    let params = decl.func_params.unwrap()
    // Detect variadic function and filter out the "..." parameter
    let (_, variadic) = function_param_info(params)
    if variadic {
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
    let saved_value_types = self.value_types.copy()
    for p in params {
      self.remember_value_type(p.name, p.ty)
    }
    let body = if self.token == LBrace {
      Some(self.parse_compound_stmt())
    } else {
      self.expect(Semicolon)
      None
    }
    self.value_types = saved_value_types
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
      is_inline: spec.is_inline,
      body,
    }
  }
  // Variable declaration (including function pointer variables)
  if self.token == Semicolon ||
    self.token == Assign ||
    self.token == Comma ||
    self.token == LBracket {
    self.parse_global_var_tail(spec, decl, post_decl_align)
    return {
      ret: Void,
      name: "",
      params: [],
      variadic: false,
      is_static: false,
      is_inline: false,
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
    is_inline: false,
    body: None,
  }
}

///|

///|
fn resolve_var_type(decl : DeclaratorResult) -> Type {
  // Older declarator paths still use func_ret_ty for wrapped pointer/array
  // declarators. Function pointers keep their call metadata directly in ty.
  if type_contains_func_ptr(decl.ty) {
    decl.ty
  } else {
    match decl.func_ret_ty {
      Some(rt) => rt
      None => decl.ty
    }
  }
}

///|
fn Parser::parse_global_var_tail(
  self : Parser,
  spec : DeclSpec,
  decl : DeclaratorResult,
  post_decl_align : Int?,
) -> Unit {
  let mut ty = apply_decl_align(
    apply_decl_align(resolve_var_type(decl), spec.align),
    post_decl_align,
  )
  let name = decl.name
  let mut init : GlobalInit? = None
  self.skip_attributes()
  // Parse initializer for first variable
  if self.token == Assign {
    self.advance()
    if self.token == LBrace {
      let init_exprs = self.parse_brace_init_exprs()
      let init_count = initializer_element_count(init_exprs)
      ty = match ty {
        Array(elem_ty, 0) => Array(elem_ty, init_count)
        other => other
      }
      init = Some(Array(init_exprs))
    } else {
      let expr = self.parse_assign()
      match (ty, expr) {
        (Array(elem_ty, 0), String(s)) => {
          ty = Array(elem_ty, s.length() + 1)
          let char_exprs = Array::make(s.length() + 1, Expr::Number(0))
          for i = 0; i < s.length(); i = i + 1 {
            char_exprs[i] = Number(s[i].to_int().to_int64())
          }
          char_exprs[s.length()] = Number(0)
          init = Some(Array(char_exprs))
        }
        _ => init = Some(Scalar(expr))
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
  self.remember_value_type(name, ty)
  self.skip_attributes()
  // Handle additional variables separated by comma
  while self.token == Comma {
    self.advance()
    let extra_decl = self.parse_declarator(spec.base_type)
    let extra_post_decl_align = self.skip_attributes_align()
    let mut extra_ty = apply_decl_align(
      apply_decl_align(resolve_var_type(extra_decl), spec.align),
      extra_post_decl_align,
    )
    let mut extra_init : GlobalInit? = None
    if self.token == Assign {
      self.advance()
      if self.token == LBrace {
        let init_exprs = self.parse_brace_init_exprs()
        let init_count = initializer_element_count(init_exprs)
        extra_ty = match extra_ty {
          Array(elem_ty, 0) => Array(elem_ty, init_count)
          other => other
        }
        extra_init = Some(Array(init_exprs))
      } else {
        let expr = self.parse_assign()
        match (extra_ty, expr) {
          (Array(elem_ty, 0), String(s)) => {
            extra_ty = Array(elem_ty, s.length() + 1)
            let char_exprs = Array::make(s.length() + 1, Expr::Number(0))
            for i = 0; i < s.length(); i = i + 1 {
              char_exprs[i] = Number(s[i].to_int().to_int64())
            }
            char_exprs[s.length()] = Number(0)
            extra_init = Some(Array(char_exprs))
          }
          _ => extra_init = Some(Scalar(expr))
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
    self.remember_value_type(extra_decl.name, extra_ty)
    self.skip_attributes()
  }
  self.skip_attributes()
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
  let post_decl_align = self.skip_attributes_align()
  {
    ty: apply_decl_align(apply_decl_align(decl.ty, spec.align), post_decl_align),
    name: decl.name,
    bit_width: None,
  }
}
