///|
/// Properties over the syntax-directed generator in `syntax_gen_test.mbt`:
/// the print/parse round trip over the whole grammar, the precedence
/// contract of the expression printer, declarator spelling, and parser
/// robustness.

///|
/// The outermost form of an expression, for the coverage labels the
/// expression round-trip property prints.
fn expr_kind(expr : @parser.Expr) -> String {
  match expr {
    Number(_, _, _) | FloatLiteral(_, _) | String(_) => "literal"
    Var(_) => "var"
    Binary(",", _, _) => "comma"
    Binary(_, _, _) => "binary"
    Unary(_, _) | Deref(_) | AddrOf(_) | PrefixInc(_) | PrefixDec(_) => "unary"
    Sizeof(_) | SizeofExpr(_) | Alignof(_) | AlignofExpr(_) => "sizeof/alignof"
    Cast(_, _) => "cast"
    Call(_, _)
    | ArrayAccess(_, _)
    | MemberAccess(_, _)
    | PostfixInc(_)
    | PostfixDec(_)
    | VaArg(_, _)
    | OffsetOf(_, _) => "postfix"
    Assign(_, _) | CompoundAssign(_, _, _) => "assign"
    Ternary(_, _, _) => "ternary"
    _ => "other"
  }
}

///|
/// Whole programs over the full grammar survive print and parse, and the
/// printed text is a fixed point. Named types are registered for the
/// reparse, as `gen_test.mbt` documents.
test "syntax programs round-trip through print and parse" {
  @quickcheck.check(
    (p : SynProgram) => {
      let printed = @printer.print_program(p.0)
      let reparsed = @parser.parse_with_named_types(printed, named_type_pool)
      reparsed == p.0 && @printer.print_program(reparsed) == printed
    },
    observe=p => program_features(p.0).map(f => @quickcheck.classify(true, f)),
    count=400,
    max_size=10,
    seed=20260928,
  )
}

///|
/// The constructs a program exercises, for the coverage table the
/// round-trip property prints: each statement form, and the declarator
/// shapes that need parentheses or a type-name spelling.
fn program_features(program : @parser.Program) -> Array[String] {
  let seen : Map[String, Bool] = Map([])
  fn note_type(ty : @ctype.Type) -> Unit {
    match ty {
      Pointer(Array(_, _) as inner) => {
        seen["type: pointer to array"] = true
        note_type(inner)
      }
      Pointer(FuncPtr(_, _, _) as inner) => {
        seen["type: pointer to function pointer"] = true
        note_type(inner)
      }
      FuncPtr(FuncPtr(_, _, _) | Pointer(_) as ret, params, _) => {
        seen["type: function pointer returning pointer"] = true
        note_type(ret)
        params.each(note_type)
      }
      FuncPtr(ret, params, _) => {
        seen["type: function pointer"] = true
        note_type(ret)
        params.each(note_type)
      }
      Array(inner, _) => {
        seen["type: array"] = true
        note_type(inner)
      }
      Atomic(Pointer(_) as inner) => {
        seen["type: atomic pointer"] = true
        note_type(inner)
      }
      Pointer(inner) | Atomic(inner) | Aligned(inner, _) => note_type(inner)
      _ => ()
    }
  }

  fn note_stmt(stmt : @parser.Stmt) -> Unit {
    match stmt {
      If(_, t, e) => {
        seen["stmt: if"] = true
        note_stmt(t)
        if e is Some(alternative) {
          note_stmt(alternative)
        }
      }
      While(_, b) => {
        seen["stmt: while"] = true
        note_stmt(b)
      }
      DoWhile(_, b) => {
        seen["stmt: do-while"] = true
        note_stmt(b)
      }
      For(init, _, _, b) => {
        seen["stmt: for"] = true
        init.each(note_stmt)
        note_stmt(b)
      }
      Switch(_, b) => {
        seen["stmt: switch"] = true
        note_stmt(b)
      }
      Case(_, b) | Default(b) => {
        seen["stmt: case/default"] = true
        note_stmt(b)
      }
      Label(_, b) => {
        seen["stmt: label"] = true
        note_stmt(b)
      }
      Goto(_) | ComputedGoto(_) => seen["stmt: goto"] = true
      Compound(body) => body.each(note_stmt)
      VarDecl(ty, _, _) => {
        seen["stmt: declaration"] = true
        note_type(ty)
      }
      _ => ()
    }
  }

  for global in program.globals {
    note_type(global.ty)
  }
  for decl in program.decls {
    note_type(decl.ret)
    if decl.ret is (FuncPtr(_, _, _) | Pointer(Array(_, _))) {
      seen["function returning function or array pointer"] = true
    }
    for param in decl.params {
      note_type(param.ty)
    }
    if decl.body is Some(body) {
      note_stmt(body)
    }
  }
  seen.keys().collect()
}

