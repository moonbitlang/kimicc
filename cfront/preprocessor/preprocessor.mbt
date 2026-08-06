///|
fn Preprocessor::set_error(self : Preprocessor, message : String) -> Unit {
  if self.error is None {
    self.error = Some(Message(message))
  }
}

///|
fn Preprocessor::record_dependency(
  self : Preprocessor,
  path : String,
  system : Bool,
) -> Unit {
  if !self.dependency_seen.contains(path) {
    self.dependency_seen[path] = true
    self.dependencies.push(path)
    self.dependency_records.push({ path, system })
  }
}

///|
fn Preprocessor::is_active(
  _self : Preprocessor,
  stack : Array[ConditionalFrame],
) -> Bool {
  match stack.last() {
    Some(frame) => frame.branch_active
    None => true
  }
}

///|
fn Preprocessor::seed_macro(
  self : Preprocessor,
  name : String,
  replacement : String,
) -> Unit {
  self.macros[name] = {
    function_like: false,
    variadic: false,
    params: [],
    replacement: pp_without_whitespace(pp_tokenize(replacement)),
  }
}

///|
fn Preprocessor::seed_macro_definition(
  self : Preprocessor,
  definition : String,
) -> Unit {
  self.define_macro(pp_tokenize(definition))
}

///|
fn pp_is_function_like_define_name(name : String) -> Bool {
  for ch in name {
    if ch == '(' {
      return true
    }
  }
  false
}

///|
fn Preprocessor::seed_command_line_macro(
  self : Preprocessor,
  name : String,
  replacement : String,
) -> Unit {
  if pp_is_function_like_define_name(name) {
    self.seed_macro_definition(name + " " + replacement)
  } else {
    self.seed_macro(name, replacement)
  }
}

///|
fn Preprocessor::seed_standard_macros(self : Preprocessor) -> Unit {
  self.seed_macro("__STDC__", "1")
  self.seed_macro("__STDC_VERSION__", "201112L")
  self.seed_macro("__STDC_HOSTED__", "1")
  self.seed_macro("__STDC_UTF_16__", "1")
  self.seed_macro("__STDC_UTF_32__", "1")
}

///|
fn Preprocessor::seed_common_target_macros(self : Preprocessor) -> Unit {
  self.seed_standard_macros()
  self.seed_macro("__GNUC__", "4")
  self.seed_macro("__GNUC_MINOR__", "2")
  self.seed_macro("__GNUC_PATCHLEVEL__", "1")
  self.seed_macro("__clang__", "1")
  self.seed_macro("__clang_major__", "18")
  self.seed_macro("__clang_minor__", "1")
  self.seed_macro("__clang_patchlevel__", "3")
  self.seed_macro(
    "__clang_version__",
    pp_quote_string("kimicc clang-compatible preprocessor"),
  )
  self.seed_macro("__clang_literal_encoding__", pp_quote_string("UTF-8"))
  self.seed_macro("__clang_wide_literal_encoding__", pp_quote_string("UTF-32"))
  self.seed_macro("__VERSION__", pp_quote_string("kimicc"))
  self.seed_macro("__LP64__", "1")
  self.seed_macro("_LP64", "1")
  self.seed_macro("__ORDER_LITTLE_ENDIAN__", "1234")
  self.seed_macro("__ORDER_BIG_ENDIAN__", "4321")
  self.seed_macro("__ORDER_PDP_ENDIAN__", "3412")
  self.seed_macro("__BYTE_ORDER__", "__ORDER_LITTLE_ENDIAN__")
  self.seed_macro("__FLOAT_WORD_ORDER__", "__ORDER_LITTLE_ENDIAN__")
  self.seed_macro("__LITTLE_ENDIAN__", "1")
  self.seed_macro("__CHAR_BIT__", "8")
  self.seed_macro("__SCHAR_MAX__", "127")
  self.seed_macro("__SHRT_MAX__", "32767")
  self.seed_macro("__INT_MAX__", "2147483647")
  self.seed_macro("__LONG_MAX__", "9223372036854775807L")
  self.seed_macro("__LONG_LONG_MAX__", "9223372036854775807LL")
  self.seed_macro("__SIZEOF_SHORT__", "2")
  self.seed_macro("__SIZEOF_INT__", "4")
  self.seed_macro("__SIZEOF_LONG__", "8")
  self.seed_macro("__SIZEOF_LONG_LONG__", "8")
  self.seed_macro("__SIZEOF_FLOAT__", "4")
  self.seed_macro("__SIZEOF_DOUBLE__", "8")
  self.seed_macro("__SIZEOF_POINTER__", "8")
  self.seed_macro("__SIZEOF_SIZE_T__", "8")
  self.seed_macro("__SIZEOF_PTRDIFF_T__", "8")
  self.seed_macro("__SIZEOF_INT128__", "16")
  self.seed_macro("__SIZEOF_WCHAR_T__", "4")
  self.seed_macro("__SIZEOF_WINT_T__", "4")
  self.seed_macro("__BIGGEST_ALIGNMENT__", "16")
  self.seed_macro("__FLT_EVAL_METHOD__", "0")
  self.seed_macro("__FLT_RADIX__", "2")
  self.seed_macro("__FLT_MANT_DIG__", "24")
  self.seed_macro("__FLT_DIG__", "6")
  self.seed_macro("__FLT_DECIMAL_DIG__", "9")
  self.seed_macro("__FLT_MIN_EXP__", "(-125)")
  self.seed_macro("__FLT_MIN_10_EXP__", "(-37)")
  self.seed_macro("__FLT_MAX_EXP__", "128")
  self.seed_macro("__FLT_MAX_10_EXP__", "38")
  self.seed_macro("__FLT_MAX__", "3.40282347e+38F")
  self.seed_macro("__FLT_NORM_MAX__", "3.40282347e+38F")
  self.seed_macro("__FLT_MIN__", "1.17549435e-38F")
  self.seed_macro("__FLT_EPSILON__", "1.19209290e-7F")
  self.seed_macro("__FLT_DENORM_MIN__", "1.40129846e-45F")
  self.seed_macro("__FLT_HAS_DENORM__", "1")
  self.seed_macro("__FLT_HAS_INFINITY__", "1")
  self.seed_macro("__FLT_HAS_QUIET_NAN__", "1")
  self.seed_macro("__DBL_MANT_DIG__", "53")
  self.seed_macro("__DBL_DIG__", "15")
  self.seed_macro("__DBL_DECIMAL_DIG__", "17")
  self.seed_macro("__DBL_MIN_EXP__", "(-1021)")
  self.seed_macro("__DBL_MIN_10_EXP__", "(-307)")
  self.seed_macro("__DBL_MAX_EXP__", "1024")
  self.seed_macro("__DBL_MAX_10_EXP__", "308")
  self.seed_macro("__DBL_MAX__", "1.7976931348623157e+308")
  self.seed_macro("__DBL_NORM_MAX__", "1.7976931348623157e+308")
  self.seed_macro("__DBL_MIN__", "2.2250738585072014e-308")
  self.seed_macro("__DBL_EPSILON__", "2.2204460492503131e-16")
  self.seed_macro("__DBL_DENORM_MIN__", "4.9406564584124654e-324")
  self.seed_macro("__DBL_HAS_DENORM__", "1")
  self.seed_macro("__DBL_HAS_INFINITY__", "1")
  self.seed_macro("__DBL_HAS_QUIET_NAN__", "1")
  self.seed_macro("__DECIMAL_DIG__", "__LDBL_DECIMAL_DIG__")
  self.seed_macro("__SCHAR_WIDTH__", "8")
  self.seed_macro("__SHRT_WIDTH__", "16")
  self.seed_macro("__INT_WIDTH__", "32")
  self.seed_macro("__LONG_WIDTH__", "64")
  self.seed_macro("__LLONG_WIDTH__", "64")
  self.seed_macro("__POINTER_WIDTH__", "64")
  self.seed_macro("__SIZE_WIDTH__", "64")
  self.seed_macro("__PTRDIFF_WIDTH__", "64")
  self.seed_macro("__INTPTR_WIDTH__", "64")
  self.seed_macro("__UINTPTR_WIDTH__", "64")
  self.seed_macro("__INTMAX_WIDTH__", "64")
  self.seed_macro("__UINTMAX_WIDTH__", "64")
  self.seed_macro("__WCHAR_WIDTH__", "32")
  self.seed_macro("__WINT_WIDTH__", "32")
  self.seed_macro("__SIG_ATOMIC_WIDTH__", "32")
  self.seed_macro("__PTRDIFF_MAX__", "9223372036854775807L")
  self.seed_macro("__INTPTR_MAX__", "9223372036854775807L")
  self.seed_macro("__INTMAX_MAX__", "9223372036854775807L")
  self.seed_macro("__SIG_ATOMIC_MAX__", "2147483647")
  self.seed_macro("__SIZE_MAX__", "18446744073709551615UL")
  self.seed_macro("__UINTPTR_MAX__", "18446744073709551615UL")
  self.seed_macro("__UINTMAX_MAX__", "18446744073709551615UL")
  self.seed_macro("__UINT8_MAX__", "255")
  self.seed_macro("__UINT16_MAX__", "65535")
  self.seed_macro("__UINT32_MAX__", "4294967295U")
  self.seed_macro("__UINT64_MAX__", "18446744073709551615UL")
  self.seed_macro("__SIZE_TYPE__", "long unsigned int")
  self.seed_macro("__PTRDIFF_TYPE__", "long int")
  self.seed_macro("__INTPTR_TYPE__", "long int")
  self.seed_macro("__UINTPTR_TYPE__", "long unsigned int")
  self.seed_macro("__INTMAX_TYPE__", "long int")
  self.seed_macro("__UINTMAX_TYPE__", "long unsigned int")
  self.seed_macro("__SIG_ATOMIC_TYPE__", "int")
  self.seed_macro("__INT8_TYPE__", "signed char")
  self.seed_macro("__UINT8_TYPE__", "unsigned char")
  self.seed_macro("__INT16_TYPE__", "short")
  self.seed_macro("__UINT16_TYPE__", "unsigned short")
  self.seed_macro("__INT32_TYPE__", "int")
  self.seed_macro("__UINT32_TYPE__", "unsigned int")
  self.seed_macro("__INT64_TYPE__", "long long int")
  self.seed_macro("__UINT64_TYPE__", "long long unsigned int")
  self.seed_macro("__INT_LEAST8_TYPE__", "signed char")
  self.seed_macro("__UINT_LEAST8_TYPE__", "unsigned char")
  self.seed_macro("__INT_LEAST16_TYPE__", "short")
  self.seed_macro("__UINT_LEAST16_TYPE__", "unsigned short")
  self.seed_macro("__INT_LEAST32_TYPE__", "int")
  self.seed_macro("__UINT_LEAST32_TYPE__", "unsigned int")
  self.seed_macro("__INT_LEAST64_TYPE__", "long long int")
  self.seed_macro("__UINT_LEAST64_TYPE__", "long long unsigned int")
  self.seed_macro("__INT_FAST8_TYPE__", "signed char")
  self.seed_macro("__UINT_FAST8_TYPE__", "unsigned char")
  self.seed_macro("__INT_FAST16_TYPE__", "short")
  self.seed_macro("__UINT_FAST16_TYPE__", "unsigned short")
  self.seed_macro("__INT_FAST32_TYPE__", "int")
  self.seed_macro("__UINT_FAST32_TYPE__", "unsigned int")
  self.seed_macro("__INT_FAST64_TYPE__", "long long int")
  self.seed_macro("__UINT_FAST64_TYPE__", "long long unsigned int")
  self.seed_macro("__WCHAR_TYPE__", "int")
  self.seed_macro("__WINT_TYPE__", "int")
  self.seed_macro("__WCHAR_MAX__", "2147483647")
  self.seed_macro("__ATOMIC_RELAXED", "0")
  self.seed_macro("__ATOMIC_CONSUME", "1")
  self.seed_macro("__ATOMIC_ACQUIRE", "2")
  self.seed_macro("__ATOMIC_RELEASE", "3")
  self.seed_macro("__ATOMIC_ACQ_REL", "4")
  self.seed_macro("__ATOMIC_SEQ_CST", "5")
  self.seed_macro("__GCC_ATOMIC_BOOL_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_CHAR_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_SHORT_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_INT_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_LONG_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_LLONG_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_POINTER_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_TEST_AND_SET_TRUEVAL", "1")
  self.seed_macro("__GNUC_STDC_INLINE__", "1")
  self.seed_macro("__FINITE_MATH_ONLY__", "0")
}

