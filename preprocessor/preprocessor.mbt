///|
fn Preprocessor::set_error(self : Preprocessor, message : String) -> Unit {
  if self.error is None {
    self.error = Some(Message(message))
  }
}

///|
fn Preprocessor::is_active(_self : Preprocessor, stack : Array[ConditionalFrame]) -> Bool {
  match stack.last() {
    Some(frame) => frame.branch_active
    None => true
  }
}

///|
fn Preprocessor::seed_macro(self : Preprocessor, name : String, replacement : String) -> Unit {
  self.macros[name] = {
    function_like: false,
    params: [],
    replacement: pp_without_whitespace(pp_tokenize(replacement)),
  }
}

///|
fn Preprocessor::new(options : PreprocessOptions) -> Preprocessor {
  let pp = { options, macros: {}, include_stack: [], error: None }
  pp.seed_macro("__STDC__", "1")
  pp.seed_macro("__STDC_VERSION__", "201112L")
  pp.seed_macro("__STDC_HOSTED__", "1")
  pp.seed_macro("__APPLE__", "1")
  pp.seed_macro("__MACH__", "1")
  pp.seed_macro("__aarch64__", "1")
  pp.seed_macro("__arm64__", "1")
  pp.seed_macro("__LP64__", "1")
  pp.seed_macro("__SIZEOF_POINTER__", "8")
  pp.seed_macro("__DATE__", pp_quote_string("May  9 2026"))
  pp.seed_macro("__TIME__", pp_quote_string("00:00:00"))
  for pair in options.defines {
    let replacement = if pair.1 == "" { "1" } else { pair.1 }
    pp.seed_macro(pair.0, replacement)
  }
  for name in options.undefines {
    pp.macros.remove(name)
  }
  pp
}

///|
fn pp_line_after(tokens : Array[PpToken], start : Int) -> Array[PpToken] {
  let result : Array[PpToken] = []
  for i = start; i < tokens.length(); i = i + 1 {
    result.push(tokens[i])
  }
  result
}

///|
fn Preprocessor::define_macro(self : Preprocessor, tokens : Array[PpToken]) -> Unit {
  let start = pp_first_non_space(tokens)
  if start >= tokens.length() || tokens[start].kind != PpIdent {
    self.set_error("expected macro name after #define")
    return
  }
  let name = tokens[start].text
  let mut function_like = false
  let params : Array[String] = []
  let mut replacement_start = start + 1
  if replacement_start < tokens.length() && tokens[replacement_start].is_punct("(") {
    function_like = true
    let mut i = replacement_start + 1
    while i < tokens.length() {
      let tok = tokens[i]
      if tok.is_punct(")") {
        replacement_start = i + 1
        break
      } else if tok.is_punct(",") {
        i += 1
      } else if tok.is_punct("...") {
        params.push("__VA_ARGS__")
        i += 1
      } else if tok.kind == PpIdent {
        if i + 1 < tokens.length() && tokens[i + 1].is_punct("...") {
          params.push(tok.text)
          i += 2
        } else {
          params.push(tok.text)
          i += 1
        }
      } else if tok.is_whitespace() {
        i += 1
      } else {
        self.set_error("invalid function-like macro parameter list for " + name)
        return
      }
    }
  }
  let replacement = pp_without_whitespace(pp_line_after(tokens, replacement_start))
  self.macros[name] = {
    function_like,
    params,
    replacement,
  }
}

///|
fn Preprocessor::replace_defined_operators(self : Preprocessor, tokens : Array[PpToken]) -> Array[PpToken] {
  let clean = pp_without_whitespace(tokens)
  let result : Array[PpToken] = []
  let mut i = 0
  while i < clean.length() {
    let tok = clean[i]
    if tok.is_ident("defined") {
      if i + 1 < clean.length() && clean[i + 1].is_punct("(") {
        if i + 2 < clean.length() && clean[i + 2].kind == PpIdent {
          let name = clean[i + 2].text
          result.push(pp_token(PpNumber, if self.macros.contains(name) { "1" } else { "0" }))
          i += 3
          if i < clean.length() && clean[i].is_punct(")") {
            i += 1
          }
        } else {
          result.push(pp_token(PpNumber, "0"))
          i += 2
        }
      } else if i + 1 < clean.length() && clean[i + 1].kind == PpIdent {
        let name = clean[i + 1].text
        result.push(pp_token(PpNumber, if self.macros.contains(name) { "1" } else { "0" }))
        i += 2
      } else {
        result.push(pp_token(PpNumber, "0"))
        i += 1
      }
    } else {
      result.push(tok)
      i += 1
    }
  }
  result
}

