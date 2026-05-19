///|
#warnings("-unused_mut")
priv struct Codegen {
  /// Darwin ARM64 assembly generator for a lowered MIR module.
  output : StringBuilder
  mut mir_module : @mir.MirModule?
  mut label_counter : Int
  mut local_offsets : Map[String, Int]
  mut var_types : Map[String, @ctype.Type]
  mut stack_size : Int
  mut func_name : String
  func_rets : Map[String, @ctype.Type]
  func_variadic : Map[String, Bool]
  func_param_counts : Map[String, Int]
  func_param_types : Map[String, Array[@ctype.Type]]
  struct_layouts : Map[String, Array[(String, @ctype.Type, Int, Int, Int, Int)]]
  strings : Array[String]
  mut break_label : String?
  mut continue_label : String?
  globals : Map[String, CodegenGlobalDecl]
  mut emitted_labels : Map[String, String]
  mut defined_labels : Map[String, Bool]
  mut fp_literals : Array[Double]
  mut sret_dest_offset : Int
  mut sret_scratch_offset : Int
  mut sret_scratch_size : Int
  mut sret_scratch_align : Int
  mut pending_sret_offset : Int
}

///|
fn octal_digit_char(d : Int) -> Char {
  match d {
    0 => '0'
    1 => '1'
    2 => '2'
    3 => '3'
    4 => '4'
    5 => '5'
    6 => '6'
    _ => '7'
  }
}

///|
fn write_octal_escape(buf : StringBuilder, value : Int) -> Unit {
  let byte = value % 256
  buf.write_char('\\')
  buf.write_char(octal_digit_char(byte / 64))
  buf.write_char(octal_digit_char(byte / 8 % 8))
  buf.write_char(octal_digit_char(byte % 8))
}

