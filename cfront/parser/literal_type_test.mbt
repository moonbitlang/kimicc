///|
/// Returns the type the parser gives the literal in `return <expr>;`.
fn literal_type(expr : String) -> String {
  let program = @parser.parse("int f(void) { return " + expr + "; }")
  match program.decls[0].body {
    Some(Compound([Return(Some(Number(_, _, ty)))])) => ty.to_string()
    Some(Compound([Return(Some(FloatLiteral(_, ty)))])) => ty.to_string()
    _ => "unexpected"
  }
}

///|
/// A literal's suffix selects its type. Dropping it made `sizeof(1L)` report 4
/// and `sizeof(0xffffffffu)` report 8.
test "integer suffixes select the literal type" {
  inspect(literal_type("1"), content="SInt")
  inspect(literal_type("1u"), content="UInt")
  inspect(literal_type("1L"), content="SLong")
  inspect(literal_type("1UL"), content="ULong")
  inspect(literal_type("1LL"), content="SLongLong")
  inspect(literal_type("1ULL"), content="ULongLong")
  inspect(literal_type("0xffffffffu"), content="UInt")
  inspect(literal_type("0x10L"), content="SLong")
}

///|
/// An unsuffixed literal takes the first type that can represent it. The
/// widened choice here is `long long` rather than C's `long`; both are 64 bits
/// on the supported targets, so only the spelling differs, and this is
/// pre-existing behaviour of the shared literal-type table.
test "unsuffixed literals widen by value" {
  inspect(literal_type("2147483647"), content="SInt")
  inspect(literal_type("2147483648"), content="SLongLong")
}

///|
/// A character constant has type `int` in C, not `char`.
test "character constants are int" {
  inspect(literal_type("'a'"), content="SInt")
}

///|
/// Floating suffixes are recorded too, even though type inference still reports
/// `double` for them until the code generators can hold a single-precision
/// constant.
test "floating suffixes select the literal type" {
  inspect(literal_type("1.0"), content="Double")
  inspect(literal_type("1.0f"), content="Float")
  inspect(literal_type("1.0L"), content="LongDouble")
}
