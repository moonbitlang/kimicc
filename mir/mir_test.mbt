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
test "mir interpreter models literal object size builtins" {
  let source =
    #|int main(void) {
    #|  int side = 0;
    #|  if (__builtin_object_size("abc", 0) != 4) return 1;
    #|  if (__builtin_object_size((const char *)"abc", 1) != 4) return 2;
    #|  if (__builtin_dynamic_object_size("hello", 2) != 6) return 3;
    #|  if (__builtin_dynamic_object_size((const void *)"hello", 3) != 6) return 4;
    #|  if (__builtin_object_size((void *)1, 0) + 1 != 0) return 5;
    #|  if (__builtin_object_size((void *)1, 2) != 0) return 6;
    #|  if (__builtin_dynamic_object_size((void *)(long)(side += 1), 0) + 1 != 0) return 7;
    #|  if (side != 0) return 8;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
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
test "mir interpreter reports unsupported local initializers" {
  let source = "int main(void) { double d = 0.0; return 0; }"
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.interpret_i64("main", []) {
    Ok(_) =>
      abort("expected MIR interpreter unsupported-local-initializer error")
    Err(err) => inspect(err.contains("local initializer"), content="true")
  }
}
