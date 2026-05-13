///|
fn linux_target() -> @target.Target {
  match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("linux target did not parse")
  }
}

///|
fn expect_const(
  mir : @mir.Program,
  expr : @parser.Expr,
  scope : @mir.Scope,
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
test "mir records target-specific scalar layout" {
  let source = "int main(void) { return 0; }"
  let darwin = @mir.lower(@parser.parse(source), @target.Target::default())
  let linux = @mir.lower(
    @parser.parse_for_target(source, linux_target()),
    linux_target(),
  )
  inspect(darwin.type_size(LongDouble), content="8")
  inspect(darwin.type_align(LongDouble), content="8")
  inspect(linux.type_size(LongDouble), content="16")
  inspect(linux.type_align(LongDouble), content="16")
  inspect(linux.type_size(Float16), content="2")
  inspect(linux.type_align(Float16), content="2")
}

///|
test "mir computes aggregate layout facts" {
  let source =
    #|struct S { char c; int i; short s; };
    #|struct __attribute__((packed)) P { char c; int i; short s; };
    #|struct B { unsigned a:3; unsigned b:5; unsigned c:9; };
    #|int main(void) { return 0; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.type_size(Struct("S")), content="12")
  inspect(mir.type_align(Struct("S")), content="4")
  match mir.field_layout(Struct("S"), "i") {
    Some({ offset: 4, size: 4, bit_width: None, .. }) => ()
    _ => abort("unexpected layout for S.i")
  }
  inspect(mir.type_size(Struct("P")), content="7")
  inspect(mir.type_align(Struct("P")), content="1")
  match mir.field_layout(Struct("B"), "b") {
    Some({ offset: 0, size: 4, bit_offset: 3, bit_width: Some(5), .. }) => ()
    _ => abort("unexpected layout for B.b")
  }
  match mir.field_layout(Struct("B"), "c") {
    Some({ offset: 0, size: 4, bit_offset: 8, bit_width: Some(9), .. }) => ()
    _ => abort("unexpected layout for B.c")
  }
}

///|
test "mir computes expression and global expression types" {
  let source =
    #|struct S { int x; double y; };
    #|struct S g;
    #|double callee(int x, ...);
    #|int main(void) { return 0; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  let scope = @mir.Scope::{
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
  inspect(mir.expr_type(MemberAccess(Var("s"), "y"), scope), content="Double")
  inspect(mir.global_expr_type(AddrOf(Var("g"))), content="Pointer(Struct(S))")
  inspect(
    mir.expr_type(Var("callee"), scope),
    content="FuncPtr(Double, [SInt], true)",
  )
}

///|
test "mir folds constants with target layout" {
  let source =
    #|struct S { char c; int i; int arr[3]; };
    #|int main(void) { return 0; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  let scope = @mir.Scope::empty()
  expect_const(mir, Sizeof(Struct("S")), scope, 20L)
  expect_const(
    mir,
    OffsetOf(Struct("S"), [OffsetField("arr"), OffsetIndex(2)]),
    scope,
    16L,
  )
  expect_const(mir, Binary("/", Number(1), Number(2)), scope, 0L)
  expect_const(
    mir,
    Binary(">", Cast(ULong, Unary("-", Number(1))), Number(1)),
    scope,
    1L,
  )
}
