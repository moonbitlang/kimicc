///|
/// Parser-neutral builtin return-type classification.
///
/// `BuiltinFixedReturn` carries a complete return type. `BuiltinFirstArgReturn`
/// and `BuiltinAtomicTargetReturn` carry the fallback type used when no first
/// argument is available; callers that have expression context substitute the
/// first argument type or its atomic target type. `BuiltinChooseExprReturn`
/// leaves branch selection to callers that can fold the condition expression.
pub(all) enum BuiltinReturnRule {
  BuiltinFixedReturn(Type)
  BuiltinFirstArgReturn(Type)
  BuiltinAtomicTargetReturn(Type)
  BuiltinChooseExprReturn
} derive(Eq)

///|
/// Mode-independent object-size fact for `__builtin_object_size`-style queries.
///
/// `whole` is the byte count remaining in the complete modeled object, while
/// `subobject` is the byte count remaining in the nearest modeled subobject.
pub(all) struct ObjectSizeFact {
  whole : Int
  subobject : Int
} derive(Eq)

///|
/// Returns the C builtin fallback value for an unknown object size.
pub fn object_size_unknown(mode : Int64) -> Int64 {
  if (mode & 2L) != 0L {
    0L
  } else {
    -1L
  }
}

///|
/// Selects the whole-object or nearest-subobject size for the requested mode.
pub fn ObjectSizeFact::value(self : ObjectSizeFact, mode : Int64) -> Int {
  if (mode & 1L) != 0L {
    self.subobject
  } else {
    self.whole
  }
}

///|
/// Selects the modeled object-size fact or the C builtin fallback.
pub fn object_size_fact_result(fact : ObjectSizeFact?, mode : Int64) -> Int64 {
  match fact {
    Some(fact) => fact.value(mode).to_int64()
    None => object_size_unknown(mode)
  }
}

///|
/// Applies a byte offset to both modeled object-size facts.
pub fn ObjectSizeFact::subtract_offset(
  self : ObjectSizeFact,
  offset : Int,
) -> ObjectSizeFact? {
  if offset < 0 || offset > self.whole || offset > self.subobject {
    None
  } else {
    Some({ whole: self.whole - offset, subobject: self.subobject - offset })
  }
}

///|
/// Applies an array element index to a modeled object-size fact.
pub fn ObjectSizeFact::array_element(
  self : ObjectSizeFact,
  length : Int,
  elem_size : Int,
  index : Int64,
) -> ObjectSizeFact? {
  if index < 0L {
    None
  } else {
    let index = index.to_int()
    if index > length {
      None
    } else {
      self.subtract_offset(index * elem_size)
    }
  }
}

///|
/// Applies a member offset while resetting the nearest-subobject size.
pub fn ObjectSizeFact::member_field(
  self : ObjectSizeFact,
  offset : Int,
  member_size : Int,
) -> ObjectSizeFact? {
  match self.subtract_offset(offset) {
    Some(fact) => Some({ whole: fact.whole, subobject: member_size })
    None => None
  }
}

///|
fn generic_strip_type(ty : Type) -> Type {
  match ty {
    Aligned(inner, _) => generic_strip_type(inner)
    _ => ty
  }
}

///|
/// Applies the C11 `_Generic` controlling-expression type adjustment.
///
/// Alignment wrappers are transparent for this query, and array expressions
/// decay to the corresponding pointer type before association matching.
pub fn generic_selection_control_type(ty : Type) -> Type {
  match generic_strip_type(ty) {
    Array(elem, _) => Pointer(elem)
    other => other
  }
}

///|
/// Returns whether two types match for `_Generic` association selection and
/// `__builtin_types_compatible_p`.
pub fn generic_types_compatible(lhs : Type, rhs : Type) -> Bool {
  generic_strip_type(lhs) == generic_strip_type(rhs)
}

///|
/// Returns GCC-compatible category codes for the covered
/// `__builtin_classify_type` type classes.
pub fn builtin_classify_type_code(ty : Type) -> Int64 {
  match generic_strip_type(ty) {
    Atomic(inner) => builtin_classify_type_code(inner)
    Void => 0
    Bool => 4
    Float | Double | LongDouble => 8
    Float16 => abort("_Float16 classification is not supported")
    Float128 => abort("__float128 classification is not supported")
    Pointer(_) | Array(_, _) | FuncPtr(_, _, _) => 5
    Struct(_) => 12
    Union(_) => 13
    Named(name) =>
      abort("Cannot classify a named type without its layout: " + name)
    SChar
    | UChar
    | SShort
    | UShort
    | SInt
    | UInt
    | SLong
    | ULong
    | SLongLong
    | ULongLong
    | SInt128
    | UInt128 => 1
    Aligned(inner, _) => builtin_classify_type_code(inner)
  }
}

