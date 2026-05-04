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
  mut break_label : String?
  mut continue_label : String?
  globals : Map[String, @parser.Type]
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
    self.globals[g.1] = g.0
  }
  for decl in prog.decls {
    self.gen_func(decl)
  }
  // Emit uninitialized global variables
  if self.globals.length() > 0 {
    self.emit("	.section	__DATA,__bss")
    for name, ty in self.globals {
      let size = self.type_size(ty)
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
            self.emit("\tcmp\tx9, #" + n.to_string())
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
      self.emit("\tb\t_" + self.func_name + "_label_" + name)
    }
    Label(name, stmt) => {
      self.emit("_" + self.func_name + "_label_" + name + ":")
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
    Number(_) => Int
    String(_) => Pointer(Char)
    Var(name) => {
      if self.var_types.contains(name) {
        self.var_types[name]
      } else if self.globals.contains(name) {
        self.globals[name]
      } else if self.func_rets.contains(name) {
        Pointer(Void) // Function pointer type
      } else {
        println("WARN: Unknown variable type: " + name)
        Int
      }
    }
    Binary(_, _, _) => Int
    Unary("-", _) => Int
    Unary("!", _) => Int
    Unary("~", _) => Int
    Call(func, _) => match func {
      Var(name) => self.func_rets[name]
      _ => Int
    }
    Assign(_, rhs) => self.type_of(rhs, frame_size)
    MemberAccess(obj, field) => {
      let obj_ty = self.type_of(obj, frame_size)
      let struct_name = match obj_ty {
        Struct(n) => n
        _ => {
          println("WARN: Member access on non-struct type: " + obj_ty.to_string())
          return Int
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
      Int
    }
    Deref(ptr) =>
      match self.type_of(ptr, frame_size) {
        Pointer(ty) => ty
        Array(elem, _) => elem
        _ => {
          println("WARN: Deref of non-pointer")
          Int
        }
      }
    AddrOf(e) => Pointer(self.type_of(e, frame_size))
    ArrayAccess(arr, _) =>
      match self.type_of(arr, frame_size) {
        Array(elem, _) => elem
        Pointer(elem) => elem
        _ => {
          println("WARN: Array access on non-array")
          Int
        }
      }
    Sizeof(_) => Int
    SizeofExpr(_) => Int
    PrefixInc(e) => self.type_of(e, frame_size)
    PrefixDec(e) => self.type_of(e, frame_size)
    PostfixInc(e) => self.type_of(e, frame_size)
    PostfixDec(e) => self.type_of(e, frame_size)
    Ternary(_, then_, _) => self.type_of(then_, frame_size)
    // CommaExpr is not in the AST, comma expressions are flattened into nested Binary(",", ...)
    Cast(ty, _) => ty
    _ => {
      println("WARN: Unknown expression type")
      Int
    }
  }
}

///|
fn Codegen::gen_expr(
  self : Codegen,
  expr : @parser.Expr,
  frame_size : Int,
) -> Unit {
  match expr {
    Number(n) => self.emit("\tldr\tx9, =" + n.to_string())
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
          Array(_, _) | Struct(_) =>
            self.emit_local_addr(offset, frame_size)
          _ => self.emit_load_local("x9", offset, frame_size)
        }
      } else if self.globals.contains(name) {
        let ty = self.globals[name]
        self.emit("\tadrp\tx9, _" + name + "@PAGE")
        self.emit("\tadd\tx9, x9, _" + name + "@PAGEOFF")
        match ty {
          Array(_, _) | Struct(_) => ()
          _ => self.emit("\tldr\tx9, [x9]")
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
      for i = 0; i < args.length(); i = i + 1 {
        self.gen_expr(args[i], frame_size)
        let reg = "x" + i.to_string()
        self.emit("\tmov\t" + reg + ", x9")
      }
      match func {
        Var(name) => {
          self.emit("\tbl\t_" + name)
        }
        _ => {
          self.gen_expr(func, frame_size)
          self.emit("\tmov\tx15, x9")
          self.emit("\tblr\tx15")
        }
      }
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
      self.emit("\tldr\tx9, =" + size.to_string())
    }
    SizeofExpr(expr) => {
      let ty = self.type_of(expr, frame_size)
      let size = self.type_size(ty)
      self.emit("\tldr\tx9, =" + size.to_string())
    }
    Cast(ty, expr) => {
      self.gen_expr(expr, frame_size)
      match ty {
        Char => {
          // Truncate to 8 bits and sign-extend
          self.emit("\tsxtb\tx9, w9")
        }
        _ => {
          // int, pointer, struct, array, void: no-op
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
      self.emit("\tldr\tx10, [x9]")
      self.emit("\tadd\tx11, x10, #1")
      self.emit("\tstr\tx11, [x9]")
      self.emit("\tmov\tx9, x11")
    }
    PrefixDec(expr) => {
      self.gen_addr(expr, frame_size)
      self.emit("\tldr\tx10, [x9]")
      self.emit("\tsub\tx11, x10, #1")
      self.emit("\tstr\tx11, [x9]")
      self.emit("\tmov\tx9, x11")
    }
    PostfixInc(expr) => {
      self.gen_addr(expr, frame_size)
      self.emit("\tldr\tx10, [x9]")
      self.emit("\tadd\tx11, x10, #1")
      self.emit("\tstr\tx11, [x9]")
      self.emit("\tmov\tx9, x10")
    }
    PostfixDec(expr) => {
      self.gen_addr(expr, frame_size)
      self.emit("\tldr\tx10, [x9]")
      self.emit("\tsub\tx11, x10, #1")
      self.emit("\tstr\tx11, [x9]")
      self.emit("\tmov\tx9, x10")
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
    _ => {
      println("WARN: Cannot take address of expression")
    }
  }
}
