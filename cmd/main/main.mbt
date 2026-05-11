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
#borrow(message)
extern "c" fn moonbit_write_stderr(message : Bytes) -> Unit = "moonbit_write_stderr"

///|
#borrow(message)
extern "c" fn moonbit_write_stdout(message : Bytes) -> Unit = "moonbit_write_stdout"

///|
extern "c" fn moonbit_exit(code : Int) -> Unit = "moonbit_exit"

///|
priv enum DriverOutput {
  LinkExecutable
  EmitAssembly
  EmitObject
  EmitPreprocessed
  EmitDependencies
  CheckSyntax
} derive(Eq)

///|
priv enum DriverMacroOp {
  Define(String, String)
  Undef(String)
}

///|
priv struct DriverOptions {
  mut output : DriverOutput
  mut target : @target.Target
  mut output_path : String?
  mut input_path : String?
  extra_input_paths : Array[String]
  mut emit_dependencies : Bool
  mut dependency_include_system : Bool
  mut dependency_phony_targets : Bool
  mut dependency_output_path : String?
  dependency_targets : Array[String]
  include_paths : Array[String]
  system_include_paths : Array[String]
  after_system_include_paths : Array[String]
  sysroot_paths : Array[String]
  mut include_prefix : String?
  forced_includes : Array[String]
  macro_ops : Array[DriverMacroOp]
  defines : Map[String, String]
  undefines : Array[String]
  linker_args : Array[String]
  assembly_input_paths : Array[String]
  toolchain_args : Array[String]
  mut input_language : String?
  mut already_preprocessed : Bool
  mut no_standard_includes : Bool
  mut show_help : Bool
  mut show_version : Bool
  mut verbose : Bool
  mut dump_machine : Bool
  mut dump_version : Bool
  mut print_target_triple : Bool
  mut print_resource_dir : Bool
  mut print_search_dirs : Bool
  mut print_sysroot : Bool
  mut print_sysroot_headers_suffix : Bool
  mut print_multiarch : Bool
  mut print_multi_directory : Bool
  mut print_multi_os_directory : Bool
  mut print_multi_lib : Bool
  mut print_libgcc_file_name : Bool
  mut print_prog_name : String?
  mut print_file_name : String?
}

