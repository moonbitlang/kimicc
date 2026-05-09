///|
priv struct DeclSpec {
  mut base_type : Type
  mut is_static : Bool
  mut is_extern : Bool
  mut is_inline : Bool
  mut align : Int?
}

///|
priv struct DeclaratorResult {
  ty : Type
  name : String
  ptr_depth : Int
  func_params : Array[Param]?
  func_ret_ty : Type?
  is_func_decl : Bool
}

///|
priv struct AbstractDeclaratorResult {
  ty : Type
  ptr_depth : Int
}

///|
fn Parser::parse_decl_specifiers(self : Parser) -> DeclSpec {
  let spec : DeclSpec = {
    base_type: SInt,
    is_static: false,
    is_extern: false,
    is_inline: false,
    align: None,
  }
  self.skip_attributes()
  let mut has_void = false
  let mut has_char = false
  let mut has_short = false
  let mut long_count = 0
  let mut has_float = false
  let mut has_double = false
  let mut has_int128 = false
  let mut has_unsigned = false
  let mut has_bool = false
  let mut has_struct = false
  let mut struct_result = Type::SInt
  let mut has_enum = false
  let mut enum_result = Type::SInt
  let mut has_typedef_name = false
  let mut typedef_type = Type::SInt
  let mut has_atomic_type = false
  let mut atomic_type = Type::SInt
  let mut has_atomic_qualifier = false
  let mut saw_primitive = false
  let mut saw_typedef_name = false
  let mut has_va_list = false
  while true {
    self.skip_attributes()
    let mut consumed = false
    // Storage class specifiers
    if !consumed {
      match self.token {
        Typedef => {
          self.advance()
          consumed = true
        }
        Extern => {
          spec.is_extern = true
          self.advance()
          consumed = true
        }
        Static => {
          spec.is_static = true
          self.advance()
          consumed = true
        }
        Auto => {
          self.advance()
          consumed = true
        }
        Register => {
          self.advance()
          consumed = true
        }
        _ => ()
      }
    }
    // Function specifier
    if !consumed && self.token == Inline {
      spec.is_inline = true
      self.advance()
      consumed = true
    }
    // Type qualifiers and GCC attributes
    if !consumed {
      match self.token {
        Const | Restrict | Volatile => {
          self.advance()
          consumed = true
        }
        Ident("_Alignas") | Ident("alignas") => {
          let align = self.parse_alignas_specifier()
          match align {
            Some(n) =>
              if n > 0 {
                spec.align = match spec.align {
                  Some(prev) => Some(if n > prev { n } else { prev })
                  None => Some(n)
                }
              }
            None => ()
          }
          consumed = true
        }
        Ident("__extension__")
        | Ident("__inline")
        | Ident("__inline__")
        | Ident("__restrict")
        | Ident("__restrict__")
        | Ident("__signed")
        | Ident("__signed__")
        | Ident("__unsigned")
        | Ident("__unsigned__")
        | Ident("__volatile")
        | Ident("__volatile__")
        | Ident("__const")
        | Ident("__const__")
        | Ident("_Noreturn")
        | Ident("_Nullable")
        | Ident("_Nonnull")
        | Ident("_Null_unspecified") => {
          self.advance()
          consumed = true
        }
        _ => ()
      }
    }
    // Primitive type specifiers (can be combined: long long, unsigned int, etc.)
    if !consumed {
      match self.token {
        Void => {
          has_void = true
          self.advance()
          saw_primitive = true
          consumed = true
        }
        Char => {
          has_char = true
          self.advance()
          saw_primitive = true
          consumed = true
        }
        Short => {
          has_short = true
          self.advance()
          saw_primitive = true
          consumed = true
        }
        Int => {
          self.advance()
          saw_primitive = true
          consumed = true
        }
        Long => {
          long_count += 1
          if long_count > 2 {
            abort("Too many long specifiers")
          }
          self.advance()
          saw_primitive = true
          consumed = true
        }
        Float => {
          has_float = true
          self.advance()
          saw_primitive = true
          consumed = true
        }
        Double => {
          has_double = true
          self.advance()
          saw_primitive = true
          consumed = true
        }
        Signed => {
          self.advance()
          saw_primitive = true
          consumed = true
        }
        Unsigned => {
          has_unsigned = true
          self.advance()
          saw_primitive = true
          consumed = true
        }
        Bool => {
          has_bool = true
          self.advance()
          saw_primitive = true
          consumed = true
        }
        Struct => {
          has_struct = true
          struct_result = self.parse_struct_type_specifier()
          saw_primitive = true
          consumed = true
        }
        Union => {
          has_struct = true
          struct_result = self.parse_union_type_specifier()
          saw_primitive = true
          consumed = true
        }
        Enum => {
          enum_result = self.parse_enum_type_specifier()
          has_enum = true
          saw_primitive = true
          consumed = true
        }
        Ident(name) =>
          if name == "_Atomic" {
            self.advance()
            if self.token == LParen {
              self.advance()
              atomic_type = Atomic(self.parse_type_name())
              self.expect(RParen)
              has_atomic_type = true
              saw_primitive = true
            } else {
              has_atomic_qualifier = true
            }
            consumed = true
          } else if name == "__builtin_va_list" {
            spec.base_type = Pointer(SChar)
            has_va_list = true
            self.advance()
            saw_primitive = true
            consumed = true
          } else if name == "__uint128_t" {
            has_int128 = true
            has_unsigned = true
            self.advance()
            saw_primitive = true
            consumed = true
          } else if name == "__int128" || name == "__int128_t" {
            has_int128 = true
            self.advance()
            saw_primitive = true
            consumed = true
          } else if name == "_Float16" {
            self.advance()
            saw_primitive = true
            consumed = true
          } else if !saw_primitive &&
            !saw_typedef_name &&
            self.typedefs.contains(name) {
            has_typedef_name = true
            typedef_type = self.typedefs[name]
            self.advance()
            saw_typedef_name = true
            consumed = true
          }
        _ => ()
      }
    }
    if !consumed {
      break
    }
  }
  if has_atomic_type {
    spec.base_type = atomic_type
  } else if has_struct {
    spec.base_type = struct_result
  } else if has_enum {
    spec.base_type = enum_result
  } else if has_typedef_name {
    spec.base_type = typedef_type
  } else if has_va_list {
    // base_type already set to Pointer(SChar)
  } else if has_void {
    spec.base_type = Void
  } else if has_bool {
    spec.base_type = Bool
  } else if has_float {
    spec.base_type = Float
  } else if has_double {
    spec.base_type = Double
  } else if has_int128 {
    if has_unsigned {
      spec.base_type = UInt128
    } else {
      spec.base_type = SInt128
    }
  } else if has_char {
    if has_unsigned {
      spec.base_type = UChar
    } else {
      spec.base_type = SChar
    }
  } else if has_short {
    if has_unsigned {
      spec.base_type = UShort
    } else {
      spec.base_type = SShort
    }
  } else if long_count == 2 {
    if has_unsigned {
      spec.base_type = ULongLong
    } else {
      spec.base_type = SLongLong
    }
  } else if long_count == 1 {
    if has_unsigned {
      spec.base_type = ULong
    } else {
      spec.base_type = SLong
    }
  } else if has_unsigned {
    spec.base_type = UInt
  } else {
    spec.base_type = SInt
  }
  if has_atomic_qualifier {
    spec.base_type = Atomic(spec.base_type)
  }
  spec
}

