///|
fn Codegen::type_of(
  self : Codegen,
  expr : @parser.Expr,
  frame_size : Int,
) -> @parser.Type {
  match expr {
    Number(_) => SInt
    FloatLiteral(_) => Double
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
    "__builtin_alloca" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        // Round up to 16-byte alignment: size = (size + 15) & ~15
        self.emit("\tadd\tx9, x9, #15")
        self.emit("\tbic\tx9, x9, #0xF")
        self.emit("\tsub\tsp, sp, x9")
      }
      self.emit("\tmov\tx9, sp")
      true
    }
    "__builtin_constant_p" => {
      // Always report non-constant (safe fallback)
      self.emit("\tmov\tx9, #0")
      true
    }
    "__builtin_object_size" => {
      // Return -1 (unknown size) cast to size_t
      self.emit("\tmov\tx9, #-1")
      true
    }
    // Fortified function stubs: fall back to unchecked versions
    "__builtin___memcpy_chk" => {
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
    "__builtin___memset_chk" => {
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
    "__builtin___memmove_chk" => {
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
    "__builtin___strcpy_chk" => {
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
    "__builtin___strcat_chk" => {
      if args.length() >= 2 {
        for i = 0; i < 2; i = i + 1 {
          self.gen_expr(args[i], frame_size)
          self.emit("\tmov\tx" + i.to_string() + ", x9")
        }
        self.emit("\tbl\t_strcat")
      }
      self.emit("\tmov\tx9, x0")
      true
    }
    "__builtin_fabs" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tfmov\td9, x9")
        self.emit("\tfabs\td9, d9")
        self.emit("\tfmov\tx9, d9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_fabsf" => {
      if args.length() > 0 {
        self.gen_expr(args[0], frame_size)
        self.emit("\tfmov\ts9, w9")
        self.emit("\tfabs\ts9, s9")
        self.emit("\tfmov\tw9, s9")
      } else {
        self.emit("\tmov\tx9, #0")
      }
      true
    }
    "__builtin_nan" | "__builtin_nanf" => {
      // Ignore string argument, return canonical NaN
      if name == "__builtin_nanf" {
        // float NaN: 0x7FC00000
        self.emit("\tmovz\tw9, #0x7FC0, lsl #16")
      } else {
        // double NaN: 0x7FF8000000000000
        self.emit("\tmovz\tx9, #0")
        self.emit("\tmovk\tx9, #0, lsl #16")
        self.emit("\tmovk\tx9, #0xF800, lsl #32")
        self.emit("\tmovk\tx9, #0x7FF8, lsl #48")
      }
      true
    }
    "__builtin_huge_val" | "__builtin_inf" => {
      // double +inf: 0x7FF0000000000000
      self.emit("\tmovz\tx9, #0")
      self.emit("\tmovk\tx9, #0, lsl #16")
      self.emit("\tmovk\tx9, #0, lsl #32")
      self.emit("\tmovk\tx9, #0x7FF0, lsl #48")
      true
    }
    "__builtin_huge_valf" | "__builtin_inff" => {
      // float +inf: 0x7F800000
      self.emit("\tmovz\tw9, #0x7F80, lsl #16")
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
    FloatLiteral(v) => {
      let idx = self.fp_literals.length()
      self.fp_literals.push(v)
      let label = "_fp_lit_" + self.func_name + "_" + idx.to_string()
      self.emit("\tadrp\tx9, " + label + "@PAGE")
      self.emit("\tadd\tx9, x9, " + label + "@PAGEOFF")
      self.emit("\tldr\tx9, [x9]")
    }
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
      let is_ptr_op = ptr_scale > 1 || is_ptr_diff
      let is_fp = not(is_ptr_op) &&
        (left_ty.is_floating() || right_ty.is_floating())
      let is_double = is_fp && (left_ty == Double || right_ty == Double)
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
        "+" => {
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfadd\td9, d9, d10")
              self.emit("\tfmov\tx9, d9")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfadd\ts9, s9, s10")
              self.emit("\tfmov\tw9, s9")
            }
          } else {
            self.emit("\tadd\tx9, x9, x10")
          }
        }
        "-" => {
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfsub\td9, d9, d10")
              self.emit("\tfmov\tx9, d9")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfsub\ts9, s9, s10")
              self.emit("\tfmov\tw9, s9")
            }
          } else {
            self.emit("\tsub\tx9, x9, x10")
            if is_ptr_diff && ptr_scale > 1 {
              self.emit("\tmov\tx11, #" + ptr_scale.to_string())
              self.emit("\tsdiv\tx9, x9, x11")
            }
          }
        }
        "*" => {
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfmul\td9, d9, d10")
              self.emit("\tfmov\tx9, d9")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfmul\ts9, s9, s10")
              self.emit("\tfmov\tw9, s9")
            }
          } else {
            self.emit("\tmul\tx9, x9, x10")
          }
        }
        "/" => {
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfdiv\td9, d9, d10")
              self.emit("\tfmov\tx9, d9")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfdiv\ts9, s9, s10")
              self.emit("\tfmov\tw9, s9")
            }
          } else {
            self.emit("\tsdiv\tx9, x9, x10")
          }
        }
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
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfcmp\td9, d10")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfcmp\ts9, s10")
            }
            self.emit("\tcset\tx9, eq")
          } else {
            self.emit("\tcmp\tx9, x10")
            self.emit("\tcset\tx9, eq")
          }
        }
        "!=" => {
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfcmp\td9, d10")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfcmp\ts9, s10")
            }
            self.emit("\tcset\tx9, ne")
          } else {
            self.emit("\tcmp\tx9, x10")
            self.emit("\tcset\tx9, ne")
          }
        }
        "<" => {
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfcmp\td9, d10")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfcmp\ts9, s10")
            }
            self.emit("\tcset\tx9, mi")
          } else {
            self.emit("\tcmp\tx9, x10")
            self.emit("\tcset\tx9, lt")
          }
        }
        "<=" => {
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfcmp\td9, d10")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfcmp\ts9, s10")
            }
            self.emit("\tcset\tx9, ls")
          } else {
            self.emit("\tcmp\tx9, x10")
            self.emit("\tcset\tx9, le")
          }
        }
        ">" => {
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfcmp\td9, d10")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfcmp\ts9, s10")
            }
            self.emit("\tcset\tx9, gt")
          } else {
            self.emit("\tcmp\tx9, x10")
            self.emit("\tcset\tx9, gt")
          }
        }
        ">=" => {
          if is_fp {
            if is_double {
              self.emit("\tfmov\td9, x9")
              self.emit("\tfmov\td10, x10")
              self.emit("\tfcmp\td9, d10")
            } else {
              self.emit("\tfmov\ts9, w9")
              self.emit("\tfmov\ts10, w10")
              self.emit("\tfcmp\ts9, s10")
            }
            self.emit("\tcset\tx9, ge")
          } else {
            self.emit("\tcmp\tx9, x10")
            self.emit("\tcset\tx9, ge")
          }
        }
        _ => {
          println("WARN: Unknown binary operator: " + op)
        }
      }
    }
    Unary("-", operand) => {
      self.gen_expr(operand, frame_size)
      let op_ty = self.type_of(operand, frame_size)
      if op_ty.is_floating() {
        if op_ty == Double {
          self.emit("\tfmov\td9, x9")
          self.emit("\tfneg\td9, d9")
          self.emit("\tfmov\tx9, d9")
        } else {
          self.emit("\tfmov\ts9, w9")
          self.emit("\tfneg\ts9, s9")
          self.emit("\tfmov\tw9, s9")
        }
      } else {
        self.emit("\tneg\tx9, x9")
      }
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
        // Check if callee is variadic
        let named_count = match func {
          Var(name) => {
            if self.func_param_counts.contains(name) {
              self.func_param_counts[name]
            } else {
              // Known external variadic functions
              match name {
                "printf" | "vprintf" | "scanf" | "fscanf" | "sscanf" => 1
                "fprintf" | "vfprintf" | "sprintf" | "vsprintf" => 2
                "snprintf" | "vsnprintf" => 3
                "___snprintf_chk" => 5
                "open" | "fcntl" | "ioctl" => 2
                _ => 0
              }
            }
          }
          _ => 0
        }
        let is_variadic = match func {
          Var(name) => {
            if self.func_variadic.get_or_default(name, false) {
              true
            } else {
              // Known external variadic functions
              match name {
                "printf" | "vprintf" | "fprintf" | "vfprintf" | "sprintf" |
                "vsprintf" | "snprintf" | "vsnprintf" | "scanf" | "fscanf" |
                "sscanf" | "___snprintf_chk" | "open" | "fcntl" | "ioctl" => true
                _ => false
              }
            }
          }
          _ => false
        }
        if is_variadic {
          // Variadic calls: named args in registers, variadic args on stack
          let mut int_idx = 0
          let mut fp_idx = 0
          // Evaluate named args into correct registers
          for i = 0; i < named_count && i < args.length(); i = i + 1 {
            self.gen_expr(args[i], frame_size)
            let arg_ty = self.type_of(args[i], frame_size)
            match arg_ty {
              Float => {
                let reg = "s" + fp_idx.to_string()
                self.emit("\tfmov\t" + reg + ", w9")
                fp_idx += 1
              }
              Double => {
                let reg = "d" + fp_idx.to_string()
                self.emit("\tfmov\t" + reg + ", x9")
                fp_idx += 1
              }
              _ => {
                let reg = "x" + int_idx.to_string()
                self.emit("\tmov\t" + reg + ", x9")
                int_idx += 1
              }
            }
          }
          // Evaluate variadic args and save to stack
          let variadic_count = if args.length() > named_count {
            args.length() - named_count
          } else {
            0
          }
          let mut save_size = 0
          if variadic_count > 0 {
            save_size = ((variadic_count * 8 + 15) / 16) * 16
            self.emit("\tsub\tsp, sp, #" + save_size.to_string())
            for i = 0; i < variadic_count; i = i + 1 {
              let arg_idx = named_count + i
              self.gen_expr(args[arg_idx], frame_size)
              let offset = i * 8
              if offset == 0 {
                self.emit("\tstr\tx9, [sp]")
              } else {
                self.emit("\tstr\tx9, [sp, #" + offset.to_string() + "]")
              }
            }
          }
          match func {
            Var(name) => {
              if self.local_offsets.contains(name) || self.globals.contains(name) {
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
          if save_size > 0 {
            self.emit("\tadd\tsp, sp, #" + save_size.to_string())
          }
          self.emit("\tmov\tx9, x0")
        } else {
          // Non-variadic calls: use correct register classes for int/FP args
          // First pass: count stack args
          let mut int_idx = 0
          let mut fp_idx = 0
          let mut stack_count = 0
          for i = 0; i < args.length(); i = i + 1 {
            let arg_ty = self.type_of(args[i], frame_size)
            match arg_ty {
              Float | Double => {
                if fp_idx >= 8 { stack_count += 1 }
                fp_idx += 1
              }
              _ => {
                if int_idx >= 8 { stack_count += 1 }
                int_idx += 1
              }
            }
          }
          let stack_arg_size = stack_count * 8
          if stack_arg_size > 0 {
            self.emit("\tsub\tsp, sp, #" + stack_arg_size.to_string())
          }
          // Second pass: evaluate and place args
          int_idx = 0
          fp_idx = 0
          let mut stack_idx = 0
          for i = 0; i < args.length(); i = i + 1 {
            self.gen_expr(args[i], frame_size)
            let arg_ty = self.type_of(args[i], frame_size)
            match arg_ty {
              Float => {
                if fp_idx < 8 {
                  let reg = "s" + fp_idx.to_string()
                  self.emit("\tfmov\t" + reg + ", w9")
                } else {
                  let offset = stack_idx * 8
                  if offset == 0 {
                    self.emit("\tstr\tw9, [sp]")
                  } else {
                    self.emit("\tstr\tw9, [sp, #" + offset.to_string() + "]")
                  }
                  stack_idx += 1
                }
                fp_idx += 1
              }
              Double => {
                if fp_idx < 8 {
                  let reg = "d" + fp_idx.to_string()
                  self.emit("\tfmov\t" + reg + ", x9")
                } else {
                  let offset = stack_idx * 8
                  if offset == 0 {
                    self.emit("\tstr\tx9, [sp]")
                  } else {
                    self.emit("\tstr\tx9, [sp, #" + offset.to_string() + "]")
                  }
                  stack_idx += 1
                }
                fp_idx += 1
              }
              _ => {
                if int_idx < 8 {
                  let reg = "x" + int_idx.to_string()
                  self.emit("\tmov\t" + reg + ", x9")
                } else {
                  let offset = stack_idx * 8
                  if offset == 0 {
                    self.emit("\tstr\tx9, [sp]")
                  } else {
                    self.emit("\tstr\tx9, [sp, #" + offset.to_string() + "]")
                  }
                  stack_idx += 1
                }
                int_idx += 1
              }
            }
          }
          match func {
            Var(name) => {
              if self.local_offsets.contains(name) || self.globals.contains(name) {
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
          if stack_arg_size > 0 {
            self.emit("\tadd\tsp, sp, #" + stack_arg_size.to_string())
          }
          // Move return value to x9 (raw bits for FP)
          let ret_ty = match func {
            Var(name) => self.func_rets.get_or_default(name, SInt)
            _ => SInt
          }
          match ret_ty {
            Float => self.emit("\tfmov\tw9, s0")
            Double => self.emit("\tfmov\tx9, d0")
            _ => self.emit("\tmov\tx9, x0")
          }
        }
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
      let expr_ty = self.type_of(expr, frame_size)
      // Handle FP conversions before integer truncation
      match (expr_ty, ty) {
        // Integer to Double
        (src, Double) => {
          if src.is_integer() {
            self.emit("\tscvtf\td9, x9")
            self.emit("\tfmov\tx9, d9")
          } else if src == Float {
            self.emit("\tfmov\ts9, w9")
            self.emit("\tfcvt\td9, s9")
            self.emit("\tfmov\tx9, d9")
          }
        }
        // Integer to Float
        (src, Float) => {
          if src.is_integer() {
            self.emit("\tscvtf\ts9, x9")
            self.emit("\tfmov\tw9, s9")
          } else if src == Double {
            self.emit("\tfmov\td9, x9")
            self.emit("\tfcvt\ts9, d9")
            self.emit("\tfmov\tw9, s9")
          }
        }
        // Double/Float to integer
        (Double, dst) => {
          if dst.is_integer() {
            self.emit("\tfmov\td9, x9")
            if dst.is_signed() {
              self.emit("\tfcvtzs\tx9, d9")
            } else {
              self.emit("\tfcvtzu\tx9, d9")
            }
          }
        }
        (Float, dst) => {
          if dst.is_integer() {
            self.emit("\tfmov\ts9, w9")
            if dst.is_signed() {
              self.emit("\tfcvtzs\tx9, s9")
            } else {
              self.emit("\tfcvtzu\tx9, s9")
            }
          }
        }
        _ => ()
      }
      // Integer truncation/sign-extension
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
          // pointer, struct, array, void, long, long long, bool: no-op
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
