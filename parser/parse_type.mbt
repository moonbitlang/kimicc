///|
fn Parser::skip_qualifiers(self : Parser) -> Unit {
  while self.token == Const || self.token == Restrict || self.token == Extern ||
        self.token == Static || self.token == Volatile {
    self.advance()
  }
}

///|
fn Parser::skip_attributes(self : Parser) -> Unit {
  while self.token == Ident("__attribute__") || self.token == Ident("__asm") {
    self.advance()
    self.expect(LParen)
    // Skip until balanced RParen
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
  }
}

///|
fn Parser::parse_type(self : Parser) -> Type {
  // Skip type qualifiers (const, restrict, extern, static, volatile)
  self.skip_qualifiers()
  // Handle type modifiers (signed, unsigned, short, long)
  let has_modifier = self.token == Signed || self.token == Unsigned ||
                     self.token == Short || self.token == Long
  if has_modifier {
    // Consume all consecutive modifiers: "unsigned short", "long long", etc.
    while self.token == Signed || self.token == Unsigned ||
          self.token == Short || self.token == Long {
      self.advance()
    }
    // After modifiers, the base type may be implicit or explicit
    self.skip_qualifiers()
    if self.token == Int || self.token == Char || self.token == Void {
      let base = match self.token {
        Int => { self.advance(); Type::Int }
        Char => { self.advance(); Type::Char }
        Void => { self.advance(); Type::Void }
        _ => Type::Int
      }
      self.skip_qualifiers()
      return self.parse_type_suffix(base)
    }
    // Modifier without explicit base type → int
    return self.parse_type_suffix(Type::Int)
  }
  let base = match self.token {
    Int => {
      self.advance()
      Type::Int
    }
    Void => {
      self.advance()
      Type::Void
    }
    Char => {
      self.advance()
      Type::Char
    }
    Float => {
      self.advance()
      Type::Int
    }
    Double => {
      self.advance()
      Type::Int
    }
    Struct => {
      self.advance()
      match self.token {
        Ident(n) => {
          self.advance()
          // Named struct with inline body: struct Name { ... }
          if self.token == LBrace {
            self.expect(LBrace)
            let fields = []
            while self.token != RBrace {
              self.skip_attributes()
              self.skip_qualifiers()
              fields.push(self.parse_param())
              self.expect(Semicolon)
            }
            self.expect(RBrace)
            self.anonymous_structs.push({ name: n, fields })
          }
          Type::Struct(n)
        }
        LBrace => {
          // Anonymous struct: parse body inline
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
              let name = match self.token {
                Ident(n) => { self.advance(); n }
                _ => ""
              }
              let f = self.parse_type_suffixes(base_type(first_field.ty), name)
              if self.token == Colon {
                self.advance()
                let _ = self.parse_assign()
              }
              fields.push(f)
            }
            self.expect(Semicolon)
          }
          self.skip_attributes()
          if self.token != RBrace {
          }
          self.expect(RBrace)
          let name = "__anon_struct_" + self.anon_counter.to_string()
          self.anon_counter += 1
          self.anonymous_structs.push({ name, fields })
          Type::Struct(name)
        }
        _ => abort("Expected struct name or {")
      }
    }
    Union => {
      self.advance()
      match self.token {
        Ident(n) => {
          self.advance()
          Type::Struct(n)
        }
        LBrace => {
          // Anonymous union: parse body inline, treat as struct
          self.expect(LBrace)
          let fields = []
          while self.token != RBrace {
            self.skip_attributes()
            self.skip_qualifiers()
            fields.push(self.parse_param())
            self.expect(Semicolon)
          }
          self.expect(RBrace)
          let name = "__anon_union_" + self.anon_counter.to_string()
          self.anon_counter += 1
          self.anonymous_structs.push({ name, fields })
          Type::Struct(name)
        }
        _ => abort("Expected union name or {")
      }
    }
    Ident(name) => {
      if self.typedefs.contains(name) {
        self.advance()
        self.typedefs[name]
      } else if name == "__builtin_va_list" {
        self.advance()
        // va_list is typically a char* or void* array on ARM64
        Pointer(Char)
      } else if name == "__uint128_t" {
        self.advance()
        // 128-bit integer not supported, treat as Int
        Type::Int
      } else {
        abort("Expected type, got identifier: " + name)
      }
    }
    Enum => {
      self.advance()
      // Optional enum name
      if self.token is Ident(_) {
        self.advance()
      }
      // Optional enum body
      if self.token == LBrace {
        self.expect(LBrace)
        let mut next_value = 0
        while self.token != RBrace {
          match self.token {
            Ident(name) => {
              self.advance()
              let value = if self.token == Assign {
                self.advance()
                match self.token {
                  Number(n) => { self.advance(); n }
                  _ => abort("Expected number in enum constant assignment")
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
      Type::Int
    }
    _ => {
      abort("Expected type, got " + self.token.to_string())
    }
  }
  self.skip_qualifiers()
  self.parse_type_suffix(base)
}

///|
fn Parser::parse_type_suffix(self : Parser, base : Type) -> Type {
  let mut ty = base
  while self.token == Star || self.token == BitXor {
    self.advance()
    self.skip_qualifiers()
    ty = Pointer(ty)
  }
  ty
}
