///|
/// Returns the printed form of `expr` used as a global initializer.
fn printed_initializer(expr : String) -> String {
  let program = @parser.parse("double g = " + expr + ";")
  let text = @printer.print_program(program)
  text.trim().to_owned()
}

///|
/// The literal is printed exactly as written. Keeping the text is what makes
/// this possible: a parsed value would have to be reformatted, and any
/// reformatting is a guess about what the author meant.
test "floating literals print as written" {
  inspect(printed_initializer("1.5"), content="double g = 1.5;")
  inspect(printed_initializer("1.50"), content="double g = 1.50;")
  inspect(printed_initializer("1e3"), content="double g = 1e3;")
  inspect(printed_initializer("0.1"), content="double g = 0.1;")
}

///|
/// A hexadecimal float keeps its spelling too, rather than being rendered as
/// the nearest decimal.
test "hexadecimal floats keep their spelling" {
  inspect(printed_initializer("0x1.8p1"), content="double g = 0x1.8p1;")
}

///|
/// The suffix is reconstructed from the type, so the literal reparses with the
/// type it had.
test "floating suffixes survive a round trip" {
  inspect(printed_initializer("1.5f"), content="double g = 1.5f;")
  inspect(printed_initializer("1.5L"), content="double g = 1.5L;")
}
