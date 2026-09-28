///|
/// A second, syntax-directed generator: where `gen_test.mbt` builds
/// type-correct `int` programs, this one covers the rest of the grammar the
/// printer and parser share -- every expression form, declarators over
/// pointers, arrays and function pointers, and the statements the first
/// generator leaves out (`do`/`while`, `switch` with `case`/`default`,
/// labels and both kinds of `goto`).
///
/// Programs need only be *syntactically* canonical: in the parser's image,
/// not necessarily well typed. The canonicalization rules, beyond the ones
/// `gen_test.mbt` documents:
///
/// - Literals are produced by lexing a spelling (`lex_literal`), so the
///   value, text and type agree with what the lexer would record.
/// - Assignment, `++` and `--` targets are syntactic lvalues (`Var`,
///   `Deref`, `ArrayAccess`, `MemberAccess`): the parser rejects any other
///   target with a diagnostic, so no other tree has a spelling.
/// - Unary `+` never appears: the parser drops it.
/// - Parameter types are never arrays and never `void`: a parameter of
///   array type is adjusted to a pointer, and `(void)` means no parameters.
/// - A `for` initializer is empty, one expression, or declarations sharing
///   one specifier -- the three shapes C can spell.
/// - `case`/`default` appear only directly in a `switch` body block, and a
///   label, `case` or `default` never labels a declaration.
/// - Compound literals and initializer lists are left out: they carry a
///   parser-assigned counter or live only in initializers.
struct SynProgram(@parser.Program)

///|
impl @quickcheck.Arbitrary for SynProgram with fn arbitrary(size, state) {
  SynProgram(gen_syn_program(size, state))
}

///|
impl @shrink.Shrink for SynProgram with fn shrink(self) {
  shrink_syn_program(self.0).map(p => SynProgram(p)).iter()
}

///|
impl @debug.Debug for SynProgram with fn to_repr(self) {
  Repr("\n" + @printer.print_program(self.0))
}

///|
/// A single generated expression, for the expression-level properties.
struct SynExpr(@parser.Expr)

///|
impl @quickcheck.Arbitrary for SynExpr with fn arbitrary(size, state) {
  let depth = if size < 1 { 1 } else if size > 6 { 6 } else { size }
  SynExpr(gen_syn_expr(depth, state))
}

///|
impl @shrink.Shrink for SynExpr with fn shrink(self) {
  syn_expr_children(self.0).map(e => SynExpr(e)).iter()
}

///|
impl @debug.Debug for SynExpr with fn to_repr(self) {
  Repr(@printer.print_expr(self.0) + "  ~  " + @debug.to_string(self.0))
}

///|
/// A single generated type, for the declarator properties.
struct SynType(@ctype.Type)

///|
impl @quickcheck.Arbitrary for SynType with fn arbitrary(size, state) {
  let depth = if size < 1 { 1 } else if size > 5 { 5 } else { size }
  SynType(gen_object_type(depth, state))
}

///|
impl @shrink.Shrink for SynType with fn shrink(self) {
  type_children(self.0).map(t => SynType(t)).iter()
}

///|
impl @debug.Debug for SynType with fn to_repr(self) {
  Repr(
    @printer.print_declaration(self.0, "x") + "  ~  " + @debug.to_string(self.0),
  )
}

// ---------------------------------------------------------------------------
// Types

///|
let arithmetic_types : ReadOnlyArray[@ctype.Type] = [
  Bool,
  SChar,
  UChar,
  SShort,
  UShort,
  SInt,
  UInt,
  SLong,
  ULong,
  SLongLong,
  ULongLong,
  SInt128,
  UInt128,
  Float,
  Double,
  LongDouble,
  Float16,
  Float128,
]

///|
/// A base specifier: arithmetic, one of the two fixed aggregates, or a
/// registered named type.
fn gen_base_type(state : @splitmix.RandomState) -> @ctype.Type {
  match pick(state, 12) {
    0 => Struct("S")
    1 => Union("U")
    2 => Named(named_type_pool[pick(state, named_type_pool.length())])
    _ => arithmetic_types[pick(state, arithmetic_types.length())]
  }
}

///|
/// A complete object type: what an array element, a `sizeof` operand or a
/// local declaration may have.
fn gen_object_type(depth : Int, state : @splitmix.RandomState) -> @ctype.Type {
  if depth <= 0 {
    return gen_base_type(state)
  }
  match pick(state, 10) {
    0 | 1 => Pointer(gen_pointee_type(depth - 1, state))
    2 => Array(gen_object_type(depth - 1, state), 1 + pick(state, 8))
    3 => gen_function_pointer(depth - 1, state)
    4 =>
      // `_Atomic` over a base type, and occasionally over a pointer: the
      // second has no specifier-prefix spelling.
      if pick(state, 3) == 0 {
        Atomic(Pointer(gen_base_type(state)))
      } else {
        Atomic(arithmetic_types[pick(state, arithmetic_types.length())])
      }
    _ => gen_base_type(state)
  }
}

