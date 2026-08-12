///|
/// Property-based tests for the print/parse round-trip.
///
/// The generator builds programs in the parser's *image*: the shapes the
/// parser itself would produce from source. Every constraint here is a
/// canonicalization rule of the AST, written down where quickcheck forced it
/// to be -- a counterexample that violates one is a generator bug, and every
/// other counterexample is a parser or printer bug. The rules so far:
///
/// - Integer literals come from `int_literal` and are non-negative: the
///   parser reads `-5` as `Unary("-", 5)`, so a canonical tree spells
///   negation the same way.
/// - Every variable is declared before use, with names from a pool that
///   avoids keywords and each other.
/// - Loop-only statements (`break`, `continue`) appear only inside loops.
/// - `items` is populated in source order: a parsed program always carries
///   it, so a canonical program does too, and whole-`Program` equality
///   includes it.
/// - A then-branch that would capture the `else` -- its trailing
///   substatement an `if` with no `else` -- is spelled braced. The
///   dangling-else rule means no source ever parses to the bare form, so the
///   braces are part of the canonical tree; the printer braces such a branch
///   itself when handed one, preserving meaning at the cost of the shape.
struct GenProgram(@parser.Program)

///|
impl @quickcheck.Arbitrary for GenProgram with fn arbitrary(size, state) {
  GenProgram(gen_program(size, state))
}

///|
impl @shrink.Shrink for GenProgram with fn shrink(self) {
  shrink_program(self.0).map(p => GenProgram(p)).iter()
}

///|
impl @debug.Debug for GenProgram with fn to_repr(self) {
  // A counterexample reads best as the C it prints to. When the text looks
  // innocent, the difference hides in structure -- switch this to
  // `self.0.to_repr()` while diagnosing.
  Repr("\n" + @printer.print_program(self.0))
}

///|
/// A uniform pick in `[0, bound)`.
fn pick(state : @splitmix.RandomState, bound : Int) -> Int {
  if bound <= 1 {
    0
  } else {
    (state.next_uint() % bound.reinterpret_as_uint()).reinterpret_as_int()
  }
}

///|
fn gen_literal(state : @splitmix.RandomState) -> @parser.Expr {
  // Small values dominate; a sprinkle of large ones exercises wide constants.
  let value : Int64 = match pick(state, 8) {
    0 => 0
    1 => 1
    2..=5 => pick(state, 100).to_int64()
    6 => pick(state, 65536).to_int64()
    _ => 2147483647
  }
  @parser.int_literal(value, SInt)
}

///|
/// An expression over `vars`, at most `depth` operators deep.
///
/// The operator pool is the full binary set the parser records as source
/// strings; precedence and associativity in the printed text are exactly
/// what this property hunts.
fn gen_expr(
  depth : Int,
  vars : Array[String],
  state : @splitmix.RandomState,
) -> @parser.Expr {
  if depth <= 0 || pick(state, 4) == 0 {
    if vars.length() > 0 && pick(state, 2) == 0 {
      return Var(vars[pick(state, vars.length())])
    }
    return gen_literal(state)
  }
  let binary_ops : ReadOnlyArray[String] = [
    "+", "-", "*", "/", "%", "<<", ">>", "<", "<=", ">", ">=", "==", "!=", "&", "^",
    "|", "&&", "||",
  ]
  match pick(state, 8) {
    0..=4 =>
      Binary(
        binary_ops[pick(state, binary_ops.length())],
        gen_expr(depth - 1, vars, state),
        gen_expr(depth - 1, vars, state),
      )
    5 => {
      let unary_ops : ReadOnlyArray[String] = ["-", "!", "~"]
      Unary(
        unary_ops[pick(state, unary_ops.length())],
        gen_expr(depth - 1, vars, state),
      )
    }
    6 =>
      Ternary(
        gen_expr(depth - 1, vars, state),
        gen_expr(depth - 1, vars, state),
        gen_expr(depth - 1, vars, state),
      )
    _ => gen_expr(depth - 1, vars, state)
  }
}

///|
/// Mirrors the printer's dangling-else test: the trailing substatement is an
/// `if` with no `else`.
fn captures_else(stmt : @parser.Stmt) -> Bool {
  match stmt {
    If(_, _, None) => true
    If(_, _, Some(alternative)) => captures_else(alternative)
    While(_, body) | For(_, _, _, body) | Switch(_, body) => captures_else(body)
    Case(_, inner) | Default(inner) | Label(_, inner) => captures_else(inner)
    _ => false
  }
}

///|
/// A single statement usable as a bare (unbraced) branch: an expression
/// statement, a nested bare `if`, or a `while` whose body is itself bare --
/// the shapes whose trailing substatement can be an open `if`.
fn gen_branch_stmt(
  depth : Int,
  vars : Array[String],
  in_loop : Bool,
  next_name : Ref[Int],
  state : @splitmix.RandomState,
) -> @parser.Stmt {
  if depth <= 0 {
    return ExprStmt(gen_expr(0, vars, state))
  }
  match pick(state, 4) {
    0 => {
      let bare_then = gen_branch_stmt(
        depth - 1,
        vars,
        in_loop,
        next_name,
        state,
      )
      let else_branch : @parser.Stmt? = if pick(state, 2) == 0 {
        Some(gen_branch_stmt(depth - 1, vars, in_loop, next_name, state))
      } else {
        None
      }
      let then_branch : @parser.Stmt = if else_branch is Some(_) &&
        captures_else(bare_then) {
        Compound([bare_then])
      } else {
        bare_then
      }
      If(gen_expr(0, vars, state), then_branch, else_branch)
    }
    1 =>
      While(
        gen_expr(0, vars, state),
        gen_branch_stmt(depth - 1, vars, true, next_name, state),
      )
    _ => ExprStmt(gen_expr(depth, vars, state))
  }
}

