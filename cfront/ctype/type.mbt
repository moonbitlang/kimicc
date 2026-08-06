///|
/// C type representation shared by parser, MIR, and code generators.
///
/// `Struct(name)` and `Union(name)` identify aggregate declarations by name;
/// layout-sensitive operations need target-specific aggregate layout facts.
pub(all) enum Type {
  Void
  Bool
  SChar
  UChar
  SShort
  UShort
  SInt
  UInt
  SLong
  ULong
  SLongLong
  ULongLong
  SInt128
  UInt128
  Float
  Float16
  Float128
  Double
  LongDouble
  Struct(String)
  Union(String)
  FuncPtr(Type, Array[Type], Bool)
  Pointer(Type)
  Array(Type, Int)
  Atomic(Type)
  Aligned(Type, Int)
} derive(Eq, Debug)

///|
fn type_array_to_string(types : Array[Type]) -> String {
  let mut result = "["
  for i in 0..<types.length() {
    if i > 0 {
      result = result + ", "
    }
    result = result + types[i].to_string()
  }
  result + "]"
}

///|
pub impl Show for Type with fn to_string(self) {
  match self {
    Void => "Void"
    Bool => "Bool"
    SChar => "SChar"
    UChar => "UChar"
    SShort => "SShort"
    UShort => "UShort"
    SInt => "SInt"
    UInt => "UInt"
    SLong => "SLong"
    ULong => "ULong"
    SLongLong => "SLongLong"
    ULongLong => "ULongLong"
    SInt128 => "SInt128"
    UInt128 => "UInt128"
    Float => "Float"
    Float16 => "Float16"
    Float128 => "Float128"
    Double => "Double"
    LongDouble => "LongDouble"
    Struct(name) => "Struct(" + name + ")"
    Union(name) => "Union(" + name + ")"
    FuncPtr(ret, params, variadic) =>
      "FuncPtr(" +
      ret.to_string() +
      ", " +
      type_array_to_string(params) +
      ", " +
      variadic.to_string() +
      ")"
    Pointer(ty) => "Pointer(" + ty.to_string() + ")"
    Array(ty, n) => "Array(" + ty.to_string() + ", " + n.to_string() + ")"
    Atomic(ty) => "Atomic(" + ty.to_string() + ")"
    Aligned(ty, align) =>
      "Aligned(" + ty.to_string() + ", " + align.to_string() + ")"
  }
}

///|
/// Removes transparent C type wrappers that do not change the underlying value
/// category for parser-neutral semantic queries.
pub fn Type::core_type(self : Type) -> Type {
  match self {
    Atomic(inner) | Aligned(inner, _) => inner.core_type()
    _ => self
  }
}

///|
/// Removes only top-level alignment wrappers, preserving qualifiers such as
/// `_Atomic`.
pub fn Type::without_alignment(self : Type) -> Type {
  match self {
    Aligned(inner, _) => inner.without_alignment()
    _ => self
  }
}

///|
/// Returns true for compiler-generated anonymous aggregate names.
///
/// Anonymous aggregate fields are flattened during layout. `Atomic` and
/// `Aligned` wrappers delegate to the wrapped aggregate type.
pub fn Type::is_anonymous_aggregate(self : Type) -> Bool {
  match self.core_type() {
    Struct(name) | Union(name) => name.has_prefix("__anon_")
    _ => false
  }
}

///|
/// Returns the element type of arrays after removing transparent wrappers.
pub fn Type::array_element(self : Type) -> Type? {
  match self.core_type() {
    Array(elem, _) => Some(elem)
    _ => None
  }
}

///|
/// Returns the pointee/element type of pointer-like expressions after removing
/// transparent wrappers.
pub fn Type::pointer_or_array_element(self : Type) -> Type? {
  match self.core_type() {
    Pointer(elem) | Array(elem, _) => Some(elem)
    _ => None
  }
}

