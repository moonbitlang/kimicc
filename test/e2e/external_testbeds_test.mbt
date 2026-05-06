///|
fn require_external_path(path : String, label : String) -> Unit {
  if !path_exists(path) {
    abort(label + " missing at " + path)
  }
}

///|
async fn compile_tree_sitter_object(
  root : String,
  name : String,
  objects : Array[String],
) -> Unit {
  let flags = "-I " +
    shell_quote(root + "/lib/include") +
    " -I " +
    shell_quote(root + "/lib/src")
  let path = root + "/lib/src/" + name + ".c"
  require_external_path(path, "tree-sitter source")
  objects.push(
    compile_c_file_with_kimicc_object_path(
      path,
      flags,
      "tree_sitter_external_" + name,
    ),
  )
}

///|
fn tree_sitter_smoke_source() -> String {
  let source =
    #|#include <stdint.h>
    #|#include <stdlib.h>
    #|#include <string.h>
    #|#include <tree_sitter/api.h>
    #|
    #|extern const TSLanguage *tree_sitter_mini(void);
    #|
    #|int main(void) {
    #|  const char *source = "alpha beta gamma";
    #|  TSParser *parser = ts_parser_new();
    #|  if (!parser) return 1;
    #|  if (!ts_parser_set_language(parser, tree_sitter_mini())) return 2;
    #|  TSTree *tree = ts_parser_parse_string(parser, 0, source, (uint32_t)strlen(source));
    #|  if (!tree) return 3;
    #|  TSNode root = ts_tree_root_node(tree);
    #|  char *printed = ts_node_string(root);
    #|  int ok = printed && strstr(printed, "source_file") && strstr(printed, "word");
    #|  free(printed);
    #|  ts_tree_delete(tree);
    #|  ts_parser_delete(parser);
    #|  return ok ? 42 : 4;
    #|}
  source
}

///|
async test "external tree-sitter C library smoke compiles and runs when enabled" {
  if !external_testbed_enabled("tree-sitter") {
    return
  }
  let root = "/tmp/kimicc_tree_sitter"
  require_external_path(
    root + "/lib/include/tree_sitter/api.h",
    "tree-sitter public header",
  )
  require_external_path(root + "/src/parser.c", "tree-sitter mini parser")
  let objects : Array[String] = []
  for
    name in [
      "alloc", "get_changed_ranges", "language", "lexer", "node", "parser", "point",
      "query", "stack", "subtree", "tree", "tree_cursor", "wasm_store",
    ] {
    compile_tree_sitter_object(root, name, objects)
  }
  let flags = "-I " +
    shell_quote(root + "/lib/include") +
    " -I " +
    shell_quote(root + "/lib/src")
  objects.push(
    compile_c_file_with_kimicc_object_path(
      root + "/src/parser.c",
      flags,
      "tree_sitter_external_mini_parser",
    ),
  )
  let smoke_path = "/tmp/kimicc_tree_sitter_external_smoke.c"
  write_text_file(smoke_path, tree_sitter_smoke_source())
  objects.push(
    compile_c_file_with_kimicc_object_path(
      smoke_path, flags, "tree_sitter_external_smoke",
    ),
  )
  let binary_path = "/tmp/kimicc_tree_sitter_external_smoke"
  run_command_checked(
    "clang -o " + shell_quote(binary_path) + " " + shell_join_quoted(objects),
    "link tree-sitter external smoke",
  )
  let result = run_command_capture(
    shell_quote(binary_path),
    "tree_sitter_external_smoke",
  )
  if result.code != 42 {
    abort(
      "tree-sitter external smoke failed with code " +
      result.code.to_string() +
      ":\n" +
      result.output,
    )
  }
}

///|
fn ocamlyacc_flags(root : String) -> String {
  "-DHAS_MKSTEMP -I " +
  shell_quote(root + "/yacc") +
  " -I " +
  shell_quote(root + "/runtime")
}

///|
fn ocamlyacc_source_paths(root : String) -> Array[String] {
  let paths : Array[String] = []
  for
    name in [
      "mkpar", "skeleton", "lr0", "warshall", "closure", "reader", "main", "error",
      "lalr", "verbose", "output", "symtab",
    ] {
    paths.push(root + "/yacc/" + name + ".c")
  }
  paths
}

