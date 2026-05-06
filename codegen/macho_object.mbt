///|
priv struct PendingBranch {
  section_index : Int
  offset : Int
  label : String
  link : Bool
}

///|
priv struct PendingCbz {
  section_index : Int
  offset : Int
  label : String
  reg : Int
  nonzero : Bool
}

///|
priv struct PendingCondBranch {
  section_index : Int
  offset : Int
  label : String
  cond : String
}

///|
priv struct SymbolLocation {
  section_index : Int
  offset : Int
}

///|
priv struct ObjectSection {
  sectname : String
  segname : String
  flags : UInt
  mut align_power : Int
  bytes : Array[Int]
  relocs : Array[Relocation]
  mut addr : Int
  mut offset : Int
  mut reloff : Int
}

///|
priv struct AssembledObject {
  sections : Array[ObjectSection]
  globals : Array[String]
  defined_symbols : Array[String]
  symbols : Map[String, SymbolLocation]
}

///|
priv struct Relocation {
  address : Int
  symbol : String
  pcrel : Bool
  length : Int
  external : Bool
  type_ : Int
}

///|
priv struct SymbolAddend {
  symbol : String
  addend : Int
}

///|
priv struct SymbolEntry {
  name : String
  type_ : Int
  section_index : Int
  value : Int
}

///|
priv struct SymbolLayout {
  entries : Array[SymbolEntry]
  indexes : Map[String, Int]
  nlocals : Int
  nextdefs : Int
  nundefs : Int
}

///|
fn write_u32_le(buf : @buffer.Buffer, value : UInt) -> Unit {
  buf.write_byte((value & 0xffU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 8) & 0xffU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 16) & 0xffU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 24) & 0xffU).reinterpret_as_int().to_byte())
}

///|
fn write_u16_le(buf : @buffer.Buffer, value : Int) -> Unit {
  let v = value.reinterpret_as_uint()
  buf.write_byte((v & 0xffU).reinterpret_as_int().to_byte())
  buf.write_byte(((v >> 8) & 0xffU).reinterpret_as_int().to_byte())
}

///|
fn write_i32_le(buf : @buffer.Buffer, value : Int) -> Unit {
  write_u32_le(buf, value.reinterpret_as_uint())
}

///|
fn write_u64_le(buf : @buffer.Buffer, value : Int64) -> Unit {
  buf.write_byte(((value >> 0) & 0xffL).to_int().to_byte())
  buf.write_byte(((value >> 8) & 0xffL).to_int().to_byte())
  buf.write_byte(((value >> 16) & 0xffL).to_int().to_byte())
  buf.write_byte(((value >> 24) & 0xffL).to_int().to_byte())
  buf.write_byte(((value >> 32) & 0xffL).to_int().to_byte())
  buf.write_byte(((value >> 40) & 0xffL).to_int().to_byte())
  buf.write_byte(((value >> 48) & 0xffL).to_int().to_byte())
  buf.write_byte(((value >> 56) & 0xffL).to_int().to_byte())
}

///|
fn write_fixed_ascii(buf : @buffer.Buffer, value : String, width : Int) -> Unit {
  let mut written = 0
  for ch in value {
    if written < width {
      buf.write_byte(ch.to_int().to_byte())
      written = written + 1
    }
  }
  while written < width {
    buf.write_byte((0).to_byte())
    written = written + 1
  }
}

///|
fn write_ascii_z(buf : @buffer.Buffer, value : String) -> Unit {
  for ch in value {
    buf.write_byte(ch.to_int().to_byte())
  }
  buf.write_byte((0).to_byte())
}

///|
fn align_int(value : Int, align : Int) -> Int {
  if align <= 1 {
    value
  } else {
    (value + align - 1) & -align
  }
}

///|
fn append_byte(section : ObjectSection, value : Int) -> Unit {
  section.bytes.push(value & 0xff)
}

///|
fn append_u16_to_section(section : ObjectSection, value : Int) -> Unit {
  let v = value.reinterpret_as_uint()
  append_byte(section, (v & 0xffU).reinterpret_as_int())
  append_byte(section, ((v >> 8) & 0xffU).reinterpret_as_int())
}

///|
fn append_u32_to_section(section : ObjectSection, value : UInt) -> Unit {
  append_byte(section, (value & 0xffU).reinterpret_as_int())
  append_byte(section, ((value >> 8) & 0xffU).reinterpret_as_int())
  append_byte(section, ((value >> 16) & 0xffU).reinterpret_as_int())
  append_byte(section, ((value >> 24) & 0xffU).reinterpret_as_int())
}

///|
fn append_i32_to_section(section : ObjectSection, value : Int) -> Unit {
  append_u32_to_section(section, value.reinterpret_as_uint())
}

///|
fn append_u64_to_section(section : ObjectSection, value : Int64) -> Unit {
  append_byte(section, ((value >> 0) & 0xffL).to_int())
  append_byte(section, ((value >> 8) & 0xffL).to_int())
  append_byte(section, ((value >> 16) & 0xffL).to_int())
  append_byte(section, ((value >> 24) & 0xffL).to_int())
  append_byte(section, ((value >> 32) & 0xffL).to_int())
  append_byte(section, ((value >> 40) & 0xffL).to_int())
  append_byte(section, ((value >> 48) & 0xffL).to_int())
  append_byte(section, ((value >> 56) & 0xffL).to_int())
}

///|
fn append_u64_bits_to_section(section : ObjectSection, value : UInt64) -> Unit {
  append_byte(section, ((value >> 0) & 0xffUL).to_int())
  append_byte(section, ((value >> 8) & 0xffUL).to_int())
  append_byte(section, ((value >> 16) & 0xffUL).to_int())
  append_byte(section, ((value >> 24) & 0xffUL).to_int())
  append_byte(section, ((value >> 32) & 0xffUL).to_int())
  append_byte(section, ((value >> 40) & 0xffUL).to_int())
  append_byte(section, ((value >> 48) & 0xffUL).to_int())
  append_byte(section, ((value >> 56) & 0xffUL).to_int())
}

///|
fn patch_u32_in_section(
  section : ObjectSection,
  offset : Int,
  value : UInt,
) -> Unit {
  section.bytes[offset] = (value & 0xffU).reinterpret_as_int()
  section.bytes[offset + 1] = ((value >> 8) & 0xffU).reinterpret_as_int()
  section.bytes[offset + 2] = ((value >> 16) & 0xffU).reinterpret_as_int()
  section.bytes[offset + 3] = ((value >> 24) & 0xffU).reinterpret_as_int()
}

///|
fn align_section(
  section : ObjectSection,
  align : Int,
  text_fill : Bool,
) -> Unit {
  while (section.bytes.length() & (align - 1)) != 0 {
    if text_fill &&
      section.bytes.length() % 4 == 0 &&
      section.bytes.length() + 4 <= align_int(section.bytes.length(), align) {
      append_u32_to_section(section, 0xd503201fU)
    } else {
      append_byte(section, 0)
    }
  }
}

///|
fn section_is_text(section : ObjectSection) -> Bool {
  section.segname == "__TEXT" && section.sectname == "__text"
}

///|
fn section_is_zerofill(section : ObjectSection) -> Bool {
  (section.flags & 0xffU) == 0x00000001U
}

///|
fn write_padding_to_offset(buf : @buffer.Buffer, offset : Int) -> Unit {
  while buf.length() < offset {
    buf.write_byte((0).to_byte())
  }
  if buf.length() > offset {
    abort("Mach-O section layout wrote past expected offset")
  }
}

///|
fn parse_int_or_abort(value : String, context : String) -> Int {
  @string.parse_int(value) catch {
    _ => abort("cannot parse integer in " + context + ": " + value)
  }
}

///|
fn parse_register(reg : String) -> Int {
  if reg == "sp" || reg == "xzr" || reg == "wzr" {
    31
  } else if reg.has_prefix("x") || reg.has_prefix("w") {
    parse_int_or_abort(reg.substring(start=1), "register")
  } else {
    abort("unsupported register in object backend: " + reg)
  }
}

///|
fn parse_fp_register(reg : String) -> Int {
  if reg.has_prefix("d") || reg.has_prefix("s") {
    parse_int_or_abort(reg.substring(start=1), "floating-point register")
  } else {
    abort("unsupported floating-point register in object backend: " + reg)
  }
}

///|
fn is_fp_register(reg : String) -> Bool {
  reg.has_prefix("d") || reg.has_prefix("s")
}

///|
fn fp_register_scale(reg : String) -> Int {
  if reg.has_prefix("d") {
    8
  } else if reg.has_prefix("s") {
    4
  } else {
    abort("unsupported floating-point register in object backend: " + reg)
  }
}

///|
fn parse_immediate(imm : String) -> Int {
  let s = imm.trim().to_string()
  if s.has_prefix("#") {
    parse_int_or_abort(s.substring(start=1), "immediate")
  } else {
    parse_int_or_abort(s, "immediate")
  }
}

///|
fn digit_value_or_abort(ch : Char, base : Int, context : String) -> Int {
  let digit = if ch >= '0' && ch <= '9' {
    ch.to_int() - '0'.to_int()
  } else if ch >= 'a' && ch <= 'f' {
    ch.to_int() - 'a'.to_int() + 10
  } else if ch >= 'A' && ch <= 'F' {
    ch.to_int() - 'A'.to_int() + 10
  } else {
    abort("invalid digit in " + context)
  }
  if digit >= base {
    abort("invalid digit in " + context)
  }
  digit
}