///|
/// Statements for one block scope. `vars` grows as declarations are
/// generated, so later statements can reference earlier names; the caller's
/// copy is unshared, matching C block scope.
fn gen_stmts(
  budget : Int,
  depth : Int,
  vars : Array[String],
  in_loop : Bool,
  next_name : Ref[Int],
  state : @splitmix.RandomState,
) -> Array[@parser.Stmt] {
  let stmts : Array[@parser.Stmt] = []
  for _ in 0..<budget {
    match pick(state, 10) {
      0 | 1 => {
        let name = "v" + next_name.val.to_string()
        next_name.val += 1
        stmts.push(VarDecl(SInt, name, Some(gen_expr(depth, vars, state))))
        vars.push(name)
      }
      2 =>
        if vars.length() > 0 {
          stmts.push(
            ExprStmt(
              Assign(
                Var(vars[pick(state, vars.length())]),
                gen_expr(depth, vars, state),
              ),
            ),
          )
        }
      3 => {
        // Branches are braced or bare at random: the bare single-statement
        // form is where dangling-else capture lives, and the printer must
        // brace an open-`if` then-branch itself.
        let bare_then : @parser.Stmt = if pick(state, 3) == 0 {
          gen_branch_stmt(depth - 1, vars, in_loop, next_name, state)
        } else {
          Compound(
            gen_stmts(1, depth - 1, vars.copy(), in_loop, next_name, state),
          )
        }
        let else_branch : @parser.Stmt? = match pick(state, 3) {
          0 => Some(gen_branch_stmt(depth - 1, vars, in_loop, next_name, state))
          1 =>
            Some(
              Compound(
                gen_stmts(1, depth - 1, vars.copy(), in_loop, next_name, state),
              ),
            )
          _ => None
        }
        let then_branch : @parser.Stmt = if else_branch is Some(_) &&
          captures_else(bare_then) {
          Compound([bare_then])
        } else {
          bare_then
        }
        stmts.push(
          If(gen_expr(depth - 1, vars, state), then_branch, else_branch),
        )
      }
      4 =>
        stmts.push(
          While(
            gen_expr(depth - 1, vars, state),
            Compound(
              gen_stmts(1, depth - 1, vars.copy(), true, next_name, state),
            ),
          ),
        )
      5 => {
        // `for` inits share one base type, which is what the printer's
        // declaration-rejoin has to reassemble.
        let init : Array[@parser.Stmt] = []
        let inner = vars.copy()
        for _ in 0..<pick(state, 3) {
          let name = "v" + next_name.val.to_string()
          next_name.val += 1
          init.push(VarDecl(SInt, name, Some(gen_expr(1, inner, state))))
          inner.push(name)
        }
        stmts.push(
          For(
            init,
            gen_expr(1, inner, state),
            if pick(state, 2) == 0 {
              Some(
                Assign(
                  Var(
                    if inner.length() > 0 {
                      inner[pick(state, inner.length())]
                    } else {
                      "v_missing"
                    },
                  ),
                  gen_expr(1, inner, state),
                ),
              )
            } else {
              None
            },
            Compound(gen_stmts(1, depth - 1, inner, true, next_name, state)),
          ),
        )
      }
      6 =>
        if in_loop {
          stmts.push(if pick(state, 2) == 0 { Break } else { Continue })
        }
      7 =>
        stmts.push(
          Compound(
            gen_stmts(2, depth - 1, vars.copy(), in_loop, next_name, state),
          ),
        )
      _ => stmts.push(ExprStmt(gen_expr(depth, vars, state)))
    }
  }
  stmts
}

///|
fn gen_program(size : Int, state : @splitmix.RandomState) -> @parser.Program {
  let scaled = if size < 1 { 1 } else if size > 12 { 12 } else { size }
  let depth = 1 + scaled / 4
  let next_name : Ref[Int] = { val: 0 }
  let globals : Array[@parser.GlobalDecl] = []
  let global_names : Array[String] = []
  for _ in 0..<pick(state, 3) {
    let name = "g" + next_name.val.to_string()
    next_name.val += 1
    globals.push({
      ty: SInt,
      name,
      init: Some(Scalar(gen_expr(1, global_names, state))),
      is_static: pick(state, 2) == 0,
      is_extern: false,
      is_weak: false,
      visibility: None,
      symbol_alias: None,
      section: None,
    })
    global_names.push(name)
  }
  let decls : Array[@parser.FuncDecl] = []
  let fn_count = 1 + pick(state, 2)
  for i in 0..<fn_count {
    let params : Array[@parser.Param] = []
    let vars = global_names.copy()
    for _ in 0..<pick(state, 3) {
      let name = "p" + next_name.val.to_string()
      next_name.val += 1
      params.push({ ty: SInt, name, bit_width: None })
      vars.push(name)
    }
    let body = gen_stmts(1 + scaled / 2, depth, vars, false, next_name, state)
    body.push(Return(Some(gen_expr(depth, vars, state))))
    decls.push({
      ret: SInt,
      name: "f" + i.to_string(),
      params,
      variadic: false,
      is_static: false,
      is_inline: false,
      is_weak: false,
      visibility: None,
      symbol_alias: None,
      section: None,
      is_constructor: false,
      is_destructor: false,
      body: Some(Compound(body)),
    })
  }
  let items : Array[@parser.TopLevel] = []
  for i in 0..<globals.length() {
    items.push(Global(i))
  }
  for i in 0..<decls.length() {
    items.push(Func(i))
  }
  { structs: [], globals, decls, items }
}
