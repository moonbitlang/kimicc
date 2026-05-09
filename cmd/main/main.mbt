///|
#borrow(path)
extern "c" fn moonbit_read_file(path : Bytes) -> Bytes = "moonbit_read_file"

///|
#borrow(path)
extern "c" fn moonbit_file_exists(path : Bytes) -> Bool = "moonbit_file_exists"

///|
#borrow(path, content)
extern "c" fn moonbit_write_file(path : Bytes, content : Bytes) -> Int = "moonbit_write_file"

///|
#borrow(cmd)
extern "c" fn moonbit_system(cmd : Bytes) -> Int = "moonbit_system"

///|
extern "c" fn moonbit_exit(code : Int) -> Unit = "moonbit_exit"

///|
priv enum DriverOutput {
  LinkExecutable
  EmitAssembly
  EmitObject
  EmitPreprocessed
} derive(Eq)

///|
priv struct DriverOptions {
  mut output : DriverOutput
  mut output_path : String?
  mut input_path : String?
  include_paths : Array[String]
  system_include_paths : Array[String]
  forced_includes : Array[String]
  defines : Map[String, String]
  undefines : Array[String]
  linker_args : Array[String]
  mut already_preprocessed : Bool
  mut no_standard_includes : Bool
  mut show_help : Bool
  mut show_version : Bool
}

///|
fn DriverOptions::new() -> DriverOptions {
  {
    output: LinkExecutable,
    output_path: None,
    input_path: None,
    include_paths: [],
    system_include_paths: [],
    forced_includes: [],
    defines: {},
    undefines: [],
    linker_args: [],
    already_preprocessed: false,
    no_standard_includes: false,
    show_help: false,
    show_version: false,
  }
}

///|
fn read_file(path : String) -> String? {
  let encoded = @utf8.encode(path)
  let bytes = moonbit_read_file(encoded)
  if bytes.length() == 0 && !moonbit_file_exists(encoded) {
    None
  } else {
    Some(@utf8.decode_lossy(bytes))
  }
}

///|
fn write_file(path : String, content : String) -> Bool {
  let rc = moonbit_write_file(@utf8.encode(path), @utf8.encode(content))
  rc == 0
}

///|
fn write_bytes_file(path : String, content : Bytes) -> Bool {
  let rc = moonbit_write_file(@utf8.encode(path), content)
  rc == 0
}

///|
fn fail(message : String) -> Unit {
  println("error: " + message)
  moonbit_exit(1)
}

///|
fn starts_with(value : String, prefix : String) -> Bool {
  value.length() >= prefix.length() &&
  value[0:prefix.length()].to_owned() == prefix
}

///|
fn ends_with(value : String, suffix : String) -> Bool {
  value.length() >= suffix.length() &&
  value[value.length() - suffix.length():].to_owned() == suffix
}

///|
fn split_define_arg(arg : String) -> (String, String) {
  let mut eq = -1
  for i = 0; i < arg.length(); i = i + 1 {
    if arg[i] == '=' {
      eq = i
      break
    }
  }
  if eq < 0 {
    (arg, "1")
  } else {
    (arg[0:eq].to_owned(), arg[eq + 1:].to_owned())
  }
}

///|
fn option_value(
  argv : Array[String],
  index : Int,
  prefix : String,
  name : String,
) -> Result[(String, Int), String] {
  let arg = argv[index]
  if arg.length() > prefix.length() {
    Ok((arg[prefix.length():].to_owned(), index))
  } else if index + 1 < argv.length() {
    Ok((argv[index + 1], index + 1))
  } else {
    Err("missing argument after " + name)
  }
}

///|
fn long_option_value(
  argv : Array[String],
  index : Int,
  name : String,
) -> Result[(String, Int), String] {
  let arg = argv[index]
  let eq_prefix = name + "="
  if starts_with(arg, eq_prefix) {
    Ok((arg[eq_prefix.length():].to_owned(), index))
  } else if arg == name {
    if index + 1 < argv.length() {
      Ok((argv[index + 1], index + 1))
    } else {
      Err("missing argument after " + name)
    }
  } else {
    Err("internal driver option mismatch: " + name)
  }
}

