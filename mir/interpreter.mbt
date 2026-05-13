///|
/// Interpreter control flow for statement execution.
priv enum ExecFlow {
  Normal
  Returned(Int64)
  Broke
  Continued
}

///|
/// Integer-only execution frame used by the MIR compile-test interpreter.
priv struct InterpFrame {
  locals : Map[String, Int64]
  local_types : Map[String, @parser.Type]
  name : String
}

///|
fn InterpFrame::scope(self : InterpFrame) -> Scope {
  { locals: self.local_types, current_func: self.name }
}

///|
priv struct Interpreter {
  program : Program
  globals : Map[String, Int64]
  mut error : String?
  mut steps : Int
  mut call_depth : Int
}

///|
fn Program::runtime_int_type(self : Program, ty : @parser.Type) -> Bool {
  match self.core_type(ty) {
    Pointer(_) | FuncPtr(_, _, _) => true
    core => const_type_int_width(core) is Some(_)
  }
}

///|
fn Program::runtime_cast_int(
  self : Program,
  value : Int64,
  ty : @parser.Type,
) -> Int64 {
  self.const_cast_int(self.const_int(value, ty), ty).bits
}

///|
fn Program::find_func_decl(self : Program, name : String) -> @parser.FuncDecl? {
  for decl in self.source.decls {
    if decl.name == name && decl.body is Some(_) {
      return Some(decl)
    }
  }
  None
}

///|
fn Interpreter::new(program : Program) -> Interpreter {
  let self = { program, globals: {}, error: None, steps: 0, call_depth: 0 }
  self.init_globals()
  self
}

///|
fn Interpreter::fail(self : Interpreter, message : String) -> Unit {
  if self.error is None {
    self.error = Some(message)
  }
}

///|
fn Interpreter::failed(self : Interpreter) -> Bool {
  self.error is Some(_)
}

///|
fn Interpreter::tick(self : Interpreter) -> Bool {
  self.steps += 1
  if self.steps > 100000 {
    self.fail("MIR interpreter step limit exceeded")
    false
  } else {
    true
  }
}

///|
fn Interpreter::init_globals(self : Interpreter) -> Unit {
  let seen : Map[String, Bool] = {}
  for original in self.program.source.globals {
    if self.program.globals.contains(original.name) &&
      !seen.contains(original.name) {
      seen[original.name] = true
      let decl = self.program.globals[original.name]
      let value = match decl.init {
        None => 0L
        Some(Scalar(expr)) =>
          match self.program.fold_const(expr, Scope::empty()) {
            Some(value) => value
            None => {
              self.fail(
                "unsupported non-constant global initializer: " + decl.name,
              )
              0L
            }
          }
        Some(Array(_)) => {
          self.fail("unsupported aggregate global initializer: " + decl.name)
          0L
        }
      }
      if self.program.runtime_int_type(decl.ty) {
        self.globals[decl.name] = self.program.runtime_cast_int(value, decl.ty)
      } else {
        self.fail("unsupported global type for MIR interpreter: " + decl.name)
      }
    }
  }
}

///|
fn Interpreter::var_type(
  self : Interpreter,
  frame : InterpFrame,
  name : String,
) -> @parser.Type? {
  if frame.local_types.contains(name) {
    Some(frame.local_types[name])
  } else if self.program.globals.contains(name) {
    Some(self.program.globals[name].ty)
  } else {
    None
  }
}

///|
fn Interpreter::read_var(
  self : Interpreter,
  frame : InterpFrame,
  name : String,
) -> Int64 {
  if frame.locals.contains(name) {
    frame.locals[name]
  } else if self.globals.contains(name) {
    self.globals[name]
  } else {
    self.fail("unknown variable in MIR interpreter: " + name)
    0L
  }
}