///|
/// What a pointer may point at: any object type, or `void`.
fn gen_pointee_type(depth : Int, state : @splitmix.RandomState) -> @ctype.Type {
  if pick(state, 6) == 0 {
    Void
  } else {
    gen_object_type(depth, state)
  }
}

///|
/// A parameter type: never an array (adjusted to a pointer) and never
/// `void` (which spells an empty list).
fn gen_param_type(depth : Int, state : @splitmix.RandomState) -> @ctype.Type {
  match pick(state, 5) {
    0 => Pointer(gen_pointee_type(depth - 1, state))
    1 => if depth > 0 { gen_function_pointer(depth - 1, state) } else { SInt }
    _ => gen_base_type(state)
  }
}

///|
/// A return type: `void`, a base type, a pointer, or a function pointer.
fn gen_return_type(depth : Int, state : @splitmix.RandomState) -> @ctype.Type {
  match pick(state, 6) {
    0 => Void
    1 => Pointer(gen_pointee_type(depth - 1, state))
    2 => if depth > 0 { gen_function_pointer(depth - 1, state) } else { SInt }
    _ => gen_base_type(state)
  }
}

///|
fn gen_function_pointer(
  depth : Int,
  state : @splitmix.RandomState,
) -> @ctype.Type {
  let params : Array[@ctype.Type] = []
  for _ in 0..<pick(state, 4) {
    params.push(gen_param_type(depth, state))
  }
  let variadic = params.length() > 0 && pick(state, 4) == 0
  FuncPtr(gen_return_type(depth, state), params, variadic)
}

///|
/// A cast target: `void`, a scalar, a pointer, or a function pointer.
fn gen_cast_type(depth : Int, state : @splitmix.RandomState) -> @ctype.Type {
  match pick(state, 8) {
    0 => Void
    1 | 2 => Pointer(gen_pointee_type(depth, state))
    3 => gen_function_pointer(depth, state)
    4 => Named(named_type_pool[pick(state, named_type_pool.length())])
    _ => arithmetic_types[pick(state, arithmetic_types.length())]
  }
}

///|
fn type_children(ty : @ctype.Type) -> Array[@ctype.Type] {
  match ty {
    Pointer(inner) | Array(inner, _) | Atomic(inner) | Aligned(inner, _) =>
      [SInt, inner]
    FuncPtr(ret, params, variadic) => {
      let out : Array[@ctype.Type] = [SInt, Pointer(ret)]
      for i in 0..<params.length() {
        let fewer = params.copy()
        let _ = fewer.remove(i)
        out.push(FuncPtr(ret, fewer, variadic && fewer.length() > 0))
      }
      out
    }
    SInt => []
    _ => [SInt]
  }
}

// ---------------------------------------------------------------------------
// Expressions

///|
/// Variable names. None is a keyword, a builtin the parser special-cases, a
/// type name, or a label.
let var_pool : ReadOnlyArray[String] = [
  "a", "b", "c", "n", "p", "q", "s", "fp", "xs",
]

///|
let field_pool : ReadOnlyArray[String] = ["a", "b", "next", "arr", "i", "f"]

///|
let label_pool : ReadOnlyArray[String] = ["L0", "L1", "L2"]

///|
/// Literal spellings, lexed to get the token the parser would record.
let literal_spellings : ReadOnlyArray[String] = [
  "0", "1", "42", "2147483647", "7u", "8L", "9uL", "10LL", "11uLL", "0xff", "0XFFu",
  "017", "0x7fffffff", "0xffffffff", "4294967296", "'a'", "'\\n'", "'\\0'", "'\\x41'",
  "'\\''", "'\"'", "'\\\\'", "'\\177'", "1.5", "0.5f", "2.", ".25", "1e10", "1.5e-3L",
  "0x1p3", "0x1.8p-2f", "3.0L",
]

///|
fn lex_literal(text : String) -> @parser.Expr {
  let token = @parser.Lexer::new(text).next_token() catch {
    _ => return @parser.int_literal(0, SInt)
  }
  match token {
    Number(value, spelled, ty) => Number(value, spelled, ty)
    FloatLiteral(spelled, ty) => FloatLiteral(spelled, ty)
    _ => @parser.int_literal(0, SInt)
  }
}

