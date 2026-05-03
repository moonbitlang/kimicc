///|
pub(all) enum Token {
  EOF
  Ident(String)
  Number(Int)
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
  If
  Else
  While
  Return
  Sizeof
  Inline
  Ellipsis
  Plus
  Minus
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
  Assign
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
  Ampersand
} derive(Eq)

///|
impl Show for Token with to_string(self) {
  match self {
    EOF => "EOF"
    Ident(s) => "Ident(" + s + ")"
    Number(n) => "Number(" + n.to_string() + ")"
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
    If => "if"
    Else => "else"
    While => "while"
    Return => "return"
    Sizeof => "sizeof"
    Inline => "inline"
    Ellipsis => "..."
    Plus => "+"
    Minus => "-"
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
    Assign => "="
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
      Plus
    }
    '-' => {
      self.advance()
      if self.peek() == '>' {
        self.advance()
        Arrow
      } else {
        Minus
      }
    }
    '*' => {
      self.advance()
      Star
    }
    '/' => {
      self.advance()
      Slash
    }
    '%' => {
      self.advance()
      Percent
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
      } else {
        Dot
      }
    }
    '&' => {
      self.advance()
      if self.peek() == '&' {
        self.advance()
        And
      } else {
        Ampersand
      }
    }
    '|' => {
      self.advance()
      if self.peek() == '|' {
        self.advance()
        Or
      } else {
        abort("Unexpected character: |")
      }
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
        abort("Unexpected character: !")
      }
    }
    '<' => {
      self.advance()
      if self.peek() == '=' {
        self.advance()
        Le
      } else {
        Lt
      }
    }
    '>' => {
      self.advance()
      if self.peek() == '=' {
        self.advance()
        Ge
      } else {
        Gt
      }
    }
    '"' => {
      self.read_string()
    }
    '\'' => {
      self.read_char()
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
fn Lexer::read_number(self : Lexer) -> Token {
  let start = self.pos
  while is_digit(self.peek()) {
    self.advance()
  }
  let s = self.input[start:self.pos]
  let mut n = 0
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i]
    n = n * 10 + (ch.to_int() - '0'.to_int())
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
    "if" => If
    "else" => Else
    "while" => While
    "return" => Return
    "sizeof" => Sizeof
    "inline" => Inline
    _ => Ident(s.to_owned())
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
      let next = self.peek()
      match next {
        'n' => { buf.write_char('\n'); self.advance() }
        't' => { buf.write_char('\t'); self.advance() }
        '\\' => { buf.write_char('\\'); self.advance() }
        '"' => { buf.write_char('"'); self.advance() }
        '0' => { buf.write_char('\u0000'); self.advance() }
        _ => { buf.write_char(next); self.advance() }
      }
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
  let mut value = 0
  if ch == '\\' {
    self.advance()
    let next = self.peek()
    match next {
      'n' => { value = '\n'.to_int(); self.advance() }
      't' => { value = '\t'.to_int(); self.advance() }
      '\\' => { value = '\\'.to_int(); self.advance() }
      '\'' => { value = '\''.to_int(); self.advance() }
      '0' => { value = 0; self.advance() }
      _ => { value = next.to_int(); self.advance() }
    }
  } else {
    value = ch.to_int()
    self.advance()
  }
  if self.peek() != '\'' {
    abort("Unterminated character literal")
  }
  self.advance() // skip closing '
  Number(value)
}

///|
fn is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn is_alpha(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
}
