///|
pub struct Codegen {
  output : StringBuilder
  mut label_counter : Int
  mut local_offsets : Map[String, Int]
  mut var_types : Map[String, @parser.Type]
  mut stack_size : Int
  mut func_name : String
  func_rets : Map[String, @parser.Type]
  struct_layouts : Map[String, Array[(String, @parser.Type, Int, Int)]]
  struct_decls : Map[String, @parser.StructDecl]
  strings : Array[String]
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
  for decl in prog.decls {
    self.gen_func(decl)
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
fn Codegen::type_size(self : Codegen, ty : @parser.Type) -> Int {
  match ty {
    Int => 8
    Void => 0
    Char => 1
    Pointer(_) => 8
    Array(elem, n) => self.type_size(elem) * n
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
      let mut total = 0
      for field in fields {
        total += field.3
      }
      total
    }
  }
}

///|
fn Codegen::compute_struct_layout(
  self : Codegen,
  decl : @parser.StructDecl,
) -> Unit {
  let mut offset = 0
  let layout = []
  for field in decl.fields {
    let size = self.type_size(field.ty)
    layout.push((field.name, field.ty, offset, size))
    offset += size
  }
  self.struct_layouts[decl.name] = layout
}

///|
fn Codegen::gen_func(self : Codegen, decl : @parser.FuncDecl) -> Unit {
  match decl.body {
    None => return
    Some(body) => {
      self.local_offsets = {}
      self.var_types = {}
      self.stack_size = 0
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
  if self.local_offsets.contains(name) {
    return self.local_offsets[name]
  }
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
    If(_, then_, else_) => {
      self.collect_locals(then_)
      match else_ {
        Some(e) => self.collect_locals(e)
        None => ()
      }
    }
    While(_, body) => self.collect_locals(body)
    VarDecl(ty, name, _) => {
      let _ = self.alloc_local(name, ty)
    }
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
    Compound(stmts) =>
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
      self.emit(start_label + ":")
      self.gen_expr(cond, frame_size)
      self.emit("\tcbz\tx9, " + end_label)
      self.gen_stmt(body, frame_size)
      self.emit("\tb\t" + start_label)
      self.emit(end_label + ":")
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
    Number(_) => Int
    Var(name) => self.var_types[name]
    Binary(_, _, _) => Int
    Unary("-", _) => Int
    Call(name, _) => self.func_rets[name]
    Assign(_, rhs) => self.type_of(rhs, frame_size)
    MemberAccess(obj, field) => {
      let obj_ty = self.type_of(obj, frame_size)
      let struct_name = match obj_ty {
        Struct(n) => n
        _ => abort("Member access on non-struct")
      }
      let fields = self.struct_layouts[struct_name]
      for f in fields {
        if f.0 == field {
          return f.1
        }
      }
      abort("Unknown field: " + field)
    }
    Deref(ptr) =>
      match self.type_of(ptr, frame_size) {
        Pointer(ty) => ty
        Array(elem, _) => elem
        _ => abort("Deref of non-pointer")
      }
    AddrOf(e) => Pointer(self.type_of(e, frame_size))
    ArrayAccess(arr, _) =>
      match self.type_of(arr, frame_size) {
        Array(elem, _) => elem
        Pointer(elem) => elem
        _ => abort("Array access on non-array")
      }
    Sizeof(_) => Int
    _ => abort("Unknown expression type")
  }
}

///|
fn Codegen::gen_expr(
  self : Codegen,
  expr : @parser.Expr,
  frame_size : Int,
) -> Unit {
  match expr {
    Number(n) => self.emit("\tmov\tx9, #" + n.to_string())
    String(s) => {
      let idx = self.strings.length()
      self.strings.push(s)
      let label = "_str" + idx.to_string()
      self.emit("\tadrp\tx9, " + label + "@PAGE")
      self.emit("\tadd\tx9, x9, " + label + "@PAGEOFF")
    }
    Var(name) => {
      let ty = self.var_types[name]
      let offset = self.local_offsets[name]
      match ty {
        Array(_, _) | Struct(_) =>
          self.emit_local_addr(offset, frame_size)
        _ => self.emit_load_local("x9", offset, frame_size)
      }
    }
    Assign(lhs, rhs) => {
      self.gen_expr(rhs, frame_size)
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.gen_addr(lhs, frame_size)
      self.emit("\tmov\tx10, x9")
      self.emit("\tldr\tx9, [sp], #16")
      self.emit("\tstr\tx9, [x10]")
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
      self.gen_expr(left, frame_size)
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.gen_expr(right, frame_size)
      self.emit("\tmov\tx10, x9")
      self.emit("\tldr\tx9, [sp], #16")
      match op {
        "+" => self.emit("\tadd\tx9, x9, x10")
        "-" => self.emit("\tsub\tx9, x9, x10")
        "*" => self.emit("\tmul\tx9, x9, x10")
        "/" => self.emit("\tsdiv\tx9, x9, x10")
        "%" => self.emit("\tsdiv\tx11, x9, x10\n\tmsub\tx9, x11, x10, x9")
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
        _ => abort("Unknown binary operator: " + op)
      }
    }
    Unary("-", operand) => {
      self.gen_expr(operand, frame_size)
      self.emit("\tneg\tx9, x9")
    }
    Call(name, args) => {
      for i = 0; i < args.length(); i = i + 1 {
        self.gen_expr(args[i], frame_size)
        let reg = "x" + i.to_string()
        self.emit("\tmov\t" + reg + ", x9")
      }
      self.emit("\tbl\t_" + name)
      self.emit("\tmov\tx9, x0")
    }
    MemberAccess(_, _) => {
      self.gen_addr(expr, frame_size)
      self.emit("\tldr\tx9, [x9]")
    }
    Deref(ptr) => {
      self.gen_expr(ptr, frame_size)
      self.emit("\tldr\tx9, [x9]")
    }
    AddrOf(e) => self.gen_addr(e, frame_size)
    ArrayAccess(_, _) => {
      self.gen_addr(expr, frame_size)
      self.emit("\tldr\tx9, [x9]")
    }
    Sizeof(ty) => {
      let size = self.type_size(ty)
      self.emit("\tmov\tx9, #" + size.to_string())
    }
    _ => abort("Unknown expression")
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
      let offset = self.local_offsets[name]
      self.emit_local_addr(offset, frame_size)
    }
    MemberAccess(obj, field) => {
      self.gen_addr(obj, frame_size)
      let obj_ty = self.type_of(obj, frame_size)
      let struct_name = match obj_ty {
        Struct(n) => n
        _ => abort("Member access on non-struct")
      }
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
    Deref(ptr) => self.gen_expr(ptr, frame_size)
    AddrOf(e) => self.gen_addr(e, frame_size)
    ArrayAccess(arr, index) => {
      self.gen_expr(arr, frame_size)
      self.emit("\tstr\tx9, [sp, #-16]!")
      self.gen_expr(index, frame_size)
      self.emit("\tmov\tx12, x9")
      self.emit("\tldr\tx9, [sp], #16")
      let elem_ty = self.type_of(expr, frame_size)
      let elem_size = self.type_size(elem_ty)
      self.emit("\tmov\tx11, #" + elem_size.to_string())
      self.emit("\tmadd\tx9, x12, x11, x9")
    }
    _ => abort("Cannot take address of expression")
  }
}
