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
    | SInt128
    | UInt128
    | Float
    | Double
    | LongDouble
    | Pointer(_)
    | FuncPtr(_, _, _) => true
    Atomic(inner) => mir_body_codegen_scalar_type(inner)
    _ => false
  }
}

///|
fn mir_body_codegen_int128_type(ty : @ctype.Type) -> Bool {
  match peel_aligned_type(ty) {
    SInt128 | UInt128 => true
    _ => false
  }
}

///|
fn mir_body_codegen_int128_binary_supported(
  op : String,
  lhs : @ctype.Type,
  rhs : @ctype.Type,
  ty : @ctype.Type,
) -> Bool {
  let lhs_int128 = mir_body_codegen_int128_type(lhs)
  let rhs_int128 = mir_body_codegen_int128_type(rhs)
  let ty_int128 = mir_body_codegen_int128_type(ty)
  if !lhs_int128 && !rhs_int128 && !ty_int128 {
    return false
  }
  if op == "<<" || op == ">>" {
    return lhs_int128 && rhs.is_integer() && ty_int128
  }
  match op {
    "+" | "-" | "*" | "/" | "%" | "&" | "|" | "^" => ty_int128
    "==" | "!=" | "<" | ">" | "<=" | ">=" =>
      (lhs_int128 || rhs_int128) && !ty_int128
    _ => false
  }
}

///|
fn mir_body_codegen_int128_unary_supported(
  op : String,
  inner : @ctype.Type,
  ty : @ctype.Type,
) -> Bool {
  let inner_int128 = mir_body_codegen_int128_type(inner)
  let ty_int128 = mir_body_codegen_int128_type(ty)
  if !inner_int128 && !ty_int128 {
    return false
  }
  match op {
    "+" => inner_int128 && ty_int128
    "-" | "~" => ty_int128
    "!" => inner_int128 && !ty_int128
    _ => false
  }
}

///|
fn mir_body_codegen_int128_cast_supported(
  src : @ctype.Type,
  dst : @ctype.Type,
) -> Bool {
  if mir_body_codegen_int128_type(src) || mir_body_codegen_int128_type(dst) {
    src.is_integer() && dst.is_integer()
  } else {
    true
  }
}

///|
fn mir_body_codegen_abi_scalar_type(ty : @ctype.Type) -> Bool {
  mir_body_codegen_abi_int_type(ty) || mir_body_codegen_abi_fp_type(ty)
}

///|
fn mir_body_codegen_abi_int_type(ty : @ctype.Type) -> Bool {
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
    | SInt128
    | UInt128
    | Pointer(_)
    | FuncPtr(_, _, _) => true
    Atomic(inner) => mir_body_codegen_abi_int_type(inner)
    _ => false
  }
}

///|
fn mir_body_codegen_abi_int_slots(ty : @ctype.Type) -> Int {
  match peel_aligned_type(ty) {
    SInt128 | UInt128 => 2
    Atomic(inner) => mir_body_codegen_abi_int_slots(inner)
    _ => 1
  }
}

///|
fn mir_body_codegen_abi_int_stack_align_slots(ty : @ctype.Type) -> Int {
  match peel_aligned_type(ty) {
    SInt128 | UInt128 => 2
    Atomic(inner) => mir_body_codegen_abi_int_stack_align_slots(inner)
    _ => 1
  }
}

///|
fn mir_body_codegen_align_stack_slots(index : Int, align_slots : Int) -> Int {
  (index + align_slots - 1) / align_slots * align_slots
}

///|
fn mir_body_codegen_abi_fp_type(ty : @ctype.Type) -> Bool {
  match peel_aligned_type(ty) {
    Float | Double | LongDouble => true
    Atomic(inner) => mir_body_codegen_abi_fp_type(inner)
    _ => false
  }
}

///|
fn mir_body_codegen_x64_arg_with_stack_supported(ty : @ctype.Type) -> Bool {
  if mir_body_codegen_abi_fp_type(ty) || mir_body_codegen_abi_int_type(ty) {
    return true
  }
  match peel_aligned_type(ty) {
    Struct(_) | Union(_) => true
    _ => false
  }
}

///|
fn mir_body_codegen_x64_args_with_stack_supported(
  params : Array[@ctype.Type],
) -> Bool {
  for param in params {
    if !mir_body_codegen_x64_arg_with_stack_supported(param) {
      return false
    }
  }
  true
}

///|
fn mir_body_codegen_darwin_hfa_return_type(
  ty : @ctype.Type,
  mir : @mir.MirModule,
) -> Bool {
  Codegen::new_with_mir_module(mir).is_hfa_aggregate(ty)
}

///|
fn mir_body_codegen_x64_small_aggregate_return_type(
  ty : @ctype.Type,
  mir : @mir.MirModule,
) -> Bool {
  match mir.target {
    LinuxAmd64 =>
      match peel_aligned_type(ty) {
        Struct(_) | Union(_) =>
          X64Codegen::new_with_mir_module(mir).aggregate_classes(ty) is Some(_)
        _ => false
      }
    DarwinArm64 =>
      match peel_aligned_type(ty) {
        Struct(_) | Union(_) =>
          mir.type_size(ty) <= 16 &&
          !mir_body_codegen_darwin_hfa_return_type(ty, mir)
        _ => false
      }
  }
}

///|
fn mir_body_codegen_x64_memory_aggregate_return_type(
  ty : @ctype.Type,
  mir : @mir.MirModule,
) -> Bool {
  match mir.target {
    LinuxAmd64 =>
      match peel_aligned_type(ty) {
        Struct(_) | Union(_) =>
          X64Codegen::new_with_mir_module(mir).is_memory_aggregate(ty)
        _ => false
      }
    DarwinArm64 =>
      match peel_aligned_type(ty) {
        Struct(_) | Union(_) => mir.type_size(ty) > 16
        _ => false
      }
  }
}

///|
fn mir_body_codegen_register_aggregate_return_type(
  ty : @ctype.Type,
  mir : @mir.MirModule,
) -> Bool {
  mir_body_codegen_x64_small_aggregate_return_type(ty, mir) ||
  mir_body_codegen_darwin_hfa_return_type(ty, mir)
}

///|
fn mir_body_codegen_variadic_args_supported(
  params : Array[@ctype.Type],
  named_count : Int,
  int_arg_limit : Int,
) -> Bool {
  let mut int_count = 0
  let mut fp_reg_count = 0
  for i in 0..<params.length() {
    let param = params[i]
    if mir_body_codegen_abi_fp_type(param) {
      if fp_reg_count < 8 {
        fp_reg_count += 1
      } else if i < named_count {
        return false
      }
    } else if mir_body_codegen_abi_int_type(param) {
      int_count += mir_body_codegen_abi_int_slots(param)
      if int_count > int_arg_limit && i < named_count {
        return false
      }
    } else {
      return false
    }
  }
  true
}

///|
fn mir_body_codegen_darwin_variadic_args_supported(
  params : Array[@ctype.Type],
  named_count : Int,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  let mut int_count = 0
  let mut fp_reg_count = 0
  for i in 0..<params.length() {
    let param = params[i]
    if mir_body_codegen_abi_fp_type(param) {
      if fp_reg_count < 8 {
        fp_reg_count += 1
      } else if i < named_count {
        return false
      }
    } else if mir_body_codegen_abi_int_type(param) {
      int_count += mir_body_codegen_abi_int_slots(param)
      if int_count > int_arg_limit && i < named_count {
        return false
      }
    } else {
      match peel_aligned_type(param) {
        Struct(_) | Union(_) =>
          if i >= named_count {
            let size = mir.type_size(param)
            let slots = if size > 16 { 1 } else if size > 8 { 2 } else { 1 }
            int_count += slots
          } else {
            return false
          }
        _ => return false
      }
    }
  }
  true
}

///|
fn mir_body_codegen_darwin_args_with_stack_supported(
  params : Array[@ctype.Type],
  mir : @mir.MirModule,
) -> Bool {
  let codegen = Codegen::new_with_mir_module(mir)
  for param in params {
    if mir_body_codegen_abi_fp_type(param) {
      ()
    } else if mir_body_codegen_abi_int_type(param) {
      ()
    } else if codegen.is_hfa_aggregate(param) {
      match codegen.darwin_hfa_parts(param) {
        Some(_) => ()
        None => return false
      }
    } else if codegen.is_register_aggregate(param) {
      ()
    } else if codegen.is_memory_aggregate(param) {
      ()
    } else {
      return false
    }
  }
  true
}

///|
fn mir_body_codegen_x64_variadic_args_supported(
  params : Array[@ctype.Type],
  named_count : Int,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  ignore(named_count)
  ignore(int_arg_limit)
  ignore(mir)
  for param in params {
    if !mir_body_codegen_x64_arg_with_stack_supported(param) {
      return false
    }
  }
  true
}

///|
fn mir_body_codegen_floating_type(ty : @ctype.Type) -> Bool {
  match peel_aligned_type(ty) {
    Float | Double | LongDouble => true
    Atomic(inner) => mir_body_codegen_floating_type(inner)
    _ => false
  }
}

///|
fn mir_body_codegen_double_type(ty : @ctype.Type) -> Bool {
  match peel_aligned_type(ty) {
    Double | LongDouble => true
    Atomic(inner) => mir_body_codegen_double_type(inner)
    _ => false
  }
}

///|
fn mir_body_codegen_fp_operand_type(ty : @ctype.Type) -> Bool {
  mir_body_codegen_floating_type(ty) || ty.is_integer()
}

///|
fn mir_body_codegen_x64_unsupported_long_double_type(ty : @ctype.Type) -> Bool {
  match peel_aligned_type(ty) {
    LongDouble => true
    Array(elem, _) | Atomic(elem) | Aligned(elem, _) =>
      mir_body_codegen_x64_unsupported_long_double_type(elem)
    _ => false
  }
}

///|
fn mir_body_codegen_x64_unsupported_long_double_value(
  value : @mir.MirValue,
) -> Bool {
  if mir_body_codegen_x64_unsupported_long_double_type(value.ty()) {
    return true
  }
  match value {
    MirUnary(_, inner, _) | MirCast(_, inner) | MirAggregateArg(inner, _) =>
      mir_body_codegen_x64_unsupported_long_double_value(inner)
    MirElemAddr(base, index, _) =>
      mir_body_codegen_x64_unsupported_long_double_value(base) ||
      mir_body_codegen_x64_unsupported_long_double_value(index)
    MirOffsetAddr(base, _, _) | MirLoad(base, _) =>
      mir_body_codegen_x64_unsupported_long_double_value(base)
    MirBinary(_, lhs, rhs, _) =>
      mir_body_codegen_x64_unsupported_long_double_value(lhs) ||
      mir_body_codegen_x64_unsupported_long_double_value(rhs)
    MirOverflow(_, left, right, result_ptr) =>
      mir_body_codegen_x64_unsupported_long_double_value(left) ||
      mir_body_codegen_x64_unsupported_long_double_value(right) ||
      mir_body_codegen_x64_unsupported_long_double_value(result_ptr)
    MirBzero(dst, size) =>
      mir_body_codegen_x64_unsupported_long_double_value(dst) ||
      mir_body_codegen_x64_unsupported_long_double_value(size)
    MirAtomicLoad(ptr, order, _) =>
      mir_body_codegen_x64_unsupported_long_double_value(ptr) ||
      mir_body_codegen_x64_unsupported_long_double_value(order)
    MirAtomicStore(ptr, stored, order) =>
      mir_body_codegen_x64_unsupported_long_double_value(ptr) ||
      mir_body_codegen_x64_unsupported_long_double_value(stored) ||
      mir_body_codegen_x64_unsupported_long_double_value(order)
    MirAtomicUpdate(_, _, ptr, stored, extras, _) => {
      if mir_body_codegen_x64_unsupported_long_double_value(ptr) ||
        mir_body_codegen_x64_unsupported_long_double_value(stored) {
        return true
      }
      for extra in extras {
        if mir_body_codegen_x64_unsupported_long_double_value(extra) {
          return true
        }
      }
      false
    }
    MirAtomicExchange(ptr, stored, extras, _) => {
      if mir_body_codegen_x64_unsupported_long_double_value(ptr) ||
        mir_body_codegen_x64_unsupported_long_double_value(stored) {
        return true
      }
      for extra in extras {
        if mir_body_codegen_x64_unsupported_long_double_value(extra) {
          return true
        }
      }
      false
    }
    MirAtomicCompareExchange(ptr, expected, desired, extras) => {
      if mir_body_codegen_x64_unsupported_long_double_value(ptr) ||
        mir_body_codegen_x64_unsupported_long_double_value(expected) ||
        mir_body_codegen_x64_unsupported_long_double_value(desired) {
        return true
      }
      for extra in extras {
        if mir_body_codegen_x64_unsupported_long_double_value(extra) {
          return true
        }
      }
      false
    }
    MirLibCall(_, args, _) => {
      for arg in args {
        if mir_body_codegen_x64_unsupported_long_double_value(arg) {
          return true
        }
      }
      false
    }
    MirCall(_, args, _) | MirIndirectCall(_, args, _) => {
      for arg in args {
        if mir_body_codegen_x64_unsupported_long_double_value(arg) {
          return true
        }
      }
      match value {
        MirIndirectCall(callee, _, _) =>
          mir_body_codegen_x64_unsupported_long_double_value(callee)
        _ => false
      }
    }
    MirStore(ptr, rhs, _)
    | MirPreUpdateMemory(ptr, _, rhs, _)
    | MirPostUpdateMemory(ptr, _, rhs, _) =>
      mir_body_codegen_x64_unsupported_long_double_value(ptr) ||
      mir_body_codegen_x64_unsupported_long_double_value(rhs)
    MirAssignLocal(_, rhs) | MirPostUpdateLocal(_, _, rhs, _) =>
      mir_body_codegen_x64_unsupported_long_double_value(rhs)
    MirTernary(cond, then_, else_, _) =>
      mir_body_codegen_x64_unsupported_long_double_value(cond) ||
      mir_body_codegen_x64_unsupported_long_double_value(then_) ||
      mir_body_codegen_x64_unsupported_long_double_value(else_)
    MirVaStart(ap) | MirVaEnd(ap) | MirVaArg(ap, _) | MirVaArgAddr(ap, _) =>
      mir_body_codegen_x64_unsupported_long_double_value(ap)
    MirVaCopy(target, source) =>
      mir_body_codegen_x64_unsupported_long_double_value(target) ||
      mir_body_codegen_x64_unsupported_long_double_value(source)
    _ => false
  }
}

///|
fn mir_body_codegen_x64_unsupported_long_double_stmt(
  stmt : @mir.MirStmt,
) -> Bool {
  match stmt {
    MirDeclare(binding, init) =>
      mir_body_codegen_x64_unsupported_long_double_type(binding.ty) ||
      (match init {
        Some(value) => mir_body_codegen_x64_unsupported_long_double_value(value)
        None => false
      })
    MirExprStmt(value) | MirReturn(Some(value)) =>
      mir_body_codegen_x64_unsupported_long_double_value(value)
    MirIf(cond, then_, else_) =>
      mir_body_codegen_x64_unsupported_long_double_value(cond) ||
      mir_body_codegen_x64_unsupported_long_double_stmts(then_) ||
      mir_body_codegen_x64_unsupported_long_double_stmts(else_)
    MirWhile(cond, body) | MirDoWhile(cond, body) =>
      mir_body_codegen_x64_unsupported_long_double_value(cond) ||
      mir_body_codegen_x64_unsupported_long_double_stmts(body)
    MirFor(init, cond, inc, body) =>
      mir_body_codegen_x64_unsupported_long_double_stmts(init) ||
      mir_body_codegen_x64_unsupported_long_double_value(cond) ||
      (match inc {
        Some(value) => mir_body_codegen_x64_unsupported_long_double_value(value)
        None => false
      }) ||
      mir_body_codegen_x64_unsupported_long_double_stmts(body)
    MirSwitch(control, _, body) =>
      mir_body_codegen_x64_unsupported_long_double_value(control) ||
      mir_body_codegen_x64_unsupported_long_double_stmts(body)
    MirBlock(body) => mir_body_codegen_x64_unsupported_long_double_stmts(body)
    _ => false
  }
}

///|
fn mir_body_codegen_x64_unsupported_long_double_stmts(
  stmts : Array[@mir.MirStmt],
) -> Bool {
  for stmt in stmts {
    if mir_body_codegen_x64_unsupported_long_double_stmt(stmt) {
      return true
    }
  }
  false
}

///|
fn mir_body_codegen_x64_unsupported_long_double_body(
  body : @mir.MirFuncBody,
) -> Bool {
  if mir_body_codegen_x64_unsupported_long_double_type(body.ret) {
    return true
  }
  for param in body.params {
    if mir_body_codegen_x64_unsupported_long_double_type(param.ty) {
      return true
    }
  }
  for binding in body.locals {
    if mir_body_codegen_x64_unsupported_long_double_type(binding.ty) {
      return true
    }
  }
  mir_body_codegen_x64_unsupported_long_double_stmts(body.body)
}

///|
fn mir_body_codegen_fp_binary_type(
  lhs : @ctype.Type,
  rhs : @ctype.Type,
  ty : @ctype.Type,
) -> @ctype.Type {
  if mir_body_codegen_double_type(ty) ||
    mir_body_codegen_double_type(lhs) ||
    mir_body_codegen_double_type(rhs) {
    Double
  } else {
    Float
  }
}

///|
fn mir_body_codegen_arm_fp_reg(ty : @ctype.Type, index : Int) -> String {
  let prefix = if peel_aligned_type(ty) == Float { "s" } else { "d" }
  prefix + index.to_string()
}

///|
fn mir_body_codegen_arm_fp_bits_reg(ty : @ctype.Type, reg : String) -> String {
  if peel_aligned_type(ty) == Float {
    w_reg(reg)
  } else {
    reg
  }
}

///|
fn Codegen::emit_mir_fp_class_constant(
  self : Codegen,
  reg : String,
  ty : @ctype.Type,
  kind : String,
) -> Unit {
  match peel_aligned_type(ty) {
    Float =>
      match kind {
        "inf" => self.emit("\tmovz\t" + reg + ", #0x7F80, lsl #16")
        "normal_min" => self.emit("\tmovz\t" + reg + ", #0x80, lsl #16")
        _ => self.emit("\tmov\t" + reg + ", #0")
      }
    _ =>
      match kind {
        "inf" => {
          self.emit("\tmovz\t" + reg + ", #0")
          self.emit("\tmovk\t" + reg + ", #0, lsl #16")
          self.emit("\tmovk\t" + reg + ", #0, lsl #32")
          self.emit("\tmovk\t" + reg + ", #0x7FF0, lsl #48")
        }
        "normal_min" => {
          self.emit("\tmovz\t" + reg + ", #0")
          self.emit("\tmovk\t" + reg + ", #0, lsl #16")
          self.emit("\tmovk\t" + reg + ", #0, lsl #32")
          self.emit("\tmovk\t" + reg + ", #0x10, lsl #48")
        }
        _ => self.emit("\tmov\t" + reg + ", #0")
      }
  }
}

///|
fn Codegen::emit_mir_fp_class_result(
  self : Codegen,
  op : String,
  ty : @ctype.Type,
) -> Unit {
  if op == "fp_signbit" {
    match peel_aligned_type(ty) {
      Float => self.emit("\tlsr\tw9, w9, #31")
      _ => self.emit("\tlsr\tx9, x9, #63")
    }
    return
  }
  let fp_reg = mir_body_codegen_arm_fp_reg(ty, 9)
  let const_fp_reg = mir_body_codegen_arm_fp_reg(ty, 10)
  let const_bits_reg = mir_body_codegen_arm_fp_bits_reg(ty, "x10")
  self.emit(
    "\tfmov\t" + fp_reg + ", " + mir_body_codegen_arm_fp_bits_reg(ty, "x9"),
  )
  match op {
    "fp_isnan" => {
      self.emit("\tfcmp\t" + fp_reg + ", " + fp_reg)
      self.emit("\tcset\tx9, vs")
    }
    "fp_isinf" => {
      self.emit("\tfabs\t" + fp_reg + ", " + fp_reg)
      self.emit_mir_fp_class_constant(const_bits_reg, ty, "inf")
      self.emit("\tfmov\t" + const_fp_reg + ", " + const_bits_reg)
      self.emit("\tfcmp\t" + fp_reg + ", " + const_fp_reg)
      self.emit("\tcset\tx9, eq")
    }
    "fp_isfinite" => {
      self.emit("\tfabs\t" + fp_reg + ", " + fp_reg)
      self.emit_mir_fp_class_constant(const_bits_reg, ty, "inf")
      self.emit("\tfmov\t" + const_fp_reg + ", " + const_bits_reg)
      self.emit("\tfcmp\t" + fp_reg + ", " + const_fp_reg)
      self.emit("\tcset\tx9, mi")
    }
    "fp_isnormal" => {
      self.emit("\tfabs\t" + fp_reg + ", " + fp_reg)
      self.emit_mir_fp_class_constant(const_bits_reg, ty, "normal_min")
      self.emit("\tfmov\t" + const_fp_reg + ", " + const_bits_reg)
      self.emit("\tfcmp\t" + fp_reg + ", " + const_fp_reg)
      self.emit("\tcset\tx11, ge")
      self.emit_mir_fp_class_constant(const_bits_reg, ty, "inf")
      self.emit("\tfmov\t" + const_fp_reg + ", " + const_bits_reg)
      self.emit("\tfcmp\t" + fp_reg + ", " + const_fp_reg)
      self.emit("\tcset\tx9, mi")
      self.emit("\tand\tx9, x9, x11")
    }
    _ => self.emit("\tmov\tx9, #0")
  }
}

///|
fn Codegen::emit_mir_fp_arg_from_x9(
  self : Codegen,
  ty : @ctype.Type,
  index : Int,
) -> Unit {
  self.emit(
    "\tfmov\t" +
    mir_body_codegen_arm_fp_reg(ty, index) +
    ", " +
    mir_body_codegen_arm_fp_bits_reg(ty, "x9"),
  )
}

///|
fn Codegen::emit_mir_fp_return_to_x9(self : Codegen, ty : @ctype.Type) -> Unit {
  self.emit(
    "\tfmov\t" +
    mir_body_codegen_arm_fp_bits_reg(ty, "x9") +
    ", " +
    mir_body_codegen_arm_fp_reg(ty, 0),
  )
}

///|
fn Codegen::emit_mir_fp_return_from_x9(
  self : Codegen,
  ty : @ctype.Type,
) -> Unit {
  self.emit(
    "\tfmov\t" +
    mir_body_codegen_arm_fp_reg(ty, 0) +
    ", " +
    mir_body_codegen_arm_fp_bits_reg(ty, "x9"),
  )
}

///|
fn mir_body_compare_op(op : String) -> Bool {
  match op {
    "==" | "!=" | "<" | ">" | "<=" | ">=" | "<>" | "unordered" => true
    _ => false
  }
}

///|
fn mir_body_arith_op(op : String) -> Bool {
  match op {
    "+" | "-" | "*" | "/" => true
    _ => false
  }
}

