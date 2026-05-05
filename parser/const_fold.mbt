///|
pub fn fold_const(expr : Expr) -> Int64? {
  match expr {
    Number(n) => Some(n)
    Binary("+", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x + y)
        _ => None
      }
    Binary("-", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x - y)
        _ => None
      }
    Binary("*", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x * y)
        _ => None
      }
    Binary("/", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => if y != 0 { Some(x / y) } else { None }
        _ => None
      }
    Binary("%", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => if y != 0 { Some(x % y) } else { None }
        _ => None
      }
    Binary("|", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x | y)
        _ => None
      }
    Binary("&", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x & y)
        _ => None
      }
    Binary("^", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x ^ y)
        _ => None
      }
    Binary("<<", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x << y.to_int())
        _ => None
      }
    Binary(">>", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(x >> y.to_int())
        _ => None
      }
    Binary("==", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x == y { 1L } else { 0L })
        _ => None
      }
    Binary("!=", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x != y { 1L } else { 0L })
        _ => None
      }
    Binary("<", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x < y { 1L } else { 0L })
        _ => None
      }
    Binary(">", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x > y { 1L } else { 0L })
        _ => None
      }
    Binary("<=", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x <= y { 1L } else { 0L })
        _ => None
      }
    Binary(">=", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x >= y { 1L } else { 0L })
        _ => None
      }
    Binary("&&", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x != 0L && y != 0L { 1L } else { 0L })
        _ => None
      }
    Binary("||", a, b) =>
      match (fold_const(a), fold_const(b)) {
        (Some(x), Some(y)) => Some(if x != 0L || y != 0L { 1L } else { 0L })
        _ => None
      }
    Ternary(cond, a, b) =>
      match fold_const(cond) {
        Some(0L) => fold_const(b)
        Some(_) => fold_const(a)
        None => None
      }
    Unary("-", e) =>
      match fold_const(e) {
        Some(x) => Some(-x)
        _ => None
      }
    Unary("~", e) =>
      match fold_const(e) {
        Some(x) => Some(x.lnot())
        _ => None
      }
    Unary("!", e) =>
      match fold_const(e) {
        Some(0L) => Some(1L)
        Some(_) => Some(0L)
        _ => None
      }
    Cast(_, e) => fold_const(e)
    Sizeof(ty) => Some(basic_type_size(ty).to_int64())
    SizeofExpr(String(s)) => Some((s.length() + 1).to_int64())
    SizeofExpr(e) => Some(basic_type_size(type_of_expr(e)).to_int64())
    DesignatedField(_, e) => fold_const(e)
    DesignatedIndex(_, e) => fold_const(e)
    DesignatedRange(_, _, e) => fold_const(e)
    Array(_) => None
    CompoundLiteral(_, _, _) => None
    _ => None
  }
}

///|
fn Parser::fold_const(self : Parser, expr : Expr) -> Int64? {
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
        (Some(x), Some(y)) => if y != 0 { Some(x / y) } else { None }
        _ => None
      }
    Binary("%", a, b) =>
      match (self.fold_const(a), self.fold_const(b)) {
        (Some(x), Some(y)) => if y != 0 { Some(x % y) } else { None }
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
    Sizeof(ty) => Some(self.const_type_size(ty).to_int64())
    SizeofExpr(e) =>
      Some(self.const_type_size(self.const_expr_type(e)).to_int64())
    OffsetOf(ty, field) =>
      match self.const_offset_of(ty, field) {
        Some(offset) => Some(offset.to_int64())
        None => None
      }
    DesignatedField(_, e) => self.fold_const(e)
    DesignatedIndex(_, e) => self.fold_const(e)
    DesignatedRange(_, _, e) => self.fold_const(e)
    Array(_) => None
    CompoundLiteral(_, _, _) => None
    _ => None
  }
}

///|
fn basic_type_size(ty : Type) -> Int {
  match ty {
    Void => 0
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt | Float => 4
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    Array(elem, n) => basic_type_size(elem) * n
    Struct(_) => 8 // unknown struct size, assume pointer-sized
    Union(_) => 8 // unknown union size, assume pointer-sized
    Atomic(inner) => basic_type_size(inner)
  }
}

///|
fn Parser::const_type_size(self : Parser, ty : Type) -> Int {
  match ty {
    Void => 0
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt | Float => 4
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    Array(elem, n) => self.const_type_size(elem) * n
    Atomic(inner) => self.const_type_size(inner)
    Struct(name) => self.const_struct_size(name)
    Union(name) => self.const_union_size(name)
  }
}

