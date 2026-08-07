///|
/// Parsing of floating literals from the text that was written.
///
/// The text is what the AST keeps, so this is the one place that turns it into
/// a value. Two reasons it lives here rather than in the lexer: `long double`
/// can be wider than `Double` on some targets, so parsing eagerly would
/// silently truncate what the program said; and folding a float is easy to get
/// subtly wrong, so it should be done once rather than at each consumer.

///|
/// Returns the value of a floating literal written as `text`, rounded to the
/// precision of `ty`.
///
/// Both C spellings are accepted: decimal with an optional exponent, and the
/// hexadecimal `0x1.8p3` form, which decimal parsing does not handle. Any
/// suffix is ignored, since `ty` already carries what it selected.
///
/// A `long double` wider than `Double` cannot be represented in the result. The
/// text remains authoritative, so a backend that supports the wider format can
/// parse it directly rather than inheriting this rounding.
///
/// ```mbt check
/// test {
///   inspect(@ctype.floating_literal_value("1.5", Double), content="1.5")
///   inspect(@ctype.floating_literal_value("0x1.8p1", Double), content="3")
///   // `0.1` is not representable in single precision, so it rounds.
///   inspect(@ctype.floating_literal_value("0.1", Float) == 0.1, content="false")
/// }
/// ```
pub fn floating_literal_value(text : String, ty : Type) -> Double {
  let digits = strip_float_suffix(text)
  let value = if is_hex_float(digits) {
    parse_hex_float(digits)
  } else {
    @string.parse_double(digits) catch {
      _ => 0.0
    }
  }
  match ty.core_type() {
    // A `float` literal is converted to single precision at translation time,
    // so the value the program means is the rounded one.
    Float => Float::from_double(value).to_double()
    _ => value
  }
}

///|
/// Reports whether the text uses the hexadecimal floating form.
fn is_hex_float(text : String) -> Bool {
  text.has_prefix("0x") || text.has_prefix("0X")
}

///|
/// Removes a trailing `f` or `l` suffix, which the type already records.
///
/// A hexadecimal literal's exponent is introduced by `p`, so its digits can
/// never end in `f` ambiguously.
fn strip_float_suffix(text : String) -> String {
  let length = text.length()
  guard length > 0 else { return text }
  if text[length - 1] is ('f' | 'F' | 'l' | 'L') {
    text[0:length - 1].to_owned()
  } else {
    text
  }
}

///|
/// Parses the hexadecimal floating form, `0x` digits `.` digits `p` exponent.
fn parse_hex_float(text : String) -> Double {
  let length = text.length()
  let mut i = 2 // past `0x`
  let mut mantissa = 0.0
  while i < length && hex_digit_of(text[i]) is Some(digit) {
    mantissa = mantissa * 16.0 + digit.to_double()
    i += 1
  }
  if i < length && text[i] is '.' {
    i += 1
    let mut scale = 1.0
    while i < length && hex_digit_of(text[i]) is Some(digit) {
      scale = scale * 16.0
      mantissa = mantissa + digit.to_double() / scale
      i += 1
    }
  }
  let mut exponent = 0
  if i < length && text[i] is ('p' | 'P') {
    i += 1
    let mut negative = false
    if i < length && text[i] is '-' {
      negative = true
      i += 1
    } else if i < length && text[i] is '+' {
      i += 1
    }
    while i < length && text[i] is ('0'..='9') {
      exponent = exponent * 10 + (text[i].to_int() - '0')
      i += 1
    }
    if negative {
      exponent = -exponent
    }
  }
  mantissa * power_of_two(exponent)
}

///|
/// Returns the value of a hexadecimal digit, or `None` for anything else.
fn hex_digit_of(ch : UInt16) -> Int? {
  if ch is ('0'..='9') {
    Some(ch.to_int() - '0')
  } else if ch is ('a'..='f') {
    Some(ch.to_int() - 'a' + 10)
  } else if ch is ('A'..='F') {
    Some(ch.to_int() - 'A' + 10)
  } else {
    None
  }
}

///|
/// Returns two raised to `exponent`, by repeated multiplication so that no
/// intermediate overflows for the exponents a literal can carry.
fn power_of_two(exponent : Int) -> Double {
  let mut result = 1.0
  let magnitude = if exponent < 0 { -exponent } else { exponent }
  for _ in 0..<magnitude {
    result = result * 2.0
  }
  if exponent < 0 {
    1.0 / result
  } else {
    result
  }
}
