///|
/// Stable reference to a lowered function-local C object.
///
/// Codegen-facing MIR should use this ID rather than parser AST variable names
/// so later passes do not need to recover binding information from source AST
/// nodes.
pub(all) struct MirLocal {
  id : Int
  name : String
  ty : @parser.Type
} derive(Eq)

///|
/// Integer/scalar MIR value expression.
///
/// This is intentionally smaller than the parser AST. Unsupported source
/// expressions simply keep the containing function out of `Program.bodies`
/// until the MIR layer learns that feature.
pub(all) enum MirValue {
  MirConst(Int64, @parser.Type)
  MirLocal(MirLocal)
  MirAddrLocal(MirLocal)
  MirAddrGlobal(String, @parser.Type)
  MirFuncAddr(String, @parser.Type)
  MirStringAddr(String)
  MirElemAddr(MirValue, MirValue, @parser.Type)
  MirOffsetAddr(MirValue, Int, @parser.Type)
  MirLoad(MirValue, @parser.Type)
  MirUnary(String, MirValue, @parser.Type)
  MirBinary(String, MirValue, MirValue, @parser.Type)
  MirCast(@parser.Type, MirValue)
  MirCall(String, Array[MirValue], @parser.Type)
  MirIndirectCall(MirValue, Array[MirValue], @parser.Type)
  MirAssignLocal(MirLocal, MirValue)
  MirStore(MirValue, MirValue, @parser.Type)
  MirPostUpdateLocal(MirLocal, String, MirValue, @parser.Type)
  MirPreUpdateMemory(MirValue, String, MirValue, @parser.Type)
  MirPostUpdateMemory(MirValue, String, MirValue, @parser.Type)
  MirTernary(MirValue, MirValue, MirValue, @parser.Type)
} derive(Eq)

///|
/// Structured MIR statement subset used before CFG/block lowering.
pub(all) enum MirStmt {
  MirDeclare(MirLocal, MirValue?)
  MirExprStmt(MirValue)
  MirReturn(MirValue?)
  MirIf(MirValue, Array[MirStmt], Array[MirStmt])
  MirWhile(MirValue, Array[MirStmt])
  MirFor(Array[MirStmt], MirValue, MirValue?, Array[MirStmt])
  MirDoWhile(MirValue, Array[MirStmt])
  MirSwitch(MirValue, Array[(Int64?, String)], Array[MirStmt])
  MirLabel(String)
  MirGoto(String)
  MirBreak
  MirContinue
  MirBlock(Array[MirStmt])
} derive(Eq)

///|
/// MIR-owned function body. This is the boundary that lets later codegen stop
/// walking parser statements and expressions.
pub(all) struct MirFuncBody {
  name : String
  ret : @parser.Type
  params : Array[MirLocal]
  locals : Array[MirLocal]
  body : Array[MirStmt]
} derive(Eq)

///|
pub fn MirValue::ty(self : MirValue) -> @parser.Type {
  match self {
    MirConst(_, ty) => ty
    MirLocal(binding) => binding.ty
    MirAddrLocal(binding) => Pointer(binding.ty)
    MirAddrGlobal(_, ty) => Pointer(ty)
    MirFuncAddr(_, ty) => ty
    MirStringAddr(_) => Pointer(SChar)
    MirElemAddr(_, _, elem_ty) => Pointer(elem_ty)
    MirOffsetAddr(_, _, ty) => Pointer(ty)
    MirLoad(_, ty) => ty
    MirUnary(_, _, ty) => ty
    MirBinary(_, _, _, ty) => ty
    MirCast(ty, _) => ty
    MirCall(_, _, ty) => ty
    MirIndirectCall(_, _, ty) => ty
    MirAssignLocal(binding, _) => binding.ty
    MirStore(_, _, ty) => ty
    MirPostUpdateLocal(_, _, _, ty) => ty
    MirPreUpdateMemory(_, _, _, ty) => ty
    MirPostUpdateMemory(_, _, _, ty) => ty
    MirTernary(_, _, _, ty) => ty
  }
}

///|
priv struct BodyLowerContext {
  scopes : Array[Map[String, MirLocal]]
  locals : Array[MirLocal]
  mut next_id : Int
  current_func : String
}

///|
fn BodyLowerContext::new(current_func : String) -> BodyLowerContext {
  { scopes: [{}], locals: [], next_id: 0, current_func }
}

///|
fn BodyLowerContext::scope(self : BodyLowerContext) -> Scope {
  let locals : Map[String, @parser.Type] = {}
  for binding in self.locals {
    match self.lookup_local(binding.name) {
      Some(active) =>
        if active.id == binding.id {
          locals[binding.name] = binding.ty
        }
      None => ()
    }
  }
  { locals, current_func: self.current_func }
}

///|
fn BodyLowerContext::push_scope(self : BodyLowerContext) -> Unit {
  self.scopes.push({})
}

///|
fn BodyLowerContext::pop_scope(self : BodyLowerContext) -> Unit {
  if self.scopes.length() > 1 {
    let _ = self.scopes.pop()
  }
}

///|
fn BodyLowerContext::declare_local(
  self : BodyLowerContext,
  name : String,
  ty : @parser.Type,
) -> MirLocal {
  let binding = { id: self.next_id, name, ty }
  self.next_id += 1
  self.locals.push(binding)
  let index = self.scopes.length() - 1
  self.scopes[index][name] = binding
  binding
}

///|
fn BodyLowerContext::declare_temp(
  self : BodyLowerContext,
  ty : @parser.Type,
) -> MirLocal {
  self.declare_local("$mir_tmp" + self.next_id.to_string(), ty)
}

///|
fn BodyLowerContext::lookup_local(
  self : BodyLowerContext,
  name : String,
) -> MirLocal? {
  for i = self.scopes.length() - 1; i >= 0; i = i - 1 {
    let scope = self.scopes[i]
    if scope.contains(name) {
      return Some(scope[name])
    }
  }
  None
}