///|
fn Preprocessor::eval_if(self : Preprocessor, tokens : Array[PpToken], file : String, line : Int) -> Bool {
  let defined_replaced = self.replace_defined_operators(tokens)
  let expanded = self.expand_tokens(defined_replaced, {}, file, line, 0)
  let normalized : Array[PpToken] = []
  for tok in expanded {
    if tok.kind == PpIdent {
      normalized.push(pp_token(PpNumber, "0"))
    } else {
      normalized.push(tok)
    }
  }
  pp_eval_if_expr(normalized) != 0L
}

///|
fn Preprocessor::parse_include_name(
  self : Preprocessor,
  tokens : Array[PpToken],
  file : String,
  line : Int,
) -> (String, Bool)? {
  let expanded = self.expand_tokens(tokens, {}, file, line, 0)
  let clean = pp_without_whitespace(expanded)
  if clean.length() == 0 {
    self.set_error("expected header name after #include")
    return None
  }
  if clean[0].kind == PpString {
    return Some((pp_unquote_string_literal(clean[0].text), false))
  }
  if clean[0].is_punct("<") {
    let buf = StringBuilder::new()
    let mut i = 1
    while i < clean.length() && !clean[i].is_punct(">") {
      buf.write_string(clean[i].text)
      i += 1
    }
    if i < clean.length() && clean[i].is_punct(">") {
      return Some((buf.to_string(), true))
    }
  }
  self.set_error("unsupported #include header form")
  None
}

///|
fn Preprocessor::resolve_include(
  self : Preprocessor,
  name : String,
  system : Bool,
  including_file : String,
) -> String? {
  if pp_is_absolute_path(name) && pp_file_exists(name) {
    return Some(name)
  }
  if !system {
    let candidate = pp_join_path(pp_dirname(including_file), name)
    if pp_file_exists(candidate) {
      return Some(candidate)
    }
  }
  let search_paths = if system {
    self.options.system_include_paths + self.options.include_paths
  } else {
    self.options.include_paths
  }
  for dir in search_paths {
    let candidate = pp_join_path(dir, name)
    if pp_file_exists(candidate) {
      return Some(candidate)
    }
  }
  None
}

///|
fn Preprocessor::process_include(
  self : Preprocessor,
  tokens : Array[PpToken],
  including_file : String,
  line : Int,
) -> String {
  match self.parse_include_name(tokens, including_file, line) {
    Some((name, system)) =>
      match self.resolve_include(name, system, including_file) {
        Some(path) =>
          match pp_read_file(path) {
            Some(content) => self.process_source(content, path)
            None => {
              self.set_error("cannot read include file: " + path)
              ""
            }
          }
        None => {
          self.set_error("include file not found: " + name)
          ""
        }
      }
    None => ""
  }
}