///|
/// Returns the aggregate type used for field lookup on either an aggregate
/// value or a pointer to an aggregate value.
pub fn Type::field_receiver(self : Type) -> Type? {
  match self.core_type() {
    Struct(name) => Some(Struct(name))
    Union(name) => Some(Union(name))
    Pointer(inner) =>
      match inner.core_type() {
        Struct(name) => Some(Struct(name))
        Union(name) => Some(Union(name))
        _ => None
      }
    _ => None
  }
}

///|
/// Returns true for scalar integer types.
///
/// `Aligned(inner, _)` delegates to `inner`. Pointers are not considered
/// integers by this predicate.
pub fn Type::is_integer(self : Type) -> Bool {
  match self {
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
    | UInt128 => true
    Aligned(ty, _) => ty.is_integer()
    _ => false
  }
}

///|
/// Returns true for signed scalar integer types.
///
/// `Aligned(inner, _)` delegates to `inner`. Non-integer types return false.
pub fn Type::is_signed(self : Type) -> Bool {
  match self {
    SChar | SShort | SInt | SLong | SLongLong | SInt128 => true
    Aligned(ty, _) => ty.is_signed()
    _ => false
  }
}

///|
/// Returns true for unsigned scalar integer types, excluding `_Bool`.
///
/// This is used by runtime code generation decisions. Constant folding uses
/// `const_is_unsigned`, where `_Bool` is unsigned-like because conversion clamps
/// to `0` or `1`.
pub fn Type::is_unsigned_integer(self : Type) -> Bool {
  match self.core_type() {
    UChar | UShort | UInt | ULong | ULongLong | UInt128 => true
    _ => false
  }
}

///|
/// Returns true for signed or unsigned `__int128` after transparent wrappers.
pub fn Type::is_int128(self : Type) -> Bool {
  match self.core_type() {
    SInt128 | UInt128 => true
    _ => false
  }
}

///|
/// Returns true for the ordinary floating types directly handled by the current
/// scalar backends.
pub fn Type::is_float_or_double(self : Type) -> Bool {
  match self.core_type() {
    Float | Double => true
    _ => false
  }
}

///|
/// Returns true for aggregate record types after transparent wrappers.
pub fn Type::is_aggregate(self : Type) -> Bool {
  match self.core_type() {
    Struct(_) | Union(_) => true
    _ => false
  }
}

///|
/// Returns true for object-valued aggregate types after transparent wrappers.
pub fn Type::is_object_aggregate(self : Type) -> Bool {
  match self.core_type() {
    Array(_, _) | Struct(_) | Union(_) => true
    _ => false
  }
}

///|
/// Returns true for integer-like types treated as unsigned during integer
/// constant folding.
///
/// `_Bool` is included here because constant conversion clamps it to `0` or
/// `1`. `Atomic` and `Aligned` qualifiers delegate to their inner type.
pub fn Type::const_is_unsigned(self : Type) -> Bool {
  match self {
    Bool | UChar | UShort | UInt | ULong | ULongLong | UInt128 => true
    Atomic(ty) | Aligned(ty, _) => ty.const_is_unsigned()
    _ => false
  }
}

///|
/// Returns the bit width used by integer constant folding for this type.
///
/// This is intentionally not the ABI storage width: `_Bool` folds as a 1-bit
/// value. Pointer-like values use the current compiler's 64-bit address model.
pub fn Type::const_int_width(self : Type) -> Int? {
  match self {
    Bool => Some(1)
    SChar | UChar => Some(8)
    SShort | UShort => Some(16)
    SInt | UInt => Some(32)
    SLong | ULong | SLongLong | ULongLong | Pointer(_) | FuncPtr(_, _, _) =>
      Some(64)
    SInt128 | UInt128 => Some(128)
    Atomic(ty) | Aligned(ty, _) => ty.const_int_width()
    _ => None
  }
}