///|
fn Interpreter::write_var(
  self : Interpreter,
  frame : InterpFrame,
  name : String,
  value : Int64,
) -> Int64 {
  match self.var_type(frame, name) {
    Some(ty) =>
      if self.program.runtime_int_type(ty) {
        let casted = self.program.runtime_cast_int(value, ty)
        if frame.local_types.contains(name) {
          frame.locals[name] = casted
        } else {
          self.globals[name] = casted
        }
        casted
      } else {
        self.fail("unsupported assignment type in MIR interpreter: " + name)
        0L
      }
    None => {
      self.fail("unknown assignment target in MIR interpreter: " + name)
      0L
    }
  }
}

///|
fn Interpreter::read_lvalue(
  self : Interpreter,
  frame : InterpFrame,
  expr : @parser.Expr,
) -> Int64 {
  match expr {
    Var(name) => self.read_var(frame, name)
    _ => {
      self.fail("unsupported MIR interpreter lvalue")
      0L
    }
  }
}

///|
fn Interpreter::write_lvalue(
  self : Interpreter,
  frame : InterpFrame,
  expr : @parser.Expr,
  value : Int64,
) -> Int64 {
  match expr {
    Var(name) => self.write_var(frame, name, value)
    _ => {
      self.fail("unsupported MIR interpreter assignment target")
      0L
    }
  }
}

///|
fn Interpreter::eval_pointer_binary(
  self : Interpreter,
  op : String,
  left : Int64,
  left_ty : @parser.Type,
  right : Int64,
  right_ty : @parser.Type,
) -> Int64? {
  match self.program.pointer_element(left_ty) {
    Some(elem) =>
      if right_ty.is_integer() {
        let scale = self.program.type_size(elem).to_int64()
        if op == "+" {
          return Some(left + right * scale)
        } else if op == "-" {
          return Some(left - right * scale)
        }
      }
    None => ()
  }
  match self.program.pointer_element(right_ty) {
    Some(elem) =>
      if op == "+" && left_ty.is_integer() {
        return Some(right + left * self.program.type_size(elem).to_int64())
      } else if op == "-" && self.program.pointer_element(left_ty) is Some(_) {
        let scale = self.program.type_size(elem).to_int64()
        if scale == 0L {
          return Some(0L)
        }
        return Some((left - right) / scale)
      }
    None => ()
  }
  None
}

///|
fn Interpreter::eval_binary_values(
  self : Interpreter,
  op : String,
  left : Int64,
  left_ty : @parser.Type,
  right : Int64,
  right_ty : @parser.Type,
) -> Int64 {
  match self.eval_pointer_binary(op, left, left_ty, right, right_ty) {
    Some(value) => return value
    None => ()
  }
  let left_value = self.program.const_cast_int(
    self.program.const_int(left, left_ty),
    left_ty,
  )
  let right_value = self.program.const_cast_int(
    self.program.const_int(right, right_ty),
    right_ty,
  )
  let result = match op {
    "+" => self.program.const_binary_arith("+", left_value, right_value)
    "-" => self.program.const_binary_arith("-", left_value, right_value)
    "*" => self.program.const_binary_arith("*", left_value, right_value)
    "/" => self.program.const_divide("/", left_value, right_value)
    "%" => self.program.const_divide("%", left_value, right_value)
    "|" => self.program.const_binary_arith("|", left_value, right_value)
    "&" => self.program.const_binary_arith("&", left_value, right_value)
    "^" => self.program.const_binary_arith("^", left_value, right_value)
    "<<" => self.program.const_shift("<<", left_value, right_value)
    ">>" => self.program.const_shift(">>", left_value, right_value)
    "==" =>
      Some(
        const_bool(self.program.const_equal_compare(left_value, right_value)),
      )
    "!=" =>
      Some(
        const_bool(!self.program.const_equal_compare(left_value, right_value)),
      )
    "<" =>
      Some(
        const_bool(self.program.const_rel_compare("<", left_value, right_value)),
      )
    ">" =>
      Some(
        const_bool(self.program.const_rel_compare(">", left_value, right_value)),
      )
    "<=" =>
      Some(
        const_bool(
          self.program.const_rel_compare("<=", left_value, right_value),
        ),
      )
    ">=" =>
      Some(
        const_bool(
          self.program.const_rel_compare(">=", left_value, right_value),
        ),
      )
    _ => None
  }
  match result {
    Some(value) => value.bits
    None => {
      self.fail("unsupported MIR interpreter binary operator: " + op)
      0L
    }
  }
}