///|
/// Return types for builtin functions whose type does not depend on argument
/// expressions.
///
/// Argument-dependent builtins such as generic rotate/bswap, `expect`, and
/// atomic read-modify-write helpers are intentionally left to callers that have
/// expression-type context. The shared atomic target-type rule lives on
/// `Type::atomic_target`.
pub fn builtin_fixed_return_type(name : String) -> Type? {
  match name {
    "__builtin_object_size" | "__builtin_dynamic_object_size" => Some(ULong)
    "__builtin_return_address"
    | "__builtin_frame_address"
    | "__builtin_extract_return_addr"
    | "__builtin_frob_return_addr" => Some(Pointer(Void))
    "__builtin_alloca"
    | "__builtin_alloca_with_align"
    | "__builtin_malloc"
    | "__builtin_calloc"
    | "__builtin_realloc" => Some(Pointer(Void))
    "__builtin_free" => Some(Void)
    "__builtin_strdup" | "__builtin_strndup" => Some(Pointer(SChar))
    "__builtin_memcpy"
    | "__builtin___memcpy_chk"
    | "__builtin_mempcpy"
    | "__builtin___mempcpy_chk"
    | "__builtin_memmove"
    | "__builtin___memmove_chk"
    | "__builtin_memset"
    | "__builtin___memset_chk"
    | "__builtin_memccpy"
    | "__builtin_memmem"
    | "__builtin_memchr" => Some(Pointer(Void))
    "__builtin_strlen"
    | "__builtin_strnlen"
    | "__builtin_strspn"
    | "__builtin_strcspn" => Some(ULong)
    "__builtin_memcmp"
    | "__builtin_bcmp"
    | "__builtin_strcmp"
    | "__builtin_strncmp" => Some(SInt)
    "__builtin_strcpy"
    | "__builtin___strcpy_chk"
    | "__builtin_strcat"
    | "__builtin___strcat_chk"
    | "__builtin_stpcpy"
    | "__builtin___stpcpy_chk"
    | "__builtin_strncpy"
    | "__builtin___strncpy_chk"
    | "__builtin_stpncpy"
    | "__builtin___stpncpy_chk"
    | "__builtin_strncat"
    | "__builtin___strncat_chk"
    | "__builtin_strchr"
    | "__builtin_strrchr"
    | "__builtin_strstr"
    | "__builtin_strpbrk" => Some(Pointer(SChar))
    "__builtin___strlcpy_chk" | "__builtin___strlcat_chk" => Some(ULong)
    "__builtin___snprintf_chk"
    | "__builtin_snprintf"
    | "__builtin_vsnprintf"
    | "__builtin___vsnprintf_chk"
    | "__builtin___sprintf_chk"
    | "__builtin_sprintf"
    | "__builtin_vsprintf"
    | "__builtin___vsprintf_chk"
    | "__builtin___printf_chk"
    | "__builtin_printf"
    | "__builtin_vprintf"
    | "__builtin___vprintf_chk"
    | "__builtin___fprintf_chk"
    | "__builtin___vfprintf_chk" => Some(SInt)
    "__builtin_fabsf"
    | "__builtin_copysignf"
    | "__builtin_sqrtf"
    | "__builtin_nanf"
    | "__builtin_huge_valf"
    | "__builtin_inff" => Some(Float)
    "__builtin_fabs"
    | "__builtin_copysign"
    | "__builtin_sqrt"
    | "__builtin_nan"
    | "__builtin_huge_val"
    | "__builtin_inf" => Some(Double)
    "__builtin_fabsl"
    | "__builtin_copysignl"
    | "__builtin_sqrtl"
    | "__builtin_nanl"
    | "__builtin_huge_vall"
    | "__builtin_infl" => Some(LongDouble)
    "__atomic_test_and_set"
    | "__atomic_compare_exchange"
    | "__atomic_compare_exchange_n"
    | "__c11_atomic_compare_exchange_strong"
    | "__c11_atomic_compare_exchange_weak"
    | "__sync_bool_compare_and_swap"
    | "__atomic_always_lock_free"
    | "__atomic_is_lock_free"
    | "__c11_atomic_is_lock_free" => Some(Bool)
    "__atomic_clear"
    | "__atomic_exchange"
    | "__atomic_load"
    | "__atomic_store"
    | "__atomic_store_n"
    | "__atomic_thread_fence"
    | "__atomic_signal_fence"
    | "__c11_atomic_store"
    | "__c11_atomic_thread_fence"
    | "__c11_atomic_signal_fence"
    | "__sync_synchronize"
    | "__sync_lock_release" => Some(Void)
    "__builtin_constant_p"
    | "__builtin_isgreater"
    | "__builtin_isgreaterequal"
    | "__builtin_isless"
    | "__builtin_islessequal"
    | "__builtin_islessgreater"
    | "__builtin_isunordered"
    | "__builtin_isnan"
    | "__builtin_isnanf"
    | "__builtin_isnanl"
    | "__builtin_isinf"
    | "__builtin_isinff"
    | "__builtin_isinfl"
    | "__builtin_isfinite"
    | "__builtin_isfinitef"
    | "__builtin_isfinitel"
    | "__builtin_isnormal"
    | "__builtin_isnormalf"
    | "__builtin_isnormall"
    | "__builtin_signbit"
    | "__builtin_signbitf"
    | "__builtin_signbitl"
    | "__builtin_clz"
    | "__builtin_clzl"
    | "__builtin_clzll"
    | "__builtin_ctz"
    | "__builtin_ctzl"
    | "__builtin_ctzll"
    | "__builtin_ffs"
    | "__builtin_ffsl"
    | "__builtin_ffsll"
    | "__builtin_popcount"
    | "__builtin_popcountl"
    | "__builtin_popcountll"
    | "__builtin_parity"
    | "__builtin_parityl"
    | "__builtin_parityll"
    | "__builtin_abs"
    | "__builtin_flt_rounds" => Some(SInt)
    "__builtin_labs" => Some(SLong)
    "__builtin_llabs" => Some(SLongLong)
    "__builtin_is_aligned" => Some(Bool)
    "__builtin_unreachable"
    | "__builtin_trap"
    | "__builtin_assume"
    | "__builtin_prefetch"
    | "__builtin___clear_cache"
    | "__builtin_clear_cache"
    | "__builtin_bzero"
    | "__builtin_va_start"
    | "__builtin_va_end"
    | "__builtin_va_copy" => Some(Void)
    "__builtin_add_overflow"
    | "__builtin_sub_overflow"
    | "__builtin_mul_overflow"
    | "__builtin_sadd_overflow"
    | "__builtin_saddl_overflow"
    | "__builtin_saddll_overflow"
    | "__builtin_uadd_overflow"
    | "__builtin_uaddl_overflow"
    | "__builtin_uaddll_overflow"
    | "__builtin_ssub_overflow"
    | "__builtin_ssubl_overflow"
    | "__builtin_ssubll_overflow"
    | "__builtin_usub_overflow"
    | "__builtin_usubl_overflow"
    | "__builtin_usubll_overflow"
    | "__builtin_smul_overflow"
    | "__builtin_smull_overflow"
    | "__builtin_smulll_overflow"
    | "__builtin_umul_overflow"
    | "__builtin_umull_overflow"
    | "__builtin_umulll_overflow" => Some(Bool)
    "__builtin_bswap16" => Some(UShort)
    "__builtin_bswap32"
    | "__builtin_rotateleft32"
    | "__builtin_rotateright32" => Some(UInt)
    "__builtin_bswap64"
    | "__builtin_rotateleft64"
    | "__builtin_rotateright64" => Some(ULongLong)
    _ => None
  }
}