///|
fn Preprocessor::process_directive(
  self : Preprocessor,
  tokens : Array[PpToken],
  stack : Array[ConditionalFrame],
  file : String,
  line : Int,
) -> String {
  let hash = pp_first_non_space(tokens)
  if hash >= tokens.length() || !tokens[hash].is_punct("#") {
    return ""
  }
  let after_hash = pp_first_non_space(pp_line_after(tokens, hash + 1))
  let directive_tokens = pp_line_after(tokens, hash + 1)
  let directive_index = pp_first_non_space(directive_tokens)
  if directive_index >= directive_tokens.length() {
    return ""
  }
  let directive = directive_tokens[directive_index]
  let rest = pp_line_after(directive_tokens, directive_index + 1)
  if directive.kind != PpIdent {
    self.set_error("invalid preprocessor directive")
    return ""
  }
  let active = self.is_active(stack)
  match directive.text {
    "if" => {
      let cond = if active { self.eval_if(rest, file, line) } else { false }
      stack.push({
        parent_active: active,
        branch_active: active && cond,
        taken: active && cond,
        else_seen: false,
      })
    }
    "ifdef" | "ifndef" => {
      let idx = pp_first_non_space(rest)
      let defined = idx < rest.length() &&
        rest[idx].kind == PpIdent &&
        self.macros.contains(rest[idx].text)
      let cond = if directive.text == "ifdef" { defined } else { !defined }
      stack.push({
        parent_active: active,
        branch_active: active && cond,
        taken: active && cond,
        else_seen: false,
      })
    }
    "elif" => {
      if stack.length() == 0 {
        self.set_error("#elif without matching #if")
      } else {
        let idx = stack.length() - 1
        let frame = stack[idx]
        if frame.else_seen {
          self.set_error("#elif after #else")
        } else {
          let cond = frame.parent_active &&
            !frame.taken &&
            self.eval_if(rest, file, line)
          stack[idx] = {
            parent_active: frame.parent_active,
            branch_active: cond,
            taken: frame.taken || cond,
            else_seen: false,
          }
        }
      }
    }
    "else" => {
      if stack.length() == 0 {
        self.set_error("#else without matching #if")
      } else {
        let idx = stack.length() - 1
        let frame = stack[idx]
        if frame.else_seen {
          self.set_error("duplicate #else")
        } else {
          let cond = frame.parent_active && !frame.taken
          stack[idx] = {
            parent_active: frame.parent_active,
            branch_active: cond,
            taken: true,
            else_seen: true,
          }
        }
      }
    }
    "endif" => {
      if stack.length() == 0 {
        self.set_error("#endif without matching #if")
      } else {
        ignore(stack.remove(stack.length() - 1))
      }
    }
    "define" =>
      if active {
        self.define_macro(rest)
      }
    "undef" =>
      if active {
        let idx = pp_first_non_space(rest)
        if idx < rest.length() && rest[idx].kind == PpIdent {
          self.macros.remove(rest[idx].text)
        }
      }
    "include" =>
      if active {
        return self.process_include(rest, file, line)
      }
    "error" =>
      if active {
        self.set_error("#error " + pp_tokens_to_source(rest))
      }
    "pragma" => ()
    "line" => ()
    _ =>
      if active {
        self.set_error("unsupported preprocessor directive: #" + directive.text)
      }
  }
  ignore(after_hash)
  ""
}

///|
fn pp_is_directive_line(tokens : Array[PpToken]) -> Bool {
  let idx = pp_first_non_space(tokens)
  idx < tokens.length() && tokens[idx].is_punct("#")
}

///|
fn Preprocessor::process_source(self : Preprocessor, source : String, file : String) -> String {
  for active_file in self.include_stack {
    if active_file == file {
      self.set_error("recursive include detected: " + file)
      return ""
    }
  }
  self.include_stack.push(file)
  let output = StringBuilder::new()
  if self.options.emit_line_markers {
    output.write_string("#line 1 ")
    output.write_string(pp_quote_string(file))
    output.write_char('\n')
  }
  let tokens = pp_tokenize(source)
  let stack : Array[ConditionalFrame] = []
  let mut line_tokens : Array[PpToken] = []
  let mut line = 1
  for tok in tokens {
    if tok.is_newline() {
      if pp_is_directive_line(line_tokens) {
        output.write_string(self.process_directive(line_tokens, stack, file, line))
      } else if self.is_active(stack) {
        let expanded = self.expand_tokens(line_tokens, {}, file, line, 0)
        output.write_string(pp_tokens_to_source(expanded))
        output.write_char('\n')
      }
      line_tokens = []
      line += 1
      if self.error is Some(_) {
        ignore(self.include_stack.remove(self.include_stack.length() - 1))
        return output.to_string()
      }
    } else {
      line_tokens.push(tok)
    }
  }
  if line_tokens.length() > 0 {
    if pp_is_directive_line(line_tokens) {
      output.write_string(self.process_directive(line_tokens, stack, file, line))
    } else if self.is_active(stack) {
      let expanded = self.expand_tokens(line_tokens, {}, file, line, 0)
      output.write_string(pp_tokens_to_source(expanded))
      output.write_char('\n')
    }
  }
  if stack.length() > 0 && self.error is None {
    self.set_error("unterminated conditional directive")
  }
  ignore(self.include_stack.remove(self.include_stack.length() - 1))
  output.to_string()
}

///|
/// Preprocess one C translation unit into ordinary C source for the parser.
pub fn preprocess(
  source : String,
  options : PreprocessOptions,
) -> Result[String, PreprocessError] {
  let pp = Preprocessor::new(options)
  let text = pp.process_source(source, options.filename)
  match pp.error {
    Some(err) => Err(err)
    None => Ok(text)
  }
}

///|
/// Preprocess and parse one C translation unit.
///
/// This is a convenience API; callers that need a hard preprocessing/parsing
/// boundary should call `preprocess` and `@parser.parse` separately.
pub fn parse(
  source : String,
  options : PreprocessOptions,
) -> Result[@parser.Program, PreprocessError] {
  match preprocess(source, options) {
    Ok(text) => Ok(@parser.parse(text))
    Err(err) => Err(err)
  }
}
