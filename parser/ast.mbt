///|
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
// Helper: check if type is any integer type (signed or unsigned)
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
// Helper: check if type is a signed integer type
pub fn Type::is_signed(self : Type) -> Bool {
  match self {
    SChar | SShort | SInt | SLong | SLongLong | SInt128 => true
    Aligned(ty, _) => ty.is_signed()
    _ => false
  }
}

///|
// Helper: check if type is a floating-point type
pub fn Type::is_floating(self : Type) -> Bool {
  match self {
    Float | Double => true
    Aligned(ty, _) => ty.is_floating()
    _ => false
  }
}

///|
// Helper: get the unsigned variant of a signed integer type
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
// Helper: get the size in bytes for a type (ARM64 macOS ABI)
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
// Helper: get the alignment in bytes for a type (ARM64 macOS ABI)
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
pub(all) struct Param {
  ty : Type
  name : String
  bit_width : Int?
} derive(Eq)

///|
pub(all) struct StructDecl {
  name : String
  fields : Array[Param]
  is_union : Bool
} derive(Eq)

///|
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
pub(all) enum GlobalInit {
  Scalar(Expr)
  Array(Array[Expr])
} derive(Eq)

///|
pub(all) struct GlobalDecl {
  ty : Type
  name : String
  init : GlobalInit?
  is_static : Bool
  is_extern : Bool
} derive(Eq)

///|
pub(all) struct Program {
  structs : Array[StructDecl]
  globals : Array[GlobalDecl]
  decls : Array[FuncDecl]
}
