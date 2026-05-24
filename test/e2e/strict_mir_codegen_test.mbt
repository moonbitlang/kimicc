///|
fn compile_strict_mir(source : String) -> String {
  compile_strict_mir_for_target(source, @target.Target::default())
}

///|
fn compile_strict_mir_for_target(
  source : String,
  target : @target.Target,
) -> String {
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
fn strict_mir_scalar_control_flow_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes scalar control flow and calls" {
  let source = strict_mir_scalar_control_flow_source()
  assert_eq(run_source_strict_mir(source), 17)
}

///|
async test "strict MIR codegen matches parser codegen for scalar control flow and calls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_scalar_control_flow_source(),
    "strict_mir_scalar_control_flow_differential",
  )
  assert_eq(result.code, 17)
}

///|
fn strict_mir_generic_selection_source() -> String {
  let source =
    #|int main(void) {
    #|  int x = 0;
    #|  int arr[3];
    #|  double d = 0.0;
    #|  unsigned long u = 0;
    #|  int score = 0;
    #|  score = score + _Generic(x, int: 10, default: 100);
    #|  score = score + _Generic(d, double: 20, default: 100);
    #|  score = score + _Generic("x", char *: 12, char[2]: 100, default: 100);
    #|  score = score + _Generic(arr, int *: 0, int[3]: 100, default: 100);
    #|  score = score + _Generic(x++, int: 0, default: 100);
    #|  if (x != 0) return 1;
    #|  if (_Generic((0, u), unsigned long: 0, default: 1)) return 2;
    #|  return score;
    #|}
  source
}

///|
test "strict MIR codegen executes generic selection lowering" {
  let source = strict_mir_generic_selection_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for generic selection lowering" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_generic_selection_source(),
    "strict_mir_generic_selection_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_builtin_choose_expr_source() -> String {
  let source =
    #|int missing(void);
    #|int main(void) {
    #|  return __builtin_choose_expr(__builtin_types_compatible_p(int, signed int), 40, missing()) +
    #|         __builtin_choose_expr(__builtin_types_compatible_p(int, unsigned int), missing(), 2);
    #|}
  source
}

///|
test "strict MIR codegen executes builtin choose expression lowering" {
  let source = strict_mir_builtin_choose_expr_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for builtin choose expression lowering" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_builtin_choose_expr_source(),
    "strict_mir_builtin_choose_expr_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_compile_time_type_fact_source() -> String {
  let source =
    #|struct S { int x; };
    #|union U { int x; double y; };
    #|int main(void) {
    #|  int x = 0;
    #|  double d = 0.0;
    #|  int a[2];
    #|  struct S s;
    #|  union U u;
    #|  __typeof__(x++) y = 20;
    #|  if (x != 0) return 1;
    #|  typeof(unsigned long) z = 20;
    #|  __auto_type bonus = 2;
    #|  __auto_type p = &bonus;
    #|  for (__auto_type i = 0; i < *p; i++) y = y + 1;
    #|  if (__builtin_classify_type(x++) != 1) return 3;
    #|  if (x != 0) return 4;
    #|  if (__builtin_classify_type((_Bool)0) != 4) return 5;
    #|  if (__builtin_classify_type(d) != 8) return 6;
    #|  if (__builtin_classify_type(&x) != 5) return 7;
    #|  if (__builtin_classify_type(a) != 5) return 8;
    #|  if (__builtin_classify_type("x") != 5) return 9;
    #|  if (__builtin_classify_type(s) != 12) return 10;
    #|  if (__builtin_classify_type(u) != 13) return 11;
    #|  if (!__builtin_types_compatible_p(__typeof__(z), unsigned long)) return 12;
    #|  return y + (int)z;
    #|}
  source
}

///|
test "strict MIR codegen executes compile-time type fact lowering" {
  let source = strict_mir_compile_time_type_fact_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for compile-time type fact lowering" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_compile_time_type_fact_source(),
    "strict_mir_compile_time_type_fact_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_local_computed_goto_source() -> String {
  let source =
    #|int main(void) {
    #|  void *target = &&done;
    #|  goto *target;
    #|  return 1;
    #|done:
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes local computed goto" {
  let source = strict_mir_local_computed_goto_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for local computed goto" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_local_computed_goto_source(),
    "strict_mir_local_computed_goto_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_static_computed_goto_table_source() -> String {
  let source =
    #|int main(void) {
    #|  static void *labels[] = { &&bad, &&good };
    #|  goto *labels[1];
    #|bad:
    #|  return 1;
    #|good:
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes static computed goto table" {
  let source = strict_mir_static_computed_goto_table_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for static computed goto table" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_static_computed_goto_table_source(),
    "strict_mir_static_computed_goto_table_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_static_computed_goto_range_table_source() -> String {
  let source =
    #|int main(void) {
    #|  int op = 3;
    #|  static void * const dispatch_table[4] = {
    #|    &&case_zero,
    #|    &&case_one,
    #|    [2 ... 3] = &&case_two,
    #|  };
    #|  goto *dispatch_table[op];
    #|case_zero:
    #|  return 1;
    #|case_one:
    #|  return 2;
    #|case_two:
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes static computed goto range table" {
  let source = strict_mir_static_computed_goto_range_table_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for static computed goto range table" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_static_computed_goto_range_table_source(),
    "strict_mir_static_computed_goto_range_table_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_local_computed_goto_table_source() -> String {
  let source =
    #|int main(void) {
    #|  void *labels[] = { &&bad, &&good, &&also_bad };
    #|  int index = 0;
    #|  index = index + 1;
    #|  goto *labels[index];
    #|bad:
    #|  return 1;
    #|also_bad:
    #|  return 2;
    #|good:
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes local computed goto table" {
  assert_eq(
    run_source_strict_mir(strict_mir_local_computed_goto_table_source()),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for local computed goto table" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_local_computed_goto_table_source(),
    "strict_mir_local_computed_goto_table_differential",
  )
  assert_eq(result.code, 42)
}

///|
test "strict MIR codegen emits linux x64 local computed goto table" {
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("linux target did not parse")
  }
  let assembly = compile_strict_mir_for_target(
    strict_mir_local_computed_goto_table_source(),
    target,
  )
  inspect(assembly.contains("\tlea\trax, [rip + "), content="true")
  inspect(assembly.contains("\tjmp\trax"), content="true")
}

///|
test "strict MIR codegen rejects unsupported source builtins before backend calls" {
  let source =
    #|int main(void) {
    #|  return __builtin_mir_unsupported(0);
    #|}
  let target = @target.Target::default()
  let prog = @parser.parse_for_target(source, target)
  match @parser.validate_semantics(prog) {
    Ok(_) => ()
    Err(err) => abort("strict MIR semantic validation failed: " + err)
  }
  let mir_module = @mir.lower_to_module(prog, target)
  assert_eq(mir_module.bodies.contains("main"), false)
  match @mir_codegen.generate_assembly_from_mir_module_strict(mir_module) {
    Ok(_) => abort("expected unsupported builtin to fail strict MIR codegen")
    Err(err) => assert_eq(err, "missing MIR body for main")
  }
}

///|
fn strict_mir_clear_cache_source() -> String {
  let source =
    #|int main(void) {
    #|  int side = 0;
    #|  char buf[16];
    #|  __builtin___clear_cache(buf + (side += 2), buf + (side += 4));
    #|  __builtin_clear_cache(buf + (side += 8), buf + (side += 16));
    #|  return side + 12;
    #|}
  source
}

///|
test "strict MIR codegen executes clear-cache builtin" {
  let source = strict_mir_clear_cache_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for clear-cache builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_clear_cache_source(),
    "strict_mir_clear_cache_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_alignment_hint_builtin_source() -> String {
  let source =
    #|int main(void) {
    #|  int side = 0;
    #|  unsigned long value = 37ul;
    #|  char buf[64];
    #|  char *p = buf + 3;
    #|  if (__builtin_unpredictable(side += 1) != 1) return 1;
    #|  if (__builtin_expect(side += 2, side += 4) != 3) return 2;
    #|  if (side != 7) return 3;
    #|  if (__builtin_expect_with_probability(side += 5, side += 6, 0.25) != 12) return 4;
    #|  if (side != 18) return 5;
    #|  __builtin_assume(side == 18);
    #|  __builtin_prefetch(buf + (side += 1));
    #|  char *q = __builtin_assume_aligned(p + 5, 8, side += 3);
    #|  if (q != buf + 8) return 6;
    #|  if (__builtin_align_up(value, 8ul) != 40ul) return 7;
    #|  if (__builtin_align_down(value, 8ul) != 32ul) return 8;
    #|  if (!__builtin_is_aligned(40ul, 8ul)) return 9;
    #|  if (__builtin_is_aligned(value, 8ul)) return 10;
    #|  if (side != 22) return 11;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes alignment and hint builtins" {
  let source = strict_mir_alignment_hint_builtin_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for alignment and hint builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_alignment_hint_builtin_source(),
    "strict_mir_alignment_hint_builtin_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_alloca_source() -> String {
  let source =
    #|int main(void) {
    #|  int n = 5;
    #|  char *p = __builtin_alloca(n += 3);
    #|  p[0] = 40;
    #|  p[7] = 2;
    #|  char *q = __builtin_alloca_with_align(n += 4, 256);
    #|  q[0] = 20;
    #|  q[3] = 22;
    #|  if ((((unsigned long)q) & 31ul) != 0) return 1;
    #|  return q[0] + q[3] + (p[0] + p[7] == 42 ? 0 : 2) +
    #|    (n == 12 ? 0 : 4);
    #|}
  source
}

