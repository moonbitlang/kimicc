///|
#borrow(path, content)
extern "c" fn moonbit_write_file(path : Bytes, content : Bytes) -> Int = "moonbit_write_file"

///|
#borrow(cmd)
extern "c" fn moonbit_system(cmd : Bytes) -> Int = "moonbit_system"

///|
fn compile(source : String) -> String {
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  codegen.generate(prog)
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
fn run_source(source : String) -> Int {
  let assembly = compile(source)
  let id = source_id(source)
  let asm_path = "/tmp/kimicc_test_" + id + ".s"
  let bin_path = "/tmp/kimicc_test_" + id
  write_text_file(asm_path, assembly)
  let link_rc = moonbit_system(
    @utf8.encode("clang -o " + bin_path + " " + asm_path),
  )
  if link_rc != 0 {
    abort("Link failed with code: " + link_rc.to_string())
  }
  run_command_exit_silent(shell_quote(bin_path), "run_source")
}

///|
fn run_source_against_mir_oracle(source : String) -> Unit {
  let program = @parser.parse(source)
  let expected = match
    @mir.lower(program, @target.Target::default()).interpret_i64("main", []) {
    Ok(value) => value
    Err(err) => abort("MIR oracle failed: " + err)
  }
  let actual = run_source(source)
  if actual != expected.to_int() {
    abort(
      "MIR oracle mismatch: expected " +
      expected.to_string() +
      ", compiled exit code " +
      actual.to_string(),
    )
  }
}

///|
fn run_source_async(source : String) -> Int {
  run_source(source)
}

///|
async fn run_source_against_clang_baseline(
  source : String,
  tag : String,
) -> CommandResult {
  let source_path = temp_file_path(tag + "_source", source, ".c")
  let asm_path = temp_file_path(tag + "_kimicc", source, ".s")
  let kimicc_bin = temp_file_path(tag + "_kimicc", source, "")
  let clang_bin = temp_file_path(tag + "_clang", source, "")
  write_text_file(source_path, source)
  write_text_file(asm_path, compile(source))
  run_command_checked(
    "clang -o " + shell_quote(kimicc_bin) + " " + shell_quote(asm_path),
    "link kimicc differential " + tag,
  )
  run_command_checked(
    "clang -o " + shell_quote(clang_bin) + " " + shell_quote(source_path),
    "build clang differential " + tag,
  )
  let kimicc = run_command_capture(shell_quote(kimicc_bin), tag + "_kimicc_run")
  let clang = run_command_capture(shell_quote(clang_bin), tag + "_clang_run")
  if kimicc.code != clang.code || kimicc.output != clang.output {
    abort(
      "C differential mismatch for " +
      tag +
      ":\nclang code=" +
      clang.code.to_string() +
      "\nclang output:\n" +
      clang.output +
      "\nkimicc code=" +
      kimicc.code.to_string() +
      "\nkimicc output:\n" +
      kimicc.output,
    )
  }
  kimicc
}

///|
async fn run_source_direct_object_against_clang_baseline(
  source : String,
  tag : String,
) -> CommandResult {
  let source_path = temp_file_path(tag + "_source", source, ".c")
  let obj_path = compile_source_to_direct_object_path(source, tag + "_direct")
  let direct_bin = temp_file_path(tag + "_direct", source, "")
  let clang_bin = temp_file_path(tag + "_clang", source, "")
  write_text_file(source_path, source)
  run_command_checked(
    "clang -o " + shell_quote(direct_bin) + " " + shell_quote(obj_path),
    "link direct object differential " + tag,
  )
  run_command_checked(
    "clang -o " + shell_quote(clang_bin) + " " + shell_quote(source_path),
    "build clang direct object differential " + tag,
  )
  let direct = run_command_capture(shell_quote(direct_bin), tag + "_direct_run")
  let clang = run_command_capture(shell_quote(clang_bin), tag + "_clang_run")
  if direct.code != clang.code || direct.output != clang.output {
    abort(
      "Direct object C differential mismatch for " +
      tag +
      ":\nclang code=" +
      clang.code.to_string() +
      "\nclang output:\n" +
      clang.output +
      "\ndirect object code=" +
      direct.code.to_string() +
      "\ndirect object output:\n" +
      direct.output,
    )
  }
  direct
}

///|
priv struct CommandResult {
  code : Int
  output : String
}

///|
priv enum SQLiteObjectCompiler {
  Kimicc
  Clang
  DirectObject
}

///|
fn SQLiteObjectCompiler::tag(self : SQLiteObjectCompiler) -> String {
  match self {
    Kimicc => "kimicc"
    Clang => "clang"
    DirectObject => "direct"
  }
}

///|
fn temp_file_path(prefix : String, seed : String, suffix : String) -> String {
  "/tmp/kimicc_" + prefix + "_" + source_id(seed) + suffix
}

///|
fn write_text_file(path : String, content : String) -> Unit {
  let rc = moonbit_write_file(@utf8.encode(path), @utf8.encode(content))
  if rc != 0 {
    abort("write failed for " + path + " with code: " + rc.to_string())
  }
}

///|
fn write_binary_file(path : String, content : Bytes) -> Unit {
  let rc = moonbit_write_file(@utf8.encode(path), content)
  if rc != 0 {
    abort("write failed for " + path + " with code: " + rc.to_string())
  }
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
fn path_exists(path : String) -> Bool {
  moonbit_system(@utf8.encode("test -e " + shell_quote(path))) == 0
}

///|
fn run_command_checked(cmd : String, context : String) -> Unit {
  let rc = moonbit_system(@utf8.encode(cmd))
  if rc != 0 {
    abort(context + " failed with code: " + rc.to_string())
  }
}

///|
fn run_command_exit_silent(cmd : String, tag : String) -> Int {
  let output_path = temp_file_path(tag, cmd, ".out")
  moonbit_system(@utf8.encode(cmd + " > " + shell_quote(output_path) + " 2>&1"))
}

///|
async fn run_command_capture(cmd : String, tag : String) -> CommandResult {
  let output_path = temp_file_path(tag, cmd, ".out")
  let rc = moonbit_system(@utf8.encode(cmd + " > " + output_path + " 2>&1"))
  let data = @fs.read_file(output_path)
  { code: rc, output: data.text() }
}

///|
async fn run_command_capture_tail(
  cmd : String,
  tag : String,
  tail_lines : Int,
) -> CommandResult {
  let output_path = temp_file_path(tag, cmd, ".out")
  let tail_path = output_path + ".tail"
  let rc = moonbit_system(
    @utf8.encode(
      "( " +
      cmd +
      " ) > " +
      shell_quote(output_path) +
      " 2>&1; rc=$?; tail -n " +
      tail_lines.to_string() +
      " " +
      shell_quote(output_path) +
      " > " +
      shell_quote(tail_path) +
      "; exit $rc",
    ),
  )
  let data = @fs.read_file(tail_path)
  { code: rc, output: "full-output: " + output_path + "\n" + data.text() }
}

///|
fn compile_source_to_object_path(source : String, tag : String) -> String {
  let asm_path = temp_file_path(tag, source, ".s")
  let obj_path = temp_file_path(tag, source, ".o")
  let assembly = compile(source)
  write_text_file(asm_path, assembly)
  run_command_checked(
    "clang -c -o " + obj_path + " " + asm_path,
    "assemble " + tag,
  )
  obj_path
}

///|
fn compile_source_to_strict_mir_assembly(source : String) -> String {
  let target = @target.Target::default()
  let prog = @parser.parse_for_target(source, target)
  match @parser.validate_semantics(prog) {
    Ok(_) => ()
    Err(err) => abort("strict MIR semantic validation failed: " + err)
  }
  match
    @mir_codegen.generate_assembly_from_mir_module_strict(
      @mir.lower_to_module(prog, target),
    ) {
    Ok(assembly) => assembly
    Err(err) => abort("strict MIR codegen failed: " + err)
  }
}

///|
fn compile_source_to_strict_mir_object_path(
  source : String,
  tag : String,
) -> String {
  let asm_path = temp_file_path(tag, source, ".strict-mir.s")
  let obj_path = temp_file_path(tag, source, ".strict-mir.o")
  write_text_file(asm_path, compile_source_to_strict_mir_assembly(source))
  run_command_checked(
    "clang -c -o " + obj_path + " " + asm_path,
    "assemble strict MIR " + tag,
  )
  obj_path
}

///|
fn compile_source_to_direct_object_path(
  source : String,
  tag : String,
) -> String {
  let obj_path = temp_file_path(tag, source, ".direct.o")
  let prog = @parser.parse(source)
  write_binary_file(obj_path, @codegen.generate_macho_object(prog))
  obj_path
}

///|
fn run_source_direct_object_async(source : String, tag : String) -> Int {
  let obj_path = compile_source_to_direct_object_path(source, tag)
  let bin_path = temp_file_path(tag + "_direct_bin", source, "")
  run_command_checked(
    "clang -o " + shell_quote(bin_path) + " " + shell_quote(obj_path),
    "link direct object " + tag,
  )
  run_command_exit_silent(shell_quote(bin_path), tag + "_direct_run")
}

///|
async fn preprocess_c_file(path : String, tag : String) -> String {
  let preprocessed_path = temp_file_path(tag, path, ".i")
  run_command_checked(
    "clang -E " + path + " -o " + preprocessed_path,
    "preprocess " + path,
  )
  let data = @fs.read_file(preprocessed_path)
  data.text()
}

///|
async fn preprocess_c_file_with_flags(
  path : String,
  flags : String,
  tag : String,
) -> String {
  let preprocessed_path = temp_file_path(tag, path + flags, ".i")
  run_command_checked(
    "clang -E " +
    flags +
    " " +
    shell_quote(path) +
    " -o " +
    shell_quote(preprocessed_path),
    "preprocess " + path,
  )
  let data = @fs.read_file(preprocessed_path)
  data.text()
}

///|
async fn compile_c_file_with_kimicc_object_path(
  path : String,
  flags : String,
  tag : String,
) -> String {
  let source = preprocess_c_file_with_flags(path, flags, tag)
  compile_source_to_object_path(source, tag)
}

///|
async fn compile_c_file_with_kimicc_direct_object_path(
  path : String,
  flags : String,
  tag : String,
) -> String {
  let source = preprocess_c_file_with_flags(path, flags, tag)
  compile_source_to_direct_object_path(source, tag)
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
fn external_testbed_enabled(name : String) -> Bool {
  moonbit_system(
    @utf8.encode(
      "test \"${KIMICC_EXTERNAL_TESTBED:-}\" = " +
      shell_quote(name) +
      " || test \"${KIMICC_EXTERNAL_TESTBED:-}\" = all",
    ),
  ) ==
  0
}

///|
async fn compile_sqlite_fixture_object() -> String {
  let source = preprocess_c_file(
    "test/fixtures/sqlite/sqlite3.c", "sqlite3_preprocessed",
  )
  let assembly = compile(source)
  assert_true(assembly.contains("_sqlite3_open:"))
  let asm_path = "/tmp/kimicc_sqlite3.s"
  let obj_path = "/tmp/kimicc_sqlite3.o"
  write_text_file(asm_path, assembly)
  run_command_checked(
    "clang -c -o " + obj_path + " " + asm_path,
    "assemble sqlite3",
  )
  obj_path
}

///|
fn compile_clang_sqlite_fixture_object() -> String {
  let obj_path = "/tmp/clang_sqlite3.o"
  run_command_checked(
    "clang -I test/fixtures/sqlite -c -o " +
    obj_path +
    " test/fixtures/sqlite/sqlite3.c",
    "compile clang sqlite3",
  )
  obj_path
}

///|
async fn compile_sqlite_fixture_object_with(
  compiler : SQLiteObjectCompiler,
) -> String {
  match compiler {
    Kimicc => compile_sqlite_fixture_object()
    Clang => compile_clang_sqlite_fixture_object()
    DirectObject => compile_sqlite_fixture_direct_object()
  }
}

///|
fn sqlite_testfixture_flags() -> String {
  "-DSQLITE_NO_SYNC=1 " +
  "-DSQLITE_TEST=1 " +
  "-DSQLITE_CRASH_TEST=1 " +
  "-DTCLSH_INIT_PROC=sqlite3TestInit " +
  "-DSQLITE_SERVER=1 " +
  "-DSQLITE_PRIVATE= " +
  "-DSQLITE_CORE " +
  "-DBUILD_sqlite " +
  "-DSQLITE_SERIES_CONSTRAINT_VERIFY=1 " +
  "-DSQLITE_DEFAULT_PAGE_SIZE=1024 " +
  "-DSQLITE_ENABLE_STMTVTAB " +
  "-DSQLITE_ENABLE_DBPAGE_VTAB " +
  "-DSQLITE_ENABLE_BYTECODE_VTAB " +
  "-DSQLITE_ENABLE_MATH_FUNCTIONS " +
  "-DSQLITE_CKSUMVFS_STATIC " +
  "-DSQLITE_STATIC_RANDOMJSON " +
  "-DSQLITE_STRICT_SUBTYPE=1 " +
  "-I test/fixtures/sqlite"
}

///|
async fn compile_sqlite_fixture_testfixture_object_with(
  compiler : SQLiteObjectCompiler,
) -> String {
  match compiler {
    Kimicc => {
      let source = preprocess_c_file_with_flags(
        "test/fixtures/sqlite/sqlite3.c",
        sqlite_testfixture_flags(),
        "sqlite3_testfixture_preprocessed",
      )
      let assembly = compile(source)
      assert_true(assembly.contains("_sqlite3_open:"))
      assert_true(assembly.contains("_sqlite3Atoi64:"))
      let asm_path = "/tmp/kimicc_sqlite3_testfixture.s"
      let obj_path = "/tmp/kimicc_sqlite3_testfixture.o"
      write_text_file(asm_path, assembly)
      run_command_checked(
        "clang -c -o " + shell_quote(obj_path) + " " + shell_quote(asm_path),
        "assemble sqlite3 testfixture object",
      )
      obj_path
    }
    Clang => {
      let obj_path = "/tmp/clang_sqlite3_testfixture.o"
      run_command_checked(
        "clang -c " +
        sqlite_testfixture_flags() +
        " -o " +
        shell_quote(obj_path) +
        " " +
        shell_quote("test/fixtures/sqlite/sqlite3.c"),
        "compile clang sqlite3 testfixture object",
      )
      obj_path
    }
    DirectObject => {
      let source = preprocess_c_file_with_flags(
        "test/fixtures/sqlite/sqlite3.c",
        sqlite_testfixture_flags(),
        "sqlite3_direct_testfixture_preprocessed",
      )
      compile_source_to_direct_object_path(
        source, "sqlite3_direct_testfixture_object",
      )
    }
  }
}

///|
fn sqlite_public_default_source_root() -> String {
  "/tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001"
}

///|
fn sqlite_public_source_root_from_env(root : String?) -> String {
  match root {
    Some(value) =>
      if value == "" {
        sqlite_public_default_source_root()
      } else {
        value
      }
    None => sqlite_public_default_source_root()
  }
}

///|
fn sqlite_public_source_root() -> String {
  sqlite_public_source_root_from_env(
    @env.get_env_var("KIMICC_SQLITE_SOURCE_ROOT"),
  )
}

///|
fn sqlite_public_tests_available() -> Bool {
  sqlite_public_tests_available_at(sqlite_public_source_root())
}

///|
fn sqlite_public_tests_available_at(root : String) -> Bool {
  path_exists(root + "/configure") && path_exists(root + "/test/select1.test")
}

///|
fn sqlite_public_platform_adjusted_source_root() -> String {
  let src = sqlite_public_source_root()
  let root = "/tmp/kimicc_sqlite_src_3049001_platform"
  if !sqlite_public_tests_available_at(src) {
    return root
  }
  run_command_checked(
    "rm -rf " +
    shell_quote(root) +
    " && cp -R " +
    shell_quote(src) +
    " " +
    shell_quote(root),
    "prepare platform-adjusted sqlite public source",
  )
  let testdir = root + "/test"
  run_command_checked(
    "perl -0pi -e 's/\\{Inf Inf Inf -Inf -Inf -Inf\\}/\\{inf inf inf -inf -inf -inf\\}/g; s/\\{Inf Inf Inf\\}/\\{inf inf inf\\}/g' " +
    shell_quote(testdir + "/func.test"),
    "patch sqlite func infinity expectations",
  )
  run_command_checked(
    "perl -0pi -e 's/\\n\\} Inf\\n/\\n\\} inf\\n/g; s/\\n\\} \\{-Inf\\}\\n/\\n\\} \\{-inf\\}\\n/g' " +
    shell_quote(testdir + "/json101.test"),
    "patch sqlite json101 infinity expectations",
  )
  run_command_checked(
    "perl -0pi -e 's/\\{Inf \\{\\{\"x\":9e999\\}\\}\\}/\\{inf \\{\\{\"x\":9e999\\}\\}\\}/g; s/\\{-Inf \\{\\{\"x\":-9e999\\}\\}\\}/\\{-inf \\{\\{\"x\":-9e999\\}\\}\\}/g' " +
    shell_quote(testdir + "/json501.test"),
    "patch sqlite json501 infinity expectations",
  )
  run_command_checked(
    "perl -0pi -e 's/(test_literal 2\\.3\\s+1e1000\\s+real\\s+)Inf/$1inf/; s/(test_literal 2\\.4\\s+-1e1000\\s+real\\s+)-Inf/$1-inf/; s/(test_literal 3\\.4\\s+1e1_000\\s+real\\s+)Inf/$1inf/' " +
    shell_quote(testdir + "/literal.test"),
    "patch sqlite literal infinity expectations",
  )
  run_command_checked(
    "perl -0pi -e 's/\\} \\{text\\}\\n\\n# A variable with an integer/\\} \\{string text\\}\\n\\n# A variable with an integer/' " +
    shell_quote(testdir + "/types3.test"),
    "patch sqlite types3 Tcl string representation expectation",
  )
  run_command_checked(
    "perl -0pi -e 's/\\Qset dlerror_nosuchfile {dlopen.%s, 10.: .*image.*found.*}\\E/set dlerror_nosuchfile {dlopen.%s.*(image.*found|no such file).*}/; s/set dlerror_notadll\\s+\\{dlopen\\.[^\\n]*image\\.\\*found\\.\\*\\}/set dlerror_notadll    {dlopen.%1\\$s.*(image.*found|no such file).*}/' " +
    shell_quote(testdir + "/loadext.test"),
    "patch sqlite loadext Darwin loader expectations",
  )
  root
}

///|
fn sqlite_tcl_config_path() -> String {
  let macos_155 = "/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk/System/Library/Frameworks/Tcl.framework/tclConfig.sh"
  if path_exists(macos_155) {
    return macos_155
  }
  let macos_260 = "/Library/Developer/CommandLineTools/SDKs/MacOSX26.0.sdk/System/Library/Frameworks/Tcl.framework/tclConfig.sh"
  if path_exists(macos_260) {
    return macos_260
  }
  ""
}

///|
fn sqlite_public_conformance_enabled(suite : String) -> Bool {
  moonbit_system(
    @utf8.encode(
      "test \"${KIMICC_SQLITE_CONFORMANCE:-}\" = " +
      shell_quote(suite) +
      " || test \"${KIMICC_SQLITE_CONFORMANCE:-}\" = all",
    ),
  ) ==
  0
}

///|
async fn build_sqlite_public_testfixture_with(
  compiler : SQLiteObjectCompiler,
) -> String {
  let root = sqlite_public_source_root()
  let tcl_config = sqlite_tcl_config_path()
  if tcl_config == "" {
    abort("SQLite public Tcl testfixture requires tclConfig.sh")
  }
  let object_path = compile_sqlite_fixture_testfixture_object_with(compiler)
  let build_dir = "/tmp/kimicc_sqlite_testfixture_build_" + compiler.tag()
  let configure_log = "/tmp/kimicc_sqlite_configure.out"
  let make_log = "/tmp/kimicc_sqlite_make_testfixture.out"
  run_command_checked(
    "rm -rf " +
    shell_quote(build_dir) +
    " && mkdir -p " +
    shell_quote(build_dir),
    "prepare sqlite testfixture build dir",
  )
  run_command_checked(
    "cd " +
    shell_quote(build_dir) +
    " && " +
    shell_quote(root + "/configure") +
    " TCL_CONFIG_SH=" +
    shell_quote(tcl_config) +
    " --disable-shared --enable-static > " +
    shell_quote(configure_log) +
    " 2>&1",
    "configure sqlite testfixture",
  )
  run_command_checked(
    "cd " +
    shell_quote(build_dir) +
    " && make parse.h sqlite3.h opcodes.h >> " +
    shell_quote(make_log) +
    " 2>&1",
    "prepare sqlite generated test headers",
  )
  run_command_checked(
    "cd " +
    shell_quote(build_dir) +
    " && make testfixture TCL_CONFIG_SH=" +
    shell_quote(tcl_config) +
    " USE_AMALGAMATION=1 TESTFIXTURE_SRC1=" +
    shell_quote(object_path) +
    " >> " +
    shell_quote(make_log) +
    " 2>&1",
    "build sqlite public testfixture",
  )
  build_dir + "/testfixture"
}

///|
async fn run_sqlite_public_tcl_batch_with(
  test_paths : Array[String],
  tag : String,
  compiler : SQLiteObjectCompiler,
) -> CommandResult {
  if !sqlite_public_tests_available() {
    return { code: 0, output: "sqlite-public-tests-skipped\n" }
  }
  let root = sqlite_public_source_root()
  let testfixture = build_sqlite_public_testfixture_with(compiler)
  let output = StringBuilder::new()
  for test_path in test_paths {
    let run_tag = tag + "_" + compiler.tag() + "_" + source_id(test_path)
    let run_dir = temp_file_path(run_tag + "_work", test_path, "")
    run_command_checked(
      "rm -rf " + shell_quote(run_dir) + " && mkdir -p " + shell_quote(run_dir),
      "prepare sqlite public tcl test work dir",
    )
    let result = run_command_capture(
      "cd " +
      shell_quote(run_dir) +
      " && " +
      shell_quote(testfixture) +
      " " +
      shell_quote(root + "/" + test_path),
      run_tag,
    )
    output.write_string("### ")
    output.write_string(test_path)
    output.write_string("\n")
    output.write_string(result.output)
    if result.code != 0 {
      return { code: result.code, output: output.to_string() }
    }
  }
  { code: 0, output: output.to_string() }
}

///|
async fn run_sqlite_public_tcl_batch_collect_with(
  test_paths : Array[String],
  tag : String,
  compiler : SQLiteObjectCompiler,
) -> CommandResult {
  run_sqlite_public_tcl_batch_collect_with_root(
    test_paths,
    tag,
    compiler,
    sqlite_public_source_root(),
  )
}

///|
async fn run_sqlite_public_tcl_batch_collect_with_root(
  test_paths : Array[String],
  tag : String,
  compiler : SQLiteObjectCompiler,
  root : String,
) -> CommandResult {
  if !sqlite_public_tests_available_at(root) {
    return { code: 0, output: "sqlite-public-tests-skipped\n" }
  }
  let testfixture = build_sqlite_public_testfixture_with(compiler)
  let output = StringBuilder::new()
  let mut code = 0
  for test_path in test_paths {
    let run_tag = tag + "_" + compiler.tag() + "_" + source_id(test_path)
    let run_dir = temp_file_path(run_tag + "_work", test_path, "")
    run_command_checked(
      "rm -rf " + shell_quote(run_dir) + " && mkdir -p " + shell_quote(run_dir),
      "prepare sqlite public tcl test work dir",
    )
    let result = run_command_capture(
      "cd " +
      shell_quote(run_dir) +
      " && " +
      shell_quote(testfixture) +
      " " +
      shell_quote(root + "/" + test_path),
      run_tag,
    )
    output.write_string("### ")
    output.write_string(test_path)
    output.write_string("\nexit-code: ")
    output.write_string(result.code.to_string())
    output.write_string("\n")
    output.write_string(result.output)
    if code == 0 && result.code != 0 {
      code = result.code
    }
  }
  { code, output: output.to_string() }
}

///|
async fn run_sqlite_public_tcl_batch(
  test_paths : Array[String],
  tag : String,
) -> CommandResult {
  run_sqlite_public_tcl_batch_with(test_paths, tag, Kimicc)
}

///|
async fn run_sqlite_public_tcl_script_tail_with(
  test_path : String,
  tag : String,
  compiler : SQLiteObjectCompiler,
  tail_lines : Int,
) -> CommandResult {
  if !sqlite_public_tests_available() {
    return { code: 0, output: "sqlite-public-tests-skipped\n" }
  }
  let root = sqlite_public_source_root()
  let testfixture = build_sqlite_public_testfixture_with(compiler)
  let run_tag = tag + "_" + compiler.tag() + "_" + source_id(test_path)
  let run_dir = temp_file_path(run_tag + "_work", test_path, "")
  run_command_checked(
    "rm -rf " + shell_quote(run_dir) + " && mkdir -p " + shell_quote(run_dir),
    "prepare sqlite public tcl test work dir",
  )
  run_command_capture_tail(
    "cd " +
    shell_quote(run_dir) +
    " && " +
    shell_quote(testfixture) +
    " " +
    shell_quote(root + "/" + test_path),
    run_tag,
    tail_lines,
  )
}

///|
async fn run_sqlite_public_tcl_runner_tail_with(
  runner_args : String,
  tag : String,
  compiler : SQLiteObjectCompiler,
  tail_lines : Int,
) -> CommandResult {
  run_sqlite_public_tcl_runner_tail_with_root(
    runner_args,
    tag,
    compiler,
    tail_lines,
    sqlite_public_source_root(),
  )
}

///|
async fn run_sqlite_public_tcl_runner_tail_with_root(
  runner_args : String,
  tag : String,
  compiler : SQLiteObjectCompiler,
  tail_lines : Int,
  root : String,
) -> CommandResult {
  if !sqlite_public_tests_available_at(root) {
    return { code: 0, output: "sqlite-public-tests-skipped\n" }
  }
  let testfixture = build_sqlite_public_testfixture_with(compiler)
  let run_seed = root + "/test/testrunner.tcl " + runner_args
  let run_tag = tag + "_" + compiler.tag() + "_" + source_id(run_seed)
  let run_dir = temp_file_path(run_tag + "_work", run_seed, "")
  run_command_checked(
    "rm -rf " + shell_quote(run_dir) + " && mkdir -p " + shell_quote(run_dir),
    "prepare sqlite public tcl runner work dir",
  )
  let result = run_command_capture_tail(
    "cd " +
    shell_quote(run_dir) +
    " && " +
    shell_quote(testfixture) +
    " " +
    shell_quote(root + "/test/testrunner.tcl") +
    " " +
    runner_args,
    run_tag,
    tail_lines,
  )
  if result.code == 0 && !result.output.contains("FAILED:") {
    result
  } else {
    let errors = run_command_capture(
      "cd " +
      shell_quote(run_dir) +
      " && " +
      shell_quote(testfixture) +
      " " +
      shell_quote(root + "/test/testrunner.tcl") +
      " errors",
      run_tag + "_errors",
    )
    {
      code: result.code,
      output: result.output + "### testrunner-errors\n" + errors.output,
    }
  }
}

///|
fn compile_driver_with_object(
  driver_source : String,
  object_path : String,
  tag : String,
) -> String {
  let driver_path = temp_file_path(tag, driver_source, ".c")
  let bin_path = temp_file_path(tag, driver_source + object_path, "")
  write_text_file(driver_path, driver_source)
  run_command_checked(
    "clang -I test/fixtures/sqlite -o " +
    bin_path +
    " " +
    driver_path +
    " " +
    object_path,
    "link driver " + tag,
  )
  bin_path
}

///|
async fn run_driver_with_sqlite_object(
  driver_source : String,
  tag : String,
) -> CommandResult {
  let object_path = compile_sqlite_fixture_object_with(Kimicc)
  let bin_path = compile_driver_with_object(driver_source, object_path, tag)
  run_command_capture(bin_path, tag)
}

///|
async fn compile_sqlite_fixture_direct_object() -> String {
  let source = preprocess_c_file(
    "test/fixtures/sqlite/sqlite3.c", "sqlite3_direct_preprocessed",
  )
  compile_source_to_direct_object_path(source, "sqlite3_direct_object")
}

///|
async fn compile_sqlite_fixture_strict_mir_object() -> String {
  let source = preprocess_c_file(
    "test/fixtures/sqlite/sqlite3.c", "sqlite3_strict_mir_preprocessed",
  )
  compile_source_to_strict_mir_object_path(source, "sqlite3_strict_mir_object")
}

///|
async fn run_driver_with_direct_sqlite_object(
  driver_source : String,
  tag : String,
) -> CommandResult {
  let object_path = compile_sqlite_fixture_direct_object()
  let bin_path = compile_driver_with_object(driver_source, object_path, tag)
  run_command_capture(bin_path, tag)
}

///|
async fn run_driver_with_strict_mir_sqlite_object(
  driver_source : String,
  tag : String,
) -> CommandResult {
  let object_path = compile_sqlite_fixture_strict_mir_object()
  let bin_path = compile_driver_with_object(driver_source, object_path, tag)
  run_command_capture(bin_path, tag)
}

///|
fn c_string_literal(value : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('"')
  for ch in value {
    match ch {
      '\n' => buf.write_string("\\n")
      '\t' => buf.write_string("\\t")
      '\r' => buf.write_string("\\r")
      '\\' => buf.write_string("\\\\")
      '"' => buf.write_string("\\\"")
      '\u0000' => buf.write_string("\\0")
      _ => buf.write_char(ch)
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
fn sqlite_script_driver_source(sql_path : String) -> String {
  let buf = StringBuilder::new()
  let prefix =
    #|#include "sqlite3.h"
    #|#include <stdio.h>
    #|#include <stdlib.h>
    #|#include <string.h>
    #|
    #|static char *read_file(const char *path) {
    #|  FILE *f = fopen(path, "rb");
    #|  char *buf;
    #|  long n;
    #|  if (!f) {
    #|    printf("open-script-failed:%s\n", path);
    #|    return 0;
    #|  }
    #|  if (fseek(f, 0, SEEK_END) != 0) {
    #|    fclose(f);
    #|    return 0;
    #|  }
    #|  n = ftell(f);
    #|  if (n < 0) {
    #|    fclose(f);
    #|    return 0;
    #|  }
    #|  rewind(f);
    #|  buf = (char *)malloc((size_t)n + 1);
    #|  if (!buf) {
    #|    fclose(f);
    #|    return 0;
    #|  }
    #|  if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
    #|    free(buf);
    #|    fclose(f);
    #|    return 0;
    #|  }
    #|  buf[n] = 0;
    #|  fclose(f);
    #|  return buf;
    #|}
    #|
    #|static int print_row(void *unused, int argc, char **argv, char **cols) {
    #|  int i;
    #|  (void)unused;
    #|  printf("row");
    #|  for (i = 0; i < argc; i++) {
    #|    printf("|%s=%s", cols[i], argv[i] ? argv[i] : "NULL");
    #|  }
    #|  printf("\n");
    #|  return 0;
    #|}
    #|
    #|int main(void) {
    #|  sqlite3 *db = 0;
    #|  char *sql = 0;
    #|  char *err = 0;
    #|  int rc = sqlite3_open(":memory:", &db);
    #|  if (rc != SQLITE_OK) {
    #|    printf("open rc=%d err=%s\n", rc, db ? sqlite3_errmsg(db) : "null");
    #|    return 1;
    #|  }
    #|  sql = read_file(
  buf.write_string(prefix)
  buf.write_string(c_string_literal(sql_path))
  let suffix =
    #|);
    #|  if (!sql) {
    #|    sqlite3_close(db);
    #|    return 2;
    #|  }
    #|  rc = sqlite3_exec(db, sql, print_row, 0, &err);
    #|  if (rc != SQLITE_OK) {
    #|    printf("exec rc=%d err=%s\n", rc, err ? err : sqlite3_errmsg(db));
    #|    sqlite3_free(err);
    #|    free(sql);
    #|    sqlite3_close(db);
    #|    return 3;
    #|  }
    #|  free(sql);
    #|  sqlite3_close(db);
    #|  printf("script-ok\n");
    #|  return 0;
    #|}
  buf.write_string(suffix)
  buf.to_string()
}

///|
async fn run_sql_script_with_sqlite_object(
  sql : String,
  tag : String,
  compiler : SQLiteObjectCompiler,
) -> CommandResult {
  let sql_path = temp_file_path(tag + "_sql", sql, ".sql")
  write_text_file(sql_path, sql)
  let object_path = compile_sqlite_fixture_object_with(compiler)
  let driver_source = sqlite_script_driver_source(sql_path)
  let run_tag = tag + "_" + compiler.tag()
  let bin_path = compile_driver_with_object(driver_source, object_path, run_tag)
  run_command_capture(bin_path, run_tag)
}

///|
async fn run_sql_script_against_clang_baseline(
  sql : String,
  tag : String,
) -> CommandResult {
  run_sql_script_compiler_against_clang_baseline(sql, tag, Kimicc)
}

///|
async fn run_sql_script_compiler_against_clang_baseline(
  sql : String,
  tag : String,
  compiler : SQLiteObjectCompiler,
) -> CommandResult {
  let clang_result = run_sql_script_with_sqlite_object(sql, tag, Clang)
  if clang_result.code != 0 {
    abort("SQLite clang baseline failed:\n" + clang_result.output)
  }
  let compiled_result = run_sql_script_with_sqlite_object(sql, tag, compiler)
  let compiler_tag = compiler.tag()
  if compiled_result.code != 0 {
    abort(
      "SQLite " + compiler_tag + " object failed:\n" + compiled_result.output,
    )
  }
  if compiled_result.output != clang_result.output {
    abort(
      "SQLite " +
      compiler_tag +
      " output differs from clang baseline:\nclang:\n" +
      clang_result.output +
      "\n" +
      compiler_tag +
      ":\n" +
      compiled_result.output,
    )
  }
  compiled_result
}