///|
fn lower_mir_cancelled_local_lvalue(
  expr : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirLocal? {
  match expr {
    Var(name) => ctx.lookup_local(name)
    Deref(AddrOf(Var(name))) => ctx.lookup_local(name)
    _ => None
  }
}

///|
fn mir_body_scalar_type(ty : @parser.Type) -> Bool {
  match ty {
    Void => true
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
    | Pointer(_)
    | FuncPtr(_, _, _) => true
    Atomic(inner) | Aligned(inner, _) => mir_body_scalar_type(inner)
    _ => false
  }
}

///|
fn mir_body_array_local_type(ty : @parser.Type) -> Bool {
  match ty {
    Array(elem, _) => mir_body_scalar_type(elem)
    Aligned(inner, _) => mir_body_array_local_type(inner)
    _ => false
  }
}

///|
fn mir_body_array_local_info(ty : @parser.Type) -> (@parser.Type, Int)? {
  match ty {
    Array(elem, len) => Some((elem, len))
    Aligned(inner, _) => mir_body_array_local_info(inner)
    _ => None
  }
}

///|
fn lower_mir_local_update(
  name : String,
  op : String,
  rhs : MirValue,
  ty : @parser.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  match ctx.lookup_local(name) {
    Some(binding) =>
      if binding.ty.is_integer() {
        Some(MirAssignLocal(binding, MirBinary(op, MirLocal(binding), rhs, ty)))
      } else {
        None
      }
    None => None
  }
}

///|
fn lower_mir_local_step(
  name : String,
  op : String,
  ty : @parser.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  lower_mir_local_update(name, op, MirConst(1L, SInt), ty, ctx)
}

///|
fn lower_mir_post_update(
  binding : MirLocal,
  op : String,
  rhs : MirValue,
  ty : @parser.Type,
) -> MirValue? {
  if binding.ty.is_integer() {
    Some(MirPostUpdateLocal(binding, op, rhs, ty))
  } else {
    None
  }
}

///|
fn Program::lower_mir_post_step(
  self : Program,
  expr : @parser.Expr,
  op : String,
  ty : @parser.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  match lower_mir_cancelled_local_lvalue(expr, ctx) {
    Some(binding) => lower_mir_post_update(binding, op, MirConst(1L, SInt), ty)
    None => {
      let lhs_ty = self.expr_type(expr, ctx.scope())
      if !lhs_ty.is_integer() {
        return None
      }
      match self.lower_mir_scalar_lvalue_addr(expr, lhs_ty, ctx) {
        Some(addr) =>
          Some(MirPostUpdateMemory(addr, op, MirConst(1L, SInt), lhs_ty))
        None => None
      }
    }
  }
}

///|
fn mir_body_reusable_addr_operand(expr : @parser.Expr) -> Bool {
  match expr {
    Number(_) | Var(_) => true
    Cast(_, inner) => mir_body_reusable_addr_operand(inner)
    _ => false
  }
}

///|
fn mir_body_reusable_scalar_lvalue(expr : @parser.Expr) -> Bool {
  match expr {
    Deref(Var(_)) => true
    ArrayAccess(base, index) =>
      mir_body_reusable_addr_operand(base) &&
      mir_body_reusable_addr_operand(index)
    MemberAccess(Var(_), _) => true
    _ => false
  }
}

///|
fn mir_body_memory_update_op(op : String) -> Bool {
  match op {
    "+" | "-" | "*" | "/" | "%" | "|" | "&" | "^" | "<<" | ">>" => true
    _ => false
  }
}

///|
fn mir_body_side_effect_free_expr(expr : @parser.Expr) -> Bool {
  match expr {
    Number(_)
    | FloatLiteral(_)
    | String(_)
    | Var(_)
    | Sizeof(_)
    | Alignof(_)
    | OffsetOf(_, _)
    | LabelAddr(_) => true
    SizeofExpr(_) | AlignofExpr(_) => true
    Unary(_, inner) | Cast(_, inner) | Deref(inner) | AddrOf(inner) =>
      mir_body_side_effect_free_expr(inner)
    Binary(_, lhs, rhs) =>
      mir_body_side_effect_free_expr(lhs) && mir_body_side_effect_free_expr(rhs)
    MemberAccess(obj, _) => mir_body_side_effect_free_expr(obj)
    ArrayAccess(base, index) =>
      mir_body_side_effect_free_expr(base) &&
      mir_body_side_effect_free_expr(index)
    Ternary(cond, then_, else_) =>
      mir_body_side_effect_free_expr(cond) &&
      mir_body_side_effect_free_expr(then_) &&
      mir_body_side_effect_free_expr(else_)
    Array(items) | CompoundLiteral(_, items, _) => {
      for item in items {
        if !mir_body_side_effect_free_expr(item) {
          return false
        }
      }
      true
    }
    DesignatedField(_, value)
    | DesignatedIndex(_, value)
    | DesignatedRange(_, _, value) => mir_body_side_effect_free_expr(value)
    _ => false
  }
}

///|
fn mir_body_literal_string_arg(expr : @parser.Expr) -> String? {
  match expr {
    String(value) => Some(value)
    Cast(_, inner) => mir_body_literal_string_arg(inner)
    _ => None
  }
}

///|
fn mir_body_c_string_len(value : String) -> Int64 {
  for i in 0..<value.length() {
    if value[i].to_int() == 0 {
      return i.to_int64()
    }
  }
  value.length().to_int64()
}

///|
fn mir_body_scalar_initializer_expr(expr : @parser.Expr) -> @parser.Expr {
  match expr {
    DesignatedField(_, value)
    | DesignatedIndex(_, value)
    | DesignatedRange(_, _, value) => mir_body_scalar_initializer_expr(value)
    _ => expr
  }
}

///|
fn mir_body_char_array_elem_type(ty : @parser.Type) -> Bool {
  match ty {
    SChar | UChar => true
    Atomic(inner) | Aligned(inner, _) => mir_body_char_array_elem_type(inner)
    _ => false
  }
}

///|
fn Program::lower_mir_array_init_stores(
  self : Program,
  base : MirValue,
  ty : @parser.Type,
  init : @parser.Expr,
  ctx : BodyLowerContext,
) -> Array[MirStmt]? {
  let (elem_ty, len) = match mir_body_array_local_info(ty) {
    Some(info) => info
    None => return None
  }
  if !mir_body_scalar_type(elem_ty) {
    return None
  }
  if init is String(_) && !mir_body_char_array_elem_type(elem_ty) {
    return None
  }
  let items : Array[@parser.Expr] = match init {
    Number(value) => if value == 0L { [] } else { return None }
    Array(values) | CompoundLiteral(_, values, _) => values
    String(_) => []
    _ => return None
  }
  let stores : Array[MirStmt] = []
  for i in 0..<len {
    let addr = MirElemAddr(base, MirConst(i.to_int64(), SInt), elem_ty)
    stores.push(MirExprStmt(MirStore(addr, MirConst(0L, elem_ty), elem_ty)))
  }
  match init {
    String(value) => {
      let limit = if value.length() < len { value.length() } else { len }
      for i in 0..<limit {
        let addr = MirElemAddr(base, MirConst(i.to_int64(), SInt), elem_ty)
        stores.push(
          MirExprStmt(
            MirStore(
              addr,
              MirConst(value[i].to_int().to_int64(), elem_ty),
              elem_ty,
            ),
          ),
        )
      }
      return Some(stores)
    }
    _ => ()
  }
  let mut next_index = 0
  for item in items {
    let (index, value_expr) = match item {
      DesignatedIndex(i, value) => {
        if i < 0L || i >= len.to_int64() {
          return None
        }
        next_index = i.to_int() + 1
        (i.to_int(), value)
      }
      DesignatedRange(_, _, _) | DesignatedField(_, _) => return None
      _ => {
        if next_index >= len {
          return None
        }
        let index = next_index
        next_index += 1
        (index, item)
      }
    }
    let value = match
      self.lower_mir_expr(mir_body_scalar_initializer_expr(value_expr), ctx) {
      Some(value) => value
      None => return None
    }
    let addr = MirElemAddr(base, MirConst(index.to_int64(), SInt), elem_ty)
    stores.push(MirExprStmt(MirStore(addr, value, elem_ty)))
  }
  Some(stores)
}

///|
fn Program::lower_mir_local_array_init(
  self : Program,
  binding : MirLocal,
  init : @parser.Expr,
  ctx : BodyLowerContext,
) -> Array[MirStmt]? {
  self.lower_mir_array_init_stores(MirAddrLocal(binding), binding.ty, init, ctx)
}

///|
fn Program::lower_mir_zero_init_stores(
  self : Program,
  base : MirValue,
  ty : @parser.Type,
) -> Array[MirStmt]? {
  match self.core_type(ty) {
    Struct(name) | Union(name) => {
      let decl = match self.aggregates.get(name) {
        Some(decl) => decl
        None => return None
      }
      if decl.is_union {
        if decl.fields.length() == 0 {
          return Some([])
        }
        let field = decl.fields[0]
        if field.bit_width is Some(_) {
          return None
        }
        let layout = match self.field_layout(ty, field.name) {
          Some(layout) => layout
          None => return None
        }
        let addr = mir_body_offset_addr_value(base, layout.offset, layout.ty)
        return self.lower_mir_zero_init_stores(addr, layout.ty)
      }
      let stores : Array[MirStmt] = []
      for field in decl.fields {
        if field.bit_width is Some(_) {
          return None
        }
        let layout = match self.field_layout(ty, field.name) {
          Some(layout) => layout
          None => return None
        }
        let addr = mir_body_offset_addr_value(base, layout.offset, layout.ty)
        let nested = match self.lower_mir_zero_init_stores(addr, layout.ty) {
          Some(stores) => stores
          None => return None
        }
        for store in nested {
          stores.push(store)
        }
      }
      Some(stores)
    }
    Array(elem_ty, len) =>
      if mir_body_scalar_type(elem_ty) {
        let stores : Array[MirStmt] = []
        for i in 0..<len {
          let addr = MirElemAddr(base, MirConst(i.to_int64(), SInt), elem_ty)
          stores.push(
            MirExprStmt(MirStore(addr, MirConst(0L, elem_ty), elem_ty)),
          )
        }
        Some(stores)
      } else {
        None
      }
    _ =>
      if mir_body_scalar_type(ty) {
        Some([MirExprStmt(MirStore(base, MirConst(0L, ty), ty))])
      } else {
        None
      }
  }
}

///|
fn mir_body_local_copy_source_addr(value : MirValue) -> Bool {
  match value {
    MirAddrGlobal(_, _) | MirFuncAddr(_, _) | MirStringAddr(_) => false
    MirElemAddr(base, _, _) | MirOffsetAddr(base, _, _) =>
      mir_body_local_copy_source_addr(base)
    _ => true
  }
}

///|
fn Program::lower_mir_union_copy_init_stores(
  self : Program,
  dest_base : MirValue,
  dest_ty : @parser.Type,
  src_base : MirValue,
  src_ty : @parser.Type,
  union_name : String,
) -> Array[MirStmt]? {
  if self.core_type(src_ty) != Union(union_name) {
    return None
  }
  let decl = match self.aggregates.get(union_name) {
    Some(decl) => decl
    None => return None
  }
  if !decl.is_union {
    return None
  }
  let size = self.type_size(dest_ty)
  let mut copy_field = ""
  for field in decl.fields {
    if field.bit_width is Some(_) {
      return None
    }
    let layout = match self.field_layout(dest_ty, field.name) {
      Some(layout) => layout
      None => return None
    }
    if layout.offset == 0 &&
      mir_body_scalar_type(layout.ty) &&
      self.type_size(layout.ty) == size {
      copy_field = field.name
    }
  }
  if copy_field == "" {
    return None
  }
  let dest_layout = match self.field_layout(dest_ty, copy_field) {
    Some(layout) => layout
    None => return None
  }
  let src_layout = match self.field_layout(src_ty, copy_field) {
    Some(layout) => layout
    None => return None
  }
  Some([
    MirExprStmt(
      MirStore(
        mir_body_offset_addr_value(
          dest_base,
          dest_layout.offset,
          dest_layout.ty,
        ),
        MirLoad(
          mir_body_offset_addr_value(src_base, src_layout.offset, src_layout.ty),
          src_layout.ty,
        ),
        dest_layout.ty,
      ),
    ),
  ])
}

///|
fn Program::lower_mir_copy_init_stores(
  self : Program,
  dest_base : MirValue,
  dest_ty : @parser.Type,
  src_base : MirValue,
  src_ty : @parser.Type,
) -> Array[MirStmt]? {
  match (self.core_type(dest_ty), self.core_type(src_ty)) {
    (Union(dest_name), Union(_)) =>
      self.lower_mir_union_copy_init_stores(
        dest_base, dest_ty, src_base, src_ty, dest_name,
      )
    (Struct(dest_name), Struct(src_name)) => {
      if dest_name != src_name {
        return None
      }
      let decl = match self.aggregates.get(dest_name) {
        Some(decl) => decl
        None => return None
      }
      if decl.is_union {
        return None
      }
      let stores : Array[MirStmt] = []
      for field in decl.fields {
        if field.bit_width is Some(_) {
          return None
        }
        let dest_layout = match self.field_layout(dest_ty, field.name) {
          Some(layout) => layout
          None => return None
        }
        let src_layout = match self.field_layout(src_ty, field.name) {
          Some(layout) => layout
          None => return None
        }
        let dest_addr = mir_body_offset_addr_value(
          dest_base,
          dest_layout.offset,
          dest_layout.ty,
        )
        let src_addr = mir_body_offset_addr_value(
          src_base,
          src_layout.offset,
          src_layout.ty,
        )
        let nested = match
          self.lower_mir_copy_init_stores(
            dest_addr,
            dest_layout.ty,
            src_addr,
            src_layout.ty,
          ) {
          Some(stores) => stores
          None => return None
        }
        for store in nested {
          stores.push(store)
        }
      }
      Some(stores)
    }
    (Array(dest_elem, dest_len), Array(src_elem, src_len)) =>
      if dest_len == src_len &&
        mir_body_scalar_type(dest_elem) &&
        self.core_type(dest_elem) == self.core_type(src_elem) {
        let stores : Array[MirStmt] = []
        for i in 0..<dest_len {
          let index = MirConst(i.to_int64(), SInt)
          let dest_addr = MirElemAddr(dest_base, index, dest_elem)
          let src_addr = MirElemAddr(src_base, index, src_elem)
          stores.push(
            MirExprStmt(
              MirStore(dest_addr, MirLoad(src_addr, src_elem), dest_elem),
            ),
          )
        }
        Some(stores)
      } else {
        None
      }
    (dest_core, src_core) =>
      if mir_body_scalar_type(dest_ty) &&
        mir_body_scalar_type(src_ty) &&
        dest_core == src_core {
        Some([
          MirExprStmt(MirStore(dest_base, MirLoad(src_base, src_ty), dest_ty)),
        ])
      } else {
        None
      }
  }
}

///|
fn Program::lower_mir_struct_init_stores(
  self : Program,
  base : MirValue,
  ty : @parser.Type,
  init : @parser.Expr,
  ctx : BodyLowerContext,
) -> Array[MirStmt]? {
  let struct_name = match self.core_type(ty) {
    Struct(name) | Union(name) => name
    _ => return None
  }
  match init {
    Number(_) | Array(_) | CompoundLiteral(_, _, _) => ()
    _ => {
      let src_addr = match self.lower_mir_object_addr(init, ctx) {
        Some(addr) => addr
        None => return None
      }
      if !mir_body_local_copy_source_addr(src_addr) {
        return None
      }
      return self.lower_mir_copy_init_stores(
        base,
        ty,
        src_addr,
        self.expr_type(init, ctx.scope()),
      )
    }
  }
  let items : Array[@parser.Expr] = match init {
    Number(value) => if value == 0L { [] } else { return None }
    Array(values) | CompoundLiteral(_, values, _) => values
    _ => return None
  }
  let decl = match self.aggregates.get(struct_name) {
    Some(decl) => decl
    None => return None
  }
  for field in decl.fields {
    if field.bit_width is Some(_) {
      return None
    }
    if self.field_layout(ty, field.name) is None {
      return None
    }
  }
  let stores = match self.lower_mir_zero_init_stores(base, ty) {
    Some(stores) => stores
    None => return None
  }
  let mut next_index = 0
  for item in items {
    let (field_index, value_expr) = match item {
      DesignatedField(name, value) => {
        let mut found = -1
        for i in 0..<decl.fields.length() {
          if decl.fields[i].name == name {
            found = i
          }
        }
        if found < 0 {
          return None
        }
        next_index = found + 1
        (found, value)
      }
      DesignatedIndex(_, _) | DesignatedRange(_, _, _) => return None
      _ => {
        if next_index >= decl.fields.length() {
          return None
        }
        let index = next_index
        next_index += 1
        (index, item)
      }
    }
    let field = decl.fields[field_index]
    if !mir_body_scalar_type(field.ty) {
      match value_expr {
        Number(0) => continue
        Array(_)
        | CompoundLiteral(_, _, _)
        | DesignatedField(_, _)
        | DesignatedIndex(_, _)
        | DesignatedRange(_, _, _) => {
          let layout = match self.field_layout(ty, field.name) {
            Some(layout) => layout
            None => return None
          }
          let addr = mir_body_offset_addr_value(base, layout.offset, layout.ty)
          let nested_init = match value_expr {
            DesignatedField(_, _)
            | DesignatedIndex(_, _)
            | DesignatedRange(_, _, _) => @parser.Expr::Array([value_expr])
            _ => value_expr
          }
          let nested = match self.core_type(layout.ty) {
            Struct(_) | Union(_) =>
              self.lower_mir_struct_init_stores(
                addr,
                layout.ty,
                nested_init,
                ctx,
              )
            _ =>
              self.lower_mir_array_init_stores(
                addr,
                layout.ty,
                nested_init,
                ctx,
              )
          }
          match nested {
            Some(nested_stores) =>
              for store in nested_stores {
                stores.push(store)
              }
            None => return None
          }
          continue
        }
        _ => return None
      }
    }
    let value = match
      self.lower_mir_expr(mir_body_scalar_initializer_expr(value_expr), ctx) {
      Some(value) => value
      None => return None
    }
    match self.field_layout(ty, field.name) {
      Some(layout) => {
        let addr = mir_body_offset_addr_value(base, layout.offset, layout.ty)
        stores.push(MirExprStmt(MirStore(addr, value, layout.ty)))
      }
      None => return None
    }
  }
  Some(stores)
}

///|
fn Program::lower_mir_local_struct_init(
  self : Program,
  binding : MirLocal,
  init : @parser.Expr,
  ctx : BodyLowerContext,
) -> Array[MirStmt]? {
  self.lower_mir_struct_init_stores(
    MirAddrLocal(binding),
    binding.ty,
    init,
    ctx,
  )
}

///|
fn mir_body_sequence_exprs(
  stmts : Array[MirStmt],
  tail : MirValue,
  ty : @parser.Type,
) -> MirValue? {
  let mut result = tail
  for i = stmts.length() - 1; i >= 0; i = i - 1 {
    match stmts[i] {
      MirExprStmt(value) => result = MirBinary(",", value, result, ty)
      _ => return None
    }
  }
  Some(result)
}

///|
fn Program::lower_mir_identity_builtin(
  self : Program,
  args : Array[@parser.Expr],
  side_effect_arg : Int?,
  ty : @parser.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if args.length() == 0 {
    return Some(MirConst(0L, ty))
  }
  let value = match self.lower_mir_call_arg(args[0], ctx) {
    Some(value) => value
    None => return None
  }
  let side_index = match side_effect_arg {
    Some(index) => index
    None => return Some(value)
  }
  if side_index < 0 ||
    side_index >= args.length() ||
    mir_body_side_effect_free_expr(args[side_index]) {
    return Some(value)
  }
  let side = match self.lower_mir_call_arg(args[side_index], ctx) {
    Some(value) => value
    None => return None
  }
  let temp = ctx.declare_temp(value.ty())
  Some(
    MirBinary(
      ",",
      MirAssignLocal(temp, value),
      MirBinary(",", side, MirLocal(temp), ty),
      ty,
    ),
  )
}

///|
fn Program::lower_mir_scalar_lvalue_addr(
  self : Program,
  expr : @parser.Expr,
  lhs_ty : @parser.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if !mir_body_scalar_type(lhs_ty) {
    return None
  }
  match expr {
    Var(name) =>
      if ctx.lookup_local(name) is None &&
        self.globals.contains(name) &&
        mir_body_scalar_type(lhs_ty) {
        Some(MirAddrGlobal(name, lhs_ty))
      } else {
        None
      }
    Deref(Var(name)) => self.lower_mir_expr(Var(name), ctx)
    Deref(ptr) => self.lower_mir_known_object_ptr_expr(ptr, ctx)
    ArrayAccess(base, index) =>
      self.lower_mir_array_elem_addr(base, index, lhs_ty, ctx)
    MemberAccess(obj, field) => self.lower_mir_member_addr(obj, field, ctx)
    _ => None
  }
}

///|
fn Program::lower_mir_compound_memory_update(
  self : Program,
  lhs : @parser.Expr,
  op : String,
  value : MirValue,
  lhs_ty : @parser.Type,
  result_ty : @parser.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if !lhs_ty.is_integer() {
    return None
  }
  match self.lower_mir_scalar_lvalue_addr(lhs, lhs_ty, ctx) {
    Some(addr) =>
      if mir_body_memory_update_op(op) {
        Some(MirPreUpdateMemory(addr, op, value, lhs_ty))
      } else if mir_body_reusable_scalar_lvalue(lhs) {
        Some(
          MirStore(
            addr,
            MirBinary(op, MirLoad(addr, lhs_ty), value, result_ty),
            lhs_ty,
          ),
        )
      } else {
        None
      }
    None => None
  }
}

///|
fn Program::lower_mir_prefix_step(
  self : Program,
  expr : @parser.Expr,
  op : String,
  ty : @parser.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  match lower_mir_cancelled_local_lvalue(expr, ctx) {
    Some(binding) => lower_mir_local_step(binding.name, op, ty, ctx)
    None => {
      let lhs_ty = self.expr_type(expr, ctx.scope())
      if !lhs_ty.is_integer() {
        return None
      }
      match self.lower_mir_scalar_lvalue_addr(expr, lhs_ty, ctx) {
        Some(addr) =>
          Some(MirPreUpdateMemory(addr, op, MirConst(1L, SInt), lhs_ty))
        None => None
      }
    }
  }
}

///|
fn Program::lower_mir_array_base_addr(
  self : Program,
  base : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirValue? {
  match base {
    MemberAccess(_, _) =>
      if mir_body_array_local_type(self.expr_type(base, ctx.scope())) {
        self.lower_mir_object_addr(base, ctx)
      } else {
        self.lower_mir_expr(base, ctx)
      }
    Var(name) =>
      match ctx.lookup_local(name) {
        Some(binding) =>
          if mir_body_array_local_type(binding.ty) {
            Some(MirAddrLocal(binding))
          } else {
            self.lower_mir_expr(base, ctx)
          }
        None =>
          if self.globals.contains(name) &&
            mir_body_array_local_type(self.globals[name].ty) {
            Some(MirAddrGlobal(name, self.globals[name].ty))
          } else {
            self.lower_mir_expr(base, ctx)
          }
      }
    _ => self.lower_mir_expr(base, ctx)
  }
}

///|
fn Program::lower_mir_call_arg(
  self : Program,
  arg : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirValue? {
  if mir_body_array_local_type(self.expr_type(arg, ctx.scope())) {
    self.lower_mir_array_base_addr(arg, ctx)
  } else {
    self.lower_mir_expr(arg, ctx)
  }
}

///|
fn Program::lower_mir_array_elem_addr(
  self : Program,
  base : @parser.Expr,
  index : @parser.Expr,
  elem_ty : @parser.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  match
    (self.lower_mir_array_base_addr(base, ctx), self.lower_mir_expr(index, ctx)) {
    (Some(base_addr), Some(index_value)) =>
      if mir_body_scalar_type(elem_ty) {
        Some(MirElemAddr(base_addr, index_value, elem_ty))
      } else {
        None
      }
    _ => None
  }
}

///|
fn Program::lower_mir_member_addr(
  self : Program,
  obj : @parser.Expr,
  field : String,
  ctx : BodyLowerContext,
) -> MirValue? {
  let obj_ty = self.expr_type(obj, ctx.scope())
  match self.field_layout(obj_ty, field) {
    Some(layout) =>
      if layout.bit_width is None && mir_body_scalar_type(layout.ty) {
        match self.lower_mir_object_addr(obj, ctx) {
          Some(base) =>
            Some(mir_body_offset_addr_value(base, layout.offset, layout.ty))
          None => None
        }
      } else {
        None
      }
    None => None
  }
}

///|
fn mir_body_offset_addr_value(
  base : MirValue,
  offset : Int,
  ty : @parser.Type,
) -> MirValue {
  match base {
    MirOffsetAddr(inner, base_offset, _) =>
      MirOffsetAddr(inner, base_offset + offset, ty)
    _ => MirOffsetAddr(base, offset, ty)
  }
}

///|
fn Program::lower_mir_known_object_ptr_expr(
  self : Program,
  expr : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirValue? {
  match expr {
    AddrOf(CompoundLiteral(lit_ty, items, id)) =>
      self.lower_mir_expr(AddrOf(CompoundLiteral(lit_ty, items, id)), ctx)
    AddrOf(inner) => self.lower_mir_object_addr(inner, ctx)
    Cast(_, inner) => self.lower_mir_known_object_ptr_expr(inner, ctx)
    _ => None
  }
}

///|
fn Program::lower_mir_object_addr(
  self : Program,
  expr : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirValue? {
  match expr {
    Var(name) =>
      match ctx.lookup_local(name) {
        Some(binding) => Some(MirAddrLocal(binding))
        None =>
          match self.globals.get(name) {
            Some(global) => Some(MirAddrGlobal(name, global.ty))
            None => None
          }
      }
    MemberAccess(obj, field) => {
      let obj_ty = self.expr_type(obj, ctx.scope())
      match self.field_layout(obj_ty, field) {
        Some(layout) =>
          if layout.bit_width is None {
            match self.lower_mir_object_addr(obj, ctx) {
              Some(base) =>
                Some(mir_body_offset_addr_value(base, layout.offset, layout.ty))
              None => None
            }
          } else {
            None
          }
        None => None
      }
    }
    Deref(ptr) => self.lower_mir_known_object_ptr_expr(ptr, ctx)
    _ => None
  }
}

///|
fn Program::lower_mir_indirect_call(
  self : Program,
  callee : @parser.Expr,
  args : Array[@parser.Expr],
  ty : @parser.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let normalized_callee = match callee {
    Deref(inner) =>
      match self.core_type(self.expr_type(inner, ctx.scope())) {
        FuncPtr(_, _, _) => inner
        _ => callee
      }
    _ => callee
  }
  let callee_value = match self.lower_mir_expr(normalized_callee, ctx) {
    Some(value) => value
    None => return None
  }
  match self.core_type(callee_value.ty()) {
    FuncPtr(_, _, _) => ()
    _ => return None
  }
  let values : Array[MirValue] = []
  for arg in args {
    match self.lower_mir_call_arg(arg, ctx) {
      Some(value) => values.push(value)
      None => return None
    }
  }
  Some(MirIndirectCall(callee_value, values, ty))
}

///|
fn mir_stmts_have_direct_label(stmts : Array[MirStmt], name : String) -> Bool {
  for stmt in stmts {
    match stmt {
      MirLabel(label) if label == name => return true
      _ => ()
    }
  }
  false
}

///|
fn mir_switch_cases_are_direct(
  cases : Array[(Int64?, String)],
  body : Array[MirStmt],
) -> Bool {
  for c in cases {
    if !mir_stmts_have_direct_label(body, c.1) {
      return false
    }
  }
  true
}

///|
fn Program::lower_mir_expr(
  self : Program,
  expr : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirValue? {
  let scope = ctx.scope()
  let ty = self.expr_type(expr, scope)
  match expr {
    Number(value) => Some(MirConst(value, ty))
    String(value) => Some(MirStringAddr(value))
    Var(name) =>
      match ctx.lookup_local(name) {
        Some(binding) => Some(MirLocal(binding))
        None =>
          if self.globals.contains(name) && mir_body_scalar_type(ty) {
            Some(MirLoad(MirAddrGlobal(name, ty), ty))
          } else if self.funcs.contains(name) {
            Some(MirFuncAddr(name, ty))
          } else {
            None
          }
      }
    AddrOf(CompoundLiteral(lit_ty, items, id)) => {
      if mir_body_scalar_type(lit_ty) {
        let value = match
          self.lower_mir_expr(CompoundLiteral(lit_ty, items, id), ctx) {
          Some(value) => value
          None => return None
        }
        let temp = ctx.declare_temp(lit_ty)
        return Some(
          MirBinary(
            ",",
            MirAssignLocal(temp, value),
            MirAddrLocal(temp),
            Pointer(lit_ty),
          ),
        )
      }
      match self.core_type(lit_ty) {
        Struct(_) | Union(_) => {
          let temp = ctx.declare_temp(lit_ty)
          let stores = match
            self.lower_mir_local_struct_init(
              temp,
              CompoundLiteral(lit_ty, items, id),
              ctx,
            ) {
            Some(stores) => stores
            None => return None
          }
          mir_body_sequence_exprs(stores, MirAddrLocal(temp), Pointer(lit_ty))
        }
        _ => None
      }
    }
    AddrOf(Var(name)) =>
      match ctx.lookup_local(name) {
        Some(binding) =>
          if mir_body_scalar_type(binding.ty) {
            Some(MirAddrLocal(binding))
          } else {
            None
          }
        None =>
          if self.globals.contains(name) &&
            mir_body_scalar_type(self.globals[name].ty) {
            Some(MirAddrGlobal(name, self.globals[name].ty))
          } else if self.funcs.contains(name) {
            Some(MirFuncAddr(name, self.expr_type(Var(name), scope)))
          } else {
            None
          }
      }
    Deref(AddrOf(Var(name))) =>
      match ctx.lookup_local(name) {
        Some(binding) => Some(MirLocal(binding))
        None => None
      }
    AddrOf(Deref(inner)) => self.lower_mir_expr(inner, ctx)
    AddrOf(ArrayAccess(base, index)) =>
      self.lower_mir_array_elem_addr(
        base,
        index,
        self.expr_type(ArrayAccess(base, index), scope),
        ctx,
      )
    AddrOf(MemberAccess(obj, field)) =>
      self.lower_mir_member_addr(obj, field, ctx)
    Deref(Var(name)) =>
      match self.lower_mir_expr(Var(name), ctx) {
        Some(value) =>
          if mir_body_scalar_type(ty) {
            Some(MirLoad(value, ty))
          } else {
            None
          }
        None => None
      }
    Deref(ptr) =>
      match self.lower_mir_known_object_ptr_expr(ptr, ctx) {
        Some(addr) =>
          if mir_body_scalar_type(ty) {
            Some(MirLoad(addr, ty))
          } else {
            None
          }
        None => None
      }
    ArrayAccess(base, index) =>
      match self.lower_mir_array_elem_addr(base, index, ty, ctx) {
        Some(addr) => Some(MirLoad(addr, ty))
        None => None
      }
    MemberAccess(obj, field) =>
      match self.lower_mir_member_addr(obj, field, ctx) {
        Some(addr) => Some(MirLoad(addr, ty))
        None => None
      }
    Binary(op, lhs, rhs) =>
      match (self.lower_mir_expr(lhs, ctx), self.lower_mir_expr(rhs, ctx)) {
        (Some(left), Some(right)) => Some(MirBinary(op, left, right, ty))
        _ => None
      }
    Unary(op, inner) =>
      match self.lower_mir_expr(inner, ctx) {
        Some(value) => Some(MirUnary(op, value, ty))
        None => None
      }
    Cast(cast_ty, inner) =>
      match self.lower_mir_expr(inner, ctx) {
        Some(value) => Some(MirCast(cast_ty, value))
        None => None
      }
    Assign(lhs, rhs) => {
      let lhs_ty = self.expr_type(lhs, scope)
      match
        (
          lower_mir_cancelled_local_lvalue(lhs, ctx),
          self.lower_mir_expr(rhs, ctx),
        ) {
        (Some(binding), Some(value)) =>
          if mir_body_scalar_type(binding.ty) {
            return Some(MirAssignLocal(binding, value))
          }
        _ => ()
      }
      match self.lower_mir_expr(rhs, ctx) {
        Some(value) =>
          match self.lower_mir_scalar_lvalue_addr(lhs, lhs_ty, ctx) {
            Some(addr) => Some(MirStore(addr, value, lhs_ty))
            None => None
          }
        _ => None
      }
    }
    CompoundAssign(op, lhs, rhs) => {
      let lhs_ty = self.expr_type(lhs, scope)
      match
        (
          lower_mir_cancelled_local_lvalue(lhs, ctx),
          self.lower_mir_expr(rhs, ctx),
        ) {
        (Some(binding), Some(value)) =>
          match lower_mir_local_update(binding.name, op, value, ty, ctx) {
            Some(value) => return Some(value)
            None => return None
          }
        _ => ()
      }
      match self.lower_mir_expr(rhs, ctx) {
        Some(value) =>
          self.lower_mir_compound_memory_update(lhs, op, value, lhs_ty, ty, ctx)
        _ => None
      }
    }
    PrefixInc(target) => self.lower_mir_prefix_step(target, "+", ty, ctx)
    PrefixDec(target) => self.lower_mir_prefix_step(target, "-", ty, ctx)
    PostfixInc(target) => self.lower_mir_post_step(target, "+", ty, ctx)
    PostfixDec(target) => self.lower_mir_post_step(target, "-", ty, ctx)
    Ternary(cond, then_, else_) =>
      match
        (
          self.lower_mir_expr(cond, ctx),
          self.lower_mir_expr(then_, ctx),
          self.lower_mir_expr(else_, ctx),
        ) {
        (Some(c), Some(t), Some(e)) => Some(MirTernary(c, t, e, ty))
        _ => None
      }
    CompoundLiteral(lit_ty, items, _) => {
      if !mir_body_scalar_type(lit_ty) {
        return None
      }
      if items.length() == 0 {
        return Some(MirConst(0L, lit_ty))
      }
      if items.length() != 1 {
        return None
      }
      let init = mir_body_scalar_initializer_expr(items[0])
      match self.lower_mir_expr(init, ctx) {
        Some(value) => Some(MirCast(lit_ty, value))
        None => None
      }
    }
    Call(Var(name), args) => {
      if name == "__builtin_unpredictable" && args.length() == 1 {
        return self.lower_mir_expr(args[0], ctx)
      }
      if name == "__builtin_assume" {
        return Some(MirConst(0L, ty))
      }
      if name == "__builtin_prefetch" {
        if args.length() == 0 {
          return Some(MirConst(0L, ty))
        }
        match self.lower_mir_call_arg(args[0], ctx) {
          Some(value) =>
            return Some(MirBinary(",", value, MirConst(0L, ty), ty))
          None => return None
        }
      }
      if name == "__builtin_strlen" && args.length() == 1 {
        match mir_body_literal_string_arg(args[0]) {
          Some(value) => return Some(MirConst(mir_body_c_string_len(value), ty))
          None => ()
        }
      }
      if name == "__builtin_expect" ||
        name == "__builtin_expect_with_probability" {
        return self.lower_mir_identity_builtin(args, Some(1), ty, ctx)
      }
      if name == "__builtin_assume_aligned" {
        return self.lower_mir_identity_builtin(args, Some(2), ty, ctx)
      }
      if name == "__builtin_extract_return_addr" ||
        name == "__builtin_frob_return_addr" {
        if args.length() == 1 {
          return self.lower_mir_expr(args[0], ctx)
        }
        return None
      }
      match self.fold_const(expr, scope) {
        Some(value) => return Some(MirConst(value, ty))
        None => ()
      }
      let values : Array[MirValue] = []
      for arg in args {
        match self.lower_mir_call_arg(arg, ctx) {
          Some(value) => values.push(value)
          None => return None
        }
      }
      if ctx.lookup_local(name) is None {
        if self.funcs.contains(name) || !self.globals.contains(name) {
          Some(MirCall(name, values, ty))
        } else {
          self.lower_mir_indirect_call(Var(name), args, ty, ctx)
        }
      } else {
        self.lower_mir_indirect_call(Var(name), args, ty, ctx)
      }
    }
    Call(callee, args) => self.lower_mir_indirect_call(callee, args, ty, ctx)
    _ =>
      match self.fold_const(expr, scope) {
        Some(value) => Some(MirConst(value, ty))
        None => None
      }
  }
}

///|
fn Program::lower_mir_ignored_aggregate_assign(
  self : Program,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirValue? {
  let lhs_ty = self.expr_type(lhs, ctx.scope())
  match self.core_type(lhs_ty) {
    Struct(_) | Union(_) => ()
    _ => return None
  }
  let dest_addr = match self.lower_mir_object_addr(lhs, ctx) {
    Some(addr) => addr
    None => return None
  }
  if !mir_body_local_copy_source_addr(dest_addr) {
    return None
  }
  match rhs {
    CompoundLiteral(_, _, _) => {
      let rhs_ty = self.expr_type(rhs, ctx.scope())
      if self.core_type(rhs_ty) != self.core_type(lhs_ty) {
        return None
      }
      let temp = ctx.declare_temp(lhs_ty)
      let stores = match
        self.lower_mir_struct_init_stores(MirAddrLocal(temp), lhs_ty, rhs, ctx) {
        Some(stores) => stores
        None => return None
      }
      let copy_stores = match
        self.lower_mir_copy_init_stores(
          dest_addr,
          lhs_ty,
          MirAddrLocal(temp),
          rhs_ty,
        ) {
        Some(stores) => stores
        None => return None
      }
      for store in copy_stores {
        stores.push(store)
      }
      return mir_body_sequence_exprs(stores, MirConst(0L, SInt), SInt)
    }
    _ => ()
  }
  let src_addr = match self.lower_mir_object_addr(rhs, ctx) {
    Some(addr) => addr
    None => return None
  }
  if !mir_body_local_copy_source_addr(src_addr) {
    return None
  }
  let stores = match
    self.lower_mir_copy_init_stores(
      dest_addr,
      lhs_ty,
      src_addr,
      self.expr_type(rhs, ctx.scope()),
    ) {
    Some(stores) => stores
    None => return None
  }
  mir_body_sequence_exprs(stores, MirConst(0L, SInt), SInt)
}

///|
fn Program::lower_mir_ignored_expr(
  self : Program,
  expr : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirValue? {
  match expr {
    Assign(lhs, rhs) =>
      match self.lower_mir_ignored_aggregate_assign(lhs, rhs, ctx) {
        Some(value) => Some(value)
        None => self.lower_mir_expr(expr, ctx)
      }
    _ => self.lower_mir_expr(expr, ctx)
  }
}

///|
fn Program::lower_mir_stmt(
  self : Program,
  stmt : @parser.Stmt,
  ctx : BodyLowerContext,
) -> Array[MirStmt]? {
  match stmt {
    ExprStmt(expr) =>
      match self.lower_mir_ignored_expr(expr, ctx) {
        Some(value) => Some([MirExprStmt(value)])
        None => None
      }
    Return(expr) =>
      match expr {
        Some(value_expr) =>
          match self.lower_mir_expr(value_expr, ctx) {
            Some(value) => Some([MirReturn(Some(value))])
            None => None
          }
        None => Some([MirReturn(None)])
      }
    If(cond, then_, else_) =>
      match (self.lower_mir_expr(cond, ctx), self.lower_mir_stmt(then_, ctx)) {
        (Some(cond_value), Some(then_body)) => {
          let else_body = match else_ {
            Some(stmt) =>
              match self.lower_mir_stmt(stmt, ctx) {
                Some(body) => body
                None => return None
              }
            None => []
          }
          Some([MirIf(cond_value, then_body, else_body)])
        }
        _ => None
      }
    While(cond, body) =>
      match (self.lower_mir_expr(cond, ctx), self.lower_mir_stmt(body, ctx)) {
        (Some(cond_value), Some(body_values)) =>
          Some([MirWhile(cond_value, body_values)])
        _ => None
      }
    For(init, cond, inc, body) => {
      ctx.push_scope()
      let init_values = match init {
        Some(init_stmt) =>
          match self.lower_mir_stmt(init_stmt, ctx) {
            Some(values) => values
            None => {
              ctx.pop_scope()
              return None
            }
          }
        None => []
      }
      let cond_value = match self.lower_mir_expr(cond, ctx) {
        Some(value) => value
        None => {
          ctx.pop_scope()
          return None
        }
      }
      let inc_value = match inc {
        Some(expr) =>
          match self.lower_mir_ignored_expr(expr, ctx) {
            Some(value) => Some(value)
            None => {
              ctx.pop_scope()
              return None
            }
          }
        None => None
      }
      let body_values = match self.lower_mir_stmt(body, ctx) {
        Some(values) => values
        None => {
          ctx.pop_scope()
          return None
        }
      }
      ctx.pop_scope()
      Some([MirFor(init_values, cond_value, inc_value, body_values)])
    }
    DoWhile(cond, body) =>
      match (self.lower_mir_expr(cond, ctx), self.lower_mir_stmt(body, ctx)) {
        (Some(cond_value), Some(body_values)) =>
          Some([MirDoWhile(cond_value, body_values)])
        _ => None
      }
    Switch(expr, body, cases) =>
      match (self.lower_mir_expr(expr, ctx), self.lower_mir_stmt(body, ctx)) {
        (Some(control), Some(body_values)) =>
          if mir_switch_cases_are_direct(cases, body_values) {
            Some([MirSwitch(control, cases, body_values)])
          } else {
            None
          }
        _ => None
      }
    Label(name, body) =>
      match self.lower_mir_stmt(body, ctx) {
        Some(body_values) => {
          let lowered : Array[MirStmt] = [MirLabel(name)]
          for value in body_values {
            lowered.push(value)
          }
          Some(lowered)
        }
        None => None
      }
    Goto(name) => Some([MirGoto(name)])
    Break => Some([MirBreak])
    Continue => Some([MirContinue])
    Compound(stmts) => {
      ctx.push_scope()
      let values : Array[MirStmt] = []
      for nested in stmts {
        match self.lower_mir_stmt(nested, ctx) {
          Some(lowered) =>
            for value in lowered {
              values.push(value)
            }
          None => {
            ctx.pop_scope()
            return None
          }
        }
      }
      ctx.pop_scope()
      Some(values)
    }
    StmtList(stmts) => {
      let values : Array[MirStmt] = []
      for nested in stmts {
        match self.lower_mir_stmt(nested, ctx) {
          Some(lowered) =>
            for value in lowered {
              values.push(value)
            }
          None => return None
        }
      }
      Some(values)
    }
    VarDecl(ty, name, init) => {
      match init {
        Some(expr) =>
          if self.core_type(ty) is Struct(_) || self.core_type(ty) is Union(_) {
            let binding = ctx.declare_local(name, ty)
            match self.lower_mir_local_struct_init(binding, expr, ctx) {
              Some(stores) => {
                let stmts : Array[MirStmt] = [MirDeclare(binding, None)]
                for store in stores {
                  stmts.push(store)
                }
                return Some(stmts)
              }
              None => return None
            }
          } else if mir_body_array_local_type(ty) {
            let binding = ctx.declare_local(name, ty)
            match self.lower_mir_local_array_init(binding, expr, ctx) {
              Some(stores) => {
                let stmts : Array[MirStmt] = [MirDeclare(binding, None)]
                for store in stores {
                  stmts.push(store)
                }
                return Some(stmts)
              }
              None => return None
            }
          }
        None => ()
      }
      let init_value = match init {
        Some(expr) =>
          match self.lower_mir_expr(expr, ctx) {
            Some(value) => Some(value)
            None => return None
          }
        None => None
      }
      let binding = ctx.declare_local(name, ty)
      Some([MirDeclare(binding, init_value)])
    }
    _ => None
  }
}

///|
fn Program::lower_mir_func_body(
  self : Program,
  decl : @parser.FuncDecl,
) -> MirFuncBody? {
  match decl.body {
    Some(body) => {
      let ctx = BodyLowerContext::new(decl.name)
      let params : Array[MirLocal] = []
      for param in decl.params {
        let binding = ctx.declare_local(param.name, param.ty)
        params.push(binding)
      }
      match self.lower_mir_stmt(body, ctx) {
        Some(stmts) =>
          Some({
            name: decl.name,
            ret: decl.ret,
            params,
            locals: ctx.locals,
            body: stmts,
          })
        None => None
      }
    }
    None => None
  }
}
