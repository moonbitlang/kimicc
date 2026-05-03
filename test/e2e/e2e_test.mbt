///|
fn compile(source : String) -> String {
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  codegen.generate(prog)
}

///|
async test "compile hello fixture" {
  let source =
    #|int main() {
    #|  int a = 1;
    #|  int b = 2;
    #|  return a + b + 3;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
  assert_true(assembly.contains(".globl\t_main"))
}

///|
async test "compile var_decls fixture" {
  let source =
    #|int main() {
    #|  int a, b, c;
    #|  a = 10;
    #|  b = 20;
    #|  c = a + b;
    #|  if (c > 25) {
    #|    c = c * 2;
    #|  } else {
    #|    c = c - 5;
    #|  }
    #|  while (c > 0) {
    #|    c = c - 1;
    #|  }
    #|  return c + 100;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "compile switch fixture" {
  let source =
    #|int main() {
    #|  int x = 2;
    #|  switch (x) {
    #|    case 1: return 10;
    #|    case 2: return 20;
    #|    case 3: return 30;
    #|    default: return 0;
    #|  }
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "compile pointers fixture" {
  let source =
    #|int main() {
    #|  int x = 42;
    #|  int *p = &x;
    #|  *p = *p + 8;
    #|  return x;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "compile c4_stripped fixture" {
  let data = @fs.read_file("test/fixtures/c4_stripped.c")
  let source = data.text()
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
  assert_true(assembly.contains("_next:"))
  assert_true(assembly.contains("_expr:"))
  assert_true(assembly.contains("_stmt:"))
}
