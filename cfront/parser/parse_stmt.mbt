///|
priv enum InitDesignator {
  InitField(String)
  InitIndex(Int64)
  InitRange(Int64, Int64)
}

///|
fn Parser::parse_initializer_designator_path(
  self : Parser,
) -> Array[InitDesignator] raise ParseError {
  let path = []
  while self.token == Dot || self.token == LBracket {
    match self.token {
      Dot => {
        self.advance()
        match self.token {
          Ident(name) => {
            path.push(InitField(name))
            self.advance()
          }
          _ => self.unexpected("a field name in a designated initializer")
        }
      }
      LBracket => {
        self.advance()
        let start = match self.fold_const(self.parse_assign()) {
          Some(n) => n
          None => 0L
        }
        let end = if self.token == Ellipsis {
          self.advance()
          match self.fold_const(self.parse_assign()) {
            Some(n) => n
            None => start
          }
        } else {
          start
        }
        self.expect(RBracket)
        if start == end {
          path.push(InitIndex(start))
        } else {
          path.push(InitRange(start, end))
        }
      }
      _ => ()
    }
  }
  path
}

///|
fn Parser::parse_initializer_value(
  self : Parser,
  compound_literal : Bool,
) -> Expr raise ParseError {
  if self.token == LBrace {
    if compound_literal {
      Array(self.parse_compound_literal_init_exprs())
    } else {
      Array(self.parse_brace_init_exprs())
    }
  } else {
    self.parse_assign()
  }
}

///|
fn Parser::parse_designated_initializer(
  self : Parser,
  compound_literal : Bool,
) -> Expr raise ParseError {
  let path = self.parse_initializer_designator_path()
  self.expect(Assign)
  let mut value = self.parse_initializer_value(compound_literal)
  for i = path.length() - 1; i >= 0; i = i - 1 {
    match path[i] {
      InitField(name) => value = DesignatedField(name, value)
      InitIndex(index) => value = DesignatedIndex(index, value)
      InitRange(first, last) => value = DesignatedRange(first, last, value)
    }
  }
  value
}

///|
/// Parse expressions inside a brace initializer: { expr1, expr2, ... }
fn Parser::parse_brace_init_exprs(
  self : Parser,
) -> Array[Expr] raise ParseError {
  let exprs = []
  self.expect(LBrace)
  while self.token != RBrace && self.token != EOF {
    if self.token == LBrace {
      // Recursively parse nested brace initializer and wrap as Expr::Array
      let nested = self.parse_brace_init_exprs()
      exprs.push(Expr::Array(nested))
    } else if self.token == Dot || self.token == LBracket {
      exprs.push(self.parse_designated_initializer(false))
    } else {
      exprs.push(self.parse_assign())
    }
    if self.token == Comma {
      self.advance()
    }
  }
  self.expect(RBrace)
  exprs
}

///|
fn Parser::parse_compound_literal_init_exprs(
  self : Parser,
) -> Array[Expr] raise ParseError {
  let exprs = []
  self.expect(LBrace)
  while self.token != RBrace && self.token != EOF {
    if self.token == LBrace {
      let nested = self.parse_compound_literal_init_exprs()
      exprs.push(Expr::Array(nested))
    } else if self.token == Dot || self.token == LBracket {
      exprs.push(self.parse_designated_initializer(true))
    } else {
      exprs.push(self.parse_assign())
    }
    if self.token == Comma {
      self.advance()
    }
  }
  self.expect(RBrace)
  exprs
}

