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

///|
async test "compile struct fixture" {
  let source =
    #|struct Point {
    #|  int x;
    #|  int y;
    #|};
    #|int main() {
    #|  struct Point p;
    #|  p.x = 3;
    #|  p.y = 4;
    #|  return p.x + p.y;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "compile arrays fixture" {
  let source =
    #|int main() {
    #|  int a[5];
    #|  a[0] = 1;
    #|  a[1] = 2;
    #|  a[2] = a[0] + a[1];
    #|  return a[2];
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "compile logic fixture" {
  let source =
    #|int main() {
    #|  int a = 1;
    #|  int b = 0;
    #|  if (a && b) {
    #|    return 1;
    #|  }
    #|  if (a || b) {
    #|    return 2;
    #|  }
    #|  if (!b) {
    #|    return 3;
    #|  }
    #|  return 0;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "compile globals fixture" {
  let source =
    #|int counter = 0;
    #|int inc() {
    #|  counter = counter + 1;
    #|  return counter;
    #|}
    #|int main() {
    #|  inc();
    #|  inc();
    #|  return counter;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
  assert_true(assembly.contains("_counter:"))
  assert_true(assembly.contains("_inc:"))
}

///|
async test "compile loops fixture" {
  let source =
    #|int main() {
    #|  int sum = 0;
    #|  for (int i = 0; i < 5; i = i + 1) {
    #|    sum = sum + i;
    #|  }
    #|  int j = 0;
    #|  while (j < 3) {
    #|    j = j + 1;
    #|    if (j == 2) {
    #|      continue;
    #|    }
    #|    sum = sum + 10;
    #|  }
    #|  return sum;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "compile funcall fixture" {
  let source =
    #|int add(int a, int b) {
    #|  return a + b;
    #|}
    #|int mul(int a, int b) {
    #|  return a * b;
    #|}
    #|int main() {
    #|  return add(2, 3) + mul(4, 5);
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
  assert_true(assembly.contains("_add:"))
  assert_true(assembly.contains("_mul:"))
}

///|
async test "compile enum fixture" {
  let source =
    #|enum Color { Red, Green, Blue };
    #|int main() {
    #|  int c = Green;
    #|  return c + 1;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "compile bitwise fixture" {
  let source =
    #|int main() {
    #|  int a = 15;
    #|  int b = 240;
    #|  int r = (a & b) | (a ^ b);
    #|  r = r | (a << 2);
    #|  r = r | (b >> 4);
    #|  r = r | ~a;
    #|  return r;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "compile prepost incdec fixture" {
  let source =
    #|int main() {
    #|  int x = 5;
    #|  int a = ++x;
    #|  int b = x++;
    #|  int c = --x;
    #|  int d = x--;
    #|  return a + b + c + d;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "compile ternary fixture" {
  let source =
    #|int main() {
    #|  int a = 5;
    #|  int b = 3;
    #|  return a > b ? a * 2 : b * 2;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "compile sizeof fixture" {
  let source =
    #|int main() {
    #|  int x;
    #|  return sizeof(x) + sizeof(int);
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}
