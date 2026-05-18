///|
fn Codegen::type_size(self : Codegen, ty : @ctype.Type) -> Int {
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
    Atomic(inner) | Aligned(inner, _) => self.type_size(inner)
    Struct(name) | Union(name) =>
      match self.mir_aggregate_layout(name) {
        Some(layout) => layout.size
        None => 8
      }
  }
}

///|
fn Codegen::type_align(self : Codegen, ty : @ctype.Type) -> Int {
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
    Atomic(inner) => self.type_align(inner)
    Aligned(inner, align) => {
      let inner_align = self.type_align(inner)
      if align > inner_align {
        align
      } else {
        inner_align
      }
    }
    Struct(name) | Union(name) =>
      match self.mir_aggregate_layout(name) {
        Some(layout) => layout.align
        None => 8
      }
  }
}

///|
fn darwin_field_layout_tuple(
  layout : @mir.FieldLayout,
) -> (String, @ctype.Type, Int, Int, Int, Int) {
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
        let fields : Array[(String, @ctype.Type, Int, Int, Int, Int)] = []
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
fn darwin_field_receiver_type(ty : @ctype.Type) -> @ctype.Type? {
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
) -> (String, @ctype.Type, Int, Int, Int, Int)? {
  match self.mir_module {
    Some(mir) => {
      let ty = match mir.aggregates.get(struct_name) {
        Some(decl) =>
          if decl.is_union {
            @ctype.Type::Union(struct_name)
          } else {
            @ctype.Type::Struct(struct_name)
          }
        None => @ctype.Type::Struct(struct_name)
      }
      match mir.field_layout(ty, field) {
        Some(layout) => return Some(darwin_field_layout_tuple(layout))
        None => return None
      }
    }
    None => ()
  }
  match self.struct_layouts.get(struct_name) {
    Some(fields) =>
      for field_info in fields {
        if field_info.0 == field {
          return Some(field_info)
        }
      }
    None => ()
  }
  None
}

///|
fn Codegen::find_field_layout_for_type(
  self : Codegen,
  ty : @ctype.Type,
  field : String,
) -> (String, @ctype.Type, Int, Int, Int, Int)? {
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
fn offset_array_element_type(ty : @ctype.Type) -> @ctype.Type? {
  match peel_aligned_type(ty) {
    Array(elem, _) => Some(elem)
    _ => None
  }
}
