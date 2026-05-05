///|
priv struct DeclSpec {
  mut base_type : Type
  mut is_typedef : Bool
  mut is_static : Bool
  mut is_extern : Bool
  mut is_inline : Bool
  mut is_register : Bool
  mut is_auto : Bool
}

///|
priv struct DeclaratorResult {
  ty : Type
  name : String
  func_params : Array[Param]?
  func_ret_ty : Type?
  is_func_decl : Bool
}

///|
fn Parser::parse_decl_specifiers(self : Parser) -> DeclSpec {
  let spec : DeclSpec = {
    base_type: SInt,
    is_typedef: false,
    is_static: false,
    is_extern: false,
    is_inline: false,
    is_register: false,
    is_auto: false,
  }
  self.skip_attributes()
  let mut has_void = false
  let mut has_char = false
  let mut has_short = false
  let mut long_count = 0
  let mut has_float = false
  let mut has_double = false
  let mut has_unsigned = false
  let mut has_bool = false
  let mut has_struct = false
  let mut struct_result = Type::SInt
  let mut has_typedef_name = false
  let mut typedef_type = Type::SInt
  let mut saw_primitive = false
  let mut saw_typedef_name = false
  let mut has_va_list = false
  while true {
    self.skip_attributes()
    let mut consumed = false
    // Storage class specifiers
    if not(consumed) {
      match self.token {
        Typedef => {
          spec.is_typedef = true
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
          spec.is_auto = true
          self.advance()
          consumed = true
        }
        Register => {
          spec.is_register = true
          self.advance()
          consumed = true
        }
        _ => ()
      }
    }
    // Function specifier
    if not(consumed) && self.token == Inline {
      spec.is_inline = true
      self.advance()
      consumed = true
    }
    // Type qualifiers and GCC attributes
    if not(consumed) {
      match self.token {
        Const | Restrict | Volatile => {
          self.advance()
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
    if not(consumed) {
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
          spec.base_type = self.parse_enum_type_specifier()
          saw_primitive = true
          consumed = true
        }
        Ident(name) =>
          if name == "_Atomic" {
            self.advance()
            if self.token == LParen {
              self.advance()
              let _ = self.parse_type_name()
              self.expect(RParen)
            }
            saw_primitive = true
            consumed = true
          } else if name == "__builtin_va_list" {
            spec.base_type = Pointer(SChar)
            has_va_list = true
            self.advance()
            saw_primitive = true
            consumed = true
          } else if name == "__uint128_t" ||
            name == "__int128" ||
            name == "_Float16" {
            self.advance()
            saw_primitive = true
            consumed = true
          } else if not(saw_primitive) &&
            not(saw_typedef_name) &&
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
    if not(consumed) {
      break
    }
  }
  if has_struct {
    spec.base_type = struct_result
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
        self.anonymous_structs.push({ name: n, fields, is_union: false })
        Type::Struct(n)
      } else {
        Type::Struct(n)
      }
    }
    LBrace => {
      self.expect(LBrace)
      let fields = self.parse_struct_body()
      self.expect(RBrace)
      let name = "__anon_struct_" + self.anon_counter.to_string()
      self.anon_counter += 1
      self.anonymous_structs.push({ name, fields, is_union: false })
      Type::Struct(name)
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
        self.anonymous_structs.push({ name: n, fields, is_union: true })
        Type::Union(n)
      } else {
        Type::Union(n)
      }
    }
    LBrace => {
      self.expect(LBrace)
      let fields = self.parse_struct_body()
      self.expect(RBrace)
      let name = "__anon_union_" + self.anon_counter.to_string()
      self.anon_counter += 1
      self.anonymous_structs.push({ name, fields, is_union: true })
      Type::Union(name)
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
  if self.token == Colon {
    self.advance()
    let _ = self.parse_type_name()
  }
  self.skip_attributes()
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
          self.enum_constants[name] = value
          next_value = value + 1
          if self.token == Comma {
            self.advance()
          }
        }
        _ => abort("Expected enum constant name")
      }
    }
    self.expect(RBrace)
  }
  Type::SInt
}