///|
/// A string literal body: bytes 0-255, biased toward the characters the
/// printer must escape, plus source characters above 0xff -- CJK, the
/// characters next to the surrogate range, and astral ones -- which a
/// UTF-8 source file puts in a literal whole.
fn gen_string_body(state : @splitmix.RandomState) -> String {
  let buf = StringBuilder()
  let specials : ReadOnlyArray[Char] = [
    '"', '\\', '\n', '\t', '\r', '\u{0}', '\u{7}', '?', '\'', '\u{7f}', '\u{80}',
    '\u{e9}', '\u{ff}', '0', '7', 'x',
  ]
  let wide : ReadOnlyArray[Char] = [
    '\u{100}', '\u{4E2D}', '\u{D7FF}', '\u{E000}', '\u{FFFD}', '\u{FFFF}', '\u{10000}',
    '\u{1F600}', '\u{10FFFF}',
  ]
  for _ in 0..<pick(state, 6) {
    match pick(state, 4) {
      0 => buf.write_char(specials[pick(state, specials.length())])
      1 => buf.write_char((32 + pick(state, 95)).unsafe_to_char())
      2 => buf.write_char(pick(state, 256).unsafe_to_char())
      _ => buf.write_char(wide[pick(state, wide.length())])
    }
  }
  buf.to_string()
}

///|
fn gen_leaf(state : @splitmix.RandomState) -> @parser.Expr {
  match pick(state, 10) {
    0 | 1 | 2 | 3 => Var(var_pool[pick(state, var_pool.length())])
    4 | 5 => @parser.int_literal(pick(state, 1000).to_int64(), SInt)
    6 | 7 =>
      lex_literal(literal_spellings[pick(state, literal_spellings.length())])
    8 => String(gen_string_body(state))
    _ => LabelAddr(label_pool[pick(state, label_pool.length())])
  }
}

///|
/// A syntactic lvalue: the only shapes the parser accepts as an assignment,
/// `++` or `--` target.
fn gen_lvalue(depth : Int, state : @splitmix.RandomState) -> @parser.Expr {
  if depth <= 0 {
    return Var(var_pool[pick(state, var_pool.length())])
  }
  match pick(state, 6) {
    0 => Deref(gen_syn_expr(depth - 1, state))
    1 =>
      ArrayAccess(
        gen_syn_expr(depth - 1, state),
        gen_syn_expr(depth - 1, state),
      )
    2 =>
      MemberAccess(
        member_base(gen_syn_expr(depth - 1, state)),
        field_pool[pick(state, field_pool.length())],
      )
    3 =>
      MemberAccess(
        Deref(gen_syn_expr(depth - 1, state)),
        field_pool[pick(state, field_pool.length())],
      )
    _ => Var(var_pool[pick(state, var_pool.length())])
  }
}

///|
let syn_binary_ops : ReadOnlyArray[String] = [
  "+", "-", "*", "/", "%", "<<", ">>", "<", "<=", ">", ">=", "==", "!=", "&", "^",
  "|", "&&", "||", ",",
]

///|
let syn_compound_ops : ReadOnlyArray[String] = [
  "+", "-", "*", "/", "%", "<<", ">>", "&", "^", "|",
]

///|
/// An `offsetof` member path: a field, then fields and constant indices.
fn gen_offset_path(
  state : @splitmix.RandomState,
) -> Array[@ctype.OffsetDesignator] {
  let path : Array[@ctype.OffsetDesignator] = [
    OffsetField(field_pool[pick(state, field_pool.length())]),
  ]
  for _ in 0..<pick(state, 3) {
    if pick(state, 2) == 0 {
      path.push(OffsetIndex(pick(state, 8).to_int64()))
    } else {
      path.push(OffsetField(field_pool[pick(state, field_pool.length())]))
    }
  }
  path
}

