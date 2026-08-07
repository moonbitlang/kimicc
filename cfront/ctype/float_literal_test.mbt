///|
/// The accessor is the one place a floating literal becomes a number, so the
/// cases that are easy to get wrong are pinned here rather than at each caller.
test "decimal and hexadecimal spellings parse to the same value" {
  inspect(@ctype.floating_literal_value("1.5", Double), content="1.5")
  inspect(@ctype.floating_literal_value("0x1.8p1", Double), content="3")
  inspect(@ctype.floating_literal_value("0x1p-1", Double), content="0.5")
  inspect(@ctype.floating_literal_value("1e3", Double), content="1000")
}

///|
/// A `float` literal is converted to single precision at translation time, so
/// the value is the rounded one. `0.1` is the standard witness: it is not
/// representable in either precision, and the two roundings differ.
test "float literals round to single precision" {
  let as_double = @ctype.floating_literal_value("0.1", Double)
  let as_float = @ctype.floating_literal_value("0.1", Float)
  inspect(as_double == 0.1, content="true")
  inspect(as_float == as_double, content="false")
  // Rounding is idempotent: converting the rounded value again changes nothing.
  inspect(
    @ctype.floating_literal_value(as_float.to_string(), Float) == as_float,
    content="true",
  )
}

///|
/// A suffix is part of the written text but the type already records it, so it
/// must not disturb the value.
test "suffixes do not affect the value" {
  inspect(@ctype.floating_literal_value("1.5f", Float), content="1.5")
  inspect(@ctype.floating_literal_value("1.5L", LongDouble), content="1.5")
}
