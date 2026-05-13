///|
fn peel_aligned_type(ty : @parser.Type) -> @parser.Type {
  match ty {
    Aligned(inner, _) => peel_aligned_type(inner)
    _ => ty
  }
}

///|
fn aggregate_owner_name(ty : @parser.Type) -> String? {
  match peel_aligned_type(ty) {
    Struct(n) | Union(n) => Some(n)
    _ => None
  }
}

///|
fn array_element_type(ty : @parser.Type) -> @parser.Type? {
  match peel_aligned_type(ty) {
    Array(elem, _) => Some(elem)
    _ => None
  }
}

///|
fn pointer_or_array_element_type(ty : @parser.Type) -> @parser.Type? {
  match peel_aligned_type(ty) {
    Pointer(elem) | Array(elem, _) => Some(elem)
    _ => None
  }
}

///|
fn address_value_type(ty : @parser.Type) -> Bool {
  match peel_aligned_type(ty) {
    Array(_, _) | Struct(_) | Union(_) => true
    _ => false
  }
}

///|
fn number_literal_type(value : Int64) -> @parser.Type {
  if value < -2147483648L || value > 2147483647L {
    SLongLong
  } else {
    SInt
  }
}

///|
fn Codegen::type_of(
  self : Codegen,
  expr : @parser.Expr,
  frame_size : Int,
) -> @parser.Type {
  match expr {
    Number(value) => number_literal_type(value)
    FloatLiteral(_) => Double
    String(_) => Pointer(SChar)
    Var(name) =>
      if self.var_types.contains(name) {
        self.var_types[name]
      } else if self.globals.contains(name) {
        self.globals[name].ty
      } else if self.func_rets.contains(name) {
        FuncPtr(
          self.func_rets[name],
          self.func_param_types.get_or_default(name, []),
          self.func_variadic.get_or_default(name, false),
        )
      } else {
        SInt
      }
    Binary(op, lhs, rhs) => {
      let lhs_ty = self.type_of(lhs, frame_size)
      let rhs_ty = self.type_of(rhs, frame_size)
      let lhs_core = peel_aligned_type(lhs_ty)
      let rhs_core = peel_aligned_type(rhs_ty)
      // Pointer arithmetic
      match (lhs_core, rhs_core) {
        (Pointer(_), Pointer(_))
        | (Array(_, _), Pointer(_))
        | (Pointer(_), Array(_, _))
        | (Array(_, _), Array(_, _)) => if op == "-" { return SLong }
        (Pointer(elem), _) =>
          // ptr + int → ptr, ptr - int → ptr
          if (op == "+" || op == "-") && rhs_ty.is_integer() {
            return Pointer(elem)
          }
        (Array(elem, _), _) =>
          // array + int follows normal array-to-pointer decay
          if (op == "+" || op == "-") && rhs_ty.is_integer() {
            return Pointer(elem)
          }
        (_, Pointer(elem)) =>
          // int + ptr → ptr
          if op == "+" && lhs_ty.is_integer() {
            return Pointer(elem)
          }
        (_, Array(elem, _)) =>
          // int + array follows normal array-to-pointer decay
          if op == "+" && lhs_ty.is_integer() {
            return Pointer(elem)
          }
        _ => ()
      }
      binary_expr_result_type(op, lhs, lhs_ty, rhs, rhs_ty)
    }
    Unary("-", operand) =>
      unary_numeric_result_type(self.type_of(operand, frame_size))
    Unary("+", operand) =>
      unary_numeric_result_type(self.type_of(operand, frame_size))
    Unary("!", _) => SInt
    Unary("~", operand) =>
      unary_integer_result_type(self.type_of(operand, frame_size))
    Call(func, _) => self.call_return_type(func, frame_size)
    Assign(_, rhs) => self.type_of(rhs, frame_size)
    CompoundAssign(_, lhs, _) => self.type_of(lhs, frame_size)
    MemberAccess(obj, field) => {
      let obj_ty = self.type_of(obj, frame_size)
      let struct_name = match aggregate_owner_name(obj_ty) {
        Some(n) => n
        None => return SInt
      }
      if self.struct_layouts.contains(struct_name) {
        let fields = self.struct_layouts[struct_name]
        for f in fields {
          if f.0 == field {
            return f.1
          }
        }
      }
      SInt
    }
    Deref(ptr) =>
      match peel_aligned_type(self.type_of(ptr, frame_size)) {
        Pointer(ty) => ty
        FuncPtr(ret, params, variadic) => FuncPtr(ret, params, variadic)
        Array(elem, _) => elem
        _ => SInt
      }
    AddrOf(e) => Pointer(self.type_of(e, frame_size))
    ArrayAccess(arr, _) =>
      match pointer_or_array_element_type(self.type_of(arr, frame_size)) {
        Some(elem) => elem
        None => SInt
      }
    Sizeof(_) => SInt
    SizeofExpr(_) => SInt
    Alignof(_) => SInt
    AlignofExpr(_) => SInt
    PrefixInc(e) => self.type_of(e, frame_size)
    PrefixDec(e) => self.type_of(e, frame_size)
    PostfixInc(e) => self.type_of(e, frame_size)
    PostfixDec(e) => self.type_of(e, frame_size)
    Ternary(_, then_, else_) =>
      ternary_result_type(
        self.type_of(then_, frame_size),
        self.type_of(else_, frame_size),
      )
    LabelAddr(_) => Pointer(Void)
    VaArg(_, ty) => ty
    OffsetOf(_, _) => SInt
    // CommaExpr is not in the AST, comma expressions are flattened into nested Binary(",", ...)
    Cast(ty, _) => ty
    Array(_) => SInt
    CompoundLiteral(ty, _, _) => ty
    DesignatedField(_, e) => self.type_of(e, frame_size)
    DesignatedIndex(_, e) => self.type_of(e, frame_size)
    DesignatedRange(_, _, e) => self.type_of(e, frame_size)
    _ => SInt
  }
}

///|
fn ternary_result_type(
  then_ty : @parser.Type,
  else_ty : @parser.Type,
) -> @parser.Type {
  match (peel_aligned_type(then_ty), peel_aligned_type(else_ty)) {
    (Array(elem, _), _) => Pointer(elem)
    (_, Array(elem, _)) => Pointer(elem)
    (Pointer(elem), _) => Pointer(elem)
    (_, Pointer(elem)) => Pointer(elem)
    (FuncPtr(ret, params, variadic), _) => FuncPtr(ret, params, variadic)
    (_, FuncPtr(ret, params, variadic)) => FuncPtr(ret, params, variadic)
    _ =>
      if then_ty.is_floating() || else_ty.is_floating() {
        if peel_aligned_type(then_ty) == Double ||
          peel_aligned_type(else_ty) == Double {
          Double
        } else {
          Float
        }
      } else if then_ty.is_integer() && else_ty.is_integer() {
        integer_common_type(then_ty, else_ty)
      } else {
        then_ty
      }
  }
}

///|
fn is_unsigned_integer_type(ty : @parser.Type) -> Bool {
  match ty {
    UChar | UShort | UInt | ULong | ULongLong | UInt128 => true
    _ => false
  }
}

///|
fn is_int128_type(ty : @parser.Type) -> Bool {
  match ty {
    SInt128 | UInt128 => true
    _ => false
  }
}

///|
fn needs_int128_integer_op(
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
) -> Bool {
  lhs_ty.is_integer() &&
  rhs_ty.is_integer() &&
  is_int128_type(integer_common_type(lhs_ty, rhs_ty))
}

///|
fn Codegen::emit_numeric_conversion(
  self : Codegen,
  src : @parser.Type,
  dst : @parser.Type,
) -> Unit {
  if src == dst {
    return
  }
  match (src, dst) {
    (src, Bool) => if is_int128_type(src) { self.emit("\torr\tx9, x9, x10") }
    (src, Double) =>
      if src.is_integer() {
        if is_unsigned_integer_type(src) {
          self.emit("\tucvtf\td9, x9")
        } else {
          self.emit("\tscvtf\td9, x9")
        }
        self.emit("\tfmov\tx9, d9")
      } else if src == Float {
        self.emit("\tfmov\ts9, w9")
        self.emit("\tfcvt\td9, s9")
        self.emit("\tfmov\tx9, d9")
      }
    (src, Float) =>
      if src.is_integer() {
        if is_unsigned_integer_type(src) {
          self.emit("\tucvtf\ts9, x9")
        } else {
          self.emit("\tscvtf\ts9, x9")
        }
        self.emit("\tfmov\tw9, s9")
      } else if src == Double {
        self.emit("\tfmov\td9, x9")
        self.emit("\tfcvt\ts9, d9")
        self.emit("\tfmov\tw9, s9")
      }
    (Double, dst) =>
      if dst.is_integer() {
        self.emit("\tfmov\td9, x9")
        if dst.is_signed() {
          self.emit("\tfcvtzs\tx9, d9")
        } else {
          self.emit("\tfcvtzu\tx9, d9")
        }
      }
    (Float, dst) =>
      if dst.is_integer() {
        self.emit("\tfmov\ts9, w9")
        if dst.is_signed() {
          self.emit("\tfcvtzs\tx9, s9")
        } else {
          self.emit("\tfcvtzu\tx9, s9")
        }
      }
    (src, SInt128) | (src, UInt128) =>
      if src.is_integer() && !is_int128_type(src) {
        if src.is_signed() {
          self.emit("\tasr\tx10, x9, #63")
        } else {
          self.emit("\tmov\tx10, #0")
        }
      }
    _ => ()
  }
}

///|
fn Codegen::emit_scalar_conversion_to(
  self : Codegen,
  ty : @parser.Type,
) -> Unit {
  match ty {
    Bool => {
      self.emit("\tcmp\tx9, #0")
      self.emit("\tcset\tx9, ne")
    }
    SChar => self.emit("\tsxtb\tx9, w9")
    UChar => self.emit("\tand\tx9, x9, #0xFF")
    SShort => self.emit("\tsxth\tx9, w9")
    UShort => self.emit("\tand\tx9, x9, #0xFFFF")
    SInt => self.emit("\tsxtw\tx9, w9")
    UInt => self.emit("\tand\tx9, x9, #0xFFFFFFFF")
    SInt128 | UInt128 => ()
    Atomic(inner) => self.emit_scalar_conversion_to(inner)
    Aligned(inner, _) => self.emit_scalar_conversion_to(inner)
    _ => ()
  }
}

///|
fn atomic_target_type(ty : @parser.Type) -> @parser.Type {
  match ty {
    Pointer(Atomic(inner)) | Array(Atomic(inner), _) => inner
    Pointer(Aligned(inner, _)) | Array(Aligned(inner, _), _) => inner
    Pointer(inner) | Array(inner, _) => inner
    Atomic(inner) | Aligned(inner, _) => inner
    _ => SLongLong
  }
}

