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
