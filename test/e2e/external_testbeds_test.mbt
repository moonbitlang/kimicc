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
