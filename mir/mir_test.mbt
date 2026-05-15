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
fn expect_float_const(
  mir : @mir.Program,
  expr : @parser.Expr,
  scope : @mir.Scope,
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
fn expect_interp(source : String, expected : Int64) -> Unit {
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.interpret_i64("main", []) {
    Ok(value) =>
      if value != expected {
        abort(
          "unexpected MIR interpreter result: expected " +
          expected.to_string() +
          ", got " +
          value.to_string(),
        )
      }
    Err(err) => abort(err)
  }
}

///|
fn expect_body_interp(source : String, expected : Int64) -> Unit {
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.interpret_body_i64("main", []) {
    Ok(value) =>
      if value != expected {
        abort(
          "unexpected MIR body interpreter result: expected " +
          expected.to_string() +
          ", got " +
          value.to_string(),
        )
      }
    Err(err) => abort(err)
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
  let scope = @mir.Scope::empty()
  let long_double_builtin : @parser.Expr = Call(Var("__builtin_fabsl"), [
    FloatLiteral(1.0),
  ])
  inspect(darwin.expr_type(long_double_builtin, scope), content="LongDouble")
  inspect(linux.expr_type(long_double_builtin, scope), content="LongDouble")
  expect_const(darwin, SizeofExpr(long_double_builtin), scope, 8L)
  expect_const(linux, SizeofExpr(long_double_builtin), scope, 16L)
}

///|
test "mir owns function declaration metadata" {
  let source =
    #|int ext(long x);
    #|static inline int helper(int x) { return x; }
    #|int main(void) { return helper(1); }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.decls.length(), content="3")
  inspect(mir.decls[0].name, content="ext")
  inspect(mir.decls[0].has_body, content="false")
  inspect(mir.decls[0].params[0].name, content="x")
  inspect(mir.decls[0].params[0].ty, content="SLong")
  inspect(mir.decls[1].name, content="helper")
  inspect(mir.decls[1].is_static, content="true")
  inspect(mir.decls[1].is_inline, content="true")
  inspect(mir.decls[1].has_body, content="true")
  inspect(mir.decls[2].name, content="main")
  inspect(mir.decls[2].has_body, content="true")
}

///|
test "mir owns global declaration metadata" {
  let source =
    #|extern int extg;
    #|static int sg = 7;
    #|int arr[2];
    #|int main(void) { return sg; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.global_decls.length(), content="3")
  inspect(mir.global_decls[0].name, content="extg")
  inspect(mir.global_decls[0].is_extern, content="true")
  inspect(mir.global_decls[0].has_init, content="false")
  inspect(mir.global_decls[1].name, content="sg")
  inspect(mir.global_decls[1].is_static, content="true")
  inspect(mir.global_decls[1].has_init, content="true")
  inspect(mir.global_decls[2].name, content="arr")
  inspect(mir.global_decls[2].ty, content="Array(SInt, 2)")
  inspect(mir.global_decls[2].has_init, content="false")
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
  inspect(
    mir.expr_type(Binary("<<", Number(1), Number(40)), scope),
    content="ULongLong",
  )
  inspect(mir.expr_type(MemberAccess(Var("s"), "y"), scope), content="Double")
  inspect(mir.global_expr_type(AddrOf(Var("g"))), content="Pointer(Struct(S))")
  inspect(
    mir.expr_type(Var("callee"), scope),
    content="FuncPtr(Double, [SInt], true)",
  )
}

///|
test "mir lowers scalar function bodies into MIR-owned statements" {
  let source =
    #|int main(void) {
    #|  int x = 6;
    #|  int y = 7;
    #|  return x * y;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  let body = mir.bodies["main"]
  inspect(body.locals.length(), content="2")
  match mir.interpret_body_i64("main", []) {
    Ok(value) => inspect(value, content="42")
    Err(err) => abort(err)
  }
}

///|
test "mir body interpreter executes calls branches and loops" {
  let source =
    #|int add_if_odd(int acc, int x) {
    #|  if (x % 2) {
    #|    return acc + x;
    #|  }
    #|  return acc;
    #|}
    #|int main(void) {
    #|  int i = 0;
    #|  int sum = 0;
    #|  while (i < 10) {
    #|    sum = add_if_odd(sum, i);
    #|    i = i + 1;
    #|  }
    #|  return sum;
    #|}
  expect_body_interp(source, 25L)
}

///|
test "mir body lowering uses scoped stable local ids" {
  let source =
    #|int main(void) {
    #|  int x = 1;
    #|  {
    #|    int x = 40;
    #|    x = x + 2;
    #|  }
    #|  return x;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  let body = mir.bodies["main"]
  inspect(body.locals.length(), content="2")
  expect_body_interp(source, 1L)
}

///|
test "mir body interpreter executes for break and continue" {
  let source =
    #|int main(void) {
    #|  int sum = 0;
    #|  for (int i = 0; i < 8; i = i + 1) {
    #|    if (i == 2) continue;
    #|    if (i == 6) break;
    #|    sum = sum + i;
    #|  }
    #|  return sum;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 13L)
}

///|
test "mir body interpreter executes do while break and continue" {
  let source =
    #|int main(void) {
    #|  int i = 0;
    #|  int sum = 0;
    #|  do {
    #|    i = i + 1;
    #|    if (i == 2) continue;
    #|    if (i == 6) break;
    #|    sum = sum + i;
    #|  } while (i < 8);
    #|  return sum;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 13L)
}

///|
test "mir body interpreter executes switch fallthrough" {
  let source =
    #|int main(void) {
    #|  int total = 0;
    #|  for (int i = 0; i < 5; i = i + 1) {
    #|    switch (i) {
    #|    case 0:
    #|      total = total + 3;
    #|      break;
    #|    case 1:
    #|    case 2:
    #|      total = total + 5;
    #|      break;
    #|    case 4:
    #|      total = total + 7;
    #|    default:
    #|      total = total + 11;
    #|    }
    #|  }
    #|  return total;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter executes simple goto" {
  let source =
    #|int main(void) {
    #|  int total = 0;
    #|  int i = 0;
    #|loop:
    #|  i = i + 1;
    #|  if (i == 2) goto skip;
    #|  total = total + i;
    #|skip:
    #|  if (i < 5) goto loop;
    #|  return total;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 13L)
}

///|
test "mir body interpreter executes scalar updates" {
  let source =
    #|int main(void) {
    #|  int total = 0;
    #|  int i = 0;
    #|loop:
    #|  i++;
    #|  if (i == 2) goto skip;
    #|  total += i;
    #|skip:
    #|  if (i < 5) goto loop;
    #|  return total;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 13L)
}

///|
test "mir body interpreter preserves postfix update value" {
  let source =
    #|int main(void) {
    #|  int i = 4;
    #|  int old = i++;
    #|  return old * 10 + i;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 45L)
}

///|
test "mir body interpreter evaluates scalar address dereference cancellation" {
  let source =
    #|int main(void) {
    #|  int x = 4;
    #|  *&x += 5;
    #|  return *&x;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 9L)
}

///|
test "mir body interpreter handles scalar local pointers" {
  let source =
    #|int main(void) {
    #|  int x = 4;
    #|  int *p = &x;
    #|  *p += 5;
    #|  return x + *p;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 18L)
}

///|
test "mir body interpreter handles scalar local arrays" {
  let source =
    #|int main(void) {
    #|  int a[3];
    #|  a[0] = 4;
    #|  a[1] = a[0] + 5;
    #|  int *p = &a[1];
    #|  p[1] = 7;
    #|  return a[0] + a[1] + a[2];
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 20L)
}

///|
test "mir body interpreter handles scalar memory prefix updates" {
  let source =
    #|struct S { int x; };
    #|int main(void) {
    #|  int x = 4;
    #|  int *p = &x;
    #|  int a[2];
    #|  struct S s;
    #|  a[0] = 2;
    #|  s.x = 7;
    #|  ++*p;
    #|  --a[0];
    #|  ++s.x;
    #|  return x + a[0] + s.x;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 14L)
}

///|
test "mir body interpreter handles side effecting scalar memory prefix updates" {
  let source =
    #|int main(void) {
    #|  int a[2];
    #|  int i = 0;
    #|  a[0] = 4;
    #|  int got = ++a[i++];
    #|  return got * 10 + a[0] + i;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 56L)
}

///|
test "mir body interpreter handles side effecting scalar memory compound updates" {
  let source =
    #|int main(void) {
    #|  int a[2];
    #|  int i = 0;
    #|  a[0] = 4;
    #|  int got = (a[i++] += 3);
    #|  return got * 10 + a[0] + i;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 78L)
}

///|
test "mir body interpreter handles side effecting non-additive compound updates" {
  let source =
    #|int main(void) {
    #|  int a[2];
    #|  int i = 0;
    #|  a[0] = 4;
    #|  int got = (a[i++] *= 3);
    #|  return got * 10 + a[0] + i;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 133L)
}

///|
test "mir body interpreter handles scalar memory postfix updates" {
  let source =
    #|struct S { int x; };
    #|int main(void) {
    #|  int x = 4;
    #|  int *p = &x;
    #|  int a[2];
    #|  int i = 0;
    #|  struct S s;
    #|  a[0] = 9;
    #|  s.x = 7;
    #|  int old_p = (*p)++;
    #|  int old_a = a[i++]--;
    #|  int old_s = s.x++;
    #|  return old_p * 1000 + old_a * 100 + old_s * 10 + x + a[0] + s.x + i;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 4992L)
}

///|
test "mir body lowering folds scalar builtin calls" {
  let source =
    #|int main(void) {
    #|  int x = 0;
    #|  return __builtin_constant_p(1 + 2) * 10 +
    #|    __builtin_constant_p(x) +
    #|    __builtin_unpredictable(5);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 15L)
}

///|
test "mir body lowering handles side effect free identity builtins" {
  let source =
    #|int main(void) {
    #|  int x = 4;
    #|  void *p = (void *)32;
    #|  void *ra = (void *)77;
    #|  return __builtin_expect(x, 1) +
    #|    __builtin_expect_with_probability(x, 0, 0.9) +
    #|    ((unsigned long)__builtin_assume_aligned(p, 16) == 32ul) +
    #|    ((unsigned long)__builtin_extract_return_addr(ra) == 77ul) +
    #|    ((unsigned long)__builtin_frob_return_addr(ra) == 77ul);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 11L)
}

///|
test "mir body interpreter handles no-op builtins" {
  let source =
    #|int main(void) {
    #|  int side = 0;
    #|  __builtin_prefetch((void *)(long)(side += 1), 0, 0);
    #|  __builtin_assume(side += 10);
    #|  return side + 41;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles scalar globals" {
  let source =
    #|int g = 5;
    #|int h;
    #|int bump(void) {
    #|  g += 3;
    #|  h = g++;
    #|  return h;
    #|}
    #|int main(void) {
    #|  h = 2;
    #|  return bump() + g + h;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("bump"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 25L)
}

///|
test "mir body interpreter handles scalar global arrays" {
  let source =
    #|int a[3];
    #|int main(void) {
    #|  a[0] = 4;
    #|  a[1] = a[0] + 5;
    #|  int *p = &a[1];
    #|  p[1] = 7;
    #|  return a[0] + a[1] + a[2];
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 20L)
}

