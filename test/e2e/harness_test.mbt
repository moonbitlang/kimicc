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
fn run_command_checked(cmd : String, context : String) -> Unit {
  let rc = moonbit_system(@utf8.encode(cmd))
  if rc != 0 {
    abort(context + " failed with code: " + rc.to_string())
  }
}

///|
async fn run_command_capture(
  cmd : String,
  tag : String,
) -> CommandResult {
  let output_path = temp_file_path(tag, cmd, ".out")
  let rc = moonbit_system(
    @utf8.encode(cmd + " > " + output_path + " 2>&1"),
  )
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
async fn compile_sqlite_fixture_object() -> String {
  let source = preprocess_c_file(
    "test/fixtures/sqlite/sqlite3.c",
    "sqlite3_preprocessed",
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
  let object_path = compile_sqlite_fixture_object()
  let bin_path = compile_driver_with_object(driver_source, object_path, tag)
  run_command_capture(bin_path, tag)
}
