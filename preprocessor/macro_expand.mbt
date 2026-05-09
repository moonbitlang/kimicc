///|
fn pp_clone_tokens(tokens : Array[PpToken]) -> Array[PpToken] {
  let result : Array[PpToken] = []
  for token in tokens {
    result.push(token)
  }
  result
}

///|
fn pp_macro_param_index(macro_ : Macro, name : String) -> Int {
  for i = 0; i < macro_.params.length(); i = i + 1 {
    if macro_.params[i] == name {
      return i
    }
  }
  -1
}

///|
fn pp_macro_param_is_variadic(macro_ : Macro, index : Int) -> Bool {
  macro_.variadic && index == macro_.params.length() - 1
}

///|
fn pp_stringize_tokens(tokens : Array[PpToken]) -> PpToken {
  let buf = StringBuilder::new()
  let mut first = true
  for token in tokens {
    if token.is_whitespace() || token.is_newline() {
      continue
    }
    if first {
      first = false
    } else {
      buf.write_char(' ')
    }
    buf.write_string(token.text)
  }
  pp_token(PpString, pp_quote_string(buf.to_string()))
}

///|
fn pp_paste_token(left : PpToken, right : PpToken) -> PpToken {
  let text = left.text + right.text
  let toks = pp_without_whitespace(pp_tokenize(text))
  if toks.length() == 1 {
    toks[0]
  } else {
    pp_token(PpOther, text)
  }
}

///|
fn pp_skip_parenthesized(tokens : Array[PpToken], lparen : Int) -> Int {
  let mut depth = 0
  let mut i = lparen
  while i < tokens.length() {
    if tokens[i].is_punct("(") {
      depth += 1
    } else if tokens[i].is_punct(")") {
      depth -= 1
      if depth == 0 {
        return i + 1
      }
    }
    i += 1
  }
  tokens.length()
}

///|
fn Preprocessor::disabled_with(
  _self : Preprocessor,
  disabled : Map[String, Bool],
  name : String,
) -> Map[String, Bool] {
  let copy = disabled.copy()
  copy[name] = true
  copy
}

///|
fn Preprocessor::parse_macro_invocation(
  self : Preprocessor,
  tokens : Array[PpToken],
  lparen : Int,
  name : String,
) -> (Array[Array[PpToken]], Int)? {
  if lparen >= tokens.length() || !tokens[lparen].is_punct("(") {
    return None
  }
  let args : Array[Array[PpToken]] = []
  let mut current : Array[PpToken] = []
  let mut depth = 0
  let mut i = lparen + 1
  while i < tokens.length() {
    let tok = tokens[i]
    if tok.is_punct("(") {
      depth += 1
      current.push(tok)
    } else if tok.is_punct(")") {
      if depth == 0 {
        if current.length() > 0 || args.length() > 0 {
          args.push(current)
        }
        return Some((args, i + 1))
      }
      depth -= 1
      current.push(tok)
    } else if tok.is_punct(",") && depth == 0 {
      args.push(current)
      current = []
    } else {
      current.push(tok)
    }
    i += 1
  }
  self.set_error("unterminated macro invocation for " + name)
  None
}

///|
fn Preprocessor::macro_argument(
  _self : Preprocessor,
  macro_ : Macro,
  args : Array[Array[PpToken]],
  index : Int,
) -> Array[PpToken] {
  if pp_macro_param_is_variadic(macro_, index) {
    let result : Array[PpToken] = []
    for i = index; i < args.length(); i = i + 1 {
      if i > index {
        result.push(pp_token(PpPunct, ","))
      }
      for tok in args[i] {
        result.push(tok)
      }
    }
    result
  } else if index >= 0 && index < args.length() {
    args[index]
  } else {
    []
  }
}

///|
fn Preprocessor::expanded_macro_argument(
  self : Preprocessor,
  macro_ : Macro,
  args : Array[Array[PpToken]],
  index : Int,
  disabled : Map[String, Bool],
  file : String,
  line : Int,
  depth : Int,
) -> Array[PpToken] {
  self.expand_tokens(
    self.macro_argument(macro_, args, index),
    disabled,
    file,
    line,
    depth + 1,
  )
}

