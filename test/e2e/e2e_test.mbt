///|
#borrow(path, content)
extern "c" fn moonbit_write_file(path : Bytes, content : Bytes) -> Int = "moonbit_write_file"

///|
#borrow(cmd)
extern "c" fn moonbit_system(cmd : Bytes) -> Int = "moonbit_system"

///|
fn compile(source : String) -> String {
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  codegen.generate(prog)
}

///|
fn run_source(source : String) -> Int {
  let assembly = compile(source)
  let asm_path = "/tmp/kimicc_test.s"
  let bin_path = "/tmp/kimicc_test"
  let _ = moonbit_write_file(
    @utf8.encode(asm_path),
    @utf8.encode(assembly),
  )
  let link_rc = moonbit_system(@utf8.encode("clang -o " + bin_path + " " + asm_path))
  if link_rc != 0 {
    abort("Link failed with code: " + link_rc.to_string())
  }
  moonbit_system(@utf8.encode(bin_path))
}

///|
fn run_source_async(source : String) -> Int {
  run_source(source)
}

///|
async test "run hello fixture" {
  let source =
    #|int main() {
    #|  int a = 1;
    #|  int b = 2;
    #|  return a + b + 3;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="6")
}

///|
async test "run var_decls fixture" {
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
  let exit_code = run_source_async(source)
  inspect(exit_code, content="100")
}

///|
async test "run switch fixture" {
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
  let exit_code = run_source_async(source)
  inspect(exit_code, content="20")
}

///|
async test "run pointers fixture" {
  let source =
    #|int main() {
    #|  int x = 42;
    #|  int *p = &x;
    #|  *p = *p + 8;
    #|  return x;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="50")
}

///|
async test "run struct fixture" {
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
  let exit_code = run_source_async(source)
  inspect(exit_code, content="7")
}

///|
async test "run arrays fixture" {
  let source =
    #|int main() {
    #|  int a[5];
    #|  a[0] = 1;
    #|  a[1] = 2;
    #|  a[2] = a[0] + a[1];
    #|  return a[2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="3")
}

///|
async test "run logic fixture" {
  let source =
    #|int main() {
    #|  int a = 1;
    #|  int b = 0;
    #|  if (a && b) {
    #|    return 1;
    #|  }
    #|  if (a || b) {
    #|    if (!b) {
    #|      return 3;
    #|    }
    #|    return 2;
    #|  }
    #|  return 0;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="3")
}

///|
async test "run globals fixture" {
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
  let exit_code = run_source_async(source)
  inspect(exit_code, content="2")
}

///|
async test "run loops fixture" {
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
  let exit_code = run_source_async(source)
  inspect(exit_code, content="30")
}

///|
async test "run funcall fixture" {
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
  let exit_code = run_source_async(source)
  inspect(exit_code, content="25")
}

///|
async test "run enum fixture" {
  let source =
    #|enum Color { Red, Green, Blue };
    #|int main() {
    #|  int c = Green;
    #|  return c + 1;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="2")
}

///|
async test "run bitwise fixture" {
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
  let exit_code = run_source_async(source)
  inspect(exit_code, content="255")
}

///|
async test "run prepost incdec fixture" {
  let source =
    #|int main() {
    #|  int x = 5;
    #|  int a = ++x;
    #|  int b = x++;
    #|  int c = --x;
    #|  int d = x--;
    #|  return a + b + c + d;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="24")
}

///|
async test "run ternary fixture" {
  let source =
    #|int main() {
    #|  int a = 5;
    #|  int b = 3;
    #|  return a > b ? a * 2 : b * 2;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="10")
}

