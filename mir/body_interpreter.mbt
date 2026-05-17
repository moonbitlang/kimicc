///|
priv enum BodyFlow {
  BodyNormal
  BodyReturned(Int64)
  BodyBroke
  BodyContinued
  BodyJump(String)
}

///|
priv struct BodyFrame {
  locals : Map[Int, Int64]
  bindings : Map[Int, MirLocal]
  memory : Map[Int64, Int64]
}

///|
priv struct BodyInterpreter {
  program : Program
  globals : Map[String, Int64]
  global_memory : Map[Int64, Int64]
  global_addrs : Map[String, Int64]
  func_addrs : Map[String, Int64]
  func_names : Map[Int64, String]
  string_memory : Map[Int64, Int64]
  string_addrs : Map[String, Int64]
  mut error : String?
  mut steps : Int
  mut call_depth : Int
}

///|
fn mir_body_array_len(ty : @parser.Type) -> Int? {
  match ty {
    Array(_, len) => Some(len)
    Aligned(inner, _) => mir_body_array_len(inner)
    _ => None
  }
}

///|
fn mir_body_array_info(ty : @parser.Type) -> (@parser.Type, Int)? {
  match ty {
    Array(elem, len) => Some((elem, len))
    Aligned(inner, _) => mir_body_array_info(inner)
    _ => None
  }
}

///|
fn Program::mir_body_addressable_global_type(
  self : Program,
  ty : @parser.Type,
) -> Bool {
  if mir_body_scalar_type(ty) || mir_body_array_local_type(ty) {
    true
  } else {
    match self.core_type(ty) {
      Struct(_) | Union(_) => true
      _ => false
    }
  }
}

///|
fn mir_body_global_scalar_init(init : MirGlobalInit?) -> Int64? {
  match init {
    Some(MirGlobalScalarInt(bits)) => Some(bits)
    _ => None
  }
}

///|
fn mir_body_global_array_init(
  init : MirGlobalInit?,
) -> Array[(Int, MirGlobalInit)]? {
  match init {
    Some(MirGlobalArray(items)) => {
      let values : Array[(Int, MirGlobalInit)] = []
      for i = 0; i < items.length(); i = i + 1 {
        values.push((i, items[i]))
      }
      Some(values)
    }
    Some(MirGlobalArraySparse(items)) => Some(items)
    _ => None
  }
}

