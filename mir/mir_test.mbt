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
fn expect_interp(source : String, expected : Int64) -> Unit {
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.interpret_i64("main", []) {
    Ok(value) =>
      if value != expected {
        abort("unexpected MIR interpreter result")
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
  expect_const(mir, SizeofExpr(String("abc")), scope, 4L)
  expect_const(mir, AlignofExpr(String("abc")), scope, 1L)
  expect_const(mir, Binary("/", Number(1), Number(2)), scope, 0L)
  expect_const(
    mir,
    Binary(">", Cast(ULong, Unary("-", Number(1))), Number(1)),
    scope,
    1L,
  )
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
test "mir interpreter models floating builtin return sizes" {
  let source =
    #|int main(void) {
    #|  return sizeof(__builtin_fabsf(-1.0f)) +
    #|    sizeof(__builtin_fabs(-1.0)) +
    #|    sizeof(__builtin_fabsl(-1.0L)) +
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
  expect_interp(source, 100L)
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
test "mir interpreter reports unsupported memory behavior" {
  let source = "int main(void) { int x = 1; return *&x; }"
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
test "mir interpreter reports unsupported local initializers" {
  let source = "int main(void) { double d = 0.0; return 0; }"
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.interpret_i64("main", []) {
    Ok(_) =>
      abort("expected MIR interpreter unsupported-local-initializer error")
    Err(err) => inspect(err.contains("local initializer"), content="true")
  }
}
