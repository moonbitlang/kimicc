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
async test "direct macho object supports double comparison" {
  let source = "int main(void) { double a = 2.0; double b = 1.0; if (a > b) return 42; return 1; }"
  let exit_code = run_source_direct_object_async(source, "macho_double_cmp")
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
