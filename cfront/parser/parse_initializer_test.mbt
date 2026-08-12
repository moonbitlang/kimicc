///|
/// Parses one function body and returns its statements.
fn initializer_body_stmts(source : String) -> Array[@parser.Stmt] raise {
  let program = @parser.parse(source)
  guard program.decls[0].body is Some(Compound(stmts)) else {
    fail("expected a function body")
  }
  stmts
}

///|
/// A local brace initializer is one declaration, not a zeroed declaration
/// followed by element assignments.
///
/// The old shape had no printable form and no constructible one: a user
/// emitting `int a[3] = {1, 2, 3}` had to know to write four statements, the
/// first of which said `= 0` and meant "zero the whole object".
test "a local array initializer is recorded as one declaration" {
  let stmts = initializer_body_stmts(
    "int f(void) { int a[5] = {1, 2, 3}; return a[0]; }",
  )
  guard stmts[0]
    is VarDecl(
      Array(SInt, 5),
      "a",
      Some(Array([Number(1, _, _), Number(2, _, _), Number(3, _, _)]))
    ) else {
    fail("expected the braces to be recorded: \{Repr(stmts[0])}")
  }
  assert_eq(stmts.length(), 2)
}

///|
/// Struct and union initializers keep their designators, in the order and the
/// nesting they were written with.
test "aggregate initializers keep designators and nesting" {
  let source =
    #|struct P { int x; int y; };
    #|struct Nest { struct P p; int tail; };
    #|int f(void) {
    #|  struct P designated = { .y = 5 };
    #|  struct Nest deep = { .p = { .y = 7 }, .tail = 3 };
    #|  int ranged[6] = { [1 ... 3] = 9 };
    #|  return designated.y + deep.tail + ranged[1];
    #|}
  let stmts = initializer_body_stmts(source)
  guard stmts[0]
    is VarDecl(
      Struct("P"),
      "designated",
      Some(Array([DesignatedField("y", Number(5, _, _))]))
    ) else {
    fail("expected a designated field: \{Repr(stmts[0])}")
  }
  guard stmts[1]
    is VarDecl(
      Struct("Nest"),
      "deep",
      Some(
        Array(
          [
            DesignatedField("p", Array([DesignatedField("y", Number(7, _, _))])),
            DesignatedField("tail", Number(3, _, _)),
          ]
        )
      )
    ) else {
    fail("expected nested designators: \{Repr(stmts[1])}")
  }
  guard stmts[2]
    is VarDecl(
      Array(SInt, 6),
      "ranged",
      Some(Array([DesignatedRange(1, 3, Number(9, _, _))]))
    ) else {
    fail("expected a designated range: \{Repr(stmts[2])}")
  }
}

///|
/// The one thing the parser still decides is the size the braces imply, since
/// the size is part of the type the declaration carries. A designator counts
/// toward it, and an explicit size wins over the element count.
test "array size inference survives, and only that" {
  let source =
    #|int f(void) {
    #|  int inferred[] = { 1, 2, 3 };
    #|  int from_designator[] = { [4] = 1 };
    #|  int explicit[9] = { 1, 2 };
    #|  return inferred[0] + from_designator[4] + explicit[0];
    #|}
  let stmts = initializer_body_stmts(source)
  guard stmts[0] is VarDecl(Array(SInt, 3), "inferred", _) else {
    fail("expected size 3 from three elements: \{Repr(stmts[0])}")
  }
  guard stmts[1] is VarDecl(Array(SInt, 5), "from_designator", _) else {
    fail("expected size 5 from `[4]`: \{Repr(stmts[1])}")
  }
  guard stmts[2] is VarDecl(Array(SInt, 9), "explicit", _) else {
    fail("expected the written size to win: \{Repr(stmts[2])}")
  }
}

