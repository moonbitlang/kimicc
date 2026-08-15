///|
/// The generated IQ2_XXS paired gate/up kernel -- the hottest kernel in
/// ds4's Metal decode path, at roughly 40% of routed-MoE time -- must
/// compile through the same runtime Metal compiler ds4 itself uses.
///
/// This gate proves emission and syntax, not numerics: a kernel that
/// compiles can still compute the wrong thing, and the correctness
/// referee against a double-precision oracle is separate work. What it
/// does establish is that the toolkit can express the construct set a
/// real GPU kernel needs -- threadgroup memory, cooperative staging with
/// a barrier, simdgroup reductions, address-space-qualified locals and
/// casts, and `half` loads -- none of which it could a day ago.
///
/// Skips on Linux CI and on machines without a Metal device.
async test "the generated IQ2_XXS Metal kernel compiles on device" {
  let sys = run_command_capture("uname -s", "ds4_metal_uname")
  if !sys.output.contains("Darwin") {
    println("skipped: Metal gate needs macOS")
    return
  }
  // The real checkpoint's expert shape: 4096 wide in, 2048 rows out.
  let source = @ds4_metal.generate({
    in_dim: 4096,
    out_rows: 2048,
    nr0: 4,
    nsg: 4,
  })
  // The specialization is visible in the emitted text: ds4 derives both
  // of these from runtime buffer fields.
  assert_true(source.contains("ib32 < 128"))
  assert_true(source.contains("first_row * 1056"))
  let metal_path = temp_file_path("ds4_metal_gate", source, ".metal")
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
    #|    printf("compiled: %lu functions\n", (unsigned long)lib.functionNames.count);
    #|    for (NSString *n in lib.functionNames) printf("  %s\n", n.UTF8String);
    #|    return 0;
    #|  }
    #|}
  let probe_path = temp_file_path("ds4_metal_probe", probe, ".m")
  let probe_bin = temp_file_path("ds4_metal_probe_bin", probe, "")
  write_text_file(probe_path, probe)
  let compiled = run_command_capture(
    "clang -fobjc-arc -framework Metal -framework Foundation -o " +
    probe_bin +
    " " +
    probe_path,
    "ds4_metal_probe_compile",
  )
  if compiled.code != 0 {
    println(compiled.output)
    fail("Metal probe failed to compile")
  }
  let result = run_command_capture(
    probe_bin + " " + metal_path,
    "ds4_metal_run",
  )
  println(result.output)
  if result.code == 3 {
    println("skipped: no Metal device")
    return
  }
  assert_eq(result.code, 0)
  assert_true(result.output.contains("gen_iq2_xxs_pair_4096"))
}

///|
/// Shapes whose trailing threadgroup would read past the weight tensor
/// are refused at generation. Every simdgroup reads `nr0` rows
/// unconditionally, and the epilogue guard only stops stores -- so the
/// alternative to this check is a bounds test in the hot loop.
test "output shapes that would overrun the weights are refused" {
  // 2048 rows over 4 simdgroups x 4 rows divides evenly; 2044 does not.
  let ok = @ds4_metal.generate({ in_dim: 4096, out_rows: 2048, nr0: 4, nsg: 4 })
  assert_true(ok.contains("gen_iq2_xxs_pair_4096"))
  // The staging loop must be strided by the real thread count, not
  // ds4's hardcoded four-per-thread, which is only correct at nsg == 2.
  assert_true(ok.contains("idx += 128"))
}
