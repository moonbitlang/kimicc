///|
fn Preprocessor::set_error(self : Preprocessor, message : String) -> Unit {
  if self.error is None {
    self.error = Some(Message(message))
  }
}

///|
fn Preprocessor::is_active(
  _self : Preprocessor,
  stack : Array[ConditionalFrame],
) -> Bool {
  match stack.last() {
    Some(frame) => frame.branch_active
    None => true
  }
}

///|
fn Preprocessor::seed_macro(
  self : Preprocessor,
  name : String,
  replacement : String,
) -> Unit {
  self.macros[name] = {
    function_like: false,
    variadic: false,
    params: [],
    replacement: pp_without_whitespace(pp_tokenize(replacement)),
  }
}

///|
fn Preprocessor::seed_macro_definition(
  self : Preprocessor,
  definition : String,
) -> Unit {
  self.define_macro(pp_tokenize(definition))
}

///|
fn Preprocessor::seed_common_target_macros(self : Preprocessor) -> Unit {
  self.seed_macro("__STDC__", "1")
  self.seed_macro("__STDC_VERSION__", "201112L")
  self.seed_macro("__STDC_HOSTED__", "1")
  self.seed_macro("__GNUC__", "4")
  self.seed_macro("__GNUC_MINOR__", "2")
  self.seed_macro("__GNUC_PATCHLEVEL__", "1")
  self.seed_macro("__clang__", "1")
  self.seed_macro("__LP64__", "1")
  self.seed_macro("_LP64", "1")
  self.seed_macro("__ORDER_LITTLE_ENDIAN__", "1234")
  self.seed_macro("__ORDER_BIG_ENDIAN__", "4321")
  self.seed_macro("__BYTE_ORDER__", "__ORDER_LITTLE_ENDIAN__")
  self.seed_macro("__LITTLE_ENDIAN__", "1")
  self.seed_macro("__CHAR_BIT__", "8")
  self.seed_macro("__SCHAR_MAX__", "127")
  self.seed_macro("__SHRT_MAX__", "32767")
  self.seed_macro("__INT_MAX__", "2147483647")
  self.seed_macro("__LONG_MAX__", "9223372036854775807L")
  self.seed_macro("__LONG_LONG_MAX__", "9223372036854775807LL")
  self.seed_macro("__SIZEOF_SHORT__", "2")
  self.seed_macro("__SIZEOF_INT__", "4")
  self.seed_macro("__SIZEOF_LONG__", "8")
  self.seed_macro("__SIZEOF_LONG_LONG__", "8")
  self.seed_macro("__SIZEOF_FLOAT__", "4")
  self.seed_macro("__SIZEOF_DOUBLE__", "8")
  self.seed_macro("__SIZEOF_POINTER__", "8")
  self.seed_macro("__SIZEOF_SIZE_T__", "8")
  self.seed_macro("__SIZEOF_PTRDIFF_T__", "8")
  self.seed_macro("__SIZEOF_INT128__", "16")
  self.seed_macro("__SIZEOF_WCHAR_T__", "4")
  self.seed_macro("__SIZEOF_WINT_T__", "4")
  self.seed_macro("__POINTER_WIDTH__", "64")
  self.seed_macro("__SIZE_WIDTH__", "64")
  self.seed_macro("__PTRDIFF_WIDTH__", "64")
  self.seed_macro("__INTPTR_WIDTH__", "64")
  self.seed_macro("__UINTPTR_WIDTH__", "64")
  self.seed_macro("__INTMAX_WIDTH__", "64")
  self.seed_macro("__UINTMAX_WIDTH__", "64")
  self.seed_macro("__SIZE_TYPE__", "long unsigned int")
  self.seed_macro("__PTRDIFF_TYPE__", "long int")
  self.seed_macro("__INTPTR_TYPE__", "long int")
  self.seed_macro("__UINTPTR_TYPE__", "long unsigned int")
  self.seed_macro("__INTMAX_TYPE__", "long int")
  self.seed_macro("__UINTMAX_TYPE__", "long unsigned int")
  self.seed_macro("__INT8_TYPE__", "signed char")
  self.seed_macro("__UINT8_TYPE__", "unsigned char")
  self.seed_macro("__INT16_TYPE__", "short")
  self.seed_macro("__UINT16_TYPE__", "unsigned short")
  self.seed_macro("__INT32_TYPE__", "int")
  self.seed_macro("__UINT32_TYPE__", "unsigned int")
  self.seed_macro("__INT64_TYPE__", "long long int")
  self.seed_macro("__UINT64_TYPE__", "long long unsigned int")
  self.seed_macro("__INT_LEAST8_TYPE__", "signed char")
  self.seed_macro("__UINT_LEAST8_TYPE__", "unsigned char")
  self.seed_macro("__INT_LEAST16_TYPE__", "short")
  self.seed_macro("__UINT_LEAST16_TYPE__", "unsigned short")
  self.seed_macro("__INT_LEAST32_TYPE__", "int")
  self.seed_macro("__UINT_LEAST32_TYPE__", "unsigned int")
  self.seed_macro("__INT_LEAST64_TYPE__", "long long int")
  self.seed_macro("__UINT_LEAST64_TYPE__", "long long unsigned int")
  self.seed_macro("__INT_FAST8_TYPE__", "signed char")
  self.seed_macro("__UINT_FAST8_TYPE__", "unsigned char")
  self.seed_macro("__INT_FAST16_TYPE__", "short")
  self.seed_macro("__UINT_FAST16_TYPE__", "unsigned short")
  self.seed_macro("__INT_FAST32_TYPE__", "int")
  self.seed_macro("__UINT_FAST32_TYPE__", "unsigned int")
  self.seed_macro("__INT_FAST64_TYPE__", "long long int")
  self.seed_macro("__UINT_FAST64_TYPE__", "long long unsigned int")
  self.seed_macro("__WCHAR_TYPE__", "int")
  self.seed_macro("__WINT_TYPE__", "int")
  self.seed_macro("__WCHAR_MAX__", "2147483647")
  self.seed_macro("__ATOMIC_RELAXED", "0")
  self.seed_macro("__ATOMIC_CONSUME", "1")
  self.seed_macro("__ATOMIC_ACQUIRE", "2")
  self.seed_macro("__ATOMIC_RELEASE", "3")
  self.seed_macro("__ATOMIC_ACQ_REL", "4")
  self.seed_macro("__ATOMIC_SEQ_CST", "5")
  self.seed_macro("__GCC_ATOMIC_BOOL_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_CHAR_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_SHORT_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_INT_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_LONG_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_LLONG_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_POINTER_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_TEST_AND_SET_TRUEVAL", "1")
  self.seed_macro("__GNUC_STDC_INLINE__", "1")
  self.seed_macro("__STDC_UTF_16__", "1")
  self.seed_macro("__STDC_UTF_32__", "1")
  self.seed_macro("__FINITE_MATH_ONLY__", "0")
}

