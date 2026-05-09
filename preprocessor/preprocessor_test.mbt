///|
fn test_options() -> @preprocessor.PreprocessOptions {
  @preprocessor.PreprocessOptions::new("preprocessor/testdata/input.c")
}

///|
fn expect_preprocess(source : String) -> String {
  match @preprocessor.preprocess(source, test_options()) {
    Ok(text) => text
    Err(err) => abort(err.to_string())
  }
}

///|
test "object-like and function-like macros expand" {
  let source =
    #|#define ANSWER 42
    #|#define ADD(x, y) ((x) + (y))
    #|int main(void) { return ADD(ANSWER, 1); }
  let text = expect_preprocess(source)
  inspect(text, content="int main(void){return((42)+(1));}\n")
}

///|
test "conditionals select active branch" {
  let source =
    #|#define ENABLED 1
    #|#if defined(ENABLED) && ENABLED
    #|int value(void) { return 7; }
    #|#else
    #|int value(void) { return 0; }
    #|#endif
  let text = expect_preprocess(source)
  inspect(text, content="int value(void){return 7;}\n")
}

///|
test "stringizing and token paste" {
  let source =
    #|#define STR(x) #x
    #|#define CAT(a, b) a ## b
    #|const char *name = STR(alpha beta);
    #|int CAT(fo, o)(void) { return 3; }
  let text = expect_preprocess(source)
  inspect(
    text,
    content="const char*name=\"alpha beta\";\nint foo(void){return 3;}\n",
  )
}

///|
test "variadic macros bind all remaining arguments" {
  let source =
    #|#define CALL(fn, ...) fn(__VA_ARGS__)
    #|int value = CALL(add3, 1, 2, 3);
  let text = expect_preprocess(source)
  inspect(text, content="int value=add3(1,2,3);\n")
}

///|
test "gnu variadic comma paste drops empty varargs comma" {
  let source =
    #|#define LOG(fmt, ...) log(fmt, ## __VA_ARGS__)
    #|LOG("only")
    #|LOG("pair", 1, 2)
  let text = expect_preprocess(source)
  inspect(text, content="log(\"only\")\nlog(\"pair\",1,2)\n")
}

///|
test "nested macro argument expansion preserves outer disabled names" {
  let source =
    #|#define GLOBAL(t, v) v
    #|#define vfsList GLOBAL(sqlite3_vfs *, vfsList)
    #|int *p = vfsList;
  let text = expect_preprocess(source)
  inspect(text, content="int*p=vfsList;\n")
}

///|
test "_Pragma operator is consumed during preprocessing" {
  let source =
    #|#define PUSH _Pragma("clang diagnostic push")
    #|PUSH
    #|int value = 1;
  let text = expect_preprocess(source)
  inspect(text, content="\nint value=1;\n")
}

///|
test "quote include searches including directory" {
  let source =
    #|#include "local_header.h"
    #|int main(void) { return HEADER_ADD(HEADER_VALUE, 25); }
  let text = expect_preprocess(source)
  inspect(text, content="int main(void){return((17)+(25));}\n")
}

///|
test "include paths are explicit" {
  let options : @preprocessor.PreprocessOptions = {
    filename: "input.c",
    include_paths: ["preprocessor/testdata/include_path"],
    system_include_paths: ["preprocessor/testdata/system_path"],
    defines: {},
    undefines: [],
    emit_line_markers: false,
  }
  let source =
    #|#include "path_header.h"
    #|#include <system_header.h>
    #|int main(void) { return PATH_VALUE + SYSTEM_VALUE; }
  match @preprocessor.preprocess(source, options) {
    Ok(text) => inspect(text, content="int main(void){return 9+11;}\n")
    Err(err) => fail(err.to_string())
  }
}

///|
test "preprocess parse convenience keeps parser separate" {
  let source =
    #|#define RET 42
    #|int main(void) { return RET; }
  match @preprocessor.parse(source, test_options()) {
    Ok(program) => {
      inspect(program.decls.length(), content="1")
      inspect(program.decls[0].name, content="main")
    }
    Err(err) => fail(err.to_string())
  }
}
