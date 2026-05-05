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
  moonbit_system(@utf8.encode(bin_path))
}

///|
fn run_source_async(source : String) -> Int {
  run_source(source)
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
}

///|
fn SQLiteObjectCompiler::tag(self : SQLiteObjectCompiler) -> String {
  match self {
    Kimicc => "kimicc"
    Clang => "clang"
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
async fn run_command_capture(cmd : String, tag : String) -> CommandResult {
  let output_path = temp_file_path(tag, cmd, ".out")
  let rc = moonbit_system(@utf8.encode(cmd + " > " + output_path + " 2>&1"))
  let data = @fs.read_file(output_path)
  { code: rc, output: data.text() }
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
  }
}

///|
fn sqlite_public_source_root() -> String {
  "/tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001"
}

///|
fn sqlite_public_tests_available() -> Bool {
  let root = sqlite_public_source_root()
  path_exists(root + "/configure") && path_exists(root + "/test/select1.test")
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
async fn run_sqlite_public_tcl_batch(
  test_paths : Array[String],
  tag : String,
) -> CommandResult {
  run_sqlite_public_tcl_batch_with(test_paths, tag, Kimicc)
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
  let clang_result = run_sql_script_with_sqlite_object(sql, tag, Clang)
  if clang_result.code != 0 {
    abort("SQLite clang baseline failed:\n" + clang_result.output)
  }
  let kimicc_result = run_sql_script_with_sqlite_object(sql, tag, Kimicc)
  if kimicc_result.code != 0 {
    abort("SQLite kimicc object failed:\n" + kimicc_result.output)
  }
  if kimicc_result.output != clang_result.output {
    abort(
      "SQLite kimicc output differs from clang baseline:\nclang:\n" +
      clang_result.output +
      "\nkimicc:\n" +
      kimicc_result.output,
    )
  }
  kimicc_result
}
