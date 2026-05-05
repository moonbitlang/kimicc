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
async test "sqlite fixture preprocesses and assembles" {
  let object_path = compile_sqlite_fixture_object()
  assert_true(object_path.contains("sqlite3"))
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
async test "fortified libc builtins lower to unchecked calls" {
  let source =
    #|typedef unsigned long size_t;
    #|typedef __builtin_va_list va_list;
    #|extern int strcmp(const char *, const char *);
    #|extern int __builtin___snprintf_chk(char *, size_t, int, size_t, const char *, ...);
    #|extern int __builtin___sprintf_chk(char *, int, size_t, const char *, ...);
    #|extern char *__builtin___strncpy_chk(char *, const char *, size_t, size_t);
    #|extern int __builtin___vsnprintf_chk(char *, size_t, int, size_t, const char *, va_list);
    #|
    #|static int format_into(char *buf, const char *fmt, ...) {
    #|  int n;
    #|  va_list ap;
    #|  __builtin_va_start(ap, fmt);
    #|  n = __builtin___vsnprintf_chk(buf, 32, 0, (size_t)-1, fmt, ap);
    #|  __builtin_va_end(ap);
    #|  return n;
    #|}
    #|
    #|int main() {
    #|  char buf[32];
    #|  int n = __builtin___snprintf_chk(buf, sizeof(buf), 0, (size_t)-1, "%s-%d", "ok", 7);
    #|  if (n != 4 || strcmp(buf, "ok-7") != 0) return 1;
    #|  n = __builtin___sprintf_chk(buf, 0, (size_t)-1, "%s", "xy");
    #|  if (n != 2 || strcmp(buf, "xy") != 0) return 2;
    #|  __builtin___strncpy_chk(buf, "abcd", 3, (size_t)-1);
    #|  buf[3] = 0;
    #|  if (strcmp(buf, "abc") != 0) return 3;
    #|  n = format_into(buf, "%s%d", "z", 5);
    #|  if (n != 2 || strcmp(buf, "z5") != 0) return 4;
    #|  return 0;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
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
async test "large struct field offset materializes address" {
  let source =
    #|struct S { char pad[4320]; long value; };
    #|int main() {
    #|  struct S s;
    #|  s.value = 37;
    #|  return s.value == 37 ? 0 : 1;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
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
async test "computed goto execution" {
  let source =
    #|int main() {
    #|  void *tab[] = { &&L1, &&L2 };
    #|  goto *tab[0];
    #|L1:
    #|  return 1;
    #|L2:
    #|  return 2;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="1")
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
async test "global array explicit size initialized" {
  let source =
    #|int global_arr[3] = {5, 10, 15};
    #|int main() {
    #|  return global_arr[0] + global_arr[1] + global_arr[2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="30")
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

///|
async test "array initializer partial" {
  let source =
    #|int main() {
    #|  int arr[5] = {1, 2};
    #|  return arr[0] + arr[1];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="3")
}

///|
async test "pointer subtraction" {
  let source =
    #|int main() {
    #|  int arr[5] = {10, 20, 30, 40, 50};
    #|  int *p = &arr[4];
    #|  int *q = &arr[1];
    #|  return p - q;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="3")
}

///|
async test "void pointer cast" {
  let source =
    #|int main() {
    #|  int x = 42;
    #|  void *vp = &x;
    #|  int *ip = (int *)vp;
    #|  return *ip;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "long long type" {
  let source =
    #|int main() {
    #|  long long x = 100;
    #|  return (int)x;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="100")
}

///|
async test "character literal as int" {
  let source =
    #|int main() {
    #|  int x = 'A';
    #|  return x;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="65")
}

///|
async test "function modifies array via decay" {
  let source =
    #|void set(int *a, int i, int v) {
    #|  a[i] = v;
    #|}
    #|int main() {
    #|  int arr[3] = {0, 0, 0};
    #|  set(arr, 1, 99);
    #|  return arr[1];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="99")
}

///|
async test "nested struct" {
  let source =
    #|struct Inner { int x; };
    #|struct Outer { struct Inner i; int y; };
    #|int main() {
    #|  struct Outer o;
    #|  o.i.x = 7;
    #|  o.y = 8;
    #|  return o.i.x + o.y;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="15")
}

///|
async test "for loop with compound body" {
  let source =
    #|int main() {
    #|  int sum = 0;
    #|  for (int i = 0; i < 3; i = i + 1) {
    #|    sum = sum + i;
    #|    sum = sum + 1;
    #|  }
    #|  return sum;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="6")
}

///|
async test "sizeof pointer vs array" {
  let source =
    #|int main() {
    #|  int arr[5];
    #|  int *p = arr;
    #|  return sizeof(p) + 1;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="9")
}

///|
async test "unsigned char array" {
  let source =
    #|int main() {
    #|  unsigned char arr[] = {1, 2, 3};
    #|  return arr[0] + arr[1] + arr[2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="6")
}

///|
async test "global scalar initializer" {
  let source =
    #|int x = 42;
    #|int main() {
    #|  return x;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "global string pointer initializer" {
  let source =
    #|char *msg = "hi";
    #|int main() {
    #|  return msg[0];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="104")
}

///|
async test "global mixed initialized and uninitialized" {
  let source =
    #|int a = 7;
    #|int b;
    #|int c = 3;
    #|int main() {
    #|  return a + c;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="10")
}

///|
async test "computed goto with dynamic index" {
  let source =
    #|int main() {
    #|  void *tab[] = { &&L1, &&L2, &&L3 };
    #|  int i = 1;
    #|  goto *tab[i];
    #|L1:
    #|  return 10;
    #|L2:
    #|  return 20;
    #|L3:
    #|  return 30;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="20")
}

///|
async test "function pointer array call" {
  let source =
    #|int add(int a, int b) { return a + b; }
    #|int sub(int a, int b) { return a - b; }
    #|int main() {
    #|  int (*ops[])(int, int) = {add, sub};
    #|  return ops[0](3, 2);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="5")
}

///|
async test "__builtin_expect" {
  let source =
    #|int main() {
    #|  int x = __builtin_expect(42, 42);
    #|  return x;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "__builtin_clz" {
  let source =
    #|int main() {
    #|  return __builtin_clz(1);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="31")
}

///|
async test "__builtin_ctz" {
  let source =
    #|int main() {
    #|  return __builtin_ctz(8);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="3")
}

///|
async test "__builtin_bswap32" {
  let source =
    #|int main() {
    #|  return __builtin_bswap32(0x01020304);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="1")
}

///|
async test "__builtin_memcpy" {
  let source =
    #|int main() {
    #|  int src[] = {1, 2, 3};
    #|  int dst[3];
    #|  __builtin_memcpy(dst, src, 12);
    #|  return dst[0] + dst[1] + dst[2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="6")
}

///|
async test "switch fallthrough with negative enum cases" {
  let source =
    #|enum { A = -7, B = -8, C = 0 };
    #|int f(int x) {
    #|    switch (x) {
    #|    case C:
    #|    case A:
    #|    case B:
    #|        return 1;
    #|    default:
    #|        return 0;
    #|    }
    #|}
    #|int main() {
    #|    if (f(0) != 1) return 1;
    #|    if (f(-7) != 1) return 2;
    #|    if (f(-8) != 1) return 3;
    #|    if (f(42) != 0) return 4;
    #|    return 0;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "variadic snprintf with integer" {
  let source =
    #|int snprintf(char *buf, unsigned long n, const char *fmt, ...);
    #|int main() {
    #|  char buf[32];
    #|  int r = snprintf(buf, 32, "val=%d", 42);
    #|  return r;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="6")
}

///|
async test "variadic snprintf with string" {
  let source =
    #|int snprintf(char *buf, unsigned long n, const char *fmt, ...);
    #|int main() {
    #|  char buf[32];
    #|  int r = snprintf(buf, 32, "hi %s", "there");
    #|  return r;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="8")
}

///|
async test "variadic snprintf with multiple args" {
  let source =
    #|int snprintf(char *buf, unsigned long n, const char *fmt, ...);
    #|int main() {
    #|  char buf[64];
    #|  int r = snprintf(buf, 64, "%d %s %d", 1, "two", 3);
    #|  return r;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="7")
}

///|
async test "variadic snprintf buffer contents integer" {
  let source =
    #|int snprintf(char *buf, unsigned long n, const char *fmt, ...);
    #|int main() {
    #|  char buf[32];
    #|  snprintf(buf, 32, "val=%d", 42);
    #|  return buf[0]; // 'v' = 118
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="118")
}

///|
async test "variadic snprintf buffer contents string" {
  let source =
    #|int snprintf(char *buf, unsigned long n, const char *fmt, ...);
    #|int main() {
    #|  char buf[32];
    #|  snprintf(buf, 32, "hi %s", "there");
    #|  return buf[3]; // 't' = 116
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="116")
}

///|
async test "variadic snprintf with no variadic args" {
  let source =
    #|int snprintf(char *buf, unsigned long n, const char *fmt, ...);
    #|int main() {
    #|  char buf[32];
    #|  int r = snprintf(buf, 32, "hello");
    #|  return r;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="5")
}

///|
async test "variadic snprintf with hex" {
  let source =
    #|int snprintf(char *buf, unsigned long n, const char *fmt, ...);
    #|int main() {
    #|  char buf[32];
    #|  int r = snprintf(buf, 32, "0x%x", 255);
    #|  return r;
    #|}
  let exit_code = run_source_async(source)
  // "0xff" is 4 chars
  inspect(exit_code, content="4")
}

///|
async test "variadic snprintf with pointer" {
  let source =
    #|int snprintf(char *buf, unsigned long n, const char *fmt, ...);
    #|int main() {
    #|  char buf[64];
    #|  int x = 42;
    #|  int r = snprintf(buf, 64, "%p", &x);
    #|  return r;
    #|}
  let exit_code = run_source_async(source)
  // macOS %p prints without leading zeros: "0x" + 9 hex digits = 11
  inspect(exit_code, content="11")
}

///|
async test "variadic snprintf with double" {
  let source =
    #|int snprintf(char *buf, unsigned long n, const char *fmt, ...);
    #|int strcmp(const char *s1, const char *s2);
    #|int main() {
    #|  char buf[64];
    #|  snprintf(buf, 64, "%.2f", 3.14);
    #|  if (strcmp(buf, "3.14") == 0) return 0;
    #|  return 1;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "variadic snprintf with mixed int and double" {
  let source =
    #|int snprintf(char *buf, unsigned long n, const char *fmt, ...);
    #|int strcmp(const char *s1, const char *s2);
    #|int main() {
    #|  char buf[64];
    #|  snprintf(buf, 64, "int=%d double=%.2f", 42, 3.14);
    #|  if (strcmp(buf, "int=42 double=3.14") == 0) return 0;
    #|  return 1;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "variadic function pointer cast passes unnamed args on stack" {
  let source =
    #|int snprintf(char *buf, unsigned long n, const char *fmt, ...);
    #|int strcmp(const char *s1, const char *s2);
    #|int main() {
    #|  char buf[32];
    #|  int r = ((int (*)(char *, unsigned long, const char *, ...))snprintf)(
    #|    buf,
    #|    32,
    #|    "v=%d",
    #|    42
    #|  );
    #|  if (r != 4) return 1;
    #|  if (strcmp(buf, "v=42") != 0) return 2;
    #|  return 0;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "hex float literal" {
  let source =
    #|int main() {
    #|    double d = 0x1p10;
    #|    if (d == 1024.0) return 0;
    #|    return 1;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "hex float literal large exponent" {
  let source =
    #|int main() {
    #|    double d = 0x1p1008;
    #|    // 2^1008 overflows double to infinity
    #|    if (d > 1e300) return 0;
    #|    return 1;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "__builtin_alloca basic" {
  let source =
    #|int main() {
    #|  int *p = __builtin_alloca(16);
    #|  p[0] = 42;
    #|  p[1] = 43;
    #|  p[2] = 44;
    #|  p[3] = 45;
    #|  return p[0] + p[1] + p[2] + p[3];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="174")
}

///|
async test "__builtin_alloca with variable size" {
  let source =
    #|int main() {
    #|  int n = 4;
    #|  int *p = __builtin_alloca(n * 8);
    #|  p[0] = 1;
    #|  p[1] = 2;
    #|  p[2] = 3;
    #|  p[3] = 4;
    #|  return p[0] + p[1] + p[2] + p[3];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="10")
}

///|
async test "__builtin_constant_p" {
  let source =
    #|int main() {
    #|  int x = 42;
    #|  return __builtin_constant_p(x);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "__builtin_object_size" {
  let source =
    #|int main() {
    #|  int x;
    #|  return (int)__builtin_object_size(&x, 0);
    #|}
  let exit_code = run_source_async(source)
  // __builtin_object_size returns -1 (SIZE_MAX) as stub; exit code is 255
  inspect(exit_code, content="255")
}

///|
async test "__builtin___memcpy_chk" {
  let source =
    #|int main() {
    #|  int src[] = {1, 2, 3};
    #|  int dst[3];
    #|  __builtin___memcpy_chk(dst, src, 12, 12);
    #|  return dst[0] + dst[1] + dst[2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="6")
}

///|
async test "__builtin___memset_chk" {
  let source =
    #|int main() {
    #|  char buf[4];
    #|  __builtin___memset_chk(buf, 7, 4, 4);
    #|  return buf[0] + buf[1] + buf[2] + buf[3];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="28")
}

///|
async test "__builtin___strcpy_chk" {
  let source =
    #|int main() {
    #|  char dst[16];
    #|  __builtin___strcpy_chk(dst, "hi", 16);
    #|  return dst[0] + dst[1];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="209")
}

///|
async test "double literal return compiles" {
  let source =
    #|double get_pi() { return 3.14; }
    #|int main() { return 0; }
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "double local variable compiles" {
  let source =
    #|double get_val() {
    #|  double x = 2.5;
    #|  return x;
    #|}
    #|int main() { return 0; }
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "float literal return compiles" {
  let source =
    #|float get_val() { return 1.5; }
    #|int main() { return 0; }
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "double parameter and return" {
  let source =
    #|double foo(int a, double b, int c, double d) { return d; }
    #|int main() { return 0; }
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "float parameter and return" {
  let source =
    #|float foo(int a, float b) { return b; }
    #|int main() { return 0; }
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "double arithmetic compiles" {
  let source =
    #|double add(double a, double b) { return a + b; }
    #|double sub(double a, double b) { return a - b; }
    #|double mul(double a, double b) { return a * b; }
    #|double div(double a, double b) { return a / b; }
    #|double neg(double a) { return -a; }
    #|int main() { return 0; }
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "double comparisons compiles" {
  let source =
    #|int eq(double a, double b) { return a == b; }
    #|int lt(double a, double b) { return a < b; }
    #|int gt(double a, double b) { return a > b; }
    #|int main() { return 0; }
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "double casts compiles" {
  let source =
    #|int d2i(double a) { return (int)a; }
    #|double i2d(int a) { return (double)a; }
    #|float d2f(double a) { return (float)a; }
    #|double f2d(float a) { return (double)a; }
    #|int main() { return 0; }
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "fp builtins compiles" {
  let source =
    #|double test_fabs(double a) { return __builtin_fabs(a); }
    #|float test_fabsf(float a) { return __builtin_fabsf(a); }
    #|double test_nan() { return __builtin_nan(""); }
    #|float test_nanf() { return __builtin_nanf(""); }
    #|double test_inf() { return __builtin_huge_val(); }
    #|float test_inff() { return __builtin_huge_valf(); }
    #|int main() { return 0; }
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}
