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
  local_types : Map[String, @ctype.Type]
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
  ty : @ctype.Type,
) -> @ctype.Type {
  match ty {
    Atomic(inner) | Aligned(inner, _) => self.switch_control_type(inner)
    Bool | SChar | UChar | SShort | UShort => SInt
    _ => ty
  }
}

///|
fn Program::runtime_int_type(self : Program, ty : @ctype.Type) -> Bool {
  match self.core_type(ty) {
    Pointer(_) | FuncPtr(_, _, _) => true
    core => core.const_int_width() is Some(_)
  }
}

///|
fn Program::runtime_cast_int(
  self : Program,
  value : Int64,
  ty : @ctype.Type,
) -> Int64 {
  @ctype.integer_constant(value, self.core_type(ty)).bits
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
    AddrOf(Deref(inner)) => self.global_string_pointer_initializer(inner)
    AddrOf(ArrayAccess(base, index)) =>
      match self.global_string_pointer_initializer(base) {
        Some(ptr) =>
          match self.global_pointer_offset(base, index) {
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
  ty : @ctype.Type,
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
fn interpreter_char_core_type(ty : @ctype.Type) -> @ctype.Type {
  ty.core_type()
}

///|
fn global_char_array_length(ty : @ctype.Type) -> Int? {
  match interpreter_char_core_type(ty) {
    Array(elem, length) =>
      match interpreter_char_core_type(elem) {
        SChar | UChar => Some(length)
        _ => None
      }
    _ => None
  }
}

///|
fn Interpreter::char_initializer_value(
  self : Interpreter,
  expr : @parser.Expr,
) -> Int64? {
  match self.program.fold_const(expr, Scope::empty()) {
    Some(value) => Some(value & 0xFFL)
    None => None
  }
}

///|
fn Interpreter::string_from_char_initializers(
  self : Interpreter,
  exprs : Array[@parser.Expr],
  length : Int,
) -> String? {
  let bytes : Array[Int64] = Array::make(length, 0L)
  let mut cursor = 0
  for expr in exprs {
    match expr {
      DesignatedIndex(index, value) => {
        if index < 0L || index >= length.to_int64() {
          return None
        }
        match self.char_initializer_value(value) {
          Some(byte) => {
            let slot = index.to_int()
            bytes[slot] = byte
            cursor = slot + 1
          }
          None => return None
        }
      }
      DesignatedRange(first, last, value) => {
        if first < 0L || last < first || last >= length.to_int64() {
          return None
        }
        match self.char_initializer_value(value) {
          Some(byte) => {
            for i in first.to_int()..<=last.to_int() {
              bytes[i] = byte
            }
            cursor = last.to_int() + 1
          }
          None => return None
        }
      }
      _ =>
        if cursor < length {
          match self.char_initializer_value(expr) {
            Some(byte) => {
              bytes[cursor] = byte
              cursor += 1
            }
            None => return None
          }
        }
    }
  }
  let buf = StringBuilder::new()
  for byte in bytes {
    buf.write_char(byte.to_int().unsafe_to_char())
  }
  Some(buf.to_string())
}

///|
fn string_from_fixed_char_string(value : String, length : Int) -> String {
  let buf = StringBuilder::new()
  let limit = if value.length() < length { value.length() } else { length }
  for i in 0..<limit {
    buf.write_char(value[i].to_int().unsafe_to_char())
  }
  for _ in limit..<length {
    buf.write_char('\u0000')
  }
  buf.to_string()
}

///|
fn zero_byte_string(length : Int) -> String {
  let buf = StringBuilder::new()
  for _ in 0..<length {
    buf.write_char('\u0000')
  }
  buf.to_string()
}

///|
fn Interpreter::init_global_string_array(
  self : Interpreter,
  name : String,
  ty : @ctype.Type,
  init : @parser.GlobalInit?,
) -> Unit {
  match global_char_array_length(ty) {
    Some(length) =>
      match init {
        None =>
          self.globals[name] = self.fresh_string_object_base(
            zero_byte_string(length),
          )
        Some(Scalar(String(value))) =>
          self.globals[name] = self.fresh_string_object_base(
            string_from_fixed_char_string(value, length),
          )
        Some(Array(exprs)) =>
          match self.string_from_char_initializers(exprs, length) {
            Some(value) =>
              self.globals[name] = self.fresh_string_object_base(value)
            None => ()
          }
        _ => ()
      }
    None => ()
  }
}

///|
fn Interpreter::init_local_string_array(
  self : Interpreter,
  frame : InterpFrame,
  ty : @ctype.Type,
  name : String,
  init : @parser.Expr?,
) -> Bool {
  match global_char_array_length(ty) {
    Some(length) => {
      frame.local_types[name] = ty
      let value = match init {
        Some(String(value)) => string_from_fixed_char_string(value, length)
        Some(Array(exprs)) =>
          match self.string_from_char_initializers(exprs, length) {
            Some(value) => value
            None => {
              for expr in exprs {
                self.eval_ignored_expr_side_effects(frame, expr)
              }
              zero_byte_string(length)
            }
          }
        Some(Number(_, _, _)) => zero_byte_string(length)
        None => zero_byte_string(length)
        Some(expr) => {
          self.eval_ignored_expr_side_effects(frame, expr)
          zero_byte_string(length)
        }
      }
      frame.locals[name] = self.fresh_string_object_base(value)
      true
    }
    None => false
  }
}

///|
fn interpreter_global_has_init(g : @parser.GlobalDecl) -> Bool {
  g.init is Some(_)
}

///|
fn interpreter_should_replace_global_decl(
  old : @parser.GlobalDecl,
  next : @parser.GlobalDecl,
) -> Bool {
  if next.is_extern && !interpreter_global_has_init(next) {
    false
  } else if !interpreter_global_has_init(old) &&
    interpreter_global_has_init(next) {
    true
  } else if old.is_extern && !next.is_extern {
    true
  } else if interpreter_global_has_init(old) &&
    !interpreter_global_has_init(next) {
    false
  } else {
    interpreter_global_has_init(next)
  }
}

///|
fn interpreter_merge_parser_globals(
  globals : Array[@parser.GlobalDecl],
) -> Map[String, @parser.GlobalDecl] {
  let merged : Map[String, @parser.GlobalDecl] = Map([])
  for g in globals {
    if !merged.contains(g.name) ||
      interpreter_should_replace_global_decl(merged[g.name], g) {
      merged[g.name] = g
    }
  }
  merged
}

///|
fn Interpreter::init_globals(self : Interpreter) -> Unit {
  let seen : Map[String, Bool] = Map([])
  let parser_globals = interpreter_merge_parser_globals(
    self.program.source.globals,
  )
  for original in self.program.source.globals {
    if self.program.globals.contains(original.name) &&
      !seen.contains(original.name) {
      seen[original.name] = true
      let decl = self.program.globals[original.name]
      let parser_decl = parser_globals[original.name]
      if !self.program.runtime_int_type(decl.ty) {
        // Non-runtime globals still provide type facts through Program::globals.
        self.init_global_string_array(decl.name, decl.ty, parser_decl.init)
        continue
      }
      let value = match parser_decl.init {
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
) -> @ctype.Type? {
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
    Deref(value) =>
      match self.literal_string_pointer(frame, value) {
        Some(ptr) => string_literal_byte_at(ptr.value, ptr.offset)
        None => {
          self.fail("unsupported MIR interpreter lvalue")
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
          self.fail("unsupported MIR interpreter lvalue")
          0L
        }
      }
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
    Deref(target) =>
      match self.literal_string_pointer(frame, target) {
        Some(ptr) => self.write_string_byte(ptr.base + ptr.offset, value)
        None => {
          self.fail("unsupported MIR interpreter assignment target")
          0L
        }
      }
    ArrayAccess(base, index) =>
      match self.literal_string_pointer(frame, base) {
        Some(ptr) =>
          self.write_string_byte(
            ptr.base + ptr.offset + self.eval_expr(frame, index),
            value,
          )
        None => {
          self.fail("unsupported MIR interpreter assignment target")
          0L
        }
      }
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
  left_ty : @ctype.Type,
  right : Int64,
  right_ty : @ctype.Type,
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
  left_ty : @ctype.Type,
  right : Int64,
  right_ty : @ctype.Type,
) -> Int64 {
  match self.eval_pointer_binary(op, left, left_ty, right, right_ty) {
    Some(value) => return value
    None => ()
  }
  let left_value = @ctype.integer_constant(left, left_ty)
  let right_value = @ctype.integer_constant(right, right_ty)
  let result = match op {
    "+" => @ctype.integer_constant_binary_arith("+", left_value, right_value)
    "-" => @ctype.integer_constant_binary_arith("-", left_value, right_value)
    "*" => @ctype.integer_constant_binary_arith("*", left_value, right_value)
    "/" => @ctype.integer_constant_divide("/", left_value, right_value)
    "%" => @ctype.integer_constant_divide("%", left_value, right_value)
    "|" => @ctype.integer_constant_binary_arith("|", left_value, right_value)
    "&" => @ctype.integer_constant_binary_arith("&", left_value, right_value)
    "^" => @ctype.integer_constant_binary_arith("^", left_value, right_value)
    "<<" => @ctype.integer_constant_shift("<<", left_value, right_value)
    ">>" => @ctype.integer_constant_shift(">>", left_value, right_value)
    "==" =>
      Some(
        @ctype.integer_constant_bool(
          @ctype.integer_constant_equal_compare(left_value, right_value),
        ),
      )
    "!=" =>
      Some(
        @ctype.integer_constant_bool(
          !@ctype.integer_constant_equal_compare(left_value, right_value),
        ),
      )
    "<" =>
      Some(
        @ctype.integer_constant_bool(
          @ctype.integer_constant_rel_compare("<", left_value, right_value),
        ),
      )
    ">" =>
      Some(
        @ctype.integer_constant_bool(
          @ctype.integer_constant_rel_compare(">", left_value, right_value),
        ),
      )
    "<=" =>
      Some(
        @ctype.integer_constant_bool(
          @ctype.integer_constant_rel_compare("<=", left_value, right_value),
        ),
      )
    ">=" =>
      Some(
        @ctype.integer_constant_bool(
          @ctype.integer_constant_rel_compare(">=", left_value, right_value),
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
fn Interpreter::literal_string_pointer_if_known(
  self : Interpreter,
  frame : InterpFrame,
  expr : @parser.Expr,
) -> LiteralStringPointer? {
  match expr {
    String(value) =>
      Some({ value, base: self.string_literal_base(value), offset: 0L })
    Cast(_, inner) => self.literal_string_pointer_if_known(frame, inner)
    Var(name) =>
      if frame.locals.contains(name) {
        self.string_literal_pointer_at(frame.locals[name])
      } else if self.globals.contains(name) {
        self.string_literal_pointer_at(self.globals[name])
      } else {
        None
      }
    Binary("+", lhs, rhs) =>
      match self.literal_string_pointer_if_known(frame, lhs) {
        Some(ptr) =>
          Some({
            value: ptr.value,
            base: ptr.base,
            offset: ptr.offset + self.eval_expr(frame, rhs),
          })
        None =>
          match self.literal_string_pointer_if_known(frame, rhs) {
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
      match self.literal_string_pointer_if_known(frame, lhs) {
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
fn Interpreter::ignored_string_lvalue_address(
  self : Interpreter,
  frame : InterpFrame,
  expr : @parser.Expr,
) -> Int64? {
  match expr {
    Deref(AddrOf(target)) => self.ignored_string_lvalue_address(frame, target)
    Deref(target) =>
      match self.literal_string_pointer_if_known(frame, target) {
        Some(ptr) => Some(ptr.base + ptr.offset)
        None => None
      }
    ArrayAccess(base, index) =>
      match self.literal_string_pointer_if_known(frame, base) {
        Some(ptr) => Some(ptr.base + ptr.offset + self.eval_expr(frame, index))
        None => None
      }
    _ => None
  }
}

///|
fn Interpreter::read_string_byte_address(
  self : Interpreter,
  address : Int64,
) -> Int64? {
  match self.string_literal_pointer_at(address) {
    Some(ptr) => Some(string_literal_byte_at(ptr.value, ptr.offset))
    None => None
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
      match self.ignored_string_lvalue_address(frame, lhs) {
        Some(address) => {
          let value = self.eval_expr(frame, rhs)
          ignore(self.write_string_byte(address, value))
        }
        None =>
          if interpreter_can_write_lvalue(lhs) {
            ignore(self.eval_expr(frame, expr))
          } else {
            self.eval_ignored_expr_side_effects(frame, lhs)
            self.eval_ignored_expr_side_effects(frame, rhs)
          }
      }
    CompoundAssign(op, lhs, rhs) =>
      match self.ignored_string_lvalue_address(frame, lhs) {
        Some(address) =>
          match self.read_string_byte_address(address) {
            Some(old) => {
              let right = self.eval_expr(frame, rhs)
              let value = self.eval_binary_values(
                op,
                old,
                self.program.expr_type(lhs, frame.scope()),
                right,
                self.program.expr_type(rhs, frame.scope()),
              )
              ignore(self.write_string_byte(address, value))
            }
            None => self.eval_ignored_expr_side_effects(frame, rhs)
          }
        None =>
          if interpreter_can_write_lvalue(lhs) {
            ignore(self.eval_expr(frame, expr))
          } else {
            self.eval_ignored_expr_side_effects(frame, lhs)
            self.eval_ignored_expr_side_effects(frame, rhs)
          }
      }
    PrefixInc(target)
    | PrefixDec(target)
    | PostfixInc(target)
    | PostfixDec(target) =>
      match self.ignored_string_lvalue_address(frame, target) {
        Some(address) =>
          match self.read_string_byte_address(address) {
            Some(old) => {
              let value = match expr {
                PrefixInc(_) | PostfixInc(_) => old + 1L
                PrefixDec(_) | PostfixDec(_) => old - 1L
                _ => old
              }
              ignore(self.write_string_byte(address, value))
            }
            None => ()
          }
        None =>
          if interpreter_can_write_lvalue(target) {
            ignore(self.eval_expr(frame, expr))
          } else {
            self.eval_ignored_expr_side_effects(frame, target)
          }
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
    return @ctype.object_size_unknown(mode)
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
  match @ctype.floating_builtin_compare(name, left, right) {
    Some(result) => fp_class_bool(result)
    None => 0L
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
  match @ctype.floating_builtin_classify(name, value) {
    Some(result) => fp_class_bool(result)
    None => 0L
  }
}

///|
fn Interpreter::eval_builtin_abs(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
) -> Int64 {
  let value = self.program.runtime_cast_int(
    self.eval_first_call_arg_or_zero(frame, args),
    ty,
  )
  self.program.runtime_cast_int(if value < 0L { -value } else { value }, ty)
}

///|
fn Interpreter::eval_builtin_alignment(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
  kind : String,
) -> Int64 {
  if args.length() < 2 {
    return 0L
  }
  let value = self.eval_expr(frame, args[0])
  let align = self.eval_expr(frame, args[1])
  match kind {
    "is_aligned" => if (value & (align - 1L)) == 0L { 1L } else { 0L }
    "align_up" => (value + align - 1L) & -align
    "align_down" => value & -align
    _ => 0L
  }
}

///|
fn Interpreter::eval_builtin_identity_call(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
  side_effect_arg : Int,
) -> Int64 {
  let result = self.eval_first_call_arg_or_zero(frame, args)
  if side_effect_arg >= 0 && side_effect_arg < args.length() {
    self.eval_ignored_expr_side_effects(frame, args[side_effect_arg])
  }
  result
}

///|
fn Interpreter::eval_builtin_noop_call(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
  kind : String,
) -> Int64 {
  match kind {
    "eval_first" =>
      if args.length() > 0 {
        ignore(self.eval_expr(frame, args[0]))
      }
    "eval_all" =>
      for arg in args {
        self.eval_ignored_expr_side_effects(frame, arg)
      }
    "ignore_all" => ()
    _ => ()
  }
  0L
}

///|
fn Interpreter::eval_builtin_address_query(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
) -> Int64 {
  let level = if args.length() > 0 {
    self.eval_expr(frame, args[0])
  } else {
    0L
  }
  // The MIR oracle models address nullness only, not exact machine PCs/FPs.
  if level == 0L {
    1L
  } else {
    0L
  }
}

///|
fn Interpreter::eval_builtin_stack_alloc_call(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
  op : String,
) -> Int64 {
  let size = if args.length() > 0 { self.eval_expr(frame, args[0]) } else { 0L }
  let align_bits = if op == "alloca_align" && args.length() > 1 {
    self.eval_expr(frame, args[1])
  } else {
    128L
  }
  let align_bytes = if align_bits > 128L { align_bits / 8L } else { 16L }
  let ptr = if align_bytes > 1L {
    (self.next_alloca + align_bytes - 1L) / align_bytes * align_bytes
  } else {
    self.next_alloca
  }
  let bump = if size <= 0L { 16L } else { (size + 15L) & -16L }
  self.next_alloca = ptr + bump
  ptr
}

///|
fn Interpreter::eval_builtin_strlen_call(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
) -> Int64 {
  if args.length() == 0 {
    0L
  } else {
    match self.literal_string_pointer(frame, args[0]) {
      Some(ptr) => string_literal_c_length_from(ptr.value, ptr.offset)
      _ => {
        self.fail("unsupported MIR interpreter strlen argument")
        0L
      }
    }
  }
}

///|
fn Interpreter::eval_builtin_memory_libcall_return(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
  symbol : String,
) -> Int64? {
  match symbol {
    "memcpy" | "memmove" | "memset" =>
      Some(self.eval_return_first_call_arg(frame, args, 3))
    "strcpy" | "strcat" | "strncpy" | "strncat" =>
      Some(self.eval_return_first_call_arg(frame, args, args.length()))
    "mempcpy" => {
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
    "stpcpy" => {
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
    "stpncpy" => {
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
    _ => None
  }
}

///|
fn Interpreter::eval_builtin_strl_libcall_return(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
  symbol : String,
) -> Int64? {
  match symbol {
    "strlcpy" => {
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
    "strlcat" => {
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
    _ => None
  }
}

///|
fn printf_format_source_position(symbol : String) -> Int? {
  match symbol {
    "snprintf" => Some(2)
    "sprintf" => Some(1)
    "printf" => Some(0)
    _ => None
  }
}

///|
fn Interpreter::eval_builtin_printf_libcall_length(
  self : Interpreter,
  frame : InterpFrame,
  name : String,
  args : Array[@parser.Expr],
  symbol : String,
) -> Int64? {
  let format_source_position = match printf_format_source_position(symbol) {
    Some(position) => position
    None => return None
  }
  let source_indexes = match
    @ctype.builtin_printf_source_indexes(name, args.length()) {
    Some(indexes) => indexes
    None => return None
  }
  if source_indexes.length() <= format_source_position {
    return Some(0L)
  }
  let format_index = source_indexes[format_source_position]
  let first_value_index = if source_indexes.length() >
    format_source_position + 1 {
    source_indexes[format_source_position + 1]
  } else {
    args.length()
  }
  let values = self.eval_call_args(frame, args)
  match
    self.literal_printf_format_length(
      args[format_index],
      symbol,
      args,
      values,
      first_value_index,
    ) {
    Some(value) => Some(value)
    None => Some(0L)
  }
}

///|
fn Interpreter::eval_builtin_compare_libcall_return(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
  symbol : String,
) -> Int64? {
  match symbol {
    "strcmp" =>
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
    "strncmp" =>
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
    "memcmp" | "bcmp" =>
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
          self.fail("unsupported MIR interpreter " + symbol + " argument")
          Some(0L)
        }
      }
    _ => None
  }
}

///|
fn Interpreter::eval_builtin_search_libcall_return(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
  symbol : String,
) -> Int64? {
  match symbol {
    "strchr" | "strrchr" =>
      match self.literal_string_pointer(frame, args[0]) {
        Some(ptr) => {
          let offset = if symbol == "strrchr" {
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
    "memchr" =>
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
    "strstr" =>
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
    "memmem" =>
      match
        (
          self.literal_string_pointer(frame, args[0]),
          self.literal_string_pointer(frame, args[2]),
        ) {
        (Some(haystack), Some(needle)) => {
          let haystack_length = self.eval_expr(frame, args[1])
          let needle_length = self.eval_expr(frame, args[3])
          if haystack_length < 0L || needle_length < 0L {
            self.fail("unsupported MIR interpreter memmem length")
            Some(0L)
          } else {
            match
              string_literal_find_memory_from(
                haystack.value,
                haystack.offset,
                haystack_length,
                needle.value,
                needle.offset,
                needle_length,
              ) {
              Some(index) => Some(haystack.base + index)
              None => Some(0L)
            }
          }
        }
        _ => {
          self.fail("unsupported MIR interpreter memmem argument")
          Some(0L)
        }
      }
    _ => None
  }
}

///|
fn Interpreter::eval_builtin_span_libcall_return(
  self : Interpreter,
  frame : InterpFrame,
  args : Array[@parser.Expr],
  symbol : String,
) -> Int64? {
  match
    (
      self.literal_string_pointer(frame, args[0]),
      self.literal_string_pointer(frame, args[1]),
    ) {
    (Some(value), Some(set)) =>
      match symbol {
        "strspn" =>
          Some(
            string_literal_span_from(
              value.value,
              value.offset,
              set.value,
              set.offset,
              true,
            ),
          )
        "strcspn" =>
          Some(
            string_literal_span_from(
              value.value,
              value.offset,
              set.value,
              set.offset,
              false,
            ),
          )
        "strpbrk" => {
          let offset = string_literal_find_first_set_byte_from(
            value.value,
            value.offset,
            set.value,
            set.offset,
          )
          match offset {
            Some(index) => Some(value.base + index)
            None => Some(0L)
          }
        }
        _ => None
      }
    _ => {
      self.fail("unsupported MIR interpreter " + symbol + " argument")
      Some(0L)
    }
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
  ty : @ctype.Type,
  op : String,
  left : Int64,
  right : Int64,
) -> (Int64, Bool)? {
  let core = self.core_type(ty)
  match core.const_int_width() {
    Some(width) if width <= 64 =>
      Some(
        if core.const_is_unsigned() {
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
fn string_literal_byte_at(value : String, index : Int64) -> Int64 {
  if index < 0L || index >= value.length().to_int64() {
    0L
  } else {
    value[index.to_int()].to_int().to_int64()
  }
}

///|
fn string_literal_c_length_from(value : String, offset : Int64) -> Int64 {
  @ctype.string_literal_c_length_from(value, offset)
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
fn Interpreter::record_string_object(
  self : Interpreter,
  value : String,
  base : Int64,
) -> Unit {
  for i in 0..<=value.length() {
    let offset = i.to_int64()
    self.string_values[base + offset] = value
    self.string_offsets[base + offset] = offset
  }
}

///|
fn replace_string_byte(value : String, offset : Int64, byte : Int64) -> String? {
  if offset < 0L || offset >= value.length().to_int64() {
    None
  } else {
    let target = offset.to_int()
    let buf = StringBuilder::new()
    for i in 0..<value.length() {
      if i == target {
        buf.write_char((byte & 0xFFL).to_int().unsafe_to_char())
      } else {
        buf.write_char(value[i].to_int().unsafe_to_char())
      }
    }
    Some(buf.to_string())
  }
}

///|
fn Interpreter::write_string_byte(
  self : Interpreter,
  address : Int64,
  value : Int64,
) -> Int64 {
  if self.string_values.contains(address) &&
    self.string_offsets.contains(address) {
    let old_value = self.string_values[address]
    let offset = self.string_offsets[address]
    match replace_string_byte(old_value, offset, value) {
      Some(new_value) => {
        self.record_string_object(new_value, address - offset)
        value & 0xFFL
      }
      None => {
        self.fail("unsupported MIR interpreter string object write")
        0L
      }
    }
  } else {
    self.fail("unsupported MIR interpreter string object write")
    0L
  }
}

///|
fn Interpreter::fresh_string_object_base(
  self : Interpreter,
  value : String,
) -> Int64 {
  let base = self.next_string_base
  self.record_string_object(value, base)
  self.next_string_base += value.length().to_int64() + 16L
  base
}

///|
fn Interpreter::string_literal_base(
  self : Interpreter,
  value : String,
) -> Int64 {
  if self.string_bases.contains(value) {
    self.string_bases[value]
  } else {
    let base = self.fresh_string_object_base(value)
    self.string_bases[value] = base
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
  @ctype.string_literal_c_length(value)
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
fn string_literal_contains_c_byte_from(
  value : String,
  start_offset : Int64,
  byte : Int64,
) -> Bool {
  let needle = byte & 0xFFL
  let mut index = start_offset
  while true {
    let current = string_literal_byte_at(value, index)
    if current == 0L {
      return false
    }
    if current == needle {
      return true
    }
    index += 1L
  }
  false
}

///|
fn string_literal_span_from(
  value : String,
  start_offset : Int64,
  set : String,
  set_offset : Int64,
  accept : Bool,
) -> Int64 {
  let mut index = 0L
  while true {
    let current = string_literal_byte_at(value, start_offset + index)
    if current == 0L {
      return index
    }
    let present = string_literal_contains_c_byte_from(set, set_offset, current)
    if present != accept {
      return index
    }
    index += 1L
  }
  0L
}

///|
fn string_literal_find_first_set_byte_from(
  value : String,
  start_offset : Int64,
  set : String,
  set_offset : Int64,
) -> Int64? {
  let mut index = 0L
  while true {
    let current = string_literal_byte_at(value, start_offset + index)
    if current == 0L {
      return None
    }
    if string_literal_contains_c_byte_from(set, set_offset, current) {
      return Some(start_offset + index)
    }
    index += 1L
  }
  None
}

///|
fn string_literal_find_memory_from(
  haystack : String,
  start_offset : Int64,
  haystack_length : Int64,
  needle : String,
  needle_offset : Int64,
  needle_length : Int64,
) -> Int64? {
  if needle_length == 0L {
    return Some(start_offset)
  }
  if haystack_length < needle_length {
    return None
  }
  let mut start = 0L
  while start <= haystack_length - needle_length {
    let mut matched = true
    let mut i = 0L
    while i < needle_length {
      if string_literal_byte_at(haystack, start_offset + start + i) !=
        string_literal_byte_at(needle, needle_offset + i) {
        matched = false
      }
      i += 1L
    }
    if matched {
      return Some(start_offset + start)
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
  match @ctype.builtin_overflow_op(name) {
    Some(op) => return Some(self.eval_overflow_builtin(frame, op, args))
    None => ()
  }
  match @ctype.integer_count_builtin_info(name) {
    Some((kind, width)) => {
      let value = self.eval_first_call_arg_or_zero(frame, args)
      return match kind {
        "clz" => Some(@ctype.count_leading_zero_bits(value, width))
        "ctz" => Some(@ctype.count_trailing_zero_bits(value, width))
        "ffs" => Some(@ctype.first_set_bit(value, width))
        "popcount" => Some(@ctype.count_one_bits(value, width))
        "parity" => Some(@ctype.count_one_bits(value, width) & 1L)
        _ => None
      }
    }
    None => ()
  }
  match @ctype.integer_abs_builtin_type(name) {
    Some(ty) => return Some(self.eval_builtin_abs(frame, args, ty))
    None => ()
  }
  let first_arg_ty = if args.length() == 0 {
    @ctype.Type::UInt
  } else {
    self.program.expr_type(args[0], frame.scope())
  }
  match @ctype.integer_bswap_builtin_info(name, first_arg_ty) {
    Some((_, width)) =>
      return Some(
        @ctype.byte_swap_bits(
          self.eval_first_call_arg_or_zero(frame, args),
          width,
        ),
      )
    None => ()
  }
  match @ctype.integer_rotate_builtin_info(name, first_arg_ty) {
    Some((_, width, left)) => {
      if args.length() >= 2 {
        return Some(
          @ctype.rotate_bits(
            self.eval_expr(frame, args[0]),
            self.eval_expr(frame, args[1]),
            width,
            left,
          ),
        )
      }
      return Some(0L)
    }
    None => ()
  }
  match @ctype.integer_alignment_builtin_info(name, first_arg_ty) {
    Some((kind, _)) =>
      return Some(self.eval_builtin_alignment(frame, args, kind))
    None => ()
  }
  match @ctype.builtin_identity_call_info(name) {
    Some((_, side_effect_arg)) =>
      return Some(self.eval_builtin_identity_call(frame, args, side_effect_arg))
    None => ()
  }
  match @ctype.builtin_noop_call_info(name) {
    Some(kind) => return Some(self.eval_builtin_noop_call(frame, args, kind))
    None => ()
  }
  match @ctype.builtin_address_query_info(name) {
    Some(_) => return Some(self.eval_builtin_address_query(frame, args))
    None => ()
  }
  match @ctype.builtin_constant_query_call_info(name) {
    Some(kind) =>
      match
        @ctype.builtin_constant_query_result(
          kind,
          args.length() > 0 &&
          self.program.fold_const(args[0], frame.scope()) is Some(_),
        ) {
        Some(value) => return Some(value)
        None => ()
      }
    None => ()
  }
  match @ctype.builtin_fixed_int_constant_call_info(name) {
    Some((value, _)) => return Some(value)
    None => ()
  }
  match @ctype.builtin_object_size_call_info(name) {
    Some(_) => return Some(self.eval_builtin_object_size(frame, args))
    None => ()
  }
  match @ctype.floating_builtin_compare_op(name) {
    Some(_) => return Some(self.eval_builtin_fp_compare(frame, name, args))
    None => ()
  }
  match @ctype.floating_builtin_runtime_class_info(name) {
    Some(_) => return Some(self.eval_builtin_fp_class(frame, name, args))
    None => ()
  }
  match @ctype.builtin_va_setup_call_info(name) {
    Some(_) => return Some(0L)
    None => ()
  }
  match @ctype.builtin_zero_memory_call_info(name) {
    Some(_) => {
      ignore(self.eval_call_args(frame, args))
      return Some(0L)
    }
    None => ()
  }
  match @ctype.builtin_stack_alloc_call_info(name) {
    Some((op, _)) =>
      return Some(self.eval_builtin_stack_alloc_call(frame, args, op))
    None => ()
  }
  match @ctype.builtin_length_libcall_info(name, 1) {
    Some(("strlen", _)) =>
      return Some(self.eval_builtin_strlen_call(frame, args))
    _ => ()
  }
  match @ctype.builtin_memory_libcall_info(name, args.length()) {
    Some((symbol, _)) =>
      match self.eval_builtin_memory_libcall_return(frame, args, symbol) {
        Some(value) => return Some(value)
        None => ()
      }
    None => ()
  }
  match @ctype.builtin_strl_libcall_info(name, args.length()) {
    Some((symbol, _)) =>
      match self.eval_builtin_strl_libcall_return(frame, args, symbol) {
        Some(value) => return Some(value)
        None => ()
      }
    None => ()
  }
  match @ctype.builtin_printf_libcall_symbol(name, args.length()) {
    Some(symbol) =>
      match self.eval_builtin_printf_libcall_length(frame, name, args, symbol) {
        Some(value) => return Some(value)
        None => ()
      }
    None => ()
  }
  match @ctype.builtin_compare_libcall_info(name, args.length()) {
    Some((symbol, _)) =>
      match self.eval_builtin_compare_libcall_return(frame, args, symbol) {
        Some(value) => return Some(value)
        None => ()
      }
    None => ()
  }
  match @ctype.builtin_search_libcall_info(name, args.length()) {
    Some((symbol, _)) =>
      match self.eval_builtin_search_libcall_return(frame, args, symbol) {
        Some(value) => return Some(value)
        None => ()
      }
    None => ()
  }
  match @ctype.builtin_span_libcall_info(name, args.length()) {
    Some((symbol, _)) =>
      match self.eval_builtin_span_libcall_return(frame, args, symbol) {
        Some(value) => return Some(value)
        None => ()
      }
    None => ()
  }
  match name {
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
    Number(value, _, _) => value
    FloatLiteral(_, _) => {
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
      let ty = self.program.expr_type(operand, scope).integer_promote()
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
    AddrOf(ArrayAccess(base, index)) =>
      match self.literal_string_pointer(frame, base) {
        Some(ptr) => ptr.base + ptr.offset + self.eval_expr(frame, index)
        None => {
          self.fail("unsupported MIR interpreter memory expression")
          0L
        }
      }
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
    SizeofExpr(String(value)) => @ctype.string_literal_object_size(value)
    SizeofExpr(e) =>
      self.program.type_size(self.program.expr_type(e, scope)).to_int64()
    Alignof(ty) => self.program.type_align(ty).to_int64()
    AlignofExpr(String(value)) =>
      self.program
      .type_align(Array(SChar, @ctype.string_literal_array_length(value)))
      .to_int64()
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
  ty : @ctype.Type,
  name : String,
  init : @parser.Expr?,
) -> Unit {
  if !self.program.runtime_int_type(ty) {
    if self.init_local_string_array(frame, ty, name, init) {
      return
    }
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
  init : Array[@parser.Stmt],
  cond : @parser.Expr,
  inc : @parser.Expr?,
  body : @parser.Stmt,
) -> ExecFlow {
  for stmt in init {
    match self.exec_stmt(frame, stmt) {
      Normal => ()
      flow => return flow
    }
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
/// Which clause of a `switch` control transfers to.
priv enum SwitchTarget {
  /// The control value, already cast to the promoted control type.
  CaseValue(Int64)
  DefaultClause
}

///|
/// Collects the clauses one `switch` owns, in source order: `Some(value)` for
/// `case value:` and `None` for `default:`.
///
/// A nested `switch` owns its own clauses, so the walk stops there.
fn collect_switch_clauses(stmt : @parser.Stmt, out : Array[Int64?]) -> Unit {
  match stmt {
    Case(value, body) => {
      out.push(Some(value))
      collect_switch_clauses(body, out)
    }
    Default(body) => {
      out.push(None)
      collect_switch_clauses(body, out)
    }
    Label(_, body) => collect_switch_clauses(body, out)
    Compound(stmts) =>
      for nested in stmts {
        collect_switch_clauses(nested, out)
      }
    If(_, then_, else_) => {
      collect_switch_clauses(then_, out)
      if else_ is Some(alternative) {
        collect_switch_clauses(alternative, out)
      }
    }
    While(_, body) | DoWhile(_, body) => collect_switch_clauses(body, out)
    For(init, _, _, body) => {
      for nested in init {
        collect_switch_clauses(nested, out)
      }
      collect_switch_clauses(body, out)
    }
    Switch(_, _) => ()
    _ => ()
  }
}

///|
/// Reports whether `stmt` is the clause `target` selects.
fn Interpreter::stmt_starts_switch_target(
  self : Interpreter,
  stmt : @parser.Stmt,
  target : SwitchTarget,
  control_ty : @ctype.Type,
) -> Bool {
  match (stmt, target) {
    (Case(value, _), CaseValue(wanted)) =>
      self.program.runtime_cast_int(value, control_ty) == wanted
    (Default(_), DefaultClause) => true
    _ => false
  }
}

///|
/// Executes `stmt` from whichever of its leading labels `matches` selects.
///
/// Only leading labels count: control enters a clause at its own label, and a
/// statement reached by falling through carries no label of its own.
fn Interpreter::exec_stmt_from_leading_label(
  self : Interpreter,
  frame : InterpFrame,
  stmt : @parser.Stmt,
  matches : (@parser.Stmt) -> Bool,
) -> (Bool, ExecFlow) {
  match stmt {
    Case(_, body) | Default(body) | Label(_, body) =>
      if matches(stmt) {
        (true, self.exec_stmt(frame, body))
      } else {
        self.exec_stmt_from_leading_label(frame, body, matches)
      }
    _ => (false, Normal)
  }
}

///|
fn Interpreter::exec_switch_body(
  self : Interpreter,
  frame : InterpFrame,
  body : @parser.Stmt,
  target : SwitchTarget,
  control_ty : @ctype.Type,
) -> ExecFlow {
  let stmts = match body {
    Compound(stmts) => stmts
    _ => {
      self.fail("unsupported MIR interpreter switch body")
      return Normal
    }
  }
  let matches = stmt => self.stmt_starts_switch_target(stmt, target, control_ty)
  let mut active = false
  let mut found = false
  for stmt in stmts {
    if !active {
      if matches(stmt) {
        active = true
        found = true
      } else {
        let (nested_found, flow) = self.exec_stmt_from_leading_label(
          frame, stmt, matches,
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
    }
    match self.exec_stmt(frame, stmt) {
      Normal => ()
      Broke => return Normal
      flow => return flow
    }
  }
  if !found {
    // The clause exists -- it was found by the walk in `exec_switch` -- but it
    // is nested somewhere control cannot enter from here, such as inside a
    // block or a loop within the switch body.
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
) -> ExecFlow {
  let control_ty = self.program.switch_control_type(
    self.program.expr_type(expr, frame.scope()),
  )
  let control_value = self.program.runtime_cast_int(
    self.eval_expr(frame, expr),
    control_ty,
  )
  let clauses : Array[Int64?] = []
  collect_switch_clauses(body, clauses)
  let mut target : SwitchTarget? = None
  for clause in clauses {
    if clause is Some(value) &&
      self.program.runtime_cast_int(value, control_ty) == control_value {
      target = Some(CaseValue(control_value))
      break
    }
  }
  if target is None && clauses.iter().any(clause => clause is None) {
    target = Some(DefaultClause)
  }
  match target {
    Some(selected) => self.exec_switch_body(frame, body, selected, control_ty)
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
    Compound(stmts) => self.exec_block(frame, stmts)
    VarDecl(ty, name, init) => {
      self.declare_local(frame, ty, name, init)
      Normal
    }
    Break => Broke
    Continue => Continued
    Switch(expr, body) => self.exec_switch(frame, expr, body)
    Goto(name) => Jump(name)
    ComputedGoto(_) => {
      self.fail("unsupported MIR interpreter control statement")
      Normal
    }
    Case(_, body) | Default(body) | Label(_, body) =>
      self.exec_stmt(frame, body)
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
    Compound(stmts) => stmts
    _ => {
      self.fail("unsupported MIR interpreter goto body")
      return Normal
    }
  }
  let matches = (stmt : @parser.Stmt) => {
    stmt is Label(name, _) && name == target
  }
  let mut active = false
  let mut found = false
  for stmt in stmts {
    if !active {
      if matches(stmt) {
        active = true
        found = true
      } else {
        let (nested_found, flow) = self.exec_stmt_from_leading_label(
          frame, stmt, matches,
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