///|
/// An expression at most `depth` operators deep, over every form the printer
/// and parser share outside initializers.
fn gen_syn_expr(depth : Int, state : @splitmix.RandomState) -> @parser.Expr {
  if depth <= 0 || pick(state, 5) == 0 {
    return gen_leaf(state)
  }
  let d = depth - 1
  match pick(state, 34) {
    0..=7 =>
      Binary(
        syn_binary_ops[pick(state, syn_binary_ops.length())],
        gen_syn_expr(d, state),
        gen_syn_expr(d, state),
      )
    8 | 9 => {
      let unary_ops : ReadOnlyArray[String] = ["-", "!", "~"]
      Unary(unary_ops[pick(state, unary_ops.length())], gen_syn_expr(d, state))
    }
    10 => Deref(gen_syn_expr(d, state))
    11 => AddrOf(gen_syn_expr(d, state))
    12 => SizeofExpr(gen_syn_expr(d, state))
    13 => Sizeof(gen_object_type(d, state))
    14 => AlignofExpr(gen_syn_expr(d, state))
    15 => Alignof(gen_object_type(d, state))
    16 | 17 => Cast(gen_cast_type(d, state), gen_syn_expr(d, state))
    18 => PrefixInc(gen_lvalue(d, state))
    19 => PrefixDec(gen_lvalue(d, state))
    20 => PostfixInc(gen_lvalue(d, state))
    21 => PostfixDec(gen_lvalue(d, state))
    22 => {
      let args : Array[@parser.Expr] = []
      for _ in 0..<pick(state, 4) {
        args.push(gen_syn_expr(d, state))
      }
      let callee : @parser.Expr = if pick(state, 3) == 0 {
        gen_syn_expr(d, state)
      } else {
        Var(var_pool[pick(state, var_pool.length())])
      }
      Call(callee, args)
    }
    23 => ArrayAccess(gen_syn_expr(d, state), gen_syn_expr(d, state))
    24 =>
      MemberAccess(
        member_base(gen_syn_expr(d, state)),
        field_pool[pick(state, field_pool.length())],
      )
    25 =>
      MemberAccess(
        Deref(gen_syn_expr(d, state)),
        field_pool[pick(state, field_pool.length())],
      )
    26 | 27 => Assign(gen_lvalue(d, state), gen_syn_expr(d, state))
    28 =>
      CompoundAssign(
        syn_compound_ops[pick(state, syn_compound_ops.length())],
        gen_lvalue(d, state),
        gen_syn_expr(d, state),
      )
    29 | 30 =>
      Ternary(
        gen_syn_expr(d, state),
        gen_syn_expr(d, state),
        gen_syn_expr(d, state),
      )
    31 => VaArg(gen_syn_expr(d, state), gen_cast_type(d, state))
    32 =>
      OffsetOf(
        if pick(state, 2) == 0 {
          Struct("S")
        } else {
          Union("U")
        },
        gen_offset_path(state),
      )
    _ => gen_leaf(state)
  }
}

///|
/// The direct subexpressions of an expression, plus a literal for anything
/// that is not already one: the shrink candidates. A child is always a
/// well-formed expression, but it may stand where only an lvalue is
/// accepted; the round-trip property filters those out.
fn syn_expr_children(expr : @parser.Expr) -> Array[@parser.Expr] {
  let one = @parser.int_literal(1, SInt)
  match expr {
    Number(_, _, _) => []
    Var(_) => []
    FloatLiteral(_, _) | String(_) | LabelAddr(_) => [one]
    Binary(op, lhs, rhs) => {
      let out = [one, lhs, rhs]
      for reduced in syn_expr_children(lhs) {
        out.push(Binary(op, reduced, rhs))
      }
      for reduced in syn_expr_children(rhs) {
        out.push(Binary(op, lhs, reduced))
      }
      out
    }
    Unary(op, operand) => {
      let out = [one, operand]
      for reduced in syn_expr_children(operand) {
        out.push(Unary(op, reduced))
      }
      out
    }
    Deref(operand) => {
      let out = [one, operand]
      for reduced in syn_expr_children(operand) {
        out.push(Deref(reduced))
      }
      out
    }
    AddrOf(operand) => {
      let out = [one, operand]
      for reduced in syn_expr_children(operand) {
        out.push(AddrOf(reduced))
      }
      out
    }
    SizeofExpr(operand) => {
      let out = [one, operand]
      for reduced in syn_expr_children(operand) {
        out.push(SizeofExpr(reduced))
      }
      out
    }
    AlignofExpr(operand) => {
      let out = [one, operand]
      for reduced in syn_expr_children(operand) {
        out.push(AlignofExpr(reduced))
      }
      out
    }
    Sizeof(ty) => [one, ..type_children(ty).map(t => @parser.Expr::Sizeof(t))]
    Alignof(ty) => [one, ..type_children(ty).map(t => @parser.Expr::Alignof(t))]
    Cast(ty, operand) => {
      let out = [one, operand]
      for t in type_children(ty) {
        out.push(Cast(t, operand))
      }
      for reduced in syn_expr_children(operand) {
        out.push(Cast(ty, reduced))
      }
      out
    }
    PrefixInc(operand)
    | PrefixDec(operand)
    | PostfixInc(operand)
    | PostfixDec(operand) => [one, operand]
    Call(callee, args) => {
      let out = [one, callee, ..args]
      for i in 0..<args.length() {
        let fewer = args.copy()
        let _ = fewer.remove(i)
        out.push(Call(callee, fewer))
      }
      out
    }
    ArrayAccess(base, index) => {
      let out = [one, base, index]
      for reduced in syn_expr_children(base) {
        out.push(ArrayAccess(reduced, index))
      }
      for reduced in syn_expr_children(index) {
        out.push(ArrayAccess(base, reduced))
      }
      out
    }
    MemberAccess(base, field) => {
      let out = [one, base]
      for reduced in syn_expr_children(base) {
        out.push(MemberAccess(reduced, field))
      }
      out
    }
    Assign(target, value) => {
      let out = [one, target, value]
      for reduced in syn_expr_children(value) {
        out.push(Assign(target, reduced))
      }
      for reduced in syn_expr_children(target) {
        out.push(Assign(reduced, value))
      }
      out
    }
    CompoundAssign(op, target, value) => {
      let out = [one, target, value, Assign(target, value)]
      for reduced in syn_expr_children(value) {
        out.push(CompoundAssign(op, target, reduced))
      }
      out
    }
    Ternary(cond, then_value, else_value) => {
      let out = [one, cond, then_value, else_value]
      for reduced in syn_expr_children(cond) {
        out.push(Ternary(reduced, then_value, else_value))
      }
      for reduced in syn_expr_children(then_value) {
        out.push(Ternary(cond, reduced, else_value))
      }
      for reduced in syn_expr_children(else_value) {
        out.push(Ternary(cond, then_value, reduced))
      }
      out
    }
    VaArg(list, ty) =>
      [one, list, ..type_children(ty).map(t => @parser.Expr::VaArg(list, t))]
    _ => [one]
  }
}