///|
fn parse_immediate_i64(imm : String) -> Int64 {
  let s = imm.trim().to_string()
  let mut text = if s.has_prefix("#") {
    s.substring(start=1).to_string()
  } else {
    s
  }
  let mut sign = 1L
  if text.has_prefix("-") {
    sign = -1L
    text = text.substring(start=1).to_string()
  }
  let mut base = 10
  if text.has_prefix("0x") || text.has_prefix("0X") {
    base = 16
    text = text.substring(start=2).to_string()
  }
  if text.length() == 0 {
    abort("empty immediate")
  }
  let mut value = 0L
  for ch in text {
    value = value * base.to_int64() +
      digit_value_or_abort(ch, base, "immediate").to_int64()
  }
  value * sign
}

///|
fn clean_mem_token(token : String) -> String {
  token
  .replace_all(old="[", new="")
  .replace_all(old="]", new="")
  .replace_all(old="!", new="")
  .trim()
  .to_string()
}

///|
fn split_operands(rest : String) -> Array[String] {
  let parts : Array[String] = []
  for part in rest.split(",") {
    parts.push(part.to_string().trim().to_string())
  }
  parts
}

///|
fn encode_add_sub_imm(
  dst : String,
  src : String,
  imm : Int,
  is_sub : Bool,
) -> UInt {
  let rd = parse_register(dst)
  let rn = parse_register(src)
  if imm < 0 {
    encode_add_sub_imm(dst, src, -imm, !is_sub)
  } else {
    let base = if is_sub { 0xd1000000U } else { 0x91000000U }
    base |
    (imm.reinterpret_as_uint() << 10) |
    (rn.reinterpret_as_uint() << 5) |
    rd.reinterpret_as_uint()
  }
}

///|
fn encode_add_sub_reg(
  dst : String,
  left : String,
  right : String,
  is_sub : Bool,
) -> UInt {
  let rd = parse_register(dst)
  let rn = parse_register(left)
  let rm = parse_register(right)
  let base = if is_sub { 0xcb000000U } else { 0x8b000000U }
  base |
  (rm.reinterpret_as_uint() << 16) |
  (rn.reinterpret_as_uint() << 5) |
  rd.reinterpret_as_uint()
}

///|
fn encode_add_sub(rest : String, is_sub : Bool) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 3 {
    abort("malformed add/sub instruction")
  }
  if parts[2].has_prefix("#") {
    encode_add_sub_imm(parts[0], parts[1], parse_immediate(parts[2]), is_sub)
  } else {
    encode_add_sub_reg(parts[0], parts[1], parts[2], is_sub)
  }
}

///|
fn encode_mul(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 3 {
    abort("malformed mul instruction")
  }
  let rd = parse_register(parts[0])
  let rn = parse_register(parts[1])
  let rm = parse_register(parts[2])
  0x9b007c00U |
  (rm.reinterpret_as_uint() << 16) |
  (rn.reinterpret_as_uint() << 5) |
  rd.reinterpret_as_uint()
}

///|
fn encode_madd(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 4 {
    abort("malformed madd instruction")
  }
  let rd = parse_register(parts[0])
  let rn = parse_register(parts[1])
  let rm = parse_register(parts[2])
  let ra = parse_register(parts[3])
  0x9b000000U |
  (rm.reinterpret_as_uint() << 16) |
  (ra.reinterpret_as_uint() << 10) |
  (rn.reinterpret_as_uint() << 5) |
  rd.reinterpret_as_uint()
}

///|
fn encode_msub(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 4 {
    abort("malformed msub instruction")
  }
  let rd = parse_register(parts[0])
  let rn = parse_register(parts[1])
  let rm = parse_register(parts[2])
  let ra = parse_register(parts[3])
  0x9b008000U |
  (rm.reinterpret_as_uint() << 16) |
  (ra.reinterpret_as_uint() << 10) |
  (rn.reinterpret_as_uint() << 5) |
  rd.reinterpret_as_uint()
}

///|
fn encode_sdiv(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 3 {
    abort("malformed sdiv instruction")
  }
  let rd = parse_register(parts[0])
  let rn = parse_register(parts[1])
  let rm = parse_register(parts[2])
  0x9ac00c00U |
  (rm.reinterpret_as_uint() << 16) |
  (rn.reinterpret_as_uint() << 5) |
  rd.reinterpret_as_uint()
}

///|
fn encode_three_register(rest : String, base : UInt, name : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 3 {
    abort("malformed " + name + " instruction")
  }
  let rd = parse_register(parts[0])
  let rn = parse_register(parts[1])
  let rm = parse_register(parts[2])
  base |
  (rm.reinterpret_as_uint() << 16) |
  (rn.reinterpret_as_uint() << 5) |
  rd.reinterpret_as_uint()
}

///|
fn encode_shift(rest : String, kind : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 3 {
    abort("malformed " + kind + " instruction")
  }
  if !parts[2].has_prefix("#") {
    let base = match kind {
      "lsl" => 0x9ac02000U
      "lsr" => 0x9ac02400U
      "asr" => 0x9ac02800U
      _ => abort("unsupported shift instruction: " + kind)
    }
    encode_three_register(rest, base, kind)
  } else {
    let rd = parse_register(parts[0])
    let rn = parse_register(parts[1])
    let shift = parse_immediate(parts[2])
    let wide = !parts[0].has_prefix("w")
    let width = if wide { 64 } else { 32 }
    if shift < 0 || shift >= width {
      abort("shift immediate out of range: " + parts[2])
    }
    let base = match kind {
      "lsl" => if wide { 0xd3400000U } else { 0x53000000U }
      "lsr" => if wide { 0xd3400000U } else { 0x53000000U }
      "asr" => if wide { 0x93400000U } else { 0x13000000U }
      _ => abort("unsupported shift instruction: " + kind)
    }
    let immr = if kind == "lsl" && shift != 0 { width - shift } else { shift }
    let imms = if kind == "lsl" { width - 1 - shift } else { width - 1 }
    base |
    (immr.reinterpret_as_uint() << 16) |
    (imms.reinterpret_as_uint() << 10) |
    (rn.reinterpret_as_uint() << 5) |
    rd.reinterpret_as_uint()
  }
}

///|
fn encode_and(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 3 {
    abort("malformed and instruction")
  }
  if parts[2].has_prefix("#") {
    let rd = parse_register(parts[0])
    let rn = parse_register(parts[1])
    let is_wide = !parts[0].has_prefix("w")
    let base = match parts[2] {
      "#0xFF" => if is_wide { 0x92401c00U } else { 0x12001c00U }
      "#0xFFFF" => if is_wide { 0x92403c00U } else { 0x12003c00U }
      "#0xFFFFFFFF" =>
        if is_wide {
          0x92407c00U
        } else {
          abort("unsupported 32-bit and immediate: " + parts[2])
        }
      _ => abort("unsupported and immediate: " + parts[2])
    }
    base | (rn.reinterpret_as_uint() << 5) | rd.reinterpret_as_uint()
  } else {
    encode_three_register(rest, 0x8a000000U, "and")
  }
}

///|
fn encode_cmp(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 2 {
    abort("malformed cmp instruction")
  }
  let rn = parse_register(parts[0])
  if parts[1].has_prefix("#") {
    let imm = parse_immediate(parts[1])
    let base = if parts[0].has_prefix("w") { 0x7100001fU } else { 0xf100001fU }
    base | (imm.reinterpret_as_uint() << 10) | (rn.reinterpret_as_uint() << 5)
  } else {
    let rm = parse_register(parts[1])
    let base = if parts[0].has_prefix("w") { 0x6b00001fU } else { 0xeb00001fU }
    base | (rm.reinterpret_as_uint() << 16) | (rn.reinterpret_as_uint() << 5)
  }
}

///|
fn condition_code(cond : String) -> Int {
  match cond {
    "eq" => 0
    "ne" => 1
    "hs" | "cs" => 2
    "lo" | "cc" => 3
    "mi" => 4
    "pl" => 5
    "vs" => 6
    "vc" => 7
    "hi" => 8
    "ls" => 9
    "ge" => 10
    "lt" => 11
    "gt" => 12
    "le" => 13
    _ => abort("unsupported condition: " + cond)
  }
}

///|
fn inverted_condition_code(cond : String) -> Int {
  condition_code(cond) ^ 1
}

///|
fn encode_cset(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 2 {
    abort("malformed cset instruction")
  }
  let rd = parse_register(parts[0])
  let cond = inverted_condition_code(parts[1])
  0x9a9f07e0U | (cond.reinterpret_as_uint() << 12) | rd.reinterpret_as_uint()
}

///|
fn encode_mov_reg(dst : String, src : String) -> UInt {
  let rd = parse_register(dst)
  let rn = parse_register(src)
  if dst == "sp" || src == "sp" {
    0x91000000U | (rn.reinterpret_as_uint() << 5) | rd.reinterpret_as_uint()
  } else {
    0xaa0003e0U | (rn.reinterpret_as_uint() << 16) | rd.reinterpret_as_uint()
  }
}

///|
fn encode_stur_64(
  rt_text : String,
  base_text : String,
  offset_text : String,
) -> UInt {
  let rt = parse_register(rt_text)
  let rn = parse_register(clean_mem_token(base_text))
  let offset = parse_immediate(clean_mem_token(offset_text))
  0xf8000000U |
  ((offset & 0x1ff).reinterpret_as_uint() << 12) |
  (rn.reinterpret_as_uint() << 5) |
  rt.reinterpret_as_uint()
}

///|
fn encode_str_pre_64(
  rt_text : String,
  base_text : String,
  offset_text : String,
) -> UInt {
  let rt = parse_register(rt_text)
  let rn = parse_register(clean_mem_token(base_text))
  let offset = parse_immediate(clean_mem_token(offset_text))
  0xf8000c00U |
  ((offset & 0x1ff).reinterpret_as_uint() << 12) |
  (rn.reinterpret_as_uint() << 5) |
  rt.reinterpret_as_uint()
}