///|
fn Codegen::emit_atomic_update_loop(
  self : Codegen,
  op : String,
  elem_ty : @parser.Type,
  return_new : Bool,
) -> Unit {
  let loop_label = self.new_label()
  let byte_width = self.type_size(elem_ty)
  self.emit(loop_label + ":")
  if byte_width == 1 {
    self.emit("\tldaxrb\tw9, [x0]")
    self.emit_atomic_update_op(op, "w11", "w9", "w10")
    self.emit("\tstlxrb\tw12, w11, [x0]")
  } else if byte_width == 2 {
    self.emit("\tldaxrh\tw9, [x0]")
    self.emit_atomic_update_op(op, "w11", "w9", "w10")
    self.emit("\tstlxrh\tw12, w11, [x0]")
  } else if byte_width == 4 {
    self.emit("\tldaxr\tw9, [x0]")
    self.emit_atomic_update_op(op, "w11", "w9", "w10")
    self.emit("\tstlxr\tw12, w11, [x0]")
  } else {
    self.emit("\tldaxr\tx9, [x0]")
    self.emit_atomic_update_op(op, "x11", "x9", "x10")
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
fn Codegen::emit_atomic_update_op(
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
    _ => self.emit("\tmov\t" + dst + ", " + old)
  }
}

///|
fn Codegen::emit_atomic_update(
  self : Codegen,
  args : Array[@parser.Expr],
  frame_size : Int,
  op : String,
  return_new : Bool,
) -> Unit {
  if args.length() >= 2 {
    let elem_ty = atomic_target_type(self.type_of(args[0], frame_size))
    self.gen_expr(args[0], frame_size)
    self.emit("\tstr\tx9, [sp, #-16]!")
    self.gen_expr(args[1], frame_size)
    self.emit_numeric_conversion(self.type_of(args[1], frame_size), elem_ty)
    self.emit_scalar_conversion_to(elem_ty)
    if self.type_size(elem_ty) == 8 {
      self.emit("\tmov\tx10, x9")
    } else {
      self.emit("\tmov\tw10, w9")
    }
    self.emit("\tldr\tx0, [sp], #16")
    self.emit_atomic_update_loop(op, elem_ty, return_new)
  } else {
    self.emit("\tmov\tx9, #0")
  }
}

///|
fn Codegen::emit_atomic_exchange(
  self : Codegen,
  args : Array[@parser.Expr],
  frame_size : Int,
) -> Unit {
  if args.length() >= 2 {
    let elem_ty = atomic_target_type(self.type_of(args[0], frame_size))
    let byte_width = self.type_size(elem_ty)
    self.gen_expr(args[0], frame_size)
    self.emit("\tstr\tx9, [sp, #-16]!")
    self.gen_expr(args[1], frame_size)
    self.emit_numeric_conversion(self.type_of(args[1], frame_size), elem_ty)
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
  } else {
    self.emit("\tmov\tx9, #0")
  }
}

///|
fn Codegen::emit_atomic_compare_exchange(
  self : Codegen,
  args : Array[@parser.Expr],
  frame_size : Int,
) -> Unit {
  if args.length() >= 3 {
    let elem_ty = atomic_target_type(self.type_of(args[0], frame_size))
    let byte_width = self.type_size(elem_ty)
    self.gen_expr(args[0], frame_size)
    self.emit("\tstr\tx9, [sp, #-16]!")
    self.gen_expr(args[1], frame_size)
    self.emit("\tstr\tx9, [sp, #-16]!")
    self.gen_expr(args[2], frame_size)
    self.emit_numeric_conversion(self.type_of(args[2], frame_size), elem_ty)
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
  } else {
    self.emit("\tmov\tx9, #0")
  }
}

///|
fn Codegen::emit_darwin_fd_helper(
  self : Codegen,
  args : Array[@parser.Expr],
  frame_size : Int,
  op : String,
) -> Unit {
  if args.length() >= 2 {
    self.gen_expr(args[0], frame_size)
    self.emit("\tstr\tx9, [sp, #-16]!")
    self.gen_expr(args[1], frame_size)
    self.emit("\tmov\tx10, x9")
    self.emit("\tldr\tx9, [sp], #16")
    self.emit("\tand\tx11, x9, #31")
    self.emit("\tmov\tx12, #1")
    self.emit("\tlsl\tx12, x12, x11")
    self.emit("\tlsr\tx11, x9, #5")
    self.emit("\tadd\tx10, x10, x11, lsl #2")
    self.emit("\tldr\tw13, [x10]")
    match op {
      "set" => {
        self.emit("\torr\tw13, w13, w12")
        self.emit("\tstr\tw13, [x10]")
        self.emit("\tmov\tx9, #0")
      }
      "clr" => {
        self.emit("\tbic\tw13, w13, w12")
        self.emit("\tstr\tw13, [x10]")
        self.emit("\tmov\tx9, #0")
      }
      _ => {
        self.emit("\tand\tw9, w13, w12")
        self.emit("\tcmp\tw9, #0")
        self.emit("\tcset\tx9, ne")
      }
    }
  } else {
    self.emit("\tmov\tx9, #0")
  }
}

///|
fn Codegen::emit_sp_offset_addr(
  self : Codegen,
  reg : String,
  offset : Int,
) -> Unit {
  if offset == 0 {
    self.emit("\tmov\t" + reg + ", sp")
  } else if offset <= 4095 {
    self.emit("\tadd\t" + reg + ", sp, #" + offset.to_string())
  } else {
    self.emit_load_int(reg, offset.to_int64())
    self.emit("\tadd\t" + reg + ", sp, " + reg)
  }
}

///|
fn Codegen::emit_copy_large_arg_to_call_area(
  self : Codegen,
  arg : @parser.Expr,
  ty : @parser.Type,
  frame_size : Int,
  dest_offset : Int,
) -> Unit {
  self.gen_aggregate_addr(arg, frame_size)
  self.emit("\tmov\tx1, x9")
  self.emit_sp_offset_addr("x0", dest_offset)
  self.emit_load_int("x2", self.type_size(ty).to_int64())
  self.emit("\tbl\t_memcpy")
  self.emit_sp_offset_addr("x9", dest_offset)
}

///|
fn Codegen::emit_save_small_aggregate_arg_to_stack(
  self : Codegen,
  arg : @parser.Expr,
  ty : @parser.Type,
  frame_size : Int,
  dest_offset : Int,
) -> Unit {
  let size = self.type_size(ty)
  match arg {
    Call(_, _) => {
      self.gen_expr(arg, frame_size)
      self.emit("\tstr\tx0, [sp, #" + dest_offset.to_string() + "]")
      if size > 8 {
        self.emit("\tstr\tx1, [sp, #" + (dest_offset + 8).to_string() + "]")
      }
    }
    MemberAccess(_, _) =>
      match self.emit_member_addr(arg, frame_size) {
        Some(info) => {
          self.emit("\tldr\tx10, [x9]")
          if size > 8 {
            self.emit("\tldr\tx11, [x9, #8]")
          }
          if info.stack_temp_size > 0 {
            self.emit("\tadd\tsp, sp, #" + info.stack_temp_size.to_string())
          }
          self.emit("\tstr\tx10, [sp, #" + dest_offset.to_string() + "]")
          if size > 8 {
            self.emit(
              "\tstr\tx11, [sp, #" + (dest_offset + 8).to_string() + "]",
            )
          }
        }
        None => {
          self.gen_aggregate_addr(arg, frame_size)
          self.emit("\tldr\tx10, [x9]")
          self.emit("\tstr\tx10, [sp, #" + dest_offset.to_string() + "]")
          if size > 8 {
            self.emit("\tldr\tx10, [x9, #8]")
            self.emit(
              "\tstr\tx10, [sp, #" + (dest_offset + 8).to_string() + "]",
            )
          }
        }
      }
    _ => {
      self.gen_aggregate_addr(arg, frame_size)
      self.emit("\tldr\tx10, [x9]")
      self.emit("\tstr\tx10, [sp, #" + dest_offset.to_string() + "]")
      if size > 8 {
        self.emit("\tldr\tx10, [x9, #8]")
        self.emit("\tstr\tx10, [sp, #" + (dest_offset + 8).to_string() + "]")
      }
    }
  }
}

///|
fn Codegen::emit_call_sret_addr(
  self : Codegen,
  ret_ty : @parser.Type,
  frame_size : Int,
) -> Unit {
  let offset = if self.pending_sret_offset >= 0 {
    self.pending_sret_offset
  } else if self.is_indirect_aggregate(ret_ty) {
    self.sret_scratch_offset
  } else {
    -1
  }
  if offset >= 0 {
    self.emit_local_addr(offset, frame_size)
    self.emit("\tmov\tx8, x9")
  }
}

///|
fn Codegen::declared_call_arg_type(
  self : Codegen,
  func : @parser.Expr,
  index : Int,
  actual : @parser.Type,
  named_count_limit : Int?,
  frame_size : Int,
) -> @parser.Type {
  match named_count_limit {
    Some(limit) => if index >= limit { return actual }
    None => ()
  }
  match self.type_of(func, frame_size) {
    FuncPtr(_, param_types, variadic) => {
      if variadic && index >= param_types.length() {
        return actual
      }
      if !variadic && param_types.length() == 0 {
        return actual
      }
      if index < param_types.length() {
        return param_types[index]
      }
    }
    _ => ()
  }
  match func {
    Var(name) =>
      if self.func_param_types.contains(name) {
        let param_types = self.func_param_types[name]
        if index < param_types.length() {
          param_types[index]
        } else {
          actual
        }
      } else {
        actual
      }
    _ => actual
  }
}

///|
fn Codegen::emit_call_arg_conversion(
  self : Codegen,
  actual : @parser.Type,
  expected : @parser.Type,
) -> Unit {
  if actual != expected {
    self.emit_numeric_conversion(actual, expected)
    self.emit_scalar_conversion_to(expected)
  }
}

///|
fn Codegen::call_return_type(
  self : Codegen,
  func : @parser.Expr,
  frame_size : Int,
) -> @parser.Type {
  match self.type_of(func, frame_size) {
    FuncPtr(ret, _, _) => ret
    _ =>
      match func {
        Var(name) =>
          match name {
            "__builtin_fabsf"
            | "__builtin_nanf"
            | "__builtin_huge_valf"
            | "__builtin_inff" => Float
            "__builtin_fabs"
            | "__builtin_nan"
            | "__builtin_huge_val"
            | "__builtin_inf" => Double
            "__builtin_fabsl"
            | "__builtin_nanl"
            | "__builtin_huge_vall"
            | "__builtin_infl" => LongDouble
            "__builtin_rotateleft32" | "__builtin_rotateright32" => UInt
            "__builtin_rotateleft64" | "__builtin_rotateright64" => ULongLong
            "__builtin_object_size" | "__builtin_dynamic_object_size" => ULong
            "__builtin_flt_rounds" => SInt
            _ => self.func_rets.get_or_default(name, SInt)
          }
        _ => SInt
      }
  }
}

///|
fn Codegen::emit_call_result(self : Codegen, ret_ty : @parser.Type) -> Unit {
  match ret_ty {
    Float => self.emit("\tfmov\tw9, s0")
    Double | LongDouble => self.emit("\tfmov\tx9, d0")
    SInt128 | UInt128 => {
      self.emit("\tmov\tx9, x0")
      self.emit("\tmov\tx10, x1")
    }
    _ => self.emit("\tmov\tx9, x0")
  }
}

///|
fn unary_integer_result_type(ty : @parser.Type) -> @parser.Type {
  match ty {
    Bool | SChar | UChar | SShort | UShort => SInt
    _ => ty
  }
}

///|
fn unary_numeric_result_type(ty : @parser.Type) -> @parser.Type {
  if ty.is_floating() {
    ty
  } else {
    unary_integer_result_type(ty)
  }
}

///|
fn integer_rank(ty : @parser.Type) -> Int {
  match ty {
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt => 3
    SLong | ULong => 4
    SLongLong | ULongLong => 5
    SInt128 | UInt128 => 6
    _ => 0
  }
}

///|
fn unsigned_type_for_rank(rank : Int) -> @parser.Type {
  if rank >= 6 {
    UInt128
  } else if rank == 5 {
    ULongLong
  } else if rank == 4 {
    ULong
  } else {
    UInt
  }
}

///|
fn signed_type_for_rank(rank : Int) -> @parser.Type {
  if rank >= 6 {
    SInt128
  } else if rank == 5 {
    SLongLong
  } else if rank == 4 {
    SLong
  } else {
    SInt
  }
}

///|
fn integer_width_bits(ty : @parser.Type) -> Int {
  match ty {
    Bool | SChar | UChar => 8
    SShort | UShort => 16
    SInt | UInt => 32
    SLong | ULong | SLongLong | ULongLong => 64
    SInt128 | UInt128 => 128
    _ => 0
  }
}

///|
fn bitfield_mask(width : Int) -> Int64 {
  if width >= 64 {
    -1L
  } else {
    (1L << width) - 1L
  }
}

///|
fn integer_common_type(
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
) -> @parser.Type {
  let lhs_ty = unary_integer_result_type(lhs_ty)
  let rhs_ty = unary_integer_result_type(rhs_ty)
  if lhs_ty == rhs_ty {
    return lhs_ty
  }
  let lhs_unsigned = is_unsigned_integer_type(lhs_ty)
  let rhs_unsigned = is_unsigned_integer_type(rhs_ty)
  let lhs_rank = integer_rank(lhs_ty)
  let rhs_rank = integer_rank(rhs_ty)
  if lhs_unsigned == rhs_unsigned {
    let rank = if lhs_rank > rhs_rank { lhs_rank } else { rhs_rank }
    if lhs_unsigned {
      unsigned_type_for_rank(rank)
    } else {
      signed_type_for_rank(rank)
    }
  } else {
    let unsigned_ty = if lhs_unsigned { lhs_ty } else { rhs_ty }
    let signed_ty = if lhs_unsigned { rhs_ty } else { lhs_ty }
    let unsigned_rank = integer_rank(unsigned_ty)
    let signed_rank = integer_rank(signed_ty)
    if unsigned_rank >= signed_rank {
      unsigned_ty
    } else if integer_width_bits(signed_ty) > integer_width_bits(unsigned_ty) {
      signed_ty
    } else {
      unsigned_type_for_rank(signed_rank)
    }
  }
}

///|
fn uses_unsigned_integer_op(
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
) -> Bool {
  lhs_ty.is_integer() &&
  rhs_ty.is_integer() &&
  is_unsigned_integer_type(integer_common_type(lhs_ty, rhs_ty))
}

///|
fn Codegen::emit_integer_compare(
  self : Codegen,
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
  is_ptr_diff : Bool,
) -> Unit {
  if !is_ptr_diff &&
    lhs_ty.is_integer() &&
    rhs_ty.is_integer() &&
    self.type_size(integer_common_type(lhs_ty, rhs_ty)) <= 4 {
    self.emit("\tcmp\tw9, w10")
  } else {
    self.emit("\tcmp\tx9, x10")
  }
}

///|
fn binary_result_type(
  op : String,
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
) -> @parser.Type {
  match op {
    "==" | "!=" | "<" | ">" | "<=" | ">=" | "&&" | "||" => SInt
    "," => rhs_ty
    "<<" | ">>" => unary_integer_result_type(lhs_ty)
    _ =>
      if lhs_ty.is_floating() || rhs_ty.is_floating() {
        if lhs_ty == Double || rhs_ty == Double {
          Double
        } else {
          Float
        }
      } else if lhs_ty.is_integer() && rhs_ty.is_integer() {
        integer_common_type(lhs_ty, rhs_ty)
      } else {
        SInt
      }
  }
}

///|
fn binary_expr_result_type(
  op : String,
  lhs : @parser.Expr,
  lhs_ty : @parser.Type,
  rhs : @parser.Expr,
  rhs_ty : @parser.Type,
) -> @parser.Type {
  if op == "<<" || op == ">>" {
    match (lhs, rhs) {
      (Number(_), Number(shift)) => if shift >= 32L { return ULongLong }
      _ => ()
    }
  }
  binary_result_type(op, lhs_ty, rhs_ty)
}

///|
fn binary_needs_scalar_result_conversion(op : String) -> Bool {
  match op {
    "+" | "-" | "*" | "/" | "%" => true
    _ => false
  }
}

///|
fn Codegen::gen_compound_assign(
  self : Codegen,
  op : String,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
  frame_size : Int,
) -> Unit {
  match self.find_bitfield_member(lhs, frame_size) {
    Some(info) => {
      self.gen_bitfield_compound_assign(op, lhs, rhs, info, frame_size)
      return
    }
    None => ()
  }
  let lhs_ty = self.type_of(lhs, frame_size)
  let rhs_ty = self.type_of(rhs, frame_size)
  let lhs_core = peel_aligned_type(lhs_ty)
  let rhs_core = peel_aligned_type(rhs_ty)
  let ptr_scale = match (lhs_core, rhs_core) {
    (Pointer(elem), _) => self.type_size(elem)
    (Array(elem, _), _) => self.type_size(elem)
    (_, Pointer(elem)) => self.type_size(elem)
    (_, Array(elem, _)) => self.type_size(elem)
    _ => 1
  }
  let has_ptr_operand = match (lhs_core, rhs_core) {
    (Pointer(_), _) | (Array(_, _), _) | (_, Pointer(_)) | (_, Array(_, _)) =>
      true
    _ => false
  }
  let scale_right = match lhs_core {
    Pointer(_) | Array(_, _) => (op == "+" || op == "-") && rhs_ty.is_integer()
    _ => false
  }
  let is_fp = !has_ptr_operand && (lhs_ty.is_floating() || rhs_ty.is_floating())
  let is_double = is_fp && (lhs_ty == Double || rhs_ty == Double)
  let fp_ty : @parser.Type = if is_double { Double } else { Float }
  let result_ty = binary_result_type(op, lhs_ty, rhs_ty)
  let is_unsigned_int = match op {
    "<<" | ">>" => is_unsigned_integer_type(result_ty)
    _ => uses_unsigned_integer_op(lhs_ty, rhs_ty)
  }

  self.gen_addr(lhs, frame_size)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.emit_load_typed("x9", "x9", lhs_ty)
  if is_fp {
    self.emit_numeric_conversion(lhs_ty, fp_ty)
  }
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_expr(rhs, frame_size)
  if is_fp {
    self.emit_numeric_conversion(rhs_ty, fp_ty)
  }
  if ptr_scale > 1 && scale_right {
    self.emit("\tmov\tx11, #" + ptr_scale.to_string())
    self.emit("\tmul\tx9, x9, x11")
  }
  self.emit("\tmov\tx10, x9")
  self.emit("\tldr\tx9, [sp], #16")
  match op {
    "+" =>
      if is_fp {
        if is_double {
          self.emit("\tfmov\td9, x9")
          self.emit("\tfmov\td10, x10")
          self.emit("\tfadd\td9, d9, d10")
          self.emit("\tfmov\tx9, d9")
        } else {
          self.emit("\tfmov\ts9, w9")
          self.emit("\tfmov\ts10, w10")
          self.emit("\tfadd\ts9, s9, s10")
          self.emit("\tfmov\tw9, s9")
        }
      } else {
        self.emit("\tadd\tx9, x9, x10")
      }
    "-" =>
      if is_fp {
        if is_double {
          self.emit("\tfmov\td9, x9")
          self.emit("\tfmov\td10, x10")
          self.emit("\tfsub\td9, d9, d10")
          self.emit("\tfmov\tx9, d9")
        } else {
          self.emit("\tfmov\ts9, w9")
          self.emit("\tfmov\ts10, w10")
          self.emit("\tfsub\ts9, s9, s10")
          self.emit("\tfmov\tw9, s9")
        }
      } else {
        self.emit("\tsub\tx9, x9, x10")
      }
    "*" =>
      if is_fp {
        if is_double {
          self.emit("\tfmov\td9, x9")
          self.emit("\tfmov\td10, x10")
          self.emit("\tfmul\td9, d9, d10")
          self.emit("\tfmov\tx9, d9")
        } else {
          self.emit("\tfmov\ts9, w9")
          self.emit("\tfmov\ts10, w10")
          self.emit("\tfmul\ts9, s9, s10")
          self.emit("\tfmov\tw9, s9")
        }
      } else {
        self.emit("\tmul\tx9, x9, x10")
      }
    "/" =>
      if is_fp {
        if is_double {
          self.emit("\tfmov\td9, x9")
          self.emit("\tfmov\td10, x10")
          self.emit("\tfdiv\td9, d9, d10")
          self.emit("\tfmov\tx9, d9")
        } else {
          self.emit("\tfmov\ts9, w9")
          self.emit("\tfmov\ts10, w10")
          self.emit("\tfdiv\ts9, s9, s10")
          self.emit("\tfmov\tw9, s9")
        }
      } else if is_unsigned_int {
        self.emit("\tudiv\tx9, x9, x10")
      } else {
        self.emit("\tsdiv\tx9, x9, x10")
      }
    "%" =>
      if is_unsigned_int {
        self.emit("\tudiv\tx11, x9, x10\n\tmsub\tx9, x11, x10, x9")
      } else {
        self.emit("\tsdiv\tx11, x9, x10\n\tmsub\tx9, x11, x10, x9")
      }
    "&" => self.emit("\tand\tx9, x9, x10")
    "|" => self.emit("\torr\tx9, x9, x10")
    "^" => self.emit("\teor\tx9, x9, x10")
    "<<" => self.emit("\tlsl\tx9, x9, x10")
    ">>" =>
      if is_unsigned_int {
        self.emit("\tlsr\tx9, x9, x10")
      } else {
        self.emit("\tasr\tx9, x9, x10")
      }
    _ => ()
  }
  if is_fp {
    self.emit_numeric_conversion(fp_ty, lhs_ty)
  } else if !has_ptr_operand {
    self.emit_scalar_conversion_to(lhs_ty)
  }
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.emit("\tldr\tx10, [sp, #16]")
  self.emit_store_typed("x9", "x10", lhs_ty)
  self.emit("\tldr\tx9, [sp], #16")
  self.emit("\tadd\tsp, sp, #16")
}

///|
fn Codegen::find_bitfield_member(
  self : Codegen,
  expr : @parser.Expr,
  frame_size : Int,
) -> MemberAddrInfo? {
  match expr {
    MemberAccess(obj, field) => {
      let obj_ty = self.type_of(obj, frame_size)
      match aggregate_owner_name(obj_ty) {
        Some(struct_name) =>
          match self.find_field_layout(struct_name, field) {
            Some((_, ty, _, size, bit_offset, bit_width)) =>
              if bit_width > 0 {
                Some({ ty, size, bit_offset, bit_width, stack_temp_size: 0 })
              } else {
                None
              }
            None => None
          }
        None => None
      }
    }
    _ => None
  }
}

///|
fn Codegen::gen_bitfield_compound_assign(
  self : Codegen,
  op : String,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
  info : MemberAddrInfo,
  frame_size : Int,
) -> Unit {
  let lhs_ty = info.ty
  let rhs_ty = self.type_of(rhs, frame_size)
  let is_unsigned_int = match op {
    "<<" | ">>" => is_unsigned_integer_type(lhs_ty)
    _ => uses_unsigned_integer_op(lhs_ty, rhs_ty)
  }
  let mask = bitfield_mask(info.bit_width)
  self.gen_addr(lhs, frame_size)
  self.emit("\tstr\tx9, [sp, #-16]!")
  match info.size {
    1 => self.emit("\tldrb\tw9, [x9]")
    2 => self.emit("\tldrh\tw9, [x9]")
    4 => self.emit("\tldr\tw9, [x9]")
    _ => self.emit("\tldr\tx9, [x9]")
  }
  self.emit("\tlsr\tx9, x9, #" + info.bit_offset.to_string())
  self.emit_load_int("x10", mask)
  self.emit("\tand\tx9, x9, x10")
  if lhs_ty.is_signed() {
    let shift = 64 - info.bit_width
    self.emit("\tlsl\tx9, x9, #" + shift.to_string())
    self.emit("\tasr\tx9, x9, #" + shift.to_string())
  }
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_expr(rhs, frame_size)
  self.emit_numeric_conversion(rhs_ty, lhs_ty)
  self.emit_scalar_conversion_to(lhs_ty)
  self.emit("\tmov\tx10, x9")
  self.emit("\tldr\tx9, [sp], #16")
  match op {
    "+" => self.emit("\tadd\tx9, x9, x10")
    "-" => self.emit("\tsub\tx9, x9, x10")
    "*" => self.emit("\tmul\tx9, x9, x10")
    "/" =>
      if is_unsigned_int {
        self.emit("\tudiv\tx9, x9, x10")
      } else {
        self.emit("\tsdiv\tx9, x9, x10")
      }
    "%" =>
      if is_unsigned_int {
        self.emit("\tudiv\tx11, x9, x10\n\tmsub\tx9, x11, x10, x9")
      } else {
        self.emit("\tsdiv\tx11, x9, x10\n\tmsub\tx9, x11, x10, x9")
      }
    "&" => self.emit("\tand\tx9, x9, x10")
    "|" => self.emit("\torr\tx9, x9, x10")
    "^" => self.emit("\teor\tx9, x9, x10")
    "<<" => self.emit("\tlsl\tx9, x9, x10")
    ">>" =>
      if is_unsigned_int {
        self.emit("\tlsr\tx9, x9, x10")
      } else {
        self.emit("\tasr\tx9, x9, x10")
      }
    _ => ()
  }
  self.emit_scalar_conversion_to(lhs_ty)
  self.emit_load_int("x10", mask)
  self.emit("\tand\tx9, x9, x10")
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.emit("\tldr\tx10, [sp, #16]")
  match info.size {
    1 => self.emit("\tldrb\tw11, [x10]")
    2 => self.emit("\tldrh\tw11, [x10]")
    4 => self.emit("\tldr\tw11, [x10]")
    _ => self.emit("\tldr\tx11, [x10]")
  }
  self.emit_load_int("x12", mask)
  self.emit("\tlsl\tx12, x12, #" + info.bit_offset.to_string())
  self.emit("\tmvn\tx12, x12")
  self.emit("\tand\tx11, x11, x12")
  self.emit("\tldr\tx9, [sp]")
  self.emit("\tlsl\tx9, x9, #" + info.bit_offset.to_string())
  self.emit("\torr\tx11, x11, x9")
  match info.size {
    1 => self.emit("\tstrb\tw11, [x10]")
    2 => self.emit("\tstrh\tw11, [x10]")
    4 => self.emit("\tstr\tw11, [x10]")
    _ => self.emit("\tstr\tx11, [x10]")
  }
  self.emit("\tldr\tx9, [sp], #16")
  self.emit("\tadd\tsp, sp, #16")
  if lhs_ty.is_signed() {
    let shift = 64 - info.bit_width
    self.emit("\tlsl\tx9, x9, #" + shift.to_string())
    self.emit("\tasr\tx9, x9, #" + shift.to_string())
  }
}

///|
fn Codegen::gen_callee_addr(
  self : Codegen,
  func : @parser.Expr,
  frame_size : Int,
) -> Unit {
  match func {
    // In call position, `(*fp)(...)` calls the function pointer value. It does
    // not load from the function address as an ordinary object dereference.
    Deref(ptr) => self.gen_expr(ptr, frame_size)
    _ => self.gen_expr(func, frame_size)
  }
}

///|
fn call_signature_expr(func : @parser.Expr) -> @parser.Expr {
  match func {
    Binary(",", _, right) => call_signature_expr(right)
    _ => func
  }
}

///|
fn Codegen::uses_indirect_callee(self : Codegen, func : @parser.Expr) -> Bool {
  match func {
    Var(name) =>
      self.local_offsets.contains(name) || self.globals.contains(name)
    _ => true
  }
}

///|
fn Codegen::emit_builtin_lib_call(
  self : Codegen,
  target : String,
  args : Array[@parser.Expr],
  arg_count : Int,
  frame_size : Int,
) -> Unit {
  let save_size = (arg_count * 8 + 15) / 16 * 16
  if save_size > 0 {
    self.emit("\tsub\tsp, sp, #" + save_size.to_string())
  }
  for i = 0; i < arg_count; i = i + 1 {
    self.gen_expr(args[i], frame_size)
    self.emit("\tstr\tx9, [sp, #" + (i * 8).to_string() + "]")
  }
  for i = 0; i < arg_count; i = i + 1 {
    self.emit(
      "\tldr\tx" + i.to_string() + ", [sp, #" + (i * 8).to_string() + "]",
    )
  }
  if save_size > 0 {
    self.emit("\tadd\tsp, sp, #" + save_size.to_string())
  }
  self.emit("\tbl\t" + target)
}

///|
fn Codegen::emit_lowered_builtin_call(
  self : Codegen,
  target : String,
  args : Array[@parser.Expr],
  fixed_indexes : Array[Int],
  rest_start : Int,
  frame_size : Int,
) -> Unit {
  let lowered_args = []
  for index in fixed_indexes {
    if index < args.length() {
      lowered_args.push(args[index])
    }
  }
  for i = rest_start; i < args.length(); i = i + 1 {
    lowered_args.push(args[i])
  }
  self.gen_expr(Call(Var(target), lowered_args), frame_size)
}

///|
fn Codegen::emit_builtin_rotate(
  self : Codegen,
  args : Array[@parser.Expr],
  frame_size : Int,
  width : Int,
  left : Bool,
) -> Unit {
  if args.length() < 2 {
    self.emit("\tmov\tx9, #0")
    return
  }
  self.gen_expr(args[0], frame_size)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_expr(args[1], frame_size)
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
}

///|
fn Codegen::emit_builtin_ffs(
  self : Codegen,
  args : Array[@parser.Expr],
  frame_size : Int,
  width : Int,
) -> Unit {
  if args.length() == 0 {
    self.emit("\tmov\tx9, #0")
    return
  }
  self.gen_expr(args[0], frame_size)
  let zero_label = self.new_label()
  let done_label = self.new_label()
  if width == 32 {
    self.emit("\tcbz\tw9, " + zero_label)
    self.emit("\trbit\tw9, w9")
    self.emit("\tclz\tw9, w9")
    self.emit("\tadd\tw9, w9, #1")
  } else {
    self.emit("\tcbz\tx9, " + zero_label)
    self.emit("\trbit\tx9, x9")
    self.emit("\tclz\tx9, x9")
    self.emit("\tadd\tx9, x9, #1")
  }
  self.emit("\tb\t" + done_label)
  self.emit(zero_label + ":")
  self.emit("\tmov\tx9, #0")
  self.emit(done_label + ":")
}

///|
fn Codegen::emit_builtin_popcount(
  self : Codegen,
  args : Array[@parser.Expr],
  frame_size : Int,
  width : Int,
) -> Unit {
  if args.length() == 0 {
    self.emit("\tmov\tx9, #0")
    return
  }
  self.gen_expr(args[0], frame_size)
  if width == 32 {
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
  self.emit("\tand\tx9, x9, #127")
}

///|
fn Codegen::emit_builtin_parity(
  self : Codegen,
  args : Array[@parser.Expr],
  frame_size : Int,
  width : Int,
) -> Unit {
  self.emit_builtin_popcount(args, frame_size, width)
  self.emit("\tand\tx9, x9, #1")
}

///|
fn Codegen::emit_builtin_call(
  self : Codegen,
  name : String,
  args : Array[@parser.Expr],
  frame_size : Int,
) -> Bool {
  match name {
    "__builtin_expect"
    | "__builtin_expect_with_probability"
    | "__builtin_unpredictable" => {
      // __builtin_expect(exp, c) -> just return exp
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_unreachable" => {
      self.emit("\tbrk\t#0x1")
      true
    }
    "__builtin_trap" => {
      self.emit("\tbrk\t#0x1")
      true
    }
    "__builtin_frame_address" => {
      if args.length() > 0 {
        match args[0] {
          Number(0L) => self.emit("\tmov\tx9, x29")
          _ => self.emit("\tmov\tx9, #0")
        }
      } else {
        self.emit("\tmov\tx9, x29")
      }
      true
    }
    "__builtin_assume" => {
      // No-op
      self.emit("\tmov\tx9, #0")
      true
    }
    "__builtin_prefetch" => {
      self.emit("\tmov\tx9, #0")
      true
    }
    "__builtin_clz" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tclz\tw9, w9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_clzl" | "__builtin_clzll" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tclz\tx9, x9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_ctz" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\trbit\tw9, w9")
        self.emit("\tclz\tw9, w9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_ctzl" | "__builtin_ctzll" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\trbit\tx9, x9")
        self.emit("\tclz\tx9, x9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_bswap16" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\trev\tw9, w9")
        self.emit("\tlsr\tw9, w9, #16")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_bswap32" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\trev\tw9, w9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_bswap64" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\trev\tx9, x9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_rotateleft32" => {
      self.emit_builtin_rotate(args, frame_size, 32, true)
      true
    }
    "__builtin_rotateright32" => {
      self.emit_builtin_rotate(args, frame_size, 32, false)
      true
    }
    "__builtin_rotateleft64" => {
      self.emit_builtin_rotate(args, frame_size, 64, true)
      true
    }
    "__builtin_rotateright64" => {
      self.emit_builtin_rotate(args, frame_size, 64, false)
      true
    }
    "__builtin_ffs" => {
      self.emit_builtin_ffs(args, frame_size, 32)
      true
    }
    "__builtin_ffsl" | "__builtin_ffsll" => {
      self.emit_builtin_ffs(args, frame_size, 64)
      true
    }
    "__builtin_popcount" => {
      self.emit_builtin_popcount(args, frame_size, 32)
      true
    }
    "__builtin_popcountl" | "__builtin_popcountll" => {
      self.emit_builtin_popcount(args, frame_size, 64)
      true
    }
    "__builtin_parity" => {
      self.emit_builtin_parity(args, frame_size, 32)
      true
    }
    "__builtin_parityl" | "__builtin_parityll" => {
      self.emit_builtin_parity(args, frame_size, 64)
      true
    }
    "__builtin_memcpy" => {
      if args.length() >= 3 {
        self.emit_builtin_lib_call("_memcpy", args, 3, frame_size)
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin_memset" => {
      if args.length() >= 3 {
        self.emit_builtin_lib_call("_memset", args, 3, frame_size)
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin_bzero" => {
      if args.length() >= 2 {
        self.emit_builtin_lib_call("_bzero", args, 2, frame_size)
      }
      self.emit("\tmov\tx9, #0")
      true
    }
    "__builtin_memmove" => {
      if args.length() >= 3 {
        self.emit_builtin_lib_call("_memmove", args, 3, frame_size)
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin_strlen" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tmov\tx0, x9")
        self.emit("\tbl\t_strlen")
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin_strcmp" => {
      if args.length() >= 2 {
        self.emit_builtin_lib_call("_strcmp", args, 2, frame_size)
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin_strcpy" => {
      if args.length() >= 2 {
        self.emit_builtin_lib_call("_strcpy", args, 2, frame_size)
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin_alloca" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        // Round up to 16-byte alignment: size = (size + 15) & ~15
        self.emit("\tadd\tx9, x9, #15")
        self.emit("\tbic\tx9, x9, #0xF")
        self.emit("\tsub\tsp, sp, x9")
      }
      self.emit("\tmov\tx9, sp")
      true
    }
    "__builtin_constant_p" => {
      // Always report non-constant (safe fallback)
      self.emit("\tmov\tx9, #0")
      true
    }
    "__builtin_flt_rounds" => {
      self.emit("\tmov\tx9, #1")
      true
    }
    "__builtin_object_size" | "__builtin_dynamic_object_size" => {
      // Return -1 (unknown size) cast to size_t
      self.emit("\tmov\tx9, #-1")
      true
    }
    // Fortified function stubs: fall back to unchecked versions
    "__builtin___memcpy_chk" => {
      if args.length() >= 3 {
        self.emit_builtin_lib_call("_memcpy", args, 3, frame_size)
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin___memset_chk" => {
      if args.length() >= 3 {
        self.emit_builtin_lib_call("_memset", args, 3, frame_size)
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin___memmove_chk" => {
      if args.length() >= 3 {
        self.emit_builtin_lib_call("_memmove", args, 3, frame_size)
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin___strcpy_chk" => {
      if args.length() >= 2 {
        self.emit_builtin_lib_call("_strcpy", args, 2, frame_size)
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin___strcat_chk" => {
      if args.length() >= 2 {
        self.emit_builtin_lib_call("_strcat", args, 2, frame_size)
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin___strncpy_chk" => {
      self.emit_lowered_builtin_call(
        "strncpy",
        args,
        [0, 1, 2],
        args.length(),
        frame_size,
      )
      true
    }
    "__builtin___strncat_chk" => {
      self.emit_lowered_builtin_call(
        "strncat",
        args,
        [0, 1, 2],
        args.length(),
        frame_size,
      )
      true
    }
    "__builtin___snprintf_chk" => {
      self.emit_lowered_builtin_call("snprintf", args, [0, 1, 4], 5, frame_size)
      true
    }
    "__builtin___vsnprintf_chk" => {
      self.emit_lowered_builtin_call(
        "vsnprintf",
        args,
        [0, 1, 4, 5],
        args.length(),
        frame_size,
      )
      true
    }
    "__builtin___sprintf_chk" => {
      self.emit_lowered_builtin_call("sprintf", args, [0, 3], 4, frame_size)
      true
    }
    "__builtin___vsprintf_chk" => {
      self.emit_lowered_builtin_call(
        "vsprintf",
        args,
        [0, 3, 4],
        args.length(),
        frame_size,
      )
      true
    }
    "__builtin___printf_chk" => {
      self.emit_lowered_builtin_call("printf", args, [1], 2, frame_size)
      true
    }
    "__builtin___fprintf_chk" => {
      self.emit_lowered_builtin_call("fprintf", args, [0, 2], 3, frame_size)
      true
    }
    "__builtin___vfprintf_chk" => {
      self.emit_lowered_builtin_call(
        "vfprintf",
        args,
        [0, 2, 3],
        args.length(),
        frame_size,
      )
      true
    }
    "__builtin_fabs" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tfmov\td9, x9")
        self.emit("\tfabs\td9, d9")
        self.emit("\tfmov\tx9, d9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_fabsf" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tfmov\ts9, w9")
        self.emit("\tfabs\ts9, s9")
        self.emit("\tfmov\tw9, s9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_nan" | "__builtin_nanf" | "__builtin_nanl" => {
      // Ignore string argument, return canonical NaN
      if name == "__builtin_nanf" {
        // float NaN: 0x7FC00000
        self.emit("\tmovz\tw9, #0x7FC0, lsl #16")
      } else {
        // double NaN: 0x7FF8000000000000
        self.emit("\tmovz\tx9, #0")
        self.emit("\tmovk\tx9, #0, lsl #16")
        self.emit("\tmovk\tx9, #0xF800, lsl #32")
        self.emit("\tmovk\tx9, #0x7FF8, lsl #48")
      }
      true
    }
    "__builtin_huge_val" | "__builtin_huge_vall" | "__builtin_inf" => {
      // double +inf: 0x7FF0000000000000
      self.emit("\tmovz\tx9, #0")
      self.emit("\tmovk\tx9, #0, lsl #16")
      self.emit("\tmovk\tx9, #0, lsl #32")
      self.emit("\tmovk\tx9, #0x7FF0, lsl #48")
      true
    }
    "__builtin_huge_valf" | "__builtin_inff" => {
      // float +inf: 0x7F800000
      self.emit("\tmovz\tw9, #0x7F80, lsl #16")
      true
    }
    "__builtin_fabsl" => {
      // long double is same as double on macOS ARM64
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tfmov\td9, x9")
        self.emit("\tfabs\td9, d9")
        self.emit("\tfmov\tx9, d9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_infl" => {
      // long double +inf: same as double
      self.emit("\tmovz\tx9, #0")
      self.emit("\tmovk\tx9, #0, lsl #16")
      self.emit("\tmovk\tx9, #0, lsl #32")
      self.emit("\tmovk\tx9, #0x7FF0, lsl #48")
      true
    }
    "__builtin_va_start" => {
      // __builtin_va_start(ap, last) - set ap to FP + 16
      // On macOS ARM64, va_list is char* and va_start always sets ap = FP + 16
      // (caller SP), which points to the first variadic arg in the save area.
      // The caller stores variadic register args starting at [sp, #0].
      if args.length() >= 1 {
        match args[0] {
          Var(ap_name) =>
            if self.local_offsets.contains(ap_name) {
              let offset = self.local_offsets[ap_name]
              self.emit("\tadd\tx9, x29, #16")
              self.emit_store_local("x9", offset, frame_size)
            } else {

            }
          _ => {
            self.gen_addr(args[0], frame_size)
            self.emit("\tmov\tx10, x9")
            self.emit("\tadd\tx9, x29, #16")
            self.emit("\tstr\tx9, [x10]")
          }
        }
      }
      true
    }
    "__builtin_va_end" => {
      // No-op for now
      self.emit("\tmov\tx9, #0")
      true
    }
    "__builtin_va_copy" => {
      // __builtin_va_copy(dest, src) - copy va_list pointer
      if args.length() >= 2 {
        self.gen_expr(args[1], frame_size)
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.gen_addr(args[0], frame_size)
        self.emit("\tmov\tx10, x9")
        self.emit("\tldr\tx9, [sp], #16")
        self.emit("\tstr\tx9, [x10]")
      }
      true
    }
    "__atomic_load_n" | "__c11_atomic_load" => {
      // __atomic_load_n(ptr, memorder)
      if args.length() >= 2 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tmov\tx0, x9")
        let elem_ty = atomic_target_type(self.type_of(args[0], frame_size))
        match elem_ty {
          Bool | SChar | UChar => self.emit("\tldarb\tw9, [x0]")
          SShort | UShort => self.emit("\tldarh\tw9, [x0]")
          SInt | UInt | Float => self.emit("\tldar\tw9, [x0]")
          _ => self.emit("\tldar\tx9, [x0]")
        }
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__atomic_store_n" | "__c11_atomic_store" => {
      // __atomic_store_n(ptr, val, memorder)
      if args.length() >= 2 {
        let elem_ty = atomic_target_type(self.type_of(args[0], frame_size))
        self.gen_expr(args[0], frame_size)
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.gen_expr(args[1], frame_size)
        self.emit_numeric_conversion(self.type_of(args[1], frame_size), elem_ty)
        self.emit_scalar_conversion_to(elem_ty)
        self.emit("\tldr\tx0, [sp], #16")
        match elem_ty {
          Bool | SChar | UChar => self.emit("\tstlrb\tw9, [x0]")
          SShort | UShort => self.emit("\tstlrh\tw9, [x0]")
          SInt | UInt | Float => self.emit("\tstlr\tw9, [x0]")
          _ => self.emit("\tstlr\tx9, [x0]")
        }
      }
      self.emit("\tmov\tx9, #0")
      true
    }
    "__atomic_add_fetch" => {
      self.emit_atomic_update(args, frame_size, "+", true)
      true
    }
    "__atomic_sub_fetch" => {
      self.emit_atomic_update(args, frame_size, "-", true)
      true
    }
    "__c11_atomic_fetch_add" => {
      self.emit_atomic_update(args, frame_size, "+", false)
      true
    }
    "__c11_atomic_fetch_sub" => {
      self.emit_atomic_update(args, frame_size, "-", false)
      true
    }
    "__c11_atomic_fetch_and" => {
      self.emit_atomic_update(args, frame_size, "&", false)
      true
    }
    "__c11_atomic_fetch_or" => {
      self.emit_atomic_update(args, frame_size, "|", false)
      true
    }
    "__c11_atomic_fetch_xor" => {
      self.emit_atomic_update(args, frame_size, "^", false)
      true
    }
    "__c11_atomic_exchange" => {
      self.emit_atomic_exchange(args, frame_size)
      true
    }
    "__c11_atomic_compare_exchange_strong" => {
      self.emit_atomic_compare_exchange(args, frame_size)
      true
    }
    "__darwin_fd_set" => {
      self.emit_darwin_fd_helper(args, frame_size, "set")
      true
    }
    "__darwin_fd_clr" => {
      self.emit_darwin_fd_helper(args, frame_size, "clr")
      true
    }
    "__darwin_fd_isset" => {
      self.emit_darwin_fd_helper(args, frame_size, "isset")
      true
    }
    "__sync_synchronize" => {
      // Full memory barrier
      self.emit("\tdmb\tish")
      self.emit("\tmov\tx9, #0")
      true
    }
    "__builtin___strlcpy_chk" => {
      // __builtin___strlcpy_chk(dst, src, len, objsize) -> strlcpy(dst, src, len)
      if args.length() >= 3 {
        self.emit_builtin_lib_call("_strlcpy", args, 3, frame_size)
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin___strlcat_chk" => {
      // __builtin___strlcat_chk(dst, src, len, objsize) -> strlcat(dst, src, len)
      if args.length() >= 3 {
        self.emit_builtin_lib_call("_strlcat", args, 3, frame_size)
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin_bswap" => {
      // Generic bswap - assume 32-bit for int, 64-bit for long
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\trev\tx9, x9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_isgreater" => {
      if args.length() >= 2 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tfmov\td9, x9")
        self.gen_expr(args[1], frame_size)
        self.emit("\tfmov\td10, x9")
        self.emit("\tfcmp\td9, d10")
        self.emit("\tcset\tx9, gt")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_isgreaterequal" => {
      if args.length() >= 2 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tfmov\td9, x9")
        self.gen_expr(args[1], frame_size)
        self.emit("\tfmov\td10, x9")
        self.emit("\tfcmp\td9, d10")
        self.emit("\tcset\tx9, ge")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_isless" => {
      if args.length() >= 2 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tfmov\td9, x9")
        self.gen_expr(args[1], frame_size)
        self.emit("\tfmov\td10, x9")
        self.emit("\tfcmp\td9, d10")
        self.emit("\tcset\tx9, mi")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_islessequal" => {
      if args.length() >= 2 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tfmov\td9, x9")
        self.gen_expr(args[1], frame_size)
        self.emit("\tfmov\td10, x9")
        self.emit("\tfcmp\td9, d10")
        self.emit("\tcset\tx9, ls")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_islessgreater" => {
      if args.length() >= 2 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tfmov\td9, x9")
        self.gen_expr(args[1], frame_size)
        self.emit("\tfmov\td10, x9")
        self.emit("\tfcmp\td9, d10")
        // lessgreater = (less || greater) = !equal && !unordered
        // We use the condition codes: NE (not equal) excludes both eq and unordered
        // Actually, fcmp sets NE if neither EQ nor UNO
        self.emit("\tcset\tx9, ne")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_isunordered" => {
      if args.length() >= 2 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tfmov\td9, x9")
        self.gen_expr(args[1], frame_size)
        self.emit("\tfmov\td10, x9")
        self.emit("\tfcmp\td9, d10")
        self.emit("\tcset\tx9, vs")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    _ => false
  }
}

///|
fn is_aggregate_type(ty : @parser.Type) -> Bool {
  match peel_aligned_type(ty) {
    Struct(_) | Union(_) | Array(_, _) => true
    _ => false
  }
}

///|
fn Codegen::is_register_aggregate(self : Codegen, ty : @parser.Type) -> Bool {
  match peel_aligned_type(ty) {
    Struct(_) | Union(_) => self.type_size(ty) <= 16
    _ => false
  }
}

///|
fn Codegen::is_indirect_aggregate(self : Codegen, ty : @parser.Type) -> Bool {
  match peel_aligned_type(ty) {
    Struct(_) | Union(_) => self.type_size(ty) > 16
    _ => false
  }
}

///|
fn Codegen::emit_save_register_aggregate(
  self : Codegen,
  ty : @parser.Type,
) -> Unit {
  self.emit("\tsub\tsp, sp, #16")
  self.emit("\tstr\tx0, [sp]")
  if self.type_size(ty) > 8 {
    self.emit("\tstr\tx1, [sp, #8]")
  }
}

///|
fn Codegen::emit_store_saved_register_aggregate_at_x9(
  self : Codegen,
  ty : @parser.Type,
) -> Unit {
  self.emit("\tldr\tx10, [sp]")
  self.emit("\tstr\tx10, [x9]")
  if self.type_size(ty) > 8 {
    self.emit("\tldr\tx10, [sp, #8]")
    self.emit("\tstr\tx10, [x9, #8]")
  }
  self.emit("\tadd\tsp, sp, #16")
}

///|
fn Codegen::emit_load_register_aggregate_from_x9(
  self : Codegen,
  ty : @parser.Type,
) -> Unit {
  self.emit("\tldr\tx0, [x9]")
  if self.type_size(ty) > 8 {
    self.emit("\tldr\tx1, [x9, #8]")
  }
}

///|
priv struct MemberAddrInfo {
  ty : @parser.Type
  size : Int
  bit_offset : Int
  bit_width : Int
  stack_temp_size : Int
}

///|
fn Codegen::emit_member_base_addr(
  self : Codegen,
  obj : @parser.Expr,
  frame_size : Int,
) -> Int {
  let obj_ty = self.type_of(obj, frame_size)
  match obj {
    Call(_, _) if self.is_register_aggregate(obj_ty) => {
      self.gen_expr(obj, frame_size)
      self.emit_save_register_aggregate(obj_ty)
      self.emit("\tmov\tx9, sp")
      16
    }
    Call(_, _) if self.is_indirect_aggregate(obj_ty) => {
      self.gen_aggregate_addr(obj, frame_size)
      0
    }
    Cast(ty, inner) if is_aggregate_type(ty) =>
      self.emit_member_base_addr(inner, frame_size)
    Binary(",", left, right) => {
      self.gen_expr(left, frame_size)
      self.emit_member_base_addr(right, frame_size)
    }
    MemberAccess(_, _) =>
      match self.emit_member_addr(obj, frame_size) {
        Some(info) => info.stack_temp_size
        None => {
          self.gen_addr(obj, frame_size)
          0
        }
      }
    _ => {
      self.gen_addr(obj, frame_size)
      0
    }
  }
}

///|
fn Codegen::emit_member_addr(
  self : Codegen,
  expr : @parser.Expr,
  frame_size : Int,
) -> MemberAddrInfo? {
  match expr {
    MemberAccess(obj, field) => {
      let obj_ty = self.type_of(obj, frame_size)
      let struct_name = match aggregate_owner_name(obj_ty) {
        Some(n) => n
        None => return None
      }
      let stack_temp_size = self.emit_member_base_addr(obj, frame_size)
      match self.find_field_layout(struct_name, field) {
        None => {
          if stack_temp_size > 0 {
            self.emit("\tadd\tsp, sp, #" + stack_temp_size.to_string())
          }
          None
        }
        Some((_, ty, offset, size, bit_offset, bit_width)) => {
          self.emit_add_offset_to_x9(offset)
          Some({ ty, size, bit_offset, bit_width, stack_temp_size })
        }
      }
    }
    _ => None
  }
}

///|
fn Codegen::emit_add_offset_to_x9(self : Codegen, offset : Int) -> Unit {
  if offset == 0 {
    return
  }
  if offset >= 0 && offset <= 4095 {
    self.emit("\tadd\tx9, x9, #" + offset.to_string())
  } else {
    self.emit_load_int("x12", offset.to_int64())
    self.emit("\tadd\tx9, x9, x12")
  }
}

///|
fn Codegen::emit_copy_aggregate_from_addr_on_stack(
  self : Codegen,
  ty : @parser.Type,
) -> Unit {
  self.emit("\tldr\tx0, [sp, #16]")
  self.emit("\tldr\tx1, [sp]")
  let size = self.type_size(ty)
  self.emit_load_int("x2", size.to_int64())
  self.emit("\tbl\t_memcpy")
  self.emit("\tadd\tsp, sp, #32")
  self.emit("\tmov\tx9, x0")
}

///|
fn Codegen::emit_init_scalar_at_addr(
  self : Codegen,
  ty : @parser.Type,
  init_expr : @parser.Expr,
  frame_size : Int,
) -> Unit {
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_expr(init_expr, frame_size)
  self.emit_numeric_conversion(self.type_of(init_expr, frame_size), ty)
  self.emit_scalar_conversion_to(ty)
  self.emit("\tldr\tx10, [sp], #16")
  self.emit_store_typed("x9", "x10", ty)
}

///|
fn Codegen::emit_init_value_at_addr(
  self : Codegen,
  ty : @parser.Type,
  init_expr : @parser.Expr,
  frame_size : Int,
) -> Unit {
  let value = match init_expr {
    DesignatedField(_, e) => e
    DesignatedIndex(_, e) => e
    DesignatedRange(_, _, e) => e
    _ => init_expr
  }
  if is_aggregate_type(ty) {
    match init_expr {
      DesignatedField(_, e)
      | DesignatedIndex(_, e)
      | DesignatedRange(_, _, e) => {
        if self.designator_matches_type(ty, init_expr) {
          self.emit_init_aggregate_at_addr(ty, [init_expr], frame_size)
        } else {
          self.emit_init_value_at_addr(ty, e, frame_size)
        }
        return
      }
      _ => ()
    }
    match value {
      CompoundLiteral(_, init_exprs, _) | Array(init_exprs) =>
        self.emit_init_aggregate_at_addr(ty, init_exprs, frame_size)
      Number(0) => ()
      Call(_, _) if self.is_register_aggregate(ty) => {
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.gen_expr(value, frame_size)
        self.emit_save_register_aggregate(ty)
        self.emit("\tldr\tx9, [sp, #16]")
        self.emit_store_saved_register_aggregate_at_x9(ty)
        self.emit("\tadd\tsp, sp, #16")
      }
      _ => {
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.gen_aggregate_addr(value, frame_size)
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.emit_copy_aggregate_from_addr_on_stack(ty)
      }
    }
  } else {
    self.emit_init_scalar_at_addr(ty, value, frame_size)
  }
}

///|
fn Codegen::emit_init_bitfield_at_addr(
  self : Codegen,
  field_ty : @parser.Type,
  container_size : Int,
  bit_offset : Int,
  bit_width : Int,
  init_expr : @parser.Expr,
  frame_size : Int,
) -> Unit {
  let value = match init_expr {
    DesignatedField(_, e) => e
    DesignatedIndex(_, e) => e
    DesignatedRange(_, _, e) => e
    _ => init_expr
  }
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.gen_expr(value, frame_size)
  self.emit_numeric_conversion(self.type_of(value, frame_size), field_ty)
  self.emit_scalar_conversion_to(field_ty)
  self.emit("\tldr\tx10, [sp], #16")
  match container_size {
    1 => self.emit("\tldrb\tw11, [x10]")
    2 => self.emit("\tldrh\tw11, [x10]")
    4 => self.emit("\tldr\tw11, [x10]")
    _ => self.emit("\tldr\tx11, [x10]")
  }
  let mask = bitfield_mask(bit_width)
  self.emit_load_int("x12", mask)
  self.emit("\tlsl\tx12, x12, #" + bit_offset.to_string())
  self.emit("\tmvn\tx12, x12")
  self.emit("\tand\tx11, x11, x12")
  self.emit_load_int("x12", mask)
  self.emit("\tand\tx9, x9, x12")
  self.emit("\tlsl\tx9, x9, #" + bit_offset.to_string())
  self.emit("\torr\tx11, x11, x9")
  match container_size {
    1 => self.emit("\tstrb\tw11, [x10]")
    2 => self.emit("\tstrh\tw11, [x10]")
    4 => self.emit("\tstr\tw11, [x10]")
    _ => self.emit("\tstr\tx11, [x10]")
  }
}

///|
fn Codegen::emit_init_aggregate_at_addr(
  self : Codegen,
  ty : @parser.Type,
  init_exprs : Array[@parser.Expr],
  frame_size : Int,
) -> Unit {
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.emit("\tldr\tx0, [sp]")
  self.emit("\tmov\tx1, #0")
  let size = self.type_size(ty)
  self.emit_load_int("x2", size.to_int64())
  self.emit("\tbl\t_memset")
  match ty {
    Struct(name) => {
      let layout = if self.struct_layouts.contains(name) {
        self.struct_layouts[name]
      } else {
        []
      }
      let mut positional = 0
      for init_expr in init_exprs {
        let field = match init_expr {
          DesignatedField(field_name, _) => {
            let mut found = None
            for i = 0; i < layout.length(); i = i + 1 {
              let f = layout[i]
              if f.0 == field_name {
                found = Some(f)
                positional = i + 1
                break
              }
            }
            found
          }
          _ =>
            if positional < layout.length() {
              let f = layout[positional]
              positional += 1
              Some(f)
            } else {
              None
            }
        }
        match field {
          Some((_, field_ty, field_offset, field_size, bit_offset, bit_width)) => {
            self.emit("\tldr\tx9, [sp]")
            self.emit_add_offset_to_x9(field_offset)
            if bit_width > 0 {
              self.emit_init_bitfield_at_addr(
                field_ty, field_size, bit_offset, bit_width, init_expr, frame_size,
              )
            } else {
              self.emit_init_value_at_addr(field_ty, init_expr, frame_size)
            }
          }
          None => ()
        }
      }
    }
    Union(name) => {
      let field = if init_exprs.length() > 0 {
        match init_exprs[0] {
          DesignatedField(field_name, _) =>
            self.find_field_layout(name, field_name)
          _ =>
            if self.struct_layouts.contains(name) &&
              self.struct_layouts[name].length() > 0 {
              Some(self.struct_layouts[name][0])
            } else {
              None
            }
        }
      } else {
        None
      }
      match field {
        Some((_, field_ty, field_offset, field_size, bit_offset, bit_width)) =>
          if init_exprs.length() > 0 {
            self.emit("\tldr\tx9, [sp]")
            self.emit_add_offset_to_x9(field_offset)
            if bit_width > 0 {
              self.emit_init_bitfield_at_addr(
                field_ty,
                field_size,
                bit_offset,
                bit_width,
                init_exprs[0],
                frame_size,
              )
            } else {
              self.emit_init_value_at_addr(field_ty, init_exprs[0], frame_size)
            }
          }
        None => ()
      }
    }
    Array(elem_ty, n) => {
      let elem_size = self.type_size(elem_ty)
      let mut cursor = 0
      for init_expr in init_exprs {
        let mut start = cursor
        let mut end = cursor
        let value = match init_expr {
          DesignatedIndex(index, e) => {
            start = index.to_int()
            end = start
            cursor = start + 1
            e
          }
          DesignatedRange(first, last, e) => {
            start = first.to_int()
            end = last.to_int()
            cursor = end + 1
            e
          }
          _ => {
            cursor += 1
            init_expr
          }
        }
        for i = start; i <= end; i = i + 1 {
          if i >= 0 && i < n {
            self.emit("\tldr\tx9, [sp]")
            self.emit_add_offset_to_x9(i * elem_size)
            self.emit_init_value_at_addr(elem_ty, value, frame_size)
          }
        }
      }
    }
    _ => ()
  }
  self.emit("\tadd\tsp, sp, #16")
}

///|
fn Codegen::emit_load_float_literal(self : Codegen, v : Double) -> Unit {
  let idx = self.fp_literals.length()
  self.fp_literals.push(v)
  let label = "_fp_lit_" + self.func_name + "_" + idx.to_string()
  self.emit("\tadrp\tx9, " + label + "@PAGE")
  self.emit("\tadd\tx9, x9, " + label + "@PAGEOFF")
  self.emit("\tldr\tx9, [x9]")
}

///|
fn Codegen::emit_int128_compare(
  self : Codegen,
  op : String,
  is_unsigned : Bool,
) -> Unit {
  let high_diff = self.new_label()
  let done = self.new_label()
  self.emit("\tcmp\tx10, x12")
  self.emit("\tb.ne\t" + high_diff)
  self.emit("\tcmp\tx9, x11")
  match op {
    "==" => self.emit("\tcset\tx9, eq")
    "!=" => self.emit("\tcset\tx9, ne")
    "<" => self.emit("\tcset\tx9, lo")
    "<=" => self.emit("\tcset\tx9, ls")
    ">" => self.emit("\tcset\tx9, hi")
    ">=" => self.emit("\tcset\tx9, hs")
    _ => self.emit("\tmov\tx9, #0")
  }
  self.emit("\tb\t" + done)
  self.emit(high_diff + ":")
  match op {
    "==" => self.emit("\tmov\tx9, #0")
    "!=" => self.emit("\tmov\tx9, #1")
    "<" =>
      if is_unsigned {
        self.emit("\tcset\tx9, lo")
      } else {
        self.emit("\tcset\tx9, lt")
      }
    "<=" =>
      if is_unsigned {
        self.emit("\tcset\tx9, lo")
      } else {
        self.emit("\tcset\tx9, lt")
      }
    ">" =>
      if is_unsigned {
        self.emit("\tcset\tx9, hi")
      } else {
        self.emit("\tcset\tx9, gt")
      }
    ">=" =>
      if is_unsigned {
        self.emit("\tcset\tx9, hi")
      } else {
        self.emit("\tcset\tx9, gt")
      }
    _ => self.emit("\tmov\tx9, #0")
  }
  self.emit(done + ":")
}

///|
fn Codegen::emit_int128_left_shift(self : Codegen) -> Unit {
  let wide = self.new_label()
  let done = self.new_label()
  self.emit("\tand\tx13, x11, #127")
  self.emit("\tcmp\tx13, #0")
  self.emit("\tb.eq\t" + done)
  self.emit("\tcmp\tx13, #64")
  self.emit("\tb.hs\t" + wide)
  self.emit("\tmov\tx14, #64")
  self.emit("\tsub\tx14, x14, x13")
  self.emit("\tlsl\tx10, x10, x13")
  self.emit("\tlsr\tx15, x9, x14")
  self.emit("\torr\tx10, x10, x15")
  self.emit("\tlsl\tx9, x9, x13")
  self.emit("\tb\t" + done)
  self.emit(wide + ":")
  self.emit("\tsub\tx13, x13, #64")
  self.emit("\tlsl\tx10, x9, x13")
  self.emit("\tmov\tx9, #0")
  self.emit(done + ":")
}

///|
fn Codegen::emit_int128_right_shift(self : Codegen, is_unsigned : Bool) -> Unit {
  let wide = self.new_label()
  let done = self.new_label()
  self.emit("\tand\tx13, x11, #127")
  self.emit("\tcmp\tx13, #0")
  self.emit("\tb.eq\t" + done)
  self.emit("\tcmp\tx13, #64")
  self.emit("\tb.hs\t" + wide)
  self.emit("\tmov\tx14, #64")
  self.emit("\tsub\tx14, x14, x13")
  self.emit("\tlsr\tx9, x9, x13")
  self.emit("\tlsl\tx15, x10, x14")
  self.emit("\torr\tx9, x9, x15")
  if is_unsigned {
    self.emit("\tlsr\tx10, x10, x13")
  } else {
    self.emit("\tasr\tx10, x10, x13")
  }
  self.emit("\tb\t" + done)
  self.emit(wide + ":")
  self.emit("\tsub\tx13, x13, #64")
  if is_unsigned {
    self.emit("\tlsr\tx9, x10, x13")
    self.emit("\tmov\tx10, #0")
  } else {
    self.emit("\tasr\tx9, x10, x13")
    self.emit("\tasr\tx10, x10, #63")
  }
  self.emit(done + ":")
}

///|
fn Codegen::gen_int128_binary(
  self : Codegen,
  op : String,
  left : @parser.Expr,
  right : @parser.Expr,
  left_ty : @parser.Type,
  right_ty : @parser.Type,
  frame_size : Int,
) -> Unit {
  let result_ty = if op == "<<" || op == ">>" {
    unary_integer_result_type(left_ty)
  } else {
    integer_common_type(left_ty, right_ty)
  }
  let is_unsigned = is_unsigned_integer_type(result_ty)
  self.gen_expr(left, frame_size)
  self.emit_numeric_conversion(left_ty, result_ty)
  self.emit("\tstr\tx9, [sp, #-16]!")
  self.emit("\tstr\tx10, [sp, #8]")
  self.gen_expr(right, frame_size)
  if op == "<<" || op == ">>" {
    self.emit_numeric_conversion(right_ty, unary_integer_result_type(right_ty))
  } else {
    self.emit_numeric_conversion(right_ty, result_ty)
  }
  self.emit("\tmov\tx11, x9")
  self.emit("\tmov\tx12, x10")
  self.emit("\tldr\tx9, [sp]")
  self.emit("\tldr\tx10, [sp, #8]")
  self.emit("\tadd\tsp, sp, #16")
  match op {
    "+" => {
      self.emit("\tadds\tx9, x9, x11")
      self.emit("\tadc\tx10, x10, x12")
    }
    "-" => {
      self.emit("\tsubs\tx9, x9, x11")
      self.emit("\tsbc\tx10, x10, x12")
    }
    "*" => {
      self.emit("\tmul\tx13, x9, x11")
      self.emit("\tumulh\tx14, x9, x11")
      self.emit("\tmul\tx15, x9, x12")
      self.emit("\tadd\tx14, x14, x15")
      self.emit("\tmul\tx15, x10, x11")
      self.emit("\tadd\tx10, x14, x15")
      self.emit("\tmov\tx9, x13")
    }
    "/" => {
      self.emit("\tmov\tx0, x9")
      self.emit("\tmov\tx1, x10")
      self.emit("\tmov\tx2, x11")
      self.emit("\tmov\tx3, x12")
      if is_unsigned {
        self.emit("\tbl\t___udivti3")
      } else {
        self.emit("\tbl\t___divti3")
      }
      self.emit("\tmov\tx9, x0")
      self.emit("\tmov\tx10, x1")
    }
    "%" => {
      self.emit("\tmov\tx0, x9")
      self.emit("\tmov\tx1, x10")
      self.emit("\tmov\tx2, x11")
      self.emit("\tmov\tx3, x12")
      if is_unsigned {
        self.emit("\tbl\t___umodti3")
      } else {
        self.emit("\tbl\t___modti3")
      }
      self.emit("\tmov\tx9, x0")
      self.emit("\tmov\tx10, x1")
    }
    "&" => {
      self.emit("\tand\tx9, x9, x11")
      self.emit("\tand\tx10, x10, x12")
    }
    "|" => {
      self.emit("\torr\tx9, x9, x11")
      self.emit("\torr\tx10, x10, x12")
    }
    "^" => {
      self.emit("\teor\tx9, x9, x11")
      self.emit("\teor\tx10, x10, x12")
    }
    "<<" => self.emit_int128_left_shift()
    ">>" => self.emit_int128_right_shift(is_unsigned)
    "==" | "!=" | "<" | "<=" | ">" | ">=" =>
      self.emit_int128_compare(op, is_unsigned)
    "," => {
      self.emit("\tmov\tx9, x11")
      self.emit("\tmov\tx10, x12")
    }
    _ => ()
  }
}

///|
fn Codegen::gen_expr(
  self : Codegen,
  expr : @parser.Expr,
  frame_size : Int,
) -> Unit {
  match expr {
    Number(n) => self.emit_load_int("x9", n)
    FloatLiteral(v) => self.emit_load_float_literal(v)
    String(s) => {
      let idx = self.strings.length()
      self.strings.push(s)
      let label = "_str" + idx.to_string()
      self.emit("\tadrp\tx9, " + label + "@PAGE")
      self.emit("\tadd\tx9, x9, " + label + "@PAGEOFF")
    }
    Var(name) =>
      if self.local_offsets.contains(name) {
        let ty = self.var_types[name]
        let offset = self.local_offsets[name]
        if address_value_type(ty) {
          self.emit_local_addr(offset, frame_size)
        } else {
          self.emit_local_addr(offset, frame_size)
          self.emit_load_typed("x9", "x9", ty)
        }
      } else if self.globals.contains(name) {
        let ty = self.globals[name].ty
        // Use GOT for globals to handle undefined externals on macOS
        self.emit("\tadrp\tx9, _" + name + "@GOTPAGE")
        self.emit("\tldr\tx9, [x9, _" + name + "@GOTPAGEOFF]")
        if !address_value_type(ty) {
          self.emit_load_typed("x9", "x9", ty)
        }
      } else if self.func_rets.contains(name) {
        // Function pointer / function address - use GOT for undefined externals
        self.emit("\tadrp\tx9, _" + name + "@GOTPAGE")
        self.emit("\tldr\tx9, [x9, _" + name + "@GOTPAGEOFF]")
      } else {
        self.emit("\tmov\tx9, #0")
      }
    CompoundAssign(op, lhs, rhs) =>
      self.gen_compound_assign(op, lhs, rhs, frame_size)
    Assign(lhs, rhs) => {
      // Check if lhs is a bit-field member access
      let is_bitfield = match lhs {
        MemberAccess(obj, field) => {
          let obj_ty = self.type_of(obj, frame_size)
          match aggregate_owner_name(obj_ty) {
            Some(struct_name) =>
              match self.find_field_layout(struct_name, field) {
                Some((_, _, _, _, _, bit_width)) => bit_width > 0
                None => false
              }
            None => false
          }
        }
        _ => false
      }
      if is_bitfield {
        // Bit-field assignment: read-modify-write
        self.gen_expr(rhs, frame_size)
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.gen_addr(lhs, frame_size) // returns container address
        self.emit("\tmov\tx10, x9")
        self.emit("\tldr\tx9, [sp], #16") // value in x9
        // Get bit-field info
        match lhs {
          MemberAccess(obj, field) => {
            let obj_ty = self.type_of(obj, frame_size)
            let struct_name = match aggregate_owner_name(obj_ty) {
              Some(n) => n
              None => ""
            }
            match self.find_field_layout(struct_name, field) {
              Some((_, field_ty, _, size, bit_offset, bit_width)) => {
                // Load container
                match size {
                  1 => self.emit("\tldrb\tw11, [x10]")
                  2 => self.emit("\tldrh\tw11, [x10]")
                  4 => self.emit("\tldr\tw11, [x10]")
                  _ => self.emit("\tldr\tx11, [x10]")
                }
                // Clear old bits
                let mask = bitfield_mask(bit_width)
                self.emit_load_int("x12", mask)
                self.emit("\tlsl\tx12, x12, #" + bit_offset.to_string())
                self.emit("\tmvn\tx12, x12")
                self.emit("\tand\tx11, x11, x12")
                // Insert new value
                self.emit_load_int("x12", mask)
                self.emit("\tand\tx9, x9, x12")
                self.emit("\tstr\tx9, [sp, #-16]!")
                self.emit("\tlsl\tx9, x9, #" + bit_offset.to_string())
                self.emit("\torr\tx11, x11, x9")
                // Store container back
                match size {
                  1 => self.emit("\tstrb\tw11, [x10]")
                  2 => self.emit("\tstrh\tw11, [x10]")
                  4 => self.emit("\tstr\tw11, [x10]")
                  _ => self.emit("\tstr\tx11, [x10]")
                }
                self.emit("\tldr\tx9, [sp], #16")
                if field_ty.is_signed() {
                  let shift = 64 - bit_width
                  self.emit("\tlsl\tx9, x9, #" + shift.to_string())
                  self.emit("\tasr\tx9, x9, #" + shift.to_string())
                }
              }
              None => ()
            }
          }
          _ => ()
        }
      } else {
        let lhs_ty = self.type_of(lhs, frame_size)
        match peel_aligned_type(lhs_ty) {
          Struct(_) | Union(_) =>
            // Struct/union assignment: use memcpy via addresses
            match rhs {
              Call(_, _) if self.is_register_aggregate(lhs_ty) => {
                self.gen_expr(rhs, frame_size)
                self.emit_save_register_aggregate(lhs_ty)
                self.gen_addr(lhs, frame_size)
                self.emit_store_saved_register_aggregate_at_x9(lhs_ty)
              }
              _ => {
                self.gen_aggregate_addr(rhs, frame_size)
                self.emit("\tstr\tx9, [sp, #-16]!")
                self.gen_addr(lhs, frame_size)
                self.emit("\tstr\tx9, [sp, #-16]!")
                self.emit("\tmov\tx0, x9")
                self.emit("\tldr\tx1, [sp, #16]")
                let size = self.type_size(lhs_ty)
                self.emit_load_int("x2", size.to_int64())
                self.emit("\tbl\t_memcpy")
                self.emit("\tadd\tsp, sp, #32")
                self.emit("\tmov\tx9, x0")
              }
            }
          _ => {
            self.gen_expr(rhs, frame_size)
            self.emit_numeric_conversion(self.type_of(rhs, frame_size), lhs_ty)
            self.emit_scalar_conversion_to(lhs_ty)
            if is_int128_type(lhs_ty) {
              self.emit("\tstr\tx9, [sp, #-16]!")
              self.emit("\tstr\tx10, [sp, #8]")
              self.gen_addr(lhs, frame_size)
              self.emit("\tmov\tx11, x9")
              self.emit("\tldr\tx9, [sp]")
              self.emit("\tldr\tx10, [sp, #8]")
              self.emit("\tadd\tsp, sp, #16")
              self.emit_store_typed("x9", "x11", lhs_ty)
            } else {
              self.emit("\tstr\tx9, [sp, #-16]!")
              self.gen_addr(lhs, frame_size)
              self.emit("\tmov\tx10, x9")
              self.emit("\tldr\tx9, [sp], #16")
              self.emit_store_typed("x9", "x10", lhs_ty)
            }
          }
        }
      }
    }
    Binary("&&", left, right) => {
      let end_label = self.new_label()
      let false_label = self.new_label()
      self.gen_expr(left, frame_size)
      self.emit("\tcbz\tx9, " + false_label)
      self.gen_expr(right, frame_size)
      self.emit("\tcbz\tx9, " + false_label)
      self.emit("\tmov\tx9, #1")
      self.emit("\tb\t" + end_label)
      self.emit(false_label + ":")
      self.emit("\tmov\tx9, #0")
      self.emit(end_label + ":")
    }
    Binary("||", left, right) => {
      let end_label = self.new_label()
      let true_label = self.new_label()
      self.gen_expr(left, frame_size)
      self.emit("\tcbnz\tx9, " + true_label)
      self.gen_expr(right, frame_size)
      self.emit("\tcbnz\tx9, " + true_label)
      self.emit("\tmov\tx9, #0")
      self.emit("\tb\t" + end_label)
      self.emit(true_label + ":")
      self.emit("\tmov\tx9, #1")
      self.emit(end_label + ":")
    }
    Binary(op, left, right) => {
      let left_ty = self.type_of(left, frame_size)
      let right_ty = self.type_of(right, frame_size)
      let left_core = peel_aligned_type(left_ty)
      let right_core = peel_aligned_type(right_ty)
      if needs_int128_integer_op(left_ty, right_ty) {
        self.gen_int128_binary(op, left, right, left_ty, right_ty, frame_size)
        return
      }
      let ptr_scale = match (left_core, right_core) {
        (Pointer(elem), _) => self.type_size(elem)
        (Array(elem, _), _) => self.type_size(elem)
        (_, Pointer(elem)) => self.type_size(elem)
        (_, Array(elem, _)) => self.type_size(elem)
        _ => 1
      }
      let is_ptr_diff = match (left_core, right_core) {
        (Pointer(_), Pointer(_)) => true
        (Array(_, _), Pointer(_)) => true
        (Pointer(_), Array(_, _)) => true
        (Array(_, _), Array(_, _)) => true
        _ => false
      }
      let has_ptr_operand = match (left_core, right_core) {
        (Pointer(_), _)
        | (Array(_, _), _)
        | (_, Pointer(_))
        | (_, Array(_, _)) => true
        _ => false
      }
      let scale_right = match (left_core, right_core) {
        (Pointer(_), rhs_ty) | (Array(_, _), rhs_ty) =>
          !is_ptr_diff && (op == "+" || op == "-") && rhs_ty.is_integer()
        _ => false
      }
      let scale_left = match (left_core, right_core) {
        (lhs_ty, Pointer(_)) | (lhs_ty, Array(_, _)) =>
          !is_ptr_diff && op == "+" && lhs_ty.is_integer()
        _ => false
      }
      let is_ptr_op = has_ptr_operand
      let is_fp = !is_ptr_op &&
        op != "," &&
        (left_ty.is_floating() || right_ty.is_floating())
      let is_double = is_fp && (left_ty == Double || right_ty == Double)
      let fp_ty : @parser.Type = if is_double { Double } else { Float }
      let result_ty = binary_expr_result_type(
        op, left, left_ty, right, right_ty,
      )
      let is_unsigned_int = match op {
        "<<" | ">>" => is_unsigned_integer_type(result_ty)
        _ => uses_unsigned_integer_op(left_ty, right_ty)
      }
      let is_unsigned_cmp = is_unsigned_int || is_ptr_diff
      self.gen_expr(left, frame_size)
      if is_fp {
        self.emit_numeric_conversion(left_ty, fp_ty)
      }
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.gen_expr(right, frame_size)
      if is_fp {
        self.emit_numeric_conversion(right_ty, fp_ty)
      }
      if ptr_scale > 1 && scale_right {
        self.emit("\tmov\tx11, #" + ptr_scale.to_string())
        self.emit("\tmul\tx9, x9, x11")
      }
      self.emit("\tmov\tx10, x9")
      self.emit("\tldr\tx9, [sp], #16")
      if ptr_scale > 1 && scale_left {
        self.emit("\tmov\tx11, #" + ptr_scale.to_string())
        self.emit("\tmul\tx9, x9, x11")
      }
      match op {
        "+" =>
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfadd\td9, d9, d10")
              self.emit("\tfmov\tx9, d9")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfadd\ts9, s9, s10")
              self.emit("\tfmov\tw9, s9")
            }
          } else {
            self.emit("\tadd\tx9, x9, x10")
          }
        "-" =>
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfsub\td9, d9, d10")
              self.emit("\tfmov\tx9, d9")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfsub\ts9, s9, s10")
              self.emit("\tfmov\tw9, s9")
            }
          } else {
            self.emit("\tsub\tx9, x9, x10")
            if is_ptr_diff && ptr_scale > 1 {
              self.emit("\tmov\tx11, #" + ptr_scale.to_string())
              self.emit("\tsdiv\tx9, x9, x11")
            }
          }
        "*" =>
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfmul\td9, d9, d10")
              self.emit("\tfmov\tx9, d9")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfmul\ts9, s9, s10")
              self.emit("\tfmov\tw9, s9")
            }
          } else {
            self.emit("\tmul\tx9, x9, x10")
          }
        "/" =>
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfdiv\td9, d9, d10")
              self.emit("\tfmov\tx9, d9")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfdiv\ts9, s9, s10")
              self.emit("\tfmov\tw9, s9")
            }
          } else if is_unsigned_int {
            self.emit("\tudiv\tx9, x9, x10")
          } else {
            self.emit("\tsdiv\tx9, x9, x10")
          }
        "%" =>
          if is_unsigned_int {
            self.emit("\tudiv\tx11, x9, x10\n\tmsub\tx9, x11, x10, x9")
          } else {
            self.emit("\tsdiv\tx11, x9, x10\n\tmsub\tx9, x11, x10, x9")
          }
        "&" => self.emit("\tand\tx9, x9, x10")
        "|" => self.emit("\torr\tx9, x9, x10")
        "^" => self.emit("\teor\tx9, x9, x10")
        "<<" => self.emit("\tlsl\tx9, x9, x10")
        ">>" =>
          if is_unsigned_int {
            self.emit("\tlsr\tx9, x9, x10")
          } else {
            self.emit("\tasr\tx9, x9, x10")
          }
        "," =>
          // Result is the right operand (in x10)
          self.emit("\tmov\tx9, x10")
        "==" =>
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfcmp\td9, d10")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfcmp\ts9, s10")
            }
            self.emit("\tcset\tx9, eq")
          } else {
            self.emit_integer_compare(left_ty, right_ty, is_ptr_diff)
            self.emit("\tcset\tx9, eq")
          }
        "!=" =>
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfcmp\td9, d10")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfcmp\ts9, s10")
            }
            self.emit("\tcset\tx9, ne")
          } else {
            self.emit_integer_compare(left_ty, right_ty, is_ptr_diff)
            self.emit("\tcset\tx9, ne")
          }
        "<" =>
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfcmp\td9, d10")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfcmp\ts9, s10")
            }
            self.emit("\tcset\tx9, mi")
          } else {
            self.emit_integer_compare(left_ty, right_ty, is_ptr_diff)
            if is_unsigned_cmp {
              self.emit("\tcset\tx9, lo")
            } else {
              self.emit("\tcset\tx9, lt")
            }
          }
        "<=" =>
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfcmp\td9, d10")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfcmp\ts9, s10")
            }
            self.emit("\tcset\tx9, ls")
          } else {
            self.emit_integer_compare(left_ty, right_ty, is_ptr_diff)
            if is_unsigned_cmp {
              self.emit("\tcset\tx9, ls")
            } else {
              self.emit("\tcset\tx9, le")
            }
          }
        ">" =>
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfcmp\td9, d10")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfcmp\ts9, s10")
            }
            self.emit("\tcset\tx9, gt")
          } else {
            self.emit_integer_compare(left_ty, right_ty, is_ptr_diff)
            if is_unsigned_cmp {
              self.emit("\tcset\tx9, hi")
            } else {
              self.emit("\tcset\tx9, gt")
            }
          }
        ">=" =>
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfcmp\td9, d10")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfcmp\ts9, s10")
            }
            self.emit("\tcset\tx9, ge")
          } else {
            self.emit_integer_compare(left_ty, right_ty, is_ptr_diff)
            if is_unsigned_cmp {
              self.emit("\tcset\tx9, hs")
            } else {
              self.emit("\tcset\tx9, ge")
            }
          }
        _ => ()
      }
      if !is_fp && !is_ptr_op && binary_needs_scalar_result_conversion(op) {
        self.emit_scalar_conversion_to(result_ty)
      }
    }
    Unary("-", operand) => {
      self.gen_expr(operand, frame_size)
      let op_ty = self.type_of(operand, frame_size)
      if op_ty.is_floating() {
        if op_ty == Double {
          self.emit("\tfmov\td9, x9")
          self.emit("\tfneg\td9, d9")
          self.emit("\tfmov\tx9, d9")
        } else {
          self.emit("\tfmov\ts9, w9")
          self.emit("\tfneg\ts9, s9")
          self.emit("\tfmov\tw9, s9")
        }
      } else if is_int128_type(op_ty) {
        self.emit("\tnegs\tx9, x9")
        self.emit("\tngc\tx10, x10")
      } else {
        self.emit("\tneg\tx9, x9")
      }
    }
    Unary("~", operand) => {
      self.gen_expr(operand, frame_size)
      if is_int128_type(self.type_of(operand, frame_size)) {
        self.emit("\tmvn\tx9, x9")
        self.emit("\tmvn\tx10, x10")
      } else {
        self.emit("\tmvn\tx9, x9")
      }
    }
    Unary("!", operand) => {
      self.gen_expr(operand, frame_size)
      if is_int128_type(self.type_of(operand, frame_size)) {
        self.emit("\torr\tx9, x9, x10")
      }
      self.emit("\tcmp\tx9, #0")
      self.emit("\tcset\tx9, eq")
    }
    Call(func, args) => {
      // Try builtin dispatch first
      let is_builtin = match func {
        Var(name) => self.emit_builtin_call(name, args, frame_size)
        _ => false
      }
      if !is_builtin {
        // Check if callee is variadic
        let signature_func = call_signature_expr(func)
        let callee_ty = self.type_of(signature_func, frame_size)
        let typed_variadic_count = match callee_ty {
          FuncPtr(_, params, true) => Some(params.length())
          _ => None
        }
        let named_count = match typed_variadic_count {
          Some(count) => count
          None =>
            match signature_func {
              Var(name) =>
                if self.func_param_counts.contains(name) {
                  self.func_param_counts[name]
                } else {
                  // Known external variadic functions
                  match name {
                    "printf" | "vprintf" | "scanf" | "fscanf" | "sscanf" => 1
                    "fprintf" | "vfprintf" | "sprintf" | "vsprintf" => 2
                    "snprintf" | "vsnprintf" => 3
                    "___snprintf_chk" => 5
                    "open" | "fcntl" | "ioctl" => 2
                    _ => 0
                  }
                }
              _ => 0
            }
        }
        let is_variadic = match typed_variadic_count {
          Some(_) => true
          None =>
            match signature_func {
              Var(name) =>
                if self.func_variadic.get_or_default(name, false) {
                  true
                } else {
                  // Known external variadic functions
                  match name {
                    "printf"
                    | "vprintf"
                    | "fprintf"
                    | "vfprintf"
                    | "sprintf"
                    | "vsprintf"
                    | "snprintf"
                    | "vsnprintf"
                    | "scanf"
                    | "fscanf"
                    | "sscanf"
                    | "___snprintf_chk"
                    | "open"
                    | "fcntl"
                    | "ioctl" => true
                    _ => false
                  }
                }
              _ => false
            }
        }
        let needs_indirect_callee = self.uses_indirect_callee(func)
        if is_variadic {
          // AAPCS64 variadic calls: all args passed in x0-x7/v0-v7 as usual,
          // plus caller must save x0-x7 to a 64-byte register save area on stack.
          let mut int_idx = 0
          let mut fp_idx = 0
          let mut total_slots = 0
          let actual_arg_types = []
          let arg_types = []
          let arg_slot_counts = []
          let arg_copy_offsets = []
          let mut copy_area_size = 0
          for i = 0; i < args.length(); i = i + 1 {
            let actual_ty = self.type_of(args[i], frame_size)
            let arg_ty = self.declared_call_arg_type(
              signature_func,
              i,
              actual_ty,
              Some(named_count),
              frame_size,
            )
            actual_arg_types.push(actual_ty)
            arg_types.push(arg_ty)
            arg_copy_offsets.push(-1)
            match peel_aligned_type(arg_ty) {
              Float | Double | LongDouble => {
                total_slots += 1
                fp_idx += 1
                arg_slot_counts.push(1)
              }
              SInt128 | UInt128 => {
                total_slots += 2
                int_idx += 2
                arg_slot_counts.push(2)
              }
              Struct(_) | Union(_) => {
                let size = self.type_size(arg_ty)
                if size > 8 && size <= 16 {
                  total_slots += 2
                  int_idx += 2
                  arg_slot_counts.push(2)
                } else {
                  if size > 16 {
                    arg_copy_offsets[i] = copy_area_size
                    copy_area_size += (size + 15) / 16 * 16
                  }
                  total_slots += 1
                  int_idx += 1
                  arg_slot_counts.push(1)
                }
              }
              _ => {
                total_slots += 1
                int_idx += 1
                arg_slot_counts.push(1)
              }
            }
          }
          // Reset for register allocation pass
          int_idx = 0
          fp_idx = 0
          let aligned_save = (total_slots * 8 + 15) / 16 * 16
          let mut variadic_slots = 0
          for i = named_count; i < arg_slot_counts.length(); i = i + 1 {
            variadic_slots += arg_slot_counts[i]
          }
          let variadic_area = if variadic_slots * 8 > 64 {
            (variadic_slots * 8 + 15) / 16 * 16
          } else {
            64
          }
          let backup_offset = variadic_area
          let callee_save_size = if needs_indirect_callee { 16 } else { 0 }
          let callee_offset = variadic_area + aligned_save
          let copy_base = variadic_area + aligned_save + callee_save_size
          let aligned_copy_area = (copy_area_size + 15) / 16 * 16
          let total_stack = copy_base + aligned_copy_area
          if total_stack > 0 {
            self.emit("\tsub\tsp, sp, #" + total_stack.to_string())
          }
          // Evaluate all args first; nested calls can clobber argument registers.
          let mut slot_idx = 0
          for i = 0; i < args.length(); i = i + 1 {
            match peel_aligned_type(arg_types[i]) {
              Struct(_) | Union(_) => {
                let size = self.type_size(arg_types[i])
                if size <= 16 {
                  self.emit_save_small_aggregate_arg_to_stack(
                    args[i],
                    arg_types[i],
                    frame_size,
                    backup_offset + slot_idx * 8,
                  )
                  if size > 8 {
                    slot_idx += 2
                  } else {
                    slot_idx += 1
                  }
                } else {
                  self.emit_copy_large_arg_to_call_area(
                    args[i],
                    arg_types[i],
                    frame_size,
                    copy_base + arg_copy_offsets[i],
                  )
                  self.emit(
                    "\tstr\tx9, [sp, #" +
                    (backup_offset + slot_idx * 8).to_string() +
                    "]",
                  )
                  slot_idx += 1
                }
              }
              _ => {
                self.gen_expr(args[i], frame_size)
                self.emit_call_arg_conversion(actual_arg_types[i], arg_types[i])
                if is_int128_type(arg_types[i]) {
                  self.emit(
                    "\tstr\tx9, [sp, #" +
                    (backup_offset + slot_idx * 8).to_string() +
                    "]",
                  )
                  self.emit(
                    "\tstr\tx10, [sp, #" +
                    (backup_offset + (slot_idx + 1) * 8).to_string() +
                    "]",
                  )
                  slot_idx += 2
                } else {
                  self.emit(
                    "\tstr\tx9, [sp, #" +
                    (backup_offset + slot_idx * 8).to_string() +
                    "]",
                  )
                  slot_idx += 1
                }
              }
            }
          }
          if needs_indirect_callee {
            self.gen_callee_addr(func, frame_size)
            self.emit("\tstr\tx9, [sp, #" + callee_offset.to_string() + "]")
          }
          // Load ALL args into registers from backup slots
          int_idx = 0
          fp_idx = 0
          slot_idx = 0
          for i = 0; i < args.length(); i = i + 1 {
            match peel_aligned_type(arg_types[i]) {
              Float => {
                let reg = "s" + fp_idx.to_string()
                self.emit(
                  "\tldr\tw9, [sp, #" +
                  (backup_offset + slot_idx * 8).to_string() +
                  "]",
                )
                self.emit("\tfmov\t" + reg + ", w9")
                fp_idx += 1
                slot_idx += 1
              }
              Double | LongDouble => {
                let reg = "d" + fp_idx.to_string()
                self.emit(
                  "\tldr\tx9, [sp, #" +
                  (backup_offset + slot_idx * 8).to_string() +
                  "]",
                )
                self.emit("\tfmov\t" + reg + ", x9")
                fp_idx += 1
                slot_idx += 1
              }
              SInt128 | UInt128 => {
                self.emit(
                  "\tldr\tx" +
                  int_idx.to_string() +
                  ", [sp, #" +
                  (backup_offset + slot_idx * 8).to_string() +
                  "]",
                )
                self.emit(
                  "\tldr\tx" +
                  (int_idx + 1).to_string() +
                  ", [sp, #" +
                  (backup_offset + (slot_idx + 1) * 8).to_string() +
                  "]",
                )
                int_idx += 2
                slot_idx += 2
              }
              Struct(_) | Union(_) => {
                let size = self.type_size(arg_types[i])
                if size > 8 && size <= 16 {
                  self.emit(
                    "\tldr\tx" +
                    int_idx.to_string() +
                    ", [sp, #" +
                    (backup_offset + slot_idx * 8).to_string() +
                    "]",
                  )
                  self.emit(
                    "\tldr\tx" +
                    (int_idx + 1).to_string() +
                    ", [sp, #" +
                    (backup_offset + (slot_idx + 1) * 8).to_string() +
                    "]",
                  )
                  int_idx += 2
                  slot_idx += 2
                } else {
                  self.emit(
                    "\tldr\tx" +
                    int_idx.to_string() +
                    ", [sp, #" +
                    (backup_offset + slot_idx * 8).to_string() +
                    "]",
                  )
                  int_idx += 1
                  slot_idx += 1
                }
              }
              _ => {
                self.emit(
                  "\tldr\tx" +
                  int_idx.to_string() +
                  ", [sp, #" +
                  (backup_offset + slot_idx * 8).to_string() +
                  "]",
                )
                int_idx += 1
                slot_idx += 1
              }
            }
          }
          // Darwin ARM64 variadic callees read unnamed arguments from stack slots.
          let mut src_slot = 0
          let mut dst_slot = 0
          for i = 0; i < args.length(); i = i + 1 {
            if i >= named_count {
              for j = 0; j < arg_slot_counts[i]; j = j + 1 {
                self.emit(
                  "\tldr\tx9, [sp, #" +
                  (backup_offset + (src_slot + j) * 8).to_string() +
                  "]",
                )
                self.emit(
                  "\tstr\tx9, [sp, #" + ((dst_slot + j) * 8).to_string() + "]",
                )
              }
              dst_slot += arg_slot_counts[i]
            }
            src_slot += arg_slot_counts[i]
          }
          let ret_ty = self.call_return_type(signature_func, frame_size)
          if needs_indirect_callee {
            self.emit("\tldr\tx15, [sp, #" + callee_offset.to_string() + "]")
            self.emit_call_sret_addr(ret_ty, frame_size)
            self.emit("\tblr\tx15")
          } else {
            self.emit_call_sret_addr(ret_ty, frame_size)
            match func {
              Var(name) => self.emit("\tbl\t_" + name)
              _ => ()
            }
          }
          if total_stack > 0 {
            self.emit("\tadd\tsp, sp, #" + total_stack.to_string())
          }
          self.emit_call_result(ret_ty)
        } else {
          // Non-variadic calls: evaluate args and save to stack first
          // to prevent nested calls from clobbering register arguments
          let mut int_idx = 0
          let mut fp_idx = 0
          let mut stack_count = 0
          let actual_arg_types = []
          let arg_types = []
          let arg_slot_counts = []
          let arg_copy_offsets = []
          let mut copy_area_size = 0
          for i = 0; i < args.length(); i = i + 1 {
            let actual_ty = self.type_of(args[i], frame_size)
            let arg_ty = self.declared_call_arg_type(
              signature_func,
              i,
              actual_ty,
              None,
              frame_size,
            )
            actual_arg_types.push(actual_ty)
            arg_types.push(arg_ty)
            arg_copy_offsets.push(-1)
            match peel_aligned_type(arg_ty) {
              Float | Double | LongDouble => {
                if fp_idx >= 8 {
                  stack_count += 1
                }
                fp_idx += 1
                arg_slot_counts.push(1)
              }
              SInt128 | UInt128 => {
                if int_idx >= 7 {
                  stack_count += 2
                } else if int_idx == 7 {
                  stack_count += 1
                }
                int_idx += 2
                arg_slot_counts.push(2)
              }
              Struct(_) | Union(_) => {
                let size = self.type_size(arg_ty)
                if size > 8 && size <= 16 {
                  if int_idx >= 7 {
                    stack_count += 2
                  } else if int_idx == 7 {
                    stack_count += 1
                  }
                  int_idx += 2
                  arg_slot_counts.push(2)
                } else {
                  if size > 16 {
                    arg_copy_offsets[i] = copy_area_size
                    copy_area_size += (size + 15) / 16 * 16
                  }
                  if int_idx >= 8 {
                    stack_count += 1
                  }
                  int_idx += 1
                  arg_slot_counts.push(1)
                }
              }
              _ => {
                if int_idx >= 8 {
                  stack_count += 1
                }
                int_idx += 1
                arg_slot_counts.push(1)
              }
            }
          }
          let stack_arg_size = stack_count * 8
          let reg_save_size = arg_slot_counts.fold(init=0, fn(acc, n) {
              acc + n
            }) *
            8
          let aligned_reg_save = (reg_save_size + 15) / 16 * 16
          let aligned_stack_arg = (stack_arg_size + 15) / 16 * 16
          let callee_save_size = if needs_indirect_callee { 16 } else { 0 }
          let temp_area = aligned_reg_save + callee_save_size
          let callee_offset = aligned_reg_save
          let copy_base = temp_area + aligned_stack_arg
          let aligned_copy_area = (copy_area_size + 15) / 16 * 16
          let total_stack = copy_base + aligned_copy_area
          if total_stack > 0 {
            self.emit("\tsub\tsp, sp, #" + total_stack.to_string())
          }
          // Evaluate all args and save to temporary stack slots
          let mut slot_idx = 0
          for i = 0; i < args.length(); i = i + 1 {
            match peel_aligned_type(arg_types[i]) {
              Struct(_) | Union(_) => {
                let size = self.type_size(arg_types[i])
                if size <= 16 {
                  self.emit_save_small_aggregate_arg_to_stack(
                    args[i],
                    arg_types[i],
                    frame_size,
                    slot_idx * 8,
                  )
                  if size > 8 {
                    slot_idx += 2
                  } else {
                    slot_idx += 1
                  }
                } else {
                  self.emit_copy_large_arg_to_call_area(
                    args[i],
                    arg_types[i],
                    frame_size,
                    copy_base + arg_copy_offsets[i],
                  )
                  self.emit(
                    "\tstr\tx9, [sp, #" + (slot_idx * 8).to_string() + "]",
                  )
                  slot_idx += 1
                }
              }
              _ => {
                self.gen_expr(args[i], frame_size)
                self.emit_call_arg_conversion(actual_arg_types[i], arg_types[i])
                if is_int128_type(arg_types[i]) {
                  self.emit(
                    "\tstr\tx9, [sp, #" + (slot_idx * 8).to_string() + "]",
                  )
                  self.emit(
                    "\tstr\tx10, [sp, #" +
                    ((slot_idx + 1) * 8).to_string() +
                    "]",
                  )
                  slot_idx += 2
                } else {
                  self.emit(
                    "\tstr\tx9, [sp, #" + (slot_idx * 8).to_string() + "]",
                  )
                  slot_idx += 1
                }
              }
            }
          }
          if needs_indirect_callee {
            self.gen_callee_addr(func, frame_size)
            self.emit("\tstr\tx9, [sp, #" + callee_offset.to_string() + "]")
          }
          // Load args from stack into correct registers / stack positions
          int_idx = 0
          fp_idx = 0
          let mut stack_idx = 0
          slot_idx = 0
          for i = 0; i < args.length(); i = i + 1 {
            match peel_aligned_type(arg_types[i]) {
              Float => {
                if fp_idx < 8 {
                  self.emit(
                    "\tldr\tw9, [sp, #" + (slot_idx * 8).to_string() + "]",
                  )
                  let reg = "s" + fp_idx.to_string()
                  self.emit("\tfmov\t" + reg + ", w9")
                } else {
                  let offset = temp_area + stack_idx * 8
                  self.emit(
                    "\tldr\tw9, [sp, #" + (slot_idx * 8).to_string() + "]",
                  )
                  self.emit("\tstr\tw9, [sp, #" + offset.to_string() + "]")
                  stack_idx += 1
                }
                fp_idx += 1
                slot_idx += 1
              }
              Double | LongDouble => {
                if fp_idx < 8 {
                  self.emit(
                    "\tldr\tx9, [sp, #" + (slot_idx * 8).to_string() + "]",
                  )
                  let reg = "d" + fp_idx.to_string()
                  self.emit("\tfmov\t" + reg + ", x9")
                } else {
                  let offset = temp_area + stack_idx * 8
                  self.emit(
                    "\tldr\tx9, [sp, #" + (slot_idx * 8).to_string() + "]",
                  )
                  self.emit("\tstr\tx9, [sp, #" + offset.to_string() + "]")
                  stack_idx += 1
                }
                fp_idx += 1
                slot_idx += 1
              }
              SInt128 | UInt128 => {
                if int_idx < 7 {
                  self.emit(
                    "\tldr\tx" +
                    int_idx.to_string() +
                    ", [sp, #" +
                    (slot_idx * 8).to_string() +
                    "]",
                  )
                  self.emit(
                    "\tldr\tx" +
                    (int_idx + 1).to_string() +
                    ", [sp, #" +
                    ((slot_idx + 1) * 8).to_string() +
                    "]",
                  )
                } else if int_idx == 7 {
                  self.emit(
                    "\tldr\tx7, [sp, #" + (slot_idx * 8).to_string() + "]",
                  )
                  let offset = temp_area + stack_idx * 8
                  self.emit(
                    "\tldr\tx9, [sp, #" + ((slot_idx + 1) * 8).to_string() + "]",
                  )
                  self.emit("\tstr\tx9, [sp, #" + offset.to_string() + "]")
                  stack_idx += 1
                } else {
                  let offset = temp_area + stack_idx * 8
                  self.emit(
                    "\tldr\tx9, [sp, #" + (slot_idx * 8).to_string() + "]",
                  )
                  self.emit("\tstr\tx9, [sp, #" + offset.to_string() + "]")
                  self.emit(
                    "\tldr\tx9, [sp, #" + ((slot_idx + 1) * 8).to_string() + "]",
                  )
                  self.emit(
                    "\tstr\tx9, [sp, #" + (offset + 8).to_string() + "]",
                  )
                  stack_idx += 2
                }
                int_idx += 2
                slot_idx += 2
              }
              Struct(_) | Union(_) => {
                let size = self.type_size(arg_types[i])
                if size > 8 && size <= 16 {
                  if int_idx < 7 {
                    self.emit(
                      "\tldr\tx" +
                      int_idx.to_string() +
                      ", [sp, #" +
                      (slot_idx * 8).to_string() +
                      "]",
                    )
                    self.emit(
                      "\tldr\tx" +
                      (int_idx + 1).to_string() +
                      ", [sp, #" +
                      ((slot_idx + 1) * 8).to_string() +
                      "]",
                    )
                  } else if int_idx == 7 {
                    // First half in x7, second half on stack
                    self.emit(
                      "\tldr\tx7, [sp, #" + (slot_idx * 8).to_string() + "]",
                    )
                    let offset = temp_area + stack_idx * 8
                    self.emit(
                      "\tldr\tx9, [sp, #" +
                      ((slot_idx + 1) * 8).to_string() +
                      "]",
                    )
                    self.emit("\tstr\tx9, [sp, #" + offset.to_string() + "]")
                    stack_idx += 1
                  } else {
                    // Both halves on stack
                    let offset = temp_area + stack_idx * 8
                    self.emit(
                      "\tldr\tx9, [sp, #" + (slot_idx * 8).to_string() + "]",
                    )
                    self.emit("\tstr\tx9, [sp, #" + offset.to_string() + "]")
                    self.emit(
                      "\tldr\tx9, [sp, #" +
                      ((slot_idx + 1) * 8).to_string() +
                      "]",
                    )
                    self.emit(
                      "\tstr\tx9, [sp, #" + (offset + 8).to_string() + "]",
                    )
                    stack_idx += 2
                  }
                  int_idx += 2
                  slot_idx += 2
                } else {
                  if int_idx < 8 {
                    let reg = "x" + int_idx.to_string()
                    self.emit(
                      "\tldr\t" +
                      reg +
                      ", [sp, #" +
                      (slot_idx * 8).to_string() +
                      "]",
                    )
                  } else {
                    let offset = temp_area + stack_idx * 8
                    self.emit(
                      "\tldr\tx9, [sp, #" + (slot_idx * 8).to_string() + "]",
                    )
                    self.emit("\tstr\tx9, [sp, #" + offset.to_string() + "]")
                    stack_idx += 1
                  }
                  int_idx += 1
                  slot_idx += 1
                }
              }
              _ => {
                if int_idx < 8 {
                  let reg = "x" + int_idx.to_string()
                  self.emit(
                    "\tldr\t" +
                    reg +
                    ", [sp, #" +
                    (slot_idx * 8).to_string() +
                    "]",
                  )
                } else {
                  let offset = temp_area + stack_idx * 8
                  self.emit(
                    "\tldr\tx9, [sp, #" + (slot_idx * 8).to_string() + "]",
                  )
                  self.emit("\tstr\tx9, [sp, #" + offset.to_string() + "]")
                  stack_idx += 1
                }
                int_idx += 1
                slot_idx += 1
              }
            }
          }
          // Remove temporary save area so stack args are at [sp]
          if needs_indirect_callee {
            self.emit("\tldr\tx15, [sp, #" + callee_offset.to_string() + "]")
          }
          if temp_area > 0 {
            self.emit("\tadd\tsp, sp, #" + temp_area.to_string())
          }
          let ret_ty = self.call_return_type(signature_func, frame_size)
          if needs_indirect_callee {
            self.emit_call_sret_addr(ret_ty, frame_size)
            self.emit("\tblr\tx15")
          } else {
            self.emit_call_sret_addr(ret_ty, frame_size)
            match func {
              Var(name) => self.emit("\tbl\t_" + name)
              _ => ()
            }
          }
          let call_stack_area = aligned_stack_arg + aligned_copy_area
          if call_stack_area > 0 {
            self.emit("\tadd\tsp, sp, #" + call_stack_area.to_string())
          }
          self.emit_call_result(ret_ty)
        }
      }
    }
    MemberAccess(_, _) =>
      match self.emit_member_addr(expr, frame_size) {
        None => {
          self.gen_addr(expr, frame_size)
          if !address_value_type(self.type_of(expr, frame_size)) {
            self.emit("\tldr\tx9, [x9]")
          }
        }
        Some(info) => {
          let ty = info.ty
          let size = info.size
          let bit_offset = info.bit_offset
          let bit_width = info.bit_width
          if bit_width > 0 {
            match size {
              1 => self.emit("\tldrb\tw9, [x9]")
              2 => self.emit("\tldrh\tw9, [x9]")
              4 => self.emit("\tldr\tw9, [x9]")
              _ => self.emit("\tldr\tx9, [x9]")
            }
          } else if !address_value_type(ty) {
            match size {
              1 => self.emit("\tldrb\tw9, [x9]")
              2 => self.emit("\tldrh\tw9, [x9]")
              4 => self.emit("\tldr\tw9, [x9]")
              _ => self.emit("\tldr\tx9, [x9]")
            }
          }
          if bit_width > 0 {
            self.emit("\tlsr\tx9, x9, #" + bit_offset.to_string())
            if bit_width < 64 {
              let mask = bitfield_mask(bit_width)
              self.emit_load_int("x10", mask)
              self.emit("\tand\tx9, x9, x10")
            }
          }
          if ty.is_signed() {
            if bit_width > 0 {
              let shift = 64 - bit_width
              self.emit("\tlsl\tx9, x9, #" + shift.to_string())
              self.emit("\tasr\tx9, x9, #" + shift.to_string())
            } else {
              match size {
                1 => self.emit("\tsxtb\tx9, w9")
                2 => self.emit("\tsxth\tx9, w9")
                4 => self.emit("\tsxtw\tx9, w9")
                _ => ()
              }
            }
          }
          if info.stack_temp_size > 0 {
            self.emit("\tadd\tsp, sp, #" + info.stack_temp_size.to_string())
          }
        }
      }
    Deref(ptr) => {
      self.gen_expr(ptr, frame_size)
      let deref_ty = match peel_aligned_type(self.type_of(ptr, frame_size)) {
        Pointer(ty) => ty
        Array(elem, _) => elem
        _ => SInt
      }
      if !address_value_type(deref_ty) {
        self.emit_load_typed("x9", "x9", deref_ty)
      }
    }
    AddrOf(e) => self.gen_addr(e, frame_size)
    ArrayAccess(_, _) => {
      self.gen_addr(expr, frame_size)
      let elem_ty = self.type_of(expr, frame_size)
      if !address_value_type(elem_ty) {
        self.emit_load_typed("x9", "x9", elem_ty)
      }
    }
    Sizeof(ty) => {
      let size = self.type_size(ty)
      self.emit_load_int("x9", size.to_int64())
    }
    SizeofExpr(expr) => {
      let size = match expr {
        String(s) => s.length() + 1
        _ => self.type_size(self.type_of(expr, frame_size))
      }
      self.emit_load_int("x9", size.to_int64())
    }
    Alignof(ty) => {
      let align = self.type_align(ty)
      self.emit_load_int("x9", align.to_int64())
    }
    AlignofExpr(expr) => {
      let align = self.type_align(self.type_of(expr, frame_size))
      self.emit_load_int("x9", align.to_int64())
    }
    Cast(ty, expr) => {
      self.gen_expr(expr, frame_size)
      let expr_ty = self.type_of(expr, frame_size)
      self.emit_numeric_conversion(expr_ty, ty)
      self.emit_scalar_conversion_to(ty)
    }
    Ternary(cond, then_expr, else_expr) => {
      let else_label = self.new_label()
      let end_label = self.new_label()
      let result_ty = self.type_of(expr, frame_size)
      self.gen_expr(cond, frame_size)
      self.emit("\tcbz\tx9, " + else_label)
      self.gen_expr(then_expr, frame_size)
      if !address_value_type(result_ty) {
        self.emit_numeric_conversion(
          self.type_of(then_expr, frame_size),
          result_ty,
        )
        self.emit_scalar_conversion_to(result_ty)
      }
      self.emit("\tb\t" + end_label)
      self.emit(else_label + ":")
      self.gen_expr(else_expr, frame_size)
      if !address_value_type(result_ty) {
        self.emit_numeric_conversion(
          self.type_of(else_expr, frame_size),
          result_ty,
        )
        self.emit_scalar_conversion_to(result_ty)
      }
      self.emit(end_label + ":")
    }
    PrefixInc(expr) => {
      self.gen_addr(expr, frame_size)
      let ty = self.type_of(expr, frame_size)
      let ptr_scale = match ty {
        Pointer(elem) => self.type_size(elem)
        _ => 1
      }
      self.emit_load_typed("x10", "x9", ty)
      if ptr_scale > 1 {
        self.emit("\tadd\tx11, x10, #" + ptr_scale.to_string())
      } else {
        self.emit("\tadd\tx11, x10, #1")
      }
      self.emit_store_typed("x11", "x9", ty)
      self.emit("\tmov\tx9, x11")
      self.emit_scalar_conversion_to(ty)
    }
    PrefixDec(expr) => {
      self.gen_addr(expr, frame_size)
      let ty = self.type_of(expr, frame_size)
      let ptr_scale = match ty {
        Pointer(elem) => self.type_size(elem)
        _ => 1
      }
      self.emit_load_typed("x10", "x9", ty)
      if ptr_scale > 1 {
        self.emit("\tsub\tx11, x10, #" + ptr_scale.to_string())
      } else {
        self.emit("\tsub\tx11, x10, #1")
      }
      self.emit_store_typed("x11", "x9", ty)
      self.emit("\tmov\tx9, x11")
      self.emit_scalar_conversion_to(ty)
    }
    PostfixInc(expr) => {
      self.gen_addr(expr, frame_size)
      let ty = self.type_of(expr, frame_size)
      let ptr_scale = match ty {
        Pointer(elem) => self.type_size(elem)
        _ => 1
      }
      self.emit_load_typed("x10", "x9", ty)
      if ptr_scale > 1 {
        self.emit("\tadd\tx11, x10, #" + ptr_scale.to_string())
      } else {
        self.emit("\tadd\tx11, x10, #1")
      }
      self.emit_store_typed("x11", "x9", ty)
      match ty {
        SChar => self.emit("\tsxtb\tx9, w10")
        SShort => self.emit("\tsxth\tx9, w10")
        SInt => self.emit("\tsxtw\tx9, w10")
        _ => self.emit("\tmov\tx9, x10")
      }
    }
    PostfixDec(expr) => {
      self.gen_addr(expr, frame_size)
      let ty = self.type_of(expr, frame_size)
      let ptr_scale = match ty {
        Pointer(elem) => self.type_size(elem)
        _ => 1
      }
      self.emit_load_typed("x10", "x9", ty)
      if ptr_scale > 1 {
        self.emit("\tsub\tx11, x10, #" + ptr_scale.to_string())
      } else {
        self.emit("\tsub\tx11, x10, #1")
      }
      self.emit_store_typed("x11", "x9", ty)
      match ty {
        SChar => self.emit("\tsxtb\tx9, w10")
        SShort => self.emit("\tsxth\tx9, w10")
        SInt => self.emit("\tsxtw\tx9, w10")
        _ => self.emit("\tmov\tx9, x10")
      }
    }
    LabelAddr(name) => {
      let label = self.label_ref(name)
      self.emit("\tadr\tx9, " + label)
    }
    VaArg(ap_expr, ty) => {
      // Load ap pointer
      self.gen_expr(ap_expr, frame_size)
      // x9 now holds the va_list pointer value
      // Load the value from [x9] into the result register
      let ty_size = self.type_size(ty)
      match ty {
        Float => {
          self.emit("\tldr\tw9, [x9]")
          // Advance ap by align_up(4, 8) = 8
          self.gen_expr(ap_expr, frame_size)
          self.emit("\tadd\tx9, x9, #8")
          // Store back to ap
          self.emit("\tstr\tx9, [sp, #-16]!")
          self.gen_addr(ap_expr, frame_size)
          self.emit("\tmov\tx10, x9")
          self.emit("\tldr\tx9, [sp], #16")
          self.emit("\tstr\tx9, [x10]")
          // Reload the float value into w9 for return
          self.emit("\tmov\tw9, w9")
        }
        Double | LongDouble => {
          self.emit("\tldr\tx9, [x9]")
          // Advance ap by 8
          self.emit("\tstr\tx9, [sp, #-16]!") // save value
          self.gen_expr(ap_expr, frame_size)
          self.emit("\tadd\tx9, x9, #8")
          self.emit("\tstr\tx9, [sp, #-16]!") // save advanced ap
          self.gen_addr(ap_expr, frame_size)
          self.emit("\tmov\tx10, x9")
          self.emit("\tldr\tx9, [sp], #16") // restore advanced ap
          self.emit("\tstr\tx9, [x10]")
          self.emit("\tldr\tx9, [sp], #16") // restore value
        }
        SInt => {
          self.emit("\tldr\tw9, [x9]")
          self.emit("\tsxtw\tx9, w9")
          // Advance ap by align_up(4, 8) = 8
          self.emit("\tstr\tx9, [sp, #-16]!") // save value
          self.gen_expr(ap_expr, frame_size)
          self.emit("\tadd\tx9, x9, #8")
          self.emit("\tstr\tx9, [sp, #-16]!") // save advanced ap
          self.gen_addr(ap_expr, frame_size)
          self.emit("\tmov\tx10, x9")
          self.emit("\tldr\tx9, [sp], #16") // restore advanced ap
          self.emit("\tstr\tx9, [x10]")
          self.emit("\tldr\tx9, [sp], #16") // restore value
        }
        UInt => {
          self.emit("\tldr\tw9, [x9]")
          // Advance ap by align_up(4, 8) = 8
          self.emit("\tstr\tx9, [sp, #-16]!") // save value
          self.gen_expr(ap_expr, frame_size)
          self.emit("\tadd\tx9, x9, #8")
          self.emit("\tstr\tx9, [sp, #-16]!") // save advanced ap
          self.gen_addr(ap_expr, frame_size)
          self.emit("\tmov\tx10, x9")
          self.emit("\tldr\tx9, [sp], #16") // restore advanced ap
          self.emit("\tstr\tx9, [x10]")
          self.emit("\tldr\tx9, [sp], #16") // restore value
        }
        _ => {
          // For 64-bit types and pointers
          self.emit("\tldr\tx9, [x9]")
          // Advance ap by align_up(size, 8)
          let advance = if ty_size < 8 { 8 } else { ty_size }
          self.emit("\tstr\tx9, [sp, #-16]!") // save value
          self.gen_expr(ap_expr, frame_size)
          self.emit("\tadd\tx9, x9, #" + advance.to_string())
          self.emit("\tstr\tx9, [sp, #-16]!") // save advanced ap
          self.gen_addr(ap_expr, frame_size)
          self.emit("\tmov\tx10, x9")
          self.emit("\tldr\tx9, [sp], #16") // restore advanced ap
          self.emit("\tstr\tx9, [x10]")
          self.emit("\tldr\tx9, [sp], #16") // restore value
        }
      }
    }
    OffsetOf(ty, path) => {
      let offset = match self.offset_of_path(ty, path) {
        Some(value) => value
        None => 0
      }
      self.emit_load_int("x9", offset.to_int64())
    }
    CompoundLiteral(ty, init_exprs, id) =>
      if is_aggregate_type(ty) {
        self.gen_aggregate_addr(CompoundLiteral(ty, init_exprs, id), frame_size)
      } else if init_exprs.length() > 0 {
        self.gen_expr(init_exprs[0], frame_size)
        self.emit_numeric_conversion(
          self.type_of(init_exprs[0], frame_size),
          ty,
        )
        self.emit_scalar_conversion_to(ty)
      } else {
        self.emit("\tmov\tx9, #0")
      }
    DesignatedField(_, value) => self.gen_expr(value, frame_size)
    DesignatedIndex(_, value) => self.gen_expr(value, frame_size)
    DesignatedRange(_, _, value) => self.gen_expr(value, frame_size)
    _ => self.emit("\tmov\tx9, #0")
  }
}