///|
/// A `.` member access never applies to a numeric literal. `(56).b` has no
/// meaning in C, and its natural spelling `56.b` lexes as the floating
/// literal `56.` followed by `b`; a generator that respects C's constraints
/// never builds it.
fn member_base(base : @parser.Expr) -> @parser.Expr {
  match base {
    Number(_, _, _) | FloatLiteral(_, _) => Var("s")
    _ => base
  }
}

///|
/// Whether `expr` is in the generator's canonical image: every assignment,
/// `++` and `--` target is a syntactic lvalue, and no `.` applies to a
/// numeric literal (see `member_base`). Shrinking can break either (it
/// replaces a subtree by a child or a literal); generation never does.
fn in_parser_image(expr : @parser.Expr) -> Bool {
  fn is_lvalue(e : @parser.Expr) -> Bool {
    e is (Var(_) | Deref(_) | ArrayAccess(_, _) | MemberAccess(_, _))
  }

  match expr {
    Assign(target, value) | CompoundAssign(_, target, value) =>
      is_lvalue(target) && in_parser_image(target) && in_parser_image(value)
    PrefixInc(target)
    | PrefixDec(target)
    | PostfixInc(target)
    | PostfixDec(target) => is_lvalue(target) && in_parser_image(target)
    Binary(_, lhs, rhs) | ArrayAccess(lhs, rhs) =>
      in_parser_image(lhs) && in_parser_image(rhs)
    Unary(_, e)
    | Deref(e)
    | AddrOf(e)
    | SizeofExpr(e)
    | AlignofExpr(e)
    | Cast(_, e)
    | VaArg(e, _) => in_parser_image(e)
    MemberAccess(e, _) =>
      !(e is (Number(_, _, _) | FloatLiteral(_, _))) && in_parser_image(e)
    Call(callee, args) =>
      in_parser_image(callee) && args.iter().all(in_parser_image)
    Ternary(c, t, e) =>
      in_parser_image(c) && in_parser_image(t) && in_parser_image(e)
    _ => true
  }
}

// ---------------------------------------------------------------------------
// Statements and programs

///|
priv struct StmtCtx {
  in_loop : Bool
  in_switch : Bool
  next_name : Ref[Int]
}

///|
fn fresh_name(ctx : StmtCtx, prefix : String) -> String {
  let name = prefix + ctx.next_name.val.to_string()
  ctx.next_name.val += 1
  name
}

///|
/// A local declaration: any object type, with an initializer when the type
/// is scalar.
fn gen_local_decl(
  depth : Int,
  ctx : StmtCtx,
  state : @splitmix.RandomState,
) -> @parser.Stmt {
  let ty = if pick(state, 8) == 0 {
    @ctype.Type::Aligned(
      arithmetic_types[pick(state, arithmetic_types.length())],
      16,
    )
  } else {
    gen_object_type(depth, state)
  }
  let init : @parser.Expr? = match ty {
    Array(_, _) | Struct(_) | Union(_) | Named(_) => None
    _ =>
      if pick(state, 2) == 0 {
        Some(gen_syn_expr(depth, state))
      } else {
        None
      }
  }
  VarDecl(ty, fresh_name(ctx, "v"), init)
}

