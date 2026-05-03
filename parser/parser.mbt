///|
pub struct Parser {
  lexer : Lexer
  mut token : Token
  typedefs : Map[String, Type]
  anonymous_structs : Array[StructDecl]
  mut anon_counter : Int
  enum_constants : Map[String, Int]
  globals : Array[(Type, String)]
}

///|
pub fn Parser::new(lexer : Lexer) -> Parser {
  let p = { lexer, token: EOF, typedefs: {}, anonymous_structs: [], anon_counter: 0, enum_constants: {}, globals: [] }
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
pub fn parse(input : String) -> Program {
  let lexer = Lexer::new(input)
  let parser = Parser::new(lexer)
  parser.parse_program()
}
