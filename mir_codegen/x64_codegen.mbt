///|
#warnings("-unused_mut")
priv struct X64Codegen {
  output : StringBuilder
  mut mir_module : @mir.MirModule?
  mut label_counter : Int
  mut local_offsets : Map[String, Int]
  mut var_types : Map[String, @ctype.Type]
  mut stack_size : Int
  mut stack_align : Int
  mut local_base_reg : String
  mut func_name : String
  func_rets : Map[String, @ctype.Type]
  func_variadic : Map[String, Bool]
  func_param_counts : Map[String, Int]
  func_param_types : Map[String, Array[@ctype.Type]]
  func_defined : Map[String, Bool]
  func_weak : Map[String, Bool]
  struct_layouts : Map[String, Array[(String, @ctype.Type, Int, Int, Int, Int)]]
  globals : Map[String, CodegenGlobalDecl]
  strings : Array[String]
  fp_literals : Array[Double]
  mut va_list_offsets : Map[String, Int]
  mut va_reg_save_offset : Int
  mut va_initial_gp_offset : Int
  mut va_initial_fp_offset : Int
  mut va_initial_overflow_offset : Int
  mut sret_scratch_offset : Int
  mut va_arg_scratch_offset : Int
  mut va_arg_scratch_size : Int
  mut va_arg_scratch_align : Int
  mut break_label : String?
  mut continue_label : String?
  mut emitted_labels : Map[String, String]
  mut defined_labels : Map[String, Bool]
}

///|
fn X64Codegen::new() -> X64Codegen {
  {
    output: StringBuilder::new(),
    mir_module: None,
    label_counter: 0,
    local_offsets: {},
    var_types: {},
    stack_size: 0,
    stack_align: 16,
    local_base_reg: "rbp",
    func_name: "",
    func_rets: {},
    func_variadic: {},
    func_param_counts: {},
    func_param_types: {},
    func_defined: {},
    func_weak: {},
    struct_layouts: {},
    globals: {},
    strings: [],
    fp_literals: [],
    va_list_offsets: {},
    va_reg_save_offset: -1,
    va_initial_gp_offset: 0,
    va_initial_fp_offset: 48,
    va_initial_overflow_offset: 16,
    sret_scratch_offset: -1,
    va_arg_scratch_offset: -1,
    va_arg_scratch_size: 0,
    va_arg_scratch_align: 1,
    break_label: None,
    continue_label: None,
    emitted_labels: {},
    defined_labels: {},
  }
}

///|
fn X64Codegen::new_with_mir_module(mir : @mir.MirModule) -> X64Codegen {
  let codegen = X64Codegen::new()
  codegen.mir_module = Some(mir)
  codegen
}

///|
fn X64Codegen::register_mir_function_decls(
  self : X64Codegen,
  mir : @mir.MirModule,
) -> Unit {
  for decl in mir.decls {
    self.func_rets[decl.name] = decl.ret
    self.func_variadic[decl.name] = decl.variadic
    self.func_param_counts[decl.name] = decl.params.length()
    if decl.has_body || decl.symbol_alias is Some(_) {
      self.func_defined[decl.name] = true
    } else if !self.func_defined.contains(decl.name) {
      self.func_defined[decl.name] = false
    }
    if decl.is_weak {
      self.func_weak[decl.name] = true
    } else if !self.func_weak.contains(decl.name) {
      self.func_weak[decl.name] = false
    }
    let param_types = []
    for param in decl.params {
      param_types.push(param.ty)
    }
    self.func_param_types[decl.name] = param_types
  }
}

///|
fn X64Codegen::register_mir_global_decls(
  self : X64Codegen,
  mir : @mir.MirModule,
) -> Unit {
  for global in @mir.merge_global_decls(mir.global_decls) {
    self.globals[global.name] = codegen_global_decl_from_mir(global)
  }
}

///|
fn X64Codegen::emit(self : X64Codegen, text : String) -> Unit {
  self.output.write_string(text)
  self.output.write_char('\n')
}

///|
fn X64Codegen::new_label(self : X64Codegen) -> String {
  let n = self.label_counter
  self.label_counter += 1
  ".Lx64_" + n.to_string()
}

///|
fn x64_align_to(value : Int, align : Int) -> Int {
  if align <= 1 {
    value
  } else {
    let rem = value % align
    if rem == 0 {
      value
    } else {
      value + align - rem
    }
  }
}

///|
fn x64_core_type(ty : @ctype.Type) -> @ctype.Type {
  match ty {
    Atomic(inner) | Aligned(inner, _) => x64_core_type(inner)
    _ => ty
  }
}

///|
fn x64_is_pointer_like(ty : @ctype.Type) -> Bool {
  match x64_core_type(ty) {
    Pointer(_) | Array(_, _) => true
    _ => false
  }
}

///|
fn x64_pointer_element(ty : @ctype.Type) -> @ctype.Type? {
  match x64_core_type(ty) {
    Pointer(elem) | Array(elem, _) => Some(elem)
    _ => None
  }
}

///|
fn X64Codegen::pointer_element_size(
  self : X64Codegen,
  elem_ty : @ctype.Type,
) -> Int {
  match x64_core_type(elem_ty) {
    Void => 1
    _ => self.type_size(elem_ty)
  }
}

///|
fn x64_is_fp_type(ty : @ctype.Type) -> Bool {
  match x64_core_type(ty) {
    Float | Double => true
    _ => false
  }
}

///|
fn x64_is_int128_type(ty : @ctype.Type) -> Bool {
  match x64_core_type(ty) {
    SInt128 | UInt128 => true
    _ => false
  }
}

///|
fn x64_reject_unsupported_scalar(ty : @ctype.Type) -> Unit {
  match x64_core_type(ty) {
    Float16 => abort("_Float16 ABI lowering is not supported")
    Float128 => abort("__float128 ABI lowering is not supported")
    LongDouble => abort("long double x87 ABI lowering is not supported")
    Pointer(_) | FuncPtr(_, _, _) => ()
    Array(elem, _) | Atomic(elem) | Aligned(elem, _) =>
      x64_reject_unsupported_scalar(elem)
    _ => ()
  }
}

///|
fn x64_is_aggregate_type(ty : @ctype.Type) -> Bool {
  match x64_core_type(ty) {
    Struct(_) | Union(_) => true
    _ => false
  }
}

///|
fn x64_is_object_aggregate_type(ty : @ctype.Type) -> Bool {
  match x64_core_type(ty) {
    Array(_, _) | Struct(_) | Union(_) => true
    _ => false
  }
}

///|
fn x64_atomic_target_type(ty : @ctype.Type) -> @ctype.Type {
  match ty {
    Pointer(Atomic(inner)) | Array(Atomic(inner), _) => inner
    Pointer(Aligned(inner, _)) | Array(Aligned(inner, _), _) => inner
    Pointer(inner) | Array(inner, _) => inner
    Atomic(inner) | Aligned(inner, _) => inner
    _ => SLongLong
  }
}

///|
fn x64_atomic_mem_operand(addr_reg : String, width : Int) -> String {
  match width {
    1 => "BYTE PTR [" + addr_reg + "]"
    2 => "WORD PTR [" + addr_reg + "]"
    4 => "DWORD PTR [" + addr_reg + "]"
    _ => "QWORD PTR [" + addr_reg + "]"
  }
}

///|
fn x64_atomic_rax_reg(width : Int) -> String {
  match width {
    1 => "al"
    2 => "ax"
    4 => "eax"
    _ => "rax"
  }
}

///|
fn x64_atomic_r10_reg(width : Int) -> String {
  match width {
    1 => "r10b"
    2 => "r10w"
    4 => "r10d"
    _ => "r10"
  }
}

///|
fn x64_atomic_r11_reg(width : Int) -> String {
  match width {
    1 => "r11b"
    2 => "r11w"
    4 => "r11d"
    _ => "r11"
  }
}

///|
priv enum X64AggregateClass {
  IntClass
  SseClass
} derive(Eq)

///|
priv struct X64BitfieldInfo {
  ty : @ctype.Type
  size : Int
  bit_offset : Int
  bit_width : Int
}

///|
fn x64_fp_suffix(ty : @ctype.Type) -> String {
  match x64_core_type(ty) {
    Float => "ss"
    _ => "sd"
  }
}

///|
fn x64_fits_i32(value : Int64) -> Bool {
  value >= -2147483648L && value <= 2147483647L
}

///|
fn x64_signed_i32_bits(value : Int64) -> Int64 {
  let bits = value & 0xFFFFFFFFL
  if bits >= 2147483648L {
    bits - 4294967296L
  } else {
    bits
  }
}

///|
fn X64Codegen::type_size(self : X64Codegen, ty : @ctype.Type) -> Int {
  match self.mir_module {
    Some(mir) => return mir.type_size(ty)
    None => ()
  }
  match x64_core_type(ty) {
    Void => 0
    Bool | SChar | UChar => 1
    SShort | UShort | Float16 => 2
    SInt | UInt | Float => 4
    Float128 | LongDouble => 16
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    SInt128 | UInt128 => 16
    Array(elem, n) => self.type_size(elem) * n
    Atomic(inner) | Aligned(inner, _) => self.type_size(inner)
    Struct(name) | Union(name) =>
      match self.mir_aggregate_layout(name) {
        Some(layout) => layout.size
        None => 8
      }
  }
}

