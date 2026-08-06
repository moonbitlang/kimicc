///|
/// Incremental parser state for a single C translation unit.
///
/// Most callers should use `parse` instead of constructing `Parser` directly.
/// The state is public so parser tests and compiler tools can inspect it, but
/// its fields are implementation details and may not remain stable.
pub struct Parser {
  lexer : Lexer
  target : @target.Target
  pragma_pack : PragmaPackTable
  mut token : Token
  typedefs : Map[String, Type]
  // Aggregate definitions in creation order, anonymous ones included. Order
  // matters: an anonymous aggregate is created while parsing the declaration
  // that introduces it, so appending as they are built puts every definition
  // ahead of its first use.
  aggregates : Array[StructDecl]
  struct_decls : Map[String, StructDecl]
  local_func_decls : Array[FuncDecl]
  mut anon_counter : Int
  enum_constants : Map[String, Int64]
  globals : Array[GlobalDecl]
  mut value_types : Map[String, Type]
  mut current_func_name : String
  mut static_locals : Map[String, String]
  mut case_label_counter : Int
  mut compound_literal_counter : Int
}

///|
/// Creates a parser over an existing lexer and reads the first token.
///
/// Prefer `parse(input)` unless you need to drive lexer/parser state manually.
pub fn Parser::new(lexer : Lexer) -> Parser {
  Parser::new_for_target(lexer, @target.Target::default())
}

///|
/// Creates a parser using target-specific layout assumptions for constant
/// folding of target-sensitive types.
pub fn Parser::new_for_target(lexer : Lexer, target : @target.Target) -> Parser {
  let p = {
    lexer,
    target,
    pragma_pack: PragmaPackTable::scan(lexer.input),
    token: EOF,
    typedefs: {},
    aggregates: [],
    struct_decls: {},
    local_func_decls: [],
    anon_counter: 0,
    enum_constants: {},
    globals: [],
    value_types: {},
    current_func_name: "",
    static_locals: {},
    case_label_counter: 0,
    compound_literal_counter: 0,
  }
  p.advance()
  p
}

///|
fn Parser::advance(self : Parser) -> Unit {
  self.token = self.lexer.next_token()
}

///|
fn Parser::expect(self : Parser, t : Token) -> Unit {
  if self.token != t {
    abort("Expected \{t} but got \{self.token}")
  }
  self.advance()
}

///|
/// Parses one complete, already preprocessed C translation unit.
///
/// The parser does not run a C preprocessor. Invalid or unsupported syntax
/// aborts instead of returning a structured error value.
pub fn parse(input : String) -> Program {
  parse_for_target(input, @target.Target::default())
}

///|
/// Parses one complete C translation unit using target-specific layout
/// assumptions where parsing must fold layout constants.
pub fn parse_for_target(input : String, target : @target.Target) -> Program {
  let lexer = Lexer::new(input)
  let parser = Parser::new_for_target(lexer, target)
  parser.parse_program()
}

///|
fn Parser::remember_value_type(self : Parser, name : String, ty : Type) -> Unit {
  if name != "" {
    self.value_types[name] = ty
  }
}