///|
fn Preprocessor::seed_darwin_arm64_macros(self : Preprocessor) -> Unit {
  self.seed_macro("__APPLE__", "1")
  self.seed_macro("__APPLE_CC__", "6000")
  self.seed_macro("__MACH__", "1")
  self.seed_macro("__DYNAMIC__", "1")
  self.seed_macro("__PIC__", "2")
  self.seed_macro("__pic__", "2")
  self.seed_macro("__NO_MATH_ERRNO__", "1")
  self.seed_macro("__PRAGMA_REDEFINE_EXTNAME", "1")
  self.seed_macro("__STDC_NO_THREADS__", "1")
  self.seed_macro("TARGET_OS_MAC", "1")
  self.seed_macro("TARGET_OS_OSX", "1")
  self.seed_macro("TARGET_OS_IPHONE", "0")
  self.seed_macro("TARGET_IPHONE_SIMULATOR", "0")
  self.seed_macro("TARGET_OS_SIMULATOR", "0")
  self.seed_macro("TARGET_OS_EMBEDDED", "0")
  self.seed_macro("TARGET_OS_IOS", "0")
  self.seed_macro("TARGET_OS_IOSMAC", "0")
  self.seed_macro("TARGET_OS_MACCATALYST", "0")
  self.seed_macro("TARGET_OS_UIKITFORMAC", "0")
  self.seed_macro("TARGET_OS_TV", "0")
  self.seed_macro("TARGET_OS_WATCH", "0")
  self.seed_macro("TARGET_OS_BRIDGE", "0")
  self.seed_macro("TARGET_OS_NANO", "0")
  self.seed_macro("TARGET_OS_VISION", "0")
  self.seed_macro("TARGET_OS_XR", "0")
  self.seed_macro("TARGET_OS_ARROW", "1")
  self.seed_macro("TARGET_OS_DRIVERKIT", "0")
  self.seed_macro("TARGET_OS_LINUX", "0")
  self.seed_macro("TARGET_OS_UNIX", "0")
  self.seed_macro("TARGET_OS_WINDOWS", "0")
  self.seed_macro("TARGET_OS_WIN32", "0")
  self.seed_macro("__aarch64__", "1")
  self.seed_macro("__arm64", "1")
  self.seed_macro("__arm64__", "1")
  self.seed_macro("__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__", "150500")
  self.seed_macro("__ENVIRONMENT_OS_VERSION_MIN_REQUIRED__", "150500")
  self.seed_macro("__BIGGEST_ALIGNMENT__", "8")
  self.seed_macro("__SIZEOF_LONG_DOUBLE__", "8")
  self.seed_macro("__LDBL_MANT_DIG__", "53")
  self.seed_macro("__LDBL_DIG__", "15")
  self.seed_macro("__LDBL_DECIMAL_DIG__", "17")
  self.seed_macro("__LDBL_MIN_EXP__", "(-1021)")
  self.seed_macro("__LDBL_MIN_10_EXP__", "(-307)")
  self.seed_macro("__LDBL_MAX_EXP__", "1024")
  self.seed_macro("__LDBL_MAX_10_EXP__", "308")
  self.seed_macro("__LDBL_MAX__", "1.7976931348623157e+308L")
  self.seed_macro("__LDBL_NORM_MAX__", "1.7976931348623157e+308L")
  self.seed_macro("__LDBL_MIN__", "2.2250738585072014e-308L")
  self.seed_macro("__LDBL_EPSILON__", "2.2204460492503131e-16L")
  self.seed_macro("__LDBL_DENORM_MIN__", "4.9406564584124654e-324L")
  self.seed_macro("__LDBL_HAS_DENORM__", "1")
  self.seed_macro("__LDBL_HAS_INFINITY__", "1")
  self.seed_macro("__LDBL_HAS_QUIET_NAN__", "1")
  self.seed_macro("__BOOL_WIDTH__", "8")
  self.seed_macro("__CHAR16_TYPE__", "unsigned short")
  self.seed_macro("__CHAR32_TYPE__", "unsigned int")
  self.seed_macro("__CLANG_ATOMIC_BOOL_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_CHAR_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_CHAR16_T_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_CHAR32_T_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_SHORT_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_INT_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_LONG_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_LLONG_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_POINTER_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_WCHAR_T_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_CHAR16_T_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_CHAR32_T_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_WCHAR_T_LOCK_FREE", "2")
  self.seed_macro("__GCC_HAVE_SYNC_COMPARE_AND_SWAP_1", "1")
  self.seed_macro("__GCC_HAVE_SYNC_COMPARE_AND_SWAP_2", "1")
  self.seed_macro("__GCC_HAVE_SYNC_COMPARE_AND_SWAP_4", "1")
  self.seed_macro("__GCC_HAVE_SYNC_COMPARE_AND_SWAP_8", "1")
  self.seed_macro("__INT8_MAX__", "127")
  self.seed_macro("__INT16_MAX__", "32767")
  self.seed_macro("__INT32_MAX__", "2147483647")
  self.seed_macro("__INT64_MAX__", "9223372036854775807LL")
  self.seed_macro("__UINT8_MAX__", "255")
  self.seed_macro("__UINT16_MAX__", "65535")
  self.seed_macro("__UINT32_MAX__", "4294967295U")
  self.seed_macro("__UINT64_MAX__", "18446744073709551615ULL")
  self.seed_macro("__INT8_C_SUFFIX__", "")
  self.seed_macro("__INT16_C_SUFFIX__", "")
  self.seed_macro("__INT32_C_SUFFIX__", "")
  self.seed_macro("__UINT8_C_SUFFIX__", "")
  self.seed_macro("__UINT16_C_SUFFIX__", "")
  self.seed_macro("__UINT32_C_SUFFIX__", "U")
  self.seed_macro("__INTMAX_C_SUFFIX__", "L")
  self.seed_macro("__UINTMAX_C_SUFFIX__", "UL")
  self.seed_macro("__INT8_FMTd__", "\"hhd\"")
  self.seed_macro("__INT8_FMTi__", "\"hhi\"")
  self.seed_macro("__INT16_FMTd__", "\"hd\"")
  self.seed_macro("__INT16_FMTi__", "\"hi\"")
  self.seed_macro("__INT32_FMTd__", "\"d\"")
  self.seed_macro("__INT32_FMTi__", "\"i\"")
  self.seed_macro("__INTMAX_FMTd__", "\"ld\"")
  self.seed_macro("__INTMAX_FMTi__", "\"li\"")
  self.seed_macro("__INTPTR_FMTd__", "\"ld\"")
  self.seed_macro("__INTPTR_FMTi__", "\"li\"")
  self.seed_macro("__PTRDIFF_FMTd__", "\"ld\"")
  self.seed_macro("__PTRDIFF_FMTi__", "\"li\"")
  self.seed_macro("__UINT8_FMTX__", "\"hhX\"")
  self.seed_macro("__UINT8_FMTo__", "\"hho\"")
  self.seed_macro("__UINT8_FMTu__", "\"hhu\"")
  self.seed_macro("__UINT8_FMTx__", "\"hhx\"")
  self.seed_macro("__UINT16_FMTX__", "\"hX\"")
  self.seed_macro("__UINT16_FMTo__", "\"ho\"")
  self.seed_macro("__UINT16_FMTu__", "\"hu\"")
  self.seed_macro("__UINT16_FMTx__", "\"hx\"")
  self.seed_macro("__UINT32_FMTX__", "\"X\"")
  self.seed_macro("__UINT32_FMTo__", "\"o\"")
  self.seed_macro("__UINT32_FMTu__", "\"u\"")
  self.seed_macro("__UINT32_FMTx__", "\"x\"")
  self.seed_macro("__UINTMAX_FMTX__", "\"lX\"")
  self.seed_macro("__UINTMAX_FMTo__", "\"lo\"")
  self.seed_macro("__UINTMAX_FMTu__", "\"lu\"")
  self.seed_macro("__UINTMAX_FMTx__", "\"lx\"")
  self.seed_macro("__UINTPTR_FMTX__", "\"lX\"")
  self.seed_macro("__UINTPTR_FMTo__", "\"lo\"")
  self.seed_macro("__UINTPTR_FMTu__", "\"lu\"")
  self.seed_macro("__UINTPTR_FMTx__", "\"lx\"")
  self.seed_macro("__SIZE_FMTX__", "\"lX\"")
  self.seed_macro("__SIZE_FMTo__", "\"lo\"")
  self.seed_macro("__SIZE_FMTu__", "\"lu\"")
  self.seed_macro("__SIZE_FMTx__", "\"lx\"")
  self.seed_macro("__INT_LEAST8_MAX__", "127")
  self.seed_macro("__INT_LEAST16_MAX__", "32767")
  self.seed_macro("__INT_LEAST32_MAX__", "2147483647")
  self.seed_macro("__INT_LEAST64_MAX__", "9223372036854775807LL")
  self.seed_macro("__INT_LEAST8_WIDTH__", "8")
  self.seed_macro("__INT_LEAST16_WIDTH__", "16")
  self.seed_macro("__INT_LEAST32_WIDTH__", "32")
  self.seed_macro("__UINT_LEAST64_MAX__", "18446744073709551615ULL")
  self.seed_macro("__UINT_LEAST8_MAX__", "255")
  self.seed_macro("__UINT_LEAST16_MAX__", "65535")
  self.seed_macro("__UINT_LEAST32_MAX__", "4294967295U")
  self.seed_macro("__INT_FAST8_MAX__", "127")
  self.seed_macro("__INT_FAST16_MAX__", "32767")
  self.seed_macro("__INT_FAST32_MAX__", "2147483647")
  self.seed_macro("__INT_FAST64_MAX__", "9223372036854775807LL")
  self.seed_macro("__INT_FAST8_WIDTH__", "8")
  self.seed_macro("__INT_FAST16_WIDTH__", "16")
  self.seed_macro("__INT_FAST32_WIDTH__", "32")
  self.seed_macro("__UINT_FAST8_MAX__", "255")
  self.seed_macro("__UINT_FAST16_MAX__", "65535")
  self.seed_macro("__UINT_FAST32_MAX__", "4294967295U")
  self.seed_macro("__UINT_FAST64_MAX__", "18446744073709551615ULL")
  self.seed_macro("__INT_LEAST64_WIDTH__", "64")
  self.seed_macro("__INT_FAST64_WIDTH__", "64")
  self.seed_macro("__INT64_C_SUFFIX__", "LL")
  self.seed_macro("__UINT64_C_SUFFIX__", "ULL")
  self.seed_macro("__INT64_FMTd__", "\"lld\"")
  self.seed_macro("__INT64_FMTi__", "\"lli\"")
  self.seed_macro("__UINT64_FMTX__", "\"llX\"")
  self.seed_macro("__UINT64_FMTo__", "\"llo\"")
  self.seed_macro("__UINT64_FMTu__", "\"llu\"")
  self.seed_macro("__UINT64_FMTx__", "\"llx\"")
  self.seed_macro("__INT_LEAST8_FMTd__", "\"hhd\"")
  self.seed_macro("__INT_LEAST8_FMTi__", "\"hhi\"")
  self.seed_macro("__INT_LEAST16_FMTd__", "\"hd\"")
  self.seed_macro("__INT_LEAST16_FMTi__", "\"hi\"")
  self.seed_macro("__INT_LEAST32_FMTd__", "\"d\"")
  self.seed_macro("__INT_LEAST32_FMTi__", "\"i\"")
  self.seed_macro("__INT_LEAST64_FMTd__", "\"lld\"")
  self.seed_macro("__INT_LEAST64_FMTi__", "\"lli\"")
  self.seed_macro("__UINT_LEAST8_FMTX__", "\"hhX\"")
  self.seed_macro("__UINT_LEAST8_FMTo__", "\"hho\"")
  self.seed_macro("__UINT_LEAST8_FMTu__", "\"hhu\"")
  self.seed_macro("__UINT_LEAST8_FMTx__", "\"hhx\"")
  self.seed_macro("__UINT_LEAST16_FMTX__", "\"hX\"")
  self.seed_macro("__UINT_LEAST16_FMTo__", "\"ho\"")
  self.seed_macro("__UINT_LEAST16_FMTu__", "\"hu\"")
  self.seed_macro("__UINT_LEAST16_FMTx__", "\"hx\"")
  self.seed_macro("__UINT_LEAST32_FMTX__", "\"X\"")
  self.seed_macro("__UINT_LEAST32_FMTo__", "\"o\"")
  self.seed_macro("__UINT_LEAST32_FMTu__", "\"u\"")
  self.seed_macro("__UINT_LEAST32_FMTx__", "\"x\"")
  self.seed_macro("__UINT_LEAST64_FMTX__", "\"llX\"")
  self.seed_macro("__UINT_LEAST64_FMTo__", "\"llo\"")
  self.seed_macro("__UINT_LEAST64_FMTu__", "\"llu\"")
  self.seed_macro("__UINT_LEAST64_FMTx__", "\"llx\"")
  self.seed_macro("__INT_FAST8_FMTd__", "\"hhd\"")
  self.seed_macro("__INT_FAST8_FMTi__", "\"hhi\"")
  self.seed_macro("__INT_FAST16_FMTd__", "\"hd\"")
  self.seed_macro("__INT_FAST16_FMTi__", "\"hi\"")
  self.seed_macro("__INT_FAST32_FMTd__", "\"d\"")
  self.seed_macro("__INT_FAST32_FMTi__", "\"i\"")
  self.seed_macro("__INT_FAST64_FMTd__", "\"lld\"")
  self.seed_macro("__INT_FAST64_FMTi__", "\"lli\"")
  self.seed_macro("__UINT_FAST8_FMTX__", "\"hhX\"")
  self.seed_macro("__UINT_FAST8_FMTo__", "\"hho\"")
  self.seed_macro("__UINT_FAST8_FMTu__", "\"hhu\"")
  self.seed_macro("__UINT_FAST8_FMTx__", "\"hhx\"")
  self.seed_macro("__UINT_FAST16_FMTX__", "\"hX\"")
  self.seed_macro("__UINT_FAST16_FMTo__", "\"ho\"")
  self.seed_macro("__UINT_FAST16_FMTu__", "\"hu\"")
  self.seed_macro("__UINT_FAST16_FMTx__", "\"hx\"")
  self.seed_macro("__UINT_FAST32_FMTX__", "\"X\"")
  self.seed_macro("__UINT_FAST32_FMTo__", "\"o\"")
  self.seed_macro("__UINT_FAST32_FMTu__", "\"u\"")
  self.seed_macro("__UINT_FAST32_FMTx__", "\"x\"")
  self.seed_macro("__UINT_FAST64_FMTX__", "\"llX\"")
  self.seed_macro("__UINT_FAST64_FMTo__", "\"llo\"")
  self.seed_macro("__UINT_FAST64_FMTu__", "\"llu\"")
  self.seed_macro("__UINT_FAST64_FMTx__", "\"llx\"")
  self.seed_macro("__GXX_ABI_VERSION", "1002")
  self.seed_macro("__GCC_CONSTRUCTIVE_SIZE", "64")
  self.seed_macro("__GCC_DESTRUCTIVE_SIZE", "64")
  self.seed_macro("__FPCLASS_SNAN", "0x0001")
  self.seed_macro("__FPCLASS_QNAN", "0x0002")
  self.seed_macro("__FPCLASS_NEGINF", "0x0004")
  self.seed_macro("__FPCLASS_NEGNORMAL", "0x0008")
  self.seed_macro("__FPCLASS_NEGSUBNORMAL", "0x0010")
  self.seed_macro("__FPCLASS_NEGZERO", "0x0020")
  self.seed_macro("__FPCLASS_POSZERO", "0x0040")
  self.seed_macro("__FPCLASS_POSSUBNORMAL", "0x0080")
  self.seed_macro("__FPCLASS_POSNORMAL", "0x0100")
  self.seed_macro("__FPCLASS_POSINF", "0x0200")
  self.seed_macro("__MEMORY_SCOPE_SYSTEM", "0")
  self.seed_macro("__MEMORY_SCOPE_DEVICE", "1")
  self.seed_macro("__MEMORY_SCOPE_WRKGRP", "2")
  self.seed_macro("__MEMORY_SCOPE_WVFRNT", "3")
  self.seed_macro("__MEMORY_SCOPE_SINGLE", "4")
  self.seed_macro("__OPENCL_MEMORY_SCOPE_WORK_ITEM", "0")
  self.seed_macro("__OPENCL_MEMORY_SCOPE_WORK_GROUP", "1")
  self.seed_macro("__OPENCL_MEMORY_SCOPE_DEVICE", "2")
  self.seed_macro("__OPENCL_MEMORY_SCOPE_ALL_SVM_DEVICES", "3")
  self.seed_macro("__OPENCL_MEMORY_SCOPE_SUB_GROUP", "4")
  self.seed_macro("__REGISTER_PREFIX__", "")
  self.seed_macro("__USER_LABEL_PREFIX__", "_")
  self.seed_macro("__WINT_MAX__", "2147483647")
}

