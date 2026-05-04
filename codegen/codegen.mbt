///|
pub struct Codegen {
  output : StringBuilder
  mut label_counter : Int
  mut local_offsets : Map[String, Int]
  mut var_types : Map[String, @parser.Type]
  mut stack_size : Int
  mut func_name : String
  func_rets : Map[String, @parser.Type]
  func_variadic : Map[String, Bool]
  func_param_counts : Map[String, Int]
  struct_layouts : Map[String, Array[(String, @parser.Type, Int, Int, Int, Int)]]
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
pub fn Codegen::new() -> Codegen {
  {
    output: StringBuilder::new(),
    label_counter: 0,
    local_offsets: {},
    var_types: {},
    stack_size: 0,
    func_name: "",
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
    FloatLiteral(v) => {
      match ty {
        Float => self.emit("\t.single\t" + v.to_string())
        _ => self.emit("\t.double\t" + v.to_string())
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
  // Precompute function return types, variadic flags, and param counts
  for decl in prog.decls {
    self.func_rets[decl.name] = decl.ret
    self.func_variadic[decl.name] = decl.variadic
    self.func_param_counts[decl.name] = decl.params.length()
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
