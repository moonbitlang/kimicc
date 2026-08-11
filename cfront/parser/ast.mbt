///|
/// Compatibility alias for the parser-neutral C type model.
pub type Type = @ctype.Type

///|
/// C expression tree.
///
/// Binary and unary operators are stored as source-level operator strings such
/// as `"+"`, `"=="`, `"*"`, and `"!"`.
pub(all) enum Expr {
  // An integer literal keeps the text that was written, the value it denotes,
  // and the type its suffix selected. The text is authoritative -- it is what
  // distinguishes `0xff` from `255` and survives printing -- and the value is a
  // cache for constant folding, which is hot enough that re-parsing at each
  // fold would be wasteful. Build these with `int_literal` rather than by hand
  // so the two cannot disagree.
  Number(Int64, String, Type)
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
/// conditions are represented internally as a truthy expression, and `init`
/// is empty for `for (;;)`.
///
/// `VarDecl` declares one name. C lets one declaration introduce several --
/// `int a, b;` -- and those are recorded as one `VarDecl` each, side by side in
/// the enclosing block, because the grouping carries no meaning a consumer
/// could act on and nothing a generator would want to build. The declared type
/// is per-name already, since `int *a, b` declares a pointer and an int.
///
/// `Case` and `Default` are labels rather than clauses: they wrap the single
/// statement they label, exactly as C spells them, and the statements that
/// follow are siblings the switch falls through into. `Case` holds the value
/// its constant expression folds to, not the expression as written.
pub(all) enum Stmt {
  ExprStmt(Expr)
  Return(Expr?)
  If(Expr, Stmt, Stmt?)
  While(Expr, Stmt)
  Compound(Array[Stmt])
  VarDecl(Type, String, Expr?)
  Break
  Continue
  Switch(Expr, Stmt)
  Case(Int64, Stmt)
  Default(Stmt)
  Goto(String)
  Label(String, Stmt)
  For(Array[Stmt], Expr, Expr?, Stmt)
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

///|
/// Builds an integer literal from a value, formatting the text canonically.
///
/// Prefer this to constructing `Number` directly: the text is authoritative and
/// the value is a cache of it, so they must agree, and this is what guarantees
/// that for a literal the compiler synthesises rather than reads from source.
pub fn int_literal(value : Int64, ty : Type) -> Expr {
  Number(value, value.to_string(), ty)
}
