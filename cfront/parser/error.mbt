///|
/// A position in the source text.
///
/// `offset` is the byte index the lexer works in; `line` and `column` are
/// derived from it and are both 1-based. They are computed when an error is
/// raised rather than tracked per token, because the parsing path never needs
/// them and tracking them would cost on every character.
pub(all) struct Position {
  offset : Int
  line : Int
  column : Int
} derive(Eq, Debug)

///|
/// Renders a position as `line:column`.
pub impl Show for Position with fn to_string(self) {
  self.line.to_string() + ":" + self.column.to_string()
}

///|
/// Returns the line and column of `offset` within `source`.
///
/// Scanning from the start each time is fine: this runs only when an error is
/// being reported.
pub fn position_at(source : String, offset : Int) -> Position {
  let limit = if offset < source.length() { offset } else { source.length() }
  let mut line = 1
  let mut column = 1
  for i in 0..<limit {
    if source[i] is '\n' {
      line += 1
      column = 1
    } else {
      column += 1
    }
  }
  { offset, line, column }
}

///|
/// Why a translation unit could not be read.
///
/// Raised rather than fatal: `cfront` is a library, and a caller feeding it
/// generated or untrusted C needs a diagnostic back, not a dead process.
///
/// When the parser itself is converted, `Unsupported` will matter as much as
/// `Unexpected`: the parser covers a subset of C, so a caller handing it
/// real-world source meets constructs that are valid and simply not
/// implemented, and that should be a diagnostic rather than a crash.
/// Only `Malformed` exists so far, because only the lexer raises yet. The
/// parser's own failures -- an unexpected token, a construct it does not
/// implement -- gain their variants as it is converted.
pub(all) suberror ParseError {
  /// A literal or token is malformed.
  Malformed(position~ : Position, what~ : String)
} derive(Eq, Debug)

///|
/// Renders a diagnostic as `line:column: message`, the form editors parse.
pub impl Show for ParseError with fn to_string(self) {
  match self {
    Malformed(position~, what~) => position.to_string() + ": malformed " + what
  }
}
