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
async fn compile_preprocessed_file_with_kimicc_object_path(
  path : String,
  tag : String,
) -> String {
  require_external_path(path, "preprocessed C testbed")
  let data = @fs.read_file(path)
  compile_source_to_object_path(data.text(), tag)
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
  let smoke_source =
    #|int fib(int n) {
    #|  return n < 2 ? n : fib(n - 1) + fib(n - 2);
    #|}
    #|
    #|int main(void) {
    #|  return fib(10) == 55 ? 42 : 1;
    #|}
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