///|
test "strict MIR codegen executes alloca builtin" {
  let source = strict_mir_alloca_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for alloca builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_alloca_source(),
    "strict_mir_alloca_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_alloca_aggregate_memory_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern void *memset(void *, int, size_t);
    #|struct Pair {
    #|  int a;
    #|  double b;
    #|  char tag;
    #|};
    #|int main(void) {
    #|  struct Pair *p = __builtin_alloca(sizeof(struct Pair) * 3);
    #|  struct Pair *q = __builtin_alloca(sizeof(struct Pair));
    #|  memset(p, 0, sizeof(struct Pair) * 3);
    #|  memset(q, 0, sizeof(struct Pair));
    #|  if (p[0].a != 0 || (int)p[0].b != 0 || p[1].tag != 0) return 1;
    #|  p[0].a = 9;
    #|  p[0].b = 1.5;
    #|  p[0].tag = 4;
    #|  if (memcpy(q, p, sizeof(*q)) != q) return 2;
    #|  if (q->a != 9 || (int)(q->b * 2.0) != 3 || q->tag != 4) return 3;
    #|  p[1] = *q;
    #|  if (p[1].a != 9 || (int)(p[1].b * 2.0) != 3 || p[1].tag != 4) return 4;
    #|  p[2].a = p[0].a + p[1].a;
    #|  p[2].b = p[0].b + p[1].b;
    #|  p[2].tag = p[0].tag + p[1].tag;
    #|  if (p[2].a != 18) return 5;
    #|  if ((int)(p[2].b * 10.0) != 30) return 6;
    #|  if (p[2].tag != 8) return 7;
    #|  memset(q, 0, sizeof(*q));
    #|  if (q->a != 0 || (int)q->b != 0 || q->tag != 0) return 8;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes alloca aggregate memory" {
  assert_eq(
    run_source_strict_mir(strict_mir_alloca_aggregate_memory_source()),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for alloca aggregate memory" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_alloca_aggregate_memory_source(),
    "strict_mir_alloca_aggregate_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_alloca_aggregate_cross_call_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memset(void *, int, size_t);
    #|struct Pair {
    #|  int a;
    #|  double b;
    #|  char tag;
    #|};
    #|void fill_pair(struct Pair *p) {
    #|  p[0].a = 11;
    #|  p[0].b = 2.0;
    #|  p[0].tag = 5;
    #|  p[1] = p[0];
    #|}
    #|int observe_pair(struct Pair *p) {
    #|  if (p[0].a != 11 || (int)(p[0].b * 10.0) != 20 || p[0].tag != 5) return 1;
    #|  if (p[1].a != 11 || (int)(p[1].b * 10.0) != 20 || p[1].tag != 5) return 2;
    #|  return p[0].a + p[1].a + (int)(p[0].b * 5.0) + (int)(p[1].b * 5.0);
    #|}
    #|int main(void) {
    #|  struct Pair *p = __builtin_alloca(sizeof(struct Pair) * 2);
    #|  memset(p, 0, sizeof(struct Pair) * 2);
    #|  fill_pair(p);
    #|  return observe_pair(p);
    #|}
  source
}

///|
test "strict MIR codegen executes alloca aggregate cross-call memory" {
  assert_eq(
    run_source_strict_mir(strict_mir_alloca_aggregate_cross_call_source()),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for alloca aggregate cross-call memory" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_alloca_aggregate_cross_call_source(),
    "strict_mir_alloca_aggregate_cross_call_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_alloca_aggregate_indirect_call_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memset(void *, int, size_t);
    #|struct Pair {
    #|  int a;
    #|  double b;
    #|  char tag;
    #|};
    #|void fill_pair(struct Pair *p) {
    #|  p[0].a = 12;
    #|  p[0].b = 1.5;
    #|  p[0].tag = 6;
    #|  p[1] = p[0];
    #|}
    #|int observe_pair(struct Pair *p) {
    #|  if (p[0].a != 12 || (int)(p[0].b * 10.0) != 15 || p[0].tag != 6) return 1;
    #|  if (p[1].a != 12 || (int)(p[1].b * 10.0) != 15 || p[1].tag != 6) return 2;
    #|  return p[0].a + p[1].a + (int)(p[0].b * 6.0) + (int)(p[1].b * 6.0);
    #|}
    #|int main(void) {
    #|  void (*fill)(struct Pair *) = fill_pair;
    #|  int (*observe)(struct Pair *) = observe_pair;
    #|  struct Pair *p = __builtin_alloca(sizeof(struct Pair) * 2);
    #|  memset(p, 0, sizeof(struct Pair) * 2);
    #|  fill(p);
    #|  return observe(p);
    #|}
  source
}

///|
test "strict MIR codegen executes alloca aggregate indirect-call memory" {
  assert_eq(
    run_source_strict_mir(strict_mir_alloca_aggregate_indirect_call_source()),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for alloca aggregate indirect-call memory" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_alloca_aggregate_indirect_call_source(),
    "strict_mir_alloca_aggregate_indirect_call_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_alloca_aggregate_call_argument_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memset(void *, int, size_t);
    #|struct Pair {
    #|  int a;
    #|  double b;
    #|  char tag;
    #|};
    #|int score(struct Pair p) {
    #|  return p.a + (int)(p.b * 10.0) + p.tag;
    #|}
    #|int main(void) {
    #|  struct Pair *p = __builtin_alloca(sizeof(struct Pair));
    #|  memset(p, 0, sizeof(struct Pair));
    #|  p->a = 7;
    #|  p->b = 2.5;
    #|  p->tag = 10;
    #|  if ((int)(p->b * 10.0) != 25) return 100;
    #|  return score(*p);
    #|}
  source
}

///|
test "strict MIR codegen passes alloca aggregate call arguments" {
  assert_eq(
    run_source_strict_mir(strict_mir_alloca_aggregate_call_argument_source()),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for alloca aggregate call arguments" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_alloca_aggregate_call_argument_source(),
    "strict_mir_alloca_aggregate_call_argument_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_alloca_aggregate_variadic_argument_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|typedef __builtin_va_list va_list;
    #|extern void *memset(void *, int, size_t);
    #|struct Pair {
    #|  int a;
    #|  double b;
    #|  char tag;
    #|};
    #|int score(int seed, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, seed);
    #|  struct Pair p = __builtin_va_arg(ap, struct Pair);
    #|  __builtin_va_end(ap);
    #|  return seed + p.a + (int)(p.b * 10.0) + p.tag;
    #|}
    #|int main(void) {
    #|  struct Pair *p = __builtin_alloca(sizeof(struct Pair));
    #|  memset(p, 0, sizeof(struct Pair));
    #|  p->a = 5;
    #|  p->b = 2.0;
    #|  p->tag = 12;
    #|  if ((int)(p->b * 10.0) != 20) return 100;
    #|  return score(5, *p);
    #|}
  source
}

///|
test "strict MIR codegen passes alloca aggregate variadic arguments" {
  assert_eq(
    run_source_strict_mir(
      strict_mir_alloca_aggregate_variadic_argument_source(),
    ),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for alloca aggregate variadic arguments" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_alloca_aggregate_variadic_argument_source(),
    "strict_mir_alloca_aggregate_variadic_argument_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_alloca_aggregate_return_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memset(void *, int, size_t);
    #|struct Pair {
    #|  int a;
    #|  double b;
    #|  char tag;
    #|};
    #|struct Pair make_pair(void) {
    #|  struct Pair *p = __builtin_alloca(sizeof(struct Pair));
    #|  memset(p, 0, sizeof(struct Pair));
    #|  p->a = 8;
    #|  p->b = 2.5;
    #|  p->tag = 9;
    #|  return *p;
    #|}
    #|int main(void) {
    #|  struct Pair p = make_pair();
    #|  if ((int)(p.b * 10.0) != 25) return 100;
    #|  return p.a + (int)(p.b * 10.0) + p.tag;
    #|}
  source
}

///|
test "strict MIR codegen returns alloca aggregate values" {
  assert_eq(
    run_source_strict_mir(strict_mir_alloca_aggregate_return_source()),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for alloca aggregate returns" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_alloca_aggregate_return_source(),
    "strict_mir_alloca_aggregate_return_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_malloc_memory_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *malloc(size_t);
    #|extern void *calloc(size_t, size_t);
    #|extern void free(void *);
    #|int main(void) {
    #|  char *src = malloc(8);
    #|  char *dst = calloc(8, 1);
    #|  if (!src || !dst) return 1;
    #|  __builtin_memset(src, 'A', 4);
    #|  src[4] = 0;
    #|  if (__builtin_strlen(src) != 4) return 2;
    #|  __builtin_memcpy(dst, src, 5);
    #|  int result = dst[0] + dst[3] - 88;
    #|  free(src);
    #|  free(dst);
    #|  return result;
    #|}
  source
}

///|
test "strict MIR codegen executes malloc memory libcalls" {
  assert_eq(run_source_strict_mir(strict_mir_malloc_memory_source()), 42)
}

///|
async test "strict MIR codegen matches parser codegen for malloc memory libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_malloc_memory_source(),
    "strict_mir_malloc_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_realloc_memory_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *malloc(size_t);
    #|extern void *realloc(void *, size_t);
    #|extern void free(void *);
    #|int main(void) {
    #|  char *p = malloc(4);
    #|  if (!p) return 1;
    #|  p[0] = 'a';
    #|  p[1] = 'b';
    #|  p[2] = 0;
    #|  p = realloc(p, 8);
    #|  if (!p) return 2;
    #|  if (__builtin_strcmp(p, "ab") != 0) return 3;
    #|  p[2] = 'c';
    #|  p[3] = 0;
    #|  int result = __builtin_strlen(p) + p[0] - 58;
    #|  free(p);
    #|  return result;
    #|}
  source
}

///|
test "strict MIR codegen executes realloc memory preservation" {
  assert_eq(run_source_strict_mir(strict_mir_realloc_memory_source()), 42)
}

///|
async test "strict MIR codegen matches parser codegen for realloc memory preservation" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_realloc_memory_source(),
    "strict_mir_realloc_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_heap_aggregate_memory_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *malloc(size_t);
    #|extern void *calloc(size_t, size_t);
    #|extern void *realloc(void *, size_t);
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern void *memset(void *, int, size_t);
    #|extern void free(void *);
    #|struct Pair {
    #|  int a;
    #|  double b;
    #|  char tag;
    #|};
    #|int main(void) {
    #|  struct Pair *p = calloc(2, sizeof(struct Pair));
    #|  if (!p) return 1;
    #|  if (p[0].a != 0 || (int)p[0].b != 0 || p[1].tag != 0) return 2;
    #|  p[0].a = 7;
    #|  p[0].b = 2.5;
    #|  p[0].tag = 3;
    #|  struct Pair *q = malloc(sizeof(struct Pair));
    #|  if (!q) return 3;
    #|  if (memcpy(q, p, sizeof(*q)) != q) return 4;
    #|  if (q->a != 7 || (int)(q->b * 2.0) != 5 || q->tag != 3) return 5;
    #|  p = realloc(p, sizeof(struct Pair) * 3);
    #|  if (!p) return 6;
    #|  if (p[0].a != 7 || (int)(p[0].b * 2.0) != 5 || p[0].tag != 3) return 7;
    #|  p[1] = *q;
    #|  if (p[1].a != 7) return 8;
    #|  p[2].a = p[0].a + p[1].a;
    #|  p[2].b = p[0].b + p[1].b;
    #|  p[2].tag = p[0].tag + p[1].tag;
    #|  if (p[2].a != 14) return 9;
    #|  if ((int)(p[2].b * 10.0) != 50) return 10;
    #|  if (p[2].tag != 6) return 11;
    #|  memset(q, 0, sizeof(*q));
    #|  if (q->a != 0 || (int)q->b != 0 || q->tag != 0) return 12;
    #|  free(q);
    #|  free(p);
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes heap aggregate memory" {
  assert_eq(
    run_source_strict_mir(strict_mir_heap_aggregate_memory_source()),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for heap aggregate memory" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_heap_aggregate_memory_source(),
    "strict_mir_heap_aggregate_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_strdup_memory_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern char *strdup(const char *);
    #|extern char *strndup(const char *, size_t);
    #|extern void free(void *);
    #|int main(void) {
    #|  char *p = strdup("hi");
    #|  if (!p) return 1;
    #|  if (__builtin_strcmp(p, "hi") != 0) return 2;
    #|  p[1] = 'o';
    #|  if (__builtin_strcmp(p, "ho") != 0) return 3;
    #|  char *q = strndup("abcdef", 3);
    #|  if (!q) return 4;
    #|  if (__builtin_strcmp(q, "abc") != 0) return 5;
    #|  int result = __builtin_strlen(p) + __builtin_strlen(q) + p[1] + q[2] - 173;
    #|  free(p);
    #|  free(q);
    #|  return result;
    #|}
  source
}

///|
test "strict MIR codegen executes strdup heap memory" {
  assert_eq(run_source_strict_mir(strict_mir_strdup_memory_source()), 42)
}

///|
async test "strict MIR codegen matches parser codegen for strdup heap memory" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_strdup_memory_source(),
    "strict_mir_strdup_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_builtin_heap_memory_source() -> String {
  let source =
    #|int main(void) {
    #|  char *p = __builtin_malloc(4);
    #|  char *q = __builtin_calloc(4, 1);
    #|  if (!p || !q) return 1;
    #|  if (q[0] != 0 || q[3] != 0) return 2;
    #|  p[0] = 'a';
    #|  p[1] = 'b';
    #|  p[2] = 0;
    #|  q[0] = 'x';
    #|  q[1] = 0;
    #|  p = __builtin_realloc(p, 8);
    #|  if (!p) return 3;
    #|  if (__builtin_strcmp(p, "ab") != 0) return 4;
    #|  char *s = __builtin_strdup("hi");
    #|  char *t = __builtin_strndup("wxyz", 2);
    #|  if (!s || !t) return 5;
    #|  if (__builtin_strcmp(s, "hi") != 0) return 6;
    #|  if (__builtin_strcmp(t, "wx") != 0) return 7;
    #|  int result = __builtin_strlen(p) + __builtin_strlen(q) +
    #|    __builtin_strlen(s) + __builtin_strlen(t) + p[0] - 62;
    #|  __builtin_free(p);
    #|  __builtin_free(q);
    #|  __builtin_free(s);
    #|  __builtin_free(t);
    #|  return result;
    #|}
  source
}

///|
test "strict MIR codegen executes builtin heap libcalls" {
  assert_eq(run_source_strict_mir(strict_mir_builtin_heap_memory_source()), 42)
}

///|
async test "strict MIR codegen matches parser codegen for builtin heap libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_builtin_heap_memory_source(),
    "strict_mir_builtin_heap_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_posix_memalign_memory_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern int posix_memalign(char **, size_t, size_t);
    #|extern void free(void *);
    #|int main(void) {
    #|  char *p = 0;
    #|  int rc = posix_memalign(&p, 32, 8);
    #|  if (rc != 0) return rc;
    #|  if (!p) return 1;
    #|  if ((((unsigned long)p) & 31ul) != 0) return 2;
    #|  p[0] = 40;
    #|  p[7] = 2;
    #|  int result = p[0] + p[7];
    #|  free(p);
    #|  return result;
    #|}
  source
}

///|
test "strict MIR codegen executes posix_memalign heap memory" {
  assert_eq(
    run_source_strict_mir(strict_mir_posix_memalign_memory_source()),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for posix_memalign heap memory" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_posix_memalign_memory_source(),
    "strict_mir_posix_memalign_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aligned_alloc_memory_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *aligned_alloc(size_t, size_t);
    #|extern void free(void *);
    #|int main(void) {
    #|  char *p = aligned_alloc(32, 32);
    #|  if (!p) return 1;
    #|  if ((((unsigned long)p) & 31ul) != 0) return 2;
    #|  p[0] = 17;
    #|  p[31] = 25;
    #|  int result = p[0] + p[31];
    #|  free(p);
    #|  return result;
    #|}
  source
}

///|
test "strict MIR codegen executes aligned_alloc heap memory" {
  assert_eq(run_source_strict_mir(strict_mir_aligned_alloc_memory_source()), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aligned_alloc heap memory" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aligned_alloc_memory_source(),
    "strict_mir_aligned_alloc_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_valloc_malloc_size_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *valloc(size_t);
    #|extern size_t malloc_size(const void *);
    #|extern void free(void *);
    #|int main(void) {
    #|  char *p = valloc(32);
    #|  if (!p) return 1;
    #|  if ((((unsigned long)p) & 4095ul) != 0) return 2;
    #|  if (malloc_size(0) != 0) return 3;
    #|  if (malloc_size(p) < 32) return 4;
    #|  p[0] = 17;
    #|  p[31] = 25;
    #|  int result = p[0] + p[31];
    #|  free(p);
    #|  return result;
    #|}
  source
}

///|
test "strict MIR codegen executes valloc and malloc_size heap facts" {
  assert_eq(run_source_strict_mir(strict_mir_valloc_malloc_size_source()), 42)
}

///|
async test "strict MIR codegen matches parser codegen for valloc and malloc_size heap facts" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_valloc_malloc_size_source(),
    "strict_mir_valloc_malloc_size_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_frame_return_address_source() -> String {
  let source =
    #|int main(void) {
    #|  int level = 0;
    #|  void *fa = __builtin_frame_address(level);
    #|  void *ra = __builtin_return_address(level);
    #|  if (fa == 0) return 1;
    #|  if (ra == 0) return 2;
    #|  level = level + 1;
    #|  if (__builtin_frame_address(level) != 0) return 3;
    #|  if (__builtin_return_address(level) != 0) return 4;
    #|  if (__builtin_extract_return_addr(ra) != ra) return 5;
    #|  if (__builtin_frob_return_addr(ra) != ra) return 6;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes frame and return address builtins" {
  let source = strict_mir_frame_return_address_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for frame and return address builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_frame_return_address_source(),
    "strict_mir_frame_return_address_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_object_size_source() -> String {
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
    #|  if (__builtin_dynamic_object_size((const void *)"hello", 3) != 6) return 2;
    #|  if (__builtin_object_size((void *)1, 0) + 1 != 0) return 3;
    #|  if (__builtin_object_size((void *)1, 2) != 0) return 4;
    #|  if (__builtin_dynamic_object_size((void *)(long)(side += 1), side += 2) + 1 != 0) return 5;
    #|  if (side != 0) return 6;
    #|  if (__builtin_object_size(&x, 0) != sizeof(x)) return 7;
    #|  if (__builtin_dynamic_object_size((void *)buf, 2) != sizeof(buf)) return 8;
    #|  if (__builtin_object_size(&buf[3], 1) != sizeof(buf) - 3) return 9;
    #|  if (__builtin_object_size(buf + 3, 0) != sizeof(buf) - 3) return 10;
    #|  if (__builtin_object_size(&global_s.buf, 0) != sizeof(global_s) - __builtin_offsetof(struct S, buf)) return 11;
    #|  if (__builtin_dynamic_object_size(global_s.buf, 3) != sizeof(global_s.buf)) return 12;
    #|  if (__builtin_dynamic_object_size(&global_s.buf[4], 2) != sizeof(global_s) - __builtin_offsetof(struct S, buf) - 4) return 13;
    #|  if (__builtin_object_size(&local_s.buf, 0) != sizeof(local_s) - __builtin_offsetof(struct S, buf)) return 14;
    #|  if (__builtin_dynamic_object_size(local_s.buf, 3) != sizeof(local_s.buf)) return 15;
    #|  if (__builtin_dynamic_object_size((void *)global_buf, 2) != sizeof(global_buf)) return 16;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes object size builtins" {
  let source = strict_mir_object_size_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for object size builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_object_size_source(),
    "strict_mir_object_size_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_constant_query_source() -> String {
  let source =
    #|int main(void) {
    #|  int side = 0;
    #|  if (!__builtin_constant_p(1 + 2)) return 1;
    #|  if (__builtin_constant_p(side)) return 2;
    #|  if (__builtin_constant_p(side += 1)) return 3;
    #|  if (side != 0) return 4;
    #|  if (__builtin_constant_p(1 / 0)) return 5;
    #|  if (__builtin_flt_rounds() != 1) return 6;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes constant query builtins" {
  let source = strict_mir_constant_query_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for constant query builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_constant_query_source(),
    "strict_mir_constant_query_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_sync_atomic_fence_source() -> String {
  let source =
    #|int main(void) {
    #|  int x = 0;
    #|  __sync_synchronize();
    #|  __atomic_thread_fence((x += 1, 5));
    #|  __atomic_signal_fence((x += 1, 5));
    #|  __c11_atomic_thread_fence((x += 1, 5));
    #|  __c11_atomic_signal_fence((x += 1, 5));
    #|  return x == 4 ? 42 : x;
    #|}
  source
}

///|
test "strict MIR codegen executes sync and atomic fence builtins" {
  let source = strict_mir_sync_atomic_fence_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for sync and atomic fence builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_sync_atomic_fence_source(),
    "strict_mir_sync_atomic_fence_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_local_pointer_target_initializer_source() -> String {
  let source =
    #|typedef struct TokenString {
    #|  int *str;
    #|  int len;
    #|  int need_spc;
    #|  int allocated_len;
    #|  int last_line_num;
    #|  int save_line_num;
    #|  struct TokenString *prev;
    #|  const int *prev_ptr;
    #|  char alloc;
    #|} TokenString;
    #|
    #|unsigned long seen;
    #|
    #|void *remember(unsigned long n) {
    #|  seen = n;
    #|  return (void *)0;
    #|}
    #|
    #|int main(void) {
    #|  TokenString *str = remember(sizeof *str);
    #|  return seen == 56 ? 42 : (int)seen;
    #|}
  source
}

///|
test "strict MIR codegen sizes local pointer target in own initializer" {
  let source = strict_mir_local_pointer_target_initializer_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for local pointer target initializer" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_local_pointer_target_initializer_source(),
    "strict_mir_local_pointer_target_initializer_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_unsigned_int128_limb_multiply_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes unsigned int128 limb multiply" {
  let source = strict_mir_unsigned_int128_limb_multiply_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for unsigned int128 limb multiply" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_unsigned_int128_limb_multiply_source(),
    "strict_mir_unsigned_int128_limb_multiply_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_unsigned_int128_limb_divide_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes unsigned int128 limb divide" {
  let source = strict_mir_unsigned_int128_limb_divide_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for unsigned int128 limb divide" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_unsigned_int128_limb_divide_source(),
    "strict_mir_unsigned_int128_limb_divide_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_int128_direct_call_source() -> String {
  let source =
    #|typedef __int128 i128;
    #|typedef unsigned __int128 u128;
    #|static i128 make_i128(long hi, unsigned long lo) {
    #|  return ((i128)hi << 64) | lo;
    #|}
    #|static u128 make_u128(unsigned long hi, unsigned long lo) {
    #|  return ((u128)hi << 64) | lo;
    #|}
    #|static long split_i128(long tag, i128 v) {
    #|  return tag + (long)v + (long)(v >> 64);
    #|}
    #|static unsigned long split_u128(u128 v) {
    #|  return (unsigned long)v + (unsigned long)(v >> 64);
    #|}
    #|int main(void) {
    #|  i128 s = make_i128(5, 7);
    #|  u128 u = make_u128(11, 13);
    #|  return (int)(split_i128(30, s) + split_u128(u) - 24);
    #|}
  source
}

///|
test "strict MIR codegen executes int128 direct call ABI" {
  let source = strict_mir_int128_direct_call_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for int128 direct call ABI" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_int128_direct_call_source(),
    "strict_mir_int128_direct_call_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_stack_int128_direct_call_source() -> String {
  let source =
    #|typedef __int128 i128;
    #|static long split_stack(long a0, long a1, long a2, long a3, long a4,
    #|                        long a5, long a6, long a7, long a8, i128 v) {
    #|  return a8 + (long)v + (long)(v >> 64);
    #|}
    #|int main(void) {
    #|  i128 v = ((i128)5 << 64) | 7;
    #|  return (int)split_stack(0, 0, 0, 0, 0, 0, 0, 0, 30, v);
    #|}
  source
}

///|
test "strict MIR codegen executes stack-passed int128 direct calls" {
  let source = strict_mir_stack_int128_direct_call_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for stack-passed int128 direct calls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_stack_int128_direct_call_source(),
    "strict_mir_stack_int128_direct_call_differential",
  )
  assert_eq(result.code, 42)
}

///|
test "strict MIR codegen receives int128 parameters from clang callers" {
  let callee =
    #|typedef __int128 i128;
    #|long split_from_clang(i128 v) {
    #|  return (long)v + (long)(v >> 64);
    #|}
  let driver =
    #|typedef __int128 i128;
    #|long split_from_clang(i128 v);
    #|int main(void) {
    #|  i128 v = ((i128)5 << 64) | 7;
    #|  return (int)(split_from_clang(v) + 30);
    #|}
  assert_eq(run_strict_mir_with_clang_driver(callee, driver), 42)
}

///|
test "strict MIR codegen passes int128 parameters to clang callees" {
  let caller =
    #|typedef __int128 i128;
    #|long split_to_clang(i128 v);
    #|int main(void) {
    #|  i128 v = ((i128)5 << 64) | 7;
    #|  return (int)(split_to_clang(v) + 30);
    #|}
  let callee =
    #|typedef __int128 i128;
    #|long split_to_clang(i128 v) {
    #|  return (long)v + (long)(v >> 64);
    #|}
  assert_eq(run_strict_mir_with_clang_driver(caller, callee), 42)
}

///|
test "strict MIR codegen returns int128 values to clang callers" {
  let callee =
    #|typedef __int128 i128;
    #|i128 make_for_clang(long hi, unsigned long lo) {
    #|  return ((i128)hi << 64) | lo;
    #|}
  let driver =
    #|typedef __int128 i128;
    #|i128 make_for_clang(long hi, unsigned long lo);
    #|int main(void) {
    #|  i128 v = make_for_clang(5, 7);
    #|  return (int)((long)v + (long)(v >> 64) + 30);
    #|}
  assert_eq(run_strict_mir_with_clang_driver(callee, driver), 42)
}

///|
test "strict MIR codegen receives int128 return values from clang callees" {
  let caller =
    #|typedef __int128 i128;
    #|i128 make_from_clang(long hi, unsigned long lo);
    #|int main(void) {
    #|  i128 v = make_from_clang(5, 7);
    #|  return (int)((long)v + (long)(v >> 64) + 30);
    #|}
  let callee =
    #|typedef __int128 i128;
    #|i128 make_from_clang(long hi, unsigned long lo) {
    #|  return ((i128)hi << 64) | lo;
    #|}
  assert_eq(run_strict_mir_with_clang_driver(caller, callee), 42)
}

///|
fn strict_mir_implicit_external_scalar_call_arguments_source() -> String {
  let source =
    #|int main(void) {
    #|  if (strcmp("kimicc", "kimicc") != 0) return 1;
    #|  if (strcmp("abc", "abd") >= 0) return 2;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes implicit external scalar call arguments" {
  let source = strict_mir_implicit_external_scalar_call_arguments_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for implicit external scalar call arguments" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_implicit_external_scalar_call_arguments_source(),
    "strict_mir_implicit_external_scalar_call_arguments_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_bzero_source() -> String {
  let source =
    #|struct Pair {
    #|  int a;
    #|  int b;
    #|};
    #|struct Pair global_pair = { 19, 23 };
    #|int main(void) {
    #|  char buf[4];
    #|  struct Pair local = { 7, 35 };
    #|  struct Pair slots[2];
    #|  int n = 0;
    #|  buf[0] = 1;
    #|  buf[1] = 2;
    #|  buf[2] = 3;
    #|  buf[3] = 4;
    #|  slots[0].a = 5;
    #|  slots[0].b = 37;
    #|  __builtin_bzero(buf, n += 4);
    #|  __builtin_bzero(&local, sizeof(local));
    #|  __builtin_bzero(&global_pair, sizeof(global_pair));
    #|  __builtin_bzero(&slots[0], sizeof(slots[0]));
    #|  if (n != 4) return 1;
    #|  return 42 + buf[0] + buf[1] + buf[2] + buf[3] +
    #|    local.a + local.b + global_pair.a + global_pair.b +
    #|    slots[0].a + slots[0].b;
    #|}
  source
}

///|
test "strict MIR codegen executes bzero operation" {
  let source = strict_mir_bzero_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for bzero operation" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_bzero_source(),
    "strict_mir_bzero_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_darwin_fd_helpers_source() -> String {
  let source =
    #|struct fd_set {
    #|  int fds_bits[32];
    #|};
    #|
    #|int main(void) {
    #|  struct fd_set fds;
    #|  int side = 0;
    #|  __builtin_bzero(&fds, sizeof(fds));
    #|  __darwin_fd_set((side += 1, 9), &fds);
    #|  if (!__darwin_fd_isset((side += 2, 9), &fds)) return 1;
    #|  if (__darwin_fd_isset(8, &fds)) return 2;
    #|  __darwin_fd_set(40, &fds);
    #|  if (!__darwin_fd_isset(40, &fds)) return 3;
    #|  if (__darwin_fd_isset(41, &fds)) return 4;
    #|  __darwin_fd_clr((side += 4, 9), &fds);
    #|  if (__darwin_fd_isset(9, &fds)) return 5;
    #|  __darwin_fd_clr(40, &fds);
    #|  if (__darwin_fd_isset(40, &fds)) return 6;
    #|  return side == 7 ? 42 : side;
    #|}
  source
}

///|
test "strict MIR codegen executes darwin fd helpers" {
  let source = strict_mir_darwin_fd_helpers_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for darwin fd helpers" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_darwin_fd_helpers_source(),
    "strict_mir_darwin_fd_helpers_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_strlen_source() -> String {
  let source =
    #|int main(void) {
    #|  char s[4];
    #|  char *p = s;
    #|  int n = 0;
    #|  s[0] = 'a';
    #|  s[1] = 'b';
    #|  s[2] = 0;
    #|  s[3] = 'z';
    #|  if (__builtin_strlen((n += 1, p)) != 2) return 1;
    #|  if (n != 1) return 2;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes strlen libcall operation" {
  let source = strict_mir_strlen_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for strlen libcall operation" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_strlen_source(),
    "strict_mir_strlen_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_compare_libcalls_source() -> String {
  let source =
    #|int main(void) {
    #|  char a[4] = "ab";
    #|  char b[4] = "ac";
    #|  int n = 0;
    #|  if (__builtin_strcmp(a, b) >= 0) return 1;
    #|  if (__builtin_strcmp(b, a) <= 0) return 2;
    #|  if (__builtin_strncmp(a, b, n += 1) != 0) return 3;
    #|  if (__builtin_strncmp(a, b, n += 1) >= 0) return 4;
    #|  if (__builtin_memcmp(a, b, 1) != 0) return 5;
    #|  if (__builtin_memcmp(a, b, 2) >= 0) return 6;
    #|  if (n != 2) return 7;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes compare libcalls" {
  let source = strict_mir_compare_libcalls_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for compare libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_compare_libcalls_source(),
    "strict_mir_compare_libcalls_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_search_libcalls_source() -> String {
  let source =
    #|int main(void) {
    #|  char s[6] = "abca";
    #|  char hay[6] = "abcde";
    #|  char needle[3] = "cd";
    #|  int n = 0;
    #|  if (__builtin_strchr((n += 1, s), 'b') != s + 1) return 1;
    #|  if (__builtin_strchr(s, 'x') != 0) return 2;
    #|  if (__builtin_strchr(s, 0) != s + 4) return 3;
    #|  if (__builtin_strrchr(s, 'a') != s + 3) return 4;
    #|  if (__builtin_strrchr(s, 0) != s + 4) return 5;
    #|  if (__builtin_memchr(s, 'c', n += 3) != s + 2) return 6;
    #|  if (__builtin_memchr(s, 'a', 0) != 0) return 7;
    #|  if (__builtin_strstr(hay + 1, needle) != hay + 2) return 8;
    #|  if (__builtin_strstr(hay, needle + 1) != hay + 3) return 9;
    #|  if (__builtin_strstr(hay, "") != hay) return 10;
    #|  if (n != 4) return 11;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes search libcalls" {
  let source = strict_mir_search_libcalls_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for search libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_search_libcalls_source(),
    "strict_mir_search_libcalls_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_extended_builtin_libcalls_source() -> String {
  let source =
    #|int main(void) {
    #|  char text[10];
    #|  char reject[3];
    #|  char accept[3];
    #|  char raw[8];
    #|  char needle[3];
    #|  char dst[8];
    #|  int n = 0;
    #|  text[0] = 'a';
    #|  text[1] = 'b';
    #|  text[2] = 'c';
    #|  text[3] = '1';
    #|  text[4] = '2';
    #|  text[5] = '3';
    #|  text[6] = 'x';
    #|  text[7] = 'y';
    #|  text[8] = 'z';
    #|  text[9] = 0;
    #|  reject[0] = '2';
    #|  reject[1] = 'z';
    #|  reject[2] = 0;
    #|  accept[0] = 'x';
    #|  accept[1] = 'y';
    #|  accept[2] = 0;
    #|  raw[0] = 'a';
    #|  raw[1] = 0;
    #|  raw[2] = 'b';
    #|  raw[3] = 'c';
    #|  raw[4] = 0;
    #|  raw[5] = 'b';
    #|  raw[6] = 'c';
    #|  raw[7] = 0;
    #|  needle[0] = 0;
    #|  needle[1] = 'b';
    #|  needle[2] = 'c';
    #|  if (__builtin_strnlen(text, n += 10) != 9) return 1;
    #|  if (__builtin_strnlen(text, 4) != 4) return 2;
    #|  if (__builtin_strspn(text, "abc") != 3) return 3;
    #|  if (__builtin_strcspn(text, reject) != 4) return 4;
    #|  if (__builtin_strpbrk(text, accept) != text + 6) return 5;
    #|  if (__builtin_strpbrk(text, "q") != 0) return 6;
    #|  if (__builtin_bcmp(text, "abc123xyz", 9) != 0) return 7;
    #|  if (__builtin_bcmp(text, "abc123xyq", 9) == 0) return 8;
    #|  if (__builtin_memmem(raw, 8, needle, 3) != raw + 1) return 9;
    #|  if (__builtin_memmem(raw + 2, 4, "bc", 2) != raw + 2) return 10;
    #|  if (__builtin_memmem(raw, 2, "bc", 2) != 0) return 11;
    #|  if (__builtin_memmem(raw, 8, "bd", 2) != 0) return 12;
    #|  char *hit = (char *)__builtin_memccpy(dst, raw + 2, 0, 4);
    #|  if (hit != dst + 3) return 13;
    #|  if (dst[0] != 'b' || dst[1] != 'c' || dst[2] != 0) return 14;
    #|  if (__builtin_memccpy(dst, "xy", 'q', 2) != 0) return 15;
    #|  if (dst[0] != 'x' || dst[1] != 'y') return 16;
    #|  if (n != 10) return 17;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes extended builtin libcalls" {
  assert_eq(
    run_source_strict_mir(strict_mir_extended_builtin_libcalls_source()),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for extended builtin libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_extended_builtin_libcalls_source(),
    "strict_mir_extended_builtin_libcalls_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_checked_strl_source() -> String {
  let source =
    #|int main(void) {
    #|  char dst[8];
    #|  int n = 0;
    #|  if (__builtin___strlcpy_chk(dst, "abcd", 3, n += 8) != 4) return 1;
    #|  if (dst[0] != 'a' || dst[1] != 'b' || dst[2] != 0) return 2;
    #|  if (__builtin___strlcat_chk(dst, "xy", 0, n += 8) != 2) return 3;
    #|  if (n != 16) return 4;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes checked strl libcalls" {
  let source = strict_mir_checked_strl_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for checked strl libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_checked_strl_source(),
    "strict_mir_checked_strl_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_memory_libcalls_source() -> String {
  let source =
    #|int main(void) {
    #|  char src[4];
    #|  char dst[4];
    #|  int n = 0;
    #|  src[0] = 'a';
    #|  src[1] = 'b';
    #|  src[2] = 'c';
    #|  src[3] = 0;
    #|  if (__builtin_memcpy(dst, src, 4) != dst) return 1;
    #|  if (dst[0] != 'a' || dst[1] != 'b' || dst[2] != 'c' || dst[3] != 0) return 2;
    #|  if (__builtin_memset(dst + 1, 'x', 2) != dst + 1) return 3;
    #|  if (dst[0] != 'a' || dst[1] != 'x' || dst[2] != 'x' || dst[3] != 0) return 4;
    #|  if (__builtin_memmove(dst + 1, dst, 3) != dst + 1) return 5;
    #|  if (dst[0] != 'a' || dst[1] != 'a' || dst[2] != 'x' || dst[3] != 'x') return 6;
    #|  if (__builtin___memcpy_chk(dst, src, 1, n += 10) != dst) return 7;
    #|  if (__builtin___memmove_chk(dst + 1, dst, 1, n += 4) != dst + 1) return 8;
    #|  if (__builtin___memset_chk(dst + 2, 'z', 1, n += 2) != dst + 2) return 9;
    #|  if (n != 16) return 10;
    #|  if (dst[0] != 'a' || dst[1] != 'a' || dst[2] != 'z') return 11;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes memory libcalls" {
  let source = strict_mir_memory_libcalls_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for memory libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_memory_libcalls_source(),
    "strict_mir_memory_libcalls_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_declared_memory_string_libcalls_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern void *memmove(void *, const void *, size_t);
    #|extern void *memset(void *, int, size_t);
    #|extern int memcmp(const void *, const void *, size_t);
    #|extern size_t strlen(const char *);
    #|extern int strcmp(const char *, const char *);
    #|extern char *strcpy(char *, const char *);
    #|extern char *strcat(char *, const char *);
    #|extern char *strchr(const char *, int);
    #|extern char *strstr(const char *, const char *);
    #|int main(void) {
    #|  char src[8];
    #|  char dst[16];
    #|  if (strcpy(src, "abc") != src) return 1;
    #|  if (strlen(src) != 3) return 2;
    #|  if (memcpy(dst, src, 4) != dst) return 3;
    #|  if (strcmp(dst, "abc") != 0) return 4;
    #|  if (memset(dst + 1, 'x', 2) != dst + 1) return 5;
    #|  if (memcmp(dst, "axx", 3) != 0) return 6;
    #|  strcpy(src, "wxyz");
    #|  memmove(src + 1, src, 3);
    #|  if (strcmp(src, "wwxy") != 0) return 7;
    #|  strcpy(dst, "hi");
    #|  if (strcat(dst, "!") != dst) return 8;
    #|  if (strchr(dst, '!') != dst + 2) return 9;
    #|  if (strstr(dst, "i!") != dst + 1) return 10;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes declared memory and string libcalls" {
  assert_eq(
    run_source_strict_mir(strict_mir_declared_memory_string_libcalls_source()),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for declared memory and string libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_declared_memory_string_libcalls_source(),
    "strict_mir_declared_memory_string_libcalls_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_declared_bsd_memory_libcalls_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void bzero(void *, size_t);
    #|extern void bcopy(const void *, void *, size_t);
    #|extern int bcmp(const void *, const void *, size_t);
    #|extern int strcmp(const char *, const char *);
    #|int main(void) {
    #|  char src[8];
    #|  char dst[8];
    #|  src[0] = 'a';
    #|  src[1] = 'b';
    #|  src[2] = 'c';
    #|  src[3] = 0;
    #|  bzero(dst, 8);
    #|  if (dst[0] != 0 || dst[7] != 0) return 1;
    #|  bcopy(src, dst, 4);
    #|  if (strcmp(dst, "abc") != 0) return 2;
    #|  if (bcmp(src, dst, 4) != 0) return 3;
    #|  dst[1] = 'x';
    #|  if (bcmp(src, dst, 3) == 0) return 4;
    #|  bcopy(dst, dst + 1, 3);
    #|  if (dst[0] != 'a' || dst[1] != 'a' || dst[2] != 'x' || dst[3] != 'c') return 5;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes declared BSD memory libcalls" {
  assert_eq(
    run_source_strict_mir(strict_mir_declared_bsd_memory_libcalls_source()),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for declared BSD memory libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_declared_bsd_memory_libcalls_source(),
    "strict_mir_declared_bsd_memory_libcalls_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_strnlen_memccpy_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern size_t strnlen(const char *, size_t);
    #|extern void *memccpy(void *, const void *, int, size_t);
    #|extern int strcmp(const char *, const char *);
    #|int main(void) {
    #|  char src[8];
    #|  char dst[8];
    #|  src[0] = 'a';
    #|  src[1] = 'b';
    #|  src[2] = 'c';
    #|  src[3] = 0;
    #|  src[4] = 'd';
    #|  if (strnlen(src, 8) != 3) return 1;
    #|  if (strnlen(src, 2) != 2) return 2;
    #|  char *hit = memccpy(dst, src, 'c', 8);
    #|  if (hit != dst + 3) return 3;
    #|  dst[3] = 0;
    #|  if (strcmp(dst, "abc") != 0) return 4;
    #|  src[0] = 'x';
    #|  src[1] = 'y';
    #|  src[2] = 'z';
    #|  src[3] = 0;
    #|  if (memccpy(dst, src, 'q', 4) != 0) return 5;
    #|  if (strcmp(dst, "xyz") != 0) return 6;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes declared strnlen and memccpy" {
  assert_eq(run_source_strict_mir(strict_mir_strnlen_memccpy_source()), 42)
}

///|
async test "strict MIR codegen matches parser codegen for declared strnlen and memccpy" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_strnlen_memccpy_source(),
    "strict_mir_strnlen_memccpy_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_memmem_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern char *memmem(const void *, size_t, const void *, size_t);
    #|int main(void) {
    #|  char hay[8];
    #|  char needle[3];
    #|  hay[0] = 'a';
    #|  hay[1] = 0;
    #|  hay[2] = 'b';
    #|  hay[3] = 'c';
    #|  hay[4] = 0;
    #|  hay[5] = 'b';
    #|  hay[6] = 'c';
    #|  hay[7] = 0;
    #|  needle[0] = 0;
    #|  needle[1] = 'b';
    #|  needle[2] = 'c';
    #|  if (memmem(hay, 8, needle, 3) != hay + 1) return 1;
    #|  if (memmem(hay + 2, 4, "bc", 2) != hay + 2) return 2;
    #|  if (memmem(hay, 2, "bc", 2) != 0) return 3;
    #|  if (memmem(hay, 8, hay + 7, 0) != 0) return 4;
    #|  if (memmem(hay, 8, "bd", 2) != 0) return 5;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes declared memmem" {
  assert_eq(run_source_strict_mir(strict_mir_memmem_source()), 42)
}

///|
async test "strict MIR codegen matches parser codegen for declared memmem" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_memmem_source(),
    "strict_mir_memmem_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_string_span_libcalls_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern size_t strspn(const char *, const char *);
    #|extern size_t strcspn(const char *, const char *);
    #|extern char *strpbrk(const char *, const char *);
    #|int main(void) {
    #|  char s[10];
    #|  char reject[3];
    #|  char accept[3];
    #|  s[0] = 'a';
    #|  s[1] = 'b';
    #|  s[2] = 'c';
    #|  s[3] = '1';
    #|  s[4] = '2';
    #|  s[5] = '3';
    #|  s[6] = 'x';
    #|  s[7] = 'y';
    #|  s[8] = 'z';
    #|  s[9] = 0;
    #|  reject[0] = '2';
    #|  reject[1] = 'z';
    #|  reject[2] = 0;
    #|  accept[0] = 'x';
    #|  accept[1] = 'y';
    #|  accept[2] = 0;
    #|  if (strspn(s, "abc") != 3) return 1;
    #|  if (strspn(s, "") != 0) return 2;
    #|  if (strspn(s + 3, "12345") != 3) return 3;
    #|  if (strcspn(s, reject) != 4) return 4;
    #|  if (strcspn(s, "") != 9) return 5;
    #|  if (strpbrk(s, accept) != s + 6) return 6;
    #|  if (strpbrk(s, "31") != s + 3) return 7;
    #|  if (strpbrk(s, "") != 0) return 8;
    #|  if (strpbrk(s, "q") != 0) return 9;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes declared string span libcalls" {
  assert_eq(run_source_strict_mir(strict_mir_string_span_libcalls_source()), 42)
}

///|
async test "strict MIR codegen matches parser codegen for declared string span libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_string_span_libcalls_source(),
    "strict_mir_string_span_libcalls_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_case_bsd_string_libcalls_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern int strcasecmp(const char *, const char *);
    #|extern int strncasecmp(const char *, const char *, size_t);
    #|extern char *strcasestr(const char *, const char *);
    #|extern char *index(const char *, int);
    #|extern char *rindex(const char *, int);
    #|int main(void) {
    #|  char s[7];
    #|  s[0] = 'A';
    #|  s[1] = 'b';
    #|  s[2] = 'C';
    #|  s[3] = 'a';
    #|  s[4] = 'B';
    #|  s[5] = 'c';
    #|  s[6] = 0;
    #|  if (strcasecmp("AbC", "aBc") != 0) return 1;
    #|  if (strcasecmp("abc", "abd") >= 0) return 2;
    #|  if (strcasecmp("abe", "abd") <= 0) return 3;
    #|  if (strncasecmp("AbD", "aBc", 2) != 0) return 4;
    #|  if (strncasecmp("AbD", "aBc", 3) <= 0) return 5;
    #|  if (strncasecmp(s, "zz", 0) != 0) return 6;
    #|  if (strcasestr(s, "ca") != s + 2) return 7;
    #|  if (strcasestr(s, "BC") != s + 1) return 8;
    #|  if (strcasestr(s, "") != s) return 9;
    #|  if (strcasestr(s, "qq") != 0) return 10;
    #|  if (index(s, 'B') != s + 4) return 11;
    #|  if (rindex(s, 'a') != s + 3) return 12;
    #|  if (rindex(s, 'A') != s) return 13;
    #|  if (index(s, 'z') != 0) return 14;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes declared case-insensitive and BSD string libcalls" {
  assert_eq(
    run_source_strict_mir(strict_mir_case_bsd_string_libcalls_source()),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for declared case-insensitive and BSD string libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_case_bsd_string_libcalls_source(),
    "strict_mir_case_bsd_string_libcalls_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_strsep_source() -> String {
  let source =
    #|extern char *strsep(char **, const char *);
    #|extern int strcmp(const char *, const char *);
    #|int main(void) {
    #|  char text[8];
    #|  text[0] = 'a';
    #|  text[1] = 'b';
    #|  text[2] = ',';
    #|  text[3] = 'c';
    #|  text[4] = 'd';
    #|  text[5] = ',';
    #|  text[6] = 0;
    #|  text[7] = 'z';
    #|  char *p = text;
    #|  char *first = strsep(&p, ",");
    #|  if (first != text) return 1;
    #|  if (p != text + 3) return 2;
    #|  if (text[2] != 0) return 3;
    #|  if (strcmp(first, "ab") != 0) return 4;
    #|  char *second = strsep(&p, ",");
    #|  if (second != text + 3) return 5;
    #|  if (p != text + 6) return 6;
    #|  if (text[5] != 0) return 7;
    #|  if (strcmp(second, "cd") != 0) return 8;
    #|  char *third = strsep(&p, ",");
    #|  if (third != text + 6) return 9;
    #|  if (p != 0) return 10;
    #|  if (strcmp(third, "") != 0) return 11;
    #|  if (strsep(&p, ",") != 0) return 12;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes declared strsep" {
  assert_eq(run_source_strict_mir(strict_mir_strsep_source()), 42)
}

///|
async test "strict MIR codegen matches parser codegen for declared strsep" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_strsep_source(),
    "strict_mir_strsep_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_strtok_source() -> String {
  let source =
    #|extern char *strtok(char *, const char *);
    #|extern int strcmp(const char *, const char *);
    #|int main(void) {
    #|  char text[12];
    #|  text[0] = ',';
    #|  text[1] = 'a';
    #|  text[2] = 'b';
    #|  text[3] = ',';
    #|  text[4] = ';';
    #|  text[5] = 'c';
    #|  text[6] = 'd';
    #|  text[7] = ';';
    #|  text[8] = 0;
    #|  text[9] = 'x';
    #|  char other[4];
    #|  other[0] = 'z';
    #|  other[1] = ':';
    #|  other[2] = 'q';
    #|  other[3] = 0;
    #|  char *first = strtok(text, ",;");
    #|  if (first != text + 1) return 1;
    #|  if (strcmp(first, "ab") != 0) return 2;
    #|  if (text[3] != 0) return 3;
    #|  char *second = strtok(0, ",;");
    #|  if (second != text + 5) return 4;
    #|  if (strcmp(second, "cd") != 0) return 5;
    #|  if (text[7] != 0) return 6;
    #|  if (strtok(0, ",;") != 0) return 7;
    #|  char *reset = strtok(other, ":");
    #|  if (reset != other) return 8;
    #|  if (strcmp(reset, "z") != 0) return 9;
    #|  if (other[1] != 0) return 10;
    #|  char *tail = strtok(0, ":");
    #|  if (tail != other + 2) return 11;
    #|  if (strcmp(tail, "q") != 0) return 12;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes declared strtok" {
  assert_eq(run_source_strict_mir(strict_mir_strtok_source()), 42)
}

///|
async test "strict MIR codegen matches parser codegen for declared strtok" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_strtok_source(),
    "strict_mir_strtok_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_decimal_integer_conversion_source() -> String {
  let source =
    #|extern long strtol(const char *, char **, int);
    #|extern long long strtoll(const char *, char **, int);
    #|extern unsigned long strtoul(const char *, char **, int);
    #|extern unsigned long long strtoull(const char *, char **, int);
    #|extern int atoi(const char *);
    #|extern long atol(const char *);
    #|extern long long atoll(const char *);
    #|int main(void) {
    #|  char *end;
    #|  char nodigits[4];
    #|  nodigits[0] = 'x';
    #|  nodigits[1] = '7';
    #|  nodigits[2] = 0;
    #|  nodigits[3] = 'z';
    #|  if (strtol("  -42xyz", &end, 10) != -42L) return 1;
    #|  if (*end != 'x') return 2;
    #|  if (strtoll("+17", &end, 10) != 17LL) return 3;
    #|  if (*end != 0) return 4;
    #|  if (strtoul("42x", &end, 10) != 42UL) return 5;
    #|  if (*end != 'x') return 6;
    #|  if (strtoull("9", 0, 10) != 9ULL) return 7;
    #|  if (strtol(nodigits, &end, 10) != 0L) return 8;
    #|  if (end != nodigits) return 9;
    #|  if (atoi(" -12q") != -12) return 10;
    #|  if (atol("33q") != 33L) return 11;
    #|  if (atoll("-44q") != -44LL) return 12;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes declared decimal integer conversion libcalls" {
  assert_eq(
    run_source_strict_mir(strict_mir_decimal_integer_conversion_source()),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for declared decimal integer conversion libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_decimal_integer_conversion_source(),
    "strict_mir_decimal_integer_conversion_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_integer_conversion_bases_source() -> String {
  let source =
    #|extern long strtol(const char *, char **, int);
    #|extern unsigned long strtoul(const char *, char **, int);
    #|int main(void) {
    #|  char *end;
    #|  if (strtol("0x2a!", &end, 0) != 42L) return 1;
    #|  if (*end != '!') return 2;
    #|  if (strtol("052!", &end, 0) != 42L) return 3;
    #|  if (*end != '!') return 4;
    #|  if (strtol("2A!", &end, 16) != 42L) return 5;
    #|  if (*end != '!') return 6;
    #|  if (strtoul("101010!", &end, 2) != 42UL) return 7;
    #|  if (*end != '!') return 8;
    #|  if (strtol("z!", &end, 36) != 35L) return 9;
    #|  if (*end != '!') return 10;
    #|  if (strtol("19!", &end, 8) != 1L) return 11;
    #|  if (*end != '9') return 12;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes declared integer conversion bases" {
  assert_eq(
    run_source_strict_mir(strict_mir_integer_conversion_bases_source()),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for declared integer conversion bases" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_integer_conversion_bases_source(),
    "strict_mir_integer_conversion_bases_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_scalar_object_memory_source() -> String {
  let source =
    #|static unsigned int g = 0x89abcdefu;
    #|int main(void) {
    #|  unsigned int x = 0x12345678u;
    #|  unsigned int y = 0u;
    #|  unsigned int z = 0xffffffffu;
    #|  if (__builtin_memcpy(&y, &x, sizeof(y)) != &y) return 1;
    #|  if (y != x) return 2;
    #|  if (__builtin_memset(&z, 0, sizeof(z)) != &z) return 3;
    #|  if (z != 0u) return 4;
    #|  __builtin_memset(&z, 0x2a, 1);
    #|  if (z != 42u) return 5;
    #|  __builtin_memmove(&z, &g, sizeof(z));
    #|  if (z != g) return 6;
    #|  __builtin_memset(&g, 0, sizeof(g));
    #|  if (g != 0u) return 7;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes scalar object memory libcalls" {
  let source = strict_mir_scalar_object_memory_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for scalar object memory libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_scalar_object_memory_source(),
    "strict_mir_scalar_object_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_double_object_memory_source() -> String {
  let source =
    #|static double gd = 9.5;
    #|int main(void) {
    #|  double x = 1.25;
    #|  double y = 0.0;
    #|  double z = -4.5;
    #|  if (__builtin_memcpy(&y, &x, sizeof(y)) != &y) return 1;
    #|  if ((int)(y * 4.0) != 5) return 2;
    #|  __builtin_memmove(&z, &gd, sizeof(z));
    #|  if ((int)(z * 2.0) != 19) return 3;
    #|  __builtin_memset(&z, 0, sizeof(z));
    #|  if ((int)z != 0) return 4;
    #|  __builtin_memcpy(&gd, &x, sizeof(gd));
    #|  if ((int)(gd * 4.0) != 5) return 5;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes double object memory libcalls" {
  let source = strict_mir_double_object_memory_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for double object memory libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_double_object_memory_source(),
    "strict_mir_double_object_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_float_object_memory_source() -> String {
  let source =
    #|static float gf = 1.5f;
    #|int main(void) {
    #|  float x = 1.0f;
    #|  unsigned char *p = (unsigned char *)&x;
    #|  if (p[0] != 0u || p[1] != 0u || p[2] != 0x80u || p[3] != 0x3fu) return 1;
    #|  p[0] = 0u;
    #|  p[1] = 0u;
    #|  p[2] = 0u;
    #|  p[3] = 0x40u;
    #|  if ((int)x != 2) return 2;
    #|  unsigned char raw[4];
    #|  raw[0] = 0u;
    #|  raw[1] = 0u;
    #|  raw[2] = 0x40u;
    #|  raw[3] = 0x40u;
    #|  if ((int)*(float *)raw != 3) return 3;
    #|  float y = 0.0f;
    #|  __builtin_memcpy(&y, &gf, sizeof(y));
    #|  if ((int)y != 1) return 4;
    #|  __builtin_memset(&gf, 0, sizeof(gf));
    #|  if ((int)gf != 0) return 5;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes float object memory bytes" {
  let source = strict_mir_float_object_memory_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for float object memory bytes" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_float_object_memory_source(),
    "strict_mir_float_object_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_scalar_aggregate_field_memory_source() -> String {
  let source =
    #|struct S {
    #|  unsigned int head;
    #|  unsigned int values[2];
    #|};
    #|static struct S g = { 0x12345678u, { 0x01020304u, 0x89abcdefu } };
    #|int main(void) {
    #|  struct S s;
    #|  s.head = 0x55667788u;
    #|  s.values[0] = 0u;
    #|  s.values[1] = 0u;
    #|  unsigned int copy = 0u;
    #|  if (__builtin_memcpy(&copy, &s.head, sizeof(copy)) != &copy) return 1;
    #|  if (copy != 0x55667788u) return 2;
    #|  __builtin_memcpy(&s.values[1], &g.values[1], sizeof(copy));
    #|  if (s.values[1] != 0x89abcdefu) return 3;
    #|  __builtin_memset(&s.head, 0, sizeof(s.head));
    #|  if (s.head != 0u) return 4;
    #|  __builtin_memset(&g.values[0], 0, sizeof(g.values[0]));
    #|  if (g.values[0] != 0u) return 5;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes scalar aggregate field memory libcalls" {
  let source = strict_mir_scalar_aggregate_field_memory_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for scalar aggregate field memory libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_scalar_aggregate_field_memory_source(),
    "strict_mir_scalar_aggregate_field_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_direct_scalar_byte_memory_source() -> String {
  let source =
    #|struct S {
    #|  unsigned int head;
    #|  unsigned int tail;
    #|};
    #|static unsigned int g = 0x01020304u;
    #|int main(void) {
    #|  unsigned int x = 0x12345678u;
    #|  unsigned char *p = (unsigned char *)&x;
    #|  if (p[0] != 0x78u) return 1;
    #|  if (p[1] != 0x56u) return 2;
    #|  p[1] = 0xaau;
    #|  if (x != 0x1234aa78u) return 3;
    #|  unsigned char raw[4];
    #|  raw[0] = 0xefu;
    #|  raw[1] = 0xbeu;
    #|  raw[2] = 0xadu;
    #|  raw[3] = 0xdeu;
    #|  if (*(unsigned int *)raw != 0xdeadbeefu) return 4;
    #|  struct S s;
    #|  s.head = 0u;
    #|  s.tail = 0u;
    #|  *(unsigned int *)(((unsigned char *)&s) + sizeof(unsigned int)) = g;
    #|  if (s.tail != 0x01020304u) return 5;
    #|  unsigned char *q = (unsigned char *)&g;
    #|  q[0] = 0x2au;
    #|  if (g != 0x0102032au) return 6;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes direct scalar byte memory access" {
  let source = strict_mir_direct_scalar_byte_memory_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for direct scalar byte memory access" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_direct_scalar_byte_memory_source(),
    "strict_mir_direct_scalar_byte_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_string_destination_libcalls_source() -> String {
  let source =
    #|int main(void) {
    #|  char dst[16];
    #|  int n = 0;
    #|  if (__builtin_strcpy(dst, "ab") != dst) return 1;
    #|  if (dst[0] != 'a' || dst[1] != 'b' || dst[2] != 0) return 2;
    #|  if (__builtin___strcpy_chk(dst, "cd", n += 16) != dst) return 3;
    #|  if (dst[0] != 'c' || dst[1] != 'd' || dst[2] != 0) return 4;
    #|  if (__builtin_strcat(dst, "e") != dst) return 5;
    #|  if (dst[0] != 'c' || dst[1] != 'd' || dst[2] != 'e' || dst[3] != 0) return 6;
    #|  if (__builtin___strcat_chk(dst, "f", n += 16) != dst) return 7;
    #|  if (dst[0] != 'c' || dst[1] != 'd' || dst[2] != 'e' || dst[3] != 'f') return 8;
    #|  if (__builtin_strncpy(dst, "xy", 3) != dst) return 9;
    #|  if (dst[0] != 'x' || dst[1] != 'y' || dst[2] != 0) return 10;
    #|  dst[0] = 0;
    #|  if (__builtin___strncpy_chk(dst, "pq", 2, n += 16) != dst) return 11;
    #|  if (dst[0] != 'p' || dst[1] != 'q') return 12;
    #|  dst[2] = 0;
    #|  if (__builtin_strncat(dst, "rs", 1) != dst) return 13;
    #|  if (dst[0] != 'p' || dst[1] != 'q' || dst[2] != 'r' || dst[3] != 0) return 14;
    #|  if (__builtin___strncat_chk(dst, "tu", 1, n += 16) != dst) return 15;
    #|  if (dst[0] != 'p' || dst[1] != 'q' || dst[2] != 'r' || dst[3] != 't') return 16;
    #|  if (n != 64) return 17;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes string destination libcalls" {
  let source = strict_mir_string_destination_libcalls_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for string destination libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_string_destination_libcalls_source(),
    "strict_mir_string_destination_libcalls_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_end_pointer_memory_string_builtins_source() -> String {
  let source =
    #|void *mempcpy(void *dst, const void *src, unsigned long n) {
    #|  char *d = (char *)dst;
    #|  const char *s = (const char *)src;
    #|  for (unsigned long i = 0; i < n; i = i + 1) d[i] = s[i];
    #|  return d + n;
    #|}
    #|char *stpcpy(char *dst, const char *src) {
    #|  char *d = dst;
    #|  while (*src) {
    #|    *d = *src;
    #|    d = d + 1;
    #|    src = src + 1;
    #|  }
    #|  *d = 0;
    #|  return d;
    #|}
    #|char *stpncpy(char *dst, const char *src, unsigned long n) {
    #|  char *d = dst;
    #|  while (n && *src) {
    #|    *d = *src;
    #|    d = d + 1;
    #|    src = src + 1;
    #|    n = n - 1;
    #|  }
    #|  char *ret = d;
    #|  while (n) {
    #|    *d = 0;
    #|    d = d + 1;
    #|    n = n - 1;
    #|  }
    #|  return ret;
    #|}
    #|int main(void) {
    #|  char copy[16];
    #|  int n = 0;
    #|  if (__builtin_mempcpy(copy, "uv", 2) != copy + 2) return 1;
    #|  if (copy[0] != 'u' || copy[1] != 'v') return 2;
    #|  if (__builtin___mempcpy_chk(copy + 2, "wx", 2, n += 14) != copy + 4) return 3;
    #|  if (copy[2] != 'w' || copy[3] != 'x') return 4;
    #|  if (n != 14) return 5;
    #|  if (__builtin_stpcpy(copy, "hi") != copy + 2) return 6;
    #|  if (copy[0] != 'h' || copy[1] != 'i' || copy[2] != 0) return 7;
    #|  if (__builtin___stpcpy_chk(copy, "ok", n += 16) != copy + 2) return 8;
    #|  if (copy[0] != 'o' || copy[1] != 'k' || copy[2] != 0) return 9;
    #|  if (__builtin_stpncpy(copy, "abcd", 2) != copy + 2) return 10;
    #|  if (copy[0] != 'a' || copy[1] != 'b') return 11;
    #|  if (__builtin___stpncpy_chk(copy, "cd", 5, n += 16) != copy + 2) return 12;
    #|  if (copy[0] != 'c' || copy[1] != 'd' || copy[2] != 0) return 13;
    #|  if (n != 46) return 14;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes end-pointer memory string builtins" {
  let source = strict_mir_end_pointer_memory_string_builtins_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for end-pointer memory string builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_end_pointer_memory_string_builtins_source(),
    "strict_mir_end_pointer_memory_string_builtins_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_stack_integer_direct_call_source() -> String {
  let source =
    #|int sum9(int a, int b, int c, int d, int e, int f, int g, int h, int i) {
    #|  return a + b + c + d + e + f + g + h + i;
    #|}
    #|int main(void) {
    #|  return sum9(1, 2, 3, 4, 5, 6, 7, 8, 9);
    #|}
  source
}

///|
test "strict MIR codegen executes stack-passed integer direct calls" {
  let source = strict_mir_stack_integer_direct_call_source()
  assert_eq(run_source_strict_mir(source), 45)
}

///|
async test "strict MIR codegen matches parser codegen for stack-passed integer direct calls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_stack_integer_direct_call_source(),
    "strict_mir_stack_integer_direct_call_differential",
  )
  assert_eq(result.code, 45)
}

///|
fn strict_mir_stack_integer_indirect_call_source() -> String {
  let source =
    #|int sum9(int a, int b, int c, int d, int e, int f, int g, int h, int i) {
    #|  return a + b + c + d + e + f + g + h + i;
    #|}
    #|int main(void) {
    #|  int (*fp)(int, int, int, int, int, int, int, int, int) = sum9;
    #|  return fp(1, 2, 3, 4, 5, 6, 7, 8, 9);
    #|}
  source
}

///|
test "strict MIR codegen executes stack-passed integer indirect calls" {
  let source = strict_mir_stack_integer_indirect_call_source()
  assert_eq(run_source_strict_mir(source), 45)
}

///|
async test "strict MIR codegen matches parser codegen for stack-passed integer indirect calls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_stack_integer_indirect_call_source(),
    "strict_mir_stack_integer_indirect_call_differential",
  )
  assert_eq(result.code, 45)
}

///|
fn strict_mir_indirect_variadic_function_pointer_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes indirect variadic function pointer calls" {
  let source = strict_mir_indirect_variadic_function_pointer_source()
  assert_eq(run_source_strict_mir(source), 17)
}

///|
async test "strict MIR codegen matches parser codegen for indirect variadic function pointer calls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_indirect_variadic_function_pointer_source(),
    "strict_mir_indirect_variadic_function_pointer_differential",
  )
  assert_eq(result.code, 17)
}

