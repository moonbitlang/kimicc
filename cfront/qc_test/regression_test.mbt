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

///|
/// An initializer and the operand of `_Alignof(...)` are single
/// assignment-expressions, so a comma-operator value must keep its
/// parentheses. Printed bare, `int x = (a, b);` became `int x = a , b;` --
/// a second declaration of `b` -- and `_Alignof((a, b))` became
/// `_Alignof(a , b)`, which does not parse.
test "regression: comma operands keep parentheses in initializers and _Alignof" {
  let comma : @parser.Expr = Binary(",", Var("a"), Var("b"))
  let (printed, back) = round_trip_expr(AlignofExpr(comma))
  inspect(printed, content="_Alignof((a , b))")
  assert_eq(back, Some(AlignofExpr(comma)))
  let sources = [
    "int a, b;\nint g = (1, 2);\n", "void h(int a, int b) {\n  int x = (a, b);\n}\n",
    "void h(int a, int b) {\n  for (int i = (a, b), j = 0; i; ) ;\n}\n",
  ]
  for source in sources {
    let program = @parser.parse(source)
    let printed = @printer.print_program(program)
    assert_eq(@parser.parse(printed), program)
  }
}

///|
/// `&` applied to an expression that itself starts with `&` needs a space:
/// `AddrOf(AddrOf(x))` printed as `&&x` lexes as the label address `&&x`.
test "regression: nested address-of does not glue into &&" {
  for expr in [@parser.Expr::AddrOf(AddrOf(Var("x"))), AddrOf(LabelAddr("L0"))] {
    let (printed, back) = round_trip_expr(expr)
    assert_true(printed.has_prefix("& &"))
    assert_eq(back, Some(expr))
  }
}

///|
/// An atomic pointer and a pointer to an atomic type are different types,
/// and the specifier spelling only says the second: `Atomic(Pointer(UShort))`
/// printed as `_Atomic unsigned short *x`, which declares
/// `Pointer(Atomic(UShort))`. The type-name form keeps them apart.
test "regression: an atomic pointer prints as _Atomic(type-name)" {
  let atomic_pointer : @ctype.Type = Atomic(Pointer(UShort))
  inspect(
    @printer.print_declaration(atomic_pointer, "x"),
    content="_Atomic(unsigned short *) x",
  )
  inspect(
    @printer.print_declaration(Pointer(Atomic(UShort)), "x"),
    content="_Atomic unsigned short *x",
  )
  inspect(
    @printer.print_declaration(Pointer(atomic_pointer), "x"),
    content="_Atomic(unsigned short *) *x",
  )
  for ty in [atomic_pointer, Pointer(atomic_pointer)] {
    let program = @parser.parse(
      "void h(void) {\n  " + @printer.print_declaration(ty, "x") + ";\n}\n",
    )
    assert_eq(program.decls[0].body, Some(Compound([VarDecl(ty, "x", None)])))
    assert_eq(reparse_expr(@printer.print_expr(Sizeof(ty))), Some(Sizeof(ty)))
  }
}
