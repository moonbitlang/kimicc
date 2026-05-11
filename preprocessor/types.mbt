///|
/// Options controlling C preprocessing.
///
/// `filename` names the main translation unit for diagnostics, `__FILE__`,
/// and quote-include lookup. Include paths are searched explicitly; the
/// preprocessor does not auto-discover SDK paths.
pub(all) struct PreprocessOptions {
  filename : String
  target : @target.Target
  include_paths : Array[String]
  system_include_paths : Array[String]
  defines : Map[String, String]
  undefines : Array[String]
  undef_predefined : Bool
  allow_missing_includes : Bool
  emit_line_markers : Bool
} derive(Eq)

///|
/// Creates conservative default preprocessing options for one source file.
pub fn PreprocessOptions::new(filename : String) -> PreprocessOptions {
  {
    filename,
    target: @target.Target::default(),
    include_paths: [],
    system_include_paths: [],
    defines: {},
    undefines: [],
    undef_predefined: false,
    allow_missing_includes: false,
    emit_line_markers: false,
  }
}

///|
/// Structured preprocessing failure.
pub(all) enum PreprocessError {
  Message(String)
} derive(Eq)

///|
/// One physical file read while preprocessing.
///
/// `system` is true when the file was resolved from a system include search
/// directory or by an angle-form absolute include.
pub(all) struct PreprocessDependency {
  path : String
  system : Bool
} derive(Eq)

///|
/// Preprocessed source plus the physical files read while preprocessing.
///
/// `dependencies` starts with the main translation-unit filename and then lists
/// resolved include paths in first-seen order.
/// `dependency_records` carries the same paths with system-header classification
/// for compiler-driver dependency output.
pub(all) struct PreprocessResult {
  text : String
  dependencies : Array[String]
  dependency_records : Array[PreprocessDependency]
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
  once_files : Map[String, Bool]
  dependencies : Array[String]
  dependency_records : Array[PreprocessDependency]
  dependency_seen : Map[String, Bool]
  mut line_control_file : String?
  mut line_control_line : Int?
  mut counter : Int
  mut error : PreprocessError?
}
