///|
fn Parser::is_static_assert_token(self : Parser) -> Bool {
  match self.token {
    Ident("_Static_assert")
    | Ident("__Static_assert")
    | Ident("static_assert") => true
    _ => false
  }
}

///|
fn Parser::parse_static_assert_decl(self : Parser) -> Unit raise ParseError {
  if !self.is_static_assert_token() {
    self.unexpected("a static assertion")
  }
  self.advance()
  self.expect(LParen)
  let expr = self.parse_assign()
  let failed = match self.fold_const(expr) {
    Some(0L) => true
    _ => false
  }
  let mut message = ""
  if self.token == Comma {
    self.advance()
    // C requires a string-literal message. Accept adjacent literals and keep
    // parsing tolerant for preprocessed system headers.
    while self.token is String(_) {
      match self.token {
        String(s) => if message == "" { message = s }
        _ => ()
      }
      self.advance()
    }
  }
  self.expect(RParen)
  self.expect(Semicolon)
  if failed {
    if message == "" {
      self.malformed("static assertion failed")
    } else {
      self.malformed("program: static assertion failed: " + message)
    }
  }
}
