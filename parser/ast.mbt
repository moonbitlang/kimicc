///|
/// C type representation used by the parser and code generator.
///
/// `Struct(name)` and `Union(name)` identify aggregate declarations by name;
/// layout-sensitive operations need the corresponding `StructDecl`.
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
  Double
  Struct(String)
  Union(String)
  FuncPtr(Type, Int, Bool)
  Pointer(Type)
  Array(Type, Int)
  Atomic(Type)
  Aligned(Type, Int)
} derive(Eq)

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
    Double => "Double"
    Struct(name) => "Struct(" + name + ")"
    Union(name) => "Union(" + name + ")"
    FuncPtr(ret, count, variadic) =>
      "FuncPtr(" +
      ret.to_string() +
      ", " +
      count.to_string() +
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
/// Returns true for `float` and `double`.
pub fn Type::is_floating(self : Type) -> Bool {
  match self {
    Float | Double => true
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
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    SInt128 | UInt128 => 16
    Struct(name) =>
      // Forward reference: we can't compute struct size without the decl.
      // Callers should use codegen's type_size which has struct_decls.
      abort("Cannot compute struct size without struct_decls: " + name)
    Union(name) =>
      abort("Cannot compute union size without struct_decls: " + name)
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
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    SInt128 | UInt128 => 16
    Struct(name) =>
      abort("Cannot compute struct alignment without struct_decls: " + name)
    Union(name) =>
      abort("Cannot compute union alignment without struct_decls: " + name)
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
/// C expression tree.
///
/// Binary and unary operators are stored as source-level operator strings such
/// as `"+"`, `"=="`, `"*"`, and `"!"`.
pub(all) enum Expr {
  Number(Int64)
  FloatLiteral(Double)
  String(String)
  Var(String)
  Binary(String, Expr, Expr)
  Unary(String, Expr)
  Call(Expr, Array[Expr])
  Assign(Expr, Expr)
  CompoundAssign(String, Expr, Expr)
  MemberAccess(Expr, String)
  Deref(Expr)
  AddrOf(Expr)
  ArrayAccess(Expr, Expr)
  Sizeof(Type)
  SizeofExpr(Expr)
  Cast(Type, Expr)
  PrefixInc(Expr)
  PrefixDec(Expr)
  PostfixInc(Expr)
  PostfixDec(Expr)
  Ternary(Expr, Expr, Expr)
  LabelAddr(String)
  VaArg(Expr, Type)
  OffsetOf(Type, String)
  Array(Array[Expr])
  CompoundLiteral(Type, Array[Expr], Int)
  DesignatedField(String, Expr)
  DesignatedIndex(Int64, Expr)
  DesignatedRange(Int64, Int64, Expr)
} derive(Eq)

///|
/// C statement tree.
///
/// Compound statements contain nested statement arrays. `For(init, cond, inc,
/// body)` stores the condition as an expression; parser-generated empty
/// conditions are represented internally as a truthy expression.
pub(all) enum Stmt {
  ExprStmt(Expr)
  Return(Expr?)
  If(Expr, Stmt, Stmt?)
  While(Expr, Stmt)
  Compound(Array[Stmt])
  StmtList(Array[Stmt])
  VarDecl(Type, String, Expr?)
  Break
  Continue
  Switch(Expr, Stmt, Array[(Int64?, String)])
  Goto(String)
  Label(String, Stmt)
  For(Stmt?, Expr, Expr?, Stmt)
  DoWhile(Expr, Stmt)
  ComputedGoto(Expr)
} derive(Eq)

///|
/// Function parameter or aggregate field.
///
/// `bit_width` is `Some(width)` for C bit-fields and `None` otherwise.
pub(all) struct Param {
  ty : Type
  name : String
  bit_width : Int?
} derive(Eq)

///|
/// Struct or union declaration.
///
/// `is_union` distinguishes `union` declarations from `struct` declarations.
pub(all) struct StructDecl {
  name : String
  fields : Array[Param]
  is_union : Bool
} derive(Eq)

///|
/// Function declaration or definition.
///
/// `body` is `None` for declarations without a function body.
pub(all) struct FuncDecl {
  ret : Type
  name : String
  params : Array[Param]
  variadic : Bool
  is_static : Bool
  is_inline : Bool
  body : Stmt?
} derive(Eq)

///|
/// Global initializer representation.
///
/// `Scalar` covers scalar initializers and `Array` covers brace initializer
/// lists, including aggregate initializers.
pub(all) enum GlobalInit {
  Scalar(Expr)
  Array(Array[Expr])
} derive(Eq)

///|
/// Global variable declaration or definition.
///
/// `init` is `None` for declarations without an initializer.
pub(all) struct GlobalDecl {
  ty : Type
  name : String
  init : GlobalInit?
  is_static : Bool
  is_extern : Bool
} derive(Eq)

///|
/// Parsed C translation unit.
///
/// `structs` stores aggregate declarations, `globals` stores global variables,
/// and `decls` stores function declarations and definitions.
pub(all) struct Program {
  structs : Array[StructDecl]
  globals : Array[GlobalDecl]
  decls : Array[FuncDecl]
}