///|
fn Preprocessor::seed_darwin_arm64_macros(self : Preprocessor) -> Unit {
  self.seed_macro("__APPLE__", "1")
  self.seed_macro("__APPLE_CC__", "6000")
  self.seed_macro("__MACH__", "1")
  self.seed_macro("__aarch64__", "1")
  self.seed_macro("__arm64__", "1")
  self.seed_macro("__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__", "150500")
}

///|
fn Preprocessor::seed_linux_amd64_macros(self : Preprocessor) -> Unit {
  self.seed_macro("__gnu_linux__", "1")
  self.seed_macro("__linux__", "1")
  self.seed_macro("__linux", "1")
  self.seed_macro("linux", "1")
  self.seed_macro("__unix__", "1")
  self.seed_macro("__unix", "1")
  self.seed_macro("unix", "1")
  self.seed_macro("__ELF__", "1")
  self.seed_macro("__x86_64__", "1")
  self.seed_macro("__x86_64", "1")
  self.seed_macro("__amd64__", "1")
  self.seed_macro("__amd64", "1")
  self.seed_macro("__REGISTER_PREFIX__", "")
  self.seed_macro("__USER_LABEL_PREFIX__", "")
  self.seed_macro("__SIZEOF_LONG_DOUBLE__", "16")
  self.seed_macro("__WINT_TYPE__", "unsigned int")
  self.seed_macro("__WINT_MAX__", "4294967295U")
}

