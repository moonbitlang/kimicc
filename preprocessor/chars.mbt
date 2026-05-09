///|
fn pp_is_alpha(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
}

///|
fn pp_is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn pp_is_ident_start(ch : Char) -> Bool {
  pp_is_alpha(ch) || ch == '_'
}

///|
fn pp_is_ident_continue(ch : Char) -> Bool {
  pp_is_ident_start(ch) || pp_is_digit(ch)
}

///|
fn pp_starts_with_at(input : String, pos : Int, needle : String) -> Bool {
  if pos + needle.length() > input.length() {
    return false
  }
  input[pos:pos + needle.length()] == needle
}

///|
fn pp_dirname(path : String) -> String {
  let mut last = -1
  for i = 0; i < path.length(); i = i + 1 {
    if path[i] == '/' {
      last = i
    }
  }
  if last < 0 {
    "."
  } else if last == 0 {
    "/"
  } else {
    path[0:last].to_owned()
  }
}

///|
fn pp_is_absolute_path(path : String) -> Bool {
  path.length() > 0 && path[0] == '/'
}

///|
fn pp_join_path(dir : String, name : String) -> String {
  if pp_is_absolute_path(name) || dir == "" || dir == "." {
    if pp_is_absolute_path(name) {
      name
    } else {
      "./" + name
    }
  } else if dir.has_suffix("/") {
    dir + name
  } else {
    dir + "/" + name
  }
}

///|
fn pp_unquote_string_literal(text : String) -> String {
  let mut start = 0
  while start < text.length() && text[start] != '"' {
    start += 1
  }
  if start >= text.length() {
    return text
  }
  let mut end = text.length() - 1
  while end > start && text[end] != '"' {
    end -= 1
  }
  if end <= start {
    ""
  } else {
    text[start + 1:end].to_owned()
  }
}

///|
fn pp_quote_string(text : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('"')
  for i = 0; i < text.length(); i = i + 1 {
    let ch = text[i].unsafe_to_char()
    if ch == '"' || ch == '\\' {
      buf.write_char('\\')
      buf.write_char(ch)
    } else if ch == '\n' {
      buf.write_string("\\n")
    } else {
      buf.write_char(ch)
    }
  }
  buf.write_char('"')
  buf.to_string()
}
