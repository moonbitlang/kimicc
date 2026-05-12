///|
priv struct X64Codegen {
  output : StringBuilder
  mut label_counter : Int
  mut local_offsets : Map[String, Int]
  mut var_types : Map[String, @parser.Type]
  mut stack_size : Int
  mut stack_align : Int
  mut local_base_reg : String
  mut func_name : String
  func_rets : Map[String, @parser.Type]
  func_variadic : Map[String, Bool]
  func_param_counts : Map[String, Int]
  func_param_types : Map[String, Array[@parser.Type]]
  struct_layouts : Map[
    String,
    Array[(String, @parser.Type, Int, Int, Int, Int)],
  ]
  struct_decls : Map[String, @parser.StructDecl]
  globals : Map[String, @parser.GlobalDecl]
  strings : Array[String]
  fp_literals : Array[Double]
  mut va_list_offsets : Map[String, Int]
  mut va_reg_save_offset : Int
  mut va_initial_gp_offset : Int
  mut va_initial_fp_offset : Int
  mut va_initial_overflow_offset : Int
  mut sret_dest_offset : Int
  mut sret_scratch_offset : Int
  mut sret_scratch_size : Int
  mut sret_scratch_align : Int
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
    struct_layouts: {},
    struct_decls: {},
    globals: {},
    strings: [],
    fp_literals: [],
    va_list_offsets: {},
    va_reg_save_offset: -1,
    va_initial_gp_offset: 0,
    va_initial_fp_offset: 48,
    va_initial_overflow_offset: 16,
    sret_dest_offset: -1,
    sret_scratch_offset: -1,
    sret_scratch_size: 0,
    sret_scratch_align: 1,
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
fn x64_core_type(ty : @parser.Type) -> @parser.Type {
  match ty {
    Atomic(inner) | Aligned(inner, _) => x64_core_type(inner)
    _ => ty
  }
}

///|
fn x64_is_pointer_like(ty : @parser.Type) -> Bool {
  match x64_core_type(ty) {
    Pointer(_) | Array(_, _) => true
    _ => false
  }
}

///|
fn x64_pointer_element(ty : @parser.Type) -> @parser.Type? {
  match x64_core_type(ty) {
    Pointer(elem) | Array(elem, _) => Some(elem)
    _ => None
  }
}

///|
fn X64Codegen::pointer_element_size(
  self : X64Codegen,
  elem_ty : @parser.Type,
) -> Int {
  match x64_core_type(elem_ty) {
    Void => 1
    _ => self.type_size(elem_ty)
  }
}

///|
fn x64_is_fp_type(ty : @parser.Type) -> Bool {
  match x64_core_type(ty) {
    Float | Double => true
    _ => false
  }
}

///|
fn x64_is_int128_type(ty : @parser.Type) -> Bool {
  match x64_core_type(ty) {
    SInt128 | UInt128 => true
    _ => false
  }
}

///|
fn x64_reject_unsupported_scalar(ty : @parser.Type) -> Unit {
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
fn x64_is_aggregate_type(ty : @parser.Type) -> Bool {
  match x64_core_type(ty) {
    Struct(_) | Union(_) => true
    _ => false
  }
}

///|
fn x64_is_object_aggregate_type(ty : @parser.Type) -> Bool {
  match x64_core_type(ty) {
    Array(_, _) | Struct(_) | Union(_) => true
    _ => false
  }
}

///|
fn x64_atomic_target_type(ty : @parser.Type) -> @parser.Type {
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
  ty : @parser.Type
  size : Int
  bit_offset : Int
  bit_width : Int
}

///|
fn x64_fp_suffix(ty : @parser.Type) -> String {
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
fn X64Codegen::type_size(self : X64Codegen, ty : @parser.Type) -> Int {
  match ty {
    Atomic(inner) | Aligned(inner, _) => self.type_size(inner)
    _ =>
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
        Struct(name) => {
          self.ensure_struct_layout(name)
          let fields = self.struct_layouts[name]
          let mut max_end = 0
          let mut max_align = 1
          let is_packed = self.struct_decls.contains(name) &&
            self.struct_decls[name].is_packed
          for field in fields {
            let end = field.2 + field.3
            if end > max_end {
              max_end = end
            }
            if !is_packed {
              let align = self.type_align(field.1)
              if align > max_align {
                max_align = align
              }
            }
          }
          x64_align_to(max_end, max_align)
        }
        Union(name) => {
          self.ensure_struct_layout(name)
          let fields = self.struct_layouts[name]
          let mut max_size = 0
          let mut max_align = 1
          let is_packed = self.struct_decls.contains(name) &&
            self.struct_decls[name].is_packed
          for field in fields {
            let size = self.type_size(field.1)
            if size > max_size {
              max_size = size
            }
            if !is_packed {
              let align = self.type_align(field.1)
              if align > max_align {
                max_align = align
              }
            }
          }
          x64_align_to(max_size, max_align)
        }
        Atomic(_) | Aligned(_, _) => abort("unreachable x86-64 wrapped type")
      }
  }
}

///|
fn X64Codegen::type_align(self : X64Codegen, ty : @parser.Type) -> Int {
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
        Struct(name) | Union(name) => {
          if self.struct_decls.contains(name) &&
            self.struct_decls[name].is_packed {
            return 1
          }
          self.ensure_struct_layout(name)
          let fields = self.struct_layouts[name]
          let mut max_align = 1
          for field in fields {
            let align = self.type_align(field.1)
            if align > max_align {
              max_align = align
            }
          }
          max_align
        }
        Atomic(_) | Aligned(_, _) => abort("unreachable x86-64 wrapped type")
      }
  }
}

///|
fn X64Codegen::ensure_struct_layout(self : X64Codegen, name : String) -> Unit {
  if self.struct_layouts.contains(name) {
    return
  }
  if !self.struct_decls.contains(name) {
    self.struct_layouts[name] = []
    return
  }
  self.compute_struct_layout(self.struct_decls[name])
}

///|
fn X64Codegen::compute_struct_layout(
  self : X64Codegen,
  decl : @parser.StructDecl,
) -> Unit {
  if self.struct_layouts.contains(decl.name) {
    return
  }
  let fields : Array[(String, @parser.Type, Int, Int, Int, Int)] = []
  if decl.is_union {
    for field in decl.fields {
      let size = self.type_size(field.ty)
      match field.bit_width {
        Some(width) =>
          if width > 0 {
            fields.push((field.name, field.ty, 0, size, 0, width))
          }
        None => fields.push((field.name, field.ty, 0, size, 0, -1))
      }
    }
  } else {
    let mut offset = 0
    let mut in_bitfield_run = false
    let mut current_bit_offset = 0
    for field in decl.fields {
      match field.bit_width {
        None => {
          let align = if decl.is_packed { 1 } else { self.type_align(field.ty) }
          offset = x64_align_to(offset, align)
          let size = self.type_size(field.ty)
          fields.push((field.name, field.ty, offset, size, 0, -1))
          offset += size
          in_bitfield_run = false
          current_bit_offset = 0
        }
        Some(width) => {
          let container_size = self.type_size(field.ty)
          let container_align = if decl.is_packed {
            1
          } else {
            self.type_align(field.ty)
          }
          let container_bits = container_size * 8
          if width == 0 {
            offset = x64_align_to(offset, container_align)
            in_bitfield_run = false
            current_bit_offset = 0
          } else {
            let mut container_offset = current_bit_offset /
              (container_align * 8) *
              container_align
            let mut field_bit_offset = current_bit_offset - container_offset * 8
            let can_continue = in_bitfield_run &&
              field_bit_offset + width <= container_bits
            if !can_continue {
              container_offset = offset / container_align * container_align
              field_bit_offset = (offset - container_offset) * 8
              if offset >= container_offset + container_size ||
                field_bit_offset + width > container_bits {
                container_offset = x64_align_to(offset, container_align)
                field_bit_offset = 0
              }
              current_bit_offset = container_offset * 8 + field_bit_offset
            }
            fields.push(
              (
                field.name,
                field.ty,
                container_offset,
                container_size,
                field_bit_offset,
                width,
              ),
            )
            in_bitfield_run = true
            current_bit_offset += width
            let end_offset = (current_bit_offset + 7) / 8
            if end_offset > offset {
              offset = end_offset
            }
          }
        }
      }
    }
  }
  self.struct_layouts[decl.name] = fields
}

