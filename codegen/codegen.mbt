///|
/// Darwin ARM64 assembly generator for a parsed C program.
///
/// Construct with `Codegen::new`. The fields are exposed by the current
/// MoonBit API surface, but callers should treat them as implementation
/// details and use `generate` as the stable entry point.
pub struct Codegen {
  output : StringBuilder
  mut mir : @mir.Program?
  mut mir_module : @mir.MirModule?
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
  globals : Map[String, @mir.MirGlobalDecl]
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
fn merge_global_visibility(
  primary : @parser.GlobalDecl,
  other : @parser.GlobalDecl,
) -> String? {
  match primary.visibility {
    Some(_) => primary.visibility
    None => other.visibility
  }
}

///|
fn merge_global_alias(
  primary : @parser.GlobalDecl,
  other : @parser.GlobalDecl,
) -> String? {
  match primary.symbol_alias {
    Some(_) => primary.symbol_alias
    None => other.symbol_alias
  }
}

///|
fn merge_global_section(
  primary : @parser.GlobalDecl,
  other : @parser.GlobalDecl,
) -> String? {
  match primary.section {
    Some(_) => primary.section
    None => other.section
  }
}

///|
fn with_merged_global_attrs(
  primary : @parser.GlobalDecl,
  other : @parser.GlobalDecl,
) -> @parser.GlobalDecl {
  {
    ty: primary.ty,
    name: primary.name,
    init: primary.init,
    is_static: primary.is_static,
    is_extern: primary.is_extern,
    is_weak: primary.is_weak || other.is_weak,
    visibility: merge_global_visibility(primary, other),
    symbol_alias: merge_global_alias(primary, other),
    section: merge_global_section(primary, other),
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
      merged[found] = with_merged_global_attrs(g, merged[found])
    } else {
      merged[found] = with_merged_global_attrs(merged[found], g)
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
    | Alignof(_)
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
    | AlignofExpr(inner)
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
  match self.mir_module {
    Some(mir) => return mir.global_expr_type(expr)
    None =>
      match self.mir {
        Some(mir) => return mir.global_expr_type(expr)
        None => ()
      }
  }
  match expr {
    Number(value) => number_literal_type(value)
    FloatLiteral(_) => Double
    Var(name) =>
      if self.globals.contains(name) {
        self.globals[name].ty
      } else if self.func_rets.contains(name) {
        FuncPtr(
          self.func_rets[name],
          self.func_param_types.get_or_default(name, []),
          self.func_variadic.get_or_default(name, false),
        )
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
    Deref(e) =>
      match peel_aligned_type(self.global_expr_type(e)) {
        Pointer(elem) | Array(elem, _) => elem
        _ => SInt
      }
    ArrayAccess(base, _) =>
      match peel_aligned_type(self.global_expr_type(base)) {
        Array(elem, _) | Pointer(elem) => elem
        _ => SInt
      }
    MemberAccess(obj, field) => {
      let obj_ty = self.global_expr_type(obj)
      match self.find_field_layout_for_type(obj_ty, field) {
        Some((_, ty, _, _, _, _)) => ty
        None => SInt
      }
    }
    _ => SInt
  }
}

///|
priv struct DarwinConstIntValue {
  bits : Int64
  ty : @parser.Type
}

///|
fn darwin_const_core_type(ty : @parser.Type) -> @parser.Type {
  match ty {
    Atomic(inner) | Aligned(inner, _) => darwin_const_core_type(inner)
    _ => ty
  }
}

///|
fn darwin_const_int(bits : Int64, ty : @parser.Type) -> DarwinConstIntValue {
  { bits, ty: darwin_const_core_type(ty) }
}

///|
fn darwin_const_bool(value : Bool) -> DarwinConstIntValue {
  { bits: if value { 1L } else { 0L }, ty: SInt }
}

///|
fn darwin_const_type_is_unsigned(ty : @parser.Type) -> Bool {
  match darwin_const_core_type(ty) {
    Bool | UChar | UShort | UInt | ULong | ULongLong | UInt128 => true
    _ => false
  }
}

///|
fn darwin_const_type_int_width(ty : @parser.Type) -> Int? {
  match darwin_const_core_type(ty) {
    Bool => Some(1)
    SChar | UChar => Some(8)
    SShort | UShort => Some(16)
    SInt | UInt => Some(32)
    SLong | ULong | SLongLong | ULongLong | Pointer(_) | FuncPtr(_, _, _) =>
      Some(64)
    SInt128 | UInt128 => Some(128)
    _ => None
  }
}

///|
fn darwin_const_type_is_integer(ty : @parser.Type) -> Bool {
  match darwin_const_core_type(ty) {
    Bool
    | SChar
    | UChar
    | SShort
    | UShort
    | SInt
    | UInt
    | SLong
    | ULong
    | SLongLong
    | ULongLong
    | SInt128
    | UInt128 => true
    _ => false
  }
}

///|
fn darwin_const_integer_promote(ty : @parser.Type) -> @parser.Type {
  match darwin_const_core_type(ty) {
    Bool | SChar | UChar | SShort | UShort => SInt
    other => other
  }
}

///|
fn darwin_const_unsigned_type_for_rank(rank : Int) -> @parser.Type {
  if rank >= 6 {
    UInt128
  } else if rank == 5 {
    ULongLong
  } else if rank == 4 {
    ULong
  } else {
    UInt
  }
}

///|
fn darwin_const_signed_type_for_rank(rank : Int) -> @parser.Type {
  if rank >= 6 {
    SInt128
  } else if rank == 5 {
    SLongLong
  } else if rank == 4 {
    SLong
  } else {
    SInt
  }
}

///|
fn darwin_const_integer_common_type(
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
) -> @parser.Type {
  let lhs_ty = darwin_const_integer_promote(lhs_ty)
  let rhs_ty = darwin_const_integer_promote(rhs_ty)
  if lhs_ty == rhs_ty {
    return lhs_ty
  }
  if !darwin_const_type_is_integer(lhs_ty) ||
    !darwin_const_type_is_integer(rhs_ty) {
    return lhs_ty
  }
  let lhs_unsigned = darwin_const_type_is_unsigned(lhs_ty)
  let rhs_unsigned = darwin_const_type_is_unsigned(rhs_ty)
  let lhs_rank = integer_rank(lhs_ty)
  let rhs_rank = integer_rank(rhs_ty)
  if lhs_unsigned == rhs_unsigned {
    let rank = if lhs_rank > rhs_rank { lhs_rank } else { rhs_rank }
    if lhs_unsigned {
      darwin_const_unsigned_type_for_rank(rank)
    } else {
      darwin_const_signed_type_for_rank(rank)
    }
  } else {
    let unsigned_ty = if lhs_unsigned { lhs_ty } else { rhs_ty }
    let signed_ty = if lhs_unsigned { rhs_ty } else { lhs_ty }
    let unsigned_rank = integer_rank(unsigned_ty)
    let signed_rank = integer_rank(signed_ty)
    let unsigned_width = darwin_const_type_int_width(unsigned_ty).unwrap_or(0)
    let signed_width = darwin_const_type_int_width(signed_ty).unwrap_or(0)
    if unsigned_rank >= signed_rank {
      unsigned_ty
    } else if signed_width > unsigned_width {
      signed_ty
    } else {
      darwin_const_unsigned_type_for_rank(signed_rank)
    }
  }
}

///|
fn darwin_const_cast_int(
  value : DarwinConstIntValue,
  ty : @parser.Type,
) -> DarwinConstIntValue {
  let core_ty = darwin_const_core_type(ty)
  let unsigned = darwin_const_type_is_unsigned(core_ty)
  match darwin_const_type_int_width(core_ty) {
    None => darwin_const_int(value.bits, core_ty)
    Some(1) => darwin_const_int(if value.bits == 0L { 0L } else { 1L }, core_ty)
    Some(width) =>
      if width >= 64 {
        darwin_const_int(value.bits, core_ty)
      } else {
        let mask = (1L << width) - 1L
        let bits = value.bits & mask
        if unsigned {
          darwin_const_int(bits, core_ty)
        } else {
          let sign = 1L << (width - 1)
          if (bits & sign) != 0L {
            darwin_const_int(bits | mask.lnot(), core_ty)
          } else {
            darwin_const_int(bits, core_ty)
          }
        }
      }
  }
}

///|
fn darwin_const_apply_binary_type(
  left : DarwinConstIntValue,
  right : DarwinConstIntValue,
) -> (DarwinConstIntValue, DarwinConstIntValue, @parser.Type) {
  let ty = darwin_const_integer_common_type(left.ty, right.ty)
  (darwin_const_cast_int(left, ty), darwin_const_cast_int(right, ty), ty)
}

///|
fn darwin_const_binary_arith(
  op : String,
  left : DarwinConstIntValue,
  right : DarwinConstIntValue,
) -> DarwinConstIntValue? {
  let (x, y, ty) = darwin_const_apply_binary_type(left, right)
  let bits = match op {
    "+" => x.bits + y.bits
    "-" => x.bits - y.bits
    "*" => x.bits * y.bits
    "|" => x.bits | y.bits
    "&" => x.bits & y.bits
    "^" => x.bits ^ y.bits
    _ => return None
  }
  Some(darwin_const_cast_int(darwin_const_int(bits, ty), ty))
}

///|
fn darwin_const_equal_compare(
  left : DarwinConstIntValue,
  right : DarwinConstIntValue,
) -> Bool {
  let (x, y, _) = darwin_const_apply_binary_type(left, right)
  x.bits == y.bits
}

///|
fn darwin_const_rel_compare(
  op : String,
  left : DarwinConstIntValue,
  right : DarwinConstIntValue,
) -> Bool {
  let (left, right, ty) = darwin_const_apply_binary_type(left, right)
  if darwin_const_type_is_unsigned(ty) {
    let x = left.bits.reinterpret_as_uint64()
    let y = right.bits.reinterpret_as_uint64()
    match op {
      "<" => x < y
      ">" => x > y
      "<=" => x <= y
      ">=" => x >= y
      _ => false
    }
  } else {
    match op {
      "<" => left.bits < right.bits
      ">" => left.bits > right.bits
      "<=" => left.bits <= right.bits
      ">=" => left.bits >= right.bits
      _ => false
    }
  }
}

///|
fn darwin_const_divide(
  op : String,
  left : DarwinConstIntValue,
  right : DarwinConstIntValue,
) -> DarwinConstIntValue? {
  let (left, right, ty) = darwin_const_apply_binary_type(left, right)
  if right.bits == 0L {
    return None
  }
  if darwin_const_type_is_unsigned(ty) {
    let x = left.bits.reinterpret_as_uint64()
    let y = right.bits.reinterpret_as_uint64()
    let result = if op == "/" { x / y } else { x % y }
    Some(
      darwin_const_cast_int(
        darwin_const_int(result.reinterpret_as_int64(), ty),
        ty,
      ),
    )
  } else {
    let result = if op == "/" {
      left.bits / right.bits
    } else {
      left.bits % right.bits
    }
    Some(darwin_const_cast_int(darwin_const_int(result, ty), ty))
  }
}

///|
fn darwin_const_shift(
  op : String,
  left : DarwinConstIntValue,
  right : DarwinConstIntValue,
) -> DarwinConstIntValue? {
  let lhs_ty = darwin_const_integer_promote(left.ty)
  let x = darwin_const_cast_int(left, lhs_ty)
  let y = darwin_const_cast_int(right, darwin_const_integer_promote(right.ty))
  let shift = y.bits.to_int()
  if op == "<<" {
    Some(
      darwin_const_cast_int(darwin_const_int(x.bits << shift, lhs_ty), lhs_ty),
    )
  } else if darwin_const_type_is_unsigned(lhs_ty) {
    Some(
      darwin_const_cast_int(
        darwin_const_int(
          (x.bits.reinterpret_as_uint64() >> shift).reinterpret_as_int64(),
          lhs_ty,
        ),
        lhs_ty,
      ),
    )
  } else {
    Some(
      darwin_const_cast_int(darwin_const_int(x.bits >> shift, lhs_ty), lhs_ty),
    )
  }
}

///|
fn Codegen::fold_const_int(
  self : Codegen,
  expr : @parser.Expr,
) -> DarwinConstIntValue? {
  match expr {
    Number(n) => {
      let ty = number_literal_type(n)
      Some(darwin_const_cast_int(darwin_const_int(n, ty), ty))
    }
    Binary("+", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => darwin_const_binary_arith("+", x, y)
        _ => None
      }
    Binary("-", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => darwin_const_binary_arith("-", x, y)
        _ => None
      }
    Binary("*", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => darwin_const_binary_arith("*", x, y)
        _ => None
      }
    Binary("/", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => darwin_const_divide("/", x, y)
        _ => None
      }
    Binary("%", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => darwin_const_divide("%", x, y)
        _ => None
      }
    Binary("|", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => darwin_const_binary_arith("|", x, y)
        _ => None
      }
    Binary("&", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => darwin_const_binary_arith("&", x, y)
        _ => None
      }
    Binary("^", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => darwin_const_binary_arith("^", x, y)
        _ => None
      }
    Binary("<<", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => darwin_const_shift("<<", x, y)
        _ => None
      }
    Binary(">>", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => darwin_const_shift(">>", x, y)
        _ => None
      }
    Binary("==", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(darwin_const_bool(darwin_const_equal_compare(x, y)))
        _ => None
      }
    Binary("!=", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(darwin_const_bool(!darwin_const_equal_compare(x, y)))
        _ => None
      }
    Binary("<", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(darwin_const_bool(darwin_const_rel_compare("<", x, y)))
        _ => None
      }
    Binary(">", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(darwin_const_bool(darwin_const_rel_compare(">", x, y)))
        _ => None
      }
    Binary("<=", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(darwin_const_bool(darwin_const_rel_compare("<=", x, y)))
        _ => None
      }
    Binary(">=", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(darwin_const_bool(darwin_const_rel_compare(">=", x, y)))
        _ => None
      }
    Binary("&&", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(darwin_const_bool(x.bits != 0L && y.bits != 0L))
        _ => None
      }
    Binary("||", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(darwin_const_bool(x.bits != 0L || y.bits != 0L))
        _ => None
      }
    Ternary(cond, a, b) =>
      match self.fold_const_int(cond) {
        Some({ bits: 0L, .. }) => self.fold_const_int(b)
        Some(_) => self.fold_const_int(a)
        None => None
      }
    Unary("-", e) =>
      match self.fold_const_int(e) {
        Some(value) => {
          let ty = darwin_const_integer_promote(value.ty)
          Some(darwin_const_cast_int(darwin_const_int(-value.bits, ty), ty))
        }
        None => None
      }
    Unary("+", e) =>
      match self.fold_const_int(e) {
        Some(value) => {
          let ty = darwin_const_integer_promote(value.ty)
          Some(darwin_const_cast_int(value, ty))
        }
        None => None
      }
    Unary("~", e) =>
      match self.fold_const_int(e) {
        Some(value) => {
          let ty = darwin_const_integer_promote(value.ty)
          Some(
            darwin_const_cast_int(darwin_const_int(value.bits.lnot(), ty), ty),
          )
        }
        None => None
      }
    Unary("!", e) =>
      match self.fold_const_int(e) {
        Some(value) => Some(darwin_const_bool(value.bits == 0L))
        None => None
      }
    Cast(ty, e) =>
      if ty.is_floating() {
        None
      } else if self.type_of(e, 0).is_floating() {
        match self.fold_float_const(e) {
          Some(value) =>
            Some(
              darwin_const_cast_int(
                darwin_const_int(value.to_int().to_int64(), ty),
                ty,
              ),
            )
          None => None
        }
      } else {
        match darwin_const_type_int_width(ty) {
          Some(_) =>
            match self.fold_const_int(e) {
              Some(value) => Some(darwin_const_cast_int(value, ty))
              None => None
            }
          None => None
        }
      }
    DesignatedField(_, e) => self.fold_const_int(e)
    DesignatedIndex(_, e) => self.fold_const_int(e)
    DesignatedRange(_, _, e) => self.fold_const_int(e)
    Sizeof(ty) => Some(darwin_const_int(self.type_size(ty).to_int64(), ULong))
    SizeofExpr(e) =>
      Some(
        darwin_const_int(
          self.type_size(self.global_expr_type(e)).to_int64(),
          ULong,
        ),
      )
    Alignof(ty) => Some(darwin_const_int(self.type_align(ty).to_int64(), ULong))
    AlignofExpr(e) =>
      Some(
        darwin_const_int(
          self.type_align(self.global_expr_type(e)).to_int64(),
          ULong,
        ),
      )
    OffsetOf(ty, path) =>
      match self.offset_of_path(ty, path) {
        Some(offset) => Some(darwin_const_int(offset.to_int64(), ULong))
        None => None
      }
    _ => None
  }
}

///|
fn Codegen::fold_const(self : Codegen, expr : @parser.Expr) -> Int64? {
  match self.mir {
    Some(mir) =>
      match
        mir.fold_const(expr, {
          locals: self.var_types,
          current_func: self.func_name,
        }) {
        Some(value) => return Some(value)
        None => ()
      }
    None => ()
  }
  match self.fold_const_int(expr) {
    Some(value) => Some(value.bits)
    None => None
  }
}

///|
fn Codegen::fold_float_const(self : Codegen, expr : @parser.Expr) -> Double? {
  match self.mir {
    Some(mir) =>
      match
        mir.fold_float_const(expr, {
          locals: self.var_types,
          current_func: self.func_name,
        }) {
        Some(value) => return Some(value)
        None => ()
      }
    None => ()
  }
  let expr_ty = self.type_of(expr, 0)
  if !expr_ty.is_floating() {
    match expr {
      Cast(_, e) if self.type_of(e, 0).is_floating() =>
        match self.fold_float_const(e) {
          Some(v) => Some(v.to_int().to_double())
          None => None
        }
      _ =>
        match self.fold_const(expr) {
          Some(n) => Some(n.to_double())
          _ => None
        }
    }
  } else {
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
          "__builtin_nan" | "__builtin_nanf" | "__builtin_nanl" =>
            Some(0.0 / 0.0)
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
fn Codegen::designator_matches_type(
  self : Codegen,
  ty : @parser.Type,
  expr : @parser.Expr,
) -> Bool {
  match (peel_aligned_type(ty), expr) {
    (Struct(_), DesignatedField(field, _))
    | (Union(_), DesignatedField(field, _)) =>
      self.find_field_layout_for_type(ty, field) is Some(_)
    (Array(_, _), DesignatedIndex(_, _))
    | (Array(_, _), DesignatedRange(_, _, _)) => true
    _ => false
  }
}

///|
fn Codegen::global_lvalue_reloc(
  self : Codegen,
  expr : @parser.Expr,
) -> (String, Int)? {
  match expr {
    Var(name) => Some(("_" + name, 0))
    Cast(_, e) => self.global_lvalue_reloc(e)
    Deref(e) => self.global_address_reloc_parts(e)
    ArrayAccess(base, index) =>
      match
        (self.global_lvalue_reloc(base), self.global_address_reloc_parts(base)) {
        (Some(parts), _) | (None, Some(parts)) => {
          let (label, base_offset) = parts
          let elem_size = match peel_aligned_type(self.global_expr_type(base)) {
            Array(elem, _) | Pointer(elem) => self.pointer_element_size(elem)
            _ => 1
          }
          match self.fold_const(index) {
            Some(i) => Some((label, base_offset + i.to_int() * elem_size))
            None => None
          }
        }
        _ => None
      }
    MemberAccess(obj, field) =>
      match self.global_lvalue_reloc(obj) {
        Some((label, base_offset)) => {
          let obj_ty = self.global_expr_type(obj)
          match self.find_field_layout_for_type(obj_ty, field) {
            Some((_, _, field_offset, _, _, _)) =>
              Some((label, base_offset + field_offset))
            None => None
          }
        }
        None => None
      }
    _ => None
  }
}

///|
fn Codegen::global_address_reloc_parts(
  self : Codegen,
  expr : @parser.Expr,
) -> (String, Int)? {
  match expr {
    Cast(_, e) => self.global_address_reloc_parts(e)
    AddrOf(e) => self.global_lvalue_reloc(e)
    LabelAddr(name) => Some((self.label_ref(name), 0))
    Var(name) => Some(("_" + name, 0))
    Binary("+", base, offset_expr) =>
      match
        (self.global_address_reloc_parts(base), self.fold_const(offset_expr)) {
        (Some((label, base_offset)), Some(offset)) =>
          Some((label, base_offset + self.global_offset_bytes(base, offset)))
        _ =>
          match
            (
              self.global_address_reloc_parts(offset_expr),
              self.fold_const(base),
            ) {
            (Some((label, base_offset)), Some(offset)) =>
              Some(
                (
                  label,
                  base_offset + self.global_offset_bytes(offset_expr, offset),
                ),
              )
            _ => None
          }
      }
    Binary("-", base, offset_expr) =>
      match
        (self.global_address_reloc_parts(base), self.fold_const(offset_expr)) {
        (Some((label, base_offset)), Some(offset)) =>
          Some((label, base_offset - self.global_offset_bytes(base, offset)))
        _ => None
      }
    _ => None
  }
}

///|
fn Codegen::global_address_reloc(
  self : Codegen,
  expr : @parser.Expr,
) -> String? {
  match self.global_address_reloc_parts(expr) {
    Some((label, offset)) => Some(reloc_with_offset(label, offset))
    None => None
  }
}

///|
fn Codegen::pointer_element_size(self : Codegen, elem_ty : @parser.Type) -> Int {
  match peel_aligned_type(elem_ty) {
    Void => 1
    _ => self.type_size(elem_ty)
  }
}

///|
fn Codegen::global_offset_bytes(
  self : Codegen,
  base : @parser.Expr,
  offset : Int64,
) -> Int {
  match peel_aligned_type(self.global_expr_type(base)) {
    Pointer(elem) | Array(elem, _) =>
      offset.to_int() * self.pointer_element_size(elem)
    _ => offset.to_int()
  }
}

///|
/// Creates a fresh code generator with empty per-program state.
pub fn Codegen::new() -> Codegen {
  {
    output: StringBuilder::new(),
    mir: None,
    mir_module: None,
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
fn Codegen::new_with_mir(mir : @mir.Program) -> Codegen {
  let codegen = Codegen::new()
  codegen.mir = Some(mir)
  codegen.mir_module = Some(mir.to_module())
  codegen
}

///|
fn Codegen::new_with_mir_module(mir : @mir.MirModule) -> Codegen {
  let codegen = Codegen::new()
  codegen.mir_module = Some(mir)
  codegen
}

///|
fn Codegen::register_mir_function_decls(
  self : Codegen,
  mir : @mir.MirModule,
) -> Unit {
  for decl in mir.decls {
    self.func_rets[decl.name] = decl.ret
    self.func_variadic[decl.name] = decl.variadic
    self.func_param_counts[decl.name] = decl.params.length()
    let param_types = []
    for param in decl.params {
      param_types.push(param.ty)
    }
    self.func_param_types[decl.name] = param_types
  }
}

///|
fn Codegen::register_mir_global_decls(
  self : Codegen,
  mir : @mir.MirModule,
) -> Unit {
  for global in @mir.merge_global_decls(mir.global_decls) {
    self.globals[global.name] = global
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
    Float | Double | LongDouble =>
      match self.fold_float_const(expr) {
        Some(v) => {
          self.emit_global_float(ty, v)
          return
        }
        None => ()
      }
    _ => ()
  }
  if ty.is_integer() && self.type_of(expr, 0).is_floating() {
    match self.fold_float_const(expr) {
      Some(v) => {
        self.emit_global_scalar(ty, Number(v.to_int().to_int64()))
        return
      }
      None => ()
    }
  }
  match expr {
    DesignatedField(_, e) | DesignatedIndex(_, e) | DesignatedRange(_, _, e) => {
      if is_aggregate_type(ty) && self.designator_matches_type(ty, expr) {
        self.emit_global_array(ty, [expr])
      } else {
        self.emit_global_scalar(ty, e)
      }
      return
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
        SInt128 => {
          self.emit("\t.quad\t" + n.to_string())
          let high = if n < 0L { "-1" } else { "0" }
          self.emit("\t.quad\t" + high)
        }
        UInt128 => {
          self.emit("\t.quad\t" + n.to_string())
          self.emit("\t.quad\t0")
        }
        Float | Double | LongDouble => self.emit_global_float(ty, n.to_double())
        Struct(_) | Union(_) | Array(_, _) => {
          // Zero-initialize aggregate type
          let size = self.type_size(ty)
          self.emit("\t.space\t" + size.to_string())
        }
        _ => self.emit("\t.quad\t" + n.to_string())
      }
    FloatLiteral(v) =>
      if ty.is_floating() {
        self.emit_global_float(ty, v)
      } else {
        self.emit_global_scalar(ty, Number(v.to_int().to_int64()))
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
    Cast(_, e) => self.emit_global_scalar(ty, e)
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
fn Codegen::mir_global_scalar_int_supported(
  self : Codegen,
  ty : @parser.Type,
) -> Bool {
  match ty {
    Aligned(inner, _) => self.mir_global_scalar_int_supported(inner)
    _ =>
      match ty {
        Bool
        | SChar
        | UChar
        | SShort
        | UShort
        | SInt
        | UInt
        | SLong
        | ULong
        | SLongLong
        | ULongLong
        | SInt128
        | UInt128
        | Float
        | Double
        | LongDouble
        | Pointer(_)
        | FuncPtr(_, _, _) => true
        _ => false
      }
  }
}

///|
fn Codegen::mir_global_string_supported(
  self : Codegen,
  ty : @parser.Type,
) -> Bool {
  match ty {
    Aligned(inner, _) => self.mir_global_string_supported(inner)
    _ =>
      match ty {
        Array(SChar, _) | Array(UChar, _) | Pointer(_) => true
        _ => false
      }
  }
}

///|
fn Codegen::mir_global_symbol_supported(
  self : Codegen,
  ty : @parser.Type,
) -> Bool {
  match ty {
    Aligned(inner, _) => self.mir_global_symbol_supported(inner)
    Pointer(_) | FuncPtr(_, _, _) => true
    _ => false
  }
}

///|
fn Codegen::mir_global_init_supported(
  self : Codegen,
  ty : @parser.Type,
  init : @mir.MirGlobalInit,
) -> Bool {
  match ty {
    Aligned(inner, _) => self.mir_global_init_supported(inner, init)
    _ =>
      match init {
        MirGlobalInitUnsupported => false
        MirGlobalScalarInt(_) => self.mir_global_scalar_int_supported(ty)
        MirGlobalString(_) => self.mir_global_string_supported(ty)
        MirGlobalSymbol(_) => self.mir_global_symbol_supported(ty)
        MirGlobalSymbolOffset(_, _) => self.mir_global_symbol_supported(ty)
        MirGlobalArray(values) =>
          match ty {
            Array(elem_ty, n) => {
              if values.length() > n {
                return false
              }
              for value in values {
                if !self.mir_global_init_supported(elem_ty, value) {
                  return false
                }
              }
              true
            }
            Struct(name) | Union(name) => {
              let layout = match self.mir_aggregate_layout(name) {
                Some(layout) => layout
                None => return false
              }
              if layout.is_union {
                if values.length() > 1 {
                  return false
                }
              } else if values.length() > layout.fields.length() {
                return false
              }
              for i = 0; i < values.length(); i = i + 1 {
                if i >= layout.fields.length() {
                  return false
                }
                let field = layout.fields[i]
                if field.bit_width is Some(_) {
                  return false
                }
                if !self.mir_global_init_supported(field.ty, values[i]) {
                  return false
                }
              }
              true
            }
            _ => false
          }
      }
  }
}

///|
fn Codegen::mir_aggregate_layout(
  self : Codegen,
  name : String,
) -> @mir.AggregateLayout? {
  match self.mir_module {
    Some(mir) => mir.layouts.get(name)
    None => None
  }
}

///|
fn Codegen::emit_mir_global_scalar_int(
  self : Codegen,
  ty : @parser.Type,
  value : Int64,
) -> Unit {
  match ty {
    Aligned(inner, _) => {
      self.emit_mir_global_scalar_int(inner, value)
      return
    }
    _ => ()
  }
  match ty {
    Bool | SChar | UChar => self.emit("\t.byte\t" + value.to_string())
    SShort | UShort => self.emit("\t.short\t" + value.to_string())
    SInt | UInt => self.emit("\t.long\t" + value.to_string())
    SInt128 => {
      self.emit("\t.quad\t" + value.to_string())
      let high = if value < 0L { "-1" } else { "0" }
      self.emit("\t.quad\t" + high)
    }
    UInt128 => {
      self.emit("\t.quad\t" + value.to_string())
      self.emit("\t.quad\t0")
    }
    Float | Double | LongDouble => self.emit_global_float(ty, value.to_double())
    _ => self.emit("\t.quad\t" + value.to_string())
  }
}

///|
fn Codegen::emit_mir_global_string(
  self : Codegen,
  ty : @parser.Type,
  value : String,
) -> Unit {
  match ty {
    Aligned(inner, _) => {
      self.emit_mir_global_string(inner, value)
      return
    }
    _ => ()
  }
  match ty {
    Array(SChar, n) | Array(UChar, n) => {
      self.emit("\t.asciz\t\"" + escape_string(value) + "\"")
      let pad = n - value.length() - 1
      if pad > 0 {
        self.emit("\t.space\t" + pad.to_string())
      }
    }
    _ => {
      let idx = self.strings.length()
      self.strings.push(value)
      self.emit("\t.quad\t_str" + idx.to_string())
    }
  }
}

///|
fn Codegen::emit_mir_global_init(
  self : Codegen,
  ty : @parser.Type,
  init : @mir.MirGlobalInit,
) -> Unit {
  match ty {
    Aligned(inner, _) => {
      self.emit_mir_global_init(inner, init)
      return
    }
    _ => ()
  }
  match init {
    MirGlobalScalarInt(value) => self.emit_mir_global_scalar_int(ty, value)
    MirGlobalString(value) => self.emit_mir_global_string(ty, value)
    MirGlobalSymbol(name) => self.emit("\t.quad\t_" + name)
    MirGlobalSymbolOffset(name, offset) =>
      self.emit("\t.quad\t" + reloc_with_offset("_" + name, offset))
    MirGlobalArray(values) =>
      match ty {
        Array(elem_ty, n) => {
          let elem_size = self.type_size(elem_ty)
          let mut emitted = 0
          for value in values {
            self.emit_mir_global_init(elem_ty, value)
            emitted += 1
          }
          while emitted < n {
            self.emit("\t.space\t" + elem_size.to_string())
            emitted += 1
          }
        }
        Struct(name) | Union(name) =>
          self.emit_mir_global_aggregate(name, values)
        _ => self.emit("\t.space\t" + self.type_size(ty).to_string())
      }
    MirGlobalInitUnsupported =>
      self.emit("\t.space\t" + self.type_size(ty).to_string())
  }
}

///|
fn Codegen::emit_mir_global_aggregate(
  self : Codegen,
  name : String,
  values : Array[@mir.MirGlobalInit],
) -> Unit {
  let layout = match self.mir_aggregate_layout(name) {
    Some(layout) => layout
    None => {
      self.emit("\t.space\t8")
      return
    }
  }
  let mut emitted = 0
  let count = if layout.is_union && values.length() > 0 {
    1
  } else {
    values.length()
  }
  for i = 0; i < count; i = i + 1 {
    let field = layout.fields[i]
    if field.offset > emitted {
      self.emit("\t.space\t" + (field.offset - emitted).to_string())
    }
    self.emit_mir_global_init(field.ty, values[i])
    emitted = field.offset + field.size
    if layout.is_union {
      break
    }
  }
  if layout.size > emitted {
    self.emit("\t.space\t" + (layout.size - emitted).to_string())
  }
}

///|
fn Codegen::try_emit_mir_global_init(
  self : Codegen,
  g : @mir.MirGlobalDecl,
) -> Bool {
  match g.init {
    Some(init) =>
      if self.mir_global_init_supported(g.ty, init) {
        self.emit_mir_global_init(g.ty, init)
        true
      } else {
        false
      }
    None => false
  }
}

///|
fn global_initializer_value(expr : @parser.Expr) -> @parser.Expr {
  match expr {
    DesignatedField(_, e) | DesignatedIndex(_, e) | DesignatedRange(_, _, e) =>
      e
    _ => expr
  }
}

///|
fn Codegen::emit_global_int_by_size(
  self : Codegen,
  size : Int,
  value : Int64,
) -> Unit {
  match size {
    1 => self.emit("\t.byte\t" + value.to_string())
    2 => self.emit("\t.short\t" + value.to_string())
    4 => self.emit("\t.long\t" + value.to_string())
    _ => self.emit("\t.quad\t" + value.to_string())
  }
}

///|
fn Codegen::global_bitfield_bits(
  self : Codegen,
  init_expr : @parser.Expr,
  bit_width : Int,
  bit_offset : Int,
) -> Int64 {
  match self.fold_const(global_initializer_value(init_expr)) {
    Some(value) => (value & bitfield_mask(bit_width)) << bit_offset
    None => 0L
  }
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
      let field_inits : Array[@parser.Expr?] = Array::make(
        layout.length(),
        None,
      )
      let mut positional = 0
      for init_expr in exprs {
        match init_expr {
          DesignatedField(field_name, _) =>
            for i = 0; i < layout.length(); i = i + 1 {
              if layout[i].0 == field_name {
                field_inits[i] = Some(init_expr)
                positional = i + 1
                break
              }
            }
          _ =>
            if positional < layout.length() {
              field_inits[positional] = Some(init_expr)
              positional += 1
            }
        }
      }
      let mut emitted = 0
      let mut i = 0
      while i < layout.length() {
        let field = layout[i]
        let field_ty = field.1
        let field_offset = field.2
        let field_size = field.3
        let bit_width = field.5
        if bit_width > 0 {
          let container_offset = field_offset
          let container_size = field_size
          let mut container_value = 0L
          let mut j = i
          while j < layout.length() &&
                layout[j].2 == container_offset &&
                layout[j].3 == container_size &&
                layout[j].5 > 0 {
            let width = layout[j].5
            let offset = layout[j].4
            match field_inits[j] {
              Some(init_expr) =>
                container_value = container_value |
                  self.global_bitfield_bits(init_expr, width, offset)
              None => ()
            }
            j += 1
          }
          if container_offset >= emitted {
            if container_offset > emitted {
              self.emit("\t.space\t" + (container_offset - emitted).to_string())
            }
            self.emit_global_int_by_size(container_size, container_value)
            emitted = container_offset + container_size
          }
          i = j
        } else {
          match field_inits[i] {
            Some(expr) => {
              // Emit padding to reach the correct field offset
              if field_offset > emitted {
                self.emit("\t.space\t" + (field_offset - emitted).to_string())
              }
              self.emit_global_scalar(field_ty, expr)
              emitted = field_offset + field_size
            }
            None => ()
          }
          i += 1
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
            self.find_field_layout_for_type(ty, field_name)
          _ => if layout.length() > 0 { Some(layout[0]) } else { None }
        }
        match field {
          Some((_, field_ty, field_offset, field_size, bit_offset, bit_width)) =>
            if bit_width > 0 {
              if field_offset > 0 {
                self.emit("\t.space\t" + field_offset.to_string())
              }
              self.emit_global_int_by_size(
                field_size,
                self.global_bitfield_bits(init_expr, bit_width, bit_offset),
              )
              emitted = field_offset + field_size
            } else {
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
  if self.mir is None {
    self.mir = Some(@mir.lower(prog, @target.Target::default()))
  }
  self.output.write_string(
    "\t.section\t__TEXT,__text,regular,pure_instructions\n",
  )
  self.output.write_string("\t.build_version macos, 14, 0\n")
  // Register all struct/union declarations first (to handle forward refs)
  for sdecl in prog.structs {
    self.struct_decls[sdecl.name] = sdecl
  }
  // Then seed layouts in a second pass
  let mir_module = match self.mir_module {
    Some(mir) => Some(mir)
    None =>
      match self.mir {
        Some(mir) => {
          let mir_module = mir.to_module()
          self.mir_module = Some(mir_module)
          Some(mir_module)
        }
        None => None
      }
  }
  match mir_module {
    Some(mir) => self.register_mir_aggregate_layouts(mir)
    None =>
      for sdecl in prog.structs {
        self.compute_struct_layout(sdecl)
      }
  }
  // Precompute function return types, variadic flags, and param counts
  match mir_module {
    Some(mir) => self.register_mir_function_decls(mir)
    None => ()
  }
  let inline_decls : Map[String, @parser.FuncDecl] = {}
  for decl in prog.decls {
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
  let parser_globals = merge_global_decls(prog.globals)
  let parser_global_fallbacks : Map[String, @parser.GlobalDecl] = {}
  for g in parser_globals {
    parser_global_fallbacks[g.name] = g
  }
  // Record global variables
  match mir_module {
    Some(mir) => self.register_mir_global_decls(mir)
    None => ()
  }
  let mir_globals : Array[@mir.MirGlobalDecl] = match mir_module {
    Some(mir) => @mir.merge_global_decls(mir.global_decls)
    None => []
  }
  let mir_func_decls : Array[@mir.MirFuncDecl] = match mir_module {
    Some(mir) => mir.decls
    None => []
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
  for g in mir_globals {
    if g.has_init {
      if !has_data {
        self.emit("	.section	__DATA,__data")
        has_data = true
      }
      if !g.is_static {
        if g.is_weak {
          self.emit("	.weak_definition	_" + g.name)
        } else {
          self.emit("	.globl	_" + g.name)
        }
      }
      self.emit_global_p2align(g.ty)
      self.emit("_" + g.name + ":")
      let saved_func_name = self.func_name
      let saved_emitted_labels = self.emitted_labels
      match static_global_owner_name(g.name, mir_func_decls) {
        Some(owner) => {
          self.func_name = owner
          match func_label_maps.get(owner) {
            Some(labels) => self.emitted_labels = labels
            None => ()
          }
        }
        None => ()
      }
      if !self.try_emit_mir_global_init(g) {
        match parser_global_fallbacks.get(g.name) {
          Some(parser_global) =>
            match parser_global.init {
              Some(Scalar(expr)) => self.emit_global_scalar(g.ty, expr)
              Some(Array(exprs)) => self.emit_global_array(g.ty, exprs)
              None => ()
            }
          None => self.emit("\t.space\t" + self.type_size(g.ty).to_string())
        }
      }
      self.func_name = saved_func_name
      self.emitted_labels = saved_emitted_labels
    }
  }
  // Emit uninitialized global variables
  let mut has_bss = false
  for g in mir_globals {
    if !g.has_init && !g.is_extern {
      if !has_bss {
        self.emit("	.section	__DATA,__bss")
        has_bss = true
      }
      let size = self.type_size(g.ty)
      if !g.is_static {
        if g.is_weak {
          self.emit("	.weak_definition	_" + g.name)
        } else {
          self.emit("	.globl	_" + g.name)
        }
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
fn Codegen::generate_mir_only(
  self : Codegen,
  mir_module : @mir.MirModule,
) -> String {
  self.output.write_string(
    "\t.section\t__TEXT,__text,regular,pure_instructions\n",
  )
  self.output.write_string("\t.build_version macos, 14, 0\n")
  self.register_mir_aggregate_layouts(mir_module)
  self.register_mir_function_decls(mir_module)
  self.register_mir_global_decls(mir_module)
  for decl in mir_module.decls {
    if decl.has_body {
      match mir_module.bodies.get(decl.name) {
        Some(body) => self.gen_mir_func(decl, body)
        None => ()
      }
    }
  }
  let mir_globals = @mir.merge_global_decls(mir_module.global_decls)
  let mut has_data = false
  for g in mir_globals {
    if g.has_init {
      if !has_data {
        self.emit("	.section	__DATA,__data")
        has_data = true
      }
      if !g.is_static {
        if g.is_weak {
          self.emit("	.weak_definition	_" + g.name)
        } else {
          self.emit("	.globl	_" + g.name)
        }
      }
      self.emit_global_p2align(g.ty)
      self.emit("_" + g.name + ":")
      if !self.try_emit_mir_global_init(g) {
        self.emit("\t.space\t" + self.type_size(g.ty).to_string())
      }
    }
  }
  let mut has_bss = false
  for g in mir_globals {
    if !g.has_init && !g.is_extern {
      if !has_bss {
        self.emit("	.section	__DATA,__bss")
        has_bss = true
      }
      if !g.is_static {
        if g.is_weak {
          self.emit("	.weak_definition	_" + g.name)
        } else {
          self.emit("	.globl	_" + g.name)
        }
      }
      self.emit_global_p2align(g.ty)
      self.emit("_" + g.name + ":")
      self.emit("	.space	" + self.type_size(g.ty).to_string())
    }
  }
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
  generate_assembly_from_mir_with_parser_fallback(@mir.lower(prog, target))
}

///|
/// Generates assembly from an already lowered MIR program.
///
/// This is the backend-facing entry point. It does not use the parser AST
/// fallback stored on transitional MIR programs; unsupported MIR coverage is a
/// hard error.
pub fn generate_assembly_from_mir(mir : @mir.Program) -> String {
  match generate_assembly_from_mir_strict(mir) {
    Ok(assembly) => assembly
    Err(err) => abort(err)
  }
}

///|
/// Generates assembly from MIR, falling back to parser AST codegen for source
/// constructs that are not represented in MIR yet.
pub fn generate_assembly_from_mir_with_parser_fallback(
  mir : @mir.Program,
) -> String {
  match generate_assembly_from_mir_strict(mir) {
    Ok(assembly) => return assembly
    Err(_) => ()
  }
  match mir.target {
    DarwinArm64 => Codegen::new_with_mir(mir).generate(mir.source)
    LinuxAmd64 => X64Codegen::new_with_mir(mir).generate(mir.source)
  }
}

///|
/// Generates assembly from a parser-free MIR module when the current MIR-only
/// backend coverage is sufficient.
pub fn generate_assembly_from_mir_module_strict(
  mir_module : @mir.MirModule,
) -> Result[String, String] {
  match mir_module_body_codegen_strict_error(mir_module) {
    Some(err) => Err(err)
    None =>
      match mir_module_global_codegen_strict_error(mir_module) {
        Some(err) => Err(err)
        None => Ok(generate_assembly_from_mir_module_unchecked(mir_module))
      }
  }
}

///|
/// Generates assembly from MIR only when every source function definition can
/// use the MIR-body backend path.
///
/// This strict gate is deliberately narrower than full parser independence: it
/// prevents parser statement/expression fallback for function bodies while
/// globals and metadata continue to migrate into MIR-owned declarations.
pub fn generate_assembly_from_mir_strict(
  mir : @mir.Program,
) -> Result[String, String] {
  generate_assembly_from_mir_module_strict(mir.to_module())
}

///|
fn generate_assembly_from_mir_module_unchecked(
  mir_module : @mir.MirModule,
) -> String {
  match mir_module.target {
    DarwinArm64 =>
      Codegen::new_with_mir_module(mir_module).generate_mir_only(mir_module)
    LinuxAmd64 =>
      X64Codegen::new_with_mir_module(mir_module).generate_mir_only(mir_module)
  }
}

///|
fn mir_module_global_codegen_strict_error(
  mir_module : @mir.MirModule,
) -> String? {
  match mir_module.target {
    DarwinArm64 => {
      let codegen = Codegen::new_with_mir_module(mir_module)
      for g in @mir.merge_global_decls(mir_module.global_decls) {
        if g.has_init {
          match g.init {
            Some(init) =>
              if !codegen.mir_global_init_supported(g.ty, init) {
                return Some("unsupported MIR global initializer for " + g.name)
              }
            None => return Some("missing MIR global initializer for " + g.name)
          }
        }
      }
    }
    LinuxAmd64 => {
      let codegen = X64Codegen::new_with_mir_module(mir_module)
      for g in @mir.merge_global_decls(mir_module.global_decls) {
        if g.has_init {
          match g.init {
            Some(init) =>
              if !codegen.mir_global_init_supported(g.ty, init) {
                return Some("unsupported MIR global initializer for " + g.name)
              }
            None => return Some("missing MIR global initializer for " + g.name)
          }
        }
      }
    }
  }
  None
}

///|
fn mir_module_body_codegen_strict_error(mir_module : @mir.MirModule) -> String? {
  let int_arg_limit = match mir_module.target {
    DarwinArm64 => 8
    LinuxAmd64 => 6
  }
  for decl in mir_module.decls {
    if decl.has_body {
      if !mir_module.bodies.contains(decl.name) {
        return Some("missing MIR body for " + decl.name)
      }
      let body = mir_module.bodies[decl.name]
      if !mir_body_codegen_func_supported(
          body,
          decl.variadic,
          int_arg_limit,
          mir_module,
        ) {
        return Some("unsupported MIR body codegen for " + decl.name)
      }
    }
  }
  None
}

///|
fn static_global_owner_name(
  name : String,
  decls : Array[@mir.MirFuncDecl],
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