///|
/// Return-type rule for builtin functions known to the C semantic layer.
pub fn builtin_return_rule(name : String) -> BuiltinReturnRule? {
  match builtin_fixed_return_type(name) {
    Some(ty) => return Some(BuiltinFixedReturn(ty))
    None => ()
  }
  match name {
    "__atomic_load_n"
    | "__c11_atomic_load"
    | "__atomic_add_fetch"
    | "__atomic_sub_fetch"
    | "__atomic_and_fetch"
    | "__atomic_or_fetch"
    | "__atomic_xor_fetch"
    | "__atomic_nand_fetch"
    | "__atomic_fetch_add"
    | "__atomic_fetch_sub"
    | "__atomic_fetch_and"
    | "__atomic_fetch_or"
    | "__atomic_fetch_xor"
    | "__atomic_fetch_nand"
    | "__atomic_exchange_n"
    | "__c11_atomic_fetch_add"
    | "__c11_atomic_fetch_sub"
    | "__c11_atomic_fetch_and"
    | "__c11_atomic_fetch_or"
    | "__c11_atomic_fetch_xor"
    | "__c11_atomic_exchange"
    | "__sync_val_compare_and_swap"
    | "__sync_fetch_and_add"
    | "__sync_fetch_and_sub"
    | "__sync_fetch_and_and"
    | "__sync_fetch_and_or"
    | "__sync_fetch_and_xor"
    | "__sync_fetch_and_nand"
    | "__sync_fetch_and_max"
    | "__sync_fetch_and_min"
    | "__sync_fetch_and_umax"
    | "__sync_fetch_and_umin"
    | "__sync_add_and_fetch"
    | "__sync_sub_and_fetch"
    | "__sync_and_and_fetch"
    | "__sync_or_and_fetch"
    | "__sync_xor_and_fetch"
    | "__sync_nand_and_fetch"
    | "__sync_swap"
    | "__sync_lock_test_and_set" => Some(BuiltinAtomicTargetReturn(SLongLong))
    "__builtin_assume_aligned" => Some(BuiltinFirstArgReturn(Pointer(Void)))
    "__builtin_expect"
    | "__builtin_expect_with_probability"
    | "__builtin_unpredictable" => Some(BuiltinFirstArgReturn(SInt))
    "__builtin_align_up" | "__builtin_align_down" =>
      Some(BuiltinFirstArgReturn(ULong))
    "__builtin_bswap" | "__builtin_rotateleft" | "__builtin_rotateright" =>
      Some(BuiltinFirstArgReturn(UInt))
    "__builtin_choose_expr" => Some(BuiltinChooseExprReturn)
    _ => None
  }
}

///|
/// Source argument index whose folded constant value is needed to resolve a
/// builtin return-type rule.
pub fn builtin_return_condition_arg_index(name : String) -> Int? {
  match builtin_return_rule(name) {
    Some(BuiltinChooseExprReturn) => Some(0)
    _ => None
  }
}

///|
/// Resolves a builtin return type from parser-neutral argument type facts.
///
/// `choose_cond` is the folded first argument for `__builtin_choose_expr`, when
/// available. A non-constant or missing condition follows the existing parser
/// and MIR convention of selecting the then-branch type.
pub fn builtin_return_type(
  name : String,
  arg_types : Array[Type],
  choose_cond : Int64?,
) -> Type? {
  match builtin_return_rule(name) {
    Some(BuiltinFixedReturn(ty)) => Some(ty)
    Some(BuiltinAtomicTargetReturn(default_ty)) =>
      if arg_types.length() > 0 {
        Some(arg_types[0].atomic_target())
      } else {
        Some(default_ty)
      }
    Some(BuiltinFirstArgReturn(default_ty)) =>
      if arg_types.length() > 0 {
        Some(arg_types[0])
      } else {
        Some(default_ty)
      }
    Some(BuiltinChooseExprReturn) =>
      if arg_types.length() >= 3 {
        match choose_cond {
          Some(0L) => Some(arg_types[2])
          Some(_) | None => Some(arg_types[1])
        }
      } else {
        Some(SInt)
      }
    None => None
  }
}

///|
/// Parser-neutral call-shape metadata for builtins that return their first
/// argument while optionally preserving one non-result operand's side effects.
///
/// The second tuple item is the source argument index to evaluate for side
/// effects after the result operand, or `-1` when there is no extra operand.
pub fn builtin_identity_call_info(name : String) -> (String, Int)? {
  match name {
    "__builtin_expect" | "__builtin_expect_with_probability" =>
      Some(("expect", 1))
    "__builtin_assume_aligned" => Some(("assume_aligned", 2))
    "__builtin_unpredictable" => Some(("unpredictable", -1))
    "__builtin_extract_return_addr" | "__builtin_frob_return_addr" =>
      Some(("return_address_transform", -1))
    _ => None
  }
}

///|
/// Parser-neutral operand-evaluation rule for no-op builtins that produce a
/// zero/void result but may still evaluate selected operands for side effects.
pub fn builtin_noop_call_info(name : String) -> String? {
  match name {
    "__builtin_assume" => Some("ignore_all")
    "__builtin_prefetch" => Some("eval_first")
    "__builtin___clear_cache" | "__builtin_clear_cache" => Some("eval_all")
    _ => None
  }
}

///|
/// Parser-neutral operation selected by frame/return address query builtins.
pub fn builtin_address_query_info(name : String) -> String? {
  match name {
    "__builtin_frame_address" => Some("frame_address")
    "__builtin_return_address" => Some("return_address")
    _ => None
  }
}

///|
/// Parser-neutral operation selected by source trap-like builtins.
pub fn builtin_trap_call_info(name : String) -> String? {
  match name {
    "__builtin_trap" | "__builtin_unreachable" => Some("trap")
    _ => None
  }
}

///|
/// Parser-neutral operation selected by synchronization fence builtins.
///
/// The integer is the source argument count expected by strict MIR lowering.
pub fn builtin_fence_call_info(name : String) -> (String, Int)? {
  match name {
    "__sync_synchronize" => Some(("sync_synchronize", 0))
    "__atomic_thread_fence" | "__c11_atomic_thread_fence" =>
      Some(("atomic_thread_fence", 1))
    "__atomic_signal_fence" | "__c11_atomic_signal_fence" =>
      Some(("atomic_signal_fence", 1))
    _ => None
  }
}