///|
fn add_define(opts : DriverOptions, raw : String) -> Unit {
  let (name, value) = split_define_arg(raw)
  if name != "" {
    opts.defines[name] = value
  }
}

///|
fn is_c_source_path(path : String) -> Bool {
  ends_with(path, ".c") || ends_with(path, ".i")
}

///|
fn is_linker_input(path : String) -> Bool {
  ends_with(path, ".o") ||
  ends_with(path, ".a") ||
  ends_with(path, ".dylib") ||
  ends_with(path, ".so")
}

///|
fn add_positional(opts : DriverOptions, value : String) -> Result[Unit, String] {
  match opts.input_path {
    None =>
      if is_linker_input(value) {
        opts.linker_args.push(value)
      } else {
        opts.input_path = Some(value)
      }
    Some(_) =>
      if opts.output == LinkExecutable && is_linker_input(value) {
        opts.linker_args.push(value)
      } else if opts.output == LinkExecutable && !is_c_source_path(value) {
        opts.linker_args.push(value)
      } else {
        return Err("multiple C source inputs are not supported yet: " + value)
      }
  }
  Ok(())
}

///|
fn consume_ignored_option(
  opts : DriverOptions,
  argv : Array[String],
  index : Int,
  arg : String,
) -> Result[Int, String] {
  match arg {
    "-arch"
    | "-target"
    | "-std"
    | "-x"
    | "-Xclang"
    | "-Xpreprocessor"
    | "-include-pch"
    | "-imacros"
    | "-iframework" =>
      if index + 1 < argv.length() {
        Ok(index + 1)
      } else {
        Err("missing argument after " + arg)
      }
    "-isysroot" | "--sysroot" =>
      if index + 1 < argv.length() {
        opts.system_include_paths.push(argv[index + 1] + "/usr/include")
        Ok(index + 1)
      } else {
        Err("missing argument after " + arg)
      }
    "-MF" | "-MT" | "-MQ" =>
      if index + 1 < argv.length() {
        Ok(index + 1)
      } else {
        Err("missing argument after " + arg)
      }
    _ =>
      if starts_with(arg, "-isysroot") && arg.length() > "-isysroot".length() {
        opts.system_include_paths.push(
          arg["-isysroot".length():].to_owned() + "/usr/include",
        )
        Ok(index)
      } else if starts_with(arg, "--sysroot=") {
        opts.system_include_paths.push(
          arg["--sysroot=".length():].to_owned() + "/usr/include",
        )
        Ok(index)
      } else if starts_with(arg, "-MF") ||
        starts_with(arg, "-MT") ||
        starts_with(arg, "-MQ") ||
        starts_with(arg, "-std=") ||
        starts_with(arg, "-x") ||
        starts_with(arg, "-O") ||
        starts_with(arg, "-g") ||
        starts_with(arg, "-W") ||
        starts_with(arg, "-f") ||
        starts_with(arg, "-m") ||
        starts_with(arg, "-M") ||
        starts_with(arg, "-Wp,") ||
        starts_with(arg, "-Wa,") ||
        arg == "-pipe" ||
        arg == "-pedantic" ||
        arg == "-ansi" ||
        arg == "-Qunused-arguments" {
        Ok(index)
      } else {
        Ok(index)
      }
  }
}

///|
fn consume_linker_option(
  opts : DriverOptions,
  argv : Array[String],
  index : Int,
  arg : String,
) -> Result[Int, String] {
  match arg {
    "-framework" | "-F" | "-L" | "-Xlinker" | "-filelist" =>
      if index + 1 < argv.length() {
        opts.linker_args.push(arg)
        opts.linker_args.push(argv[index + 1])
        Ok(index + 1)
      } else {
        Err("missing argument after " + arg)
      }
    _ =>
      if starts_with(arg, "-l") ||
        starts_with(arg, "-L") ||
        starts_with(arg, "-F") ||
        starts_with(arg, "-Wl,") ||
        arg == "-pthread" ||
        arg == "-shared" ||
        arg == "-dynamiclib" ||
        arg == "-bundle" ||
        arg == "-rdynamic" {
        opts.linker_args.push(arg)
        Ok(index)
      } else {
        consume_ignored_option(opts, argv, index, arg)
      }
  }
}

