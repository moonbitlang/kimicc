///|
/// The add2 kernel from the plan discussion, spelled exactly: ds4's
/// smallest Metal kernel with the dimension baked, which is the shape
/// the L4 rung generates.
fn add2_kernel() -> Kernel {
  let a = @build.v("a")
  let b = @build.v("b")
  let out = @build.v("out")
  let i = @build.v("i")
  {
    qualifier: "kernel",
    decl: @build.func(
      Void,
      "gen_add2_f32_4096",
      [
        @build.param(Pointer(Float), "a"),
        @build.param(Pointer(Float), "b"),
        @build.param(Pointer(Float), "out"),
        @build.param(Named("uint"), "i"),
      ],
      [
        If(i.ge(@parser.int_literal(4096, UInt)), Return(None), None),
        @build.assign(out[i], a[i] + b[i]),
      ],
    ),
    decor: [
      decor("device const"),
      decor("device const"),
      decor("device"),
      decor("", attr="[[thread_position_in_grid]]"),
    ],
  }
}

///|
/// The printed form is the MSL from the design discussion, word for
/// word: decorated single-line signature, C body.
test "print_kernel spells the add2 kernel as designed" {
  let printed = print_kernel(add2_kernel())
  // The bare then-branch is the C printer's canonical spelling for an
  // unbraced single-statement branch (trailing space included).
  let expected = "kernel void gen_add2_f32_4096(" +
    "device const float *a, device const float *b, device float *out, " +
    "uint i [[thread_position_in_grid]]) {\n" +
    "  if (i >= 4096u) \n" +
    "    return;\n" +
    "  out[i] = a[i] + b[i];\n" +
    "}"
  assert_eq(printed, expected)
}

///|
/// The decoration bridge reads back exactly what the printer wrote:
/// qualifier, decorations, and the C declaration underneath, with the
/// reprint a fixed point -- the same round-trip contract the C side
/// holds, restored for the dialect.
test "printed kernels round-trip through the decoration bridge" {
  let k = add2_kernel()
  let printed = print_kernel(k)
  let back = parse_kernel(printed, ["uint"])
  assert_eq(back, k)
  assert_eq(print_kernel(back), printed)
}

///|
/// The round trip over randomized decorations and widths, splitmix-style
/// with a fixed seed: whatever mix of address spaces and attributes the
/// generator attaches, the bridge recovers the same kernel.
test "random decorations round-trip through the bridge" {
  let spaces : ReadOnlyArray[String] = [
    "", "device", "device const", "constant", "threadgroup",
  ]
  let attrs : ReadOnlyArray[String] = [
    "", "[[thread_position_in_grid]]", "[[threadgroup(0)]]", "[[buffer(2)]]",
  ]
  let state = @splitmix.new(seed=20260813)
  for case_index in 0..<60 {
    let width = 32 * (1 + (state.next_uint() % 128).reinterpret_as_int())
    let n_params = 1 + (state.next_uint() % 4).reinterpret_as_int()
    let params : Array[@parser.Param] = []
    let decors : Array[ParamDecor] = []
    for p in 0..<n_params {
      let name = "p" + p.to_string()
      if state.next_uint() % 4 == 0 {
        params.push(@build.param(Named("uint"), name))
      } else {
        params.push(@build.param(Pointer(Float), name))
      }
      decors.push({
        space: spaces[(state.next_uint() % 5).reinterpret_as_int()],
        attr: attrs[(state.next_uint() % 4).reinterpret_as_int()],
      })
    }
    let k : Kernel = {
      qualifier: "kernel",
      decl: @build.func(Void, "k" + case_index.to_string(), params, [
        If(
          @build.v("p0").ge(@parser.int_literal(width.to_int64(), UInt)),
          Return(None),
          None,
        ),
        @build.ret(),
      ]),
      decor: decors,
    }
    let printed = print_kernel(k)
    let back = parse_kernel(printed, ["uint"])
    if back != k {
      fail("round-trip failed at case \{case_index}:\n\{printed}")
    }
    if print_kernel(back) != printed {
      fail("reprint diverged at case \{case_index}:\n\{printed}")
    }
  }
}

