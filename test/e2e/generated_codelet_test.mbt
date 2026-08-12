///|
/// The construction API, proven the way its consumer would use it: a MoonBit
/// program builds an FFT codelet -- the FFTW shape, straight-line arithmetic
/// over strided arrays -- prints it, and clang compiles it next to a
/// hand-written reference. Both run over the same inputs and must agree to
/// within float tolerance.
///
/// The codelet is a radix-2 decimation-in-time butterfly with a twiddle
/// factor applied to the odd input:
///
///   tr = wr*ri[rs] - wi*ii[rs]        (complex twiddle multiply)
///   ti = wr*ii[rs] + wi*ri[rs]
///   ro[0]  = ri[0] + tr;  io[0]  = ii[0] + ti
///   ro[os] = ri[0] - tr;  io[os] = ii[0] - ti
fn generated_butterfly() -> @parser.Program {
  let dbl : @ctype.Type = Double
  let dptr : @ctype.Type = Pointer(Double)
  let ri = @build.v("ri")
  let ii = @build.v("ii")
  let ro = @build.v("ro")
  let io = @build.v("io")
  let rs = @build.v("rs")
  let os = @build.v("os")
  let wr = @build.v("wr")
  let wi = @build.v("wi")
  let zero = @parser.int_literal(0, SInt)
  let body : Array[@parser.Stmt] = [
    @build.decl(dbl, "t1", init=ri[zero]),
    @build.decl(dbl, "t2", init=ii[zero]),
    @build.decl(dbl, "t3", init=ri[rs]),
    @build.decl(dbl, "t4", init=ii[rs]),
    // The twiddle multiply, written as the math reads.
    @build.decl(dbl, "tr", init=wr * @build.v("t3") - wi * @build.v("t4")),
    @build.decl(dbl, "ti", init=wr * @build.v("t4") + wi * @build.v("t3")),
    @build.assign(ro[zero], @build.v("t1") + @build.v("tr")),
    @build.assign(io[zero], @build.v("t2") + @build.v("ti")),
    @build.assign(ro[os], @build.v("t1") - @build.v("tr")),
    @build.assign(io[os], @build.v("t2") - @build.v("ti")),
  ]
  @build.program(decls=[
    @build.func(
      Void,
      "bfly2",
      [
        @build.param(dptr, "ri"),
        @build.param(dptr, "ii"),
        @build.param(dptr, "ro"),
        @build.param(dptr, "io"),
        @build.param(SInt, "rs"),
        @build.param(SInt, "os"),
        @build.param(Double, "wr"),
        @build.param(Double, "wi"),
      ],
      body,
    ),
  ])
}

///|
/// The generated codelet agrees with a hand-written reference at runtime,
/// and the generated text round-trips through the parser.
async test "generated butterfly codelet matches a handwritten reference" {
  let program = generated_butterfly()
  let printed = @printer.print_program(program)
  // The construction API emits the canonical form: reparse equality holds.
  assert_eq(@parser.parse(printed), program)
  let harness =
    #|#include <stdio.h>
    #|#include <math.h>
    #|static void reference(double *ri, double *ii, double *ro, double *io,
    #|                      int rs, int os, double wr, double wi) {
    #|  double tr = wr * ri[rs] - wi * ii[rs];
    #|  double ti = wr * ii[rs] + wi * ri[rs];
    #|  ro[0] = ri[0] + tr; io[0] = ii[0] + ti;
    #|  ro[os] = ri[0] - tr; io[os] = ii[0] - ti;
    #|}
    #|int main(void) {
    #|  double wr = 0.7071067811865476, wi = -0.7071067811865475;
    #|  int bad = 0;
    #|  for (int trial = 0; trial < 64; trial++) {
    #|    double ri[8], ii[8], ro_a[8] = {0}, io_a[8] = {0};
    #|    double ro_b[8] = {0}, io_b[8] = {0};
    #|    for (int i = 0; i < 8; i++) {
    #|      ri[i] = sin(trial * 1.7 + i * 0.3);
    #|      ii[i] = cos(trial * 0.9 - i * 1.1);
    #|    }
    #|    bfly2(ri, ii, ro_a, io_a, 3, 2, wr, wi);
    #|    reference(ri, ii, ro_b, io_b, 3, 2, wr, wi);
    #|    for (int i = 0; i < 8; i++) {
    #|      if (fabs(ro_a[i] - ro_b[i]) > 1e-12 ||
    #|          fabs(io_a[i] - io_b[i]) > 1e-12) bad++;
    #|    }
    #|  }
    #|  printf("bad=%d\n", bad);
    #|  return bad == 0 ? 0 : 1;
    #|}
  let source = printed + "\n" + harness
  let source_path = temp_file_path("codelet", source, ".c")
  let bin_path = temp_file_path("codelet_bin", source, "")
  write_text_file(source_path, source)
  run_command_checked(
    "clang -O2 -o " + shell_quote(bin_path) + " " + shell_quote(source_path),
    "compile generated codelet",
  )
  let result = run_command_capture(shell_quote(bin_path), "codelet_run")
  assert_eq(result.code, 0)
  assert_true(result.output.contains("bad=0"))
}