///|
fn strict_mir_aggregate_member_address_function_table_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes aggregate member address function table" {
  let source = strict_mir_aggregate_member_address_function_table_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate member address function table" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_member_address_function_table_source(),
    "strict_mir_aggregate_member_address_function_table_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_local_aggregate_member_address_function_table_source() -> String {
  let source =
    #|struct Methods { int (*init)(void); };
    #|struct Config { struct Methods methods; };
    #|int good(void) { return 42; }
    #|int main(void) {
    #|  struct Config cfg;
    #|  struct Methods *to = &cfg.methods;
    #|  to->init = good;
    #|  return cfg.methods.init();
    #|}
  source
}

///|
test "strict MIR codegen executes local aggregate member address function table" {
  let source = strict_mir_local_aggregate_member_address_function_table_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for local aggregate member address function table" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_local_aggregate_member_address_function_table_source(),
    "strict_mir_local_aggregate_member_address_function_table_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aggregate_array_element_address_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes aggregate array element address" {
  let source = strict_mir_aggregate_array_element_address_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate array element address" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_array_element_address_source(),
    "strict_mir_aggregate_array_element_address_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_pointer_post_update_through_memory_source() -> String {
  let source =
    #|int main(void) {
    #|  int values[3] = {4, 7, 9};
    #|  int *p = values;
    #|  int **pp = &p;
    #|  int first = *((*pp)++);
    #|  return first + **pp;
    #|}
  source
}

///|
test "strict MIR codegen executes pointer post update through memory" {
  let source = strict_mir_pointer_post_update_through_memory_source()
  assert_eq(run_source_strict_mir(source), 11)
}

///|
async test "strict MIR codegen matches parser codegen for pointer post update through memory" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_pointer_post_update_through_memory_source(),
    "strict_mir_pointer_post_update_through_memory_differential",
  )
  assert_eq(result.code, 11)
}

