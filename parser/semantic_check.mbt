///|
priv struct SemanticContext {
  funcs : Map[String, Type]
  globals : Map[String, Type]
  structs : Map[String, StructDecl]
}

///|
fn semantic_core_type(ty : Type) -> Type {
  match ty {
    Aligned(inner, _) | Atomic(inner) => semantic_core_type(inner)
    _ => ty
  }
}

///|
fn semantic_is_pointer_operand(ty : Type) -> Bool {
  match semantic_core_type(ty) {
    Pointer(_) | Array(_, _) => true
    _ => false
  }
}

///|
fn semantic_is_callable_type(ty : Type) -> Bool {
  match semantic_core_type(ty) {
    FuncPtr(_, _, _) | Pointer(FuncPtr(_, _, _)) => true
    _ => false
  }
}

///|
fn semantic_is_arithmetic_type(ty : Type) -> Bool {
  let core = semantic_core_type(ty)
  core == Bool || core.is_integer() || core.is_floating()
}

///|
fn semantic_is_scalar_type(ty : Type) -> Bool {
  semantic_is_arithmetic_type(ty) ||
  semantic_is_pointer_operand(ty) ||
  semantic_is_callable_type(ty)
}

///|
fn semantic_param_types(params : Array[Param]) -> Array[Type] {
  let types : Array[Type] = []
  for param in params {
    types.push(param.ty)
  }
  types
}

///|
fn semantic_func_type(func : FuncDecl) -> Type {
  FuncPtr(func.ret, semantic_param_types(func.params), func.variadic)
}

///|
fn semantic_lookup_value(
  ctx : SemanticContext,
  locals : Map[String, Type],
  name : String,
) -> Type? {
  if locals.contains(name) {
    Some(locals[name])
  } else if ctx.globals.contains(name) {
    Some(ctx.globals[name])
  } else if ctx.funcs.contains(name) {
    Some(ctx.funcs[name])
  } else {
    None
  }
}

///|
fn semantic_call_result_type(ty : Type) -> Type {
  match semantic_core_type(ty) {
    FuncPtr(ret, _, _) => ret
    Pointer(FuncPtr(ret, _, _)) => ret
    _ => SInt
  }
}

///|
fn semantic_pointer_element_type(ty : Type) -> Type? {
  match semantic_core_type(ty) {
    Pointer(elem) | Array(elem, _) => Some(elem)
    _ => None
  }
}

///|
fn semantic_find_field_type(
  ctx : SemanticContext,
  ty : Type,
  field : String,
) -> Result[Type, String] {
  let aggregate_name = match semantic_core_type(ty) {
    Struct(name) | Union(name) => name
    _ => return Ok(SInt)
  }
  if !ctx.structs.contains(aggregate_name) {
    return Err("incomplete aggregate type: " + aggregate_name)
  }
  for param in ctx.structs[aggregate_name].fields {
    if param.name == field {
      return Ok(param.ty)
    }
  }
  Err("unknown field '" + field + "' in aggregate " + aggregate_name)
}

