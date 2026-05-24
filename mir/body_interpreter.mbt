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
  base : Int64
  locals : Map[Int, Int64]
  bindings : Map[Int, MirLocal]
  memory : Map[Int64, Int64]
  variadic_args : Array[Int64]
  va_list_indices : Map[Int, Int]
  aggregate_arg_bases : Map[Int64, Int]
  alloca_bases : Map[Int64, Int64]
}

///|
fn BodyFrame::aggregate_arg_addr(self : BodyFrame, addr : Int64) -> Bool {
  for base in self.aggregate_arg_bases.keys() {
    let size = self.aggregate_arg_bases[base].to_int64()
    if addr <= base && addr > base - size {
      return true
    }
  }
  false
}

///|
fn mir_body_va_list_handle(local_id : Int) -> Int64 {
  5000000000L + local_id.to_int64()
}

///|
fn mir_body_va_list_handle_local_id(handle : Int64) -> Int? {
  let base = 5000000000L
  if handle < base {
    None
  } else {
    Some((handle - base).to_int())
  }
}

///|
fn mir_body_va_arg_aggregate_addr(local_id : Int, index : Int) -> Int64 {
  6000000000L + local_id.to_int64() * 100000L + index.to_int64() * 1000L
}

///|
fn mir_body_va_list_local(value : MirValue) -> MirLocal? {
  match value {
    MirLocal(binding) => Some(binding)
    MirCast(_, inner) => mir_body_va_list_local(inner)
    _ => None
  }
}

///|
priv struct BodyAggregateArgData {
  ty : @ctype.Type
  slots : Map[Int64, Int64]
}

///|
priv struct BodyInterpreter {
  program : Program
  globals : Map[String, Int64]
  global_memory : Map[Int64, Int64]
  global_addrs : Map[String, Int64]
  func_addrs : Map[String, Int64]
  func_names : Map[Int64, String]
  label_addrs : Map[String, Int64]
  label_names : Map[Int64, String]
  string_memory : Map[Int64, Int64]
  string_addrs : Map[String, Int64]
  aggregate_args : Map[Int64, BodyAggregateArgData]
  stack_locals : Map[Int64, Int64]
  stack_bindings : Map[Int64, MirLocal]
  stack_memory : Map[Int64, Int64]
  stack_memory_ranges : Map[Int64, Int64]
  alloca_memory_ranges : Map[Int64, Int64]
  heap_memory_ranges : Map[Int64, Int64]
  mut error : String?
  mut steps : Int
  mut call_depth : Int
  mut strtok_next : Int64
  mut next_frame : Int64
  mut next_alloca : Int64
  mut next_aggregate_arg : Int64
}

///|
fn mir_body_array_info(ty : @ctype.Type) -> (@ctype.Type, Int)? {
  match ty {
    Array(elem, len) => Some((elem, len))
    Aligned(inner, _) => mir_body_array_info(inner)
    _ => None
  }
}

///|
fn Program::mir_body_addressable_global_type(
  self : Program,
  ty : @ctype.Type,
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
fn mir_body_collect_label_addrs(
  stmts : Array[MirStmt],
  label_addrs : Map[String, Int64],
  label_names : Map[Int64, String],
  next_label : Array[Int],
) -> Unit {
  for stmt in stmts {
    match stmt {
      MirLabel(name) =>
        if !label_addrs.contains(name) {
          let addr = 4000000000L + next_label[0].to_int64() * 100000L
          label_addrs[name] = addr
          label_names[addr] = name
          next_label[0] = next_label[0] + 1
        }
      MirIf(_, then_, else_) => {
        mir_body_collect_label_addrs(
          then_, label_addrs, label_names, next_label,
        )
        mir_body_collect_label_addrs(
          else_, label_addrs, label_names, next_label,
        )
      }
      MirWhile(_, body) | MirDoWhile(_, body) =>
        mir_body_collect_label_addrs(body, label_addrs, label_names, next_label)
      MirFor(init, _, _, body) => {
        mir_body_collect_label_addrs(init, label_addrs, label_names, next_label)
        mir_body_collect_label_addrs(body, label_addrs, label_names, next_label)
      }
      MirSwitch(_, _, body) | MirBlock(body) =>
        mir_body_collect_label_addrs(body, label_addrs, label_names, next_label)
      _ => ()
    }
  }
}

///|
fn mir_body_global_scalar_init(
  program : Program,
  init : MirGlobalInit?,
  global_addrs : Map[String, Int64],
  func_addrs : Map[String, Int64],
  label_addrs : Map[String, Int64],
  string_memory : Map[Int64, Int64],
  string_addrs : Map[String, Int64],
) -> Int64? {
  match init {
    Some(MirGlobalScalarInt(bits)) => Some(bits)
    Some(MirGlobalString(value)) =>
      Some(mir_body_string_literal_base(value, string_memory, string_addrs))
    Some(MirGlobalSymbol(name)) =>
      match global_addrs.get(name) {
        Some(addr) => Some(addr)
        None => func_addrs.get(name)
      }
    Some(MirGlobalSymbolOffset(name, offset)) =>
      match global_addrs.get(name) {
        Some(addr) =>
          match program.globals.get(name) {
            Some(decl) =>
              match program.core_type(decl.ty) {
                Array(_, _) => Some(addr - offset.to_int64())
                Struct(_) | Union(_) => Some(mir_body_offset_addr(addr, offset))
                _ => Some(addr - offset.to_int64())
              }
            None => Some(addr - offset.to_int64())
          }
        None => None
      }
    Some(MirGlobalLabelAddr(name)) => label_addrs.get(name)
    _ => None
  }
}

///|
fn mir_body_global_string_array_init(
  ty : @ctype.Type,
  value : String,
) -> Array[(Int, MirGlobalInit)]? {
  match mir_body_array_info(ty) {
    Some((elem_ty, len)) =>
      match elem_ty {
        SChar | UChar => {
          let values : Array[(Int, MirGlobalInit)] = []
          let count = if value.length() < len { value.length() } else { len }
          for i in 0..<count {
            values.push((i, MirGlobalScalarInt(value[i].to_int().to_int64())))
          }
          Some(values)
        }
        _ => None
      }
    None => None
  }
}

///|
fn mir_body_global_array_init(
  ty : @ctype.Type,
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
    Some(MirGlobalString(value)) => mir_body_global_string_array_init(ty, value)
    _ => None
  }
}

///|
fn mir_body_global_scalar_init_bits(
  program : Program,
  init : MirGlobalInit?,
  global_addrs : Map[String, Int64],
  func_addrs : Map[String, Int64],
  label_addrs : Map[String, Int64],
  string_memory : Map[Int64, Int64],
  string_addrs : Map[String, Int64],
) -> Int64? {
  match init {
    Some(MirGlobalScalarFloat(value)) => Some(value.reinterpret_as_int64())
    _ =>
      mir_body_global_scalar_init(
        program, init, global_addrs, func_addrs, label_addrs, string_memory, string_addrs,
      )
  }
}

///|
fn mir_body_global_aggregate_slots(
  layout : AggregateLayout,
  init : MirGlobalInit?,
) -> Array[MirGlobalInit?]? {
  let slots : Array[MirGlobalInit?] = Array::make(layout.fields.length(), None)
  match init {
    Some(MirGlobalArray(values)) => {
      let count = if layout.is_union && values.length() > 0 {
        1
      } else {
        values.length()
      }
      for i in 0..<count {
        if i < slots.length() {
          slots[i] = Some(values[i])
        }
      }
      Some(slots)
    }
    Some(MirGlobalAggregateSparse(values)) => {
      for item in values {
        let index = item.0
        if index >= 0 && index < slots.length() {
          slots[index] = Some(item.1)
          if layout.is_union {
            break
          }
        }
      }
      Some(slots)
    }
    None => Some(slots)
    _ => None
  }
}

///|
fn mir_body_global_bitfield_bits(
  init : MirGlobalInit?,
  bit_width : Int,
  bit_offset : Int,
) -> Int64 {
  match init {
    Some(MirGlobalScalarInt(value)) =>
      (value & mir_body_bitfield_mask(bit_width)) << bit_offset
    _ => 0L
  }
}

///|
fn mir_body_init_global_bitfield_container(
  program : Program,
  global_memory : Map[Int64, Int64],
  layout : AggregateLayout,
  slots : Array[MirGlobalInit?],
  base : Int64,
  start : Int,
) -> Int {
  let field = layout.fields[start]
  let container_offset = field.offset
  let container_size = field.size
  let mut container_value = 0L
  let mut index = start
  while index < layout.fields.length() &&
        layout.fields[index].offset == container_offset &&
        layout.fields[index].size == container_size &&
        layout.fields[index].bit_width is Some(_) {
    let bitfield = layout.fields[index]
    match bitfield.bit_width {
      Some(width) =>
        container_value = container_value |
          mir_body_global_bitfield_bits(
            slots[index],
            width,
            bitfield.bit_offset,
          )
      None => ()
    }
    index += 1
  }
  let addr = mir_body_offset_addr(base, container_offset)
  global_memory[addr] = program.runtime_cast_int(container_value, field.ty)
  index
}

///|
fn mir_body_init_global_memory(
  program : Program,
  ty : @ctype.Type,
  init : MirGlobalInit?,
  base : Int64,
  array_base_is_offset_addr : Bool,
  global_memory : Map[Int64, Int64],
  global_addrs : Map[String, Int64],
  func_addrs : Map[String, Int64],
  label_addrs : Map[String, Int64],
  string_memory : Map[Int64, Int64],
  string_addrs : Map[String, Int64],
) -> Unit {
  match program.core_type(ty) {
    Array(elem_ty, len) =>
      match mir_body_global_array_init(ty, init) {
        Some(items) =>
          for item in items {
            let index = item.0
            if index < 0 || index >= len {
              continue
            }
            let raw_elem_base = mir_body_typed_elem_addr(
              program,
              base,
              index.to_int64(),
              elem_ty,
            )
            let elem_base = match program.core_type(elem_ty) {
              Struct(_) | Union(_) =>
                if array_base_is_offset_addr {
                  raw_elem_base + 50000L
                } else {
                  raw_elem_base
                }
              _ => raw_elem_base
            }
            let elem_array_base_is_offset_addr = match
              program.core_type(elem_ty) {
              Array(_, _) => array_base_is_offset_addr
              _ => false
            }
            mir_body_init_global_memory(
              program,
              elem_ty,
              Some(item.1),
              elem_base,
              elem_array_base_is_offset_addr,
              global_memory,
              global_addrs,
              func_addrs,
              label_addrs,
              string_memory,
              string_addrs,
            )
          }
        None => ()
      }
    Struct(name) | Union(name) =>
      match program.layouts.get(name) {
        Some(layout) =>
          match mir_body_global_aggregate_slots(layout, init) {
            Some(slots) => {
              let mut index = 0
              while index < layout.fields.length() {
                let field = layout.fields[index]
                match field.bit_width {
                  Some(_) => {
                    index = mir_body_init_global_bitfield_container(
                      program, global_memory, layout, slots, base, index,
                    )
                    continue
                  }
                  None =>
                    match slots[index] {
                      Some(value) => {
                        let (field_base, field_array_base_is_offset_addr) = match
                          program.core_type(field.ty) {
                          Struct(_) | Union(_) =>
                            (base - field.offset.to_int64(), false)
                          Array(_, _) =>
                            (mir_body_offset_addr(base, field.offset), true)
                          _ => (mir_body_offset_addr(base, field.offset), false)
                        }
                        mir_body_init_global_memory(
                          program,
                          field.ty,
                          Some(value),
                          field_base,
                          field_array_base_is_offset_addr,
                          global_memory,
                          global_addrs,
                          func_addrs,
                          label_addrs,
                          string_memory,
                          string_addrs,
                        )
                      }
                      None => ()
                    }
                }
                index += 1
              }
            }
            None => ()
          }
        None => ()
      }
    _ =>
      if mir_body_scalar_type(ty) {
        match
          mir_body_global_scalar_init_bits(
            program, init, global_addrs, func_addrs, label_addrs, string_memory,
            string_addrs,
          ) {
          Some(bits) => global_memory[base] = program.runtime_cast_int(bits, ty)
          None => ()
        }
      }
  }
}

///|
fn Program::runtime_cast_body_scalar(
  self : Program,
  bits : Int64,
  src_ty : @ctype.Type,
  dst_ty : @ctype.Type,
) -> Int64 {
  let src = self.core_type(src_ty)
  let dst = self.core_type(dst_ty)
  match (src, dst) {
    (Pointer(_) | FuncPtr(_, _, _), Pointer(_) | FuncPtr(_, _, _)) =>
      return bits
    _ => ()
  }
  if self.is_floating_type(src) && dst.is_integer() {
    return self.runtime_cast_int(bits.reinterpret_as_double().to_int64(), dst)
  }
  if src.is_integer() && self.is_floating_type(dst) {
    let value = self.runtime_cast_int(bits, src).to_double()
    return value.reinterpret_as_int64()
  }
  self.runtime_cast_int(bits, dst)
}

///|
fn Program::runtime_body_double(
  self : Program,
  bits : Int64,
  ty : @ctype.Type,
) -> Double? {
  let core = self.core_type(ty)
  if self.is_floating_type(core) {
    Some(bits.reinterpret_as_double())
  } else if core.is_integer() {
    Some(self.runtime_cast_int(bits, core).to_double())
  } else {
    None
  }
}

///|
fn Program::runtime_body_truthy(
  self : Program,
  bits : Int64,
  ty : @ctype.Type,
) -> Bool {
  if self.is_floating_type(ty) {
    match self.runtime_body_double(bits, ty) {
      Some(value) => value != 0.0
      None => bits != 0L
    }
  } else {
    bits != 0L
  }
}

///|
fn mir_body_rotate_binary_op(op : String) -> (Int, Bool)? {
  match op {
    "rotl32" => Some((32, true))
    "rotr32" => Some((32, false))
    "rotl64" => Some((64, true))
    "rotr64" => Some((64, false))
    _ => None
  }
}

///|
fn BodyInterpreter::eval_fp_compare_values(
  self : BodyInterpreter,
  op : String,
  left : Int64,
  left_ty : @ctype.Type,
  right : Int64,
  right_ty : @ctype.Type,
) -> Int64? {
  if !self.program.is_floating_type(left_ty) &&
    !self.program.is_floating_type(right_ty) {
    return None
  }
  match
    (
      self.program.runtime_body_double(left, left_ty),
      self.program.runtime_body_double(right, right_ty),
    ) {
    (Some(left), Some(right)) =>
      match @ctype.floating_compare(op, left, right) {
        Some(result) => Some(if result { 1L } else { 0L })
        None => None
      }
    _ => None
  }
}

///|
fn BodyInterpreter::eval_fp_class_value(
  self : BodyInterpreter,
  op : String,
  value : Int64,
  ty : @ctype.Type,
) -> Int64? {
  if !self.program.is_floating_type(ty) {
    return None
  }
  let fp = value.reinterpret_as_double()
  let kind = match op {
    "fp_isnan" => "isnan"
    "fp_isinf" => "isinf"
    "fp_isfinite" => "isfinite"
    "fp_isnormal" => "isnormal"
    "fp_signbit" => "signbit"
    _ => return None
  }
  match @ctype.floating_classify(kind, fp, ty) {
    Some(result) => Some(if result { 1L } else { 0L })
    None => None
  }
}

