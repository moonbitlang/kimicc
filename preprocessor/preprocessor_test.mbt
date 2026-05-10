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
test "elifdef and elifndef select active branch" {
  let source =
    #|#define ENABLED 1
    #|#if 0
    #|int enabled = 0;
    #|#elifdef ENABLED
    #|int enabled = 1;
    #|#else
    #|int enabled = 2;
    #|#endif
    #|#if 0
    #|int missing = 0;
    #|#elifndef MISSING
    #|int missing = 1;
    #|#else
    #|int missing = 2;
    #|#endif
  let text = expect_preprocess(source)
  inspect(text, content="int enabled=1;\nint missing=1;\n")
}

///|
test "counter macro increments per expansion" {
  let source =
    #|#define TAKE(x) x
    #|int a = __COUNTER__;
    #|int b = TAKE(__COUNTER__);
    #|#if __COUNTER__ == 2
    #|int c = __COUNTER__;
    #|#else
    #|int c = 99;
    #|#endif
  let text = expect_preprocess(source)
  inspect(text, content="int a=0;\nint b=1;\nint c=3;\n")
}

///|
test "line directive updates logical file and line macros" {
  let source =
    #|#line 100 "virtual.c"
    #|int first = __LINE__;
    #|const char *file = __FILE__;
    #|#line 7
    #|int second = __LINE__;
  let text = expect_preprocess(source)
  inspect(
    text,
    content="int first=100;\nconst char*file=\"virtual.c\";\nint second=7;\n",
  )
}

///|
test "line directive expands macro arguments" {
  let source =
    #|#define LINE_VALUE 23
    #|#define FILE_VALUE "macro-line.c"
    #|#line LINE_VALUE FILE_VALUE
    #|int line_value = __LINE__;
    #|const char *file_value = __FILE__;
  let text = expect_preprocess(source)
  inspect(
    text,
    content="int line_value=23;\nconst char*file_value=\"macro-line.c\";\n",
  )
}

///|
test "gcc line marker updates logical file and line macros" {
  let source =
    #|# 42 "marker.c" 1 3
    #|int marker_line = __LINE__;
    #|const char *marker_file = __FILE__;
  let text = expect_preprocess(source)
  inspect(
    text,
    content="int marker_line=42;\nconst char*marker_file=\"marker.c\";\n",
  )
}

///|
test "target macros follow selected target" {
  let linux = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("linux target did not parse")
  }
  let options = @preprocessor.PreprocessOptions::new("input.c")
  let linux_options : @preprocessor.PreprocessOptions = {
    filename: options.filename,
    target: linux,
    include_paths: options.include_paths,
    system_include_paths: options.system_include_paths,
    defines: options.defines,
    undefines: options.undefines,
    emit_line_markers: options.emit_line_markers,
  }
  let source =
    #|#if defined(__linux__) && defined(__x86_64__) && !defined(__APPLE__)
    #|int target_value = 64;
    #|#else
    #|int target_value = 0;
    #|#endif
  match @preprocessor.preprocess(source, linux_options) {
    Ok(text) => inspect(text, content="int target_value=64;\n")
    Err(err) => fail(err.to_string())
  }
}

///|
test "linux amd64 predefined macros cover system header probes" {
  let linux = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("linux target did not parse")
  }
  let options = @preprocessor.PreprocessOptions::new("input.c")
  let linux_options : @preprocessor.PreprocessOptions = {
    filename: options.filename,
    target: linux,
    include_paths: options.include_paths,
    system_include_paths: options.system_include_paths,
    defines: options.defines,
    undefines: options.undefines,
    emit_line_markers: options.emit_line_markers,
  }
  let source =
    #|#if defined(__gnu_linux__) && defined(__ELF__) && defined(_LP64)
    #|#if __SIZEOF_POINTER__ == 8 && __SIZEOF_LONG__ == 8 && __CHAR_BIT__ == 8
    #|#if __ATOMIC_SEQ_CST == 5 && __GCC_ATOMIC_POINTER_LOCK_FREE == 2
    #|int probes = 1;
    #|#else
    #|int probes = 2;
    #|#endif
    #|#endif
    #|#endif
    #|int prefix = __USER_LABEL_PREFIX__ 9;
    #|__WINT_TYPE__ wint_value;
  match @preprocessor.preprocess(source, linux_options) {
    Ok(text) =>
      inspect(
        text,
        content="int probes=1;\nint prefix=9;\nunsigned int wint_value;\n",
      )
    Err(err) => fail(err.to_string())
  }
}