///|
fn X64Codegen::type_align(self : X64Codegen, ty : @ctype.Type) -> Int {
  match self.mir_module {
    Some(mir) => return mir.type_align(ty)
    None => ()
  }
  match ty {
    Atomic(inner) => self.type_align(inner)
    Aligned(inner, align) => {
      let inner_align = self.type_align(inner)
      if align > inner_align {
        align
      } else {
        inner_align
      }
    }
    _ =>
      match x64_core_type(ty) {
        Void => 1
        Bool | SChar | UChar => 1
        SShort | UShort | Float16 => 2
        SInt | UInt | Float => 4
        Float128 | LongDouble => 16
        SLong
        | ULong
        | SLongLong
        | ULongLong
        | Double
        | Pointer(_)
        | FuncPtr(_, _, _) => 8
        SInt128 | UInt128 => 16
        Array(elem, _) => self.type_align(elem)
        Struct(name) | Union(name) =>
          match self.mir_aggregate_layout(name) {
            Some(layout) => layout.align
            None => 8
          }
        Atomic(_) | Aligned(_, _) => abort("unreachable x86-64 wrapped type")
      }
  }
}

///|
fn X64Codegen::ensure_struct_layout(self : X64Codegen, name : String) -> Unit {
  if !self.struct_layouts.contains(name) {
    self.struct_layouts[name] = []
  }
}

///|
fn x64_field_layout_tuple(
  layout : @mir.FieldLayout,
) -> (String, @ctype.Type, Int, Int, Int, Int) {
  (
    layout.name,
    layout.ty,
    layout.offset,
    layout.size,
    layout.bit_offset,
    match layout.bit_width {
      Some(width) => width
      None => -1
    },
  )
}

///|
fn X64Codegen::register_mir_aggregate_layouts(
  self : X64Codegen,
  mir : @mir.MirModule,
) -> Unit {
  for decl in mir.aggregate_decls {
    match mir.layouts.get(decl.name) {
      Some(layout) => {
        let fields : Array[(String, @ctype.Type, Int, Int, Int, Int)] = []
        for field in layout.fields {
          fields.push(x64_field_layout_tuple(field))
        }
        self.struct_layouts[decl.name] = fields
      }
      None => ()
    }
  }
}

///|
fn X64Codegen::alloc_local(
  self : X64Codegen,
  name : String,
  ty : @ctype.Type,
) -> Int {
  let size = self.type_size(ty)
  let natural_align = self.type_align(ty)
  let align = if natural_align > 8 { natural_align } else { 8 }
  if align > self.stack_align {
    self.stack_align = align
  }
  self.stack_size = x64_align_to(self.stack_size, align)
  let aligned_size = x64_align_to(size, align)
  self.stack_size += aligned_size
  let offset = self.stack_size
  self.local_offsets[name] = offset
  self.var_types[name] = ty
  offset
}

///|
fn x64_rsp_ref(offset : Int) -> String {
  if offset == 0 {
    "[rsp]"
  } else {
    "[rsp + " + offset.to_string() + "]"
  }
}

///|
fn x64_base_neg_ref(base : String, offset : Int, extra : Int) -> String {
  let total = offset - extra
  if total > 0 {
    "[" + base + " - " + total.to_string() + "]"
  } else if total == 0 {
    "[" + base + "]"
  } else {
    "[" + base + " + " + (-total).to_string() + "]"
  }
}

///|
fn X64Codegen::local_ref(self : X64Codegen, offset : Int) -> String {
  x64_base_neg_ref(self.local_base_reg, offset, 0)
}

///|
fn X64Codegen::local_neg_ref(
  self : X64Codegen,
  offset : Int,
  extra : Int,
) -> String {
  x64_base_neg_ref(self.local_base_reg, offset, extra)
}

///|
fn X64Codegen::emit_local_addr(self : X64Codegen, offset : Int) -> Unit {
  self.emit("\tlea\trax, " + self.local_ref(offset))
}

///|
fn X64Codegen::emit_push_rax(self : X64Codegen) -> Unit {
  self.emit("\tpush\trax")
}

///|
fn X64Codegen::emit_pop_rax(self : X64Codegen) -> Unit {
  self.emit("\tpop\trax")
}

///|
fn X64Codegen::emit_load_indirect(self : X64Codegen, ty : @ctype.Type) -> Unit {
  match x64_core_type(ty) {
    Float => self.emit("\tmovss\txmm0, DWORD PTR [rax]")
    Float16 => abort("_Float16 load is not supported")
    Float128 => abort("__float128 load is not supported")
    LongDouble => abort("long double x87 load is not supported")
    Double => self.emit("\tmovsd\txmm0, QWORD PTR [rax]")
    Bool | UChar => self.emit("\tmovzx\trax, BYTE PTR [rax]")
    SChar => self.emit("\tmovsx\trax, BYTE PTR [rax]")
    UShort => self.emit("\tmovzx\trax, WORD PTR [rax]")
    SShort => self.emit("\tmovsx\trax, WORD PTR [rax]")
    UInt => self.emit("\tmov\teax, DWORD PTR [rax]")
    SInt => self.emit("\tmovsxd\trax, DWORD PTR [rax]")
    SLong | ULong | SLongLong | ULongLong | Pointer(_) | FuncPtr(_, _, _) =>
      self.emit("\tmov\trax, QWORD PTR [rax]")
    SInt128 | UInt128 => {
      self.emit("\tmov\trdx, QWORD PTR [rax + 8]")
      self.emit("\tmov\trax, QWORD PTR [rax]")
    }
    Array(_, _) | Struct(_) | Union(_) => ()
    Void => ()
    Atomic(inner) | Aligned(inner, _) => self.emit_load_indirect(inner)
  }
}

///|
fn X64Codegen::emit_store_indirect(self : X64Codegen, ty : @ctype.Type) -> Unit {
  match x64_core_type(ty) {
    Float => self.emit("\tmovss\tDWORD PTR [r10], xmm0")
    Float16 => abort("_Float16 store is not supported")
    Float128 => abort("__float128 store is not supported")
    LongDouble => abort("long double x87 store is not supported")
    Double => self.emit("\tmovsd\tQWORD PTR [r10], xmm0")
    Bool | SChar | UChar => self.emit("\tmov\tBYTE PTR [r10], al")
    SShort | UShort => self.emit("\tmov\tWORD PTR [r10], ax")
    SInt | UInt => self.emit("\tmov\tDWORD PTR [r10], eax")
    SLong | ULong | SLongLong | ULongLong | Pointer(_) | FuncPtr(_, _, _) =>
      self.emit("\tmov\tQWORD PTR [r10], rax")
    SInt128 | UInt128 => {
      self.emit("\tmov\tQWORD PTR [r10], rax")
      self.emit("\tmov\tQWORD PTR [r10 + 8], rdx")
    }
    Array(_, _) | Struct(_) | Union(_) | Void => ()
    Atomic(inner) | Aligned(inner, _) => self.emit_store_indirect(inner)
  }
}

///|
fn X64Codegen::emit_store_local_from_rax(
  self : X64Codegen,
  offset : Int,
  ty : @ctype.Type,
) -> Unit {
  match x64_core_type(ty) {
    Float =>
      self.emit("\tmovss\tDWORD PTR " + self.local_ref(offset) + ", xmm0")
    Double =>
      self.emit("\tmovsd\tQWORD PTR " + self.local_ref(offset) + ", xmm0")
    Bool | SChar | UChar =>
      self.emit("\tmov\tBYTE PTR " + self.local_ref(offset) + ", al")
    SShort | UShort =>
      self.emit("\tmov\tWORD PTR " + self.local_ref(offset) + ", ax")
    SInt | UInt =>
      self.emit("\tmov\tDWORD PTR " + self.local_ref(offset) + ", eax")
    SInt128 | UInt128 => {
      self.emit("\tmov\tQWORD PTR " + self.local_ref(offset) + ", rax")
      self.emit("\tmov\tQWORD PTR " + self.local_neg_ref(offset, 8) + ", rdx")
    }
    _ => self.emit("\tmov\tQWORD PTR " + self.local_ref(offset) + ", rax")
  }
}

///|
fn X64Codegen::emit_store_int_reg_to_local(
  self : X64Codegen,
  reg : String,
  offset : Int,
) -> Unit {
  self.emit("\tmov\tQWORD PTR " + self.local_ref(offset) + ", " + reg)
}

///|
fn X64Codegen::emit_store_fp_reg_to_local(
  self : X64Codegen,
  reg : String,
  offset : Int,
  ty : @ctype.Type,
) -> Unit {
  match x64_core_type(ty) {
    Float =>
      self.emit("\tmovss\tDWORD PTR " + self.local_ref(offset) + ", " + reg)
    _ => self.emit("\tmovsd\tQWORD PTR " + self.local_ref(offset) + ", " + reg)
  }
}

