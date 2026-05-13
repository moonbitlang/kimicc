///|
/// Function signature facts collected from a parsed translation unit.
pub(all) struct FuncSig {
  ret : @parser.Type
  params : Array[@parser.Type]
  variadic : Bool
  defined : Bool
  weak : Bool
} derive(Eq)

///|
/// Lexical expression-typing context used by MIR semantic queries.
pub(all) struct Scope {
  locals : Map[String, @parser.Type]
  current_func : String
} derive(Eq)

///|
/// Aggregate field layout in target object bytes.
///
/// `bit_width` is `Some(width)` for bit-fields and `None` for ordinary fields.
pub(all) struct FieldLayout {
  name : String
  ty : @parser.Type
  offset : Int
  size : Int
  bit_offset : Int
  bit_width : Int?
} derive(Eq)

///|
/// Struct or union layout facts for the selected target.
pub(all) struct AggregateLayout {
  fields : Array[FieldLayout]
  size : Int
  align : Int
  is_union : Bool
  is_packed : Bool
} derive(Eq)

///|
/// Target-sensitive C semantic facts derived from the parser AST.
pub(all) struct Program {
  target : @target.Target
  source : @parser.Program
  funcs : Map[String, FuncSig]
  globals : Map[String, @parser.GlobalDecl]
  structs : Map[String, @parser.StructDecl]
  layouts : Map[String, AggregateLayout]
}

///|
pub fn Scope::empty() -> Scope {
  { locals: {}, current_func: "" }
}

