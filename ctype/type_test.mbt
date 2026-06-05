///|
test "ctype scalar predicates and aliases" {
  inspect(@ctype.Type::SInt.is_integer(), content="true")
  inspect(@ctype.Type::SInt.is_signed(), content="true")
  inspect(@ctype.Type::UInt.is_signed(), content="false")
  inspect(@ctype.Type::UInt.is_unsigned_integer(), content="true")
  inspect(@ctype.Type::Bool.is_unsigned_integer(), content="false")
  inspect(@ctype.Type::Atomic(UInt128).is_int128(), content="true")
  inspect(@ctype.Type::Bool.const_is_unsigned(), content="true")
  inspect(@ctype.Type::SLong.const_is_unsigned(), content="false")
  inspect(@ctype.Type::Double.is_floating(), content="true")
  inspect(@ctype.Type::Aligned(Float, 8).is_float_or_double(), content="true")
  inspect(@ctype.Type::SInt.to_unsigned(), content="UInt")
}

///|
test "ctype string literal helpers cover object and C lengths" {
  let buf = StringBuilder::new()
  buf.write_char('a')
  buf.write_char('\u0000')
  buf.write_string("bc")
  let value = buf.to_string()
  inspect(@ctype.string_literal_array_length(value), content="5")
  inspect(@ctype.string_literal_object_size(value), content="5")
  inspect(@ctype.string_literal_c_length(value), content="1")
  inspect(@ctype.string_literal_c_length_from(value, 0L), content="1")
  inspect(@ctype.string_literal_c_length_from(value, 2L), content="2")
  inspect(@ctype.string_literal_c_length_from(value, 3L), content="1")
  inspect(@ctype.string_literal_c_length_from(value, 4L), content="0")
}

///|
test "ctype type-shape helpers unwrap transparent wrappers" {
  inspect(
    @ctype.Type::Atomic(Aligned(Pointer(SInt), 8)).core_type(),
    content="Pointer(SInt)",
  )
  inspect(
    @ctype.Type::Aligned(Aligned(SInt, 4), 16).without_alignment(),
    content="SInt",
  )
  inspect(
    @ctype.Type::Aligned(Atomic(Aligned(SInt, 4)), 16).without_alignment(),
    content="Atomic(Aligned(SInt, 4))",
  )
  inspect(
    @ctype.Type::Atomic(Aligned(SInt, 4)).without_alignment(),
    content="Atomic(Aligned(SInt, 4))",
  )
  inspect(
    @ctype.Type::Aligned(Struct("__anon_struct_1"), 16).is_anonymous_aggregate(),
    content="true",
  )
  inspect(@ctype.Type::Struct("S").is_aggregate(), content="true")
  inspect(@ctype.Type::Array(SInt, 2).is_aggregate(), content="false")
  inspect(
    @ctype.Type::Atomic(Array(SInt, 2)).is_object_aggregate(),
    content="true",
  )
  match @ctype.Type::Pointer(Atomic(Struct("S"))).field_receiver() {
    Some(receiver) => inspect(receiver, content="Struct(S)")
    None => abort("expected aggregate field receiver")
  }
  match @ctype.Type::Pointer(SInt).field_receiver() {
    Some(_) => abort("unexpected aggregate field receiver")
    None => ()
  }
  match @ctype.Type::Pointer(SChar).pointer_or_array_element() {
    Some(elem) => inspect(elem, content="SChar")
    None => abort("expected pointer element")
  }
  match @ctype.Type::Atomic(Array(UChar, 4)).array_element() {
    Some(elem) => inspect(elem, content="UChar")
    None => abort("expected array element")
  }
  match @ctype.Type::Pointer(SChar).array_element() {
    Some(_) => abort("unexpected array element")
    None => ()
  }
}

///|
test "ctype generic and classify builtins expose parser-neutral type facts" {
  inspect(
    @ctype.generic_selection_control_type(Aligned(Array(SInt, 4), 16)),
    content="Pointer(SInt)",
  )
  inspect(
    @ctype.generic_types_compatible(Aligned(SInt, 4), SInt),
    content="true",
  )
  inspect(
    @ctype.generic_types_compatible(Array(SInt, 4), Pointer(SInt)),
    content="false",
  )
  inspect(@ctype.builtin_classify_type_code(SInt), content="1")
  inspect(@ctype.builtin_classify_type_code(Bool), content="4")
  inspect(
    @ctype.builtin_classify_type_code(Aligned(Atomic(Double), 8)),
    content="8",
  )
  inspect(@ctype.builtin_classify_type_code(Pointer(SInt)), content="5")
  inspect(@ctype.builtin_classify_type_code(Struct("S")), content="12")
  inspect(@ctype.builtin_classify_type_code(Union("U")), content="13")
}

///|
fn expect_const_int_width(ty : @ctype.Type, expected : Int) -> Unit {
  match ty.const_int_width() {
    Some(actual) =>
      if actual != expected {
        abort("unexpected integer constant width")
      }
    None => abort("expected integer constant width")
  }
}

///|
fn expect_no_const_int_width(ty : @ctype.Type) -> Unit {
  match ty.const_int_width() {
    Some(_) => abort("unexpected integer constant width")
    None => ()
  }
}

///|
test "ctype integer constant width helper covers scalar facts" {
  expect_const_int_width(Bool, 1)
  expect_const_int_width(SChar, 8)
  expect_const_int_width(Pointer(SInt), 64)
  expect_const_int_width(Atomic(UInt128), 128)
  expect_no_const_int_width(Double)
}

///|
test "ctype integer bit cast helper covers narrowing and signedness" {
  inspect(@ctype.Type::Bool.cast_integer_bits(42L), content="1")
  inspect(@ctype.Type::SChar.cast_integer_bits(255L), content="-1")
  inspect(@ctype.Type::UChar.cast_integer_bits(-1L), content="255")
  inspect(@ctype.Type::SInt.cast_integer_bits(0xffffffffL), content="-1")
  inspect(@ctype.Type::UInt.cast_integer_bits(-1L), content="4294967295")
  inspect(@ctype.Type::ULongLong.cast_integer_bits(-1L), content="-1")
  inspect(
    @ctype.Type::Atomic(Aligned(SChar, 4)).cast_integer_bits(255L),
    content="-1",
  )
}

///|
test "ctype integer constant helpers cover C arithmetic conversions" {
  let char_value = @ctype.integer_constant(255L, SChar)
  inspect(char_value.bits, content="-1")
  inspect(char_value.ty, content="SChar")
  let wrapped_uint = @ctype.integer_constant(-1L, UInt)
  inspect(wrapped_uint.bits, content="4294967295")
  inspect(wrapped_uint.ty, content="UInt")
  match
    @ctype.integer_constant_binary_arith(
      "+",
      @ctype.integer_constant(-1L, UInt),
      @ctype.integer_constant(2L, SInt),
    ) {
    Some(value) => {
      inspect(value.bits, content="1")
      inspect(value.ty, content="UInt")
    }
    None => abort("expected arithmetic result")
  }
  match
    @ctype.integer_constant_divide(
      "/",
      @ctype.integer_constant(-2L, ULongLong),
      @ctype.integer_constant(2L, SInt),
    ) {
    Some(value) => inspect(value.bits, content="9223372036854775807")
    None => abort("expected division result")
  }
  inspect(
    @ctype.integer_constant_rel_compare(
      ">",
      @ctype.integer_constant(-1L, UInt),
      @ctype.integer_constant(0L, SInt),
    ),
    content="true",
  )
  match
    @ctype.integer_constant_shift(
      ">>",
      @ctype.integer_constant(-1L, UInt),
      @ctype.integer_constant(1L, SInt),
    ) {
    Some(value) => inspect(value.bits, content="2147483647")
    None => abort("expected shift result")
  }
  match @ctype.integer_constant_unary("-", char_value) {
    Some(value) => {
      inspect(value.bits, content="1")
      inspect(value.ty, content="SInt")
    }
    None => abort("expected unary result")
  }
  match @ctype.integer_constant_unary("~", @ctype.integer_constant(0L, UChar)) {
    Some(value) => {
      inspect(value.bits, content="-1")
      inspect(value.ty, content="SInt")
    }
    None => abort("expected unary bit-not result")
  }
  match
    @ctype.integer_constant_logical(
      "||",
      @ctype.integer_constant(0L, SInt),
      @ctype.integer_constant(-1L, ULongLong),
    ) {
    Some(value) => {
      inspect(value.bits, content="1")
      inspect(value.ty, content="SInt")
    }
    None => abort("expected logical result")
  }
}

