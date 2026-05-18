///|
fn peel_aligned_type(ty : @ctype.Type) -> @ctype.Type {
  match ty {
    Aligned(inner, _) => peel_aligned_type(inner)
    _ => ty
  }
}

///|
fn pointer_or_array_element_type(ty : @ctype.Type) -> @ctype.Type? {
  match peel_aligned_type(ty) {
    Pointer(elem) | Array(elem, _) => Some(elem)
    _ => None
  }
}

///|
fn is_unsigned_integer_type(ty : @ctype.Type) -> Bool {
  match peel_aligned_type(ty) {
    Bool | UChar | UShort | UInt | ULong | ULongLong | UInt128 => true
    _ => false
  }
}

///|
fn is_int128_type(ty : @ctype.Type) -> Bool {
  match peel_aligned_type(ty) {
    SInt128 | UInt128 => true
    _ => false
  }
}

///|
fn Codegen::emit_numeric_conversion(
  self : Codegen,
  src : @ctype.Type,
  dst : @ctype.Type,
) -> Unit {
  if src == dst {
    return
  }
  match (src, dst) {
    (src, Bool) => if is_int128_type(src) { self.emit("\torr\tx9, x9, x10") }
    (src, Double) | (src, LongDouble) =>
      if src.is_integer() {
        if is_unsigned_integer_type(src) {
          self.emit("\tucvtf\td9, x9")
        } else {
          self.emit("\tscvtf\td9, x9")
        }
        self.emit("\tfmov\tx9, d9")
      } else if peel_aligned_type(src) == Float {
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
      } else if peel_aligned_type(src) == Double ||
        peel_aligned_type(src) == LongDouble {
        self.emit("\tfmov\td9, x9")
        self.emit("\tfcvt\ts9, d9")
        self.emit("\tfmov\tw9, s9")
      }
    (Double, dst) | (LongDouble, dst) =>
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
fn Codegen::emit_scalar_conversion_to(self : Codegen, ty : @ctype.Type) -> Unit {
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
    Atomic(inner) | Aligned(inner, _) => self.emit_scalar_conversion_to(inner)
    _ => ()
  }
}

///|
fn unary_integer_result_type(ty : @ctype.Type) -> @ctype.Type {
  match peel_aligned_type(ty) {
    Bool | SChar | UChar | SShort | UShort => SInt
    core => core
  }
}

///|
fn integer_rank(ty : @ctype.Type) -> Int {
  match peel_aligned_type(ty) {
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
fn unsigned_type_for_rank(rank : Int) -> @ctype.Type {
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
fn signed_type_for_rank(rank : Int) -> @ctype.Type {
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
fn integer_width_bits(ty : @ctype.Type) -> Int {
  match peel_aligned_type(ty) {
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
  lhs_ty : @ctype.Type,
  rhs_ty : @ctype.Type,
) -> @ctype.Type {
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
fn overflow_builtin_operator(name : String) -> String? {
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
fn overflow_small_int_range(ty : @ctype.Type) -> (Int64, Int64)? {
  match peel_aligned_type(ty) {
    SChar => Some((-128L, 127L))
    UChar => Some((0L, 255L))
    SShort => Some((-32768L, 32767L))
    UShort => Some((0L, 65535L))
    SInt => Some((-2147483648L, 2147483647L))
    UInt => Some((0L, 4294967295L))
    _ => None
  }
}

///|
fn Codegen::emit_overflow_range_check(
  self : Codegen,
  result_ty : @ctype.Type,
) -> Unit {
  match overflow_small_int_range(result_ty) {
    Some((min_value, max_value)) =>
      if is_unsigned_integer_type(result_ty) {
        self.emit_load_int("x12", max_value)
        self.emit("\tcmp\tx9, x12")
        self.emit("\tcset\tx11, hi")
      } else {
        self.emit_load_int("x12", min_value)
        self.emit("\tcmp\tx9, x12")
        self.emit("\tcset\tx11, lt")
        self.emit_load_int("x12", max_value)
        self.emit("\tcmp\tx9, x12")
        self.emit("\tcset\tx12, gt")
        self.emit("\torr\tx11, x11, x12")
      }
    None => self.emit("\tmov\tx11, #0")
  }
}

///|
fn Codegen::emit_small_overflow_arithmetic(
  self : Codegen,
  result_ty : @ctype.Type,
  op : String,
) -> Unit {
  match op {
    "+" => self.emit("\tadd\tx9, x9, x10")
    "-" => self.emit("\tsub\tx9, x9, x10")
    "*" =>
      if self.type_size(result_ty) == 4 {
        if is_unsigned_integer_type(result_ty) {
          self.emit("\tumull\tx9, w9, w10")
        } else {
          self.emit("\tsmull\tx9, w9, w10")
        }
      } else {
        self.emit("\tmul\tx9, x9, x10")
      }
    _ => ()
  }
  self.emit_overflow_range_check(result_ty)
}

///|
fn Codegen::emit_i64_overflow_arithmetic(
  self : Codegen,
  result_ty : @ctype.Type,
  op : String,
) -> Unit {
  let unsigned = is_unsigned_integer_type(result_ty)
  match op {
    "+" => {
      self.emit("\tadds\tx9, x9, x10")
      let cond = if unsigned { "cs" } else { "vs" }
      self.emit("\tcset\tx11, " + cond)
    }
    "-" => {
      self.emit("\tsubs\tx9, x9, x10")
      let cond = if unsigned { "lo" } else { "vs" }
      self.emit("\tcset\tx11, " + cond)
    }
    "*" =>
      if unsigned {
        self.emit("\tumulh\tx11, x9, x10")
        self.emit("\tmul\tx9, x9, x10")
        self.emit("\tcmp\tx11, #0")
        self.emit("\tcset\tx11, ne")
      } else {
        self.emit("\tmul\tx12, x9, x10")
        self.emit("\tsmulh\tx11, x9, x10")
        self.emit("\tasr\tx13, x12, #63")
        self.emit("\tcmp\tx11, x13")
        self.emit("\tcset\tx11, ne")
        self.emit("\tmov\tx9, x12")
      }
    _ => self.emit("\tmov\tx11, #0")
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
