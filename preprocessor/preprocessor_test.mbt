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
test "dump macros returns final macro table" {
  let source =
    #|#define LOCAL 7
    #|#define ADD(x, y) ((x) + (y))
    #|#define LOG(fmt, ...) fmt
    #|#undef __STDC__
  let text = match @preprocessor.dump_macros(source, test_options()) {
    Ok(text) => text
    Err(err) => abort(err.to_string())
  }
  assert_true(text.contains("#define ADD(x,y) ((x)+(y))\n"))
  assert_true(text.contains("#define LOCAL 7\n"))
  assert_true(text.contains("#define LOG(fmt,...) fmt\n"))
  assert_true(text.contains("#define __STDC_VERSION__ 201112L\n"))
  assert_true(!text.contains("#define __STDC__ 1\n"))
}

///|
test "undef predefined keeps only standard macro baseline" {
  let options : @preprocessor.PreprocessOptions = {
    ..test_options(),
    undef_predefined: true,
    allow_missing_includes: false,
  }
  let text = match @preprocessor.dump_macros("", options) {
    Ok(text) => text
    Err(err) => abort(err.to_string())
  }
  assert_true(text.contains("#define __STDC__ 1\n"))
  assert_true(text.contains("#define __STDC_VERSION__ 201112L\n"))
  assert_true(text.contains("#define __STDC_HOSTED__ 1\n"))
  assert_true(!text.contains("#define __GNUC__"))
  assert_true(!text.contains("#define __clang__"))
  assert_true(!text.contains("#define __clang_major__"))
  assert_true(!text.contains("#define __clang_literal_encoding__"))
  assert_true(!text.contains("#define __VERSION__"))
  assert_true(!text.contains("#define __LP64__"))
  assert_true(!text.contains("#define __BIGGEST_ALIGNMENT__"))
  assert_true(!text.contains("#define __SIG_ATOMIC_WIDTH__"))
  assert_true(!text.contains("#define __DATE__"))
  assert_true(!text.contains("#define __has_builtin"))
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
test "file prefix maps remap physical file macro names" {
  let options : @preprocessor.PreprocessOptions = {
    ..@preprocessor.PreprocessOptions::new("/work/project/main.c"),
    file_prefix_maps: [
      { from_prefix: "/work", to_prefix: "/mapped" },
      { from_prefix: "/work/project", to_prefix: "/src" },
    ],
  }
  let source =
    #|const char *main_file = __FILE__;
    #|#line 7 "/work/project/generated.h"
    #|const char *logical_file = __FILE__;
  match @preprocessor.preprocess(source, options) {
    Ok(text) =>
      inspect(
        text,
        content="const char*main_file=\"/src/main.c\";\nconst char*logical_file=\"/work/project/generated.h\";\n",
      )
    Err(err) => abort(err.to_string())
  }
}

///|
test "base file and include level follow physical include stack" {
  let options : @preprocessor.PreprocessOptions = {
    ..@preprocessor.PreprocessOptions::new("/work/project/main.c"),
    include_paths: ["preprocessor/testdata/include_level"],
    file_prefix_maps: [{ from_prefix: "/work/project", to_prefix: "/src" }],
  }
  let source =
    #|const char *main_base = __BASE_FILE__;
    #|const char *main_file = __FILE__;
    #|int main_level = __INCLUDE_LEVEL__;
    #|#include "level.h"
    #|#line 8 "/work/project/generated.h"
    #|const char *line_base = __BASE_FILE__;
    #|const char *line_file = __FILE__;
    #|int line_level = __INCLUDE_LEVEL__;
  match @preprocessor.preprocess(source, options) {
    Ok(text) =>
      inspect(
        text,
        content="const char*main_base=\"/src/main.c\";\nconst char*main_file=\"/src/main.c\";\nint main_level=0;\nconst char*header_base=\"/src/main.c\";\nconst char*header_file=\"preprocessor/testdata/include_level/level.h\";\nint header_level=1;\nconst char*line_base=\"/src/main.c\";\nconst char*line_file=\"/work/project/generated.h\";\nint line_level=0;\n",
      )
    Err(err) => abort(err.to_string())
  }
}

///|
test "file name macro uses basename without prefix maps" {
  let options : @preprocessor.PreprocessOptions = {
    ..@preprocessor.PreprocessOptions::new("/work/project/main.c"),
    include_paths: ["preprocessor/testdata/include_level"],
    file_prefix_maps: [
      { from_prefix: "/work/project/main.c", to_prefix: "/mapped/renamed.c" },
      { from_prefix: "/work/project", to_prefix: "/src" },
    ],
  }
  let source =
    #|const char *main_name = __FILE_NAME__;
    #|#include "name.h"
    #|#line 8 "/work/project/generated.h"
    #|const char *line_name = __FILE_NAME__;
  match @preprocessor.preprocess(source, options) {
    Ok(text) =>
      inspect(
        text,
        content="const char*main_name=\"main.c\";\nconst char*header_file_name=\"name.h\";\nconst char*line_name=\"generated.h\";\n",
      )
    Err(err) => abort(err.to_string())
  }
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
    file_prefix_maps: options.file_prefix_maps,
    defines: options.defines,
    undefines: options.undefines,
    undef_predefined: options.undef_predefined,
    allow_missing_includes: options.allow_missing_includes,
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
    file_prefix_maps: options.file_prefix_maps,
    defines: options.defines,
    undefines: options.undefines,
    undef_predefined: options.undef_predefined,
    allow_missing_includes: options.allow_missing_includes,
    emit_line_markers: options.emit_line_markers,
  }
  let source =
    #|#if defined(__gnu_linux__) && defined(__ELF__) && defined(_LP64) && defined(__code_model_small__)
    #|#if __SIZEOF_POINTER__ == 8 && __SIZEOF_LONG__ == 8 && __CHAR_BIT__ == 8
    #|#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__ && __FLOAT_WORD_ORDER__ == __ORDER_LITTLE_ENDIAN__ && __ORDER_PDP_ENDIAN__ == 3412
    #|#if __BIGGEST_ALIGNMENT__ == 16 && __SIZEOF_LONG_DOUBLE__ == 16
    #|#if __SIZE_MAX__ == 18446744073709551615UL && __UINTPTR_MAX__ == 18446744073709551615UL && __PTRDIFF_MAX__ == 9223372036854775807L
    #|#if __WCHAR_WIDTH__ == 32 && __WINT_WIDTH__ == 32 && __WINT_UNSIGNED__ == 1 && __SIG_ATOMIC_WIDTH__ == 32 && __SIG_ATOMIC_MAX__ == 2147483647
    #|#if __ATOMIC_SEQ_CST == 5 && __GCC_ATOMIC_POINTER_LOCK_FREE == 2
    #|int probes = 1;
    #|#else
    #|int probes = 2;
    #|#endif
    #|#endif
    #|#endif
    #|#endif
    #|#endif
    #|#endif
    #|#endif
    #|#if __FLT_EVAL_METHOD__ == 0 && __FLT_RADIX__ == 2 && __FLT_MANT_DIG__ == 24 && __DBL_MANT_DIG__ == 53 && __LDBL_MANT_DIG__ == 64 && __DECIMAL_DIG__ == 21
    #|int float_probes = 1;
    #|#else
    #|int float_probes = 2;
    #|#endif
    #|#if __INT64_MAX__ == 9223372036854775807L && __UINT64_MAX__ == 18446744073709551615UL
    #|int int64_probes = 1;
    #|#else
    #|int int64_probes = 2;
    #|#endif
    #|#if defined(__clang__) && __clang_major__ == 18 && __clang_minor__ == 1 && __clang_patchlevel__ == 3
    #|int clang_version_probes = 1;
    #|#else
    #|int clang_version_probes = 2;
    #|#endif
    #|#if __GXX_ABI_VERSION == 1002
    #|int abi_version_probes = 1;
    #|#else
    #|int abi_version_probes = 2;
    #|#endif
    #|#if __GCC_HAVE_SYNC_COMPARE_AND_SWAP_1 == 1 && __GCC_HAVE_SYNC_COMPARE_AND_SWAP_2 == 1 && __GCC_HAVE_SYNC_COMPARE_AND_SWAP_4 == 1 && __GCC_HAVE_SYNC_COMPARE_AND_SWAP_8 == 1
    #|int sync_compare_exchange_probes = 1;
    #|#else
    #|int sync_compare_exchange_probes = 2;
    #|#endif
    #|#if __GCC_CONSTRUCTIVE_SIZE == 64 && __GCC_DESTRUCTIVE_SIZE == 64 && __FPCLASS_QNAN == 0x0002 && __FPCLASS_POSINF == 0x0200 && __MEMORY_SCOPE_SYSTEM == 0 && __OPENCL_MEMORY_SCOPE_SUB_GROUP == 4
    #|int numeric_constant_probes = 1;
    #|#else
    #|int numeric_constant_probes = 2;
    #|#endif
    #|#if defined(__NO_MATH_INLINES) && __NO_MATH_INLINES == 1
    #|int math_inline_probes = 1;
    #|#else
    #|int math_inline_probes = 2;
    #|#endif
    #|#if __BOOL_WIDTH__ == 8 && __INT8_MAX__ == 127 && __INT_FAST64_WIDTH__ == 64 && __UINT_LEAST32_MAX__ == 4294967295U && __CLANG_ATOMIC_WCHAR_T_LOCK_FREE == 2
    #|int integer_introspection_probes = 1;
    #|#else
    #|int integer_introspection_probes = 2;
    #|#endif
    #|#define KIMICC_STRINGIFY_1(x) #x
    #|#define KIMICC_STRINGIFY(x) KIMICC_STRINGIFY_1(x)
    #|int prefix = __USER_LABEL_PREFIX__ 9;
    #|const char *clang_version = __clang_version__;
    #|const char *literal_encoding = __clang_literal_encoding__;
    #|const char *wide_literal_encoding = __clang_wide_literal_encoding__;
    #|const char *compiler_version = __VERSION__;
    #|const char *int64_format = __INT64_FMTd__;
    #|const char *uint64_format = __UINT64_FMTu__;
    #|const char *size_format = __SIZE_FMTu__;
    #|const char *int_fast64_format = __INT_FAST64_FMTi__;
    #|const char *uint_least16_format = __UINT_LEAST16_FMTx__;
    #|const char *int64_suffix = KIMICC_STRINGIFY(__INT64_C_SUFFIX__);
    #|const char *uint64_suffix = KIMICC_STRINGIFY(__UINT64_C_SUFFIX__);
    #|__SIG_ATOMIC_TYPE__ sig_atomic_value;
    #|__WINT_TYPE__ wint_value;
    #|__CHAR16_TYPE__ char16_value;
    #|__CHAR32_TYPE__ char32_value;
    #|__INT64_TYPE__ int64_value;
    #|__UINT64_TYPE__ uint64_value;
    #|__INT_LEAST64_TYPE__ least64_value;
    #|__UINT_FAST64_TYPE__ fast64_value;
  match @preprocessor.preprocess(source, linux_options) {
    Ok(text) =>
      inspect(
        text,
        content=(
          #|int probes=1;
          #|int float_probes=1;
          #|int int64_probes=1;
          #|int clang_version_probes=1;
          #|int abi_version_probes=1;
          #|int sync_compare_exchange_probes=1;
          #|int numeric_constant_probes=1;
          #|int math_inline_probes=1;
          #|int integer_introspection_probes=1;
          #|int prefix=9;
          #|const char*clang_version="kimicc clang-compatible preprocessor";
          #|const char*literal_encoding="UTF-8";
          #|const char*wide_literal_encoding="UTF-32";
          #|const char*compiler_version="kimicc";
          #|const char*int64_format="ld";
          #|const char*uint64_format="lu";
          #|const char*size_format="lu";
          #|const char*int_fast64_format="li";
          #|const char*uint_least16_format="hx";
          #|const char*int64_suffix="L";
          #|const char*uint64_suffix="UL";
          #|int sig_atomic_value;
          #|unsigned int wint_value;
          #|unsigned short char16_value;
          #|unsigned int char32_value;
          #|long int int64_value;
          #|long unsigned int uint64_value;
          #|long int least64_value;
          #|long unsigned int fast64_value;
          #|
        ),
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
    file_prefix_maps: options.file_prefix_maps,
    defines: options.defines,
    undefines: options.undefines,
    undef_predefined: options.undef_predefined,
    allow_missing_includes: options.allow_missing_includes,
    emit_line_markers: options.emit_line_markers,
  }
  let source =
    #|#if __has_builtin(__builtin_memcpy) && __has_builtin(__builtin_return_address) && __has_builtin(__builtin_dynamic_object_size)
    #|int memory_and_return_address = 1;
    #|#else
    #|int memory_and_return_address = 0;
    #|#endif
    #|#if __has_builtin(__builtin_mempcpy) && __has_builtin(__builtin___mempcpy_chk) && __has_builtin(__builtin_stpcpy) && __has_builtin(__builtin___stpncpy_chk)
    #|int gnu_copy_builtins = 1;
    #|#else
    #|int gnu_copy_builtins = 0;
    #|#endif
    #|#if __has_builtin(__atomic_load_n) && __has_builtin(__builtin_add_overflow) && __has_builtin(__sync_bool_compare_and_swap) && __has_builtin(__sync_val_compare_and_swap)
    #|int atomic_and_overflow = 1;
    #|#else
    #|int atomic_and_overflow = 0;
    #|#endif
    #|#if __has_builtin(__sync_fetch_and_add) && __has_builtin(__sync_add_and_fetch) && __has_builtin(__sync_fetch_and_nand) && __has_builtin(__sync_nand_and_fetch) && __has_builtin(__sync_fetch_and_max) && __has_builtin(__sync_fetch_and_min) && __has_builtin(__sync_fetch_and_umax) && __has_builtin(__sync_fetch_and_umin) && __has_builtin(__sync_lock_test_and_set) && __has_builtin(__sync_lock_release) && __has_builtin(__sync_swap)
    #|int sync_update_builtins = 1;
    #|#else
    #|int sync_update_builtins = 0;
    #|#endif
    #|#if __has_builtin(__builtin_choose_expr) && __has_builtin(__builtin_types_compatible_p) && __has_builtin(__builtin_classify_type)
    #|int compile_time_selection = 1;
    #|#else
    #|int compile_time_selection = 0;
    #|#endif
    #|#if __has_builtin(__builtin_flt_rounds)
    #|int floating_environment_query = 1;
    #|#else
    #|int floating_environment_query = 0;
    #|#endif
    #|#if __has_builtin(__builtin_unpredictable)
    #|int unpredictable_hint = 1;
    #|#else
    #|int unpredictable_hint = 0;
    #|#endif
    #|#if __has_builtin(__builtin_is_aligned) && __has_builtin(__builtin_align_up) && __has_builtin(__builtin_align_down)
    #|int alignment_builtins = 1;
    #|#else
    #|int alignment_builtins = 0;
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
        content="int memory_and_return_address=1;\nint gnu_copy_builtins=1;\nint atomic_and_overflow=1;\nint sync_update_builtins=1;\nint compile_time_selection=1;\nint floating_environment_query=1;\nint unpredictable_hint=1;\nint alignment_builtins=1;\nint unsupported=0;\n",
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
    file_prefix_maps: options.file_prefix_maps,
    defines: options.defines,
    undefines: options.undefines,
    undef_predefined: options.undef_predefined,
    allow_missing_includes: options.allow_missing_includes,
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
    #|#if __has_attribute(mode) && __has_attribute(__mode__)
    #|int mode_attr = 1;
    #|#else
    #|int mode_attr = 0;
    #|#endif
    #|#if __has_attribute(weak) && __has_attribute(__weak__)
    #|int weak_attr = 1;
    #|#else
    #|int weak_attr = 0;
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
    #|#if __has_attribute(noreturn) && __has_attribute(__noreturn__) && __has_attribute(noinline) && __has_attribute(__always_inline__)
    #|int function_hint_attrs = 1;
    #|#else
    #|int function_hint_attrs = 0;
    #|#endif
    #|#if __has_attribute(format) && __has_attribute(__format__) && __has_attribute(nonnull) && __has_attribute(warn_unused_result)
    #|int diagnostic_attrs = 1;
    #|#else
    #|int diagnostic_attrs = 0;
    #|#endif
    #|#if __has_attribute(malloc) && __has_attribute(alloc_size) && __has_attribute(alloc_align)
    #|int allocation_attrs = 1;
    #|#else
    #|int allocation_attrs = 0;
    #|#endif
    #|#if __has_attribute(no_sanitize_thread) && __has_attribute(__no_sanitize_address__)
    #|int sanitizer_attrs = 1;
    #|#else
    #|int sanitizer_attrs = 0;
    #|#endif
    #|#if __has_attribute(vector_size) || __has_attribute(__vector_size__) || __has_attribute(ext_vector_type) || __has_attribute(__ext_vector_type__)
    #|int unsupported_type_attrs = 1;
    #|#else
    #|int unsupported_type_attrs = 0;
    #|#endif
  match @preprocessor.preprocess(source, linux_options) {
    Ok(text) =>
      inspect(
        text,
        content="int packed_attr=1;\nint aligned_attr=1;\nint mode_attr=1;\nint weak_attr=1;\nint unused_attr=1;\nint fallthrough_attr=1;\nint function_hint_attrs=1;\nint diagnostic_attrs=1;\nint allocation_attrs=1;\nint sanitizer_attrs=1;\nint unsupported_type_attrs=0;\n",
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
    #|#if !__is_identifier(_Static_assert) && !__is_identifier(__int128) && !__is_identifier(_Generic) && !__is_identifier(__typeof__) && !__is_identifier(__auto_type) && !__is_identifier(_Float16) && !__is_identifier(__float128) && !__is_identifier(_Float128) && !__is_identifier(_BitInt) && !__is_identifier(_Complex) && !__is_identifier(__complex__) && !__is_identifier(_Alignof) && !__is_identifier(__alignof__)
    #|int extensions = 1;
    #|#else
    #|int extensions = 0;
    #|#endif
    #|#if !__is_identifier(_Float32) && !__is_identifier(_Float64) && !__is_identifier(_Float32x) && !__is_identifier(_Float64x)
    #|int binary_float_extensions = 1;
    #|#else
    #|int binary_float_extensions = 0;
    #|#endif
    #|#if !__is_identifier(_Decimal32) && !__is_identifier(_Decimal64) && !__is_identifier(_Decimal128) && !__is_identifier(__bf16) && !__is_identifier(__ibm128)
    #|int unsupported_float_extensions = 1;
    #|#else
    #|int unsupported_float_extensions = 0;
    #|#endif
  let text = expect_preprocess(source)
  inspect(
    text,
    content="int c_keywords=1;\nint extensions=1;\nint binary_float_extensions=1;\nint unsupported_float_extensions=1;\n",
  )
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
    file_prefix_maps: [],
    defines: {},
    undefines: [],
    undef_predefined: false,
    allow_missing_includes: false,
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
test "literal angle includes ignore macros in path components" {
  let options : @preprocessor.PreprocessOptions = {
    filename: "input.c",
    target: @target.Target::default(),
    include_paths: [],
    system_include_paths: ["preprocessor/testdata/system_path"],
    file_prefix_maps: [],
    defines: {},
    undefines: [],
    undef_predefined: false,
    allow_missing_includes: false,
    emit_line_markers: false,
  }
  let source =
    #|#define bits 1
    #|#include <bits/errno.h>
    #|#if __has_include(<bits/errno.h>)
    #|int literal_bits_probe = 1;
    #|#else
    #|int literal_bits_probe = 0;
    #|#endif
  match @preprocessor.preprocess(source, options) {
    Ok(text) =>
      inspect(
        text,
        content="int literal_bits_errno=7;\nint literal_bits_probe=1;\n",
      )
    Err(err) => fail(err.to_string())
  }
}

///|
test "missing generated includes can be recorded for dependencies" {
  let options : @preprocessor.PreprocessOptions = {
    filename: "input.c",
    target: @target.Target::default(),
    include_paths: [],
    system_include_paths: [],
    file_prefix_maps: [],
    defines: {},
    undefines: [],
    undef_predefined: false,
    allow_missing_includes: true,
    emit_line_markers: false,
  }
  let source =
    #|#include "generated/config.h"
    #|#include <generated/system.h>
    #|int body = 1;
  match @preprocessor.preprocess_with_dependencies(source, options) {
    Ok(result) => {
      inspect(result.text, content="int body=1;\n")
      let mut saw_quote = false
      let mut saw_angle = false
      for dep in result.dependency_records {
        if dep.path == "generated/config.h" && !dep.system {
          saw_quote = true
        } else if dep.path == "generated/system.h" && !dep.system {
          saw_angle = true
        }
      }
      assert_true(saw_quote)
      assert_true(saw_angle)
    }
    Err(err) => fail(err.to_string())
  }
}

///|
test "missing include without generated mode remains an error" {
  match
    @preprocessor.preprocess(
      "#include \"missing/generated.h\"\n",
      test_options(),
    ) {
    Ok(_) => fail("expected missing include to fail")
    Err(err) =>
      assert_eq(err.to_string(), "include file not found: missing/generated.h")
  }
}

///|
test "preprocess with dependencies records resolved includes" {
  let options : @preprocessor.PreprocessOptions = {
    filename: "preprocessor/testdata/input.c",
    target: @target.Target::default(),
    include_paths: ["preprocessor/testdata/include_path"],
    system_include_paths: ["preprocessor/testdata/system_path"],
    file_prefix_maps: [],
    defines: {},
    undefines: [],
    undef_predefined: false,
    allow_missing_includes: false,
    emit_line_markers: false,
  }
  let source =
    #|#include "local_header.h"
    #|#include "path_header.h"
    #|#include <system_header.h>
    #|int main(void) { return HEADER_ADD(PATH_VALUE, SYSTEM_VALUE); }
  match @preprocessor.preprocess_with_dependencies(source, options) {
    Ok(result) => {
      inspect(result.text, content="int main(void){return((9)+(11));}\n")
      let mut saw_main = false
      let mut saw_local = false
      let mut saw_quote_path = false
      let mut saw_system = false
      for dep in result.dependency_records {
        if dep.path == "preprocessor/testdata/input.c" {
          saw_main = true
          assert_true(!dep.system)
        } else if dep.path == "preprocessor/testdata/local_header.h" {
          saw_local = true
          assert_true(!dep.system)
        } else if dep.path == "preprocessor/testdata/include_path/path_header.h" {
          saw_quote_path = true
          assert_true(!dep.system)
        } else if dep.path ==
          "preprocessor/testdata/system_path/system_header.h" {
          saw_system = true
          assert_true(dep.system)
        }
      }
      assert_true(saw_main)
      assert_true(saw_local)
      assert_true(saw_quote_path)
      assert_true(saw_system)
    }
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
    file_prefix_maps: [],
    defines: {},
    undefines: [],
    undef_predefined: false,
    allow_missing_includes: false,
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
    file_prefix_maps: [],
    defines: {},
    undefines: [],
    undef_predefined: false,
    allow_missing_includes: false,
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
    file_prefix_maps: [],
    defines: {},
    undefines: [],
    undef_predefined: false,
    allow_missing_includes: false,
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
    file_prefix_maps: [],
    defines: {},
    undefines: [],
    undef_predefined: false,
    allow_missing_includes: false,
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
    file_prefix_maps: [],
    defines: {},
    undefines: [],
    undef_predefined: false,
    allow_missing_includes: false,
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