///|
fn Interpreter::eval_expr(
  self : Interpreter,
  frame : InterpFrame,
  expr : @parser.Expr,
) -> Int64 {
  if self.failed() || !self.tick() {
    return 0L
  }
  let scope = frame.scope()
  match expr {
    Number(value) => value
    FloatLiteral(_) => {
      self.fail("unsupported MIR interpreter floating expression")
      0L
    }
    String(_) => {
      self.fail("unsupported MIR interpreter string expression")
      0L
    }
    Var(name) => self.read_var(frame, name)
    Binary("&&", lhs, rhs) =>
      if self.eval_expr(frame, lhs) == 0L {
        0L
      } else if self.eval_expr(frame, rhs) == 0L {
        0L
      } else {
        1L
      }
    Binary("||", lhs, rhs) =>
      if self.eval_expr(frame, lhs) != 0L {
        1L
      } else if self.eval_expr(frame, rhs) != 0L {
        1L
      } else {
        0L
      }
    Binary(",", lhs, rhs) => {
      ignore(self.eval_expr(frame, lhs))
      self.eval_expr(frame, rhs)
    }
    Binary(op, lhs, rhs) => {
      let left = self.eval_expr(frame, lhs)
      let right = self.eval_expr(frame, rhs)
      self.eval_binary_values(
        op,
        left,
        self.program.expr_type(lhs, scope),
        right,
        self.program.expr_type(rhs, scope),
      )
    }
    Unary("-", operand) => {
      let ty = self.program.expr_type(operand, scope)
      let value = -self.eval_expr(frame, operand)
      self.program.runtime_cast_int(
        value,
        self.program.unary_numeric_result_type(ty),
      )
    }
    Unary("+", operand) => {
      let ty = self.program.expr_type(operand, scope)
      self.program.runtime_cast_int(
        self.eval_expr(frame, operand),
        self.program.unary_numeric_result_type(ty),
      )
    }
    Unary("~", operand) => {
      let ty = unary_integer_result_type(self.program.expr_type(operand, scope))
      self.program.runtime_cast_int(self.eval_expr(frame, operand).lnot(), ty)
    }
    Unary("!", operand) =>
      if self.eval_expr(frame, operand) == 0L {
        1L
      } else {
        0L
      }
    Unary(op, _) => {
      self.fail("unsupported MIR interpreter unary operator: " + op)
      0L
    }
    Call(func, args) => {
      let values : Array[Int64] = []
      for arg in args {
        values.push(self.eval_expr(frame, arg))
      }
      match func {
        Var("__builtin_expect") =>
          if values.length() > 0 {
            values[0]
          } else {
            0L
          }
        Var(name) => self.call_func(name, values)
        _ => {
          self.fail("unsupported MIR interpreter indirect call")
          0L
        }
      }
    }
    Assign(lhs, rhs) => {
      let value = self.eval_expr(frame, rhs)
      self.write_lvalue(frame, lhs, value)
    }
    CompoundAssign(op, lhs, rhs) => {
      let old = self.read_lvalue(frame, lhs)
      let right = self.eval_expr(frame, rhs)
      let value = self.eval_binary_values(
        op,
        old,
        self.program.expr_type(lhs, scope),
        right,
        self.program.expr_type(rhs, scope),
      )
      self.write_lvalue(frame, lhs, value)
    }
    MemberAccess(_, _) | Deref(_) | AddrOf(_) | ArrayAccess(_, _) => {
      self.fail("unsupported MIR interpreter memory expression")
      0L
    }
    Sizeof(ty) => self.program.type_size(ty).to_int64()
    SizeofExpr(e) =>
      self.program.type_size(self.program.expr_type(e, scope)).to_int64()
    Alignof(ty) => self.program.type_align(ty).to_int64()
    AlignofExpr(e) =>
      self.program.type_align(self.program.expr_type(e, scope)).to_int64()
    Cast(ty, value) =>
      if self.program.runtime_int_type(ty) {
        self.program.runtime_cast_int(self.eval_expr(frame, value), ty)
      } else {
        self.fail("unsupported MIR interpreter cast target")
        0L
      }
    PrefixInc(e) => {
      let value = self.read_lvalue(frame, e) + 1L
      self.write_lvalue(frame, e, value)
    }
    PrefixDec(e) => {
      let value = self.read_lvalue(frame, e) - 1L
      self.write_lvalue(frame, e, value)
    }
    PostfixInc(e) => {
      let old = self.read_lvalue(frame, e)
      ignore(self.write_lvalue(frame, e, old + 1L))
      old
    }
    PostfixDec(e) => {
      let old = self.read_lvalue(frame, e)
      ignore(self.write_lvalue(frame, e, old - 1L))
      old
    }
    Ternary(cond, then_, else_) =>
      if self.eval_expr(frame, cond) != 0L {
        self.eval_expr(frame, then_)
      } else {
        self.eval_expr(frame, else_)
      }
    LabelAddr(_) | VaArg(_, _) => {
      self.fail("unsupported MIR interpreter control/runtime expression")
      0L
    }
    OffsetOf(ty, path) =>
      match self.program.offset_of_path(ty, path) {
        Some(offset) => offset.to_int64()
        None => {
          self.fail("unsupported MIR interpreter offsetof path")
          0L
        }
      }
    Array(_) | CompoundLiteral(_, _, _) => {
      self.fail("unsupported MIR interpreter aggregate expression")
      0L
    }
    DesignatedField(_, e) | DesignatedIndex(_, e) | DesignatedRange(_, _, e) =>
      self.eval_expr(frame, e)
  }
}