///|
fn expect_integer_builtin_constant(
  name : String,
  arg0 : @ctype.IntegerConstant?,
  arg1 : @ctype.IntegerConstant?,
  first_ty : @ctype.Type,
  expected_bits : Int64,
  expected_ty : @ctype.Type,
) -> Unit {
  match @ctype.integer_scalar_builtin_constant(name, arg0, arg1, first_ty) {
    Some(value) => {
      if value.bits != expected_bits {
        abort("unexpected integer builtin constant bits")
      }
      if value.ty != expected_ty {
        abort("unexpected integer builtin constant type")
      }
    }
    None => abort("expected integer builtin constant")
  }
}

///|
fn expect_integer_builtin_constant_from_folded_args(
  name : String,
  arg_count : Int,
  arg0 : @ctype.IntegerConstant?,
  arg1 : @ctype.IntegerConstant?,
  first_ty : @ctype.Type,
  expected_bits : Int64,
  expected_ty : @ctype.Type,
) -> Unit {
  match
    @ctype.integer_scalar_builtin_constant_from_folded_args(
      name, arg_count, arg0, arg1, first_ty,
    ) {
    Some(value) => {
      if value.bits != expected_bits {
        abort("unexpected integer builtin folded-arg bits")
      }
      if value.ty != expected_ty {
        abort("unexpected integer builtin folded-arg type")
      }
    }
    None => abort("expected integer builtin folded-arg constant")
  }
}

///|
test "ctype integer scalar builtin constant helper covers shared facts" {
  expect_integer_builtin_constant(
    "__builtin_flt_rounds",
    None,
    None,
    SInt,
    1L,
    SInt,
  )
  expect_integer_builtin_constant(
    "__builtin_abs",
    Some(@ctype.integer_constant(-7L, SInt)),
    None,
    SInt,
    7L,
    SInt,
  )
  expect_integer_builtin_constant(
    "__builtin_align_up",
    Some(@ctype.integer_constant(33L, ULong)),
    Some(@ctype.integer_constant(16L, SInt)),
    ULong,
    48L,
    ULong,
  )
  expect_integer_builtin_constant(
    "__builtin_is_aligned",
    Some(@ctype.integer_constant(32L, ULong)),
    Some(@ctype.integer_constant(16L, SInt)),
    ULong,
    1L,
    SInt,
  )
  expect_integer_builtin_constant(
    "__builtin_clz",
    Some(@ctype.integer_constant(0x10L, SInt)),
    None,
    SInt,
    27L,
    SInt,
  )
  expect_integer_builtin_constant(
    "__builtin_bswap32",
    Some(@ctype.integer_constant(0x01020304L, UInt)),
    None,
    UInt,
    0x04030201L,
    UInt,
  )
  expect_integer_builtin_constant(
    "__builtin_rotateleft32",
    Some(@ctype.integer_constant(0x12345678L, UInt)),
    Some(@ctype.integer_constant(8L, SInt)),
    UInt,
    0x34567812L,
    UInt,
  )
  expect_integer_builtin_constant_from_folded_args(
    "__builtin_rotateleft32",
    2,
    Some(@ctype.integer_constant(0x12345678L, UInt)),
    Some(@ctype.integer_constant(8L, SInt)),
    UInt,
    0x34567812L,
    UInt,
  )
  expect_integer_builtin_constant_from_folded_args(
    "__builtin_flt_rounds",
    0,
    None,
    None,
    SInt,
    1L,
    SInt,
  )
  match
    @ctype.integer_scalar_builtin_constant_from_folded_args(
      "__builtin_abs",
      1,
      None,
      None,
      SInt,
    ) {
    Some(_) => abort("unexpected missing folded first arg")
    None => ()
  }
  match
    @ctype.integer_scalar_builtin_constant_from_folded_args(
      "__builtin_align_up",
      2,
      Some(@ctype.integer_constant(33L, ULong)),
      None,
      ULong,
    ) {
    Some(_) => abort("unexpected missing folded second arg")
    None => ()
  }
  match
    @ctype.integer_scalar_builtin_constant(
      "__builtin_clz",
      Some(@ctype.integer_constant(0L, SInt)),
      None,
      SInt,
    ) {
    Some(_) => abort("unexpected clz zero fold")
    None => ()
  }
}

///|
test "ctype integer literal type helper covers signed int boundary" {
  inspect(@ctype.integer_literal_type(-2147483648L), content="SInt")
  inspect(@ctype.integer_literal_type(2147483647L), content="SInt")
  inspect(@ctype.integer_literal_type(-2147483649L), content="SLongLong")
  inspect(@ctype.integer_literal_type(2147483648L), content="SLongLong")
}

///|
test "ctype integer constant token type helper covers wrapped unsigned bits" {
  inspect(@ctype.integer_constant_token_type(0L), content="SInt")
  inspect(@ctype.integer_constant_token_type(2147483648L), content="SLongLong")
  inspect(@ctype.integer_constant_token_type(-1L), content="ULongLong")
}

///|
test "ctype generic integer builtin widths cover scalar facts" {
  inspect(@ctype.Type::UShort.generic_builtin_bswap_width(), content="16")
  inspect(@ctype.Type::UInt.generic_builtin_bswap_width(), content="32")
  inspect(@ctype.Type::ULongLong.generic_builtin_bswap_width(), content="64")
  inspect(
    @ctype.Type::Atomic(UChar).generic_builtin_bswap_width(),
    content="16",
  )
  inspect(@ctype.Type::Double.generic_builtin_bswap_width(), content="64")
  inspect(@ctype.Type::UShort.generic_builtin_rotate_width(), content="32")
  inspect(@ctype.Type::ULongLong.generic_builtin_rotate_width(), content="64")
}

///|
fn expect_integer_count_builtin_info(
  name : String,
  expected_kind : String,
  expected_width : Int,
) -> Unit {
  match @ctype.integer_count_builtin_info(name) {
    Some((kind, width)) => {
      if kind != expected_kind {
        abort("unexpected integer count builtin kind")
      }
      if width != expected_width {
        abort("unexpected integer count builtin width")
      }
    }
    None => abort("expected integer count builtin info")
  }
}

///|
fn expect_no_integer_count_builtin_info(name : String) -> Unit {
  match @ctype.integer_count_builtin_info(name) {
    Some(_) => abort("unexpected integer count builtin info")
    None => ()
  }
}

///|
test "ctype integer count builtin metadata covers runtime dispatch facts" {
  expect_integer_count_builtin_info("__builtin_clz", "clz", 32)
  expect_integer_count_builtin_info("__builtin_clzll", "clz", 64)
  expect_integer_count_builtin_info("__builtin_ctz", "ctz", 32)
  expect_integer_count_builtin_info("__builtin_ffsll", "ffs", 64)
  expect_integer_count_builtin_info("__builtin_popcount", "popcount", 32)
  expect_integer_count_builtin_info("__builtin_parityl", "parity", 64)
  expect_no_integer_count_builtin_info("__builtin_bswap32")
}