///|
fn encode_fp_mem_signed(
  rt_text : String,
  base_text : String,
  offset_text : String,
  is_load : Bool,
) -> UInt {
  let rt = parse_fp_register(rt_text)
  let rn = parse_register(clean_mem_token(base_text))
  let offset = parse_immediate(clean_mem_token(offset_text))
  let base = if rt_text.has_prefix("d") {
    if is_load {
      0xfc400000U
    } else {
      0xfc000000U
    }
  } else if is_load {
    0xbc400000U
  } else {
    0xbc000000U
  }
  base |
  ((offset & 0x1ff).reinterpret_as_uint() << 12) |
  (rn.reinterpret_as_uint() << 5) |
  rt.reinterpret_as_uint()
}

///|
fn encode_fp_mem_pre(
  rt_text : String,
  base_text : String,
  offset_text : String,
  is_load : Bool,
) -> UInt {
  encode_fp_mem_signed(rt_text, base_text, offset_text, is_load) | 0x00000c00U
}

///|
fn encode_fp_mem_unsigned(
  rt_text : String,
  base_text : String,
  offset_text : String,
  is_load : Bool,
) -> UInt {
  let rt = parse_fp_register(rt_text)
  let rn = parse_register(clean_mem_token(base_text))
  let offset = parse_immediate(clean_mem_token(offset_text))
  let scale = fp_register_scale(rt_text)
  let base = if rt_text.has_prefix("d") {
    if is_load {
      0xfd400000U
    } else {
      0xfd000000U
    }
  } else if is_load {
    0xbd400000U
  } else {
    0xbd000000U
  }
  base |
  ((offset / scale).reinterpret_as_uint() << 10) |
  (rn.reinterpret_as_uint() << 5) |
  rt.reinterpret_as_uint()
}

///|
fn encode_fp_mem(
  rt_text : String,
  base_text : String,
  offset_text : String,
  is_load : Bool,
) -> UInt {
  let cleaned_offset = clean_mem_token(offset_text)
  let offset = parse_immediate(cleaned_offset)
  let scale = fp_register_scale(rt_text)
  if offset >= 0 && offset % scale == 0 {
    encode_fp_mem_unsigned(rt_text, base_text, offset_text, is_load)
  } else {
    encode_fp_mem_signed(rt_text, base_text, offset_text, is_load)
  }
}

///|
fn encode_ldr_unsigned(rt_text : String, base_text : String) -> UInt {
  let rt = parse_register(rt_text)
  let rn = parse_register(clean_mem_token(base_text))
  let base = if rt_text.has_prefix("w") { 0xb9400000U } else { 0xf9400000U }
  base | (rn.reinterpret_as_uint() << 5) | rt.reinterpret_as_uint()
}

///|
fn encode_ldr_unsigned_offset(
  rt_text : String,
  base_text : String,
  offset_text : String,
) -> UInt {
  let rt = parse_register(rt_text)
  let rn = parse_register(clean_mem_token(base_text))
  let offset = parse_immediate(clean_mem_token(offset_text))
  let scale = if rt_text.has_prefix("w") { 4 } else { 8 }
  let base = if rt_text.has_prefix("w") { 0xb9400000U } else { 0xf9400000U }
  base |
  ((offset / scale).reinterpret_as_uint() << 10) |
  (rn.reinterpret_as_uint() << 5) |
  rt.reinterpret_as_uint()
}

///|
fn encode_ldr_post_64(
  rt_text : String,
  base_text : String,
  offset_text : String,
) -> UInt {
  let rt = parse_register(rt_text)
  let rn = parse_register(clean_mem_token(base_text))
  let offset = parse_immediate(clean_mem_token(offset_text))
  0xf8400400U |
  ((offset & 0x1ff).reinterpret_as_uint() << 12) |
  (rn.reinterpret_as_uint() << 5) |
  rt.reinterpret_as_uint()
}

///|
fn is_register_name(text : String) -> Bool {
  text == "sp" || text.has_prefix("x") || text.has_prefix("w")
}

///|
fn encode_register_offset_memory(
  rt_text : String,
  base_text : String,
  offset_text : String,
  is_load : Bool,
) -> UInt {
  let rt = parse_register(rt_text)
  let rn = parse_register(clean_mem_token(base_text))
  let rm = parse_register(clean_mem_token(offset_text))
  let base = if rt_text.has_prefix("w") {
    if is_load {
      0xb8606800U
    } else {
      0xb8206800U
    }
  } else if is_load {
    0xf8606800U
  } else {
    0xf8206800U
  }
  base |
  (rm.reinterpret_as_uint() << 16) |
  (rn.reinterpret_as_uint() << 5) |
  rt.reinterpret_as_uint()
}

///|
fn encode_str(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() == 2 && is_fp_register(parts[0]) {
    encode_fp_mem_unsigned(parts[0], parts[1], "#0", false)
  } else if parts.length() == 2 {
    let rt = parse_register(parts[0])
    let rn = parse_register(clean_mem_token(parts[1]))
    let base = if parts[0].has_prefix("w") { 0xb9000000U } else { 0xf9000000U }
    base | (rn.reinterpret_as_uint() << 5) | rt.reinterpret_as_uint()
  } else if parts.length() != 3 {
    abort("malformed str instruction")
  } else if is_fp_register(parts[0]) {
    if parts[2].has_suffix("]!") {
      encode_fp_mem_pre(parts[0], parts[1], parts[2], false)
    } else {
      encode_fp_mem(parts[0], parts[1], parts[2], false)
    }
  } else if parts[2].has_suffix("]!") {
    encode_str_pre_64(parts[0], parts[1], parts[2])
  } else if is_register_name(clean_mem_token(parts[2])) {
    encode_register_offset_memory(parts[0], parts[1], parts[2], false)
  } else {
    encode_stur_64(parts[0], parts[1], parts[2])
  }
}

///|
fn encode_ldr(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() == 2 && is_fp_register(parts[0]) {
    encode_fp_mem_unsigned(parts[0], parts[1], "#0", true)
  } else if parts.length() == 2 {
    encode_ldr_unsigned(parts[0], parts[1])
  } else if parts.length() == 3 {
    if is_fp_register(parts[0]) {
      if parts[1].has_suffix("]") {
        abort("unsupported post-index floating-point load in object backend")
      } else {
        encode_fp_mem(parts[0], parts[1], parts[2], true)
      }
    } else if parts[1].has_suffix("]") {
      encode_ldr_post_64(parts[0], parts[1], parts[2])
    } else if is_register_name(clean_mem_token(parts[2])) {
      encode_register_offset_memory(parts[0], parts[1], parts[2], true)
    } else {
      encode_ldr_unsigned_offset(parts[0], parts[1], parts[2])
    }
  } else {
    abort("malformed ldr instruction")
  }
}

///|
fn encode_movz(dst : String, imm : Int, shift : Int) -> UInt {
  let rd = parse_register(dst)
  let hw = shift / 16
  let base = if dst.has_prefix("w") { 0x52800000U } else { 0xd2800000U }
  base |
  (hw.reinterpret_as_uint() << 21) |
  (imm.reinterpret_as_uint() << 5) |
  rd.reinterpret_as_uint()
}

///|
fn encode_movk(dst : String, imm : Int, shift : Int) -> UInt {
  let rd = parse_register(dst)
  let hw = shift / 16
  let base = if dst.has_prefix("w") { 0x72800000U } else { 0xf2800000U }
  base |
  (hw.reinterpret_as_uint() << 21) |
  (imm.reinterpret_as_uint() << 5) |
  rd.reinterpret_as_uint()
}

///|
fn encode_movn(dst : String, imm : Int, shift : Int) -> UInt {
  let rd = parse_register(dst)
  let hw = shift / 16
  let base = if dst.has_prefix("w") { 0x12800000U } else { 0x92800000U }
  base |
  (hw.reinterpret_as_uint() << 21) |
  (imm.reinterpret_as_uint() << 5) |
  rd.reinterpret_as_uint()
}

///|
fn encode_sxtw(dst : String, src : String) -> UInt {
  let rd = parse_register(dst)
  let rn = parse_register(src)
  0x93407c00U | (rn.reinterpret_as_uint() << 5) | rd.reinterpret_as_uint()
}

///|
fn encode_sxtb(dst : String, src : String) -> UInt {
  let rd = parse_register(dst)
  let rn = parse_register(src)
  0x93401c00U | (rn.reinterpret_as_uint() << 5) | rd.reinterpret_as_uint()
}

///|
fn encode_sxth(dst : String, src : String) -> UInt {
  let rd = parse_register(dst)
  let rn = parse_register(src)
  0x93403c00U | (rn.reinterpret_as_uint() << 5) | rd.reinterpret_as_uint()
}

///|
fn encode_byte_halfword_memory(
  rest : String,
  base : UInt,
  scale : Int,
  name : String,
) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 2 && parts.length() != 3 {
    abort("malformed " + name + " instruction")
  }
  let rt = parse_register(parts[0])
  let rn = parse_register(clean_mem_token(parts[1]))
  let offset = if parts.length() == 3 {
    parse_immediate(clean_mem_token(parts[2]))
  } else {
    0
  }
  base |
  ((offset / scale).reinterpret_as_uint() << 10) |
  (rn.reinterpret_as_uint() << 5) |
  rt.reinterpret_as_uint()
}

///|
fn encode_mov_wide(rest : String, kind : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() < 2 {
    abort("malformed " + kind + " instruction")
  }
  let shift = if parts.length() >= 3 {
    let s = parts[2]
    if s.has_prefix("lsl #") {
      parse_int_or_abort(s.substring(start=5), kind + " shift")
    } else {
      abort("unsupported " + kind + " shift: " + s)
    }
  } else {
    0
  }
  let imm = parse_immediate(parts[1])
  match kind {
    "movz" => encode_movz(parts[0], imm, shift)
    "movk" => encode_movk(parts[0], imm, shift)
    "movn" => encode_movn(parts[0], imm, shift)
    _ => abort("unsupported wide move: " + kind)
  }
}