///|
/// Parser-neutral fixed integer value returned by side-effect-free builtins.
///
/// The integer in the tuple tail is the expected source argument count.
pub fn builtin_fixed_int_constant_call_info(name : String) -> (Int64, Int)? {
  match name {
    "__builtin_flt_rounds" => Some((1L, 0))
    _ => None
  }
}

///|
/// Parser-neutral operation selected by stack-allocation builtins.
///
/// The integer is the source argument count expected by strict MIR lowering.
pub fn builtin_stack_alloc_call_info(name : String) -> (String, Int)? {
  match name {
    "__builtin_alloca" => Some(("alloca", 1))
    "__builtin_alloca_with_align" => Some(("alloca_align", 2))
    _ => None
  }
}

///|
/// Parser-neutral operation selected by variadic setup builtins.
///
/// The integer is the source argument count expected by strict MIR lowering.
pub fn builtin_va_setup_call_info(name : String) -> (String, Int)? {
  match name {
    "__builtin_va_start" => Some(("va_start", 2))
    "__builtin_va_copy" => Some(("va_copy", 2))
    "__builtin_va_end" => Some(("va_end", 1))
    _ => None
  }
}

///|
/// Parser-neutral operation selected by Darwin fd_set helper builtins.
///
/// The integer is the source argument count expected by strict MIR lowering.
pub fn builtin_darwin_fd_helper_call_info(name : String) -> (String, Int)? {
  match name {
    "__darwin_fd_set" => Some(("set", 2))
    "__darwin_fd_clr" => Some(("clr", 2))
    "__darwin_fd_isset" => Some(("isset", 2))
    _ => None
  }
}

///|
/// Parser-neutral operation selected by zero-memory builtins.
///
/// The integer is the source argument count expected by strict MIR lowering.
pub fn builtin_zero_memory_call_info(name : String) -> (String, Int)? {
  match name {
    "__builtin_bzero" => Some(("bzero", 2))
    _ => None
  }
}

///|
/// Parser-neutral object-size builtin classification.
pub fn builtin_object_size_call_info(name : String) -> String? {
  match name {
    "__builtin_object_size" => Some("object_size")
    "__builtin_dynamic_object_size" => Some("dynamic_object_size")
    _ => None
  }
}

///|
/// Parser-neutral constant-query builtin classification.
pub fn builtin_constant_query_call_info(name : String) -> String? {
  match name {
    "__builtin_constant_p" => Some("constant_p")
    _ => None
  }
}

///|
/// Returns the integer result for parser-neutral constant-query builtins.
pub fn builtin_constant_query_result(
  kind : String,
  operand_is_constant : Bool,
) -> Int64? {
  match kind {
    "constant_p" => Some(if operand_is_constant { 1L } else { 0L })
    _ => None
  }
}

///|
/// Parser-neutral atomic lock-free query builtin classification.
///
/// The boolean indicates whether the optional pointer operand is evaluated for
/// source side effects.
pub fn builtin_atomic_lock_free_call_info(name : String) -> (String, Bool)? {
  match name {
    "__atomic_always_lock_free" => Some(("always_lock_free", false))
    "__atomic_is_lock_free" => Some(("is_lock_free", true))
    "__c11_atomic_is_lock_free" => Some(("is_lock_free", false))
    _ => None
  }
}

///|
/// Byte widths modeled as lock-free by the compiler builtins.
pub fn builtin_atomic_lock_free_size_supported(size : Int64) -> Bool {
  size == 1L || size == 2L || size == 4L || size == 8L
}

///|
/// Parser-neutral atomic load/store builtin lowering metadata.
///
/// The string is the MIR/direct-backend operation family, and the integer is
/// the minimum source argument count expected by strict MIR lowering.
pub fn builtin_atomic_load_store_call_info(name : String) -> (String, Int)? {
  match name {
    "__atomic_load" => Some(("load_ptr", 3))
    "__atomic_load_n" | "__c11_atomic_load" => Some(("load_value", 2))
    "__atomic_store" => Some(("store_ptr", 3))
    "__atomic_store_n" | "__c11_atomic_store" => Some(("store_value", 2))
    _ => None
  }
}

///|
/// Parser-neutral atomic helper metadata for builtins that store integer zero.
///
/// The string is the operation family, and the integer is the minimum source
/// argument count expected by strict MIR lowering.
pub fn builtin_atomic_zero_store_call_info(name : String) -> (String, Int)? {
  match name {
    "__atomic_clear" => Some(("clear", 1))
    "__sync_lock_release" => Some(("release", 1))
    _ => None
  }
}

///|
/// Parser-neutral atomic exchange builtin lowering metadata.
///
/// The string is the operation family. The integers are the minimum source
/// argument count and the first source argument index used as memory-order or
/// legacy sync extra operands.
pub fn builtin_atomic_exchange_call_info(name : String) -> (String, Int, Int)? {
  match name {
    "__atomic_exchange" => Some(("exchange_ptr", 4, 3))
    "__atomic_test_and_set" => Some(("test_and_set", 1, 1))
    "__atomic_exchange_n" | "__c11_atomic_exchange" =>
      Some(("exchange_value", 2, 2))
    "__sync_swap" | "__sync_lock_test_and_set" =>
      Some(("sync_exchange_value", 2, 2))
    _ => None
  }
}

///|
/// Parser-neutral atomic compare-exchange builtin lowering metadata.
///
/// The string is the operation family. The integers are the minimum source
/// argument count and the first source argument index used as memory-order or
/// legacy sync extra operands.
pub fn builtin_atomic_compare_exchange_call_info(
  name : String,
) -> (String, Int, Int)? {
  match name {
    "__atomic_compare_exchange" => Some(("compare_exchange_ptr", 6, 3))
    "__atomic_compare_exchange_n"
    | "__c11_atomic_compare_exchange_strong"
    | "__c11_atomic_compare_exchange_weak" =>
      Some(("compare_exchange_value", 3, 3))
    "__sync_bool_compare_and_swap" => Some(("sync_compare_exchange_bool", 3, 3))
    "__sync_val_compare_and_swap" => Some(("sync_compare_exchange_value", 3, 3))
    _ => None
  }
}

