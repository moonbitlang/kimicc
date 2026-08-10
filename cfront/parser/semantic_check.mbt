///|
priv struct SemanticContext {
  funcs : Map[String, Type]
  globals : Map[String, Type]
  structs : Map[String, StructDecl]
}

///|
fn semantic_core_type(ty : Type) -> Type {
  ty.core_type()
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
    FuncPtr(_, _, _) => Some(ty)
    _ => None
  }
}

///|
fn semantic_is_anon_aggregate_type(ty : Type) -> Bool {
  ty.is_anonymous_aggregate()
}

///|
fn semantic_find_field_type_optional(
  ctx : SemanticContext,
  ty : Type,
  field : String,
) -> Result[Type?, String] {
  let aggregate_name = match semantic_core_type(ty) {
    Struct(name) | Union(name) => name
    _ => return Ok(None)
  }
  if !ctx.structs.contains(aggregate_name) {
    return Err("incomplete aggregate type: " + aggregate_name)
  }
  for param in ctx.structs[aggregate_name].fields {
    if param.name == field {
      return Ok(Some(param.ty))
    }
    if param.name == "" && semantic_is_anon_aggregate_type(param.ty) {
      match semantic_find_field_type_optional(ctx, param.ty, field) {
        Ok(Some(ty)) => return Ok(Some(ty))
        Ok(None) => ()
        Err(err) => return Err(err)
      }
    }
  }
  Ok(None)
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
  match semantic_find_field_type_optional(ctx, ty, field) {
    Ok(Some(ty)) => Ok(ty)
    Ok(None) =>
      Err("unknown field '" + field + "' in aggregate " + aggregate_name)
    Err(err) => Err(err)
  }
}

///|
fn semantic_expr_preview(expr : Expr) -> String {
  match expr {
    Number(n, _, _) => n.to_string()
    FloatLiteral(n, _) => n.to_string()
    String(_) => "string literal"
    Var(name) => name
    Binary(op, _, _) => "binary " + op
    Unary(op, operand) => op + semantic_expr_preview(operand)
    Call(func, _) => "call " + semantic_expr_preview(func)
    Assign(_, _) => "assignment"
    CompoundAssign(op, _, _) => "compound assignment " + op
    MemberAccess(obj, field) => semantic_expr_preview(obj) + "." + field
    Deref(ptr) => "*" + semantic_expr_preview(ptr)
    AddrOf(e) => "&" + semantic_expr_preview(e)
    ArrayAccess(arr, _) => semantic_expr_preview(arr) + "[]"
    Sizeof(_) | SizeofExpr(_) => "sizeof"
    Alignof(_) | AlignofExpr(_) => "alignof"
    Cast(ty, e) => "(" + ty.to_string() + ")" + semantic_expr_preview(e)
    PrefixInc(e) => "++" + semantic_expr_preview(e)
    PrefixDec(e) => "--" + semantic_expr_preview(e)
    PostfixInc(e) => semantic_expr_preview(e) + "++"
    PostfixDec(e) => semantic_expr_preview(e) + "--"
    Ternary(_, _, _) => "ternary"
    LabelAddr(name) => "&&" + name
    VaArg(_, ty) => "va_arg(" + ty.to_string() + ")"
    OffsetOf(_, _) => "offsetof"
    Array(_) => "array initializer"
    CompoundLiteral(ty, _, _) => "compound literal " + ty.to_string()
    DesignatedField(field, _) => "." + field
    DesignatedIndex(index, _) => "[" + index.to_string() + "]"
    DesignatedRange(start, end, _) =>
      "[" + start.to_string() + "..." + end.to_string() + "]"
  }
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
    Number(_, _, _) => Ok(SInt)
    FloatLiteral(_, _) => Ok(Double)
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
            Err(
              "unary numeric operator requires arithmetic operand: " +
              op +
              semantic_expr_preview(operand) +
              " has type " +
              operand_ty.to_string(),
            )
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
    Compound(stmts) => {
      let scoped = locals.copy()
      for item in stmts {
        match semantic_validate_stmt(ctx, scoped, item) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      Ok(())
    }
    StmtList(stmts) => {
      for item in stmts {
        match semantic_validate_stmt(ctx, locals, item) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      Ok(())
    }
    Switch(expr, body) => {
      let expr_ty = match semantic_expr_type(ctx, locals, expr) {
        Ok(ty) => ty
        Err(err) => return Err(err)
      }
      if !expr_ty.is_integer() {
        return Err("switch expression must be integer")
      }
      semantic_validate_stmt(ctx, locals.copy(), body)
    }
    Case(_, body) | Default(body) | Label(_, body) =>
      semantic_validate_stmt(ctx, locals.copy(), body)
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
  let locals : Map[String, Type] = Map([])
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
  let funcs : Map[String, Type] = Map([])
  let globals : Map[String, Type] = Map([])
  let structs : Map[String, StructDecl] = Map([])
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
          Err(err) => return Err("global " + global.name + ": " + err)
        }
      None => ()
    }
  }
  for func in prog.decls {
    match func.body {
      Some(body) => {
        let locals : Map[String, Type] = Map([])
        for param in func.params {
          if param.name != "" {
            locals[param.name] = param.ty
          }
        }
        match semantic_validate_stmt(ctx, locals, body) {
          Ok(_) => ()
          Err(err) => return Err("function " + func.name + ": " + err)
        }
      }
      None => ()
    }
  }
  Ok(())
}
