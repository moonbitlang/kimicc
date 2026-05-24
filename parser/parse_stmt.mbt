///|
priv enum InitDesignator {
  InitField(String)
  InitIndex(Int64)
  InitRange(Int64, Int64)
}

///|
fn Parser::parse_initializer_designator_path(
  self : Parser,
) -> Array[InitDesignator] {
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
          _ => abort("Expected field name in designated initializer")
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
) -> Expr {
  if self.token == LBrace {
    if compound_literal {
      Expr::Array(self.parse_compound_literal_init_exprs())
    } else {
      Expr::Array(self.parse_brace_init_exprs())
    }
  } else {
    self.parse_assign()
  }
}

///|
fn Parser::parse_designated_initializer(
  self : Parser,
  compound_literal : Bool,
) -> Expr {
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
fn Parser::parse_brace_init_exprs(self : Parser) -> Array[Expr] {
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
fn Parser::parse_compound_literal_init_exprs(self : Parser) -> Array[Expr] {
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
fn Parser::parse_stmt(self : Parser) -> Stmt {
  // Skip __extension__ before statements
  while self.token == Ident("__extension__") {
    self.advance()
  }
  match self.token {
    If => self.parse_if_stmt()
    While => self.parse_while_stmt()
    For => self.parse_for_stmt()
    Do => self.parse_do_while_stmt()
    Switch => self.parse_switch_stmt()
    Break => self.parse_break_stmt()
    Continue => self.parse_continue_stmt()
    Goto => self.parse_goto_stmt()
    Return => self.parse_return_stmt()
    LBrace => self.parse_compound_stmt()
    Semicolon => {
      self.advance()
      ExprStmt(Number(0))
    }
    Ident("_Static_assert")
    | Ident("__Static_assert")
    | Ident("static_assert") => {
      self.parse_static_assert_decl()
      ExprStmt(Number(0))
    }
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
    | Auto => self.parse_var_decl_stmt()
    Typedef => {
      self.parse_typedef()
      ExprStmt(Number(0))
    }
    Ident("_Alignas") | Ident("alignas") => self.parse_var_decl_stmt()
    Ident("_Atomic") => self.parse_var_decl_stmt()
    Case => {
      self.advance()
      let expr = self.parse_assign()
      let value = match self.fold_const(expr) {
        Some(n) => n
        None =>
          match expr {
            Var(name) =>
              if self.enum_constants.contains(name) {
                self.enum_constants[name]
              } else {
                0
              }
            _ => 0
          }
      }
      self.expect(Colon)
      let stmt = self.parse_stmt()
      let label = self.fresh_case_label(value)
      Label(label, stmt)
    }
    Default => {
      self.advance()
      self.expect(Colon)
      let stmt = self.parse_stmt()
      let label = self.fresh_default_label()
      Label(label, stmt)
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
        return ExprStmt(Number(0))
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
          return self.parse_var_decl_stmt()
        }
        self.expect(Semicolon)
        return ExprStmt(Number(0))
      }
      // Check if this is a label: name:
      let saved_pos = self.lexer.pos
      let saved_token = self.token
      self.advance()
      if self.token == Colon {
        self.advance()
        // If labeled statement is case/default, don't consume it
        // Let parse_switch_stmt handle it
        if self.token == Case || self.token == Default {
          return Label(name, ExprStmt(Number(0)))
        }
        let stmt = self.parse_stmt()
        return Label(name, stmt)
      }
      self.lexer.pos = saved_pos
      self.token = saved_token
      // Check if this is a typedef'd or builtin type used for variable declaration
      if self.is_stmt_decl_start() {
        self.parse_var_decl_stmt()
      } else {
        self.parse_expr_stmt()
      }
    }
    _ => self.parse_expr_stmt()
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
fn Parser::parse_if_stmt(self : Parser) -> Stmt {
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
fn Parser::parse_while_stmt(self : Parser) -> Stmt {
  self.advance() // while
  self.expect(LParen)
  let cond = self.parse_expr()
  self.expect(RParen)
  let body = self.parse_stmt()
  While(cond, body)
}

///|
fn Parser::parse_for_stmt(self : Parser) -> Stmt {
  self.advance() // for
  self.expect(LParen)
  // Parse init: can be empty, a declaration, or an expression
  let init = if self.token == Semicolon {
    self.advance()
    None
  } else if self.is_stmt_decl_start() {
    Some(self.parse_var_decl_stmt())
  } else {
    let expr = self.parse_expr()
    self.expect(Semicolon)
    Some(ExprStmt(expr))
  }
  // Parse condition
  let cond = if self.token == Semicolon {
    self.advance()
    Expr::Number(1) // always true
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
fn Parser::parse_do_while_stmt(self : Parser) -> Stmt {
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
fn Parser::parse_continue_stmt(self : Parser) -> Stmt {
  self.advance() // continue
  self.expect(Semicolon)
  Continue
}

///|
fn extract_case_value(name : String) -> Int64? {
  let prefix_len = if name.has_prefix("__kimicc_case_") {
    "__kimicc_case_".length()
  } else if name.has_prefix("case_") {
    5
  } else {
    return None
  }
  let mut case_value : Int64 = 0
  let mut negative = false
  let mut saw_digit = false
  for i = prefix_len; i < name.length(); i = i + 1 {
    let ch = name[i]
    if ch >= '0' && ch <= '9' {
      saw_digit = true
      case_value = case_value * 10 + (ch.to_int() - '0'.to_int()).to_int64()
    } else if ch == '-' && i == prefix_len {
      negative = true
    } else if saw_digit {
      break
    }
  }
  if negative {
    case_value = -case_value
  }
  Some(case_value)
}

///|
fn is_default_label(name : String) -> Bool {
  name == "default" || name.has_prefix("__kimicc_default_")
}

///|
fn Parser::fresh_case_label(self : Parser, value : Int64) -> String {
  let label = "__kimicc_case_" +
    value.to_string() +
    "_" +
    self.case_label_counter.to_string()
  self.case_label_counter += 1
  label
}

///|
fn Parser::fresh_default_label(self : Parser) -> String {
  let label = "__kimicc_default_" + self.case_label_counter.to_string()
  self.case_label_counter += 1
  label
}

///|
fn collect_switch_cases(stmt : Stmt, cases : Array[(Int64?, String)]) -> Unit {
  match stmt {
    Label(name, body) => {
      match extract_case_value(name) {
        Some(value) => cases.push((Some(value), name))
        None => if is_default_label(name) { cases.push((None, name)) }
      }
      collect_switch_cases(body, cases)
    }
    Compound(stmts) | StmtList(stmts) =>
      for s in stmts {
        collect_switch_cases(s, cases)
      }
    If(_, then_, else_) => {
      collect_switch_cases(then_, cases)
      match else_ {
        Some(s) => collect_switch_cases(s, cases)
        None => ()
      }
    }
    While(_, body) | DoWhile(_, body) => collect_switch_cases(body, cases)
    For(init, _, _, body) => {
      match init {
        Some(s) => collect_switch_cases(s, cases)
        None => ()
      }
      collect_switch_cases(body, cases)
    }
    // A nested switch owns its own case/default labels.
    Switch(_, _, _) => ()
    _ => ()
  }
}

///|
fn Parser::parse_switch_stmt(self : Parser) -> Stmt {
  self.advance() // switch
  self.expect(LParen)
  let expr = self.parse_expr()
  self.expect(RParen)
  self.expect(LBrace)
  let stmts = []
  while self.token != RBrace {
    stmts.push(self.parse_stmt())
  }
  self.expect(RBrace)
  let body = Compound(stmts)
  let cases = []
  collect_switch_cases(body, cases)
  Switch(expr, body, cases)
}

///|
fn Parser::parse_break_stmt(self : Parser) -> Stmt {
  self.advance() // break
  self.expect(Semicolon)
  Break
}

///|
fn Parser::parse_goto_stmt(self : Parser) -> Stmt {
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
    _ => abort("Expected label name after goto")
  }
  self.expect(Semicolon)
  Goto(name)
}

///|
fn Parser::parse_return_stmt(self : Parser) -> Stmt {
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
fn Parser::parse_compound_stmt(self : Parser) -> Stmt {
  let saved_value_types = self.value_types.copy()
  self.expect(LBrace)
  let stmts = []
  while self.token != RBrace {
    stmts.push(self.parse_stmt())
  }
  self.expect(RBrace)
  self.value_types = saved_value_types
  Compound(stmts)
}

///|
/// Helper to register a function-local static variable as a global.
/// Returns the mangled global name and adds the mapping to static_locals.
fn Parser::register_static_local(self : Parser, name : String) -> String {
  let mangled = if self.current_func_name == "" {
    name
  } else {
    "_" + self.current_func_name + "_" + name
  }
  self.static_locals[name] = mangled
  mangled
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
) -> (Type, GlobalInit?) {
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
          let init_exprs = Array::make(len + 1, Expr::Number(0))
          for i = 0; i < len; i = i + 1 {
            init_exprs[i] = Number(s[i].to_int().to_int64())
          }
          init_exprs[len] = Number(0)
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
fn find_struct_init_field_index(fields : Array[Param], name : String) -> Int {
  for i = 0; i < fields.length(); i = i + 1 {
    if fields[i].name == name {
      return i
    }
  }
  -1
}

///|
fn local_init_core_type(ty : Type) -> Type {
  ty.core_type()
}

///|
fn local_init_array_elem_type(ty : Type) -> Type? {
  ty.array_element()
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
fn local_init_scalar_expr(expr : Expr) -> Expr {
  match expr {
    Array(values) => local_init_scalar_brace_expr(values)
    DesignatedField(_, value)
    | DesignatedIndex(_, value)
    | DesignatedRange(_, _, value) => local_init_scalar_expr(value)
    _ => expr
  }
}

///|
fn local_init_scalar_brace_expr(init_exprs : Array[Expr]) -> Expr {
  if init_exprs.length() == 0 {
    Number(0)
  } else {
    local_init_scalar_expr(init_exprs[0])
  }
}

///|
fn Parser::push_struct_init_assignments(
  self : Parser,
  stmts : Array[Stmt],
  target : Expr,
  ty : Type,
  init_exprs : Array[Expr],
) -> Unit {
  let struct_name = match local_init_core_type(ty) {
    Struct(n) | Union(n) => n
    _ => return
  }
  let fields = if self.struct_decls.contains(struct_name) {
    self.struct_decls[struct_name].fields
  } else {
    []
  }
  let mut positional = 0
  for init_expr in init_exprs {
    let (field_index, value) = match init_expr {
      DesignatedField(field_name, e) => {
        let idx = find_struct_init_field_index(fields, field_name)
        if idx >= 0 {
          positional = idx + 1
        }
        (idx, e)
      }
      _ => {
        let idx = positional
        positional += 1
        (idx, init_expr)
      }
    }
    if field_index < 0 || field_index >= fields.length() {
      continue
    }
    let field = fields[field_index]
    let field_target = Expr::MemberAccess(target, field.name)
    match (local_init_core_type(field.ty), value) {
      (Struct(_) | Union(_), Array(field_exprs)) =>
        self.push_struct_init_assignments(
          stmts,
          field_target,
          field.ty,
          field_exprs,
        )
      (Struct(_) | Union(_), DesignatedField(_, _)) =>
        self.push_struct_init_assignments(stmts, field_target, field.ty, [value])
      (Array(_, _), Array(elem_exprs)) =>
        self.push_array_init_assignments_at(
          stmts,
          field_target,
          field.ty,
          elem_exprs,
        )
      (Array(_, _), DesignatedIndex(_, _))
      | (Array(_, _), DesignatedRange(_, _, _)) =>
        self.push_array_init_assignments_at(stmts, field_target, field.ty, [
          value,
        ])
      (Struct(_) | Union(_), Number(0)) => ()
      (Array(_, _), Number(0)) => ()
      _ =>
        stmts.push(
          ExprStmt(Assign(field_target, local_init_scalar_expr(value))),
        )
    }
  }
}

///|
fn Parser::push_array_init_assignments_at(
  self : Parser,
  stmts : Array[Stmt],
  target : Expr,
  ty : Type,
  init_exprs : Array[Expr],
) -> Unit {
  let elem_ty = match local_init_array_elem_type(ty) {
    Some(elem) => elem
    None => return
  }
  let mut cursor = 0
  for init_expr in init_exprs {
    let mut start = cursor
    let mut end = cursor
    let value = match init_expr {
      DesignatedIndex(index, e) => {
        start = index.to_int()
        end = start
        cursor = start + 1
        e
      }
      DesignatedRange(first, last, e) => {
        start = first.to_int()
        end = last.to_int()
        cursor = end + 1
        e
      }
      _ => {
        cursor += 1
        init_expr
      }
    }
    for i = start; i <= end; i = i + 1 {
      let elem = Expr::ArrayAccess(target, Number(i.to_int64()))
      match (local_init_core_type(elem_ty), value) {
        (Struct(_) | Union(_), Array(field_exprs)) =>
          self.push_struct_init_assignments(stmts, elem, elem_ty, field_exprs)
        (Struct(_) | Union(_), DesignatedField(_, _)) =>
          self.push_struct_init_assignments(stmts, elem, elem_ty, [value])
        (Array(_, _), Array(elem_exprs)) =>
          self.push_array_init_assignments_at(stmts, elem, elem_ty, elem_exprs)
        (Array(_, _), DesignatedIndex(_, _))
        | (Array(_, _), DesignatedRange(_, _, _)) =>
          self.push_array_init_assignments_at(stmts, elem, elem_ty, [value])
        (Struct(_) | Union(_), Number(0)) => ()
        (Array(_, _), Number(0)) => ()
        _ => stmts.push(ExprStmt(Assign(elem, local_init_scalar_expr(value))))
      }
    }
  }
}

///|
fn Parser::push_array_init_assignments(
  self : Parser,
  stmts : Array[Stmt],
  name : String,
  ty : Type,
  init_exprs : Array[Expr],
) -> Unit {
  self.push_array_init_assignments_at(stmts, Var(name), ty, init_exprs)
}

///|
fn Parser::parse_var_decl_stmt(self : Parser) -> Stmt {
  let spec = self.parse_decl_specifiers()
  // Local struct/union/enum definition without variable: struct Foo { ... };
  if self.token == Semicolon {
    self.advance()
    return ExprStmt(Number(0))
  }
  let stmts = []
  // Parse first declarator
  let decl = self.parse_declarator(spec.base_type)
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
      abort("__auto_type requires one initialized local identifier")
    }
    self.expect(Assign)
    let expr = self.parse_assign()
    let inferred_ty = auto_decl_type(self.const_expr_type(expr))
    let ty = self.apply_decl_attrs(inferred_ty, post_decl_attrs)
    self.expect(Semicolon)
    self.remember_value_type(decl.name, ty)
    return VarDecl(ty, decl.name, Some(expr))
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
    return ExprStmt(Number(0))
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
      self.globals.push({
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
      self.globals.push({
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
      let extra_decl = self.parse_declarator(spec.base_type)
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
        self.globals.push({
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
        self.globals.push({
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
    return ExprStmt(Number(0))
  }
  // Handle initializer
  let ty = if self.token == Assign {
    self.advance()
    if self.token == LBrace {
      // For struct/union types, lower brace initializers into field assignments.
      match local_init_core_type(decl_ty) {
        Struct(_) | Union(_) => {
          // Parse brace initializer expressions and create field assignments
          let init_exprs = self.parse_brace_init_exprs()
          stmts.push(VarDecl(decl_ty, decl.name, Some(Number(0))))
          self.push_struct_init_assignments(
            stmts,
            Var(decl.name),
            decl_ty,
            init_exprs,
          )
          decl_ty
        }
        Array(_, _) => {
          let init_exprs = self.parse_brace_init_exprs()
          let init_count = initializer_element_count(init_exprs)
          // Update array type if size was inferred
          let ty = local_init_infer_array_size(decl_ty, init_count)
          stmts.push(VarDecl(ty, decl.name, Some(Number(0))))
          self.push_array_init_assignments(stmts, decl.name, ty, init_exprs)
          ty
        }
        _ => {
          let init_exprs = self.parse_brace_init_exprs()
          stmts.push(
            VarDecl(
              decl_ty,
              decl.name,
              Some(local_init_scalar_brace_expr(init_exprs)),
            ),
          )
          decl_ty
        }
      }
    } else {
      let expr = self.parse_assign()
      // Handle string literal initializer for char arrays: char s[] = "abc"
      match (decl_ty, expr) {
        (Array(elem_ty, 0), String(s)) => {
          let len = s.length()
          let arr_ty = Type::Array(elem_ty, len + 1) // +1 for null terminator
          stmts.push(VarDecl(arr_ty, decl.name, None))
          for i = 0; i < len; i = i + 1 {
            let ch = s[i]
            stmts.push(
              ExprStmt(
                Assign(
                  ArrayAccess(Var(decl.name), Number(i.to_int64())),
                  Number(ch.to_int().to_int64()),
                ),
              ),
            )
          }
          // Null terminator
          stmts.push(
            ExprStmt(
              Assign(
                ArrayAccess(Var(decl.name), Number(len.to_int64())),
                Number(0),
              ),
            ),
          )
          arr_ty
        }
        _ => {
          stmts.push(VarDecl(decl_ty, decl.name, Some(expr)))
          decl_ty
        }
      }
    }
  } else {
    stmts.push(VarDecl(decl_ty, decl.name, None))
    decl_ty
  }
  self.remember_value_type(decl.name, ty)
  // Parse additional variables: int a, *b, c[8], (*fp)(void);
  while self.token == Comma {
    self.advance()
    let extra_decl = self.parse_declarator(spec.base_type)
    let extra_post_decl_attrs = self.skip_attributes_info()
    let extra_decl_ty = self.apply_decl_attrs(
      apply_decl_align(resolve_var_type(extra_decl), spec.align),
      extra_post_decl_attrs,
    )
    let mut remembered_extra_ty = extra_decl_ty
    if self.token == Assign {
      self.advance()
      if self.token == LBrace {
        match local_init_core_type(extra_decl_ty) {
          Struct(_) | Union(_) => {
            stmts.push(VarDecl(extra_decl_ty, extra_decl.name, Some(Number(0))))
            let init_exprs = self.parse_brace_init_exprs()
            self.push_struct_init_assignments(
              stmts,
              Var(extra_decl.name),
              extra_decl_ty,
              init_exprs,
            )
          }
          Array(_, _) => {
            let init_exprs = self.parse_brace_init_exprs()
            let init_count = initializer_element_count(init_exprs)
            let extra_ty = local_init_infer_array_size(
              extra_decl_ty, init_count,
            )
            remembered_extra_ty = extra_ty
            stmts.push(VarDecl(extra_ty, extra_decl.name, Some(Number(0))))
            self.push_array_init_assignments(
              stmts,
              extra_decl.name,
              extra_ty,
              init_exprs,
            )
          }
          _ => {
            let init_exprs = self.parse_brace_init_exprs()
            stmts.push(
              VarDecl(
                extra_decl_ty,
                extra_decl.name,
                Some(local_init_scalar_brace_expr(init_exprs)),
              ),
            )
          }
        }
      } else {
        let expr = self.parse_assign()
        match (extra_decl_ty, expr) {
          (Array(elem_ty, 0), String(s)) => {
            let len = s.length()
            let arr_ty = Type::Array(elem_ty, len + 1)
            remembered_extra_ty = arr_ty
            stmts.push(VarDecl(arr_ty, extra_decl.name, None))
            for i = 0; i < len; i = i + 1 {
              let ch = s[i]
              stmts.push(
                ExprStmt(
                  Assign(
                    ArrayAccess(Var(extra_decl.name), Number(i.to_int64())),
                    Number(ch.to_int().to_int64()),
                  ),
                ),
              )
            }
            stmts.push(
              ExprStmt(
                Assign(
                  ArrayAccess(Var(extra_decl.name), Number(len.to_int64())),
                  Number(0),
                ),
              ),
            )
          }
          _ => stmts.push(VarDecl(extra_decl_ty, extra_decl.name, Some(expr)))
        }
      }
    } else {
      stmts.push(VarDecl(extra_decl_ty, extra_decl.name, None))
    }
    self.remember_value_type(extra_decl.name, remembered_extra_ty)
  }
  self.expect(Semicolon)
  if stmts.length() == 1 {
    stmts[0]
  } else {
    StmtList(stmts)
  }
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
fn Parser::parse_expr_stmt(self : Parser) -> Stmt {
  let expr = self.parse_expr()
  self.expect(Semicolon)
  ExprStmt(expr)
}
