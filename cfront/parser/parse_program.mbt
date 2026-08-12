///|
// Parse variable declarations after a struct/union definition: struct Foo { ... } *ptr, arr[8];
fn Parser::parse_struct_vars(
  self : Parser,
  base_ty : Type,
) -> Unit raise ParseError {
  // Parse first declarator
  let decl = self.parse_declarator(base_ty)
  let post_decl_attrs = self.skip_attributes_info()
  if decl.name != "" {
    let mut decl_ty = self.apply_decl_attrs(
      resolve_var_type(decl),
      post_decl_attrs,
    )
    let mut init : GlobalInit? = None
    if self.token == Assign {
      self.advance()
      if self.token == LBrace {
        let init_exprs = self.parse_brace_init_exprs()
        let (final_ty, brace_init) = global_brace_initializer_for_type(
          decl_ty, init_exprs,
        )
        decl_ty = final_ty
        init = brace_init
      } else {
        init = Some(Scalar(self.parse_assign()))
      }
    }
    self.add_global({
      ty: decl_ty,
      name: decl.name,
      init,
      is_static: false,
      is_extern: false,
      is_weak: post_decl_attrs.is_weak,
      visibility: post_decl_attrs.visibility,
      symbol_alias: post_decl_attrs.symbol_alias,
      section: post_decl_attrs.section,
    })
    self.remember_value_type(decl.name, decl_ty)
  }
  // Additional variables separated by comma
  while self.token == Comma {
    self.advance()
    let extra = self.parse_declarator(base_ty)
    let extra_post_decl_attrs = self.skip_attributes_info()
    if extra.name != "" {
      let mut extra_ty = self.apply_decl_attrs(
        resolve_var_type(extra),
        extra_post_decl_attrs,
      )
      let mut extra_init : GlobalInit? = None
      if self.token == Assign {
        self.advance()
        if self.token == LBrace {
          let init_exprs = self.parse_brace_init_exprs()
          let (final_extra_ty, brace_init) = global_brace_initializer_for_type(
            extra_ty, init_exprs,
          )
          extra_ty = final_extra_ty
          extra_init = brace_init
        } else {
          extra_init = Some(Scalar(self.parse_assign()))
        }
      }
      self.add_global({
        ty: extra_ty,
        name: extra.name,
        init: extra_init,
        is_static: false,
        is_extern: false,
        is_weak: extra_post_decl_attrs.is_weak,
        visibility: extra_post_decl_attrs.visibility,
        symbol_alias: extra_post_decl_attrs.symbol_alias,
        section: extra_post_decl_attrs.section,
      })
      self.remember_value_type(extra.name, extra_ty)
    }
  }
  self.expect(Semicolon)
}

