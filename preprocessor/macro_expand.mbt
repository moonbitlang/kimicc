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
fn pp_query_name(args : Array[Array[PpToken]]) -> String? {
  if args.length() != 1 {
    return None
  }
  let clean = pp_without_whitespace(args[0])
  if clean.length() != 1 || clean[0].kind != PpIdent {
    return None
  }
  Some(clean[0].text)
}

///|
fn pp_has_attribute(name : String) -> Bool {
  match name {
    "packed" | "__packed__" | "aligned" | "__aligned__" => true
    _ => false
  }
}

///|
fn pp_has_feature(name : String) -> Bool {
  match name {
    "c_alignas" | "c_static_assert" | "c_atomic" => true
    _ => false
  }
}

///|
fn pp_is_identifier_query(name : String) -> Bool {
  match name {
    "auto"
    | "break"
    | "case"
    | "char"
    | "const"
    | "continue"
    | "default"
    | "do"
    | "double"
    | "else"
    | "enum"
    | "extern"
    | "float"
    | "for"
    | "goto"
    | "if"
    | "inline"
    | "int"
    | "long"
    | "register"
    | "restrict"
    | "return"
    | "short"
    | "signed"
    | "sizeof"
    | "static"
    | "struct"
    | "switch"
    | "typedef"
    | "union"
    | "unsigned"
    | "void"
    | "volatile"
    | "while"
    | "_Alignas"
    | "alignas"
    | "_Atomic"
    | "_Bool"
    | "bool"
    | "_Noreturn"
    | "_Static_assert"
    | "__Static_assert"
    | "static_assert"
    | "__extension__"
    | "__inline"
    | "__inline__"
    | "__restrict"
    | "__restrict__"
    | "__signed"
    | "__signed__"
    | "__unsigned"
    | "__unsigned__"
    | "__volatile"
    | "__volatile__"
    | "__const"
    | "__const__"
    | "__attribute"
    | "__attribute__"
    | "__asm"
    | "__asm__"
    | "asm"
    | "__builtin_va_list"
    | "__int128"
    | "__int128_t"
    | "__uint128_t" => false
    _ => true
  }
}