///|
test "mir body interpreter handles initialized scalar global arrays" {
  let source =
    #|int a[3] = {1, 2, 3};
    #|int main(void) {
    #|  a[1] += 5;
    #|  return a[0] + a[1] + a[2];
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 11L)
}

///|
test "mir body lowering keeps side effecting ignored builtin operands unsupported" {
  let source =
    #|int main(void) {
    #|  int x = 4;
    #|  int side = 0;
    #|  return __builtin_expect(x, side += 1);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="false")
}

///|
test "mir body interpreter handles scalar aggregate fields" {
  let source =
    #|struct S { int x; unsigned char y; };
    #|int main(void) {
    #|  struct S s;
    #|  s.x = 4;
    #|  s.y = 250 + 10;
    #|  return s.x + s.y;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 8L)
}

///|
test "mir body lowering keeps nested aggregate fields unsupported" {
  let source =
    #|struct Inner { int z; };
    #|struct S { struct Inner inner; };
    #|int main(void) {
    #|  struct S s;
    #|  s.inner.z = 7;
    #|  return s.inner.z;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="false")
}

///|
test "mir body lowering refuses unsupported parser constructs" {
  let source =
    #|int main(void) {
    #|  goto *0;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="false")
  match mir.interpret_body_i64("main", []) {
    Ok(_) => abort("expected missing MIR body")
    Err(err) => inspect(err.contains("no MIR body"), content="true")
  }
}