///|
fn Interpreter::declare_local(
  self : Interpreter,
  frame : InterpFrame,
  ty : @parser.Type,
  name : String,
  init : @parser.Expr?,
) -> Unit {
  if !self.program.runtime_int_type(ty) {
    self.fail("unsupported MIR interpreter local type: " + name)
    return
  }
  let value = match init {
    Some(expr) => self.eval_expr(frame, expr)
    None => 0L
  }
  frame.local_types[name] = ty
  frame.locals[name] = self.program.runtime_cast_int(value, ty)
}

///|
fn Interpreter::exec_block(
  self : Interpreter,
  frame : InterpFrame,
  stmts : Array[@parser.Stmt],
) -> ExecFlow {
  for stmt in stmts {
    match self.exec_stmt(frame, stmt) {
      Normal => ()
      flow => return flow
    }
  }
  Normal
}

///|
fn Interpreter::exec_while(
  self : Interpreter,
  frame : InterpFrame,
  cond : @parser.Expr,
  body : @parser.Stmt,
) -> ExecFlow {
  while !self.failed() && self.eval_expr(frame, cond) != 0L {
    match self.exec_stmt(frame, body) {
      Normal | Continued => ()
      Broke => return Normal
      Returned(value) => return Returned(value)
    }
  }
  Normal
}

///|
fn Interpreter::exec_do_while(
  self : Interpreter,
  frame : InterpFrame,
  cond : @parser.Expr,
  body : @parser.Stmt,
) -> ExecFlow {
  while !self.failed() {
    match self.exec_stmt(frame, body) {
      Normal | Continued => ()
      Broke => return Normal
      Returned(value) => return Returned(value)
    }
    if self.eval_expr(frame, cond) == 0L {
      return Normal
    }
  }
  Normal
}

///|
fn Interpreter::exec_for(
  self : Interpreter,
  frame : InterpFrame,
  init : @parser.Stmt?,
  cond : @parser.Expr,
  inc : @parser.Expr?,
  body : @parser.Stmt,
) -> ExecFlow {
  match init {
    Some(stmt) =>
      match self.exec_stmt(frame, stmt) {
        Normal => ()
        flow => return flow
      }
    None => ()
  }
  while !self.failed() && self.eval_expr(frame, cond) != 0L {
    match self.exec_stmt(frame, body) {
      Normal | Continued => ()
      Broke => return Normal
      Returned(value) => return Returned(value)
    }
    match inc {
      Some(expr) => ignore(self.eval_expr(frame, expr))
      None => ()
    }
  }
  Normal
}