///|
fn pp_linux_amd64_has_builtin(name : String) -> Bool {
  match name {
    "__builtin_expect"
    | "__builtin_expect_with_probability"
    | "__builtin_assume"
    | "__builtin_assume_aligned"
    | "__builtin_prefetch"
    | "__builtin_constant_p"
    | "__builtin_object_size"
    | "__builtin_frame_address"
    | "__builtin_return_address"
    | "__builtin_extract_return_addr"
    | "__builtin_frob_return_addr"
    | "__builtin_unreachable"
    | "__builtin_trap"
    | "__builtin_alloca"
    | "__builtin_va_start"
    | "__builtin_va_arg"
    | "__builtin_va_end"
    | "__builtin_va_copy"
    | "__builtin_offsetof"
    | "__builtin_abs"
    | "__builtin_labs"
    | "__builtin_llabs"
    | "__builtin_add_overflow"
    | "__builtin_sub_overflow"
    | "__builtin_mul_overflow"
    | "__builtin_sadd_overflow"
    | "__builtin_saddl_overflow"
    | "__builtin_saddll_overflow"
    | "__builtin_uadd_overflow"
    | "__builtin_uaddl_overflow"
    | "__builtin_uaddll_overflow"
    | "__builtin_ssub_overflow"
    | "__builtin_ssubl_overflow"
    | "__builtin_ssubll_overflow"
    | "__builtin_usub_overflow"
    | "__builtin_usubl_overflow"
    | "__builtin_usubll_overflow"
    | "__builtin_smul_overflow"
    | "__builtin_smull_overflow"
    | "__builtin_smulll_overflow"
    | "__builtin_umul_overflow"
    | "__builtin_umull_overflow"
    | "__builtin_umulll_overflow"
    | "__builtin_clz"
    | "__builtin_clzl"
    | "__builtin_clzll"
    | "__builtin_ctz"
    | "__builtin_ctzl"
    | "__builtin_ctzll"
    | "__builtin_ffs"
    | "__builtin_ffsl"
    | "__builtin_ffsll"
    | "__builtin_parity"
    | "__builtin_parityl"
    | "__builtin_parityll"
    | "__builtin_popcount"
    | "__builtin_popcountl"
    | "__builtin_popcountll"
    | "__builtin_bswap"
    | "__builtin_bswap16"
    | "__builtin_bswap32"
    | "__builtin_bswap64"
    | "__builtin_rotateleft"
    | "__builtin_rotateleft32"
    | "__builtin_rotateleft64"
    | "__builtin_rotateright"
    | "__builtin_rotateright32"
    | "__builtin_rotateright64"
    | "__builtin_bzero"
    | "__builtin_memcpy"
    | "__builtin___memcpy_chk"
    | "__builtin_memmove"
    | "__builtin___memmove_chk"
    | "__builtin_memset"
    | "__builtin___memset_chk"
    | "__builtin_memcmp"
    | "__builtin_memchr"
    | "__builtin_strlen"
    | "__builtin_strcmp"
    | "__builtin_strncmp"
    | "__builtin_strcpy"
    | "__builtin___strcpy_chk"
    | "__builtin_strcat"
    | "__builtin___strcat_chk"
    | "__builtin_strncpy"
    | "__builtin___strncpy_chk"
    | "__builtin_strncat"
    | "__builtin___strncat_chk"
    | "__builtin_strchr"
    | "__builtin_strrchr"
    | "__builtin_strstr"
    | "__builtin___strlcpy_chk"
    | "__builtin___strlcat_chk"
    | "__builtin___snprintf_chk"
    | "__builtin___vsnprintf_chk"
    | "__builtin___sprintf_chk"
    | "__builtin___vsprintf_chk"
    | "__builtin___printf_chk"
    | "__builtin___fprintf_chk"
    | "__builtin___vfprintf_chk"
    | "__builtin_fabs"
    | "__builtin_fabsf"
    | "__builtin_fabsl"
    | "__builtin_copysign"
    | "__builtin_copysignf"
    | "__builtin_copysignl"
    | "__builtin_sqrt"
    | "__builtin_sqrtf"
    | "__builtin_sqrtl"
    | "__builtin_nan"
    | "__builtin_nanf"
    | "__builtin_nanl"
    | "__builtin_huge_val"
    | "__builtin_huge_valf"
    | "__builtin_huge_vall"
    | "__builtin_inf"
    | "__builtin_inff"
    | "__builtin_infl"
    | "__builtin_isgreater"
    | "__builtin_isgreaterequal"
    | "__builtin_isless"
    | "__builtin_islessequal"
    | "__builtin_islessgreater"
    | "__builtin_isunordered"
    | "__builtin_isnan"
    | "__builtin_isnanf"
    | "__builtin_isnanl"
    | "__builtin_isinf"
    | "__builtin_isinff"
    | "__builtin_isinfl"
    | "__builtin_isfinite"
    | "__builtin_isfinitef"
    | "__builtin_isfinitel"
    | "__builtin_isnormal"
    | "__builtin_isnormalf"
    | "__builtin_isnormall"
    | "__builtin_signbit"
    | "__builtin_signbitf"
    | "__builtin_signbitl"
    | "__atomic_load"
    | "__atomic_load_n"
    | "__atomic_store"
    | "__atomic_store_n"
    | "__atomic_exchange"
    | "__atomic_exchange_n"
    | "__atomic_compare_exchange"
    | "__atomic_compare_exchange_n"
    | "__atomic_fetch_add"
    | "__atomic_fetch_sub"
    | "__atomic_fetch_and"
    | "__atomic_fetch_or"
    | "__atomic_fetch_xor"
    | "__atomic_fetch_nand"
    | "__atomic_add_fetch"
    | "__atomic_sub_fetch"
    | "__atomic_and_fetch"
    | "__atomic_or_fetch"
    | "__atomic_xor_fetch"
    | "__atomic_nand_fetch"
    | "__atomic_test_and_set"
    | "__atomic_clear"
    | "__atomic_thread_fence"
    | "__atomic_signal_fence"
    | "__atomic_always_lock_free"
    | "__atomic_is_lock_free"
    | "__c11_atomic_load"
    | "__c11_atomic_store"
    | "__c11_atomic_exchange"
    | "__c11_atomic_compare_exchange_strong"
    | "__c11_atomic_compare_exchange_weak"
    | "__c11_atomic_fetch_add"
    | "__c11_atomic_fetch_sub"
    | "__c11_atomic_fetch_and"
    | "__c11_atomic_fetch_or"
    | "__c11_atomic_fetch_xor"
    | "__c11_atomic_thread_fence"
    | "__c11_atomic_signal_fence"
    | "__c11_atomic_is_lock_free"
    | "__sync_synchronize" => true
    _ => false
  }
}