///|
fn global_has_init(g : @parser.GlobalDecl) -> Bool {
  g.init is Some(_)
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
pub fn lower(source : @parser.Program, target : @target.Target) -> Program {
  let funcs : Map[String, FuncSig] = {}
  for decl in source.decls {
    let param_types : Array[@parser.Type] = []
    for param in decl.params {
      param_types.push(param.ty)
    }
    funcs[decl.name] = {
      ret: decl.ret,
      params: param_types,
      variadic: decl.variadic,
      defined: decl.body is Some(_) || decl.symbol_alias is Some(_),
      weak: decl.is_weak,
    }
  }
  let globals : Map[String, @parser.GlobalDecl] = {}
  for g in source.globals {
    if !globals.contains(g.name) ||
      should_replace_global_decl(globals[g.name], g) {
      globals[g.name] = g
    }
  }
  let structs : Map[String, @parser.StructDecl] = {}
  for decl in source.structs {
    structs[decl.name] = decl
  }
  { target, source, funcs, globals, structs, layouts: {} }
}

///|
fn Program::core_type(self : Program, ty : @parser.Type) -> @parser.Type {
  match ty {
    Atomic(inner) | Aligned(inner, _) => self.core_type(inner)
    _ => ty
  }
}

///|
fn Program::pointer_element(self : Program, ty : @parser.Type) -> @parser.Type? {
  match self.core_type(ty) {
    Pointer(elem) | Array(elem, _) => Some(elem)
    _ => None
  }
}

///|
fn Program::offset_array_element(
  self : Program,
  ty : @parser.Type,
) -> @parser.Type? {
  match self.core_type(ty) {
    Array(elem, _) => Some(elem)
    _ => None
  }
}

///|
fn is_unsigned_integer_type(ty : @parser.Type) -> Bool {
  match ty {
    UChar | UShort | UInt | ULong | ULongLong | UInt128 => true
    _ => false
  }
}

///|
fn integer_rank(ty : @parser.Type) -> Int {
  match ty {
    Bool | SChar | UChar => 1
    SShort | UShort => 2
    SInt | UInt => 3
    SLong | ULong => 4
    SLongLong | ULongLong => 5
    SInt128 | UInt128 => 6
    _ => 0
  }
}

///|
fn integer_width_bits(ty : @parser.Type) -> Int {
  match ty {
    Bool | SChar | UChar => 8
    SShort | UShort => 16
    SInt | UInt => 32
    SLong | ULong | SLongLong | ULongLong | Pointer(_) | FuncPtr(_, _, _) => 64
    SInt128 | UInt128 => 128
    _ => 0
  }
}

///|
fn unsigned_type_for_rank(rank : Int) -> @parser.Type {
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
fn signed_type_for_rank(rank : Int) -> @parser.Type {
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
fn unary_integer_result_type(ty : @parser.Type) -> @parser.Type {
  match ty {
    Bool | SChar | UChar | SShort | UShort => SInt
    _ => ty
  }
}

///|
fn Program::is_floating_type(self : Program, ty : @parser.Type) -> Bool {
  match self.core_type(ty) {
    Float | Double => true
    LongDouble => self.target is DarwinArm64
    _ => false
  }
}

///|
fn Program::unary_numeric_result_type(
  self : Program,
  ty : @parser.Type,
) -> @parser.Type {
  if self.is_floating_type(ty) {
    ty
  } else {
    unary_integer_result_type(ty)
  }
}

///|
fn integer_common_type(
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
) -> @parser.Type {
  let lhs_ty = unary_integer_result_type(lhs_ty)
  let rhs_ty = unary_integer_result_type(rhs_ty)
  if lhs_ty == rhs_ty {
    return lhs_ty
  }
  let lhs_unsigned = is_unsigned_integer_type(lhs_ty)
  let rhs_unsigned = is_unsigned_integer_type(rhs_ty)
  let lhs_rank = integer_rank(lhs_ty)
  let rhs_rank = integer_rank(rhs_ty)
  if lhs_unsigned == rhs_unsigned {
    let rank = if lhs_rank > rhs_rank { lhs_rank } else { rhs_rank }
    if lhs_unsigned {
      unsigned_type_for_rank(rank)
    } else {
      signed_type_for_rank(rank)
    }
  } else {
    let unsigned_ty = if lhs_unsigned { lhs_ty } else { rhs_ty }
    let signed_ty = if lhs_unsigned { rhs_ty } else { lhs_ty }
    let unsigned_rank = integer_rank(unsigned_ty)
    let signed_rank = integer_rank(signed_ty)
    if unsigned_rank >= signed_rank {
      unsigned_ty
    } else if integer_width_bits(signed_ty) > integer_width_bits(unsigned_ty) {
      signed_ty
    } else {
      unsigned_type_for_rank(signed_rank)
    }
  }
}

///|
fn Program::binary_result_type(
  self : Program,
  op : String,
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
) -> @parser.Type {
  match op {
    "==" | "!=" | "<" | ">" | "<=" | ">=" | "&&" | "||" => SInt
    "," => rhs_ty
    "<<" | ">>" => unary_integer_result_type(lhs_ty)
    _ =>
      if self.is_floating_type(lhs_ty) || self.is_floating_type(rhs_ty) {
        if self.core_type(lhs_ty) == Double || self.core_type(rhs_ty) == Double {
          Double
        } else {
          Float
        }
      } else if lhs_ty.is_integer() && rhs_ty.is_integer() {
        integer_common_type(lhs_ty, rhs_ty)
      } else {
        SInt
      }
  }
}

///|
fn Program::ternary_result_type(
  self : Program,
  then_ty : @parser.Type,
  else_ty : @parser.Type,
) -> @parser.Type {
  match (self.core_type(then_ty), self.core_type(else_ty)) {
    (Array(elem, _), _) | (_, Array(elem, _)) => Pointer(elem)
    (Pointer(elem), _) | (_, Pointer(elem)) => Pointer(elem)
    (FuncPtr(ret, params, variadic), _) | (_, FuncPtr(ret, params, variadic)) =>
      FuncPtr(ret, params, variadic)
    _ =>
      if self.is_floating_type(then_ty) || self.is_floating_type(else_ty) {
        if self.core_type(then_ty) == Double ||
          self.core_type(else_ty) == Double {
          Double
        } else {
          Float
        }
      } else if then_ty.is_integer() && else_ty.is_integer() {
        integer_common_type(then_ty, else_ty)
      } else {
        then_ty
      }
  }
}

///|
fn number_literal_type(value : Int64) -> @parser.Type {
  if value < -2147483648L || value > 2147483647L {
    SLongLong
  } else {
    SInt
  }
}

///|
pub fn Program::type_size(self : Program, ty : @parser.Type) -> Int {
  match ty {
    Atomic(inner) | Aligned(inner, _) => self.type_size(inner)
    _ =>
      match self.core_type(ty) {
        Void => 0
        Bool | SChar | UChar => 1
        SShort | UShort => 2
        Float16 =>
          match self.target {
            DarwinArm64 => abort("_Float16 size is not supported")
            LinuxAmd64 => 2
          }
        SInt | UInt | Float => 4
        Float128 =>
          match self.target {
            DarwinArm64 => abort("__float128 size is not supported")
            LinuxAmd64 => 16
          }
        LongDouble =>
          match self.target {
            DarwinArm64 => 8
            LinuxAmd64 => 16
          }
        SLong
        | ULong
        | SLongLong
        | ULongLong
        | Double
        | Pointer(_)
        | FuncPtr(_, _, _) => 8
        SInt128 | UInt128 => 16
        Array(elem, n) => self.type_size(elem) * n
        Struct(name) | Union(name) => self.aggregate_layout_by_name(name).size
        Atomic(_) | Aligned(_, _) => abort("unreachable wrapped type")
      }
  }
}

///|
pub fn Program::type_align(self : Program, ty : @parser.Type) -> Int {
  match ty {
    Atomic(inner) => self.type_align(inner)
    Aligned(inner, align) => {
      let inner_align = self.type_align(inner)
      if align > inner_align {
        align
      } else {
        inner_align
      }
    }
    _ =>
      match self.core_type(ty) {
        Void => 1
        Bool | SChar | UChar => 1
        SShort | UShort => 2
        Float16 =>
          match self.target {
            DarwinArm64 => abort("_Float16 alignment is not supported")
            LinuxAmd64 => 2
          }
        SInt | UInt | Float => 4
        Float128 =>
          match self.target {
            DarwinArm64 => abort("__float128 alignment is not supported")
            LinuxAmd64 => 16
          }
        LongDouble =>
          match self.target {
            DarwinArm64 => 8
            LinuxAmd64 => 16
          }
        SLong
        | ULong
        | SLongLong
        | ULongLong
        | Double
        | Pointer(_)
        | FuncPtr(_, _, _) => 8
        SInt128 | UInt128 => 16
        Array(elem, _) => self.type_align(elem)
        Struct(name) | Union(name) => self.aggregate_layout_by_name(name).align
        Atomic(_) | Aligned(_, _) => abort("unreachable wrapped type")
      }
  }
}

///|
fn align_to(value : Int, align : Int) -> Int {
  if align <= 1 {
    value
  } else {
    let rem = value % align
    if rem == 0 {
      value
    } else {
      value + align - rem
    }
  }
}

///|
fn is_anon_type(ty : @parser.Type) -> Bool {
  match ty {
    Struct(name) | Union(name) => name.has_prefix("__anon_")
    _ => false
  }
}

///|
fn Program::flatten_anon_fields(
  self : Program,
  ty : @parser.Type,
  base_offset : Int,
) -> Array[FieldLayout] {
  let name = match self.core_type(ty) {
    Struct(n) | Union(n) => n
    _ => return []
  }
  let layout = self.aggregate_layout_by_name(name)
  let fields : Array[FieldLayout] = []
  for field in layout.fields {
    if field.name == "" && is_anon_type(field.ty) {
      for
        inner in self.flatten_anon_fields(field.ty, base_offset + field.offset) {
        fields.push(inner)
      }
    } else {
      fields.push({
        name: field.name,
        ty: field.ty,
        offset: base_offset + field.offset,
        size: field.size,
        bit_offset: field.bit_offset,
        bit_width: field.bit_width,
      })
    }
  }
  fields
}

///|
fn Program::compute_struct_layout(
  self : Program,
  decl : @parser.StructDecl,
) -> AggregateLayout {
  let fields : Array[FieldLayout] = []
  let mut offset = 0
  let mut in_bitfield_run = false
  let mut current_bit_offset = 0
  for field in decl.fields {
    if field.name == "" && is_anon_type(field.ty) {
      let align = if decl.is_packed { 1 } else { self.type_align(field.ty) }
      offset = align_to(offset, align)
      for inner in self.flatten_anon_fields(field.ty, offset) {
        fields.push(inner)
      }
      offset += self.type_size(field.ty)
      in_bitfield_run = false
      current_bit_offset = 0
      continue
    }
    match field.bit_width {
      None => {
        let align = if decl.is_packed { 1 } else { self.type_align(field.ty) }
        offset = align_to(offset, align)
        let size = self.type_size(field.ty)
        fields.push({
          name: field.name,
          ty: field.ty,
          offset,
          size,
          bit_offset: 0,
          bit_width: None,
        })
        offset += size
        in_bitfield_run = false
        current_bit_offset = 0
      }
      Some(width) => {
        let container_size = self.type_size(field.ty)
        let container_align = if decl.is_packed {
          1
        } else {
          self.type_align(field.ty)
        }
        let container_bits = container_size * 8
        if width == 0 {
          offset = align_to(offset, container_align)
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
              container_offset = align_to(offset, container_align)
              field_bit_offset = 0
            }
            current_bit_offset = container_offset * 8 + field_bit_offset
          }
          fields.push({
            name: field.name,
            ty: field.ty,
            offset: container_offset,
            size: container_size,
            bit_offset: field_bit_offset,
            bit_width: Some(width),
          })
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
  let mut max_end = 0
  let mut max_align = 1
  for field in fields {
    let end = field.offset + field.size
    if end > max_end {
      max_end = end
    }
    if !decl.is_packed {
      let field_align = self.type_align(field.ty)
      if field_align > max_align {
        max_align = field_align
      }
    }
  }
  {
    fields,
    size: align_to(max_end, max_align),
    align: if decl.is_packed {
      1
    } else {
      max_align
    },
    is_union: false,
    is_packed: decl.is_packed,
  }
}

///|
fn Program::compute_union_layout(
  self : Program,
  decl : @parser.StructDecl,
) -> AggregateLayout {
  let fields : Array[FieldLayout] = []
  let mut max_size = 0
  let mut max_align = 1
  for field in decl.fields {
    if field.name == "" && is_anon_type(field.ty) {
      for inner in self.flatten_anon_fields(field.ty, 0) {
        fields.push(inner)
      }
      let size = self.type_size(field.ty)
      if size > max_size {
        max_size = size
      }
      let align = self.type_align(field.ty)
      if !decl.is_packed && align > max_align {
        max_align = align
      }
      continue
    }
    let size = self.type_size(field.ty)
    if size > max_size {
      max_size = size
    }
    let align = self.type_align(field.ty)
    if !decl.is_packed && align > max_align {
      max_align = align
    }
    match field.bit_width {
      Some(width) =>
        if width > 0 {
          fields.push({
            name: field.name,
            ty: field.ty,
            offset: 0,
            size,
            bit_offset: 0,
            bit_width: Some(width),
          })
        }
      None =>
        fields.push({
          name: field.name,
          ty: field.ty,
          offset: 0,
          size,
          bit_offset: 0,
          bit_width: None,
        })
    }
  }
  {
    fields,
    size: align_to(max_size, max_align),
    align: if decl.is_packed {
      1
    } else {
      max_align
    },
    is_union: true,
    is_packed: decl.is_packed,
  }
}

///|
fn Program::ensure_layout(self : Program, name : String) -> Unit {
  if self.layouts.contains(name) {
    return
  }
  if !self.structs.contains(name) {
    self.layouts[name] = {
      fields: [],
      size: 8,
      align: 8,
      is_union: false,
      is_packed: false,
    }
    return
  }
  let decl = self.structs[name]
  self.layouts[name] = if decl.is_union {
    self.compute_union_layout(decl)
  } else {
    self.compute_struct_layout(decl)
  }
}

///|
fn Program::aggregate_layout_by_name(
  self : Program,
  name : String,
) -> AggregateLayout {
  self.ensure_layout(name)
  self.layouts[name]
}

///|
pub fn Program::field_layout(
  self : Program,
  ty : @parser.Type,
  field : String,
) -> FieldLayout? {
  let name = match self.core_type(ty) {
    Struct(n) | Union(n) => n
    _ => return None
  }
  let layout = self.aggregate_layout_by_name(name)
  for item in layout.fields {
    if item.name == field {
      return Some(item)
    }
  }
  None
}

///|
pub fn Program::offset_of_path(
  self : Program,
  ty : @parser.Type,
  path : Array[@parser.OffsetDesignator],
) -> Int? {
  let mut current_ty = ty
  let mut offset = 0
  for designator in path {
    match designator {
      OffsetField(field) =>
        match self.field_layout(current_ty, field) {
          Some(layout) => {
            offset += layout.offset
            current_ty = layout.ty
          }
          None => return None
        }
      OffsetIndex(index) =>
        match self.offset_array_element(current_ty) {
          Some(elem) => {
            offset += index.to_int() * self.type_size(elem)
            current_ty = elem
          }
          None => return None
        }
    }
  }
  Some(offset)
}

///|
pub fn Program::global_expr_type(
  self : Program,
  expr : @parser.Expr,
) -> @parser.Type {
  match expr {
    Number(value) => number_literal_type(value)
    FloatLiteral(_) => Double
    Var(name) =>
      if self.globals.contains(name) {
        self.globals[name].ty
      } else if self.funcs.contains(name) {
        let sig = self.funcs[name]
        FuncPtr(sig.ret, sig.params, sig.variadic)
      } else {
        Pointer(Void)
      }
    String(value) => Array(SChar, value.length() + 1)
    CompoundLiteral(ty, _, _) => ty
    DesignatedField(_, e) | DesignatedIndex(_, e) | DesignatedRange(_, _, e) =>
      self.global_expr_type(e)
    Cast(ty, _) => ty
    AddrOf(e) => Pointer(self.global_expr_type(e))
    Deref(e) =>
      match self.core_type(self.global_expr_type(e)) {
        Pointer(elem) | Array(elem, _) => elem
        _ => SInt
      }
    ArrayAccess(base, _) =>
      match self.pointer_element(self.global_expr_type(base)) {
        Some(elem) => elem
        None => SInt
      }
    MemberAccess(obj, field) =>
      match self.field_layout(self.global_expr_type(obj), field) {
        Some(layout) => layout.ty
        None => SInt
      }
    _ => SInt
  }
}

///|
fn Program::builtin_return_type(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  scope : Scope,
) -> @parser.Type? {
  match name {
    "__builtin_object_size" | "__builtin_dynamic_object_size" => Some(ULong)
    "__builtin_return_address"
    | "__builtin_frame_address"
    | "__builtin_extract_return_addr"
    | "__builtin_frob_return_addr" => Some(Pointer(Void))
    "__builtin_memcpy"
    | "__builtin_memmove"
    | "__builtin_memset"
    | "__builtin_memchr" => Some(Pointer(Void))
    "__builtin_strlen" => Some(ULong)
    "__builtin_memcmp" | "__builtin_strcmp" | "__builtin_strncmp" => Some(SInt)
    "__builtin_strcpy"
    | "__builtin_strchr"
    | "__builtin_strrchr"
    | "__builtin_strstr" => Some(Pointer(SChar))
    "__builtin_constant_p"
    | "__builtin_clz"
    | "__builtin_clzl"
    | "__builtin_clzll"
    | "__builtin_ctz"
    | "__builtin_ctzl"
    | "__builtin_ctzll"
    | "__builtin_ffs"
    | "__builtin_ffsl"
    | "__builtin_ffsll"
    | "__builtin_popcount"
    | "__builtin_popcountl"
    | "__builtin_popcountll"
    | "__builtin_parity"
    | "__builtin_parityl"
    | "__builtin_parityll"
    | "__builtin_abs"
    | "__builtin_flt_rounds" => Some(SInt)
    "__builtin_labs" => Some(SLong)
    "__builtin_llabs" => Some(SLongLong)
    "__builtin_is_aligned" => Some(Bool)
    "__builtin_align_up" | "__builtin_align_down" =>
      if args.length() > 0 {
        Some(self.expr_type(args[0], scope))
      } else {
        Some(ULong)
      }
    "__builtin_bswap16" => Some(UShort)
    "__builtin_bswap32"
    | "__builtin_rotateleft32"
    | "__builtin_rotateright32" => Some(UInt)
    "__builtin_bswap64"
    | "__builtin_rotateleft64"
    | "__builtin_rotateright64" => Some(ULongLong)
    "__builtin_bswap" =>
      if args.length() > 0 {
        Some(self.expr_type(args[0], scope))
      } else {
        Some(UInt)
      }
    "__builtin_rotateleft" | "__builtin_rotateright" =>
      if args.length() > 0 {
        Some(self.expr_type(args[0], scope))
      } else {
        Some(UInt)
      }
    "__builtin_assume_aligned" =>
      if args.length() > 0 {
        Some(self.expr_type(args[0], scope))
      } else {
        Some(Pointer(Void))
      }
    "__builtin_expect"
    | "__builtin_expect_with_probability"
    | "__builtin_unpredictable" =>
      if args.length() > 0 {
        Some(self.expr_type(args[0], scope))
      } else {
        Some(SLong)
      }
    "__builtin_choose_expr" =>
      if args.length() >= 3 {
        match self.fold_const(args[0], scope) {
          Some(0L) => Some(self.expr_type(args[2], scope))
          Some(_) => Some(self.expr_type(args[1], scope))
          None => Some(self.expr_type(args[1], scope))
        }
      } else {
        Some(SInt)
      }
    _ => None
  }
}

///|
pub fn Program::expr_type(
  self : Program,
  expr : @parser.Expr,
  scope : Scope,
) -> @parser.Type {
  match expr {
    Number(value) => number_literal_type(value)
    FloatLiteral(_) => Double
    String(_) => Pointer(SChar)
    Var(name) =>
      if scope.locals.contains(name) {
        scope.locals[name]
      } else if self.globals.contains(name) {
        self.globals[name].ty
      } else if self.funcs.contains(name) {
        let sig = self.funcs[name]
        FuncPtr(sig.ret, sig.params, sig.variadic)
      } else {
        SInt
      }
    Binary(op, lhs, rhs) => {
      let lhs_ty = self.expr_type(lhs, scope)
      let rhs_ty = self.expr_type(rhs, scope)
      if op == "-" &&
        self.pointer_element(lhs_ty) is Some(_) &&
        self.pointer_element(rhs_ty) is Some(_) {
        return SLong
      }
      match self.pointer_element(lhs_ty) {
        Some(elem) =>
          if (op == "+" || op == "-") && rhs_ty.is_integer() {
            return Pointer(elem)
          }
        None => ()
      }
      match self.pointer_element(rhs_ty) {
        Some(elem) =>
          if op == "+" && lhs_ty.is_integer() {
            return Pointer(elem)
          }
        None => ()
      }
      self.binary_result_type(op, lhs_ty, rhs_ty)
    }
    Unary("-", operand) | Unary("+", operand) =>
      self.unary_numeric_result_type(self.expr_type(operand, scope))
    Unary("!", _) => SInt
    Unary("~", operand) =>
      unary_integer_result_type(self.expr_type(operand, scope))
    Unary(_, operand) => self.expr_type(operand, scope)
    Call(func, args) =>
      match func {
        Var(name) =>
          match self.builtin_return_type(name, args, scope) {
            Some(ty) => ty
            None =>
              match self.expr_type(func, scope) {
                FuncPtr(ret, _, _) => ret
                _ => SInt
              }
          }
        _ =>
          match self.expr_type(func, scope) {
            FuncPtr(ret, _, _) => ret
            _ => SInt
          }
      }
    Assign(lhs, _) => self.expr_type(lhs, scope)
    CompoundAssign(_, lhs, _) => self.expr_type(lhs, scope)
    MemberAccess(obj, field) =>
      match self.field_layout(self.expr_type(obj, scope), field) {
        Some(layout) => layout.ty
        None => SInt
      }
    Deref(ptr) =>
      match self.core_type(self.expr_type(ptr, scope)) {
        Pointer(ty) | Array(ty, _) => ty
        FuncPtr(ret, params, variadic) => FuncPtr(ret, params, variadic)
        _ => SInt
      }
    AddrOf(e) => Pointer(self.expr_type(e, scope))
    ArrayAccess(arr, _) =>
      match self.pointer_element(self.expr_type(arr, scope)) {
        Some(elem) => elem
        None => SInt
      }
    Sizeof(_) | SizeofExpr(_) | Alignof(_) | AlignofExpr(_) | OffsetOf(_, _) =>
      match self.target {
        DarwinArm64 => SInt
        LinuxAmd64 => SLong
      }
    Cast(ty, _) => ty
    PrefixInc(e) | PrefixDec(e) | PostfixInc(e) | PostfixDec(e) =>
      self.expr_type(e, scope)
    Ternary(_, then_, else_) =>
      self.ternary_result_type(
        self.expr_type(then_, scope),
        self.expr_type(else_, scope),
      )
    LabelAddr(_) => Pointer(Void)
    VaArg(_, ty) => ty
    Array(_) => SInt
    CompoundLiteral(ty, _, _) => ty
    DesignatedField(_, e) | DesignatedIndex(_, e) | DesignatedRange(_, _, e) =>
      self.expr_type(e, scope)
  }
}

///|
priv struct ConstIntValue {
  bits : Int64
  ty : @parser.Type
}

///|
fn Program::const_int(
  self : Program,
  bits : Int64,
  ty : @parser.Type,
) -> ConstIntValue {
  { bits, ty: self.core_type(ty) }
}

///|
fn const_bool(value : Bool) -> ConstIntValue {
  { bits: if value { 1L } else { 0L }, ty: SInt }
}

///|
fn const_type_is_unsigned(ty : @parser.Type) -> Bool {
  match ty {
    Bool | UChar | UShort | UInt | ULong | ULongLong | UInt128 => true
    _ => false
  }
}

///|
fn const_type_int_width(ty : @parser.Type) -> Int? {
  match ty {
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
fn Program::const_cast_int(
  self : Program,
  value : ConstIntValue,
  ty : @parser.Type,
) -> ConstIntValue {
  let core_ty = self.core_type(ty)
  let unsigned = const_type_is_unsigned(core_ty)
  match const_type_int_width(core_ty) {
    None => self.const_int(value.bits, core_ty)
    Some(1) => self.const_int(if value.bits == 0L { 0L } else { 1L }, core_ty)
    Some(width) =>
      if width >= 64 {
        self.const_int(value.bits, core_ty)
      } else {
        let mask = (1L << width) - 1L
        let bits = value.bits & mask
        if unsigned {
          self.const_int(bits, core_ty)
        } else {
          let sign = 1L << (width - 1)
          if (bits & sign) != 0L {
            self.const_int(bits | mask.lnot(), core_ty)
          } else {
            self.const_int(bits, core_ty)
          }
        }
      }
  }
}

///|
fn const_integer_common_type(
  lhs_ty : @parser.Type,
  rhs_ty : @parser.Type,
) -> @parser.Type {
  integer_common_type(lhs_ty, rhs_ty)
}

///|
fn Program::const_apply_binary_type(
  self : Program,
  left : ConstIntValue,
  right : ConstIntValue,
) -> (ConstIntValue, ConstIntValue, @parser.Type) {
  let ty = const_integer_common_type(left.ty, right.ty)
  (self.const_cast_int(left, ty), self.const_cast_int(right, ty), ty)
}

///|
fn Program::const_binary_arith(
  self : Program,
  op : String,
  left : ConstIntValue,
  right : ConstIntValue,
) -> ConstIntValue? {
  let (x, y, ty) = self.const_apply_binary_type(left, right)
  let bits = match op {
    "+" => x.bits + y.bits
    "-" => x.bits - y.bits
    "*" => x.bits * y.bits
    "|" => x.bits | y.bits
    "&" => x.bits & y.bits
    "^" => x.bits ^ y.bits
    _ => return None
  }
  Some(self.const_cast_int(self.const_int(bits, ty), ty))
}

///|
fn Program::const_equal_compare(
  self : Program,
  left : ConstIntValue,
  right : ConstIntValue,
) -> Bool {
  let (x, y, _) = self.const_apply_binary_type(left, right)
  x.bits == y.bits
}

///|
fn Program::const_rel_compare(
  self : Program,
  op : String,
  left : ConstIntValue,
  right : ConstIntValue,
) -> Bool {
  let (left, right, ty) = self.const_apply_binary_type(left, right)
  if const_type_is_unsigned(ty) {
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
fn Program::const_divide(
  self : Program,
  op : String,
  left : ConstIntValue,
  right : ConstIntValue,
) -> ConstIntValue? {
  let (left, right, ty) = self.const_apply_binary_type(left, right)
  if right.bits == 0L {
    return None
  }
  if const_type_is_unsigned(ty) {
    let x = left.bits.reinterpret_as_uint64()
    let y = right.bits.reinterpret_as_uint64()
    let result = if op == "/" { x / y } else { x % y }
    Some(
      self.const_cast_int(self.const_int(result.reinterpret_as_int64(), ty), ty),
    )
  } else {
    let result = if op == "/" {
      left.bits / right.bits
    } else {
      left.bits % right.bits
    }
    Some(self.const_cast_int(self.const_int(result, ty), ty))
  }
}

///|
fn Program::const_shift(
  self : Program,
  op : String,
  left : ConstIntValue,
  right : ConstIntValue,
) -> ConstIntValue? {
  let lhs_ty = unary_integer_result_type(left.ty)
  let x = self.const_cast_int(left, lhs_ty)
  let y = self.const_cast_int(right, unary_integer_result_type(right.ty))
  let shift = y.bits.to_int()
  if op == "<<" {
    Some(self.const_cast_int(self.const_int(x.bits << shift, lhs_ty), lhs_ty))
  } else if const_type_is_unsigned(lhs_ty) {
    Some(
      self.const_cast_int(
        self.const_int(
          (x.bits.reinterpret_as_uint64() >> shift).reinterpret_as_int64(),
          lhs_ty,
        ),
        lhs_ty,
      ),
    )
  } else {
    Some(self.const_cast_int(self.const_int(x.bits >> shift, lhs_ty), lhs_ty))
  }
}

///|
fn Program::fold_const_int(
  self : Program,
  expr : @parser.Expr,
  scope : Scope,
) -> ConstIntValue? {
  match expr {
    Number(n) => {
      let ty = number_literal_type(n)
      Some(self.const_cast_int(self.const_int(n, ty), ty))
    }
    Binary("+", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => self.const_binary_arith("+", x, y)
        _ => None
      }
    Binary("-", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => self.const_binary_arith("-", x, y)
        _ => None
      }
    Binary("*", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => self.const_binary_arith("*", x, y)
        _ => None
      }
    Binary("/", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => self.const_divide("/", x, y)
        _ => None
      }
    Binary("%", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => self.const_divide("%", x, y)
        _ => None
      }
    Binary("|", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => self.const_binary_arith("|", x, y)
        _ => None
      }
    Binary("&", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => self.const_binary_arith("&", x, y)
        _ => None
      }
    Binary("^", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => self.const_binary_arith("^", x, y)
        _ => None
      }
    Binary("<<", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => self.const_shift("<<", x, y)
        _ => None
      }
    Binary(">>", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => self.const_shift(">>", x, y)
        _ => None
      }
    Binary("==", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => Some(const_bool(self.const_equal_compare(x, y)))
        _ => None
      }
    Binary("!=", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => Some(const_bool(!self.const_equal_compare(x, y)))
        _ => None
      }
    Binary("<", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) =>
          Some(const_bool(self.const_rel_compare("<", x, y)))
        _ => None
      }
    Binary(">", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) =>
          Some(const_bool(self.const_rel_compare(">", x, y)))
        _ => None
      }
    Binary("<=", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) =>
          Some(const_bool(self.const_rel_compare("<=", x, y)))
        _ => None
      }
    Binary(">=", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) =>
          Some(const_bool(self.const_rel_compare(">=", x, y)))
        _ => None
      }
    Binary("&&", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => Some(const_bool(x.bits != 0L && y.bits != 0L))
        _ => None
      }
    Binary("||", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => Some(const_bool(x.bits != 0L || y.bits != 0L))
        _ => None
      }
    Ternary(cond, a, b) =>
      match self.fold_const_int(cond, scope) {
        Some({ bits: 0L, .. }) => self.fold_const_int(b, scope)
        Some(_) => self.fold_const_int(a, scope)
        None => None
      }
    Unary("-", e) =>
      match self.fold_const_int(e, scope) {
        Some(value) => {
          let ty = unary_integer_result_type(value.ty)
          Some(self.const_cast_int(self.const_int(-value.bits, ty), ty))
        }
        None => None
      }
    Unary("+", e) =>
      match self.fold_const_int(e, scope) {
        Some(value) => {
          let ty = unary_integer_result_type(value.ty)
          Some(self.const_cast_int(value, ty))
        }
        None => None
      }
    Unary("~", e) =>
      match self.fold_const_int(e, scope) {
        Some(value) => {
          let ty = unary_integer_result_type(value.ty)
          Some(self.const_cast_int(self.const_int(value.bits.lnot(), ty), ty))
        }
        None => None
      }
    Unary("!", e) =>
      match self.fold_const_int(e, scope) {
        Some(value) => Some(const_bool(value.bits == 0L))
        None => None
      }
    Cast(ty, e) =>
      match const_type_int_width(self.core_type(ty)) {
        Some(_) =>
          match self.fold_const_int(e, scope) {
            Some(value) => Some(self.const_cast_int(value, ty))
            None => None
          }
        None => None
      }
    DesignatedField(_, e) | DesignatedIndex(_, e) | DesignatedRange(_, _, e) =>
      self.fold_const_int(e, scope)
    Sizeof(ty) => Some(self.const_int(self.type_size(ty).to_int64(), ULong))
    SizeofExpr(e) =>
      Some(
        self.const_int(
          match e {
            String(value) => value.length().to_int64() + 1L
            _ => self.type_size(self.expr_type(e, scope)).to_int64()
          },
          ULong,
        ),
      )
    Alignof(ty) => Some(self.const_int(self.type_align(ty).to_int64(), ULong))
    AlignofExpr(e) =>
      Some(
        self.const_int(
          match e {
            String(value) =>
              self.type_align(Array(SChar, value.length() + 1)).to_int64()
            _ => self.type_align(self.expr_type(e, scope)).to_int64()
          },
          ULong,
        ),
      )
    OffsetOf(ty, path) =>
      match self.offset_of_path(ty, path) {
        Some(offset) => Some(self.const_int(offset.to_int64(), ULong))
        None => None
      }
    _ => None
  }
}

///|
pub fn Program::fold_const(
  self : Program,
  expr : @parser.Expr,
  scope : Scope,
) -> Int64? {
  match self.fold_const_int(expr, scope) {
    Some(value) => Some(value.bits)
    None => None
  }
}
