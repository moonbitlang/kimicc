///|
priv struct AttributeInfo {
  mut is_packed : Bool
  mut align : Int?
  mut mode : String?
  mut is_weak : Bool
  mut visibility : String?
  mut symbol_alias : String?
  mut section : String?
  mut is_constructor : Bool
  mut is_destructor : Bool
}

///|
fn merge_align(lhs : Int?, rhs : Int?) -> Int? {
  match (lhs, rhs) {
    (Some(a), Some(b)) => Some(if a > b { a } else { b })
    (Some(_), None) => lhs
    (None, Some(_)) => rhs
    (None, None) => None
  }
}

///|
fn merge_mode(lhs : String?, rhs : String?) -> String? {
  match rhs {
    Some(_) => rhs
    None => lhs
  }
}

///|
fn merge_visibility(lhs : String?, rhs : String?) -> String? {
  match rhs {
    Some(_) => rhs
    None => lhs
  }
}

///|
fn merge_alias(lhs : String?, rhs : String?) -> String? {
  match rhs {
    Some(_) => rhs
    None => lhs
  }
}

///|
fn merge_section(lhs : String?, rhs : String?) -> String? {
  match rhs {
    Some(_) => rhs
    None => lhs
  }
}

///|
fn Parser::skip_qualifiers(self : Parser) -> Unit {
  while self.token == Const ||
        self.token == Restrict ||
        self.token == Extern ||
        self.token == Static ||
        self.token == Volatile ||
        self.token == Inline ||
        self.token == Register ||
        self.token == Auto ||
        self.token == Ident("__extension__") ||
        self.token == Ident("__inline") ||
        self.token == Ident("__inline__") ||
        self.token == Ident("__restrict") ||
        self.token == Ident("__restrict__") ||
        self.token == Ident("__signed") ||
        self.token == Ident("__signed__") ||
        self.token == Ident("__unsigned") ||
        self.token == Ident("__unsigned__") ||
        self.token == Ident("__volatile") ||
        self.token == Ident("__volatile__") ||
        self.token == Ident("__const") ||
        self.token == Ident("__const__") ||
        self.token == Ident("_Noreturn") ||
        self.token == Ident("_Nullable") ||
        self.token == Ident("_Nonnull") ||
        self.token == Ident("_Null_unspecified") {
    self.advance()
  }
}

