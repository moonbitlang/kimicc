///|
/// Returns the printed form of a global initialized with `expr`.
fn printed_int(expr : String) -> String {
  let program = @parser.parse("int g = " + expr + ";")
  @printer.print_program(program).trim().to_owned()
}

///|
/// The literal prints exactly as written. `0xff` and `255` denote the same
/// value but are not the same program text, and a printer that turns one into
/// the other is guessing at what the author meant.
test "integer literals print as written" {
  inspect(printed_int("255"), content="int g = 255;")
  inspect(printed_int("0xff"), content="int g = 0xff;")
  inspect(printed_int("0XFF"), content="int g = 0XFF;")
  inspect(printed_int("0755"), content="int g = 0755;")
}

///|
/// The suffix is part of the text, so it needs no reconstruction -- which is
/// what retired the hexadecimal special case the old printer needed for values
/// with no decimal spelling.
test "suffixes print as written" {
  inspect(printed_int("1L"), content="int g = 1L;")
  inspect(printed_int("1ull"), content="int g = 1ull;")
  inspect(
    printed_int("0x8000000000000000ULL"),
    content="int g = 0x8000000000000000ULL;",
  )
}

///|
/// The value is a cache of the text, so the two must agree. This is the
/// invariant `int_literal` exists to maintain; a literal read from source keeps
/// whatever the lexer computed, and both paths are checked here.
test "the cached value agrees with the text" {
  for spelling in ["0", "255", "0xff", "0755", "1L", "0x10", "2147483647"] {
    let program = @parser.parse("int g = " + spelling + ";")
    match program.globals[0].init {
      Some(Scalar(Number(value, text, _))) => {
        assert_eq(text, spelling)
        // Re-lexing the text alone must yield the same value.
        let again = @parser.parse("int h = " + text + ";")
        match again.globals[0].init {
          Some(Scalar(Number(value_again, _, _))) =>
            assert_eq(value, value_again)
          _ => fail("expected an integer initializer for " + spelling)
        }
      }
      _ => fail("expected an integer initializer for " + spelling)
    }
  }
}
