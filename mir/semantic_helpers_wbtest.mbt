///|
fn semantic_helper_linux_target() -> @target.Target {
  match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("linux target did not parse")
  }
}

///|
fn expect_const(
  mir : Program,
  expr : @parser.Expr,
  scope : Scope,
  expected : Int64,
) -> Unit {
  match mir.fold_const(expr, scope) {
    Some(value) =>
      if value != expected {
        abort("unexpected constant fold result")
      }
    None => abort("expected constant fold result")
  }
}

///|
fn expect_float_const(
  mir : Program,
  expr : @parser.Expr,
  scope : Scope,
  expected : Double,
) -> Unit {
  match mir.fold_float_const(expr, scope) {
    Some(value) =>
      if value != expected {
        abort("unexpected floating constant fold result")
      }
    None => abort("expected floating constant fold result")
  }
}

///|
test "mir internal expression helpers use target layout" {
  let source = "int main(void) { return 0; }"
  let darwin = lower(@parser.parse(source), @target.Target::default())
  let linux = lower(
    @parser.parse_for_target(source, semantic_helper_linux_target()),
    semantic_helper_linux_target(),
  )
  let scope = Scope::empty()
  let long_double_builtin : @parser.Expr = Call(Var("__builtin_fabsl"), [
    FloatLiteral("1.0", Double),
  ])
  inspect(darwin.expr_type(long_double_builtin, scope), content="LongDouble")
  inspect(linux.expr_type(long_double_builtin, scope), content="LongDouble")
  expect_const(darwin, SizeofExpr(long_double_builtin), scope, 8L)
  expect_const(linux, SizeofExpr(long_double_builtin), scope, 16L)
}

///|
test "mir internal expression helpers compute parser expression types" {
  let source =
    #|struct S { int x; double y; };
    #|struct S g;
    #|double callee(int x, ...);
    #|int main(void) { return 0; }
  let mir = lower(@parser.parse(source), @target.Target::default())
  let scope = Scope::{
    locals: { "p": Pointer(SInt), "s": Struct("S") },
    current_func: "main",
  }
  inspect(
    mir.expr_type(Binary("+", Var("p"), @parser.int_literal(1, SInt)), scope),
    content="Pointer(SInt)",
  )
  inspect(
    mir.expr_type(Binary("-", Var("p"), Var("p")), scope),
    content="SLong",
  )
  inspect(
    mir.expr_type(
      Binary("<<", @parser.int_literal(1, SInt), @parser.int_literal(40, SInt)),
      scope,
    ),
    content="ULongLong",
  )
  inspect(mir.expr_type(MemberAccess(Var("s"), "y"), scope), content="Double")
  inspect(
    mir.expr_type(Var("callee"), scope),
    content="FuncPtr(Double, [SInt], true)",
  )
}

