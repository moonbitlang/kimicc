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
///
/// `is_anonymous` records that the definition was written without a tag and
/// `name` was synthesized by the parser. It is semantics, not merely
/// provenance: an empty-named field whose type is anonymous is a C11
/// anonymous member, whose members reach through to the parent, while the
/// same field with a written tag is a tag declaration that declares no
/// member at all -- and no inspection of the name can tell the two apart,
/// since real headers write `__anon_` tags of their own. Equality therefore
/// includes it.
pub(all) struct StructDecl {
  name : String
  fields : Array[Param]
  is_union : Bool
  pack : Int?
  is_anonymous : Bool
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
/// One top-level entry of a translation unit, in the order it was written,
/// as an index into the matching grouped array.
///
/// The grouped arrays on `Program` answer "what aggregates exist" without a
/// walk; this is the other view, the document itself. C requires declaration
/// before use at file scope, so a printer working from the groups alone emits
/// every global before every function and breaks any initializer that names a
/// function declared later. The order is data the source carried, and this is
/// where it is kept.
///
/// Entries are indices rather than values so the grouped arrays stay
/// authoritative: replacing `program.globals[0]` with a transformed
/// declaration is the ordinary way to edit a program, and a value here would
/// keep printing the original. `Aggregate(i)` names `structs[i]`, and not
/// every aggregate has an entry -- a definition written inside another
/// aggregate's member list prints inside its parent and takes no top-level
/// place of its own.
pub(all) enum TopLevel {
  Aggregate(Int)
  Global(Int)
  Func(Int)
} derive(Eq, Debug)

///|
/// Parsed C translation unit.
///
/// `structs` stores aggregate declarations, `globals` stores global variables,
/// and `decls` stores function declarations and definitions -- grouped views
/// for consumers that ask by kind. `items` holds the same entries in source
/// order as indices into the groups, and is what the printer walks. A
/// hand-built `Program` may leave `items` empty, in which case printing falls
/// back to the grouped order: aggregates, then globals, then functions.
pub(all) struct Program {
  structs : Array[StructDecl]
  globals : Array[GlobalDecl]
  decls : Array[FuncDecl]
  items : Array[TopLevel]
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
