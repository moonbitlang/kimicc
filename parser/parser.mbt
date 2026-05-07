///|
/// Incremental parser state for a single C translation unit.
///
/// Most callers should use `parse` instead of constructing `Parser` directly.
/// The state is public so parser tests and compiler tools can inspect it, but
/// its fields are implementation details and may not remain stable.
pub struct Parser {
  lexer : Lexer
  mut token : Token
  typedefs : Map[String, Type]
  anonymous_structs : Array[StructDecl]
  struct_decls : Map[String, StructDecl]
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
  let p = {
    lexer,
    token: EOF,
    typedefs: {},
    anonymous_structs: [],
    struct_decls: {},
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
    abort("Expected " + t.to_string() + " but got " + self.token.to_string())
  }
  self.advance()
}

///|
fn Parser::skip_balanced_parens(self : Parser) -> Unit {
  // Assumes current token is LParen, skips to matching RParen
  if self.token != LParen {
    return
  }
  let mut depth = 1
  self.advance()
  while depth > 0 && self.token != EOF {
    if self.token == LParen {
      depth += 1
    } else if self.token == RParen {
      depth -= 1
    }
    if depth > 0 {
      self.advance()
    } else {
      self.advance()
      break
    }
  }
}

///|
fn Parser::skip_balanced_braces(self : Parser) -> Unit {
  // Assumes current token is LBrace, skips to matching RBrace
  if self.token != LBrace {
    return
  }
  let mut depth = 1
  self.advance()
  while depth > 0 && self.token != EOF {
    if self.token == LBrace {
      depth += 1
    } else if self.token == RBrace {
      depth -= 1
    }
    if depth > 0 {
      self.advance()
    } else {
      self.advance()
      break
    }
  }
}

///|
fn Parser::skip_balanced_brackets(self : Parser) -> Unit {
  // Assumes current token is LBracket, skips to matching RBracket
  if self.token != LBracket {
    return
  }
  let mut depth = 1
  self.advance()
  while depth > 0 && self.token != EOF {
    if self.token == LBracket {
      depth += 1
    } else if self.token == RBracket {
      depth -= 1
    }
    if depth > 0 {
      self.advance()
    } else {
      self.advance()
      break
    }
  }
}

///|
/// Parses one complete, already preprocessed C translation unit.
///
/// The parser does not run a C preprocessor. Invalid or unsupported syntax
/// aborts instead of returning a structured error value.
pub fn parse(input : String) -> Program {
  let lexer = Lexer::new(input)
  let parser = Parser::new(lexer)
  parser.parse_program()
}

///|
fn Parser::remember_value_type(self : Parser, name : String, ty : Type) -> Unit {
  if name != "" {
    self.value_types[name] = ty
  }
}
