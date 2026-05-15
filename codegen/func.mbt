///|
fn Codegen::gen_func(self : Codegen, decl : @parser.FuncDecl) -> Unit {
  match decl.body {
    None => return
    Some(body) => {
      if self.try_gen_mir_func(decl) {
        return
      }
      self.local_offsets = {}
      self.var_types = {}
      self.stack_size = 0
      self.emitted_labels = {}
      self.defined_labels = {}
      self.fp_literals = []
      self.func_name = decl.name
      self.func_params = decl.params
      self.sret_dest_offset = -1
      self.sret_scratch_offset = -1
      self.sret_scratch_size = 0
      self.pending_sret_offset = -1
      // Allocate space for params
      let param_offsets : Map[String, Int] = {}
      let param_types : Map[String, @parser.Type] = {}
      let mut param_stack_end = 0
      if self.is_indirect_aggregate(decl.ret) {
        self.sret_dest_offset = self.alloc_local(
          "__kimicc_sret_dest",
          Pointer(Void),
        )
        param_stack_end = self.sret_dest_offset + 8
      }
      for i = 0; i < decl.params.length(); i = i + 1 {
        let p = decl.params[i]
        let offset = self.alloc_local(p.name, p.ty)
        param_offsets[p.name] = offset
        param_types[p.name] = p.ty
        let param_size = (self.type_size(p.ty) + 7) / 8 * 8
        let param_end = offset + param_size
        if param_end > param_stack_end {
          param_stack_end = param_end
        }
      }
      // Collect locals and compute offsets
      self.collect_locals(body)
      if self.sret_scratch_size > 0 {
        self.sret_scratch_offset = self.alloc_local(
          "__kimicc_sret_scratch",
          Array(UChar, self.sret_scratch_size),
        )
      }
      let frame_size = (self.stack_size + 15) / 16 * 16
      if !decl.is_static && !decl.is_inline {
        if decl.is_weak {
          self.emit("\t.weak_definition\t_" + decl.name)
        } else {
          self.emit("\t.globl\t_" + decl.name)
        }
      }
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
      if self.sret_dest_offset >= 0 {
        self.emit_store_local("x8", self.sret_dest_offset, frame_size)
      }
      // Store params
      // AAPCS64: args 1-8 in x0-x7 (or v0-v7 for FP), args 9+ on stack
      let mut int_idx = 0
      let mut fp_idx = 0
      for i = 0; i < decl.params.length(); i = i + 1 {
        let p = decl.params[i]
        let offset = param_offsets[p.name]
        match p.ty {
          Float => {
            if fp_idx < 8 {
              let reg = "s" + fp_idx.to_string()
              self.emit_store_local(reg, offset, frame_size)
            } else {
              let stack_off = 16 + (fp_idx - 8) * 8
              self.emit("\tldr\ts9, [x29, #" + stack_off.to_string() + "]")
              self.emit_store_local("s9", offset, frame_size)
            }
            fp_idx += 1
          }
          Double | LongDouble => {
            if fp_idx < 8 {
              let reg = "d" + fp_idx.to_string()
              self.emit_store_local(reg, offset, frame_size)
            } else {
              let stack_off = 16 + (fp_idx - 8) * 8
              self.emit("\tldr\td9, [x29, #" + stack_off.to_string() + "]")
              self.emit_store_local("d9", offset, frame_size)
            }
            fp_idx += 1
          }
          SInt128 | UInt128 => {
            if int_idx < 7 {
              self.emit_store_local(
                "x" + int_idx.to_string(),
                offset,
                frame_size,
              )
              self.emit_store_local(
                "x" + (int_idx + 1).to_string(),
                offset + 8,
                frame_size,
              )
            } else if int_idx == 7 {
              self.emit_store_local("x7", offset, frame_size)
              self.emit("\tldr\tx9, [x29, #16]")
              self.emit_store_local("x9", offset + 8, frame_size)
            } else {
              let stack_off = 16 + (int_idx - 8) * 8
              self.emit("\tldr\tx9, [x29, #" + stack_off.to_string() + "]")
              self.emit_store_local("x9", offset, frame_size)
              self.emit(
                "\tldr\tx9, [x29, #" + (stack_off + 8).to_string() + "]",
              )
              self.emit_store_local("x9", offset + 8, frame_size)
            }
            int_idx += 2
          }
          Struct(_) | Union(_) => {
            let size = self.type_size(p.ty)
            if size > 16 {
              if int_idx < 8 {
                let reg = "x" + int_idx.to_string()
                self.emit_copy_indirect_param_to_local(
                  reg, offset, size, frame_size,
                )
              } else {
                let stack_off = 16 + (int_idx - 8) * 8
                self.emit("\tldr\tx11, [x29, #" + stack_off.to_string() + "]")
                self.emit_copy_indirect_param_to_local(
                  "x11", offset, size, frame_size,
                )
              }
              int_idx += 1
            } else if size > 8 {
              // Composite type passed in two consecutive X registers or on stack
              if int_idx < 7 {
                self.emit_store_local(
                  "x" + int_idx.to_string(),
                  offset,
                  frame_size,
                )
                self.emit_store_local(
                  "x" + (int_idx + 1).to_string(),
                  offset + 8,
                  frame_size,
                )
              } else if int_idx == 7 {
                self.emit_store_local("x7", offset, frame_size)
                self.emit("\tldr\tx9, [x29, #16]")
                self.emit_store_local("x9", offset + 8, frame_size)
              } else {
                let stack_off = 16 + (int_idx - 8) * 8
                self.emit("\tldr\tx9, [x29, #" + stack_off.to_string() + "]")
                self.emit_store_local("x9", offset, frame_size)
                self.emit(
                  "\tldr\tx9, [x29, #" + (stack_off + 8).to_string() + "]",
                )
                self.emit_store_local("x9", offset + 8, frame_size)
              }
              int_idx += 2
            } else {
              if int_idx < 8 {
                let reg = "x" + int_idx.to_string()
                self.emit_store_local(reg, offset, frame_size)
              } else {
                let stack_off = 16 + (int_idx - 8) * 8
                self.emit("\tldr\tx9, [x29, #" + stack_off.to_string() + "]")
                self.emit_store_local("x9", offset, frame_size)
              }
              int_idx += 1
            }
          }
          _ => {
            if int_idx < 8 {
              let reg = "x" + int_idx.to_string()
              self.emit_store_local(reg, offset, frame_size)
            } else {
              let stack_off = 16 + (int_idx - 8) * 8
              self.emit("\tldr\tx9, [x29, #" + stack_off.to_string() + "]")
              self.emit_store_local("x9", offset, frame_size)
            }
            int_idx += 1
          }
        }
      }
      // Reset local state so gen_stmt allocates locals fresh
      self.local_offsets = param_offsets
      self.var_types = param_types
      self.stack_size = param_stack_end
      self.gen_stmt(body, frame_size)
      // Default return
      match decl.ret {
        Float => self.emit("\tfmov\ts0, wzr")
        Double | LongDouble => self.emit("\tfmov\td0, xzr")
        SInt128 | UInt128 => {
          self.emit("\tmov\tx0, #0")
          self.emit("\tmov\tx1, #0")
        }
        _ => self.emit("\tmov\tx0, #0")
      }
      self.emit("_" + decl.name + "_ret:")
      // Restore SP from x29 to support __builtin_alloca
      self.emit("\tmov\tsp, x29")
      // Emit any referenced-but-not-defined labels to satisfy assembler
      for name, label in self.emitted_labels {
        if !self.defined_labels.contains(name) {
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
fn Codegen::emit_copy_indirect_param_to_local(
  self : Codegen,
  src_reg : String,
  offset : Int,
  size : Int,
  frame_size : Int,
) -> Unit {
  self.emit("\tmov\tx10, " + src_reg)
  self.emit_local_addr(offset, frame_size)
  let mut pos = 0
  while pos + 8 <= size {
    let suffix = if pos == 0 { "" } else { ", #" + pos.to_string() }
    self.emit("\tldr\tx12, [x10" + suffix + "]")
    self.emit("\tstr\tx12, [x9" + suffix + "]")
    pos += 8
  }
  if pos + 4 <= size {
    let suffix = if pos == 0 { "" } else { ", #" + pos.to_string() }
    self.emit("\tldr\tw12, [x10" + suffix + "]")
    self.emit("\tstr\tw12, [x9" + suffix + "]")
    pos += 4
  }
  if pos + 2 <= size {
    let suffix = if pos == 0 { "" } else { ", #" + pos.to_string() }
    self.emit("\tldrh\tw12, [x10" + suffix + "]")
    self.emit("\tstrh\tw12, [x9" + suffix + "]")
    pos += 2
  }
  if pos < size {
    let suffix = if pos == 0 { "" } else { ", #" + pos.to_string() }
    self.emit("\tldrb\tw12, [x10" + suffix + "]")
    self.emit("\tstrb\tw12, [x9" + suffix + "]")
  }
}

///|
fn Codegen::emit_load_local(
  self : Codegen,
  dst_reg : String,
  offset : Int,
  frame_size : Int,
) -> Unit {
  let off = offset - frame_size
  if off >= -256 && off <= 255 {
    self.emit("\tldr\t" + dst_reg + ", [x29, #" + off.to_string() + "]")
  } else {
    self.emit("\tmov\tx12, #" + off.to_string())
    self.emit("\tldr\t" + dst_reg + ", [x29, x12]")
  }
}

///|
fn Codegen::emit_store_local(
  self : Codegen,
  src_reg : String,
  offset : Int,
  frame_size : Int,
) -> Unit {
  let off = offset - frame_size
  if off >= -256 && off <= 255 {
    self.emit("\tstr\t" + src_reg + ", [x29, #" + off.to_string() + "]")
  } else {
    self.emit("\tmov\tx12, #" + off.to_string())
    self.emit("\tstr\t" + src_reg + ", [x29, x12]")
  }
}

///|
fn Codegen::emit_local_addr(
  self : Codegen,
  offset : Int,
  frame_size : Int,
) -> Unit {
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
  let natural_align = self.type_align(ty)
  let align = if natural_align > 8 { natural_align } else { 8 }
  let padding = (align - self.stack_size % align) % align
  self.stack_size += padding
  let aligned_size = (size + align - 1) / align * align
  let offset = self.stack_size
  self.stack_size += aligned_size
  self.local_offsets[name] = offset
  self.var_types[name] = ty
  offset
}

///|
fn compound_literal_local_name(id : Int) -> String {
  "__kimicc_compound_literal_" + id.to_string()
}

///|
fn Codegen::collect_expr_locals(self : Codegen, expr : @parser.Expr) -> Unit {
  match expr {
    Binary(_, lhs, rhs) | Assign(lhs, rhs) | CompoundAssign(_, lhs, rhs) => {
      self.collect_expr_locals(lhs)
      self.collect_expr_locals(rhs)
    }
    Unary(_, e)
    | Deref(e)
    | AddrOf(e)
    | SizeofExpr(e)
    | AlignofExpr(e)
    | Cast(_, e)
    | PrefixInc(e)
    | PrefixDec(e)
    | PostfixInc(e)
    | PostfixDec(e)
    | DesignatedField(_, e) => self.collect_expr_locals(e)
    Call(func, args) => {
      let ret_ty = self.call_return_type(func, args, 0)
      if self.is_indirect_aggregate(ret_ty) {
        let size = self.type_size(ret_ty)
        if size > self.sret_scratch_size {
          self.sret_scratch_size = size
        }
      }
      self.collect_expr_locals(func)
      for arg in args {
        self.collect_expr_locals(arg)
      }
    }
    MemberAccess(obj, _) => self.collect_expr_locals(obj)
    ArrayAccess(arr, index) => {
      self.collect_expr_locals(arr)
      self.collect_expr_locals(index)
    }
    Ternary(cond, then_expr, else_expr) => {
      self.collect_expr_locals(cond)
      self.collect_expr_locals(then_expr)
      self.collect_expr_locals(else_expr)
    }
    VaArg(ap, _) => self.collect_expr_locals(ap)
    Array(exprs) =>
      for e in exprs {
        self.collect_expr_locals(e)
      }
    CompoundLiteral(ty, exprs, id) => {
      let _ = self.alloc_local(compound_literal_local_name(id), ty)
      for e in exprs {
        self.collect_expr_locals(e)
      }
    }
    _ => ()
  }
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
    ExprStmt(expr) => self.collect_expr_locals(expr)
    Return(expr) =>
      match expr {
        Some(e) => self.collect_expr_locals(e)
        None => ()
      }
    If(cond, then_, else_) => {
      self.collect_expr_locals(cond)
      self.collect_locals(then_)
      match else_ {
        Some(e) => self.collect_locals(e)
        None => ()
      }
    }
    While(cond, body) => {
      self.collect_expr_locals(cond)
      self.collect_locals(body)
    }
    For(init, cond, update, body) => {
      match init {
        Some(i) => self.collect_locals(i)
        None => ()
      }
      self.collect_expr_locals(cond)
      match update {
        Some(e) => self.collect_expr_locals(e)
        None => ()
      }
      self.collect_locals(body)
    }
    DoWhile(cond, body) => {
      self.collect_expr_locals(cond)
      self.collect_locals(body)
    }
    Switch(expr, body, _) => {
      self.collect_expr_locals(expr)
      self.collect_locals(body)
    }
    Label(_, s) => self.collect_locals(s)
    VarDecl(ty, name, init) => {
      let _ = self.alloc_local(name, ty)
      match init {
        Some(e) => self.collect_expr_locals(e)
        None => ()
      }
    }
    ComputedGoto(expr) => self.collect_expr_locals(expr)
    _ => ()
  }
}
