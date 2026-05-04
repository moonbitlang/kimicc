///|
fn Codegen::gen_func(self : Codegen, decl : @parser.FuncDecl) -> Unit {
  match decl.body {
    None => return
    Some(body) => {
      self.local_offsets = {}
      self.var_types = {}
      self.stack_size = 0
      self.emitted_labels = {}
      self.defined_labels = {}
      self.fp_literals = []
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
        if frame_size <= 4095 {
          self.emit("\tsub\tsp, sp, #" + frame_size.to_string())
        } else {
          self.emit_load_int("x16", frame_size.to_int64())
          self.emit("\tsub\tsp, sp, x16")
        }
      }
      // Store params
      let mut int_idx = 0
      let mut fp_idx = 0
      for i = 0; i < decl.params.length(); i = i + 1 {
        let p = decl.params[i]
        let offset = self.local_offsets[p.name]
        match p.ty {
          Float => {
            let reg = "s" + fp_idx.to_string()
            self.emit_store_local(reg, offset, frame_size)
            fp_idx += 1
          }
          Double => {
            let reg = "d" + fp_idx.to_string()
            self.emit_store_local(reg, offset, frame_size)
            fp_idx += 1
          }
          _ => {
            let reg = "x" + int_idx.to_string()
            self.emit_store_local(reg, offset, frame_size)
            int_idx += 1
          }
        }
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
      match decl.ret {
        Float => self.emit("\tfmov\ts0, wzr")
        Double => self.emit("\tfmov\td0, xzr")
        _ => self.emit("\tmov\tx0, #0")
      }
      self.emit("_" + decl.name + "_ret:")
      // Restore SP from x29 to support __builtin_alloca
      self.emit("\tmov\tsp, x29")
      // Emit any referenced-but-not-defined labels to satisfy assembler
      for name, label in self.emitted_labels {
        if not(self.defined_labels.contains(name)) {
          self.emit(label + ":")
          self.emit("\tb\t_" + self.func_name + "_ret")
        }
      }
      self.emit("\tldp\tx29, x30, [sp], #16")
      self.emit("\tret")
      // Emit floating-point literal pool for this function
      if self.fp_literals.length() > 0 {
        self.emit("\t.section\t__TEXT,__literal8,8byte_literals")
        self.emit("\t.p2align\t3")
        for i = 0; i < self.fp_literals.length(); i = i + 1 {
          let label = "_fp_lit_" + self.func_name + "_" + i.to_string()
          self.emit(label + ":")
          self.emit("\t.double\t" + self.fp_literals[i].to_string())
        }
        self.emit("\t.section\t__TEXT,__text,regular,pure_instructions")
      }
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
