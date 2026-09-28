///|
/// Properties of `@preprocessor.preprocess`, judged at the token level: the
/// preprocessor may respace its output freely, so text is compared by the
/// token sequence `@parser.Lexer` reads from it.

///|
/// The C tokens of `text`, or `None` when the lexer rejects it.
fn lex_all(text : String) -> Array[@parser.Token]? {
  let lexer = @parser.Lexer::new(text)
  let tokens : Array[@parser.Token] = []
  while true {
    let token = lexer.next_token() catch { _ => return None }
    if token is EOF {
      break
    }
    tokens.push(token)
  }
  Some(tokens)
}

///|
/// Whether `tokens` has a `.` followed by a token that starts with `.` --
/// another `.`, or a number like `.5`. C reads `..` and `..5` as two
/// tokens, so the preprocessor may write them adjacent; `@parser.Lexer`
/// rejects `..` outright. No C production puts either pair in a row, so the
/// difference cannot matter to valid input, and the properties skip it.
fn has_dot_pair(tokens : Array[@parser.Token]) -> Bool {
  for i in 1..<tokens.length() {
    if tokens[i - 1] is Dot &&
      (
        tokens[i] is Dot ||
        (tokens[i] is FloatLiteral(text, _) && text.has_prefix("."))
      ) {
      return true
    }
  }
  false
}

///|
fn pp(text : String) -> String? {
  match
    @preprocessor.preprocess(text, @preprocessor.PreprocessOptions::new("qc.c")) {
    Ok(out) => Some(out)
    Err(_) => None
  }
}

///|
/// Tokens that are never macros: identifiers from a pool no header defines,
/// keywords, every punctuator, and literals of each kind. `L`, `u` and `U`
/// are there because gluing one to a following quote makes a wide literal.
let pp_vocab : ReadOnlyArray[String] = [
  "a", "b", "xy", "L", "u", "U", "u8", "int", "return", "0", "1", "42", "1.5", "0x1f",
  "1e5", "7u", "\"s\"", "\"a b\"", "\"q\\\"x\"", "'c'", "'\\n'", "+", "-", "*", "/",
  "%", "++", "--", "+=", "-=", "<", "<<", "<=", ">", ">>", ">=", "=", "==", "!=",
  "!", "~", "&", "&&", "|", "||", "^", "?", ":", ";", ",", ".", "->", "...", "(",
  ")", "[", "]", "{", "}",
]

///|
/// Separators, including none at all and both comment forms.
let pp_separators : ReadOnlyArray[String] = [
  " ", " ", " ", "", "\t", "\n", " /* c */ ", "// c\n", "\n\n",
]

///|
/// A list of vocabulary tokens, rendered two ways by the properties.
struct PpTokens(Array[String])

///|
impl @quickcheck.Arbitrary for PpTokens with fn arbitrary(size, state) {
  let tokens : Array[String] = []
  for _ in 0..<pick(state, size + 1) {
    tokens.push(pp_vocab[pick(state, pp_vocab.length())])
  }
  PpTokens(tokens)
}

///|
impl @shrink.Shrink for PpTokens with fn shrink(self) {
  let out : Array[PpTokens] = []
  for i in 0..<self.0.length() {
    let fewer = self.0.copy()
    let _ = fewer.remove(i)
    out.push(PpTokens(fewer))
  }
  out.iter()
}

///|
impl @debug.Debug for PpTokens with fn to_repr(self) {
  Repr(@debug.to_string(self.0))
}

///|
/// `tokens` joined by separators chosen by a seeded walk, so the same input
/// always renders the same text.
fn pp_join(tokens : Array[String], seed : Int) -> String {
  let buf = StringBuilder()
  let state = @splitmix.new(seed=seed.to_uint64())
  for i, token in tokens {
    if i > 0 {
      buf.write_string(pp_separators[pick(state, pp_separators.length())])
    }
    buf.write_string(token)
  }
  buf.write_string("\n")
  buf.to_string()
}

///|
/// Text with no directives and no macro names preprocesses to the same
/// tokens: expansion is the identity on it, and the respacing never glues
/// two tokens into one (`- -` into `--`, `L "s"` into `L"s"`) or splits one.
test "preprocessing macro-free text preserves its tokens" {
  @quickcheck.check(
    (input : (PpTokens, Int)) => {
      let (tokens, seed) = input
      let text = pp_join(tokens.0, seed)
      match lex_all(text) {
        None => true
        Some(expected) if has_dot_pair(expected) => true
        Some(expected) =>
          match pp(text) {
            Some(out) => lex_all(out) == Some(expected)
            None => false
          }
      }
    },
    count=1500,
    max_size=24,
    seed=5150,
  )
}

///|
/// Lines a disabled group may hold: text, directives that would matter if
/// the group were live, a balanced nested conditional, and prose with an
/// apostrophe -- the `#if 0` comment idiom.
let skipped_lines : ReadOnlyArray[String] = [
  "a b c", "#define a 99", "#undef xy", "#include \"no_such_header.h\"", "#error never",
  "#if 1\nb\n#else\nc\n#endif", "#ifdef a\n#endif", "#pragma once", "don't touch this",
  "\"unterminated", "#line 12", "int x = 1;", "#", "# 7 \"f.c\"", "#elif_not_a_directive",
]

