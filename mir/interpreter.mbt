///|
/// Interpreter control flow for statement execution.
priv enum ExecFlow {
  Normal
  Returned(Int64)
  Broke
  Continued
  Jump(String)
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
  string_bases : Map[String, Int64]
  string_values : Map[Int64, String]
  string_offsets : Map[Int64, Int64]
  mut error : String?
  mut steps : Int
  mut call_depth : Int
  mut next_alloca : Int64
  mut next_string_base : Int64
}

///|
fn Program::switch_control_type(
  self : Program,
  ty : @parser.Type,
) -> @parser.Type {
  match ty {
    Atomic(inner) | Aligned(inner, _) => self.switch_control_type(inner)
    Bool | SChar | UChar | SShort | UShort => SInt
    _ => ty
  }
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
  let self = {
    program,
    globals: {},
    string_bases: {},
    string_values: {},
    string_offsets: {},
    error: None,
    steps: 0,
    call_depth: 0,
    next_alloca: 4096L,
    next_string_base: 1048576L,
  }
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
fn Interpreter::global_pointer_offset(
  self : Interpreter,
  base : @parser.Expr,
  offset : @parser.Expr,
) -> Int64? {
  match self.program.fold_const(offset, Scope::empty()) {
    Some(value) =>
      match
        self.program.pointer_element(
          self.program.expr_type(base, Scope::empty()),
        ) {
        Some(elem) => Some(value * self.program.type_size(elem).to_int64())
        None => Some(value)
      }
    None => None
  }
}

///|
fn Interpreter::global_string_pointer_initializer(
  self : Interpreter,
  expr : @parser.Expr,
) -> LiteralStringPointer? {
  match expr {
    String(value) =>
      Some({ value, base: self.string_literal_base(value), offset: 0L })
    Cast(_, inner) => self.global_string_pointer_initializer(inner)
    Var(name) =>
      if self.globals.contains(name) {
        self.string_literal_pointer_at(self.globals[name])
      } else {
        None
      }
    Binary("+", lhs, rhs) =>
      match self.global_string_pointer_initializer(lhs) {
        Some(ptr) =>
          match self.global_pointer_offset(lhs, rhs) {
            Some(offset) =>
              Some({
                value: ptr.value,
                base: ptr.base,
                offset: ptr.offset + offset,
              })
            None => None
          }
        None =>
          match self.global_string_pointer_initializer(rhs) {
            Some(ptr) =>
              match self.global_pointer_offset(rhs, lhs) {
                Some(offset) =>
                  Some({
                    value: ptr.value,
                    base: ptr.base,
                    offset: ptr.offset + offset,
                  })
                None => None
              }
            None => None
          }
      }
    Binary("-", lhs, rhs) =>
      match self.global_string_pointer_initializer(lhs) {
        Some(ptr) =>
          match self.global_pointer_offset(lhs, rhs) {
            Some(offset) =>
              Some({
                value: ptr.value,
                base: ptr.base,
                offset: ptr.offset - offset,
              })
            None => None
          }
        None => None
      }
    _ => None
  }
}

///|
fn Interpreter::eval_global_scalar_initializer(
  self : Interpreter,
  name : String,
  ty : @parser.Type,
  expr : @parser.Expr,
) -> Int64 {
  match self.program.fold_const(expr, Scope::empty()) {
    Some(value) => value
    None =>
      match self.program.pointer_element(ty) {
        Some(_) =>
          match self.global_string_pointer_initializer(expr) {
            Some(ptr) => ptr.base + ptr.offset
            None => {
              self.fail("unsupported non-constant global initializer: " + name)
              0L
            }
          }
        None => {
          self.fail("unsupported non-constant global initializer: " + name)
          0L
        }
      }
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
      if !self.program.runtime_int_type(decl.ty) {
        // Non-runtime globals still provide type facts through Program::globals.
        continue
      }
      let value = match decl.init {
        None => 0L
        Some(Scalar(expr)) =>
          self.eval_global_scalar_initializer(decl.name, decl.ty, expr)
        Some(Array(_)) => {
          self.fail("unsupported aggregate global initializer: " + decl.name)
          0L
        }
      }
      self.globals[decl.name] = self.program.runtime_cast_int(value, decl.ty)
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
  } else if frame.local_types.contains(name) {
    self.fail("unsupported MIR interpreter local value: " + name)
    0L
  } else if self.globals.contains(name) {
    self.globals[name]
  } else if self.program.globals.contains(name) {
    self.fail("unsupported MIR interpreter global value: " + name)
    0L
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
    Deref(AddrOf(target)) => self.read_lvalue(frame, target)
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
    Deref(AddrOf(target)) => self.write_lvalue(frame, target, value)
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
fn Interpreter::eval_call_args(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
) -> Array[Int64] {
  let values : Array[Int64] = []
  for arg in args {
    values.push(self.eval_expr(frame, arg))
  }
  values
}

///|
fn Interpreter::eval_first_call_arg_or_zero(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
) -> Int64 {
  if args.length() > 0 {
    self.eval_expr(frame, args[0])
  } else {
    0L
  }
}

///|
fn Interpreter::eval_return_first_call_arg(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
  count : Int,
) -> Int64 {
  let limit = if args.length() < count { args.length() } else { count }
  let mut result = 0L
  for i in 0..<limit {
    let value = self.eval_expr(frame, args[i])
    if i == 0 {
      result = value
    }
  }
  result
}

///|
fn interpreter_can_write_lvalue(expr : @parser.Expr) -> Bool {
  match expr {
    Var(_) => true
    Deref(AddrOf(target)) => interpreter_can_write_lvalue(target)
    _ => false
  }
}

///|
fn Interpreter::eval_ignored_expr_side_effects(
  self : Interpreter,
  frame : InterpFrame,
  expr : @parser.Expr,
) -> Unit {
  match expr {
    Assign(lhs, rhs) =>
      if interpreter_can_write_lvalue(lhs) {
        ignore(self.eval_expr(frame, expr))
      } else {
        self.eval_ignored_expr_side_effects(frame, lhs)
        self.eval_ignored_expr_side_effects(frame, rhs)
      }
    CompoundAssign(_, lhs, rhs) =>
      if interpreter_can_write_lvalue(lhs) {
        ignore(self.eval_expr(frame, expr))
      } else {
        self.eval_ignored_expr_side_effects(frame, lhs)
        self.eval_ignored_expr_side_effects(frame, rhs)
      }
    PrefixInc(target)
    | PrefixDec(target)
    | PostfixInc(target)
    | PostfixDec(target) =>
      if interpreter_can_write_lvalue(target) {
        ignore(self.eval_expr(frame, expr))
      } else {
        self.eval_ignored_expr_side_effects(frame, target)
      }
    Call(_, _) => ignore(self.eval_expr(frame, expr))
    Binary("&&", lhs, rhs) =>
      if self.eval_expr(frame, lhs) != 0L {
        self.eval_ignored_expr_side_effects(frame, rhs)
      }
    Binary("||", lhs, rhs) =>
      if self.eval_expr(frame, lhs) == 0L {
        self.eval_ignored_expr_side_effects(frame, rhs)
      }
    Binary(_, lhs, rhs) => {
      self.eval_ignored_expr_side_effects(frame, lhs)
      self.eval_ignored_expr_side_effects(frame, rhs)
    }
    Unary(_, operand) | Cast(_, operand) | Deref(operand) | AddrOf(operand) =>
      self.eval_ignored_expr_side_effects(frame, operand)
    MemberAccess(obj, _) => self.eval_ignored_expr_side_effects(frame, obj)
    ArrayAccess(base, index) => {
      self.eval_ignored_expr_side_effects(frame, base)
      self.eval_ignored_expr_side_effects(frame, index)
    }
    Ternary(cond, then_, else_) =>
      if self.eval_expr(frame, cond) != 0L {
        self.eval_ignored_expr_side_effects(frame, then_)
      } else {
        self.eval_ignored_expr_side_effects(frame, else_)
      }
    CompoundLiteral(_, init_exprs, _) | Array(init_exprs) =>
      for init_expr in init_exprs {
        self.eval_ignored_expr_side_effects(frame, init_expr)
      }
    DesignatedField(_, value)
    | DesignatedIndex(_, value)
    | DesignatedRange(_, _, value) =>
      self.eval_ignored_expr_side_effects(frame, value)
    _ => ()
  }
}

///|
fn Interpreter::eval_builtin_object_size(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
) -> Int64 {
  let mode = if args.length() > 1 {
    match self.program.fold_const(args[1], frame.scope()) {
      Some(value) => value
      None => {
        self.fail("unsupported MIR interpreter object_size type argument")
        0L
      }
    }
  } else {
    0L
  }
  if args.length() == 0 {
    return unknown_object_size(mode)
  }
  self.program.object_size_value(args[0], frame.scope(), mode)
}

///|
fn Interpreter::eval_builtin_fp_compare(
  self : Interpreter,
  frame : InterpFrame,
  name : String,
  args : Array[@parser.Expr],
) -> Int64 {
  if args.length() < 2 {
    return 0L
  }
  let left = match self.program.fold_float_const(args[0], frame.scope()) {
    Some(value) => value
    None => {
      self.fail("unsupported MIR interpreter " + name + " argument")
      return 0L
    }
  }
  let right = match self.program.fold_float_const(args[1], frame.scope()) {
    Some(value) => value
    None => {
      self.fail("unsupported MIR interpreter " + name + " argument")
      return 0L
    }
  }
  let unordered = left != left || right != right
  let result = match name {
    "__builtin_isgreater" => !unordered && left > right
    "__builtin_isgreaterequal" => !unordered && left >= right
    "__builtin_isless" => !unordered && left < right
    "__builtin_islessequal" => !unordered && left <= right
    "__builtin_islessgreater" => !unordered && left != right
    "__builtin_isunordered" => unordered
    _ => false
  }
  if result {
    1L
  } else {
    0L
  }
}

///|
fn fp_class_bool(value : Bool) -> Int64 {
  if value {
    1L
  } else {
    0L
  }
}

///|
fn fp_class_normal_min(name : String) -> Double {
  match name {
    "__builtin_isnormalf" => 1.1754943508222875e-38
    _ => 2.2250738585072014e-308
  }
}

///|
fn Interpreter::eval_builtin_fp_class(
  self : Interpreter,
  frame : InterpFrame,
  name : String,
  args : Array[@parser.Expr],
) -> Int64 {
  if args.length() == 0 {
    return 0L
  }
  let value = match self.program.fold_float_const(args[0], frame.scope()) {
    Some(value) => value
    None => {
      self.fail("unsupported MIR interpreter " + name + " argument")
      return 0L
    }
  }
  let nan = value != value
  let pos_inf = 1.0 / 0.0
  let neg_inf = -pos_inf
  let inf = !nan && (value == pos_inf || value == neg_inf)
  let finite = !nan && !inf
  let result = match name {
    "__builtin_isnan" | "__builtin_isnanf" | "__builtin_isnanl" => nan
    "__builtin_isinf" | "__builtin_isinff" | "__builtin_isinfl" => inf
    "__builtin_isfinite" | "__builtin_isfinitef" | "__builtin_isfinitel" =>
      finite
    "__builtin_isnormal" | "__builtin_isnormalf" | "__builtin_isnormall" =>
      finite && floating_abs(value) >= fp_class_normal_min(name)
    "__builtin_signbit" | "__builtin_signbitf" | "__builtin_signbitl" =>
      floating_signbit(value)
    _ => false
  }
  fp_class_bool(result)
}

///|
fn Interpreter::eval_builtin_abs(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
  ty : @parser.Type,
) -> Int64 {
  let value = self.program.runtime_cast_int(
    self.eval_first_call_arg_or_zero(frame, args),
    ty,
  )
  self.program.runtime_cast_int(if value < 0L { -value } else { value }, ty)
}

///|
fn Interpreter::eval_builtin_is_aligned(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
) -> Int64 {
  if args.length() < 2 {
    return 0L
  }
  let value = self.eval_expr(frame, args[0])
  let align = self.eval_expr(frame, args[1])
  if (value & (align - 1L)) == 0L {
    1L
  } else {
    0L
  }
}

///|
fn Interpreter::eval_builtin_align_value(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
  round_up : Bool,
) -> Int64 {
  if args.length() < 2 {
    return 0L
  }
  let value = self.eval_expr(frame, args[0])
  let align = self.eval_expr(frame, args[1])
  let adjusted = if round_up { value + align - 1L } else { value }
  adjusted & -align
}

///|
fn overflow_builtin_op(name : String) -> String? {
  match name {
    "__builtin_add_overflow"
    | "__builtin_sadd_overflow"
    | "__builtin_saddl_overflow"
    | "__builtin_saddll_overflow"
    | "__builtin_uadd_overflow"
    | "__builtin_uaddl_overflow"
    | "__builtin_uaddll_overflow" => Some("+")
    "__builtin_sub_overflow"
    | "__builtin_ssub_overflow"
    | "__builtin_ssubl_overflow"
    | "__builtin_ssubll_overflow"
    | "__builtin_usub_overflow"
    | "__builtin_usubl_overflow"
    | "__builtin_usubll_overflow" => Some("-")
    "__builtin_mul_overflow"
    | "__builtin_smul_overflow"
    | "__builtin_smull_overflow"
    | "__builtin_smulll_overflow"
    | "__builtin_umul_overflow"
    | "__builtin_umull_overflow"
    | "__builtin_umulll_overflow" => Some("*")
    _ => None
  }
}

///|
fn unsigned_overflow_arithmetic(
  op : String,
  left : Int64,
  right : Int64,
  width : Int,
) -> (Int64, Bool) {
  let x = left.reinterpret_as_uint64()
  let y = right.reinterpret_as_uint64()
  let result = match op {
    "+" => x + y
    "-" => x - y
    "*" => x * y
    _ => 0UL
  }
  let overflow = if width >= 64 {
    match op {
      "+" => result < x
      "-" => x < y
      "*" => x != 0UL && y > 18446744073709551615UL / x
      _ => false
    }
  } else {
    result > (1UL << width) - 1UL
  }
  (result.reinterpret_as_int64(), overflow)
}

///|
fn signed_overflow_arithmetic(
  op : String,
  left : Int64,
  right : Int64,
  width : Int,
) -> (Int64, Bool) {
  let result = match op {
    "+" => left + right
    "-" => left - right
    "*" => left * right
    _ => 0L
  }
  let overflow = if width >= 64 {
    let min_value = -9223372036854775807L - 1L
    match op {
      "+" => ((left ^ result) & (right ^ result)) < 0L
      "-" => ((left ^ right) & (left ^ result)) < 0L
      "*" =>
        if left == 0L || right == 0L {
          false
        } else if (left == min_value && right == -1L) ||
          (right == min_value && left == -1L) {
          true
        } else {
          result / right != left
        }
      _ => false
    }
  } else {
    let min_value = -(1L << (width - 1))
    let max_value = (1L << (width - 1)) - 1L
    result < min_value || result > max_value
  }
  (result, overflow)
}

///|
fn Program::overflow_arithmetic_result(
  self : Program,
  ty : @parser.Type,
  op : String,
  left : Int64,
  right : Int64,
) -> (Int64, Bool)? {
  let core = self.core_type(ty)
  match const_type_int_width(core) {
    Some(width) if width <= 64 =>
      Some(
        if const_type_is_unsigned(core) {
          unsigned_overflow_arithmetic(op, left, right, width)
        } else {
          signed_overflow_arithmetic(op, left, right, width)
        },
      )
    _ => None
  }
}

///|
fn Interpreter::eval_overflow_builtin(
  self : Interpreter,
  frame : InterpFrame,
  op : String,
  args : Array[@parser.Expr],
) -> Int64 {
  if args.length() < 3 {
    return 0L
  }
  let result_lvalue = match args[2] {
    AddrOf(target) => target
    _ => {
      self.fail("unsupported MIR interpreter overflow result pointer")
      return 0L
    }
  }
  let result_ty = match
    self.program.pointer_element(self.program.expr_type(args[2], frame.scope())) {
    Some(ty) => ty
    None => {
      self.fail("unsupported MIR interpreter overflow result type")
      return 0L
    }
  }
  let left = self.program.runtime_cast_int(
    self.eval_expr(frame, args[0]),
    result_ty,
  )
  let right = self.program.runtime_cast_int(
    self.eval_expr(frame, args[1]),
    result_ty,
  )
  match self.program.overflow_arithmetic_result(result_ty, op, left, right) {
    Some((result, overflow)) => {
      ignore(self.write_lvalue(frame, result_lvalue, result))
      if overflow {
        1L
      } else {
        0L
      }
    }
    None => {
      self.fail("unsupported MIR interpreter overflow result type")
      0L
    }
  }
}

///|
fn mask_int_width(value : Int64, width : Int) -> Int64 {
  if width >= 64 {
    value
  } else {
    value & ((1L << width) - 1L)
  }
}

///|
fn count_leading_zero_bits(value : Int64, width : Int) -> Int64 {
  let value = mask_int_width(value, width)
  for i in 0..<width {
    let shift = width - 1 - i
    if ((value >> shift) & 1L) != 0L {
      return i.to_int64()
    }
  }
  width.to_int64()
}

///|
fn count_trailing_zero_bits(value : Int64, width : Int) -> Int64 {
  let value = mask_int_width(value, width)
  for i in 0..<width {
    if ((value >> i) & 1L) != 0L {
      return i.to_int64()
    }
  }
  width.to_int64()
}

///|
fn first_set_bit(value : Int64, width : Int) -> Int64 {
  let value = mask_int_width(value, width)
  if value == 0L {
    0L
  } else {
    count_trailing_zero_bits(value, width) + 1L
  }
}

///|
fn count_one_bits(value : Int64, width : Int) -> Int64 {
  let mut value = mask_int_width(value, width)
  let mut count = 0L
  for _ in 0..<width {
    count += value & 1L
    value = value >> 1
  }
  count
}

///|
fn byte_swap_bits(value : Int64, width : Int) -> Int64 {
  let value = mask_int_width(value, width)
  let mut result = 0L
  for i in 0..<(width / 8) {
    result = (result << 8) | ((value >> (i * 8)) & 0xFFL)
  }
  result
}

///|
fn Program::generic_builtin_bswap_width(
  self : Program,
  frame : InterpFrame,
  args : Array[@parser.Expr],
) -> Int {
  if args.length() == 0 {
    return 32
  }
  let ty = self.core_type(self.expr_type(args[0], frame.scope()))
  let width = const_type_int_width(ty).unwrap_or(64)
  if width <= 16 {
    16
  } else if width <= 32 {
    32
  } else {
    64
  }
}

///|
fn Program::generic_builtin_bit_width(
  self : Program,
  frame : InterpFrame,
  args : Array[@parser.Expr],
) -> Int {
  if args.length() == 0 {
    return 32
  }
  let ty = self.core_type(self.expr_type(args[0], frame.scope()))
  let width = const_type_int_width(ty).unwrap_or(64)
  if width <= 32 {
    32
  } else {
    64
  }
}

///|
fn normalized_bit_shift(shift : Int64, width : Int) -> Int {
  let mut amount = (shift % width.to_int64()).to_int()
  if amount < 0 {
    amount += width
  }
  amount
}

///|
fn logical_right_shift_bits(value : Int64, width : Int, shift : Int) -> Int64 {
  if shift == 0 {
    mask_int_width(value, width)
  } else if width >= 64 {
    (value.reinterpret_as_uint64() >> shift).reinterpret_as_int64()
  } else {
    mask_int_width(value, width) >> shift
  }
}

///|
fn rotate_bits(value : Int64, shift : Int64, width : Int, left : Bool) -> Int64 {
  let amount = normalized_bit_shift(shift, width)
  let value = mask_int_width(value, width)
  if amount == 0 {
    value
  } else if left {
    mask_int_width(
      (value << amount) | logical_right_shift_bits(value, width, width - amount),
      width,
    )
  } else {
    mask_int_width(
      logical_right_shift_bits(value, width, amount) |
      (value << (width - amount)),
      width,
    )
  }
}

///|
fn string_literal_byte_at(value : String, index : Int64) -> Int64 {
  if index < 0L || index >= value.length().to_int64() {
    0L
  } else {
    value[index.to_int()].to_int().to_int64()
  }
}

///|
fn string_literal_c_length_from(value : String, offset : Int64) -> Int64 {
  let length = string_literal_c_length(value).to_int64()
  if offset <= 0L {
    length
  } else if offset >= length {
    0L
  } else {
    length - offset
  }
}

///|
fn literal_string_arg(expr : @parser.Expr) -> String? {
  match expr {
    String(value) => Some(value)
    Cast(_, inner) => literal_string_arg(inner)
    _ => None
  }
}

///|
priv struct LiteralStringPointer {
  value : String
  base : Int64
  offset : Int64
}

///|
fn Interpreter::string_literal_base(
  self : Interpreter,
  value : String,
) -> Int64 {
  if self.string_bases.contains(value) {
    self.string_bases[value]
  } else {
    let base = self.next_string_base
    self.string_bases[value] = base
    for i in 0..<=value.length() {
      let offset = i.to_int64()
      self.string_values[base + offset] = value
      self.string_offsets[base + offset] = offset
    }
    self.next_string_base += value.length().to_int64() + 16L
    base
  }
}

///|
fn Interpreter::string_literal_pointer_at(
  self : Interpreter,
  address : Int64,
) -> LiteralStringPointer? {
  if self.string_values.contains(address) &&
    self.string_offsets.contains(address) {
    Some({
      value: self.string_values[address],
      base: address - self.string_offsets[address],
      offset: self.string_offsets[address],
    })
  } else {
    None
  }
}

///|
fn Interpreter::literal_string_pointer(
  self : Interpreter,
  frame : InterpFrame,
  expr : @parser.Expr,
) -> LiteralStringPointer? {
  match expr {
    String(value) =>
      Some({ value, base: self.string_literal_base(value), offset: 0L })
    Cast(_, inner) => self.literal_string_pointer(frame, inner)
    Var(name) => self.string_literal_pointer_at(self.read_var(frame, name))
    Binary("+", lhs, rhs) =>
      match self.literal_string_pointer(frame, lhs) {
        Some(ptr) =>
          Some({
            value: ptr.value,
            base: ptr.base,
            offset: ptr.offset + self.eval_expr(frame, rhs),
          })
        None =>
          match self.literal_string_pointer(frame, rhs) {
            Some(ptr) =>
              Some({
                value: ptr.value,
                base: ptr.base,
                offset: ptr.offset + self.eval_expr(frame, lhs),
              })
            None => None
          }
      }
    Binary("-", lhs, rhs) =>
      match self.literal_string_pointer(frame, lhs) {
        Some(ptr) =>
          Some({
            value: ptr.value,
            base: ptr.base,
            offset: ptr.offset - self.eval_expr(frame, rhs),
          })
        None => None
      }
    _ => None
  }
}

///|
fn nonnegative_min(left : Int64, right : Int64) -> Int64? {
  if left < 0L || right < 0L {
    None
  } else if left < right {
    Some(left)
  } else {
    Some(right)
  }
}

///|
fn unknown_object_size(mode : Int64) -> Int64 {
  if (mode & 2L) != 0L {
    0L
  } else {
    -1L
  }
}

///|
fn nonnegative_radix_length(value : Int64, radix : Int64) -> Int64? {
  if value < 0L {
    None
  } else {
    let mut n = value
    let mut length = 1L
    while n >= radix {
      n = n / radix
      length += 1L
    }
    Some(length)
  }
}

///|
fn Interpreter::literal_printf_format_length(
  self : Interpreter,
  expr : @parser.Expr,
  name : String,
  args : Array[@parser.Expr],
  values : Array[Int64],
  first_value_index : Int,
) -> Int64? {
  match literal_string_arg(expr) {
    Some(format) => {
      let mut index = 0
      let mut length = 0L
      let mut value_index = first_value_index
      while index < format.length() {
        if format[index].to_int() == 37 {
          if index + 1 < format.length() && format[index + 1].to_int() == 37 {
            length += 1L
            index += 2
          } else {
            let mut conversion_index = index + 1
            let mut plus_flag = false
            let mut space_flag = false
            let mut alternate_flag = false
            while conversion_index < format.length() {
              let flag = format[conversion_index].to_int()
              if flag == 45 || flag == 48 {
                conversion_index += 1
              } else if flag == 35 {
                alternate_flag = true
                conversion_index += 1
              } else if flag == 43 {
                plus_flag = true
                conversion_index += 1
              } else if flag == 32 {
                space_flag = true
                conversion_index += 1
              } else {
                break
              }
            }
            let mut width = 0L
            while conversion_index < format.length() &&
                  format[conversion_index].to_int() >= 48 &&
                  format[conversion_index].to_int() <= 57 {
              width = width * 10L +
                (format[conversion_index].to_int() - 48).to_int64()
              conversion_index += 1
            }
            let mut has_precision = false
            let mut precision = 0L
            if conversion_index < format.length() &&
              format[conversion_index].to_int() == 46 {
              has_precision = true
              conversion_index += 1
              while conversion_index < format.length() &&
                    format[conversion_index].to_int() >= 48 &&
                    format[conversion_index].to_int() <= 57 {
                precision = precision * 10L +
                  (format[conversion_index].to_int() - 48).to_int64()
                conversion_index += 1
              }
            }
            let mut modified = false
            if conversion_index < format.length() {
              if format[conversion_index].to_int() == 108 {
                modified = true
                conversion_index += 1
                if conversion_index < format.length() &&
                  format[conversion_index].to_int() == 108 {
                  conversion_index += 1
                }
              } else if format[conversion_index].to_int() == 106 ||
                format[conversion_index].to_int() == 116 ||
                format[conversion_index].to_int() == 122 {
                modified = true
                conversion_index += 1
              }
            }
            if conversion_index < format.length() &&
              (
                format[conversion_index].to_int() == 88 ||
                format[conversion_index].to_int() == 99 ||
                format[conversion_index].to_int() == 100 ||
                format[conversion_index].to_int() == 105 ||
                format[conversion_index].to_int() == 111 ||
                format[conversion_index].to_int() == 115 ||
                format[conversion_index].to_int() == 117 ||
                format[conversion_index].to_int() == 120
              ) {
              if modified &&
                (
                  format[conversion_index].to_int() == 99 ||
                  format[conversion_index].to_int() == 115
                ) {
                self.fail("unsupported MIR interpreter " + name + " format")
                return None
              }
              if has_precision &&
                format[conversion_index].to_int() != 100 &&
                format[conversion_index].to_int() != 105 &&
                format[conversion_index].to_int() != 88 &&
                format[conversion_index].to_int() != 111 &&
                format[conversion_index].to_int() != 115 &&
                format[conversion_index].to_int() != 117 &&
                format[conversion_index].to_int() != 120 {
                self.fail("unsupported MIR interpreter " + name + " format")
                return None
              }
              if (plus_flag || space_flag) &&
                format[conversion_index].to_int() != 100 &&
                format[conversion_index].to_int() != 105 {
                self.fail("unsupported MIR interpreter " + name + " format")
                return None
              }
              if alternate_flag &&
                format[conversion_index].to_int() != 111 &&
                format[conversion_index].to_int() != 88 &&
                format[conversion_index].to_int() != 120 {
                self.fail("unsupported MIR interpreter " + name + " format")
                return None
              }
              if value_index >= values.length() {
                self.fail("unsupported MIR interpreter " + name + " argument")
                return None
              }
              let mut conversion_length = 0L
              if format[conversion_index].to_int() == 99 {
                conversion_length = 1L
              } else if format[conversion_index].to_int() == 115 {
                match literal_string_arg(args[value_index]) {
                  Some(value) => {
                    conversion_length = string_literal_c_length(value).to_int64()
                    if has_precision && precision < conversion_length {
                      conversion_length = precision
                    }
                  }
                  None => {
                    self.fail(
                      "unsupported MIR interpreter " + name + " string argument",
                    )
                    return None
                  }
                }
              } else if format[conversion_index].to_int() == 111 ||
                format[conversion_index].to_int() == 88 ||
                format[conversion_index].to_int() == 120 {
                let radix = if format[conversion_index].to_int() == 88 ||
                  format[conversion_index].to_int() == 120 {
                  16L
                } else {
                  8L
                }
                let value = values[value_index]
                match nonnegative_radix_length(value, radix) {
                  Some(radix_length) => {
                    conversion_length = if has_precision &&
                      value == 0L &&
                      precision == 0L {
                      0L
                    } else {
                      radix_length
                    }
                    if has_precision && precision > conversion_length {
                      conversion_length = precision
                    }
                    if alternate_flag &&
                      format[conversion_index].to_int() == 111 {
                      if has_precision {
                        if value == 0L {
                          if precision == 0L {
                            conversion_length = 1L
                          }
                        } else if precision <= radix_length {
                          conversion_length += 1L
                        }
                      } else if value != 0L {
                        conversion_length += 1L
                      }
                    } else if alternate_flag && value != 0L {
                      conversion_length += 2L
                    }
                  }
                  None => {
                    self.fail(
                      "unsupported MIR interpreter " + name + " radix argument",
                    )
                    return None
                  }
                }
              } else {
                if format[conversion_index].to_int() == 117 &&
                  values[value_index] < 0L {
                  self.fail(
                    "unsupported MIR interpreter " + name + " unsigned argument",
                  )
                  return None
                }
                let value = values[value_index]
                if has_precision && value < 0L {
                  let digit_length = value.to_string().length().to_int64() - 1L
                  let padded_digits = if precision > digit_length {
                    precision
                  } else {
                    digit_length
                  }
                  conversion_length = 1L + padded_digits
                } else {
                  conversion_length = if has_precision &&
                    value == 0L &&
                    precision == 0L {
                    0L
                  } else {
                    value.to_string().length().to_int64()
                  }
                  if has_precision && precision > conversion_length {
                    conversion_length = precision
                  }
                  if value >= 0L && (plus_flag || space_flag) {
                    conversion_length += 1L
                  }
                }
              }
              if width > conversion_length {
                length += width
              } else {
                length += conversion_length
              }
              value_index += 1
              index = conversion_index + 1
            } else {
              self.fail("unsupported MIR interpreter " + name + " format")
              return None
            }
          }
        } else {
          length += 1L
          index += 1
        }
      }
      Some(length)
    }
    None => {
      self.fail("unsupported MIR interpreter " + name + " format argument")
      None
    }
  }
}

///|
fn compare_string_literal_bytes_from(
  left : String,
  left_offset : Int64,
  right : String,
  right_offset : Int64,
  limit : Int64?,
  stop_at_nul : Bool,
) -> Int64 {
  let mut index = 0L
  while limit is None || index < limit.unwrap() {
    let lhs = string_literal_byte_at(left, left_offset + index)
    let rhs = string_literal_byte_at(right, right_offset + index)
    if lhs != rhs {
      return if lhs < rhs { -1L } else { 1L }
    }
    if stop_at_nul && lhs == 0L {
      return 0L
    }
    index += 1L
  }
  0L
}

///|
fn string_literal_find_byte_from(
  value : String,
  start_offset : Int64,
  byte : Int64,
  limit : Int64?,
  stop_at_nul : Bool,
) -> Int64? {
  let needle = byte & 0xFFL
  let mut index = 0L
  while limit is None || index < limit.unwrap() {
    let absolute_index = start_offset + index
    let current = string_literal_byte_at(value, absolute_index)
    if current == needle {
      return Some(absolute_index)
    }
    if stop_at_nul && current == 0L {
      return None
    }
    index += 1L
  }
  None
}

///|
fn string_literal_find_last_byte_from(
  value : String,
  start_offset : Int64,
  byte : Int64,
) -> Int64? {
  let needle = byte & 0xFFL
  let mut index = start_offset
  let mut found : Int64? = None
  while true {
    let current = string_literal_byte_at(value, index)
    if current == needle {
      found = Some(index)
    }
    if current == 0L {
      return found
    }
    index += 1L
  }
  None
}

///|
fn string_literal_c_length(value : String) -> Int {
  for i in 0..<value.length() {
    if value[i].to_int() == 0 {
      return i
    }
  }
  value.length()
}

///|
fn string_literal_find_string_from(
  haystack : String,
  start_offset : Int64,
  needle : String,
  needle_offset : Int64,
) -> Int64? {
  let haystack_length = string_literal_c_length(haystack).to_int64()
  let needle_length = string_literal_c_length_from(needle, needle_offset)
  if needle_length == 0 {
    return Some(start_offset)
  }
  if start_offset > haystack_length ||
    needle_length > haystack_length - start_offset {
    return None
  }
  let mut start = start_offset
  while start <= haystack_length - needle_length {
    let mut matched = true
    let mut i = 0L
    while i < needle_length {
      if string_literal_byte_at(haystack, start + i) !=
        string_literal_byte_at(needle, needle_offset + i) {
        matched = false
      }
      i += 1L
    }
    if matched {
      return Some(start)
    }
    start += 1L
  }
  None
}

///|
fn Interpreter::eval_builtin_call(
  self : Interpreter,
  frame : InterpFrame,
  name : String,
  args : Array[@parser.Expr],
) -> Int64? {
  match overflow_builtin_op(name) {
    Some(op) => return Some(self.eval_overflow_builtin(frame, op, args))
    None => ()
  }
  match name {
    "__builtin_expect" | "__builtin_expect_with_probability" => {
      let result = self.eval_first_call_arg_or_zero(frame, args)
      if args.length() > 1 {
        self.eval_ignored_expr_side_effects(frame, args[1])
      }
      Some(result)
    }
    "__builtin_unpredictable"
    | "__builtin_extract_return_addr"
    | "__builtin_frob_return_addr" =>
      Some(self.eval_first_call_arg_or_zero(frame, args))
    "__builtin_assume_aligned" => {
      let result = self.eval_first_call_arg_or_zero(frame, args)
      if args.length() > 2 {
        self.eval_ignored_expr_side_effects(frame, args[2])
      }
      Some(result)
    }
    "__builtin_constant_p" =>
      if args.length() > 0 &&
        self.program.fold_const(args[0], frame.scope()) is Some(_) {
        Some(1L)
      } else {
        Some(0L)
      }
    "__builtin_flt_rounds" => Some(1L)
    "__builtin_assume" => Some(0L)
    "__builtin_prefetch" => {
      if args.length() > 0 {
        ignore(self.eval_expr(frame, args[0]))
      }
      Some(0L)
    }
    "__builtin_object_size" | "__builtin_dynamic_object_size" =>
      Some(self.eval_builtin_object_size(frame, args))
    "__builtin_isgreater"
    | "__builtin_isgreaterequal"
    | "__builtin_isless"
    | "__builtin_islessequal"
    | "__builtin_islessgreater"
    | "__builtin_isunordered" =>
      Some(self.eval_builtin_fp_compare(frame, name, args))
    "__builtin_isnan"
    | "__builtin_isnanf"
    | "__builtin_isnanl"
    | "__builtin_isinf"
    | "__builtin_isinff"
    | "__builtin_isinfl"
    | "__builtin_isfinite"
    | "__builtin_isfinitef"
    | "__builtin_isfinitel"
    | "__builtin_isnormal"
    | "__builtin_isnormalf"
    | "__builtin_isnormall"
    | "__builtin_signbit"
    | "__builtin_signbitf"
    | "__builtin_signbitl" =>
      Some(self.eval_builtin_fp_class(frame, name, args))
    "__builtin_va_start" | "__builtin_va_end" | "__builtin_va_copy" => Some(0L)
    "__builtin_bzero" => {
      ignore(self.eval_call_args(frame, args))
      Some(0L)
    }
    "__builtin_memcpy"
    | "__builtin___memcpy_chk"
    | "__builtin_memmove"
    | "__builtin___memmove_chk"
    | "__builtin_memset"
    | "__builtin___memset_chk" =>
      Some(self.eval_return_first_call_arg(frame, args, 3))
    "__builtin_mempcpy" | "__builtin___mempcpy_chk" => {
      let values = self.eval_call_args(frame, args)
      if args.length() < 3 {
        Some(0L)
      } else if values[2] < 0L {
        self.fail("unsupported MIR interpreter mempcpy length")
        Some(0L)
      } else {
        Some(values[0] + values[2])
      }
    }
    "__builtin_strcpy"
    | "__builtin___strcpy_chk"
    | "__builtin_strcat"
    | "__builtin___strcat_chk"
    | "__builtin_strncpy"
    | "__builtin___strncpy_chk"
    | "__builtin_strncat"
    | "__builtin___strncat_chk" =>
      Some(self.eval_return_first_call_arg(frame, args, args.length()))
    "__builtin_stpcpy" | "__builtin___stpcpy_chk" => {
      let values = self.eval_call_args(frame, args)
      if args.length() < 2 {
        Some(0L)
      } else {
        match literal_string_arg(args[1]) {
          Some(value) =>
            Some(values[0] + string_literal_c_length(value).to_int64())
          None => {
            self.fail("unsupported MIR interpreter stpcpy source argument")
            Some(0L)
          }
        }
      }
    }
    "__builtin_stpncpy" | "__builtin___stpncpy_chk" => {
      let values = self.eval_call_args(frame, args)
      if args.length() < 3 {
        Some(0L)
      } else {
        match literal_string_arg(args[1]) {
          Some(value) =>
            match
              nonnegative_min(
                string_literal_c_length(value).to_int64(),
                values[2],
              ) {
              Some(offset) => Some(values[0] + offset)
              None => {
                self.fail("unsupported MIR interpreter stpncpy length")
                Some(0L)
              }
            }
          None => {
            self.fail("unsupported MIR interpreter stpncpy source argument")
            Some(0L)
          }
        }
      }
    }
    "__builtin___strlcpy_chk" => {
      ignore(self.eval_call_args(frame, args))
      if args.length() < 2 {
        Some(0L)
      } else {
        match literal_string_arg(args[1]) {
          Some(value) => Some(string_literal_c_length(value).to_int64())
          None => {
            self.fail("unsupported MIR interpreter strlcpy source argument")
            Some(0L)
          }
        }
      }
    }
    "__builtin___strlcat_chk" => {
      let values = self.eval_call_args(frame, args)
      if args.length() < 3 {
        Some(0L)
      } else {
        match literal_string_arg(args[1]) {
          Some(value) =>
            if values[2] == 0L {
              Some(string_literal_c_length(value).to_int64())
            } else {
              self.fail(
                "unsupported MIR interpreter strlcat destination length",
              )
              Some(0L)
            }
          None => {
            self.fail("unsupported MIR interpreter strlcat source argument")
            Some(0L)
          }
        }
      }
    }
    "__builtin___snprintf_chk" => {
      let values = self.eval_call_args(frame, args)
      if args.length() < 5 {
        Some(0L)
      } else {
        match
          self.literal_printf_format_length(
            args[4],
            "snprintf",
            args,
            values,
            5,
          ) {
          Some(value) => Some(value)
          None => Some(0L)
        }
      }
    }
    "__builtin___sprintf_chk" => {
      let values = self.eval_call_args(frame, args)
      if args.length() < 4 {
        Some(0L)
      } else {
        match
          self.literal_printf_format_length(args[3], "sprintf", args, values, 4) {
          Some(value) => Some(value)
          None => Some(0L)
        }
      }
    }
    "__builtin___printf_chk" => {
      let values = self.eval_call_args(frame, args)
      if args.length() < 2 {
        Some(0L)
      } else {
        match
          self.literal_printf_format_length(args[1], "printf", args, values, 2) {
          Some(value) => Some(value)
          None => Some(0L)
        }
      }
    }
    "__builtin_alloca" => {
      let size = if args.length() > 0 {
        self.eval_expr(frame, args[0])
      } else {
        0L
      }
      let ptr = self.next_alloca
      let bump = if size <= 0L { 16L } else { (size + 15L) & -16L }
      self.next_alloca += bump
      Some(ptr)
    }
    "__builtin_frame_address" | "__builtin_return_address" => {
      let level = if args.length() > 0 {
        self.eval_expr(frame, args[0])
      } else {
        0L
      }
      // The MIR oracle models address nullness only, not exact machine PCs/FPs.
      Some(if level == 0L { 1L } else { 0L })
    }
    "__builtin_abs" => Some(self.eval_builtin_abs(frame, args, SInt))
    "__builtin_labs" => Some(self.eval_builtin_abs(frame, args, SLong))
    "__builtin_llabs" => Some(self.eval_builtin_abs(frame, args, SLongLong))
    "__builtin_is_aligned" => Some(self.eval_builtin_is_aligned(frame, args))
    "__builtin_align_up" =>
      Some(self.eval_builtin_align_value(frame, args, true))
    "__builtin_align_down" =>
      Some(self.eval_builtin_align_value(frame, args, false))
    "__builtin_clz" =>
      Some(
        count_leading_zero_bits(
          self.eval_first_call_arg_or_zero(frame, args),
          32,
        ),
      )
    "__builtin_clzl" | "__builtin_clzll" =>
      Some(
        count_leading_zero_bits(
          self.eval_first_call_arg_or_zero(frame, args),
          64,
        ),
      )
    "__builtin_ctz" =>
      Some(
        count_trailing_zero_bits(
          self.eval_first_call_arg_or_zero(frame, args),
          32,
        ),
      )
    "__builtin_ctzl" | "__builtin_ctzll" =>
      Some(
        count_trailing_zero_bits(
          self.eval_first_call_arg_or_zero(frame, args),
          64,
        ),
      )
    "__builtin_ffs" =>
      Some(first_set_bit(self.eval_first_call_arg_or_zero(frame, args), 32))
    "__builtin_ffsl" | "__builtin_ffsll" =>
      Some(first_set_bit(self.eval_first_call_arg_or_zero(frame, args), 64))
    "__builtin_bswap16" =>
      Some(byte_swap_bits(self.eval_first_call_arg_or_zero(frame, args), 16))
    "__builtin_bswap32" =>
      Some(byte_swap_bits(self.eval_first_call_arg_or_zero(frame, args), 32))
    "__builtin_bswap64" =>
      Some(byte_swap_bits(self.eval_first_call_arg_or_zero(frame, args), 64))
    "__builtin_bswap" =>
      Some(
        byte_swap_bits(
          self.eval_first_call_arg_or_zero(frame, args),
          self.program.generic_builtin_bswap_width(frame, args),
        ),
      )
    "__builtin_popcount" =>
      Some(count_one_bits(self.eval_first_call_arg_or_zero(frame, args), 32))
    "__builtin_popcountl" | "__builtin_popcountll" =>
      Some(count_one_bits(self.eval_first_call_arg_or_zero(frame, args), 64))
    "__builtin_parity" =>
      Some(
        count_one_bits(self.eval_first_call_arg_or_zero(frame, args), 32) & 1L,
      )
    "__builtin_parityl" | "__builtin_parityll" =>
      Some(
        count_one_bits(self.eval_first_call_arg_or_zero(frame, args), 64) & 1L,
      )
    "__builtin_rotateleft" | "__builtin_rotateright" =>
      if args.length() >= 2 {
        Some(
          rotate_bits(
            self.eval_expr(frame, args[0]),
            self.eval_expr(frame, args[1]),
            self.program.generic_builtin_bit_width(frame, args),
            name == "__builtin_rotateleft",
          ),
        )
      } else {
        Some(0L)
      }
    "__builtin_rotateleft32" | "__builtin_rotateright32" =>
      if args.length() >= 2 {
        Some(
          rotate_bits(
            self.eval_expr(frame, args[0]),
            self.eval_expr(frame, args[1]),
            32,
            name == "__builtin_rotateleft32",
          ),
        )
      } else {
        Some(0L)
      }
    "__builtin_rotateleft64" | "__builtin_rotateright64" =>
      if args.length() >= 2 {
        Some(
          rotate_bits(
            self.eval_expr(frame, args[0]),
            self.eval_expr(frame, args[1]),
            64,
            name == "__builtin_rotateleft64",
          ),
        )
      } else {
        Some(0L)
      }
    "__builtin_strlen" =>
      if args.length() == 0 {
        Some(0L)
      } else {
        match self.literal_string_pointer(frame, args[0]) {
          Some(ptr) => Some(string_literal_c_length_from(ptr.value, ptr.offset))
          _ => {
            self.fail("unsupported MIR interpreter strlen argument")
            Some(0L)
          }
        }
      }
    "__builtin_strcmp" =>
      if args.length() < 2 {
        Some(0L)
      } else {
        match
          (
            self.literal_string_pointer(frame, args[0]),
            self.literal_string_pointer(frame, args[1]),
          ) {
          (Some(left), Some(right)) =>
            Some(
              compare_string_literal_bytes_from(
                left.value,
                left.offset,
                right.value,
                right.offset,
                None,
                true,
              ),
            )
          _ => {
            self.fail("unsupported MIR interpreter strcmp argument")
            Some(0L)
          }
        }
      }
    "__builtin_strncmp" =>
      if args.length() < 3 {
        Some(0L)
      } else {
        match
          (
            self.literal_string_pointer(frame, args[0]),
            self.literal_string_pointer(frame, args[1]),
          ) {
          (Some(left), Some(right)) =>
            Some(
              compare_string_literal_bytes_from(
                left.value,
                left.offset,
                right.value,
                right.offset,
                Some(self.eval_expr(frame, args[2])),
                true,
              ),
            )
          _ => {
            self.fail("unsupported MIR interpreter strncmp argument")
            Some(0L)
          }
        }
      }
    "__builtin_memcmp" =>
      if args.length() < 3 {
        Some(0L)
      } else {
        match
          (
            self.literal_string_pointer(frame, args[0]),
            self.literal_string_pointer(frame, args[1]),
          ) {
          (Some(left), Some(right)) =>
            Some(
              compare_string_literal_bytes_from(
                left.value,
                left.offset,
                right.value,
                right.offset,
                Some(self.eval_expr(frame, args[2])),
                false,
              ),
            )
          _ => {
            self.fail("unsupported MIR interpreter memcmp argument")
            Some(0L)
          }
        }
      }
    "__builtin_strchr" | "__builtin_strrchr" =>
      if args.length() < 2 {
        Some(0L)
      } else {
        match self.literal_string_pointer(frame, args[0]) {
          Some(ptr) => {
            let offset = if name == "__builtin_strrchr" {
              string_literal_find_last_byte_from(
                ptr.value,
                ptr.offset,
                self.eval_expr(frame, args[1]),
              )
            } else {
              string_literal_find_byte_from(
                ptr.value,
                ptr.offset,
                self.eval_expr(frame, args[1]),
                None,
                true,
              )
            }
            match offset {
              Some(index) => Some(ptr.base + index)
              None => Some(0L)
            }
          }
          None => {
            self.fail("unsupported MIR interpreter string search argument")
            Some(0L)
          }
        }
      }
    "__builtin_memchr" =>
      if args.length() < 3 {
        Some(0L)
      } else {
        match self.literal_string_pointer(frame, args[0]) {
          Some(ptr) => {
            let limit = self.eval_expr(frame, args[2])
            if limit < 0L {
              self.fail("unsupported MIR interpreter memchr length")
              Some(0L)
            } else {
              match
                string_literal_find_byte_from(
                  ptr.value,
                  ptr.offset,
                  self.eval_expr(frame, args[1]),
                  Some(limit),
                  false,
                ) {
                Some(index) => Some(ptr.base + index)
                None => Some(0L)
              }
            }
          }
          None => {
            self.fail("unsupported MIR interpreter memchr argument")
            Some(0L)
          }
        }
      }
    "__builtin_strstr" =>
      if args.length() < 2 {
        Some(0L)
      } else {
        match
          (
            self.literal_string_pointer(frame, args[0]),
            self.literal_string_pointer(frame, args[1]),
          ) {
          (Some(haystack), Some(needle)) =>
            match
              string_literal_find_string_from(
                haystack.value,
                haystack.offset,
                needle.value,
                needle.offset,
              ) {
              Some(index) => Some(haystack.base + index)
              None => Some(0L)
            }
          _ => {
            self.fail("unsupported MIR interpreter strstr argument")
            Some(0L)
          }
        }
      }
    _ => None
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
    String(value) => self.string_literal_base(value)
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
    Call(func, args) =>
      match func {
        Var(name) =>
          match self.eval_builtin_call(frame, name, args) {
            Some(value) => value
            None => self.call_func(name, self.eval_call_args(frame, args))
          }
        _ => {
          self.fail("unsupported MIR interpreter indirect call")
          0L
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
    Deref(AddrOf(value)) => self.read_lvalue(frame, value)
    AddrOf(Deref(value)) => self.eval_expr(frame, value)
    Deref(value) =>
      match self.literal_string_pointer(frame, value) {
        Some(ptr) => string_literal_byte_at(ptr.value, ptr.offset)
        None => {
          self.fail("unsupported MIR interpreter memory expression")
          0L
        }
      }
    ArrayAccess(base, index) =>
      match self.literal_string_pointer(frame, base) {
        Some(ptr) =>
          string_literal_byte_at(
            ptr.value,
            ptr.offset + self.eval_expr(frame, index),
          )
        None => {
          self.fail("unsupported MIR interpreter memory expression")
          0L
        }
      }
    MemberAccess(_, _) | AddrOf(_) => {
      self.fail("unsupported MIR interpreter memory expression")
      0L
    }
    Sizeof(ty) => self.program.type_size(ty).to_int64()
    SizeofExpr(String(value)) => (value.length() + 1).to_int64()
    SizeofExpr(e) =>
      self.program.type_size(self.program.expr_type(e, scope)).to_int64()
    Alignof(ty) => self.program.type_align(ty).to_int64()
    AlignofExpr(String(value)) =>
      self.program.type_align(Array(SChar, value.length() + 1)).to_int64()
    AlignofExpr(e) =>
      self.program.type_align(self.program.expr_type(e, scope)).to_int64()
    Cast(ty, value) =>
      if self.program.runtime_int_type(ty) {
        if self.program.is_floating_type(self.program.expr_type(value, scope)) {
          match self.program.fold_float_const(value, scope) {
            Some(value) =>
              self.program.runtime_cast_int(value.to_int().to_int64(), ty)
            None =>
              self.program.runtime_cast_int(self.eval_expr(frame, value), ty)
          }
        } else {
          self.program.runtime_cast_int(self.eval_expr(frame, value), ty)
        }
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
    CompoundLiteral(ty, init_exprs, _) =>
      if self.program.runtime_int_type(ty) {
        let value = if init_exprs.length() > 0 {
          self.eval_expr(frame, init_exprs[0])
        } else {
          0L
        }
        self.program.runtime_cast_int(value, ty)
      } else {
        self.fail("unsupported MIR interpreter aggregate expression")
        0L
      }
    Array(_) => {
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
    frame.local_types[name] = ty
    match init {
      Some(expr) => self.eval_ignored_expr_side_effects(frame, expr)
      None => ()
    }
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
      Jump(label) => return Jump(label)
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
      Jump(label) => return Jump(label)
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
      Jump(label) => return Jump(label)
    }
    match inc {
      Some(expr) => ignore(self.eval_expr(frame, expr))
      None => ()
    }
  }
  Normal
}

///|
fn switch_stmt_label(stmt : @parser.Stmt) -> String? {
  match stmt {
    Label(name, _) => Some(name)
    _ => None
  }
}

///|
fn Interpreter::exec_stmt_from_leading_label(
  self : Interpreter,
  frame : InterpFrame,
  stmt : @parser.Stmt,
  target : String,
) -> (Bool, ExecFlow) {
  match stmt {
    Label(name, body) =>
      if name == target {
        (true, self.exec_stmt(frame, body))
      } else {
        self.exec_stmt_from_leading_label(frame, body, target)
      }
    _ => (false, Normal)
  }
}

///|
fn Interpreter::exec_switch_body(
  self : Interpreter,
  frame : InterpFrame,
  body : @parser.Stmt,
  target : String?,
) -> ExecFlow {
  let stmts = match body {
    Compound(stmts) | StmtList(stmts) => stmts
    _ => {
      self.fail("unsupported MIR interpreter switch body")
      return Normal
    }
  }
  let mut active = target is None
  let mut found = target is None
  for stmt in stmts {
    if !active {
      match (target, switch_stmt_label(stmt)) {
        (Some(want), Some(got)) if want == got => {
          active = true
          found = true
        }
        (Some(want), _) => {
          let (nested_found, flow) = self.exec_stmt_from_leading_label(
            frame, stmt, want,
          )
          if nested_found {
            active = true
            found = true
            match flow {
              Normal => continue
              Broke => return Normal
              flow => return flow
            }
          } else {
            continue
          }
        }
        _ => continue
      }
    }
    match self.exec_stmt(frame, stmt) {
      Normal => ()
      Broke => return Normal
      flow => return flow
    }
  }
  if !found {
    self.fail("unsupported nested MIR interpreter switch label")
  }
  Normal
}

///|
fn Interpreter::exec_switch(
  self : Interpreter,
  frame : InterpFrame,
  expr : @parser.Expr,
  body : @parser.Stmt,
  cases : Array[(Int64?, String)],
) -> ExecFlow {
  let control_ty = self.program.switch_control_type(
    self.program.expr_type(expr, frame.scope()),
  )
  let control_value = self.program.runtime_cast_int(
    self.eval_expr(frame, expr),
    control_ty,
  )
  let mut target : String? = None
  let mut default_target : String? = None
  for c in cases {
    match c.0 {
      Some(value) => {
        let case_value = self.program.runtime_cast_int(value, control_ty)
        if target is None && case_value == control_value {
          target = Some(c.1)
        }
      }
      None => if default_target is None { default_target = Some(c.1) }
    }
  }
  match target {
    Some(_) => ()
    None => target = default_target
  }
  match target {
    Some(_) => self.exec_switch_body(frame, body, target)
    None => Normal
  }
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
    Switch(expr, body, cases) => self.exec_switch(frame, expr, body, cases)
    Goto(name) => Jump(name)
    ComputedGoto(_) => {
      self.fail("unsupported MIR interpreter control statement")
      Normal
    }
    Label(_, body) => self.exec_stmt(frame, body)
    For(init, cond, inc, body) => self.exec_for(frame, init, cond, inc, body)
    DoWhile(cond, body) => self.exec_do_while(frame, cond, body)
  }
}

///|
fn Interpreter::exec_func_body_from_label(
  self : Interpreter,
  frame : InterpFrame,
  body : @parser.Stmt,
  target : String,
) -> ExecFlow {
  let stmts = match body {
    Compound(stmts) | StmtList(stmts) => stmts
    _ => {
      self.fail("unsupported MIR interpreter goto body")
      return Normal
    }
  }
  let mut active = false
  let mut found = false
  for stmt in stmts {
    if !active {
      match switch_stmt_label(stmt) {
        Some(got) if got == target => {
          active = true
          found = true
        }
        _ => {
          let (nested_found, flow) = self.exec_stmt_from_leading_label(
            frame, stmt, target,
          )
          if nested_found {
            active = true
            found = true
            match flow {
              Normal => continue
              flow => return flow
            }
          } else {
            continue
          }
        }
      }
    }
    match self.exec_stmt(frame, stmt) {
      Normal => ()
      flow => return flow
    }
  }
  if !found {
    self.fail("unknown label in MIR interpreter goto: " + target)
  }
  Normal
}

///|
fn Interpreter::exec_func_body(
  self : Interpreter,
  frame : InterpFrame,
  body : @parser.Stmt,
) -> ExecFlow {
  let mut flow = self.exec_stmt(frame, body)
  while !self.failed() {
    match flow {
      Jump(label) => flow = self.exec_func_body_from_label(frame, body, label)
      _ => break
    }
  }
  flow
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
          match self.exec_func_body(frame, body) {
            Returned(value) => self.program.runtime_cast_int(value, decl.ret)
            Normal => 0L
            Broke | Continued => {
              self.fail("break or continue escaped function in MIR interpreter")
              0L
            }
            Jump(label) => {
              self.fail("unknown label in MIR interpreter goto: " + label)
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
/// call, computed goto, varargs, and floating-point behavior that is not
/// modeled yet.
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