///|
fn strict_mir_small_aggregate_call_result_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes small aggregate call results" {
  let source = strict_mir_small_aggregate_call_result_source()
  assert_eq(run_source_strict_mir(source), 72)
}

///|
async test "strict MIR codegen matches parser codegen for small aggregate call results" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_small_aggregate_call_result_source(),
    "strict_mir_small_aggregate_call_result_differential",
  )
  assert_eq(result.code, 72)
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
test "strict MIR codegen receives small aggregates from clang callees" {
  let caller =
    #|struct Pair { long a; long b; };
    #|struct Pair make_pair(long a, long b);
    #|struct Pair forward_pair(long a, long b);
    #|int main(void) {
    #|  struct Pair p = make_pair(10, 20);
    #|  struct Pair q = forward_pair(3, 4);
    #|  return (int)(p.a + p.b + q.a + q.b);
    #|}
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
  assert_eq(run_strict_mir_with_clang_driver(caller, callee), 40)
}

///|
fn strict_mir_hfa_aggregate_call_result_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes HFA aggregate call results" {
  let source = strict_mir_hfa_aggregate_call_result_source()
  assert_eq(run_source_strict_mir(source), 48)
}

///|
async test "strict MIR codegen matches parser codegen for HFA aggregate call results" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_hfa_aggregate_call_result_source(),
    "strict_mir_hfa_aggregate_call_result_differential",
  )
  assert_eq(result.code, 48)
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
test "strict MIR codegen receives HFA aggregates from clang callees" {
  let caller =
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
  assert_eq(run_strict_mir_with_clang_driver(caller, callee), 51)
}

///|
fn strict_mir_register_aggregate_parameter_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes register aggregate parameters" {
  let source = strict_mir_register_aggregate_parameter_source()
  assert_eq(run_source_strict_mir(source), 83)
}

///|
async test "strict MIR codegen matches parser codegen for register aggregate parameters" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_register_aggregate_parameter_source(),
    "strict_mir_register_aggregate_parameter_differential",
  )
  assert_eq(result.code, 83)
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
fn strict_mir_stack_aggregate_parameter_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes stack aggregate parameters" {
  let source = strict_mir_stack_aggregate_parameter_source()
  assert_eq(run_source_strict_mir(source), 226)
}

///|
async test "strict MIR codegen matches parser codegen for stack aggregate parameters" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_stack_aggregate_parameter_source(),
    "strict_mir_stack_aggregate_parameter_differential",
  )
  assert_eq(result.code, 226)
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
fn strict_mir_indirect_register_aggregate_parameter_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes indirect register aggregate parameters" {
  let source = strict_mir_indirect_register_aggregate_parameter_source()
  assert_eq(run_source_strict_mir(source), 83)
}

///|
async test "strict MIR codegen matches parser codegen for indirect register aggregate parameters" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_indirect_register_aggregate_parameter_source(),
    "strict_mir_indirect_register_aggregate_parameter_differential",
  )
  assert_eq(result.code, 83)
}

///|
test "strict MIR codegen passes indirect register aggregate parameters to clang callees" {
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
fn strict_mir_indirect_stack_aggregate_parameter_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes indirect stack aggregate parameters" {
  let source = strict_mir_indirect_stack_aggregate_parameter_source()
  assert_eq(run_source_strict_mir(source), 226)
}

///|
async test "strict MIR codegen matches parser codegen for indirect stack aggregate parameters" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_indirect_stack_aggregate_parameter_source(),
    "strict_mir_indirect_stack_aggregate_parameter_differential",
  )
  assert_eq(result.code, 226)
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
test "strict MIR codegen receives indirect stack aggregate parameters from clang callers" {
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
    #|int run_indirect(struct Pair p, struct Tiny t, struct H h, struct Hthree hthree) {
    #|  long (*fp_pair)(long, long, long, long, long, long, long, struct Pair, long) = sum_pair_stack;
    #|  int (*fp_tiny)(long, long, long, long, long, long, long, long, struct Tiny, long) = sum_tiny_stack;
    #|  int (*fp_h)(double, double, double, double, double, double, double, struct H, double) = sum_h_stack;
    #|  int (*fp_hthree)(double, double, double, double, double, double, struct Hthree, double) = sum_h3_stack;
    #|  return (int)fp_pair(1, 2, 3, 4, 5, 6, 7, p, 9) + fp_tiny(1, 2, 3, 4, 5, 6, 7, 8, t, 9) + fp_h(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, h, 9.0) + fp_hthree(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, hthree, 5.0);
    #|}
  let driver =
    #|struct Pair { long a; long b; };
    #|struct Tiny { char a; short b; };
    #|struct H { double a[2]; };
    #|struct Hthree { double a[3]; };
    #|int run_indirect(struct Pair p, struct Tiny t, struct H h, struct Hthree hthree);
    #|int main(void) {
    #|  struct Pair p = {10, 20};
    #|  struct Tiny t = {5, 30};
    #|  struct H h = {{3.0, 4.0}};
    #|  struct Hthree hthree = {{2.0, 3.0, 4.0}};
    #|  return run_indirect(p, t, h, hthree);
    #|}
  assert_eq(run_strict_mir_with_clang_driver(callee, driver), 226)
}

///|
fn strict_mir_large_aggregate_parameter_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes large aggregate parameters" {
  let source = strict_mir_large_aggregate_parameter_source()
  assert_eq(run_source_strict_mir(source), 118)
}

///|
async test "strict MIR codegen matches parser codegen for large aggregate parameters" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_large_aggregate_parameter_source(),
    "strict_mir_large_aggregate_parameter_differential",
  )
  assert_eq(result.code, 118)
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
fn strict_mir_memory_aggregate_call_result_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes memory aggregate call results" {
  let source = strict_mir_memory_aggregate_call_result_source()
  assert_eq(run_source_strict_mir(source), 72)
}

///|
async test "strict MIR codegen matches parser codegen for memory aggregate call results" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_memory_aggregate_call_result_source(),
    "strict_mir_memory_aggregate_call_result_differential",
  )
  assert_eq(result.code, 72)
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
test "strict MIR codegen receives memory aggregates from clang callees" {
  let caller =
    #|struct Big { long a; long b; long c; };
    #|struct Big make_big(long a, long b, long c);
    #|struct Big forward_big(long a, long b, long c);
    #|int main(void) {
    #|  struct Big p = make_big(10, 20, 30);
    #|  struct Big q = forward_big(3, 4, 5);
    #|  return (int)(p.a + p.b + p.c + q.a + q.b + q.c);
    #|}
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
  assert_eq(run_strict_mir_with_clang_driver(caller, callee), 78)
}

///|
fn strict_mir_aggregate_object_address_source() -> String {
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
  source
}

///|
test "strict MIR codegen takes address of aggregate objects" {
  let source = strict_mir_aggregate_object_address_source()
  assert_eq(run_source_strict_mir(source), 11)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate object addresses" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_object_address_source(),
    "strict_mir_aggregate_object_address_differential",
  )
  assert_eq(result.code, 11)
}

///|
fn strict_mir_aggregate_pointer_member_source() -> String {
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
  source
}

///|
test "strict MIR codegen accesses aggregate pointer members" {
  let source = strict_mir_aggregate_pointer_member_source()
  assert_eq(run_source_strict_mir(source), 9)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate pointer members" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_pointer_member_source(),
    "strict_mir_aggregate_pointer_member_differential",
  )
  assert_eq(result.code, 9)
}

///|
fn strict_mir_globals_arrays_and_structs_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes globals arrays and structs" {
  let source = strict_mir_globals_arrays_and_structs_source()
  assert_eq(run_source_strict_mir(source), 16)
}

///|
async test "strict MIR codegen matches parser codegen for globals arrays and structs" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_globals_arrays_and_structs_source(),
    "strict_mir_globals_arrays_and_structs_differential",
  )
  assert_eq(result.code, 16)
}

///|
fn strict_mir_static_nested_array_access_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes static nested array access" {
  let source = strict_mir_static_nested_array_access_source()
  assert_eq(run_source_strict_mir(source), 6)
}

///|
async test "strict MIR codegen matches parser codegen for static nested array access" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_static_nested_array_access_source(),
    "strict_mir_static_nested_array_access_differential",
  )
  assert_eq(result.code, 6)
}

///|
fn strict_mir_array_element_aggregate_field_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes array element aggregate fields" {
  let source = strict_mir_array_element_aggregate_field_source()
  assert_eq(run_source_strict_mir(source), 7)
}

///|
async test "strict MIR codegen matches parser codegen for array element aggregate fields" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_array_element_aggregate_field_source(),
    "strict_mir_array_element_aggregate_field_differential",
  )
  assert_eq(result.code, 7)
}

///|
fn strict_mir_bitfield_load_store_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes bitfield loads and stores" {
  let source = strict_mir_bitfield_load_store_source()
  assert_eq(run_source_strict_mir(source), 45)
}

///|
async test "strict MIR codegen matches parser codegen for bitfield loads and stores" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_bitfield_load_store_source(),
    "strict_mir_bitfield_load_store_differential",
  )
  assert_eq(result.code, 45)
}

///|
fn strict_mir_signed_bitfield_source() -> String {
  let source =
    #|struct Bits { unsigned a : 3; signed b : 4; unsigned c : 5; };
    #|static struct Bits bits = { .a = 5, .b = -3, .c = 17 };
    #|int main(void) {
    #|  struct Bits local;
    #|  local.a = 3;
    #|  local.b = -2;
    #|  local.c = 24;
    #|  return bits.a + bits.b + bits.c + local.a + local.b + local.c;
    #|}
  source
}

///|
test "strict MIR codegen sign extends signed bitfield loads" {
  let source = strict_mir_signed_bitfield_source()
  assert_eq(run_source_strict_mir(source), 44)
}

///|
async test "strict MIR codegen matches parser codegen for signed bitfield loads" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_signed_bitfield_source(),
    "strict_mir_signed_bitfield_differential",
  )
  assert_eq(result.code, 44)
}

///|
fn strict_mir_switch_case_nested_if_source() -> String {
  let source =
    #|int main(void) {
    #|  int x = 2;
    #|  int total = 0;
    #|  switch (x) {
    #|    if (x > 0) {
    #|    case 1:
    #|      total = 10;
    #|      break;
    #|    case 2:
    #|      total = 20;
    #|    }
    #|    total = total + 22;
    #|  }
    #|  return total;
    #|}
  source
}

///|
test "strict MIR codegen executes switch case labels nested in if" {
  let source = strict_mir_switch_case_nested_if_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for switch case labels nested in if" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_switch_case_nested_if_source(),
    "strict_mir_switch_case_nested_if_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_switch_case_nested_loop_source() -> String {
  let source =
    #|int main(void) {
    #|  int x = 2;
    #|  int total = 0;
    #|  switch (x) {
    #|    while (x > 0) {
    #|    case 1:
    #|      total = total + 10;
    #|      x = 0;
    #|      break;
    #|    case 2:
    #|      total = total + 20;
    #|      x = x - 1;
    #|    }
    #|    total = total + 3;
    #|  }
    #|  return total;
    #|}
  source
}

///|
test "strict MIR codegen executes switch case labels nested in loops" {
  let source = strict_mir_switch_case_nested_loop_source()
  assert_eq(run_source_strict_mir(source), 33)
}

///|
async test "strict MIR codegen matches parser codegen for switch case labels nested in loops" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_switch_case_nested_loop_source(),
    "strict_mir_switch_case_nested_loop_differential",
  )
  assert_eq(result.code, 33)
}

///|
fn strict_mir_switch_case_skips_for_init_source() -> String {
  let source =
    #|int main(void) {
    #|  int x = 2;
    #|  int total = 0;
    #|  switch (x) {
    #|    for (total = 100; x > 0; x = x - 1) {
    #|    case 1:
    #|      total = total + 10;
    #|      break;
    #|    case 2:
    #|      total = total + 20;
    #|    }
    #|    total = total + 3;
    #|  }
    #|  return total;
    #|}
  source
}

///|
test "strict MIR codegen skips for init when switch enters loop case" {
  let source = strict_mir_switch_case_skips_for_init_source()
  assert_eq(run_source_strict_mir(source), 33)
}

///|
async test "strict MIR codegen matches parser codegen when switch enters for-loop case" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_switch_case_skips_for_init_source(),
    "strict_mir_switch_case_skips_for_init_differential",
  )
  assert_eq(result.code, 33)
}

///|
fn strict_mir_switch_case_nested_do_while_source() -> String {
  let source =
    #|int main(void) {
    #|  int x = 2;
    #|  int total = 0;
    #|  switch (x) {
    #|    do {
    #|    case 1:
    #|      total = total + 10;
    #|      break;
    #|    case 2:
    #|      total = total + 20;
    #|      x = x - 1;
    #|    } while (x > 0);
    #|    total = total + 3;
    #|  }
    #|  return total;
    #|}
  source
}

///|
test "strict MIR codegen executes switch case labels nested in do while" {
  let source = strict_mir_switch_case_nested_do_while_source()
  assert_eq(run_source_strict_mir(source), 33)
}

///|
async test "strict MIR codegen matches parser codegen for switch case labels nested in do while" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_switch_case_nested_do_while_source(),
    "strict_mir_switch_case_nested_do_while_differential",
  )
  assert_eq(result.code, 33)
}

///|
fn strict_mir_struct_copy_with_bitfields_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes struct copies with bitfields" {
  let source = strict_mir_struct_copy_with_bitfields_source()
  assert_eq(run_source_strict_mir(source), 35)
}

///|
async test "strict MIR codegen matches parser codegen for struct copies with bitfields" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_struct_copy_with_bitfields_source(),
    "strict_mir_struct_copy_with_bitfields_differential",
  )
  assert_eq(result.code, 35)
}

///|
fn strict_mir_pointer_arithmetic_local_array_source() -> String {
  let source =
    #|int main(void) {
    #|  int a[3];
    #|  int *p = a;
    #|  int *q;
    #|  q = a;
    #|  q[1] = 8;
    #|  return *(p + 1);
    #|}
  source
}

///|
test "strict MIR codegen executes pointer arithmetic on local arrays" {
  let source = strict_mir_pointer_arithmetic_local_array_source()
  assert_eq(run_source_strict_mir(source), 8)
}

///|
async test "strict MIR codegen matches parser codegen for pointer arithmetic on local arrays" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_pointer_arithmetic_local_array_source(),
    "strict_mir_pointer_arithmetic_local_array_differential",
  )
  assert_eq(result.code, 8)
}

///|
fn strict_mir_casted_object_pointer_byte_offsets_source() -> String {
  let source =
    #|struct S { unsigned char a; unsigned char b; };
    #|int main(void) {
    #|  struct S s;
    #|  s.a = 0;
    #|  s.b = 0;
    #|  *(((unsigned char *)&s) + __builtin_offsetof(struct S, b)) = 42;
    #|  return s.b;
    #|}
  source
}

///|
test "strict MIR codegen executes casted object pointer byte offsets" {
  let source = strict_mir_casted_object_pointer_byte_offsets_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for casted object pointer byte offsets" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_casted_object_pointer_byte_offsets_source(),
    "strict_mir_casted_object_pointer_byte_offsets_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_memory_compound_lhs_source() -> String {
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
  source
}

///|
test "strict MIR codegen preserves memory compound update lhs across rhs" {
  let source = strict_mir_memory_compound_lhs_source()
  assert_eq(run_source_strict_mir(source), 5)
}

///|
async test "strict MIR codegen matches parser codegen for memory compound update lhs across rhs" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_memory_compound_lhs_source(),
    "strict_mir_memory_compound_lhs_differential",
  )
  assert_eq(result.code, 5)
}

///|
fn strict_mir_pointer_memory_update_lhs_source() -> String {
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
  source
}

///|
test "strict MIR codegen preserves pointer memory update lhs across rhs" {
  let source = strict_mir_pointer_memory_update_lhs_source()
  assert_eq(run_source_strict_mir(source), 17)
}

///|
async test "strict MIR codegen matches parser codegen for pointer memory update lhs across rhs" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_pointer_memory_update_lhs_source(),
    "strict_mir_pointer_memory_update_lhs_differential",
  )
  assert_eq(result.code, 17)
}

///|
async test "strict MIR codegen matches parser codegen for stack object pointer calls" {
  let source =
    #|extern int printf(const char *, ...);
    #|struct Pair { int x; int y; };
    #|void fill_array(int *p) {
    #|  p[0] = 12;
    #|  p[1] = 30;
    #|}
    #|int sum_array(int *p) {
    #|  return p[0] + p[1];
    #|}
    #|void fill_chars(char *p) {
    #|  __builtin_strcpy(p, "ok");
    #|}
    #|int check_chars(char *p) {
    #|  return __builtin_strlen(p) == 2 && p[0] == 'o' && p[1] == 'k' ? 42 : 1;
    #|}
    #|void fill_pair(struct Pair *p) {
    #|  p->x = 19;
    #|  p->y = 23;
    #|}
    #|int sum_pair(struct Pair *p) {
    #|  return p->x + p->y;
    #|}
    #|int main(void) {
    #|  int values[2];
    #|  char *buf = __builtin_alloca(4);
    #|  struct Pair pair;
    #|  fill_array(values);
    #|  fill_chars(buf);
    #|  fill_pair(&pair);
    #|  int a = sum_array(values);
    #|  int b = check_chars(buf);
    #|  int c = sum_pair(&pair);
    #|  printf("%d|%s|%d\n", a, buf, c);
    #|  return (a + b + c) & 255;
    #|}
  let result = run_source_strict_mir_against_parser_codegen(
    source, "strict_mir_stack_object_pointer_differential",
  )
  assert_true(result.output.contains("42|ok|42"))
}

///|
async test "strict MIR codegen matches parser codegen for indirect stack object pointer calls" {
  let source =
    #|extern int printf(const char *, ...);
    #|struct Pair { int x; int y; };
    #|void write_ints(int *p) {
    #|  p[0] = 20;
    #|  p[1] = 22;
    #|}
    #|int read_ints(int *p) {
    #|  return p[0] + p[1];
    #|}
    #|void write_bytes(char *p) {
    #|  p[0] = 'h';
    #|  p[1] = 'i';
    #|  p[2] = 0;
    #|}
    #|int read_bytes(char *p) {
    #|  return p[0] + p[1] == 209 ? 42 : 1;
    #|}
    #|void write_pair(struct Pair *p) {
    #|  p->x = 31;
    #|  p->y = 11;
    #|}
    #|int read_pair(struct Pair *p) {
    #|  return p->x + p->y;
    #|}
    #|int main(void) {
    #|  void (*wi)(int *) = write_ints;
    #|  int (*ri)(int *) = read_ints;
    #|  void (*wb)(char *) = write_bytes;
    #|  int (*rb)(char *) = read_bytes;
    #|  void (*wp)(struct Pair *) = write_pair;
    #|  int (*rp)(struct Pair *) = read_pair;
    #|  int values[2];
    #|  char *buf = __builtin_alloca(3);
    #|  struct Pair pair;
    #|  wi(values);
    #|  wb(buf);
    #|  wp(&pair);
    #|  int a = ri(values);
    #|  int b = rb(buf);
    #|  int c = rp(&pair);
    #|  printf("%d|%s|%d\n", a, buf, c);
    #|  return (a + b + c) & 255;
    #|}
  let result = run_source_strict_mir_against_parser_codegen(
    source, "strict_mir_indirect_stack_object_pointer_differential",
  )
  assert_true(result.output.contains("42|hi|42"))
}

///|
fn strict_mir_direct_array_decay_pointer_arithmetic_source() -> String {
  let source =
    #|int main(void) {
    #|  int a[3];
    #|  a[0] = 3;
    #|  a[1] = 6;
    #|  return *(a + 1);
    #|}
  source
}

///|
test "strict MIR codegen executes direct array decay in pointer arithmetic" {
  let source = strict_mir_direct_array_decay_pointer_arithmetic_source()
  assert_eq(run_source_strict_mir(source), 6)
}

///|
async test "strict MIR codegen matches parser codegen for direct array decay in pointer arithmetic" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_direct_array_decay_pointer_arithmetic_source(),
    "strict_mir_direct_array_decay_pointer_arithmetic_differential",
  )
  assert_eq(result.code, 6)
}

///|
fn strict_mir_ternary_local_array_decay_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes ternary local array decay before indexing" {
  let source = strict_mir_ternary_local_array_decay_source()
  assert_eq(run_source_strict_mir(source), 12)
}

///|
async test "strict MIR codegen matches parser codegen for ternary local array decay before indexing" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_ternary_local_array_decay_source(),
    "strict_mir_ternary_local_array_decay_differential",
  )
  assert_eq(result.code, 12)
}

///|
fn strict_mir_member_array_decay_pointer_difference_source() -> String {
  let source =
    #|struct S { int a[4]; unsigned char iPrev; };
    #|int main(void) {
    #|  struct S s;
    #|  int *p = &s.a[2];
    #|  s.iPrev = (unsigned char)(p - s.a);
    #|  return s.iPrev;
    #|}
  source
}