///|
fn expect_integer_abs_builtin_type(
  name : String,
  expected : @ctype.Type,
) -> Unit {
  match @ctype.integer_abs_builtin_type(name) {
    Some(actual) =>
      if actual != expected {
        abort("unexpected integer abs builtin type")
      }
    None => abort("expected integer abs builtin type")
  }
}

///|
fn expect_no_integer_abs_builtin_type(name : String) -> Unit {
  match @ctype.integer_abs_builtin_type(name) {
    Some(_) => abort("unexpected integer abs builtin type")
    None => ()
  }
}

///|
fn expect_integer_bswap_builtin_info(
  name : String,
  first_ty : @ctype.Type,
  expected_ty : @ctype.Type,
  expected_width : Int,
) -> Unit {
  match @ctype.integer_bswap_builtin_info(name, first_ty) {
    Some((actual_ty, actual_width)) => {
      if actual_ty != expected_ty {
        abort("unexpected integer bswap builtin type")
      }
      if actual_width != expected_width {
        abort("unexpected integer bswap builtin width")
      }
    }
    None => abort("expected integer bswap builtin info")
  }
}

///|
fn expect_integer_rotate_builtin_info(
  name : String,
  first_ty : @ctype.Type,
  expected_ty : @ctype.Type,
  expected_width : Int,
  expected_left : Bool,
) -> Unit {
  match @ctype.integer_rotate_builtin_info(name, first_ty) {
    Some((actual_ty, actual_width, actual_left)) => {
      if actual_ty != expected_ty {
        abort("unexpected integer rotate builtin type")
      }
      if actual_width != expected_width {
        abort("unexpected integer rotate builtin width")
      }
      if actual_left != expected_left {
        abort("unexpected integer rotate builtin direction")
      }
    }
    None => abort("expected integer rotate builtin info")
  }
}

///|
fn expect_integer_alignment_builtin_info(
  name : String,
  first_ty : @ctype.Type,
  expected_kind : String,
  expected_ty : @ctype.Type,
) -> Unit {
  match @ctype.integer_alignment_builtin_info(name, first_ty) {
    Some((actual_kind, actual_ty)) => {
      if actual_kind != expected_kind {
        abort("unexpected integer alignment builtin kind")
      }
      if actual_ty != expected_ty {
        abort("unexpected integer alignment builtin type")
      }
    }
    None => abort("expected integer alignment builtin info")
  }
}

///|
test "ctype integer unary runtime metadata covers abs bswap and rotates" {
  expect_integer_abs_builtin_type("__builtin_labs", SLong)
  expect_no_integer_abs_builtin_type("__builtin_ffs")
  expect_integer_bswap_builtin_info("__builtin_bswap16", UInt, UShort, 16)
  expect_integer_bswap_builtin_info("__builtin_bswap", ULongLong, ULongLong, 64)
  expect_integer_rotate_builtin_info(
    "__builtin_rotateleft",
    UShort,
    UShort,
    32,
    true,
  )
  expect_integer_rotate_builtin_info(
    "__builtin_rotateright64",
    UInt,
    ULongLong,
    64,
    false,
  )
}

///|
test "ctype integer alignment builtin metadata covers runtime dispatch facts" {
  expect_integer_alignment_builtin_info(
    "__builtin_is_aligned",
    ULong,
    "is_aligned",
    Bool,
  )
  expect_integer_alignment_builtin_info(
    "__builtin_align_up",
    ULongLong,
    "align_up",
    ULongLong,
  )
  expect_integer_alignment_builtin_info(
    "__builtin_align_down",
    SInt,
    "align_down",
    SInt,
  )
  match @ctype.integer_alignment_builtin_info("__builtin_bswap32", UInt) {
    Some(_) => abort("unexpected integer alignment builtin info")
    None => ()
  }
}

///|
test "ctype integer bit helpers cover builtin operations" {
  inspect(@ctype.mask_int_width(0x1234L, 8), content="52")
  inspect(@ctype.count_leading_zero_bits(0x10L, 32), content="27")
  inspect(@ctype.count_trailing_zero_bits(0x10L, 32), content="4")
  inspect(@ctype.first_set_bit(0x10L, 32), content="5")
  inspect(@ctype.count_one_bits(43L, 32), content="4")
  inspect(@ctype.byte_swap_bits(0x01020304L, 32), content="67305985")
  inspect(@ctype.rotate_bits(0x12345678L, 8L, 32, true), content="878082066")
  inspect(@ctype.rotate_bits(0x12345678L, 8L, 32, false), content="2014458966")
}

///|
fn expect_float_predicate(actual : Bool?, expected : Bool) -> Unit {
  match actual {
    Some(actual) =>
      if actual != expected {
        abort("unexpected floating predicate result")
      }
    None => abort("expected floating predicate result")
  }
}

///|
test "ctype floating helpers cover classification and comparisons" {
  inspect(@ctype.floating_abs(-4.5), content="4.5")
  inspect(@ctype.floating_signbit(-0.0), content="true")
  inspect(
    @ctype.floating_signbit(@ctype.floating_copysign(0.0, -1.0)),
    content="true",
  )
  match @ctype.floating_constant_binary_arith("*", 2.5, 4.0) {
    Some(value) => inspect(value, content="10")
    None => abort("expected floating arithmetic result")
  }
  match @ctype.floating_constant_unary("-", 2.5) {
    Some(value) => inspect(value, content="-2.5")
    None => abort("expected floating unary result")
  }
  inspect(@ctype.floating_constant_from_integer_bits(42L), content="42")
  inspect(@ctype.floating_constant_to_integer_bits(3.9), content="3")
  match @ctype.integer_constant_from_floating(260.0, UChar) {
    { bits, ty } => {
      inspect(bits, content="4")
      inspect(ty, content="UChar")
    }
  }
  match @ctype.floating_builtin_constant("__builtin_sqrt", Some(81.0), None) {
    Some(value) => inspect(value, content="9")
    None => abort("expected floating sqrt result")
  }
  match
    @ctype.floating_builtin_constant_from_folded_args(
      "__builtin_sqrt",
      Some(81.0),
      None,
    ) {
    Some(value) => inspect(value, content="9")
    None => abort("expected folded-arg floating sqrt result")
  }
  match
    @ctype.floating_builtin_constant(
      "__builtin_copysign",
      Some(0.0),
      Some(-1.0),
    ) {
    Some(value) => inspect(@ctype.floating_signbit(value), content="true")
    None => abort("expected floating copysign result")
  }
  let nan = 0.0 / 0.0
  let inf = 1.0 / 0.0
  match @ctype.floating_builtin_constant("__builtin_nan", None, None) {
    Some(value) =>
      expect_float_predicate(
        @ctype.floating_builtin_classify("__builtin_isnan", value),
        true,
      )
    None => abort("expected floating nan result")
  }
  match
    @ctype.floating_builtin_constant_from_folded_args(
      "__builtin_copysign",
      Some(0.0),
      None,
    ) {
    Some(_) => abort("unexpected folded-arg floating copysign result")
    None => ()
  }
  match
    @ctype.floating_builtin_constant_from_folded_args(
      "__builtin_nan",
      Some(1.0),
      Some(2.0),
    ) {
    Some(value) =>
      expect_float_predicate(
        @ctype.floating_builtin_classify("__builtin_isnan", value),
        true,
      )
    None => abort("expected zero-arg floating nan result")
  }
  match @ctype.floating_builtin_constant("__builtin_inf", None, None) {
    Some(value) =>
      expect_float_predicate(
        @ctype.floating_builtin_classify("__builtin_isinf", value),
        true,
      )
    None => abort("expected floating inf result")
  }
  match @ctype.floating_builtin_constant_arg_count("__builtin_copysign") {
    Some(count) => inspect(count, content="2")
    None => abort("expected floating builtin argument count")
  }
  match @ctype.floating_builtin_constant_bits_info("__builtin_nanf") {
    Some((bits, ty)) => {
      inspect(bits, content="2143289344")
      inspect(ty, content="Float")
    }
    None => abort("expected floating constant bits info")
  }
  match @ctype.floating_builtin_constant_bits_info("__builtin_inf") {
    Some((bits, ty)) => {
      inspect(bits, content="9218868437227405312")
      inspect(ty, content="Double")
    }
    None => abort("expected floating constant bits info")
  }
  match @ctype.floating_builtin_runtime_class_info("__builtin_signbitf") {
    Some((kind, ty)) => {
      inspect(kind, content="signbit")
      inspect(ty, content="Float")
    }
    None => abort("expected floating runtime class info")
  }
  match @ctype.floating_builtin_compare_op("__builtin_islessgreater") {
    Some(op) => inspect(op, content="<>")
    None => abort("expected floating compare operation")
  }
  match @ctype.floating_builtin_runtime_math_info("__builtin_copysign") {
    Some((op, ty, arity)) => {
      inspect(op, content="copysign")
      inspect(ty, content="Double")
      inspect(arity, content="2")
    }
    None => abort("expected floating runtime math info")
  }
  match @ctype.floating_builtin_runtime_math_info("__builtin_fabsf") {
    Some((op, ty, arity)) => {
      inspect(op, content="fabs")
      inspect(ty, content="Float")
      inspect(arity, content="1")
    }
    None => abort("expected floating runtime math info")
  }
  expect_float_predicate(
    @ctype.floating_builtin_classify("__builtin_isnan", nan),
    true,
  )
  expect_float_predicate(
    @ctype.floating_builtin_classify("__builtin_isinf", inf),
    true,
  )
  expect_float_predicate(
    @ctype.floating_builtin_classify("__builtin_isnormalf", 1.0e-40),
    false,
  )
  expect_float_predicate(
    @ctype.floating_builtin_classify("__builtin_isnormal", 1.0e-40),
    true,
  )
  expect_float_predicate(
    @ctype.floating_classify("signbit", -0.0, Double),
    true,
  )
  expect_float_predicate(@ctype.floating_compare(">", 2.0, 1.0), true)
  expect_float_predicate(@ctype.floating_compare("<>", nan, 1.0), false)
  expect_float_predicate(
    @ctype.floating_builtin_compare("__builtin_isunordered", nan, 1.0),
    true,
  )
}

