///|
fn compile_strict_mir(source : String) -> String {
  let target = @target.Target::default()
  let prog = @parser.parse_for_target(source, target)
  match @parser.validate_semantics(prog) {
    Ok(_) => ()
    Err(err) => abort("strict MIR semantic validation failed: " + err)
  }
  match
    @mir_codegen.generate_assembly_from_mir_module_strict(
      @mir.lower_to_module(prog, target),
    ) {
    Ok(assembly) => assembly
    Err(err) => abort("strict MIR codegen failed: " + err)
  }
}

///|
fn run_source_strict_mir(source : String) -> Int {
  let assembly = compile_strict_mir(source)
  let id = source_id(source)
  let asm_path = "/tmp/kimicc_strict_mir_test_" + id + ".s"
  let bin_path = "/tmp/kimicc_strict_mir_test_" + id
  write_text_file(asm_path, assembly)
  let link_rc = moonbit_system(
    @utf8.encode("clang -o " + bin_path + " " + asm_path),
  )
  if link_rc != 0 {
    abort("strict MIR link failed with code: " + link_rc.to_string())
  }
  run_command_exit_silent(shell_quote(bin_path), "strict_mir_run_source")
}

///|
fn run_strict_mir_with_clang_driver(
  callee_source : String,
  driver_source : String,
) -> Int {
  let assembly = compile_strict_mir(callee_source)
  let id = source_id(callee_source + driver_source)
  let asm_path = "/tmp/kimicc_strict_mir_driver_" + id + ".s"
  let driver_path = "/tmp/kimicc_strict_mir_driver_" + id + ".c"
  let bin_path = "/tmp/kimicc_strict_mir_driver_" + id
  write_text_file(asm_path, assembly)
  write_text_file(driver_path, driver_source)
  let link_rc = moonbit_system(
    @utf8.encode("clang -o " + bin_path + " " + asm_path + " " + driver_path),
  )
  if link_rc != 0 {
    abort("strict MIR driver link failed with code: " + link_rc.to_string())
  }
  run_command_exit_silent(shell_quote(bin_path), "strict_mir_run_driver")
}

///|
test "strict MIR codegen executes scalar control flow and calls" {
  let source =
    #|int add(int a, int b) { return a + b; }
    #|int main(void) {
    #|  int i = 0;
    #|  int s = 0;
    #|  while (i < 5) {
    #|    s = s + add(i, 1);
    #|    i = i + 1;
    #|  }
    #|  if (s == 15) return s + 2;
    #|  return 1;
    #|}
  assert_eq(run_source_strict_mir(source), 17)
}

///|
test "strict MIR codegen executes unsigned int128 limb multiply" {
  let source =
    #|typedef unsigned long js_limb_t;
    #|typedef unsigned __int128 js_dlimb_t;
    #|static js_limb_t mp_mul1(js_limb_t *tabr, const js_limb_t *taba, js_limb_t n,
    #|                         js_limb_t b, js_limb_t l) {
    #|  js_limb_t i;
    #|  js_dlimb_t t;
    #|  for (i = 0; i < n; i++) {
    #|    t = (js_dlimb_t)taba[i] * (js_dlimb_t)b + l;
    #|    tabr[i] = t;
    #|    l = t >> 64;
    #|  }
    #|  return l;
    #|}
    #|int main(void) {
    #|  js_limb_t in[2] = { ~0UL, 2 };
    #|  js_limb_t out[2];
    #|  js_limb_t carry = mp_mul1(out, in, 2, 2, 1);
    #|  if (out[0] != ~0UL) return 10;
    #|  if (out[1] != 5) return 20;
    #|  if (carry != 0) return 30;
    #|  return 42;
    #|}
  assert_eq(run_source_strict_mir(source), 42)
}

///|
test "strict MIR codegen executes unsigned int128 limb divide" {
  let source =
    #|typedef unsigned long js_limb_t;
    #|typedef long js_slimb_t;
    #|typedef unsigned __int128 js_dlimb_t;
    #|static js_limb_t mp_div1(js_limb_t *tabr, const js_limb_t *taba, js_limb_t n,
    #|                         js_limb_t b, js_limb_t r) {
    #|  js_slimb_t i;
    #|  js_dlimb_t a1;
    #|  for (i = n - 1; i >= 0; i--) {
    #|    a1 = ((js_dlimb_t)r << 64) | taba[i];
    #|    tabr[i] = a1 / b;
    #|    r = a1 % b;
    #|  }
    #|  return r;
    #|}
    #|int main(void) {
    #|  js_limb_t in[1] = { 5 };
    #|  js_limb_t out[1];
    #|  js_limb_t rem = mp_div1(out, in, 1, 2, 1);
    #|  if (out[0] != ((1UL << 63) + 2)) return 10;
    #|  if (rem != 1) return 20;
    #|  return 42;
    #|}
  assert_eq(run_source_strict_mir(source), 42)
}

///|
test "strict MIR codegen executes implicit external scalar call arguments" {
  let source =
    #|int main(void) {
    #|  if (strcmp("kimicc", "kimicc") != 0) return 1;
    #|  if (strcmp("abc", "abd") >= 0) return 2;
    #|  return 42;
    #|}
  assert_eq(run_source_strict_mir(source), 42)
}

///|
test "strict MIR codegen executes stack-passed integer direct calls" {
  let source =
    #|int sum9(int a, int b, int c, int d, int e, int f, int g, int h, int i) {
    #|  return a + b + c + d + e + f + g + h + i;
    #|}
    #|int main(void) {
    #|  return sum9(1, 2, 3, 4, 5, 6, 7, 8, 9);
    #|}
  assert_eq(run_source_strict_mir(source), 45)
}

///|
test "strict MIR codegen executes stack-passed integer indirect calls" {
  let source =
    #|int sum9(int a, int b, int c, int d, int e, int f, int g, int h, int i) {
    #|  return a + b + c + d + e + f + g + h + i;
    #|}
    #|int main(void) {
    #|  int (*fp)(int, int, int, int, int, int, int, int, int) = sum9;
    #|  return fp(1, 2, 3, 4, 5, 6, 7, 8, 9);
    #|}
  assert_eq(run_source_strict_mir(source), 45)
}

///|
test "strict MIR codegen executes indirect variadic function pointer calls" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int read_variadic(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  int a = __builtin_va_arg(ap, int);
    #|  double b = __builtin_va_arg(ap, double);
    #|  __builtin_va_end(ap);
    #|  return tag + a + (int)b;
    #|}
    #|int main(void) {
    #|  int (*fp)(int, ...) = read_variadic;
    #|  return fp(4, 10, 3.5);
    #|}
  assert_eq(run_source_strict_mir(source), 17)
}

///|
test "strict MIR codegen executes aggregate member address function table" {
  let source =
    #|struct Methods { int (*init)(void); };
    #|struct Config { struct Methods methods; };
    #|struct Config cfg;
    #|int good(void) { return 42; }
    #|int setup(void) {
    #|  struct Methods *to = &cfg.methods;
    #|  to->init = good;
    #|  return cfg.methods.init();
    #|}
    #|int main(void) {
    #|  return setup();
    #|}
  assert_eq(run_source_strict_mir(source), 42)
}

///|
test "strict MIR codegen executes aggregate array element address" {
  let source =
    #|struct Item { int v; };
    #|struct Item items[3];
    #|struct Item *pick(int i) {
    #|  return &items[i];
    #|}
    #|int main(void) {
    #|  items[2].v = 42;
    #|  return pick(2)->v;
    #|}
  assert_eq(run_source_strict_mir(source), 42)
}

///|
test "strict MIR codegen executes pointer post update through memory" {
  let source =
    #|int main(void) {
    #|  int values[3] = {4, 7, 9};
    #|  int *p = values;
    #|  int **pp = &p;
    #|  int first = *((*pp)++);
    #|  return first + **pp;
    #|}
  assert_eq(run_source_strict_mir(source), 11)
}

///|
test "strict MIR codegen executes small aggregate call results" {
  let source =
    #|struct Pair { long a; long b; };
    #|struct Tiny { char a; short b; };
    #|struct Pair make_pair(long a, long b) {
    #|  struct Pair p;
    #|  p.a = a;
    #|  p.b = b;
    #|  return p;
    #|}
    #|struct Tiny make_tiny(int a, int b) {
    #|  struct Tiny t;
    #|  t.a = a;
    #|  t.b = b;
    #|  return t;
    #|}
    #|int main(void) {
    #|  struct Pair p = make_pair(10, 20);
    #|  struct Pair q;
    #|  struct Tiny t = make_tiny(5, 30);
    #|  q = make_pair(3, 4);
    #|  return (int)(p.a + p.b + q.a + q.b) + t.a + t.b;
    #|}
  assert_eq(run_source_strict_mir(source), 72)
}

