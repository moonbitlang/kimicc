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
fn strict_mir_codegen_error(source : String) -> String {
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
    Ok(_) => abort("strict MIR codegen unexpectedly succeeded")
    Err(err) => err
  }
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
test "strict MIR codegen rejects unsupported floating body instead of using AST fallback" {
  let source =
    #|int main(void) {
    #|  double x = 1.5;
    #|  return (int)(x + 1.0);
    #|}
  assert_true(
    strict_mir_codegen_error(source).contains("unsupported MIR body codegen"),
  )
}