///|
test "mir folds constants with target layout" {
  let source =
    #|struct S { char c; int i; int arr[3]; };
    #|struct S global_s;
    #|int global_x;
    #|char global_buf[16];
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
  let local_types : Map[String, @parser.Type] = {}
  local_types["local_x"] = SInt
  local_types["local_buf"] = Array(SChar, 16)
  local_types["local_s"] = Struct("S")
  let local_scope : @mir.Scope = { locals: local_types, current_func: "main" }
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

///|
test "mir interpreter executes scalar calls and locals" {
  let source =
    #|int helper(int x) { return x * 2; }
    #|int main(void) {
    #|  int a = 20;
    #|  return helper(a) + 2;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter executes integer control flow and globals" {
  let source =
    #|int g = 1;
    #|int bump(int n) {
    #|  g += n;
    #|  return g;
    #|}
    #|int main(void) {
    #|  int sum = 0;
    #|  for (int i = 0; i < 8; i++) {
    #|    if (i == 2) continue;
    #|    if (i == 6) break;
    #|    sum += i;
    #|  }
    #|  while (sum < 20) {
    #|    sum++;
    #|  }
    #|  return bump(sum) + (sum == 20 ? 21 : 0);
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter evaluates scalar address dereference cancellation" {
  let source =
    #|int main(void) {
    #|  int x = 4;
    #|  *&x += 5;
    #|  return *&x;
    #|}
  expect_interp(source, 9L)
}

///|
test "mir interpreter evaluates integer overflow builtins" {
  let source =
    #|int main(void) {
    #|  int i = 0;
    #|  unsigned u = 0;
    #|  long long l = 0;
    #|  unsigned long long ul = 0;
    #|  int total = 0;
    #|  total += __builtin_add_overflow(1, 2, &i);
    #|  if (i != 3) return 10;
    #|  total += __builtin_add_overflow(2147483647, 1, &i);
    #|  if (i >= 0) return 20;
    #|  total += __builtin_sub_overflow(0u, 1u, &u);
    #|  if (u != 4294967295u) return 30;
    #|  total += __builtin_mul_overflow(50000, 50000, &i);
    #|  total += __builtin_add_overflow(l, 1LL, &l);
    #|  if (l != 1LL) return 40;
    #|  total += __builtin_ssubll_overflow(-9223372036854775807LL - 1LL, 1LL, &l);
    #|  if (l != 9223372036854775807LL) return 50;
    #|  total += __builtin_uaddll_overflow(0xffffffffffffffffULL, 1ULL, &ul);
    #|  if (ul != 0ULL) return 60;
    #|  total += __builtin_smulll_overflow(3037000500LL, 3037000500LL, &l);
    #|  if (l != -9223372036709301616LL) return 70;
    #|  total += __builtin_umulll_overflow(0xffffffffffffffffULL, 2ULL, &ul);
    #|  if (ul != 0xfffffffffffffffeULL) return 80;
    #|  return total;
    #|}
  expect_interp(source, 7L)
}

///|
test "mir interpreter evaluates scalar compound literals" {
  let source =
    #|int main(void) {
    #|  int a = (int){40};
    #|  unsigned char b = (unsigned char){255 + 1};
    #|  long long c = (long long){-9223372036854775807LL - 1LL};
    #|  unsigned long long d = (unsigned long long){0xffffffffffffffffULL};
    #|  return a + b + (c < 0 ? 2 : 0) + (d == 0xffffffffffffffffULL ? 0 : 100);
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter applies target layout and integer casts" {
  let source =
    #|int main(void) {
    #|  unsigned char x = 255 + 1;
    #|  return sizeof(long double) + x;
    #|}
  let darwin = @mir.lower(@parser.parse(source), @target.Target::default())
  let linux = @mir.lower(
    @parser.parse_for_target(source, linux_target()),
    linux_target(),
  )
  match darwin.interpret_i64("main", []) {
    Ok(value) => inspect(value, content="8")
    Err(err) => abort(err)
  }
  match linux.interpret_i64("main", []) {
    Ok(value) => inspect(value, content="16")
    Err(err) => abort(err)
  }
}

///|
test "mir interpreter models frame and return address nullness" {
  let source =
    #|int main(void) {
    #|  void *fa = __builtin_frame_address(0);
    #|  void *ra = __builtin_return_address(0);
    #|  if (fa == 0) return 1;
    #|  if (ra == 0) return 2;
    #|  if (__builtin_frame_address(1) != 0) return 3;
    #|  if (__builtin_return_address(1) != 0) return 4;
    #|  if (__builtin_extract_return_addr(ra) != ra) return 5;
    #|  if (__builtin_frob_return_addr(ra) != ra) return 6;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models string literal scalar facts" {
  let source =
    #|int main(void) {
    #|  if (sizeof("abc") != 4) return 1;
    #|  if (__alignof__("abc") != 1) return 2;
    #|  if (!"abc") return 3;
    #|  if (*"abc" != 'a') return 4;
    #|  if ("abc"[1] != 'b') return 5;
    #|  if ("abc"[3] != 0) return 6;
    #|  if (__func__[0] != 'm') return 7;
    #|  if (__builtin_strlen("hello") != 5) return 8;
    #|  if (*((char *)"abc") != 'a') return 9;
    #|  if (((char *)"abc")[2] != 'c') return 10;
    #|  if (((unsigned char *)"abc")[3] != 0) return 11;
    #|  if (__builtin_strlen((const char *)"hello") != 5) return 12;
    #|  if (*("abcd" + 1) != 'b') return 13;
    #|  if ((1 + "abcd")[2] != 'd') return 14;
    #|  int side = 0;
    #|  if (*((const char *)"abcd" + (side += 2)) != 'c') return 15;
    #|  if (side != 2) return 16;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models string literal pointer locals" {
  let source =
    #|int main(void) {
    #|  char *s = (char *)"abc";
    #|  char *tail = s + 1;
    #|  char *u = (char *)"abba";
    #|  char *hay = (char *)"abcde";
    #|  char *needle = (char *)"cd";
    #|  if (*s != 'a') return 1;
    #|  if (tail[1] != 'c') return 2;
    #|  if (__builtin_strlen(s) != 3) return 3;
    #|  if (__builtin_strlen(tail) != 2) return 4;
    #|  if (__builtin_strcmp(s, "abc") != 0) return 5;
    #|  if (__builtin_strncmp(tail, "bc", 2) != 0) return 6;
    #|  if (__builtin_memcmp(tail, "bc", 2) != 0) return 7;
    #|  if (__builtin_strchr(s, 'b') != s + 1) return 8;
    #|  if (__builtin_strchr(tail, 'a') != 0) return 9;
    #|  if (__builtin_strchr(s, 0) != s + 3) return 10;
    #|  if (__builtin_strrchr(u, 'b') != u + 2) return 11;
    #|  if (__builtin_strrchr(u + 1, 'a') != u + 3) return 12;
    #|  if (__builtin_memchr(s, 'b', 2) != s + 1) return 13;
    #|  if (__builtin_memchr(s, 0, 4) != s + 3) return 14;
    #|  if (__builtin_strstr(hay + 1, needle) != hay + 2) return 15;
    #|  if (__builtin_strstr(hay, needle + 1) != hay + 3) return 16;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models global string pointer initializers" {
  let source =
    #|char *g = "abc";
    #|char *tail = (char *)"abc" + 1;
    #|int main(void) {
    #|  if (g[0] != 'a') return 1;
    #|  if (tail[0] != 'b') return 2;
    #|  if (__builtin_strlen(g) != 3) return 3;
    #|  if (__builtin_strlen(tail) != 2) return 4;
    #|  if (__builtin_strchr(g, 'c') != g + 2) return 5;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models global string array initializers" {
  let source =
    #|char g[] = "abc";
    #|unsigned char u[] = { 'x', 'y', 0, 'z' };
    #|char padded[5] = { 'q' };
    #|int main(void) {
    #|  if (g[0] != 'a') return 1;
    #|  if (g[3] != 0) return 2;
    #|  if (__builtin_strlen(g) != 3) return 3;
    #|  if (__builtin_strcmp(g, "abc") != 0) return 4;
    #|  if (__builtin_strlen((char *)u) != 2) return 5;
    #|  if (u[3] != 'z') return 6;
    #|  if (padded[0] != 'q') return 7;
    #|  if (padded[1] != 0 || padded[4] != 0) return 8;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models local string array initializers" {
  let source =
    #|int main(void) {
    #|  char s[] = "abc";
    #|  unsigned char u[4] = { 'x', 'y', 0, 'z' };
    #|  char padded[5] = { 'q' };
    #|  char *tail = s + 1;
    #|  if (s[0] != 'a') return 1;
    #|  if (s[3] != 0) return 2;
    #|  if (__builtin_strlen(s) != 3) return 3;
    #|  s[1] = 'z';
    #|  if (__builtin_strcmp(s, "azc") != 0) return 4;
    #|  *tail = 'b';
    #|  if (__builtin_strcmp(s, "abc") != 0) return 5;
    #|  if (__builtin_strlen((char *)u) != 2) return 6;
    #|  if (u[3] != 'z') return 7;
    #|  if (padded[0] != 'q') return 8;
    #|  if (padded[1] != 0 || padded[4] != 0) return 9;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models string array element addresses" {
  let source =
    #|char g[] = "abc";
    #|char *gp = &g[1];
    #|int main(void) {
    #|  char s[] = "wxyz";
    #|  char *p = &s[2];
    #|  if (*p != 'y') return 1;
    #|  *p = 'q';
    #|  if (__builtin_strcmp(s, "wxqz") != 0) return 2;
    #|  if (*gp != 'b') return 3;
    #|  if (__builtin_strchr(g, 'c') != &g[2]) return 4;
    #|  if (__builtin_strchr(s, 'z') != &s[3]) return 5;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models embedded nul string literal lengths" {
  let source =
    #|int main(void) {
    #|  char *dst = (char *)__builtin_alloca(8);
    #|  if (sizeof("a\0bc") != 5) return 1;
    #|  if (__builtin_strlen("a\0bc") != 1) return 2;
    #|  if (__builtin_stpcpy(dst, "a\0bc") != dst + 1) return 3;
    #|  if (__builtin_stpncpy(dst, "a\0bc", 4) != dst + 1) return 4;
    #|  if (__builtin___strlcpy_chk(dst, "a\0bc", 8, 8) != 1) return 5;
    #|  if (__builtin___strlcat_chk(dst, "a\0bc", 0, 8) != 1) return 6;
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"%s", "a\0bc") != 1) return 7;
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"%.3s", "a\0bc") != 1) return 8;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models string builtin return sizes" {
  let source =
    #|int main(void) {
    #|  return sizeof(__builtin_strlen("abc")) +
    #|    sizeof(__builtin_memchr("abc", 'a', 3)) +
    #|    sizeof(__builtin_strchr("abc", 'a')) +
    #|    sizeof(__builtin_strcmp("a", "b")) +
    #|    sizeof(__builtin_strncmp("a", "b", 1)) +
    #|    sizeof(__builtin_memcmp("a", "b", 1));
    #|}
  expect_interp(source, 36L)
}