///|
test "ctype integer promotion and common type helpers cover C ranks" {
  inspect(@ctype.Type::UShort.integer_promote(), content="SInt")
  inspect(@ctype.Type::Aligned(SShort, 8).integer_promote(), content="SInt")
  inspect(@ctype.Type::UInt.integer_rank(), content="3")
  inspect(@ctype.integer_common_type(UInt, SLong), content="SLong")
  inspect(@ctype.integer_common_type(ULong, SLongLong), content="ULongLong")
  inspect(@ctype.integer_common_type(Atomic(UChar), SShort), content="SInt")
}

///|
test "ctype scalar expression result type helpers cover parser-neutral rules" {
  inspect(
    @ctype.Type::LongDouble.is_floating_with_long_double(true),
    content="true",
  )
  inspect(
    @ctype.Type::LongDouble.is_floating_with_long_double(false),
    content="false",
  )
  inspect(@ctype.unary_numeric_result_type(UChar, true), content="SInt")
  inspect(
    @ctype.unary_numeric_result_type(LongDouble, true),
    content="LongDouble",
  )
  inspect(@ctype.binary_result_type("+", Float, Double, true), content="Double")
  inspect(
    @ctype.binary_result_type("+", LongDouble, SInt, true),
    content="LongDouble",
  )
  inspect(
    @ctype.binary_result_type("+", LongDouble, SInt, false),
    content="SInt",
  )
  inspect(@ctype.binary_result_type("<<", UShort, ULong, true), content="SInt")
  inspect(
    @ctype.binary_expr_result_type("+", Pointer(SInt), SLong, false, true),
    content="Pointer(SInt)",
  )
  inspect(
    @ctype.binary_expr_result_type("+", SLong, Array(Double, 2), false, true),
    content="Pointer(Double)",
  )
  inspect(
    @ctype.binary_expr_result_type(
      "-",
      Pointer(SChar),
      Array(SChar, 4),
      false,
      true,
    ),
    content="SLong",
  )
  inspect(
    @ctype.binary_expr_result_type("<<", SInt, SInt, true, true),
    content="ULongLong",
  )
  inspect(
    @ctype.ternary_result_type(Array(SChar, 4), Pointer(Void), true),
    content="Pointer(SChar)",
  )
  inspect(@ctype.ternary_result_type(SInt, ULong, true), content="ULong")
  inspect(
    @ctype.ternary_result_type(LongDouble, Double, false),
    content="Double",
  )
}

///|
test "ctype layout helpers cover scalar ABI facts" {
  inspect(@ctype.Type::Pointer(SInt).size(), content="8")
  inspect(@ctype.Type::Array(SChar, 4).size(), content="4")
  inspect(@ctype.Type::Aligned(SInt, 16).align(), content="16")
}

///|
test "ctype atomic target helper covers builtin pointer targets" {
  inspect(@ctype.Type::Pointer(Atomic(UInt)).atomic_target(), content="UInt")
  inspect(
    @ctype.Type::Array(Aligned(SShort, 16), 3).atomic_target(),
    content="SShort",
  )
  inspect(@ctype.Type::SInt.atomic_target(), content="SLongLong")
}

///|
fn expect_builtin_fixed_return_type(
  name : String,
  expected : @ctype.Type,
) -> Unit {
  match @ctype.builtin_fixed_return_type(name) {
    Some(actual) =>
      if actual != expected {
        abort("unexpected fixed builtin return type")
      }
    None => abort("expected fixed builtin return type")
  }
}

///|
fn expect_no_builtin_fixed_return_type(name : String) -> Unit {
  match @ctype.builtin_fixed_return_type(name) {
    Some(_) => abort("unexpected fixed builtin return type")
    None => ()
  }
}

///|
test "ctype builtin fixed return types cover parser-neutral facts" {
  expect_builtin_fixed_return_type("__builtin_memcpy", Pointer(Void))
  expect_builtin_fixed_return_type("__builtin_fabsf", Float)
  expect_builtin_fixed_return_type("__builtin_islessgreater", SInt)
  expect_builtin_fixed_return_type("__builtin_add_overflow", Bool)
  expect_builtin_fixed_return_type("__builtin_va_start", Void)
  expect_no_builtin_fixed_return_type("__builtin_bswap")
  expect_no_builtin_fixed_return_type("__atomic_fetch_add")
}

///|
fn expect_builtin_overflow_op(name : String, expected : String) -> Unit {
  match @ctype.builtin_overflow_op(name) {
    Some(actual) =>
      if actual != expected {
        abort("unexpected builtin overflow op")
      }
    None => abort("expected builtin overflow op")
  }
}

///|
fn expect_no_builtin_overflow_op(name : String) -> Unit {
  match @ctype.builtin_overflow_op(name) {
    Some(_) => abort("unexpected builtin overflow op")
    None => ()
  }
}

///|
test "ctype builtin overflow operator facts cover arithmetic families" {
  expect_builtin_overflow_op("__builtin_add_overflow", "+")
  expect_builtin_overflow_op("__builtin_uaddll_overflow", "+")
  expect_builtin_overflow_op("__builtin_sub_overflow", "-")
  expect_builtin_overflow_op("__builtin_ssubll_overflow", "-")
  expect_builtin_overflow_op("__builtin_mul_overflow", "*")
  expect_builtin_overflow_op("__builtin_umulll_overflow", "*")
  expect_no_builtin_overflow_op("__builtin_bswap")
}