///|
fn BodyInterpreter::new(program : Program) -> BodyInterpreter {
  let globals : Map[String, Int64] = {}
  let global_memory : Map[Int64, Int64] = {}
  let global_addrs : Map[String, Int64] = {}
  let func_addrs : Map[String, Int64] = {}
  let func_names : Map[Int64, String] = {}
  for i in 0..<program.decls.length() {
    let name = program.decls[i].name
    let addr = 3000000000L + i.to_int64() * 100000L
    func_addrs[name] = addr
    func_names[addr] = name
  }
  let mut next_global = 0
  for decl in program.globals.values() {
    if program.mir_body_addressable_global_type(decl.ty) {
      let base = 1000000000L + next_global.to_int64() * 100000L
      global_addrs[decl.name] = base
      next_global += 1
    }
    if mir_body_scalar_type(decl.ty) {
      let value = match mir_body_global_scalar_init(decl.init) {
        Some(bits) => bits
        None => 0L
      }
      globals[decl.name] = program.runtime_cast_int(value, decl.ty)
    } else {
      match
        (mir_body_array_info(decl.ty), mir_body_global_array_init(decl.init)) {
        (Some((elem_ty, len)), Some(items)) => {
          if !global_addrs.contains(decl.name) || !mir_body_scalar_type(elem_ty) {
            continue
          }
          let base = global_addrs[decl.name]
          for item in items {
            let index = item.0
            let init = item.1
            if index < 0 || index >= len {
              continue
            }
            match mir_body_global_scalar_init(Some(init)) {
              Some(bits) =>
                global_memory[base - index.to_int64()] = program.runtime_cast_int(
                  bits, elem_ty,
                )
              None => ()
            }
          }
        }
        _ => ()
      }
    }
  }
  {
    program,
    globals,
    global_memory,
    global_addrs,
    func_addrs,
    func_names,
    string_memory: {},
    string_addrs: {},
    error: None,
    steps: 0,
    call_depth: 0,
  }
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
fn mir_body_local_addr(binding : MirLocal) -> Int64 {
  -1000000000L - binding.id.to_int64() * 100000L
}

///|
fn mir_body_elem_addr(base : Int64, index : Int64) -> Int64 {
  base - index
}

///|
fn mir_body_offset_addr(base : Int64, offset : Int) -> Int64 {
  base - 50000L - offset.to_int64()
}

///|
fn BodyInterpreter::string_literal_base(
  self : BodyInterpreter,
  value : String,
) -> Int64 {
  match self.string_addrs.get(value) {
    Some(base) => base
    None => {
      let base = 2000000000L + self.string_addrs.length().to_int64() * 100000L
      self.string_addrs[value] = base
      for i in 0..<value.length() {
        self.string_memory[base - i.to_int64()] = value[i].to_int().to_int64()
      }
      self.string_memory[base - value.length().to_int64()] = 0L
      base
    }
  }
}

///|
fn BodyInterpreter::string_array_elem_addr(
  self : BodyInterpreter,
  addr : Int64,
) -> Bool {
  for value in self.string_addrs.keys() {
    let base = self.string_addrs[value]
    let len = value.length() + 1
    if addr <= base && addr > base - len.to_int64() {
      return true
    }
  }
  false
}

///|
fn BodyInterpreter::global_for_addr(
  self : BodyInterpreter,
  addr : Int64,
) -> String? {
  for name in self.global_addrs.keys() {
    if self.global_addrs[name] == addr {
      return Some(name)
    }
  }
  None
}

///|
fn BodyInterpreter::global_array_elem_addr(
  self : BodyInterpreter,
  addr : Int64,
) -> Bool {
  for name in self.global_addrs.keys() {
    match self.program.globals.get(name) {
      Some(decl) =>
        match self.program.core_type(decl.ty) {
          Struct(_) | Union(_) => {
            let base = mir_body_offset_addr(self.global_addrs[name], 0)
            let size = self.program.type_size(decl.ty).to_int64()
            if addr <= base && addr > base - size {
              return true
            }
          }
          _ =>
            match mir_body_array_len(decl.ty) {
              Some(len) => {
                let base = self.global_addrs[name]
                if addr <= base && addr > base - len.to_int64() {
                  return true
                }
              }
              None => ()
            }
        }
      None => ()
    }
  }
  false
}

///|
fn BodyFrame::binding_for_addr(self : BodyFrame, addr : Int64) -> MirLocal? {
  for binding in self.bindings.values() {
    if mir_body_local_addr(binding) == addr {
      return Some(binding)
    }
  }
  None
}

///|
fn BodyInterpreter::aggregate_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
) -> Bool {
  for binding in frame.bindings.values() {
    match self.program.core_type(binding.ty) {
      Struct(_) | Union(_) => {
        let base = mir_body_offset_addr(mir_body_local_addr(binding), 0)
        let size = self.program.type_size(binding.ty).to_int64()
        if addr <= base && addr > base - size {
          return true
        }
      }
      _ => ()
    }
  }
  false
}

