///|
/// Prelude for the optional C-compiler check: typedefs for the named types
/// the generators use, which the printer emits by spelling alone.
let cc_prelude : String =
  #|typedef float float32x4_t __attribute__((vector_size(16)));
  #|typedef int int32x4_t __attribute__((vector_size(16)));
  #|typedef struct { unsigned x, y, z; } uint3;
  #|

///|
/// `expr` with every variable replaced by a literal and every divisor by
/// `1`: a constant expression.
fn constant_expr(expr : @parser.Expr) -> @parser.Expr {
  match expr {
    Var(_) => @parser.int_literal(1, SInt)
    // A constant division by zero is not a constant expression either.
    Binary("/" | "%" as op, a, _) =>
      Binary(op, constant_expr(a), @parser.int_literal(1, SInt))
    Binary(op, a, b) => Binary(op, constant_expr(a), constant_expr(b))
    Unary(op, a) => Unary(op, constant_expr(a))
    Ternary(c, t, e) =>
      Ternary(constant_expr(c), constant_expr(t), constant_expr(e))
    other => other
  }
}

///|
/// Marks the start of one emitted program in the test output.
let cc_marker : String = "/*@@cfront-qc@@*/"

///|
/// Emits generated programs for `qc_test/cc_check.sh`, which compiles each
/// one with the system C compiler: printed output must be C that another
/// compiler accepts, which the round-trip properties -- judged by this
/// project's own parser -- cannot establish. Two corpora:
///
/// - `GenProgram`s from `gen_test.mbt`, which are well typed, printed
///   whole;
/// - `SynProgram`s from `syntax_gen_test.mbt` reduced to their
///   declarations (globals and prototypes, no bodies), whose declarators
///   cover pointers, arrays, function pointers returning function pointers
///   and atomic pointers. Their bodies are not well typed, so they are
///   dropped. Programs spelling `__float128` are skipped: arm64 Clang has
///   no such type.
///
/// Skipped in the default run, since it needs a compiler and a shell.
#skip("emits programs for qc_test/cc_check.sh")
test "emit generated programs for a C compiler" {
  let state = @splitmix.new(seed=20260928)
  for i in 0..<150 {
    let program = gen_program(4 + i % 9, state)
    // File-scope initializers must be constant in C; the generator lets
    // them name earlier globals, so fold those names to a literal. And a
    // `for` step with no counter in scope names `v_missing`; skip those.
    let globals = program.globals.map(global => {
      ..global,
      init: global.init.map(init => {
        match init {
          Scalar(e) => Scalar(constant_expr(e))
          other => other
        }
      }),
    })
    let text = @printer.print_program({ ..program, globals, })
    if text.contains("v_missing") {
      continue
    }
    println(cc_marker)
    println(cc_prelude + text)
  }
  for i in 0..<150 {
    let program = gen_syn_program(3 + i % 8, state)
    let declarations = syn_rebuild(
      program.globals,
      program.decls.map(decl => { ..decl, body: None, }),
    )
    let text = @printer.print_program(declarations)
    if text.contains("__float128") {
      continue
    }
    println(cc_marker)
    println(cc_prelude + text)
  }
  println(cc_marker)
}
