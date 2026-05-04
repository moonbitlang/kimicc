///|
pub struct Codegen {
  output : StringBuilder
  mut label_counter : Int
  mut local_offsets : Map[String, Int]
  mut var_types : Map[String, @parser.Type]
  mut stack_size : Int
  mut func_name : String
  func_rets : Map[String, @parser.Type]
  struct_layouts : Map[String, Array[(String, @parser.Type, Int, Int, Int, Int)]]
  struct_decls : Map[String, @parser.StructDecl]
  strings : Array[String]
  mut break_label : String?
  mut continue_label : String?
  globals : Map[String, @parser.GlobalDecl]
  mut emitted_labels : Map[String, String]
}

///|
fn escape_string(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    match ch {
      '\n' => buf.write_string("\\n")
      '\t' => buf.write_string("\\t")
      '\\' => buf.write_string("\\\\")
      '"' => buf.write_string("\\\"")
      '\u0000' => buf.write_string("\\0")
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
pub fn Codegen::new() -> Codegen {
  {
    output: StringBuilder::new(),
    label_counter: 0,
    local_offsets: {},
    var_types: {},
    stack_size: 0,
    func_name: "",
    func_rets: {},
    struct_layouts: {},
    struct_decls: {},
    strings: [],
    break_label: None,
    continue_label: None,
    globals: {},
    emitted_labels: {},
  }
}

///|
fn Codegen::emit_global_scalar(
  self : Codegen,
  ty : @parser.Type,
  expr : @parser.Expr
) -> Unit {
  match expr {
    Number(n) => {
      match ty {
        Bool | SChar | UChar => self.emit("\t.byte\t" + n.to_string())
        SShort | UShort => self.emit("\t.short\t" + n.to_string())
        SInt | UInt | Float => self.emit("\t.long\t" + n.to_string())
        _ => self.emit("\t.quad\t" + n.to_string())
      }
    }
    String(s) => {
      let idx = self.strings.length()
      self.strings.push(s)
      self.emit("\t.quad\t_str" + idx.to_string())
    }
    _ => {
      // Non-constant expression: emit zero placeholder
      let size = self.type_size(ty)
      self.emit("\t.space\t" + size.to_string())
    }
  }
}

///|
fn Codegen::emit_global_array(
  self : Codegen,
  ty : @parser.Type,
  exprs : Array[@parser.Expr]
) -> Unit {
  match ty {
    Array(elem_ty, n) => {
      for i = 0; i < exprs.length(); i = i + 1 {
        self.emit_global_scalar(elem_ty, exprs[i])
      }
      // Pad remaining elements with zeros
      let elem_size = self.type_size(elem_ty)
      let pad_count = n - exprs.length()
      if pad_count > 0 {
        self.emit("\t.space\t" + (pad_count * elem_size).to_string())
      }
    }
    _ => {
      // Should not happen: array init for non-array type
      let size = self.type_size(ty)
      self.emit("\t.space\t" + size.to_string())
    }
  }
}

///|
pub fn Codegen::generate(self : Codegen, prog : @parser.Program) -> String {
  self.output.write_string(
    "\t.section\t__TEXT,__text,regular,pure_instructions\n",
  )
  self.output.write_string("\t.build_version macos, 14, 0\n")
  // Precompute struct layouts
  for sdecl in prog.structs {
    self.compute_struct_layout(sdecl)
  }
  // Precompute function return types
  for decl in prog.decls {
    self.func_rets[decl.name] = decl.ret
  }
  // Record global variables
  for g in prog.globals {
    self.globals[g.name] = g
  }
  for decl in prog.decls {
    self.gen_func(decl)
  }
  // Emit initialized global variables
  let mut has_data = false
  for name, g in self.globals {
    if g.init.is_some() {
      if not(has_data) {
        self.emit("	.section	__DATA,__data")
        has_data = true
      }
      self.emit("	.globl	_" + name)
      self.emit("	.p2align	3")
      self.emit("_" + name + ":")
      match g.init {
        Some(Scalar(expr)) => self.emit_global_scalar(g.ty, expr)
        Some(Array(exprs)) => self.emit_global_array(g.ty, exprs)
        None => ()
      }
    }
  }
  // Emit uninitialized global variables
  let mut has_bss = false
  for name, g in self.globals {
    if g.init.is_none() {
      if not(has_bss) {
        self.emit("	.section	__DATA,__bss")
        has_bss = true
      }
      let size = self.type_size(g.ty)
      self.emit("	.globl	_" + name)
      self.emit("	.p2align	3")
      self.emit("_" + name + ":")
      self.emit("	.space	" + size.to_string())
    }
  }
  // Emit string literals
  if self.strings.length() > 0 {
    self.emit("	.section	__TEXT,__cstring,cstring_literals")
    for i = 0; i < self.strings.length(); i = i + 1 {
      self.emit("_str" + i.to_string() + ":")
      self.emit("	.asciz	\"" + escape_string(self.strings[i]) + "\"")
    }
  }
  self.output.to_string()
}

///|
fn Codegen::emit(self : Codegen, s : String) -> Unit {
  self.output.write_string(s)
  self.output.write_char('\n')
}

///|
fn Codegen::new_label(self : Codegen) -> String {
  let n = self.label_counter
  self.label_counter += 1
  "L" + n.to_string()
}

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
  ty : @parser.Type
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
  ty : @parser.Type
) -> Unit {
  match ty {
    Bool | SChar | UChar => self.emit("\tstrb\t" + w_reg(value_reg) + ", [" + addr_reg + "]")
    SShort | UShort => self.emit("\tstrh\t" + w_reg(value_reg) + ", [" + addr_reg + "]")
    SInt | UInt | Float => self.emit("\tstr\t" + w_reg(value_reg) + ", [" + addr_reg + "]")
    Atomic(inner) => self.emit_store_typed(value_reg, addr_reg, inner)
    _ => self.emit("\tstr\t" + value_reg + ", [" + addr_reg + "]")
  }
}

///|
// Get or create the assembly label name for an AST label.
// Case/default labels get unique anonymous labels (they are never goto targets).
// Regular labels are scoped to the function and sanitized.
fn Codegen::label_ref(self : Codegen, name : String) -> String {
  if name == "default" || name.starts_with("case_") {
    // Case/default labels are never goto targets; each gets a fresh unique label
    self.new_label()
  } else {
    // Regular label: scoped to function, sanitized
    "_" + self.func_name + "_label_" + sanitize_label(name)
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

///|
fn Codegen::type_size(self : Codegen, ty : @parser.Type) -> Int {
  match ty {
    Void => 0
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt | Float => 4
    SLong | ULong | SLongLong | ULongLong | Double | Pointer(_) => 8
    Array(elem, n) => self.type_size(elem) * n
    Atomic(ty) => self.type_size(ty)
    Struct(name) => {
      if not(self.struct_layouts.contains(name)) {
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
      for field in fields {
        let end = field.2 + field.3
        if end > max_end {
          max_end = end
        }
        let fa = self.type_align(field.1)
        if fa > max_align {
          max_align = fa
        }
      }
      // Round up to struct alignment (trailing padding)
      let padding = (max_align - max_end % max_align) % max_align
      max_end + padding
    }
    Union(name) => {
      if not(self.struct_layouts.contains(name)) {
        if self.struct_decls.contains(name) {
          self.compute_struct_layout(self.struct_decls[name])
        } else {
          // Forward-declared opaque union: assume pointer size
          return 8
        }
      }
      let fields = self.struct_layouts[name]
      let mut max_size = 0
      for field in fields {
        if field.3 > max_size {
          max_size = field.3
        }
      }
      max_size
    }
  }
}

///|
fn Codegen::type_align(self : Codegen, ty : @parser.Type) -> Int {
  match ty {
    Void => 1
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt | Float => 4
    SLong | ULong | SLongLong | ULongLong | Double | Pointer(_) => 8
    Array(elem, _) => self.type_align(elem)
    Atomic(ty) => self.type_align(ty)
    Struct(name) => {
      if not(self.struct_layouts.contains(name)) {
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
      if not(self.struct_layouts.contains(name)) {
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
fn Codegen::is_anon_type(self : Codegen, ty : @parser.Type) -> Bool {
  match ty {
    Struct(name) | Union(name) => name.has_prefix("__anon_")
    _ => false
  }
}

///|
fn Codegen::flatten_anon_fields(
  self : Codegen,
  ty : @parser.Type,
  base_offset : Int
) -> Array[(String, @parser.Type, Int, Int, Int, Int)] {
  let name = match ty {
    Struct(n) | Union(n) => n
    _ => return []
  }
  if not(self.struct_layouts.contains(name)) {
    if self.struct_decls.contains(name) {
      self.compute_struct_layout(self.struct_decls[name])
    } else {
      return []
    }
  }
  let result = []
  for f in self.struct_layouts[name] {
    if f.0 == "" && self.is_anon_type(f.1) {
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
  let mut current_container_size = 0
  let mut current_container_offset = 0
  let mut current_bit_offset = 0
  for field in decl.fields {
    // Anonymous struct/union member: flatten its fields into parent
    if field.name == "" && self.is_anon_type(field.ty) {
      let align = self.type_align(field.ty)
      let padding = (align - offset % align) % align
      offset += padding
      for f in self.flatten_anon_fields(field.ty, offset) {
        layout.push(f)
      }
      offset += self.type_size(field.ty)
      current_container_size = 0
      current_container_offset = 0
      current_bit_offset = 0
      continue
    }
    match field.bit_width {
      None => {
        // Normal field: align to natural boundary, reset bit packing
        let size = self.type_size(field.ty)
        let align = self.type_align(field.ty)
        let padding = (align - offset % align) % align
        offset += padding
        layout.push((field.name, field.ty, offset, size, 0, 0))
        offset += size
        current_container_size = 0
        current_container_offset = 0
        current_bit_offset = 0
      }
      Some(w) => {
        let container_size = self.type_size(field.ty)
        let container_align = self.type_align(field.ty)
        if w == 0 {
          // Zero-width bit-field: force alignment to next container boundary
          let padding = (container_align - offset % container_align) % container_align
          offset += padding
          current_container_size = 0
          current_container_offset = 0
          current_bit_offset = 0
          // Don't add a layout entry for zero-width bit-fields
        } else {
          // Start new container if needed
          if current_container_size == 0 ||
            current_container_size != container_size ||
            current_bit_offset + w > current_container_size * 8 {
            let padding = (container_align - offset % container_align) % container_align
            offset += padding
            current_container_offset = offset
            current_container_size = container_size
            current_bit_offset = 0
            offset += container_size
          }
          layout.push(
            (field.name, field.ty, current_container_offset, container_size, current_bit_offset, w),
          )
          current_bit_offset += w
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
    if field.name == "" && self.is_anon_type(field.ty) {
      for f in self.flatten_anon_fields(field.ty, 0) {
        layout.push(f)
      }
      continue
    }
    let size = self.type_size(field.ty)
    match field.bit_width {
      None => {
        layout.push((field.name, field.ty, 0, size, 0, 0))
      }
      Some(w) => {
        if w == 0 {
          // Zero-width bit-field in union: no effect
        } else {
          layout.push((field.name, field.ty, 0, size, 0, w))
        }
      }
    }
  }
  self.struct_layouts[decl.name] = layout
}

///|
fn Codegen::find_field_layout(
  self : Codegen,
  struct_name : String,
  field : String
) -> (String, @parser.Type, Int, Int, Int, Int)? {
  if not(self.struct_layouts.contains(struct_name)) {
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
fn Codegen::gen_func(self : Codegen, decl : @parser.FuncDecl) -> Unit {
  match decl.body {
    None => return
    Some(body) => {
      self.local_offsets = {}
      self.var_types = {}
      self.stack_size = 0
      self.emitted_labels = {}
      self.func_name = decl.name
      // Allocate space for params
      for i = 0; i < decl.params.length(); i = i + 1 {
        let _ = self.alloc_local(decl.params[i].name, decl.params[i].ty)
      }
      // Collect locals and compute offsets
      self.collect_locals(body)
      let frame_size = (self.stack_size + 15) / 16 * 16
      self.emit("\t.globl\t_" + decl.name)
      self.emit("\t.p2align\t2")
      self.emit("_" + decl.name + ":")
      self.emit("\tstp\tx29, x30, [sp, #-16]!")
      self.emit("\tmov\tx29, sp")
      if frame_size > 0 {
        self.emit("\tsub\tsp, sp, #" + frame_size.to_string())
      }
      // Store params
      for i = 0; i < decl.params.length(); i = i + 1 {
        let p = decl.params[i]
        let offset = self.local_offsets[p.name]
        let reg = "x" + i.to_string()
        self.emit_store_local(reg, offset, frame_size)
      }
      // Reset local state so gen_stmt allocates locals fresh
      let param_offsets : Map[String, Int] = {}
      let param_types : Map[String, @parser.Type] = {}
      let mut param_stack_end = 0
      for i = 0; i < decl.params.length(); i = i + 1 {
        let p = decl.params[i]
        param_offsets[p.name] = self.local_offsets[p.name]
        param_types[p.name] = self.var_types[p.name]
        param_stack_end = @math.maximum(param_stack_end, self.local_offsets[p.name] + self.type_size(p.ty))
      }
      self.local_offsets = param_offsets
      self.var_types = param_types
      self.stack_size = param_stack_end
      self.gen_stmt(body, frame_size)
      // Default return
      self.emit("\tmov\tx0, #0")
      self.emit("_" + decl.name + "_ret:")
      if frame_size > 0 {
        self.emit("\tadd\tsp, sp, #" + frame_size.to_string())
      }
      self.emit("\tldp\tx29, x30, [sp], #16")
      self.emit("\tret")
    }
  }
}

///|
fn Codegen::emit_load_local(self : Codegen, dst_reg : String, offset : Int, frame_size : Int) -> Unit {
  let off = offset - frame_size
  if off >= -256 && off <= 255 {
    self.emit("\tldr\t" + dst_reg + ", [x29, #" + off.to_string() + "]")
  } else {
    self.emit("\tmov\tx12, #" + off.to_string())
    self.emit("\tldr\t" + dst_reg + ", [x29, x12]")
  }
}

///|
fn Codegen::emit_store_local(self : Codegen, src_reg : String, offset : Int, frame_size : Int) -> Unit {
  let off = offset - frame_size
  if off >= -256 && off <= 255 {
    self.emit("\tstr\t" + src_reg + ", [x29, #" + off.to_string() + "]")
  } else {
    self.emit("\tmov\tx12, #" + off.to_string())
    self.emit("\tstr\t" + src_reg + ", [x29, x12]")
  }
}

///|
fn Codegen::emit_local_addr(self : Codegen, offset : Int, frame_size : Int) -> Unit {
  let off = offset - frame_size
  if off >= -256 && off <= 255 {
    self.emit("\tadd\tx9, x29, #" + off.to_string())
  } else {
    self.emit("\tmov\tx12, #" + off.to_string())
    self.emit("\tadd\tx9, x29, x12")
  }
}

///|
fn Codegen::alloc_local(
  self : Codegen,
  name : String,
  ty : @parser.Type,
) -> Int {
  let size = self.type_size(ty)
  let aligned_size = (size + 7) / 8 * 8
  let offset = self.stack_size
  self.stack_size += aligned_size
  self.local_offsets[name] = offset
  self.var_types[name] = ty
  offset
}

///|
fn Codegen::collect_locals(self : Codegen, stmt : @parser.Stmt) -> Unit {
  match stmt {
    Compound(stmts) =>
      for s in stmts {
        self.collect_locals(s)
      }
    StmtList(stmts) =>
      for s in stmts {
        self.collect_locals(s)
      }
    If(_, then_, else_) => {
      self.collect_locals(then_)
      match else_ {
        Some(e) => self.collect_locals(e)
        None => ()
      }
    }
    While(_, body) => self.collect_locals(body)
    For(init, _, _, body) => {
      match init {
        Some(i) => self.collect_locals(i)
        None => ()
      }
      self.collect_locals(body)
    }
    DoWhile(_, body) => self.collect_locals(body)
    Switch(_, cases) =>
      for c in cases {
        self.collect_locals(c.1)
      }
    Label(_, s) => self.collect_locals(s)
    VarDecl(ty, name, _) => {
      let _ = self.alloc_local(name, ty)
    }
    ComputedGoto(_) => ()
    _ => ()
  }
}

///|
fn Codegen::gen_stmt(
  self : Codegen,
  stmt : @parser.Stmt,
  frame_size : Int,
) -> Unit {
  match stmt {
    Compound(stmts) => {
      let saved_offsets = self.local_offsets.copy()
      let saved_types = self.var_types.copy()
      for s in stmts {
        self.gen_stmt(s, frame_size)
      }
      self.local_offsets = saved_offsets
      self.var_types = saved_types
    }
    StmtList(stmts) =>
      for s in stmts {
        self.gen_stmt(s, frame_size)
      }
    ExprStmt(expr) => self.gen_expr(expr, frame_size)
    Return(None) => {
      self.emit("\tmov\tx0, #0")
      self.emit("\tb\t_" + self.func_name + "_ret")
    }
    Return(Some(expr)) => {
      self.gen_expr(expr, frame_size)
      self.emit("\tmov\tx0, x9")
      self.emit("\tb\t_" + self.func_name + "_ret")
    }
    If(cond, then_, else_) => {
      let else_label = self.new_label()
      let end_label = self.new_label()
      self.gen_expr(cond, frame_size)
      self.emit("\tcbz\tx9, " + else_label)
      self.gen_stmt(then_, frame_size)
      self.emit("\tb\t" + end_label)
      self.emit(else_label + ":")
      match else_ {
        Some(e) => self.gen_stmt(e, frame_size)
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
      self.gen_expr(cond, frame_size)
      self.emit("\tcbz\tx9, " + end_label)
      self.gen_stmt(body, frame_size)
      self.emit("\tb\t" + start_label)
      self.emit(end_label + ":")
      self.break_label = old_break
      self.continue_label = old_continue
    }
    For(init, cond, update, body) => {
      let start_label = self.new_label()
      let continue_label = self.new_label()
      let end_label = self.new_label()
      let old_break = self.break_label
      let old_continue = self.continue_label
      self.break_label = Some(end_label)
      self.continue_label = Some(continue_label)
      // init
      match init {
        Some(i) => self.gen_stmt(i, frame_size)
        None => ()
      }
      self.emit(start_label + ":")
      self.gen_expr(cond, frame_size)
      self.emit("\tcbz\tx9, " + end_label)
      self.gen_stmt(body, frame_size)
      self.emit(continue_label + ":")
      match update {
        Some(u) => self.gen_expr(u, frame_size)
        None => ()
      }
      self.emit("\tb\t" + start_label)
      self.emit(end_label + ":")
      self.break_label = old_break
      self.continue_label = old_continue
    }
    DoWhile(cond, body) => {
      let start_label = self.new_label()
      let cond_label = self.new_label()
      let end_label = self.new_label()
      let old_break = self.break_label
      let old_continue = self.continue_label
      self.break_label = Some(end_label)
      self.continue_label = Some(cond_label)
      self.emit(start_label + ":")
      self.gen_stmt(body, frame_size)
      self.emit(cond_label + ":")
      self.gen_expr(cond, frame_size)
      self.emit("\tcbnz\tx9, " + start_label)
      self.emit(end_label + ":")
      self.break_label = old_break
      self.continue_label = old_continue
    }
    Break => {
      match self.break_label {
        Some(label) => self.emit("\tb\t" + label)
        None => abort("break outside of loop or switch")
      }
    }
    Continue => {
      match self.continue_label {
        Some(label) => self.emit("\tb\t" + label)
        None => abort("continue outside of loop")
      }
    }
    Switch(expr, cases) => {
      let end_label = self.new_label()
      let old_break = self.break_label
      self.break_label = Some(end_label)
      self.gen_expr(expr, frame_size)
      // Generate comparison and branch for each case
      let case_labels = []
      for c in cases {
        let label = self.new_label()
        case_labels.push(label)
        match c.0 {
          Some(n) => {
            if fits_cmp_imm(n) {
              self.emit("\tcmp\tx9, #" + n.to_string())
            } else {
              self.emit_load_int("x10", n)
              self.emit("\tcmp\tx9, x10")
            }
            self.emit("\tb.eq\t" + label)
          }
          None => () // default handled after all cases
        }
      }
      // Branch to default or end
      let default_label = if cases.length() > 0 {
        match cases[cases.length() - 1].0 {
          None => case_labels[cases.length() - 1]
          Some(_) => end_label
        }
      } else {
        end_label
      }
      self.emit("\tb\t" + default_label)
      // Generate case bodies
      for i = 0; i < cases.length(); i = i + 1 {
        self.emit(case_labels[i] + ":")
        self.gen_stmt(cases[i].1, frame_size)
      }
      self.emit(end_label + ":")
      self.break_label = old_break
    }
    Goto(name) => {
      self.emit("\tb\t" + self.label_ref(name))
    }
    ComputedGoto(expr) => {
      self.gen_expr(expr, frame_size)
      self.emit("\tbr\tx9")
    }
    Label(name, stmt) => {
      self.emit(self.label_ref(name) + ":")
      self.gen_stmt(stmt, frame_size)
    }
    VarDecl(ty, name, init) => {
      let offset = self.alloc_local(name, ty)
      match init {
        Some(expr) => {
          self.gen_expr(expr, frame_size)
          self.emit_store_local("x9", offset, frame_size)
        }
        None => ()
      }
    }
  }
}

///|
fn Codegen::type_of(
  self : Codegen,
  expr : @parser.Expr,
  frame_size : Int,
) -> @parser.Type {
  match expr {
    Number(_) => SInt
    String(_) => Pointer(SChar)
    Var(name) => {
      if self.var_types.contains(name) {
        self.var_types[name]
      } else if self.globals.contains(name) {
        self.globals[name].ty
      } else if self.func_rets.contains(name) {
        Pointer(Void) // Function pointer type
      } else {
        println("WARN: Unknown variable type: " + name)
        SInt
      }
    }
    Binary(_, _, _) => SInt
    Unary("-", _) => SInt
    Unary("!", _) => SInt
    Unary("~", _) => SInt
    Call(func, _) => match func {
      Var(name) =>
        if self.func_rets.contains(name) {
          self.func_rets[name]
        } else {
          SInt
        }
      _ => SInt
    }
    Assign(_, rhs) => self.type_of(rhs, frame_size)
    MemberAccess(obj, field) => {
      let obj_ty = self.type_of(obj, frame_size)
      let struct_name = match obj_ty {
        Struct(n) => n
        Union(n) => n
        _ => {
          println("WARN: Member access on non-struct type: " + obj_ty.to_string())
          return SInt
        }
      }
      if self.struct_layouts.contains(struct_name) {
        let fields = self.struct_layouts[struct_name]
        for f in fields {
          if f.0 == field {
            return f.1
          }
        }
      }
      println("WARN: Unknown field '" + field + "' in struct '" + struct_name + "'")
      SInt
    }
    Deref(ptr) =>
      match self.type_of(ptr, frame_size) {
        Pointer(ty) => ty
        Array(elem, _) => elem
        _ => {
          println("WARN: Deref of non-pointer")
          SInt
        }
      }
    AddrOf(e) => Pointer(self.type_of(e, frame_size))
    ArrayAccess(arr, _) =>
      match self.type_of(arr, frame_size) {
        Array(elem, _) => elem
        Pointer(elem) => elem
        _ => {
          println("WARN: Array access on non-array")
          SInt
        }
      }
    Sizeof(_) => SInt
    SizeofExpr(_) => SInt
    PrefixInc(e) => self.type_of(e, frame_size)
    PrefixDec(e) => self.type_of(e, frame_size)
    PostfixInc(e) => self.type_of(e, frame_size)
    PostfixDec(e) => self.type_of(e, frame_size)
    Ternary(_, then_, _) => self.type_of(then_, frame_size)
    LabelAddr(_) => Pointer(Void)
    // CommaExpr is not in the AST, comma expressions are flattened into nested Binary(",", ...)
    Cast(ty, _) => ty
    _ => {
      println("WARN: Unknown expression type")
      SInt
    }
  }
}

///|
fn Codegen::emit_builtin_call(
  self : Codegen,
  name : String,
  args : Array[@parser.Expr],
  frame_size : Int
) -> Bool {
  match name {
    "__builtin_expect" => {
      // __builtin_expect(exp, c) -> just return exp
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_unreachable" => {
      self.emit("\tbrk\t#0x1")
      true
    }
    "__builtin_trap" => {
      self.emit("\tbrk\t#0x1")
      true
    }
    "__builtin_assume" => {
      // No-op
      self.emit("\tmov\tx9, #0")
      true
    }
    "__builtin_clz" | "__builtin_clzl" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tclz\tw9, w9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_clzll" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tclz\tx9, x9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_ctz" | "__builtin_ctzl" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\trbit\tw9, w9")
        self.emit("\tclz\tw9, w9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_ctzll" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\trbit\tx9, x9")
        self.emit("\tclz\tx9, x9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_bswap32" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\trev\tw9, w9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_bswap64" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\trev\tx9, x9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_popcount" | "__builtin_popcountl" | "__builtin_popcountll" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        // ARM64 doesn't have scalar popcount; use a software fallback
        // Store arg, call stub
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.emit("\tbl\t___popcountdi2")
        self.emit("\tadd\tsp, sp, #16")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_memcpy" => {
      if args.length() >= 3 {
        for i = 0; i < 3; i = i + 1 {
          self.gen_expr(args[i], frame_size)
          self.emit("\tmov\tx" + i.to_string() + ", x9")
        }
        self.emit("\tbl\t_memcpy")
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin_memset" => {
      if args.length() >= 3 {
        for i = 0; i < 3; i = i + 1 {
          self.gen_expr(args[i], frame_size)
          self.emit("\tmov\tx" + i.to_string() + ", x9")
        }
        self.emit("\tbl\t_memset")
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin_memmove" => {
      if args.length() >= 3 {
        for i = 0; i < 3; i = i + 1 {
          self.gen_expr(args[i], frame_size)
          self.emit("\tmov\tx" + i.to_string() + ", x9")
        }
        self.emit("\tbl\t_memmove")
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin_strlen" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tmov\tx0, x9")
        self.emit("\tbl\t_strlen")
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin_strcmp" => {
      if args.length() >= 2 {
        for i = 0; i < 2; i = i + 1 {
          self.gen_expr(args[i], frame_size)
          self.emit("\tmov\tx" + i.to_string() + ", x9")
        }
        self.emit("\tbl\t_strcmp")
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin_strcpy" => {
      if args.length() >= 2 {
        for i = 0; i < 2; i = i + 1 {
          self.gen_expr(args[i], frame_size)
          self.emit("\tmov\tx" + i.to_string() + ", x9")
        }
        self.emit("\tbl\t_strcpy")
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    _ => false
  }
}

///|
fn Codegen::gen_expr(
  self : Codegen,
  expr : @parser.Expr,
  frame_size : Int,
) -> Unit {
  match expr {
    Number(n) => self.emit_load_int("x9", n)
    String(s) => {
      let idx = self.strings.length()
      self.strings.push(s)
      let label = "_str" + idx.to_string()
      self.emit("\tadrp\tx9, " + label + "@PAGE")
      self.emit("\tadd\tx9, x9, " + label + "@PAGEOFF")
    }
    Var(name) => {
      if self.local_offsets.contains(name) {
        let ty = self.var_types[name]
        let offset = self.local_offsets[name]
        match ty {
          Array(_, _) | Struct(_) | Union(_) =>
            self.emit_local_addr(offset, frame_size)
          _ => {
            self.emit_local_addr(offset, frame_size)
            self.emit_load_typed("x9", "x9", ty)
          }
        }
      } else if self.globals.contains(name) {
        let ty = self.globals[name].ty
        self.emit("\tadrp\tx9, _" + name + "@PAGE")
        self.emit("\tadd\tx9, x9, _" + name + "@PAGEOFF")
        match ty {
          Array(_, _) | Struct(_) | Union(_) => ()
          _ => self.emit_load_typed("x9", "x9", ty)
        }
      } else if self.func_rets.contains(name) {
        // Function pointer / function address
        self.emit("\tadrp\tx9, _" + name + "@PAGE")
        self.emit("\tadd\tx9, x9, _" + name + "@PAGEOFF")
      } else {
        println("WARN: Unknown variable: " + name)
        self.emit("\tmov\tx9, #0")
      }
    }
    Assign(lhs, rhs) => {
      // Check if lhs is a bit-field member access
      let is_bitfield = match lhs {
        MemberAccess(obj, field) => {
          let obj_ty = self.type_of(obj, frame_size)
          let struct_name = match obj_ty {
            Struct(n) => n
            Union(n) => n
            _ => ""
          }
          if struct_name != "" {
            match self.find_field_layout(struct_name, field) {
              Some((_, _, _, _, _, bit_width)) => bit_width > 0
              None => false
            }
          } else {
            false
          }
        }
        _ => false
      }
      if is_bitfield {
        // Bit-field assignment: read-modify-write
        self.gen_expr(rhs, frame_size)
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.gen_addr(lhs, frame_size)  // returns container address
        self.emit("\tmov\tx10, x9")
        self.emit("\tldr\tx9, [sp], #16")  // value in x9
        // Get bit-field info
        match lhs {
          MemberAccess(obj, field) => {
            let obj_ty = self.type_of(obj, frame_size)
            let struct_name = match obj_ty {
              Struct(n) => n
              Union(n) => n
              _ => ""
            }
            match self.find_field_layout(struct_name, field) {
              Some((_, _, _, size, bit_offset, bit_width)) => {
                // Load container
                match size {
                  1 => self.emit("\tldrb\tw11, [x10]")
                  2 => self.emit("\tldrh\tw11, [x10]")
                  4 => self.emit("\tldr\tw11, [x10]")
                  _ => self.emit("\tldr\tx11, [x10]")
                }
                // Clear old bits
                let mask = (1 << bit_width) - 1
                self.emit_load_int("x12", mask.to_int64())
                self.emit("\tlsl\tx12, x12, #" + bit_offset.to_string())
                self.emit("\tmvn\tx12, x12")
                self.emit("\tand\tx11, x11, x12")
                // Insert new value
                self.emit_load_int("x12", mask.to_int64())
                self.emit("\tand\tx9, x9, x12")
                self.emit("\tlsl\tx9, x9, #" + bit_offset.to_string())
                self.emit("\torr\tx11, x11, x9")
                // Store container back
                match size {
                  1 => self.emit("\tstrb\tw11, [x10]")
                  2 => self.emit("\tstrh\tw11, [x10]")
                  4 => self.emit("\tstr\tw11, [x10]")
                  _ => self.emit("\tstr\tx11, [x10]")
                }
              }
              None => ()
            }
          }
          _ => ()
        }
      } else {
        self.gen_expr(rhs, frame_size)
        self.emit("\tstr\tx9, [sp, #-16]!")
        self.gen_addr(lhs, frame_size)
        self.emit("\tmov\tx10, x9")
        self.emit("\tldr\tx9, [sp], #16")
        let lhs_ty = self.type_of(lhs, frame_size)
        self.emit_store_typed("x9", "x10", lhs_ty)
      }
    }
    Binary("&&", left, right) => {
      let end_label = self.new_label()
      let false_label = self.new_label()
      self.gen_expr(left, frame_size)
      self.emit("\tcbz\tx9, " + false_label)
      self.gen_expr(right, frame_size)
      self.emit("\tcbz\tx9, " + false_label)
      self.emit("\tmov\tx9, #1")
      self.emit("\tb\t" + end_label)
      self.emit(false_label + ":")
      self.emit("\tmov\tx9, #0")
      self.emit(end_label + ":")
    }
    Binary("||", left, right) => {
      let end_label = self.new_label()
      let true_label = self.new_label()
      self.gen_expr(left, frame_size)
      self.emit("\tcbnz\tx9, " + true_label)
      self.gen_expr(right, frame_size)
      self.emit("\tcbnz\tx9, " + true_label)
      self.emit("\tmov\tx9, #0")
      self.emit("\tb\t" + end_label)
      self.emit(true_label + ":")
      self.emit("\tmov\tx9, #1")
      self.emit(end_label + ":")
    }
    Binary(op, left, right) => {
      let left_ty = self.type_of(left, frame_size)
      let right_ty = self.type_of(right, frame_size)
      let ptr_scale = match (left_ty, right_ty) {
        (Pointer(elem), _) => self.type_size(elem)
        (Array(elem, _), _) => self.type_size(elem)
        (_, Pointer(elem)) => self.type_size(elem)
        (_, Array(elem, _)) => self.type_size(elem)
        _ => 1
      }
      let is_ptr_diff = match (left_ty, right_ty) {
        (Pointer(_), Pointer(_)) => true
        (Array(_, _), Pointer(_)) => true
        (Pointer(_), Array(_, _)) => true
        (Array(_, _), Array(_, _)) => true
        _ => false
      }
      self.gen_expr(left, frame_size)
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.gen_expr(right, frame_size)
      if ptr_scale > 1 && not(is_ptr_diff) {
        self.emit("\tmov\tx11, #" + ptr_scale.to_string())
        self.emit("\tmul\tx9, x9, x11")
      }
      self.emit("\tmov\tx10, x9")
      self.emit("\tldr\tx9, [sp], #16")
      match op {
        "+" => self.emit("\tadd\tx9, x9, x10")
        "-" => {
          self.emit("\tsub\tx9, x9, x10")
          if is_ptr_diff && ptr_scale > 1 {
            self.emit("\tmov\tx11, #" + ptr_scale.to_string())
            self.emit("\tsdiv\tx9, x9, x11")
          }
        }
        "*" => self.emit("\tmul\tx9, x9, x10")
        "/" => self.emit("\tsdiv\tx9, x9, x10")
        "%" => self.emit("\tsdiv\tx11, x9, x10\n\tmsub\tx9, x11, x10, x9")
        "&" => self.emit("\tand\tx9, x9, x10")
        "|" => self.emit("\torr\tx9, x9, x10")
        "^" => self.emit("\teor\tx9, x9, x10")
        "<<" => self.emit("\tlsl\tx9, x9, x10")
        ">>" => self.emit("\tasr\tx9, x9, x10")
        "," => {
          // Result is the right operand (in x10)
          self.emit("\tmov\tx9, x10")
        }
        "==" => {
          self.emit("\tcmp\tx9, x10")
          self.emit("\tcset\tx9, eq")
        }
        "!=" => {
          self.emit("\tcmp\tx9, x10")
          self.emit("\tcset\tx9, ne")
        }
        "<" => {
          self.emit("\tcmp\tx9, x10")
          self.emit("\tcset\tx9, lt")
        }
        "<=" => {
          self.emit("\tcmp\tx9, x10")
          self.emit("\tcset\tx9, le")
        }
        ">" => {
          self.emit("\tcmp\tx9, x10")
          self.emit("\tcset\tx9, gt")
        }
        ">=" => {
          self.emit("\tcmp\tx9, x10")
          self.emit("\tcset\tx9, ge")
        }
        _ => {
          println("WARN: Unknown binary operator: " + op)
        }
      }
    }
    Unary("-", operand) => {
      self.gen_expr(operand, frame_size)
      self.emit("\tneg\tx9, x9")
    }
    Unary("~", operand) => {
      self.gen_expr(operand, frame_size)
      self.emit("\tmvn\tx9, x9")
    }
    Unary("!", operand) => {
      self.gen_expr(operand, frame_size)
      self.emit("\tcmp\tx9, #0")
      self.emit("\tcset\tx9, eq")
    }
    Call(func, args) => {
      // Try builtin dispatch first
      let is_builtin = match func {
        Var(name) => self.emit_builtin_call(name, args, frame_size)
        _ => false
      }
      if not(is_builtin) {
        for i = 0; i < args.length(); i = i + 1 {
          self.gen_expr(args[i], frame_size)
          let reg = "x" + i.to_string()
          self.emit("\tmov\t" + reg + ", x9")
        }
        match func {
          Var(name) => {
            if self.local_offsets.contains(name) || self.globals.contains(name) {
              // Function pointer variable: load and call indirectly
              self.gen_expr(func, frame_size)
              self.emit("\tmov\tx15, x9")
              self.emit("\tblr\tx15")
            } else {
              self.emit("\tbl\t_" + name)
            }
          }
          _ => {
            self.gen_expr(func, frame_size)
            self.emit("\tmov\tx15, x9")
            self.emit("\tblr\tx15")
          }
        }
        self.emit("\tmov\tx9, x0")
      }
    }
    MemberAccess(obj, field) => {
      let obj_ty = self.type_of(obj, frame_size)
      let struct_name = match obj_ty {
        Struct(n) => n
        Union(n) => n
        _ => {
          println("WARN: MemberAccess on non-struct: " + obj_ty.to_string())
          self.gen_addr(expr, frame_size)
          self.emit("\tldr\tx9, [x9]")
          return
        }
      }
      match self.find_field_layout(struct_name, field) {
        None => {
          println("WARN: Unknown field '" + field + "' in struct '" + struct_name + "'")
          self.emit("\tmov\tx9, #0")
        }
        Some((_, ty, offset, size, bit_offset, bit_width)) => {
          // Compute address of container
          self.gen_addr(obj, frame_size)
          if offset != 0 {
            self.emit("\tadd\tx9, x9, #" + offset.to_string())
          }
          // Load container based on size
          match size {
            1 => self.emit("\tldrb\tw9, [x9]")
            2 => self.emit("\tldrh\tw9, [x9]")
            4 => self.emit("\tldr\tw9, [x9]")
            _ => self.emit("\tldr\tx9, [x9]")
          }
          if bit_width > 0 {
            // Extract bit-field
            self.emit("\tlsr\tx9, x9, #" + bit_offset.to_string())
            if bit_width < 64 {
              let mask = (1 << bit_width) - 1
              self.emit_load_int("x10", mask.to_int64())
              self.emit("\tand\tx9, x9, x10")
            }
          }
          // Sign-extend if signed type
          if ty.is_signed() {
            if bit_width > 0 {
              // Bit-field: sign-extend from bit_width
              let shift = 64 - bit_width
              self.emit("\tlsl\tx9, x9, #" + shift.to_string())
              self.emit("\tasr\tx9, x9, #" + shift.to_string())
            } else {
              // Normal field: sign-extend from field size
              match size {
                1 => self.emit("\tsxtb\tx9, w9")
                2 => self.emit("\tsxth\tx9, w9")
                4 => self.emit("\tsxtw\tx9, w9")
                _ => ()
              }
            }
          }
        }
      }
    }
    Deref(ptr) => {
      self.gen_expr(ptr, frame_size)
      let deref_ty = match self.type_of(ptr, frame_size) {
        Pointer(ty) => ty
        Array(elem, _) => elem
        _ => SInt
      }
      self.emit_load_typed("x9", "x9", deref_ty)
    }
    AddrOf(e) => self.gen_addr(e, frame_size)
    ArrayAccess(_, _) => {
      self.gen_addr(expr, frame_size)
      let elem_ty = self.type_of(expr, frame_size)
      self.emit_load_typed("x9", "x9", elem_ty)
    }
    Sizeof(ty) => {
      let size = self.type_size(ty)
      self.emit_load_int("x9", size.to_int64())
    }
    SizeofExpr(expr) => {
      let ty = self.type_of(expr, frame_size)
      let size = self.type_size(ty)
      self.emit_load_int("x9", size.to_int64())
    }
    Cast(ty, expr) => {
      self.gen_expr(expr, frame_size)
      match ty {
        SChar => {
          // Sign-extend byte
          self.emit("\tsxtb\tx9, w9")
        }
        UChar => {
          // Zero-extend byte
          self.emit("\tand\tx9, x9, #0xFF")
        }
        SShort => {
          // Sign-extend halfword
          self.emit("\tsxth\tx9, w9")
        }
        UShort => {
          // Zero-extend halfword
          self.emit("\tand\tx9, x9, #0xFFFF")
        }
        SInt => {
          // Sign-extend word
          self.emit("\tsxtw\tx9, w9")
        }
        UInt => {
          // Already zero-extended in 64-bit register, no-op for now
          ()
        }
        _ => {
          // pointer, struct, array, void, long, long long, bool, float, double: no-op
          ()
        }
      }
    }
    Ternary(cond, then_expr, else_expr) => {
      let else_label = self.new_label()
      let end_label = self.new_label()
      self.gen_expr(cond, frame_size)
      self.emit("\tcbz\tx9, " + else_label)
      self.gen_expr(then_expr, frame_size)
      self.emit("\tb\t" + end_label)
      self.emit(else_label + ":")
      self.gen_expr(else_expr, frame_size)
      self.emit(end_label + ":")
    }
    PrefixInc(expr) => {
      self.gen_addr(expr, frame_size)
      let ty = self.type_of(expr, frame_size)
      let ptr_scale = match ty {
        Pointer(elem) => self.type_size(elem)
        _ => 1
      }
      self.emit_load_typed("x10", "x9", ty)
      if ptr_scale > 1 {
        self.emit("\tadd\tx11, x10, #" + ptr_scale.to_string())
      } else {
        self.emit("\tadd\tx11, x10, #1")
      }
      self.emit_store_typed("x11", "x9", ty)
      match ty {
        SChar => self.emit("\tsxtb\tx9, w11")
        SShort => self.emit("\tsxth\tx9, w11")
        SInt => self.emit("\tsxtw\tx9, w11")
        _ => self.emit("\tmov\tx9, x11")
      }
    }
    PrefixDec(expr) => {
      self.gen_addr(expr, frame_size)
      let ty = self.type_of(expr, frame_size)
      let ptr_scale = match ty {
        Pointer(elem) => self.type_size(elem)
        _ => 1
      }
      self.emit_load_typed("x10", "x9", ty)
      if ptr_scale > 1 {
        self.emit("\tsub\tx11, x10, #" + ptr_scale.to_string())
      } else {
        self.emit("\tsub\tx11, x10, #1")
      }
      self.emit_store_typed("x11", "x9", ty)
      match ty {
        SChar => self.emit("\tsxtb\tx9, w11")
        SShort => self.emit("\tsxth\tx9, w11")
        SInt => self.emit("\tsxtw\tx9, w11")
        _ => self.emit("\tmov\tx9, x11")
      }
    }
    PostfixInc(expr) => {
      self.gen_addr(expr, frame_size)
      let ty = self.type_of(expr, frame_size)
      let ptr_scale = match ty {
        Pointer(elem) => self.type_size(elem)
        _ => 1
      }
      self.emit_load_typed("x10", "x9", ty)
      if ptr_scale > 1 {
        self.emit("\tadd\tx11, x10, #" + ptr_scale.to_string())
      } else {
        self.emit("\tadd\tx11, x10, #1")
      }
      self.emit_store_typed("x11", "x9", ty)
      match ty {
        SChar => self.emit("\tsxtb\tx9, w10")
        SShort => self.emit("\tsxth\tx9, w10")
        SInt => self.emit("\tsxtw\tx9, w10")
        _ => self.emit("\tmov\tx9, x10")
      }
    }
    PostfixDec(expr) => {
      self.gen_addr(expr, frame_size)
      let ty = self.type_of(expr, frame_size)
      let ptr_scale = match ty {
        Pointer(elem) => self.type_size(elem)
        _ => 1
      }
      self.emit_load_typed("x10", "x9", ty)
      if ptr_scale > 1 {
        self.emit("\tsub\tx11, x10, #" + ptr_scale.to_string())
      } else {
        self.emit("\tsub\tx11, x10, #1")
      }
      self.emit_store_typed("x11", "x9", ty)
      match ty {
        SChar => self.emit("\tsxtb\tx9, w10")
        SShort => self.emit("\tsxth\tx9, w10")
        SInt => self.emit("\tsxtw\tx9, w10")
        _ => self.emit("\tmov\tx9, x10")
      }
    }
    LabelAddr(name) => {
      let label = self.label_ref(name)
      self.emit("\tadr\tx9, " + label)
    }
    _ => {
      println("WARN: Unknown expression")
      self.emit("\tmov\tx9, #0")
    }
  }
}

///|
fn Codegen::gen_addr(
  self : Codegen,
  expr : @parser.Expr,
  frame_size : Int,
) -> Unit {
  match expr {
    Var(name) => {
      if self.local_offsets.contains(name) {
        let offset = self.local_offsets[name]
        self.emit_local_addr(offset, frame_size)
      } else if self.globals.contains(name) || self.func_rets.contains(name) {
        self.emit("\tadrp\tx9, _" + name + "@PAGE")
        self.emit("\tadd\tx9, x9, _" + name + "@PAGEOFF")
      } else {
        println("WARN: Unknown variable in address: " + name)
      }
    }
    MemberAccess(obj, field) => {
      self.gen_addr(obj, frame_size)
      let obj_ty = self.type_of(obj, frame_size)
      let struct_name = match obj_ty {
        Struct(n) => n
        Union(n) => n
        _ => {
          println("WARN: gen_addr MemberAccess on non-struct: " + obj_ty.to_string())
          return
        }
      }
      if self.struct_layouts.contains(struct_name) {
        let fields = self.struct_layouts[struct_name]
        let mut field_offset = 0
        for f in fields {
          if f.0 == field {
            field_offset = f.2
            break
          }
        }
        if field_offset != 0 {
          self.emit("\tadd\tx9, x9, #" + field_offset.to_string())
        }
      }
    }
    Deref(ptr) => self.gen_expr(ptr, frame_size)
    AddrOf(e) => self.gen_addr(e, frame_size)
    ArrayAccess(arr, index) => {
      // Array decay: if arr is an array type, use its address; if pointer, use its value
      match self.type_of(arr, frame_size) {
        Array(_, _) => self.gen_addr(arr, frame_size)
        _ => self.gen_expr(arr, frame_size)
      }
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.gen_expr(index, frame_size)
      self.emit("\tmov\tx12, x9")
      self.emit("\tldr\tx9, [sp], #16")
      let elem_ty = self.type_of(expr, frame_size)
      let elem_size = self.type_size(elem_ty)
      self.emit("\tmov\tx11, #" + elem_size.to_string())
      self.emit("\tmadd\tx9, x12, x11, x9")
    }
    Call(_, _) => {
      // Function call result used as address (e.g., compound literal or GCC extension)
      self.gen_expr(expr, frame_size)
    }
    LabelAddr(name) => {
      let label = self.label_ref(name)
      self.emit("\tadr\tx9, " + label)
    }
    _ => {
      println("WARN: Cannot take address of expression")
    }
  }
}