///|
fn parse_driver_args(argv : Array[String]) -> Result[DriverOptions, String] {
  let opts = DriverOptions::new()
  let mut i = 1
  while i < argv.length() {
    let arg = argv[i]
    if arg == "--" {
      i = i + 1
      while i < argv.length() {
        match add_positional(opts, argv[i]) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
        i = i + 1
      }
      continue
    }
    match arg {
      "-h" | "--help" => opts.show_help = true
      "-v" | "--version" => opts.show_version = true
      "-E" | "--preprocess-only" => opts.output = EmitPreprocessed
      "-S" => opts.output = EmitAssembly
      "-c" | "--compile" => opts.output = EmitObject
      "--preprocessed" => opts.already_preprocessed = true
      "-nostdinc" => opts.no_standard_includes = true
      "-o" =>
        match option_value(argv, i, "-o", "-o") {
          Ok((value, next_i)) => {
            opts.output_path = Some(value)
            i = next_i
          }
          Err(err) => return Err(err)
        }
      _ =>
        if starts_with(arg, "--output=") || arg == "--output" {
          match long_option_value(argv, i, "--output") {
            Ok((value, next_i)) => {
              opts.output_path = Some(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if starts_with(arg, "-o") && arg.length() > 2 {
          opts.output_path = Some(arg[2:].to_owned())
        } else if arg == "-I" || starts_with(arg, "-I") {
          match option_value(argv, i, "-I", "-I") {
            Ok((value, next_i)) => {
              opts.include_paths.push(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if starts_with(arg, "--include=") || arg == "--include" {
          match long_option_value(argv, i, "--include") {
            Ok((value, next_i)) => {
              opts.include_paths.push(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if arg == "-isystem" || starts_with(arg, "-isystem") {
          match option_value(argv, i, "-isystem", "-isystem") {
            Ok((value, next_i)) => {
              opts.system_include_paths.push(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if starts_with(arg, "--isystem=") || arg == "--isystem" {
          match long_option_value(argv, i, "--isystem") {
            Ok((value, next_i)) => {
              opts.system_include_paths.push(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if arg == "-iquote" || starts_with(arg, "-iquote") {
          match option_value(argv, i, "-iquote", "-iquote") {
            Ok((value, next_i)) => {
              opts.include_paths.push(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if arg == "-idirafter" || starts_with(arg, "-idirafter") {
          match option_value(argv, i, "-idirafter", "-idirafter") {
            Ok((value, next_i)) => {
              opts.system_include_paths.push(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if arg == "-D" || starts_with(arg, "-D") {
          match option_value(argv, i, "-D", "-D") {
            Ok((value, next_i)) => {
              add_define(opts, value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if starts_with(arg, "--define=") || arg == "--define" {
          match long_option_value(argv, i, "--define") {
            Ok((value, next_i)) => {
              add_define(opts, value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if arg == "-U" || starts_with(arg, "-U") {
          match option_value(argv, i, "-U", "-U") {
            Ok((value, next_i)) => {
              opts.undefines.push(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if starts_with(arg, "--undefine=") || arg == "--undefine" {
          match long_option_value(argv, i, "--undefine") {
            Ok((value, next_i)) => {
              opts.undefines.push(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if arg == "-include-pch" {
          match consume_ignored_option(opts, argv, i, arg) {
            Ok(next_i) => i = next_i
            Err(err) => return Err(err)
          }
        } else if arg == "-include" || starts_with(arg, "-include") {
          match option_value(argv, i, "-include", "-include") {
            Ok((value, next_i)) => {
              opts.forced_includes.push(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if starts_with(arg, "-") {
          match consume_linker_option(opts, argv, i, arg) {
            Ok(next_i) => i = next_i
            Err(err) => return Err(err)
          }
        } else {
          match add_positional(opts, arg) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        }
    }
    i = i + 1
  }
  Ok(opts)
}

///|
fn standard_system_include_paths() -> Array[String] {
  [
    "/Library/Developer/CommandLineTools/usr/lib/clang/17/include", "/Library/Developer/CommandLineTools/usr/lib/clang/17.0.0/include",
    "/Library/Developer/CommandLineTools/usr/lib/clang/18/include", "/Library/Developer/CommandLineTools/usr/lib/clang/16/include",
    "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include", "/Library/Developer/CommandLineTools/usr/include",
    "/opt/homebrew/include", "/usr/local/include",
  ]
}

///|
fn full_system_include_paths(opts : DriverOptions) -> Array[String] {
  let paths : Array[String] = []
  for path in opts.system_include_paths {
    paths.push(path)
  }
  if !opts.no_standard_includes {
    for path in standard_system_include_paths() {
      paths.push(path)
    }
  }
  paths
}

///|
fn preprocess_options(
  input_path : String,
  opts : DriverOptions,
) -> @preprocessor.PreprocessOptions {
  {
    filename: input_path,
    include_paths: opts.include_paths,
    system_include_paths: full_system_include_paths(opts),
    defines: opts.defines,
    undefines: opts.undefines,
    emit_line_markers: false,
  }
}

///|
fn c_string_literal(value : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('"')
  for ch in value {
    if ch == '\\' || ch == '"' {
      buf.write_char('\\')
      buf.write_char(ch)
    } else {
      buf.write_char(ch)
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
fn forced_include_prefix(opts : DriverOptions) -> String {
  let buf = StringBuilder::new()
  for path in opts.forced_includes {
    buf.write_string("#include ")
    buf.write_string(c_string_literal(path))
    buf.write_char('\n')
  }
  buf.to_string()
}

///|
fn source_id(source : String) -> String {
  let mut h = 0
  for ch in source {
    h = h * 31 + ch.to_int()
  }
  h.to_string()
}

///|
fn shell_quote(value : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string("'")
  for ch in value {
    if ch.to_int() == 39 {
      buf.write_string("'\\''")
    } else {
      buf.write_char(ch)
    }
  }
  buf.write_string("'")
  buf.to_string()
}

///|
fn shell_join_quoted(values : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for value in values {
    if first {
      first = false
    } else {
      buf.write_char(' ')
    }
    buf.write_string(shell_quote(value))
  }
  buf.to_string()
}

///|
fn temp_file_path(prefix : String, seed : String, suffix : String) -> String {
  "/tmp/kimicc_" + prefix + "_" + source_id(seed) + suffix
}

///|
fn replace_extension(path : String, suffix : String) -> String {
  let mut slash = -1
  let mut dot = -1
  for i = 0; i < path.length(); i = i + 1 {
    if path[i] == '/' {
      slash = i
      dot = -1
    } else if path[i] == '.' {
      dot = i
    }
  }
  if dot > slash {
    path[0:dot].to_owned() + suffix
  } else {
    path + suffix
  }
}

///|
fn default_output_path(opts : DriverOptions, input_path : String) -> String {
  match opts.output_path {
    Some(path) => path
    None =>
      match opts.output {
        EmitPreprocessed => "-"
        EmitAssembly => replace_extension(input_path, ".s")
        EmitObject => replace_extension(input_path, ".o")
        LinkExecutable => "a.out"
      }
  }
}

///|
fn generate_assembly(source : String, opts : DriverOptions) -> String {
  let parser_input = if opts.already_preprocessed {
    if opts.forced_includes.length() > 0 {
      fail("--preprocessed cannot be combined with -include")
    }
    source
  } else {
    let preprocessed_source = forced_include_prefix(opts) + source
    match
      @preprocessor.preprocess(
        preprocessed_source,
        preprocess_options(
          match opts.input_path {
            Some(path) => path
            None => "<stdin>"
          },
          opts,
        ),
      ) {
      Ok(text) => text
      Err(err) => {
        fail(err.to_string())
        ""
      }
    }
  }
  let prog = @parser.parse(parser_input)
  let codegen = @codegen.Codegen::new()
  codegen.generate(prog)
}

///|
fn preprocess_source(
  source : String,
  input_path : String,
  opts : DriverOptions,
) -> String {
  if opts.already_preprocessed {
    if opts.forced_includes.length() > 0 {
      fail("--preprocessed cannot be combined with -include")
    }
    source
  } else {
    let preprocessed_source = forced_include_prefix(opts) + source
    match
      @preprocessor.preprocess(
        preprocessed_source,
        preprocess_options(input_path, opts),
      ) {
      Ok(text) => text
      Err(err) => {
        fail(err.to_string())
        ""
      }
    }
  }
}

///|
fn link_args(
  opts : DriverOptions,
  output_path : String,
  primary_input : String?,
) -> Array[String] {
  let args : Array[String] = ["clang", "-o", output_path]
  match primary_input {
    Some(path) => args.push(path)
    None => ()
  }
  for arg in opts.linker_args {
    args.push(arg)
  }
  args
}

///|
fn run_link(
  opts : DriverOptions,
  output_path : String,
  primary_input : String?,
) -> Unit {
  let args = link_args(opts, output_path, primary_input)
  let rc = moonbit_system(@utf8.encode(shell_join_quoted(args)))
  if rc != 0 {
    fail("link failed with code " + rc.to_string())
  }
}

///|
fn print_usage() -> Unit {
  let text =
    #|usage: kimicc [options] input.c
    #|
    #|Modes:
    #|  -E                  preprocess only
    #|  -S                  compile to assembly
    #|  -c                  compile to a Mach-O relocatable object
    #|  default             compile one C source and delegate final linking to clang
    #|
    #|Preprocessor options:
    #|  -I DIR              add a quote include path
    #|  -isystem DIR        add a system include path
    #|  -D NAME[=VALUE]     define a macro
    #|  -U NAME             undefine a macro
    #|  -include FILE       include a file before the main source
    #|  -nostdinc           disable built-in macOS system include paths
    #|  --preprocessed      skip preprocessing and parse input as already preprocessed C
    #|
    #|Output options:
    #|  -o PATH             set output path
  println(text)
}

///|
fn compile_input(opts : DriverOptions, input_path : String) -> Unit {
  let source = match read_file(input_path) {
    Some(content) => content
    None => {
      fail("cannot read file: " + input_path)
      ""
    }
  }
  let output_path = default_output_path(opts, input_path)
  match opts.output {
    EmitPreprocessed => {
      let text = preprocess_source(source, input_path, opts)
      if output_path == "-" {
        println(text)
      } else if !write_file(output_path, text) {
        fail("cannot write file: " + output_path)
      }
    }
    EmitAssembly => {
      let assembly = generate_assembly(source, opts)
      if output_path == "-" {
        println(assembly)
      } else if !write_file(output_path, assembly) {
        fail("cannot write file: " + output_path)
      }
    }
    EmitObject => {
      if output_path == "-" {
        fail("direct object output to stdout is not supported")
      }
      let parser_input = preprocess_source(source, input_path, opts)
      let prog = @parser.parse(parser_input)
      let object = @codegen.generate_macho_object(prog)
      if !write_bytes_file(output_path, object) {
        fail("cannot write file: " + output_path)
      }
    }
    LinkExecutable => {
      let assembly = generate_assembly(source, opts)
      let asm_path = temp_file_path("driver", input_path + source, ".s")
      if !write_file(asm_path, assembly) {
        fail("cannot write temporary assembly: " + asm_path)
      }
      run_link(opts, output_path, Some(asm_path))
    }
  }
}

///|
fn main {
  let opts = match parse_driver_args(@env.args()) {
    Ok(opts) => opts
    Err(err) => {
      fail(err)
      return
    }
  }
  if opts.show_help {
    print_usage()
    return
  }
  if opts.show_version {
    println("kimicc 0.1.4")
    return
  }
  match opts.input_path {
    Some(input_path) => compile_input(opts, input_path)
    None =>
      if opts.output == LinkExecutable && opts.linker_args.length() > 0 {
        let output_path = match opts.output_path {
          Some(path) => path
          None => "a.out"
        }
        run_link(opts, output_path, None)
      } else {
        fail("no input file")
      }
  }
}