///|
test "linux amd64 has builtin reflects supported lowering" {
  let linux = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("linux target did not parse")
  }
  let options = @preprocessor.PreprocessOptions::new("input.c")
  let linux_options : @preprocessor.PreprocessOptions = {
    filename: options.filename,
    target: linux,
    include_paths: options.include_paths,
    system_include_paths: options.system_include_paths,
    defines: options.defines,
    undefines: options.undefines,
    emit_line_markers: options.emit_line_markers,
  }
  let source =
    #|#if __has_builtin(__builtin_memcpy) && __has_builtin(__builtin_return_address)
    #|int memory_and_return_address = 1;
    #|#else
    #|int memory_and_return_address = 0;
    #|#endif
    #|#if __has_builtin(__atomic_load_n) && __has_builtin(__builtin_add_overflow)
    #|int atomic_and_overflow = 1;
    #|#else
    #|int atomic_and_overflow = 0;
    #|#endif
    #|#if __has_builtin(__builtin_choose_expr) && __has_builtin(__builtin_types_compatible_p) && __has_builtin(__builtin_classify_type)
    #|int compile_time_selection = 1;
    #|#else
    #|int compile_time_selection = 0;
    #|#endif
    #|#if __has_builtin(__builtin_unsupported_vector_thing)
    #|int unsupported = 1;
    #|#else
    #|int unsupported = 0;
    #|#endif
  match @preprocessor.preprocess(source, linux_options) {
    Ok(text) =>
      inspect(
        text,
        content="int memory_and_return_address=1;\nint atomic_and_overflow=1;\nint compile_time_selection=1;\nint unsupported=0;\n",
      )
    Err(err) => fail(err.to_string())
  }
}

///|
test "has attribute reflects supported packed layout" {
  let linux = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("linux target did not parse")
  }
  let options = @preprocessor.PreprocessOptions::new("input.c")
  let linux_options : @preprocessor.PreprocessOptions = {
    filename: options.filename,
    target: linux,
    include_paths: options.include_paths,
    system_include_paths: options.system_include_paths,
    defines: options.defines,
    undefines: options.undefines,
    emit_line_markers: options.emit_line_markers,
  }
  let source =
    #|#if __has_attribute(packed) && __has_attribute(__packed__)
    #|int packed_attr = 1;
    #|#else
    #|int packed_attr = 0;
    #|#endif
    #|#if __has_attribute(aligned) && __has_attribute(__aligned__)
    #|int aligned_attr = 1;
    #|#else
    #|int aligned_attr = 0;
    #|#endif
    #|#if __has_attribute(unused) && __has_attribute(__unused__)
    #|int unused_attr = 1;
    #|#else
    #|int unused_attr = 0;
    #|#endif
    #|#if __has_attribute(fallthrough) && __has_attribute(__fallthrough__)
    #|int fallthrough_attr = 1;
    #|#else
    #|int fallthrough_attr = 0;
    #|#endif
  match @preprocessor.preprocess(source, linux_options) {
    Ok(text) =>
      inspect(
        text,
        content="int packed_attr=1;\nint aligned_attr=1;\nint unused_attr=1;\nint fallthrough_attr=1;\n",
      )
    Err(err) => fail(err.to_string())
  }
}

///|
test "clang feature probes are conservative" {
  let source =
    #|#if __has_feature(c_static_assert) && __has_extension(c_alignas) && __has_feature(c_alignof)
    #|int core_features = 1;
    #|#else
    #|int core_features = 0;
    #|#endif
    #|#if __has_feature(c_atomic)
    #|int atomic_feature = 1;
    #|#else
    #|int atomic_feature = 0;
    #|#endif
    #|#if __has_feature(c_generic_selections)
    #|int generic_feature = 1;
    #|#else
    #|int generic_feature = 0;
    #|#endif
    #|#if __has_c_attribute(deprecated) || __has_declspec_attribute(dllexport) || __has_warning("-Wunknown")
    #|int unsupported_probe = 1;
    #|#else
    #|int unsupported_probe = 0;
    #|#endif
  let text = expect_preprocess(source)
  inspect(
    text,
    content="int core_features=1;\nint atomic_feature=1;\nint generic_feature=1;\nint unsupported_probe=0;\n",
  )
}

///|
test "is identifier reflects parser keywords and extensions" {
  let source =
    #|#if __is_identifier(custom_name) && !__is_identifier(int)
    #|int c_keywords = 1;
    #|#else
    #|int c_keywords = 0;
    #|#endif
    #|#if !__is_identifier(_Static_assert) && !__is_identifier(__int128) && !__is_identifier(_Generic) && !__is_identifier(__typeof__) && !__is_identifier(__auto_type) && !__is_identifier(_Alignof) && !__is_identifier(__alignof__)
    #|int extensions = 1;
    #|#else
    #|int extensions = 0;
    #|#endif
  let text = expect_preprocess(source)
  inspect(text, content="int c_keywords=1;\nint extensions=1;\n")
}

///|
test "ident directive is ignored" {
  let source =
    #|#ident "kimicc test"
    #|int value = 1;
  let text = expect_preprocess(source)
  inspect(text, content="int value=1;\n")
}