///|
/// Parses one statement, appending it to `into`.
///
/// A declaration is the reason this appends rather than returns: `int a, b;`
/// is two `VarDecl`s, and a label or clause in front of one labels the first
/// with the rest following as siblings, which is what C means by it. A
/// declaration that declares nothing -- a `typedef`, a `_Static_assert`, a
/// local prototype -- appends nothing at all rather than a placeholder.
fn Parser::parse_stmt_into(
  self : Parser,
  into : Array[Stmt],
) -> Unit raise ParseError {
  // Skip __extension__ before statements
  while self.token == Ident("__extension__") {
    self.advance()
  }
  match self.token {
    If => into.push(self.parse_if_stmt())
    While => into.push(self.parse_while_stmt())
    For => into.push(self.parse_for_stmt())
    Do => into.push(self.parse_do_while_stmt())
    Switch => into.push(self.parse_switch_stmt())
    Break => into.push(self.parse_break_stmt())
    Continue => into.push(self.parse_continue_stmt())
    Goto => into.push(self.parse_goto_stmt())
    Return => into.push(self.parse_return_stmt())
    LBrace => into.push(self.parse_compound_stmt())
    Semicolon => {
      self.advance()
      into.push(ExprStmt(int_literal(0, SInt)))
    }
    Ident("_Static_assert")
    | Ident("__Static_assert")
    | Ident("static_assert") => self.parse_static_assert_decl()
    Int
    | Void
    | Char
    | Struct
    | Union
    | Signed
    | Unsigned
    | Short
    | Long
    | Float
    | Double
    | Bool
    | Enum
    | Const
    | Restrict
    | Volatile
    | Extern
    | Static
    | Inline
    | Register
    | Auto => self.extend_stmts(into, self.parse_var_decl_stmts())
    Typedef => self.parse_typedef()
    Ident("_Alignas") | Ident("alignas") =>
      self.extend_stmts(into, self.parse_var_decl_stmts())
    Ident("_Atomic") => self.extend_stmts(into, self.parse_var_decl_stmts())
    Case => {
      self.advance()
      // Report against the start of the constant expression: by the time
      // folding has failed the parser sits on the colon after it.
      let value_start = self.token_start
      let expr = self.parse_assign()
      let value = match self.fold_const(expr) {
        Some(n) => n
        None =>
          match expr {
            Var(name) if self.enum_constants.contains(name) =>
              self.enum_constants[name]
            _ =>
              raise Unsupported(
                position=position_at(self.lexer.input, value_start),
                what="case label that does not fold to an integer constant",
              )
          }
      }
      self.expect(Colon)
      self.push_labelled(into, stmt => Case(value, stmt))
    }
    Default => {
      self.advance()
      self.expect(Colon)
      self.push_labelled(into, stmt => Default(stmt))
    }
    Ident(name) => {
      // Handle GCC inline assembly: asm volatile ("..." ::: "memory");
      if name == "asm" || name == "__asm__" || name == "__asm" {
        self.advance()
        // Skip optional volatile, goto, etc.
        while self.token == Volatile ||
              self.token == Ident("__volatile__") ||
              self.token == Ident("goto") {
          self.advance()
        }
        // Skip the asm body in parentheses
        if self.token == LParen {
          let mut depth = 1
          self.advance()
          while depth > 0 && self.token != EOF {
            if self.token == LParen {
              depth += 1
            } else if self.token == RParen {
              depth -= 1
            }
            if depth > 0 {
              self.advance()
            } else {
              self.advance()
              break
            }
          }
        }
        self.expect(Semicolon)
        return
      }
      // Handle __attribute__((...)); as a no-op statement
      if name == "__attribute__" || name == "__attribute" {
        self.advance()
        if self.token == LParen {
          let mut depth = 1
          self.advance()
          while depth > 0 && self.token != EOF {
            if self.token == LParen {
              depth += 1
            } else if self.token == RParen {
              depth -= 1
            }
            if depth > 0 {
              self.advance()
            } else {
              self.advance()
              break
            }
          }
        }
        if self.is_stmt_decl_start() {
          self.extend_stmts(into, self.parse_var_decl_stmts())
          return
        }
        self.expect(Semicolon)
        return
      }
      // Check if this is a label: name:
      let saved_pos = self.lexer.pos
      let saved_token = self.token
      self.advance()
      if self.token == Colon {
        self.advance()
        self.push_labelled(into, stmt => Label(name, stmt))
        return
      }
      self.lexer.pos = saved_pos
      self.token = saved_token
      // Check if this is a typedef'd or builtin type used for variable declaration
      if self.is_stmt_decl_start() {
        self.extend_stmts(into, self.parse_var_decl_stmts())
      } else {
        into.push(self.parse_expr_stmt())
      }
    }
    _ => into.push(self.parse_expr_stmt())
  }
}

///|
fn Parser::extend_stmts(
  self : Parser,
  into : Array[Stmt],
  stmts : Array[Stmt],
) -> Unit {
  ignore(self)
  for stmt in stmts {
    into.push(stmt)
  }
}

