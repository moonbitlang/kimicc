///|
fn pp_normalize_source(input : String) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < input.length() {
    if input[i] == '\\' && i + 1 < input.length() && input[i + 1] == '\n' {
      i += 2
    } else if input[i] == '"' || input[i] == '\'' {
      let quote = input[i]
      buf.write_char(input[i].unsafe_to_char())
      i += 1
      while i < input.length() {
        let ch = input[i]
        buf.write_char(ch.unsafe_to_char())
        i += 1
        if ch == '\\' && i < input.length() {
          buf.write_char(input[i].unsafe_to_char())
          i += 1
        } else if ch == quote {
          break
        }
      }
    } else if i + 1 < input.length() && input[i] == '/' && input[i + 1] == '/' {
      buf.write_char(' ')
      i += 2
      while i < input.length() && input[i] != '\n' {
        i += 1
      }
    } else if i + 1 < input.length() && input[i] == '/' && input[i + 1] == '*' {
      buf.write_char(' ')
      i += 2
      while i + 1 < input.length() {
        if input[i] == '*' && input[i + 1] == '/' {
          i += 2
          break
        }
        if input[i] == '\n' {
          buf.write_char('\n')
        }
        i += 1
      }
    } else {
      buf.write_char(input[i].unsafe_to_char())
      i += 1
    }
  }
  buf.to_string()
}

///|
fn pp_read_quoted(input : String, start : Int, quote : Char) -> Int {
  let mut i = start + 1
  while i < input.length() {
    let ch = input[i].unsafe_to_char()
    i += 1
    if ch == '\\' && i < input.length() {
      i += 1
    } else if ch == quote {
      break
    }
  }
  i
}

///|
fn pp_punct_at(input : String, pos : Int) -> String {
  if pp_starts_with_at(input, pos, "<<=") {
    return "<<="
  }
  if pp_starts_with_at(input, pos, ">>=") {
    return ">>="
  }
  if pp_starts_with_at(input, pos, "...") {
    return "..."
  }
  if pp_starts_with_at(input, pos, "##") {
    return "##"
  }
  if pp_starts_with_at(input, pos, "->") {
    return "->"
  }
  if pp_starts_with_at(input, pos, "++") {
    return "++"
  }
  if pp_starts_with_at(input, pos, "--") {
    return "--"
  }
  if pp_starts_with_at(input, pos, "&&") {
    return "&&"
  }
  if pp_starts_with_at(input, pos, "||") {
    return "||"
  }
  if pp_starts_with_at(input, pos, "==") {
    return "=="
  }
  if pp_starts_with_at(input, pos, "!=") {
    return "!="
  }
  if pp_starts_with_at(input, pos, "<=") {
    return "<="
  }
  if pp_starts_with_at(input, pos, ">=") {
    return ">="
  }
  if pp_starts_with_at(input, pos, "<<") {
    return "<<"
  }
  if pp_starts_with_at(input, pos, ">>") {
    return ">>"
  }
  if pp_starts_with_at(input, pos, "+=") {
    return "+="
  }
  if pp_starts_with_at(input, pos, "-=") {
    return "-="
  }
  if pp_starts_with_at(input, pos, "*=") {
    return "*="
  }
  if pp_starts_with_at(input, pos, "/=") {
    return "/="
  }
  if pp_starts_with_at(input, pos, "%=") {
    return "%="
  }
  if pp_starts_with_at(input, pos, "&=") {
    return "&="
  }
  if pp_starts_with_at(input, pos, "|=") {
    return "|="
  }
  if pp_starts_with_at(input, pos, "^=") {
    return "^="
  }
  input[pos:pos + 1].to_owned()
}