///|
test "mir interpreter models string alias builtin return sizes" {
  let source =
    #|char *dst;
    #|char *src;
    #|int main(void) {
    #|  return sizeof(__builtin_mempcpy(dst, src, 1)) +
    #|    sizeof(__builtin___mempcpy_chk(dst, src, 1, 16)) +
    #|    sizeof(__builtin_strcat(dst, src)) +
    #|    sizeof(__builtin_stpcpy(dst, src)) +
    #|    sizeof(__builtin___stpcpy_chk(dst, src, 16)) +
    #|    sizeof(__builtin_strncpy(dst, src, 1)) +
    #|    sizeof(__builtin_stpncpy(dst, src, 1)) +
    #|    sizeof(__builtin___stpncpy_chk(dst, src, 1, 16)) +
    #|    sizeof(__builtin_strncat(dst, src, 1));
    #|}
  expect_interp(source, 72L)
}

///|
test "mir interpreter models string end pointer builtin returns" {
  let source =
    #|int main(void) {
    #|  char *dst = (char *)__builtin_alloca(16);
    #|  int side = 0;
    #|  if (__builtin_mempcpy(((side += 1), dst), "uv", side + 1) != dst + 2) return 1;
    #|  if (__builtin___mempcpy_chk(dst + 2, (const char *)"wx", 2, 16) != dst + 4) return 2;
    #|  if (__builtin_stpcpy(((side += 1), dst), "hi") != dst + 2) return 3;
    #|  if (__builtin___stpcpy_chk(dst, (const char *)"ok", 16) != dst + 2) return 4;
    #|  if (__builtin_stpncpy(dst, "abc", 2) != dst + 2) return 5;
    #|  if (__builtin_stpncpy(dst, "abc", 6) != dst + 3) return 6;
    #|  if (__builtin___stpncpy_chk(((side += 1), dst), (const char *)"cd", 2, 16) != dst + 2) return 7;
    #|  if (side != 3) return 8;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models floating builtin return sizes" {
  let source =
    #|int main(void) {
    #|  return sizeof(__builtin_fabsf(-1.0f)) +
    #|    sizeof(__builtin_fabs(-1.0)) +
    #|    sizeof(__builtin_fabsl(-1.0L)) +
    #|    sizeof(__builtin_copysignf(1.0f, -1.0f)) +
    #|    sizeof(__builtin_copysign(1.0, -1.0)) +
    #|    sizeof(__builtin_copysignl(1.0L, -1.0L)) +
    #|    sizeof(__builtin_sqrtf(4.0f)) +
    #|    sizeof(__builtin_sqrt(4.0)) +
    #|    sizeof(__builtin_sqrtl(4.0L)) +
    #|    sizeof(__builtin_nanf("")) +
    #|    sizeof(__builtin_nan("")) +
    #|    sizeof(__builtin_nanl("")) +
    #|    sizeof(__builtin_huge_valf()) +
    #|    sizeof(__builtin_huge_val()) +
    #|    sizeof(__builtin_huge_vall()) +
    #|    sizeof(__builtin_inff()) +
    #|    sizeof(__builtin_inf()) +
    #|    sizeof(__builtin_infl());
    #|}
  expect_interp(source, 120L)
}

///|
test "mir interpreter models floating classification return sizes" {
  let source =
    #|int main(void) {
    #|  return sizeof(__builtin_isgreater(2.0, 1.0)) +
    #|    sizeof(__builtin_isgreaterequal(2.0, 2.0)) +
    #|    sizeof(__builtin_isless(1.0, 2.0)) +
    #|    sizeof(__builtin_islessequal(2.0, 2.0)) +
    #|    sizeof(__builtin_islessgreater(1.0, 2.0)) +
    #|    sizeof(__builtin_isunordered(__builtin_nan(""), 1.0)) +
    #|    sizeof(__builtin_isnan(__builtin_nan(""))) +
    #|    sizeof(__builtin_isnanf(__builtin_nanf(""))) +
    #|    sizeof(__builtin_isnanl(__builtin_nanl(""))) +
    #|    sizeof(__builtin_isinf(__builtin_inf())) +
    #|    sizeof(__builtin_isinff(__builtin_inff())) +
    #|    sizeof(__builtin_isinfl(__builtin_infl())) +
    #|    sizeof(__builtin_isfinite(1.0)) +
    #|    sizeof(__builtin_isfinitef(1.0f)) +
    #|    sizeof(__builtin_isfinitel(1.0L)) +
    #|    sizeof(__builtin_isnormal(1.0)) +
    #|    sizeof(__builtin_isnormalf(1.0f)) +
    #|    sizeof(__builtin_isnormall(1.0L)) +
    #|    sizeof(__builtin_signbit(-1.0)) +
    #|    sizeof(__builtin_signbitf(-1.0f)) +
    #|    sizeof(__builtin_signbitl(-1.0L));
    #|}
  expect_interp(source, 84L)
}