///|
fn encode_mov_immediate(dst : String, imm : Int64) -> UInt {
  let shifts = [0, 16, 32, 48]
  if imm >= 0L {
    for shift in shifts {
      let imm16 = imm >> shift
      if imm16 << shift == imm && imm16 <= 65535L {
        return encode_movz(dst, imm16.to_int(), shift)
      }
    }
  } else {
    let m = -imm - 1L
    for shift in shifts {
      let imm16 = m >> shift
      if imm16 << shift == m && imm16 <= 65535L {
        return encode_movn(dst, imm16.to_int(), shift)
      }
    }
  }
  abort("unsupported mov immediate in object backend: #" + imm.to_string())
}

///|
fn encode_mov(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 2 {
    abort("malformed mov instruction")
  }
  if parts[1].has_prefix("#") {
    encode_mov_immediate(parts[0], parse_immediate_i64(parts[1]))
  } else {
    encode_mov_reg(parts[0], parts[1])
  }
}

///|
fn encode_mvn(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 2 {
    abort("malformed mvn instruction")
  }
  let rd = parse_register(parts[0])
  let rm = parse_register(parts[1])
  let base = if parts[0].has_prefix("w") { 0x2a200000U } else { 0xaa200000U }
  base |
  (rm.reinterpret_as_uint() << 16) |
  (31U << 5) |
  rd.reinterpret_as_uint()
}

///|
fn encode_neg(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 2 {
    abort("malformed neg instruction")
  }
  let rd = parse_register(parts[0])
  let rm = parse_register(parts[1])
  let base = if parts[0].has_prefix("w") { 0x4b000000U } else { 0xcb000000U }
  base |
  (rm.reinterpret_as_uint() << 16) |
  (31U << 5) |
  rd.reinterpret_as_uint()
}

///|
fn encode_blr(rest : String) -> UInt {
  let rn = parse_register(rest.trim().to_string())
  0xd63f0000U | (rn.reinterpret_as_uint() << 5)
}

///|
fn encode_fmov(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 2 {
    abort("malformed fmov instruction")
  }
  if parts[0].has_prefix("d") && !is_fp_register(parts[1]) {
    let rd = parse_fp_register(parts[0])
    let rn = parse_register(parts[1])
    0x9e670000U | (rn.reinterpret_as_uint() << 5) | rd.reinterpret_as_uint()
  } else if parts[0].has_prefix("s") && !is_fp_register(parts[1]) {
    let rd = parse_fp_register(parts[0])
    let rn = parse_register(parts[1])
    0x1e270000U | (rn.reinterpret_as_uint() << 5) | rd.reinterpret_as_uint()
  } else if !is_fp_register(parts[0]) && parts[1].has_prefix("d") {
    let rd = parse_register(parts[0])
    let rn = parse_fp_register(parts[1])
    0x9e660000U | (rn.reinterpret_as_uint() << 5) | rd.reinterpret_as_uint()
  } else if !is_fp_register(parts[0]) && parts[1].has_prefix("s") {
    let rd = parse_register(parts[0])
    let rn = parse_fp_register(parts[1])
    0x1e260000U | (rn.reinterpret_as_uint() << 5) | rd.reinterpret_as_uint()
  } else {
    abort("unsupported fmov instruction in object backend: " + rest)
  }
}

///|
fn encode_fp_three_register(rest : String, base : UInt, name : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 3 {
    abort("malformed " + name + " instruction")
  }
  if !parts[0].has_prefix("d") ||
    !parts[1].has_prefix("d") ||
    !parts[2].has_prefix("d") {
    abort("unsupported " + name + " operand width in object backend")
  }
  let rd = parse_fp_register(parts[0])
  let rn = parse_fp_register(parts[1])
  let rm = parse_fp_register(parts[2])
  base |
  (rm.reinterpret_as_uint() << 16) |
  (rn.reinterpret_as_uint() << 5) |
  rd.reinterpret_as_uint()
}

///|
fn encode_fp_two_register(
  rest : String,
  double_base : UInt,
  single_base : UInt,
  name : String,
) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 2 {
    abort("malformed " + name + " instruction")
  }
  if (!parts[0].has_prefix("d") || !parts[1].has_prefix("d")) &&
    (!parts[0].has_prefix("s") || !parts[1].has_prefix("s")) {
    abort("unsupported " + name + " operand width in object backend")
  }
  let rd = parse_fp_register(parts[0])
  let rn = parse_fp_register(parts[1])
  let base = if parts[0].has_prefix("d") { double_base } else { single_base }
  base | (rn.reinterpret_as_uint() << 5) | rd.reinterpret_as_uint()
}

///|
fn encode_fp_precision_convert(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 2 {
    abort("malformed fcvt instruction")
  }
  let rd = parse_fp_register(parts[0])
  let rn = parse_fp_register(parts[1])
  if parts[0].has_prefix("d") && parts[1].has_prefix("s") {
    0x1e22c000U | (rn.reinterpret_as_uint() << 5) | rd.reinterpret_as_uint()
  } else if parts[0].has_prefix("s") && parts[1].has_prefix("d") {
    0x1e624000U | (rn.reinterpret_as_uint() << 5) | rd.reinterpret_as_uint()
  } else {
    abort("unsupported fcvt operand width in object backend")
  }
}

///|
fn encode_fcmp(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 2 {
    abort("malformed fcmp instruction")
  }
  if (!parts[0].has_prefix("d") || !parts[1].has_prefix("d")) &&
    (!parts[0].has_prefix("s") || !parts[1].has_prefix("s")) {
    abort("unsupported fcmp operand width in object backend")
  }
  let rn = parse_fp_register(parts[0])
  let rm = parse_fp_register(parts[1])
  let base = if parts[0].has_prefix("d") { 0x1e602000U } else { 0x1e202000U }
  base | (rm.reinterpret_as_uint() << 16) | (rn.reinterpret_as_uint() << 5)
}

///|
fn encode_fp_convert_to_int(rest : String, base : UInt, name : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 2 {
    abort("malformed " + name + " instruction")
  }
  if !parts[0].has_prefix("x") || !parts[1].has_prefix("d") {
    abort("unsupported " + name + " operand width in object backend")
  }
  let rd = parse_register(parts[0])
  let rn = parse_fp_register(parts[1])
  base | (rn.reinterpret_as_uint() << 5) | rd.reinterpret_as_uint()
}

///|
fn encode_int_convert_to_fp(
  rest : String,
  signed : Bool,
  name : String,
) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 2 {
    abort("malformed " + name + " instruction")
  }
  if !parts[0].has_prefix("d") ||
    (!parts[1].has_prefix("x") && !parts[1].has_prefix("w")) {
    abort("unsupported " + name + " operand width in object backend")
  }
  let rd = parse_fp_register(parts[0])
  let rn = parse_register(parts[1])
  let base = if parts[1].has_prefix("x") {
    if signed {
      0x9e620000U
    } else {
      0x9e630000U
    }
  } else if signed {
    0x1e620000U
  } else {
    0x1e630000U
  }
  base | (rn.reinterpret_as_uint() << 5) | rd.reinterpret_as_uint()
}

///|
fn encode_dmb(rest : String) -> UInt {
  let option = rest.trim().to_string()
  match option {
    "ish" => 0xd5033bbfU
    "ishld" => 0xd50339bfU
    "ishst" => 0xd5033abfU
    _ => abort("unsupported dmb option in object backend: " + option)
  }
}

///|
fn encode_atomic_memory(rest : String, base : UInt, name : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 2 {
    abort("malformed " + name + " instruction")
  }
  let rt = parse_register(parts[0])
  let rn = parse_register(clean_mem_token(parts[1]))
  base | (rn.reinterpret_as_uint() << 5) | rt.reinterpret_as_uint()
}

///|
fn encode_branch(from_offset : Int, target_offset : Int) -> UInt {
  encode_branch_with_base(from_offset, target_offset, 0x14000000U)
}

///|
fn encode_branch_link(from_offset : Int, target_offset : Int) -> UInt {
  encode_branch_with_base(from_offset, target_offset, 0x94000000U)
}

///|
fn encode_cbz(from_offset : Int, target_offset : Int, reg : Int) -> UInt {
  let delta = (target_offset - from_offset) / 4
  if delta < -(1 << 18) || delta >= 1 << 18 {
    abort("cbz target out of range for Mach-O object backend")
  }
  let imm = if delta < 0 { delta + (1 << 19) } else { delta }
  0xb4000000U | (imm.reinterpret_as_uint() << 5) | reg.reinterpret_as_uint()
}

///|
fn encode_cbnz(from_offset : Int, target_offset : Int, reg : Int) -> UInt {
  encode_cbz(from_offset, target_offset, reg) | 0x01000000U
}

///|
fn encode_cond_branch(
  from_offset : Int,
  target_offset : Int,
  cond : String,
) -> UInt {
  let delta = (target_offset - from_offset) / 4
  if delta < -(1 << 18) || delta >= 1 << 18 {
    abort("conditional branch target out of range for Mach-O object backend")
  }
  let imm = if delta < 0 { delta + (1 << 19) } else { delta }
  0x54000000U |
  (imm.reinterpret_as_uint() << 5) |
  condition_code(cond).reinterpret_as_uint()
}

///|
fn encode_adrp(dst : String) -> UInt {
  0x90000000U | parse_register(dst).reinterpret_as_uint()
}

///|
fn encode_branch_with_base(
  from_offset : Int,
  target_offset : Int,
  base : UInt,
) -> UInt {
  let delta = (target_offset - from_offset) / 4
  if delta < -(1 << 25) || delta >= 1 << 25 {
    abort("branch target out of range for Mach-O object backend")
  }
  let imm = if delta < 0 { delta + (1 << 26) } else { delta }
  base | imm.reinterpret_as_uint()
}

