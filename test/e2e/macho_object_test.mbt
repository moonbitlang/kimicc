///|

///|
priv struct DirectObjectFixture {
  path : String
  tag : String
  expected : Int
}

///|
async test "direct macho object links and runs constant return" {
  let source = "int main(void) { return 42; }"
  let exit_code = run_source_direct_object_async(source, "macho_return_42")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports local return branch" {
  let source = "int main(void) { return 7; }"
  let exit_code = run_source_direct_object_async(source, "macho_return_7")
  inspect(exit_code, content="7")
}

///|
async test "direct macho object supports wide immediate return" {
  let source = "int main(void) { return 1114111; }"
  let exit_code = run_source_direct_object_async(source, "macho_return_wide")
  inspect(exit_code, content="255")
}

///|
async test "direct macho object supports shifted mov immediate" {
  let source = "int main(void) { unsigned long x = 2147483648UL; return x == 2147483648UL ? 42 : 1; }"
  let exit_code = run_source_direct_object_async(
    source, "macho_shifted_mov_imm",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports large quad initializer" {
  let source = "unsigned long g = 2147483648UL; int main(void) { return g == 2147483648UL ? 42 : 1; }"
  let exit_code = run_source_direct_object_async(
    source, "macho_large_quad_init",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports float global initializer" {
  let source = "float g = 1.0f; int main(void) { unsigned int *p = (unsigned int *)&g; return *p == 0x3f800000 ? 42 : 1; }"
  let exit_code = run_source_direct_object_async(
    source, "macho_float_global_init",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports max unsigned data initializers" {
  let source = "unsigned char c = 255; unsigned short s = 65535; unsigned int i = 4294967295U; int main(void) { return c == 255 && s == 65535 && i == 4294967295U ? 42 : 1; }"
  let exit_code = run_source_direct_object_async(
    source, "macho_unsigned_data_max",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports global bit-field initializers" {
  let source =
    #|struct Bits { unsigned a : 3; signed b : 4; unsigned c : 5; };
    #|union UBits { unsigned a : 3; signed b : 4; };
    #|struct Bits bits = { .a = 5, .b = -3, .c = 17 };
    #|union UBits ubits = { .b = -3 };
    #|int main(void) {
    #|  if (bits.a != 5) return 1;
    #|  if (bits.b != -3) return 2;
    #|  if (bits.c != 17) return 3;
    #|  if (ubits.b != -3) return 4;
    #|  return 42;
    #|}
  let exit_code = run_source_direct_object_async(
    source, "macho_global_bitfield_init",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports global aggregate initializers" {
  let source =
    #|struct Inner { char c; int x; };
    #|struct Outer { char tag; struct Inner inner; int tail; };
    #|struct Refs { int *first; int *tail; int (*fn)(int); };
    #|struct Node { int value; struct Node *next; };
    #|union Bytes { int i; char c[4]; };
    #|int add1(int x) { return x + 1; }
    #|int arr[5] = { 1, [3] = 4 };
    #|struct Outer outer = { .tail = 9, .inner = { .x = 7, .c = 2 }, .tag = 1 };
    #|int *ptr = arr + 3;
    #|int (*fp)(int) = add1;
    #|int *ptrs[3] = { arr, arr + 2, &arr[4] };
    #|struct Refs refs = { .tail = arr + 4, .fn = add1, .first = &arr[1] };
    #|int *member = &outer.inner.x;
    #|int *member_next = &outer.inner.x + 1;
    #|struct Node node2 = { 2, 0 };
    #|struct Node node1 = { .next = &node2, .value = 1 };
    #|struct Node *nodes[2] = { &node1, &node2 };
    #|union Bytes bytes = { .c = { 65, 66, 0, 0 } };
    #|char str[6] = "hey";
    #|int main(void) {
    #|  if (arr[0] != 1 || arr[3] != 4 || arr[4] != 0) return 1;
    #|  if (outer.tag != 1 || outer.inner.c != 2 || outer.inner.x != 7 || outer.tail != 9) return 2;
    #|  if (ptr != &arr[3] || *ptr != 4) return 3;
    #|  if (fp(41) != 42) return 4;
    #|  if (ptrs[0] != &arr[0] || ptrs[1] != &arr[2] || ptrs[2] != &arr[4]) return 5;
    #|  if (refs.first != &arr[1] || refs.tail != &arr[4] || refs.fn(41) != 42) return 6;
    #|  if (member != &outer.inner.x || *member != 7 || member_next != &outer.tail) return 7;
    #|  if (node1.value != 1 || node1.next != &node2 || node2.value != 2 || node2.next != 0) return 8;
    #|  if (nodes[0] != &node1 || nodes[1] != &node2) return 9;
    #|  if (bytes.c[0] != 65 || bytes.c[1] != 66 || bytes.c[2] != 0 || bytes.c[3] != 0) return 10;
    #|  if (str[0] != 104 || str[1] != 101 || str[2] != 121 || str[3] != 0 || str[5] != 0) return 11;
    #|  return 42;
    #|}
  let exit_code = run_source_direct_object_async(
    source, "macho_global_aggregate_init",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports nested global designators" {
  let source =
    #|typedef union Box {
    #|  double d;
    #|  long l;
    #|} Box;
    #|typedef struct Value {
    #|  Box box;
    #|  int tag;
    #|  int arr[3];
    #|} Value;
    #|struct Pair {
    #|  int a;
    #|  int b;
    #|};
    #|Value value = { .box.d = 1.5, .tag = 7, .arr[2] = 35 };
    #|struct Pair pairs[2] = { [1].b = 5, [0].a = 37 };
    #|int main(void) {
    #|  if (value.box.d != 1.5) return 1;
    #|  if (value.tag != 7) return 2;
    #|  if (value.arr[0] != 0 || value.arr[1] != 0 || value.arr[2] != 35) return 3;
    #|  if (pairs[0].a != 37 || pairs[0].b != 0) return 4;
    #|  if (pairs[1].a != 0 || pairs[1].b != 5) return 5;
    #|  return 42;
    #|}
  let exit_code = run_source_direct_object_async(
    source, "macho_nested_global_designators",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object emits bss as zerofill with later const data" {
  let source = "int data = 1; int bss; int main(void) { char *s = \"A\"; bss = 40; return data + bss + s[0] - 64; }"
  let obj_path = compile_source_to_direct_object_path(
    source, "macho_bss_zerofill_const",
  )
  let bin_path = temp_file_path("macho_bss_zerofill_const_bin", source, "")
  run_command_checked(
    "clang -o " + shell_quote(bin_path) + " " + shell_quote(obj_path),
    "link direct object macho_bss_zerofill_const",
  )
  let headers = run_command_capture(
    "otool -l " + shell_quote(obj_path),
    "macho_bss_zerofill_const_otool",
  )
  if !headers.output.contains("sectname __bss") ||
    !headers.output.contains("offset 0") ||
    !headers.output.contains("flags 0x00000001") {
    abort("direct Mach-O __bss is not emitted as zerofill:\n" + headers.output)
  }
  let result = run_command_capture(
    shell_quote(bin_path),
    "macho_bss_zerofill_const_run",
  )
  inspect(result.code, content="42")
}

///|
async test "direct macho object retains non-external function labels" {
  let source = "static int hidden(void) { return 42; }"
  let obj_path = compile_source_to_direct_object_path(
    source, "macho_local_function_symbol",
  )
  let symbols = run_command_capture(
    "nm -m " + shell_quote(obj_path),
    "macho_local_function_symbol_nm",
  )
  if !symbols.output.contains("non-external _hidden") {
    abort(
      "direct Mach-O object omitted local function symbol:\n" + symbols.output,
    )
  }
}

///|
async test "direct macho object keeps subsection atomization disabled" {
  let source = "int helper(void) { return 40; } int main(void) { return helper() + 2; }"
  let obj_path = compile_source_to_direct_object_path(
    source, "macho_no_subsections_via_symbols",
  )
  let header = run_command_capture(
    "otool -h " + shell_quote(obj_path),
    "macho_no_subsections_via_symbols_header",
  )
  if !header.output.contains("0x00000000") ||
    header.output.contains("0x00002000") {
    abort(
      "direct Mach-O object should not request MH_SUBSECTIONS_VIA_SYMBOLS:\n" +
      header.output,
    )
  }
  let exit_code = run_source_direct_object_async(
    source, "macho_no_subsections_via_symbols_run",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports local integer arithmetic" {
  let source = "int main(void) { int a = 1; int b = 2; return a + b + 3; }"
  let exit_code = run_source_direct_object_async(source, "macho_local_arith")
  inspect(exit_code, content="6")
}

///|
async test "direct macho object supports local multiply and subtract" {
  let source = "int main(void) { int a = 6; int b = 7; return a * b - 1; }"
  let exit_code = run_source_direct_object_async(source, "macho_local_mul_sub")
  inspect(exit_code, content="41")
}

///|
async test "direct macho object supports signed division" {
  let source = "int main(void) { int a = 40; int b = 5; return a / b; }"
  let exit_code = run_source_direct_object_async(source, "macho_signed_div")
  inspect(exit_code, content="8")
}

///|
async test "direct macho object supports signed modulo" {
  let source = "int main(void) { int a = 43; int b = 5; return a % b; }"
  let exit_code = run_source_direct_object_async(source, "macho_signed_mod")
  inspect(exit_code, content="3")
}

///|
async test "direct macho object supports unary minus" {
  let source = "int main(void) { int a = 7; return -a + 9; }"
  let exit_code = run_source_direct_object_async(source, "macho_unary_minus")
  inspect(exit_code, content="2")
}

///|
async test "direct macho object supports unsigned division" {
  let source = "int main(void) { unsigned long a = 42; unsigned long b = 5; return (int)(a / b); }"
  let exit_code = run_source_direct_object_async(source, "macho_unsigned_div")
  inspect(exit_code, content="8")
}

///|
async test "direct macho object supports unsigned modulo" {
  let source = "int main(void) { unsigned long a = 42; unsigned long b = 5; return (int)(a % b); }"
  let exit_code = run_source_direct_object_async(source, "macho_unsigned_mod")
  inspect(exit_code, content="2")
}

///|
async test "direct macho object supports unsigned int128 multiply high limb" {
  let source =
    #|typedef unsigned __int128 u128;
    #|
    #|u128 mk(unsigned long a, unsigned long b) {
    #|  return (u128)a * (u128)b;
    #|}
    #|
    #|unsigned long lo(u128 x) {
    #|  return (unsigned long)x;
    #|}
    #|
    #|unsigned long hi(u128 x) {
    #|  return (unsigned long)(x >> 64);
    #|}
    #|
    #|int main(void) {
    #|  unsigned long all = ~0UL;
    #|  u128 x = mk(all, 2UL);
    #|  if (lo(x) != all - 1UL) return 1;
    #|  if (hi(x) != 1UL) return 2;
    #|  return 42;
    #|}
  let exit_code = run_source_direct_object_async(source, "macho_uint128_mul")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports unsigned int128 add and subtract carry" {
  let source =
    #|typedef unsigned __int128 u128;
    #|
    #|unsigned long lo(u128 x) {
    #|  return (unsigned long)x;
    #|}
    #|
    #|unsigned long hi(u128 x) {
    #|  return (unsigned long)(x >> 64);
    #|}
    #|
    #|int main(void) {
    #|  unsigned long all = ~0UL;
    #|  u128 x = (u128)all + 2UL;
    #|  if (lo(x) != 1UL) return 1;
    #|  if (hi(x) != 1UL) return 2;
    #|  x = x - 3UL;
    #|  if (lo(x) != all - 1UL) return 3;
    #|  if (hi(x) != 0UL) return 4;
    #|  return 42;
    #|}
  let exit_code = run_source_direct_object_async(source, "macho_uint128_carry")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports unsigned int128 negation carry" {
  let source =
    #|typedef unsigned __int128 u128;
    #|
    #|unsigned long lo(u128 x) {
    #|  return (unsigned long)x;
    #|}
    #|
    #|unsigned long hi(u128 x) {
    #|  return (unsigned long)(x >> 64);
    #|}
    #|
    #|int main(void) {
    #|  unsigned long all = ~0UL;
    #|  u128 x = -((u128)1);
    #|  if (lo(x) != all) return 1;
    #|  if (hi(x) != all) return 2;
    #|  return 42;
    #|}
  let exit_code = run_source_direct_object_async(source, "macho_uint128_neg")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports bitwise operators" {
  let source = "int main(void) { int a = 12; int b = 10; return (a & b) | (a ^ b); }"
  let exit_code = run_source_direct_object_async(source, "macho_bitwise")
  inspect(exit_code, content="14")
}

///|
async test "direct macho object supports bitwise not" {
  let source = "int main(void) { int a = 15; return ~a; }"
  let exit_code = run_source_direct_object_async(source, "macho_bitwise_not")
  inspect(exit_code, content="240")
}

///|
async test "direct macho object supports unsigned char mask immediate" {
  let source = "int main(void) { long x = 0x12345; return (unsigned char)x; }"
  let exit_code = run_source_direct_object_async(source, "macho_and_imm_u8")
  inspect(exit_code, content="69")
}

///|
async test "direct macho object supports unsigned short mask immediate" {
  let source = "int main(void) { long x = 0x12345; return (unsigned short)x; }"
  let exit_code = run_source_direct_object_async(source, "macho_and_imm_u16")
  inspect(exit_code, content="69")
}

///|
async test "direct macho object supports bitfield shift immediates" {
  let source = "struct S { signed int a:5; unsigned int b:6; }; int main(void) { struct S s; s.a = -3; s.b = 17; return s.a + s.b + 3; }"
  let exit_code = run_source_direct_object_async(
    source, "macho_bitfield_shift_immediates",
  )
  inspect(exit_code, content="17")
}

///|
async test "direct macho object supports stack store register offset" {
  let source = "int f(long a) { long pad[40]; pad[0] = 1; return (int)(a + pad[0]); } int main(void) { return f(41); }"
  let exit_code = run_source_direct_object_async(
    source, "macho_stack_store_register_offset",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports large aligned stack offsets" {
  let source = "int main(void) { long pad[80]; pad[70] = 42; return (int)pad[70]; }"
  let exit_code = run_source_direct_object_async(
    source, "macho_large_aligned_stack_offset",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports signed shifts" {
  let source = "int main(void) { int a = 3; int b = 2; return (a << b) + (16 >> b); }"
  let exit_code = run_source_direct_object_async(source, "macho_signed_shift")
  inspect(exit_code, content="16")
}

///|
async test "direct macho object supports unsigned shift mask" {
  let source = "int main(void) { unsigned int a = 16; int b = 2; return a >> b; }"
  let exit_code = run_source_direct_object_async(source, "macho_unsigned_shift")
  inspect(exit_code, content="4")
}

///|
async test "direct macho object supports bit count and byte swap builtins" {
  let source =
    #|int main(void) {
    #|  if (__builtin_clz(1) != 31) return 1;
    #|  if (__builtin_clzll(1) != 63) return 2;
    #|  if (__builtin_ctz(8) != 3) return 3;
    #|  if (__builtin_ctzll(16) != 4) return 4;
    #|  if ((__builtin_bswap32(0x01020304u) & 255) != 1) return 5;
    #|  if ((__builtin_bswap64(0x0102030405060708ull) & 255) != 1) return 6;
    #|  if (__builtin_rotateleft32(0x12345678u, 8) != 0x34567812u) return 7;
    #|  if (__builtin_rotateright32(0x12345678u, 8) != 0x78123456u) return 8;
    #|  if (__builtin_rotateleft64(0x0123456789abcdefull, 16) != 0x456789abcdef0123ull) return 9;
    #|  if (__builtin_rotateright64(0x0123456789abcdefull, 16) != 0xcdef0123456789abull) return 10;
    #|  if (__builtin_rotateleft(0x12345678u, 8) != 0x34567812u) return 11;
    #|  if ((__builtin_rotateright(0x0123456789abcdefull, 16) & 255) != 0xab) return 12;
    #|  __builtin_prefetch((void*)0, 0, 3);
    #|  return 42;
    #|}
  let exit_code = run_source_direct_object_async(source, "macho_bit_builtins")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object keeps aligned struct array pointer arithmetic address" {
  let source =
    #|struct State {
    #|  unsigned long prefix;
    #|  _Alignas(64) unsigned char buffer[256];
    #|  unsigned int bufferedSize;
    #|};
    #|
    #|int main(void) {
    #|  struct State state;
    #|  state.bufferedSize = 13;
    #|  unsigned char *p = state.buffer + state.bufferedSize;
    #|  *p = 42;
    #|  return state.buffer[13];
    #|}
  let exit_code = run_source_direct_object_async(
    source, "macho_aligned_member_ptr_arith",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object keeps aligned global byte array initializer" {
  let source =
    #|_Alignas(64) static const unsigned char secret[4] = { 1, 2, 3, 36 };
    #|
    #|int main(void) {
    #|  return secret[0] + secret[1] + secret[2] + secret[3];
    #|}
  let exit_code = run_source_direct_object_async(
    source, "macho_aligned_global_array_init",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports alloca alignment mask" {
  let source =
    #|int main(void) {
    #|  char *p = __builtin_alloca(13);
    #|  return (((long)p & 15) == 0) ? 42 : 1;
    #|}
  let exit_code = run_source_direct_object_async(source, "macho_alloca_bic")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object adjusts stack for dynamic alloca" {
  let source =
    #|int main(void) {
    #|  int n = 17;
    #|  char *a = __builtin_alloca(n);
    #|  a[0] = 40;
    #|  char *b = __builtin_alloca(n);
    #|  b[0] = 2;
    #|  return a[0] + b[0];
    #|}
  let exit_code = run_source_direct_object_async(source, "macho_alloca_sp_sub")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports darwin fd clear helper" {
  let source =
    #|struct fd_set {
    #|  int fds_bits[32];
    #|};
    #|
    #|int main(void) {
    #|  struct fd_set fds;
    #|  __builtin_bzero(&fds, sizeof(fds));
    #|  __darwin_fd_set(9, &fds);
    #|  if (!__darwin_fd_isset(9, &fds)) return 1;
    #|  __darwin_fd_clr(9, &fds);
    #|  if (__darwin_fd_isset(9, &fds)) return 2;
    #|  return 42;
    #|}
  let exit_code = run_source_direct_object_async(source, "macho_darwin_fd_bic")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports double addition and cast" {
  let source = "double add(double a, double b) { return a + b; } int main(void) { return (int)add(1.5, 2.5); }"
  let exit_code = run_source_direct_object_async(
    source, "macho_double_add_cast",
  )
  inspect(exit_code, content="4")
}

///|
async test "direct macho object supports signed integer to double cast" {
  let source = "double f(long x) { return (double)x; } int main(void) { return (int)f(42); }"
  let exit_code = run_source_direct_object_async(source, "macho_scvtf")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports unsigned integer to double cast" {
  let source = "double f(unsigned long x) { return (double)x; } int main(void) { return (int)f(42); }"
  let exit_code = run_source_direct_object_async(source, "macho_ucvtf")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports signed integer to float cast" {
  let source = "float f(long x) { return (float)x; } int main(void) { return (int)f(42); }"
  let exit_code = run_source_direct_object_async(source, "macho_scvtf_float")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports unsigned integer to float cast" {
  let source = "float f(unsigned long x) { return (float)x; } int main(void) { return (int)f(42); }"
  let exit_code = run_source_direct_object_async(source, "macho_ucvtf_float")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports float to unsigned integer cast" {
  let source = "unsigned long f(float x) { return (unsigned long)x; } int main(void) { return (int)f(42.5f); }"
  let exit_code = run_source_direct_object_async(source, "macho_fcvtzu_float")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports double comparison" {
  let source = "int main(void) { double a = 2.0; double b = 1.0; if (a > b) return 42; return 1; }"
  let exit_code = run_source_direct_object_async(source, "macho_double_cmp")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports negative compare immediates" {
  let source =
    #|long f(long x) {
    #|  return x == -1 ? 40 : 1;
    #|}
    #|
    #|int g(int x) {
    #|  return x == -1 ? 2 : 1;
    #|}
    #|
    #|int main(void) {
    #|  return (int)f(-1) + g(-1);
    #|}
  let exit_code = run_source_direct_object_async(
    source, "macho_negative_cmp_imm",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports double negation" {
  let source = "double f(double x) { return -x; } int main(void) { return (int)f(42.0) + 84; }"
  let exit_code = run_source_direct_object_async(source, "macho_double_neg")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports float to double conversion" {
  let source = "double f(float x) { return (double)x; } int main(void) { return (int)f(42.0f); }"
  let exit_code = run_source_direct_object_async(
    source, "macho_float_to_double",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports floating absolute value" {
  let source = "float f(float x) { return __builtin_fabsf(x); } double g(double x) { return __builtin_fabs(x); } int main(void) { return (int)(f(-19.5f) + g(-22.5)); }"
  let exit_code = run_source_direct_object_async(source, "macho_fabs")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports floating register offset memory" {
  let source =
    #|int main(void) {
    #|  double a[4];
    #|  int i = 2;
    #|  a[i] = 21.0;
    #|  return (int)(a[i] * 2.0);
    #|}
  let exit_code = run_source_direct_object_async(source, "macho_fp_reg_offset")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports synchronization barrier" {
  let source = "int main(void) { __sync_synchronize(); return 42; }"
  let exit_code = run_source_direct_object_async(source, "macho_dmb_ish")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports atomic load and store widths" {
  let source = "int main(void) { unsigned char b = 0; unsigned short h = 0; int w = 0; long x = 0; __atomic_store_n(&b, 1, 5); __atomic_store_n(&h, 2, 5); __atomic_store_n(&w, 3, 5); __atomic_store_n(&x, 36, 5); return __atomic_load_n(&b, 5) + __atomic_load_n(&h, 5) + __atomic_load_n(&w, 5) + (int)__atomic_load_n(&x, 5); }"
  let exit_code = run_source_direct_object_async(
    source, "macho_atomic_load_store_widths",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports exclusive atomic update loops" {
  let source =
    #|int main(void) {
    #|  _Atomic(unsigned int) x = 5;
    #|  unsigned int expected = 11;
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
    #|  if (__c11_atomic_compare_exchange_strong(&x, &expected, 21, 5, 5)) return 10;
    #|  if (expected != 19) return 11;
    #|  if (__c11_atomic_load(&x, 5) != 19) return 12;
    #|  __c11_atomic_store(&x, 42, 5);
    #|  return (int)x;
    #|}
  let exit_code = run_source_direct_object_async(
    source, "macho_exclusive_atomic_update_loops",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports negative offset loads" {
  let source =
    #|struct Pair {
    #|  long a;
    #|  long b;
    #|  long c;
    #|  long d;
    #|};
    #|
    #|struct Pair make_pair(long seed) {
    #|  struct Pair p;
    #|  p.a = seed;
    #|  p.b = seed + 1;
    #|  p.c = seed + 2;
    #|  p.d = seed + 3;
    #|  return p;
    #|}
    #|
    #|int main(void) {
    #|  struct Pair p = make_pair(39);
    #|  return (int)p.d;
    #|}
  let exit_code = run_source_direct_object_async(
    source, "macho_negative_offset_loads",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports return address builtin" {
  let source =
    #|int main(void) {
    #|  void *ra = __builtin_return_address(0);
    #|  if (ra == 0) return 1;
    #|  if (__builtin_return_address(1) != 0) return 2;
    #|  if (__builtin_extract_return_addr(ra) != ra) return 3;
    #|  if (__builtin_frob_return_addr(ra) != ra) return 4;
    #|  return 42;
    #|}
  let exit_code = run_source_direct_object_async(
    source, "macho_return_address_builtin",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports zero-argument internal call" {
  let source = "int answer(void) { return 42; } int main(void) { return answer(); }"
  let exit_code = run_source_direct_object_async(source, "macho_internal_call0")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports integer argument internal call" {
  let source = "int add(int a, int b) { return a + b; } int main(void) { return add(20, 22); }"
  let exit_code = run_source_direct_object_async(source, "macho_internal_call2")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports function pointer call" {
  let source = "int add(int x) { return x + 3; } int main(void) { int (*fp)(int) = add; return fp(39); }"
  let exit_code = run_source_direct_object_async(
    source, "macho_function_pointer_call",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports ternary conversions and fp callee" {
  let source =
    #|double add_one(double x) { return x + 1.0; }
    #|double sub_one(double x) { return x - 1.0; }
    #|double choose_double(int flag) { return flag ? 1 : 2.5; }
    #|int choose_int(int flag) { return flag ? 1.5 : 2; }
    #|double call_selected(int flag, double x) {
    #|  return (flag ? add_one : sub_one)(x);
    #|}
    #|int main(void) {
    #|  if (choose_double(1) != 1.0) return 1;
    #|  if (choose_double(0) != 2.5) return 2;
    #|  if (choose_int(1) != 1) return 3;
    #|  if (choose_int(0) != 2) return 4;
    #|  if (call_selected(1, 41.0) != 42.0) return 5;
    #|  if (call_selected(0, 43.0) != 42.0) return 6;
    #|  return 42;
    #|}
  let exit_code = run_source_direct_object_async(
    source, "macho_ternary_conversions_fp_callee",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports constant if control flow" {
  let source = "int main(void) { if (1) return 42; return 1; }"
  let exit_code = run_source_direct_object_async(source, "macho_if_const")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports comparison if control flow" {
  let source = "int main(void) { int x = 5; if (x > 3) return 42; return 1; }"
  let exit_code = run_source_direct_object_async(source, "macho_if_cmp")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports 64-bit register comparison" {
  let source = "int main(void) { long a = 4294967296L; long b = 0; return a > b ? 42 : 1; }"
  let exit_code = run_source_direct_object_async(source, "macho_cmp_x_register")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports logical or branch" {
  let source = "int main(void) { int a = 0; int b = 1; if (a || b) return 42; return 1; }"
  let exit_code = run_source_direct_object_async(source, "macho_logic_or")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports logical not compare" {
  let source = "int main(void) { int b = 0; if (!b) return 42; return 1; }"
  let exit_code = run_source_direct_object_async(source, "macho_logic_not")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports simple while loop" {
  let source = "int main(void) { int i = 0; int s = 0; while (i < 4) { s = s + i; i = i + 1; } return s; }"
  let exit_code = run_source_direct_object_async(source, "macho_while_sum")
  inspect(exit_code, content="6")
}

///|
async test "direct macho object supports switch conditional branches" {
  let source = "int f(int x) { switch (x) { case 1: return 11; case 2: return 22; default: return 7; } } int main(void) { return f(2); }"
  let exit_code = run_source_direct_object_async(source, "macho_switch_cond")
  inspect(exit_code, content="22")
}

///|
async test "direct macho object supports computed goto branch register" {
  let source =
    #|int main(void) {
    #|  static void *labels[] = { &&case0, &&case1 };
    #|  goto *labels[1];
    #|case0:
    #|  return 1;
    #|case1:
    #|  return 42;
    #|}
  let exit_code = run_source_direct_object_async(source, "macho_computed_goto")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object links initialized global data section" {
  let source = "int g = 42; char name[] = \"kimicc\"; int main(void) { return 7; }"
  let exit_code = run_source_direct_object_async(
    source, "macho_initialized_global_data",
  )
  inspect(exit_code, content="7")
}

///|
async test "direct macho object links zero-filled global data section" {
  let source = "int g; char scratch[32]; int main(void) { return 9; }"
  let exit_code = run_source_direct_object_async(
    source, "macho_zero_global_data",
  )
  inspect(exit_code, content="9")
}

///|
async test "direct macho object supports initialized global read relocation" {
  let source = "int g = 40; int main(void) { return g + 2; }"
  let exit_code = run_source_direct_object_async(source, "macho_global_read")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports zero global write relocation" {
  let source = "int g; int main(void) { g = 42; return g; }"
  let exit_code = run_source_direct_object_async(source, "macho_global_write")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports char global write relocation" {
  let source = "char g; int main(void) { g = 42; return g; }"
  let exit_code = run_source_direct_object_async(source, "macho_char_global")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports short global write relocation" {
  let source = "short g; int main(void) { g = 42; return g; }"
  let exit_code = run_source_direct_object_async(source, "macho_short_global")
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports string literal page relocation" {
  let source = "int main(void) { char *s = \"x\"; return 7; }"
  let exit_code = run_source_direct_object_async(source, "macho_string_page")
  inspect(exit_code, content="7")
}

///|
async test "direct macho object supports string literal byte load" {
  let source = "int main(void) { char *s = \"x\"; return s[0]; }"
  let exit_code = run_source_direct_object_async(source, "macho_string_byte")
  inspect(exit_code, content="120")
}

///|
async test "direct macho object keeps 2D array row decay as address" {
  let source =
    #|int main(void) {
    #|  int matrix[2][3];
    #|  int *row;
    #|  matrix[0][0] = 1; matrix[0][1] = 2; matrix[0][2] = 3;
    #|  matrix[1][0] = 4; matrix[1][1] = 5; matrix[1][2] = 6;
    #|  row = matrix[1];
    #|  if (row != &matrix[1][0]) return 1;
    #|  return row[0] + row[2];
    #|}
  let exit_code = run_source_direct_object_async(source, "macho_2d_row_decay")
  inspect(exit_code, content="10")
}

///|
async test "direct macho object calls parenthesized extern function declarator" {
  let source =
    #|extern int (putchar)(int);
    #|int main(void) {
    #|  return putchar(65) == 65 ? 42 : 1;
    #|}
  let exit_code = run_source_direct_object_async(
    source, "macho_parenthesized_extern_call",
  )
  inspect(exit_code, content="42")
}

///|
async test "direct macho object supports data pointer relocation" {
  let source = "char *g = \"x\"; int main(void) { return g[0]; }"
  let exit_code = run_source_direct_object_async(source, "macho_data_pointer")
  inspect(exit_code, content="120")
}

///|
async test "direct macho object supports data pointer relocation addend" {
  let source = "static unsigned char table[4] = {1, 40, 9, 2}; unsigned char *p = &table[1]; int main(void) { return *p; }"
  let exit_code = run_source_direct_object_async(
    source, "macho_data_pointer_addend",
  )
  inspect(exit_code, content="40")
}

///|
async test "direct macho object supports external branch relocation" {
  let source = "int putchar(int); int main(void) { return putchar(65); }"
  let exit_code = run_source_direct_object_async(source, "macho_external_bl")
  inspect(exit_code, content="65")
}

///|
async test "direct macho object runs fixture matrix" {
  let fixtures : Array[DirectObjectFixture] = [
    { path: "test/run_fixtures/add.c", tag: "fixture_add", expected: 7 },
    { path: "test/run_fixtures/arrays.c", tag: "fixture_arrays", expected: 3 },
    {
      path: "test/run_fixtures/bitwise.c",
      tag: "fixture_bitwise",
      expected: 255,
    },
    {
      path: "test/run_fixtures/for_loop.c",
      tag: "fixture_for_loop",
      expected: 15,
    },
    {
      path: "test/run_fixtures/funcall.c",
      tag: "fixture_funcall",
      expected: 25,
    },
    { path: "test/run_fixtures/globals.c", tag: "fixture_globals", expected: 2 },
    {
      path: "test/run_fixtures/if_else.c",
      tag: "fixture_if_else",
      expected: 20,
    },
    { path: "test/run_fixtures/logic.c", tag: "fixture_logic", expected: 3 },
    {
      path: "test/run_fixtures/pointers.c",
      tag: "fixture_pointers",
      expected: 50,
    },
    {
      path: "test/run_fixtures/prepost.c",
      tag: "fixture_prepost",
      expected: 24,
    },
    {
      path: "test/run_fixtures/return_42.c",
      tag: "fixture_return_42",
      expected: 42,
    },
    { path: "test/run_fixtures/struct.c", tag: "fixture_struct", expected: 7 },
    {
      path: "test/run_fixtures/switch_case.c",
      tag: "fixture_switch_case",
      expected: 30,
    },
    {
      path: "test/run_fixtures/ternary.c",
      tag: "fixture_ternary",
      expected: 10,
    },
    {
      path: "test/run_fixtures/while_loop.c",
      tag: "fixture_while_loop",
      expected: 10,
    },
    { path: "test/fixtures/hello.c", tag: "fixture_hello", expected: 6 },
    {
      path: "test/fixtures/var_decls.c",
      tag: "fixture_var_decls",
      expected: 100,
    },
    { path: "test/fixtures/switch.c", tag: "fixture_switch", expected: 20 },
    {
      path: "test/fixtures/pointers.c",
      tag: "fixture_pointers_full",
      expected: 50,
    },
    {
      path: "test/fixtures/c4_stripped.c",
      tag: "fixture_c4_stripped_usage",
      expected: 255,
    },
  ]
  for fixture in fixtures {
    let source = @fs.read_file(fixture.path).text()
    let exit_code = run_source_direct_object_async(source, fixture.tag)
    inspect(exit_code, content=fixture.expected.to_string())
  }
}

///|
async test "direct macho object runs preprocessed c4 smoke program" {
  let source = preprocess_c_file(
    "test/fixtures/c4_stripped.c", "fixture_c4_direct_preprocessed",
  )
  let obj_path = compile_source_to_direct_object_path(
    source, "fixture_c4_preprocessed_direct",
  )
  let bin_path = temp_file_path(
    "fixture_c4_preprocessed_direct_bin", source, "",
  )
  run_command_checked(
    "clang -o " + shell_quote(bin_path) + " " + shell_quote(obj_path),
    "link direct object fixture_c4_preprocessed_direct",
  )
  let input_path = temp_file_path("fixture_c4_smoke_input", source, ".c")
  write_text_file(input_path, "int main() { return 42; }\n")
  let result = run_command_capture(
    shell_quote(bin_path) + " " + shell_quote(input_path),
    "fixture_c4_preprocessed_direct_run",
  )
  if result.code != 42 || !result.output.contains("exit(42) cycle = 5") {
    abort(
      "preprocessed c4 direct-object smoke failed with code " +
      result.code.to_string() +
      "\n" +
      result.output,
    )
  }
}

///|
async test "direct macho object links and runs sqlite basic api smoke" {
  let driver =
    #|#include "sqlite3.h"
    #|#include <stdio.h>
    #|
    #|int main(void) {
    #|  sqlite3 *db = 0;
    #|  char *err = 0;
    #|  int rc = sqlite3_open(":memory:", &db);
    #|  if (rc != SQLITE_OK) {
    #|    printf("open rc=%d err=%s\n", rc, db ? sqlite3_errmsg(db) : "null");
    #|    return 1;
    #|  }
    #|  rc = sqlite3_exec(db, "select 1;", 0, 0, &err);
    #|  if (rc != SQLITE_OK) {
    #|    printf("exec rc=%d err=%s\n", rc, err ? err : sqlite3_errmsg(db));
    #|    sqlite3_free(err);
    #|    sqlite3_close(db);
    #|    return 2;
    #|  }
    #|  sqlite3_close(db);
    #|  printf("sqlite-direct-ok\n");
    #|  return 0;
    #|}
  let result = run_driver_with_direct_sqlite_object(
    driver, "sqlite_direct_basic_api",
  )
  if result.code != 0 {
    abort("SQLite direct-object basic API smoke failed:\n" + result.output)
  }
  assert_true(result.output.contains("sqlite-direct-ok"))
}
