///|
fn mir_body_local_name(binding : @mir.MirLocal) -> String {
  "__mir_" + binding.id.to_string() + "_" + binding.name
}

///|
fn mir_body_codegen_scalar_type(ty : @parser.Type) -> Bool {
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
    | Pointer(_)
    | FuncPtr(_, _, _) => true
    Atomic(inner) => mir_body_codegen_scalar_type(inner)
    _ => false
  }
}

///|
fn mir_body_codegen_local_type(ty : @parser.Type) -> Bool {
  match ty {
    Aligned(_, _) => false
    Array(elem, _) => mir_body_codegen_scalar_type(elem)
    Struct(_) | Union(_) => true
    _ => mir_body_codegen_scalar_type(ty)
  }
}

///|
fn mir_body_codegen_value_supported(
  value : @mir.MirValue,
  int_arg_limit : Int,
  mir : @mir.Program,
) -> Bool {
  if !mir_body_codegen_scalar_type(value.ty()) {
    return false
  }
  match value {
    MirConst(_, ty) => mir_body_codegen_scalar_type(ty)
    MirLocal(binding) => mir_body_codegen_scalar_type(binding.ty)
    MirAddrLocal(binding) => mir_body_codegen_local_type(binding.ty)
    MirElemAddr(base, index, elem_ty) =>
      mir_body_codegen_scalar_type(elem_ty) &&
      mir_body_codegen_value_supported(base, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(index, int_arg_limit, mir)
    MirOffsetAddr(base, _, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(base, int_arg_limit, mir)
    MirLoad(ptr, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(ptr, int_arg_limit, mir)
    MirUnary(_, inner, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(inner, int_arg_limit, mir)
    MirBinary(_, lhs, rhs, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(lhs, int_arg_limit, mir) &&
      mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
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
      mir_body_codegen_value_supported(rhs, int_arg_limit, mir)
    MirTernary(cond, then_, else_, ty) =>
      mir_body_codegen_scalar_type(ty) &&
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
  }
}

///|
fn mir_body_codegen_call_supported(
  name : String,
  args : Array[@mir.MirValue],
  ret : @parser.Type,
  int_arg_limit : Int,
  mir : @mir.Program,
) -> Bool {
  if name.has_prefix("__") ||
    args.length() > int_arg_limit ||
    !mir_body_codegen_scalar_type(ret) {
    return false
  }
  if mir.bodies.contains(name) {
    return true
  }
  if !mir.funcs.contains(name) {
    return false
  }
  let sig = mir.funcs[name]
  if sig.defined || sig.variadic || !mir_body_codegen_scalar_type(sig.ret) {
    return false
  }
  if sig.params.length() != args.length() {
    return false
  }
  if sig.params.length() > int_arg_limit {
    return false
  }
  for ty in sig.params {
    if !mir_body_codegen_scalar_type(ty) {
      return false
    }
  }
  true
}

///|
fn mir_body_codegen_stmt_supported(
  stmt : @mir.MirStmt,
  int_arg_limit : Int,
  mir : @mir.Program,
) -> Bool {
  match stmt {
    MirDeclare(binding, init) => {
      if !mir_body_codegen_local_type(binding.ty) {
        return false
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
  mir : @mir.Program,
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
  decl : @parser.FuncDecl,
  int_arg_limit : Int,
  mir : @mir.Program,
) -> Bool {
  if decl.variadic || body.params.length() > int_arg_limit {
    return false
  }
  if !mir_body_codegen_scalar_type(body.ret) {
    return false
  }
  for binding in body.params {
    if !mir_body_codegen_scalar_type(binding.ty) {
      return false
    }
  }
  for binding in body.locals {
    if !mir_body_codegen_local_type(binding.ty) {
      return false
    }
  }
  mir_body_codegen_stmts_supported(body.body, int_arg_limit, mir)
}

///|
fn mir_body_binary_left_type(
  op : String,
  lhs : @parser.Type,
  rhs : @parser.Type,
) -> @parser.Type {
  if op == "<<" || op == ">>" {
    unary_integer_result_type(lhs)
  } else {
    integer_common_type(lhs, rhs)
  }
}

///|
fn mir_body_binary_right_type(
  op : String,
  lhs : @parser.Type,
  rhs : @parser.Type,
) -> @parser.Type {
  if op == "<<" || op == ">>" {
    unary_integer_result_type(rhs)
  } else {
    integer_common_type(lhs, rhs)
  }
}

///|
fn mir_body_binary_common_type(
  op : String,
  lhs : @parser.Type,
  rhs : @parser.Type,
) -> @parser.Type {
  if op == "<<" || op == ">>" {
    unary_integer_result_type(lhs)
  } else {
    integer_common_type(lhs, rhs)
  }
}

///|
fn mir_body_unsigned_binary(
  op : String,
  lhs : @parser.Type,
  rhs : @parser.Type,
) -> Bool {
  is_unsigned_integer_type(mir_body_binary_common_type(op, lhs, rhs))
}

///|
fn Codegen::mir_body_offsets(
  self : Codegen,
  body : @mir.MirFuncBody,
) -> Map[Int, Int] {
  let offsets : Map[Int, Int] = {}
  for binding in body.locals {
    offsets[binding.id] = self.alloc_local(
      mir_body_local_name(binding),
      binding.ty,
    )
  }
  offsets
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
    MirElemAddr(base, index, elem_ty) => {
      self.gen_mir_value(base, offsets, frame_size)
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
      self.emit_scalar_conversion_to(ty)
    }
    MirAssignLocal(binding, rhs) => {
      self.gen_mir_value(rhs, offsets, frame_size)
      self.emit_scalar_conversion_to(binding.ty)
      self.emit_store_local("x9", offsets[binding.id], frame_size)
    }
    MirStore(ptr, rhs, ty) => {
      self.gen_mir_value(ptr, offsets, frame_size)
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.gen_mir_value(rhs, offsets, frame_size)
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
      for i in 0..<args.length() {
        let arg = args[i]
        self.gen_mir_value(arg, offsets, frame_size)
        let expected = self.mir_call_arg_type(name, i, arg.ty())
        self.emit_numeric_conversion(arg.ty(), expected)
        self.emit_scalar_conversion_to(expected)
        self.emit("\tstr\tx9, [sp, #-16]!")
      }
      for i = args.length() - 1; i >= 0; i = i - 1 {
        self.emit("\tldr\tx" + i.to_string() + ", [sp], #16")
      }
      self.emit("\tbl\t_" + name)
      self.emit("\tmov\tx9, x0")
      self.emit_mir_abi_int_return_conversion(ty)
    }
  }
}

///|
fn Codegen::mir_call_arg_type(
  self : Codegen,
  name : String,
  index : Int,
  actual : @parser.Type,
) -> @parser.Type {
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
  ty : @parser.Type,
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
  ty : @parser.Type,
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
  let left_ty = mir_body_binary_left_type(op, lhs.ty(), rhs.ty())
  let right_ty = mir_body_binary_right_type(op, lhs.ty(), rhs.ty())
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
    "-" => self.emit("\tsub\tx9, x10, x9")
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
      match init {
        Some(value) => {
          self.gen_mir_value(value, offsets, frame_size)
          self.emit_scalar_conversion_to(binding.ty)
          self.emit_store_local("x9", offsets[binding.id], frame_size)
        }
        None => ()
      }
    MirExprStmt(value) => self.gen_mir_value(value, offsets, frame_size)
    MirReturn(value) => {
      match value {
        Some(value) => {
          self.gen_mir_value(value, offsets, frame_size)
          self.emit_scalar_conversion_to(self.func_rets[self.func_name])
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
fn Codegen::try_gen_mir_func(self : Codegen, decl : @parser.FuncDecl) -> Bool {
  match self.mir {
    Some(mir) =>
      if mir.bodies.contains(decl.name) {
        let body = mir.bodies[decl.name]
        if !mir_body_codegen_func_supported(body, decl, 8, mir) {
          return false
        }
        self.gen_mir_func(decl, body)
        true
      } else {
        false
      }
    None => false
  }
}

///|
fn Codegen::gen_mir_func(
  self : Codegen,
  decl : @parser.FuncDecl,
  body : @mir.MirFuncBody,
) -> Unit {
  self.local_offsets = {}
  self.var_types = {}
  self.stack_size = 0
  self.emitted_labels = {}
  self.defined_labels = {}
  self.fp_literals = []
  self.func_name = decl.name
  self.func_params = decl.params
  self.sret_dest_offset = -1
  self.sret_scratch_offset = -1
  self.sret_scratch_size = 0
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
    offsets[binding.id] = self.alloc_local(
      mir_body_local_name(binding),
      binding.ty,
    )
  }
  offsets
}

///|
fn X64Codegen::gen_mir_value(
  self : X64Codegen,
  value : @mir.MirValue,
  offsets : Map[Int, Int],
) -> Unit {
  match value {
    MirConst(bits, ty) => {
      self.emit_load_mir_int(bits)
      self.emit_int_conversion_to(ty)
    }
    MirLocal(binding) => {
      self.emit_local_addr(offsets[binding.id])
      self.emit_load_indirect(binding.ty)
    }
    MirAddrLocal(binding) => self.emit_local_addr(offsets[binding.id])
    MirElemAddr(base, index, elem_ty) => {
      self.gen_mir_value(base, offsets)
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
      self.emit_int_conversion_to(ty)
    }
    MirAssignLocal(binding, rhs) => {
      self.gen_mir_value(rhs, offsets)
      self.emit_int_conversion_to(binding.ty)
      self.emit_store_local_from_rax(offsets[binding.id], binding.ty)
    }
    MirStore(ptr, rhs, ty) => {
      self.gen_mir_value(ptr, offsets)
      self.emit_mir_push_rax()
      self.gen_mir_value(rhs, offsets)
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
      for i in 0..<args.length() {
        let arg = args[i]
        self.gen_mir_value(arg, offsets)
        self.emit_int_conversion_to(self.mir_call_arg_type(name, i, arg.ty()))
        self.emit_mir_push_rax()
      }
      let arg_regs = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
      for i = args.length() - 1; i >= 0; i = i - 1 {
        self.emit("\tmov\t" + arg_regs[i] + ", QWORD PTR [rsp]")
        self.emit("\tadd\trsp, 16")
      }
      self.emit("\tcall\t" + name)
      self.emit_abi_int_return_conversion(ty)
    }
  }
}

///|
fn X64Codegen::mir_call_arg_type(
  self : X64Codegen,
  name : String,
  index : Int,
  actual : @parser.Type,
) -> @parser.Type {
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
  ty : @parser.Type,
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
  let left_ty = mir_body_binary_left_type(op, lhs.ty(), rhs.ty())
  let right_ty = mir_body_binary_right_type(op, lhs.ty(), rhs.ty())
  self.gen_mir_value(lhs, offsets)
  self.emit_int_conversion_to(left_ty)
  self.emit_mir_push_rax()
  self.gen_mir_value(rhs, offsets)
  self.emit_int_conversion_to(right_ty)
  self.emit("\tmov\tr10, rax")
  self.emit_mir_pop_rax()
  match op {
    "+" => self.emit("\tadd\trax, r10")
    "-" => self.emit("\tsub\trax, r10")
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
      match init {
        Some(value) => {
          self.gen_mir_value(value, offsets)
          self.emit_int_conversion_to(binding.ty)
          self.emit_store_local_from_rax(offsets[binding.id], binding.ty)
        }
        None => ()
      }
    MirExprStmt(value) => self.gen_mir_value(value, offsets)
    MirReturn(value) => {
      match value {
        Some(value) => {
          self.gen_mir_value(value, offsets)
          self.emit_int_conversion_to(self.func_rets[self.func_name])
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
fn X64Codegen::try_gen_mir_func(
  self : X64Codegen,
  decl : @parser.FuncDecl,
) -> Bool {
  match self.mir {
    Some(mir) =>
      if mir.bodies.contains(decl.name) {
        let body = mir.bodies[decl.name]
        if !mir_body_codegen_func_supported(body, decl, 6, mir) {
          return false
        }
        self.gen_mir_func(decl, body)
        true
      } else {
        false
      }
    None => false
  }
}

///|
fn X64Codegen::gen_mir_func(
  self : X64Codegen,
  decl : @parser.FuncDecl,
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
