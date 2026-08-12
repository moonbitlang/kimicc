///|
/// The toolkit's central promise, checked over generated programs: build an
/// AST, print it, and the text parses back to the same AST -- with the
/// printed text a fixed point from the first print. A failure prints the
/// generated C as the counterexample.
test "generated programs round-trip through print and parse" {
  @quickcheck.check(
    (p : GenProgram) => {
      // A parse error propagates as an exceptional counterexample:
      // printing something the parser rejects is its own failure.
      let printed = @printer.print_program(p.0)
      let second = @parser.parse(printed)
      second == p.0 && @printer.print_program(second) == printed
    },
    count=300,
    max_size=12,
    seed=20260812,
  )
}

///|
/// The same property under a second seed, so a regression cannot hide behind
/// one lucky corpus.
test "generated programs round-trip under a second seed" {
  @quickcheck.check(
    (p : GenProgram) => {
      let printed = @printer.print_program(p.0)
      let second = @parser.parse(printed)
      second == p.0 && @printer.print_program(second) == printed
    },
    count=300,
    max_size=12,
    seed=427,
  )
}

///|
/// A tree outside the parser's image -- an else-less `if` as the bare
/// then-branch of an `if` that has an `else` -- has no source spelling: the
/// dangling-else rule would bind the `else` inward. The printer braces the
/// branch, preserving meaning; the reparse carries the braces, which is the
/// canonical form of the same statement.
test "an else-capturing then-branch prints braced" {
  let outside : @parser.Stmt = If(
    Var("b"),
    If(Var("a"), ExprStmt(Assign(Var("x"), @parser.int_literal(1, SInt))), None),
    Some(ExprStmt(Assign(Var("x"), @parser.int_literal(2, SInt)))),
  )
  let printed = @printer.print_stmt(outside)
  // The else belongs to the outer if in the text...
  let expected =
    #|if (b) {
    #|  if (a) 
    #|    x = 1;
    #|} else 
    #|  x = 2;
  assert_eq(printed, expected)
}

///|
/// A bare `switch` body is a trailing substatement too: an open `if` at the
/// end of one captures a following `else`, so the printer braces the branch.
test "an open if behind a switch is braced before an else" {
  let outside : @parser.Stmt = If(
    Var("b"),
    Switch(
      Var("s"),
      If(
        Var("a"),
        ExprStmt(Assign(Var("x"), @parser.int_literal(1, SInt))),
        None,
      ),
    ),
    Some(ExprStmt(Assign(Var("x"), @parser.int_literal(2, SInt)))),
  )
  let printed = @printer.print_stmt(outside)
  // The then-branch is braced, so the else stays with the outer if.
  assert_true(printed.contains("} else"))
}