///|
fn Interpreter::exec_stmt(
  self : Interpreter,
  frame : InterpFrame,
  stmt : @parser.Stmt,
) -> ExecFlow {
  if self.failed() || !self.tick() {
    return Normal
  }
  match stmt {
    ExprStmt(expr) => {
      ignore(self.eval_expr(frame, expr))
      Normal
    }
    Return(expr) =>
      match expr {
        Some(value) => Returned(self.eval_expr(frame, value))
        None => Returned(0L)
      }
    If(cond, then_, else_) =>
      if self.eval_expr(frame, cond) != 0L {
        self.exec_stmt(frame, then_)
      } else {
        match else_ {
          Some(stmt) => self.exec_stmt(frame, stmt)
          None => Normal
        }
      }
    While(cond, body) => self.exec_while(frame, cond, body)
    Compound(stmts) | StmtList(stmts) => self.exec_block(frame, stmts)
    VarDecl(ty, name, init) => {
      self.declare_local(frame, ty, name, init)
      Normal
    }
    Break => Broke
    Continue => Continued
    Switch(_, _, _) | Goto(_) | ComputedGoto(_) => {
      self.fail("unsupported MIR interpreter control statement")
      Normal
    }
    Label(_, body) => self.exec_stmt(frame, body)
    For(init, cond, inc, body) => self.exec_for(frame, init, cond, inc, body)
    DoWhile(cond, body) => self.exec_do_while(frame, cond, body)
  }
}

///|
fn Interpreter::call_func(
  self : Interpreter,
  name : String,
  args : Array[Int64],
) -> Int64 {
  if self.failed() {
    return 0L
  }
  self.call_depth += 1
  if self.call_depth > 128 {
    self.fail("MIR interpreter call depth exceeded")
    self.call_depth -= 1
    return 0L
  }
  let result = match self.program.find_func_decl(name) {
    None => {
      self.fail("undefined function in MIR interpreter: " + name)
      0L
    }
    Some(decl) =>
      match decl.body {
        None => {
          self.fail("function has no body in MIR interpreter: " + name)
          0L
        }
        Some(body) => {
          let frame = { locals: {}, local_types: {}, name }
          for i in 0..<decl.params.length() {
            let param = decl.params[i]
            if param.name != "" {
              frame.local_types[param.name] = param.ty
              let value = if i < args.length() { args[i] } else { 0L }
              frame.locals[param.name] = self.program.runtime_cast_int(
                value,
                param.ty,
              )
            }
          }
          match self.exec_stmt(frame, body) {
            Returned(value) => self.program.runtime_cast_int(value, decl.ret)
            Normal => 0L
            Broke | Continued => {
              self.fail("break or continue escaped function in MIR interpreter")
              0L
            }
          }
        }
      }
  }
  self.call_depth -= 1
  result
}

///|
/// Interpret an integer-returning function from this lowered MIR program.
///
/// This is intended as a compile-test oracle for scalar C snippets. It is
/// deliberately conservative and returns `Err` for memory, aggregate, indirect
/// call, goto, switch, varargs, and floating-point behavior that is not modeled
/// yet.
pub fn Program::interpret_i64(
  self : Program,
  entry : String,
  args : Array[Int64],
) -> Result[Int64, String] {
  let interp = Interpreter::new(self)
  let value = interp.call_func(entry, args)
  match interp.error {
    Some(message) => Err(message)
    None => Ok(value)
  }
}

///|
/// Lower and interpret an integer-returning function in one step.
pub fn interpret_i64(
  source : @parser.Program,
  target : @target.Target,
  entry : String,
  args : Array[Int64],
) -> Result[Int64, String] {
  lower(source, target).interpret_i64(entry, args)
}
