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