///|
fn Parser::skip_attributes_info(self : Parser) -> AttributeInfo {
  let info : AttributeInfo = {
    is_packed: false,
    align: None,
    mode: None,
    is_weak: false,
    visibility: None,
    symbol_alias: None,
    section: None,
    is_constructor: false,
    is_destructor: false,
  }
  while self.token == Ident("__attribute__") ||
        self.token == Ident("__attribute") ||
        self.token == Ident("__asm") ||
        self.token == Ident("__asm__") {
    let tracks_packed = self.token == Ident("__attribute__") ||
      self.token == Ident("__attribute")
    self.advance()
    self.expect(LParen)
    // Skip until balanced RParen
    let mut depth = 1
    while depth > 0 && self.token != EOF {
      if tracks_packed {
        match self.token {
          Ident("packed") | Ident("__packed__") => info.is_packed = true
          Ident("weak") | Ident("__weak__") => info.is_weak = true
          Ident("constructor") | Ident("__constructor__") =>
            info.is_constructor = true
          Ident("destructor") | Ident("__destructor__") =>
            info.is_destructor = true
          Ident("alias") | Ident("__alias__") => {
            self.advance()
            if self.token == LParen {
              self.advance()
              match self.token {
                String(name) => {
                  info.symbol_alias = Some(name)
                  self.advance()
                }
                _ => ()
              }
              self.expect(RParen)
            }
            continue
          }
          Ident("section") | Ident("__section__") => {
            self.advance()
            if self.token == LParen {
              self.advance()
              match self.token {
                String(name) => {
                  info.section = Some(name)
                  self.advance()
                }
                _ => ()
              }
              self.expect(RParen)
            }
            continue
          }
          Ident("visibility") | Ident("__visibility__") => {
            self.advance()
            if self.token == LParen {
              self.advance()
              match self.token {
                String(name) => {
                  info.visibility = Some(name)
                  self.advance()
                }
                _ => ()
              }
              self.expect(RParen)
            }
            continue
          }
          Ident("vector_size")
          | Ident("__vector_size__")
          | Ident("ext_vector_type")
          | Ident("__ext_vector_type__") =>
            abort("vector types are not supported")
          Ident("mode") | Ident("__mode__") => {
            self.advance()
            if self.token == LParen {
              self.advance()
              match self.token {
                Ident(mode_name) => {
                  info.mode = Some(canonical_mode_name(mode_name))
                  self.advance()
                }
                _ => ()
              }
              self.expect(RParen)
            }
            continue
          }
          Ident("aligned") | Ident("__aligned__") => {
            self.advance()
            if self.token == LParen {
              self.advance()
              let expr = self.parse_assign()
              self.expect(RParen)
              match self.fold_const(expr) {
                Some(n) => {
                  let align = n.to_int()
                  if align > 0 {
                    info.align = merge_align(info.align, Some(align))
                  }
                }
                None => ()
              }
            }
            continue
          }
          _ => ()
        }
      }
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
  }
  info
}

///|
fn canonical_mode_name(name : String) -> String {
  let mut start = 0
  let mut end = name.length()
  if name.length() >= 2 && name[0] == '_' && name[1] == '_' {
    start = 2
  }
  if end - start >= 2 && name[end - 1] == '_' && name[end - 2] == '_' {
    end = end - 2
  }
  name[start:end].to_owned()
}

///|
fn type_is_unsigned_integer(ty : Type) -> Bool {
  match ty {
    Bool | UChar | UShort | UInt | ULong | ULongLong | UInt128 => true
    Atomic(inner) | Aligned(inner, _) => type_is_unsigned_integer(inner)
    _ => false
  }
}

///|
fn sized_integer_type(unsigned : Bool, bits : Int) -> Type {
  match bits {
    8 => if unsigned { UChar } else { SChar }
    16 => if unsigned { UShort } else { SShort }
    32 => if unsigned { UInt } else { SInt }
    64 => if unsigned { ULong } else { SLong }
    128 => if unsigned { UInt128 } else { SInt128 }
    _ => abort("unsupported mode integer width")
  }
}

///|
fn Parser::apply_decl_mode(self : Parser, ty : Type, mode : String?) -> Type {
  match mode {
    None => ty
    Some(name) => {
      let unsigned = type_is_unsigned_integer(ty)
      let word_bits = match self.target {
        DarwinArm64 | LinuxAmd64 => 64
      }
      match name {
        "QI" => sized_integer_type(unsigned, 8)
        "HI" => sized_integer_type(unsigned, 16)
        "SI" => sized_integer_type(unsigned, 32)
        "DI" => sized_integer_type(unsigned, 64)
        "word" | "unwind_word" => sized_integer_type(unsigned, word_bits)
        "TI" => sized_integer_type(unsigned, 128)
        "HF" => Float16
        "SF" => Float
        "DF" => Double
        "XF" => LongDouble
        "TF" => Float128
        "HC" | "SC" | "DC" | "XC" | "TC" =>
          abort("_Complex types are not supported")
        "V2QI"
        | "V4QI"
        | "V8QI"
        | "V16QI"
        | "V2HI"
        | "V4HI"
        | "V8HI"
        | "V2SI"
        | "V4SI"
        | "V2DI"
        | "V4SF"
        | "V2DF" => abort("vector types are not supported")
        _ => abort("unsupported mode attribute: " + name)
      }
    }
  }
}

///|
fn Parser::apply_decl_attrs(
  self : Parser,
  ty : Type,
  attrs : AttributeInfo,
) -> Type {
  apply_decl_align(self.apply_decl_mode(ty, attrs.mode), attrs.align)
}

///|
fn Parser::skip_attributes_packed(self : Parser) -> Bool {
  self.skip_attributes_info().is_packed
}

///|
fn Parser::skip_attributes(self : Parser) -> Unit {
  let _ = self.skip_attributes_info()
}

///|
fn Parser::is_type_name_start(self : Parser) -> Bool {
  match self.token {
    Int
    | Void
    | Char
    | Struct
    | Union
    | Signed
    | Unsigned
    | Short
    | Long
    | Float
    | Double
    | Bool
    | Enum
    | Const
    | Restrict
    | Volatile
    | Static
    | Extern
    | Inline => true
    Ident(name) =>
      name == "_Float16" ||
      name == "__float128" ||
      name == "_Float128" ||
      is_extended_float_type_name(name) ||
      name == "__int128" ||
      name == "__int128_t" ||
      name == "__uint128_t" ||
      name == "_BitInt" ||
      name == "_Complex" ||
      name == "__complex__" ||
      name == "_Atomic" ||
      name == "_Alignas" ||
      name == "alignas" ||
      name == "__typeof" ||
      name == "__typeof__" ||
      name == "typeof" ||
      self.typedefs.contains(name)
    _ => false
  }
}

///|
fn Parser::parse_typeof_specifier(self : Parser) -> Type {
  match self.token {
    Ident("__typeof") | Ident("__typeof__") | Ident("typeof") => ()
    _ => abort("Expected typeof specifier")
  }
  self.advance()
  self.expect(LParen)
  let ty = if self.is_type_name_start() {
    self.parse_type_name()
  } else {
    let expr = self.parse_expr()
    self.const_expr_type(expr)
  }
  self.expect(RParen)
  ty
}

///|
fn Parser::parse_alignas_specifier(self : Parser) -> Int? {
  match self.token {
    Ident("_Alignas") | Ident("alignas") => ()
    _ => return None
  }
  self.advance()
  self.expect(LParen)
  let expr = self.parse_assign()
  self.expect(RParen)
  match self.fold_const(expr) {
    Some(n) => Some(n.to_int())
    None => None
  }
}
