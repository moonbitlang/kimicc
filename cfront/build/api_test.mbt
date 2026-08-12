///|
/// The operators build the trees the parser produces, so an expression
/// written as math prints as the C it means.
test "operators build parser-shaped trees" {
  let a = @build.v("a")
  let b = @build.v("b")
  let c = @build.v("c")
  inspect(@printer.print_expr(a + b * c), content="a + b * c")
  inspect(@printer.print_expr((a + b) * c), content="(a + b) * c")
  inspect(@printer.print_expr(-(a - b)), content="-(a - b)")
  inspect(@printer.print_expr(a[b + c]), content="a[b + c]")
  inspect(@printer.print_expr(a.lt(b)), content="a < b")
  inspect(@printer.print_expr(a / b - c.rem(a)), content="a / b - c % a")
}

///|
/// `double_literal` text survives the round-trip and always lexes as a
/// floating constant; negatives canonicalize to unary minus.
test "double literals are canonical and round-trip" {
  assert_true(@parser.double_literal(0.5) is FloatLiteral("0.5", Double))
  assert_true(@parser.double_literal(1.0) is FloatLiteral("1.0", Double))
  assert_true(
    @parser.double_literal(0.7071067811865476)
    is FloatLiteral("0.7071067811865476", Double),
  )
  assert_true(
    @parser.double_literal(-0.25) is Unary("-", FloatLiteral("0.25", Double)),
  )
  // Text round-trips through print and parse inside a program.
  let p = @build.program(globals=[
    @build.global(Double, "k", init=Scalar(@parser.double_literal(1.0e100))),
  ])
  let printed = @printer.print_program(p)
  assert_eq(@parser.parse(printed), p)
}

///|
/// The builders emit the canonical form: a program built by hand reparses
/// equal, aggregates and prototypes included.
test "built programs are the parser's image" {
  let p = @build.program(
    structs=[
      @build.aggregate("Pair", [
        @build.field(Double, "re"),
        @build.field(Double, "im"),
      ]),
    ],
    globals=[
      @build.global(SInt, "count", init=Scalar(@parser.int_literal(3, SInt))),
    ],
    decls=[
      @build.prototype(Void, "consume", [
        @build.param(Pointer(Struct("Pair")), "p"),
      ]),
      @build.func(SInt, "main_like", [], [
        @build.decl(SInt, "x", init=@parser.int_literal(1, SInt)),
        @build.assign(@build.v("x"), @build.v("x") + @build.v("count")),
        @build.ret(value=@build.v("x")),
      ]),
    ],
  )
  let printed = @printer.print_program(p)
  assert_eq(@parser.parse(printed), p)
  assert_eq(printed, @printer.print_program(@parser.parse(printed)))
}

///|
/// The inference-kernel builders: a constant-bound loop accumulating an
/// inner product, libm calls, casts, and a float literal -- the shapes a
/// specialized model kernel is made of.
test "kernel builders print as the C they mean" {
  let acc = @build.v("acc")
  let a = @build.v("a")
  let b = @build.v("b")
  let i = @build.v("i")
  let dot = @build.for_range("i", @parser.int_literal(64, SInt), [
    @build.add_assign(acc, a[i] * b[i]),
  ])
  inspect(
    @printer.print_stmt(dot),
    content=(
      #|for (int i = 0; i < 64; i++) {
      #|  acc += a[i] * b[i];
      #|}
    ),
  )
  inspect(
    @printer.print_expr(@build.call("expf", [-@build.v("x")])),
    content="expf(-x)",
  )
  inspect(
    @printer.print_expr(
      @build.cast(Float, @build.v("q")) * @parser.float_literal(0.125),
    ),
    content="(float)q * 0.125f",
  )
  // Float literal text is canonical and reparses with its suffix type.
  assert_true(@parser.float_literal(0.5) is FloatLiteral("0.5", Float))
  assert_true(
    @parser.float_literal(-2.0) is Unary("-", FloatLiteral("2.0", Float)),
  )
}