///|
fn expect_builtin_return_rule(
  name : String,
  expected : @ctype.BuiltinReturnRule,
) -> Unit {
  match @ctype.builtin_return_rule(name) {
    Some(actual) =>
      if actual != expected {
        abort("unexpected builtin return rule")
      }
    None => abort("expected builtin return rule")
  }
}

///|
fn expect_no_builtin_return_rule(name : String) -> Unit {
  match @ctype.builtin_return_rule(name) {
    Some(_) => abort("unexpected builtin return rule")
    None => ()
  }
}

///|
fn expect_builtin_return_condition_arg_index(
  name : String,
  expected_index : Int,
) -> Unit {
  match @ctype.builtin_return_condition_arg_index(name) {
    Some(index) =>
      if index != expected_index {
        abort("unexpected builtin return condition argument index")
      }
    None => abort("expected builtin return condition argument index")
  }
}

///|
fn expect_no_builtin_return_condition_arg_index(name : String) -> Unit {
  match @ctype.builtin_return_condition_arg_index(name) {
    Some(_) => abort("unexpected builtin return condition argument index")
    None => ()
  }
}

///|
test "ctype builtin return rules cover argument-dependent facts" {
  expect_builtin_return_rule("__builtin_fabsf", BuiltinFixedReturn(Float))
  expect_builtin_return_rule(
    "__atomic_fetch_add",
    BuiltinAtomicTargetReturn(SLongLong),
  )
  expect_builtin_return_rule("__builtin_bswap", BuiltinFirstArgReturn(UInt))
  expect_builtin_return_rule("__builtin_expect", BuiltinFirstArgReturn(SInt))
  expect_builtin_return_rule(
    "__builtin_assume_aligned",
    BuiltinFirstArgReturn(Pointer(Void)),
  )
  expect_builtin_return_rule("__builtin_choose_expr", BuiltinChooseExprReturn)
  expect_builtin_return_condition_arg_index("__builtin_choose_expr", 0)
  expect_no_builtin_return_condition_arg_index("__builtin_expect")
  expect_no_builtin_return_rule("__not_a_builtin")
}

///|
fn expect_builtin_return_type(
  name : String,
  arg_types : Array[@ctype.Type],
  choose_cond : Int64?,
  expected : @ctype.Type,
) -> Unit {
  match @ctype.builtin_return_type(name, arg_types, choose_cond) {
    Some(actual) =>
      if actual != expected {
        abort("unexpected builtin return type")
      }
    None => abort("expected builtin return type")
  }
}

///|
fn expect_no_builtin_return_type(name : String) -> Unit {
  match @ctype.builtin_return_type(name, [], None) {
    Some(_) => abort("unexpected builtin return type")
    None => ()
  }
}

///|
test "ctype builtin return type resolver applies argument facts" {
  expect_builtin_return_type("__builtin_fabs", [], None, Double)
  expect_builtin_return_type("__builtin_expect", [ULong], None, ULong)
  expect_builtin_return_type(
    "__atomic_fetch_add",
    [Pointer(Atomic(UInt))],
    None,
    UInt,
  )
  expect_builtin_return_type(
    "__builtin_choose_expr",
    [SInt, SLong, Double],
    Some(1L),
    SLong,
  )
  expect_builtin_return_type(
    "__builtin_choose_expr",
    [SInt, SLong, Double],
    Some(0L),
    Double,
  )
  expect_builtin_return_type(
    "__builtin_choose_expr",
    [SInt, SLong, Double],
    None,
    SLong,
  )
  expect_builtin_return_type("__builtin_choose_expr", [], None, SInt)
  expect_no_builtin_return_type("__not_a_builtin")
}

///|
fn expect_builtin_identity_call_info(
  name : String,
  expected_kind : String,
  expected_side_effect_arg : Int,
) -> Unit {
  match @ctype.builtin_identity_call_info(name) {
    Some((kind, side_effect_arg)) => {
      if kind != expected_kind {
        abort("unexpected builtin identity call kind")
      }
      if side_effect_arg != expected_side_effect_arg {
        abort("unexpected builtin identity side-effect argument")
      }
    }
    None => abort("expected builtin identity call info")
  }
}

///|
test "ctype builtin identity call metadata covers hint call shapes" {
  expect_builtin_identity_call_info("__builtin_expect", "expect", 1)
  expect_builtin_identity_call_info(
    "__builtin_expect_with_probability", "expect", 1,
  )
  expect_builtin_identity_call_info(
    "__builtin_assume_aligned", "assume_aligned", 2,
  )
  expect_builtin_identity_call_info(
    "__builtin_unpredictable", "unpredictable", -1,
  )
  expect_builtin_identity_call_info(
    "__builtin_extract_return_addr", "return_address_transform", -1,
  )
  match @ctype.builtin_identity_call_info("__builtin_bswap32") {
    Some(_) => abort("unexpected builtin identity call info")
    None => ()
  }
}

///|
fn expect_builtin_noop_call_info(name : String, expected_kind : String) -> Unit {
  match @ctype.builtin_noop_call_info(name) {
    Some(kind) =>
      if kind != expected_kind {
        abort("unexpected builtin no-op call kind")
      }
    None => abort("expected builtin no-op call info")
  }
}

///|
test "ctype builtin no-op call metadata covers operand evaluation rules" {
  expect_builtin_noop_call_info("__builtin_assume", "ignore_all")
  expect_builtin_noop_call_info("__builtin_prefetch", "eval_first")
  expect_builtin_noop_call_info("__builtin___clear_cache", "eval_all")
  expect_builtin_noop_call_info("__builtin_clear_cache", "eval_all")
  match @ctype.builtin_noop_call_info("__builtin_expect") {
    Some(_) => abort("unexpected builtin no-op call info")
    None => ()
  }
}

///|
fn expect_builtin_address_query_info(
  name : String,
  expected_kind : String,
) -> Unit {
  match @ctype.builtin_address_query_info(name) {
    Some(kind) =>
      if kind != expected_kind {
        abort("unexpected builtin address query kind")
      }
    None => abort("expected builtin address query info")
  }
}

///|
test "ctype builtin address query metadata covers frame and return address" {
  expect_builtin_address_query_info("__builtin_frame_address", "frame_address")
  expect_builtin_address_query_info(
    "__builtin_return_address", "return_address",
  )
  match @ctype.builtin_address_query_info("__builtin_frob_return_addr") {
    Some(_) => abort("unexpected builtin address query info")
    None => ()
  }
}

///|
fn expect_builtin_trap_call_info(name : String, expected_kind : String) -> Unit {
  match @ctype.builtin_trap_call_info(name) {
    Some(kind) =>
      if kind != expected_kind {
        abort("unexpected builtin trap call kind")
      }
    None => abort("expected builtin trap call info")
  }
}

///|
test "ctype builtin trap metadata covers trap-like calls" {
  expect_builtin_trap_call_info("__builtin_trap", "trap")
  expect_builtin_trap_call_info("__builtin_unreachable", "trap")
  match @ctype.builtin_trap_call_info("__builtin_assume") {
    Some(_) => abort("unexpected builtin trap call info")
    None => ()
  }
}

///|
fn expect_builtin_fence_call_info(
  name : String,
  expected_kind : String,
  expected_arg_count : Int,
) -> Unit {
  match @ctype.builtin_fence_call_info(name) {
    Some((kind, arg_count)) => {
      if kind != expected_kind {
        abort("unexpected builtin fence call kind")
      }
      if arg_count != expected_arg_count {
        abort("unexpected builtin fence call argument count")
      }
    }
    None => abort("expected builtin fence call info")
  }
}

