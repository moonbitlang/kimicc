///|
/// Attempts to evaluate an integer constant expression.
///
/// Returns `Some(value)` when all required operands can be folded. Returns
/// `None` for expressions that depend on runtime values, unsupported operators,
/// floating-point expressions, and aggregate literals.
pub fn fold_const(expr : Expr) -> Int64? {
  match expr {
    Number(n) => Some(n)
    Binary("+", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x + y)
        _ => None
      }
    Binary("-", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x - y)
        _ => None
      }
    Binary("*", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x * y)
        _ => None
      }
    Binary("/", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => if y != 0 { Some(x / y) } else { None }
        _ => None
      }
    Binary("%", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => if y != 0 { Some(x % y) } else { None }
        _ => None
      }
    Binary("|", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x | y)
        _ => None
      }
    Binary("&", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x & y)
        _ => None
      }
    Binary("^", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x ^ y)
        _ => None
      }
    Binary("<<", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x << y.to_int())
        _ => None
      }
    Binary(">>", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x >> y.to_int())
        _ => None
      }
    Binary("==", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x == y { 1L } else { 0L })
        _ => None
      }
    Binary("!=", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x != y { 1L } else { 0L })
        _ => None
      }
    Binary("<", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x < y { 1L } else { 0L })
        _ => None
      }
    Binary(">", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x > y { 1L } else { 0L })
        _ => None
      }
    Binary("<=", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x <= y { 1L } else { 0L })
        _ => None
      }
    Binary(">=", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x >= y { 1L } else { 0L })
        _ => None
      }
    Binary("&&", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x != 0L && y != 0L { 1L } else { 0L })
        _ => None
      }
    Binary("||", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x != 0L || y != 0L { 1L } else { 0L })
        _ => None
      }
    Ternary(cond, a, b) =>
      match fold_const(cond) {
        Some(0L) => fold_const(b)
        Some(_) => fold_const(a)
        None => None
      }
    Unary("-", e) =>
      match fold_const(e) {
        Some(x) => Some(-x)
        _ => None
      }
    Unary("+", e) => fold_const(e)
    Unary("~", e) =>
      match fold_const(e) {
        Some(x) => Some(x.lnot())
        _ => None
      }
    Unary("!", e) =>
      match fold_const(e) {
        Some(0L) => Some(1L)
        Some(_) => Some(0L)
        _ => None
      }
    Cast(_, e) => fold_const(e)
    Sizeof(ty) => Some(basic_type_size(ty).to_int64())
    SizeofExpr(String(s)) => Some((s.length() + 1).to_int64())
    SizeofExpr(e) => Some(basic_type_size(type_of_expr(e)).to_int64())
    Alignof(ty) => Some(basic_type_align(ty).to_int64())
    AlignofExpr(String(s)) =>
      Some(basic_type_align(Array(SChar, s.length() + 1)).to_int64())
    AlignofExpr(e) => Some(basic_type_align(type_of_expr(e)).to_int64())
    DesignatedField(_, e) => fold_const(e)
    DesignatedIndex(_, e) => fold_const(e)
    DesignatedRange(_, _, e) => fold_const(e)
    Array(_) => None
    CompoundLiteral(_, _, _) => None
    _ => None
  }
}

///|
priv struct ConstIntValue {
  bits : Int64
  ty : Type
}

///|
fn const_int(bits : Int64, ty : Type) -> ConstIntValue {
  { bits, ty }
}

///|
fn const_bool(value : Bool) -> ConstIntValue {
  { bits: if value { 1L } else { 0L }, ty: SInt }
}

///|
fn const_type_core(ty : Type) -> Type {
  match ty {
    Atomic(inner) | Aligned(inner, _) => const_type_core(inner)
    _ => ty
  }
}

///|
fn Parser::long_double_size(self : Parser) -> Int {
  match self.target {
    DarwinArm64 => 8
    LinuxAmd64 => 16
  }
}

///|
fn Parser::long_double_align(self : Parser) -> Int {
  match self.target {
    DarwinArm64 => 8
    LinuxAmd64 => 16
  }
}

///|
fn Parser::float16_size(_self : Parser) -> Int {
  2
}

///|
fn Parser::float16_align(_self : Parser) -> Int {
  2
}

