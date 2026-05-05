///|
pub(all) enum Token {
  EOF
  Ident(String)
  Number(Int64)
  FloatLiteral(Double)
  String(String)
  Int
  Void
  Char
  Struct
  Union
  Typedef
  Const
  Restrict
  Extern
  Static
  Volatile
  Signed
  Unsigned
  Short
  Long
  Float
  Double
  Bool
  If
  Else
  While
  Return
  Sizeof
  Inline
  Register
  Auto
  For
  Enum
  Switch
  Case
  Default
  Break
  Goto
  Continue
  Do
  Ellipsis
  Plus
  Minus
  PlusPlus
  MinusMinus
  Star
  Slash
  Percent
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
  And
  Or
  BitOr
  BitXor
  LShift
  RShift
  BitNot
  Not
  Assign
  PlusEq
  MinusEq
  StarEq
  SlashEq
  PercentEq
  BitOrEq
  AmpersandEq
  BitXorEq
  LShiftEq
  RShiftEq
  Semicolon
  Comma
  LParen
  RParen
  LBrace
  RBrace
  LBracket
  RBracket
  Dot
  Arrow
  Colon
  Question
  Ampersand
} derive(Eq)

///|
impl Show for Token with to_string(self) {
  match self {
    EOF => "EOF"
    Ident(s) => "Ident(" + s + ")"
    Number(n) => "Number(" + n.to_string() + ")"
    FloatLiteral(v) => "FloatLiteral(" + v.to_string() + ")"
    String(s) => "String(" + s + ")"
    Int => "int"
    Void => "void"
    Char => "char"
    Struct => "struct"
    Union => "union"
    Typedef => "typedef"
    Const => "const"
    Restrict => "restrict"
    Extern => "extern"
    Static => "static"
    Volatile => "volatile"
    Signed => "signed"
    Unsigned => "unsigned"
    Short => "short"
    Long => "long"
    Float => "float"
    Double => "double"
    Bool => "bool"
    If => "if"
    Else => "else"
    While => "while"
    Return => "return"
    Sizeof => "sizeof"
    Inline => "inline"
    Register => "register"
    Auto => "auto"
    For => "for"
    Enum => "enum"
    Switch => "switch"
    Case => "case"
    Default => "default"
    Break => "break"
    Goto => "goto"
    Continue => "continue"
    Do => "do"
    Ellipsis => "..."
    Plus => "+"
    Minus => "-"
    PlusPlus => "++"
    MinusMinus => "--"
    Star => "*"
    Slash => "/"
    Percent => "%"
    Eq => "=="
    Ne => "!="
    Lt => "<"
    Le => "<="
    Gt => ">"
    Ge => ">="
    And => "&&"
    Or => "||"
    BitOr => "|"
    BitXor => "^"
    LShift => "<<"
    RShift => ">>"
    BitNot => "~"
    Not => "!"
    Assign => "="
    PlusEq => "+="
    MinusEq => "-="
    StarEq => "*="
    SlashEq => "/="
    PercentEq => "%="
    BitOrEq => "|="
    AmpersandEq => "&="
    BitXorEq => "^="
    LShiftEq => "<<="
    RShiftEq => ">>="
    Semicolon => ";"
    Comma => ","
    LParen => "("
    RParen => ")"
    LBrace => "{"
    RBrace => "}"
    LBracket => "["
    RBracket => "]"
    Dot => "."
    Arrow => "->"
    Colon => ":"
    Question => "?"
    Ampersand => "&"
  }
}

///|
pub struct Lexer {
  input : String
  mut pos : Int
}

///|
pub fn Lexer::new(input : String) -> Lexer {
  { input, pos: 0 }
}