///|
test "mir interpreter models alloca return size and nullness" {
  let source =
    #|int main(void) {
    #|  int n = 16;
    #|  void *p = __builtin_alloca(n += 1);
    #|  if (n != 17) return 1;
    #|  if (p == 0) return 2;
    #|  char *a = __builtin_alloca(n += 2);
    #|  char *b = __builtin_alloca(n += 3);
    #|  if (n != 22) return 3;
    #|  if (a == 0 || b == 0) return 4;
    #|  if (a == b || a == p || b == p) return 5;
    #|  return sizeof(__builtin_alloca(16)) + 34;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models fortified builtin return sizes" {
  let source =
    #|int main(void) {
    #|  return sizeof(__builtin___memcpy_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___memset_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___memmove_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___strcpy_chk(0, 0, 0)) +
    #|    sizeof(__builtin___strcat_chk(0, 0, 0)) +
    #|    sizeof(__builtin___strncpy_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___strncat_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___strlcpy_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___strlcat_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___snprintf_chk(0, 0, 0, 0, 0)) +
    #|    sizeof(__builtin___vsnprintf_chk(0, 0, 0, 0, 0, 0)) +
    #|    sizeof(__builtin___sprintf_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___vsprintf_chk(0, 0, 0, 0, 0)) +
    #|    sizeof(__builtin___printf_chk(0, 0)) +
    #|    sizeof(__builtin___fprintf_chk(0, 0, 0)) +
    #|    sizeof(__builtin___vfprintf_chk(0, 0, 0, 0));
    #|}
  expect_interp(source, 100L)
}

///|
test "mir interpreter models atomic builtin return sizes" {
  let source =
    #|int atomic_int_value;
    #|long atomic_long_value;
    #|_Atomic int c11_atomic_int_value;
    #|int expected_atomic_value;
    #|int main(void) {
    #|  return sizeof(__atomic_load_n(&atomic_int_value, 0)) +
    #|    sizeof(__atomic_load_n(&atomic_long_value, 0)) +
    #|    sizeof(__c11_atomic_load(&c11_atomic_int_value, 0)) +
    #|    sizeof(__atomic_add_fetch(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_sub_fetch(&atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_fetch_add(&c11_atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_fetch_sub(&c11_atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_fetch_and(&c11_atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_fetch_or(&c11_atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_fetch_xor(&c11_atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_exchange(&c11_atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_compare_exchange_strong(&c11_atomic_int_value, &expected_atomic_value, 1, 0, 0)) +
    #|    sizeof(__c11_atomic_compare_exchange_weak(&c11_atomic_int_value, &expected_atomic_value, 1, 0, 0)) +
    #|    sizeof(__atomic_store_n(&atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_store(&c11_atomic_int_value, 1, 0)) +
    #|    sizeof(__sync_synchronize());
    #|}
  expect_interp(source, 50L)
}

///|
test "mir interpreter models extended atomic builtin return sizes" {
  let source =
    #|int atomic_int_value;
    #|int expected_atomic_value;
    #|int desired_atomic_value;
    #|int main(void) {
    #|  return sizeof(__atomic_and_fetch(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_or_fetch(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_xor_fetch(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_nand_fetch(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_fetch_add(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_fetch_sub(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_fetch_and(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_fetch_or(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_fetch_xor(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_fetch_nand(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_exchange_n(&atomic_int_value, 1, 0)) +
    #|    sizeof(__sync_val_compare_and_swap(&atomic_int_value, 0, 1)) +
    #|    sizeof(__sync_fetch_and_add(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_sub(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_and(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_or(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_xor(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_nand(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_max(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_min(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_umax(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_umin(&atomic_int_value, 1)) +
    #|    sizeof(__sync_add_and_fetch(&atomic_int_value, 1)) +
    #|    sizeof(__sync_sub_and_fetch(&atomic_int_value, 1)) +
    #|    sizeof(__sync_and_and_fetch(&atomic_int_value, 1)) +
    #|    sizeof(__sync_or_and_fetch(&atomic_int_value, 1)) +
    #|    sizeof(__sync_xor_and_fetch(&atomic_int_value, 1)) +
    #|    sizeof(__sync_nand_and_fetch(&atomic_int_value, 1)) +
    #|    sizeof(__sync_swap(&atomic_int_value, 1)) +
    #|    sizeof(__sync_lock_test_and_set(&atomic_int_value, 1)) +
    #|    sizeof(__atomic_test_and_set(&atomic_int_value, 0)) +
    #|    sizeof(__atomic_compare_exchange(&atomic_int_value, &expected_atomic_value, &desired_atomic_value, 0, 0, 0)) +
    #|    sizeof(__atomic_compare_exchange_n(&atomic_int_value, &expected_atomic_value, desired_atomic_value, 0, 0, 0)) +
    #|    sizeof(__sync_bool_compare_and_swap(&atomic_int_value, 0, 1)) +
    #|    sizeof(__atomic_always_lock_free(4, 0)) +
    #|    sizeof(__atomic_is_lock_free(4, 0)) +
    #|    sizeof(__c11_atomic_is_lock_free(4)) +
    #|    sizeof(__atomic_clear(&atomic_int_value, 0)) +
    #|    sizeof(__atomic_exchange(&atomic_int_value, &desired_atomic_value, &expected_atomic_value, 0)) +
    #|    sizeof(__atomic_load(&atomic_int_value, &expected_atomic_value, 0)) +
    #|    sizeof(__atomic_store(&atomic_int_value, &desired_atomic_value, 0)) +
    #|    sizeof(__atomic_thread_fence(0)) +
    #|    sizeof(__atomic_signal_fence(0)) +
    #|    sizeof(__c11_atomic_thread_fence(0)) +
    #|    sizeof(__c11_atomic_signal_fence(0)) +
    #|    sizeof(__sync_lock_release(&atomic_int_value));
    #|}
  expect_interp(source, 127L)
}

///|
test "mir interpreter models scalar builtin return sizes" {
  let source =
    #|int main(void) {
    #|  return sizeof(__builtin_clz(8)) +
    #|    sizeof(__builtin_clzl(8ul)) +
    #|    sizeof(__builtin_clzll(8ull)) +
    #|    sizeof(__builtin_ctz(40)) +
    #|    sizeof(__builtin_ctzl(48ul)) +
    #|    sizeof(__builtin_ctzll(48ull)) +
    #|    sizeof(__builtin_ffs(8u)) +
    #|    sizeof(__builtin_ffsl(16ul)) +
    #|    sizeof(__builtin_ffsll(32ull)) +
    #|    sizeof(__builtin_popcount(0xf0f0u)) +
    #|    sizeof(__builtin_popcountl(0xf0f0ul)) +
    #|    sizeof(__builtin_popcountll(0xf0f0ull)) +
    #|    sizeof(__builtin_parity(0xf0f1u)) +
    #|    sizeof(__builtin_parityl(0xf0f1ul)) +
    #|    sizeof(__builtin_parityll(0xf0f1ull)) +
    #|    sizeof(__builtin_bswap16(0x0102)) +
    #|    sizeof(__builtin_bswap32(0x01020304u)) +
    #|    sizeof(__builtin_bswap64(0x0102030405060708ull)) +
    #|    sizeof(__builtin_bswap((unsigned short)0x0102)) +
    #|    sizeof(__builtin_bswap((unsigned int)0x01020304)) +
    #|    sizeof(__builtin_bswap((unsigned long long)0x0102030405060708)) +
    #|    sizeof(__builtin_abs(-7)) +
    #|    sizeof(__builtin_labs(-123456789L)) +
    #|    sizeof(__builtin_llabs(-123456789LL)) +
    #|    sizeof(__builtin_is_aligned(32, 16)) +
    #|    sizeof(__builtin_align_up(33, 16)) +
    #|    sizeof(__builtin_align_down((long)47, 16)) +
    #|    sizeof(__builtin_align_up((unsigned long long)0x1234567890, 256)) +
    #|    sizeof(__builtin_rotateleft32(0x12345678u, 8)) +
    #|    sizeof(__builtin_rotateright32(0x12345678u, 8)) +
    #|    sizeof(__builtin_rotateleft64(0x0123456789abcdefull, 16)) +
    #|    sizeof(__builtin_rotateright64(0x0123456789abcdefull, 16)) +
    #|    sizeof(__builtin_rotateleft((unsigned int)0x12345678, 8)) +
    #|    sizeof(__builtin_rotateright((unsigned long long)0x0123456789abcdef, 16)) +
    #|    sizeof(__builtin_expect((long)0x1234567890, 0L)) +
    #|    sizeof(__builtin_expect_with_probability((long long)0x1234567890, 0LL, 0.5)) +
    #|    sizeof(__builtin_unpredictable((unsigned long long)0x1234567890)) +
    #|    sizeof(__builtin_assume_aligned((char *)0, 16)) +
    #|    sizeof(__builtin_constant_p(1));
    #|}
  expect_interp(source, 201L)
}