///|
test "mir internal expression helpers fold constants with target layout" {
  let source =
    #|struct S { char c; int i; int arr[3]; };
    #|struct S global_s;
    #|int global_x;
    #|char global_buf[16];
    #|int main(void) { return 0; }
  let mir = lower(@parser.parse(source), @target.Target::default())
  let scope = Scope::empty()
  expect_const(mir, Sizeof(Struct("S")), scope, 20L)
  expect_const(
    mir,
    OffsetOf(Struct("S"), [OffsetField("arr"), OffsetIndex(2)]),
    scope,
    16L,
  )
  expect_const(mir, SizeofExpr(String("abc")), scope, 4L)
  expect_const(mir, AlignofExpr(String("abc")), scope, 1L)
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      String("abc"),
      @parser.int_literal(0, SInt),
    ]),
    scope,
    4L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_dynamic_object_size"), [
      Cast(Pointer(SChar), String("abcd")),
      @parser.int_literal(2, SInt),
    ]),
    scope,
    5L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      Cast(Pointer(Void), @parser.int_literal(0, SInt)),
      @parser.int_literal(0, SInt),
    ]),
    scope,
    -1L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_dynamic_object_size"), [
      Cast(Pointer(Void), @parser.int_literal(0, SInt)),
      @parser.int_literal(2, SInt),
    ]),
    scope,
    0L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      AddrOf(Var("global_x")),
      @parser.int_literal(0, SInt),
    ]),
    scope,
    4L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_dynamic_object_size"), [
      Var("global_buf"),
      @parser.int_literal(2, SInt),
    ]),
    scope,
    16L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      AddrOf(ArrayAccess(Var("global_buf"), @parser.int_literal(3, SInt))),
      @parser.int_literal(0, SInt),
    ]),
    scope,
    13L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      AddrOf(ArrayAccess(Var("global_buf"), @parser.int_literal(3, SInt))),
      @parser.int_literal(1, SInt),
    ]),
    scope,
    13L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      Binary("+", Var("global_buf"), @parser.int_literal(3, SInt)),
      @parser.int_literal(0, SInt),
    ]),
    scope,
    13L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      Binary(
        "+",
        AddrOf(ArrayAccess(Var("global_buf"), @parser.int_literal(3, SInt))),
        @parser.int_literal(2, SInt),
      ),
      @parser.int_literal(1, SInt),
    ]),
    scope,
    11L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      AddrOf(MemberAccess(Var("global_s"), "arr")),
      @parser.int_literal(0, SInt),
    ]),
    scope,
    12L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_dynamic_object_size"), [
      MemberAccess(Var("global_s"), "arr"),
      @parser.int_literal(2, SInt),
    ]),
    scope,
    12L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_dynamic_object_size"), [
      AddrOf(
        ArrayAccess(
          MemberAccess(Var("global_s"), "arr"),
          @parser.int_literal(1, SInt),
        ),
      ),
      @parser.int_literal(2, SInt),
    ]),
    scope,
    8L,
  )
  let local_types : Map[String, @ctype.Type] = Map([])
  local_types["local_x"] = SInt
  local_types["local_buf"] = Array(SChar, 16)
  local_types["local_s"] = Struct("S")
  let local_scope : Scope = { locals: local_types, current_func: "main" }
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      AddrOf(Var("local_x")),
      @parser.int_literal(0, SInt),
    ]),
    local_scope,
    4L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_dynamic_object_size"), [
      Var("local_buf"),
      @parser.int_literal(2, SInt),
    ]),
    local_scope,
    16L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      AddrOf(ArrayAccess(Var("local_buf"), @parser.int_literal(3, SInt))),
      @parser.int_literal(0, SInt),
    ]),
    local_scope,
    13L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      AddrOf(MemberAccess(Var("local_s"), "arr")),
      @parser.int_literal(0, SInt),
    ]),
    local_scope,
    12L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_dynamic_object_size"), [
      MemberAccess(Var("local_s"), "arr"),
      @parser.int_literal(2, SInt),
    ]),
    local_scope,
    12L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      AddrOf(
        ArrayAccess(
          MemberAccess(Var("local_s"), "arr"),
          @parser.int_literal(1, SInt),
        ),
      ),
      @parser.int_literal(1, SInt),
    ]),
    local_scope,
    8L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_constant_p"), [
      Binary("+", @parser.int_literal(1, SInt), @parser.int_literal(2, SInt)),
    ]),
    scope,
    1L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_constant_p"), [Var("global_x")]),
    scope,
    0L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_abs"), [Unary("-", @parser.int_literal(7, SInt))]),
    scope,
    7L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_align_up"), [
      @parser.int_literal(33, SInt),
      @parser.int_literal(16, SInt),
    ]),
    scope,
    48L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_popcount"), [@parser.int_literal(0xf0f0, SInt)]),
    scope,
    8L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_bswap32"), [@parser.int_literal(0x01020304, SInt)]),
    scope,
    0x04030201L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_rotateleft32"), [
      @parser.int_literal(0x12345678, SInt),
      @parser.int_literal(8, SInt),
    ]),
    scope,
    0x34567812L,
  )
  expect_const(
    mir,
    Binary("/", @parser.int_literal(1, SInt), @parser.int_literal(2, SInt)),
    scope,
    0L,
  )
  expect_const(
    mir,
    Binary(
      ">",
      Cast(ULong, Unary("-", @parser.int_literal(1, SInt))),
      @parser.int_literal(1, SInt),
    ),
    scope,
    1L,
  )
  expect_float_const(
    mir,
    Binary(
      "/",
      Cast(Double, @parser.int_literal(1, SInt)),
      @parser.int_literal(2, SInt),
    ),
    scope,
    0.5,
  )
  expect_float_const(
    mir,
    Cast(Double, Cast(SInt, FloatLiteral("1.75", Double))),
    scope,
    1.0,
  )
  expect_float_const(
    mir,
    Ternary(
      @parser.int_literal(0, SInt),
      FloatLiteral("9.0", Double),
      Binary("+", FloatLiteral("1.25", Double), FloatLiteral("2.5", Double)),
    ),
    scope,
    3.75,
  )
  expect_float_const(
    mir,
    Call(Var("__builtin_fabs"), [FloatLiteral("-4.5", Double)]),
    scope,
    4.5,
  )
  expect_float_const(
    mir,
    Call(Var("__builtin_copysign"), [
      FloatLiteral("3.0", Double),
      FloatLiteral("-1.0", Double),
    ]),
    scope,
    -3.0,
  )
  expect_float_const(
    mir,
    Call(Var("__builtin_sqrt"), [FloatLiteral("81.0", Double)]),
    scope,
    9.0,
  )
  match
    mir.fold_float_const(
      Call(Var("__builtin_sqrt"), [FloatLiteral("-1.0", Double)]),
      scope,
    ) {
    Some(value) => if value == value { abort("expected folded NaN") }
    None => abort("expected folded NaN")
  }
  match mir.fold_float_const(Call(Var("__builtin_huge_valf"), []), scope) {
    Some(value) => if !(value > 1000000.0) { abort("expected folded infinity") }
    None => abort("expected folded infinity")
  }
}