///|
/// Parser-neutral atomic read-modify-write builtin lowering metadata.
///
/// The string is the integer update operation used by MIR. The boolean is true
/// when the source builtin returns the value after the update. The integers are
/// the minimum source argument count and the first source argument index used
/// as memory-order or legacy sync extra operands.
pub fn builtin_atomic_update_call_info(
  name : String,
) -> (String, Bool, Int, Int)? {
  match name {
    "__atomic_add_fetch" => Some(("+", true, 2, 2))
    "__atomic_sub_fetch" => Some(("-", true, 2, 2))
    "__atomic_and_fetch" => Some(("&", true, 2, 2))
    "__atomic_or_fetch" => Some(("|", true, 2, 2))
    "__atomic_xor_fetch" => Some(("^", true, 2, 2))
    "__atomic_nand_fetch" => Some(("~&", true, 2, 2))
    "__atomic_fetch_add" | "__c11_atomic_fetch_add" => Some(("+", false, 2, 2))
    "__atomic_fetch_sub" | "__c11_atomic_fetch_sub" => Some(("-", false, 2, 2))
    "__atomic_fetch_and" | "__c11_atomic_fetch_and" => Some(("&", false, 2, 2))
    "__atomic_fetch_or" | "__c11_atomic_fetch_or" => Some(("|", false, 2, 2))
    "__atomic_fetch_xor" | "__c11_atomic_fetch_xor" => Some(("^", false, 2, 2))
    "__atomic_fetch_nand" => Some(("~&", false, 2, 2))
    "__sync_add_and_fetch" => Some(("+", true, 2, 2))
    "__sync_sub_and_fetch" => Some(("-", true, 2, 2))
    "__sync_and_and_fetch" => Some(("&", true, 2, 2))
    "__sync_or_and_fetch" => Some(("|", true, 2, 2))
    "__sync_xor_and_fetch" => Some(("^", true, 2, 2))
    "__sync_nand_and_fetch" => Some(("~&", true, 2, 2))
    "__sync_fetch_and_add" => Some(("+", false, 2, 2))
    "__sync_fetch_and_sub" => Some(("-", false, 2, 2))
    "__sync_fetch_and_and" => Some(("&", false, 2, 2))
    "__sync_fetch_and_or" => Some(("|", false, 2, 2))
    "__sync_fetch_and_xor" => Some(("^", false, 2, 2))
    "__sync_fetch_and_nand" => Some(("~&", false, 2, 2))
    "__sync_fetch_and_max" => Some(("max", false, 2, 2))
    "__sync_fetch_and_min" => Some(("min", false, 2, 2))
    "__sync_fetch_and_umax" => Some(("umax", false, 2, 2))
    "__sync_fetch_and_umin" => Some(("umin", false, 2, 2))
    _ => None
  }
}

///|
/// Parser-neutral atomic read-modify-write operation/result metadata.
pub fn builtin_atomic_update_op(name : String) -> (String, Bool)? {
  match builtin_atomic_update_call_info(name) {
    Some((op, return_new, _, _)) => Some((op, return_new))
    None => None
  }
}

///|
/// Parser-neutral operator selected by `__builtin_*_overflow` arithmetic.
pub fn builtin_overflow_op(name : String) -> String? {
  match name {
    "__builtin_add_overflow"
    | "__builtin_sadd_overflow"
    | "__builtin_saddl_overflow"
    | "__builtin_saddll_overflow"
    | "__builtin_uadd_overflow"
    | "__builtin_uaddl_overflow"
    | "__builtin_uaddll_overflow" => Some("+")
    "__builtin_sub_overflow"
    | "__builtin_ssub_overflow"
    | "__builtin_ssubl_overflow"
    | "__builtin_ssubll_overflow"
    | "__builtin_usub_overflow"
    | "__builtin_usubl_overflow"
    | "__builtin_usubll_overflow" => Some("-")
    "__builtin_mul_overflow"
    | "__builtin_smul_overflow"
    | "__builtin_smull_overflow"
    | "__builtin_smulll_overflow"
    | "__builtin_umul_overflow"
    | "__builtin_umull_overflow"
    | "__builtin_umulll_overflow" => Some("*")
    _ => None
  }
}

///|
/// Platform libcall selected by a source builtin plus the number of source
/// arguments forwarded to that libcall.
pub fn builtin_memory_libcall_info(
  name : String,
  arg_count : Int,
) -> (String, Int)? {
  match name {
    "__builtin_memcpy" =>
      if arg_count == 3 {
        Some(("memcpy", 3))
      } else {
        None
      }
    "__builtin_memmove" =>
      if arg_count == 3 {
        Some(("memmove", 3))
      } else {
        None
      }
    "__builtin_memset" =>
      if arg_count == 3 {
        Some(("memset", 3))
      } else {
        None
      }
    "__builtin_mempcpy" =>
      if arg_count == 3 {
        Some(("mempcpy", 3))
      } else {
        None
      }
    "__builtin_memccpy" =>
      if arg_count == 4 {
        Some(("memccpy", 4))
      } else {
        None
      }
    "__builtin_strcpy" =>
      if arg_count == 2 {
        Some(("strcpy", 2))
      } else {
        None
      }
    "__builtin_strcat" =>
      if arg_count == 2 {
        Some(("strcat", 2))
      } else {
        None
      }
    "__builtin_strncpy" =>
      if arg_count == 3 {
        Some(("strncpy", 3))
      } else {
        None
      }
    "__builtin_strncat" =>
      if arg_count == 3 {
        Some(("strncat", 3))
      } else {
        None
      }
    "__builtin_stpcpy" =>
      if arg_count == 2 {
        Some(("stpcpy", 2))
      } else {
        None
      }
    "__builtin_stpncpy" =>
      if arg_count == 3 {
        Some(("stpncpy", 3))
      } else {
        None
      }
    "__builtin___memcpy_chk" =>
      if arg_count == 4 {
        Some(("memcpy", 3))
      } else {
        None
      }
    "__builtin___memmove_chk" =>
      if arg_count == 4 {
        Some(("memmove", 3))
      } else {
        None
      }
    "__builtin___memset_chk" =>
      if arg_count == 4 {
        Some(("memset", 3))
      } else {
        None
      }
    "__builtin___mempcpy_chk" =>
      if arg_count == 4 {
        Some(("mempcpy", 3))
      } else {
        None
      }
    "__builtin___strcpy_chk" =>
      if arg_count == 3 {
        Some(("strcpy", 2))
      } else {
        None
      }
    "__builtin___strcat_chk" =>
      if arg_count == 3 {
        Some(("strcat", 2))
      } else {
        None
      }
    "__builtin___strncpy_chk" =>
      if arg_count == 4 {
        Some(("strncpy", 3))
      } else {
        None
      }
    "__builtin___strncat_chk" =>
      if arg_count == 4 {
        Some(("strncat", 3))
      } else {
        None
      }
    "__builtin___stpcpy_chk" =>
      if arg_count == 3 {
        Some(("stpcpy", 2))
      } else {
        None
      }
    "__builtin___stpncpy_chk" =>
      if arg_count == 4 {
        Some(("stpncpy", 3))
      } else {
        None
      }
    _ => None
  }
}