///|
/// Parses the statement a label, `case`, or `default` introduces, and appends
/// it wrapped by `wrap`.
///
/// The label takes the first statement parsed and any others follow it as
/// siblings, which is what `foo: int a, b;` means: the label marks the
/// declaration of `a`, and `b` is declared next to it in the same scope. A
/// label with no statement after it -- `foo: }` at the end of a block, or a
/// label on a `typedef` -- wraps an empty statement so that the label survives
/// and stays jumpable.
fn Parser::push_labelled(
  self : Parser,
  into : Array[Stmt],
  wrap : (Stmt) -> Stmt,
) -> Unit raise ParseError {
  let labelled : Array[Stmt] = []
  if self.token != RBrace && self.token != EOF {
    self.parse_stmt_into(labelled)
  }
  if labelled.length() == 0 {
    into.push(wrap(ExprStmt(int_literal(0, SInt))))
    return
  }
  into.push(wrap(labelled[0]))
  for i in 1..<labelled.length() {
    into.push(labelled[i])
  }
}

///|
/// Parses one statement where C allows exactly one -- the body of an `if`,
/// loop, or `else`.
///
/// A declaration is not a statement in C and cannot appear in those positions,
/// so the multi-statement case does not arise for valid input; a block keeps
/// anything that does arrive together rather than dropping it.
fn Parser::parse_stmt(self : Parser) -> Stmt raise ParseError {
  let stmts : Array[Stmt] = []
  self.parse_stmt_into(stmts)
  match stmts.length() {
    1 => stmts[0]
    0 => ExprStmt(int_literal(0, SInt))
    _ => Compound(stmts)
  }
}

///|
fn Parser::is_stmt_decl_start(self : Parser) -> Bool {
  match self.token {
    Int
    | Void
    | Char
    | Struct
    | Union
    | Signed
    | Unsigned
    | Short
    | Long
    | Float
    | Double
    | Bool
    | Enum
    | Const
    | Restrict
    | Volatile
    | Extern
    | Static
    | Inline
    | Register
    | Auto => true
    Ident(name) =>
      name == "_Atomic" ||
      name == "_Alignas" ||
      name == "alignas" ||
      name == "__int128" ||
      name == "__int128_t" ||
      name == "__uint128_t" ||
      name == "_Float16" ||
      name == "__float128" ||
      name == "_Float128" ||
      is_extended_float_type_name(name) ||
      name == "_BitInt" ||
      name == "_Complex" ||
      name == "__complex__" ||
      name == "__builtin_va_list" ||
      name == "__typeof" ||
      name == "__typeof__" ||
      name == "typeof" ||
      name == "__auto_type" ||
      self.typedefs.contains(name)
    _ => false
  }
}

///|
fn Parser::parse_if_stmt(self : Parser) -> Stmt raise ParseError {
  self.advance() // if
  self.expect(LParen)
  let cond = self.parse_expr()
  if self.token != RParen {

  }
  self.expect(RParen)
  let then_ = self.parse_stmt()
  let else_ = if self.token == Else {
    self.advance()
    Some(self.parse_stmt())
  } else {
    None
  }
  If(cond, then_, else_)
}

///|
fn Parser::parse_while_stmt(self : Parser) -> Stmt raise ParseError {
  self.advance() // while
  self.expect(LParen)
  let cond = self.parse_expr()
  self.expect(RParen)
  let body = self.parse_stmt()
  While(cond, body)
}

///|
fn Parser::parse_for_stmt(self : Parser) -> Stmt raise ParseError {
  self.advance() // for
  self.expect(LParen)
  // Parse init: can be empty, a declaration of one or more names, or an
  // expression. `for (int i = 0, n = len; ...)` is why this is a list.
  let init : Array[Stmt] = if self.token == Semicolon {
    self.advance()
    []
  } else if self.is_stmt_decl_start() {
    self.parse_var_decl_stmts()
  } else {
    let expr = self.parse_expr()
    self.expect(Semicolon)
    [ExprStmt(expr)]
  }
  // Parse condition
  let cond = if self.token == Semicolon {
    self.advance()
    int_literal(1, SInt) // always true
  } else {
    let expr = self.parse_expr()
    self.expect(Semicolon)
    expr
  }
  // Parse update
  let update = if self.token == RParen { None } else { Some(self.parse_expr()) }
  self.expect(RParen)
  let body = self.parse_stmt()
  For(init, cond, update, body)
}

