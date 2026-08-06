///|
/// Stable reference to a lowered function-local C object.
///
/// Codegen-facing MIR should use this ID rather than parser AST variable names
/// so later passes do not need to recover binding information from source AST
/// nodes.
pub(all) struct MirLocal {
  id : Int
  name : String
  ty : @ctype.Type
} derive(Eq)

///|
/// Scalar MIR value expression.
///
/// This is intentionally smaller than the parser AST. Unsupported source
/// expressions simply keep the containing function out of `Program.bodies`
/// until the MIR layer learns that feature.
///
/// `MirConst` stores integer values as integer bits and floating constants as
/// their raw IEEE payload bits.
pub(all) enum MirValue {
  MirConst(Int64, @ctype.Type)
  MirLocal(MirLocal)
  MirAddrLocal(MirLocal)
  MirAddrGlobal(String, @ctype.Type)
  MirFuncAddr(String, @ctype.Type)
  MirLabelAddr(String)
  MirStringAddr(String)
  MirElemAddr(MirValue, MirValue, @ctype.Type)
  MirOffsetAddr(MirValue, Int, @ctype.Type)
  MirLoad(MirValue, @ctype.Type)
  MirUnary(String, MirValue, @ctype.Type)
  MirBinary(String, MirValue, MirValue, @ctype.Type)
  MirCast(@ctype.Type, MirValue)
  MirAggregateArg(MirValue, @ctype.Type)
  MirVaArg(MirValue, @ctype.Type)
  MirVaArgAddr(MirValue, @ctype.Type)
  MirVaStart(MirValue)
  MirVaCopy(MirValue, MirValue)
  MirVaEnd(MirValue)
  MirOverflow(String, MirValue, MirValue, MirValue)
  MirBzero(MirValue, MirValue)
  MirAtomicLoad(MirValue, MirValue, @ctype.Type)
  MirAtomicStore(MirValue, MirValue, MirValue)
  MirAtomicUpdate(
    String,
    Bool,
    MirValue,
    MirValue,
    Array[MirValue],
    @ctype.Type
  )
  MirAtomicExchange(MirValue, MirValue, Array[MirValue], @ctype.Type)
  MirAtomicCompareExchange(MirValue, MirValue, MirValue, Array[MirValue])
  MirLibCall(String, Array[MirValue], @ctype.Type)
  MirCall(String, Array[MirValue], @ctype.Type)
  MirIndirectCall(MirValue, Array[MirValue], @ctype.Type)
  MirAssignLocal(MirLocal, MirValue)
  MirStore(MirValue, MirValue, @ctype.Type)
  MirPostUpdateLocal(MirLocal, String, MirValue, @ctype.Type)
  MirPreUpdateMemory(MirValue, String, MirValue, @ctype.Type)
  MirPostUpdateMemory(MirValue, String, MirValue, @ctype.Type)
  MirTernary(MirValue, MirValue, MirValue, @ctype.Type)
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
  MirComputedGoto(MirValue)
  MirBreak
  MirContinue
  MirBlock(Array[MirStmt])
} derive(Eq)

///|
/// MIR-owned function body. This is the boundary that lets later codegen stop
/// walking parser statements and expressions.
pub(all) struct MirFuncBody {
  name : String
  ret : @ctype.Type
  params : Array[MirLocal]
  locals : Array[MirLocal]
  body : Array[MirStmt]
} derive(Eq)

