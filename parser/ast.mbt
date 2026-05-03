///|
pub(all) enum Type {
  Int
  Void
  Char
  Struct(String)
  Pointer(Type)
  Array(Type, Int)
} derive(Eq)

///|
pub impl Show for Type with to_string(self) {
  match self {
    Int => "Int"
    Void => "Void"
    Char => "Char"
    Struct(name) => "Struct(" + name + ")"
    Pointer(ty) => "Pointer(" + ty.to_string() + ")"
    Array(ty, n) => "Array(" + ty.to_string() + ", " + n.to_string() + ")"
  }
}

///|
pub(all) enum Expr {
  Number(Int)
  String(String)
  Var(String)
  Binary(String, Expr, Expr)
  Unary(String, Expr)
  Call(String, Array[Expr])
  Assign(Expr, Expr)
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
} derive(Eq)

///|
pub(all) enum Stmt {
  ExprStmt(Expr)
  Return(Expr?)
  If(Expr, Stmt, Stmt?)
  While(Expr, Stmt)
  Compound(Array[Stmt])
  VarDecl(Type, String, Expr?)
  Break
  Continue
  Switch(Expr, Array[(Int?, Stmt)])
  Goto(String)
  Label(String, Stmt)
  For(Stmt?, Expr, Expr?, Stmt)
  DoWhile(Expr, Stmt)
} derive(Eq)

///|
pub(all) struct Param {
  ty : Type
  name : String
} derive(Eq)

///|
pub(all) struct StructDecl {
  name : String
  fields : Array[Param]
} derive(Eq)

///|
pub(all) struct FuncDecl {
  ret : Type
  name : String
  params : Array[Param]
  body : Stmt?
} derive(Eq)

///|
pub(all) struct Program {
  structs : Array[StructDecl]
  globals : Array[(Type, String)]
  decls : Array[FuncDecl]
}
