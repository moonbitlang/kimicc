///|
/// Declaration-level builders for constructing a `Program` by hand.
///
/// This package is the construction half of the suite: a code generator --
/// the FFTW shape, a MoonBit program emitting optimized C kernels -- builds
/// declarations through these and prints the result, and everything built
/// here is in the canonical form the parser itself produces, so it
/// round-trips and satisfies the suite's property tests. The raw constructors
/// stay available for shapes these do not cover; the builders exist to
/// default the boilerplate, not to hide the AST.

///|
/// A function parameter. An outer array type adjusts to the pointer C says
/// it is -- `int a[3]` as a parameter *is* `int *a` -- which is also what
/// the parser records, so built programs keep their print/parse equality.
pub fn param(ty : @ctype.Type, name : String) -> @parser.Param {
  let adjusted : @ctype.Type = match ty {
    Array(elem, _) => Pointer(elem)
    other => other
  }
  { ty: adjusted, name, bit_width: None }
}

///|
/// A function definition. Nine of `FuncDecl`'s thirteen fields are attribute
/// boilerplate a generator rarely touches; they default here and stay
/// reachable as labels.
pub fn func(
  ret : @ctype.Type,
  name : String,
  params : Array[@parser.Param],
  body : Array[@parser.Stmt],
  variadic? : Bool = false,
  is_static? : Bool = false,
  is_inline? : Bool = false,
) -> @parser.FuncDecl {
  {
    ret,
    name,
    params,
    variadic,
    is_static,
    is_inline,
    is_weak: false,
    visibility: None,
    symbol_alias: None,
    section: None,
    is_constructor: false,
    is_destructor: false,
    body: Some(Compound(body)),
  }
}

///|
/// A function declaration without a body -- a prototype.
pub fn prototype(
  ret : @ctype.Type,
  name : String,
  params : Array[@parser.Param],
  variadic? : Bool = false,
  is_static? : Bool = false,
) -> @parser.FuncDecl {
  {
    ret,
    name,
    params,
    variadic,
    is_static,
    is_inline: false,
    is_weak: false,
    visibility: None,
    symbol_alias: None,
    section: None,
    is_constructor: false,
    is_destructor: false,
    body: None,
  }
}

///|
/// A global variable declaration or definition.
pub fn global(
  ty : @ctype.Type,
  name : String,
  init? : @parser.GlobalInit,
  is_static? : Bool = false,
  is_extern? : Bool = false,
) -> @parser.GlobalDecl {
  // A brace initializer over a scalar destination denotes the value inside,
  // which is what the parser records for `int x = {1}`.
  let canonical_init : @parser.GlobalInit? = match (ty.core_type(), init) {
    (Struct(_) | Union(_) | Array(_, _), _) => init
    (_, Some(Array(items))) =>
      Some(Scalar(@parser.scalar_initializer_value(Array(items))))
    _ => init
  }
  {
    ty: @parser.infer_global_array_type(ty, canonical_init),
    name,
    init: canonical_init,
    is_static,
    is_extern,
    is_weak: false,
    visibility: None,
    symbol_alias: None,
    section: None,
  }
}

///|
/// A struct or union definition with a written tag.
pub fn aggregate(
  name : String,
  fields : Array[@parser.Param],
  is_union? : Bool = false,
  pack? : Int,
) -> @parser.StructDecl {
  { name, fields, is_union, pack, is_anonymous: false }
}

///|
/// A field of an aggregate.
pub fn field(ty : @ctype.Type, name : String) -> @parser.Param {
  { ty, name, bit_width: None }
}

///|
/// A whole translation unit in canonical form: `items` is filled in the
/// order given -- aggregates, then globals, then functions -- which is what
/// a parsed program carries and what `Program` equality includes.
pub fn program(
  structs? : Array[@parser.StructDecl] = [],
  globals? : Array[@parser.GlobalDecl] = [],
  decls? : Array[@parser.FuncDecl] = [],
) -> @parser.Program {
  let items : Array[@parser.TopLevel] = []
  for i in 0..<structs.length() {
    items.push(Aggregate(i))
  }
  for i in 0..<globals.length() {
    items.push(Global(i))
  }
  for i in 0..<decls.length() {
    items.push(Func(i))
  }
  { structs, globals, decls, items }
}