///|
fn DriverOptions::new() -> DriverOptions {
  {
    output: LinkExecutable,
    target: @target.Target::default(),
    output_path: None,
    input_path: None,
    extra_input_paths: [],
    emit_dependencies: false,
    dependency_include_system: true,
    dependency_phony_targets: false,
    dependency_output_path: None,
    dependency_targets: [],
    include_paths: [],
    system_include_paths: [],
    after_system_include_paths: [],
    sysroot_paths: [],
    include_prefix: None,
    forced_includes: [],
    macro_ops: [],
    defines: {},
    undefines: [],
    linker_args: [],
    assembly_input_paths: [],
    toolchain_args: [],
    input_language: None,
    already_preprocessed: false,
    no_standard_includes: false,
    show_help: false,
    show_version: false,
    verbose: false,
    dump_machine: false,
    dump_version: false,
    print_target_triple: false,
    print_resource_dir: false,
    print_search_dirs: false,
    print_sysroot: false,
    print_sysroot_headers_suffix: false,
    print_multiarch: false,
    print_multi_directory: false,
    print_multi_os_directory: false,
    print_multi_lib: false,
    print_libgcc_file_name: false,
    print_prog_name: None,
    print_file_name: None,
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
fn write_stdout(content : String) -> Unit {
  moonbit_write_stdout(@utf8.encode(content))
}

///|
fn fail(message : String) -> Unit {
  moonbit_write_stderr(@utf8.encode("error: " + message + "\n"))
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
    opts.macro_ops.push(Define(name, value))
  }
}

///|
fn add_undefine(opts : DriverOptions, name : String) -> Unit {
  opts.undefines.push(name)
  opts.macro_ops.push(Undef(name))
}

///|
fn add_sysroot(opts : DriverOptions, spelling : String, path : String) -> Unit {
  opts.sysroot_paths.push(path)
  if spelling == "--sysroot" {
    opts.toolchain_args.push("--sysroot=" + path)
  } else {
    opts.toolchain_args.push(spelling)
    opts.toolchain_args.push(path)
  }
}

///|
fn add_resource_dir(opts : DriverOptions, path : String) -> Unit {
  opts.system_include_paths.push(path + "/include")
  opts.toolchain_args.push("-resource-dir")
  opts.toolchain_args.push(path)
}

///|
fn prefixed_include_path(opts : DriverOptions, path : String) -> String {
  match opts.include_prefix {
    Some(prefix) => prefix + path
    None => path
  }
}

///|
fn add_joined_toolchain_arg(
  opts : DriverOptions,
  spelling : String,
  value : String,
) -> Unit {
  opts.toolchain_args.push(spelling + "=" + value)
}

///|
fn add_pthread(opts : DriverOptions) -> Unit {
  opts.linker_args.push("-pthread")
  add_define(opts, "_REENTRANT=1")
}

///|
fn add_pic_macros(opts : DriverOptions, value : String) -> Unit {
  add_define(opts, "__PIC__=" + value)
  add_define(opts, "__pic__=" + value)
  add_undefine(opts, "__PIE__")
  add_undefine(opts, "__pie__")
}

///|
fn add_pie_macros(opts : DriverOptions, value : String) -> Unit {
  add_define(opts, "__PIC__=" + value)
  add_define(opts, "__pic__=" + value)
  add_define(opts, "__PIE__=" + value)
  add_define(opts, "__pie__=" + value)
}

///|
fn clear_pic_pie_macros(opts : DriverOptions) -> Unit {
  add_undefine(opts, "__PIC__")
  add_undefine(opts, "__pic__")
  add_undefine(opts, "__PIE__")
  add_undefine(opts, "__pie__")
}

///|
fn apply_dependency_mode(opts : DriverOptions, mode : String) -> Bool {
  match mode {
    "-M" => {
      opts.output = EmitDependencies
      opts.emit_dependencies = true
      opts.dependency_include_system = true
      true
    }
    "-MM" => {
      opts.output = EmitDependencies
      opts.emit_dependencies = true
      opts.dependency_include_system = false
      true
    }
    "-MD" => {
      opts.emit_dependencies = true
      opts.dependency_include_system = true
      true
    }
    "-MMD" => {
      opts.emit_dependencies = true
      opts.dependency_include_system = false
      true
    }
    "-MP" => {
      opts.dependency_phony_targets = true
      true
    }
    _ => false
  }
}

///|
fn is_wp_option_name(value : String) -> Bool {
  apply_dependency_mode(DriverOptions::new(), value) ||
  value == "-MF" ||
  value == "-MT" ||
  value == "-MQ" ||
  value == "-I" ||
  starts_with(value, "-I") ||
  value == "-include" ||
  starts_with(value, "-include") ||
  value == "-isystem-after" ||
  starts_with(value, "-isystem-after") ||
  value == "-isystem" ||
  starts_with(value, "-isystem") ||
  value == "-idirafter" ||
  starts_with(value, "-idirafter") ||
  value == "-iquote" ||
  starts_with(value, "-iquote") ||
  starts_with(value, "-D") ||
  starts_with(value, "-U")
}

///|
fn wp_option_value(
  parts : Array[String],
  index : Int,
  prefix : String,
  option : String,
) -> Result[(String, Int), String] {
  let part = parts[index]
  let value = part[prefix.length():].to_owned()
  if value != "" {
    Ok((value, index))
  } else if index + 1 < parts.length() {
    Ok((parts[index + 1], index + 1))
  } else {
    Err("missing argument after -Wp," + option)
  }
}

///|
fn apply_wp_options(opts : DriverOptions, arg : String) -> Result[Unit, String] {
  let body = arg["-Wp,".length():].to_owned()
  let parts : Array[String] = []
  for part in body.split(",") {
    parts.push(part.to_owned())
  }
  let mut i = 0
  while i < parts.length() {
    let part = parts[i]
    if apply_dependency_mode(opts, part) {
      if (part == "-MD" || part == "-MMD") &&
        i + 1 < parts.length() &&
        !is_wp_option_name(parts[i + 1]) {
        opts.dependency_output_path = Some(parts[i + 1])
        i += 1
      }
    } else if part == "-MF" {
      if i + 1 < parts.length() {
        opts.dependency_output_path = Some(parts[i + 1])
        i += 1
      } else {
        return Err("missing argument after -Wp,-MF")
      }
    } else if part == "-MT" {
      if i + 1 < parts.length() {
        opts.dependency_targets.push(parts[i + 1])
        i += 1
      } else {
        return Err("missing argument after -Wp,-MT")
      }
    } else if part == "-MQ" {
      if i + 1 < parts.length() {
        opts.dependency_targets.push(makefile_escape_path(parts[i + 1]))
        i += 1
      } else {
        return Err("missing argument after -Wp,-MQ")
      }
    } else if starts_with(part, "-D") {
      let value = part[2:].to_owned()
      if value == "" {
        if i + 1 < parts.length() {
          add_define(opts, parts[i + 1])
          i += 1
        } else {
          return Err("missing argument after -Wp,-D")
        }
      } else {
        add_define(opts, value)
      }
    } else if starts_with(part, "-U") {
      let value = part[2:].to_owned()
      if value == "" {
        if i + 1 < parts.length() {
          add_undefine(opts, parts[i + 1])
          i += 1
        } else {
          return Err("missing argument after -Wp,-U")
        }
      } else {
        add_undefine(opts, value)
      }
    } else if part == "-I" || starts_with(part, "-I") {
      match wp_option_value(parts, i, "-I", "-I") {
        Ok((value, next_i)) => {
          opts.include_paths.push(value)
          i = next_i
        }
        Err(err) => return Err(err)
      }
    } else if part == "-include-pch" {
      match wp_option_value(parts, i, "-include-pch", "-include-pch") {
        Ok((_value, next_i)) => i = next_i
        Err(err) => return Err(err)
      }
    } else if part == "-include" || starts_with(part, "-include") {
      match wp_option_value(parts, i, "-include", "-include") {
        Ok((value, next_i)) => {
          opts.forced_includes.push(value)
          i = next_i
        }
        Err(err) => return Err(err)
      }
    } else if part == "-isystem-after" || starts_with(part, "-isystem-after") {
      match wp_option_value(parts, i, "-isystem-after", "-isystem-after") {
        Ok((value, next_i)) => {
          opts.after_system_include_paths.push(value)
          i = next_i
        }
        Err(err) => return Err(err)
      }
    } else if part == "-isystem" || starts_with(part, "-isystem") {
      match wp_option_value(parts, i, "-isystem", "-isystem") {
        Ok((value, next_i)) => {
          opts.system_include_paths.push(value)
          i = next_i
        }
        Err(err) => return Err(err)
      }
    } else if part == "-idirafter" || starts_with(part, "-idirafter") {
      match wp_option_value(parts, i, "-idirafter", "-idirafter") {
        Ok((value, next_i)) => {
          opts.after_system_include_paths.push(value)
          i = next_i
        }
        Err(err) => return Err(err)
      }
    } else if part == "-iquote" || starts_with(part, "-iquote") {
      match wp_option_value(parts, i, "-iquote", "-iquote") {
        Ok((value, next_i)) => {
          opts.include_paths.push(value)
          i = next_i
        }
        Err(err) => return Err(err)
      }
    }
    i += 1
  }
  Ok(())
}

///|
fn xpreprocessor_value(
  argv : Array[String],
  index : Int,
  option : String,
) -> Result[(String, Int), String] {
  if index + 3 < argv.length() && argv[index + 2] == "-Xpreprocessor" {
    Ok((argv[index + 3], index + 3))
  } else {
    Err("missing argument after -Xpreprocessor " + option)
  }
}

///|
fn xpreprocessor_option_value(
  argv : Array[String],
  index : Int,
  prefix : String,
  option : String,
) -> Result[(String, Int), String] {
  let arg = argv[index + 1]
  let value = arg[prefix.length():].to_owned()
  if value != "" {
    Ok((value, index + 1))
  } else {
    xpreprocessor_value(argv, index, option)
  }
}

///|
fn consume_xpreprocessor_option(
  opts : DriverOptions,
  argv : Array[String],
  index : Int,
) -> Result[Int, String] {
  if index + 1 >= argv.length() {
    return Err("missing argument after -Xpreprocessor")
  }
  let part = argv[index + 1]
  if apply_dependency_mode(opts, part) {
    if (part == "-MD" || part == "-MMD") &&
      index + 3 < argv.length() &&
      argv[index + 2] == "-Xpreprocessor" &&
      !is_wp_option_name(argv[index + 3]) {
      opts.dependency_output_path = Some(argv[index + 3])
      Ok(index + 3)
    } else {
      Ok(index + 1)
    }
  } else if part == "-MF" || starts_with(part, "-MF") {
    match xpreprocessor_option_value(argv, index, "-MF", "-MF") {
      Ok((value, next_i)) => {
        opts.dependency_output_path = Some(value)
        Ok(next_i)
      }
      Err(err) => Err(err)
    }
  } else if part == "-MT" || starts_with(part, "-MT") {
    match xpreprocessor_option_value(argv, index, "-MT", "-MT") {
      Ok((value, next_i)) => {
        opts.dependency_targets.push(value)
        Ok(next_i)
      }
      Err(err) => Err(err)
    }
  } else if part == "-MQ" || starts_with(part, "-MQ") {
    match xpreprocessor_option_value(argv, index, "-MQ", "-MQ") {
      Ok((value, next_i)) => {
        opts.dependency_targets.push(makefile_escape_path(value))
        Ok(next_i)
      }
      Err(err) => Err(err)
    }
  } else if part == "-D" || starts_with(part, "-D") {
    match xpreprocessor_option_value(argv, index, "-D", "-D") {
      Ok((value, next_i)) => {
        add_define(opts, value)
        Ok(next_i)
      }
      Err(err) => Err(err)
    }
  } else if part == "-U" || starts_with(part, "-U") {
    match xpreprocessor_option_value(argv, index, "-U", "-U") {
      Ok((value, next_i)) => {
        add_undefine(opts, value)
        Ok(next_i)
      }
      Err(err) => Err(err)
    }
  } else if part == "-include-pch" {
    match xpreprocessor_value(argv, index, "-include-pch") {
      Ok((_value, next_i)) => Ok(next_i)
      Err(err) => Err(err)
    }
  } else if part == "-include" || starts_with(part, "-include") {
    match xpreprocessor_option_value(argv, index, "-include", "-include") {
      Ok((value, next_i)) => {
        opts.forced_includes.push(value)
        Ok(next_i)
      }
      Err(err) => Err(err)
    }
  } else if part == "-I" || starts_with(part, "-I") {
    match xpreprocessor_option_value(argv, index, "-I", "-I") {
      Ok((value, next_i)) => {
        opts.include_paths.push(value)
        Ok(next_i)
      }
      Err(err) => Err(err)
    }
  } else if part == "-iquote" || starts_with(part, "-iquote") {
    match xpreprocessor_option_value(argv, index, "-iquote", "-iquote") {
      Ok((value, next_i)) => {
        opts.include_paths.push(value)
        Ok(next_i)
      }
      Err(err) => Err(err)
    }
  } else if part == "-isystem-after" || starts_with(part, "-isystem-after") {
    match
      xpreprocessor_option_value(
        argv, index, "-isystem-after", "-isystem-after",
      ) {
      Ok((value, next_i)) => {
        opts.after_system_include_paths.push(value)
        Ok(next_i)
      }
      Err(err) => Err(err)
    }
  } else if part == "-isystem" || starts_with(part, "-isystem") {
    match xpreprocessor_option_value(argv, index, "-isystem", "-isystem") {
      Ok((value, next_i)) => {
        opts.system_include_paths.push(value)
        Ok(next_i)
      }
      Err(err) => Err(err)
    }
  } else if part == "-idirafter" || starts_with(part, "-idirafter") {
    match xpreprocessor_option_value(argv, index, "-idirafter", "-idirafter") {
      Ok((value, next_i)) => {
        opts.after_system_include_paths.push(value)
        Ok(next_i)
      }
      Err(err) => Err(err)
    }
  } else if starts_with(part, "-Wp,") {
    match apply_wp_options(opts, part) {
      Ok(_) => Ok(index + 1)
      Err(err) => Err(err)
    }
  } else {
    Ok(index + 1)
  }
}

///|
fn is_c_source_path(path : String) -> Bool {
  ends_with(path, ".c") || ends_with(path, ".i")
}

///|
fn is_preprocessed_source_path(path : String) -> Bool {
  ends_with(path, ".i")
}

///|
fn is_assembly_input(path : String) -> Bool {
  ends_with(path, ".s") || ends_with(path, ".S") || ends_with(path, ".asm")
}

///|
fn set_input_language(opts : DriverOptions, language : String) -> Unit {
  if language == "none" {
    opts.input_language = None
  } else {
    opts.input_language = Some(language)
  }
}

///|
fn language_is_c_source(language : String) -> Bool {
  language == "c" || language == "c-header" || language == "cpp-output"
}

///|
fn language_is_assembler(language : String) -> Bool {
  language == "assembler" || language == "assembler-with-cpp"
}

///|
fn treats_as_c_source(opts : DriverOptions, path : String) -> Bool {
  match opts.input_language {
    Some(language) => language_is_c_source(language)
    None => is_c_source_path(path)
  }
}

///|
fn treats_as_assembly_input(opts : DriverOptions, path : String) -> Bool {
  match opts.input_language {
    Some(language) => language_is_assembler(language)
    None => is_assembly_input(path)
  }
}

///|
fn is_linker_input(path : String) -> Bool {
  ends_with(path, ".o") ||
  ends_with(path, ".a") ||
  is_assembly_input(path) ||
  ends_with(path, ".dylib") ||
  ends_with(path, ".so")
}

///|
fn add_delegated_assembly_input(opts : DriverOptions, value : String) -> Unit {
  opts.linker_args.push(value)
  opts.assembly_input_paths.push(value)
}

///|
fn add_positional(opts : DriverOptions, value : String) -> Result[Unit, String] {
  match opts.input_path {
    None =>
      if treats_as_assembly_input(opts, value) {
        add_delegated_assembly_input(opts, value)
      } else if is_linker_input(value) && !treats_as_c_source(opts, value) {
        opts.linker_args.push(value)
      } else {
        opts.input_path = Some(value)
      }
    Some(_) =>
      if (opts.output == LinkExecutable || opts.output == EmitObject) &&
        treats_as_assembly_input(opts, value) {
        add_delegated_assembly_input(opts, value)
      } else if opts.output == LinkExecutable &&
        is_linker_input(value) &&
        !treats_as_c_source(opts, value) {
        opts.linker_args.push(value)
      } else if treats_as_c_source(opts, value) {
        opts.extra_input_paths.push(value)
      } else if opts.output == LinkExecutable &&
        !treats_as_c_source(opts, value) {
        opts.linker_args.push(value)
      } else {
        return Err(
          "multiple input files are not supported for this mode: " + value,
        )
      }
  }
  Ok(())
}

///|
fn response_arg_is_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

///|
fn split_response_file_content(
  content : String,
) -> Result[Array[String], String] {
  let args : Array[String] = []
  let mut current = StringBuilder::new()
  let mut has_current = false
  let mut quote : Char? = None
  let mut i = 0
  while i < content.length() {
    let ch = content[i].unsafe_to_char()
    match quote {
      Some(q) =>
        if ch == q {
          quote = None
        } else if ch == '\\' && i + 1 < content.length() {
          i += 1
          current.write_char(content[i].unsafe_to_char())
          has_current = true
        } else {
          current.write_char(ch)
          has_current = true
        }
      None =>
        if response_arg_is_space(ch) {
          if has_current {
            args.push(current.to_string())
            current = StringBuilder::new()
            has_current = false
          }
        } else if ch == '"' || ch == '\'' {
          quote = Some(ch)
          has_current = true
        } else if ch == '\\' && i + 1 < content.length() {
          i += 1
          current.write_char(content[i].unsafe_to_char())
          has_current = true
        } else {
          current.write_char(ch)
          has_current = true
        }
    }
    i += 1
  }
  match quote {
    Some(_) => Err("unterminated quote in response file")
    None => {
      if has_current {
        args.push(current.to_string())
      }
      Ok(args)
    }
  }
}

///|
fn expand_response_arg_into(
  expanded : Array[String],
  arg : String,
  depth : Int,
) -> Result[Unit, String] {
  if starts_with(arg, "@rpath/") ||
    starts_with(arg, "@loader_path/") ||
    starts_with(arg, "@executable_path/") {
    expanded.push(arg)
  } else if starts_with(arg, "@") && arg.length() > 1 {
    if depth >= 16 {
      return Err("response file nesting too deep: " + arg)
    }
    let path = arg[1:].to_owned()
    match read_file(path) {
      Some(content) =>
        match split_response_file_content(content) {
          Ok(parts) =>
            for part in parts {
              match expand_response_arg_into(expanded, part, depth + 1) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
            }
          Err(err) => return Err(err + ": " + path)
        }
      None => return Err("cannot read response file: " + path)
    }
  } else {
    expanded.push(arg)
  }
  Ok(())
}

///|
fn expand_response_args(argv : Array[String]) -> Result[Array[String], String] {
  let expanded : Array[String] = []
  for arg in argv {
    match expand_response_arg_into(expanded, arg, 0) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(expanded)
}

///|
fn consume_ignored_option(
  opts : DriverOptions,
  argv : Array[String],
  index : Int,
  arg : String,
) -> Result[Int, String] {
  match arg {
    "--config"
    | "-arch"
    | "-analyzer-output"
    | "-arcmt-migrate-report-output"
    | "-aux-info"
    | "-auxbase"
    | "-auxbase-strip"
    | "-b"
    | "-MJ"
    | "-std"
    | "--std"
    | "-Xclang"
    | "-Xpreprocessor"
    | "-Xanalyzer"
    | "-Xarch_device"
    | "-Xarch_host"
    | "-Xcuda-fatbinary"
    | "-Xcuda-ptxas"
    | "-Xopenmp-target"
    | "-cc1-args"
    | "-cxx-isystem"
    | "-darwin-target-variant"
    | "-darwin-target-variant-triple"
    | "-dependency-dot"
    | "-dumpbase"
    | "-dumpbase-ext"
    | "-dsym-dir"
    | "-dumpdir"
    | "-iapinotes-modules"
    | "-iapinotes-path"
    | "-include-pch"
    | "-imacros"
    | "-fdebug-compilation-dir"
    | "-fdepscan-share-identifier"
    | "-fexperimental-openacc-macro-override"
    | "-fmodules-user-build-path"
    | "-iframework"
    | "-iframeworkwithsysroot"
    | "-index-store-path"
    | "-index-unit-output-path"
    | "-ivfsoverlay"
    | "-ivfsstatcache"
    | "-iwithsysroot"
    | "-meabi"
    | "-mmlir"
    | "-mllvm"
    | "-module-dependency-dir"
    | "-mthread-model"
    | "-serialize-diagnostics"
    | "-stdlib++-isystem"
    | "--serialize-diagnostics"
    | "-vfsoverlay"
    | "-working-directory"
    | "--working-directory"
    | "-fmodule-map-file"
    | "-hlsl-entry"
    | "--param" =>
      if index + 1 < argv.length() {
        Ok(index + 1)
      } else {
        Err("missing argument after " + arg)
      }
    "-x" =>
      if index + 1 < argv.length() {
        set_input_language(opts, argv[index + 1])
        Ok(index + 1)
      } else {
        Err("missing argument after " + arg)
      }
    "-Xassembler" =>
      if index + 1 < argv.length() {
        opts.toolchain_args.push(arg)
        opts.toolchain_args.push(argv[index + 1])
        Ok(index + 1)
      } else {
        Err("missing argument after " + arg)
      }
    "-resource-dir" =>
      if index + 1 < argv.length() {
        add_resource_dir(opts, argv[index + 1])
        Ok(index + 1)
      } else {
        Err("missing argument after " + arg)
      }
    "-target" | "--target" =>
      if index + 1 < argv.length() {
        match @target.Target::parse(argv[index + 1]) {
          Some(t) => {
            opts.target = t
            Ok(index + 1)
          }
          None => Err("unsupported target: " + argv[index + 1])
        }
      } else {
        Err("missing argument after " + arg)
      }
    "-isysroot" | "--sysroot" =>
      if index + 1 < argv.length() {
        add_sysroot(opts, arg, argv[index + 1])
        Ok(index + 1)
      } else {
        Err("missing argument after " + arg)
      }
    "-iprefix" =>
      if index + 1 < argv.length() {
        opts.include_prefix = Some(argv[index + 1])
        Ok(index + 1)
      } else {
        Err("missing argument after " + arg)
      }
    "-iwithprefixbefore" =>
      if index + 1 < argv.length() {
        opts.include_paths.push(prefixed_include_path(opts, argv[index + 1]))
        Ok(index + 1)
      } else {
        Err("missing argument after " + arg)
      }
    "-iwithprefix" =>
      if index + 1 < argv.length() {
        opts.system_include_paths.push(
          prefixed_include_path(opts, argv[index + 1]),
        )
        Ok(index + 1)
      } else {
        Err("missing argument after " + arg)
      }
    "-B" =>
      if index + 1 < argv.length() {
        opts.toolchain_args.push(arg)
        opts.toolchain_args.push(argv[index + 1])
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
    "--gcc-toolchain" | "--gcc-install-dir" =>
      if index + 1 < argv.length() {
        add_joined_toolchain_arg(opts, arg, argv[index + 1])
        Ok(index + 1)
      } else {
        Err("missing argument after " + arg)
      }
    _ =>
      if starts_with(arg, "-isysroot") && arg.length() > "-isysroot".length() {
        add_sysroot(opts, "-isysroot", arg["-isysroot".length():].to_owned())
        Ok(index)
      } else if starts_with(arg, "--sysroot=") {
        add_sysroot(opts, "--sysroot", arg["--sysroot=".length():].to_owned())
        Ok(index)
      } else if starts_with(arg, "-resource-dir=") {
        add_resource_dir(opts, arg["-resource-dir=".length():].to_owned())
        Ok(index)
      } else if starts_with(arg, "-resource-dir") &&
        arg.length() > "-resource-dir".length() {
        add_resource_dir(opts, arg["-resource-dir".length():].to_owned())
        Ok(index)
      } else if starts_with(arg, "-iprefix") &&
        arg.length() > "-iprefix".length() {
        opts.include_prefix = Some(arg["-iprefix".length():].to_owned())
        Ok(index)
      } else if starts_with(arg, "-iwithprefixbefore") &&
        arg.length() > "-iwithprefixbefore".length() {
        opts.include_paths.push(
          prefixed_include_path(
            opts,
            arg["-iwithprefixbefore".length():].to_owned(),
          ),
        )
        Ok(index)
      } else if starts_with(arg, "-iwithprefix") &&
        arg.length() > "-iwithprefix".length() {
        opts.system_include_paths.push(
          prefixed_include_path(opts, arg["-iwithprefix".length():].to_owned()),
        )
        Ok(index)
      } else if starts_with(arg, "-serialize-diagnostics=") ||
        starts_with(arg, "--serialize-diagnostics=") ||
        starts_with(arg, "-working-directory=") ||
        starts_with(arg, "--working-directory=") ||
        starts_with(arg, "-fdebug-compilation-dir=") ||
        starts_with(arg, "-fmodule-map-file=") {
        Ok(index)
      } else if starts_with(arg, "--gcc-toolchain=") ||
        starts_with(arg, "--gcc-install-dir=") {
        opts.toolchain_args.push(arg)
        Ok(index)
      } else if starts_with(arg, "-x") && arg.length() > 2 {
        set_input_language(opts, arg[2:].to_owned())
        Ok(index)
      } else if starts_with(arg, "-Wa,") {
        opts.toolchain_args.push(arg)
        Ok(index)
      } else if starts_with(arg, "-B") && arg.length() > "-B".length() {
        opts.toolchain_args.push(arg)
        Ok(index)
      } else if starts_with(arg, "-Xarch_") ||
        starts_with(arg, "-Xoffload-linker") {
        if index + 1 < argv.length() {
          Ok(index + 1)
        } else {
          Err("missing argument after " + arg)
        }
      } else if starts_with(arg, "-Xopenmp-target=") {
        if index + 1 < argv.length() {
          Ok(index + 1)
        } else {
          Err("missing argument after " + arg)
        }
      } else if starts_with(arg, "--target=") {
        let value = arg["--target=".length():].to_owned()
        match @target.Target::parse(value) {
          Some(t) => {
            opts.target = t
            Ok(index)
          }
          None => Err("unsupported target: " + value)
        }
      } else if starts_with(arg, "-target") && arg.length() > "-target".length() {
        let value = arg["-target".length():].to_owned()
        match @target.Target::parse(value) {
          Some(t) => {
            opts.target = t
            Ok(index)
          }
          None => Err("unsupported target: " + value)
        }
      } else if arg == "-fpic" {
        add_pic_macros(opts, "1")
        Ok(index)
      } else if arg == "-fPIC" {
        add_pic_macros(opts, "2")
        Ok(index)
      } else if arg == "-fpie" {
        add_pie_macros(opts, "1")
        Ok(index)
      } else if arg == "-fPIE" {
        add_pie_macros(opts, "2")
        Ok(index)
      } else if arg == "-fno-pic" ||
        arg == "-fno-PIC" ||
        arg == "-fno-pie" ||
        arg == "-fno-PIE" {
        clear_pic_pie_macros(opts)
        Ok(index)
      } else if starts_with(arg, "-MF") ||
        starts_with(arg, "-MT") ||
        starts_with(arg, "-MQ") ||
        starts_with(arg, "-std=") ||
        starts_with(arg, "--std=") ||
        starts_with(arg, "-O") ||
        starts_with(arg, "-g") ||
        starts_with(arg, "-W") ||
        starts_with(arg, "-f") ||
        starts_with(arg, "-m") ||
        starts_with(arg, "-M") ||
        starts_with(arg, "-Wp,") ||
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
    "-framework"
    | "-l"
    | "-F"
    | "-L"
    | "-Xlinker"
    | "-compatibility_version"
    | "-current_version"
    | "-e"
    | "-filelist"
    | "-install_name"
    | "-rpath"
    | "-u"
    | "-z"
    | "-T" =>
      if index + 1 < argv.length() {
        opts.linker_args.push(arg)
        opts.linker_args.push(argv[index + 1])
        Ok(index + 1)
      } else {
        Err("missing argument after " + arg)
      }
    _ =>
      if arg == "-pthread" {
        add_pthread(opts)
        Ok(index)
      } else if starts_with(arg, "--library-directory=") {
        opts.linker_args.push("-L")
        opts.linker_args.push(arg["--library-directory=".length():].to_owned())
        Ok(index)
      } else if arg == "--library-directory" {
        if index + 1 < argv.length() {
          opts.linker_args.push("-L")
          opts.linker_args.push(argv[index + 1])
          Ok(index + 1)
        } else {
          Err("missing argument after " + arg)
        }
      } else if starts_with(arg, "-l") ||
        starts_with(arg, "-L") ||
        starts_with(arg, "-F") ||
        starts_with(arg, "-Wl,") ||
        starts_with(arg, "-fuse-ld=") ||
        starts_with(arg, "-rtlib=") ||
        starts_with(arg, "-stdlib=") ||
        starts_with(arg, "-unwindlib=") ||
        starts_with(arg, "--rtlib=") ||
        starts_with(arg, "--stdlib=") ||
        starts_with(arg, "--unwindlib=") ||
        arg == "-shared" ||
        arg == "--shared" ||
        arg == "-dynamiclib" ||
        arg == "-bundle" ||
        arg == "-rdynamic" ||
        arg == "--rdynamic" ||
        arg == "-static" ||
        arg == "--static" ||
        arg == "-static-pie" ||
        arg == "--static-pie" ||
        arg == "-static-libgcc" ||
        arg == "-static-libstdc++" ||
        arg == "-pie" ||
        arg == "-no-pie" ||
        arg == "--no-pie" ||
        arg == "-nostdlib" ||
        arg == "--nostdlib" ||
        arg == "-nodefaultlibs" ||
        arg == "--nodefaultlibs" ||
        arg == "-nostartfiles" ||
        arg == "--nostartfiles" ||
        arg == "-r" ||
        arg == "-s" {
        opts.linker_args.push(arg)
        Ok(index)
      } else {
        consume_ignored_option(opts, argv, index, arg)
      }
  }
}

///|
fn compile_only_input_count(opts : DriverOptions) -> Int {
  let mut count = opts.extra_input_paths.length() +
    opts.assembly_input_paths.length()
  match opts.input_path {
    Some(_) => count += 1
    None => ()
  }
  count
}

///|
fn validate_driver_options(opts : DriverOptions) -> Result[Unit, String] {
  if opts.output != LinkExecutable &&
    opts.output != EmitObject &&
    opts.assembly_input_paths.length() > 0 {
    Err("assembly inputs are only supported with -c or link mode")
  } else if opts.output != LinkExecutable && compile_only_input_count(opts) > 1 {
    match opts.output_path {
      Some(_) => Err("cannot specify -o when generating multiple output files")
      None =>
        if opts.emit_dependencies && opts.dependency_output_path is Some(_) {
          Err("cannot specify -MF with multiple input files")
        } else {
          Ok(())
        }
    }
  } else {
    Ok(())
  }
}

///|
fn parse_driver_args(argv : Array[String]) -> Result[DriverOptions, String] {
  let argv = match expand_response_args(argv) {
    Ok(args) => args
    Err(err) => return Err(err)
  }
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
      "-v" => opts.verbose = true
      "--version" => opts.show_version = true
      "-dumpmachine" | "--dumpmachine" => opts.dump_machine = true
      "-dumpversion"
      | "--dumpversion"
      | "-dumpfullversion"
      | "--dumpfullversion" => opts.dump_version = true
      "-print-target-triple" | "--print-target-triple" =>
        opts.print_target_triple = true
      "-print-resource-dir" | "--print-resource-dir" =>
        opts.print_resource_dir = true
      "-print-search-dirs" | "--print-search-dirs" =>
        opts.print_search_dirs = true
      "-print-sysroot" | "--print-sysroot" => opts.print_sysroot = true
      "-print-sysroot-headers-suffix" | "--print-sysroot-headers-suffix" =>
        opts.print_sysroot_headers_suffix = true
      "-print-multiarch" | "--print-multiarch" => opts.print_multiarch = true
      "-print-multi-directory" | "--print-multi-directory" =>
        opts.print_multi_directory = true
      "-print-multi-os-directory" | "--print-multi-os-directory" =>
        opts.print_multi_os_directory = true
      "-print-multi-lib" | "--print-multi-lib" => opts.print_multi_lib = true
      "-print-libgcc-file-name" | "--print-libgcc-file-name" =>
        opts.print_libgcc_file_name = true
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
        } else if starts_with(arg, "-print-prog-name=") {
          opts.print_prog_name = Some(
            arg["-print-prog-name=".length():].to_owned(),
          )
        } else if starts_with(arg, "--print-prog-name=") ||
          arg == "--print-prog-name" {
          match long_option_value(argv, i, "--print-prog-name") {
            Ok((value, next_i)) => {
              opts.print_prog_name = Some(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if starts_with(arg, "-print-file-name=") {
          opts.print_file_name = Some(
            arg["-print-file-name=".length():].to_owned(),
          )
        } else if starts_with(arg, "--print-file-name=") ||
          arg == "--print-file-name" {
          match long_option_value(argv, i, "--print-file-name") {
            Ok((value, next_i)) => {
              opts.print_file_name = Some(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if arg == "-fsyntax-only" {
          opts.output = CheckSyntax
        } else if arg == "-fpreprocessed" {
          opts.already_preprocessed = true
        } else if apply_dependency_mode(opts, arg) {
          ()
        } else if arg == "-MF" || starts_with(arg, "-MF") {
          match option_value(argv, i, "-MF", "-MF") {
            Ok((value, next_i)) => {
              opts.dependency_output_path = Some(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if arg == "-dependency-file" {
          if i + 1 < argv.length() {
            opts.dependency_output_path = Some(argv[i + 1])
            i = i + 1
          } else {
            return Err("missing argument after " + arg)
          }
        } else if arg == "-MT" || starts_with(arg, "-MT") {
          match option_value(argv, i, "-MT", "-MT") {
            Ok((value, next_i)) => {
              opts.dependency_targets.push(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if arg == "-MQ" || starts_with(arg, "-MQ") {
          match option_value(argv, i, "-MQ", "-MQ") {
            Ok((value, next_i)) => {
              opts.dependency_targets.push(makefile_escape_path(value))
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if arg == "-Xpreprocessor" {
          match consume_xpreprocessor_option(opts, argv, i) {
            Ok(next_i) => i = next_i
            Err(err) => return Err(err)
          }
        } else if starts_with(arg, "-Wp,") {
          match apply_wp_options(opts, arg) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        } else if arg == "-I" || starts_with(arg, "-I") {
          match option_value(argv, i, "-I", "-I") {
            Ok((value, next_i)) => {
              opts.include_paths.push(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if starts_with(arg, "--include-directory=") ||
          arg == "--include-directory" {
          match long_option_value(argv, i, "--include-directory") {
            Ok((value, next_i)) => {
              opts.include_paths.push(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if starts_with(arg, "--include=") || arg == "--include" {
          match long_option_value(argv, i, "--include") {
            Ok((value, next_i)) => {
              opts.forced_includes.push(value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if arg == "-isystem-after" || starts_with(arg, "-isystem-after") {
          match option_value(argv, i, "-isystem-after", "-isystem-after") {
            Ok((value, next_i)) => {
              opts.after_system_include_paths.push(value)
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
              opts.after_system_include_paths.push(value)
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
              add_undefine(opts, value)
              i = next_i
            }
            Err(err) => return Err(err)
          }
        } else if starts_with(arg, "--undefine=") || arg == "--undefine" {
          match long_option_value(argv, i, "--undefine") {
            Ok((value, next_i)) => {
              add_undefine(opts, value)
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
  match validate_driver_options(opts) {
    Ok(_) => Ok(opts)
    Err(err) => Err(err)
  }
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
fn linux_amd64_system_include_paths() -> Array[String] {
  [
    "/usr/lib/llvm-20/lib/clang/20/include", "/usr/lib/llvm-19/lib/clang/19/include",
    "/usr/lib/llvm-18/lib/clang/18/include", "/usr/lib/llvm-17/lib/clang/17/include",
    "/usr/lib/llvm-16/lib/clang/16/include", "/usr/lib/gcc/x86_64-linux-gnu/14/include",
    "/usr/lib/gcc/x86_64-linux-gnu/13/include", "/usr/local/include", "/usr/include/x86_64-linux-gnu",
    "/usr/include", "/usr/lib/clang/18/include", "/usr/lib/clang/17/include", "/usr/lib/clang/16/include",
  ]
}

///|
fn full_system_include_paths(opts : DriverOptions) -> Array[String] {
  let paths : Array[String] = []
  for path in opts.system_include_paths {
    paths.push(path)
  }
  for sysroot in opts.sysroot_paths {
    match opts.target {
      DarwinArm64 => paths.push(sysroot + "/usr/include")
      LinuxAmd64 => {
        paths.push(sysroot + "/usr/include/x86_64-linux-gnu")
        paths.push(sysroot + "/usr/include")
      }
    }
  }
  if !opts.no_standard_includes {
    match opts.target {
      DarwinArm64 =>
        for path in standard_system_include_paths() {
          paths.push(path)
        }
      LinuxAmd64 =>
        for path in linux_amd64_system_include_paths() {
          paths.push(path)
        }
    }
  }
  for path in opts.after_system_include_paths {
    paths.push(path)
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
    target: opts.target,
    include_paths: opts.include_paths,
    system_include_paths: full_system_include_paths(opts),
    defines: {},
    undefines: [],
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
fn command_line_macro_prefix(opts : DriverOptions) -> String {
  let buf = StringBuilder::new()
  for op in opts.macro_ops {
    match op {
      Define(name, replacement) => {
        buf.write_string("#define ")
        buf.write_string(name)
        if replacement != "" {
          buf.write_char(' ')
          buf.write_string(replacement)
        }
        buf.write_char('\n')
      }
      Undef(name) => {
        buf.write_string("#undef ")
        buf.write_string(name)
        buf.write_char('\n')
      }
    }
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
fn makefile_escape_path(value : String) -> String {
  let buf = StringBuilder::new()
  for ch in value {
    if ch == '$' {
      buf.write_string("$$")
    } else if ch == ' ' || ch == '#' || ch == ':' || ch == '\\' {
      buf.write_char('\\')
      buf.write_char(ch)
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
fn default_dependency_output_path(
  output_path : String,
  input_path : String,
) -> String {
  if output_path == "-" {
    replace_extension(input_path, ".d")
  } else {
    replace_extension(output_path, ".d")
  }
}

///|
fn dependency_output_path(
  opts : DriverOptions,
  input_path : String,
  output_path : String,
) -> String {
  match opts.dependency_output_path {
    Some(path) => path
    None => default_dependency_output_path(output_path, input_path)
  }
}

///|
fn dependency_target(
  opts : DriverOptions,
  input_path : String,
  output_path : String,
) -> String {
  if opts.dependency_targets.length() > 0 {
    let buf = StringBuilder::new()
    for i = 0; i < opts.dependency_targets.length(); i = i + 1 {
      if i > 0 {
        buf.write_char(' ')
      }
      buf.write_string(opts.dependency_targets[i])
    }
    buf.to_string()
  } else if output_path == "-" {
    makefile_escape_path(input_path)
  } else {
    makefile_escape_path(output_path)
  }
}

///|
fn dependency_file_content(
  opts : DriverOptions,
  input_path : String,
  output_path : String,
  dependencies : Array[String],
) -> String {
  let buf = StringBuilder::new()
  buf.write_string(dependency_target(opts, input_path, output_path))
  buf.write_string(":")
  let seen : Map[String, Bool] = {}
  for dep in dependencies {
    if !seen.contains(dep) {
      seen[dep] = true
      buf.write_char(' ')
      buf.write_string(makefile_escape_path(dep))
    }
  }
  if dependencies.length() == 0 {
    buf.write_char(' ')
    buf.write_string(makefile_escape_path(input_path))
  }
  buf.write_char('\n')
  if opts.dependency_phony_targets {
    let phony_seen : Map[String, Bool] = {}
    for dep in dependencies {
      if dep != input_path && !phony_seen.contains(dep) {
        phony_seen[dep] = true
        buf.write_char('\n')
        buf.write_string(makefile_escape_path(dep))
        buf.write_string(":\n")
      }
    }
  }
  buf.to_string()
}

///|
fn dependency_paths(
  opts : DriverOptions,
  dependency_records : Array[@preprocessor.PreprocessDependency],
) -> Array[String] {
  let paths : Array[String] = []
  for dep in dependency_records {
    if opts.dependency_include_system || !dep.system {
      paths.push(dep.path)
    }
  }
  paths
}

///|
fn dependency_rule_content(
  opts : DriverOptions,
  input_path : String,
  output_path : String,
  dependency_records : Array[@preprocessor.PreprocessDependency],
) -> String {
  dependency_file_content(
    opts,
    input_path,
    output_path,
    dependency_paths(opts, dependency_records),
  )
}

///|
fn write_dependency_file(
  opts : DriverOptions,
  input_path : String,
  output_path : String,
  dependency_records : Array[@preprocessor.PreprocessDependency],
) -> Unit {
  if opts.emit_dependencies {
    let path = dependency_output_path(opts, input_path, output_path)
    let content = dependency_rule_content(
      opts, input_path, output_path, dependency_records,
    )
    if path == "-" {
      write_stdout(content)
    } else if !write_file(path, content) {
      fail("cannot write dependency file: " + path)
    }
  }
}

///|
fn emit_dependency_output(
  opts : DriverOptions,
  input_path : String,
  output_path : String,
  dependency_records : Array[@preprocessor.PreprocessDependency],
) -> Unit {
  let content = dependency_rule_content(
    opts, input_path, output_path, dependency_records,
  )
  match dependency_only_destination_path(opts) {
    Some(path) =>
      if path == "-" {
        write_stdout(content)
      } else if !write_file(path, content) {
        fail("cannot write dependency file: " + path)
      }
    None => write_stdout(content)
  }
}

///|
fn dependency_only_destination_path(opts : DriverOptions) -> String? {
  match opts.dependency_output_path {
    Some(path) => Some(path)
    None => opts.output_path
  }
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
        EmitDependencies => "-"
        CheckSyntax => replace_extension(input_path, ".o")
        LinkExecutable => "a.out"
      }
  }
}

///|
priv struct DriverPreprocessResult {
  text : String
  dependency_records : Array[@preprocessor.PreprocessDependency]
}

///|
fn preprocess_source_with_dependencies(
  source : String,
  input_path : String,
  opts : DriverOptions,
) -> DriverPreprocessResult {
  if opts.already_preprocessed || is_preprocessed_source_path(input_path) {
    if opts.forced_includes.length() > 0 {
      fail("--preprocessed cannot be combined with -include")
    }
    { text: source, dependency_records: [{ path: input_path, system: false }] }
  } else {
    let preprocessed_source = command_line_macro_prefix(opts) +
      forced_include_prefix(opts) +
      source
    match
      @preprocessor.preprocess_with_dependencies(
        preprocessed_source,
        preprocess_options(input_path, opts),
      ) {
      Ok(result) =>
        { text: result.text, dependency_records: result.dependency_records }
      Err(err) => {
        fail(err.to_string())
        { text: "", dependency_records: [] }
      }
    }
  }
}

///|
fn generate_assembly_from_preprocessed(
  parser_input : String,
  opts : DriverOptions,
) -> String {
  let prog = @parser.parse(parser_input)
  @codegen.generate_assembly_for_target(prog, opts.target)
}

///|
fn link_args_with_inputs(
  opts : DriverOptions,
  output_path : String,
  primary_inputs : Array[String],
) -> Array[String] {
  let args : Array[String] = ["clang", "-o", output_path]
  match opts.target {
    DarwinArm64 => ()
    LinuxAmd64 => {
      args.push("-target")
      args.push(opts.target.triple())
    }
  }
  for arg in opts.toolchain_args {
    args.push(arg)
  }
  for path in primary_inputs {
    args.push(path)
  }
  for arg in opts.linker_args {
    args.push(arg)
  }
  args
}

///|
fn clang_query_args(opts : DriverOptions, query : String) -> Array[String] {
  let args : Array[String] = ["clang"]
  match opts.target {
    DarwinArm64 => ()
    LinuxAmd64 => {
      args.push("-target")
      args.push(opts.target.triple())
    }
  }
  for arg in opts.toolchain_args {
    args.push(arg)
  }
  args.push(query)
  args
}

///|
fn run_clang_query(opts : DriverOptions, query : String) -> Unit {
  let args = clang_query_args(opts, query)
  let rc = moonbit_system(@utf8.encode(shell_join_quoted(args)))
  if rc != 0 {
    fail("clang query failed with code " + rc.to_string())
  }
}

///|
fn driver_sysroot(opts : DriverOptions) -> String {
  if opts.sysroot_paths.length() == 0 {
    ""
  } else {
    opts.sysroot_paths[opts.sysroot_paths.length() - 1]
  }
}

///|
fn driver_multiarch(opts : DriverOptions) -> String {
  match opts.target {
    LinuxAmd64 => "x86_64-linux-gnu"
    DarwinArm64 => ""
  }
}

///|
fn driver_multi_os_directory(opts : DriverOptions) -> String {
  match opts.target {
    LinuxAmd64 => "../lib"
    DarwinArm64 => "."
  }
}

///|
fn link_args(
  opts : DriverOptions,
  output_path : String,
  primary_input : String?,
) -> Array[String] {
  let inputs : Array[String] = []
  match primary_input {
    Some(path) => inputs.push(path)
    None => ()
  }
  link_args_with_inputs(opts, output_path, inputs)
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
fn run_link_with_inputs(
  opts : DriverOptions,
  output_path : String,
  primary_inputs : Array[String],
) -> Unit {
  let args = link_args_with_inputs(opts, output_path, primary_inputs)
  let rc = moonbit_system(@utf8.encode(shell_join_quoted(args)))
  if rc != 0 {
    fail("link failed with code " + rc.to_string())
  }
}

///|
fn assemble_args(
  opts : DriverOptions,
  asm_path : String,
  output_path : String,
) -> Array[String] {
  let args : Array[String] = ["clang"]
  match opts.target {
    DarwinArm64 => ()
    LinuxAmd64 => {
      args.push("-target")
      args.push(opts.target.triple())
    }
  }
  for arg in opts.toolchain_args {
    args.push(arg)
  }
  match opts.input_language {
    Some(language) =>
      if language_is_assembler(language) {
        args.push("-x")
        args.push(language)
      }
    None => ()
  }
  args.push("-c")
  args.push(asm_path)
  args.push("-o")
  args.push(output_path)
  args
}

///|
fn assemble_with_clang(
  opts : DriverOptions,
  asm_path : String,
  output_path : String,
) -> Unit {
  let args = assemble_args(opts, asm_path, output_path)
  let rc = moonbit_system(@utf8.encode(shell_join_quoted(args)))
  if rc != 0 {
    fail("assemble failed with code " + rc.to_string())
  }
}

///|
fn assembly_output_path(opts : DriverOptions, input_path : String) -> String {
  match opts.output_path {
    Some(path) => path
    None => replace_extension(input_path, ".o")
  }
}

///|
fn compile_assembly_inputs(opts : DriverOptions) -> Unit {
  if opts.assembly_input_paths.length() == 0 {
    fail("no input file")
  }
  for input_path in opts.assembly_input_paths {
    if !treats_as_assembly_input(opts, input_path) {
      fail("no C input file")
    }
    assemble_with_clang(
      opts,
      input_path,
      assembly_output_path(opts, input_path),
    )
  }
}

///|
fn print_usage() -> Unit {
  let text =
    #|usage: kimicc [options] input.c [input2.c ...] [objects/libraries]
    #|
    #|Modes:
    #|  -E                  preprocess only
    #|  -S                  compile to assembly
    #|  -c                  compile to a relocatable object
    #|  -fsyntax-only       preprocess and parse without emitting output
    #|  -M, -MM             write dependencies only
    #|  default             compile C source inputs and delegate final linking to clang
    #|
    #|Preprocessor options:
    #|  -I DIR              add a quote include path
    #|  -isystem DIR        add a system include path
    #|  -D NAME[=VALUE]     define a macro
    #|  -U NAME             undefine a macro
    #|  -include FILE       include a file before the main source
    #|  -Wp,OPTS            forward supported comma-separated preprocessor options
    #|  -Xpreprocessor OPT  forward one supported preprocessor option
    #|  -nostdinc           disable built-in system include paths
    #|  --preprocessed      skip preprocessing and parse input as already preprocessed C
    #|
    #|Output options:
    #|  -o PATH             set output path
    #|  -target TARGET      choose darwin-arm64 or linux-amd64
    #|  -MD, -MMD           write a Makefile dependency sidecar
    #|  -MF PATH            set dependency sidecar path
    #|  -MT TARGET          set dependency rule target
    #|  -MQ TARGET          set and Makefile-quote dependency rule target
  println(text)
}

///|
fn compile_link_inputs(opts : DriverOptions, input_path : String) -> Unit {
  let output_path = default_output_path(opts, input_path)
  let source_paths : Array[String] = [input_path]
  for path in opts.extra_input_paths {
    source_paths.push(path)
  }
  let asm_paths : Array[String] = []
  let dependency_records : Array[@preprocessor.PreprocessDependency] = []
  for path in source_paths {
    let source = match read_file(path) {
      Some(content) => content
      None => {
        fail("cannot read file: " + path)
        ""
      }
    }
    let preprocessed = preprocess_source_with_dependencies(source, path, opts)
    if opts.emit_dependencies {
      for dep in preprocessed.dependency_records {
        dependency_records.push(dep)
      }
    }
    let assembly = generate_assembly_from_preprocessed(preprocessed.text, opts)
    let asm_path = temp_file_path("driver", path + source, ".s")
    if !write_file(asm_path, assembly) {
      fail("cannot write temporary assembly: " + asm_path)
    }
    asm_paths.push(asm_path)
  }
  run_link_with_inputs(opts, output_path, asm_paths)
  write_dependency_file(opts, input_path, output_path, dependency_records)
}

///|
fn compile_multiple_inputs(opts : DriverOptions, input_path : String) -> Unit {
  compile_input(opts, input_path)
  for path in opts.extra_input_paths {
    compile_input(opts, path)
  }
  for path in opts.assembly_input_paths {
    assemble_with_clang(opts, path, assembly_output_path(opts, path))
  }
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
      let preprocessed = preprocess_source_with_dependencies(
        source, input_path, opts,
      )
      if output_path == "-" {
        write_stdout(preprocessed.text)
      } else if !write_file(output_path, preprocessed.text) {
        fail("cannot write file: " + output_path)
      }
      write_dependency_file(
        opts,
        input_path,
        output_path,
        preprocessed.dependency_records,
      )
    }
    EmitDependencies => {
      let preprocessed = preprocess_source_with_dependencies(
        source, input_path, opts,
      )
      let rule_output_path = replace_extension(input_path, ".o")
      emit_dependency_output(
        opts,
        input_path,
        rule_output_path,
        preprocessed.dependency_records,
      )
    }
    EmitAssembly => {
      let preprocessed = preprocess_source_with_dependencies(
        source, input_path, opts,
      )
      let assembly = generate_assembly_from_preprocessed(
        preprocessed.text,
        opts,
      )
      if output_path == "-" {
        write_stdout(assembly)
      } else if !write_file(output_path, assembly) {
        fail("cannot write file: " + output_path)
      }
      write_dependency_file(
        opts,
        input_path,
        output_path,
        preprocessed.dependency_records,
      )
    }
    EmitObject => {
      if output_path == "-" {
        fail("direct object output to stdout is not supported")
      }
      match opts.target {
        DarwinArm64 => {
          let preprocessed = preprocess_source_with_dependencies(
            source, input_path, opts,
          )
          let prog = @parser.parse(preprocessed.text)
          let object = @codegen.generate_macho_object(prog)
          if !write_bytes_file(output_path, object) {
            fail("cannot write file: " + output_path)
          }
          write_dependency_file(
            opts,
            input_path,
            output_path,
            preprocessed.dependency_records,
          )
        }
        LinuxAmd64 => {
          let preprocessed = preprocess_source_with_dependencies(
            source, input_path, opts,
          )
          let assembly = generate_assembly_from_preprocessed(
            preprocessed.text,
            opts,
          )
          let asm_path = temp_file_path("object", input_path + source, ".s")
          if !write_file(asm_path, assembly) {
            fail("cannot write temporary assembly: " + asm_path)
          }
          assemble_with_clang(opts, asm_path, output_path)
          write_dependency_file(
            opts,
            input_path,
            output_path,
            preprocessed.dependency_records,
          )
        }
      }
    }
    CheckSyntax => {
      let preprocessed = preprocess_source_with_dependencies(
        source, input_path, opts,
      )
      let _ = @parser.parse(preprocessed.text)
      write_dependency_file(
        opts,
        input_path,
        output_path,
        preprocessed.dependency_records,
      )
    }
    LinkExecutable => {
      let preprocessed = preprocess_source_with_dependencies(
        source, input_path, opts,
      )
      let assembly = generate_assembly_from_preprocessed(
        preprocessed.text,
        opts,
      )
      let asm_path = temp_file_path("driver", input_path + source, ".s")
      if !write_file(asm_path, assembly) {
        fail("cannot write temporary assembly: " + asm_path)
      }
      run_link(opts, output_path, Some(asm_path))
      write_dependency_file(
        opts,
        input_path,
        output_path,
        preprocessed.dependency_records,
      )
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
  if opts.dump_machine || opts.print_target_triple {
    println(opts.target.triple())
    return
  }
  if opts.dump_version {
    println("0.1.4")
    return
  }
  if opts.print_resource_dir {
    run_clang_query(opts, "-print-resource-dir")
    return
  }
  if opts.print_search_dirs {
    run_clang_query(opts, "-print-search-dirs")
    return
  }
  if opts.print_sysroot {
    println(driver_sysroot(opts))
    return
  }
  if opts.print_sysroot_headers_suffix {
    fail("not configured with sysroot headers suffix")
    return
  }
  if opts.print_multiarch {
    println(driver_multiarch(opts))
    return
  }
  if opts.print_multi_directory {
    println(".")
    return
  }
  if opts.print_multi_os_directory {
    println(driver_multi_os_directory(opts))
    return
  }
  if opts.print_multi_lib {
    run_clang_query(opts, "-print-multi-lib")
    return
  }
  if opts.print_libgcc_file_name {
    run_clang_query(opts, "-print-libgcc-file-name")
    return
  }
  match opts.print_prog_name {
    Some(name) => {
      run_clang_query(opts, "-print-prog-name=" + name)
      return
    }
    None => ()
  }
  match opts.print_file_name {
    Some(name) => {
      run_clang_query(opts, "-print-file-name=" + name)
      return
    }
    None => ()
  }
  match opts.input_path {
    Some(input_path) =>
      if opts.extra_input_paths.length() > 0 ||
        opts.assembly_input_paths.length() > 0 {
        if opts.output == LinkExecutable {
          compile_link_inputs(opts, input_path)
        } else {
          compile_multiple_inputs(opts, input_path)
        }
      } else {
        compile_input(opts, input_path)
      }
    None =>
      if opts.output == EmitObject && opts.assembly_input_paths.length() > 0 {
        compile_assembly_inputs(opts)
      } else if opts.output == LinkExecutable && opts.linker_args.length() > 0 {
        let output_path = match opts.output_path {
          Some(path) => path
          None => "a.out"
        }
        run_link(opts, output_path, None)
      } else if opts.verbose && opts.output == LinkExecutable {
        println("kimicc 0.1.4")
      } else {
        fail("no input file")
      }
  }
}
