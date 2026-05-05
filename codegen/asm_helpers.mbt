///|
// Check if a value fits in ARM64 movz/movn immediate encoding.
fn fits_mov_imm(n : Int64) -> Bool {
  let shifts = [0, 16, 32, 48]
  if n >= 0 {
    for shift in shifts {
      let imm16 = n >> shift
      if imm16 << shift == n && imm16 <= 65535 {
        return true
      }
    }
  } else {
    // movn: n = -(imm16 << shift) - 1  =>  -n - 1 = imm16 << shift
    let m = -n - 1
    for shift in shifts {
      let imm16 = m >> shift
      if imm16 << shift == m && imm16 <= 65535 {
        return true
      }
    }
  }
  false
}

///|
// Emit instruction(s) to load a 32-bit signed constant into a 64-bit register.
// Uses mov/movn when possible, otherwise movz + movk sequence.
fn Codegen::emit_load_int(self : Codegen, reg : String, n : Int64) -> Unit {
  if fits_mov_imm(n) {
    self.emit("\tmov\t" + reg + ", #" + n.to_string())
    return
  }
  // Decompose into 16-bit chunks. For negative values we need sign-extension.
  let low = (n & 0xFFFFL).to_int()
  let high = ((n >> 16) & 0xFFFFL).to_int()
  if n >= 0 {
    // Zero-extended 32-bit value in 64-bit register
    self.emit("\tmovz\t" + reg + ", #" + low.to_string())
    if high != 0 {
      self.emit("\tmovk\t" + reg + ", #" + high.to_string() + ", lsl #16")
    }
  } else {
    // Sign-extended 32-bit value: 0xFFFFFFFFnnnnnnnn
    self.emit("\tmovz\t" + reg + ", #" + low.to_string())
    self.emit("\tmovk\t" + reg + ", #" + high.to_string() + ", lsl #16")
    self.emit("\tmovk\t" + reg + ", #65535, lsl #32")
    self.emit("\tmovk\t" + reg + ", #65535, lsl #48")
  }
}

///|
// Sanitize a label name for assembler output.
fn sanitize_label(name : String) -> String {
  let buf = StringBuilder::new()
  for ch in name {
    match ch {
      '-' | '*' | ' ' | '.' | '@' | '$' | '#' => buf.write_char('_')
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
// Convert xN register name to wN for 32-bit operations.
fn w_reg(x : String) -> String {
  match x {
    "x9" => "w9"
    "x10" => "w10"
    "x11" => "w11"
    "x12" => "w12"
    "x13" => "w13"
    "x14" => "w14"
    "x15" => "w15"
    _ => x
  }
}

///|
// Load a value of type ty from [addr_reg] into reg.
// Uses correct width and sign/zero extension.
fn Codegen::emit_load_typed(
  self : Codegen,
  reg : String,
  addr_reg : String,
  ty : @parser.Type,
) -> Unit {
  match ty {
    Bool | UChar => self.emit("\tldrb\t" + w_reg(reg) + ", [" + addr_reg + "]")
    SChar => {
      self.emit("\tldrb\t" + w_reg(reg) + ", [" + addr_reg + "]")
      self.emit("\tsxtb\t" + reg + ", " + w_reg(reg))
    }
    UShort => self.emit("\tldrh\t" + w_reg(reg) + ", [" + addr_reg + "]")
    SShort => {
      self.emit("\tldrh\t" + w_reg(reg) + ", [" + addr_reg + "]")
      self.emit("\tsxth\t" + reg + ", " + w_reg(reg))
    }
    UInt => self.emit("\tldr\t" + w_reg(reg) + ", [" + addr_reg + "]")
    SInt => {
      self.emit("\tldr\t" + w_reg(reg) + ", [" + addr_reg + "]")
      self.emit("\tsxtw\t" + reg + ", " + w_reg(reg))
    }
    Atomic(inner) => self.emit_load_typed(reg, addr_reg, inner)
    _ => self.emit("\tldr\t" + reg + ", [" + addr_reg + "]")
  }
}

///|
// Store a value of type ty from value_reg to [addr_reg].
fn Codegen::emit_store_typed(
  self : Codegen,
  value_reg : String,
  addr_reg : String,
  ty : @parser.Type,
) -> Unit {
  match ty {
    Bool | SChar | UChar =>
      self.emit("\tstrb\t" + w_reg(value_reg) + ", [" + addr_reg + "]")
    SShort | UShort =>
      self.emit("\tstrh\t" + w_reg(value_reg) + ", [" + addr_reg + "]")
    SInt | UInt | Float =>
      self.emit("\tstr\t" + w_reg(value_reg) + ", [" + addr_reg + "]")
    Atomic(inner) => self.emit_store_typed(value_reg, addr_reg, inner)
    _ => self.emit("\tstr\t" + value_reg + ", [" + addr_reg + "]")
  }
}

///|
// Get or create the assembly label name for an AST label.

///|
fn is_digit_char(ch : UInt16) -> Bool {
  ch >= '0'.to_int().to_uint16() && ch <= '9'.to_int().to_uint16()
}

///|
fn is_numeric_case_label(name : String) -> Bool {
  if not(name.starts_with("case_")) {
    return false
  }
  for i = 5; i < name.length(); i = i + 1 {
    if not(is_digit_char(name[i])) {
      return false
    }
  }
  true
}

///|
// Case/default labels and regular labels both need stable assembly labels:
// switch dispatch may reference a case label before its statement is emitted.
fn Codegen::label_ref(self : Codegen, name : String) -> String {
  match self.emitted_labels.get(name) {
    Some(label) => label
    None => {
      let label = if name == "default" ||
        is_numeric_case_label(name) ||
        name.starts_with("__kimicc_case_") ||
        name.starts_with("__kimicc_default_") {
        self.new_label()
      } else {
        "_" + self.func_name + "_label_" + sanitize_label(name)
      }
      self.emitted_labels[name] = label
      label
    }
  }
}

///|
// Check if an integer fits in ARM64 cmp immediate encoding.
// Valid: 0..4095 or k*4096 where 1<=k<=4095 (and negatives via cmn).
fn fits_cmp_imm(n : Int64) -> Bool {
  if n < 0 {
    let m = -n
    m <= 4095 || (m % 4096 == 0 && m <= 16773120)
  } else {
    n <= 4095 || (n % 4096 == 0 && n <= 16773120)
  }
}