///|
fn add_relocation(
  section : ObjectSection,
  address : Int,
  symbol : String,
  pcrel : Bool,
  type_ : Int,
) -> Unit {
  add_relocation_with_length(section, address, symbol, pcrel, type_, 2)
}

///|
fn add_relocation_with_length(
  section : ObjectSection,
  address : Int,
  symbol : String,
  pcrel : Bool,
  type_ : Int,
  length : Int,
) -> Unit {
  section.relocs.push({ address, symbol, pcrel, length, external: true, type_ })
}

///|
fn strip_reloc_suffix(operand : String, suffix : String) -> String {
  let cleaned = clean_mem_token(operand)
  if !cleaned.has_suffix(suffix) {
    abort("unsupported relocation operand: " + operand)
  }
  cleaned.substring(end=cleaned.length() - suffix.length())
}

///|
fn parse_p2align(line : String) -> Int {
  let rest = line.substring(start=".p2align".length()).trim().to_string()
  let parts = split_operands(rest)
  if parts.length() == 0 {
    abort("malformed .p2align directive")
  }
  parse_int_or_abort(parts[0], ".p2align")
}

///|
fn push_global_once(globals : Array[String], name : String) -> Unit {
  for existing in globals {
    if existing == name {
      return
    }
  }
  globals.push(name)
}

///|
fn default_section_align_power(segname : String, sectname : String) -> Int {
  if segname == "__TEXT" && sectname == "__text" {
    2
  } else if segname == "__TEXT" && sectname == "__const" {
    0
  } else if segname == "__TEXT" && sectname == "__cstring" {
    0
  } else {
    3
  }
}

///|
fn section_flags(segname : String, sectname : String, line : String) -> UInt {
  if segname == "__TEXT" && sectname == "__text" {
    0x80000400U
  } else if segname == "__DATA" && sectname == "__bss" {
    0x00000001U
  } else if (segname == "__TEXT" && sectname == "__cstring") ||
    line.contains("cstring_literals") {
    0x00000002U
  } else if line.contains("8byte_literals") {
    0x00000004U
  } else {
    0U
  }
}

///|
fn get_or_add_section(
  sections : Array[ObjectSection],
  segname : String,
  sectname : String,
  flags : UInt,
  align_power : Int,
) -> Int {
  for i = 0; i < sections.length(); i = i + 1 {
    if sections[i].segname == segname && sections[i].sectname == sectname {
      return i
    }
  }
  sections.push({
    sectname,
    segname,
    flags,
    align_power,
    bytes: [],
    relocs: [],
    addr: 0,
    offset: 0,
    reloff: 0,
  })
  sections.length() - 1
}

///|
fn parse_section_index(sections : Array[ObjectSection], line : String) -> Int {
  let rest = line.substring(start=".section".length()).trim().to_string()
  let parts = split_operands(rest)
  if parts.length() < 2 {
    abort("malformed Mach-O section directive: " + line)
  }
  let segname = parts[0]
  let sectname = parts[1]
  get_or_add_section(
    sections,
    segname,
    sectname,
    section_flags(segname, sectname, line),
    default_section_align_power(segname, sectname),
  )
}

///|
fn directive_rest(line : String, directive : String) -> String {
  line.substring(start=directive.length()).trim().to_string()
}

///|
fn parse_data_integer(value : String, context : String) -> Int {
  parse_int_or_abort(value.trim().to_string(), context)
}

///|
fn parse_data_integer_i64_opt(value : String) -> Int64? {
  let mut text = value.trim().to_string()
  if text.length() == 0 {
    return None
  }
  let mut sign = 1L
  if text.has_prefix("-") {
    sign = -1L
    text = text.substring(start=1).to_string()
  }
  let mut base = 10
  if text.has_prefix("0x") || text.has_prefix("0X") {
    base = 16
    text = text.substring(start=2).to_string()
  }
  if text.length() == 0 {
    return None
  }
  let mut n = 0L
  for ch in text {
    let digit = if ch >= '0' && ch <= '9' {
      ch.to_int() - '0'.to_int()
    } else if ch >= 'a' && ch <= 'f' {
      ch.to_int() - 'a'.to_int() + 10
    } else if ch >= 'A' && ch <= 'F' {
      ch.to_int() - 'A'.to_int() + 10
    } else {
      return None
    }
    if digit >= base {
      return None
    }
    n = n * base.to_int64() + digit.to_int64()
  }
  Some(n * sign)
}

///|
fn parse_symbol_addend(value : String) -> SymbolAddend {
  let text = value.trim().to_string()
  if text == "" || text.contains(" ") {
    abort("unsupported .quad operand in Mach-O object backend: " + value)
  }
  let mut split_at = -1
  let mut i = 1
  while i < text.length() {
    if text[i] == '+' || text[i] == '-' {
      split_at = i
      break
    }
    i = i + 1
  }
  if split_at < 0 {
    { symbol: text, addend: 0 }
  } else {
    let symbol = text.substring(end=split_at)
    let amount = parse_int_or_abort(
      text.substring(start=split_at + 1),
      ".quad symbol addend",
    )
    let addend = if text[split_at] == '-' { -amount } else { amount }
    { symbol, addend }
  }
}

///|
fn append_quad_value(section : ObjectSection, value : String) -> Unit {
  match parse_data_integer_i64_opt(value) {
    Some(n) => append_u64_to_section(section, n)
    None => {
      let parsed = parse_symbol_addend(value)
      let address = section.bytes.length()
      append_u64_to_section(section, parsed.addend.to_int64())
      add_relocation_with_length(section, address, parsed.symbol, false, 0, 3)
    }
  }
}

///|
fn append_double_value(section : ObjectSection, value : String) -> Unit {
  let text = value.trim().to_string()
  let parsed = @string.parse_double(text) catch {
    _ => abort("cannot parse double in .double: " + text)
  }
  append_u64_bits_to_section(section, parsed.reinterpret_as_uint64())
}

///|
fn append_single_value(section : ObjectSection, value : String) -> Unit {
  let text = value.trim().to_string()
  let parsed = @string.parse_double(text) catch {
    _ => abort("cannot parse float in .single: " + text)
  }
  append_u32_to_section(
    section,
    Float::from_double(parsed).reinterpret_as_uint(),
  )
}

///|
fn is_octal_char(ch : UInt16) -> Bool {
  ch >= '0'.to_int().to_uint16() && ch <= '7'.to_int().to_uint16()
}

///|
fn parse_asm_string_literal(rest : String) -> Array[Int] {
  let bytes : Array[Int] = []
  let s = rest.trim().to_string()
  if s.length() < 2 || s[0] != '"' {
    abort("malformed string directive in Mach-O object backend: " + rest)
  }
  let mut i = 1
  while i < s.length() {
    let ch = s[i]
    if ch == '"' {
      return bytes
    } else if ch == '\\' {
      if i + 1 >= s.length() {
        abort("unterminated escape in string directive")
      }
      let next = s[i + 1]
      if is_octal_char(next) {
        let mut value = 0
        let mut count = 0
        i = i + 1
        while i < s.length() && count < 3 && is_octal_char(s[i]) {
          value = value * 8 + s[i].to_int() - '0'.to_int()
          i = i + 1
          count = count + 1
        }
        bytes.push(value & 0xff)
        continue
      } else {
        match next {
          'n' => bytes.push(10)
          't' => bytes.push(9)
          'r' => bytes.push(13)
          '\\' => bytes.push('\\'.to_int())
          '"' => bytes.push('"'.to_int())
          _ => bytes.push(next.to_int())
        }
        i = i + 2
        continue
      }
    } else {
      bytes.push(ch.to_int() & 0xff)
      i = i + 1
    }
  }
  abort("unterminated string directive in Mach-O object backend: " + rest)
}

///|
fn append_data_directive(section : ObjectSection, line : String) -> Bool {
  if line.has_prefix(".byte") {
    for value in split_operands(directive_rest(line, ".byte")) {
      append_byte(section, parse_data_integer(value, ".byte"))
    }
    return true
  } else if line.has_prefix(".short") {
    for value in split_operands(directive_rest(line, ".short")) {
      append_u16_to_section(section, parse_data_integer(value, ".short"))
    }
    return true
  } else if line.has_prefix(".long") {
    for value in split_operands(directive_rest(line, ".long")) {
      append_i32_to_section(section, parse_data_integer(value, ".long"))
    }
    return true
  } else if line.has_prefix(".quad") {
    for value in split_operands(directive_rest(line, ".quad")) {
      append_quad_value(section, value)
    }
    return true
  } else if line.has_prefix(".double") {
    for value in split_operands(directive_rest(line, ".double")) {
      append_double_value(section, value)
    }
    return true
  } else if line.has_prefix(".single") {
    for value in split_operands(directive_rest(line, ".single")) {
      append_single_value(section, value)
    }
    return true
  } else if line.has_prefix(".space") {
    let count = parse_data_integer(directive_rest(line, ".space"), ".space")
    let mut i = 0
    while i < count {
      append_byte(section, 0)
      i = i + 1
    }
    return true
  } else if line.has_prefix(".asciz") {
    let bytes = parse_asm_string_literal(directive_rest(line, ".asciz"))
    for byte in bytes {
      append_byte(section, byte)
    }
    append_byte(section, 0)
    return true
  } else {
    false
  }
}