///|
test "strict MIR codegen returns small aggregates to clang callers" {
  let callee =
    #|struct Pair { long a; long b; };
    #|struct Pair make_pair(long a, long b) {
    #|  struct Pair p;
    #|  p.a = a;
    #|  p.b = b;
    #|  return p;
    #|}
    #|struct Pair forward_pair(long a, long b) {
    #|  return make_pair(a + 1, b + 2);
    #|}
  let driver =
    #|struct Pair { long a; long b; };
    #|struct Pair make_pair(long a, long b);
    #|struct Pair forward_pair(long a, long b);
    #|int main(void) {
    #|  struct Pair p = make_pair(10, 20);
    #|  struct Pair q = forward_pair(3, 4);
    #|  return (int)(p.a + p.b + q.a + q.b);
    #|}
  assert_eq(run_strict_mir_with_clang_driver(callee, driver), 40)
}

///|
test "strict MIR codegen executes HFA aggregate call results" {
  let source =
    #|struct H { double a[2]; };
    #|struct F { float a; float b; float c; };
    #|union U { double d; };
    #|struct H make_h(double x, double y) {
    #|  struct H h;
    #|  h.a[0] = x;
    #|  h.a[1] = y;
    #|  return h;
    #|}
    #|struct F make_f(float x, float y, float z) {
    #|  struct F f;
    #|  f.a = x;
    #|  f.b = y;
    #|  f.c = z;
    #|  return f;
    #|}
    #|union U make_u(double x) {
    #|  union U u;
    #|  u.d = x;
    #|  return u;
    #|}
    #|int main(void) {
    #|  struct H h = make_h(10.0, 20.0);
    #|  struct H k;
    #|  struct F f = make_f(1.0f, 2.0f, 3.0f);
    #|  union U u = make_u(5.0);
    #|  k = make_h(3.0, 4.0);
    #|  return (int)(h.a[0] + h.a[1] + k.a[0] + k.a[1] + f.a + f.b + f.c + u.d);
    #|}
  assert_eq(run_source_strict_mir(source), 48)
}

///|
test "strict MIR codegen returns HFA aggregates to clang callers" {
  let callee =
    #|struct H { double a[2]; };
    #|struct F { float a; float b; float c; };
    #|union U { double d; };
    #|struct H make_h(double x, double y) {
    #|  struct H h;
    #|  h.a[0] = x;
    #|  h.a[1] = y;
    #|  return h;
    #|}
    #|struct H forward_h(double x, double y) {
    #|  return make_h(x + 1.0, y + 2.0);
    #|}
    #|struct F make_f(float x, float y, float z) {
    #|  struct F f;
    #|  f.a = x;
    #|  f.b = y;
    #|  f.c = z;
    #|  return f;
    #|}
    #|union U make_u(double x) {
    #|  union U u;
    #|  u.d = x;
    #|  return u;
    #|}
  let driver =
    #|struct H { double a[2]; };
    #|struct F { float a; float b; float c; };
    #|union U { double d; };
    #|struct H make_h(double x, double y);
    #|struct H forward_h(double x, double y);
    #|struct F make_f(float x, float y, float z);
    #|union U make_u(double x);
    #|int main(void) {
    #|  struct H h = make_h(10.0, 20.0);
    #|  struct H k = forward_h(3.0, 4.0);
    #|  struct F f = make_f(1.0f, 2.0f, 3.0f);
    #|  union U u = make_u(5.0);
    #|  return (int)(h.a[0] + h.a[1] + k.a[0] + k.a[1] + f.a + f.b + f.c + u.d);
    #|}
  assert_eq(run_strict_mir_with_clang_driver(callee, driver), 51)
}

///|
test "strict MIR codegen executes register aggregate parameters" {
  let source =
    #|struct Pair { long a; long b; };
    #|struct Tiny { char a; short b; };
    #|struct H { double a[2]; };
    #|struct Hthree { double a[3]; };
    #|struct F { float a; float b; float c; };
    #|long sum_pair(struct Pair p, long z) {
    #|  return p.a + p.b + z;
    #|}
    #|int sum_tiny(struct Tiny t) {
    #|  return t.a + t.b;
    #|}
    #|int sum_h(struct H h) {
    #|  return (int)(h.a[0] + h.a[1]);
    #|}
    #|int sum_f(struct F f) {
    #|  return (int)(f.a + f.b + f.c);
    #|}
    #|int main(void) {
    #|  struct Pair p;
    #|  struct Tiny t;
    #|  struct H h;
    #|  struct F f;
    #|  p.a = 10;
    #|  p.b = 20;
    #|  t.a = 5;
    #|  t.b = 30;
    #|  h.a[0] = 3.0;
    #|  h.a[1] = 4.0;
    #|  f.a = 1.0f;
    #|  f.b = 2.0f;
    #|  f.c = 3.0f;
    #|  return (int)sum_pair(p, 5) + sum_tiny(t) + sum_h(h) + sum_f(f);
    #|}
  assert_eq(run_source_strict_mir(source), 83)
}

///|
test "strict MIR codegen receives register aggregate parameters from clang callers" {
  let callee =
    #|struct Pair { long a; long b; };
    #|struct Tiny { char a; short b; };
    #|struct H { double a[2]; };
    #|struct F { float a; float b; float c; };
    #|long sum_pair(struct Pair p, long z) {
    #|  return p.a + p.b + z;
    #|}
    #|int sum_tiny(struct Tiny t) {
    #|  return t.a + t.b;
    #|}
    #|int sum_h(struct H h) {
    #|  return (int)(h.a[0] + h.a[1]);
    #|}
    #|int sum_f(struct F f) {
    #|  return (int)(f.a + f.b + f.c);
    #|}
  let driver =
    #|struct Pair { long a; long b; };
    #|struct Tiny { char a; short b; };
    #|struct H { double a[2]; };
    #|struct F { float a; float b; float c; };
    #|long sum_pair(struct Pair p, long z);
    #|int sum_tiny(struct Tiny t);
    #|int sum_h(struct H h);
    #|int sum_f(struct F f);
    #|int main(void) {
    #|  struct Pair p = {10, 20};
    #|  struct Tiny t = {5, 30};
    #|  struct H h = {{3.0, 4.0}};
    #|  struct F f = {1.0f, 2.0f, 3.0f};
    #|  return (int)sum_pair(p, 5) + sum_tiny(t) + sum_h(h) + sum_f(f);
    #|}
  assert_eq(run_strict_mir_with_clang_driver(callee, driver), 83)
}

///|
test "strict MIR codegen passes register aggregate parameters to clang callees" {
  let caller =
    #|struct Pair { long a; long b; };
    #|struct Tiny { char a; short b; };
    #|struct H { double a[2]; };
    #|struct F { float a; float b; float c; };
    #|long sum_pair(struct Pair p, long z);
    #|int sum_tiny(struct Tiny t);
    #|int sum_h(struct H h);
    #|int sum_f(struct F f);
    #|int main(void) {
    #|  struct Pair p;
    #|  struct Tiny t;
    #|  struct H h;
    #|  struct F f;
    #|  p.a = 10;
    #|  p.b = 20;
    #|  t.a = 5;
    #|  t.b = 30;
    #|  h.a[0] = 3.0;
    #|  h.a[1] = 4.0;
    #|  f.a = 1.0f;
    #|  f.b = 2.0f;
    #|  f.c = 3.0f;
    #|  return (int)sum_pair(p, 5) + sum_tiny(t) + sum_h(h) + sum_f(f);
    #|}
  let callee =
    #|struct Pair { long a; long b; };
    #|struct Tiny { char a; short b; };
    #|struct H { double a[2]; };
    #|struct F { float a; float b; float c; };
    #|long sum_pair(struct Pair p, long z) {
    #|  return p.a + p.b + z;
    #|}
    #|int sum_tiny(struct Tiny t) {
    #|  return t.a + t.b;
    #|}
    #|int sum_h(struct H h) {
    #|  return (int)(h.a[0] + h.a[1]);
    #|}
    #|int sum_f(struct F f) {
    #|  return (int)(f.a + f.b + f.c);
    #|}
  assert_eq(run_strict_mir_with_clang_driver(caller, callee), 83)
}

///|
test "strict MIR codegen executes stack aggregate parameters" {
  let source =
    #|struct Pair { long a; long b; };
    #|struct Tiny { char a; short b; };
    #|struct H { double a[2]; };
    #|struct Hthree { double a[3]; };
    #|long sum_pair_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, struct Pair p, long z) {
    #|  return a0 + a1 + a2 + a3 + a4 + a5 + a6 + p.a + p.b + z;
    #|}
    #|int sum_tiny_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, long a7, struct Tiny t, long z) {
    #|  return (int)(a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7 + t.a + t.b + z);
    #|}
    #|int sum_h_stack(double d0, double d1, double d2, double d3, double d4, double d5, double d6, struct H h, double z) {
    #|  return (int)(d0 + d1 + d2 + d3 + d4 + d5 + d6 + h.a[0] + h.a[1] + z);
    #|}
    #|int sum_h3_stack(double d0, double d1, double d2, double d3, double d4, double d5, struct Hthree h, double z) {
    #|  return (int)(d0 + d1 + d2 + d3 + d4 + d5 + h.a[0] + h.a[1] + h.a[2] + z);
    #|}
    #|int main(void) {
    #|  struct Pair p;
    #|  struct Tiny t;
    #|  struct H h;
    #|  struct Hthree hthree;
    #|  p.a = 10;
    #|  p.b = 20;
    #|  t.a = 5;
    #|  t.b = 30;
    #|  h.a[0] = 3.0;
    #|  h.a[1] = 4.0;
    #|  hthree.a[0] = 2.0;
    #|  hthree.a[1] = 3.0;
    #|  hthree.a[2] = 4.0;
    #|  return (int)sum_pair_stack(1, 2, 3, 4, 5, 6, 7, p, 9) + sum_tiny_stack(1, 2, 3, 4, 5, 6, 7, 8, t, 9) + sum_h_stack(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, h, 9.0) + sum_h3_stack(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, hthree, 5.0);
    #|}
  assert_eq(run_source_strict_mir(source), 226)
}