///|
test "strict MIR codegen executes member array decay in pointer differences" {
  let source = strict_mir_member_array_decay_pointer_difference_source()
  assert_eq(run_source_strict_mir(source), 2)
}

///|
async test "strict MIR codegen matches parser codegen for member array decay in pointer differences" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_member_array_decay_pointer_difference_source(),
    "strict_mir_member_array_decay_pointer_difference_differential",
  )
  assert_eq(result.code, 2)
}

///|
fn strict_mir_member_array_decay_pointer_comparison_source() -> String {
  let source =
    #|struct S { int *p; int a[2]; };
    #|int main(void) {
    #|  struct S s;
    #|  s.p = s.a;
    #|  return s.p == s.a;
    #|}
  source
}

///|
test "strict MIR codegen executes member array decay in pointer comparisons" {
  let source = strict_mir_member_array_decay_pointer_comparison_source()
  assert_eq(run_source_strict_mir(source), 1)
}

///|
async test "strict MIR codegen matches parser codegen for member array decay in pointer comparisons" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_member_array_decay_pointer_comparison_source(),
    "strict_mir_member_array_decay_pointer_comparison_differential",
  )
  assert_eq(result.code, 1)
}

///|
fn strict_mir_local_aggregate_array_initializer_source() -> String {
  let source =
    #|struct Item { const char *z; int a; int b; };
    #|int main(void) {
    #|  struct Item items[] = {
    #|    { "x", 1, 2 },
    #|    { "y", 3, 4 },
    #|  };
    #|  return items[1].a + items[0].b + (items[0].z == items[1].z);
    #|}
  source
}

///|
test "strict MIR codegen executes local aggregate array initializers" {
  let source = strict_mir_local_aggregate_array_initializer_source()
  assert_eq(run_source_strict_mir(source), 5)
}

///|
async test "strict MIR codegen matches parser codegen for local aggregate array initializers" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_local_aggregate_array_initializer_source(),
    "strict_mir_local_aggregate_array_initializer_differential",
  )
  assert_eq(result.code, 5)
}

///|
fn strict_mir_local_array_range_initializer_source() -> String {
  let source =
    #|struct Item { int a; int b; };
    #|int main(void) {
    #|  int nums[5] = { [0 ... 2] = 4, [4] = 5 };
    #|  struct Item items[4] = {
    #|    [0 ... 1] = { 3, 4 },
    #|    [3] = { 7, 8 },
    #|  };
    #|  int *p = (int[]){ [0 ... 1] = 5, [2] = 4 };
    #|  return nums[0] + nums[2] + nums[3] + nums[4] +
    #|    items[0].a + items[1].b + items[2].a + items[3].b +
    #|    p[0] + p[1] + p[2];
    #|}
  source
}

///|
test "strict MIR codegen executes local array range initializers" {
  let source = strict_mir_local_array_range_initializer_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for local array range initializers" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_local_array_range_initializer_source(),
    "strict_mir_local_array_range_initializer_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_nested_local_compound_literal_designators_source() -> String {
  let source =
    #|struct Inner { int z; int q; };
    #|struct S { int tag; struct Inner inner; int a[3]; };
    #|struct Pair { int a; int b; };
    #|int main(void) {
    #|  struct S s = (struct S){
    #|    .inner.z = 20,
    #|    .inner.q = 2,
    #|    .a[2] = 5,
    #|    .tag = 1,
    #|    .a[0] = 4
    #|  };
    #|  struct Pair *pairs = (struct Pair[]){
    #|    [1].b = 1,
    #|    [0].a = 4,
    #|    [1].a = 5
    #|  };
    #|  return s.tag + s.inner.z + s.inner.q + s.a[0] + s.a[1] + s.a[2] +
    #|    pairs[0].a + pairs[0].b + pairs[1].a + pairs[1].b;
    #|}
  source
}

///|
test "strict MIR codegen executes nested local compound literal designators" {
  let source = strict_mir_nested_local_compound_literal_designators_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for nested local compound literal designators" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_nested_local_compound_literal_designators_source(),
    "strict_mir_nested_local_compound_literal_designators_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_local_scalar_brace_initializer_source() -> String {
  let source =
    #|struct S { int a; int b; };
    #|int main(void) {
    #|  int x = {19}, y = {{23}};
    #|  int arr[2] = {{5}, {37}};
    #|  struct S s = {{11}, {31}};
    #|  return x + y == 42 && arr[0] + arr[1] == 42 && s.a + s.b == 42
    #|       ? 42 : 1;
    #|}
  source
}

///|
test "strict MIR codegen executes local scalar brace initializers" {
  let source = strict_mir_local_scalar_brace_initializer_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for local scalar brace initializers" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_local_scalar_brace_initializer_source(),
    "strict_mir_local_scalar_brace_initializer_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_global_aggregate_copy_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes global aggregate copies" {
  let source = strict_mir_global_aggregate_copy_source()
  assert_eq(run_source_strict_mir(source), 0)
}

///|
async test "strict MIR codegen matches parser codegen for global aggregate copies" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_global_aggregate_copy_source(),
    "strict_mir_global_aggregate_copy_differential",
  )
  assert_eq(result.code, 0)
}

///|
async test "strict MIR codegen matches parser codegen for initialized global aggregate memory" {
  let source =
    #|extern int printf(const char *, ...);
    #|struct Pair { int a; int b; };
    #|struct Outer { int head; struct Pair pairs[2]; int tail; };
    #|static struct Outer g = {
    #|  .head = 5,
    #|  .pairs = { [1] = { .a = 17, .b = 19 } },
    #|  .tail = 1
    #|};
    #|int main(void) {
    #|  struct Pair copy = g.pairs[1];
    #|  printf("%d:%d:%d:%d\n", g.head, copy.a, copy.b, g.tail);
    #|  return g.head + copy.a + copy.b + g.tail;
    #|}
  let result = run_source_strict_mir_against_parser_codegen(
    source, "strict_mir_initialized_global_aggregate_memory_differential",
  )
  assert_true(result.output.contains("5:17:19:1"))
}

///|
fn strict_mir_aggregate_array_field_copy_source() -> String {
  let source =
    #|struct Item { int x; int y; };
    #|struct Db { struct Item items[2]; int tail; };
    #|int main(void) {
    #|  struct Db src;
    #|  src.items[0].x = 10;
    #|  src.items[0].y = 1;
    #|  src.items[1].x = 2;
    #|  src.items[1].y = 29;
    #|  src.tail = 3;
    #|  struct Db copy = src;
    #|  src.items[1].y = 0;
    #|  return copy.items[0].x + copy.items[1].y + copy.tail;
    #|}
  source
}

///|
test "strict MIR codegen copies aggregate array fields" {
  let source = strict_mir_aggregate_array_field_copy_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate array field copies" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_array_field_copy_source(),
    "strict_mir_aggregate_array_field_copy_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_va_arg_pointer_aggregate_copy_source() -> String {
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
  source
}

///|
test "strict MIR codegen copies aggregate into global member from va_arg pointer" {
  let source = strict_mir_va_arg_pointer_aggregate_copy_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for va_arg pointer aggregate copies" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_va_arg_pointer_aggregate_copy_source(),
    "strict_mir_va_arg_pointer_aggregate_copy_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_global_aggregate_float_array_initializer_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes global aggregate float array initializers" {
  let source = strict_mir_global_aggregate_float_array_initializer_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
fn strict_mir_exact_width_global_string_aggregate_source() -> String {
  let source =
    #|struct S {
    #|  char a[3];
    #|  char b;
    #|};
    #|struct S s = { "abc", 5 };
    #|int main(void) {
    #|  return s.a[0] == 'a' && s.a[2] == 'c' && s.b == 5 ? 42 : s.b;
    #|}
  source
}

///|
test "strict MIR codegen emits exact-width global string aggregate fields" {
  let source = strict_mir_exact_width_global_string_aggregate_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for exact-width global string aggregate fields" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_exact_width_global_string_aggregate_source(),
    "strict_mir_exact_width_global_string_aggregate_differential",
  )
  assert_eq(result.code, 42)
}

///|
async test "strict MIR codegen matches parser codegen for global aggregate float array initializers" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_global_aggregate_float_array_initializer_source(),
    "strict_mir_global_aggregate_float_array_initializer_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_global_compound_literal_initializer_source() -> String {
  let source =
    #|int gi = (int){42};
    #|struct Pair {
    #|  int a;
    #|  int b;
    #|};
    #|struct Pair gp = (struct Pair){ .b = 35, .a = 7 };
    #|int main(void) {
    #|  return gi == 42 && gp.a + gp.b == 42 ? 42 : 1;
    #|}
  source
}

///|
test "strict MIR codegen executes global compound literal initializers" {
  let source = strict_mir_global_compound_literal_initializer_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
fn strict_mir_braced_scalar_global_initializer_source() -> String {
  let source =
    #|int scalar = {21};
    #|int nested = {{21}};
    #|double fp = {0.5 + 40.5};
    #|char *text = {"xyz"};
    #|int main(void) {
    #|  return scalar + nested == 42 && (int)fp == 41 && text[2] == 'z' ? 42 : 1;
    #|}
  source
}

///|
test "strict MIR codegen executes braced scalar global initializers" {
  let source = strict_mir_braced_scalar_global_initializer_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for braced scalar global initializers" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_braced_scalar_global_initializer_source(),
    "strict_mir_braced_scalar_global_initializer_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_nested_braced_scalar_global_initializer_source() -> String {
  let source =
    #|int arr[2] = {{20}, {22}};
    #|struct S {
    #|  int a;
    #|  double b;
    #|  char *c;
    #|};
    #|struct S s = {{7}, {35.5}, {"ok"}};
    #|int main(void) {
    #|  return arr[0] + arr[1] == 42 && s.a + (int)s.b == 42 && s.c[1] == 'k'
    #|       ? 42 : 1;
    #|}
  source
}

///|
test "strict MIR codegen executes nested braced scalar global initializers" {
  let source = strict_mir_nested_braced_scalar_global_initializer_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for nested braced scalar global initializers" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_nested_braced_scalar_global_initializer_source(),
    "strict_mir_nested_braced_scalar_global_initializer_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_file_scope_compound_literal_address_source() -> String {
  let source =
    #|struct S {
    #|  int a;
    #|  int b;
    #|};
    #|struct S *p = &(struct S){ .b = 23, .a = 19 };
    #|int *q = &((struct S){ 5, 37 }).b;
    #|int *r = (int[]){ 11, 31 };
    #|int main(void) {
    #|  return p->a + p->b == 42 && *q == 37 && r[0] + r[1] == 42 ? 42 : 1;
    #|}
  source
}

///|
test "strict MIR codegen executes file-scope compound literal addresses" {
  let source = strict_mir_file_scope_compound_literal_address_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for file-scope compound literal addresses" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_file_scope_compound_literal_address_source(),
    "strict_mir_file_scope_compound_literal_address_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_local_array_compound_literal_source() -> String {
  let source =
    #|struct Pair { int x; int y; };
    #|int main(void) {
    #|  int side = 0;
    #|  int *p = (int[]){ side += 10, 11 };
    #|  struct Pair *pairs = (struct Pair[]){ { 3, 4 }, { 7, 8 } };
    #|  int (*q)[2] = &(int[2]){ 4, 6 };
    #|  if (side != 10) return 1;
    #|  return p[0] + p[1] + pairs[0].x + pairs[1].y +
    #|    (*q)[0] + (*q)[1];
    #|}
  source
}

///|
test "strict MIR codegen executes local array compound literals" {
  let source = strict_mir_local_array_compound_literal_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for local array compound literals" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_local_array_compound_literal_source(),
    "strict_mir_local_array_compound_literal_differential",
  )
  assert_eq(result.code, 42)
}

///|
async test "strict MIR codegen matches parser codegen for global compound literal initializers" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_global_compound_literal_initializer_source(),
    "strict_mir_global_compound_literal_initializer_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_casted_string_pointer_global_array_initializer_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes casted string pointer global array initializers" {
  let source = strict_mir_casted_string_pointer_global_array_initializer_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for casted string pointer global array initializers" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_casted_string_pointer_global_array_initializer_source(),
    "strict_mir_casted_string_pointer_global_array_initializer_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aggregate_ternary_copy_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes aggregate ternary copies" {
  let source = strict_mir_aggregate_ternary_copy_source()
  assert_eq(run_source_strict_mir(source), 50)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate ternary copies" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_ternary_copy_source(),
    "strict_mir_aggregate_ternary_copy_differential",
  )
  assert_eq(result.code, 50)
}

///|
fn strict_mir_aggregate_call_result_ternary_assignment_source() -> String {
  let source =
    #|struct Box { int a; int b; };
    #|int side;
    #|struct Box make(int tag) {
    #|  struct Box box;
    #|  box.a = tag;
    #|  box.b = 42;
    #|  side = side * 10 + tag;
    #|  return box;
    #|}
    #|int pick_false(void) {
    #|  struct Box dst;
    #|  int cond = 0;
    #|  side = 0;
    #|  dst = cond ? make(1) : make(2);
    #|  if (side != 2) return side;
    #|  if (dst.a != 2) return dst.a;
    #|  return dst.b;
    #|}
    #|int pick_true(void) {
    #|  struct Box dst;
    #|  int cond = 1;
    #|  side = 0;
    #|  dst = cond ? make(3) : make(4);
    #|  if (side != 3) return side;
    #|  if (dst.a != 3) return dst.a;
    #|  return dst.b;
    #|}
    #|int main(void) {
    #|  if (pick_false() != 42) return 1;
    #|  if (pick_true() != 42) return 2;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen assigns aggregate call-result ternaries" {
  let source = strict_mir_aggregate_call_result_ternary_assignment_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate call-result ternary assignments" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_call_result_ternary_assignment_source(),
    "strict_mir_aggregate_call_result_ternary_assignment_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aggregate_ternary_call_argument_source() -> String {
  let source =
    #|struct Box { int a; int b; };
    #|struct Desc { int flags; struct Box getter; struct Box setter; };
    #|struct Box dup(struct Box v) { return v; }
    #|int main(void) {
    #|  struct Desc desc;
    #|  desc.flags = 0;
    #|  desc.getter.a = 1;
    #|  desc.getter.b = 2;
    #|  desc.setter.a = 20;
    #|  desc.setter.b = 21;
    #|  struct Box r = dup(desc.flags ? desc.getter : desc.setter);
    #|  return r.a + r.b + 1;
    #|}
  source
}

///|
test "strict MIR codegen passes aggregate ternary call arguments" {
  let source = strict_mir_aggregate_ternary_call_argument_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate ternary call arguments" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_ternary_call_argument_source(),
    "strict_mir_aggregate_ternary_call_argument_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aggregate_call_result_ternary_argument_source() -> String {
  let source =
    #|struct Box { int a; int b; };
    #|int side;
    #|struct Box make(int tag) {
    #|  struct Box box;
    #|  box.a = tag;
    #|  box.b = 42 - tag;
    #|  side = side * 10 + tag;
    #|  return box;
    #|}
    #|int sum(struct Box box) {
    #|  return box.a + box.b;
    #|}
    #|int pick_false(void) {
    #|  int cond = 0;
    #|  side = 0;
    #|  int value = sum(cond ? make(1) : make(2));
    #|  if (side != 2) return side;
    #|  return value;
    #|}
    #|int pick_true(void) {
    #|  int cond = 1;
    #|  side = 0;
    #|  int value = sum(cond ? make(3) : make(4));
    #|  if (side != 3) return side;
    #|  return value;
    #|}
    #|int main(void) {
    #|  if (pick_false() != 42) return 1;
    #|  if (pick_true() != 42) return 2;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen passes aggregate call-result ternary arguments" {
  let source = strict_mir_aggregate_call_result_ternary_argument_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate call-result ternary arguments" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_call_result_ternary_argument_source(),
    "strict_mir_aggregate_call_result_ternary_argument_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aggregate_call_result_ternary_member_read_source() -> String {
  let source =
    #|struct Box { int a; int b; };
    #|int side;
    #|struct Box make(int tag) {
    #|  struct Box box;
    #|  box.a = tag;
    #|  box.b = 42 - tag;
    #|  side = side * 10 + tag;
    #|  return box;
    #|}
    #|int pick_false(void) {
    #|  int cond = 0;
    #|  side = 0;
    #|  int value = (cond ? make(5) : make(6)).a;
    #|  if (side != 6) return side;
    #|  return value + 36;
    #|}
    #|int pick_true(void) {
    #|  int cond = 1;
    #|  side = 0;
    #|  int value = (cond ? make(7) : make(8)).a;
    #|  if (side != 7) return side;
    #|  return value + 35;
    #|}
    #|int main(void) {
    #|  if (pick_false() != 42) return 1;
    #|  if (pick_true() != 42) return 2;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen reads members from aggregate call-result ternaries" {
  let source = strict_mir_aggregate_call_result_ternary_member_read_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate call-result ternary member reads" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_call_result_ternary_member_read_source(),
    "strict_mir_aggregate_call_result_ternary_member_read_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aggregate_call_result_ternary_local_initializer_source() -> String {
  let source =
    #|struct Box { int a; int b; };
    #|int side;
    #|struct Box make(int tag) {
    #|  struct Box box;
    #|  box.a = tag;
    #|  box.b = 42 - tag;
    #|  side = side * 10 + tag;
    #|  return box;
    #|}
    #|int pick_false(void) {
    #|  int cond = 0;
    #|  side = 0;
    #|  struct Box box = cond ? make(1) : make(2);
    #|  if (side != 2) return side;
    #|  return box.a + box.b;
    #|}
    #|int pick_true(void) {
    #|  int cond = 1;
    #|  side = 0;
    #|  struct Box box = cond ? make(3) : make(4);
    #|  if (side != 3) return side;
    #|  return box.a + box.b;
    #|}
    #|int main(void) {
    #|  if (pick_false() != 42) return 1;
    #|  if (pick_true() != 42) return 2;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen initializes locals from aggregate call-result ternaries" {
  let source = strict_mir_aggregate_call_result_ternary_local_initializer_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate call-result ternary local initializers" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_call_result_ternary_local_initializer_source(),
    "strict_mir_aggregate_call_result_ternary_local_initializer_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aggregate_call_result_ternary_return_source() -> String {
  let source =
    #|struct Box { int a; int b; };
    #|int side;
    #|struct Box make(int tag) {
    #|  struct Box box;
    #|  box.a = tag;
    #|  box.b = 42 - tag;
    #|  side = side * 10 + tag;
    #|  return box;
    #|}
    #|struct Box pick(int cond) {
    #|  return cond ? make(5) : make(6);
    #|}
    #|int main(void) {
    #|  side = 0;
    #|  struct Box a = pick(0);
    #|  if (side != 6) return side;
    #|  if (a.a + a.b != 42) return 1;
    #|  side = 0;
    #|  struct Box b = pick(1);
    #|  if (side != 5) return side;
    #|  return b.a + b.b;
    #|}
  source
}

///|
test "strict MIR codegen returns aggregate call-result ternaries" {
  let source = strict_mir_aggregate_call_result_ternary_return_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate call-result ternary returns" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_call_result_ternary_return_source(),
    "strict_mir_aggregate_call_result_ternary_return_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aggregate_compound_literal_ternary_argument_source() -> String {
  let source =
    #|struct Box { int a; int b; };
    #|int sum(struct Box box) {
    #|  return box.a + box.b;
    #|}
    #|int main(void) {
    #|  int cond = 0;
    #|  if (sum(cond ? (struct Box){ 1, 2 } : (struct Box){ 19, 23 }) != 42) {
    #|    return 1;
    #|  }
    #|  cond = 1;
    #|  return sum(cond ? (struct Box){ 20, 22 } : (struct Box){ 3, 4 });
    #|}
  source
}

///|
test "strict MIR codegen passes aggregate compound literal ternary arguments" {
  let source = strict_mir_aggregate_compound_literal_ternary_argument_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate compound literal ternary arguments" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_compound_literal_ternary_argument_source(),
    "strict_mir_aggregate_compound_literal_ternary_argument_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aggregate_compound_literal_ternary_return_source() -> String {
  let source =
    #|struct Box { int a; int b; };
    #|struct Box pick(int cond) {
    #|  return cond ? (struct Box){ 20, 22 } : (struct Box){ 19, 23 };
    #|}
    #|int main(void) {
    #|  struct Box a = pick(0);
    #|  if (a.a + a.b != 42) return 1;
    #|  struct Box b = pick(1);
    #|  return b.a + b.b;
    #|}
  source
}

///|
test "strict MIR codegen returns aggregate compound literal ternaries" {
  let source = strict_mir_aggregate_compound_literal_ternary_return_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate compound literal ternary returns" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_compound_literal_ternary_return_source(),
    "strict_mir_aggregate_compound_literal_ternary_return_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aggregate_compound_literal_ternary_assignment_source() -> String {
  let source =
    #|struct Box { int a; int b; };
    #|int main(void) {
    #|  struct Box rval;
    #|  int found = 0;
    #|  rval = !found ? (struct Box){ 1, 41 } : (struct Box){ 1, 2 };
    #|  return rval.a + rval.b;
    #|}
  source
}

///|
test "strict MIR codegen assigns aggregate compound literal ternaries" {
  let source = strict_mir_aggregate_compound_literal_ternary_assignment_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate compound literal ternary assignments" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_compound_literal_ternary_assignment_source(),
    "strict_mir_aggregate_compound_literal_ternary_assignment_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aggregate_void_cast_source() -> String {
  let source =
    #|struct Token { int n; };
    #|int main(void) {
    #|  struct Token t;
    #|  t.n = 42;
    #|  (void)t;
    #|  return t.n;
    #|}
  source
}

///|
test "strict MIR codegen ignores aggregate void casts" {
  let source = strict_mir_aggregate_void_cast_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate void casts" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_void_cast_source(),
    "strict_mir_aggregate_void_cast_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_member_array_decay_pointer_call_args_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes member array decay in pointer call args" {
  let source = strict_mir_member_array_decay_pointer_call_args_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for member array decay in pointer call args" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_member_array_decay_pointer_call_args_source(),
    "strict_mir_member_array_decay_pointer_call_args_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_atomic_load_store_source() -> String {
  let source =
    #|int main(void) {
    #|  unsigned int x = 5;
    #|  int order = 0;
    #|  __atomic_store_n(&x, 37, order += 1);
    #|  if (order != 1) return 1;
    #|  if (__atomic_load_n(&x, order += 2) != 37) return 2;
    #|  return 39 + order;
    #|}
  source
}

///|
test "strict MIR codegen executes atomic load/store operations" {
  let source = strict_mir_atomic_load_store_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for atomic load/store operations" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_atomic_load_store_source(),
    "strict_mir_atomic_load_store_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_atomic_read_modify_write_source() -> String {
  (
    #|int main(void) {
    #|  _Atomic(unsigned char) b = 5;
    #|  _Atomic(unsigned short) h = 10;
    #|  _Atomic(unsigned int) x = 5;
    #|  _Atomic(unsigned long) q = 40;
    #|  unsigned int expected = 11;
    #|  unsigned int y = 1;
    #|  if (__c11_atomic_fetch_add(&x, 3, 5) != 5) return 1;
    #|  if (x != 8) return 2;
    #|  if (__c11_atomic_fetch_sub(&x, 1, 5) != 8) return 3;
    #|  if (__c11_atomic_fetch_or(&x, 16, 5) != 7) return 4;
    #|  if (__c11_atomic_fetch_and(&x, 23, 5) != 23) return 5;
    #|  if (__c11_atomic_fetch_xor(&x, 3, 5) != 23) return 6;
    #|  if (__c11_atomic_exchange(&x, 11, 5) != 20) return 7;
    #|  if (!__c11_atomic_compare_exchange_strong(&x, &expected, 19, 5, 5)) return 8;
    #|  if (x != 19) return 9;
    #|  expected = 11;
    #|  if (__c11_atomic_compare_exchange_weak(&x, &expected, 21, 5, 5)) return 10;
    #|  if (expected != 19) return 11;
    #|  if (__c11_atomic_load(&x, 5) != 19) return 12;
    #|  if (__c11_atomic_fetch_add(&b, 1, 5) != 5) return 13;
    #|  if (__c11_atomic_fetch_sub(&h, 3, 5) != 10) return 14;
    #|  if (__c11_atomic_exchange(&q, 42, 5) != 40) return 15;
    #|  if (__atomic_add_fetch(&y, 4, 5) != 5) return 16;
    #|  if (__atomic_fetch_xor(&y, 1, 5) != 5) return 17;
    #|  if (__atomic_exchange_n(&y, 8, 5) != 4) return 18;
    #|  expected = 8;
    #|  if (!__atomic_compare_exchange_n(&y, &expected, 9, 0, 5, 5)) return 19;
    #|  return (int)(x + b + h + q + y);
    #|}
  )
}

///|
test "strict MIR codegen executes atomic read modify write builtins" {
  let source = strict_mir_atomic_read_modify_write_source()
  assert_eq(run_source_strict_mir(source), 83)
}

///|
async test "strict MIR codegen matches parser codegen for atomic read modify write builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_atomic_read_modify_write_source(),
    "strict_mir_atomic_read_modify_write_differential",
  )
  assert_eq(result.code, 83)
}