///|
struct SkippedGroup(Array[Int])

///|
impl @quickcheck.Arbitrary for SkippedGroup with fn arbitrary(size, state) {
  let lines : Array[Int] = []
  for _ in 0..<pick(state, size + 1) {
    lines.push(pick(state, skipped_lines.length()))
  }
  SkippedGroup(lines)
}

///|
impl @shrink.Shrink for SkippedGroup with fn shrink(self) {
  let out : Array[SkippedGroup] = []
  for i in 0..<self.0.length() {
    let fewer = self.0.copy()
    let _ = fewer.remove(i)
    out.push(SkippedGroup(fewer))
  }
  out.iter()
}

///|
impl @debug.Debug for SkippedGroup with fn to_repr(self) {
  Repr(self.0.map(i => skipped_lines[i]).join("\n").escape())
}

///|
/// An `#if 0` group vanishes: the text around it preprocesses to the same
/// tokens with or without the group, whatever the group contains.
test "an #if 0 group vanishes" {
  @quickcheck.check(
    (input : (PpTokens, SkippedGroup, PpTokens)) => {
      let (before, group, after) = input
      let head = pp_join(before.0, 1)
      let tail = pp_join(after.0, 2)
      let body = group.0.map(i => skipped_lines[i]).join("\n")
      let with_group = head + "#if 0\n" + body + "\n#endif\n" + tail
      match pp(head + tail) {
        None => true
        Some(without) =>
          match pp(with_group) {
            Some(out) => lex_all(out) == lex_all(without)
            None => false
          }
      }
    },
    count=800,
    max_size=10,
    seed=6174,
  )
}

///|
/// An object-like macro expands to its replacement list, token for token,
/// wherever it appears -- including next to tokens its replacement could
/// glue with.
test "an object-like macro expands to its replacement tokens" {
  @quickcheck.check(
    (input : (PpTokens, PpTokens, UInt)) => {
      let (body, text, every) = input
      // Every `every % 3 + 1`-th token of the text becomes the macro name.
      let stride = (every % 3).reinterpret_as_int() + 1
      let items = text.0.mapi((i, t) => if i % stride == 0 { "MQ" } else { t })
      let source = "#define MQ " +
        body.0.join(" ") +
        "\n" +
        items.join(" ") +
        "\n"
      // The expectation is the text with the name replaced by the
      // replacement list, every token space-separated -- lexed as a whole,
      // since adjacent string literals join.
      let substituted = items.map(item => {
        if item == "MQ" {
          body.0.join(" ")
        } else {
          item
        }
      })
      guard lex_all(substituted.join(" ")) is Some(expected) else {
        return true
      }
      if has_dot_pair(expected) {
        return true
      }
      match pp(source) {
        Some(out) => lex_all(out) == Some(expected)
        None => false
      }
    },
    count=1000,
    max_size=12,
    seed=1729,
  )
}

///|
/// A function-like macro substitutes its argument: `W(arg)` with
/// `#define W(p) [ p ]` is `[`, the argument's tokens, `]`.
test "a function-like macro substitutes its argument" {
  @quickcheck.check(
    (arg : PpTokens) => {
      // A macro argument ends at an unbalanced `)` or a top-level `,`.
      let plain = arg.0.filter(t => !(t is ("(" | ")" | ",")))
      let source = "#define W(p) [ p ]\nW(" + plain.join(" ") + ")\n"
      guard lex_all("[ " + plain.join(" ") + " ]") is Some(expected) else {
        return true
      }
      if has_dot_pair(expected) {
        return true
      }
      match pp(source) {
        Some(out) => lex_all(out) == Some(expected)
        None => false
      }
    },
    count=800,
    max_size=12,
    seed=4104,
  )
}

///|
/// Arbitrary line soups -- directives with garbage operands, unbalanced
/// conditionals, macro definitions that use themselves -- preprocess to a
/// result or an error, never an abort.
test "the preprocessor returns a result on arbitrary directive soups" {
  let lines : ReadOnlyArray[String] = [
    "#define A A", "#define B(x) B(x) x", "#define C(x, ...) #x __VA_ARGS__ ## x",
    "#undef A", "#if", "#if A", "#if (1", "#if 1 +", "#if 1/0", "#if 1 ? 2", "#elif 1",
    "#else", "#endif", "#ifdef", "#ifndef B", "#include", "#include <", "#include \"",
    "#line", "#line x", "#pragma pack(push, 2)", "#error", "#", "##", "A B(1) C(2, 3)",
    "B(", "B(1, 2", "C()", "__LINE__ __FILE__ __COUNTER__", "defined(A)", "'", "\"",
    "/*", "\\", "\u{1F600}",
  ]
  @quickcheck.check(
    (picks : Array[UInt]) => {
      let text = picks
        .map(i => {
          lines[(i % lines.length().reinterpret_as_uint()).reinterpret_as_int()]
        })
        .join("\n")
      let _ = pp(text)
      true
    },
    count=1500,
    max_size=16,
    seed=3141,
  )
}