///|
/// Returns the C type that this MIR value evaluates to.
///
/// The type is derived structurally from the value node, so this never
/// consults a `Program` or `MirModule`. Address-producing nodes report a
/// pointer to their pointee type (for example `MirAddrLocal` of an `Int` local
/// has type `Pointer(SInt)`, and a string address has type `Pointer(SChar)`),
/// while loads, casts, and arithmetic report the type recorded on the node.
/// Backends use this to choose operand sizes and register classes.
pub fn MirValue::ty(self : MirValue) -> @ctype.Type {
  match self {
    MirConst(_, ty) => ty
    MirLocal(binding) => binding.ty
    MirAddrLocal(binding) => Pointer(binding.ty)
    MirAddrGlobal(_, ty) => Pointer(ty)
    MirFuncAddr(_, ty) => ty
    MirLabelAddr(_) => Pointer(Void)
    MirStringAddr(_) => Pointer(SChar)
    MirElemAddr(_, _, elem_ty) => Pointer(elem_ty)
    MirOffsetAddr(_, _, ty) => Pointer(ty)
    MirLoad(_, ty) => ty
    MirUnary(_, _, ty) => ty
    MirBinary(_, _, _, ty) => ty
    MirCast(ty, _) => ty
    MirAggregateArg(_, ty) => ty
    MirVaArg(_, ty) => ty
    MirVaArgAddr(_, ty) => Pointer(ty)
    MirVaStart(_) | MirVaCopy(_, _) | MirVaEnd(_) => Void
    MirOverflow(_, _, _, _) => Bool
    MirBzero(_, _) => Void
    MirAtomicLoad(_, _, ty) => ty
    MirAtomicStore(_, _, _) => Void
    MirAtomicUpdate(_, _, _, _, _, ty) => ty
    MirAtomicExchange(_, _, _, ty) => ty
    MirAtomicCompareExchange(_, _, _, _) => Bool
    MirLibCall(_, _, ty) => ty
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
  let locals : Map[String, @ctype.Type] = Map([])
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
  ty : @ctype.Type,
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
  ty : @ctype.Type,
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
fn mir_body_scalar_type(ty : @ctype.Type) -> Bool {
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
    | SInt128
    | UInt128
    | Float
    | Double
    | LongDouble
    | Pointer(_)
    | FuncPtr(_, _, _) => true
    Atomic(inner) | Aligned(inner, _) => mir_body_scalar_type(inner)
    _ => false
  }
}

///|
fn mir_body_array_local_type(ty : @ctype.Type) -> Bool {
  match ty {
    Array(elem, _) => mir_body_array_element_addressable_type(elem)
    Aligned(inner, _) => mir_body_array_local_type(inner)
    _ => false
  }
}

///|
fn mir_body_array_element_addressable_type(ty : @ctype.Type) -> Bool {
  match ty {
    Array(elem, _) => mir_body_array_element_addressable_type(elem)
    Struct(_) | Union(_) => true
    Aligned(inner, _) => mir_body_array_element_addressable_type(inner)
    _ => mir_body_scalar_type(ty)
  }
}

///|
fn mir_body_array_local_info(ty : @ctype.Type) -> (@ctype.Type, Int)? {
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
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  match ctx.lookup_local(name) {
    Some(binding) =>
      if binding.ty.is_integer() ||
        (
          mir_body_pointer_type(binding.ty) &&
          (op == "+" || op == "-") &&
          rhs.ty().is_integer()
        ) ||
        (binding.ty.is_floating() && mir_body_floating_update_op(op)) {
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
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  lower_mir_local_update(name, op, MirConst(1L, SInt), ty, ctx)
}

///|
fn lower_mir_post_update(
  binding : MirLocal,
  op : String,
  rhs : MirValue,
  ty : @ctype.Type,
) -> MirValue? {
  if binding.ty.is_integer() ||
    (
      mir_body_pointer_type(binding.ty) &&
      (op == "+" || op == "-") &&
      rhs.ty().is_integer()
    ) ||
    (binding.ty.is_floating() && mir_body_floating_update_op(op)) {
    Some(MirPostUpdateLocal(binding, op, rhs, ty))
  } else {
    None
  }
}

///|
fn mir_body_pointer_type(ty : @ctype.Type) -> Bool {
  match ty {
    Pointer(_) => true
    Atomic(inner) | Aligned(inner, _) => mir_body_pointer_type(inner)
    _ => false
  }
}

///|
fn Program::lower_mir_post_step(
  self : Program,
  expr : @parser.Expr,
  op : String,
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  match self.lower_mir_bitfield_post_step(expr, op, ty, ctx) {
    Some(value) => return Some(value)
    None => ()
  }
  match lower_mir_cancelled_local_lvalue(expr, ctx) {
    Some(binding) => lower_mir_post_update(binding, op, MirConst(1L, SInt), ty)
    None => {
      let lhs_ty = self.expr_type(expr, ctx.scope())
      if !lhs_ty.is_integer() &&
        !lhs_ty.is_floating() &&
        !mir_body_pointer_type(lhs_ty) {
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
fn mir_body_floating_update_op(op : String) -> Bool {
  match op {
    "+" | "-" | "*" | "/" => true
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
fn mir_body_scalar_initializer_expr(expr : @parser.Expr) -> @parser.Expr {
  match expr {
    DesignatedField(_, value)
    | DesignatedIndex(_, value)
    | DesignatedRange(_, _, value) => mir_body_scalar_initializer_expr(value)
    _ => expr
  }
}

///|
fn mir_body_char_array_elem_type(ty : @ctype.Type) -> Bool {
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
  ty : @ctype.Type,
  init : @parser.Expr,
  ctx : BodyLowerContext,
) -> Array[MirStmt]? {
  self.lower_mir_array_init_stores_impl(base, ty, init, ctx, true)
}

///|
fn Program::lower_mir_array_init_stores_impl(
  self : Program,
  base : MirValue,
  ty : @ctype.Type,
  init : @parser.Expr,
  ctx : BodyLowerContext,
  zero_first : Bool,
) -> Array[MirStmt]? {
  let (elem_ty, len) = match mir_body_array_local_info(ty) {
    Some(info) => info
    None => return None
  }
  let aggregate_elem = match self.core_type(elem_ty) {
    Struct(_) | Union(_) => true
    _ => false
  }
  let array_elem = match self.core_type(elem_ty) {
    Array(_, _) => true
    _ => false
  }
  if !mir_body_scalar_type(elem_ty) && !aggregate_elem && !array_elem {
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
  if zero_first {
    for i in 0..<len {
      let addr = MirElemAddr(base, MirConst(i.to_int64(), SInt), elem_ty)
      if aggregate_elem || array_elem {
        match self.lower_mir_zero_init_stores(addr, elem_ty) {
          Some(zero_stores) =>
            for store in zero_stores {
              stores.push(store)
            }
          None => return None
        }
      } else {
        stores.push(MirExprStmt(MirStore(addr, MirConst(0L, elem_ty), elem_ty)))
      }
    }
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
    let (start, end, value_expr) = match item {
      DesignatedIndex(i, value) => {
        if i < 0L || i >= len.to_int64() {
          return None
        }
        next_index = i.to_int() + 1
        (i.to_int(), i.to_int(), value)
      }
      DesignatedRange(first, last, value) => {
        if first < 0L || last < first || last >= len.to_int64() {
          return None
        }
        next_index = last.to_int() + 1
        (first.to_int(), last.to_int(), value)
      }
      DesignatedField(_, _) => return None
      _ => {
        if next_index >= len {
          return None
        }
        let index = next_index
        next_index += 1
        (index, index, item)
      }
    }
    for index = start; index <= end; index = index + 1 {
      let addr = MirElemAddr(base, MirConst(index.to_int64(), SInt), elem_ty)
      if aggregate_elem {
        let nested = match value_expr {
          DesignatedField(_, _) =>
            self.lower_mir_struct_init_stores_impl(
              addr,
              elem_ty,
              Array([value_expr]),
              ctx,
              false,
            )
          _ => self.lower_mir_struct_init_stores(addr, elem_ty, value_expr, ctx)
        }
        match nested {
          Some(init_stores) =>
            for store in init_stores {
              stores.push(store)
            }
          None => return None
        }
      } else if array_elem {
        let nested_designator = match value_expr {
          DesignatedIndex(_, _) | DesignatedRange(_, _, _) => true
          _ => false
        }
        let nested_init = if nested_designator {
          @parser.Expr::Array([value_expr])
        } else {
          value_expr
        }
        let nested = self.lower_mir_array_init_stores_impl(
          addr,
          elem_ty,
          nested_init,
          ctx,
          !nested_designator,
        )
        match nested {
          Some(init_stores) =>
            for store in init_stores {
              stores.push(store)
            }
          None => return None
        }
      } else {
        let value = match
          self.lower_mir_expr(mir_body_scalar_initializer_expr(value_expr), ctx) {
          Some(value) => value
          None => return None
        }
        stores.push(MirExprStmt(MirStore(addr, value, elem_ty)))
      }
    }
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
  ty : @ctype.Type,
) -> Array[MirStmt]? {
  match self.core_type(ty) {
    Struct(_) | Union(_) | Array(_, _) =>
      return Some(self.lower_mir_zero_object_stores(base, ty))
    _ => ()
  }
  if mir_body_scalar_type(ty) {
    Some([MirExprStmt(MirStore(base, MirConst(0L, ty), ty))])
  } else {
    None
  }
}

///|
fn Program::lower_mir_zero_object_stores(
  self : Program,
  base : MirValue,
  ty : @ctype.Type,
) -> Array[MirStmt] {
  let stores : Array[MirStmt] = []
  let size = self.type_size(ty)
  let mut offset = 0
  while offset < size {
    let remaining = size - offset
    let (chunk_ty, chunk_size) : (@ctype.Type, Int) = if remaining >= 8 &&
      offset % 8 == 0 {
      (ULongLong, 8)
    } else if remaining >= 4 && offset % 4 == 0 {
      (UInt, 4)
    } else if remaining >= 2 && offset % 2 == 0 {
      (UShort, 2)
    } else {
      (UChar, 1)
    }
    let addr = mir_body_offset_addr_value(base, offset, chunk_ty)
    stores.push(MirExprStmt(MirStore(addr, MirConst(0L, chunk_ty), chunk_ty)))
    offset += chunk_size
  }
  stores
}

///|
fn mir_body_copy_dest_addr(value : MirValue) -> Bool {
  match value {
    MirFuncAddr(_, _) | MirLabelAddr(_) | MirStringAddr(_) => false
    MirElemAddr(base, _, _) | MirOffsetAddr(base, _, _) =>
      mir_body_copy_dest_addr(base)
    _ => true
  }
}

///|
fn mir_body_copy_source_addr(value : MirValue) -> Bool {
  match value {
    MirFuncAddr(_, _) | MirLabelAddr(_) | MirStringAddr(_) => false
    MirElemAddr(base, _, _) | MirOffsetAddr(base, _, _) =>
      mir_body_copy_source_addr(base)
    _ => true
  }
}

///|
fn mir_body_copy_addr_has_side_effect(value : MirValue) -> Bool {
  match value {
    MirConst(_, _)
    | MirLocal(_)
    | MirAddrLocal(_)
    | MirAddrGlobal(_, _)
    | MirFuncAddr(_, _)
    | MirLabelAddr(_)
    | MirStringAddr(_) => false
    MirElemAddr(base, index, _) =>
      mir_body_copy_addr_has_side_effect(base) ||
      mir_body_copy_addr_has_side_effect(index)
    MirOffsetAddr(base, _, _) => mir_body_copy_addr_has_side_effect(base)
    MirLoad(_, _) => true
    MirUnary(_, value, _) | MirCast(_, value) =>
      mir_body_copy_addr_has_side_effect(value)
    MirBinary(_, left, right, _) =>
      mir_body_copy_addr_has_side_effect(left) ||
      mir_body_copy_addr_has_side_effect(right)
    MirAggregateArg(value, _) => mir_body_copy_addr_has_side_effect(value)
    MirVaArg(_, _)
    | MirVaArgAddr(_, _)
    | MirVaStart(_)
    | MirVaCopy(_, _)
    | MirVaEnd(_) => true
    MirBzero(_, _) => true
    MirAtomicLoad(_, _, _) | MirAtomicStore(_, _, _) => true
    MirAtomicUpdate(_, _, _, _, _, _)
    | MirAtomicExchange(_, _, _, _)
    | MirAtomicCompareExchange(_, _, _, _) => true
    MirOverflow(_, _, _, _)
    | MirLibCall(_, _, _)
    | MirCall(_, _, _)
    | MirIndirectCall(_, _, _) => true
    MirAssignLocal(_, _) | MirStore(_, _, _) => true
    MirPostUpdateLocal(_, _, _, _)
    | MirPreUpdateMemory(_, _, _, _)
    | MirPostUpdateMemory(_, _, _, _) => true
    MirTernary(cond, then_, else_, _) =>
      mir_body_copy_addr_has_side_effect(cond) ||
      mir_body_copy_addr_has_side_effect(then_) ||
      mir_body_copy_addr_has_side_effect(else_)
  }
}

///|
fn lower_mir_stable_copy_addr(
  value : MirValue,
  ctx : BodyLowerContext,
) -> (Array[MirStmt], MirValue) {
  if !mir_body_copy_addr_has_side_effect(value) {
    return ([], value)
  }
  let temp = ctx.declare_temp(value.ty())
  ([MirExprStmt(MirAssignLocal(temp, value))], MirLocal(temp))
}

///|
fn prepend_mir_stmts(
  prefix : Array[MirStmt],
  stmts : Array[MirStmt],
) -> Array[MirStmt] {
  if prefix.length() == 0 {
    return stmts
  }
  let result : Array[MirStmt] = []
  for stmt in prefix {
    result.push(stmt)
  }
  for stmt in stmts {
    result.push(stmt)
  }
  result
}

///|
fn Program::lower_mir_union_copy_init_stores(
  self : Program,
  dest_base : MirValue,
  dest_ty : @ctype.Type,
  src_base : MirValue,
  src_ty : @ctype.Type,
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
  let union_layout = self.aggregate_layout_by_name(union_name)
  let size = self.type_size(dest_ty)
  let mut copy_field = ""
  for field in union_layout.fields {
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
    for field in union_layout.fields {
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
      if dest_layout.offset == 0 &&
        src_layout.offset == 0 &&
        self.type_size(dest_layout.ty) == size &&
        self.type_size(src_layout.ty) == size {
        return self.lower_mir_copy_init_stores(
          mir_body_offset_addr_value(
            dest_base,
            dest_layout.offset,
            dest_layout.ty,
          ),
          dest_layout.ty,
          mir_body_offset_addr_value(src_base, src_layout.offset, src_layout.ty),
          src_layout.ty,
        )
      }
    }
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
  dest_ty : @ctype.Type,
  src_base : MirValue,
  src_ty : @ctype.Type,
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
      let layout = self.aggregate_layout_by_name(dest_name)
      let stores : Array[MirStmt] = []
      for field in layout.fields {
        let dest_layout = match self.field_layout(dest_ty, field.name) {
          Some(layout) => layout
          None => return None
        }
        let src_layout = match self.field_layout(src_ty, field.name) {
          Some(layout) => layout
          None => return None
        }
        if field.bit_width is Some(_) {
          stores.push(
            MirExprStmt(
              MirStore(
                mir_body_offset_addr_value(
                  dest_base,
                  dest_layout.offset,
                  dest_layout.ty,
                ),
                MirLoad(
                  mir_body_offset_addr_value(
                    src_base,
                    src_layout.offset,
                    src_layout.ty,
                  ),
                  src_layout.ty,
                ),
                dest_layout.ty,
              ),
            ),
          )
          continue
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
        mir_body_array_element_addressable_type(dest_elem) &&
        self.core_type(dest_elem) == self.core_type(src_elem) {
        let stores : Array[MirStmt] = []
        for i in 0..<dest_len {
          let index = MirConst(i.to_int64(), SInt)
          let dest_addr = MirElemAddr(dest_base, index, dest_elem)
          let src_addr = MirElemAddr(src_base, index, src_elem)
          let nested = match
            self.lower_mir_copy_init_stores(
              dest_addr, dest_elem, src_addr, src_elem,
            ) {
            Some(stores) => stores
            None => return None
          }
          for store in nested {
            stores.push(store)
          }
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
fn Program::lower_mir_va_arg_copy_init_stores(
  self : Program,
  dest_base : MirValue,
  dest_ty : @ctype.Type,
  init : @parser.Expr,
  ctx : BodyLowerContext,
) -> Array[MirStmt]? {
  match init {
    VaArg(ap, va_ty) => {
      if self.core_type(dest_ty) != self.core_type(va_ty) {
        return None
      }
      match self.core_type(va_ty) {
        Struct(_) | Union(_) => ()
        _ => return None
      }
      let ap_value = match self.lower_mir_expr(ap, ctx) {
        Some(value) => value
        None => return None
      }
      let temp = ctx.declare_temp(Pointer(va_ty))
      let stores : Array[MirStmt] = [
        MirExprStmt(MirAssignLocal(temp, MirVaArgAddr(ap_value, va_ty))),
      ]
      let copy_stores = match
        self.lower_mir_copy_init_stores(
          dest_base,
          dest_ty,
          MirLocal(temp),
          va_ty,
        ) {
        Some(stores) => stores
        None => return None
      }
      for store in copy_stores {
        stores.push(store)
      }
      Some(stores)
    }
    _ => None
  }
}

///|
fn Program::lower_mir_struct_init_stores(
  self : Program,
  base : MirValue,
  ty : @ctype.Type,
  init : @parser.Expr,
  ctx : BodyLowerContext,
) -> Array[MirStmt]? {
  self.lower_mir_struct_init_stores_impl(base, ty, init, ctx, true)
}

///|
fn Program::lower_mir_struct_init_stores_impl(
  self : Program,
  base : MirValue,
  ty : @ctype.Type,
  init : @parser.Expr,
  ctx : BodyLowerContext,
  zero_first : Bool,
) -> Array[MirStmt]? {
  let struct_name = match self.core_type(ty) {
    Struct(name) | Union(name) => name
    _ => return None
  }
  match self.lower_mir_va_arg_copy_init_stores(base, ty, init, ctx) {
    Some(stores) => return Some(stores)
    None => ()
  }
  match init {
    Number(_) | Array(_) | CompoundLiteral(_, _, _) | DesignatedField(_, _) =>
      ()
    _ => {
      let src_addr = match self.lower_mir_object_addr(init, ctx) {
        Some(addr) => addr
        None => return None
      }
      if !mir_body_copy_source_addr(src_addr) {
        return None
      }
      let (src_prefix, src_addr) = lower_mir_stable_copy_addr(src_addr, ctx)
      let stores = match
        self.lower_mir_copy_init_stores(
          base,
          ty,
          src_addr,
          self.expr_type(init, ctx.scope()),
        ) {
        Some(stores) => stores
        None => return None
      }
      return Some(prepend_mir_stmts(src_prefix, stores))
    }
  }
  let items : Array[@parser.Expr] = match init {
    Number(value) => if value == 0L { [] } else { return None }
    Array(values) | CompoundLiteral(_, values, _) => values
    DesignatedField(_, _) => [init]
    _ => return None
  }
  let decl = match self.aggregates.get(struct_name) {
    Some(decl) => decl
    None => return None
  }
  let stores : Array[MirStmt] = if zero_first {
    match self.lower_mir_zero_init_stores(base, ty) {
      Some(stores) => stores
      None => return None
    }
  } else {
    []
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
          let nested_designator = match value_expr {
            DesignatedField(_, _)
            | DesignatedIndex(_, _)
            | DesignatedRange(_, _, _) => true
            _ => false
          }
          let nested_init = if nested_designator {
            @parser.Expr::Array([value_expr])
          } else {
            value_expr
          }
          let nested = match self.core_type(layout.ty) {
            Struct(_) | Union(_) =>
              self.lower_mir_struct_init_stores_impl(
                addr,
                layout.ty,
                nested_init,
                ctx,
                !nested_designator,
              )
            _ =>
              self.lower_mir_array_init_stores_impl(
                addr,
                layout.ty,
                nested_init,
                ctx,
                !nested_designator,
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
        if layout.bit_width is Some(_) {
          match value {
            MirConst(0L, _) => continue
            _ =>
              match
                lower_mir_bitfield_store_value(
                  field.ty,
                  mir_body_offset_addr_value(base, layout.offset, layout.ty),
                  layout,
                  value,
                  ctx,
                ) {
                Some(store) => {
                  stores.push(MirExprStmt(store))
                  continue
                }
                None => return None
              }
          }
        }
        let addr = mir_body_offset_addr_value(base, layout.offset, layout.ty)
        stores.push(MirExprStmt(MirStore(addr, value, layout.ty)))
      }
      None =>
        match value {
          MirConst(0L, _) => continue
          _ => return None
        }
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
fn mir_body_aggregate_call_value(value : MirValue) -> Bool {
  match value {
    MirCall(_, _, _) | MirIndirectCall(_, _, _) => true
    _ => false
  }
}

///|
fn mir_body_sequence_exprs(
  stmts : Array[MirStmt],
  tail : MirValue,
  ty : @ctype.Type,
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
fn mir_body_source_builtin_call_name(name : String) -> Bool {
  name.has_prefix("__builtin_") ||
  name.has_prefix("__sync_") ||
  name.has_prefix("__atomic_") ||
  name.has_prefix("__c11_atomic_") ||
  @ctype.builtin_darwin_fd_helper_call_info(name) is Some(_)
}

///|
fn Program::lower_mir_identity_builtin(
  self : Program,
  args : Array[@parser.Expr],
  side_effect_arg : Int?,
  ty : @ctype.Type,
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
fn Program::lower_mir_identity_call_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let (kind, side_effect_arg) = match @ctype.builtin_identity_call_info(name) {
    Some(info) => info
    None => return None
  }
  if (kind == "unpredictable" || kind == "return_address_transform") &&
    args.length() != 1 {
    return None
  }
  self.lower_mir_identity_builtin(
    args,
    if side_effect_arg >= 0 {
      Some(side_effect_arg)
    } else {
      None
    },
    ty,
    ctx,
  )
}

///|
fn Program::lower_mir_alloca_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if !(self.core_type(ty) is Pointer(_)) {
    return None
  }
  match @ctype.builtin_stack_alloc_call_info(name) {
    Some(("alloca", expected_arg_count)) =>
      if args.length() == expected_arg_count {
        match self.lower_mir_call_arg(args[0], ctx) {
          Some(size) => Some(MirUnary("alloca", size, ty))
          None => None
        }
      } else {
        None
      }
    Some(("alloca_align", expected_arg_count)) =>
      if args.length() == expected_arg_count {
        match
          (
            self.lower_mir_call_arg(args[0], ctx),
            self.lower_mir_call_arg(args[1], ctx),
          ) {
          (Some(size), Some(align_bits)) =>
            Some(MirBinary("alloca_align", size, align_bits, ty))
          _ => None
        }
      } else {
        None
      }
    Some(_) | None => None
  }
}

///|
fn Program::lower_mir_heap_libcall_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  match @ctype.builtin_heap_libcall_info(name, args.length()) {
    Some((symbol, call_arg_count)) => {
      if symbol == "free" {
        if !(self.core_type(ty) is Void) {
          return None
        }
      } else if !mir_body_pointer_type(ty) {
        return None
      }
      let values : Array[MirValue] = []
      for i in 0..<call_arg_count {
        match self.lower_mir_call_arg(args[i], ctx) {
          Some(value) =>
            values.push(
              mir_body_cast_call_arg(
                value,
                @ctype.builtin_heap_libcall_arg_type(symbol, i),
              ),
            )
          None => return None
        }
      }
      Some(MirLibCall(symbol, values, ty))
    }
    None => None
  }
}

///|
fn Program::lower_mir_address_query_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let op = match @ctype.builtin_address_query_info(name) {
    Some(op) => op
    None => return None
  }
  if args.length() > 1 || !(self.core_type(ty) is Pointer(_)) {
    return None
  }
  let level = if args.length() == 0 {
    MirConst(0L, SInt)
  } else {
    let level_ty = self.expr_type(args[0], ctx.scope())
    if !self.core_type(level_ty).is_integer() {
      return None
    }
    match self.lower_mir_call_arg(args[0], ctx) {
      Some(value) => value
      None => return None
    }
  }
  Some(MirUnary(op, level, ty))
}

///|
fn Program::lower_mir_fence_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if !(self.core_type(ty) is Void) {
    return None
  }
  let (op, expected_arg_count) = match @ctype.builtin_fence_call_info(name) {
    Some(info) => info
    None => return None
  }
  if args.length() != expected_arg_count {
    return None
  }
  if expected_arg_count == 0 {
    return Some(MirUnary(op, MirConst(0L, SInt), ty))
  }
  let order_ty = self.expr_type(args[0], ctx.scope())
  if !self.core_type(order_ty).is_integer() {
    return None
  }
  match self.lower_mir_call_arg(args[0], ctx) {
    Some(order) => Some(MirUnary(op, order, ty))
    None => None
  }
}

///|
fn Program::lower_mir_trap_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
) -> MirValue? {
  if !(self.core_type(ty) is Void) || args.length() != 0 {
    return None
  }
  match @ctype.builtin_trap_call_info(name) {
    Some("trap") => Some(MirUnary("trap", MirConst(0L, SInt), ty))
    _ => None
  }
}

///|
fn Program::lower_mir_noop_call_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let kind = match @ctype.builtin_noop_call_info(name) {
    Some(kind) => kind
    None => return None
  }
  match kind {
    "ignore_all" => Some(MirConst(0L, ty))
    "eval_first" =>
      if args.length() == 0 {
        Some(MirConst(0L, ty))
      } else {
        match self.lower_mir_call_arg(args[0], ctx) {
          Some(value) => Some(MirBinary(",", value, MirConst(0L, ty), ty))
          None => None
        }
      }
    "eval_all" => {
      let side_effects : Array[MirStmt] = []
      for arg in args {
        match self.lower_mir_call_arg(arg, ctx) {
          Some(value) => side_effects.push(MirExprStmt(value))
          None => return None
        }
      }
      mir_body_sequence_exprs(side_effects, MirConst(0L, ty), ty)
    }
    _ => None
  }
}

///|
fn mir_body_alignment_operand_supported(ty : @ctype.Type) -> Bool {
  match ty {
    Pointer(_) | FuncPtr(_, _, _) => true
    _ => ty.is_integer()
  }
}

///|
fn Program::lower_mir_alignment_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let (kind, result_ty) = match
    @ctype.integer_alignment_builtin_info(name, ty) {
    Some(info) => info
    None => return None
  }
  if args.length() < 2 {
    return Some(MirConst(0L, result_ty))
  }
  let value = match self.lower_mir_call_arg(args[0], ctx) {
    Some(value) => value
    None => return None
  }
  let align = match self.lower_mir_call_arg(args[1], ctx) {
    Some(value) => value
    None => return None
  }
  if !mir_body_alignment_operand_supported(self.core_type(value.ty())) ||
    !mir_body_alignment_operand_supported(self.core_type(align.ty())) {
    return None
  }
  let value_temp = ctx.declare_temp(value.ty())
  let align_temp = ctx.declare_temp(align.ty())
  let value_bits = MirCast(ULongLong, MirLocal(value_temp))
  let align_bits = MirCast(ULongLong, MirLocal(align_temp))
  let one = MirConst(1L, ULongLong)
  let zero = MirConst(0L, ULongLong)
  let align_minus_one = MirBinary("-", align_bits, one, ULongLong)
  let neg_align = MirUnary("-", align_bits, ULongLong)
  let masked = match kind {
    "is_aligned" => MirBinary("&", value_bits, align_minus_one, ULongLong)
    "align_up" =>
      MirBinary(
        "&",
        MirBinary("+", value_bits, align_minus_one, ULongLong),
        neg_align,
        ULongLong,
      )
    _ => MirBinary("&", value_bits, neg_align, ULongLong)
  }
  let result = if kind == "is_aligned" {
    MirBinary("==", masked, zero, result_ty)
  } else {
    MirCast(result_ty, masked)
  }
  mir_body_sequence_exprs(
    [
      MirExprStmt(MirAssignLocal(value_temp, value)),
      MirExprStmt(MirAssignLocal(align_temp, align)),
    ],
    result,
    result_ty,
  )
}

///|
fn Program::lower_mir_object_size_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  match @ctype.builtin_object_size_call_info(name) {
    Some(_) => ()
    None => return None
  }
  if args.length() == 0 || !ty.is_integer() {
    return None
  }
  let mode = if args.length() > 1 {
    match self.fold_const(args[1], ctx.scope()) {
      Some(value) => value
      None => 0L
    }
  } else {
    0L
  }
  Some(MirConst(self.object_size_value(args[0], ctx.scope(), mode), ty))
}

///|
fn Program::lower_mir_constant_query_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if !ty.is_integer() {
    return None
  }
  match @ctype.builtin_constant_query_call_info(name) {
    Some(kind) =>
      match
        @ctype.builtin_constant_query_result(
          kind,
          args.length() > 0 && self.fold_const(args[0], ctx.scope()) is Some(_),
        ) {
        Some(value) => Some(MirConst(value, ty))
        None => None
      }
    None =>
      match @ctype.builtin_fixed_int_constant_call_info(name) {
        Some((value, expected_arg_count)) =>
          if args.length() == expected_arg_count {
            Some(MirConst(value, ty))
          } else {
            None
          }
        None => None
      }
  }
}

///|
fn mir_body_atomic_lock_free_predicate(
  size : MirValue,
  ty : @ctype.Type,
) -> MirValue {
  let bytes = MirCast(ULongLong, size)
  let one = MirBinary("==", bytes, MirConst(1L, ULongLong), Bool)
  let two = MirBinary("==", bytes, MirConst(2L, ULongLong), Bool)
  let four = MirBinary("==", bytes, MirConst(4L, ULongLong), Bool)
  let eight = MirBinary("==", bytes, MirConst(8L, ULongLong), Bool)
  MirCast(
    ty,
    MirBinary(
      "||",
      MirBinary("||", one, two, Bool),
      MirBinary("||", four, eight, Bool),
      Bool,
    ),
  )
}

///|
fn Program::lower_mir_atomic_lock_free_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if !ty.is_integer() && !(self.core_type(ty) is Bool) {
    return None
  }
  let (kind, evaluate_pointer) = match
    @ctype.builtin_atomic_lock_free_call_info(name) {
    Some(info) => info
    None => return None
  }
  match kind {
    "always_lock_free" => {
      if args.length() == 0 {
        return None
      }
      match self.fold_const(args[0], ctx.scope()) {
        Some(size) =>
          Some(
            MirConst(
              if @ctype.builtin_atomic_lock_free_size_supported(size) {
                1L
              } else {
                0L
              },
              ty,
            ),
          )
        None => None
      }
    }
    "is_lock_free" => {
      if args.length() == 0 {
        return None
      }
      let size = match self.lower_mir_call_arg(args[0], ctx) {
        Some(value) => value
        None => return None
      }
      if !self.core_type(size.ty()).is_integer() {
        return None
      }
      let size_temp = ctx.declare_temp(size.ty())
      let side_effects = [MirExprStmt(MirAssignLocal(size_temp, size))]
      if evaluate_pointer && args.length() > 1 {
        let ptr = match self.lower_mir_call_arg(args[1], ctx) {
          Some(value) => value
          None => return None
        }
        side_effects.push(MirExprStmt(ptr))
      }
      mir_body_sequence_exprs(
        side_effects,
        mir_body_atomic_lock_free_predicate(MirLocal(size_temp), ty),
        ty,
      )
    }
    _ => None
  }
}

///|
fn Program::mir_body_fp_compare_operand_supported(
  self : Program,
  ty : @ctype.Type,
) -> Bool {
  let core = self.core_type(ty)
  core.is_integer() || self.is_floating_type(core)
}

///|
fn Program::lower_mir_fp_compare_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let op = match @ctype.floating_builtin_compare_op(name) {
    Some(value) => value
    None => return None
  }
  if args.length() < 2 {
    return Some(MirConst(0L, ty))
  }
  let scope = ctx.scope()
  let lhs_ty = self.expr_type(args[0], scope)
  let rhs_ty = self.expr_type(args[1], scope)
  if !self.mir_body_fp_compare_operand_supported(lhs_ty) ||
    !self.mir_body_fp_compare_operand_supported(rhs_ty) ||
    (!self.is_floating_type(lhs_ty) && !self.is_floating_type(rhs_ty)) {
    return None
  }
  match
    (
      self.lower_mir_call_arg(args[0], ctx),
      self.lower_mir_call_arg(args[1], ctx),
    ) {
    (Some(left), Some(right)) => Some(MirBinary(op, left, right, ty))
    _ => None
  }
}

///|
fn Program::lower_mir_fp_class_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let (kind, class_ty) = match
    @ctype.floating_builtin_runtime_class_info(name) {
    Some(value) => value
    None => return None
  }
  if args.length() == 0 {
    return Some(MirConst(0L, ty))
  }
  let scope = ctx.scope()
  let arg_ty = self.expr_type(args[0], scope)
  if !self.mir_body_fp_compare_operand_supported(arg_ty) {
    return None
  }
  match self.lower_mir_call_arg(args[0], ctx) {
    Some(value) => Some(MirUnary("fp_" + kind, MirCast(class_ty, value), ty))
    None => None
  }
}

///|
fn mir_body_float_const_value(value : Double, ty : @ctype.Type) -> MirValue {
  let bits = value.reinterpret_as_int64()
  match ty {
    Float => MirCast(Float, MirConst(bits, Double))
    _ => MirConst(bits, ty)
  }
}

///|
fn Program::lower_mir_floating_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let scope = ctx.scope()
  match @ctype.floating_builtin_constant_bits_info(name) {
    Some(_) => {
      for arg in args {
        if !mir_body_side_effect_free_expr(arg) {
          return None
        }
      }
      match self.fold_float_const(Call(Var(name), args), scope) {
        Some(value) => Some(mir_body_float_const_value(value, ty))
        None => None
      }
    }
    None => None
  }
}

///|
fn Program::lower_mir_fp_math_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let (op, math_ty, arity) = match
    @ctype.floating_builtin_runtime_math_info(name) {
    Some(value) => value
    None => return None
  }
  if args.length() < arity {
    return Some(MirConst(0L, ty))
  }
  let scope = ctx.scope()
  for i in 0..<arity {
    if !self.mir_body_fp_compare_operand_supported(
        self.expr_type(args[i], scope),
      ) {
      return None
    }
  }
  match op {
    "fabs" =>
      match self.lower_mir_call_arg(args[0], ctx) {
        Some(value) => Some(MirUnary("fabs", MirCast(math_ty, value), ty))
        None => None
      }
    "sqrt" =>
      match self.lower_mir_call_arg(args[0], ctx) {
        Some(value) => Some(MirUnary("fsqrt", MirCast(math_ty, value), ty))
        None => None
      }
    "copysign" =>
      match
        (
          self.lower_mir_call_arg(args[0], ctx),
          self.lower_mir_call_arg(args[1], ctx),
        ) {
        (Some(magnitude), Some(sign)) =>
          Some(
            MirBinary(
              "copysign",
              MirCast(math_ty, magnitude),
              MirCast(math_ty, sign),
              ty,
            ),
          )
        _ => None
      }
    _ => None
  }
}

///|
fn Program::lower_mir_integer_unary_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if args.length() != 1 {
    return None
  }
  let op = match @ctype.integer_count_builtin_info(name) {
    Some((kind, width)) => kind + width.to_string()
    None =>
      match @ctype.integer_abs_builtin_type(name) {
        Some(abs_ty) =>
          if self.type_size(abs_ty) <= 4 {
            "abs32"
          } else {
            "abs64"
          }
        None =>
          match @ctype.integer_bswap_builtin_info(name, ty) {
            Some((_, width)) => "bswap" + width.to_string()
            None => return None
          }
      }
  }
  match self.lower_mir_call_arg(args[0], ctx) {
    Some(value) => Some(MirUnary(op, value, ty))
    None => None
  }
}

///|
fn mir_body_rotate_builtin_op(width : Int, left : Bool) -> String? {
  match (width, left) {
    (32, true) => Some("rotl32")
    (32, false) => Some("rotr32")
    (64, true) => Some("rotl64")
    (64, false) => Some("rotr64")
    _ => None
  }
}

///|
fn Program::lower_mir_rotate_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if args.length() < 2 {
    return match @ctype.integer_rotate_builtin_info(name, UInt) {
      Some(_) => Some(MirConst(0L, ty))
      None => None
    }
  }
  let scope = ctx.scope()
  let arg_ty = self.expr_type(args[0], scope)
  let shift_ty = self.expr_type(args[1], scope)
  let arg_core = self.core_type(arg_ty)
  let shift_core = self.core_type(shift_ty)
  if !arg_core.is_integer() || !shift_core.is_integer() {
    return None
  }
  match (arg_core, shift_core) {
    (SInt128 | UInt128, _) | (_, SInt128 | UInt128) => return None
    _ => ()
  }
  let (value_ty, width, left) = match
    @ctype.integer_rotate_builtin_info(name, arg_ty) {
    Some(info) => info
    None => return None
  }
  let op = match mir_body_rotate_builtin_op(width, left) {
    Some(value) => value
    None => return None
  }
  match
    (
      self.lower_mir_call_arg(args[0], ctx),
      self.lower_mir_call_arg(args[1], ctx),
    ) {
    (Some(value), Some(shift)) =>
      Some(MirBinary(op, MirCast(value_ty, value), shift, ty))
    _ => None
  }
}

///|
fn Program::lower_mir_overflow_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let op = match @ctype.builtin_overflow_op(name) {
    Some(value) => value
    None => return None
  }
  if !(self.core_type(ty) is Bool) || args.length() != 3 {
    return None
  }
  match
    (
      self.lower_mir_call_arg(args[0], ctx),
      self.lower_mir_call_arg(args[1], ctx),
      self.lower_mir_call_arg(args[2], ctx),
    ) {
    (Some(left), Some(right), Some(result)) => {
      let result_ty = match self.pointer_element(result.ty()) {
        Some(value) => value
        None => return None
      }
      match self.core_type(result_ty).const_int_width() {
        Some(width) if width <= 64 => Some(MirOverflow(op, left, right, result))
        _ => None
      }
    }
    _ => None
  }
}

///|
fn Program::lower_mir_va_setup_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if !(self.core_type(ty) is Void) {
    return None
  }
  let (op, expected_arg_count) = match @ctype.builtin_va_setup_call_info(name) {
    Some(info) => info
    None => return None
  }
  if args.length() != expected_arg_count {
    return None
  }
  match op {
    "va_start" =>
      match self.lower_mir_call_arg(args[0], ctx) {
        Some(target) =>
          match target {
            MirLocal(_) => Some(MirVaStart(target))
            _ => None
          }
        None => None
      }
    "va_copy" =>
      match
        (
          self.lower_mir_call_arg(args[0], ctx),
          self.lower_mir_call_arg(args[1], ctx),
        ) {
        (Some(target), Some(source)) =>
          match target {
            MirLocal(_) => Some(MirVaCopy(target, source))
            _ => None
          }
        _ => None
      }
    "va_end" =>
      match self.lower_mir_call_arg(args[0], ctx) {
        Some(target) => Some(MirVaEnd(target))
        None => None
      }
    _ => None
  }
}

///|
fn Program::lower_mir_bzero_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if !(self.core_type(ty) is Void) {
    return None
  }
  match @ctype.builtin_zero_memory_call_info(name) {
    Some(("bzero", expected_arg_count)) =>
      if args.length() != expected_arg_count {
        return None
      }
    Some(_) | None => return None
  }
  match
    (
      self.lower_mir_call_arg(args[0], ctx),
      self.lower_mir_call_arg(args[1], ctx),
    ) {
    (Some(dst), Some(size)) => Some(MirBzero(dst, size))
    _ => None
  }
}

///|
fn Program::lower_mir_darwin_fd_helper_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let (op, expected_arg_count) = match
    @ctype.builtin_darwin_fd_helper_call_info(name) {
    Some(info) => info
    None => return None
  }
  if args.length() != expected_arg_count || !mir_body_scalar_type(ty) {
    return None
  }
  if op == "isset" && self.core_type(ty) is Void {
    return None
  }
  let fd_value = match self.lower_mir_call_arg(args[0], ctx) {
    Some(value) => value
    None => return None
  }
  if !self.core_type(fd_value.ty()).is_integer() {
    return None
  }
  let set_value = match self.lower_mir_call_arg(args[1], ctx) {
    Some(value) => value
    None => return None
  }
  if self.pointer_element(set_value.ty()) is None {
    return None
  }
  let fd_temp = ctx.declare_temp(fd_value.ty())
  let set_temp = ctx.declare_temp(set_value.ty())
  let fd_bits = MirCast(ULongLong, MirLocal(fd_temp))
  let word_index = MirBinary(">>", fd_bits, MirConst(5L, ULongLong), ULongLong)
  let bit_index = MirBinary("&", fd_bits, MirConst(31L, ULongLong), ULongLong)
  let mask = MirBinary("<<", MirConst(1L, SInt), MirCast(SInt, bit_index), SInt)
  let set_base = MirOffsetAddr(
    MirCast(Pointer(SInt), MirLocal(set_temp)),
    0,
    SInt,
  )
  let slot = MirElemAddr(set_base, word_index, SInt)
  let loaded = MirLoad(slot, SInt)
  let result = match op {
    "set" => {
      let updated = MirBinary("|", loaded, mask, SInt)
      let store = MirStore(slot, updated, SInt)
      MirBinary(",", store, MirConst(0L, ty), ty)
    }
    "clr" => {
      let updated = MirBinary("&", loaded, MirUnary("~", mask, SInt), SInt)
      let store = MirStore(slot, updated, SInt)
      MirBinary(",", store, MirConst(0L, ty), ty)
    }
    "isset" => {
      let present = MirBinary("&", loaded, mask, SInt)
      MirBinary("!=", present, MirConst(0L, SInt), ty)
    }
    _ => return None
  }
  mir_body_sequence_exprs(
    [
      MirExprStmt(MirAssignLocal(fd_temp, fd_value)),
      MirExprStmt(MirAssignLocal(set_temp, set_value)),
    ],
    result,
    ty,
  )
}

///|
fn Program::lower_mir_strlen_libcall_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if !ty.is_integer() {
    return None
  }
  match @ctype.builtin_length_libcall_info(name, args.length()) {
    Some((symbol, call_arg_count)) => {
      let values : Array[MirValue] = []
      for i in 0..<call_arg_count {
        match self.lower_mir_call_arg(args[i], ctx) {
          Some(value) =>
            values.push(
              mir_body_cast_call_arg(
                value,
                @ctype.builtin_length_libcall_arg_type(i),
              ),
            )
          None => return None
        }
      }
      Some(MirLibCall(symbol, values, ty))
    }
    None => None
  }
}

