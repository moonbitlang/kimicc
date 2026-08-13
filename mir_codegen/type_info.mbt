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
    Named(name) => abort("named type has no layout known to codegen: " + name)
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
    Named(name) =>
      abort("named type has no alignment known to codegen: " + name)
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
