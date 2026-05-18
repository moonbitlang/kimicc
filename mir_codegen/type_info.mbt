///|
fn Codegen::type_size(self : Codegen, ty : @parser.Type) -> Int {
  match self.mir_module {
    Some(mir) => return mir.type_size(ty)
    None => ()
  }
  match ty {
    Void => 0
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt | Float => 4
    Float16 => abort("_Float16 size is not supported")
    Float128 => abort("__float128 size is not supported")
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | LongDouble
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    SInt128 | UInt128 => 16
    Array(elem, n) => self.type_size(elem) * n
    Atomic(ty) => self.type_size(ty)
    Aligned(ty, _) => self.type_size(ty)
    Struct(name) => {
      if !self.struct_layouts.contains(name) {
        if self.struct_decls.contains(name) {
          self.compute_struct_layout(self.struct_decls[name])
        } else {
          // Forward-declared opaque struct: assume pointer size
          return 8
        }
      }
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
          let fa = self.type_align(field.1)
          if fa > max_align {
            max_align = fa
          }
        }
      }
      // Round up to struct alignment (trailing padding)
      let padding = (max_align - max_end % max_align) % max_align
      max_end + padding
    }
    Union(name) => {
      if !self.struct_layouts.contains(name) {
        if self.struct_decls.contains(name) {
          self.compute_struct_layout(self.struct_decls[name])
        } else {
          // Forward-declared opaque union: assume pointer size
          return 8
        }
      }
      let fields = self.struct_layouts[name]
      let mut max_size = 0
      let mut max_align = 1
      let is_packed = self.struct_decls.contains(name) &&
        self.struct_decls[name].is_packed
      for field in fields {
        let fs = self.type_size(field.1)
        if fs > max_size {
          max_size = fs
        }
        if !is_packed {
          let fa = self.type_align(field.1)
          if fa > max_align {
            max_align = fa
          }
        }
      }
      max_size + (max_align - max_size % max_align) % max_align
    }
  }
}

///|
fn Codegen::type_align(self : Codegen, ty : @parser.Type) -> Int {
  match self.mir_module {
    Some(mir) => return mir.type_align(ty)
    None => ()
  }
  match ty {
    Void => 1
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt | Float => 4
    Float16 => abort("_Float16 alignment is not supported")
    Float128 => abort("__float128 alignment is not supported")
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | LongDouble
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    SInt128 | UInt128 => 16
    Array(elem, _) => self.type_align(elem)
    Atomic(ty) => self.type_align(ty)
    Aligned(ty, align) => {
      let inner = self.type_align(ty)
      if align > inner {
        align
      } else {
        inner
      }
    }
    Struct(name) => {
      if self.struct_decls.contains(name) && self.struct_decls[name].is_packed {
        return 1
      }
      if !self.struct_layouts.contains(name) {
        if self.struct_decls.contains(name) {
          self.compute_struct_layout(self.struct_decls[name])
        } else {
          return 8
        }
      }
      let fields = self.struct_layouts[name]
      let mut max_align = 1
      for field in fields {
        let field_align = self.type_align(field.1)
        if field_align > max_align {
          max_align = field_align
        }
      }
      max_align
    }
    Union(name) => {
      if self.struct_decls.contains(name) && self.struct_decls[name].is_packed {
        return 1
      }
      if !self.struct_layouts.contains(name) {
        if self.struct_decls.contains(name) {
          self.compute_struct_layout(self.struct_decls[name])
        } else {
          return 8
        }
      }
      let fields = self.struct_layouts[name]
      let mut max_align = 1
      for field in fields {
        let field_align = self.type_align(field.1)
        if field_align > max_align {
          max_align = field_align
        }
      }
      max_align
    }
  }
}

///|
fn is_anon_type(ty : @parser.Type) -> Bool {
  match ty {
    Struct(name) | Union(name) => name.has_prefix("__anon_")
    _ => false
  }
}