///|
fn mir_body_cast_call_arg(value : MirValue, ty : @ctype.Type) -> MirValue {
  if value.ty() == ty {
    value
  } else {
    MirCast(ty, value)
  }
}

///|
fn Program::lower_mir_memory_libcall_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if !(self.core_type(ty) is Pointer(_)) {
    return None
  }
  match @ctype.builtin_memory_libcall_info(name, args.length()) {
    Some((symbol, call_arg_count)) => {
      let values : Array[MirValue] = []
      for i in 0..<call_arg_count {
        match self.lower_mir_call_arg(args[i], ctx) {
          Some(value) =>
            values.push(
              mir_body_cast_call_arg(
                value,
                @ctype.builtin_memory_libcall_arg_type(symbol, i),
              ),
            )
          None => return None
        }
      }
      let call = MirLibCall(symbol, values, ty)
      if args.length() == call_arg_count ||
        mir_body_side_effect_free_expr(args[call_arg_count]) {
        Some(call)
      } else {
        match self.lower_mir_call_arg(args[call_arg_count], ctx) {
          Some(side) => Some(MirBinary(",", side, call, ty))
          None => None
        }
      }
    }
    None => None
  }
}

///|
fn Program::lower_mir_compare_libcall_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if !ty.is_integer() {
    return None
  }
  match @ctype.builtin_compare_libcall_info(name, args.length()) {
    Some((symbol, call_arg_count)) => {
      let values : Array[MirValue] = []
      for i in 0..<call_arg_count {
        match self.lower_mir_call_arg(args[i], ctx) {
          Some(value) =>
            values.push(
              mir_body_cast_call_arg(
                value,
                @ctype.builtin_compare_libcall_arg_type(symbol, i),
              ),
            )
          None => return None
        }
      }
      Some(MirLibCall(symbol, values, ty))
    }
    None => None
  }
}