///|
fn escape_string(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    let value = ch.to_int()
    if value < 0x20 || value >= 0x7f || ch == '\\' || ch == '"' {
      write_octal_escape(buf, value)
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
fn reloc_with_offset(base : String, offset : Int) -> String {
  if offset == 0 {
    base
  } else if offset > 0 {
    base + "+" + offset.to_string()
  } else {
    base + offset.to_string()
  }
}

///|
priv struct CodegenFuncDecl {
  name : String
  is_static : Bool
  is_weak : Bool
  visibility : String?
  symbol_alias : String?
  is_constructor : Bool
  is_destructor : Bool
  has_body : Bool
}

///|
priv struct CodegenGlobalDecl {
  ty : @ctype.Type
  name : String
  has_init : Bool
  is_static : Bool
  is_extern : Bool
  is_weak : Bool
  visibility : String?
  symbol_alias : String?
  section : String?
}

///|
fn codegen_func_decl_from_mir(decl : @mir.MirFuncDecl) -> CodegenFuncDecl {
  {
    name: decl.name,
    is_static: decl.is_static,
    is_weak: decl.is_weak,
    visibility: decl.visibility,
    symbol_alias: decl.symbol_alias,
    is_constructor: decl.is_constructor,
    is_destructor: decl.is_destructor,
    has_body: decl.has_body,
  }
}

///|
fn codegen_func_decls_from_mir(
  decls : Array[@mir.MirFuncDecl],
) -> Array[CodegenFuncDecl] {
  let result : Array[CodegenFuncDecl] = []
  for decl in decls {
    result.push(codegen_func_decl_from_mir(decl))
  }
  result
}

///|
fn mir_codegen_inline_decls(
  decls : Array[@mir.MirFuncDecl],
) -> Map[String, @mir.MirFuncDecl] {
  let inline_decls : Map[String, @mir.MirFuncDecl] = {}
  for decl in decls {
    if decl.is_inline {
      inline_decls[decl.name] = decl
    }
  }
  inline_decls
}

///|
fn mir_codegen_mark_needed_inline(
  name : String,
  inline_decls : Map[String, @mir.MirFuncDecl],
  bodies : Map[String, @mir.MirFuncBody],
  needed : Map[String, Bool],
) -> Unit {
  if needed.contains(name) || !inline_decls.contains(name) {
    return
  }
  needed[name] = true
  match bodies.get(name) {
    Some(body) =>
      mir_codegen_collect_stmt_inline_refs(
        body.body,
        inline_decls,
        bodies,
        needed,
      )
    None => ()
  }
}

///|
fn mir_codegen_collect_value_inline_refs(
  value : @mir.MirValue,
  inline_decls : Map[String, @mir.MirFuncDecl],
  bodies : Map[String, @mir.MirFuncBody],
  needed : Map[String, Bool],
) -> Unit {
  match value {
    MirConst(_, _)
    | MirLocal(_)
    | MirAddrLocal(_)
    | MirAddrGlobal(_, _)
    | MirStringAddr(_) => ()
    MirFuncAddr(name, _) =>
      mir_codegen_mark_needed_inline(name, inline_decls, bodies, needed)
    MirElemAddr(base, index, _) => {
      mir_codegen_collect_value_inline_refs(base, inline_decls, bodies, needed)
      mir_codegen_collect_value_inline_refs(index, inline_decls, bodies, needed)
    }
    MirOffsetAddr(base, _, _)
    | MirLoad(base, _)
    | MirUnary(_, base, _)
    | MirCast(_, base)
    | MirAggregateArg(base, _)
    | MirVaArg(base, _)
    | MirVaArgAddr(base, _) =>
      mir_codegen_collect_value_inline_refs(base, inline_decls, bodies, needed)
    MirBinary(_, left, right, _) => {
      mir_codegen_collect_value_inline_refs(left, inline_decls, bodies, needed)
      mir_codegen_collect_value_inline_refs(right, inline_decls, bodies, needed)
    }
    MirCall(name, args, _) => {
      mir_codegen_mark_needed_inline(name, inline_decls, bodies, needed)
      for arg in args {
        mir_codegen_collect_value_inline_refs(arg, inline_decls, bodies, needed)
      }
    }
    MirIndirectCall(callee, args, _) => {
      mir_codegen_collect_value_inline_refs(
        callee, inline_decls, bodies, needed,
      )
      for arg in args {
        mir_codegen_collect_value_inline_refs(arg, inline_decls, bodies, needed)
      }
    }
    MirAssignLocal(_, rhs) =>
      mir_codegen_collect_value_inline_refs(rhs, inline_decls, bodies, needed)
    MirStore(addr, rhs, _) => {
      mir_codegen_collect_value_inline_refs(addr, inline_decls, bodies, needed)
      mir_codegen_collect_value_inline_refs(rhs, inline_decls, bodies, needed)
    }
    MirPostUpdateLocal(_, _, rhs, _) =>
      mir_codegen_collect_value_inline_refs(rhs, inline_decls, bodies, needed)
    MirPreUpdateMemory(addr, _, rhs, _)
    | MirPostUpdateMemory(addr, _, rhs, _) => {
      mir_codegen_collect_value_inline_refs(addr, inline_decls, bodies, needed)
      mir_codegen_collect_value_inline_refs(rhs, inline_decls, bodies, needed)
    }
    MirTernary(cond, then_, else_, _) => {
      mir_codegen_collect_value_inline_refs(cond, inline_decls, bodies, needed)
      mir_codegen_collect_value_inline_refs(then_, inline_decls, bodies, needed)
      mir_codegen_collect_value_inline_refs(else_, inline_decls, bodies, needed)
    }
  }
}

///|
fn mir_codegen_collect_stmt_inline_refs(
  stmts : Array[@mir.MirStmt],
  inline_decls : Map[String, @mir.MirFuncDecl],
  bodies : Map[String, @mir.MirFuncBody],
  needed : Map[String, Bool],
) -> Unit {
  for stmt in stmts {
    match stmt {
      MirDeclare(_, init) =>
        match init {
          Some(value) =>
            mir_codegen_collect_value_inline_refs(
              value, inline_decls, bodies, needed,
            )
          None => ()
        }
      MirExprStmt(value) | MirReturn(Some(value)) =>
        mir_codegen_collect_value_inline_refs(
          value, inline_decls, bodies, needed,
        )
      MirReturn(None) | MirLabel(_) | MirGoto(_) | MirBreak | MirContinue => ()
      MirIf(cond, then_, else_) => {
        mir_codegen_collect_value_inline_refs(
          cond, inline_decls, bodies, needed,
        )
        mir_codegen_collect_stmt_inline_refs(
          then_, inline_decls, bodies, needed,
        )
        mir_codegen_collect_stmt_inline_refs(
          else_, inline_decls, bodies, needed,
        )
      }
      MirWhile(cond, body) | MirDoWhile(cond, body) => {
        mir_codegen_collect_value_inline_refs(
          cond, inline_decls, bodies, needed,
        )
        mir_codegen_collect_stmt_inline_refs(body, inline_decls, bodies, needed)
      }
      MirFor(init, cond, inc, body) => {
        mir_codegen_collect_stmt_inline_refs(init, inline_decls, bodies, needed)
        mir_codegen_collect_value_inline_refs(
          cond, inline_decls, bodies, needed,
        )
        match inc {
          Some(value) =>
            mir_codegen_collect_value_inline_refs(
              value, inline_decls, bodies, needed,
            )
          None => ()
        }
        mir_codegen_collect_stmt_inline_refs(body, inline_decls, bodies, needed)
      }
      MirSwitch(control, _, body) => {
        mir_codegen_collect_value_inline_refs(
          control, inline_decls, bodies, needed,
        )
        mir_codegen_collect_stmt_inline_refs(body, inline_decls, bodies, needed)
      }
      MirBlock(body) =>
        mir_codegen_collect_stmt_inline_refs(body, inline_decls, bodies, needed)
    }
  }
}

///|
fn mir_codegen_collect_global_init_inline_refs(
  init : @mir.MirGlobalInit,
  inline_decls : Map[String, @mir.MirFuncDecl],
  bodies : Map[String, @mir.MirFuncBody],
  needed : Map[String, Bool],
) -> Unit {
  match init {
    MirGlobalSymbol(name) | MirGlobalSymbolOffset(name, _) =>
      mir_codegen_mark_needed_inline(name, inline_decls, bodies, needed)
    MirGlobalArray(values) =>
      for value in values {
        mir_codegen_collect_global_init_inline_refs(
          value, inline_decls, bodies, needed,
        )
      }
    MirGlobalArraySparse(values) | MirGlobalAggregateSparse(values) =>
      for value in values {
        mir_codegen_collect_global_init_inline_refs(
          value.1,
          inline_decls,
          bodies,
          needed,
        )
      }
    MirGlobalScalarInt(_)
    | MirGlobalScalarFloat(_)
    | MirGlobalString(_)
    | MirGlobalInitUnsupported => ()
  }
}

///|
fn mir_codegen_needed_inline_bodies(
  mir_module : @mir.MirModule,
) -> Map[String, Bool] {
  let inline_decls = mir_codegen_inline_decls(mir_module.decls)
  let needed : Map[String, Bool] = {}
  for decl in mir_module.decls {
    if !decl.is_inline && decl.has_body {
      match mir_module.bodies.get(decl.name) {
        Some(body) =>
          mir_codegen_collect_stmt_inline_refs(
            body.body,
            inline_decls,
            mir_module.bodies,
            needed,
          )
        None => ()
      }
    }
  }
  for global in @mir.merge_global_decls(mir_module.global_decls) {
    match global.init {
      Some(init) =>
        mir_codegen_collect_global_init_inline_refs(
          init,
          inline_decls,
          mir_module.bodies,
          needed,
        )
      None => ()
    }
  }
  needed
}

///|
fn mir_codegen_should_emit_body(
  decl : @mir.MirFuncDecl,
  needed_inline : Map[String, Bool],
) -> Bool {
  decl.has_body && (!decl.is_inline || needed_inline.contains(decl.name))
}

///|
fn codegen_global_decl_from_mir(decl : @mir.MirGlobalDecl) -> CodegenGlobalDecl {
  {
    ty: decl.ty,
    name: decl.name,
    has_init: decl.has_init,
    is_static: decl.is_static,
    is_extern: decl.is_extern,
    is_weak: decl.is_weak,
    visibility: decl.visibility,
    symbol_alias: decl.symbol_alias,
    section: decl.section,
  }
}

///|
fn codegen_global_decls_from_mir(
  decls : Array[@mir.MirGlobalDecl],
) -> Array[CodegenGlobalDecl] {
  let result : Array[CodegenGlobalDecl] = []
  for decl in decls {
    result.push(codegen_global_decl_from_mir(decl))
  }
  result
}

///|
fn codegen_float_asm_literal(value : Double) -> String {
  let text = value.to_string()
  if text.contains(".") ||
    text.contains("e") ||
    text.contains("E") ||
    text.contains("inf") ||
    text.contains("Inf") ||
    text.contains("nan") ||
    text.contains("NaN") {
    text
  } else {
    text + ".0"
  }
}

///|
fn Codegen::emit_global_float(
  self : Codegen,
  ty : @ctype.Type,
  value : Double,
) -> Unit {
  let literal = codegen_float_asm_literal(value)
  match peel_aligned_type(ty) {
    Float => self.emit("\t.single\t" + literal)
    _ => self.emit("\t.double\t" + literal)
  }
}

///|
fn Codegen::new() -> Codegen {
  {
    output: StringBuilder::new(),
    mir_module: None,
    label_counter: 0,
    local_offsets: {},
    var_types: {},
    stack_size: 0,
    func_name: "",
    func_rets: {},
    func_variadic: {},
    func_param_counts: {},
    func_param_types: {},
    struct_layouts: {},
    strings: [],
    break_label: None,
    continue_label: None,
    globals: {},
    emitted_labels: {},
    defined_labels: {},
    fp_literals: [],
    sret_dest_offset: -1,
    sret_scratch_offset: -1,
    sret_scratch_size: 0,
    sret_scratch_align: 1,
    pending_sret_offset: -1,
  }
}

///|
fn Codegen::new_with_mir_module(mir : @mir.MirModule) -> Codegen {
  let codegen = Codegen::new()
  codegen.mir_module = Some(mir)
  codegen
}

///|
fn Codegen::register_mir_function_decls(
  self : Codegen,
  mir : @mir.MirModule,
) -> Unit {
  for decl in mir.decls {
    self.func_rets[decl.name] = decl.ret
    self.func_variadic[decl.name] = decl.variadic
    self.func_param_counts[decl.name] = decl.params.length()
    let param_types = []
    for param in decl.params {
      param_types.push(param.ty)
    }
    self.func_param_types[decl.name] = param_types
  }
}

///|
fn Codegen::register_mir_global_decls(
  self : Codegen,
  mir : @mir.MirModule,
) -> Unit {
  for global in @mir.merge_global_decls(mir.global_decls) {
    self.globals[global.name] = codegen_global_decl_from_mir(global)
  }
}

///|
fn Codegen::mir_global_scalar_int_supported(
  self : Codegen,
  ty : @ctype.Type,
) -> Bool {
  let _ = self
  match peel_aligned_type(ty) {
    Bool
    | SChar
    | UChar
    | SShort
    | UShort
    | SInt
    | UInt
    | SLong
    | ULong
    | SLongLong
    | ULongLong
    | SInt128
    | UInt128
    | Float
    | Double
    | LongDouble
    | Pointer(_)
    | FuncPtr(_, _, _) => true
    _ => false
  }
}

///|
fn Codegen::mir_global_string_supported(
  self : Codegen,
  ty : @ctype.Type,
) -> Bool {
  let _ = self
  match peel_aligned_type(ty) {
    Array(SChar, _) | Array(UChar, _) | Pointer(_) => true
    _ => false
  }
}

///|
fn Codegen::mir_global_symbol_supported(
  self : Codegen,
  ty : @ctype.Type,
) -> Bool {
  let _ = self
  match peel_aligned_type(ty) {
    Pointer(_) | FuncPtr(_, _, _) => true
    _ => false
  }
}

///|
fn Codegen::mir_global_init_supported(
  self : Codegen,
  ty : @ctype.Type,
  init : @mir.MirGlobalInit,
) -> Bool {
  match peel_aligned_type(ty) {
    core =>
      match init {
        MirGlobalInitUnsupported => false
        MirGlobalScalarInt(_) => self.mir_global_scalar_int_supported(core)
        MirGlobalScalarFloat(_) => core.is_floating()
        MirGlobalString(_) => self.mir_global_string_supported(core)
        MirGlobalSymbol(_) => self.mir_global_symbol_supported(core)
        MirGlobalSymbolOffset(_, _) => self.mir_global_symbol_supported(core)
        MirGlobalArraySparse(values) =>
          match core {
            Array(elem_ty, n) => {
              for item in values {
                let index = item.0
                let value = item.1
                if index < 0 || index >= n {
                  return false
                }
                if !self.mir_global_init_supported(elem_ty, value) {
                  return false
                }
              }
              true
            }
            _ => false
          }
        MirGlobalAggregateSparse(values) =>
          match core {
            Struct(name) | Union(name) => {
              let layout = match self.mir_aggregate_layout(name) {
                Some(layout) => layout
                None => return false
              }
              for item in values {
                let index = item.0
                let value = item.1
                if index < 0 || index >= layout.fields.length() {
                  return false
                }
                let field = layout.fields[index]
                match field.bit_width {
                  Some(width) =>
                    if width <= 0 || !(value is MirGlobalScalarInt(_)) {
                      return false
                    }
                  None =>
                    if !self.mir_global_init_supported(field.ty, value) {
                      return false
                    }
                }
              }
              true
            }
            _ => false
          }
        MirGlobalArray(values) =>
          match core {
            Array(elem_ty, n) => {
              if values.length() > n {
                return false
              }
              for value in values {
                if !self.mir_global_init_supported(elem_ty, value) {
                  return false
                }
              }
              true
            }
            Struct(name) | Union(name) => {
              let layout = match self.mir_aggregate_layout(name) {
                Some(layout) => layout
                None => return false
              }
              if layout.is_union {
                if values.length() > 1 {
                  return false
                }
              } else if values.length() > layout.fields.length() {
                return false
              }
              for i = 0; i < values.length(); i = i + 1 {
                if i >= layout.fields.length() {
                  return false
                }
                let field = layout.fields[i]
                match field.bit_width {
                  Some(width) =>
                    if width <= 0 || !(values[i] is MirGlobalScalarInt(_)) {
                      return false
                    }
                  None =>
                    if !self.mir_global_init_supported(field.ty, values[i]) {
                      return false
                    }
                }
              }
              true
            }
            _ => false
          }
      }
  }
}

///|
fn Codegen::mir_aggregate_layout(
  self : Codegen,
  name : String,
) -> @mir.AggregateLayout? {
  match self.mir_module {
    Some(mir) => mir.layouts.get(name)
    None => None
  }
}

///|
fn Codegen::emit_mir_global_scalar_int(
  self : Codegen,
  ty : @ctype.Type,
  value : Int64,
) -> Unit {
  match peel_aligned_type(ty) {
    Bool | SChar | UChar => self.emit("\t.byte\t" + value.to_string())
    SShort | UShort => self.emit("\t.short\t" + value.to_string())
    SInt | UInt => self.emit("\t.long\t" + value.to_string())
    SInt128 => {
      self.emit("\t.quad\t" + value.to_string())
      let high = if value < 0L { "-1" } else { "0" }
      self.emit("\t.quad\t" + high)
    }
    UInt128 => {
      self.emit("\t.quad\t" + value.to_string())
      self.emit("\t.quad\t0")
    }
    Float | Double | LongDouble => self.emit_global_float(ty, value.to_double())
    _ => self.emit("\t.quad\t" + value.to_string())
  }
}

///|
fn Codegen::emit_mir_global_string(
  self : Codegen,
  ty : @ctype.Type,
  value : String,
) -> Unit {
  match peel_aligned_type(ty) {
    Array(SChar, n) | Array(UChar, n) => {
      self.emit("\t.asciz\t\"" + escape_string(value) + "\"")
      let pad = n - value.length() - 1
      if pad > 0 {
        self.emit("\t.space\t" + pad.to_string())
      }
    }
    _ => {
      let idx = self.strings.length()
      self.strings.push(value)
      self.emit("\t.quad\t_str" + idx.to_string())
    }
  }
}

///|
fn Codegen::emit_mir_global_init(
  self : Codegen,
  ty : @ctype.Type,
  init : @mir.MirGlobalInit,
) -> Unit {
  match peel_aligned_type(ty) {
    core =>
      match init {
        MirGlobalScalarInt(value) =>
          self.emit_mir_global_scalar_int(core, value)
        MirGlobalScalarFloat(value) => self.emit_global_float(core, value)
        MirGlobalString(value) => self.emit_mir_global_string(core, value)
        MirGlobalSymbol(name) => self.emit("\t.quad\t_" + name)
        MirGlobalSymbolOffset(name, offset) =>
          self.emit("\t.quad\t" + reloc_with_offset("_" + name, offset))
        MirGlobalArraySparse(values) =>
          match core {
            Array(elem_ty, n) => {
              let elem_size = self.type_size(elem_ty)
              let slots : Array[@mir.MirGlobalInit?] = Array::make(n, None)
              for item in values {
                let index = item.0
                let value = item.1
                if index >= 0 && index < n {
                  slots[index] = Some(value)
                }
              }
              for slot in slots {
                match slot {
                  Some(value) => self.emit_mir_global_init(elem_ty, value)
                  None => self.emit("\t.space\t" + elem_size.to_string())
                }
              }
            }
            _ => self.emit("\t.space\t" + self.type_size(core).to_string())
          }
        MirGlobalAggregateSparse(values) =>
          match core {
            Struct(name) | Union(name) =>
              self.emit_mir_global_sparse_aggregate(name, values)
            _ => self.emit("\t.space\t" + self.type_size(core).to_string())
          }
        MirGlobalArray(values) =>
          match core {
            Array(elem_ty, n) => {
              let elem_size = self.type_size(elem_ty)
              let mut emitted = 0
              for value in values {
                self.emit_mir_global_init(elem_ty, value)
                emitted += 1
              }
              while emitted < n {
                self.emit("\t.space\t" + elem_size.to_string())
                emitted += 1
              }
            }
            Struct(name) | Union(name) =>
              self.emit_mir_global_aggregate(name, values)
            _ => self.emit("\t.space\t" + self.type_size(core).to_string())
          }
        MirGlobalInitUnsupported =>
          self.emit("\t.space\t" + self.type_size(core).to_string())
      }
  }
}

///|
fn Codegen::emit_mir_global_aggregate(
  self : Codegen,
  name : String,
  values : Array[@mir.MirGlobalInit],
) -> Unit {
  let layout = match self.mir_aggregate_layout(name) {
    Some(layout) => layout
    None => {
      self.emit("\t.space\t8")
      return
    }
  }
  let slots : Array[@mir.MirGlobalInit?] = Array::make(
    layout.fields.length(),
    None,
  )
  let count = if layout.is_union && values.length() > 0 {
    1
  } else {
    values.length()
  }
  for i = 0; i < count; i = i + 1 {
    if i < slots.length() {
      slots[i] = Some(values[i])
    }
  }
  self.emit_mir_global_aggregate_slots(layout, slots)
}

///|
fn Codegen::emit_mir_global_sparse_aggregate(
  self : Codegen,
  name : String,
  values : Array[(Int, @mir.MirGlobalInit)],
) -> Unit {
  let layout = match self.mir_aggregate_layout(name) {
    Some(layout) => layout
    None => {
      self.emit("\t.space\t8")
      return
    }
  }
  let slots : Array[@mir.MirGlobalInit?] = Array::make(
    layout.fields.length(),
    None,
  )
  for item in values {
    let index = item.0
    let value = item.1
    if index >= 0 && index < layout.fields.length() {
      slots[index] = Some(value)
      if layout.is_union {
        break
      }
    }
  }
  self.emit_mir_global_aggregate_slots(layout, slots)
}

///|
fn Codegen::mir_global_bitfield_bits(
  self : Codegen,
  init : @mir.MirGlobalInit?,
  bit_width : Int,
  bit_offset : Int,
) -> Int64 {
  let _ = self
  match init {
    Some(MirGlobalScalarInt(value)) =>
      (value & bitfield_mask(bit_width)) << bit_offset
    _ => 0L
  }
}

///|
fn Codegen::emit_mir_global_bitfield_container(
  self : Codegen,
  layout : @mir.AggregateLayout,
  slots : Array[@mir.MirGlobalInit?],
  start : Int,
) -> (Int, Int) {
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
          self.mir_global_bitfield_bits(
            slots[index],
            width,
            bitfield.bit_offset,
          )
      None => ()
    }
    index += 1
  }
  self.emit_global_int_by_size(container_size, container_value)
  (index, container_offset + container_size)
}

