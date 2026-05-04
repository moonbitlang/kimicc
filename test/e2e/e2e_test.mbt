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

///|
async test "array initializer with inferred size" {
  let source =
    #|int main() {
    #|  int arr[] = {10, 20, 30};
    #|  return arr[0] + arr[1] + arr[2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="60")
}

///|
async test "array initializer with explicit size" {
  let source =
    #|int main() {
    #|  int arr[5] = {1, 2, 3};
    #|  return arr[0] + arr[1] * 2 + arr[2] * 4;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="17")
}

///|
async test "array initializer with expressions" {
  let source =
    #|int add(int a, int b) { return a + b; }
    #|int main() {
    #|  int arr[] = {1 + 1, add(2, 2), 5 * 1};
    #|  return arr[0] + arr[1] + arr[2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="11")
}

///|
async test "array initializer and pointer arithmetic" {
  let source =
    #|int main() {
    #|  int arr[] = {10, 20, 30, 40, 50};
    #|  int *p = arr;
    #|  return p[0] + *(p + 2) + p[4];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="90")
}

///|
async test "array initializer in loop" {
  let source =
    #|int main() {
    #|  int arr[] = {3, 1, 4, 1, 5};
    #|  int sum = 0;
    #|  for (int i = 0; i < 5; i = i + 1) {
    #|    sum = sum + arr[i];
    #|  }
    #|  return sum;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="14")
}

///|
async test "bubble sort with array initializer" {
  let source =
    #|void swap(int *a, int *b) {
    #|  int t = *a; *a = *b; *b = t;
    #|}
    #|void bubble_sort(int arr[], int n) {
    #|  for (int i = 0; i < n - 1; i = i + 1) {
    #|    for (int j = 0; j < n - i - 1; j = j + 1) {
    #|      if (arr[j] > arr[j + 1]) {
    #|        swap(&arr[j], &arr[j + 1]);
    #|      }
    #|    }
    #|  }
    #|}
    #|int main() {
    #|  int arr[] = {5, 2, 8, 1, 3};
    #|  bubble_sort(arr, 5);
    #|  return arr[0] + arr[1]*10 + arr[2]*100 + arr[3]*1000 + arr[4]*10000;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="73")
}

///|
async test "array initializer with char literals" {
  let source =
    #|int main() {
    #|  int arr[] = {'a', 'b', 'c'};
    #|  return arr[0] - 'a' + arr[1] - 'b' + arr[2] - 'c';
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "multiple variables with array initializer" {
  let source =
    #|int main() {
    #|  int a = 1, b[] = {2, 3}, c = 4;
    #|  return a + b[0] + b[1] + c;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="10")
}

///|
async test "function taking initialized array" {
  let source =
    #|int sum(int arr[], int n) {
    #|  int s = 0;
    #|  for (int i = 0; i < n; i = i + 1) {
    #|    s = s + arr[i];
    #|  }
    #|  return s;
    #|}
    #|int main() {
    #|  int arr[] = {3, 1, 4, 1, 5};
    #|  return sum(arr, 5);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="14")
}

///|
async test "address of array element with initializer" {
  let source =
    #|int main() {
    #|  int arr[] = {10, 20, 30};
    #|  int *p = &arr[1];
    #|  return *p;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="20")
}

///|
async test "struct with array field explicit assignment" {
  let source =
    #|struct S { int arr[3]; };
    #|int main() {
    #|  struct S s;
    #|  s.arr[0] = 1;
    #|  s.arr[1] = 2;
    #|  s.arr[2] = 3;
    #|  return s.arr[0] + s.arr[1] + s.arr[2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="6")
}

///|
async test "array initializer in nested loop" {
  let source =
    #|int main() {
    #|  int arr[] = {1, 2, 3, 4, 5, 6};
    #|  int sum = 0;
    #|  for (int i = 0; i < 2; i = i + 1) {
    #|    for (int j = 0; j < 3; j = j + 1) {
    #|      sum = sum + arr[i * 3 + j];
    #|    }
    #|  }
    #|  return sum;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="21")
}

///|
async test "switch with array initializer" {
  let source =
    #|int main() {
    #|  int arr[] = {10, 20, 30};
    #|  int idx = 1;
    #|  switch (idx) {
    #|    case 0: return arr[0];
    #|    case 1: return arr[1];
    #|    case 2: return arr[2];
    #|    default: return 0;
    #|  }
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="20")
}

