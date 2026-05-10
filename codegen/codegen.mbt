///|
/// Darwin ARM64 assembly generator for a parsed C program.
///
/// Construct with `Codegen::new`. The fields are exposed by the current
/// MoonBit API surface, but callers should treat them as implementation
/// details and use `generate` as the stable entry point.
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
  func_param_types : Map[String, Array[@parser.Type]]
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
  mut sret_dest_offset : Int
  mut sret_scratch_offset : Int
  mut sret_scratch_size : Int
  mut pending_sret_offset : Int
}

///|
fn octal_digit_char(d : Int) -> Char {
  match d {
    0 => '0'
    1 => '1'
    2 => '2'
    3 => '3'
    4 => '4'
    5 => '5'
    6 => '6'
    _ => '7'
  }
}

///|
fn write_octal_escape(buf : StringBuilder, value : Int) -> Unit {
  let byte = value % 256
  buf.write_char('\\')
  buf.write_char(octal_digit_char(byte / 64))
  buf.write_char(octal_digit_char(byte / 8 % 8))
  buf.write_char(octal_digit_char(byte % 8))
}

///|
fn escape_string(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    let value = ch.to_int()
    if value < 0x20 || value >= 0x7f || ch == '\\' || ch == '"' {
      write_octal_escape(buf, value)
    } else {
      buf.write_char(ch)
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
fn global_has_init(g : @parser.GlobalDecl) -> Bool {
  match g.init {
    Some(_) => true
    None => false
  }
}

///|
fn should_replace_global_decl(
  old : @parser.GlobalDecl,
  next : @parser.GlobalDecl,
) -> Bool {
  if next.is_extern && !global_has_init(next) {
    false
  } else if !global_has_init(old) && global_has_init(next) {
    true
  } else if old.is_extern && !next.is_extern {
    true
  } else if global_has_init(old) && !global_has_init(next) {
    false
  } else {
    global_has_init(next)
  }
}

///|
fn merge_global_decls(
  globals : Array[@parser.GlobalDecl],
) -> Array[@parser.GlobalDecl] {
  let merged : Array[@parser.GlobalDecl] = []
  for g in globals {
    let mut found = -1
    for i = 0; i < merged.length(); i = i + 1 {
      if merged[i].name == g.name {
        found = i
      }
    }
    if found < 0 {
      merged.push(g)
    } else if should_replace_global_decl(merged[found], g) {
      merged[found] = g
    }
  }
  merged
}

///|
fn mark_static_inline_needed(
  name : String,
  inline_decls : Map[String, @parser.FuncDecl],
  needed : Map[String, Bool],
) -> Unit {
  if needed.contains(name) || !inline_decls.contains(name) {
    return
  }
  needed[name] = true
  match inline_decls[name].body {
    Some(body) => collect_static_inline_stmt(body, inline_decls, needed)
    None => ()
  }
}

///|
fn collect_static_inline_expr(
  expr : @parser.Expr,
  inline_decls : Map[String, @parser.FuncDecl],
  needed : Map[String, Bool],
) -> Unit {
  match expr {
    Var(name) => mark_static_inline_needed(name, inline_decls, needed)
    Number(_)
    | FloatLiteral(_)
    | String(_)
    | Sizeof(_)
    | LabelAddr(_)
    | OffsetOf(_, _) => ()
    Binary(_, left, right)
    | Assign(left, right)
    | CompoundAssign(_, left, right)
    | ArrayAccess(left, right) => {
      collect_static_inline_expr(left, inline_decls, needed)
      collect_static_inline_expr(right, inline_decls, needed)
    }
    Unary(_, inner)
    | Deref(inner)
    | SizeofExpr(inner)
    | Cast(_, inner)
    | PrefixInc(inner)
    | PrefixDec(inner)
    | PostfixInc(inner)
    | PostfixDec(inner)
    | VaArg(inner, _)
    | DesignatedField(_, inner)
    | DesignatedIndex(_, inner)
    | DesignatedRange(_, _, inner) =>
      collect_static_inline_expr(inner, inline_decls, needed)
    MemberAccess(obj, _) =>
      collect_static_inline_expr(obj, inline_decls, needed)
    AddrOf(inner) => {
      match inner {
        Var(name) => mark_static_inline_needed(name, inline_decls, needed)
        _ => ()
      }
      collect_static_inline_expr(inner, inline_decls, needed)
    }
    Call(callee, args) => {
      match callee {
        Var(name) => mark_static_inline_needed(name, inline_decls, needed)
        _ => ()
      }
      collect_static_inline_expr(callee, inline_decls, needed)
      for arg in args {
        collect_static_inline_expr(arg, inline_decls, needed)
      }
    }
    Ternary(cond, yes, no) => {
      collect_static_inline_expr(cond, inline_decls, needed)
      collect_static_inline_expr(yes, inline_decls, needed)
      collect_static_inline_expr(no, inline_decls, needed)
    }
    Array(items) | CompoundLiteral(_, items, _) =>
      for item in items {
        collect_static_inline_expr(item, inline_decls, needed)
      }
  }
}

///|
fn collect_static_inline_stmt(
  stmt : @parser.Stmt,
  inline_decls : Map[String, @parser.FuncDecl],
  needed : Map[String, Bool],
) -> Unit {
  match stmt {
    ExprStmt(expr) | ComputedGoto(expr) =>
      collect_static_inline_expr(expr, inline_decls, needed)
    Return(expr) =>
      match expr {
        Some(value) => collect_static_inline_expr(value, inline_decls, needed)
        None => ()
      }
    If(cond, then_, else_) => {
      collect_static_inline_expr(cond, inline_decls, needed)
      collect_static_inline_stmt(then_, inline_decls, needed)
      match else_ {
        Some(stmt) => collect_static_inline_stmt(stmt, inline_decls, needed)
        None => ()
      }
    }
    While(cond, body) | DoWhile(cond, body) => {
      collect_static_inline_expr(cond, inline_decls, needed)
      collect_static_inline_stmt(body, inline_decls, needed)
    }
    Compound(stmts) | StmtList(stmts) =>
      for child in stmts {
        collect_static_inline_stmt(child, inline_decls, needed)
      }
    VarDecl(_, _, init) =>
      match init {
        Some(expr) => collect_static_inline_expr(expr, inline_decls, needed)
        None => ()
      }
    Switch(expr, body, _) => {
      collect_static_inline_expr(expr, inline_decls, needed)
      collect_static_inline_stmt(body, inline_decls, needed)
    }
    Label(_, body) => collect_static_inline_stmt(body, inline_decls, needed)
    For(init, cond, update, body) => {
      match init {
        Some(stmt) => collect_static_inline_stmt(stmt, inline_decls, needed)
        None => ()
      }
      collect_static_inline_expr(cond, inline_decls, needed)
      match update {
        Some(expr) => collect_static_inline_expr(expr, inline_decls, needed)
        None => ()
      }
      collect_static_inline_stmt(body, inline_decls, needed)
    }
    Break | Continue | Goto(_) => ()
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
    String(s) => Array(SChar, s.length() + 1)
    CompoundLiteral(ty, _, _) => ty
    DesignatedField(_, e) => self.global_expr_type(e)
    DesignatedIndex(_, e) => self.global_expr_type(e)
    DesignatedRange(_, _, e) => self.global_expr_type(e)
    Cast(ty, _) => ty
    AddrOf(e) => Pointer(self.global_expr_type(e))
    ArrayAccess(base, _) =>
      match peel_aligned_type(self.global_expr_type(base)) {
        Array(elem, _) | Pointer(elem) => elem
        _ => SInt
      }
    MemberAccess(obj, field) =>
      match peel_aligned_type(self.global_expr_type(obj)) {
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
fn Codegen::fold_const(self : Codegen, expr : @parser.Expr) -> Int64? {
  match expr {
    Number(n) => Some(n)
    Binary("+", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(x + y)
        _ => None
      }
    Binary("-", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(x - y)
        _ => None
      }
    Binary("*", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(x * y)
        _ => None
      }
    Binary("/", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(_), Some(0L)) => None
        (Some(x), Some(y)) => Some(x / y)
        _ => None
      }
    Binary("%", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(_), Some(0L)) => None
        (Some(x), Some(y)) => Some(x % y)
        _ => None
      }
    Binary("|", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(x | y)
        _ => None
      }
    Binary("&", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(x & y)
        _ => None
      }
    Binary("^", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(x ^ y)
        _ => None
      }
    Binary("<<", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(x << y.to_int())
        _ => None
      }
    Binary(">>", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(x >> y.to_int())
        _ => None
      }
    Binary("==", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(if x == y { 1L } else { 0L })
        _ => None
      }
    Binary("!=", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(if x != y { 1L } else { 0L })
        _ => None
      }
    Binary("<", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(if x < y { 1L } else { 0L })
        _ => None
      }
    Binary(">", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(if x > y { 1L } else { 0L })
        _ => None
      }
    Binary("<=", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(if x <= y { 1L } else { 0L })
        _ => None
      }
    Binary(">=", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(if x >= y { 1L } else { 0L })
        _ => None
      }
    Binary("&&", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(if x != 0L && y != 0L { 1L } else { 0L })
        _ => None
      }
    Binary("||", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => Some(if x != 0L || y != 0L { 1L } else { 0L })
        _ => None
      }
    Ternary(cond, a, b) =>
      match self.fold_const(cond) {
        Some(0L) => self.fold_const(b)
        Some(_) => self.fold_const(a)
        None => None
      }
    Unary("-", e) =>
      match self.fold_const(e) {
        Some(x) => Some(-x)
        _ => None
      }
    Unary("~", e) =>
      match self.fold_const(e) {
        Some(x) => Some(x.lnot())
        _ => None
      }
    Unary("!", e) =>
      match self.fold_const(e) {
        Some(0L) => Some(1L)
        Some(_) => Some(0L)
        _ => None
      }
    Cast(_, e) => self.fold_const(e)
    DesignatedField(_, e) => self.fold_const(e)
    DesignatedIndex(_, e) => self.fold_const(e)
    DesignatedRange(_, _, e) => self.fold_const(e)
    Sizeof(ty) => Some(self.type_size(ty).to_int64())
    SizeofExpr(e) => Some(self.type_size(self.global_expr_type(e)).to_int64())
    OffsetOf(ty, field) =>
      match ty {
        Struct(name) | Union(name) =>
          match self.find_field_layout(name, field) {
            Some((_, _, offset, _, _, _)) => Some(offset.to_int64())
            None => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn Codegen::fold_float_const(self : Codegen, expr : @parser.Expr) -> Double? {
  match expr {
    FloatLiteral(v) => Some(v)
    Number(n) => Some(n.to_double())
    Binary("+", a, b) =>
      match (self.fold_float_const(a), self.fold_float_const(b)) {
        (Some(x), Some(y)) => Some(x + y)
        _ => None
      }
    Binary("-", a, b) =>
      match (self.fold_float_const(a), self.fold_float_const(b)) {
        (Some(x), Some(y)) => Some(x - y)
        _ => None
      }
    Binary("*", a, b) =>
      match (self.fold_float_const(a), self.fold_float_const(b)) {
        (Some(x), Some(y)) => Some(x * y)
        _ => None
      }
    Binary("/", a, b) =>
      match (self.fold_float_const(a), self.fold_float_const(b)) {
        (Some(x), Some(y)) => Some(x / y)
        _ => None
      }
    Unary("-", e) =>
      match self.fold_float_const(e) {
        Some(x) => Some(-x)
        None => None
      }
    Unary("+", e) => self.fold_float_const(e)
    Ternary(cond, a, b) =>
      match self.fold_const(cond) {
        Some(0L) => self.fold_float_const(b)
        Some(_) => self.fold_float_const(a)
        None => None
      }
    Cast(_, e) => self.fold_float_const(e)
    DesignatedField(_, e) => self.fold_float_const(e)
    DesignatedIndex(_, e) => self.fold_float_const(e)
    DesignatedRange(_, _, e) => self.fold_float_const(e)
    Call(Var(name), _) =>
      match name {
        "__builtin_nan" | "__builtin_nanf" | "__builtin_nanl" => Some(0.0 / 0.0)
        "__builtin_huge_val"
        | "__builtin_huge_valf"
        | "__builtin_huge_vall"
        | "__builtin_inf"
        | "__builtin_inff"
        | "__builtin_infl" => Some(1.0 / 0.0)
        _ => None
      }
    _ => None
  }
}

///|
fn Codegen::emit_global_float(
  self : Codegen,
  ty : @parser.Type,
  v : Double,
) -> Unit {
  match ty {
    Float => self.emit("\t.single\t" + v.to_string())
    _ => self.emit("\t.double\t" + v.to_string())
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
          let elem_size = match peel_aligned_type(self.global_expr_type(base)) {
            Array(elem, _) | Pointer(elem) => self.type_size(elem)
            _ => 1
          }
          match self.fold_const(index) {
            Some(i) => Some((label, base_offset + i.to_int() * elem_size))
            None => None
          }
        }
        None => None
      }
    MemberAccess(obj, field) =>
      match self.global_lvalue_reloc(obj) {
        Some((label, base_offset)) =>
          match peel_aligned_type(self.global_expr_type(obj)) {
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
    LabelAddr(name) => Some(self.label_ref(name))
    Var(name) => Some("_" + name)
    Binary("+", base, offset_expr) =>
      match (self.global_address_reloc(base), self.fold_const(offset_expr)) {
        (Some(label), Some(offset)) =>
          Some(reloc_with_offset(label, offset.to_int()))
        _ =>
          match
            (self.global_address_reloc(offset_expr), self.fold_const(base)) {
            (Some(label), Some(offset)) =>
              Some(reloc_with_offset(label, offset.to_int()))
            _ => None
          }
      }
    Binary("-", base, offset_expr) =>
      match (self.global_address_reloc(base), self.fold_const(offset_expr)) {
        (Some(label), Some(offset)) =>
          Some(reloc_with_offset(label, -offset.to_int()))
        _ => None
      }
    _ => None
  }
}

///|
/// Creates a fresh code generator with empty per-program state.
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
    func_param_types: {},
    struct_layouts: {},
    struct_decls: {},
    strings: [],
    break_label: None,
    continue_label: None,
    globals: {},
    emitted_labels: {},
    defined_labels: {},
    fp_literals: [],
    sret_dest_offset: -1,
    sret_scratch_offset: -1,
    sret_scratch_size: 0,
    pending_sret_offset: -1,
  }
}

///|
fn Codegen::emit_global_scalar(
  self : Codegen,
  ty : @parser.Type,
  expr : @parser.Expr,
) -> Unit {
  match ty {
    Aligned(inner, _) => {
      self.emit_global_scalar(inner, expr)
      return
    }
    _ => ()
  }
  match ty {
    Pointer(_) | FuncPtr(_, _, _) =>
      match self.global_address_reloc(expr) {
        Some(reloc) => {
          self.emit("\t.quad\t" + reloc)
          return
        }
        None => ()
      }
    _ => ()
  }
  match ty {
    Float | Double =>
      match self.fold_float_const(expr) {
        Some(v) => {
          self.emit_global_float(ty, v)
          return
        }
        None => ()
      }
    _ => ()
  }
  // Try constant-fold the expression first
  let folded_expr = match self.fold_const(expr) {
    Some(n) => @parser.Expr::Number(n)
    None => expr
  }
  match folded_expr {
    Number(n) =>
      match ty {
        Bool | SChar | UChar => self.emit("\t.byte\t" + n.to_string())
        SShort | UShort => self.emit("\t.short\t" + n.to_string())
        SInt | UInt => self.emit("\t.long\t" + n.to_string())
        Float | Double => self.emit_global_float(ty, n.to_double())
        Struct(_) | Union(_) | Array(_, _) => {
          // Zero-initialize aggregate type
          let size = self.type_size(ty)
          self.emit("\t.space\t" + size.to_string())
        }
        _ => self.emit("\t.quad\t" + n.to_string())
      }
    FloatLiteral(v) => self.emit_global_float(ty, v)
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
    Cast(_, e) => self.emit_global_scalar(ty, e)
    DesignatedField(_, e) => self.emit_global_scalar(ty, e)
    DesignatedIndex(_, e) => self.emit_global_scalar(ty, e)
    DesignatedRange(_, _, e) => self.emit_global_scalar(ty, e)
    CompoundLiteral(_, exprs, _) => self.emit_global_array(ty, exprs)
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
fn find_designated_initializer(
  exprs : Array[@parser.Expr],
  field_name : String,
) -> @parser.Expr? {
  for expr in exprs {
    match expr {
      DesignatedField(name, _) if name == field_name => return Some(expr)
      _ => ()
    }
  }
  None
}

///|
fn Codegen::emit_global_array(
  self : Codegen,
  ty : @parser.Type,
  exprs : Array[@parser.Expr],
) -> Unit {
  match ty {
    Aligned(inner, _) => self.emit_global_array(inner, exprs)
    Array(elem_ty, n) => {
      let elem_size = self.type_size(elem_ty)
      let slots : Array[@parser.Expr?] = Array::make(n, None)
      let mut cursor = 0
      for expr in exprs {
        let mut start = cursor
        let mut end = cursor
        let value = match expr {
          DesignatedIndex(index, e) => {
            start = index.to_int()
            end = start
            cursor = start + 1
            e
          }
          DesignatedRange(first, last, e) => {
            start = first.to_int()
            end = last.to_int()
            cursor = end + 1
            e
          }
          _ => {
            cursor += 1
            expr
          }
        }
        for i = start; i <= end; i = i + 1 {
          if i >= 0 && i < n {
            slots[i] = Some(value)
          }
        }
      }
      for slot in slots {
        match slot {
          Some(Array(nested)) => self.emit_global_array(elem_ty, nested)
          Some(value) => self.emit_global_scalar(elem_ty, value)
          None => self.emit("\t.space\t" + elem_size.to_string())
        }
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
      let mut positional = 0
      for field in layout {
        let field_name = field.0
        let field_ty = field.1
        let field_offset = field.2
        let field_size = field.3
        let bit_width = field.5
        let init_expr = match find_designated_initializer(exprs, field_name) {
          Some(expr) => Some(expr)
          None => {
            while positional < exprs.length() &&
                  exprs[positional] is DesignatedField(_, _) {
              positional = positional + 1
            }
            if positional < exprs.length() {
              let expr = exprs[positional]
              positional = positional + 1
              Some(expr)
            } else {
              None
            }
          }
        }
        match init_expr {
          Some(expr) =>
            if bit_width == 0 {
              // Emit padding to reach the correct field offset
              if field_offset > emitted {
                self.emit("\t.space\t" + (field_offset - emitted).to_string())
              }
              self.emit_global_scalar(field_ty, expr)
              emitted = field_offset + field_size
            }
          None => ()
        }
      }
      // Pad remaining space with zeros
      let total_size = self.type_size(ty)
      if total_size > emitted {
        self.emit("\t.space\t" + (total_size - emitted).to_string())
      }
    }
    Union(name) => {
      let layout = if self.struct_layouts.contains(name) {
        self.struct_layouts[name]
      } else {
        []
      }
      let mut emitted = 0
      if exprs.length() > 0 {
        let init_expr = exprs[0]
        let field = match init_expr {
          DesignatedField(field_name, _) =>
            self.find_field_layout(name, field_name)
          _ => if layout.length() > 0 { Some(layout[0]) } else { None }
        }
        match field {
          Some((_, field_ty, field_offset, field_size, _, bit_width)) =>
            if bit_width == 0 {
              if field_offset > 0 {
                self.emit("\t.space\t" + field_offset.to_string())
              }
              self.emit_global_scalar(field_ty, init_expr)
              emitted = field_offset + field_size
            }
          None => ()
        }
      }
      let total_size = self.type_size(ty)
      if total_size > emitted {
        self.emit("\t.space\t" + (total_size - emitted).to_string())
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
fn global_align_power(align : Int) -> Int {
  let mut power = 0
  let mut bytes = 1
  while bytes < align {
    bytes = bytes * 2
    power = power + 1
  }
  power
}

///|
fn Codegen::emit_global_p2align(self : Codegen, ty : @parser.Type) -> Unit {
  let align = self.type_align(ty)
  let effective_align = if align > 8 { align } else { 8 }
  self.emit("\t.p2align\t" + global_align_power(effective_align).to_string())
}

///|
/// Generates Darwin ARM64 assembly for a parsed C translation unit.
///
/// The input must come from `bobzhang/kimicc/parser`. The returned string is
/// assembly text intended for the macOS assembler and linker.
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
  let inline_decls : Map[String, @parser.FuncDecl] = {}
  for decl in prog.decls {
    self.func_rets[decl.name] = decl.ret
    self.func_variadic[decl.name] = decl.variadic
    self.func_param_counts[decl.name] = decl.params.length()
    let param_types = []
    for param in decl.params {
      param_types.push(param.ty)
    }
    self.func_param_types[decl.name] = param_types
    if decl.is_inline {
      inline_decls[decl.name] = decl
    }
  }
  let needed_inline : Map[String, Bool] = {}
  for decl in prog.decls {
    if !decl.is_inline {
      match decl.body {
        Some(body) =>
          collect_static_inline_stmt(body, inline_decls, needed_inline)
        None => ()
      }
    }
  }
  let globals = merge_global_decls(prog.globals)
  // Record global variables
  for g in globals {
    self.globals[g.name] = g
  }
  let func_label_maps : Map[String, Map[String, String]] = {}
  for decl in prog.decls {
    if decl.is_inline && !needed_inline.contains(decl.name) {
      continue
    }
    self.gen_func(decl)
    func_label_maps[decl.name] = self.emitted_labels
  }
  // Emit initialized global variables
  let mut has_data = false
  for g in globals {
    if g.init is Some(_) {
      if !has_data {
        self.emit("	.section	__DATA,__data")
        has_data = true
      }
      if !g.is_static {
        self.emit("	.globl	_" + g.name)
      }
      self.emit_global_p2align(g.ty)
      self.emit("_" + g.name + ":")
      let saved_func_name = self.func_name
      let saved_emitted_labels = self.emitted_labels
      match static_global_owner_name(g.name, prog.decls) {
        Some(owner) => {
          self.func_name = owner
          match func_label_maps.get(owner) {
            Some(labels) => self.emitted_labels = labels
            None => ()
          }
        }
        None => ()
      }
      match g.init {
        Some(Scalar(expr)) => self.emit_global_scalar(g.ty, expr)
        Some(Array(exprs)) => self.emit_global_array(g.ty, exprs)
        None => ()
      }
      self.func_name = saved_func_name
      self.emitted_labels = saved_emitted_labels
    }
  }
  // Emit uninitialized global variables
  let mut has_bss = false
  for g in globals {
    if g.init is None && !g.is_extern {
      if !has_bss {
        self.emit("	.section	__DATA,__bss")
        has_bss = true
      }
      let size = self.type_size(g.ty)
      if !g.is_static {
        self.emit("	.globl	_" + g.name)
      }
      self.emit_global_p2align(g.ty)
      self.emit("_" + g.name + ":")
      self.emit("	.space	" + size.to_string())
    }
  }
  // Emit string literals
  if self.strings.length() > 0 {
    self.emit("	.section	__TEXT,__const")
    for i = 0; i < self.strings.length(); i = i + 1 {
      self.emit("_str" + i.to_string() + ":")
      self.emit("	.asciz	\"" + escape_string(self.strings[i]) + "\"")
    }
  }
  self.output.to_string()
}

///|
/// Generates assembly for `prog` using the requested target backend.
///
/// `DarwinArm64` preserves the existing macOS ARM64 assembly output.
/// `LinuxAmd64` emits GNU assembler syntax for the System V x86-64 ABI.
pub fn generate_assembly_for_target(
  prog : @parser.Program,
  target : @target.Target,
) -> String {
  match target {
    DarwinArm64 => Codegen::new().generate(prog)
    LinuxAmd64 => X64Codegen::new().generate(prog)
  }
}

///|
fn static_global_owner_name(
  name : String,
  decls : Array[@parser.FuncDecl],
) -> String? {
  let mut owner : String? = None
  let mut owner_prefix_len = 0
  for decl in decls {
    let prefix = "_" + decl.name + "_"
    if name.has_prefix(prefix) && prefix.length() > owner_prefix_len {
      owner = Some(decl.name)
      owner_prefix_len = prefix.length()
    }
  }
  owner
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
