///|
fn Parser::skip_qualifiers(self : Parser) -> Unit {
  while self.token == Const || self.token == Restrict || self.token == Extern ||
        self.token == Static || self.token == Volatile || self.token == Inline ||
        self.token == Register || self.token == Auto ||
        self.token == Ident("__extension__") ||
        self.token == Ident("__inline") || self.token == Ident("__inline__") ||
        self.token == Ident("__restrict") || self.token == Ident("__restrict__") ||
        self.token == Ident("__signed") || self.token == Ident("__signed__") ||
        self.token == Ident("__unsigned") || self.token == Ident("__unsigned__") ||
        self.token == Ident("__volatile") || self.token == Ident("__volatile__") ||
        self.token == Ident("__const") || self.token == Ident("__const__") ||
        self.token == Ident("_Nullable") || self.token == Ident("_Nonnull") ||
        self.token == Ident("_Null_unspecified") {
    self.advance()
  }
}

///|
fn Parser::skip_attributes(self : Parser) -> Unit {
  while self.token == Ident("__attribute__") || self.token == Ident("__attribute") ||
        self.token == Ident("__asm") || self.token == Ident("__asm__") {
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