///|
/// Hand-written MSL beyond the phase-1 subset fails with a diagnostic
/// rather than a misread: a reference parameter is not something this
/// package prints, so the C parser under the bridge rejects it.
test "reference parameters are rejected, not misread" {
  let source = "kernel void f(constant Args &args) { return; }"
  try parse_kernel(source, []) |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("expected the reference parameter to be rejected")
  }
}

///|
/// The three failure shapes codex round 1 named, pinned: an unterminated
/// attribute raises rather than aborting; a translation unit smuggling
/// extra declarations past the single kernel is rejected; and a
/// non-Compound body prints braced, never as `kernel void f() return;`.
test "bridge failures raise and stray declarations are rejected" {
  try
    parse_kernel("kernel void f(device float *x [[buffer(0)) { return; }", [])
    |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected the unterminated attribute to raise")
  }
  try
    parse_kernel("kernel void f(void) { return; } int leaked;", []) |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected the stray global to be rejected")
  }
  // A prototype and a storage-class flag are both shapes the printer
  // could not reproduce; the bridge rejects them up front, so a
  // successful parse is always printable.
  try parse_kernel("kernel void f(void);", []) |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("expected the prototype to be rejected")
  }
  try
    parse_kernel("kernel static void f(void) { return; }", []) |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected the static kernel to be rejected")
  }
}

///|
/// Round 3's counterexamples, pinned: a trailing typedef cannot vanish
/// silently, and `(void)` round-trips as the empty parameter list.
test "trailing declarations are rejected and void lists round-trip" {
  try
    parse_kernel("kernel void f(void) { return; } typedef int Hidden;", [])
    |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected the trailing typedef to be rejected")
  }
  let k = parse_kernel("kernel void f(void) { return; }", [])
  assert_eq(k.decl.params.length(), 0)
  assert_eq(k.decor.length(), 0)
  let printed = print_kernel(k)
  assert_eq(parse_kernel(printed, []), k)
}

///|
/// Round 4's counterexamples, pinned: a brace inside a string literal is
/// text, not structure; a normalized-away `void x` parameter is a parse
/// failure rather than a later abort; and a non-stage qualifier never
/// strips.
test "string braces, named void, and non-stage qualifiers" {
  let str_kernel = parse_kernel(
    "kernel void f(device char *s) {\n  s[0] = '}';\n}",
    [],
  )
  assert_eq(print_kernel(str_kernel).contains("'}'"), true)
  try parse_kernel("kernel void f(void x) { return; }", []) |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("expected the named void parameter to be rejected")
  }
  try parse_kernel("static void f(void) { return; }", []) |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("expected the non-stage qualifier to be rejected")
  }
}

///|
/// Round 5's counterexamples, pinned: reversed attribute delimiters and
/// declarations smuggled into the head both raise diagnostics.
test "reversed delimiters and head declarations are rejected" {
  try
    parse_kernel("kernel void f(float *x ]] [[bad) { return; }", []) |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected reversed delimiters to raise")
  }
  try
    parse_kernel("kernel typedef int X; void f(void) { return; }", []) |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected the hidden typedef to be rejected")
  }
}

///|
/// Round 6, pinned: a kernel that returns non-void is rejected on both
/// sides of the bridge -- which also forecloses return declarators whose
/// abstract spelling cannot carry the function name.
test "non-void kernel returns are rejected" {
  try
    parse_kernel("kernel float f(void) { return 1.0f; }", []) |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected the non-void return to be rejected")
  }
}

///|
/// Round 8, pinned: MSL `auto` and source-level array parameters are
/// both silent-retype traps in the C parser, so the bridge rejects them
/// before parsing.
test "auto and array parameters are rejected before the C parse" {
  try
    parse_kernel("kernel void f(device float *x) { auto y = x[0]; }", [])
    |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected auto to be rejected")
  }
  try
    parse_kernel("kernel void f(device float x[4]) { return; }", []) |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected the array parameter to be rejected")
  }
}