///|
fn X64Codegen::alloc_local(
  self : X64Codegen,
  name : String,
  ty : @parser.Type,
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
fn X64Codegen::emit_load_indirect(self : X64Codegen, ty : @parser.Type) -> Unit {
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
fn X64Codegen::emit_store_indirect(
  self : X64Codegen,
  ty : @parser.Type,
) -> Unit {
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
  ty : @parser.Type,
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
  ty : @parser.Type,
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
fn x64_scalar_aggregate_class(ty : @parser.Type) -> X64AggregateClass? {
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
  ty : @parser.Type,
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
  ty : @parser.Type,
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
  ty : @parser.Type,
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
  ty : @parser.Type,
) -> Bool {
  self.aggregate_classes(ty) is Some(_)
}

///|
fn X64Codegen::is_memory_aggregate(
  self : X64Codegen,
  ty : @parser.Type,
) -> Bool {
  x64_is_aggregate_type(ty) && self.aggregate_classes(ty) is None
}

///|
fn X64Codegen::aggregate_word_count(
  self : X64Codegen,
  ty : @parser.Type,
) -> Int {
  x64_align_to(self.type_size(ty), 8) / 8
}

///|
fn X64Codegen::stack_arg_align_slots(
  self : X64Codegen,
  ty : @parser.Type,
) -> Int {
  let align = self.type_align(ty)
  if x64_is_int128_type(ty) || align > 8 {
    x64_align_to(align, 8) / 8
  } else {
    1
  }
}

///|
fn X64Codegen::align_stack_arg_index(
  self : X64Codegen,
  index : Int,
  ty : @parser.Type,
) -> Int {
  x64_align_to(index, self.stack_arg_align_slots(ty))
}

///|
fn X64Codegen::align_call_stack_arg(
  self : X64Codegen,
  index : Int,
  call_align : Int,
  ty : @parser.Type,
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
  ty : @parser.Type,
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
fn X64Codegen::emit_store_int_bytes_to_local(
  self : X64Codegen,
  src_reg : String,
  local_offset : Int,
  byte_offset : Int,
  width : Int,
) -> Unit {
  self.emit_store_int_bytes_to_mem_refs(
    src_reg,
    self.local_neg_ref(local_offset, byte_offset),
    self.local_neg_ref(local_offset, byte_offset + 2),
    self.local_neg_ref(local_offset, byte_offset + 4),
    self.local_neg_ref(local_offset, byte_offset + 6),
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
fn X64Codegen::emit_store_sse_word_to_local(
  self : X64Codegen,
  src_reg : String,
  local_offset : Int,
  byte_offset : Int,
  width : Int,
) -> Unit {
  let mem = self.local_neg_ref(local_offset, byte_offset)
  if width <= 4 {
    self.emit("\tmovss\t" + x64_sized_mem_ref(mem, 4) + ", " + src_reg)
  } else {
    self.emit("\tmovsd\t" + x64_sized_mem_ref(mem, 8) + ", " + src_reg)
  }
}

///|
fn X64Codegen::emit_load_small_aggregate_return(
  self : X64Codegen,
  ty : @parser.Type,
) -> Unit {
  let classes = match self.aggregate_classes(ty) {
    Some(classes) => classes
    None => abort("x86-64 backend does not support this aggregate return yet")
  }
  let int_regs = ["rax", "rdx"]
  let fp_regs = ["xmm0", "xmm1"]
  let mut int_idx = 0
  let mut fp_idx = 0
  self.emit("\tmov\tr10, rax")
  for word in 0..<classes.length() {
    let width = self.aggregate_word_width(ty, word)
    match classes[word] {
      IntClass => {
        self.emit_load_int_bytes_from_mem_reg(
          int_regs[int_idx],
          "r10",
          word * 8,
          width,
        )
        int_idx += 1
      }
      SseClass => {
        self.emit_load_sse_word_from_mem_reg(
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
fn X64Codegen::emit_store_small_aggregate_return(
  self : X64Codegen,
  ty : @parser.Type,
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
  ty : @parser.Type,
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
  ty : @parser.Type,
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
fn x64_initializer_value(expr : @parser.Expr) -> @parser.Expr {
  match expr {
    DesignatedField(_, e) | DesignatedIndex(_, e) | DesignatedRange(_, _, e) =>
      e
    _ => expr
  }
}

///|
fn X64Codegen::emit_init_scalar_at_addr(
  self : X64Codegen,
  ty : @parser.Type,
  init_expr : @parser.Expr,
) -> Unit {
  let value = x64_initializer_value(init_expr)
  x64_reject_unsupported_scalar(ty)
  self.emit_push_rax()
  self.gen_expr_as_scalar(value, ty)
  self.emit("\tmov\tr10, QWORD PTR [rsp]")
  self.emit("\tadd\trsp, 8")
  self.emit_store_indirect(ty)
}

///|
fn X64Codegen::emit_init_bitfield_at_addr(
  self : X64Codegen,
  field_ty : @parser.Type,
  container_size : Int,
  bit_offset : Int,
  bit_width : Int,
  init_expr : @parser.Expr,
) -> Unit {
  let value = x64_initializer_value(init_expr)
  self.emit_push_rax()
  self.gen_expr_as_scalar(value, field_ty)
  self.emit("\tmov\tr10, QWORD PTR [rsp]")
  self.emit("\tadd\trsp, 8")
  self.emit_store_bitfield_value({
    ty: field_ty,
    size: container_size,
    bit_offset,
    bit_width,
  })
}

///|
fn X64Codegen::emit_init_value_at_addr(
  self : X64Codegen,
  ty : @parser.Type,
  init_expr : @parser.Expr,
) -> Unit {
  let value = x64_initializer_value(init_expr)
  if x64_is_object_aggregate_type(ty) {
    match init_expr {
      DesignatedField(_, inner)
      | DesignatedIndex(_, inner)
      | DesignatedRange(_, _, inner) => {
        if self.designator_matches_type(ty, init_expr) {
          self.emit_init_aggregate_at_addr(ty, [init_expr])
        } else {
          self.emit_init_value_at_addr(ty, inner)
        }
        return
      }
      _ => ()
    }
    match value {
      Array(init_exprs) | CompoundLiteral(_, init_exprs, _) =>
        self.emit_init_aggregate_at_addr(ty, init_exprs)
      Number(0) => self.emit_zero_memory_at_rax(ty)
      Call(_, _) if x64_is_aggregate_type(ty) &&
        self.is_supported_small_aggregate(ty) => {
        self.emit_push_rax()
        self.gen_expr(value)
        self.emit_store_aggregate_call_result_to_pushed_addr(ty)
      }
      _ => {
        self.emit_push_rax()
        self.gen_aggregate_addr(value)
        self.emit("\tmov\tr11, rax")
        self.emit("\tmov\tr10, QWORD PTR [rsp]")
        self.emit("\tadd\trsp, 8")
        self.emit_copy_aggregate_from_addr(ty)
      }
    }
  } else {
    self.emit_init_scalar_at_addr(ty, value)
  }
}

///|
fn X64Codegen::emit_init_aggregate_at_addr(
  self : X64Codegen,
  ty : @parser.Type,
  init_exprs : Array[@parser.Expr],
) -> Unit {
  self.emit_push_rax()
  self.emit_zero_memory_at_rax(ty)
  match x64_core_type(ty) {
    Struct(name) => {
      self.ensure_struct_layout(name)
      let layout = self.struct_layouts[name]
      let mut positional = 0
      for init_expr in init_exprs {
        let field = match init_expr {
          DesignatedField(field_name, _) => {
            let mut found = None
            for i = 0; i < layout.length(); i = i + 1 {
              let f = layout[i]
              if f.0 == field_name {
                found = Some(f)
                positional = i + 1
                break
              }
            }
            found
          }
          _ =>
            if positional < layout.length() {
              let f = layout[positional]
              positional += 1
              Some(f)
            } else {
              None
            }
        }
        match field {
          Some((_, field_ty, field_offset, field_size, bit_offset, bit_width)) => {
            self.emit("\tmov\trax, QWORD PTR [rsp]")
            if field_offset != 0 {
              self.emit("\tadd\trax, " + field_offset.to_string())
            }
            if bit_width > 0 {
              self.emit_init_bitfield_at_addr(
                field_ty, field_size, bit_offset, bit_width, init_expr,
              )
            } else {
              self.emit_init_value_at_addr(field_ty, init_expr)
            }
          }
          None => ()
        }
      }
    }
    Union(name) => {
      self.ensure_struct_layout(name)
      let field = if init_exprs.length() > 0 {
        match init_exprs[0] {
          DesignatedField(field_name, _) => self.field_layout(ty, field_name)
          _ =>
            if self.struct_layouts[name].length() > 0 {
              Some(self.struct_layouts[name][0])
            } else {
              None
            }
        }
      } else {
        None
      }
      match field {
        Some((_, field_ty, field_offset, field_size, bit_offset, bit_width)) =>
          if init_exprs.length() > 0 {
            self.emit("\tmov\trax, QWORD PTR [rsp]")
            if field_offset != 0 {
              self.emit("\tadd\trax, " + field_offset.to_string())
            }
            if bit_width > 0 {
              self.emit_init_bitfield_at_addr(
                field_ty,
                field_size,
                bit_offset,
                bit_width,
                init_exprs[0],
              )
            } else {
              self.emit_init_value_at_addr(field_ty, init_exprs[0])
            }
          }
        None => ()
      }
    }
    Array(elem_ty, n) => {
      let elem_size = self.type_size(elem_ty)
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
          if i >= 0 && i < n {
            self.emit("\tmov\trax, QWORD PTR [rsp]")
            if i * elem_size != 0 {
              self.emit("\tadd\trax, " + (i * elem_size).to_string())
            }
            self.emit_init_value_at_addr(elem_ty, value)
          }
        }
      }
    }
    _ => ()
  }
  self.emit("\tadd\trsp, 8")
}

///|
fn X64Codegen::emit_store_aggregate_call_result_to_pushed_addr(
  self : X64Codegen,
  ty : @parser.Type,
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
  ret_ty : @parser.Type,
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
fn X64Codegen::compute_va_initial_offsets(
  self : X64Codegen,
  params : Array[@parser.Param],
  initial_gp_slots : Int,
) -> (Int, Int, Int) {
  let mut int_idx = initial_gp_slots
  let mut fp_idx = 0
  let mut stack_idx = 0
  for param in params {
    if x64_is_aggregate_type(param.ty) {
      let classes = match self.aggregate_classes(param.ty) {
        Some(classes) => classes
        None => {
          stack_idx = self.align_stack_arg_index(stack_idx, param.ty)
          stack_idx += self.aggregate_word_count(param.ty)
          continue
        }
      }
      let int_needed = x64_class_count(classes, IntClass)
      let fp_needed = x64_class_count(classes, SseClass)
      if int_idx + int_needed <= 6 && fp_idx + fp_needed <= 8 {
        int_idx += int_needed
        fp_idx += fp_needed
      } else {
        stack_idx = self.align_stack_arg_index(stack_idx, param.ty)
        stack_idx += classes.length()
      }
    } else if x64_is_fp_type(param.ty) {
      if fp_idx < 8 {
        fp_idx += 1
      } else {
        stack_idx = self.align_stack_arg_index(stack_idx, param.ty)
        stack_idx += 1
      }
    } else if x64_is_int128_type(param.ty) {
      if int_idx + 2 <= 6 {
        int_idx += 2
      } else {
        stack_idx = self.align_stack_arg_index(stack_idx, param.ty)
        stack_idx += 2
      }
    } else if int_idx < 6 {
      int_idx += 1
    } else {
      stack_idx = self.align_stack_arg_index(stack_idx, param.ty)
      stack_idx += 1
    }
  }
  (int_idx * 8, 48 + fp_idx * 16, 16 + stack_idx * 8)
}

///|
fn X64Codegen::emit_save_variadic_registers(self : X64Codegen) -> Unit {
  if self.va_reg_save_offset < 0 {
    return
  }
  let arg_regs = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
  let fp_arg_regs = [
    "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7",
  ]
  for i = 0; i < arg_regs.length(); i = i + 1 {
    self.emit(
      "\tmov\tQWORD PTR " +
      self.local_neg_ref(self.va_reg_save_offset, i * 8) +
      ", " +
      arg_regs[i],
    )
  }
  for i = 0; i < fp_arg_regs.length(); i = i + 1 {
    self.emit(
      "\tmovups\tXMMWORD PTR " +
      self.local_neg_ref(self.va_reg_save_offset, 48 + i * 16) +
      ", " +
      fp_arg_regs[i],
    )
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
fn X64Codegen::emit_store_va_list_pointer(
  self : X64Codegen,
  dest : @parser.Expr,
  state_offset : Int,
) -> Unit {
  match dest {
    Var(name) =>
      if self.local_offsets.contains(name) {
        self.emit("\tlea\trax, " + self.local_ref(state_offset))
        self.emit(
          "\tmov\tQWORD PTR " +
          self.local_ref(self.local_offsets[name]) +
          ", rax",
        )
      } else {
        self.gen_addr(dest)
        self.emit("\tmov\tr10, rax")
        self.emit("\tlea\trax, " + self.local_ref(state_offset))
        self.emit("\tmov\tQWORD PTR [r10], rax")
      }
    _ => {
      self.gen_addr(dest)
      self.emit("\tmov\tr10, rax")
      self.emit("\tlea\trax, " + self.local_ref(state_offset))
      self.emit("\tmov\tQWORD PTR [r10], rax")
    }
  }
}

///|
fn X64Codegen::emit_va_start(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() == 0 {
    self.emit("\tmov\trax, 0")
    return
  }
  if self.va_reg_save_offset < 0 {
    abort("__builtin_va_start used in non-variadic x86-64 function")
  }
  let state_offset = match args[0] {
    Var(name) => self.ensure_va_list_storage(name)
    _ => abort("x86-64 backend only supports va_start on a va_list variable")
  }
  self.emit(
    "\tmov\tDWORD PTR " +
    self.local_neg_ref(state_offset, 0) +
    ", " +
    self.va_initial_gp_offset.to_string(),
  )
  self.emit(
    "\tmov\tDWORD PTR " +
    self.local_neg_ref(state_offset, 4) +
    ", " +
    self.va_initial_fp_offset.to_string(),
  )
  self.emit(
    "\tlea\trax, [rbp + " + self.va_initial_overflow_offset.to_string() + "]",
  )
  self.emit("\tmov\tQWORD PTR " + self.local_neg_ref(state_offset, 8) + ", rax")
  self.emit("\tlea\trax, " + self.local_ref(self.va_reg_save_offset))
  self.emit(
    "\tmov\tQWORD PTR " + self.local_neg_ref(state_offset, 16) + ", rax",
  )
  self.emit_store_va_list_pointer(args[0], state_offset)
  self.emit("\tmov\trax, 0")
}

///|
fn X64Codegen::emit_va_copy(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() < 2 {
    self.emit("\tmov\trax, 0")
    return
  }
  let dest_offset = match args[0] {
    Var(name) => self.ensure_va_list_storage(name)
    _ => abort("x86-64 backend only supports va_copy to a va_list variable")
  }
  self.gen_expr(args[1])
  self.emit("\tmov\tr10, rax")
  self.emit("\tmov\trax, QWORD PTR [r10]")
  self.emit("\tmov\tQWORD PTR " + self.local_neg_ref(dest_offset, 0) + ", rax")
  self.emit("\tmov\trax, QWORD PTR [r10 + 8]")
  self.emit("\tmov\tQWORD PTR " + self.local_neg_ref(dest_offset, 8) + ", rax")
  self.emit("\tmov\trax, QWORD PTR [r10 + 16]")
  self.emit("\tmov\tQWORD PTR " + self.local_neg_ref(dest_offset, 16) + ", rax")
  self.emit_store_va_list_pointer(args[0], dest_offset)
  self.emit("\tmov\trax, 0")
}

///|
fn x64_first_call_args(
  args : Array[@parser.Expr],
  count : Int,
) -> Array[@parser.Expr] {
  let selected : Array[@parser.Expr] = []
  for i = 0; i < count; i = i + 1 {
    if i < args.length() {
      selected.push(args[i])
    }
  }
  selected
}

///|
fn X64Codegen::emit_builtin_lib_call(
  self : X64Codegen,
  name : String,
  args : Array[@parser.Expr],
  count : Int,
  ret_ty : @parser.Type,
  param_types : Array[@parser.Type],
) -> Unit {
  self.func_rets[name] = ret_ty
  self.func_variadic[name] = false
  self.func_param_counts[name] = param_types.length()
  self.func_param_types[name] = param_types
  self.gen_call(Var(name), x64_first_call_args(args, count))
}

///|
fn x64_selected_call_args(
  args : Array[@parser.Expr],
  fixed_indexes : Array[Int],
  rest_start : Int,
) -> Array[@parser.Expr] {
  let selected : Array[@parser.Expr] = []
  for index in fixed_indexes {
    if index < args.length() {
      selected.push(args[index])
    }
  }
  for i = rest_start; i < args.length(); i = i + 1 {
    selected.push(args[i])
  }
  selected
}

///|
fn X64Codegen::emit_lowered_builtin_call(
  self : X64Codegen,
  name : String,
  args : Array[@parser.Expr],
  fixed_indexes : Array[Int],
  rest_start : Int,
  ret_ty : @parser.Type,
  variadic : Bool,
  param_types : Array[@parser.Type],
) -> Unit {
  self.func_rets[name] = ret_ty
  self.func_variadic[name] = variadic
  self.func_param_counts[name] = param_types.length()
  self.func_param_types[name] = param_types
  self.gen_call(
    Var(name),
    x64_selected_call_args(args, fixed_indexes, rest_start),
  )
}

///|
fn X64Codegen::emit_builtin_first_arg(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Bool {
  if args.length() > 0 {
    self.gen_expr(args[0])
    true
  } else {
    self.emit("\tmov\trax, 0")
    false
  }
}

///|
fn X64Codegen::emit_builtin_clz(
  self : X64Codegen,
  args : Array[@parser.Expr],
  width : Int,
) -> Unit {
  if !self.emit_builtin_first_arg(args) {
    return
  }
  if width == 32 {
    self.emit("\tbsr\tecx, eax")
    self.emit("\tmov\teax, 31")
  } else {
    self.emit("\tbsr\trcx, rax")
    self.emit("\tmov\teax, 63")
  }
  self.emit("\tsub\teax, ecx")
}

///|
fn X64Codegen::emit_builtin_ctz(
  self : X64Codegen,
  args : Array[@parser.Expr],
  width : Int,
) -> Unit {
  if !self.emit_builtin_first_arg(args) {
    return
  }
  if width == 32 {
    self.emit("\tbsf\tecx, eax")
  } else {
    self.emit("\tbsf\trcx, rax")
  }
  self.emit("\tmov\teax, ecx")
}

///|
fn X64Codegen::emit_builtin_ffs(
  self : X64Codegen,
  args : Array[@parser.Expr],
  width : Int,
) -> Unit {
  if !self.emit_builtin_first_arg(args) {
    return
  }
  let zero_label = self.new_label()
  let done_label = self.new_label()
  if width == 32 {
    self.emit("\ttest\teax, eax")
    self.emit("\tje\t" + zero_label)
    self.emit("\tbsf\tecx, eax")
  } else {
    self.emit("\ttest\trax, rax")
    self.emit("\tje\t" + zero_label)
    self.emit("\tbsf\trcx, rax")
  }
  self.emit("\tlea\teax, [rcx + 1]")
  self.emit("\tjmp\t" + done_label)
  self.emit(zero_label + ":")
  self.emit("\tmov\teax, 0")
  self.emit(done_label + ":")
}

///|
fn X64Codegen::emit_builtin_bswap(
  self : X64Codegen,
  args : Array[@parser.Expr],
  width : Int,
) -> Unit {
  if !self.emit_builtin_first_arg(args) {
    return
  }
  if width == 16 {
    self.emit("\trol\tax, 8")
    self.emit("\tmovzx\trax, ax")
  } else if width == 32 {
    self.emit("\tbswap\teax")
    self.emit("\tmov\teax, eax")
  } else {
    self.emit("\tbswap\trax")
  }
}

///|
fn X64Codegen::emit_builtin_rotate(
  self : X64Codegen,
  args : Array[@parser.Expr],
  width : Int,
  left : Bool,
) -> Unit {
  if args.length() < 2 {
    self.emit("\tmov\trax, 0")
    return
  }
  self.gen_expr(args[0])
  self.emit_push_rax()
  self.gen_expr(args[1])
  self.emit("\tmov\trcx, rax")
  self.emit_pop_rax()
  let op = if left { "rol" } else { "ror" }
  if width == 32 {
    self.emit("\t" + op + "\teax, cl")
    self.emit("\tmov\teax, eax")
  } else {
    self.emit("\t" + op + "\trax, cl")
  }
}

///|
fn X64Codegen::generic_builtin_bit_width(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Int {
  if args.length() == 0 {
    return 32
  }
  let width = self.type_size(x64_core_type(self.type_of(args[0]))) * 8
  if width <= 32 {
    32
  } else {
    64
  }
}

///|
fn X64Codegen::generic_builtin_bswap_width(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Int {
  if args.length() == 0 {
    return 32
  }
  let width = self.type_size(x64_core_type(self.type_of(args[0]))) * 8
  if width <= 16 {
    16
  } else if width <= 32 {
    32
  } else {
    64
  }
}

///|
fn X64Codegen::emit_builtin_popcount(
  self : X64Codegen,
  args : Array[@parser.Expr],
  width : Int,
) -> Unit {
  if !self.emit_builtin_first_arg(args) {
    return
  }
  if width == 32 {
    self.emit("\tmov\teax, eax")
  }
  self.emit("\tmov\tr10, rax")
  self.emit("\tshr\tr10, 1")
  self.emit("\tmovabs\tr11, 6148914691236517205")
  self.emit("\tand\tr10, r11")
  self.emit("\tsub\trax, r10")
  self.emit("\tmov\tr10, rax")
  self.emit("\tshr\tr10, 2")
  self.emit("\tmovabs\tr11, 3689348814741910323")
  self.emit("\tand\trax, r11")
  self.emit("\tand\tr10, r11")
  self.emit("\tadd\trax, r10")
  self.emit("\tmov\tr10, rax")
  self.emit("\tshr\tr10, 4")
  self.emit("\tadd\trax, r10")
  self.emit("\tmovabs\tr11, 1085102592571150095")
  self.emit("\tand\trax, r11")
  self.emit("\tmov\tr10, rax")
  self.emit("\tshr\tr10, 8")
  self.emit("\tadd\trax, r10")
  self.emit("\tmov\tr10, rax")
  self.emit("\tshr\tr10, 16")
  self.emit("\tadd\trax, r10")
  self.emit("\tmov\tr10, rax")
  self.emit("\tshr\tr10, 32")
  self.emit("\tadd\trax, r10")
  self.emit("\tand\trax, 127")
}

///|
fn X64Codegen::emit_builtin_parity(
  self : X64Codegen,
  args : Array[@parser.Expr],
  width : Int,
) -> Unit {
  self.emit_builtin_popcount(args, width)
  self.emit("\tand\trax, 1")
}

///|
fn X64Codegen::emit_builtin_alloca(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() > 0 {
    self.gen_expr(args[0])
    self.emit("\tadd\trax, 15")
    self.emit("\tand\trax, -16")
    self.emit("\tsub\trsp, rax")
  }
  self.emit("\tmov\trax, rsp")
}

///|
fn X64Codegen::emit_builtin_is_aligned(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() >= 2 {
    self.gen_expr(args[0])
    self.emit_push_rax()
    self.gen_expr(args[1])
    self.emit("\tmov\tr10, rax")
    self.emit_pop_rax()
    self.emit("\tsub\tr10, 1")
    self.emit("\ttest\trax, r10")
    self.emit_setcc("sete")
  } else {
    self.emit("\tmov\trax, 0")
  }
}

///|
fn X64Codegen::emit_builtin_align_value(
  self : X64Codegen,
  args : Array[@parser.Expr],
  round_up : Bool,
) -> Unit {
  if args.length() >= 2 {
    let result_ty = self.type_of(args[0])
    self.gen_expr(args[0])
    self.emit_push_rax()
    self.gen_expr(args[1])
    self.emit("\tmov\tr10, rax")
    if round_up {
      self.emit("\tmov\tr11, r10")
      self.emit("\tsub\tr11, 1")
    }
    self.emit_pop_rax()
    if round_up {
      self.emit("\tadd\trax, r11")
    }
    self.emit("\tneg\tr10")
    self.emit("\tand\trax, r10")
    if result_ty.is_integer() {
      self.emit_int_conversion_to(result_ty)
    }
  } else {
    self.emit("\tmov\trax, 0")
  }
}

///|
fn X64Codegen::emit_atomic_raw_load_to_rax(
  self : X64Codegen,
  addr_reg : String,
  elem_ty : @parser.Type,
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
  elem_ty : @parser.Type,
) -> Unit {
  let width = self.type_size(elem_ty)
  let mem = x64_atomic_mem_operand(addr_reg, width)
  let reg = x64_atomic_rax_reg(width)
  self.emit("\tmov\t" + mem + ", " + reg)
}

///|
fn X64Codegen::emit_atomic_clean_rax(
  self : X64Codegen,
  elem_ty : @parser.Type,
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
  elem_ty : @parser.Type,
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
fn X64Codegen::emit_atomic_load_builtin(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() > 0 {
    let elem_ty = x64_atomic_target_type(self.type_of(args[0]))
    self.gen_expr(args[0])
    self.emit_load_indirect(elem_ty)
  } else {
    self.emit("\tmov\trax, 0")
  }
}

///|
fn X64Codegen::emit_atomic_load_ptr_builtin(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() >= 2 {
    let elem_ty = x64_atomic_target_type(self.type_of(args[0]))
    self.gen_expr(args[0])
    self.emit_push_rax()
    self.gen_expr(args[1])
    self.emit("\tmov\tr10, rax")
    self.emit("\tpop\trdi")
    self.emit_atomic_raw_load_to_rax("rdi", elem_ty)
    self.emit_atomic_raw_store_from_rax("r10", elem_ty)
  }
  self.emit("\tmov\trax, 0")
}

///|
fn X64Codegen::emit_atomic_store_builtin(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() >= 2 {
    let elem_ty = x64_atomic_target_type(self.type_of(args[0]))
    self.gen_expr(args[0])
    self.emit_push_rax()
    self.gen_expr_as_scalar(args[1], elem_ty)
    self.emit("\tpop\tr10")
    if x64_is_fp_type(elem_ty) {
      self.emit_store_indirect(elem_ty)
    } else {
      let width = self.type_size(elem_ty)
      self.emit(
        "\txchg\t" +
        x64_atomic_mem_operand("r10", width) +
        ", " +
        x64_atomic_rax_reg(width),
      )
    }
  }
  self.emit("\tmov\trax, 0")
}

///|
fn X64Codegen::emit_atomic_store_ptr_builtin(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() >= 2 {
    let elem_ty = x64_atomic_target_type(self.type_of(args[0]))
    let width = self.type_size(elem_ty)
    self.gen_expr(args[0])
    self.emit_push_rax()
    self.gen_expr(args[1])
    self.emit_atomic_raw_load_to_rax("rax", elem_ty)
    self.emit("\tpop\tr10")
    self.emit(
      "\txchg\t" +
      x64_atomic_mem_operand("r10", width) +
      ", " +
      x64_atomic_rax_reg(width),
    )
  }
  self.emit("\tmov\trax, 0")
}

///|
fn X64Codegen::emit_atomic_test_and_set_builtin(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() > 0 {
    self.gen_expr(args[0])
    self.emit("\tmov\tr10, rax")
    self.emit("\tmov\teax, 1")
    self.emit("\txchg\tBYTE PTR [r10], al")
    self.emit("\tcmp\tal, 0")
    self.emit_setcc("setne")
  } else {
    self.emit("\tmov\trax, 0")
  }
}

///|
fn X64Codegen::emit_atomic_clear_builtin(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() > 0 {
    self.gen_expr(args[0])
    self.emit("\tmov\tr10, rax")
    self.emit("\txor\teax, eax")
    self.emit("\txchg\tBYTE PTR [r10], al")
  }
  self.emit("\tmov\trax, 0")
}

///|
fn X64Codegen::emit_atomic_update_builtin(
  self : X64Codegen,
  args : Array[@parser.Expr],
  op : String,
  return_new : Bool,
) -> Unit {
  if args.length() >= 2 {
    let elem_ty = x64_atomic_target_type(self.type_of(args[0]))
    self.gen_expr(args[0])
    self.emit_push_rax()
    self.gen_expr_as_scalar(args[1], elem_ty)
    self.emit("\tmov\tr10, rax")
    self.emit("\tpop\trdi")
    self.emit_atomic_update_loop(op, elem_ty, return_new)
  } else {
    self.emit("\tmov\trax, 0")
  }
}

///|
fn X64Codegen::emit_atomic_exchange_builtin(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() >= 2 {
    let elem_ty = x64_atomic_target_type(self.type_of(args[0]))
    self.gen_expr(args[0])
    self.emit_push_rax()
    self.gen_expr_as_scalar(args[1], elem_ty)
    self.emit("\tpop\tr10")
    if x64_is_fp_type(elem_ty) {
      self.emit("\tsub\trsp, 8")
      match x64_core_type(elem_ty) {
        Float => {
          self.emit("\tmovss\tDWORD PTR [rsp], xmm0")
          self.emit("\tmov\trax, r10")
          self.emit_load_indirect(elem_ty)
          self.emit("\tmovss\txmm1, DWORD PTR [rsp]")
          self.emit("\tmovss\tDWORD PTR [r10], xmm1")
        }
        _ => {
          self.emit("\tmovsd\tQWORD PTR [rsp], xmm0")
          self.emit("\tmov\trax, r10")
          self.emit_load_indirect(elem_ty)
          self.emit("\tmovsd\txmm1, QWORD PTR [rsp]")
          self.emit("\tmovsd\tQWORD PTR [r10], xmm1")
        }
      }
      self.emit("\tadd\trsp, 8")
    } else {
      let width = self.type_size(elem_ty)
      self.emit(
        "\txchg\t" +
        x64_atomic_mem_operand("r10", width) +
        ", " +
        x64_atomic_rax_reg(width),
      )
      self.emit_atomic_clean_rax(elem_ty)
      self.emit_int_conversion_to(elem_ty)
    }
  } else {
    self.emit("\tmov\trax, 0")
  }
}

///|
fn X64Codegen::emit_atomic_exchange_ptr_builtin(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() >= 3 {
    let elem_ty = x64_atomic_target_type(self.type_of(args[0]))
    let width = self.type_size(elem_ty)
    self.gen_expr(args[0])
    self.emit_push_rax()
    self.gen_expr(args[1])
    self.emit_atomic_raw_load_to_rax("rax", elem_ty)
    self.emit_push_rax()
    self.gen_expr(args[2])
    self.emit("\tmov\tr11, rax")
    self.emit_pop_rax()
    self.emit("\tpop\tr10")
    self.emit(
      "\txchg\t" +
      x64_atomic_mem_operand("r10", width) +
      ", " +
      x64_atomic_rax_reg(width),
    )
    self.emit_atomic_raw_store_from_rax("r11", elem_ty)
  }
  self.emit("\tmov\trax, 0")
}

///|
fn X64Codegen::emit_atomic_compare_exchange_builtin(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() >= 3 {
    let elem_ty = x64_atomic_target_type(self.type_of(args[0]))
    let width = self.type_size(elem_ty)
    let fail_label = self.new_label()
    let done_label = self.new_label()
    self.gen_expr(args[0])
    self.emit_push_rax()
    self.gen_expr(args[1])
    self.emit_push_rax()
    self.gen_expr_as_scalar(args[2], elem_ty)
    self.emit("\tmov\tr11, rax")
    self.emit("\tpop\trsi")
    self.emit("\tpop\trdi")
    self.emit_atomic_raw_load_to_rax("rsi", elem_ty)
    self.emit(
      "\tlock cmpxchg\t" +
      x64_atomic_mem_operand("rdi", width) +
      ", " +
      x64_atomic_r11_reg(width),
    )
    self.emit("\tjne\t" + fail_label)
    self.emit("\tmov\trax, 1")
    self.emit("\tjmp\t" + done_label)
    self.emit(fail_label + ":")
    self.emit_atomic_raw_store_from_rax("rsi", elem_ty)
    self.emit("\tmov\trax, 0")
    self.emit(done_label + ":")
  } else {
    self.emit("\tmov\trax, 0")
  }
}

///|
fn X64Codegen::emit_atomic_compare_exchange_ptr_builtin(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() >= 3 {
    let elem_ty = x64_atomic_target_type(self.type_of(args[0]))
    let width = self.type_size(elem_ty)
    let fail_label = self.new_label()
    let done_label = self.new_label()
    self.gen_expr(args[0])
    self.emit_push_rax()
    self.gen_expr(args[1])
    self.emit_push_rax()
    self.gen_expr(args[2])
    self.emit_atomic_raw_load_to_rax("rax", elem_ty)
    self.emit("\tmov\tr11, rax")
    self.emit("\tpop\trsi")
    self.emit("\tpop\trdi")
    self.emit_atomic_raw_load_to_rax("rsi", elem_ty)
    self.emit(
      "\tlock cmpxchg\t" +
      x64_atomic_mem_operand("rdi", width) +
      ", " +
      x64_atomic_r11_reg(width),
    )
    self.emit("\tjne\t" + fail_label)
    self.emit("\tmov\trax, 1")
    self.emit("\tjmp\t" + done_label)
    self.emit(fail_label + ":")
    self.emit_atomic_raw_store_from_rax("rsi", elem_ty)
    self.emit("\tmov\trax, 0")
    self.emit(done_label + ":")
  } else {
    self.emit("\tmov\trax, 0")
  }
}

///|
fn X64Codegen::emit_sync_compare_and_swap_builtin(
  self : X64Codegen,
  args : Array[@parser.Expr],
  return_old : Bool,
) -> Unit {
  if args.length() >= 3 {
    let elem_ty = x64_atomic_target_type(self.type_of(args[0]))
    let width = self.type_size(elem_ty)
    self.gen_expr(args[0])
    self.emit_push_rax()
    self.gen_expr_as_scalar(args[1], elem_ty)
    self.emit_push_rax()
    self.gen_expr_as_scalar(args[2], elem_ty)
    self.emit("\tmov\tr11, rax")
    self.emit_pop_rax()
    self.emit("\tpop\trdi")
    self.emit(
      "\tlock cmpxchg\t" +
      x64_atomic_mem_operand("rdi", width) +
      ", " +
      x64_atomic_r11_reg(width),
    )
    if return_old {
      self.emit_atomic_clean_rax(elem_ty)
      self.emit_int_conversion_to(elem_ty)
    } else {
      self.emit_setcc("sete")
    }
  } else {
    self.emit("\tmov\trax, 0")
  }
}

///|
fn X64Codegen::emit_sync_lock_release_builtin(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() > 0 {
    let elem_ty = x64_atomic_target_type(self.type_of(args[0]))
    self.gen_expr(args[0])
    self.emit("\tmov\tr10, rax")
    self.emit("\txor\teax, eax")
    self.emit_atomic_raw_store_from_rax("r10", elem_ty)
  }
  self.emit("\tmov\trax, 0")
}

///|
fn X64Codegen::emit_atomic_lock_free_builtin(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> Unit {
  if args.length() > 0 {
    self.gen_expr(args[0])
    self.emit("\tmov\tr10, rax")
    self.emit("\tcmp\tr10, 1")
    self.emit("\tsete\tal")
    self.emit("\tcmp\tr10, 2")
    self.emit("\tsete\tr11b")
    self.emit("\tor\tal, r11b")
    self.emit("\tcmp\tr10, 4")
    self.emit("\tsete\tr11b")
    self.emit("\tor\tal, r11b")
    self.emit("\tcmp\tr10, 8")
    self.emit("\tsete\tr11b")
    self.emit("\tor\tal, r11b")
    self.emit("\tmovzx\teax, al")
  } else {
    self.emit("\tmov\trax, 0")
  }
}

///|
fn X64Codegen::overflow_result_type(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> @parser.Type {
  if args.length() >= 3 {
    match x64_pointer_element(self.type_of(args[2])) {
      Some(ty) => x64_core_type(ty)
      None => SLongLong
    }
  } else {
    SLongLong
  }
}

///|
fn X64Codegen::emit_overflow_arithmetic_builtin(
  self : X64Codegen,
  args : Array[@parser.Expr],
  op : String,
) -> Unit {
  if args.length() < 3 {
    self.emit("\tmov\trax, 0")
    return
  }
  let result_ty = self.overflow_result_type(args)
  if !result_ty.is_integer() || x64_is_int128_type(result_ty) {
    abort(
      "unsupported x86-64 overflow builtin result type: " +
      result_ty.to_string(),
    )
  }
  let width = self.type_size(result_ty)
  self.gen_expr(args[2])
  self.emit_push_rax()
  self.gen_expr_as_scalar(args[0], result_ty)
  self.emit_push_rax()
  self.gen_expr_as_scalar(args[1], result_ty)
  self.emit("\tmov\tr10, rax")
  self.emit_pop_rax()
  let rhs_reg = x64_atomic_r10_reg(width)
  let lhs_reg = x64_sized_reg(width)
  match op {
    "+" => self.emit("\tadd\t" + lhs_reg + ", " + rhs_reg)
    "-" => self.emit("\tsub\t" + lhs_reg + ", " + rhs_reg)
    "*" =>
      if is_unsigned_integer_type(result_ty) {
        self.emit("\tmul\t" + rhs_reg)
      } else {
        self.emit("\timul\t" + rhs_reg)
      }
    _ => abort("unsupported x86-64 overflow builtin operator: " + op)
  }
  let cc = if is_unsigned_integer_type(result_ty) && (op == "+" || op == "-") {
    "setb"
  } else {
    "seto"
  }
  self.emit("\t" + cc + "\tr11b")
  self.emit("\tpop\tr10")
  self.emit_store_indirect(result_ty)
  self.emit("\tmovzx\teax, r11b")
}

///|
fn X64Codegen::emit_builtin_fabs(
  self : X64Codegen,
  args : Array[@parser.Expr],
  ty : @parser.Type,
) -> Unit {
  if args.length() > 0 {
    self.gen_expr_as_fp(args[0], ty)
    match x64_core_type(ty) {
      Float => {
        self.emit("\tmov\teax, 2147483647")
        self.emit("\tmovd\txmm1, eax")
        self.emit("\tandps\txmm0, xmm1")
      }
      _ => {
        self.emit("\tmovabs\trax, 9223372036854775807")
        self.emit("\tmovq\txmm1, rax")
        self.emit("\tandpd\txmm0, xmm1")
      }
    }
  } else {
    self.emit("\tpxor\txmm0, xmm0")
  }
}

///|
fn X64Codegen::emit_builtin_copysign(
  self : X64Codegen,
  args : Array[@parser.Expr],
  ty : @parser.Type,
) -> Unit {
  if args.length() < 2 {
    self.emit("\tpxor\txmm0, xmm0")
    return
  }
  self.gen_expr_as_fp(args[0], ty)
  match x64_core_type(ty) {
    Float => {
      self.emit("\tmovd\tr11d, xmm0")
      self.emit("\tand\tr11d, 2147483647")
      self.gen_expr_as_fp(args[1], ty)
      self.emit("\tmovd\teax, xmm0")
      self.emit("\tand\teax, -2147483648")
      self.emit("\tor\teax, r11d")
      self.emit("\tmovd\txmm0, eax")
    }
    _ => {
      self.emit("\tmovq\tr11, xmm0")
      self.emit("\tmovabs\tr10, 9223372036854775807")
      self.emit("\tand\tr11, r10")
      self.gen_expr_as_fp(args[1], ty)
      self.emit("\tmovq\trax, xmm0")
      self.emit("\tmovabs\tr10, -9223372036854775808")
      self.emit("\tand\trax, r10")
      self.emit("\tor\trax, r11")
      self.emit("\tmovq\txmm0, rax")
    }
  }
}

///|
fn X64Codegen::emit_builtin_sqrt(
  self : X64Codegen,
  args : Array[@parser.Expr],
  ty : @parser.Type,
) -> Unit {
  if args.length() > 0 {
    self.gen_expr_as_fp(args[0], ty)
    self.emit("\tsqrt" + x64_fp_suffix(ty) + "\txmm0, xmm0")
  } else {
    self.emit("\tpxor\txmm0, xmm0")
  }
}

///|
fn X64Codegen::emit_builtin_abs(
  self : X64Codegen,
  args : Array[@parser.Expr],
  ty : @parser.Type,
) -> Unit {
  if args.length() > 0 {
    self.gen_expr_as_scalar(args[0], ty)
    let width = self.type_size(ty)
    let reg = x64_sized_reg(width)
    let done = self.new_label()
    self.emit("\tcmp\t" + reg + ", 0")
    self.emit("\tjge\t" + done)
    self.emit("\tneg\t" + reg)
    self.emit(done + ":")
    self.emit_int_conversion_to(ty)
  } else {
    self.emit("\tmov\trax, 0")
  }
}

///|
fn X64Codegen::emit_builtin_fp_bits(
  self : X64Codegen,
  bits : Int64,
  ty : @parser.Type,
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
fn X64Codegen::emit_builtin_fp_compare(
  self : X64Codegen,
  args : Array[@parser.Expr],
  op : String,
) -> Unit {
  if args.length() < 2 {
    self.emit("\tmov\trax, 0")
    return
  }
  let lhs_ty = self.type_of(args[0])
  let rhs_ty = self.type_of(args[1])
  let cmp_ty : @parser.Type = if x64_core_type(lhs_ty) == Double ||
    x64_core_type(rhs_ty) == Double {
    Double
  } else {
    Float
  }
  let suffix = x64_fp_suffix(cmp_ty)
  let spill = if x64_core_type(cmp_ty) == Float {
    "DWORD PTR [rsp]"
  } else {
    "QWORD PTR [rsp]"
  }
  self.gen_expr_as_fp(args[0], cmp_ty)
  self.emit("\tsub\trsp, 8")
  self.emit("\tmov" + suffix + "\t" + spill + ", xmm0")
  self.gen_expr_as_fp(args[1], cmp_ty)
  self.emit("\tmovapd\txmm1, xmm0")
  self.emit("\tmov" + suffix + "\txmm0, " + spill)
  self.emit("\tadd\trsp, 8")
  self.emit("\tucomi" + suffix + "\txmm0, xmm1")
  self.emit_fp_compare_result(op)
}

///|
fn X64Codegen::builtin_unary_fp_type(
  self : X64Codegen,
  args : Array[@parser.Expr],
) -> @parser.Type {
  if args.length() > 0 && x64_core_type(self.type_of(args[0])) == Float {
    Float
  } else {
    Double
  }
}

///|
fn X64Codegen::emit_builtin_fp_class_as(
  self : X64Codegen,
  args : Array[@parser.Expr],
  op : String,
  ty : @parser.Type,
) -> Unit {
  if args.length() == 0 {
    self.emit("\tmov\trax, 0")
    return
  }
  self.gen_expr_as_fp(args[0], ty)
  match op {
    "isnan" => {
      self.emit("\tucomi" + x64_fp_suffix(ty) + "\txmm0, xmm0")
      self.emit_setcc("setp")
    }
    "isinf" => {
      self.emit_fp_abs_bits_in_rax(ty)
      match x64_core_type(ty) {
        Float => self.emit("\tcmp\teax, 2139095040")
        _ => {
          self.emit("\tmovabs\tr10, 9218868437227405312")
          self.emit("\tcmp\trax, r10")
        }
      }
      self.emit_setcc("sete")
    }
    "isfinite" => {
      self.emit_fp_abs_bits_in_rax(ty)
      match x64_core_type(ty) {
        Float => self.emit("\tcmp\teax, 2139095040")
        _ => {
          self.emit("\tmovabs\tr10, 9218868437227405312")
          self.emit("\tcmp\trax, r10")
        }
      }
      self.emit_setcc("setb")
    }
    "isnormal" => {
      self.emit_fp_abs_bits_in_rax(ty)
      match x64_core_type(ty) {
        Float => {
          self.emit("\tmov\tr10d, eax")
          self.emit("\tcmp\tr10d, 8388608")
          self.emit("\tsetae\tal")
          self.emit("\tcmp\tr10d, 2139095040")
          self.emit("\tsetb\tr11b")
        }
        _ => {
          self.emit("\tmov\tr10, rax")
          self.emit("\tmovabs\tr11, 4503599627370496")
          self.emit("\tcmp\tr10, r11")
          self.emit("\tsetae\tal")
          self.emit("\tmovabs\tr11, 9218868437227405312")
          self.emit("\tcmp\tr10, r11")
          self.emit("\tsetb\tr11b")
        }
      }
      self.emit("\tand\tal, r11b")
      self.emit("\tmovzx\trax, al")
    }
    "signbit" =>
      match x64_core_type(ty) {
        Float => {
          self.emit("\tmovd\teax, xmm0")
          self.emit("\tshr\teax, 31")
        }
        _ => {
          self.emit("\tmovq\trax, xmm0")
          self.emit("\tshr\trax, 63")
        }
      }
    _ => self.emit("\tmov\trax, 0")
  }
}

///|
fn X64Codegen::emit_fp_abs_bits_in_rax(
  self : X64Codegen,
  ty : @parser.Type,
) -> Unit {
  match x64_core_type(ty) {
    Float => {
      self.emit("\tmovd\teax, xmm0")
      self.emit("\tand\teax, 2147483647")
    }
    _ => {
      self.emit("\tmovq\trax, xmm0")
      self.emit("\tmovabs\tr10, 9223372036854775807")
      self.emit("\tand\trax, r10")
    }
  }
}

///|
fn X64Codegen::emit_builtin_fp_class(
  self : X64Codegen,
  args : Array[@parser.Expr],
  op : String,
) -> Unit {
  self.emit_builtin_fp_class_as(args, op, self.builtin_unary_fp_type(args))
}

///|
fn X64Codegen::builtin_return_type(
  self : X64Codegen,
  name : String,
  args : Array[@parser.Expr],
) -> @parser.Type? {
  match name {
    "__builtin_expect"
    | "__builtin_expect_with_probability"
    | "__builtin_unpredictable" =>
      if args.length() > 0 {
        Some(self.type_of(args[0]))
      } else {
        Some(SInt)
      }
    "__builtin_assume_aligned" =>
      if args.length() > 0 {
        Some(self.type_of(args[0]))
      } else {
        Some(Pointer(Void))
      }
    "__builtin_constant_p" => Some(SInt)
    "__builtin_is_aligned" => Some(Bool)
    "__builtin_align_up" | "__builtin_align_down" =>
      if args.length() > 0 {
        Some(self.type_of(args[0]))
      } else {
        Some(ULong)
      }
    "__builtin_object_size" | "__builtin_dynamic_object_size" => Some(ULong)
    "__builtin_frame_address"
    | "__builtin_return_address"
    | "__builtin_extract_return_addr"
    | "__builtin_frob_return_addr" => Some(Pointer(Void))
    "__builtin_alloca" => Some(Pointer(Void))
    "__builtin_flt_rounds" => Some(SInt)
    "__builtin_fabsf"
    | "__builtin_copysignf"
    | "__builtin_sqrtf"
    | "__builtin_nanf"
    | "__builtin_huge_valf"
    | "__builtin_inff" => Some(Float)
    "__builtin_fabs"
    | "__builtin_fabsl"
    | "__builtin_copysign"
    | "__builtin_copysignl"
    | "__builtin_sqrt"
    | "__builtin_sqrtl"
    | "__builtin_nan"
    | "__builtin_nanl"
    | "__builtin_huge_val"
    | "__builtin_huge_vall"
    | "__builtin_inf"
    | "__builtin_infl" => Some(Double)
    "__builtin_isgreater"
    | "__builtin_isgreaterequal"
    | "__builtin_isless"
    | "__builtin_islessequal"
    | "__builtin_islessgreater"
    | "__builtin_isunordered"
    | "__builtin_isnan"
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
    | "__builtin_signbitl" => Some(SInt)
    "__builtin_abs" => Some(SInt)
    "__builtin_labs" => Some(SLong)
    "__builtin_llabs" => Some(SLongLong)
    "__builtin_add_overflow"
    | "__builtin_sub_overflow"
    | "__builtin_mul_overflow"
    | "__builtin_sadd_overflow"
    | "__builtin_saddl_overflow"
    | "__builtin_saddll_overflow"
    | "__builtin_uadd_overflow"
    | "__builtin_uaddl_overflow"
    | "__builtin_uaddll_overflow"
    | "__builtin_ssub_overflow"
    | "__builtin_ssubl_overflow"
    | "__builtin_ssubll_overflow"
    | "__builtin_usub_overflow"
    | "__builtin_usubl_overflow"
    | "__builtin_usubll_overflow"
    | "__builtin_smul_overflow"
    | "__builtin_smull_overflow"
    | "__builtin_smulll_overflow"
    | "__builtin_umul_overflow"
    | "__builtin_umull_overflow"
    | "__builtin_umulll_overflow" => Some(Bool)
    "__atomic_load_n" | "__c11_atomic_load" =>
      if args.length() > 0 {
        Some(x64_atomic_target_type(self.type_of(args[0])))
      } else {
        Some(SLongLong)
      }
    "__atomic_add_fetch"
    | "__atomic_sub_fetch"
    | "__atomic_and_fetch"
    | "__atomic_or_fetch"
    | "__atomic_xor_fetch"
    | "__atomic_nand_fetch"
    | "__atomic_fetch_add"
    | "__atomic_fetch_sub"
    | "__atomic_fetch_and"
    | "__atomic_fetch_or"
    | "__atomic_fetch_xor"
    | "__atomic_fetch_nand"
    | "__atomic_exchange_n"
    | "__c11_atomic_fetch_add"
    | "__c11_atomic_fetch_sub"
    | "__c11_atomic_fetch_and"
    | "__c11_atomic_fetch_or"
    | "__c11_atomic_fetch_xor"
    | "__c11_atomic_exchange" =>
      if args.length() > 0 {
        Some(x64_atomic_target_type(self.type_of(args[0])))
      } else {
        Some(SLongLong)
      }
    "__atomic_test_and_set" => Some(Bool)
    "__atomic_compare_exchange"
    | "__atomic_compare_exchange_n"
    | "__c11_atomic_compare_exchange_strong"
    | "__c11_atomic_compare_exchange_weak"
    | "__sync_bool_compare_and_swap"
    | "__atomic_always_lock_free"
    | "__atomic_is_lock_free"
    | "__c11_atomic_is_lock_free" => Some(Bool)
    "__sync_val_compare_and_swap" =>
      if args.length() > 0 {
        Some(x64_atomic_target_type(self.type_of(args[0])))
      } else {
        Some(SLongLong)
      }
    "__sync_fetch_and_add"
    | "__sync_fetch_and_sub"
    | "__sync_fetch_and_and"
    | "__sync_fetch_and_or"
    | "__sync_fetch_and_xor"
    | "__sync_fetch_and_nand"
    | "__sync_fetch_and_max"
    | "__sync_fetch_and_min"
    | "__sync_fetch_and_umax"
    | "__sync_fetch_and_umin"
    | "__sync_add_and_fetch"
    | "__sync_sub_and_fetch"
    | "__sync_and_and_fetch"
    | "__sync_or_and_fetch"
    | "__sync_xor_and_fetch"
    | "__sync_nand_and_fetch"
    | "__sync_swap"
    | "__sync_lock_test_and_set" =>
      if args.length() > 0 {
        Some(x64_atomic_target_type(self.type_of(args[0])))
      } else {
        Some(SLongLong)
      }
    "__sync_lock_release" => Some(Void)
    "__builtin_clz"
    | "__builtin_clzl"
    | "__builtin_clzll"
    | "__builtin_ctz"
    | "__builtin_ctzl"
    | "__builtin_ctzll"
    | "__builtin_ffs"
    | "__builtin_ffsl"
    | "__builtin_ffsll"
    | "__builtin_parity"
    | "__builtin_parityl"
    | "__builtin_parityll"
    | "__builtin_popcount"
    | "__builtin_popcountl"
    | "__builtin_popcountll" => Some(SInt)
    "__builtin_bswap" | "__builtin_rotateleft" | "__builtin_rotateright" =>
      if args.length() > 0 {
        Some(self.type_of(args[0]))
      } else {
        Some(UInt)
      }
    "__builtin_bswap16" => Some(UShort)
    "__builtin_bswap32"
    | "__builtin_rotateleft32"
    | "__builtin_rotateright32" => Some(UInt)
    "__builtin_bswap64"
    | "__builtin_rotateleft64"
    | "__builtin_rotateright64" => Some(ULongLong)
    "__builtin_unreachable"
    | "__builtin_trap"
    | "__builtin_assume"
    | "__builtin_prefetch"
    | "__atomic_clear"
    | "__atomic_exchange"
    | "__atomic_load"
    | "__atomic_store"
    | "__atomic_store_n"
    | "__atomic_thread_fence"
    | "__atomic_signal_fence"
    | "__c11_atomic_store"
    | "__c11_atomic_thread_fence"
    | "__c11_atomic_signal_fence"
    | "__sync_synchronize"
    | "__builtin_va_start"
    | "__builtin_va_end"
    | "__builtin_va_copy"
    | "__builtin_bzero" => Some(Void)
    "__builtin_memcpy"
    | "__builtin___memcpy_chk"
    | "__builtin_mempcpy"
    | "__builtin___mempcpy_chk"
    | "__builtin_memmove"
    | "__builtin___memmove_chk"
    | "__builtin_memset"
    | "__builtin___memset_chk" => Some(Pointer(Void))
    "__builtin_strlen" => Some(ULong)
    "__builtin_memcmp" | "__builtin_strcmp" | "__builtin_strncmp" => Some(SInt)
    "__builtin_memchr" => Some(Pointer(Void))
    "__builtin_strcpy"
    | "__builtin___strcpy_chk"
    | "__builtin_strcat"
    | "__builtin___strcat_chk"
    | "__builtin_stpcpy"
    | "__builtin___stpcpy_chk"
    | "__builtin_strncpy"
    | "__builtin___strncpy_chk"
    | "__builtin_stpncpy"
    | "__builtin___stpncpy_chk"
    | "__builtin_strncat"
    | "__builtin___strncat_chk"
    | "__builtin_strchr"
    | "__builtin_strrchr"
    | "__builtin_strstr" => Some(Pointer(SChar))
    "__builtin___strlcpy_chk" | "__builtin___strlcat_chk" => Some(ULong)
    "__builtin___snprintf_chk"
    | "__builtin___vsnprintf_chk"
    | "__builtin___sprintf_chk"
    | "__builtin___vsprintf_chk"
    | "__builtin___printf_chk"
    | "__builtin___fprintf_chk"
    | "__builtin___vfprintf_chk" => Some(SInt)
    _ => None
  }
}

///|
fn X64Codegen::emit_builtin_call(
  self : X64Codegen,
  name : String,
  args : Array[@parser.Expr],
) -> Bool {
  match name {
    "__builtin_expect"
    | "__builtin_expect_with_probability"
    | "__builtin_unpredictable" => {
      if args.length() > 0 {
        self.gen_expr(args[0])
      } else {
        self.emit("\tmov\trax, 0")
      }
      true
    }
    "__builtin_assume_aligned" => {
      if args.length() > 0 {
        self.gen_expr(args[0])
      } else {
        self.emit("\tmov\trax, 0")
      }
      true
    }
    "__builtin_unreachable" | "__builtin_trap" => {
      self.emit("\tud2")
      true
    }
    "__builtin_frame_address" => {
      if args.length() > 0 {
        match args[0] {
          Number(0L) => self.emit("\tmov\trax, rbp")
          _ => self.emit("\tmov\trax, 0")
        }
      } else {
        self.emit("\tmov\trax, rbp")
      }
      true
    }
    "__builtin_return_address" => {
      if args.length() > 0 {
        match args[0] {
          Number(0L) => self.emit("\tmov\trax, QWORD PTR [rbp + 8]")
          _ => self.emit("\tmov\trax, 0")
        }
      } else {
        self.emit("\tmov\trax, QWORD PTR [rbp + 8]")
      }
      true
    }
    "__builtin_extract_return_addr" | "__builtin_frob_return_addr" => {
      if args.length() > 0 {
        self.gen_expr(args[0])
      } else {
        self.emit("\tmov\trax, 0")
      }
      true
    }
    "__builtin_assume" | "__builtin_prefetch" => {
      self.emit("\tmov\trax, 0")
      true
    }
    "__builtin_constant_p" => {
      self.emit("\tmov\trax, 0")
      true
    }
    "__builtin_flt_rounds" => {
      self.emit("\tmov\trax, 1")
      true
    }
    "__builtin_is_aligned" => {
      self.emit_builtin_is_aligned(args)
      true
    }
    "__builtin_align_up" => {
      self.emit_builtin_align_value(args, true)
      true
    }
    "__builtin_align_down" => {
      self.emit_builtin_align_value(args, false)
      true
    }
    "__builtin_object_size" | "__builtin_dynamic_object_size" => {
      self.emit("\tmov\trax, -1")
      true
    }
    "__builtin_alloca" => {
      self.emit_builtin_alloca(args)
      true
    }
    "__atomic_load" => {
      self.emit_atomic_load_ptr_builtin(args)
      true
    }
    "__atomic_load_n" | "__c11_atomic_load" => {
      self.emit_atomic_load_builtin(args)
      true
    }
    "__atomic_store" => {
      self.emit_atomic_store_ptr_builtin(args)
      true
    }
    "__atomic_store_n" | "__c11_atomic_store" => {
      self.emit_atomic_store_builtin(args)
      true
    }
    "__atomic_test_and_set" => {
      self.emit_atomic_test_and_set_builtin(args)
      true
    }
    "__atomic_clear" => {
      self.emit_atomic_clear_builtin(args)
      true
    }
    "__atomic_add_fetch" => {
      self.emit_atomic_update_builtin(args, "+", true)
      true
    }
    "__atomic_sub_fetch" => {
      self.emit_atomic_update_builtin(args, "-", true)
      true
    }
    "__atomic_and_fetch" => {
      self.emit_atomic_update_builtin(args, "&", true)
      true
    }
    "__atomic_or_fetch" => {
      self.emit_atomic_update_builtin(args, "|", true)
      true
    }
    "__atomic_xor_fetch" => {
      self.emit_atomic_update_builtin(args, "^", true)
      true
    }
    "__atomic_nand_fetch" => {
      self.emit_atomic_update_builtin(args, "~&", true)
      true
    }
    "__atomic_fetch_add" | "__c11_atomic_fetch_add" => {
      self.emit_atomic_update_builtin(args, "+", false)
      true
    }
    "__atomic_fetch_sub" | "__c11_atomic_fetch_sub" => {
      self.emit_atomic_update_builtin(args, "-", false)
      true
    }
    "__atomic_fetch_and" | "__c11_atomic_fetch_and" => {
      self.emit_atomic_update_builtin(args, "&", false)
      true
    }
    "__atomic_fetch_or" | "__c11_atomic_fetch_or" => {
      self.emit_atomic_update_builtin(args, "|", false)
      true
    }
    "__atomic_fetch_xor" | "__c11_atomic_fetch_xor" => {
      self.emit_atomic_update_builtin(args, "^", false)
      true
    }
    "__atomic_fetch_nand" => {
      self.emit_atomic_update_builtin(args, "~&", false)
      true
    }
    "__atomic_exchange" => {
      self.emit_atomic_exchange_ptr_builtin(args)
      true
    }
    "__atomic_exchange_n" | "__c11_atomic_exchange" => {
      self.emit_atomic_exchange_builtin(args)
      true
    }
    "__atomic_compare_exchange" => {
      self.emit_atomic_compare_exchange_ptr_builtin(args)
      true
    }
    "__atomic_compare_exchange_n"
    | "__c11_atomic_compare_exchange_strong"
    | "__c11_atomic_compare_exchange_weak" => {
      self.emit_atomic_compare_exchange_builtin(args)
      true
    }
    "__atomic_thread_fence" | "__c11_atomic_thread_fence" => {
      self.emit("\tmfence")
      self.emit("\tmov\trax, 0")
      true
    }
    "__atomic_signal_fence" | "__c11_atomic_signal_fence" => {
      self.emit("\tmov\trax, 0")
      true
    }
    "__atomic_always_lock_free"
    | "__atomic_is_lock_free"
    | "__c11_atomic_is_lock_free" => {
      self.emit_atomic_lock_free_builtin(args)
      true
    }
    "__sync_bool_compare_and_swap" => {
      self.emit_sync_compare_and_swap_builtin(args, false)
      true
    }
    "__sync_val_compare_and_swap" => {
      self.emit_sync_compare_and_swap_builtin(args, true)
      true
    }
    "__sync_fetch_and_add" => {
      self.emit_atomic_update_builtin(args, "+", false)
      true
    }
    "__sync_fetch_and_sub" => {
      self.emit_atomic_update_builtin(args, "-", false)
      true
    }
    "__sync_fetch_and_and" => {
      self.emit_atomic_update_builtin(args, "&", false)
      true
    }
    "__sync_fetch_and_or" => {
      self.emit_atomic_update_builtin(args, "|", false)
      true
    }
    "__sync_fetch_and_xor" => {
      self.emit_atomic_update_builtin(args, "^", false)
      true
    }
    "__sync_fetch_and_nand" => {
      self.emit_atomic_update_builtin(args, "~&", false)
      true
    }
    "__sync_fetch_and_max" => {
      self.emit_atomic_update_builtin(args, "max", false)
      true
    }
    "__sync_fetch_and_min" => {
      self.emit_atomic_update_builtin(args, "min", false)
      true
    }
    "__sync_fetch_and_umax" => {
      self.emit_atomic_update_builtin(args, "umax", false)
      true
    }
    "__sync_fetch_and_umin" => {
      self.emit_atomic_update_builtin(args, "umin", false)
      true
    }
    "__sync_add_and_fetch" => {
      self.emit_atomic_update_builtin(args, "+", true)
      true
    }
    "__sync_sub_and_fetch" => {
      self.emit_atomic_update_builtin(args, "-", true)
      true
    }
    "__sync_and_and_fetch" => {
      self.emit_atomic_update_builtin(args, "&", true)
      true
    }
    "__sync_or_and_fetch" => {
      self.emit_atomic_update_builtin(args, "|", true)
      true
    }
    "__sync_xor_and_fetch" => {
      self.emit_atomic_update_builtin(args, "^", true)
      true
    }
    "__sync_nand_and_fetch" => {
      self.emit_atomic_update_builtin(args, "~&", true)
      true
    }
    "__sync_swap" | "__sync_lock_test_and_set" => {
      self.emit_atomic_exchange_builtin(args)
      true
    }
    "__sync_lock_release" => {
      self.emit_sync_lock_release_builtin(args)
      true
    }
    "__builtin_add_overflow"
    | "__builtin_sadd_overflow"
    | "__builtin_saddl_overflow"
    | "__builtin_saddll_overflow"
    | "__builtin_uadd_overflow"
    | "__builtin_uaddl_overflow"
    | "__builtin_uaddll_overflow" => {
      self.emit_overflow_arithmetic_builtin(args, "+")
      true
    }
    "__builtin_sub_overflow"
    | "__builtin_ssub_overflow"
    | "__builtin_ssubl_overflow"
    | "__builtin_ssubll_overflow"
    | "__builtin_usub_overflow"
    | "__builtin_usubl_overflow"
    | "__builtin_usubll_overflow" => {
      self.emit_overflow_arithmetic_builtin(args, "-")
      true
    }
    "__builtin_mul_overflow"
    | "__builtin_smul_overflow"
    | "__builtin_smull_overflow"
    | "__builtin_smulll_overflow"
    | "__builtin_umul_overflow"
    | "__builtin_umull_overflow"
    | "__builtin_umulll_overflow" => {
      self.emit_overflow_arithmetic_builtin(args, "*")
      true
    }
    "__sync_synchronize" => {
      self.emit("\tmfence")
      self.emit("\tmov\trax, 0")
      true
    }
    "__builtin_fabs" | "__builtin_fabsl" => {
      self.emit_builtin_fabs(args, Double)
      true
    }
    "__builtin_fabsf" => {
      self.emit_builtin_fabs(args, Float)
      true
    }
    "__builtin_copysign" | "__builtin_copysignl" => {
      self.emit_builtin_copysign(args, Double)
      true
    }
    "__builtin_copysignf" => {
      self.emit_builtin_copysign(args, Float)
      true
    }
    "__builtin_sqrt" | "__builtin_sqrtl" => {
      self.emit_builtin_sqrt(args, Double)
      true
    }
    "__builtin_sqrtf" => {
      self.emit_builtin_sqrt(args, Float)
      true
    }
    "__builtin_abs" => {
      self.emit_builtin_abs(args, SInt)
      true
    }
    "__builtin_labs" => {
      self.emit_builtin_abs(args, SLong)
      true
    }
    "__builtin_llabs" => {
      self.emit_builtin_abs(args, SLongLong)
      true
    }
    "__builtin_nan" | "__builtin_nanl" => {
      self.emit_builtin_fp_bits(9221120237041090560L, Double)
      true
    }
    "__builtin_nanf" => {
      self.emit_builtin_fp_bits(2143289344L, Float)
      true
    }
    "__builtin_huge_val"
    | "__builtin_huge_vall"
    | "__builtin_inf"
    | "__builtin_infl" => {
      self.emit_builtin_fp_bits(9218868437227405312L, Double)
      true
    }
    "__builtin_huge_valf" | "__builtin_inff" => {
      self.emit_builtin_fp_bits(2139095040L, Float)
      true
    }
    "__builtin_isgreater" => {
      self.emit_builtin_fp_compare(args, ">")
      true
    }
    "__builtin_isgreaterequal" => {
      self.emit_builtin_fp_compare(args, ">=")
      true
    }
    "__builtin_isless" => {
      self.emit_builtin_fp_compare(args, "<")
      true
    }
    "__builtin_islessequal" => {
      self.emit_builtin_fp_compare(args, "<=")
      true
    }
    "__builtin_islessgreater" => {
      self.emit_builtin_fp_compare(args, "<>")
      true
    }
    "__builtin_isunordered" => {
      self.emit_builtin_fp_compare(args, "unordered")
      true
    }
    "__builtin_isnan" | "__builtin_isnanl" => {
      self.emit_builtin_fp_class(args, "isnan")
      true
    }
    "__builtin_isnanf" => {
      self.emit_builtin_fp_class_as(args, "isnan", Float)
      true
    }
    "__builtin_isinf" | "__builtin_isinfl" => {
      self.emit_builtin_fp_class(args, "isinf")
      true
    }
    "__builtin_isinff" => {
      self.emit_builtin_fp_class_as(args, "isinf", Float)
      true
    }
    "__builtin_isfinite" | "__builtin_isfinitel" => {
      self.emit_builtin_fp_class(args, "isfinite")
      true
    }
    "__builtin_isfinitef" => {
      self.emit_builtin_fp_class_as(args, "isfinite", Float)
      true
    }
    "__builtin_isnormal" | "__builtin_isnormall" => {
      self.emit_builtin_fp_class(args, "isnormal")
      true
    }
    "__builtin_isnormalf" => {
      self.emit_builtin_fp_class_as(args, "isnormal", Float)
      true
    }
    "__builtin_signbit" | "__builtin_signbitl" => {
      self.emit_builtin_fp_class(args, "signbit")
      true
    }
    "__builtin_signbitf" => {
      self.emit_builtin_fp_class_as(args, "signbit", Float)
      true
    }
    "__builtin_clz" => {
      self.emit_builtin_clz(args, 32)
      true
    }
    "__builtin_clzl" | "__builtin_clzll" => {
      self.emit_builtin_clz(args, 64)
      true
    }
    "__builtin_ctz" => {
      self.emit_builtin_ctz(args, 32)
      true
    }
    "__builtin_ctzl" | "__builtin_ctzll" => {
      self.emit_builtin_ctz(args, 64)
      true
    }
    "__builtin_ffs" => {
      self.emit_builtin_ffs(args, 32)
      true
    }
    "__builtin_ffsl" | "__builtin_ffsll" => {
      self.emit_builtin_ffs(args, 64)
      true
    }
    "__builtin_bswap16" => {
      self.emit_builtin_bswap(args, 16)
      true
    }
    "__builtin_bswap32" => {
      self.emit_builtin_bswap(args, 32)
      true
    }
    "__builtin_bswap64" => {
      self.emit_builtin_bswap(args, 64)
      true
    }
    "__builtin_bswap" => {
      self.emit_builtin_bswap(args, self.generic_builtin_bswap_width(args))
      true
    }
    "__builtin_rotateleft" => {
      self.emit_builtin_rotate(args, self.generic_builtin_bit_width(args), true)
      true
    }
    "__builtin_rotateright" => {
      self.emit_builtin_rotate(
        args,
        self.generic_builtin_bit_width(args),
        false,
      )
      true
    }
    "__builtin_rotateleft32" => {
      self.emit_builtin_rotate(args, 32, true)
      true
    }
    "__builtin_rotateright32" => {
      self.emit_builtin_rotate(args, 32, false)
      true
    }
    "__builtin_rotateleft64" => {
      self.emit_builtin_rotate(args, 64, true)
      true
    }
    "__builtin_rotateright64" => {
      self.emit_builtin_rotate(args, 64, false)
      true
    }
    "__builtin_popcount" => {
      self.emit_builtin_popcount(args, 32)
      true
    }
    "__builtin_popcountl" | "__builtin_popcountll" => {
      self.emit_builtin_popcount(args, 64)
      true
    }
    "__builtin_parity" => {
      self.emit_builtin_parity(args, 32)
      true
    }
    "__builtin_parityl" | "__builtin_parityll" => {
      self.emit_builtin_parity(args, 64)
      true
    }
    "__builtin_va_start" => {
      self.emit_va_start(args)
      true
    }
    "__builtin_va_end" => {
      self.emit("\tmov\trax, 0")
      true
    }
    "__builtin_va_copy" => {
      self.emit_va_copy(args)
      true
    }
    "__builtin_memcpy" | "__builtin___memcpy_chk" => {
      self.emit_builtin_lib_call("memcpy", args, 3, Pointer(Void), [
        Pointer(Void),
        Pointer(Void),
        ULong,
      ])
      true
    }
    "__builtin_mempcpy" | "__builtin___mempcpy_chk" => {
      self.emit_builtin_lib_call("mempcpy", args, 3, Pointer(Void), [
        Pointer(Void),
        Pointer(Void),
        ULong,
      ])
      true
    }
    "__builtin_memmove" | "__builtin___memmove_chk" => {
      self.emit_builtin_lib_call("memmove", args, 3, Pointer(Void), [
        Pointer(Void),
        Pointer(Void),
        ULong,
      ])
      true
    }
    "__builtin_memset" | "__builtin___memset_chk" => {
      self.emit_builtin_lib_call("memset", args, 3, Pointer(Void), [
        Pointer(Void),
        SInt,
        ULong,
      ])
      true
    }
    "__builtin_bzero" => {
      self.emit_builtin_lib_call("bzero", args, 2, Void, [Pointer(Void), ULong])
      true
    }
    "__builtin_memcmp" => {
      self.emit_builtin_lib_call("memcmp", args, 3, SInt, [
        Pointer(Void),
        Pointer(Void),
        ULong,
      ])
      true
    }
    "__builtin_memchr" => {
      self.emit_builtin_lib_call("memchr", args, 3, Pointer(Void), [
        Pointer(Void),
        SInt,
        ULong,
      ])
      true
    }
    "__builtin_strlen" => {
      self.emit_builtin_lib_call("strlen", args, 1, ULong, [Pointer(SChar)])
      true
    }
    "__builtin_strcmp" => {
      self.emit_builtin_lib_call("strcmp", args, 2, SInt, [
        Pointer(SChar),
        Pointer(SChar),
      ])
      true
    }
    "__builtin_strncmp" => {
      self.emit_builtin_lib_call("strncmp", args, 3, SInt, [
        Pointer(SChar),
        Pointer(SChar),
        ULong,
      ])
      true
    }
    "__builtin_strchr" => {
      self.emit_builtin_lib_call("strchr", args, 2, Pointer(SChar), [
        Pointer(SChar),
        SInt,
      ])
      true
    }
    "__builtin_strrchr" => {
      self.emit_builtin_lib_call("strrchr", args, 2, Pointer(SChar), [
        Pointer(SChar),
        SInt,
      ])
      true
    }
    "__builtin_strstr" => {
      self.emit_builtin_lib_call("strstr", args, 2, Pointer(SChar), [
        Pointer(SChar),
        Pointer(SChar),
      ])
      true
    }
    "__builtin_strcpy" | "__builtin___strcpy_chk" => {
      self.emit_builtin_lib_call("strcpy", args, 2, Pointer(SChar), [
        Pointer(SChar),
        Pointer(SChar),
      ])
      true
    }
    "__builtin_strcat" | "__builtin___strcat_chk" => {
      self.emit_builtin_lib_call("strcat", args, 2, Pointer(SChar), [
        Pointer(SChar),
        Pointer(SChar),
      ])
      true
    }
    "__builtin_stpcpy" | "__builtin___stpcpy_chk" => {
      self.emit_builtin_lib_call("stpcpy", args, 2, Pointer(SChar), [
        Pointer(SChar),
        Pointer(SChar),
      ])
      true
    }
    "__builtin_strncpy" | "__builtin___strncpy_chk" => {
      self.emit_builtin_lib_call("strncpy", args, 3, Pointer(SChar), [
        Pointer(SChar),
        Pointer(SChar),
        ULong,
      ])
      true
    }
    "__builtin_stpncpy" | "__builtin___stpncpy_chk" => {
      self.emit_builtin_lib_call("stpncpy", args, 3, Pointer(SChar), [
        Pointer(SChar),
        Pointer(SChar),
        ULong,
      ])
      true
    }
    "__builtin_strncat" | "__builtin___strncat_chk" => {
      self.emit_builtin_lib_call("strncat", args, 3, Pointer(SChar), [
        Pointer(SChar),
        Pointer(SChar),
        ULong,
      ])
      true
    }
    "__builtin___strlcpy_chk" => {
      self.emit_lowered_builtin_call(
        "strlcpy",
        args,
        [0, 1, 2],
        args.length(),
        ULong,
        false,
        [Pointer(SChar), Pointer(SChar), ULong],
      )
      true
    }
    "__builtin___strlcat_chk" => {
      self.emit_lowered_builtin_call(
        "strlcat",
        args,
        [0, 1, 2],
        args.length(),
        ULong,
        false,
        [Pointer(SChar), Pointer(SChar), ULong],
      )
      true
    }
    "__builtin___snprintf_chk" => {
      self.emit_lowered_builtin_call(
        "snprintf",
        args,
        [0, 1, 4],
        5,
        SInt,
        true,
        [Pointer(SChar), ULong, Pointer(SChar)],
      )
      true
    }
    "__builtin___vsnprintf_chk" => {
      self.emit_lowered_builtin_call(
        "vsnprintf",
        args,
        [0, 1, 4, 5],
        args.length(),
        SInt,
        false,
        [Pointer(SChar), ULong, Pointer(SChar), Pointer(SChar)],
      )
      true
    }
    "__builtin___sprintf_chk" => {
      self.emit_lowered_builtin_call("sprintf", args, [0, 3], 4, SInt, true, [
        Pointer(SChar),
        Pointer(SChar),
      ])
      true
    }
    "__builtin___vsprintf_chk" => {
      self.emit_lowered_builtin_call(
        "vsprintf",
        args,
        [0, 3, 4],
        args.length(),
        SInt,
        false,
        [Pointer(SChar), Pointer(SChar), Pointer(SChar)],
      )
      true
    }
    "__builtin___printf_chk" => {
      self.emit_lowered_builtin_call("printf", args, [1], 2, SInt, true, [
        Pointer(SChar),
      ])
      true
    }
    "__builtin___fprintf_chk" => {
      self.emit_lowered_builtin_call("fprintf", args, [0, 2], 3, SInt, true, [
        Pointer(Void),
        Pointer(SChar),
      ])
      true
    }
    "__builtin___vfprintf_chk" => {
      self.emit_lowered_builtin_call(
        "vfprintf",
        args,
        [0, 2, 3],
        args.length(),
        SInt,
        false,
        [Pointer(Void), Pointer(SChar), Pointer(SChar)],
      )
      true
    }
    _ => false
  }
}

///|
fn X64Codegen::field_info(
  self : X64Codegen,
  ty : @parser.Type,
  field_name : String,
) -> (@parser.Type, Int) {
  match self.field_layout(ty, field_name) {
    Some((_, field_ty, offset, _, _, _)) => (field_ty, offset)
    None => abort("unknown field: " + field_name)
  }
}

///|
fn X64Codegen::field_layout(
  self : X64Codegen,
  ty : @parser.Type,
  field_name : String,
) -> (String, @parser.Type, Int, Int, Int, Int)? {
  let struct_name = match x64_core_type(ty) {
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
  ty : @parser.Type,
  path : Array[@parser.OffsetDesignator],
) -> Int? {
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
fn x64_offset_array_element_type(ty : @parser.Type) -> @parser.Type? {
  match x64_core_type(ty) {
    Array(elem, _) => Some(elem)
    _ => None
  }
}

///|
fn X64Codegen::bitfield_info(
  self : X64Codegen,
  expr : @parser.Expr,
) -> X64BitfieldInfo? {
  match expr {
    MemberAccess(obj, field) =>
      match self.field_layout(self.type_of(obj), field) {
        Some((_, ty, _, size, bit_offset, bit_width)) =>
          if bit_width > 0 {
            Some({ ty, size, bit_offset, bit_width })
          } else {
            None
          }
        None => None
      }
    _ => None
  }
}

///|
fn x64_bitfield_promoted_type(info : X64BitfieldInfo) -> @parser.Type {
  match x64_core_type(info.ty) {
    Bool | SChar | UChar | SShort | UShort | SInt => SInt
    UInt => if info.bit_width <= 31 { SInt } else { UInt }
    _ => info.ty
  }
}

///|
fn X64Codegen::emit_load_container_to_rax(
  self : X64Codegen,
  addr_reg : String,
  size : Int,
) -> Unit {
  let mem = x64_mem_at_reg(addr_reg, 0)
  match size {
    1 => self.emit("\tmovzx\trax, BYTE PTR " + mem)
    2 => self.emit("\tmovzx\trax, WORD PTR " + mem)
    4 => self.emit("\tmov\teax, DWORD PTR " + mem)
    _ => self.emit("\tmov\trax, QWORD PTR " + mem)
  }
}

///|
fn X64Codegen::emit_load_container_to_rdx(
  self : X64Codegen,
  addr_reg : String,
  size : Int,
) -> Unit {
  let mem = x64_mem_at_reg(addr_reg, 0)
  match size {
    1 => self.emit("\tmovzx\trdx, BYTE PTR " + mem)
    2 => self.emit("\tmovzx\trdx, WORD PTR " + mem)
    4 => self.emit("\tmov\tedx, DWORD PTR " + mem)
    _ => self.emit("\tmov\trdx, QWORD PTR " + mem)
  }
}

///|
fn X64Codegen::emit_store_container_from_rdx(
  self : X64Codegen,
  addr_reg : String,
  size : Int,
) -> Unit {
  let mem = x64_mem_at_reg(addr_reg, 0)
  match size {
    1 => self.emit("\tmov\tBYTE PTR " + mem + ", dl")
    2 => self.emit("\tmov\tWORD PTR " + mem + ", dx")
    4 => self.emit("\tmov\tDWORD PTR " + mem + ", edx")
    _ => self.emit("\tmov\tQWORD PTR " + mem + ", rdx")
  }
}

///|
fn X64Codegen::emit_load_bitfield_from_addr(
  self : X64Codegen,
  addr_reg : String,
  info : X64BitfieldInfo,
) -> Unit {
  self.emit_load_container_to_rax(addr_reg, info.size)
  if info.bit_offset > 0 {
    self.emit("\tshr\trax, " + info.bit_offset.to_string())
  }
  if info.bit_width < 64 {
    self.emit("\tmov\tr11, " + bitfield_mask(info.bit_width).to_string())
    self.emit("\tand\trax, r11")
  }
  if info.ty.is_signed() && info.bit_width < 64 {
    let shift = 64 - info.bit_width
    self.emit("\tshl\trax, " + shift.to_string())
    self.emit("\tsar\trax, " + shift.to_string())
  }
}

///|
fn X64Codegen::emit_store_bitfield_value(
  self : X64Codegen,
  info : X64BitfieldInfo,
) -> Unit {
  let mask = bitfield_mask(info.bit_width).to_string()
  self.emit("\tmov\tr11, " + mask)
  self.emit("\tand\trax, r11")
  self.emit("\tmov\trcx, rax")
  self.emit_load_container_to_rdx("r10", info.size)
  self.emit("\tmov\tr11, " + mask)
  if info.bit_offset > 0 {
    self.emit("\tshl\tr11, " + info.bit_offset.to_string())
  }
  self.emit("\tnot\tr11")
  self.emit("\tand\trdx, r11")
  if info.bit_offset > 0 {
    self.emit("\tshl\trax, " + info.bit_offset.to_string())
  }
  self.emit("\tor\trdx, rax")
  self.emit_store_container_from_rdx("r10", info.size)
  self.emit("\tmov\trax, rcx")
  if info.ty.is_signed() && info.bit_width < 64 {
    let shift = 64 - info.bit_width
    self.emit("\tshl\trax, " + shift.to_string())
    self.emit("\tsar\trax, " + shift.to_string())
  }
}

///|
fn X64Codegen::type_of(self : X64Codegen, expr : @parser.Expr) -> @parser.Type {
  match expr {
    Number(value) => number_literal_type(value)
    FloatLiteral(_) => Double
    String(_) => Pointer(SChar)
    Var(name) =>
      if self.var_types.contains(name) {
        self.var_types[name]
      } else if self.globals.contains(name) {
        self.globals[name].ty
      } else if self.func_rets.contains(name) {
        FuncPtr(
          self.func_rets[name],
          self.func_param_types.get_or_default(name, []),
          self.func_variadic.get_or_default(name, false),
        )
      } else {
        SInt
      }
    Binary(op, lhs, rhs) => {
      let lhs_ty = self.type_of(lhs)
      let rhs_ty = self.type_of(rhs)
      if op == "-" && x64_is_pointer_like(lhs_ty) && x64_is_pointer_like(rhs_ty) {
        return SLong
      }
      match x64_pointer_element(lhs_ty) {
        Some(elem) =>
          if (op == "+" || op == "-") && rhs_ty.is_integer() {
            return Pointer(elem)
          }
        None => ()
      }
      match x64_pointer_element(rhs_ty) {
        Some(elem) =>
          if op == "+" && lhs_ty.is_integer() {
            return Pointer(elem)
          }
        None => ()
      }
      match op {
        "==" | "!=" | "<" | "<=" | ">" | ">=" | "&&" | "||" => SInt
        _ => binary_result_type(op, lhs_ty, rhs_ty)
      }
    }
    Unary("!", _) => SInt
    Unary(_, operand) => self.type_of(operand)
    Call(func, args) =>
      match func {
        Var(name) =>
          match self.builtin_return_type(name, args) {
            Some(ty) => ty
            None =>
              match self.type_of(func) {
                FuncPtr(ret, _, _) => ret
                _ => SInt
              }
          }
        _ =>
          match self.type_of(func) {
            FuncPtr(ret, _, _) => ret
            _ => SInt
          }
      }
    Assign(lhs, _) => self.type_of(lhs)
    CompoundAssign(_, lhs, _) => self.type_of(lhs)
    MemberAccess(obj, field) => {
      let (field_ty, _) = self.field_info(self.type_of(obj), field)
      field_ty
    }
    Deref(ptr) =>
      match x64_core_type(self.type_of(ptr)) {
        Pointer(ty) | Array(ty, _) => ty
        FuncPtr(ret, params, variadic) => FuncPtr(ret, params, variadic)
        _ => SInt
      }
    AddrOf(e) => Pointer(self.type_of(e))
    ArrayAccess(arr, _) =>
      match x64_pointer_element(self.type_of(arr)) {
        Some(elem) => elem
        None => SInt
      }
    Sizeof(_) | SizeofExpr(_) | Alignof(_) | AlignofExpr(_) | OffsetOf(_, _) =>
      SLong
    Cast(ty, _) => ty
    PrefixInc(e) | PrefixDec(e) | PostfixInc(e) | PostfixDec(e) =>
      self.type_of(e)
    Ternary(_, then_, else_) =>
      x64_ternary_result_type(self.type_of(then_), self.type_of(else_))
    LabelAddr(_) => Pointer(Void)
    VaArg(_, ty) => ty
    Array(_) => SInt
    CompoundLiteral(ty, _, _) => ty
    DesignatedField(_, e) | DesignatedIndex(_, e) | DesignatedRange(_, _, e) =>
      self.type_of(e)
  }
}

///|
fn X64Codegen::global_expr_type(
  self : X64Codegen,
  expr : @parser.Expr,
) -> @parser.Type {
  match expr {
    Number(value) => number_literal_type(value)
    FloatLiteral(_) => Double
    String(s) => Array(SChar, s.length() + 1)
    Var(name) =>
      if self.globals.contains(name) {
        self.globals[name].ty
      } else if self.func_rets.contains(name) {
        FuncPtr(
          self.func_rets[name],
          self.func_param_types.get_or_default(name, []),
          self.func_variadic.get_or_default(name, false),
        )
      } else {
        SInt
      }
    DesignatedField(_, e) | DesignatedIndex(_, e) | DesignatedRange(_, _, e) =>
      self.global_expr_type(e)
    Cast(ty, _) => ty
    AddrOf(e) => Pointer(self.global_expr_type(e))
    Deref(e) =>
      match peel_aligned_type(self.global_expr_type(e)) {
        Pointer(elem) | Array(elem, _) => elem
        _ => SInt
      }
    ArrayAccess(base, _) =>
      match peel_aligned_type(self.global_expr_type(base)) {
        Array(elem, _) | Pointer(elem) => elem
        _ => SInt
      }
    MemberAccess(obj, field) =>
      match peel_aligned_type(self.global_expr_type(obj)) {
        Struct(name) =>
          match self.field_layout(Struct(name), field) {
            Some((_, ty, _, _, _, _)) => ty
            None => SInt
          }
        Union(name) =>
          match self.field_layout(Union(name), field) {
            Some((_, ty, _, _, _, _)) => ty
            None => SInt
          }
        Pointer(Struct(name)) =>
          match self.field_layout(Struct(name), field) {
            Some((_, ty, _, _, _, _)) => ty
            None => SInt
          }
        Pointer(Union(name)) =>
          match self.field_layout(Union(name), field) {
            Some((_, ty, _, _, _, _)) => ty
            None => SInt
          }
        _ => SInt
      }
    CompoundLiteral(ty, _, _) => ty
    _ => SInt
  }
}

///|
fn X64Codegen::gen_addr(self : X64Codegen, expr : @parser.Expr) -> Unit {
  match expr {
    Var(name) =>
      if self.local_offsets.contains(name) {
        self.emit_local_addr(self.local_offsets[name])
      } else {
        self.emit("\tlea\trax, [rip + " + name + "]")
      }
    Deref(ptr) => self.gen_expr(ptr)
    AddrOf(e) => self.gen_addr(e)
    MemberAccess(obj, field) => {
      if x64_is_aggregate_type(self.type_of(obj)) {
        self.gen_aggregate_addr(obj)
      } else {
        self.gen_addr(obj)
      }
      let (_, offset) = self.field_info(self.type_of(obj), field)
      if offset != 0 {
        self.emit("\tadd\trax, " + offset.to_string())
      }
    }
    ArrayAccess(arr, index) => {
      match x64_core_type(self.type_of(arr)) {
        Array(_, _) => self.gen_addr(arr)
        _ => self.gen_expr(arr)
      }
      self.emit_push_rax()
      self.gen_expr(index)
      let elem_ty = match x64_pointer_element(self.type_of(arr)) {
        Some(ty) => ty
        None => SInt
      }
      let elem_size = self.pointer_element_size(elem_ty)
      if elem_size != 1 {
        self.emit("\timul\trax, rax, " + elem_size.to_string())
      }
      self.emit("\tmov\tr10, rax")
      self.emit_pop_rax()
      self.emit("\tadd\trax, r10")
    }
    LabelAddr(name) =>
      self.emit("\tlea\trax, [rip + " + self.label_ref(name) + "]")
    CompoundLiteral(ty, init_exprs, id) =>
      self.gen_compound_literal_addr(ty, init_exprs, id)
    _ => abort("expression is not addressable")
  }
}

///|
fn X64Codegen::gen_compound_literal_addr(
  self : X64Codegen,
  ty : @parser.Type,
  init_exprs : Array[@parser.Expr],
  id : Int,
) -> Unit {
  let name = compound_literal_local_name(id)
  let offset = if self.local_offsets.contains(name) {
    self.local_offsets[name]
  } else {
    self.alloc_local(name, ty)
  }
  self.emit_local_addr(offset)
  if x64_is_object_aggregate_type(ty) {
    self.emit_init_aggregate_at_addr(ty, init_exprs)
  } else if init_exprs.length() > 0 {
    self.emit_init_value_at_addr(ty, init_exprs[0])
  } else {
    self.emit_zero_memory_at_rax(ty)
  }
  self.emit_local_addr(offset)
}

///|
fn X64Codegen::gen_aggregate_addr(
  self : X64Codegen,
  expr : @parser.Expr,
) -> Unit {
  match expr {
    Ternary(cond, then_, else_) => {
      let else_label = self.new_label()
      let end_label = self.new_label()
      self.gen_cond_jump_false(cond, else_label)
      self.gen_aggregate_addr(then_)
      self.emit("\tjmp\t" + end_label)
      self.emit(else_label + ":")
      self.gen_aggregate_addr(else_)
      self.emit(end_label + ":")
    }
    Binary(",", lhs, rhs) => {
      self.gen_expr(lhs)
      self.gen_aggregate_addr(rhs)
    }
    Cast(ty, inner) if x64_is_aggregate_type(ty) =>
      self.gen_aggregate_addr(inner)
    Assign(_, _) | CompoundAssign(_, _, _) => self.gen_expr(expr)
    VaArg(ap_expr, ty) if x64_is_aggregate_type(ty) =>
      self.emit_va_arg_aggregate_addr(ap_expr, ty)
    Call(_, _) if self.is_memory_aggregate(self.type_of(expr)) =>
      self.gen_expr(expr)
    CompoundLiteral(ty, init_exprs, id) =>
      self.gen_compound_literal_addr(ty, init_exprs, id)
    _ => self.gen_addr(expr)
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
  ty : @parser.Type,
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
  src_ty : @parser.Type,
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
  ty : @parser.Type,
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
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
) -> @parser.Type {
  if op == "<<" || op == ">>" {
    unary_integer_result_type(lhs_ty)
  } else {
    integer_common_type(lhs_ty, rhs_ty)
  }
}

///|
fn x64_binary_rhs_int_type(
  op : String,
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
) -> @parser.Type {
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
  then_ty : @parser.Type,
  else_ty : @parser.Type,
) -> @parser.Type {
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
fn X64Codegen::emit_fp_to_bool(self : X64Codegen, ty : @parser.Type) -> Unit {
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
fn X64Codegen::gen_int128_binary(
  self : X64Codegen,
  op : String,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
) -> Unit {
  let result_ty = if op == "<<" || op == ">>" {
    unary_integer_result_type(lhs_ty)
  } else {
    integer_common_type(lhs_ty, rhs_ty)
  }
  let is_unsigned = is_unsigned_integer_type(result_ty)
  self.gen_expr_as_scalar(lhs, result_ty)
  self.emit_push_int128()
  if op == "<<" || op == ">>" {
    self.gen_expr_as_scalar(rhs, unary_integer_result_type(rhs_ty))
  } else {
    self.gen_expr_as_scalar(rhs, result_ty)
  }
  self.emit("\tmov\tr10, rax")
  self.emit("\tmov\tr11, rdx")
  self.emit_pop_int128()
  match op {
    "+" => {
      self.emit("\tadd\trax, r10")
      self.emit("\tadc\trdx, r11")
    }
    "-" => {
      self.emit("\tsub\trax, r10")
      self.emit("\tsbb\trdx, r11")
    }
    "*" => {
      self.emit("\tmov\tr8, rax")
      self.emit("\tmov\tr9, rdx")
      self.emit("\tmov\trax, r8")
      self.emit("\tmul\tr10")
      self.emit("\timul\tr11, r8")
      self.emit("\timul\tr9, r10")
      self.emit("\tadd\trdx, r11")
      self.emit("\tadd\trdx, r9")
    }
    "/" =>
      if is_unsigned {
        self.emit_int128_libcall("__udivti3")
      } else {
        self.emit_int128_libcall("__divti3")
      }
    "%" =>
      if is_unsigned {
        self.emit_int128_libcall("__umodti3")
      } else {
        self.emit_int128_libcall("__modti3")
      }
    "&" => {
      self.emit("\tand\trax, r10")
      self.emit("\tand\trdx, r11")
    }
    "|" => {
      self.emit("\tor\trax, r10")
      self.emit("\tor\trdx, r11")
    }
    "^" => {
      self.emit("\txor\trax, r10")
      self.emit("\txor\trdx, r11")
    }
    "<<" => {
      self.emit("\tmov\trcx, r10")
      self.emit_int128_left_shift()
    }
    ">>" => {
      self.emit("\tmov\trcx, r10")
      self.emit_int128_right_shift(is_unsigned)
    }
    "==" | "!=" | "<" | "<=" | ">" | ">=" =>
      self.emit_int128_compare(op, is_unsigned)
    _ => abort("unsupported x86-64 int128 binary operator: " + op)
  }
}

///|
fn X64Codegen::gen_int128_compound_assign(
  self : X64Codegen,
  op : String,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
) -> Unit {
  let result_ty = if op == "<<" || op == ">>" {
    unary_integer_result_type(lhs_ty)
  } else {
    integer_common_type(lhs_ty, rhs_ty)
  }
  let is_unsigned = is_unsigned_integer_type(result_ty)
  self.gen_addr(lhs)
  self.emit_push_rax()
  self.emit_load_indirect(lhs_ty)
  self.emit_push_int128()
  if op == "<<" || op == ">>" {
    self.gen_expr_as_scalar(rhs, unary_integer_result_type(rhs_ty))
  } else {
    self.gen_expr_as_scalar(rhs, result_ty)
  }
  self.emit("\tmov\tr10, rax")
  self.emit("\tmov\tr11, rdx")
  self.emit_pop_int128()
  match op {
    "+" => {
      self.emit("\tadd\trax, r10")
      self.emit("\tadc\trdx, r11")
    }
    "-" => {
      self.emit("\tsub\trax, r10")
      self.emit("\tsbb\trdx, r11")
    }
    "*" => {
      self.emit("\tmov\tr8, rax")
      self.emit("\tmov\tr9, rdx")
      self.emit("\tmov\trax, r8")
      self.emit("\tmul\tr10")
      self.emit("\timul\tr11, r8")
      self.emit("\timul\tr9, r10")
      self.emit("\tadd\trdx, r11")
      self.emit("\tadd\trdx, r9")
    }
    "/" =>
      if is_unsigned {
        self.emit_int128_libcall("__udivti3")
      } else {
        self.emit_int128_libcall("__divti3")
      }
    "%" =>
      if is_unsigned {
        self.emit_int128_libcall("__umodti3")
      } else {
        self.emit_int128_libcall("__modti3")
      }
    "&" => {
      self.emit("\tand\trax, r10")
      self.emit("\tand\trdx, r11")
    }
    "|" => {
      self.emit("\tor\trax, r10")
      self.emit("\tor\trdx, r11")
    }
    "^" => {
      self.emit("\txor\trax, r10")
      self.emit("\txor\trdx, r11")
    }
    "<<" => {
      self.emit("\tmov\trcx, r10")
      self.emit_int128_left_shift()
    }
    ">>" => {
      self.emit("\tmov\trcx, r10")
      self.emit_int128_right_shift(is_unsigned)
    }
    _ => abort("unsupported x86-64 int128 compound assignment: " + op)
  }
  self.emit("\tmov\tr8, rax")
  self.emit("\tmov\tr9, rdx")
  self.emit_pop_rax()
  self.emit("\tmov\tr10, rax")
  self.emit("\tmov\trax, r8")
  self.emit("\tmov\trdx, r9")
  self.emit_store_indirect(lhs_ty)
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
  ty : @parser.Type,
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
fn X64Codegen::gen_expr_as_fp(
  self : X64Codegen,
  expr : @parser.Expr,
  dst_ty : @parser.Type,
) -> Unit {
  let src_ty = self.type_of(expr)
  if x64_is_fp_type(src_ty) {
    self.gen_expr(expr)
    match (x64_core_type(src_ty), x64_core_type(dst_ty)) {
      (Float, Double) => self.emit("\tcvtss2sd\txmm0, xmm0")
      (Double, Float) => self.emit("\tcvtsd2ss\txmm0, xmm0")
      _ => ()
    }
  } else {
    self.gen_expr(expr)
    self.emit_int_to_fp(src_ty, dst_ty)
  }
}

///|
fn X64Codegen::emit_int_to_fp(
  self : X64Codegen,
  src_ty : @parser.Type,
  dst_ty : @parser.Type,
) -> Unit {
  if is_unsigned_integer_type(src_ty) && self.type_size(src_ty) == 8 {
    self.emit_uint64_to_fp(dst_ty)
  } else if x64_core_type(dst_ty) == Float {
    self.emit("\tcvtsi2ss\txmm0, rax")
  } else {
    self.emit("\tcvtsi2sd\txmm0, rax")
  }
}

///|
fn X64Codegen::emit_uint64_to_fp(
  self : X64Codegen,
  dst_ty : @parser.Type,
) -> Unit {
  let non_negative = self.new_label()
  let done = self.new_label()
  self.emit("\ttest\trax, rax")
  self.emit("\tjns\t" + non_negative)
  self.emit("\tmov\tr10, rax")
  self.emit("\tand\trax, 1")
  self.emit("\tshr\tr10, 1")
  self.emit("\tor\trax, r10")
  if x64_core_type(dst_ty) == Float {
    self.emit("\tcvtsi2ss\txmm0, rax")
    self.emit("\taddss\txmm0, xmm0")
  } else {
    self.emit("\tcvtsi2sd\txmm0, rax")
    self.emit("\taddsd\txmm0, xmm0")
  }
  self.emit("\tjmp\t" + done)
  self.emit(non_negative + ":")
  if x64_core_type(dst_ty) == Float {
    self.emit("\tcvtsi2ss\txmm0, rax")
  } else {
    self.emit("\tcvtsi2sd\txmm0, rax")
  }
  self.emit(done + ":")
}

///|
fn X64Codegen::emit_fp_to_uint64(
  self : X64Codegen,
  src_ty : @parser.Type,
) -> Unit {
  let below_high_bit = self.new_label()
  let done = self.new_label()
  if x64_core_type(src_ty) == Float {
    self.emit("\tcvtss2sd\txmm0, xmm0")
  }
  self.emit_load_fp_literal_into("xmm1", 9223372036854775808.0)
  self.emit("\tucomisd\txmm0, xmm1")
  self.emit("\tjb\t" + below_high_bit)
  self.emit("\tsubsd\txmm0, xmm1")
  self.emit("\tcvttsd2si\trax, xmm0")
  self.emit("\tmovabs\tr10, -9223372036854775808")
  self.emit("\tor\trax, r10")
  self.emit("\tjmp\t" + done)
  self.emit(below_high_bit + ":")
  self.emit("\tcvttsd2si\trax, xmm0")
  self.emit(done + ":")
}

///|
fn X64Codegen::emit_fp_to_integer(
  self : X64Codegen,
  src_ty : @parser.Type,
  dst_ty : @parser.Type,
) -> Unit {
  if is_unsigned_integer_type(dst_ty) && self.type_size(dst_ty) == 8 {
    self.emit_fp_to_uint64(src_ty)
  } else if x64_core_type(src_ty) == Float {
    self.emit("\tcvttss2si\trax, xmm0")
  } else {
    self.emit("\tcvttsd2si\trax, xmm0")
  }
}

///|
fn X64Codegen::emit_fp_to_scalar(
  self : X64Codegen,
  src_ty : @parser.Type,
  dst_ty : @parser.Type,
) -> Unit {
  if x64_core_type(dst_ty) == Bool {
    self.emit_fp_to_bool(src_ty)
  } else {
    self.emit_fp_to_integer(src_ty, dst_ty)
    self.emit_int_conversion_to(dst_ty)
  }
}

///|
fn X64Codegen::gen_expr_as_int(self : X64Codegen, expr : @parser.Expr) -> Unit {
  let src_ty = self.type_of(expr)
  self.gen_expr(expr)
  if x64_is_fp_type(src_ty) {
    self.emit_fp_to_integer(src_ty, SLongLong)
  }
}

///|
fn X64Codegen::gen_expr_as_integer(
  self : X64Codegen,
  expr : @parser.Expr,
  dst_ty : @parser.Type,
) -> Unit {
  let src_ty = self.type_of(expr)
  self.gen_expr(expr)
  if x64_is_fp_type(src_ty) {
    self.emit_fp_to_integer(src_ty, dst_ty)
  }
}

///|
fn X64Codegen::gen_expr_as_scalar(
  self : X64Codegen,
  expr : @parser.Expr,
  dst_ty : @parser.Type,
) -> Unit {
  let src_ty = self.type_of(expr)
  if x64_is_fp_type(dst_ty) {
    self.gen_expr_as_fp(expr, dst_ty)
  } else if x64_core_type(dst_ty) == Bool {
    self.gen_expr(expr)
    if x64_is_fp_type(src_ty) {
      self.emit_fp_to_bool(src_ty)
    } else if x64_is_int128_type(src_ty) {
      self.emit_int128_to_bool()
    } else {
      self.emit_int_conversion_to(dst_ty)
    }
  } else if x64_is_int128_type(dst_ty) {
    self.gen_expr_as_int(expr)
    self.emit_extend_rax_to_int128(src_ty)
  } else {
    self.gen_expr_as_integer(expr, dst_ty)
    self.emit_int_conversion_to(dst_ty)
  }
}

///|
fn X64Codegen::gen_cond_jump_false(
  self : X64Codegen,
  expr : @parser.Expr,
  false_label : String,
) -> Unit {
  let ty = self.type_of(expr)
  self.gen_expr(expr)
  if x64_is_fp_type(ty) {
    self.emit_fp_cond_jump_false(ty, false_label)
  } else if x64_is_int128_type(ty) {
    self.emit("\tor\trax, rdx")
    self.emit("\tje\t" + false_label)
  } else {
    self.emit("\tcmp\trax, 0")
    self.emit("\tje\t" + false_label)
  }
}

///|
fn X64Codegen::emit_switch_case_compare(
  self : X64Codegen,
  case_value : Int64,
  control_ty : @parser.Type,
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
fn X64Codegen::emit_scaled_integer(
  self : X64Codegen,
  expr : @parser.Expr,
  elem_ty : @parser.Type,
) -> Unit {
  self.gen_expr(expr)
  let size = self.pointer_element_size(elem_ty)
  if size != 1 {
    self.emit("\timul\trax, rax, " + size.to_string())
  }
}

///|
fn X64Codegen::gen_pointer_arith(
  self : X64Codegen,
  op : String,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
) -> Bool {
  let lhs_ty = self.type_of(lhs)
  let rhs_ty = self.type_of(rhs)
  match (x64_pointer_element(lhs_ty), x64_pointer_element(rhs_ty)) {
    (Some(elem_ty), None) =>
      if (op == "+" || op == "-") && rhs_ty.is_integer() {
        self.emit_scaled_integer(rhs, elem_ty)
        self.emit_push_rax()
        self.gen_expr(lhs)
        self.emit("\tmov\tr10, rax")
        self.emit_pop_rax()
        if op == "+" {
          self.emit("\tadd\trax, r10")
        } else {
          self.emit("\tmov\tr11, rax")
          self.emit("\tmov\trax, r10")
          self.emit("\tsub\trax, r11")
        }
        return true
      } else {
        false
      }
    (None, Some(elem_ty)) =>
      if op == "+" && lhs_ty.is_integer() {
        self.emit_scaled_integer(lhs, elem_ty)
        self.emit_push_rax()
        self.gen_expr(rhs)
        self.emit("\tmov\tr10, rax")
        self.emit_pop_rax()
        self.emit("\tadd\trax, r10")
        true
      } else {
        false
      }
    (Some(elem_ty), Some(_)) =>
      if op == "-" {
        self.gen_expr(lhs)
        self.emit_push_rax()
        self.gen_expr(rhs)
        self.emit("\tmov\tr10, rax")
        self.emit_pop_rax()
        self.emit("\tsub\trax, r10")
        let size = self.pointer_element_size(elem_ty)
        if size != 1 {
          self.emit("\tcqo")
          self.emit("\tmov\tr10, " + size.to_string())
          self.emit("\tidiv\tr10")
        }
        true
      } else {
        false
      }
    _ => false
  }
}

///|
fn X64Codegen::gen_logical_and(
  self : X64Codegen,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
) -> Unit {
  let false_label = self.new_label()
  let end_label = self.new_label()
  self.gen_cond_jump_false(lhs, false_label)
  self.gen_cond_jump_false(rhs, false_label)
  self.emit("\tmov\trax, 1")
  self.emit("\tjmp\t" + end_label)
  self.emit(false_label + ":")
  self.emit("\tmov\trax, 0")
  self.emit(end_label + ":")
}

///|
fn X64Codegen::gen_logical_or(
  self : X64Codegen,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
) -> Unit {
  let rhs_label = self.new_label()
  let false_label = self.new_label()
  let end_label = self.new_label()
  self.gen_cond_jump_false(lhs, rhs_label)
  self.emit("\tmov\trax, 1")
  self.emit("\tjmp\t" + end_label)
  self.emit(rhs_label + ":")
  self.gen_cond_jump_false(rhs, false_label)
  self.emit("\tmov\trax, 1")
  self.emit("\tjmp\t" + end_label)
  self.emit(false_label + ":")
  self.emit("\tmov\trax, 0")
  self.emit(end_label + ":")
}

///|
fn X64Codegen::gen_fp_binary(
  self : X64Codegen,
  op : String,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
) -> Unit {
  let result_ty : @parser.Type = if self.type_of(lhs) == Double ||
    self.type_of(rhs) == Double {
    Double
  } else {
    Float
  }
  let suffix = x64_fp_suffix(result_ty)
  let spill_store = if result_ty == Float {
    "DWORD PTR [rsp], xmm0"
  } else {
    "QWORD PTR [rsp], xmm0"
  }
  let spill_load = if result_ty == Float {
    "DWORD PTR [rsp]"
  } else {
    "QWORD PTR [rsp]"
  }
  self.gen_expr_as_fp(lhs, result_ty)
  self.emit("\tsub\trsp, 8")
  self.emit("\tmov" + suffix + "\t" + spill_store)
  self.gen_expr_as_fp(rhs, result_ty)
  self.emit("\tmovapd\txmm1, xmm0")
  self.emit("\tmov" + suffix + "\txmm0, " + spill_load)
  self.emit("\tadd\trsp, 8")
  match op {
    "+" => self.emit("\tadd" + suffix + "\txmm0, xmm1")
    "-" => self.emit("\tsub" + suffix + "\txmm0, xmm1")
    "*" => self.emit("\tmul" + suffix + "\txmm0, xmm1")
    "/" => self.emit("\tdiv" + suffix + "\txmm0, xmm1")
    "==" | "!=" | "<" | "<=" | ">" | ">=" => {
      self.emit("\tucomi" + suffix + "\txmm0, xmm1")
      self.emit_fp_compare_result(op)
    }
    _ => abort("unsupported x86-64 floating operator: " + op)
  }
}

///|
fn X64Codegen::gen_binary(
  self : X64Codegen,
  op : String,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
) -> Unit {
  if op == "&&" {
    self.gen_logical_and(lhs, rhs)
    return
  }
  if op == "||" {
    self.gen_logical_or(lhs, rhs)
    return
  }
  if self.gen_pointer_arith(op, lhs, rhs) {
    return
  }
  let lhs_ty = self.type_of(lhs)
  let rhs_ty = self.type_of(rhs)
  if x64_is_fp_type(lhs_ty) || x64_is_fp_type(rhs_ty) {
    self.gen_fp_binary(op, lhs, rhs)
    return
  }
  if op == "," {
    self.gen_expr(lhs)
    self.gen_expr(rhs)
    return
  }
  let is_integer_binary = lhs_ty.is_integer() && rhs_ty.is_integer()
  if is_integer_binary &&
    x64_is_int128_type(x64_binary_int_type(op, lhs_ty, rhs_ty)) {
    self.gen_int128_binary(op, lhs, rhs, lhs_ty, rhs_ty)
    return
  }
  let lhs_eval_ty = if is_integer_binary {
    x64_binary_int_type(op, lhs_ty, rhs_ty)
  } else {
    lhs_ty
  }
  let rhs_eval_ty = if is_integer_binary {
    x64_binary_rhs_int_type(op, lhs_ty, rhs_ty)
  } else {
    rhs_ty
  }
  let unsigned_op = if is_integer_binary {
    is_unsigned_integer_type(lhs_eval_ty)
  } else {
    false
  }
  self.gen_expr(lhs)
  if is_integer_binary {
    self.emit_int_conversion_to(lhs_eval_ty)
  }
  self.emit_push_rax()
  self.gen_expr(rhs)
  if is_integer_binary {
    self.emit_int_conversion_to(rhs_eval_ty)
  }
  self.emit("\tmov\tr10, rax")
  self.emit_pop_rax()
  match op {
    "+" => self.emit("\tadd\trax, r10")
    "-" => self.emit("\tsub\trax, r10")
    "*" => self.emit("\timul\trax, r10")
    "/" =>
      if unsigned_op {
        self.emit("\txor\trdx, rdx")
        self.emit("\tdiv\tr10")
      } else {
        self.emit("\tcqo")
        self.emit("\tidiv\tr10")
      }
    "%" => {
      if unsigned_op {
        self.emit("\txor\trdx, rdx")
        self.emit("\tdiv\tr10")
      } else {
        self.emit("\tcqo")
        self.emit("\tidiv\tr10")
      }
      self.emit("\tmov\trax, rdx")
    }
    "&" => self.emit("\tand\trax, r10")
    "|" => self.emit("\tor\trax, r10")
    "^" => self.emit("\txor\trax, r10")
    "<<" => {
      self.emit("\tmov\trcx, r10")
      self.emit("\tshl\trax, cl")
    }
    ">>" => {
      self.emit("\tmov\trcx, r10")
      if unsigned_op {
        self.emit("\tshr\trax, cl")
      } else {
        self.emit("\tsar\trax, cl")
      }
    }
    "==" => {
      self.emit("\tcmp\trax, r10")
      self.emit_setcc("sete")
    }
    "!=" => {
      self.emit("\tcmp\trax, r10")
      self.emit_setcc("setne")
    }
    "<" => {
      self.emit("\tcmp\trax, r10")
      if unsigned_op {
        self.emit_setcc("setb")
      } else {
        self.emit_setcc("setl")
      }
    }
    "<=" => {
      self.emit("\tcmp\trax, r10")
      if unsigned_op {
        self.emit_setcc("setbe")
      } else {
        self.emit_setcc("setle")
      }
    }
    ">" => {
      self.emit("\tcmp\trax, r10")
      if unsigned_op {
        self.emit_setcc("seta")
      } else {
        self.emit_setcc("setg")
      }
    }
    ">=" => {
      self.emit("\tcmp\trax, r10")
      if unsigned_op {
        self.emit_setcc("setae")
      } else {
        self.emit_setcc("setge")
      }
    }
    _ => abort("unsupported x86-64 binary operator: " + op)
  }
  if is_integer_binary && x64_binary_converts_result(op) {
    self.emit_int_conversion_to(lhs_eval_ty)
  }
}

///|
fn X64Codegen::gen_assign(
  self : X64Codegen,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
) -> Unit {
  let lhs_ty = self.type_of(lhs)
  match self.bitfield_info(lhs) {
    Some(info) => {
      self.gen_expr_as_scalar(rhs, info.ty)
      self.emit_push_rax()
      self.gen_addr(lhs)
      self.emit("\tmov\tr10, rax")
      self.emit_pop_rax()
      self.emit_store_bitfield_value(info)
      return
    }
    None => ()
  }
  if x64_is_aggregate_type(lhs_ty) {
    self.gen_addr(lhs)
    self.emit_push_rax()
    match rhs {
      Call(_, _) if self.is_supported_small_aggregate(lhs_ty) => {
        self.gen_expr(rhs)
        self.emit_store_aggregate_call_result_to_pushed_addr(lhs_ty)
      }
      _ => {
        self.gen_aggregate_addr(rhs)
        self.emit("\tmov\tr11, rax")
        self.emit_pop_rax()
        self.emit("\tmov\tr10, rax")
        self.emit_push_rax()
        self.emit_copy_aggregate_from_addr(lhs_ty)
        self.emit_pop_rax()
      }
    }
    return
  }
  self.gen_expr_as_scalar(rhs, lhs_ty)
  if x64_is_int128_type(lhs_ty) {
    self.emit("\tpush\trdx")
  }
  self.emit_push_rax()
  self.gen_addr(lhs)
  self.emit("\tmov\tr10, rax")
  self.emit_pop_rax()
  if x64_is_int128_type(lhs_ty) {
    self.emit("\tpop\trdx")
  }
  self.emit_store_indirect(lhs_ty)
}

///|
fn X64Codegen::gen_pointer_compound_assign(
  self : X64Codegen,
  op : String,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
) -> Bool {
  match x64_core_type(lhs_ty) {
    Pointer(elem_ty) =>
      if (op == "+" || op == "-") && rhs_ty.is_integer() {
        self.gen_addr(lhs)
        self.emit_push_rax()
        self.emit_load_indirect(lhs_ty)
        self.emit_push_rax()
        self.emit_scaled_integer(rhs, elem_ty)
        self.emit("\tmov\tr10, rax")
        self.emit_pop_rax()
        if op == "+" {
          self.emit("\tadd\trax, r10")
        } else {
          self.emit("\tsub\trax, r10")
        }
        self.emit("\tmov\tr11, rax")
        self.emit_pop_rax()
        self.emit("\tmov\tr10, rax")
        self.emit("\tmov\trax, r11")
        self.emit_store_indirect(lhs_ty)
        true
      } else {
        false
      }
    _ => false
  }
}

///|
fn X64Codegen::gen_integer_fp_compound_assign(
  self : X64Codegen,
  op : String,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
) -> Bool {
  if !lhs_ty.is_integer() ||
    x64_is_int128_type(lhs_ty) ||
    !x64_is_fp_type(rhs_ty) {
    return false
  }
  match op {
    "+" | "-" | "*" | "/" => ()
    _ => return false
  }
  let result_ty : @parser.Type = if x64_core_type(rhs_ty) == Double {
    Double
  } else {
    Float
  }
  let suffix = x64_fp_suffix(result_ty)
  let spill_store = if x64_core_type(result_ty) == Float {
    "DWORD PTR [rsp], xmm0"
  } else {
    "QWORD PTR [rsp], xmm0"
  }
  let spill_load = if x64_core_type(result_ty) == Float {
    "DWORD PTR [rsp]"
  } else {
    "QWORD PTR [rsp]"
  }
  self.gen_addr(lhs)
  self.emit_push_rax()
  self.emit_load_indirect(lhs_ty)
  self.emit_int_to_fp(lhs_ty, result_ty)
  self.emit("\tsub\trsp, 8")
  self.emit("\tmov" + suffix + "\t" + spill_store)
  self.gen_expr_as_fp(rhs, result_ty)
  self.emit("\tmovapd\txmm1, xmm0")
  self.emit("\tmov" + suffix + "\txmm0, " + spill_load)
  self.emit("\tadd\trsp, 8")
  match op {
    "+" => self.emit("\tadd" + suffix + "\txmm0, xmm1")
    "-" => self.emit("\tsub" + suffix + "\txmm0, xmm1")
    "*" => self.emit("\tmul" + suffix + "\txmm0, xmm1")
    "/" => self.emit("\tdiv" + suffix + "\txmm0, xmm1")
    _ => abort("unsupported x86-64 integer/floating compound assignment: " + op)
  }
  self.emit_fp_to_scalar(result_ty, lhs_ty)
  self.emit("\tmov\tr11, rax")
  self.emit_pop_rax()
  self.emit("\tmov\tr10, rax")
  self.emit("\tmov\trax, r11")
  self.emit_store_indirect(lhs_ty)
  true
}

///|
fn X64Codegen::gen_bitfield_fp_compound_assign(
  self : X64Codegen,
  op : String,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
  info : X64BitfieldInfo,
) -> Bool {
  let rhs_ty = self.type_of(rhs)
  if !x64_is_fp_type(rhs_ty) {
    return false
  }
  match op {
    "+" | "-" | "*" | "/" => ()
    _ => return false
  }
  let result_ty : @parser.Type = if x64_core_type(rhs_ty) == Double {
    Double
  } else {
    Float
  }
  let suffix = x64_fp_suffix(result_ty)
  let spill_store = if x64_core_type(result_ty) == Float {
    "DWORD PTR [rsp], xmm0"
  } else {
    "QWORD PTR [rsp], xmm0"
  }
  let spill_load = if x64_core_type(result_ty) == Float {
    "DWORD PTR [rsp]"
  } else {
    "QWORD PTR [rsp]"
  }
  self.gen_addr(lhs)
  self.emit_push_rax()
  self.emit_load_bitfield_from_addr("rax", info)
  self.emit_int_to_fp(info.ty, result_ty)
  self.emit("\tsub\trsp, 8")
  self.emit("\tmov" + suffix + "\t" + spill_store)
  self.gen_expr_as_fp(rhs, result_ty)
  self.emit("\tmovapd\txmm1, xmm0")
  self.emit("\tmov" + suffix + "\txmm0, " + spill_load)
  self.emit("\tadd\trsp, 8")
  match op {
    "+" => self.emit("\tadd" + suffix + "\txmm0, xmm1")
    "-" => self.emit("\tsub" + suffix + "\txmm0, xmm1")
    "*" => self.emit("\tmul" + suffix + "\txmm0, xmm1")
    "/" => self.emit("\tdiv" + suffix + "\txmm0, xmm1")
    _ =>
      abort("unsupported x86-64 bit-field/floating compound assignment: " + op)
  }
  self.emit_fp_to_scalar(result_ty, info.ty)
  self.emit("\tmov\tr11, rax")
  self.emit_pop_rax()
  self.emit("\tmov\tr10, rax")
  self.emit("\tmov\trax, r11")
  self.emit_store_bitfield_value(info)
  true
}

///|
fn X64Codegen::gen_compound_assign(
  self : X64Codegen,
  op : String,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
) -> Unit {
  match self.bitfield_info(lhs) {
    Some(info) => {
      if self.gen_bitfield_fp_compound_assign(op, lhs, rhs, info) {
        return
      }
      let rhs_ty = self.type_of(rhs)
      let lhs_promoted_ty = x64_bitfield_promoted_type(info)
      let is_integer_compound = lhs_promoted_ty.is_integer() &&
        rhs_ty.is_integer()
      let lhs_eval_ty = if is_integer_compound {
        x64_binary_int_type(op, lhs_promoted_ty, rhs_ty)
      } else {
        lhs_promoted_ty
      }
      let rhs_eval_ty = if is_integer_compound {
        x64_binary_rhs_int_type(op, lhs_promoted_ty, rhs_ty)
      } else {
        rhs_ty
      }
      let unsigned_op = if is_integer_compound {
        is_unsigned_integer_type(lhs_eval_ty)
      } else {
        false
      }
      self.gen_addr(lhs)
      self.emit_push_rax()
      self.emit_load_bitfield_from_addr("rax", info)
      if is_integer_compound {
        self.emit_int_conversion_to(lhs_eval_ty)
      }
      self.emit_push_rax()
      self.gen_expr_as_int(rhs)
      if is_integer_compound {
        self.emit_int_conversion_to(rhs_eval_ty)
      }
      self.emit("\tmov\tr10, rax")
      self.emit_pop_rax()
      match op {
        "+" => self.emit("\tadd\trax, r10")
        "-" => self.emit("\tsub\trax, r10")
        "*" => self.emit("\timul\trax, r10")
        "/" =>
          if unsigned_op {
            self.emit("\txor\trdx, rdx")
            self.emit("\tdiv\tr10")
          } else {
            self.emit("\tcqo")
            self.emit("\tidiv\tr10")
          }
        "%" =>
          if unsigned_op {
            self.emit("\txor\trdx, rdx")
            self.emit("\tdiv\tr10")
            self.emit("\tmov\trax, rdx")
          } else {
            self.emit("\tcqo")
            self.emit("\tidiv\tr10")
            self.emit("\tmov\trax, rdx")
          }
        "&" => self.emit("\tand\trax, r10")
        "|" => self.emit("\tor\trax, r10")
        "^" => self.emit("\txor\trax, r10")
        "<<" => {
          self.emit("\tmov\trcx, r10")
          self.emit("\tshl\trax, cl")
        }
        ">>" => {
          self.emit("\tmov\trcx, r10")
          if unsigned_op {
            self.emit("\tshr\trax, cl")
          } else {
            self.emit("\tsar\trax, cl")
          }
        }
        _ => abort("unsupported x86-64 bit-field compound assignment: " + op)
      }
      self.emit("\tmov\tr11, rax")
      self.emit_pop_rax()
      self.emit("\tmov\tr10, rax")
      self.emit("\tmov\trax, r11")
      self.emit_store_bitfield_value(info)
      return
    }
    None => ()
  }
  let lhs_ty = self.type_of(lhs)
  let rhs_ty = self.type_of(rhs)
  if self.gen_pointer_compound_assign(op, lhs, rhs, lhs_ty, rhs_ty) {
    return
  }
  if lhs_ty.is_integer() && rhs_ty.is_integer() && x64_is_int128_type(lhs_ty) {
    self.gen_int128_compound_assign(op, lhs, rhs, lhs_ty, rhs_ty)
    return
  }
  if x64_is_fp_type(lhs_ty) {
    let spill_store = if lhs_ty == Float {
      "DWORD PTR [rsp], xmm0"
    } else {
      "QWORD PTR [rsp], xmm0"
    }
    let spill_load = if lhs_ty == Float {
      "DWORD PTR [rsp]"
    } else {
      "QWORD PTR [rsp]"
    }
    self.gen_addr(lhs)
    self.emit_push_rax()
    self.emit_load_indirect(lhs_ty)
    self.emit("\tsub\trsp, 8")
    self.emit("\tmov" + x64_fp_suffix(lhs_ty) + "\t" + spill_store)
    self.gen_expr_as_fp(rhs, lhs_ty)
    self.emit("\tmovapd\txmm1, xmm0")
    self.emit("\tmov" + x64_fp_suffix(lhs_ty) + "\txmm0, " + spill_load)
    self.emit("\tadd\trsp, 8")
    match op {
      "+" => self.emit("\tadd" + x64_fp_suffix(lhs_ty) + "\txmm0, xmm1")
      "-" => self.emit("\tsub" + x64_fp_suffix(lhs_ty) + "\txmm0, xmm1")
      "*" => self.emit("\tmul" + x64_fp_suffix(lhs_ty) + "\txmm0, xmm1")
      "/" => self.emit("\tdiv" + x64_fp_suffix(lhs_ty) + "\txmm0, xmm1")
      _ => abort("unsupported x86-64 floating compound assignment: " + op)
    }
    self.emit("\tpop\tr10")
    self.emit_store_indirect(lhs_ty)
    return
  }
  if self.gen_integer_fp_compound_assign(op, lhs, rhs, lhs_ty, rhs_ty) {
    return
  }
  self.gen_addr(lhs)
  self.emit_push_rax()
  self.emit_load_indirect(lhs_ty)
  let is_integer_compound = lhs_ty.is_integer() && rhs_ty.is_integer()
  let lhs_eval_ty = if is_integer_compound {
    x64_binary_int_type(op, lhs_ty, rhs_ty)
  } else {
    lhs_ty
  }
  let rhs_eval_ty = if is_integer_compound {
    x64_binary_rhs_int_type(op, lhs_ty, rhs_ty)
  } else {
    rhs_ty
  }
  let unsigned_op = if is_integer_compound {
    is_unsigned_integer_type(lhs_eval_ty)
  } else {
    false
  }
  if is_integer_compound {
    self.emit_int_conversion_to(lhs_eval_ty)
  }
  self.emit_push_rax()
  self.gen_expr_as_int(rhs)
  if is_integer_compound {
    self.emit_int_conversion_to(rhs_eval_ty)
  }
  self.emit("\tmov\tr10, rax")
  self.emit_pop_rax()
  match op {
    "+" => self.emit("\tadd\trax, r10")
    "-" => self.emit("\tsub\trax, r10")
    "*" => self.emit("\timul\trax, r10")
    "/" =>
      if unsigned_op {
        self.emit("\txor\trdx, rdx")
        self.emit("\tdiv\tr10")
      } else {
        self.emit("\tcqo")
        self.emit("\tidiv\tr10")
      }
    "%" => {
      if unsigned_op {
        self.emit("\txor\trdx, rdx")
        self.emit("\tdiv\tr10")
      } else {
        self.emit("\tcqo")
        self.emit("\tidiv\tr10")
      }
      self.emit("\tmov\trax, rdx")
    }
    "&" => self.emit("\tand\trax, r10")
    "|" => self.emit("\tor\trax, r10")
    "^" => self.emit("\txor\trax, r10")
    "<<" => {
      self.emit("\tmov\trcx, r10")
      self.emit("\tshl\trax, cl")
    }
    ">>" => {
      self.emit("\tmov\trcx, r10")
      if unsigned_op {
        self.emit("\tshr\trax, cl")
      } else {
        self.emit("\tsar\trax, cl")
      }
    }
    _ => abort("unsupported x86-64 compound assignment: " + op)
  }
  if is_integer_compound {
    self.emit_int_conversion_to(lhs_ty)
  }
  self.emit("\tmov\tr11, rax")
  self.emit_pop_rax()
  self.emit("\tmov\tr10, rax")
  self.emit("\tmov\trax, r11")
  self.emit_store_indirect(lhs_ty)
}

///|
fn X64Codegen::gen_inc_dec(
  self : X64Codegen,
  expr : @parser.Expr,
  delta : Int,
  postfix : Bool,
) -> Unit {
  let expr_ty = self.type_of(expr)
  match self.bitfield_info(expr) {
    Some(info) => {
      self.gen_addr(expr)
      self.emit("\tmov\tr10, rax")
      self.emit_load_bitfield_from_addr("r10", info)
      if postfix {
        self.emit_push_rax()
      }
      if delta > 0 {
        self.emit("\tadd\trax, " + delta.to_string())
      } else {
        self.emit("\tsub\trax, " + (-delta).to_string())
      }
      self.emit_store_bitfield_value(info)
      if postfix {
        self.emit_pop_rax()
      }
      return
    }
    None => ()
  }
  if x64_is_fp_type(expr_ty) {
    let suffix = x64_fp_suffix(expr_ty)
    self.gen_addr(expr)
    self.emit_push_rax()
    self.emit_load_indirect(expr_ty)
    if postfix {
      self.emit("\tsub\trsp, 8")
      if x64_core_type(expr_ty) == Float {
        self.emit("\tmovss\tDWORD PTR [rsp], xmm0")
      } else {
        self.emit("\tmovsd\tQWORD PTR [rsp], xmm0")
      }
    }
    self.emit("\tmov\teax, 1")
    if x64_core_type(expr_ty) == Float {
      self.emit("\tcvtsi2ss\txmm1, rax")
    } else {
      self.emit("\tcvtsi2sd\txmm1, rax")
    }
    if delta > 0 {
      self.emit("\tadd" + suffix + "\txmm0, xmm1")
    } else {
      self.emit("\tsub" + suffix + "\txmm0, xmm1")
    }
    if postfix {
      self.emit("\tmov\tr10, QWORD PTR [rsp + 8]")
    } else {
      self.emit("\tpop\tr10")
    }
    self.emit_store_indirect(expr_ty)
    if postfix {
      if x64_core_type(expr_ty) == Float {
        self.emit("\tmovss\txmm0, DWORD PTR [rsp]")
      } else {
        self.emit("\tmovsd\txmm0, QWORD PTR [rsp]")
      }
      self.emit("\tadd\trsp, 16")
    }
    return
  }
  self.gen_addr(expr)
  self.emit_push_rax()
  self.emit_load_indirect(expr_ty)
  if postfix {
    self.emit_push_rax()
  }
  let step = match x64_pointer_element(expr_ty) {
    Some(elem) => self.pointer_element_size(elem)
    None => 1
  }
  let amount = if delta > 0 { delta * step } else { -delta * step }
  if delta > 0 {
    self.emit("\tadd\trax, " + amount.to_string())
  } else {
    self.emit("\tsub\trax, " + amount.to_string())
  }
  self.emit("\tmov\tr11, rax")
  if postfix {
    self.emit("\tpop\trdx")
  }
  self.emit("\tpop\tr10")
  self.emit("\tmov\trax, r11")
  self.emit_store_indirect(expr_ty)
  if postfix {
    self.emit("\tmov\trax, rdx")
  }
}

///|
fn X64Codegen::is_variadic_call(self : X64Codegen, func : @parser.Expr) -> Bool {
  match self.type_of(func) {
    FuncPtr(_, _, variadic) => variadic
    _ =>
      match func {
        Var(name) =>
          if self.func_variadic.get_or_default(name, false) {
            true
          } else {
            match name {
              "printf"
              | "fprintf"
              | "sprintf"
              | "snprintf"
              | "scanf"
              | "fscanf"
              | "sscanf"
              | "open"
              | "fcntl"
              | "ioctl" => true
              _ => false
            }
          }
        _ => false
      }
  }
}

///|
fn X64Codegen::is_direct_call(self : X64Codegen, func : @parser.Expr) -> Bool {
  match func {
    Var(name) =>
      !self.local_offsets.contains(name) && !self.globals.contains(name)
    _ => false
  }
}

///|
fn X64Codegen::gen_callee_addr(self : X64Codegen, func : @parser.Expr) -> Unit {
  match func {
    Deref(ptr) => self.gen_expr(ptr)
    _ => self.gen_expr(func)
  }
}

///|
fn x64_default_argument_promotion(ty : @parser.Type) -> @parser.Type {
  match x64_core_type(ty) {
    Bool | SChar | UChar | SShort | UShort => SInt
    Float => Double
    _ => ty
  }
}

///|
fn X64Codegen::declared_call_arg_type(
  self : X64Codegen,
  func : @parser.Expr,
  index : Int,
  actual : @parser.Type,
  named_count_limit : Int?,
) -> @parser.Type {
  match named_count_limit {
    Some(limit) =>
      if index >= limit {
        return x64_default_argument_promotion(actual)
      }
    None => ()
  }
  match self.type_of(func) {
    FuncPtr(_, params, false) =>
      if params.length() == 0 {
        return x64_default_argument_promotion(actual)
      } else if index < params.length() {
        return params[index]
      }
    FuncPtr(_, params, true) =>
      if index < params.length() {
        return params[index]
      }
    _ => ()
  }
  match func {
    Var(name) =>
      if self.func_param_types.contains(name) {
        let param_types = self.func_param_types[name]
        if index < param_types.length() {
          param_types[index]
        } else {
          actual
        }
      } else {
        actual
      }
    _ => actual
  }
}

///|
fn X64Codegen::named_call_arg_count(
  self : X64Codegen,
  func : @parser.Expr,
) -> Int {
  match self.type_of(func) {
    FuncPtr(_, params, true) => params.length()
    _ =>
      match func {
        Var(name) =>
          if self.func_param_counts.contains(name) {
            self.func_param_counts[name]
          } else {
            match name {
              "printf" | "scanf" => 1
              "fprintf"
              | "sprintf"
              | "fscanf"
              | "sscanf"
              | "open"
              | "fcntl"
              | "ioctl" => 2
              "snprintf" => 3
              _ => 0
            }
          }
        _ => 0
      }
  }
}

///|
fn X64Codegen::gen_call(
  self : X64Codegen,
  func : @parser.Expr,
  args : Array[@parser.Expr],
) -> Unit {
  let arg_regs = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
  let fp_arg_regs = [
    "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7",
  ]
  let arg_is_fp : Array[Bool] = []
  let arg_is_aggregate : Array[Bool] = []
  let arg_classes : Array[Array[X64AggregateClass]] = []
  let arg_words : Array[Int] = []
  let arg_int_reg_index : Array[Int] = []
  let arg_fp_reg_index : Array[Int] = []
  let arg_stack_index : Array[Int] = []
  let arg_temp_index : Array[Int] = []
  let ret_ty = self.type_of(Call(func, args))
  x64_reject_unsupported_scalar(ret_ty)
  let has_sret = self.is_memory_aggregate(ret_ty)
  let indirect_call = !self.is_direct_call(func)
  let is_variadic = self.is_variadic_call(func)
  let named_count_limit = if is_variadic {
    Some(self.named_call_arg_count(func))
  } else {
    None
  }
  let arg_types : Array[@parser.Type] = []
  let mut int_count = if has_sret { 1 } else { 0 }
  let mut fp_count = 0
  let mut stack_count = 0
  let mut call_stack_align = 16
  let mut temp_count = 0
  for i = 0; i < args.length(); i = i + 1 {
    let actual_ty = self.type_of(args[i])
    let arg_ty = self.declared_call_arg_type(
      func, i, actual_ty, named_count_limit,
    )
    x64_reject_unsupported_scalar(arg_ty)
    arg_types.push(arg_ty)
    if x64_is_fp_type(arg_ty) {
      arg_is_fp.push(true)
      arg_is_aggregate.push(false)
      arg_classes.push([])
      arg_words.push(1)
      arg_temp_index.push(temp_count)
      temp_count += 1
      if fp_count < fp_arg_regs.length() {
        arg_int_reg_index.push(-1)
        arg_fp_reg_index.push(fp_count)
        arg_stack_index.push(-1)
        fp_count += 1
      } else {
        arg_int_reg_index.push(-1)
        arg_fp_reg_index.push(-1)
        let (aligned_stack_count, aligned_call_stack_align) = self.align_call_stack_arg(
          stack_count, call_stack_align, arg_ty,
        )
        stack_count = aligned_stack_count
        call_stack_align = aligned_call_stack_align
        arg_stack_index.push(stack_count)
        stack_count += 1
      }
    } else if x64_is_aggregate_type(arg_ty) {
      let classes = match self.aggregate_classes(arg_ty) {
        Some(classes) => classes
        None => {
          let words = self.aggregate_word_count(arg_ty)
          arg_is_fp.push(false)
          arg_is_aggregate.push(true)
          arg_classes.push([])
          arg_words.push(words)
          arg_temp_index.push(temp_count)
          temp_count += words
          arg_int_reg_index.push(-1)
          arg_fp_reg_index.push(-1)
          let (aligned_stack_count, aligned_call_stack_align) = self.align_call_stack_arg(
            stack_count, call_stack_align, arg_ty,
          )
          stack_count = aligned_stack_count
          call_stack_align = aligned_call_stack_align
          arg_stack_index.push(stack_count)
          stack_count += words
          continue
        }
      }
      let words = classes.length()
      let int_needed = x64_class_count(classes, IntClass)
      let fp_needed = x64_class_count(classes, SseClass)
      arg_is_fp.push(false)
      arg_is_aggregate.push(true)
      arg_classes.push(classes)
      arg_words.push(words)
      arg_temp_index.push(temp_count)
      temp_count += words
      if int_count + int_needed <= arg_regs.length() &&
        fp_count + fp_needed <= fp_arg_regs.length() {
        arg_int_reg_index.push(int_count)
        arg_fp_reg_index.push(fp_count)
        arg_stack_index.push(-1)
        int_count += int_needed
        fp_count += fp_needed
      } else {
        arg_int_reg_index.push(-1)
        arg_fp_reg_index.push(-1)
        let (aligned_stack_count, aligned_call_stack_align) = self.align_call_stack_arg(
          stack_count, call_stack_align, arg_ty,
        )
        stack_count = aligned_stack_count
        call_stack_align = aligned_call_stack_align
        arg_stack_index.push(stack_count)
        stack_count += words
      }
    } else if x64_is_int128_type(arg_ty) {
      arg_is_fp.push(false)
      arg_is_aggregate.push(false)
      arg_classes.push([])
      arg_words.push(2)
      arg_temp_index.push(temp_count)
      temp_count += 2
      if int_count + 2 <= arg_regs.length() {
        arg_int_reg_index.push(int_count)
        arg_fp_reg_index.push(-1)
        arg_stack_index.push(-1)
        int_count += 2
      } else {
        arg_int_reg_index.push(-1)
        arg_fp_reg_index.push(-1)
        let (aligned_stack_count, aligned_call_stack_align) = self.align_call_stack_arg(
          stack_count, call_stack_align, arg_ty,
        )
        stack_count = aligned_stack_count
        call_stack_align = aligned_call_stack_align
        arg_stack_index.push(stack_count)
        stack_count += 2
      }
    } else {
      arg_is_fp.push(false)
      arg_is_aggregate.push(false)
      arg_classes.push([])
      arg_words.push(1)
      arg_temp_index.push(temp_count)
      temp_count += 1
      if int_count < arg_regs.length() {
        arg_int_reg_index.push(int_count)
        arg_fp_reg_index.push(-1)
        arg_stack_index.push(-1)
        int_count += 1
      } else {
        arg_int_reg_index.push(-1)
        arg_fp_reg_index.push(-1)
        let (aligned_stack_count, aligned_call_stack_align) = self.align_call_stack_arg(
          stack_count, call_stack_align, arg_ty,
        )
        stack_count = aligned_stack_count
        call_stack_align = aligned_call_stack_align
        arg_stack_index.push(stack_count)
        stack_count += 1
      }
    }
  }
  let save_area = 16
  let save_temp_area = x64_align_to(
    save_area + temp_count * 8,
    call_stack_align,
  )
  let call_area = x64_align_to(stack_count * 8, call_stack_align)
  self.emit("\tmov\tr11, rsp")
  self.emit("\tand\trsp, -" + call_stack_align.to_string())
  self.emit("\tsub\trsp, " + save_temp_area.to_string())
  self.emit("\tmov\tQWORD PTR [rsp], r11")
  if indirect_call {
    self.gen_callee_addr(func)
    self.emit("\tmov\tQWORD PTR [rsp + 8], rax")
  }
  for i = 0; i < args.length(); i = i + 1 {
    let arg_ty = arg_types[i]
    let slot = save_area + arg_temp_index[i] * 8
    if arg_is_aggregate[i] {
      match args[i] {
        Call(_, _) if self.is_supported_small_aggregate(arg_ty) => {
          self.gen_expr(args[i])
          self.emit("\tlea\tr10, " + x64_rsp_ref(slot))
          self.emit_store_small_aggregate_return(arg_ty)
        }
        _ => {
          self.gen_aggregate_addr(args[i])
          self.emit("\tmov\tr11, rax")
          self.emit("\tlea\tr10, " + x64_rsp_ref(slot))
          self.emit_copy_aggregate_from_addr(arg_ty)
        }
      }
    } else if x64_is_fp_type(arg_ty) {
      self.gen_expr_as_fp(args[i], arg_ty)
      match x64_core_type(arg_ty) {
        Float => {
          self.emit("\tmov\tQWORD PTR " + x64_rsp_ref(slot) + ", 0")
          self.emit("\tmovss\tDWORD PTR " + x64_rsp_ref(slot) + ", xmm0")
        }
        _ => self.emit("\tmovsd\tQWORD PTR " + x64_rsp_ref(slot) + ", xmm0")
      }
    } else {
      self.gen_expr_as_scalar(args[i], arg_ty)
      self.emit("\tmov\tQWORD PTR " + x64_rsp_ref(slot) + ", rax")
      if x64_is_int128_type(arg_ty) {
        self.emit("\tmov\tQWORD PTR " + x64_rsp_ref(slot + 8) + ", rdx")
      }
    }
  }
  if call_area > 0 {
    self.emit("\tsub\trsp, " + call_area.to_string())
  }
  for i = 0; i < args.length(); i = i + 1 {
    let stack_index = arg_stack_index[i]
    if stack_index >= 0 {
      let src_off = call_area + save_area + arg_temp_index[i] * 8
      let dst_off = stack_index * 8
      if arg_is_aggregate[i] && arg_classes[i].length() > 0 {
        for word in 0..<arg_words[i] {
          let width = self.aggregate_word_width(arg_types[i], word)
          self.emit_load_int_bytes_from_mem_reg(
            "rax",
            "rsp",
            src_off + word * 8,
            width,
          )
          self.emit_store_int_bytes_to_mem_reg(
            "rax",
            "rsp",
            dst_off + word * 8,
            width,
          )
        }
      } else {
        for word in 0..<arg_words[i] {
          self.emit("\tmov\trax, QWORD PTR " + x64_rsp_ref(src_off + word * 8))
          self.emit(
            "\tmov\tQWORD PTR " + x64_rsp_ref(dst_off + word * 8) + ", rax",
          )
        }
      }
    }
  }
  for i = 0; i < args.length(); i = i + 1 {
    let int_reg_index = arg_int_reg_index[i]
    let fp_reg_index = arg_fp_reg_index[i]
    let src_off = call_area + save_area + arg_temp_index[i] * 8
    if arg_is_fp[i] && fp_reg_index >= 0 {
      let arg_ty = arg_types[i]
      match x64_core_type(arg_ty) {
        Float =>
          self.emit(
            "\tmovss\t" +
            fp_arg_regs[fp_reg_index] +
            ", DWORD PTR " +
            x64_rsp_ref(src_off),
          )
        _ =>
          self.emit(
            "\tmovsd\t" +
            fp_arg_regs[fp_reg_index] +
            ", QWORD PTR " +
            x64_rsp_ref(src_off),
          )
      }
    } else if arg_is_aggregate[i] && arg_stack_index[i] < 0 {
      let mut int_cursor = int_reg_index
      let mut fp_cursor = fp_reg_index
      for word in 0..<arg_words[i] {
        let width = self.aggregate_word_width(arg_types[i], word)
        match arg_classes[i][word] {
          IntClass => {
            self.emit_load_int_bytes_from_mem_reg(
              arg_regs[int_cursor],
              "rsp",
              src_off + word * 8,
              width,
            )
            int_cursor += 1
          }
          SseClass => {
            self.emit_load_sse_word_from_mem_reg(
              fp_arg_regs[fp_cursor],
              "rsp",
              src_off + word * 8,
              width,
            )
            fp_cursor += 1
          }
        }
      }
    } else if int_reg_index >= 0 {
      if x64_is_int128_type(arg_types[i]) {
        self.emit(
          "\tmov\t" +
          arg_regs[int_reg_index] +
          ", QWORD PTR " +
          x64_rsp_ref(src_off),
        )
        self.emit(
          "\tmov\t" +
          arg_regs[int_reg_index + 1] +
          ", QWORD PTR " +
          x64_rsp_ref(src_off + 8),
        )
      } else {
        self.emit(
          "\tmov\t" +
          arg_regs[int_reg_index] +
          ", QWORD PTR " +
          x64_rsp_ref(src_off),
        )
      }
    }
  }
  let vector_count = if is_variadic { fp_count } else { 0 }
  self.emit("\tmov\tal, " + vector_count.to_string())
  self.emit_call_sret_addr(ret_ty)
  if indirect_call {
    self.emit("\tcall\tQWORD PTR " + x64_rsp_ref(call_area + 8))
  } else {
    match func {
      Var(name) => self.emit("\tcall\t" + name)
      _ => abort("unreachable x86-64 direct call")
    }
  }
  self.emit_abi_int_return_conversion(ret_ty)
  self.emit("\tmov\trsp, QWORD PTR " + x64_rsp_ref(call_area))
}

///|
fn X64Codegen::emit_va_arg(
  self : X64Codegen,
  ap_expr : @parser.Expr,
  ty : @parser.Type,
) -> Unit {
  x64_reject_unsupported_scalar(ty)
  if x64_is_aggregate_type(ty) {
    self.emit_va_arg_aggregate_addr(ap_expr, ty)
    return
  }
  let overflow_label = self.new_label()
  let load_label = self.new_label()
  if x64_is_fp_type(ty) {
    self.gen_expr(ap_expr)
    self.emit("\tmov\tr11, rax")
    self.emit("\tmov\teax, DWORD PTR [r11 + 4]")
    self.emit("\tcmp\teax, 176")
    self.emit("\tjae\t" + overflow_label)
    self.emit("\tmov\tr10, QWORD PTR [r11 + 16]")
    self.emit("\tadd\tr10, rax")
    self.emit("\tadd\tDWORD PTR [r11 + 4], 16")
    self.emit("\tjmp\t" + load_label)
    self.emit(overflow_label + ":")
    self.emit("\tmov\tr10, QWORD PTR [r11 + 8]")
    self.emit("\tlea\trax, [r10 + 8]")
    self.emit("\tmov\tQWORD PTR [r11 + 8], rax")
    self.emit(load_label + ":")
    self.emit("\tmov\trax, r10")
    self.emit_load_indirect(ty)
  } else {
    let gp_limit = if x64_is_int128_type(ty) { 32 } else { 48 }
    let gp_step = if x64_is_int128_type(ty) { 16 } else { 8 }
    self.gen_expr(ap_expr)
    self.emit("\tmov\tr11, rax")
    self.emit("\tmov\teax, DWORD PTR [r11]")
    self.emit("\tcmp\teax, " + gp_limit.to_string())
    if x64_is_int128_type(ty) {
      self.emit("\tja\t" + overflow_label)
    } else {
      self.emit("\tjae\t" + overflow_label)
    }
    self.emit("\tmov\tr10, QWORD PTR [r11 + 16]")
    self.emit("\tadd\tr10, rax")
    self.emit("\tadd\tDWORD PTR [r11], " + gp_step.to_string())
    self.emit("\tjmp\t" + load_label)
    self.emit(overflow_label + ":")
    self.emit("\tmov\tr10, QWORD PTR [r11 + 8]")
    if x64_is_int128_type(ty) {
      self.emit("\tadd\tr10, 15")
      self.emit("\tand\tr10, -16")
    }
    self.emit("\tlea\trax, [r10 + " + gp_step.to_string() + "]")
    self.emit("\tmov\tQWORD PTR [r11 + 8], rax")
    self.emit(load_label + ":")
    self.emit("\tmov\trax, r10")
    self.emit_load_indirect(ty)
  }
}

///|
fn X64Codegen::emit_copy_va_arg_overflow_aggregate(
  self : X64Codegen,
  ty : @parser.Type,
) -> Unit {
  self.emit("\tmov\tr10, QWORD PTR [r11 + 8]")
  let align = self.type_align(ty)
  if align > 8 {
    self.emit("\tadd\tr10, " + (align - 1).to_string())
    self.emit("\tand\tr10, -" + align.to_string())
  }
  let overflow_size = x64_align_to(self.type_size(ty), 8)
  self.emit("\tlea\trax, [r10 + " + overflow_size.to_string() + "]")
  self.emit("\tmov\tQWORD PTR [r11 + 8], rax")
  self.emit("\tmov\tr11, r10")
  self.emit("\tlea\tr10, " + self.local_ref(self.va_arg_scratch_offset))
  self.emit_copy_aggregate_from_addr(ty)
  self.emit("\tmov\trax, r10")
}

///|
fn X64Codegen::emit_va_arg_aggregate_addr(
  self : X64Codegen,
  ap_expr : @parser.Expr,
  ty : @parser.Type,
) -> Unit {
  if self.va_arg_scratch_offset < 0 {
    abort("x86-64 backend missing aggregate va_arg scratch storage")
  }
  let overflow_label = self.new_label()
  let done_label = self.new_label()
  self.gen_expr(ap_expr)
  self.emit("\tmov\tr11, rax")
  let classes = match self.aggregate_classes(ty) {
    Some(classes) => classes
    None => {
      self.emit_copy_va_arg_overflow_aggregate(ty)
      return
    }
  }
  let int_needed = x64_class_count(classes, IntClass)
  let fp_needed = x64_class_count(classes, SseClass)
  if int_needed > 0 {
    let gp_limit = 48 - int_needed * 8
    self.emit("\tmov\teax, DWORD PTR [r11]")
    self.emit("\tcmp\teax, " + gp_limit.to_string())
    self.emit("\tja\t" + overflow_label)
  }
  if fp_needed > 0 {
    let fp_limit = 176 - fp_needed * 16
    self.emit("\tmov\tecx, DWORD PTR [r11 + 4]")
    self.emit("\tcmp\tecx, " + fp_limit.to_string())
    self.emit("\tja\t" + overflow_label)
  }
  self.emit("\tmov\tr9, QWORD PTR [r11 + 16]")
  if int_needed > 0 {
    self.emit("\tmov\teax, DWORD PTR [r11]")
  }
  if fp_needed > 0 {
    self.emit("\tmov\tecx, DWORD PTR [r11 + 4]")
  }
  self.emit("\tlea\tr10, " + self.local_ref(self.va_arg_scratch_offset))
  let mut int_cursor = 0
  let mut fp_cursor = 0
  for word in 0..<classes.length() {
    let width = self.aggregate_word_width(ty, word)
    match classes[word] {
      IntClass => {
        self.emit("\tmov\tr8d, eax")
        if int_cursor > 0 {
          self.emit("\tadd\tr8, " + (int_cursor * 8).to_string())
        }
        self.emit("\tmov\trdx, QWORD PTR [r9 + r8]")
        self.emit_store_int_bytes_to_mem_reg("rdx", "r10", word * 8, width)
        int_cursor += 1
      }
      SseClass => {
        self.emit("\tmov\tr8d, ecx")
        if fp_cursor > 0 {
          self.emit("\tadd\tr8, " + (fp_cursor * 16).to_string())
        }
        if width <= 4 {
          self.emit("\tmovss\txmm0, DWORD PTR [r9 + r8]")
        } else {
          self.emit("\tmovsd\txmm0, QWORD PTR [r9 + r8]")
        }
        self.emit_store_sse_word_to_mem_reg("xmm0", "r10", word * 8, width)
        fp_cursor += 1
      }
    }
  }
  if int_needed > 0 {
    self.emit("\tadd\tDWORD PTR [r11], " + (int_needed * 8).to_string())
  }
  if fp_needed > 0 {
    self.emit("\tadd\tDWORD PTR [r11 + 4], " + (fp_needed * 16).to_string())
  }
  self.emit("\tmov\trax, r10")
  self.emit("\tjmp\t" + done_label)
  self.emit(overflow_label + ":")
  self.emit_copy_va_arg_overflow_aggregate(ty)
  self.emit(done_label + ":")
}

///|
fn X64Codegen::gen_expr(self : X64Codegen, expr : @parser.Expr) -> Unit {
  match expr {
    Number(value) => self.emit("\tmov\trax, " + value.to_string())
    FloatLiteral(value) => self.emit_load_fp_literal(value)
    String(value) => {
      let id = self.strings.length()
      self.strings.push(value)
      self.emit("\tlea\trax, [rip + .Lstr" + id.to_string() + "]")
    }
    Var(name) =>
      if !self.local_offsets.contains(name) &&
        !self.globals.contains(name) &&
        self.func_rets.contains(name) {
        self.emit("\tlea\trax, [rip + " + name + "]")
      } else {
        self.gen_addr(Var(name))
        match x64_core_type(self.type_of(expr)) {
          Array(_, _) | Struct(_) | Union(_) => ()
          _ => self.emit_load_indirect(self.type_of(expr))
        }
      }
    Binary(op, lhs, rhs) => self.gen_binary(op, lhs, rhs)
    Unary("-", e) => {
      let ty = self.type_of(e)
      if x64_is_fp_type(ty) {
        self.gen_expr(e)
        match x64_core_type(ty) {
          Float => {
            self.emit("\tmov\teax, -2147483648")
            self.emit("\tmovd\txmm1, eax")
            self.emit("\txorps\txmm0, xmm1")
          }
          _ => {
            self.emit("\tmovabs\trax, -9223372036854775808")
            self.emit("\tmovq\txmm1, rax")
            self.emit("\txorpd\txmm0, xmm1")
          }
        }
      } else {
        self.gen_expr(e)
        if x64_is_int128_type(ty) {
          self.emit("\tneg\trdx")
          self.emit("\tneg\trax")
          self.emit("\tsbb\trdx, 0")
        } else {
          self.emit("\tneg\trax")
        }
      }
    }
    Unary("+", e) => self.gen_expr(e)
    Unary("~", e) => {
      self.gen_expr(e)
      if x64_is_int128_type(self.type_of(e)) {
        self.emit("\tnot\trax")
        self.emit("\tnot\trdx")
      } else {
        self.emit("\tnot\trax")
      }
    }
    Unary("!", e) => {
      self.gen_expr(e)
      let ty = self.type_of(e)
      if x64_is_fp_type(ty) {
        self.emit_fp_to_bool(ty)
        self.emit("\tcmp\trax, 0")
        self.emit_setcc("sete")
      } else if x64_is_int128_type(ty) {
        self.emit("\tor\trax, rdx")
        self.emit_setcc("sete")
      } else {
        self.emit("\tcmp\trax, 0")
        self.emit_setcc("sete")
      }
    }
    Unary("*", e) | Deref(e) => {
      self.gen_expr(e)
      self.emit_load_indirect(self.type_of(expr))
    }
    Unary("&", e) | AddrOf(e) => self.gen_addr(e)
    Unary(op, _) => abort("unsupported x86-64 unary operator: " + op)
    Call(func, args) => {
      let handled = match func {
        Var(name) => self.emit_builtin_call(name, args)
        _ => false
      }
      if !handled {
        self.gen_call(func, args)
      }
    }
    Assign(lhs, rhs) => self.gen_assign(lhs, rhs)
    CompoundAssign(op, lhs, rhs) => self.gen_compound_assign(op, lhs, rhs)
    MemberAccess(_, _) => {
      self.gen_addr(expr)
      match self.bitfield_info(expr) {
        Some(info) => self.emit_load_bitfield_from_addr("rax", info)
        None => self.emit_load_indirect(self.type_of(expr))
      }
    }
    ArrayAccess(_, _) => {
      self.gen_addr(expr)
      self.emit_load_indirect(self.type_of(expr))
    }
    Sizeof(ty) => self.emit("\tmov\trax, " + self.type_size(ty).to_string())
    SizeofExpr(e) =>
      self.emit("\tmov\trax, " + self.type_size(self.type_of(e)).to_string())
    Alignof(ty) => self.emit("\tmov\trax, " + self.type_align(ty).to_string())
    AlignofExpr(e) =>
      self.emit("\tmov\trax, " + self.type_align(self.type_of(e)).to_string())
    Cast(ty, e) => self.gen_expr_as_scalar(e, ty)
    PrefixInc(e) => self.gen_inc_dec(e, 1, false)
    PrefixDec(e) => self.gen_inc_dec(e, -1, false)
    PostfixInc(e) => self.gen_inc_dec(e, 1, true)
    PostfixDec(e) => self.gen_inc_dec(e, -1, true)
    Ternary(cond, then_, else_) => {
      let else_label = self.new_label()
      let end_label = self.new_label()
      let result_ty = self.type_of(expr)
      self.gen_cond_jump_false(cond, else_label)
      if x64_is_fp_type(result_ty) {
        self.gen_expr_as_fp(then_, result_ty)
      } else if x64_is_object_aggregate_type(result_ty) {
        self.gen_expr(then_)
      } else {
        self.gen_expr_as_scalar(then_, result_ty)
      }
      self.emit("\tjmp\t" + end_label)
      self.emit(else_label + ":")
      if x64_is_fp_type(result_ty) {
        self.gen_expr_as_fp(else_, result_ty)
      } else if x64_is_object_aggregate_type(result_ty) {
        self.gen_expr(else_)
      } else {
        self.gen_expr_as_scalar(else_, result_ty)
      }
      self.emit(end_label + ":")
    }
    LabelAddr(name) =>
      self.emit("\tlea\trax, [rip + " + self.label_ref(name) + "]")
    OffsetOf(ty, path) => {
      let offset = match self.offset_of_path(ty, path) {
        Some(value) => value
        None => 0
      }
      self.emit("\tmov\trax, " + offset.to_string())
    }
    VaArg(ap_expr, ty) => self.emit_va_arg(ap_expr, ty)
    Array(_) => abort("x86-64 backend does not support array expressions yet")
    CompoundLiteral(ty, init_exprs, id) => {
      self.gen_compound_literal_addr(ty, init_exprs, id)
      if !x64_is_object_aggregate_type(ty) {
        self.emit_load_indirect(ty)
      }
    }
    DesignatedField(_, e) | DesignatedIndex(_, e) | DesignatedRange(_, _, e) =>
      self.gen_expr(e)
  }
}

///|
fn X64Codegen::collect_expr_locals(
  self : X64Codegen,
  expr : @parser.Expr,
) -> Unit {
  match expr {
    Binary(_, lhs, rhs) | Assign(lhs, rhs) | CompoundAssign(_, lhs, rhs) => {
      self.collect_expr_locals(lhs)
      self.collect_expr_locals(rhs)
    }
    Unary(_, e)
    | Deref(e)
    | AddrOf(e)
    | SizeofExpr(e)
    | AlignofExpr(e)
    | Cast(_, e)
    | PrefixInc(e)
    | PrefixDec(e)
    | PostfixInc(e)
    | PostfixDec(e)
    | DesignatedField(_, e)
    | DesignatedIndex(_, e)
    | DesignatedRange(_, _, e) => self.collect_expr_locals(e)
    Call(func, args) => {
      let ret_ty = self.type_of(expr)
      if self.is_memory_aggregate(ret_ty) {
        let size = self.type_size(ret_ty)
        if size > self.sret_scratch_size {
          self.sret_scratch_size = size
        }
        let align = self.type_align(ret_ty)
        if align > self.sret_scratch_align {
          self.sret_scratch_align = align
        }
      }
      match func {
        Var("__builtin_va_start") | Var("__builtin_va_copy") =>
          match args.get(0) {
            Some(Var(name)) => {
              let _ = self.ensure_va_list_storage(name)
            }
            _ => ()
          }
        _ => ()
      }
      self.collect_expr_locals(func)
      for arg in args {
        self.collect_expr_locals(arg)
      }
    }
    VaArg(ap_expr, ty) => {
      if x64_is_aggregate_type(ty) {
        let size = self.type_size(ty)
        if size > self.va_arg_scratch_size {
          self.va_arg_scratch_size = size
        }
        let align = self.type_align(ty)
        if align > self.va_arg_scratch_align {
          self.va_arg_scratch_align = align
        }
      }
      self.collect_expr_locals(ap_expr)
    }
    MemberAccess(obj, _) => self.collect_expr_locals(obj)
    ArrayAccess(arr, index) => {
      self.collect_expr_locals(arr)
      self.collect_expr_locals(index)
    }
    Ternary(cond, then_, else_) => {
      self.collect_expr_locals(cond)
      self.collect_expr_locals(then_)
      self.collect_expr_locals(else_)
    }
    Array(values) =>
      for value in values {
        self.collect_expr_locals(value)
      }
    CompoundLiteral(ty, values, id) => {
      let _ = self.alloc_local(compound_literal_local_name(id), ty)
      for value in values {
        self.collect_expr_locals(value)
      }
    }
    _ => ()
  }
}

///|
fn X64Codegen::collect_stmt_locals(
  self : X64Codegen,
  stmt : @parser.Stmt,
) -> Unit {
  match stmt {
    VarDecl(ty, name, init) => {
      let _ = self.alloc_local(name, ty)
      match init {
        Some(expr) => self.collect_expr_locals(expr)
        None => ()
      }
    }
    Compound(stmts) | StmtList(stmts) =>
      for s in stmts {
        self.collect_stmt_locals(s)
      }
    ExprStmt(expr) => self.collect_expr_locals(expr)
    Return(Some(expr)) => self.collect_expr_locals(expr)
    Return(None) => ()
    If(cond, then_, else_) => {
      self.collect_expr_locals(cond)
      self.collect_stmt_locals(then_)
      match else_ {
        Some(stmt) => self.collect_stmt_locals(stmt)
        None => ()
      }
    }
    While(cond, body) | DoWhile(cond, body) => {
      self.collect_expr_locals(cond)
      self.collect_stmt_locals(body)
    }
    For(init, cond, inc, body) => {
      match init {
        Some(stmt) => self.collect_stmt_locals(stmt)
        None => ()
      }
      self.collect_expr_locals(cond)
      match inc {
        Some(expr) => self.collect_expr_locals(expr)
        None => ()
      }
      self.collect_stmt_locals(body)
    }
    Switch(expr, body, _) => {
      self.collect_expr_locals(expr)
      self.collect_stmt_locals(body)
    }
    Label(_, stmt) => self.collect_stmt_locals(stmt)
    ComputedGoto(expr) => self.collect_expr_locals(expr)
    Break | Continue | Goto(_) => ()
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
fn X64Codegen::gen_stmt(self : X64Codegen, stmt : @parser.Stmt) -> Unit {
  match stmt {
    Compound(stmts) => {
      let saved_offsets = self.local_offsets.copy()
      let saved_types = self.var_types.copy()
      for s in stmts {
        self.gen_stmt(s)
      }
      self.local_offsets = saved_offsets
      self.var_types = saved_types
    }
    StmtList(stmts) =>
      for s in stmts {
        self.gen_stmt(s)
      }
    ExprStmt(expr) => self.gen_expr(expr)
    Return(None) => {
      self.emit("\tmov\trax, 0")
      self.emit("\tjmp\t.L" + self.func_name + "_ret")
    }
    Return(Some(expr)) => {
      let ret_ty = self.func_rets[self.func_name]
      if self.is_supported_small_aggregate(ret_ty) {
        match expr {
          Call(_, _) => self.gen_expr(expr)
          _ => {
            self.gen_aggregate_addr(expr)
            self.emit_load_small_aggregate_return(ret_ty)
          }
        }
      } else if x64_is_aggregate_type(ret_ty) {
        self.gen_aggregate_addr(expr)
        self.emit("\tmov\tr11, rax")
        self.emit(
          "\tmov\tr10, QWORD PTR " + self.local_ref(self.sret_dest_offset),
        )
        self.emit_copy_aggregate_from_addr(ret_ty)
        self.emit("\tmov\trax, r10")
      } else if x64_is_fp_type(ret_ty) {
        self.gen_expr_as_fp(expr, ret_ty)
      } else {
        self.gen_expr_as_scalar(expr, ret_ty)
      }
      self.emit("\tjmp\t.L" + self.func_name + "_ret")
    }
    VarDecl(ty, name, init) => {
      let offset = self.alloc_local(name, ty)
      match init {
        Some(expr) =>
          if x64_is_object_aggregate_type(ty) {
            self.emit_local_addr(offset)
            self.emit_init_value_at_addr(ty, expr)
          } else {
            self.gen_expr_as_scalar(expr, ty)
            self.emit_store_local_from_rax(offset, ty)
          }
        None => ()
      }
    }
    If(cond, then_, else_) => {
      let else_label = self.new_label()
      let end_label = self.new_label()
      self.gen_cond_jump_false(cond, else_label)
      self.gen_stmt(then_)
      self.emit("\tjmp\t" + end_label)
      self.emit(else_label + ":")
      match else_ {
        Some(stmt) => self.gen_stmt(stmt)
        None => ()
      }
      self.emit(end_label + ":")
    }
    While(cond, body) => {
      let start_label = self.new_label()
      let end_label = self.new_label()
      let old_break = self.break_label
      let old_continue = self.continue_label
      self.break_label = Some(end_label)
      self.continue_label = Some(start_label)
      self.emit(start_label + ":")
      self.gen_cond_jump_false(cond, end_label)
      self.gen_stmt(body)
      self.emit("\tjmp\t" + start_label)
      self.emit(end_label + ":")
      self.break_label = old_break
      self.continue_label = old_continue
    }
    DoWhile(cond, body) => {
      let start_label = self.new_label()
      let end_label = self.new_label()
      let old_break = self.break_label
      let old_continue = self.continue_label
      self.break_label = Some(end_label)
      self.continue_label = Some(start_label)
      self.emit(start_label + ":")
      self.gen_stmt(body)
      self.gen_cond_jump_false(cond, end_label)
      self.emit("\tjmp\t" + start_label)
      self.emit(end_label + ":")
      self.break_label = old_break
      self.continue_label = old_continue
    }
    For(init, cond, inc, body) => {
      let start_label = self.new_label()
      let continue_label = self.new_label()
      let end_label = self.new_label()
      let old_break = self.break_label
      let old_continue = self.continue_label
      self.break_label = Some(end_label)
      self.continue_label = Some(continue_label)
      match init {
        Some(stmt) => self.gen_stmt(stmt)
        None => ()
      }
      self.emit(start_label + ":")
      self.gen_cond_jump_false(cond, end_label)
      self.gen_stmt(body)
      self.emit(continue_label + ":")
      match inc {
        Some(expr) => self.gen_expr(expr)
        None => ()
      }
      self.emit("\tjmp\t" + start_label)
      self.emit(end_label + ":")
      self.break_label = old_break
      self.continue_label = old_continue
    }
    Break =>
      match self.break_label {
        Some(label) => self.emit("\tjmp\t" + label)
        None => abort("break outside loop")
      }
    Continue =>
      match self.continue_label {
        Some(label) => self.emit("\tjmp\t" + label)
        None => abort("continue outside loop")
      }
    Goto(name) => self.emit("\tjmp\t" + self.label_ref(name))
    Label(name, stmt) => {
      let label = self.label_ref(name)
      self.defined_labels[name] = true
      self.emit(label + ":")
      self.gen_stmt(stmt)
    }
    Switch(expr, body, cases) => {
      let end_label = self.new_label()
      let old_break = self.break_label
      self.break_label = Some(end_label)
      let control_ty = switch_control_type(self.type_of(expr))
      self.gen_expr_as_scalar(expr, control_ty)
      for c in cases {
        match c.0 {
          Some(value) => {
            self.emit_switch_case_compare(value, control_ty)
            self.emit("\tje\t" + self.label_ref(c.1))
          }
          None => ()
        }
      }
      let mut default_label = end_label
      for c in cases {
        match c.0 {
          None => {
            default_label = self.label_ref(c.1)
            break
          }
          Some(_) => ()
        }
      }
      self.emit("\tjmp\t" + default_label)
      self.gen_stmt(body)
      self.emit(end_label + ":")
      self.break_label = old_break
    }
    ComputedGoto(expr) => {
      self.gen_expr(expr)
      self.emit("\tjmp\trax")
    }
  }
}

///|
fn X64Codegen::emit_function(
  self : X64Codegen,
  decl : @parser.FuncDecl,
) -> Unit {
  match decl.body {
    None => return
    Some(body) => {
      x64_reject_unsupported_scalar(decl.ret)
      for param in decl.params {
        x64_reject_unsupported_scalar(param.ty)
      }
      self.local_offsets = {}
      self.var_types = {}
      self.stack_size = 0
      self.stack_align = 16
      self.local_base_reg = "rbp"
      self.func_name = decl.name
      self.va_list_offsets = {}
      self.va_reg_save_offset = -1
      self.va_initial_gp_offset = 0
      self.va_initial_fp_offset = 48
      self.va_initial_overflow_offset = 16
      self.sret_dest_offset = -1
      self.sret_scratch_offset = -1
      self.sret_scratch_size = 0
      self.sret_scratch_align = 1
      self.va_arg_scratch_offset = -1
      self.va_arg_scratch_size = 0
      self.va_arg_scratch_align = 1
      self.break_label = None
      self.continue_label = None
      self.emitted_labels = {}
      self.defined_labels = {}
      let param_offsets : Map[String, Int] = {}
      let param_types : Map[String, @parser.Type] = {}
      if self.is_memory_aggregate(decl.ret) {
        self.sret_dest_offset = self.alloc_local(
          "__kimicc_sret_dest",
          Pointer(Void),
        )
      }
      for param in decl.params {
        let offset = self.alloc_local(param.name, param.ty)
        param_offsets[param.name] = offset
        param_types[param.name] = param.ty
      }
      if decl.variadic {
        let initial_gp_slots = if self.is_memory_aggregate(decl.ret) {
          1
        } else {
          0
        }
        let (gp_offset, fp_offset, overflow_offset) = self.compute_va_initial_offsets(
          decl.params,
          initial_gp_slots,
        )
        self.va_initial_gp_offset = gp_offset
        self.va_initial_fp_offset = fp_offset
        self.va_initial_overflow_offset = overflow_offset
        self.va_reg_save_offset = self.alloc_local(
          "__kimicc_va_reg_save",
          Array(UChar, 176),
        )
      }
      let param_stack_end = self.stack_size
      self.collect_stmt_locals(body)
      if self.sret_scratch_size > 0 {
        self.sret_scratch_offset = self.alloc_local(
          "__kimicc_sret_scratch",
          Aligned(Array(UChar, self.sret_scratch_size), self.sret_scratch_align),
        )
      }
      if self.va_arg_scratch_size > 0 {
        self.va_arg_scratch_offset = self.alloc_local(
          "__kimicc_va_arg_scratch",
          Aligned(
            Array(UChar, self.va_arg_scratch_size),
            self.va_arg_scratch_align,
          ),
        )
      }
      let frame_align = if self.stack_align > 16 {
        self.stack_align
      } else {
        16
      }
      let frame_size = x64_align_to(self.stack_size, frame_align)
      if self.stack_align > 16 {
        self.local_base_reg = "r13"
      }
      if !decl.is_static {
        self.emit("\t.globl\t" + decl.name)
      }
      self.emit("\t.type\t" + decl.name + ", @function")
      self.emit(decl.name + ":")
      self.emit("\tpush\trbp")
      self.emit("\tmov\trbp, rsp")
      if self.stack_align > 16 {
        self.emit("\tpush\tr13")
        self.emit("\tand\trsp, -" + self.stack_align.to_string())
        self.emit("\tmov\tr13, rsp")
      }
      if frame_size > 0 {
        self.emit("\tsub\trsp, " + frame_size.to_string())
      }
      if self.sret_dest_offset >= 0 {
        self.emit(
          "\tmov\tQWORD PTR " + self.local_ref(self.sret_dest_offset) + ", rdi",
        )
      }
      self.emit_save_variadic_registers()
      let arg_regs = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
      let fp_arg_regs = [
        "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7",
      ]
      let mut int_idx = if self.is_memory_aggregate(decl.ret) { 1 } else { 0 }
      let mut fp_idx = 0
      let mut stack_idx = 0
      for i = 0; i < decl.params.length(); i = i + 1 {
        let param = decl.params[i]
        let offset = param_offsets[param.name]
        if x64_is_aggregate_type(param.ty) {
          let classes = match self.aggregate_classes(param.ty) {
            Some(classes) => classes
            None => {
              let words = self.aggregate_word_count(param.ty)
              stack_idx = self.align_stack_arg_index(stack_idx, param.ty)
              for word in 0..<words {
                let stack_off = 16 + (stack_idx + word) * 8
                self.emit(
                  "\tmov\trax, QWORD PTR [rbp + " + stack_off.to_string() + "]",
                )
                self.emit(
                  "\tmov\tQWORD PTR " +
                  self.local_neg_ref(offset, word * 8) +
                  ", rax",
                )
              }
              stack_idx += words
              continue
            }
          }
          let int_needed = x64_class_count(classes, IntClass)
          let fp_needed = x64_class_count(classes, SseClass)
          if int_idx + int_needed <= arg_regs.length() &&
            fp_idx + fp_needed <= fp_arg_regs.length() {
            let mut int_cursor = int_idx
            let mut fp_cursor = fp_idx
            for word in 0..<classes.length() {
              let width = self.aggregate_word_width(param.ty, word)
              match classes[word] {
                IntClass => {
                  self.emit_store_int_bytes_to_local(
                    arg_regs[int_cursor],
                    offset,
                    word * 8,
                    width,
                  )
                  int_cursor += 1
                }
                SseClass => {
                  self.emit_store_sse_word_to_local(
                    fp_arg_regs[fp_cursor],
                    offset,
                    word * 8,
                    width,
                  )
                  fp_cursor += 1
                }
              }
            }
            int_idx += int_needed
            fp_idx += fp_needed
          } else {
            stack_idx = self.align_stack_arg_index(stack_idx, param.ty)
            for word in 0..<classes.length() {
              let width = self.aggregate_word_width(param.ty, word)
              let stack_off = 16 + (stack_idx + word) * 8
              self.emit_load_int_bytes_from_mem_reg(
                "rax", "rbp", stack_off, width,
              )
              self.emit_store_int_bytes_to_local("rax", offset, word * 8, width)
            }
            stack_idx += classes.length()
          }
        } else if x64_is_fp_type(param.ty) {
          if fp_idx < fp_arg_regs.length() {
            self.emit_store_fp_reg_to_local(
              fp_arg_regs[fp_idx],
              offset,
              param.ty,
            )
            fp_idx += 1
          } else {
            stack_idx = self.align_stack_arg_index(stack_idx, param.ty)
            let stack_off = 16 + stack_idx * 8
            match x64_core_type(param.ty) {
              Float =>
                self.emit(
                  "\tmovss\txmm0, DWORD PTR [rbp + " +
                  stack_off.to_string() +
                  "]",
                )
              _ =>
                self.emit(
                  "\tmovsd\txmm0, QWORD PTR [rbp + " +
                  stack_off.to_string() +
                  "]",
                )
            }
            self.emit_store_local_from_rax(offset, param.ty)
            stack_idx += 1
          }
        } else if x64_is_int128_type(param.ty) {
          if int_idx + 2 <= arg_regs.length() {
            self.emit(
              "\tmov\tQWORD PTR " +
              self.local_ref(offset) +
              ", " +
              arg_regs[int_idx],
            )
            self.emit(
              "\tmov\tQWORD PTR " +
              self.local_neg_ref(offset, 8) +
              ", " +
              arg_regs[int_idx + 1],
            )
            int_idx += 2
          } else {
            stack_idx = self.align_stack_arg_index(stack_idx, param.ty)
            let stack_off = 16 + stack_idx * 8
            self.emit(
              "\tmov\trax, QWORD PTR [rbp + " + stack_off.to_string() + "]",
            )
            self.emit(
              "\tmov\trdx, QWORD PTR [rbp + " +
              (stack_off + 8).to_string() +
              "]",
            )
            self.emit_store_local_from_rax(offset, param.ty)
            stack_idx += 2
          }
        } else if int_idx < arg_regs.length() {
          self.emit_store_int_reg_to_local(arg_regs[int_idx], offset)
          int_idx += 1
        } else {
          stack_idx = self.align_stack_arg_index(stack_idx, param.ty)
          let stack_off = 16 + stack_idx * 8
          self.emit(
            "\tmov\trax, QWORD PTR [rbp + " + stack_off.to_string() + "]",
          )
          self.emit_store_local_from_rax(offset, param.ty)
          stack_idx += 1
        }
      }
      self.local_offsets = param_offsets
      self.var_types = param_types
      self.stack_size = param_stack_end
      self.va_list_offsets = {}
      self.gen_stmt(body)
      if self.is_memory_aggregate(decl.ret) {
        self.emit(
          "\tmov\trax, QWORD PTR " + self.local_ref(self.sret_dest_offset),
        )
      } else if x64_is_fp_type(decl.ret) {
        self.emit("\tpxor\txmm0, xmm0")
      } else {
        self.emit("\tmov\trax, 0")
      }
      self.emit(".L" + decl.name + "_ret:")
      for name, label in self.emitted_labels {
        if !self.defined_labels.contains(name) {
          self.emit(label + ":")
          self.emit("\tjmp\t.L" + self.func_name + "_ret")
        }
      }
      if self.stack_align > 16 {
        self.emit("\tmov\tr13, QWORD PTR [rbp - 8]")
      }
      self.emit("\tmov\trsp, rbp")
      self.emit("\tpop\trbp")
      self.emit("\tret")
      self.emit("\t.size\t" + decl.name + ", .-" + decl.name)
    }
  }
}

///|
priv struct X64ConstIntValue {
  bits : Int64
  ty : @parser.Type
}

///|
fn x64_const_int(bits : Int64, ty : @parser.Type) -> X64ConstIntValue {
  { bits, ty }
}

///|
fn x64_const_bool(value : Bool) -> X64ConstIntValue {
  { bits: if value { 1L } else { 0L }, ty: SInt }
}

///|
fn x64_const_type_is_unsigned(ty : @parser.Type) -> Bool {
  match x64_core_type(ty) {
    Bool | UChar | UShort | UInt | ULong | ULongLong | UInt128 => true
    _ => false
  }
}

///|
fn x64_const_type_int_width(ty : @parser.Type) -> Int? {
  match x64_core_type(ty) {
    Bool => Some(1)
    SChar | UChar => Some(8)
    SShort | UShort => Some(16)
    SInt | UInt => Some(32)
    SLong | ULong | SLongLong | ULongLong | Pointer(_) | FuncPtr(_, _, _) =>
      Some(64)
    SInt128 | UInt128 => Some(128)
    _ => None
  }
}

///|
fn x64_const_type_is_integer(ty : @parser.Type) -> Bool {
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
    | UInt128 => true
    _ => false
  }
}

///|
fn x64_const_integer_promote(ty : @parser.Type) -> @parser.Type {
  match x64_core_type(ty) {
    Bool | SChar | UChar | SShort | UShort => SInt
    other => other
  }
}

///|
fn x64_const_unsigned_type_for_rank(rank : Int) -> @parser.Type {
  if rank >= 6 {
    UInt128
  } else if rank == 5 {
    ULongLong
  } else if rank == 4 {
    ULong
  } else {
    UInt
  }
}

///|
fn x64_const_signed_type_for_rank(rank : Int) -> @parser.Type {
  if rank >= 6 {
    SInt128
  } else if rank == 5 {
    SLongLong
  } else if rank == 4 {
    SLong
  } else {
    SInt
  }
}

///|
fn x64_const_integer_common_type(
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
) -> @parser.Type {
  let lhs_ty = x64_const_integer_promote(lhs_ty)
  let rhs_ty = x64_const_integer_promote(rhs_ty)
  if lhs_ty == rhs_ty {
    return lhs_ty
  }
  if !x64_const_type_is_integer(lhs_ty) || !x64_const_type_is_integer(rhs_ty) {
    return lhs_ty
  }
  let lhs_unsigned = x64_const_type_is_unsigned(lhs_ty)
  let rhs_unsigned = x64_const_type_is_unsigned(rhs_ty)
  let lhs_rank = integer_rank(lhs_ty)
  let rhs_rank = integer_rank(rhs_ty)
  if lhs_unsigned == rhs_unsigned {
    let rank = if lhs_rank > rhs_rank { lhs_rank } else { rhs_rank }
    if lhs_unsigned {
      x64_const_unsigned_type_for_rank(rank)
    } else {
      x64_const_signed_type_for_rank(rank)
    }
  } else {
    let unsigned_ty = if lhs_unsigned { lhs_ty } else { rhs_ty }
    let signed_ty = if lhs_unsigned { rhs_ty } else { lhs_ty }
    let unsigned_rank = integer_rank(unsigned_ty)
    let signed_rank = integer_rank(signed_ty)
    let unsigned_width = x64_const_type_int_width(unsigned_ty).unwrap_or(0)
    let signed_width = x64_const_type_int_width(signed_ty).unwrap_or(0)
    if unsigned_rank >= signed_rank {
      unsigned_ty
    } else if signed_width > unsigned_width {
      signed_ty
    } else {
      x64_const_unsigned_type_for_rank(signed_rank)
    }
  }
}

///|
fn x64_const_cast_int(
  value : X64ConstIntValue,
  ty : @parser.Type,
) -> X64ConstIntValue {
  let core_ty = x64_core_type(ty)
  let unsigned = x64_const_type_is_unsigned(core_ty)
  match x64_const_type_int_width(core_ty) {
    None => x64_const_int(value.bits, core_ty)
    Some(1) => x64_const_int(if value.bits == 0L { 0L } else { 1L }, core_ty)
    Some(width) =>
      if width >= 64 {
        x64_const_int(value.bits, core_ty)
      } else {
        let mask = (1L << width) - 1L
        let bits = value.bits & mask
        if unsigned {
          x64_const_int(bits, core_ty)
        } else {
          let sign = 1L << (width - 1)
          if (bits & sign) != 0L {
            x64_const_int(bits | mask.lnot(), core_ty)
          } else {
            x64_const_int(bits, core_ty)
          }
        }
      }
  }
}

///|
fn x64_const_apply_binary_type(
  left : X64ConstIntValue,
  right : X64ConstIntValue,
) -> (X64ConstIntValue, X64ConstIntValue, @parser.Type) {
  let ty = x64_const_integer_common_type(left.ty, right.ty)
  (x64_const_cast_int(left, ty), x64_const_cast_int(right, ty), ty)
}

///|
fn x64_const_binary_arith(
  op : String,
  left : X64ConstIntValue,
  right : X64ConstIntValue,
) -> X64ConstIntValue? {
  let (x, y, ty) = x64_const_apply_binary_type(left, right)
  let bits = match op {
    "+" => x.bits + y.bits
    "-" => x.bits - y.bits
    "*" => x.bits * y.bits
    "|" => x.bits | y.bits
    "&" => x.bits & y.bits
    "^" => x.bits ^ y.bits
    _ => return None
  }
  Some(x64_const_cast_int(x64_const_int(bits, ty), ty))
}

///|
fn x64_const_equal_compare(
  left : X64ConstIntValue,
  right : X64ConstIntValue,
) -> Bool {
  let (x, y, _) = x64_const_apply_binary_type(left, right)
  x.bits == y.bits
}

///|
fn x64_const_rel_compare(
  op : String,
  left : X64ConstIntValue,
  right : X64ConstIntValue,
) -> Bool {
  let (left, right, ty) = x64_const_apply_binary_type(left, right)
  if x64_const_type_is_unsigned(ty) {
    let x = left.bits.reinterpret_as_uint64()
    let y = right.bits.reinterpret_as_uint64()
    match op {
      "<" => x < y
      ">" => x > y
      "<=" => x <= y
      ">=" => x >= y
      _ => false
    }
  } else {
    match op {
      "<" => left.bits < right.bits
      ">" => left.bits > right.bits
      "<=" => left.bits <= right.bits
      ">=" => left.bits >= right.bits
      _ => false
    }
  }
}

///|
fn x64_const_divide(
  op : String,
  left : X64ConstIntValue,
  right : X64ConstIntValue,
) -> X64ConstIntValue? {
  let (left, right, ty) = x64_const_apply_binary_type(left, right)
  if right.bits == 0L {
    return None
  }
  if x64_const_type_is_unsigned(ty) {
    let x = left.bits.reinterpret_as_uint64()
    let y = right.bits.reinterpret_as_uint64()
    let result = if op == "/" { x / y } else { x % y }
    Some(
      x64_const_cast_int(x64_const_int(result.reinterpret_as_int64(), ty), ty),
    )
  } else {
    let result = if op == "/" {
      left.bits / right.bits
    } else {
      left.bits % right.bits
    }
    Some(x64_const_cast_int(x64_const_int(result, ty), ty))
  }
}

///|
fn x64_const_shift(
  op : String,
  left : X64ConstIntValue,
  right : X64ConstIntValue,
) -> X64ConstIntValue? {
  let lhs_ty = x64_const_integer_promote(left.ty)
  let x = x64_const_cast_int(left, lhs_ty)
  let y = x64_const_cast_int(right, x64_const_integer_promote(right.ty))
  let shift = y.bits.to_int()
  if op == "<<" {
    Some(x64_const_cast_int(x64_const_int(x.bits << shift, lhs_ty), lhs_ty))
  } else if x64_const_type_is_unsigned(lhs_ty) {
    Some(
      x64_const_cast_int(
        x64_const_int(
          (x.bits.reinterpret_as_uint64() >> shift).reinterpret_as_int64(),
          lhs_ty,
        ),
        lhs_ty,
      ),
    )
  } else {
    Some(x64_const_cast_int(x64_const_int(x.bits >> shift, lhs_ty), lhs_ty))
  }
}

///|
fn X64Codegen::fold_const_int(
  self : X64Codegen,
  expr : @parser.Expr,
) -> X64ConstIntValue? {
  match expr {
    Number(n) => {
      let ty = number_literal_type(n)
      Some(x64_const_cast_int(x64_const_int(n, ty), ty))
    }
    Binary("+", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => x64_const_binary_arith("+", x, y)
        _ => None
      }
    Binary("-", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => x64_const_binary_arith("-", x, y)
        _ => None
      }
    Binary("*", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => x64_const_binary_arith("*", x, y)
        _ => None
      }
    Binary("/", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => x64_const_divide("/", x, y)
        _ => None
      }
    Binary("%", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => x64_const_divide("%", x, y)
        _ => None
      }
    Binary("|", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => x64_const_binary_arith("|", x, y)
        _ => None
      }
    Binary("&", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => x64_const_binary_arith("&", x, y)
        _ => None
      }
    Binary("^", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => x64_const_binary_arith("^", x, y)
        _ => None
      }
    Binary("<<", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => x64_const_shift("<<", x, y)
        _ => None
      }
    Binary(">>", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => x64_const_shift(">>", x, y)
        _ => None
      }
    Binary("==", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(x64_const_bool(x64_const_equal_compare(x, y)))
        _ => None
      }
    Binary("!=", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(x64_const_bool(!x64_const_equal_compare(x, y)))
        _ => None
      }
    Binary("<", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(x64_const_bool(x64_const_rel_compare("<", x, y)))
        _ => None
      }
    Binary(">", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(x64_const_bool(x64_const_rel_compare(">", x, y)))
        _ => None
      }
    Binary("<=", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(x64_const_bool(x64_const_rel_compare("<=", x, y)))
        _ => None
      }
    Binary(">=", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(x64_const_bool(x64_const_rel_compare(">=", x, y)))
        _ => None
      }
    Binary("&&", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => Some(x64_const_bool(x.bits != 0L && y.bits != 0L))
        _ => None
      }
    Binary("||", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => Some(x64_const_bool(x.bits != 0L || y.bits != 0L))
        _ => None
      }
    Ternary(cond, a, b) =>
      match self.fold_const_int(cond) {
        Some({ bits: 0L, .. }) => self.fold_const_int(b)
        Some(_) => self.fold_const_int(a)
        None => None
      }
    Unary("-", e) =>
      match self.fold_const_int(e) {
        Some(value) => {
          let ty = x64_const_integer_promote(value.ty)
          Some(x64_const_cast_int(x64_const_int(-value.bits, ty), ty))
        }
        None => None
      }
    Unary("+", e) =>
      match self.fold_const_int(e) {
        Some(value) => {
          let ty = x64_const_integer_promote(value.ty)
          Some(x64_const_cast_int(value, ty))
        }
        None => None
      }
    Unary("~", e) =>
      match self.fold_const_int(e) {
        Some(value) => {
          let ty = x64_const_integer_promote(value.ty)
          Some(x64_const_cast_int(x64_const_int(value.bits.lnot(), ty), ty))
        }
        None => None
      }
    Unary("!", e) =>
      match self.fold_const_int(e) {
        Some(value) => Some(x64_const_bool(value.bits == 0L))
        None => None
      }
    Cast(ty, e) =>
      if x64_is_fp_type(ty) {
        None
      } else if !x64_is_fp_type(ty) && x64_is_fp_type(self.type_of(e)) {
        match self.fold_float_const(e) {
          Some(value) =>
            Some(
              x64_const_cast_int(
                x64_const_int(value.to_int().to_int64(), ty),
                ty,
              ),
            )
          None => None
        }
      } else {
        match x64_const_type_int_width(ty) {
          Some(_) =>
            match self.fold_const_int(e) {
              Some(value) => Some(x64_const_cast_int(value, ty))
              None => None
            }
          None => None
        }
      }
    DesignatedField(_, e) | DesignatedIndex(_, e) | DesignatedRange(_, _, e) =>
      self.fold_const_int(e)
    Sizeof(ty) => Some(x64_const_int(self.type_size(ty).to_int64(), ULong))
    SizeofExpr(e) =>
      Some(
        x64_const_int(
          self.type_size(self.global_expr_type(e)).to_int64(),
          ULong,
        ),
      )
    Alignof(ty) => Some(x64_const_int(self.type_align(ty).to_int64(), ULong))
    AlignofExpr(e) =>
      Some(
        x64_const_int(
          self.type_align(self.global_expr_type(e)).to_int64(),
          ULong,
        ),
      )
    OffsetOf(ty, path) =>
      match self.offset_of_path(ty, path) {
        Some(offset) => Some(x64_const_int(offset.to_int64(), ULong))
        None => None
      }
    _ => None
  }
}

///|
fn X64Codegen::fold_const(self : X64Codegen, expr : @parser.Expr) -> Int64? {
  match self.fold_const_int(expr) {
    Some(value) => Some(value.bits)
    None => None
  }
}

///|
fn X64Codegen::fold_float_const(
  self : X64Codegen,
  expr : @parser.Expr,
) -> Double? {
  let expr_ty = self.type_of(expr)
  if !x64_is_fp_type(expr_ty) {
    match expr {
      Cast(_, e) if x64_is_fp_type(self.type_of(e)) =>
        match self.fold_float_const(e) {
          Some(value) => Some(value.to_int().to_double())
          None => None
        }
      _ =>
        match self.fold_const(expr) {
          Some(value) => Some(value.to_double())
          None => None
        }
    }
  } else {
    match expr {
      FloatLiteral(v) => Some(v)
      Number(n) => Some(n.to_double())
      Binary("+", a, b) =>
        match (self.fold_float_const(a), self.fold_float_const(b)) {
          (Some(x), Some(y)) => Some(x + y)
          _ => None
        }
      Binary("-", a, b) =>
        match (self.fold_float_const(a), self.fold_float_const(b)) {
          (Some(x), Some(y)) => Some(x - y)
          _ => None
        }
      Binary("*", a, b) =>
        match (self.fold_float_const(a), self.fold_float_const(b)) {
          (Some(x), Some(y)) => Some(x * y)
          _ => None
        }
      Binary("/", a, b) =>
        match (self.fold_float_const(a), self.fold_float_const(b)) {
          (Some(x), Some(y)) => Some(x / y)
          _ => None
        }
      Unary("-", e) =>
        match self.fold_float_const(e) {
          Some(x) => Some(-x)
          None => None
        }
      Unary("+", e) => self.fold_float_const(e)
      Ternary(cond, a, b) =>
        match self.fold_const(cond) {
          Some(0L) => self.fold_float_const(b)
          Some(_) => self.fold_float_const(a)
          None => None
        }
      Cast(_, e)
      | DesignatedField(_, e)
      | DesignatedIndex(_, e)
      | DesignatedRange(_, _, e) => self.fold_float_const(e)
      Call(Var(name), _) =>
        match name {
          "__builtin_nan" | "__builtin_nanf" | "__builtin_nanl" =>
            Some(0.0 / 0.0)
          "__builtin_huge_val"
          | "__builtin_huge_valf"
          | "__builtin_huge_vall"
          | "__builtin_inf"
          | "__builtin_inff"
          | "__builtin_infl" => Some(1.0 / 0.0)
          _ => None
        }
      _ => None
    }
  }
}

///|
fn X64Codegen::global_lvalue_reloc(
  self : X64Codegen,
  expr : @parser.Expr,
) -> (String, Int)? {
  match expr {
    Var(name) => Some((name, 0))
    Cast(_, e) => self.global_lvalue_reloc(e)
    Unary("*", e) | Deref(e) => self.global_address_reloc_parts(e)
    ArrayAccess(base, index) =>
      match
        (self.global_lvalue_reloc(base), self.global_address_reloc_parts(base)) {
        (Some(parts), _) | (None, Some(parts)) => {
          let (label, base_offset) = parts
          let elem_size = match peel_aligned_type(self.global_expr_type(base)) {
            Array(elem, _) | Pointer(elem) => self.pointer_element_size(elem)
            _ => 1
          }
          match self.fold_const(index) {
            Some(i) => Some((label, base_offset + i.to_int() * elem_size))
            None => None
          }
        }
        _ => None
      }
    MemberAccess(obj, field) =>
      match self.global_lvalue_reloc(obj) {
        Some((label, base_offset)) =>
          match peel_aligned_type(self.global_expr_type(obj)) {
            Struct(_) | Union(_) =>
              match self.field_layout(self.global_expr_type(obj), field) {
                Some((_, _, field_offset, _, _, _)) =>
                  Some((label, base_offset + field_offset))
                None => None
              }
            Pointer(Struct(name)) =>
              match self.field_layout(Struct(name), field) {
                Some((_, _, field_offset, _, _, _)) =>
                  Some((label, base_offset + field_offset))
                None => None
              }
            Pointer(Union(name)) =>
              match self.field_layout(Union(name), field) {
                Some((_, _, field_offset, _, _, _)) =>
                  Some((label, base_offset + field_offset))
                None => None
              }
            _ => None
          }
        None => None
      }
    _ => None
  }
}

///|
fn X64Codegen::global_address_reloc_parts(
  self : X64Codegen,
  expr : @parser.Expr,
) -> (String, Int)? {
  match expr {
    Var(name) => Some((name, 0))
    Cast(_, e) => self.global_address_reloc_parts(e)
    LabelAddr(name) => Some((self.label_ref(name), 0))
    AddrOf(e) => self.global_lvalue_reloc(e)
    Binary("+", base, offset_expr) =>
      match
        (self.global_address_reloc_parts(base), self.fold_const(offset_expr)) {
        (Some((label, base_offset)), Some(offset)) =>
          Some((label, base_offset + self.global_offset_bytes(base, offset)))
        _ =>
          match
            (
              self.global_address_reloc_parts(offset_expr),
              self.fold_const(base),
            ) {
            (Some((label, base_offset)), Some(offset)) =>
              Some(
                (
                  label,
                  base_offset + self.global_offset_bytes(offset_expr, offset),
                ),
              )
            _ => None
          }
      }
    Binary("-", base, offset_expr) =>
      match
        (self.global_address_reloc_parts(base), self.fold_const(offset_expr)) {
        (Some((label, base_offset)), Some(offset)) =>
          Some((label, base_offset - self.global_offset_bytes(base, offset)))
        _ => None
      }
    _ => None
  }
}

///|
fn X64Codegen::global_address_reloc(
  self : X64Codegen,
  expr : @parser.Expr,
) -> String? {
  match self.global_address_reloc_parts(expr) {
    Some((label, offset)) => Some(reloc_with_offset(label, offset))
    None => None
  }
}

///|
fn X64Codegen::global_offset_bytes(
  self : X64Codegen,
  base : @parser.Expr,
  offset : Int64,
) -> Int {
  match x64_pointer_element(self.global_expr_type(base)) {
    Some(elem_ty) => offset.to_int() * self.pointer_element_size(elem_ty)
    None => offset.to_int()
  }
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
  ty : @parser.Type,
  value : Double,
) -> Unit {
  match x64_core_type(ty) {
    Float => self.emit("\t.float\t" + value.to_string())
    _ => self.emit("\t.double\t" + value.to_string())
  }
}

///|
fn X64Codegen::global_bitfield_bits(
  self : X64Codegen,
  init_expr : @parser.Expr,
  bit_width : Int,
  bit_offset : Int,
) -> Int64 {
  match self.fold_const(x64_initializer_value(init_expr)) {
    Some(value) => (value & bitfield_mask(bit_width)) << bit_offset
    None => 0L
  }
}

///|
fn X64Codegen::designator_matches_type(
  self : X64Codegen,
  ty : @parser.Type,
  expr : @parser.Expr,
) -> Bool {
  match (x64_core_type(ty), expr) {
    (Struct(name), DesignatedField(field, _)) =>
      self.field_layout(Struct(name), field) is Some(_)
    (Union(name), DesignatedField(field, _)) =>
      self.field_layout(Union(name), field) is Some(_)
    (Array(_, _), DesignatedIndex(_, _))
    | (Array(_, _), DesignatedRange(_, _, _)) => true
    _ => false
  }
}

///|
fn X64Codegen::emit_global_scalar(
  self : X64Codegen,
  ty : @parser.Type,
  expr : @parser.Expr,
) -> Unit {
  match ty {
    Aligned(inner, _) => {
      self.emit_global_scalar(inner, expr)
      return
    }
    _ => ()
  }
  match x64_core_type(ty) {
    Pointer(_) | FuncPtr(_, _, _) =>
      match self.global_address_reloc(expr) {
        Some(reloc) => {
          self.emit("\t.quad\t" + reloc)
          return
        }
        None => ()
      }
    _ => ()
  }
  match x64_core_type(ty) {
    Float | Double =>
      match self.fold_float_const(expr) {
        Some(value) => {
          self.emit_global_float(ty, value)
          return
        }
        None => ()
      }
    _ => ()
  }
  match x64_const_type_int_width(ty) {
    Some(_) =>
      if x64_is_fp_type(self.type_of(expr)) {
        match self.fold_float_const(expr) {
          Some(value) => {
            let converted = x64_const_cast_int(
              x64_const_int(value.to_int().to_int64(), ty),
              ty,
            )
            self.emit_global_scalar(ty, Number(converted.bits))
            return
          }
          None => ()
        }
      }
    None => ()
  }
  match expr {
    DesignatedField(_, inner)
    | DesignatedIndex(_, inner)
    | DesignatedRange(_, _, inner) => {
      if x64_is_object_aggregate_type(ty) &&
        self.designator_matches_type(ty, expr) {
        self.emit_global_array(ty, [expr])
      } else {
        self.emit_global_scalar(ty, inner)
      }
      return
    }
    _ => ()
  }
  let folded_expr = match self.fold_const(expr) {
    Some(value) => @parser.Expr::Number(value)
    None => expr
  }
  match folded_expr {
    Number(value) =>
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
        Float128 => abort("__float128 global initializer is not supported")
        LongDouble => abort("long double global initializer is not supported")
        Struct(_) | Union(_) | Array(_, _) =>
          self.emit("\t.zero\t" + self.type_size(ty).to_string())
        _ => self.emit_global_int_by_size(8, value)
      }
    FloatLiteral(value) =>
      if x64_core_type(ty) == Float128 {
        abort("__float128 global initializer is not supported")
      } else if x64_core_type(ty) == LongDouble {
        abort("long double global initializer is not supported")
      } else if x64_is_fp_type(ty) {
        self.emit_global_float(ty, value)
      } else {
        self.emit_global_scalar(ty, Number(value.to_int().to_int64()))
      }
    String(value) =>
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
    Cast(_, inner) => self.emit_global_scalar(ty, inner)
    CompoundLiteral(_, exprs, _) | Array(exprs) =>
      self.emit_global_array(ty, exprs)
    Var(name) => self.emit("\t.quad\t" + name)
    _ => self.emit("\t.zero\t" + self.type_size(ty).to_string())
  }
}

///|
fn X64Codegen::emit_global_array(
  self : X64Codegen,
  ty : @parser.Type,
  exprs : Array[@parser.Expr],
) -> Unit {
  match ty {
    Aligned(inner, _) => {
      self.emit_global_array(inner, exprs)
      return
    }
    _ => ()
  }
  match x64_core_type(ty) {
    Array(elem_ty, n) => {
      let elem_size = self.type_size(elem_ty)
      let slots : Array[@parser.Expr?] = Array::make(n, None)
      let mut cursor = 0
      for expr in exprs {
        let mut start = cursor
        let mut end = cursor
        let value = match expr {
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
            expr
          }
        }
        for i = start; i <= end; i = i + 1 {
          if i >= 0 && i < n {
            slots[i] = Some(value)
          }
        }
      }
      for slot in slots {
        match slot {
          Some(value) => self.emit_global_scalar(elem_ty, value)
          None => self.emit("\t.zero\t" + elem_size.to_string())
        }
      }
    }
    Struct(name) => {
      self.ensure_struct_layout(name)
      let layout = self.struct_layouts[name]
      let field_inits : Array[@parser.Expr?] = Array::make(
        layout.length(),
        None,
      )
      let mut positional = 0
      for init_expr in exprs {
        match init_expr {
          DesignatedField(field_name, _) =>
            for i = 0; i < layout.length(); i = i + 1 {
              if layout[i].0 == field_name {
                field_inits[i] = Some(init_expr)
                positional = i + 1
                break
              }
            }
          _ =>
            if positional < layout.length() {
              field_inits[positional] = Some(init_expr)
              positional += 1
            }
        }
      }
      let mut emitted = 0
      let mut i = 0
      while i < layout.length() {
        let (_, field_ty, field_offset, field_size, _, bit_width) = layout[i]
        if bit_width > 0 {
          let container_offset = field_offset
          let container_size = field_size
          let mut j = i
          let mut container_value = 0L
          while j < layout.length() &&
                layout[j].2 == container_offset &&
                layout[j].3 == container_size &&
                layout[j].5 > 0 {
            let (_, _, _, _, bit_offset, width) = layout[j]
            match field_inits[j] {
              Some(init_expr) =>
                container_value = container_value |
                  self.global_bitfield_bits(init_expr, width, bit_offset)
              None => ()
            }
            j += 1
          }
          if container_offset >= emitted {
            if container_offset > emitted {
              self.emit("\t.zero\t" + (container_offset - emitted).to_string())
            }
            self.emit_global_int_by_size(container_size, container_value)
            emitted = container_offset + container_size
          }
          i = j
        } else if bit_width < 0 {
          match field_inits[i] {
            Some(init_expr) => {
              if field_offset > emitted {
                self.emit("\t.zero\t" + (field_offset - emitted).to_string())
              }
              self.emit_global_scalar(field_ty, init_expr)
              emitted = field_offset + field_size
            }
            None => ()
          }
          i += 1
        } else {
          i += 1
        }
      }
      let total_size = self.type_size(ty)
      if total_size > emitted {
        self.emit("\t.zero\t" + (total_size - emitted).to_string())
      }
    }
    Union(name) => {
      self.ensure_struct_layout(name)
      let layout = self.struct_layouts[name]
      let mut emitted = 0
      if exprs.length() > 0 {
        let init_expr = exprs[0]
        let field = match init_expr {
          DesignatedField(field_name, _) =>
            self.field_layout(Union(name), field_name)
          _ => if layout.length() > 0 { Some(layout[0]) } else { None }
        }
        match field {
          Some((_, field_ty, field_offset, field_size, _, bit_width)) =>
            if bit_width > 0 {
              if field_offset > 0 {
                self.emit("\t.zero\t" + field_offset.to_string())
              }
              self.emit_global_int_by_size(
                field_size,
                self.global_bitfield_bits(init_expr, bit_width, 0),
              )
              emitted = field_offset + field_size
            } else if bit_width < 0 {
              if field_offset > 0 {
                self.emit("\t.zero\t" + field_offset.to_string())
              }
              self.emit_global_scalar(field_ty, init_expr)
              emitted = field_offset + field_size
            }
          None => ()
        }
      }
      let total_size = self.type_size(ty)
      if total_size > emitted {
        self.emit("\t.zero\t" + (total_size - emitted).to_string())
      }
    }
    _ => self.emit("\t.zero\t" + self.type_size(ty).to_string())
  }
}

///|
fn X64Codegen::emit_globals(
  self : X64Codegen,
  globals : Array[@parser.GlobalDecl],
) -> Unit {
  let mut has_data = false
  for g in globals {
    if g.init is Some(_) {
      if !has_data {
        self.emit("\t.data")
        has_data = true
      }
      if !g.is_static {
        self.emit("\t.globl\t" + g.name)
      }
      self.emit("\t.align\t" + self.type_align(g.ty).to_string())
      self.emit(g.name + ":")
      match g.init {
        Some(Scalar(expr)) => self.emit_global_scalar(g.ty, expr)
        Some(Array(exprs)) => self.emit_global_array(g.ty, exprs)
        None => ()
      }
    }
  }
  let mut has_bss = false
  for g in globals {
    if g.init is None && !g.is_extern {
      if !has_bss {
        self.emit("\t.bss")
        has_bss = true
      }
      if !g.is_static {
        self.emit("\t.globl\t" + g.name)
      }
      self.emit("\t.align\t" + self.type_align(g.ty).to_string())
      self.emit(g.name + ":")
      self.emit("\t.zero\t" + self.type_size(g.ty).to_string())
    }
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
    self.emit("\t.double\t" + self.fp_literals[i].to_string())
  }
}

///|
fn X64Codegen::generate(self : X64Codegen, prog : @parser.Program) -> String {
  self.emit("\t.intel_syntax noprefix")
  self.emit("\t.text")
  for sdecl in prog.structs {
    self.struct_decls[sdecl.name] = sdecl
  }
  for sdecl in prog.structs {
    self.compute_struct_layout(sdecl)
  }
  for decl in prog.decls {
    self.func_rets[decl.name] = decl.ret
    self.func_variadic[decl.name] = decl.variadic
    self.func_param_counts[decl.name] = decl.params.length()
    let param_types = []
    for param in decl.params {
      param_types.push(param.ty)
    }
    self.func_param_types[decl.name] = param_types
  }
  let globals = merge_global_decls(prog.globals)
  for g in globals {
    self.globals[g.name] = g
  }
  for decl in prog.decls {
    self.emit_function(decl)
  }
  self.emit_globals(globals)
  self.emit_strings()
  self.emit_fp_literals()
  self.emit("\t.section\t.note.GNU-stack,\"\",@progbits")
  self.output.to_string()
}