///|
fn mir_body_fp_class_op(op : String) -> Bool {
  match op {
    "fp_isnan" | "fp_isinf" | "fp_isfinite" | "fp_isnormal" | "fp_signbit" =>
      true
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
  mir_body_codegen_fp_operand_type(lhs) &&
  mir_body_codegen_fp_operand_type(rhs) &&
  (mir_body_codegen_floating_type(lhs) || mir_body_codegen_floating_type(rhs))
}

///|
fn mir_body_codegen_fp_arith_supported(
  op : String,
  lhs : @ctype.Type,
  rhs : @ctype.Type,
  ty : @ctype.Type,
) -> Bool {
  mir_body_arith_op(op) &&
  mir_body_codegen_scalar_type(ty) &&
  mir_body_codegen_fp_operand_type(lhs) &&
  mir_body_codegen_fp_operand_type(rhs) &&
  (mir_body_codegen_floating_type(lhs) || mir_body_codegen_floating_type(rhs))
}

///|
fn mir_body_codegen_fp_copysign_supported(
  op : String,
  lhs : @ctype.Type,
  rhs : @ctype.Type,
  ty : @ctype.Type,
) -> Bool {
  op == "copysign" &&
  mir_body_codegen_floating_type(ty) &&
  mir_body_codegen_fp_operand_type(lhs) &&
  mir_body_codegen_fp_operand_type(rhs)
}

///|
fn mir_body_codegen_fp_update_supported(
  op : String,
  lhs : @ctype.Type,
  rhs : @ctype.Type,
) -> Bool {
  mir_body_arith_op(op) &&
  mir_body_codegen_fp_operand_type(lhs) &&
  mir_body_codegen_fp_operand_type(rhs) &&
  (mir_body_codegen_floating_type(lhs) || mir_body_codegen_floating_type(rhs))
}

///|
fn mir_body_codegen_local_type(ty : @ctype.Type) -> Bool {
  match ty {
    Aligned(inner, _) => mir_body_codegen_local_type(inner)
    Array(elem, _) => mir_body_codegen_local_type(elem)
    Struct(_) | Union(_) => true
    _ => mir_body_codegen_scalar_type(ty)
  }
}

///|
fn mir_body_codegen_addressed_object_type(ty : @ctype.Type) -> Bool {
  match ty {
    Aligned(inner, _) => mir_body_codegen_addressed_object_type(inner)
    _ => mir_body_codegen_local_type(ty)
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
fn mir_body_codegen_register_aggregate_call_value_supported(
  value : @mir.MirValue,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  match value {
    MirCall(name, args, ty) => {
      if !mir_body_codegen_register_aggregate_return_type(ty, mir) ||
        !mir_body_codegen_call_supported(name, args, ty, int_arg_limit, mir) {
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
      if !mir_body_codegen_register_aggregate_return_type(ty, mir) ||
        !mir_body_codegen_value_supported(callee, int_arg_limit, mir) ||
        !mir_body_codegen_indirect_call_supported(
          callee.ty(),
          args,
          ty,
          int_arg_limit,
          mir,
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
    _ => false
  }
}

///|
fn mir_body_codegen_memory_aggregate_call_value_supported(
  value : @mir.MirValue,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  match value {
    MirCall(name, args, ty) => {
      if !mir_body_codegen_x64_memory_aggregate_return_type(ty, mir) ||
        !mir_body_codegen_call_supported(name, args, ty, int_arg_limit, mir) {
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
      if !mir_body_codegen_x64_memory_aggregate_return_type(ty, mir) ||
        !mir_body_codegen_value_supported(callee, int_arg_limit, mir) ||
        !mir_body_codegen_indirect_call_supported(
          callee.ty(),
          args,
          ty,
          int_arg_limit,
          mir,
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
    _ => false
  }
}

///|
fn mir_body_codegen_value_supported(
  value : @mir.MirValue,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  match value {
    MirAggregateArg(addr, ty) => {
      let aggregate = match peel_aligned_type(ty) {
        Struct(_) | Union(_) => true
        _ => false
      }
      return aggregate &&
        mir_body_codegen_value_supported(addr, int_arg_limit, mir)
    }
    MirCall(_, _, _) | MirIndirectCall(_, _, _) => {
      if mir_body_codegen_register_aggregate_call_value_supported(
          value, int_arg_limit, mir,
        ) {
        return true
      }
      if mir_body_codegen_memory_aggregate_call_value_supported(
          value, int_arg_limit, mir,
        ) {
        return true
      }
    }
    MirStore(ptr, rhs, ty) => {
      if mir_body_codegen_register_aggregate_return_type(ty, mir) &&
        mir_body_codegen_value_supported(ptr, int_arg_limit, mir) &&
        mir_body_codegen_aggregate_return_value_supported(
          rhs, int_arg_limit, mir,
        ) {
        return true
      }
      if mir_body_codegen_x64_memory_aggregate_return_type(ty, mir) &&
        mir_body_codegen_value_supported(ptr, int_arg_limit, mir) &&
        mir_body_codegen_memory_aggregate_return_value_supported(
          rhs, int_arg_limit, mir,
        ) {
        return true
      }
    }
    _ => ()
  }
  if !mir_body_codegen_scalar_type(value.ty()) {
    return false
  }
  match value {
    MirConst(_, ty) => mir_body_codegen_scalar_type(ty)
    MirLocal(binding) => mir_body_codegen_scalar_type(binding.ty)
    MirAddrLocal(binding) => mir_body_codegen_local_type(binding.ty)
    MirAddrGlobal(_, ty) => mir_body_codegen_addressed_object_type(ty)
    MirFuncAddr(name, ty) =>
      mir.funcs.contains(name) && mir_body_codegen_scalar_type(ty)
    MirLabelAddr(_) => true
    MirStringAddr(_) => true
    MirElemAddr(base, index, elem_ty) =>
      mir_body_codegen_addressed_object_type(elem_ty) &&
      mir_body_codegen_array_address_base(base, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(index, int_arg_limit, mir)
    MirOffsetAddr(base, _, ty) =>
      mir_body_codegen_addressed_object_type(ty) &&
      mir_body_codegen_value_supported(base, int_arg_limit, mir)
    MirLoad(ptr, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(ptr, int_arg_limit, mir)
    MirUnary(op, inner, ty) => {
      if !mir_body_codegen_scalar_type(ty) {
        return false
      }
      if op == "alloca" {
        return mir_body_codegen_return_pointer_type(ty) &&
          mir_body_codegen_scalar_type(inner.ty()) &&
          mir_body_codegen_value_supported(inner, int_arg_limit, mir)
      }
      if op == "frame_address" || op == "return_address" {
        return mir_body_codegen_return_pointer_type(ty) &&
          inner.ty().is_integer() &&
          mir_body_codegen_value_supported(inner, int_arg_limit, mir)
      }
      if op == "sync_synchronize" ||
        op == "atomic_thread_fence" ||
        op == "atomic_signal_fence" {
        return peel_aligned_type(ty) is Void &&
          mir_body_codegen_scalar_type(inner.ty()) &&
          mir_body_codegen_value_supported(inner, int_arg_limit, mir)
      }
      if op == "trap" {
        return peel_aligned_type(ty) is Void &&
          mir_body_codegen_value_supported(inner, int_arg_limit, mir)
      }
      if mir_body_fp_class_op(op) {
        return !mir_body_codegen_floating_type(ty) &&
          mir_body_codegen_floating_type(inner.ty()) &&
          mir_body_codegen_value_supported(inner, int_arg_limit, mir)
      }
      if mir_body_codegen_int128_type(ty) ||
        mir_body_codegen_int128_type(inner.ty()) {
        return mir_body_codegen_int128_unary_supported(op, inner.ty(), ty) &&
          mir_body_codegen_value_supported(inner, int_arg_limit, mir)
      }
      (if mir_body_codegen_floating_type(ty) ||
        mir_body_codegen_floating_type(inner.ty()) {
        if op == "!" {
          !mir_body_codegen_floating_type(ty) &&
          mir_body_codegen_floating_type(inner.ty())
        } else {
          (op == "+" || op == "-" || op == "fabs" || op == "fsqrt") &&
          mir_body_codegen_floating_type(ty) &&
          mir_body_codegen_floating_type(inner.ty())
        }
      } else {
        true
      }) &&
      mir_body_codegen_value_supported(inner, int_arg_limit, mir)
    }
    MirBinary(op, lhs, rhs, ty) => {
      if !mir_body_codegen_scalar_type(ty) {
        return false
      }
      if op == "alloca_align" {
        return mir_body_codegen_return_pointer_type(ty) &&
          mir_body_codegen_scalar_type(lhs.ty()) &&
          mir_body_codegen_scalar_type(rhs.ty()) &&
          mir_body_codegen_value_supported(lhs, int_arg_limit, mir) &&
          mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
      }
      if op == "&&" || op == "||" {
        return !mir_body_codegen_floating_type(ty) &&
          mir_body_codegen_value_supported(lhs, int_arg_limit, mir) &&
          mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
      }
      if op == "," {
        return mir_body_codegen_value_supported(lhs, int_arg_limit, mir) &&
          mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
      }
      if mir_body_codegen_rotate_op_supported(op, lhs.ty(), rhs.ty(), ty) {
        return mir_body_codegen_value_supported(lhs, int_arg_limit, mir) &&
          mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
      }
      if mir_body_codegen_fp_compare_supported(op, lhs.ty(), rhs.ty(), ty) {
        return mir_body_codegen_value_supported(lhs, int_arg_limit, mir) &&
          mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
      }
      if mir_body_codegen_fp_arith_supported(op, lhs.ty(), rhs.ty(), ty) {
        return mir_body_codegen_value_supported(lhs, int_arg_limit, mir) &&
          mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
      }
      if mir_body_codegen_fp_copysign_supported(op, lhs.ty(), rhs.ty(), ty) {
        return mir_body_codegen_value_supported(lhs, int_arg_limit, mir) &&
          mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
      }
      if mir_body_codegen_int128_type(lhs.ty()) ||
        mir_body_codegen_int128_type(rhs.ty()) ||
        mir_body_codegen_int128_type(ty) {
        return mir_body_codegen_int128_binary_supported(
            op,
            lhs.ty(),
            rhs.ty(),
            ty,
          ) &&
          mir_body_codegen_value_supported(lhs, int_arg_limit, mir) &&
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
      mir_body_codegen_int128_cast_supported(inner.ty(), ty) &&
      mir_body_codegen_value_supported(inner, int_arg_limit, mir)
    MirVaArg(ap, ty) =>
      !(peel_aligned_type(ty) is Void) &&
      mir_body_codegen_abi_scalar_type(ty) &&
      mir_body_codegen_value_supported(ap, int_arg_limit, mir)
    MirVaArgAddr(ap, ty) =>
      (match peel_aligned_type(ty) {
        Struct(_) | Union(_) => true
        _ => false
      }) &&
      mir_body_codegen_local_type(ty) &&
      mir_body_codegen_value_supported(ap, int_arg_limit, mir)
    MirAssignLocal(binding, rhs) =>
      mir_body_codegen_scalar_type(binding.ty) &&
      mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
    MirStore(ptr, rhs, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(ptr, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
    MirPostUpdateLocal(binding, op, rhs, ty) =>
      mir_body_codegen_scalar_type(binding.ty) &&
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(rhs, int_arg_limit, mir) &&
      (if mir_body_codegen_int128_type(binding.ty) ||
        mir_body_codegen_int128_type(rhs.ty()) ||
        mir_body_codegen_int128_type(ty) {
        false
      } else if mir_body_codegen_floating_type(binding.ty) ||
        mir_body_codegen_floating_type(rhs.ty()) ||
        mir_body_codegen_floating_type(ty) {
        (op == "+" || op == "-") &&
        mir_body_codegen_fp_update_supported(op, binding.ty, rhs.ty())
      } else {
        true
      })
    MirPreUpdateMemory(ptr, op, rhs, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(ptr, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(rhs, int_arg_limit, mir) &&
      (if mir_body_codegen_int128_type(ty) ||
        mir_body_codegen_int128_type(rhs.ty()) {
        false
      } else if mir_body_codegen_floating_type(ty) ||
        mir_body_codegen_floating_type(rhs.ty()) {
        mir_body_codegen_fp_update_supported(op, ty, rhs.ty())
      } else {
        true
      })
    MirPostUpdateMemory(ptr, op, rhs, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(ptr, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(rhs, int_arg_limit, mir) &&
      (if mir_body_codegen_int128_type(ty) ||
        mir_body_codegen_int128_type(rhs.ty()) {
        false
      } else if mir_body_codegen_floating_type(ty) ||
        mir_body_codegen_floating_type(rhs.ty()) {
        (op == "+" || op == "-") &&
        mir_body_codegen_fp_update_supported(op, ty, rhs.ty())
      } else {
        true
      })
    MirTernary(cond, then_, else_, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(cond, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(then_, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(else_, int_arg_limit, mir)
    MirOverflow(op, left, right, result_ptr) =>
      mir_body_codegen_overflow_supported(
        op, left, right, result_ptr, int_arg_limit, mir,
      )
    MirVaStart(target) =>
      match target {
        MirLocal(_) => true
        _ => false
      }
    MirVaCopy(target, source) =>
      (match target {
        MirLocal(_) => true
        _ => false
      }) &&
      mir_body_codegen_value_supported(source, int_arg_limit, mir)
    MirVaEnd(target) =>
      mir_body_codegen_value_supported(target, int_arg_limit, mir)
    MirBzero(dst, size) =>
      mir_body_codegen_value_supported(dst, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(size, int_arg_limit, mir)
    MirAtomicLoad(ptr, order, ty) =>
      mir_body_codegen_atomic_load_supported(ptr, order, ty, int_arg_limit, mir)
    MirAtomicStore(ptr, value, order) =>
      mir_body_codegen_atomic_store_supported(
        ptr, value, order, int_arg_limit, mir,
      )
    MirAtomicUpdate(op, _, ptr, value, extras, ty) =>
      mir_body_codegen_atomic_update_supported(
        op, ptr, value, extras, ty, int_arg_limit, mir,
      )
    MirAtomicExchange(ptr, value, extras, ty) =>
      mir_body_codegen_atomic_exchange_supported(
        ptr, value, extras, ty, int_arg_limit, mir,
      )
    MirAtomicCompareExchange(ptr, expected, desired, extras) =>
      mir_body_codegen_atomic_compare_exchange_supported(
        ptr, expected, desired, extras, int_arg_limit, mir,
      )
    MirLibCall(name, args, ty) => {
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
          mir,
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
    MirAggregateArg(_, _) => false
  }
}

///|
fn mir_body_codegen_atomic_target_type(ty : @ctype.Type) -> @ctype.Type {
  match ty {
    Pointer(Atomic(inner)) | Array(Atomic(inner), _) => inner
    Pointer(Aligned(inner, _)) | Array(Aligned(inner, _), _) => inner
    Pointer(inner) | Array(inner, _) => inner
    Atomic(inner) | Aligned(inner, _) => inner
    _ => SLongLong
  }
}

///|
fn mir_body_codegen_atomic_load_supported(
  ptr : @mir.MirValue,
  order : @mir.MirValue,
  ret : @ctype.Type,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  mir_body_codegen_abi_scalar_type(ret) &&
  mir_body_codegen_abi_scalar_type(
    mir_body_codegen_atomic_target_type(ptr.ty()),
  ) &&
  mir_body_codegen_value_supported(ptr, int_arg_limit, mir) &&
  mir_body_codegen_value_supported(order, int_arg_limit, mir)
}

///|
fn mir_body_codegen_atomic_store_supported(
  ptr : @mir.MirValue,
  value : @mir.MirValue,
  order : @mir.MirValue,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  peel_aligned_type(value.ty()) != Void &&
  mir_body_codegen_abi_scalar_type(
    mir_body_codegen_atomic_target_type(ptr.ty()),
  ) &&
  mir_body_codegen_value_supported(ptr, int_arg_limit, mir) &&
  mir_body_codegen_value_supported(value, int_arg_limit, mir) &&
  mir_body_codegen_value_supported(order, int_arg_limit, mir)
}

///|
fn mir_body_codegen_atomic_rmw_target_supported(ptr : @mir.MirValue) -> Bool {
  let elem_ty = mir_body_codegen_atomic_target_type(ptr.ty())
  mir_body_codegen_abi_int_type(elem_ty) &&
  !mir_body_codegen_int128_type(elem_ty)
}

///|
fn mir_body_codegen_atomic_update_op_supported(op : String) -> Bool {
  op == "+" ||
  op == "-" ||
  op == "&" ||
  op == "|" ||
  op == "^" ||
  op == "~&" ||
  op == "max" ||
  op == "min" ||
  op == "umax" ||
  op == "umin"
}

///|
fn mir_body_codegen_atomic_extra_values_supported(
  values : Array[@mir.MirValue],
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  for value in values {
    if !mir_body_codegen_value_supported(value, int_arg_limit, mir) {
      return false
    }
  }
  true
}

///|
fn mir_body_codegen_atomic_update_supported(
  op : String,
  ptr : @mir.MirValue,
  value : @mir.MirValue,
  extras : Array[@mir.MirValue],
  ret : @ctype.Type,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  mir_body_codegen_atomic_update_op_supported(op) &&
  mir_body_codegen_abi_int_type(ret) &&
  !mir_body_codegen_int128_type(ret) &&
  mir_body_codegen_atomic_rmw_target_supported(ptr) &&
  mir_body_codegen_value_supported(ptr, int_arg_limit, mir) &&
  mir_body_codegen_value_supported(value, int_arg_limit, mir) &&
  mir_body_codegen_atomic_extra_values_supported(extras, int_arg_limit, mir)
}

///|
fn mir_body_codegen_atomic_exchange_supported(
  ptr : @mir.MirValue,
  value : @mir.MirValue,
  extras : Array[@mir.MirValue],
  ret : @ctype.Type,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  mir_body_codegen_abi_int_type(ret) &&
  !mir_body_codegen_int128_type(ret) &&
  mir_body_codegen_atomic_rmw_target_supported(ptr) &&
  mir_body_codegen_value_supported(ptr, int_arg_limit, mir) &&
  mir_body_codegen_value_supported(value, int_arg_limit, mir) &&
  mir_body_codegen_atomic_extra_values_supported(extras, int_arg_limit, mir)
}

///|
fn mir_body_codegen_atomic_compare_exchange_supported(
  ptr : @mir.MirValue,
  expected : @mir.MirValue,
  desired : @mir.MirValue,
  extras : Array[@mir.MirValue],
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  mir_body_codegen_atomic_rmw_target_supported(ptr) &&
  mir_body_codegen_value_supported(ptr, int_arg_limit, mir) &&
  mir_body_codegen_value_supported(expected, int_arg_limit, mir) &&
  mir_body_codegen_value_supported(desired, int_arg_limit, mir) &&
  mir_body_codegen_atomic_extra_values_supported(extras, int_arg_limit, mir)
}

///|
fn mir_body_codegen_rotate_op(op : String) -> (Int, Bool)? {
  match op {
    "rotl32" => Some((32, true))
    "rotr32" => Some((32, false))
    "rotl64" => Some((64, true))
    "rotr64" => Some((64, false))
    _ => None
  }
}

///|
fn mir_body_codegen_rotate_op_supported(
  op : String,
  lhs : @ctype.Type,
  rhs : @ctype.Type,
  ty : @ctype.Type,
) -> Bool {
  mir_body_codegen_rotate_op(op) is Some(_) &&
  ty.is_integer() &&
  lhs.is_integer() &&
  rhs.is_integer() &&
  !is_int128_type(ty) &&
  !is_int128_type(lhs) &&
  !is_int128_type(rhs)
}

///|
fn mir_body_codegen_return_pointer_type(ty : @ctype.Type) -> Bool {
  peel_aligned_type(ty) is Pointer(_)
}

///|
fn mir_body_codegen_overflow_result_type(
  result_ptr : @mir.MirValue,
) -> @ctype.Type? {
  match pointer_or_array_element_type(result_ptr.ty()) {
    Some(ty) => Some(peel_aligned_type(ty))
    None => None
  }
}

///|
fn mir_body_codegen_overflow_op_supported(op : String) -> Bool {
  op == "+" || op == "-" || op == "*"
}

///|
fn mir_body_codegen_overflow_supported(
  op : String,
  left : @mir.MirValue,
  right : @mir.MirValue,
  result_ptr : @mir.MirValue,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  if !mir_body_codegen_overflow_op_supported(op) ||
    !mir_body_codegen_value_supported(left, int_arg_limit, mir) ||
    !mir_body_codegen_value_supported(right, int_arg_limit, mir) ||
    !mir_body_codegen_value_supported(result_ptr, int_arg_limit, mir) {
    return false
  }
  match mir_body_codegen_overflow_result_type(result_ptr) {
    Some(ty) => ty.is_integer() && !is_int128_type(ty)
    None => false
  }
}

///|
fn mir_body_codegen_builtin_lib_call_supported(
  name : String,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
  int_arg_limit : Int,
) -> Bool {
  if mir_body_codegen_printf_libcall_variadic(name) && ret.is_integer() {
    let params : Array[@ctype.Type] = []
    for i in 0..<args.length() {
      match mir_body_codegen_lowered_builtin_arg_type(name, i) {
        Some(ty) => params.push(ty)
        None => params.push(args[i].ty())
      }
    }
    return mir_body_codegen_variadic_args_supported(
      params,
      mir_body_codegen_direct_call_named_arg_count(name),
      int_arg_limit,
    )
  }
  false
}

///|
fn mir_body_codegen_direct_call_symbol(name : String) -> String {
  name
}

///|
fn mir_body_codegen_direct_call_source_indexes(
  args : Array[@mir.MirValue],
) -> Array[Int] {
  let indexes = []
  for i in 0..<args.length() {
    indexes.push(i)
  }
  indexes
}

///|
fn mir_body_codegen_direct_call_variadic(name : String) -> Bool {
  if mir_body_codegen_printf_libcall_variadic(name) {
    return true
  }
  false
}

///|
fn mir_body_codegen_printf_libcall_variadic(name : String) -> Bool {
  match name {
    "snprintf" | "sprintf" | "printf" | "fprintf" => true
    _ => false
  }
}

///|
fn mir_body_codegen_direct_call_named_arg_count(name : String) -> Int {
  match name {
    "snprintf" => 3
    "sprintf" => 2
    "printf" => 1
    "fprintf" => 2
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
    "snprintf" =>
      match index {
        0 => Some(Pointer(SChar))
        1 => Some(ULong)
        2 => Some(Pointer(SChar))
        _ => None
      }
    "sprintf" =>
      match index {
        0 => Some(Pointer(SChar))
        1 => Some(Pointer(SChar))
        _ => None
      }
    "vsprintf" =>
      match index {
        0 => Some(Pointer(SChar))
        1 => Some(Pointer(SChar))
        2 => Some(Pointer(SChar))
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
    "vsnprintf" =>
      match index {
        0 => Some(Pointer(SChar))
        1 => Some(ULong)
        2 => Some(Pointer(SChar))
        3 => Some(Pointer(SChar))
        _ => None
      }
    "vfprintf" =>
      match index {
        0 => Some(Pointer(Void))
        1 => Some(Pointer(SChar))
        2 => Some(Pointer(SChar))
        _ => None
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
  if mir_body_codegen_builtin_lib_call_supported(name, args, ret, int_arg_limit) {
    return true
  }
  if !mir_body_codegen_abi_scalar_type(ret) &&
    !mir_body_codegen_register_aggregate_return_type(ret, mir) &&
    !mir_body_codegen_x64_memory_aggregate_return_type(ret, mir) {
    return false
  }
  if !mir.funcs.contains(name) {
    if mir.globals.contains(name) || !mir_body_codegen_abi_scalar_type(ret) {
      return false
    }
    let params : Array[@ctype.Type] = []
    for arg in args {
      if !mir_body_codegen_abi_scalar_type(arg.ty()) {
        return false
      }
      params.push(mir_body_default_argument_promoted_type(arg.ty()))
    }
    if mir.target is LinuxAmd64 {
      return mir_body_codegen_x64_args_with_stack_supported(params)
    }
    return mir_body_codegen_darwin_args_with_stack_supported(params, mir)
  }
  let sig = mir.funcs[name]
  if !mir_body_codegen_abi_scalar_type(sig.ret) &&
    !mir_body_codegen_register_aggregate_return_type(sig.ret, mir) &&
    !mir_body_codegen_x64_memory_aggregate_return_type(sig.ret, mir) {
    return false
  }
  if sig.variadic {
    if sig.params.length() > args.length() {
      return false
    }
    let call_params : Array[@ctype.Type] = []
    for i in 0..<args.length() {
      let ty = if i < sig.params.length() {
        sig.params[i]
      } else {
        mir_body_default_argument_promoted_type(args[i].ty())
      }
      call_params.push(ty)
    }
    if mir.target is DarwinArm64 {
      return mir_body_codegen_darwin_variadic_args_supported(
        call_params,
        sig.params.length(),
        int_arg_limit,
        mir,
      )
    }
    if mir.target is LinuxAmd64 {
      return mir_body_codegen_x64_variadic_args_supported(
        call_params,
        sig.params.length(),
        int_arg_limit,
        mir,
      )
    }
    return mir_body_codegen_variadic_args_supported(
      call_params,
      sig.params.length(),
      int_arg_limit,
    )
  }
  if sig.params.length() != args.length() {
    if sig.params.length() != 0 {
      return false
    }
  }
  let call_params = if sig.params.length() == 0 && args.length() > 0 {
    mir_body_default_argument_promoted_types(args)
  } else {
    sig.params
  }
  if mir.target is LinuxAmd64 {
    mir_body_codegen_x64_args_with_stack_supported(call_params)
  } else {
    mir_body_codegen_darwin_args_with_stack_supported(call_params, mir)
  }
}

///|
fn mir_body_codegen_indirect_call_supported(
  callee_ty : @ctype.Type,
  args : Array[@mir.MirValue],
  ret : @ctype.Type,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  let ret_supported = mir_body_codegen_abi_scalar_type(ret) ||
    mir_body_codegen_register_aggregate_return_type(ret, mir) ||
    mir_body_codegen_x64_memory_aggregate_return_type(ret, mir)
  if !ret_supported {
    return false
  }
  match mir_indirect_callable_type(callee_ty) {
    Some(FuncPtr(sig_ret, params, variadic)) => {
      let sig_ret_supported = mir_body_codegen_abi_scalar_type(sig_ret) ||
        mir_body_codegen_register_aggregate_return_type(sig_ret, mir) ||
        mir_body_codegen_x64_memory_aggregate_return_type(sig_ret, mir)
      if !sig_ret_supported {
        return false
      }
      if variadic {
        if params.length() > args.length() {
          return false
        }
        let call_params : Array[@ctype.Type] = []
        for i in 0..<args.length() {
          let ty = if i < params.length() {
            params[i]
          } else {
            mir_body_default_argument_promoted_type(args[i].ty())
          }
          call_params.push(ty)
        }
        if mir.target is DarwinArm64 {
          return mir_body_codegen_darwin_variadic_args_supported(
            call_params,
            params.length(),
            int_arg_limit,
            mir,
          )
        }
        if mir.target is LinuxAmd64 {
          return mir_body_codegen_x64_variadic_args_supported(
            call_params,
            params.length(),
            int_arg_limit,
            mir,
          )
        }
        return mir_body_codegen_variadic_args_supported(
          call_params,
          params.length(),
          int_arg_limit,
        )
      }
      let call_params : Array[@ctype.Type] = []
      if params.length() == args.length() {
        for param in params {
          call_params.push(param)
        }
      } else if params.length() == 0 {
        for arg in args {
          call_params.push(mir_body_default_argument_promoted_type(arg.ty()))
        }
      } else {
        return false
      }
      if mir.target is LinuxAmd64 {
        mir_body_codegen_x64_args_with_stack_supported(call_params)
      } else {
        mir_body_codegen_darwin_args_with_stack_supported(call_params, mir)
      }
    }
    _ => false
  }
}

///|
fn mir_indirect_callable_type(callee_ty : @ctype.Type) -> @ctype.Type? {
  match peel_aligned_type(callee_ty) {
    FuncPtr(sig_ret, params, variadic) =>
      Some(FuncPtr(sig_ret, params, variadic))
    Pointer(FuncPtr(sig_ret, params, variadic)) =>
      Some(FuncPtr(sig_ret, params, variadic))
    _ => None
  }
}

///|
fn mir_indirect_call_variadic(callee_ty : @ctype.Type) -> Bool {
  match mir_indirect_callable_type(callee_ty) {
    Some(FuncPtr(_, _, variadic)) => variadic
    _ => false
  }
}

///|
fn mir_body_default_argument_promoted_type(ty : @ctype.Type) -> @ctype.Type {
  match peel_aligned_type(ty) {
    Float => Double
    _ => if ty.is_integer() { ty.integer_promote() } else { ty }
  }
}

///|
fn mir_body_default_argument_promoted_types(
  args : Array[@mir.MirValue],
) -> Array[@ctype.Type] {
  let params : Array[@ctype.Type] = []
  for arg in args {
    params.push(mir_body_default_argument_promoted_type(arg.ty()))
  }
  params
}

///|
fn mir_indirect_call_named_arg_count(callee_ty : @ctype.Type) -> Int {
  match mir_indirect_callable_type(callee_ty) {
    Some(FuncPtr(_, params, _)) => params.length()
    _ => 0
  }
}

///|
fn mir_indirect_call_arg_type(
  callee_ty : @ctype.Type,
  index : Int,
  actual : @ctype.Type,
) -> @ctype.Type {
  match mir_indirect_callable_type(callee_ty) {
    Some(FuncPtr(_, params, variadic)) =>
      if index >= 0 && index < params.length() {
        params[index]
      } else if variadic {
        mir_body_default_argument_promoted_type(actual)
      } else if params.length() == 0 {
        mir_body_default_argument_promoted_type(actual)
      } else {
        actual
      }
    _ => actual
  }
}

///|
fn mir_body_codegen_aggregate_return_value_supported(
  value : @mir.MirValue,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  if !mir_body_codegen_register_aggregate_return_type(value.ty(), mir) {
    return false
  }
  match value {
    MirLocal(binding) => mir_body_codegen_local_type(binding.ty)
    MirAggregateArg(addr, _) =>
      mir_body_codegen_value_supported(addr, int_arg_limit, mir)
    MirLoad(ptr, _) => mir_body_codegen_value_supported(ptr, int_arg_limit, mir)
    MirCall(_, _, _) | MirIndirectCall(_, _, _) =>
      mir_body_codegen_register_aggregate_call_value_supported(
        value, int_arg_limit, mir,
      )
    _ => false
  }
}

///|
fn mir_body_codegen_memory_aggregate_return_value_supported(
  value : @mir.MirValue,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  if !mir_body_codegen_x64_memory_aggregate_return_type(value.ty(), mir) {
    return false
  }
  match value {
    MirLocal(binding) => mir_body_codegen_local_type(binding.ty)
    MirAggregateArg(addr, _) =>
      mir_body_codegen_value_supported(addr, int_arg_limit, mir)
    MirLoad(ptr, _) => mir_body_codegen_value_supported(ptr, int_arg_limit, mir)
    MirCall(_, _, _) | MirIndirectCall(_, _, _) =>
      mir_body_codegen_memory_aggregate_call_value_supported(
        value, int_arg_limit, mir,
      )
    _ => false
  }
}

///|
fn mir_body_codegen_return_value_supported(
  value : @mir.MirValue,
  ret : @ctype.Type,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  if mir_body_codegen_abi_scalar_type(ret) {
    return mir_body_codegen_value_supported(value, int_arg_limit, mir)
  }
  if mir_body_codegen_register_aggregate_return_type(ret, mir) {
    return mir_body_codegen_aggregate_return_value_supported(
      value, int_arg_limit, mir,
    )
  }
  if mir_body_codegen_x64_memory_aggregate_return_type(ret, mir) {
    return mir_body_codegen_memory_aggregate_return_value_supported(
      value, int_arg_limit, mir,
    )
  }
  false
}

///|
fn mir_body_codegen_stmt_supported(
  stmt : @mir.MirStmt,
  ret : @ctype.Type,
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
          mir_body_codegen_return_value_supported(
            value, ret, int_arg_limit, mir,
          )
        None => true
      }
    MirIf(cond, then_, else_) =>
      mir_body_codegen_value_supported(cond, int_arg_limit, mir) &&
      mir_body_codegen_stmts_supported(then_, ret, int_arg_limit, mir) &&
      mir_body_codegen_stmts_supported(else_, ret, int_arg_limit, mir)
    MirWhile(cond, body) =>
      mir_body_codegen_value_supported(cond, int_arg_limit, mir) &&
      mir_body_codegen_stmts_supported(body, ret, int_arg_limit, mir)
    MirFor(init, cond, inc, body) => {
      let inc_supported = match inc {
        Some(value) =>
          mir_body_codegen_value_supported(value, int_arg_limit, mir)
        None => true
      }
      mir_body_codegen_stmts_supported(init, ret, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(cond, int_arg_limit, mir) &&
      inc_supported &&
      mir_body_codegen_stmts_supported(body, ret, int_arg_limit, mir)
    }
    MirDoWhile(cond, body) =>
      mir_body_codegen_value_supported(cond, int_arg_limit, mir) &&
      mir_body_codegen_stmts_supported(body, ret, int_arg_limit, mir)
    MirSwitch(control, _, body) =>
      mir_body_codegen_value_supported(control, int_arg_limit, mir) &&
      mir_body_codegen_stmts_supported(body, ret, int_arg_limit, mir)
    MirLabel(_) => true
    MirGoto(_) => true
    MirComputedGoto(value) =>
      mir_body_codegen_value_supported(value, int_arg_limit, mir)
    MirBreak => true
    MirContinue => true
    MirBlock(stmts) =>
      mir_body_codegen_stmts_supported(stmts, ret, int_arg_limit, mir)
  }
}

///|
fn mir_body_codegen_stmts_supported(
  stmts : Array[@mir.MirStmt],
  ret : @ctype.Type,
  int_arg_limit : Int,
  mir : @mir.MirModule,
) -> Bool {
  for stmt in stmts {
    if !mir_body_codegen_stmt_supported(stmt, ret, int_arg_limit, mir) {
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
  if mir.target is LinuxAmd64 &&
    mir_body_codegen_x64_unsupported_long_double_body(body) {
    return false
  }
  if !mir_body_codegen_abi_scalar_type(body.ret) &&
    !mir_body_codegen_register_aggregate_return_type(body.ret, mir) &&
    !mir_body_codegen_x64_memory_aggregate_return_type(body.ret, mir) {
    return false
  }
  let param_types : Array[@ctype.Type] = []
  for param in body.params {
    param_types.push(param.ty)
  }
  match mir.target {
    LinuxAmd64 =>
      if !mir_body_codegen_x64_args_with_stack_supported(param_types) {
        return false
      }
    DarwinArm64 =>
      if !mir_body_codegen_darwin_args_with_stack_supported(param_types, mir) {
        return false
      }
  }
  mir_body_codegen_stmts_supported(body.body, body.ret, int_arg_limit, mir)
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
fn mir_body_pointer_compare_binary(
  op : String,
  lhs : @ctype.Type,
  rhs : @ctype.Type,
) -> Bool {
  (
    op == "==" ||
    op == "!=" ||
    op == "<" ||
    op == "<=" ||
    op == ">" ||
    op == ">="
  ) &&
  (
    pointer_or_array_element_type(lhs) is Some(_) ||
    pointer_or_array_element_type(rhs) is Some(_)
  )
}

///|
fn mir_body_unsigned_compare_binary(
  op : String,
  lhs : @ctype.Type,
  rhs : @ctype.Type,
) -> Bool {
  mir_body_pointer_compare_binary(op, lhs, rhs) ||
  mir_body_unsigned_binary(op, lhs, rhs)
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
  let offsets : Map[Int, Int] = Map([])
  for binding in body.locals {
    if mir_body_codegen_local_type(binding.ty) {
      offsets[binding.id] = self.alloc_local(
        mir_body_local_name(binding),
        binding.ty,
      )
    }
  }
  for stmt in body.body {
    self.collect_mir_sret_scratch_stmt(stmt)
  }
  if self.sret_scratch_size > 0 {
    self.sret_scratch_offset = self.alloc_local(
      "__kimicc_mir_sret_scratch",
      Aligned(Array(UChar, self.sret_scratch_size), self.sret_scratch_align),
    )
  }
  offsets
}

///|
fn Codegen::collect_mir_sret_scratch_value(
  self : Codegen,
  value : @mir.MirValue,
) -> Unit {
  match value {
    MirConst(_, _)
    | MirLocal(_)
    | MirAddrLocal(_)
    | MirAddrGlobal(_, _)
    | MirFuncAddr(_, _)
    | MirLabelAddr(_)
    | MirStringAddr(_) => ()
    MirElemAddr(base, index, _) => {
      self.collect_mir_sret_scratch_value(base)
      self.collect_mir_sret_scratch_value(index)
    }
    MirOffsetAddr(base, _, _) | MirLoad(base, _) | MirUnary(_, base, _) =>
      self.collect_mir_sret_scratch_value(base)
    MirBinary(_, lhs, rhs, _) | MirStore(lhs, rhs, _) => {
      self.collect_mir_sret_scratch_value(lhs)
      self.collect_mir_sret_scratch_value(rhs)
    }
    MirOverflow(_, left, right, result_ptr) => {
      self.collect_mir_sret_scratch_value(left)
      self.collect_mir_sret_scratch_value(right)
      self.collect_mir_sret_scratch_value(result_ptr)
    }
    MirVaStart(target) | MirVaEnd(target) =>
      self.collect_mir_sret_scratch_value(target)
    MirVaCopy(target, source) => {
      self.collect_mir_sret_scratch_value(target)
      self.collect_mir_sret_scratch_value(source)
    }
    MirBzero(dst, size) => {
      self.collect_mir_sret_scratch_value(dst)
      self.collect_mir_sret_scratch_value(size)
    }
    MirAtomicLoad(ptr, order, _) => {
      self.collect_mir_sret_scratch_value(ptr)
      self.collect_mir_sret_scratch_value(order)
    }
    MirAtomicStore(ptr, stored, order) => {
      self.collect_mir_sret_scratch_value(ptr)
      self.collect_mir_sret_scratch_value(stored)
      self.collect_mir_sret_scratch_value(order)
    }
    MirAtomicUpdate(_, _, ptr, stored, extras, _) => {
      self.collect_mir_sret_scratch_value(ptr)
      self.collect_mir_sret_scratch_value(stored)
      for extra in extras {
        self.collect_mir_sret_scratch_value(extra)
      }
    }
    MirAtomicExchange(ptr, stored, extras, _) => {
      self.collect_mir_sret_scratch_value(ptr)
      self.collect_mir_sret_scratch_value(stored)
      for extra in extras {
        self.collect_mir_sret_scratch_value(extra)
      }
    }
    MirAtomicCompareExchange(ptr, expected, desired, extras) => {
      self.collect_mir_sret_scratch_value(ptr)
      self.collect_mir_sret_scratch_value(expected)
      self.collect_mir_sret_scratch_value(desired)
      for extra in extras {
        self.collect_mir_sret_scratch_value(extra)
      }
    }
    MirLibCall(_, args, _) =>
      for arg in args {
        self.collect_mir_sret_scratch_value(arg)
      }
    MirCast(_, inner)
    | MirAggregateArg(inner, _)
    | MirVaArg(inner, _)
    | MirVaArgAddr(inner, _) => self.collect_mir_sret_scratch_value(inner)
    MirCall(_, args, _) => {
      if self.is_memory_aggregate(value.ty()) {
        let size = self.type_size(value.ty())
        if size > self.sret_scratch_size {
          self.sret_scratch_size = size
        }
        let align = self.type_align(value.ty())
        if align > self.sret_scratch_align {
          self.sret_scratch_align = align
        }
      }
      for arg in args {
        self.collect_mir_sret_scratch_value(arg)
      }
    }
    MirIndirectCall(callee, args, _) => {
      if self.is_memory_aggregate(value.ty()) {
        let size = self.type_size(value.ty())
        if size > self.sret_scratch_size {
          self.sret_scratch_size = size
        }
        let align = self.type_align(value.ty())
        if align > self.sret_scratch_align {
          self.sret_scratch_align = align
        }
      }
      self.collect_mir_sret_scratch_value(callee)
      for arg in args {
        self.collect_mir_sret_scratch_value(arg)
      }
    }
    MirAssignLocal(_, rhs) | MirPostUpdateLocal(_, _, rhs, _) =>
      self.collect_mir_sret_scratch_value(rhs)
    MirPreUpdateMemory(ptr, _, rhs, _) | MirPostUpdateMemory(ptr, _, rhs, _) => {
      self.collect_mir_sret_scratch_value(ptr)
      self.collect_mir_sret_scratch_value(rhs)
    }
    MirTernary(cond, then_, else_, _) => {
      self.collect_mir_sret_scratch_value(cond)
      self.collect_mir_sret_scratch_value(then_)
      self.collect_mir_sret_scratch_value(else_)
    }
  }
}

///|
fn Codegen::collect_mir_sret_scratch_stmt(
  self : Codegen,
  stmt : @mir.MirStmt,
) -> Unit {
  match stmt {
    MirDeclare(_, init) =>
      match init {
        Some(value) => self.collect_mir_sret_scratch_value(value)
        None => ()
      }
    MirExprStmt(value) => self.collect_mir_sret_scratch_value(value)
    MirReturn(value) =>
      match value {
        Some(value) => self.collect_mir_sret_scratch_value(value)
        None => ()
      }
    MirIf(cond, then_, else_) => {
      self.collect_mir_sret_scratch_value(cond)
      for nested in then_ {
        self.collect_mir_sret_scratch_stmt(nested)
      }
      for nested in else_ {
        self.collect_mir_sret_scratch_stmt(nested)
      }
    }
    MirWhile(cond, body) | MirDoWhile(cond, body) => {
      self.collect_mir_sret_scratch_value(cond)
      for nested in body {
        self.collect_mir_sret_scratch_stmt(nested)
      }
    }
    MirFor(init, cond, inc, body) => {
      for nested in init {
        self.collect_mir_sret_scratch_stmt(nested)
      }
      self.collect_mir_sret_scratch_value(cond)
      match inc {
        Some(value) => self.collect_mir_sret_scratch_value(value)
        None => ()
      }
      for nested in body {
        self.collect_mir_sret_scratch_stmt(nested)
      }
    }
    MirSwitch(control, _, body) => {
      self.collect_mir_sret_scratch_value(control)
      for nested in body {
        self.collect_mir_sret_scratch_stmt(nested)
      }
    }
    MirBlock(stmts) =>
      for nested in stmts {
        self.collect_mir_sret_scratch_stmt(nested)
      }
    MirComputedGoto(value) => self.collect_mir_sret_scratch_value(value)
    MirLabel(_) | MirGoto(_) | MirBreak | MirContinue => ()
  }
}

///|
fn Codegen::emit_mir_atomic_load(
  self : Codegen,
  ptr : @mir.MirValue,
  order : @mir.MirValue,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  let elem_ty = mir_body_codegen_atomic_target_type(ptr.ty())
  self.gen_mir_value(ptr, offsets, frame_size)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_mir_value(order, offsets, frame_size)
  self.emit("\tldr\tx9, [sp], #16")
  self.emit("\tmov\tx0, x9")
  match peel_aligned_type(elem_ty) {
    Bool | SChar | UChar => self.emit("\tldarb\tw9, [x0]")
    SShort | UShort => self.emit("\tldarh\tw9, [x0]")
    SInt | UInt | Float => self.emit("\tldar\tw9, [x0]")
    _ => self.emit("\tldar\tx9, [x0]")
  }
  self.emit_scalar_conversion_to(elem_ty)
}

///|
fn Codegen::emit_mir_atomic_store(
  self : Codegen,
  ptr : @mir.MirValue,
  value : @mir.MirValue,
  order : @mir.MirValue,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  let elem_ty = mir_body_codegen_atomic_target_type(ptr.ty())
  self.gen_mir_value(ptr, offsets, frame_size)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_mir_value(order, offsets, frame_size)
  self.gen_mir_value(value, offsets, frame_size)
  self.emit_numeric_conversion(value.ty(), elem_ty)
  self.emit_scalar_conversion_to(elem_ty)
  self.emit("\tldr\tx0, [sp], #16")
  match peel_aligned_type(elem_ty) {
    Bool | SChar | UChar => self.emit("\tstlrb\tw9, [x0]")
    SShort | UShort => self.emit("\tstlrh\tw9, [x0]")
    SInt | UInt | Float => self.emit("\tstlr\tw9, [x0]")
    _ => self.emit("\tstlr\tx9, [x0]")
  }
  self.emit("\tmov\tx9, #0")
}

///|
fn Codegen::emit_mir_atomic_update_op(
  self : Codegen,
  op : String,
  dst : String,
  old : String,
  value : String,
) -> Unit {
  match op {
    "+" => self.emit("\tadd\t" + dst + ", " + old + ", " + value)
    "-" => self.emit("\tsub\t" + dst + ", " + old + ", " + value)
    "&" => self.emit("\tand\t" + dst + ", " + old + ", " + value)
    "|" => self.emit("\torr\t" + dst + ", " + old + ", " + value)
    "^" => self.emit("\teor\t" + dst + ", " + old + ", " + value)
    "~&" => {
      self.emit("\tand\t" + dst + ", " + old + ", " + value)
      self.emit("\tmvn\t" + dst + ", " + dst)
    }
    "max" => {
      let keep_label = self.new_label()
      self.emit("\tmov\t" + dst + ", " + old)
      self.emit("\tcmp\t" + old + ", " + value)
      self.emit("\tb.ge\t" + keep_label)
      self.emit("\tmov\t" + dst + ", " + value)
      self.emit(keep_label + ":")
    }
    "min" => {
      let keep_label = self.new_label()
      self.emit("\tmov\t" + dst + ", " + old)
      self.emit("\tcmp\t" + old + ", " + value)
      self.emit("\tb.le\t" + keep_label)
      self.emit("\tmov\t" + dst + ", " + value)
      self.emit(keep_label + ":")
    }
    "umax" => {
      let keep_label = self.new_label()
      self.emit("\tmov\t" + dst + ", " + old)
      self.emit("\tcmp\t" + old + ", " + value)
      self.emit("\tb.hs\t" + keep_label)
      self.emit("\tmov\t" + dst + ", " + value)
      self.emit(keep_label + ":")
    }
    "umin" => {
      let keep_label = self.new_label()
      self.emit("\tmov\t" + dst + ", " + old)
      self.emit("\tcmp\t" + old + ", " + value)
      self.emit("\tb.ls\t" + keep_label)
      self.emit("\tmov\t" + dst + ", " + value)
      self.emit(keep_label + ":")
    }
    _ => self.emit("\tmov\t" + dst + ", " + old)
  }
}

///|
fn Codegen::emit_mir_atomic_update_loop(
  self : Codegen,
  op : String,
  elem_ty : @ctype.Type,
  return_new : Bool,
) -> Unit {
  let loop_label = self.new_label()
  let byte_width = self.type_size(elem_ty)
  self.emit(loop_label + ":")
  if byte_width == 1 {
    self.emit("\tldaxrb\tw9, [x0]")
    self.emit_mir_atomic_update_op(op, "w11", "w9", "w10")
    self.emit("\tstlxrb\tw12, w11, [x0]")
  } else if byte_width == 2 {
    self.emit("\tldaxrh\tw9, [x0]")
    self.emit_mir_atomic_update_op(op, "w11", "w9", "w10")
    self.emit("\tstlxrh\tw12, w11, [x0]")
  } else if byte_width == 4 {
    self.emit("\tldaxr\tw9, [x0]")
    self.emit_mir_atomic_update_op(op, "w11", "w9", "w10")
    self.emit("\tstlxr\tw12, w11, [x0]")
  } else {
    self.emit("\tldaxr\tx9, [x0]")
    self.emit_mir_atomic_update_op(op, "x11", "x9", "x10")
    self.emit("\tstlxr\tw12, x11, [x0]")
  }
  self.emit("\tcbnz\tw12, " + loop_label)
  if return_new {
    if byte_width == 8 {
      self.emit("\tmov\tx9, x11")
    } else {
      self.emit("\tmov\tw9, w11")
    }
  }
  self.emit_scalar_conversion_to(elem_ty)
}

///|
fn Codegen::emit_mir_ignored_values(
  self : Codegen,
  values : Array[@mir.MirValue],
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  for value in values {
    self.gen_mir_value(value, offsets, frame_size)
  }
}

///|
fn Codegen::emit_mir_atomic_update(
  self : Codegen,
  ptr : @mir.MirValue,
  value : @mir.MirValue,
  extras : Array[@mir.MirValue],
  offsets : Map[Int, Int],
  frame_size : Int,
  op : String,
  return_new : Bool,
) -> Unit {
  self.emit_mir_ignored_values(extras, offsets, frame_size)
  let elem_ty = mir_body_codegen_atomic_target_type(ptr.ty())
  self.gen_mir_value(ptr, offsets, frame_size)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_mir_value(value, offsets, frame_size)
  self.emit_numeric_conversion(value.ty(), elem_ty)
  self.emit_scalar_conversion_to(elem_ty)
  if self.type_size(elem_ty) == 8 {
    self.emit("\tmov\tx10, x9")
  } else {
    self.emit("\tmov\tw10, w9")
  }
  self.emit("\tldr\tx0, [sp], #16")
  self.emit_mir_atomic_update_loop(op, elem_ty, return_new)
}

///|
fn Codegen::emit_mir_atomic_exchange(
  self : Codegen,
  ptr : @mir.MirValue,
  value : @mir.MirValue,
  extras : Array[@mir.MirValue],
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  self.emit_mir_ignored_values(extras, offsets, frame_size)
  let elem_ty = mir_body_codegen_atomic_target_type(ptr.ty())
  let byte_width = self.type_size(elem_ty)
  self.gen_mir_value(ptr, offsets, frame_size)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_mir_value(value, offsets, frame_size)
  self.emit_numeric_conversion(value.ty(), elem_ty)
  self.emit_scalar_conversion_to(elem_ty)
  if byte_width == 8 {
    self.emit("\tmov\tx10, x9")
  } else {
    self.emit("\tmov\tw10, w9")
  }
  self.emit("\tldr\tx0, [sp], #16")
  let loop_label = self.new_label()
  self.emit(loop_label + ":")
  if byte_width == 1 {
    self.emit("\tldaxrb\tw9, [x0]")
    self.emit("\tstlxrb\tw12, w10, [x0]")
  } else if byte_width == 2 {
    self.emit("\tldaxrh\tw9, [x0]")
    self.emit("\tstlxrh\tw12, w10, [x0]")
  } else if byte_width == 4 {
    self.emit("\tldaxr\tw9, [x0]")
    self.emit("\tstlxr\tw12, w10, [x0]")
  } else {
    self.emit("\tldaxr\tx9, [x0]")
    self.emit("\tstlxr\tw12, x10, [x0]")
  }
  self.emit("\tcbnz\tw12, " + loop_label)
  self.emit_scalar_conversion_to(elem_ty)
}

///|
fn Codegen::emit_mir_atomic_compare_exchange(
  self : Codegen,
  ptr : @mir.MirValue,
  expected : @mir.MirValue,
  desired : @mir.MirValue,
  extras : Array[@mir.MirValue],
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  self.emit_mir_ignored_values(extras, offsets, frame_size)
  let elem_ty = mir_body_codegen_atomic_target_type(ptr.ty())
  let byte_width = self.type_size(elem_ty)
  self.gen_mir_value(ptr, offsets, frame_size)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_mir_value(expected, offsets, frame_size)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_mir_value(desired, offsets, frame_size)
  self.emit_numeric_conversion(desired.ty(), elem_ty)
  self.emit_scalar_conversion_to(elem_ty)
  if byte_width == 8 {
    self.emit("\tmov\tx10, x9")
  } else {
    self.emit("\tmov\tw10, w9")
  }
  self.emit("\tldr\tx1, [sp], #16")
  self.emit("\tldr\tx0, [sp], #16")
  self.emit_load_typed("x13", "x1", elem_ty)
  let loop_label = self.new_label()
  let fail_label = self.new_label()
  let done_label = self.new_label()
  self.emit(loop_label + ":")
  if byte_width == 1 {
    self.emit("\tldaxrb\tw9, [x0]")
    self.emit("\tcmp\tw9, w13")
    self.emit("\tb.ne\t" + fail_label)
    self.emit("\tstlxrb\tw12, w10, [x0]")
  } else if byte_width == 2 {
    self.emit("\tldaxrh\tw9, [x0]")
    self.emit("\tcmp\tw9, w13")
    self.emit("\tb.ne\t" + fail_label)
    self.emit("\tstlxrh\tw12, w10, [x0]")
  } else if byte_width == 4 {
    self.emit("\tldaxr\tw9, [x0]")
    self.emit("\tcmp\tw9, w13")
    self.emit("\tb.ne\t" + fail_label)
    self.emit("\tstlxr\tw12, w10, [x0]")
  } else {
    self.emit("\tldaxr\tx9, [x0]")
    self.emit("\tcmp\tx9, x13")
    self.emit("\tb.ne\t" + fail_label)
    self.emit("\tstlxr\tw12, x10, [x0]")
  }
  self.emit("\tcbnz\tw12, " + loop_label)
  self.emit("\tmov\tx9, #1")
  self.emit("\tb\t" + done_label)
  self.emit(fail_label + ":")
  self.emit_store_typed("x9", "x1", elem_ty)
  self.emit("\tmov\tx9, #0")
  self.emit(done_label + ":")
}

///|
fn Codegen::mir_pointer_update_scale(self : Codegen, ty : @ctype.Type) -> Int {
  match pointer_or_array_element_type(ty) {
    Some(elem_ty) => self.mir_pointer_element_scale(elem_ty)
    None => 1
  }
}

///|
fn Codegen::mir_pointer_element_scale(
  self : Codegen,
  elem_ty : @ctype.Type,
) -> Int {
  match elem_ty {
    Void => 1
    _ => self.type_size(elem_ty)
  }
}

///|
fn Codegen::emit_mir_scale_update_rhs_for_pointer(
  self : Codegen,
  ty : @ctype.Type,
) -> Unit {
  let scale = self.mir_pointer_update_scale(ty)
  if scale != 1 {
    self.emit("\tmov\tx11, #" + scale.to_string())
    self.emit("\tmul\tx9, x9, x11")
  }
}

///|
fn Codegen::emit_mir_overflow_arithmetic_builtin(
  self : Codegen,
  left : @mir.MirValue,
  right : @mir.MirValue,
  result_ptr : @mir.MirValue,
  offsets : Map[Int, Int],
  frame_size : Int,
  op : String,
) -> Unit {
  let result_ty = match mir_body_codegen_overflow_result_type(result_ptr) {
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
  self.gen_mir_value(result_ptr, offsets, frame_size)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_mir_value(left, offsets, frame_size)
  self.emit_numeric_conversion(left.ty(), result_ty)
  self.emit_scalar_conversion_to(result_ty)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_mir_value(right, offsets, frame_size)
  self.emit_numeric_conversion(right.ty(), result_ty)
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
fn mir_body_codegen_va_slot_advance(size : Int) -> Int {
  if size < 8 {
    8
  } else {
    (size + 7) / 8 * 8
  }
}

///|
fn Codegen::emit_mir_bzero(
  self : Codegen,
  dst : @mir.MirValue,
  size : @mir.MirValue,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  self.gen_mir_value(dst, offsets, frame_size)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_mir_value(size, offsets, frame_size)
  self.emit_scalar_conversion_to(size.ty())
  self.emit("\tmov\tx1, x9")
  self.emit("\tldr\tx0, [sp], #16")
  self.emit("\tbl\t_bzero")
  self.emit("\tmov\tx9, #0")
}

///|
fn Codegen::emit_mir_va_start(
  self : Codegen,
  target : @mir.MirValue,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  match target {
    MirLocal(binding) => {
      self.emit("\tadd\tx9, x29, #16")
      self.emit_store_local("x9", offsets[binding.id], frame_size)
    }
    _ => ()
  }
  self.emit("\tmov\tx9, #0")
}

///|
fn Codegen::emit_mir_va_copy(
  self : Codegen,
  target : @mir.MirValue,
  source : @mir.MirValue,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  match target {
    MirLocal(binding) => {
      self.gen_mir_value(source, offsets, frame_size)
      self.emit_store_local("x9", offsets[binding.id], frame_size)
    }
    _ => ()
  }
  self.emit("\tmov\tx9, #0")
}

///|
fn Codegen::emit_mir_va_arg(
  self : Codegen,
  ap : @mir.MirValue,
  ty : @ctype.Type,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  let binding = match ap {
    MirLocal(binding) => binding
    _ => abort("Darwin ARM64 MIR va_arg only supports local va_list values")
  }
  self.gen_mir_value(ap, offsets, frame_size)
  self.emit("\tmov\tx11, x9")
  self.emit_load_typed("x9", "x11", ty)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.emit(
    "\tadd\tx11, x11, #" +
    mir_body_codegen_va_slot_advance(self.type_size(ty)).to_string(),
  )
  self.emit("\tmov\tx9, x11")
  self.emit_store_local("x9", offsets[binding.id], frame_size)
  self.emit("\tldr\tx9, [sp], #16")
  self.emit_scalar_conversion_to(ty)
}

///|
fn Codegen::emit_mir_va_arg_addr(
  self : Codegen,
  ap : @mir.MirValue,
  ty : @ctype.Type,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  let binding = match ap {
    MirLocal(binding) => binding
    _ =>
      abort(
        "Darwin ARM64 MIR aggregate va_arg only supports local va_list values",
      )
  }
  self.gen_mir_value(ap, offsets, frame_size)
  self.emit("\tmov\tx11, x9")
  if self.type_size(ty) > 16 {
    self.emit("\tadd\tx9, x11, #8")
    self.emit_store_local("x9", offsets[binding.id], frame_size)
    self.emit("\tldr\tx9, [x11]")
  } else {
    self.emit_add_offset_to_x9(
      mir_body_codegen_va_slot_advance(self.type_size(ty)),
    )
    self.emit_store_local("x9", offsets[binding.id], frame_size)
    self.emit("\tmov\tx9, x11")
  }
}

///|
fn mir_body_codegen_arm_addr_ref(base : String, offset : Int) -> String {
  if offset == 0 {
    "[" + base + "]"
  } else {
    "[" + base + ", #" + offset.to_string() + "]"
  }
}

///|
fn Codegen::is_register_aggregate(self : Codegen, ty : @ctype.Type) -> Bool {
  match peel_aligned_type(ty) {
    Struct(_) | Union(_) =>
      self.type_size(ty) <= 16 && !self.is_hfa_aggregate(ty)
    _ => false
  }
}

///|
fn Codegen::is_memory_aggregate(self : Codegen, ty : @ctype.Type) -> Bool {
  match peel_aligned_type(ty) {
    Struct(_) | Union(_) => self.type_size(ty) > 16
    _ => false
  }
}

///|
fn Codegen::darwin_hfa_parts(
  self : Codegen,
  ty : @ctype.Type,
) -> (@ctype.Type, Int)? {
  match peel_aligned_type(ty) {
    Float => Some((Float, 1))
    Double | LongDouble => Some((Double, 1))
    Array(elem, len) =>
      match self.darwin_hfa_parts(elem) {
        Some((base, count)) => {
          let total = count * len
          if total > 0 && total <= 4 {
            Some((base, total))
          } else {
            None
          }
        }
        None => None
      }
    Struct(name) | Union(name) => {
      let layout = match self.mir_aggregate_layout(name) {
        Some(layout) => layout
        None => return None
      }
      if layout.fields.length() == 0 {
        return None
      }
      let mut fp_ty : @ctype.Type? = None
      let mut total = 0
      for field in layout.fields {
        if field.bit_width is Some(_) {
          return None
        }
        let (field_base, field_count) = match self.darwin_hfa_parts(field.ty) {
          Some(parts) => parts
          None => return None
        }
        match fp_ty {
          Some(seen) => if seen != field_base { return None }
          None => fp_ty = Some(field_base)
        }
        if layout.is_union {
          if field_count > total {
            total = field_count
          }
        } else {
          total += field_count
        }
      }
      match fp_ty {
        Some(base) =>
          if total > 0 && total <= 4 {
            Some((base, total))
          } else {
            None
          }
        None => None
      }
    }
    Atomic(inner) | Aligned(inner, _) => self.darwin_hfa_parts(inner)
    _ => None
  }
}

///|
fn Codegen::is_hfa_aggregate(self : Codegen, ty : @ctype.Type) -> Bool {
  match peel_aligned_type(ty) {
    Struct(_) | Union(_) => self.darwin_hfa_parts(ty) is Some(_)
    _ => false
  }
}

///|
fn Codegen::darwin_hfa_member_offsets(
  self : Codegen,
  ty : @ctype.Type,
  base_offset : Int,
) -> (@ctype.Type, Array[Int])? {
  match peel_aligned_type(ty) {
    Float => {
      let offsets : Array[Int] = []
      offsets.push(base_offset)
      Some((Float, offsets))
    }
    Double | LongDouble => {
      let offsets : Array[Int] = []
      offsets.push(base_offset)
      Some((Double, offsets))
    }
    Array(elem, len) => {
      let (base, elem_offsets) = match
        self.darwin_hfa_member_offsets(elem, base_offset) {
        Some(parts) => parts
        None => return None
      }
      let offsets : Array[Int] = []
      let elem_size = self.type_size(elem)
      for i in 0..<len {
        for offset in elem_offsets {
          offsets.push(offset + i * elem_size)
        }
      }
      if offsets.length() > 0 && offsets.length() <= 4 {
        Some((base, offsets))
      } else {
        None
      }
    }
    Struct(name) | Union(name) => {
      let layout = match self.mir_aggregate_layout(name) {
        Some(layout) => layout
        None => return None
      }
      if layout.fields.length() == 0 {
        return None
      }
      let offsets : Array[Int] = []
      let mut union_offsets : Array[Int] = []
      let mut fp_ty : @ctype.Type? = None
      for field in layout.fields {
        if field.bit_width is Some(_) {
          return None
        }
        let field_offset = if layout.is_union {
          base_offset
        } else {
          base_offset + field.offset
        }
        let (field_base, field_offsets) = match
          self.darwin_hfa_member_offsets(field.ty, field_offset) {
          Some(parts) => parts
          None => return None
        }
        match fp_ty {
          Some(seen) => if seen != field_base { return None }
          None => fp_ty = Some(field_base)
        }
        if layout.is_union {
          if field_offsets.length() > union_offsets.length() {
            union_offsets = field_offsets
          }
        } else {
          for offset in field_offsets {
            offsets.push(offset)
          }
        }
      }
      let result_offsets = if layout.is_union { union_offsets } else { offsets }
      match fp_ty {
        Some(base) =>
          if result_offsets.length() > 0 && result_offsets.length() <= 4 {
            Some((base, result_offsets))
          } else {
            None
          }
        None => None
      }
    }
    Atomic(inner) | Aligned(inner, _) =>
      self.darwin_hfa_member_offsets(inner, base_offset)
    _ => None
  }
}

///|
fn Codegen::emit_load_hfa_aggregate_return_from_x9(
  self : Codegen,
  ty : @ctype.Type,
) -> Unit {
  let (base, offsets) = match self.darwin_hfa_member_offsets(ty, 0) {
    Some(parts) => parts
    None => abort("unsupported Darwin ARM64 HFA aggregate return load")
  }
  for i in 0..<offsets.length() {
    self.emit(
      "\tldr\t" +
      mir_body_codegen_arm_fp_reg(base, i) +
      ", " +
      mir_body_codegen_arm_addr_ref("x9", offsets[i]),
    )
  }
}

///|
fn Codegen::emit_store_hfa_aggregate_return_to_x9(
  self : Codegen,
  ty : @ctype.Type,
) -> Unit {
  let (base, offsets) = match self.darwin_hfa_member_offsets(ty, 0) {
    Some(parts) => parts
    None => abort("unsupported Darwin ARM64 HFA aggregate return store")
  }
  for i in 0..<offsets.length() {
    self.emit(
      "\tstr\t" +
      mir_body_codegen_arm_fp_reg(base, i) +
      ", " +
      mir_body_codegen_arm_addr_ref("x9", offsets[i]),
    )
  }
}

///|
fn Codegen::emit_save_darwin_aggregate_call_arg_raw(
  self : Codegen,
  arg : @mir.MirValue,
  ty : @ctype.Type,
  raw_size : Int,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  match arg {
    MirCall(_, _, _) | MirIndirectCall(_, _, _) => {
      self.gen_mir_value(arg, offsets, frame_size)
      self.emit("\tsub\tsp, sp, #" + raw_size.to_string())
      if self.is_hfa_aggregate(ty) {
        self.emit("\tmov\tx9, sp")
        self.emit_store_hfa_aggregate_return_to_x9(ty)
      } else if self.is_register_aggregate(ty) {
        self.emit("\tmov\tx9, sp")
        self.emit_store_register_aggregate_return_to_x9(ty)
      } else if self.is_memory_aggregate(ty) {
        self.emit("\tmov\tx11, x9")
        self.emit("\tmov\tx10, sp")
        self.emit_copy_memory_aggregate_from_x11_to_x10(ty)
      } else {
        abort("unsupported Darwin ARM64 MIR aggregate call argument")
      }
    }
    _ => {
      self.gen_mir_value(arg, offsets, frame_size)
      self.emit("\tsub\tsp, sp, #" + raw_size.to_string())
      self.emit("\tmov\tx11, x9")
      self.emit("\tmov\tx10, sp")
      self.emit_copy_memory_aggregate_from_x11_to_x10(ty)
    }
  }
}

///|
fn Codegen::emit_load_hfa_aggregate_arg_from_raw(
  self : Codegen,
  ty : @ctype.Type,
  raw_offset : Int,
  fp_start : Int,
) -> Unit {
  let (base, offsets) = match self.darwin_hfa_member_offsets(ty, 0) {
    Some(parts) => parts
    None => abort("unsupported Darwin ARM64 HFA aggregate argument load")
  }
  for i in 0..<offsets.length() {
    self.emit(
      "\tldr\t" +
      mir_body_codegen_arm_fp_reg(base, fp_start + i) +
      ", " +
      mir_body_codegen_arm_addr_ref("sp", raw_offset + offsets[i]),
    )
  }
}

///|
fn Codegen::emit_store_hfa_aggregate_param_from_regs(
  self : Codegen,
  ty : @ctype.Type,
  local_offset : Int,
  fp_start : Int,
  frame_size : Int,
) -> Unit {
  let (base, offsets) = match self.darwin_hfa_member_offsets(ty, 0) {
    Some(parts) => parts
    None => abort("unsupported Darwin ARM64 HFA aggregate parameter store")
  }
  self.emit_local_addr(local_offset, frame_size)
  for i in 0..<offsets.length() {
    self.emit(
      "\tstr\t" +
      mir_body_codegen_arm_fp_reg(base, fp_start + i) +
      ", " +
      mir_body_codegen_arm_addr_ref("x9", offsets[i]),
    )
  }
}

///|
fn Codegen::emit_store_register_aggregate_param_from_regs(
  self : Codegen,
  ty : @ctype.Type,
  local_offset : Int,
  int_start : Int,
  frame_size : Int,
) -> Unit {
  let size = self.type_size(ty)
  self.emit_local_addr(local_offset, frame_size)
  self.emit_store_reg_bytes_to_addr(
    "x" + int_start.to_string(),
    "x9",
    0,
    if size > 8 {
      8
    } else {
      size
    },
  )
  if size > 8 {
    self.emit_store_reg_bytes_to_addr(
      "x" + (int_start + 1).to_string(),
      "x9",
      8,
      size - 8,
    )
  }
}

///|
fn Codegen::emit_addr_with_offset_to_reg(
  self : Codegen,
  dst : String,
  base : String,
  offset : Int,
) -> Unit {
  if offset == 0 {
    self.emit("\tmov\t" + dst + ", " + base)
  } else if offset <= 4095 {
    self.emit("\tadd\t" + dst + ", " + base + ", #" + offset.to_string())
  } else {
    self.emit_load_int(dst, offset.to_int64())
    if base == "sp" {
      self.emit("\tmov\tx12, sp")
      self.emit("\tadd\t" + dst + ", x12, " + dst)
    } else {
      self.emit("\tadd\t" + dst + ", " + base + ", " + dst)
    }
  }
}

///|
fn Codegen::emit_copy_darwin_aggregate_arg_from_raw_to_stack(
  self : Codegen,
  ty : @ctype.Type,
  raw_offset : Int,
  stack_offset : Int,
) -> Unit {
  self.emit_addr_with_offset_to_reg("x11", "sp", raw_offset)
  self.emit_addr_with_offset_to_reg("x10", "sp", stack_offset)
  self.emit_copy_memory_aggregate_from_x11_to_x10(ty)
}

///|
fn Codegen::emit_save_darwin_variadic_aggregate_arg_raw(
  self : Codegen,
  arg : @mir.MirValue,
  ty : @ctype.Type,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> (Int, Int) {
  let size = self.type_size(ty)
  if size > 16 {
    let copy_size = (size + 15) / 16 * 16
    self.gen_mir_value(arg, offsets, frame_size)
    self.emit("\tsub\tsp, sp, #" + copy_size.to_string())
    self.emit("\tmov\tx11, x9")
    self.emit("\tmov\tx10, sp")
    self.emit_copy_memory_aggregate_from_x11_to_x10(ty)
    self.emit("\tmov\tx9, sp")
    self.emit("\tstr\tx9, [sp, #-16]!")
    (1, copy_size + 16)
  } else {
    let slots = if size > 8 { 2 } else { 1 }
    self.gen_mir_value(arg, offsets, frame_size)
    self.emit("\tsub\tsp, sp, #16")
    self.emit("\tmov\tx11, x9")
    self.emit("\tmov\tx10, sp")
    self.emit_copy_memory_aggregate_from_x11_to_x10(ty)
    (slots, 16)
  }
}

///|
fn Codegen::emit_pass_darwin_indirect_aggregate_arg_from_raw(
  self : Codegen,
  raw_offset : Int,
  int_arg_index : Int,
  stack_arg_index : Int,
) -> Unit {
  if int_arg_index >= 0 {
    self.emit_addr_with_offset_to_reg(
      "x" + int_arg_index.to_string(),
      "sp",
      raw_offset,
    )
  } else {
    self.emit_addr_with_offset_to_reg("x9", "sp", raw_offset)
    self.emit("\tstr\tx9, [sp, #" + (stack_arg_index * 8).to_string() + "]")
  }
}

///|
fn Codegen::emit_store_darwin_aggregate_param_from_stack(
  self : Codegen,
  ty : @ctype.Type,
  local_offset : Int,
  stack_offset : Int,
  frame_size : Int,
) -> Unit {
  self.emit_local_addr(local_offset, frame_size)
  self.emit("\tmov\tx10, x9")
  self.emit_addr_with_offset_to_reg("x11", "x29", 16 + stack_offset)
  self.emit_copy_memory_aggregate_from_x11_to_x10(ty)
}

///|
fn Codegen::emit_store_darwin_indirect_aggregate_param(
  self : Codegen,
  ty : @ctype.Type,
  local_offset : Int,
  src_reg : String,
  frame_size : Int,
) -> Unit {
  self.emit("\tmov\tx11, " + src_reg)
  self.emit_local_addr(local_offset, frame_size)
  self.emit("\tmov\tx10, x9")
  self.emit_copy_memory_aggregate_from_x11_to_x10(ty)
}

///|
fn Codegen::emit_load_reg_bytes_from_addr(
  self : Codegen,
  dst : String,
  addr : String,
  offset : Int,
  size : Int,
) -> Unit {
  if size <= 0 {
    self.emit("\tmov\t" + dst + ", #0")
    return
  }
  if size >= 8 {
    self.emit(
      "\tldr\t" + dst + ", " + mir_body_codegen_arm_addr_ref(addr, offset),
    )
    return
  }
  self.emit("\tmov\t" + dst + ", #0")
  let mut pos = 0
  while pos < size {
    let remaining = size - pos
    let chunk = if remaining >= 4 { 4 } else if remaining >= 2 { 2 } else { 1 }
    let load_reg = if pos == 0 { w_reg(dst) } else { "w12" }
    let ref_ = mir_body_codegen_arm_addr_ref(addr, offset + pos)
    match chunk {
      4 => self.emit("\tldr\t" + load_reg + ", " + ref_)
      2 => self.emit("\tldrh\t" + load_reg + ", " + ref_)
      _ => self.emit("\tldrb\t" + load_reg + ", " + ref_)
    }
    if pos > 0 {
      self.emit(
        "\torr\t" + dst + ", " + dst + ", x12, lsl #" + (pos * 8).to_string(),
      )
    }
    pos += chunk
  }
}

///|
fn Codegen::emit_store_reg_bytes_to_addr(
  self : Codegen,
  src : String,
  addr : String,
  offset : Int,
  size : Int,
) -> Unit {
  let mut pos = 0
  while pos < size {
    let remaining = size - pos
    let chunk = if remaining >= 8 {
      8
    } else if remaining >= 4 {
      4
    } else if remaining >= 2 {
      2
    } else {
      1
    }
    let value_reg = if pos == 0 {
      src
    } else {
      self.emit("\tlsr\tx12, " + src + ", #" + (pos * 8).to_string())
      "x12"
    }
    let ref_ = mir_body_codegen_arm_addr_ref(addr, offset + pos)
    match chunk {
      8 => self.emit("\tstr\t" + value_reg + ", " + ref_)
      4 => self.emit("\tstr\t" + w_reg(value_reg) + ", " + ref_)
      2 => self.emit("\tstrh\t" + w_reg(value_reg) + ", " + ref_)
      _ => self.emit("\tstrb\t" + w_reg(value_reg) + ", " + ref_)
    }
    pos += chunk
  }
}

///|
fn Codegen::emit_load_register_aggregate_return_from_x9(
  self : Codegen,
  ty : @ctype.Type,
) -> Unit {
  let size = self.type_size(ty)
  if size <= 8 {
    self.emit_load_reg_bytes_from_addr("x0", "x9", 0, size)
  } else {
    self.emit_load_reg_bytes_from_addr("x0", "x9", 0, 8)
    self.emit_load_reg_bytes_from_addr("x1", "x9", 8, size - 8)
  }
}

///|
fn Codegen::emit_store_register_aggregate_return_to_x9(
  self : Codegen,
  ty : @ctype.Type,
) -> Unit {
  let size = self.type_size(ty)
  if size <= 8 {
    self.emit_store_reg_bytes_to_addr("x0", "x9", 0, size)
  } else {
    self.emit_store_reg_bytes_to_addr("x0", "x9", 0, 8)
    self.emit_store_reg_bytes_to_addr("x1", "x9", 8, size - 8)
  }
}

///|
fn Codegen::emit_copy_memory_aggregate_from_x11_to_x10(
  self : Codegen,
  ty : @ctype.Type,
) -> Unit {
  let mut offset = 0
  let mut remaining = self.type_size(ty)
  while remaining > 0 {
    let chunk = if remaining >= 8 {
      8
    } else if remaining >= 4 {
      4
    } else if remaining >= 2 {
      2
    } else {
      1
    }
    let src = mir_body_codegen_arm_addr_ref("x11", offset)
    let dst = mir_body_codegen_arm_addr_ref("x10", offset)
    match chunk {
      8 => {
        self.emit("\tldr\tx12, " + src)
        self.emit("\tstr\tx12, " + dst)
      }
      4 => {
        self.emit("\tldr\tw12, " + src)
        self.emit("\tstr\tw12, " + dst)
      }
      2 => {
        self.emit("\tldrh\tw12, " + src)
        self.emit("\tstrh\tw12, " + dst)
      }
      _ => {
        self.emit("\tldrb\tw12, " + src)
        self.emit("\tstrb\tw12, " + dst)
      }
    }
    offset += chunk
    remaining -= chunk
  }
}

///|
fn Codegen::sret_result_offset(self : Codegen, ret_ty : @ctype.Type) -> Int {
  if self.pending_sret_offset >= 0 {
    self.pending_sret_offset
  } else if self.is_memory_aggregate(ret_ty) {
    if self.sret_scratch_offset < 0 {
      abort("Darwin ARM64 MIR backend missing aggregate return scratch storage")
    }
    self.sret_scratch_offset
  } else {
    -1
  }
}

///|
fn Codegen::emit_call_sret_addr(
  self : Codegen,
  ret_ty : @ctype.Type,
  frame_size : Int,
) -> Unit {
  let offset = self.sret_result_offset(ret_ty)
  if offset >= 0 {
    self.emit_local_addr(offset, frame_size)
    self.emit("\tmov\tx8, x9")
  }
}

///|
fn Codegen::emit_sret_result_addr(
  self : Codegen,
  ret_ty : @ctype.Type,
  frame_size : Int,
) -> Unit {
  let offset = self.sret_result_offset(ret_ty)
  if offset < 0 {
    abort("Darwin ARM64 MIR backend missing aggregate return result storage")
  }
  self.emit_local_addr(offset, frame_size)
}

///|
fn Codegen::emit_sret_dest_addr(self : Codegen, frame_size : Int) -> Unit {
  if self.sret_dest_offset < 0 {
    abort("Darwin ARM64 MIR backend missing aggregate return destination")
  }
  self.emit_local_addr(self.sret_dest_offset, frame_size)
  self.emit_load_typed("x9", "x9", Pointer(Void))
}

///|
fn Codegen::gen_mir_aggregate_return_addr(
  self : Codegen,
  value : @mir.MirValue,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  match value {
    MirLocal(binding) => self.emit_local_addr(offsets[binding.id], frame_size)
    MirAggregateArg(addr, _) => self.gen_mir_value(addr, offsets, frame_size)
    MirLoad(ptr, _) => self.gen_mir_value(ptr, offsets, frame_size)
    MirCall(_, _, _) | MirIndirectCall(_, _, _) =>
      self.gen_mir_value(value, offsets, frame_size)
    _ => abort("unsupported Darwin ARM64 MIR aggregate return source")
  }
}

///|
fn Codegen::emit_mir_rotate_op(
  self : Codegen,
  op : String,
  lhs : @mir.MirValue,
  rhs : @mir.MirValue,
  ty : @ctype.Type,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  let (width, left) = match mir_body_codegen_rotate_op(op) {
    Some(value) => value
    None => abort("unsupported MIR body rotate operator")
  }
  self.gen_mir_value(lhs, offsets, frame_size)
  self.emit_numeric_conversion(lhs.ty(), ty)
  self.emit_scalar_conversion_to(ty)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_mir_value(rhs, offsets, frame_size)
  self.emit_scalar_conversion_to(rhs.ty())
  self.emit("\tmov\tx10, x9")
  self.emit("\tldr\tx9, [sp], #16")
  if width == 32 {
    self.emit("\tneg\tw11, w10")
    if left {
      self.emit("\tlsl\tw12, w9, w10")
      self.emit("\tlsr\tw11, w9, w11")
    } else {
      self.emit("\tlsr\tw12, w9, w10")
      self.emit("\tlsl\tw11, w9, w11")
    }
    self.emit("\torr\tw9, w12, w11")
  } else {
    self.emit("\tneg\tx11, x10")
    if left {
      self.emit("\tlsl\tx12, x9, x10")
      self.emit("\tlsr\tx11, x9, x11")
    } else {
      self.emit("\tlsr\tx12, x9, x10")
      self.emit("\tlsl\tx11, x9, x11")
    }
    self.emit("\torr\tx9, x12, x11")
  }
  self.emit_scalar_conversion_to(ty)
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
      match peel_aligned_type(ty) {
        SInt128 => self.emit_load_int("x10", if bits < 0L { -1L } else { 0L })
        UInt128 => self.emit("\tmov\tx10, #0")
        _ => self.emit_scalar_conversion_to(ty)
      }
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
    MirLabelAddr(name) => self.emit("\tadr\tx9, " + self.label_ref(name))
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
      self.emit_load_int(
        "x10",
        self.mir_pointer_element_scale(elem_ty).to_int64(),
      )
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
        "fp_isnan"
        | "fp_isinf"
        | "fp_isfinite"
        | "fp_isnormal"
        | "fp_signbit" =>
          if mir_body_codegen_floating_type(inner.ty()) {
            self.emit_mir_fp_class_result(op, inner.ty())
            self.emit_scalar_conversion_to(ty)
          } else {
            abort("unsupported MIR body floating classification operand")
          }
        "alloca" => {
          self.emit("\tadd\tx9, x9, #15")
          self.emit("\tbic\tx9, x9, #0xF")
          self.emit("\tsub\tsp, sp, x9")
          self.emit("\tmov\tx9, sp")
        }
        "frame_address" =>
          match inner {
            MirConst(level, _) =>
              if level == 0L {
                self.emit("\tmov\tx9, x29")
              } else {
                self.emit("\tmov\tx9, #0")
              }
            _ => {
              self.emit("\tcmp\tx9, #0")
              self.emit("\tmov\tx10, #0")
              self.emit("\tcsel\tx9, x29, x10, eq")
            }
          }
        "return_address" =>
          match inner {
            MirConst(level, _) =>
              if level == 0L {
                self.emit("\tldr\tx9, [x29, #8]")
              } else {
                self.emit("\tmov\tx9, #0")
              }
            _ => {
              self.emit("\tcmp\tx9, #0")
              self.emit("\tldr\tx10, [x29, #8]")
              self.emit("\tmov\tx11, #0")
              self.emit("\tcsel\tx9, x10, x11, eq")
            }
          }
        "sync_synchronize" | "atomic_thread_fence" => {
          self.emit("\tdmb\tish")
          self.emit("\tmov\tx9, #0")
        }
        "atomic_signal_fence" => self.emit("\tmov\tx9, #0")
        "trap" => {
          self.emit("\tbrk\t#0x1")
          self.emit("\tmov\tx9, #0")
        }
        "+" => ()
        "-" =>
          if mir_body_codegen_int128_type(ty) {
            self.emit_numeric_conversion(inner.ty(), ty)
            self.emit("\tnegs\tx9, x9")
            self.emit("\tngc\tx10, x10")
          } else if mir_body_codegen_floating_type(ty) {
            self.emit_numeric_conversion(inner.ty(), ty)
            self.emit(
              "\tfmov\t" +
              mir_body_codegen_arm_fp_reg(ty, 9) +
              ", " +
              mir_body_codegen_arm_fp_bits_reg(ty, "x9"),
            )
            self.emit(
              "\tfneg\t" +
              mir_body_codegen_arm_fp_reg(ty, 9) +
              ", " +
              mir_body_codegen_arm_fp_reg(ty, 9),
            )
            self.emit(
              "\tfmov\t" +
              mir_body_codegen_arm_fp_bits_reg(ty, "x9") +
              ", " +
              mir_body_codegen_arm_fp_reg(ty, 9),
            )
          } else {
            self.emit("\tneg\tx9, x9")
          }
        "fabs" =>
          if mir_body_codegen_floating_type(ty) {
            self.emit_numeric_conversion(inner.ty(), ty)
            self.emit(
              "\tfmov\t" +
              mir_body_codegen_arm_fp_reg(ty, 9) +
              ", " +
              mir_body_codegen_arm_fp_bits_reg(ty, "x9"),
            )
            self.emit(
              "\tfabs\t" +
              mir_body_codegen_arm_fp_reg(ty, 9) +
              ", " +
              mir_body_codegen_arm_fp_reg(ty, 9),
            )
            self.emit(
              "\tfmov\t" +
              mir_body_codegen_arm_fp_bits_reg(ty, "x9") +
              ", " +
              mir_body_codegen_arm_fp_reg(ty, 9),
            )
          } else {
            abort("unsupported MIR body fabs result type")
          }
        "fsqrt" =>
          if mir_body_codegen_floating_type(ty) {
            self.emit_numeric_conversion(inner.ty(), ty)
            self.emit(
              "\tfmov\t" +
              mir_body_codegen_arm_fp_reg(ty, 9) +
              ", " +
              mir_body_codegen_arm_fp_bits_reg(ty, "x9"),
            )
            self.emit(
              "\tfsqrt\t" +
              mir_body_codegen_arm_fp_reg(ty, 9) +
              ", " +
              mir_body_codegen_arm_fp_reg(ty, 9),
            )
            self.emit(
              "\tfmov\t" +
              mir_body_codegen_arm_fp_bits_reg(ty, "x9") +
              ", " +
              mir_body_codegen_arm_fp_reg(ty, 9),
            )
          } else {
            abort("unsupported MIR body fsqrt result type")
          }
        "!" =>
          if mir_body_codegen_int128_type(inner.ty()) {
            self.emit("\torr\tx9, x9, x10")
            self.emit("\tcmp\tx9, #0")
            self.emit("\tcset\tx9, eq")
          } else if mir_body_codegen_floating_type(inner.ty()) {
            let reg = mir_body_codegen_arm_fp_reg(inner.ty(), 9)
            self.emit(
              "\tfmov\t" +
              reg +
              ", " +
              mir_body_codegen_arm_fp_bits_reg(inner.ty(), "x9"),
            )
            self.emit("\tfcmp\t" + reg + ", #0.0")
            self.emit("\tcset\tx9, eq")
          } else {
            self.emit("\tcmp\tx9, #0")
            self.emit("\tcset\tx9, eq")
          }
        "~" =>
          if mir_body_codegen_int128_type(ty) {
            self.emit_numeric_conversion(inner.ty(), ty)
            self.emit("\tmvn\tx9, x9")
            self.emit("\tmvn\tx10, x10")
          } else {
            self.emit("\tmvn\tx9, x9")
          }
        "abs32" => {
          self.emit_numeric_conversion(inner.ty(), ty)
          let done = self.new_label()
          self.emit("\tcmp\tw9, #0")
          self.emit("\tb.ge\t" + done)
          self.emit("\tneg\tw9, w9")
          self.emit(done + ":")
        }
        "abs64" => {
          self.emit_numeric_conversion(inner.ty(), ty)
          let done = self.new_label()
          self.emit("\tcmp\tx9, #0")
          self.emit("\tb.ge\t" + done)
          self.emit("\tneg\tx9, x9")
          self.emit(done + ":")
        }
        "clz32" => self.emit("\tclz\tw9, w9")
        "clz64" => self.emit("\tclz\tx9, x9")
        "ctz32" => {
          self.emit("\trbit\tw9, w9")
          self.emit("\tclz\tw9, w9")
        }
        "ctz64" => {
          self.emit("\trbit\tx9, x9")
          self.emit("\tclz\tx9, x9")
        }
        "ffs32" => {
          let zero_label = self.new_label()
          let done_label = self.new_label()
          self.emit("\tcbz\tw9, " + zero_label)
          self.emit("\trbit\tw9, w9")
          self.emit("\tclz\tw9, w9")
          self.emit("\tadd\tw9, w9, #1")
          self.emit("\tb\t" + done_label)
          self.emit(zero_label + ":")
          self.emit("\tmov\tx9, #0")
          self.emit(done_label + ":")
        }
        "ffs64" => {
          let zero_label = self.new_label()
          let done_label = self.new_label()
          self.emit("\tcbz\tx9, " + zero_label)
          self.emit("\trbit\tx9, x9")
          self.emit("\tclz\tx9, x9")
          self.emit("\tadd\tx9, x9, #1")
          self.emit("\tb\t" + done_label)
          self.emit(zero_label + ":")
          self.emit("\tmov\tx9, #0")
          self.emit(done_label + ":")
        }
        "bswap16" => {
          self.emit("\trev\tw9, w9")
          self.emit("\tlsr\tw9, w9, #16")
        }
        "bswap32" => self.emit("\trev\tw9, w9")
        "bswap64" => self.emit("\trev\tx9, x9")
        "popcount32" | "popcount64" | "parity32" | "parity64" => {
          if op == "popcount32" || op == "parity32" {
            self.emit("\tmov\tw9, w9")
          }
          self.emit("\tlsr\tx10, x9, #1")
          self.emit_load_int("x11", 6148914691236517205L)
          self.emit("\tand\tx10, x10, x11")
          self.emit("\tsub\tx9, x9, x10")
          self.emit_load_int("x11", 3689348814741910323L)
          self.emit("\tand\tx10, x9, x11")
          self.emit("\tlsr\tx12, x9, #2")
          self.emit("\tand\tx12, x12, x11")
          self.emit("\tadd\tx9, x10, x12")
          self.emit("\tlsr\tx10, x9, #4")
          self.emit("\tadd\tx9, x9, x10")
          self.emit_load_int("x11", 1085102592571150095L)
          self.emit("\tand\tx9, x9, x11")
          self.emit("\tlsr\tx10, x9, #8")
          self.emit("\tadd\tx9, x9, x10")
          self.emit("\tlsr\tx10, x9, #16")
          self.emit("\tadd\tx9, x9, x10")
          self.emit("\tlsr\tx10, x9, #32")
          self.emit("\tadd\tx9, x9, x10")
          if op == "parity32" || op == "parity64" {
            self.emit("\tand\tx9, x9, #1")
          } else {
            self.emit("\tand\tx9, x9, #127")
          }
        }
        _ => abort("unsupported MIR body unary operator")
      }
      self.emit_scalar_conversion_to(ty)
    }
    MirBinary(op, lhs, rhs, ty) =>
      self.gen_mir_binary(op, lhs, rhs, ty, offsets, frame_size)
    MirCast(ty, inner) => {
      self.gen_mir_value(inner, offsets, frame_size)
      if mir_body_codegen_int128_type(inner.ty()) &&
        peel_aligned_type(ty) == Bool {
        self.emit("\torr\tx9, x9, x10")
      }
      self.emit_numeric_conversion(inner.ty(), ty)
      self.emit_scalar_conversion_to(ty)
    }
    MirAggregateArg(addr, _) => self.gen_mir_value(addr, offsets, frame_size)
    MirVaArg(ap, ty) => self.emit_mir_va_arg(ap, ty, offsets, frame_size)
    MirVaArgAddr(ap, ty) =>
      self.emit_mir_va_arg_addr(ap, ty, offsets, frame_size)
    MirAssignLocal(binding, rhs) => {
      self.gen_mir_value(rhs, offsets, frame_size)
      self.emit_numeric_conversion(rhs.ty(), binding.ty)
      self.emit_scalar_conversion_to(binding.ty)
      self.emit_store_mir_local_scalar(
        "x9",
        offsets[binding.id],
        frame_size,
        binding.ty,
      )
    }
    MirStore(ptr, rhs, ty) =>
      if self.is_hfa_aggregate(ty) {
        self.gen_mir_value(ptr, offsets, frame_size)
        self.emit("\tstr\tx9, [sp, #-16]!")
        match rhs {
          MirCall(_, _, _) | MirIndirectCall(_, _, _) =>
            self.gen_mir_value(rhs, offsets, frame_size)
          _ => {
            self.gen_mir_aggregate_return_addr(rhs, offsets, frame_size)
            self.emit_load_hfa_aggregate_return_from_x9(ty)
          }
        }
        self.emit("\tldr\tx9, [sp], #16")
        self.emit_store_hfa_aggregate_return_to_x9(ty)
      } else if self.is_register_aggregate(ty) {
        self.gen_mir_value(ptr, offsets, frame_size)
        self.emit("\tstr\tx9, [sp, #-16]!")
        match rhs {
          MirCall(_, _, _) | MirIndirectCall(_, _, _) =>
            self.gen_mir_value(rhs, offsets, frame_size)
          _ => {
            self.gen_mir_aggregate_return_addr(rhs, offsets, frame_size)
            self.emit_load_register_aggregate_return_from_x9(ty)
          }
        }
        self.emit("\tldr\tx9, [sp], #16")
        self.emit_store_register_aggregate_return_to_x9(ty)
      } else if self.is_memory_aggregate(ty) {
        self.gen_mir_value(ptr, offsets, frame_size)
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.gen_mir_aggregate_return_addr(rhs, offsets, frame_size)
        self.emit("\tmov\tx11, x9")
        self.emit("\tldr\tx10, [sp], #16")
        self.emit_copy_memory_aggregate_from_x11_to_x10(ty)
        self.emit("\tmov\tx9, x10")
      } else {
        self.gen_mir_value(ptr, offsets, frame_size)
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.gen_mir_value(rhs, offsets, frame_size)
        self.emit_numeric_conversion(rhs.ty(), ty)
        self.emit_scalar_conversion_to(ty)
        if mir_body_codegen_int128_type(ty) {
          self.emit("\tstp\tx9, x10, [sp, #-16]!")
          self.emit("\tldr\tx11, [sp, #16]")
          self.emit("\tldp\tx9, x10, [sp], #16")
          self.emit("\tadd\tsp, sp, #16")
          self.emit_store_typed("x9", "x11", ty)
        } else {
          self.emit("\tldr\tx10, [sp], #16")
          self.emit_store_typed("x9", "x10", ty)
        }
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
      self.emit_store_mir_local_scalar(
        "x9",
        offsets[binding.id],
        frame_size,
        binding.ty,
      )
      self.emit("\tldr\tx9, [sp], #16")
      self.emit_scalar_conversion_to(ty)
    }
    MirPreUpdateMemory(ptr, op, rhs, ty) => {
      if mir_body_pointer_integer_op(op, ty, rhs.ty()) {
        self.gen_mir_value(ptr, offsets, frame_size)
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.emit_load_typed("x10", "x9", ty)
        self.emit("\tstr\tx10, [sp, #-16]!")
        self.gen_mir_value(rhs, offsets, frame_size)
        self.emit_scalar_conversion_to(rhs.ty())
        self.emit_mir_scale_update_rhs_for_pointer(ty)
        self.emit("\tldr\tx10, [sp], #16")
        match op {
          "+" => self.emit("\tadd\tx9, x10, x9")
          "-" => self.emit("\tsub\tx9, x10, x9")
          _ => abort("unsupported MIR body memory pointer pre-update operator")
        }
        self.emit("\tldr\tx12, [sp], #16")
        self.emit_store_typed("x9", "x12", ty)
        return
      }
      if mir_body_codegen_fp_update_supported(op, ty, rhs.ty()) {
        let fp_ty = mir_body_codegen_fp_binary_type(ty, rhs.ty(), ty)
        self.gen_mir_value(ptr, offsets, frame_size)
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.emit_load_typed("x9", "x9", ty)
        self.emit_numeric_conversion(ty, fp_ty)
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.gen_mir_value(rhs, offsets, frame_size)
        self.emit_numeric_conversion(rhs.ty(), fp_ty)
        self.emit("\tldr\tx10, [sp], #16")
        self.emit_mir_fp_binary_from_x10_x9(op, fp_ty)
        self.emit_numeric_conversion(fp_ty, ty)
        self.emit_scalar_conversion_to(ty)
        self.emit("\tldr\tx12, [sp], #16")
        self.emit_store_typed("x9", "x12", ty)
        return
      }
      let left_ty = mir_body_binary_left_type(op, ty, rhs.ty())
      let right_ty = mir_body_binary_right_type(op, ty, rhs.ty())
      self.gen_mir_value(ptr, offsets, frame_size)
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.emit_load_typed("x10", "x9", ty)
      self.emit("\tmov\tx9, x10")
      self.emit_numeric_conversion(ty, left_ty)
      self.emit_scalar_conversion_to(left_ty)
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.gen_mir_value(rhs, offsets, frame_size)
      self.emit_numeric_conversion(rhs.ty(), right_ty)
      self.emit_scalar_conversion_to(right_ty)
      self.emit("\tldr\tx10, [sp], #16")
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
      if mir_body_pointer_integer_op(op, ty, rhs.ty()) {
        self.gen_mir_value(ptr, offsets, frame_size)
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.emit_load_typed("x10", "x9", ty)
        self.emit("\tstr\tx10, [sp, #-16]!")
        self.gen_mir_value(rhs, offsets, frame_size)
        self.emit_scalar_conversion_to(rhs.ty())
        self.emit_mir_scale_update_rhs_for_pointer(ty)
        self.emit("\tldr\tx10, [sp], #16")
        match op {
          "+" => self.emit("\tadd\tx11, x10, x9")
          "-" => self.emit("\tsub\tx11, x10, x9")
          _ => abort("unsupported MIR body memory pointer post-update operator")
        }
        self.emit("\tldr\tx12, [sp], #16")
        self.emit_store_typed("x11", "x12", ty)
        self.emit("\tmov\tx9, x10")
        return
      }
      if mir_body_codegen_fp_update_supported(op, ty, rhs.ty()) {
        let fp_ty = mir_body_codegen_fp_binary_type(ty, rhs.ty(), ty)
        self.gen_mir_value(ptr, offsets, frame_size)
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.emit_load_typed("x9", "x9", ty)
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.emit_numeric_conversion(ty, fp_ty)
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.gen_mir_value(rhs, offsets, frame_size)
        self.emit_numeric_conversion(rhs.ty(), fp_ty)
        self.emit("\tldr\tx10, [sp], #16")
        self.emit_mir_fp_binary_from_x10_x9(op, fp_ty)
        self.emit_numeric_conversion(fp_ty, ty)
        self.emit_scalar_conversion_to(ty)
        self.emit("\tldr\tx11, [sp], #16")
        self.emit("\tldr\tx12, [sp], #16")
        self.emit_store_typed("x9", "x12", ty)
        self.emit("\tmov\tx9, x11")
        self.emit_scalar_conversion_to(ty)
        return
      }
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
      self.emit_mir_cond_jump_false(cond, offsets, frame_size, else_label)
      self.gen_mir_value(then_, offsets, frame_size)
      self.emit_numeric_conversion(then_.ty(), ty)
      self.emit_scalar_conversion_to(ty)
      self.emit("\tb\t" + end_label)
      self.emit(else_label + ":")
      self.gen_mir_value(else_, offsets, frame_size)
      self.emit_numeric_conversion(else_.ty(), ty)
      self.emit_scalar_conversion_to(ty)
      self.emit(end_label + ":")
    }
    MirOverflow(op, left, right, result_ptr) =>
      self.emit_mir_overflow_arithmetic_builtin(
        left, right, result_ptr, offsets, frame_size, op,
      )
    MirVaStart(target) => self.emit_mir_va_start(target, offsets, frame_size)
    MirVaCopy(target, source) =>
      self.emit_mir_va_copy(target, source, offsets, frame_size)
    MirVaEnd(_) => self.emit("\tmov\tx9, #0")
    MirBzero(dst, size) => self.emit_mir_bzero(dst, size, offsets, frame_size)
    MirAtomicLoad(ptr, order, _) =>
      self.emit_mir_atomic_load(ptr, order, offsets, frame_size)
    MirAtomicStore(ptr, value, order) =>
      self.emit_mir_atomic_store(ptr, value, order, offsets, frame_size)
    MirAtomicUpdate(op, return_new, ptr, value, extras, _) =>
      self.emit_mir_atomic_update(
        ptr, value, extras, offsets, frame_size, op, return_new,
      )
    MirAtomicExchange(ptr, value, extras, _) =>
      self.emit_mir_atomic_exchange(ptr, value, extras, offsets, frame_size)
    MirAtomicCompareExchange(ptr, expected, desired, extras) =>
      self.emit_mir_atomic_compare_exchange(
        ptr, expected, desired, extras, offsets, frame_size,
      )
    MirLibCall(name, args, ty) =>
      self.gen_mir_value(MirCall(name, args, ty), offsets, frame_size)
    MirCall(name, args, ty) => {
      let source_indexes = mir_body_codegen_direct_call_source_indexes(args)
      if self.mir_direct_call_variadic(name) {
        let named_count = self.mir_direct_call_named_arg_count(name)
        let expected_types : Array[@ctype.Type] = []
        let arg_slot_counts : Array[Int] = []
        let arg_raw_sizes : Array[Int] = []
        for i in 0..<source_indexes.length() {
          let arg = args[source_indexes[i]]
          let expected = self.mir_call_arg_type(name, i, arg.ty())
          expected_types.push(expected)
          match peel_aligned_type(expected) {
            Struct(_) | Union(_) => {
              let (slots, raw_size) = self.emit_save_darwin_variadic_aggregate_arg_raw(
                arg, expected, offsets, frame_size,
              )
              arg_slot_counts.push(slots)
              arg_raw_sizes.push(raw_size)
            }
            _ => {
              let slots = mir_body_codegen_abi_int_slots(expected)
              arg_slot_counts.push(slots)
              arg_raw_sizes.push(16)
              self.gen_mir_value(arg, offsets, frame_size)
              self.emit_numeric_conversion(arg.ty(), expected)
              self.emit_scalar_conversion_to(expected)
              if mir_body_codegen_int128_type(expected) {
                self.emit("\tstp\tx9, x10, [sp, #-16]!")
              } else {
                self.emit("\tstr\tx9, [sp, #-16]!")
              }
            }
          }
        }
        let mut raw_args_area = 0
        for raw_size in arg_raw_sizes {
          raw_args_area += raw_size
        }
        let mut variadic_slots = 0
        for i in named_count..<arg_slot_counts.length() {
          variadic_slots += arg_slot_counts[i]
        }
        let variadic_area = if variadic_slots * 8 > 64 {
          (variadic_slots * 8 + 15) / 16 * 16
        } else {
          64
        }
        self.emit("\tsub\tsp, sp, #" + variadic_area.to_string())
        let mut int_arg_index = 0
        let mut fp_arg_index = 0
        let mut raw_offset_cursor = variadic_area + raw_args_area
        for i in 0..<source_indexes.length() {
          raw_offset_cursor -= arg_raw_sizes[i]
          let raw_offset = raw_offset_cursor
          if mir_body_codegen_abi_fp_type(expected_types[i]) {
            if fp_arg_index < 8 {
              self.emit("\tldr\tx9, [sp, #" + raw_offset.to_string() + "]")
              self.emit_mir_fp_arg_from_x9(expected_types[i], fp_arg_index)
            }
            fp_arg_index += 1
          } else if peel_aligned_type(expected_types[i]) is Struct(_) ||
            peel_aligned_type(expected_types[i]) is Union(_) {
            if int_arg_index < 8 {
              self.emit(
                "\tldr\tx" +
                int_arg_index.to_string() +
                ", [sp, #" +
                raw_offset.to_string() +
                "]",
              )
            }
            int_arg_index += 1
            if arg_slot_counts[i] == 2 {
              if int_arg_index < 8 {
                self.emit(
                  "\tldr\tx" +
                  int_arg_index.to_string() +
                  ", [sp, #" +
                  (raw_offset + 8).to_string() +
                  "]",
                )
              }
              int_arg_index += 1
            }
          } else if mir_body_codegen_int128_type(expected_types[i]) {
            if int_arg_index + 2 <= 8 {
              self.emit(
                "\tldr\tx" +
                int_arg_index.to_string() +
                ", [sp, #" +
                raw_offset.to_string() +
                "]",
              )
              self.emit(
                "\tldr\tx" +
                (int_arg_index + 1).to_string() +
                ", [sp, #" +
                (raw_offset + 8).to_string() +
                "]",
              )
            }
            int_arg_index += 2
          } else {
            if int_arg_index < 8 {
              self.emit(
                "\tldr\tx" +
                int_arg_index.to_string() +
                ", [sp, #" +
                raw_offset.to_string() +
                "]",
              )
            }
            int_arg_index += 1
          }
        }
        let mut dst_slot = 0
        raw_offset_cursor = variadic_area + raw_args_area
        for i in named_count..<source_indexes.length() {
          raw_offset_cursor = variadic_area + raw_args_area
          for j in 0..<(i + 1) {
            raw_offset_cursor -= arg_raw_sizes[j]
          }
          let raw_offset = raw_offset_cursor
          for j in 0..<arg_slot_counts[i] {
            self.emit(
              "\tldr\tx9, [sp, #" + (raw_offset + j * 8).to_string() + "]",
            )
            self.emit(
              "\tstr\tx9, [sp, #" + ((dst_slot + j) * 8).to_string() + "]",
            )
          }
          dst_slot += arg_slot_counts[i]
        }
        self.emit_call_sret_addr(ty, frame_size)
        self.emit("\tbl\t_" + mir_body_codegen_direct_call_symbol(name))
        self.emit(
          "\tadd\tsp, sp, #" + (variadic_area + raw_args_area).to_string(),
        )
      } else {
        let expected_types : Array[@ctype.Type] = []
        let int_arg_indexes : Array[Int] = []
        let fp_arg_indexes : Array[Int] = []
        let stack_arg_indexes : Array[Int] = []
        let arg_is_hfa : Array[Bool] = []
        let arg_is_register_aggregate : Array[Bool] = []
        let arg_is_indirect_aggregate : Array[Bool] = []
        let arg_slot_counts : Array[Int] = []
        let arg_raw_sizes : Array[Int] = []
        let mut int_arg_index = 0
        let mut fp_arg_index = 0
        let mut stack_arg_index = 0
        for i in 0..<source_indexes.length() {
          let arg = args[source_indexes[i]]
          let expected = self.mir_call_arg_type(name, i, arg.ty())
          expected_types.push(expected)
          if mir_body_codegen_abi_fp_type(expected) {
            arg_is_hfa.push(false)
            arg_is_register_aggregate.push(false)
            arg_is_indirect_aggregate.push(false)
            arg_slot_counts.push(1)
            int_arg_indexes.push(-1)
            if fp_arg_index < 8 {
              fp_arg_indexes.push(fp_arg_index)
              stack_arg_indexes.push(-1)
            } else {
              fp_arg_indexes.push(-1)
              stack_arg_indexes.push(stack_arg_index)
              stack_arg_index += 1
            }
            fp_arg_index += 1
            arg_raw_sizes.push(16)
            self.gen_mir_value(arg, offsets, frame_size)
            self.emit_numeric_conversion(arg.ty(), expected)
            self.emit_scalar_conversion_to(expected)
            self.emit("\tstr\tx9, [sp, #-16]!")
          } else if self.is_hfa_aggregate(expected) {
            let hfa_count = match self.darwin_hfa_parts(expected) {
              Some((_, count)) => count
              None => abort("unsupported Darwin ARM64 MIR HFA call argument")
            }
            arg_is_hfa.push(true)
            arg_is_register_aggregate.push(false)
            arg_is_indirect_aggregate.push(false)
            arg_slot_counts.push(hfa_count)
            int_arg_indexes.push(-1)
            if fp_arg_index + hfa_count <= 8 {
              fp_arg_indexes.push(fp_arg_index)
              stack_arg_indexes.push(-1)
            } else {
              let stack_slots = (self.type_size(expected) + 7) / 8
              fp_arg_indexes.push(-1)
              stack_arg_indexes.push(stack_arg_index)
              stack_arg_index += stack_slots
            }
            fp_arg_index += hfa_count
            let raw_size = (self.type_size(expected) + 15) / 16 * 16
            arg_raw_sizes.push(raw_size)
            self.emit_save_darwin_aggregate_call_arg_raw(
              arg, expected, raw_size, offsets, frame_size,
            )
          } else if self.is_register_aggregate(expected) {
            let slots = (self.type_size(expected) + 7) / 8
            arg_is_hfa.push(false)
            arg_is_register_aggregate.push(true)
            arg_is_indirect_aggregate.push(false)
            arg_slot_counts.push(slots)
            if int_arg_index + slots <= 8 {
              int_arg_indexes.push(int_arg_index)
              stack_arg_indexes.push(-1)
            } else {
              int_arg_indexes.push(-1)
              stack_arg_indexes.push(stack_arg_index)
              stack_arg_index += slots
            }
            fp_arg_indexes.push(-1)
            int_arg_index += slots
            let raw_size = (self.type_size(expected) + 15) / 16 * 16
            arg_raw_sizes.push(raw_size)
            self.emit_save_darwin_aggregate_call_arg_raw(
              arg, expected, raw_size, offsets, frame_size,
            )
          } else if self.is_memory_aggregate(expected) {
            arg_is_hfa.push(false)
            arg_is_register_aggregate.push(false)
            arg_is_indirect_aggregate.push(true)
            arg_slot_counts.push(1)
            if int_arg_index < 8 {
              int_arg_indexes.push(int_arg_index)
              stack_arg_indexes.push(-1)
            } else {
              int_arg_indexes.push(-1)
              stack_arg_indexes.push(stack_arg_index)
              stack_arg_index += 1
            }
            fp_arg_indexes.push(-1)
            int_arg_index += 1
            let raw_size = (self.type_size(expected) + 15) / 16 * 16
            arg_raw_sizes.push(raw_size)
            self.emit_save_darwin_aggregate_call_arg_raw(
              arg, expected, raw_size, offsets, frame_size,
            )
          } else {
            arg_is_hfa.push(false)
            arg_is_register_aggregate.push(false)
            arg_is_indirect_aggregate.push(false)
            let slots = mir_body_codegen_abi_int_slots(expected)
            arg_slot_counts.push(slots)
            if int_arg_index + slots <= 8 {
              int_arg_indexes.push(int_arg_index)
              stack_arg_indexes.push(-1)
            } else {
              int_arg_indexes.push(-1)
              stack_arg_index = mir_body_codegen_align_stack_slots(
                stack_arg_index,
                mir_body_codegen_abi_int_stack_align_slots(expected),
              )
              stack_arg_indexes.push(stack_arg_index)
              stack_arg_index += slots
            }
            fp_arg_indexes.push(-1)
            int_arg_index += slots
            arg_raw_sizes.push(16)
            self.gen_mir_value(arg, offsets, frame_size)
            self.emit_numeric_conversion(arg.ty(), expected)
            self.emit_scalar_conversion_to(expected)
            if mir_body_codegen_int128_type(expected) {
              self.emit("\tstp\tx9, x10, [sp, #-16]!")
            } else {
              self.emit("\tstr\tx9, [sp, #-16]!")
            }
          }
        }
        let mut raw_area = 0
        for raw_size in arg_raw_sizes {
          raw_area += raw_size
        }
        let stack_area = (stack_arg_index * 8 + 15) / 16 * 16
        if stack_area > 0 {
          self.emit("\tsub\tsp, sp, #" + stack_area.to_string())
        }
        let mut raw_offset_cursor = stack_area + raw_area
        for i in 0..<source_indexes.length() {
          raw_offset_cursor -= arg_raw_sizes[i]
          let raw_offset = raw_offset_cursor
          if arg_is_hfa[i] {
            if fp_arg_indexes[i] >= 0 {
              self.emit_load_hfa_aggregate_arg_from_raw(
                expected_types[i],
                raw_offset,
                fp_arg_indexes[i],
              )
            } else {
              self.emit_copy_darwin_aggregate_arg_from_raw_to_stack(
                expected_types[i],
                raw_offset,
                stack_arg_indexes[i] * 8,
              )
            }
          } else if arg_is_register_aggregate[i] {
            if int_arg_indexes[i] >= 0 {
              for j in 0..<arg_slot_counts[i] {
                self.emit(
                  "\tldr\tx" +
                  (int_arg_indexes[i] + j).to_string() +
                  ", [sp, #" +
                  (raw_offset + j * 8).to_string() +
                  "]",
                )
              }
            } else {
              self.emit_copy_darwin_aggregate_arg_from_raw_to_stack(
                expected_types[i],
                raw_offset,
                stack_arg_indexes[i] * 8,
              )
            }
          } else if arg_is_indirect_aggregate[i] {
            self.emit_pass_darwin_indirect_aggregate_arg_from_raw(
              raw_offset,
              int_arg_indexes[i],
              stack_arg_indexes[i],
            )
          } else if mir_body_codegen_abi_fp_type(expected_types[i]) {
            self.emit("\tldr\tx9, [sp, #" + raw_offset.to_string() + "]")
            if fp_arg_indexes[i] >= 0 {
              self.emit_mir_fp_arg_from_x9(expected_types[i], fp_arg_indexes[i])
            } else {
              self.emit(
                "\tstr\tx9, [sp, #" +
                (stack_arg_indexes[i] * 8).to_string() +
                "]",
              )
            }
          } else if int_arg_indexes[i] >= 0 {
            if mir_body_codegen_int128_type(expected_types[i]) {
              self.emit(
                "\tldr\tx" +
                int_arg_indexes[i].to_string() +
                ", [sp, #" +
                raw_offset.to_string() +
                "]",
              )
              self.emit(
                "\tldr\tx" +
                (int_arg_indexes[i] + 1).to_string() +
                ", [sp, #" +
                (raw_offset + 8).to_string() +
                "]",
              )
            } else {
              self.emit(
                "\tldr\tx" +
                int_arg_indexes[i].to_string() +
                ", [sp, #" +
                raw_offset.to_string() +
                "]",
              )
            }
          } else if mir_body_codegen_int128_type(expected_types[i]) {
            self.emit("\tldr\tx9, [sp, #" + raw_offset.to_string() + "]")
            self.emit("\tldr\tx10, [sp, #" + (raw_offset + 8).to_string() + "]")
            self.emit(
              "\tstr\tx9, [sp, #" + (stack_arg_indexes[i] * 8).to_string() + "]",
            )
            self.emit(
              "\tstr\tx10, [sp, #" +
              ((stack_arg_indexes[i] + 1) * 8).to_string() +
              "]",
            )
          } else {
            self.emit("\tldr\tx9, [sp, #" + raw_offset.to_string() + "]")
            self.emit(
              "\tstr\tx9, [sp, #" + (stack_arg_indexes[i] * 8).to_string() + "]",
            )
          }
        }
        self.emit_call_sret_addr(ty, frame_size)
        self.emit("\tbl\t_" + mir_body_codegen_direct_call_symbol(name))
        if raw_area + stack_area > 0 {
          self.emit("\tadd\tsp, sp, #" + (raw_area + stack_area).to_string())
        }
      }
      if self.is_memory_aggregate(ty) {
        self.emit_sret_result_addr(ty, frame_size)
      } else if self.is_hfa_aggregate(ty) {
        ()
      } else if mir_body_codegen_abi_fp_type(ty) {
        self.emit_mir_fp_return_to_x9(ty)
      } else if mir_body_codegen_int128_type(ty) {
        self.emit("\tmov\tx9, x0")
        self.emit("\tmov\tx10, x1")
      } else {
        self.emit("\tmov\tx9, x0")
        self.emit_mir_abi_int_return_conversion(ty)
      }
    }
    MirIndirectCall(callee, args, ty) => {
      self.gen_mir_value(callee, offsets, frame_size)
      self.emit("\tstr\tx9, [sp, #-16]!")
      if mir_indirect_call_variadic(callee.ty()) {
        let named_count = mir_indirect_call_named_arg_count(callee.ty())
        let expected_types : Array[@ctype.Type] = []
        let arg_slot_counts : Array[Int] = []
        let arg_raw_sizes : Array[Int] = []
        for i in 0..<args.length() {
          let arg = args[i]
          let expected = mir_indirect_call_arg_type(callee.ty(), i, arg.ty())
          expected_types.push(expected)
          match peel_aligned_type(expected) {
            Struct(_) | Union(_) => {
              let (slots, raw_size) = self.emit_save_darwin_variadic_aggregate_arg_raw(
                arg, expected, offsets, frame_size,
              )
              arg_slot_counts.push(slots)
              arg_raw_sizes.push(raw_size)
            }
            _ => {
              let slots = mir_body_codegen_abi_int_slots(expected)
              arg_slot_counts.push(slots)
              arg_raw_sizes.push(16)
              self.gen_mir_value(arg, offsets, frame_size)
              self.emit_numeric_conversion(arg.ty(), expected)
              self.emit_scalar_conversion_to(expected)
              if mir_body_codegen_int128_type(expected) {
                self.emit("\tstp\tx9, x10, [sp, #-16]!")
              } else {
                self.emit("\tstr\tx9, [sp, #-16]!")
              }
            }
          }
        }
        let mut raw_args_area = 0
        for raw_size in arg_raw_sizes {
          raw_args_area += raw_size
        }
        let mut variadic_slots = 0
        for i in named_count..<arg_slot_counts.length() {
          variadic_slots += arg_slot_counts[i]
        }
        let variadic_area = if variadic_slots * 8 > 64 {
          (variadic_slots * 8 + 15) / 16 * 16
        } else {
          64
        }
        self.emit("\tsub\tsp, sp, #" + variadic_area.to_string())
        let mut int_arg_index = 0
        let mut fp_arg_index = 0
        let mut raw_offset_cursor = variadic_area + raw_args_area
        for i in 0..<args.length() {
          raw_offset_cursor -= arg_raw_sizes[i]
          let raw_offset = raw_offset_cursor
          if mir_body_codegen_abi_fp_type(expected_types[i]) {
            if fp_arg_index < 8 {
              self.emit("\tldr\tx9, [sp, #" + raw_offset.to_string() + "]")
              self.emit_mir_fp_arg_from_x9(expected_types[i], fp_arg_index)
            }
            fp_arg_index += 1
          } else if peel_aligned_type(expected_types[i]) is Struct(_) ||
            peel_aligned_type(expected_types[i]) is Union(_) {
            if int_arg_index < 8 {
              self.emit(
                "\tldr\tx" +
                int_arg_index.to_string() +
                ", [sp, #" +
                raw_offset.to_string() +
                "]",
              )
            }
            int_arg_index += 1
            if arg_slot_counts[i] == 2 {
              if int_arg_index < 8 {
                self.emit(
                  "\tldr\tx" +
                  int_arg_index.to_string() +
                  ", [sp, #" +
                  (raw_offset + 8).to_string() +
                  "]",
                )
              }
              int_arg_index += 1
            }
          } else if mir_body_codegen_int128_type(expected_types[i]) {
            if int_arg_index + 2 <= 8 {
              self.emit(
                "\tldr\tx" +
                int_arg_index.to_string() +
                ", [sp, #" +
                raw_offset.to_string() +
                "]",
              )
              self.emit(
                "\tldr\tx" +
                (int_arg_index + 1).to_string() +
                ", [sp, #" +
                (raw_offset + 8).to_string() +
                "]",
              )
            }
            int_arg_index += 2
          } else {
            if int_arg_index < 8 {
              self.emit(
                "\tldr\tx" +
                int_arg_index.to_string() +
                ", [sp, #" +
                raw_offset.to_string() +
                "]",
              )
            }
            int_arg_index += 1
          }
        }
        let mut dst_slot = 0
        for i in named_count..<args.length() {
          raw_offset_cursor = variadic_area + raw_args_area
          for j in 0..<(i + 1) {
            raw_offset_cursor -= arg_raw_sizes[j]
          }
          let raw_offset = raw_offset_cursor
          for j in 0..<arg_slot_counts[i] {
            self.emit(
              "\tldr\tx9, [sp, #" + (raw_offset + j * 8).to_string() + "]",
            )
            self.emit(
              "\tstr\tx9, [sp, #" + ((dst_slot + j) * 8).to_string() + "]",
            )
          }
          dst_slot += arg_slot_counts[i]
        }
        self.emit(
          "\tldr\tx15, [sp, #" +
          (variadic_area + raw_args_area).to_string() +
          "]",
        )
        self.emit_call_sret_addr(ty, frame_size)
        self.emit("\tblr\tx15")
        self.emit(
          "\tadd\tsp, sp, #" + (variadic_area + raw_args_area + 16).to_string(),
        )
        if self.is_memory_aggregate(ty) {
          self.emit_sret_result_addr(ty, frame_size)
        } else if self.is_hfa_aggregate(ty) {
          ()
        } else if mir_body_codegen_abi_fp_type(ty) {
          self.emit_mir_fp_return_to_x9(ty)
        } else {
          self.emit("\tmov\tx9, x0")
          self.emit_mir_abi_int_return_conversion(ty)
        }
        return
      }
      let expected_types : Array[@ctype.Type] = []
      let int_arg_indexes : Array[Int] = []
      let fp_arg_indexes : Array[Int] = []
      let stack_arg_indexes : Array[Int] = []
      let arg_is_hfa : Array[Bool] = []
      let arg_is_register_aggregate : Array[Bool] = []
      let arg_is_indirect_aggregate : Array[Bool] = []
      let arg_slot_counts : Array[Int] = []
      let arg_raw_sizes : Array[Int] = []
      let mut int_arg_index = 0
      let mut fp_arg_index = 0
      let mut stack_arg_index = 0
      for i in 0..<args.length() {
        let arg = args[i]
        let expected = mir_indirect_call_arg_type(callee.ty(), i, arg.ty())
        expected_types.push(expected)
        if mir_body_codegen_abi_fp_type(expected) {
          arg_is_hfa.push(false)
          arg_is_register_aggregate.push(false)
          arg_is_indirect_aggregate.push(false)
          arg_slot_counts.push(1)
          int_arg_indexes.push(-1)
          if fp_arg_index < 8 {
            fp_arg_indexes.push(fp_arg_index)
            stack_arg_indexes.push(-1)
          } else {
            fp_arg_indexes.push(-1)
            stack_arg_indexes.push(stack_arg_index)
            stack_arg_index += 1
          }
          fp_arg_index += 1
          arg_raw_sizes.push(16)
          self.gen_mir_value(arg, offsets, frame_size)
          self.emit_numeric_conversion(arg.ty(), expected)
          self.emit_scalar_conversion_to(expected)
          self.emit("\tstr\tx9, [sp, #-16]!")
        } else if self.is_hfa_aggregate(expected) {
          let hfa_count = match self.darwin_hfa_parts(expected) {
            Some((_, count)) => count
            None => abort("unsupported Darwin ARM64 MIR HFA indirect argument")
          }
          arg_is_hfa.push(true)
          arg_is_register_aggregate.push(false)
          arg_is_indirect_aggregate.push(false)
          arg_slot_counts.push(hfa_count)
          int_arg_indexes.push(-1)
          if fp_arg_index + hfa_count <= 8 {
            fp_arg_indexes.push(fp_arg_index)
            stack_arg_indexes.push(-1)
          } else {
            let stack_slots = (self.type_size(expected) + 7) / 8
            fp_arg_indexes.push(-1)
            stack_arg_indexes.push(stack_arg_index)
            stack_arg_index += stack_slots
          }
          fp_arg_index += hfa_count
          let raw_size = (self.type_size(expected) + 15) / 16 * 16
          arg_raw_sizes.push(raw_size)
          self.emit_save_darwin_aggregate_call_arg_raw(
            arg, expected, raw_size, offsets, frame_size,
          )
        } else if self.is_register_aggregate(expected) {
          let slots = (self.type_size(expected) + 7) / 8
          arg_is_hfa.push(false)
          arg_is_register_aggregate.push(true)
          arg_is_indirect_aggregate.push(false)
          arg_slot_counts.push(slots)
          if int_arg_index + slots <= 8 {
            int_arg_indexes.push(int_arg_index)
            stack_arg_indexes.push(-1)
          } else {
            int_arg_indexes.push(-1)
            stack_arg_indexes.push(stack_arg_index)
            stack_arg_index += slots
          }
          fp_arg_indexes.push(-1)
          int_arg_index += slots
          let raw_size = (self.type_size(expected) + 15) / 16 * 16
          arg_raw_sizes.push(raw_size)
          self.emit_save_darwin_aggregate_call_arg_raw(
            arg, expected, raw_size, offsets, frame_size,
          )
        } else if self.is_memory_aggregate(expected) {
          arg_is_hfa.push(false)
          arg_is_register_aggregate.push(false)
          arg_is_indirect_aggregate.push(true)
          arg_slot_counts.push(1)
          if int_arg_index < 8 {
            int_arg_indexes.push(int_arg_index)
            stack_arg_indexes.push(-1)
          } else {
            int_arg_indexes.push(-1)
            stack_arg_indexes.push(stack_arg_index)
            stack_arg_index += 1
          }
          fp_arg_indexes.push(-1)
          int_arg_index += 1
          let raw_size = (self.type_size(expected) + 15) / 16 * 16
          arg_raw_sizes.push(raw_size)
          self.emit_save_darwin_aggregate_call_arg_raw(
            arg, expected, raw_size, offsets, frame_size,
          )
        } else {
          arg_is_hfa.push(false)
          arg_is_register_aggregate.push(false)
          arg_is_indirect_aggregate.push(false)
          let slots = mir_body_codegen_abi_int_slots(expected)
          arg_slot_counts.push(slots)
          if int_arg_index + slots <= 8 {
            int_arg_indexes.push(int_arg_index)
            stack_arg_indexes.push(-1)
          } else {
            int_arg_indexes.push(-1)
            stack_arg_index = mir_body_codegen_align_stack_slots(
              stack_arg_index,
              mir_body_codegen_abi_int_stack_align_slots(expected),
            )
            stack_arg_indexes.push(stack_arg_index)
            stack_arg_index += slots
          }
          fp_arg_indexes.push(-1)
          int_arg_index += slots
          arg_raw_sizes.push(16)
          self.gen_mir_value(arg, offsets, frame_size)
          self.emit_numeric_conversion(arg.ty(), expected)
          self.emit_scalar_conversion_to(expected)
          if mir_body_codegen_int128_type(expected) {
            self.emit("\tstp\tx9, x10, [sp, #-16]!")
          } else {
            self.emit("\tstr\tx9, [sp, #-16]!")
          }
        }
      }
      let mut raw_args_area = 0
      for raw_size in arg_raw_sizes {
        raw_args_area += raw_size
      }
      let raw_area = raw_args_area + 16
      let stack_area = (stack_arg_index * 8 + 15) / 16 * 16
      if stack_area > 0 {
        self.emit("\tsub\tsp, sp, #" + stack_area.to_string())
      }
      let mut raw_offset_cursor = stack_area + raw_args_area
      for i in 0..<args.length() {
        raw_offset_cursor -= arg_raw_sizes[i]
        let raw_offset = raw_offset_cursor
        if arg_is_hfa[i] {
          if fp_arg_indexes[i] >= 0 {
            self.emit_load_hfa_aggregate_arg_from_raw(
              expected_types[i],
              raw_offset,
              fp_arg_indexes[i],
            )
          } else {
            self.emit_copy_darwin_aggregate_arg_from_raw_to_stack(
              expected_types[i],
              raw_offset,
              stack_arg_indexes[i] * 8,
            )
          }
        } else if arg_is_register_aggregate[i] {
          if int_arg_indexes[i] >= 0 {
            for j in 0..<arg_slot_counts[i] {
              self.emit(
                "\tldr\tx" +
                (int_arg_indexes[i] + j).to_string() +
                ", [sp, #" +
                (raw_offset + j * 8).to_string() +
                "]",
              )
            }
          } else {
            self.emit_copy_darwin_aggregate_arg_from_raw_to_stack(
              expected_types[i],
              raw_offset,
              stack_arg_indexes[i] * 8,
            )
          }
        } else if arg_is_indirect_aggregate[i] {
          self.emit_pass_darwin_indirect_aggregate_arg_from_raw(
            raw_offset,
            int_arg_indexes[i],
            stack_arg_indexes[i],
          )
        } else if mir_body_codegen_abi_fp_type(expected_types[i]) {
          self.emit("\tldr\tx9, [sp, #" + raw_offset.to_string() + "]")
          if fp_arg_indexes[i] >= 0 {
            self.emit_mir_fp_arg_from_x9(expected_types[i], fp_arg_indexes[i])
          } else {
            self.emit(
              "\tstr\tx9, [sp, #" + (stack_arg_indexes[i] * 8).to_string() + "]",
            )
          }
        } else if int_arg_indexes[i] >= 0 {
          if mir_body_codegen_int128_type(expected_types[i]) {
            self.emit(
              "\tldr\tx" +
              int_arg_indexes[i].to_string() +
              ", [sp, #" +
              raw_offset.to_string() +
              "]",
            )
            self.emit(
              "\tldr\tx" +
              (int_arg_indexes[i] + 1).to_string() +
              ", [sp, #" +
              (raw_offset + 8).to_string() +
              "]",
            )
          } else {
            self.emit(
              "\tldr\tx" +
              int_arg_indexes[i].to_string() +
              ", [sp, #" +
              raw_offset.to_string() +
              "]",
            )
          }
        } else if mir_body_codegen_int128_type(expected_types[i]) {
          self.emit("\tldr\tx9, [sp, #" + raw_offset.to_string() + "]")
          self.emit("\tldr\tx10, [sp, #" + (raw_offset + 8).to_string() + "]")
          self.emit(
            "\tstr\tx9, [sp, #" + (stack_arg_indexes[i] * 8).to_string() + "]",
          )
          self.emit(
            "\tstr\tx10, [sp, #" +
            ((stack_arg_indexes[i] + 1) * 8).to_string() +
            "]",
          )
        } else {
          self.emit("\tldr\tx9, [sp, #" + raw_offset.to_string() + "]")
          self.emit(
            "\tstr\tx9, [sp, #" + (stack_arg_indexes[i] * 8).to_string() + "]",
          )
        }
      }
      self.emit(
        "\tldr\tx15, [sp, #" + (stack_area + raw_args_area).to_string() + "]",
      )
      self.emit_call_sret_addr(ty, frame_size)
      self.emit("\tblr\tx15")
      if raw_area + stack_area > 0 {
        self.emit("\tadd\tsp, sp, #" + (raw_area + stack_area).to_string())
      }
      if self.is_memory_aggregate(ty) {
        self.emit_sret_result_addr(ty, frame_size)
      } else if self.is_hfa_aggregate(ty) {
        ()
      } else if mir_body_codegen_abi_fp_type(ty) {
        self.emit_mir_fp_return_to_x9(ty)
      } else if mir_body_codegen_int128_type(ty) {
        self.emit("\tmov\tx9, x0")
        self.emit("\tmov\tx10, x1")
      } else {
        self.emit("\tmov\tx9, x0")
        self.emit_mir_abi_int_return_conversion(ty)
      }
    }
  }
}

///|
fn Codegen::emit_mir_cond_jump_false(
  self : Codegen,
  cond : @mir.MirValue,
  offsets : Map[Int, Int],
  frame_size : Int,
  false_label : String,
) -> Unit {
  self.gen_mir_value(cond, offsets, frame_size)
  if mir_body_codegen_floating_type(cond.ty()) {
    let reg = mir_body_codegen_arm_fp_reg(cond.ty(), 9)
    self.emit(
      "\tfmov\t" +
      reg +
      ", " +
      mir_body_codegen_arm_fp_bits_reg(cond.ty(), "x9"),
    )
    self.emit("\tfcmp\t" + reg + ", #0.0")
    self.emit("\tb.eq\t" + false_label)
  } else if mir_body_codegen_int128_type(cond.ty()) {
    self.emit("\torr\tx9, x9, x10")
    self.emit("\tcbz\tx9, " + false_label)
  } else {
    self.emit("\tcbz\tx9, " + false_label)
  }
}

///|
fn Codegen::emit_mir_fp_binary_from_x10_x9(
  self : Codegen,
  op : String,
  fp_ty : @ctype.Type,
) -> Unit {
  self.emit(
    "\tfmov\t" +
    mir_body_codegen_arm_fp_reg(fp_ty, 9) +
    ", " +
    mir_body_codegen_arm_fp_bits_reg(fp_ty, "x10"),
  )
  self.emit(
    "\tfmov\t" +
    mir_body_codegen_arm_fp_reg(fp_ty, 10) +
    ", " +
    mir_body_codegen_arm_fp_bits_reg(fp_ty, "x9"),
  )
  let lhs_reg = mir_body_codegen_arm_fp_reg(fp_ty, 9)
  let rhs_reg = mir_body_codegen_arm_fp_reg(fp_ty, 10)
  match op {
    "+" => self.emit("\tfadd\t" + lhs_reg + ", " + lhs_reg + ", " + rhs_reg)
    "-" => self.emit("\tfsub\t" + lhs_reg + ", " + lhs_reg + ", " + rhs_reg)
    "*" => self.emit("\tfmul\t" + lhs_reg + ", " + lhs_reg + ", " + rhs_reg)
    "/" => self.emit("\tfdiv\t" + lhs_reg + ", " + lhs_reg + ", " + rhs_reg)
    _ => abort("unsupported MIR body floating arithmetic operator")
  }
  self.emit(
    "\tfmov\t" +
    mir_body_codegen_arm_fp_bits_reg(fp_ty, "x9") +
    ", " +
    mir_body_codegen_arm_fp_reg(fp_ty, 9),
  )
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
    if params.length() == 0 && !self.mir_direct_call_variadic(name) {
      return mir_body_default_argument_promoted_type(actual)
    }
  }
  if self.mir_direct_call_variadic(name) {
    return mir_body_default_argument_promoted_type(actual)
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
fn Codegen::emit_store_frame_offset(
  self : Codegen,
  src_reg : String,
  off : Int,
) -> Unit {
  if off >= -256 && off <= 255 {
    self.emit("\tstr\t" + src_reg + ", [x29, #" + off.to_string() + "]")
  } else {
    self.emit("\tmov\tx12, #" + off.to_string())
    self.emit("\tstr\t" + src_reg + ", [x29, x12]")
  }
}

///|
fn Codegen::emit_store_mir_local_scalar(
  self : Codegen,
  src_reg : String,
  offset : Int,
  frame_size : Int,
  ty : @ctype.Type,
) -> Unit {
  match peel_aligned_type(ty) {
    SInt128 | UInt128 => {
      let off = offset - frame_size
      self.emit_store_frame_offset(src_reg, off)
      self.emit_store_frame_offset(paired_high_reg(src_reg), off + 8)
    }
    _ => self.emit_store_local(src_reg, offset, frame_size)
  }
}

///|
fn Codegen::emit_arm_int128_compare(
  self : Codegen,
  op : String,
  unsigned : Bool,
) -> Unit {
  let high_diff = self.new_label()
  let done = self.new_label()
  self.emit("\tcmp\tx12, x10")
  self.emit("\tb.ne\t" + high_diff)
  self.emit("\tcmp\tx11, x9")
  let low_cc = match op {
    "==" => "eq"
    "!=" => "ne"
    "<" => "lo"
    ">" => "hi"
    "<=" => "ls"
    _ => "hs"
  }
  self.emit("\tcset\tx9, " + low_cc)
  self.emit("\tb\t" + done)
  self.emit(high_diff + ":")
  match op {
    "==" => self.emit("\tmov\tx9, #0")
    "!=" => self.emit("\tmov\tx9, #1")
    _ => {
      let high_cc = match op {
        "<" | "<=" => if unsigned { "lo" } else { "lt" }
        _ => if unsigned { "hi" } else { "gt" }
      }
      self.emit("\tcset\tx9, " + high_cc)
    }
  }
  self.emit(done + ":")
}

///|
fn Codegen::emit_arm_int128_left_shift(self : Codegen) -> Unit {
  let wide = self.new_label()
  let done = self.new_label()
  self.emit("\tand\tx13, x9, #127")
  self.emit("\tmov\tx9, x11")
  self.emit("\tmov\tx10, x12")
  self.emit("\tcmp\tx13, #0")
  self.emit("\tb.eq\t" + done)
  self.emit("\tcmp\tx13, #64")
  self.emit("\tb.hs\t" + wide)
  self.emit("\tlsl\tx10, x12, x13")
  self.emit("\tneg\tx14, x13")
  self.emit("\tand\tx14, x14, #63")
  self.emit("\tlsr\tx15, x11, x14")
  self.emit("\torr\tx10, x10, x15")
  self.emit("\tlsl\tx9, x11, x13")
  self.emit("\tb\t" + done)
  self.emit(wide + ":")
  self.emit("\tsub\tx13, x13, #64")
  self.emit("\tlsl\tx10, x11, x13")
  self.emit("\tmov\tx9, #0")
  self.emit(done + ":")
}

///|
fn Codegen::emit_arm_int128_right_shift(
  self : Codegen,
  unsigned : Bool,
) -> Unit {
  let wide = self.new_label()
  let done = self.new_label()
  self.emit("\tand\tx13, x9, #127")
  self.emit("\tmov\tx9, x11")
  self.emit("\tmov\tx10, x12")
  self.emit("\tcmp\tx13, #0")
  self.emit("\tb.eq\t" + done)
  self.emit("\tcmp\tx13, #64")
  self.emit("\tb.hs\t" + wide)
  self.emit("\tneg\tx14, x13")
  self.emit("\tand\tx14, x14, #63")
  self.emit("\tlsl\tx15, x12, x14")
  self.emit("\tlsr\tx9, x11, x13")
  self.emit("\torr\tx9, x9, x15")
  if unsigned {
    self.emit("\tlsr\tx10, x12, x13")
  } else {
    self.emit("\tasr\tx10, x12, x13")
  }
  self.emit("\tb\t" + done)
  self.emit(wide + ":")
  self.emit("\tsub\tx13, x13, #64")
  if unsigned {
    self.emit("\tlsr\tx9, x12, x13")
    self.emit("\tmov\tx10, #0")
  } else {
    self.emit("\tasr\tx9, x12, x13")
    self.emit("\tasr\tx10, x12, #63")
  }
  self.emit(done + ":")
}

///|
fn Codegen::emit_arm_int128_libcall(self : Codegen, name : String) -> Unit {
  self.emit("\tmov\tx0, x11")
  self.emit("\tmov\tx1, x12")
  self.emit("\tmov\tx2, x9")
  self.emit("\tmov\tx3, x10")
  self.emit("\tbl\t" + name)
  self.emit("\tmov\tx9, x0")
  self.emit("\tmov\tx10, x1")
}

///|
fn Codegen::gen_mir_int128_binary(
  self : Codegen,
  op : String,
  lhs : @mir.MirValue,
  rhs : @mir.MirValue,
  ty : @ctype.Type,
  offsets : Map[Int, Int],
  frame_size : Int,
) -> Unit {
  let left_ty = mir_body_binary_left_type(op, lhs.ty(), rhs.ty())
  let right_ty = mir_body_binary_right_type(op, lhs.ty(), rhs.ty())
  self.gen_mir_value(lhs, offsets, frame_size)
  self.emit_numeric_conversion(lhs.ty(), left_ty)
  self.emit_scalar_conversion_to(left_ty)
  self.emit("\tstp\tx9, x10, [sp, #-16]!")
  self.gen_mir_value(rhs, offsets, frame_size)
  self.emit_numeric_conversion(rhs.ty(), right_ty)
  self.emit_scalar_conversion_to(right_ty)
  self.emit("\tldp\tx11, x12, [sp], #16")
  match op {
    "+" => {
      self.emit("\tadds\tx9, x11, x9")
      self.emit("\tadc\tx10, x12, x10")
    }
    "-" => {
      self.emit("\tsubs\tx9, x11, x9")
      self.emit("\tsbc\tx10, x12, x10")
    }
    "*" => {
      self.emit("\tumulh\tx13, x11, x9")
      self.emit("\tmul\tx14, x12, x9")
      self.emit("\tadd\tx13, x13, x14")
      self.emit("\tmul\tx14, x11, x10")
      self.emit("\tadd\tx10, x13, x14")
      self.emit("\tmul\tx9, x11, x9")
    }
    "/" =>
      self.emit_arm_int128_libcall(
        if mir_body_unsigned_binary(op, lhs.ty(), rhs.ty()) {
          "___udivti3"
        } else {
          "___divti3"
        },
      )
    "%" =>
      self.emit_arm_int128_libcall(
        if mir_body_unsigned_binary(op, lhs.ty(), rhs.ty()) {
          "___umodti3"
        } else {
          "___modti3"
        },
      )
    "&" => {
      self.emit("\tand\tx9, x11, x9")
      self.emit("\tand\tx10, x12, x10")
    }
    "|" => {
      self.emit("\torr\tx9, x11, x9")
      self.emit("\torr\tx10, x12, x10")
    }
    "^" => {
      self.emit("\teor\tx9, x11, x9")
      self.emit("\teor\tx10, x12, x10")
    }
    "<<" => self.emit_arm_int128_left_shift()
    ">>" => self.emit_arm_int128_right_shift(is_unsigned_integer_type(left_ty))
    "==" | "!=" | "<" | ">" | "<=" | ">=" =>
      self.emit_arm_int128_compare(
        op,
        mir_body_unsigned_binary(op, lhs.ty(), rhs.ty()),
      )
    _ => abort("unsupported MIR body int128 binary operator")
  }
  self.emit_scalar_conversion_to(ty)
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
    "alloca_align" => {
      self.gen_mir_value(lhs, offsets, frame_size)
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.gen_mir_value(rhs, offsets, frame_size)
      self.emit("\tmov\tx11, x9")
      self.emit("\tldr\tx10, [sp], #16")
      self.emit("\tlsr\tx11, x11, #3")
      self.emit("\tmov\tx12, #16")
      self.emit("\tcmp\tx11, #16")
      self.emit("\tcsel\tx11, x11, x12, hs")
      self.emit("\tadd\tx9, x10, #15")
      self.emit("\tbic\tx9, x9, #0xF")
      self.emit("\tsub\tsp, sp, x9")
      self.emit("\tsub\tx11, x11, #1")
      self.emit("\tmov\tx9, sp")
      self.emit("\tbic\tx9, x9, x11")
      self.emit("\tmov\tsp, x9")
      return
    }
    "&&" => {
      let false_label = self.new_label()
      let end_label = self.new_label()
      self.emit_mir_cond_jump_false(lhs, offsets, frame_size, false_label)
      self.emit_mir_cond_jump_false(rhs, offsets, frame_size, false_label)
      self.emit("\tmov\tx9, #1")
      self.emit("\tb\t" + end_label)
      self.emit(false_label + ":")
      self.emit("\tmov\tx9, #0")
      self.emit(end_label + ":")
      return
    }
    "||" => {
      let rhs_label = self.new_label()
      let end_label = self.new_label()
      let false_label = self.new_label()
      self.emit_mir_cond_jump_false(lhs, offsets, frame_size, rhs_label)
      self.emit("\tmov\tx9, #1")
      self.emit("\tb\t" + end_label)
      self.emit(rhs_label + ":")
      self.emit_mir_cond_jump_false(rhs, offsets, frame_size, false_label)
      self.emit("\tmov\tx9, #1")
      self.emit("\tb\t" + end_label)
      self.emit(false_label + ":")
      self.emit("\tmov\tx9, #0")
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
        let scale = self.mir_pointer_element_scale(elem_ty)
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
            let scale = self.mir_pointer_element_scale(elem_ty)
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
  if mir_body_codegen_rotate_op_supported(op, lhs.ty(), rhs.ty(), ty) {
    self.emit_mir_rotate_op(op, lhs, rhs, ty, offsets, frame_size)
    return
  }
  let left_ty = mir_body_binary_left_type(op, lhs.ty(), rhs.ty())
  let right_ty = mir_body_binary_right_type(op, lhs.ty(), rhs.ty())
  if mir_body_codegen_fp_compare_supported(op, lhs.ty(), rhs.ty(), ty) {
    let fp_ty = mir_body_codegen_fp_binary_type(lhs.ty(), rhs.ty(), ty)
    self.gen_mir_value(lhs, offsets, frame_size)
    self.emit_numeric_conversion(lhs.ty(), fp_ty)
    self.emit("\tstr\tx9, [sp, #-16]!")
    self.gen_mir_value(rhs, offsets, frame_size)
    self.emit_numeric_conversion(rhs.ty(), fp_ty)
    self.emit("\tldr\tx10, [sp], #16")
    self.emit(
      "\tfmov\t" +
      mir_body_codegen_arm_fp_reg(fp_ty, 9) +
      ", " +
      mir_body_codegen_arm_fp_bits_reg(fp_ty, "x10"),
    )
    self.emit(
      "\tfmov\t" +
      mir_body_codegen_arm_fp_reg(fp_ty, 10) +
      ", " +
      mir_body_codegen_arm_fp_bits_reg(fp_ty, "x9"),
    )
    self.emit(
      "\tfcmp\t" +
      mir_body_codegen_arm_fp_reg(fp_ty, 9) +
      ", " +
      mir_body_codegen_arm_fp_reg(fp_ty, 10),
    )
    if op == "<>" {
      self.emit("\tcset\tx9, ne")
      self.emit("\tcset\tx10, vc")
      self.emit("\tand\tx9, x9, x10")
      self.emit_scalar_conversion_to(ty)
      return
    }
    let cc = match op {
      "==" => "eq"
      "!=" => "ne"
      "<" => "mi"
      ">" => "gt"
      "<=" => "ls"
      ">=" => "ge"
      _ => "vs"
    }
    self.emit("\tcset\tx9, " + cc)
    self.emit_scalar_conversion_to(ty)
    return
  }
  if mir_body_codegen_fp_copysign_supported(op, lhs.ty(), rhs.ty(), ty) {
    let fp_ty = mir_body_codegen_fp_binary_type(lhs.ty(), rhs.ty(), ty)
    self.gen_mir_value(lhs, offsets, frame_size)
    self.emit_numeric_conversion(lhs.ty(), fp_ty)
    match peel_aligned_type(fp_ty) {
      Float => {
        self.emit("\tlsl\tw9, w9, #1")
        self.emit("\tlsr\tw9, w9, #1")
      }
      _ => {
        self.emit("\tlsl\tx9, x9, #1")
        self.emit("\tlsr\tx9, x9, #1")
      }
    }
    self.emit("\tstr\tx9, [sp, #-16]!")
    self.gen_mir_value(rhs, offsets, frame_size)
    self.emit_numeric_conversion(rhs.ty(), fp_ty)
    match peel_aligned_type(fp_ty) {
      Float => {
        self.emit("\tlsr\tw9, w9, #31")
        self.emit("\tlsl\tw9, w9, #31")
        self.emit("\tldr\tx10, [sp], #16")
        self.emit("\torr\tw9, w9, w10")
      }
      _ => {
        self.emit("\tlsr\tx9, x9, #63")
        self.emit("\tlsl\tx9, x9, #63")
        self.emit("\tldr\tx10, [sp], #16")
        self.emit("\torr\tx9, x9, x10")
      }
    }
    self.emit_numeric_conversion(fp_ty, ty)
    self.emit_scalar_conversion_to(ty)
    return
  }
  if mir_body_codegen_fp_arith_supported(op, lhs.ty(), rhs.ty(), ty) {
    let fp_ty = mir_body_codegen_fp_binary_type(lhs.ty(), rhs.ty(), ty)
    self.gen_mir_value(lhs, offsets, frame_size)
    self.emit_numeric_conversion(lhs.ty(), fp_ty)
    self.emit("\tstr\tx9, [sp, #-16]!")
    self.gen_mir_value(rhs, offsets, frame_size)
    self.emit_numeric_conversion(rhs.ty(), fp_ty)
    self.emit("\tldr\tx10, [sp], #16")
    self.emit(
      "\tfmov\t" +
      mir_body_codegen_arm_fp_reg(fp_ty, 9) +
      ", " +
      mir_body_codegen_arm_fp_bits_reg(fp_ty, "x10"),
    )
    self.emit(
      "\tfmov\t" +
      mir_body_codegen_arm_fp_reg(fp_ty, 10) +
      ", " +
      mir_body_codegen_arm_fp_bits_reg(fp_ty, "x9"),
    )
    let lhs_reg = mir_body_codegen_arm_fp_reg(fp_ty, 9)
    let rhs_reg = mir_body_codegen_arm_fp_reg(fp_ty, 10)
    match op {
      "+" => self.emit("\tfadd\t" + lhs_reg + ", " + lhs_reg + ", " + rhs_reg)
      "-" => self.emit("\tfsub\t" + lhs_reg + ", " + lhs_reg + ", " + rhs_reg)
      "*" => self.emit("\tfmul\t" + lhs_reg + ", " + lhs_reg + ", " + rhs_reg)
      "/" => self.emit("\tfdiv\t" + lhs_reg + ", " + lhs_reg + ", " + rhs_reg)
      _ => abort("unsupported MIR body floating arithmetic operator")
    }
    self.emit(
      "\tfmov\t" +
      mir_body_codegen_arm_fp_bits_reg(fp_ty, "x9") +
      ", " +
      mir_body_codegen_arm_fp_reg(fp_ty, 9),
    )
    self.emit_numeric_conversion(fp_ty, ty)
    self.emit_scalar_conversion_to(ty)
    return
  }
  if mir_body_codegen_int128_type(left_ty) ||
    mir_body_codegen_int128_type(right_ty) ||
    mir_body_codegen_int128_type(ty) {
    self.gen_mir_int128_binary(op, lhs, rhs, ty, offsets, frame_size)
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
      let unsigned = mir_body_unsigned_compare_binary(op, lhs.ty(), rhs.ty())
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
          Some(value) =>
            if self.is_hfa_aggregate(binding.ty) {
              match value {
                MirCall(_, _, _) | MirIndirectCall(_, _, _) =>
                  self.gen_mir_value(value, offsets, frame_size)
                _ => {
                  self.gen_mir_aggregate_return_addr(value, offsets, frame_size)
                  self.emit_load_hfa_aggregate_return_from_x9(binding.ty)
                }
              }
              self.emit_local_addr(offsets[binding.id], frame_size)
              self.emit_store_hfa_aggregate_return_to_x9(binding.ty)
            } else if self.is_register_aggregate(binding.ty) {
              match value {
                MirCall(_, _, _) | MirIndirectCall(_, _, _) =>
                  self.gen_mir_value(value, offsets, frame_size)
                _ => {
                  self.gen_mir_aggregate_return_addr(value, offsets, frame_size)
                  self.emit_load_register_aggregate_return_from_x9(binding.ty)
                }
              }
              self.emit_local_addr(offsets[binding.id], frame_size)
              self.emit_store_register_aggregate_return_to_x9(binding.ty)
            } else if self.is_memory_aggregate(binding.ty) {
              match value {
                MirCall(_, _, _) | MirIndirectCall(_, _, _) => {
                  let saved_pending = self.pending_sret_offset
                  self.pending_sret_offset = offsets[binding.id]
                  self.gen_mir_value(value, offsets, frame_size)
                  self.pending_sret_offset = saved_pending
                }
                _ => {
                  self.gen_mir_aggregate_return_addr(value, offsets, frame_size)
                  self.emit("\tmov\tx11, x9")
                  self.emit_local_addr(offsets[binding.id], frame_size)
                  self.emit("\tmov\tx10, x9")
                  self.emit_copy_memory_aggregate_from_x11_to_x10(binding.ty)
                }
              }
            } else {
              self.gen_mir_value(value, offsets, frame_size)
              self.emit_numeric_conversion(value.ty(), binding.ty)
              self.emit_scalar_conversion_to(binding.ty)
              self.emit_store_mir_local_scalar(
                "x9",
                offsets[binding.id],
                frame_size,
                binding.ty,
              )
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
          let ret_ty = self.func_rets[self.func_name]
          if self.is_hfa_aggregate(ret_ty) {
            match value {
              MirCall(_, _, _) | MirIndirectCall(_, _, _) =>
                self.gen_mir_value(value, offsets, frame_size)
              _ => {
                self.gen_mir_aggregate_return_addr(value, offsets, frame_size)
                self.emit_load_hfa_aggregate_return_from_x9(ret_ty)
              }
            }
          } else if self.is_register_aggregate(ret_ty) {
            match value {
              MirCall(_, _, _) | MirIndirectCall(_, _, _) =>
                self.gen_mir_value(value, offsets, frame_size)
              _ => {
                self.gen_mir_aggregate_return_addr(value, offsets, frame_size)
                self.emit_load_register_aggregate_return_from_x9(ret_ty)
              }
            }
          } else if self.is_memory_aggregate(ret_ty) {
            self.gen_mir_aggregate_return_addr(value, offsets, frame_size)
            self.emit("\tmov\tx11, x9")
            self.emit_sret_dest_addr(frame_size)
            self.emit("\tmov\tx10, x9")
            self.emit_copy_memory_aggregate_from_x11_to_x10(ret_ty)
            self.emit("\tmov\tx0, x10")
          } else {
            self.gen_mir_value(value, offsets, frame_size)
            self.emit_numeric_conversion(value.ty(), ret_ty)
            self.emit_scalar_conversion_to(ret_ty)
            if mir_body_codegen_abi_fp_type(ret_ty) {
              self.emit_mir_fp_return_from_x9(ret_ty)
            } else if mir_body_codegen_int128_type(ret_ty) {
              self.emit("\tmov\tx0, x9")
              self.emit("\tmov\tx1, x10")
            } else {
              self.emit("\tmov\tx0, x9")
            }
          }
        }
        None => self.emit("\tmov\tx0, #0")
      }
      self.emit("\tb\t_" + self.func_name + "_ret")
    }
    MirIf(cond, then_, else_) => {
      let else_label = self.new_label()
      let end_label = self.new_label()
      self.emit_mir_cond_jump_false(cond, offsets, frame_size, else_label)
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
      self.emit_mir_cond_jump_false(cond, offsets, frame_size, end_label)
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
      self.emit_mir_cond_jump_false(cond, offsets, frame_size, end_label)
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
      if mir_body_codegen_floating_type(cond.ty()) {
        self.emit_mir_cond_jump_false(cond, offsets, frame_size, end_label)
        self.emit("\tb\t" + start_label)
      } else {
        self.gen_mir_value(cond, offsets, frame_size)
        self.emit("\tcbnz\tx9, " + start_label)
      }
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
    MirComputedGoto(value) => {
      self.gen_mir_value(value, offsets, frame_size)
      self.emit("\tbr\tx9")
    }
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
  self.func_name = decl.name
  self.sret_dest_offset = -1
  self.sret_scratch_offset = -1
  self.sret_scratch_size = 0
  self.sret_scratch_align = 1
  self.pending_sret_offset = -1
  self.break_label = None
  self.continue_label = None
  let offsets = self.mir_body_offsets(body)
  let has_sret = self.is_memory_aggregate(decl.ret)
  if has_sret {
    self.sret_dest_offset = self.alloc_local(
      "__kimicc_mir_sret_dest",
      Pointer(Void),
    )
  }
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
  if self.sret_dest_offset >= 0 {
    self.emit_store_local("x8", self.sret_dest_offset, frame_size)
  }
  let mut int_arg_index = 0
  let mut fp_arg_index = 0
  let mut stack_arg_index = 0
  for i in 0..<body.params.length() {
    let param = body.params[i]
    if mir_body_codegen_abi_fp_type(param.ty) {
      if fp_arg_index < 8 {
        self.emit_store_local(
          mir_body_codegen_arm_fp_reg(param.ty, fp_arg_index),
          offsets[param.id],
          frame_size,
        )
      } else {
        self.emit(
          "\tldr\tx9, [x29, #" + (16 + stack_arg_index * 8).to_string() + "]",
        )
        self.emit_store_local("x9", offsets[param.id], frame_size)
        stack_arg_index += 1
      }
      fp_arg_index += 1
    } else if self.is_hfa_aggregate(param.ty) {
      let hfa_count = match self.darwin_hfa_parts(param.ty) {
        Some((_, count)) => count
        None => abort("unsupported Darwin ARM64 MIR HFA parameter")
      }
      if fp_arg_index + hfa_count <= 8 {
        self.emit_store_hfa_aggregate_param_from_regs(
          param.ty,
          offsets[param.id],
          fp_arg_index,
          frame_size,
        )
      } else {
        self.emit_store_darwin_aggregate_param_from_stack(
          param.ty,
          offsets[param.id],
          stack_arg_index * 8,
          frame_size,
        )
        stack_arg_index += (self.type_size(param.ty) + 7) / 8
      }
      fp_arg_index += hfa_count
    } else if self.is_register_aggregate(param.ty) {
      let slots = (self.type_size(param.ty) + 7) / 8
      if int_arg_index + slots <= 8 {
        self.emit_store_register_aggregate_param_from_regs(
          param.ty,
          offsets[param.id],
          int_arg_index,
          frame_size,
        )
      } else {
        self.emit_store_darwin_aggregate_param_from_stack(
          param.ty,
          offsets[param.id],
          stack_arg_index * 8,
          frame_size,
        )
        stack_arg_index += slots
      }
      int_arg_index += slots
    } else if self.is_memory_aggregate(param.ty) {
      if int_arg_index < 8 {
        self.emit_store_darwin_indirect_aggregate_param(
          param.ty,
          offsets[param.id],
          "x" + int_arg_index.to_string(),
          frame_size,
        )
      } else {
        self.emit(
          "\tldr\tx11, [x29, #" + (16 + stack_arg_index * 8).to_string() + "]",
        )
        self.emit_store_darwin_indirect_aggregate_param(
          param.ty,
          offsets[param.id],
          "x11",
          frame_size,
        )
        stack_arg_index += 1
      }
      int_arg_index += 1
    } else if mir_body_codegen_int128_type(param.ty) {
      if int_arg_index + 2 <= 8 {
        self.emit_store_mir_local_scalar(
          "x" + int_arg_index.to_string(),
          offsets[param.id],
          frame_size,
          param.ty,
        )
      } else {
        stack_arg_index = mir_body_codegen_align_stack_slots(stack_arg_index, 2)
        self.emit(
          "\tldr\tx9, [x29, #" + (16 + stack_arg_index * 8).to_string() + "]",
        )
        self.emit(
          "\tldr\tx10, [x29, #" +
          (16 + (stack_arg_index + 1) * 8).to_string() +
          "]",
        )
        self.emit_store_mir_local_scalar(
          "x9",
          offsets[param.id],
          frame_size,
          param.ty,
        )
        stack_arg_index += 2
      }
      int_arg_index += 2
    } else {
      if int_arg_index < 8 {
        self.emit_store_local(
          "x" + int_arg_index.to_string(),
          offsets[param.id],
          frame_size,
        )
      } else {
        self.emit(
          "\tldr\tx9, [x29, #" + (16 + stack_arg_index * 8).to_string() + "]",
        )
        self.emit_store_local("x9", offsets[param.id], frame_size)
        stack_arg_index += 1
      }
      int_arg_index += 1
    }
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
  if x64_is_int128_type(src_core) && dst_core == Bool {
    self.emit_int128_to_bool()
    return
  }
  if x64_is_int128_type(dst_core) {
    if src_core.is_integer() {
      self.emit_int_conversion_to(src_core)
      self.emit_extend_rax_to_int128(src_core)
    }
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
      if dst_core.const_is_unsigned() && self.type_size(dst_core) == 8 {
        self.emit_mir_fp_to_unsigned64(src_core)
      } else if src_core == Float {
        self.emit("\tcvttss2si\trax, xmm0")
      } else {
        self.emit("\tcvttsd2si\trax, xmm0")
      }
      self.emit_int_conversion_to(dst_core)
    }
  } else if x64_is_fp_type(dst_core) {
    self.emit_int_conversion_to(src_core)
    if src_core.const_is_unsigned() && self.type_size(src_core) == 8 {
      self.emit_mir_unsigned64_to_fp(dst_core)
    } else if dst_core == Float {
      self.emit("\tcvtsi2ss\txmm0, rax")
    } else {
      self.emit("\tcvtsi2sd\txmm0, rax")
    }
  } else {
    self.emit_int_conversion_to(dst_core)
  }
}

///|
fn X64Codegen::emit_mir_unsigned64_to_fp(
  self : X64Codegen,
  dst : @ctype.Type,
) -> Unit {
  let high_label = self.new_label()
  let done_label = self.new_label()
  let suffix = x64_fp_suffix(dst)
  self.emit("\ttest\trax, rax")
  self.emit("\tjs\t" + high_label)
  self.emit("\tcvtsi2" + suffix + "\txmm0, rax")
  self.emit("\tjmp\t" + done_label)
  self.emit(high_label + ":")
  self.emit("\tmov\tr10, rax")
  self.emit("\tand\teax, 1")
  self.emit("\tshr\tr10, 1")
  self.emit("\tor\tr10, rax")
  self.emit("\tcvtsi2" + suffix + "\txmm0, r10")
  self.emit("\tadd" + suffix + "\txmm0, xmm0")
  self.emit(done_label + ":")
}

///|
fn X64Codegen::emit_mir_fp_to_unsigned64(
  self : X64Codegen,
  src : @ctype.Type,
) -> Unit {
  let low_label = self.new_label()
  let done_label = self.new_label()
  let suffix = x64_fp_suffix(src)
  if src == Float {
    self.emit("\tmov\teax, 1593835520")
    self.emit("\tmovd\txmm1, eax")
  } else {
    self.emit("\tmovabs\tr10, 4890909195324358656")
    self.emit("\tmovq\txmm1, r10")
  }
  self.emit("\tucomi" + suffix + "\txmm0, xmm1")
  self.emit("\tjb\t" + low_label)
  self.emit("\tsub" + suffix + "\txmm0, xmm1")
  if src == Float {
    self.emit("\tcvttss2si\trax, xmm0")
  } else {
    self.emit("\tcvttsd2si\trax, xmm0")
  }
  self.emit("\tmovabs\tr10, -9223372036854775808")
  self.emit("\tor\trax, r10")
  self.emit("\tjmp\t" + done_label)
  self.emit(low_label + ":")
  if src == Float {
    self.emit("\tcvttss2si\trax, xmm0")
  } else {
    self.emit("\tcvttsd2si\trax, xmm0")
  }
  self.emit(done_label + ":")
}

///|
fn X64Codegen::emit_mir_fp_abs_bits_in_rax(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Unit {
  match x64_core_type(ty) {
    Float => {
      self.emit("\tmovd\teax, xmm0")
      self.emit("\tand\teax, 2147483647")
    }
    _ => {
      self.emit("\tmovq\trax, xmm0")
      self.emit("\tmovabs\tr10, 9223372036854775807")
      self.emit("\tand\trax, r10")
    }
  }
}

///|
fn X64Codegen::emit_mir_fp_class_result(
  self : X64Codegen,
  op : String,
  ty : @ctype.Type,
) -> Unit {
  match op {
    "fp_isnan" => {
      self.emit("\tucomi" + x64_fp_suffix(ty) + "\txmm0, xmm0")
      self.emit_setcc("setp")
    }
    "fp_isinf" => {
      self.emit_mir_fp_abs_bits_in_rax(ty)
      match x64_core_type(ty) {
        Float => self.emit("\tcmp\teax, 2139095040")
        _ => {
          self.emit("\tmovabs\tr10, 9218868437227405312")
          self.emit("\tcmp\trax, r10")
        }
      }
      self.emit_setcc("sete")
    }
    "fp_isfinite" => {
      self.emit_mir_fp_abs_bits_in_rax(ty)
      match x64_core_type(ty) {
        Float => self.emit("\tcmp\teax, 2139095040")
        _ => {
          self.emit("\tmovabs\tr10, 9218868437227405312")
          self.emit("\tcmp\trax, r10")
        }
      }
      self.emit_setcc("setb")
    }
    "fp_isnormal" => {
      self.emit_mir_fp_abs_bits_in_rax(ty)
      match x64_core_type(ty) {
        Float => {
          self.emit("\tmov\tr10d, eax")
          self.emit("\tcmp\tr10d, 8388608")
          self.emit("\tsetae\tal")
          self.emit("\tcmp\tr10d, 2139095040")
          self.emit("\tsetb\tr11b")
        }
        _ => {
          self.emit("\tmov\tr10, rax")
          self.emit("\tmovabs\tr11, 4503599627370496")
          self.emit("\tcmp\tr10, r11")
          self.emit("\tsetae\tal")
          self.emit("\tmovabs\tr11, 9218868437227405312")
          self.emit("\tcmp\tr10, r11")
          self.emit("\tsetb\tr11b")
        }
      }
      self.emit("\tand\tal, r11b")
      self.emit("\tmovzx\trax, al")
    }
    "fp_signbit" =>
      match x64_core_type(ty) {
        Float => {
          self.emit("\tmovd\teax, xmm0")
          self.emit("\tshr\teax, 31")
        }
        _ => {
          self.emit("\tmovq\trax, xmm0")
          self.emit("\tshr\trax, 63")
        }
      }
    _ => self.emit("\tmov\trax, 0")
  }
}

///|
fn X64Codegen::emit_mir_push_rax(self : X64Codegen) -> Unit {
  self.emit("\tsub\trsp, 16")
  self.emit("\tmov\tQWORD PTR [rsp], rax")
}

///|
fn X64Codegen::emit_mir_push_xmm0(self : X64Codegen, ty : @ctype.Type) -> Unit {
  let suffix = x64_fp_suffix(ty)
  self.emit("\tsub\trsp, 16")
  let size = if suffix == "ss" { "DWORD" } else { "QWORD" }
  self.emit("\tmov" + suffix + "\t" + size + " PTR [rsp], xmm0")
}

///|
fn X64Codegen::emit_mir_pop_xmm0(self : X64Codegen, ty : @ctype.Type) -> Unit {
  let suffix = x64_fp_suffix(ty)
  let size = if suffix == "ss" { "DWORD" } else { "QWORD" }
  self.emit("\tmov" + suffix + "\txmm0, " + size + " PTR [rsp]")
  self.emit("\tadd\trsp, 16")
}

///|
fn X64Codegen::emit_mir_spill_scalar(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Unit {
  if x64_is_fp_type(ty) {
    self.emit_mir_push_xmm0(ty)
  } else if x64_is_int128_type(ty) {
    self.emit_push_int128()
  } else {
    self.emit_mir_push_rax()
  }
}

///|
fn mir_body_codegen_raw_arg_offset(
  raw_sizes : Array[Int],
  index : Int,
  stack_area : Int,
) -> Int {
  let mut offset = stack_area
  let start = index + 1
  for i in start..<raw_sizes.length() {
    offset += raw_sizes[i]
  }
  offset
}

///|
fn X64Codegen::emit_mir_copy_int128_arg_from_raw_to_stack(
  self : X64Codegen,
  raw_offset : Int,
  stack_offset : Int,
) -> Unit {
  self.emit("\tmov\trax, QWORD PTR " + x64_rsp_ref(raw_offset))
  self.emit("\tmov\tQWORD PTR " + x64_rsp_ref(stack_offset) + ", rax")
  self.emit("\tmov\trax, QWORD PTR " + x64_rsp_ref(raw_offset + 8))
  self.emit("\tmov\tQWORD PTR " + x64_rsp_ref(stack_offset + 8) + ", rax")
}

///|
fn X64Codegen::emit_mir_load_int128_arg_from_raw_to_regs(
  self : X64Codegen,
  arg_regs : Array[String],
  start_index : Int,
  raw_offset : Int,
) -> Unit {
  self.emit(
    "\tmov\t" + arg_regs[start_index] + ", QWORD PTR " + x64_rsp_ref(raw_offset),
  )
  self.emit(
    "\tmov\t" +
    arg_regs[start_index + 1] +
    ", QWORD PTR " +
    x64_rsp_ref(raw_offset + 8),
  )
}

///|
fn X64Codegen::emit_mir_save_aggregate_call_arg_raw(
  self : X64Codegen,
  arg : @mir.MirValue,
  ty : @ctype.Type,
  raw_size : Int,
  offsets : Map[Int, Int],
) -> Unit {
  match arg {
    MirCall(_, _, _) | MirIndirectCall(_, _, _) =>
      if self.is_supported_small_aggregate(ty) {
        self.gen_mir_value(arg, offsets)
        self.emit("\tsub\trsp, " + raw_size.to_string())
        self.emit("\tmov\tr10, rsp")
        self.emit_store_small_aggregate_return(ty)
      } else if self.is_memory_aggregate(ty) {
        self.gen_mir_value(arg, offsets)
        self.emit("\tsub\trsp, " + raw_size.to_string())
        self.emit("\tmov\tr11, rax")
        self.emit("\tmov\tr10, rsp")
        self.emit_copy_aggregate_from_addr(ty)
      } else {
        abort("unsupported x86-64 MIR aggregate call argument")
      }
    _ => {
      self.gen_mir_value(arg, offsets)
      self.emit("\tsub\trsp, " + raw_size.to_string())
      self.emit("\tmov\tr11, rax")
      self.emit("\tmov\tr10, rsp")
      self.emit_copy_aggregate_from_addr(ty)
    }
  }
}

///|
fn X64Codegen::emit_mir_store_aggregate_param_from_regs(
  self : X64Codegen,
  ty : @ctype.Type,
  local_offset : Int,
  classes : Array[X64AggregateClass],
  int_start : Int,
  fp_start : Int,
) -> Unit {
  let arg_regs : ReadOnlyArray[String] = [
    "rdi", "rsi", "rdx", "rcx", "r8", "r9",
  ]
  let fp_arg_regs : ReadOnlyArray[String] = [
    "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7",
  ]
  self.emit_local_addr(local_offset)
  self.emit("\tmov\tr10, rax")
  let mut int_cursor = int_start
  let mut fp_cursor = fp_start
  for word in 0..<classes.length() {
    let width = self.aggregate_word_width(ty, word)
    match classes[word] {
      IntClass => {
        self.emit_store_int_bytes_to_mem_reg(
          arg_regs[int_cursor],
          "r10",
          word * 8,
          width,
        )
        int_cursor += 1
      }
      SseClass => {
        self.emit_store_sse_word_to_mem_reg(
          fp_arg_regs[fp_cursor],
          "r10",
          word * 8,
          width,
        )
        fp_cursor += 1
      }
    }
  }
}

///|
fn X64Codegen::emit_mir_copy_aggregate_param_from_stack(
  self : X64Codegen,
  ty : @ctype.Type,
  local_offset : Int,
  stack_arg_index : Int,
) -> Unit {
  self.emit_local_addr(local_offset)
  self.emit("\tmov\tr10, rax")
  let words = self.aggregate_word_count(ty)
  for word in 0..<words {
    let width = self.aggregate_word_width(ty, word)
    self.emit_load_int_bytes_from_mem_reg(
      "rax",
      "rbp",
      16 + (stack_arg_index + word) * 8,
      width,
    )
    self.emit_store_int_bytes_to_mem_reg("rax", "r10", word * 8, width)
  }
}

///|
fn X64Codegen::emit_mir_pop_rax(self : X64Codegen) -> Unit {
  self.emit("\tmov\trax, QWORD PTR [rsp]")
  self.emit("\tadd\trsp, 16")
}

///|
fn X64Codegen::emit_mir_restore_scalar(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Unit {
  if x64_is_fp_type(ty) {
    self.emit_mir_pop_xmm0(ty)
  } else if x64_is_int128_type(ty) {
    self.emit_pop_int128()
  } else {
    self.emit_mir_pop_rax()
  }
}

///|
fn X64Codegen::emit_mir_atomic_load(
  self : X64Codegen,
  ptr : @mir.MirValue,
  order : @mir.MirValue,
  offsets : Map[Int, Int],
) -> Unit {
  let elem_ty = mir_body_codegen_atomic_target_type(ptr.ty())
  self.gen_mir_value(ptr, offsets)
  self.emit_mir_push_rax()
  self.gen_mir_value(order, offsets)
  self.emit_mir_pop_rax()
  self.emit_load_indirect(elem_ty)
}

///|
fn X64Codegen::emit_mir_atomic_store(
  self : X64Codegen,
  ptr : @mir.MirValue,
  value : @mir.MirValue,
  order : @mir.MirValue,
  offsets : Map[Int, Int],
) -> Unit {
  let elem_ty = mir_body_codegen_atomic_target_type(ptr.ty())
  self.gen_mir_value(ptr, offsets)
  self.emit_mir_push_rax()
  self.gen_mir_value(order, offsets)
  self.gen_mir_value(value, offsets)
  self.emit_mir_numeric_conversion(value.ty(), elem_ty)
  if x64_is_fp_type(elem_ty) {
    self.emit("\tmov\tr10, QWORD PTR [rsp]")
    self.emit("\tadd\trsp, 16")
    self.emit_store_indirect(elem_ty)
  } else {
    self.emit_int_conversion_to(elem_ty)
    self.emit("\tmov\tr10, QWORD PTR [rsp]")
    self.emit("\tadd\trsp, 16")
    let width = self.type_size(elem_ty)
    self.emit(
      "\txchg\t" +
      x64_atomic_mem_operand("r10", width) +
      ", " +
      x64_atomic_rax_reg(width),
    )
  }
  self.emit("\tmov\trax, 0")
}

///|
fn X64Codegen::emit_mir_pop_to(self : X64Codegen, reg : String) -> Unit {
  self.emit("\tmov\t" + reg + ", QWORD PTR [rsp]")
  self.emit("\tadd\trsp, 16")
}

///|
fn X64Codegen::emit_mir_ignored_values(
  self : X64Codegen,
  values : Array[@mir.MirValue],
  offsets : Map[Int, Int],
) -> Unit {
  for value in values {
    self.gen_mir_value(value, offsets)
  }
}

///|
fn X64Codegen::emit_mir_atomic_update(
  self : X64Codegen,
  ptr : @mir.MirValue,
  value : @mir.MirValue,
  extras : Array[@mir.MirValue],
  offsets : Map[Int, Int],
  op : String,
  return_new : Bool,
) -> Unit {
  self.emit_mir_ignored_values(extras, offsets)
  let elem_ty = mir_body_codegen_atomic_target_type(ptr.ty())
  self.gen_mir_value(ptr, offsets)
  self.emit_mir_push_rax()
  self.gen_mir_value(value, offsets)
  self.emit_mir_numeric_conversion(value.ty(), elem_ty)
  self.emit_int_conversion_to(elem_ty)
  self.emit("\tmov\tr10, rax")
  self.emit_mir_pop_to("rdi")
  self.emit_atomic_update_loop(op, elem_ty, return_new)
}

///|
fn X64Codegen::emit_mir_atomic_exchange(
  self : X64Codegen,
  ptr : @mir.MirValue,
  value : @mir.MirValue,
  extras : Array[@mir.MirValue],
  offsets : Map[Int, Int],
) -> Unit {
  self.emit_mir_ignored_values(extras, offsets)
  let elem_ty = mir_body_codegen_atomic_target_type(ptr.ty())
  let width = self.type_size(elem_ty)
  self.gen_mir_value(ptr, offsets)
  self.emit_mir_push_rax()
  self.gen_mir_value(value, offsets)
  self.emit_mir_numeric_conversion(value.ty(), elem_ty)
  self.emit_int_conversion_to(elem_ty)
  self.emit_mir_pop_to("r10")
  self.emit(
    "\txchg\t" +
    x64_atomic_mem_operand("r10", width) +
    ", " +
    x64_atomic_rax_reg(width),
  )
  self.emit_atomic_clean_rax(elem_ty)
  self.emit_int_conversion_to(elem_ty)
}

///|
fn X64Codegen::emit_mir_atomic_compare_exchange(
  self : X64Codegen,
  ptr : @mir.MirValue,
  expected : @mir.MirValue,
  desired : @mir.MirValue,
  extras : Array[@mir.MirValue],
  offsets : Map[Int, Int],
) -> Unit {
  self.emit_mir_ignored_values(extras, offsets)
  let elem_ty = mir_body_codegen_atomic_target_type(ptr.ty())
  let width = self.type_size(elem_ty)
  let fail_label = self.new_label()
  let done_label = self.new_label()
  self.gen_mir_value(ptr, offsets)
  self.emit_mir_push_rax()
  self.gen_mir_value(expected, offsets)
  self.emit_mir_push_rax()
  self.gen_mir_value(desired, offsets)
  self.emit_mir_numeric_conversion(desired.ty(), elem_ty)
  self.emit_int_conversion_to(elem_ty)
  self.emit("\tmov\tr11, rax")
  self.emit_mir_pop_to("rsi")
  self.emit_mir_pop_to("rdi")
  self.emit_atomic_raw_load_to_rax("rsi", elem_ty)
  self.emit(
    "\tlock cmpxchg\t" +
    x64_atomic_mem_operand("rdi", width) +
    ", " +
    x64_atomic_r11_reg(width),
  )
  self.emit("\tjne\t" + fail_label)
  self.emit("\tmov\trax, 1")
  self.emit("\tjmp\t" + done_label)
  self.emit(fail_label + ":")
  self.emit_atomic_raw_store_from_rax("rsi", elem_ty)
  self.emit("\tmov\trax, 0")
  self.emit(done_label + ":")
}

///|
fn X64Codegen::mir_pointer_update_scale(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Int {
  match pointer_or_array_element_type(ty) {
    Some(elem_ty) => self.mir_pointer_element_scale(elem_ty)
    None => 1
  }
}

///|
fn X64Codegen::mir_pointer_element_scale(
  self : X64Codegen,
  elem_ty : @ctype.Type,
) -> Int {
  match elem_ty {
    Void => 1
    _ => self.type_size(elem_ty)
  }
}

///|
fn X64Codegen::emit_mir_scale_update_rhs_for_pointer(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Unit {
  let scale = self.mir_pointer_update_scale(ty)
  if scale != 1 {
    self.emit("\timul\trax, " + scale.to_string())
  }
}

///|
fn X64Codegen::emit_mir_fp_binary_xmm0_xmm1(
  self : X64Codegen,
  op : String,
  fp_ty : @ctype.Type,
) -> Unit {
  let suffix = x64_fp_suffix(fp_ty)
  match op {
    "+" => self.emit("\tadd" + suffix + "\txmm0, xmm1")
    "-" => self.emit("\tsub" + suffix + "\txmm0, xmm1")
    "*" => self.emit("\tmul" + suffix + "\txmm0, xmm1")
    "/" => self.emit("\tdiv" + suffix + "\txmm0, xmm1")
    _ => abort("unsupported MIR body floating arithmetic operator")
  }
}

///|
fn X64Codegen::ensure_mir_va_list_storage(
  self : X64Codegen,
  binding : @mir.MirLocal,
) -> Int {
  self.ensure_va_list_storage(mir_body_local_name(binding))
}

///|
fn X64Codegen::collect_mir_va_list_storage_value(
  self : X64Codegen,
  value : @mir.MirValue,
) -> Unit {
  match value {
    MirConst(_, _)
    | MirLocal(_)
    | MirAddrLocal(_)
    | MirAddrGlobal(_, _)
    | MirFuncAddr(_, _)
    | MirLabelAddr(_)
    | MirStringAddr(_) => ()
    MirElemAddr(base, index, _) => {
      self.collect_mir_va_list_storage_value(base)
      self.collect_mir_va_list_storage_value(index)
    }
    MirOffsetAddr(base, _, _) | MirLoad(base, _) | MirUnary(_, base, _) =>
      self.collect_mir_va_list_storage_value(base)
    MirBinary(_, lhs, rhs, _) | MirStore(lhs, rhs, _) => {
      self.collect_mir_va_list_storage_value(lhs)
      self.collect_mir_va_list_storage_value(rhs)
    }
    MirOverflow(_, left, right, result_ptr) => {
      self.collect_mir_va_list_storage_value(left)
      self.collect_mir_va_list_storage_value(right)
      self.collect_mir_va_list_storage_value(result_ptr)
    }
    MirVaStart(target) => {
      match target {
        MirLocal(binding) => {
          let _ = self.ensure_mir_va_list_storage(binding)
        }
        _ => ()
      }
      self.collect_mir_va_list_storage_value(target)
    }
    MirVaCopy(target, source) => {
      match target {
        MirLocal(binding) => {
          let _ = self.ensure_mir_va_list_storage(binding)
        }
        _ => ()
      }
      self.collect_mir_va_list_storage_value(target)
      self.collect_mir_va_list_storage_value(source)
    }
    MirVaEnd(target) => self.collect_mir_va_list_storage_value(target)
    MirBzero(dst, size) => {
      self.collect_mir_va_list_storage_value(dst)
      self.collect_mir_va_list_storage_value(size)
    }
    MirAtomicLoad(ptr, order, _) => {
      self.collect_mir_va_list_storage_value(ptr)
      self.collect_mir_va_list_storage_value(order)
    }
    MirAtomicStore(ptr, stored, order) => {
      self.collect_mir_va_list_storage_value(ptr)
      self.collect_mir_va_list_storage_value(stored)
      self.collect_mir_va_list_storage_value(order)
    }
    MirAtomicUpdate(_, _, ptr, stored, extras, _) => {
      self.collect_mir_va_list_storage_value(ptr)
      self.collect_mir_va_list_storage_value(stored)
      for extra in extras {
        self.collect_mir_va_list_storage_value(extra)
      }
    }
    MirAtomicExchange(ptr, stored, extras, _) => {
      self.collect_mir_va_list_storage_value(ptr)
      self.collect_mir_va_list_storage_value(stored)
      for extra in extras {
        self.collect_mir_va_list_storage_value(extra)
      }
    }
    MirAtomicCompareExchange(ptr, expected, desired, extras) => {
      self.collect_mir_va_list_storage_value(ptr)
      self.collect_mir_va_list_storage_value(expected)
      self.collect_mir_va_list_storage_value(desired)
      for extra in extras {
        self.collect_mir_va_list_storage_value(extra)
      }
    }
    MirLibCall(_, args, _) =>
      for arg in args {
        self.collect_mir_va_list_storage_value(arg)
      }
    MirCast(_, inner) | MirAggregateArg(inner, _) | MirVaArg(inner, _) =>
      self.collect_mir_va_list_storage_value(inner)
    MirVaArgAddr(inner, ty) => {
      if x64_is_aggregate_type(ty) {
        let size = self.type_size(ty)
        if size > self.va_arg_scratch_size {
          self.va_arg_scratch_size = size
        }
        let align = self.type_align(ty)
        if align > self.va_arg_scratch_align {
          self.va_arg_scratch_align = align
        }
      }
      self.collect_mir_va_list_storage_value(inner)
    }
    MirCall(_, args, _) => {
      if self.is_memory_aggregate(value.ty()) {
        let size = self.type_size(value.ty())
        if size > self.sret_scratch_size {
          self.sret_scratch_size = size
        }
        let align = self.type_align(value.ty())
        if align > self.sret_scratch_align {
          self.sret_scratch_align = align
        }
      }
      for arg in args {
        self.collect_mir_va_list_storage_value(arg)
      }
    }
    MirIndirectCall(callee, args, _) => {
      if self.is_memory_aggregate(value.ty()) {
        let size = self.type_size(value.ty())
        if size > self.sret_scratch_size {
          self.sret_scratch_size = size
        }
        let align = self.type_align(value.ty())
        if align > self.sret_scratch_align {
          self.sret_scratch_align = align
        }
      }
      self.collect_mir_va_list_storage_value(callee)
      for arg in args {
        self.collect_mir_va_list_storage_value(arg)
      }
    }
    MirAssignLocal(_, rhs) | MirPostUpdateLocal(_, _, rhs, _) =>
      self.collect_mir_va_list_storage_value(rhs)
    MirPreUpdateMemory(ptr, _, rhs, _) | MirPostUpdateMemory(ptr, _, rhs, _) => {
      self.collect_mir_va_list_storage_value(ptr)
      self.collect_mir_va_list_storage_value(rhs)
    }
    MirTernary(cond, then_, else_, _) => {
      self.collect_mir_va_list_storage_value(cond)
      self.collect_mir_va_list_storage_value(then_)
      self.collect_mir_va_list_storage_value(else_)
    }
  }
}

///|
fn X64Codegen::collect_mir_va_list_storage_stmt(
  self : X64Codegen,
  stmt : @mir.MirStmt,
) -> Unit {
  match stmt {
    MirDeclare(_, init) =>
      match init {
        Some(value) => self.collect_mir_va_list_storage_value(value)
        None => ()
      }
    MirExprStmt(value) => self.collect_mir_va_list_storage_value(value)
    MirReturn(value) =>
      match value {
        Some(value) => self.collect_mir_va_list_storage_value(value)
        None => ()
      }
    MirIf(cond, then_, else_) => {
      self.collect_mir_va_list_storage_value(cond)
      for nested in then_ {
        self.collect_mir_va_list_storage_stmt(nested)
      }
      for nested in else_ {
        self.collect_mir_va_list_storage_stmt(nested)
      }
    }
    MirWhile(cond, body) | MirDoWhile(cond, body) => {
      self.collect_mir_va_list_storage_value(cond)
      for nested in body {
        self.collect_mir_va_list_storage_stmt(nested)
      }
    }
    MirFor(init, cond, inc, body) => {
      for nested in init {
        self.collect_mir_va_list_storage_stmt(nested)
      }
      self.collect_mir_va_list_storage_value(cond)
      match inc {
        Some(value) => self.collect_mir_va_list_storage_value(value)
        None => ()
      }
      for nested in body {
        self.collect_mir_va_list_storage_stmt(nested)
      }
    }
    MirSwitch(control, _, body) => {
      self.collect_mir_va_list_storage_value(control)
      for nested in body {
        self.collect_mir_va_list_storage_stmt(nested)
      }
    }
    MirBlock(stmts) =>
      for nested in stmts {
        self.collect_mir_va_list_storage_stmt(nested)
      }
    MirComputedGoto(value) => self.collect_mir_va_list_storage_value(value)
    MirLabel(_) | MirGoto(_) | MirBreak | MirContinue => ()
  }
}

///|
fn X64Codegen::mir_body_offsets(
  self : X64Codegen,
  body : @mir.MirFuncBody,
) -> Map[Int, Int] {
  let offsets : Map[Int, Int] = Map([])
  for binding in body.locals {
    if mir_body_codegen_local_type(binding.ty) {
      offsets[binding.id] = self.alloc_local(
        mir_body_local_name(binding),
        binding.ty,
      )
    }
  }
  for stmt in body.body {
    self.collect_mir_va_list_storage_stmt(stmt)
  }
  if self.va_arg_scratch_size > 0 {
    self.va_arg_scratch_offset = self.alloc_local(
      "__kimicc_mir_va_arg_scratch",
      Aligned(Array(UChar, self.va_arg_scratch_size), self.va_arg_scratch_align),
    )
  }
  if self.sret_scratch_size > 0 {
    self.sret_scratch_offset = self.alloc_local(
      "__kimicc_mir_sret_scratch",
      Aligned(Array(UChar, self.sret_scratch_size), self.sret_scratch_align),
    )
  }
  offsets
}

///|
fn x64_compute_mir_va_initial_offsets(
  params : Array[@mir.MirLocal],
  initial_int_slots : Int,
) -> (Int, Int, Int) {
  let mut int_idx = initial_int_slots
  let mut fp_idx = 0
  let mut stack_idx = 0
  for param in params {
    if mir_body_codegen_abi_fp_type(param.ty) {
      if fp_idx < 8 {
        fp_idx += 1
      } else {
        stack_idx += 1
      }
    } else if int_idx < 6 {
      int_idx += 1
    } else {
      stack_idx += 1
    }
  }
  (int_idx * 8, 48 + fp_idx * 16, 16 + stack_idx * 8)
}

///|
fn X64Codegen::emit_mir_save_variadic_registers(self : X64Codegen) -> Unit {
  if self.va_reg_save_offset < 0 {
    return
  }
  let arg_regs : ReadOnlyArray[String] = [
    "rdi", "rsi", "rdx", "rcx", "r8", "r9",
  ]
  let fp_arg_regs : ReadOnlyArray[String] = [
    "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7",
  ]
  for i in 0..<arg_regs.length() {
    self.emit(
      "\tmov\tQWORD PTR " +
      self.local_neg_ref(self.va_reg_save_offset, i * 8) +
      ", " +
      arg_regs[i],
    )
  }
  for i in 0..<fp_arg_regs.length() {
    self.emit(
      "\tmovups\tXMMWORD PTR " +
      self.local_neg_ref(self.va_reg_save_offset, 48 + i * 16) +
      ", " +
      fp_arg_regs[i],
    )
  }
}

///|
fn X64Codegen::emit_mir_store_va_list_pointer(
  self : X64Codegen,
  binding : @mir.MirLocal,
  state_offset : Int,
  offsets : Map[Int, Int],
) -> Unit {
  self.emit("\tlea\trax, " + self.local_ref(state_offset))
  self.emit("\tmov\tQWORD PTR " + self.local_ref(offsets[binding.id]) + ", rax")
}

///|
fn X64Codegen::emit_mir_va_start(
  self : X64Codegen,
  target : @mir.MirValue,
  offsets : Map[Int, Int],
) -> Unit {
  if self.va_reg_save_offset < 0 {
    abort("MIR va_start used in non-variadic x86-64 function")
  }
  match target {
    MirLocal(binding) => {
      let state_offset = self.ensure_mir_va_list_storage(binding)
      self.emit(
        "\tmov\tDWORD PTR " +
        self.local_neg_ref(state_offset, 0) +
        ", " +
        self.va_initial_gp_offset.to_string(),
      )
      self.emit(
        "\tmov\tDWORD PTR " +
        self.local_neg_ref(state_offset, 4) +
        ", " +
        self.va_initial_fp_offset.to_string(),
      )
      self.emit(
        "\tlea\trax, [rbp + " +
        self.va_initial_overflow_offset.to_string() +
        "]",
      )
      self.emit(
        "\tmov\tQWORD PTR " + self.local_neg_ref(state_offset, 8) + ", rax",
      )
      self.emit("\tlea\trax, " + self.local_ref(self.va_reg_save_offset))
      self.emit(
        "\tmov\tQWORD PTR " + self.local_neg_ref(state_offset, 16) + ", rax",
      )
      self.emit_mir_store_va_list_pointer(binding, state_offset, offsets)
    }
    _ => ()
  }
  self.emit("\tmov\trax, 0")
}

///|
fn X64Codegen::emit_mir_va_copy(
  self : X64Codegen,
  target : @mir.MirValue,
  source : @mir.MirValue,
  offsets : Map[Int, Int],
) -> Unit {
  match target {
    MirLocal(binding) => {
      let dest_offset = self.ensure_mir_va_list_storage(binding)
      self.gen_mir_value(source, offsets)
      self.emit("\tmov\tr11, rax")
      self.emit("\tmov\trax, QWORD PTR [r11]")
      self.emit(
        "\tmov\tQWORD PTR " + self.local_neg_ref(dest_offset, 0) + ", rax",
      )
      self.emit("\tmov\trax, QWORD PTR [r11 + 8]")
      self.emit(
        "\tmov\tQWORD PTR " + self.local_neg_ref(dest_offset, 8) + ", rax",
      )
      self.emit("\tmov\trax, QWORD PTR [r11 + 16]")
      self.emit(
        "\tmov\tQWORD PTR " + self.local_neg_ref(dest_offset, 16) + ", rax",
      )
      self.emit_mir_store_va_list_pointer(binding, dest_offset, offsets)
    }
    _ => ()
  }
  self.emit("\tmov\trax, 0")
}

///|
fn X64Codegen::emit_mir_va_arg(
  self : X64Codegen,
  ap : @mir.MirValue,
  ty : @ctype.Type,
  offsets : Map[Int, Int],
) -> Unit {
  let overflow_label = self.new_label()
  let load_label = self.new_label()
  if mir_body_codegen_abi_fp_type(ty) {
    self.gen_mir_value(ap, offsets)
    self.emit("\tmov\tr11, rax")
    self.emit("\tmov\teax, DWORD PTR [r11 + 4]")
    self.emit("\tcmp\teax, 176")
    self.emit("\tjae\t" + overflow_label)
    self.emit("\tmov\tr10, QWORD PTR [r11 + 16]")
    self.emit("\tadd\tr10, rax")
    self.emit("\tadd\tDWORD PTR [r11 + 4], 16")
    self.emit("\tjmp\t" + load_label)
    self.emit(overflow_label + ":")
    self.emit("\tmov\tr10, QWORD PTR [r11 + 8]")
    self.emit("\tlea\trax, [r10 + 8]")
    self.emit("\tmov\tQWORD PTR [r11 + 8], rax")
    self.emit(load_label + ":")
    self.emit("\tmov\trax, r10")
    self.emit_load_indirect(ty)
  } else {
    let gp_bytes = mir_body_codegen_abi_int_slots(ty) * 8
    let gp_overflow_at = 56 - gp_bytes
    self.gen_mir_value(ap, offsets)
    self.emit("\tmov\tr11, rax")
    self.emit("\tmov\teax, DWORD PTR [r11]")
    self.emit("\tcmp\teax, " + gp_overflow_at.to_string())
    self.emit("\tjae\t" + overflow_label)
    self.emit("\tmov\tr10, QWORD PTR [r11 + 16]")
    self.emit("\tadd\tr10, rax")
    self.emit("\tadd\tDWORD PTR [r11], " + gp_bytes.to_string())
    self.emit("\tjmp\t" + load_label)
    self.emit(overflow_label + ":")
    self.emit("\tmov\tr10, QWORD PTR [r11 + 8]")
    if mir_body_codegen_int128_type(ty) {
      self.emit("\tadd\tr10, 15")
      self.emit("\tand\tr10, -16")
    }
    self.emit("\tlea\trax, [r10 + " + gp_bytes.to_string() + "]")
    self.emit("\tmov\tQWORD PTR [r11 + 8], rax")
    self.emit(load_label + ":")
    self.emit("\tmov\trax, r10")
    self.emit_load_indirect(ty)
  }
}

///|
fn X64Codegen::emit_mir_copy_va_arg_overflow_aggregate(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Unit {
  self.emit("\tmov\tr10, QWORD PTR [r11 + 8]")
  let align = self.type_align(ty)
  if align > 8 {
    self.emit("\tadd\tr10, " + (align - 1).to_string())
    self.emit("\tand\tr10, -" + align.to_string())
  }
  let overflow_size = x64_align_to(self.type_size(ty), 8)
  self.emit("\tlea\trax, [r10 + " + overflow_size.to_string() + "]")
  self.emit("\tmov\tQWORD PTR [r11 + 8], rax")
  self.emit("\tmov\tr11, r10")
  self.emit("\tlea\tr10, " + self.local_ref(self.va_arg_scratch_offset))
  self.emit_copy_aggregate_from_addr(ty)
  self.emit("\tmov\trax, r10")
}

///|
fn X64Codegen::emit_mir_va_arg_aggregate_addr(
  self : X64Codegen,
  ap : @mir.MirValue,
  ty : @ctype.Type,
  offsets : Map[Int, Int],
) -> Unit {
  if self.va_arg_scratch_offset < 0 {
    abort("x86-64 MIR backend missing aggregate va_arg scratch storage")
  }
  let overflow_label = self.new_label()
  let done_label = self.new_label()
  self.gen_mir_value(ap, offsets)
  self.emit("\tmov\tr11, rax")
  let classes = match self.aggregate_classes(ty) {
    Some(classes) => classes
    None => {
      self.emit_mir_copy_va_arg_overflow_aggregate(ty)
      return
    }
  }
  let int_needed = x64_class_count(classes, IntClass)
  let fp_needed = x64_class_count(classes, SseClass)
  if int_needed > 0 {
    let gp_limit = 48 - int_needed * 8
    self.emit("\tmov\teax, DWORD PTR [r11]")
    self.emit("\tcmp\teax, " + gp_limit.to_string())
    self.emit("\tja\t" + overflow_label)
  }
  if fp_needed > 0 {
    let fp_limit = 176 - fp_needed * 16
    self.emit("\tmov\tecx, DWORD PTR [r11 + 4]")
    self.emit("\tcmp\tecx, " + fp_limit.to_string())
    self.emit("\tja\t" + overflow_label)
  }
  self.emit("\tmov\tr9, QWORD PTR [r11 + 16]")
  if int_needed > 0 {
    self.emit("\tmov\teax, DWORD PTR [r11]")
  }
  if fp_needed > 0 {
    self.emit("\tmov\tecx, DWORD PTR [r11 + 4]")
  }
  self.emit("\tlea\tr10, " + self.local_ref(self.va_arg_scratch_offset))
  let mut int_cursor = 0
  let mut fp_cursor = 0
  for word in 0..<classes.length() {
    let width = self.aggregate_word_width(ty, word)
    match classes[word] {
      IntClass => {
        self.emit("\tmov\tr8d, eax")
        if int_cursor > 0 {
          self.emit("\tadd\tr8, " + (int_cursor * 8).to_string())
        }
        self.emit("\tmov\trdx, QWORD PTR [r9 + r8]")
        self.emit_store_int_bytes_to_mem_reg("rdx", "r10", word * 8, width)
        int_cursor += 1
      }
      SseClass => {
        self.emit("\tmov\tr8d, ecx")
        if fp_cursor > 0 {
          self.emit("\tadd\tr8, " + (fp_cursor * 16).to_string())
        }
        if width <= 4 {
          self.emit("\tmovss\txmm0, DWORD PTR [r9 + r8]")
        } else {
          self.emit("\tmovsd\txmm0, QWORD PTR [r9 + r8]")
        }
        self.emit_store_sse_word_to_mem_reg("xmm0", "r10", word * 8, width)
        fp_cursor += 1
      }
    }
  }
  if int_needed > 0 {
    self.emit("\tadd\tDWORD PTR [r11], " + (int_needed * 8).to_string())
  }
  if fp_needed > 0 {
    self.emit("\tadd\tDWORD PTR [r11 + 4], " + (fp_needed * 16).to_string())
  }
  self.emit("\tmov\trax, r10")
  self.emit("\tjmp\t" + done_label)
  self.emit(overflow_label + ":")
  self.emit_mir_copy_va_arg_overflow_aggregate(ty)
  self.emit(done_label + ":")
}

///|
fn X64Codegen::emit_mir_bzero(
  self : X64Codegen,
  dst : @mir.MirValue,
  size : @mir.MirValue,
  offsets : Map[Int, Int],
) -> Unit {
  self.gen_mir_value(dst, offsets)
  self.emit_mir_push_rax()
  self.gen_mir_value(size, offsets)
  self.emit_int_conversion_to(size.ty())
  self.emit("\tmov\trsi, rax")
  self.emit("\tmov\trdi, QWORD PTR [rsp]")
  self.emit("\tadd\trsp, 16")
  self.emit("\tcall\tbzero")
  self.emit("\tmov\trax, 0")
}

///|
fn X64Codegen::emit_mir_overflow_arithmetic_builtin(
  self : X64Codegen,
  left : @mir.MirValue,
  right : @mir.MirValue,
  result_ptr : @mir.MirValue,
  offsets : Map[Int, Int],
  op : String,
) -> Unit {
  let result_ty = match mir_body_codegen_overflow_result_type(result_ptr) {
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
  self.gen_mir_value(result_ptr, offsets)
  self.emit_mir_push_rax()
  self.gen_mir_value(left, offsets)
  self.emit_int_conversion_to(result_ty)
  self.emit_mir_push_rax()
  self.gen_mir_value(right, offsets)
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
fn X64Codegen::emit_mir_rotate_op(
  self : X64Codegen,
  op : String,
  lhs : @mir.MirValue,
  rhs : @mir.MirValue,
  ty : @ctype.Type,
  offsets : Map[Int, Int],
) -> Unit {
  let (width, left) = match mir_body_codegen_rotate_op(op) {
    Some(value) => value
    None => abort("unsupported x86-64 MIR body rotate operator")
  }
  self.gen_mir_value(lhs, offsets)
  self.emit_mir_numeric_conversion(lhs.ty(), ty)
  self.emit_int_conversion_to(ty)
  self.emit_mir_push_rax()
  self.gen_mir_value(rhs, offsets)
  self.emit_int_conversion_to(rhs.ty())
  self.emit("\tmov\trcx, rax")
  self.emit_mir_pop_rax()
  let instr = if left { "rol" } else { "ror" }
  if width == 32 {
    self.emit("\t" + instr + "\teax, cl")
    self.emit("\tmov\teax, eax")
  } else {
    self.emit("\t" + instr + "\trax, cl")
  }
  self.emit_int_conversion_to(ty)
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
        match x64_core_type(ty) {
          SInt128 =>
            if bits < 0L {
              self.emit("\tmov\trdx, -1")
            } else {
              self.emit("\txor\trdx, rdx")
            }
          UInt128 => self.emit("\txor\trdx, rdx")
          _ => self.emit_int_conversion_to(ty)
        }
      }
    MirLocal(binding) => {
      self.emit_local_addr(offsets[binding.id])
      self.emit_load_indirect(binding.ty)
    }
    MirAddrLocal(binding) => self.emit_local_addr(offsets[binding.id])
    MirAddrGlobal(name, _) => self.emit_symbol_addr(name)
    MirFuncAddr(name, _) => self.emit_symbol_addr(name)
    MirLabelAddr(name) =>
      self.emit("\tlea\trax, [rip + " + self.label_ref(name) + "]")
    MirStringAddr(value) => {
      let id = self.strings.length()
      self.strings.push(value)
      self.emit("\tlea\trax, [rip + .Lstr" + id.to_string() + "]")
    }
    MirElemAddr(base, index, elem_ty) => {
      self.gen_mir_address_base(base, offsets)
      self.emit_mir_push_rax()
      self.gen_mir_value(index, offsets)
      let elem_size = self.mir_pointer_element_scale(elem_ty)
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
        "fp_isnan"
        | "fp_isinf"
        | "fp_isfinite"
        | "fp_isnormal"
        | "fp_signbit" =>
          if x64_is_fp_type(inner.ty()) {
            self.emit_mir_fp_class_result(op, inner.ty())
            self.emit_int_conversion_to(ty)
          } else {
            abort("unsupported MIR body floating classification operand")
          }
        "alloca" => {
          self.emit("\tadd\trax, 15")
          self.emit("\tand\trax, -16")
          self.emit("\tsub\trsp, rax")
          self.emit("\tmov\trax, rsp")
        }
        "frame_address" =>
          match inner {
            MirConst(level, _) =>
              if level == 0L {
                self.emit("\tmov\trax, rbp")
              } else {
                self.emit("\tmov\trax, 0")
              }
            _ => {
              self.emit("\tcmp\trax, 0")
              self.emit("\tmov\tr10, rbp")
              self.emit("\tmov\trax, 0")
              self.emit("\tcmove\trax, r10")
            }
          }
        "return_address" =>
          match inner {
            MirConst(level, _) =>
              if level == 0L {
                self.emit("\tmov\trax, QWORD PTR [rbp + 8]")
              } else {
                self.emit("\tmov\trax, 0")
              }
            _ => {
              self.emit("\tcmp\trax, 0")
              self.emit("\tmov\tr10, QWORD PTR [rbp + 8]")
              self.emit("\tmov\trax, 0")
              self.emit("\tcmove\trax, r10")
            }
          }
        "sync_synchronize" | "atomic_thread_fence" => {
          self.emit("\tmfence")
          self.emit("\tmov\trax, 0")
        }
        "atomic_signal_fence" => self.emit("\tmov\trax, 0")
        "trap" => {
          self.emit("\tud2")
          self.emit("\tmov\trax, 0")
        }
        "+" => ()
        "-" =>
          if mir_body_codegen_int128_type(ty) {
            self.emit_mir_numeric_conversion(inner.ty(), ty)
            self.emit("\tneg\trax")
            self.emit("\tadc\trdx, 0")
            self.emit("\tneg\trdx")
          } else if x64_is_fp_type(ty) {
            self.emit_mir_numeric_conversion(inner.ty(), ty)
            match x64_core_type(ty) {
              Float => {
                self.emit("\tmov\teax, -2147483648")
                self.emit("\tmovd\txmm1, eax")
                self.emit("\txorps\txmm0, xmm1")
              }
              _ => {
                self.emit("\tmovabs\trax, -9223372036854775808")
                self.emit("\tmovq\txmm1, rax")
                self.emit("\txorpd\txmm0, xmm1")
              }
            }
          } else {
            self.emit("\tneg\trax")
          }
        "fabs" =>
          if x64_is_fp_type(ty) {
            self.emit_mir_numeric_conversion(inner.ty(), ty)
            match x64_core_type(ty) {
              Float => {
                self.emit("\tmov\teax, 2147483647")
                self.emit("\tmovd\txmm1, eax")
                self.emit("\tandps\txmm0, xmm1")
              }
              _ => {
                self.emit("\tmovabs\trax, 9223372036854775807")
                self.emit("\tmovq\txmm1, rax")
                self.emit("\tandpd\txmm0, xmm1")
              }
            }
          } else {
            abort("unsupported MIR body fabs result type")
          }
        "fsqrt" =>
          if x64_is_fp_type(ty) {
            self.emit_mir_numeric_conversion(inner.ty(), ty)
            let suffix = x64_fp_suffix(ty)
            self.emit("\tsqrt" + suffix + "\txmm0, xmm0")
          } else {
            abort("unsupported MIR body fsqrt result type")
          }
        "!" =>
          if mir_body_codegen_int128_type(inner.ty()) {
            self.emit("\tor\trax, rdx")
            self.emit_setcc("sete")
          } else if x64_is_fp_type(inner.ty()) {
            let suffix = x64_fp_suffix(inner.ty())
            self.emit("\tpxor\txmm1, xmm1")
            self.emit("\tucomi" + suffix + "\txmm0, xmm1")
            self.emit("\tsete\tal")
            self.emit("\tsetnp\tdl")
            self.emit("\tand\tal, dl")
            self.emit("\tmovzx\trax, al")
          } else {
            self.emit("\tcmp\trax, 0")
            self.emit_setcc("sete")
          }
        "~" =>
          if mir_body_codegen_int128_type(ty) {
            self.emit_mir_numeric_conversion(inner.ty(), ty)
            self.emit("\tnot\trax")
            self.emit("\tnot\trdx")
          } else {
            self.emit("\tnot\trax")
          }
        "abs32" => {
          self.emit_mir_numeric_conversion(inner.ty(), ty)
          let done = self.new_label()
          self.emit("\tcmp\teax, 0")
          self.emit("\tjge\t" + done)
          self.emit("\tneg\teax")
          self.emit(done + ":")
        }
        "abs64" => {
          self.emit_mir_numeric_conversion(inner.ty(), ty)
          let done = self.new_label()
          self.emit("\tcmp\trax, 0")
          self.emit("\tjge\t" + done)
          self.emit("\tneg\trax")
          self.emit(done + ":")
        }
        "clz32" => {
          self.emit("\tbsr\tecx, eax")
          self.emit("\tmov\teax, 31")
          self.emit("\tsub\teax, ecx")
        }
        "clz64" => {
          self.emit("\tbsr\trcx, rax")
          self.emit("\tmov\teax, 63")
          self.emit("\tsub\teax, ecx")
        }
        "ctz32" => {
          self.emit("\tbsf\tecx, eax")
          self.emit("\tmov\teax, ecx")
        }
        "ctz64" => {
          self.emit("\tbsf\trcx, rax")
          self.emit("\tmov\teax, ecx")
        }
        "ffs32" => {
          let zero_label = self.new_label()
          let done_label = self.new_label()
          self.emit("\ttest\teax, eax")
          self.emit("\tje\t" + zero_label)
          self.emit("\tbsf\tecx, eax")
          self.emit("\tlea\teax, [ecx + 1]")
          self.emit("\tjmp\t" + done_label)
          self.emit(zero_label + ":")
          self.emit("\tmov\teax, 0")
          self.emit(done_label + ":")
        }
        "ffs64" => {
          let zero_label = self.new_label()
          let done_label = self.new_label()
          self.emit("\ttest\trax, rax")
          self.emit("\tje\t" + zero_label)
          self.emit("\tbsf\trcx, rax")
          self.emit("\tlea\teax, [rcx + 1]")
          self.emit("\tjmp\t" + done_label)
          self.emit(zero_label + ":")
          self.emit("\tmov\teax, 0")
          self.emit(done_label + ":")
        }
        "bswap16" => {
          self.emit("\trol\tax, 8")
          self.emit("\tmovzx\trax, ax")
        }
        "bswap32" => {
          self.emit("\tbswap\teax")
          self.emit("\tmov\teax, eax")
        }
        "bswap64" => self.emit("\tbswap\trax")
        "popcount32" | "popcount64" | "parity32" | "parity64" => {
          if op == "popcount32" || op == "parity32" {
            self.emit("\tmov\teax, eax")
          }
          self.emit("\tmov\tr10, rax")
          self.emit("\tshr\tr10, 1")
          self.emit("\tmovabs\tr11, 6148914691236517205")
          self.emit("\tand\tr10, r11")
          self.emit("\tsub\trax, r10")
          self.emit("\tmov\tr10, rax")
          self.emit("\tshr\tr10, 2")
          self.emit("\tmovabs\tr11, 3689348814741910323")
          self.emit("\tand\trax, r11")
          self.emit("\tand\tr10, r11")
          self.emit("\tadd\trax, r10")
          self.emit("\tmov\tr10, rax")
          self.emit("\tshr\tr10, 4")
          self.emit("\tadd\trax, r10")
          self.emit("\tmovabs\tr11, 1085102592571150095")
          self.emit("\tand\trax, r11")
          self.emit("\tmov\tr10, rax")
          self.emit("\tshr\tr10, 8")
          self.emit("\tadd\trax, r10")
          self.emit("\tmov\tr10, rax")
          self.emit("\tshr\tr10, 16")
          self.emit("\tadd\trax, r10")
          self.emit("\tmov\tr10, rax")
          self.emit("\tshr\tr10, 32")
          self.emit("\tadd\trax, r10")
          if op == "parity32" || op == "parity64" {
            self.emit("\tand\trax, 1")
          } else {
            self.emit("\tand\trax, 127")
          }
        }
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
    MirAggregateArg(addr, _) => self.gen_mir_value(addr, offsets)
    MirVaArg(ap, ty) => self.emit_mir_va_arg(ap, ty, offsets)
    MirVaArgAddr(ap, ty) => self.emit_mir_va_arg_aggregate_addr(ap, ty, offsets)
    MirAssignLocal(binding, rhs) => {
      self.gen_mir_value(rhs, offsets)
      self.emit_mir_numeric_conversion(rhs.ty(), binding.ty)
      self.emit_int_conversion_to(binding.ty)
      self.emit_store_local_from_rax(offsets[binding.id], binding.ty)
    }
    MirStore(ptr, rhs, ty) =>
      match rhs {
        MirCall(_, _, _) | MirIndirectCall(_, _, _) =>
          if self.is_supported_small_aggregate(ty) {
            self.gen_mir_value(ptr, offsets)
            self.emit_mir_push_rax()
            self.gen_mir_value(rhs, offsets)
            self.emit("\tmov\tr10, QWORD PTR [rsp]")
            self.emit_store_small_aggregate_return(ty)
            self.emit("\tmov\trax, r10")
            self.emit("\tadd\trsp, 16")
          } else if self.is_memory_aggregate(ty) {
            self.gen_mir_value(ptr, offsets)
            self.emit_mir_push_rax()
            self.gen_mir_value(rhs, offsets)
            self.emit("\tmov\tr11, rax")
            self.emit("\tmov\tr10, QWORD PTR [rsp]")
            self.emit_copy_aggregate_from_addr(ty)
            self.emit("\tmov\trax, r10")
            self.emit("\tadd\trsp, 16")
          } else {
            self.gen_mir_value(ptr, offsets)
            self.emit_mir_push_rax()
            self.gen_mir_value(rhs, offsets)
            self.emit_mir_numeric_conversion(rhs.ty(), ty)
            self.emit_int_conversion_to(ty)
            self.emit("\tmov\tr10, QWORD PTR [rsp]")
            self.emit("\tadd\trsp, 16")
            self.emit_store_indirect(ty)
          }
        _ => {
          self.gen_mir_value(ptr, offsets)
          self.emit_mir_push_rax()
          self.gen_mir_value(rhs, offsets)
          self.emit_mir_numeric_conversion(rhs.ty(), ty)
          self.emit_int_conversion_to(ty)
          self.emit("\tmov\tr10, QWORD PTR [rsp]")
          self.emit("\tadd\trsp, 16")
          self.emit_store_indirect(ty)
        }
      }
    MirPostUpdateLocal(binding, op, rhs, ty) => {
      if mir_body_codegen_fp_update_supported(op, binding.ty, rhs.ty()) {
        self.gen_mir_value(MirLocal(binding), offsets)
        self.emit_mir_spill_scalar(binding.ty)
        self.gen_mir_binary(op, MirLocal(binding), rhs, binding.ty, offsets)
        self.emit_int_conversion_to(binding.ty)
        self.emit_store_local_from_rax(offsets[binding.id], binding.ty)
        self.emit_mir_restore_scalar(binding.ty)
        self.emit_mir_numeric_conversion(binding.ty, ty)
        self.emit_int_conversion_to(ty)
        return
      }
      self.gen_mir_value(MirLocal(binding), offsets)
      self.emit_mir_push_rax()
      self.gen_mir_binary(op, MirLocal(binding), rhs, binding.ty, offsets)
      self.emit_int_conversion_to(binding.ty)
      self.emit_store_local_from_rax(offsets[binding.id], binding.ty)
      self.emit_mir_pop_rax()
      self.emit_int_conversion_to(ty)
    }
    MirPreUpdateMemory(ptr, op, rhs, ty) => {
      if mir_body_pointer_integer_op(op, ty, rhs.ty()) {
        self.gen_mir_value(ptr, offsets)
        self.emit_mir_push_rax()
        self.emit_load_indirect(ty)
        self.emit_mir_push_rax()
        self.gen_mir_value(rhs, offsets)
        self.emit_int_conversion_to(rhs.ty())
        self.emit_mir_scale_update_rhs_for_pointer(ty)
        self.emit("\tmov\tr10, rax")
        self.emit_mir_pop_rax()
        match op {
          "+" => self.emit("\tadd\trax, r10")
          "-" => self.emit("\tsub\trax, r10")
          _ => abort("unsupported MIR body memory pointer pre-update operator")
        }
        self.emit("\tmov\tr10, QWORD PTR [rsp]")
        self.emit("\tadd\trsp, 16")
        self.emit_store_indirect(ty)
        return
      }
      if mir_body_codegen_fp_update_supported(op, ty, rhs.ty()) {
        let fp_ty = mir_body_codegen_fp_binary_type(ty, rhs.ty(), ty)
        let suffix = x64_fp_suffix(fp_ty)
        self.gen_mir_value(ptr, offsets)
        self.emit_mir_push_rax()
        self.emit_load_indirect(ty)
        self.emit_mir_numeric_conversion(ty, fp_ty)
        self.emit_mir_push_xmm0(fp_ty)
        self.gen_mir_value(rhs, offsets)
        self.emit_mir_numeric_conversion(rhs.ty(), fp_ty)
        self.emit("\tmov" + suffix + "\txmm1, xmm0")
        self.emit_mir_pop_xmm0(fp_ty)
        self.emit_mir_fp_binary_xmm0_xmm1(op, fp_ty)
        self.emit_mir_numeric_conversion(fp_ty, ty)
        self.emit_int_conversion_to(ty)
        self.emit("\tmov\tr10, QWORD PTR [rsp]")
        self.emit("\tadd\trsp, 16")
        self.emit_store_indirect(ty)
        return
      }
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
      if mir_body_pointer_integer_op(op, ty, rhs.ty()) {
        self.gen_mir_value(ptr, offsets)
        self.emit_mir_push_rax()
        self.emit_load_indirect(ty)
        self.emit_mir_push_rax()
        self.gen_mir_value(rhs, offsets)
        self.emit_int_conversion_to(rhs.ty())
        self.emit_mir_scale_update_rhs_for_pointer(ty)
        self.emit("\tmov\tr10, rax")
        self.emit_mir_pop_rax()
        self.emit("\tmov\tr11, rax")
        match op {
          "+" => self.emit("\tadd\trax, r10")
          "-" => self.emit("\tsub\trax, r10")
          _ => abort("unsupported MIR body memory pointer post-update operator")
        }
        self.emit("\tmov\tr10, QWORD PTR [rsp]")
        self.emit("\tadd\trsp, 16")
        self.emit_store_indirect(ty)
        self.emit("\tmov\trax, r11")
        return
      }
      if mir_body_codegen_fp_update_supported(op, ty, rhs.ty()) {
        let fp_ty = mir_body_codegen_fp_binary_type(ty, rhs.ty(), ty)
        let suffix = x64_fp_suffix(fp_ty)
        self.gen_mir_value(ptr, offsets)
        self.emit_mir_push_rax()
        self.emit_load_indirect(ty)
        self.emit_mir_spill_scalar(ty)
        self.emit_mir_numeric_conversion(ty, fp_ty)
        self.emit_mir_push_xmm0(fp_ty)
        self.gen_mir_value(rhs, offsets)
        self.emit_mir_numeric_conversion(rhs.ty(), fp_ty)
        self.emit("\tmov" + suffix + "\txmm1, xmm0")
        self.emit_mir_pop_xmm0(fp_ty)
        self.emit_mir_fp_binary_xmm0_xmm1(op, fp_ty)
        self.emit_mir_numeric_conversion(fp_ty, ty)
        self.emit_int_conversion_to(ty)
        self.emit("\tmov\tr10, QWORD PTR [rsp + 16]")
        self.emit_store_indirect(ty)
        self.emit_mir_restore_scalar(ty)
        self.emit("\tadd\trsp, 16")
        return
      }
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
      self.emit_mir_cond_jump_false(cond, offsets, else_label)
      self.gen_mir_value(then_, offsets)
      self.emit_mir_numeric_conversion(then_.ty(), ty)
      self.emit_int_conversion_to(ty)
      self.emit("\tjmp\t" + end_label)
      self.emit(else_label + ":")
      self.gen_mir_value(else_, offsets)
      self.emit_mir_numeric_conversion(else_.ty(), ty)
      self.emit_int_conversion_to(ty)
      self.emit(end_label + ":")
    }
    MirOverflow(op, left, right, result_ptr) =>
      self.emit_mir_overflow_arithmetic_builtin(
        left, right, result_ptr, offsets, op,
      )
    MirVaStart(target) => self.emit_mir_va_start(target, offsets)
    MirVaCopy(target, source) => self.emit_mir_va_copy(target, source, offsets)
    MirVaEnd(_) => self.emit("\tmov\trax, 0")
    MirBzero(dst, size) => self.emit_mir_bzero(dst, size, offsets)
    MirAtomicLoad(ptr, order, _) =>
      self.emit_mir_atomic_load(ptr, order, offsets)
    MirAtomicStore(ptr, value, order) =>
      self.emit_mir_atomic_store(ptr, value, order, offsets)
    MirAtomicUpdate(op, return_new, ptr, value, extras, _) =>
      self.emit_mir_atomic_update(ptr, value, extras, offsets, op, return_new)
    MirAtomicExchange(ptr, value, extras, _) =>
      self.emit_mir_atomic_exchange(ptr, value, extras, offsets)
    MirAtomicCompareExchange(ptr, expected, desired, extras) =>
      self.emit_mir_atomic_compare_exchange(
        ptr, expected, desired, extras, offsets,
      )
    MirLibCall(name, args, ty) =>
      self.gen_mir_value(MirCall(name, args, ty), offsets)
    MirCall(name, args, ty) => {
      let source_indexes = mir_body_codegen_direct_call_source_indexes(args)
      let has_sret = self.is_memory_aggregate(ty)
      let mut call_stack_cleanup = 0
      let mut dynamic_call_stack_align = false
      let mut dynamic_call_stack_restore_offset = 0
      if self.mir_direct_call_variadic(name) {
        let arg_regs : ReadOnlyArray[String] = [
          "rdi", "rsi", "rdx", "rcx", "r8", "r9",
        ]
        let fp_arg_regs : ReadOnlyArray[String] = [
          "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7",
        ]
        let expected_types : Array[@ctype.Type] = []
        let int_arg_indexes : Array[Int] = []
        let fp_arg_indexes : Array[Int] = []
        let stack_arg_indexes : Array[Int] = []
        let arg_is_aggregate : Array[Bool] = []
        let arg_classes : Array[Array[X64AggregateClass]] = []
        let arg_words : Array[Int] = []
        let raw_sizes : Array[Int] = []
        let mut int_arg_index = if has_sret { 1 } else { 0 }
        let mut fp_arg_index = 0
        let mut stack_arg_index = 0
        let mut call_stack_align = 16
        for i in 0..<source_indexes.length() {
          let arg = args[source_indexes[i]]
          let expected = self.mir_call_arg_type(name, i, arg.ty())
          expected_types.push(expected)
          if mir_body_codegen_abi_fp_type(expected) {
            arg_is_aggregate.push(false)
            arg_classes.push([])
            arg_words.push(1)
            raw_sizes.push(16)
            int_arg_indexes.push(-1)
            if fp_arg_index < fp_arg_regs.length() {
              fp_arg_indexes.push(fp_arg_index)
              stack_arg_indexes.push(-1)
            } else {
              fp_arg_indexes.push(-1)
              stack_arg_indexes.push(stack_arg_index)
              stack_arg_index += 1
            }
            fp_arg_index += 1
            self.gen_mir_value(arg, offsets)
            self.emit_mir_numeric_conversion(arg.ty(), expected)
            self.emit_mir_push_xmm0(expected)
          } else if peel_aligned_type(expected) is Struct(_) ||
            peel_aligned_type(expected) is Union(_) {
            let classes = match self.aggregate_classes(expected) {
              Some(classes) => classes
              None => []
            }
            let words = if classes.length() > 0 {
              classes.length()
            } else {
              self.aggregate_word_count(expected)
            }
            let raw_size = if classes.length() > 0 { 16 } else { words * 8 }
            let int_needed = x64_class_count(classes, IntClass)
            let fp_needed = x64_class_count(classes, SseClass)
            arg_is_aggregate.push(true)
            arg_classes.push(classes)
            arg_words.push(words)
            raw_sizes.push(raw_size)
            if classes.length() > 0 &&
              int_arg_index + int_needed <= arg_regs.length() &&
              fp_arg_index + fp_needed <= fp_arg_regs.length() {
              int_arg_indexes.push(int_arg_index)
              fp_arg_indexes.push(fp_arg_index)
              stack_arg_indexes.push(-1)
              int_arg_index += int_needed
              fp_arg_index += fp_needed
            } else {
              int_arg_indexes.push(-1)
              fp_arg_indexes.push(-1)
              let (aligned_stack_arg_index, aligned_call_stack_align) = self.align_call_stack_arg(
                stack_arg_index, call_stack_align, expected,
              )
              stack_arg_index = aligned_stack_arg_index
              call_stack_align = aligned_call_stack_align
              stack_arg_indexes.push(stack_arg_index)
              stack_arg_index += words
            }
            self.emit_mir_save_aggregate_call_arg_raw(
              arg, expected, raw_size, offsets,
            )
          } else {
            arg_is_aggregate.push(false)
            arg_classes.push([])
            let slots = mir_body_codegen_abi_int_slots(expected)
            arg_words.push(slots)
            raw_sizes.push(16)
            if int_arg_index + slots <= arg_regs.length() {
              int_arg_indexes.push(int_arg_index)
              stack_arg_indexes.push(-1)
            } else {
              int_arg_indexes.push(-1)
              let (aligned_stack_arg_index, aligned_call_stack_align) = self.align_call_stack_arg(
                stack_arg_index, call_stack_align, expected,
              )
              stack_arg_index = aligned_stack_arg_index
              call_stack_align = aligned_call_stack_align
              stack_arg_indexes.push(stack_arg_index)
              stack_arg_index += slots
            }
            fp_arg_indexes.push(-1)
            int_arg_index += slots
            self.gen_mir_value(arg, offsets)
            self.emit_mir_numeric_conversion(arg.ty(), expected)
            if mir_body_codegen_int128_type(expected) {
              self.emit_push_int128()
            } else {
              self.emit_mir_push_rax()
            }
          }
        }
        let mut raw_area = 0
        for size in raw_sizes {
          raw_area += size
        }
        let stack_area = x64_align_to(stack_arg_index * 8, call_stack_align)
        let dynamic_stack_align = call_stack_align > 16 && stack_area > 0
        dynamic_call_stack_align = dynamic_stack_align
        dynamic_call_stack_restore_offset = stack_area
        let raw_base_reg = if dynamic_stack_align { "r10" } else { "rsp" }
        let raw_offset_base = if dynamic_stack_align { 0 } else { stack_area }
        let outgoing_stack_area = if dynamic_stack_align {
          x64_align_to(stack_area + 16, call_stack_align)
        } else {
          stack_area
        }
        if dynamic_stack_align {
          self.emit("\tmov\tr10, rsp")
          self.emit("\tlea\tr11, " + x64_mem_at_reg("rsp", raw_area))
          self.emit("\tand\trsp, -" + call_stack_align.to_string())
          self.emit("\tsub\trsp, " + outgoing_stack_area.to_string())
          self.emit("\tmov\tQWORD PTR " + x64_rsp_ref(stack_area) + ", r11")
        } else if stack_area > 0 {
          self.emit("\tsub\trsp, " + stack_area.to_string())
        }
        call_stack_cleanup = if dynamic_stack_align {
          0
        } else {
          raw_area + stack_area
        }
        for i in 0..<source_indexes.length() {
          if stack_arg_indexes[i] >= 0 {
            let raw_offset = mir_body_codegen_raw_arg_offset(
              raw_sizes, i, raw_offset_base,
            )
            if arg_is_aggregate[i] {
              let stack_offset = stack_arg_indexes[i] * 8
              for word in 0..<arg_words[i] {
                let width = self.aggregate_word_width(expected_types[i], word)
                self.emit_load_int_bytes_from_mem_reg(
                  "rax",
                  raw_base_reg,
                  raw_offset + word * 8,
                  width,
                )
                self.emit_store_int_bytes_to_mem_reg(
                  "rax",
                  "rsp",
                  stack_offset + word * 8,
                  width,
                )
              }
            } else if mir_body_codegen_abi_fp_type(expected_types[i]) {
              let suffix = x64_fp_suffix(expected_types[i])
              let size = if suffix == "ss" { "DWORD" } else { "QWORD" }
              self.emit(
                "\tmov" +
                suffix +
                "\txmm0, " +
                size +
                " PTR " +
                x64_mem_at_reg(raw_base_reg, raw_offset),
              )
              self.emit(
                "\tmov" +
                suffix +
                "\t" +
                size +
                " PTR " +
                x64_rsp_ref(stack_arg_indexes[i] * 8) +
                ", xmm0",
              )
            } else {
              let stack_offset = stack_arg_indexes[i] * 8
              if mir_body_codegen_int128_type(expected_types[i]) {
                self.emit(
                  "\tmov\trax, QWORD PTR " +
                  x64_mem_at_reg(raw_base_reg, raw_offset),
                )
                self.emit(
                  "\tmov\tQWORD PTR " + x64_rsp_ref(stack_offset) + ", rax",
                )
                self.emit(
                  "\tmov\trax, QWORD PTR " +
                  x64_mem_at_reg(raw_base_reg, raw_offset + 8),
                )
                self.emit(
                  "\tmov\tQWORD PTR " + x64_rsp_ref(stack_offset + 8) + ", rax",
                )
              } else {
                self.emit(
                  "\tmov\trax, QWORD PTR " +
                  x64_mem_at_reg(raw_base_reg, raw_offset),
                )
                self.emit(
                  "\tmov\tQWORD PTR " + x64_rsp_ref(stack_offset) + ", rax",
                )
              }
            }
          }
        }
        for i in 0..<source_indexes.length() {
          let raw_offset = mir_body_codegen_raw_arg_offset(
            raw_sizes, i, raw_offset_base,
          )
          if mir_body_codegen_abi_fp_type(expected_types[i]) {
            if fp_arg_indexes[i] >= 0 {
              let suffix = x64_fp_suffix(expected_types[i])
              let size = if suffix == "ss" { "DWORD" } else { "QWORD" }
              self.emit(
                "\tmov" +
                suffix +
                "\t" +
                fp_arg_regs[fp_arg_indexes[i]] +
                ", " +
                size +
                " PTR " +
                x64_mem_at_reg(raw_base_reg, raw_offset),
              )
            }
          } else if arg_is_aggregate[i] && stack_arg_indexes[i] < 0 {
            let mut int_cursor = int_arg_indexes[i]
            let mut fp_cursor = fp_arg_indexes[i]
            for word in 0..<arg_words[i] {
              let width = self.aggregate_word_width(expected_types[i], word)
              match arg_classes[i][word] {
                IntClass => {
                  self.emit_load_int_bytes_from_mem_reg(
                    arg_regs[int_cursor],
                    raw_base_reg,
                    raw_offset + word * 8,
                    width,
                  )
                  int_cursor += 1
                }
                SseClass => {
                  self.emit_load_sse_word_from_mem_reg(
                    fp_arg_regs[fp_cursor],
                    raw_base_reg,
                    raw_offset + word * 8,
                    width,
                  )
                  fp_cursor += 1
                }
              }
            }
          } else if int_arg_indexes[i] >= 0 {
            if mir_body_codegen_int128_type(expected_types[i]) {
              self.emit(
                "\tmov\t" +
                arg_regs[int_arg_indexes[i]] +
                ", QWORD PTR " +
                x64_mem_at_reg(raw_base_reg, raw_offset),
              )
              self.emit(
                "\tmov\t" +
                arg_regs[int_arg_indexes[i] + 1] +
                ", QWORD PTR " +
                x64_mem_at_reg(raw_base_reg, raw_offset + 8),
              )
            } else {
              self.emit(
                "\tmov\t" +
                arg_regs[int_arg_indexes[i]] +
                ", QWORD PTR " +
                x64_mem_at_reg(raw_base_reg, raw_offset),
              )
            }
          }
        }
        let fp_reg_count = if fp_arg_index > 8 { 8 } else { fp_arg_index }
        self.emit("\tmov\tal, " + fp_reg_count.to_string())
      } else {
        let arg_regs = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
        let fp_arg_regs : ReadOnlyArray[String] = [
          "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7",
        ]
        let expected_types : Array[@ctype.Type] = []
        let int_arg_indexes : Array[Int] = []
        let fp_arg_indexes : Array[Int] = []
        let stack_arg_indexes : Array[Int] = []
        let arg_is_aggregate : Array[Bool] = []
        let arg_classes : Array[Array[X64AggregateClass]] = []
        let arg_words : Array[Int] = []
        let raw_sizes : Array[Int] = []
        let mut int_arg_index = if has_sret { 1 } else { 0 }
        let mut fp_arg_index = 0
        let mut stack_arg_index = 0
        let mut call_stack_align = 16
        for i in 0..<source_indexes.length() {
          let arg = args[source_indexes[i]]
          let expected = self.mir_call_arg_type(name, i, arg.ty())
          expected_types.push(expected)
          if mir_body_codegen_abi_fp_type(expected) {
            arg_is_aggregate.push(false)
            arg_classes.push([])
            arg_words.push(1)
            raw_sizes.push(16)
            int_arg_indexes.push(-1)
            if fp_arg_index < fp_arg_regs.length() {
              fp_arg_indexes.push(fp_arg_index)
              stack_arg_indexes.push(-1)
            } else {
              fp_arg_indexes.push(-1)
              stack_arg_indexes.push(stack_arg_index)
              stack_arg_index += 1
            }
            fp_arg_index += 1
            self.gen_mir_value(arg, offsets)
            self.emit_mir_numeric_conversion(arg.ty(), expected)
            self.emit_mir_push_xmm0(expected)
          } else if peel_aligned_type(expected) is Struct(_) ||
            peel_aligned_type(expected) is Union(_) {
            let classes = match self.aggregate_classes(expected) {
              Some(classes) => classes
              None => []
            }
            let words = if classes.length() > 0 {
              classes.length()
            } else {
              self.aggregate_word_count(expected)
            }
            let raw_size = if classes.length() > 0 { 16 } else { words * 8 }
            let int_needed = x64_class_count(classes, IntClass)
            let fp_needed = x64_class_count(classes, SseClass)
            arg_is_aggregate.push(true)
            arg_classes.push(classes)
            arg_words.push(words)
            raw_sizes.push(raw_size)
            if classes.length() > 0 &&
              int_arg_index + int_needed <= arg_regs.length() &&
              fp_arg_index + fp_needed <= fp_arg_regs.length() {
              int_arg_indexes.push(int_arg_index)
              fp_arg_indexes.push(fp_arg_index)
              stack_arg_indexes.push(-1)
              int_arg_index += int_needed
              fp_arg_index += fp_needed
            } else {
              int_arg_indexes.push(-1)
              fp_arg_indexes.push(-1)
              let (aligned_stack_arg_index, aligned_call_stack_align) = self.align_call_stack_arg(
                stack_arg_index, call_stack_align, expected,
              )
              stack_arg_index = aligned_stack_arg_index
              call_stack_align = aligned_call_stack_align
              stack_arg_indexes.push(stack_arg_index)
              stack_arg_index += words
            }
            self.emit_mir_save_aggregate_call_arg_raw(
              arg, expected, raw_size, offsets,
            )
          } else {
            arg_is_aggregate.push(false)
            arg_classes.push([])
            let slots = mir_body_codegen_abi_int_slots(expected)
            arg_words.push(slots)
            raw_sizes.push(16)
            if int_arg_index + slots <= arg_regs.length() {
              int_arg_indexes.push(int_arg_index)
              stack_arg_indexes.push(-1)
            } else {
              int_arg_indexes.push(-1)
              let (aligned_stack_arg_index, aligned_call_stack_align) = self.align_call_stack_arg(
                stack_arg_index, call_stack_align, expected,
              )
              stack_arg_index = aligned_stack_arg_index
              call_stack_align = aligned_call_stack_align
              stack_arg_indexes.push(stack_arg_index)
              stack_arg_index += slots
            }
            fp_arg_indexes.push(-1)
            int_arg_index += slots
            self.gen_mir_value(arg, offsets)
            self.emit_mir_numeric_conversion(arg.ty(), expected)
            if mir_body_codegen_int128_type(expected) {
              self.emit_push_int128()
            } else {
              self.emit_mir_push_rax()
            }
          }
        }
        let mut raw_area = 0
        for size in raw_sizes {
          raw_area += size
        }
        let stack_area = x64_align_to(stack_arg_index * 8, call_stack_align)
        if stack_area > 0 {
          self.emit("\tsub\trsp, " + stack_area.to_string())
        }
        call_stack_cleanup = raw_area + stack_area
        for i in 0..<source_indexes.length() {
          if stack_arg_indexes[i] >= 0 {
            let raw_offset = mir_body_codegen_raw_arg_offset(
              raw_sizes, i, stack_area,
            )
            if arg_is_aggregate[i] {
              let stack_offset = stack_arg_indexes[i] * 8
              for word in 0..<arg_words[i] {
                let width = self.aggregate_word_width(expected_types[i], word)
                self.emit_load_int_bytes_from_mem_reg(
                  "rax",
                  "rsp",
                  raw_offset + word * 8,
                  width,
                )
                self.emit_store_int_bytes_to_mem_reg(
                  "rax",
                  "rsp",
                  stack_offset + word * 8,
                  width,
                )
              }
            } else if mir_body_codegen_abi_fp_type(expected_types[i]) {
              let suffix = x64_fp_suffix(expected_types[i])
              let size = if suffix == "ss" { "DWORD" } else { "QWORD" }
              self.emit(
                "\tmov" +
                suffix +
                "\txmm0, " +
                size +
                " PTR " +
                x64_rsp_ref(raw_offset),
              )
              self.emit(
                "\tmov" +
                suffix +
                "\t" +
                size +
                " PTR " +
                x64_rsp_ref(stack_arg_indexes[i] * 8) +
                ", xmm0",
              )
            } else {
              let stack_offset = stack_arg_indexes[i] * 8
              if mir_body_codegen_int128_type(expected_types[i]) {
                self.emit_mir_copy_int128_arg_from_raw_to_stack(
                  raw_offset, stack_offset,
                )
              } else {
                self.emit("\tmov\trax, QWORD PTR " + x64_rsp_ref(raw_offset))
                self.emit(
                  "\tmov\tQWORD PTR " + x64_rsp_ref(stack_offset) + ", rax",
                )
              }
            }
          }
        }
        for i in 0..<source_indexes.length() {
          let raw_offset = mir_body_codegen_raw_arg_offset(
            raw_sizes, i, stack_area,
          )
          if mir_body_codegen_abi_fp_type(expected_types[i]) {
            if fp_arg_indexes[i] >= 0 {
              let suffix = x64_fp_suffix(expected_types[i])
              let size = if suffix == "ss" { "DWORD" } else { "QWORD" }
              self.emit(
                "\tmov" +
                suffix +
                "\t" +
                fp_arg_regs[fp_arg_indexes[i]] +
                ", " +
                size +
                " PTR " +
                x64_rsp_ref(raw_offset),
              )
            }
          } else if arg_is_aggregate[i] && stack_arg_indexes[i] < 0 {
            let mut int_cursor = int_arg_indexes[i]
            let mut fp_cursor = fp_arg_indexes[i]
            for word in 0..<arg_words[i] {
              let width = self.aggregate_word_width(expected_types[i], word)
              match arg_classes[i][word] {
                IntClass => {
                  self.emit_load_int_bytes_from_mem_reg(
                    arg_regs[int_cursor],
                    "rsp",
                    raw_offset + word * 8,
                    width,
                  )
                  int_cursor += 1
                }
                SseClass => {
                  self.emit_load_sse_word_from_mem_reg(
                    fp_arg_regs[fp_cursor],
                    "rsp",
                    raw_offset + word * 8,
                    width,
                  )
                  fp_cursor += 1
                }
              }
            }
          } else if int_arg_indexes[i] >= 0 {
            if mir_body_codegen_int128_type(expected_types[i]) {
              self.emit_mir_load_int128_arg_from_raw_to_regs(
                arg_regs,
                int_arg_indexes[i],
                raw_offset,
              )
            } else {
              self.emit(
                "\tmov\t" +
                arg_regs[int_arg_indexes[i]] +
                ", QWORD PTR " +
                x64_rsp_ref(raw_offset),
              )
            }
          }
        }
      }
      if has_sret {
        self.emit_call_sret_addr(ty)
      }
      self.emit("\tcall\t" + mir_body_codegen_direct_call_symbol(name))
      if dynamic_call_stack_align {
        self.emit(
          "\tmov\trsp, QWORD PTR " +
          x64_rsp_ref(dynamic_call_stack_restore_offset),
        )
      } else if call_stack_cleanup > 0 {
        self.emit("\tadd\trsp, " + call_stack_cleanup.to_string())
      }
      if self.is_supported_small_aggregate(ty) {
        ()
      } else if self.is_memory_aggregate(ty) {
        ()
      } else if !mir_body_codegen_abi_fp_type(ty) {
        self.emit_abi_int_return_conversion(ty)
      }
    }
    MirIndirectCall(callee, args, ty) => {
      self.gen_mir_value(callee, offsets)
      self.emit_mir_push_rax()
      let has_sret = self.is_memory_aggregate(ty)
      let arg_regs = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
      let fp_arg_regs : ReadOnlyArray[String] = [
        "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7",
      ]
      let expected_types : Array[@ctype.Type] = []
      let int_arg_indexes : Array[Int] = []
      let fp_arg_indexes : Array[Int] = []
      let stack_arg_indexes : Array[Int] = []
      let arg_is_aggregate : Array[Bool] = []
      let arg_classes : Array[Array[X64AggregateClass]] = []
      let arg_words : Array[Int] = []
      let raw_sizes : Array[Int] = []
      let mut int_arg_index = if has_sret { 1 } else { 0 }
      let mut fp_arg_index = 0
      let mut stack_arg_index = 0
      let mut call_stack_align = 16
      for i in 0..<args.length() {
        let arg = args[i]
        let expected = mir_indirect_call_arg_type(callee.ty(), i, arg.ty())
        expected_types.push(expected)
        if mir_body_codegen_abi_fp_type(expected) {
          arg_is_aggregate.push(false)
          arg_classes.push([])
          arg_words.push(1)
          raw_sizes.push(16)
          int_arg_indexes.push(-1)
          if fp_arg_index < fp_arg_regs.length() {
            fp_arg_indexes.push(fp_arg_index)
            stack_arg_indexes.push(-1)
          } else {
            fp_arg_indexes.push(-1)
            stack_arg_indexes.push(stack_arg_index)
            stack_arg_index += 1
          }
          fp_arg_index += 1
          self.gen_mir_value(arg, offsets)
          self.emit_mir_numeric_conversion(arg.ty(), expected)
          self.emit_mir_push_xmm0(expected)
        } else if peel_aligned_type(expected) is Struct(_) ||
          peel_aligned_type(expected) is Union(_) {
          let classes = match self.aggregate_classes(expected) {
            Some(classes) => classes
            None => []
          }
          let words = if classes.length() > 0 {
            classes.length()
          } else {
            self.aggregate_word_count(expected)
          }
          let raw_size = if classes.length() > 0 { 16 } else { words * 8 }
          let int_needed = x64_class_count(classes, IntClass)
          let fp_needed = x64_class_count(classes, SseClass)
          arg_is_aggregate.push(true)
          arg_classes.push(classes)
          arg_words.push(words)
          raw_sizes.push(raw_size)
          if classes.length() > 0 &&
            int_arg_index + int_needed <= arg_regs.length() &&
            fp_arg_index + fp_needed <= fp_arg_regs.length() {
            int_arg_indexes.push(int_arg_index)
            fp_arg_indexes.push(fp_arg_index)
            stack_arg_indexes.push(-1)
            int_arg_index += int_needed
            fp_arg_index += fp_needed
          } else {
            int_arg_indexes.push(-1)
            fp_arg_indexes.push(-1)
            let (aligned_stack_arg_index, aligned_call_stack_align) = self.align_call_stack_arg(
              stack_arg_index, call_stack_align, expected,
            )
            stack_arg_index = aligned_stack_arg_index
            call_stack_align = aligned_call_stack_align
            stack_arg_indexes.push(stack_arg_index)
            stack_arg_index += words
          }
          self.emit_mir_save_aggregate_call_arg_raw(
            arg, expected, raw_size, offsets,
          )
        } else {
          arg_is_aggregate.push(false)
          arg_classes.push([])
          let slots = mir_body_codegen_abi_int_slots(expected)
          arg_words.push(slots)
          raw_sizes.push(16)
          if int_arg_index + slots <= arg_regs.length() {
            int_arg_indexes.push(int_arg_index)
            stack_arg_indexes.push(-1)
          } else {
            int_arg_indexes.push(-1)
            let (aligned_stack_arg_index, aligned_call_stack_align) = self.align_call_stack_arg(
              stack_arg_index, call_stack_align, expected,
            )
            stack_arg_index = aligned_stack_arg_index
            call_stack_align = aligned_call_stack_align
            stack_arg_indexes.push(stack_arg_index)
            stack_arg_index += slots
          }
          fp_arg_indexes.push(-1)
          int_arg_index += slots
          self.gen_mir_value(arg, offsets)
          self.emit_mir_numeric_conversion(arg.ty(), expected)
          if mir_body_codegen_int128_type(expected) {
            self.emit_push_int128()
          } else {
            self.emit_mir_push_rax()
          }
        }
      }
      let mut raw_area = 16
      for size in raw_sizes {
        raw_area += size
      }
      let stack_area = x64_align_to(stack_arg_index * 8, call_stack_align)
      if stack_area > 0 {
        self.emit("\tsub\trsp, " + stack_area.to_string())
      }
      for i in 0..<args.length() {
        let raw_offset = mir_body_codegen_raw_arg_offset(
          raw_sizes, i, stack_area,
        )
        if stack_arg_indexes[i] >= 0 {
          if arg_is_aggregate[i] {
            let stack_offset = stack_arg_indexes[i] * 8
            for word in 0..<arg_words[i] {
              let width = self.aggregate_word_width(expected_types[i], word)
              self.emit_load_int_bytes_from_mem_reg(
                "rax",
                "rsp",
                raw_offset + word * 8,
                width,
              )
              self.emit_store_int_bytes_to_mem_reg(
                "rax",
                "rsp",
                stack_offset + word * 8,
                width,
              )
            }
          } else if mir_body_codegen_abi_fp_type(expected_types[i]) {
            let suffix = x64_fp_suffix(expected_types[i])
            let size = if suffix == "ss" { "DWORD" } else { "QWORD" }
            self.emit(
              "\tmov" +
              suffix +
              "\txmm0, " +
              size +
              " PTR " +
              x64_rsp_ref(raw_offset),
            )
            self.emit(
              "\tmov" +
              suffix +
              "\t" +
              size +
              " PTR " +
              x64_rsp_ref(stack_arg_indexes[i] * 8) +
              ", xmm0",
            )
          } else {
            let stack_offset = stack_arg_indexes[i] * 8
            if mir_body_codegen_int128_type(expected_types[i]) {
              self.emit_mir_copy_int128_arg_from_raw_to_stack(
                raw_offset, stack_offset,
              )
            } else {
              self.emit("\tmov\trax, QWORD PTR " + x64_rsp_ref(raw_offset))
              self.emit(
                "\tmov\tQWORD PTR " + x64_rsp_ref(stack_offset) + ", rax",
              )
            }
          }
        }
      }
      for i in 0..<args.length() {
        let raw_offset = mir_body_codegen_raw_arg_offset(
          raw_sizes, i, stack_area,
        )
        if mir_body_codegen_abi_fp_type(expected_types[i]) {
          if fp_arg_indexes[i] >= 0 {
            let suffix = x64_fp_suffix(expected_types[i])
            let size = if suffix == "ss" { "DWORD" } else { "QWORD" }
            self.emit(
              "\tmov" +
              suffix +
              "\t" +
              fp_arg_regs[fp_arg_indexes[i]] +
              ", " +
              size +
              " PTR " +
              x64_rsp_ref(raw_offset),
            )
          }
        } else if arg_is_aggregate[i] && stack_arg_indexes[i] < 0 {
          let mut int_cursor = int_arg_indexes[i]
          let mut fp_cursor = fp_arg_indexes[i]
          for word in 0..<arg_words[i] {
            let width = self.aggregate_word_width(expected_types[i], word)
            match arg_classes[i][word] {
              IntClass => {
                self.emit_load_int_bytes_from_mem_reg(
                  arg_regs[int_cursor],
                  "rsp",
                  raw_offset + word * 8,
                  width,
                )
                int_cursor += 1
              }
              SseClass => {
                self.emit_load_sse_word_from_mem_reg(
                  fp_arg_regs[fp_cursor],
                  "rsp",
                  raw_offset + word * 8,
                  width,
                )
                fp_cursor += 1
              }
            }
          }
        } else if int_arg_indexes[i] >= 0 {
          if mir_body_codegen_int128_type(expected_types[i]) {
            self.emit_mir_load_int128_arg_from_raw_to_regs(
              arg_regs,
              int_arg_indexes[i],
              raw_offset,
            )
          } else {
            self.emit(
              "\tmov\t" +
              arg_regs[int_arg_indexes[i]] +
              ", QWORD PTR " +
              x64_rsp_ref(raw_offset),
            )
          }
        }
      }
      if mir_indirect_call_variadic(callee.ty()) {
        let fp_reg_count = if fp_arg_index > 8 { 8 } else { fp_arg_index }
        self.emit("\tmov\tal, " + fp_reg_count.to_string())
      }
      self.emit(
        "\tmov\tr10, QWORD PTR " + x64_rsp_ref(stack_area + raw_area - 16),
      )
      if has_sret {
        self.emit_call_sret_addr(ty)
      }
      self.emit("\tcall\tr10")
      if raw_area + stack_area > 0 {
        self.emit("\tadd\trsp, " + (raw_area + stack_area).to_string())
      }
      if self.is_supported_small_aggregate(ty) {
        ()
      } else if self.is_memory_aggregate(ty) {
        ()
      } else if !mir_body_codegen_abi_fp_type(ty) {
        self.emit_abi_int_return_conversion(ty)
      }
    }
  }
}

///|
fn X64Codegen::emit_mir_cond_jump_false(
  self : X64Codegen,
  cond : @mir.MirValue,
  offsets : Map[Int, Int],
  false_label : String,
) -> Unit {
  self.gen_mir_value(cond, offsets)
  if x64_is_fp_type(cond.ty()) {
    self.emit_fp_cond_jump_false(cond.ty(), false_label)
  } else if mir_body_codegen_int128_type(cond.ty()) {
    self.emit("\tor\trax, rdx")
    self.emit("\tje\t" + false_label)
  } else {
    self.emit("\tcmp\trax, 0")
    self.emit("\tje\t" + false_label)
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
    if params.length() == 0 && !self.mir_direct_call_variadic(name) {
      return mir_body_default_argument_promoted_type(actual)
    }
  }
  if self.mir_direct_call_variadic(name) {
    return mir_body_default_argument_promoted_type(actual)
  }
  actual
}

///|
fn X64Codegen::gen_mir_int128_binary(
  self : X64Codegen,
  op : String,
  lhs : @mir.MirValue,
  rhs : @mir.MirValue,
  ty : @ctype.Type,
  offsets : Map[Int, Int],
) -> Unit {
  let left_ty = mir_body_binary_left_type(op, lhs.ty(), rhs.ty())
  let right_ty = mir_body_binary_right_type(op, lhs.ty(), rhs.ty())
  self.gen_mir_value(lhs, offsets)
  self.emit_mir_numeric_conversion(lhs.ty(), left_ty)
  self.emit_int_conversion_to(left_ty)
  self.emit_push_int128()
  self.gen_mir_value(rhs, offsets)
  self.emit_mir_numeric_conversion(rhs.ty(), right_ty)
  self.emit_int_conversion_to(right_ty)
  if op == "<<" || op == ">>" {
    self.emit("\tmov\tr10, rax")
    self.emit_pop_int128()
    self.emit("\tmov\trcx, r10")
    if op == "<<" {
      self.emit_int128_left_shift()
    } else {
      self.emit_int128_right_shift(is_unsigned_integer_type(left_ty))
    }
    self.emit_int_conversion_to(ty)
    return
  }
  self.emit("\tmov\tr10, rax")
  self.emit("\tmov\tr11, rdx")
  self.emit_pop_int128()
  match op {
    "+" => {
      self.emit("\tadd\trax, r10")
      self.emit("\tadc\trdx, r11")
    }
    "-" => {
      self.emit("\tsub\trax, r10")
      self.emit("\tsbb\trdx, r11")
    }
    "*" => {
      self.emit("\tmov\tr8, rax")
      self.emit("\tmov\tr9, rdx")
      self.emit("\tmov\trax, r8")
      self.emit("\tmul\tr10")
      self.emit("\timul\tr9, r10")
      self.emit("\tadd\trdx, r9")
      self.emit("\timul\tr11, r8")
      self.emit("\tadd\trdx, r11")
    }
    "/" =>
      self.emit_int128_libcall(
        if mir_body_unsigned_binary(op, lhs.ty(), rhs.ty()) {
          "__udivti3"
        } else {
          "__divti3"
        },
      )
    "%" =>
      self.emit_int128_libcall(
        if mir_body_unsigned_binary(op, lhs.ty(), rhs.ty()) {
          "__umodti3"
        } else {
          "__modti3"
        },
      )
    "&" => {
      self.emit("\tand\trax, r10")
      self.emit("\tand\trdx, r11")
    }
    "|" => {
      self.emit("\tor\trax, r10")
      self.emit("\tor\trdx, r11")
    }
    "^" => {
      self.emit("\txor\trax, r10")
      self.emit("\txor\trdx, r11")
    }
    "==" | "!=" | "<" | ">" | "<=" | ">=" =>
      self.emit_int128_compare(
        op,
        mir_body_unsigned_binary(op, lhs.ty(), rhs.ty()),
      )
    _ => abort("unsupported x86-64 MIR body int128 binary operator")
  }
  self.emit_int_conversion_to(ty)
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
    "alloca_align" => {
      self.gen_mir_value(lhs, offsets)
      self.emit_mir_push_rax()
      self.gen_mir_value(rhs, offsets)
      self.emit("\tmov\tr11, rax")
      self.emit_mir_pop_rax()
      self.emit("\tmov\tr10, rax")
      self.emit("\tshr\tr11, 3")
      self.emit("\tmov\trax, 16")
      self.emit("\tcmp\tr11, rax")
      self.emit("\tcmovb\tr11, rax")
      self.emit("\tmov\trax, r10")
      self.emit("\tadd\trax, 15")
      self.emit("\tand\trax, -16")
      self.emit("\tsub\trsp, rax")
      self.emit("\tsub\tr11, 1")
      self.emit("\tnot\tr11")
      self.emit("\tand\trsp, r11")
      self.emit("\tmov\trax, rsp")
      return
    }
    "&&" => {
      let false_label = self.new_label()
      let end_label = self.new_label()
      self.emit_mir_cond_jump_false(lhs, offsets, false_label)
      self.emit_mir_cond_jump_false(rhs, offsets, false_label)
      self.emit("\tmov\trax, 1")
      self.emit("\tjmp\t" + end_label)
      self.emit(false_label + ":")
      self.emit("\tmov\trax, 0")
      self.emit(end_label + ":")
      return
    }
    "||" => {
      let rhs_label = self.new_label()
      let false_label = self.new_label()
      let end_label = self.new_label()
      self.emit_mir_cond_jump_false(lhs, offsets, rhs_label)
      self.emit("\tmov\trax, 1")
      self.emit("\tjmp\t" + end_label)
      self.emit(rhs_label + ":")
      self.emit_mir_cond_jump_false(rhs, offsets, false_label)
      self.emit("\tmov\trax, 1")
      self.emit("\tjmp\t" + end_label)
      self.emit(false_label + ":")
      self.emit("\tmov\trax, 0")
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
        let scale = self.mir_pointer_element_scale(elem_ty)
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
            let scale = self.mir_pointer_element_scale(elem_ty)
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
  if mir_body_codegen_rotate_op_supported(op, lhs.ty(), rhs.ty(), ty) {
    self.emit_mir_rotate_op(op, lhs, rhs, ty, offsets)
    return
  }
  let left_ty = mir_body_binary_left_type(op, lhs.ty(), rhs.ty())
  let right_ty = mir_body_binary_right_type(op, lhs.ty(), rhs.ty())
  if mir_body_codegen_int128_type(left_ty) ||
    mir_body_codegen_int128_type(right_ty) ||
    mir_body_codegen_int128_type(ty) {
    self.gen_mir_int128_binary(op, lhs, rhs, ty, offsets)
    return
  }
  if mir_body_codegen_fp_compare_supported(op, lhs.ty(), rhs.ty(), ty) {
    let fp_ty = mir_body_codegen_fp_binary_type(lhs.ty(), rhs.ty(), ty)
    let suffix = x64_fp_suffix(fp_ty)
    self.gen_mir_value(lhs, offsets)
    self.emit_mir_numeric_conversion(lhs.ty(), fp_ty)
    self.emit("\tsub\trsp, 16")
    let size = if suffix == "ss" { "DWORD" } else { "QWORD" }
    self.emit("\tmov" + suffix + "\t" + size + " PTR [rsp], xmm0")
    self.gen_mir_value(rhs, offsets)
    self.emit_mir_numeric_conversion(rhs.ty(), fp_ty)
    self.emit("\tmov" + suffix + "\txmm1, xmm0")
    self.emit("\tmov" + suffix + "\txmm0, " + size + " PTR [rsp]")
    self.emit("\tadd\trsp, 16")
    self.emit("\tucomi" + suffix + "\txmm0, xmm1")
    self.emit_fp_compare_result(op)
    self.emit_int_conversion_to(ty)
    return
  }
  if mir_body_codegen_fp_copysign_supported(op, lhs.ty(), rhs.ty(), ty) {
    let fp_ty = mir_body_codegen_fp_binary_type(lhs.ty(), rhs.ty(), ty)
    self.gen_mir_value(lhs, offsets)
    self.emit_mir_numeric_conversion(lhs.ty(), fp_ty)
    match x64_core_type(fp_ty) {
      Float => {
        self.emit("\tmovd\tr11d, xmm0")
        self.emit("\tand\tr11d, 2147483647")
        self.emit("\tsub\trsp, 16")
        self.emit("\tmov\tQWORD PTR [rsp], r11")
        self.gen_mir_value(rhs, offsets)
        self.emit_mir_numeric_conversion(rhs.ty(), fp_ty)
        self.emit("\tmovd\teax, xmm0")
        self.emit("\tand\teax, -2147483648")
        self.emit("\tmov\tr11, QWORD PTR [rsp]")
        self.emit("\tadd\trsp, 16")
        self.emit("\tor\teax, r11d")
        self.emit("\tmovd\txmm0, eax")
      }
      _ => {
        self.emit("\tmovq\tr11, xmm0")
        self.emit("\tmovabs\tr10, 9223372036854775807")
        self.emit("\tand\tr11, r10")
        self.emit("\tsub\trsp, 16")
        self.emit("\tmov\tQWORD PTR [rsp], r11")
        self.gen_mir_value(rhs, offsets)
        self.emit_mir_numeric_conversion(rhs.ty(), fp_ty)
        self.emit("\tmovq\trax, xmm0")
        self.emit("\tmovabs\tr10, -9223372036854775808")
        self.emit("\tand\trax, r10")
        self.emit("\tmov\tr11, QWORD PTR [rsp]")
        self.emit("\tadd\trsp, 16")
        self.emit("\tor\trax, r11")
        self.emit("\tmovq\txmm0, rax")
      }
    }
    self.emit_mir_numeric_conversion(fp_ty, ty)
    self.emit_int_conversion_to(ty)
    return
  }
  if mir_body_codegen_fp_arith_supported(op, lhs.ty(), rhs.ty(), ty) {
    let fp_ty = mir_body_codegen_fp_binary_type(lhs.ty(), rhs.ty(), ty)
    let suffix = x64_fp_suffix(fp_ty)
    self.gen_mir_value(lhs, offsets)
    self.emit_mir_numeric_conversion(lhs.ty(), fp_ty)
    self.emit("\tsub\trsp, 16")
    let size = if suffix == "ss" { "DWORD" } else { "QWORD" }
    self.emit("\tmov" + suffix + "\t" + size + " PTR [rsp], xmm0")
    self.gen_mir_value(rhs, offsets)
    self.emit_mir_numeric_conversion(rhs.ty(), fp_ty)
    self.emit("\tmov" + suffix + "\txmm1, xmm0")
    self.emit("\tmov" + suffix + "\txmm0, " + size + " PTR [rsp]")
    self.emit("\tadd\trsp, 16")
    match op {
      "+" => self.emit("\tadd" + suffix + "\txmm0, xmm1")
      "-" => self.emit("\tsub" + suffix + "\txmm0, xmm1")
      "*" => self.emit("\tmul" + suffix + "\txmm0, xmm1")
      "/" => self.emit("\tdiv" + suffix + "\txmm0, xmm1")
      _ => abort("unsupported MIR body floating arithmetic operator")
    }
    self.emit_mir_numeric_conversion(fp_ty, ty)
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
      let unsigned = mir_body_unsigned_compare_binary(op, lhs.ty(), rhs.ty())
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
fn X64Codegen::gen_mir_aggregate_return_addr(
  self : X64Codegen,
  value : @mir.MirValue,
  offsets : Map[Int, Int],
) -> Unit {
  match value {
    MirLocal(binding) => self.emit_local_addr(offsets[binding.id])
    MirAggregateArg(addr, _) => self.gen_mir_value(addr, offsets)
    MirLoad(ptr, _) => self.gen_mir_value(ptr, offsets)
    MirCall(_, _, _) | MirIndirectCall(_, _, _) =>
      self.gen_mir_value(value, offsets)
    _ => abort("unsupported x86-64 MIR aggregate return source")
  }
}

///|
fn X64Codegen::emit_store_small_aggregate_return_to_local(
  self : X64Codegen,
  ty : @ctype.Type,
  offset : Int,
) -> Unit {
  self.emit("\tlea\tr10, " + self.local_ref(offset))
  self.emit_store_small_aggregate_return(ty)
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
          Some(value) =>
            match value {
              MirCall(_, _, _) | MirIndirectCall(_, _, _) =>
                if self.is_supported_small_aggregate(binding.ty) {
                  self.gen_mir_value(value, offsets)
                  self.emit_store_small_aggregate_return_to_local(
                    binding.ty,
                    offsets[binding.id],
                  )
                } else if self.is_memory_aggregate(binding.ty) {
                  self.gen_mir_value(value, offsets)
                  self.emit("\tmov\tr11, rax")
                  self.emit(
                    "\tlea\tr10, " + self.local_ref(offsets[binding.id]),
                  )
                  self.emit_copy_aggregate_from_addr(binding.ty)
                  self.emit("\tmov\trax, r10")
                } else {
                  self.gen_mir_value(value, offsets)
                  self.emit_mir_numeric_conversion(value.ty(), binding.ty)
                  self.emit_int_conversion_to(binding.ty)
                  self.emit_store_local_from_rax(
                    offsets[binding.id],
                    binding.ty,
                  )
                }
              _ => {
                self.gen_mir_value(value, offsets)
                self.emit_mir_numeric_conversion(value.ty(), binding.ty)
                self.emit_int_conversion_to(binding.ty)
                self.emit_store_local_from_rax(offsets[binding.id], binding.ty)
              }
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
          let ret_ty = self.func_rets[self.func_name]
          if self.is_supported_small_aggregate(ret_ty) {
            match value {
              MirCall(_, _, _) | MirIndirectCall(_, _, _) =>
                self.gen_mir_value(value, offsets)
              _ => {
                self.gen_mir_aggregate_return_addr(value, offsets)
                self.emit_load_small_aggregate_return(ret_ty)
              }
            }
          } else if self.is_memory_aggregate(ret_ty) {
            self.gen_mir_aggregate_return_addr(value, offsets)
            self.emit("\tmov\tr11, rax")
            self.emit(
              "\tmov\tr10, QWORD PTR " + self.local_ref(self.sret_dest_offset),
            )
            self.emit_copy_aggregate_from_addr(ret_ty)
            self.emit("\tmov\trax, r10")
          } else {
            self.gen_mir_value(value, offsets)
            self.emit_mir_numeric_conversion(value.ty(), ret_ty)
            self.emit_int_conversion_to(ret_ty)
          }
        }
        None => self.emit("\tmov\trax, 0")
      }
      self.emit("\tjmp\t.L" + self.func_name + "_ret")
    }
    MirIf(cond, then_, else_) => {
      let else_label = self.new_label()
      let end_label = self.new_label()
      self.emit_mir_cond_jump_false(cond, offsets, else_label)
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
      self.emit_mir_cond_jump_false(cond, offsets, end_label)
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
      self.emit_mir_cond_jump_false(cond, offsets, end_label)
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
      if x64_is_fp_type(cond.ty()) {
        self.emit_mir_cond_jump_false(cond, offsets, end_label)
        self.emit("\tjmp\t" + start_label)
      } else {
        self.gen_mir_value(cond, offsets)
        self.emit("\tcmp\trax, 0")
        self.emit("\tjne\t" + start_label)
      }
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
    MirComputedGoto(value) => {
      self.gen_mir_value(value, offsets)
      self.emit("\tjmp\trax")
    }
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
  self.sret_dest_offset = -1
  self.sret_scratch_offset = -1
  self.sret_scratch_size = 0
  self.sret_scratch_align = 1
  self.va_arg_scratch_offset = -1
  self.va_arg_scratch_size = 0
  self.va_arg_scratch_align = 1
  self.break_label = None
  self.continue_label = None
  self.emitted_labels = {}
  self.defined_labels = {}
  let offsets = self.mir_body_offsets(body)
  let has_sret = self.is_memory_aggregate(decl.ret)
  if has_sret {
    self.sret_dest_offset = self.alloc_local(
      "__kimicc_mir_sret_dest",
      Pointer(Void),
    )
  }
  if decl.variadic {
    let (gp_offset, fp_offset, overflow_offset) = x64_compute_mir_va_initial_offsets(
      body.params,
      if has_sret {
        1
      } else {
        0
      },
    )
    self.va_initial_gp_offset = gp_offset
    self.va_initial_fp_offset = fp_offset
    self.va_initial_overflow_offset = overflow_offset
    self.va_reg_save_offset = self.alloc_local(
      "__kimicc_va_reg_save",
      Array(UChar, 176),
    )
  }
  let frame_align = if self.stack_align > 16 { self.stack_align } else { 16 }
  let frame_size = x64_align_to(self.stack_size, frame_align)
  let realign_frame = frame_align > 16
  if realign_frame {
    self.local_base_reg = "r12"
  }
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
  if realign_frame {
    self.emit("\tpush\tr12")
    self.emit("\tand\trsp, -" + frame_align.to_string())
  }
  if frame_size > 0 {
    self.emit("\tsub\trsp, " + frame_size.to_string())
  }
  if realign_frame {
    self.emit("\tlea\tr12, " + x64_mem_at_reg("rsp", frame_size))
  }
  if self.sret_dest_offset >= 0 {
    self.emit(
      "\tmov\tQWORD PTR " + self.local_ref(self.sret_dest_offset) + ", rdi",
    )
  }
  self.emit_mir_save_variadic_registers()
  let arg_regs : ReadOnlyArray[String] = [
    "rdi", "rsi", "rdx", "rcx", "r8", "r9",
  ]
  let fp_arg_regs : ReadOnlyArray[String] = [
    "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7",
  ]
  let mut int_arg_index = if has_sret { 1 } else { 0 }
  let mut fp_arg_index = 0
  let mut stack_arg_index = 0
  let mut call_stack_align = 16
  for i in 0..<body.params.length() {
    let param = body.params[i]
    if mir_body_codegen_abi_fp_type(param.ty) {
      if fp_arg_index < fp_arg_regs.length() {
        self.emit_store_fp_reg_to_local(
          fp_arg_regs[fp_arg_index],
          offsets[param.id],
          param.ty,
        )
      } else {
        let suffix = x64_fp_suffix(param.ty)
        let size = if suffix == "ss" { "DWORD" } else { "QWORD" }
        self.emit(
          "\tmov" +
          suffix +
          "\txmm0, " +
          size +
          " PTR [rbp + " +
          (16 + stack_arg_index * 8).to_string() +
          "]",
        )
        self.emit_store_fp_reg_to_local("xmm0", offsets[param.id], param.ty)
        stack_arg_index += 1
      }
      fp_arg_index += 1
    } else if peel_aligned_type(param.ty) is Struct(_) ||
      peel_aligned_type(param.ty) is Union(_) {
      let classes = match self.aggregate_classes(param.ty) {
        Some(classes) => classes
        None => []
      }
      let words = if classes.length() > 0 {
        classes.length()
      } else {
        self.aggregate_word_count(param.ty)
      }
      let int_needed = x64_class_count(classes, IntClass)
      let fp_needed = x64_class_count(classes, SseClass)
      if classes.length() > 0 &&
        int_arg_index + int_needed <= arg_regs.length() &&
        fp_arg_index + fp_needed <= fp_arg_regs.length() {
        self.emit_mir_store_aggregate_param_from_regs(
          param.ty,
          offsets[param.id],
          classes,
          int_arg_index,
          fp_arg_index,
        )
        int_arg_index += int_needed
        fp_arg_index += fp_needed
      } else {
        let (aligned_stack_arg_index, aligned_call_stack_align) = self.align_call_stack_arg(
          stack_arg_index,
          call_stack_align,
          param.ty,
        )
        stack_arg_index = aligned_stack_arg_index
        call_stack_align = aligned_call_stack_align
        self.emit_mir_copy_aggregate_param_from_stack(
          param.ty,
          offsets[param.id],
          stack_arg_index,
        )
        stack_arg_index += words
      }
    } else if mir_body_codegen_int128_type(param.ty) {
      if int_arg_index + 2 <= arg_regs.length() {
        self.emit("\tmov\trax, " + arg_regs[int_arg_index])
        self.emit("\tmov\trdx, " + arg_regs[int_arg_index + 1])
        self.emit_store_local_from_rax(offsets[param.id], param.ty)
      } else {
        let (aligned_stack_arg_index, aligned_call_stack_align) = self.align_call_stack_arg(
          stack_arg_index,
          call_stack_align,
          param.ty,
        )
        stack_arg_index = aligned_stack_arg_index
        call_stack_align = aligned_call_stack_align
        self.emit(
          "\tmov\trax, QWORD PTR [rbp + " +
          (16 + stack_arg_index * 8).to_string() +
          "]",
        )
        self.emit(
          "\tmov\trdx, QWORD PTR [rbp + " +
          (16 + (stack_arg_index + 1) * 8).to_string() +
          "]",
        )
        self.emit_store_local_from_rax(offsets[param.id], param.ty)
        stack_arg_index += 2
      }
      int_arg_index += 2
    } else {
      if int_arg_index < arg_regs.length() {
        self.emit_store_int_reg_to_local(
          arg_regs[int_arg_index],
          offsets[param.id],
        )
      } else {
        self.emit(
          "\tmov\trax, QWORD PTR [rbp + " +
          (16 + stack_arg_index * 8).to_string() +
          "]",
        )
        self.emit_store_int_reg_to_local("rax", offsets[param.id])
        stack_arg_index += 1
      }
      int_arg_index += 1
    }
  }
  self.gen_mir_stmts(body.body, offsets)
  self.emit("\tmov\trax, 0")
  self.emit(".L" + decl.name + "_ret:")
  if realign_frame {
    self.emit("\tmov\tr12, QWORD PTR [rbp - 8]")
  }
  self.emit("\tmov\trsp, rbp")
  self.emit("\tpop\trbp")
  self.emit("\tret")
  self.emit("\t.size\t" + decl.name + ", .-" + decl.name)
}