///|
fn Parser::float128_size(self : Parser) -> Int {
  match self.target {
    DarwinArm64 => abort("__float128 size is not supported")
    LinuxAmd64 => 16
  }
}

///|
fn Parser::float128_align(self : Parser) -> Int {
  match self.target {
    DarwinArm64 => abort("__float128 alignment is not supported")
    LinuxAmd64 => 16
  }
}

///|
fn const_number_type(bits : Int64) -> Type {
  if bits < 0L {
    ULongLong
  } else if bits > 2147483647L {
    SLongLong
  } else {
    SInt
  }
}

///|
fn const_type_is_integer(ty : Type) -> Bool {
  match const_type_core(ty) {
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
    | UInt128 => true
    _ => false
  }
}

///|
fn const_type_is_unsigned(ty : Type) -> Bool {
  match const_type_core(ty) {
    Bool | UChar | UShort | UInt | ULong | ULongLong | UInt128 => true
    _ => false
  }
}

///|
fn const_type_int_width(ty : Type) -> Int? {
  match const_type_core(ty) {
    Bool => Some(1)
    SChar | UChar => Some(8)
    SShort | UShort => Some(16)
    SInt | UInt => Some(32)
    SLong | ULong | SLongLong | ULongLong | Pointer(_) => Some(64)
    SInt128 | UInt128 => Some(128)
    _ => None
  }
}