///|
fn Program::lower_mir_search_libcall_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if !mir_body_pointer_type(ty) {
    return None
  }
  match @ctype.builtin_search_libcall_info(name, args.length()) {
    Some((symbol, call_arg_count)) => {
      let values : Array[MirValue] = []
      for i in 0..<call_arg_count {
        match self.lower_mir_call_arg(args[i], ctx) {
          Some(value) =>
            values.push(
              mir_body_cast_call_arg(
                value,
                @ctype.builtin_search_libcall_arg_type(symbol, i),
              ),
            )
          None => return None
        }
      }
      Some(MirLibCall(symbol, values, ty))
    }
    None => None
  }
}

///|
fn Program::lower_mir_span_libcall_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  match @ctype.builtin_span_libcall_info(name, args.length()) {
    Some((symbol, call_arg_count)) => {
      if symbol == "strpbrk" {
        if !mir_body_pointer_type(ty) {
          return None
        }
      } else if !ty.is_integer() {
        return None
      }
      let values : Array[MirValue] = []
      for i in 0..<call_arg_count {
        match self.lower_mir_call_arg(args[i], ctx) {
          Some(value) =>
            values.push(mir_body_cast_call_arg(value, Pointer(SChar)))
          None => return None
        }
      }
      Some(MirLibCall(symbol, values, ty))
    }
    None => None
  }
}

///|
fn Program::lower_mir_strl_libcall_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if !ty.is_integer() {
    return None
  }
  match @ctype.builtin_strl_libcall_info(name, args.length()) {
    Some((symbol, call_arg_count)) => {
      let values : Array[MirValue] = []
      for i in 0..<call_arg_count {
        match self.lower_mir_call_arg(args[i], ctx) {
          Some(value) =>
            values.push(
              mir_body_cast_call_arg(
                value,
                @ctype.builtin_strl_libcall_arg_type(i),
              ),
            )
          None => return None
        }
      }
      let call = MirLibCall(symbol, values, ty)
      if mir_body_side_effect_free_expr(args[call_arg_count]) {
        Some(call)
      } else {
        match self.lower_mir_call_arg(args[call_arg_count], ctx) {
          Some(side) => Some(MirBinary(",", side, call, ty))
          None => None
        }
      }
    }
    None => None
  }
}

///|
fn Program::lower_mir_checked_printf_libcall_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if !ty.is_integer() {
    return None
  }
  match
    (
      @ctype.builtin_printf_libcall_symbol(name, args.length()),
      @ctype.builtin_printf_source_indexes(name, args.length()),
    ) {
    (Some(symbol), Some(source_indexes)) => {
      let values : Array[MirValue] = []
      for i in 0..<source_indexes.length() {
        let source_index = source_indexes[i]
        match self.lower_mir_call_arg(args[source_index], ctx) {
          Some(value) =>
            match @ctype.builtin_printf_libcall_arg_type(symbol, i) {
              Some(expected) =>
                values.push(mir_body_cast_call_arg(value, expected))
              None => values.push(value)
            }
          None => return None
        }
      }
      let side_effects : Array[MirStmt] = []
      for i in 0..<args.length() {
        if !@ctype.builtin_printf_source_index_used(source_indexes, i) &&
          !mir_body_side_effect_free_expr(args[i]) {
          match self.lower_mir_call_arg(args[i], ctx) {
            Some(value) => side_effects.push(MirExprStmt(value))
            None => return None
          }
        }
      }
      let call = MirLibCall(symbol, values, ty)
      if side_effects.length() == 0 {
        Some(call)
      } else {
        mir_body_sequence_exprs(side_effects, call, ty)
      }
    }
    _ => None
  }
}

