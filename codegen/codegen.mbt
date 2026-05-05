///|
pub struct Codegen {
  output : StringBuilder
  mut label_counter : Int
  mut local_offsets : Map[String, Int]
  mut var_types : Map[String, @parser.Type]
  mut stack_size : Int
  mut func_name : String
  mut func_params : Array[@parser.Param]
  func_rets : Map[String, @parser.Type]
  func_variadic : Map[String, Bool]
  func_param_counts : Map[String, Int]
  struct_layouts : Map[
    String,
    Array[(String, @parser.Type, Int, Int, Int, Int)],
  ]
  struct_decls : Map[String, @parser.StructDecl]
  strings : Array[String]
  mut break_label : String?
  mut continue_label : String?
  globals : Map[String, @parser.GlobalDecl]
  mut emitted_labels : Map[String, String]
  mut defined_labels : Map[String, Bool]
  mut fp_literals : Array[Double]
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
fn reloc_with_offset(base : String, offset : Int) -> String {
  if offset == 0 {
    base
  } else if offset > 0 {
    base + "+" + offset.to_string()
  } else {
    base + offset.to_string()
  }
}

///|
fn Codegen::global_expr_type(
  self : Codegen,
  expr : @parser.Expr,
) -> @parser.Type {
  match expr {
    Var(name) =>
      if self.globals.contains(name) {
        self.globals[name].ty
      } else {
        Pointer(Void)
      }
    Cast(ty, _) => ty
    AddrOf(e) => Pointer(self.global_expr_type(e))
    ArrayAccess(base, _) =>
      match self.global_expr_type(base) {
        Array(elem, _) | Pointer(elem) => elem
        _ => SInt
      }
    MemberAccess(obj, field) =>
      match self.global_expr_type(obj) {
        Struct(name) | Union(name) =>
          match self.find_field_layout(name, field) {
            Some((_, ty, _, _, _, _)) => ty
            None => SInt
          }
        Pointer(Struct(name)) | Pointer(Union(name)) =>
          match self.find_field_layout(name, field) {
            Some((_, ty, _, _, _, _)) => ty
            None => SInt
          }
        _ => SInt
      }
    _ => SInt
  }
}

///|
fn Codegen::global_lvalue_reloc(
  self : Codegen,
  expr : @parser.Expr,
) -> (String, Int)? {
  match expr {
    Var(name) => Some(("_" + name, 0))
    ArrayAccess(base, index) =>
      match self.global_lvalue_reloc(base) {
        Some((label, base_offset)) => {
          let elem_size = match self.global_expr_type(base) {
            Array(elem, _) | Pointer(elem) => self.type_size(elem)
            _ => 1
          }
          match @parser.fold_const(index) {
            Some(i) => Some((label, base_offset + i.to_int() * elem_size))
            None => None
          }
        }
        None => None
      }
    MemberAccess(obj, field) =>
      match self.global_lvalue_reloc(obj) {
        Some((label, base_offset)) =>
          match self.global_expr_type(obj) {
            Struct(name)
            | Union(name)
            | Pointer(Struct(name))
            | Pointer(Union(name)) =>
              match self.find_field_layout(name, field) {
                Some((_, _, field_offset, _, _, _)) =>
                  Some((label, base_offset + field_offset))
                None => None
              }
            _ => None
          }
        None => None
      }
    _ => None
  }
}

///|
fn Codegen::global_address_reloc(
  self : Codegen,
  expr : @parser.Expr,
) -> String? {
  match expr {
    Cast(_, e) => self.global_address_reloc(e)
    AddrOf(e) =>
      match self.global_lvalue_reloc(e) {
        Some((label, offset)) => Some(reloc_with_offset(label, offset))
        None => None
      }
    Var(name) => Some("_" + name)
    Binary("+", base, offset_expr) =>
      match (self.global_address_reloc(base), @parser.fold_const(offset_expr)) {
        (Some(label), Some(offset)) =>
          Some(reloc_with_offset(label, offset.to_int()))
        _ =>
          match
            (self.global_address_reloc(offset_expr), @parser.fold_const(base)) {
            (Some(label), Some(offset)) =>
              Some(reloc_with_offset(label, offset.to_int()))
            _ => None
          }
      }
    Binary("-", base, offset_expr) =>
      match (self.global_address_reloc(base), @parser.fold_const(offset_expr)) {
        (Some(label), Some(offset)) =>
          Some(reloc_with_offset(label, -offset.to_int()))
        _ => None
      }
    _ => None
  }
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
    func_params: [],
    func_rets: {},
    func_variadic: {},
    func_param_counts: {},
    struct_layouts: {},
    struct_decls: {},
    strings: [],
    break_label: None,
    continue_label: None,
    globals: {},
    emitted_labels: {},
    defined_labels: {},
    fp_literals: [],
  }
}