///|
fn Codegen::gen_aggregate_addr(
  self : Codegen,
  expr : @parser.Expr,
  frame_size : Int,
) -> Unit {
  match expr {
    Ternary(cond, then_expr, else_expr) => {
      let else_label = self.new_label()
      let end_label = self.new_label()
      self.gen_expr(cond, frame_size)
      self.emit("\tcbz\tx9, " + else_label)
      self.gen_aggregate_addr(then_expr, frame_size)
      self.emit("\tb\t" + end_label)
      self.emit(else_label + ":")
      self.gen_aggregate_addr(else_expr, frame_size)
      self.emit(end_label + ":")
    }
    Binary(",", left, right) => {
      self.gen_expr(left, frame_size)
      self.gen_aggregate_addr(right, frame_size)
    }
    Cast(ty, inner) if is_aggregate_type(ty) =>
      self.gen_aggregate_addr(inner, frame_size)
    Assign(_, _) | CompoundAssign(_, _, _) => self.gen_expr(expr, frame_size)
    Call(_, _) if self.is_indirect_aggregate(self.type_of(expr, frame_size)) => {
      let saved_pending = self.pending_sret_offset
      self.pending_sret_offset = self.sret_scratch_offset
      self.gen_expr(expr, frame_size)
      self.pending_sret_offset = saved_pending
      self.emit_local_addr(self.sret_scratch_offset, frame_size)
    }
    CompoundLiteral(ty, init_exprs, id) => {
      let name = compound_literal_local_name(id)
      let offset = if self.local_offsets.contains(name) {
        self.local_offsets[name]
      } else {
        self.alloc_local(name, ty)
      }
      self.emit_local_addr(offset, frame_size)
      self.emit_init_aggregate_at_addr(ty, init_exprs, frame_size)
      self.emit_local_addr(offset, frame_size)
    }
    _ => self.gen_addr(expr, frame_size)
  }
}

