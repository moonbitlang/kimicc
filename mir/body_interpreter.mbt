///|
priv enum BodyFlow {
  BodyNormal
  BodyReturned(Int64)
}

///|
priv struct BodyFrame {
  locals : Map[Int, Int64]
}

///|
priv struct BodyInterpreter {
  program : Program
  mut error : String?
  mut steps : Int
  mut call_depth : Int
}

///|
fn BodyInterpreter::new(program : Program) -> BodyInterpreter {
  { program, error: None, steps: 0, call_depth: 0 }
}

///|
fn BodyInterpreter::fail(self : BodyInterpreter, message : String) -> Unit {
  if self.error is None {
    self.error = Some(message)
  }
}

///|
fn BodyInterpreter::failed(self : BodyInterpreter) -> Bool {
  self.error is Some(_)
}

///|
fn BodyInterpreter::tick(self : BodyInterpreter) -> Bool {
  self.steps += 1
  if self.steps > 100000 {
    self.fail("MIR body interpreter step limit exceeded")
    false
  } else {
    true
  }
}

///|
fn BodyInterpreter::eval_binary_values(
  self : BodyInterpreter,
  op : String,
  left : Int64,
  left_ty : @parser.Type,
  right : Int64,
  right_ty : @parser.Type,
) -> Int64 {
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
      self.fail("unsupported MIR body binary operator: " + op)
      0L
    }
  }
}

///|
fn BodyInterpreter::eval_value(
  self : BodyInterpreter,
  frame : BodyFrame,
  value : MirValue,
) -> Int64 {
  if !self.tick() || self.failed() {
    return 0L
  }
  match value {
    MirConst(bits, ty) => self.program.runtime_cast_int(bits, ty)
    MirLocal(binding) =>
      if frame.locals.contains(binding.id) {
        self.program.runtime_cast_int(frame.locals[binding.id], binding.ty)
      } else {
        self.fail("unknown MIR body local value: " + binding.name)
        0L
      }
    MirUnary(op, inner, ty) => {
      let value = self.eval_value(frame, inner)
      match op {
        "+" => self.program.runtime_cast_int(value, ty)
        "-" => self.program.runtime_cast_int(-value, ty)
        "!" => if value == 0L { 1L } else { 0L }
        "~" => self.program.runtime_cast_int(value.lnot(), ty)
        _ => {
          self.fail("unsupported MIR body unary operator: " + op)
          0L
        }
      }
    }
    MirBinary(op, lhs, rhs, ty) =>
      match op {
        "&&" => {
          let left = self.eval_value(frame, lhs)
          if left == 0L {
            0L
          } else {
            let right = self.eval_value(frame, rhs)
            if right == 0L {
              0L
            } else {
              1L
            }
          }
        }
        "||" => {
          let left = self.eval_value(frame, lhs)
          if left != 0L {
            1L
          } else {
            let right = self.eval_value(frame, rhs)
            if right == 0L {
              0L
            } else {
              1L
            }
          }
        }
        "," => {
          ignore(self.eval_value(frame, lhs))
          self.program.runtime_cast_int(self.eval_value(frame, rhs), ty)
        }
        _ => {
          let left = self.eval_value(frame, lhs)
          let right = self.eval_value(frame, rhs)
          self.program.runtime_cast_int(
            self.eval_binary_values(op, left, lhs.ty(), right, rhs.ty()),
            ty,
          )
        }
      }
    MirCast(ty, inner) =>
      self.program.runtime_cast_int(self.eval_value(frame, inner), ty)
    MirCall(name, args, ty) => {
      let values : Array[Int64] = []
      for arg in args {
        values.push(self.eval_value(frame, arg))
      }
      self.program.runtime_cast_int(self.call_func(name, values), ty)
    }
    MirAssignLocal(binding, rhs) => {
      let assigned = self.program.runtime_cast_int(
        self.eval_value(frame, rhs),
        binding.ty,
      )
      frame.locals[binding.id] = assigned
      assigned
    }
    MirTernary(cond, then_, else_, ty) => {
      let selected = if self.eval_value(frame, cond) != 0L {
        self.eval_value(frame, then_)
      } else {
        self.eval_value(frame, else_)
      }
      self.program.runtime_cast_int(selected, ty)
    }
  }
}

///|
fn BodyInterpreter::exec_stmt(
  self : BodyInterpreter,
  frame : BodyFrame,
  stmt : MirStmt,
) -> BodyFlow {
  if !self.tick() || self.failed() {
    return BodyNormal
  }
  match stmt {
    MirDeclare(binding, init) => {
      let value = match init {
        Some(expr) => self.eval_value(frame, expr)
        None => 0L
      }
      frame.locals[binding.id] = self.program.runtime_cast_int(
        value,
        binding.ty,
      )
      BodyNormal
    }
    MirExprStmt(value) => {
      ignore(self.eval_value(frame, value))
      BodyNormal
    }
    MirReturn(value) => {
      let result = match value {
        Some(expr) => self.eval_value(frame, expr)
        None => 0L
      }
      BodyReturned(result)
    }
    MirIf(cond, then_, else_) =>
      if self.eval_value(frame, cond) != 0L {
        self.exec_stmts(frame, then_)
      } else {
        self.exec_stmts(frame, else_)
      }
    MirWhile(cond, body) => {
      while self.eval_value(frame, cond) != 0L && !self.failed() {
        match self.exec_stmts(frame, body) {
          BodyNormal => ()
          BodyReturned(value) => return BodyReturned(value)
        }
      }
      BodyNormal
    }
    MirBlock(stmts) => self.exec_stmts(frame, stmts)
  }
}

///|
fn BodyInterpreter::exec_stmts(
  self : BodyInterpreter,
  frame : BodyFrame,
  stmts : Array[MirStmt],
) -> BodyFlow {
  for stmt in stmts {
    match self.exec_stmt(frame, stmt) {
      BodyNormal => ()
      BodyReturned(value) => return BodyReturned(value)
    }
    if self.failed() {
      return BodyNormal
    }
  }
  BodyNormal
}

///|
fn BodyInterpreter::call_func(
  self : BodyInterpreter,
  name : String,
  args : Array[Int64],
) -> Int64 {
  if self.failed() {
    return 0L
  }
  if self.call_depth > 256 {
    self.fail("MIR body interpreter call depth exceeded")
    return 0L
  }
  if !self.program.bodies.contains(name) {
    self.fail("function has no MIR body: " + name)
    return 0L
  }
  let body = self.program.bodies[name]
  if args.length() != body.params.length() {
    self.fail("MIR body argument count mismatch for " + name)
    return 0L
  }
  self.call_depth += 1
  let frame = { locals: {} }
  for i in 0..<body.params.length() {
    let param = body.params[i]
    frame.locals[param.id] = self.program.runtime_cast_int(args[i], param.ty)
  }
  let result = match self.exec_stmts(frame, body.body) {
    BodyReturned(value) => self.program.runtime_cast_int(value, body.ret)
    BodyNormal => 0L
  }
  self.call_depth -= 1
  result
}

///|
/// Interpret a lowered MIR body without reading parser statements.
///
/// This is a compile-test oracle for the subset already represented by
/// `MirFuncBody`. Missing bodies report `Err`, which keeps unsupported parser
/// constructs out of the new layer until they are intentionally modeled.
pub fn Program::interpret_body_i64(
  self : Program,
  entry : String,
  args : Array[Int64],
) -> Result[Int64, String] {
  let interp = BodyInterpreter::new(self)
  let value = interp.call_func(entry, args)
  match interp.error {
    Some(message) => Err(message)
    None => Ok(value)
  }
}