///|
test "strict MIR codegen receives stack aggregate parameters from clang callers" {
  let callee =
    #|struct Pair { long a; long b; };
    #|struct Tiny { char a; short b; };
    #|struct H { double a[2]; };
    #|struct Hthree { double a[3]; };
    #|long sum_pair_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, struct Pair p, long z) {
    #|  return a0 + a1 + a2 + a3 + a4 + a5 + a6 + p.a + p.b + z;
    #|}
    #|int sum_tiny_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, long a7, struct Tiny t, long z) {
    #|  return (int)(a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7 + t.a + t.b + z);
    #|}
    #|int sum_h_stack(double d0, double d1, double d2, double d3, double d4, double d5, double d6, struct H h, double z) {
    #|  return (int)(d0 + d1 + d2 + d3 + d4 + d5 + d6 + h.a[0] + h.a[1] + z);
    #|}
    #|int sum_h3_stack(double d0, double d1, double d2, double d3, double d4, double d5, struct Hthree h, double z) {
    #|  return (int)(d0 + d1 + d2 + d3 + d4 + d5 + h.a[0] + h.a[1] + h.a[2] + z);
    #|}
  let driver =
    #|struct Pair { long a; long b; };
    #|struct Tiny { char a; short b; };
    #|struct H { double a[2]; };
    #|struct Hthree { double a[3]; };
    #|long sum_pair_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, struct Pair p, long z);
    #|int sum_tiny_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, long a7, struct Tiny t, long z);
    #|int sum_h_stack(double d0, double d1, double d2, double d3, double d4, double d5, double d6, struct H h, double z);
    #|int sum_h3_stack(double d0, double d1, double d2, double d3, double d4, double d5, struct Hthree h, double z);
    #|int main(void) {
    #|  struct Pair p = {10, 20};
    #|  struct Tiny t = {5, 30};
    #|  struct H h = {{3.0, 4.0}};
    #|  struct Hthree hthree = {{2.0, 3.0, 4.0}};
    #|  return (int)sum_pair_stack(1, 2, 3, 4, 5, 6, 7, p, 9) + sum_tiny_stack(1, 2, 3, 4, 5, 6, 7, 8, t, 9) + sum_h_stack(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, h, 9.0) + sum_h3_stack(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, hthree, 5.0);
    #|}
  assert_eq(run_strict_mir_with_clang_driver(callee, driver), 226)
}

///|
test "strict MIR codegen passes stack aggregate parameters to clang callees" {
  let caller =
    #|struct Pair { long a; long b; };
    #|struct Tiny { char a; short b; };
    #|struct H { double a[2]; };
    #|struct Hthree { double a[3]; };
    #|long sum_pair_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, struct Pair p, long z);
    #|int sum_tiny_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, long a7, struct Tiny t, long z);
    #|int sum_h_stack(double d0, double d1, double d2, double d3, double d4, double d5, double d6, struct H h, double z);
    #|int sum_h3_stack(double d0, double d1, double d2, double d3, double d4, double d5, struct Hthree h, double z);
    #|int main(void) {
    #|  struct Pair p;
    #|  struct Tiny t;
    #|  struct H h;
    #|  struct Hthree hthree;
    #|  p.a = 10;
    #|  p.b = 20;
    #|  t.a = 5;
    #|  t.b = 30;
    #|  h.a[0] = 3.0;
    #|  h.a[1] = 4.0;
    #|  hthree.a[0] = 2.0;
    #|  hthree.a[1] = 3.0;
    #|  hthree.a[2] = 4.0;
    #|  return (int)sum_pair_stack(1, 2, 3, 4, 5, 6, 7, p, 9) + sum_tiny_stack(1, 2, 3, 4, 5, 6, 7, 8, t, 9) + sum_h_stack(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, h, 9.0) + sum_h3_stack(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, hthree, 5.0);
    #|}
  let callee =
    #|struct Pair { long a; long b; };
    #|struct Tiny { char a; short b; };
    #|struct H { double a[2]; };
    #|struct Hthree { double a[3]; };
    #|long sum_pair_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, struct Pair p, long z) {
    #|  return a0 + a1 + a2 + a3 + a4 + a5 + a6 + p.a + p.b + z;
    #|}
    #|int sum_tiny_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, long a7, struct Tiny t, long z) {
    #|  return (int)(a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7 + t.a + t.b + z);
    #|}
    #|int sum_h_stack(double d0, double d1, double d2, double d3, double d4, double d5, double d6, struct H h, double z) {
    #|  return (int)(d0 + d1 + d2 + d3 + d4 + d5 + d6 + h.a[0] + h.a[1] + z);
    #|}
    #|int sum_h3_stack(double d0, double d1, double d2, double d3, double d4, double d5, struct Hthree h, double z) {
    #|  return (int)(d0 + d1 + d2 + d3 + d4 + d5 + h.a[0] + h.a[1] + h.a[2] + z);
    #|}
  assert_eq(run_strict_mir_with_clang_driver(caller, callee), 226)
}

///|
test "strict MIR codegen executes indirect register aggregate parameters" {
  let source =
    #|struct Pair { long a; long b; };
    #|struct Tiny { char a; short b; };
    #|struct H { double a[2]; };
    #|struct F { float a; float b; float c; };
    #|long sum_pair(struct Pair p, long z) {
    #|  return p.a + p.b + z;
    #|}
    #|int sum_tiny(struct Tiny t) {
    #|  return t.a + t.b;
    #|}
    #|int sum_h(struct H h) {
    #|  return (int)(h.a[0] + h.a[1]);
    #|}
    #|int sum_f(struct F f) {
    #|  return (int)(f.a + f.b + f.c);
    #|}
    #|int main(void) {
    #|  struct Pair p;
    #|  struct Tiny t;
    #|  struct H h;
    #|  struct F f;
    #|  long (*fp_pair)(struct Pair, long) = sum_pair;
    #|  int (*fp_tiny)(struct Tiny) = sum_tiny;
    #|  int (*fp_h)(struct H) = sum_h;
    #|  int (*fp_f)(struct F) = sum_f;
    #|  p.a = 10;
    #|  p.b = 20;
    #|  t.a = 5;
    #|  t.b = 30;
    #|  h.a[0] = 3.0;
    #|  h.a[1] = 4.0;
    #|  f.a = 1.0f;
    #|  f.b = 2.0f;
    #|  f.c = 3.0f;
    #|  return (int)fp_pair(p, 5) + fp_tiny(t) + fp_h(h) + fp_f(f);
    #|}
  assert_eq(run_source_strict_mir(source), 83)
}

///|
test "strict MIR codegen passes indirect stack aggregate parameters to clang callees" {
  let caller =
    #|struct Pair { long a; long b; };
    #|struct Tiny { char a; short b; };
    #|struct H { double a[2]; };
    #|struct Hthree { double a[3]; };
    #|long sum_pair_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, struct Pair p, long z);
    #|int sum_tiny_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, long a7, struct Tiny t, long z);
    #|int sum_h_stack(double d0, double d1, double d2, double d3, double d4, double d5, double d6, struct H h, double z);
    #|int sum_h3_stack(double d0, double d1, double d2, double d3, double d4, double d5, struct Hthree h, double z);
    #|int main(void) {
    #|  struct Pair p;
    #|  struct Tiny t;
    #|  struct H h;
    #|  struct Hthree hthree;
    #|  long (*fp_pair)(long, long, long, long, long, long, long, struct Pair, long) = sum_pair_stack;
    #|  int (*fp_tiny)(long, long, long, long, long, long, long, long, struct Tiny, long) = sum_tiny_stack;
    #|  int (*fp_h)(double, double, double, double, double, double, double, struct H, double) = sum_h_stack;
    #|  int (*fp_hthree)(double, double, double, double, double, double, struct Hthree, double) = sum_h3_stack;
    #|  p.a = 10;
    #|  p.b = 20;
    #|  t.a = 5;
    #|  t.b = 30;
    #|  h.a[0] = 3.0;
    #|  h.a[1] = 4.0;
    #|  hthree.a[0] = 2.0;
    #|  hthree.a[1] = 3.0;
    #|  hthree.a[2] = 4.0;
    #|  return (int)fp_pair(1, 2, 3, 4, 5, 6, 7, p, 9) + fp_tiny(1, 2, 3, 4, 5, 6, 7, 8, t, 9) + fp_h(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, h, 9.0) + fp_hthree(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, hthree, 5.0);
    #|}
  let callee =
    #|struct Pair { long a; long b; };
    #|struct Tiny { char a; short b; };
    #|struct H { double a[2]; };
    #|struct Hthree { double a[3]; };
    #|long sum_pair_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, struct Pair p, long z) {
    #|  return a0 + a1 + a2 + a3 + a4 + a5 + a6 + p.a + p.b + z;
    #|}
    #|int sum_tiny_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, long a7, struct Tiny t, long z) {
    #|  return (int)(a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7 + t.a + t.b + z);
    #|}
    #|int sum_h_stack(double d0, double d1, double d2, double d3, double d4, double d5, double d6, struct H h, double z) {
    #|  return (int)(d0 + d1 + d2 + d3 + d4 + d5 + d6 + h.a[0] + h.a[1] + z);
    #|}
    #|int sum_h3_stack(double d0, double d1, double d2, double d3, double d4, double d5, struct Hthree h, double z) {
    #|  return (int)(d0 + d1 + d2 + d3 + d4 + d5 + h.a[0] + h.a[1] + h.a[2] + z);
    #|}
  assert_eq(run_strict_mir_with_clang_driver(caller, callee), 226)
}

