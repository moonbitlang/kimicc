///|
fn Codegen::emit_store_local(
  self : Codegen,
  src_reg : String,
  offset : Int,
  frame_size : Int,
) -> Unit {
  let off = offset - frame_size
  if off >= -256 && off <= 255 {
    self.emit("\tstr\t" + src_reg + ", [x29, #" + off.to_string() + "]")
  } else {
    self.emit("\tmov\tx12, #" + off.to_string())
    self.emit("\tstr\t" + src_reg + ", [x29, x12]")
  }
}

///|
fn Codegen::emit_local_addr(
  self : Codegen,
  offset : Int,
  frame_size : Int,
) -> Unit {
  let off = offset - frame_size
  if off >= -256 && off <= 255 {
    self.emit("\tadd\tx9, x29, #" + off.to_string())
  } else {
    self.emit("\tmov\tx12, #" + off.to_string())
    self.emit("\tadd\tx9, x29, x12")
  }
}

///|
fn Codegen::alloc_local(self : Codegen, name : String, ty : @ctype.Type) -> Int {
  let size = self.type_size(ty)
  let natural_align = self.type_align(ty)
  let align = if natural_align > 8 { natural_align } else { 8 }
  let padding = (align - self.stack_size % align) % align
  self.stack_size += padding
  let aligned_size = (size + align - 1) / align * align
  let offset = self.stack_size
  self.stack_size += aligned_size
  self.local_offsets[name] = offset
  self.var_types[name] = ty
  offset
}
