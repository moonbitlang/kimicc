///|
/// Compatibility alias for the parser-neutral C type model.
pub type Type = @ctype.Type

///|
/// C expression tree.
///
/// Binary and unary operators are stored as source-level operator strings such
/// as `"+"`, `"=="`, `"*"`, and `"!"`.
pub(all) enum Expr {
  // Literals carry the type their suffix selected. Dropping it made
  // `sizeof(1L)` report 4 and `sizeof(1.0f)` report 8.
  Number(Int64, Type)
  // The text that was written, not a parsed value: `long double` can be wider
  // than `Double`, so parsing eagerly would silently truncate what the program
  // said. Use `@ctype.floating_literal_value` to convert.
  FloatLiteral(String, Type)
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
} derive(Eq, Debug)

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
} derive(Eq, Debug)

///|
/// Function parameter or aggregate field.
///
/// `bit_width` is `Some(width)` for C bit-fields and `None` otherwise.
pub(all) struct Param {
  ty : Type
  name : String
  bit_width : Int?
} derive(Eq, Debug)

///|
/// Struct or union declaration.
///
/// `is_union` distinguishes `union` declarations from `struct` declarations.
///
/// `pack` caps the alignment of every field, covering both the GNU `packed`
/// attribute (equivalent to `Some(1)`) and `#pragma pack(N)` (`Some(n)`).
/// `None` means fields keep their natural alignment.
pub(all) struct StructDecl {
  name : String
  fields : Array[Param]
  is_union : Bool
  pack : Int?
} derive(Eq, Debug)

///|
/// Caps `natural` alignment by an aggregate's `pack` value.
///
/// This is the single rule behind both `__attribute__((packed))` and
/// `#pragma pack(N)`: a field is aligned to the smaller of its natural
/// alignment and the cap in effect.
pub fn packed_align(pack : Int?, natural : Int) -> Int {
  match pack {
    Some(n) => if n < natural { n } else { natural }
    None => natural
  }
}

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
} derive(Eq, Debug)

///|
/// Global initializer representation.
///
/// `Scalar` covers scalar initializers and `Array` covers brace initializer
/// lists, including aggregate initializers.
pub(all) enum GlobalInit {
  Scalar(Expr)
  Array(Array[Expr])
} derive(Eq, Debug)

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
} derive(Eq, Debug)

///|
/// Parsed C translation unit.
///
/// `structs` stores aggregate declarations, `globals` stores global variables,
/// and `decls` stores function declarations and definitions.
pub(all) struct Program {
  structs : Array[StructDecl]
  globals : Array[GlobalDecl]
  decls : Array[FuncDecl]
} derive(Eq, Debug)