///|
test "strict MIR codegen executes large aggregate parameters" {
  let source =
    #|struct BigArg { long a; long b; long c; long d; };
    #|struct BigArg make_big(long a, long b, long c, long d) {
    #|  struct BigArg value = { a, b, c, d };
    #|  return value;
    #|}
    #|int observe_big(struct BigArg value) {
    #|  value.a = 20;
    #|  return (int)(value.a + value.d);
    #|}
    #|int observe_big_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, long a7, struct BigArg value) {
    #|  value.b = 30;
    #|  return (int)(a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7 + value.b + value.d);
    #|}
    #|int main(void) {
    #|  struct BigArg value = { 1, 2, 3, 4 };
    #|  int total = observe_big(value) + observe_big(make_big(1, 2, 3, 4)) + observe_big_stack(1, 2, 3, 4, 5, 6, 7, 8, value);
    #|  if (value.a != 1) return 3;
    #|  if (value.b != 2) return 4;
    #|  return total;
    #|}
  assert_eq(run_source_strict_mir(source), 118)
}

///|
test "strict MIR codegen receives large aggregate parameters from clang callers" {
  let callee =
    #|struct BigArg { long a; long b; long c; long d; };
    #|int observe_big(struct BigArg value) {
    #|  value.a = 20;
    #|  return (int)(value.a + value.d);
    #|}
    #|int observe_big_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, long a7, struct BigArg value) {
    #|  value.b = 30;
    #|  return (int)(a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7 + value.b + value.d);
    #|}
  let driver =
    #|struct BigArg { long a; long b; long c; long d; };
    #|int observe_big(struct BigArg value);
    #|int observe_big_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, long a7, struct BigArg value);
    #|int main(void) {
    #|  struct BigArg value = { 1, 2, 3, 4 };
    #|  int total = observe_big(value) + observe_big_stack(1, 2, 3, 4, 5, 6, 7, 8, value);
    #|  if (value.a != 1) return 3;
    #|  if (value.b != 2) return 4;
    #|  return total;
    #|}
  assert_eq(run_strict_mir_with_clang_driver(callee, driver), 94)
}

///|
test "strict MIR codegen passes large aggregate parameters to clang callees" {
  let caller =
    #|struct BigArg { long a; long b; long c; long d; };
    #|struct BigArg make_big(long a, long b, long c, long d) {
    #|  struct BigArg value = { a, b, c, d };
    #|  return value;
    #|}
    #|int clang_observe_big(struct BigArg value);
    #|int clang_observe_big_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, long a7, struct BigArg value);
    #|int main(void) {
    #|  struct BigArg value = { 1, 2, 3, 4 };
    #|  int (*fp_big)(struct BigArg) = clang_observe_big;
    #|  int (*fp_stack)(long, long, long, long, long, long, long, long, struct BigArg) = clang_observe_big_stack;
    #|  int total = clang_observe_big(value) + fp_big(make_big(1, 2, 3, 4)) + fp_stack(1, 2, 3, 4, 5, 6, 7, 8, value);
    #|  if (value.a != 1) return 3;
    #|  if (value.b != 2) return 4;
    #|  return total;
    #|}
  let callee =
    #|struct BigArg { long a; long b; long c; long d; };
    #|int clang_observe_big(struct BigArg value) {
    #|  value.a = 20;
    #|  return (int)(value.a + value.d);
    #|}
    #|int clang_observe_big_stack(long a0, long a1, long a2, long a3, long a4, long a5, long a6, long a7, struct BigArg value) {
    #|  value.b = 30;
    #|  return (int)(a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7 + value.b + value.d);
    #|}
  assert_eq(run_strict_mir_with_clang_driver(caller, callee), 118)
}

///|
test "strict MIR codegen executes memory aggregate call results" {
  let source =
    #|struct Big { long a; long b; long c; };
    #|struct Big make_big(long a, long b, long c) {
    #|  struct Big p;
    #|  p.a = a;
    #|  p.b = b;
    #|  p.c = c;
    #|  return p;
    #|}
    #|int main(void) {
    #|  struct Big p = make_big(10, 20, 30);
    #|  struct Big q;
    #|  q = make_big(3, 4, 5);
    #|  return (int)(p.a + p.b + p.c + q.a + q.b + q.c);
    #|}
  assert_eq(run_source_strict_mir(source), 72)
}

///|
test "strict MIR codegen returns memory aggregates to clang callers" {
  let callee =
    #|struct Big { long a; long b; long c; };
    #|struct Big make_big(long a, long b, long c) {
    #|  struct Big p;
    #|  p.a = a;
    #|  p.b = b;
    #|  p.c = c;
    #|  return p;
    #|}
    #|struct Big forward_big(long a, long b, long c) {
    #|  return make_big(a + 1, b + 2, c + 3);
    #|}
  let driver =
    #|struct Big { long a; long b; long c; };
    #|struct Big make_big(long a, long b, long c);
    #|struct Big forward_big(long a, long b, long c);
    #|int main(void) {
    #|  struct Big p = make_big(10, 20, 30);
    #|  struct Big q = forward_big(3, 4, 5);
    #|  return (int)(p.a + p.b + p.c + q.a + q.b + q.c);
    #|}
  assert_eq(run_strict_mir_with_clang_driver(callee, driver), 78)
}

///|
test "strict MIR codegen takes address of aggregate objects" {
  let source =
    #|struct Pair { long a; long b; };
    #|struct Pair global_pair = { 5, 6 };
    #|int main(void) {
    #|  struct Pair local_pair = { 1, 2 };
    #|  struct Pair copy = { 0, 0 };
    #|  __builtin_memcpy(&copy, &local_pair, sizeof(copy));
    #|  if (copy.a + copy.b != 3) return 1;
    #|  __builtin_memcpy(&copy, &global_pair, sizeof(copy));
    #|  return (int)(copy.a + copy.b);
    #|}
  assert_eq(run_source_strict_mir(source), 11)
}

///|
test "strict MIR codegen accesses aggregate pointer members" {
  let source =
    #|struct Pair { long a; long b; };
    #|int sum_pair(struct Pair *p) {
    #|  p->a = p->a + 6;
    #|  return (int)(p->a + p->b);
    #|}
    #|int main(void) {
    #|  struct Pair local_pair = { 1, 2 };
    #|  struct Pair *p = &local_pair;
    #|  int seen = sum_pair(p);
    #|  if (local_pair.a != 7) return 1;
    #|  return seen;
    #|}
  assert_eq(run_source_strict_mir(source), 9)
}

///|
test "strict MIR codegen executes globals arrays and structs" {
  let source =
    #|struct Pair { int x; int y; };
    #|int g = 9;
    #|int main(void) {
    #|  int a[3];
    #|  struct Pair p;
    #|  a[0] = 2;
    #|  a[1] = 5;
    #|  p.x = a[0] + g;
    #|  p.y = a[1];
    #|  g = p.x + p.y;
    #|  return g;
    #|}
  assert_eq(run_source_strict_mir(source), 16)
}

///|
test "strict MIR codegen executes static nested array access" {
  let source =
    #|int main(void) {
    #|  static const unsigned char trans[2][3] = {
    #|    { 1, 2, 3 },
    #|    { 4, 5, 6 },
    #|  };
    #|  int i = 1;
    #|  int j = 2;
    #|  return trans[i][j];
    #|}
  assert_eq(run_source_strict_mir(source), 6)
}

///|
test "strict MIR codegen executes array element aggregate fields" {
  let source =
    #|struct Item { int v; };
    #|struct Db { struct Item a[2]; };
    #|int get(struct Db *db, int i) {
    #|  return db->a[i].v;
    #|}
    #|int main(void) {
    #|  struct Db db;
    #|  db.a[0].v = 4;
    #|  db.a[1].v = 7;
    #|  return get(&db, 1);
    #|}
  assert_eq(run_source_strict_mir(source), 7)
}

