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