///|
fn Preprocessor::seed_linux_amd64_integer_introspection_macros(
  self : Preprocessor,
) -> Unit {
  self.seed_macro("__BOOL_WIDTH__", "8")
  self.seed_macro("__CHAR16_TYPE__", "unsigned short")
  self.seed_macro("__CHAR32_TYPE__", "unsigned int")
  self.seed_macro("__CLANG_ATOMIC_BOOL_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_CHAR_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_CHAR16_T_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_CHAR32_T_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_SHORT_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_INT_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_LONG_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_LLONG_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_POINTER_LOCK_FREE", "2")
  self.seed_macro("__CLANG_ATOMIC_WCHAR_T_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_CHAR16_T_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_CHAR32_T_LOCK_FREE", "2")
  self.seed_macro("__GCC_ATOMIC_WCHAR_T_LOCK_FREE", "2")
  self.seed_macro("__INT8_MAX__", "127")
  self.seed_macro("__INT16_MAX__", "32767")
  self.seed_macro("__INT32_MAX__", "2147483647")
  self.seed_macro("__INT64_MAX__", "9223372036854775807L")
  self.seed_macro("__INT8_C_SUFFIX__", "")
  self.seed_macro("__INT16_C_SUFFIX__", "")
  self.seed_macro("__INT32_C_SUFFIX__", "")
  self.seed_macro("__INT64_C_SUFFIX__", "L")
  self.seed_macro("__INTMAX_C_SUFFIX__", "L")
  self.seed_macro("__UINT8_C_SUFFIX__", "")
  self.seed_macro("__UINT16_C_SUFFIX__", "")
  self.seed_macro("__UINT32_C_SUFFIX__", "U")
  self.seed_macro("__UINT64_C_SUFFIX__", "UL")
  self.seed_macro("__UINTMAX_C_SUFFIX__", "UL")
  self.seed_macro("__INT8_FMTd__", "\"hhd\"")
  self.seed_macro("__INT8_FMTi__", "\"hhi\"")
  self.seed_macro("__INT16_FMTd__", "\"hd\"")
  self.seed_macro("__INT16_FMTi__", "\"hi\"")
  self.seed_macro("__INT32_FMTd__", "\"d\"")
  self.seed_macro("__INT32_FMTi__", "\"i\"")
  self.seed_macro("__INT64_FMTd__", "\"ld\"")
  self.seed_macro("__INT64_FMTi__", "\"li\"")
  self.seed_macro("__INTMAX_FMTd__", "\"ld\"")
  self.seed_macro("__INTMAX_FMTi__", "\"li\"")
  self.seed_macro("__INTPTR_FMTd__", "\"ld\"")
  self.seed_macro("__INTPTR_FMTi__", "\"li\"")
  self.seed_macro("__PTRDIFF_FMTd__", "\"ld\"")
  self.seed_macro("__PTRDIFF_FMTi__", "\"li\"")
  self.seed_macro("__UINT8_FMTX__", "\"hhX\"")
  self.seed_macro("__UINT8_FMTo__", "\"hho\"")
  self.seed_macro("__UINT8_FMTu__", "\"hhu\"")
  self.seed_macro("__UINT8_FMTx__", "\"hhx\"")
  self.seed_macro("__UINT16_FMTX__", "\"hX\"")
  self.seed_macro("__UINT16_FMTo__", "\"ho\"")
  self.seed_macro("__UINT16_FMTu__", "\"hu\"")
  self.seed_macro("__UINT16_FMTx__", "\"hx\"")
  self.seed_macro("__UINT32_FMTX__", "\"X\"")
  self.seed_macro("__UINT32_FMTo__", "\"o\"")
  self.seed_macro("__UINT32_FMTu__", "\"u\"")
  self.seed_macro("__UINT32_FMTx__", "\"x\"")
  self.seed_macro("__UINT64_FMTX__", "\"lX\"")
  self.seed_macro("__UINT64_FMTo__", "\"lo\"")
  self.seed_macro("__UINT64_FMTu__", "\"lu\"")
  self.seed_macro("__UINT64_FMTx__", "\"lx\"")
  self.seed_macro("__UINTMAX_FMTX__", "\"lX\"")
  self.seed_macro("__UINTMAX_FMTo__", "\"lo\"")
  self.seed_macro("__UINTMAX_FMTu__", "\"lu\"")
  self.seed_macro("__UINTMAX_FMTx__", "\"lx\"")
  self.seed_macro("__UINTPTR_FMTX__", "\"lX\"")
  self.seed_macro("__UINTPTR_FMTo__", "\"lo\"")
  self.seed_macro("__UINTPTR_FMTu__", "\"lu\"")
  self.seed_macro("__UINTPTR_FMTx__", "\"lx\"")
  self.seed_macro("__SIZE_FMTX__", "\"lX\"")
  self.seed_macro("__SIZE_FMTo__", "\"lo\"")
  self.seed_macro("__SIZE_FMTu__", "\"lu\"")
  self.seed_macro("__SIZE_FMTx__", "\"lx\"")
  self.seed_macro("__INT_LEAST8_MAX__", "127")
  self.seed_macro("__INT_LEAST16_MAX__", "32767")
  self.seed_macro("__INT_LEAST32_MAX__", "2147483647")
  self.seed_macro("__INT_LEAST64_MAX__", "9223372036854775807L")
  self.seed_macro("__INT_LEAST8_WIDTH__", "8")
  self.seed_macro("__INT_LEAST16_WIDTH__", "16")
  self.seed_macro("__INT_LEAST32_WIDTH__", "32")
  self.seed_macro("__INT_LEAST64_WIDTH__", "64")
  self.seed_macro("__INT_LEAST8_FMTd__", "\"hhd\"")
  self.seed_macro("__INT_LEAST8_FMTi__", "\"hhi\"")
  self.seed_macro("__INT_LEAST16_FMTd__", "\"hd\"")
  self.seed_macro("__INT_LEAST16_FMTi__", "\"hi\"")
  self.seed_macro("__INT_LEAST32_FMTd__", "\"d\"")
  self.seed_macro("__INT_LEAST32_FMTi__", "\"i\"")
  self.seed_macro("__INT_LEAST64_FMTd__", "\"ld\"")
  self.seed_macro("__INT_LEAST64_FMTi__", "\"li\"")
  self.seed_macro("__UINT_LEAST8_MAX__", "255")
  self.seed_macro("__UINT_LEAST16_MAX__", "65535")
  self.seed_macro("__UINT_LEAST32_MAX__", "4294967295U")
  self.seed_macro("__UINT_LEAST64_MAX__", "18446744073709551615UL")
  self.seed_macro("__UINT_LEAST8_FMTX__", "\"hhX\"")
  self.seed_macro("__UINT_LEAST8_FMTo__", "\"hho\"")
  self.seed_macro("__UINT_LEAST8_FMTu__", "\"hhu\"")
  self.seed_macro("__UINT_LEAST8_FMTx__", "\"hhx\"")
  self.seed_macro("__UINT_LEAST16_FMTX__", "\"hX\"")
  self.seed_macro("__UINT_LEAST16_FMTo__", "\"ho\"")
  self.seed_macro("__UINT_LEAST16_FMTu__", "\"hu\"")
  self.seed_macro("__UINT_LEAST16_FMTx__", "\"hx\"")
  self.seed_macro("__UINT_LEAST32_FMTX__", "\"X\"")
  self.seed_macro("__UINT_LEAST32_FMTo__", "\"o\"")
  self.seed_macro("__UINT_LEAST32_FMTu__", "\"u\"")
  self.seed_macro("__UINT_LEAST32_FMTx__", "\"x\"")
  self.seed_macro("__UINT_LEAST64_FMTX__", "\"lX\"")
  self.seed_macro("__UINT_LEAST64_FMTo__", "\"lo\"")
  self.seed_macro("__UINT_LEAST64_FMTu__", "\"lu\"")
  self.seed_macro("__UINT_LEAST64_FMTx__", "\"lx\"")
  self.seed_macro("__INT_FAST8_MAX__", "127")
  self.seed_macro("__INT_FAST16_MAX__", "32767")
  self.seed_macro("__INT_FAST32_MAX__", "2147483647")
  self.seed_macro("__INT_FAST64_MAX__", "9223372036854775807L")
  self.seed_macro("__INT_FAST8_WIDTH__", "8")
  self.seed_macro("__INT_FAST16_WIDTH__", "16")
  self.seed_macro("__INT_FAST32_WIDTH__", "32")
  self.seed_macro("__INT_FAST64_WIDTH__", "64")
  self.seed_macro("__INT_FAST8_FMTd__", "\"hhd\"")
  self.seed_macro("__INT_FAST8_FMTi__", "\"hhi\"")
  self.seed_macro("__INT_FAST16_FMTd__", "\"hd\"")
  self.seed_macro("__INT_FAST16_FMTi__", "\"hi\"")
  self.seed_macro("__INT_FAST32_FMTd__", "\"d\"")
  self.seed_macro("__INT_FAST32_FMTi__", "\"i\"")
  self.seed_macro("__INT_FAST64_FMTd__", "\"ld\"")
  self.seed_macro("__INT_FAST64_FMTi__", "\"li\"")
  self.seed_macro("__UINT_FAST8_MAX__", "255")
  self.seed_macro("__UINT_FAST16_MAX__", "65535")
  self.seed_macro("__UINT_FAST32_MAX__", "4294967295U")
  self.seed_macro("__UINT_FAST64_MAX__", "18446744073709551615UL")
  self.seed_macro("__UINT_FAST8_FMTX__", "\"hhX\"")
  self.seed_macro("__UINT_FAST8_FMTo__", "\"hho\"")
  self.seed_macro("__UINT_FAST8_FMTu__", "\"hhu\"")
  self.seed_macro("__UINT_FAST8_FMTx__", "\"hhx\"")
  self.seed_macro("__UINT_FAST16_FMTX__", "\"hX\"")
  self.seed_macro("__UINT_FAST16_FMTo__", "\"ho\"")
  self.seed_macro("__UINT_FAST16_FMTu__", "\"hu\"")
  self.seed_macro("__UINT_FAST16_FMTx__", "\"hx\"")
  self.seed_macro("__UINT_FAST32_FMTX__", "\"X\"")
  self.seed_macro("__UINT_FAST32_FMTo__", "\"o\"")
  self.seed_macro("__UINT_FAST32_FMTu__", "\"u\"")
  self.seed_macro("__UINT_FAST32_FMTx__", "\"x\"")
  self.seed_macro("__UINT_FAST64_FMTX__", "\"lX\"")
  self.seed_macro("__UINT_FAST64_FMTo__", "\"lo\"")
  self.seed_macro("__UINT_FAST64_FMTu__", "\"lu\"")
  self.seed_macro("__UINT_FAST64_FMTx__", "\"lx\"")
}