///|
/// Converts integer bits as if casting to this C integer type for constant
/// folding.
///
/// The result is still carried in `Int64`; 64-bit unsigned results therefore
/// keep their two's-complement bit pattern.
pub fn Type::cast_integer_bits(self : Type, bits : Int64) -> Int64 {
  let core_ty = self.core_type()
  match core_ty.const_int_width() {
    None => bits
    Some(1) => if bits == 0L { 0L } else { 1L }
    Some(width) =>
      if width >= 64 {
        bits
      } else {
        let mask = (1L << width) - 1L
        let narrowed = bits & mask
        if core_ty.const_is_unsigned() {
          narrowed
        } else {
          let sign = 1L << (width - 1)
          if (narrowed & sign) != 0L {
            narrowed | mask.lnot()
          } else {
            narrowed
          }
        }
      }
  }
}

///|
/// Returns the default type assigned to an integer literal token.
pub fn integer_literal_type(value : Int64) -> Type {
  if value < -2147483648L || value > 2147483647L {
    SLongLong
  } else {
    SInt
  }
}

///|
/// Returns the type used by constant folding for a lexer-encoded integer token.
///
/// The current lexer stores integer token bits in `Int64` and drops suffix
/// metadata. Negative bit patterns therefore represent constants that overflow
/// signed 64-bit storage, and are treated as unsigned long long.
pub fn integer_constant_token_type(bits : Int64) -> Type {
  if bits < 0L {
    ULongLong
  } else {
    integer_literal_type(bits)
  }
}

///|
/// Returns the integer width selected by generic `__builtin_bswap`.
pub fn Type::generic_builtin_bswap_width(self : Type) -> Int {
  let width = self.const_int_width().unwrap_or(64)
  if width <= 16 {
    16
  } else if width <= 32 {
    32
  } else {
    64
  }
}

///|
/// Returns the integer width selected by generic rotate builtins.
pub fn Type::generic_builtin_rotate_width(self : Type) -> Int {
  let width = self.const_int_width().unwrap_or(64)
  if width <= 32 {
    32
  } else {
    64
  }
}

///|
/// Returns the usual integer conversion rank for scalar integer types.
pub fn Type::integer_rank(self : Type) -> Int {
  match self {
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt => 3
    SLong | ULong => 4
    SLongLong | ULongLong => 5
    SInt128 | UInt128 => 6
    Atomic(ty) | Aligned(ty, _) => ty.integer_rank()
    _ => 0
  }
}