///|
pub fn Lexer::next_token(self : Lexer) -> Token {
  self.skip_whitespace()
  if self.pos >= self.input.length() {
    return EOF
  }
  let ch = self.peek()
  match ch {
    '+' => {
      self.advance()
      if self.peek() == '+' {
        self.advance()
        PlusPlus
      } else if self.peek() == '=' {
        self.advance()
        PlusEq
      } else {
        Plus
      }
    }
    '-' => {
      self.advance()
      if self.peek() == '>' {
        self.advance()
        Arrow
      } else if self.peek() == '-' {
        self.advance()
        MinusMinus
      } else if self.peek() == '=' {
        self.advance()
        MinusEq
      } else {
        Minus
      }
    }
    '*' => {
      self.advance()
      if self.peek() == '=' {
        self.advance()
        StarEq
      } else {
        Star
      }
    }
    '/' => {
      self.advance()
      if self.peek() == '/' {
        // Line comment: skip until end of line
        while self.pos < self.input.length() && self.peek() != '\n' {
          self.pos += 1
        }
        self.next_token()
      } else if self.peek() == '*' {
        // Block comment: skip until */
        self.advance() // skip *
        while self.pos < self.input.length() {
          if self.peek() == '*' &&
            self.pos + 1 < self.input.length() &&
            self.input[self.pos + 1] == '/' {
            self.pos += 2
            break
          }
          self.pos += 1
        }
        self.next_token()
      } else if self.peek() == '=' {
        self.advance()
        SlashEq
      } else {
        Slash
      }
    }
    '%' => {
      self.advance()
      if self.peek() == '=' {
        self.advance()
        PercentEq
      } else {
        Percent
      }
    }
    ';' => {
      self.advance()
      Semicolon
    }
    ',' => {
      self.advance()
      Comma
    }
    '(' => {
      self.advance()
      LParen
    }
    ')' => {
      self.advance()
      RParen
    }
    '{' => {
      self.advance()
      LBrace
    }
    '}' => {
      self.advance()
      RBrace
    }
    '[' => {
      self.advance()
      LBracket
    }
    ']' => {
      self.advance()
      RBracket
    }
    '.' => {
      self.advance()
      if self.peek() == '.' {
        self.advance()
        if self.peek() == '.' {
          self.advance()
          Ellipsis
        } else {
          abort("Unexpected token: ..")
        }
      } else if is_digit(self.peek()) {
        // Float literal starting with .: .5, .5e10
        let fstart = self.pos - 1
        while is_digit(self.peek()) {
          self.advance()
        }
        if self.peek() == 'e' || self.peek() == 'E' {
          self.advance()
          if self.peek() == '+' || self.peek() == '-' {
            self.advance()
          }
          while is_digit(self.peek()) {
            self.advance()
          }
        }
        if self.peek() == 'f' ||
          self.peek() == 'F' ||
          self.peek() == 'l' ||
          self.peek() == 'L' {
          self.advance()
        }
        let fs = self.input[fstart:self.pos]
        let v = @strconv.parse_double(fs) catch { _ => 0.0 }
        FloatLiteral(v)
      } else {
        Dot
      }
    }
    ':' => {
      self.advance()
      Colon
    }
    '?' => {
      self.advance()
      Question
    }
    '&' => {
      self.advance()
      if self.peek() == '&' {
        self.advance()
        And
      } else if self.peek() == '=' {
        self.advance()
        AmpersandEq
      } else {
        Ampersand
      }
    }
    '|' => {
      self.advance()
      if self.peek() == '|' {
        self.advance()
        Or
      } else if self.peek() == '=' {
        self.advance()
        BitOrEq
      } else {
        BitOr
      }
    }
    '^' => {
      self.advance()
      if self.peek() == '=' {
        self.advance()
        BitXorEq
      } else {
        BitXor
      }
    }
    '~' => {
      self.advance()
      BitNot
    }
    '=' => {
      self.advance()
      if self.peek() == '=' {
        self.advance()
        Eq
      } else {
        Assign
      }
    }
    '!' => {
      self.advance()
      if self.peek() == '=' {
        self.advance()
        Ne
      } else {
        Not
      }
    }
    '<' => {
      self.advance()
      if self.peek() == '<' {
        self.advance()
        if self.peek() == '=' {
          self.advance()
          LShiftEq
        } else {
          LShift
        }
      } else if self.peek() == '=' {
        self.advance()
        Le
      } else {
        Lt
      }
    }
    '>' => {
      self.advance()
      if self.peek() == '>' {
        self.advance()
        if self.peek() == '=' {
          self.advance()
          RShiftEq
        } else {
          RShift
        }
      } else if self.peek() == '=' {
        self.advance()
        Ge
      } else {
        Gt
      }
    }
    '"' => {
      let mut result = self.read_string()
      // Concatenate adjacent string literals
      while true {
        self.skip_whitespace()
        // Skip preprocessor directives between adjacent strings
        while self.pos < self.input.length() && self.peek() == '#' {
          while self.pos < self.input.length() && self.peek() != '\n' {
            self.pos += 1
          }
          if self.pos < self.input.length() {
            self.pos += 1
          }
          self.skip_whitespace()
        }
        if self.pos < self.input.length() && self.peek() == '"' {
          let next = self.read_string()
          match (result, next) {
            (String(s1), String(s2)) => result = String(s1 + s2)
            _ => ()
          }
        } else {
          break
        }
      }
      result
    }
    '\'' => self.read_char()
    '#' => {
      // Skip preprocessor directive until end of line
      while self.pos < self.input.length() && self.peek() != '\n' {
        self.pos += 1
      }
      if self.pos < self.input.length() {
        self.pos += 1
      }
      self.next_token()
    }
    _ =>
      if is_digit(ch) {
        self.read_number()
      } else if is_alpha(ch) || ch == '_' {
        self.read_ident()
      } else {
        abort("Unexpected character: " + ch.to_string())
      }
  }
}

