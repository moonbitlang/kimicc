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
  ]
  for fixture in fixtures {
    let source = @fs.read_file(fixture.path).text()
    let exit_code = run_source_direct_object_async(source, fixture.tag)
    inspect(exit_code, content=fixture.expected.to_string())
  }
}
