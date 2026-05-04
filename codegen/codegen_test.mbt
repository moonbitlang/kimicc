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

test "collect locals with array init" {
  let source =
    #|int main() {
    #|    char buf[16];
    #|    char *p;
    #|    char src[] = "abcd";
    #|    char dst[8];
    #|    char buf2[8];
    #|    char buf3[6];
    #|    return 0;
    #|}
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let _ = codegen.generate(prog)
  // Just check it doesn't crash; the real check is in the assembly
}

///|
test "generate double literal return" {
  let source = "double foo() { return 3.14; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("_foo:"), content="true")
  inspect(assembly.contains("_fp_lit_foo_0:"), content="true")
  inspect(assembly.contains(".double\t3.14"), content="true")
  inspect(assembly.contains("fmov\td0, x9"), content="true")
}

///|
test "generate double local init" {
  let source = "double foo() { double x = 2.5; return x; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains(".double\t2.5"), content="true")
}

///|
test "generate float literal" {
  let source = "float foo() { return 1.5; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fmov\ts0, w9"), content="true")
}

///|
test "generate mixed int double params" {
  let source = "double foo(int a, double b, int c, double d) { return d; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  // Callee should store from x0, d0, x1, d1
  inspect(assembly.contains("str\tx0, [x29, #-32]"), content="true")
  inspect(assembly.contains("str\td0, [x29, #-24]"), content="true")
  inspect(assembly.contains("str\tx1, [x29, #-16]"), content="true")
  inspect(assembly.contains("str\td1, [x29, #-8]"), content="true")
}

///|
test "generate mixed int double args in call" {
  let source = "double foo(int a, double b); double bar() { return foo(1, 2.0); }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  // Caller should pass int in x0, double in d0
  inspect(assembly.contains("mov\tx0, x9"), content="true")
  inspect(assembly.contains("fmov\td0, x9"), content="true")
  // After call, should move return from d0
  inspect(assembly.contains("fmov\tx9, d0"), content="true")
}

///|
test "generate double addition" {
  let source = "double foo(double a, double b) { return a + b; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fadd\td9, d9, d10"), content="true")
}

///|
test "generate double subtraction" {
  let source = "double foo(double a, double b) { return a - b; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fsub\td9, d9, d10"), content="true")
}

///|
test "generate double multiplication" {
  let source = "double foo(double a, double b) { return a * b; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fmul\td9, d9, d10"), content="true")
}

///|
test "generate double division" {
  let source = "double foo(double a, double b) { return a / b; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fdiv\td9, d9, d10"), content="true")
}

///|
test "generate double negation" {
  let source = "double foo(double a) { return -a; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fneg\td9, d9"), content="true")
}

///|
test "generate double comparison" {
  let source = "int foo(double a, double b) { return a < b; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fcmp\td9, d10"), content="true")
  inspect(assembly.contains("cset\tx9, mi"), content="true")
}

///|
test "generate int to double cast" {
  let source = "double foo(int a) { return (double)a; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("scvtf\td9, x9"), content="true")
  inspect(assembly.contains("fmov\tx9, d9"), content="true")
}

///|
test "generate double to int cast" {
  let source = "int foo(double a) { return (int)a; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fcvtzs\tx9, d9"), content="true")
}

///|
test "generate float to double cast" {
  let source = "double foo(float a) { return (double)a; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fcvt\td9, s9"), content="true")
}

///|
test "generate double to float cast" {
  let source = "float foo(double a) { return (float)a; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fcvt\ts9, d9"), content="true")
}

///|
test "generate builtin fabs" {
  let source = "double foo(double a) { return __builtin_fabs(a); }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fabs\td9, d9"), content="true")
}

///|
test "generate builtin fabsf" {
  let source = "float foo(float a) { return __builtin_fabsf(a); }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fabs\ts9, s9"), content="true")
}

///|
test "generate builtin nanf" {
  let source = "float foo() { return __builtin_nanf(\"\"); }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("movz\tw9, #0x7FC0, lsl #16"), content="true")
}

///|
test "generate builtin huge_valf" {
  let source = "float foo() { return __builtin_huge_valf(); }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("movz\tw9, #0x7F80, lsl #16"), content="true")
}