///|
fn strict_mir_exchange_style_atomic_source() -> String {
  let source =
    #|int main(void) {
    #|  unsigned char flag = 0;
    #|  unsigned int w = 10;
    #|  int side = 0;
    #|  if (__atomic_test_and_set(&flag, side += 1)) return 1;
    #|  if (side != 1 || flag != 1) return 2;
    #|  if (!__atomic_test_and_set(&flag, side += 2)) return 3;
    #|  if (side != 3) return 4;
    #|  __atomic_clear(&flag, side += 4);
    #|  if (side != 7 || flag != 0) return 5;
    #|  if (__sync_fetch_and_add(&w, 2u) != 10u) return 6;
    #|  if (__sync_add_and_fetch(&w, 5u) != 17u) return 7;
    #|  if (__sync_fetch_and_nand(&w, 15u) != 17u) return 8;
    #|  if (w != ~1u) return 9;
    #|  __sync_lock_release(&w);
    #|  if (w != 0u) return 10;
    #|  if (__sync_lock_test_and_set(&w, 23u) != 0u) return 11;
    #|  if (__sync_swap(&w, 42u) != 23u) return 12;
    #|  return (int)w;
    #|}
  source
}

///|
test "strict MIR codegen executes exchange-style atomic builtins" {
  let source = strict_mir_exchange_style_atomic_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for exchange-style atomic builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_exchange_style_atomic_source(),
    "strict_mir_exchange_style_atomic_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_sync_compare_and_swap_source() -> String {
  let source =
    #|int main(void) {
    #|  unsigned int w = 10u;
    #|  int side = 0;
    #|  if (!__sync_bool_compare_and_swap(&w, side += 10, 12u)) return 1;
    #|  if (side != 10 || w != 12u) return 2;
    #|  if (__sync_bool_compare_and_swap(&w, 10u, side += 1)) return 3;
    #|  if (side != 11 || w != 12u) return 4;
    #|  if (__sync_val_compare_and_swap(&w, 12u, side += 6) != 12u) return 5;
    #|  if (side != 17 || w != 17u) return 6;
    #|  if (__sync_val_compare_and_swap(&w, 12u, side += 25) != 17u) return 7;
    #|  if (side != 42 || w != 17u) return 8;
    #|  return side;
    #|}
  source
}

///|
test "strict MIR codegen executes sync compare-and-swap builtins" {
  let source = strict_mir_sync_compare_and_swap_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for sync compare-and-swap builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_sync_compare_and_swap_source(),
    "strict_mir_sync_compare_and_swap_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_generic_pointer_atomic_source() -> String {
  (
    #|int main(void) {
    #|  int x = 11;
    #|  int out = 0;
    #|  int set = 17;
    #|  int old = 0;
    #|  int desired = 23;
    #|  int expected = 17;
    #|  int side = 0;
    #|  __atomic_load(&x, &out, side += 1);
    #|  if (out != 11 || side != 1) return 1;
    #|  __atomic_store(&x, &set, side += 2);
    #|  if (x != 17 || side != 3) return 2;
    #|  __atomic_exchange(&x, &desired, &old, side += 4);
    #|  if (x != 23 || old != 17 || side != 7) return 3;
    #|  int fail_desired = 29;
    #|  expected = 17;
    #|  if (__atomic_compare_exchange(&x, &expected, &fail_desired, side += 8, side += 16, side += 32)) return 4;
    #|  if (expected != 23 || x != 23 || side != 63) return 5;
    #|  desired = 31;
    #|  expected = 23;
    #|  if (!__atomic_compare_exchange(&x, &expected, &desired, side += 64, side += 128, side += 256)) return 6;
    #|  if (x != 31 || expected != 23 || side != 511) return 7;
    #|  return 42;
    #|}
  )
}

///|
test "strict MIR codegen executes generic pointer atomic builtins" {
  let source = strict_mir_generic_pointer_atomic_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for generic pointer atomic builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_generic_pointer_atomic_source(),
    "strict_mir_generic_pointer_atomic_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_atomic_lock_free_query_source() -> String {
  (
    #|int main(void) {
    #|  int side = 0;
    #|  int object = 0;
    #|  if (!__atomic_is_lock_free((side += 1, 4), &object)) return 1;
    #|  if (side != 1) return 2;
    #|  if (__atomic_is_lock_free(3, (void *)(long)(side += 10))) return 3;
    #|  if (side != 11) return 4;
    #|  if (!__c11_atomic_is_lock_free((side += 4, 8))) return 5;
    #|  if (__c11_atomic_is_lock_free(16)) return 6;
    #|  if (!__atomic_always_lock_free(4, (void *)(long)(side += 100))) return 7;
    #|  if (__atomic_always_lock_free(16, 0)) return 8;
    #|  if (side != 15) return 9;
    #|  return 42;
    #|}
  )
}

///|
test "strict MIR codegen executes atomic lock-free query builtins" {
  let source = strict_mir_atomic_lock_free_query_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for atomic lock-free query builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_atomic_lock_free_query_source(),
    "strict_mir_atomic_lock_free_query_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_sync_minmax_atomic_source() -> String {
  let source =
    #|int main(void) {
    #|  int sw = -3;
    #|  unsigned int uw = 10u;
    #|  if (__sync_fetch_and_max(&sw, -1) != -3) return 1;
    #|  if (sw != -1) return 2;
    #|  if (__sync_fetch_and_min(&sw, -7) != -1) return 3;
    #|  if (sw != -7) return 4;
    #|  if (__sync_fetch_and_umax(&uw, 12u) != 10u) return 5;
    #|  if (uw != 12u) return 6;
    #|  if (__sync_fetch_and_umin(&uw, 7u) != 12u) return 7;
    #|  if (uw != 7u) return 8;
    #|  return sw + (int)uw + 42;
    #|}
  source
}

///|
test "strict MIR codegen executes sync minmax atomic builtins" {
  let source = strict_mir_sync_minmax_atomic_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for sync minmax atomic builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_sync_minmax_atomic_source(),
    "strict_mir_sync_minmax_atomic_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_atomic_rmw_extra_operands_source() -> String {
  let source =
    #|int main(void) {
    #|  unsigned int x = 5;
    #|  unsigned int expected = 20;
    #|  int order = 0;
    #|  int exchange_order = 0;
    #|  int weak = 0;
    #|  int success = 0;
    #|  int failure = 0;
    #|  if (__atomic_fetch_add(&x, 7, order += 1) != 5) return 1;
    #|  if (x != 12) return 2;
    #|  if (__atomic_exchange_n(&x, 20, exchange_order += 2) != 12) return 3;
    #|  if (!__atomic_compare_exchange_n(&x, &expected, 42, weak += 1, success += 2, failure += 3)) return 4;
    #|  if (x != 42) return 5;
    #|  if (order != 1 || exchange_order != 2 || weak != 1 || success != 2 || failure != 3) return 6;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen evaluates atomic rmw extra operands" {
  let source = strict_mir_atomic_rmw_extra_operands_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for atomic rmw extra operands" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_atomic_rmw_extra_operands_source(),
    "strict_mir_atomic_rmw_extra_operands_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_integer_overflow_source() -> String {
  let source =
    #|int main(void) {
    #|  int i = 0;
    #|  unsigned u = 0;
    #|  long long l = 0;
    #|  unsigned long long ul = 0;
    #|  int total = 0;
    #|  total += __builtin_add_overflow(1, 2, &i);
    #|  if (i != 3) return 1;
    #|  total += __builtin_add_overflow(2147483647, 1, &i);
    #|  if (i != (-2147483647 - 1)) return 2;
    #|  total += __builtin_sub_overflow(0u, 1u, &u);
    #|  if (u != 4294967295u) return 3;
    #|  total += __builtin_mul_overflow(50000, 50000, &i);
    #|  if (i >= 0) return 4;
    #|  total += __builtin_uaddll_overflow(0xffffffffffffffffULL, 1ULL, &ul);
    #|  if (ul != 0ULL) return 5;
    #|  total += __builtin_saddll_overflow(9223372036854775807LL, 1LL, &l);
    #|  if (l != (-9223372036854775807LL - 1LL)) return 6;
    #|  return total + 37;
    #|}
  source
}

///|
test "strict MIR codegen executes integer overflow builtins" {
  let source = strict_mir_integer_overflow_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for integer overflow builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_integer_overflow_source(),
    "strict_mir_integer_overflow_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_anonymous_union_array_member_decay_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes anonymous union array member decay" {
  let source = strict_mir_anonymous_union_array_member_decay_source()
  assert_eq(run_source_strict_mir(source), 1)
}

///|
async test "strict MIR codegen matches parser codegen for anonymous union array member decay" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_anonymous_union_array_member_decay_source(),
    "strict_mir_anonymous_union_array_member_decay_differential",
  )
  assert_eq(result.code, 1)
}

///|
fn strict_mir_local_extern_function_prototype_source() -> String {
  let source =
    #|int value = 37;
    #|int *external_ptr(void) {
    #|  return &value;
    #|}
    #|int read_external(void) {
    #|  extern int *external_ptr(void);
    #|  return *external_ptr();
    #|}
    #|int main(void) {
    #|  return read_external();
    #|}
  source
}

///|
test "strict MIR codegen executes local extern function prototypes" {
  let source = strict_mir_local_extern_function_prototype_source()
  assert_eq(run_source_strict_mir(source), 37)
}

///|
async test "strict MIR codegen matches parser codegen for local extern function prototypes" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_local_extern_function_prototype_source(),
    "strict_mir_local_extern_function_prototype_differential",
  )
  assert_eq(result.code, 37)
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
fn strict_mir_local_pointer_updates_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes local pointer updates" {
  let source = strict_mir_local_pointer_updates_source()
  assert_eq(run_source_strict_mir(source), 16)
}

///|
async test "strict MIR codegen matches parser codegen for local pointer updates" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_local_pointer_updates_source(),
    "strict_mir_local_pointer_updates_differential",
  )
  assert_eq(result.code, 16)
}

///|
fn strict_mir_casted_pointer_dereference_source() -> String {
  let source =
    #|int main(void) {
    #|  char c = 37;
    #|  char *p = &c;
    #|  return *(unsigned char*)p;
    #|}
  source
}

///|
test "strict MIR codegen executes casted pointer dereference" {
  let source = strict_mir_casted_pointer_dereference_source()
  assert_eq(run_source_strict_mir(source), 37)
}

///|
async test "strict MIR codegen matches parser codegen for casted pointer dereference" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_casted_pointer_dereference_source(),
    "strict_mir_casted_pointer_dereference_differential",
  )
  assert_eq(result.code, 37)
}

///|
fn strict_mir_casted_global_array_decay_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes casted global array decay" {
  let source = strict_mir_casted_global_array_decay_source()
  assert_eq(run_source_strict_mir(source), 8)
}

///|
async test "strict MIR codegen matches parser codegen for casted global array decay" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_casted_global_array_decay_source(),
    "strict_mir_casted_global_array_decay_differential",
  )
  assert_eq(result.code, 8)
}

///|
fn strict_mir_aligned_global_array_address_source() -> String {
  let source =
    #|static unsigned char secret[16] __attribute__((aligned(64))) = {1, 2, 3, 4, 5, 6, 7, 8};
    #|unsigned char *get(void) {
    #|  return (unsigned char*)secret;
    #|}
    #|int main(void) {
    #|  unsigned char *p = get();
    #|  return p[0] + p[7] + (((unsigned long)p & 63) == 0 ? 33 : 0);
    #|}
  source
}

///|
test "strict MIR codegen takes address of aligned global arrays" {
  let source = strict_mir_aligned_global_array_address_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aligned global array addresses" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aligned_global_array_address_source(),
    "strict_mir_aligned_global_array_address_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aligned_local_array_scratch_source() -> String {
  let source =
    #|static void mix(unsigned long long *acc, unsigned long long seed) {
    #|  acc[0] += seed;
    #|  acc[1] ^= seed;
    #|}
    #|int main(void) {
    #|  _Alignas(8) unsigned long long acc[4] = {10ull, 20ull, 7ull, 2ull};
    #|  mix(acc, 5ull);
    #|  return acc[0] == 15ull && acc[1] == 17ull && acc[2] == 7ull && acc[3] == 2ull ? 42 : 1;
    #|}
  source
}

///|
test "strict MIR codegen executes aligned local array scratch state" {
  let source = strict_mir_aligned_local_array_scratch_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aligned local array scratch state" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aligned_local_array_scratch_source(),
    "strict_mir_aligned_local_array_scratch_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_over_aligned_array_field_pointer_source() -> String {
  let source =
    #|struct State {
    #|  int pad;
    #|  unsigned long long acc[2] __attribute__((aligned(64)));
    #|  unsigned long len;
    #|};
    #|static struct State st;
    #|static void reset(struct State *s) {
    #|  s->acc[0] = 10ull;
    #|  s->acc[1] = 32ull;
    #|  s->len = s->acc[0] + s->acc[1];
    #|}
    #|int main(void) {
    #|  reset(&st);
    #|  return st.len == 42ul ? 42 : 1;
    #|}
  source
}

///|
test "strict MIR codegen writes over-aligned array fields through pointers" {
  let source = strict_mir_over_aligned_array_field_pointer_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for over-aligned array field pointers" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_over_aligned_array_field_pointer_source(),
    "strict_mir_over_aligned_array_field_pointer_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_implicit_global_array_decay_source() -> String {
  let source =
    #|char version[4] = "abc";
    #|char *get(void) {
    #|  return version;
    #|}
    #|int main(void) {
    #|  char *p = get();
    #|  return p[1];
    #|}
  source
}

///|
test "strict MIR codegen returns implicit global array decay" {
  let source = strict_mir_implicit_global_array_decay_source()
  assert_eq(run_source_strict_mir(source), 98)
}

///|
async test "strict MIR codegen matches parser codegen for implicit global array decay" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_implicit_global_array_decay_source(),
    "strict_mir_implicit_global_array_decay_differential",
  )
  assert_eq(result.code, 98)
}

///|
fn strict_mir_floating_local_casts_source() -> String {
  let source =
    #|int main(void) {
    #|  double x = 1.75;
    #|  double y = 2.25;
    #|  return (int)x + (int)y;
    #|}
  source
}

///|
test "strict MIR codegen executes floating local casts to int" {
  let source = strict_mir_floating_local_casts_source()
  assert_eq(run_source_strict_mir(source), 3)
}

///|
async test "strict MIR codegen matches parser codegen for floating local casts to int" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_local_casts_source(),
    "strict_mir_floating_local_casts_differential",
  )
  assert_eq(result.code, 3)
}

///|
fn strict_mir_floating_local_comparisons_source() -> String {
  let source =
    #|int main(void) {
    #|  double x = 1.5;
    #|  double y = 2.5;
    #|  return (x < y) + (x != y) + (y > 2.0) + (x == 1.5) + (x <= y) + (y >= x);
    #|}
  source
}

///|
test "strict MIR codegen executes floating local comparisons" {
  let source = strict_mir_floating_local_comparisons_source()
  assert_eq(run_source_strict_mir(source), 6)
}

///|
async test "strict MIR codegen matches parser codegen for floating local comparisons" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_local_comparisons_source(),
    "strict_mir_floating_local_comparisons_differential",
  )
  assert_eq(result.code, 6)
}

///|
fn strict_mir_floating_ternary_conversions_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes floating ternary conversions" {
  let source = strict_mir_floating_ternary_conversions_source()
  assert_eq(run_source_strict_mir(source), 58)
}

///|
async test "strict MIR codegen matches parser codegen for floating ternary conversions" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_ternary_conversions_source(),
    "strict_mir_floating_ternary_conversions_differential",
  )
  assert_eq(result.code, 58)
}

///|
fn strict_mir_floating_logical_operators_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes floating logical operators" {
  let source = strict_mir_floating_logical_operators_source()
  assert_eq(run_source_strict_mir(source), 37)
}

///|
async test "strict MIR codegen matches parser codegen for floating logical operators" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_logical_operators_source(),
    "strict_mir_floating_logical_operators_differential",
  )
  assert_eq(result.code, 37)
}

///|
fn strict_mir_floating_compound_updates_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes floating compound updates" {
  let source = strict_mir_floating_compound_updates_source()
  assert_eq(run_source_strict_mir(source), 114)
}

///|
async test "strict MIR codegen matches parser codegen for floating compound updates" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_compound_updates_source(),
    "strict_mir_floating_compound_updates_differential",
  )
  assert_eq(result.code, 114)
}

///|
fn strict_mir_floating_local_arithmetic_source() -> String {
  let source =
    #|int main(void) {
    #|  double x = 5.5;
    #|  double y = 2.0;
    #|  return (int)(x + y) + (int)(x - y) + (int)(x * y) + (int)(x / y) + (int)(x + 2);
    #|}
  source
}

///|
test "strict MIR codegen executes floating local arithmetic" {
  let source = strict_mir_floating_local_arithmetic_source()
  assert_eq(run_source_strict_mir(source), 30)
}

///|
async test "strict MIR codegen matches parser codegen for floating local arithmetic" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_local_arithmetic_source(),
    "strict_mir_floating_local_arithmetic_differential",
  )
  assert_eq(result.code, 30)
}

///|
fn strict_mir_float_local_arithmetic_source() -> String {
  let source =
    #|int main(void) {
    #|  float x = (float)5.5;
    #|  float y = (float)2.0;
    #|  return (int)(x + y) + (int)(x - y) + (int)(x * y) + (int)(x / y) + (int)(x + 2);
    #|}
  source
}

///|
test "strict MIR codegen executes float local arithmetic" {
  let source = strict_mir_float_local_arithmetic_source()
  assert_eq(run_source_strict_mir(source), 30)
}

///|
async test "strict MIR codegen matches parser codegen for float local arithmetic" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_float_local_arithmetic_source(),
    "strict_mir_float_local_arithmetic_differential",
  )
  assert_eq(result.code, 30)
}

///|
fn strict_mir_floating_array_byte_memory_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern void *memmove(void *, const void *, size_t);
    #|extern int memcmp(const void *, const void *, size_t);
    #|int main(void) {
    #|  double src[2] = {1.5, 2.25};
    #|  double dst[2] = {0.0, 0.0};
    #|  float fs[3] = {1.25f, 2.5f, 3.75f};
    #|  float fd[3] = {0.0f, 0.0f, 0.0f};
    #|  if (memcpy(dst, src, sizeof(src)) != dst) return 1;
    #|  if (memmove(fd, fs, sizeof(fs)) != fd) return 2;
    #|  if (memcmp(dst, src, sizeof(src)) != 0) return 3;
    #|  if (memcmp(fd, fs, sizeof(fs)) != 0) return 4;
    #|  if ((int)(dst[0] * 10.0) != 15) return 5;
    #|  if ((int)(dst[1] * 100.0) != 225) return 6;
    #|  if ((int)(fd[0] * 100.0f) != 125) return 7;
    #|  fd[1] += 1.5f;
    #|  if ((int)(fd[1] * 10.0f) != 40) return 8;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes floating array byte memory" {
  let source = strict_mir_floating_array_byte_memory_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for floating array byte memory" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_array_byte_memory_source(),
    "strict_mir_floating_array_byte_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_floating_aggregate_byte_copy_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memset(void *, int, size_t);
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern void *memmove(void *, const void *, size_t);
    #|struct Box {
    #|  char tag;
    #|  float f;
    #|  double d;
    #|};
    #|int main(void) {
    #|  struct Box src;
    #|  struct Box dst;
    #|  struct Box slots[2];
    #|  memset(&src, 0, sizeof(src));
    #|  memset(&dst, 0, sizeof(dst));
    #|  memset(slots, 0, sizeof(slots));
    #|  src.tag = 5;
    #|  src.f = 1.25f;
    #|  src.d = 2.5;
    #|  if (memcpy(&dst, &src, sizeof(src)) != &dst) return 1;
    #|  if (dst.tag != 5) return 2;
    #|  if ((int)(dst.f * 100.0f) != 125) return 3;
    #|  if ((int)(dst.d * 10.0) != 25) return 4;
    #|  slots[0].tag = 1;
    #|  slots[0].f = 3.5f;
    #|  slots[0].d = 4.5;
    #|  if (memmove(&slots[1], &slots[0], sizeof(slots[0])) != &slots[1]) return 5;
    #|  if (slots[1].tag != 1) return 6;
    #|  if ((int)(slots[1].f * 10.0f) != 35) return 7;
    #|  if ((int)(slots[1].d * 10.0) != 45) return 8;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes floating aggregate byte copies" {
  let source = strict_mir_floating_aggregate_byte_copy_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for floating aggregate byte copies" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_aggregate_byte_copy_source(),
    "strict_mir_floating_aggregate_byte_copy_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_global_floating_aggregate_byte_copy_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memset(void *, int, size_t);
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern void *memmove(void *, const void *, size_t);
    #|struct Box {
    #|  char tag;
    #|  float f;
    #|  double d;
    #|};
    #|struct Box global_box;
    #|struct Box global_slots[2];
    #|int main(void) {
    #|  struct Box local;
    #|  struct Box copy;
    #|  memset(&global_box, 0, sizeof(global_box));
    #|  memset(global_slots, 0, sizeof(global_slots));
    #|  memset(&local, 0, sizeof(local));
    #|  memset(&copy, 0, sizeof(copy));
    #|  local.tag = 7;
    #|  local.f = 1.5f;
    #|  local.d = 2.25;
    #|  if (memcpy(&global_box, &local, sizeof(global_box)) != &global_box) return 1;
    #|  if (global_box.tag != 7) return 2;
    #|  if ((int)(global_box.f * 10.0f) != 15) return 3;
    #|  if ((int)(global_box.d * 100.0) != 225) return 4;
    #|  if (memmove(&copy, &global_box, sizeof(copy)) != &copy) return 5;
    #|  if (copy.tag != 7) return 6;
    #|  if ((int)(copy.f * 10.0f) != 15) return 7;
    #|  global_slots[0] = copy;
    #|  if (memcpy(&global_slots[1], &global_slots[0], sizeof(global_slots[0])) != &global_slots[1]) return 8;
    #|  if (global_slots[1].tag != 7) return 9;
    #|  if ((int)(global_slots[1].d * 100.0) != 225) return 10;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes global floating aggregate byte copies" {
  let source = strict_mir_global_floating_aggregate_byte_copy_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for global floating aggregate byte copies" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_global_floating_aggregate_byte_copy_source(),
    "strict_mir_global_floating_aggregate_byte_copy_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_union_overlay_byte_memory_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern int memcmp(const void *, const void *, size_t);
    #|union Value {
    #|  float f;
    #|  unsigned u;
    #|  unsigned char bytes[4];
    #|};
    #|union BytesFirst {
    #|  unsigned char bytes[4];
    #|  float f;
    #|  unsigned u;
    #|};
    #|int main(void) {
    #|  union Value v;
    #|  v.f = 1.0f;
    #|  if (v.u != 0x3f800000u) return 1;
    #|  v.bytes[0] = 0u;
    #|  v.bytes[1] = 0u;
    #|  v.bytes[2] = 0u;
    #|  v.bytes[3] = 0x40u;
    #|  if ((int)v.f != 2) return 2;
    #|  union BytesFirst w;
    #|  unsigned char raw[4] = {0u, 0u, 0x40u, 0x40u};
    #|  if (memcpy(w.bytes, raw, 4) != w.bytes) return 3;
    #|  if ((int)w.f != 3) return 4;
    #|  if (memcmp(w.bytes, raw, 4) != 0) return 5;
    #|  w.u = 0x40800000u;
    #|  if ((int)w.f != 4) return 6;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes union overlay byte memory" {
  let source = strict_mir_union_overlay_byte_memory_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for union overlay byte memory" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_union_overlay_byte_memory_source(),
    "strict_mir_union_overlay_byte_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_long_double_byte_memory_source() -> String {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern void *memmove(void *, const void *, size_t);
    #|extern void *memset(void *, int, size_t);
    #|struct LDBox { char tag; long double value; };
    #|static long double global_ld = 8.5L;
    #|static struct LDBox global_box;
    #|int main(void) {
    #|  long double x = 1.25L;
    #|  long double y = 0.0L;
    #|  long double z = -4.5L;
    #|  if (memcpy(&y, &x, sizeof(y)) != &y) return 1;
    #|  if ((int)(y * 4.0L) != 5) return 2;
    #|  if (memmove(&z, &global_ld, sizeof(z)) != &z) return 3;
    #|  if ((int)(z * 2.0L) != 17) return 4;
    #|  if (memset(&z, 0, sizeof(z)) != &z) return 5;
    #|  if ((int)z != 0) return 6;
    #|  long double src[2] = {2.5L, 3.5L};
    #|  long double dst[2] = {0.0L, 0.0L};
    #|  if (memcpy(dst, src, sizeof(src)) != dst) return 7;
    #|  if ((int)(dst[0] * 10.0L) != 25) return 8;
    #|  if ((int)(dst[1] * 10.0L) != 35) return 9;
    #|  struct LDBox box;
    #|  memset(&box, 0, sizeof(box));
    #|  box.tag = 4;
    #|  box.value = 4.75L;
    #|  if (memcpy(&global_box, &box, sizeof(box)) != &global_box) return 10;
    #|  if (global_box.tag != 4) return 11;
    #|  if ((int)(global_box.value * 4.0L) != 19) return 12;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes Darwin long double byte memory" {
  let source = strict_mir_long_double_byte_memory_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for Darwin long double byte memory" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_long_double_byte_memory_source(),
    "strict_mir_long_double_byte_memory_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_floating_unary_operators_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes floating unary operators" {
  let source = strict_mir_floating_unary_operators_source()
  assert_eq(run_source_strict_mir(source), 37)
}