///|
fn BodyInterpreter::eval_fp_arith_values(
  self : BodyInterpreter,
  op : String,
  left : Int64,
  left_ty : @ctype.Type,
  right : Int64,
  right_ty : @ctype.Type,
) -> Int64? {
  if !self.program.is_floating_type(left_ty) &&
    !self.program.is_floating_type(right_ty) {
    return None
  }
  match
    (
      self.program.runtime_body_double(left, left_ty),
      self.program.runtime_body_double(right, right_ty),
    ) {
    (Some(left), Some(right)) =>
      match op {
        "+" => Some((left + right).reinterpret_as_int64())
        "-" => Some((left - right).reinterpret_as_int64())
        "*" => Some((left * right).reinterpret_as_int64())
        "/" => Some((left / right).reinterpret_as_int64())
        "copysign" =>
          Some(@ctype.floating_copysign(left, right).reinterpret_as_int64())
        _ => None
      }
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
  let label_addrs : Map[String, Int64] = {}
  let label_names : Map[Int64, String] = {}
  let string_memory : Map[Int64, Int64] = {}
  let string_addrs : Map[String, Int64] = {}
  for i in 0..<program.decls.length() {
    let name = program.decls[i].name
    let addr = 3000000000L + i.to_int64() * 100000L
    func_addrs[name] = addr
    func_names[addr] = name
  }
  let next_label = [0]
  for body in program.bodies.values() {
    mir_body_collect_label_addrs(
      body.body,
      label_addrs,
      label_names,
      next_label,
    )
  }
  let mut next_global = 0
  for decl in program.globals.values() {
    if program.mir_body_addressable_global_type(decl.ty) {
      let base = 1000000000L + next_global.to_int64() * 100000L
      global_addrs[decl.name] = base
      next_global += 1
    }
  }
  for decl in program.globals.values() {
    if mir_body_scalar_type(decl.ty) {
      let value = match
        mir_body_global_scalar_init_bits(
          program,
          decl.init,
          global_addrs,
          func_addrs,
          label_addrs,
          string_memory,
          string_addrs,
        ) {
        Some(bits) => bits
        None => 0L
      }
      globals[decl.name] = program.runtime_cast_int(value, decl.ty)
    } else {
      match global_addrs.get(decl.name) {
        Some(base) =>
          mir_body_init_global_memory(
            program,
            decl.ty,
            decl.init,
            base,
            false,
            global_memory,
            global_addrs,
            func_addrs,
            label_addrs,
            string_memory,
            string_addrs,
          )
        None => ()
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
    label_addrs,
    label_names,
    string_memory,
    string_addrs,
    aggregate_args: {},
    stack_locals: {},
    stack_bindings: {},
    stack_memory: {},
    stack_memory_ranges: {},
    alloca_memory_ranges: {},
    heap_memory_ranges: {},
    error: None,
    steps: 0,
    call_depth: 0,
    strtok_next: 0L,
    next_frame: 0L,
    next_alloca: 4000000000L,
    next_aggregate_arg: 7000000000L,
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
fn BodyInterpreter::next_frame_base(self : BodyInterpreter) -> Int64 {
  let frame_id = self.next_frame
  self.next_frame += 1L
  -1000000000L - frame_id * 100000000000L
}

///|
fn BodyFrame::local_addr(self : BodyFrame, binding : MirLocal) -> Int64 {
  self.base - binding.id.to_int64() * 100000L
}

///|
fn BodyInterpreter::write_stack_local(
  self : BodyInterpreter,
  frame : BodyFrame,
  binding : MirLocal,
  value : Int64,
) -> Int64 {
  let assigned = self.program.runtime_cast_int(value, binding.ty)
  frame.locals[binding.id] = assigned
  if mir_body_scalar_type(binding.ty) {
    let addr = frame.local_addr(binding)
    self.stack_locals[addr] = assigned
    self.stack_bindings[addr] = binding
  }
  assigned
}

///|
fn BodyInterpreter::read_stack_local(
  self : BodyInterpreter,
  frame : BodyFrame,
  binding : MirLocal,
  ty : @ctype.Type,
) -> Int64 {
  if mir_body_scalar_type(binding.ty) {
    match self.stack_locals.get(frame.local_addr(binding)) {
      Some(value) => return self.program.runtime_cast_int(value, ty)
      None => ()
    }
  }
  if frame.locals.contains(binding.id) {
    self.program.runtime_cast_int(frame.locals[binding.id], ty)
  } else {
    self.fail("unknown MIR body local value: " + binding.name)
    0L
  }
}

///|
fn BodyInterpreter::read_stack_addr(
  self : BodyInterpreter,
  addr : Int64,
  ty : @ctype.Type,
) -> Int64? {
  match self.stack_bindings.get(addr) {
    Some(binding) =>
      match self.stack_locals.get(addr) {
        Some(value) => Some(self.program.runtime_cast_int(value, ty))
        None => {
          self.fail("unknown MIR body local value: " + binding.name)
          Some(0L)
        }
      }
    None => None
  }
}

///|
fn BodyInterpreter::write_stack_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
  value : Int64,
  ty : @ctype.Type,
) -> Int64? {
  match self.stack_bindings.get(addr) {
    Some(binding) => {
      let assigned = self.program.runtime_cast_int(value, binding.ty)
      self.stack_locals[addr] = assigned
      match frame.binding_for_addr(addr) {
        Some(current_binding) => frame.locals[current_binding.id] = assigned
        None => ()
      }
      Some(self.program.runtime_cast_int(assigned, ty))
    }
    None => None
  }
}

///|
fn BodyInterpreter::register_stack_memory_range(
  self : BodyInterpreter,
  base : Int64,
  size : Int64,
) -> Unit {
  if size > 0L {
    self.stack_memory_ranges[base] = size
  }
}

///|
fn BodyInterpreter::register_stack_binding_memory(
  self : BodyInterpreter,
  frame : BodyFrame,
  binding : MirLocal,
) -> Unit {
  match mir_body_array_info(binding.ty) {
    Some((elem_ty, len)) => {
      let elem_size = self.program.type_size(elem_ty).to_int64()
      let base = frame.local_addr(binding)
      self.register_stack_memory_range(base, elem_size * len.to_int64())
      match self.program.core_type(elem_ty) {
        Struct(_) | Union(_) =>
          for i in 0..<len {
            self.register_stack_memory_range(
              mir_body_offset_addr(
                mir_body_typed_elem_addr(
                  self.program,
                  base,
                  i.to_int64(),
                  elem_ty,
                ),
                0,
              ),
              elem_size,
            )
          }
        _ => ()
      }
    }
    None =>
      match self.program.core_type(binding.ty) {
        Struct(_) | Union(_) =>
          self.register_stack_memory_range(
            mir_body_offset_addr(frame.local_addr(binding), 0),
            self.program.type_size(binding.ty).to_int64(),
          )
        _ => ()
      }
  }
}

///|
fn BodyInterpreter::register_frame_memory_ranges(
  self : BodyInterpreter,
  frame : BodyFrame,
) -> Unit {
  for binding in frame.bindings.values() {
    self.register_stack_binding_memory(frame, binding)
  }
}

///|
fn BodyInterpreter::stack_memory_addr(
  self : BodyInterpreter,
  addr : Int64,
) -> Bool {
  for base in self.stack_memory_ranges.keys() {
    let size = self.stack_memory_ranges[base]
    if addr <= base && addr > base - size {
      return true
    }
  }
  false
}

///|
fn BodyInterpreter::read_stack_memory(
  self : BodyInterpreter,
  addr : Int64,
  ty : @ctype.Type,
) -> Int64? {
  if self.stack_memory_addr(addr) {
    let value = match self.stack_memory.get(addr) {
      Some(value) => value
      None => 0L
    }
    Some(self.program.runtime_cast_int(value, ty))
  } else {
    None
  }
}

///|
fn BodyInterpreter::write_stack_memory(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
  value : Int64,
  ty : @ctype.Type,
) -> Int64? {
  if self.stack_memory_addr(addr) {
    let assigned = self.program.runtime_cast_int(value, ty)
    self.stack_memory[addr] = assigned
    if self.frame_memory_addr(frame, addr) {
      frame.memory[addr] = assigned
    }
    Some(assigned)
  } else {
    None
  }
}

///|
fn Program::mir_body_scalar_byte_memory_type(
  self : Program,
  ty : @ctype.Type,
) -> Bool {
  let size = self.type_size(ty)
  if size <= 0 || size > 8 {
    return false
  }
  match self.core_type(ty) {
    Bool | Pointer(_) | FuncPtr(_, _, _) => true
    Float => size == 4
    Double | LongDouble => size == 8
    core => core.is_integer()
  }
}

///|
fn Program::mir_body_scalar_object_bits(
  self : Program,
  bits : Int64,
  ty : @ctype.Type,
) -> Int64 {
  match self.core_type(ty) {
    Float =>
      Float::from_double(bits.reinterpret_as_double())
      .reinterpret_as_uint()
      .to_int64()
    _ => self.runtime_cast_int(bits, ty)
  }
}

///|
fn Program::mir_body_scalar_value_bits(
  self : Program,
  object_bits : Int64,
  ty : @ctype.Type,
) -> Int64 {
  match self.core_type(ty) {
    Float =>
      Float::reinterpret_from_uint(
        object_bits.reinterpret_as_uint64().to_uint(),
      )
      .to_double()
      .reinterpret_as_int64()
    _ => self.runtime_cast_int(object_bits, ty)
  }
}

///|
fn mir_body_scalar_byte_offset(
  base : Int64,
  size : Int64,
  addr : Int64,
) -> Int64? {
  if addr <= base && addr > base - size {
    Some(base - addr)
  } else {
    None
  }
}

///|
fn mir_body_scalar_byte(bits : Int64, offset : Int64) -> Int64 {
  (bits >> (offset.to_int() * 8)) & 0xFFL
}

///|
fn mir_body_store_scalar_byte(
  bits : Int64,
  offset : Int64,
  byte : Int64,
) -> Int64 {
  let shift = offset.to_int() * 8
  let mask = 0xFFL << shift
  (bits & mask.lnot()) | ((byte & 0xFFL) << shift)
}

///|
priv struct BodyScalarByteSlot {
  base : Int64
  ty : @ctype.Type
  offset : Int64
}

///|
fn Program::scalar_byte_slot_in_type(
  self : Program,
  ty : @ctype.Type,
  base : Int64,
  array_base_is_offset_addr : Bool,
  addr : Int64,
) -> BodyScalarByteSlot? {
  if self.mir_body_scalar_byte_memory_type(ty) {
    let size = self.type_size(ty).to_int64()
    match mir_body_scalar_byte_offset(base, size, addr) {
      Some(offset) => return Some({ base, ty, offset })
      None => ()
    }
  }
  match self.core_type(ty) {
    Array(elem_ty, len) => {
      for i in 0..<len {
        let raw_elem_base = mir_body_typed_elem_addr(
          self,
          base,
          i.to_int64(),
          elem_ty,
        )
        let elem_base = match self.core_type(elem_ty) {
          Struct(_) | Union(_) =>
            if array_base_is_offset_addr {
              raw_elem_base + 50000L
            } else {
              raw_elem_base
            }
          _ => raw_elem_base
        }
        let elem_array_base_is_offset_addr = match self.core_type(elem_ty) {
          Array(_, _) => array_base_is_offset_addr
          _ => false
        }
        match
          self.scalar_byte_slot_in_type(
            elem_ty, elem_base, elem_array_base_is_offset_addr, addr,
          ) {
          Some(slot) => return Some(slot)
          None => ()
        }
      }
      None
    }
    Struct(name) | Union(name) =>
      match self.layouts.get(name) {
        Some(layout) => {
          for field in layout.fields {
            if field.bit_width is Some(_) {
              continue
            }
            let (field_base, field_array_base_is_offset_addr) = match
              self.core_type(field.ty) {
              Struct(_) | Union(_) => (base - field.offset.to_int64(), false)
              Array(_, _) => (mir_body_offset_addr(base, field.offset), true)
              _ => (mir_body_offset_addr(base, field.offset), false)
            }
            match
              self.scalar_byte_slot_in_type(
                field.ty,
                field_base,
                field_array_base_is_offset_addr,
                addr,
              ) {
              Some(slot) => return Some(slot)
              None => ()
            }
          }
          None
        }
        None => None
      }
    _ => None
  }
}

///|
fn mir_body_binding_object_base(frame : BodyFrame, binding : MirLocal) -> Int64 {
  frame.local_addr(binding)
}

///|
fn mir_body_global_object_base(raw_base : Int64) -> Int64 {
  raw_base
}

///|
fn BodyInterpreter::local_scalar_byte_slot(
  self : BodyInterpreter,
  frame : BodyFrame,
  binding : MirLocal,
  addr : Int64,
) -> BodyScalarByteSlot? {
  self.program.scalar_byte_slot_in_type(
    binding.ty,
    mir_body_binding_object_base(frame, binding),
    false,
    addr,
  )
}

///|
fn BodyInterpreter::global_scalar_byte_slot(
  self : BodyInterpreter,
  name : String,
  addr : Int64,
) -> BodyScalarByteSlot? {
  match self.program.globals.get(name) {
    Some(decl) =>
      match self.global_addrs.get(name) {
        Some(base) =>
          self.program.scalar_byte_slot_in_type(
            decl.ty,
            mir_body_global_object_base(base),
            false,
            addr,
          )
        None => None
      }
    None => None
  }
}

///|
fn Program::bitfield_container_addr_in_type(
  self : Program,
  ty : @ctype.Type,
  base : Int64,
  array_base_is_offset_addr : Bool,
  addr : Int64,
) -> Bool {
  match self.core_type(ty) {
    Array(elem_ty, len) => {
      for i in 0..<len {
        let raw_elem_base = mir_body_typed_elem_addr(
          self,
          base,
          i.to_int64(),
          elem_ty,
        )
        let elem_base = match self.core_type(elem_ty) {
          Struct(_) | Union(_) =>
            if array_base_is_offset_addr {
              raw_elem_base + 50000L
            } else {
              raw_elem_base
            }
          _ => raw_elem_base
        }
        let elem_array_base_is_offset_addr = match self.core_type(elem_ty) {
          Array(_, _) => array_base_is_offset_addr
          _ => false
        }
        if self.bitfield_container_addr_in_type(
            elem_ty, elem_base, elem_array_base_is_offset_addr, addr,
          ) {
          return true
        }
      }
      false
    }
    Struct(name) | Union(name) =>
      match self.layouts.get(name) {
        Some(layout) => {
          for field in layout.fields {
            if field.bit_width is Some(_) {
              if mir_body_offset_addr(base, field.offset) == addr {
                return true
              }
              continue
            }
            let (field_base, field_array_base_is_offset_addr) = match
              self.core_type(field.ty) {
              Struct(_) | Union(_) => (base - field.offset.to_int64(), false)
              Array(_, _) => (mir_body_offset_addr(base, field.offset), true)
              _ => (mir_body_offset_addr(base, field.offset), false)
            }
            if self.bitfield_container_addr_in_type(
                field.ty,
                field_base,
                field_array_base_is_offset_addr,
                addr,
              ) {
              return true
            }
          }
          false
        }
        None => false
      }
    _ => false
  }
}

///|
fn BodyInterpreter::local_bitfield_container_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
) -> Bool {
  for binding in frame.bindings.values() {
    if self.program.bitfield_container_addr_in_type(
        binding.ty,
        mir_body_binding_object_base(frame, binding),
        false,
        addr,
      ) {
      return true
    }
  }
  false
}

///|
fn BodyInterpreter::global_bitfield_container_addr(
  self : BodyInterpreter,
  addr : Int64,
) -> Bool {
  for name in self.global_addrs.keys() {
    match self.program.globals.get(name) {
      Some(decl) =>
        if self.program.bitfield_container_addr_in_type(
            decl.ty,
            mir_body_global_object_base(self.global_addrs[name]),
            false,
            addr,
          ) {
          return true
        }
      None => ()
    }
  }
  false
}

///|
fn BodyInterpreter::bitfield_container_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
) -> Bool {
  self.local_bitfield_container_addr(frame, addr) ||
  self.global_bitfield_container_addr(addr)
}

///|
fn BodyInterpreter::scalar_local_byte_for_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
) -> Int64? {
  for binding in frame.bindings.values() {
    match self.local_scalar_byte_slot(frame, binding, addr) {
      Some(slot) => {
        let bits = match self.stack_memory.get(slot.base) {
          Some(value) => value
          None =>
            match frame.memory.get(slot.base) {
              Some(value) => value
              None =>
                if slot.base == frame.local_addr(binding) &&
                  self.program.mir_body_scalar_byte_memory_type(binding.ty) {
                  match self.stack_locals.get(slot.base) {
                    Some(value) => value
                    None =>
                      match frame.locals.get(binding.id) {
                        Some(value) => value
                        None => {
                          self.fail(
                            "unknown MIR body local value: " + binding.name,
                          )
                          0L
                        }
                      }
                  }
                } else {
                  0L
                }
            }
        }
        return Some(
          mir_body_scalar_byte(
            self.program.mir_body_scalar_object_bits(bits, slot.ty),
            slot.offset,
          ),
        )
      }
      None => ()
    }
  }
  None
}

///|
fn BodyInterpreter::write_scalar_local_byte_for_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
  byte : Int64,
) -> Bool {
  for binding in frame.bindings.values() {
    match self.local_scalar_byte_slot(frame, binding, addr) {
      Some(slot) => {
        let bits = match self.stack_memory.get(slot.base) {
          Some(value) => value
          None =>
            match frame.memory.get(slot.base) {
              Some(value) => value
              None =>
                if slot.base == frame.local_addr(binding) &&
                  self.program.mir_body_scalar_byte_memory_type(binding.ty) {
                  match self.stack_locals.get(slot.base) {
                    Some(value) => value
                    None =>
                      match frame.locals.get(binding.id) {
                        Some(value) => value
                        None => 0L
                      }
                  }
                } else {
                  0L
                }
            }
        }
        let updated = self.program.mir_body_scalar_value_bits(
          mir_body_store_scalar_byte(
            self.program.mir_body_scalar_object_bits(bits, slot.ty),
            slot.offset,
            byte,
          ),
          slot.ty,
        )
        if slot.base == frame.local_addr(binding) &&
          self.program.mir_body_scalar_byte_memory_type(binding.ty) {
          ignore(self.write_stack_local(frame, binding, updated))
        } else {
          let assigned = self.program.runtime_cast_int(updated, slot.ty)
          self.stack_memory[slot.base] = assigned
          frame.memory[slot.base] = assigned
        }
        return true
      }
      None => ()
    }
  }
  false
}

///|
fn BodyInterpreter::scalar_global_byte_for_addr(
  self : BodyInterpreter,
  addr : Int64,
) -> Int64? {
  for name in self.global_addrs.keys() {
    match self.global_scalar_byte_slot(name, addr) {
      Some(slot) => {
        let decl = match self.program.globals.get(name) {
          Some(decl) => decl
          None => continue
        }
        let global_base = self.global_addrs[name]
        let bits = if slot.base == global_base &&
          self.program.mir_body_scalar_byte_memory_type(decl.ty) {
          match self.globals.get(name) {
            Some(value) => value
            None => 0L
          }
        } else {
          match self.global_memory.get(slot.base) {
            Some(value) => value
            None => 0L
          }
        }
        return Some(
          mir_body_scalar_byte(
            self.program.mir_body_scalar_object_bits(bits, slot.ty),
            slot.offset,
          ),
        )
      }
      None => ()
    }
  }
  None
}

///|
fn BodyInterpreter::write_scalar_global_byte_for_addr(
  self : BodyInterpreter,
  addr : Int64,
  byte : Int64,
) -> Bool {
  for name in self.global_addrs.keys() {
    match self.global_scalar_byte_slot(name, addr) {
      Some(slot) => {
        let decl = match self.program.globals.get(name) {
          Some(decl) => decl
          None => continue
        }
        let global_base = self.global_addrs[name]
        let bits = if slot.base == global_base &&
          self.program.mir_body_scalar_byte_memory_type(decl.ty) {
          match self.globals.get(name) {
            Some(value) => value
            None => 0L
          }
        } else {
          match self.global_memory.get(slot.base) {
            Some(value) => value
            None => 0L
          }
        }
        let updated = self.program.mir_body_scalar_value_bits(
          mir_body_store_scalar_byte(
            self.program.mir_body_scalar_object_bits(bits, slot.ty),
            slot.offset,
            byte,
          ),
          slot.ty,
        )
        if slot.base == global_base &&
          self.program.mir_body_scalar_byte_memory_type(decl.ty) {
          self.globals[name] = self.program.runtime_cast_int(updated, decl.ty)
        } else {
          self.global_memory[slot.base] = self.program.runtime_cast_int(
            updated,
            slot.ty,
          )
        }
        return true
      }
      None => ()
    }
  }
  false
}

///|
fn mir_body_elem_addr(base : Int64, index : Int64) -> Int64 {
  base - index
}

///|
fn mir_body_typed_elem_addr(
  program : Program,
  base : Int64,
  index : Int64,
  elem_ty : @ctype.Type,
) -> Int64 {
  base - index * program.type_size(elem_ty).to_int64()
}

///|
fn mir_body_typed_elem_addr_value(
  program : Program,
  base_value : MirValue,
  base : Int64,
  index : Int64,
  elem_ty : @ctype.Type,
) -> Int64 {
  let addr = mir_body_typed_elem_addr(program, base, index, elem_ty)
  match program.core_type(elem_ty) {
    Struct(_) | Union(_) =>
      match base_value {
        MirOffsetAddr(_, _, _) => addr + 50000L
        _ => addr
      }
    _ => addr
  }
}

///|
fn mir_body_offset_addr(base : Int64, offset : Int) -> Int64 {
  base - 50000L - offset.to_int64()
}

///|
fn mir_body_string_literal_base(
  value : String,
  string_memory : Map[Int64, Int64],
  string_addrs : Map[String, Int64],
) -> Int64 {
  match string_addrs.get(value) {
    Some(base) => base
    None => {
      let base = 2000000000L + string_addrs.length().to_int64() * 100000L
      string_addrs[value] = base
      for i in 0..<value.length() {
        string_memory[base - i.to_int64()] = value[i].to_int().to_int64()
      }
      string_memory[base - value.length().to_int64()] = 0L
      base
    }
  }
}

///|
fn mir_body_c_string_len_from(value : String, offset : Int64) -> Int64 {
  @ctype.string_literal_c_length_from(value, offset)
}

///|
fn mir_body_nonnegative_min(left : Int64, right : Int64) -> Int64? {
  if left < 0L || right < 0L {
    None
  } else if left < right {
    Some(left)
  } else {
    Some(right)
  }
}

///|
fn mir_body_checked_printf_format_indexes(
  name : String,
  args : Array[MirValue],
  ty : @ctype.Type,
) -> (Int, Int)? {
  if !ty.is_integer() {
    return None
  }
  match name {
    "snprintf" => if args.length() >= 3 { Some((2, 3)) } else { None }
    "vsnprintf" =>
      if args.length() == 4 {
        Some((2, args.length()))
      } else {
        None
      }
    "sprintf" => if args.length() >= 2 { Some((1, 2)) } else { None }
    "vsprintf" =>
      if args.length() == 3 {
        Some((1, args.length()))
      } else {
        None
      }
    "printf" => if args.length() >= 1 { Some((0, 1)) } else { None }
    "vprintf" =>
      if args.length() == 2 {
        Some((0, args.length()))
      } else {
        None
      }
    "fprintf" => if args.length() >= 2 { Some((1, 2)) } else { None }
    "vfprintf" =>
      if args.length() == 3 {
        Some((1, args.length()))
      } else {
        None
      }
    _ => None
  }
}

///|
fn mir_body_external_printf_format_indexes(
  name : String,
  arg_count : Int,
) -> (Int, Int)? {
  match name {
    "snprintf" => if arg_count >= 3 { Some((2, 3)) } else { None }
    "vsnprintf" => if arg_count == 4 { Some((2, arg_count)) } else { None }
    "sprintf" => if arg_count >= 2 { Some((1, 2)) } else { None }
    "vsprintf" => if arg_count == 3 { Some((1, arg_count)) } else { None }
    "printf" => if arg_count >= 1 { Some((0, 1)) } else { None }
    "vprintf" => if arg_count == 2 { Some((0, arg_count)) } else { None }
    "fprintf" => if arg_count >= 2 { Some((1, 2)) } else { None }
    "vfprintf" => if arg_count == 3 { Some((1, arg_count)) } else { None }
    _ => None
  }
}

///|
fn mir_body_checked_vprintf_va_list_index(name : String) -> Int? {
  match name {
    "vsnprintf" => Some(3)
    "vsprintf" => Some(2)
    "vprintf" => Some(1)
    "vfprintf" => Some(2)
    _ => None
  }
}

///|
priv enum MirPrintfLengthModifier {
  MirPrintfNoLength
  MirPrintfHH
  MirPrintfH
  MirPrintfL
  MirPrintfLL
  MirPrintfJ
  MirPrintfT
  MirPrintfZ
} derive(Eq)

///|
fn mir_body_printf_count_store_type(
  modifier : MirPrintfLengthModifier,
) -> @ctype.Type {
  match modifier {
    MirPrintfHH => SChar
    MirPrintfH => SShort
    MirPrintfL | MirPrintfJ | MirPrintfT | MirPrintfZ => SLong
    MirPrintfLL => SLongLong
    MirPrintfNoLength => SInt
  }
}

///|
fn BodyInterpreter::literal_printf_format_arg_count(
  self : BodyInterpreter,
  format_addr : Int64,
  name : String,
) -> Int? {
  match self.string_literal_for_addr(format_addr) {
    Some((format, offset)) => {
      if offset < 0L || offset > format.length().to_int64() {
        self.fail("unsupported MIR body " + name + " format argument")
        return None
      }
      let mut index = offset.to_int()
      let mut count = 0
      while index < format.length() {
        let byte = format[index].to_int()
        if byte == 0 {
          return Some(count)
        }
        if byte == 37 {
          if index + 1 < format.length() && format[index + 1].to_int() == 37 {
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
            if conversion_index < format.length() &&
              format[conversion_index].to_int() == 42 {
              count += 1
              conversion_index += 1
            } else {
              while conversion_index < format.length() &&
                    format[conversion_index].to_int() >= 48 &&
                    format[conversion_index].to_int() <= 57 {
                conversion_index += 1
              }
            }
            let mut has_precision = false
            if conversion_index < format.length() &&
              format[conversion_index].to_int() == 46 {
              has_precision = true
              conversion_index += 1
              if conversion_index < format.length() &&
                format[conversion_index].to_int() == 42 {
                count += 1
                conversion_index += 1
              } else {
                while conversion_index < format.length() &&
                      format[conversion_index].to_int() >= 48 &&
                      format[conversion_index].to_int() <= 57 {
                  conversion_index += 1
                }
              }
            }
            let mut modifier = MirPrintfNoLength
            if conversion_index < format.length() {
              if format[conversion_index].to_int() == 104 {
                conversion_index += 1
                if conversion_index < format.length() &&
                  format[conversion_index].to_int() == 104 {
                  modifier = MirPrintfHH
                  conversion_index += 1
                } else {
                  modifier = MirPrintfH
                }
              } else if format[conversion_index].to_int() == 108 {
                modifier = MirPrintfL
                conversion_index += 1
                if conversion_index < format.length() &&
                  format[conversion_index].to_int() == 108 {
                  modifier = MirPrintfLL
                  conversion_index += 1
                }
              } else if format[conversion_index].to_int() == 106 {
                modifier = MirPrintfJ
                conversion_index += 1
              } else if format[conversion_index].to_int() == 116 {
                modifier = MirPrintfT
                conversion_index += 1
              } else if format[conversion_index].to_int() == 122 {
                modifier = MirPrintfZ
                conversion_index += 1
              }
            }
            if conversion_index < format.length() &&
              (
                format[conversion_index].to_int() == 88 ||
                format[conversion_index].to_int() == 69 ||
                format[conversion_index].to_int() == 99 ||
                format[conversion_index].to_int() == 100 ||
                format[conversion_index].to_int() == 101 ||
                format[conversion_index].to_int() == 102 ||
                format[conversion_index].to_int() == 105 ||
                format[conversion_index].to_int() == 110 ||
                format[conversion_index].to_int() == 111 ||
                format[conversion_index].to_int() == 112 ||
                format[conversion_index].to_int() == 115 ||
                format[conversion_index].to_int() == 117 ||
                format[conversion_index].to_int() == 120
              ) {
              let conversion = format[conversion_index].to_int()
              if modifier != MirPrintfNoLength &&
                (conversion == 99 || conversion == 112 || conversion == 115) {
                self.fail("unsupported MIR body " + name + " format")
                return None
              }
              if has_precision &&
                conversion != 100 &&
                conversion != 69 &&
                conversion != 101 &&
                conversion != 102 &&
                conversion != 105 &&
                conversion != 88 &&
                conversion != 111 &&
                conversion != 115 &&
                conversion != 117 &&
                conversion != 120 {
                self.fail("unsupported MIR body " + name + " format")
                return None
              }
              if (plus_flag || space_flag) &&
                conversion != 100 &&
                conversion != 69 &&
                conversion != 101 &&
                conversion != 102 &&
                conversion != 105 {
                self.fail("unsupported MIR body " + name + " format")
                return None
              }
              if alternate_flag &&
                conversion != 111 &&
                conversion != 88 &&
                conversion != 120 {
                self.fail("unsupported MIR body " + name + " format")
                return None
              }
              count += 1
              index = conversion_index + 1
            } else {
              self.fail("unsupported MIR body " + name + " format")
              return None
            }
          }
        } else {
          index += 1
        }
      }
      Some(count)
    }
    None => {
      self.fail("unsupported MIR body " + name + " format argument")
      None
    }
  }
}

