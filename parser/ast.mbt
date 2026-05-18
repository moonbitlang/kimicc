///|
/// Compatibility alias for the parser-neutral C type model.
pub type Type = @ctype.Type

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
  Alignof(Type)
  AlignofExpr(Expr)
  Cast(Type, Expr)
  PrefixInc(Expr)
  PrefixDec(Expr)
  PostfixInc(Expr)
  PostfixDec(Expr)
  Ternary(Expr, Expr, Expr)
  LabelAddr(String)
  VaArg(Expr, Type)
  OffsetOf(Type, Array[OffsetDesignator])
  Array(Array[Expr])
  CompoundLiteral(Type, Array[Expr], Int)
  DesignatedField(String, Expr)
  DesignatedIndex(Int64, Expr)
  DesignatedRange(Int64, Int64, Expr)
} derive(Eq)

///|
/// Compatibility alias for parser-neutral offsetof designators.
pub type OffsetDesignator = @ctype.OffsetDesignator

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
/// `is_packed` records GNU `packed` layout attributes on the aggregate.
pub(all) struct StructDecl {
  name : String
  fields : Array[Param]
  is_union : Bool
  is_packed : Bool
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
  is_weak : Bool
  visibility : String?
  symbol_alias : String?
  section : String?
  is_constructor : Bool
  is_destructor : Bool
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
  is_weak : Bool
  visibility : String?
  symbol_alias : String?
  section : String?
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
