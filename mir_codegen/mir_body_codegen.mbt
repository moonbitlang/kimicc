///|
fn mir_body_local_name(binding : @mir.MirLocal) -> String {
  "__mir_" + binding.id.to_string() + "_" + binding.name
}

///|
fn mir_body_codegen_scalar_type(ty : @ctype.Type) -> Bool {
  match peel_aligned_type(ty) {
    Void => true
    Bool
    | SChar
    | UChar
    | SShort
    | UShort
    | SInt
    | UInt
    | SLong
    | ULong
    | SLongLong
    | ULongLong
    | Float
    | Double
    | Pointer(_)
    | FuncPtr(_, _, _) => true
    Atomic(inner) => mir_body_codegen_scalar_type(inner)
    _ => false
  }
}

///|
fn mir_body_codegen_abi_scalar_type(ty : @ctype.Type) -> Bool {
  match peel_aligned_type(ty) {
    Void
    | Bool
    | SChar
    | UChar
    | SShort
    | UShort
    | SInt
    | UInt
    | SLong
    | ULong
    | SLongLong
    | ULongLong
    | Pointer(_)
    | FuncPtr(_, _, _) => true
    Atomic(inner) => mir_body_codegen_abi_scalar_type(inner)
    _ => false
  }
}

///|
fn mir_body_codegen_floating_type(ty : @ctype.Type) -> Bool {
  match peel_aligned_type(ty) {
    Float | Double => true
    Atomic(inner) => mir_body_codegen_floating_type(inner)
    _ => false
  }
}

///|
fn mir_body_codegen_double_type(ty : @ctype.Type) -> Bool {
  match peel_aligned_type(ty) {
    Double => true
    Atomic(inner) => mir_body_codegen_double_type(inner)
    _ => false
  }
}

///|
fn mir_body_compare_op(op : String) -> Bool {
  match op {
    "==" | "!=" | "<" | ">" | "<=" | ">=" => true
    _ => false
  }
}

///|
fn mir_body_codegen_fp_compare_supported(
  op : String,
  lhs : @ctype.Type,
  rhs : @ctype.Type,
  ty : @ctype.Type,
) -> Bool {
  mir_body_compare_op(op) &&
  !mir_body_codegen_floating_type(ty) &&
  (mir_body_codegen_double_type(lhs) || lhs.is_integer()) &&
  (mir_body_codegen_double_type(rhs) || rhs.is_integer()) &&
  (mir_body_codegen_double_type(lhs) || mir_body_codegen_double_type(rhs))
}

///|
fn mir_body_codegen_local_type(ty : @ctype.Type) -> Bool {
  match ty {
    Aligned(_, _) => false
    Array(elem, _) => mir_body_codegen_scalar_type(elem)
    Struct(_) | Union(_) => true
    _ => mir_body_codegen_scalar_type(ty)
  }
}

///|
fn mir_body_codegen_array_address_base(
  value : @mir.MirValue,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  match value {
    MirLocal(binding) =>
      match peel_aligned_type(binding.ty) {
        Array(_, _) => mir_body_codegen_local_type(binding.ty)
        _ => mir_body_codegen_value_supported(value, int_arg_limit, mir)
      }
    _ => mir_body_codegen_value_supported(value, int_arg_limit, mir)
  }
}

///|
fn mir_body_codegen_pointer_operand_supported(
  value : @mir.MirValue,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  match pointer_or_array_element_type(value.ty()) {
    Some(_) => mir_body_codegen_array_address_base(value, int_arg_limit, mir)
    None => mir_body_codegen_value_supported(value, int_arg_limit, mir)
  }
}