///|
/// C type expected at argument `index` of a lowered memory/string libcall.
///
/// Used after `builtin_memory_libcall_info` selects a libcall (such as
/// `memset`, `memccpy`, or `strcpy`) to coerce each forwarded argument to the
/// libc prototype. Pointer and length positions are typed precisely; any index
/// beyond the named ones falls back to `ULong` (the `size_t` count argument).
pub fn builtin_memory_libcall_arg_type(symbol : String, index : Int) -> Type {
  match symbol {
    "memset" =>
      match index {
        0 => Pointer(Void)
        1 => SInt
        _ => ULong
      }
    "memccpy" =>
      match index {
        0 | 1 => Pointer(Void)
        2 => SInt
        _ => ULong
      }
    "strcpy" | "strcat" | "strncpy" | "strncat" | "stpcpy" | "stpncpy" =>
      match index {
        0 | 1 => Pointer(SChar)
        _ => ULong
      }
    _ =>
      match index {
        0 | 1 => Pointer(Void)
        _ => ULong
      }
  }
}

///|
/// Heap-management libcall selected by a source builtin, with its forwarded
/// argument count.
///
/// Maps allocation builtins such as `__builtin_malloc`, `__builtin_calloc`,
/// `__builtin_realloc`, `__builtin_free`, and the `strdup` family to the libc
/// symbol they lower to. Returns `None` when the builtin name is unknown or the
/// argument count does not match the builtin's prototype.
pub fn builtin_heap_libcall_info(
  name : String,
  arg_count : Int,
) -> (String, Int)? {
  match name {
    "__builtin_malloc" =>
      if arg_count == 1 {
        Some(("malloc", 1))
      } else {
        None
      }
    "__builtin_calloc" =>
      if arg_count == 2 {
        Some(("calloc", 2))
      } else {
        None
      }
    "__builtin_realloc" =>
      if arg_count == 2 {
        Some(("realloc", 2))
      } else {
        None
      }
    "__builtin_free" => if arg_count == 1 { Some(("free", 1)) } else { None }
    "__builtin_strdup" =>
      if arg_count == 1 {
        Some(("strdup", 1))
      } else {
        None
      }
    "__builtin_strndup" =>
      if arg_count == 2 {
        Some(("strndup", 2))
      } else {
        None
      }
    _ => None
  }
}

///|
/// C type expected at argument `index` of a lowered heap-management libcall.
///
/// Companion to `builtin_heap_libcall_info`: it gives each argument of the
/// selected libc symbol (`malloc`, `calloc`, `realloc`, `free`, `strdup`,
/// `strndup`) its prototype type, defaulting to `Pointer(Void)` for unmodeled
/// positions.
pub fn builtin_heap_libcall_arg_type(symbol : String, index : Int) -> Type {
  match symbol {
    "malloc" => ULong
    "calloc" => ULong
    "realloc" =>
      match index {
        0 => Pointer(Void)
        _ => ULong
      }
    "free" => Pointer(Void)
    "strdup" => Pointer(SChar)
    "strndup" =>
      match index {
        0 => Pointer(SChar)
        _ => ULong
      }
    _ => Pointer(Void)
  }
}

///|
/// String-length libcall selected by a source builtin, with its forwarded
/// argument count.
///
/// Maps `__builtin_strlen` and `__builtin_strnlen` to `strlen`/`strnlen`.
/// Returns `None` for unknown names or mismatched argument counts.
pub fn builtin_length_libcall_info(
  name : String,
  arg_count : Int,
) -> (String, Int)? {
  match name {
    "__builtin_strlen" =>
      if arg_count == 1 {
        Some(("strlen", 1))
      } else {
        None
      }
    "__builtin_strnlen" =>
      if arg_count == 2 {
        Some(("strnlen", 2))
      } else {
        None
      }
    _ => None
  }
}

///|
/// C type expected at argument `index` of a lowered `strlen`/`strnlen` call.
///
/// Argument 0 is the `char *` string; any later argument is the `size_t`
/// bound, returned as `ULong`.
pub fn builtin_length_libcall_arg_type(index : Int) -> Type {
  if index == 0 {
    Pointer(SChar)
  } else {
    ULong
  }
}

///|
/// Comparison libcall selected by a source builtin, with its forwarded
/// argument count.
///
/// Maps `__builtin_strcmp`, `__builtin_strncmp`, and `__builtin_memcmp` to
/// `strcmp`/`strncmp`/`memcmp`. Returns `None` for unknown names or mismatched
/// argument counts.
pub fn builtin_compare_libcall_info(
  name : String,
  arg_count : Int,
) -> (String, Int)? {
  match name {
    "__builtin_strcmp" =>
      if arg_count == 2 {
        Some(("strcmp", 2))
      } else {
        None
      }
    "__builtin_strncmp" =>
      if arg_count == 3 {
        Some(("strncmp", 3))
      } else {
        None
      }
    "__builtin_memcmp" =>
      if arg_count == 3 {
        Some(("memcmp", 3))
      } else {
        None
      }
    "__builtin_bcmp" => if arg_count == 3 { Some(("bcmp", 3)) } else { None }
    _ => None
  }
}