///|
fn Lexer::peek(self : Lexer) -> Char {
  if self.pos >= self.input.length() {
    '\u0000'
  } else {
    self.input.get_char(self.pos).unwrap_or('\u0000')
  }
}

///|
fn Lexer::advance(self : Lexer) -> Unit {
  self.pos += 1
}

///|
fn Lexer::skip_whitespace(self : Lexer) -> Unit {
  while self.pos < self.input.length() {
    let ch = self.peek()
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      self.advance()
    } else {
      break
    }
  }
}

///|
fn hex_float_pow2(exp : Int) -> Double {
  if exp > 1023 {
    return @double.infinity
  }
  if exp < -1074 {
    return 0.0
  }
  let mut result = 1.0
  let mut e = exp
  let mut base = 2.0
  if e < 0 {
    e = -e
    base = 0.5
  }
  while e > 0 {
    if e.land(1) == 1 {
      result = result * base
    }
    base = base * base
    e = e.lsr(1)
  }
  result
}

///|
fn Lexer::read_number(self : Lexer) -> Token {
  let start = self.pos
  // Check for hex prefix 0x or 0X
  if self.peek() == '0' && (self.peek_next() == 'x' || self.peek_next() == 'X') {
    self.advance() // skip '0'
    self.advance() // skip 'x'/'X'
    let hex_start = self.pos
    while is_hex_digit(self.peek()) {
      self.advance()
    }
    // Check for hex float literal: 0x1.fp10 or 0x1p10
    let is_hex_float = self.peek() == '.' ||
      self.peek() == 'p' ||
      self.peek() == 'P'
    if is_hex_float {
      // Parse hex float
      let mut int_part = 0.0
      let hex_int_str = self.input[hex_start:self.pos]
      for i = 0; i < hex_int_str.length(); i = i + 1 {
        let ch = hex_int_str[i]
        let digit = if ch >= '0' && ch <= '9' {
          ch.to_int() - '0'.to_int()
        } else if ch >= 'a' && ch <= 'f' {
          ch.to_int() - 'a'.to_int() + 10
        } else {
          ch.to_int() - 'A'.to_int() + 10
        }
        int_part = int_part * 16.0 + digit.to_double()
      }
      let mut frac_part = 0.0
      let mut frac_div = 1.0
      if self.peek() == '.' {
        self.advance()
        while is_hex_digit(self.peek()) {
          let ch = self.peek()
          let digit = if ch >= '0' && ch <= '9' {
            ch.to_int() - '0'.to_int()
          } else if ch >= 'a' && ch <= 'f' {
            ch.to_int() - 'a'.to_int() + 10
          } else {
            ch.to_int() - 'A'.to_int() + 10
          }
          frac_part = frac_part * 16.0 + digit.to_double()
          frac_div = frac_div * 16.0
          self.advance()
        }
      }
      let mut exp = 0
      if self.peek() == 'p' || self.peek() == 'P' {
        self.advance()
        let mut neg = false
        if self.peek() == '-' {
          neg = true
          self.advance()
        } else if self.peek() == '+' {
          self.advance()
        }
        while is_digit(self.peek()) {
          exp = exp * 10 + (self.peek().to_int() - '0'.to_int())
          self.advance()
        }
        if neg {
          exp = -exp
        }
      }
      let mut mantissa = int_part
      if frac_div > 1.0 {
        mantissa = mantissa + frac_part / frac_div
      }
      let v = mantissa * hex_float_pow2(exp)
      // Skip float suffix
      if self.peek() == 'f' ||
        self.peek() == 'F' ||
        self.peek() == 'l' ||
        self.peek() == 'L' {
        self.advance()
      }
      return FloatLiteral(v)
    }
    let s = self.input[hex_start:self.pos]
    let mut n = 0L
    for i = 0; i < s.length(); i = i + 1 {
      let ch = s[i]
      let digit = if ch >= '0' && ch <= '9' {
        ch.to_int() - '0'.to_int()
      } else if ch >= 'a' && ch <= 'f' {
        ch.to_int() - 'a'.to_int() + 10
      } else {
        ch.to_int() - 'A'.to_int() + 10
      }
      n = n * 16L + digit.to_int64()
    }
    // Skip integer suffixes for hex literals too
    if self.peek() == 'u' || self.peek() == 'U' {
      self.advance()
      if self.peek() == 'l' || self.peek() == 'L' {
        self.advance()
        if self.peek() == 'l' || self.peek() == 'L' {
          self.advance()
        }
      }
    } else if self.peek() == 'l' || self.peek() == 'L' {
      self.advance()
      if self.peek() == 'l' || self.peek() == 'L' {
        self.advance()
      }
      if self.peek() == 'u' || self.peek() == 'U' {
        self.advance()
      }
    }
    return Number(n)
  }
  while is_digit(self.peek()) {
    self.advance()
  }
  // Extract digits before suffix/float check
  let s = self.input[start:self.pos]

  // Check for float literal: 123.45, 123., 123e10
  if self.peek() == '.' || self.peek() == 'e' || self.peek() == 'E' {
    if self.peek() == '.' {
      self.advance()
      while is_digit(self.peek()) {
        self.advance()
      }
    }
    if self.peek() == 'e' || self.peek() == 'E' {
      self.advance()
      if self.peek() == '+' || self.peek() == '-' {
        self.advance()
      }
      while is_digit(self.peek()) {
        self.advance()
      }
    }
    if self.peek() == 'f' ||
      self.peek() == 'F' ||
      self.peek() == 'l' ||
      self.peek() == 'L' {
      self.advance()
    }
    let fs = self.input[start:self.pos]
    let v = @strconv.parse_double(fs) catch { _ => 0.0 }
    return FloatLiteral(v)
  }
  // Skip integer suffixes: u, U, l, L, ll, LL, ul, UL, lu, LU, ull, ULL, llu, LLU
  if self.peek() == 'u' || self.peek() == 'U' {
    self.advance()
    if self.peek() == 'l' || self.peek() == 'L' {
      self.advance()
      if self.peek() == 'l' || self.peek() == 'L' {
        self.advance()
      }
    }
  } else if self.peek() == 'l' || self.peek() == 'L' {
    self.advance()
    if self.peek() == 'l' || self.peek() == 'L' {
      self.advance()
    }
    if self.peek() == 'u' || self.peek() == 'U' {
      self.advance()
    }
  }
  let base = if s.length() > 1 && s[0] == '0' { 8L } else { 10L }
  let mut n = 0L
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i]
    if base == 8L && ch > '7' {
      abort("Invalid octal digit")
    }
    n = n * base + (ch.to_int() - '0'.to_int()).to_int64()
  }

  Number(n)
}