///|
/// A string initializing a `char` array stays the string that was written.
/// Sizing still happens here, and an explicit size is left alone whether it
/// leaves room for the terminator or not.
test "a char array keeps the string it was initialized with" {
  let source =
    #|int f(void) {
    #|  char inferred[] = "abc";
    #|  char padded[8] = "hi";
    #|  char exact[3] = "abc";
    #|  return inferred[0] + padded[0] + exact[0];
    #|}
  let stmts = initializer_body_stmts(source)
  guard stmts[0] is VarDecl(Array(SChar, 4), "inferred", Some(String("abc"))) else {
    fail("expected the terminator in the size: \{Repr(stmts[0])}")
  }
  guard stmts[1] is VarDecl(Array(SChar, 8), "padded", Some(String("hi"))) else {
    fail("expected the written size: \{Repr(stmts[1])}")
  }
  guard stmts[2] is VarDecl(Array(SChar, 3), "exact", Some(String("abc"))) else {
    fail("expected no room for a terminator: \{Repr(stmts[2])}")
  }
}

///|
/// Every declarator in a comma-separated list is recorded the same way, which
/// is the path that used to be a second copy of the lowering.
test "later declarators record their initializers too" {
  let stmts = initializer_body_stmts(
    "int f(void) { int a = 1, b[] = {7, 8}, c = 3; return a; }",
  )
  guard stmts
    is [
      VarDecl(SInt, "a", Some(Number(1, _, _))),
      VarDecl(
        Array(SInt, 2),
        "b",
        Some(Array([Number(7, _, _), Number(8, _, _)]))
      ),
      VarDecl(SInt, "c", Some(Number(3, _, _))),
      ..,
    ] else {
    fail("expected three sibling declarations: \{Repr(stmts)}")
  }
}

///|
/// A `static` local is promoted to a global and keeps taking the `GlobalInit`
/// path, which this change leaves alone.
test "a static local initializer is still a global initializer" {
  let program = @parser.parse(
    "int f(void) { static int a[3] = {1, 2, 3}; return a[0]; }",
  )
  assert_eq(program.globals.length(), 1)
  guard program.globals[0].init
    is Some(Array([Number(1, _, _), Number(2, _, _), Number(3, _, _)])) else {
    fail(
      "expected a global array initializer: \{Repr(program.globals[0].init)}",
    )
  }
  guard program.globals[0].ty is Array(SInt, 3) else {
    fail("expected the inferred size on the global")
  }
}

///|
/// Two blocks of one function may each declare a static with the same name;
/// each is its own object. A shared mangled name used to emit one global per
/// declaration -- the same symbol several times over.
test "same-named statics in one function get distinct globals" {
  let source =
    #|int f(void) {
    #|  { static int iLn = 1; iLn += 1; }
    #|  { static int iLn = 2; iLn += 2; }
    #|  return 0;
    #|}
  let program = @parser.parse(source)
  assert_eq(program.globals.length(), 2)
  assert_true(program.globals[0].name != program.globals[1].name)
  guard program.globals[0].init is Some(Scalar(Number(1, _, _))) else {
    fail("expected the first static's initializer")
  }
  guard program.globals[1].init is Some(Scalar(Number(2, _, _))) else {
    fail("expected the second static's initializer")
  }
}

///|
/// A nested block's shadowing static is its own object, and leaving the block
/// restores the outer binding: `x += 100` after the inner block updates the
/// outer static, not the inner one.
test "static shadowing restores the outer binding at block exit" {
  let source =
    #|int f(void) {
    #|  static int x = 1;
    #|  { static int x = 2; x += 10; }
    #|  x += 100;
    #|  return x;
    #|}
  let program = @parser.parse(source)
  assert_eq(program.globals.length(), 2)
  let outer = program.globals[0].name
  let inner = program.globals[1].name
  assert_true(outer != inner)
  // The static declarations leave no statements -- they are promoted -- so
  // the body is the inner block, the post-block assignment, and the return.
  guard program.decls[0].body
    is Some(
      Compound(
        [
          Compound([ExprStmt(CompoundAssign("+", Var(inside_block), _))]),
          ExprStmt(CompoundAssign("+", Var(after_block), Number(100, _, _))),
          Return(_),
        ]
      )
    ) else {
    fail("expected the post-block assignment: \{Repr(program.decls[0].body)}")
  }
  assert_eq(inside_block, inner)
  assert_eq(after_block, outer)
}
