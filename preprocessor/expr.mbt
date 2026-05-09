///|
priv struct IfExprParser {
  tokens : Array[PpToken]
  mut pos : Int
}

///|
fn pp_parse_int_literal(text : String) -> Int64 {
  let mut i = 0
  let mut base = 10L
  if text.length() > 2 && text[0] == '0' && (text[1] == 'x' || text[1] == 'X') {
    i = 2
    base = 16L
  } else if text.length() > 1 && text[0] == '0' {
    i = 1
    base = 8L
  }
  let mut value = 0L
  while i < text.length() {
    let ch = text[i]
    let digit = if ch >= '0' && ch <= '9' {
      ch.to_int() - '0'.to_int()
    } else if ch >= 'a' && ch <= 'f' {
      ch.to_int() - 'a'.to_int() + 10
    } else if ch >= 'A' && ch <= 'F' {
      ch.to_int() - 'A'.to_int() + 10
    } else {
      break
    }
    if digit >= base.to_int() {
      break
    }
    value = value * base + digit.to_int64()
    i += 1
  }
  value
}

///|
fn IfExprParser::peek(self : IfExprParser) -> PpToken? {
  if self.pos < self.tokens.length() {
    Some(self.tokens[self.pos])
  } else {
    None
  }
}

///|
fn IfExprParser::match_punct(self : IfExprParser, text : String) -> Bool {
  match self.peek() {
    Some(tok) =>
      if tok.is_punct(text) {
        self.pos += 1
        true
      } else {
        false
      }
    None => false
  }
}

///|
fn IfExprParser::parse_primary(self : IfExprParser) -> Int64 {
  match self.peek() {
    Some(tok) =>
      if tok.is_punct("(") {
        self.pos += 1
        let value = self.parse_conditional()
        ignore(self.match_punct(")"))
        value
      } else if tok.kind == PpNumber {
        self.pos += 1
        pp_parse_int_literal(tok.text)
      } else {
        self.pos += 1
        0L
      }
    None => 0L
  }
}

///|
fn IfExprParser::parse_unary(self : IfExprParser) -> Int64 {
  if self.match_punct("+") {
    self.parse_unary()
  } else if self.match_punct("-") {
    -self.parse_unary()
  } else if self.match_punct("!") {
    if self.parse_unary() == 0L { 1L } else { 0L }
  } else if self.match_punct("~") {
    self.parse_unary().lnot()
  } else {
    self.parse_primary()
  }
}

///|
fn IfExprParser::parse_mul(self : IfExprParser) -> Int64 {
  let mut value = self.parse_unary()
  while true {
    if self.match_punct("*") {
      value = value * self.parse_unary()
    } else if self.match_punct("/") {
      let rhs = self.parse_unary()
      value = if rhs == 0L { 0L } else { value / rhs }
    } else if self.match_punct("%") {
      let rhs = self.parse_unary()
      value = if rhs == 0L { 0L } else { value % rhs }
    } else {
      break
    }
  }
  value
}

///|
fn IfExprParser::parse_add(self : IfExprParser) -> Int64 {
  let mut value = self.parse_mul()
  while true {
    if self.match_punct("+") {
      value = value + self.parse_mul()
    } else if self.match_punct("-") {
      value = value - self.parse_mul()
    } else {
      break
    }
  }
  value
}

///|
fn IfExprParser::parse_shift(self : IfExprParser) -> Int64 {
  let mut value = self.parse_add()
  while true {
    if self.match_punct("<<") {
      value = value << self.parse_add().to_int()
    } else if self.match_punct(">>") {
      value = value >> self.parse_add().to_int()
    } else {
      break
    }
  }
  value
}

///|
fn IfExprParser::parse_relational(self : IfExprParser) -> Int64 {
  let mut value = self.parse_shift()
  while true {
    if self.match_punct("<") {
      value = if value < self.parse_shift() { 1L } else { 0L }
    } else if self.match_punct("<=") {
      value = if value <= self.parse_shift() { 1L } else { 0L }
    } else if self.match_punct(">") {
      value = if value > self.parse_shift() { 1L } else { 0L }
    } else if self.match_punct(">=") {
      value = if value >= self.parse_shift() { 1L } else { 0L }
    } else {
      break
    }
  }
  value
}

///|
fn IfExprParser::parse_equality(self : IfExprParser) -> Int64 {
  let mut value = self.parse_relational()
  while true {
    if self.match_punct("==") {
      value = if value == self.parse_relational() { 1L } else { 0L }
    } else if self.match_punct("!=") {
      value = if value != self.parse_relational() { 1L } else { 0L }
    } else {
      break
    }
  }
  value
}

///|
fn IfExprParser::parse_bit_and(self : IfExprParser) -> Int64 {
  let mut value = self.parse_equality()
  while self.match_punct("&") {
    value = value & self.parse_equality()
  }
  value
}

///|
fn IfExprParser::parse_bit_xor(self : IfExprParser) -> Int64 {
  let mut value = self.parse_bit_and()
  while self.match_punct("^") {
    value = value ^ self.parse_bit_and()
  }
  value
}

///|
fn IfExprParser::parse_bit_or(self : IfExprParser) -> Int64 {
  let mut value = self.parse_bit_xor()
  while self.match_punct("|") {
    value = value | self.parse_bit_xor()
  }
  value
}

///|
fn IfExprParser::parse_logical_and(self : IfExprParser) -> Int64 {
  let mut value = self.parse_bit_or()
  while self.match_punct("&&") {
    let rhs = self.parse_bit_or()
    value = if value != 0L && rhs != 0L { 1L } else { 0L }
  }
  value
}

///|
fn IfExprParser::parse_logical_or(self : IfExprParser) -> Int64 {
  let mut value = self.parse_logical_and()
  while self.match_punct("||") {
    let rhs = self.parse_logical_and()
    value = if value != 0L || rhs != 0L { 1L } else { 0L }
  }
  value
}

///|
fn IfExprParser::parse_conditional(self : IfExprParser) -> Int64 {
  let cond = self.parse_logical_or()
  if self.match_punct("?") {
    let then_value = self.parse_conditional()
    ignore(self.match_punct(":"))
    let else_value = self.parse_conditional()
    if cond != 0L { then_value } else { else_value }
  } else {
    cond
  }
}

///|
fn pp_eval_if_expr(tokens : Array[PpToken]) -> Int64 {
  let parser = { tokens, pos: 0 }
  parser.parse_conditional()
}