///|
fn Preprocessor::seed_linux_amd64_macros(self : Preprocessor) -> Unit {
  self.seed_linux_amd64_integer_introspection_macros()
  self.seed_macro("__gnu_linux__", "1")
  self.seed_macro("__linux__", "1")
  self.seed_macro("__linux", "1")
  self.seed_macro("linux", "1")
  self.seed_macro("__unix__", "1")
  self.seed_macro("__unix", "1")
  self.seed_macro("unix", "1")
  self.seed_macro("__ELF__", "1")
  self.seed_macro("__x86_64__", "1")
  self.seed_macro("__x86_64", "1")
  self.seed_macro("__amd64__", "1")
  self.seed_macro("__amd64", "1")
  self.seed_macro("__GXX_ABI_VERSION", "1002")
  self.seed_macro("__code_model_small__", "1")
  self.seed_macro("__GCC_HAVE_SYNC_COMPARE_AND_SWAP_1", "1")
  self.seed_macro("__GCC_HAVE_SYNC_COMPARE_AND_SWAP_2", "1")
  self.seed_macro("__GCC_HAVE_SYNC_COMPARE_AND_SWAP_4", "1")
  self.seed_macro("__GCC_HAVE_SYNC_COMPARE_AND_SWAP_8", "1")
  self.seed_macro("__GCC_CONSTRUCTIVE_SIZE", "64")
  self.seed_macro("__GCC_DESTRUCTIVE_SIZE", "64")
  self.seed_macro("__FPCLASS_SNAN", "0x0001")
  self.seed_macro("__FPCLASS_QNAN", "0x0002")
  self.seed_macro("__FPCLASS_NEGINF", "0x0004")
  self.seed_macro("__FPCLASS_NEGNORMAL", "0x0008")
  self.seed_macro("__FPCLASS_NEGSUBNORMAL", "0x0010")
  self.seed_macro("__FPCLASS_NEGZERO", "0x0020")
  self.seed_macro("__FPCLASS_POSZERO", "0x0040")
  self.seed_macro("__FPCLASS_POSSUBNORMAL", "0x0080")
  self.seed_macro("__FPCLASS_POSNORMAL", "0x0100")
  self.seed_macro("__FPCLASS_POSINF", "0x0200")
  self.seed_macro("__MEMORY_SCOPE_SYSTEM", "0")
  self.seed_macro("__MEMORY_SCOPE_DEVICE", "1")
  self.seed_macro("__MEMORY_SCOPE_WRKGRP", "2")
  self.seed_macro("__MEMORY_SCOPE_WVFRNT", "3")
  self.seed_macro("__MEMORY_SCOPE_SINGLE", "4")
  self.seed_macro("__OPENCL_MEMORY_SCOPE_WORK_ITEM", "0")
  self.seed_macro("__OPENCL_MEMORY_SCOPE_WORK_GROUP", "1")
  self.seed_macro("__OPENCL_MEMORY_SCOPE_DEVICE", "2")
  self.seed_macro("__OPENCL_MEMORY_SCOPE_ALL_SVM_DEVICES", "3")
  self.seed_macro("__OPENCL_MEMORY_SCOPE_SUB_GROUP", "4")
  self.seed_macro("__REGISTER_PREFIX__", "")
  self.seed_macro("__USER_LABEL_PREFIX__", "")
  self.seed_macro("__SIZEOF_LONG_DOUBLE__", "16")
  self.seed_macro("__INT64_MAX__", "9223372036854775807L")
  self.seed_macro("__INT64_TYPE__", "long int")
  self.seed_macro("__UINT64_TYPE__", "long unsigned int")
  self.seed_macro("__INT_LEAST64_TYPE__", "long int")
  self.seed_macro("__UINT_LEAST64_TYPE__", "long unsigned int")
  self.seed_macro("__INT_FAST64_TYPE__", "long int")
  self.seed_macro("__UINT_FAST64_TYPE__", "long unsigned int")
  self.seed_macro("__LDBL_MANT_DIG__", "64")
  self.seed_macro("__LDBL_DIG__", "18")
  self.seed_macro("__LDBL_DECIMAL_DIG__", "21")
  self.seed_macro("__LDBL_MIN_EXP__", "(-16381)")
  self.seed_macro("__LDBL_MIN_10_EXP__", "(-4931)")
  self.seed_macro("__LDBL_MAX_EXP__", "16384")
  self.seed_macro("__LDBL_MAX_10_EXP__", "4932")
  self.seed_macro("__LDBL_MAX__", "1.18973149535723176502e+4932L")
  self.seed_macro("__LDBL_NORM_MAX__", "1.18973149535723176502e+4932L")
  self.seed_macro("__LDBL_MIN__", "3.36210314311209350626e-4932L")
  self.seed_macro("__LDBL_EPSILON__", "1.08420217248550443401e-19L")
  self.seed_macro("__LDBL_DENORM_MIN__", "3.64519953188247460253e-4951L")
  self.seed_macro("__LDBL_HAS_DENORM__", "1")
  self.seed_macro("__LDBL_HAS_INFINITY__", "1")
  self.seed_macro("__LDBL_HAS_QUIET_NAN__", "1")
  self.seed_macro("__WINT_TYPE__", "unsigned int")
  self.seed_macro("__WINT_MAX__", "4294967295U")
  self.seed_macro("__WINT_UNSIGNED__", "1")
  self.seed_macro("__NO_MATH_INLINES", "1")
}