///|
fn BodyFrame::array_elem_addr(self : BodyFrame, addr : Int64) -> Bool {
  for binding in self.bindings.values() {
    match binding.ty {
      Array(_, len) => {
        let base = mir_body_local_addr(binding)
        if addr <= base && addr > base - len.to_int64() {
          return true
        }
      }
      Aligned(inner, _) =>
        match inner {
          Array(_, len) => {
            let base = mir_body_local_addr(binding)
            if addr <= base && addr > base - len.to_int64() {
              return true
            }
          }
          _ => ()
        }
      _ => ()
    }
  }
  false
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
  match self.eval_pointer_binary_values(op, left, left_ty, right, right_ty) {
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
      self.fail("unsupported MIR body binary operator: " + op)
      0L
    }
  }
}

///|
fn BodyInterpreter::eval_pointer_binary_values(
  self : BodyInterpreter,
  op : String,
  left : Int64,
  left_ty : @parser.Type,
  right : Int64,
  right_ty : @parser.Type,
) -> Int64? {
  match self.program.pointer_element(left_ty) {
    Some(_) =>
      if right_ty.is_integer() {
        if op == "+" {
          return Some(left - right)
        } else if op == "-" {
          return Some(left + right)
        }
      }
    None => ()
  }
  match self.program.pointer_element(right_ty) {
    Some(_) =>
      if op == "+" && left_ty.is_integer() {
        return Some(right - left)
      } else if op == "-" && self.program.pointer_element(left_ty) is Some(_) {
        return Some(right - left)
      }
    None => ()
  }
  None
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
    MirAddrLocal(binding) => mir_body_local_addr(binding)
    MirAddrGlobal(name, _) =>
      match self.global_addrs.get(name) {
        Some(addr) => addr
        None => {
          self.fail("unknown MIR body global address: " + name)
          0L
        }
      }
    MirFuncAddr(name, _) =>
      match self.func_addrs.get(name) {
        Some(addr) => addr
        None => {
          self.fail("unknown MIR body function address: " + name)
          0L
        }
      }
    MirStringAddr(value) => self.string_literal_base(value)
    MirElemAddr(base, index, _) =>
      mir_body_elem_addr(
        self.eval_value(frame, base),
        self.eval_value(frame, index),
      )
    MirOffsetAddr(base, offset, _) =>
      mir_body_offset_addr(self.eval_value(frame, base), offset)
    MirLoad(ptr, ty) => {
      let addr = self.eval_value(frame, ptr)
      if frame.array_elem_addr(addr) {
        let value = match frame.memory.get(addr) {
          Some(value) => value
          None => 0L
        }
        self.program.runtime_cast_int(value, ty)
      } else if self.global_array_elem_addr(addr) {
        let value = match self.global_memory.get(addr) {
          Some(value) => value
          None => 0L
        }
        self.program.runtime_cast_int(value, ty)
      } else if self.string_array_elem_addr(addr) {
        let value = match self.string_memory.get(addr) {
          Some(value) => value
          None => 0L
        }
        self.program.runtime_cast_int(value, ty)
      } else if self.aggregate_addr(frame, addr) {
        let value = match frame.memory.get(addr) {
          Some(value) => value
          None => 0L
        }
        self.program.runtime_cast_int(value, ty)
      } else {
        match frame.binding_for_addr(addr) {
          Some(binding) =>
            if frame.locals.contains(binding.id) {
              self.program.runtime_cast_int(frame.locals[binding.id], ty)
            } else {
              self.fail("unknown MIR body local value: " + binding.name)
              0L
            }
          None =>
            match self.global_for_addr(addr) {
              Some(name) =>
                if self.globals.contains(name) {
                  self.program.runtime_cast_int(self.globals[name], ty)
                } else {
                  self.fail("unknown MIR body global value: " + name)
                  0L
                }
              None => {
                self.fail("unsupported MIR body load address")
                0L
              }
            }
        }
      }
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
      if name == "__sync_synchronize" &&
        args.length() == 0 &&
        self.program.core_type(ty) is Void {
        return 0L
      }
      if (
          name == "__atomic_thread_fence" ||
          name == "__atomic_signal_fence" ||
          name == "__c11_atomic_thread_fence" ||
          name == "__c11_atomic_signal_fence"
        ) &&
        args.length() == 1 &&
        self.program.core_type(ty) is Void {
        ignore(self.eval_value(frame, args[0]))
        return 0L
      }
      if (
          name == "__builtin_frame_address" ||
          name == "__builtin_return_address"
        ) &&
        args.length() <= 1 &&
        self.program.core_type(ty) is Pointer(_) {
        let level = if args.length() == 0 {
          0L
        } else {
          self.eval_value(frame, args[0])
        }
        return if level == 0L { 1L } else { 0L }
      }
      let values : Array[Int64] = []
      for arg in args {
        values.push(self.eval_value(frame, arg))
      }
      self.program.runtime_cast_int(self.call_func(name, values), ty)
    }
    MirIndirectCall(callee, args, ty) => {
      let addr = self.eval_value(frame, callee)
      let name = match self.func_names.get(addr) {
        Some(name) => name
        None => {
          self.fail("unknown MIR body indirect call target")
          return 0L
        }
      }
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
    MirStore(ptr, rhs, ty) => {
      let addr = self.eval_value(frame, ptr)
      if frame.array_elem_addr(addr) {
        let assigned = self.program.runtime_cast_int(
          self.eval_value(frame, rhs),
          ty,
        )
        frame.memory[addr] = assigned
        assigned
      } else if self.global_array_elem_addr(addr) {
        let assigned = self.program.runtime_cast_int(
          self.eval_value(frame, rhs),
          ty,
        )
        self.global_memory[addr] = assigned
        assigned
      } else if self.aggregate_addr(frame, addr) {
        let assigned = self.program.runtime_cast_int(
          self.eval_value(frame, rhs),
          ty,
        )
        frame.memory[addr] = assigned
        assigned
      } else {
        match frame.binding_for_addr(addr) {
          Some(binding) => {
            let assigned = self.program.runtime_cast_int(
              self.eval_value(frame, rhs),
              binding.ty,
            )
            frame.locals[binding.id] = assigned
            self.program.runtime_cast_int(assigned, ty)
          }
          None =>
            match self.global_for_addr(addr) {
              Some(name) => {
                let assigned = self.program.runtime_cast_int(
                  self.eval_value(frame, rhs),
                  ty,
                )
                self.globals[name] = assigned
                assigned
              }
              None => {
                self.fail("unsupported MIR body store address")
                0L
              }
            }
        }
      }
    }
    MirPostUpdateLocal(binding, op, rhs, ty) => {
      let old = if frame.locals.contains(binding.id) {
        self.program.runtime_cast_int(frame.locals[binding.id], binding.ty)
      } else {
        self.fail("unknown MIR body local value: " + binding.name)
        0L
      }
      let right = self.eval_value(frame, rhs)
      let updated = self.program.runtime_cast_int(
        self.eval_binary_values(op, old, binding.ty, right, rhs.ty()),
        binding.ty,
      )
      frame.locals[binding.id] = updated
      self.program.runtime_cast_int(old, ty)
    }
    MirPreUpdateMemory(ptr, op, rhs, ty) => {
      let addr = self.eval_value(frame, ptr)
      let old = if frame.array_elem_addr(addr) ||
        self.global_array_elem_addr(addr) ||
        self.aggregate_addr(frame, addr) {
        let memory = if self.global_array_elem_addr(addr) {
          self.global_memory
        } else {
          frame.memory
        }
        match memory.get(addr) {
          Some(value) => self.program.runtime_cast_int(value, ty)
          None => 0L
        }
      } else {
        match frame.binding_for_addr(addr) {
          Some(binding) =>
            if frame.locals.contains(binding.id) {
              self.program.runtime_cast_int(frame.locals[binding.id], ty)
            } else {
              self.fail("unknown MIR body local value: " + binding.name)
              0L
            }
          None =>
            match self.global_for_addr(addr) {
              Some(name) =>
                if self.globals.contains(name) {
                  self.program.runtime_cast_int(self.globals[name], ty)
                } else {
                  self.fail("unknown MIR body global value: " + name)
                  0L
                }
              None => {
                self.fail("unsupported MIR body pre-update address")
                0L
              }
            }
        }
      }
      let right = self.eval_value(frame, rhs)
      let updated = self.program.runtime_cast_int(
        self.eval_binary_values(op, old, ty, right, rhs.ty()),
        ty,
      )
      if self.global_array_elem_addr(addr) {
        self.global_memory[addr] = updated
      } else if frame.array_elem_addr(addr) || self.aggregate_addr(frame, addr) {
        frame.memory[addr] = updated
      } else {
        match frame.binding_for_addr(addr) {
          Some(binding) => frame.locals[binding.id] = updated
          None =>
            match self.global_for_addr(addr) {
              Some(name) => self.globals[name] = updated
              None => ()
            }
        }
      }
      updated
    }
    MirPostUpdateMemory(ptr, op, rhs, ty) => {
      let addr = self.eval_value(frame, ptr)
      let old = if frame.array_elem_addr(addr) ||
        self.global_array_elem_addr(addr) ||
        self.aggregate_addr(frame, addr) {
        let memory = if self.global_array_elem_addr(addr) {
          self.global_memory
        } else {
          frame.memory
        }
        match memory.get(addr) {
          Some(value) => self.program.runtime_cast_int(value, ty)
          None => 0L
        }
      } else {
        match frame.binding_for_addr(addr) {
          Some(binding) =>
            if frame.locals.contains(binding.id) {
              self.program.runtime_cast_int(frame.locals[binding.id], ty)
            } else {
              self.fail("unknown MIR body local value: " + binding.name)
              0L
            }
          None =>
            match self.global_for_addr(addr) {
              Some(name) =>
                if self.globals.contains(name) {
                  self.program.runtime_cast_int(self.globals[name], ty)
                } else {
                  self.fail("unknown MIR body global value: " + name)
                  0L
                }
              None => {
                self.fail("unsupported MIR body post-update address")
                0L
              }
            }
        }
      }
      let right = self.eval_value(frame, rhs)
      let updated = self.program.runtime_cast_int(
        self.eval_binary_values(op, old, ty, right, rhs.ty()),
        ty,
      )
      if self.global_array_elem_addr(addr) {
        self.global_memory[addr] = updated
      } else if frame.array_elem_addr(addr) || self.aggregate_addr(frame, addr) {
        frame.memory[addr] = updated
      } else {
        match frame.binding_for_addr(addr) {
          Some(binding) => frame.locals[binding.id] = updated
          None =>
            match self.global_for_addr(addr) {
              Some(name) => self.globals[name] = updated
              None => ()
            }
        }
      }
      self.program.runtime_cast_int(old, ty)
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
fn BodyInterpreter::exec_switch_body(
  self : BodyInterpreter,
  frame : BodyFrame,
  body : Array[MirStmt],
  target : String,
) -> BodyFlow {
  let mut active = false
  let mut found = false
  for stmt in body {
    if !active {
      match stmt {
        MirLabel(name) if name == target => {
          active = true
          found = true
        }
        _ => continue
      }
    }
    match self.exec_stmt(frame, stmt) {
      BodyNormal => ()
      BodyBroke => return BodyNormal
      flow => return flow
    }
  }
  if !found {
    self.fail("unknown MIR body switch label: " + target)
  }
  BodyNormal
}

///|
fn BodyInterpreter::exec_switch(
  self : BodyInterpreter,
  frame : BodyFrame,
  control : MirValue,
  cases : Array[(Int64?, String)],
  body : Array[MirStmt],
) -> BodyFlow {
  let control_ty = self.program.switch_control_type(control.ty())
  let control_value = self.program.runtime_cast_int(
    self.eval_value(frame, control),
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
    Some(label) => self.exec_switch_body(frame, body, label)
    None => BodyNormal
  }
}

///|
fn BodyInterpreter::exec_stmts_from_label(
  self : BodyInterpreter,
  frame : BodyFrame,
  stmts : Array[MirStmt],
  target : String,
) -> BodyFlow {
  let mut active = false
  for stmt in stmts {
    if !active {
      match stmt {
        MirLabel(name) if name == target => active = true
        _ => continue
      }
    }
    match self.exec_stmt(frame, stmt) {
      BodyNormal => ()
      flow => return flow
    }
    if self.failed() {
      return BodyNormal
    }
  }
  if !active {
    self.fail("unknown MIR body label: " + target)
  }
  BodyNormal
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
          BodyBroke => return BodyNormal
          BodyContinued => ()
          BodyJump(name) => return BodyJump(name)
        }
      }
      BodyNormal
    }
    MirFor(init, cond, inc, body) => {
      match self.exec_stmts(frame, init) {
        BodyNormal => ()
        BodyReturned(value) => return BodyReturned(value)
        BodyBroke => return BodyNormal
        BodyContinued => ()
        BodyJump(name) => return BodyJump(name)
      }
      while self.eval_value(frame, cond) != 0L && !self.failed() {
        match self.exec_stmts(frame, body) {
          BodyNormal => ()
          BodyReturned(value) => return BodyReturned(value)
          BodyBroke => return BodyNormal
          BodyContinued => ()
          BodyJump(name) => return BodyJump(name)
        }
        match inc {
          Some(value) => ignore(self.eval_value(frame, value))
          None => ()
        }
      }
      BodyNormal
    }
    MirDoWhile(cond, body) => {
      let mut keep_running = true
      while keep_running && !self.failed() {
        match self.exec_stmts(frame, body) {
          BodyNormal => ()
          BodyReturned(value) => return BodyReturned(value)
          BodyBroke => return BodyNormal
          BodyContinued => ()
          BodyJump(name) => return BodyJump(name)
        }
        keep_running = self.eval_value(frame, cond) != 0L
      }
      BodyNormal
    }
    MirSwitch(control, cases, body) =>
      self.exec_switch(frame, control, cases, body)
    MirLabel(_) => BodyNormal
    MirGoto(name) => BodyJump(name)
    MirBreak => BodyBroke
    MirContinue => BodyContinued
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
      BodyBroke => return BodyBroke
      BodyContinued => return BodyContinued
      BodyJump(name) => return BodyJump(name)
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
  let bindings : Map[Int, MirLocal] = {}
  for binding in body.locals {
    bindings[binding.id] = binding
  }
  let frame = { locals: {}, bindings, memory: {} }
  for i in 0..<body.params.length() {
    let param = body.params[i]
    frame.locals[param.id] = self.program.runtime_cast_int(args[i], param.ty)
  }
  let result = match self.exec_stmts(frame, body.body) {
    BodyJump(name) => {
      let mut flow = self.exec_stmts_from_label(frame, body.body, name)
      while flow is BodyJump(_) && !self.failed() {
        match flow {
          BodyJump(next) =>
            flow = self.exec_stmts_from_label(frame, body.body, next)
          _ => ()
        }
      }
      match flow {
        BodyReturned(value) => self.program.runtime_cast_int(value, body.ret)
        BodyNormal => 0L
        BodyBroke => {
          self.fail("break escaped MIR body function")
          0L
        }
        BodyContinued => {
          self.fail("continue escaped MIR body function")
          0L
        }
        BodyJump(_) => 0L
      }
    }
    BodyReturned(value) => self.program.runtime_cast_int(value, body.ret)
    BodyNormal => 0L
    BodyBroke => {
      self.fail("break escaped MIR body function")
      0L
    }
    BodyContinued => {
      self.fail("continue escaped MIR body function")
      0L
    }
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