///|
async test "strict MIR codegen matches parser codegen for floating unary operators" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_unary_operators_source(),
    "strict_mir_floating_unary_operators_differential",
  )
  assert_eq(result.code, 37)
}

///|
fn strict_mir_floating_direct_call_source() -> String {
  let source =
    #|double add(double x, double y) { return x + y; }
    #|double mix(int a, double b, int c) { return a + b + c; }
    #|int main(void) {
    #|  return (int)add(2.25, 3.75) + (int)mix(2, 3.5, 4);
    #|}
  source
}

///|
test "strict MIR codegen executes floating direct calls" {
  let source = strict_mir_floating_direct_call_source()
  assert_eq(run_source_strict_mir(source), 15)
}

///|
async test "strict MIR codegen matches parser codegen for floating direct calls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_direct_call_source(),
    "strict_mir_floating_direct_call_differential",
  )
  assert_eq(result.code, 15)
}

///|
fn strict_mir_stack_floating_direct_call_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes stack-passed floating direct calls" {
  let source = strict_mir_stack_floating_direct_call_source()
  assert_eq(run_source_strict_mir(source), 90)
}

///|
async test "strict MIR codegen matches parser codegen for stack-passed floating direct calls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_stack_floating_direct_call_source(),
    "strict_mir_stack_floating_direct_call_differential",
  )
  assert_eq(result.code, 90)
}

///|
fn strict_mir_float_direct_and_indirect_call_source() -> String {
  let source =
    #|float addf(float x, float y) { return x + y; }
    #|float mixf(int a, float b, int c) { return a + b + c; }
    #|int main(void) {
    #|  float (*fp)(float, float) = addf;
    #|  return (int)addf((float)2.25, (float)3.75) + (int)mixf(2, (float)3.5, 4) + (int)fp((float)1.25, (float)2.75);
    #|}
  source
}

///|
test "strict MIR codegen executes float direct and indirect calls" {
  let source = strict_mir_float_direct_and_indirect_call_source()
  assert_eq(run_source_strict_mir(source), 19)
}

///|
async test "strict MIR codegen matches parser codegen for float direct and indirect calls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_float_direct_and_indirect_call_source(),
    "strict_mir_float_direct_and_indirect_call_differential",
  )
  assert_eq(result.code, 19)
}

///|
fn strict_mir_floating_indirect_call_source() -> String {
  let source =
    #|double add(double x, double y) { return x + y; }
    #|double mix(int a, double b, int c) { return a + b + c; }
    #|int main(void) {
    #|  double (*fp)(double, double) = add;
    #|  double (*gp)(int, double, int) = mix;
    #|  return (int)fp(2.25, 3.75) + (int)gp(2, 3.5, 4);
    #|}
  source
}

///|
test "strict MIR codegen executes floating indirect calls" {
  let source = strict_mir_floating_indirect_call_source()
  assert_eq(run_source_strict_mir(source), 15)
}

///|
async test "strict MIR codegen matches parser codegen for floating indirect calls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_indirect_call_source(),
    "strict_mir_floating_indirect_call_differential",
  )
  assert_eq(result.code, 15)
}

///|
fn strict_mir_indirect_calls_returning_function_pointers_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes indirect calls returning function pointers" {
  let source = strict_mir_indirect_calls_returning_function_pointers_source()
  assert_eq(run_source_strict_mir(source), 37)
}

///|
async test "strict MIR codegen matches parser codegen for indirect calls returning function pointers" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_indirect_calls_returning_function_pointers_source(),
    "strict_mir_indirect_calls_returning_function_pointers_differential",
  )
  assert_eq(result.code, 37)
}

///|
fn strict_mir_stack_floating_indirect_call_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes stack-passed floating indirect calls" {
  let source = strict_mir_stack_floating_indirect_call_source()
  assert_eq(run_source_strict_mir(source), 90)
}

///|
async test "strict MIR codegen matches parser codegen for stack-passed floating indirect calls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_stack_floating_indirect_call_source(),
    "strict_mir_stack_floating_indirect_call_differential",
  )
  assert_eq(result.code, 90)
}

///|
fn strict_mir_floating_variadic_libcall_source() -> String {
  let source =
    #|int main(void) {
    #|  char buf[64];
    #|  int n = __builtin___snprintf_chk(buf, 64, 0, 64, "%.1f", 1.5);
    #|  return n + (buf[0] == '1') + (buf[1] == '.') + (buf[2] == '5');
    #|}
  source
}

///|
test "strict MIR codegen executes floating variadic libcalls" {
  let source = strict_mir_floating_variadic_libcall_source()
  assert_eq(run_source_strict_mir(source), 6)
}

///|
async test "strict MIR codegen matches parser codegen for floating variadic libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_variadic_libcall_source(),
    "strict_mir_floating_variadic_libcall_differential",
  )
  assert_eq(result.code, 6)
}

///|
fn strict_mir_stack_floating_variadic_libcall_source() -> String {
  let source =
    #|int main(void) {
    #|  char buf[32];
    #|  int n = __builtin___snprintf_chk(buf, 32, 0, 32, "%.0f%.0f%.0f%.0f%.0f%.0f%.0f%.0f%.0f", 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0);
    #|  return n + (buf[0] == '1') + (buf[1] == '2') + (buf[2] == '3') + (buf[3] == '4') + (buf[4] == '5') + (buf[5] == '6') + (buf[6] == '7') + (buf[7] == '8') + (buf[8] == '9');
    #|}
  source
}

///|
test "strict MIR codegen executes stack-passed floating variadic libcalls" {
  let source = strict_mir_stack_floating_variadic_libcall_source()
  assert_eq(run_source_strict_mir(source), 18)
}

///|
async test "strict MIR codegen matches parser codegen for stack-passed floating variadic libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_stack_floating_variadic_libcall_source(),
    "strict_mir_stack_floating_variadic_libcall_differential",
  )
  assert_eq(result.code, 18)
}

///|
fn strict_mir_stack_integer_variadic_libcall_source() -> String {
  let source =
    #|int main(void) {
    #|  char buf[32];
    #|  int n = __builtin___snprintf_chk(buf, 32, 0, 32, "%d%d%d%d%d%d", 1, 2, 3, 4, 5, 6);
    #|  return n + (buf[0] == '1') + (buf[1] == '2') + (buf[2] == '3') + (buf[3] == '4') + (buf[4] == '5') + (buf[5] == '6');
    #|}
  source
}

///|
test "strict MIR codegen executes stack-passed integer variadic libcalls" {
  let source = strict_mir_stack_integer_variadic_libcall_source()
  assert_eq(run_source_strict_mir(source), 12)
}

///|
async test "strict MIR codegen matches parser codegen for stack-passed integer variadic libcalls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_stack_integer_variadic_libcall_source(),
    "strict_mir_stack_integer_variadic_libcall_differential",
  )
  assert_eq(result.code, 12)
}

///|
fn strict_mir_declared_mixed_variadic_snprintf_source() -> String {
  let source =
    #|int snprintf(char *buf, unsigned long n, const char *fmt, ...);
    #|int strcmp(const char *s1, const char *s2);
    #|int main(void) {
    #|  char buf[64];
    #|  int n = snprintf(buf, 64, "int=%d double=%.2f", 42, 3.14);
    #|  if (n != 18) return 1;
    #|  if (strcmp(buf, "int=42 double=3.14") != 0) return 2;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes declared mixed variadic snprintf" {
  let source = strict_mir_declared_mixed_variadic_snprintf_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for declared mixed variadic snprintf" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_declared_mixed_variadic_snprintf_source(),
    "strict_mir_declared_mixed_variadic_snprintf_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_checked_printf_side_effect_source() -> String {
  let source =
    #|int main(void) {
    #|  char buf[32];
    #|  int side = 0;
    #|  int n = __builtin___snprintf_chk(buf, 32, side += 1, side += 2, "%d", 42);
    #|  if (n != 2) return 1;
    #|  if (side != 3) return 2;
    #|  if (buf[0] != '4' || buf[1] != '2' || buf[2] != 0) return 3;
    #|  n = __builtin___sprintf_chk(buf, side += 4, side += 8, "%s", "ok");
    #|  if (n != 2) return 4;
    #|  if (side != 15) return 5;
    #|  if (buf[0] != 'o' || buf[1] != 'k' || buf[2] != 0) return 6;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes checked printf libcall side effects" {
  let source = strict_mir_checked_printf_side_effect_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for checked printf libcall side effects" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_checked_printf_side_effect_source(),
    "strict_mir_checked_printf_side_effect_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_plain_printf_builtin_source() -> String {
  let source =
    #|int main(void) {
    #|  char buf[64];
    #|  int n = __builtin_snprintf(buf, 64, "%s:%05d", "go", 7);
    #|  if (n != 8) return 1;
    #|  if (__builtin_strcmp(buf, "go:00007") != 0) return 2;
    #|  int count = 0;
    #|  int m = __builtin_sprintf(buf, "%#x|%n%s", 42, &count, "ok");
    #|  if (m != 7 || count != 5) return 3;
    #|  int p = __builtin_printf("%s|%d|%d|%d\n", buf, n, count, m);
    #|  if (p != 14) return 4;
    #|  return 42;
    #|}
  source
}

///|
fn strict_mir_plain_vprintf_builtin_source() -> String {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int write_plain(char *dst, const char *fmt, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, fmt);
    #|  int n = __builtin_vsnprintf(dst, 32, fmt, ap);
    #|  __builtin_va_end(ap);
    #|  return n;
    #|}
    #|int write_plain_sprintf(char *dst, const char *fmt, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, fmt);
    #|  int n = __builtin_vsprintf(dst, fmt, ap);
    #|  __builtin_va_end(ap);
    #|  return n;
    #|}
    #|int count_plain(const char *fmt, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, fmt);
    #|  int n = __builtin_vprintf(fmt, ap);
    #|  __builtin_va_end(ap);
    #|  return n;
    #|}
    #|int main(void) {
    #|  char dst[32];
    #|  int n = write_plain(dst, "%s:%04d", "ok", 7);
    #|  if (n != 7) return 1;
    #|  if (__builtin_strcmp(dst, "ok:0007") != 0) return 2;
    #|  int m = write_plain_sprintf(dst, "%#x", 42);
    #|  if (m != 4) return 3;
    #|  if (__builtin_strcmp(dst, "0x2a") != 0) return 4;
    #|  int p = count_plain(":%d", 42);
    #|  if (p != 3) return 5;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes plain printf builtins" {
  assert_eq(run_source_strict_mir(strict_mir_plain_printf_builtin_source()), 42)
}

///|
async test "strict MIR codegen matches parser codegen for plain printf builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_plain_printf_builtin_source(),
    "strict_mir_plain_printf_builtin_differential",
  )
  assert_eq(result.code, 42)
  assert_true(result.output.contains("0x2a|ok|8|5|7"))
}

///|
test "strict MIR codegen executes plain vprintf builtins" {
  assert_eq(
    run_source_strict_mir(strict_mir_plain_vprintf_builtin_source()),
    42,
  )
}

///|
async test "strict MIR codegen matches parser codegen for plain vprintf builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_plain_vprintf_builtin_source(),
    "strict_mir_plain_vprintf_builtin_differential",
  )
  assert_eq(result.code, 42)
  assert_true(result.output.contains(":42"))
}

///|
fn strict_mir_checked_vsnprintf_va_list_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes checked vsnprintf va_list libcall" {
  let source = strict_mir_checked_vsnprintf_va_list_source()
  assert_eq(run_source_strict_mir(source), 10)
}

///|
async test "strict MIR codegen matches parser codegen for checked vsnprintf va_list libcall" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_checked_vsnprintf_va_list_source(),
    "strict_mir_checked_vsnprintf_va_list_differential",
  )
  assert_eq(result.code, 10)
}

///|
async test "strict MIR codegen matches parser codegen for checked printf formatting" {
  let source =
    #|extern int printf(const char *, ...);
    #|int main(void) {
    #|  char buf[128];
    #|  int count = 0;
    #|  short short_count = 0;
    #|  signed char tiny_count = 0;
    #|  int n = __builtin___snprintf_chk(buf, 128, 0, 128, "%+05d|%-4s|%#x|%p|%n|%hn|%hhn", 7, "xy", 31, (void *)0, &count, &short_count, &tiny_count);
    #|  printf("%s|%d|%d|%d|%d\n", buf, n, count, short_count, tiny_count);
    #|  return (n + count + short_count + tiny_count) & 255;
    #|}
  let result = run_source_strict_mir_against_parser_codegen(
    source, "strict_mir_checked_printf_differential",
  )
  assert_true(result.output.contains("+0007|xy  |0x1f|"))
}

///|
async test "strict MIR codegen matches parser codegen for declared printf formatting" {
  let source =
    #|typedef unsigned long size_t;
    #|extern int snprintf(char *, size_t, const char *, ...);
    #|extern int sprintf(char *, const char *, ...);
    #|extern int printf(const char *, ...);
    #|int main(void) {
    #|  char buf[64];
    #|  int n = snprintf(buf, 64, "%s:%05d", "go", 7);
    #|  if (n != 8) return 1;
    #|  int count = 0;
    #|  int m = sprintf(buf, "%#x|%n%s", 42, &count, "ok");
    #|  if (m != 7 || count != 5) return 2;
    #|  printf("%s|%d|%d|%d\n", buf, n, count, m);
    #|  return 42;
    #|}
  let result = run_source_strict_mir_against_parser_codegen(
    source, "strict_mir_declared_printf_differential",
  )
  assert_eq(result.code, 42)
  assert_true(result.output.contains("0x2a|ok|8|5|7"))
}

///|
async test "strict MIR codegen matches parser codegen for checked vprintf formatting" {
  let source =
    #|extern int printf(const char *, ...);
    #|typedef __builtin_va_list va_list;
    #|int write_fmt(char *buf, unsigned long size, const char *fmt, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, fmt);
    #|  int n = __builtin___vsnprintf_chk(buf, size, 0, size, fmt, ap);
    #|  __builtin_va_end(ap);
    #|  return n;
    #|}
    #|int main(void) {
    #|  char buf[80];
    #|  int n = write_fmt(buf, 80, "%*.*s:%#x:%c:%d", 5, 3, "abcdef", 31, '!', -7);
    #|  printf("%s|%d\n", buf, n);
    #|  return (n + buf[0] + buf[4]) & 255;
    #|}
  let result = run_source_strict_mir_against_parser_codegen(
    source, "strict_mir_checked_vprintf_differential",
  )
  assert_true(result.output.contains("  abc:0x1f:!:-7|"))
}

///|
async test "strict MIR codegen matches parser codegen for checked floating printf formatting" {
  let source =
    #|extern int printf(const char *, ...);
    #|int main(void) {
    #|  char buf[80];
    #|  int n = __builtin___snprintf_chk(buf, 80, 0, 80, "%+.1f|% 6.2f|%05.0f", 1.5, 2.0, 3.0);
    #|  printf("%s|%d\n", buf, n);
    #|  return (n + buf[0] + buf[5]) & 255;
    #|}
  let result = run_source_strict_mir_against_parser_codegen(
    source, "strict_mir_checked_floating_printf_differential",
  )
  assert_true(result.output.contains("+1.5|  2.00|00003|17"))
}

///|
async test "strict MIR codegen matches parser codegen for checked scientific printf formatting" {
  let source =
    #|extern int printf(const char *, ...);
    #|int main(void) {
    #|  char buf[80];
    #|  int n = __builtin___snprintf_chk(buf, 80, 0, 80, "%+.2e|% 8.1E|%05.0e", 123.0, 0.012, 9.9);
    #|  printf("%s|%d\n", buf, n);
    #|  return (n + buf[0] + buf[10]) & 255;
    #|}
  let result = run_source_strict_mir_against_parser_codegen(
    source, "strict_mir_checked_scientific_printf_differential",
  )
  assert_true(result.output.contains("+1.23e+02| 1.2E-02|1e+01|24"))
}

///|
fn strict_mir_scalar_va_arg_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes scalar va_arg reads" {
  let source = strict_mir_scalar_va_arg_source()
  assert_eq(run_source_strict_mir(source), 37)
}

///|
async test "strict MIR codegen matches parser codegen for scalar va_arg reads" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_scalar_va_arg_source(),
    "strict_mir_scalar_va_arg_differential",
  )
  assert_eq(result.code, 37)
}

///|
fn strict_mir_int128_va_arg_source() -> String {
  let source =
    #|typedef __builtin_va_list va_list;
    #|typedef __int128 i128;
    #|long read128(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  i128 v = __builtin_va_arg(ap, i128);
    #|  __builtin_va_end(ap);
    #|  return tag + (long)v + (long)(v >> 64);
    #|}
    #|int main(void) {
    #|  i128 v = ((i128)5 << 64) | 7;
    #|  long (*fp)(int, ...) = read128;
    #|  if (read128(30, v) != 42) return 1;
    #|  return (int)fp(30, v);
    #|}
  source
}

///|
test "strict MIR codegen executes int128 va_arg reads" {
  let source = strict_mir_int128_va_arg_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for int128 va_arg reads" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_int128_va_arg_source(),
    "strict_mir_int128_va_arg_differential",
  )
  assert_eq(result.code, 42)
}

///|
test "strict MIR codegen emits linux x64 int128 va_arg reads" {
  let source = strict_mir_int128_va_arg_source()
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("linux target did not parse")
  }
  let assembly = compile_strict_mir_for_target(source, target)
  assert_true(assembly.contains("\tadd\tDWORD PTR [r11], 16"))
  assert_true(assembly.contains("\tand\tr10, -16"))
}

///|
fn strict_mir_va_copy_source() -> String {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int copy_variadic(int tag, ...) {
    #|  va_list ap;
    #|  va_list copy;
    #|  __builtin_va_start(ap, tag);
    #|  __builtin_va_copy(copy, ap);
    #|  int first = __builtin_va_arg(ap, int);
    #|  int copied = __builtin_va_arg(copy, int);
    #|  __builtin_va_end(copy);
    #|  __builtin_va_end(ap);
    #|  return first + copied;
    #|}
    #|int main(void) {
    #|  return copy_variadic(0, 21);
    #|}
  source
}

///|
test "strict MIR codegen executes va_copy" {
  let source = strict_mir_va_copy_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for va_copy" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_va_copy_source(),
    "strict_mir_va_copy_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_va_arg_pointer_store_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes stores through va_arg pointers" {
  let source = strict_mir_va_arg_pointer_store_source()
  assert_eq(run_source_strict_mir(source), 37)
}

///|
async test "strict MIR codegen matches parser codegen for stores through va_arg pointers" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_va_arg_pointer_store_source(),
    "strict_mir_va_arg_pointer_store_differential",
  )
  assert_eq(result.code, 37)
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
fn strict_mir_aggregate_va_arg_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes aggregate va_arg reads from MIR caller" {
  let source = strict_mir_aggregate_va_arg_source()
  assert_eq(run_source_strict_mir(source), 34)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate va_arg reads" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_va_arg_source(),
    "strict_mir_aggregate_va_arg_differential",
  )
  assert_eq(result.code, 34)
}

///|
test "strict MIR codegen passes aggregate variadic args to clang callees" {
  let caller =
    #|struct Pair { long long a; long long b; };
    #|int read_pair(int tag, ...);
    #|int main(void) {
    #|  struct Pair p = {10, 20};
    #|  return read_pair(4, p);
    #|}
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
  assert_eq(run_strict_mir_with_clang_driver(caller, callee), 34)
}

///|
fn strict_mir_large_aggregate_va_arg_source() -> String {
  let source =
    #|typedef __builtin_va_list va_list;
    #|struct Big { long long a; long long b; long long c; };
    #|int read_big(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  struct Big p = __builtin_va_arg(ap, struct Big);
    #|  __builtin_va_end(ap);
    #|  return tag + (int)p.a + (int)p.c;
    #|}
    #|int main(void) {
    #|  struct Big p = {10, 20, 25};
    #|  return read_big(7, p);
    #|}
  source
}

///|
test "strict MIR codegen executes large aggregate va_arg reads" {
  let source = strict_mir_large_aggregate_va_arg_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for large aggregate va_arg reads" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_large_aggregate_va_arg_source(),
    "strict_mir_large_aggregate_va_arg_differential",
  )
  assert_eq(result.code, 42)
}

///|
test "strict MIR codegen executes large aggregate va_arg reads from clang caller" {
  let callee =
    #|typedef __builtin_va_list va_list;
    #|struct Big { long long a; long long b; long long c; };
    #|int read_big(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  struct Big p = __builtin_va_arg(ap, struct Big);
    #|  __builtin_va_end(ap);
    #|  return tag + (int)p.a + (int)p.c;
    #|}
  let driver =
    #|struct Big { long long a; long long b; long long c; };
    #|int read_big(int tag, ...);
    #|int main(void) {
    #|  struct Big p = {10, 20, 25};
    #|  return read_big(7, p);
    #|}
  assert_eq(run_strict_mir_with_clang_driver(callee, driver), 42)
}

///|
test "strict MIR codegen passes large aggregate variadic args to clang callees" {
  let caller =
    #|struct Big { long long a; long long b; long long c; };
    #|int read_big(int tag, ...);
    #|int main(void) {
    #|  struct Big p = {10, 20, 25};
    #|  return read_big(7, p);
    #|}
  let callee =
    #|typedef __builtin_va_list va_list;
    #|struct Big { long long a; long long b; long long c; };
    #|int read_big(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  struct Big p = __builtin_va_arg(ap, struct Big);
    #|  __builtin_va_end(ap);
    #|  return tag + (int)p.a + (int)p.c;
    #|}
  assert_eq(run_strict_mir_with_clang_driver(caller, callee), 42)
}

///|
fn strict_mir_indirect_large_aggregate_va_arg_source() -> String {
  let source =
    #|typedef __builtin_va_list va_list;
    #|struct Big { long long a; long long b; long long c; };
    #|int read_big(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  struct Big p = __builtin_va_arg(ap, struct Big);
    #|  __builtin_va_end(ap);
    #|  return tag + (int)p.a + (int)p.c;
    #|}
    #|int main(void) {
    #|  struct Big p = {11, 20, 27};
    #|  int (*fp)(int, ...) = read_big;
    #|  return fp(4, p);
    #|}
  source
}