///|
async fn build_ocamlyacc_with_kimicc(root : String) -> String {
  let flags = ocamlyacc_flags(root)
  let objects : Array[String] = []
  for path in ocamlyacc_source_paths(root) {
    require_external_path(path, "ocamlyacc source")
    objects.push(
      compile_c_file_with_kimicc_object_path(
        path,
        flags,
        "ocamlyacc_external_" + source_id(path),
      ),
    )
  }
  let binary_path = "/tmp/kimicc_ocamlyacc_external"
  run_command_checked(
    "clang -o " + shell_quote(binary_path) + " " + shell_join_quoted(objects),
    "link kimicc ocamlyacc",
  )
  binary_path
}

///|
fn build_ocamlyacc_with_clang(root : String) -> String {
  let binary_path = "/tmp/clang_ocamlyacc_external"
  run_command_checked(
    "clang " +
    ocamlyacc_flags(root) +
    " -o " +
    shell_quote(binary_path) +
    " " +
    shell_join_quoted(ocamlyacc_source_paths(root)),
    "build clang ocamlyacc",
  )
  binary_path
}

///|
async fn run_ocamlyacc_calc_parser(
  binary_path : String,
  root : String,
  work_dir : String,
  tag : String,
) -> CommandResult {
  run_command_checked(
    "rm -rf " + shell_quote(work_dir) + " && mkdir -p " + shell_quote(work_dir),
    "prepare ocamlyacc work dir",
  )
  run_command_checked(
    "cp " +
    shell_quote(root + "/testsuite/tests/tool-lexyacc/calc_parser.mly") +
    " " +
    shell_quote(work_dir + "/calc_parser.mly"),
    "copy ocamlyacc calc grammar",
  )
  run_command_capture(
    "cd " +
    shell_quote(work_dir) +
    " && " +
    shell_quote(binary_path) +
    " " +
    shell_quote("calc_parser.mly"),
    tag,
  )
}

///|
async test "external ocamlyacc calc grammar matches clang when enabled" {
  if !external_testbed_enabled("ocamlyacc") {
    return
  }
  let root = "/tmp/kimicc_ocaml"
  require_external_path(root + "/yacc/main.c", "ocamlyacc source root")
  require_external_path(
    root + "/testsuite/tests/tool-lexyacc/calc_parser.mly",
    "ocamlyacc calc grammar",
  )
  let kimicc_binary = build_ocamlyacc_with_kimicc(root)
  let clang_binary = build_ocamlyacc_with_clang(root)
  let kimicc_version = run_command_capture(
    shell_quote(kimicc_binary) + " -version",
    "ocamlyacc_kimicc_version",
  )
  if kimicc_version.code != 0 {
    abort("kimicc ocamlyacc -version failed:\n" + kimicc_version.output)
  }
  let clang_version = run_command_capture(
    shell_quote(clang_binary) + " -version",
    "ocamlyacc_clang_version",
  )
  if clang_version.code != 0 {
    abort("clang ocamlyacc -version failed:\n" + clang_version.output)
  }
  let kimicc_dir = "/tmp/kimicc_ocamlyacc_external_cmp/kimicc"
  let clang_dir = "/tmp/kimicc_ocamlyacc_external_cmp/clang"
  let kimicc = run_ocamlyacc_calc_parser(
    kimicc_binary, root, kimicc_dir, "ocamlyacc_kimicc_calc",
  )
  if kimicc.code != 0 {
    abort("kimicc ocamlyacc calc parser failed:\n" + kimicc.output)
  }
  let clang = run_ocamlyacc_calc_parser(
    clang_binary, root, clang_dir, "ocamlyacc_clang_calc",
  )
  if clang.code != 0 {
    abort("clang ocamlyacc calc parser failed:\n" + clang.output)
  }
  run_command_checked(
    "cmp -s " +
    shell_quote(kimicc_dir + "/calc_parser.ml") +
    " " +
    shell_quote(clang_dir + "/calc_parser.ml"),
    "compare ocamlyacc generated ml",
  )
  run_command_checked(
    "cmp -s " +
    shell_quote(kimicc_dir + "/calc_parser.mli") +
    " " +
    shell_quote(clang_dir + "/calc_parser.mli"),
    "compare ocamlyacc generated mli",
  )
}