///|
fn Codegen::emit_mir_global_aggregate_slots(
  self : Codegen,
  layout : @mir.AggregateLayout,
  slots : Array[@mir.MirGlobalInit?],
) -> Unit {
  let mut emitted = 0
  if layout.is_union {
    for i = 0; i < layout.fields.length(); i = i + 1 {
      match slots[i] {
        Some(value) => {
          let field = layout.fields[i]
          if field.offset > emitted {
            self.emit("\t.space\t" + (field.offset - emitted).to_string())
          }
          match field.bit_width {
            Some(_) => {
              let (_, next_emitted) = self.emit_mir_global_bitfield_container(
                layout, slots, i,
              )
              emitted = next_emitted
            }
            None => {
              self.emit_mir_global_init(field.ty, value)
              emitted = field.offset + field.size
            }
          }
          break
        }
        None => ()
      }
    }
  } else {
    let mut i = 0
    while i < layout.fields.length() {
      let field = layout.fields[i]
      if field.offset > emitted {
        self.emit("\t.space\t" + (field.offset - emitted).to_string())
      }
      match field.bit_width {
        Some(_) => {
          let (next_i, next_emitted) = self.emit_mir_global_bitfield_container(
            layout, slots, i,
          )
          i = next_i
          emitted = next_emitted
          continue
        }
        None => {
          match slots[i] {
            Some(value) => self.emit_mir_global_init(field.ty, value)
            None => self.emit("\t.space\t" + field.size.to_string())
          }
          emitted = field.offset + field.size
        }
      }
      i += 1
    }
  }
  if layout.size > emitted {
    self.emit("\t.space\t" + (layout.size - emitted).to_string())
  }
}