///|
/// A statement usable where C wants exactly one: never a declaration.
fn gen_syn_stmt(
  depth : Int,
  ctx : StmtCtx,
  state : @splitmix.RandomState,
) -> @parser.Stmt {
  if depth <= 0 {
    return ExprStmt(gen_syn_expr(1, state))
  }
  let d = depth - 1
  match pick(state, 16) {
    0 => {
      let then_branch = gen_syn_stmt(d, ctx, state)
      let else_branch : @parser.Stmt? = if pick(state, 2) == 0 {
        Some(gen_syn_stmt(d, ctx, state))
      } else {
        None
      }
      canonical_if(gen_syn_expr(d, state), then_branch, else_branch)
    }
    1 =>
      While(
        gen_syn_expr(d, state),
        gen_syn_stmt(d, { ..ctx, in_loop: true, }, state),
      )
    2 =>
      DoWhile(
        gen_syn_expr(d, state),
        gen_syn_stmt(d, { ..ctx, in_loop: true, }, state),
      )
    3 => {
      let init : Array[@parser.Stmt] = match pick(state, 3) {
        0 => []
        1 => [ExprStmt(gen_syn_expr(d, state))]
        _ => {
          // Declarators over one shared base specifier.
          let base = gen_base_type(state)
          let decls : Array[@parser.Stmt] = []
          for _ in 0..<(1 + pick(state, 3)) {
            let ty : @ctype.Type = match pick(state, 4) {
              0 => Pointer(base)
              1 => Array(base, 1 + pick(state, 4))
              2 => Pointer(Pointer(base))
              _ => base
            }
            let init : @parser.Expr? = if ty is Array(_, _) ||
              pick(state, 2) == 0 {
              None
            } else {
              Some(gen_syn_expr(d, state))
            }
            decls.push(VarDecl(ty, fresh_name(ctx, "i"), init))
          }
          decls
        }
      }
      let step : @parser.Expr? = if pick(state, 2) == 0 {
        Some(gen_syn_expr(d, state))
      } else {
        None
      }
      For(
        init,
        gen_syn_expr(d, state),
        step,
        gen_syn_stmt(d, { ..ctx, in_loop: true, }, state),
      )
    }
    4 => {
      // A switch body: a block of clauses, each labelling one statement,
      // with ordinary statements between them.
      let inner = { ..ctx, in_switch: true, }
      let body : Array[@parser.Stmt] = []
      let mut has_default = false
      for _ in 0..<(1 + pick(state, 4)) {
        match pick(state, 4) {
          0 if !has_default => {
            has_default = true
            body.push(Default(gen_syn_stmt(d, inner, state)))
          }
          1 => body.push(gen_syn_stmt(d, inner, state))
          _ => {
            let value = pick(state, 20).to_int64() - 5L
            body.push(Case(value, gen_syn_stmt(d, inner, state)))
          }
        }
      }
      Switch(gen_syn_expr(d, state), Compound(body))
    }
    5 => {
      let body : Array[@parser.Stmt] = []
      for _ in 0..<pick(state, 4) {
        if pick(state, 3) == 0 {
          body.push(gen_local_decl(d, ctx, state))
        } else {
          body.push(gen_syn_stmt(d, ctx, state))
        }
      }
      Compound(body)
    }
    6 =>
      if ctx.in_loop || ctx.in_switch {
        Break
      } else {
        ExprStmt(gen_syn_expr(d, state))
      }
    7 => if ctx.in_loop { Continue } else { ExprStmt(gen_syn_expr(d, state)) }
    8 => Goto(label_pool[pick(state, label_pool.length())])
    9 => ComputedGoto(gen_syn_expr(d, state))
    10 =>
      Label(
        label_pool[pick(state, label_pool.length())],
        gen_syn_stmt(d, ctx, state),
      )
    11 =>
      Return(
        if pick(state, 2) == 0 {
          Some(gen_syn_expr(d, state))
        } else {
          None
        },
      )
    _ => ExprStmt(gen_syn_expr(d, state))
  }
}