///|
/// C type expected at argument `index` of a lowered comparison libcall.
///
/// Companion to `builtin_compare_libcall_info`. The pointer operands of
/// `strcmp`/`strncmp` are `char *` and those of `memcmp` are `void *`; the
/// trailing length argument is `size_t` (`ULong`).
pub fn builtin_compare_libcall_arg_type(symbol : String, index : Int) -> Type {
  match symbol {
    "strcmp" | "strncmp" =>
      match index {
        0 | 1 => Pointer(SChar)
        _ => ULong
      }
    "memcmp" | "bcmp" =>
      match index {
        0 | 1 => Pointer(Void)
        _ => ULong
      }
    _ => Pointer(Void)
  }
}

///|
/// Search libcall selected by a source builtin, with its forwarded argument
/// count.
///
/// Maps the character/substring search builtins (`__builtin_strchr`,
/// `__builtin_strrchr`, `__builtin_strstr`, `__builtin_memchr`,
/// `__builtin_memmem`) to their libc symbols. Returns `None` for unknown names
/// or mismatched argument counts.
pub fn builtin_search_libcall_info(
  name : String,
  arg_count : Int,
) -> (String, Int)? {
  match name {
    "__builtin_strchr" =>
      if arg_count == 2 {
        Some(("strchr", 2))
      } else {
        None
      }
    "__builtin_strrchr" =>
      if arg_count == 2 {
        Some(("strrchr", 2))
      } else {
        None
      }
    "__builtin_strstr" =>
      if arg_count == 2 {
        Some(("strstr", 2))
      } else {
        None
      }
    "__builtin_memchr" =>
      if arg_count == 3 {
        Some(("memchr", 3))
      } else {
        None
      }
    "__builtin_memmem" =>
      if arg_count == 4 {
        Some(("memmem", 4))
      } else {
        None
      }
    _ => None
  }
}

///|
/// C type expected at argument `index` of a lowered search libcall.
///
/// Companion to `builtin_search_libcall_info`. String searches take `char *`
/// haystacks/needles and an `int` character argument; memory searches take
/// `void *` operands; trailing length arguments are `size_t` (`ULong`).
pub fn builtin_search_libcall_arg_type(symbol : String, index : Int) -> Type {
  match symbol {
    "strchr" | "strrchr" =>
      match index {
        0 => Pointer(SChar)
        1 => SInt
        _ => ULong
      }
    "strstr" =>
      match index {
        0 | 1 => Pointer(SChar)
        _ => ULong
      }
    "memchr" =>
      match index {
        0 => Pointer(Void)
        1 => SInt
        _ => ULong
      }
    "memmem" =>
      match index {
        0 | 2 => Pointer(Void)
        _ => ULong
      }
    _ => Pointer(Void)
  }
}

///|
/// Span libcall selected by a source builtin, with its forwarded argument
/// count.
///
/// Maps `__builtin_strspn`, `__builtin_strcspn`, and `__builtin_strpbrk` to
/// their libc symbols, each forwarding its two `char *` arguments. Returns
/// `None` for unknown names or mismatched argument counts.
pub fn builtin_span_libcall_info(
  name : String,
  arg_count : Int,
) -> (String, Int)? {
  match name {
    "__builtin_strspn" =>
      if arg_count == 2 {
        Some(("strspn", 2))
      } else {
        None
      }
    "__builtin_strcspn" =>
      if arg_count == 2 {
        Some(("strcspn", 2))
      } else {
        None
      }
    "__builtin_strpbrk" =>
      if arg_count == 2 {
        Some(("strpbrk", 2))
      } else {
        None
      }
    _ => None
  }
}

///|
/// BSD `strlcpy`/`strlcat` libcall selected by a fortified source builtin.
///
/// Maps the `_chk` fortified forms `__builtin___strlcpy_chk` and
/// `__builtin___strlcat_chk` to `strlcpy`/`strlcat`, forwarding their first
/// three arguments (dropping the trailing object-size guard). Returns `None`
/// for unknown names or mismatched argument counts.
pub fn builtin_strl_libcall_info(
  name : String,
  arg_count : Int,
) -> (String, Int)? {
  match name {
    "__builtin___strlcpy_chk" =>
      if arg_count == 4 {
        Some(("strlcpy", 3))
      } else {
        None
      }
    "__builtin___strlcat_chk" =>
      if arg_count == 4 {
        Some(("strlcat", 3))
      } else {
        None
      }
    _ => None
  }
}

///|
/// C type expected at argument `index` of a lowered `strlcpy`/`strlcat` call.
///
/// Arguments 0 and 1 are the `char *` destination and source; argument 2 is the
/// `size_t` buffer size, returned as `ULong`.
pub fn builtin_strl_libcall_arg_type(index : Int) -> Type {
  match index {
    0 | 1 => Pointer(SChar)
    _ => ULong
  }
}

///|
/// libc `printf`-family symbol that a source builtin lowers to.
///
/// Recognizes the `printf`/`sprintf`/`snprintf` builtins and their `v...` and
/// fortified `_chk` variants, mapping each to the plain libc symbol
/// (`printf`, `sprintf`, `snprintf`, `vsnprintf`, …). The accepted argument
/// counts differ per builtin: variadic forms require at least the fixed
/// arguments, while the `v...` forms take an exact count. Returns `None` when
/// the name is unknown or the count is too small.
///
/// Unlike the other `_info` helpers this returns only the symbol; the source
/// argument positions to forward come from `builtin_printf_source_indexes`.
pub fn builtin_printf_libcall_symbol(name : String, arg_count : Int) -> String? {
  match name {
    "__builtin_snprintf" => if arg_count >= 3 { Some("snprintf") } else { None }
    "__builtin_vsnprintf" =>
      if arg_count == 4 {
        Some("vsnprintf")
      } else {
        None
      }
    "__builtin___snprintf_chk" =>
      if arg_count >= 5 {
        Some("snprintf")
      } else {
        None
      }
    "__builtin___vsnprintf_chk" =>
      if arg_count == 6 {
        Some("vsnprintf")
      } else {
        None
      }
    "__builtin_sprintf" => if arg_count >= 2 { Some("sprintf") } else { None }
    "__builtin_vsprintf" => if arg_count == 3 { Some("vsprintf") } else { None }
    "__builtin___sprintf_chk" =>
      if arg_count >= 4 {
        Some("sprintf")
      } else {
        None
      }
    "__builtin___vsprintf_chk" =>
      if arg_count == 5 {
        Some("vsprintf")
      } else {
        None
      }
    "__builtin_printf" => if arg_count >= 1 { Some("printf") } else { None }
    "__builtin_vprintf" => if arg_count == 2 { Some("vprintf") } else { None }
    "__builtin___printf_chk" =>
      if arg_count >= 2 {
        Some("printf")
      } else {
        None
      }
    "__builtin___vprintf_chk" =>
      if arg_count == 3 {
        Some("vprintf")
      } else {
        None
      }
    "__builtin___fprintf_chk" =>
      if arg_count >= 3 {
        Some("fprintf")
      } else {
        None
      }
    "__builtin___vfprintf_chk" =>
      if arg_count == 4 {
        Some("vfprintf")
      } else {
        None
      }
    _ => None
  }
}