///|
fn Codegen::try_emit_mir_global_init(
  self : Codegen,
  g : @mir.MirGlobalDecl,
) -> Bool {
  match g.init {
    Some(init) =>
      if self.mir_global_init_supported(g.ty, init) {
        self.emit_mir_global_init(g.ty, init)
        true
      } else {
        false
      }
    None => false
  }
}

///|
fn Codegen::emit_global_int_by_size(
  self : Codegen,
  size : Int,
  value : Int64,
) -> Unit {
  match size {
    1 => self.emit("\t.byte\t" + value.to_string())
    2 => self.emit("\t.short\t" + value.to_string())
    4 => self.emit("\t.long\t" + value.to_string())
    _ => self.emit("\t.quad\t" + value.to_string())
  }
}

///|
fn global_align_power(align : Int) -> Int {
  let mut power = 0
  let mut bytes = 1
  while bytes < align {
    bytes = bytes * 2
    power = power + 1
  }
  power
}

///|
fn Codegen::emit_global_p2align(self : Codegen, ty : @ctype.Type) -> Unit {
  let align = self.type_align(ty)
  let effective_align = if align > 8 { align } else { 8 }
  self.emit("\t.p2align\t" + global_align_power(effective_align).to_string())
}

///|
fn Codegen::generate_mir_only(
  self : Codegen,
  mir_module : @mir.MirModule,
) -> String {
  self.output.write_string(
    "\t.section\t__TEXT,__text,regular,pure_instructions\n",
  )
  self.output.write_string("\t.build_version macos, 14, 0\n")
  self.register_mir_aggregate_layouts(mir_module)
  self.register_mir_function_decls(mir_module)
  self.register_mir_global_decls(mir_module)
  let needed_inline = mir_codegen_needed_inline_bodies(mir_module)
  for decl in mir_module.decls {
    if mir_codegen_should_emit_body(decl, needed_inline) {
      match mir_module.bodies.get(decl.name) {
        Some(body) => self.gen_mir_func(decl, body)
        None => ()
      }
    }
  }
  let mir_globals = @mir.merge_global_decls(mir_module.global_decls)
  let mut has_data = false
  for g in mir_globals {
    if g.has_init {
      if !has_data {
        self.emit("\t.section\t__DATA,__data")
        has_data = true
      }
      if !g.is_static {
        if g.is_weak {
          self.emit("\t.weak_definition\t_" + g.name)
        } else {
          self.emit("\t.globl\t_" + g.name)
        }
      }
      self.emit_global_p2align(g.ty)
      self.emit("_" + g.name + ":")
      if !self.try_emit_mir_global_init(g) {
        self.emit("\t.space\t" + self.type_size(g.ty).to_string())
      }
    }
  }
  let mut has_bss = false
  for g in mir_globals {
    if !g.has_init && !g.is_extern {
      if !has_bss {
        self.emit("\t.section\t__DATA,__bss")
        has_bss = true
      }
      if !g.is_static {
        if g.is_weak {
          self.emit("\t.weak_definition\t_" + g.name)
        } else {
          self.emit("\t.globl\t_" + g.name)
        }
      }
      self.emit_global_p2align(g.ty)
      self.emit("_" + g.name + ":")
      self.emit("\t.space\t" + self.type_size(g.ty).to_string())
    }
  }
  if self.strings.length() > 0 {
    self.emit("\t.section\t__TEXT,__const")
    for i = 0; i < self.strings.length(); i = i + 1 {
      self.emit("_str" + i.to_string() + ":")
      self.emit("\t.asciz\t\"" + escape_string(self.strings[i]) + "\"")
    }
  }
  self.output.to_string()
}

