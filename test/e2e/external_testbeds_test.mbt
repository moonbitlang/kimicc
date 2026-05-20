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
  tag : String,
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
      "tree_sitter_external_" + tag + "_" + name,
    ),
  )
}

///|
async fn compile_tree_sitter_direct_object(
  root : String,
  name : String,
  tag : String,
  objects : Array[String],
) -> Unit {
  let flags = "-I " +
    shell_quote(root + "/lib/include") +
    " -I " +
    shell_quote(root + "/lib/src")
  let path = root + "/lib/src/" + name + ".c"
  require_external_path(path, "tree-sitter source")
  objects.push(
    compile_c_file_with_kimicc_direct_object_path(
      path,
      flags,
      "tree_sitter_direct_external_" + tag + "_" + name,
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
fn tree_sitter_query_edit_source() -> String {
  let source =
    #|#include <stdint.h>
    #|#include <stdio.h>
    #|#include <stdlib.h>
    #|#include <string.h>
    #|#include <tree_sitter/api.h>
    #|
    #|extern const TSLanguage *tree_sitter_mini(void);
    #|
    #|static void fail(int code, const char *message) {
    #|  printf("tree-sitter-query-edit-failed:%d:%s\n", code, message);
    #|  exit(code);
    #|}
    #|
    #|int main(void) {
    #|  const TSLanguage *language = tree_sitter_mini();
    #|  const char *source = "alpha beta gamma";
    #|  const char *edited = "alpha delta beta gamma";
    #|  const char *pattern = "(word) @item";
    #|  uint32_t error_offset = 0;
    #|  TSQueryError error_type = TSQueryErrorNone;
    #|  uint32_t changed_count = 0;
    #|  TSParser *parser = ts_parser_new();
    #|  TSQuery *query = 0;
    #|  TSQueryCursor *query_cursor = 0;
    #|  TSQueryMatch match;
    #|  TSTree *tree = 0;
    #|  TSTree *edited_tree = 0;
    #|  TSRange *changed = 0;
    #|  TSNode root, first, second, found, edited_root;
    #|  TSTreeCursor cursor;
    #|  TSInputEdit edit;
    #|  uint32_t capture_name_len = 0;
    #|  uint32_t match_count = 0;
    #|  uint32_t query_capture_count = 0;
    #|  const char *capture_name = 0;
    #|
    #|  if (!parser) fail(1, "parser");
    #|  if (!ts_parser_set_language(parser, language)) fail(2, "language");
    #|  if (ts_language_symbol_count(language) < 2) fail(3, "symbol count");
    #|  tree = ts_parser_parse_string(parser, 0, source, (uint32_t)strlen(source));
    #|  if (!tree) fail(4, "parse");
    #|  root = ts_tree_root_node(tree);
    #|  if (ts_node_named_child_count(root) != 3) fail(5, "initial child count");
    #|  first = ts_node_named_child(root, 0);
    #|  second = ts_node_named_child(root, 1);
    #|  if (strcmp(ts_node_type(first), "word") != 0) fail(6, "first type");
    #|  if (ts_node_start_byte(first) != 0 || ts_node_end_byte(first) != 5) fail(7, "first range");
    #|  if (ts_node_start_byte(second) != 6 || ts_node_end_byte(second) != 10) fail(8, "second range");
    #|  found = ts_node_named_descendant_for_byte_range(root, 6, 10);
    #|  if (!ts_node_eq(found, second)) fail(9, "descendant lookup");
    #|  cursor = ts_tree_cursor_new(root);
    #|  if (!ts_tree_cursor_goto_first_child(&cursor)) fail(10, "cursor first");
    #|  if (!ts_node_eq(ts_tree_cursor_current_node(&cursor), first)) fail(11, "cursor current");
    #|  if (!ts_tree_cursor_goto_next_sibling(&cursor)) fail(12, "cursor sibling");
    #|  if (!ts_node_eq(ts_tree_cursor_current_node(&cursor), second)) fail(13, "cursor second");
    #|  ts_tree_cursor_delete(&cursor);
    #|
    #|  query = ts_query_new(language, pattern, (uint32_t)strlen(pattern), &error_offset, &error_type);
    #|  if (!query) fail(14, "query compile");
    #|  if (ts_query_capture_count(query) != 1) fail(15, "capture count");
    #|  if (ts_query_pattern_count(query) != 1) fail(16, "pattern count");
    #|  capture_name = ts_query_capture_name_for_id(query, 0, &capture_name_len);
    #|  if (!capture_name || capture_name_len != 4 || strncmp(capture_name, "item", 4) != 0) fail(20, "capture name");
    #|  query_cursor = ts_query_cursor_new();
    #|  if (!query_cursor) fail(21, "query cursor");
    #|  ts_query_cursor_exec(query_cursor, query, root);
    #|  while (ts_query_cursor_next_match(query_cursor, &match)) {
    #|    match_count++;
    #|    query_capture_count += match.capture_count;
    #|  }
    #|  if (match_count != 3 || query_capture_count != 3) fail(23, "query cursor captures");
    #|  ts_query_cursor_delete(query_cursor);
    #|  query_cursor = 0;
    #|
    #|  edit.start_byte = 6;
    #|  edit.old_end_byte = 6;
    #|  edit.new_end_byte = 12;
    #|  edit.start_point = (TSPoint){0, 6};
    #|  edit.old_end_point = (TSPoint){0, 6};
    #|  edit.new_end_point = (TSPoint){0, 12};
    #|  ts_tree_edit(tree, &edit);
    #|  edited_tree = ts_parser_parse_string(parser, tree, edited, (uint32_t)strlen(edited));
    #|  if (!edited_tree) fail(17, "incremental parse");
    #|  changed = ts_tree_get_changed_ranges(tree, edited_tree, &changed_count);
    #|  if (!changed || changed_count == 0) fail(18, "changed ranges");
    #|  free(changed);
    #|  edited_root = ts_tree_root_node(edited_tree);
    #|  if (ts_node_named_child_count(edited_root) != 4) fail(19, "edited child count");
    #|  second = ts_node_named_child(edited_root, 1);
    #|  if (ts_node_start_byte(second) != 6 || ts_node_end_byte(second) != 11) fail(22, "edited second range");
    #|
    #|  if (query_cursor) ts_query_cursor_delete(query_cursor);
    #|  ts_query_delete(query);
    #|  ts_tree_delete(edited_tree);
    #|  ts_tree_delete(tree);
    #|  ts_parser_delete(parser);
    #|  printf("tree-sitter-query-edit-ok %u\n", changed_count);
    #|  return 43;
    #|}
  source
}

///|
async fn build_tree_sitter_external_binary(
  root : String,
  driver_source : String,
  tag : String,
) -> String {
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
    compile_tree_sitter_object(root, name, tag, objects)
  }
  let flags = "-I " +
    shell_quote(root + "/lib/include") +
    " -I " +
    shell_quote(root + "/lib/src")
  objects.push(
    compile_c_file_with_kimicc_object_path(
      root + "/src/parser.c",
      flags,
      "tree_sitter_external_" + tag + "_mini_parser",
    ),
  )
  let smoke_path = "/tmp/kimicc_tree_sitter_external_" + tag + ".c"
  write_text_file(smoke_path, driver_source)
  objects.push(
    compile_c_file_with_kimicc_object_path(
      smoke_path,
      flags,
      "tree_sitter_external_" + tag + "_driver",
    ),
  )
  let binary_path = "/tmp/kimicc_tree_sitter_external_" + tag
  run_command_checked(
    "clang -o " + shell_quote(binary_path) + " " + shell_join_quoted(objects),
    "link tree-sitter external " + tag,
  )
  binary_path
}

///|
async fn build_tree_sitter_external_direct_binary(
  root : String,
  driver_source : String,
  tag : String,
) -> String {
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
    compile_tree_sitter_direct_object(root, name, tag, objects)
  }
  let flags = "-I " +
    shell_quote(root + "/lib/include") +
    " -I " +
    shell_quote(root + "/lib/src")
  objects.push(
    compile_c_file_with_kimicc_direct_object_path(
      root + "/src/parser.c",
      flags,
      "tree_sitter_direct_external_" + tag + "_mini_parser",
    ),
  )
  let smoke_path = "/tmp/kimicc_tree_sitter_direct_external_" + tag + ".c"
  write_text_file(smoke_path, driver_source)
  objects.push(
    compile_c_file_with_kimicc_direct_object_path(
      smoke_path,
      flags,
      "tree_sitter_direct_external_" + tag + "_driver",
    ),
  )
  let binary_path = "/tmp/kimicc_tree_sitter_direct_external_" + tag
  run_command_checked(
    "clang -o " + shell_quote(binary_path) + " " + shell_join_quoted(objects),
    "link direct tree-sitter external " + tag,
  )
  binary_path
}

///|
async test "external tree-sitter C library smoke compiles and runs when enabled" {
  if !external_testbed_enabled("tree-sitter") {
    return
  }
  let root = "/tmp/kimicc_tree_sitter"
  let binary_path = build_tree_sitter_external_binary(
    root,
    tree_sitter_smoke_source(),
    "smoke",
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
async test "external tree-sitter query edit APIs run when enabled" {
  if !external_testbed_enabled("tree-sitter") {
    return
  }
  let root = "/tmp/kimicc_tree_sitter"
  let binary_path = build_tree_sitter_external_binary(
    root,
    tree_sitter_query_edit_source(),
    "query_edit",
  )
  let result = run_command_capture(
    shell_quote(binary_path),
    "tree_sitter_external_query_edit",
  )
  if result.code != 43 || !result.output.contains("tree-sitter-query-edit-ok") {
    abort(
      "tree-sitter query/edit smoke failed with code " +
      result.code.to_string() +
      ":\n" +
      result.output,
    )
  }
}

///|
async test "external tree-sitter direct object query edit APIs run when enabled" {
  if !external_testbed_enabled("tree-sitter") {
    return
  }
  let root = "/tmp/kimicc_tree_sitter"
  let binary_path = build_tree_sitter_external_direct_binary(
    root,
    tree_sitter_query_edit_source(),
    "query_edit",
  )
  let result = run_command_capture(
    shell_quote(binary_path),
    "tree_sitter_direct_external_query_edit",
  )
  if result.code != 43 || !result.output.contains("tree-sitter-query-edit-ok") {
    abort(
      "tree-sitter direct query/edit smoke failed with code " +
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
async fn build_ocamlyacc_with_direct_object(root : String) -> String {
  let flags = ocamlyacc_flags(root)
  let objects : Array[String] = []
  for path in ocamlyacc_source_paths(root) {
    require_external_path(path, "ocamlyacc source")
    objects.push(
      compile_c_file_with_kimicc_direct_object_path(
        path,
        flags,
        "ocamlyacc_direct_external_" + source_id(path),
      ),
    )
  }
  let binary_path = "/tmp/kimicc_ocamlyacc_direct_external"
  run_command_checked(
    "clang -o " + shell_quote(binary_path) + " " + shell_join_quoted(objects),
    "link direct-object ocamlyacc",
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
fn ocamlyacc_command(
  binary_path : String,
  args : String,
  file_name : String,
) -> String {
  if args == "" {
    shell_quote(binary_path) + " " + shell_quote(file_name)
  } else {
    shell_quote(binary_path) + " " + args + " " + shell_quote(file_name)
  }
}

///|
async fn run_ocamlyacc_grammar_file(
  binary_path : String,
  source_path : String,
  file_name : String,
  args : String,
  work_dir : String,
  tag : String,
) -> CommandResult {
  run_command_checked(
    "rm -rf " + shell_quote(work_dir) + " && mkdir -p " + shell_quote(work_dir),
    "prepare ocamlyacc work dir",
  )
  run_command_checked(
    "cp " +
    shell_quote(source_path) +
    " " +
    shell_quote(work_dir + "/" + file_name),
    "copy ocamlyacc grammar",
  )
  run_command_capture(
    "cd " +
    shell_quote(work_dir) +
    " && " +
    ocamlyacc_command(binary_path, args, file_name),
    tag,
  )
}

///|
async fn run_ocamlyacc_calc_parser(
  binary_path : String,
  root : String,
  work_dir : String,
  tag : String,
) -> CommandResult {
  run_ocamlyacc_grammar_file(
    binary_path,
    root + "/testsuite/tests/tool-lexyacc/calc_parser.mly",
    "calc_parser.mly",
    "",
    work_dir,
    tag,
  )
}

///|
fn ocamlyacc_expression_grammar() -> String {
  let source =
    #|%token <string> ID
    #|%token <int> INT
    #|%token LET EQ IN PLUS STAR LPAREN RPAREN EOF
    #|%left PLUS
    #|%left STAR
    #|%start main expr_only
    #|%type <string> main expr_only expr
    #|%%
    #|main:
    #|    LET ID EQ expr IN expr EOF { "let " ^ $2 ^ "=" ^ $4 ^ " in " ^ $6 }
    #|  | expr EOF { $1 }
    #|;
    #|expr_only:
    #|    expr EOF { $1 }
    #|;
    #|expr:
    #|    INT { string_of_int $1 }
    #|  | ID { $1 }
    #|  | LPAREN expr RPAREN { "(" ^ $2 ^ ")" }
    #|  | expr PLUS expr { $1 ^ "+" ^ $3 }
    #|  | expr STAR expr { $1 ^ "*" ^ $3 }
    #|;
  source
}

///|
fn ocamlyacc_conflict_grammar() -> String {
  let source =
    #|%token INT PLUS EOF
    #|%start main
    #|%type <unit> main expr
    #|%%
    #|main:
    #|    expr EOF { () }
    #|;
    #|expr:
    #|    INT { () }
    #|  | expr PLUS expr { () }
    #|;
  source
}

///|
fn compare_ocamlyacc_file(
  kimicc_dir : String,
  clang_dir : String,
  file_name : String,
) -> Unit {
  run_command_checked(
    "cmp -s " +
    shell_quote(kimicc_dir + "/" + file_name) +
    " " +
    shell_quote(clang_dir + "/" + file_name),
    "compare ocamlyacc generated " + file_name,
  )
}

///|
async fn run_and_compare_ocamlyacc_grammar(
  kimicc_binary : String,
  clang_binary : String,
  grammar_path : String,
  file_name : String,
  stem : String,
  args : String,
  compare_verbose : Bool,
  work_root : String,
  tag : String,
) -> Unit {
  let kimicc_dir = work_root + "/" + tag + "/kimicc"
  let clang_dir = work_root + "/" + tag + "/clang"
  let kimicc = run_ocamlyacc_grammar_file(
    kimicc_binary,
    grammar_path,
    file_name,
    args,
    kimicc_dir,
    "ocamlyacc_kimicc_" + tag,
  )
  let clang = run_ocamlyacc_grammar_file(
    clang_binary,
    grammar_path,
    file_name,
    args,
    clang_dir,
    "ocamlyacc_clang_" + tag,
  )
  if kimicc.code != clang.code {
    abort(
      "ocamlyacc " +
      tag +
      " exit code differs:\nkimicc:\n" +
      kimicc.output +
      "\nclang:\n" +
      clang.output,
    )
  }
  if kimicc.output != clang.output {
    abort(
      "ocamlyacc " +
      tag +
      " output differs:\nkimicc:\n" +
      kimicc.output +
      "\nclang:\n" +
      clang.output,
    )
  }
  if kimicc.code != 0 {
    abort("ocamlyacc " + tag + " failed:\n" + kimicc.output)
  }
  compare_ocamlyacc_file(kimicc_dir, clang_dir, stem + ".ml")
  compare_ocamlyacc_file(kimicc_dir, clang_dir, stem + ".mli")
  if compare_verbose {
    compare_ocamlyacc_file(kimicc_dir, clang_dir, stem + ".output")
  }
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

///|
async test "external ocamlyacc grammar matrix matches clang when enabled" {
  if !external_testbed_enabled("ocamlyacc") {
    return
  }
  let root = "/tmp/kimicc_ocaml"
  require_external_path(root + "/yacc/main.c", "ocamlyacc source root")
  require_external_path(
    root + "/testsuite/tests/tool-lexyacc/parsecheck.mly",
    "ocamlyacc parsecheck grammar",
  )
  let kimicc_binary = build_ocamlyacc_with_kimicc(root)
  let clang_binary = build_ocamlyacc_with_clang(root)
  let fixture_dir = "/tmp/kimicc_ocamlyacc_external_matrix/fixtures"
  run_command_checked(
    "rm -rf " +
    shell_quote(fixture_dir) +
    " && mkdir -p " +
    shell_quote(fixture_dir),
    "prepare ocamlyacc matrix fixtures",
  )
  let expr_path = fixture_dir + "/expr_matrix.mly"
  let conflict_path = fixture_dir + "/conflict_matrix.mly"
  write_text_file(expr_path, ocamlyacc_expression_grammar())
  write_text_file(conflict_path, ocamlyacc_conflict_grammar())
  let work_root = "/tmp/kimicc_ocamlyacc_external_matrix/run"
  run_command_checked(
    "rm -rf " +
    shell_quote(work_root) +
    " && mkdir -p " +
    shell_quote(work_root),
    "prepare ocamlyacc matrix work root",
  )
  run_and_compare_ocamlyacc_grammar(
    kimicc_binary,
    clang_binary,
    root + "/testsuite/tests/tool-lexyacc/parsecheck.mly",
    "parsecheck.mly",
    "parsecheck",
    "-q --strict",
    false,
    work_root,
    "parsecheck",
  )
  run_and_compare_ocamlyacc_grammar(
    kimicc_binary, clang_binary, expr_path, "expr_matrix.mly", "expr_matrix", "",
    false, work_root, "expr_matrix",
  )
  run_and_compare_ocamlyacc_grammar(
    kimicc_binary, clang_binary, conflict_path, "conflict_matrix.mly", "conflict_matrix",
    "-v", true, work_root, "conflict_matrix",
  )
}

///|
async test "external ocamlyacc direct object grammar matrix matches clang when enabled" {
  if !external_testbed_enabled("ocamlyacc") {
    return
  }
  let root = "/tmp/kimicc_ocaml"
  require_external_path(root + "/yacc/main.c", "ocamlyacc source root")
  require_external_path(
    root + "/testsuite/tests/tool-lexyacc/parsecheck.mly",
    "ocamlyacc parsecheck grammar",
  )
  let direct_binary = build_ocamlyacc_with_direct_object(root)
  let clang_binary = build_ocamlyacc_with_clang(root)
  let fixture_dir = "/tmp/kimicc_ocamlyacc_direct_external_matrix/fixtures"
  run_command_checked(
    "rm -rf " +
    shell_quote(fixture_dir) +
    " && mkdir -p " +
    shell_quote(fixture_dir),
    "prepare direct ocamlyacc matrix fixtures",
  )
  let expr_path = fixture_dir + "/expr_matrix.mly"
  let conflict_path = fixture_dir + "/conflict_matrix.mly"
  write_text_file(expr_path, ocamlyacc_expression_grammar())
  write_text_file(conflict_path, ocamlyacc_conflict_grammar())
  let work_root = "/tmp/kimicc_ocamlyacc_direct_external_matrix/run"
  run_command_checked(
    "rm -rf " +
    shell_quote(work_root) +
    " && mkdir -p " +
    shell_quote(work_root),
    "prepare direct ocamlyacc matrix work root",
  )
  run_and_compare_ocamlyacc_grammar(
    direct_binary,
    clang_binary,
    root + "/testsuite/tests/tool-lexyacc/parsecheck.mly",
    "parsecheck.mly",
    "parsecheck",
    "-q --strict",
    false,
    work_root,
    "direct_parsecheck",
  )
  run_and_compare_ocamlyacc_grammar(
    direct_binary, clang_binary, expr_path, "expr_matrix.mly", "expr_matrix", "",
    false, work_root, "direct_expr_matrix",
  )
  run_and_compare_ocamlyacc_grammar(
    direct_binary, clang_binary, conflict_path, "conflict_matrix.mly", "conflict_matrix",
    "-v", true, work_root, "direct_conflict_matrix",
  )
}

///|
async fn compile_preprocessed_file_with_kimicc_object_path(
  path : String,
  tag : String,
) -> String {
  require_external_path(path, "preprocessed C testbed")
  let data = @fs.read_file(path)
  compile_source_to_object_path(data.text(), tag)
}

///|
async fn compile_preprocessed_file_with_kimicc_direct_object_path(
  path : String,
  tag : String,
) -> String {
  require_external_path(path, "preprocessed C testbed")
  let data = @fs.read_file(path)
  compile_source_to_direct_object_path(data.text(), tag)
}

///|
async fn compile_preprocessed_file_with_strict_mir_object_path(
  path : String,
  tag : String,
) -> String {
  require_external_path(path, "preprocessed C testbed")
  let data = @fs.read_file(path)
  compile_source_to_strict_mir_object_path(data.text(), tag)
}

///|
fn tinycc_smoke_source() -> String {
  let source =
    #|int fib(int n) {
    #|  return n < 2 ? n : fib(n - 1) + fib(n - 2);
    #|}
    #|
    #|int main(void) {
    #|  return fib(10) == 55 ? 42 : 1;
    #|}
  source
}

///|
async test "external TinyCC stripped compiler builds and emits smoke object when enabled" {
  if !external_testbed_enabled("tinycc") {
    return
  }
  let source_path = "/tmp/tinycc_stripped.c"
  require_external_path(source_path, "TinyCC stripped source")
  let data = @fs.read_file(source_path)
  let object_path = compile_source_to_object_path(
    data.text(),
    "tinycc_external_stripped",
  )
  let tcc_path = "/tmp/kimicc_tinycc_external"
  run_command_checked(
    "clang -o " + shell_quote(tcc_path) + " " + shell_quote(object_path),
    "link TinyCC external compiler",
  )
  let version = run_command_capture(
    shell_quote(tcc_path) + " -v",
    "tinycc_external_version",
  )
  if version.code != 0 || !version.output.contains("tcc version") {
    abort(
      "TinyCC external version failed with code " +
      version.code.to_string() +
      ":\n" +
      version.output,
    )
  }
  let smoke_source = tinycc_smoke_source()
  let smoke_source_path = "/tmp/kimicc_tinycc_external_smoke.c"
  let smoke_object_path = "/tmp/kimicc_tinycc_external_smoke.o"
  let smoke_binary_path = "/tmp/kimicc_tinycc_external_smoke"
  write_text_file(smoke_source_path, smoke_source)
  run_command_checked(
    "rm -f " +
    shell_quote(smoke_object_path) +
    " " +
    shell_quote(smoke_binary_path),
    "clean TinyCC smoke outputs",
  )
  run_command_checked(
    shell_quote(tcc_path) +
    " -c -o " +
    shell_quote(smoke_object_path) +
    " " +
    shell_quote(smoke_source_path),
    "TinyCC compile smoke object",
  )
  run_command_checked(
    "test -s " + shell_quote(smoke_object_path),
    "TinyCC smoke object exists",
  )
  let result = run_command_capture(
    "file " + shell_quote(smoke_object_path),
    "tinycc_external_smoke_object",
  )
  if result.code != 0 || !result.output.contains("ELF 64-bit") {
    abort(
      "TinyCC external smoke object check failed with code " +
      result.code.to_string() +
      ":\n" +
      result.output,
    )
  }
}

///|
async test "external TinyCC stripped compiler direct object builds and emits smoke object when enabled" {
  if !external_testbed_enabled("tinycc") {
    return
  }
  let source_path = "/tmp/tinycc_stripped.c"
  require_external_path(source_path, "TinyCC stripped source")
  let data = @fs.read_file(source_path)
  let object_path = compile_source_to_direct_object_path(
    data.text(),
    "tinycc_direct_external_stripped",
  )
  let tcc_path = "/tmp/kimicc_tinycc_direct_external"
  run_command_checked(
    "clang -o " + shell_quote(tcc_path) + " " + shell_quote(object_path),
    "link direct TinyCC external compiler",
  )
  let version = run_command_capture(
    shell_quote(tcc_path) + " -v",
    "tinycc_direct_external_version",
  )
  if version.code != 0 || !version.output.contains("tcc version") {
    abort(
      "TinyCC direct external version failed with code " +
      version.code.to_string() +
      ":\n" +
      version.output,
    )
  }
  let smoke_source_path = "/tmp/kimicc_tinycc_direct_external_smoke.c"
  let smoke_object_path = "/tmp/kimicc_tinycc_direct_external_smoke.o"
  let smoke_binary_path = "/tmp/kimicc_tinycc_direct_external_smoke"
  write_text_file(smoke_source_path, tinycc_smoke_source())
  run_command_checked(
    "rm -f " +
    shell_quote(smoke_object_path) +
    " " +
    shell_quote(smoke_binary_path),
    "clean direct TinyCC smoke outputs",
  )
  run_command_checked(
    shell_quote(tcc_path) +
    " -c -o " +
    shell_quote(smoke_object_path) +
    " " +
    shell_quote(smoke_source_path),
    "direct TinyCC compile smoke object",
  )
  run_command_checked(
    "test -s " + shell_quote(smoke_object_path),
    "direct TinyCC smoke object exists",
  )
  let result = run_command_capture(
    "file " + shell_quote(smoke_object_path),
    "tinycc_direct_external_smoke_object",
  )
  if result.code != 0 || !result.output.contains("ELF 64-bit") {
    abort(
      "TinyCC direct external smoke object check failed with code " +
      result.code.to_string() +
      ":\n" +
      result.output,
    )
  }
}

///|
async fn compile_quickjs_object(
  build_dir : String,
  name : String,
  objects : Array[String],
) -> Unit {
  objects.push(
    compile_preprocessed_file_with_kimicc_object_path(
      build_dir + "/" + name + ".i",
      "quickjs_external_" + name,
    ),
  )
}

///|
async fn compile_quickjs_direct_object(
  build_dir : String,
  name : String,
  objects : Array[String],
) -> Unit {
  objects.push(
    compile_preprocessed_file_with_kimicc_direct_object_path(
      build_dir + "/" + name + ".i",
      "quickjs_direct_external_" + name,
    ),
  )
}

///|
async fn compile_quickjs_strict_mir_object(
  build_dir : String,
  name : String,
  objects : Array[String],
) -> Unit {
  objects.push(
    compile_preprocessed_file_with_strict_mir_object_path(
      build_dir + "/" + name + ".i",
      "quickjs_strict_mir_external_" + name,
    ),
  )
}

///|
async fn build_quickjs_qjs_external(tag : String) -> String {
  let build_dir = "/tmp/kimicc_quickjs_build"
  let objects : Array[String] = []
  for
    name in [
      "quickjs", "libregexp", "libunicode", "cutils", "quickjs-libc", "repl", "qjs",
      "dtoa",
    ] {
    compile_quickjs_object(build_dir, name, objects)
  }
  let qjs_path = "/tmp/kimicc_quickjs_external_qjs_" + tag
  run_command_checked(
    "clang -o " + shell_quote(qjs_path) + " " + shell_join_quoted(objects),
    "link QuickJS qjs external " + tag,
  )
  qjs_path
}

///|
async fn build_quickjs_qjs_direct_external(tag : String) -> String {
  let build_dir = "/tmp/kimicc_quickjs_build"
  let objects : Array[String] = []
  for
    name in [
      "quickjs", "libregexp", "libunicode", "cutils", "quickjs-libc", "repl", "qjs",
      "dtoa",
    ] {
    compile_quickjs_direct_object(build_dir, name, objects)
  }
  let qjs_path = "/tmp/kimicc_quickjs_direct_external_qjs_" + tag
  run_command_checked(
    "clang -o " + shell_quote(qjs_path) + " " + shell_join_quoted(objects),
    "link direct QuickJS qjs external " + tag,
  )
  qjs_path
}

///|
async fn build_quickjs_qjs_strict_mir_external(tag : String) -> String {
  let build_dir = "/tmp/kimicc_quickjs_build"
  let objects : Array[String] = []
  for
    name in [
      "quickjs", "libregexp", "libunicode", "cutils", "quickjs-libc", "repl", "qjs",
      "dtoa",
    ] {
    compile_quickjs_strict_mir_object(build_dir, name, objects)
  }
  let qjs_path = "/tmp/kimicc_quickjs_strict_mir_external_qjs_" + tag
  run_command_checked(
    "clang -o " + shell_quote(qjs_path) + " " + shell_join_quoted(objects),
    "link strict MIR QuickJS qjs external " + tag,
  )
  qjs_path
}

///|
async test "external QuickJS qjs builds and runs smoke when enabled" {
  if !external_testbed_enabled("quickjs") {
    return
  }
  let qjs_path = build_quickjs_qjs_external("smoke")
  let script = "let s = 0; for (let i = 0; i < 1000; i++) s += i; " +
    "console.log('quickjs-smoke', s);"
  let result = run_command_capture(
    shell_quote(qjs_path) + " -e " + shell_quote(script),
    "quickjs_external_smoke",
  )
  if result.code != 0 || !result.output.contains("quickjs-smoke 499500") {
    abort(
      "QuickJS external smoke failed with code " +
      result.code.to_string() +
      ":\n" +
      result.output,
    )
  }
}

///|
async test "external QuickJS strict MIR qjs runs language matrix when enabled" {
  if !external_testbed_enabled("quickjs") {
    return
  }
  let qjs_path = build_quickjs_qjs_strict_mir_external("matrix")
  let script =
    #|function assert(cond, message) {
    #|  if (!cond) throw new Error(message);
    #|}
    #|
    #|class Box {
    #|  constructor(value) { this.value = value; }
    #|  inc(delta) {
    #|    this.value += delta;
    #|    return this.value;
    #|  }
    #|}
    #|
    #|function *range(n) {
    #|  for (let i = 0; i < n; i++) yield i;
    #|}
    #|
    #|let box = new Box(10);
    #|let total = 0;
    #|for (const n of range(5)) total += box.inc(n);
    #|assert(total === 70, "generator/class total");
    #|
    #|let data = JSON.parse(JSON.stringify({ items: ["alpha", "beta"], total }));
    #|assert(data.items.join(":") === "alpha:beta", "json roundtrip");
    #|
    #|let match = /([a-z]+)-(\d+)/.exec("ticket-42");
    #|assert(match[1] === "ticket" && Number(match[2]) === 42, "regexp");
    #|
    #|let mapped = [1, 2, 3, 4]
    #|  .map(x => x * x)
    #|  .filter(x => x % 2 === 0)
    #|  .reduce((a, b) => a + b, 0);
    #|assert(mapped === 20, "array methods");
    #|
    #|let keys = Object.keys({ b: 1, a: 2 }).sort().join("");
    #|assert(keys === "ab", "object keys");
    #|
    #|let big = typeof BigInt === "function" ? Number(BigInt(10) + BigInt(32)) : 42;
    #|assert(big === 42, "bigint");
    #|
    #|console.log("quickjs-strict-mir-matrix", total + mapped + big);
  let result = run_command_capture(
    shell_quote(qjs_path) + " -e " + shell_quote(script),
    "quickjs_strict_mir_external_matrix",
  )
  if result.code != 0 ||
    !result.output.contains("quickjs-strict-mir-matrix 132") {
    abort(
      "QuickJS strict MIR external language matrix failed with code " +
      result.code.to_string() +
      ":\n" +
      result.output,
    )
  }
}

///|
async test "external QuickJS direct object qjs runs language matrix when enabled" {
  if !external_testbed_enabled("quickjs") {
    return
  }
  let qjs_path = build_quickjs_qjs_direct_external("matrix")
  let script =
    #|function assert(cond, message) {
    #|  if (!cond) throw new Error(message);
    #|}
    #|
    #|let total = 0;
    #|for (let i = 0; i < 16; i++) total += i;
    #|let mapped = [1, 2, 3, 4].map(x => x * x).filter(x => x > 4).join(",");
    #|let text = JSON.parse(JSON.stringify({ mapped })).mapped;
    #|assert(total === 120, "loop total");
    #|assert(text === "9,16", "json array methods");
    #|assert(/quick(js)?/.test("quickjs"), "regexp");
    #|console.log("quickjs-direct-matrix", total + text.length);
  let result = run_command_capture(
    shell_quote(qjs_path) + " -e " + shell_quote(script),
    "quickjs_direct_external_matrix",
  )
  if result.code != 0 || !result.output.contains("quickjs-direct-matrix 124") {
    abort(
      "QuickJS direct external language matrix failed with code " +
      result.code.to_string() +
      ":\n" +
      result.output,
    )
  }
}

///|
async test "external QuickJS qjs runs language matrix when enabled" {
  if !external_testbed_enabled("quickjs") {
    return
  }
  let qjs_path = build_quickjs_qjs_external("matrix")
  let script =
    #|function assert(cond, message) {
    #|  if (!cond) throw new Error(message);
    #|}
    #|
    #|class Box {
    #|  constructor(value) { this.value = value; }
    #|  inc(delta) {
    #|    this.value += delta;
    #|    return this.value;
    #|  }
    #|}
    #|
    #|function *range(n) {
    #|  for (let i = 0; i < n; i++) yield i;
    #|}
    #|
    #|let box = new Box(10);
    #|let total = 0;
    #|for (const n of range(5)) total += box.inc(n);
    #|assert(total === 70, "generator/class total");
    #|
    #|let data = JSON.parse(JSON.stringify({ items: ["alpha", "beta"], total }));
    #|assert(data.items.join(":") === "alpha:beta", "json roundtrip");
    #|
    #|let match = /([a-z]+)-(\d+)/.exec("ticket-42");
    #|assert(match[1] === "ticket" && Number(match[2]) === 42, "regexp");
    #|
    #|let mapped = [1, 2, 3, 4]
    #|  .map(x => x * x)
    #|  .filter(x => x % 2 === 0)
    #|  .reduce((a, b) => a + b, 0);
    #|assert(mapped === 20, "array methods");
    #|
    #|let keys = Object.keys({ b: 1, a: 2 }).sort().join("");
    #|assert(keys === "ab", "object keys");
    #|
    #|let big = typeof BigInt === "function" ? Number(BigInt(10) + BigInt(32)) : 42;
    #|assert(big === 42, "bigint");
    #|
    #|console.log("quickjs-matrix", total + mapped + big);
  let result = run_command_capture(
    shell_quote(qjs_path) + " -e " + shell_quote(script),
    "quickjs_external_matrix",
  )
  if result.code != 0 || !result.output.contains("quickjs-matrix 132") {
    abort(
      "QuickJS external language matrix failed with code " +
      result.code.to_string() +
      ":\n" +
      result.output,
    )
  }
}

///|
fn zlib_flags(root : String) -> String {
  "-DHAVE_UNISTD_H -I " + shell_quote(root)
}

///|
fn zlib_source_paths(root : String) -> Array[String] {
  let paths : Array[String] = []
  for
    name in [
      "adler32", "compress", "crc32", "deflate", "infback", "inffast", "inflate",
      "inftrees", "trees", "uncompr", "zutil",
    ] {
    paths.push(root + "/" + name + ".c")
  }
  paths
}

///|
fn zlib_smoke_source() -> String {
  let source =
    #|#include "zlib.h"
    #|
    #|extern int printf(const char *, ...);
    #|extern unsigned long strlen(const char *);
    #|extern int strcmp(const char *, const char *);
    #|
    #|int main(void) {
    #|  const unsigned char input[] = "kimicc zlib smoke: alpha beta gamma alpha beta gamma";
    #|  unsigned char compressed[256];
    #|  unsigned char output[256];
    #|  uLongf compressed_len = sizeof(compressed);
    #|  uLongf output_len = sizeof(output);
    #|  int rc = compress2(compressed, &compressed_len, input, (uLong)strlen((const char *)input) + 1, Z_BEST_COMPRESSION);
    #|  if (rc != Z_OK) return 10 + rc;
    #|  rc = uncompress(output, &output_len, compressed, compressed_len);
    #|  if (rc != Z_OK) return 20 + rc;
    #|  if (output_len != strlen((const char *)input) + 1) return 30;
    #|  if (strcmp((const char *)input, (const char *)output) != 0) return 31;
    #|  printf("zlib-smoke %lu %lu %s\n", (unsigned long)compressed_len, (unsigned long)output_len, zlibVersion());
    #|  return 42;
    #|}
  source
}

///|
async fn compile_zlib_smoke_driver(
  root : String,
  tag : String,
  direct : Bool,
) -> String {
  let path = "/tmp/kimicc_zlib_" + tag + "_driver.c"
  write_text_file(path, zlib_smoke_source())
  if direct {
    compile_c_file_with_kimicc_direct_object_path(
      path,
      zlib_flags(root),
      "zlib_direct_external_" + tag + "_driver",
    )
  } else {
    compile_c_file_with_kimicc_object_path(
      path,
      zlib_flags(root),
      "zlib_external_" + tag + "_driver",
    )
  }
}

///|
async fn build_zlib_with_kimicc(root : String, tag : String) -> String {
  let flags = zlib_flags(root)
  let objects : Array[String] = []
  for path in zlib_source_paths(root) {
    require_external_path(path, "zlib source")
    objects.push(
      compile_c_file_with_kimicc_object_path(
        path,
        flags,
        "zlib_external_" + tag + "_" + source_id(path),
      ),
    )
  }
  objects.push(compile_zlib_smoke_driver(root, tag, false))
  let binary_path = "/tmp/kimicc_zlib_external_" + tag
  run_command_checked(
    "clang -o " + shell_quote(binary_path) + " " + shell_join_quoted(objects),
    "link zlib external " + tag,
  )
  binary_path
}

///|
async fn build_zlib_with_direct_object(root : String, tag : String) -> String {
  let flags = zlib_flags(root)
  let objects : Array[String] = []
  for path in zlib_source_paths(root) {
    require_external_path(path, "zlib source")
    objects.push(
      compile_c_file_with_kimicc_direct_object_path(
        path,
        flags,
        "zlib_direct_external_" + tag + "_" + source_id(path),
      ),
    )
  }
  objects.push(compile_zlib_smoke_driver(root, tag, true))
  let binary_path = "/tmp/kimicc_zlib_direct_external_" + tag
  run_command_checked(
    "clang -o " + shell_quote(binary_path) + " " + shell_join_quoted(objects),
    "link direct zlib external " + tag,
  )
  binary_path
}

///|
async fn assert_zlib_smoke(binary_path : String, tag : String) -> Unit {
  let result = run_command_capture(
    shell_quote(binary_path),
    "zlib_external_smoke_" + tag,
  )
  if result.code != 42 ||
    !result.output.contains("zlib-smoke ") ||
    !result.output.contains(" 1.3.1") {
    abort(
      "zlib external smoke failed with code " +
      result.code.to_string() +
      ":\n" +
      result.output,
    )
  }
}

///|
async test "external zlib compression roundtrip runs when enabled" {
  if !external_testbed_enabled("zlib") {
    return
  }
  let root = "/tmp/kimicc_zlib/zlib-1.3.1"
  require_external_path(root + "/zlib.h", "zlib source root")
  let binary_path = build_zlib_with_kimicc(root, "roundtrip")
  assert_zlib_smoke(binary_path, "roundtrip")
}

///|
async test "external zlib direct object compression roundtrip runs when enabled" {
  if !external_testbed_enabled("zlib") {
    return
  }
  let root = "/tmp/kimicc_zlib/zlib-1.3.1"
  require_external_path(root + "/zlib.h", "zlib source root")
  let binary_path = build_zlib_with_direct_object(root, "roundtrip")
  assert_zlib_smoke(binary_path, "direct_roundtrip")
}

///|
fn xxhash_flags(root : String) -> String {
  "-DXXH_VECTOR=0 -U__ARM_NEON -U__ARM_NEON__ -I " + shell_quote(root)
}

///|
fn xxhash_smoke_source() -> String {
  let source =
    #|#include "xxhash.h"
    #|
    #|extern int printf(const char *, ...);
    #|extern unsigned long strlen(const char *);
    #|
    #|int main(void) {
    #|  const char *text = "kimicc xxhash smoke: alpha beta gamma";
    #|  unsigned int h32 = XXH32(text, strlen(text), 0x12345678U);
    #|  unsigned long long h64 = (unsigned long long)XXH64(text, strlen(text), 0x123456789abcdef0ULL);
    #|  unsigned long long h3 = (unsigned long long)XXH3_64bits(text, strlen(text));
    #|  unsigned long long h3seed = (unsigned long long)XXH3_64bits_withSeed(text, strlen(text), 0x123456789abcdef0ULL);
    #|  XXH128_hash_t h128 = XXH3_128bits(text, strlen(text));
    #|  XXH64_state_t *state = XXH64_createState();
    #|  if (!state) return 10;
    #|  if (XXH64_reset(state, 0x123456789abcdef0ULL) != XXH_OK) return 11;
    #|  if (XXH64_update(state, text, 13) != XXH_OK) return 12;
    #|  if (XXH64_update(state, text + 13, strlen(text) - 13) != XXH_OK) return 13;
    #|  unsigned long long stream = (unsigned long long)XXH64_digest(state);
    #|  XXH64_freeState(state);
    #|  XXH3_state_t *state3 = XXH3_createState();
    #|  if (!state3) return 14;
    #|  if (XXH3_64bits_reset(state3) != XXH_OK) return 15;
    #|  if (XXH3_64bits_update(state3, text, 13) != XXH_OK) return 16;
    #|  if (XXH3_64bits_update(state3, text + 13, strlen(text) - 13) != XXH_OK) return 17;
    #|  unsigned long long stream3 = (unsigned long long)XXH3_64bits_digest(state3);
    #|  XXH3_freeState(state3);
    #|  if (h32 != 313589854U) return 20;
    #|  if (h64 != 12728883423309814983ULL) return 21;
    #|  if (stream != h64) return 22;
    #|  if (h3 != 12821467295178229974ULL) return 23;
    #|  if (h3seed != 2994235077724246409ULL) return 24;
    #|  if ((unsigned long long)h128.low64 != 6904674586532039231ULL) return 25;
    #|  if ((unsigned long long)h128.high64 != 12534773462583583157ULL) return 26;
    #|  if (stream3 != h3) return 27;
    #|  printf("xxhash-smoke %u %llu %llu %llu %llu %llu %llu\n", h32, h64, stream, h3, h3seed, (unsigned long long)h128.low64, (unsigned long long)h128.high64);
    #|  return 42;
    #|}
  source
}

///|
async fn compile_xxhash_smoke_driver(
  root : String,
  tag : String,
  direct : Bool,
) -> String {
  let path = "/tmp/kimicc_xxhash_" + tag + "_driver.c"
  write_text_file(path, xxhash_smoke_source())
  if direct {
    compile_c_file_with_kimicc_direct_object_path(
      path,
      xxhash_flags(root),
      "xxhash_direct_external_" + tag + "_driver",
    )
  } else {
    compile_c_file_with_kimicc_object_path(
      path,
      xxhash_flags(root),
      "xxhash_external_" + tag + "_driver",
    )
  }
}

///|
async fn build_xxhash_with_kimicc(root : String, tag : String) -> String {
  let library_path = root + "/xxhash.c"
  require_external_path(library_path, "xxHash source")
  let objects = [
    compile_c_file_with_kimicc_object_path(
      library_path,
      xxhash_flags(root),
      "xxhash_external_" + tag + "_library",
    ),
    compile_xxhash_smoke_driver(root, tag, false),
  ]
  let binary_path = "/tmp/kimicc_xxhash_external_" + tag
  run_command_checked(
    "clang -o " + shell_quote(binary_path) + " " + shell_join_quoted(objects),
    "link xxHash external " + tag,
  )
  binary_path
}

///|
async fn build_xxhash_with_direct_object(root : String, tag : String) -> String {
  let library_path = root + "/xxhash.c"
  require_external_path(library_path, "xxHash source")
  let objects = [
    compile_c_file_with_kimicc_direct_object_path(
      library_path,
      xxhash_flags(root),
      "xxhash_direct_external_" + tag + "_library",
    ),
    compile_xxhash_smoke_driver(root, tag, true),
  ]
  let binary_path = "/tmp/kimicc_xxhash_direct_external_" + tag
  run_command_checked(
    "clang -o " + shell_quote(binary_path) + " " + shell_join_quoted(objects),
    "link direct xxHash external " + tag,
  )
  binary_path
}

///|
async fn assert_xxhash_smoke(binary_path : String, tag : String) -> Unit {
  let result = run_command_capture(
    shell_quote(binary_path),
    "xxhash_external_smoke_" + tag,
  )
  if result.code != 42 ||
    !result.output.contains(
      "xxhash-smoke 313589854 12728883423309814983 12728883423309814983 12821467295178229974 2994235077724246409 6904674586532039231 12534773462583583157",
    ) {
    abort(
      "xxHash external smoke failed with code " +
      result.code.to_string() +
      ":\n" +
      result.output,
    )
  }
}

///|
async test "external xxHash checksum matrix runs when enabled" {
  if !external_testbed_enabled("xxhash") {
    return
  }
  let root = "/tmp/kimicc_xxhash/xxHash-0.8.2"
  require_external_path(root + "/xxhash.h", "xxHash source root")
  let binary_path = build_xxhash_with_kimicc(root, "checksum_matrix")
  assert_xxhash_smoke(binary_path, "checksum_matrix")
}

///|
async test "external xxHash direct object checksum matrix runs when enabled" {
  if !external_testbed_enabled("xxhash") {
    return
  }
  let root = "/tmp/kimicc_xxhash/xxHash-0.8.2"
  require_external_path(root + "/xxhash.h", "xxHash source root")
  let binary_path = build_xxhash_with_direct_object(root, "checksum_matrix")
  assert_xxhash_smoke(binary_path, "direct_checksum_matrix")
}

///|
fn cjson_flags(root : String) -> String {
  "-I " + shell_quote(root)
}

///|
fn cjson_smoke_source() -> String {
  let source =
    #|#include "cJSON.h"
    #|
    #|extern int printf(const char *, ...);
    #|extern int strcmp(const char *, const char *);
    #|extern char *strstr(const char *, const char *);
    #|
    #|int main(void) {
    #|  const char *text = "{\"name\":\"kimicc\",\"values\":[1,2,3.5],\"nested\":{\"ok\":true}}";
    #|  cJSON *root = cJSON_Parse(text);
    #|  if (!root) return 10;
    #|  cJSON *name = cJSON_GetObjectItemCaseSensitive(root, "name");
    #|  cJSON *values = cJSON_GetObjectItemCaseSensitive(root, "values");
    #|  cJSON *nested = cJSON_GetObjectItemCaseSensitive(root, "nested");
    #|  cJSON *ok = cJSON_GetObjectItemCaseSensitive(nested, "ok");
    #|  if (!cJSON_IsString(name) || strcmp(name->valuestring, "kimicc") != 0) return 11;
    #|  if (!cJSON_IsArray(values) || cJSON_GetArraySize(values) != 3) return 12;
    #|  double total = 0.0;
    #|  for (int i = 0; i < cJSON_GetArraySize(values); i++) {
    #|    cJSON *item = cJSON_GetArrayItem(values, i);
    #|    if (!cJSON_IsNumber(item)) return 13;
    #|    total += item->valuedouble;
    #|  }
    #|  if (total < 6.49 || total > 6.51) return 14;
    #|  if (!cJSON_IsTrue(ok)) return 15;
    #|  cJSON_AddStringToObject(root, "mode", "direct");
    #|  char *printed = cJSON_PrintUnformatted(root);
    #|  if (!printed) return 16;
    #|  int has_mode = strstr(printed, "\"mode\":\"direct\"") != 0;
    #|  printf("cjson-smoke %.1f %d %s\n", total, cJSON_GetArraySize(values), has_mode ? "ok" : "missing");
    #|  cJSON_free(printed);
    #|  cJSON_Delete(root);
    #|  return has_mode ? 42 : 17;
    #|}
  source
}

///|
async fn compile_cjson_smoke_driver(
  root : String,
  tag : String,
  direct : Bool,
) -> String {
  let path = "/tmp/kimicc_cjson_" + tag + "_driver.c"
  write_text_file(path, cjson_smoke_source())
  if direct {
    compile_c_file_with_kimicc_direct_object_path(
      path,
      cjson_flags(root),
      "cjson_direct_external_" + tag + "_driver",
    )
  } else {
    compile_c_file_with_kimicc_object_path(
      path,
      cjson_flags(root),
      "cjson_external_" + tag + "_driver",
    )
  }
}

///|
async fn build_cjson_with_kimicc(root : String, tag : String) -> String {
  let library_path = root + "/cJSON.c"
  require_external_path(library_path, "cJSON source")
  let objects = [
    compile_c_file_with_kimicc_object_path(
      library_path,
      cjson_flags(root),
      "cjson_external_" + tag + "_library",
    ),
    compile_cjson_smoke_driver(root, tag, false),
  ]
  let binary_path = "/tmp/kimicc_cjson_external_" + tag
  run_command_checked(
    "clang -o " + shell_quote(binary_path) + " " + shell_join_quoted(objects),
    "link cJSON external " + tag,
  )
  binary_path
}

///|
async fn build_cjson_with_direct_object(root : String, tag : String) -> String {
  let library_path = root + "/cJSON.c"
  require_external_path(library_path, "cJSON source")
  let objects = [
    compile_c_file_with_kimicc_direct_object_path(
      library_path,
      cjson_flags(root),
      "cjson_direct_external_" + tag + "_library",
    ),
    compile_cjson_smoke_driver(root, tag, true),
  ]
  let binary_path = "/tmp/kimicc_cjson_direct_external_" + tag
  run_command_checked(
    "clang -o " + shell_quote(binary_path) + " " + shell_join_quoted(objects),
    "link direct cJSON external " + tag,
  )
  binary_path
}

///|
async fn assert_cjson_smoke(binary_path : String, tag : String) -> Unit {
  let result = run_command_capture(
    shell_quote(binary_path),
    "cjson_external_smoke_" + tag,
  )
  if result.code != 42 || !result.output.contains("cjson-smoke 6.5 3 ok") {
    abort(
      "cJSON external smoke failed with code " +
      result.code.to_string() +
      ":\n" +
      result.output,
    )
  }
}

///|
async test "external cJSON parser roundtrip runs when enabled" {
  if !external_testbed_enabled("cjson") {
    return
  }
  let root = "/tmp/kimicc_cjson/cJSON-1.7.18"
  require_external_path(root + "/cJSON.h", "cJSON source root")
  let binary_path = build_cjson_with_kimicc(root, "roundtrip")
  assert_cjson_smoke(binary_path, "roundtrip")
}

///|
async test "external cJSON direct object parser roundtrip runs when enabled" {
  if !external_testbed_enabled("cjson") {
    return
  }
  let root = "/tmp/kimicc_cjson/cJSON-1.7.18"
  require_external_path(root + "/cJSON.h", "cJSON source root")
  let binary_path = build_cjson_with_direct_object(root, "roundtrip")
  assert_cjson_smoke(binary_path, "direct_roundtrip")
}

///|
fn inih_flags(root : String) -> String {
  "-DINI_HANDLER_LINENO=1 -DINI_CALL_HANDLER_ON_NEW_SECTION=1 -DINI_ALLOW_NO_VALUE=1 -I " +
  shell_quote(root)
}

///|
fn inih_smoke_source() -> String {
  let source =
    #|#include "ini.h"
    #|
    #|extern int printf(const char *, ...);
    #|extern int strcmp(const char *, const char *);
    #|
    #|typedef struct {
    #|  int sections;
    #|  int callbacks;
    #|  int server_port;
    #|  int multiline_hits;
    #|  int no_value_hits;
    #|  char host[32];
    #|  char title[64];
    #|} Config;
    #|
    #|static void copy_text(char *dst, unsigned long cap, const char *src) {
    #|  unsigned long i = 0;
    #|  while (i + 1 < cap && src[i]) {
    #|    dst[i] = src[i];
    #|    i++;
    #|  }
    #|  dst[i] = 0;
    #|}
    #|
    #|static void append_text(char *dst, unsigned long cap, const char *src) {
    #|  unsigned long i = 0;
    #|  unsigned long j = 0;
    #|  while (i < cap && dst[i]) i++;
    #|  while (i + 1 < cap && src[j]) {
    #|    dst[i] = src[j];
    #|    i++;
    #|    j++;
    #|  }
    #|  dst[i] = 0;
    #|}
    #|
    #|static int parse_decimal(const char *s) {
    #|  int value = 0;
    #|  while (*s >= '0' && *s <= '9') {
    #|    value = value * 10 + (*s - '0');
    #|    s++;
    #|  }
    #|  return value;
    #|}
    #|
    #|static int handler(void *user, const char *section, const char *name, const char *value, int lineno) {
    #|  Config *cfg = (Config *)user;
    #|  cfg->callbacks++;
    #|  if (name == 0) {
    #|    cfg->sections++;
    #|    return lineno > 0;
    #|  }
    #|  if (strcmp(section, "server") == 0 && strcmp(name, "host") == 0) {
    #|    copy_text(cfg->host, sizeof(cfg->host), value);
    #|  } else if (strcmp(section, "server") == 0 && strcmp(name, "port") == 0) {
    #|    cfg->server_port = parse_decimal(value);
    #|  } else if (strcmp(section, "meta") == 0 && strcmp(name, "title") == 0) {
    #|    if (cfg->title[0]) append_text(cfg->title, sizeof(cfg->title), ":");
    #|    append_text(cfg->title, sizeof(cfg->title), value);
    #|    cfg->multiline_hits++;
    #|  } else if (strcmp(section, "meta") == 0 && strcmp(name, "flag") == 0 && value == 0) {
    #|    cfg->no_value_hits++;
    #|  }
    #|  return lineno > 0;
    #|}
    #|
    #|int main(void) {
    #|  const char *text =
    #|      "; comment\n"
    #|      "[server]\n"
    #|      "host = localhost ; inline\n"
    #|      "port: 8080\n"
    #|      "[meta]\n"
    #|      "title = alpha\n"
    #|      "  beta\n"
    #|      "flag\n";
    #|  Config cfg = {0};
    #|  int rc = ini_parse_string(text, handler, &cfg);
    #|  if (rc != 0) return 10 + rc;
    #|  if (cfg.sections != 2) return 20;
    #|  if (cfg.callbacks != 7) return 21;
    #|  if (strcmp(cfg.host, "localhost") != 0) return 22;
    #|  if (cfg.server_port != 8080) return 23;
    #|  if (strcmp(cfg.title, "alpha:beta") != 0) return 24;
    #|  if (cfg.multiline_hits != 2) return 25;
    #|  if (cfg.no_value_hits != 1) return 26;
    #|  printf("inih-smoke %d %d %s %s\n", cfg.sections, cfg.server_port, cfg.host, cfg.title);
    #|  return 42;
    #|}
  source
}

///|
async fn compile_inih_smoke_driver(
  root : String,
  tag : String,
  direct : Bool,
) -> String {
  let path = "/tmp/kimicc_inih_" + tag + "_driver.c"
  write_text_file(path, inih_smoke_source())
  if direct {
    compile_c_file_with_kimicc_direct_object_path(
      path,
      inih_flags(root),
      "inih_direct_external_" + tag + "_driver",
    )
  } else {
    compile_c_file_with_kimicc_object_path(
      path,
      inih_flags(root),
      "inih_external_" + tag + "_driver",
    )
  }
}

///|
async fn build_inih_with_kimicc(root : String, tag : String) -> String {
  let library_path = root + "/ini.c"
  require_external_path(library_path, "inih source")
  let objects = [
    compile_c_file_with_kimicc_object_path(
      library_path,
      inih_flags(root),
      "inih_external_" + tag + "_library",
    ),
    compile_inih_smoke_driver(root, tag, false),
  ]
  let binary_path = "/tmp/kimicc_inih_external_" + tag
  run_command_checked(
    "clang -o " + shell_quote(binary_path) + " " + shell_join_quoted(objects),
    "link inih external " + tag,
  )
  binary_path
}

///|
async fn build_inih_with_direct_object(root : String, tag : String) -> String {
  let library_path = root + "/ini.c"
  require_external_path(library_path, "inih source")
  let objects = [
    compile_c_file_with_kimicc_direct_object_path(
      library_path,
      inih_flags(root),
      "inih_direct_external_" + tag + "_library",
    ),
    compile_inih_smoke_driver(root, tag, true),
  ]
  let binary_path = "/tmp/kimicc_inih_direct_external_" + tag
  run_command_checked(
    "clang -o " + shell_quote(binary_path) + " " + shell_join_quoted(objects),
    "link direct inih external " + tag,
  )
  binary_path
}

///|
async fn assert_inih_smoke(binary_path : String, tag : String) -> Unit {
  let result = run_command_capture(
    shell_quote(binary_path),
    "inih_external_smoke_" + tag,
  )
  if result.code != 42 ||
    !result.output.contains("inih-smoke 2 8080 localhost alpha:beta") {
    abort(
      "inih external smoke failed with code " +
      result.code.to_string() +
      ":\n" +
      result.output,
    )
  }
}

///|
async test "external inih parser callback matrix runs when enabled" {
  if !external_testbed_enabled("inih") {
    return
  }
  let root = "/tmp/kimicc_inih/inih-r58"
  require_external_path(root + "/ini.h", "inih source root")
  let binary_path = build_inih_with_kimicc(root, "callback_matrix")
  assert_inih_smoke(binary_path, "callback_matrix")
}

///|
async test "external inih direct object parser callback matrix runs when enabled" {
  if !external_testbed_enabled("inih") {
    return
  }
  let root = "/tmp/kimicc_inih/inih-r58"
  require_external_path(root + "/ini.h", "inih source root")
  let binary_path = build_inih_with_direct_object(root, "callback_matrix")
  assert_inih_smoke(binary_path, "direct_callback_matrix")
}

///|
fn lua_flags(root : String) -> String {
  "-DLUA_COMPAT_5_3 -I " + shell_quote(root + "/src")
}

///|
fn lua_source_paths(root : String) -> Array[String] {
  let paths : Array[String] = []
  for
    name in [
      "lapi", "lcode", "lctype", "ldebug", "ldo", "ldump", "lfunc", "lgc", "llex",
      "lmem", "lobject", "lopcodes", "lparser", "lstate", "lstring", "ltable", "ltm",
      "lundump", "lvm", "lzio", "lauxlib", "lbaselib", "lcorolib", "ldblib", "liolib",
      "lmathlib", "loadlib", "loslib", "lstrlib", "ltablib", "lutf8lib", "linit",
      "lua",
    ] {
    paths.push(root + "/src/" + name + ".c")
  }
  paths
}

///|
async fn build_lua_with_kimicc(root : String, tag : String) -> String {
  let flags = lua_flags(root)
  let objects : Array[String] = []
  for path in lua_source_paths(root) {
    require_external_path(path, "Lua source")
    objects.push(
      compile_c_file_with_kimicc_object_path(
        path,
        flags,
        "lua_external_" + tag + "_" + source_id(path),
      ),
    )
  }
  let binary_path = "/tmp/kimicc_lua_external_" + tag
  run_command_checked(
    "clang -o " +
    shell_quote(binary_path) +
    " " +
    shell_join_quoted(objects) +
    " -lm",
    "link Lua external " + tag,
  )
  binary_path
}

///|
async fn build_lua_with_direct_object(root : String, tag : String) -> String {
  let flags = lua_flags(root)
  let objects : Array[String] = []
  for path in lua_source_paths(root) {
    require_external_path(path, "Lua source")
    objects.push(
      compile_c_file_with_kimicc_direct_object_path(
        path,
        flags,
        "lua_direct_external_" + tag + "_" + source_id(path),
      ),
    )
  }
  let binary_path = "/tmp/kimicc_lua_direct_external_" + tag
  run_command_checked(
    "clang -o " +
    shell_quote(binary_path) +
    " " +
    shell_join_quoted(objects) +
    " -lm",
    "link direct Lua external " + tag,
  )
  binary_path
}

///|
fn lua_language_matrix_script() -> String {
  let script =
    #|local function fact(n)
    #|  if n < 2 then return 1 end
    #|  return n * fact(n - 1)
    #|end
    #|
    #|local total = 0
    #|local values = {}
    #|for i = 1, 6 do
    #|  values[i] = fact(i)
    #|  total = total + values[i]
    #|end
    #|
    #|local co = coroutine.create(function(a, b)
    #|  coroutine.yield(a + b)
    #|  return a * b
    #|end)
    #|
    #|local ok1, first = coroutine.resume(co, 7, 5)
    #|local ok2, second = coroutine.resume(co)
    #|if not ok1 or not ok2 then error("coroutine") end
    #|if table.concat({"a", "b", "c"}, ":") ~= "a:b:c" then error("table") end
    #|
    #|print("lua-matrix", total + first + second)
  script
}

///|
async fn assert_lua_language_matrix(lua_path : String, tag : String) -> Unit {
  let version = run_command_capture(
    shell_quote(lua_path) + " -v",
    "lua_external_version_" + tag,
  )
  if version.code != 0 || !version.output.contains("Lua 5.4.6") {
    abort(
      "Lua external version failed with code " +
      version.code.to_string() +
      ":\n" +
      version.output,
    )
  }
  let result = run_command_capture(
    shell_quote(lua_path) + " -e " + shell_quote(lua_language_matrix_script()),
    "lua_external_matrix_" + tag,
  )
  if result.code != 0 || !result.output.contains("lua-matrix\t920") {
    abort(
      "Lua external language matrix failed with code " +
      result.code.to_string() +
      ":\n" +
      result.output,
    )
  }
}

///|
async test "external Lua interpreter runs language matrix when enabled" {
  if !external_testbed_enabled("lua") {
    return
  }
  let root = "/tmp/kimicc_lua/lua-5.4.6"
  require_external_path(root + "/src/lua.c", "Lua source root")
  let lua_path = build_lua_with_kimicc(root, "matrix")
  assert_lua_language_matrix(lua_path, "matrix")
}

///|
async test "external Lua direct object interpreter runs language matrix when enabled" {
  if !external_testbed_enabled("lua") {
    return
  }
  let root = "/tmp/kimicc_lua/lua-5.4.6"
  require_external_path(root + "/src/lua.c", "Lua source root")
  let lua_path = build_lua_with_direct_object(root, "matrix")
  assert_lua_language_matrix(lua_path, "direct_matrix")
}
