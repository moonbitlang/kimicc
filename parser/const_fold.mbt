///|
fn const_literal_string_arg(expr : Expr) -> String? {
  match expr {
    String(value) => Some(value)
    Cast(_, inner) => const_literal_string_arg(inner)
    _ => None
  }
}

///|
fn Parser::const_object_size_lvalue_type(self : Parser, expr : Expr) -> Type? {
  match expr {
    Var(name) =>
      if self.value_types.contains(name) {
        Some(self.value_types[name])
      } else {
        None
      }
    ArrayAccess(base, _) =>
      match self.const_object_size_lvalue_type(base) {
        Some(base_ty) => base_ty.pointer_or_array_element()
        None => None
      }
    MemberAccess(obj, field) =>
      match self.const_object_size_lvalue_type(obj) {
        Some(obj_ty) => self.const_member_type(obj_ty, field)
        None => None
      }
    _ => None
  }
}

///|
fn Parser::const_object_size_var_fact(
  self : Parser,
  name : String,
) -> @ctype.ObjectSizeFact? {
  if self.value_types.contains(name) {
    let size = self.const_type_size(self.value_types[name])
    Some({ whole: size, subobject: size })
  } else {
    None
  }
}

///|
fn Parser::const_object_size_array_element_fact(
  self : Parser,
  base_ty : Type,
  index : Expr,
  base_fact : @ctype.ObjectSizeFact,
) -> @ctype.ObjectSizeFact? {
  match base_ty.core_type() {
    Array(elem, n) =>
      match self.fold_const(index) {
        Some(raw_index) =>
          base_fact.array_element(n, self.const_type_size(elem), raw_index)
        None => None
      }
    _ => None
  }
}