///|
async test "array initializer reverse traversal" {
  let source =
    #|int main() {
    #|  int arr[] = {5, 4, 3, 2, 1};
    #|  int sum = 0;
    #|  for (int i = 4; i >= 0; i = i - 1) {
    #|    sum = sum + arr[i];
    #|  }
    #|  return sum;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="15")
}

///|
async test "array of pointers with initializer" {
  let source =
    #|int main() {
    #|  int a = 10, b = 20, c = 30;
    #|  int *arr[] = {&a, &b, &c};
    #|  return *arr[0] + *arr[1] + *arr[2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="60")
}

///|
async test "2D array explicit assignment" {
  let source =
    #|int main() {
    #|  int arr[2][3];
    #|  arr[0][0] = 1; arr[0][1] = 2; arr[0][2] = 3;
    #|  arr[1][0] = 4; arr[1][1] = 5; arr[1][2] = 6;
    #|  return arr[0][0] + arr[1][2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="7")
}

///|
async test "array in ternary expression" {
  let source =
    #|int main() {
    #|  int arr[] = {5, 10};
    #|  return arr[0] > arr[1] ? arr[0] : arr[1];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="10")
}

///|
async test "array in conditional" {
  let source =
    #|int main() {
    #|  int arr[] = {3, 1, 4};
    #|  if (arr[0] > arr[1]) {
    #|    return arr[2];
    #|  }
    #|  return 0;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="4")
}

///|
async test "global array declaration compile only" {
  let source =
    #|int global_arr[5];
    #|int main() {
    #|  global_arr[0] = 7;
    #|  return global_arr[0];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="7")
}

///|
async test "empty array initializer" {
  let source =
    #|int main() {
    #|  int arr[3] = {};
    #|  arr[0] = 1;
    #|  return arr[0];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="1")
}

///|
async test "array initializer with all same values" {
  let source =
    #|int main() {
    #|  int arr[] = {5, 5, 5, 5};
    #|  return arr[0] + arr[1] + arr[2] + arr[3];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="20")
}

///|
async test "__func__ in function" {
  let source =
    #|const char *get_name() {
    #|  return __func__;
    #|}
    #|int main() {
    #|  const char *name = get_name();
    #|  return name[0] == 'g' && name[1] == 'e' && name[2] == 't' ? 0 : 1;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "bit-field cross byte boundary" {
  let source =
    #|struct S { unsigned int a:4; unsigned int b:4; unsigned int c:4; };
    #|int main() {
    #|  struct S s;
    #|  s.a = 7; s.b = 12; s.c = 3;
    #|  return s.a + s.b + s.c;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="22")
}

///|
async test "nested struct access" {
  let source =
    #|struct Inner { int x; int y; };
    #|struct Outer { struct Inner i; int z; };
    #|int main() {
    #|  struct Outer o;
    #|  o.i.x = 1;
    #|  o.i.y = 2;
    #|  o.z = 3;
    #|  return o.i.x + o.i.y + o.z;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="6")
}

///|
async test "computed goto compiles" {
  let source =
    #|int main() {
    #|  void *tab[] = { &&L1, &&L2 };
    #|  goto *tab[0];
    #|L1:
    #|  return 1;
    #|L2:
    #|  return 2;
}

///|
async test "sizeof array type" {
  let source =
    #|int main() {
    #|  int arr[10];
    #|  return sizeof(arr);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="40")
}

///|
async test "array decays to pointer in function call" {
  let source =
    #|int first(int *p) { return p[0]; }
    #|int main() {
    #|  int arr[] = {7, 8, 9};
    #|  return first(arr);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="7")
}

///|
async test "global array with skipped initializer compiles" {
  let source =
    #|int global_arr[] = {1, 2, 3};
    #|int main() {
    #|  global_arr[0] = 5;
    #|  return global_arr[0];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="5")
}

///|
async test "array initializer with variable expressions" {
  let source =
    #|int main() {
    #|  int a = 3;
    #|  int b = 4;
    #|  int arr[] = {a, b, a + b};
    #|  return arr[2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="7")
}

///|
async test "shadowed array with initializer" {
  let source =
    #|int main() {
    #|  int arr[] = {1, 2, 3};
    #|  {
    #|    int arr[] = {10, 20};
    #|    if (arr[0] != 10) return 1;
    #|    if (arr[1] != 20) return 2;
    #|  }
    #|  return arr[0] + arr[1] + arr[2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="6")
}