///|
test "mir interpreter models overflow builtin return sizes" {
  let source =
    #|int main(void) {
    #|  return sizeof(__builtin_add_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_sub_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_mul_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_sadd_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_saddl_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_saddll_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_uadd_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_uaddl_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_uaddll_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_ssub_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_ssubl_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_ssubll_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_usub_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_usubl_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_usubll_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_smul_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_smull_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_smulll_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_umul_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_umull_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_umulll_overflow(1, 2, 0));
    #|}
  expect_interp(source, 21L)
}

///|
test "mir interpreter models void builtin return sizes" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|void *ptr;
    #|int variadic(int last, ...) {
    #|  va_list ap;
    #|  return sizeof(__builtin_va_start(ap, last)) +
    #|    sizeof(__builtin_va_copy(ap, ap)) +
    #|    sizeof(__builtin_va_end(ap));
    #|}
    #|int main(void) {
    #|  return sizeof(__builtin_unreachable()) +
    #|    sizeof(__builtin_trap()) +
    #|    sizeof(__builtin_assume(1)) +
    #|    sizeof(__builtin_prefetch(ptr)) +
    #|    sizeof(__builtin_bzero(ptr, 0)) +
    #|    variadic(0, 1);
    #|}
  expect_interp(source, 0L)
}

///|
test "mir interpreter evaluates prefetch address argument" {
  let source =
    #|int main(void) {
    #|  int side = 0;
    #|  __builtin_prefetch((void *)(long)(side += 1), 0, 0);
    #|  __builtin_assume(side += 10);
    #|  return side + 41;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter evaluates ignored hint operand side effects" {
  let source =
    #|int g = 0;
    #|int bump(void) {
    #|  g += 1;
    #|  return 0;
    #|}
    #|int main(void) {
    #|  int x = 4;
    #|  int y = 0;
    #|  int side = 0;
    #|  int total = 0;
    #|  total += __builtin_expect(x, (side += 1, 1 / y));
    #|  total += __builtin_expect_with_probability(x, bump(), 0.9);
    #|  if ((unsigned long)__builtin_assume_aligned((void*)32, 16, (side += 2, 1 / y)) != 32ul) return 1;
    #|  return total + side + g + 30;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models literal object size builtins" {
  let source =
    #|struct S { int x; char buf[9]; };
    #|char global_buf[16];
    #|struct S global_s;
    #|int main(void) {
    #|  int side = 0;
    #|  int x;
    #|  char buf[16];
    #|  struct S local_s;
    #|  if (__builtin_object_size("abc", 0) != 4) return 1;
    #|  if (__builtin_object_size((const char *)"abc", 1) != 4) return 2;
    #|  if (__builtin_dynamic_object_size("hello", 2) != 6) return 3;
    #|  if (__builtin_dynamic_object_size((const void *)"hello", 3) != 6) return 4;
    #|  if (__builtin_object_size((void *)1, 0) + 1 != 0) return 5;
    #|  if (__builtin_object_size((void *)1, 2) != 0) return 6;
    #|  if (__builtin_dynamic_object_size((void *)(long)(side += 1), 0) + 1 != 0) return 7;
    #|  if (side != 0) return 8;
    #|  if (__builtin_object_size(&x, 0) != sizeof(x)) return 9;
    #|  if (__builtin_dynamic_object_size((void *)buf, 2) != sizeof(buf)) return 10;
    #|  if (__builtin_object_size(&global_s.buf, 0) != sizeof(global_s) - __builtin_offsetof(struct S, buf)) return 11;
    #|  if (__builtin_dynamic_object_size((void *)global_buf, 2) != sizeof(global_buf)) return 12;
    #|  if (__builtin_dynamic_object_size(global_s.buf, 2) != sizeof(global_s) - __builtin_offsetof(struct S, buf)) return 13;
    #|  if (__builtin_dynamic_object_size(global_s.buf, 3) != sizeof(global_s.buf)) return 14;
    #|  if (__builtin_object_size(&local_s.buf, 0) != sizeof(local_s) - __builtin_offsetof(struct S, buf)) return 15;
    #|  if (__builtin_dynamic_object_size(local_s.buf, 2) != sizeof(local_s) - __builtin_offsetof(struct S, buf)) return 16;
    #|  if (__builtin_dynamic_object_size(local_s.buf, 3) != sizeof(local_s.buf)) return 17;
    #|  if (__builtin_object_size(&buf[3], 1) != sizeof(buf) - 3) return 18;
    #|  if (__builtin_object_size(buf + 3, 0) != sizeof(buf) - 3) return 19;
    #|  if (__builtin_dynamic_object_size(&global_s.buf[4], 2) != sizeof(global_s) - __builtin_offsetof(struct S, buf) - 4) return 20;
    #|  if (__builtin_dynamic_object_size(&global_s.buf[4], 3) != sizeof(global_s.buf) - 4) return 21;
    #|  if (!__builtin_constant_p(1 + 2)) return 23;
    #|  if (__builtin_constant_p(side)) return 22;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter reports unsupported global aggregate reads" {
  let source =
    #|char global_buf[16];
    #|int main(void) {
    #|  return global_buf;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.interpret_i64("main", []) {
    Ok(_) => abort("expected MIR interpreter unsupported-global-value error")
    Err(message) =>
      assert_eq(message, "unsupported MIR interpreter global value: global_buf")
  }
}