///|
fn Codegen::gen_addr(
  self : Codegen,
  expr : @parser.Expr,
  frame_size : Int,
) -> Unit {
  match expr {
    Var(name) =>
      if self.local_offsets.contains(name) {
        let offset = self.local_offsets[name]
        self.emit_local_addr(offset, frame_size)
      } else if self.globals.contains(name) || self.func_rets.contains(name) {
        self.emit("\tadrp\tx9, _" + name + "@GOTPAGE")
        self.emit("\tldr\tx9, [x9, _" + name + "@GOTPAGEOFF]")
      } else {

      }
    MemberAccess(obj, field) => {
      self.gen_addr(obj, frame_size)
      let obj_ty = self.type_of(obj, frame_size)
      let struct_name = match aggregate_owner_name(obj_ty) {
        Some(n) => n
        None => return
      }
      if self.struct_layouts.contains(struct_name) {
        let fields = self.struct_layouts[struct_name]
        let mut field_offset = 0
        for f in fields {
          if f.0 == field {
            field_offset = f.2
            break
          }
        }
        if field_offset != 0 {
          self.emit_add_offset_to_x9(field_offset)
        }
      }
    }
    Deref(ptr) => self.gen_expr(ptr, frame_size)
    AddrOf(e) => self.gen_addr(e, frame_size)
    ArrayAccess(arr, index) => {
      // Array decay: if arr is an array type, use its address; if pointer, use its value
      match array_element_type(self.type_of(arr, frame_size)) {
        Some(_) => self.gen_addr(arr, frame_size)
        None => self.gen_expr(arr, frame_size)
      }
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.gen_expr(index, frame_size)
      self.emit("\tmov\tx12, x9")
      self.emit("\tldr\tx9, [sp], #16")
      let elem_ty = self.type_of(expr, frame_size)
      let elem_size = self.type_size(elem_ty)
      self.emit("\tmov\tx11, #" + elem_size.to_string())
      self.emit("\tmadd\tx9, x12, x11, x9")
    }
    CompoundLiteral(_, _, _) => self.gen_aggregate_addr(expr, frame_size)
    Call(_, _) =>
      // Function call result used as address (e.g., compound literal or GCC extension)
      self.gen_expr(expr, frame_size)
    LabelAddr(name) => {
      let label = self.label_ref(name)
      self.emit("\tadr\tx9, " + label)
    }
    _ => ()
  }
}