///|
/// Source argument positions forwarded to a lowered `printf`-family libcall.
///
/// Fortified `_chk` builtins carry extra guard arguments (a flag and an
/// object-size) that the plain libc function does not take. This returns the
/// indices of the original-call arguments that survive lowering, in call
/// order, so the backend can drop the guard arguments. For non-fortified
/// builtins it returns every index. Returns `None` when the name is unknown or
/// the argument count is too small.
pub fn builtin_printf_source_indexes(
  name : String,
  arg_count : Int,
) -> Array[Int]? {
  match name {
    "__builtin_snprintf" =>
      if arg_count >= 3 {
        let indexes = []
        for i in 0..<arg_count {
          indexes.push(i)
        }
        Some(indexes)
      } else {
        None
      }
    "__builtin_vsnprintf" =>
      if arg_count == 4 {
        Some([0, 1, 2, 3])
      } else {
        None
      }
    "__builtin___snprintf_chk" =>
      if arg_count >= 5 {
        let indexes = [0, 1, 4]
        for i in 5..<arg_count {
          indexes.push(i)
        }
        Some(indexes)
      } else {
        None
      }
    "__builtin___vsnprintf_chk" =>
      if arg_count == 6 {
        Some([0, 1, 4, 5])
      } else {
        None
      }
    "__builtin_sprintf" =>
      if arg_count >= 2 {
        let indexes = []
        for i in 0..<arg_count {
          indexes.push(i)
        }
        Some(indexes)
      } else {
        None
      }
    "__builtin_vsprintf" => if arg_count == 3 { Some([0, 1, 2]) } else { None }
    "__builtin___sprintf_chk" =>
      if arg_count >= 4 {
        let indexes = [0, 3]
        for i in 4..<arg_count {
          indexes.push(i)
        }
        Some(indexes)
      } else {
        None
      }
    "__builtin___vsprintf_chk" =>
      if arg_count == 5 {
        Some([0, 3, 4])
      } else {
        None
      }
    "__builtin_printf" =>
      if arg_count >= 1 {
        let indexes = []
        for i in 0..<arg_count {
          indexes.push(i)
        }
        Some(indexes)
      } else {
        None
      }
    "__builtin_vprintf" => if arg_count == 2 { Some([0, 1]) } else { None }
    "__builtin___printf_chk" =>
      if arg_count >= 2 {
        let indexes = [1]
        for i in 2..<arg_count {
          indexes.push(i)
        }
        Some(indexes)
      } else {
        None
      }
    "__builtin___vprintf_chk" =>
      if arg_count == 3 {
        Some([1, 2])
      } else {
        None
      }
    "__builtin___fprintf_chk" =>
      if arg_count >= 3 {
        let indexes = [0, 2]
        for i in 3..<arg_count {
          indexes.push(i)
        }
        Some(indexes)
      } else {
        None
      }
    "__builtin___vfprintf_chk" =>
      if arg_count == 4 {
        Some([0, 2, 3])
      } else {
        None
      }
    _ => None
  }
}

///|
/// Whether a source argument `index` appears in a forwarded-index list.
///
/// A small membership helper over the result of
/// `builtin_printf_source_indexes`, letting the lowering decide whether a given
/// original argument is forwarded to the libc call or dropped as a guard.
pub fn builtin_printf_source_index_used(
  indexes : Array[Int],
  index : Int,
) -> Bool {
  for value in indexes {
    if value == index {
      return true
    }
  }
  false
}

///|
/// Whether a lowered `printf`-family libcall is variadic.
///
/// The non-`v` symbols (`printf`, `sprintf`, `snprintf`, `fprintf`) take a
/// trailing `...` of format arguments, so they are variadic; the `v...` forms
/// take a single `va_list` and are not. Callers use this to decide how to type
/// arguments past the fixed prototype.
pub fn builtin_printf_libcall_variadic(symbol : String) -> Bool {
  match symbol {
    "snprintf" | "sprintf" | "printf" | "fprintf" => true
    _ => false
  }
}

///|
/// C type expected at fixed argument `index` of a `printf`-family libcall.
///
/// Returns the prototype type for the leading fixed arguments of the selected
/// symbol (for example `snprintf`'s `char *`, `size_t`, `char *` prefix), and
/// `None` once past the fixed prototype — those trailing positions belong to
/// the variadic format arguments (see `builtin_printf_libcall_variadic`) and
/// are typed from the call instead.
pub fn builtin_printf_libcall_arg_type(symbol : String, index : Int) -> Type? {
  match symbol {
    "snprintf" =>
      match index {
        0 => Some(Pointer(SChar))
        1 => Some(ULong)
        2 => Some(Pointer(SChar))
        _ => None
      }
    "vsnprintf" =>
      match index {
        0 => Some(Pointer(SChar))
        1 => Some(ULong)
        2 => Some(Pointer(SChar))
        3 => Some(Pointer(SChar))
        _ => None
      }
    "sprintf" =>
      match index {
        0 | 1 => Some(Pointer(SChar))
        _ => None
      }
    "vsprintf" =>
      match index {
        0 | 1 | 2 => Some(Pointer(SChar))
        _ => None
      }
    "printf" => if index == 0 { Some(Pointer(SChar)) } else { None }
    "vprintf" =>
      match index {
        0 | 1 => Some(Pointer(SChar))
        _ => None
      }
    "fprintf" =>
      match index {
        0 => Some(Pointer(Void))
        1 => Some(Pointer(SChar))
        _ => None
      }
    "vfprintf" =>
      match index {
        0 => Some(Pointer(Void))
        1 | 2 => Some(Pointer(SChar))
        _ => None
      }
    _ => None
  }
}