///|
/// The same property under a second seed.
test "syntax programs round-trip under a second seed" {
  @quickcheck.check(
    (p : SynProgram) => {
      let printed = @printer.print_program(p.0)
      let reparsed = @parser.parse_with_named_types(printed, named_type_pool)
      reparsed == p.0 && @printer.print_program(reparsed) == printed
    },
    count=400,
    max_size=10,
    seed=77,
  )
}

///|
/// Expression printing inserts enough parentheses: the printed text parses
/// back to the same tree, whatever the nesting of precedence levels and
/// associativity. And the printed form is a fixed point.
test "printed expressions reparse to the same tree" {
  @quickcheck.check(
    (e : SynExpr) => {
      let printed = @printer.print_expr(e.0)
      match reparse_expr(printed) {
        Some(back) => back == e.0 && @printer.print_expr(back) == printed
        None => false
      }
    },
    filter=e => in_parser_image(e.0),
    observe=e => [@quickcheck.label(expr_kind(e.0))],
    count=2000,
    max_size=6,
    seed=1928,
  )
}

///|
/// Every matched pair of parentheses in `text`, as (open, close) offsets.
fn paren_pairs(text : String) -> Array[(Int, Int)] {
  let pairs = []
  let stack : Array[Int] = []
  let mut in_quote : Char? = None
  let mut i = 0
  while i < text.length() {
    let ch = text[i].to_int().unsafe_to_char()
    match in_quote {
      Some(q) => if ch == '\\' { i += 1 } else if ch == q { in_quote = None }
      None =>
        if ch == '"' || ch == '\'' {
          in_quote = Some(ch)
        } else if ch == '(' {
          stack.push(i)
        } else if ch == ')' {
          match stack.pop() {
            Some(open) => pairs.push((open, i))
            None => ()
          }
        }
    }
    i += 1
  }
  pairs
}

///|
/// Whether `expr` puts a postfix operator where C would reject it bare but
/// this parser accepts it, so minimality judged against the parser would
/// demand invalid C:
///
/// - on a `&&label`: GNU C makes `&&label` a unary expression, so `(&&l).f`
///   needs its parentheses, but the parser reads `&&l.f` as the same tree;
/// - on a cast whose operand ends in `sizeof(type)`, `_Alignof(...)` or
///   `&&label` -- forms that take no postfix operator of their own: the
///   parser binds a trailing postfix to the cast itself, so it reads
///   `(int)sizeof(int)[a]` as `((int)sizeof(int))[a]`.
///
/// Every such tree is also meaningless, a postfix applied to an rvalue
/// that is not an array, pointer or function.
fn lax_postfix(expr : @parser.Expr) -> Bool {
  fn takes_no_postfix(e : @parser.Expr) -> Bool {
    match e {
      Sizeof(_) | Alignof(_) | AlignofExpr(_) | LabelAddr(_) => true
      Unary(_, x)
      | Deref(x)
      | AddrOf(x)
      | Cast(_, x)
      | PrefixInc(x)
      | PrefixDec(x) => takes_no_postfix(x)
      _ => false
    }
  }

  fn lax_base(e : @parser.Expr) -> Bool {
    match e {
      LabelAddr(_) | Deref(LabelAddr(_)) => true
      Cast(_, x) | Deref(Cast(_, x)) => takes_no_postfix(x)
      _ => false
    }
  }

  match expr {
    MemberAccess(base, _)
    | ArrayAccess(base, _)
    | Call(base, _)
    | PostfixInc(base)
    | PostfixDec(base) if lax_base(base) => true
    _ => lax_postfix_within(expr)
  }
}