///|
fn semantic_binary_type(
  op : String,
  lhs_ty : Type,
  rhs_ty : Type,
) -> Result[Type, String] {
  if op == "," {
    return Ok(rhs_ty)
  }
  let lhs_ptr = semantic_is_pointer_operand(lhs_ty)
  let rhs_ptr = semantic_is_pointer_operand(rhs_ty)
  match op {
    "+" => {
      if lhs_ptr && rhs_ptr {
        return Err("invalid operands to binary +: pointer plus pointer")
      }
      if lhs_ptr && !rhs_ty.is_integer() {
        return Err("invalid pointer arithmetic operand")
      }
      if rhs_ptr && !lhs_ty.is_integer() {
        return Err("invalid pointer arithmetic operand")
      }
      if lhs_ptr {
        return Ok(lhs_ty)
      }
      if rhs_ptr {
        return Ok(rhs_ty)
      }
    }
    "-" => {
      if lhs_ptr && rhs_ptr {
        return Ok(SLong)
      }
      if lhs_ptr && !rhs_ty.is_integer() {
        return Err("invalid pointer arithmetic operand")
      }
      if rhs_ptr {
        return Err("invalid operands to binary -: non-pointer minus pointer")
      }
      if lhs_ptr {
        return Ok(lhs_ty)
      }
    }
    "*" | "/" =>
      if !semantic_is_arithmetic_type(lhs_ty) ||
        !semantic_is_arithmetic_type(rhs_ty) {
        return Err("arithmetic operator requires arithmetic operands")
      }
    "%" | "&" | "|" | "^" | "<<" | ">>" =>
      if !lhs_ty.is_integer() || !rhs_ty.is_integer() {
        return Err("integer operator requires integer operands")
      }
    "==" | "!=" | "<" | "<=" | ">" | ">=" | "&&" | "||" => {
      if !semantic_is_scalar_type(lhs_ty) || !semantic_is_scalar_type(rhs_ty) {
        return Err("comparison or logical operator requires scalar operands")
      }
      return Ok(SInt)
    }
    _ => ()
  }
  if lhs_ty.is_floating() || rhs_ty.is_floating() {
    if semantic_core_type(lhs_ty) == Double ||
      semantic_core_type(rhs_ty) == Double {
      Ok(Double)
    } else {
      Ok(Float)
    }
  } else if lhs_ty.is_integer() && rhs_ty.is_integer() {
    Ok(SInt)
  } else {
    Ok(lhs_ty)
  }
}

