///|
/// The Metal compile gate: the emitted kernel must be accepted by the
/// compiler that will actually consume it. ds4 compiles its shaders from
/// source at runtime through Metal.framework (`newLibraryWithSource`),
/// not the offline `xcrun metal` toolchain -- so the gate does exactly
/// that: a small ObjC probe hands the generated source to the system
/// Metal compiler and reports what it built. Needs only the command-line
/// tools and a Metal device; skips on Linux CI and on GPU-less machines.
async test "generated MSL compiles through the runtime Metal compiler" {
  let sys = run_command_capture("uname -s", "msl_gate_uname")
  if !sys.output.contains("Darwin") {
    println("skipped: Metal gate needs macOS")
    return
  }
  // The kernel from the msl package's own tests, regenerated here: the
  // add2 shape with the model dimension baked, plus a threadgroup and
  // buffer-bound variant to exercise the other decoration forms.
  let a = @build.v("a")
  let b = @build.v("b")
  let out = @build.v("out")
  let i = @build.v("i")
  let add2 : @msl.Kernel = {
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
      @msl.decor("device const"),
      @msl.decor("device const"),
      @msl.decor("device"),
      @msl.decor("", attr="[[thread_position_in_grid]]"),
    ],
  }
  let scaled : @msl.Kernel = {
    qualifier: "kernel",
    decl: @build.func(
      Void,
      "gen_scale_f32_4096",
      [
        @build.param(Pointer(Float), "x"),
        @build.param(Pointer(Float), "s"),
        @build.param(Named("uint"), "i"),
      ],
      {
        let xi = @build.v("x")[@build.v("i")]
        let s0 = @build.v("s")[@parser.int_literal(0, SInt)]
        [
          If(
            @build.v("i").ge(@parser.int_literal(4096, UInt)),
            Return(None),
            None,
          ),
          ExprStmt(CompoundAssign("*", xi, s0)),
        ]
      },
    ),
    decor: [
      @msl.decor("device"),
      @msl.decor("constant", attr="[[buffer(1)]]"),
      @msl.decor("", attr="[[thread_position_in_grid]]"),
    ],
  }
  // A uniform-block reference parameter -- `constant Args &args` -- the
  // shape ds4's own hot kernels use and the one the round-trip tests
  // exercise structurally. Only the Metal compiler can confirm the
  // emitted spelling is valid MSL rather than merely self-consistent.
  let uniform : @msl.Kernel = {
    qualifier: "kernel",
    decl: @build.func(
      Void,
      "gen_scale_uniform_f32",
      [
        @build.param(Named("gen_args"), "args"),
        @build.param(Pointer(Float), "x"),
        @build.param(Named("uint"), "i"),
      ],
      [
        If(
          @build.v("i").ge(@parser.int_literal(4096, UInt)),
          Return(None),
          None,
        ),
        ExprStmt(
          CompoundAssign(
            "*",
            @build.v("x")[@build.v("i")],
            MemberAccess(@build.v("args"), "scale"),
          ),
        ),
      ],
    ),
    decor: [
      @msl.decor("constant", by_ref=true),
      @msl.decor("device"),
      @msl.decor("", attr="[[thread_position_in_grid]]"),
    ],
  }
  let prelude =
    #|struct gen_args { float scale; };
  let source = @msl.print_kernels([add2, scaled, uniform], prelude~)
  let metal_path = temp_file_path("msl_gate", source, ".metal")
  write_text_file(metal_path, source)
  let probe =
    #|#import <Metal/Metal.h>
    #|#import <Foundation/Foundation.h>
    #|int main(int argc, char **argv) {
    #|  @autoreleasepool {
    #|    NSError *err = nil;
    #|    NSString *src = [NSString stringWithContentsOfFile:@(argv[1])
    #|                                              encoding:NSUTF8StringEncoding
    #|                                                 error:&err];
    #|    if (!src) { fprintf(stderr, "read failed\n"); return 2; }
    #|    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    #|    if (!dev) { printf("no metal device\n"); return 3; }
    #|    id<MTLLibrary> lib = [dev newLibraryWithSource:src options:nil error:&err];
    #|    if (!lib) {
    #|      fprintf(stderr, "compile: %s\n", err.localizedDescription.UTF8String);
    #|      return 1;
    #|    }
    #|    printf("metal library compiled: %lu functions\n",
    #|           (unsigned long)lib.functionNames.count);
    #|    for (NSString *name in lib.functionNames) printf("  %s\n", name.UTF8String);
    #|    return 0;
    #|  }
    #|}
  let probe_path = temp_file_path("msl_gate_probe", probe, ".m")
  let probe_bin = temp_file_path("msl_gate_probe_bin", probe, "")
  write_text_file(probe_path, probe)
  let compiled = run_command_capture(
    "clang -fobjc-arc -framework Metal -framework Foundation -o " +
    probe_bin +
    " " +
    probe_path,
    "msl_gate_probe_compile",
  )
  // On macOS the frameworks ship with the command-line tools: a probe
  // compile failure here is a real regression, not a missing
  // prerequisite, and skipping it would pass the gate without ever
  // invoking Metal.
  if compiled.code != 0 {
    println(compiled.output)
    fail("Metal probe failed to compile")
  }
  let result = run_command_capture(probe_bin + " " + metal_path, "msl_gate_run")
  println(result.output)
  if result.code == 3 {
    println("skipped: no Metal device")
    return
  }
  assert_eq(result.code, 0)
  assert_true(result.output.contains("metal library compiled: 3 functions"))
  assert_true(result.output.contains("gen_add2_f32_4096"))
  assert_true(result.output.contains("gen_scale_f32_4096"))
  assert_true(result.output.contains("gen_scale_uniform_f32"))
}
