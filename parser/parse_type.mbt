///|
priv struct AttributeInfo {
  mut is_packed : Bool
  mut align : Int?
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
  let info : AttributeInfo = { is_packed: false, align: None }
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
fn Parser::skip_attributes_packed(self : Parser) -> Bool {
  self.skip_attributes_info().is_packed
}

///|
fn Parser::skip_attributes_align(self : Parser) -> Int? {
  self.skip_attributes_info().align
}

///|
fn Parser::skip_attributes(self : Parser) -> Unit {
  let _ = self.skip_attributes_info()
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