///|
test "strict MIR codegen executes bitfield loads and stores" {
  let source =
    #|struct Flags {
    #|  unsigned a : 1;
    #|  unsigned b : 2;
    #|  unsigned c : 3;
    #|};
    #|int main(void) {
    #|  struct Flags flags;
    #|  flags.a = 1;
    #|  flags.b = 2;
    #|  flags.c = 5;
    #|  return flags.a + (flags.b << 1) + (flags.c << 3);
    #|}
  assert_eq(run_source_strict_mir(source), 45)
}

///|
test "strict MIR codegen executes struct copies with bitfields" {
  let source =
    #|struct Flags {
    #|  int x;
    #|  unsigned a : 1;
    #|  unsigned b : 2;
    #|};
    #|int main(void) {
    #|  struct Flags flags;
    #|  flags.x = 30;
    #|  flags.a = 1;
    #|  flags.b = 2;
    #|  struct Flags copy = flags;
    #|  return copy.x + copy.a + (copy.b << 1);
    #|}
  assert_eq(run_source_strict_mir(source), 35)
}

///|
test "strict MIR codegen executes pointer arithmetic on local arrays" {
  let source =
    #|int main(void) {
    #|  int a[3];
    #|  int *p = a;
    #|  int *q;
    #|  q = a;
    #|  q[1] = 8;
    #|  return *(p + 1);
    #|}
  assert_eq(run_source_strict_mir(source), 8)
}

///|
test "strict MIR codegen executes casted object pointer byte offsets" {
  let source =
    #|struct S { unsigned char a; unsigned char b; };
    #|int main(void) {
    #|  struct S s;
    #|  s.a = 0;
    #|  s.b = 0;
    #|  *(((unsigned char *)&s) + __builtin_offsetof(struct S, b)) = 42;
    #|  return s.b;
    #|}
  assert_eq(run_source_strict_mir(source), 42)
}

///|
test "strict MIR codegen preserves memory compound update lhs across rhs" {
  let source =
    #|typedef unsigned long long Bitmask;
    #|struct Item { Bitmask colUsed; };
    #|
    #|void mark(struct Item *item, int iCol) {
    #|  item->colUsed |= ((Bitmask)1) << (iCol >= 64 ? 63 : iCol);
    #|}
    #|
    #|int main(void) {
    #|  struct Item item;
    #|  Bitmask b;
    #|  int n = 0;
    #|  item.colUsed = 0;
    #|  for (int i = 0; i < 5; i = i + 1) {
    #|    mark(&item, i);
    #|  }
    #|  for (b = item.colUsed; b; b = b >> 1) {
    #|    n = n + 1;
    #|  }
    #|  return n;
    #|}
  assert_eq(run_source_strict_mir(source), 5)
}

///|
test "strict MIR codegen preserves pointer memory update lhs across rhs" {
  let source =
    #|struct Holder { int *p; };
    #|
    #|int step(int *base) {
    #|  return base[0] - 2;
    #|}
    #|
    #|int main(void) {
    #|  int values[3];
    #|  struct Holder holder;
    #|  values[0] = 3;
    #|  values[1] = 17;
    #|  values[2] = 29;
    #|  holder.p = values;
    #|  holder.p += step(values);
    #|  return *holder.p;
    #|}
  assert_eq(run_source_strict_mir(source), 17)
}

///|
test "strict MIR codegen executes direct array decay in pointer arithmetic" {
  let source =
    #|int main(void) {
    #|  int a[3];
    #|  a[0] = 3;
    #|  a[1] = 6;
    #|  return *(a + 1);
    #|}
  assert_eq(run_source_strict_mir(source), 6)
}

///|
test "strict MIR codegen executes ternary local array decay before indexing" {
  let source =
    #|int main(void) {
    #|  int a[2];
    #|  int b[2];
    #|  a[0] = 3;
    #|  a[1] = 5;
    #|  b[0] = 7;
    #|  b[1] = 11;
    #|  return (1 ? a : b)[1] + (0 ? a : b)[0];
    #|}
  assert_eq(run_source_strict_mir(source), 12)
}

///|
test "strict MIR codegen executes member array decay in pointer differences" {
  let source =
    #|struct S { int a[4]; unsigned char iPrev; };
    #|int main(void) {
    #|  struct S s;
    #|  int *p = &s.a[2];
    #|  s.iPrev = (unsigned char)(p - s.a);
    #|  return s.iPrev;
    #|}
  assert_eq(run_source_strict_mir(source), 2)
}

///|
test "strict MIR codegen executes member array decay in pointer comparisons" {
  let source =
    #|struct S { int *p; int a[2]; };
    #|int main(void) {
    #|  struct S s;
    #|  s.p = s.a;
    #|  return s.p == s.a;
    #|}
  assert_eq(run_source_strict_mir(source), 1)
}

///|
test "strict MIR codegen executes local aggregate array initializers" {
  let source =
    #|struct Item { const char *z; int a; int b; };
    #|int main(void) {
    #|  struct Item items[] = {
    #|    { "x", 1, 2 },
    #|    { "y", 3, 4 },
    #|  };
    #|  return items[1].a + items[0].b + (items[0].z == items[1].z);
    #|}
  assert_eq(run_source_strict_mir(source), 5)
}

///|
test "strict MIR codegen executes global aggregate copies" {
  let source =
    #|struct Item { int x; int *p; };
    #|static const struct Item zeroItem = {0};
    #|int main(void) {
    #|  struct Item items[1];
    #|  struct Item *p = &items[0];
    #|  p->x = 7;
    #|  p->p = (int*)1;
    #|  *p = zeroItem;
    #|  return p->x + (p->p != 0);
    #|}
  assert_eq(run_source_strict_mir(source), 0)
}

///|
test "strict MIR codegen copies aggregate into global member from va_arg pointer" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|struct Pair { int a; int b; };
    #|struct Config { struct Pair pair; };
    #|struct Config cfg;
    #|int set_pair(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  cfg.pair = *__builtin_va_arg(ap, struct Pair*);
    #|  *__builtin_va_arg(ap, struct Pair*) = cfg.pair;
    #|  __builtin_va_end(ap);
    #|  return cfg.pair.b;
    #|}
    #|int main(void) {
    #|  struct Pair input = { 7, 35 };
    #|  struct Pair output = { 0, 0 };
    #|  return set_pair(0, &input, &output) + output.a;
    #|}
  assert_eq(run_source_strict_mir(source), 42)
}

///|
test "strict MIR codegen executes global aggregate float array initializers" {
  let source =
    #|struct Xform {
    #|  unsigned char nName;
    #|  char zName[7];
    #|  float rLimit;
    #|  float rXform;
    #|};
    #|static const struct Xform xs[] = {
    #|  { 6, "second", 4.5f, 4.5f },
    #|  { 4, "hour", 20.0f, 3.0f },
    #|};
    #|int main(void) {
    #|  return xs[1].nName + xs[0].zName[0] - 115
    #|       + (int)xs[1].rLimit + (int)(xs[0].rXform * 4.0f);
    #|}
  assert_eq(run_source_strict_mir(source), 42)
}

///|
test "strict MIR codegen executes casted string pointer global array initializers" {
  let source =
    #|typedef unsigned char u8;
    #|static unsigned char * const azOne[] = { (u8*)" " };
    #|int read_ending(void) {
    #|  static const char *azEndings[] = { "dylib" };
    #|  return azEndings[0][0] - 58;
    #|}
    #|int main(void) {
    #|  return azOne[0][0] + read_ending() - 32;
    #|}
  assert_eq(run_source_strict_mir(source), 42)
}

///|
test "strict MIR codegen executes aggregate ternary copies" {
  let source =
    #|struct Token { char *z; int n; };
    #|union U { struct Token tok; int i; };
    #|int main(void) {
    #|  union U stack[2];
    #|  union U *p = &stack[1];
    #|  p[-1].tok.z = "left";
    #|  p[-1].tok.n = 3;
    #|  p[0].tok.z = "right";
    #|  p[0].tok.n = 5;
    #|  p[-1].tok = (p[0].tok.n == 0 ? p[-1].tok : p[0].tok);
    #|  int first = p[-1].tok.n;
    #|  p[-1].tok.n = 8;
    #|  p[0].tok.n = 0;
    #|  p[-1].tok = (p[0].tok.n == 0 ? p[0].tok : p[-1].tok);
    #|  return first * 10 + p[-1].tok.n;
    #|}
  assert_eq(run_source_strict_mir(source), 50)
}

///|
test "strict MIR codegen ignores aggregate void casts" {
  let source =
    #|struct Token { int n; };
    #|int main(void) {
    #|  struct Token t;
    #|  t.n = 42;
    #|  (void)t;
    #|  return t.n;
    #|}
  assert_eq(run_source_strict_mir(source), 42)
}

///|
test "strict MIR codegen executes member array decay in pointer call args" {
  let source =
    #|struct Info { unsigned aReadMark[4]; };
    #|unsigned load_mark(struct Info *pInfo, int i) {
    #|  return __atomic_load_n(pInfo->aReadMark + i, 0);
    #|}
    #|void store_mark(struct Info *pInfo, int i, unsigned value) {
    #|  __atomic_store_n(pInfo->aReadMark + i, value, 0);
    #|}
    #|int main(void) {
    #|  struct Info info;
    #|  info.aReadMark[0] = 5;
    #|  info.aReadMark[1] = 7;
    #|  store_mark(&info, 1, 37);
    #|  return (int)(load_mark(&info, 0) + load_mark(&info, 1));
    #|}
  assert_eq(run_source_strict_mir(source), 42)
}