///|
test "ctype builtin fence metadata covers sync and atomic fences" {
  expect_builtin_fence_call_info("__sync_synchronize", "sync_synchronize", 0)
  expect_builtin_fence_call_info(
    "__atomic_thread_fence", "atomic_thread_fence", 1,
  )
  expect_builtin_fence_call_info(
    "__c11_atomic_signal_fence", "atomic_signal_fence", 1,
  )
  match @ctype.builtin_fence_call_info("__builtin_assume") {
    Some(_) => abort("unexpected builtin fence call info")
    None => ()
  }
}

///|
fn expect_builtin_fixed_int_constant_call_info(
  name : String,
  expected_value : Int64,
  expected_arg_count : Int,
) -> Unit {
  match @ctype.builtin_fixed_int_constant_call_info(name) {
    Some((value, arg_count)) => {
      if value != expected_value {
        abort("unexpected builtin fixed integer constant value")
      }
      if arg_count != expected_arg_count {
        abort("unexpected builtin fixed integer constant argument count")
      }
    }
    None => abort("expected builtin fixed integer constant call info")
  }
}

///|
test "ctype builtin fixed integer constant metadata covers flt rounds" {
  expect_builtin_fixed_int_constant_call_info("__builtin_flt_rounds", 1L, 0)
  match @ctype.builtin_fixed_int_constant_call_info("__builtin_constant_p") {
    Some(_) => abort("unexpected builtin fixed integer constant call info")
    None => ()
  }
}

///|
fn expect_builtin_stack_alloc_call_info(
  name : String,
  expected_op : String,
  expected_arg_count : Int,
) -> Unit {
  match @ctype.builtin_stack_alloc_call_info(name) {
    Some((op, arg_count)) => {
      if op != expected_op {
        abort("unexpected builtin stack allocation op")
      }
      if arg_count != expected_arg_count {
        abort("unexpected builtin stack allocation argument count")
      }
    }
    None => abort("expected builtin stack allocation call info")
  }
}

///|
test "ctype builtin stack allocation metadata covers alloca calls" {
  expect_builtin_stack_alloc_call_info("__builtin_alloca", "alloca", 1)
  expect_builtin_stack_alloc_call_info(
    "__builtin_alloca_with_align", "alloca_align", 2,
  )
  match @ctype.builtin_stack_alloc_call_info("__builtin_malloc") {
    Some(_) => abort("unexpected builtin stack allocation call info")
    None => ()
  }
}

///|
fn expect_builtin_va_setup_call_info(
  name : String,
  expected_op : String,
  expected_arg_count : Int,
) -> Unit {
  match @ctype.builtin_va_setup_call_info(name) {
    Some((op, arg_count)) => {
      if op != expected_op {
        abort("unexpected builtin va setup op")
      }
      if arg_count != expected_arg_count {
        abort("unexpected builtin va setup argument count")
      }
    }
    None => abort("expected builtin va setup call info")
  }
}

///|
test "ctype builtin va setup metadata covers varargs setup calls" {
  expect_builtin_va_setup_call_info("__builtin_va_start", "va_start", 2)
  expect_builtin_va_setup_call_info("__builtin_va_copy", "va_copy", 2)
  expect_builtin_va_setup_call_info("__builtin_va_end", "va_end", 1)
  match @ctype.builtin_va_setup_call_info("__builtin_alloca") {
    Some(_) => abort("unexpected builtin va setup call info")
    None => ()
  }
}

///|
fn expect_builtin_darwin_fd_helper_call_info(
  name : String,
  expected_op : String,
  expected_arg_count : Int,
) -> Unit {
  match @ctype.builtin_darwin_fd_helper_call_info(name) {
    Some((op, arg_count)) => {
      if op != expected_op {
        abort("unexpected Darwin fd helper op")
      }
      if arg_count != expected_arg_count {
        abort("unexpected Darwin fd helper argument count")
      }
    }
    None => abort("expected Darwin fd helper call info")
  }
}

///|
test "ctype Darwin fd helper metadata covers fd_set helpers" {
  expect_builtin_darwin_fd_helper_call_info("__darwin_fd_set", "set", 2)
  expect_builtin_darwin_fd_helper_call_info("__darwin_fd_clr", "clr", 2)
  expect_builtin_darwin_fd_helper_call_info("__darwin_fd_isset", "isset", 2)
  match @ctype.builtin_darwin_fd_helper_call_info("__builtin_va_start") {
    Some(_) => abort("unexpected Darwin fd helper call info")
    None => ()
  }
}

///|
fn expect_builtin_zero_memory_call_info(
  name : String,
  expected_op : String,
  expected_arg_count : Int,
) -> Unit {
  match @ctype.builtin_zero_memory_call_info(name) {
    Some((op, arg_count)) => {
      if op != expected_op {
        abort("unexpected builtin zero-memory op")
      }
      if arg_count != expected_arg_count {
        abort("unexpected builtin zero-memory argument count")
      }
    }
    None => abort("expected builtin zero-memory call info")
  }
}

///|
test "ctype builtin zero-memory metadata covers bzero" {
  expect_builtin_zero_memory_call_info("__builtin_bzero", "bzero", 2)
  match @ctype.builtin_zero_memory_call_info("__builtin_memset") {
    Some(_) => abort("unexpected builtin zero-memory call info")
    None => ()
  }
}

///|
fn expect_builtin_object_size_call_info(
  name : String,
  expected_kind : String,
) -> Unit {
  match @ctype.builtin_object_size_call_info(name) {
    Some(kind) =>
      if kind != expected_kind {
        abort("unexpected builtin object-size kind")
      }
    None => abort("expected builtin object-size call info")
  }
}

///|
test "ctype builtin object-size metadata covers object size queries" {
  expect_builtin_object_size_call_info("__builtin_object_size", "object_size")
  expect_builtin_object_size_call_info(
    "__builtin_dynamic_object_size", "dynamic_object_size",
  )
  inspect(
    @ctype.object_size_fact_result(Some({ whole: 9, subobject: 3 }), 0L),
    content="9",
  )
  inspect(
    @ctype.object_size_fact_result(Some({ whole: 9, subobject: 3 }), 1L),
    content="3",
  )
  inspect(@ctype.object_size_fact_result(None, 0L), content="-1")
  inspect(@ctype.object_size_fact_result(None, 2L), content="0")
  match @ctype.builtin_object_size_call_info("__builtin_constant_p") {
    Some(_) => abort("unexpected builtin object-size call info")
    None => ()
  }
}

///|
fn expect_builtin_constant_query_call_info(
  name : String,
  expected_kind : String,
) -> Unit {
  match @ctype.builtin_constant_query_call_info(name) {
    Some(kind) =>
      if kind != expected_kind {
        abort("unexpected builtin constant-query kind")
      }
    None => abort("expected builtin constant-query call info")
  }
}

///|
test "ctype builtin constant-query metadata covers constant p" {
  expect_builtin_constant_query_call_info("__builtin_constant_p", "constant_p")
  match @ctype.builtin_constant_query_result("constant_p", true) {
    Some(1L) => ()
    _ => abort("unexpected constant-query true result")
  }
  match @ctype.builtin_constant_query_result("constant_p", false) {
    Some(0L) => ()
    _ => abort("unexpected constant-query false result")
  }
  match @ctype.builtin_constant_query_result("not_constant_p", true) {
    None => ()
    Some(_) => abort("unexpected unknown constant-query result")
  }
  match @ctype.builtin_constant_query_call_info("__builtin_object_size") {
    Some(_) => abort("unexpected builtin constant-query call info")
    None => ()
  }
}

///|
fn expect_builtin_atomic_lock_free_call_info(
  name : String,
  expected_kind : String,
  expected_evaluate_pointer : Bool,
) -> Unit {
  match @ctype.builtin_atomic_lock_free_call_info(name) {
    Some((kind, evaluate_pointer)) => {
      if kind != expected_kind {
        abort("unexpected atomic lock-free builtin kind")
      }
      if evaluate_pointer != expected_evaluate_pointer {
        abort("unexpected atomic lock-free pointer evaluation")
      }
    }
    None => abort("expected atomic lock-free builtin metadata")
  }
}

