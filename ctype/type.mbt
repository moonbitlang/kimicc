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
} derive(Eq)

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
pub impl Show for Type with to_string(self) {
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
pub(all) enum OffsetDesignator {
  OffsetField(String)
  OffsetIndex(Int64)
} derive(Eq)
