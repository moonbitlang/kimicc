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
  mut token_start : Int
  typedefs : Map[String, Type]
  // Typedef names that denote a bare function type, like `typedef void F(int)`.
  // The type model spells every function as a pointer, so the map is what
  // remembers that `F *` adds no second level: pointer-to-function-type is the
  // function pointer itself. `typedef void (*F)(int)` is not in this map.
  function_typedefs : Map[String, Bool]
  // Aggregate definitions in creation order, anonymous ones included. Order
  // matters: an anonymous aggregate is created while parsing the declaration
  // that introduces it, so appending as they are built puts every definition
  // ahead of its first use.
  aggregates : Array[StructDecl]
  // Top-level entries in source order; see `Program::items`. Aggregates and
  // globals are appended here by the same helpers that append to the grouped
  // arrays, and functions are appended by `parse_program` as they complete.
  items : Array[TopLevel]
  struct_decls : Map[String, StructDecl]
  // Tag scoping: `tag_aliases` is the lexical view, saved and restored around
  // each block; `used_tag_names` is global, so a block-scoped tag never reuses
  // a name. See tag_scope.mbt.
  mut tag_aliases : Map[String, String]
  used_tag_names : Map[String, Bool]
  mut block_depth : Int
  // Depth of struct/union body nesting. A definition written inside another
  // aggregate's member list is not a top-level entry -- it prints inside its
  // parent -- so `add_aggregate` skips the items tape while this is nonzero.
  mut struct_body_depth : Int
  local_func_decls : Array[FuncDecl]
  mut anon_counter : Int
  enum_constants : Map[String, Int64]
  globals : Array[GlobalDecl]
  mut value_types : Map[String, Type]
  mut current_func_name : String
  mut static_locals : Map[String, String]
  mut compound_literal_counter : Int
}

///|
/// Creates a parser over an existing lexer and reads the first token.
///
/// Prefer `parse(input)` unless you need to drive lexer/parser state manually.
pub fn Parser::new(lexer : Lexer) -> Parser raise ParseError {
  Parser::new_for_target(lexer, @target.Target::default())
}

///|
/// Creates a parser using target-specific layout assumptions for constant
/// folding of target-sensitive types.
pub fn Parser::new_for_target(
  lexer : Lexer,
  target : @target.Target,
) -> Parser raise ParseError {
  let p = {
    lexer,
    target,
    pragma_pack: PragmaPackTable::scan(lexer.input),
    token: EOF,
    token_start: 0,
    typedefs: {},
    function_typedefs: {},
    aggregates: [],
    items: [],
    struct_decls: {},
    tag_aliases: Map([]),
    used_tag_names: Map([]),
    block_depth: 0,
    struct_body_depth: 0,
    local_func_decls: [],
    anon_counter: 0,
    enum_constants: {},
    globals: [],
    value_types: {},
    current_func_name: "",
    static_locals: {},
    compound_literal_counter: 0,
  }
  p.advance()
  p
}

///|
/// Reads the next token, remembering where it starts.
///
/// The start offset is what diagnostics report: by the time the parser objects
/// to a token, the lexer has already advanced past it, so reporting
/// `lexer.pos` would point at whatever follows.
fn Parser::advance(self : Parser) -> Unit raise ParseError {
  self.lexer.skip_whitespace()
  self.token_start = self.lexer.pos
  self.token = self.lexer.next_token()
}

///|
fn Parser::expect(self : Parser, t : Token) -> Unit raise ParseError {
  if self.token != t {
    self.unexpected("\{t}")
  }
  self.advance()
}

///|
/// Parses one complete, already preprocessed C translation unit.
///
/// The parser does not run a C preprocessor. Invalid or unsupported syntax
/// aborts instead of returning a structured error value.
pub fn parse(input : String) -> Program raise ParseError {
  parse_for_target(input, @target.Target::default())
}

///|
/// Parses one complete C translation unit using target-specific layout
/// assumptions where parsing must fold layout constants.
pub fn parse_for_target(
  input : String,
  target : @target.Target,
) -> Program raise ParseError {
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

///|
/// Returns the parser's current position, for reporting.
fn Parser::position(self : Parser) -> Position {
  position_at(self.lexer.input, self.token_start)
}

///|
/// Raises `Unexpected` at the current position.
fn[T] Parser::unexpected(
  self : Parser,
  expected : String,
) -> T raise ParseError {
  raise Unexpected(position=self.position(), expected~, found="\{self.token}")
}

///|
/// Raises `Unsupported` at the current position.
fn[T] Parser::unsupported(self : Parser, what : String) -> T raise ParseError {
  raise Unsupported(position=self.position(), what~)
}

///|
/// Raises `Malformed` at the current position.
fn[T] Parser::malformed(self : Parser, what : String) -> T raise ParseError {
  raise Malformed(position=self.position(), what~)
}

///|
/// Registers an aggregate definition in both the grouped array and the source-
/// order tape, sharing one value.
fn Parser::add_aggregate(self : Parser, decl : StructDecl) -> Unit {
  self.aggregates.push(decl)
  // A definition inside another aggregate's member list prints inside that
  // parent, so it takes no place of its own in the top-level order. Keeping it
  // out of `items` is also what keeps the grouped array's creation order a
  // fixed point: printed inline, it is re-created at the same member position
  // on reparse rather than ahead of its parent as a hoisted definition.
  if self.struct_body_depth == 0 {
    self.items.push(Aggregate(self.aggregates.length() - 1))
  }
}

///|
/// Registers a global in both the grouped array and the source-order tape.
///
/// Statics and externs promoted out of a function body come through here too,
/// while the body is still being parsed -- so they land ahead of the function
/// that contains them, which is where their references must sit for a printed
/// program to compile.
fn Parser::add_global(self : Parser, decl : GlobalDecl) -> Unit {
  self.globals.push(decl)
  self.items.push(Global(self.globals.length() - 1))
}