///|
fn semantic_expr_type(
  ctx : SemanticContext,
  locals : Map[String, Type],
  expr : Expr,
) -> Result[Type, String] {
  match expr {
    Number(_) => Ok(SInt)
    FloatLiteral(_) => Ok(Double)
    String(_) => Ok(Pointer(SChar))
    Var(name) =>
      match semantic_lookup_value(ctx, locals, name) {
        Some(ty) => Ok(ty)
        None => Ok(SInt)
      }
    Binary(op, lhs, rhs) => {
      let lhs_ty = match semantic_expr_type(ctx, locals, lhs) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      let rhs_ty = match semantic_expr_type(ctx, locals, rhs) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      semantic_binary_type(op, lhs_ty, rhs_ty)
    }
    Unary(op, operand) => {
      let operand_ty = match semantic_expr_type(ctx, locals, operand) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      match op {
        "*" =>
          match semantic_pointer_element_type(operand_ty) {
            Some(elem) => Ok(elem)
            None => Err("cannot dereference non-pointer expression")
          }
        "&" => Ok(Pointer(operand_ty))
        "+" | "-" =>
          if semantic_is_arithmetic_type(operand_ty) {
            Ok(operand_ty)
          } else {
            Err("unary numeric operator requires arithmetic operand")
          }
        "~" =>
          if operand_ty.is_integer() {
            Ok(operand_ty)
          } else {
            Err("bitwise not requires integer operand")
          }
        "!" =>
          if semantic_is_scalar_type(operand_ty) {
            Ok(SInt)
          } else {
            Err("logical not requires scalar operand")
          }
        _ => Ok(operand_ty)
      }
    }
    Call(func, args) => {
      for arg in args {
        match semantic_expr_type(ctx, locals, arg) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      match func {
        Var(name) =>
          match semantic_lookup_value(ctx, locals, name) {
            Some(ty) =>
              if semantic_is_callable_type(ty) {
                Ok(semantic_call_result_type(ty))
              } else {
                Err("called object is not a function: " + name)
              }
            None => Ok(SInt)
          }
        _ => {
          let func_ty = match semantic_expr_type(ctx, locals, func) {
            Ok(ty) => ty
            Err(err) => return Err(err)
          }
          if semantic_is_callable_type(func_ty) {
            Ok(semantic_call_result_type(func_ty))
          } else {
            Err("called expression is not a function")
          }
        }
      }
    }
    Assign(lhs, rhs) => {
      let lhs_ty = match semantic_expr_type(ctx, locals, lhs) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      match semantic_core_type(lhs_ty) {
        Array(_, _) => return Err("array expression is not assignable")
        _ => ()
      }
      match semantic_expr_type(ctx, locals, rhs) {
        Ok(_) => Ok(lhs_ty)
        Err(err) => Err(err)
      }
    }
    CompoundAssign(op, lhs, rhs) => {
      let lhs_ty = match semantic_expr_type(ctx, locals, lhs) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      let rhs_ty = match semantic_expr_type(ctx, locals, rhs) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      semantic_binary_type(op, lhs_ty, rhs_ty)
    }
    MemberAccess(obj, field) => {
      let obj_ty = match semantic_expr_type(ctx, locals, obj) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      semantic_find_field_type(ctx, obj_ty, field)
    }
    Deref(ptr) => {
      let ptr_ty = match semantic_expr_type(ctx, locals, ptr) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      match semantic_pointer_element_type(ptr_ty) {
        Some(elem) => Ok(elem)
        None => Err("cannot dereference non-pointer expression")
      }
    }
    AddrOf(e) =>
      match semantic_expr_type(ctx, locals, e) {
        Ok(ty) => Ok(Pointer(ty))
        Err(err) => Err(err)
      }
    ArrayAccess(arr, index) => {
      let arr_ty = match semantic_expr_type(ctx, locals, arr) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      let index_ty = match semantic_expr_type(ctx, locals, index) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      if !index_ty.is_integer() {
        return Err("array subscript index must be integer")
      }
      match semantic_pointer_element_type(arr_ty) {
        Some(elem) => Ok(elem)
        None => Ok(SInt)
      }
    }
    Sizeof(_) | Alignof(_) | OffsetOf(_, _) => Ok(SInt)
    SizeofExpr(e) | AlignofExpr(e) => {
      let _ = semantic_expr_type(ctx, locals, e)
      Ok(SInt)
    }
    Cast(ty, e) => {
      let _ = semantic_expr_type(ctx, locals, e)
      Ok(ty)
    }
    PrefixInc(e) | PrefixDec(e) | PostfixInc(e) | PostfixDec(e) => {
      let ty = match semantic_expr_type(ctx, locals, e) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      if semantic_is_arithmetic_type(ty) || semantic_is_pointer_operand(ty) {
        Ok(ty)
      } else {
        Err("increment or decrement requires scalar arithmetic or pointer")
      }
    }
    Ternary(cond, then_expr, else_expr) => {
      let cond_ty = match semantic_expr_type(ctx, locals, cond) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      if !semantic_is_scalar_type(cond_ty) {
        return Err("ternary condition must be scalar")
      }
      let then_ty = match semantic_expr_type(ctx, locals, then_expr) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      let else_ty = match semantic_expr_type(ctx, locals, else_expr) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      semantic_binary_type(",", then_ty, else_ty)
    }
    LabelAddr(_) => Ok(Pointer(Void))
    VaArg(ap, ty) => {
      let _ = semantic_expr_type(ctx, locals, ap)
      Ok(ty)
    }
    Array(items) => {
      for item in items {
        match semantic_expr_type(ctx, locals, item) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      Ok(SInt)
    }
    CompoundLiteral(ty, items, _) => {
      for item in items {
        match semantic_expr_type(ctx, locals, item) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      Ok(ty)
    }
    DesignatedField(_, e) | DesignatedIndex(_, e) | DesignatedRange(_, _, e) =>
      semantic_expr_type(ctx, locals, e)
  }
}

///|
fn semantic_validate_stmt(
  ctx : SemanticContext,
  locals : Map[String, Type],
  stmt : Stmt,
) -> Result[Unit, String] {
  match stmt {
    ExprStmt(expr) | ComputedGoto(expr) =>
      match semantic_expr_type(ctx, locals, expr) {
        Ok(_) => Ok(())
        Err(err) => Err(err)
      }
    Return(Some(expr)) =>
      match semantic_expr_type(ctx, locals, expr) {
        Ok(_) => Ok(())
        Err(err) => Err(err)
      }
    Return(None) | Break | Continue | Goto(_) => Ok(())
    VarDecl(ty, name, init) => {
      if name != "" {
        locals[name] = ty
      }
      match init {
        Some(expr) =>
          match semantic_expr_type(ctx, locals, expr) {
            Ok(_) => Ok(())
            Err(err) => Err(err)
          }
        None => Ok(())
      }
    }
    If(cond, then_stmt, else_stmt) => {
      let cond_ty = match semantic_expr_type(ctx, locals, cond) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      if !semantic_is_scalar_type(cond_ty) {
        return Err("if condition must be scalar")
      }
      match semantic_validate_stmt(ctx, locals.copy(), then_stmt) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      match else_stmt {
        Some(stmt) => semantic_validate_stmt(ctx, locals.copy(), stmt)
        None => Ok(())
      }
    }
    While(cond, body) | DoWhile(cond, body) => {
      let cond_ty = match semantic_expr_type(ctx, locals, cond) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      if !semantic_is_scalar_type(cond_ty) {
        return Err("loop condition must be scalar")
      }
      semantic_validate_stmt(ctx, locals.copy(), body)
    }
    Compound(stmts) | StmtList(stmts) => {
      let scoped = locals.copy()
      for item in stmts {
        match semantic_validate_stmt(ctx, scoped, item) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      Ok(())
    }
    Switch(expr, body, _) => {
      let expr_ty = match semantic_expr_type(ctx, locals, expr) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      if !expr_ty.is_integer() {
        return Err("switch expression must be integer")
      }
      semantic_validate_stmt(ctx, locals.copy(), body)
    }
    Label(_, body) => semantic_validate_stmt(ctx, locals.copy(), body)
    For(init, cond, inc, body) => {
      let scoped = locals.copy()
      match init {
        Some(stmt) =>
          match semantic_validate_stmt(ctx, scoped, stmt) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        None => ()
      }
      let cond_ty = match semantic_expr_type(ctx, scoped, cond) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      if !semantic_is_scalar_type(cond_ty) {
        return Err("for condition must be scalar")
      }
      match inc {
        Some(expr) =>
          match semantic_expr_type(ctx, scoped, expr) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        None => ()
      }
      semantic_validate_stmt(ctx, scoped, body)
    }
  }
}

///|
fn semantic_validate_global_init(
  ctx : SemanticContext,
  init : GlobalInit,
) -> Result[Unit, String] {
  let locals : Map[String, Type] = {}
  match init {
    Scalar(expr) =>
      match semantic_expr_type(ctx, locals, expr) {
        Ok(_) => Ok(())
        Err(err) => Err(err)
      }
    Array(items) => {
      for item in items {
        match semantic_expr_type(ctx, locals, item) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      Ok(())
    }
  }
}

///|
fn semantic_context(prog : Program) -> SemanticContext {
  let funcs : Map[String, Type] = {}
  let globals : Map[String, Type] = {}
  let structs : Map[String, StructDecl] = {}
  for decl in prog.decls {
    if decl.name != "" {
      funcs[decl.name] = semantic_func_type(decl)
    }
  }
  for global in prog.globals {
    if global.name != "" {
      globals[global.name] = global.ty
    }
  }
  for decl in prog.structs {
    if decl.name != "" {
      structs[decl.name] = decl
    }
  }
  { funcs, globals, structs }
}

///|
/// Performs lightweight semantic validation over the parsed C AST.
///
/// This is intentionally parser/AST-owned rather than MIR-owned, so the fast
/// direct compiler path can reject common ill-typed programs without lowering
/// through MIR. It is not a complete ISO C constraint checker yet.
pub fn validate_semantics(prog : Program) -> Result[Unit, String] {
  let ctx = semantic_context(prog)
  for global in prog.globals {
    match global.init {
      Some(init) =>
        match semantic_validate_global_init(ctx, init) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      None => ()
    }
  }
  for func in prog.decls {
    match func.body {
      Some(body) => {
        let locals : Map[String, Type] = {}
        for param in func.params {
          if param.name != "" {
            locals[param.name] = param.ty
          }
        }
        match semantic_validate_stmt(ctx, locals, body) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      None => ()
    }
  }
  Ok(())
}