///|
fn x64_merge_aggregate_class(
  a : X64AggregateClass,
  b : X64AggregateClass,
) -> X64AggregateClass {
  if a == IntClass || b == IntClass {
    IntClass
  } else {
    SseClass
  }
}

///|
fn x64_scalar_aggregate_class(ty : @ctype.Type) -> X64AggregateClass? {
  match x64_core_type(ty) {
    Float | Double => Some(SseClass)
    Float128 | LongDouble | Void | Array(_, _) | Struct(_) | Union(_) => None
    _ => Some(IntClass)
  }
}

///|
fn x64_mark_aggregate_class_range(
  classes : Array[X64AggregateClass],
  offset : Int,
  size : Int,
  class_ : X64AggregateClass,
) -> Bool {
  if size <= 0 {
    return true
  }
  let start_word = offset / 8
  let end_word = (offset + size - 1) / 8
  if start_word < 0 || end_word >= classes.length() {
    return false
  }
  for word in start_word..<=end_word {
    classes[word] = x64_merge_aggregate_class(classes[word], class_)
  }
  true
}

///|
fn X64Codegen::classify_aggregate_field(
  self : X64Codegen,
  ty : @ctype.Type,
  offset : Int,
  classes : Array[X64AggregateClass],
) -> Bool {
  match x64_core_type(ty) {
    Array(elem, n) => {
      let elem_size = self.type_size(elem)
      for i in 0..<n {
        if !self.classify_aggregate_field(elem, offset + i * elem_size, classes) {
          return false
        }
      }
      true
    }
    Struct(name) | Union(name) => {
      self.ensure_struct_layout(name)
      for field in self.struct_layouts[name] {
        let field_size = self.type_size(field.1)
        if field_size <= 0 {
          continue
        }
        if field.5 >= 0 {
          if !x64_mark_aggregate_class_range(
              classes,
              offset + field.2,
              field_size,
              IntClass,
            ) {
            return false
          }
        } else if !self.classify_aggregate_field(
            field.1,
            offset + field.2,
            classes,
          ) {
          return false
        }
      }
      true
    }
    Atomic(inner) | Aligned(inner, _) =>
      self.classify_aggregate_field(inner, offset, classes)
    _ =>
      match x64_scalar_aggregate_class(ty) {
        Some(class_) =>
          x64_mark_aggregate_class_range(
            classes,
            offset,
            self.type_size(ty),
            class_,
          )
        None => false
      }
  }
}

///|
fn X64Codegen::aggregate_has_unaligned_field(
  self : X64Codegen,
  ty : @ctype.Type,
  offset : Int,
) -> Bool {
  match ty {
    Atomic(inner) => self.aggregate_has_unaligned_field(inner, offset)
    Aligned(inner, align) =>
      if align > 1 && offset % align != 0 {
        true
      } else {
        self.aggregate_has_unaligned_field(inner, offset)
      }
    _ =>
      match x64_core_type(ty) {
        Array(elem, n) => {
          let elem_size = self.type_size(elem)
          for i in 0..<n {
            if self.aggregate_has_unaligned_field(elem, offset + i * elem_size) {
              return true
            }
          }
          false
        }
        Struct(name) | Union(name) => {
          self.ensure_struct_layout(name)
          for field in self.struct_layouts[name] {
            let field_offset = offset + field.2
            if field.5 >= 0 {
              let align = self.type_align(field.1)
              if align > 1 && field_offset % align != 0 {
                return true
              }
            } else if self.aggregate_has_unaligned_field(field.1, field_offset) {
              return true
            }
          }
          false
        }
        _ => {
          let align = self.type_align(ty)
          align > 1 && offset % align != 0
        }
      }
  }
}

