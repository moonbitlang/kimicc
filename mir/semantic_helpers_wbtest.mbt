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
    FloatLiteral(1.0),
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
    mir.expr_type(Binary("+", Var("p"), Number(1)), scope),
    content="Pointer(SInt)",
  )
  inspect(
    mir.expr_type(Binary("-", Var("p"), Var("p")), scope),
    content="SLong",
  )
  inspect(
    mir.expr_type(Binary("<<", Number(1), Number(40)), scope),
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
    Call(Var("__builtin_object_size"), [String("abc"), Number(0)]),
    scope,
    4L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_dynamic_object_size"), [
      Cast(Pointer(SChar), String("abcd")),
      Number(2),
    ]),
    scope,
    5L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      Cast(Pointer(Void), Number(0)),
      Number(0),
    ]),
    scope,
    -1L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_dynamic_object_size"), [
      Cast(Pointer(Void), Number(0)),
      Number(2),
    ]),
    scope,
    0L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [AddrOf(Var("global_x")), Number(0)]),
    scope,
    4L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_dynamic_object_size"), [Var("global_buf"), Number(2)]),
    scope,
    16L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      AddrOf(ArrayAccess(Var("global_buf"), Number(3))),
      Number(0),
    ]),
    scope,
    13L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      AddrOf(ArrayAccess(Var("global_buf"), Number(3))),
      Number(1),
    ]),
    scope,
    13L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      Binary("+", Var("global_buf"), Number(3)),
      Number(0),
    ]),
    scope,
    13L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      Binary("+", AddrOf(ArrayAccess(Var("global_buf"), Number(3))), Number(2)),
      Number(1),
    ]),
    scope,
    11L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      AddrOf(MemberAccess(Var("global_s"), "arr")),
      Number(0),
    ]),
    scope,
    12L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_dynamic_object_size"), [
      MemberAccess(Var("global_s"), "arr"),
      Number(2),
    ]),
    scope,
    12L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_dynamic_object_size"), [
      AddrOf(ArrayAccess(MemberAccess(Var("global_s"), "arr"), Number(1))),
      Number(2),
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
    Call(Var("__builtin_object_size"), [AddrOf(Var("local_x")), Number(0)]),
    local_scope,
    4L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_dynamic_object_size"), [Var("local_buf"), Number(2)]),
    local_scope,
    16L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      AddrOf(ArrayAccess(Var("local_buf"), Number(3))),
      Number(0),
    ]),
    local_scope,
    13L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      AddrOf(MemberAccess(Var("local_s"), "arr")),
      Number(0),
    ]),
    local_scope,
    12L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_dynamic_object_size"), [
      MemberAccess(Var("local_s"), "arr"),
      Number(2),
    ]),
    local_scope,
    12L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_object_size"), [
      AddrOf(ArrayAccess(MemberAccess(Var("local_s"), "arr"), Number(1))),
      Number(1),
    ]),
    local_scope,
    8L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_constant_p"), [Binary("+", Number(1), Number(2))]),
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
    Call(Var("__builtin_abs"), [Unary("-", Number(7))]),
    scope,
    7L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_align_up"), [Number(33), Number(16)]),
    scope,
    48L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_popcount"), [Number(0xf0f0)]),
    scope,
    8L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_bswap32"), [Number(0x01020304)]),
    scope,
    0x04030201L,
  )
  expect_const(
    mir,
    Call(Var("__builtin_rotateleft32"), [Number(0x12345678), Number(8)]),
    scope,
    0x34567812L,
  )
  expect_const(mir, Binary("/", Number(1), Number(2)), scope, 0L)
  expect_const(
    mir,
    Binary(">", Cast(ULong, Unary("-", Number(1))), Number(1)),
    scope,
    1L,
  )
  expect_float_const(
    mir,
    Binary("/", Cast(Double, Number(1)), Number(2)),
    scope,
    0.5,
  )
  expect_float_const(
    mir,
    Cast(Double, Cast(SInt, FloatLiteral(1.75))),
    scope,
    1.0,
  )
  expect_float_const(
    mir,
    Ternary(
      Number(0),
      FloatLiteral(9.0),
      Binary("+", FloatLiteral(1.25), FloatLiteral(2.5)),
    ),
    scope,
    3.75,
  )
  expect_float_const(
    mir,
    Call(Var("__builtin_fabs"), [FloatLiteral(-4.5)]),
    scope,
    4.5,
  )
  expect_float_const(
    mir,
    Call(Var("__builtin_copysign"), [FloatLiteral(3.0), FloatLiteral(-1.0)]),
    scope,
    -3.0,
  )
  expect_float_const(
    mir,
    Call(Var("__builtin_sqrt"), [FloatLiteral(81.0)]),
    scope,
    9.0,
  )
  match
    mir.fold_float_const(
      Call(Var("__builtin_sqrt"), [FloatLiteral(-1.0)]),
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