///|
fn mir_body_codegen_value_supported(
  value : @mir.MirValue,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  if !mir_body_codegen_scalar_type(value.ty()) {
    return false
  }
  match value {
    MirConst(_, ty) => mir_body_codegen_scalar_type(ty)
    MirLocal(binding) => mir_body_codegen_scalar_type(binding.ty)
    MirAddrLocal(binding) => mir_body_codegen_local_type(binding.ty)
    MirAddrGlobal(_, ty) => mir_body_codegen_local_type(ty)
    MirFuncAddr(name, ty) =>
      mir.funcs.contains(name) && mir_body_codegen_scalar_type(ty)
    MirStringAddr(_) => true
    MirElemAddr(base, index, elem_ty) =>
      mir_body_codegen_scalar_type(elem_ty) &&
      mir_body_codegen_array_address_base(base, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(index, int_arg_limit, mir)
    MirOffsetAddr(base, _, ty) =>
      mir_body_codegen_local_type(ty) &&
      mir_body_codegen_value_supported(base, int_arg_limit, mir)
    MirLoad(ptr, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(ptr, int_arg_limit, mir)
    MirUnary(_, inner, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      !mir_body_codegen_floating_type(ty) &&
      !mir_body_codegen_floating_type(inner.ty()) &&
      mir_body_codegen_value_supported(inner, int_arg_limit, mir)
    MirBinary(op, lhs, rhs, ty) => {
      if !mir_body_codegen_scalar_type(ty) {
        return false
      }
      if mir_body_codegen_fp_compare_supported(op, lhs.ty(), rhs.ty(), ty) {
        return mir_body_codegen_value_supported(lhs, int_arg_limit, mir) &&
          mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
      }
      if mir_body_codegen_floating_type(lhs.ty()) ||
        mir_body_codegen_floating_type(rhs.ty()) ||
        mir_body_codegen_floating_type(ty) {
        return false
      }
      if mir_body_pointer_integer_op(op, lhs.ty(), rhs.ty()) {
        return mir_body_codegen_pointer_operand_supported(
            lhs, int_arg_limit, mir,
          ) &&
          mir_body_codegen_pointer_operand_supported(rhs, int_arg_limit, mir)
      } else {
        return mir_body_codegen_value_supported(lhs, int_arg_limit, mir) &&
          mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
      }
    }
    MirCast(ty, inner) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(inner, int_arg_limit, mir)
    MirAssignLocal(binding, rhs) =>
      mir_body_codegen_scalar_type(binding.ty) &&
      mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
    MirStore(ptr, rhs, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(ptr, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
    MirPostUpdateLocal(binding, _, rhs, ty) =>
      mir_body_codegen_scalar_type(binding.ty) &&
      mir_body_codegen_scalar_type(ty) &&
      !mir_body_codegen_floating_type(binding.ty) &&
      !mir_body_codegen_floating_type(ty) &&
      mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
    MirPreUpdateMemory(ptr, _, rhs, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      !mir_body_codegen_floating_type(ty) &&
      mir_body_codegen_value_supported(ptr, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
    MirPostUpdateMemory(ptr, _, rhs, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      !mir_body_codegen_floating_type(ty) &&
      mir_body_codegen_value_supported(ptr, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
    MirTernary(cond, then_, else_, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      !mir_body_codegen_floating_type(ty) &&
      mir_body_codegen_value_supported(cond, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(then_, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(else_, int_arg_limit, mir)
    MirCall(name, args, ty) => {
      if !mir_body_codegen_call_supported(name, args, ty, int_arg_limit, mir) {
        return false
      }
      for arg in args {
        if !mir_body_codegen_value_supported(arg, int_arg_limit, mir) {
          return false
        }
      }
      true
    }
    MirIndirectCall(callee, args, ty) => {
      if !mir_body_codegen_value_supported(callee, int_arg_limit, mir) ||
        !mir_body_codegen_indirect_call_supported(
          callee.ty(),
          args,
          ty,
          int_arg_limit,
        ) {
        return false
      }
      for arg in args {
        if !mir_body_codegen_value_supported(arg, int_arg_limit, mir) {
          return false
        }
      }
      true
    }
  }
}

///|
fn mir_body_codegen_builtin_call_name(name : String) -> Bool {
  name.has_prefix("__builtin_") ||
  name.has_prefix("__sync_") ||
  name.has_prefix("__atomic_") ||
  name.has_prefix("__c11_atomic_")
}

///|
fn mir_body_codegen_sync_synchronize_call(
  name : String,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
) -> Bool {
  name == "__sync_synchronize" &&
  args.length() == 0 &&
  peel_aligned_type(ret) is Void
}

///|
fn mir_body_codegen_atomic_thread_fence_call(
  name : String,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
) -> Bool {
  (name == "__atomic_thread_fence" || name == "__c11_atomic_thread_fence") &&
  args.length() == 1 &&
  peel_aligned_type(ret) is Void
}

///|
fn mir_body_codegen_atomic_signal_fence_call(
  name : String,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
) -> Bool {
  (name == "__atomic_signal_fence" || name == "__c11_atomic_signal_fence") &&
  args.length() == 1 &&
  peel_aligned_type(ret) is Void
}

///|
fn mir_body_codegen_trap_call(
  name : String,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
) -> Bool {
  (name == "__builtin_trap" || name == "__builtin_unreachable") &&
  args.length() == 0 &&
  peel_aligned_type(ret) is Void
}

///|
fn mir_body_codegen_return_pointer_type(ty : @ctype.Type) -> Bool {
  peel_aligned_type(ty) is Pointer(_)
}

///|
fn mir_body_codegen_alloca_call(
  name : String,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
) -> Bool {
  name == "__builtin_alloca" &&
  args.length() == 1 &&
  mir_body_codegen_return_pointer_type(ret)
}

///|
fn mir_body_codegen_const_builtin_level(args : Array[@mir.MirValue]) -> Int64? {
  if args.length() == 0 {
    return Some(0L)
  }
  if args.length() != 1 {
    return None
  }
  match args[0] {
    MirConst(value, _) => Some(value)
    _ => None
  }
}

///|
fn mir_body_codegen_frame_address_call(
  name : String,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
) -> Bool {
  name == "__builtin_frame_address" &&
  mir_body_codegen_const_builtin_level(args) is Some(_) &&
  mir_body_codegen_return_pointer_type(ret)
}

///|
fn mir_body_codegen_return_address_call(
  name : String,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
) -> Bool {
  name == "__builtin_return_address" &&
  mir_body_codegen_const_builtin_level(args) is Some(_) &&
  mir_body_codegen_return_pointer_type(ret)
}

///|
fn mir_body_codegen_va_setup_call(
  name : String,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
) -> Bool {
  let arity = match name {
    "__builtin_va_start" | "__builtin_va_copy" => Some(2)
    "__builtin_va_end" => Some(1)
    _ => None
  }
  match arity {
    Some(count) => args.length() == count && peel_aligned_type(ret) is Void
    None => false
  }
}

///|
fn mir_body_codegen_overflow_result_type(
  args : Array[@mir.MirValue],
) -> @ctype.Type? {
  if args.length() < 3 {
    return None
  }
  match pointer_or_array_element_type(args[2].ty()) {
    Some(ty) => Some(peel_aligned_type(ty))
    None => None
  }
}

///|
fn mir_body_codegen_overflow_call(
  name : String,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
) -> Bool {
  if overflow_builtin_operator(name) is None ||
    args.length() != 3 ||
    !(peel_aligned_type(ret) is Bool) {
    return false
  }
  match mir_body_codegen_overflow_result_type(args) {
    Some(ty) => ty.is_integer() && !is_int128_type(ty)
    None => false
  }
}

///|
fn mir_body_codegen_builtin_lib_call_arg_count(
  name : String,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
  int_arg_limit : Int,
) -> Int? {
  match mir_body_codegen_checked_printf_source_indexes(name, args, ret) {
    Some(indexes) =>
      if indexes.length() <= int_arg_limit {
        return Some(indexes.length())
      } else {
        return None
      }
    None => ()
  }
  if mir_body_codegen_direct_call_source_indexes(name, args).length() >
    int_arg_limit {
    return None
  }
  match name {
    "__builtin_bzero" =>
      if args.length() == 2 && peel_aligned_type(ret) is Void {
        Some(2)
      } else {
        None
      }
    "__builtin_strlen" =>
      if args.length() == 1 && ret.is_integer() {
        Some(1)
      } else {
        None
      }
    "__builtin_strcmp" =>
      if args.length() == 2 && ret.is_integer() {
        Some(2)
      } else {
        None
      }
    "__builtin_strncmp" | "__builtin_memcmp" =>
      if args.length() == 3 && ret.is_integer() {
        Some(3)
      } else {
        None
      }
    "__builtin_strchr" | "__builtin_strrchr" | "__builtin_strstr" =>
      if args.length() == 2 && mir_body_codegen_return_pointer_type(ret) {
        Some(2)
      } else {
        None
      }
    "__builtin_memchr" =>
      if args.length() == 3 && mir_body_codegen_return_pointer_type(ret) {
        Some(3)
      } else {
        None
      }
    "__builtin_memcpy" | "__builtin_memmove" | "__builtin_memset" =>
      if args.length() == 3 && mir_body_codegen_return_pointer_type(ret) {
        Some(3)
      } else {
        None
      }
    "__builtin___memcpy_chk"
    | "__builtin___memmove_chk"
    | "__builtin___memset_chk" =>
      if args.length() == 4 && mir_body_codegen_return_pointer_type(ret) {
        Some(3)
      } else {
        None
      }
    "__builtin_strcpy" | "__builtin_strcat" =>
      if args.length() == 2 && mir_body_codegen_return_pointer_type(ret) {
        Some(2)
      } else {
        None
      }
    "__builtin___strcpy_chk" | "__builtin___strcat_chk" =>
      if args.length() == 3 && mir_body_codegen_return_pointer_type(ret) {
        Some(2)
      } else {
        None
      }
    "__builtin_strncpy" | "__builtin_strncat" =>
      if args.length() == 3 && mir_body_codegen_return_pointer_type(ret) {
        Some(3)
      } else {
        None
      }
    "__builtin___strncpy_chk" | "__builtin___strncat_chk" =>
      if args.length() == 4 && mir_body_codegen_return_pointer_type(ret) {
        Some(3)
      } else {
        None
      }
    "__builtin___strlcpy_chk" | "__builtin___strlcat_chk" =>
      if args.length() == 4 && ret.is_integer() {
        Some(3)
      } else {
        None
      }
    _ => None
  }
}

///|
fn mir_body_codegen_builtin_lib_call_supported(
  name : String,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
  int_arg_limit : Int,
) -> Bool {
  mir_body_codegen_builtin_lib_call_arg_count(name, args, ret, int_arg_limit)
  is Some(_)
}

///|
fn mir_body_codegen_direct_call_symbol(name : String) -> String {
  match name {
    "__builtin_bzero" => "bzero"
    "__builtin_strlen" => "strlen"
    "__builtin_strcmp" => "strcmp"
    "__builtin_strncmp" => "strncmp"
    "__builtin_memcmp" => "memcmp"
    "__builtin_strchr" => "strchr"
    "__builtin_strrchr" => "strrchr"
    "__builtin_memchr" => "memchr"
    "__builtin_strstr" => "strstr"
    "__builtin_memcpy" | "__builtin___memcpy_chk" => "memcpy"
    "__builtin_memmove" | "__builtin___memmove_chk" => "memmove"
    "__builtin_memset" | "__builtin___memset_chk" => "memset"
    "__builtin_strcpy" | "__builtin___strcpy_chk" => "strcpy"
    "__builtin_strcat" | "__builtin___strcat_chk" => "strcat"
    "__builtin_strncpy" | "__builtin___strncpy_chk" => "strncpy"
    "__builtin_strncat" | "__builtin___strncat_chk" => "strncat"
    "__builtin___strlcpy_chk" => "strlcpy"
    "__builtin___strlcat_chk" => "strlcat"
    "__builtin___snprintf_chk" => "snprintf"
    "__builtin___sprintf_chk" => "sprintf"
    "__builtin___printf_chk" => "printf"
    _ => name
  }
}

///|
fn mir_body_codegen_checked_printf_source_indexes(
  name : String,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
) -> Array[Int]? {
  match name {
    "__builtin___snprintf_chk" =>
      if args.length() >= 5 && ret.is_integer() {
        let indexes = [0, 1, 4]
        for i in 5..<args.length() {
          indexes.push(i)
        }
        Some(indexes)
      } else {
        None
      }
    "__builtin___sprintf_chk" =>
      if args.length() >= 4 && ret.is_integer() {
        let indexes = [0, 3]
        for i in 4..<args.length() {
          indexes.push(i)
        }
        Some(indexes)
      } else {
        None
      }
    "__builtin___printf_chk" =>
      if args.length() >= 2 && ret.is_integer() {
        let indexes = [1]
        for i in 2..<args.length() {
          indexes.push(i)
        }
        Some(indexes)
      } else {
        None
      }
    _ => None
  }
}

///|
fn mir_body_codegen_direct_call_source_indexes(
  name : String,
  args : Array[@mir.MirValue],
) -> Array[Int] {
  match mir_body_codegen_checked_printf_source_indexes(name, args, SInt) {
    Some(indexes) => return indexes
    None => ()
  }
  let count = match name {
    "__builtin___memcpy_chk"
    | "__builtin___memmove_chk"
    | "__builtin___memset_chk"
    | "__builtin___strncpy_chk"
    | "__builtin___strncat_chk"
    | "__builtin___strlcpy_chk"
    | "__builtin___strlcat_chk" => 3
    "__builtin___strcpy_chk" | "__builtin___strcat_chk" => 2
    _ => args.length()
  }
  let indexes = []
  for i in 0..<count {
    indexes.push(i)
  }
  indexes
}

///|
fn mir_body_codegen_direct_call_variadic(name : String) -> Bool {
  match name {
    "__builtin___snprintf_chk"
    | "__builtin___sprintf_chk"
    | "__builtin___printf_chk" => true
    _ => false
  }
}

///|
fn mir_body_codegen_direct_call_named_arg_count(name : String) -> Int {
  match name {
    "__builtin___snprintf_chk" => 3
    "__builtin___sprintf_chk" => 2
    "__builtin___printf_chk" => 1
    _ => 0
  }
}

///|
fn Codegen::mir_direct_call_variadic(self : Codegen, name : String) -> Bool {
  mir_body_codegen_direct_call_variadic(name) ||
  self.func_variadic.get_or_default(name, false)
}

///|
fn Codegen::mir_direct_call_named_arg_count(
  self : Codegen,
  name : String,
) -> Int {
  if mir_body_codegen_direct_call_variadic(name) {
    mir_body_codegen_direct_call_named_arg_count(name)
  } else {
    self.func_param_counts.get_or_default(name, 0)
  }
}

///|
fn X64Codegen::mir_direct_call_variadic(
  self : X64Codegen,
  name : String,
) -> Bool {
  mir_body_codegen_direct_call_variadic(name) ||
  self.func_variadic.get_or_default(name, false)
}

///|
fn mir_body_codegen_lowered_builtin_arg_type(
  name : String,
  index : Int,
) -> @ctype.Type? {
  match name {
    "__builtin_strlen" => if index == 0 { Some(Pointer(SChar)) } else { None }
    "__builtin_strcmp" | "__builtin_strstr" =>
      match index {
        0 | 1 => Some(Pointer(SChar))
        _ => None
      }
    "__builtin_strncmp" =>
      match index {
        0 | 1 => Some(Pointer(SChar))
        2 => Some(ULong)
        _ => None
      }
    "__builtin_memcmp" =>
      match index {
        0 | 1 => Some(Pointer(Void))
        2 => Some(ULong)
        _ => None
      }
    "__builtin_strchr" | "__builtin_strrchr" =>
      match index {
        0 => Some(Pointer(SChar))
        1 => Some(SInt)
        _ => None
      }
    "__builtin_memchr" =>
      match index {
        0 => Some(Pointer(Void))
        1 => Some(SInt)
        2 => Some(ULong)
        _ => None
      }
    "__builtin___snprintf_chk" =>
      match index {
        0 => Some(Pointer(SChar))
        1 => Some(ULong)
        2 => Some(Pointer(SChar))
        _ => None
      }
    "__builtin___sprintf_chk" =>
      match index {
        0 => Some(Pointer(SChar))
        1 => Some(Pointer(SChar))
        _ => None
      }
    "__builtin___printf_chk" =>
      if index == 0 {
        Some(Pointer(SChar))
      } else {
        None
      }
    _ => None
  }
}

///|
fn mir_body_codegen_call_supported(
  name : String,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  if mir_body_codegen_sync_synchronize_call(name, args, ret) ||
    mir_body_codegen_atomic_thread_fence_call(name, args, ret) ||
    mir_body_codegen_atomic_signal_fence_call(name, args, ret) ||
    mir_body_codegen_trap_call(name, args, ret) ||
    mir_body_codegen_alloca_call(name, args, ret) ||
    mir_body_codegen_frame_address_call(name, args, ret) ||
    mir_body_codegen_return_address_call(name, args, ret) ||
    mir_body_codegen_va_setup_call(name, args, ret) ||
    mir_body_codegen_overflow_call(name, args, ret) {
    return true
  }
  if mir_body_codegen_builtin_lib_call_supported(name, args, ret, int_arg_limit) {
    return true
  }
  if mir_body_codegen_builtin_call_name(name) ||
    args.length() > int_arg_limit ||
    !mir_body_codegen_abi_scalar_type(ret) {
    return false
  }
  if mir.bodies.contains(name) {
    return true
  }
  if !mir.funcs.contains(name) {
    return args.length() == 0 && !mir.globals.contains(name)
  }
  let sig = mir.funcs[name]
  if sig.defined || sig.variadic || !mir_body_codegen_abi_scalar_type(sig.ret) {
    return false
  }
  if sig.params.length() != args.length() {
    return false
  }
  if sig.params.length() > int_arg_limit {
    return false
  }
  for ty in sig.params {
    if !mir_body_codegen_abi_scalar_type(ty) {
      return false
    }
  }
  true
}

///|
fn mir_body_codegen_indirect_call_supported(
  callee_ty : @ctype.Type,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
  int_arg_limit : Int,
) -> Bool {
  if args.length() > int_arg_limit || !mir_body_codegen_abi_scalar_type(ret) {
    return false
  }
  match peel_aligned_type(callee_ty) {
    FuncPtr(sig_ret, params, variadic) => {
      if variadic ||
        params.length() != args.length() ||
        !mir_body_codegen_abi_scalar_type(sig_ret) ||
        !mir_body_codegen_abi_scalar_type(ret) {
        return false
      }
      for param in params {
        if !mir_body_codegen_abi_scalar_type(param) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn mir_indirect_call_arg_type(
  callee_ty : @ctype.Type,
  index : Int,
  actual : @ctype.Type,
) -> @ctype.Type {
  match peel_aligned_type(callee_ty) {
    FuncPtr(_, params, _) =>
      if index >= 0 && index < params.length() {
        params[index]
      } else {
        actual
      }
    _ => actual
  }
}

///|
fn mir_body_codegen_stmt_supported(
  stmt : @mir.MirStmt,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  match stmt {
    MirDeclare(binding, init) => {
      if !mir_body_codegen_local_type(binding.ty) {
        match init {
          Some(value) =>
            return mir_body_codegen_value_supported(value, int_arg_limit, mir)
          None => return true
        }
      }
      match peel_aligned_type(binding.ty) {
        Array(_, _) => return init is None
        _ => ()
      }
      match init {
        Some(value) =>
          mir_body_codegen_value_supported(value, int_arg_limit, mir)
        None => true
      }
    }
    MirExprStmt(value) =>
      mir_body_codegen_value_supported(value, int_arg_limit, mir)
    MirReturn(value) =>
      match value {
        Some(value) =>
          mir_body_codegen_value_supported(value, int_arg_limit, mir)
        None => true
      }
    MirIf(cond, then_, else_) =>
      mir_body_codegen_value_supported(cond, int_arg_limit, mir) &&
      mir_body_codegen_stmts_supported(then_, int_arg_limit, mir) &&
      mir_body_codegen_stmts_supported(else_, int_arg_limit, mir)
    MirWhile(cond, body) =>
      mir_body_codegen_value_supported(cond, int_arg_limit, mir) &&
      mir_body_codegen_stmts_supported(body, int_arg_limit, mir)
    MirFor(init, cond, inc, body) => {
      let inc_supported = match inc {
        Some(value) =>
          mir_body_codegen_value_supported(value, int_arg_limit, mir)
        None => true
      }
      mir_body_codegen_stmts_supported(init, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(cond, int_arg_limit, mir) &&
      inc_supported &&
      mir_body_codegen_stmts_supported(body, int_arg_limit, mir)
    }
    MirDoWhile(cond, body) =>
      mir_body_codegen_value_supported(cond, int_arg_limit, mir) &&
      mir_body_codegen_stmts_supported(body, int_arg_limit, mir)
    MirSwitch(control, _, body) =>
      mir_body_codegen_value_supported(control, int_arg_limit, mir) &&
      mir_body_codegen_stmts_supported(body, int_arg_limit, mir)
    MirLabel(_) => true
    MirGoto(_) => true
    MirBreak => true
    MirContinue => true
    MirBlock(stmts) =>
      mir_body_codegen_stmts_supported(stmts, int_arg_limit, mir)
  }
}

///|
fn mir_body_codegen_stmts_supported(
  stmts : Array[@mir.MirStmt],
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  for stmt in stmts {
    if !mir_body_codegen_stmt_supported(stmt, int_arg_limit, mir) {
      return false
    }
  }
  true
}

///|
fn mir_body_codegen_func_supported(
  body : @mir.MirFuncBody,
  variadic : Bool,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  ignore(variadic)
  if body.params.length() > int_arg_limit {
    return false
  }
  if !mir_body_codegen_abi_scalar_type(body.ret) {
    return false
  }
  for binding in body.params {
    if !mir_body_codegen_abi_scalar_type(binding.ty) {
      return false
    }
  }
  mir_body_codegen_stmts_supported(body.body, int_arg_limit, mir)
}

///|
fn mir_body_binary_left_type(
  op : String,
  lhs : @ctype.Type,
  rhs : @ctype.Type,
) -> @ctype.Type {
  if op == "<<" || op == ">>" {
    unary_integer_result_type(lhs)
  } else {
    integer_common_type(lhs, rhs)
  }
}

///|
fn mir_body_binary_right_type(
  op : String,
  lhs : @ctype.Type,
  rhs : @ctype.Type,
) -> @ctype.Type {
  if op == "<<" || op == ">>" {
    unary_integer_result_type(rhs)
  } else {
    integer_common_type(lhs, rhs)
  }
}

///|
fn mir_body_binary_common_type(
  op : String,
  lhs : @ctype.Type,
  rhs : @ctype.Type,
) -> @ctype.Type {
  if op == "<<" || op == ">>" {
    unary_integer_result_type(lhs)
  } else {
    integer_common_type(lhs, rhs)
  }
}

///|
fn mir_body_unsigned_binary(
  op : String,
  lhs : @ctype.Type,
  rhs : @ctype.Type,
) -> Bool {
  is_unsigned_integer_type(mir_body_binary_common_type(op, lhs, rhs))
}

///|
fn mir_body_pointer_integer_op(
  op : String,
  lhs : @ctype.Type,
  rhs : @ctype.Type,
) -> Bool {
  match pointer_or_array_element_type(lhs) {
    Some(_) => (op == "+" || op == "-") && rhs.is_integer()
    None =>
      op == "+" &&
      lhs.is_integer() &&
      pointer_or_array_element_type(rhs) is Some(_)
  }
}

///|
fn mir_body_pointer_diff_elem(
  op : String,
  lhs : @ctype.Type,
  rhs : @ctype.Type,
) -> @ctype.Type? {
  if op != "-" {
    return None
  }
  match
    (pointer_or_array_element_type(lhs), pointer_or_array_element_type(rhs)) {
    (Some(elem), Some(_)) => Some(elem)
    _ => None
  }
}

///|
fn Codegen::mir_body_offsets(
  self : Codegen,
  body : @mir.MirFuncBody,
) -> Map[Int, Int] {
  let offsets : Map[Int, Int] = {}
  for binding in body.locals {
    if mir_body_codegen_local_type(binding.ty) {
      offsets[binding.id] = self.alloc_local(
        mir_body_local_name(binding),
        binding.ty,
      )
    }
  }
  offsets
}

///|
fn Codegen::emit_mir_overflow_arithmetic_builtin(
  self : Codegen,
  args : Array[@mir.MirValue],
  offsets : Map[Int, Int],
  frame_size : Int,
  op : String,
) -> Unit {
  let result_ty = match mir_body_codegen_overflow_result_type(args) {
    Some(ty) => ty
    None => {
      self.emit("\tmov\tx9, #0")
      return
    }
  }
  if !result_ty.is_integer() || is_int128_type(result_ty) {
    abort(
      "unsupported Darwin ARM64 MIR overflow builtin result type: " +
      result_ty.to_string(),
    )
  }
  self.gen_mir_value(args[2], offsets, frame_size)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_mir_value(args[0], offsets, frame_size)
  self.emit_numeric_conversion(args[0].ty(), result_ty)
  self.emit_scalar_conversion_to(result_ty)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_mir_value(args[1], offsets, frame_size)
  self.emit_numeric_conversion(args[1].ty(), result_ty)
  self.emit_scalar_conversion_to(result_ty)
  self.emit("\tmov\tx10, x9")
  self.emit("\tldr\tx9, [sp], #16")
  if self.type_size(result_ty) < 8 {
    self.emit_small_overflow_arithmetic(result_ty, op)
  } else {
    self.emit_i64_overflow_arithmetic(result_ty, op)
  }
  self.emit("\tldr\tx10, [sp], #16")
  self.emit_store_typed("x9", "x10", result_ty)
  self.emit("\tmov\tx9, x11")
}

///|
fn Codegen::gen_mir_value(
  self : Codegen,
  value : @mir.MirValue,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  match value {
    MirConst(bits, ty) => {
      self.emit_load_int("x9", bits)
      self.emit_scalar_conversion_to(ty)
    }
    MirLocal(binding) => {
      self.emit_local_addr(offsets[binding.id], frame_size)
      self.emit_load_typed("x9", "x9", binding.ty)
    }
    MirAddrLocal(binding) =>
      self.emit_local_addr(offsets[binding.id], frame_size)
    MirAddrGlobal(name, _) => {
      self.emit("\tadrp\tx9, _" + name + "@GOTPAGE")
      self.emit("\tldr\tx9, [x9, _" + name + "@GOTPAGEOFF]")
    }
    MirFuncAddr(name, _) => {
      self.emit("\tadrp\tx9, _" + name + "@GOTPAGE")
      self.emit("\tldr\tx9, [x9, _" + name + "@GOTPAGEOFF]")
    }
    MirStringAddr(value) => {
      let idx = self.strings.length()
      self.strings.push(value)
      let label = "_str" + idx.to_string()
      self.emit("\tadrp\tx9, " + label + "@PAGE")
      self.emit("\tadd\tx9, x9, " + label + "@PAGEOFF")
    }
    MirElemAddr(base, index, elem_ty) => {
      self.gen_mir_address_base(base, offsets, frame_size)
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.gen_mir_value(index, offsets, frame_size)
      self.emit_load_int("x10", self.type_size(elem_ty).to_int64())
      self.emit("\tmul\tx9, x9, x10")
      self.emit("\tldr\tx10, [sp], #16")
      self.emit("\tadd\tx9, x10, x9")
    }
    MirOffsetAddr(base, offset, _) => {
      self.gen_mir_value(base, offsets, frame_size)
      if offset != 0 {
        self.emit_add_offset_to_x9(offset)
      }
    }
    MirLoad(ptr, ty) => {
      self.gen_mir_value(ptr, offsets, frame_size)
      self.emit_load_typed("x9", "x9", ty)
    }
    MirUnary(op, inner, ty) => {
      self.gen_mir_value(inner, offsets, frame_size)
      match op {
        "+" => ()
        "-" => self.emit("\tneg\tx9, x9")
        "!" => {
          self.emit("\tcmp\tx9, #0")
          self.emit("\tcset\tx9, eq")
        }
        "~" => self.emit("\tmvn\tx9, x9")
        _ => abort("unsupported MIR body unary operator")
      }
      self.emit_scalar_conversion_to(ty)
    }
    MirBinary(op, lhs, rhs, ty) =>
      self.gen_mir_binary(op, lhs, rhs, ty, offsets, frame_size)
    MirCast(ty, inner) => {
      self.gen_mir_value(inner, offsets, frame_size)
      self.emit_numeric_conversion(inner.ty(), ty)
      self.emit_scalar_conversion_to(ty)
    }
    MirAssignLocal(binding, rhs) => {
      self.gen_mir_value(rhs, offsets, frame_size)
      self.emit_numeric_conversion(rhs.ty(), binding.ty)
      self.emit_scalar_conversion_to(binding.ty)
      self.emit_store_local("x9", offsets[binding.id], frame_size)
    }
    MirStore(ptr, rhs, ty) => {
      self.gen_mir_value(ptr, offsets, frame_size)
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.gen_mir_value(rhs, offsets, frame_size)
      self.emit_numeric_conversion(rhs.ty(), ty)
      self.emit_scalar_conversion_to(ty)
      self.emit("\tldr\tx10, [sp], #16")
      self.emit_store_typed("x9", "x10", ty)
    }
    MirPostUpdateLocal(binding, op, rhs, ty) => {
      self.gen_mir_value(MirLocal(binding), offsets, frame_size)
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.gen_mir_binary(
        op,
        MirLocal(binding),
        rhs,
        binding.ty,
        offsets,
        frame_size,
      )
      self.emit_scalar_conversion_to(binding.ty)
      self.emit_store_local("x9", offsets[binding.id], frame_size)
      self.emit("\tldr\tx9, [sp], #16")
      self.emit_scalar_conversion_to(ty)
    }
    MirPreUpdateMemory(ptr, op, rhs, ty) => {
      let left_ty = mir_body_binary_left_type(op, ty, rhs.ty())
      let right_ty = mir_body_binary_right_type(op, ty, rhs.ty())
      self.gen_mir_value(ptr, offsets, frame_size)
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.emit_load_typed("x10", "x9", ty)
      self.emit("\tmov\tx9, x10")
      self.emit_numeric_conversion(ty, left_ty)
      self.emit_scalar_conversion_to(left_ty)
      self.emit("\tmov\tx10, x9")
      self.gen_mir_value(rhs, offsets, frame_size)
      self.emit_numeric_conversion(rhs.ty(), right_ty)
      self.emit_scalar_conversion_to(right_ty)
      match op {
        "+" => self.emit("\tadd\tx9, x9, x10")
        "-" => self.emit("\tsub\tx9, x10, x9")
        "*" => self.emit("\tmul\tx9, x10, x9")
        "/" =>
          if mir_body_unsigned_binary(op, ty, rhs.ty()) {
            self.emit("\tudiv\tx9, x10, x9")
          } else {
            self.emit("\tsdiv\tx9, x10, x9")
          }
        "%" => {
          if mir_body_unsigned_binary(op, ty, rhs.ty()) {
            self.emit("\tudiv\tx11, x10, x9")
          } else {
            self.emit("\tsdiv\tx11, x10, x9")
          }
          self.emit("\tmsub\tx9, x11, x9, x10")
        }
        "|" => self.emit("\torr\tx9, x10, x9")
        "&" => self.emit("\tand\tx9, x10, x9")
        "^" => self.emit("\teor\tx9, x10, x9")
        "<<" => self.emit("\tlsl\tx9, x10, x9")
        ">>" =>
          if is_unsigned_integer_type(left_ty) {
            self.emit("\tlsr\tx9, x10, x9")
          } else {
            self.emit("\tasr\tx9, x10, x9")
          }
        _ => abort("unsupported MIR body memory pre-update operator")
      }
      self.emit_scalar_conversion_to(ty)
      self.emit("\tldr\tx12, [sp], #16")
      self.emit_store_typed("x9", "x12", ty)
    }
    MirPostUpdateMemory(ptr, op, rhs, ty) => {
      self.gen_mir_value(ptr, offsets, frame_size)
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.emit_load_typed("x9", "x9", ty)
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.gen_mir_value(rhs, offsets, frame_size)
      self.emit_scalar_conversion_to(rhs.ty())
      self.emit("\tldr\tx10, [sp], #16")
      match op {
        "+" => self.emit("\tadd\tx11, x10, x9")
        "-" => self.emit("\tsub\tx11, x10, x9")
        _ => abort("unsupported MIR body memory post-update operator")
      }
      self.emit("\tldr\tx12, [sp], #16")
      self.emit_store_typed("x11", "x12", ty)
      self.emit("\tmov\tx9, x10")
      self.emit_scalar_conversion_to(ty)
    }
    MirTernary(cond, then_, else_, ty) => {
      let else_label = self.new_label()
      let end_label = self.new_label()
      self.gen_mir_value(cond, offsets, frame_size)
      self.emit("\tcbz\tx9, " + else_label)
      self.gen_mir_value(then_, offsets, frame_size)
      self.emit_scalar_conversion_to(ty)
      self.emit("\tb\t" + end_label)
      self.emit(else_label + ":")
      self.gen_mir_value(else_, offsets, frame_size)
      self.emit_scalar_conversion_to(ty)
      self.emit(end_label + ":")
    }
    MirCall(name, args, ty) => {
      if mir_body_codegen_sync_synchronize_call(name, args, ty) {
        self.emit("\tdmb\tish")
        self.emit("\tmov\tx9, #0")
        return
      } else if mir_body_codegen_atomic_thread_fence_call(name, args, ty) {
        for arg in args {
          self.gen_mir_value(arg, offsets, frame_size)
        }
        self.emit("\tdmb\tish")
        self.emit("\tmov\tx9, #0")
        return
      } else if mir_body_codegen_atomic_signal_fence_call(name, args, ty) {
        for arg in args {
          self.gen_mir_value(arg, offsets, frame_size)
        }
        self.emit("\tmov\tx9, #0")
        return
      } else if mir_body_codegen_trap_call(name, args, ty) {
        self.emit("\tbrk\t#0x1")
        self.emit("\tmov\tx9, #0")
        return
      } else if mir_body_codegen_alloca_call(name, args, ty) {
        self.gen_mir_value(args[0], offsets, frame_size)
        self.emit("\tadd\tx9, x9, #15")
        self.emit("\tbic\tx9, x9, #0xF")
        self.emit("\tsub\tsp, sp, x9")
        self.emit("\tmov\tx9, sp")
        return
      } else if mir_body_codegen_frame_address_call(name, args, ty) {
        let level = match mir_body_codegen_const_builtin_level(args) {
          Some(level) => level
          None => 0L
        }
        if level == 0L {
          self.emit("\tmov\tx9, x29")
        } else {
          self.emit("\tmov\tx9, #0")
        }
        return
      } else if mir_body_codegen_return_address_call(name, args, ty) {
        let level = match mir_body_codegen_const_builtin_level(args) {
          Some(level) => level
          None => 0L
        }
        if level == 0L {
          self.emit("\tldr\tx9, [x29, #8]")
        } else {
          self.emit("\tmov\tx9, #0")
        }
        return
      } else if mir_body_codegen_va_setup_call(name, args, ty) {
        self.emit("\tmov\tx9, #0")
        return
      }
      match overflow_builtin_operator(name) {
        Some(op) =>
          if mir_body_codegen_overflow_call(name, args, ty) {
            self.emit_mir_overflow_arithmetic_builtin(
              args, offsets, frame_size, op,
            )
            return
          }
        None => ()
      }
      let source_indexes = mir_body_codegen_direct_call_source_indexes(
        name, args,
      )
      if self.mir_direct_call_variadic(name) {
        let named_count = self.mir_direct_call_named_arg_count(name)
        for i in 0..<source_indexes.length() {
          let arg = args[source_indexes[i]]
          self.gen_mir_value(arg, offsets, frame_size)
          let expected = self.mir_call_arg_type(name, i, arg.ty())
          self.emit_numeric_conversion(arg.ty(), expected)
          self.emit_scalar_conversion_to(expected)
          self.emit("\tstr\tx9, [sp, #-16]!")
        }
        let variadic_slots = source_indexes.length() - named_count
        let variadic_area = if variadic_slots * 8 > 64 {
          (variadic_slots * 8 + 15) / 16 * 16
        } else {
          64
        }
        self.emit("\tsub\tsp, sp, #" + variadic_area.to_string())
        for i in 0..<source_indexes.length() {
          self.emit(
            "\tldr\tx" +
            i.to_string() +
            ", [sp, #" +
            (variadic_area + (source_indexes.length() - 1 - i) * 16).to_string() +
            "]",
          )
        }
        for i in named_count..<source_indexes.length() {
          self.emit(
            "\tldr\tx9, [sp, #" +
            (variadic_area + (source_indexes.length() - 1 - i) * 16).to_string() +
            "]",
          )
          self.emit(
            "\tstr\tx9, [sp, #" + ((i - named_count) * 8).to_string() + "]",
          )
        }
        self.emit("\tbl\t_" + mir_body_codegen_direct_call_symbol(name))
        self.emit(
          "\tadd\tsp, sp, #" +
          (variadic_area + source_indexes.length() * 16).to_string(),
        )
      } else {
        for i in 0..<source_indexes.length() {
          let arg = args[source_indexes[i]]
          self.gen_mir_value(arg, offsets, frame_size)
          let expected = self.mir_call_arg_type(name, i, arg.ty())
          self.emit_numeric_conversion(arg.ty(), expected)
          self.emit_scalar_conversion_to(expected)
          self.emit("\tstr\tx9, [sp, #-16]!")
        }
        for i = source_indexes.length() - 1; i >= 0; i = i - 1 {
          self.emit("\tldr\tx" + i.to_string() + ", [sp], #16")
        }
        self.emit("\tbl\t_" + mir_body_codegen_direct_call_symbol(name))
      }
      self.emit("\tmov\tx9, x0")
      self.emit_mir_abi_int_return_conversion(ty)
    }
    MirIndirectCall(callee, args, ty) => {
      self.gen_mir_value(callee, offsets, frame_size)
      self.emit("\tstr\tx9, [sp, #-16]!")
      for i in 0..<args.length() {
        let arg = args[i]
        self.gen_mir_value(arg, offsets, frame_size)
        let expected = mir_indirect_call_arg_type(callee.ty(), i, arg.ty())
        self.emit_numeric_conversion(arg.ty(), expected)
        self.emit_scalar_conversion_to(expected)
        self.emit("\tstr\tx9, [sp, #-16]!")
      }
      for i = args.length() - 1; i >= 0; i = i - 1 {
        self.emit("\tldr\tx" + i.to_string() + ", [sp], #16")
      }
      self.emit("\tldr\tx15, [sp], #16")
      self.emit("\tblr\tx15")
      self.emit("\tmov\tx9, x0")
      self.emit_mir_abi_int_return_conversion(ty)
    }
  }
}

///|
fn Codegen::gen_mir_address_base(
  self : Codegen,
  value : @mir.MirValue,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  match value {
    MirLocal(binding) =>
      match peel_aligned_type(binding.ty) {
        Array(_, _) => self.emit_local_addr(offsets[binding.id], frame_size)
        _ => self.gen_mir_value(value, offsets, frame_size)
      }
    _ => self.gen_mir_value(value, offsets, frame_size)
  }
}

///|
fn Codegen::mir_call_arg_type(
  self : Codegen,
  name : String,
  index : Int,
  actual : @ctype.Type,
) -> @ctype.Type {
  match mir_body_codegen_lowered_builtin_arg_type(name, index) {
    Some(ty) => return ty
    None => ()
  }
  if self.func_param_types.contains(name) {
    let params = self.func_param_types[name]
    if index < params.length() {
      return params[index]
    }
  }
  actual
}

///|
fn Codegen::emit_mir_abi_int_return_conversion(
  self : Codegen,
  ty : @ctype.Type,
) -> Unit {
  match peel_aligned_type(ty) {
    Bool | UChar => self.emit("\tand\tx9, x9, #0xFF")
    SChar => self.emit("\tsxtb\tx9, w9")
    UShort => self.emit("\tand\tx9, x9, #0xFFFF")
    SShort => self.emit("\tsxth\tx9, w9")
    UInt => self.emit("\tand\tx9, x9, #0xFFFFFFFF")
    SInt => self.emit("\tsxtw\tx9, w9")
    Atomic(inner) => self.emit_mir_abi_int_return_conversion(inner)
    _ => ()
  }
}

///|
fn Codegen::gen_mir_binary(
  self : Codegen,
  op : String,
  lhs : @mir.MirValue,
  rhs : @mir.MirValue,
  ty : @ctype.Type,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  match op {
    "&&" => {
      let false_label = self.new_label()
      let end_label = self.new_label()
      self.gen_mir_value(lhs, offsets, frame_size)
      self.emit("\tcbz\tx9, " + false_label)
      self.gen_mir_value(rhs, offsets, frame_size)
      self.emit("\tcbz\tx9, " + false_label)
      self.emit("\tmov\tx9, #1")
      self.emit("\tb\t" + end_label)
      self.emit(false_label + ":")
      self.emit("\tmov\tx9, #0")
      self.emit(end_label + ":")
      return
    }
    "||" => {
      let true_label = self.new_label()
      let end_label = self.new_label()
      self.gen_mir_value(lhs, offsets, frame_size)
      self.emit("\tcbnz\tx9, " + true_label)
      self.gen_mir_value(rhs, offsets, frame_size)
      self.emit("\tcbnz\tx9, " + true_label)
      self.emit("\tmov\tx9, #0")
      self.emit("\tb\t" + end_label)
      self.emit(true_label + ":")
      self.emit("\tmov\tx9, #1")
      self.emit(end_label + ":")
      return
    }
    "," => {
      self.gen_mir_value(lhs, offsets, frame_size)
      self.gen_mir_value(rhs, offsets, frame_size)
      self.emit_scalar_conversion_to(ty)
      return
    }
    _ => ()
  }
  if mir_body_pointer_integer_op(op, lhs.ty(), rhs.ty()) {
    match pointer_or_array_element_type(lhs.ty()) {
      Some(_) => self.gen_mir_address_base(lhs, offsets, frame_size)
      None => self.gen_mir_value(lhs, offsets, frame_size)
    }
    if lhs.ty().is_integer() {
      self.emit_numeric_conversion(
        lhs.ty(),
        unary_integer_result_type(lhs.ty()),
      )
      self.emit_scalar_conversion_to(unary_integer_result_type(lhs.ty()))
    }
    self.emit("\tstr\tx9, [sp, #-16]!")
    match pointer_or_array_element_type(rhs.ty()) {
      Some(_) => self.gen_mir_address_base(rhs, offsets, frame_size)
      None => self.gen_mir_value(rhs, offsets, frame_size)
    }
    if rhs.ty().is_integer() {
      self.emit_numeric_conversion(
        rhs.ty(),
        unary_integer_result_type(rhs.ty()),
      )
      self.emit_scalar_conversion_to(unary_integer_result_type(rhs.ty()))
    }
    self.emit("\tldr\tx10, [sp], #16")
    match pointer_or_array_element_type(lhs.ty()) {
      Some(elem_ty) => {
        let scale = self.type_size(elem_ty)
        if scale != 1 {
          self.emit_load_int("x11", scale.to_int64())
          self.emit("\tmul\tx9, x9, x11")
        }
        if op == "+" {
          self.emit("\tadd\tx9, x10, x9")
        } else {
          self.emit("\tsub\tx9, x10, x9")
        }
      }
      None =>
        match pointer_or_array_element_type(rhs.ty()) {
          Some(elem_ty) => {
            let scale = self.type_size(elem_ty)
            if scale != 1 {
              self.emit_load_int("x11", scale.to_int64())
              self.emit("\tmul\tx10, x10, x11")
            }
            self.emit("\tadd\tx9, x9, x10")
          }
          None => ()
        }
    }
    self.emit_scalar_conversion_to(ty)
    return
  }
  let left_ty = mir_body_binary_left_type(op, lhs.ty(), rhs.ty())
  let right_ty = mir_body_binary_right_type(op, lhs.ty(), rhs.ty())
  if mir_body_codegen_fp_compare_supported(op, lhs.ty(), rhs.ty(), ty) {
    self.gen_mir_value(lhs, offsets, frame_size)
    self.emit_numeric_conversion(lhs.ty(), Double)
    self.emit("\tstr\tx9, [sp, #-16]!")
    self.gen_mir_value(rhs, offsets, frame_size)
    self.emit_numeric_conversion(rhs.ty(), Double)
    self.emit("\tldr\tx10, [sp], #16")
    self.emit("\tfmov\td9, x10")
    self.emit("\tfmov\td10, x9")
    self.emit("\tfcmp\td9, d10")
    let cc = match op {
      "==" => "eq"
      "!=" => "ne"
      "<" => "mi"
      ">" => "gt"
      "<=" => "ls"
      _ => "ge"
    }
    self.emit("\tcset\tx9, " + cc)
    self.emit_scalar_conversion_to(ty)
    return
  }
  self.gen_mir_value(lhs, offsets, frame_size)
  self.emit_numeric_conversion(lhs.ty(), left_ty)
  self.emit_scalar_conversion_to(left_ty)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_mir_value(rhs, offsets, frame_size)
  self.emit_numeric_conversion(rhs.ty(), right_ty)
  self.emit_scalar_conversion_to(right_ty)
  self.emit("\tldr\tx10, [sp], #16")
  match op {
    "+" => self.emit("\tadd\tx9, x9, x10")
    "-" => {
      self.emit("\tsub\tx9, x10, x9")
      match mir_body_pointer_diff_elem(op, lhs.ty(), rhs.ty()) {
        Some(elem_ty) => {
          let scale = self.type_size(elem_ty)
          if scale > 1 {
            self.emit_load_int("x10", scale.to_int64())
            self.emit("\tsdiv\tx9, x9, x10")
          }
        }
        None => ()
      }
    }
    "*" => self.emit("\tmul\tx9, x10, x9")
    "/" =>
      if mir_body_unsigned_binary(op, lhs.ty(), rhs.ty()) {
        self.emit("\tudiv\tx9, x10, x9")
      } else {
        self.emit("\tsdiv\tx9, x10, x9")
      }
    "%" => {
      if mir_body_unsigned_binary(op, lhs.ty(), rhs.ty()) {
        self.emit("\tudiv\tx11, x10, x9")
      } else {
        self.emit("\tsdiv\tx11, x10, x9")
      }
      self.emit("\tmsub\tx9, x11, x9, x10")
    }
    "|" => self.emit("\torr\tx9, x10, x9")
    "&" => self.emit("\tand\tx9, x10, x9")
    "^" => self.emit("\teor\tx9, x10, x9")
    "<<" => self.emit("\tlsl\tx9, x10, x9")
    ">>" =>
      if is_unsigned_integer_type(left_ty) {
        self.emit("\tlsr\tx9, x10, x9")
      } else {
        self.emit("\tasr\tx9, x10, x9")
      }
    "==" | "!=" | "<" | ">" | "<=" | ">=" => {
      self.emit("\tcmp\tx10, x9")
      let unsigned = mir_body_unsigned_binary(op, lhs.ty(), rhs.ty())
      let cc = match op {
        "==" => "eq"
        "!=" => "ne"
        "<" => if unsigned { "lo" } else { "lt" }
        ">" => if unsigned { "hi" } else { "gt" }
        "<=" => if unsigned { "ls" } else { "le" }
        _ => if unsigned { "hs" } else { "ge" }
      }
      self.emit("\tcset\tx9, " + cc)
    }
    _ => abort("unsupported MIR body binary operator")
  }
  self.emit_scalar_conversion_to(ty)
}

///|
fn Codegen::gen_mir_stmt(
  self : Codegen,
  stmt : @mir.MirStmt,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  match stmt {
    MirDeclare(binding, init) =>
      if mir_body_codegen_local_type(binding.ty) {
        match init {
          Some(value) => {
            self.gen_mir_value(value, offsets, frame_size)
            self.emit_numeric_conversion(value.ty(), binding.ty)
            self.emit_scalar_conversion_to(binding.ty)
            self.emit_store_local("x9", offsets[binding.id], frame_size)
          }
          None => ()
        }
      } else {
        match init {
          Some(value) => self.gen_mir_value(value, offsets, frame_size)
          None => ()
        }
      }
    MirExprStmt(value) => self.gen_mir_value(value, offsets, frame_size)
    MirReturn(value) => {
      match value {
        Some(value) => {
          self.gen_mir_value(value, offsets, frame_size)
          let ret_ty = self.func_rets[self.func_name]
          self.emit_numeric_conversion(value.ty(), ret_ty)
          self.emit_scalar_conversion_to(ret_ty)
          self.emit("\tmov\tx0, x9")
        }
        None => self.emit("\tmov\tx0, #0")
      }
      self.emit("\tb\t_" + self.func_name + "_ret")
    }
    MirIf(cond, then_, else_) => {
      let else_label = self.new_label()
      let end_label = self.new_label()
      self.gen_mir_value(cond, offsets, frame_size)
      self.emit("\tcbz\tx9, " + else_label)
      self.gen_mir_stmts(then_, offsets, frame_size)
      self.emit("\tb\t" + end_label)
      self.emit(else_label + ":")
      self.gen_mir_stmts(else_, offsets, frame_size)
      self.emit(end_label + ":")
    }
    MirWhile(cond, body) => {
      let start_label = self.new_label()
      let end_label = self.new_label()
      let old_break = self.break_label
      let old_continue = self.continue_label
      self.break_label = Some(end_label)
      self.continue_label = Some(start_label)
      self.emit(start_label + ":")
      self.gen_mir_value(cond, offsets, frame_size)
      self.emit("\tcbz\tx9, " + end_label)
      self.gen_mir_stmts(body, offsets, frame_size)
      self.emit("\tb\t" + start_label)
      self.emit(end_label + ":")
      self.break_label = old_break
      self.continue_label = old_continue
    }
    MirFor(init, cond, inc, body) => {
      let start_label = self.new_label()
      let continue_label = self.new_label()
      let end_label = self.new_label()
      let old_break = self.break_label
      let old_continue = self.continue_label
      self.break_label = Some(end_label)
      self.continue_label = Some(continue_label)
      self.gen_mir_stmts(init, offsets, frame_size)
      self.emit(start_label + ":")
      self.gen_mir_value(cond, offsets, frame_size)
      self.emit("\tcbz\tx9, " + end_label)
      self.gen_mir_stmts(body, offsets, frame_size)
      self.emit(continue_label + ":")
      match inc {
        Some(value) => self.gen_mir_value(value, offsets, frame_size)
        None => ()
      }
      self.emit("\tb\t" + start_label)
      self.emit(end_label + ":")
      self.break_label = old_break
      self.continue_label = old_continue
    }
    MirDoWhile(cond, body) => {
      let start_label = self.new_label()
      let continue_label = self.new_label()
      let end_label = self.new_label()
      let old_break = self.break_label
      let old_continue = self.continue_label
      self.break_label = Some(end_label)
      self.continue_label = Some(continue_label)
      self.emit(start_label + ":")
      self.gen_mir_stmts(body, offsets, frame_size)
      self.emit(continue_label + ":")
      self.gen_mir_value(cond, offsets, frame_size)
      self.emit("\tcbnz\tx9, " + start_label)
      self.emit(end_label + ":")
      self.break_label = old_break
      self.continue_label = old_continue
    }
    MirSwitch(control, cases, body) => {
      let end_label = self.new_label()
      let old_break = self.break_label
      self.break_label = Some(end_label)
      let control_ty = switch_control_type(control.ty())
      self.gen_mir_value(control, offsets, frame_size)
      self.emit_scalar_conversion_to(control_ty)
      for c in cases {
        match c.0 {
          Some(value) => {
            self.emit_switch_case_compare(value, control_ty)
            self.emit("\tb.eq\t" + self.label_ref(c.1))
          }
          None => ()
        }
      }
      let mut default_label = end_label
      for c in cases {
        match c.0 {
          None => {
            default_label = self.label_ref(c.1)
            break
          }
          Some(_) => ()
        }
      }
      self.emit("\tb\t" + default_label)
      self.gen_mir_stmts(body, offsets, frame_size)
      self.emit(end_label + ":")
      self.break_label = old_break
    }
    MirLabel(name) => {
      let label = self.label_ref(name)
      self.emit(label + ":")
      self.defined_labels[name] = true
    }
    MirGoto(name) => self.emit("\tb\t" + self.label_ref(name))
    MirBreak =>
      match self.break_label {
        Some(label) => self.emit("\tb\t" + label)
        None => abort("break outside MIR body loop")
      }
    MirContinue =>
      match self.continue_label {
        Some(label) => self.emit("\tb\t" + label)
        None => abort("continue outside MIR body loop")
      }
    MirBlock(stmts) => self.gen_mir_stmts(stmts, offsets, frame_size)
  }
}

///|
fn Codegen::gen_mir_stmts(
  self : Codegen,
  stmts : Array[@mir.MirStmt],
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  for stmt in stmts {
    self.gen_mir_stmt(stmt, offsets, frame_size)
  }
}

///|
fn Codegen::gen_mir_func(
  self : Codegen,
  decl : @mir.MirFuncDecl,
  body : @mir.MirFuncBody,
) -> Unit {
  self.local_offsets = {}
  self.var_types = {}
  self.stack_size = 0
  self.emitted_labels = {}
  self.defined_labels = {}
  self.fp_literals = []
  self.func_name = decl.name
  self.sret_scratch_offset = -1
  self.pending_sret_offset = -1
  self.break_label = None
  self.continue_label = None
  let offsets = self.mir_body_offsets(body)
  let frame_size = (self.stack_size + 15) / 16 * 16
  if !decl.is_static && !decl.is_inline {
    if decl.is_weak {
      self.emit("\t.weak_definition\t_" + decl.name)
    } else {
      self.emit("\t.globl\t_" + decl.name)
    }
  }
  self.emit("\t// kimicc: mir-body")
  self.emit("\t.p2align\t2")
  self.emit("_" + decl.name + ":")
  self.emit("\tstp\tx29, x30, [sp, #-16]!")
  self.emit("\tmov\tx29, sp")
  if frame_size > 0 {
    if frame_size <= 4095 {
      self.emit("\tsub\tsp, sp, #" + frame_size.to_string())
    } else {
      self.emit_load_int("x16", frame_size.to_int64())
      self.emit("\tsub\tsp, sp, x16")
    }
  }
  for i in 0..<body.params.length() {
    let param = body.params[i]
    self.emit_store_local("x" + i.to_string(), offsets[param.id], frame_size)
  }
  self.gen_mir_stmts(body.body, offsets, frame_size)
  self.emit("\tmov\tx0, #0")
  self.emit("_" + decl.name + "_ret:")
  self.emit("\tmov\tsp, x29")
  self.emit("\tldp\tx29, x30, [sp], #16")
  self.emit("\tret")
}

///|
fn X64Codegen::emit_load_mir_int(self : X64Codegen, value : Int64) -> Unit {
  if x64_fits_i32(value) {
    self.emit("\tmov\trax, " + value.to_string())
  } else {
    self.emit("\tmovabs\trax, " + value.to_string())
  }
}

///|
fn X64Codegen::emit_mir_numeric_conversion(
  self : X64Codegen,
  src : @ctype.Type,
  dst : @ctype.Type,
) -> Unit {
  let src_core = x64_core_type(src)
  let dst_core = x64_core_type(dst)
  if src_core == dst_core {
    return
  }
  if x64_is_fp_type(src_core) {
    if x64_is_fp_type(dst_core) {
      if src_core == Float && dst_core == Double {
        self.emit("\tcvtss2sd\txmm0, xmm0")
      } else if src_core == Double && dst_core == Float {
        self.emit("\tcvtsd2ss\txmm0, xmm0")
      }
    } else if dst_core == Bool {
      self.emit_fp_to_bool(src_core)
    } else if dst_core.is_integer() {
      if src_core == Float {
        self.emit("\tcvttss2si\trax, xmm0")
      } else {
        self.emit("\tcvttsd2si\trax, xmm0")
      }
      self.emit_int_conversion_to(dst_core)
    }
  } else if x64_is_fp_type(dst_core) {
    if dst_core == Float {
      self.emit("\tcvtsi2ss\txmm0, rax")
    } else {
      self.emit("\tcvtsi2sd\txmm0, rax")
    }
  } else {
    self.emit_int_conversion_to(dst_core)
  }
}

///|
fn X64Codegen::emit_mir_push_rax(self : X64Codegen) -> Unit {
  self.emit("\tsub\trsp, 16")
  self.emit("\tmov\tQWORD PTR [rsp], rax")
}

///|
fn X64Codegen::emit_mir_pop_rax(self : X64Codegen) -> Unit {
  self.emit("\tmov\trax, QWORD PTR [rsp]")
  self.emit("\tadd\trsp, 16")
}

///|
fn X64Codegen::mir_body_offsets(
  self : X64Codegen,
  body : @mir.MirFuncBody,
) -> Map[Int, Int] {
  let offsets : Map[Int, Int] = {}
  for binding in body.locals {
    if mir_body_codegen_local_type(binding.ty) {
      offsets[binding.id] = self.alloc_local(
        mir_body_local_name(binding),
        binding.ty,
      )
    }
  }
  offsets
}

///|
fn X64Codegen::emit_mir_overflow_arithmetic_builtin(
  self : X64Codegen,
  args : Array[@mir.MirValue],
  offsets : Map[Int, Int],
  op : String,
) -> Unit {
  let result_ty = match mir_body_codegen_overflow_result_type(args) {
    Some(ty) => ty
    None => {
      self.emit("\tmov\trax, 0")
      return
    }
  }
  if !result_ty.is_integer() || x64_is_int128_type(result_ty) {
    abort(
      "unsupported x86-64 MIR overflow builtin result type: " +
      result_ty.to_string(),
    )
  }
  let width = self.type_size(result_ty)
  self.gen_mir_value(args[2], offsets)
  self.emit_mir_push_rax()
  self.gen_mir_value(args[0], offsets)
  self.emit_int_conversion_to(result_ty)
  self.emit_mir_push_rax()
  self.gen_mir_value(args[1], offsets)
  self.emit_int_conversion_to(result_ty)
  self.emit("\tmov\tr10, rax")
  self.emit_mir_pop_rax()
  let rhs_reg = x64_atomic_r10_reg(width)
  let lhs_reg = x64_sized_reg(width)
  match op {
    "+" => self.emit("\tadd\t" + lhs_reg + ", " + rhs_reg)
    "-" => self.emit("\tsub\t" + lhs_reg + ", " + rhs_reg)
    "*" =>
      if is_unsigned_integer_type(result_ty) {
        self.emit("\tmul\t" + rhs_reg)
      } else {
        self.emit("\timul\t" + rhs_reg)
      }
    _ => abort("unsupported x86-64 MIR overflow builtin operator: " + op)
  }
  let cc = if is_unsigned_integer_type(result_ty) && (op == "+" || op == "-") {
    "setb"
  } else {
    "seto"
  }
  self.emit("\t" + cc + "\tr11b")
  self.emit("\tmov\tr10, QWORD PTR [rsp]")
  self.emit("\tadd\trsp, 16")
  self.emit_store_indirect(result_ty)
  self.emit("\tmovzx\teax, r11b")
}

///|
fn X64Codegen::gen_mir_value(
  self : X64Codegen,
  value : @mir.MirValue,
  offsets : Map[Int, Int],
) -> Unit {
  match value {
    MirConst(bits, ty) =>
      if x64_is_fp_type(ty) {
        self.emit_load_fp_literal(bits.reinterpret_as_double())
        if x64_core_type(ty) == Float {
          self.emit("\tcvtsd2ss\txmm0, xmm0")
        }
      } else {
        self.emit_load_mir_int(bits)
        self.emit_int_conversion_to(ty)
      }
    MirLocal(binding) => {
      self.emit_local_addr(offsets[binding.id])
      self.emit_load_indirect(binding.ty)
    }
    MirAddrLocal(binding) => self.emit_local_addr(offsets[binding.id])
    MirAddrGlobal(name, _) => self.emit_symbol_addr(name)
    MirFuncAddr(name, _) => self.emit_symbol_addr(name)
    MirStringAddr(value) => {
      let id = self.strings.length()
      self.strings.push(value)
      self.emit("\tlea\trax, [rip + .Lstr" + id.to_string() + "]")
    }
    MirElemAddr(base, index, elem_ty) => {
      self.gen_mir_address_base(base, offsets)
      self.emit_mir_push_rax()
      self.gen_mir_value(index, offsets)
      let elem_size = self.type_size(elem_ty)
      if elem_size != 1 {
        self.emit("\timul\trax, rax, " + elem_size.to_string())
      }
      self.emit("\tmov\tr10, rax")
      self.emit_mir_pop_rax()
      self.emit("\tadd\trax, r10")
    }
    MirOffsetAddr(base, offset, _) => {
      self.gen_mir_value(base, offsets)
      if offset != 0 {
        self.emit("\tadd\trax, " + offset.to_string())
      }
    }
    MirLoad(ptr, ty) => {
      self.gen_mir_value(ptr, offsets)
      self.emit_load_indirect(ty)
    }
    MirUnary(op, inner, ty) => {
      self.gen_mir_value(inner, offsets)
      match op {
        "+" => ()
        "-" => self.emit("\tneg\trax")
        "!" => {
          self.emit("\tcmp\trax, 0")
          self.emit_setcc("sete")
        }
        "~" => self.emit("\tnot\trax")
        _ => abort("unsupported MIR body unary operator")
      }
      self.emit_int_conversion_to(ty)
    }
    MirBinary(op, lhs, rhs, ty) =>
      self.gen_mir_binary(op, lhs, rhs, ty, offsets)
    MirCast(ty, inner) => {
      self.gen_mir_value(inner, offsets)
      self.emit_mir_numeric_conversion(inner.ty(), ty)
      self.emit_int_conversion_to(ty)
    }
    MirAssignLocal(binding, rhs) => {
      self.gen_mir_value(rhs, offsets)
      self.emit_mir_numeric_conversion(rhs.ty(), binding.ty)
      self.emit_int_conversion_to(binding.ty)
      self.emit_store_local_from_rax(offsets[binding.id], binding.ty)
    }
    MirStore(ptr, rhs, ty) => {
      self.gen_mir_value(ptr, offsets)
      self.emit_mir_push_rax()
      self.gen_mir_value(rhs, offsets)
      self.emit_mir_numeric_conversion(rhs.ty(), ty)
      self.emit_int_conversion_to(ty)
      self.emit("\tmov\tr10, QWORD PTR [rsp]")
      self.emit("\tadd\trsp, 16")
      self.emit_store_indirect(ty)
    }
    MirPostUpdateLocal(binding, op, rhs, ty) => {
      self.gen_mir_value(MirLocal(binding), offsets)
      self.emit_mir_push_rax()
      self.gen_mir_binary(op, MirLocal(binding), rhs, binding.ty, offsets)
      self.emit_int_conversion_to(binding.ty)
      self.emit_store_local_from_rax(offsets[binding.id], binding.ty)
      self.emit_mir_pop_rax()
      self.emit_int_conversion_to(ty)
    }
    MirPreUpdateMemory(ptr, op, rhs, ty) => {
      let left_ty = mir_body_binary_left_type(op, ty, rhs.ty())
      let right_ty = mir_body_binary_right_type(op, ty, rhs.ty())
      self.gen_mir_value(ptr, offsets)
      self.emit_mir_push_rax()
      self.emit_load_indirect(ty)
      self.emit_mir_push_rax()
      self.gen_mir_value(rhs, offsets)
      self.emit_int_conversion_to(right_ty)
      self.emit("\tmov\tr10, rax")
      self.emit_mir_pop_rax()
      self.emit_int_conversion_to(left_ty)
      match op {
        "+" => self.emit("\tadd\trax, r10")
        "-" => self.emit("\tsub\trax, r10")
        "*" => self.emit("\timul\trax, r10")
        "/" =>
          if mir_body_unsigned_binary(op, ty, rhs.ty()) {
            self.emit("\txor\trdx, rdx")
            self.emit("\tdiv\tr10")
          } else {
            self.emit("\tcqo")
            self.emit("\tidiv\tr10")
          }
        "%" => {
          if mir_body_unsigned_binary(op, ty, rhs.ty()) {
            self.emit("\txor\trdx, rdx")
            self.emit("\tdiv\tr10")
          } else {
            self.emit("\tcqo")
            self.emit("\tidiv\tr10")
          }
          self.emit("\tmov\trax, rdx")
        }
        "|" => self.emit("\tor\trax, r10")
        "&" => self.emit("\tand\trax, r10")
        "^" => self.emit("\txor\trax, r10")
        "<<" => {
          self.emit("\tmov\trcx, r10")
          self.emit("\tshl\trax, cl")
        }
        ">>" => {
          self.emit("\tmov\trcx, r10")
          if is_unsigned_integer_type(left_ty) {
            self.emit("\tshr\trax, cl")
          } else {
            self.emit("\tsar\trax, cl")
          }
        }
        _ => abort("unsupported MIR body memory pre-update operator")
      }
      self.emit_int_conversion_to(ty)
      self.emit("\tmov\tr10, QWORD PTR [rsp]")
      self.emit("\tadd\trsp, 16")
      self.emit_store_indirect(ty)
      self.emit_int_conversion_to(ty)
    }
    MirPostUpdateMemory(ptr, op, rhs, ty) => {
      self.gen_mir_value(ptr, offsets)
      self.emit_mir_push_rax()
      self.emit_load_indirect(ty)
      self.emit_mir_push_rax()
      self.gen_mir_value(rhs, offsets)
      self.emit_int_conversion_to(rhs.ty())
      self.emit("\tmov\tr10, rax")
      self.emit_mir_pop_rax()
      self.emit("\tmov\tr11, rax")
      match op {
        "+" => self.emit("\tadd\trax, r10")
        "-" => self.emit("\tsub\trax, r10")
        _ => abort("unsupported MIR body memory post-update operator")
      }
      self.emit_int_conversion_to(ty)
      self.emit("\tmov\tr10, QWORD PTR [rsp]")
      self.emit("\tadd\trsp, 16")
      self.emit_store_indirect(ty)
      self.emit("\tmov\trax, r11")
      self.emit_int_conversion_to(ty)
    }
    MirTernary(cond, then_, else_, ty) => {
      let else_label = self.new_label()
      let end_label = self.new_label()
      self.gen_mir_value(cond, offsets)
      self.emit("\tcmp\trax, 0")
      self.emit("\tje\t" + else_label)
      self.gen_mir_value(then_, offsets)
      self.emit_int_conversion_to(ty)
      self.emit("\tjmp\t" + end_label)
      self.emit(else_label + ":")
      self.gen_mir_value(else_, offsets)
      self.emit_int_conversion_to(ty)
      self.emit(end_label + ":")
    }
    MirCall(name, args, ty) => {
      if mir_body_codegen_sync_synchronize_call(name, args, ty) {
        self.emit("\tmfence")
        self.emit("\tmov\trax, 0")
        return
      } else if mir_body_codegen_atomic_thread_fence_call(name, args, ty) {
        for arg in args {
          self.gen_mir_value(arg, offsets)
        }
        self.emit("\tmfence")
        self.emit("\tmov\trax, 0")
        return
      } else if mir_body_codegen_atomic_signal_fence_call(name, args, ty) {
        for arg in args {
          self.gen_mir_value(arg, offsets)
        }
        self.emit("\tmov\trax, 0")
        return
      } else if mir_body_codegen_trap_call(name, args, ty) {
        self.emit("\tud2")
        self.emit("\tmov\trax, 0")
        return
      } else if mir_body_codegen_alloca_call(name, args, ty) {
        self.gen_mir_value(args[0], offsets)
        self.emit("\tadd\trax, 15")
        self.emit("\tand\trax, -16")
        self.emit("\tsub\trsp, rax")
        self.emit("\tmov\trax, rsp")
        return
      } else if mir_body_codegen_frame_address_call(name, args, ty) {
        let level = match mir_body_codegen_const_builtin_level(args) {
          Some(level) => level
          None => 0L
        }
        if level == 0L {
          self.emit("\tmov\trax, rbp")
        } else {
          self.emit("\tmov\trax, 0")
        }
        return
      } else if mir_body_codegen_return_address_call(name, args, ty) {
        let level = match mir_body_codegen_const_builtin_level(args) {
          Some(level) => level
          None => 0L
        }
        if level == 0L {
          self.emit("\tmov\trax, QWORD PTR [rbp + 8]")
        } else {
          self.emit("\tmov\trax, 0")
        }
        return
      } else if mir_body_codegen_va_setup_call(name, args, ty) {
        self.emit("\tmov\trax, 0")
        return
      }
      match overflow_builtin_operator(name) {
        Some(op) =>
          if mir_body_codegen_overflow_call(name, args, ty) {
            self.emit_mir_overflow_arithmetic_builtin(args, offsets, op)
            return
          }
        None => ()
      }
      let source_indexes = mir_body_codegen_direct_call_source_indexes(
        name, args,
      )
      for i in 0..<source_indexes.length() {
        let arg = args[source_indexes[i]]
        self.gen_mir_value(arg, offsets)
        self.emit_int_conversion_to(self.mir_call_arg_type(name, i, arg.ty()))
        self.emit_mir_push_rax()
      }
      let arg_regs = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
      for i = source_indexes.length() - 1; i >= 0; i = i - 1 {
        self.emit("\tmov\t" + arg_regs[i] + ", QWORD PTR [rsp]")
        self.emit("\tadd\trsp, 16")
      }
      if self.mir_direct_call_variadic(name) {
        self.emit("\tmov\tal, 0")
      }
      self.emit("\tcall\t" + mir_body_codegen_direct_call_symbol(name))
      self.emit_abi_int_return_conversion(ty)
    }
    MirIndirectCall(callee, args, ty) => {
      self.gen_mir_value(callee, offsets)
      self.emit_mir_push_rax()
      for i in 0..<args.length() {
        let arg = args[i]
        self.gen_mir_value(arg, offsets)
        self.emit_int_conversion_to(
          mir_indirect_call_arg_type(callee.ty(), i, arg.ty()),
        )
        self.emit_mir_push_rax()
      }
      let arg_regs = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
      for i = args.length() - 1; i >= 0; i = i - 1 {
        self.emit("\tmov\t" + arg_regs[i] + ", QWORD PTR [rsp]")
        self.emit("\tadd\trsp, 16")
      }
      self.emit("\tmov\tr10, QWORD PTR [rsp]")
      self.emit("\tadd\trsp, 16")
      self.emit("\tcall\tr10")
      self.emit_abi_int_return_conversion(ty)
    }
  }
}

///|
fn X64Codegen::gen_mir_address_base(
  self : X64Codegen,
  value : @mir.MirValue,
  offsets : Map[Int, Int],
) -> Unit {
  match value {
    MirLocal(binding) =>
      match peel_aligned_type(binding.ty) {
        Array(_, _) => self.emit_local_addr(offsets[binding.id])
        _ => self.gen_mir_value(value, offsets)
      }
    _ => self.gen_mir_value(value, offsets)
  }
}

///|
fn X64Codegen::mir_call_arg_type(
  self : X64Codegen,
  name : String,
  index : Int,
  actual : @ctype.Type,
) -> @ctype.Type {
  match mir_body_codegen_lowered_builtin_arg_type(name, index) {
    Some(ty) => return ty
    None => ()
  }
  if self.func_param_types.contains(name) {
    let params = self.func_param_types[name]
    if index < params.length() {
      return params[index]
    }
  }
  actual
}

///|
fn X64Codegen::gen_mir_binary(
  self : X64Codegen,
  op : String,
  lhs : @mir.MirValue,
  rhs : @mir.MirValue,
  ty : @ctype.Type,
  offsets : Map[Int, Int],
) -> Unit {
  match op {
    "&&" => {
      let false_label = self.new_label()
      let end_label = self.new_label()
      self.gen_mir_value(lhs, offsets)
      self.emit("\tcmp\trax, 0")
      self.emit("\tje\t" + false_label)
      self.gen_mir_value(rhs, offsets)
      self.emit("\tcmp\trax, 0")
      self.emit("\tje\t" + false_label)
      self.emit("\tmov\trax, 1")
      self.emit("\tjmp\t" + end_label)
      self.emit(false_label + ":")
      self.emit("\tmov\trax, 0")
      self.emit(end_label + ":")
      return
    }
    "||" => {
      let true_label = self.new_label()
      let end_label = self.new_label()
      self.gen_mir_value(lhs, offsets)
      self.emit("\tcmp\trax, 0")
      self.emit("\tjne\t" + true_label)
      self.gen_mir_value(rhs, offsets)
      self.emit("\tcmp\trax, 0")
      self.emit("\tjne\t" + true_label)
      self.emit("\tmov\trax, 0")
      self.emit("\tjmp\t" + end_label)
      self.emit(true_label + ":")
      self.emit("\tmov\trax, 1")
      self.emit(end_label + ":")
      return
    }
    "," => {
      self.gen_mir_value(lhs, offsets)
      self.gen_mir_value(rhs, offsets)
      self.emit_int_conversion_to(ty)
      return
    }
    _ => ()
  }
  if mir_body_pointer_integer_op(op, lhs.ty(), rhs.ty()) {
    match pointer_or_array_element_type(lhs.ty()) {
      Some(_) => self.gen_mir_address_base(lhs, offsets)
      None => self.gen_mir_value(lhs, offsets)
    }
    if lhs.ty().is_integer() {
      self.emit_int_conversion_to(unary_integer_result_type(lhs.ty()))
    }
    self.emit_mir_push_rax()
    match pointer_or_array_element_type(rhs.ty()) {
      Some(_) => self.gen_mir_address_base(rhs, offsets)
      None => self.gen_mir_value(rhs, offsets)
    }
    if rhs.ty().is_integer() {
      self.emit_int_conversion_to(unary_integer_result_type(rhs.ty()))
    }
    self.emit("\tmov\tr10, rax")
    self.emit_mir_pop_rax()
    match pointer_or_array_element_type(lhs.ty()) {
      Some(elem_ty) => {
        let scale = self.type_size(elem_ty)
        if scale != 1 {
          self.emit("\timul\tr10, r10, " + scale.to_string())
        }
        if op == "+" {
          self.emit("\tadd\trax, r10")
        } else {
          self.emit("\tsub\trax, r10")
        }
      }
      None =>
        match pointer_or_array_element_type(rhs.ty()) {
          Some(elem_ty) => {
            let scale = self.type_size(elem_ty)
            if scale != 1 {
              self.emit("\timul\trax, rax, " + scale.to_string())
            }
            self.emit("\tadd\trax, r10")
          }
          None => ()
        }
    }
    self.emit_int_conversion_to(ty)
    return
  }
  let left_ty = mir_body_binary_left_type(op, lhs.ty(), rhs.ty())
  let right_ty = mir_body_binary_right_type(op, lhs.ty(), rhs.ty())
  if mir_body_codegen_fp_compare_supported(op, lhs.ty(), rhs.ty(), ty) {
    self.gen_mir_value(lhs, offsets)
    self.emit_mir_numeric_conversion(lhs.ty(), Double)
    self.emit("\tsub\trsp, 16")
    self.emit("\tmovsd\tQWORD PTR [rsp], xmm0")
    self.gen_mir_value(rhs, offsets)
    self.emit_mir_numeric_conversion(rhs.ty(), Double)
    self.emit("\tmovapd\txmm1, xmm0")
    self.emit("\tmovsd\txmm0, QWORD PTR [rsp]")
    self.emit("\tadd\trsp, 16")
    self.emit("\tucomisd\txmm0, xmm1")
    self.emit_fp_compare_result(op)
    self.emit_int_conversion_to(ty)
    return
  }
  self.gen_mir_value(lhs, offsets)
  self.emit_int_conversion_to(left_ty)
  self.emit_mir_push_rax()
  self.gen_mir_value(rhs, offsets)
  self.emit_int_conversion_to(right_ty)
  self.emit("\tmov\tr10, rax")
  self.emit_mir_pop_rax()
  match op {
    "+" => self.emit("\tadd\trax, r10")
    "-" => {
      self.emit("\tsub\trax, r10")
      match mir_body_pointer_diff_elem(op, lhs.ty(), rhs.ty()) {
        Some(elem_ty) => {
          let scale = self.type_size(elem_ty)
          if scale > 1 {
            self.emit("\tmov\tr10, " + scale.to_string())
            self.emit("\tcqo")
            self.emit("\tidiv\tr10")
          }
        }
        None => ()
      }
    }
    "*" => self.emit("\timul\trax, r10")
    "/" =>
      if mir_body_unsigned_binary(op, lhs.ty(), rhs.ty()) {
        self.emit("\txor\trdx, rdx")
        self.emit("\tdiv\tr10")
      } else {
        self.emit("\tcqo")
        self.emit("\tidiv\tr10")
      }
    "%" => {
      if mir_body_unsigned_binary(op, lhs.ty(), rhs.ty()) {
        self.emit("\txor\trdx, rdx")
        self.emit("\tdiv\tr10")
      } else {
        self.emit("\tcqo")
        self.emit("\tidiv\tr10")
      }
      self.emit("\tmov\trax, rdx")
    }
    "|" => self.emit("\tor\trax, r10")
    "&" => self.emit("\tand\trax, r10")
    "^" => self.emit("\txor\trax, r10")
    "<<" => {
      self.emit("\tmov\trcx, r10")
      self.emit("\tshl\trax, cl")
    }
    ">>" => {
      self.emit("\tmov\trcx, r10")
      if is_unsigned_integer_type(left_ty) {
        self.emit("\tshr\trax, cl")
      } else {
        self.emit("\tsar\trax, cl")
      }
    }
    "==" | "!=" | "<" | ">" | "<=" | ">=" => {
      self.emit("\tcmp\trax, r10")
      let unsigned = mir_body_unsigned_binary(op, lhs.ty(), rhs.ty())
      let cc = match op {
        "==" => "sete"
        "!=" => "setne"
        "<" => if unsigned { "setb" } else { "setl" }
        ">" => if unsigned { "seta" } else { "setg" }
        "<=" => if unsigned { "setbe" } else { "setle" }
        _ => if unsigned { "setae" } else { "setge" }
      }
      self.emit_setcc(cc)
    }
    _ => abort("unsupported MIR body binary operator")
  }
  self.emit_int_conversion_to(ty)
}

///|
fn X64Codegen::gen_mir_stmt(
  self : X64Codegen,
  stmt : @mir.MirStmt,
  offsets : Map[Int, Int],
) -> Unit {
  match stmt {
    MirDeclare(binding, init) =>
      if mir_body_codegen_local_type(binding.ty) {
        match init {
          Some(value) => {
            self.gen_mir_value(value, offsets)
            self.emit_mir_numeric_conversion(value.ty(), binding.ty)
            self.emit_int_conversion_to(binding.ty)
            self.emit_store_local_from_rax(offsets[binding.id], binding.ty)
          }
          None => ()
        }
      } else {
        match init {
          Some(value) => self.gen_mir_value(value, offsets)
          None => ()
        }
      }
    MirExprStmt(value) => self.gen_mir_value(value, offsets)
    MirReturn(value) => {
      match value {
        Some(value) => {
          self.gen_mir_value(value, offsets)
          let ret_ty = self.func_rets[self.func_name]
          self.emit_mir_numeric_conversion(value.ty(), ret_ty)
          self.emit_int_conversion_to(ret_ty)
        }
        None => self.emit("\tmov\trax, 0")
      }
      self.emit("\tjmp\t.L" + self.func_name + "_ret")
    }
    MirIf(cond, then_, else_) => {
      let else_label = self.new_label()
      let end_label = self.new_label()
      self.gen_mir_value(cond, offsets)
      self.emit("\tcmp\trax, 0")
      self.emit("\tje\t" + else_label)
      self.gen_mir_stmts(then_, offsets)
      self.emit("\tjmp\t" + end_label)
      self.emit(else_label + ":")
      self.gen_mir_stmts(else_, offsets)
      self.emit(end_label + ":")
    }
    MirWhile(cond, body) => {
      let start_label = self.new_label()
      let end_label = self.new_label()
      let old_break = self.break_label
      let old_continue = self.continue_label
      self.break_label = Some(end_label)
      self.continue_label = Some(start_label)
      self.emit(start_label + ":")
      self.gen_mir_value(cond, offsets)
      self.emit("\tcmp\trax, 0")
      self.emit("\tje\t" + end_label)
      self.gen_mir_stmts(body, offsets)
      self.emit("\tjmp\t" + start_label)
      self.emit(end_label + ":")
      self.break_label = old_break
      self.continue_label = old_continue
    }
    MirFor(init, cond, inc, body) => {
      let start_label = self.new_label()
      let continue_label = self.new_label()
      let end_label = self.new_label()
      let old_break = self.break_label
      let old_continue = self.continue_label
      self.break_label = Some(end_label)
      self.continue_label = Some(continue_label)
      self.gen_mir_stmts(init, offsets)
      self.emit(start_label + ":")
      self.gen_mir_value(cond, offsets)
      self.emit("\tcmp\trax, 0")
      self.emit("\tje\t" + end_label)
      self.gen_mir_stmts(body, offsets)
      self.emit(continue_label + ":")
      match inc {
        Some(value) => self.gen_mir_value(value, offsets)
        None => ()
      }
      self.emit("\tjmp\t" + start_label)
      self.emit(end_label + ":")
      self.break_label = old_break
      self.continue_label = old_continue
    }
    MirDoWhile(cond, body) => {
      let start_label = self.new_label()
      let continue_label = self.new_label()
      let end_label = self.new_label()
      let old_break = self.break_label
      let old_continue = self.continue_label
      self.break_label = Some(end_label)
      self.continue_label = Some(continue_label)
      self.emit(start_label + ":")
      self.gen_mir_stmts(body, offsets)
      self.emit(continue_label + ":")
      self.gen_mir_value(cond, offsets)
      self.emit("\tcmp\trax, 0")
      self.emit("\tjne\t" + start_label)
      self.emit(end_label + ":")
      self.break_label = old_break
      self.continue_label = old_continue
    }
    MirSwitch(control, cases, body) => {
      let end_label = self.new_label()
      let old_break = self.break_label
      self.break_label = Some(end_label)
      let control_ty = switch_control_type(control.ty())
      self.gen_mir_value(control, offsets)
      self.emit_int_conversion_to(control_ty)
      for c in cases {
        match c.0 {
          Some(value) => {
            self.emit_switch_case_compare(value, control_ty)
            self.emit("\tje\t" + self.label_ref(c.1))
          }
          None => ()
        }
      }
      let mut default_label = end_label
      for c in cases {
        match c.0 {
          None => {
            default_label = self.label_ref(c.1)
            break
          }
          Some(_) => ()
        }
      }
      self.emit("\tjmp\t" + default_label)
      self.gen_mir_stmts(body, offsets)
      self.emit(end_label + ":")
      self.break_label = old_break
    }
    MirLabel(name) => {
      let label = self.label_ref(name)
      self.defined_labels[name] = true
      self.emit(label + ":")
    }
    MirGoto(name) => self.emit("\tjmp\t" + self.label_ref(name))
    MirBreak =>
      match self.break_label {
        Some(label) => self.emit("\tjmp\t" + label)
        None => abort("break outside MIR body loop")
      }
    MirContinue =>
      match self.continue_label {
        Some(label) => self.emit("\tjmp\t" + label)
        None => abort("continue outside MIR body loop")
      }
    MirBlock(stmts) => self.gen_mir_stmts(stmts, offsets)
  }
}

///|
fn X64Codegen::gen_mir_stmts(
  self : X64Codegen,
  stmts : Array[@mir.MirStmt],
  offsets : Map[Int, Int],
) -> Unit {
  for stmt in stmts {
    self.gen_mir_stmt(stmt, offsets)
  }
}

///|
fn X64Codegen::gen_mir_func(
  self : X64Codegen,
  decl : @mir.MirFuncDecl,
  body : @mir.MirFuncBody,
) -> Unit {
  self.local_offsets = {}
  self.var_types = {}
  self.stack_size = 0
  self.stack_align = 16
  self.local_base_reg = "rbp"
  self.func_name = decl.name
  self.va_list_offsets = {}
  self.va_reg_save_offset = -1
  self.va_initial_gp_offset = 0
  self.va_initial_fp_offset = 48
  self.va_initial_overflow_offset = 16
  self.sret_scratch_offset = -1
  self.va_arg_scratch_offset = -1
  self.break_label = None
  self.continue_label = None
  self.emitted_labels = {}
  self.defined_labels = {}
  let offsets = self.mir_body_offsets(body)
  let frame_size = x64_align_to(self.stack_size, 16)
  self.emit_function_section(decl.section)
  self.emit_symbol_binding(
    decl.name,
    decl.is_static,
    decl.is_weak,
    decl.visibility,
  )
  self.emit("\t# kimicc: mir-body")
  self.emit("\t.type\t" + decl.name + ", @function")
  self.emit(decl.name + ":")
  self.emit("\tpush\trbp")
  self.emit("\tmov\trbp, rsp")
  if frame_size > 0 {
    self.emit("\tsub\trsp, " + frame_size.to_string())
  }
  let arg_regs = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
  for i in 0..<body.params.length() {
    let param = body.params[i]
    self.emit_store_int_reg_to_local(arg_regs[i], offsets[param.id])
  }
  self.gen_mir_stmts(body.body, offsets)
  self.emit("\tmov\trax, 0")
  self.emit(".L" + decl.name + "_ret:")
  self.emit("\tmov\trsp, rbp")
  self.emit("\tpop\trbp")
  self.emit("\tret")
  self.emit("\t.size\t" + decl.name + ", .-" + decl.name)
}