///|
fn Parser::const_object_size_lvalue_fact(
  self : Parser,
  expr : Expr,
) -> @ctype.ObjectSizeFact? {
  match expr {
    Var(name) => self.const_object_size_var_fact(name)
    ArrayAccess(base, index) =>
      match
        (
          self.const_object_size_lvalue_type(base),
          self.const_object_size_lvalue_fact(base),
        ) {
        (Some(base_ty), Some(base_fact)) =>
          self.const_object_size_array_element_fact(base_ty, index, base_fact)
        _ => None
      }
    MemberAccess(obj, field) =>
      match
        (
          self.const_object_size_lvalue_type(obj),
          self.const_object_size_lvalue_fact(obj),
        ) {
        (Some(obj_ty), Some(obj_fact)) =>
          match self.const_field_layout(obj_ty, field) {
            Some((_, field_ty, offset, _, _, _)) =>
              obj_fact.member_field(offset, self.const_type_size(field_ty))
            None => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn Parser::const_object_size_offset_expr_fact(
  self : Parser,
  base : Expr,
  offset_expr : Expr,
) -> @ctype.ObjectSizeFact? {
  match
    (
      self.const_object_size_expr_fact(base),
      self.fold_const(offset_expr),
      self.const_expr_type(base).pointer_or_array_element(),
    ) {
    (Some(fact), Some(index), Some(elem)) =>
      if index < 0L {
        None
      } else {
        fact.subtract_offset(index.to_int() * self.const_type_size(elem))
      }
    _ => None
  }
}

///|
fn Parser::const_object_size_expr_fact(
  self : Parser,
  expr : Expr,
) -> @ctype.ObjectSizeFact? {
  match expr {
    Cast(_, inner) => self.const_object_size_expr_fact(inner)
    AddrOf(inner) => self.const_object_size_lvalue_fact(inner)
    Binary("+", lhs, rhs) =>
      match self.const_object_size_offset_expr_fact(lhs, rhs) {
        Some(fact) => Some(fact)
        None => self.const_object_size_offset_expr_fact(rhs, lhs)
      }
    Var(name) =>
      if self.value_types.contains(name) {
        let ty = self.value_types[name]
        match ty.core_type() {
          Array(_, _) => self.const_object_size_var_fact(name)
          _ => None
        }
      } else {
        None
      }
    MemberAccess(_, _) =>
      match self.const_object_size_lvalue_type(expr) {
        Some(ty) =>
          match ty.core_type() {
            Array(_, _) => self.const_object_size_lvalue_fact(expr)
            _ => None
          }
        None => None
      }
    _ => None
  }
}

///|
fn Parser::const_builtin_object_size_value(
  self : Parser,
  args : Array[Expr],
  mode : Int64,
) -> Int64 {
  if args.length() > 0 {
    match const_literal_string_arg(args[0]) {
      Some(value) => return @ctype.string_literal_object_size(value)
      None => ()
    }
    return @ctype.object_size_fact_result(
      self.const_object_size_expr_fact(args[0]),
      mode,
    )
  }
  @ctype.object_size_unknown(mode)
}

///|
fn Parser::long_double_size(self : Parser) -> Int {
  match self.target {
    DarwinArm64 => 8
    LinuxAmd64 => 16
  }
}

///|
fn Parser::long_double_align(self : Parser) -> Int {
  match self.target {
    DarwinArm64 => 8
    LinuxAmd64 => 16
  }
}

///|
fn Parser::float16_size(_self : Parser) -> Int {
  2
}

///|
fn Parser::float16_align(_self : Parser) -> Int {
  2
}

///|
fn Parser::float128_size(self : Parser) -> Int {
  match self.target {
    DarwinArm64 => abort("__float128 size is not supported")
    LinuxAmd64 => 16
  }
}

///|
fn Parser::float128_align(self : Parser) -> Int {
  match self.target {
    DarwinArm64 => abort("__float128 alignment is not supported")
    LinuxAmd64 => 16
  }
}

///|
fn const_number_type(bits : Int64) -> Type {
  @ctype.integer_constant_token_type(bits)
}

///|
fn Parser::fold_scalar_builtin_const(
  self : Parser,
  name : String,
  args : Array[Expr],
) -> @ctype.IntegerConstant? {
  let arg0 = if args.length() > 0 { self.fold_const_int(args[0]) } else { None }
  let arg1 = if args.length() > 1 { self.fold_const_int(args[1]) } else { None }
  let first_ty = if args.length() > 0 {
    self.const_expr_type(args[0])
  } else {
    SInt
  }
  @ctype.integer_scalar_builtin_constant_from_folded_args(
    name,
    args.length(),
    arg0,
    arg1,
    first_ty,
  )
}

///|
fn Parser::fold_const_int(
  self : Parser,
  expr : Expr,
) -> @ctype.IntegerConstant? {
  match expr {
    Number(n) => Some(@ctype.integer_constant(n, const_number_type(n)))
    Binary("+", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => @ctype.integer_constant_binary_arith("+", x, y)
        _ => None
      }
    Binary("-", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => @ctype.integer_constant_binary_arith("-", x, y)
        _ => None
      }
    Binary("*", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => @ctype.integer_constant_binary_arith("*", x, y)
        _ => None
      }
    Binary("/", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => @ctype.integer_constant_divide("/", x, y)
        _ => None
      }
    Binary("%", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => @ctype.integer_constant_divide("%", x, y)
        _ => None
      }
    Binary("|", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => @ctype.integer_constant_binary_arith("|", x, y)
        _ => None
      }
    Binary("&", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => @ctype.integer_constant_binary_arith("&", x, y)
        _ => None
      }
    Binary("^", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => @ctype.integer_constant_binary_arith("^", x, y)
        _ => None
      }
    Binary("<<", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => @ctype.integer_constant_shift("<<", x, y)
        _ => None
      }
    Binary(">>", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => @ctype.integer_constant_shift(">>", x, y)
        _ => None
      }
    Binary("==", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(
            @ctype.integer_constant_bool(
              @ctype.integer_constant_equal_compare(x, y),
            ),
          )
        _ => None
      }
    Binary("!=", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(
            @ctype.integer_constant_bool(
              !@ctype.integer_constant_equal_compare(x, y),
            ),
          )
        _ => None
      }
    Binary("<", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(
            @ctype.integer_constant_bool(
              @ctype.integer_constant_rel_compare("<", x, y),
            ),
          )
        _ => None
      }
    Binary(">", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(
            @ctype.integer_constant_bool(
              @ctype.integer_constant_rel_compare(">", x, y),
            ),
          )
        _ => None
      }
    Binary("<=", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(
            @ctype.integer_constant_bool(
              @ctype.integer_constant_rel_compare("<=", x, y),
            ),
          )
        _ => None
      }
    Binary(">=", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) =>
          Some(
            @ctype.integer_constant_bool(
              @ctype.integer_constant_rel_compare(">=", x, y),
            ),
          )
        _ => None
      }
    Binary("&&", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => @ctype.integer_constant_logical("&&", x, y)
        _ => None
      }
    Binary("||", a, b) =>
      match (self.fold_const_int(a), self.fold_const_int(b)) {
        (Some(x), Some(y)) => @ctype.integer_constant_logical("||", x, y)
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
        Some(x) => @ctype.integer_constant_unary("-", x)
        _ => None
      }
    Unary("+", e) =>
      match self.fold_const_int(e) {
        Some(x) => @ctype.integer_constant_unary("+", x)
        _ => None
      }
    Unary("~", e) =>
      match self.fold_const_int(e) {
        Some(x) => @ctype.integer_constant_unary("~", x)
        _ => None
      }
    Unary("!", e) =>
      match self.fold_const_int(e) {
        Some(x) => @ctype.integer_constant_unary("!", x)
        _ => None
      }
    Cast(ty, e) =>
      match self.fold_const_int(e) {
        Some(value) => Some(value.cast(ty))
        None => None
      }
    Sizeof(ty) =>
      Some(@ctype.integer_constant(self.const_type_size(ty).to_int64(), ULong))
    SizeofExpr(e) =>
      Some(
        @ctype.integer_constant(
          match e {
            String(value) => @ctype.string_literal_object_size(value)
            _ => self.const_type_size(self.const_expr_type(e)).to_int64()
          },
          ULong,
        ),
      )
    Alignof(ty) =>
      Some(@ctype.integer_constant(self.const_type_align(ty).to_int64(), ULong))
    AlignofExpr(e) =>
      Some(
        @ctype.integer_constant(
          match e {
            String(value) =>
              self
              .const_type_align(
                Array(SChar, @ctype.string_literal_array_length(value)),
              )
              .to_int64()
            _ => self.const_type_align(self.const_expr_type(e)).to_int64()
          },
          ULong,
        ),
      )
    OffsetOf(ty, path) =>
      match self.const_offset_of(ty, path) {
        Some(offset) => Some(@ctype.integer_constant(offset.to_int64(), ULong))
        None => None
      }
    DesignatedField(_, e) => self.fold_const_int(e)
    DesignatedIndex(_, e) => self.fold_const_int(e)
    DesignatedRange(_, _, e) => self.fold_const_int(e)
    Call(Var(name), args) =>
      match @ctype.builtin_object_size_call_info(name) {
        Some(_) => {
          let mode = if args.length() > 1 {
            match self.fold_const(args[1]) {
              Some(value) => value
              None => return None
            }
          } else {
            0L
          }
          Some(
            @ctype.integer_constant(
              self.const_builtin_object_size_value(args, mode),
              ULong,
            ),
          )
        }
        None =>
          match @ctype.builtin_constant_query_call_info(name) {
            Some(kind) =>
              match
                @ctype.builtin_constant_query_result(
                  kind,
                  args.length() > 0 && self.fold_const(args[0]) is Some(_),
                ) {
                Some(value) => Some(@ctype.integer_constant(value, SInt))
                None => None
              }
            None => self.fold_scalar_builtin_const(name, args)
          }
      }
    Array(_) => None
    CompoundLiteral(_, _, _) => None
    _ => None
  }
}

///|
fn Parser::fold_const(self : Parser, expr : Expr) -> Int64? {
  match self.fold_const_int(expr) {
    Some(value) => Some(value.bits)
    None => None
  }
}

///|
fn Parser::const_type_size(self : Parser, ty : Type) -> Int {
  match ty {
    Void => 0
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt | Float => 4
    Float16 => self.float16_size()
    Float128 => self.float128_size()
    LongDouble => self.long_double_size()
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    SInt128 | UInt128 => 16
    Array(elem, n) => self.const_type_size(elem) * n
    Atomic(inner) => self.const_type_size(inner)
    Aligned(inner, _) => self.const_type_size(inner)
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
    Float16 => self.float16_align()
    Float128 => self.float128_align()
    LongDouble => self.long_double_align()
    SLong
    | ULong
    | SLongLong
    | ULongLong
    | Double
    | Pointer(_)
    | FuncPtr(_, _, _) => 8
    SInt128 | UInt128 => 16
    Array(elem, _) => self.const_type_align(elem)
    Atomic(inner) => self.const_type_align(inner)
    Aligned(inner, align) => {
      let inner_align = self.const_type_align(inner)
      if align > inner_align {
        align
      } else {
        inner_align
      }
    }
    Struct(name) => self.const_struct_align(name)
    Union(name) => self.const_union_align(name)
  }
}

///|
fn Parser::const_struct_size(self : Parser, name : String) -> Int {
  if !self.struct_decls.contains(name) {
    return 8
  }
  let decl = self.struct_decls[name]
  let layout = self.const_struct_layout(decl)
  let mut max_end = 0
  let mut max_align = 1
  for field in layout {
    let end = field.2 + field.3
    if end > max_end {
      max_end = end
    }
    if !decl.is_packed {
      let align = self.const_type_align(field.1)
      if align > max_align {
        max_align = align
      }
    }
  }
  max_end + (max_align - max_end % max_align) % max_align
}

///|
fn Parser::const_union_size(self : Parser, name : String) -> Int {
  if !self.struct_decls.contains(name) {
    return 8
  }
  let decl = self.struct_decls[name]
  let mut max_size = 0
  let mut max_align = 1
  for field in decl.fields {
    let size = self.const_type_size(field.ty)
    if size > max_size {
      max_size = size
    }
    if !decl.is_packed {
      let align = self.const_type_align(field.ty)
      if align > max_align {
        max_align = align
      }
    }
  }
  max_size + (max_align - max_size % max_align) % max_align
}

///|
fn Parser::const_struct_align(self : Parser, name : String) -> Int {
  if !self.struct_decls.contains(name) {
    return 8
  }
  if self.struct_decls[name].is_packed {
    return 1
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
    if field.0 == "" && field.1.is_anonymous_aggregate() {
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
    if field.name == "" && field.ty.is_anonymous_aggregate() {
      let align = if decl.is_packed {
        1
      } else {
        self.const_type_align(field.ty)
      }
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
        let align = if decl.is_packed {
          1
        } else {
          self.const_type_align(field.ty)
        }
        offset += (align - offset % align) % align
        layout.push((field.name, field.ty, offset, size, 0, 0))
        offset += size
        in_bitfield_run = false
        current_bit_offset = 0
      }
      Some(width) => {
        let container_size = self.const_type_size(field.ty)
        let container_align = if decl.is_packed {
          1
        } else {
          self.const_type_align(field.ty)
        }
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
    if field.name == "" && field.ty.is_anonymous_aggregate() {
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
fn Parser::const_field_layout(
  self : Parser,
  ty : Type,
  field : String,
) -> (String, Type, Int, Int, Int, Int)? {
  let name = match ty {
    Struct(n) | Union(n) => n
    Aligned(inner, _) | Atomic(inner) =>
      return self.const_field_layout(inner, field)
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
      return Some(item)
    }
  }
  None
}

///|
fn Parser::const_offset_of(
  self : Parser,
  ty : Type,
  path : Array[OffsetDesignator],
) -> Int? {
  let mut current_ty = ty
  let mut offset = 0
  for designator in path {
    match designator {
      OffsetField(field) =>
        match self.const_field_layout(current_ty, field) {
          Some((_, field_ty, field_offset, _, _, _)) => {
            offset += field_offset
            current_ty = field_ty
          }
          None => return None
        }
      OffsetIndex(index) =>
        match current_ty.array_element() {
          Some(elem) => {
            offset += index.to_int() * self.const_type_size(elem)
            current_ty = elem
          }
          None => return None
        }
    }
  }
  Some(offset)
}

///|
fn Parser::const_member_type(self : Parser, ty : Type, field : String) -> Type? {
  match ty {
    Pointer(inner) => self.const_member_type(inner, field)
    _ =>
      match self.const_field_layout(ty, field) {
        Some((_, field_ty, _, _, _, _)) => Some(field_ty)
        None => None
      }
  }
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
    CompoundAssign(_, lhs, _) => type_of_expr(lhs)
    MemberAccess(_, _) => SInt
    Deref(_) => SInt
    AddrOf(_) => Pointer(SInt)
    ArrayAccess(_, _) => SInt
    Sizeof(_) => SInt
    SizeofExpr(_) => SInt
    Alignof(_) => SInt
    AlignofExpr(_) => SInt
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
fn Parser::const_builtin_return_type(
  self : Parser,
  name : String,
  args : Array[Expr],
) -> Type? {
  let arg_types : Array[Type] = []
  for arg in args {
    arg_types.push(self.const_expr_type(arg))
  }
  let choose_cond = match @ctype.builtin_return_condition_arg_index(name) {
    Some(index) =>
      if index < args.length() {
        self.fold_const(args[index])
      } else {
        None
      }
    None => None
  }
  @ctype.builtin_return_type(name, arg_types, choose_cond)
}

///|
fn Parser::const_expr_type(self : Parser, expr : Expr) -> Type {
  match expr {
    Sizeof(_) | SizeofExpr(_) | Alignof(_) | AlignofExpr(_) | OffsetOf(_, _) =>
      ULong
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
    String(s) => Array(SChar, @ctype.string_literal_array_length(s))
    FloatLiteral(_) => Double
    Number(_) => SInt
    CompoundLiteral(ty, _, _) => ty
    Call(Var(name), args) =>
      match self.const_builtin_return_type(name, args) {
        Some(ty) => ty
        None => type_of_expr(expr)
      }
    DesignatedField(_, e) => self.const_expr_type(e)
    DesignatedIndex(_, e) => self.const_expr_type(e)
    DesignatedRange(_, _, e) => self.const_expr_type(e)
    Binary(",", _, rhs) => self.const_expr_type(rhs)
    Ternary(_, a, _) => self.const_expr_type(a)
    Assign(_, rhs) => self.const_expr_type(rhs)
    CompoundAssign(_, lhs, _) => self.const_expr_type(lhs)
    _ => type_of_expr(expr)
  }
}