///|
fn Parser::parse_do_while_stmt(self : Parser) -> Stmt raise ParseError {
  self.advance() // do
  let body = self.parse_stmt()
  self.expect(While)
  self.expect(LParen)
  let cond = self.parse_expr()
  self.expect(RParen)
  self.expect(Semicolon)
  DoWhile(cond, body)
}

///|
fn Parser::parse_continue_stmt(self : Parser) -> Stmt raise ParseError {
  self.advance() // continue
  self.expect(Semicolon)
  Continue
}

///|
fn Parser::parse_switch_stmt(self : Parser) -> Stmt raise ParseError {
  self.advance() // switch
  self.expect(LParen)
  let expr = self.parse_expr()
  self.expect(RParen)
  self.expect(LBrace)
  let stmts = []
  while self.token != RBrace {
    self.parse_stmt_into(stmts)
  }
  self.expect(RBrace)
  Switch(expr, Compound(stmts))
}

///|
fn Parser::parse_break_stmt(self : Parser) -> Stmt raise ParseError {
  self.advance() // break
  self.expect(Semicolon)
  Break
}

///|
fn Parser::parse_goto_stmt(self : Parser) -> Stmt raise ParseError {
  self.advance() // goto
  if self.token == Star {
    // Computed goto: goto *expr;
    self.advance() // consume *
    let expr = self.parse_expr()
    self.expect(Semicolon)
    return ComputedGoto(expr)
  }
  let name = match self.token {
    Ident(n) => {
      self.advance()
      n
    }
    _ => self.unexpected("a label name after goto")
  }
  self.expect(Semicolon)
  Goto(name)
}

///|
fn Parser::parse_return_stmt(self : Parser) -> Stmt raise ParseError {
  self.advance() // return
  let expr = if self.token == Semicolon {
    None
  } else {
    Some(self.parse_expr())
  }
  self.expect(Semicolon)
  Return(expr)
}

///|
fn Parser::parse_compound_stmt(self : Parser) -> Stmt raise ParseError {
  let saved_value_types = self.value_types.copy()
  let saved_tags = self.enter_tag_scope()
  // Statics bind lexically like everything else: a nested block's shadowing
  // `static int x` gets its own symbol, and when the block ends, references
  // to `x` must go back to the outer object's symbol rather than stay bound
  // to the inner one.
  let saved_static_locals = self.static_locals.copy()
  self.expect(LBrace)
  let stmts = []
  while self.token != RBrace {
    self.parse_stmt_into(stmts)
  }
  self.expect(RBrace)
  self.value_types = saved_value_types
  self.exit_tag_scope(saved_tags)
  self.static_locals = saved_static_locals
  Compound(stmts)
}

///|
/// Helper to register a function-local static variable as a global.
/// Returns the mangled global name and adds the mapping to static_locals.
fn Parser::register_static_local(self : Parser, name : String) -> String {
  let base = if self.current_func_name == "" {
    name
  } else {
    "_" + self.current_func_name + "_" + name
  }
  // Distinct blocks of one function may each declare a static with the same
  // name -- sqlite's `iLn` counters do -- and each is its own object with its
  // own storage. A shared mangled name would emit one global several times
  // over, so later ones take a numbered suffix. References resolve through
  // `static_locals`, which now points at the newest, matching the lexical
  // scope the reference sits in for straight-line code.
  let mut mangled = base
  let mut attempt = 2
  while self.global_name_taken(mangled) {
    mangled = base + "_" + attempt.to_string()
    attempt += 1
  }
  self.static_locals[name] = mangled
  mangled
}

///|
fn Parser::global_name_taken(self : Parser, name : String) -> Bool {
  for global in self.globals {
    if global.name == name {
      return true
    }
  }
  false
}

///|
fn initializer_element_count(init_exprs : Array[Expr]) -> Int {
  let mut count = 0
  let mut cursor = 0
  for expr in init_exprs {
    match expr {
      DesignatedIndex(index, _) => {
        let next = index.to_int() + 1
        if next > count {
          count = next
        }
        cursor = next
      }
      DesignatedRange(_, end, _) => {
        let next = end.to_int() + 1
        if next > count {
          count = next
        }
        cursor = next
      }
      _ => {
        let next = cursor + 1
        if next > count {
          count = next
        }
        cursor = next
      }
    }
  }
  count
}