///|
test "ctype atomic lock-free builtin metadata covers query shape" {
  expect_builtin_atomic_lock_free_call_info(
    "__atomic_always_lock_free", "always_lock_free", false,
  )
  expect_builtin_atomic_lock_free_call_info(
    "__atomic_is_lock_free", "is_lock_free", true,
  )
  expect_builtin_atomic_lock_free_call_info(
    "__c11_atomic_is_lock_free", "is_lock_free", false,
  )
  if !@ctype.builtin_atomic_lock_free_size_supported(1L) ||
    !@ctype.builtin_atomic_lock_free_size_supported(2L) ||
    !@ctype.builtin_atomic_lock_free_size_supported(4L) ||
    !@ctype.builtin_atomic_lock_free_size_supported(8L) {
    abort("expected standard atomic lock-free byte widths")
  }
  if @ctype.builtin_atomic_lock_free_size_supported(3L) ||
    @ctype.builtin_atomic_lock_free_size_supported(16L) {
    abort("unexpected atomic lock-free byte width")
  }
  match @ctype.builtin_atomic_lock_free_call_info("__atomic_load_n") {
    Some(_) => abort("unexpected atomic lock-free builtin metadata")
    None => ()
  }
}

///|
fn expect_builtin_atomic_load_store_call_info(
  name : String,
  expected_op : String,
  expected_min_arg_count : Int,
) -> Unit {
  match @ctype.builtin_atomic_load_store_call_info(name) {
    Some((op, min_arg_count)) => {
      if op != expected_op {
        abort("unexpected atomic load/store builtin op")
      }
      if min_arg_count != expected_min_arg_count {
        abort("unexpected atomic load/store builtin argument count")
      }
    }
    None => abort("expected atomic load/store builtin metadata")
  }
}

///|
test "ctype atomic load-store builtin metadata covers operation shape" {
  expect_builtin_atomic_load_store_call_info("__atomic_load", "load_ptr", 3)
  expect_builtin_atomic_load_store_call_info("__atomic_load_n", "load_value", 2)
  expect_builtin_atomic_load_store_call_info(
    "__c11_atomic_load", "load_value", 2,
  )
  expect_builtin_atomic_load_store_call_info("__atomic_store", "store_ptr", 3)
  expect_builtin_atomic_load_store_call_info(
    "__atomic_store_n", "store_value", 2,
  )
  expect_builtin_atomic_load_store_call_info(
    "__c11_atomic_store", "store_value", 2,
  )
  match @ctype.builtin_atomic_load_store_call_info("__atomic_clear") {
    Some(_) => abort("unexpected atomic load/store builtin metadata")
    None => ()
  }
}

///|
fn expect_builtin_atomic_zero_store_call_info(
  name : String,
  expected_op : String,
  expected_min_arg_count : Int,
) -> Unit {
  match @ctype.builtin_atomic_zero_store_call_info(name) {
    Some((op, min_arg_count)) => {
      if op != expected_op {
        abort("unexpected atomic zero-store builtin op")
      }
      if min_arg_count != expected_min_arg_count {
        abort("unexpected atomic zero-store builtin argument count")
      }
    }
    None => abort("expected atomic zero-store builtin metadata")
  }
}

///|
test "ctype atomic zero-store builtin metadata covers operation shape" {
  expect_builtin_atomic_zero_store_call_info("__atomic_clear", "clear", 1)
  expect_builtin_atomic_zero_store_call_info(
    "__sync_lock_release", "release", 1,
  )
  match @ctype.builtin_atomic_zero_store_call_info("__atomic_store_n") {
    Some(_) => abort("unexpected atomic zero-store builtin metadata")
    None => ()
  }
}

///|
fn expect_builtin_atomic_exchange_call_info(
  name : String,
  expected_op : String,
  expected_min_arg_count : Int,
  expected_extra_start : Int,
) -> Unit {
  match @ctype.builtin_atomic_exchange_call_info(name) {
    Some((op, min_arg_count, extra_start)) => {
      if op != expected_op {
        abort("unexpected atomic exchange builtin op")
      }
      if min_arg_count != expected_min_arg_count {
        abort("unexpected atomic exchange builtin argument count")
      }
      if extra_start != expected_extra_start {
        abort("unexpected atomic exchange builtin extra argument start")
      }
    }
    None => abort("expected atomic exchange builtin metadata")
  }
}

///|
test "ctype atomic exchange builtin metadata covers operation shape" {
  expect_builtin_atomic_exchange_call_info(
    "__atomic_exchange", "exchange_ptr", 4, 3,
  )
  expect_builtin_atomic_exchange_call_info(
    "__atomic_test_and_set", "test_and_set", 1, 1,
  )
  expect_builtin_atomic_exchange_call_info(
    "__atomic_exchange_n", "exchange_value", 2, 2,
  )
  expect_builtin_atomic_exchange_call_info(
    "__c11_atomic_exchange", "exchange_value", 2, 2,
  )
  expect_builtin_atomic_exchange_call_info(
    "__sync_swap", "sync_exchange_value", 2, 2,
  )
  expect_builtin_atomic_exchange_call_info(
    "__sync_lock_test_and_set", "sync_exchange_value", 2, 2,
  )
  match @ctype.builtin_atomic_exchange_call_info("__atomic_store_n") {
    Some(_) => abort("unexpected atomic exchange builtin metadata")
    None => ()
  }
}

///|
fn expect_builtin_atomic_compare_exchange_call_info(
  name : String,
  expected_op : String,
  expected_min_arg_count : Int,
  expected_extra_start : Int,
) -> Unit {
  match @ctype.builtin_atomic_compare_exchange_call_info(name) {
    Some((op, min_arg_count, extra_start)) => {
      if op != expected_op {
        abort("unexpected atomic compare-exchange builtin op")
      }
      if min_arg_count != expected_min_arg_count {
        abort("unexpected atomic compare-exchange builtin argument count")
      }
      if extra_start != expected_extra_start {
        abort("unexpected atomic compare-exchange builtin extra argument start")
      }
    }
    None => abort("expected atomic compare-exchange builtin metadata")
  }
}

///|
test "ctype atomic compare-exchange builtin metadata covers operation shape" {
  expect_builtin_atomic_compare_exchange_call_info(
    "__atomic_compare_exchange", "compare_exchange_ptr", 6, 3,
  )
  expect_builtin_atomic_compare_exchange_call_info(
    "__atomic_compare_exchange_n", "compare_exchange_value", 3, 3,
  )
  expect_builtin_atomic_compare_exchange_call_info(
    "__c11_atomic_compare_exchange_strong", "compare_exchange_value", 3, 3,
  )
  expect_builtin_atomic_compare_exchange_call_info(
    "__c11_atomic_compare_exchange_weak", "compare_exchange_value", 3, 3,
  )
  expect_builtin_atomic_compare_exchange_call_info(
    "__sync_bool_compare_and_swap", "sync_compare_exchange_bool", 3, 3,
  )
  expect_builtin_atomic_compare_exchange_call_info(
    "__sync_val_compare_and_swap", "sync_compare_exchange_value", 3, 3,
  )
  match
    @ctype.builtin_atomic_compare_exchange_call_info("__atomic_exchange_n") {
    Some(_) => abort("unexpected atomic compare-exchange builtin metadata")
    None => ()
  }
}

///|
fn expect_builtin_atomic_update_op(
  name : String,
  expected_op : String,
  expected_return_new : Bool,
) -> Unit {
  match @ctype.builtin_atomic_update_op(name) {
    Some((op, return_new)) =>
      if op != expected_op || return_new != expected_return_new {
        abort("unexpected atomic update builtin metadata")
      }
    None => abort("expected atomic update builtin metadata")
  }
}