///|
fn assemble_object_from_darwin_arm64(assembly : String) -> AssembledObject {
  let sections : Array[ObjectSection] = []
  let globals : Array[String] = []
  let defined_symbols : Array[String] = []
  let symbols : Map[String, SymbolLocation] = {}
  let pending : Array[PendingBranch] = []
  let pending_cbz : Array[PendingCbz] = []
  let pending_cond : Array[PendingCondBranch] = []
  let mut current_section = -1
  for raw in assembly.split("\n") {
    let line = raw.to_string().trim().to_string()
    if line == "" {
      continue
    } else if line.has_prefix(".section") {
      current_section = parse_section_index(sections, line)
    } else if line.has_prefix(".build_version") {
      continue
    } else if line.has_prefix(".globl") {
      push_global_once(
        globals,
        line.substring(start=".globl".length()).trim().to_string(),
      )
    } else if line.has_prefix(".p2align") {
      if current_section >= 0 {
        let power = parse_p2align(line)
        if power > sections[current_section].align_power {
          sections[current_section].align_power = power
        }
        align_section(
          sections[current_section],
          1 << power,
          section_is_text(sections[current_section]),
        )
      }
    } else if line.has_suffix(":") {
      if current_section < 0 {
        abort("label before section in Mach-O object backend: " + line)
      }
      let name = line.substring(end=line.length() - 1)
      symbols[name] = {
        section_index: current_section,
        offset: sections[current_section].bytes.length(),
      }
      push_string_once(defined_symbols, name)
    } else if current_section >= 0 && section_is_text(sections[current_section]) {
      if line == "stp\tx29, x30, [sp, #-16]!" {
        append_u32_to_section(sections[current_section], 0xa9bf7bfdU)
      } else if line == "ldp\tx29, x30, [sp], #16" {
        append_u32_to_section(sections[current_section], 0xa8c17bfdU)
      } else if line == "ret" {
        append_u32_to_section(sections[current_section], 0xd65f03c0U)
      } else if line.has_prefix("mov\t") {
        append_u32_to_section(
          sections[current_section],
          encode_mov(line.substring(start=4)),
        )
      } else if line.has_prefix("movz\t") {
        append_u32_to_section(
          sections[current_section],
          encode_mov_wide(line.substring(start=5), "movz"),
        )
      } else if line.has_prefix("movk\t") {
        append_u32_to_section(
          sections[current_section],
          encode_mov_wide(line.substring(start=5), "movk"),
        )
      } else if line.has_prefix("movn\t") {
        append_u32_to_section(
          sections[current_section],
          encode_mov_wide(line.substring(start=5), "movn"),
        )
      } else if line.has_prefix("mvn\t") {
        append_u32_to_section(
          sections[current_section],
          encode_mvn(line.substring(start=4)),
        )
      } else if line.has_prefix("neg\t") {
        append_u32_to_section(
          sections[current_section],
          encode_neg(line.substring(start=4)),
        )
      } else if line.has_prefix("sxtw\t") {
        let parts = split_operands(line.substring(start=5))
        if parts.length() != 2 {
          abort("malformed sxtw instruction")
        }
        append_u32_to_section(
          sections[current_section],
          encode_sxtw(parts[0], parts[1]),
        )
      } else if line.has_prefix("sxtb\t") {
        let parts = split_operands(line.substring(start=5))
        if parts.length() != 2 {
          abort("malformed sxtb instruction")
        }
        append_u32_to_section(
          sections[current_section],
          encode_sxtb(parts[0], parts[1]),
        )
      } else if line.has_prefix("sxth\t") {
        let parts = split_operands(line.substring(start=5))
        if parts.length() != 2 {
          abort("malformed sxth instruction")
        }
        append_u32_to_section(
          sections[current_section],
          encode_sxth(parts[0], parts[1]),
        )
      } else if line.has_prefix("adrp\t") {
        let parts = split_operands(line.substring(start=5))
        if parts.length() != 2 {
          abort("malformed adrp instruction")
        }
        let reloc_type = if parts[1].has_suffix("@GOTPAGE") { 5 } else { 3 }
        let suffix = if parts[1].has_suffix("@GOTPAGE") {
          "@GOTPAGE"
        } else {
          "@PAGE"
        }
        let address = sections[current_section].bytes.length()
        append_u32_to_section(sections[current_section], encode_adrp(parts[0]))
        add_relocation(
          sections[current_section],
          address,
          strip_reloc_suffix(parts[1], suffix),
          true,
          reloc_type,
        )
      } else if line.has_prefix("add\t") {
        let parts = split_operands(line.substring(start=4))
        if parts.length() == 3 && parts[2].contains("@PAGEOFF") {
          let address = sections[current_section].bytes.length()
          append_u32_to_section(
            sections[current_section],
            encode_add_sub_imm(parts[0], parts[1], 0, false),
          )
          add_relocation(
            sections[current_section],
            address,
            strip_reloc_suffix(parts[2], "@PAGEOFF"),
            false,
            4,
          )
        } else {
          append_u32_to_section(
            sections[current_section],
            encode_add_sub(line.substring(start=4), false),
          )
        }
      } else if line.has_prefix("sub\t") {
        append_u32_to_section(
          sections[current_section],
          encode_add_sub(line.substring(start=4), true),
        )
      } else if line.has_prefix("mul\t") {
        append_u32_to_section(
          sections[current_section],
          encode_mul(line.substring(start=4)),
        )
      } else if line.has_prefix("madd\t") {
        append_u32_to_section(
          sections[current_section],
          encode_madd(line.substring(start=5)),
        )
      } else if line.has_prefix("msub\t") {
        append_u32_to_section(
          sections[current_section],
          encode_msub(line.substring(start=5)),
        )
      } else if line.has_prefix("sdiv\t") {
        append_u32_to_section(
          sections[current_section],
          encode_sdiv(line.substring(start=5)),
        )
      } else if line.has_prefix("fmov\t") {
        append_u32_to_section(
          sections[current_section],
          encode_fmov(line.substring(start=5)),
        )
      } else if line.has_prefix("fadd\t") {
        append_u32_to_section(
          sections[current_section],
          encode_fp_three_register(line.substring(start=5), 0x1e602800U, "fadd"),
        )
      } else if line.has_prefix("fsub\t") {
        append_u32_to_section(
          sections[current_section],
          encode_fp_three_register(line.substring(start=5), 0x1e603800U, "fsub"),
        )
      } else if line.has_prefix("fmul\t") {
        append_u32_to_section(
          sections[current_section],
          encode_fp_three_register(line.substring(start=5), 0x1e600800U, "fmul"),
        )
      } else if line.has_prefix("fdiv\t") {
        append_u32_to_section(
          sections[current_section],
          encode_fp_three_register(line.substring(start=5), 0x1e601800U, "fdiv"),
        )
      } else if line.has_prefix("fneg\t") {
        append_u32_to_section(
          sections[current_section],
          encode_fp_two_register(
            line.substring(start=5),
            0x1e614000U,
            0x1e214000U,
            "fneg",
          ),
        )
      } else if line.has_prefix("fcvt\t") {
        append_u32_to_section(
          sections[current_section],
          encode_fp_precision_convert(line.substring(start=5)),
        )
      } else if line.has_prefix("fcmp\t") {
        append_u32_to_section(
          sections[current_section],
          encode_fcmp(line.substring(start=5)),
        )
      } else if line.has_prefix("fcvtzs\t") {
        append_u32_to_section(
          sections[current_section],
          encode_fp_convert_to_int(
            line.substring(start=7),
            0x9e780000U,
            "fcvtzs",
          ),
        )
      } else if line.has_prefix("fcvtzu\t") {
        append_u32_to_section(
          sections[current_section],
          encode_fp_convert_to_int(
            line.substring(start=7),
            0x9e790000U,
            "fcvtzu",
          ),
        )
      } else if line.has_prefix("scvtf\t") {
        append_u32_to_section(
          sections[current_section],
          encode_int_convert_to_fp(line.substring(start=6), true, "scvtf"),
        )
      } else if line.has_prefix("ucvtf\t") {
        append_u32_to_section(
          sections[current_section],
          encode_int_convert_to_fp(line.substring(start=6), false, "ucvtf"),
        )
      } else if line.has_prefix("dmb\t") {
        append_u32_to_section(
          sections[current_section],
          encode_dmb(line.substring(start=4)),
        )
      } else if line.has_prefix("ldarb\t") {
        append_u32_to_section(
          sections[current_section],
          encode_atomic_memory(line.substring(start=6), 0x08dffc00U, "ldarb"),
        )
      } else if line.has_prefix("ldarh\t") {
        append_u32_to_section(
          sections[current_section],
          encode_atomic_memory(line.substring(start=6), 0x48dffc00U, "ldarh"),
        )
      } else if line.has_prefix("ldar\t") {
        let parts = split_operands(line.substring(start=5))
        let base = if parts.length() > 0 && parts[0].has_prefix("x") {
          0xc8dffc00U
        } else {
          0x88dffc00U
        }
        append_u32_to_section(
          sections[current_section],
          encode_atomic_memory(line.substring(start=5), base, "ldar"),
        )
      } else if line.has_prefix("stlrb\t") {
        append_u32_to_section(
          sections[current_section],
          encode_atomic_memory(line.substring(start=6), 0x089ffc00U, "stlrb"),
        )
      } else if line.has_prefix("stlrh\t") {
        append_u32_to_section(
          sections[current_section],
          encode_atomic_memory(line.substring(start=6), 0x489ffc00U, "stlrh"),
        )
      } else if line.has_prefix("stlr\t") {
        let parts = split_operands(line.substring(start=5))
        let base = if parts.length() > 0 && parts[0].has_prefix("x") {
          0xc89ffc00U
        } else {
          0x889ffc00U
        }
        append_u32_to_section(
          sections[current_section],
          encode_atomic_memory(line.substring(start=5), base, "stlr"),
        )
      } else if line.has_prefix("udiv\t") {
        append_u32_to_section(
          sections[current_section],
          encode_three_register(line.substring(start=5), 0x9ac00800U, "udiv"),
        )
      } else if line.has_prefix("and\t") {
        append_u32_to_section(
          sections[current_section],
          encode_and(line.substring(start=4)),
        )
      } else if line.has_prefix("orr\t") {
        append_u32_to_section(
          sections[current_section],
          encode_three_register(line.substring(start=4), 0xaa000000U, "orr"),
        )
      } else if line.has_prefix("eor\t") {
        append_u32_to_section(
          sections[current_section],
          encode_three_register(line.substring(start=4), 0xca000000U, "eor"),
        )
      } else if line.has_prefix("lsl\t") {
        append_u32_to_section(
          sections[current_section],
          encode_shift(line.substring(start=4), "lsl"),
        )
      } else if line.has_prefix("asr\t") {
        append_u32_to_section(
          sections[current_section],
          encode_shift(line.substring(start=4), "asr"),
        )
      } else if line.has_prefix("lsr\t") {
        append_u32_to_section(
          sections[current_section],
          encode_shift(line.substring(start=4), "lsr"),
        )
      } else if line.has_prefix("cmp\t") {
        append_u32_to_section(
          sections[current_section],
          encode_cmp(line.substring(start=4)),
        )
      } else if line.has_prefix("cset\t") {
        append_u32_to_section(
          sections[current_section],
          encode_cset(line.substring(start=5)),
        )
      } else if line.has_prefix("str\t") {
        append_u32_to_section(
          sections[current_section],
          encode_str(line.substring(start=4)),
        )
      } else if line.has_prefix("strb\t") {
        append_u32_to_section(
          sections[current_section],
          encode_byte_halfword_memory(
            line.substring(start=5),
            0x39000000U,
            1,
            "strb",
          ),
        )
      } else if line.has_prefix("strh\t") {
        append_u32_to_section(
          sections[current_section],
          encode_byte_halfword_memory(
            line.substring(start=5),
            0x79000000U,
            2,
            "strh",
          ),
        )
      } else if line.has_prefix("ldrb\t") {
        append_u32_to_section(
          sections[current_section],
          encode_byte_halfword_memory(
            line.substring(start=5),
            0x39400000U,
            1,
            "ldrb",
          ),
        )
      } else if line.has_prefix("ldrh\t") {
        append_u32_to_section(
          sections[current_section],
          encode_byte_halfword_memory(
            line.substring(start=5),
            0x79400000U,
            2,
            "ldrh",
          ),
        )
      } else if line.has_prefix("ldr\t") {
        let parts = split_operands(line.substring(start=4))
        if parts.length() == 3 &&
          (parts[2].contains("@GOTPAGEOFF") || parts[2].contains("@PAGEOFF")) {
          let reloc_type = if parts[2].contains("@GOTPAGEOFF") { 6 } else { 4 }
          let suffix = if parts[2].contains("@GOTPAGEOFF") {
            "@GOTPAGEOFF"
          } else {
            "@PAGEOFF"
          }
          let address = sections[current_section].bytes.length()
          append_u32_to_section(
            sections[current_section],
            encode_ldr_unsigned_offset(parts[0], parts[1], "#0"),
          )
          add_relocation(
            sections[current_section],
            address,
            strip_reloc_suffix(parts[2], suffix),
            false,
            reloc_type,
          )
        } else {
          append_u32_to_section(
            sections[current_section],
            encode_ldr(line.substring(start=4)),
          )
        }
      } else if line.has_prefix("cbz\t") {
        let parts = split_operands(line.substring(start=4))
        if parts.length() != 2 {
          abort("malformed cbz instruction")
        }
        pending_cbz.push({
          section_index: current_section,
          offset: sections[current_section].bytes.length(),
          label: parts[1],
          reg: parse_register(parts[0]),
          nonzero: false,
        })
        append_u32_to_section(sections[current_section], 0U)
      } else if line.has_prefix("cbnz\t") {
        let parts = split_operands(line.substring(start=5))
        if parts.length() != 2 {
          abort("malformed cbnz instruction")
        }
        pending_cbz.push({
          section_index: current_section,
          offset: sections[current_section].bytes.length(),
          label: parts[1],
          reg: parse_register(parts[0]),
          nonzero: true,
        })
        append_u32_to_section(sections[current_section], 0U)
      } else if line.has_prefix("b.") {
        let parts : Array[String] = []
        for part in line.substring(start=2).trim().to_string().split("\t") {
          parts.push(part.to_string().trim().to_string())
        }
        if parts.length() != 2 {
          abort("malformed conditional branch instruction: " + line)
        }
        pending_cond.push({
          section_index: current_section,
          offset: sections[current_section].bytes.length(),
          label: parts[1],
          cond: parts[0],
        })
        append_u32_to_section(sections[current_section], 0U)
      } else if line.has_prefix("b\t") {
        pending.push({
          section_index: current_section,
          offset: sections[current_section].bytes.length(),
          label: line.substring(start=2).trim().to_string(),
          link: false,
        })
        append_u32_to_section(sections[current_section], 0U)
      } else if line.has_prefix("bl\t") {
        pending.push({
          section_index: current_section,
          offset: sections[current_section].bytes.length(),
          label: line.substring(start=3).trim().to_string(),
          link: true,
        })
        append_u32_to_section(sections[current_section], 0U)
      } else if line.has_prefix("blr\t") {
        append_u32_to_section(
          sections[current_section],
          encode_blr(line.substring(start=4)),
        )
      } else {
        abort("unsupported instruction in Mach-O object backend: " + line)
      }
    } else if current_section >= 0 &&
      append_data_directive(sections[current_section], line) {
      continue
    } else if line == ".subsections_via_symbols" {
      continue
    }
  }
  for branch in pending {
    match symbols.get(branch.label) {
      Some(target) =>
        if target.section_index != branch.section_index {
          abort("cross-section branch needs relocation: " + branch.label)
        } else {
          patch_u32_in_section(
            sections[branch.section_index],
            branch.offset,
            if branch.link {
              encode_branch_link(branch.offset, target.offset)
            } else {
              encode_branch(branch.offset, target.offset)
            },
          )
        }
      None =>
        if branch.link {
          patch_u32_in_section(
            sections[branch.section_index],
            branch.offset,
            0x94000000U,
          )
          add_relocation(
            sections[branch.section_index],
            branch.offset,
            branch.label,
            true,
            2,
          )
        } else {
          abort(
            "unknown branch label in Mach-O object backend: " + branch.label,
          )
        }
    }
  }
  for branch in pending_cbz {
    match symbols.get(branch.label) {
      Some(target) =>
        if target.section_index != branch.section_index {
          abort("cross-section cbz needs relocation: " + branch.label)
        } else {
          patch_u32_in_section(
            sections[branch.section_index],
            branch.offset,
            if branch.nonzero {
              encode_cbnz(branch.offset, target.offset, branch.reg)
            } else {
              encode_cbz(branch.offset, target.offset, branch.reg)
            },
          )
        }
      None =>
        abort(
          "unknown compare-zero branch label in Mach-O object backend: " +
          branch.label,
        )
    }
  }
  for branch in pending_cond {
    match symbols.get(branch.label) {
      Some(target) =>
        if target.section_index != branch.section_index {
          abort(
            "cross-section conditional branch needs relocation: " + branch.label,
          )
        } else {
          patch_u32_in_section(
            sections[branch.section_index],
            branch.offset,
            encode_cond_branch(branch.offset, target.offset, branch.cond),
          )
        }
      None =>
        abort(
          "unknown conditional branch label in Mach-O object backend: " +
          branch.label,
        )
    }
  }
  { sections, globals, defined_symbols, symbols }
}

