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
fn mir_body_codegen_value_supported(value : @mir.MirValue) -> Bool {
  if !mir_body_codegen_scalar_type(value.ty()) {
    return false
  }
  match value {
    MirConst(_, ty) => mir_body_codegen_scalar_type(ty)
    MirLocal(binding) => mir_body_codegen_scalar_type(binding.ty)
    MirUnary(_, inner, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(inner)
    MirBinary(_, lhs, rhs, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(lhs) &&
      mir_body_codegen_value_supported(rhs)
    MirCast(ty, inner) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(inner)
    MirAssignLocal(binding, rhs) =>
      mir_body_codegen_scalar_type(binding.ty) &&
      mir_body_codegen_value_supported(rhs)
    MirTernary(cond, then_, else_, ty) =>
      mir_body_codegen_scalar_type(ty) &&
      mir_body_codegen_value_supported(cond) &&
      mir_body_codegen_value_supported(then_) &&
      mir_body_codegen_value_supported(else_)
    // Keep the first production migration slice call-free. Calls need ABI
    // argument staging and stack-alignment coverage for both backends.
    MirCall(_, _, _) => false
  }
}

///|
fn mir_body_codegen_stmt_supported(stmt : @mir.MirStmt) -> Bool {
  match stmt {
    MirDeclare(binding, init) => {
      if !mir_body_codegen_scalar_type(binding.ty) {
        return false
      }
      match init {
        Some(value) => mir_body_codegen_value_supported(value)
        None => true
      }
    }
    MirExprStmt(value) => mir_body_codegen_value_supported(value)
    MirReturn(value) =>
      match value {
        Some(value) => mir_body_codegen_value_supported(value)
        None => true
      }
    MirIf(cond, then_, else_) =>
      mir_body_codegen_value_supported(cond) &&
      mir_body_codegen_stmts_supported(then_) &&
      mir_body_codegen_stmts_supported(else_)
    MirWhile(cond, body) =>
      mir_body_codegen_value_supported(cond) &&
      mir_body_codegen_stmts_supported(body)
    MirBlock(stmts) => mir_body_codegen_stmts_supported(stmts)
  }
}

///|
fn mir_body_codegen_stmts_supported(stmts : Array[@mir.MirStmt]) -> Bool {
  for stmt in stmts {
    if !mir_body_codegen_stmt_supported(stmt) {
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
) -> Bool {
  if decl.variadic || body.params.length() > int_arg_limit {
    return false
  }
  if !mir_body_codegen_scalar_type(body.ret) {
    return false
  }
  for binding in body.locals {
    if !mir_body_codegen_scalar_type(binding.ty) {
      return false
    }
  }
  mir_body_codegen_stmts_supported(body.body)
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
    MirCall(_, _, _) => abort("unsupported MIR body call")
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
      self.emit(start_label + ":")
      self.gen_mir_value(cond, offsets, frame_size)
      self.emit("\tcbz\tx9, " + end_label)
      self.gen_mir_stmts(body, offsets, frame_size)
      self.emit("\tb\t" + start_label)
      self.emit(end_label + ":")
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
        if !mir_body_codegen_func_supported(body, decl, 8) {
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
    MirCall(_, _, _) => abort("unsupported MIR body call")
  }
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
  self.emit_push_rax()
  self.gen_mir_value(rhs, offsets)
  self.emit_int_conversion_to(right_ty)
  self.emit("\tmov\tr10, rax")
  self.emit_pop_rax()
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
      self.emit(start_label + ":")
      self.gen_mir_value(cond, offsets)
      self.emit("\tcmp\trax, 0")
      self.emit("\tje\t" + end_label)
      self.gen_mir_stmts(body, offsets)
      self.emit("\tjmp\t" + start_label)
      self.emit(end_label + ":")
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
        if !mir_body_codegen_func_supported(body, decl, 6) {
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