///|
fn X64Codegen::aggregate_classes(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Array[X64AggregateClass]? {
  if !x64_is_aggregate_type(ty) {
    return None
  }
  let size = self.type_size(ty)
  if size <= 0 || size > 16 {
    return None
  }
  if self.aggregate_has_unaligned_field(ty, 0) {
    return None
  }
  let words = self.aggregate_word_count(ty)
  let classes : Array[X64AggregateClass] = []
  for _ in 0..<words {
    classes.push(SseClass)
  }
  if !self.classify_aggregate_field(ty, 0, classes) {
    return None
  }
  Some(classes)
}

///|
fn x64_class_count(
  classes : Array[X64AggregateClass],
  expected : X64AggregateClass,
) -> Int {
  let mut count = 0
  for class_ in classes {
    if class_ == expected {
      count += 1
    }
  }
  count
}

///|
fn X64Codegen::is_supported_small_aggregate(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Bool {
  self.aggregate_classes(ty) is Some(_)
}

///|
fn X64Codegen::is_memory_aggregate(self : X64Codegen, ty : @ctype.Type) -> Bool {
  x64_is_aggregate_type(ty) && self.aggregate_classes(ty) is None
}

///|
fn X64Codegen::aggregate_word_count(self : X64Codegen, ty : @ctype.Type) -> Int {
  x64_align_to(self.type_size(ty), 8) / 8
}

///|
fn X64Codegen::stack_arg_align_slots(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Int {
  let align = self.type_align(ty)
  if x64_is_int128_type(ty) || align > 8 {
    x64_align_to(align, 8) / 8
  } else {
    1
  }
}

///|
fn X64Codegen::align_call_stack_arg(
  self : X64Codegen,
  index : Int,
  call_align : Int,
  ty : @ctype.Type,
) -> (Int, Int) {
  let align_slots = self.stack_arg_align_slots(ty)
  let aligned_index = x64_align_to(index, align_slots)
  let stack_align = align_slots * 8
  let aligned_call = if stack_align > call_align {
    stack_align
  } else {
    call_align
  }
  (aligned_index, aligned_call)
}

///|
fn x64_mem_at_reg(reg : String, offset : Int) -> String {
  if offset == 0 {
    "[" + reg + "]"
  } else {
    "[" + reg + " + " + offset.to_string() + "]"
  }
}

///|
fn x64_sized_mem_at_reg(reg : String, offset : Int, width : Int) -> String {
  x64_sized_mem_ref(x64_mem_at_reg(reg, offset), width)
}

///|
fn x64_sized_mem_ref(mem : String, width : Int) -> String {
  let prefix = match width {
    1 => "BYTE PTR "
    2 => "WORD PTR "
    4 => "DWORD PTR "
    _ => "QWORD PTR "
  }
  prefix + mem
}

///|
fn x64_sized_reg(width : Int) -> String {
  match width {
    1 => "al"
    2 => "ax"
    4 => "eax"
    _ => "rax"
  }
}

///|
fn x64_reg8(reg : String) -> String {
  match reg {
    "rax" => "al"
    "rbx" => "bl"
    "rcx" => "cl"
    "rdx" => "dl"
    "rdi" => "dil"
    "rsi" => "sil"
    "r8" => "r8b"
    "r9" => "r9b"
    "r10" => "r10b"
    "r11" => "r11b"
    _ => reg
  }
}

///|
fn x64_reg16(reg : String) -> String {
  match reg {
    "rax" => "ax"
    "rbx" => "bx"
    "rcx" => "cx"
    "rdx" => "dx"
    "rdi" => "di"
    "rsi" => "si"
    "r8" => "r8w"
    "r9" => "r9w"
    "r10" => "r10w"
    "r11" => "r11w"
    _ => reg
  }
}

///|
fn x64_reg32(reg : String) -> String {
  match reg {
    "rax" => "eax"
    "rbx" => "ebx"
    "rcx" => "ecx"
    "rdx" => "edx"
    "rdi" => "edi"
    "rsi" => "esi"
    "r8" => "r8d"
    "r9" => "r9d"
    "r10" => "r10d"
    "r11" => "r11d"
    _ => reg
  }
}

///|
fn X64Codegen::aggregate_word_width(
  self : X64Codegen,
  ty : @ctype.Type,
  word : Int,
) -> Int {
  let remaining = self.type_size(ty) - word * 8
  if remaining >= 8 {
    8
  } else if remaining > 0 {
    remaining
  } else {
    0
  }
}

///|
fn X64Codegen::emit_load_int_bytes_from_mem_reg(
  self : X64Codegen,
  dst_reg : String,
  base_reg : String,
  offset : Int,
  width : Int,
) -> Unit {
  match width {
    1 =>
      self.emit(
        "\tmovzx\t" +
        x64_reg32(dst_reg) +
        ", " +
        x64_sized_mem_at_reg(base_reg, offset, 1),
      )
    2 =>
      self.emit(
        "\tmovzx\t" +
        x64_reg32(dst_reg) +
        ", " +
        x64_sized_mem_at_reg(base_reg, offset, 2),
      )
    3 => {
      self.emit(
        "\tmovzx\t" +
        x64_reg32(dst_reg) +
        ", " +
        x64_sized_mem_at_reg(base_reg, offset, 2),
      )
      self.emit(
        "\tmovzx\tr11d, " + x64_sized_mem_at_reg(base_reg, offset + 2, 1),
      )
      self.emit("\tshl\tr11, 16")
      self.emit("\tor\t" + dst_reg + ", r11")
    }
    4 =>
      self.emit(
        "\tmov\t" +
        x64_reg32(dst_reg) +
        ", " +
        x64_sized_mem_at_reg(base_reg, offset, 4),
      )
    5 | 6 | 7 => {
      self.emit(
        "\tmov\t" +
        x64_reg32(dst_reg) +
        ", " +
        x64_sized_mem_at_reg(base_reg, offset, 4),
      )
      if width == 5 {
        self.emit(
          "\tmovzx\tr11d, " + x64_sized_mem_at_reg(base_reg, offset + 4, 1),
        )
        self.emit("\tshl\tr11, 32")
        self.emit("\tor\t" + dst_reg + ", r11")
      } else {
        self.emit(
          "\tmovzx\tr11d, " + x64_sized_mem_at_reg(base_reg, offset + 4, 2),
        )
        self.emit("\tshl\tr11, 32")
        self.emit("\tor\t" + dst_reg + ", r11")
        if width == 7 {
          self.emit(
            "\tmovzx\tr11d, " + x64_sized_mem_at_reg(base_reg, offset + 6, 1),
          )
          self.emit("\tshl\tr11, 48")
          self.emit("\tor\t" + dst_reg + ", r11")
        }
      }
    }
    8 =>
      self.emit(
        "\tmov\t" + dst_reg + ", " + x64_sized_mem_at_reg(base_reg, offset, 8),
      )
    _ => ()
  }
}

///|
fn X64Codegen::emit_store_int_bytes_to_mem_reg(
  self : X64Codegen,
  src_reg : String,
  base_reg : String,
  offset : Int,
  width : Int,
) -> Unit {
  self.emit_store_int_bytes_to_mem_refs(
    src_reg,
    x64_mem_at_reg(base_reg, offset),
    x64_mem_at_reg(base_reg, offset + 2),
    x64_mem_at_reg(base_reg, offset + 4),
    x64_mem_at_reg(base_reg, offset + 6),
    width,
  )
}

///|
fn X64Codegen::emit_store_int_bytes_to_mem_refs(
  self : X64Codegen,
  src_reg : String,
  mem0 : String,
  mem2 : String,
  mem4 : String,
  mem6 : String,
  width : Int,
) -> Unit {
  match width {
    1 =>
      self.emit(
        "\tmov\t" + x64_sized_mem_ref(mem0, 1) + ", " + x64_reg8(src_reg),
      )
    2 =>
      self.emit(
        "\tmov\t" + x64_sized_mem_ref(mem0, 2) + ", " + x64_reg16(src_reg),
      )
    3 => {
      self.emit(
        "\tmov\t" + x64_sized_mem_ref(mem0, 2) + ", " + x64_reg16(src_reg),
      )
      self.emit("\tmov\tr11, " + src_reg)
      self.emit("\tshr\tr11, 16")
      self.emit("\tmov\t" + x64_sized_mem_ref(mem2, 1) + ", r11b")
    }
    4 =>
      self.emit(
        "\tmov\t" + x64_sized_mem_ref(mem0, 4) + ", " + x64_reg32(src_reg),
      )
    5 | 6 | 7 => {
      self.emit(
        "\tmov\t" + x64_sized_mem_ref(mem0, 4) + ", " + x64_reg32(src_reg),
      )
      self.emit("\tmov\tr11, " + src_reg)
      self.emit("\tshr\tr11, 32")
      if width == 5 {
        self.emit("\tmov\t" + x64_sized_mem_ref(mem4, 1) + ", r11b")
      } else {
        self.emit("\tmov\t" + x64_sized_mem_ref(mem4, 2) + ", r11w")
        if width == 7 {
          self.emit("\tshr\tr11, 16")
          self.emit("\tmov\t" + x64_sized_mem_ref(mem6, 1) + ", r11b")
        }
      }
    }
    8 => self.emit("\tmov\t" + x64_sized_mem_ref(mem0, 8) + ", " + src_reg)
    _ => ()
  }
}

///|
fn X64Codegen::emit_load_sse_word_from_mem_reg(
  self : X64Codegen,
  dst_reg : String,
  base_reg : String,
  offset : Int,
  width : Int,
) -> Unit {
  if width <= 4 {
    self.emit(
      "\tmovss\t" + dst_reg + ", " + x64_sized_mem_at_reg(base_reg, offset, 4),
    )
  } else {
    self.emit(
      "\tmovsd\t" + dst_reg + ", " + x64_sized_mem_at_reg(base_reg, offset, 8),
    )
  }
}

///|
fn X64Codegen::emit_store_sse_word_to_mem_reg(
  self : X64Codegen,
  src_reg : String,
  base_reg : String,
  offset : Int,
  width : Int,
) -> Unit {
  if width <= 4 {
    self.emit(
      "\tmovss\t" + x64_sized_mem_at_reg(base_reg, offset, 4) + ", " + src_reg,
    )
  } else {
    self.emit(
      "\tmovsd\t" + x64_sized_mem_at_reg(base_reg, offset, 8) + ", " + src_reg,
    )
  }
}

///|
fn X64Codegen::emit_store_small_aggregate_return(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Unit {
  let classes = match self.aggregate_classes(ty) {
    Some(classes) => classes
    None => abort("x86-64 backend does not support this aggregate return yet")
  }
  let int_regs = ["rax", "rdx"]
  let fp_regs = ["xmm0", "xmm1"]
  let mut int_idx = 0
  let mut fp_idx = 0
  for word in 0..<classes.length() {
    let width = self.aggregate_word_width(ty, word)
    match classes[word] {
      IntClass => {
        self.emit_store_int_bytes_to_mem_reg(
          int_regs[int_idx],
          "r10",
          word * 8,
          width,
        )
        int_idx += 1
      }
      SseClass => {
        self.emit_store_sse_word_to_mem_reg(
          fp_regs[fp_idx],
          "r10",
          word * 8,
          width,
        )
        fp_idx += 1
      }
    }
  }
}

///|
fn X64Codegen::emit_copy_aggregate_from_addr(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Unit {
  let mut offset = 0
  let mut remaining = self.type_size(ty)
  while remaining >= 8 {
    let reg = x64_sized_reg(8)
    self.emit("\tmov\t" + reg + ", " + x64_sized_mem_at_reg("r11", offset, 8))
    self.emit("\tmov\t" + x64_sized_mem_at_reg("r10", offset, 8) + ", " + reg)
    offset += 8
    remaining -= 8
  }
  if remaining >= 4 {
    let reg = x64_sized_reg(4)
    self.emit("\tmov\t" + reg + ", " + x64_sized_mem_at_reg("r11", offset, 4))
    self.emit("\tmov\t" + x64_sized_mem_at_reg("r10", offset, 4) + ", " + reg)
    offset += 4
    remaining -= 4
  }
  if remaining >= 2 {
    let reg = x64_sized_reg(2)
    self.emit("\tmov\t" + reg + ", " + x64_sized_mem_at_reg("r11", offset, 2))
    self.emit("\tmov\t" + x64_sized_mem_at_reg("r10", offset, 2) + ", " + reg)
    offset += 2
    remaining -= 2
  }
  if remaining > 0 {
    let reg = x64_sized_reg(1)
    self.emit("\tmov\t" + reg + ", " + x64_sized_mem_at_reg("r11", offset, 1))
    self.emit("\tmov\t" + x64_sized_mem_at_reg("r10", offset, 1) + ", " + reg)
  }
}

///|
fn X64Codegen::emit_zero_memory_at_rax(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Unit {
  let mut offset = 0
  let mut remaining = self.type_size(ty)
  while remaining >= 8 {
    self.emit("\tmov\t" + x64_sized_mem_at_reg("rax", offset, 8) + ", 0")
    offset += 8
    remaining -= 8
  }
  if remaining >= 4 {
    self.emit("\tmov\t" + x64_sized_mem_at_reg("rax", offset, 4) + ", 0")
    offset += 4
    remaining -= 4
  }
  if remaining >= 2 {
    self.emit("\tmov\t" + x64_sized_mem_at_reg("rax", offset, 2) + ", 0")
    offset += 2
    remaining -= 2
  }
  if remaining > 0 {
    self.emit("\tmov\t" + x64_sized_mem_at_reg("rax", offset, 1) + ", 0")
  }
}

///|
fn X64Codegen::emit_store_aggregate_call_result_to_pushed_addr(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Unit {
  self.emit("\tsub\trsp, 16")
  self.emit("\tmov\tr10, rsp")
  self.emit_store_small_aggregate_return(ty)
  self.emit("\tmov\tr10, QWORD PTR [rsp + 16]")
  self.emit("\tmov\tr11, rsp")
  self.emit_copy_aggregate_from_addr(ty)
  self.emit("\tmov\trax, r10")
  self.emit("\tadd\trsp, 24")
}

///|
fn X64Codegen::emit_call_sret_addr(
  self : X64Codegen,
  ret_ty : @ctype.Type,
) -> Unit {
  if self.is_memory_aggregate(ret_ty) {
    if self.sret_scratch_offset < 0 {
      abort("x86-64 backend missing aggregate return scratch storage")
    }
    self.emit_local_addr(self.sret_scratch_offset)
    self.emit("\tmov\trdi, rax")
  }
}

///|
fn X64Codegen::ensure_va_list_storage(self : X64Codegen, name : String) -> Int {
  if self.va_list_offsets.contains(name) {
    self.va_list_offsets[name]
  } else {
    let offset = self.alloc_local("__kimicc_va_" + name, Array(UChar, 24))
    self.va_list_offsets[name] = offset
    offset
  }
}

///|
fn X64Codegen::emit_atomic_raw_load_to_rax(
  self : X64Codegen,
  addr_reg : String,
  elem_ty : @ctype.Type,
) -> Unit {
  let width = self.type_size(elem_ty)
  let mem = x64_atomic_mem_operand(addr_reg, width)
  match width {
    1 => self.emit("\tmovzx\teax, " + mem)
    2 => self.emit("\tmovzx\teax, " + mem)
    4 => self.emit("\tmov\teax, " + mem)
    _ => self.emit("\tmov\trax, " + mem)
  }
}

///|
fn X64Codegen::emit_atomic_raw_store_from_rax(
  self : X64Codegen,
  addr_reg : String,
  elem_ty : @ctype.Type,
) -> Unit {
  let width = self.type_size(elem_ty)
  let mem = x64_atomic_mem_operand(addr_reg, width)
  let reg = x64_atomic_rax_reg(width)
  self.emit("\tmov\t" + mem + ", " + reg)
}

///|
fn X64Codegen::emit_atomic_clean_rax(
  self : X64Codegen,
  elem_ty : @ctype.Type,
) -> Unit {
  match self.type_size(elem_ty) {
    1 => self.emit("\tmovzx\trax, al")
    2 => self.emit("\tmovzx\trax, ax")
    4 => self.emit("\tmov\teax, eax")
    _ => ()
  }
}

///|
fn X64Codegen::emit_atomic_update_op(
  self : X64Codegen,
  op : String,
  width : Int,
) -> Unit {
  let dst = x64_atomic_r11_reg(width)
  let value = x64_atomic_r10_reg(width)
  match op {
    "+" => self.emit("\tadd\t" + dst + ", " + value)
    "-" => self.emit("\tsub\t" + dst + ", " + value)
    "&" => self.emit("\tand\t" + dst + ", " + value)
    "|" => self.emit("\tor\t" + dst + ", " + value)
    "^" => self.emit("\txor\t" + dst + ", " + value)
    "~&" => {
      self.emit("\tand\t" + dst + ", " + value)
      self.emit("\tnot\t" + dst)
    }
    "max" => {
      let keep_label = self.new_label()
      self.emit("\tcmp\t" + dst + ", " + value)
      self.emit("\tjge\t" + keep_label)
      self.emit("\tmov\t" + dst + ", " + value)
      self.emit(keep_label + ":")
    }
    "min" => {
      let keep_label = self.new_label()
      self.emit("\tcmp\t" + dst + ", " + value)
      self.emit("\tjle\t" + keep_label)
      self.emit("\tmov\t" + dst + ", " + value)
      self.emit(keep_label + ":")
    }
    "umax" => {
      let keep_label = self.new_label()
      self.emit("\tcmp\t" + dst + ", " + value)
      self.emit("\tjae\t" + keep_label)
      self.emit("\tmov\t" + dst + ", " + value)
      self.emit(keep_label + ":")
    }
    "umin" => {
      let keep_label = self.new_label()
      self.emit("\tcmp\t" + dst + ", " + value)
      self.emit("\tjbe\t" + keep_label)
      self.emit("\tmov\t" + dst + ", " + value)
      self.emit(keep_label + ":")
    }
    _ => ()
  }
}

///|
fn X64Codegen::emit_atomic_update_loop(
  self : X64Codegen,
  op : String,
  elem_ty : @ctype.Type,
  return_new : Bool,
) -> Unit {
  let width = self.type_size(elem_ty)
  let loop_label = self.new_label()
  let mem = x64_atomic_mem_operand("rdi", width)
  let src = x64_atomic_r11_reg(width)
  self.emit(loop_label + ":")
  self.emit_atomic_raw_load_to_rax("rdi", elem_ty)
  if width == 8 {
    self.emit("\tmov\tr11, rax")
  } else {
    self.emit("\tmov\tr11d, eax")
  }
  self.emit_atomic_update_op(op, width)
  self.emit("\tlock cmpxchg\t" + mem + ", " + src)
  self.emit("\tjne\t" + loop_label)
  if return_new {
    self.emit("\tmov\trax, r11")
  }
  self.emit_atomic_clean_rax(elem_ty)
  self.emit_int_conversion_to(elem_ty)
}

///|
fn X64Codegen::emit_builtin_fp_bits(
  self : X64Codegen,
  bits : Int64,
  ty : @ctype.Type,
) -> Unit {
  match x64_core_type(ty) {
    Float => {
      self.emit("\tmov\teax, " + bits.to_string())
      self.emit("\tmovd\txmm0, eax")
    }
    _ => {
      self.emit("\tmovabs\trax, " + bits.to_string())
      self.emit("\tmovq\txmm0, rax")
    }
  }
}

///|
fn X64Codegen::field_info(
  self : X64Codegen,
  ty : @ctype.Type,
  field_name : String,
) -> (@ctype.Type, Int) {
  match self.field_layout(ty, field_name) {
    Some((_, field_ty, offset, _, _, _)) => (field_ty, offset)
    None => abort("unknown field: " + field_name)
  }
}

///|
fn x64_field_receiver_type(ty : @ctype.Type) -> @ctype.Type? {
  match x64_core_type(ty) {
    Struct(name) => Some(Struct(name))
    Union(name) => Some(Union(name))
    Pointer(inner) =>
      match x64_core_type(inner) {
        Struct(name) => Some(Struct(name))
        Union(name) => Some(Union(name))
        _ => None
      }
    _ => None
  }
}

///|
fn X64Codegen::field_layout(
  self : X64Codegen,
  ty : @ctype.Type,
  field_name : String,
) -> (String, @ctype.Type, Int, Int, Int, Int)? {
  let lookup_ty = match x64_field_receiver_type(ty) {
    Some(lookup_ty) => lookup_ty
    None => return None
  }
  match self.mir_module {
    Some(mir) =>
      return match mir.field_layout(lookup_ty, field_name) {
        Some(field) =>
          Some(
            (
              field.name,
              field.ty,
              field.offset,
              field.size,
              field.bit_offset,
              match field.bit_width {
                Some(width) => width
                None => -1
              },
            ),
          )
        None => None
      }
    None => ()
  }
  let struct_name = match lookup_ty {
    Struct(name) | Union(name) => name
    _ => return None
  }
  self.ensure_struct_layout(struct_name)
  for field in self.struct_layouts[struct_name] {
    if field.0 == field_name {
      return Some(field)
    }
  }
  None
}

///|
fn X64Codegen::offset_of_path(
  self : X64Codegen,
  ty : @ctype.Type,
  path : Array[@ctype.OffsetDesignator],
) -> Int? {
  match self.mir_module {
    Some(mir) => return mir.offset_of_path(ty, path)
    None => ()
  }
  let mut current_ty = ty
  let mut offset = 0
  for designator in path {
    match designator {
      OffsetField(field) =>
        match self.field_layout(current_ty, field) {
          Some((_, field_ty, field_offset, _, _, _)) => {
            offset += field_offset
            current_ty = field_ty
          }
          None => return None
        }
      OffsetIndex(index) =>
        match x64_offset_array_element_type(current_ty) {
          Some(elem) => {
            offset += index.to_int() * self.type_size(elem)
            current_ty = elem
          }
          None => return None
        }
    }
  }
  Some(offset)
}

///|
fn x64_offset_array_element_type(ty : @ctype.Type) -> @ctype.Type? {
  match x64_core_type(ty) {
    Array(elem, _) => Some(elem)
    _ => None
  }
}

///|
fn X64Codegen::emit_setcc(self : X64Codegen, cc : String) -> Unit {
  self.emit("\t" + cc + "\tal")
  self.emit("\tmovzx\trax, al")
}

///|
fn X64Codegen::emit_int_conversion_to(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Unit {
  match x64_core_type(ty) {
    Bool => {
      self.emit("\tcmp\trax, 0")
      self.emit_setcc("setne")
    }
    UChar => self.emit("\tmovzx\trax, al")
    SChar => self.emit("\tmovsx\trax, al")
    UShort => self.emit("\tmovzx\trax, ax")
    SShort => self.emit("\tmovsx\trax, ax")
    UInt => self.emit("\tmov\teax, eax")
    SInt => self.emit("\tmovsxd\trax, eax")
    _ => ()
  }
}

///|
fn X64Codegen::emit_extend_rax_to_int128(
  self : X64Codegen,
  src_ty : @ctype.Type,
) -> Unit {
  if x64_is_int128_type(src_ty) {
    return
  }
  if src_ty.is_signed() {
    self.emit("\tcqo")
  } else {
    self.emit("\txor\trdx, rdx")
  }
}

///|
fn X64Codegen::emit_abi_int_return_conversion(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Unit {
  match x64_core_type(ty) {
    Bool | UChar => self.emit("\tmovzx\trax, al")
    SChar => self.emit("\tmovsx\trax, al")
    UShort => self.emit("\tmovzx\trax, ax")
    SShort => self.emit("\tmovsx\trax, ax")
    UInt => self.emit("\tmov\teax, eax")
    SInt => self.emit("\tmovsxd\trax, eax")
    _ => ()
  }
}

///|
fn x64_binary_int_type(
  op : String,
  lhs_ty : @ctype.Type,
  rhs_ty : @ctype.Type,
) -> @ctype.Type {
  if op == "<<" || op == ">>" {
    unary_integer_result_type(lhs_ty)
  } else {
    integer_common_type(lhs_ty, rhs_ty)
  }
}

///|
fn x64_binary_rhs_int_type(
  op : String,
  lhs_ty : @ctype.Type,
  rhs_ty : @ctype.Type,
) -> @ctype.Type {
  if op == "<<" || op == ">>" {
    unary_integer_result_type(rhs_ty)
  } else {
    integer_common_type(lhs_ty, rhs_ty)
  }
}

///|
fn x64_binary_converts_result(op : String) -> Bool {
  match op {
    "+" | "-" | "*" | "/" | "%" | "&" | "|" | "^" | "<<" | ">>" => true
    _ => false
  }
}

///|
fn x64_ternary_result_type(
  then_ty : @ctype.Type,
  else_ty : @ctype.Type,
) -> @ctype.Type {
  match (x64_core_type(then_ty), x64_core_type(else_ty)) {
    (Array(elem, _), _) => Pointer(elem)
    (_, Array(elem, _)) => Pointer(elem)
    (Pointer(elem), _) => Pointer(elem)
    (_, Pointer(elem)) => Pointer(elem)
    (FuncPtr(ret, params, variadic), _) => FuncPtr(ret, params, variadic)
    (_, FuncPtr(ret, params, variadic)) => FuncPtr(ret, params, variadic)
    _ =>
      if x64_is_fp_type(then_ty) || x64_is_fp_type(else_ty) {
        if x64_core_type(then_ty) == Double || x64_core_type(else_ty) == Double {
          Double
        } else {
          Float
        }
      } else if then_ty.is_integer() && else_ty.is_integer() {
        integer_common_type(then_ty, else_ty)
      } else {
        then_ty
      }
  }
}

///|
fn X64Codegen::emit_load_fp_literal(self : X64Codegen, value : Double) -> Unit {
  self.emit_load_fp_literal_into("xmm0", value)
}

///|
fn X64Codegen::emit_load_fp_literal_into(
  self : X64Codegen,
  reg : String,
  value : Double,
) -> Unit {
  let id = self.fp_literals.length()
  self.fp_literals.push(value)
  self.emit(
    "\tmovsd\t" + reg + ", QWORD PTR [rip + .Lfp" + id.to_string() + "]",
  )
}

///|
fn X64Codegen::emit_fp_to_bool(self : X64Codegen, ty : @ctype.Type) -> Unit {
  self.emit("\tpxor\txmm1, xmm1")
  self.emit("\tucomi" + x64_fp_suffix(ty) + "\txmm0, xmm1")
  self.emit("\tsetne\tal")
  self.emit("\tsetp\tdl")
  self.emit("\tor\tal, dl")
  self.emit("\tmovzx\trax, al")
}

///|
fn X64Codegen::emit_int128_to_bool(self : X64Codegen) -> Unit {
  self.emit("\tor\trax, rdx")
  self.emit_setcc("setne")
}

///|
fn X64Codegen::emit_push_int128(self : X64Codegen) -> Unit {
  self.emit("\tpush\trdx")
  self.emit("\tpush\trax")
}

///|
fn X64Codegen::emit_pop_int128(self : X64Codegen) -> Unit {
  self.emit("\tpop\trax")
  self.emit("\tpop\trdx")
}

///|
fn X64Codegen::emit_int128_compare(
  self : X64Codegen,
  op : String,
  is_unsigned : Bool,
) -> Unit {
  let high_diff = self.new_label()
  let done = self.new_label()
  self.emit("\tcmp\trdx, r11")
  self.emit("\tjne\t" + high_diff)
  self.emit("\tcmp\trax, r10")
  match op {
    "==" => self.emit_setcc("sete")
    "!=" => self.emit_setcc("setne")
    "<" => self.emit_setcc("setb")
    "<=" => self.emit_setcc("setbe")
    ">" => self.emit_setcc("seta")
    ">=" => self.emit_setcc("setae")
    _ => self.emit("\tmov\trax, 0")
  }
  self.emit("\tjmp\t" + done)
  self.emit(high_diff + ":")
  match op {
    "==" => self.emit("\tmov\trax, 0")
    "!=" => self.emit("\tmov\trax, 1")
    "<" =>
      if is_unsigned {
        self.emit_setcc("setb")
      } else {
        self.emit_setcc("setl")
      }
    "<=" =>
      if is_unsigned {
        self.emit_setcc("setb")
      } else {
        self.emit_setcc("setl")
      }
    ">" =>
      if is_unsigned {
        self.emit_setcc("seta")
      } else {
        self.emit_setcc("setg")
      }
    ">=" =>
      if is_unsigned {
        self.emit_setcc("seta")
      } else {
        self.emit_setcc("setg")
      }
    _ => self.emit("\tmov\trax, 0")
  }
  self.emit(done + ":")
}

///|
fn X64Codegen::emit_int128_left_shift(self : X64Codegen) -> Unit {
  let wide = self.new_label()
  let done = self.new_label()
  self.emit("\tand\trcx, 127")
  self.emit("\tcmp\trcx, 0")
  self.emit("\tje\t" + done)
  self.emit("\tcmp\trcx, 64")
  self.emit("\tjae\t" + wide)
  self.emit("\tshld\trdx, rax, cl")
  self.emit("\tshl\trax, cl")
  self.emit("\tjmp\t" + done)
  self.emit(wide + ":")
  self.emit("\tsub\trcx, 64")
  self.emit("\tmov\trdx, rax")
  self.emit("\tshl\trdx, cl")
  self.emit("\txor\trax, rax")
  self.emit(done + ":")
}

///|
fn X64Codegen::emit_int128_right_shift(
  self : X64Codegen,
  is_unsigned : Bool,
) -> Unit {
  let wide = self.new_label()
  let done = self.new_label()
  self.emit("\tand\trcx, 127")
  self.emit("\tcmp\trcx, 0")
  self.emit("\tje\t" + done)
  self.emit("\tcmp\trcx, 64")
  self.emit("\tjae\t" + wide)
  self.emit("\tshrd\trax, rdx, cl")
  if is_unsigned {
    self.emit("\tshr\trdx, cl")
  } else {
    self.emit("\tsar\trdx, cl")
  }
  self.emit("\tjmp\t" + done)
  self.emit(wide + ":")
  self.emit("\tsub\trcx, 64")
  self.emit("\tmov\trax, rdx")
  if is_unsigned {
    self.emit("\tshr\trax, cl")
    self.emit("\txor\trdx, rdx")
  } else {
    self.emit("\tsar\trax, cl")
    self.emit("\tsar\trdx, 63")
  }
  self.emit(done + ":")
}

///|
fn X64Codegen::emit_int128_libcall(self : X64Codegen, name : String) -> Unit {
  self.emit("\tmov\trdi, rax")
  self.emit("\tmov\trsi, rdx")
  self.emit("\tmov\trdx, r10")
  self.emit("\tmov\trcx, r11")
  self.emit("\tmov\tr8, rsp")
  self.emit("\tand\trsp, -16")
  self.emit("\tsub\trsp, 16")
  self.emit("\tmov\tQWORD PTR [rsp], r8")
  self.emit("\tcall\t" + name)
  self.emit("\tmov\trsp, QWORD PTR [rsp]")
}

///|
fn X64Codegen::emit_fp_compare_result(self : X64Codegen, op : String) -> Unit {
  match op {
    "==" => {
      self.emit("\tsete\tal")
      self.emit("\tsetnp\tdl")
      self.emit("\tand\tal, dl")
      self.emit("\tmovzx\trax, al")
    }
    "!=" => {
      self.emit("\tsetne\tal")
      self.emit("\tsetp\tdl")
      self.emit("\tor\tal, dl")
      self.emit("\tmovzx\trax, al")
    }
    "<" => {
      self.emit("\tsetb\tal")
      self.emit("\tsetnp\tdl")
      self.emit("\tand\tal, dl")
      self.emit("\tmovzx\trax, al")
    }
    "<=" => {
      self.emit("\tsetbe\tal")
      self.emit("\tsetnp\tdl")
      self.emit("\tand\tal, dl")
      self.emit("\tmovzx\trax, al")
    }
    ">" => self.emit_setcc("seta")
    ">=" => self.emit_setcc("setae")
    "<>" => {
      self.emit("\tsetne\tal")
      self.emit("\tsetnp\tdl")
      self.emit("\tand\tal, dl")
      self.emit("\tmovzx\trax, al")
    }
    "unordered" => self.emit_setcc("setp")
    _ => self.emit("\tmov\trax, 0")
  }
}

///|
fn X64Codegen::emit_fp_cond_jump_false(
  self : X64Codegen,
  ty : @ctype.Type,
  false_label : String,
) -> Unit {
  let true_label = self.new_label()
  self.emit("\tpxor\txmm1, xmm1")
  self.emit("\tucomi" + x64_fp_suffix(ty) + "\txmm0, xmm1")
  self.emit("\tjp\t" + true_label)
  self.emit("\tje\t" + false_label)
  self.emit(true_label + ":")
}

///|
fn X64Codegen::emit_switch_case_compare(
  self : X64Codegen,
  case_value : Int64,
  control_ty : @ctype.Type,
) -> Unit {
  match switch_control_type(control_ty) {
    SInt | UInt => {
      self.emit("\tmov\tr10d, " + x64_signed_i32_bits(case_value).to_string())
      self.emit("\tcmp\teax, r10d")
    }
    _ =>
      if x64_fits_i32(case_value) {
        self.emit("\tcmp\trax, " + case_value.to_string())
      } else {
        self.emit("\tmovabs\tr10, " + case_value.to_string())
        self.emit("\tcmp\trax, r10")
      }
  }
}

///|
fn X64Codegen::label_ref(self : X64Codegen, name : String) -> String {
  if !self.emitted_labels.contains(name) {
    let label = if name == "default" ||
      is_numeric_case_label(name) ||
      name.has_prefix("__kimicc_case_") ||
      name.has_prefix("__kimicc_default_") {
      self.new_label()
    } else {
      ".L" + self.func_name + "_label_" + sanitize_label(name)
    }
    self.emitted_labels[name] = label
  }
  self.emitted_labels[name]
}

///|
fn X64Codegen::emit_global_int_by_size(
  self : X64Codegen,
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
fn X64Codegen::emit_global_float(
  self : X64Codegen,
  ty : @ctype.Type,
  value : Double,
) -> Unit {
  let literal = codegen_float_asm_literal(value)
  match x64_core_type(ty) {
    Float => self.emit("\t.float\t" + literal)
    _ => self.emit("\t.double\t" + literal)
  }
}

///|
fn X64Codegen::mir_global_scalar_int_supported(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Bool {
  match ty {
    Aligned(inner, _) => self.mir_global_scalar_int_supported(inner)
    _ =>
      match x64_core_type(ty) {
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
        | Pointer(_)
        | FuncPtr(_, _, _) => true
        _ => false
      }
  }
}

///|
fn X64Codegen::mir_global_string_supported(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Bool {
  match ty {
    Aligned(inner, _) => self.mir_global_string_supported(inner)
    _ =>
      match x64_core_type(ty) {
        Array(SChar, _) | Array(UChar, _) | Pointer(_) => true
        _ => false
      }
  }
}

///|
fn X64Codegen::mir_global_symbol_supported(
  self : X64Codegen,
  ty : @ctype.Type,
) -> Bool {
  match ty {
    Aligned(inner, _) => self.mir_global_symbol_supported(inner)
    _ =>
      match x64_core_type(ty) {
        Pointer(_) | FuncPtr(_, _, _) => true
        _ => false
      }
  }
}

///|
fn X64Codegen::mir_global_init_supported(
  self : X64Codegen,
  ty : @ctype.Type,
  init : @mir.MirGlobalInit,
) -> Bool {
  match ty {
    Aligned(inner, _) => self.mir_global_init_supported(inner, init)
    _ =>
      match init {
        MirGlobalInitUnsupported => false
        MirGlobalScalarInt(_) => self.mir_global_scalar_int_supported(ty)
        MirGlobalScalarFloat(_) =>
          match x64_core_type(ty) {
            Float | Double => true
            _ => false
          }
        MirGlobalString(_) => self.mir_global_string_supported(ty)
        MirGlobalSymbol(_) => self.mir_global_symbol_supported(ty)
        MirGlobalSymbolOffset(_, _) => self.mir_global_symbol_supported(ty)
        MirGlobalArraySparse(values) =>
          match x64_core_type(ty) {
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
          match x64_core_type(ty) {
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
          match x64_core_type(ty) {
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
fn X64Codegen::mir_aggregate_layout(
  self : X64Codegen,
  name : String,
) -> @mir.AggregateLayout? {
  match self.mir_module {
    Some(mir) => mir.layouts.get(name)
    None => None
  }
}

///|
fn X64Codegen::emit_mir_global_scalar_int(
  self : X64Codegen,
  ty : @ctype.Type,
  value : Int64,
) -> Unit {
  match ty {
    Aligned(inner, _) => {
      self.emit_mir_global_scalar_int(inner, value)
      return
    }
    _ => ()
  }
  match x64_core_type(ty) {
    Bool | SChar | UChar => self.emit_global_int_by_size(1, value)
    SShort | UShort => self.emit_global_int_by_size(2, value)
    SInt | UInt => self.emit_global_int_by_size(4, value)
    SInt128 => {
      self.emit_global_int_by_size(8, value)
      self.emit_global_int_by_size(8, if value < 0L { -1L } else { 0L })
    }
    UInt128 => {
      self.emit_global_int_by_size(8, value)
      self.emit_global_int_by_size(8, 0L)
    }
    Float | Double => self.emit_global_float(ty, value.to_double())
    _ => self.emit_global_int_by_size(8, value)
  }
}

///|
fn X64Codegen::emit_mir_global_string(
  self : X64Codegen,
  ty : @ctype.Type,
  value : String,
) -> Unit {
  match ty {
    Aligned(inner, _) => {
      self.emit_mir_global_string(inner, value)
      return
    }
    _ => ()
  }
  match x64_core_type(ty) {
    Array(SChar, n) | Array(UChar, n) => {
      self.emit("\t.asciz\t\"" + escape_string(value) + "\"")
      let pad = n - value.length() - 1
      if pad > 0 {
        self.emit("\t.zero\t" + pad.to_string())
      }
    }
    _ => {
      let id = self.strings.length()
      self.strings.push(value)
      self.emit("\t.quad\t.Lstr" + id.to_string())
    }
  }
}

///|
fn X64Codegen::emit_mir_global_init(
  self : X64Codegen,
  ty : @ctype.Type,
  init : @mir.MirGlobalInit,
) -> Unit {
  match ty {
    Aligned(inner, _) => {
      self.emit_mir_global_init(inner, init)
      return
    }
    _ => ()
  }
  match init {
    MirGlobalScalarInt(value) => self.emit_mir_global_scalar_int(ty, value)
    MirGlobalScalarFloat(value) => self.emit_global_float(ty, value)
    MirGlobalString(value) => self.emit_mir_global_string(ty, value)
    MirGlobalSymbol(name) => self.emit("\t.quad\t" + name)
    MirGlobalSymbolOffset(name, offset) =>
      self.emit("\t.quad\t" + reloc_with_offset(name, offset))
    MirGlobalArraySparse(values) =>
      match x64_core_type(ty) {
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
              None => self.emit("\t.zero\t" + elem_size.to_string())
            }
          }
        }
        _ => self.emit("\t.zero\t" + self.type_size(ty).to_string())
      }
    MirGlobalAggregateSparse(values) =>
      match x64_core_type(ty) {
        Struct(name) | Union(name) =>
          self.emit_mir_global_sparse_aggregate(name, values)
        _ => self.emit("\t.zero\t" + self.type_size(ty).to_string())
      }
    MirGlobalArray(values) =>
      match x64_core_type(ty) {
        Array(elem_ty, n) => {
          let elem_size = self.type_size(elem_ty)
          let mut emitted = 0
          for value in values {
            self.emit_mir_global_init(elem_ty, value)
            emitted += 1
          }
          while emitted < n {
            self.emit("\t.zero\t" + elem_size.to_string())
            emitted += 1
          }
        }
        Struct(name) | Union(name) =>
          self.emit_mir_global_aggregate(name, values)
        _ => self.emit("\t.zero\t" + self.type_size(ty).to_string())
      }
    MirGlobalInitUnsupported =>
      self.emit("\t.zero\t" + self.type_size(ty).to_string())
  }
}

///|
fn X64Codegen::emit_mir_global_aggregate(
  self : X64Codegen,
  name : String,
  values : Array[@mir.MirGlobalInit],
) -> Unit {
  let layout = match self.mir_aggregate_layout(name) {
    Some(layout) => layout
    None => {
      self.emit("\t.zero\t8")
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
fn X64Codegen::emit_mir_global_sparse_aggregate(
  self : X64Codegen,
  name : String,
  values : Array[(Int, @mir.MirGlobalInit)],
) -> Unit {
  let layout = match self.mir_aggregate_layout(name) {
    Some(layout) => layout
    None => {
      self.emit("\t.zero\t8")
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
fn X64Codegen::mir_global_bitfield_bits(
  self : X64Codegen,
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
fn X64Codegen::emit_mir_global_bitfield_container(
  self : X64Codegen,
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
fn X64Codegen::emit_mir_global_aggregate_slots(
  self : X64Codegen,
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
            self.emit("\t.zero\t" + (field.offset - emitted).to_string())
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
        self.emit("\t.zero\t" + (field.offset - emitted).to_string())
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
            None => self.emit("\t.zero\t" + field.size.to_string())
          }
          emitted = field.offset + field.size
        }
      }
      i += 1
    }
  }
  if layout.size > emitted {
    self.emit("\t.zero\t" + (layout.size - emitted).to_string())
  }
}

///|
fn X64Codegen::try_emit_mir_global_init(
  self : X64Codegen,
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
fn X64Codegen::emit_mir_globals(
  self : X64Codegen,
  globals : Array[@mir.MirGlobalDecl],
) -> Unit {
  let codegen_globals = codegen_global_decls_from_mir(globals)
  self.emit_global_decl_directives(codegen_globals)
  for g in globals {
    if g.has_init && g.symbol_alias is None {
      self.emit_global_data_section(g.section)
      self.emit_symbol_binding(g.name, g.is_static, g.is_weak, g.visibility)
      self.emit("\t.align\t" + self.type_align(g.ty).to_string())
      self.emit(g.name + ":")
      if !self.try_emit_mir_global_init(g) {
        self.emit("\t.zero\t" + self.type_size(g.ty).to_string())
      }
    }
  }
  self.emit_global_bss_definitions(codegen_globals)
}

///|
fn X64Codegen::emit_global_decl_directives(
  self : X64Codegen,
  globals : Array[CodegenGlobalDecl],
) -> Unit {
  for g in globals {
    match g.symbol_alias {
      Some(target) =>
        self.emit_symbol_alias(
          g.name,
          target,
          g.is_static,
          g.is_weak,
          g.visibility,
          Some("@object"),
        )
      None => {
        if !g.has_init && g.is_extern && g.is_weak && !g.is_static {
          self.emit("\t.weak\t" + g.name)
        }
        if !g.has_init && g.is_extern {
          self.emit_symbol_visibility(g.name, g.is_static, g.visibility)
        }
      }
    }
  }
}

///|
fn X64Codegen::emit_global_bss_definitions(
  self : X64Codegen,
  globals : Array[CodegenGlobalDecl],
) -> Unit {
  for g in globals {
    if !g.has_init && !g.is_extern && g.symbol_alias is None {
      self.emit_global_bss_section(g.section)
      self.emit_symbol_binding(g.name, g.is_static, g.is_weak, g.visibility)
      self.emit("\t.align\t" + self.type_align(g.ty).to_string())
      self.emit(g.name + ":")
      self.emit("\t.zero\t" + self.type_size(g.ty).to_string())
    }
  }
}

///|
fn X64Codegen::emit_function_section(
  self : X64Codegen,
  section : String?,
) -> Unit {
  match section {
    Some(name) => self.emit("\t.section\t" + name + ",\"ax\",@progbits")
    None => self.emit("\t.text")
  }
}

///|
fn X64Codegen::emit_global_data_section(
  self : X64Codegen,
  section : String?,
) -> Unit {
  match section {
    Some(name) => self.emit("\t.section\t" + name + ",\"aw\",@progbits")
    None => self.emit("\t.data")
  }
}

///|
fn X64Codegen::emit_global_bss_section(
  self : X64Codegen,
  section : String?,
) -> Unit {
  match section {
    Some(name) => self.emit("\t.section\t" + name + ",\"aw\",@progbits")
    None => self.emit("\t.bss")
  }
}

///|
fn X64Codegen::emit_symbol_binding(
  self : X64Codegen,
  name : String,
  is_static : Bool,
  is_weak : Bool,
  visibility : String?,
) -> Unit {
  if !is_static {
    if is_weak {
      self.emit("\t.weak\t" + name)
    } else {
      self.emit("\t.globl\t" + name)
    }
    self.emit_symbol_visibility(name, is_static, visibility)
  }
}

///|
fn X64Codegen::emit_symbol_visibility(
  self : X64Codegen,
  name : String,
  is_static : Bool,
  visibility : String?,
) -> Unit {
  if is_static {
    return
  }
  match visibility {
    Some("hidden") => self.emit("\t.hidden\t" + name)
    Some("protected") => self.emit("\t.protected\t" + name)
    Some("internal") => self.emit("\t.internal\t" + name)
    _ => ()
  }
}

///|
fn X64Codegen::emit_symbol_alias(
  self : X64Codegen,
  name : String,
  target : String,
  is_static : Bool,
  is_weak : Bool,
  visibility : String?,
  symbol_type : String?,
) -> Unit {
  self.emit_symbol_binding(name, is_static, is_weak, visibility)
  match symbol_type {
    Some(kind) => self.emit("\t.type\t" + name + ", " + kind)
    None => ()
  }
  self.emit("\t.set\t" + name + ", " + target)
}

///|
fn X64Codegen::symbol_addr_needs_got(self : X64Codegen, name : String) -> Bool {
  if self.globals.contains(name) {
    self.globals[name].is_extern && self.globals[name].symbol_alias is None
  } else if self.func_rets.contains(name) {
    !self.func_defined.get_or_default(name, false)
  } else {
    false
  }
}

///|
fn X64Codegen::emit_symbol_addr(self : X64Codegen, name : String) -> Unit {
  if self.symbol_addr_needs_got(name) {
    self.emit("\tmov\trax, QWORD PTR [rip + " + name + "@GOTPCREL]")
  } else {
    self.emit("\tlea\trax, [rip + " + name + "]")
  }
}

///|
fn X64Codegen::emit_strings(self : X64Codegen) -> Unit {
  if self.strings.length() == 0 {
    return
  }
  self.emit("\t.section\t.rodata")
  for i = 0; i < self.strings.length(); i = i + 1 {
    self.emit(".Lstr" + i.to_string() + ":")
    self.emit("\t.asciz\t\"" + escape_string(self.strings[i]) + "\"")
  }
}

///|
fn X64Codegen::emit_fp_literals(self : X64Codegen) -> Unit {
  if self.fp_literals.length() == 0 {
    return
  }
  self.emit("\t.section\t.rodata")
  self.emit("\t.align\t8")
  for i = 0; i < self.fp_literals.length(); i = i + 1 {
    self.emit(".Lfp" + i.to_string() + ":")
    self.emit("\t.double\t" + codegen_float_asm_literal(self.fp_literals[i]))
  }
}

///|
fn X64Codegen::emit_lifecycle_array(
  self : X64Codegen,
  section : String,
  decls : Array[CodegenFuncDecl],
) -> Unit {
  let mut emitted = false
  for decl in decls {
    let should_emit = if section == ".init_array" {
      decl.is_constructor
    } else {
      decl.is_destructor
    }
    if should_emit && decl.has_body {
      if !emitted {
        let kind = if section == ".init_array" {
          "init_array"
        } else {
          "fini_array"
        }
        self.emit("\t.section\t" + section + ",\"aw\",@" + kind)
        self.emit("\t.align\t8")
        emitted = true
      }
      self.emit("\t.quad\t" + decl.name)
    }
  }
}

///|
fn X64Codegen::emit_mir_function_decl_directives(
  self : X64Codegen,
  decl : CodegenFuncDecl,
) -> Unit {
  match decl.symbol_alias {
    Some(target) =>
      self.emit_symbol_alias(
        decl.name,
        target,
        decl.is_static,
        decl.is_weak,
        decl.visibility,
        Some("@function"),
      )
    None =>
      if !decl.has_body &&
        self.func_weak.get_or_default(decl.name, false) &&
        !decl.is_static {
        self.emit("\t.weak\t" + decl.name)
      }
  }
  if decl.symbol_alias is None && !decl.has_body {
    self.emit_symbol_visibility(decl.name, decl.is_static, decl.visibility)
  }
}

///|
fn X64Codegen::generate_mir_only(
  self : X64Codegen,
  mir_module : @mir.MirModule,
) -> String {
  self.emit("\t.intel_syntax noprefix")
  self.emit("\t.text")
  self.register_mir_aggregate_layouts(mir_module)
  self.register_mir_function_decls(mir_module)
  self.register_mir_global_decls(mir_module)
  let codegen_func_decls = codegen_func_decls_from_mir(mir_module.decls)
  for decl in codegen_func_decls {
    self.emit_mir_function_decl_directives(decl)
  }
  for decl in mir_module.decls {
    if decl.has_body {
      match mir_module.bodies.get(decl.name) {
        Some(body) => self.gen_mir_func(decl, body)
        None => ()
      }
    }
  }
  self.emit_mir_globals(@mir.merge_global_decls(mir_module.global_decls))
  self.emit_lifecycle_array(".init_array", codegen_func_decls)
  self.emit_lifecycle_array(".fini_array", codegen_func_decls)
  self.emit_strings()
  self.emit_fp_literals()
  self.emit("\t.section\t.note.GNU-stack,\"\",@progbits")
  self.output.to_string()
}
