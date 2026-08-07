///|
fn switch_control_type(ty : @parser.Type) -> @parser.Type {
  match ty {
    Atomic(inner) => switch_control_type(inner)
    Aligned(inner, _) => switch_control_type(inner)
    Bool | SChar | UChar | SShort | UShort => SInt
    _ => ty
  }
}

///|
fn Codegen::emit_switch_case_compare(
  self : Codegen,
  case_value : Int64,
  control_ty : @parser.Type,
) -> Unit {
  match control_ty {
    SInt | UInt => {
      let case32 = case_value & 0xFFFFFFFFL
      self.emit_load_int("x10", case32)
      self.emit("\tcmp\tw9, w10")
    }
    _ =>
      if fits_cmp_imm(case_value) {
        self.emit("\tcmp\tx9, #" + case_value.to_string())
      } else {
        self.emit_load_int("x10", case_value)
        self.emit("\tcmp\tx9, x10")
      }
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
      let ret_ty = self.func_rets[self.func_name]
      match ret_ty {
        Struct(_) | Union(_) if self.is_indirect_aggregate(ret_ty) => {
          self.gen_aggregate_addr(expr, frame_size)
          self.emit("\tstr\tx9, [sp, #-16]!")
          self.emit_load_local("x9", self.sret_dest_offset, frame_size)
          self.emit("\tstr\tx9, [sp, #-16]!")
          self.emit("\tmov\tx0, x9")
          self.emit("\tldr\tx1, [sp, #16]")
          self.emit_load_int("x2", self.type_size(ret_ty).to_int64())
          self.emit("\tbl\t_memcpy")
          self.emit("\tadd\tsp, sp, #32")
        }
        Struct(_) | Union(_) if self.is_register_aggregate(ret_ty) =>
          match expr {
            Call(_, _) => self.gen_expr(expr, frame_size)
            _ => {
              self.gen_aggregate_addr(expr, frame_size)
              self.emit_load_register_aggregate_from_x9(ret_ty)
            }
          }
        _ => {
          self.gen_expr(expr, frame_size)
          self.emit_numeric_conversion(self.type_of(expr, frame_size), ret_ty)
          self.emit_scalar_conversion_to(ret_ty)
          match ret_ty {
            Float => self.emit("\tfmov\ts0, w9")
            Double | LongDouble => self.emit("\tfmov\td0, x9")
            SInt128 | UInt128 => {
              self.emit("\tmov\tx0, x9")
              self.emit("\tmov\tx1, x10")
            }
            _ => self.emit("\tmov\tx0, x9")
          }
        }
      }
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
    Break =>
      match self.break_label {
        Some(label) => self.emit("\tb\t" + label)
        None => abort("break outside of loop or switch")
      }
    Continue =>
      match self.continue_label {
        Some(label) => self.emit("\tb\t" + label)
        None => abort("continue outside of loop")
      }
    Switch(expr, body, cases) => {
      let end_label = self.new_label()
      let old_break = self.break_label
      self.break_label = Some(end_label)
      let control_ty = switch_control_type(self.type_of(expr, frame_size))
      self.gen_expr(expr, frame_size)
      self.emit_scalar_conversion_to(control_ty)
      // Generate comparison and branch for each case
      for c in cases {
        match c.0 {
          Some(n) => {
            self.emit_switch_case_compare(n, control_ty)
            self.emit("\tb.eq\t" + self.label_ref(c.1))
          }
          None => () // default handled after all cases
        }
      }
      // Branch to default or end. The default clause may appear anywhere in
      // source order; fallthrough still follows the emitted case body order.
      let mut default_label = end_label
      for c in cases {
        match c.0 {
          None => {
            default_label = self.label_ref(c.1)
            break
          }
          Some(_) => ()
        }
      }
      self.emit("\tb\t" + default_label)
      self.gen_stmt(body, frame_size)
      self.emit(end_label + ":")
      self.break_label = old_break
    }
    Goto(name) => self.emit("\tb\t" + self.label_ref(name))
    ComputedGoto(expr) => {
      self.gen_expr(expr, frame_size)
      self.emit("\tbr\tx9")
    }
    Label(name, stmt) => {
      let label = self.label_ref(name)
      self.emit(label + ":")
      self.defined_labels[name] = true
      self.gen_stmt(stmt, frame_size)
    }
    VarDecl(ty, name, init) => {
      let offset = self.alloc_local(name, ty)
      match init {
        Some(expr) =>
          match (ty, expr) {
            (Struct(_) | Union(_) | Array(_, _), Number(0, _)) => {
              // Zero-initialize aggregate types properly
              let size = self.type_size(ty)
              self.emit_local_addr(offset, frame_size)
              self.emit("\tmov\tx0, x9")
              self.emit("\tmov\tx1, #0")
              self.emit_load_int("x2", size.to_int64())
              self.emit("\tbl\t_memset")
            }
            (Struct(_) | Union(_) | Array(_, _), rhs) => {
              self.emit_local_addr(offset, frame_size)
              self.emit_init_value_at_addr(ty, rhs, frame_size)
            }
            _ => {
              self.gen_expr(expr, frame_size)
              self.emit_numeric_conversion(self.type_of(expr, frame_size), ty)
              self.emit_scalar_conversion_to(ty)
              match ty {
                Float => self.emit_store_local("w9", offset, frame_size)
                SInt128 | UInt128 => {
                  self.emit("\tstr\tx9, [sp, #-16]!")
                  self.emit("\tstr\tx10, [sp, #8]")
                  self.emit_local_addr(offset, frame_size)
                  self.emit("\tmov\tx11, x9")
                  self.emit("\tldr\tx9, [sp]")
                  self.emit("\tldr\tx10, [sp, #8]")
                  self.emit("\tadd\tsp, sp, #16")
                  self.emit_store_typed("x9", "x11", ty)
                }
                _ => self.emit_store_local("x9", offset, frame_size)
              }
            }
          }
        None => ()
      }
    }
  }
}