///|
/// Helper to parse an initializer into GlobalInit for static locals.
fn Parser::parse_static_initializer(
  self : Parser,
  ty : Type,
) -> (Type, GlobalInit?) raise ParseError {
  if self.token == Assign {
    self.advance()
    if self.token == LBrace {
      let init_exprs = self.parse_brace_init_exprs()
      global_brace_initializer_for_type(ty, init_exprs)
    } else {
      let expr = self.parse_assign()
      match (ty, expr) {
        (Array(elem_ty, 0), String(s)) => {
          let len = s.length()
          let arr_ty = Type::Array(elem_ty, len + 1)
          let init_exprs = Array::make(len + 1, int_literal(0, SInt))
          for i = 0; i < len; i = i + 1 {
            init_exprs[i] = int_literal(s[i].to_int().to_int64(), SInt)
          }
          init_exprs[len] = int_literal(0, SInt)
          (arr_ty, Some(Array(init_exprs)))
        }
        _ => (ty, Some(Scalar(expr)))
      }
    }
  } else {
    (ty, None)
  }
}

///|
fn global_brace_initializer_for_type(
  ty : Type,
  init_exprs : Array[Expr],
) -> (Type, GlobalInit?) {
  match local_init_core_type(ty) {
    Struct(_) | Union(_) | Array(_, _) => {
      let init_count = initializer_element_count(init_exprs)
      let final_ty = local_init_infer_array_size(ty, init_count)
      (final_ty, Some(Array(init_exprs)))
    }
    _ => (ty, Some(Scalar(local_init_scalar_brace_expr(init_exprs))))
  }
}

///|
fn local_init_core_type(ty : Type) -> Type {
  ty.core_type()
}

///|
fn local_init_infer_array_size(ty : Type, count : Int) -> Type {
  match ty {
    Array(elem, 0) => Array(elem, count)
    Atomic(inner) => Atomic(local_init_infer_array_size(inner, count))
    Aligned(inner, align) =>
      Aligned(local_init_infer_array_size(inner, count), align)
    _ => ty
  }
}

///|
/// The value an initializer denotes when its destination is a scalar.
///
/// C lets braces wrap a scalar initializer -- `int x = {5}` and `int a[2] =
/// {{5}, {37}}` are both legal -- and lets a designator carry one. The AST
/// records each of those as written, so every consumer that finally stores a
/// scalar has to read through them, and this is the one rule for doing it.
/// Empty braces denote zero. A `CompoundLiteral` is deliberately left alone:
/// unlike a brace list it is an expression in its own right.
pub fn scalar_initializer_value(expr : Expr) -> Expr {
  match expr {
    Array(values) =>
      if values.length() == 0 {
        int_literal(0, SInt)
      } else {
        scalar_initializer_value(values[0])
      }
    DesignatedField(_, value)
    | DesignatedIndex(_, value)
    | DesignatedRange(_, _, value) => scalar_initializer_value(value)
    _ => expr
  }
}

///|
fn local_init_scalar_brace_expr(init_exprs : Array[Expr]) -> Expr {
  scalar_initializer_value(Array(init_exprs))
}

///|
/// Parses a local declarator's `= <initializer>` and returns the declared type
/// together with the statement that declares it.
///
/// The initializer is recorded as it was written. A brace list stays an `Array`
/// expression carrying its designators, and a string initializing a `char`
/// array stays a `String`; expanding either into element stores is MIR's job
/// and each code generator's, not the parser's. The one thing that cannot wait
/// is an array size the braces imply, since the size is part of the type this
/// returns.
fn Parser::parse_local_declarator_init(
  self : Parser,
  ty : Type,
  name : String,
) -> (Type, Stmt) raise ParseError {
  if self.token != Assign {
    return (ty, VarDecl(ty, name, None))
  }
  self.advance()
  if self.token == LBrace {
    let init_exprs = self.parse_brace_init_exprs()
    match local_init_core_type(ty) {
      Struct(_) | Union(_) => (ty, VarDecl(ty, name, Some(Array(init_exprs))))
      Array(_, _) => {
        let sized = local_init_infer_array_size(
          ty,
          initializer_element_count(init_exprs),
        )
        (sized, VarDecl(sized, name, Some(Array(init_exprs))))
      }
      // Braces around a scalar initializer denote the value itself, matching
      // what a global initializer records for the same declaration.
      _ =>
        (ty, VarDecl(ty, name, Some(local_init_scalar_brace_expr(init_exprs))))
    }
  } else {
    let expr = self.parse_assign()
    match (local_init_core_type(ty), expr) {
      // `char s[] = "abc"` sizes the array from the literal, terminator
      // included; the initializer itself stays the string that was written.
      // The size goes back inside any `_Atomic` or `_Alignas` wrapper, the
      // same way the brace path puts it there.
      (Array(_, 0), String(text)) => {
        let sized = local_init_infer_array_size(
          ty,
          @ctype.string_literal_array_length(text),
        )
        (sized, VarDecl(sized, name, Some(expr)))
      }
      _ => (ty, VarDecl(ty, name, Some(expr)))
    }
  }
}

