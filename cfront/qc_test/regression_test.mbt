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

///|
/// Declarators whose return type is itself a function pointer. The parser
/// read `int (*f(void))(char)` as a function returning `int *` -- dropping
/// the `(char)` -- and `int (*(*fp)(int))(char)` as a pointer to a function
/// taking `char`, swapping the two parameter lists.
test "regression: function pointer return types parse to the declared type" {
  let returns_fp = @parser.parse("int (*f(void))(char);\n")
  assert_eq(returns_fp.decls[0].ret, FuncPtr(SInt, [SChar], false))
  assert_eq(returns_fp.decls[0].params, [])
  let returns_array_ptr = @parser.parse("int (*g(int n))[4];\n")
  assert_eq(returns_array_ptr.decls[0].ret, Pointer(Array(SInt, 4)))
  assert_eq(returns_array_ptr.decls[0].params.length(), 1)
  let nested = @parser.parse("int (*(*fp)(int))(char);\n")
  assert_eq(
    nested.globals[0].ty,
    FuncPtr(FuncPtr(SInt, [SChar], false), [SInt], false),
  )
  assert_eq(
    reparse_expr("sizeof(int (*(*)(int))(char))"),
    Some(Sizeof(FuncPtr(FuncPtr(SInt, [SChar], false), [SInt], false))),
  )
  // And the printed forms of those trees read back as themselves.
  for
    source in [
      "int (*f(void))(char);\n", "int (*(*fp)(int))(char);\n", "char *(*(*h(int x))(long))(void) {\n  return 0;\n}\n",
    ] {
    let program = @parser.parse(source)
    let printed = @printer.print_program(program)
    assert_eq(@parser.parse(printed), program)
  }
}

///|
fn preprocess_text(source : String) -> String {
  match
    @preprocessor.preprocess(
      source,
      @preprocessor.PreprocessOptions::new("regression.c"),
    ) {
    Ok(text) => text
    Err(err) => "error: " + err.to_string()
  }
}

///|
/// An unmatched quote ends at the end of its line. The `#if 0` comment
/// idiom -- prose with an apostrophe inside a disabled group -- made the
/// preprocessor read a character literal across the `#endif`, and fail
/// with "unterminated conditional directive"; GCC and Clang accept it.
test "regression: an apostrophe in a disabled group does not hide #endif" {
  inspect(
    preprocess_text("#if 0\ndon't do this\n#endif\nint q;\n"),
    content="int q;\n",
  )
  inspect(
    preprocess_text("#if 0\n\"unterminated\n#endif\nint q;\n"),
    content="int q;\n",
  )
}

///|
/// A character outside the Basic Multilingual Plane, outside any literal
/// or comment, made the preprocessor loop forever: its tokenizer sliced
/// half a surrogate pair, got an empty token, and advanced by zero.
test "regression: an astral character outside literals does not hang the preprocessor" {
  inspect(preprocess_text("int \u{1F600} x;\n"), content="int\u{1F600}x;\n")
  inspect(preprocess_text("\u{1F600}"), content="\u{1F600}\n")
}

///|
/// A preprocessing number continues through `+` or `-` only after an
/// exponent letter. The tokenizer took any sign, so `9+SIZE` was one
/// number token and `SIZE` was never expanded.
test "regression: a macro after a number and a sign is expanded" {
  inspect(
    preprocess_text("#define SIZE 4\nint x = 9+SIZE;\nint y = 1-SIZE;\n"),
    content="int x=9+4;\nint y=1-4;\n",
  )
  // The exponent sign stays part of the number, as C specifies: `0x1e+N`
  // is one preprocessing number, and GCC does not expand it either.
  inspect(
    preprocess_text("#define N 4\ndouble d = 1e+5+N;\n"),
    content="double d=1e+5+4;\n",
  )
}

///|
/// The preprocessor respaces its output, and wrote two punctuators with no
/// space between them unless they were `+ +` or `- -`. So `y / *p`
/// became `y/*p` -- a comment that swallowed the rest of the file -- and
/// `a + ++i` became `a+++i`, which reads as `a++ + i`.
test "regression: preprocessor output keeps adjacent punctuators apart" {
  for
    source in [
      "int f(int y, int *p) { return y / *p; }\nint g(void) { return 1; }\n", "int f(int a, int i) { return a + ++i; }\n",
      "int f(int a, int b) { return a & &b != 0; }\n", "int f(int a) { return a - -1; }\n",
    ] {
    let expected = @parser.parse(source)
    let text = preprocess_text(source)
    assert_eq(@parser.parse(text), expected)
  }
  inspect(preprocess_text("y / *p;\n"), content="y/ *p;\n")
}

///|
/// Adjacent string literals concatenate across comments as well as
/// whitespace. The lexer's concatenation step skipped only whitespace, so
/// `"a" /* c */ "b"` was two literals in a row -- a parse error -- while
/// the same text preprocessed (comments removed) parsed fine.
test "regression: string literals concatenate across comments" {
  for
    source in [
      "char *s = \"a\" /* c */ \"b\";\n", "char *s = \"a\" // c\n  \"b\";\n", "char *s = \"a\" /* c */ /* d */\n\"b\";\n",
    ] {
    let program = @parser.parse(source)
    assert_eq(program.globals[0].init, Some(Scalar(String("ab"))))
  }
}