///|
fn write_macho_header(buf : @buffer.Buffer, sizeofcmds : Int) -> Unit {
  write_u32_le(buf, 0xfeedfacfU) // MH_MAGIC_64
  write_u32_le(buf, 0x0100000cU) // CPU_TYPE_ARM64
  write_i32_le(buf, 0) // CPU_SUBTYPE_ARM64_ALL
  write_u32_le(buf, 1U) // MH_OBJECT
  write_u32_le(buf, 4U)
  write_i32_le(buf, sizeofcmds)
  write_u32_le(buf, 0U) // flags
  write_u32_le(buf, 0U) // reserved
}

///|
fn write_segment_command(
  buf : @buffer.Buffer,
  sections : Array[ObjectSection],
  segment_fileoff : Int,
  segment_filesize : Int,
  segment_vmsize : Int,
) -> Unit {
  write_u32_le(buf, 0x19U) // LC_SEGMENT_64
  write_i32_le(buf, 72 + sections.length() * 80)
  write_fixed_ascii(buf, "", 16)
  write_u64_le(buf, 0L)
  write_u64_le(buf, segment_vmsize.to_int64())
  write_u64_le(buf, segment_fileoff.to_int64())
  write_u64_le(buf, segment_filesize.to_int64())
  write_i32_le(buf, 7)
  write_i32_le(buf, 7)
  write_i32_le(buf, sections.length())
  write_i32_le(buf, 0)
  for section in sections {
    write_section_header(buf, section)
  }
}

///|
fn write_section_header(buf : @buffer.Buffer, section : ObjectSection) -> Unit {
  write_fixed_ascii(buf, section.sectname, 16)
  write_fixed_ascii(buf, section.segname, 16)
  write_u64_le(buf, section.addr.to_int64())
  write_u64_le(buf, section.bytes.length().to_int64())
  write_i32_le(buf, section.offset)
  write_i32_le(buf, section.align_power)
  write_i32_le(buf, section.reloff)
  write_i32_le(buf, section.relocs.length())
  write_u32_le(buf, section.flags)
  write_i32_le(buf, 0)
  write_i32_le(buf, 0)
  write_i32_le(buf, 0)
}

///|
fn write_build_version_command(buf : @buffer.Buffer) -> Unit {
  write_u32_le(buf, 0x32U) // LC_BUILD_VERSION
  write_i32_le(buf, 24)
  write_i32_le(buf, 1) // PLATFORM_MACOS
  write_i32_le(buf, 14 << 16)
  write_i32_le(buf, 14 << 16)
  write_i32_le(buf, 0)
}