///|
fn expect_builtin_atomic_update_call_info(
  name : String,
  expected_op : String,
  expected_return_new : Bool,
  expected_min_arg_count : Int,
  expected_extra_start : Int,
) -> Unit {
  match @ctype.builtin_atomic_update_call_info(name) {
    Some((op, return_new, min_arg_count, extra_start)) => {
      if op != expected_op || return_new != expected_return_new {
        abort("unexpected atomic update builtin metadata")
      }
      if min_arg_count != expected_min_arg_count {
        abort("unexpected atomic update builtin argument count")
      }
      if extra_start != expected_extra_start {
        abort("unexpected atomic update builtin extra argument start")
      }
    }
    None => abort("expected atomic update builtin call metadata")
  }
}

///|
fn expect_no_builtin_atomic_update_op(name : String) -> Unit {
  match @ctype.builtin_atomic_update_op(name) {
    Some(_) => abort("unexpected atomic update builtin metadata")
    None => ()
  }
}

///|
test "ctype atomic update builtin metadata covers operation and result shape" {
  expect_builtin_atomic_update_op("__atomic_add_fetch", "+", true)
  expect_builtin_atomic_update_op("__atomic_fetch_nand", "~&", false)
  expect_builtin_atomic_update_op("__sync_fetch_and_umax", "umax", false)
  expect_builtin_atomic_update_op("__sync_nand_and_fetch", "~&", true)
  expect_builtin_atomic_update_call_info("__atomic_add_fetch", "+", true, 2, 2)
  expect_builtin_atomic_update_call_info(
    "__c11_atomic_fetch_xor", "^", false, 2, 2,
  )
  expect_builtin_atomic_update_call_info(
    "__sync_fetch_and_min", "min", false, 2, 2,
  )
  expect_no_builtin_atomic_update_op("__not_an_atomic_update_builtin")
}

///|
fn expect_builtin_libcall_info(
  actual : (String, Int)?,
  expected_symbol : String,
  expected_count : Int,
) -> Unit {
  match actual {
    Some((symbol, count)) =>
      if symbol != expected_symbol || count != expected_count {
        abort("unexpected builtin libcall info")
      }
    None => abort("expected builtin libcall info")
  }
}

///|
test "ctype builtin libcall lowering facts cover memory and string wrappers" {
  expect_builtin_libcall_info(
    @ctype.builtin_memory_libcall_info("__builtin___memcpy_chk", 4),
    "memcpy",
    3,
  )
  expect_builtin_libcall_info(
    @ctype.builtin_memory_libcall_info("__builtin_stpncpy", 3),
    "stpncpy",
    3,
  )
  inspect(@ctype.builtin_memory_libcall_arg_type("memset", 1), content="SInt")
  inspect(
    @ctype.builtin_memory_libcall_arg_type("stpcpy", 0),
    content="Pointer(SChar)",
  )
  expect_builtin_libcall_info(
    @ctype.builtin_heap_libcall_info("__builtin_realloc", 2),
    "realloc",
    2,
  )
  inspect(
    @ctype.builtin_heap_libcall_arg_type("realloc", 0),
    content="Pointer(Void)",
  )
  inspect(@ctype.builtin_heap_libcall_arg_type("strndup", 1), content="ULong")
  expect_builtin_libcall_info(
    @ctype.builtin_length_libcall_info("__builtin_strnlen", 2),
    "strnlen",
    2,
  )
  inspect(@ctype.builtin_length_libcall_arg_type(0), content="Pointer(SChar)")
  inspect(@ctype.builtin_length_libcall_arg_type(1), content="ULong")
  expect_builtin_libcall_info(
    @ctype.builtin_compare_libcall_info("__builtin_bcmp", 3),
    "bcmp",
    3,
  )
  inspect(
    @ctype.builtin_compare_libcall_arg_type("strncmp", 2),
    content="ULong",
  )
  expect_builtin_libcall_info(
    @ctype.builtin_search_libcall_info("__builtin_memmem", 4),
    "memmem",
    4,
  )
  inspect(
    @ctype.builtin_search_libcall_arg_type("memmem", 2),
    content="Pointer(Void)",
  )
  expect_builtin_libcall_info(
    @ctype.builtin_span_libcall_info("__builtin_strpbrk", 2),
    "strpbrk",
    2,
  )
  expect_builtin_libcall_info(
    @ctype.builtin_strl_libcall_info("__builtin___strlcat_chk", 4),
    "strlcat",
    3,
  )
  inspect(@ctype.builtin_strl_libcall_arg_type(2), content="ULong")
  match @ctype.builtin_memory_libcall_info("__builtin_memcpy", 2) {
    Some(_) => abort("unexpected wrong-arity libcall info")
    None => ()
  }
}

///|
test "ctype builtin printf libcall lowering facts cover checked wrappers" {
  match @ctype.builtin_printf_libcall_symbol("__builtin___snprintf_chk", 6) {
    Some(symbol) => inspect(symbol, content="snprintf")
    None => abort("expected printf libcall symbol")
  }
  match @ctype.builtin_printf_source_indexes("__builtin___snprintf_chk", 6) {
    Some(indexes) => {
      inspect(indexes.length(), content="4")
      inspect(indexes[0], content="0")
      inspect(indexes[1], content="1")
      inspect(indexes[2], content="4")
      inspect(indexes[3], content="5")
      inspect(
        @ctype.builtin_printf_source_index_used(indexes, 2),
        content="false",
      )
      inspect(
        @ctype.builtin_printf_source_index_used(indexes, 5),
        content="true",
      )
    }
    None => abort("expected printf source indexes")
  }
  match @ctype.builtin_printf_libcall_arg_type("snprintf", 1) {
    Some(ty) => inspect(ty, content="ULong")
    None => abort("expected snprintf arg type")
  }
  match @ctype.builtin_printf_libcall_arg_type("fprintf", 0) {
    Some(ty) => inspect(ty, content="Pointer(Void)")
    None => abort("expected fprintf arg type")
  }
  inspect(@ctype.builtin_printf_libcall_variadic("printf"), content="true")
  inspect(@ctype.builtin_printf_libcall_variadic("vprintf"), content="false")
  match @ctype.builtin_printf_source_indexes("__builtin___printf_chk", 1) {
    Some(_) => abort("unexpected wrong-arity printf indexes")
    None => ()
  }
}

///|
test "ctype object-size facts cover builtin modes" {
  let fact : @ctype.ObjectSizeFact = { whole: 12, subobject: 5 }
  inspect(fact.value(0L), content="12")
  inspect(fact.value(1L), content="5")
  inspect(@ctype.object_size_unknown(0L), content="-1")
  inspect(@ctype.object_size_unknown(2L), content="0")
  match fact.subtract_offset(3) {
    Some(remaining) => {
      inspect(remaining.value(0L), content="9")
      inspect(remaining.value(1L), content="2")
    }
    None => abort("expected remaining object-size fact")
  }
  match fact.subtract_offset(6) {
    Some(_) => abort("unexpected remaining object-size fact")
    None => ()
  }
  match fact.array_element(4, 2, 2L) {
    Some(remaining) => {
      inspect(remaining.value(0L), content="8")
      inspect(remaining.value(1L), content="1")
    }
    None => abort("expected array element object-size fact")
  }
  match fact.array_element(4, 2, 5L) {
    Some(_) => abort("unexpected array element object-size fact")
    None => ()
  }
  match fact.member_field(4, 3) {
    Some(member_fact) => {
      inspect(member_fact.value(0L), content="8")
      inspect(member_fact.value(1L), content="3")
    }
    None => abort("expected member object-size fact")
  }
}