///|
fn Parser::const_type_align(self : Parser, ty : Type) -> Int {
  match ty {
    Void => 1
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt | Float => 4
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    Array(elem, _) => self.const_type_align(elem)
    Atomic(inner) => self.const_type_align(inner)
    Struct(name) => self.const_struct_align(name)
    Union(name) => self.const_union_align(name)
  }
}

///|
fn Parser::const_struct_size(self : Parser, name : String) -> Int {
  if !self.struct_decls.contains(name) {
    return 8
  }
  let layout = self.const_struct_layout(self.struct_decls[name])
  let mut max_end = 0
  let mut max_align = 1
  for field in layout {
    let end = field.2 + field.3
    if end > max_end {
      max_end = end
    }
    let align = self.const_type_align(field.1)
    if align > max_align {
      max_align = align
    }
  }
  max_end + (max_align - max_end % max_align) % max_align
}

///|
fn Parser::const_union_size(self : Parser, name : String) -> Int {
  if !self.struct_decls.contains(name) {
    return 8
  }
  let mut max_size = 0
  for field in self.struct_decls[name].fields {
    let size = self.const_type_size(field.ty)
    if size > max_size {
      max_size = size
    }
  }
  max_size
}

///|
fn Parser::const_struct_align(self : Parser, name : String) -> Int {
  if !self.struct_decls.contains(name) {
    return 8
  }
  let mut max_align = 1
  for field in self.struct_decls[name].fields {
    let align = self.const_type_align(field.ty)
    if align > max_align {
      max_align = align
    }
  }
  max_align
}

///|
fn Parser::const_union_align(self : Parser, name : String) -> Int {
  self.const_struct_align(name)
}

///|
fn parser_is_anon_type(ty : Type) -> Bool {
  match ty {
    Struct(name) | Union(name) => name.has_prefix("__anon_")
    _ => false
  }
}

///|
fn Parser::const_flatten_anon_fields(
  self : Parser,
  ty : Type,
  base_offset : Int,
) -> Array[(String, Type, Int, Int, Int, Int)] {
  let name = match ty {
    Struct(n) | Union(n) => n
    _ => return []
  }
  if !self.struct_decls.contains(name) {
    return []
  }
  let decl = self.struct_decls[name]
  let fields = if decl.is_union {
    self.const_union_layout(decl)
  } else {
    self.const_struct_layout(decl)
  }
  let result = []
  for field in fields {
    if field.0 == "" && parser_is_anon_type(field.1) {
      for
        inner in self.const_flatten_anon_fields(field.1, base_offset + field.2) {
        result.push(inner)
      }
    } else {
      result.push(
        (field.0, field.1, base_offset + field.2, field.3, field.4, field.5),
      )
    }
  }
  result
}

///|
fn Parser::const_struct_layout(
  self : Parser,
  decl : StructDecl,
) -> Array[(String, Type, Int, Int, Int, Int)] {
  let layout = []
  let mut offset = 0
  let mut in_bitfield_run = false
  let mut current_bit_offset = 0
  for field in decl.fields {
    if field.name == "" && parser_is_anon_type(field.ty) {
      let align = self.const_type_align(field.ty)
      offset += (align - offset % align) % align
      for f in self.const_flatten_anon_fields(field.ty, offset) {
        layout.push(f)
      }
      offset += self.const_type_size(field.ty)
      in_bitfield_run = false
      current_bit_offset = 0
      continue
    }
    match field.bit_width {
      None => {
        let size = self.const_type_size(field.ty)
        let align = self.const_type_align(field.ty)
        offset += (align - offset % align) % align
        layout.push((field.name, field.ty, offset, size, 0, 0))
        offset += size
        in_bitfield_run = false
        current_bit_offset = 0
      }
      Some(width) => {
        let container_size = self.const_type_size(field.ty)
        let container_align = self.const_type_align(field.ty)
        let container_bits = container_size * 8
        if width == 0 {
          offset += (container_align - offset % container_align) %
            container_align
          in_bitfield_run = false
          current_bit_offset = 0
        } else {
          let mut container_offset = current_bit_offset /
            (container_align * 8) *
            container_align
          let mut field_bit_offset = current_bit_offset - container_offset * 8
          let can_continue = in_bitfield_run &&
            field_bit_offset + width <= container_bits
          if !can_continue {
            container_offset = offset / container_align * container_align
            field_bit_offset = (offset - container_offset) * 8
            if offset >= container_offset + container_size ||
              field_bit_offset + width > container_bits {
              let padding = (container_align - offset % container_align) %
                container_align
              container_offset = offset + padding
              field_bit_offset = 0
            }
            current_bit_offset = container_offset * 8 + field_bit_offset
          }
          layout.push(
            (
              field.name,
              field.ty,
              container_offset,
              container_size,
              field_bit_offset,
              width,
            ),
          )
          in_bitfield_run = true
          current_bit_offset = current_bit_offset + width
          let end_offset = (current_bit_offset + 7) / 8
          if end_offset > offset {
            offset = end_offset
          }
        }
      }
    }
  }
  layout
}