///|
test "strict MIR codegen executes indirect large aggregate va_arg reads" {
  let source = strict_mir_indirect_large_aggregate_va_arg_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for indirect large aggregate va_arg reads" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_indirect_large_aggregate_va_arg_source(),
    "strict_mir_indirect_large_aggregate_va_arg_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aggregate_va_arg_member_source() -> String {
  let source =
    #|typedef __builtin_va_list va_list;
    #|struct Pair { int a; int b; };
    #|int pick(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  int value = __builtin_va_arg(ap, struct Pair).b;
    #|  __builtin_va_end(ap);
    #|  return tag + value;
    #|}
    #|int main(void) {
    #|  struct Pair p = {10, 32};
    #|  return pick(10, p);
    #|}
  source
}

///|
test "strict MIR codegen reads members from aggregate va_arg rvalues" {
  let source = strict_mir_aggregate_va_arg_member_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate va_arg member reads" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_va_arg_member_source(),
    "strict_mir_aggregate_va_arg_member_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_long_double_scalar_source() -> String {
  let source =
    #|int main(void) {
    #|  long double a = 1.0L;
    #|  long double b = 2.0L;
    #|  long double d = 0 ? a : b;
    #|  d = d + 40.0L;
    #|  return (int)d;
    #|}
  source
}

///|
test "strict MIR codegen executes Darwin long double scalar ops" {
  assert_eq(run_source_strict_mir(strict_mir_long_double_scalar_source()), 42)
}

///|
async test "strict MIR codegen matches parser codegen for Darwin long double scalar ops" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_long_double_scalar_source(),
    "strict_mir_long_double_scalar_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_global_address_cancellation_load_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes loads through global address cancellation" {
  let source = strict_mir_global_address_cancellation_load_source()
  assert_eq(run_source_strict_mir(source), 9)
}

///|
async test "strict MIR codegen matches parser codegen for global address cancellation loads" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_global_address_cancellation_load_source(),
    "strict_mir_global_address_cancellation_load_differential",
  )
  assert_eq(result.code, 9)
}

///|
fn strict_mir_tinycc_style_aggregate_copy_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes TinyCC-style aggregate copies" {
  let source = strict_mir_tinycc_style_aggregate_copy_source()
  assert_eq(run_source_strict_mir(source), 30)
}

///|
async test "strict MIR codegen matches parser codegen for TinyCC-style aggregate copies" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_tinycc_style_aggregate_copy_source(),
    "strict_mir_tinycc_style_aggregate_copy_differential",
  )
  assert_eq(result.code, 30)
}

///|
fn strict_mir_comma_aggregate_assignment_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes comma aggregate assignments" {
  let source = strict_mir_comma_aggregate_assignment_source()
  assert_eq(run_source_strict_mir(source), 21)
}

///|
async test "strict MIR codegen matches parser codegen for comma aggregate assignments" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_comma_aggregate_assignment_source(),
    "strict_mir_comma_aggregate_assignment_differential",
  )
  assert_eq(result.code, 21)
}

///|
fn strict_mir_aggregate_assignment_rvalue_member_read_source() -> String {
  let source =
    #|struct S { int x; int y; };
    #|int main(void) {
    #|  struct S lhs = { 1, 2 };
    #|  struct S rhs = { 19, 23 };
    #|  return (lhs = rhs).y + lhs.x;
    #|}
  source
}

///|
test "strict MIR codegen executes aggregate assignment rvalue member reads" {
  let source = strict_mir_aggregate_assignment_rvalue_member_read_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate assignment rvalue member reads" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_assignment_rvalue_member_read_source(),
    "strict_mir_aggregate_assignment_rvalue_member_read_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_local_aggregate_array_assignment_rvalue_source() -> String {
  let source =
    #|struct S { int x; int y; };
    #|int main(void) {
    #|  struct S slots[2];
    #|  struct S rhs = { 19, 23 };
    #|  int i = 0;
    #|  int value = (slots[i++] = rhs).y;
    #|  if (i != 1) return 1;
    #|  return value + slots[0].x;
    #|}
  source
}

///|
test "strict MIR codegen executes local aggregate array assignment rvalues" {
  let source = strict_mir_local_aggregate_array_assignment_rvalue_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for local aggregate array assignment rvalues" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_local_aggregate_array_assignment_rvalue_source(),
    "strict_mir_local_aggregate_array_assignment_rvalue_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aggregate_assignment_ternary_call_rvalue_source() -> String {
  let source =
    #|struct Box { int a; int b; };
    #|int side;
    #|struct Box make(int tag) {
    #|  struct Box box;
    #|  box.a = tag;
    #|  box.b = 42 - tag;
    #|  side = side * 10 + tag;
    #|  return box;
    #|}
    #|int pick_false(void) {
    #|  struct Box slots[2];
    #|  int i = 0;
    #|  int cond = 0;
    #|  side = 0;
    #|  int value = (slots[i++] = cond ? make(1) : make(2)).a;
    #|  if (i != 1) return 10 + i;
    #|  if (side != 2) return side;
    #|  if (slots[0].b != 40) return slots[0].b;
    #|  return value + 40;
    #|}
    #|int pick_true(void) {
    #|  struct Box slots[2];
    #|  int i = 0;
    #|  int cond = 1;
    #|  side = 0;
    #|  int value = (slots[i++] = cond ? make(3) : make(4)).a;
    #|  if (i != 1) return 20 + i;
    #|  if (side != 3) return side;
    #|  if (slots[0].b != 39) return slots[0].b;
    #|  return value + 39;
    #|}
    #|int main(void) {
    #|  if (pick_false() != 42) return 1;
    #|  if (pick_true() != 42) return 2;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes aggregate assignment ternary call rvalues" {
  let source = strict_mir_aggregate_assignment_ternary_call_rvalue_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate assignment ternary call rvalues" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_assignment_ternary_call_rvalue_source(),
    "strict_mir_aggregate_assignment_ternary_call_rvalue_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_bitfield_compound_update_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes bitfield compound updates" {
  let source = strict_mir_bitfield_compound_update_source()
  assert_eq(run_source_strict_mir(source), 3)
}

///|
async test "strict MIR codegen matches parser codegen for bitfield compound updates" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_bitfield_compound_update_source(),
    "strict_mir_bitfield_compound_update_differential",
  )
  assert_eq(result.code, 3)
}

///|
fn strict_mir_floating_comma_store_source() -> String {
  let source =
    #|union U { float f; unsigned u; };
    #|int main(void) {
    #|  union U x1, x2;
    #|  x1.f = 1.0f, x2.f = -0.0f;
    #|  return (x1.u == 0x3f800000u) + (x2.u == 0x80000000u);
    #|}
  source
}

///|
test "strict MIR codegen executes floating comma stores" {
  let source = strict_mir_floating_comma_store_source()
  assert_eq(run_source_strict_mir(source), 2)
}

///|
async test "strict MIR codegen matches parser codegen for floating comma stores" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_comma_store_source(),
    "strict_mir_floating_comma_store_differential",
  )
  assert_eq(result.code, 2)
}

///|
fn strict_mir_floating_fabs_infinity_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes floating fabs and infinity builtins" {
  let source = strict_mir_floating_fabs_infinity_source()
  assert_eq(run_source_strict_mir(source), 5)
}

///|
async test "strict MIR codegen matches parser codegen for floating fabs and infinity builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_fabs_infinity_source(),
    "strict_mir_floating_fabs_infinity_differential",
  )
  assert_eq(result.code, 5)
}

///|
fn strict_mir_long_double_fabs_infinity_source() -> String {
  let source =
    #|int finitel(long double x) {
    #|  return x == x && __builtin_fabsl(x) != __builtin_infl();
    #|}
    #|int main(void) {
    #|  return finitel(-5.5L) + 2 * finitel(__builtin_infl());
    #|}
  source
}

///|
test "strict MIR codegen executes long double fabs and infinity builtins" {
  let source = strict_mir_long_double_fabs_infinity_source()
  assert_eq(run_source_strict_mir(source), 1)
}

///|
async test "strict MIR codegen matches parser codegen for long double fabs and infinity builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_long_double_fabs_infinity_source(),
    "strict_mir_long_double_fabs_infinity_differential",
  )
  assert_eq(result.code, 1)
}

///|
fn strict_mir_floating_comparison_builtin_source() -> String {
  let source =
    #|int main(void) {
    #|  double x = 3.0;
    #|  double y = 2.0;
    #|  double z = 3.0;
    #|  double zero = 0.0;
    #|  double nanv = zero / zero;
    #|  int side = 0;
    #|  if (!__builtin_isgreater(x, y)) return 1;
    #|  if (!__builtin_isgreaterequal(x, z)) return 2;
    #|  if (!__builtin_isless(y, x)) return 3;
    #|  if (!__builtin_islessequal(z, x)) return 4;
    #|  if (!__builtin_islessgreater(y, x)) return 5;
    #|  if (__builtin_islessgreater(x, z)) return 6;
    #|  if (__builtin_islessgreater(nanv, y)) return 7;
    #|  if (!__builtin_isunordered(nanv, y)) return 8;
    #|  if (__builtin_isunordered(x, y)) return 9;
    #|  if (!__builtin_isless((side += 1, y), x)) return 10;
    #|  if (side != 1) return 11;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes runtime floating comparison builtins" {
  let source = strict_mir_floating_comparison_builtin_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for runtime floating comparison builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_comparison_builtin_source(),
    "strict_mir_floating_comparison_builtin_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_floating_classification_builtin_source() -> String {
  let source =
    #|int main(void) {
    #|  double zero = 0.0;
    #|  double one = 1.0;
    #|  double four = 4.0;
    #|  double nanv = zero / zero;
    #|  double inf = one / zero;
    #|  double ninf = zero - inf;
    #|  double neg = zero - four;
    #|  float fzero = 0.0f;
    #|  float fone = 1.0f;
    #|  float ffour = 4.0f;
    #|  float fnan = fzero / fzero;
    #|  float finf = fone / fzero;
    #|  float fneg = fzero - ffour;
    #|  int side = 0;
    #|  if (!__builtin_isnan(nanv)) return 1;
    #|  if (__builtin_isnan(four)) return 2;
    #|  if (!__builtin_isinf(inf)) return 3;
    #|  if (!__builtin_isinf(ninf)) return 4;
    #|  if (!__builtin_isfinite(four)) return 5;
    #|  if (__builtin_isfinite(inf)) return 6;
    #|  if (!__builtin_isnormal(four)) return 7;
    #|  if (__builtin_isnormal(zero)) return 8;
    #|  if (!__builtin_signbit(neg)) return 9;
    #|  if (__builtin_signbit(four)) return 10;
    #|  if (!__builtin_isnanf(fnan)) return 11;
    #|  if (!__builtin_isinff(finf)) return 12;
    #|  if (!__builtin_isfinitef(ffour)) return 13;
    #|  if (!__builtin_isnormalf(ffour)) return 14;
    #|  if (!__builtin_signbitf(fneg)) return 15;
    #|  if (!__builtin_isfinite((side += 1, four))) return 16;
    #|  if (side != 1) return 17;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes runtime floating classification builtins" {
  let source = strict_mir_floating_classification_builtin_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for runtime floating classification builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_classification_builtin_source(),
    "strict_mir_floating_classification_builtin_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_floating_math_builtin_source() -> String {
  let source =
    #|int main(void) {
    #|  double zero = 0.0;
    #|  double one = 1.0;
    #|  double nine = 9.0;
    #|  double mag = 5.0;
    #|  double neg = zero - one;
    #|  float fzero = 0.0f;
    #|  float fone = 1.0f;
    #|  float fnine = 9.0f;
    #|  float fmag = 4.0f;
    #|  float fneg = fzero - fone;
    #|  int side = 0;
    #|  if ((int)__builtin_sqrt(nine) != 3) return 1;
    #|  if ((int)__builtin_sqrtf(fnine) != 3) return 2;
    #|  if (!__builtin_isnan(__builtin_sqrt(neg))) return 3;
    #|  if ((int)__builtin_copysign(mag, neg) != -5) return 4;
    #|  if ((int)__builtin_copysign(zero - mag, one) != 5) return 5;
    #|  if ((int)__builtin_copysignf(fmag, fneg) != -4) return 6;
    #|  if ((int)__builtin_copysignf(fzero - fmag, fone) != 4) return 7;
    #|  if ((int)__builtin_sqrt((side += 1, nine)) != 3) return 8;
    #|  if ((int)__builtin_copysign((side += 2, mag), (side += 4, neg)) != -5) return 9;
    #|  if (side != 7) return 10;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes runtime floating math builtins" {
  let source = strict_mir_floating_math_builtin_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for runtime floating math builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_floating_math_builtin_source(),
    "strict_mir_floating_math_builtin_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_count_zero_builtin_source() -> String {
  let source =
    #|typedef unsigned long long uint64_t;
    #|static inline int clz32(unsigned int a) { return __builtin_clz(a); }
    #|static inline int clz64(uint64_t a) { return __builtin_clzll(a); }
    #|static inline int ctz32(unsigned int a) { return __builtin_ctz(a); }
    #|static inline int ctz64(uint64_t a) { return __builtin_ctzll(a); }
    #|int main(void) {
    #|  return clz32(1u) + clz64(1ull) + ctz32(8u) + ctz64(16ull);
    #|}
  source
}

///|
test "strict MIR codegen executes count zero builtins" {
  let source = strict_mir_count_zero_builtin_source()
  assert_eq(run_source_strict_mir(source), 101)
}

///|
async test "strict MIR codegen matches parser codegen for count zero builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_count_zero_builtin_source(),
    "strict_mir_count_zero_builtin_differential",
  )
  assert_eq(result.code, 101)
}

///|
fn strict_mir_integer_unary_builtin_source() -> String {
  let source =
    #|int main(void) {
    #|  int neg = -7;
    #|  int pos = 5;
    #|  long lneg = -1234567890123L;
    #|  long long llneg = -900000000000000000LL;
    #|  unsigned int u8 = 8u;
    #|  unsigned long ul16 = 16ul;
    #|  unsigned long long ull32 = 32ull;
    #|  unsigned int u0102 = 0x0102u;
    #|  unsigned int u01020304 = 0x01020304u;
    #|  unsigned long long ullswap = 0x0102030405060708ull;
    #|  unsigned int upop = 0x00ff00ffu;
    #|  unsigned long ulpop = 0x00000000fffffffful;
    #|  unsigned long long ullpar = 0x8000000000000001ull;
    #|  if (__builtin_abs(neg) != 7) return 1;
    #|  if (__builtin_abs(pos) != 5) return 2;
    #|  if (__builtin_labs(lneg) != 1234567890123L) return 3;
    #|  if (__builtin_llabs(llneg) != 900000000000000000LL) return 4;
    #|  if (__builtin_ffs(0u) != 0) return 5;
    #|  if (__builtin_ffs(u8) != 4) return 6;
    #|  if (__builtin_ffsl(ul16) != 5) return 7;
    #|  if (__builtin_ffsll(ull32) != 6) return 8;
    #|  if ((__builtin_bswap16(u0102) & 255) != 1) return 9;
    #|  if ((__builtin_bswap32(u01020304) & 255) != 1) return 10;
    #|  if ((__builtin_bswap64(ullswap) & 255) != 1) return 11;
    #|  if ((__builtin_bswap(u01020304) & 255) != 1) return 12;
    #|  if ((__builtin_bswap(ullswap) & 255) != 1) return 13;
    #|  if (__builtin_popcount(upop) != 16) return 14;
    #|  if (__builtin_popcountl(ulpop) != 32) return 15;
    #|  if (__builtin_popcountll(ullswap) != 13) return 16;
    #|  if (__builtin_popcountll(ullpar) != 2) return 17;
    #|  if (__builtin_parity(upop) != 0) return 18;
    #|  if (__builtin_parityl(ulpop) != 0) return 19;
    #|  if (__builtin_parityll(ullpar) != 0) return 20;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes integer unary builtins" {
  let source = strict_mir_integer_unary_builtin_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for integer unary builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_integer_unary_builtin_source(),
    "strict_mir_integer_unary_builtin_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_rotate_builtin_source() -> String {
  let source =
    #|static unsigned int rl32(unsigned int x, int s) { return __builtin_rotateleft32(x, s); }
    #|static unsigned int rr32(unsigned int x, int s) { return __builtin_rotateright32(x, s); }
    #|static unsigned long long rl64(unsigned long long x, int s) { return __builtin_rotateleft64(x, s); }
    #|static unsigned long long rr64(unsigned long long x, int s) { return __builtin_rotateright64(x, s); }
    #|int main(void) {
    #|  int n = 8;
    #|  int side = 0;
    #|  if (rl32(0x12345678u, n) != 0x34567812u) return 1;
    #|  if (rr32(0x12345678u, 12) != 0x67812345u) return 2;
    #|  if (rl64(0x0123456789abcdefull, 16) != 0x456789abcdef0123ull) return 3;
    #|  if (rr64(0x0123456789abcdefull, 16) != 0xcdef0123456789abull) return 4;
    #|  if (__builtin_rotateleft((unsigned int)0x80000001u, 1) != 3u) return 5;
    #|  if (__builtin_rotateright((unsigned long long)1ull, 1) != 0x8000000000000000ull) return 6;
    #|  if (__builtin_rotateleft32((side += 1, 0x12345678u), (side += 2, n)) != 0x34567812u) return 7;
    #|  if (side != 3) return 8;
    #|  return 42;
    #|}
  source
}

///|
test "strict MIR codegen executes rotate builtins" {
  let source = strict_mir_rotate_builtin_source()
  assert_eq(run_source_strict_mir(source), 42)
}

///|
async test "strict MIR codegen matches parser codegen for rotate builtins" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_rotate_builtin_source(),
    "strict_mir_rotate_builtin_differential",
  )
  assert_eq(result.code, 42)
}

///|
fn strict_mir_aggregate_compound_literal_return_source() -> String {
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
  source
}

///|
test "strict MIR codegen returns aggregate compound literals" {
  let source = strict_mir_aggregate_compound_literal_return_source()
  assert_eq(run_source_strict_mir(source), 11)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate compound literal returns" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_compound_literal_return_source(),
    "strict_mir_aggregate_compound_literal_return_differential",
  )
  assert_eq(result.code, 11)
}

///|
fn strict_mir_identity_cast_aggregate_return_source() -> String {
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
  source
}

///|
test "strict MIR codegen returns identity-cast aggregate arguments" {
  let source = strict_mir_identity_cast_aggregate_return_source()
  assert_eq(run_source_strict_mir(source), 7)
}

///|
async test "strict MIR codegen matches parser codegen for identity-cast aggregate returns" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_identity_cast_aggregate_return_source(),
    "strict_mir_identity_cast_aggregate_return_differential",
  )
  assert_eq(result.code, 7)
}

///|
fn strict_mir_typedef_function_pointer_aggregate_return_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes typedef function pointer aggregate returns" {
  let source = strict_mir_typedef_function_pointer_aggregate_return_source()
  assert_eq(run_source_strict_mir(source), 9)
}

///|
async test "strict MIR codegen matches parser codegen for typedef function pointer aggregate returns" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_typedef_function_pointer_aggregate_return_source(),
    "strict_mir_typedef_function_pointer_aggregate_return_differential",
  )
  assert_eq(result.code, 9)
}

///|
fn strict_mir_aggregate_compound_literal_argument_source() -> String {
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
  source
}

///|
test "strict MIR codegen passes aggregate compound literal arguments" {
  let source = strict_mir_aggregate_compound_literal_argument_source()
  assert_eq(run_source_strict_mir(source), 24)
}

///|
fn strict_mir_bitfield_post_increment_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes bitfield post increment" {
  let source = strict_mir_bitfield_post_increment_source()
  assert_eq(run_source_strict_mir(source), 12)
}

///|
async test "strict MIR codegen matches parser codegen for bitfield post increment" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_bitfield_post_increment_source(),
    "strict_mir_bitfield_post_increment_differential",
  )
  assert_eq(result.code, 12)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate compound literal arguments" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_compound_literal_argument_source(),
    "strict_mir_aggregate_compound_literal_argument_differential",
  )
  assert_eq(result.code, 24)
}

///|
fn strict_mir_aggregate_call_result_field_source() -> String {
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
  source
}

///|
test "strict MIR codegen reads fields from aggregate call results" {
  let source = strict_mir_aggregate_call_result_field_source()
  assert_eq(run_source_strict_mir(source), 8)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate call result fields" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_call_result_field_source(),
    "strict_mir_aggregate_call_result_field_differential",
  )
  assert_eq(result.code, 8)
}

///|
fn strict_mir_aggregate_member_return_source() -> String {
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
  source
}

///|
test "strict MIR codegen returns aggregate members" {
  let source = strict_mir_aggregate_member_return_source()
  assert_eq(run_source_strict_mir(source), 10)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate member returns" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_member_return_source(),
    "strict_mir_aggregate_member_return_differential",
  )
  assert_eq(result.code, 10)
}

///|
fn strict_mir_identity_cast_aggregate_argument_source() -> String {
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
  source
}

///|
test "strict MIR codegen passes identity-cast aggregate arguments" {
  let source = strict_mir_identity_cast_aggregate_argument_source()
  assert_eq(run_source_strict_mir(source), 13)
}

///|
async test "strict MIR codegen matches parser codegen for identity-cast aggregate arguments" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_identity_cast_aggregate_argument_source(),
    "strict_mir_identity_cast_aggregate_argument_differential",
  )
  assert_eq(result.code, 13)
}

///|
fn strict_mir_function_typedef_pointer_call_source() -> String {
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
  source
}

///|
test "strict MIR codegen executes function typedef pointer calls" {
  let source = strict_mir_function_typedef_pointer_call_source()
  assert_eq(run_source_strict_mir(source), 12)
}

///|
async test "strict MIR codegen matches parser codegen for function typedef pointer calls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_function_typedef_pointer_call_source(),
    "strict_mir_function_typedef_pointer_call_differential",
  )
  assert_eq(result.code, 12)
}

///|
fn strict_mir_dereferenced_function_typedef_pointer_call_source() -> String {
  let source =
    #|typedef int Callback(void *data, int value);
    #|int add(void *data, int value) {
    #|  return *(int*)data + value;
    #|}
    #|int main(void) {
    #|  int base = 5;
    #|  Callback *fp = add;
    #|  return (*fp)(&base, 7);
    #|}
  source
}

///|
test "strict MIR codegen executes dereferenced function typedef pointer calls" {
  let source = strict_mir_dereferenced_function_typedef_pointer_call_source()
  assert_eq(run_source_strict_mir(source), 12)
}

///|
async test "strict MIR codegen matches parser codegen for dereferenced function typedef pointer calls" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_dereferenced_function_typedef_pointer_call_source(),
    "strict_mir_dereferenced_function_typedef_pointer_call_differential",
  )
  assert_eq(result.code, 12)
}

///|
fn strict_mir_aggregate_return_call_source_once_source() -> String {
  let source =
    #|struct Pair { long a; long b; };
    #|int calls;
    #|struct Pair make_pair(void) {
    #|  calls++;
    #|  struct Pair p;
    #|  p.a = calls;
    #|  p.b = calls * 10;
    #|  return p;
    #|}
    #|struct Pair wrapper(void) {
    #|  struct Pair (*fp)(void) = make_pair;
    #|  return fp();
    #|}
    #|int main(void) {
    #|  struct Pair p = wrapper();
    #|  if (calls != 1) return 100 + calls;
    #|  return (int)(p.a + p.b);
    #|}
  source
}

///|
test "strict MIR codegen evaluates aggregate return call sources once" {
  let source = strict_mir_aggregate_return_call_source_once_source()
  assert_eq(run_source_strict_mir(source), 11)
}

///|
async test "strict MIR codegen matches parser codegen for aggregate return call source evaluation" {
  let result = run_source_strict_mir_against_parser_codegen(
    strict_mir_aggregate_return_call_source_once_source(),
    "strict_mir_aggregate_return_call_source_once_differential",
  )
  assert_eq(result.code, 11)
}