///|
/// Negative zero keeps its sign -- it is observable through division -- and
/// an array parameter adjusts to the pointer C says it is.
test "signed zero and array parameters are canonical" {
  assert_true(
    @parser.double_literal(-0.0) is Unary("-", FloatLiteral("0.0", Double)),
  )
  assert_true(
    @parser.float_literal((-0.0 : Float))
    is Unary("-", FloatLiteral("0.0", Float)),
  )
  assert_true(@parser.double_literal(0.0) is FloatLiteral("0.0", Double))
  let p = @build.param(Array(SInt, 3), "a")
  assert_true(p.ty is Pointer(SInt))
  // And the whole shape round-trips.
  let prog = @build.program(decls=[
    @build.func(SInt, "sum3", [@build.param(Array(SInt, 3), "a")], [
      @build.ret(
        value=@build.v("a")[@parser.int_literal(0, SInt)] +
          @build.v("a")[@parser.int_literal(1, SInt)] +
          @build.v("a")[@parser.int_literal(2, SInt)],
      ),
    ]),
  ])
  let printed = @printer.print_program(prog)
  assert_eq(@parser.parse(printed), prog)
}

///|
/// A static definition needs a static forward declaration; the pair prints
/// as C clang accepts.
test "static prototypes match static definitions" {
  let prog = @build.program(decls=[
    @build.prototype(Void, "helper", [], is_static=true),
    @build.func(Void, "helper", [], [], is_static=true),
  ])
  let printed = @printer.print_program(prog)
  assert_true(printed.contains("static void helper(void);"))
  assert_eq(@parser.parse(printed), prog)
}

///|
/// A declaration builder completes an incomplete array from its initializer,
/// the same inference the parser applies -- so the built AST carries the
/// size its printed form parses back to.
test "incomplete arrays complete from their initializers" {
  let g = @build.global(
    Array(SInt, 0),
    "table",
    init=Array([
      @parser.int_literal(1, SInt),
      @parser.int_literal(2, SInt),
      @parser.int_literal(3, SInt),
    ]),
  )
  assert_true(g.ty is Array(SInt, 3))
  let s = @build.decl(Array(SChar, 0), "name", init=String("abc"))
  guard s is VarDecl(Array(SChar, 4), _, _) else {
    fail("expected the terminator counted")
  }
  let prog = @build.program(globals=[g])
  let printed = @printer.print_program(prog)
  assert_eq(@parser.parse(printed), prog)
}

///|
/// An ordered program interleaves kinds, so a global initializer can follow
/// the prototype of the function it names.
test "ordered programs keep prototypes before the globals that need them" {
  let prog = @build.ordered_program([
    Func(
      @build.prototype(
        Void,
        "on_event",
        [@build.param(SInt, "code")],
        is_static=true,
      ),
    ),
    Global(
      @build.global(
        Pointer(FuncPtr(Void, [SInt], false)),
        "handler",
        init=Scalar(@build.v("on_event")),
        is_static=true,
      ),
    ),
    Func(
      @build.func(
        Void,
        "on_event",
        [@build.param(SInt, "code")],
        [],
        is_static=true,
      ),
    ),
  ])
  let printed = @printer.print_program(prog)
  guard printed.find("static void on_event(int code);") is Some(proto_at) else {
    fail("missing prototype: \{printed}")
  }
  guard printed.find("handler") is Some(global_at) else {
    fail("missing global")
  }
  assert_true(proto_at < global_at)
  assert_eq(@parser.parse(printed), prog)
}

///|
/// Brace initializers over scalar destinations normalize to the value
/// inside, matching what the parser records for `int x = {1}`.
test "scalar brace initializers normalize in builders" {
  let g = @build.global(SInt, "x", init=Array([@parser.int_literal(1, SInt)]))
  guard g.init is Some(Scalar(Number(1, _, _))) else {
    fail("expected the scalar inside the braces")
  }
  guard @build.decl(SInt, "y", init=Array([@parser.int_literal(2, SInt)]))
    is VarDecl(SInt, _, Some(Number(2, _, _))) else {
    fail("expected the local scalar inside the braces")
  }
}