///|
fn Preprocessor::seed_target_macros(self : Preprocessor) -> Unit {
  self.seed_common_target_macros()
  match self.options.target {
    DarwinArm64 => self.seed_darwin_arm64_macros()
    LinuxAmd64 => self.seed_linux_amd64_macros()
  }
}

///|
fn Preprocessor::new(options : PreprocessOptions) -> Preprocessor {
  let pp = {
    options,
    macros: {},
    include_stack: [],
    once_files: {},
    dependencies: [],
    dependency_records: [],
    dependency_seen: {},
    line_control_file: None,
    line_control_line: None,
    counter: 0,
    error: None,
  }
  pp.record_dependency(options.filename, false)
  if options.undef_predefined {
    pp.seed_standard_macros()
  } else {
    pp.seed_target_macros()
  }
  pp.seed_macro_definition("__has_builtin(x) 0")
  pp.seed_macro_definition("__has_attribute(x) 0")
  pp.seed_macro_definition("__has_feature(x) 0")
  pp.seed_macro_definition("__has_extension(x) 0")
  pp.seed_macro_definition("__has_c_attribute(x) 0")
  pp.seed_macro_definition("__has_declspec_attribute(x) 0")
  pp.seed_macro_definition("__has_warning(x) 0")
  pp.seed_macro_definition("__is_identifier(x) 1")
  pp.seed_macro("__DATE__", pp_quote_string("May  9 2026"))
  pp.seed_macro("__TIME__", pp_quote_string("00:00:00"))
  for pair in options.defines {
    pp.seed_command_line_macro(pair.0, pair.1)
  }
  for name in options.undefines {
    pp.macros.remove(name)
  }
  pp
}

