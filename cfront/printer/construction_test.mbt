///|
/// Building an AST by hand and printing it is the suite's other direction, and
/// the one a meta-programming user actually touches. These tests construct
/// programs with no parser involved, print them, and then parse the result --
/// so they fail both when the printer emits something wrong and when it emits
/// something no C compiler would accept.
fn parses_back(source : String) -> @parser.Program raise @parser.ParseError {
  @parser.parse(source)
}

///|
/// Several names declared at once are several statements, so generating them
/// is pushing to an array rather than building a grouping node whose spelling
/// a generator would have to learn.
test "generated sibling declarations print as C" {
  let body : Array[@parser.Stmt] = [
    VarDecl(SInt, "a", Some(@parser.int_literal(1, SInt))),
    VarDecl(Pointer(SInt), "p", Some(AddrOf(Var("a")))),
    VarDecl(Array(SChar, 4), "buf", Some(String("hi"))),
    Return(Some(Deref(Var("p")))),
  ]
  let program : @parser.Program = {
    structs: [],
    globals: [],
    decls: [
      {
        ret: SInt,
        name: "generated",
        params: [],
        variadic: false,
        is_static: false,
        is_inline: false,
        is_weak: false,
        visibility: None,
        symbol_alias: None,
        section: None,
        is_constructor: false,
        is_destructor: false,
        body: Some(Compound(body)),
      },
    ],
  }
  let printed = @printer.print_program(program)
  inspect(
    printed,
    content=(
      #|int generated(void) {
      #|  int a = 1;
      #|  int *p = &a;
      #|  char buf[4] = "hi";
      #|  return *p;
      #|}
      #|
      #|
    ),
  )
  // What was generated is C, not merely text that resembles it.
  let reparsed = parses_back(printed)
  assert_eq(reparsed.decls.length(), 1)
  assert_eq(@printer.print_program(reparsed), printed)
}

///|
/// A `for` initializer is the one place C insists several names share a
/// specifier, so the printer rejoins what the AST keeps apart. A generator
/// builds the same `VarDecl`s it would build anywhere else.
test "generated for-init declarations rejoin into one declaration" {
  let for_stmt : @parser.Stmt = For(
    [
      VarDecl(SInt, "i", Some(@parser.int_literal(0, SInt))),
      VarDecl(SInt, "n", Some(@parser.int_literal(8, SInt))),
    ],
    Binary("<", Var("i"), Var("n")),
    Some(PostfixInc(Var("i"))),
    ExprStmt(Call(Var("use"), [Var("i")])),
  )
  inspect(
    @printer.print_stmt(for_stmt),
    content=(
      #|for (int i = 0, n = 8; i < n; i++) 
      #|  use(i);
    ),
  )
}

///|
/// The specifier is shared but the declarators need not match: `int i = 0, *p`
/// is one declaration of two different types, and splitting the declaration is
/// what lets that print correctly rather than as `int i = 0, int *p`.
test "generated for-init shares a specifier across unlike declarators" {
  let for_stmt : @parser.Stmt = For(
    [
      VarDecl(SInt, "i", Some(@parser.int_literal(0, SInt))),
      VarDecl(Pointer(SInt), "p", Some(Var("head"))),
      VarDecl(Array(SInt, 2), "pair", None),
    ],
    Var("p"),
    None,
    Break,
  )
  inspect(
    @printer.print_stmt(for_stmt),
    content=(
      #|for (int i = 0, *p = head, pair[2]; p;) 
      #|  break;
    ),
  )
}

///|
/// An empty initializer is an empty list, so no special node is needed for a
/// `for` without one. The condition still prints, since the AST has no way to
/// say "absent" for it -- `for (;;)` parses as a truthy constant, which is the
/// separate gap noted on `Stmt`.
test "generated for with no initializer prints an empty init clause" {
  let for_stmt : @parser.Stmt = For(
    [],
    @parser.int_literal(1, SInt),
    None,
    Break,
  )
  inspect(
    @printer.print_stmt(for_stmt),
    content=(
      #|for (; 1;) 
      #|  break;
    ),
  )
}

///|
/// Expressions in a `for` initializer join with the comma operator, which is
/// the other thing C accepts in that clause.
test "generated for-init expressions join with commas" {
  let for_stmt : @parser.Stmt = For(
    [
      ExprStmt(Assign(Var("i"), @parser.int_literal(0, SInt))),
      ExprStmt(Assign(Var("j"), Var("n"))),
    ],
    Binary("<", Var("i"), Var("j")),
    Some(PostfixInc(Var("i"))),
    Break,
  )
  inspect(
    @printer.print_stmt(for_stmt),
    content=(
      #|for (i = 0, j = n; i < j; i++) 
      #|  break;
    ),
  )
}