///|
/// The two fixed aggregates every generated program starts with, so
/// `struct S` and `union U` references resolve to a definition.
fn fixed_aggregates() -> Array[@parser.StructDecl] {
  [
    {
      name: "S",
      fields: [
        { ty: SInt, name: "a", bit_width: None, },
        { ty: Pointer(SInt), name: "b", bit_width: None, },
        { ty: Pointer(Struct("S")), name: "next", bit_width: None, },
        { ty: Array(SInt, 4), name: "arr", bit_width: None, },
      ],
      is_union: false,
      pack: None,
      is_anonymous: false,
    },
    {
      name: "U",
      fields: [
        { ty: SInt, name: "i", bit_width: None, },
        { ty: Float, name: "f", bit_width: None, },
      ],
      is_union: true,
      pack: None,
      is_anonymous: false,
    },
  ]
}

///|
fn gen_syn_program(
  size : Int,
  state : @splitmix.RandomState,
) -> @parser.Program {
  let scaled = if size < 1 { 1 } else if size > 10 { 10 } else { size }
  let depth = 1 + scaled / 3
  let ctx : StmtCtx = {
    in_loop: false,
    in_switch: false,
    next_name: { val: 0, },
  }
  let globals : Array[@parser.GlobalDecl] = []
  for _ in 0..<pick(state, 3) {
    let ty = gen_object_type(depth, state)
    let init : @parser.GlobalInit? = if arithmetic_types.contains(ty) &&
      pick(state, 2) == 0 {
      Some(Scalar(lex_literal(literal_spellings[pick(state, 15)])))
    } else {
      None
    }
    let is_extern = init is None && pick(state, 4) == 0
    globals.push({
      ty,
      name: fresh_name(ctx, "g"),
      init,
      is_static: !is_extern && pick(state, 3) == 0,
      is_extern,
      is_weak: false,
      visibility: None,
      symbol_alias: None,
      section: None,
    })
  }
  let decls : Array[@parser.FuncDecl] = []
  for _ in 0..<(1 + pick(state, 2)) {
    let params : Array[@parser.Param] = []
    for _ in 0..<pick(state, 4) {
      params.push({
        ty: gen_param_type(depth, state),
        name: fresh_name(ctx, "a"),
        bit_width: None,
      })
    }
    let body : Array[@parser.Stmt] = []
    for _ in 0..<(1 + scaled / 2) {
      if pick(state, 4) == 0 {
        body.push(gen_local_decl(depth, ctx, state))
      } else {
        body.push(gen_syn_stmt(depth, ctx, state))
      }
    }
    decls.push({
      ret: gen_return_type(depth, state),
      name: fresh_name(ctx, "f"),
      params,
      variadic: params.length() > 0 && pick(state, 4) == 0,
      is_static: pick(state, 3) == 0,
      is_inline: pick(state, 4) == 0,
      is_weak: false,
      visibility: None,
      symbol_alias: None,
      section: None,
      is_constructor: false,
      is_destructor: false,
      body: if pick(state, 6) == 0 {
        None
      } else {
        Some(Compound(body))
      },
    })
  }
  syn_rebuild(globals, decls)
}

///|
fn syn_rebuild(
  globals : Array[@parser.GlobalDecl],
  decls : Array[@parser.FuncDecl],
) -> @parser.Program {
  let items : Array[@parser.TopLevel] = [Aggregate(0), Aggregate(1)]
  for i in 0..<globals.length() {
    items.push(Global(i))
  }
  for i in 0..<decls.length() {
    items.push(Func(i))
  }
  { structs: fixed_aggregates(), globals, decls, items, }
}

///|
/// One-step reductions: drop a global or function, simplify a type, or
/// shrink a statement in a body.
fn shrink_syn_program(program : @parser.Program) -> Array[@parser.Program] {
  let out : Array[@parser.Program] = []
  for i in 0..<program.globals.length() {
    let globals = program.globals.copy()
    let _ = globals.remove(i)
    out.push(syn_rebuild(globals, program.decls))
    for t in type_children(program.globals[i].ty) {
      let globals = program.globals.copy()
      globals[i] = { ..program.globals[i], ty: t, init: None, }
      out.push(syn_rebuild(globals, program.decls))
    }
  }
  if program.decls.length() > 1 {
    for i in 0..<program.decls.length() {
      let decls = program.decls.copy()
      let _ = decls.remove(i)
      out.push(syn_rebuild(program.globals, decls))
    }
  }
  for i in 0..<program.decls.length() {
    let decl = program.decls[i]
    if !(decl.ret is SInt) {
      let decls = program.decls.copy()
      decls[i] = { ..decl, ret: SInt, }
      out.push(syn_rebuild(program.globals, decls))
    }
    for j in 0..<decl.params.length() {
      let params = decl.params.copy()
      let _ = params.remove(j)
      let decls = program.decls.copy()
      decls[i] = {
        ..decl,
        params,
        variadic: decl.variadic && params.length() > 0,
      }
      out.push(syn_rebuild(program.globals, decls))
    }
    match decl.body {
      Some(Compound(stmts)) =>
        for candidate in shrink_syn_stmts(stmts) {
          let decls = program.decls.copy()
          decls[i] = { ..decl, body: Some(Compound(candidate)), }
          out.push(syn_rebuild(program.globals, decls))
        }
      _ => ()
    }
  }
  out
}