///|
fn BodyInterpreter::literal_printf_format_length(
  self : BodyInterpreter,
  frame : BodyFrame,
  format_addr : Int64,
  name : String,
  values : Array[Int64],
  first_value_index : Int,
) -> Int64? {
  match self.string_literal_for_addr(format_addr) {
    Some((format, offset)) => {
      if offset < 0L || offset > format.length().to_int64() {
        self.fail("unsupported MIR body " + name + " format argument")
        return None
      }
      let mut index = offset.to_int()
      let mut length = 0L
      let mut value_index = first_value_index
      while index < format.length() {
        let byte = format[index].to_int()
        if byte == 0 {
          return Some(length)
        }
        if byte == 37 {
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
            if conversion_index < format.length() &&
              format[conversion_index].to_int() == 42 {
              if value_index >= values.length() {
                self.fail("unsupported MIR body " + name + " argument")
                return None
              }
              width = values[value_index]
              if width < 0L {
                width = -width
              }
              value_index += 1
              conversion_index += 1
            } else {
              while conversion_index < format.length() &&
                    format[conversion_index].to_int() >= 48 &&
                    format[conversion_index].to_int() <= 57 {
                width = width * 10L +
                  (format[conversion_index].to_int() - 48).to_int64()
                conversion_index += 1
              }
            }
            let mut has_precision = false
            let mut precision = 0L
            if conversion_index < format.length() &&
              format[conversion_index].to_int() == 46 {
              has_precision = true
              conversion_index += 1
              if conversion_index < format.length() &&
                format[conversion_index].to_int() == 42 {
                if value_index >= values.length() {
                  self.fail("unsupported MIR body " + name + " argument")
                  return None
                }
                precision = values[value_index]
                if precision < 0L {
                  has_precision = false
                  precision = 0L
                }
                value_index += 1
                conversion_index += 1
              } else {
                while conversion_index < format.length() &&
                      format[conversion_index].to_int() >= 48 &&
                      format[conversion_index].to_int() <= 57 {
                  precision = precision * 10L +
                    (format[conversion_index].to_int() - 48).to_int64()
                  conversion_index += 1
                }
              }
            }
            let mut modifier = MirPrintfNoLength
            if conversion_index < format.length() {
              if format[conversion_index].to_int() == 104 {
                conversion_index += 1
                if conversion_index < format.length() &&
                  format[conversion_index].to_int() == 104 {
                  modifier = MirPrintfHH
                  conversion_index += 1
                } else {
                  modifier = MirPrintfH
                }
              } else if format[conversion_index].to_int() == 108 {
                modifier = MirPrintfL
                conversion_index += 1
                if conversion_index < format.length() &&
                  format[conversion_index].to_int() == 108 {
                  modifier = MirPrintfLL
                  conversion_index += 1
                }
              } else if format[conversion_index].to_int() == 106 {
                modifier = MirPrintfJ
                conversion_index += 1
              } else if format[conversion_index].to_int() == 116 {
                modifier = MirPrintfT
                conversion_index += 1
              } else if format[conversion_index].to_int() == 122 {
                modifier = MirPrintfZ
                conversion_index += 1
              }
            }
            if conversion_index < format.length() &&
              (
                format[conversion_index].to_int() == 88 ||
                format[conversion_index].to_int() == 69 ||
                format[conversion_index].to_int() == 99 ||
                format[conversion_index].to_int() == 100 ||
                format[conversion_index].to_int() == 101 ||
                format[conversion_index].to_int() == 102 ||
                format[conversion_index].to_int() == 105 ||
                format[conversion_index].to_int() == 110 ||
                format[conversion_index].to_int() == 111 ||
                format[conversion_index].to_int() == 112 ||
                format[conversion_index].to_int() == 115 ||
                format[conversion_index].to_int() == 117 ||
                format[conversion_index].to_int() == 120
              ) {
              if modifier != MirPrintfNoLength &&
                (
                  format[conversion_index].to_int() == 99 ||
                  format[conversion_index].to_int() == 112 ||
                  format[conversion_index].to_int() == 115
                ) {
                self.fail("unsupported MIR body " + name + " format")
                return None
              }
              if has_precision &&
                format[conversion_index].to_int() != 100 &&
                format[conversion_index].to_int() != 69 &&
                format[conversion_index].to_int() != 101 &&
                format[conversion_index].to_int() != 102 &&
                format[conversion_index].to_int() != 105 &&
                format[conversion_index].to_int() != 88 &&
                format[conversion_index].to_int() != 111 &&
                format[conversion_index].to_int() != 115 &&
                format[conversion_index].to_int() != 117 &&
                format[conversion_index].to_int() != 120 {
                self.fail("unsupported MIR body " + name + " format")
                return None
              }
              if (plus_flag || space_flag) &&
                format[conversion_index].to_int() != 100 &&
                format[conversion_index].to_int() != 69 &&
                format[conversion_index].to_int() != 101 &&
                format[conversion_index].to_int() != 102 &&
                format[conversion_index].to_int() != 105 {
                self.fail("unsupported MIR body " + name + " format")
                return None
              }
              if alternate_flag &&
                format[conversion_index].to_int() != 111 &&
                format[conversion_index].to_int() != 88 &&
                format[conversion_index].to_int() != 120 {
                self.fail("unsupported MIR body " + name + " format")
                return None
              }
              if value_index >= values.length() {
                self.fail("unsupported MIR body " + name + " argument")
                return None
              }
              let mut conversion_length = 0L
              if format[conversion_index].to_int() == 99 {
                conversion_length = 1L
              } else if format[conversion_index].to_int() == 115 {
                match self.c_string_len_for_addr(frame, values[value_index]) {
                  Some(length) => {
                    conversion_length = length
                    if has_precision && precision < conversion_length {
                      conversion_length = precision
                    }
                  }
                  None => {
                    self.fail(
                      "unsupported MIR body " + name + " string argument",
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
                      "unsupported MIR body " + name + " radix argument",
                    )
                    return None
                  }
                }
              } else if format[conversion_index].to_int() == 112 {
                match mir_body_printf_pointer_string(values[value_index]) {
                  Some(text) => conversion_length = text.length().to_int64()
                  None => {
                    self.fail(
                      "unsupported MIR body " + name + " pointer argument",
                    )
                    return None
                  }
                }
              } else if format[conversion_index].to_int() == 102 {
                match
                  mir_body_printf_fixed_parts(
                    values[value_index],
                    plus_flag,
                    space_flag,
                    has_precision,
                    precision,
                  ) {
                  Some(parts) =>
                    conversion_length = parts.0.length().to_int64() +
                      parts.1.length().to_int64()
                  None => {
                    self.fail(
                      "unsupported MIR body " + name + " floating argument",
                    )
                    return None
                  }
                }
              } else if format[conversion_index].to_int() == 69 ||
                format[conversion_index].to_int() == 101 {
                match
                  mir_body_printf_scientific_parts(
                    values[value_index],
                    format[conversion_index].to_int() == 69,
                    plus_flag,
                    space_flag,
                    has_precision,
                    precision,
                  ) {
                  Some(parts) =>
                    conversion_length = parts.0.length().to_int64() +
                      parts.1.length().to_int64()
                  None => {
                    self.fail(
                      "unsupported MIR body " + name + " floating argument",
                    )
                    return None
                  }
                }
              } else if format[conversion_index].to_int() == 110 {
                ignore(
                  self.write_address(
                    frame,
                    values[value_index],
                    length,
                    mir_body_printf_count_store_type(modifier),
                  ),
                )
                if self.failed() {
                  return None
                }
              } else {
                if format[conversion_index].to_int() == 117 &&
                  values[value_index] < 0L {
                  self.fail(
                    "unsupported MIR body " + name + " unsigned argument",
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
              self.fail("unsupported MIR body " + name + " format")
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
      self.fail("unsupported MIR body " + name + " format argument")
      None
    }
  }
}

///|
fn mir_body_nonnegative_radix_string(
  value : Int64,
  radix : Int64,
  uppercase : Bool,
) -> String? {
  if value < 0L || radix < 2L || radix > 16L {
    return None
  }
  let digits = if uppercase { "0123456789ABCDEF" } else { "0123456789abcdef" }
  let buf = StringBuilder::new()
  let stack : Array[Int] = []
  let mut n = value
  if n == 0L {
    stack.push(0)
  } else {
    while n > 0L {
      stack.push((n % radix).to_int())
      n = n / radix
    }
  }
  for i = stack.length() - 1; i >= 0; i = i - 1 {
    buf.write_char(digits[stack[i]].unsafe_to_char())
  }
  Some(buf.to_string())
}

///|
fn mir_body_write_repeat(buf : StringBuilder, ch : Char, count : Int64) -> Unit {
  let mut i = 0L
  while i < count {
    buf.write_char(ch)
    i += 1L
  }
}

///|
fn mir_body_printf_digits_with_precision(
  digits : String,
  precision : Int64,
) -> String {
  let buf = StringBuilder::new()
  let pad = precision - digits.length().to_int64()
  if pad > 0L {
    mir_body_write_repeat(buf, '0', pad)
  }
  buf.write_string(digits)
  buf.to_string()
}

///|
fn mir_body_printf_write_field(
  buf : StringBuilder,
  text : String,
  width : Int64,
  left_flag : Bool,
) -> Unit {
  let pad = width - text.length().to_int64()
  if !left_flag && pad > 0L {
    mir_body_write_repeat(buf, ' ', pad)
  }
  buf.write_string(text)
  if left_flag && pad > 0L {
    mir_body_write_repeat(buf, ' ', pad)
  }
}

///|
fn mir_body_printf_write_numeric(
  buf : StringBuilder,
  prefix : String,
  digits : String,
  width : Int64,
  left_flag : Bool,
  zero_flag : Bool,
) -> Unit {
  let length = prefix.length().to_int64() + digits.length().to_int64()
  let pad = width - length
  if !left_flag && !zero_flag && pad > 0L {
    mir_body_write_repeat(buf, ' ', pad)
  }
  buf.write_string(prefix)
  if !left_flag && zero_flag && pad > 0L {
    mir_body_write_repeat(buf, '0', pad)
  }
  buf.write_string(digits)
  if left_flag && pad > 0L {
    mir_body_write_repeat(buf, ' ', pad)
  }
}

///|
fn mir_body_printf_signed_parts(
  value : Int64,
  plus_flag : Bool,
  space_flag : Bool,
  has_precision : Bool,
  precision : Int64,
) -> (String, String) {
  let prefix = if value < 0L {
    "-"
  } else if plus_flag {
    "+"
  } else if space_flag {
    " "
  } else {
    ""
  }
  let raw_digits = if has_precision && value == 0L && precision == 0L {
    ""
  } else if value < 0L {
    (0L - value).to_string()
  } else {
    value.to_string()
  }
  let digits = if has_precision {
    mir_body_printf_digits_with_precision(raw_digits, precision)
  } else {
    raw_digits
  }
  (prefix, digits)
}

///|
fn mir_body_printf_pow10(precision : Int64) -> Int64? {
  if precision < 0L || precision > 18L {
    return None
  }
  let mut factor = 1L
  let mut i = 0L
  while i < precision {
    factor *= 10L
    i += 1L
  }
  Some(factor)
}

///|
fn mir_body_printf_fixed_parts(
  bits : Int64,
  plus_flag : Bool,
  space_flag : Bool,
  has_precision : Bool,
  precision : Int64,
) -> (String, String)? {
  let precision = if has_precision { precision } else { 6L }
  match mir_body_printf_pow10(precision) {
    Some(factor) => {
      let value = bits.reinterpret_as_double()
      let pos_inf = 1.0 / 0.0
      let neg_inf = 0.0 - pos_inf
      if value != value || value == pos_inf || value == neg_inf {
        return None
      }
      let negative = @ctype.floating_signbit(value)
      let prefix = if negative {
        "-"
      } else if plus_flag {
        "+"
      } else if space_flag {
        " "
      } else {
        ""
      }
      let scaled = (@ctype.floating_abs(value) * factor.to_double() + 0.5).to_int64()
      let whole = scaled / factor
      let frac = scaled % factor
      let digits = if precision > 0L {
        whole.to_string() +
        "." +
        mir_body_printf_digits_with_precision(frac.to_string(), precision)
      } else {
        whole.to_string()
      }
      Some((prefix, digits))
    }
    None => None
  }
}

///|
fn mir_body_printf_exponent_suffix(exponent : Int, uppercase : Bool) -> String {
  let buf = StringBuilder::new()
  buf.write_char(if uppercase { 'E' } else { 'e' })
  if exponent < 0 {
    buf.write_char('-')
  } else {
    buf.write_char('+')
  }
  let abs_exp = if exponent < 0 { 0 - exponent } else { exponent }
  let digits = abs_exp.to_string()
  if digits.length() < 2 {
    buf.write_char('0')
  }
  buf.write_string(digits)
  buf.to_string()
}

///|
fn mir_body_printf_scientific_parts(
  bits : Int64,
  uppercase : Bool,
  plus_flag : Bool,
  space_flag : Bool,
  has_precision : Bool,
  precision : Int64,
) -> (String, String)? {
  let precision = if has_precision { precision } else { 6L }
  if precision > 17L {
    return None
  }
  match mir_body_printf_pow10(precision) {
    Some(factor) => {
      let value = bits.reinterpret_as_double()
      let pos_inf = 1.0 / 0.0
      let neg_inf = 0.0 - pos_inf
      if value != value || value == pos_inf || value == neg_inf {
        return None
      }
      let negative = @ctype.floating_signbit(value)
      let prefix = if negative {
        "-"
      } else if plus_flag {
        "+"
      } else if space_flag {
        " "
      } else {
        ""
      }
      let mut normalized = @ctype.floating_abs(value)
      let mut exponent = 0
      if normalized != 0.0 {
        while normalized >= 10.0 {
          normalized = normalized / 10.0
          exponent += 1
        }
        while normalized < 1.0 {
          normalized = normalized * 10.0
          exponent -= 1
        }
      }
      let mut scaled = (normalized * factor.to_double() + 0.5).to_int64()
      if scaled >= factor * 10L {
        scaled = factor
        exponent += 1
      }
      let whole = scaled / factor
      let frac = scaled % factor
      let mantissa = if precision > 0L {
        whole.to_string() +
        "." +
        mir_body_printf_digits_with_precision(frac.to_string(), precision)
      } else {
        whole.to_string()
      }
      Some(
        (
          prefix,
          mantissa + mir_body_printf_exponent_suffix(exponent, uppercase),
        ),
      )
    }
    None => None
  }
}

///|
fn mir_body_printf_unsigned_parts(
  value : Int64,
  radix : Int64,
  uppercase : Bool,
  alternate_flag : Bool,
  has_precision : Bool,
  precision : Int64,
) -> (String, String)? {
  let raw_digits = if has_precision && value == 0L && precision == 0L {
    ""
  } else {
    match mir_body_nonnegative_radix_string(value, radix, uppercase) {
      Some(text) => text
      None => return None
    }
  }
  let mut prefix = ""
  let mut digit_precision = precision
  if alternate_flag && radix == 8L {
    if has_precision {
      if value == 0L && precision == 0L {
        prefix = "0"
      } else if value != 0L && precision <= raw_digits.length().to_int64() {
        prefix = "0"
      }
    } else if value != 0L {
      prefix = "0"
    }
  } else if alternate_flag && value != 0L {
    prefix = if uppercase { "0X" } else { "0x" }
  }
  if !has_precision {
    digit_precision = raw_digits.length().to_int64()
  }
  let digits = if digit_precision > raw_digits.length().to_int64() {
    mir_body_printf_digits_with_precision(raw_digits, digit_precision)
  } else {
    raw_digits
  }
  Some((prefix, digits))
}

///|
fn mir_body_printf_pointer_string(value : Int64) -> String? {
  match mir_body_nonnegative_radix_string(value, 16L, false) {
    Some(digits) => Some("0x" + digits)
    None => None
  }
}

///|
fn BodyInterpreter::printf_string_arg(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
  has_precision : Bool,
  precision : Int64,
) -> String? {
  let limit = if has_precision { precision } else { 100000L }
  let buf = StringBuilder::new()
  let mut index = 0L
  while index < limit {
    match self.c_memory_byte_for_addr(frame, mir_body_elem_addr(addr, index)) {
      Some(byte) =>
        if byte == 0L {
          return Some(buf.to_string())
        } else {
          buf.write_char((byte & 0xFFL).to_int().unsafe_to_char())
        }
      None => return None
    }
    index += 1L
  }
  if has_precision {
    Some(buf.to_string())
  } else {
    match self.c_memory_byte_for_addr(frame, mir_body_elem_addr(addr, index)) {
      Some(0L) => Some(buf.to_string())
      _ => None
    }
  }
}

///|
fn BodyInterpreter::literal_printf_format_output(
  self : BodyInterpreter,
  frame : BodyFrame,
  format_addr : Int64,
  values : Array[Int64],
  first_value_index : Int,
) -> String? {
  match self.string_literal_for_addr(format_addr) {
    Some((format, offset)) => {
      if offset < 0L || offset > format.length().to_int64() {
        return None
      }
      let buf = StringBuilder::new()
      let mut index = offset.to_int()
      let mut value_index = first_value_index
      while index < format.length() {
        let byte = format[index].to_int()
        if byte == 0 {
          return Some(buf.to_string())
        }
        if byte != 37 {
          buf.write_char(format[index].unsafe_to_char())
          index += 1
          continue
        }
        if index + 1 < format.length() && format[index + 1].to_int() == 37 {
          buf.write_char('%')
          index += 2
          continue
        }
        let mut conversion_index = index + 1
        let mut left_flag = false
        let mut zero_flag = false
        let mut plus_flag = false
        let mut space_flag = false
        let mut alternate_flag = false
        while conversion_index < format.length() {
          let flag = format[conversion_index].to_int()
          if flag == 45 {
            left_flag = true
            conversion_index += 1
          } else if flag == 48 {
            zero_flag = true
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
        if conversion_index < format.length() &&
          format[conversion_index].to_int() == 42 {
          if value_index >= values.length() {
            return None
          }
          width = values[value_index]
          if width < 0L {
            left_flag = true
            width = -width
          }
          value_index += 1
          conversion_index += 1
        } else {
          while conversion_index < format.length() &&
                format[conversion_index].to_int() >= 48 &&
                format[conversion_index].to_int() <= 57 {
            width = width * 10L +
              (format[conversion_index].to_int() - 48).to_int64()
            conversion_index += 1
          }
        }
        let mut has_precision = false
        let mut precision = 0L
        if conversion_index < format.length() &&
          format[conversion_index].to_int() == 46 {
          has_precision = true
          conversion_index += 1
          if conversion_index < format.length() &&
            format[conversion_index].to_int() == 42 {
            if value_index >= values.length() {
              return None
            }
            precision = values[value_index]
            if precision < 0L {
              has_precision = false
              precision = 0L
            }
            value_index += 1
            conversion_index += 1
          } else {
            while conversion_index < format.length() &&
                  format[conversion_index].to_int() >= 48 &&
                  format[conversion_index].to_int() <= 57 {
              precision = precision * 10L +
                (format[conversion_index].to_int() - 48).to_int64()
              conversion_index += 1
            }
          }
        }
        let mut modifier = MirPrintfNoLength
        if conversion_index < format.length() {
          if format[conversion_index].to_int() == 104 {
            conversion_index += 1
            if conversion_index < format.length() &&
              format[conversion_index].to_int() == 104 {
              modifier = MirPrintfHH
              conversion_index += 1
            } else {
              modifier = MirPrintfH
            }
          } else if format[conversion_index].to_int() == 108 {
            modifier = MirPrintfL
            conversion_index += 1
            if conversion_index < format.length() &&
              format[conversion_index].to_int() == 108 {
              modifier = MirPrintfLL
              conversion_index += 1
            }
          } else if format[conversion_index].to_int() == 106 {
            modifier = MirPrintfJ
            conversion_index += 1
          } else if format[conversion_index].to_int() == 116 {
            modifier = MirPrintfT
            conversion_index += 1
          } else if format[conversion_index].to_int() == 122 {
            modifier = MirPrintfZ
            conversion_index += 1
          }
        }
        if conversion_index >= format.length() || value_index >= values.length() {
          return None
        }
        let conversion = format[conversion_index].to_int()
        if modifier != MirPrintfNoLength &&
          (conversion == 99 || conversion == 112 || conversion == 115) {
          return None
        }
        if has_precision &&
          conversion != 100 &&
          conversion != 69 &&
          conversion != 101 &&
          conversion != 102 &&
          conversion != 105 &&
          conversion != 88 &&
          conversion != 111 &&
          conversion != 115 &&
          conversion != 117 &&
          conversion != 120 {
          return None
        }
        if (plus_flag || space_flag) &&
          conversion != 100 &&
          conversion != 69 &&
          conversion != 101 &&
          conversion != 102 &&
          conversion != 105 {
          return None
        }
        if alternate_flag &&
          conversion != 111 &&
          conversion != 88 &&
          conversion != 120 {
          return None
        }
        match conversion {
          99 =>
            if has_precision {
              return None
            } else {
              let char_buf = StringBuilder::new()
              char_buf.write_char(
                (values[value_index] & 0xFFL).to_int().unsafe_to_char(),
              )
              mir_body_printf_write_field(
                buf,
                char_buf.to_string(),
                width,
                left_flag,
              )
            }
          100 | 105 => {
            let parts = mir_body_printf_signed_parts(
              values[value_index],
              plus_flag,
              space_flag,
              has_precision,
              precision,
            )
            mir_body_printf_write_numeric(
              buf,
              parts.0,
              parts.1,
              width,
              left_flag,
              zero_flag && !has_precision,
            )
          }
          117 =>
            if values[value_index] < 0L {
              return None
            } else {
              let digits = if has_precision &&
                values[value_index] == 0L &&
                precision == 0L {
                ""
              } else if has_precision {
                mir_body_printf_digits_with_precision(
                  values[value_index].to_string(),
                  precision,
                )
              } else {
                values[value_index].to_string()
              }
              mir_body_printf_write_numeric(
                buf,
                "",
                digits,
                width,
                left_flag,
                zero_flag && !has_precision,
              )
            }
          111 | 120 | 88 => {
            let radix = if conversion == 111 { 8L } else { 16L }
            match
              mir_body_printf_unsigned_parts(
                values[value_index],
                radix,
                conversion == 88,
                alternate_flag,
                has_precision,
                precision,
              ) {
              Some(parts) =>
                mir_body_printf_write_numeric(
                  buf,
                  parts.0,
                  parts.1,
                  width,
                  left_flag,
                  zero_flag && !has_precision,
                )
              None => return None
            }
          }
          102 =>
            match
              mir_body_printf_fixed_parts(
                values[value_index],
                plus_flag,
                space_flag,
                has_precision,
                precision,
              ) {
              Some(parts) =>
                mir_body_printf_write_numeric(
                  buf,
                  parts.0,
                  parts.1,
                  width,
                  left_flag,
                  zero_flag,
                )
              None => return None
            }
          69 | 101 =>
            match
              mir_body_printf_scientific_parts(
                values[value_index],
                conversion == 69,
                plus_flag,
                space_flag,
                has_precision,
                precision,
              ) {
              Some(parts) =>
                mir_body_printf_write_numeric(
                  buf,
                  parts.0,
                  parts.1,
                  width,
                  left_flag,
                  zero_flag,
                )
              None => return None
            }
          110 => ()
          112 =>
            match mir_body_printf_pointer_string(values[value_index]) {
              Some(text) =>
                mir_body_printf_write_field(buf, text, width, left_flag)
              None => return None
            }
          115 =>
            match
              self.printf_string_arg(
                frame,
                values[value_index],
                has_precision,
                precision,
              ) {
              Some(text) =>
                mir_body_printf_write_field(buf, text, width, left_flag)
              None => return None
            }
          _ => return None
        }
        value_index += 1
        index = conversion_index + 1
      }
      Some(buf.to_string())
    }
    None => None
  }
}

///|
fn BodyInterpreter::write_printf_output(
  self : BodyInterpreter,
  frame : BodyFrame,
  dest : Int64,
  output : String,
  limit : Int64?,
) -> Bool {
  let write_len = match limit {
    Some(size) =>
      if size < 0L {
        return false
      } else if size == 0L {
        return true
      } else if size - 1L < output.length().to_int64() {
        size - 1L
      } else {
        output.length().to_int64()
      }
    None => output.length().to_int64()
  }
  let mut index = 0L
  while index < write_len {
    if !self.write_c_memory_byte_for_addr(
        frame,
        mir_body_elem_addr(dest, index),
        output[index.to_int()].to_int().to_int64(),
      ) {
      return false
    }
    index += 1L
  }
  self.write_c_memory_byte_for_addr(
    frame,
    mir_body_elem_addr(dest, write_len),
    0L,
  )
}

///|
fn BodyInterpreter::string_literal_base(
  self : BodyInterpreter,
  value : String,
) -> Int64 {
  mir_body_string_literal_base(value, self.string_memory, self.string_addrs)
}

///|
fn BodyInterpreter::string_literal_for_addr(
  self : BodyInterpreter,
  addr : Int64,
) -> (String, Int64)? {
  for value in self.string_addrs.keys() {
    let base = self.string_addrs[value]
    let len = value.length().to_int64()
    if addr <= base && addr >= base - len {
      return Some((value, base - addr))
    }
  }
  None
}

///|
fn BodyInterpreter::c_string_len_for_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
) -> Int64? {
  match self.string_literal_for_addr(addr) {
    Some((value, offset)) => Some(mir_body_c_string_len_from(value, offset))
    None => {
      let mut current = addr
      let mut length = 0L
      while self.stack_memory_addr(current) {
        let value = match self.stack_memory.get(current) {
          Some(value) => value
          None => 0L
        }
        if value == 0L {
          return Some(length)
        }
        length += 1L
        current -= 1L
      }
      current = addr
      length = 0L
      while self.frame_memory_addr(frame, current) {
        let value = match frame.memory.get(current) {
          Some(value) => value
          None => 0L
        }
        if value == 0L {
          return Some(length)
        }
        length += 1L
        current -= 1L
      }
      current = addr
      length = 0L
      while self.global_array_elem_addr(current) {
        let value = match self.global_memory.get(current) {
          Some(value) => value
          None => 0L
        }
        if value == 0L {
          return Some(length)
        }
        length += 1L
        current -= 1L
      }
      current = addr
      length = 0L
      while self.string_array_elem_addr(current) {
        let value = match self.string_memory.get(current) {
          Some(value) => value
          None => 0L
        }
        if value == 0L {
          return Some(length)
        }
        length += 1L
        current -= 1L
      }
      None
    }
  }
}

///|
fn BodyInterpreter::c_memory_byte_for_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
) -> Int64? {
  let byte_addr = self.canonical_c_memory_addr(frame, addr)
  if !frame.aggregate_arg_addr(byte_addr) {
    match self.scalar_local_byte_for_addr(frame, byte_addr) {
      Some(value) => return Some(value)
      None => ()
    }
  }
  match self.scalar_global_byte_for_addr(byte_addr) {
    Some(value) => return Some(value)
    None => ()
  }
  match self.read_stack_memory(byte_addr, UChar) {
    Some(value) => return Some(value)
    None => ()
  }
  if self.frame_memory_addr(frame, byte_addr) {
    let value = match frame.memory.get(byte_addr) {
      Some(value) => value
      None => 0L
    }
    Some(self.program.runtime_cast_int(value, UChar))
  } else if self.global_array_elem_addr(byte_addr) {
    let value = match self.global_memory.get(byte_addr) {
      Some(value) => value
      None => 0L
    }
    Some(self.program.runtime_cast_int(value, UChar))
  } else if self.string_array_elem_addr(byte_addr) {
    let value = match self.string_memory.get(byte_addr) {
      Some(value) => value
      None => 0L
    }
    Some(self.program.runtime_cast_int(value, UChar))
  } else {
    None
  }
}

///|
fn BodyInterpreter::bounded_c_string_len_for_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
  limit : Int64,
) -> Int64? {
  if limit < 0L {
    return None
  }
  let mut index = 0L
  while index < limit {
    match self.c_memory_byte_for_addr(frame, mir_body_elem_addr(addr, index)) {
      Some(byte) => if byte == 0L { return Some(index) }
      None => return None
    }
    index += 1L
  }
  Some(limit)
}

///|
fn BodyInterpreter::write_c_memory_byte_for_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
  byte : Int64,
) -> Bool {
  let value = self.program.runtime_cast_int(byte, UChar)
  let byte_addr = self.canonical_c_memory_addr(frame, addr)
  if !frame.aggregate_arg_addr(byte_addr) {
    if self.write_scalar_local_byte_for_addr(frame, byte_addr, value) {
      return true
    }
  }
  if self.write_scalar_global_byte_for_addr(byte_addr, value) {
    return true
  }
  match self.write_stack_memory(frame, byte_addr, value, UChar) {
    Some(_) => return true
    None => ()
  }
  if self.frame_memory_addr(frame, byte_addr) {
    frame.memory[byte_addr] = value
    true
  } else if self.global_array_elem_addr(byte_addr) {
    self.global_memory[byte_addr] = value
    true
  } else {
    false
  }
}

///|
fn BodyInterpreter::copy_c_memory_bytes(
  self : BodyInterpreter,
  frame : BodyFrame,
  dest : Int64,
  src : Int64,
  length : Int64,
) -> Bool {
  if length < 0L {
    return false
  }
  let bytes : Array[Int64] = []
  let mut index = 0L
  while index < length {
    match self.c_memory_byte_for_addr(frame, mir_body_elem_addr(src, index)) {
      Some(byte) => bytes.push(byte)
      None => return false
    }
    index += 1L
  }
  index = 0L
  for byte in bytes {
    if !self.write_c_memory_byte_for_addr(
        frame,
        mir_body_elem_addr(dest, index),
        byte,
      ) {
      return false
    }
    index += 1L
  }
  true
}

///|
fn BodyInterpreter::set_c_memory_bytes(
  self : BodyInterpreter,
  frame : BodyFrame,
  dest : Int64,
  byte : Int64,
  length : Int64,
) -> Bool {
  if length < 0L {
    return false
  }
  let mut index = 0L
  while index < length {
    if !self.write_c_memory_byte_for_addr(
        frame,
        mir_body_elem_addr(dest, index),
        byte,
      ) {
      return false
    }
    index += 1L
  }
  true
}

///|
fn BodyInterpreter::read_c_memory_scalar_for_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
  ty : @ctype.Type,
) -> Int64? {
  if !self.program.mir_body_scalar_byte_memory_type(ty) {
    return None
  }
  let size = self.program.type_size(ty).to_int64()
  let mut bits = 0L
  for index in 0L..<size {
    match self.c_memory_byte_for_addr(frame, mir_body_elem_addr(addr, index)) {
      Some(byte) => bits = mir_body_store_scalar_byte(bits, index, byte)
      None => return None
    }
  }
  Some(self.program.mir_body_scalar_value_bits(bits, ty))
}

///|
fn BodyInterpreter::write_c_memory_scalar_for_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
  value : Int64,
  ty : @ctype.Type,
) -> Int64? {
  if !self.program.mir_body_scalar_byte_memory_type(ty) {
    return None
  }
  let assigned = self.program.runtime_cast_int(value, ty)
  let object_bits = self.program.mir_body_scalar_object_bits(assigned, ty)
  let size = self.program.type_size(ty).to_int64()
  for index in 0L..<size {
    if !self.write_c_memory_byte_for_addr(
        frame,
        mir_body_elem_addr(addr, index),
        mir_body_scalar_byte(object_bits, index),
      ) {
      return None
    }
  }
  Some(assigned)
}

///|
fn BodyInterpreter::copy_c_string_bytes(
  self : BodyInterpreter,
  frame : BodyFrame,
  dest : Int64,
  src : Int64,
) -> Int64? {
  match self.c_string_len_for_addr(frame, src) {
    Some(length) =>
      if self.copy_c_memory_bytes(frame, dest, src, length + 1L) {
        Some(length)
      } else {
        None
      }
    None => None
  }
}

///|
fn BodyInterpreter::copy_c_string_n_bytes(
  self : BodyInterpreter,
  frame : BodyFrame,
  dest : Int64,
  src : Int64,
  length : Int64,
) -> Int64? {
  if length < 0L {
    return None
  }
  let source_length = match self.c_string_len_for_addr(frame, src) {
    Some(value) => value
    None => return None
  }
  let mut index = 0L
  while index < length {
    let byte = if index <= source_length {
      match self.c_memory_byte_for_addr(frame, mir_body_elem_addr(src, index)) {
        Some(value) => value
        None => return None
      }
    } else {
      0L
    }
    if !self.write_c_memory_byte_for_addr(
        frame,
        mir_body_elem_addr(dest, index),
        byte,
      ) {
      return None
    }
    index += 1L
  }
  mir_body_nonnegative_min(source_length, length)
}

///|
fn BodyInterpreter::append_c_string_bytes(
  self : BodyInterpreter,
  frame : BodyFrame,
  dest : Int64,
  src : Int64,
) -> Bool {
  match self.c_string_len_for_addr(frame, dest) {
    Some(dest_length) =>
      match
        self.copy_c_string_bytes(
          frame,
          mir_body_elem_addr(dest, dest_length),
          src,
        ) {
        Some(_) => true
        None => false
      }
    None => false
  }
}

///|
fn BodyInterpreter::append_c_string_n_bytes(
  self : BodyInterpreter,
  frame : BodyFrame,
  dest : Int64,
  src : Int64,
  length : Int64,
) -> Bool {
  if length < 0L {
    return false
  }
  let dest_length = match self.c_string_len_for_addr(frame, dest) {
    Some(value) => value
    None => return false
  }
  let source_length = match self.c_string_len_for_addr(frame, src) {
    Some(value) => value
    None => return false
  }
  let count = match mir_body_nonnegative_min(source_length, length) {
    Some(value) => value
    None => return false
  }
  let mut index = 0L
  while index < count {
    let byte = match
      self.c_memory_byte_for_addr(frame, mir_body_elem_addr(src, index)) {
      Some(value) => value
      None => return false
    }
    if !self.write_c_memory_byte_for_addr(
        frame,
        mir_body_elem_addr(dest, dest_length + index),
        byte,
      ) {
      return false
    }
    index += 1L
  }
  self.write_c_memory_byte_for_addr(
    frame,
    mir_body_elem_addr(dest, dest_length + count),
    0L,
  )
}

///|
fn BodyInterpreter::copy_c_string_l_bytes(
  self : BodyInterpreter,
  frame : BodyFrame,
  dest : Int64,
  src : Int64,
  size : Int64,
) -> Int64? {
  if size < 0L {
    return None
  }
  let source_length = match self.c_string_len_for_addr(frame, src) {
    Some(value) => value
    None => return None
  }
  if size == 0L {
    return Some(source_length)
  }
  let count = match mir_body_nonnegative_min(source_length, size - 1L) {
    Some(value) => value
    None => return None
  }
  if !self.copy_c_memory_bytes(frame, dest, src, count) {
    return None
  }
  if !self.write_c_memory_byte_for_addr(
      frame,
      mir_body_elem_addr(dest, count),
      0L,
    ) {
    return None
  }
  Some(source_length)
}

///|
fn BodyInterpreter::append_c_string_l_bytes(
  self : BodyInterpreter,
  frame : BodyFrame,
  dest : Int64,
  src : Int64,
  size : Int64,
) -> Int64? {
  if size < 0L {
    return None
  }
  let source_length = match self.c_string_len_for_addr(frame, src) {
    Some(value) => value
    None => return None
  }
  if size == 0L {
    return Some(source_length)
  }
  let dest_length = match
    self.bounded_c_string_len_for_addr(frame, dest, size) {
    Some(value) => value
    None => return None
  }
  let result = dest_length + source_length
  if dest_length >= size {
    return Some(result)
  }
  let count = match
    mir_body_nonnegative_min(source_length, size - dest_length - 1L) {
    Some(value) => value
    None => return None
  }
  if !self.copy_c_memory_bytes(
      frame,
      mir_body_elem_addr(dest, dest_length),
      src,
      count,
    ) {
    return None
  }
  if !self.write_c_memory_byte_for_addr(
      frame,
      mir_body_elem_addr(dest, dest_length + count),
      0L,
    ) {
    return None
  }
  Some(result)
}

///|
fn BodyInterpreter::compare_c_memory_bytes(
  self : BodyInterpreter,
  frame : BodyFrame,
  left : Int64,
  right : Int64,
  limit : Int64?,
  stop_at_nul : Bool,
) -> Int64? {
  match limit {
    Some(n) => if n < 0L { return None }
    None => ()
  }
  let mut index = 0L
  while true {
    match limit {
      Some(n) => if index >= n { return Some(0L) }
      None => ()
    }
    match
      (
        self.c_memory_byte_for_addr(frame, mir_body_elem_addr(left, index)),
        self.c_memory_byte_for_addr(frame, mir_body_elem_addr(right, index)),
      ) {
      (Some(lhs), Some(rhs)) => {
        if lhs != rhs {
          return Some(if lhs < rhs { -1L } else { 1L })
        }
        if stop_at_nul && lhs == 0L {
          return Some(0L)
        }
      }
      _ => return None
    }
    index += 1L
  }
  Some(0L)
}

///|
fn mir_body_ascii_lower_byte(byte : Int64) -> Int64 {
  let value = byte & 0xFFL
  if value >= 65L && value <= 90L {
    value + 32L
  } else {
    value
  }
}

///|
fn BodyInterpreter::compare_c_memory_bytes_casefold(
  self : BodyInterpreter,
  frame : BodyFrame,
  left : Int64,
  right : Int64,
  limit : Int64?,
) -> Int64? {
  match limit {
    Some(n) => if n < 0L { return None }
    None => ()
  }
  let mut index = 0L
  while true {
    match limit {
      Some(n) => if index >= n { return Some(0L) }
      None => ()
    }
    match
      (
        self.c_memory_byte_for_addr(frame, mir_body_elem_addr(left, index)),
        self.c_memory_byte_for_addr(frame, mir_body_elem_addr(right, index)),
      ) {
      (Some(lhs), Some(rhs)) => {
        let lhs_folded = mir_body_ascii_lower_byte(lhs)
        let rhs_folded = mir_body_ascii_lower_byte(rhs)
        if lhs_folded != rhs_folded {
          return Some(if lhs_folded < rhs_folded { -1L } else { 1L })
        }
        if lhs == 0L {
          return Some(0L)
        }
      }
      _ => return None
    }
    index += 1L
  }
  Some(0L)
}

///|
fn BodyInterpreter::find_c_memory_byte(
  self : BodyInterpreter,
  frame : BodyFrame,
  start : Int64,
  byte : Int64,
  limit : Int64?,
  stop_at_nul : Bool,
) -> Int64? {
  match limit {
    Some(n) => if n < 0L { return None }
    None => ()
  }
  let needle = byte & 0xFFL
  let mut index = 0L
  while true {
    match limit {
      Some(n) => if index >= n { return Some(0L) }
      None => ()
    }
    let addr = mir_body_elem_addr(start, index)
    match self.c_memory_byte_for_addr(frame, addr) {
      Some(current) => {
        if current == needle {
          return Some(addr)
        }
        if stop_at_nul && current == 0L {
          return Some(0L)
        }
      }
      None => return None
    }
    index += 1L
  }
  Some(0L)
}

///|
fn BodyInterpreter::find_last_c_string_byte(
  self : BodyInterpreter,
  frame : BodyFrame,
  start : Int64,
  byte : Int64,
) -> Int64? {
  let needle = byte & 0xFFL
  let mut index = 0L
  let mut found = 0L
  while true {
    let addr = mir_body_elem_addr(start, index)
    match self.c_memory_byte_for_addr(frame, addr) {
      Some(current) => {
        if current == needle {
          found = addr
        }
        if current == 0L {
          return Some(found)
        }
      }
      None => return None
    }
    index += 1L
  }
  Some(found)
}

///|
fn BodyInterpreter::find_c_string(
  self : BodyInterpreter,
  frame : BodyFrame,
  haystack : Int64,
  needle : Int64,
) -> Int64? {
  match
    (
      self.c_string_len_for_addr(frame, haystack),
      self.c_string_len_for_addr(frame, needle),
    ) {
    (Some(haystack_length), Some(needle_length)) => {
      if needle_length == 0L {
        return Some(haystack)
      }
      if haystack_length < needle_length {
        return Some(0L)
      }
      let mut offset = 0L
      while offset <= haystack_length - needle_length {
        let candidate = mir_body_elem_addr(haystack, offset)
        match
          self.compare_c_memory_bytes(
            frame,
            candidate,
            needle,
            Some(needle_length),
            false,
          ) {
          Some(result) => if result == 0L { return Some(candidate) }
          None => return None
        }
        offset += 1L
      }
      Some(0L)
    }
    _ => None
  }
}

///|
fn BodyInterpreter::find_c_string_casefold(
  self : BodyInterpreter,
  frame : BodyFrame,
  haystack : Int64,
  needle : Int64,
) -> Int64? {
  match
    (
      self.c_string_len_for_addr(frame, haystack),
      self.c_string_len_for_addr(frame, needle),
    ) {
    (Some(haystack_length), Some(needle_length)) => {
      if needle_length == 0L {
        return Some(haystack)
      }
      if haystack_length < needle_length {
        return Some(0L)
      }
      let mut offset = 0L
      while offset <= haystack_length - needle_length {
        let candidate = mir_body_elem_addr(haystack, offset)
        match
          self.compare_c_memory_bytes_casefold(
            frame,
            candidate,
            needle,
            Some(needle_length),
          ) {
          Some(result) => if result == 0L { return Some(candidate) }
          None => return None
        }
        offset += 1L
      }
      Some(0L)
    }
    _ => None
  }
}

///|
fn BodyInterpreter::c_string_byte_set_contains(
  self : BodyInterpreter,
  frame : BodyFrame,
  set : Int64,
  byte : Int64,
) -> Bool? {
  let needle = byte & 0xFFL
  let mut index = 0L
  while true {
    match self.c_memory_byte_for_addr(frame, mir_body_elem_addr(set, index)) {
      Some(current) => {
        if current == 0L {
          return Some(false)
        }
        if current == needle {
          return Some(true)
        }
      }
      None => return None
    }
    index += 1L
  }
  Some(false)
}

///|
fn BodyInterpreter::span_c_string_byte_set(
  self : BodyInterpreter,
  frame : BodyFrame,
  start : Int64,
  set : Int64,
  want_in_set : Bool,
) -> Int64? {
  let mut index = 0L
  while true {
    match self.c_memory_byte_for_addr(frame, mir_body_elem_addr(start, index)) {
      Some(current) => {
        if current == 0L {
          return Some(index)
        }
        match self.c_string_byte_set_contains(frame, set, current) {
          Some(in_set) => if in_set != want_in_set { return Some(index) }
          None => return None
        }
      }
      None => return None
    }
    index += 1L
  }
  Some(index)
}

///|
fn BodyInterpreter::find_c_string_byte_set(
  self : BodyInterpreter,
  frame : BodyFrame,
  start : Int64,
  set : Int64,
) -> Int64? {
  let mut index = 0L
  while true {
    let addr = mir_body_elem_addr(start, index)
    match self.c_memory_byte_for_addr(frame, addr) {
      Some(current) => {
        if current == 0L {
          return Some(0L)
        }
        match self.c_string_byte_set_contains(frame, set, current) {
          Some(in_set) => if in_set { return Some(addr) }
          None => return None
        }
      }
      None => return None
    }
    index += 1L
  }
  Some(0L)
}

///|
fn BodyInterpreter::eval_c_string_strsep(
  self : BodyInterpreter,
  frame : BodyFrame,
  stringp : Int64,
  delim : Int64,
) -> Int64? {
  let token = self.read_address(
    frame,
    stringp,
    Pointer(SChar),
    "unsupported MIR body strsep string pointer",
  )
  if token == 0L {
    return Some(0L)
  }
  match self.find_c_string_byte_set(frame, token, delim) {
    Some(0L) => {
      ignore(self.write_address(frame, stringp, 0L, Pointer(SChar)))
      Some(token)
    }
    Some(delim_addr) => {
      if !self.write_c_memory_byte_for_addr(frame, delim_addr, 0L) {
        return None
      }
      ignore(
        self.write_address(
          frame,
          stringp,
          mir_body_elem_addr(delim_addr, 1L),
          Pointer(SChar),
        ),
      )
      Some(token)
    }
    None => None
  }
}

///|
fn BodyInterpreter::eval_c_string_strtok(
  self : BodyInterpreter,
  frame : BodyFrame,
  input : Int64,
  delim : Int64,
) -> Int64? {
  let mut current = if input != 0L { input } else { self.strtok_next }
  if current == 0L {
    return Some(0L)
  }
  while true {
    match self.c_memory_byte_for_addr(frame, current) {
      Some(byte) => {
        if byte == 0L {
          self.strtok_next = 0L
          return Some(0L)
        }
        match self.c_string_byte_set_contains(frame, delim, byte) {
          Some(true) => current = mir_body_elem_addr(current, 1L)
          Some(false) => break
          None => return None
        }
      }
      None => return None
    }
  }
  let token = current
  while true {
    match self.c_memory_byte_for_addr(frame, current) {
      Some(byte) => {
        if byte == 0L {
          self.strtok_next = 0L
          return Some(token)
        }
        match self.c_string_byte_set_contains(frame, delim, byte) {
          Some(true) => {
            if !self.write_c_memory_byte_for_addr(frame, current, 0L) {
              return None
            }
            self.strtok_next = mir_body_elem_addr(current, 1L)
            return Some(token)
          }
          Some(false) => current = mir_body_elem_addr(current, 1L)
          None => return None
        }
      }
      None => return None
    }
  }
  Some(token)
}

///|
fn mir_body_ascii_space_byte(byte : Int64) -> Bool {
  byte == 32L || (byte >= 9L && byte <= 13L)
}

///|
fn mir_body_ascii_digit_value(byte : Int64) -> Int64? {
  if byte >= 48L && byte <= 57L {
    Some(byte - 48L)
  } else if byte >= 65L && byte <= 90L {
    Some(byte - 65L + 10L)
  } else if byte >= 97L && byte <= 122L {
    Some(byte - 97L + 10L)
  } else {
    None
  }
}

///|
fn BodyInterpreter::c_integer_digit_at(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
  base : Int64,
) -> Int64? {
  match self.c_memory_byte_for_addr(frame, addr) {
    Some(byte) =>
      match mir_body_ascii_digit_value(byte) {
        Some(digit) => if digit < base { Some(digit) } else { None }
        None => None
      }
    None => None
  }
}

///|
fn BodyInterpreter::c_integer_prefixed_hex(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
) -> Bool? {
  match self.c_memory_byte_for_addr(frame, addr) {
    Some(first) =>
      if first != 48L {
        Some(false)
      } else {
        match self.c_memory_byte_for_addr(frame, mir_body_elem_addr(addr, 1L)) {
          Some(second) =>
            if second == 120L || second == 88L {
              Some(
                self.c_integer_digit_at(
                  frame,
                  mir_body_elem_addr(addr, 2L),
                  16L,
                )
                is Some(_),
              )
            } else {
              Some(false)
            }
          None => None
        }
      }
    None => None
  }
}

///|
fn BodyInterpreter::parse_c_integer(
  self : BodyInterpreter,
  frame : BodyFrame,
  start : Int64,
  requested_base : Int64,
) -> (Int64, Int64)? {
  if requested_base != 0L && (requested_base < 2L || requested_base > 36L) {
    return None
  }
  let original = start
  let mut current = start
  while true {
    match self.c_memory_byte_for_addr(frame, current) {
      Some(byte) =>
        if mir_body_ascii_space_byte(byte) {
          current = mir_body_elem_addr(current, 1L)
        } else {
          break
        }
      None => return None
    }
  }
  let mut negative = false
  match self.c_memory_byte_for_addr(frame, current) {
    Some(byte) =>
      if byte == 43L || byte == 45L {
        negative = byte == 45L
        current = mir_body_elem_addr(current, 1L)
      }
    None => return None
  }
  let mut base = requested_base
  if base == 0L {
    match self.c_integer_prefixed_hex(frame, current) {
      Some(true) => {
        base = 16L
        current = mir_body_elem_addr(current, 2L)
      }
      Some(false) =>
        match self.c_memory_byte_for_addr(frame, current) {
          Some(byte) => base = if byte == 48L { 8L } else { 10L }
          None => return None
        }
      None => return None
    }
  } else if base == 16L {
    match self.c_integer_prefixed_hex(frame, current) {
      Some(true) => current = mir_body_elem_addr(current, 2L)
      Some(false) => ()
      None => return None
    }
  }
  let mut value = 0L
  let mut digits = 0
  while true {
    match self.c_memory_byte_for_addr(frame, current) {
      Some(byte) =>
        match mir_body_ascii_digit_value(byte) {
          Some(digit) =>
            if digit < base {
              value = value * base + digit
              digits += 1
              current = mir_body_elem_addr(current, 1L)
            } else {
              break
            }
          None => break
        }
      None => return None
    }
  }
  if digits == 0 {
    Some((0L, original))
  } else if negative {
    Some((-value, current))
  } else {
    Some((value, current))
  }
}

///|
fn BodyInterpreter::eval_c_string_integer_conversion(
  self : BodyInterpreter,
  frame : BodyFrame,
  name : String,
  args : Array[Int64],
) -> Int64? {
  let uses_endptr = name == "strtol" ||
    name == "strtoll" ||
    name == "strtoul" ||
    name == "strtoull"
  if uses_endptr {
    if args.length() != 3 {
      self.fail("MIR body " + name + " argument count mismatch")
      return Some(0L)
    }
    if args[2] != 0L && (args[2] < 2L || args[2] > 36L) {
      self.fail("unsupported MIR body " + name + " base")
      return Some(0L)
    }
  } else if args.length() != 1 {
    self.fail("MIR body " + name + " argument count mismatch")
    return Some(0L)
  }
  let base = if uses_endptr { args[2] } else { 10L }
  match self.parse_c_integer(frame, args[0], base) {
    Some((value, end_addr)) => {
      if uses_endptr && args[1] != 0L {
        ignore(self.write_address(frame, args[1], end_addr, Pointer(SChar)))
      }
      Some(value)
    }
    None => None
  }
}

///|
fn BodyInterpreter::find_c_memory(
  self : BodyInterpreter,
  frame : BodyFrame,
  haystack : Int64,
  haystack_length : Int64,
  needle : Int64,
  needle_length : Int64,
) -> Int64? {
  if haystack_length < 0L || needle_length < 0L {
    return None
  }
  if needle_length == 0L {
    return match self.program.target {
      DarwinArm64 => Some(0L)
      LinuxAmd64 => Some(haystack)
    }
  }
  if haystack_length < needle_length {
    return Some(0L)
  }
  let mut offset = 0L
  while offset <= haystack_length - needle_length {
    let candidate = mir_body_elem_addr(haystack, offset)
    match
      self.compare_c_memory_bytes(
        frame,
        candidate,
        needle,
        Some(needle_length),
        false,
      ) {
      Some(result) => if result == 0L { return Some(candidate) }
      None => return None
    }
    offset += 1L
  }
  Some(0L)
}

///|
fn BodyInterpreter::string_array_elem_addr(
  self : BodyInterpreter,
  addr : Int64,
) -> Bool {
  for value in self.string_addrs.keys() {
    let base = self.string_addrs[value]
    let len = @ctype.string_literal_array_length(value)
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
            match mir_body_array_info(decl.ty) {
              Some((elem_ty, len)) => {
                let elem_size = self.program.type_size(elem_ty).to_int64()
                let base = self.global_addrs[name]
                if addr <= base && addr > base - elem_size * len.to_int64() {
                  return true
                }
                match self.program.core_type(elem_ty) {
                  Struct(_) | Union(_) =>
                    for i in 0..<len {
                      let elem_base = mir_body_offset_addr(
                        mir_body_typed_elem_addr(
                          self.program,
                          base,
                          i.to_int64(),
                          elem_ty,
                        ),
                        0,
                      )
                      if addr <= elem_base && addr > elem_base - elem_size {
                        return true
                      }
                    }
                  _ => ()
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
    if self.local_addr(binding) == addr {
      return Some(binding)
    }
  }
  None
}

///|
fn mir_body_canonical_aggregate_byte_addr(
  raw_base : Int64,
  size : Int64,
  addr : Int64,
) -> Int64? {
  if size > 0L && addr <= raw_base && addr > raw_base - size {
    Some(mir_body_offset_addr(raw_base, 0) - (raw_base - addr))
  } else {
    None
  }
}

///|
fn BodyInterpreter::local_raw_aggregate_byte_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
) -> Int64? {
  for binding in frame.bindings.values() {
    match self.program.core_type(binding.ty) {
      Struct(_) | Union(_) =>
        match
          mir_body_canonical_aggregate_byte_addr(
            frame.local_addr(binding),
            self.program.type_size(binding.ty).to_int64(),
            addr,
          ) {
          Some(value) => return Some(value)
          None => ()
        }
      _ =>
        match mir_body_array_info(binding.ty) {
          Some((elem_ty, len)) =>
            match self.program.core_type(elem_ty) {
              Struct(_) | Union(_) => {
                let elem_size = self.program.type_size(elem_ty).to_int64()
                for i in 0..<len {
                  let raw_base = mir_body_typed_elem_addr(
                    self.program,
                    frame.local_addr(binding),
                    i.to_int64(),
                    elem_ty,
                  )
                  match
                    mir_body_canonical_aggregate_byte_addr(
                      raw_base, elem_size, addr,
                    ) {
                    Some(value) => return Some(value)
                    None => ()
                  }
                }
              }
              _ => ()
            }
          None => ()
        }
    }
  }
  None
}

///|
fn BodyInterpreter::global_raw_aggregate_byte_addr(
  self : BodyInterpreter,
  addr : Int64,
) -> Int64? {
  for name in self.global_addrs.keys() {
    match self.program.globals.get(name) {
      Some(decl) =>
        match self.program.core_type(decl.ty) {
          Struct(_) | Union(_) =>
            match
              mir_body_canonical_aggregate_byte_addr(
                self.global_addrs[name],
                self.program.type_size(decl.ty).to_int64(),
                addr,
              ) {
              Some(value) => return Some(value)
              None => ()
            }
          _ =>
            match mir_body_array_info(decl.ty) {
              Some((elem_ty, len)) =>
                match self.program.core_type(elem_ty) {
                  Struct(_) | Union(_) => {
                    let elem_size = self.program.type_size(elem_ty).to_int64()
                    for i in 0..<len {
                      let raw_base = mir_body_typed_elem_addr(
                        self.program,
                        self.global_addrs[name],
                        i.to_int64(),
                        elem_ty,
                      )
                      match
                        mir_body_canonical_aggregate_byte_addr(
                          raw_base, elem_size, addr,
                        ) {
                        Some(value) => return Some(value)
                        None => ()
                      }
                    }
                  }
                  _ => ()
                }
              None => ()
            }
        }
      None => ()
    }
  }
  None
}

///|
fn BodyInterpreter::heap_memory_addr(
  self : BodyInterpreter,
  addr : Int64,
) -> Bool {
  for base in self.heap_memory_ranges.keys() {
    let size = self.heap_memory_ranges[base]
    if size > 0L && addr <= base && addr > base - size {
      return true
    }
  }
  false
}

///|
fn BodyInterpreter::alloca_memory_addr(
  self : BodyInterpreter,
  addr : Int64,
) -> Bool {
  for base in self.alloca_memory_ranges.keys() {
    let size = self.alloca_memory_ranges[base]
    if size > 0L && addr <= base && addr > base - size {
      return true
    }
  }
  false
}

///|
fn BodyInterpreter::alloca_offset_aggregate_byte_addr(
  self : BodyInterpreter,
  addr : Int64,
) -> Int64? {
  let raw = addr + 50000L
  if self.alloca_memory_addr(raw) {
    Some(raw)
  } else {
    None
  }
}

///|
fn BodyInterpreter::heap_offset_aggregate_byte_addr(
  self : BodyInterpreter,
  addr : Int64,
) -> Int64? {
  let raw = addr + 50000L
  if self.heap_memory_addr(raw) {
    Some(raw)
  } else {
    None
  }
}

///|
fn BodyInterpreter::canonical_c_memory_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
) -> Int64 {
  match self.local_raw_aggregate_byte_addr(frame, addr) {
    Some(value) => return value
    None => ()
  }
  match self.global_raw_aggregate_byte_addr(addr) {
    Some(value) => return value
    None => ()
  }
  match frame.alloca_offset_aggregate_byte_addr(addr) {
    Some(value) => return value
    None => ()
  }
  match self.alloca_offset_aggregate_byte_addr(addr) {
    Some(value) => return value
    None => ()
  }
  match self.heap_offset_aggregate_byte_addr(addr) {
    Some(value) => value
    None => addr
  }
}

///|
fn BodyInterpreter::known_direct_memory_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
) -> Bool {
  self.frame_memory_addr(frame, addr) ||
  self.global_array_elem_addr(addr) ||
  self.string_array_elem_addr(addr) ||
  self.stack_memory_addr(addr) ||
  self.alloca_memory_addr(addr) ||
  self.heap_memory_addr(addr) ||
  self.global_for_addr(addr) is Some(_)
}

///|
fn BodyInterpreter::known_memory_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
) -> Bool {
  if self.known_direct_memory_addr(frame, addr) {
    return true
  }
  let canonical = self.canonical_c_memory_addr(frame, addr)
  canonical != addr && self.known_direct_memory_addr(frame, canonical)
}

///|
fn BodyInterpreter::offset_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  base : Int64,
  offset : Int,
) -> Int64 {
  let direct = mir_body_offset_addr(base, offset)
  if self.known_memory_addr(frame, direct) {
    direct
  } else {
    let nested = base - offset.to_int64()
    if self.known_memory_addr(frame, nested) {
      nested
    } else {
      direct
    }
  }
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
        let base = mir_body_offset_addr(frame.local_addr(binding), 0)
        let size = self.program.type_size(binding.ty).to_int64()
        if addr <= base && addr > base - size {
          return true
        }
      }
      _ => ()
    }
  }
  for base in frame.aggregate_arg_bases.keys() {
    let size = frame.aggregate_arg_bases[base].to_int64()
    if addr <= base && addr > base - size {
      return true
    }
  }
  false
}

