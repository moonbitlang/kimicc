///|
test "generate simple function" {
  let source = "int main() { return 42; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("_main:"), content="true")
  inspect(assembly.contains("\tmov\tx9, #42"), content="true")
  inspect(assembly.contains("\tret"), content="true")
}

///|
test "generate function with params" {
  let source = "int add(int a, int b) { return a + b; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("_add:"), content="true")
  inspect(assembly.contains("add\tx9, x9, x10"), content="true")
}

///|
test "generate if statement" {
  let source = "int main() { if (1) return 2; else return 3; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("cbz\tx9,"), content="true")
  inspect(assembly.contains("b\tL"), content="true")
}

///|
test "generate while loop" {
  let source = "int main() { while (1) return 0; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains(":"), content="true")
}

///|
test "generate large constant" {
  let source = "int main() { return 1114111; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  // 1114111 = 0x10FFFF → movz + movk
  inspect(assembly.contains("movz\tx9, #65535"), content="true")
  inspect(assembly.contains("movk\tx9, #16, lsl #16"), content="true")
}

///|
test "generate negative large constant" {
  let source = "int main() { return -1640562687; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  // Parsed as Unary("-", Number(1640562687)) → load then neg
  // 1640562687 = 0x61C8FFFF: low=65535, high=25032
  inspect(assembly.contains("movz\tx9, #65535"), content="true")
  inspect(assembly.contains("movk\tx9, #25032, lsl #16"), content="true")
  inspect(assembly.contains("neg\tx9, x9"), content="true")
}

///|
test "generate switch statement" {
  let source = "int main() { int x = 2; switch (x) { case 1: return 10; case 2: return 20; default: return 0; } }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  // No label in the assembly should contain a space
  let lines = assembly.split("\n")
  for line in lines {
    let s = line.to_string()
    // Labels end with ':'
    if s.ends_with(":") && s.contains(" ") {
      abort("Label contains space: " + s)
    }
  }
}

///|
test "goto labels are scoped per function" {
  let source =
    #|int foo() {
    #|  goto fail;
    #|fail:
    #|  return 1;
    #|}
    #|int bar() {
    #|  goto fail;
    #|fail:
    #|  return 2;
    #|}
    #|int main() { return foo() + bar(); }
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  // Each function's fail label should be prefixed with function name
  inspect(assembly.contains("_foo_label_fail:"), content="true")
  inspect(assembly.contains("_bar_label_fail:"), content="true")
  // Must not have a global unqualified _label_fail
  inspect(assembly.contains("\n_label_fail:"), content="false")
}