///|
fn unsigned_type_for_rank(rank : Int) -> Type {
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
fn signed_type_for_rank(rank : Int) -> Type {
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
/// Applies the integer promotions used by C unary and binary integer
/// expressions.
pub fn Type::integer_promote(self : Type) -> Type {
  match self {
    Bool | SChar | UChar | SShort | UShort => SInt
    Atomic(ty) | Aligned(ty, _) => ty.integer_promote()
    _ => self
  }
}

///|
/// Returns the common integer type selected by the usual arithmetic
/// conversions after integer promotion.
pub fn integer_common_type(left : Type, right : Type) -> Type {
  let lhs = left.integer_promote()
  let rhs = right.integer_promote()
  if lhs == rhs {
    return lhs
  }
  if !lhs.is_integer() || !rhs.is_integer() {
    return lhs
  }
  let lhs_unsigned = lhs.const_is_unsigned()
  let rhs_unsigned = rhs.const_is_unsigned()
  let lhs_rank = lhs.integer_rank()
  let rhs_rank = rhs.integer_rank()
  if lhs_unsigned == rhs_unsigned {
    let rank = if lhs_rank > rhs_rank { lhs_rank } else { rhs_rank }
    if lhs_unsigned {
      unsigned_type_for_rank(rank)
    } else {
      signed_type_for_rank(rank)
    }
  } else {
    let unsigned = if lhs_unsigned { lhs } else { rhs }
    let signed = if lhs_unsigned { rhs } else { lhs }
    let unsigned_rank = unsigned.integer_rank()
    let signed_rank = signed.integer_rank()
    let unsigned_width = unsigned.const_int_width().unwrap_or(0)
    let signed_width = signed.const_int_width().unwrap_or(0)
    if unsigned_rank >= signed_rank {
      unsigned
    } else if signed_width > unsigned_width {
      signed
    } else {
      unsigned_type_for_rank(signed_rank)
    }
  }
}

///|
/// Returns true for supported floating arithmetic types under the default
/// Darwin ARM64 layout assumptions.
pub fn Type::is_floating(self : Type) -> Bool {
  match self {
    Float | Double | LongDouble => true
    Aligned(ty, _) => ty.is_floating()
    _ => false
  }
}

///|
/// Returns true for floating arithmetic types supported by a specific semantic
/// consumer. Some targets can parse `long double` but do not yet support it in
/// MIR/backend arithmetic.
pub fn Type::is_floating_with_long_double(
  self : Type,
  allow_long_double : Bool,
) -> Bool {
  match self.core_type() {
    Float | Double => true
    LongDouble => allow_long_double
    _ => false
  }
}

///|
/// Applies C unary numeric result selection for scalar types.
pub fn unary_numeric_result_type(ty : Type, allow_long_double : Bool) -> Type {
  if ty.is_floating_with_long_double(allow_long_double) {
    ty
  } else {
    ty.integer_promote()
  }
}

///|
fn floating_common_type(
  lhs : Type,
  rhs : Type,
  allow_long_double : Bool,
) -> Type {
  let lhs_core = lhs.core_type()
  let rhs_core = rhs.core_type()
  if allow_long_double && (lhs_core == LongDouble || rhs_core == LongDouble) {
    LongDouble
  } else if lhs_core == Double || rhs_core == Double {
    Double
  } else {
    Float
  }
}

///|
/// Returns the parser-neutral scalar result type for C binary operators.
pub fn binary_result_type(
  op : String,
  lhs : Type,
  rhs : Type,
  allow_long_double : Bool,
) -> Type {
  match op {
    "==" | "!=" | "<" | ">" | "<=" | ">=" | "&&" | "||" => SInt
    "," => rhs
    "<<" | ">>" => lhs.integer_promote()
    _ =>
      if lhs.is_floating_with_long_double(allow_long_double) ||
        rhs.is_floating_with_long_double(allow_long_double) {
        floating_common_type(lhs, rhs, allow_long_double)
      } else if lhs.is_integer() && rhs.is_integer() {
        integer_common_type(lhs, rhs)
      } else {
        SInt
      }
  }
}

///|
/// Returns the parser-neutral result type for C binary expressions, including
/// pointer arithmetic/difference and legacy constant-shift widening used by the
/// existing compiler frontends.
pub fn binary_expr_result_type(
  op : String,
  lhs : Type,
  rhs : Type,
  force_wide_shift : Bool,
  allow_long_double : Bool,
) -> Type {
  if force_wide_shift && (op == "<<" || op == ">>") {
    return ULongLong
  }
  if op == "-" &&
    lhs.pointer_or_array_element() is Some(_) &&
    rhs.pointer_or_array_element() is Some(_) {
    return SLong
  }
  match lhs.pointer_or_array_element() {
    Some(elem) =>
      if (op == "+" || op == "-") && rhs.is_integer() {
        return Pointer(elem)
      }
    None => ()
  }
  match rhs.pointer_or_array_element() {
    Some(elem) => if op == "+" && lhs.is_integer() { return Pointer(elem) }
    None => ()
  }
  binary_result_type(op, lhs, rhs, allow_long_double)
}

///|
/// Returns the parser-neutral scalar result type for C ternary branches.
pub fn ternary_result_type(
  then_ty : Type,
  else_ty : Type,
  allow_long_double : Bool,
) -> Type {
  match (then_ty.core_type(), else_ty.core_type()) {
    (Array(elem, _), _) | (_, Array(elem, _)) => Pointer(elem)
    (Pointer(elem), _) | (_, Pointer(elem)) => Pointer(elem)
    (FuncPtr(ret, params, variadic), _) | (_, FuncPtr(ret, params, variadic)) =>
      FuncPtr(ret, params, variadic)
    _ =>
      if then_ty.is_floating_with_long_double(allow_long_double) ||
        else_ty.is_floating_with_long_double(allow_long_double) {
        floating_common_type(then_ty, else_ty, allow_long_double)
      } else if then_ty.is_integer() && else_ty.is_integer() {
        integer_common_type(then_ty, else_ty)
      } else {
        then_ty
      }
  }
}

///|
/// Converts a signed integer type to the corresponding unsigned type.
///
/// Types that are already unsigned or not integer types are returned unchanged.
pub fn Type::to_unsigned(self : Type) -> Type {
  match self {
    SChar => UChar
    SShort => UShort
    SInt => UInt
    SLong => ULong
    SLongLong => ULongLong
    SInt128 => UInt128
    Aligned(ty, align) => Aligned(ty.to_unsigned(), align)
    _ => self
  }
}

///|
/// Returns the value type targeted by atomic pointer-like builtin arguments.
///
/// Atomic builtins conventionally receive a pointer or array expression as
/// their first argument. Plain and qualified scalar values are also accepted as
/// a fallback for parser/MIR transitional callers.
pub fn Type::atomic_target(self : Type) -> Type {
  match self {
    Pointer(Atomic(inner)) | Array(Atomic(inner), _) => inner
    Pointer(Aligned(inner, _)) | Array(Aligned(inner, _), _) => inner
    Pointer(inner) | Array(inner, _) => inner
    Atomic(inner) | Aligned(inner, _) => inner
    _ => SLongLong
  }
}

///|
/// Returns the ABI size in bytes for this type under ARM64 macOS assumptions.
///
/// This method aborts for `Struct(name)` and `Union(name)` because a bare
/// `Type` does not include the aggregate declaration layout.
pub fn Type::size(self : Type) -> Int {
  match self {
    Void => 0
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt | Float => 4
    Float16 => abort("_Float16 size is not supported")
    Float128 => abort("__float128 size is not supported")
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | LongDouble
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    SInt128 | UInt128 => 16
    Struct(name) =>
      abort("Cannot compute struct size without aggregate layout: " + name)
    Union(name) =>
      abort("Cannot compute union size without aggregate layout: " + name)
    Array(elem, n) => elem.size() * n
    Atomic(ty) => ty.size()
    Aligned(ty, _) => ty.size()
  }
}

///|
/// Returns the ABI alignment in bytes under ARM64 macOS assumptions.
///
/// This method aborts for `Struct(name)` and `Union(name)` because aggregate
/// alignment depends on the corresponding declaration layout.
pub fn Type::align(self : Type) -> Int {
  match self {
    Void => 1
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt | Float => 4
    Float16 => abort("_Float16 alignment is not supported")
    Float128 => abort("__float128 alignment is not supported")
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | LongDouble
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    SInt128 | UInt128 => 16
    Struct(name) =>
      abort("Cannot compute struct alignment without aggregate layout: " + name)
    Union(name) =>
      abort("Cannot compute union alignment without aggregate layout: " + name)
    Array(elem, _) => elem.align()
    Atomic(ty) => ty.align()
    Aligned(ty, align) => {
      let inner = ty.align()
      if align > inner {
        align
      } else {
        inner
      }
    }
  }
}

///|
/// One step of a member-access path into an aggregate type.
///
/// A list of these designators describes a nested location such as
/// `s.field.arr[3]`, and is consumed by the layout queries
/// `@mir.Program::offset_of_path` / `@mir.MirModule::offset_of_path` (which
/// implement `__builtin_offsetof`) and the object-size facts.
///
/// - `OffsetField(name)` descends into the named struct or union field.
/// - `OffsetIndex(i)` steps `i` elements into an array.
pub(all) enum OffsetDesignator {
  OffsetField(String)
  OffsetIndex(Int64)
} derive(Eq, Debug)