///|
fn BodyFrame::array_elem_addr(self : BodyFrame, addr : Int64) -> Bool {
  for binding in self.bindings.values() {
    match binding.ty {
      Array(_, len) => {
        let base = self.local_addr(binding)
        if addr <= base && addr > base - len.to_int64() {
          return true
        }
      }
      Aligned(inner, _) =>
        match inner {
          Array(_, len) => {
            let base = self.local_addr(binding)
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
fn BodyFrame::alloca_addr(self : BodyFrame, addr : Int64) -> Bool {
  for base in self.alloca_bases.keys() {
    let size = self.alloca_bases[base]
    if size > 0L && addr <= base && addr > base - size {
      return true
    }
  }
  false
}

///|
fn BodyFrame::alloca_offset_aggregate_byte_addr(
  self : BodyFrame,
  addr : Int64,
) -> Int64? {
  let raw = addr + 50000L
  if self.alloca_addr(raw) {
    Some(raw)
  } else {
    None
  }
}

///|
fn mir_body_alloca_size(size : Int64) -> Int64 {
  let bump = (size + 15L) / 16L * 16L
  if bump > 0L {
    bump
  } else {
    16L
  }
}

///|
fn mir_body_alloca_align_bytes(align_bits : Int64) -> Int64 {
  let bytes = align_bits / 8L
  if bytes > 16L {
    bytes
  } else {
    16L
  }
}

///|
fn mir_body_align_up(value : Int64, align : Int64) -> Int64 {
  if align <= 1L {
    value
  } else {
    (value + align - 1L) / align * align
  }
}

///|
fn BodyInterpreter::eval_alloca(
  self : BodyInterpreter,
  frame : BodyFrame,
  size_value : Int64,
  align_bits : Int64,
  ty : @ctype.Type,
) -> Int64 {
  if !(self.program.core_type(ty) is Pointer(_)) {
    self.fail("unsupported MIR body alloca result type")
    return 0L
  }
  let align = mir_body_alloca_align_bytes(align_bits)
  let size = mir_body_alloca_size(size_value)
  let ptr = mir_body_align_up(self.next_alloca + size, align)
  self.next_alloca = ptr
  frame.alloca_bases[ptr] = size
  self.register_stack_memory_range(ptr, size)
  self.alloca_memory_ranges[ptr] = size
  ptr
}

///|
fn BodyInterpreter::eval_heap_alloc(
  self : BodyInterpreter,
  size_value : Int64,
) -> Int64 {
  self.eval_heap_alloc_aligned(size_value, 16L)
}

///|
fn BodyInterpreter::eval_heap_alloc_aligned(
  self : BodyInterpreter,
  size_value : Int64,
  align : Int64,
) -> Int64 {
  let size = mir_body_alloca_size(size_value)
  let ptr = mir_body_align_up(self.next_alloca + size, align)
  self.next_alloca = ptr
  self.register_stack_memory_range(ptr, size)
  self.heap_memory_ranges[ptr] = size
  ptr
}

///|
fn mir_body_valid_posix_memalign_align(align : Int64) -> Bool {
  align >= 8L && (align & (align - 1L)) == 0L
}

///|
fn BodyInterpreter::eval_heap_aligned_alloc(
  self : BodyInterpreter,
  align : Int64,
  size_value : Int64,
) -> Int64 {
  if !mir_body_valid_posix_memalign_align(align) {
    self.fail("unsupported MIR body aligned_alloc alignment")
    return 0L
  }
  self.eval_heap_alloc_aligned(size_value, align)
}

///|
fn BodyInterpreter::eval_heap_valloc(
  self : BodyInterpreter,
  size_value : Int64,
) -> Int64 {
  self.eval_heap_alloc_aligned(size_value, 4096L)
}

///|
fn BodyInterpreter::eval_heap_malloc_size(
  self : BodyInterpreter,
  ptr : Int64,
) -> Int64 {
  if ptr == 0L {
    return 0L
  }
  match self.heap_memory_ranges.get(ptr) {
    Some(size) => size
    None => {
      self.fail("unsupported MIR body malloc_size source")
      0L
    }
  }
}

///|
fn BodyInterpreter::eval_heap_realloc(
  self : BodyInterpreter,
  old_ptr : Int64,
  size_value : Int64,
) -> Int64 {
  if old_ptr == 0L {
    return self.eval_heap_alloc(size_value)
  }
  let old_size = match self.heap_memory_ranges.get(old_ptr) {
    Some(size) => size
    None => {
      self.fail("unsupported MIR body realloc source")
      return 0L
    }
  }
  let new_ptr = self.eval_heap_alloc(size_value)
  let new_size = mir_body_alloca_size(size_value)
  let limit = if old_size < new_size { old_size } else { new_size }
  let mut index = 0L
  while index < limit {
    let old_addr = mir_body_elem_addr(old_ptr, index)
    let new_addr = mir_body_elem_addr(new_ptr, index)
    let byte = match self.stack_memory.get(old_addr) {
      Some(value) => value
      None => 0L
    }
    self.stack_memory[new_addr] = byte
    index += 1L
  }
  self.heap_memory_ranges.remove(old_ptr)
  self.stack_memory_ranges.remove(old_ptr)
  new_ptr
}

///|
fn BodyInterpreter::clear_heap_memory(
  self : BodyInterpreter,
  ptr : Int64,
  size : Int64,
) -> Unit {
  let mut index = 0L
  while index < size {
    self.stack_memory.remove(mir_body_elem_addr(ptr, index))
    index += 1L
  }
}

///|
fn BodyInterpreter::eval_heap_free(self : BodyInterpreter, ptr : Int64) -> Unit {
  if ptr == 0L {
    return
  }
  match self.heap_memory_ranges.get(ptr) {
    Some(size) => {
      self.clear_heap_memory(ptr, size)
      self.heap_memory_ranges.remove(ptr)
      self.stack_memory_ranges.remove(ptr)
    }
    None => self.fail("unsupported MIR body free source")
  }
}

///|
fn BodyInterpreter::eval_heap_strdup(
  self : BodyInterpreter,
  frame : BodyFrame,
  src : Int64,
) -> Int64 {
  match self.c_string_len_for_addr(frame, src) {
    Some(length) => {
      let ptr = self.eval_heap_alloc(length + 1L)
      if !self.copy_c_memory_bytes(frame, ptr, src, length + 1L) {
        self.fail("unsupported MIR body strdup memory")
      }
      ptr
    }
    None => {
      self.fail("unsupported MIR body strdup source")
      0L
    }
  }
}

///|
fn BodyInterpreter::eval_heap_strndup(
  self : BodyInterpreter,
  frame : BodyFrame,
  src : Int64,
  limit : Int64,
) -> Int64 {
  if limit < 0L {
    self.fail("unsupported MIR body strndup length")
    return 0L
  }
  match self.bounded_c_string_len_for_addr(frame, src, limit) {
    Some(length) => {
      let ptr = self.eval_heap_alloc(length + 1L)
      if !self.copy_c_memory_bytes(frame, ptr, src, length) ||
        !self.write_c_memory_byte_for_addr(
          frame,
          mir_body_elem_addr(ptr, length),
          0L,
        ) {
        self.fail("unsupported MIR body strndup memory")
      }
      ptr
    }
    None => {
      self.fail("unsupported MIR body strndup source")
      0L
    }
  }
}

///|
fn BodyInterpreter::eval_heap_posix_memalign(
  self : BodyInterpreter,
  frame : BodyFrame,
  dest_addr : Int64,
  align : Int64,
  size_value : Int64,
) -> Int64 {
  if !mir_body_valid_posix_memalign_align(align) {
    return 22L
  }
  let ptr = self.eval_heap_alloc_aligned(size_value, align)
  ignore(self.write_address(frame, dest_addr, ptr, Pointer(Void)))
  0L
}

///|
fn BodyInterpreter::external_call_frame(
  self : BodyInterpreter,
  frame : BodyFrame?,
  name : String,
) -> BodyFrame? {
  match frame {
    Some(frame) => Some(frame)
    None => {
      self.fail("unsupported MIR body " + name + " caller frame")
      None
    }
  }
}

///|
fn BodyInterpreter::eval_external_memory_string_call(
  self : BodyInterpreter,
  frame : BodyFrame?,
  name : String,
  args : Array[Int64],
) -> Int64? {
  match name {
    "strlen" => {
      if args.length() != 1 {
        self.fail("MIR body strlen argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      match self.c_string_len_for_addr(frame, args[0]) {
        Some(length) => Some(length)
        None => {
          self.fail("unsupported MIR body strlen argument")
          Some(0L)
        }
      }
    }
    "strnlen" => {
      if args.length() != 2 {
        self.fail("MIR body strnlen argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      match self.bounded_c_string_len_for_addr(frame, args[0], args[1]) {
        Some(length) => Some(length)
        None => {
          self.fail("unsupported MIR body strnlen argument")
          Some(0L)
        }
      }
    }
    "strcmp" | "strncmp" | "memcmp" | "bcmp" | "strcasecmp" | "strncasecmp" => {
      let expected_args = if name == "strcmp" || name == "strcasecmp" {
        2
      } else {
        3
      }
      if args.length() != expected_args {
        self.fail("MIR body " + name + " argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      let limit : Int64? = if name == "strcmp" || name == "strcasecmp" {
        None
      } else {
        Some(args[2])
      }
      let result = if name == "strcasecmp" || name == "strncasecmp" {
        self.compare_c_memory_bytes_casefold(frame, args[0], args[1], limit)
      } else {
        self.compare_c_memory_bytes(
          frame,
          args[0],
          args[1],
          limit,
          name != "memcmp" && name != "bcmp",
        )
      }
      match result {
        Some(result) => Some(result)
        None => {
          self.fail("unsupported MIR body " + name + " argument")
          Some(0L)
        }
      }
    }
    "strchr"
    | "strrchr"
    | "strstr"
    | "memchr"
    | "index"
    | "rindex"
    | "strcasestr" => {
      let expected_args = if name == "memchr" { 3 } else { 2 }
      if args.length() != expected_args {
        self.fail("MIR body " + name + " argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      let result = match name {
        "strchr" | "index" =>
          self.find_c_memory_byte(frame, args[0], args[1], None, true)
        "strrchr" | "rindex" =>
          self.find_last_c_string_byte(frame, args[0], args[1])
        "strstr" => self.find_c_string(frame, args[0], args[1])
        "strcasestr" => self.find_c_string_casefold(frame, args[0], args[1])
        "memchr" =>
          self.find_c_memory_byte(frame, args[0], args[1], Some(args[2]), false)
        _ => None
      }
      match result {
        Some(addr) => Some(addr)
        None => {
          self.fail("unsupported MIR body " + name + " argument")
          Some(0L)
        }
      }
    }
    "memmem" => {
      if args.length() != 4 {
        self.fail("MIR body memmem argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      match self.find_c_memory(frame, args[0], args[1], args[2], args[3]) {
        Some(addr) => Some(addr)
        None => {
          self.fail("unsupported MIR body memmem argument")
          Some(0L)
        }
      }
    }
    "strspn" | "strcspn" => {
      if args.length() != 2 {
        self.fail("MIR body " + name + " argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      match
        self.span_c_string_byte_set(frame, args[0], args[1], name == "strspn") {
        Some(length) => Some(length)
        None => {
          self.fail("unsupported MIR body " + name + " argument")
          Some(0L)
        }
      }
    }
    "strpbrk" => {
      if args.length() != 2 {
        self.fail("MIR body strpbrk argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      match self.find_c_string_byte_set(frame, args[0], args[1]) {
        Some(addr) => Some(addr)
        None => {
          self.fail("unsupported MIR body strpbrk argument")
          Some(0L)
        }
      }
    }
    "strsep" => {
      if args.length() != 2 {
        self.fail("MIR body strsep argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      match self.eval_c_string_strsep(frame, args[0], args[1]) {
        Some(addr) => Some(addr)
        None => {
          self.fail("unsupported MIR body strsep argument")
          Some(0L)
        }
      }
    }
    "strtok" => {
      if args.length() != 2 {
        self.fail("MIR body strtok argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      match self.eval_c_string_strtok(frame, args[0], args[1]) {
        Some(addr) => Some(addr)
        None => {
          self.fail("unsupported MIR body strtok argument")
          Some(0L)
        }
      }
    }
    "strtol" | "strtoll" | "strtoul" | "strtoull" | "atoi" | "atol" | "atoll" => {
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      match self.eval_c_string_integer_conversion(frame, name, args) {
        Some(value) => Some(value)
        None => {
          self.fail("unsupported MIR body " + name + " argument")
          Some(0L)
        }
      }
    }
    "memcpy" | "memmove" | "memset" => {
      if args.length() != 3 {
        self.fail("MIR body " + name + " argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      let modeled = if name == "memset" {
        self.set_c_memory_bytes(frame, args[0], args[1], args[2])
      } else {
        self.copy_c_memory_bytes(frame, args[0], args[1], args[2])
      }
      if !modeled {
        self.fail("unsupported MIR body " + name + " memory")
        return Some(0L)
      }
      Some(args[0])
    }
    "bzero" => {
      if args.length() != 2 {
        self.fail("MIR body bzero argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      if !self.set_c_memory_bytes(frame, args[0], 0L, args[1]) {
        self.fail("unsupported MIR body bzero memory")
        return Some(0L)
      }
      Some(0L)
    }
    "bcopy" => {
      if args.length() != 3 {
        self.fail("MIR body bcopy argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      if !self.copy_c_memory_bytes(frame, args[1], args[0], args[2]) {
        self.fail("unsupported MIR body bcopy memory")
        return Some(0L)
      }
      Some(0L)
    }
    "mempcpy" => {
      if args.length() != 3 {
        self.fail("MIR body mempcpy argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      if args[2] < 0L {
        self.fail("unsupported MIR body mempcpy length")
        return Some(0L)
      }
      if !self.copy_c_memory_bytes(frame, args[0], args[1], args[2]) {
        self.fail("unsupported MIR body mempcpy memory")
        return Some(0L)
      }
      Some(mir_body_elem_addr(args[0], args[2]))
    }
    "memccpy" => {
      if args.length() != 4 {
        self.fail("MIR body memccpy argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      if args[3] < 0L {
        self.fail("unsupported MIR body memccpy length")
        return Some(0L)
      }
      let needle = args[2] & 0xFFL
      let mut index = 0L
      while index < args[3] {
        let byte = match
          self.c_memory_byte_for_addr(frame, mir_body_elem_addr(args[1], index)) {
          Some(byte) => byte
          None => {
            self.fail("unsupported MIR body memccpy memory")
            return Some(0L)
          }
        }
        if !self.write_c_memory_byte_for_addr(
            frame,
            mir_body_elem_addr(args[0], index),
            byte,
          ) {
          self.fail("unsupported MIR body memccpy memory")
          return Some(0L)
        }
        if byte == needle {
          return Some(mir_body_elem_addr(args[0], index + 1L))
        }
        index += 1L
      }
      Some(0L)
    }
    "strcpy" | "strcat" => {
      if args.length() != 2 {
        self.fail("MIR body " + name + " argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      let modeled = if name == "strcpy" {
        self.copy_c_string_bytes(frame, args[0], args[1]) is Some(_)
      } else {
        self.append_c_string_bytes(frame, args[0], args[1])
      }
      if !modeled {
        self.fail("unsupported MIR body " + name + " memory")
        return Some(0L)
      }
      Some(args[0])
    }
    "strncpy" | "strncat" => {
      if args.length() != 3 {
        self.fail("MIR body " + name + " argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      let modeled = if name == "strncpy" {
        self.copy_c_string_n_bytes(frame, args[0], args[1], args[2]) is Some(_)
      } else {
        self.append_c_string_n_bytes(frame, args[0], args[1], args[2])
      }
      if !modeled {
        self.fail("unsupported MIR body " + name + " memory")
        return Some(0L)
      }
      Some(args[0])
    }
    "strlcpy" | "strlcat" => {
      if args.length() != 3 {
        self.fail("MIR body " + name + " argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      let length = if name == "strlcpy" {
        self.copy_c_string_l_bytes(frame, args[0], args[1], args[2])
      } else {
        self.append_c_string_l_bytes(frame, args[0], args[1], args[2])
      }
      match length {
        Some(length) => Some(length)
        None => {
          self.fail("unsupported MIR body " + name + " memory")
          Some(0L)
        }
      }
    }
    "stpcpy" => {
      if args.length() != 2 {
        self.fail("MIR body stpcpy argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      match self.copy_c_string_bytes(frame, args[0], args[1]) {
        Some(length) => Some(mir_body_elem_addr(args[0], length))
        None => {
          self.fail("unsupported MIR body stpcpy memory")
          Some(0L)
        }
      }
    }
    "stpncpy" => {
      if args.length() != 3 {
        self.fail("MIR body stpncpy argument count mismatch")
        return Some(0L)
      }
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      match self.copy_c_string_n_bytes(frame, args[0], args[1], args[2]) {
        Some(offset) => Some(mir_body_elem_addr(args[0], offset))
        None => {
          self.fail("unsupported MIR body stpncpy memory")
          Some(0L)
        }
      }
    }
    _ => None
  }
}

///|
fn BodyInterpreter::eval_external_printf_call(
  self : BodyInterpreter,
  frame : BodyFrame?,
  name : String,
  args : Array[Int64],
) -> Int64? {
  match mir_body_external_printf_format_indexes(name, args.length()) {
    Some((format_index, first_value_index)) => {
      let frame = match self.external_call_frame(frame, name) {
        Some(frame) => frame
        None => return Some(0L)
      }
      let values : Array[Int64] = []
      for arg in args {
        values.push(arg)
      }
      let printf_arg_count = match
        self.literal_printf_format_arg_count(values[format_index], name) {
        Some(count) => count
        None => return Some(0L)
      }
      let mut va_list_local_id : Int? = None
      let mut va_list_start = 0
      match mir_body_checked_vprintf_va_list_index(name) {
        Some(va_list_index) =>
          if printf_arg_count > 0 && va_list_index < args.length() {
            let local_id = match
              mir_body_va_list_handle_local_id(args[va_list_index]) {
              Some(local_id) => local_id
              None => {
                self.fail("unsupported MIR body " + name + " va_list")
                return Some(0L)
              }
            }
            match frame.va_list_indices.get(local_id) {
              Some(index) => {
                va_list_local_id = Some(local_id)
                va_list_start = index
                for i in index..<frame.variadic_args.length() {
                  values.push(frame.variadic_args[i])
                }
              }
              None => {
                self.fail("unstarted MIR body " + name + " va_list")
                return Some(0L)
              }
            }
          }
        None => ()
      }
      match
        self.literal_printf_format_length(
          frame,
          values[format_index],
          name,
          values,
          first_value_index,
        ) {
        Some(length) => {
          match
            self.literal_printf_format_output(
              frame,
              values[format_index],
              values,
              first_value_index,
            ) {
            Some(output) => {
              let wrote = match name {
                "snprintf" | "vsnprintf" =>
                  self.write_printf_output(
                    frame,
                    values[0],
                    output,
                    Some(values[1]),
                  )
                "sprintf" | "vsprintf" =>
                  self.write_printf_output(frame, values[0], output, None)
                _ => true
              }
              if !wrote {
                self.fail("unsupported MIR body " + name + " output")
                return Some(0L)
              }
            }
            None => ()
          }
          match va_list_local_id {
            Some(local_id) => {
              if va_list_start + printf_arg_count > frame.variadic_args.length() {
                self.fail("MIR body " + name + " va_list exhausted")
                return Some(0L)
              }
              frame.va_list_indices[local_id] = va_list_start + printf_arg_count
            }
            None => ()
          }
          Some(length)
        }
        None => Some(0L)
      }
    }
    None => None
  }
}

///|
fn BodyInterpreter::eval_external_call(
  self : BodyInterpreter,
  frame : BodyFrame?,
  name : String,
  args : Array[Int64],
) -> Int64? {
  match self.eval_external_memory_string_call(frame, name, args) {
    Some(value) => return Some(value)
    None => ()
  }
  match self.eval_external_printf_call(frame, name, args) {
    Some(value) => return Some(value)
    None => ()
  }
  match name {
    "malloc" =>
      if args.length() == 1 {
        Some(self.eval_heap_alloc(args[0]))
      } else {
        self.fail("MIR body malloc argument count mismatch")
        Some(0L)
      }
    "calloc" =>
      if args.length() == 2 {
        Some(self.eval_heap_alloc(args[0] * args[1]))
      } else {
        self.fail("MIR body calloc argument count mismatch")
        Some(0L)
      }
    "aligned_alloc" =>
      if args.length() == 2 {
        Some(self.eval_heap_aligned_alloc(args[0], args[1]))
      } else {
        self.fail("MIR body aligned_alloc argument count mismatch")
        Some(0L)
      }
    "valloc" =>
      if args.length() == 1 {
        Some(self.eval_heap_valloc(args[0]))
      } else {
        self.fail("MIR body valloc argument count mismatch")
        Some(0L)
      }
    "malloc_size" =>
      if args.length() == 1 {
        Some(self.eval_heap_malloc_size(args[0]))
      } else {
        self.fail("MIR body malloc_size argument count mismatch")
        Some(0L)
      }
    "realloc" =>
      if args.length() == 2 {
        Some(self.eval_heap_realloc(args[0], args[1]))
      } else {
        self.fail("MIR body realloc argument count mismatch")
        Some(0L)
      }
    "free" =>
      if args.length() == 1 {
        self.eval_heap_free(args[0])
        Some(0L)
      } else {
        self.fail("MIR body free argument count mismatch")
        Some(0L)
      }
    "strdup" =>
      if args.length() == 1 {
        match frame {
          Some(frame) => Some(self.eval_heap_strdup(frame, args[0]))
          None => {
            self.fail("unsupported MIR body strdup caller frame")
            Some(0L)
          }
        }
      } else {
        self.fail("MIR body strdup argument count mismatch")
        Some(0L)
      }
    "strndup" =>
      if args.length() == 2 {
        match frame {
          Some(frame) => Some(self.eval_heap_strndup(frame, args[0], args[1]))
          None => {
            self.fail("unsupported MIR body strndup caller frame")
            Some(0L)
          }
        }
      } else {
        self.fail("MIR body strndup argument count mismatch")
        Some(0L)
      }
    "posix_memalign" =>
      if args.length() == 3 {
        match frame {
          Some(frame) =>
            Some(
              self.eval_heap_posix_memalign(frame, args[0], args[1], args[2]),
            )
          None => {
            self.fail("unsupported MIR body posix_memalign caller frame")
            Some(0L)
          }
        }
      } else {
        self.fail("MIR body posix_memalign argument count mismatch")
        Some(0L)
      }
    _ => None
  }
}

///|
fn BodyInterpreter::frame_memory_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
) -> Bool {
  frame.array_elem_addr(addr) ||
  frame.alloca_addr(addr) ||
  self.aggregate_addr(frame, addr)
}

///|
fn BodyInterpreter::read_address(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
  ty : @ctype.Type,
  unsupported : String,
) -> Int64 {
  if !self.bitfield_container_addr(frame, addr) {
    match self.read_c_memory_scalar_for_addr(frame, addr, ty) {
      Some(value) => return value
      None => ()
    }
  }
  match self.read_stack_memory(addr, ty) {
    Some(value) => return value
    None => ()
  }
  if self.frame_memory_addr(frame, addr) {
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
  } else {
    match self.read_stack_addr(addr, ty) {
      Some(value) => value
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
            self.fail(unsupported)
            0L
          }
        }
    }
  }
}

///|
fn BodyInterpreter::write_address(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr : Int64,
  value : Int64,
  ty : @ctype.Type,
) -> Int64 {
  if !self.bitfield_container_addr(frame, addr) {
    match self.write_c_memory_scalar_for_addr(frame, addr, value, ty) {
      Some(assigned) => return assigned
      None => ()
    }
  }
  match self.write_stack_memory(frame, addr, value, ty) {
    Some(assigned) => return assigned
    None => ()
  }
  if self.frame_memory_addr(frame, addr) {
    let assigned = self.program.runtime_cast_int(value, ty)
    frame.memory[addr] = assigned
    assigned
  } else if self.global_array_elem_addr(addr) {
    let assigned = self.program.runtime_cast_int(value, ty)
    self.global_memory[addr] = assigned
    assigned
  } else {
    match self.write_stack_addr(frame, addr, value, ty) {
      Some(assigned) => assigned
      None =>
        match self.global_for_addr(addr) {
          Some(name) => {
            let assigned = self.program.runtime_cast_int(value, ty)
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

///|
fn BodyInterpreter::eval_overflow(
  self : BodyInterpreter,
  frame : BodyFrame,
  op : String,
  left_value : MirValue,
  right_value : MirValue,
  result_ptr : MirValue,
) -> Int64 {
  let result_ty = match self.program.pointer_element(result_ptr.ty()) {
    Some(ty) => ty
    None => {
      self.fail("unsupported MIR body overflow result type")
      return 0L
    }
  }
  let result_addr = self.eval_value(frame, result_ptr)
  let left = self.program.runtime_cast_int(
    self.eval_value(frame, left_value),
    result_ty,
  )
  let right = self.program.runtime_cast_int(
    self.eval_value(frame, right_value),
    result_ty,
  )
  match self.program.overflow_arithmetic_result(result_ty, op, left, right) {
    Some((result, overflow)) => {
      ignore(self.write_address(frame, result_addr, result, result_ty))
      if overflow {
        1L
      } else {
        0L
      }
    }
    None => {
      self.fail("unsupported MIR body overflow result type")
      0L
    }
  }
}

///|
fn BodyInterpreter::eval_truthy(
  self : BodyInterpreter,
  frame : BodyFrame,
  value : MirValue,
) -> Bool {
  self.program.runtime_body_truthy(self.eval_value(frame, value), value.ty())
}

///|
fn BodyInterpreter::eval_binary_values(
  self : BodyInterpreter,
  op : String,
  left : Int64,
  left_ty : @ctype.Type,
  right : Int64,
  right_ty : @ctype.Type,
) -> Int64 {
  match self.eval_pointer_binary_values(op, left, left_ty, right, right_ty) {
    Some(value) => return value
    None => ()
  }
  match self.eval_fp_compare_values(op, left, left_ty, right, right_ty) {
    Some(value) => return value
    None => ()
  }
  match self.eval_fp_arith_values(op, left, left_ty, right, right_ty) {
    Some(value) => return value
    None => ()
  }
  match mir_body_rotate_binary_op(op) {
    Some((width, rotate_left)) =>
      if self.program.core_type(left_ty).is_integer() &&
        self.program.core_type(right_ty).is_integer() {
        return @ctype.rotate_bits(left, right, width, rotate_left)
      }
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
  left_ty : @ctype.Type,
  right : Int64,
  right_ty : @ctype.Type,
) -> Int64? {
  match self.pointer_element_size(left_ty) {
    Some(elem_size) =>
      if right_ty.is_integer() {
        if op == "+" {
          return Some(left - right * elem_size)
        } else if op == "-" {
          return Some(left + right * elem_size)
        }
      } else if op == "-" && self.program.pointer_element(right_ty) is Some(_) {
        return Some((right - left) / elem_size)
      }
    None => ()
  }
  match self.pointer_element_size(right_ty) {
    Some(elem_size) =>
      if op == "+" && left_ty.is_integer() {
        return Some(right - left * elem_size)
      }
    None => ()
  }
  None
}

///|
fn BodyInterpreter::pointer_element_size(
  self : BodyInterpreter,
  ty : @ctype.Type,
) -> Int64? {
  match self.program.pointer_element(ty) {
    Some(elem_ty) => {
      let size = match self.program.core_type(elem_ty) {
        Void => 1
        _ => self.program.type_size(elem_ty)
      }
      if size <= 0 {
        Some(1L)
      } else {
        Some(size.to_int64())
      }
    }
    None => None
  }
}

///|
fn BodyInterpreter::eval_ignored_values(
  self : BodyInterpreter,
  frame : BodyFrame,
  values : Array[MirValue],
) -> Unit {
  for value in values {
    ignore(self.eval_value(frame, value))
  }
}

///|
fn BodyInterpreter::snapshot_aggregate_arg(
  self : BodyInterpreter,
  frame : BodyFrame,
  addr_value : MirValue,
  ty : @ctype.Type,
) -> Int64 {
  let base = self.eval_value(
    frame,
    mir_body_offset_addr_value(addr_value, 0, ty),
  )
  if self.failed() {
    return 0L
  }
  let size = self.program.type_size(ty).to_int64()
  let slots : Map[Int64, Int64] = {}
  for addr in self.stack_memory.keys() {
    if addr <= base && addr > base - size {
      slots[base - addr] = self.stack_memory[addr]
    }
  }
  for addr in frame.memory.keys() {
    if addr <= base && addr > base - size {
      slots[base - addr] = frame.memory[addr]
    }
  }
  for addr in self.global_memory.keys() {
    if addr <= base && addr > base - size {
      slots[base - addr] = self.global_memory[addr]
    }
  }
  match self.heap_offset_aggregate_byte_addr(base) {
    Some(raw_base) => {
      let mut offset = 0L
      while offset < size {
        let raw_addr = mir_body_elem_addr(raw_base, offset)
        match self.stack_memory.get(raw_addr) {
          Some(value) => slots[offset] = value
          None => ()
        }
        offset += 1L
      }
    }
    None => ()
  }
  match frame.alloca_offset_aggregate_byte_addr(base) {
    Some(raw_base) => {
      let mut offset = 0L
      while offset < size {
        let raw_addr = mir_body_elem_addr(raw_base, offset)
        match self.stack_memory.get(raw_addr) {
          Some(value) => slots[offset] = value
          None => ()
        }
        offset += 1L
      }
    }
    None => ()
  }
  match self.alloca_offset_aggregate_byte_addr(base) {
    Some(raw_base) => {
      let mut offset = 0L
      while offset < size {
        let raw_addr = mir_body_elem_addr(raw_base, offset)
        match self.stack_memory.get(raw_addr) {
          Some(value) => slots[offset] = value
          None => ()
        }
        offset += 1L
      }
    }
    None => ()
  }
  let mut byte_offset = 0L
  while byte_offset < size {
    match
      self.c_memory_byte_for_addr(frame, mir_body_elem_addr(base, byte_offset)) {
      Some(byte) => slots[byte_offset] = byte
      None => ()
    }
    byte_offset += 1L
  }
  let handle = self.next_aggregate_arg
  self.next_aggregate_arg += 1L
  self.aggregate_args[handle] = { ty, slots }
  handle
}

///|
fn BodyInterpreter::materialize_aggregate_arg(
  self : BodyInterpreter,
  frame : BodyFrame,
  data : BodyAggregateArgData,
  raw_addr : Int64,
) -> Unit {
  let base = mir_body_offset_addr(raw_addr, 0)
  let size = self.program.type_size(data.ty)
  frame.aggregate_arg_bases[base] = size
  self.register_stack_memory_range(base, size.to_int64())
  for offset in data.slots.keys() {
    let addr = base - offset
    frame.memory[addr] = data.slots[offset]
    self.stack_memory[addr] = data.slots[offset]
  }
}

///|
fn BodyInterpreter::materialize_aggregate_arg_addr(
  self : BodyInterpreter,
  frame : BodyFrame,
  data : BodyAggregateArgData,
  addr_value : MirValue,
) -> Unit {
  let base = self.eval_value(
    frame,
    mir_body_offset_addr_value(addr_value, 0, data.ty),
  )
  if self.failed() {
    return
  }
  let size = self.program.type_size(data.ty)
  let stack_target = self.stack_memory_addr(base) ||
    self.frame_memory_addr(frame, base)
  frame.aggregate_arg_bases[base] = size
  if stack_target {
    self.register_stack_memory_range(base, size.to_int64())
  }
  let raw_stack_base = match self.heap_offset_aggregate_byte_addr(base) {
    Some(raw_base) => Some(raw_base)
    None =>
      match frame.alloca_offset_aggregate_byte_addr(base) {
        Some(raw_base) => Some(raw_base)
        None => self.alloca_offset_aggregate_byte_addr(base)
      }
  }
  for offset in data.slots.keys() {
    let addr = base - offset
    match raw_stack_base {
      Some(raw_base) =>
        self.stack_memory[mir_body_elem_addr(raw_base, offset)] = data.slots[offset]
      None => {
        frame.memory[addr] = data.slots[offset]
        if self.stack_memory_addr(addr) {
          self.stack_memory[addr] = data.slots[offset]
        } else if self.global_array_elem_addr(addr) {
          self.global_memory[addr] = data.slots[offset]
        }
      }
    }
  }
}

///|
fn BodyInterpreter::aggregate_data_for_handle(
  self : BodyInterpreter,
  handle : Int64,
  ty : @ctype.Type,
) -> BodyAggregateArgData? {
  let data = match self.aggregate_args.get(handle) {
    Some(data) => data
    None => {
      self.fail("unknown MIR body aggregate value")
      return None
    }
  }
  if self.program.core_type(data.ty) != self.program.core_type(ty) {
    self.fail("MIR body aggregate value type mismatch")
    return None
  }
  Some(data)
}

///|
fn BodyInterpreter::eval_atomic_updated_value(
  self : BodyInterpreter,
  op : String,
  old : Int64,
  value : Int64,
  elem_ty : @ctype.Type,
  value_ty : @ctype.Type,
) -> Int64 {
  let raw = match op {
    "~&" => self.eval_binary_values("&", old, elem_ty, value, value_ty).lnot()
    "max" | "min" | "umax" | "umin" => {
      let compare_ty = match op {
        "umax" | "umin" => elem_ty.to_unsigned()
        _ => elem_ty
      }
      let compare_op = match op {
        "max" | "umax" => ">="
        _ => "<="
      }
      let keep_old = self.eval_binary_values(
          compare_op, old, compare_ty, value, compare_ty,
        ) !=
        0L
      if keep_old {
        old
      } else {
        value
      }
    }
    _ => self.eval_binary_values(op, old, elem_ty, value, value_ty)
  }
  self.program.runtime_cast_int(raw, elem_ty)
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
      match self.program.core_type(binding.ty) {
        Struct(_) | Union(_) =>
          self.snapshot_aggregate_arg(frame, MirAddrLocal(binding), binding.ty)
        _ => self.read_stack_local(frame, binding, binding.ty)
      }
    MirAddrLocal(binding) => frame.local_addr(binding)
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
    MirLabelAddr(name) =>
      match self.label_addrs.get(name) {
        Some(addr) => addr
        None => {
          self.fail("unknown MIR body label address: " + name)
          0L
        }
      }
    MirStringAddr(value) => self.string_literal_base(value)
    MirElemAddr(base, index, elem_ty) =>
      mir_body_typed_elem_addr_value(
        self.program,
        base,
        self.eval_value(frame, base),
        self.eval_value(frame, index),
        elem_ty,
      )
    MirOffsetAddr(base, offset, _) =>
      self.offset_addr(frame, self.eval_value(frame, base), offset)
    MirLoad(ptr, ty) => {
      let addr = self.eval_value(frame, ptr)
      self.read_address(frame, addr, ty, "unsupported MIR body load address")
    }
    MirUnary(op, inner, ty) => {
      let value = self.eval_value(frame, inner)
      match op {
        "fp_isnan"
        | "fp_isinf"
        | "fp_isfinite"
        | "fp_isnormal"
        | "fp_signbit" =>
          match self.eval_fp_class_value(op, value, inner.ty()) {
            Some(result) => result
            None => {
              self.fail("unsupported MIR body floating classification operand")
              0L
            }
          }
        "alloca" => self.eval_alloca(frame, value, 128L, ty)
        "frame_address" | "return_address" =>
          if self.program.core_type(ty) is Pointer(_) {
            if value == 0L {
              1L
            } else {
              0L
            }
          } else {
            self.fail("unsupported MIR body address query result type")
            0L
          }
        "sync_synchronize" | "atomic_thread_fence" | "atomic_signal_fence" =>
          if self.program.core_type(ty) is Void {
            0L
          } else {
            self.fail("unsupported MIR body fence result type")
            0L
          }
        "trap" => {
          self.fail("MIR body trap")
          0L
        }
        "+" => self.program.runtime_cast_int(value, ty)
        "-" =>
          if self.program.is_floating_type(ty) {
            match self.program.runtime_body_double(value, ty) {
              Some(fp) => (-fp).reinterpret_as_int64()
              None => {
                self.fail("unsupported MIR body floating negation operand")
                0L
              }
            }
          } else {
            self.program.runtime_cast_int(-value, ty)
          }
        "abs32" | "abs64" => {
          let signed = self.program.runtime_cast_int(value, ty)
          self.program.runtime_cast_int(
            if signed < 0L {
              -signed
            } else {
              signed
            },
            ty,
          )
        }
        "fabs" =>
          if self.program.is_floating_type(ty) {
            @ctype.floating_abs(value.reinterpret_as_double()).reinterpret_as_int64()
          } else {
            self.fail("unsupported MIR body fabs result type")
            0L
          }
        "fsqrt" =>
          if self.program.is_floating_type(ty) {
            value.reinterpret_as_double().sqrt().reinterpret_as_int64()
          } else {
            self.fail("unsupported MIR body fsqrt result type")
            0L
          }
        "!" =>
          if self.program.runtime_body_truthy(value, inner.ty()) {
            0L
          } else {
            1L
          }
        "~" => self.program.runtime_cast_int(value.lnot(), ty)
        "clz32" => @ctype.count_leading_zero_bits(value, 32)
        "clz64" => @ctype.count_leading_zero_bits(value, 64)
        "ctz32" => @ctype.count_trailing_zero_bits(value, 32)
        "ctz64" => @ctype.count_trailing_zero_bits(value, 64)
        "ffs32" => @ctype.first_set_bit(value, 32)
        "ffs64" => @ctype.first_set_bit(value, 64)
        "bswap16" => @ctype.byte_swap_bits(value, 16)
        "bswap32" => @ctype.byte_swap_bits(value, 32)
        "bswap64" => @ctype.byte_swap_bits(value, 64)
        "popcount32" => @ctype.count_one_bits(value, 32)
        "popcount64" => @ctype.count_one_bits(value, 64)
        "parity32" => @ctype.count_one_bits(value, 32) & 1L
        "parity64" => @ctype.count_one_bits(value, 64) & 1L
        _ => {
          self.fail("unsupported MIR body unary operator: " + op)
          0L
        }
      }
    }
    MirBinary(op, lhs, rhs, ty) =>
      match op {
        "alloca_align" => {
          let size_value = self.eval_value(frame, lhs)
          let align_bits = self.eval_value(frame, rhs)
          self.eval_alloca(frame, size_value, align_bits, ty)
        }
        "&&" => {
          let left = self.eval_value(frame, lhs)
          if !self.program.runtime_body_truthy(left, lhs.ty()) {
            0L
          } else {
            let right = self.eval_value(frame, rhs)
            if self.program.runtime_body_truthy(right, rhs.ty()) {
              1L
            } else {
              0L
            }
          }
        }
        "||" => {
          let left = self.eval_value(frame, lhs)
          if self.program.runtime_body_truthy(left, lhs.ty()) {
            1L
          } else {
            let right = self.eval_value(frame, rhs)
            if self.program.runtime_body_truthy(right, rhs.ty()) {
              1L
            } else {
              0L
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
      self.program.runtime_cast_body_scalar(
        self.eval_value(frame, inner),
        inner.ty(),
        ty,
      )
    MirAggregateArg(addr, ty) => self.snapshot_aggregate_arg(frame, addr, ty)
    MirVaArg(source, ty) => {
      let binding = match mir_body_va_list_local(source) {
        Some(binding) => binding
        None => {
          self.fail("unsupported MIR body va_arg source")
          return 0L
        }
      }
      let index = match frame.va_list_indices.get(binding.id) {
        Some(index) => index
        None => {
          self.fail("unstarted MIR body va_arg list")
          return 0L
        }
      }
      if index >= frame.variadic_args.length() {
        self.fail("MIR body va_arg exhausted")
        return 0L
      }
      frame.va_list_indices[binding.id] = index + 1
      self.program.runtime_cast_int(frame.variadic_args[index], ty)
    }
    MirVaArgAddr(source, ty) => {
      let binding = match mir_body_va_list_local(source) {
        Some(binding) => binding
        None => {
          self.fail("unsupported MIR body aggregate va_arg source")
          return 0L
        }
      }
      let index = match frame.va_list_indices.get(binding.id) {
        Some(index) => index
        None => {
          self.fail("unstarted MIR body aggregate va_arg list")
          return 0L
        }
      }
      if index >= frame.variadic_args.length() {
        self.fail("MIR body aggregate va_arg exhausted")
        return 0L
      }
      let handle = frame.variadic_args[index]
      let data = match self.aggregate_args.get(handle) {
        Some(data) => data
        None => {
          self.fail("unsupported MIR body aggregate va_arg value")
          return 0L
        }
      }
      if self.program.core_type(data.ty) != self.program.core_type(ty) {
        self.fail("MIR body aggregate va_arg type mismatch")
        return 0L
      }
      frame.va_list_indices[binding.id] = index + 1
      let raw_addr = mir_body_va_arg_aggregate_addr(binding.id, index)
      self.materialize_aggregate_arg(frame, data, raw_addr)
      raw_addr
    }
    MirVaStart(target) => {
      match mir_body_va_list_local(target) {
        Some(binding) => {
          ignore(
            self.write_stack_local(
              frame,
              binding,
              mir_body_va_list_handle(binding.id),
            ),
          )
          frame.va_list_indices[binding.id] = 0
        }
        None => self.fail("unsupported MIR body va_start target")
      }
      0L
    }
    MirVaCopy(target, source) => {
      match (mir_body_va_list_local(target), mir_body_va_list_local(source)) {
        (Some(target_binding), Some(source_binding)) =>
          match frame.va_list_indices.get(source_binding.id) {
            Some(index) => {
              ignore(
                self.write_stack_local(
                  frame,
                  target_binding,
                  mir_body_va_list_handle(target_binding.id),
                ),
              )
              frame.va_list_indices[target_binding.id] = index
            }
            None => self.fail("unstarted MIR body va_copy source")
          }
        _ => self.fail("unsupported MIR body va_copy operand")
      }
      0L
    }
    MirVaEnd(target) => {
      match mir_body_va_list_local(target) {
        Some(binding) => frame.va_list_indices.remove(binding.id)
        None => self.fail("unsupported MIR body va_end target")
      }
      0L
    }
    MirOverflow(op, left, right, result_ptr) =>
      self.eval_overflow(frame, op, left, right, result_ptr)
    MirBzero(dst, size) => {
      let dst_value = self.eval_value(frame, dst)
      let size_value = self.eval_value(frame, size)
      if !self.set_c_memory_bytes(frame, dst_value, 0L, size_value) {
        self.fail("unsupported MIR body bzero memory")
      }
      0L
    }
    MirAtomicLoad(ptr, order, ty) => {
      let result = self.eval_value(frame, MirLoad(ptr, ty))
      ignore(self.eval_value(frame, order))
      result
    }
    MirAtomicStore(ptr, value, order) => {
      ignore(self.eval_value(frame, order))
      self.eval_value(frame, MirStore(ptr, value, ptr.ty().atomic_target()))
    }
    MirAtomicUpdate(op, return_new, ptr, value, extras, ty) => {
      self.eval_ignored_values(frame, extras)
      let elem_ty = ptr.ty().atomic_target()
      let old = self.eval_value(frame, MirLoad(ptr, elem_ty))
      let rhs = self.eval_value(frame, value)
      let updated = self.eval_atomic_updated_value(
        op,
        old,
        rhs,
        elem_ty,
        value.ty(),
      )
      ignore(
        self.eval_value(
          frame,
          MirStore(ptr, MirConst(updated, elem_ty), elem_ty),
        ),
      )
      self.program.runtime_cast_int(if return_new { updated } else { old }, ty)
    }
    MirAtomicExchange(ptr, value, extras, ty) => {
      self.eval_ignored_values(frame, extras)
      let elem_ty = ptr.ty().atomic_target()
      let old = self.eval_value(frame, MirLoad(ptr, elem_ty))
      ignore(self.eval_value(frame, MirStore(ptr, value, elem_ty)))
      self.program.runtime_cast_int(old, ty)
    }
    MirAtomicCompareExchange(ptr, expected, desired, extras) => {
      self.eval_ignored_values(frame, extras)
      let elem_ty = ptr.ty().atomic_target()
      let old = self.eval_value(frame, MirLoad(ptr, elem_ty))
      let expected_value = self.eval_value(frame, MirLoad(expected, elem_ty))
      let desired_value = self.eval_value(frame, desired)
      if self.program.runtime_cast_int(old, elem_ty) ==
        self.program.runtime_cast_int(expected_value, elem_ty) {
        ignore(
          self.eval_value(
            frame,
            MirStore(ptr, MirConst(desired_value, elem_ty), elem_ty),
          ),
        )
        1L
      } else {
        ignore(
          self.eval_value(
            frame,
            MirStore(expected, MirConst(old, elem_ty), elem_ty),
          ),
        )
        0L
      }
    }
    MirLibCall(name, args, ty) => {
      if name == "strlen" && args.length() == 1 && ty.is_integer() {
        let ptr = self.eval_value(frame, args[0])
        match self.c_string_len_for_addr(frame, ptr) {
          Some(length) => return length
          None => {
            self.fail("unsupported MIR body strlen argument")
            return 0L
          }
        }
      }
      if (name == "strcmp" || name == "strncmp" || name == "memcmp") &&
        ty.is_integer() {
        let expected_args = if name == "strcmp" { 2 } else { 3 }
        if args.length() == expected_args {
          let values : Array[Int64] = []
          for arg in args {
            values.push(self.eval_value(frame, arg))
          }
          let limit : Int64? = if name == "strcmp" {
            None
          } else {
            Some(values[2])
          }
          match
            self.compare_c_memory_bytes(
              frame,
              values[0],
              values[1],
              limit,
              name != "memcmp",
            ) {
            Some(result) => return self.program.runtime_cast_int(result, ty)
            None => {
              self.fail("unsupported MIR body " + name + " argument")
              return 0L
            }
          }
        }
      }
      if (
          name == "strchr" ||
          name == "strrchr" ||
          name == "strstr" ||
          name == "memchr"
        ) &&
        mir_body_pointer_type(ty) {
        let expected_args = if name == "memchr" { 3 } else { 2 }
        if args.length() == expected_args {
          let values : Array[Int64] = []
          for arg in args {
            values.push(self.eval_value(frame, arg))
          }
          let result = match name {
            "strchr" =>
              self.find_c_memory_byte(frame, values[0], values[1], None, true)
            "strrchr" =>
              self.find_last_c_string_byte(frame, values[0], values[1])
            "strstr" => self.find_c_string(frame, values[0], values[1])
            "memchr" =>
              self.find_c_memory_byte(
                frame,
                values[0],
                values[1],
                Some(values[2]),
                false,
              )
            _ => None
          }
          match result {
            Some(addr) => return addr
            None => {
              self.fail("unsupported MIR body " + name + " argument")
              return 0L
            }
          }
        }
      }
      if (name == "memcpy" || name == "memmove" || name == "memset") &&
        args.length() == 3 &&
        self.program.core_type(ty) is Pointer(_) {
        let values : Array[Int64] = []
        for arg in args {
          values.push(self.eval_value(frame, arg))
        }
        let modeled = if name == "memset" {
          self.set_c_memory_bytes(frame, values[0], values[1], values[2])
        } else {
          self.copy_c_memory_bytes(frame, values[0], values[1], values[2])
        }
        if !modeled {
          self.fail("unsupported MIR body " + name + " memory")
          return 0L
        }
        return values[0]
      }
      if name == "mempcpy" &&
        args.length() == 3 &&
        self.program.core_type(ty) is Pointer(_) {
        let values : Array[Int64] = []
        for arg in args {
          values.push(self.eval_value(frame, arg))
        }
        if values[2] < 0L {
          self.fail("unsupported MIR body mempcpy length")
          return 0L
        }
        if !self.copy_c_memory_bytes(frame, values[0], values[1], values[2]) {
          self.fail("unsupported MIR body mempcpy memory")
          return 0L
        }
        return mir_body_elem_addr(values[0], values[2])
      }
      if (name == "strcpy" || name == "strcat") &&
        args.length() == 2 &&
        self.program.core_type(ty) is Pointer(_) {
        let values : Array[Int64] = []
        for arg in args {
          values.push(self.eval_value(frame, arg))
        }
        let modeled = if name == "strcpy" {
          self.copy_c_string_bytes(frame, values[0], values[1]) is Some(_)
        } else {
          self.append_c_string_bytes(frame, values[0], values[1])
        }
        if !modeled {
          self.fail("unsupported MIR body " + name + " memory")
          return 0L
        }
        return values[0]
      }
      if (name == "strncpy" || name == "strncat") &&
        args.length() == 3 &&
        self.program.core_type(ty) is Pointer(_) {
        let values : Array[Int64] = []
        for arg in args {
          values.push(self.eval_value(frame, arg))
        }
        let modeled = if name == "strncpy" {
          self.copy_c_string_n_bytes(frame, values[0], values[1], values[2])
          is Some(_)
        } else {
          self.append_c_string_n_bytes(frame, values[0], values[1], values[2])
        }
        if !modeled {
          self.fail("unsupported MIR body " + name + " memory")
          return 0L
        }
        return values[0]
      }
      if (name == "strlcpy" || name == "strlcat") &&
        args.length() == 3 &&
        ty.is_integer() {
        let values : Array[Int64] = []
        for arg in args {
          values.push(self.eval_value(frame, arg))
        }
        let length = if name == "strlcpy" {
          self.copy_c_string_l_bytes(frame, values[0], values[1], values[2])
        } else {
          self.append_c_string_l_bytes(frame, values[0], values[1], values[2])
        }
        match length {
          Some(length) => return length
          None => {
            self.fail("unsupported MIR body " + name + " memory")
            return 0L
          }
        }
      }
      if name == "stpcpy" &&
        args.length() == 2 &&
        self.program.core_type(ty) is Pointer(_) {
        let values : Array[Int64] = []
        for arg in args {
          values.push(self.eval_value(frame, arg))
        }
        match self.copy_c_string_bytes(frame, values[0], values[1]) {
          Some(length) => return mir_body_elem_addr(values[0], length)
          None => {
            self.fail("unsupported MIR body stpcpy memory")
            return 0L
          }
        }
      }
      if name == "stpncpy" &&
        args.length() == 3 &&
        self.program.core_type(ty) is Pointer(_) {
        let values : Array[Int64] = []
        for arg in args {
          values.push(self.eval_value(frame, arg))
        }
        match
          self.copy_c_string_n_bytes(frame, values[0], values[1], values[2]) {
          Some(offset) => return mir_body_elem_addr(values[0], offset)
          None => {
            self.fail("unsupported MIR body stpncpy memory")
            return 0L
          }
        }
      }
      match mir_body_checked_printf_format_indexes(name, args, ty) {
        Some((format_index, first_value_index)) => {
          let values : Array[Int64] = []
          for arg in args {
            values.push(self.eval_value(frame, arg))
          }
          let printf_arg_count = match
            self.literal_printf_format_arg_count(values[format_index], name) {
            Some(count) => count
            None => return 0L
          }
          let mut va_list_binding : MirLocal? = None
          let mut va_list_start = 0
          match mir_body_checked_vprintf_va_list_index(name) {
            Some(va_list_index) =>
              if printf_arg_count > 0 && va_list_index < args.length() {
                match mir_body_va_list_local(args[va_list_index]) {
                  Some(binding) =>
                    match frame.va_list_indices.get(binding.id) {
                      Some(index) => {
                        va_list_binding = Some(binding)
                        va_list_start = index
                        for i in index..<frame.variadic_args.length() {
                          values.push(frame.variadic_args[i])
                        }
                      }
                      None => {
                        self.fail("unstarted MIR body " + name + " va_list")
                        return 0L
                      }
                    }
                  None => {
                    self.fail("unsupported MIR body " + name + " va_list")
                    return 0L
                  }
                }
              }
            None => ()
          }
          match
            self.literal_printf_format_length(
              frame,
              values[format_index],
              name,
              values,
              first_value_index,
            ) {
            Some(length) => {
              match
                self.literal_printf_format_output(
                  frame,
                  values[format_index],
                  values,
                  first_value_index,
                ) {
                Some(output) => {
                  let wrote = match name {
                    "snprintf" | "vsnprintf" =>
                      self.write_printf_output(
                        frame,
                        values[0],
                        output,
                        Some(values[1]),
                      )
                    "sprintf" | "vsprintf" =>
                      self.write_printf_output(frame, values[0], output, None)
                    _ => true
                  }
                  if !wrote {
                    self.fail("unsupported MIR body " + name + " output")
                    return 0L
                  }
                }
                None => ()
              }
              match va_list_binding {
                Some(binding) => {
                  if va_list_start + printf_arg_count >
                    frame.variadic_args.length() {
                    self.fail("MIR body " + name + " va_list exhausted")
                    return 0L
                  }
                  frame.va_list_indices[binding.id] = va_list_start +
                    printf_arg_count
                }
                None => ()
              }
              return length
            }
            None => return 0L
          }
        }
        None => ()
      }
      let values : Array[Int64] = []
      for arg in args {
        values.push(self.eval_value(frame, arg))
      }
      self.program.runtime_cast_int(
        self.call_func(name, values, Some(frame)),
        ty,
      )
    }
    MirCall(name, args, ty) => {
      let values : Array[Int64] = []
      for arg in args {
        values.push(self.eval_value(frame, arg))
      }
      let result = self.call_func(name, values, Some(frame))
      match self.program.core_type(ty) {
        Struct(_) | Union(_) => result
        _ => self.program.runtime_cast_int(result, ty)
      }
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
      let result = self.call_func(name, values, Some(frame))
      match self.program.core_type(ty) {
        Struct(_) | Union(_) => result
        _ => self.program.runtime_cast_int(result, ty)
      }
    }
    MirAssignLocal(binding, rhs) =>
      match self.program.core_type(binding.ty) {
        Struct(_) | Union(_) => {
          let handle = self.eval_value(frame, rhs)
          match self.aggregate_data_for_handle(handle, binding.ty) {
            Some(data) =>
              self.materialize_aggregate_arg(
                frame,
                data,
                frame.local_addr(binding),
              )
            None => ()
          }
          frame.locals[binding.id] = 0L
          handle
        }
        _ => {
          let assigned = self.write_stack_local(
            frame,
            binding,
            self.eval_value(frame, rhs),
          )
          assigned
        }
      }
    MirStore(ptr, rhs, ty) =>
      match self.program.core_type(ty) {
        Struct(_) | Union(_) => {
          let handle = self.eval_value(frame, rhs)
          match self.aggregate_data_for_handle(handle, ty) {
            Some(data) => self.materialize_aggregate_arg_addr(frame, data, ptr)
            None => ()
          }
          handle
        }
        _ => {
          let addr = self.eval_value(frame, ptr)
          let value = self.eval_value(frame, rhs)
          self.write_address(frame, addr, value, ty)
        }
      }
    MirPostUpdateLocal(binding, op, rhs, ty) => {
      let old = self.read_stack_local(frame, binding, binding.ty)
      let right = self.eval_value(frame, rhs)
      let updated = self.program.runtime_cast_int(
        self.eval_binary_values(op, old, binding.ty, right, rhs.ty()),
        binding.ty,
      )
      ignore(self.write_stack_local(frame, binding, updated))
      self.program.runtime_cast_int(old, ty)
    }
    MirPreUpdateMemory(ptr, op, rhs, ty) => {
      let addr = self.eval_value(frame, ptr)
      let old = self.read_address(
        frame, addr, ty, "unsupported MIR body pre-update address",
      )
      let right = self.eval_value(frame, rhs)
      let updated = self.program.runtime_cast_int(
        self.eval_binary_values(op, old, ty, right, rhs.ty()),
        ty,
      )
      ignore(self.write_address(frame, addr, updated, ty))
      updated
    }
    MirPostUpdateMemory(ptr, op, rhs, ty) => {
      let addr = self.eval_value(frame, ptr)
      let old = self.read_address(
        frame, addr, ty, "unsupported MIR body post-update address",
      )
      let right = self.eval_value(frame, rhs)
      let updated = self.program.runtime_cast_int(
        self.eval_binary_values(op, old, ty, right, rhs.ty()),
        ty,
      )
      ignore(self.write_address(frame, addr, updated, ty))
      self.program.runtime_cast_int(old, ty)
    }
    MirTernary(cond, then_, else_, ty) => {
      let selected = if self.eval_truthy(frame, cond) {
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
  match self.exec_stmts_from_supported_label(frame, body, target) {
    (true, BodyBroke) => BodyNormal
    (true, flow) => flow
    (false, _) => {
      self.fail("unknown MIR body switch label: " + target)
      BodyNormal
    }
  }
}

///|
fn BodyInterpreter::exec_stmts_from_index(
  self : BodyInterpreter,
  frame : BodyFrame,
  stmts : Array[MirStmt],
  start : Int,
) -> BodyFlow {
  for i in start..<stmts.length() {
    match self.exec_stmt(frame, stmts[i]) {
      BodyNormal => ()
      flow => return flow
    }
    if self.failed() {
      return BodyNormal
    }
  }
  BodyNormal
}

///|
fn BodyInterpreter::exec_while_after_body_flow(
  self : BodyInterpreter,
  frame : BodyFrame,
  cond : MirValue,
  body : Array[MirStmt],
  first_flow : BodyFlow,
) -> BodyFlow {
  let mut flow = first_flow
  while true {
    match flow {
      BodyNormal | BodyContinued => ()
      BodyBroke => return BodyNormal
      BodyReturned(value) => return BodyReturned(value)
      BodyJump(name) => return BodyJump(name)
    }
    if self.failed() {
      return BodyNormal
    }
    if !self.eval_truthy(frame, cond) || self.failed() {
      return BodyNormal
    }
    flow = self.exec_stmts(frame, body)
  }
  BodyNormal
}

///|
fn BodyInterpreter::exec_for_after_init(
  self : BodyInterpreter,
  frame : BodyFrame,
  cond : MirValue,
  inc : MirValue?,
  body : Array[MirStmt],
) -> BodyFlow {
  while self.eval_truthy(frame, cond) && !self.failed() {
    match self.exec_stmts(frame, body) {
      BodyNormal | BodyContinued => ()
      BodyReturned(value) => return BodyReturned(value)
      BodyBroke => return BodyNormal
      BodyJump(name) => return BodyJump(name)
    }
    match inc {
      Some(value) => ignore(self.eval_value(frame, value))
      None => ()
    }
  }
  BodyNormal
}

///|
fn BodyInterpreter::exec_for_after_init_flow(
  self : BodyInterpreter,
  frame : BodyFrame,
  cond : MirValue,
  inc : MirValue?,
  body : Array[MirStmt],
  first_flow : BodyFlow,
) -> BodyFlow {
  match first_flow {
    BodyNormal | BodyContinued =>
      self.exec_for_after_init(frame, cond, inc, body)
    BodyBroke => BodyNormal
    BodyReturned(value) => BodyReturned(value)
    BodyJump(name) => BodyJump(name)
  }
}

///|
fn BodyInterpreter::exec_for_after_body_flow(
  self : BodyInterpreter,
  frame : BodyFrame,
  cond : MirValue,
  inc : MirValue?,
  body : Array[MirStmt],
  first_flow : BodyFlow,
) -> BodyFlow {
  let mut flow = first_flow
  while true {
    match flow {
      BodyNormal | BodyContinued => ()
      BodyBroke => return BodyNormal
      BodyReturned(value) => return BodyReturned(value)
      BodyJump(name) => return BodyJump(name)
    }
    match inc {
      Some(value) => ignore(self.eval_value(frame, value))
      None => ()
    }
    if self.failed() {
      return BodyNormal
    }
    if !self.eval_truthy(frame, cond) || self.failed() {
      return BodyNormal
    }
    flow = self.exec_stmts(frame, body)
  }
  BodyNormal
}

///|
fn BodyInterpreter::exec_do_while_after_body_flow(
  self : BodyInterpreter,
  frame : BodyFrame,
  cond : MirValue,
  body : Array[MirStmt],
  first_flow : BodyFlow,
) -> BodyFlow {
  let mut flow = first_flow
  while true {
    match flow {
      BodyNormal | BodyContinued => ()
      BodyBroke => return BodyNormal
      BodyReturned(value) => return BodyReturned(value)
      BodyJump(name) => return BodyJump(name)
    }
    if self.failed() {
      return BodyNormal
    }
    if !self.eval_truthy(frame, cond) || self.failed() {
      return BodyNormal
    }
    flow = self.exec_stmts(frame, body)
  }
  BodyNormal
}

///|
fn BodyInterpreter::exec_stmts_from_supported_label(
  self : BodyInterpreter,
  frame : BodyFrame,
  stmts : Array[MirStmt],
  target : String,
) -> (Bool, BodyFlow) {
  for i in 0..<stmts.length() {
    match stmts[i] {
      MirLabel(name) if name == target =>
        return (true, self.exec_stmts_from_index(frame, stmts, i))
      MirIf(_, then_, else_) => {
        match self.exec_stmts_from_supported_label(frame, then_, target) {
          (true, BodyNormal) =>
            return (true, self.exec_stmts_from_index(frame, stmts, i + 1))
          (true, flow) => return (true, flow)
          (false, _) => ()
        }
        match self.exec_stmts_from_supported_label(frame, else_, target) {
          (true, BodyNormal) =>
            return (true, self.exec_stmts_from_index(frame, stmts, i + 1))
          (true, flow) => return (true, flow)
          (false, _) => ()
        }
      }
      MirBlock(nested) =>
        match self.exec_stmts_from_supported_label(frame, nested, target) {
          (true, BodyNormal) =>
            return (true, self.exec_stmts_from_index(frame, stmts, i + 1))
          (true, flow) => return (true, flow)
          (false, _) => ()
        }
      MirWhile(cond, body) =>
        match self.exec_stmts_from_supported_label(frame, body, target) {
          (true, nested_flow) =>
            match
              self.exec_while_after_body_flow(frame, cond, body, nested_flow) {
              BodyNormal =>
                return (true, self.exec_stmts_from_index(frame, stmts, i + 1))
              flow => return (true, flow)
            }
          (false, _) => ()
        }
      MirFor(init, cond, inc, body) => {
        match self.exec_stmts_from_supported_label(frame, init, target) {
          (true, nested_flow) =>
            match
              self.exec_for_after_init_flow(frame, cond, inc, body, nested_flow) {
              BodyNormal =>
                return (true, self.exec_stmts_from_index(frame, stmts, i + 1))
              flow => return (true, flow)
            }
          (false, _) => ()
        }
        match self.exec_stmts_from_supported_label(frame, body, target) {
          (true, nested_flow) =>
            match
              self.exec_for_after_body_flow(frame, cond, inc, body, nested_flow) {
              BodyNormal =>
                return (true, self.exec_stmts_from_index(frame, stmts, i + 1))
              flow => return (true, flow)
            }
          (false, _) => ()
        }
      }
      MirDoWhile(cond, body) =>
        match self.exec_stmts_from_supported_label(frame, body, target) {
          (true, nested_flow) =>
            match
              self.exec_do_while_after_body_flow(frame, cond, body, nested_flow) {
              BodyNormal =>
                return (true, self.exec_stmts_from_index(frame, stmts, i + 1))
              flow => return (true, flow)
            }
          (false, _) => ()
        }
      _ => ()
    }
  }
  (false, BodyNormal)
}

///|
fn BodyInterpreter::exec_stmts_from_label(
  self : BodyInterpreter,
  frame : BodyFrame,
  stmts : Array[MirStmt],
  target : String,
) -> BodyFlow {
  match self.exec_stmts_from_supported_label(frame, stmts, target) {
    (true, flow) => flow
    (false, _) => {
      self.fail("unknown MIR body label: " + target)
      BodyNormal
    }
  }
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
      match self.program.core_type(binding.ty) {
        Struct(_) | Union(_) => {
          frame.locals[binding.id] = 0L
          match init {
            Some(expr) => {
              let handle = self.eval_value(frame, expr)
              match self.aggregate_data_for_handle(handle, binding.ty) {
                Some(data) =>
                  self.materialize_aggregate_arg(
                    frame,
                    data,
                    frame.local_addr(binding),
                  )
                None => ()
              }
            }
            None => ()
          }
        }
        _ => {
          let value = match init {
            Some(expr) => self.eval_value(frame, expr)
            None => 0L
          }
          ignore(self.write_stack_local(frame, binding, value))
        }
      }
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
      if self.eval_truthy(frame, cond) {
        self.exec_stmts(frame, then_)
      } else {
        self.exec_stmts(frame, else_)
      }
    MirWhile(cond, body) => {
      while self.eval_truthy(frame, cond) && !self.failed() {
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
      while self.eval_truthy(frame, cond) && !self.failed() {
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
        keep_running = self.eval_truthy(frame, cond)
      }
      BodyNormal
    }
    MirSwitch(control, cases, body) =>
      self.exec_switch(frame, control, cases, body)
    MirLabel(_) => BodyNormal
    MirGoto(name) => BodyJump(name)
    MirComputedGoto(value) => {
      let addr = self.eval_value(frame, value)
      match self.label_names.get(addr) {
        Some(name) => BodyJump(name)
        None => {
          self.fail("unknown MIR body computed goto target")
          BodyNormal
        }
      }
    }
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
  caller_frame : BodyFrame?,
) -> Int64 {
  if self.failed() {
    return 0L
  }
  if self.call_depth > 256 {
    self.fail("MIR body interpreter call depth exceeded")
    return 0L
  }
  if !self.program.bodies.contains(name) {
    match self.eval_external_call(caller_frame, name, args) {
      Some(value) => return value
      None => {
        self.fail("function has no MIR body: " + name)
        return 0L
      }
    }
  }
  let body = self.program.bodies[name]
  let variadic = match self.program.funcs.get(name) {
    Some(sig) => sig.variadic
    None => false
  }
  if (!variadic && args.length() != body.params.length()) ||
    (variadic && args.length() < body.params.length()) {
    self.fail("MIR body argument count mismatch for " + name)
    return 0L
  }
  self.call_depth += 1
  let bindings : Map[Int, MirLocal] = {}
  for binding in body.locals {
    bindings[binding.id] = binding
  }
  let variadic_args : Array[Int64] = []
  for i in body.params.length()..<args.length() {
    variadic_args.push(args[i])
  }
  let frame = {
    base: self.next_frame_base(),
    locals: {},
    bindings,
    memory: {},
    variadic_args,
    va_list_indices: {},
    aggregate_arg_bases: {},
    alloca_bases: {},
  }
  self.register_frame_memory_ranges(frame)
  for i in 0..<body.params.length() {
    let param = body.params[i]
    match self.program.core_type(param.ty) {
      Struct(_) | Union(_) =>
        match self.aggregate_args.get(args[i]) {
          Some(data) => {
            if self.program.core_type(data.ty) !=
              self.program.core_type(param.ty) {
              self.fail("MIR body aggregate argument type mismatch for " + name)
              return 0L
            }
            self.materialize_aggregate_arg(frame, data, frame.local_addr(param))
            frame.locals[param.id] = 0L
          }
          None => {
            self.fail("missing MIR body aggregate argument for " + name)
            return 0L
          }
        }
      _ => ignore(self.write_stack_local(frame, param, args[i]))
    }
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
        BodyReturned(value) =>
          match self.program.core_type(body.ret) {
            Struct(_) | Union(_) => value
            _ => self.program.runtime_cast_int(value, body.ret)
          }
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
    BodyReturned(value) =>
      match self.program.core_type(body.ret) {
        Struct(_) | Union(_) => value
        _ => self.program.runtime_cast_int(value, body.ret)
      }
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
  let value = interp.call_func(entry, args, None)
  match interp.error {
    Some(message) => Err(message)
    None => Ok(value)
  }
}