///|
fn Codegen::flatten_anon_fields(
  self : Codegen,
  ty : @parser.Type,
  base_offset : Int,
) -> Array[(String, @parser.Type, Int, Int, Int, Int)] {
  let name = match ty {
    Struct(n) | Union(n) => n
    _ => return []
  }
  if !self.struct_layouts.contains(name) {
    if self.struct_decls.contains(name) {
      self.compute_struct_layout(self.struct_decls[name])
    } else {
      return []
    }
  }
  let result = []
  for f in self.struct_layouts[name] {
    if f.0 == "" && is_anon_type(f.1) {
      // Nested anonymous struct/union: recursively flatten
      for inner in self.flatten_anon_fields(f.1, base_offset + f.2) {
        result.push(inner)
      }
    } else {
      result.push((f.0, f.1, base_offset + f.2, f.3, f.4, f.5))
    }
  }
  result
}

///|
fn Codegen::compute_struct_layout(
  self : Codegen,
  decl : @parser.StructDecl,
) -> Unit {
  if decl.is_union {
    self.compute_union_layout(decl)
    return
  }
  let mut offset = 0
  let layout = []
  // Bit-field packing state
  let mut in_bitfield_run = false
  let mut current_bit_offset = 0
  for field in decl.fields {
    // Anonymous struct/union member: flatten its fields into parent
    if field.name == "" && is_anon_type(field.ty) {
      let align = if decl.is_packed { 1 } else { self.type_align(field.ty) }
      let padding = (align - offset % align) % align
      offset += padding
      for f in self.flatten_anon_fields(field.ty, offset) {
        layout.push(f)
      }
      offset += self.type_size(field.ty)
      in_bitfield_run = false
      current_bit_offset = 0
      continue
    }
    match field.bit_width {
      None => {
        // Normal field: align to natural boundary, reset bit packing
        let size = self.type_size(field.ty)
        let align = if decl.is_packed { 1 } else { self.type_align(field.ty) }
        let padding = (align - offset % align) % align
        offset += padding
        layout.push((field.name, field.ty, offset, size, 0, 0))
        offset += size
        in_bitfield_run = false
        current_bit_offset = 0
      }
      Some(w) => {
        let container_size = self.type_size(field.ty)
        let container_align = if decl.is_packed {
          1
        } else {
          self.type_align(field.ty)
        }
        let container_bits = container_size * 8
        if w == 0 {
          // Zero-width bit-field: force alignment to next container boundary
          let padding = (container_align - offset % container_align) %
            container_align
          offset += padding
          in_bitfield_run = false
          current_bit_offset = 0
          // Don't add a layout entry for zero-width bit-fields
        } else {
          let mut container_offset = current_bit_offset /
            (container_align * 8) *
            container_align
          let mut field_bit_offset = current_bit_offset - container_offset * 8
          let can_continue = in_bitfield_run &&
            field_bit_offset + w <= container_bits
          if !can_continue {
            container_offset = offset / container_align * container_align
            field_bit_offset = (offset - container_offset) * 8
            if offset >= container_offset + container_size ||
              field_bit_offset + w > container_bits {
              let padding = (container_align - offset % container_align) %
                container_align
              container_offset = offset + padding
              field_bit_offset = 0
            }
            current_bit_offset = container_offset * 8 + field_bit_offset
          }
          layout.push(
            (
              field.name,
              field.ty,
              container_offset,
              container_size,
              field_bit_offset,
              w,
            ),
          )
          in_bitfield_run = true
          current_bit_offset = current_bit_offset + w
          let end_offset = (current_bit_offset + 7) / 8
          if end_offset > offset {
            offset = end_offset
          }
        }
      }
    }
  }
  self.struct_layouts[decl.name] = layout
}

///|
fn Codegen::compute_union_layout(
  self : Codegen,
  decl : @parser.StructDecl,
) -> Unit {
  let layout = []
  for field in decl.fields {
    // Anonymous struct/union member: flatten its fields into parent
    if field.name == "" && is_anon_type(field.ty) {
      for f in self.flatten_anon_fields(field.ty, 0) {
        layout.push(f)
      }
      continue
    }
    let size = self.type_size(field.ty)
    match field.bit_width {
      None => layout.push((field.name, field.ty, 0, size, 0, 0))
      Some(w) =>
        if w == 0 {
          // Zero-width bit-field in union: no effect
        } else {
          layout.push((field.name, field.ty, 0, size, 0, w))
        }
    }
  }
  self.struct_layouts[decl.name] = layout
}