///|
async test "run sizeof fixture" {
  let source =
    #|int main() {
    #|  int x;
    #|  return sizeof(x) + sizeof(int);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="8")
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
async test "parse tinycc stripped" {
  let data = @fs.read_file("/tmp/tinycc_stripped.c")
  let source = data.text()
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "nested function pointer struct field" {
  let source =
    #|struct vfs {
    #|  void *(*xDlOpen)(struct vfs*, const char*);
    #|  void (*(*xDlSym)(struct vfs*, void*, const char*))(void);
    #|};
    #|int main(){ return 0; }
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "multiple indirection function pointer" {
  let source =
    #|typedef void (*callback_t)(void);
    #|typedef void (**callback_ptr_t)(void);
    #|void register_cb(callback_t **cb);
    #|int main(){ return 0; }
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "register and auto storage class" {
  let source =
    #|int main(){
    #|  register int x = 1;
    #|  auto int y = 2;
    #|  return x + y;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "local struct definition and typedef" {
  let source =
    #|int main(){
    #|  struct Point { int x; int y; };
    #|  struct Point p;
    #|  p.x = 1;
    #|  typedef int arr_t[10];
    #|  arr_t a;
    #|  typedef int empty_arr_t[];
    #|  return p.x;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "comma separated typedef" {
  let source =
    #|typedef int foo_t, bar_t, *baz_t;
    #|int main(){ foo_t a = 1; bar_t b = 2; baz_t p = &a; return *p + b; }
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "switch with case labels in compound stmt" {
  let source =
    #|int main(){
    #|  int x = 2;
    #|  switch (x) {
    #|    case 1: {
    #|      int a = 1;
    #|    case 2:
    #|      a = 2;
    #|    }
    #|    break;
    #|  }
    #|  return 0;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "enum with attributes and function type typedef" {
  let source =
    #|typedef enum __attribute__((__flag_enum__)) : unsigned int {
    #|  FLAG_A = 1,
    #|  FLAG_B = 2,
    #|} flags_t;
    #|
    #|typedef void (handler_t)(int);
    #|typedef void (*handler_ptr_t)(int);
    #|
    #|int main(){ return 0; }
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "ternary with comma operator" {
  let source =
    #|int main(){
    #|  int a = 1, b = 2;
    #|  int x = a ? (b = 3, b) : 0;
    #|  return x;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "parse sqlite3 preprocessed" {
  let data = @fs.read_file("/tmp/sqlite3_preprocessed.c")
  let source = data.text()
  let assembly = compile(source)
  assert_true(assembly.contains("_sqlite3_open:"))
}

///|
async test "compound literal" {
  let source =
    #|typedef struct { int x; int y; } Point;
    #|int main(){
    #|  Point p = (Point){ 1, 2 };
    #|  return p.x;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "__int128 and _Atomic types" {
  let source =
    #|typedef unsigned __int128 uint128_t;
    #|typedef _Atomic(int) atomic_int_t;
    #|typedef _Atomic(unsigned long long) atomic_ullong_t;
    #|int main(){ return 0; }
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "computed goto" {
  let source =
    #|int main(){
    #|  void *tab[] = { &&L1, &&L2 };
    #|  goto *tab[0];
    #|L1:
    #|  return 1;
    #|L2:
    #|  return 2;
    #|}
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "__attribute without trailing underscores" {
  let source =
    #|static void __attribute((unused)) foo(int x) {}
    #|int main(){ foo(1); return 0; }
  let assembly = compile(source)
  assert_true(assembly.contains("_main:"))
}

///|
async test "parse quickjs preprocessed" {
  let data = @fs.read_file("/tmp/quickjs_preprocessed.c")
  let source = data.text()
  let assembly = compile(source)
  assert_true(assembly.contains("_JS_Eval:"))
}

///|
async test "struct trailing padding" {
  let source =
    #|struct S { int a; char b; };
    #|int main() {
    #|  return sizeof(struct S);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="8")
}

///|
async test "bit-field read" {
  let source =
    #|struct S { unsigned int a:3; unsigned int b:4; };
    #|int main() {
    #|  struct S s;
    #|  s.a = 5;
    #|  s.b = 7;
    #|  return s.a + s.b;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="12")
}

///|
async test "bit-field write and read back" {
  let source =
    #|struct S { unsigned int a:5; unsigned int b:3; };
    #|int main() {
    #|  struct S s;
    #|  s.a = 17;
    #|  s.b = 5;
    #|  if (s.a != 17) return 1;
    #|  if (s.b != 5) return 2;
    #|  s.a = 31;
    #|  if (s.a != 31) return 3;
    #|  return 0;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "union size is max field" {
  let source =
    #|union U { char c; int i; };
    #|int main() {
    #|  return sizeof(union U);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="4")
}

///|
async test "signed bit-field sign extension" {
  let source =
    #|struct S { int a:3; };
    #|int main() {
    #|  struct S s;
    #|  s.a = -1;  // 0b111 in 3-bit signed = -1
    #|  return s.a + 1;  // should be 0
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}