///|
fn Preprocessor::substitute_macro(
  self : Preprocessor,
  macro_ : Macro,
  args : Array[Array[PpToken]],
  disabled : Map[String, Bool],
  file : String,
  line : Int,
  depth : Int,
) -> Array[PpToken] {
  let result : Array[PpToken] = []
  let replacement = macro_.replacement
  let mut i = 0
  while i < replacement.length() {
    let tok = replacement[i]
    if tok.is_punct("#") && i + 1 < replacement.length() {
      let next = replacement[i + 1]
      if next.kind == PpIdent {
        let param_index = pp_macro_param_index(macro_, next.text)
        if param_index >= 0 {
          result.push(
            pp_stringize_tokens(self.macro_argument(macro_, args, param_index)),
          )
          i += 2
          continue
        }
      }
    }
    if tok.is_punct("##") {
      if result.length() == 0 || i + 1 >= replacement.length() {
        i += 1
        continue
      }
      let left = result.remove(result.length() - 1)
      let next = replacement[i + 1]
      let right_tokens = if next.kind == PpIdent {
        let param_index = pp_macro_param_index(macro_, next.text)
        if param_index >= 0 {
          self.macro_argument(macro_, args, param_index)
        } else {
          [next]
        }
      } else {
        [next]
      }
      if right_tokens.length() == 0 && next.kind == PpIdent {
        let param_index = pp_macro_param_index(macro_, next.text)
        if pp_macro_param_is_variadic(macro_, param_index) && left.is_punct(",") {
          i += 2
          continue
        }
        result.push(left)
      } else if right_tokens.length() == 0 {
        result.push(left)
      } else {
        let pasted = pp_paste_token(left, right_tokens[0])
        result.push(pasted)
        for j = 1; j < right_tokens.length(); j = j + 1 {
          result.push(right_tokens[j])
        }
      }
      i += 2
      continue
    }
    if tok.kind == PpIdent {
      let param_index = pp_macro_param_index(macro_, tok.text)
      if param_index >= 0 {
        let arg = self.expanded_macro_argument(
          macro_, args, param_index, disabled, file, line, depth,
        )
        for arg_tok in arg {
          result.push(arg_tok)
        }
        i += 1
        continue
      }
    }
    result.push(tok)
    i += 1
  }
  result
}

///|
fn Preprocessor::expand_tokens(
  self : Preprocessor,
  tokens : Array[PpToken],
  disabled : Map[String, Bool],
  file : String,
  line : Int,
  depth : Int,
) -> Array[PpToken] {
  if depth > 200 || self.error is Some(_) {
    return pp_clone_tokens(tokens)
  }
  let result : Array[PpToken] = []
  let clean = pp_without_whitespace(tokens)
  let mut i = 0
  while i < clean.length() {
    let tok = clean[i]
    if tok.kind == PpIdent {
      if tok.text == "__LINE__" {
        result.push(pp_token(PpNumber, line.to_string()))
        i += 1
        continue
      }
      if tok.text == "__FILE__" {
        result.push(pp_token(PpString, pp_quote_string(file)))
        i += 1
        continue
      }
      if tok.text == "_Pragma" &&
        i + 1 < clean.length() &&
        clean[i + 1].is_punct("(") {
        i = pp_skip_parenthesized(clean, i + 1)
        continue
      }
      match self.macros.get(tok.text) {
        Some(macro_) =>
          if !disabled.contains(tok.text) {
            if macro_.function_like {
              if i + 1 < clean.length() && clean[i + 1].is_punct("(") {
                match self.parse_macro_invocation(clean, i + 1, tok.text) {
                  Some((args, end_index)) => {
                    let disabled_next = self.disabled_with(disabled, tok.text)
                    let substituted = self.substitute_macro(
                      macro_, args, disabled, file, line, depth,
                    )
                    let expanded = self.expand_tokens(
                      substituted,
                      disabled_next,
                      file,
                      line,
                      depth + 1,
                    )
                    for out in expanded {
                      result.push(out)
                    }
                    i = end_index
                    continue
                  }
                  None => ()
                }
              }
            } else {
              let disabled_next = self.disabled_with(disabled, tok.text)
              let expanded = self.expand_tokens(
                macro_.replacement,
                disabled_next,
                file,
                line,
                depth + 1,
              )
              for out in expanded {
                result.push(out)
              }
              i += 1
              continue
            }
          }
        None => ()
      }
    }
    result.push(tok)
    i += 1
  }
  result
}
