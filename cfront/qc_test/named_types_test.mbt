///|
/// The `Named` round trip on a realistic NEON kernel shape: the printer
/// emits registered spellings verbatim, `parse_with_named_types` reads
/// them back, and the reparse is the same tree with the same text -- the
/// contract an emitted intrinsics kernel depends on.
test "named types round-trip when their spellings are registered" {
  let source =
    #|static float sum4(float *x) {
    #|  float32x4_t acc = vdupq_n_f32(0.0f);
    #|  for (int i = 0; i < 64; i += 4) {
    #|    acc = vfmaq_f32(acc, vld1q_f32(x + i), vld1q_f32(x + i));
    #|  }
    #|  return vaddvq_f32(acc);
    #|}
    #|
  let names = ["float32x4_t"]
  let program = @parser.parse_with_named_types(source, names)
  let printed = @printer.print_program(program)
  assert_true(printed.contains("float32x4_t acc"))
  let reparsed = @parser.parse_with_named_types(printed, names)
  assert_eq(reparsed, program)
  assert_eq(@printer.print_program(reparsed), printed)
}

///|
/// Named types compose with the declarator forms a kernel signature
/// needs: pointer parameters, pointer locals, and casts.
test "named types print and reparse through pointers and casts" {
  let names = ["float32x4_t", "uint3"]
  let program = @build.program(decls=[
    @build.func(
      Void,
      "k",
      [
        @build.param(Pointer(Named("float32x4_t")), "v"),
        @build.param(Named("uint3"), "tid"),
      ],
      [
        @build.decl(
          Pointer(Named("float32x4_t")),
          "p",
          init=@build.cast(Pointer(Named("float32x4_t")), @build.v("v")),
        ),
        @build.ret(),
      ],
      is_static=true,
    ),
  ])
  let printed = @printer.print_program(program)
  assert_true(printed.contains("static void k(float32x4_t *v, uint3 tid)"))
  let reparsed = @parser.parse_with_named_types(printed, names)
  assert_eq(reparsed, program)
}

///|
/// `for_range` counter types round-trip: suffix-spellable types carry
/// their own zero literal (`0uLL`), while the rest -- here `unsigned
/// char` -- initialize from a plain `int` zero, because that is the only
/// literal type the reparse can recover from the spelling `0`.
test "for_range counters round-trip for wide and narrow types" {
  for ty in ([ULongLong, UChar, SInt] : Array[@ctype.Type]) {
    let program = @build.program(decls=[
      @build.func(
        Void,
        "walk",
        [@build.param(Pointer(Float), "x")],
        [
          @build.for_range(
            "i",
            @parser.int_literal(8, SInt),
            [
              ExprStmt(
                Assign(
                  ArrayAccess(Var("x"), Var("i")),
                  @parser.float_literal(0.0),
                ),
              ),
            ],
            ty~,
          ),
          @build.ret(),
        ],
        is_static=true,
      ),
    ])
    let printed = @printer.print_program(program)
    let reparsed = @parser.parse(printed)
    assert_eq(reparsed, program)
  }
}