///|
async test "char array initializer" {
  let source =
    #|int main() {
    #|  char arr[] = {1, 2, 3};
    #|  return arr[0] + arr[1] + arr[2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="6")
}

///|
async test "pointer arithmetic with array initializer" {
  let source =
    #|int main() {
    #|  int arr[] = {10, 20, 30, 40};
    #|  int *p = arr + 2;
    #|  return *p;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="30")
}

///|
async test "enum in switch case" {
  let source =
    #|enum Color { RED, GREEN, BLUE };
    #|int main() {
    #|  enum Color c = GREEN;
    #|  switch (c) {
    #|    case RED: return 1;
    #|    case GREEN: return 2;
    #|    case BLUE: return 3;
    #|    default: return 0;
    #|  }
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="2")
}

///|
async test "ternary operator" {
  let source =
    #|int main() {
    #|  int a = 5;
    #|  int b = 10;
    #|  return a > b ? 1 : 2;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="2")
}

///|
async test "string literal indexing" {
  let source =
    #|int main() {
    #|  char *s = "hello";
    #|  return s[0] + s[4];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="215")
}

///|
async test "global array explicit size zero-initialized" {
  let source =
    #|int global_arr[3] = {5, 10, 15};
    #|int main() {
    #|  return global_arr[0] + global_arr[1] + global_arr[2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "cast to char and back" {
  let source =
    #|int main() {
    #|  int x = 300;
    #|  char c = (char)x;
    #|  return (int)c;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="44")
}

///|
async test "sizeof expression" {
  let source =
    #|int main() {
    #|  int arr[10];
    #|  return sizeof(arr) / sizeof(arr[0]);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="10")
}

///|
async test "prefix increment" {
  let source =
    #|int main() {
    #|  int x = 5;
    #|  return ++x;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="6")
}

///|
async test "postfix increment" {
  let source =
    #|int main() {
    #|  int x = 5;
    #|  int y = x++;
    #|  return y + x;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="11")
}

///|
async test "do-while loop" {
  let source =
    #|int main() {
    #|  int i = 0;
    #|  do {
    #|    i = i + 1;
    #|  } while (i < 5);
    #|  return i;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="5")
}

///|
async test "nested if-else" {
  let source =
    #|int main() {
    #|  int x = 3;
    #|  if (x == 1) return 1;
    #|  else if (x == 2) return 2;
    #|  else if (x == 3) return 3;
    #|  else return 4;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="3")
}

///|
async test "bitwise operators" {
  let source =
    #|int main() {
    #|  int a = 5;
    #|  int b = 3;
    #|  return (a & b) | (a ^ b);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="7")
}

///|
async test "logical operators short circuit" {
  let source =
    #|int main() {
    #|  int x = 0;
    #|  if (0 && (x = 1)) return 1;
    #|  return x;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "array decay in function parameter" {
  let source =
    #|int sum(int a[], int n) {
    #|  int s = 0;
    #|  for (int i = 0; i < n; i = i + 1) {
    #|    s = s + a[i];
    #|  }
    #|  return s;
    #|}
    #|int main() {
    #|  int arr[] = {1, 2, 3, 4, 5};
    #|  return sum(arr, 5);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="15")
}

///|
async test "multiple pointer dereference" {
  let source =
    #|int main() {
    #|  int x = 42;
    #|  int *p = &x;
    #|  int **pp = &p;
    #|  return **pp;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "bitwise shift operators" {
  let source =
    #|int main() {
    #|  int a = 1;
    #|  return (a << 3) | (16 >> 2);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="12")
}

///|
async test "negative number expression" {
  let source =
    #|int main() {
    #|  int x = -5;
    #|  return x + 10;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="5")
}

///|
async test "large hex constant" {
  let source =
    #|int main() {
    #|  unsigned long x = 0xFFFFFFFF;
    #|  return (int)(x >> 24);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="255")
}