///|
fn Lexer::read_ident(self : Lexer) -> Token {
  let start = self.pos
  while is_alpha(self.peek()) || is_digit(self.peek()) || self.peek() == '_' {
    self.advance()
  }
  let s = self.input[start:self.pos]
  match s {
    "int" => Int
    "void" => Void
    "char" => Char
    "struct" => Struct
    "union" => Union
    "typedef" => Typedef
    "const" => Const
    "restrict" => Restrict
    "extern" => Extern
    "static" => Static
    "volatile" => Volatile
    "signed" => Signed
    "unsigned" => Unsigned
    "short" => Short
    "long" => Long
    "float" => Float
    "double" => Double
    "bool" => Bool
    "_Bool" => Bool
    "if" => If
    "else" => Else
    "while" => While
    "return" => Return
    "sizeof" => Sizeof
    "inline" => Inline
    "register" => Register
    "auto" => Auto
    "for" => For
    "enum" => Enum
    "switch" => Switch
    "case" => Case
    "default" => Default
    "break" => Break
    "goto" => Goto
    "continue" => Continue
    "do" => Do
    _ => Ident(s.to_owned())
  }
}

///|
fn hex_digit_value(ch : Char) -> Int? {
  if ch >= '0' && ch <= '9' {
    Some(ch.to_int() - '0'.to_int())
  } else if ch >= 'a' && ch <= 'f' {
    Some(ch.to_int() - 'a'.to_int() + 10)
  } else if ch >= 'A' && ch <= 'F' {
    Some(ch.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn Lexer::read_escape_value(self : Lexer) -> Int64 {
  let next = self.peek()
  if next >= '0' && next <= '7' {
    let mut value = 0
    let mut count = 0
    while count < 3 && self.peek() >= '0' && self.peek() <= '7' {
      value = value * 8 + (self.peek().to_int() - '0'.to_int())
      self.advance()
      count += 1
    }
    return value.to_int64()
  }
  match next {
    'n' => {
      self.advance()
      '\n'.to_int().to_int64()
    }
    't' => {
      self.advance()
      '\t'.to_int().to_int64()
    }
    'r' => {
      self.advance()
      '\r'.to_int().to_int64()
    }
    'a' => {
      self.advance()
      7L
    }
    'b' => {
      self.advance()
      8L
    }
    'f' => {
      self.advance()
      12L
    }
    'v' => {
      self.advance()
      11L
    }
    '\\' => {
      self.advance()
      '\\'.to_int().to_int64()
    }
    '\'' => {
      self.advance()
      '\''.to_int().to_int64()
    }
    '"' => {
      self.advance()
      '"'.to_int().to_int64()
    }
    'x' => {
      self.advance()
      let mut value = 0
      while true {
        match hex_digit_value(self.peek()) {
          Some(digit) => {
            value = value * 16 + digit
            self.advance()
          }
          None => break
        }
      }
      value.to_int64()
    }
    _ => {
      self.advance()
      next.to_int().to_int64()
    }
  }
}

///|
fn Lexer::read_string(self : Lexer) -> Token {
  self.advance() // skip opening "
  let buf = StringBuilder::new()
  while self.peek() != '"' && self.peek() != '\u0000' {
    let ch = self.peek()
    if ch == '\\' {
      self.advance()
      let value = self.read_escape_value()
      buf.write_char(value.to_int().unsafe_to_char())
    } else {
      buf.write_char(ch)
      self.advance()
    }
  }
  if self.peek() != '"' {
    abort("Unterminated string literal")
  }
  self.advance() // skip closing "
  String(buf.to_string())
}

///|
fn Lexer::read_char(self : Lexer) -> Token {
  self.advance() // skip opening '
  let ch = self.peek()
  let mut value : Int64 = 0
  if ch == '\\' {
    self.advance()
    value = self.read_escape_value()
  } else {
    value = ch.to_int().to_int64()
    self.advance()
  }
  if self.peek() != '\'' {
    abort("Unterminated character literal")
  }
  self.advance() // skip closing '
  Number(value)
}

///|
fn Lexer::peek_next(self : Lexer) -> Char {
  if self.pos + 1 >= self.input.length() {
    '\u0000'
  } else {
    self.input.get_char(self.pos + 1).unwrap_or('\u0000')
  }
}

///|
fn is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn is_hex_digit(ch : Char) -> Bool {
  (ch >= '0' && ch <= '9') ||
  (ch >= 'a' && ch <= 'f') ||
  (ch >= 'A' && ch <= 'F')
}

///|
fn is_alpha(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
}
