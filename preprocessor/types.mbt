///|
/// Options controlling C preprocessing.
///
/// `filename` names the main translation unit for diagnostics, `__FILE__`,
/// and quote-include lookup. Include paths are searched explicitly; the
/// preprocessor does not auto-discover SDK paths.
pub(all) struct PreprocessOptions {
  filename : String
  include_paths : Array[String]
  system_include_paths : Array[String]
  defines : Map[String, String]
  undefines : Array[String]
  emit_line_markers : Bool
} derive(Eq)

///|
/// Creates conservative default preprocessing options for one source file.
pub fn PreprocessOptions::new(filename : String) -> PreprocessOptions {
  {
    filename,
    include_paths: [],
    system_include_paths: [],
    defines: {},
    undefines: [],
    emit_line_markers: false,
  }
}

///|
/// Structured preprocessing failure.
pub(all) enum PreprocessError {
  Message(String)
} derive(Eq)

///|
/// Returns a human-readable preprocessing error message.
pub fn PreprocessError::to_string(self : PreprocessError) -> String {
  match self {
    Message(message) => message
  }
}

///|
priv enum PpTokenKind {
  PpIdent
  PpNumber
  PpString
  PpChar
  PpPunct
  PpNewline
  PpWhitespace
  PpOther
} derive(Eq)

///|
priv struct PpToken {
  kind : PpTokenKind
  text : String
}

///|
fn pp_token(kind : PpTokenKind, text : String) -> PpToken {
  { kind, text }
}

///|
fn PpToken::is_whitespace(self : PpToken) -> Bool {
  self.kind == PpWhitespace
}

///|
fn PpToken::is_newline(self : PpToken) -> Bool {
  self.kind == PpNewline
}

///|
fn PpToken::is_punct(self : PpToken, text : String) -> Bool {
  self.kind == PpPunct && self.text == text
}

///|
fn PpToken::is_ident(self : PpToken, text : String) -> Bool {
  self.kind == PpIdent && self.text == text
}

///|
priv struct Macro {
  function_like : Bool
  variadic : Bool
  params : Array[String]
  replacement : Array[PpToken]
}

///|
priv struct ConditionalFrame {
  parent_active : Bool
  branch_active : Bool
  taken : Bool
  else_seen : Bool
}

///|
priv struct Preprocessor {
  options : PreprocessOptions
  macros : Map[String, Macro]
  include_stack : Array[String]
  mut error : PreprocessError?
}