///|
fn Parser::parse_program(self : Parser) -> Program raise ParseError {
  let decls = []
  while self.token != EOF {
    while self.token == Ident("__extension__") {
      self.advance()
    }
    let saved_top_pos = self.lexer.pos
    let saved_top_token = self.token
    let leading_attrs = self.skip_attributes_info()
    if self.token == Typedef {
      self.parse_typedef_with_attrs(leading_attrs)
    } else {
      self.lexer.pos = saved_top_pos
      self.token = saved_top_token
      if self.is_static_assert_token() {
        self.parse_static_assert_decl()
      } else if self.token == Struct || self.token == Union {
        // Peek ahead to distinguish struct/union definition from function declaration
        let saved_pos = self.lexer.pos
        let saved_token = self.token
        let is_union = self.token == Union
        self.advance() // past struct/union
        let pragma_pack = self.current_pack()
        let leading_packed = self.skip_attributes_packed()
        match self.token {
          Ident(name) => {
            self.advance()
            let after_name_packed = self.skip_attributes_packed()
            if self.token == LBrace {
              // Struct/union definition
              self.expect(LBrace)
              let fields = self.parse_struct_body()
              self.expect(RBrace)
              let is_packed = leading_packed ||
                after_name_packed ||
                self.skip_attributes_packed()
              let pack = combine_pack(is_packed, pragma_pack)
              let decl = { name, fields, is_union, pack, is_anonymous: false }
              self.reserve_tag(name)
              self.add_aggregate(decl)
              self.struct_decls[name] = decl
              // Handle struct definition followed by variable declarations: struct Foo { ... } *ptr;
              if self.token != Semicolon {
                let aggregate_ty = if is_union {
                  Type::Union(name)
                } else {
                  Struct(name)
                }
                self.parse_struct_vars(aggregate_ty)
              } else {
                self.expect(Semicolon)
              }
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
                self.items.push(Func(decls.length() - 1))
              }
            }
          }
          _ => {
            self.lexer.pos = saved_pos
            self.token = saved_token
            let decl = self.parse_func_decl()
            if decl.name != "" {
              decls.push(decl)
              self.items.push(Func(decls.length() - 1))
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
          self.items.push(Func(decls.length() - 1))
        }
      }
    }
  }
  let known_decls : Map[String, Bool] = Map([])
  for decl in decls {
    known_decls[decl.name] = true
  }
  // Prototypes declared inside function bodies must precede the function
  // that declared them -- its body may call through them -- so they move to
  // the front of `decls` and take items entries ahead of the earliest
  // function. Keeping `decls` and `items` in the same order is what makes
  // the printed program reparse to the same views: a reparse reads the
  // prototypes first, so the first parse must store them first too.
  let promoted : Array[FuncDecl] = []
  for decl in self.local_func_decls {
    if decl.name != "" && !known_decls.contains(decl.name) {
      promoted.push(decl)
      known_decls[decl.name] = true
    }
  }
  if promoted.length() > 0 {
    for i, item in self.items {
      match item {
        Func(index) => self.items[i] = Func(index + promoted.length())
        _ => ()
      }
    }
    let mut at = self.items.length()
    for i, item in self.items {
      if item is Func(_) {
        at = i
        break
      }
    }
    for offset, decl in promoted {
      decls.insert(offset, decl)
      self.items.insert(at + offset, Func(offset))
    }
  }
  { structs: self.aggregates, globals: self.globals, decls, items: self.items }
}

///|
fn Parser::parse_typedef(self : Parser) -> Unit raise ParseError {
  self.parse_typedef_with_attrs(empty_attribute_info())
}

///|
fn Parser::parse_typedef_with_attrs(
  self : Parser,
  leading_attrs : AttributeInfo,
) -> Unit raise ParseError {
  self.expect(Typedef)
  self.skip_attributes()
  self.skip_qualifiers()
  let spec = self.parse_decl_specifiers()
  spec.align = merge_align(spec.align, leading_attrs.align)
  spec.mode = merge_mode(spec.mode, leading_attrs.mode)
  self.skip_attributes()
  // Parse first typedef declarator
  let decl = self.parse_declarator(spec.base_type)
  let post_decl_attrs = self.skip_attributes_info()
  self.typedefs[decl.name] = self.apply_decl_attrs(
    apply_decl_align(
      typedef_type_over_function_base(decl, spec.base_is_function),
      spec.align,
    ),
    post_decl_attrs,
  )
  self.remember_function_typedef(decl, spec.base_is_function)
  // Handle comma-separated typedef names: typedef int a, b, c;
  while self.token == Comma {
    self.advance()
    self.skip_attributes()
    self.skip_qualifiers()
    let extra_decl = self.parse_declarator(spec.base_type)
    let extra_post_decl_attrs = self.skip_attributes_info()
    self.typedefs[extra_decl.name] = self.apply_decl_attrs(
      apply_decl_align(
        typedef_type_over_function_base(extra_decl, spec.base_is_function),
        spec.align,
      ),
      extra_post_decl_attrs,
    )
    self.remember_function_typedef(extra_decl, spec.base_is_function)
  }
  self.expect(Semicolon)
}

///|
/// Records whether a typedef names a bare function type.
///
/// `typedef void F(int)` and `typedef char *F(int)` do: a direct function
/// declarator's stars belong to the return type, however many there are. So
/// does `typedef F G` over an existing function typedef. `typedef void
/// (*F)(int)` does not -- the parenthesized star made it a pointer, and the
/// declarator is not a direct function declarator -- and neither does
/// `typedef F *P`, whose star turns the function type into the pointer.
fn Parser::remember_function_typedef(
  self : Parser,
  decl : DeclaratorResult,
  base_is_function : Bool,
) -> Unit {
  if decl.is_func_decl || (base_is_function && decl.ptr_depth == 0) {
    self.function_typedefs[decl.name] = true
  } else {
    // A typedef that reuses the name for a non-function type must also
    // retire the marker, or `F *p` after `typedef int F;` would keep
    // absorbing its star as if `F` still named a function.
    self.function_typedefs.remove(decl.name)
  }
}

///|
/// The type a typedef declarator denotes when its base is a bare function
/// type.
///
/// The declarator's stars were applied as pointer wraps, but the first star
/// over a function type is the pointer the `FuncPtr` spelling already
/// carries: `typedef F *P` is one function pointer, not a pointer to one.
/// Peeling one wrap when any were applied is that rule; a starless declarator
/// or a base that is not a function type passes through unchanged.
fn typedef_type_over_function_base(
  decl : DeclaratorResult,
  base_is_function : Bool,
) -> Type {
  if base_is_function && decl.ptr_depth > 0 && !decl.is_func_decl {
    match decl.ty {
      Pointer(inner) => inner
      other => other
    }
  } else {
    decl.ty
  }
}

///|
fn Parser::parse_enum(self : Parser) -> Unit raise ParseError {
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
      _ => self.unexpected("an enum constant name")
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
