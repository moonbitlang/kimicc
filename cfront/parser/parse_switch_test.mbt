///|
/// Parses one function body and returns its statements.
fn switch_body_stmts(source : String) -> Array[@parser.Stmt] raise {
  let program = @parser.parse(source)
  guard program.decls[0].body is Some(Compound(stmts)) else {
    fail("expected a function body")
  }
  stmts
}

///|
/// A clause is a label around the statement it labels, the way C writes it:
/// the statements after it are siblings that fall through, not children.
test "case and default label the statement that follows them" {
  let source =
    #|int f(int n) {
    #|  switch (n) {
    #|    case 1: n = 10; break;
    #|    default: n = 20;
    #|  }
    #|  return n;
    #|}
  let stmts = switch_body_stmts(source)
  guard stmts[0]
    is Switch(
      Var("n"),
      Compound(
        [
          Case(1, ExprStmt(Assign(Var("n"), Number(10, _, SInt)))),
          Break,
          Default(ExprStmt(Assign(Var("n"), Number(20, _, SInt)))),
        ]
      )
    ) else {
    fail("expected case and default nodes: \{Repr(stmts[0])}")
  }
}

///|
/// Clause values are folded constant expressions, including enum constants and
/// negative values, and a nested switch keeps its clauses inside itself.
test "clause values fold and nest" {
  let source =
    #|enum Color { RED = 2, BLUE = 9 };
    #|int f(int a, int b) {
    #|  switch (a) {
    #|    case -3: return 1;
    #|    case RED + 1: return 2;
    #|    case BLUE * 2:
    #|      switch (b) {
    #|        case -3: return 3;
    #|      }
    #|  }
    #|  return 0;
    #|}
  let stmts = switch_body_stmts(source)
  guard stmts[0]
    is Switch(
      _,
      Compound(
        [
          Case(-3, Return(_)),
          Case(3, Return(_)),
          Case(18, Switch(Var("b"), Compound([Case(-3, Return(_))]))),
        ]
      )
    ) else {
    fail("expected folded clause values: \{Repr(stmts[0])}")
  }
}

///|
/// A clause may sit inside a block or ahead of a written label; both keep the
/// shape they were written in rather than being hoisted to the switch body.
test "clauses keep their position in the body" {
  let source =
    #|int f(int n) {
    #|  switch (n) {
    #|    { case 1: return 1; }
    #|    top: case 2: return 2;
    #|  }
    #|  return 0;
    #|}
  let stmts = switch_body_stmts(source)
  guard stmts[0]
    is Switch(
      _,
      Compound(
        [Compound([Case(1, Return(_))]), Label("top", Case(2, Return(_)))]
      )
    ) else {
    fail("expected nested and labelled clauses: \{Repr(stmts[0])}")
  }
}

///|
/// A clause value that does not fold is reported rather than silently read as
/// `case 0:`, which is what the parser did while clauses were label names.
test "a clause value that does not fold is a diagnostic" {
  let source =
    #|int f(int n, int m) {
    #|  switch (n) {
    #|    case m: return 1;
    #|  }
    #|  return 0;
    #|}
  try @parser.parse(source) |> ignore catch {
    error =>
      inspect(
        error.to_string(),
        content="3:10: unsupported case label that does not fold to an integer constant",
      )
  } noraise {
    _ => fail("expected the non-constant clause to be reported")
  }
}
