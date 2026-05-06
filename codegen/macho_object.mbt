///|
priv struct PendingBranch {
  offset : Int
  label : String
  link : Bool
}

///|
priv struct AssembledText {
  words : Array[UInt]
  globals : Array[String]
  symbols : Map[String, Int]
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
fn align_buffer(buf : @buffer.Buffer, align : Int) -> Unit {
  let mask = align - 1
  while (buf.length() & mask) != 0 {
    buf.write_byte((0).to_byte())
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
  if parts.length() != 3 {
    abort("malformed str instruction")
  }
  if parts[2].has_suffix("]!") {
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
fn parse_p2align(line : String) -> Int {
  let rest = line.substring(start=".p2align".length()).trim().to_string()
  parse_int_or_abort(rest, ".p2align")
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
fn assemble_text_from_darwin_arm64(assembly : String) -> AssembledText {
  let words : Array[UInt] = []
  let globals : Array[String] = []
  let symbols : Map[String, Int] = {}
  let pending : Array[PendingBranch] = []
  let mut in_text = false
  for raw in assembly.split("\n") {
    let line = raw.to_string().trim().to_string()
    if line == "" {
      continue
    } else if line.has_prefix(".section") {
      in_text = line.contains("__TEXT,__text")
    } else if line.has_prefix(".build_version") {
      continue
    } else if line.has_prefix(".globl") {
      push_global_once(
        globals,
        line.substring(start=".globl".length()).trim().to_string(),
      )
    } else if line.has_prefix(".p2align") {
      if in_text {
        let align = 1 << parse_p2align(line)
        while words.length() * 4 % align != 0 {
          words.push(0xd503201fU)
        }
      }
    } else if line.has_suffix(":") {
      symbols[line.substring(end=line.length() - 1)] = words.length() * 4
    } else if in_text {
      if line == "stp\tx29, x30, [sp, #-16]!" {
        words.push(0xa9bf7bfdU)
      } else if line == "ldp\tx29, x30, [sp], #16" {
        words.push(0xa8c17bfdU)
      } else if line == "ret" {
        words.push(0xd65f03c0U)
      } else if line.has_prefix("mov\t") {
        words.push(encode_mov(line.substring(start=4)))
      } else if line.has_prefix("movz\t") {
        words.push(encode_mov_wide(line.substring(start=5), "movz"))
      } else if line.has_prefix("movk\t") {
        words.push(encode_mov_wide(line.substring(start=5), "movk"))
      } else if line.has_prefix("movn\t") {
        words.push(encode_mov_wide(line.substring(start=5), "movn"))
      } else if line.has_prefix("sxtw\t") {
        let parts = split_operands(line.substring(start=5))
        if parts.length() != 2 {
          abort("malformed sxtw instruction")
        }
        words.push(encode_sxtw(parts[0], parts[1]))
      } else if line.has_prefix("add\t") {
        words.push(encode_add_sub(line.substring(start=4), false))
      } else if line.has_prefix("sub\t") {
        words.push(encode_add_sub(line.substring(start=4), true))
      } else if line.has_prefix("mul\t") {
        words.push(encode_mul(line.substring(start=4)))
      } else if line.has_prefix("str\t") {
        words.push(encode_str(line.substring(start=4)))
      } else if line.has_prefix("ldr\t") {
        words.push(encode_ldr(line.substring(start=4)))
      } else if line.has_prefix("b\t") {
        pending.push({
          offset: words.length() * 4,
          label: line.substring(start=2).trim().to_string(),
          link: false,
        })
        words.push(0U)
      } else if line.has_prefix("bl\t") {
        pending.push({
          offset: words.length() * 4,
          label: line.substring(start=3).trim().to_string(),
          link: true,
        })
        words.push(0U)
      } else {
        abort("unsupported instruction in Mach-O object backend: " + line)
      }
    }
  }
  for branch in pending {
    match symbols.get(branch.label) {
      Some(target) =>
        words[branch.offset / 4] = if branch.link {
          encode_branch_link(branch.offset, target)
        } else {
          encode_branch(branch.offset, target)
        }
      None =>
        abort("unknown branch label in Mach-O object backend: " + branch.label)
    }
  }
  { words, globals, symbols }
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
  text_offset : Int,
  text_size : Int,
) -> Unit {
  write_u32_le(buf, 0x19U) // LC_SEGMENT_64
  write_i32_le(buf, 72 + 80)
  write_fixed_ascii(buf, "", 16)
  write_u64_le(buf, 0L)
  write_u64_le(buf, text_size.to_int64())
  write_u64_le(buf, text_offset.to_int64())
  write_u64_le(buf, text_size.to_int64())
  write_i32_le(buf, 7)
  write_i32_le(buf, 7)
  write_i32_le(buf, 1)
  write_i32_le(buf, 0)
  write_fixed_ascii(buf, "__text", 16)
  write_fixed_ascii(buf, "__TEXT", 16)
  write_u64_le(buf, 0L)
  write_u64_le(buf, text_size.to_int64())
  write_i32_le(buf, text_offset)
  write_i32_le(buf, 2)
  write_i32_le(buf, 0)
  write_i32_le(buf, 0)
  write_u32_le(buf, 0x80000400U)
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
fn write_dysymtab_command(buf : @buffer.Buffer, nsyms : Int) -> Unit {
  write_u32_le(buf, 0xbU) // LC_DYSYMTAB
  write_i32_le(buf, 80)
  write_i32_le(buf, 0)
  write_i32_le(buf, 0)
  write_i32_le(buf, 0)
  write_i32_le(buf, nsyms)
  write_i32_le(buf, nsyms)
  write_i32_le(buf, 0)
  let mut i = 0
  while i < 12 {
    write_i32_le(buf, 0)
    i = i + 1
  }
}

///|
fn append_text(buf : @buffer.Buffer, words : Array[UInt]) -> Unit {
  for word in words {
    write_u32_le(buf, word)
  }
}

///|
fn symbol_string_size(symbols : Array[String]) -> Int {
  let mut size = 1
  for symbol in symbols {
    size = size + symbol.length() + 1
  }
  size
}

///|
fn write_symbol_table(
  buf : @buffer.Buffer,
  globals : Array[String],
  symbols : Map[String, Int],
) -> Unit {
  let mut strx = 1
  for symbol in globals {
    match symbols.get(symbol) {
      Some(value) => {
        write_i32_le(buf, strx)
        buf.write_byte((0x0f).to_byte()) // N_SECT | N_EXT
        buf.write_byte((1).to_byte())
        write_u16_le(buf, 0)
        write_u64_le(buf, value.to_int64())
        strx = strx + symbol.length() + 1
      }
      None => abort("global symbol has no text label: " + symbol)
    }
  }
}

///|
fn write_string_table(buf : @buffer.Buffer, globals : Array[String]) -> Unit {
  buf.write_byte((0).to_byte())
  for symbol in globals {
    write_ascii_z(buf, symbol)
  }
}

///|
fn macho_object_from_text(text : AssembledText) -> Bytes {
  let header_size = 32
  let seg_cmd_size = 72 + 80
  let build_cmd_size = 24
  let sym_cmd_size = 24
  let dysym_cmd_size = 80
  let sizeofcmds = seg_cmd_size + build_cmd_size + sym_cmd_size + dysym_cmd_size
  let text_offset = header_size + sizeofcmds
  let text_size = text.words.length() * 4
  let symoff = (text_offset + text_size + 7) & -8
  let nsyms = text.globals.length()
  let stroff = symoff + nsyms * 16
  let strsize = symbol_string_size(text.globals)
  let buf = @buffer.new(size_hint=stroff + strsize)
  write_macho_header(buf, sizeofcmds)
  write_segment_command(buf, text_offset, text_size)
  write_build_version_command(buf)
  write_symtab_command(buf, symoff, nsyms, stroff, strsize)
  write_dysymtab_command(buf, nsyms)
  append_text(buf, text.words)
  align_buffer(buf, 8)
  write_symbol_table(buf, text.globals, text.symbols)
  write_string_table(buf, text.globals)
  buf.to_bytes()
}

///|
pub fn generate_macho_object(prog : @parser.Program) -> Bytes {
  let assembly = Codegen::new().generate(prog)
  macho_object_from_text(assemble_text_from_darwin_arm64(assembly))
}