///|
fn Parser::const_union_layout(
  self : Parser,
  decl : StructDecl,
) -> Array[(String, Type, Int, Int, Int, Int)] {
  let layout = []
  for field in decl.fields {
    if field.name == "" && parser_is_anon_type(field.ty) {
      for f in self.const_flatten_anon_fields(field.ty, 0) {
        layout.push(f)
      }
    } else {
      let size = self.const_type_size(field.ty)
      match field.bit_width {
        None => layout.push((field.name, field.ty, 0, size, 0, 0))
        Some(width) =>
          if width != 0 {
            layout.push((field.name, field.ty, 0, size, 0, width))
          }
      }
    }
  }
  layout
}

///|
fn Parser::const_offset_of(self : Parser, ty : Type, field : String) -> Int? {
  let name = match ty {
    Struct(n) | Union(n) => n
    _ => return None
  }
  if !self.struct_decls.contains(name) {
    return None
  }
  let decl = self.struct_decls[name]
  let layout = if decl.is_union {
    self.const_union_layout(decl)
  } else {
    self.const_struct_layout(decl)
  }
  for item in layout {
    if item.0 == field {
      return Some(item.2)
    }
  }
  None
}

///|
fn Parser::const_member_type(self : Parser, ty : Type, field : String) -> Type? {
  let name = match ty {
    Struct(n) | Union(n) => n
    Pointer(Struct(n)) | Pointer(Union(n)) => n
    _ => return None
  }
  if !self.struct_decls.contains(name) {
    return None
  }
  let decl = self.struct_decls[name]
  let layout = if decl.is_union {
    self.const_union_layout(decl)
  } else {
    self.const_struct_layout(decl)
  }
  for item in layout {
    if item.0 == field {
      return Some(item.1)
    }
  }
  None
}

///|
fn type_of_expr(expr : Expr) -> Type {
  match expr {
    Number(_) => SInt
    FloatLiteral(_) => Double
    String(_) => Pointer(SChar)
    Var(_) => SInt // unknown, assume int
    Binary(_, _, _) => SInt
    Unary(_, _) => SInt
    Call(_, _) => SInt
    Assign(_, rhs) => type_of_expr(rhs)
    MemberAccess(_, _) => SInt
    Deref(_) => SInt
    AddrOf(_) => Pointer(SInt)
    ArrayAccess(_, _) => SInt
    Sizeof(_) => SInt
    SizeofExpr(_) => SInt
    Cast(ty, _) => ty
    PrefixInc(_) => SInt
    PrefixDec(_) => SInt
    PostfixInc(_) => SInt
    PostfixDec(_) => SInt
    Ternary(_, a, _) => type_of_expr(a)
    LabelAddr(_) => Pointer(Void)
    VaArg(_, ty) => ty
    OffsetOf(_, _) => SInt
    Array(_) => SInt
    CompoundLiteral(ty, _, _) => ty
    DesignatedField(_, e) => type_of_expr(e)
    DesignatedIndex(_, e) => type_of_expr(e)
    DesignatedRange(_, _, e) => type_of_expr(e)
  }
}

///|
fn Parser::const_expr_type(self : Parser, expr : Expr) -> Type {
  match expr {
    Sizeof(_) | SizeofExpr(_) | OffsetOf(_, _) => ULong
    Cast(ty, _) => ty
    Var(name) =>
      if self.value_types.contains(name) {
        self.value_types[name]
      } else {
        type_of_expr(expr)
      }
    AddrOf(e) => Pointer(self.const_expr_type(e))
    Deref(e) =>
      match self.const_expr_type(e) {
        Pointer(elem) | Array(elem, _) => elem
        _ => SInt
      }
    ArrayAccess(e, _) =>
      match self.const_expr_type(e) {
        Pointer(elem) | Array(elem, _) => elem
        _ => SInt
      }
    MemberAccess(obj, field) =>
      match self.const_member_type(self.const_expr_type(obj), field) {
        Some(ty) => ty
        None => SInt
      }
    String(s) => Array(SChar, s.length() + 1)
    FloatLiteral(_) => Double
    Number(_) => SInt
    CompoundLiteral(ty, _, _) => ty
    DesignatedField(_, e) => self.const_expr_type(e)
    DesignatedIndex(_, e) => self.const_expr_type(e)
    DesignatedRange(_, _, e) => self.const_expr_type(e)
    Ternary(_, a, _) => self.const_expr_type(a)
    Assign(_, rhs) => self.const_expr_type(rhs)
    _ => type_of_expr(expr)
  }
}