///|
fn pp_tokenize(input : String) -> Array[PpToken] {
  let source = pp_normalize_source(input)
  let tokens : Array[PpToken] = []
  let mut i = 0
  while i < source.length() {
    let ch = source[i]
    if ch == '\n' {
      tokens.push(pp_token(PpNewline, "\n"))
      i += 1
    } else if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\u000c' {
      let start = i
      while i < source.length() {
        let c = source[i]
        if c == ' ' || c == '\t' || c == '\r' || c == '\u000c' {
          i += 1
        } else {
          break
        }
      }
      tokens.push(pp_token(PpWhitespace, source[start:i].to_owned()))
    } else if ch == 'u' &&
      i + 2 < source.length() &&
      source[i + 1] == '8' &&
      (source[i + 2] == '"' || source[i + 2] == '\'') {
      let end = pp_read_quoted(source, i + 2, source[i + 2].unsafe_to_char())
      tokens.push(
        pp_token(
          if source[i + 2] == '"' {
            PpString
          } else {
            PpChar
          },
          source[i:end].to_owned(),
        ),
      )
      i = end
    } else if (ch == 'L' || ch == 'u' || ch == 'U') &&
      i + 1 < source.length() &&
      (source[i + 1] == '"' || source[i + 1] == '\'') {
      let end = pp_read_quoted(source, i + 1, source[i + 1].unsafe_to_char())
      tokens.push(
        pp_token(
          if source[i + 1] == '"' {
            PpString
          } else {
            PpChar
          },
          source[i:end].to_owned(),
        ),
      )
      i = end
    } else if pp_is_ident_start(ch.unsafe_to_char()) {
      let start = i
      i += 1
      while i < source.length() &&
            pp_is_ident_continue(source[i].unsafe_to_char()) {
        i += 1
      }
      tokens.push(pp_token(PpIdent, source[start:i].to_owned()))
    } else if pp_is_digit(ch.unsafe_to_char()) ||
      (
        ch == '.' &&
        i + 1 < source.length() &&
        pp_is_digit(source[i + 1].unsafe_to_char())
      ) {
      let start = i
      i += 1
      while i < source.length() {
        let c = source[i]
        if pp_is_ident_continue(c.unsafe_to_char()) ||
          c == '.' ||
          c == '+' ||
          c == '-' {
          i += 1
        } else {
          break
        }
      }
      tokens.push(pp_token(PpNumber, source[start:i].to_owned()))
    } else if ch == '"' {
      let end = pp_read_quoted(source, i, '"')
      tokens.push(pp_token(PpString, source[i:end].to_owned()))
      i = end
    } else if ch == '\'' {
      let end = pp_read_quoted(source, i, '\'')
      tokens.push(pp_token(PpChar, source[i:end].to_owned()))
      i = end
    } else {
      let punct = pp_punct_at(source, i)
      tokens.push(pp_token(PpPunct, punct))
      i += punct.length()
    }
  }
  tokens
}

///|
fn pp_without_whitespace(tokens : Array[PpToken]) -> Array[PpToken] {
  let result : Array[PpToken] = []
  for token in tokens {
    if !token.is_whitespace() && !token.is_newline() {
      result.push(token)
    }
  }
  result
}

///|
fn pp_first_non_space(tokens : Array[PpToken]) -> Int {
  let mut i = 0
  while i < tokens.length() && tokens[i].is_whitespace() {
    i += 1
  }
  i
}

///|
fn pp_tokens_need_space(left : PpToken, right : PpToken) -> Bool {
  let left_word = left.kind == PpIdent ||
    left.kind == PpNumber ||
    left.kind == PpString ||
    left.kind == PpChar
  let right_word = right.kind == PpIdent ||
    right.kind == PpNumber ||
    right.kind == PpString ||
    right.kind == PpChar
  if left_word && right_word {
    return true
  }
  if left.text == "+" && right.text == "+" {
    return true
  }
  if left.text == "-" && right.text == "-" {
    return true
  }
  if left.kind == PpNumber && right.text == "..." {
    return true
  }
  if left.text == "..." && right.kind == PpNumber {
    return true
  }
  false
}

///|
fn pp_tokens_to_source(tokens : Array[PpToken]) -> String {
  let buf = StringBuilder::new()
  let mut previous : PpToken? = None
  for token in tokens {
    if token.is_whitespace() || token.is_newline() {
      continue
    }
    match previous {
      Some(prev) => if pp_tokens_need_space(prev, token) { buf.write_char(' ') }
      None => ()
    }
    buf.write_string(token.text)
    previous = Some(token)
  }
  buf.to_string()
}