///|
/// Generates assembly from a parser-AST-free MIR module, aborting when the
/// current MIR-only backend coverage is insufficient.
pub fn generate_assembly_from_mir_module(mir_module : @mir.MirModule) -> String {
  match generate_assembly_from_mir_module_strict(mir_module) {
    Ok(assembly) => assembly
    Err(err) => abort(err)
  }
}

///|
/// Generates assembly from a parser-AST-free MIR module when the current
/// MIR-only backend coverage is sufficient.
pub fn generate_assembly_from_mir_module_strict(
  mir_module : @mir.MirModule,
) -> Result[String, String] {
  match mir_module_body_codegen_strict_error(mir_module) {
    Some(err) => Err(err)
    None =>
      match mir_module_global_codegen_strict_error(mir_module) {
        Some(err) => Err(err)
        None => Ok(generate_assembly_from_mir_module_unchecked(mir_module))
      }
  }
}

///|
fn generate_assembly_from_mir_module_unchecked(
  mir_module : @mir.MirModule,
) -> String {
  match mir_module.target {
    DarwinArm64 =>
      Codegen::new_with_mir_module(mir_module).generate_mir_only(mir_module)
    LinuxAmd64 =>
      X64Codegen::new_with_mir_module(mir_module).generate_mir_only(mir_module)
  }
}