///|
fn const_type_int_rank(ty : Type) -> Int {
  match const_type_core(ty) {
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
fn const_unsigned_type_for_rank(rank : Int) -> Type {
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
fn const_signed_type_for_rank(rank : Int) -> Type {
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
fn const_integer_promote(ty : Type) -> Type {
  match const_type_core(ty) {
    Bool | SChar | UChar | SShort | UShort => SInt
    other => other
  }
}

///|
fn const_integer_common_type(left_ty : Type, right_ty : Type) -> Type {
  let lhs_ty = const_integer_promote(left_ty)
  let rhs_ty = const_integer_promote(right_ty)
  if lhs_ty == rhs_ty {
    return lhs_ty
  }
  if !const_type_is_integer(lhs_ty) || !const_type_is_integer(rhs_ty) {
    return lhs_ty
  }
  let lhs_unsigned = const_type_is_unsigned(lhs_ty)
  let rhs_unsigned = const_type_is_unsigned(rhs_ty)
  let lhs_rank = const_type_int_rank(lhs_ty)
  let rhs_rank = const_type_int_rank(rhs_ty)
  if lhs_unsigned == rhs_unsigned {
    let rank = if lhs_rank > rhs_rank { lhs_rank } else { rhs_rank }
    if lhs_unsigned {
      const_unsigned_type_for_rank(rank)
    } else {
      const_signed_type_for_rank(rank)
    }
  } else {
    let unsigned_ty = if lhs_unsigned { lhs_ty } else { rhs_ty }
    let signed_ty = if lhs_unsigned { rhs_ty } else { lhs_ty }
    let unsigned_rank = const_type_int_rank(unsigned_ty)
    let signed_rank = const_type_int_rank(signed_ty)
    let unsigned_width = const_type_int_width(unsigned_ty).unwrap_or(0)
    let signed_width = const_type_int_width(signed_ty).unwrap_or(0)
    if unsigned_rank >= signed_rank {
      unsigned_ty
    } else if signed_width > unsigned_width {
      signed_ty
    } else {
      const_unsigned_type_for_rank(signed_rank)
    }
  }
}

///|
fn const_cast_int(value : ConstIntValue, ty : Type) -> ConstIntValue {
  let core_ty = const_type_core(ty)
  let unsigned = const_type_is_unsigned(core_ty)
  match const_type_int_width(ty) {
    None => const_int(value.bits, core_ty)
    Some(1) => const_int(if value.bits == 0L { 0L } else { 1L }, core_ty)
    Some(width) =>
      if width >= 64 {
        const_int(value.bits, core_ty)
      } else {
        let mask = (1L << width) - 1L
        let bits = value.bits & mask
        if unsigned {
          const_int(bits, core_ty)
        } else {
          let sign = 1L << (width - 1)
          if (bits & sign) != 0L {
            const_int(bits | mask.lnot(), core_ty)
          } else {
            const_int(bits, core_ty)
          }
        }
      }
  }
}

///|
fn const_apply_binary_type(
  left : ConstIntValue,
  right : ConstIntValue,
) -> (ConstIntValue, ConstIntValue, Type) {
  let ty = const_integer_common_type(left.ty, right.ty)
  (const_cast_int(left, ty), const_cast_int(right, ty), ty)
}

///|
fn const_binary_arith(
  op : String,
  left : ConstIntValue,
  right : ConstIntValue,
) -> ConstIntValue? {
  let (x, y, ty) = const_apply_binary_type(left, right)
  let bits = match op {
    "+" => x.bits + y.bits
    "-" => x.bits - y.bits
    "*" => x.bits * y.bits
    "|" => x.bits | y.bits
    "&" => x.bits & y.bits
    "^" => x.bits ^ y.bits
    _ => return None
  }
  Some(const_cast_int(const_int(bits, ty), ty))
}

///|
fn const_equal_compare(left : ConstIntValue, right : ConstIntValue) -> Bool {
  let (x, y, _) = const_apply_binary_type(left, right)
  x.bits == y.bits
}

///|
fn const_rel_compare(
  op : String,
  left : ConstIntValue,
  right : ConstIntValue,
) -> Bool {
  let (left, right, ty) = const_apply_binary_type(left, right)
  if const_type_is_unsigned(ty) {
    let x = left.bits.reinterpret_as_uint64()
    let y = right.bits.reinterpret_as_uint64()
    match op {
      "<" => x < y
      ">" => x > y
      "<=" => x <= y
      ">=" => x >= y
      _ => false
    }
  } else {
    match op {
      "<" => left.bits < right.bits
      ">" => left.bits > right.bits
      "<=" => left.bits <= right.bits
      ">=" => left.bits >= right.bits
      _ => false
    }
  }
}

///|
fn const_divide(
  op : String,
  left : ConstIntValue,
  right : ConstIntValue,
) -> ConstIntValue? {
  let (left, right, ty) = const_apply_binary_type(left, right)
  if right.bits == 0L {
    return None
  }
  if const_type_is_unsigned(ty) {
    let x = left.bits.reinterpret_as_uint64()
    let y = right.bits.reinterpret_as_uint64()
    let result = if op == "/" { x / y } else { x % y }
    Some(const_cast_int(const_int(result.reinterpret_as_int64(), ty), ty))
  } else {
    let result = if op == "/" {
      left.bits / right.bits
    } else {
      left.bits % right.bits
    }
    Some(const_cast_int(const_int(result, ty), ty))
  }
}

///|
fn const_shift(
  op : String,
  left : ConstIntValue,
  right : ConstIntValue,
) -> ConstIntValue? {
  let lhs_ty = const_integer_promote(left.ty)
  let x = const_cast_int(left, lhs_ty)
  let y = const_cast_int(right, const_integer_promote(right.ty))
  let shift = y.bits.to_int()
  if op == "<<" {
    Some(const_cast_int(const_int(x.bits << shift, lhs_ty), lhs_ty))
  } else if const_type_is_unsigned(lhs_ty) {
    Some(
      const_cast_int(
        const_int(
          (x.bits.reinterpret_as_uint64() >> shift).reinterpret_as_int64(),
          lhs_ty,
        ),
        lhs_ty,
      ),
    )
  } else {
    Some(const_cast_int(const_int(x.bits >> shift, lhs_ty), lhs_ty))
  }
}

///|
fn Parser::fold_const_int(self : Parser, expr : Expr) -> ConstIntValue? {
  match expr {
    Number(n) =>
      Some(
        const_cast_int(const_int(n, const_number_type(n)), const_number_type(n)),
      )
    Binary("+", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => const_binary_arith("+", x, y)
        _ => None
      }
    Binary("-", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => const_binary_arith("-", x, y)
        _ => None
      }
    Binary("*", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => const_binary_arith("*", x, y)
        _ => None
      }
    Binary("/", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => const_divide("/", x, y)
        _ => None
      }
    Binary("%", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => const_divide("%", x, y)
        _ => None
      }
    Binary("|", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => const_binary_arith("|", x, y)
        _ => None
      }
    Binary("&", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => const_binary_arith("&", x, y)
        _ => None
      }
    Binary("^", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => const_binary_arith("^", x, y)
        _ => None
      }
    Binary("<<", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => const_shift("<<", x, y)
        _ => None
      }
    Binary(">>", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => const_shift(">>", x, y)
        _ => None
      }
    Binary("==", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => Some(const_bool(const_equal_compare(x, y)))
        _ => None
      }
    Binary("!=", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => Some(const_bool(!const_equal_compare(x, y)))
        _ => None
      }
    Binary("<", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => Some(const_bool(const_rel_compare("<", x, y)))
        _ => None
      }
    Binary(">", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => Some(const_bool(const_rel_compare(">", x, y)))
        _ => None
      }
    Binary("<=", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => Some(const_bool(const_rel_compare("<=", x, y)))
        _ => None
      }
    Binary(">=", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => Some(const_bool(const_rel_compare(">=", x, y)))
        _ => None
      }
    Binary("&&", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => Some(const_bool(x.bits != 0L && y.bits != 0L))
        _ => None
      }
    Binary("||", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => Some(const_bool(x.bits != 0L || y.bits != 0L))
        _ => None
      }
    Ternary(cond, a, b) =>
      match self.fold_const_int(cond) {
        Some({ bits: 0L, .. }) => self.fold_const_int(b)
        Some(_) => self.fold_const_int(a)
        None => None
      }
    Unary("-", e) =>
      match self.fold_const_int(e) {
        Some(x) => {
          let ty = const_integer_promote(x.ty)
          Some(const_cast_int(const_int(-x.bits, ty), ty))
        }
        _ => None
      }
    Unary("+", e) =>
      match self.fold_const_int(e) {
        Some(x) => {
          let ty = const_integer_promote(x.ty)
          Some(const_cast_int(x, ty))
        }
        _ => None
      }
    Unary("~", e) =>
      match self.fold_const_int(e) {
        Some(x) => {
          let ty = const_integer_promote(x.ty)
          Some(const_cast_int(const_int(x.bits.lnot(), ty), ty))
        }
        _ => None
      }
    Unary("!", e) =>
      match self.fold_const_int(e) {
        Some(x) => Some(const_bool(x.bits == 0L))
        _ => None
      }
    Cast(ty, e) =>
      match self.fold_const_int(e) {
        Some(value) => Some(const_cast_int(value, ty))
        None => None
      }
    Sizeof(ty) => Some(const_int(self.const_type_size(ty).to_int64(), ULong))
    SizeofExpr(e) =>
      Some(
        const_int(
          match e {
            String(value) => value.length().to_int64() + 1L
            _ => self.const_type_size(self.const_expr_type(e)).to_int64()
          },
          ULong,
        ),
      )
    Alignof(ty) => Some(const_int(self.const_type_align(ty).to_int64(), ULong))
    AlignofExpr(e) =>
      Some(
        const_int(
          match e {
            String(value) =>
              self.const_type_align(Array(SChar, value.length() + 1)).to_int64()
            _ => self.const_type_align(self.const_expr_type(e)).to_int64()
          },
          ULong,
        ),
      )
    OffsetOf(ty, path) =>
      match self.const_offset_of(ty, path) {
        Some(offset) => Some(const_int(offset.to_int64(), ULong))
        None => None
      }
    DesignatedField(_, e) => self.fold_const_int(e)
    DesignatedIndex(_, e) => self.fold_const_int(e)
    DesignatedRange(_, _, e) => self.fold_const_int(e)
    Array(_) => None
    CompoundLiteral(_, _, _) => None
    _ => None
  }
}

///|
fn Parser::fold_const(self : Parser, expr : Expr) -> Int64? {
  match self.fold_const_int(expr) {
    Some(value) => Some(value.bits)
    None => None
  }
}

///|
fn basic_type_size(ty : Type) -> Int {
  match ty {
    Void => 0
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt | Float => 4
    Float16 => 2
    Float128 => abort("__float128 size is not supported")
    LongDouble => 8
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    SInt128 | UInt128 => 16
    Array(elem, n) => basic_type_size(elem) * n
    Struct(_) => 8 // unknown struct size, assume pointer-sized
    Union(_) => 8 // unknown union size, assume pointer-sized
    Atomic(inner) => basic_type_size(inner)
    Aligned(inner, _) => basic_type_size(inner)
  }
}

///|
fn basic_type_align(ty : Type) -> Int {
  match ty {
    Void => 1
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt | Float => 4
    Float16 => 2
    Float128 => abort("__float128 alignment is not supported")
    LongDouble => 8
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    SInt128 | UInt128 => 16
    Array(elem, _) => basic_type_align(elem)
    Struct(_) => 8
    Union(_) => 8
    Atomic(inner) => basic_type_align(inner)
    Aligned(inner, align) => {
      let inner_align = basic_type_align(inner)
      if align > inner_align {
        align
      } else {
        inner_align
      }
    }
  }
}

///|
fn Parser::const_type_size(self : Parser, ty : Type) -> Int {
  match ty {
    Void => 0
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt | Float => 4
    Float16 => self.float16_size()
    Float128 => self.float128_size()
    LongDouble => self.long_double_size()
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    SInt128 | UInt128 => 16
    Array(elem, n) => self.const_type_size(elem) * n
    Atomic(inner) => self.const_type_size(inner)
    Aligned(inner, _) => self.const_type_size(inner)
    Struct(name) => self.const_struct_size(name)
    Union(name) => self.const_union_size(name)
  }
}

///|
fn Parser::const_type_align(self : Parser, ty : Type) -> Int {
  match ty {
    Void => 1
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt | Float => 4
    Float16 => self.float16_align()
    Float128 => self.float128_align()
    LongDouble => self.long_double_align()
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    SInt128 | UInt128 => 16
    Array(elem, _) => self.const_type_align(elem)
    Atomic(inner) => self.const_type_align(inner)
    Aligned(inner, align) => {
      let inner_align = self.const_type_align(inner)
      if align > inner_align {
        align
      } else {
        inner_align
      }
    }
    Struct(name) => self.const_struct_align(name)
    Union(name) => self.const_union_align(name)
  }
}

///|
fn Parser::const_struct_size(self : Parser, name : String) -> Int {
  if !self.struct_decls.contains(name) {
    return 8
  }
  let decl = self.struct_decls[name]
  let layout = self.const_struct_layout(decl)
  let mut max_end = 0
  let mut max_align = 1
  for field in layout {
    let end = field.2 + field.3
    if end > max_end {
      max_end = end
    }
    if !decl.is_packed {
      let align = self.const_type_align(field.1)
      if align > max_align {
        max_align = align
      }
    }
  }
  max_end + (max_align - max_end % max_align) % max_align
}

///|
fn Parser::const_union_size(self : Parser, name : String) -> Int {
  if !self.struct_decls.contains(name) {
    return 8
  }
  let decl = self.struct_decls[name]
  let mut max_size = 0
  let mut max_align = 1
  for field in decl.fields {
    let size = self.const_type_size(field.ty)
    if size > max_size {
      max_size = size
    }
    if !decl.is_packed {
      let align = self.const_type_align(field.ty)
      if align > max_align {
        max_align = align
      }
    }
  }
  max_size + (max_align - max_size % max_align) % max_align
}

///|
fn Parser::const_struct_align(self : Parser, name : String) -> Int {
  if !self.struct_decls.contains(name) {
    return 8
  }
  if self.struct_decls[name].is_packed {
    return 1
  }
  let mut max_align = 1
  for field in self.struct_decls[name].fields {
    let align = self.const_type_align(field.ty)
    if align > max_align {
      max_align = align
    }
  }
  max_align
}

///|
fn Parser::const_union_align(self : Parser, name : String) -> Int {
  self.const_struct_align(name)
}

///|
fn parser_is_anon_type(ty : Type) -> Bool {
  match ty {
    Struct(name) | Union(name) => name.has_prefix("__anon_")
    _ => false
  }
}

///|
fn Parser::const_flatten_anon_fields(
  self : Parser,
  ty : Type,
  base_offset : Int,
) -> Array[(String, Type, Int, Int, Int, Int)] {
  let name = match ty {
    Struct(n) | Union(n) => n
    _ => return []
  }
  if !self.struct_decls.contains(name) {
    return []
  }
  let decl = self.struct_decls[name]
  let fields = if decl.is_union {
    self.const_union_layout(decl)
  } else {
    self.const_struct_layout(decl)
  }
  let result = []
  for field in fields {
    if field.0 == "" && parser_is_anon_type(field.1) {
      for
        inner in self.const_flatten_anon_fields(field.1, base_offset + field.2) {
        result.push(inner)
      }
    } else {
      result.push(
        (field.0, field.1, base_offset + field.2, field.3, field.4, field.5),
      )
    }
  }
  result
}

///|
fn Parser::const_struct_layout(
  self : Parser,
  decl : StructDecl,
) -> Array[(String, Type, Int, Int, Int, Int)] {
  let layout = []
  let mut offset = 0
  let mut in_bitfield_run = false
  let mut current_bit_offset = 0
  for field in decl.fields {
    if field.name == "" && parser_is_anon_type(field.ty) {
      let align = if decl.is_packed {
        1
      } else {
        self.const_type_align(field.ty)
      }
      offset += (align - offset % align) % align
      for f in self.const_flatten_anon_fields(field.ty, offset) {
        layout.push(f)
      }
      offset += self.const_type_size(field.ty)
      in_bitfield_run = false
      current_bit_offset = 0
      continue
    }
    match field.bit_width {
      None => {
        let size = self.const_type_size(field.ty)
        let align = if decl.is_packed {
          1
        } else {
          self.const_type_align(field.ty)
        }
        offset += (align - offset % align) % align
        layout.push((field.name, field.ty, offset, size, 0, 0))
        offset += size
        in_bitfield_run = false
        current_bit_offset = 0
      }
      Some(width) => {
        let container_size = self.const_type_size(field.ty)
        let container_align = if decl.is_packed {
          1
        } else {
          self.const_type_align(field.ty)
        }
        let container_bits = container_size * 8
        if width == 0 {
          offset += (container_align - offset % container_align) %
            container_align
          in_bitfield_run = false
          current_bit_offset = 0
        } else {
          let mut container_offset = current_bit_offset /
            (container_align * 8) *
            container_align
          let mut field_bit_offset = current_bit_offset - container_offset * 8
          let can_continue = in_bitfield_run &&
            field_bit_offset + width <= container_bits
          if !can_continue {
            container_offset = offset / container_align * container_align
            field_bit_offset = (offset - container_offset) * 8
            if offset >= container_offset + container_size ||
              field_bit_offset + width > container_bits {
              let padding = (container_align - offset % container_align) %
                container_align
              container_offset = offset + padding
              field_bit_offset = 0
            }
            current_bit_offset = container_offset * 8 + field_bit_offset
          }
          layout.push(
            (
              field.name,
              field.ty,
              container_offset,
              container_size,
              field_bit_offset,
              width,
            ),
          )
          in_bitfield_run = true
          current_bit_offset = current_bit_offset + width
          let end_offset = (current_bit_offset + 7) / 8
          if end_offset > offset {
            offset = end_offset
          }
        }
      }
    }
  }
  layout
}

///|
fn Parser::const_union_layout(
  self : Parser,
  decl : StructDecl,
) -> Array[(String, Type, Int, Int, Int, Int)] {
  let layout = []
  for field in decl.fields {
    if field.name == "" && parser_is_anon_type(field.ty) {
      for f in self.const_flatten_anon_fields(field.ty, 0) {
        layout.push(f)
      }
    } else {
      let size = self.const_type_size(field.ty)
      match field.bit_width {
        None => layout.push((field.name, field.ty, 0, size, 0, 0))
        Some(width) =>
          if width != 0 {
            layout.push((field.name, field.ty, 0, size, 0, width))
          }
      }
    }
  }
  layout
}

///|
fn Parser::const_field_layout(
  self : Parser,
  ty : Type,
  field : String,
) -> (String, Type, Int, Int, Int, Int)? {
  let name = match ty {
    Struct(n) | Union(n) => n
    Aligned(inner, _) | Atomic(inner) =>
      return self.const_field_layout(inner, field)
    _ => return None
  }
  if !self.struct_decls.contains(name) {
    return None
  }
  let decl = self.struct_decls[name]
  let layout = if decl.is_union {
    self.const_union_layout(decl)
  } else {
    self.const_struct_layout(decl)
  }
  for item in layout {
    if item.0 == field {
      return Some(item)
    }
  }
  None
}

///|
fn Parser::const_offset_of(
  self : Parser,
  ty : Type,
  path : Array[OffsetDesignator],
) -> Int? {
  let mut current_ty = ty
  let mut offset = 0
  for designator in path {
    match designator {
      OffsetField(field) =>
        match self.const_field_layout(current_ty, field) {
          Some((_, field_ty, field_offset, _, _, _)) => {
            offset += field_offset
            current_ty = field_ty
          }
          None => return None
        }
      OffsetIndex(index) =>
        match const_offset_array_element(current_ty) {
          Some(elem) => {
            offset += index.to_int() * self.const_type_size(elem)
            current_ty = elem
          }
          None => return None
        }
    }
  }
  Some(offset)
}

///|
fn const_offset_array_element(ty : Type) -> Type? {
  match ty {
    Array(elem, _) => Some(elem)
    Aligned(inner, _) | Atomic(inner) => const_offset_array_element(inner)
    _ => None
  }
}

///|
fn Parser::const_member_type(self : Parser, ty : Type, field : String) -> Type? {
  match ty {
    Pointer(inner) => self.const_member_type(inner, field)
    _ =>
      match self.const_field_layout(ty, field) {
        Some((_, field_ty, _, _, _, _)) => Some(field_ty)
        None => None
      }
  }
}

///|
fn type_of_expr(expr : Expr) -> Type {
  match expr {
    Number(_) => SInt
    FloatLiteral(_) => Double
    String(_) => Pointer(SChar)
    Var(_) => SInt // unknown, assume int
    Binary(_, _, _) => SInt
    Unary(_, _) => SInt
    Call(_, _) => SInt
    Assign(_, rhs) => type_of_expr(rhs)
    CompoundAssign(_, lhs, _) => type_of_expr(lhs)
    MemberAccess(_, _) => SInt
    Deref(_) => SInt
    AddrOf(_) => Pointer(SInt)
    ArrayAccess(_, _) => SInt
    Sizeof(_) => SInt
    SizeofExpr(_) => SInt
    Alignof(_) => SInt
    AlignofExpr(_) => SInt
    Cast(ty, _) => ty
    PrefixInc(_) => SInt
    PrefixDec(_) => SInt
    PostfixInc(_) => SInt
    PostfixDec(_) => SInt
    Ternary(_, a, _) => type_of_expr(a)
    LabelAddr(_) => Pointer(Void)
    VaArg(_, ty) => ty
    OffsetOf(_, _) => SInt
    Array(_) => SInt
    CompoundLiteral(ty, _, _) => ty
    DesignatedField(_, e) => type_of_expr(e)
    DesignatedIndex(_, e) => type_of_expr(e)
    DesignatedRange(_, _, e) => type_of_expr(e)
  }
}

///|
fn const_atomic_target_type(ty : Type) -> Type {
  match ty {
    Pointer(Atomic(inner)) | Array(Atomic(inner), _) => inner
    Pointer(Aligned(inner, _)) | Array(Aligned(inner, _), _) => inner
    Pointer(inner) | Array(inner, _) => inner
    Atomic(inner) | Aligned(inner, _) => inner
    _ => SLongLong
  }
}

///|
fn Parser::const_builtin_return_type(
  self : Parser,
  name : String,
  args : Array[Expr],
) -> Type? {
  match name {
    "__builtin_object_size" | "__builtin_dynamic_object_size" => Some(ULong)
    "__builtin_return_address"
    | "__builtin_frame_address"
    | "__builtin_extract_return_addr"
    | "__builtin_frob_return_addr" => Some(Pointer(Void))
    "__builtin_alloca" => Some(Pointer(Void))
    "__builtin_memcpy"
    | "__builtin___memcpy_chk"
    | "__builtin_memmove"
    | "__builtin___memmove_chk"
    | "__builtin_memset"
    | "__builtin___memset_chk"
    | "__builtin_memchr" => Some(Pointer(Void))
    "__builtin_strlen" => Some(ULong)
    "__builtin_memcmp" | "__builtin_strcmp" | "__builtin_strncmp" => Some(SInt)
    "__builtin_strcpy"
    | "__builtin___strcpy_chk"
    | "__builtin___strcat_chk"
    | "__builtin___strncpy_chk"
    | "__builtin___strncat_chk"
    | "__builtin_strchr"
    | "__builtin_strrchr"
    | "__builtin_strstr" => Some(Pointer(SChar))
    "__builtin___strlcpy_chk" | "__builtin___strlcat_chk" => Some(ULong)
    "__builtin___snprintf_chk"
    | "__builtin___vsnprintf_chk"
    | "__builtin___sprintf_chk"
    | "__builtin___vsprintf_chk"
    | "__builtin___printf_chk"
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
    "__atomic_load_n"
    | "__c11_atomic_load"
    | "__atomic_add_fetch"
    | "__atomic_sub_fetch"
    | "__c11_atomic_fetch_add"
    | "__c11_atomic_fetch_sub"
    | "__c11_atomic_fetch_and"
    | "__c11_atomic_fetch_or"
    | "__c11_atomic_fetch_xor"
    | "__c11_atomic_exchange" =>
      if args.length() > 0 {
        Some(const_atomic_target_type(self.const_expr_type(args[0])))
      } else {
        Some(SLongLong)
      }
    "__c11_atomic_compare_exchange_strong"
    | "__c11_atomic_compare_exchange_weak" => Some(Bool)
    "__atomic_store_n" | "__c11_atomic_store" | "__sync_synchronize" =>
      Some(Void)
    "__builtin_assume_aligned" =>
      if args.length() > 0 {
        Some(self.const_expr_type(args[0]))
      } else {
        Some(Pointer(Void))
      }
    "__builtin_expect"
    | "__builtin_expect_with_probability"
    | "__builtin_unpredictable" =>
      if args.length() > 0 {
        Some(self.const_expr_type(args[0]))
      } else {
        Some(SInt)
      }
    "__builtin_constant_p"
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
    "__builtin_align_up" | "__builtin_align_down" =>
      if args.length() > 0 {
        Some(self.const_expr_type(args[0]))
      } else {
        Some(ULong)
      }
    "__builtin_bswap16" => Some(UShort)
    "__builtin_bswap32"
    | "__builtin_rotateleft32"
    | "__builtin_rotateright32" => Some(UInt)
    "__builtin_bswap64"
    | "__builtin_rotateleft64"
    | "__builtin_rotateright64" => Some(ULongLong)
    "__builtin_bswap" | "__builtin_rotateleft" | "__builtin_rotateright" =>
      if args.length() > 0 {
        Some(self.const_expr_type(args[0]))
      } else {
        Some(UInt)
      }
    "__builtin_isgreater"
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
    | "__builtin_signbitl" => Some(SInt)
    _ => None
  }
}

///|
fn Parser::const_expr_type(self : Parser, expr : Expr) -> Type {
  match expr {
    Sizeof(_) | SizeofExpr(_) | Alignof(_) | AlignofExpr(_) | OffsetOf(_, _) =>
      ULong
    Cast(ty, _) => ty
    Var(name) =>
      if self.value_types.contains(name) {
        self.value_types[name]
      } else {
        type_of_expr(expr)
      }
    AddrOf(e) => Pointer(self.const_expr_type(e))
    Deref(e) =>
      match self.const_expr_type(e) {
        Pointer(elem) | Array(elem, _) => elem
        _ => SInt
      }
    ArrayAccess(e, _) =>
      match self.const_expr_type(e) {
        Pointer(elem) | Array(elem, _) => elem
        _ => SInt
      }
    MemberAccess(obj, field) =>
      match self.const_member_type(self.const_expr_type(obj), field) {
        Some(ty) => ty
        None => SInt
      }
    String(s) => Array(SChar, s.length() + 1)
    FloatLiteral(_) => Double
    Number(_) => SInt
    CompoundLiteral(ty, _, _) => ty
    Call(Var(name), args) =>
      match self.const_builtin_return_type(name, args) {
        Some(ty) => ty
        None => type_of_expr(expr)
      }
    DesignatedField(_, e) => self.const_expr_type(e)
    DesignatedIndex(_, e) => self.const_expr_type(e)
    DesignatedRange(_, _, e) => self.const_expr_type(e)
    Binary(",", _, rhs) => self.const_expr_type(rhs)
    Ternary(_, a, _) => self.const_expr_type(a)
    Assign(_, rhs) => self.const_expr_type(rhs)
    CompoundAssign(_, lhs, _) => self.const_expr_type(lhs)
    _ => type_of_expr(expr)
  }
}