///|
test "strict MIR codegen executes anonymous union array member decay" {
  let source =
    #|typedef unsigned char uint8_t;
    #|typedef unsigned long size_t;
    #|typedef struct TinyAlloc {
    #|  uint8_t *p;
    #|  uint8_t *bufend;
    #|  union {
    #|    uint8_t buffer[1];
    #|    size_t _aligner_;
    #|  };
    #|} TinyAlloc;
    #|int main(void) {
    #|  TinyAlloc al;
    #|  al.p = al.buffer;
    #|  al.bufend = al.buffer + 1;
    #|  return (int)(al.bufend - al.p);
    #|}
  assert_eq(run_source_strict_mir(source), 1)
}

///|
test "strict MIR codegen calls local extern function prototypes" {
  let callee =
    #|int read_external(void) {
    #|  extern int *external_ptr(void);
    #|  return *external_ptr();
    #|}
  let driver =
    #|int value = 37;
    #|int *external_ptr(void) {
    #|  return &value;
    #|}
    #|int read_external(void);
    #|int main(void) {
    #|  return read_external();
    #|}
  assert_eq(run_strict_mir_with_clang_driver(callee, driver), 37)
}

///|
test "strict MIR codegen executes local pointer updates" {
  let source =
    #|int main(void) {
    #|  char buf[4];
    #|  char *p = buf;
    #|  p++;
    #|  *p = 7;
    #|  p += 1;
    #|  *p = 9;
    #|  return buf[1] + buf[2];
    #|}
  assert_eq(run_source_strict_mir(source), 16)
}

///|
test "strict MIR codegen executes casted pointer dereference" {
  let source =
    #|int main(void) {
    #|  char c = 37;
    #|  char *p = &c;
    #|  return *(unsigned char*)p;
    #|}
  assert_eq(run_source_strict_mir(source), 37)
}

///|
test "strict MIR codegen executes casted global array decay" {
  let source =
    #|int a[3] = {4, 5, 6};
    #|int *get(int *pn) {
    #|  *pn = sizeof(a) / sizeof(a[0]);
    #|  return (int*)a;
    #|}
    #|int main(void) {
    #|  int n = 0;
    #|  int *p = get(&n);
    #|  return p[1] + n;
    #|}
  assert_eq(run_source_strict_mir(source), 8)
}

///|
test "strict MIR codegen returns implicit global array decay" {
  let source =
    #|char version[4] = "abc";
    #|char *get(void) {
    #|  return version;
    #|}
    #|int main(void) {
    #|  char *p = get();
    #|  return p[1];
    #|}
  assert_eq(run_source_strict_mir(source), 98)
}

///|
test "strict MIR codegen executes floating local casts to int" {
  let source =
    #|int main(void) {
    #|  double x = 1.75;
    #|  double y = 2.25;
    #|  return (int)x + (int)y;
    #|}
  assert_eq(run_source_strict_mir(source), 3)
}

///|
test "strict MIR codegen executes floating local comparisons" {
  let source =
    #|int main(void) {
    #|  double x = 1.5;
    #|  double y = 2.5;
    #|  return (x < y) + (x != y) + (y > 2.0) + (x == 1.5) + (x <= y) + (y >= x);
    #|}
  assert_eq(run_source_strict_mir(source), 6)
}

///|
test "strict MIR codegen executes floating ternary conversions" {
  let source =
    #|int main(void) {
    #|  double c = 1.0;
    #|  double z = 0.0;
    #|  double d = c ? 3 : 2.5;
    #|  float f = c ? (float)1.25 : 4;
    #|  int a = c ? 5 : 7;
    #|  int b = z ? 9 : 11;
    #|  return (int)(d * 10) + (int)(f * 10) + a + b;
    #|}
  assert_eq(run_source_strict_mir(source), 58)
}

///|
test "strict MIR codegen executes floating logical operators" {
  let source =
    #|int g;
    #|int bump(void) {
    #|  g = g + 1;
    #|  return 1;
    #|}
    #|int main(void) {
    #|  double z = 0.0;
    #|  double x = 1.5;
    #|  double n = z / z;
    #|  int a = !z;
    #|  int b = !x;
    #|  int c = !n;
    #|  int d = z || bump();
    #|  int e = x || bump();
    #|  int f = z && bump();
    #|  int h = x && bump();
    #|  int i = n && bump();
    #|  int j = n || bump();
    #|  if (a != 1) return 1;
    #|  if (b != 0) return 2;
    #|  if (c != 0) return 3;
    #|  if (d != 1) return 4;
    #|  if (e != 1) return 5;
    #|  if (f != 0) return 6;
    #|  if (h != 1) return 7;
    #|  if (i != 1) return 8;
    #|  if (j != 1) return 9;
    #|  if (g != 3) return 10;
    #|  return 37;
    #|}
  assert_eq(run_source_strict_mir(source), 37)
}

///|
test "strict MIR codegen executes floating compound updates" {
  let source =
    #|int main(void) {
    #|  double x = 1.5;
    #|  double old = x++;
    #|  x += 2.5;
    #|  x *= 2.0;
    #|  double arr[1];
    #|  arr[0] = 3.0;
    #|  double *p = arr;
    #|  double before = (*p)++;
    #|  *p += 4.0;
    #|  float f = (float)1.25;
    #|  ++f;
    #|  f *= (float)2.0;
    #|  int i = 1;
    #|  i += 2.5;
    #|  int ints[1];
    #|  ints[0] = 1;
    #|  int *q = ints;
    #|  *q += 2.5;
    #|  return (int)(old * 10) + (int)x + (int)(before * 10) + (int)arr[0] + (int)(f * 10) + i + ints[0];
    #|}
  assert_eq(run_source_strict_mir(source), 114)
}

///|
test "strict MIR codegen executes floating local arithmetic" {
  let source =
    #|int main(void) {
    #|  double x = 5.5;
    #|  double y = 2.0;
    #|  return (int)(x + y) + (int)(x - y) + (int)(x * y) + (int)(x / y) + (int)(x + 2);
    #|}
  assert_eq(run_source_strict_mir(source), 30)
}

///|
test "strict MIR codegen executes float local arithmetic" {
  let source =
    #|int main(void) {
    #|  float x = (float)5.5;
    #|  float y = (float)2.0;
    #|  return (int)(x + y) + (int)(x - y) + (int)(x * y) + (int)(x / y) + (int)(x + 2);
    #|}
  assert_eq(run_source_strict_mir(source), 30)
}

///|
test "strict MIR codegen executes floating unary operators" {
  let source =
    #|int main(void) {
    #|  double d = 3.5;
    #|  float f = (float)2.25;
    #|  if ((int)(-d) != -3) return 1;
    #|  if ((int)(-f) != -2) return 2;
    #|  if ((int)(+d) != 3) return 3;
    #|  if ((int)(+f) != 2) return 4;
    #|  return 37;
    #|}
  assert_eq(run_source_strict_mir(source), 37)
}

///|
test "strict MIR codegen executes floating direct calls" {
  let source =
    #|double add(double x, double y) { return x + y; }
    #|double mix(int a, double b, int c) { return a + b + c; }
    #|int main(void) {
    #|  return (int)add(2.25, 3.75) + (int)mix(2, 3.5, 4);
    #|}
  assert_eq(run_source_strict_mir(source), 15)
}

///|
test "strict MIR codegen executes stack-passed floating direct calls" {
  let source =
    #|double sum9d(double a, double b, double c, double d, double e, double f, double g, double h, double i) {
    #|  return a + b + c + d + e + f + g + h + i;
    #|}
    #|float sum9f(float a, float b, float c, float d, float e, float f, float g, float h, float i) {
    #|  return a + b + c + d + e + f + g + h + i;
    #|}
    #|int main(void) {
    #|  return (int)sum9d(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0) +
    #|    (int)sum9f((float)1.0, (float)2.0, (float)3.0, (float)4.0, (float)5.0, (float)6.0, (float)7.0, (float)8.0, (float)9.0);
    #|}
  assert_eq(run_source_strict_mir(source), 90)
}

///|
test "strict MIR codegen executes float direct and indirect calls" {
  let source =
    #|float addf(float x, float y) { return x + y; }
    #|float mixf(int a, float b, int c) { return a + b + c; }
    #|int main(void) {
    #|  float (*fp)(float, float) = addf;
    #|  return (int)addf((float)2.25, (float)3.75) + (int)mixf(2, (float)3.5, 4) + (int)fp((float)1.25, (float)2.75);
    #|}
  assert_eq(run_source_strict_mir(source), 19)
}

///|
test "strict MIR codegen executes floating indirect calls" {
  let source =
    #|double add(double x, double y) { return x + y; }
    #|double mix(int a, double b, int c) { return a + b + c; }
    #|int main(void) {
    #|  double (*fp)(double, double) = add;
    #|  double (*gp)(int, double, int) = mix;
    #|  return (int)fp(2.25, 3.75) + (int)gp(2, 3.5, 4);
    #|}
  assert_eq(run_source_strict_mir(source), 15)
}