///|
/// Parses one declaration, which may introduce several names.
///
/// Each declarator becomes its own `VarDecl`. C groups them under one type
/// specifier, but the grouping means nothing once the type is resolved per
/// name -- `int *a, b` declares a pointer and an int -- and a generator
/// emitting a declaration would never build the group.
fn Parser::parse_var_decl_stmts(self : Parser) -> Array[Stmt] raise ParseError {
  let spec = self.parse_decl_specifiers()
  // Local struct/union/enum definition without variable: struct Foo { ... };
  if self.token == Semicolon {
    self.advance()
    return []
  }
  let stmts = []
  // Parse first declarator
  let decl = self.parse_declarator(
    spec.base_type,
    base_is_function=spec.base_is_function,
  )
  let post_decl_attrs = self.skip_attributes_info()
  let decl_ty = self.apply_decl_attrs(
    apply_decl_align(resolve_var_type(decl), spec.align),
    post_decl_attrs,
  )
  let decl_is_weak = spec.is_weak || post_decl_attrs.is_weak
  let decl_visibility = merge_visibility(
    spec.visibility,
    post_decl_attrs.visibility,
  )
  let decl_alias = merge_alias(spec.symbol_alias, post_decl_attrs.symbol_alias)
  let decl_section = merge_section(spec.section, post_decl_attrs.section)
  if spec.is_auto_type {
    if spec.is_static ||
      spec.is_extern ||
      decl.name == "" ||
      decl.ptr_depth != 0 {
      self.malformed(
        "__auto_type declaration, which needs one initialized identifier",
      )
    }
    self.expect(Assign)
    let expr = self.parse_assign()
    let inferred_ty = auto_decl_type(self.const_expr_type(expr))
    let ty = self.apply_decl_attrs(inferred_ty, post_decl_attrs)
    self.expect(Semicolon)
    self.remember_value_type(decl.name, ty)
    return [VarDecl(ty, decl.name, Some(expr))]
  }
  // Local function prototype inside a function body: int foo(void);
  if decl.is_func_decl && self.token == Semicolon {
    let params = decl.func_params.unwrap()
    let (_, variadic) = function_param_info(params)
    if variadic {
      let _ = params.pop()
    }
    let filtered_params = []
    for i = 0; i < params.length(); i = i + 1 {
      if params[i].ty != Void {
        filtered_params.push(params[i])
      }
    }
    for i = 0; i < filtered_params.length(); i = i + 1 {
      match filtered_params[i].ty {
        Array(elem, _) =>
          filtered_params[i] = {
            ty: Pointer(elem),
            name: filtered_params[i].name,
            bit_width: None,
          }
        _ => ()
      }
    }
    let ret_ty = match decl.func_ret_ty {
      Some(rt) => rt
      None => spec.base_type
    }
    self.local_func_decls.push({
      ret: ret_ty,
      name: decl.name,
      params: filtered_params,
      variadic,
      is_static: spec.is_static,
      is_inline: spec.is_inline,
      is_weak: decl_is_weak,
      visibility: decl_visibility,
      symbol_alias: decl_alias,
      section: decl_section,
      is_constructor: spec.is_constructor || post_decl_attrs.is_constructor,
      is_destructor: spec.is_destructor || post_decl_attrs.is_destructor,
      body: None,
    })
    self.remember_value_type(decl.name, decl_ty)
    self.expect(Semicolon)
    return []
  }
  // Handle static / extern locals: promote to globals
  if spec.is_static || spec.is_extern {
    let mangled = if spec.is_static {
      self.register_static_local(decl.name)
    } else {
      // extern local: refers to an external global with the same name
      self.static_locals[decl.name] = decl.name
      decl.name
    }
    let (final_ty, init) = self.parse_static_initializer(decl_ty)
    if spec.is_static {
      self.add_global({
        ty: final_ty,
        name: mangled,
        init,
        is_static: true,
        is_extern: false,
        is_weak: false,
        visibility: None,
        symbol_alias: None,
        section: None,
      })
    } else {
      self.add_global({
        ty: final_ty,
        name: mangled,
        init: None,
        is_static: false,
        is_extern: true,
        is_weak: decl_is_weak,
        visibility: decl_visibility,
        symbol_alias: decl_alias,
        section: decl_section,
      })
    }
    self.remember_value_type(mangled, final_ty)
    self.remember_value_type(decl.name, final_ty)
    // Parse additional static/extern variables
    while self.token == Comma {
      self.advance()
      let extra_decl = self.parse_declarator(
        spec.base_type,
        base_is_function=spec.base_is_function,
      )
      let extra_post_decl_attrs = self.skip_attributes_info()
      let extra_decl_ty = self.apply_decl_attrs(
        apply_decl_align(resolve_var_type(extra_decl), spec.align),
        extra_post_decl_attrs,
      )
      let extra_decl_is_weak = spec.is_weak || extra_post_decl_attrs.is_weak
      let extra_decl_visibility = merge_visibility(
        spec.visibility,
        extra_post_decl_attrs.visibility,
      )
      let extra_decl_alias = merge_alias(
        spec.symbol_alias,
        extra_post_decl_attrs.symbol_alias,
      )
      let extra_decl_section = merge_section(
        spec.section,
        extra_post_decl_attrs.section,
      )
      let extra_mangled = if spec.is_static {
        self.register_static_local(extra_decl.name)
      } else {
        self.static_locals[extra_decl.name] = extra_decl.name
        extra_decl.name
      }
      let (extra_ty, extra_init) = self.parse_static_initializer(extra_decl_ty)
      if spec.is_static {
        self.add_global({
          ty: extra_ty,
          name: extra_mangled,
          init: extra_init,
          is_static: true,
          is_extern: false,
          is_weak: false,
          visibility: None,
          symbol_alias: None,
          section: None,
        })
      } else {
        self.add_global({
          ty: extra_ty,
          name: extra_mangled,
          init: None,
          is_static: false,
          is_extern: true,
          is_weak: extra_decl_is_weak,
          visibility: extra_decl_visibility,
          symbol_alias: extra_decl_alias,
          section: extra_decl_section,
        })
      }
      self.remember_value_type(extra_mangled, extra_ty)
      self.remember_value_type(extra_decl.name, extra_ty)
    }
    self.expect(Semicolon)
    return []
  }
  // Handle initializer
  let (ty, decl_stmt) = self.parse_local_declarator_init(decl_ty, decl.name)
  stmts.push(decl_stmt)
  self.remember_value_type(decl.name, ty)
  // Parse additional variables: int a, *b, c[8], (*fp)(void);
  while self.token == Comma {
    self.advance()
    let extra_decl = self.parse_declarator(
      spec.base_type,
      base_is_function=spec.base_is_function,
    )
    let extra_post_decl_attrs = self.skip_attributes_info()
    let extra_decl_ty = self.apply_decl_attrs(
      apply_decl_align(resolve_var_type(extra_decl), spec.align),
      extra_post_decl_attrs,
    )
    let (extra_ty, extra_stmt) = self.parse_local_declarator_init(
      extra_decl_ty,
      extra_decl.name,
    )
    stmts.push(extra_stmt)
    self.remember_value_type(extra_decl.name, extra_ty)
  }
  self.expect(Semicolon)
  stmts
}

///|
fn auto_decl_type(ty : Type) -> Type {
  match ty {
    Array(elem, _) => Pointer(elem)
    Aligned(inner, _) => auto_decl_type(inner)
    other => other
  }
}

///|
fn Parser::parse_expr_stmt(self : Parser) -> Stmt raise ParseError {
  let expr = self.parse_expr()
  self.expect(Semicolon)
  ExprStmt(expr)
}