///|
/// Round 9, pinned: the two over-rejections of round 8 corrected. A
/// quoted `auto` is text, not a token; a pointer-to-array parameter does
/// not decay and round-trips, while an outer array still rejects.
test "quoted auto and pointer-to-array parameters round-trip" {
  let quoted = parse_kernel(
    "kernel void f(device char *s) {\n  s[0] = 'a';\n  auto_helper(s);\n}",
    [],
  )
  assert_eq(print_kernel(quoted).contains("auto_helper"), true)
  // Pointer-to-array left the subset when parameters closed over the
  // shapes real MSL kernels take; it now rejects like any bracket form.
  try
    parse_kernel("kernel void f(device float (*p)[4]) { return; }", [])
    |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected the pointer-to-array parameter to be rejected")
  }
}

///|
/// Round 10, pinned: function pointers are not MSL device code, so both
/// the plain form and the array-of-function-pointers declarator -- whose
/// outer array would otherwise decay silently -- raise diagnostics.
test "function-pointer parameters are rejected" {
  try
    parse_kernel("kernel void f(void (*p)(int)) { return; }", []) |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected the function-pointer parameter to be rejected")
  }
  try
    parse_kernel("kernel void f(void (*p[4])(int)) { return; }", []) |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected the function-pointer array to be rejected")
  }
}

///|
/// Round 12, pinned: `void *` is opaque memory and passes; tabs and
/// newlines separate decorations; a commented `auto` is text.
test "void pointers, whitespace separators, and commented auto" {
  let k = parse_kernel(
    "kernel void f(threadgroup void *p [[threadgroup(0)]]) { return; }",
    [],
  )
  assert_eq(print_kernel(k).contains("threadgroup void *p"), true)
  let ws = parse_kernel("kernel void f(device\nfloat *x) { return; }", [])
  assert_eq(ws.decor[0].space, "device")
  let commented = parse_kernel(
    "kernel void f(device float *x) { /* auto tuned */ return; }",
    [],
  )
  assert_eq(print_kernel(commented).contains("return"), true)
}

///|
/// Round 13, pinned: braces inside comments are text; an emoji in a
/// comment must not crash the code-unit scans.
test "comment braces and non-BMP characters survive the bridge" {
  let k = parse_kernel(
    "kernel void f(device float *x) { /* } 🚀 { */ return; }",
    [],
  )
  assert_eq(print_kernel(k).contains("return"), true)
}

///|
/// Round 14, pinned: an emoji in a comment before the parameter list
/// must not shift the scan offsets (non-BMP blanks keep their two code
/// units), and the address-space vocabulary is closed over what the
/// bridge strips.
test "non-BMP comments before params and the closed vocabulary" {
  let k = parse_kernel(
    "kernel /* 🚀 */ void f(device float *x) { return; }",
    [],
  )
  assert_eq(k.decor[0].space, "device")
  assert_eq(print_kernel(k).contains("device float *x"), true)
}

///|
/// Round 15, pinned: a template call diagnoses instead of misreading as
/// comparisons, and MSL's missing scalars reject at parse.
test "template calls and non-MSL scalars are rejected" {
  try
    parse_kernel("kernel void f(device float *x) { foo<4>(x); }", []) |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected the template call to be rejected")
  }
  try
    parse_kernel("kernel void f(device double *x) { return; }", []) |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected the double parameter to be rejected")
  }
}

///|
/// Round 16, pinned: a spaced template call still diagnoses, a fake
/// attribute inside a comment stays a comment, and a malformed
/// extracted attribute is a parse failure rather than a later abort.
test "spaced templates, commented attributes, malformed attributes" {
  try
    parse_kernel("kernel void f(device float *x) { foo<4> (x); }", []) |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected the spaced template call to be rejected")
  }
  let commented = parse_kernel(
    "kernel void f(device float *x /* [[fake]] */) { return; }",
    [],
  )
  assert_eq(commented.decor[0].attr, "")
  try
    parse_kernel("kernel void f(device float *x [[a]b]]) { return; }", [])
    |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected the malformed attribute to be rejected")
  }
}