///|
fn Parser::parse_struct_type_specifier(self : Parser) -> Type {
  self.expect(Struct)
  self.skip_attributes()
  match self.token {
    Ident(n) => {
      self.advance()
      if self.token == LBrace {
        self.expect(LBrace)
        let fields = self.parse_struct_body()
        self.expect(RBrace)
        let decl = { name: n, fields, is_union: false }
        self.anonymous_structs.push(decl)
        self.struct_decls[n] = decl
        Struct(n)
      } else {
        Struct(n)
      }
    }
    LBrace => {
      self.expect(LBrace)
      let fields = self.parse_struct_body()
      self.expect(RBrace)
      let name = "__anon_struct_" + self.anon_counter.to_string()
      self.anon_counter += 1
      let decl = { name, fields, is_union: false }
      self.anonymous_structs.push(decl)
      self.struct_decls[name] = decl
      Struct(name)
    }
    _ => abort("Expected struct name or {\n")
  }
}

///|
fn Parser::parse_union_type_specifier(self : Parser) -> Type {
  self.expect(Union)
  self.skip_attributes()
  match self.token {
    Ident(n) => {
      self.advance()
      if self.token == LBrace {
        self.expect(LBrace)
        let fields = self.parse_struct_body()
        self.expect(RBrace)
        let decl = { name: n, fields, is_union: true }
        self.anonymous_structs.push(decl)
        self.struct_decls[n] = decl
        Union(n)
      } else {
        Union(n)
      }
    }
    LBrace => {
      self.expect(LBrace)
      let fields = self.parse_struct_body()
      self.expect(RBrace)
      let name = "__anon_union_" + self.anon_counter.to_string()
      self.anon_counter += 1
      let decl = { name, fields, is_union: true }
      self.anonymous_structs.push(decl)
      self.struct_decls[name] = decl
      Union(name)
    }
    _ => abort("Expected union name or {\n")
  }
}

