///|
test "driver parses compile-only flags" {
  let opts = match
    parse_driver_args([
      "kimicc", "-c", "-Wall", "-std=c11", "-O2", "-Iinclude", "-isystem", "sys",
      "-DVALUE=3", "-UOLD", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.output == EmitObject)
  assert_true(opts.input_path is Some("foo.c"))
  assert_eq(opts.include_paths.length(), 1)
  assert_eq(opts.include_paths[0], "include")
  assert_eq(opts.system_include_paths.length(), 1)
  assert_eq(opts.system_include_paths[0], "sys")
  assert_eq(opts.defines["VALUE"], "3")
  assert_eq(opts.undefines.length(), 1)
  assert_eq(opts.undefines[0], "OLD")
}

///|
test "driver parses linux amd64 target" {
  let opts = match
    parse_driver_args(["kimicc", "-target", "linux-amd64", "-S", "foo.c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.target == LinuxAmd64)
  let args = link_args(opts, "out", Some("foo.s"))
  assert_eq(args[0], "clang")
  assert_eq(args[3], "-target")
  assert_eq(args[4], "x86_64-linux-gnu")
}

///|
test "driver chooses compiler-style default output names" {
  let opts = DriverOptions::new()
  opts.output = EmitAssembly
  assert_eq(default_output_path(opts, "src/foo.c"), "src/foo.s")
  opts.output = EmitObject
  assert_eq(default_output_path(opts, "src/foo.c"), "src/foo.o")
  opts.output = LinkExecutable
  assert_eq(default_output_path(opts, "src/foo.c"), "a.out")
  opts.output = EmitPreprocessed
  assert_eq(default_output_path(opts, "src/foo.c"), "-")
}

///|
test "driver keeps link-only inputs and framework flags" {
  let opts = match
    parse_driver_args([
      "kimicc", "foo.o", "-framework", "CoreFoundation", "-Wl,-rpath,/tmp", "-o",
      "tool",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.input_path is None)
  assert_true(opts.output_path is Some("tool"))
  assert_eq(opts.linker_args.length(), 4)
  assert_eq(opts.linker_args[0], "foo.o")
  assert_eq(opts.linker_args[1], "-framework")
  assert_eq(opts.linker_args[2], "CoreFoundation")
  assert_eq(opts.linker_args[3], "-Wl,-rpath,/tmp")
}