///|
fn Preprocessor::seed_target_macros(self : Preprocessor) -> Unit {
  self.seed_common_target_macros()
  match self.options.target {
    DarwinArm64 => self.seed_darwin_arm64_macros()
    LinuxAmd64 => self.seed_linux_amd64_macros()
  }
}

///|
fn Preprocessor::new(options : PreprocessOptions) -> Preprocessor {
  let pp = {
    options,
    macros: {},
    include_stack: [],
    once_files: {},
    counter: 0,
    error: None,
  }
  pp.seed_target_macros()
  pp.seed_macro_definition("__has_builtin(x) 0")
  pp.seed_macro_definition("__has_attribute(x) 0")
  pp.seed_macro_definition("__has_feature(x) 0")
  pp.seed_macro_definition("__has_extension(x) 0")
  pp.seed_macro_definition("__has_c_attribute(x) 0")
  pp.seed_macro_definition("__has_declspec_attribute(x) 0")
  pp.seed_macro_definition("__has_warning(x) 0")
  pp.seed_macro_definition("__is_identifier(x) 1")
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
fn Preprocessor::define_macro(
  self : Preprocessor,
  tokens : Array[PpToken],
) -> Unit {
  let start = pp_first_non_space(tokens)
  if start >= tokens.length() || tokens[start].kind != PpIdent {
    self.set_error("expected macro name after #define")
    return
  }
  let name = tokens[start].text
  let mut function_like = false
  let mut variadic = false
  let params : Array[String] = []
  let mut replacement_start = start + 1
  if replacement_start < tokens.length() &&
    tokens[replacement_start].is_punct("(") {
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
        variadic = true
        params.push("__VA_ARGS__")
        i += 1
      } else if tok.kind == PpIdent {
        if i + 1 < tokens.length() && tokens[i + 1].is_punct("...") {
          variadic = true
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
  let replacement = pp_without_whitespace(
    pp_line_after(tokens, replacement_start),
  )
  self.macros[name] = { function_like, variadic, params, replacement }
}

///|
fn pp_parenthesized_body(
  tokens : Array[PpToken],
  lparen : Int,
) -> (Array[PpToken], Int)? {
  if lparen >= tokens.length() || !tokens[lparen].is_punct("(") {
    return None
  }
  let body : Array[PpToken] = []
  let mut depth = 0
  let mut i = lparen
  while i < tokens.length() {
    let tok = tokens[i]
    if tok.is_punct("(") {
      if depth > 0 {
        body.push(tok)
      }
      depth += 1
    } else if tok.is_punct(")") {
      depth -= 1
      if depth == 0 {
        return Some((body, i + 1))
      }
      body.push(tok)
    } else {
      body.push(tok)
    }
    i += 1
  }
  None
}

///|
fn Preprocessor::parse_include_query_name(
  self : Preprocessor,
  tokens : Array[PpToken],
  file : String,
  line : Int,
) -> (String, Bool)? {
  let expanded = self.expand_tokens(tokens, {}, file, line, 0)
  let clean = pp_without_whitespace(expanded)
  if clean.length() == 0 {
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
  None
}

///|
fn Preprocessor::has_include_query(
  self : Preprocessor,
  tokens : Array[PpToken],
  file : String,
  line : Int,
  next : Bool,
) -> Bool {
  match self.parse_include_query_name(tokens, file, line) {
    Some((name, system)) =>
      if next {
        self.resolve_include_next(name, system, file) is Some(_)
      } else {
        self.resolve_include(name, system, file) is Some(_)
      }
    None => false
  }
}

///|
fn Preprocessor::replace_defined_operators(
  self : Preprocessor,
  tokens : Array[PpToken],
  file : String,
  line : Int,
) -> Array[PpToken] {
  let clean = pp_without_whitespace(tokens)
  let result : Array[PpToken] = []
  let mut i = 0
  while i < clean.length() {
    let tok = clean[i]
    if tok.is_ident("__has_include") || tok.is_ident("__has_include_next") {
      if i + 1 < clean.length() && clean[i + 1].is_punct("(") {
        match pp_parenthesized_body(clean, i + 1) {
          Some((body, end_index)) => {
            let found = self.has_include_query(
              body,
              file,
              line,
              tok.is_ident("__has_include_next"),
            )
            result.push(pp_token(PpNumber, if found { "1" } else { "0" }))
            i = end_index
          }
          None => {
            result.push(pp_token(PpNumber, "0"))
            i += 1
          }
        }
      } else {
        result.push(pp_token(PpNumber, "0"))
        i += 1
      }
    } else if tok.is_ident("defined") {
      if i + 1 < clean.length() && clean[i + 1].is_punct("(") {
        if i + 2 < clean.length() && clean[i + 2].kind == PpIdent {
          let name = clean[i + 2].text
          result.push(
            pp_token(
              PpNumber,
              if self.macros.contains(name) {
                "1"
              } else {
                "0"
              },
            ),
          )
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
        result.push(
          pp_token(PpNumber, if self.macros.contains(name) { "1" } else { "0" }),
        )
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
fn Preprocessor::eval_if(
  self : Preprocessor,
  tokens : Array[PpToken],
  file : String,
  line : Int,
) -> Bool {
  let defined_replaced = self.replace_defined_operators(tokens, file, line)
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
    self.options.include_paths + self.options.system_include_paths
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
fn Preprocessor::resolve_include_next(
  self : Preprocessor,
  name : String,
  system : Bool,
  including_file : String,
) -> String? {
  let search_paths = if system {
    self.options.system_include_paths + self.options.include_paths
  } else {
    self.options.include_paths + self.options.system_include_paths
  }
  let current_dir = pp_dirname(including_file)
  let mut found_current = false
  for dir in search_paths {
    let candidate = pp_join_path(dir, name)
    if found_current {
      if pp_file_exists(candidate) {
        return Some(candidate)
      }
    } else if candidate == including_file || dir == current_dir {
      found_current = true
    }
  }
  if !found_current {
    for dir in search_paths {
      let candidate = pp_join_path(dir, name)
      if candidate != including_file && pp_file_exists(candidate) {
        return Some(candidate)
      }
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
          if self.once_files.contains(path) {
            ""
          } else {
            match pp_read_file(path) {
              Some(content) => self.process_source(content, path)
              None => {
                self.set_error("cannot read include file: " + path)
                ""
              }
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
fn Preprocessor::process_include_next(
  self : Preprocessor,
  tokens : Array[PpToken],
  including_file : String,
  line : Int,
) -> String {
  match self.parse_include_name(tokens, including_file, line) {
    Some((name, system)) =>
      match self.resolve_include_next(name, system, including_file) {
        Some(path) =>
          if self.once_files.contains(path) {
            ""
          } else {
            match pp_read_file(path) {
              Some(content) => self.process_source(content, path)
              None => {
                self.set_error("cannot read include file: " + path)
                ""
              }
            }
          }
        None => {
          self.set_error("include_next file not found: " + name)
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
    "elifdef" | "elifndef" =>
      if stack.length() == 0 {
        self.set_error("#" + directive.text + " without matching #if")
      } else {
        let idx = stack.length() - 1
        let frame = stack[idx]
        if frame.else_seen {
          self.set_error("#" + directive.text + " after #else")
        } else {
          let name_index = pp_first_non_space(rest)
          let defined = name_index < rest.length() &&
            rest[name_index].kind == PpIdent &&
            self.macros.contains(rest[name_index].text)
          let branch_cond = if directive.text == "elifdef" {
            defined
          } else {
            !defined
          }
          let cond = frame.parent_active && !frame.taken && branch_cond
          stack[idx] = {
            parent_active: frame.parent_active,
            branch_active: cond,
            taken: frame.taken || cond,
            else_seen: false,
          }
        }
      }
    "elif" =>
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
    "else" =>
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
    "endif" =>
      if stack.length() == 0 {
        self.set_error("#endif without matching #if")
      } else {
        ignore(stack.remove(stack.length() - 1))
      }
    "define" => if active { self.define_macro(rest) }
    "undef" =>
      if active {
        let idx = pp_first_non_space(rest)
        if idx < rest.length() && rest[idx].kind == PpIdent {
          self.macros.remove(rest[idx].text)
        }
      }
    "include" => if active { return self.process_include(rest, file, line) }
    "include_next" =>
      if active {
        return self.process_include_next(rest, file, line)
      }
    "error" =>
      if active {
        self.set_error("#error " + pp_tokens_to_source(rest))
      }
    "warning" | "ident" | "sccs" => ()
    "pragma" =>
      if active {
        let idx = pp_first_non_space(rest)
        if idx < rest.length() && rest[idx].is_ident("once") {
          self.once_files[file] = true
        }
      }
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
fn pp_is_unterminated_macro_error(error : PreprocessError?) -> Bool {
  match error {
    Some(Message(message)) =>
      message.has_prefix("unterminated macro invocation")
    None => false
  }
}

///|
fn Preprocessor::pending_ends_with_function_macro(
  self : Preprocessor,
  pending : Array[PpToken],
) -> Bool {
  let mut i = pending.length() - 1
  while i >= 0 {
    let tok = pending[i]
    if tok.is_whitespace() || tok.is_newline() {
      i -= 1
      continue
    }
    if tok.kind == PpIdent {
      match self.macros.get(tok.text) {
        Some(macro_) => return macro_.function_like
        None => return false
      }
    }
    return false
  }
  false
}

///|
fn Preprocessor::flush_pending_tokens(
  self : Preprocessor,
  pending : Array[PpToken],
  output : StringBuilder,
  file : String,
  line : Int,
  is_final : Bool,
) -> (Array[PpToken], Bool) {
  if pending.length() == 0 {
    return (pending, true)
  }
  if !is_final && self.pending_ends_with_function_macro(pending) {
    return (pending, false)
  }
  let expanded = self.expand_tokens(pending, {}, file, line, 0)
  if pp_is_unterminated_macro_error(self.error) && !is_final {
    self.error = None
    (pending, false)
  } else if self.error is Some(_) {
    (pending, false)
  } else {
    output.write_string(pp_tokens_to_source(expanded))
    output.write_char('\n')
    ([], true)
  }
}

///|
fn Preprocessor::process_source(
  self : Preprocessor,
  source : String,
  file : String,
) -> String {
  for active_file in self.include_stack {
    if active_file == file {
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
  let mut pending_tokens : Array[PpToken] = []
  let mut pending_line = 1
  let mut line = 1
  for tok in tokens {
    if tok.is_newline() {
      if pp_is_directive_line(line_tokens) {
        let (next_pending, _) = self.flush_pending_tokens(
          pending_tokens, output, file, pending_line, true,
        )
        pending_tokens = next_pending
        if self.error is Some(_) {
          ignore(self.include_stack.remove(self.include_stack.length() - 1))
          return output.to_string()
        }
        output.write_string(
          self.process_directive(line_tokens, stack, file, line),
        )
      } else if self.is_active(stack) {
        if pending_tokens.length() == 0 {
          pending_line = line
        }
        for pending_token in line_tokens {
          pending_tokens.push(pending_token)
        }
        pending_tokens.push(pp_token(PpWhitespace, " "))
        let (next_pending, _) = self.flush_pending_tokens(
          pending_tokens, output, file, pending_line, false,
        )
        pending_tokens = next_pending
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
      let (next_pending, _) = self.flush_pending_tokens(
        pending_tokens, output, file, pending_line, true,
      )
      pending_tokens = next_pending
      if self.error is Some(_) {
        ignore(self.include_stack.remove(self.include_stack.length() - 1))
        return output.to_string()
      }
      output.write_string(
        self.process_directive(line_tokens, stack, file, line),
      )
    } else if self.is_active(stack) {
      if pending_tokens.length() == 0 {
        pending_line = line
      }
      for pending_token in line_tokens {
        pending_tokens.push(pending_token)
      }
    }
  }
  let (next_pending, _) = self.flush_pending_tokens(
    pending_tokens, output, file, pending_line, true,
  )
  pending_tokens = next_pending
  ignore(pending_tokens)
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