///|
fn write_symtab_command(
  buf : @buffer.Buffer,
  symoff : Int,
  nsyms : Int,
  stroff : Int,
  strsize : Int,
) -> Unit {
  write_u32_le(buf, 0x2U) // LC_SYMTAB
  write_i32_le(buf, 24)
  write_i32_le(buf, symoff)
  write_i32_le(buf, nsyms)
  write_i32_le(buf, stroff)
  write_i32_le(buf, strsize)
}

///|
fn write_dysymtab_command(
  buf : @buffer.Buffer,
  nlocals : Int,
  nextdefs : Int,
  nundefs : Int,
) -> Unit {
  write_u32_le(buf, 0xbU) // LC_DYSYMTAB
  write_i32_le(buf, 80)
  write_i32_le(buf, 0)
  write_i32_le(buf, nlocals)
  write_i32_le(buf, nlocals)
  write_i32_le(buf, nextdefs)
  write_i32_le(buf, nlocals + nextdefs)
  write_i32_le(buf, nundefs)
  let mut i = 0
  while i < 12 {
    write_i32_le(buf, 0)
    i = i + 1
  }
}

///|
fn append_sections(
  buf : @buffer.Buffer,
  sections : Array[ObjectSection],
) -> Unit {
  for section in sections {
    if !section_is_zerofill(section) {
      write_padding_to_offset(buf, section.offset)
      for byte in section.bytes {
        buf.write_byte(byte.to_byte())
      }
    }
  }
}

///|
fn write_relocation(
  buf : @buffer.Buffer,
  reloc : Relocation,
  symbol_indexes : Map[String, Int],
) -> Unit {
  if !symbol_indexes.contains(reloc.symbol) {
    abort("missing relocation symbol in Mach-O object backend: " + reloc.symbol)
  }
  write_i32_le(buf, reloc.address)
  let pcrel = if reloc.pcrel { 1 << 24 } else { 0 }
  let external = if reloc.external { 1 << 27 } else { 0 }
  let info = symbol_indexes[reloc.symbol] |
    pcrel |
    (reloc.length << 25) |
    external |
    (reloc.type_ << 28)
  write_i32_le(buf, info)
}

///|
fn write_relocations(
  buf : @buffer.Buffer,
  sections : Array[ObjectSection],
  symbol_indexes : Map[String, Int],
) -> Unit {
  for section in sections {
    if section.relocs.length() > 0 {
      write_padding_to_offset(buf, section.reloff)
      for i = section.relocs.length() - 1; i >= 0; i = i - 1 {
        write_relocation(buf, section.relocs[i], symbol_indexes)
      }
    }
  }
}

///|
fn symbol_string_size(symbols : Array[SymbolEntry]) -> Int {
  let mut size = 1
  for symbol in symbols {
    size = size + symbol.name.length() + 1
  }
  size
}

///|
fn write_symbol_table(buf : @buffer.Buffer, layout : SymbolLayout) -> Unit {
  let mut strx = 1
  for symbol in layout.entries {
    write_i32_le(buf, strx)
    buf.write_byte(symbol.type_.to_byte())
    buf.write_byte(symbol.section_index.to_byte())
    write_u16_le(buf, 0)
    write_u64_le(buf, symbol.value.to_int64())
    strx = strx + symbol.name.length() + 1
  }
}

///|
fn write_string_table(
  buf : @buffer.Buffer,
  entries : Array[SymbolEntry],
) -> Unit {
  buf.write_byte((0).to_byte())
  for symbol in entries {
    write_ascii_z(buf, symbol.name)
  }
}

///|
fn array_contains_string(values : Array[String], target : String) -> Bool {
  for value in values {
    if value == target {
      return true
    }
  }
  false
}

///|
fn push_string_once(values : Array[String], target : String) -> Unit {
  if !array_contains_string(values, target) {
    values.push(target)
  }
}

///|
fn is_temporary_label(name : String) -> Bool {
  name.has_prefix("L")
}

///|
fn symbol_value(
  name : String,
  symbols : Map[String, SymbolLocation],
  sections : Array[ObjectSection],
) -> Int {
  match symbols.get(name) {
    Some(loc) => sections[loc.section_index].addr + loc.offset
    None => 0
  }
}

///|
fn build_symbol_layout(obj : AssembledObject) -> SymbolLayout {
  let referenced : Array[String] = []
  for section in obj.sections {
    for reloc in section.relocs {
      push_string_once(referenced, reloc.symbol)
    }
  }
  let locals : Array[String] = []
  let extdefs : Array[String] = []
  let undefs : Array[String] = []
  for name in referenced {
    if obj.symbols.contains(name) {
      if !array_contains_string(obj.globals, name) {
        push_string_once(locals, name)
      }
    } else {
      push_string_once(undefs, name)
    }
  }
  for name in obj.defined_symbols {
    if !array_contains_string(obj.globals, name) && !is_temporary_label(name) {
      push_string_once(locals, name)
    }
  }
  for name in obj.globals {
    if obj.symbols.contains(name) {
      push_string_once(extdefs, name)
    } else {
      push_string_once(undefs, name)
    }
  }
  let entries : Array[SymbolEntry] = []
  let indexes : Map[String, Int] = {}
  for name in locals {
    indexes[name] = entries.length()
    let loc = obj.symbols[name]
    entries.push({
      name,
      type_: 0x0e,
      section_index: loc.section_index + 1,
      value: symbol_value(name, obj.symbols, obj.sections),
    })
  }
  for name in extdefs {
    indexes[name] = entries.length()
    let loc = obj.symbols[name]
    entries.push({
      name,
      type_: 0x0f,
      section_index: loc.section_index + 1,
      value: symbol_value(name, obj.symbols, obj.sections),
    })
  }
  for name in undefs {
    indexes[name] = entries.length()
    entries.push({ name, type_: 0x01, section_index: 0, value: 0 })
  }
  {
    entries,
    indexes,
    nlocals: locals.length(),
    nextdefs: extdefs.length(),
    nundefs: undefs.length(),
  }
}

///|
fn layout_sections(
  sections : Array[ObjectSection],
  content_offset : Int,
) -> (Int, Int, Int) {
  let mut file_cursor = content_offset
  let mut addr_cursor = 0
  let mut first_fileoff = content_offset
  let mut saw_file_section = false
  for i = 0; i < sections.length(); i = i + 1 {
    if section_is_zerofill(sections[i]) {
      continue
    }
    let align = 1 << sections[i].align_power
    file_cursor = align_int(file_cursor, align)
    addr_cursor = align_int(addr_cursor, align)
    if !saw_file_section {
      first_fileoff = file_cursor
      saw_file_section = true
    }
    sections[i].offset = file_cursor
    sections[i].addr = addr_cursor
    file_cursor = file_cursor + sections[i].bytes.length()
    addr_cursor = addr_cursor + sections[i].bytes.length()
  }
  for i = 0; i < sections.length(); i = i + 1 {
    if section_is_zerofill(sections[i]) {
      let align = 1 << sections[i].align_power
      addr_cursor = align_int(addr_cursor, align)
      sections[i].offset = 0
      sections[i].addr = addr_cursor
      addr_cursor = addr_cursor + sections[i].bytes.length()
    }
  }
  let segment_filesize = if saw_file_section {
    file_cursor - first_fileoff
  } else {
    0
  }
  (first_fileoff, segment_filesize, addr_cursor)
}

///|
fn layout_relocations(sections : Array[ObjectSection], offset : Int) -> Int {
  let mut cursor = align_int(offset, 4)
  for section in sections {
    if section.relocs.length() > 0 {
      section.reloff = cursor
      cursor = cursor + section.relocs.length() * 8
    }
  }
  cursor
}

///|
fn macho_object_from_assembled(obj : AssembledObject) -> Bytes {
  let header_size = 32
  let seg_cmd_size = 72 + obj.sections.length() * 80
  let build_cmd_size = 24
  let sym_cmd_size = 24
  let dysym_cmd_size = 80
  let sizeofcmds = seg_cmd_size + build_cmd_size + sym_cmd_size + dysym_cmd_size
  let content_offset = header_size + sizeofcmds
  let (segment_fileoff, segment_filesize, segment_vmsize) = layout_sections(
    obj.sections,
    content_offset,
  )
  let reloc_end = layout_relocations(
    obj.sections,
    segment_fileoff + segment_filesize,
  )
  let symbol_layout = build_symbol_layout(obj)
  let symoff = align_int(reloc_end, 8)
  let nsyms = symbol_layout.entries.length()
  let stroff = symoff + nsyms * 16
  let strsize = symbol_string_size(symbol_layout.entries)
  let buf = @buffer.new(size_hint=stroff + strsize)
  write_macho_header(buf, sizeofcmds)
  write_segment_command(
    buf,
    obj.sections,
    segment_fileoff,
    segment_filesize,
    segment_vmsize,
  )
  write_build_version_command(buf)
  write_symtab_command(buf, symoff, nsyms, stroff, strsize)
  write_dysymtab_command(
    buf,
    symbol_layout.nlocals,
    symbol_layout.nextdefs,
    symbol_layout.nundefs,
  )
  append_sections(buf, obj.sections)
  write_relocations(buf, obj.sections, symbol_layout.indexes)
  write_padding_to_offset(buf, symoff)
  write_symbol_table(buf, symbol_layout)
  write_string_table(buf, symbol_layout.entries)
  buf.to_bytes()
}

///|
pub fn generate_macho_object(prog : @parser.Program) -> Bytes {
  let assembly = Codegen::new().generate(prog)
  macho_object_from_assembled(assemble_object_from_darwin_arm64(assembly))
}