///|
fn mir_module_global_codegen_strict_error(
  mir_module : @mir.MirModule,
) -> String? {
  match mir_module.target {
    DarwinArm64 => {
      let codegen = Codegen::new_with_mir_module(mir_module)
      for g in @mir.merge_global_decls(mir_module.global_decls) {
        if g.has_init {
          match g.init {
            Some(init) =>
              if !codegen.mir_global_init_supported(g.ty, init) {
                return Some("unsupported MIR global initializer for " + g.name)
              }
            None => return Some("missing MIR global initializer for " + g.name)
          }
        }
      }
    }
    LinuxAmd64 => {
      let codegen = X64Codegen::new_with_mir_module(mir_module)
      for g in @mir.merge_global_decls(mir_module.global_decls) {
        if g.has_init {
          match g.init {
            Some(init) =>
              if !codegen.mir_global_init_supported(g.ty, init) {
                return Some("unsupported MIR global initializer for " + g.name)
              }
            None => return Some("missing MIR global initializer for " + g.name)
          }
        }
      }
    }
  }
  None
}

///|
fn mir_module_body_codegen_strict_error(mir_module : @mir.MirModule) -> String? {
  let int_arg_limit = match mir_module.target {
    DarwinArm64 => 8
    LinuxAmd64 => 6
  }
  let needed_inline = mir_codegen_needed_inline_bodies(mir_module)
  for decl in mir_module.decls {
    if mir_codegen_should_emit_body(decl, needed_inline) {
      if !mir_module.bodies.contains(decl.name) {
        return Some("missing MIR body for " + decl.name)
      }
      let body = mir_module.bodies[decl.name]
      if !mir_body_codegen_func_supported(
          body,
          decl.variadic,
          int_arg_limit,
          mir_module,
        ) {
        return Some("unsupported MIR body codegen for " + decl.name)
      }
    }
  }
  None
}

///|
fn Codegen::emit(self : Codegen, s : String) -> Unit {
  self.output.write_string(s)
  self.output.write_char('\n')
}

///|
fn Codegen::new_label(self : Codegen) -> String {
  let label = "L" + self.label_counter.to_string()
  self.label_counter += 1
  label
}
