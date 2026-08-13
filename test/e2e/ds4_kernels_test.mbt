///|
/// CI-safe gates for the ds4 kernel generator: the printed program is the
/// parser's own image (canonical form), and the emitted C is accepted by
/// clang. The bit-exact referee against ds4's kernels needs the ds4
/// checkout and the 81GB checkpoint and lives in
/// `ds4_kernels_real_test.mbt`; these checks run everywhere.
async test "ds4 kernel generator emits canonical C that clang accepts" {
  let cfg : @ds4_kernels.Config = {
    q8_dims: [64, 33],
    q2k_dims: [256],
    iq2_dims: [256],
  }
  let src = @ds4_kernels.generate_kernels(cfg)
  // A parse error propagates as a failure: emitting something the parser
  // rejects breaks the canonical-form contract by itself.
  let program = @parser.parse(src)
  assert_eq(@printer.print_program(program), src)
  let full = "#include <string.h>\n" + src
  let path = temp_file_path("ds4_kernels_gate", full, ".c")
  write_text_file(path, full)
  run_command_checked(
    "clang -fsyntax-only -ferror-limit=0 " + path,
    "clang gate on generated ds4 kernels",
  )
}

///|
/// The round-trip property over random widths, quickcheck-style with a
/// fixed seed: whatever dimensions a model brings, the generator's output
/// stays inside the parser's image. IQ2_XXS widths are exercised in the
/// gate test above and the referee; here they stay empty so the 262144-
/// entry sign table is not rebuilt hundreds of times.
test "ds4 kernels round-trip through print and parse for arbitrary widths" {
  let state = @splitmix.new(seed=20260813)
  for case_index in 0..<40 {
    let q8_a = 1 + (state.next_uint() % 96).reinterpret_as_int()
    let q8_b = 1 + (state.next_uint() % 96).reinterpret_as_int()
    let q2k = 256 * (1 + (state.next_uint() % 2).reinterpret_as_int())
    let cfg : @ds4_kernels.Config = {
      q8_dims: if q8_a == q8_b {
        [q8_a]
      } else {
        [q8_a, q8_b]
      },
      q2k_dims: [q2k],
      iq2_dims: [],
    }
    let src = @ds4_kernels.generate_kernels(cfg)
    let program = @parser.parse(src)
    if @printer.print_program(program) != src {
      fail(
        "round-trip failed at case \{case_index} for widths \{q8_a}/\{q8_b}/\{q2k}",
      )
    }
  }
}
