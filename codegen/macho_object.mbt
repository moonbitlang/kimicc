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
fn parse_immediate(imm : String) -> Int {
  let s = imm.trim().to_string()
  if s.has_prefix("#") {
    parse_int_or_abort(s.substring(start=1), "immediate")
  } else {
    parse_int_or_abort(s, "immediate")
  }
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
fn encode_cmp(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 2 {
    abort("malformed cmp instruction")
  }
  let rn = parse_register(parts[0])
  let rm = parse_register(parts[1])
  0x6b00001fU |
  (rm.reinterpret_as_uint() << 16) |
  (rn.reinterpret_as_uint() << 5)
}

///|
fn inverted_condition_code(cond : String) -> Int {
  match cond {
    "eq" => 1
    "ne" => 0
    "lt" => 10
    "ge" => 11
    "gt" => 13
    "le" => 12
    "hi" => 9
    "ls" => 8
    _ => abort("unsupported cset condition: " + cond)
  }
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
fn encode_str(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() == 2 {
    let rt = parse_register(parts[0])
    let rn = parse_register(clean_mem_token(parts[1]))
    let base = if parts[0].has_prefix("w") { 0xb9000000U } else { 0xf9000000U }
    base | (rn.reinterpret_as_uint() << 5) | rt.reinterpret_as_uint()
  } else if parts.length() != 3 {
    abort("malformed str instruction")
  } else if parts[2].has_suffix("]!") {
    encode_str_pre_64(parts[0], parts[1], parts[2])
  } else {
    encode_stur_64(parts[0], parts[1], parts[2])
  }
}

///|
fn encode_ldr(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() == 2 {
    encode_ldr_unsigned(parts[0], parts[1])
  } else if parts.length() == 3 {
    if parts[1].has_suffix("]") {
      encode_ldr_post_64(parts[0], parts[1], parts[2])
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
  0xd2800000U |
  (hw.reinterpret_as_uint() << 21) |
  (imm.reinterpret_as_uint() << 5) |
  rd.reinterpret_as_uint()
}

///|
fn encode_movk(dst : String, imm : Int, shift : Int) -> UInt {
  let rd = parse_register(dst)
  let hw = shift / 16
  0xf2800000U |
  (hw.reinterpret_as_uint() << 21) |
  (imm.reinterpret_as_uint() << 5) |
  rd.reinterpret_as_uint()
}

///|
fn encode_movn(dst : String, imm : Int, shift : Int) -> UInt {
  let rd = parse_register(dst)
  let hw = shift / 16
  0x92800000U |
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
fn encode_mov(rest : String) -> UInt {
  let parts = split_operands(rest)
  if parts.length() != 2 {
    abort("malformed mov instruction")
  }
  if parts[1].has_prefix("#") {
    encode_movz(parts[0], parse_immediate(parts[1]), 0)
  } else {
    encode_mov_reg(parts[0], parts[1])
  }
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
  } else if (segname == "__TEXT" && sectname == "__cstring") ||
    line.contains("cstring_literals") {
    0x00000002U
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
fn parse_data_integer_opt(value : String) -> Int? {
  let text = value.trim().to_string()
  let n = @string.parse_int(text) catch { _ => return None }
  Some(n)
}

///|
fn append_quad_value(section : ObjectSection, value : String) -> Unit {
  match parse_data_integer_opt(value) {
    Some(n) => append_u64_to_section(section, n.to_int64())
    None => {
      let symbol = value.trim().to_string()
      if symbol == "" || symbol.contains(" ") {
        abort("unsupported .quad operand in Mach-O object backend: " + value)
      }
      let address = section.bytes.length()
      append_u64_to_section(section, 0L)
      add_relocation_with_length(section, address, symbol, false, 0, 3)
    }
  }
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
  let symbols : Map[String, SymbolLocation] = {}
  let pending : Array[PendingBranch] = []
  let pending_cbz : Array[PendingCbz] = []
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
      symbols[line.substring(end=line.length() - 1)] = {
        section_index: current_section,
        offset: sections[current_section].bytes.length(),
      }
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
            encode_cbz(branch.offset, target.offset, branch.reg),
          )
        }
      None =>
        abort("unknown cbz label in Mach-O object backend: " + branch.label)
    }
  }
  { sections, globals, symbols }
}

///|
fn write_macho_header(buf : @buffer.Buffer, sizeofcmds : Int) -> Unit {
  write_u32_le(buf, 0xfeedfacfU) // MH_MAGIC_64
  write_u32_le(buf, 0x0100000cU) // CPU_TYPE_ARM64
  write_i32_le(buf, 0) // CPU_SUBTYPE_ARM64_ALL
  write_u32_le(buf, 1U) // MH_OBJECT
  write_u32_le(buf, 4U)
  write_i32_le(buf, sizeofcmds)
  write_u32_le(buf, 0x2000U) // MH_SUBSECTIONS_VIA_SYMBOLS
  write_u32_le(buf, 0U)
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
    write_padding_to_offset(buf, section.offset)
    for byte in section.bytes {
      buf.write_byte(byte.to_byte())
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
  for i = 0; i < sections.length(); i = i + 1 {
    let align = 1 << sections[i].align_power
    file_cursor = align_int(file_cursor, align)
    addr_cursor = align_int(addr_cursor, align)
    if i == 0 {
      first_fileoff = file_cursor
    }
    sections[i].offset = file_cursor
    sections[i].addr = addr_cursor
    file_cursor = file_cursor + sections[i].bytes.length()
    addr_cursor = addr_cursor + sections[i].bytes.length()
  }
  (first_fileoff, file_cursor - first_fileoff, addr_cursor)
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