///|
fn lax_postfix_within(expr : @parser.Expr) -> Bool {
  match expr {
    Binary(_, a, b)
    | ArrayAccess(a, b)
    | Assign(a, b)
    | CompoundAssign(_, a, b) => lax_postfix(a) || lax_postfix(b)
    Unary(_, e)
    | Deref(e)
    | AddrOf(e)
    | SizeofExpr(e)
    | AlignofExpr(e)
    | Cast(_, e)
    | MemberAccess(e, _)
    | VaArg(e, _)
    | PrefixInc(e)
    | PrefixDec(e)
    | PostfixInc(e)
    | PostfixDec(e) => lax_postfix(e)
    Call(callee, args) => lax_postfix(callee) || args.iter().any(lax_postfix)
    Ternary(c, t, e) => lax_postfix(c) || lax_postfix(t) || lax_postfix(e)
    _ => false
  }
}

///|
/// `expr` with every derived type flattened to `int`. Type names are atoms
/// to expression precedence; flattening them keeps the parentheses in the
/// printed text to the expression-level ones the next property is about.
/// (Declarators have their own, looser rule: `Pointer(FuncPtr(..))` prints
/// as `int (*(*x))(void)`, redundant but valid.)
fn flatten_types(expr : @parser.Expr) -> @parser.Expr {
  fn flat(ty : @ctype.Type) -> @ctype.Type {
    match ty {
      Pointer(_) | Array(_, _) | FuncPtr(_, _, _) | Atomic(_) | Aligned(_, _) =>
        SInt
      other => other
    }
  }

  match expr {
    Sizeof(ty) => Sizeof(flat(ty))
    Alignof(ty) => Alignof(flat(ty))
    Cast(ty, e) => Cast(flat(ty), flatten_types(e))
    VaArg(e, ty) => VaArg(flatten_types(e), flat(ty))
    Binary(op, a, b) => Binary(op, flatten_types(a), flatten_types(b))
    ArrayAccess(a, b) => ArrayAccess(flatten_types(a), flatten_types(b))
    Assign(a, b) => Assign(flatten_types(a), flatten_types(b))
    CompoundAssign(op, a, b) =>
      CompoundAssign(op, flatten_types(a), flatten_types(b))
    Unary(op, e) => Unary(op, flatten_types(e))
    Deref(e) => Deref(flatten_types(e))
    AddrOf(e) => AddrOf(flatten_types(e))
    SizeofExpr(e) => SizeofExpr(flatten_types(e))
    AlignofExpr(e) => AlignofExpr(flatten_types(e))
    MemberAccess(e, f) => MemberAccess(flatten_types(e), f)
    PrefixInc(e) => PrefixInc(flatten_types(e))
    PrefixDec(e) => PrefixDec(flatten_types(e))
    PostfixInc(e) => PostfixInc(flatten_types(e))
    PostfixDec(e) => PostfixDec(flatten_types(e))
    Call(callee, args) => Call(flatten_types(callee), args.map(flatten_types))
    Ternary(c, t, e) =>
      Ternary(flatten_types(c), flatten_types(t), flatten_types(e))
    other => other
  }
}

