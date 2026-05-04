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
      let ret_ty = self.func_rets[self.func_name]
      match ret_ty {
        Float => self.emit("\tfmov\ts0, w9")
        Double => self.emit("\tfmov\td0, x9")
        _ => self.emit("\tmov\tx0, x9")
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
      let label = self.label_ref(name)
      self.emit(label + ":")
      self.defined_labels[name] = true
      self.gen_stmt(stmt, frame_size)
    }
    VarDecl(ty, name, init) => {
      let offset = self.alloc_local(name, ty)
      match init {
        Some(expr) => {
          self.gen_expr(expr, frame_size)
          match ty {
            Float => self.emit_store_local("w9", offset, frame_size)
            _ => self.emit_store_local("x9", offset, frame_size)
          }
        }
        None => ()
      }
    }
  }
}