///|
test "strict MIR codegen executes indirect calls returning function pointers" {
  let source =
    #|int global;
    #|void target(int value) {
    #|  global = value;
    #|}
    #|void (*pick(int tag))(int) {
    #|  if (tag) return target;
    #|  return target;
    #|}
    #|int main(void) {
    #|  void (*(*fp)(int))(int) = pick;
    #|  void (*fn)(int) = fp(1);
    #|  fn(37);
    #|  return global;
    #|}
  assert_eq(run_source_strict_mir(source), 37)
}

///|
test "strict MIR codegen executes stack-passed floating indirect calls" {
  let source =
    #|double sum9d(double a, double b, double c, double d, double e, double f, double g, double h, double i) {
    #|  return a + b + c + d + e + f + g + h + i;
    #|}
    #|float sum9f(float a, float b, float c, float d, float e, float f, float g, float h, float i) {
    #|  return a + b + c + d + e + f + g + h + i;
    #|}
    #|int main(void) {
    #|  double (*dp)(double, double, double, double, double, double, double, double, double) = sum9d;
    #|  float (*fp)(float, float, float, float, float, float, float, float, float) = sum9f;
    #|  return (int)dp(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0) +
    #|    (int)fp((float)1.0, (float)2.0, (float)3.0, (float)4.0, (float)5.0, (float)6.0, (float)7.0, (float)8.0, (float)9.0);
    #|}
  assert_eq(run_source_strict_mir(source), 90)
}

///|
test "strict MIR codegen executes floating variadic libcalls" {
  let source =
    #|int main(void) {
    #|  char buf[64];
    #|  int n = __builtin___snprintf_chk(buf, 64, 0, 64, "%.1f", 1.5);
    #|  return n + (buf[0] == '1') + (buf[1] == '.') + (buf[2] == '5');
    #|}
  assert_eq(run_source_strict_mir(source), 6)
}

///|
test "strict MIR codegen executes stack-passed floating variadic libcalls" {
  let source =
    #|int main(void) {
    #|  char buf[32];
    #|  int n = __builtin___snprintf_chk(buf, 32, 0, 32, "%.0f%.0f%.0f%.0f%.0f%.0f%.0f%.0f%.0f", 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0);
    #|  return n + (buf[0] == '1') + (buf[1] == '2') + (buf[2] == '3') + (buf[3] == '4') + (buf[4] == '5') + (buf[5] == '6') + (buf[6] == '7') + (buf[7] == '8') + (buf[8] == '9');
    #|}
  assert_eq(run_source_strict_mir(source), 18)
}

///|
test "strict MIR codegen executes stack-passed integer variadic libcalls" {
  let source =
    #|int main(void) {
    #|  char buf[32];
    #|  int n = __builtin___snprintf_chk(buf, 32, 0, 32, "%d%d%d%d%d%d", 1, 2, 3, 4, 5, 6);
    #|  return n + (buf[0] == '1') + (buf[1] == '2') + (buf[2] == '3') + (buf[3] == '4') + (buf[4] == '5') + (buf[5] == '6');
    #|}
  assert_eq(run_source_strict_mir(source), 12)
}

///|
test "strict MIR codegen executes checked vsnprintf va_list libcall" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int write_fmt(char *buf, unsigned long size, const char *fmt, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, fmt);
    #|  int n = __builtin___vsnprintf_chk(buf, size, 0, size, fmt, ap);
    #|  __builtin_va_end(ap);
    #|  return n;
    #|}
    #|int main(void) {
    #|  char buf[16];
    #|  int n = write_fmt(buf, 16, "%d-%s", 42, "ok");
    #|  return n + (buf[0] == '4') + (buf[1] == '2') + (buf[2] == '-') + (buf[3] == 'o') + (buf[4] == 'k');
    #|}
  assert_eq(run_source_strict_mir(source), 10)
}

///|
test "strict MIR codegen executes scalar va_arg reads" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int read_variadic(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  int a = __builtin_va_arg(ap, int);
    #|  long long b = __builtin_va_arg(ap, long long);
    #|  double c = __builtin_va_arg(ap, double);
    #|  __builtin_va_end(ap);
    #|  return tag + a + (int)b + (int)c;
    #|}
    #|int main(void) {
    #|  return read_variadic(4, 10, 20LL, 3.5);
    #|}
  assert_eq(run_source_strict_mir(source), 37)
}

///|
test "strict MIR codegen executes stores through va_arg pointers" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|void write_variadic(int value, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, value);
    #|  *__builtin_va_arg(ap, int*) = value;
    #|  __builtin_va_end(ap);
    #|}
    #|int main(void) {
    #|  int x = 0;
    #|  write_variadic(37, &x);
    #|  return x;
    #|}
  assert_eq(run_source_strict_mir(source), 37)
}

///|
test "strict MIR codegen executes aggregate va_arg reads from clang caller" {
  let callee =
    #|typedef __builtin_va_list va_list;
    #|struct Pair { long long a; long long b; };
    #|int read_pair(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  struct Pair p = __builtin_va_arg(ap, struct Pair);
    #|  __builtin_va_end(ap);
    #|  return tag + (int)p.a + (int)p.b;
    #|}
  let driver =
    #|struct Pair { long long a; long long b; };
    #|int read_pair(int tag, ...);
    #|int main(void) {
    #|  struct Pair p = {10, 20};
    #|  return read_pair(4, p);
    #|}
  assert_eq(run_strict_mir_with_clang_driver(callee, driver), 34)
}

///|
test "strict MIR codegen executes aggregate va_arg reads from MIR caller" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|struct Pair { long long a; long long b; };
    #|int read_pair(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  struct Pair p = __builtin_va_arg(ap, struct Pair);
    #|  __builtin_va_end(ap);
    #|  return tag + (int)p.a + (int)p.b;
    #|}
    #|int main(void) {
    #|  struct Pair p = {10, 20};
    #|  return read_pair(4, p);
    #|}
  assert_eq(run_source_strict_mir(source), 34)
}

///|
test "strict MIR codegen executes Darwin long double scalar ops" {
  let source =
    #|int main(void) {
    #|  long double d = 1.0L;
    #|  d = d + 2.0L;
    #|  return (int)d;
    #|}
  assert_eq(run_source_strict_mir(source), 3)
}

///|
test "strict MIR codegen executes loads through global address cancellation" {
  let source =
    #|char buf[3] = {4, 5, 0};
    #|char *macro_ptr = buf;
    #|int tok;
    #|int next_token(void) {
    #|  int t = **(&macro_ptr);
    #|  *(&tok) = t, ++*(&macro_ptr);
    #|  return tok + **(&macro_ptr);
    #|}
    #|int main(void) {
    #|  return next_token();
    #|}
  assert_eq(run_source_strict_mir(source), 9)
}

///|
test "strict MIR codegen executes TinyCC-style aggregate copies" {
  let source =
    #|typedef unsigned long long uint64_t;
    #|typedef struct CType { int t; void *ref; } CType;
    #|typedef union CValue {
    #|  long double ld;
    #|  double d;
    #|  float f;
    #|  uint64_t i;
    #|  struct { char *data; int size; } str;
    #|  int tab[((sizeof(long double)+3)/4)];
    #|} CValue;
    #|typedef struct SValue {
    #|  CType type;
    #|  unsigned short r;
    #|  unsigned short r2;
    #|  union { struct { int jtrue, jfalse; }; CValue c; };
    #|  union { struct { unsigned short cmp_op, cmp_r; }; void *sym; };
    #|} SValue;
    #|SValue stack[2];
    #|SValue *vtop = &stack[1];
    #|void vsetc(CType *type, int r, CValue *vc) {
    #|  vtop->type = *type;
    #|  vtop->r = r;
    #|  vtop->r2 = 0x0030;
    #|  vtop->c = *vc;
    #|  vtop->sym = (void*)0;
    #|}
    #|void vswap(void) {
    #|  SValue tmp;
    #|  tmp = vtop[0];
    #|  vtop[0] = vtop[-1];
    #|  vtop[-1] = tmp;
    #|}
    #|int main(void) {
    #|  CType ty = {7, (void*)0};
    #|  CValue value;
    #|  value.str.data = (char*)0;
    #|  value.str.size = 21;
    #|  stack[0].c.i = 9;
    #|  vsetc(&ty, 3, &value);
    #|  vswap();
    #|  return stack[0].c.str.size + (int)stack[1].c.i;
    #|}
  assert_eq(run_source_strict_mir(source), 30)
}

///|
test "strict MIR codegen executes comma aggregate assignments" {
  let source =
    #|struct S { int a; int b; };
    #|struct S values[2];
    #|int main(void) {
    #|  struct S tmp;
    #|  values[0].a = 1;
    #|  values[1].a = 2;
    #|  tmp = values[0], values[0] = values[1], values[1] = tmp;
    #|  return values[0].a * 10 + values[1].a;
    #|}
  assert_eq(run_source_strict_mir(source), 21)
}