///|
fn Codegen::emit_global_scalar(
  self : Codegen,
  ty : @parser.Type,
  expr : @parser.Expr,
) -> Unit {
  match ty {
    Pointer(_) =>
      match self.global_address_reloc(expr) {
        Some(reloc) => {
          self.emit("\t.quad\t" + reloc)
          return
        }
        None => ()
      }
    _ => ()
  }
  // Try constant-fold the expression first
  let folded_expr = match @parser.fold_const(expr) {
    Some(n) => @parser.Expr::Number(n)
    None => expr
  }
  match folded_expr {
    Number(n) =>
      match ty {
        Bool | SChar | UChar => self.emit("\t.byte\t" + n.to_string())
        SShort | UShort => self.emit("\t.short\t" + n.to_string())
        SInt | UInt | Float => self.emit("\t.long\t" + n.to_string())
        Struct(_) | Union(_) | Array(_, _) => {
          // Zero-initialize aggregate type
          let size = self.type_size(ty)
          self.emit("\t.space\t" + size.to_string())
        }
        _ => self.emit("\t.quad\t" + n.to_string())
      }
    FloatLiteral(v) =>
      match ty {
        Float => self.emit("\t.single\t" + v.to_string())
        _ => self.emit("\t.double\t" + v.to_string())
      }
    String(s) =>
      match ty {
        Array(SChar, n) | Array(UChar, n) => {
          self.emit("\t.asciz\t\"" + escape_string(s) + "\"")
          let pad = n - s.length() - 1
          if pad > 0 {
            self.emit("\t.space\t" + pad.to_string())
          }
        }
        _ => {
          let idx = self.strings.length()
          self.strings.push(s)
          self.emit("\t.quad\t_str" + idx.to_string())
        }
      }
    Var(name) =>
      // Function pointer or address of global in initializer
      self.emit("\t.quad\t_" + name)
    Array(nested) =>
      // Nested brace initializer: emit as array/struct
      self.emit_global_array(ty, nested)
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
  exprs : Array[@parser.Expr],
) -> Unit {
  match ty {
    Array(elem_ty, n) => {
      for i = 0; i < exprs.length(); i = i + 1 {
        match exprs[i] {
          Array(nested) => self.emit_global_array(elem_ty, nested)
          _ => self.emit_global_scalar(elem_ty, exprs[i])
        }
      }
      // Pad remaining elements with zeros
      let elem_size = self.type_size(elem_ty)
      let pad_count = n - exprs.length()
      if pad_count > 0 {
        self.emit("\t.space\t" + (pad_count * elem_size).to_string())
      }
    }
    Struct(name) => {
      // Struct initializer: emit each expression with the corresponding field type
      // Use struct layout to insert proper padding between fields
      let layout = if self.struct_layouts.contains(name) {
        self.struct_layouts[name]
      } else {
        []
      }
      let mut emitted = 0
      for i = 0; i < exprs.length() && i < layout.length(); i = i + 1 {
        let field_offset = layout[i].2
        let field_size = layout[i].3
        // Emit padding to reach the correct field offset
        if field_offset > emitted {
          self.emit("\t.space\t" + (field_offset - emitted).to_string())
        }
        self.emit_global_scalar(layout[i].1, exprs[i])
        emitted = field_offset + field_size
      }
      // Pad remaining space with zeros
      let total_size = self.type_size(ty)
      if total_size > emitted {
        self.emit("\t.space\t" + (total_size - emitted).to_string())
      }
    }
    Union(_) => {
      // Union initializer: emit first expression, pad rest
      if exprs.length() > 0 {
        self.emit_global_scalar(SLongLong, exprs[0])
      }
      let total_size = self.type_size(ty)
      if total_size > 8 {
        self.emit("\t.space\t" + (total_size - 8).to_string())
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
  // Register all struct/union declarations first (to handle forward refs)
  for sdecl in prog.structs {
    self.struct_decls[sdecl.name] = sdecl
  }
  // Then compute layouts in a second pass
  for sdecl in prog.structs {
    self.compute_struct_layout(sdecl)
  }
  // Precompute function return types, variadic flags, and param counts
  let mut func_count = 0
  for decl in prog.decls {
    self.func_rets[decl.name] = decl.ret
    self.func_variadic[decl.name] = decl.variadic
    self.func_param_counts[decl.name] = decl.params.length()
    func_count += 1
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
