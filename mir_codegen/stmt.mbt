///|
fn switch_control_type(ty : @parser.Type) -> @parser.Type {
  match ty {
    Atomic(inner) => switch_control_type(inner)
    Aligned(inner, _) => switch_control_type(inner)
    Bool | SChar | UChar | SShort | UShort => SInt
    _ => ty
  }
}

///|
fn Codegen::emit_switch_case_compare(
  self : Codegen,
  case_value : Int64,
  control_ty : @parser.Type,
) -> Unit {
  match control_ty {
    SInt | UInt => {
      let case32 = case_value & 0xFFFFFFFFL
      self.emit_load_int("x10", case32)
      self.emit("\tcmp\tw9, w10")
    }
    _ =>
      if fits_cmp_imm(case_value) {
        self.emit("\tcmp\tx9, #" + case_value.to_string())
      } else {
        self.emit_load_int("x10", case_value)
        self.emit("\tcmp\tx9, x10")
      }
  }
}