///|
async test "struct array access" {
  let source =
    #|struct Point { int x; int y; };
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
async test "union basic usage" {
  let source =
    #|union U { int i; char c; };
    #|int main() {
    #|  union U u;
    #|  u.i = 1;
    #|  return u.i;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="1")
}

///|
async test "bit-field basic" {
  let source =
    #|struct S {
    #|  unsigned int a : 4;
    #|  unsigned int b : 4;
    #|};
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
async test "continue in loop" {
  let source =
    #|int main() {
    #|  int sum = 0;
    #|  for (int i = 0; i < 5; i = i + 1) {
    #|    if (i == 2) continue;
    #|    sum = sum + i;
    #|  }
    #|  return sum;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="8")
}

///|
async test "break in nested loop" {
  let source =
    #|int main() {
    #|  int sum = 0;
    #|  for (int i = 0; i < 5; i = i + 1) {
    #|    for (int j = 0; j < 5; j = j + 1) {
    #|      if (j == 2) break;
    #|      sum = sum + 1;
    #|    }
    #|  }
    #|  return sum;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="10")
}

///|
async test "function pointer call" {
  let source =
    #|int add(int a, int b) { return a + b; }
    #|int main() {
    #|  int (*f)(int, int) = add;
    #|  return f(2, 3);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="5")
}

///|
async test "NULL pointer comparison" {
  let source =
    #|int main() {
    #|  int *p = 0;
    #|  if (p) return 1;
    #|  return 0;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "variable shadowing different types" {
  let source =
    #|int main() {
    #|  int x = 10;
    #|  {
    #|    char x = 5;
    #|    if (x != 5) return 1;
    #|  }
    #|  return x;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="10")
}

///|
async test "array of pointers" {
  let source =
    #|int main() {
    #|  int a = 1, b = 2, c = 3;
    #|  int *arr[] = {&a, &b, &c};
    #|  return *arr[0] + *arr[1] + *arr[2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="6")
}

///|
async test "pointer to array" {
  let source =
    #|int main() {
    #|  int arr[3] = {10, 20, 30};
    #|  int (*p)[3] = &arr;
    #|  return (*p)[1];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="20")
}

///|
async test "comma operator expression" {
  let source =
    #|int main() {
    #|  int x;
    #|  x = (1, 2, 3);
    #|  return x;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="3")
}

///|
async test "nested ternary" {
  let source =
    #|int main() {
    #|  int a = 1, b = 2, c = 3;
    #|  return a > b ? 10 : (b > c ? 20 : 30);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="30")
}

///|
async test "unsigned comparison" {
  let source =
    #|int main() {
    #|  unsigned int a = 5;
    #|  unsigned int b = 10;
    #|  return a < b ? 1 : 0;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="1")
}

///|
async test "array index with expression" {
  let source =
    #|int main() {
    #|  int arr[] = {10, 20, 30, 40, 50};
    #|  int i = 2;
    #|  return arr[i + 1];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="40")
}

///|
async test "while with break" {
  let source =
    #|int main() {
    #|  int i = 0;
    #|  while (1) {
    #|    i = i + 1;
    #|    if (i == 5) break;
    #|  }
    #|  return i;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="5")
}

///|
async test "goto forward and backward" {
  let source =
    #|int main() {
    #|  int x = 0;
    #|  goto forward;
    #|backward:
    #|  return x;
    #|forward:
    #|  x = 42;
    #|  goto backward;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "switch with default" {
  let source =
    #|int main() {
    #|  int x = 7;
    #|  switch (x) {
    #|    case 1: return 1;
    #|    case 2: return 2;
    #|    default: return 99;
    #|  }
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="99")
}

///|
async test "signed right shift" {
  let source =
    #|int main() {
    #|  int x = -16;
    #|  return (x >> 2) + 10;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="6")
}

///|
async test "array of structs" {
  let source =
    #|struct Point { int x; int y; };
    #|int main() {
    #|  struct Point pts[2];
    #|  pts[0].x = 1; pts[0].y = 2;
    #|  pts[1].x = 3; pts[1].y = 4;
    #|  return pts[0].x + pts[1].y;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="5")
}

///|
async test "struct pointer member access" {
  let source =
    #|struct Point { int x; int y; };
    #|int main() {
    #|  struct Point p;
    #|  struct Point *pp = &p;
    #|  pp->x = 7;
    #|  pp->y = 8;
    #|  return pp->x + pp->y;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="15")
}

///|
async test "typedef usage" {
  let source =
    #|typedef int MyInt;
    #|typedef struct { int a; } S;
    #|int main() {
    #|  MyInt x = 5;
    #|  S s;
    #|  s.a = 10;
    #|  return x + s.a;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="15")
}

///|
async test "early return" {
  let source =
    #|int main() {
    #|  if (1) return 77;
    #|  return 0;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="77")
}

///|
async test "recursive factorial" {
  let source =
    #|int fact(int n) {
    #|  if (n <= 1) return 1;
    #|  return n * fact(n - 1);
    #|}
    #|int main() {
    #|  return fact(5);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="120")
}