///|
fn Preprocessor::has_builtin_query(self : Preprocessor, name : String) -> Bool {
  match self.options.target {
    LinuxAmd64 => pp_linux_amd64_has_builtin(name)
    DarwinArm64 => false
  }
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
fn Preprocessor::variadic_argument_nonempty(
  self : Preprocessor,
  macro_ : Macro,
  args : Array[Array[PpToken]],
) -> Bool {
  if !macro_.variadic || macro_.params.length() == 0 {
    return false
  }
  let index = macro_.params.length() - 1
  pp_without_whitespace(self.macro_argument(macro_, args, index)).length() > 0
}

///|
fn Preprocessor::substitute_macro_replacement(
  self : Preprocessor,
  macro_ : Macro,
  replacement : Array[PpToken],
  args : Array[Array[PpToken]],
  disabled : Map[String, Bool],
  file : String,
  line : Int,
  depth : Int,
) -> Array[PpToken] {
  let result : Array[PpToken] = []
  let has_variadic_args = self.variadic_argument_nonempty(macro_, args)
  let mut i = 0
  while i < replacement.length() {
    let tok = replacement[i]
    if macro_.variadic &&
      tok.kind == PpIdent &&
      tok.text == "__VA_OPT__" &&
      i + 1 < replacement.length() &&
      replacement[i + 1].is_punct("(") {
      match pp_parenthesized_body(replacement, i + 1) {
        Some((body, end_index)) => {
          if has_variadic_args {
            let substituted = self.substitute_macro_replacement(
              macro_,
              body,
              args,
              disabled,
              file,
              line,
              depth + 1,
            )
            for body_tok in substituted {
              result.push(body_tok)
            }
          }
          i = end_index
          continue
        }
        None => {
          self.set_error("unterminated __VA_OPT__ in macro replacement")
          return result
        }
      }
    }
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
fn Preprocessor::substitute_macro(
  self : Preprocessor,
  macro_ : Macro,
  args : Array[Array[PpToken]],
  disabled : Map[String, Bool],
  file : String,
  line : Int,
  depth : Int,
) -> Array[PpToken] {
  self.substitute_macro_replacement(
    macro_,
    macro_.replacement,
    args,
    disabled,
    file,
    line,
    depth,
  )
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
      if tok.text == "__COUNTER__" {
        result.push(pp_token(PpNumber, self.counter.to_string()))
        self.counter += 1
        i += 1
        continue
      }
      if tok.text == "__has_builtin" &&
        i + 1 < clean.length() &&
        clean[i + 1].is_punct("(") {
        match self.parse_macro_invocation(clean, i + 1, tok.text) {
          Some((args, end_index)) => {
            let value = match pp_query_name(args) {
              Some(name) => if self.has_builtin_query(name) { "1" } else { "0" }
              None => "0"
            }
            result.push(pp_token(PpNumber, value))
            i = end_index
            continue
          }
          None => ()
        }
      }
      if tok.text == "__has_attribute" &&
        i + 1 < clean.length() &&
        clean[i + 1].is_punct("(") {
        match self.parse_macro_invocation(clean, i + 1, tok.text) {
          Some((args, end_index)) => {
            let value = match pp_query_name(args) {
              Some(name) => if pp_has_attribute(name) { "1" } else { "0" }
              None => "0"
            }
            result.push(pp_token(PpNumber, value))
            i = end_index
            continue
          }
          None => ()
        }
      }
      if (tok.text == "__has_feature" || tok.text == "__has_extension") &&
        i + 1 < clean.length() &&
        clean[i + 1].is_punct("(") {
        match self.parse_macro_invocation(clean, i + 1, tok.text) {
          Some((args, end_index)) => {
            let value = match pp_query_name(args) {
              Some(name) => if pp_has_feature(name) { "1" } else { "0" }
              None => "0"
            }
            result.push(pp_token(PpNumber, value))
            i = end_index
            continue
          }
          None => ()
        }
      }
      if tok.text == "__is_identifier" &&
        i + 1 < clean.length() &&
        clean[i + 1].is_punct("(") {
        match self.parse_macro_invocation(clean, i + 1, tok.text) {
          Some((args, end_index)) => {
            let value = match pp_query_name(args) {
              Some(name) => if pp_is_identifier_query(name) { "1" } else { "0" }
              None => "0"
            }
            result.push(pp_token(PpNumber, value))
            i = end_index
            continue
          }
          None => ()
        }
      }
      if (
          tok.text == "__has_c_attribute" ||
          tok.text == "__has_declspec_attribute" ||
          tok.text == "__has_warning"
        ) &&
        i + 1 < clean.length() &&
        clean[i + 1].is_punct("(") {
        i = pp_skip_parenthesized(clean, i + 1)
        result.push(pp_token(PpNumber, "0"))
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