///|
fn Parser::parse_struct_body(self : Parser) -> Array[Param] {
  let fields : Array[Param] = []
  while self.token != RBrace {
    self.skip_attributes()
    self.skip_qualifiers()
    let spec = self.parse_decl_specifiers()
    let decl = self.parse_declarator(spec.base_type)
    let bit_width = if self.token == Colon {
      self.advance()
      match self.fold_const(self.parse_assign()) {
        Some(n) => Some(n.to_int())
        None => abort("Bit-field width must be a constant integer")
      }
    } else {
      None
    }
    fields.push({ ty: decl.ty, name: decl.name, bit_width })
    while self.token == Comma {
      self.advance()
      self.skip_attributes()
      self.skip_qualifiers()
      let extra = self.parse_declarator(spec.base_type)
      let extra_bit_width = if self.token == Colon {
        self.advance()
        match self.fold_const(self.parse_assign()) {
          Some(n) => Some(n.to_int())
          None => abort("Bit-field width must be a constant integer")
        }
      } else {
        None
      }
      fields.push({ ty: extra.ty, name: extra.name, bit_width: extra_bit_width })
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
    return self.parse_declarator(Pointer(base_ty))
  }
  self.parse_direct_declarator(base_ty)
}

///|
fn Parser::parse_abstract_declarator(self : Parser, base_ty : Type) -> Type {
  if self.token == Star || self.token == BitXor {
    self.advance()
    self.skip_qualifiers()
    return self.parse_abstract_declarator(Pointer(base_ty))
  }
  self.parse_direct_abstract_declarator(base_ty)
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
      self.parse_declarator_suffixes(base_ty, name, false)
    }
    LParen => {
      self.advance()
      let inner = self.parse_declarator(base_ty)
      self.expect(RParen)
      let outer = self.parse_declarator_suffixes(inner.ty, inner.name, true)
      outer.set_func_info(inner)
    }
    _ => self.parse_declarator_suffixes(base_ty, "", false)
  }
}

///|
fn Parser::parse_direct_abstract_declarator(
  self : Parser,
  base_ty : Type,
) -> Type {
  self.skip_attributes()
  match self.token {
    LParen =>
      if self.is_parenthesized_abstract_declarator() {
        self.advance()
        let inner_ty = self.parse_abstract_declarator(base_ty)
        self.expect(RParen)
        self.parse_abstract_declarator_suffixes(inner_ty, true)
      } else {
        self.parse_abstract_declarator_suffixes(base_ty, false)
      }
    _ => self.parse_abstract_declarator_suffixes(base_ty, false)
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
  if inner.func_params.is_some() {
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
) -> DeclaratorResult {
  let mut ty = base_ty
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
        if push_mode {
          ty = push_array_inside(ty, size)
        } else {
          ty = Array(ty, size)
        }
      }
      LParen => {
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
        func_ret_ty = Some(ty)
        func_params = Some(params)
        ty = Pointer(Void)
        if !push_mode {
          is_func_decl = true
        }
      }
      _ => break
    }
  }
  { ty, name, func_params, func_ret_ty, is_func_decl }
}

///|
fn Parser::parse_abstract_declarator_suffixes(
  self : Parser,
  ty : Type,
  push_mode : Bool,
) -> Type {
  let mut result = ty
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
        if push_mode {
          result = push_array_inside(result, size)
        } else {
          result = Array(result, size)
        }
      }
      LParen => {
        self.advance()
        if self.token != RParen {
          let _ = self.parse_param()
          while self.token == Comma {
            self.advance()
            let _ = self.parse_param()
          }
        }
        self.expect(RParen)
        result = Pointer(Void)
      }
      _ => break
    }
  }
  result
}

///|
fn push_array_inside(ty : Type, size : Int) -> Type {
  match ty {
    Pointer(inner) => Pointer(push_array_inside(inner, size))
    _ => Type::Array(ty, size)
  }
}

///|
// Parse a type-name (for casts and sizeof). Uses abstract declarator (no name required).
fn Parser::parse_type_name(self : Parser) -> Type {
  let spec = self.parse_decl_specifiers()
  self.parse_abstract_declarator(spec.base_type)
}