///|
fn shrink_syn_stmts(stmts : Array[@parser.Stmt]) -> Array[Array[@parser.Stmt]] {
  let out : Array[Array[@parser.Stmt]] = []
  for i in 0..<stmts.length() {
    let dropped = stmts.copy()
    let _ = dropped.remove(i)
    out.push(dropped)
    for reduced in shrink_syn_stmt(stmts[i]) {
      let replaced = stmts.copy()
      replaced[i] = reduced
      out.push(replaced)
    }
  }
  out
}

///|
/// Reductions of one statement. Candidates may leave the canonical image
/// (a `break` hoisted out of its loop, a `case` out of its switch); the
/// parser accepts all of those, so the round-trip property still judges
/// them fairly.
fn shrink_syn_stmt(stmt : @parser.Stmt) -> Array[@parser.Stmt] {
  let out : Array[@parser.Stmt] = []
  let expr_candidates = (e : @parser.Expr) => {
    syn_expr_children(e).filter(in_parser_image)
  }
  match stmt {
    ExprStmt(e) =>
      for r in expr_candidates(e) {
        out.push(ExprStmt(r))
      }
    VarDecl(ty, name, init) => {
      if init is Some(_) {
        out.push(VarDecl(ty, name, None))
      }
      for t in type_children(ty) {
        out.push(VarDecl(t, name, init))
      }
      match init {
        Some(e) =>
          for r in expr_candidates(e) {
            out.push(VarDecl(ty, name, Some(r)))
          }
        None => ()
      }
    }
    Return(Some(e)) => {
      out.push(Return(None))
      for r in expr_candidates(e) {
        out.push(Return(Some(r)))
      }
    }
    ComputedGoto(e) => {
      out.push(Goto("L0"))
      for r in expr_candidates(e) {
        out.push(ComputedGoto(r))
      }
    }
    If(cond, then_branch, else_branch) => {
      out.push(then_branch)
      match else_branch {
        Some(alternative) => {
          out.push(If(cond, then_branch, None))
          out.push(alternative)
          for r in shrink_syn_stmt(alternative) {
            out.push(canonical_if(cond, then_branch, Some(r)))
          }
        }
        None => ()
      }
      for r in expr_candidates(cond) {
        out.push(canonical_if(r, then_branch, else_branch))
      }
      for r in shrink_syn_stmt(then_branch) {
        out.push(canonical_if(cond, r, else_branch))
      }
    }
    While(cond, body) | DoWhile(cond, body) => {
      let rebuild = (c : @parser.Expr, b : @parser.Stmt) => {
        if stmt is While(_, _) {
          @parser.Stmt::While(c, b)
        } else {
          DoWhile(c, b)
        }
      }
      out.push(body)
      for r in expr_candidates(cond) {
        out.push(rebuild(r, body))
      }
      for r in shrink_syn_stmt(body) {
        out.push(rebuild(cond, r))
      }
    }
    For(init, cond, step, body) => {
      out.push(body)
      if init.length() > 0 {
        out.push(For([], cond, step, body))
      }
      if step is Some(_) {
        out.push(For(init, cond, None, body))
      }
      for r in expr_candidates(cond) {
        out.push(For(init, r, step, body))
      }
      for r in shrink_syn_stmt(body) {
        out.push(For(init, cond, step, r))
      }
    }
    Switch(subject, body) => {
      out.push(body)
      for r in expr_candidates(subject) {
        out.push(Switch(r, body))
      }
      for r in shrink_syn_stmt(body) {
        out.push(Switch(subject, r))
      }
    }
    Case(value, inner) => {
      out.push(inner)
      for r in shrink_syn_stmt(inner) {
        out.push(Case(value, r))
      }
    }
    Default(inner) => {
      out.push(inner)
      for r in shrink_syn_stmt(inner) {
        out.push(Default(r))
      }
    }
    Label(name, inner) => {
      out.push(inner)
      for r in shrink_syn_stmt(inner) {
        out.push(Label(name, r))
      }
    }
    Compound(stmts) => {
      if stmts.length() == 1 && !(stmts[0] is VarDecl(_, _, _)) {
        out.push(stmts[0])
      }
      for candidate in shrink_syn_stmts(stmts) {
        out.push(Compound(candidate))
      }
    }
    _ => ()
  }
  out
}