///|
/// ...and no more than needed: deleting any one pair of parentheses from the
/// printed text yields text that either does not parse or parses to a
/// different tree. Grouping parentheses the printer emits are therefore all
/// load-bearing; the ones that belong to syntax (calls, casts) fail
/// trivially, since removing them changes the tokens. The exception is the
/// operand parentheses of `sizeof(...)` and `_Alignof(...)`, which the
/// printer writes on purpose for every operand; those are skipped.
test "printed expressions carry no redundant parentheses" {
  @quickcheck.check(
    (e : SynExpr) => {
      let expr = flatten_types(e.0)
      let printed = @printer.print_expr(expr)
      for pair in paren_pairs(printed) {
        let (open, close) = pair
        let before = printed[0:open]
        if before.has_suffix("sizeof") || before.has_suffix("_Alignof") {
          continue
        }
        let stripped = printed[0:open].to_owned() +
          printed[open + 1:close].to_owned() +
          printed[close + 1:].to_owned()
        if reparse_expr(stripped) is Some(back) && back == expr {
          return false
        }
      }
      true
    },
    filter=e => in_parser_image(e.0) && !lax_postfix(e.0),
    count=600,
    max_size=5,
    seed=31,
  )
}

///|
/// A declaration printed by `print_declaration` parses back to the type it
/// was printed from: pointers, arrays, function pointers and `_Atomic` in
/// any nesting.
test "declarations reparse to the declared type" {
  @quickcheck.check(
    (t : SynType) => {
      let program : @parser.Program = {
        structs: fixed_aggregates(),
        globals: [
          {
            ty: t.0,
            name: "x",
            init: None,
            is_static: false,
            is_extern: false,
            is_weak: false,
            visibility: None,
            symbol_alias: None,
            section: None,
          },
        ],
        decls: [],
        items: [Aggregate(0), Aggregate(1), Global(0)],
      }
      let reparsed = @parser.parse_with_named_types(
        @printer.print_program(program),
        named_type_pool,
      )
      reparsed.globals.length() == 1 && reparsed.globals[0].ty == t.0
    },
    count=1000,
    max_size=5,
    seed=4096,
  )
}

///|
/// The abstract spelling `print_type` gives a type is what `sizeof` reads
/// back as that type.
test "abstract type names reparse under sizeof" {
  @quickcheck.check(
    (t : SynType) => {
      reparse_expr(@printer.print_expr(Sizeof(t.0))) == Some(Sizeof(t.0))
    },
    count=1000,
    max_size=5,
    seed=8192,
  )
}

///|
/// `split_declaration` and `print_declaration` agree: the shared specifier,
/// a space, and the per-name declarator are the whole declaration; the
/// declarator names the declared identifier exactly once; and `print_type`
/// is the declaration of the empty name.
test "split declarations rejoin to the full declaration" {
  @quickcheck.check(
    (t : SynType) => {
      let (specifier, declarator) = @printer.split_declaration(t.0, "zz9")
      let full = @printer.print_declaration(t.0, "zz9")
      let occurrences = declarator.split("zz9").count() - 1
      specifier + " " + declarator == full &&
      occurrences == 1 &&
      @printer.print_type(t.0) == @printer.print_declaration(t.0, "")
    },
    count=1000,
    max_size=5,
    seed=16384,
  )
}

///|
/// A token soup: C tokens from every lexical class, in random order, with no
/// grammar at all.
struct TokenSoup(String)

///|
let soup_tokens : ReadOnlyArray[String] = [
  "int", "char", "void", "struct", "union", "enum", "typedef", "static", "extern",
  "const", "unsigned", "long", "short", "double", "float", "_Bool", "_Atomic", "_Alignas",
  "__int128", "if", "else", "while", "do", "for", "switch", "case", "default", "break",
  "continue", "goto", "return", "sizeof", "_Alignof", "__attribute__", "__builtin_va_arg",
  "__builtin_offsetof", "_Generic", "_Static_assert", "__typeof__", "asm", "x", "y",
  "S", "f", "0", "1", "0x", "0x1p", "09", "1e", "1.5f", "42uLL", "'a'", "'", "\"s\"",
  "\"", "(", ")", "[", "]", "{", "}", ";", ",", ":", "?", ".", "->", "...", "..",
  "*", "&", "&&", "|", "||", "^", "~", "!", "=", "==", "!=", "<", "<=", "<<", ">",
  ">>=", "+", "++", "-", "--", "/", "%", "+=", "#", "#pragma pack(", "\\", "@", "$",
  "`", "/*", "//", "\n", "\u{e9}", "\u{1F600}",
]

