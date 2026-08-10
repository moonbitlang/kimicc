///|
/// A position is reported as 1-based line and column, which is what editors and
/// other compilers expect.
test "positions are 1-based line and column" {
  let source = "int a;\nint b;\nint c;"
  inspect(@parser.position_at(source, 0).to_string(), content="1:1")
  inspect(@parser.position_at(source, 7).to_string(), content="2:1")
  inspect(@parser.position_at(source, 11).to_string(), content="2:5")
  // An offset past the end clamps rather than failing.
  inspect(@parser.position_at(source, 9999).to_string(), content="3:7")
}

///|
/// The lexer reports malformed input by raising, with the position of the
/// offending text rather than a bare message.
test "the lexer raises with a position" {
  let lexer = @parser.Lexer::new("int a = \"unterminated;")
  try {
    for _ in 0..<8 {
      ignore(lexer.next_token())
    }
  } catch {
    Malformed(position~, what~) => {
      inspect(what, content="unterminated string literal")
      inspect(position.line, content="1")
    }
    other => fail("unexpected diagnostic: \{other}")
  } noraise {
    _ => fail("expected the unterminated string to be reported")
  }
}

///|
/// A diagnostic renders in the `line:column: message` form.
test "diagnostics render for humans" {
  let error = @parser.ParseError::Malformed(
    position=@parser.position_at("a\nbc", 3),
    what="octal literal",
  )
  inspect(error.to_string(), content="2:2: malformed octal literal")
}

///|
/// Reports the position where the offending text *starts*, not where the scan
/// stopped. A diagnostic pointing past the problem sends the reader to
/// unrelated input, which is the failure mode the string case already had.
test "diagnostics point at the offending text" {
  // The invalid digit, not the end of the literal or its suffix.
  inspect(
    lex_error("int a = 078u;").to_string(),
    content="1:11: malformed octal literal",
  )
  // Where the `..` begins, not the token after it.
  inspect(
    lex_error("int a[..x];").to_string(),
    content="1:8: malformed `..`, which is not a C token",
  )
  // Where the literal opens, not end of file.
  inspect(
    lex_error("char *s = \"oops;").to_string(),
    content="1:11: malformed unterminated string literal",
  )
}

///|
/// Lexes until something is reported, returning the diagnostic.
fn lex_error(source : String) -> @parser.ParseError {
  let lexer = @parser.Lexer::new(source)
  try {
    for _ in 0..<64 {
      if lexer.next_token() is EOF {
        break
      }
    }
    Malformed(position=@parser.position_at(source, 0), what="nothing reported")
  } catch {
    error => error
  }
}

///|
/// The recoverable contract has no holes: a caller that catches `ParseError`
/// must not be able to hit an `abort` instead. These are the paths review found
/// still bypassing it -- a malformed literal after the first token, an
/// unsupported construct, and a failing static assertion.
test "no input reaches abort instead of a diagnostic" {
  for
    source in [
      "int a;\nchar *s = \"oops;", "_Complex double z;", "int main(void) { _Static_assert(0, \"boom\"); return 0; }",
      "int f(void) { return foo bar; }", "int a = 09;",
    ] {
    try {
      ignore(@parser.parse(source))
      fail("expected a diagnostic for: " + source)
    } catch {
      _ => ()
    }
  }
}

///|
/// A diagnostic points at where the offending token starts, not at whatever
/// follows it. The lexer has already advanced past the token by the time the
/// parser objects, so this needs the token's start to be remembered.
test "diagnostics point at the offending token" {
  try {
    ignore(@parser.parse("int f(void) { return foo bar; }"))
    fail("expected a diagnostic")
  } catch {
    error =>
      inspect(error.to_string(), content="1:26: expected ;, found Ident(bar)")
  }
}