///|
test "darwin arm64 has builtin remains conservative" {
  let source =
    #|#if __has_builtin(__builtin_memcpy)
    #|int has_memcpy = 1;
    #|#else
    #|int has_memcpy = 0;
    #|#endif
  let text = expect_preprocess(source)
  inspect(text, content="int has_memcpy=0;\n")
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
test "va opt expands only when variadic arguments are present" {
  let source =
    #|#define CALL(fn, ...) fn(0 __VA_OPT__(,) __VA_ARGS__)
    #|CALL(single)
    #|CALL(pair, 1, 2)
  let text = expect_preprocess(source)
  inspect(text, content="single(0)\npair(0,1,2)\n")
}

///|
test "va opt supports named variadic macros and parameter substitution" {
  let source =
    #|#define SUM(base, rest...) (base __VA_OPT__(+ rest))
    #|int a = SUM(7);
    #|int b = SUM(7, 5);
  let text = expect_preprocess(source)
  inspect(text, content="int a=(7);\nint b=(7+5);\n")
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
test "function-like macro invocation may span newline before paren" {
  let source =
    #|#define AVAIL(...)
    #|enum { VALUE AVAIL
    #|(macos(10.14)) = 7 };
  let text = expect_preprocess(source)
  inspect(text, content="enum{VALUE=7};\n")
}

///|
test "prefixed character and string literals stay single tokens" {
  let source =
    #|int ch = L'a';
    #|const char *s = u8"ok";
  let text = expect_preprocess(source)
  inspect(text, content="int ch=L'a';\nconst char*s=u8\"ok\";\n")
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
    target: @target.Target::default(),
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
test "has include follows quote and system include search" {
  let options : @preprocessor.PreprocessOptions = {
    filename: "preprocessor/testdata/input.c",
    target: @target.Target::default(),
    include_paths: ["preprocessor/testdata/include_path"],
    system_include_paths: ["preprocessor/testdata/system_path"],
    defines: {},
    undefines: [],
    emit_line_markers: false,
  }
  let source =
    #|#define SYSTEM_HEADER <system_header.h>
    #|#if __has_include("local_header.h")
    #|int local_probe = 1;
    #|#else
    #|int local_probe = 0;
    #|#endif
    #|#if __has_include(SYSTEM_HEADER)
    #|int system_probe = 1;
    #|#else
    #|int system_probe = 0;
    #|#endif
    #|#if __has_include("missing_header.h")
    #|int missing_probe = 1;
    #|#else
    #|int missing_probe = 0;
    #|#endif
  match @preprocessor.preprocess(source, options) {
    Ok(text) =>
      inspect(
        text,
        content="int local_probe=1;\nint system_probe=1;\nint missing_probe=0;\n",
      )
    Err(err) => fail(err.to_string())
  }
}

///|
test "has include next resumes after current include directory" {
  let options : @preprocessor.PreprocessOptions = {
    filename: "preprocessor/testdata/next_first/input.c",
    target: @target.Target::default(),
    include_paths: [],
    system_include_paths: [
      "preprocessor/testdata/next_first", "preprocessor/testdata/next_second",
    ],
    defines: {},
    undefines: [],
    emit_line_markers: false,
  }
  let source =
    #|#if __has_include_next(<next_value.h>)
    #|int next_probe = 1;
    #|#else
    #|int next_probe = 0;
    #|#endif
    #|#if __has_include_next(<missing_next.h>)
    #|int missing_next = 1;
    #|#else
    #|int missing_next = 0;
    #|#endif
  match @preprocessor.preprocess(source, options) {
    Ok(text) =>
      inspect(text, content="int next_probe=1;\nint missing_next=0;\n")
    Err(err) => fail(err.to_string())
  }
}

///|
test "include_next resumes after current include directory" {
  let options : @preprocessor.PreprocessOptions = {
    filename: "input.c",
    target: @target.Target::default(),
    include_paths: [],
    system_include_paths: [
      "preprocessor/testdata/next_first", "preprocessor/testdata/next_second",
    ],
    defines: {},
    undefines: [],
    emit_line_markers: false,
  }
  let source =
    #|#include <next_value.h>
    #|int value = NEXT_VALUE;
  match @preprocessor.preprocess(source, options) {
    Ok(text) => inspect(text, content="int value=123;\n")
    Err(err) => fail(err.to_string())
  }
}

///|
test "pragma once skips repeated include" {
  let options : @preprocessor.PreprocessOptions = {
    filename: "input.c",
    target: @target.Target::default(),
    include_paths: ["preprocessor/testdata/pragma_once"],
    system_include_paths: [],
    defines: {},
    undefines: [],
    emit_line_markers: false,
  }
  let source =
    #|#include "once.h"
    #|#include "once.h"
    #|int use_once = PRAGMA_ONCE_VALUE;
  match @preprocessor.preprocess(source, options) {
    Ok(text) => inspect(text, content="int once_value=19;\nint use_once=19;\n")
    Err(err) => fail(err.to_string())
  }
}

///|
test "guarded recursive include is ignored" {
  let options : @preprocessor.PreprocessOptions = {
    filename: "input.c",
    target: @target.Target::default(),
    include_paths: ["preprocessor/testdata/self_guard"],
    system_include_paths: [],
    defines: {},
    undefines: [],
    emit_line_markers: false,
  }
  let source =
    #|#include "self.h"
    #|int value = SELF_GUARD_VALUE;
  match @preprocessor.preprocess(source, options) {
    Ok(text) => inspect(text, content="int value=77;\n")
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