///|
test "mir interpreter evaluates unobserved varargs setup builtins" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int variadic(int last, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, last);
    #|  __builtin_va_copy(ap, ap);
    #|  __builtin_va_end(ap);
    #|  return last + 1;
    #|}
    #|int main(void) {
    #|  return variadic(41, 1, 2);
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models memory builtin return pointers" {
  let source =
    #|int main(void) {
    #|  char *dst = __builtin_alloca(8);
    #|  char *src = __builtin_alloca(8);
    #|  if (__builtin_memcpy(dst, src, 0) != dst) return 1;
    #|  if (__builtin_memmove(dst, src, 0) != dst) return 2;
    #|  if (__builtin_memset(dst, 0, 0) != dst) return 3;
    #|  if (__builtin___memcpy_chk(dst, src, 0, 8) != dst) return 4;
    #|  if (__builtin___memmove_chk(dst, src, 0, 8) != dst) return 5;
    #|  if (__builtin___memset_chk(dst, 0, 0, 8) != dst) return 6;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models string destination return pointers" {
  let source =
    #|int main(void) {
    #|  char *dst = __builtin_alloca(16);
    #|  __builtin_memset(dst, 0, 16);
    #|  if (__builtin_strcpy(dst, "") != dst) return 1;
    #|  if (__builtin___strcpy_chk(dst, "", 16) != dst) return 2;
    #|  if (__builtin_strcat(dst, "") != dst) return 3;
    #|  if (__builtin___strcat_chk(dst, "", 16) != dst) return 4;
    #|  if (__builtin_strncpy(dst, "", 0) != dst) return 5;
    #|  if (__builtin___strncpy_chk(dst, "", 0, 16) != dst) return 6;
    #|  if (__builtin_strncat(dst, "", 0) != dst) return 7;
    #|  if (__builtin___strncat_chk(dst, "", 0, 16) != dst) return 8;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models checked strlcpy literal length" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(8);
    #|  if (__builtin___strlcpy_chk(dst, (const char *)"abcdef", n += 4, 8) != 6) return 1;
    #|  if (n != 4) return 2;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models zero-size checked strlcat literal length" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(1);
    #|  if (__builtin___strlcat_chk(dst, (const char *)"abc", ((n += 1), 0), 1) != 3) return 1;
    #|  if (n != 1) return 2;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models zero-size checked snprintf literal length" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  if (__builtin___snprintf_chk((char *)0, ((n += 1), 0), 0, 0, (const char *)"ready") != 5) return 1;
    #|  if (n != 1) return 2;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models checked snprintf nonzero buffer length" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(4);
    #|  if (__builtin___snprintf_chk(dst, ((n += 1), 4), 0, 4, (const char *)"abcdef") != 6) return 1;
    #|  if (__builtin___snprintf_chk(dst, 4, 0, 4, (const char *)"n=%05d", n += 6) != 7) return 2;
    #|  if (n != 7) return 3;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models checked sprintf literal length" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___sprintf_chk(((n += 1), dst), 0, 16, (const char *)"ready") != 5) return 1;
    #|  if (n != 1) return 2;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models escaped percent checked printf lengths" {
  let source =
    #|int main(void) {
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"%%ok%%") != 4) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"done%%") != 5) return 2;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models checked printf literal length" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  if (__builtin___printf_chk(1, (const char *)"ok%%", n += 1) != 3) return 1;
    #|  if (n != 1) return 2;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models decimal checked printf lengths" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"n=%d", n += 7) != 3) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"neg=%i%%", -12) != 8) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"sum=%d", n) != 5) return 3;
    #|  if (n != 7) return 4;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models length-modified checked printf lengths" {
  let source =
    #|int main(void) {
    #|  long n = 0;
    #|  char *dst = __builtin_alloca(32);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"l=%ld", n += 1234L) != 6) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, (const char *)"%lld%%", -5000LL) != 6) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%zu", 9UL) != 3) return 3;
    #|  if (__builtin___printf_chk(1, (const char *)"x=%llx", 0x1000LL) != 6) return 4;
    #|  if (n != 1234L) return 5;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models width checked printf lengths" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(32);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"n=%05d", n += 7) != 7) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, (const char *)"%-4s%%", (const char *)"hi") != 5) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"c=%3c", 'A') != 5) return 3;
    #|  if (__builtin___printf_chk(1, (const char *)"x=%4x", 0xabc) != 6) return 4;
    #|  if (n != 7) return 5;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models signed flag checked printf lengths" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(32);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"%+d", n += 7) != 2) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, (const char *)"% d%%", 12) != 4) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"x=%+05d", 9) != 7) return 3;
    #|  if (__builtin___printf_chk(1, (const char *)"n=% d", -5) != 4) return 4;
    #|  if (n != 7) return 5;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models alternate checked printf lengths" {
  let source =
    #|int main(void) {
    #|  unsigned int n = 0;
    #|  char *dst = __builtin_alloca(32);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"o=%#o", n += 8) != 5) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, (const char *)"%#x%%", 0x2au) != 5) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"X=%#X", 0xABu) != 6) return 3;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%#x", 0u) != 3) return 4;
    #|  if (n != 8) return 5;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models char checked printf lengths" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"c=%c", n += 65) != 3) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"%c%%", 'Z') != 2) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%c", 0) != 3) return 3;
    #|  if (n != 65) return 4;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models string checked printf lengths" {
  let source =
    #|int main(void) {
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"s=%s", (const char *)"ok") != 4) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"%s%%", (const char *)"abc") != 4) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%s", (const char *)"") != 2) return 3;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models precision string checked printf lengths" {
  let source =
    #|int main(void) {
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"s=%.3s", (const char *)"abcdef") != 5) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"%5.2s%%", (const char *)"abcd") != 6) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%.0s", (const char *)"hide") != 2) return 3;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models decimal precision checked printf lengths" {
  let source =
    #|int main(void) {
    #|  unsigned int n = 0;
    #|  char *dst = __builtin_alloca(32);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"n=%.3u", n += 7) != 5) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, (const char *)"%+.4d%%", 12) != 6) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%.0u", 0u) != 2) return 3;
    #|  if (__builtin___printf_chk(1, (const char *)"w=%04.3d", 7) != 6) return 4;
    #|  if (n != 7) return 5;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models signed decimal precision checked printf lengths" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(32);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"n=%.4d", n -= 12) != 7) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, (const char *)"%+.3d%%", -8) != 5) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"w=%7.3i", -5) != 9) return 3;
    #|  if (n != -12) return 4;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models radix precision checked printf lengths" {
  let source =
    #|int main(void) {
    #|  unsigned int n = 0;
    #|  char *dst = __builtin_alloca(32);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"x=%.4x", n += 0x2a) != 6) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, (const char *)"%#.4x%%", 0x2au) != 7) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"o=%#.4o", 8u) != 6) return 3;
    #|  if (__builtin___printf_chk(1, (const char *)"q=%#.2o", 8u) != 5) return 4;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%.0x", 0u) != 2) return 5;
    #|  if (__builtin___printf_chk(1, (const char *)"r=%#.0o", 0u) != 3) return 6;
    #|  if (n != 0x2a) return 7;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models unsigned checked printf lengths" {
  let source =
    #|int main(void) {
    #|  unsigned int n = 0;
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"u=%u", n += 42) != 4) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"%u%%", 100u) != 4) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"n=%u", n) != 4) return 3;
    #|  if (n != 42) return 4;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models hex checked printf lengths" {
  let source =
    #|int main(void) {
    #|  unsigned int n = 0;
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"x=%x", n += 255) != 4) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"%x%%", 4095u) != 4) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%x", 0u) != 3) return 3;
    #|  if (n != 255) return 4;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models uppercase hex checked printf lengths" {
  let source =
    #|int main(void) {
    #|  unsigned int n = 0;
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"X=%X", n += 0xABCD) != 6) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"%X%%", 0x10u) != 3) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%X", 0u) != 3) return 3;
    #|  if (n != 0xABCD) return 4;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models octal checked printf lengths" {
  let source =
    #|int main(void) {
    #|  unsigned int n = 0;
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"o=%o", n += 64) != 5) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"%o%%", 511u) != 4) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%o", 0u) != 3) return 3;
    #|  if (n != 64) return 4;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter evaluates bzero arguments" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(1);
    #|  __builtin_bzero(dst, n += 1);
    #|  if (n != 1) return 1;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models constant floating comparison builtins" {
  let source =
    #|int main(void) {
    #|  if (!__builtin_isgreater(2.0, 1.0)) return 1;
    #|  if (!__builtin_isgreaterequal(2.0, 2.0)) return 2;
    #|  if (!__builtin_isless(1.0, 2.0)) return 3;
    #|  if (!__builtin_islessequal(2.0, 2.0)) return 4;
    #|  if (!__builtin_islessgreater(1.0, 2.0)) return 5;
    #|  if (__builtin_islessgreater(2.0, 2.0)) return 6;
    #|  if (!__builtin_isunordered(__builtin_nan(""), 1.0)) return 7;
    #|  if (__builtin_isgreater(__builtin_nan(""), 1.0)) return 8;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models constant floating classification builtins" {
  let source =
    #|int main(void) {
    #|  if (!__builtin_isnan(__builtin_nan(""))) return 1;
    #|  if (__builtin_isnan(1.0)) return 2;
    #|  if (!__builtin_isnanf(__builtin_nanf(""))) return 3;
    #|  if (!__builtin_isnanl(__builtin_nanl(""))) return 4;
    #|  if (!__builtin_isinf(__builtin_inf())) return 5;
    #|  if (!__builtin_isinf(-__builtin_inf())) return 6;
    #|  if (__builtin_isinf(1.0)) return 7;
    #|  if (!__builtin_isinff(__builtin_inff())) return 8;
    #|  if (!__builtin_isinfl(__builtin_infl())) return 9;
    #|  if (!__builtin_isfinite(1.0)) return 10;
    #|  if (__builtin_isfinite(__builtin_inf())) return 11;
    #|  if (!__builtin_isfinitef(1.0f)) return 12;
    #|  if (!__builtin_isfinitel(1.0L)) return 13;
    #|  if (!__builtin_isnormal(1.0)) return 14;
    #|  if (__builtin_isnormal(0.0)) return 15;
    #|  if (__builtin_isnormal(__builtin_inf())) return 16;
    #|  if (!__builtin_isnormalf(1.0f)) return 17;
    #|  if (!__builtin_isnormall(1.0L)) return 18;
    #|  if (!__builtin_signbit(-1.0)) return 19;
    #|  if (!__builtin_signbit(-0.0)) return 20;
    #|  if (__builtin_signbit(1.0)) return 21;
    #|  if (!__builtin_signbitf(-0.0f)) return 22;
    #|  if (!__builtin_signbitl(-1.0L)) return 23;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter casts folded floating builtins" {
  let source =
    #|int main(void) {
    #|  if ((int)__builtin_fabs(-4.5) != 4) return 1;
    #|  if ((int)__builtin_fabsf(-3.5f) != 3) return 2;
    #|  if ((int)__builtin_fabsl(-2.5L) != 2) return 3;
    #|  if ((int)__builtin_copysign(3.0, -1.0) != -3) return 4;
    #|  if ((int)__builtin_copysign(-3.0, 1.0) != 3) return 5;
    #|  if (!__builtin_signbit(__builtin_copysign(0.0, -1.0))) return 6;
    #|  if ((int)__builtin_sqrt(81.0) != 9) return 7;
    #|  if ((int)__builtin_sqrtf(25.0f) != 5) return 8;
    #|  if ((int)__builtin_sqrtl(16.0L) != 4) return 9;
    #|  if (!__builtin_isnan(__builtin_sqrt(-1.0))) return 10;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models literal string comparison builtins" {
  let source =
    #|int main(void) {
    #|  if (__builtin_strcmp("abc", "abc") != 0) return 1;
    #|  if (__builtin_strcmp("abc", "abd") >= 0) return 2;
    #|  if (__builtin_strcmp((const char *)"abd", "abc") <= 0) return 3;
    #|  if (__builtin_strncmp("abc", "abd", 2) != 0) return 4;
    #|  if (__builtin_strncmp("abc", "abd", 3) >= 0) return 5;
    #|  if (__builtin_strncmp("abc", "abd", 0) != 0) return 6;
    #|  if (__builtin_memcmp("abc", "abd", 2) != 0) return 7;
    #|  if (__builtin_memcmp("abc", "abd", 3) >= 0) return 8;
    #|  if (__builtin_memcmp("abd", "abc", 3) <= 0) return 9;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models literal string search nullness" {
  let source =
    #|int main(void) {
    #|  if (__builtin_strchr("abc", 'b') == 0) return 1;
    #|  if (__builtin_strchr("abc", 'x') != 0) return 2;
    #|  if (__builtin_strchr("abc", 0) == 0) return 3;
    #|  if (__builtin_strrchr("abba", 'b') == 0) return 4;
    #|  if (__builtin_memchr("abc", 'b', 2) == 0) return 5;
    #|  if (__builtin_memchr("abc", 'c', 2) != 0) return 6;
    #|  if (__builtin_strstr("abcde", "cd") == 0) return 7;
    #|  if (__builtin_strstr("abcde", "ce") != 0) return 8;
    #|  if (__builtin_strstr("abc", "") == 0) return 9;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models literal string search pointer offsets" {
  let source =
    #|int main(void) {
    #|  if (__builtin_strchr("abc", 'a') != "abc") return 1;
    #|  if (__builtin_strchr("abc", 'b') != "abc" + 1) return 2;
    #|  if (__builtin_strchr("abc", 0) != "abc" + 3) return 3;
    #|  if (__builtin_strrchr("abba", 'b') != "abba" + 2) return 4;
    #|  if (__builtin_strrchr("abba", 0) != "abba" + 4) return 5;
    #|  if (__builtin_memchr("abc", 'b', 2) != "abc" + 1) return 6;
    #|  if (__builtin_memchr("abc", 0, 4) != "abc" + 3) return 7;
    #|  if (__builtin_strstr("abcde", "cd") != "abcde" + 2) return 8;
    #|  if (__builtin_strstr("abc", "") != "abc") return 9;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter reports unsupported memory behavior" {
  let source = "int main(void) { int *p = (int*)0; return *p; }"
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.interpret_i64("main", []) {
    Ok(_) => abort("expected MIR interpreter unsupported-memory error")
    Err(err) => inspect(err.contains("memory"), content="true")
  }
}

///|
test "mir interpreter defers unused unsupported local declarations" {
  let source =
    #|struct S { int x; };
    #|union U { int x; double y; };
    #|int main(void) {
    #|  double d;
    #|  int a[2];
    #|  struct S s;
    #|  union U u;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter reports unsupported local reads" {
  let source = "int main(void) { double d; return (int)d; }"
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.interpret_i64("main", []) {
    Ok(_) => abort("expected MIR interpreter unsupported-local-value error")
    Err(err) => inspect(err.contains("local value"), content="true")
  }
}

///|
test "mir interpreter evaluates ignored unsupported local initializer side effects" {
  let source =
    #|int main(void) {
    #|  int side = 0;
    #|  int a[2];
    #|  double d = (a[side += 1] = side += 2);
    #|  double e = side += 4;
    #|  return side + 35;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter reports unsupported initialized local reads" {
  let source = "int main(void) { double d = 0.0; return (int)d; }"
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.interpret_i64("main", []) {
    Ok(_) => abort("expected MIR interpreter unsupported-local-value error")
    Err(err) => inspect(err.contains("local value"), content="true")
  }
}
