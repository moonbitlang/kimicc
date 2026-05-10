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
test "linux amd64 include paths keep clang fallbacks after libc" {
  let paths = linux_amd64_system_include_paths()
  let mut usr_include = -1
  let mut clang_fallback = -1
  for i = 0; i < paths.length(); i = i + 1 {
    if paths[i] == "/usr/include" {
      usr_include = i
    } else if paths[i] == "/usr/lib/clang/18/include" {
      clang_fallback = i
    }
  }
  assert_true(usr_include >= 0)
  assert_true(clang_fallback > usr_include)
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

///|
test "driver accepts multiple C sources in link mode" {
  let opts = match
    parse_driver_args([
      "kimicc", "main.c", "helper.c", "support.o", "-o", "tool",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.output == LinkExecutable)
  assert_true(opts.input_path is Some("main.c"))
  assert_eq(opts.extra_input_paths.length(), 1)
  assert_eq(opts.extra_input_paths[0], "helper.c")
  assert_eq(opts.linker_args.length(), 1)
  assert_eq(opts.linker_args[0], "support.o")
  assert_eq(
    link_args_with_inputs(opts, "tool", ["/tmp/main.s", "/tmp/helper.s"]),
    ["clang", "-o", "tool", "/tmp/main.s", "/tmp/helper.s", "support.o"],
  )
}

///|
test "driver rejects multiple C sources outside link mode" {
  match parse_driver_args(["kimicc", "main.c", "helper.c", "-c"]) {
    Ok(_) => abort("expected multiple compile-only sources to fail")
    Err(err) =>
      assert_eq(err, "multiple C source inputs are only supported when linking")
  }
}

///|
test "driver shell quotes tool arguments" {
  assert_eq(shell_quote("plain"), "'plain'")
  assert_eq(shell_quote("two words"), "'two words'")
  assert_eq(shell_quote("can't"), "'can'\\''t'")
  assert_eq(
    shell_join_quoted(["clang", "-o", "/tmp/can't run/out", "input file.s"]),
    "'clang' '-o' '/tmp/can'\\''t run/out' 'input file.s'",
  )
}

///|
test "driver parses dependency sidecar options" {
  let opts = match
    parse_driver_args([
      "kimicc", "-c", "-MMD", "-MP", "-MF", "build/foo.d", "-MQ", "build dir/foo.o",
      "-o", "build dir/foo.o", "src/foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.emit_dependencies)
  assert_true(!opts.dependency_include_system)
  assert_true(opts.dependency_phony_targets)
  assert_true(opts.dependency_output_path is Some("build/foo.d"))
  assert_eq(opts.dependency_targets.length(), 1)
  assert_eq(opts.dependency_targets[0], "build\\ dir/foo.o")
  assert_eq(
    dependency_file_content(opts, "src/foo.c", "build dir/foo.o", [
      "src/foo.c", "include/config header.h", "src/foo.c",
    ]),
    "build\\ dir/foo.o: src/foo.c include/config\\ header.h\n\ninclude/config\\ header.h:\n",
  )
}

///|
test "driver parses forced include spellings" {
  let opts = match
    parse_driver_args([
      "kimicc", "-include", "config.h", "--include=prefix.h", "--include", "late.h",
      "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(opts.include_paths.length(), 0)
  assert_eq(opts.forced_includes.length(), 3)
  assert_eq(opts.forced_includes[0], "config.h")
  assert_eq(opts.forced_includes[1], "prefix.h")
  assert_eq(opts.forced_includes[2], "late.h")
}

///|
test "driver parses dependency-only options and filters system headers" {
  let opts = match
    parse_driver_args([
      "kimicc", "-MM", "-MP", "-MFdeps/foo.d", "-MT", "foo.o", "src/foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.output == EmitDependencies)
  assert_true(opts.emit_dependencies)
  assert_true(!opts.dependency_include_system)
  assert_true(opts.dependency_phony_targets)
  assert_true(opts.dependency_output_path is Some("deps/foo.d"))
  assert_eq(
    dependency_rule_content(opts, "src/foo.c", "src/foo.o", [
      { path: "src/foo.c", system: false },
      { path: "include/local.h", system: false },
      { path: "/usr/include/stdio.h", system: true },
    ]),
    "foo.o: src/foo.c include/local.h\n\ninclude/local.h:\n",
  )
}

///|
test "driver accumulates dependency targets" {
  let opts = match
    parse_driver_args([
      "kimicc", "-M", "-MT", "foo.o", "-MQ", "build dir/foo.d", "src/foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(opts.dependency_targets.length(), 2)
  assert_eq(
    dependency_file_content(opts, "src/foo.c", "src/foo.o", ["src/foo.c"]),
    "foo.o build\\ dir/foo.d: src/foo.c\n",
  )
}

///|
test "driver accepts dash dependency destination" {
  let opts = match
    parse_driver_args(["kimicc", "-MM", "-MF", "-", "src/foo.c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.output == EmitDependencies)
  assert_true(opts.dependency_output_path is Some("-"))
  assert_eq(dependency_output_path(opts, "src/foo.c", "src/foo.o"), "-")
}

///|
test "dependency-only mode treats output as dependency destination" {
  let opts = match
    parse_driver_args(["kimicc", "-MM", "-o", "deps/foo.d", "src/foo.c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.output == EmitDependencies)
  assert_true(opts.output_path is Some("deps/foo.d"))
  assert_true(dependency_only_destination_path(opts) is Some("deps/foo.d"))
  assert_eq(
    dependency_file_content(opts, "src/foo.c", "src/foo.o", ["src/foo.c"]),
    "src/foo.o: src/foo.c\n",
  )
}

///|
test "driver parses preprocessor dependency options" {
  let opts = match
    parse_driver_args([
      "kimicc", "-c", "-Wp,-MMD,build/foo.d,-MP,-MQ,build dir/foo.o,-DVALUE=3,-UOLD",
      "-o", "build/foo.o", "src/foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.emit_dependencies)
  assert_true(!opts.dependency_include_system)
  assert_true(opts.dependency_phony_targets)
  assert_true(opts.dependency_output_path is Some("build/foo.d"))
  assert_eq(opts.dependency_targets.length(), 1)
  assert_eq(opts.dependency_targets[0], "build\\ dir/foo.o")
  assert_eq(opts.defines["VALUE"], "3")
  assert_eq(opts.undefines.length(), 1)
  assert_eq(opts.undefines[0], "OLD")
}