///|
impl @quickcheck.Arbitrary for TokenSoup with fn arbitrary(size, state) {
  let buf = StringBuilder()
  let n = pick(state, 4 * size + 1)
  for i in 0..<n {
    if i > 0 && pick(state, 3) != 0 {
      buf.write_char(' ')
    }
    buf.write_string(soup_tokens[pick(state, soup_tokens.length())])
  }
  TokenSoup(buf.to_string())
}

///|
impl @shrink.Shrink for TokenSoup with fn shrink(self) {
  let text = self.0
  let out : Array[TokenSoup] = []
  let half = text.length() / 2
  if half > 0 {
    out.push(TokenSoup(text[0:half].to_owned()))
    out.push(TokenSoup(text[half:].to_owned()))
  }
  if text.length() > 0 {
    out.push(TokenSoup(text[0:text.length() - 1].to_owned()))
    out.push(TokenSoup(text[1:].to_owned()))
  }
  out.iter()
}

///|
impl @debug.Debug for TokenSoup with fn to_repr(self) {
  Repr(self.0.escape())
}

///|
/// The parser's documented recovery contract (see `parser/error_test.mbt`):
/// any input either parses or raises `ParseError` -- it never aborts. A
/// panic here fails the whole test binary rather than one case, so the
/// soup is kept small enough that the first crash is easy to read off.
test "the parser returns or raises on arbitrary token soups" {
  @quickcheck.check(
    (soup : TokenSoup) => {
      let _ = @parser.parse(soup.0) catch { _ => @parser.parse("") }
      true
    },
    count=3000,
    max_size=40,
    seed=99,
  )
}

///|
/// The same contract on near-miss programs: a printed generated program
/// with one token-sized slice deleted. These stay close to valid C, so the
/// parser gets deep into its productions before the damage shows.
test "the parser returns or raises on damaged printed programs" {
  @quickcheck.check(
    (input : (SynProgram, UInt, UInt)) => {
      let (p, at, len) = input
      let printed = @printer.print_program(p.0)
      let start = (at % (printed.length().reinterpret_as_uint() + 1)).reinterpret_as_int()
      let wanted = start + (len % 8).reinterpret_as_int()
      let stop = if wanted > printed.length() {
        printed.length()
      } else {
        wanted
      }
      let damaged = printed[0:start].to_owned() + printed[stop:].to_owned()
      let _ = @parser.parse_with_named_types(damaged, named_type_pool) catch {
        _ => @parser.parse("")
      }
      true
    },
    count=600,
    max_size=8,
    seed=2718,
  )
}

///|
/// Any string, printed as a literal and read back, is the literal whose
/// value is its execution bytes: bytes 0-255 as themselves (escaped where
/// needed) and characters above 0xff as their UTF-8 encoding. The printer
/// writes the latter verbatim, and the lexer stores their UTF-8 bytes.
test "printed string literals reparse to their execution bytes" {
  @quickcheck.check(
    (text : String) => {
      reparse_expr(@printer.print_expr(String(text))) ==
      Some(String(execution_bytes(text)))
    },
    filter=text => text.iter().all(ch => !(ch.to_int() is (0xD800..=0xDFFF))),
    observe=text => {
      [
        @quickcheck.classify(text.iter().any(ch => ch.to_int() > 0xff), "wide"),
        @quickcheck.classify(
          text.iter().any(ch => ch.to_int() > 0xffff),
          "astral",
        ),
      ]
    },
    count=1000,
    max_size=24,
    seed=6502,
  )
}