///|
fn darwin_field_layout_tuple(
  layout : @mir.FieldLayout,
) -> (String, @parser.Type, Int, Int, Int, Int) {
  let bit_width = match layout.bit_width {
    Some(width) => width
    None => 0
  }
  (
    layout.name,
    layout.ty,
    layout.offset,
    layout.size,
    layout.bit_offset,
    bit_width,
  )
}

///|
fn Codegen::register_mir_aggregate_layouts(
  self : Codegen,
  mir : @mir.MirModule,
) -> Unit {
  for decl in mir.aggregate_decls {
    match mir.layouts.get(decl.name) {
      Some(layout) => {
        let fields : Array[(String, @parser.Type, Int, Int, Int, Int)] = []
        for field in layout.fields {
          fields.push(darwin_field_layout_tuple(field))
        }
        self.struct_layouts[decl.name] = fields
      }
      None => ()
    }
  }
}

///|
fn darwin_field_receiver_type(ty : @parser.Type) -> @parser.Type? {
  match peel_aligned_type(ty) {
    Struct(name) => Some(Struct(name))
    Union(name) => Some(Union(name))
    Pointer(inner) =>
      match peel_aligned_type(inner) {
        Struct(name) => Some(Struct(name))
        Union(name) => Some(Union(name))
        _ => None
      }
    _ => None
  }
}

///|
fn Codegen::find_field_layout(
  self : Codegen,
  struct_name : String,
  field : String,
) -> (String, @parser.Type, Int, Int, Int, Int)? {
  match self.mir_module {
    Some(mir) => {
      let ty = match mir.aggregates.get(struct_name) {
        Some(decl) =>
          if decl.is_union {
            @parser.Type::Union(struct_name)
          } else {
            @parser.Type::Struct(struct_name)
          }
        None =>
          if self.struct_decls.contains(struct_name) &&
            self.struct_decls[struct_name].is_union {
            @parser.Type::Union(struct_name)
          } else {
            @parser.Type::Struct(struct_name)
          }
      }
      match mir.field_layout(ty, field) {
        Some(layout) => return Some(darwin_field_layout_tuple(layout))
        None => return None
      }
    }
    None => ()
  }
  if !self.struct_layouts.contains(struct_name) {
    return None
  }
  for f in self.struct_layouts[struct_name] {
    if f.0 == field {
      return Some(f)
    }
  }
  None
}

///|
fn Codegen::find_field_layout_for_type(
  self : Codegen,
  ty : @parser.Type,
  field : String,
) -> (String, @parser.Type, Int, Int, Int, Int)? {
  let lookup_ty = match darwin_field_receiver_type(ty) {
    Some(lookup_ty) => lookup_ty
    None => return None
  }
  match self.mir_module {
    Some(mir) =>
      match mir.field_layout(lookup_ty, field) {
        Some(layout) => return Some(darwin_field_layout_tuple(layout))
        None => return None
      }
    None => ()
  }
  match lookup_ty {
    Struct(name) | Union(name) => self.find_field_layout(name, field)
    _ => None
  }
}

///|
fn Codegen::offset_of_path(
  self : Codegen,
  ty : @parser.Type,
  path : Array[@parser.OffsetDesignator],
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
        match self.find_field_layout_for_type(current_ty, field) {
          Some((_, field_ty, field_offset, _, _, _)) => {
            offset += field_offset
            current_ty = field_ty
          }
          None => return None
        }
      OffsetIndex(index) =>
        match offset_array_element_type(current_ty) {
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
fn offset_array_element_type(ty : @parser.Type) -> @parser.Type? {
  match peel_aligned_type(ty) {
    Array(elem, _) => Some(elem)
    _ => None
  }
}