///|
fn pp_macro_dump_skips_name(name : String) -> Bool {
  match name {
    "__DATE__"
    | "__TIME__"
    | "__has_builtin"
    | "__has_attribute"
    | "__has_feature"
    | "__has_extension"
    | "__has_c_attribute"
    | "__has_declspec_attribute"
    | "__has_warning"
    | "__is_identifier" => true
    _ => false
  }
}

///|
fn pp_line_after(tokens : Array[PpToken], start : Int) -> Array[PpToken] {
  let result : Array[PpToken] = []
  for i = start; i < tokens.length(); i = i + 1 {
    result.push(tokens[i])
  }
  result
}

///|
fn Preprocessor::define_macro(
  self : Preprocessor,
  tokens : Array[PpToken],
) -> Unit {
  let start = pp_first_non_space(tokens)
  if start >= tokens.length() || tokens[start].kind != PpIdent {
    self.set_error("expected macro name after #define")
    return
  }
  let name = tokens[start].text
  let mut function_like = false
  let mut variadic = false
  let params : Array[String] = []
  let mut replacement_start = start + 1
  if replacement_start < tokens.length() &&
    tokens[replacement_start].is_punct("(") {
    function_like = true
    let mut i = replacement_start + 1
    while i < tokens.length() {
      let tok = tokens[i]
      if tok.is_punct(")") {
        replacement_start = i + 1
        break
      } else if tok.is_punct(",") {
        i += 1
      } else if tok.is_punct("...") {
        variadic = true
        params.push("__VA_ARGS__")
        i += 1
      } else if tok.kind == PpIdent {
        if i + 1 < tokens.length() && tokens[i + 1].is_punct("...") {
          variadic = true
          params.push(tok.text)
          i += 2
        } else {
          params.push(tok.text)
          i += 1
        }
      } else if tok.is_whitespace() {
        i += 1
      } else {
        self.set_error("invalid function-like macro parameter list for " + name)
        return
      }
    }
  }
  let replacement = pp_without_whitespace(
    pp_line_after(tokens, replacement_start),
  )
  self.macros[name] = { function_like, variadic, params, replacement }
}

///|
fn pp_parenthesized_body(
  tokens : Array[PpToken],
  lparen : Int,
) -> (Array[PpToken], Int)? {
  if lparen >= tokens.length() || !tokens[lparen].is_punct("(") {
    return None
  }
  let body : Array[PpToken] = []
  let mut depth = 0
  let mut i = lparen
  while i < tokens.length() {
    let tok = tokens[i]
    if tok.is_punct("(") {
      if depth > 0 {
        body.push(tok)
      }
      depth += 1
    } else if tok.is_punct(")") {
      depth -= 1
      if depth == 0 {
        return Some((body, i + 1))
      }
      body.push(tok)
    } else {
      body.push(tok)
    }
    i += 1
  }
  None
}

///|
fn pp_parse_header_name(clean : Array[PpToken]) -> (String, Bool)? {
  if clean.length() == 0 {
    return None
  }
  if clean[0].kind == PpString {
    return Some((pp_unquote_string_literal(clean[0].text), false))
  }
  if clean[0].is_punct("<") {
    let buf = StringBuilder::new()
    let mut i = 1
    while i < clean.length() && !clean[i].is_punct(">") {
      buf.write_string(clean[i].text)
      i += 1
    }
    if i < clean.length() && clean[i].is_punct(">") {
      return Some((buf.to_string(), true))
    }
  }
  None
}

///|
fn Preprocessor::parse_include_query_name(
  self : Preprocessor,
  tokens : Array[PpToken],
  file : String,
  line : Int,
) -> (String, Bool)? {
  let clean = pp_without_whitespace(tokens)
  match pp_parse_header_name(clean) {
    Some(header) => return Some(header)
    None => ()
  }
  let expanded = self.expand_tokens(tokens, {}, file, true, line, 0)
  pp_parse_header_name(pp_without_whitespace(expanded))
}

///|
fn Preprocessor::has_include_query(
  self : Preprocessor,
  tokens : Array[PpToken],
  including_file : String,
  logical_file : String,
  line : Int,
  next : Bool,
) -> Bool {
  match self.parse_include_query_name(tokens, logical_file, line) {
    Some((name, system)) =>
      if next {
        self.resolve_include_next(name, system, including_file) is Some(_)
      } else {
        self.resolve_include(name, system, including_file) is Some(_)
      }
    None => false
  }
}

///|
fn Preprocessor::replace_defined_operators(
  self : Preprocessor,
  tokens : Array[PpToken],
  including_file : String,
  logical_file : String,
  line : Int,
) -> Array[PpToken] {
  let clean = pp_without_whitespace(tokens)
  let result : Array[PpToken] = []
  let mut i = 0
  while i < clean.length() {
    let tok = clean[i]
    if tok.is_ident("__has_include") || tok.is_ident("__has_include_next") {
      if i + 1 < clean.length() && clean[i + 1].is_punct("(") {
        match pp_parenthesized_body(clean, i + 1) {
          Some((body, end_index)) => {
            let found = self.has_include_query(
              body,
              including_file,
              logical_file,
              line,
              tok.is_ident("__has_include_next"),
            )
            result.push(pp_token(PpNumber, if found { "1" } else { "0" }))
            i = end_index
          }
          None => {
            result.push(pp_token(PpNumber, "0"))
            i += 1
          }
        }
      } else {
        result.push(pp_token(PpNumber, "0"))
        i += 1
      }
    } else if tok.is_ident("defined") {
      if i + 1 < clean.length() && clean[i + 1].is_punct("(") {
        if i + 2 < clean.length() && clean[i + 2].kind == PpIdent {
          let name = clean[i + 2].text
          result.push(
            pp_token(
              PpNumber,
              if self.macros.contains(name) {
                "1"
              } else {
                "0"
              },
            ),
          )
          i += 3
          if i < clean.length() && clean[i].is_punct(")") {
            i += 1
          }
        } else {
          result.push(pp_token(PpNumber, "0"))
          i += 2
        }
      } else if i + 1 < clean.length() && clean[i + 1].kind == PpIdent {
        let name = clean[i + 1].text
        result.push(
          pp_token(PpNumber, if self.macros.contains(name) { "1" } else { "0" }),
        )
        i += 2
      } else {
        result.push(pp_token(PpNumber, "0"))
        i += 1
      }
    } else {
      result.push(tok)
      i += 1
    }
  }
  result
}

///|
fn Preprocessor::eval_if(
  self : Preprocessor,
  tokens : Array[PpToken],
  including_file : String,
  logical_file : String,
  line : Int,
) -> Bool {
  let defined_replaced = self.replace_defined_operators(
    tokens, including_file, logical_file, line,
  )
  let expanded = self.expand_tokens(
    defined_replaced,
    {},
    logical_file,
    true,
    line,
    0,
  )
  let normalized : Array[PpToken] = []
  for tok in expanded {
    if tok.kind == PpIdent {
      normalized.push(pp_token(PpNumber, "0"))
    } else {
      normalized.push(tok)
    }
  }
  pp_eval_if_expr(normalized) != 0L
}

///|
fn Preprocessor::parse_include_name(
  self : Preprocessor,
  tokens : Array[PpToken],
  file : String,
  line : Int,
) -> (String, Bool)? {
  let clean = pp_without_whitespace(tokens)
  if clean.length() == 0 {
    self.set_error("expected header name after #include")
    return None
  }
  match pp_parse_header_name(clean) {
    Some(header) => return Some(header)
    None => ()
  }
  let expanded = self.expand_tokens(tokens, {}, file, true, line, 0)
  match pp_parse_header_name(pp_without_whitespace(expanded)) {
    Some(header) => return Some(header)
    None => ()
  }
  self.set_error("unsupported #include header form")
  None
}

///|
priv struct IncludeSearchDir {
  dir : String
  system : Bool
}

///|
fn Preprocessor::include_search_dirs(
  self : Preprocessor,
  system : Bool,
) -> Array[IncludeSearchDir] {
  let paths : Array[IncludeSearchDir] = []
  if system {
    for dir in self.options.system_include_paths {
      paths.push({ dir, system: true })
    }
    for dir in self.options.include_paths {
      paths.push({ dir, system: false })
    }
  } else {
    for dir in self.options.include_paths {
      paths.push({ dir, system: false })
    }
    for dir in self.options.system_include_paths {
      paths.push({ dir, system: true })
    }
  }
  paths
}