///|
fn Program::lower_mir_atomic_load_store_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  match @ctype.builtin_atomic_load_store_call_info(name) {
    Some(("load_ptr", min_arg_count)) => {
      if args.length() < min_arg_count || !(self.core_type(ty) is Void) {
        return None
      }
      let elem_ty = self.expr_type(args[0], ctx.scope()).atomic_target()
      if !mir_body_scalar_type(elem_ty) {
        return None
      }
      let order_ty = self.expr_type(args[2], ctx.scope())
      if !self.core_type(order_ty).is_integer() {
        return None
      }
      match
        (
          self.lower_mir_call_arg(args[0], ctx),
          self.lower_mir_call_arg(args[1], ctx),
          self.lower_mir_call_arg(args[2], ctx),
        ) {
        (Some(ptr), Some(result_ptr), Some(order)) =>
          Some(
            MirStore(result_ptr, MirAtomicLoad(ptr, order, elem_ty), elem_ty),
          )
        _ => None
      }
    }
    Some(("load_value", min_arg_count)) => {
      if args.length() < min_arg_count || !mir_body_scalar_type(ty) {
        return None
      }
      let order_ty = self.expr_type(args[1], ctx.scope())
      if !self.core_type(order_ty).is_integer() {
        return None
      }
      match
        (
          self.lower_mir_call_arg(args[0], ctx),
          self.lower_mir_call_arg(args[1], ctx),
        ) {
        (Some(ptr), Some(order)) => Some(MirAtomicLoad(ptr, order, ty))
        _ => None
      }
    }
    Some(("store_ptr", min_arg_count)) => {
      if args.length() < min_arg_count || !(self.core_type(ty) is Void) {
        return None
      }
      let elem_ty = self.expr_type(args[0], ctx.scope()).atomic_target()
      if !mir_body_scalar_type(elem_ty) {
        return None
      }
      let order_ty = self.expr_type(args[2], ctx.scope())
      if !self.core_type(order_ty).is_integer() {
        return None
      }
      match
        (
          self.lower_mir_call_arg(args[0], ctx),
          self.lower_mir_call_arg(args[1], ctx),
          self.lower_mir_call_arg(args[2], ctx),
        ) {
        (Some(ptr), Some(source_ptr), Some(order)) =>
          Some(MirAtomicStore(ptr, MirLoad(source_ptr, elem_ty), order))
        _ => None
      }
    }
    Some(("store_value", min_arg_count)) => {
      if args.length() < min_arg_count || !(self.core_type(ty) is Void) {
        return None
      }
      let elem_ty = self.expr_type(args[0], ctx.scope()).atomic_target()
      if !mir_body_scalar_type(elem_ty) {
        return None
      }
      let order = if args.length() >= 3 {
        let order_ty = self.expr_type(args[2], ctx.scope())
        if !self.core_type(order_ty).is_integer() {
          return None
        }
        match self.lower_mir_call_arg(args[2], ctx) {
          Some(value) => value
          None => return None
        }
      } else {
        MirConst(0L, SInt)
      }
      match
        (
          self.lower_mir_call_arg(args[0], ctx),
          self.lower_mir_expr_for_target_type(elem_ty, args[1], ctx),
        ) {
        (Some(ptr), Some(value)) => Some(MirAtomicStore(ptr, value, order))
        _ => None
      }
    }
    Some(_) => None
    None =>
      match @ctype.builtin_atomic_zero_store_call_info(name) {
        Some((op, min_arg_count)) => {
          if args.length() < min_arg_count || !(self.core_type(ty) is Void) {
            return None
          }
          let elem_ty = self.expr_type(args[0], ctx.scope()).atomic_target()
          if !elem_ty.is_integer() && !(self.core_type(elem_ty) is Bool) {
            return None
          }
          let order = match op {
            "clear" =>
              if args.length() >= 2 {
                let order_ty = self.expr_type(args[1], ctx.scope())
                if !self.core_type(order_ty).is_integer() {
                  return None
                }
                match self.lower_mir_call_arg(args[1], ctx) {
                  Some(value) => value
                  None => return None
                }
              } else {
                MirConst(0L, SInt)
              }
            "release" => MirConst(0L, SInt)
            _ => return None
          }
          match self.lower_mir_call_arg(args[0], ctx) {
            Some(ptr) => Some(MirAtomicStore(ptr, MirConst(0L, elem_ty), order))
            None => None
          }
        }
        None => None
      }
  }
}

///|
fn Program::lower_mir_atomic_extra_args(
  self : Program,
  args : Array[@parser.Expr],
  start : Int,
  ctx : BodyLowerContext,
) -> Array[MirValue]? {
  let values : Array[MirValue] = []
  for i in start..<args.length() {
    match self.lower_mir_call_arg(args[i], ctx) {
      Some(value) => values.push(value)
      None => return None
    }
  }
  Some(values)
}

///|
fn Program::lower_mir_sync_compare_exchange_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let (op, min_arg_count, extra_start) = match
    @ctype.builtin_atomic_compare_exchange_call_info(name) {
    Some((op, min_arg_count, extra_start)) =>
      match op {
        "sync_compare_exchange_bool" | "sync_compare_exchange_value" =>
          (op, min_arg_count, extra_start)
        _ => return None
      }
    None => return None
  }
  if args.length() < min_arg_count {
    return None
  }
  let elem_ty = self.expr_type(args[0], ctx.scope()).atomic_target()
  if !elem_ty.is_integer() {
    return None
  }
  let extras = match self.lower_mir_atomic_extra_args(args, extra_start, ctx) {
    Some(values) => values
    None => return None
  }
  match
    (
      self.lower_mir_call_arg(args[0], ctx),
      self.lower_mir_expr_for_target_type(elem_ty, args[1], ctx),
      self.lower_mir_expr_for_target_type(elem_ty, args[2], ctx),
    ) {
    (Some(ptr), Some(expected_value), Some(desired)) => {
      let expected = ctx.declare_temp(elem_ty)
      let setup = MirAssignLocal(expected, expected_value)
      let cmp = MirAtomicCompareExchange(
        ptr,
        MirAddrLocal(expected),
        desired,
        extras,
      )
      match op {
        "sync_compare_exchange_bool" =>
          if self.core_type(ty) is Bool {
            Some(MirBinary(",", setup, MirCast(ty, cmp), ty))
          } else {
            None
          }
        "sync_compare_exchange_value" =>
          if mir_body_scalar_type(ty) {
            Some(
              MirBinary(
                ",",
                setup,
                MirBinary(",", cmp, MirCast(ty, MirLocal(expected)), ty),
                ty,
              ),
            )
          } else {
            None
          }
        _ => None
      }
    }
    _ => None
  }
}

///|
fn Program::lower_mir_atomic_rmw_builtin(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  match @ctype.builtin_atomic_update_call_info(name) {
    Some((op, return_new, min_arg_count, extra_start)) => {
      if args.length() < min_arg_count || !mir_body_scalar_type(ty) {
        return None
      }
      let elem_ty = self.expr_type(args[0], ctx.scope()).atomic_target()
      if !elem_ty.is_integer() {
        return None
      }
      let extras = match
        self.lower_mir_atomic_extra_args(args, extra_start, ctx) {
        Some(values) => values
        None => return None
      }
      match
        (
          self.lower_mir_call_arg(args[0], ctx),
          self.lower_mir_expr_for_target_type(elem_ty, args[1], ctx),
        ) {
        (Some(ptr), Some(value)) =>
          Some(MirAtomicUpdate(op, return_new, ptr, value, extras, ty))
        _ => None
      }
    }
    None =>
      match @ctype.builtin_atomic_exchange_call_info(name) {
        Some(("exchange_ptr", min_arg_count, extra_start)) => {
          if args.length() < min_arg_count || !(self.core_type(ty) is Void) {
            return None
          }
          let elem_ty = self.expr_type(args[0], ctx.scope()).atomic_target()
          if !elem_ty.is_integer() {
            return None
          }
          let extras = match
            self.lower_mir_atomic_extra_args(args, extra_start, ctx) {
            Some(values) => values
            None => return None
          }
          match
            (
              self.lower_mir_call_arg(args[0], ctx),
              self.lower_mir_call_arg(args[1], ctx),
              self.lower_mir_call_arg(args[2], ctx),
            ) {
            (Some(ptr), Some(source_ptr), Some(result_ptr)) => {
              let old = ctx.declare_temp(elem_ty)
              Some(
                MirBinary(
                  ",",
                  MirAssignLocal(
                    old,
                    MirAtomicExchange(
                      ptr,
                      MirLoad(source_ptr, elem_ty),
                      extras,
                      elem_ty,
                    ),
                  ),
                  MirStore(result_ptr, MirLocal(old), elem_ty),
                  elem_ty,
                ),
              )
            }
            _ => None
          }
        }
        Some(("test_and_set", min_arg_count, extra_start)) => {
          if args.length() < min_arg_count || !(self.core_type(ty) is Bool) {
            return None
          }
          let elem_ty = self.expr_type(args[0], ctx.scope()).atomic_target()
          if !elem_ty.is_integer() && !(self.core_type(elem_ty) is Bool) {
            return None
          }
          let extras = match
            self.lower_mir_atomic_extra_args(args, extra_start, ctx) {
            Some(values) => values
            None => return None
          }
          match self.lower_mir_call_arg(args[0], ctx) {
            Some(ptr) =>
              Some(
                MirCast(
                  ty,
                  MirAtomicExchange(ptr, MirConst(1L, elem_ty), extras, elem_ty),
                ),
              )
            None => None
          }
        }
        Some(("exchange_value", min_arg_count, extra_start)) => {
          if args.length() < min_arg_count || !mir_body_scalar_type(ty) {
            return None
          }
          let elem_ty = self.expr_type(args[0], ctx.scope()).atomic_target()
          if !elem_ty.is_integer() {
            return None
          }
          let extras = match
            self.lower_mir_atomic_extra_args(args, extra_start, ctx) {
            Some(values) => values
            None => return None
          }
          match
            (
              self.lower_mir_call_arg(args[0], ctx),
              self.lower_mir_expr_for_target_type(elem_ty, args[1], ctx),
            ) {
            (Some(ptr), Some(value)) =>
              Some(MirAtomicExchange(ptr, value, extras, ty))
            _ => None
          }
        }
        Some(("sync_exchange_value", min_arg_count, extra_start)) => {
          if args.length() < min_arg_count || !mir_body_scalar_type(ty) {
            return None
          }
          let elem_ty = self.expr_type(args[0], ctx.scope()).atomic_target()
          if !elem_ty.is_integer() && !(self.core_type(elem_ty) is Bool) {
            return None
          }
          let extras = match
            self.lower_mir_atomic_extra_args(args, extra_start, ctx) {
            Some(values) => values
            None => return None
          }
          match
            (
              self.lower_mir_call_arg(args[0], ctx),
              self.lower_mir_expr_for_target_type(elem_ty, args[1], ctx),
            ) {
            (Some(ptr), Some(value)) =>
              Some(MirAtomicExchange(ptr, value, extras, ty))
            _ => None
          }
        }
        Some(_) => None
        None =>
          match @ctype.builtin_atomic_compare_exchange_call_info(name) {
            Some(
              (
                "sync_compare_exchange_bool"
                | "sync_compare_exchange_value",
                _,
                _,
              )
            ) =>
              self.lower_mir_sync_compare_exchange_builtin(name, args, ty, ctx)
            Some(("compare_exchange_ptr", min_arg_count, extra_start)) => {
              if args.length() < min_arg_count || !(self.core_type(ty) is Bool) {
                return None
              }
              let elem_ty = self.expr_type(args[0], ctx.scope()).atomic_target()
              if !elem_ty.is_integer() {
                return None
              }
              let extras = match
                self.lower_mir_atomic_extra_args(args, extra_start, ctx) {
                Some(values) => values
                None => return None
              }
              match
                (
                  self.lower_mir_call_arg(args[0], ctx),
                  self.lower_mir_call_arg(args[1], ctx),
                  self.lower_mir_call_arg(args[2], ctx),
                ) {
                (Some(ptr), Some(expected), Some(desired_ptr)) =>
                  Some(
                    MirAtomicCompareExchange(
                      ptr,
                      expected,
                      MirLoad(desired_ptr, elem_ty),
                      extras,
                    ),
                  )
                _ => None
              }
            }
            Some(("compare_exchange_value", min_arg_count, extra_start)) => {
              if args.length() < min_arg_count || !(self.core_type(ty) is Bool) {
                return None
              }
              let elem_ty = self.expr_type(args[0], ctx.scope()).atomic_target()
              if !elem_ty.is_integer() {
                return None
              }
              let extras = match
                self.lower_mir_atomic_extra_args(args, extra_start, ctx) {
                Some(values) => values
                None => return None
              }
              match
                (
                  self.lower_mir_call_arg(args[0], ctx),
                  self.lower_mir_call_arg(args[1], ctx),
                  self.lower_mir_expr_for_target_type(elem_ty, args[2], ctx),
                ) {
                (Some(ptr), Some(expected), Some(desired)) =>
                  Some(MirAtomicCompareExchange(ptr, expected, desired, extras))
                _ => None
              }
            }
            Some(_) => None
            _ => None
          }
      }
  }
}

