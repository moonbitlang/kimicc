///|
test "generate simple function" {
  let source = "int main() { return 42; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  let expected =
    #|	.section	__TEXT,__text,regular,pure_instructions
    #|	.build_version macos, 14, 0
    #|	.globl	_main
    #|	.p2align	2
    #|_main:
    #|	stp	x29, x30, [sp, #-16]!
    #|	mov	x29, sp
    #|	mov	x9, #42
    #|	mov	x0, x9
    #|	b	_main_ret
    #|	mov	x0, #0
    #|_main_ret:
    #|	ldp	x29, x30, [sp], #16
    #|	ret
    #|
  inspect(assembly, content=expected)
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
