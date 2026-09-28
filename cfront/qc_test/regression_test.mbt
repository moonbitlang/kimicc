///|
/// Concrete counterexamples the properties in `syntax_qc_test.mbt` found,
/// kept as named regressions next to them.

///|
/// Parses `text` as the body of `void h(void)` and returns the expression of
/// its single expression statement, or `None` when the text does not parse
/// to exactly that shape.
fn reparse_expr(text : String) -> @parser.Expr? {
  let program = @parser.parse_with_named_types(
    "void h(void) {\n  " + text + ";\n}\n",
    named_type_pool,
  ) catch {
    _ => return None
  }
  match program.decls {
    [{ body: Some(Compound([ExprStmt(expr)])), .. }] => Some(expr)
    _ => None
  }
}

///|
fn round_trip_expr(expr : @parser.Expr) -> (String, @parser.Expr?) {
  let printed = @printer.print_expr(expr)
  (printed, reparse_expr(printed))
}

///|
/// `sizeof` and `_Alignof` are unary operators: a postfix operator applied
/// to one must parenthesize it. `(sizeof(int))[a]` is valid C (it indexes
/// `a`), but printed bare as `sizeof(int)[a]` it does not parse, and
/// `sizeof(x)[a]` parses as `sizeof((x)[a])`.
test "regression: postfix operators on sizeof and _Alignof keep parentheses" {
  let a : @parser.Expr = Var("a")
  let x : @parser.Expr = Var("x")
  for
    expr in [
      @parser.Expr::ArrayAccess(Sizeof(SInt), a),
      ArrayAccess(SizeofExpr(x), a),
      ArrayAccess(Alignof(SInt), a),
      ArrayAccess(AlignofExpr(x), a),
      Call(SizeofExpr(x), []),
    ] {
    let (printed, back) = round_trip_expr(expr)
    assert_true(
      printed.has_prefix("(sizeof(") || printed.has_prefix("(_Alignof("),
    )
    assert_eq(back, Some(expr))
  }
  inspect(
    @printer.print_expr(ArrayAccess(SizeofExpr(x), a)),
    content="(sizeof(x))[a]",
  )
}