///|
/// A local declaration statement.
pub fn decl(
  ty : @ctype.Type,
  name : String,
  init? : @parser.Expr,
) -> @parser.Stmt {
  let canonical_init : @parser.Expr? = match (ty.core_type(), init) {
    (Struct(_) | Union(_) | Array(_, _), _) => init
    (_, Some(Array(items))) =>
      Some(@parser.scalar_initializer_value(Array(items)))
    _ => init
  }
  VarDecl(
    @parser.infer_local_array_type(ty, canonical_init),
    name,
    canonical_init,
  )
}

///|
/// An assignment statement.
pub fn assign(target : @parser.Expr, value : @parser.Expr) -> @parser.Stmt {
  ExprStmt(Assign(target, value))
}

///|
/// A `return` statement.
pub fn ret(value? : @parser.Expr) -> @parser.Stmt {
  Return(value)
}

///|
/// A variable reference.
pub fn v(name : String) -> @parser.Expr {
  Var(name)
}

///|
/// A call expression by function name: `call("expf", [x])`.
pub fn call(name : String, args : Array[@parser.Expr]) -> @parser.Expr {
  Call(Var(name), args)
}

///|
/// A cast expression.
pub fn cast(ty : @ctype.Type, value : @parser.Expr) -> @parser.Expr {
  Cast(ty, value)
}

///|
/// A compound-assignment statement: `add_assign(acc, x)` is `acc += x`, the
/// accumulation shape of every inner product loop.
pub fn add_assign(target : @parser.Expr, value : @parser.Expr) -> @parser.Stmt {
  ExprStmt(CompoundAssign("+", target, value))
}

///|
/// `target -= value`.
pub fn sub_assign(target : @parser.Expr, value : @parser.Expr) -> @parser.Stmt {
  ExprStmt(CompoundAssign("-", target, value))
}

///|
/// `target *= value`.
pub fn mul_assign(target : @parser.Expr, value : @parser.Expr) -> @parser.Stmt {
  ExprStmt(CompoundAssign("*", target, value))
}

///|
/// A counting loop from `0` to `bound`, the specialized-kernel workhorse:
/// `for (int i = 0; i < bound; i++) body`. The generator knows `bound` as a
/// constant, which is the whole point of specializing to one model.
pub fn for_range(
  name : String,
  bound : @parser.Expr,
  body : Array[@parser.Stmt],
  ty? : @ctype.Type = SInt,
) -> @parser.Stmt {
  let counter : @parser.Expr = Var(name)
  // The zero initializer's literal type must be one a suffix can spell:
  // `unsigned char i = 0` parses its `0` as `SInt`, so a literal typed
  // `UChar` would print bare and reparse differently, breaking the exact
  // round trip. Suffix-spellable counter types keep their own literal.
  let literal_ty : @ctype.Type = match ty {
    SInt | UInt | SLong | ULong | SLongLong | ULongLong => ty
    _ => SInt
  }
  For(
    [VarDecl(ty, name, Some(@parser.int_literal(0, literal_ty)))],
    counter.lt(bound),
    Some(PostfixInc(counter)),
    Compound(body),
  )
}

///|
/// One entry of an ordered program, for translation units where the grouped
/// order is not enough -- a global initializer naming a function needs that
/// function's prototype first.
pub(all) enum Item {
  Aggregate(@parser.StructDecl)
  Global(@parser.GlobalDecl)
  Func(@parser.FuncDecl)
}

///|
/// A translation unit with its entries in the given order. `items` records
/// the interleaving, which is exactly what it exists for; the grouped arrays
/// fill in kind order as always.
pub fn ordered_program(entries : Array[Item]) -> @parser.Program {
  let structs : Array[@parser.StructDecl] = []
  let globals : Array[@parser.GlobalDecl] = []
  let decls : Array[@parser.FuncDecl] = []
  let items : Array[@parser.TopLevel] = []
  for entry in entries {
    match entry {
      Aggregate(decl) => {
        structs.push(decl)
        items.push(Aggregate(structs.length() - 1))
      }
      Global(decl) => {
        globals.push(decl)
        items.push(Global(globals.length() - 1))
      }
      Func(decl) => {
        decls.push(decl)
        items.push(Func(decls.length() - 1))
      }
    }
  }
  { structs, globals, decls, items }
}