///|
fn Preprocessor::resolve_include(
  self : Preprocessor,
  name : String,
  system : Bool,
  including_file : String,
) -> (String, Bool)? {
  if pp_is_absolute_path(name) && pp_file_exists(name) {
    return Some((name, system))
  }
  if !system {
    let candidate = pp_join_path(pp_dirname(including_file), name)
    if pp_file_exists(candidate) {
      return Some((candidate, false))
    }
  }
  for entry in self.include_search_dirs(system) {
    let candidate = pp_join_path(entry.dir, name)
    if pp_file_exists(candidate) {
      return Some((candidate, entry.system))
    }
  }
  None
}

///|
fn Preprocessor::resolve_include_next(
  self : Preprocessor,
  name : String,
  system : Bool,
  including_file : String,
) -> (String, Bool)? {
  let search_paths = self.include_search_dirs(system)
  let current_dir = pp_dirname(including_file)
  let mut found_current = false
  for entry in search_paths {
    let candidate = pp_join_path(entry.dir, name)
    if found_current {
      if pp_file_exists(candidate) {
        return Some((candidate, entry.system))
      }
    } else if candidate == including_file || entry.dir == current_dir {
      found_current = true
    }
  }
  if !found_current {
    for entry in search_paths {
      let candidate = pp_join_path(entry.dir, name)
      if candidate != including_file && pp_file_exists(candidate) {
        return Some((candidate, entry.system))
      }
    }
  }
  None
}

///|
fn Preprocessor::process_include(
  self : Preprocessor,
  tokens : Array[PpToken],
  including_file : String,
  logical_file : String,
  line : Int,
) -> String {
  match self.parse_include_name(tokens, logical_file, line) {
    Some((name, system)) =>
      match self.resolve_include(name, system, including_file) {
        Some((path, dependency_system)) =>
          if self.once_files.contains(path) {
            ""
          } else {
            self.record_dependency(path, dependency_system)
            match pp_read_file(path) {
              Some(content) => self.process_source(content, path)
              None => {
                self.set_error("cannot read include file: " + path)
                ""
              }
            }
          }
        None => {
          if self.options.allow_missing_includes {
            self.record_dependency(name, false)
          } else {
            self.set_error("include file not found: " + name)
          }
          ""
        }
      }
    None => ""
  }
}

///|
fn Preprocessor::process_include_next(
  self : Preprocessor,
  tokens : Array[PpToken],
  including_file : String,
  logical_file : String,
  line : Int,
) -> String {
  match self.parse_include_name(tokens, logical_file, line) {
    Some((name, system)) =>
      match self.resolve_include_next(name, system, including_file) {
        Some((path, dependency_system)) =>
          if self.once_files.contains(path) {
            ""
          } else {
            self.record_dependency(path, dependency_system)
            match pp_read_file(path) {
              Some(content) => self.process_source(content, path)
              None => {
                self.set_error("cannot read include file: " + path)
                ""
              }
            }
          }
        None => {
          if self.options.allow_missing_includes {
            self.record_dependency(name, false)
          } else {
            self.set_error("include_next file not found: " + name)
          }
          ""
        }
      }
    None => ""
  }
}

///|
fn Preprocessor::process_line_directive(
  self : Preprocessor,
  tokens : Array[PpToken],
  logical_file : String,
  line : Int,
) -> Unit {
  let expanded = self.expand_tokens(tokens, {}, logical_file, true, line, 0)
  let clean = pp_without_whitespace(expanded)
  if clean.length() == 0 || clean[0].kind != PpNumber {
    self.set_error("invalid #line directive")
    return
  }
  let next_line = pp_parse_int_literal(clean[0].text).to_int()
  if next_line <= 0 {
    self.set_error("invalid #line directive")
    return
  }
  self.line_control_line = Some(next_line)
  if clean.length() > 1 && clean[1].kind == PpString {
    self.line_control_file = Some(pp_unquote_string_literal(clean[1].text))
  }
}

///|
fn Preprocessor::process_directive(
  self : Preprocessor,
  tokens : Array[PpToken],
  stack : Array[ConditionalFrame],
  physical_file : String,
  logical_file : String,
  line : Int,
) -> String {
  let hash = pp_first_non_space(tokens)
  if hash >= tokens.length() || !tokens[hash].is_punct("#") {
    return ""
  }
  let after_hash = pp_first_non_space(pp_line_after(tokens, hash + 1))
  let directive_tokens = pp_line_after(tokens, hash + 1)
  let directive_index = pp_first_non_space(directive_tokens)
  if directive_index >= directive_tokens.length() {
    return ""
  }
  let directive = directive_tokens[directive_index]
  let rest = pp_line_after(directive_tokens, directive_index + 1)
  let active = self.is_active(stack)
  if directive.kind == PpNumber {
    if active {
      self.process_line_directive(
        pp_line_after(directive_tokens, directive_index),
        logical_file,
        line,
      )
    }
    return ""
  }
  if directive.kind != PpIdent {
    self.set_error("invalid preprocessor directive")
    return ""
  }
  match directive.text {
    "if" => {
      let cond = if active {
        self.eval_if(rest, physical_file, logical_file, line)
      } else {
        false
      }
      stack.push({
        parent_active: active,
        branch_active: active && cond,
        taken: active && cond,
        else_seen: false,
      })
    }
    "ifdef" | "ifndef" => {
      let idx = pp_first_non_space(rest)
      let defined = idx < rest.length() &&
        rest[idx].kind == PpIdent &&
        self.macros.contains(rest[idx].text)
      let cond = if directive.text == "ifdef" { defined } else { !defined }
      stack.push({
        parent_active: active,
        branch_active: active && cond,
        taken: active && cond,
        else_seen: false,
      })
    }
    "elifdef" | "elifndef" =>
      if stack.length() == 0 {
        self.set_error("#" + directive.text + " without matching #if")
      } else {
        let idx = stack.length() - 1
        let frame = stack[idx]
        if frame.else_seen {
          self.set_error("#" + directive.text + " after #else")
        } else {
          let name_index = pp_first_non_space(rest)
          let defined = name_index < rest.length() &&
            rest[name_index].kind == PpIdent &&
            self.macros.contains(rest[name_index].text)
          let branch_cond = if directive.text == "elifdef" {
            defined
          } else {
            !defined
          }
          let cond = frame.parent_active && !frame.taken && branch_cond
          stack[idx] = {
            parent_active: frame.parent_active,
            branch_active: cond,
            taken: frame.taken || cond,
            else_seen: false,
          }
        }
      }
    "elif" =>
      if stack.length() == 0 {
        self.set_error("#elif without matching #if")
      } else {
        let idx = stack.length() - 1
        let frame = stack[idx]
        if frame.else_seen {
          self.set_error("#elif after #else")
        } else {
          let cond = frame.parent_active &&
            !frame.taken &&
            self.eval_if(rest, physical_file, logical_file, line)
          stack[idx] = {
            parent_active: frame.parent_active,
            branch_active: cond,
            taken: frame.taken || cond,
            else_seen: false,
          }
        }
      }
    "else" =>
      if stack.length() == 0 {
        self.set_error("#else without matching #if")
      } else {
        let idx = stack.length() - 1
        let frame = stack[idx]
        if frame.else_seen {
          self.set_error("duplicate #else")
        } else {
          let cond = frame.parent_active && !frame.taken
          stack[idx] = {
            parent_active: frame.parent_active,
            branch_active: cond,
            taken: true,
            else_seen: true,
          }
        }
      }
    "endif" =>
      if stack.length() == 0 {
        self.set_error("#endif without matching #if")
      } else {
        ignore(stack.remove(stack.length() - 1))
      }
    "define" => if active { self.define_macro(rest) }
    "undef" =>
      if active {
        let idx = pp_first_non_space(rest)
        if idx < rest.length() && rest[idx].kind == PpIdent {
          self.macros.remove(rest[idx].text)
        }
      }
    "include" =>
      if active {
        return self.process_include(rest, physical_file, logical_file, line)
      }
    "include_next" =>
      if active {
        return self.process_include_next(
          rest, physical_file, logical_file, line,
        )
      }
    "error" =>
      if active {
        self.set_error("#error " + pp_tokens_to_source(rest))
      }
    "warning" | "ident" | "sccs" => ()
    "pragma" =>
      if active {
        let idx = pp_first_non_space(rest)
        if idx < rest.length() && rest[idx].is_ident("once") {
          self.once_files[physical_file] = true
        } else if idx < rest.length() && rest[idx].is_ident("pack") {
          // `#pragma pack` changes struct layout, so it has to survive
          // preprocessing and reach the parser rather than being dropped.
          return "#pragma " + pp_tokens_to_source(rest) + "\n"
        } else if idx < rest.length() && rest[idx].is_ident("kimicc_imacros") {
          ignore(
            self.process_include(
              pp_line_after(rest, idx + 1),
              physical_file,
              logical_file,
              line,
            ),
          )
        }
      }
    "line" =>
      if active {
        self.process_line_directive(rest, logical_file, line)
      }
    _ =>
      if active {
        self.set_error("unsupported preprocessor directive: #" + directive.text)
      }
  }
  ignore(after_hash)
  ""
}

///|
fn pp_is_directive_line(tokens : Array[PpToken]) -> Bool {
  let idx = pp_first_non_space(tokens)
  idx < tokens.length() && tokens[idx].is_punct("#")
}