///|
fn Program::lower_mir_scalar_lvalue_addr(
  self : Program,
  expr : @parser.Expr,
  lhs_ty : @ctype.Type,
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
    Deref(ptr) =>
      match self.lower_mir_known_object_ptr_expr(ptr, ctx) {
        Some(addr) => Some(addr)
        None => self.lower_mir_expr_with_array_decay(ptr, ctx)
      }
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
  lhs_ty : @ctype.Type,
  result_ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let pointer_update = mir_body_pointer_type(lhs_ty) &&
    (op == "+" || op == "-") &&
    value.ty().is_integer()
  if !lhs_ty.is_integer() &&
    !(lhs_ty.is_floating() && mir_body_floating_update_op(op)) &&
    !pointer_update {
    return None
  }
  match self.lower_mir_scalar_lvalue_addr(lhs, lhs_ty, ctx) {
    Some(addr) =>
      if mir_body_memory_update_op(op) ||
        (lhs_ty.is_floating() && mir_body_floating_update_op(op)) {
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
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  match self.lower_mir_bitfield_compound_update(expr, op, Number(1L), ty, ctx) {
    Some(value) => return Some(value)
    None => ()
  }
  match lower_mir_cancelled_local_lvalue(expr, ctx) {
    Some(binding) => lower_mir_local_step(binding.name, op, ty, ctx)
    None => {
      let lhs_ty = self.expr_type(expr, ctx.scope())
      if !lhs_ty.is_integer() &&
        !lhs_ty.is_floating() &&
        !mir_body_pointer_type(lhs_ty) {
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
fn Program::lower_mir_array_compound_literal_addr(
  self : Program,
  lit_ty : @ctype.Type,
  items : Array[@parser.Expr],
  id : Int,
  ctx : BodyLowerContext,
) -> MirValue? {
  let completed_ty = mir_file_scope_compound_literal_type(lit_ty, items)
  match self.core_type(completed_ty) {
    Array(_, _) => ()
    _ => return None
  }
  let temp = ctx.declare_temp(completed_ty)
  let stores = match
    self.lower_mir_array_init_stores(
      MirAddrLocal(temp),
      completed_ty,
      CompoundLiteral(completed_ty, items, id),
      ctx,
    ) {
    Some(stores) => stores
    None => return None
  }
  mir_body_sequence_exprs(stores, MirAddrLocal(temp), Pointer(completed_ty))
}

///|
fn Program::lower_mir_array_base_addr(
  self : Program,
  base : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirValue? {
  match self.lower_mir_known_object_ptr_expr(base, ctx) {
    Some(value) => return Some(value)
    None => ()
  }
  if mir_body_array_local_type(self.expr_type(base, ctx.scope())) {
    match self.lower_mir_object_addr(base, ctx) {
      Some(addr) => return Some(addr)
      None => ()
    }
  }
  match base {
    CompoundLiteral(lit_ty, items, id) =>
      self.lower_mir_array_compound_literal_addr(lit_ty, items, id, ctx)
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
  let ty = self.expr_type(arg, ctx.scope())
  match self.core_type(ty) {
    Struct(_) | Union(_) =>
      match self.lower_mir_object_addr(arg, ctx) {
        Some(addr) => Some(MirAggregateArg(addr, ty))
        None => {
          match arg {
            Number(_) | Array(_) | CompoundLiteral(_, _, _) => {
              let temp = ctx.declare_temp(ty)
              let stores = match
                self.lower_mir_struct_init_stores(
                  MirAddrLocal(temp),
                  ty,
                  arg,
                  ctx,
                ) {
                Some(stores) => stores
                None => return None
              }
              match
                mir_body_sequence_exprs(stores, MirAddrLocal(temp), Pointer(ty)) {
                Some(addr) => return Some(MirAggregateArg(addr, ty))
                None => return None
              }
            }
            Ternary(cond, then_expr, else_expr) => {
              if !mir_body_side_effect_free_expr(then_expr) ||
                !mir_body_side_effect_free_expr(else_expr) {
                return None
              }
              if self.core_type(self.expr_type(then_expr, ctx.scope())) !=
                self.core_type(ty) ||
                self.core_type(self.expr_type(else_expr, ctx.scope())) !=
                self.core_type(ty) {
                return None
              }
              let cond_value = match self.lower_mir_expr(cond, ctx) {
                Some(value) => value
                None => return None
              }
              let then_addr = match self.lower_mir_object_addr(then_expr, ctx) {
                Some(addr) => addr
                None => return None
              }
              let else_addr = match self.lower_mir_object_addr(else_expr, ctx) {
                Some(addr) => addr
                None => return None
              }
              let addr = MirTernary(
                cond_value,
                then_addr,
                else_addr,
                Pointer(ty),
              )
              return Some(MirAggregateArg(addr, ty))
            }
            _ => ()
          }
          match self.lower_mir_expr_for_target_type(ty, arg, ctx) {
            Some(value) =>
              if mir_body_aggregate_call_value(value) &&
                self.core_type(value.ty()) == self.core_type(ty) {
                Some(value)
              } else {
                None
              }
            None => None
          }
        }
      }
    _ =>
      match self.core_type(ty) {
        Pointer(_) | FuncPtr(_, _, _) =>
          self.lower_mir_expr_with_array_decay(arg, ctx)
        _ =>
          if mir_body_array_local_type(ty) {
            self.lower_mir_array_base_addr(arg, ctx)
          } else {
            self.lower_mir_expr(arg, ctx)
          }
      }
  }
}

///|
fn Program::lower_mir_expr_with_array_decay(
  self : Program,
  expr : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirValue? {
  match self.lower_mir_known_object_ptr_expr(expr, ctx) {
    Some(value) => return Some(value)
    None => ()
  }
  match self.core_type(self.expr_type(expr, ctx.scope())) {
    Array(elem_ty, _) =>
      match self.lower_mir_array_base_addr(expr, ctx) {
        Some(addr) => Some(MirCast(Pointer(elem_ty), addr))
        None => None
      }
    _ => self.lower_mir_expr(expr, ctx)
  }
}

///|
fn Program::lower_mir_expr_for_target_type(
  self : Program,
  expected_ty : @ctype.Type,
  expr : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirValue? {
  match self.core_type(expected_ty) {
    Pointer(_) => self.lower_mir_expr_with_array_decay(expr, ctx)
    _ => self.lower_mir_expr(expr, ctx)
  }
}

///|
fn Program::lower_mir_array_elem_addr(
  self : Program,
  base : @parser.Expr,
  index : @parser.Expr,
  elem_ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  match
    (self.lower_mir_array_base_addr(base, ctx), self.lower_mir_expr(index, ctx)) {
    (Some(base_addr), Some(index_value)) =>
      if mir_body_array_element_addressable_type(elem_ty) {
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
fn mir_body_bitfield_mask(width : Int) -> Int64 {
  if width >= 64 {
    -1L
  } else {
    (1L << width) - 1L
  }
}

///|
fn mir_body_signed_bitfield_type(ty : @ctype.Type) -> Bool {
  match ty {
    SChar | SShort | SInt | SLong | SLongLong | SInt128 => true
    Aligned(inner, _) => mir_body_signed_bitfield_type(inner)
    _ => false
  }
}

///|
fn mir_body_bitfield_access_type(layout : FieldLayout) -> @ctype.Type {
  match layout.ty {
    Bool | Aligned(Bool, _) => UChar
    _ => layout.ty
  }
}

///|
fn mir_body_bitfield_promoted_type(layout : FieldLayout) -> @ctype.Type {
  let width = match layout.bit_width {
    Some(value) => value
    None => return layout.ty.integer_promote()
  }
  let int_width = @ctype.Type::SInt.const_int_width().unwrap_or(32)
  let ty = layout.ty.without_alignment()
  if ty.is_integer() && width <= int_width {
    SInt
  } else {
    layout.ty.integer_promote()
  }
}

///|
fn Program::lower_mir_bitfield_storage(
  self : Program,
  obj : @parser.Expr,
  field : String,
  ctx : BodyLowerContext,
) -> (MirValue, FieldLayout)? {
  let obj_ty = self.expr_type(obj, ctx.scope())
  match self.field_layout(obj_ty, field) {
    Some(layout) =>
      match layout.bit_width {
        Some(_) =>
          match self.lower_mir_object_addr(obj, ctx) {
            Some(base) => {
              let access_ty = mir_body_bitfield_access_type(layout)
              Some(
                (
                  mir_body_offset_addr_value(base, layout.offset, access_ty),
                  layout,
                ),
              )
            }
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
fn Program::lower_mir_bitfield_load(
  self : Program,
  obj : @parser.Expr,
  field : String,
  result_ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let (addr, layout) = match self.lower_mir_bitfield_storage(obj, field, ctx) {
    Some(value) => value
    None => return None
  }
  let width = match layout.bit_width {
    Some(value) => value
    None => return None
  }
  let access_ty = mir_body_bitfield_access_type(layout)
  let storage = MirLoad(addr, access_ty)
  let shifted = if layout.bit_offset == 0 {
    storage
  } else {
    MirBinary(
      ">>",
      storage,
      MirConst(layout.bit_offset.to_int64(), SInt),
      access_ty,
    )
  }
  let masked = MirBinary(
    "&",
    shifted,
    MirConst(mir_body_bitfield_mask(width), access_ty),
    access_ty,
  )
  let value = if width > 0 &&
    width < 64 &&
    mir_body_signed_bitfield_type(self.core_type(layout.ty)) {
    let sign = MirConst(1L << (width - 1), access_ty)
    MirBinary("-", MirBinary("^", masked, sign, access_ty), sign, access_ty)
  } else {
    masked
  }
  Some(MirCast(result_ty, value))
}

///|
fn Program::lower_mir_bitfield_store(
  self : Program,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
  lhs_ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let (obj, field) = match lhs {
    MemberAccess(obj, field) => (obj, field)
    _ => return None
  }
  let (addr, layout) = match self.lower_mir_bitfield_storage(obj, field, ctx) {
    Some(value) => value
    None => return None
  }
  let value = match self.lower_mir_expr_for_target_type(layout.ty, rhs, ctx) {
    Some(value) => value
    None => return None
  }
  lower_mir_bitfield_store_value(lhs_ty, addr, layout, value, ctx)
}

///|
fn lower_mir_bitfield_store_value(
  lhs_ty : @ctype.Type,
  addr : MirValue,
  layout : FieldLayout,
  value : MirValue,
  ctx : BodyLowerContext,
) -> MirValue? {
  let access_ty = mir_body_bitfield_access_type(layout)
  let temp = ctx.declare_temp(access_ty)
  let width = match layout.bit_width {
    Some(value) => value
    None => return None
  }
  let mask = mir_body_bitfield_mask(width)
  let shifted_mask = mask << layout.bit_offset
  let temp_value = MirLocal(temp)
  let masked_value = MirBinary(
    "&",
    temp_value,
    MirConst(mask, access_ty),
    access_ty,
  )
  let shifted_value = if layout.bit_offset == 0 {
    masked_value
  } else {
    MirBinary(
      "<<",
      masked_value,
      MirConst(layout.bit_offset.to_int64(), SInt),
      access_ty,
    )
  }
  let cleared = MirBinary(
    "&",
    MirLoad(addr, access_ty),
    MirConst(shifted_mask.lnot(), access_ty),
    access_ty,
  )
  let stored = MirBinary("|", cleared, shifted_value, access_ty)
  mir_body_sequence_exprs(
    [
      MirExprStmt(MirAssignLocal(temp, MirCast(access_ty, value))),
      MirExprStmt(MirStore(addr, stored, access_ty)),
    ],
    MirCast(lhs_ty, temp_value),
    lhs_ty,
  )
}

///|
fn Program::lower_mir_bitfield_compound_update(
  self : Program,
  lhs : @parser.Expr,
  op : String,
  rhs : @parser.Expr,
  _result_ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let (obj, field) = match lhs {
    MemberAccess(obj, field) => (obj, field)
    _ => return None
  }
  let lhs_ty = self.expr_type(lhs, ctx.scope())
  let (addr, layout) = match self.lower_mir_bitfield_storage(obj, field, ctx) {
    Some(value) => value
    None => return None
  }
  let current = match self.lower_mir_bitfield_load(obj, field, lhs_ty, ctx) {
    Some(value) => value
    None => return None
  }
  let rhs_value = match self.lower_mir_expr(rhs, ctx) {
    Some(value) => value
    None => return None
  }
  let promoted_lhs_ty = mir_body_bitfield_promoted_type(layout)
  let op_ty = @ctype.binary_result_type(
    op,
    promoted_lhs_ty,
    rhs_value.ty(),
    self.target is DarwinArm64,
  )
  lower_mir_bitfield_store_value(
    lhs_ty,
    addr,
    layout,
    MirBinary(op, MirCast(promoted_lhs_ty, current), rhs_value, op_ty),
    ctx,
  )
}

///|
fn Program::lower_mir_bitfield_post_step(
  self : Program,
  lhs : @parser.Expr,
  op : String,
  result_ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let (obj, field) = match lhs {
    MemberAccess(obj, field) => (obj, field)
    _ => return None
  }
  let lhs_ty = self.expr_type(lhs, ctx.scope())
  let (addr, layout) = match self.lower_mir_bitfield_storage(obj, field, ctx) {
    Some(value) => value
    None => return None
  }
  let current = match self.lower_mir_bitfield_load(obj, field, lhs_ty, ctx) {
    Some(value) => value
    None => return None
  }
  let temp = ctx.declare_temp(lhs_ty)
  let updated = MirBinary(op, MirLocal(temp), MirConst(1L, SInt), result_ty)
  let stored = match
    lower_mir_bitfield_store_value(lhs_ty, addr, layout, updated, ctx) {
    Some(value) => value
    None => return None
  }
  mir_body_sequence_exprs(
    [MirExprStmt(MirAssignLocal(temp, current)), MirExprStmt(stored)],
    MirLocal(temp),
    result_ty,
  )
}

///|
fn mir_body_offset_addr_value(
  base : MirValue,
  offset : Int,
  ty : @ctype.Type,
) -> MirValue {
  match base {
    MirOffsetAddr(inner, base_offset, _) =>
      MirOffsetAddr(inner, base_offset + offset, ty)
    MirCast(_, inner) => mir_body_offset_addr_value(inner, offset, ty)
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
    String(value) => Some(MirStringAddr(value))
    AddrOf(CompoundLiteral(lit_ty, items, id)) =>
      self.lower_mir_expr(AddrOf(CompoundLiteral(lit_ty, items, id)), ctx)
    AddrOf(inner) => self.lower_mir_object_addr(inner, ctx)
    Cast(cast_ty, inner) =>
      match self.core_type(cast_ty) {
        Pointer(_) | FuncPtr(_, _, _) =>
          match self.lower_mir_known_object_ptr_expr(inner, ctx) {
            Some(value) => Some(MirCast(cast_ty, value))
            None =>
              match self.lower_mir_expr_with_array_decay(inner, ctx) {
                Some(value) => Some(MirCast(cast_ty, value))
                None => None
              }
          }
        _ => self.lower_mir_known_object_ptr_expr(inner, ctx)
      }
    Binary(op, lhs, rhs) => {
      if op == "," {
        match
          (
            self.lower_mir_ignored_expr(lhs, ctx),
            self.lower_mir_expr_with_array_decay(rhs, ctx),
          ) {
          (Some(left), Some(right)) =>
            return Some(MirBinary(",", left, right, right.ty()))
          _ => return None
        }
      }
      let scope = ctx.scope()
      let lhs_ty = self.expr_type(lhs, scope)
      let rhs_ty = self.expr_type(rhs, scope)
      let pointer_integer = match self.pointer_element(lhs_ty) {
        Some(_) => (op == "+" || op == "-") && rhs_ty.is_integer()
        None =>
          op == "+" &&
          lhs_ty.is_integer() &&
          self.pointer_element(rhs_ty) is Some(_)
      }
      if !pointer_integer {
        return None
      }
      match
        (
          self.lower_mir_expr_with_array_decay(lhs, ctx),
          self.lower_mir_expr_with_array_decay(rhs, ctx),
        ) {
        (Some(left), Some(right)) =>
          Some(MirBinary(op, left, right, self.expr_type(expr, scope)))
        _ => None
      }
    }
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
    Deref(ptr) =>
      match self.lower_mir_known_object_ptr_expr(ptr, ctx) {
        Some(addr) => Some(addr)
        None => self.lower_mir_expr_with_array_decay(ptr, ctx)
      }
    Cast(cast_ty, inner) => {
      let inner_ty = self.expr_type(inner, ctx.scope())
      match (self.core_type(cast_ty), self.core_type(inner_ty)) {
        (Struct(_), Struct(_)) | (Union(_), Union(_)) =>
          if self.core_type(cast_ty) == self.core_type(inner_ty) {
            return self.lower_mir_object_addr(inner, ctx)
          }
        _ => ()
      }
      None
    }
    ArrayAccess(base, index) => {
      let elem_ty = self.expr_type(expr, ctx.scope())
      match
        (
          self.lower_mir_array_base_addr(base, ctx),
          self.lower_mir_expr(index, ctx),
        ) {
        (Some(base_addr), Some(index_value)) =>
          if mir_body_array_element_addressable_type(elem_ty) {
            Some(MirElemAddr(base_addr, index_value, elem_ty))
          } else {
            None
          }
        _ => None
      }
    }
    _ => {
      let ty = self.expr_type(expr, ctx.scope())
      match self.core_type(ty) {
        Struct(_) | Union(_) =>
          self.lower_mir_aggregate_rvalue_addr(expr, ty, ctx)
        _ => None
      }
    }
  }
}

///|
fn Program::lower_mir_aggregate_rvalue_addr(
  self : Program,
  expr : @parser.Expr,
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  match expr {
    Assign(lhs, rhs) => {
      let lhs_ty = self.expr_type(lhs, ctx.scope())
      if self.core_type(lhs_ty) != self.core_type(ty) {
        return None
      }
      match self.lower_mir_aggregate_assign_parts(lhs, rhs, ctx) {
        Some((stores, dest_addr, _)) =>
          return mir_body_sequence_exprs(stores, dest_addr, Pointer(lhs_ty))
        None => return None
      }
    }
    VaArg(ap, va_ty) => {
      if self.core_type(va_ty) != self.core_type(ty) {
        return None
      }
      match self.core_type(va_ty) {
        Struct(_) | Union(_) => ()
        _ => return None
      }
      match self.lower_mir_expr(ap, ctx) {
        Some(ap_value) => return Some(MirVaArgAddr(ap_value, va_ty))
        None => return None
      }
    }
    Ternary(cond, then_expr, else_expr) =>
      match
        self.lower_mir_aggregate_ternary_addr(
          cond, then_expr, else_expr, ty, ctx,
        ) {
        Some(addr) => return Some(addr)
        None => return None
      }
    _ => ()
  }
  let value = match self.lower_mir_expr_for_target_type(ty, expr, ctx) {
    Some(value) => value
    None => return None
  }
  if !mir_body_aggregate_call_value(value) ||
    self.core_type(value.ty()) != self.core_type(ty) {
    return None
  }
  let temp = ctx.declare_temp(ty)
  mir_body_sequence_exprs(
    [MirExprStmt(MirStore(MirAddrLocal(temp), value, ty))],
    MirAddrLocal(temp),
    Pointer(ty),
  )
}

///|
fn Program::lower_mir_aggregate_ternary_addr(
  self : Program,
  cond : @parser.Expr,
  then_expr : @parser.Expr,
  else_expr : @parser.Expr,
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  if self.core_type(self.expr_type(then_expr, ctx.scope())) !=
    self.core_type(ty) ||
    self.core_type(self.expr_type(else_expr, ctx.scope())) != self.core_type(ty) {
    return None
  }
  if mir_body_side_effect_free_expr(then_expr) &&
    mir_body_side_effect_free_expr(else_expr) {
    match
      (
        self.lower_mir_expr(cond, ctx),
        self.lower_mir_object_addr(then_expr, ctx),
        self.lower_mir_object_addr(else_expr, ctx),
      ) {
      (Some(cond_value), Some(then_addr), Some(else_addr)) =>
        return Some(MirTernary(cond_value, then_addr, else_addr, Pointer(ty)))
      _ => ()
    }
  }
  let temp = ctx.declare_temp(ty)
  let cond_value = match self.lower_mir_expr(cond, ctx) {
    Some(value) => value
    None => return None
  }
  let then_stores = match
    self.lower_mir_aggregate_branch_copy_stores(
      MirAddrLocal(temp),
      ty,
      then_expr,
      ctx,
    ) {
    Some(stores) => stores
    None => return None
  }
  let else_stores = match
    self.lower_mir_aggregate_branch_copy_stores(
      MirAddrLocal(temp),
      ty,
      else_expr,
      ctx,
    ) {
    Some(stores) => stores
    None => return None
  }
  let then_effect = match
    mir_body_sequence_exprs(then_stores, MirConst(0L, SInt), SInt) {
    Some(value) => value
    None => return None
  }
  let else_effect = match
    mir_body_sequence_exprs(else_stores, MirConst(0L, SInt), SInt) {
    Some(value) => value
    None => return None
  }
  mir_body_sequence_exprs(
    [MirExprStmt(MirTernary(cond_value, then_effect, else_effect, SInt))],
    MirAddrLocal(temp),
    Pointer(ty),
  )
}

///|
fn Program::lower_mir_indirect_call(
  self : Program,
  callee : @parser.Expr,
  args : Array[@parser.Expr],
  ty : @ctype.Type,
  ctx : BodyLowerContext,
) -> MirValue? {
  let normalized_callee = match callee {
    Deref(inner) =>
      match self.core_type(self.expr_type(inner, ctx.scope())) {
        FuncPtr(_, _, _) | Pointer(FuncPtr(_, _, _)) => inner
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
    Pointer(FuncPtr(_, _, _)) => ()
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
fn mir_stmts_have_supported_switch_label(
  stmts : Array[MirStmt],
  name : String,
) -> Bool {
  for stmt in stmts {
    match stmt {
      MirLabel(label) if label == name => return true
      MirIf(_, then_, else_) =>
        if mir_stmts_have_supported_switch_label(then_, name) ||
          mir_stmts_have_supported_switch_label(else_, name) {
          return true
        }
      MirBlock(nested) =>
        if mir_stmts_have_supported_switch_label(nested, name) {
          return true
        }
      MirWhile(_, nested) | MirDoWhile(_, nested) =>
        if mir_stmts_have_supported_switch_label(nested, name) {
          return true
        }
      MirFor(init, _, _, nested) =>
        if mir_stmts_have_supported_switch_label(init, name) ||
          mir_stmts_have_supported_switch_label(nested, name) {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn mir_switch_cases_are_supported(
  cases : Array[(Int64?, String)],
  body : Array[MirStmt],
) -> Bool {
  for c in cases {
    if !mir_stmts_have_supported_switch_label(body, c.1) {
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
    FloatLiteral(value) => Some(MirConst(value.reinterpret_as_int64(), ty))
    String(value) => Some(MirStringAddr(value))
    LabelAddr(name) => Some(MirLabelAddr(name))
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
        Array(_, _) =>
          self.lower_mir_array_compound_literal_addr(lit_ty, items, id, ctx)
        _ => None
      }
    }
    AddrOf(Var(name)) =>
      match ctx.lookup_local(name) {
        Some(binding) => Some(MirAddrLocal(binding))
        None =>
          if self.globals.contains(name) {
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
        None =>
          if self.globals.contains(name) && mir_body_scalar_type(ty) {
            Some(MirLoad(MirAddrGlobal(name, self.globals[name].ty), ty))
          } else {
            None
          }
      }
    AddrOf(Deref(inner)) => self.lower_mir_expr(inner, ctx)
    AddrOf(ArrayAccess(base, index)) =>
      self.lower_mir_object_addr(ArrayAccess(base, index), ctx)
    AddrOf(MemberAccess(obj, field)) =>
      self.lower_mir_object_addr(MemberAccess(obj, field), ctx)
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
        None =>
          match self.pointer_element(self.expr_type(ptr, scope)) {
            Some(_) =>
              match self.lower_mir_expr_with_array_decay(ptr, ctx) {
                Some(addr) =>
                  if mir_body_scalar_type(ty) {
                    Some(MirLoad(addr, ty))
                  } else {
                    None
                  }
                None => None
              }
            None => None
          }
      }
    ArrayAccess(base, index) =>
      match self.lower_mir_array_elem_addr(base, index, ty, ctx) {
        Some(addr) => Some(MirLoad(addr, ty))
        None => None
      }
    MemberAccess(obj, field) =>
      match self.lower_mir_bitfield_load(obj, field, ty, ctx) {
        Some(value) => Some(value)
        None =>
          match self.lower_mir_member_addr(obj, field, ctx) {
            Some(addr) => Some(MirLoad(addr, ty))
            None => None
          }
      }
    Binary(op, lhs, rhs) => {
      let lhs_ty = self.expr_type(lhs, scope)
      let rhs_ty = self.expr_type(rhs, scope)
      let pointer_arith = match
        (self.pointer_element(lhs_ty), self.pointer_element(rhs_ty)) {
        (Some(_), Some(_)) => op == "-"
        (Some(_), None) => (op == "+" || op == "-") && rhs_ty.is_integer()
        (None, Some(_)) => op == "+" && lhs_ty.is_integer()
        _ => false
      }
      let pointer_compare = (
          op == "==" ||
          op == "!=" ||
          op == "<" ||
          op == "<=" ||
          op == ">" ||
          op == ">="
        ) &&
        (
          self.pointer_element(lhs_ty) is Some(_) ||
          self.pointer_element(rhs_ty) is Some(_)
        )
      let pointer_op = pointer_arith || pointer_compare
      let left_value = if pointer_op {
        self.lower_mir_expr_with_array_decay(lhs, ctx)
      } else {
        self.lower_mir_expr(lhs, ctx)
      }
      let right_value = if pointer_op {
        self.lower_mir_expr_with_array_decay(rhs, ctx)
      } else {
        self.lower_mir_expr(rhs, ctx)
      }
      match (left_value, right_value) {
        (Some(left), Some(right)) => Some(MirBinary(op, left, right, ty))
        _ => None
      }
    }
    Unary(op, inner) =>
      match self.lower_mir_expr(inner, ctx) {
        Some(value) => Some(MirUnary(op, value, ty))
        None => None
      }
    Cast(cast_ty, inner) => {
      let inner_ty = self.expr_type(inner, scope)
      match (self.core_type(cast_ty), self.core_type(inner_ty)) {
        (Struct(_), Struct(_)) | (Union(_), Union(_)) =>
          if self.core_type(cast_ty) == self.core_type(inner_ty) {
            return self.lower_mir_expr(inner, ctx)
          }
        _ => ()
      }
      if self.is_floating_const_type(self.expr_type(inner, scope)) {
        match self.fold_const(expr, scope) {
          Some(value) => return Some(MirConst(value, ty))
          None => ()
        }
      }
      let inner_value = match self.core_type(inner_ty) {
        Array(_, _) => self.lower_mir_expr_with_array_decay(inner, ctx)
        _ => self.lower_mir_expr(inner, ctx)
      }
      match inner_value {
        Some(value) => Some(MirCast(cast_ty, value))
        None => None
      }
    }
    Assign(lhs, rhs) => {
      let lhs_ty = self.expr_type(lhs, scope)
      match self.lower_mir_bitfield_store(lhs, rhs, lhs_ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match
        (
          lower_mir_cancelled_local_lvalue(lhs, ctx),
          self.lower_mir_expr_for_target_type(lhs_ty, rhs, ctx),
        ) {
        (Some(binding), Some(value)) =>
          if mir_body_scalar_type(binding.ty) {
            return Some(MirAssignLocal(binding, value))
          }
        _ => ()
      }
      match self.lower_mir_expr_for_target_type(lhs_ty, rhs, ctx) {
        Some(value) =>
          match self.lower_mir_scalar_lvalue_addr(lhs, lhs_ty, ctx) {
            Some(addr) => Some(MirStore(addr, value, lhs_ty))
            None => None
          }
        _ => None
      }
    }
    CompoundAssign(op, lhs, rhs) => {
      match self.lower_mir_bitfield_compound_update(lhs, op, rhs, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
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
          self.lower_mir_expr_for_target_type(ty, then_, ctx),
          self.lower_mir_expr_for_target_type(ty, else_, ctx),
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
      match self.lower_mir_identity_call_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_noop_call_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match @ctype.builtin_length_libcall_info(name, args.length()) {
        Some(("strlen", _)) =>
          match mir_body_literal_string_arg(args[0]) {
            Some(value) =>
              return Some(
                MirConst(@ctype.string_literal_c_length(value).to_int64(), ty),
              )
            None => ()
          }
        _ => ()
      }
      match self.lower_mir_alloca_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_heap_libcall_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_address_query_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_fence_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_trap_builtin(name, args, ty) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_floating_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_integer_unary_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_object_size_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_constant_query_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_atomic_lock_free_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.fold_const(expr, scope) {
        Some(value) => return Some(MirConst(value, ty))
        None => ()
      }
      match self.lower_mir_rotate_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_overflow_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_va_setup_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_bzero_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_darwin_fd_helper_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_strlen_libcall_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_memory_libcall_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_compare_libcall_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_search_libcall_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_span_libcall_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_strl_libcall_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_checked_printf_libcall_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_atomic_load_store_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_atomic_rmw_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_fp_math_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_fp_class_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_fp_compare_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      match self.lower_mir_alignment_builtin(name, args, ty, ctx) {
        Some(value) => return Some(value)
        None => ()
      }
      if mir_body_source_builtin_call_name(name) {
        return None
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
    VaArg(ap, va_ty) => {
      if self.core_type(va_ty) is Void || !mir_body_scalar_type(va_ty) {
        return None
      }
      match self.lower_mir_expr(ap, ctx) {
        Some(ap_value) => Some(MirVaArg(ap_value, va_ty))
        None => None
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
fn Program::lower_mir_aggregate_assign_parts(
  self : Program,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
  ctx : BodyLowerContext,
) -> (Array[MirStmt], MirValue, @ctype.Type)? {
  let lhs_ty = self.expr_type(lhs, ctx.scope())
  match self.core_type(lhs_ty) {
    Struct(_) | Union(_) => ()
    _ => return None
  }
  let dest_raw_addr = match self.lower_mir_object_addr(lhs, ctx) {
    Some(addr) => addr
    None => return None
  }
  if !mir_body_copy_dest_addr(dest_raw_addr) {
    return None
  }
  let (dest_prefix, dest_addr) = lower_mir_stable_copy_addr(dest_raw_addr, ctx)
  match self.lower_mir_va_arg_copy_init_stores(dest_addr, lhs_ty, rhs, ctx) {
    Some(stores) =>
      return Some((prepend_mir_stmts(dest_prefix, stores), dest_addr, lhs_ty))
    None => ()
  }
  match rhs {
    Ternary(cond, then_expr, else_expr) => {
      if self.core_type(self.expr_type(then_expr, ctx.scope())) !=
        self.core_type(lhs_ty) ||
        self.core_type(self.expr_type(else_expr, ctx.scope())) !=
        self.core_type(lhs_ty) {
        return None
      }
      let src_raw_addr = match
        self.lower_mir_aggregate_ternary_addr(
          cond, then_expr, else_expr, lhs_ty, ctx,
        ) {
        Some(addr) => addr
        None => return None
      }
      let (src_prefix, src_addr) = lower_mir_stable_copy_addr(src_raw_addr, ctx)
      let stores = prepend_mir_stmts(dest_prefix, src_prefix)
      let copy_stores = match
        self.lower_mir_copy_init_stores(dest_addr, lhs_ty, src_addr, lhs_ty) {
        Some(stores) => stores
        None => return None
      }
      for store in copy_stores {
        stores.push(store)
      }
      return Some((stores, dest_addr, lhs_ty))
    }
    _ => ()
  }
  match self.lower_mir_expr_for_target_type(lhs_ty, rhs, ctx) {
    Some(value) =>
      if mir_body_aggregate_call_value(value) &&
        self.core_type(value.ty()) == self.core_type(lhs_ty) {
        return Some(
          (
            prepend_mir_stmts(dest_prefix, [
              MirExprStmt(MirStore(dest_addr, value, lhs_ty)),
            ]),
            dest_addr,
            lhs_ty,
          ),
        )
      }
    None => ()
  }
  match rhs {
    CompoundLiteral(_, _, _) => {
      let rhs_ty = self.expr_type(rhs, ctx.scope())
      if self.core_type(rhs_ty) != self.core_type(lhs_ty) {
        return None
      }
      let temp = ctx.declare_temp(lhs_ty)
      let init_stores = match
        self.lower_mir_struct_init_stores(MirAddrLocal(temp), lhs_ty, rhs, ctx) {
        Some(stores) => stores
        None => return None
      }
      let stores = prepend_mir_stmts(dest_prefix, init_stores)
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
      return Some((stores, dest_addr, lhs_ty))
    }
    _ => ()
  }
  let src_addr = match self.lower_mir_object_addr(rhs, ctx) {
    Some(addr) => addr
    None => return None
  }
  if !mir_body_copy_source_addr(src_addr) {
    return None
  }
  let (src_prefix, src_addr) = lower_mir_stable_copy_addr(src_addr, ctx)
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
  Some(
    (
      prepend_mir_stmts(prepend_mir_stmts(dest_prefix, src_prefix), stores),
      dest_addr,
      lhs_ty,
    ),
  )
}

///|
fn Program::lower_mir_ignored_aggregate_assign(
  self : Program,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirValue? {
  match self.lower_mir_aggregate_assign_parts(lhs, rhs, ctx) {
    Some((stores, _, _)) =>
      mir_body_sequence_exprs(stores, MirConst(0L, SInt), SInt)
    None => None
  }
}

///|
fn Program::lower_mir_ignored_expr(
  self : Program,
  expr : @parser.Expr,
  ctx : BodyLowerContext,
) -> MirValue? {
  match expr {
    Cast(ty, inner) =>
      if self.core_type(ty) is Void &&
        !mir_body_scalar_type(self.expr_type(inner, ctx.scope())) &&
        mir_body_side_effect_free_expr(inner) {
        Some(MirConst(0L, SInt))
      } else {
        self.lower_mir_expr(expr, ctx)
      }
    Assign(lhs, rhs) =>
      match self.lower_mir_ignored_aggregate_assign(lhs, rhs, ctx) {
        Some(value) => Some(value)
        None => self.lower_mir_expr(expr, ctx)
      }
    Binary(",", lhs, rhs) =>
      match
        (
          self.lower_mir_ignored_expr(lhs, ctx),
          self.lower_mir_ignored_expr(rhs, ctx),
        ) {
        (Some(left), Some(right)) => Some(MirBinary(",", left, right, SInt))
        _ => None
      }
    _ => self.lower_mir_expr(expr, ctx)
  }
}

///|
fn Program::lower_mir_aggregate_return(
  self : Program,
  ret_ty : @ctype.Type,
  expr : @parser.Expr,
  ctx : BodyLowerContext,
) -> Array[MirStmt]? {
  match self.core_type(ret_ty) {
    Struct(_) | Union(_) => ()
    _ => return None
  }
  let temp = ctx.declare_temp(ret_ty)
  let stores = match
    self.lower_mir_struct_init_stores(MirAddrLocal(temp), ret_ty, expr, ctx) {
    Some(stores) => stores
    None => return None
  }
  let stmts : Array[MirStmt] = [MirDeclare(temp, None)]
  for store in stores {
    stmts.push(store)
  }
  stmts.push(MirReturn(Some(MirLocal(temp))))
  Some(stmts)
}

///|
fn Program::lower_mir_aggregate_branch_copy_stores(
  self : Program,
  dest_addr : MirValue,
  dest_ty : @ctype.Type,
  expr : @parser.Expr,
  ctx : BodyLowerContext,
) -> Array[MirStmt]? {
  match self.lower_mir_object_addr(expr, ctx) {
    Some(src_raw_addr) => {
      if !mir_body_copy_source_addr(src_raw_addr) {
        return None
      }
      let (src_prefix, src_addr) = lower_mir_stable_copy_addr(src_raw_addr, ctx)
      let stores = match
        self.lower_mir_copy_init_stores(
          dest_addr,
          dest_ty,
          src_addr,
          self.expr_type(expr, ctx.scope()),
        ) {
        Some(stores) => stores
        None => return None
      }
      Some(prepend_mir_stmts(src_prefix, stores))
    }
    None =>
      match expr {
        Number(_) | Array(_) | CompoundLiteral(_, _, _) =>
          self.lower_mir_struct_init_stores(dest_addr, dest_ty, expr, ctx)
        _ =>
          match self.lower_mir_expr_for_target_type(dest_ty, expr, ctx) {
            Some(value) =>
              if mir_body_aggregate_call_value(value) &&
                self.core_type(value.ty()) == self.core_type(dest_ty) {
                Some([MirExprStmt(MirStore(dest_addr, value, dest_ty))])
              } else {
                None
              }
            None => None
          }
      }
  }
}

///|
fn Program::lower_mir_aggregate_assign_stmt(
  self : Program,
  lhs : @parser.Expr,
  rhs : @parser.Expr,
  ctx : BodyLowerContext,
) -> Array[MirStmt]? {
  let lhs_ty = self.expr_type(lhs, ctx.scope())
  match self.core_type(lhs_ty) {
    Struct(_) | Union(_) => ()
    _ => return None
  }
  match rhs {
    Ternary(cond, then_expr, else_expr) => {
      if self.core_type(self.expr_type(then_expr, ctx.scope())) !=
        self.core_type(lhs_ty) ||
        self.core_type(self.expr_type(else_expr, ctx.scope())) !=
        self.core_type(lhs_ty) {
        return None
      }
      let dest_raw_addr = match self.lower_mir_object_addr(lhs, ctx) {
        Some(addr) => addr
        None => return None
      }
      if !mir_body_copy_dest_addr(dest_raw_addr) {
        return None
      }
      let (dest_prefix, dest_addr) = lower_mir_stable_copy_addr(
        dest_raw_addr, ctx,
      )
      let cond_value = match self.lower_mir_expr(cond, ctx) {
        Some(value) => value
        None => return None
      }
      let then_stores = match
        self.lower_mir_aggregate_branch_copy_stores(
          dest_addr, lhs_ty, then_expr, ctx,
        ) {
        Some(stores) => stores
        None => return None
      }
      let else_stores = match
        self.lower_mir_aggregate_branch_copy_stores(
          dest_addr, lhs_ty, else_expr, ctx,
        ) {
        Some(stores) => stores
        None => return None
      }
      let cond_temp = ctx.declare_temp(cond_value.ty())
      let stmts = dest_prefix
      stmts.push(MirExprStmt(MirAssignLocal(cond_temp, cond_value)))
      stmts.push(MirIf(MirLocal(cond_temp), then_stores, else_stores))
      Some(stmts)
    }
    _ => None
  }
}

///|
fn Program::lower_mir_stmt(
  self : Program,
  stmt : @parser.Stmt,
  ctx : BodyLowerContext,
) -> Array[MirStmt]? {
  match stmt {
    ExprStmt(Assign(lhs, rhs)) =>
      match self.lower_mir_aggregate_assign_stmt(lhs, rhs, ctx) {
        Some(stmts) => Some(stmts)
        None =>
          match self.lower_mir_ignored_expr(Assign(lhs, rhs), ctx) {
            Some(value) => Some([MirExprStmt(value)])
            None => None
          }
      }
    ExprStmt(expr) =>
      match self.lower_mir_ignored_expr(expr, ctx) {
        Some(value) => Some([MirExprStmt(value)])
        None => None
      }
    Return(expr) =>
      match expr {
        Some(value_expr) =>
          match self.funcs.get(ctx.current_func) {
            Some(sig) => {
              match self.lower_mir_aggregate_return(sig.ret, value_expr, ctx) {
                Some(stmts) => return Some(stmts)
                None => ()
              }
              match
                self.lower_mir_expr_for_target_type(sig.ret, value_expr, ctx) {
                Some(value) => Some([MirReturn(Some(value))])
                None => None
              }
            }
            None =>
              match self.lower_mir_expr(value_expr, ctx) {
                Some(value) => Some([MirReturn(Some(value))])
                None => None
              }
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
          if mir_switch_cases_are_supported(cases, body_values) {
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
    ComputedGoto(expr) =>
      match self.lower_mir_expr_with_array_decay(expr, ctx) {
        Some(target) => Some([MirComputedGoto(target)])
        None => None
      }
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
              None =>
                match self.lower_mir_expr_for_target_type(ty, expr, ctx) {
                  Some(value) =>
                    if mir_body_aggregate_call_value(value) &&
                      self.core_type(value.ty()) == self.core_type(ty) {
                      return Some([MirDeclare(binding, Some(value))])
                    } else {
                      return None
                    }
                  None => return None
                }
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
      let binding = ctx.declare_local(name, ty)
      let init_value = match init {
        Some(expr) =>
          match self.lower_mir_expr_for_target_type(ty, expr, ctx) {
            Some(value) => Some(value)
            None => return None
          }
        None => None
      }
      Some([MirDeclare(binding, init_value)])
    }
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