///|
test "strict MIR codegen executes bitfield compound updates" {
  let source =
    #|struct SymAttr {
    #|  unsigned short aligned : 5, packed : 1, weak : 1, visibility : 2;
    #|};
    #|int main(void) {
    #|  struct SymAttr a = {0};
    #|  struct SymAttr b = {0};
    #|  b.packed = 1;
    #|  b.weak = 1;
    #|  a.packed |= b.packed;
    #|  a.weak |= b.weak;
    #|  return a.packed + 2 * a.weak;
    #|}
  assert_eq(run_source_strict_mir(source), 3)
}

///|
test "strict MIR codegen executes floating comma stores" {
  let source =
    #|union U { float f; unsigned u; };
    #|int main(void) {
    #|  union U x1, x2;
    #|  x1.f = 1.0f, x2.f = -0.0f;
    #|  return (x1.u == 0x3f800000u) + (x2.u == 0x80000000u);
    #|}
  assert_eq(run_source_strict_mir(source), 2)
}

///|
test "strict MIR codegen executes floating fabs and infinity builtins" {
  let source =
    #|int finitef(float x) {
    #|  return x == x && __builtin_fabsf(x) != __builtin_inff();
    #|}
    #|int finited(double x) {
    #|  return x == x && __builtin_fabs(x) != __builtin_inf();
    #|}
    #|int main(void) {
    #|  return finitef(-3.5f) +
    #|    2 * finitef(__builtin_inff()) +
    #|    4 * finited(-4.5) +
    #|    8 * finited(__builtin_inf());
    #|}
  assert_eq(run_source_strict_mir(source), 5)
}

///|
test "strict MIR codegen executes long double fabs and infinity builtins" {
  let source =
    #|int finitel(long double x) {
    #|  return x == x && __builtin_fabsl(x) != __builtin_infl();
    #|}
    #|int main(void) {
    #|  return finitel(-5.5L) + 2 * finitel(__builtin_infl());
    #|}
  assert_eq(run_source_strict_mir(source), 1)
}

///|
test "strict MIR codegen executes count zero builtins" {
  let source =
    #|typedef unsigned long long uint64_t;
    #|static inline int clz32(unsigned int a) { return __builtin_clz(a); }
    #|static inline int clz64(uint64_t a) { return __builtin_clzll(a); }
    #|static inline int ctz32(unsigned int a) { return __builtin_ctz(a); }
    #|static inline int ctz64(uint64_t a) { return __builtin_ctzll(a); }
    #|int main(void) {
    #|  return clz32(1u) + clz64(1ull) + ctz32(8u) + ctz64(16ull);
    #|}
  assert_eq(run_source_strict_mir(source), 101)
}

///|
test "strict MIR codegen returns aggregate compound literals" {
  let source =
    #|typedef union ValueUnion {
    #|  int int32;
    #|  double float64;
    #|  void *ptr;
    #|  long long short_big_int;
    #|} ValueUnion;
    #|typedef struct Value {
    #|  ValueUnion u;
    #|  long tag;
    #|} Value;
    #|Value new_bool(int val) {
    #|  return (Value){ (ValueUnion){ .int32 = (val != 0) }, 1 };
    #|}
    #|int main(void) {
    #|  Value v = new_bool(42);
    #|  return v.u.int32 + (int)v.tag * 10;
    #|}
  assert_eq(run_source_strict_mir(source), 11)
}

///|
test "strict MIR codegen returns identity-cast aggregate arguments" {
  let source =
    #|typedef union ValueUnion {
    #|  int int32;
    #|  double float64;
    #|  void *ptr;
    #|  long long short_big_int;
    #|} ValueUnion;
    #|typedef struct Value {
    #|  ValueUnion u;
    #|  long tag;
    #|} Value;
    #|typedef struct Header {
    #|  int ref_count;
    #|} Header;
    #|Value dup(Value v) {
    #|  if ((unsigned)((int)(v).tag) >= (unsigned)-9) {
    #|    Header *p = (Header *)((v).u.ptr);
    #|    p->ref_count++;
    #|  }
    #|  return (Value)v;
    #|}
    #|int main(void) {
    #|  Value v = (Value){ (ValueUnion){ .int32 = 7 }, 1 };
    #|  Value out = dup(v);
    #|  return out.u.int32;
    #|}
  assert_eq(run_source_strict_mir(source), 7)
}

///|
test "strict MIR codegen executes typedef function pointer aggregate returns" {
  let source =
    #|typedef union ValueUnion {
    #|  int int32;
    #|  double float64;
    #|  void *ptr;
    #|  long long short_big_int;
    #|} ValueUnion;
    #|typedef struct Value {
    #|  ValueUnion u;
    #|  long tag;
    #|} Value;
    #|typedef Value JobFunc(int argc, Value *argv);
    #|Value make(int argc, Value *argv) {
    #|  return argv[argc - 1];
    #|}
    #|int main(void) {
    #|  Value args[2];
    #|  args[0] = (Value){ (ValueUnion){ .int32 = 3 }, 1 };
    #|  args[1] = (Value){ (ValueUnion){ .int32 = 9 }, 1 };
    #|  JobFunc *job_func = make;
    #|  Value res = job_func(2, (Value *)args);
    #|  return res.u.int32;
    #|}
  assert_eq(run_source_strict_mir(source), 9)
}

///|
test "strict MIR codegen passes aggregate compound literal arguments" {
  let source =
    #|typedef union ValueUnion {
    #|  int int32;
    #|  double float64;
    #|  void *ptr;
    #|  long long short_big_int;
    #|} ValueUnion;
    #|typedef struct Value {
    #|  ValueUnion u;
    #|  long tag;
    #|} Value;
    #|int observe(Value v) {
    #|  return v.u.int32 + (int)v.tag * 10;
    #|}
    #|int main(void) {
    #|  return observe((Value){ (ValueUnion){ .int32 = 4 }, 2 });
    #|}
  assert_eq(run_source_strict_mir(source), 24)
}

///|
test "strict MIR codegen executes bitfield post increment" {
  let source =
    #|struct S {
    #|  unsigned int len : 31;
    #|  unsigned char wide : 1;
    #|  unsigned short data[8];
    #|};
    #|int main(void) {
    #|  struct S s;
    #|  struct S *p = &s;
    #|  p->len = 2;
    #|  p->data[p->len++] = 9;
    #|  return p->len + p->data[2];
    #|}
  assert_eq(run_source_strict_mir(source), 12)
}

///|
test "strict MIR codegen reads fields from aggregate call results" {
  let source =
    #|typedef union ValueUnion {
    #|  int int32;
    #|  double float64;
    #|  void *ptr;
    #|  long long short_big_int;
    #|} ValueUnion;
    #|typedef struct Value {
    #|  ValueUnion u;
    #|  long tag;
    #|} Value;
    #|Value make(int value) {
    #|  return (Value){ (ValueUnion){ .int32 = value }, 3 };
    #|}
    #|int main(void) {
    #|  return make(5).u.int32 + (int)make(2).tag;
    #|}
  assert_eq(run_source_strict_mir(source), 8)
}

///|
test "strict MIR codegen returns aggregate members" {
  let source =
    #|typedef union ValueUnion {
    #|  int int32;
    #|  double float64;
    #|  void *ptr;
    #|  long long short_big_int;
    #|} ValueUnion;
    #|typedef struct Value {
    #|  ValueUnion u;
    #|  long tag;
    #|} Value;
    #|struct Desc {
    #|  int flags;
    #|  Value value;
    #|};
    #|Value pick(struct Desc *desc) {
    #|  return desc->value;
    #|}
    #|int main(void) {
    #|  struct Desc desc;
    #|  desc.value = (Value){ (ValueUnion){ .int32 = 6 }, 4 };
    #|  Value value = pick(&desc);
    #|  return value.u.int32 + (int)value.tag;
    #|}
  assert_eq(run_source_strict_mir(source), 10)
}

///|
test "strict MIR codegen passes identity-cast aggregate arguments" {
  let source =
    #|typedef union ValueUnion {
    #|  int int32;
    #|  double float64;
    #|  void *ptr;
    #|  long long short_big_int;
    #|} ValueUnion;
    #|typedef struct Value {
    #|  ValueUnion u;
    #|  long tag;
    #|} Value;
    #|int observe(Value value) {
    #|  return value.u.int32 + (int)value.tag;
    #|}
    #|int main(void) {
    #|  Value value = (Value){ (ValueUnion){ .int32 = 8 }, 5 };
    #|  return observe((Value)value);
    #|}
  assert_eq(run_source_strict_mir(source), 13)
}

///|
test "strict MIR codegen executes function typedef pointer calls" {
  let source =
    #|typedef int Callback(void *data, int value);
    #|struct Hook { Callback *call; void *data; };
    #|int add(void *data, int value) {
    #|  return *(int*)data + value;
    #|}
    #|int main(void) {
    #|  int base = 5;
    #|  struct Hook hook;
    #|  hook.call = add;
    #|  hook.data = &base;
    #|  return hook.call(hook.data, 7);
    #|}
  assert_eq(run_source_strict_mir(source), 12)
}
