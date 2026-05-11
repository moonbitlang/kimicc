///|
test "driver parses compile-only flags" {
  let opts = match
    parse_driver_args([
      "kimicc", "-c", "-Wall", "-std=c11", "-O2", "-Iinclude", "-isystem", "sys",
      "--include-directory=include2", "--include-directory", "include3", "-DVALUE=3",
      "-UOLD", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.output == EmitObject)
  assert_true(opts.input_path is Some("foo.c"))
  assert_eq(opts.include_paths.length(), 3)
  assert_eq(opts.include_paths[0], "include")
  assert_eq(opts.include_paths[1], "include2")
  assert_eq(opts.include_paths[2], "include3")
  assert_eq(opts.system_include_paths.length(), 1)
  assert_eq(opts.system_include_paths[0], "sys")
  assert_eq(opts.defines["VALUE"], "3")
  assert_eq(opts.undefines.length(), 1)
  assert_eq(opts.undefines[0], "OLD")
}

///|
test "driver command-line defines support function-like and empty macros" {
  let opts = match
    parse_driver_args([
      "kimicc", "-DADD(x,y)=((x)+(y))", "-DEMPTY=", "-E", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(opts.defines["ADD(x,y)"], "((x)+(y))")
  assert_eq(opts.defines["EMPTY"], "")
  let result = preprocess_source_with_dependencies(
    "int a = ADD(1, 2);\nint b = 3 EMPTY;\n", "foo.c", opts,
  )
  assert_eq(result.text, "int a=((1)+(2));\nint b=3;\n")
}

///|
test "driver dumps final macro definitions" {
  let opts = match
    parse_driver_args([
      "kimicc", "-E", "-dM", "-DVALUE=7", "-U__STDC__", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.dump_macros)
  let result = dump_macros_source_with_dependencies(
    "#define LOCAL(x) ((x) + VALUE)\n#undef VALUE\n#define EMPTY\n", "foo.c", opts,
  )
  assert_true(result.text.contains("#define EMPTY\n"))
  assert_true(result.text.contains("#define LOCAL(x) ((x)+VALUE)\n"))
  assert_true(!result.text.contains("#define VALUE 7\n"))
  assert_true(!result.text.contains("#define __STDC__ 1\n"))
}

///|
test "driver honors undef predefined macro mode" {
  let opts = match
    parse_driver_args([
      "kimicc", "-E", "-dM", "-undef", "-target", "linux-amd64", "-pthread", "-fPIE",
      "-O2", "-DVALUE=7", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.undef_predefined)
  let result = dump_macros_source_with_dependencies("", "foo.c", opts)
  assert_true(result.text.contains("#define VALUE 7\n"))
  assert_true(result.text.contains("#define __STDC__ 1\n"))
  assert_true(!result.text.contains("#define __linux__"))
  assert_true(!result.text.contains("#define __x86_64__"))
  assert_true(!result.text.contains("#define _REENTRANT"))
  assert_true(!result.text.contains("#define __PIC__"))
  assert_true(!result.text.contains("#define __OPTIMIZE__"))
}

///|
test "driver treats dash as stdin input" {
  let opts = match parse_driver_args(["kimicc", "-E", "-dM", "-"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.input_path is Some("-"))
  assert_true(opts.output == EmitPreprocessed)
  assert_true(opts.dump_macros)
}

///|
test "driver applies command-line macro operations in order" {
  let remove_opts = match
    parse_driver_args(["kimicc", "-DVALUE=1", "-UVALUE", "-E", "foo.c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  let remove_result = preprocess_source_with_dependencies(
    "#ifdef VALUE\nint value = VALUE;\n#else\nint value = 0;\n#endif\n", "foo.c",
    remove_opts,
  )
  assert_eq(remove_result.text, "int value=0;\n")
  let restore_opts = match
    parse_driver_args(["kimicc", "-UVALUE", "-DVALUE=7", "-E", "foo.c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  let restore_result = preprocess_source_with_dependencies(
    "#ifdef VALUE\nint value = VALUE;\n#else\nint value = 0;\n#endif\n", "foo.c",
    restore_opts,
  )
  assert_eq(restore_result.text, "int value=7;\n")
}

///|
test "driver consumes ignored flags with separate values" {
  let opts = match
    parse_driver_args([
      "kimicc", "-mllvm", "inline-threshold=10", "--param", "ssp-buffer-size=4",
      "--std", "c11", "-MJ", "compile.json", "-serialize-diagnostics", "diag.dia",
      "--serialize-diagnostics", "diag2.dia", "-working-directory", "/tmp/build",
      "-fdebug-compilation-dir", "/tmp/build", "-fmodule-map-file", "module.modulemap",
      "--config", "clang.cfg", "-analyzer-output", "plist", "-arcmt-migrate-report-output",
      "arcmt.plist", "-aux-info", "protos.h", "-auxbase", "foo", "-auxbase-strip",
      "build/foo.o", "-cxx-isystem", "cxx/include", "-dsym-dir", "dsym", "-dumpbase",
      "foo.c", "-dumpbase-ext", ".c", "-dumpdir", "aux/", "-fmodules-user-build-path",
      "modules", "-fdepscan-share-identifier", "build-share", "-fexperimental-openacc-macro-override",
      "202011", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.input_path is Some("foo.c"))
  assert_eq(opts.extra_input_paths.length(), 0)
  let eq_opts = match
    parse_driver_args([
      "kimicc", "--std=c11", "-MJcompile2.json", "--serialize-diagnostics=diag.dia",
      "--working-directory=/tmp/build", "-fdebug-compilation-dir=/tmp/build", "-fmodule-map-file=module.modulemap",
      "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(eq_opts.input_path is Some("foo.c"))
  assert_eq(eq_opts.extra_input_paths.length(), 0)
}

///|
test "driver consumes clang pass-through flags with separate values" {
  let opts = match
    parse_driver_args([
      "kimicc", "-fsyntax-only", "-Xanalyzer", "check", "-Xarch_host", "-DHOST",
      "-Xarch_device", "-DDEVICE", "-Xcuda-fatbinary", "--compress-all", "-Xcuda-ptxas",
      "-v", "-Xopenmp-target", "-march=x86-64", "-Xopenmp-target=x86_64-linux-gnu",
      "-march=x86-64-v2", "-darwin-target-variant", "macos13", "-darwin-target-variant-triple",
      "x86_64-apple-macos13", "-meabi", "gnu", "-mmlir", "--mlir-print-ir-after-all",
      "-mthread-model", "posix", "-stdlib++-isystem", "cxx-stdlib", "-vfsoverlay",
      "overlay.yaml", "-Xarch_x86_64", "-DCPU", "-Xoffload-linkerx86_64-linux-gnu",
      "--as-needed", "-b", "elf64-x86-64", "-hlsl-entry", "main", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.input_path is Some("foo.c"))
  assert_eq(opts.extra_input_paths.length(), 0)
}

///|
test "driver verbose flag does not replace compilation" {
  let opts = match parse_driver_args(["kimicc", "-v", "-S", "foo.c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.verbose)
  assert_true(!opts.show_version)
  assert_true(opts.output == EmitAssembly)
  assert_true(opts.input_path is Some("foo.c"))
}

///|
test "driver long version flag remains terminal" {
  let opts = match parse_driver_args(["kimicc", "--version"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.show_version)
  assert_true(!opts.verbose)
}

///|
test "driver language flag classifies extensionless inputs" {
  let opts = match
    parse_driver_args([
      "kimicc", "-x", "c", "main", "helper", "-x", "none", "support.o", "-o", "tool",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.input_path is Some("main"))
  assert_eq(opts.extra_input_paths, ["helper"])
  assert_eq(opts.linker_args, ["support.o"])
  assert_true(opts.input_language is None)
}

///|
test "driver language flag delegates extensionless assembler" {
  let opts = match
    parse_driver_args(["kimicc", "-c", "-xassembler", "start", "-o", "start.o"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.input_path is None)
  assert_eq(opts.linker_args, ["start"])
  assert_true(treats_as_assembly_input(opts, "start"))
}

///|
test "driver forwards forced assembler language to clang" {
  let opts = match
    parse_driver_args([
      "kimicc", "-c", "-target", "linux-amd64", "-x", "assembler-with-cpp", "start",
      "-o", "start.o",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(assemble_args(opts, "start", "start.o"), [
    "clang", "-target", "x86_64-linux-gnu", "-x", "assembler-with-cpp", "-c", "start",
    "-o", "start.o",
  ])
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
test "driver normalizes common linux amd64 target aliases" {
  let opts = match
    parse_driver_args(["kimicc", "--target=x86_64-pc-linux-gnu", "-S", "foo.c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.target == LinuxAmd64)
  assert_eq(opts.target.triple(), "x86_64-linux-gnu")
  let docker_opts = match
    parse_driver_args(["kimicc", "-target", "linux/amd64", "-S", "foo.c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(docker_opts.target == LinuxAmd64)
}

///|
test "driver parses separated long target option" {
  let opts = match
    parse_driver_args(["kimicc", "--target", "x86_64-linux-musl", "-S", "foo.c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.target == LinuxAmd64)
  assert_true(opts.input_path is Some("foo.c"))
}

///|
test "driver parses configure query flags" {
  let opts = match
    parse_driver_args([
      "kimicc", "-target", "linux-amd64", "-dumpmachine", "-print-target-triple",
      "-print-resource-dir", "-print-search-dirs", "--sysroot=/opt/sysroot", "-print-sysroot",
      "-print-sysroot-headers-suffix", "-print-multiarch", "-print-multi-directory",
      "-print-multi-os-directory", "-print-multi-lib", "-print-libgcc-file-name",
      "-print-prog-name=ld", "-print-file-name=crt1.o",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.dump_machine)
  assert_true(opts.print_target_triple)
  assert_true(opts.print_resource_dir)
  assert_true(opts.print_search_dirs)
  assert_true(opts.print_sysroot)
  assert_true(opts.print_sysroot_headers_suffix)
  assert_true(opts.print_multiarch)
  assert_true(opts.print_multi_directory)
  assert_true(opts.print_multi_os_directory)
  assert_true(opts.print_multi_lib)
  assert_true(opts.print_libgcc_file_name)
  assert_true(opts.print_prog_name is Some("ld"))
  assert_true(opts.print_file_name is Some("crt1.o"))
  assert_eq(opts.target.triple(), "x86_64-linux-gnu")
  assert_eq(driver_sysroot(opts), "/opt/sysroot")
  assert_eq(driver_multiarch(opts), "x86_64-linux-gnu")
  assert_eq(driver_multi_os_directory(opts), "../lib")
  assert_eq(clang_query_args(opts, "-print-file-name=crt1.o"), [
    "clang", "-target", "x86_64-linux-gnu", "--sysroot=/opt/sysroot", "-print-file-name=crt1.o",
  ])
  let version_opts = match parse_driver_args(["kimicc", "-dumpversion"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(version_opts.dump_version)
  let full_version_opts = match
    parse_driver_args(["kimicc", "-dumpfullversion"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(full_version_opts.dump_version)
}

///|
test "driver parses long configure query flags" {
  let opts = match
    parse_driver_args([
      "kimicc", "--target", "linux/amd64", "--dumpmachine", "--print-target-triple",
      "--print-resource-dir", "--print-search-dirs", "--print-sysroot", "--print-multiarch",
      "--print-sysroot-headers-suffix", "--print-multi-directory", "--print-multi-os-directory",
      "--print-multi-lib", "--print-libgcc-file-name", "--print-prog-name=ld", "--print-file-name=crt1.o",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.dump_machine)
  assert_true(opts.print_target_triple)
  assert_true(opts.print_resource_dir)
  assert_true(opts.print_search_dirs)
  assert_true(opts.print_sysroot)
  assert_true(opts.print_sysroot_headers_suffix)
  assert_true(opts.print_multiarch)
  assert_true(opts.print_multi_directory)
  assert_true(opts.print_multi_os_directory)
  assert_true(opts.print_multi_lib)
  assert_true(opts.print_libgcc_file_name)
  assert_true(opts.print_prog_name is Some("ld"))
  assert_true(opts.print_file_name is Some("crt1.o"))
  assert_true(opts.target == LinuxAmd64)
  let separated_opts = match
    parse_driver_args([
      "kimicc", "--print-prog-name", "ld", "--print-file-name", "crt1.o",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(separated_opts.print_prog_name is Some("ld"))
  assert_true(separated_opts.print_file_name is Some("crt1.o"))
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
test "driver parses isystem after include path" {
  let opts = match
    parse_driver_args([
      "kimicc", "-fsyntax-only", "-isystem-after", "after-sys", "-isystem", "sys",
      "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.input_path is Some("foo.c"))
  assert_eq(opts.extra_input_paths.length(), 0)
  assert_eq(opts.system_include_paths, ["sys"])
  assert_eq(opts.after_system_include_paths, ["after-sys"])
  let full_paths = full_system_include_paths(opts)
  assert_eq(full_paths[0], "sys")
  assert_eq(full_paths[full_paths.length() - 1], "after-sys")
  let attached_opts = match
    parse_driver_args([
      "kimicc", "-fsyntax-only", "-isystem-afterafter-attached", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(attached_opts.after_system_include_paths, ["after-attached"])
  let idir_opts = match
    parse_driver_args([
      "kimicc", "-fsyntax-only", "-idirafter", "after-std", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(idir_opts.after_system_include_paths, ["after-std"])
  let xpreprocessor_opts = match
    parse_driver_args([
      "kimicc", "-fsyntax-only", "-Xpreprocessor", "-isystem-after", "-Xpreprocessor",
      "after-x", "-Xpreprocessor", "-iquote", "-Xpreprocessor", "quote-x", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(xpreprocessor_opts.include_paths, ["quote-x"])
  assert_eq(xpreprocessor_opts.after_system_include_paths, ["after-x"])
}

///|
test "driver consumes unsupported include options with values" {
  let opts = match
    parse_driver_args([
      "kimicc", "-fsyntax-only", "-iframeworkwithsysroot", "/SDK/Frameworks", "-iwithsysroot",
      "/usr/include", "-ivfsoverlay", "overlay.yaml", "-ivfsstatcache", "stat.cache",
      "-iapinotes-path", "api.notes", "-iapinotes-modules", "api-mods", "-index-store-path",
      "index", "-index-unit-output-path", "unit", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.input_path is Some("foo.c"))
  assert_eq(opts.extra_input_paths.length(), 0)
}

///|
test "driver applies include prefix options" {
  let opts = match
    parse_driver_args([
      "kimicc", "-fsyntax-only", "-iprefix", "/tools/", "-iwithprefixbefore", "include",
      "-iwithprefix", "system", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(opts.include_paths, ["/tools/include"])
  assert_eq(opts.system_include_paths, ["/tools/system"])
  let attached_opts = match
    parse_driver_args([
      "kimicc", "-fsyntax-only", "-iprefix/opt/", "-iwithprefixbeforeheaders", "-iwithprefixsys",
      "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(attached_opts.include_paths, ["/opt/headers"])
  assert_eq(attached_opts.system_include_paths, ["/opt/sys"])
}

///|
test "driver forwards linux sysroot to includes and clang" {
  let opts = match
    parse_driver_args([
      "kimicc", "-target", "linux-amd64", "--sysroot=/opt/sysroot", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(opts.toolchain_args.length(), 1)
  assert_eq(opts.toolchain_args[0], "--sysroot=/opt/sysroot")
  let paths = full_system_include_paths(opts)
  assert_eq(paths[0], "/opt/sysroot/usr/include/x86_64-linux-gnu")
  assert_eq(paths[1], "/opt/sysroot/usr/include")
  assert_eq(link_args(opts, "out", Some("foo.s")), [
    "clang", "-o", "out", "-target", "x86_64-linux-gnu", "--sysroot=/opt/sysroot",
    "foo.s",
  ])
}

///|
test "driver forwards separated isysroot spelling" {
  let opts = match parse_driver_args(["kimicc", "-isysroot", "/SDK", "foo.c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(opts.toolchain_args.length(), 2)
  assert_eq(opts.toolchain_args[0], "-isysroot")
  assert_eq(opts.toolchain_args[1], "/SDK")
  let paths = full_system_include_paths(opts)
  assert_eq(paths[0], "/SDK/usr/include")
}

///|
test "driver uses resource dir for preprocessing and clang" {
  let opts = match
    parse_driver_args(["kimicc", "-resource-dir", "/clang/lib", "foo.c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  let paths = full_system_include_paths(opts)
  assert_eq(paths[0], "/clang/lib/include")
  assert_eq(link_args(opts, "out", Some("foo.s")), [
    "clang", "-o", "out", "-resource-dir", "/clang/lib", "foo.s",
  ])
}

///|
test "driver forwards gcc toolchain discovery options to clang" {
  let opts = match
    parse_driver_args([
      "kimicc", "-target", "linux-amd64", "--gcc-toolchain", "/opt/gcc", "--gcc-install-dir=/opt/gcc/lib/gcc/x86_64-linux-gnu/13",
      "-B", "/opt/gcc/bin", "-B/opt/alt-gcc/bin", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(opts.toolchain_args, [
    "--gcc-toolchain=/opt/gcc", "--gcc-install-dir=/opt/gcc/lib/gcc/x86_64-linux-gnu/13",
    "-B", "/opt/gcc/bin", "-B/opt/alt-gcc/bin",
  ])
  assert_eq(link_args(opts, "out", Some("foo.s")), [
    "clang", "-o", "out", "-target", "x86_64-linux-gnu", "--gcc-toolchain=/opt/gcc",
    "--gcc-install-dir=/opt/gcc/lib/gcc/x86_64-linux-gnu/13", "-B", "/opt/gcc/bin",
    "-B/opt/alt-gcc/bin", "foo.s",
  ])
  assert_eq(clang_query_args(opts, "-print-file-name=crt1.o"), [
    "clang", "-target", "x86_64-linux-gnu", "--gcc-toolchain=/opt/gcc", "--gcc-install-dir=/opt/gcc/lib/gcc/x86_64-linux-gnu/13",
    "-B", "/opt/gcc/bin", "-B/opt/alt-gcc/bin", "-print-file-name=crt1.o",
  ])
}

///|
test "driver chooses compiler-style default output names" {
  let opts = DriverOptions::new()
  opts.output = EmitAssembly
  assert_eq(default_output_path(opts, "src/foo.c"), "src/foo.s")
  opts.output = EmitObject
  assert_eq(default_output_path(opts, "src/foo.c"), "src/foo.o")
  opts.output = CheckSyntax
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
      "kimicc", "foo.o", "start.s", "-framework", "CoreFoundation", "-Wl,-rpath,/tmp",
      "-o", "tool",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.input_path is None)
  assert_true(opts.output_path is Some("tool"))
  assert_eq(opts.linker_args.length(), 5)
  assert_eq(opts.linker_args[0], "foo.o")
  assert_eq(opts.linker_args[1], "start.s")
  assert_eq(opts.linker_args[2], "-framework")
  assert_eq(opts.linker_args[3], "CoreFoundation")
  assert_eq(opts.linker_args[4], "-Wl,-rpath,/tmp")
}

///|
test "driver parses syntax-only mode" {
  let opts = match parse_driver_args(["kimicc", "-fsyntax-only", "foo.c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.output == CheckSyntax)
  assert_true(opts.input_path is Some("foo.c"))
}

///|
test "driver treats assembly compile input as delegated input" {
  let opts = match
    parse_driver_args(["kimicc", "-c", "start.s", "-o", "start.o"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.output == EmitObject)
  assert_true(opts.input_path is None)
  assert_eq(opts.linker_args, ["start.s"])
  assert_eq(opts.assembly_input_paths, ["start.s"])
  assert_eq(assembly_output_path(opts, "start.s"), "start.o")
}

///|
test "driver separates assembly compile inputs from linker flags" {
  let opts = match
    parse_driver_args([
      "kimicc", "-c", "-pthread", "start.s", "-l", "m", "-o", "start.o",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.output == EmitObject)
  assert_true(opts.input_path is None)
  assert_eq(opts.assembly_input_paths, ["start.s"])
  assert_eq(opts.linker_args, ["-pthread", "start.s", "-l", "m"])
}

///|
test "driver preserves assembler options for clang steps" {
  let opts = match
    parse_driver_args([
      "kimicc", "-c", "-Wa,-fatal-warnings", "-Xassembler", "--noexecstack", "start.s",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(opts.toolchain_args, [
    "-Wa,-fatal-warnings", "-Xassembler", "--noexecstack",
  ])
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
test "driver emits one dependency sidecar for multi-source links" {
  let opts = match
    parse_driver_args([
      "kimicc", "-MMD", "-MP", "-o", "tool", "main.c", "helper.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.output == LinkExecutable)
  assert_true(opts.emit_dependencies)
  assert_true(opts.input_path is Some("main.c"))
  assert_eq(opts.extra_input_paths, ["helper.c"])
  assert_eq(dependency_output_path(opts, "main.c", "tool"), "tool.d")
  assert_eq(
    dependency_rule_content(opts, "main.c", "tool", [
      { path: "main.c", system: false },
      { path: "include/main.h", system: false },
      { path: "helper.c", system: false },
      { path: "/usr/include/stdio.h", system: true },
      { path: "include/main.h", system: false },
    ]),
    "tool: main.c include/main.h helper.c\n\ninclude/main.h:\n\nhelper.c:\n",
  )
}

///|
test "driver preserves common linker flags" {
  let opts = match
    parse_driver_args([
      "kimicc", "foo.o", "-static", "-pie", "-nostdlib", "-u", "entry", "-z", "now",
      "-l", "m", "--library-directory=/extra", "--library-directory", "/more", "-rpath",
      "/runtime/lib", "-e", "entry_point", "-install_name", "@rpath/libfoo.dylib",
      "-compatibility_version", "1.0", "-current_version", "1.2", "-fuse-ld=lld",
      "-rtlib=compiler-rt", "-o", "tool",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.input_path is None)
  assert_eq(opts.linker_args, [
    "foo.o", "-static", "-pie", "-nostdlib", "-u", "entry", "-z", "now", "-l", "m",
    "-L", "/extra", "-L", "/more", "-rpath", "/runtime/lib", "-e", "entry_point",
    "-install_name", "@rpath/libfoo.dylib", "-compatibility_version", "1.0", "-current_version",
    "1.2", "-fuse-ld=lld", "-rtlib=compiler-rt",
  ])
}

///|
test "driver preserves long linker flag spellings" {
  let opts = match
    parse_driver_args([
      "kimicc", "foo.o", "--shared", "--rdynamic", "--static", "--static-pie", "--no-pie",
      "--nostdlib", "--nodefaultlibs", "--nostartfiles", "--rtlib=compiler-rt", "--stdlib=libc++",
      "--unwindlib=libunwind", "-unwindlib=libgcc", "-o", "tool",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.input_path is None)
  assert_eq(opts.linker_args, [
    "foo.o", "--shared", "--rdynamic", "--static", "--static-pie", "--no-pie", "--nostdlib",
    "--nodefaultlibs", "--nostartfiles", "--rtlib=compiler-rt", "--stdlib=libc++",
    "--unwindlib=libunwind", "-unwindlib=libgcc",
  ])
}

///|
test "driver pthread seeds reentrant define and linker flag" {
  let opts = match parse_driver_args(["kimicc", "-c", "-pthread", "foo.c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(opts.defines["_REENTRANT"], "1")
  assert_eq(opts.linker_args, ["-pthread"])
  let result = preprocess_source_with_dependencies(
    "#ifdef _REENTRANT\nint threaded = _REENTRANT;\n#else\nint threaded = 0;\n#endif\n",
    "foo.c", opts,
  )
  assert_eq(result.text, "int threaded=1;\n")
}

///|
fn preprocess_driver_pic_pie(argv : Array[String]) -> String {
  let opts = match parse_driver_args(argv) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  let source = "#ifdef __PIC__\nint pic = __PIC__;\n#else\nint pic = 0;\n#endif\n#ifdef __PIE__\nint pie = __PIE__;\n#else\nint pie = 0;\n#endif\n"
  let result = preprocess_source_with_dependencies(source, "foo.c", opts)
  result.text
}

///|
test "driver seeds pic and pie predefined macros" {
  assert_eq(
    preprocess_driver_pic_pie(["kimicc", "-E", "-fpic", "foo.c"]),
    "int pic=1;\nint pie=0;\n",
  )
  assert_eq(
    preprocess_driver_pic_pie(["kimicc", "-E", "-fPIC", "foo.c"]),
    "int pic=2;\nint pie=0;\n",
  )
  assert_eq(
    preprocess_driver_pic_pie(["kimicc", "-E", "-fpie", "foo.c"]),
    "int pic=1;\nint pie=1;\n",
  )
  assert_eq(
    preprocess_driver_pic_pie(["kimicc", "-E", "-fPIE", "foo.c"]),
    "int pic=2;\nint pie=2;\n",
  )
}

///|
test "driver applies pic and pie macro options in order" {
  assert_eq(
    preprocess_driver_pic_pie(["kimicc", "-E", "-fpie", "-fPIC", "foo.c"]),
    "int pic=2;\nint pie=0;\n",
  )
  assert_eq(
    preprocess_driver_pic_pie(["kimicc", "-E", "-fPIC", "-fpie", "foo.c"]),
    "int pic=1;\nint pie=1;\n",
  )
  assert_eq(
    preprocess_driver_pic_pie(["kimicc", "-E", "-fPIE", "-fno-pie", "foo.c"]),
    "int pic=0;\nint pie=0;\n",
  )
  assert_eq(
    preprocess_driver_pic_pie(["kimicc", "-E", "-fno-pic", "-fPIC", "foo.c"]),
    "int pic=2;\nint pie=0;\n",
  )
}

///|
fn preprocess_driver_hosted(argv : Array[String]) -> String {
  let opts = match parse_driver_args(argv) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  let source = "#ifdef __STDC_HOSTED__\nint hosted = __STDC_HOSTED__;\n#else\nint hosted = -1;\n#endif\n"
  let result = preprocess_source_with_dependencies(source, "foo.c", opts)
  result.text
}

///|
test "driver honors hosted and freestanding mode macros" {
  assert_eq(
    preprocess_driver_hosted(["kimicc", "-E", "foo.c"]),
    "int hosted=1;\n",
  )
  assert_eq(
    preprocess_driver_hosted(["kimicc", "-E", "-ffreestanding", "foo.c"]),
    "int hosted=0;\n",
  )
  assert_eq(
    preprocess_driver_hosted([
      "kimicc", "-E", "-ffreestanding", "-fhosted", "foo.c",
    ]),
    "int hosted=1;\n",
  )
  assert_eq(
    preprocess_driver_hosted([
      "kimicc", "-E", "-fhosted", "-ffreestanding", "foo.c",
    ]),
    "int hosted=0;\n",
  )
}

///|
test "driver leaves hosted macro overrides after mode selection" {
  assert_eq(
    preprocess_driver_hosted([
      "kimicc", "-E", "-D__STDC_HOSTED__=9", "-ffreestanding", "foo.c",
    ]),
    "int hosted=9;\n",
  )
  assert_eq(
    preprocess_driver_hosted([
      "kimicc", "-E", "-ffreestanding", "-D__STDC_HOSTED__=9", "foo.c",
    ]),
    "int hosted=9;\n",
  )
  assert_eq(
    preprocess_driver_hosted([
      "kimicc", "-E", "-U__STDC_HOSTED__", "-ffreestanding", "foo.c",
    ]),
    "int hosted=-1;\n",
  )
}

///|
fn preprocess_driver_standard(argv : Array[String]) -> String {
  let opts = match parse_driver_args(argv) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  let source = "#ifdef __STDC_VERSION__\nlong version = __STDC_VERSION__;\n#else\nlong version = 0;\n#endif\n#ifdef __STRICT_ANSI__\nint strict = __STRICT_ANSI__;\n#else\nint strict = 0;\n#endif\n"
  let result = preprocess_source_with_dependencies(source, "foo.c", opts)
  result.text
}

///|
test "driver maps std options to predefined standard macros" {
  assert_eq(
    preprocess_driver_standard(["kimicc", "-E", "foo.c"]),
    "long version=201112L;\nint strict=0;\n",
  )
  assert_eq(
    preprocess_driver_standard(["kimicc", "-E", "-std=c89", "foo.c"]),
    "long version=0;\nint strict=1;\n",
  )
  assert_eq(
    preprocess_driver_standard(["kimicc", "-E", "-std=gnu89", "foo.c"]),
    "long version=0;\nint strict=0;\n",
  )
  assert_eq(
    preprocess_driver_standard(["kimicc", "-E", "-std=c99", "foo.c"]),
    "long version=199901L;\nint strict=1;\n",
  )
  assert_eq(
    preprocess_driver_standard(["kimicc", "-E", "-std=gnu17", "foo.c"]),
    "long version=201710L;\nint strict=0;\n",
  )
  assert_eq(
    preprocess_driver_standard(["kimicc", "-E", "--std=c23", "foo.c"]),
    "long version=202311L;\nint strict=1;\n",
  )
}

///|
test "driver applies std options and macro overrides in clang order" {
  assert_eq(
    preprocess_driver_standard([
      "kimicc", "-E", "-std=c99", "-std=gnu11", "foo.c",
    ]),
    "long version=201112L;\nint strict=0;\n",
  )
  assert_eq(
    preprocess_driver_standard([
      "kimicc", "-E", "-D__STDC_VERSION__=9L", "-std=c89", "foo.c",
    ]),
    "long version=9L;\nint strict=1;\n",
  )
  assert_eq(
    preprocess_driver_standard([
      "kimicc", "-E", "-U__STRICT_ANSI__", "-std=c11", "foo.c",
    ]),
    "long version=201112L;\nint strict=0;\n",
  )
  assert_eq(
    preprocess_driver_standard(["kimicc", "-E", "-ansi", "foo.c"]),
    "long version=0;\nint strict=1;\n",
  )
}

///|
fn preprocess_driver_optimization(argv : Array[String]) -> String {
  let opts = match parse_driver_args(argv) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  let source = "#ifdef __OPTIMIZE__\nint optimize = __OPTIMIZE__;\n#else\nint optimize = 0;\n#endif\n#ifdef __OPTIMIZE_SIZE__\nint size = __OPTIMIZE_SIZE__;\n#else\nint size = 0;\n#endif\n#ifdef __NO_INLINE__\nint no_inline = __NO_INLINE__;\n#else\nint no_inline = 0;\n#endif\n#ifdef __FAST_MATH__\nint fast = __FAST_MATH__;\n#else\nint fast = 0;\n#endif\n#ifdef __FINITE_MATH_ONLY__\nint finite = __FINITE_MATH_ONLY__;\n#else\nint finite = -1;\n#endif\n"
  let result = preprocess_source_with_dependencies(source, "foo.c", opts)
  result.text
}

///|
test "driver maps optimization options to predefined macros" {
  assert_eq(
    preprocess_driver_optimization(["kimicc", "-E", "foo.c"]),
    "int optimize=0;\nint size=0;\nint no_inline=1;\nint fast=0;\nint finite=0;\n",
  )
  assert_eq(
    preprocess_driver_optimization(["kimicc", "-E", "-O0", "foo.c"]),
    "int optimize=0;\nint size=0;\nint no_inline=1;\nint fast=0;\nint finite=0;\n",
  )
  assert_eq(
    preprocess_driver_optimization(["kimicc", "-E", "-O2", "foo.c"]),
    "int optimize=1;\nint size=0;\nint no_inline=0;\nint fast=0;\nint finite=0;\n",
  )
  assert_eq(
    preprocess_driver_optimization(["kimicc", "-E", "-Os", "foo.c"]),
    "int optimize=1;\nint size=1;\nint no_inline=0;\nint fast=0;\nint finite=0;\n",
  )
  assert_eq(
    preprocess_driver_optimization(["kimicc", "-E", "-Ofast", "foo.c"]),
    "int optimize=1;\nint size=0;\nint no_inline=0;\nint fast=1;\nint finite=1;\n",
  )
}

///|
test "driver applies optimization options and macro overrides in order" {
  assert_eq(
    preprocess_driver_optimization(["kimicc", "-E", "-Os", "-O0", "foo.c"]),
    "int optimize=0;\nint size=0;\nint no_inline=1;\nint fast=0;\nint finite=0;\n",
  )
  assert_eq(
    preprocess_driver_optimization(["kimicc", "-E", "-O0", "-Oz", "foo.c"]),
    "int optimize=1;\nint size=1;\nint no_inline=0;\nint fast=0;\nint finite=0;\n",
  )
  assert_eq(
    preprocess_driver_optimization(["kimicc", "-E", "-Ofast", "-O2", "foo.c"]),
    "int optimize=1;\nint size=0;\nint no_inline=0;\nint fast=0;\nint finite=0;\n",
  )
  assert_eq(
    preprocess_driver_optimization([
      "kimicc", "-E", "-D__OPTIMIZE__=9", "-O0", "foo.c",
    ]),
    "int optimize=9;\nint size=0;\nint no_inline=1;\nint fast=0;\nint finite=0;\n",
  )
  assert_eq(
    preprocess_driver_optimization([
      "kimicc", "-E", "-U__NO_INLINE__", "-O0", "foo.c",
    ]),
    "int optimize=0;\nint size=0;\nint no_inline=0;\nint fast=0;\nint finite=0;\n",
  )
}

///|
test "driver applies explicit fast math macros in clang order" {
  assert_eq(
    preprocess_driver_optimization(["kimicc", "-E", "-ffast-math", "foo.c"]),
    "int optimize=0;\nint size=0;\nint no_inline=1;\nint fast=1;\nint finite=1;\n",
  )
  assert_eq(
    preprocess_driver_optimization([
      "kimicc", "-E", "-ffast-math", "-fno-fast-math", "foo.c",
    ]),
    "int optimize=0;\nint size=0;\nint no_inline=1;\nint fast=0;\nint finite=0;\n",
  )
  assert_eq(
    preprocess_driver_optimization([
      "kimicc", "-E", "-fno-fast-math", "-ffast-math", "foo.c",
    ]),
    "int optimize=0;\nint size=0;\nint no_inline=1;\nint fast=1;\nint finite=1;\n",
  )
  assert_eq(
    preprocess_driver_optimization([
      "kimicc", "-E", "-ffast-math", "-O0", "foo.c",
    ]),
    "int optimize=0;\nint size=0;\nint no_inline=1;\nint fast=1;\nint finite=1;\n",
  )
  assert_eq(
    preprocess_driver_optimization([
      "kimicc", "-E", "-ffast-math", "-Ofast", "-O2", "foo.c",
    ]),
    "int optimize=1;\nint size=0;\nint no_inline=0;\nint fast=1;\nint finite=1;\n",
  )
}

///|
test "driver recognizes preprocessed inputs" {
  let opts = match parse_driver_args(["kimicc", "-fpreprocessed", "foo.c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.already_preprocessed)
  let text = "#define X 1\nint value = X;\n"
  let result = preprocess_source_with_dependencies(
    text,
    "foo.i",
    DriverOptions::new(),
  )
  assert_eq(result.text, text)
  assert_eq(result.dependency_records.length(), 1)
  assert_eq(result.dependency_records[0].path, "foo.i")
}

///|
test "driver splits response file content" {
  let args = match
    split_response_file_content(
      "-I include\\ dir -DNAME='two words' \"main file.c\" '' plain\\\\arg",
    ) {
    Ok(args) => args
    Err(err) => abort(err)
  }
  assert_eq(args, [
    "-I", "include dir", "-DNAME=two words", "main file.c", "", "plain\\arg",
  ])
}

///|
test "driver reports unterminated response quotes" {
  match split_response_file_content("-DNAME=\"unterminated") {
    Ok(_) => abort("expected unterminated quote to fail")
    Err(err) => assert_eq(err, "unterminated quote in response file")
  }
}

///|
test "driver expands nested response files" {
  let inner = "/tmp/kimicc-driver-inner.rsp"
  let outer = "/tmp/kimicc-driver-outer.rsp"
  assert_true(write_file(inner, "-DVALUE=7"))
  assert_true(write_file(outer, "@" + inner + " foo.c"))
  let opts = match parse_driver_args(["kimicc", "@" + outer]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.input_path is Some("foo.c"))
  assert_eq(opts.defines["VALUE"], "7")
}

///|
test "driver preserves darwin loader paths while expanding response files" {
  let opts = match
    parse_driver_args([
      "kimicc", "foo.o", "-install_name", "@rpath/libfoo.dylib", "-Xlinker", "@loader_path/lib",
      "-o", "tool",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(opts.linker_args, [
    "foo.o", "-install_name", "@rpath/libfoo.dylib", "-Xlinker", "@loader_path/lib",
  ])
}

///|
test "driver accepts multiple C sources in compile-only modes" {
  let opts = match parse_driver_args(["kimicc", "main.c", "helper.c", "-c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.output == EmitObject)
  assert_true(opts.input_path is Some("main.c"))
  assert_eq(opts.extra_input_paths, ["helper.c"])
  assert_eq(default_output_path(opts, "main.c"), "main.o")
  assert_eq(default_output_path(opts, "helper.c"), "helper.o")

  let asm_opts = match
    parse_driver_args(["kimicc", "-S", "main.c", "helper.c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(asm_opts.output == EmitAssembly)
  assert_true(asm_opts.input_path is Some("main.c"))
  assert_eq(asm_opts.extra_input_paths, ["helper.c"])
  assert_eq(default_output_path(asm_opts, "main.c"), "main.s")
  assert_eq(default_output_path(asm_opts, "helper.c"), "helper.s")
}

///|
test "driver accepts multiple assembly sources in object mode" {
  let opts = match parse_driver_args(["kimicc", "one.s", "two.s", "-c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.output == EmitObject)
  assert_true(opts.input_path is None)
  assert_eq(opts.assembly_input_paths, ["one.s", "two.s"])
  assert_eq(assembly_output_path(opts, "one.s"), "one.o")
  assert_eq(assembly_output_path(opts, "two.s"), "two.o")
}

///|
test "driver accepts mixed C and assembly sources in object mode" {
  let opts = match parse_driver_args(["kimicc", "main.c", "start.s", "-c"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.output == EmitObject)
  assert_true(opts.input_path is Some("main.c"))
  assert_eq(opts.extra_input_paths.length(), 0)
  assert_eq(opts.assembly_input_paths, ["start.s"])
  assert_eq(default_output_path(opts, "main.c"), "main.o")
  assert_eq(assembly_output_path(opts, "start.s"), "start.o")
  let early_mode_opts = match
    parse_driver_args(["kimicc", "-c", "main.c", "start.s"]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(early_mode_opts.input_path is Some("main.c"))
  assert_eq(early_mode_opts.assembly_input_paths, ["start.s"])
}

///|
test "driver rejects single output path with multiple compile inputs" {
  match
    parse_driver_args(["kimicc", "main.c", "helper.c", "-c", "-o", "out.o"]) {
    Ok(_) => abort("expected multiple compile-only sources with -o to fail")
    Err(err) =>
      assert_eq(err, "cannot specify -o when generating multiple output files")
  }
  match
    parse_driver_args(["kimicc", "main.c", "start.s", "-c", "-o", "out.o"]) {
    Ok(_) => abort("expected mixed compile-only inputs with -o to fail")
    Err(err) =>
      assert_eq(err, "cannot specify -o when generating multiple output files")
  }
}

///|
test "driver rejects single dependency path with multiple compile inputs" {
  match
    parse_driver_args([
      "kimicc", "main.c", "helper.c", "-c", "-MMD", "-MF", "deps.d",
    ]) {
    Ok(_) => abort("expected multiple compile-only sources with -MF to fail")
    Err(err) => assert_eq(err, "cannot specify -MF with multiple input files")
  }
}

///|
test "driver rejects assembly inputs outside object and link modes" {
  match parse_driver_args(["kimicc", "-S", "start.s"]) {
    Ok(_) => abort("expected assembly input in -S mode to fail")
    Err(err) =>
      assert_eq(err, "assembly inputs are only supported with -c or link mode")
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
test "driver parses clang dependency file option" {
  let opts = match
    parse_driver_args([
      "kimicc", "-c", "-MMD", "-dependency-file", "build/foo.d", "-dependency-dot",
      "build/foo.dot", "-module-dependency-dir", "build/modules", "-o", "build/foo.o",
      "src/foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.emit_dependencies)
  assert_true(!opts.dependency_include_system)
  assert_true(opts.dependency_output_path is Some("build/foo.d"))
  assert_true(opts.input_path is Some("src/foo.c"))
  assert_eq(opts.extra_input_paths.length(), 0)
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
test "driver applies macro options before forced includes" {
  let header = "/tmp/kimicc-driver-forced-include.h"
  assert_true(
    write_file(header, "#ifdef VALUE\nint from_header = VALUE;\n#endif\n"),
  )
  let opts = match
    parse_driver_args([
      "kimicc", "-include", header, "-UVALUE", "-DVALUE=11", "-E", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  let result = preprocess_source_with_dependencies(
    "int body = VALUE;\n", "foo.c", opts,
  )
  assert_eq(result.text, "int from_header=11;\nint body=11;\n")
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
      "kimicc", "-c", "-Wp,-MMD,build/foo.d,-MP,-dM,-undef,-MQ,build dir/foo.o,-DVALUE=3,-DINC(x)=((x)+1),-DEMPTY=,-UOLD",
      "-o", "build/foo.o", "src/foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.emit_dependencies)
  assert_true(opts.dump_macros)
  assert_true(opts.undef_predefined)
  assert_true(!opts.dependency_include_system)
  assert_true(opts.dependency_phony_targets)
  assert_true(opts.dependency_output_path is Some("build/foo.d"))
  assert_eq(opts.dependency_targets.length(), 1)
  assert_eq(opts.dependency_targets[0], "build\\ dir/foo.o")
  assert_eq(opts.defines["VALUE"], "3")
  assert_eq(opts.defines["INC(x)"], "((x)+1)")
  assert_eq(opts.defines["EMPTY"], "")
  assert_eq(opts.undefines.length(), 1)
  assert_eq(opts.undefines[0], "OLD")
}

///|
test "driver parses Wp include options" {
  let opts = match
    parse_driver_args([
      "kimicc", "-c", "-Wp,-MMD,-Iinclude,-isystem,sys,-isystem-after,after-sys,-idirafter,late-sys,-iquote,quote,-include,config.h",
      "-o", "build/foo.o", "src/foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_true(opts.emit_dependencies)
  assert_true(!opts.dependency_include_system)
  assert_true(opts.dependency_output_path is None)
  assert_eq(opts.include_paths, ["include", "quote"])
  assert_eq(opts.system_include_paths, ["sys"])
  assert_eq(opts.after_system_include_paths, ["after-sys", "late-sys"])
  assert_eq(opts.forced_includes, ["config.h"])
}

///|
test "driver parses Xpreprocessor macro and include options" {
  let header = "/tmp/kimicc-driver-xpreprocessor-include.h"
  assert_true(write_file(header, "int from_xpreprocessor = VALUE;\n"))
  let opts = match
    parse_driver_args([
      "kimicc", "-E", "-Xpreprocessor", "-D", "-Xpreprocessor", "VALUE=19", "-Xpreprocessor",
      "-include", "-Xpreprocessor", header, "-Xpreprocessor", "-I", "-Xpreprocessor",
      "include-x", "-Xpreprocessor", "-iquote", "-Xpreprocessor", "quote-x", "-Xpreprocessor",
      "-dM", "-Xpreprocessor", "-undef", "-Xpreprocessor", "-UOLD", "foo.c",
    ]) {
    Ok(opts) => opts
    Err(err) => abort(err)
  }
  assert_eq(opts.defines["VALUE"], "19")
  assert_true(opts.dump_macros)
  assert_true(opts.undef_predefined)
  assert_eq(opts.include_paths, ["include-x", "quote-x"])
  assert_eq(opts.undefines, ["OLD"])
  let result = preprocess_source_with_dependencies(
    "int body = VALUE;\n", "foo.c", opts,
  )
  assert_eq(result.text, "int from_xpreprocessor=19;\nint body=19;\n")
}