///|
fn pp_is_unterminated_macro_error(error : PreprocessError?) -> Bool {
  match error {
    Some(Message(message)) =>
      message.has_prefix("unterminated macro invocation")
    None => false
  }
}

///|
fn Preprocessor::pending_ends_with_function_macro(
  self : Preprocessor,
  pending : Array[PpToken],
) -> Bool {
  let mut i = pending.length() - 1
  while i >= 0 {
    let tok = pending[i]
    if tok.is_whitespace() || tok.is_newline() {
      i -= 1
      continue
    }
    if tok.kind == PpIdent {
      match self.macros.get(tok.text) {
        Some(macro_) => return macro_.function_like
        None => return false
      }
    }
    return false
  }
  false
}

///|
fn Preprocessor::flush_pending_tokens(
  self : Preprocessor,
  pending : Array[PpToken],
  output : StringBuilder,
  file : String,
  file_remappable : Bool,
  line : Int,
  is_final : Bool,
) -> (Array[PpToken], Bool) {
  if pending.length() == 0 {
    return (pending, true)
  }
  if !is_final && self.pending_ends_with_function_macro(pending) {
    return (pending, false)
  }
  let expanded = self.expand_tokens(pending, {}, file, file_remappable, line, 0)
  if pp_is_unterminated_macro_error(self.error) && !is_final {
    self.error = None
    (pending, false)
  } else if self.error is Some(_) {
    (pending, false)
  } else {
    output.write_string(pp_tokens_to_source(expanded))
    output.write_char('\n')
    ([], true)
  }
}

///|
fn Preprocessor::process_source(
  self : Preprocessor,
  source : String,
  file : String,
) -> String {
  for active_file in self.include_stack {
    if active_file == file {
      return ""
    }
  }
  self.include_stack.push(file)
  let output = StringBuilder::new()
  if self.options.emit_line_markers {
    output.write_string("#line 1 ")
    output.write_string(pp_quote_string(file))
    output.write_char('\n')
  }
  let tokens = pp_tokenize(source)
  let stack : Array[ConditionalFrame] = []
  let mut line_tokens : Array[PpToken] = []
  let mut pending_tokens : Array[PpToken] = []
  let mut pending_line = 1
  let mut logical_file = file
  let mut logical_file_remappable = true
  let mut pending_file = logical_file
  let mut pending_file_remappable = logical_file_remappable
  let mut line = 1
  for tok in tokens {
    if tok.is_newline() {
      if pp_is_directive_line(line_tokens) {
        let (next_pending, _) = self.flush_pending_tokens(
          pending_tokens, output, pending_file, pending_file_remappable, pending_line,
          true,
        )
        pending_tokens = next_pending
        if self.error is Some(_) {
          ignore(self.include_stack.remove(self.include_stack.length() - 1))
          return output.to_string()
        }
        output.write_string(
          self.process_directive(line_tokens, stack, file, logical_file, line),
        )
        match self.line_control_file {
          Some(next_file) => {
            logical_file = next_file
            logical_file_remappable = false
            self.line_control_file = None
          }
          None => ()
        }
        match self.line_control_line {
          Some(next_line) => {
            line = next_line - 1
            self.line_control_line = None
          }
          None => ()
        }
      } else if self.is_active(stack) {
        if pending_tokens.length() == 0 {
          pending_line = line
          pending_file = logical_file
          pending_file_remappable = logical_file_remappable
        }
        for pending_token in line_tokens {
          pending_tokens.push(pending_token)
        }
        pending_tokens.push(pp_token(PpWhitespace, " "))
        let (next_pending, _) = self.flush_pending_tokens(
          pending_tokens, output, pending_file, pending_file_remappable, pending_line,
          false,
        )
        pending_tokens = next_pending
      }
      line_tokens = []
      line += 1
      if self.error is Some(_) {
        ignore(self.include_stack.remove(self.include_stack.length() - 1))
        return output.to_string()
      }
    } else {
      line_tokens.push(tok)
    }
  }
  if line_tokens.length() > 0 {
    if pp_is_directive_line(line_tokens) {
      let (next_pending, _) = self.flush_pending_tokens(
        pending_tokens, output, pending_file, pending_file_remappable, pending_line,
        true,
      )
      pending_tokens = next_pending
      if self.error is Some(_) {
        ignore(self.include_stack.remove(self.include_stack.length() - 1))
        return output.to_string()
      }
      output.write_string(
        self.process_directive(line_tokens, stack, file, logical_file, line),
      )
      match self.line_control_file {
        Some(next_file) => {
          logical_file = next_file
          logical_file_remappable = false
          self.line_control_file = None
        }
        None => ()
      }
      match self.line_control_line {
        Some(next_line) => {
          line = next_line - 1
          self.line_control_line = None
        }
        None => ()
      }
    } else if self.is_active(stack) {
      if pending_tokens.length() == 0 {
        pending_line = line
        pending_file = logical_file
        pending_file_remappable = logical_file_remappable
      }
      for pending_token in line_tokens {
        pending_tokens.push(pending_token)
      }
    }
  }
  let (next_pending, _) = self.flush_pending_tokens(
    pending_tokens, output, pending_file, pending_file_remappable, pending_line,
    true,
  )
  pending_tokens = next_pending
  ignore(pending_tokens)
  if stack.length() > 0 && self.error is None {
    self.set_error("unterminated conditional directive")
  }
  ignore(self.include_stack.remove(self.include_stack.length() - 1))
  output.to_string()
}

///|
fn pp_sorted_macro_names(macros : Map[String, Macro]) -> Array[String] {
  let names : Array[String] = []
  for pair in macros {
    names.push(pair.0)
  }
  for i in 1..<names.length() {
    let key = names[i]
    let mut j = i - 1
    while j >= 0 && names[j] > key {
      names[j + 1] = names[j]
      j -= 1
    }
    names[j + 1] = key
  }
  names
}

///|
fn pp_macro_param_source(macro_ : Macro, index : Int) -> String {
  let param = macro_.params[index]
  if macro_.variadic && index == macro_.params.length() - 1 {
    if param == "__VA_ARGS__" {
      "..."
    } else {
      param + "..."
    }
  } else {
    param
  }
}

///|
fn pp_macro_definition_source(name : String, macro_ : Macro) -> String {
  let buf = StringBuilder::new()
  buf.write_string("#define ")
  buf.write_string(name)
  if macro_.function_like {
    buf.write_char('(')
    for i in 0..<macro_.params.length() {
      if i > 0 {
        buf.write_char(',')
      }
      buf.write_string(pp_macro_param_source(macro_, i))
    }
    buf.write_char(')')
  }
  if macro_.replacement.length() > 0 {
    buf.write_char(' ')
    buf.write_string(pp_tokens_to_source(macro_.replacement))
  }
  buf.to_string()
}

///|
fn Preprocessor::dump_macro_definitions(self : Preprocessor) -> String {
  let buf = StringBuilder::new()
  for name in pp_sorted_macro_names(self.macros) {
    if !pp_macro_dump_skips_name(name) {
      match self.macros.get(name) {
        Some(macro_) => {
          buf.write_string(pp_macro_definition_source(name, macro_))
          buf.write_char('\n')
        }
        None => ()
      }
    }
  }
  buf.to_string()
}

///|
/// Preprocess one C translation unit into ordinary C source for the parser.
pub fn preprocess_with_dependencies(
  source : String,
  options : PreprocessOptions,
) -> Result[PreprocessResult, PreprocessError] {
  let pp = Preprocessor::new(options)
  let text = pp.process_source(source, options.filename)
  match pp.error {
    Some(err) => Err(err)
    None =>
      Ok({
        text,
        dependencies: pp.dependencies,
        dependency_records: pp.dependency_records,
      })
  }
}

///|
/// Run preprocessing and return the final macro table as `#define` lines.
pub fn dump_macros_with_dependencies(
  source : String,
  options : PreprocessOptions,
) -> Result[PreprocessResult, PreprocessError] {
  let pp = Preprocessor::new(options)
  ignore(pp.process_source(source, options.filename))
  match pp.error {
    Some(err) => Err(err)
    None =>
      Ok({
        text: pp.dump_macro_definitions(),
        dependencies: pp.dependencies,
        dependency_records: pp.dependency_records,
      })
  }
}

///|
/// Run preprocessing and return the final macro table as `#define` lines.
pub fn dump_macros(
  source : String,
  options : PreprocessOptions,
) -> Result[String, PreprocessError] {
  match dump_macros_with_dependencies(source, options) {
    Ok(result) => Ok(result.text)
    Err(err) => Err(err)
  }
}

///|
/// Preprocess one C translation unit into ordinary C source for the parser.
pub fn preprocess(
  source : String,
  options : PreprocessOptions,
) -> Result[String, PreprocessError] {
  match preprocess_with_dependencies(source, options) {
    Ok(result) => Ok(result.text)
    Err(err) => Err(err)
  }
}

///|
/// Preprocess and parse one C translation unit.
///
/// This is a convenience API; callers that need a hard preprocessing/parsing
/// boundary should call `preprocess` and `@parser.parse` separately.
pub fn parse(
  source : String,
  options : PreprocessOptions,
) -> Result[@parser.Program, PreprocessError] {
  match preprocess(source, options) {
    Ok(text) => Ok(@parser.parse(text))
    Err(err) => Err(err)
  }
}