///|
fn Parser::parse_enum_type_specifier(self : Parser) -> Type {
  self.expect(Enum)
  self.skip_attributes()
  if self.token is Ident(_) {
    self.advance()
    self.skip_attributes()
  }
  let mut explicit_ty : Type? = None
  if self.token == Colon {
    self.advance()
    explicit_ty = Some(self.parse_type_name())
  }
  self.skip_attributes()
  let mut has_negative = false
  if self.token == LBrace {
    self.expect(LBrace)
    let mut next_value : Int64 = 0
    while self.token != RBrace {
      self.skip_attributes()
      match self.token {
        Ident(name) => {
          self.advance()
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
          if value < 0 {
            has_negative = true
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
        _ => abort("Expected enum constant name")
      }
    }
    self.expect(RBrace)
  }
  match explicit_ty {
    Some(ty) => ty
    None => if has_negative { SInt } else { UInt }
  }
}

///|
fn Parser::parse_struct_body(self : Parser) -> Array[Param] {
  let fields : Array[Param] = []
  while self.token != RBrace {
    self.skip_attributes()
    if self.is_static_assert_token() {
      self.parse_static_assert_decl()
      continue
    }
    self.skip_qualifiers()
    let spec = self.parse_decl_specifiers()
    let decl = self.parse_declarator(spec.base_type)
    let field_ty = apply_decl_align(decl.ty, spec.align)
    let bit_width = if self.token == Colon {
      self.advance()
      match self.fold_const(self.parse_assign()) {
        Some(n) => Some(n.to_int())
        None => abort("Bit-field width must be a constant integer")
      }
    } else {
      None
    }
    fields.push({ ty: field_ty, name: decl.name, bit_width })
    while self.token == Comma {
      self.advance()
      self.skip_attributes()
      self.skip_qualifiers()
      let extra = self.parse_declarator(spec.base_type)
      let extra_ty = apply_decl_align(extra.ty, spec.align)
      let extra_bit_width = if self.token == Colon {
        self.advance()
        match self.fold_const(self.parse_assign()) {
          Some(n) => Some(n.to_int())
          None => abort("Bit-field width must be a constant integer")
        }
      } else {
        None
      }
      fields.push({ ty: extra_ty, name: extra.name, bit_width: extra_bit_width })
    }
    self.expect(Semicolon)
  }
  fields
}

// Declarator parsing following C grammar

///|
fn Parser::parse_declarator(self : Parser, base_ty : Type) -> DeclaratorResult {
  if self.token == Star || self.token == BitXor {
    self.advance()
    self.skip_qualifiers()
    let decl = self.parse_declarator(Pointer(base_ty))
    return { ..decl, ptr_depth: decl.ptr_depth + 1 }
  }
  self.parse_direct_declarator(base_ty)
}

///|
fn Parser::parse_abstract_declarator(self : Parser, base_ty : Type) -> Type {
  self.parse_abstract_declarator_result(base_ty).ty
}

///|
fn Parser::parse_abstract_declarator_result(
  self : Parser,
  base_ty : Type,
) -> AbstractDeclaratorResult {
  if self.token == Star || self.token == BitXor {
    self.advance()
    self.skip_qualifiers()
    let decl = self.parse_abstract_declarator_result(Pointer(base_ty))
    return { ..decl, ptr_depth: decl.ptr_depth + 1 }
  }
  self.parse_direct_abstract_declarator_result(base_ty)
}

///|
fn function_param_info(params : Array[Param]) -> (Int, Bool) {
  if params.length() > 0 && params[params.length() - 1].name == "..." {
    (params.length() - 1, true)
  } else {
    (params.length(), false)
  }
}

///|
fn make_function_pointer_type(
  ty : Type,
  push_mode : Bool,
  ptr_depth : Int,
  named_count : Int,
  variadic : Bool,
) -> Type {
  if push_mode {
    return push_function_pointer_inside(ty, ptr_depth, named_count, variadic)
  }
  FuncPtr(ty, named_count, variadic)
}

///|
fn push_function_pointer_inside(
  ty : Type,
  ptr_depth : Int,
  named_count : Int,
  variadic : Bool,
) -> Type {
  match ty {
    Array(inner, size) =>
      Array(
        push_function_pointer_inside(inner, ptr_depth, named_count, variadic),
        size,
      )
    Pointer(ret) =>
      if ptr_depth <= 1 {
        FuncPtr(ret, named_count, variadic)
      } else {
        Pointer(
          push_function_pointer_inside(
            ret,
            ptr_depth - 1,
            named_count,
            variadic,
          ),
        )
      }
    _ => FuncPtr(ty, named_count, variadic)
  }
}

///|
fn type_contains_func_ptr(ty : Type) -> Bool {
  match ty {
    FuncPtr(_, _, _) => true
    Pointer(inner) | Array(inner, _) | Atomic(inner) | Aligned(inner, _) =>
      type_contains_func_ptr(inner)
    _ => false
  }
}

///|
fn apply_decl_align(ty : Type, align : Int?) -> Type {
  match align {
    Some(n) => if n > 0 { Aligned(ty, n) } else { ty }
    None => ty
  }
}

///|
fn Parser::parse_direct_declarator(
  self : Parser,
  base_ty : Type,
) -> DeclaratorResult {
  self.skip_attributes()
  match self.token {
    Ident(name) => {
      self.advance()
      self.parse_declarator_suffixes(base_ty, name, false, 0)
    }
    LParen => {
      self.advance()
      let inner = self.parse_declarator(base_ty)
      self.expect(RParen)
      let push_suffix_inside = inner.ptr_depth > 0
      let outer = self.parse_declarator_suffixes(
        inner.ty,
        inner.name,
        push_suffix_inside,
        inner.ptr_depth,
      )
      outer.set_func_info(inner)
    }
    _ => self.parse_declarator_suffixes(base_ty, "", false, 0)
  }
}

///|
fn Parser::parse_direct_abstract_declarator_result(
  self : Parser,
  base_ty : Type,
) -> AbstractDeclaratorResult {
  self.skip_attributes()
  match self.token {
    LParen =>
      if self.is_parenthesized_abstract_declarator() {
        self.advance()
        let inner = self.parse_abstract_declarator_result(base_ty)
        self.expect(RParen)
        {
          ty: self.parse_abstract_declarator_suffixes(
            inner.ty,
            true,
            inner.ptr_depth,
          ),
          ptr_depth: inner.ptr_depth,
        }
      } else {
        {
          ty: self.parse_abstract_declarator_suffixes(base_ty, false, 0),
          ptr_depth: 0,
        }
      }
    _ =>
      {
        ty: self.parse_abstract_declarator_suffixes(base_ty, false, 0),
        ptr_depth: 0,
      }
  }
}

///|
// Lookahead to determine if LParen starts a parenthesized abstract declarator
// or a function suffix (parameter list).
// A parenthesized abstract declarator contains * or ( inside.
// A function suffix contains parameter declarations or is empty.
fn Parser::is_parenthesized_abstract_declarator(self : Parser) -> Bool {
  let saved_pos = self.lexer.pos
  let saved_token = self.token
  self.advance() // past (
  let result = self.token == Star ||
    self.token == BitXor ||
    self.token == LParen
  self.lexer.pos = saved_pos
  self.token = saved_token
  result
}

///|
fn DeclaratorResult::set_func_info(
  self : DeclaratorResult,
  inner : DeclaratorResult,
) -> DeclaratorResult {
  if inner.func_params is Some(_) {
    {
      ..self,
      func_params: inner.func_params,
      func_ret_ty: inner.func_ret_ty,
      is_func_decl: inner.is_func_decl,
    }
  } else {
    self
  }
}

///|
fn Parser::parse_declarator_suffixes(
  self : Parser,
  base_ty : Type,
  name : String,
  push_mode : Bool,
  ptr_depth : Int,
) -> DeclaratorResult {
  let mut ty = base_ty
  let mut pending_arrays : Array[Int] = []
  let mut func_params : Array[Param]? = None
  let mut func_ret_ty : Type? = None
  let mut is_func_decl = false
  while true {
    match self.token {
      LBracket => {
        self.advance()
        // Skip C99 array parameter qualifiers: static, const, restrict, volatile
        while self.token == Static ||
              self.token == Const ||
              self.token == Restrict ||
              self.token == Volatile {
          self.advance()
        }
        let size = if self.token == RBracket {
          self.advance()
          0
        } else {
          let size_expr = self.parse_assign()
          self.expect(RBracket)
          match self.fold_const(size_expr) {
            Some(n) => n.to_int()
            None => 0
          }
        }
        pending_arrays.push(size)
      }
      LParen => {
        ty = apply_pending_array_suffixes(ty, pending_arrays, push_mode)
        pending_arrays = []
        self.advance()
        let params : Array[Param] = []
        if self.token != RParen {
          params.push(self.parse_param())
          while self.token == Comma {
            self.advance()
            params.push(self.parse_param())
          }
        }
        self.expect(RParen)
        let (named_count, variadic) = function_param_info(params)
        func_ret_ty = Some(ty)
        func_params = Some(params)
        ty = make_function_pointer_type(
          ty, push_mode, ptr_depth, named_count, variadic,
        )
        if !push_mode {
          is_func_decl = true
        }
      }
      _ => break
    }
  }
  ty = apply_pending_array_suffixes(ty, pending_arrays, push_mode)
  { ty, name, ptr_depth, func_params, func_ret_ty, is_func_decl }
}

///|
fn Parser::parse_abstract_declarator_suffixes(
  self : Parser,
  ty : Type,
  push_mode : Bool,
  ptr_depth : Int,
) -> Type {
  let mut result = ty
  let mut pending_arrays : Array[Int] = []
  while true {
    match self.token {
      LBracket => {
        self.advance()
        // Skip C99 array parameter qualifiers: static, const, restrict, volatile
        while self.token == Static ||
              self.token == Const ||
              self.token == Restrict ||
              self.token == Volatile {
          self.advance()
        }
        let size = if self.token == RBracket {
          self.advance()
          0
        } else {
          let size_expr = self.parse_assign()
          self.expect(RBracket)
          match self.fold_const(size_expr) {
            Some(n) => n.to_int()
            None => 0
          }
        }
        pending_arrays.push(size)
      }
      LParen => {
        result = apply_pending_array_suffixes(result, pending_arrays, push_mode)
        pending_arrays = []
        self.advance()
        let params : Array[Param] = []
        if self.token != RParen {
          params.push(self.parse_param())
          while self.token == Comma {
            self.advance()
            params.push(self.parse_param())
          }
        }
        self.expect(RParen)
        let (named_count, variadic) = function_param_info(params)
        result = make_function_pointer_type(
          result, push_mode, ptr_depth, named_count, variadic,
        )
      }
      _ => break
    }
  }
  result = apply_pending_array_suffixes(result, pending_arrays, push_mode)
  result
}

///|
fn apply_array_suffixes(ty : Type, sizes : Array[Int]) -> Type {
  let mut result = ty
  for i = sizes.length() - 1; i >= 0; i = i - 1 {
    result = Array(result, sizes[i])
  }
  result
}

///|
fn push_array_suffixes_inside(ty : Type, sizes : Array[Int]) -> Type {
  match ty {
    Pointer(inner) => Pointer(push_array_suffixes_inside(inner, sizes))
    _ => apply_array_suffixes(ty, sizes)
  }
}

///|
fn apply_pending_array_suffixes(
  ty : Type,
  sizes : Array[Int],
  push_mode : Bool,
) -> Type {
  if sizes.length() == 0 {
    ty
  } else if push_mode {
    push_array_suffixes_inside(ty, sizes)
  } else {
    apply_array_suffixes(ty, sizes)
  }
}

///|
// Parse a type-name (for casts and sizeof). Uses abstract declarator (no name required).
fn Parser::parse_type_name(self : Parser) -> Type {
  let spec = self.parse_decl_specifiers()
  self.parse_abstract_declarator(spec.base_type)
}
