///|
/// Function signature facts collected from a parsed translation unit.
pub(all) struct FuncSig {
  ret : @ctype.Type
  params : Array[@ctype.Type]
  variadic : Bool
  defined : Bool
  weak : Bool
} derive(Eq)

///|
/// Function parameter facts owned by MIR.
///
/// This mirrors the semantic parameter information needed by later phases
/// without carrying parser declaration nodes.
pub(all) struct MirParam {
  name : String
  ty : @ctype.Type
} derive(Eq)

///|
/// Function declaration or definition metadata owned by MIR.
///
/// `has_body` records whether the parser declaration had a body, but the body
/// itself is represented separately in `Program.bodies` when the MIR body
/// lowering supports it.
pub(all) struct MirFuncDecl {
  ret : @ctype.Type
  name : String
  params : Array[MirParam]
  variadic : Bool
  is_static : Bool
  is_inline : Bool
  is_weak : Bool
  visibility : String?
  symbol_alias : String?
  section : String?
  is_constructor : Bool
  is_destructor : Bool
  has_body : Bool
} derive(Eq)

///|
/// Global declaration metadata owned by MIR.
///
/// Simple initializer payloads are represented by `init`; unsupported
/// initializer syntax is marked explicitly during the data-layer transition.
/// `has_init` lets backend-facing checks reason about declaration/definition
/// state without reading parser declaration nodes.
pub(all) struct MirGlobalDecl {
  ty : @ctype.Type
  name : String
  init : MirGlobalInit?
  has_init : Bool
  is_static : Bool
  is_extern : Bool
  is_weak : Bool
  visibility : String?
  symbol_alias : String?
  section : String?
} derive(Eq)

///|
/// MIR-owned global initializer subset.
///
/// `MirGlobalInitUnsupported` marks initializer syntax that still exists only
/// as parser expressions. This lets later phases distinguish missing
/// initializers from present-but-not-lowered initializers.
pub(all) enum MirGlobalInit {
  MirGlobalScalarInt(Int64)
  MirGlobalScalarFloat(Double)
  MirGlobalString(String)
  MirGlobalSymbol(String)
  MirGlobalSymbolOffset(String, Int)
  MirGlobalLabelAddr(String)
  MirGlobalArray(Array[MirGlobalInit])
  MirGlobalArraySparse(Array[(Int, MirGlobalInit)])
  MirGlobalAggregateSparse(Array[(Int, MirGlobalInit)])
  MirGlobalInitUnsupported
} derive(Eq)

///|
/// Aggregate field declaration metadata owned by MIR.
pub(all) struct MirAggregateField {
  name : String
  ty : @ctype.Type
  bit_width : Int?
} derive(Eq)

///|
/// Struct or union declaration metadata owned by MIR.
///
/// Target-specific byte/bit placement lives in `Program.layouts`; this keeps
/// source declaration facts separate from computed layout facts.
pub(all) struct MirAggregateDecl {
  name : String
  fields : Array[MirAggregateField]
  is_union : Bool
  pack : Int?
} derive(Eq)

///|
/// Lexical expression-typing context used by MIR semantic queries.
pub(all) struct Scope {
  locals : Map[String, @ctype.Type]
  current_func : String
} derive(Eq)

///|
/// Aggregate field layout in target object bytes.
///
/// `bit_width` is `Some(width)` for bit-fields and `None` for ordinary fields.
pub(all) struct FieldLayout {
  name : String
  ty : @ctype.Type
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
  pack : Int?
} derive(Eq)

///|
/// Target-sensitive C semantic facts derived from the parser AST.
pub(all) struct Program {
  target : @target.Target
  priv source : @parser.Program
  decls : Array[MirFuncDecl]
  global_decls : Array[MirGlobalDecl]
  aggregate_decls : Array[MirAggregateDecl]
  funcs : Map[String, FuncSig]
  globals : Map[String, MirGlobalDecl]
  aggregates : Map[String, MirAggregateDecl]
  layouts : Map[String, AggregateLayout]
  bodies : Map[String, MirFuncBody]
}

///|
/// Parser-free MIR module facts intended for backend consumers.
///
/// This is the long-term codegen boundary. `Program` keeps parser source while
/// lowering and fallback consumers are still migrating; `MirModule` contains
/// only MIR-owned declarations, layouts, and lowered bodies.
pub(all) struct MirModule {
  target : @target.Target
  decls : Array[MirFuncDecl]
  global_decls : Array[MirGlobalDecl]
  aggregate_decls : Array[MirAggregateDecl]
  funcs : Map[String, FuncSig]
  globals : Map[String, MirGlobalDecl]
  aggregates : Map[String, MirAggregateDecl]
  layouts : Map[String, AggregateLayout]
  bodies : Map[String, MirFuncBody]
}

///|
/// Projects a `Program` onto a parser-free `MirModule`.
///
/// `Program` retains the original `@parser.Program` (in a private field) so it
/// can answer semantic queries during lowering and fallback. `MirModule` keeps
/// only MIR-owned declarations, computed layouts, and lowered bodies, which is
/// the long-term boundary the MIR backend consumes. Calling this first forces
/// every aggregate layout to be computed, so the resulting module's `layouts`
/// map is fully populated.
///
/// # Example
///
/// ```moonbit check
/// test {
///   let program = @mir.lower(
///     @parser.parse("int main(void) { return 0; }"),
///     @target.Target::default(),
///   )
///   let module_ = program.to_module()
///   inspect(module_.bodies.contains("main"), content="true")
/// }
/// ```
pub fn Program::to_module(self : Program) -> MirModule {
  for decl in self.aggregate_decls {
    let ty = if decl.is_union {
      @ctype.Type::Union(decl.name)
    } else {
      Struct(decl.name)
    }
    let _ = self.type_size(ty)
  }
  {
    target: self.target,
    decls: self.decls,
    global_decls: self.global_decls,
    aggregate_decls: self.aggregate_decls,
    funcs: self.funcs,
    globals: self.globals,
    aggregates: self.aggregates,
    layouts: self.layouts,
    bodies: self.bodies,
  }
}

///|
/// Returns an empty typing scope with no locals and no current function.
///
/// A `Scope` supplies the local-variable types that MIR semantic queries (such
/// as constant folding of expressions) need. The empty scope is the right
/// starting point for evaluating expressions that do not reference locals, for
/// example file-scope constant initializers.
pub fn Scope::empty() -> Scope {
  { locals: {}, current_func: "" }
}

///|
fn should_replace_mir_global_decl(
  old : MirGlobalDecl,
  next : MirGlobalDecl,
) -> Bool {
  if next.is_extern && !next.has_init {
    false
  } else if !old.has_init && next.has_init {
    true
  } else if old.is_extern && !next.is_extern {
    true
  } else if old.has_init && !next.has_init {
    false
  } else {
    next.has_init
  }
}

///|
fn merge_mir_global_visibility(
  primary : MirGlobalDecl,
  other : MirGlobalDecl,
) -> String? {
  match primary.visibility {
    Some(_) => primary.visibility
    None => other.visibility
  }
}

///|
fn merge_mir_global_alias(
  primary : MirGlobalDecl,
  other : MirGlobalDecl,
) -> String? {
  match primary.symbol_alias {
    Some(_) => primary.symbol_alias
    None => other.symbol_alias
  }
}

///|
fn merge_mir_global_section(
  primary : MirGlobalDecl,
  other : MirGlobalDecl,
) -> String? {
  match primary.section {
    Some(_) => primary.section
    None => other.section
  }
}

///|
fn MirGlobalDecl::with_merged_attrs(
  self : MirGlobalDecl,
  other : MirGlobalDecl,
) -> MirGlobalDecl {
  {
    ty: self.ty,
    name: self.name,
    init: self.init,
    has_init: self.has_init,
    is_static: self.is_static,
    is_extern: self.is_extern,
    is_weak: self.is_weak || other.is_weak,
    visibility: merge_mir_global_visibility(self, other),
    symbol_alias: merge_mir_global_alias(self, other),
    section: merge_mir_global_section(self, other),
  }
}

///|
/// Coalesces repeated declarations of the same global into one definition.
///
/// C allows a global to be declared several times (tentative definitions,
/// `extern` re-declarations, attribute-only declarations). This merges entries
/// that share a name in source order: an initializing definition wins over a
/// tentative or `extern` declaration, and attributes such as weakness,
/// visibility, symbol alias, and section are combined so the surviving entry
/// carries the union of what was specified. Declarations with distinct names
/// are preserved in their original order.
///
/// Parameters:
///
/// - `globals`: the per-declaration global entries, in source order.
///
/// Returns one merged entry per distinct global name.
pub fn merge_global_decls(
  globals : Array[MirGlobalDecl],
) -> Array[MirGlobalDecl] {
  let merged : Array[MirGlobalDecl] = []
  for g in globals {
    let mut found = -1
    for i = 0; i < merged.length(); i = i + 1 {
      if merged[i].name == g.name {
        found = i
      }
    }
    if found < 0 {
      merged.push(g)
    } else if should_replace_mir_global_decl(merged[found], g) {
      merged[found] = g.with_merged_attrs(merged[found])
    } else {
      merged[found] = merged[found].with_merged_attrs(g)
    }
  }
  merged
}

///|
fn MirGlobalDecl::with_init(
  self : MirGlobalDecl,
  init : MirGlobalInit?,
) -> MirGlobalDecl {
  {
    ty: self.ty,
    name: self.name,
    init,
    has_init: self.has_init,
    is_static: self.is_static,
    is_extern: self.is_extern,
    is_weak: self.is_weak,
    visibility: self.visibility,
    symbol_alias: self.symbol_alias,
    section: self.section,
  }
}

///|
fn MirGlobalDecl::from_parser(g : @parser.GlobalDecl) -> MirGlobalDecl {
  {
    ty: g.ty,
    name: g.name,
    init: None,
    has_init: g.init is Some(_),
    is_static: g.is_static,
    is_extern: g.is_extern,
    is_weak: g.is_weak,
    visibility: g.visibility,
    symbol_alias: g.symbol_alias,
    section: g.section,
  }
}

///|
fn mir_file_scope_compound_literal_name(id : Int) -> String {
  "__kimicc_file_scope_compound_literal_" + id.to_string()
}

///|
fn mir_compound_literal_array_length(exprs : Array[@parser.Expr]) -> Int {
  let mut cursor = 0
  let mut length = 0
  for expr in exprs {
    match expr {
      DesignatedIndex(index, _) => {
        cursor = index.to_int() + 1
        if cursor > length {
          length = cursor
        }
      }
      DesignatedRange(_, last, _) => {
        cursor = last.to_int() + 1
        if cursor > length {
          length = cursor
        }
      }
      _ => {
        cursor += 1
        if cursor > length {
          length = cursor
        }
      }
    }
  }
  length
}

///|
fn mir_file_scope_compound_literal_type(
  ty : @ctype.Type,
  exprs : Array[@parser.Expr],
) -> @ctype.Type {
  match ty {
    Array(elem, n) =>
      if n <= 0 {
        Array(elem, mir_compound_literal_array_length(exprs))
      } else {
        ty
      }
    Aligned(inner, align) =>
      Aligned(mir_file_scope_compound_literal_type(inner, exprs), align)
    _ => ty
  }
}

///|
fn Program::lower_mir_global_init(
  self : Program,
  ty : @ctype.Type,
  init : @parser.GlobalInit?,
) -> MirGlobalInit? {
  match init {
    None => None
    Some(Scalar(expr)) =>
      Some(self.lower_mir_global_scalar_init_for_type(ty, expr))
    Some(Array(exprs)) => {
      if exprs.length() == 1 {
        match (self.core_type(ty), exprs[0]) {
          (Array(SChar, _) | Array(UChar, _), String(s)) =>
            return Some(MirGlobalString(s))
          _ => ()
        }
      }
      match self.core_type(ty) {
        Struct(_) | Union(_) | Array(_, _) =>
          Some(self.lower_mir_global_array_init_for_type(ty, exprs))
        _ => Some(self.lower_mir_global_braced_scalar_init_for_type(ty, exprs))
      }
    }
  }
}

///|
fn mir_global_array_uses_sparse(exprs : Array[@parser.Expr]) -> Bool {
  for expr in exprs {
    match expr {
      DesignatedIndex(_, _) | DesignatedRange(_, _, _) => return true
      _ => ()
    }
  }
  false
}

///|
fn mir_global_aggregate_uses_sparse(exprs : Array[@parser.Expr]) -> Bool {
  for expr in exprs {
    match expr {
      DesignatedField(_, _) => return true
      _ => ()
    }
  }
  false
}

///|
fn Program::lower_mir_global_array_value(
  self : Program,
  expr : @parser.Expr,
) -> MirGlobalInit {
  match expr {
    Array(nested) => {
      let nested_values : Array[MirGlobalInit] = []
      for nested_expr in nested {
        nested_values.push(self.lower_mir_global_array_value(nested_expr))
      }
      MirGlobalArray(nested_values)
    }
    _ => self.lower_mir_global_scalar_init(expr)
  }
}

///|
fn Program::lower_mir_global_value_for_type(
  self : Program,
  ty : @ctype.Type,
  expr : @parser.Expr,
) -> MirGlobalInit {
  match expr {
    Array(exprs) =>
      match self.core_type(ty) {
        Struct(_) | Union(_) | Array(_, _) =>
          self.lower_mir_global_array_init_for_type(ty, exprs)
        _ => self.lower_mir_global_braced_scalar_init_for_type(ty, exprs)
      }
    CompoundLiteral(lit_ty, exprs, id) =>
      if self.mir_global_compound_literal_decays_to_pointer(ty, lit_ty) {
        MirGlobalSymbol(mir_file_scope_compound_literal_name(id))
      } else {
        self.lower_mir_global_compound_literal_init_for_type(ty, exprs)
      }
    DesignatedField(_, value)
    | DesignatedIndex(_, value)
    | DesignatedRange(_, _, value) =>
      if self.mir_global_designator_matches_type(ty, expr) {
        self.lower_mir_global_array_init_for_type(ty, [expr])
      } else {
        self.lower_mir_global_value_for_type(ty, value)
      }
    _ => self.lower_mir_global_scalar_init_for_type(ty, expr)
  }
}

///|
fn Program::mir_global_compound_literal_decays_to_pointer(
  self : Program,
  target_ty : @ctype.Type,
  literal_ty : @ctype.Type,
) -> Bool {
  match (self.core_type(target_ty), self.core_type(literal_ty)) {
    (Pointer(_), Array(_, _)) => true
    _ => false
  }
}

///|
fn Program::lower_mir_global_compound_literal_init_for_type(
  self : Program,
  ty : @ctype.Type,
  exprs : Array[@parser.Expr],
) -> MirGlobalInit {
  match self.core_type(ty) {
    Struct(_) | Union(_) | Array(_, _) =>
      self.lower_mir_global_array_init_for_type(ty, exprs)
    _ =>
      if exprs.length() > 0 {
        self.lower_mir_global_value_for_type(ty, exprs[0])
      } else {
        MirGlobalScalarInt(0)
      }
  }
}

///|
fn Program::lower_mir_global_braced_scalar_init_for_type(
  self : Program,
  ty : @ctype.Type,
  exprs : Array[@parser.Expr],
) -> MirGlobalInit {
  if exprs.length() == 0 {
    return self.lower_mir_global_scalar_init_for_type(ty, Number(0))
  }
  match exprs[0] {
    Array(nested) =>
      self.lower_mir_global_braced_scalar_init_for_type(ty, nested)
    DesignatedField(_, value)
    | DesignatedIndex(_, value)
    | DesignatedRange(_, _, value) =>
      self.lower_mir_global_braced_scalar_init_for_type(ty, [value])
    value => self.lower_mir_global_value_for_type(ty, value)
  }
}

///|
fn Program::mir_global_designator_matches_type(
  self : Program,
  ty : @ctype.Type,
  expr : @parser.Expr,
) -> Bool {
  match (self.core_type(ty), expr) {
    (Struct(_), DesignatedField(field, _))
    | (Union(_), DesignatedField(field, _)) =>
      self.field_layout(ty, field) is Some(_)
    (Array(_, _), DesignatedIndex(_, _))
    | (Array(_, _), DesignatedRange(_, _, _)) => true
    _ => false
  }
}

///|
fn Program::lower_mir_global_array_init_for_type(
  self : Program,
  ty : @ctype.Type,
  exprs : Array[@parser.Expr],
) -> MirGlobalInit {
  match self.core_type(ty) {
    Array(elem_ty, _) =>
      if mir_global_array_uses_sparse(exprs) {
        self.lower_mir_global_sparse_array_init(elem_ty, exprs)
      } else {
        let values : Array[MirGlobalInit] = []
        for expr in exprs {
          values.push(self.lower_mir_global_value_for_type(elem_ty, expr))
        }
        MirGlobalArray(values)
      }
    Struct(name) | Union(name) => {
      let layout = self.aggregate_layout_by_name(name)
      if mir_global_aggregate_uses_sparse(exprs) {
        self.lower_mir_global_sparse_aggregate_init(layout, exprs)
      } else {
        self.lower_mir_global_dense_aggregate_init(layout, exprs)
      }
    }
    _ => {
      let values : Array[MirGlobalInit] = []
      for expr in exprs {
        values.push(self.lower_mir_global_array_value(expr))
      }
      MirGlobalArray(values)
    }
  }
}

///|
fn Program::lower_mir_global_sparse_array_init(
  self : Program,
  elem_ty : @ctype.Type,
  exprs : Array[@parser.Expr],
) -> MirGlobalInit {
  let values : Array[(Int, MirGlobalInit)] = []
  let mut cursor = 0
  for expr in exprs {
    match expr {
      DesignatedIndex(index, value) => {
        let idx = index.to_int()
        values.push((idx, self.lower_mir_global_value_for_type(elem_ty, value)))
        cursor = idx + 1
      }
      DesignatedRange(first, last, value) => {
        let start = first.to_int()
        let end = last.to_int()
        for idx = start; idx <= end; idx = idx + 1 {
          values.push(
            (idx, self.lower_mir_global_value_for_type(elem_ty, value)),
          )
        }
        cursor = end + 1
      }
      _ => {
        values.push(
          (cursor, self.lower_mir_global_value_for_type(elem_ty, expr)),
        )
        cursor += 1
      }
    }
  }
  MirGlobalArraySparse(values)
}

///|
fn aggregate_field_index(layout : AggregateLayout, field_name : String) -> Int {
  for i = 0; i < layout.fields.length(); i = i + 1 {
    if layout.fields[i].name == field_name {
      return i
    }
  }
  -1
}

///|
fn Program::lower_mir_global_sparse_aggregate_init(
  self : Program,
  layout : AggregateLayout,
  exprs : Array[@parser.Expr],
) -> MirGlobalInit {
  let values : Array[(Int, MirGlobalInit)] = []
  if layout.is_union {
    if exprs.length() > 0 {
      match exprs[0] {
        DesignatedField(field_name, value) => {
          let index = aggregate_field_index(layout, field_name)
          let init = if index >= 0 {
            self.lower_mir_global_value_for_type(layout.fields[index].ty, value)
          } else {
            self.lower_mir_global_array_value(value)
          }
          values.push((index, init))
        }
        value =>
          if layout.fields.length() > 0 {
            values.push(
              (
                0,
                self.lower_mir_global_value_for_type(layout.fields[0].ty, value),
              ),
            )
          } else {
            values.push((0, self.lower_mir_global_array_value(value)))
          }
      }
    }
    return MirGlobalAggregateSparse(values)
  }
  let mut positional = 0
  for expr in exprs {
    match expr {
      DesignatedField(field_name, value) => {
        let index = aggregate_field_index(layout, field_name)
        if index >= 0 {
          positional = index + 1
          values.push(
            (
              index,
              self.lower_mir_global_value_for_type(
                layout.fields[index].ty,
                value,
              ),
            ),
          )
        } else {
          values.push((index, self.lower_mir_global_array_value(value)))
        }
      }
      value => {
        if positional < layout.fields.length() {
          values.push(
            (
              positional,
              self.lower_mir_global_value_for_type(
                layout.fields[positional].ty,
                value,
              ),
            ),
          )
        } else {
          values.push((positional, self.lower_mir_global_array_value(value)))
        }
        positional += 1
      }
    }
  }
  MirGlobalAggregateSparse(values)
}

///|
fn Program::lower_mir_global_dense_aggregate_init(
  self : Program,
  layout : AggregateLayout,
  exprs : Array[@parser.Expr],
) -> MirGlobalInit {
  let values : Array[MirGlobalInit] = []
  let count = if layout.is_union && exprs.length() > 0 {
    1
  } else {
    exprs.length()
  }
  for i = 0; i < count; i = i + 1 {
    if i < layout.fields.length() {
      values.push(
        self.lower_mir_global_value_for_type(layout.fields[i].ty, exprs[i]),
      )
    } else {
      values.push(self.lower_mir_global_array_value(exprs[i]))
    }
  }
  MirGlobalArray(values)
}

///|
fn Program::lower_mir_global_scalar_init(
  self : Program,
  expr : @parser.Expr,
) -> MirGlobalInit {
  match expr {
    Number(n) => MirGlobalScalarInt(n)
    String(s) => MirGlobalString(s)
    LabelAddr(name) => MirGlobalLabelAddr(name)
    DesignatedField(_, _) | DesignatedIndex(_, _) | DesignatedRange(_, _, _) =>
      MirGlobalInitUnsupported
    _ =>
      match self.lower_mir_global_address_reloc_parts(expr) {
        Some((name, offset)) =>
          if offset == 0 {
            MirGlobalSymbol(name)
          } else {
            MirGlobalSymbolOffset(name, offset)
          }
        None =>
          match self.fold_const(expr, Scope::empty()) {
            Some(n) => MirGlobalScalarInt(n)
            None => MirGlobalInitUnsupported
          }
      }
  }
}

///|
fn Program::lower_mir_file_scope_compound_literal_global(
  self : Program,
  ty : @ctype.Type,
  exprs : Array[@parser.Expr],
  id : Int,
) -> MirGlobalDecl {
  let completed_ty = mir_file_scope_compound_literal_type(ty, exprs)
  {
    ty: completed_ty,
    name: mir_file_scope_compound_literal_name(id),
    init: Some(
      self.lower_mir_global_compound_literal_init_for_type(completed_ty, exprs),
    ),
    has_init: true,
    is_static: true,
    is_extern: false,
    is_weak: false,
    visibility: None,
    symbol_alias: None,
    section: None,
  }
}

///|
fn Program::collect_mir_file_scope_compound_literal_globals_expr(
  self : Program,
  expr : @parser.Expr,
  seen : Map[Int, Bool],
  globals : Array[MirGlobalDecl],
) -> Unit {
  match expr {
    CompoundLiteral(ty, exprs, id) => {
      if !seen.contains(id) {
        seen[id] = true
        globals.push(
          self.lower_mir_file_scope_compound_literal_global(ty, exprs, id),
        )
      }
      for item in exprs {
        self.collect_mir_file_scope_compound_literal_globals_expr(
          item, seen, globals,
        )
      }
    }
    Binary(_, lhs, rhs) | Assign(lhs, rhs) | CompoundAssign(_, lhs, rhs) => {
      self.collect_mir_file_scope_compound_literal_globals_expr(
        lhs, seen, globals,
      )
      self.collect_mir_file_scope_compound_literal_globals_expr(
        rhs, seen, globals,
      )
    }
    Unary(_, value)
    | Deref(value)
    | AddrOf(value)
    | Cast(_, value)
    | PrefixInc(value)
    | PrefixDec(value)
    | PostfixInc(value)
    | PostfixDec(value)
    | DesignatedField(_, value)
    | DesignatedIndex(_, value)
    | DesignatedRange(_, _, value) =>
      self.collect_mir_file_scope_compound_literal_globals_expr(
        value, seen, globals,
      )
    Call(func, args) => {
      self.collect_mir_file_scope_compound_literal_globals_expr(
        func, seen, globals,
      )
      for arg in args {
        self.collect_mir_file_scope_compound_literal_globals_expr(
          arg, seen, globals,
        )
      }
    }
    MemberAccess(obj, _) =>
      self.collect_mir_file_scope_compound_literal_globals_expr(
        obj, seen, globals,
      )
    ArrayAccess(base, index) => {
      self.collect_mir_file_scope_compound_literal_globals_expr(
        base, seen, globals,
      )
      self.collect_mir_file_scope_compound_literal_globals_expr(
        index, seen, globals,
      )
    }
    Ternary(cond, then_, else_) => {
      self.collect_mir_file_scope_compound_literal_globals_expr(
        cond, seen, globals,
      )
      self.collect_mir_file_scope_compound_literal_globals_expr(
        then_, seen, globals,
      )
      self.collect_mir_file_scope_compound_literal_globals_expr(
        else_, seen, globals,
      )
    }
    VaArg(ap, _) =>
      self.collect_mir_file_scope_compound_literal_globals_expr(
        ap, seen, globals,
      )
    Array(values) =>
      for value in values {
        self.collect_mir_file_scope_compound_literal_globals_expr(
          value, seen, globals,
        )
      }
    SizeofExpr(_) | AlignofExpr(_) => ()
    Number(_)
    | FloatLiteral(_)
    | String(_)
    | Var(_)
    | Sizeof(_)
    | Alignof(_)
    | LabelAddr(_)
    | OffsetOf(_, _) => ()
  }
}

///|
fn Program::append_mir_file_scope_compound_literal_globals(
  self : Program,
  source_globals : Array[@parser.GlobalDecl],
) -> Unit {
  let seen : Map[Int, Bool] = Map([])
  let generated : Array[MirGlobalDecl] = []
  for global in source_globals {
    match global.init {
      Some(Scalar(expr)) =>
        self.collect_mir_file_scope_compound_literal_globals_expr(
          expr, seen, generated,
        )
      Some(Array(exprs)) =>
        for expr in exprs {
          self.collect_mir_file_scope_compound_literal_globals_expr(
            expr, seen, generated,
          )
        }
      None => ()
    }
  }
  for global in generated {
    self.global_decls.push(global)
  }
}

///|
fn mir_global_string_literal(expr : @parser.Expr) -> String? {
  match expr {
    String(value) => Some(value)
    Cast(_, inner) => mir_global_string_literal(inner)
    _ => None
  }
}

///|
fn Program::lower_mir_global_scalar_init_for_type(
  self : Program,
  ty : @ctype.Type,
  expr : @parser.Expr,
) -> MirGlobalInit {
  match expr {
    CompoundLiteral(lit_ty, exprs, id) =>
      if self.mir_global_compound_literal_decays_to_pointer(ty, lit_ty) {
        return MirGlobalSymbol(mir_file_scope_compound_literal_name(id))
      } else {
        return self.lower_mir_global_compound_literal_init_for_type(ty, exprs)
      }
    _ => ()
  }
  match self.core_type(ty) {
    Pointer(_) | Array(SChar, _) | Array(UChar, _) =>
      match mir_global_string_literal(expr) {
        Some(value) => return MirGlobalString(value)
        None => ()
      }
    _ => ()
  }
  if ty.is_floating() {
    match self.fold_float_const(expr, Scope::empty()) {
      Some(value) => return MirGlobalScalarFloat(value)
      None => ()
    }
  } else if ty.is_integer() &&
    self.expr_type(expr, Scope::empty()).is_floating() {
    match self.fold_float_const(expr, Scope::empty()) {
      Some(value) =>
        return MirGlobalScalarInt(
          @ctype.floating_constant_to_integer_bits(value),
        )
      None => ()
    }
  }
  self.lower_mir_global_scalar_init(expr)
}

///|
fn Program::global_init_pointer_element_size(
  self : Program,
  elem_ty : @ctype.Type,
) -> Int {
  match self.core_type(elem_ty) {
    Void => 1
    _ => self.type_size(elem_ty)
  }
}

///|
fn Program::global_init_offset_bytes(
  self : Program,
  base : @parser.Expr,
  offset : Int64,
) -> Int {
  match self.core_type(self.global_expr_type(base)) {
    Pointer(elem) | Array(elem, _) =>
      offset.to_int() * self.global_init_pointer_element_size(elem)
    _ => offset.to_int()
  }
}

///|
fn Program::lower_mir_global_lvalue_reloc_parts(
  self : Program,
  expr : @parser.Expr,
) -> (String, Int)? {
  match expr {
    Var(name) => Some((name, 0))
    CompoundLiteral(_, _, id) =>
      Some((mir_file_scope_compound_literal_name(id), 0))
    Cast(_, inner) => self.lower_mir_global_lvalue_reloc_parts(inner)
    Deref(inner) => self.lower_mir_global_address_reloc_parts(inner)
    ArrayAccess(base, index) =>
      match
        (
          self.lower_mir_global_lvalue_reloc_parts(base),
          self.lower_mir_global_address_reloc_parts(base),
        ) {
        (Some(parts), _) | (None, Some(parts)) => {
          let (name, base_offset) = parts
          let elem_size = match self.core_type(self.global_expr_type(base)) {
            Array(elem, _) | Pointer(elem) =>
              self.global_init_pointer_element_size(elem)
            _ => 1
          }
          match self.fold_const(index, Scope::empty()) {
            Some(i) => Some((name, base_offset + i.to_int() * elem_size))
            None => None
          }
        }
        _ => None
      }
    MemberAccess(obj, field) =>
      match self.lower_mir_global_lvalue_reloc_parts(obj) {
        Some((name, base_offset)) =>
          match self.field_layout(self.global_expr_type(obj), field) {
            Some(layout) => Some((name, base_offset + layout.offset))
            None => None
          }
        None => None
      }
    _ => None
  }
}

///|
fn Program::lower_mir_global_address_reloc_parts(
  self : Program,
  expr : @parser.Expr,
) -> (String, Int)? {
  match expr {
    Var(name) => Some((name, 0))
    CompoundLiteral(_, _, id) =>
      Some((mir_file_scope_compound_literal_name(id), 0))
    Cast(_, inner) => self.lower_mir_global_address_reloc_parts(inner)
    AddrOf(inner) => self.lower_mir_global_lvalue_reloc_parts(inner)
    Binary("+", base, offset_expr) =>
      match
        (
          self.lower_mir_global_address_reloc_parts(base),
          self.fold_const(offset_expr, Scope::empty()),
        ) {
        (Some((name, base_offset)), Some(offset)) =>
          Some(
            (name, base_offset + self.global_init_offset_bytes(base, offset)),
          )
        _ =>
          match
            (
              self.lower_mir_global_address_reloc_parts(offset_expr),
              self.fold_const(base, Scope::empty()),
            ) {
            (Some((name, base_offset)), Some(offset)) =>
              Some(
                (
                  name,
                  base_offset +
                  self.global_init_offset_bytes(offset_expr, offset),
                ),
              )
            _ => None
          }
      }
    Binary("-", base, offset_expr) =>
      match
        (
          self.lower_mir_global_address_reloc_parts(base),
          self.fold_const(offset_expr, Scope::empty()),
        ) {
        (Some((name, base_offset)), Some(offset)) =>
          Some(
            (name, base_offset - self.global_init_offset_bytes(base, offset)),
          )
        _ => None
      }
    _ => None
  }
}

///|
/// Lowers a parsed translation unit into a target-sensitive MIR `Program`.
///
/// This is the entry point of the `cast -> mir` half of the pipeline. It walks
/// the parser AST and builds MIR-owned tables: function signatures and
/// declarations, merged global declarations with lowered initializers,
/// aggregate declarations, and a lowered body (`MirFuncBody`) for every defined
/// function whose body the MIR layer supports — functions using constructs not
/// yet modeled are simply omitted from `bodies`. Type sizes and layouts follow
/// `target`, so the same C source lowered for different targets can differ.
///
/// The returned `Program` still retains the source AST for semantic queries;
/// call `to_module` (or use `lower_to_module`) to obtain the parser-free
/// `MirModule` the backend consumes.
///
/// Parameters:
///
/// - `source`: an already-parsed translation unit.
/// - `target`: the target whose ABI drives sizes, alignments, and layouts.
///
/// Returns the lowered MIR `Program`.
///
/// # Example
///
/// ```moonbit check
/// test {
///   let program = @mir.lower(
///     @parser.parse("int add(int x, int y) { return x + y; }"),
///     @target.Target::default(),
///   )
///   inspect(program.bodies.contains("add"), content="true")
///   // int is 4 bytes on the supported targets.
///   inspect(program.type_size(SInt), content="4")
/// }
/// ```
pub fn lower(source : @parser.Program, target : @target.Target) -> Program {
  let funcs : Map[String, FuncSig] = Map([])
  let decls : Array[MirFuncDecl] = []
  for decl in source.decls {
    let param_types : Array[@ctype.Type] = []
    let params : Array[MirParam] = []
    for param in decl.params {
      param_types.push(param.ty)
      params.push({ name: param.name, ty: param.ty })
    }
    funcs[decl.name] = {
      ret: decl.ret,
      params: param_types,
      variadic: decl.variadic,
      defined: decl.body is Some(_) || decl.symbol_alias is Some(_),
      weak: decl.is_weak,
    }
    decls.push({
      ret: decl.ret,
      name: decl.name,
      params,
      variadic: decl.variadic,
      is_static: decl.is_static,
      is_inline: decl.is_inline,
      is_weak: decl.is_weak,
      visibility: decl.visibility,
      symbol_alias: decl.symbol_alias,
      section: decl.section,
      is_constructor: decl.is_constructor,
      is_destructor: decl.is_destructor,
      has_body: decl.body is Some(_),
    })
  }
  let globals : Map[String, MirGlobalDecl] = Map([])
  let global_decls : Array[MirGlobalDecl] = []
  for g in source.globals {
    let mir_global = MirGlobalDecl::from_parser(g)
    if !globals.contains(g.name) ||
      should_replace_mir_global_decl(globals[g.name], mir_global) {
      if globals.contains(g.name) {
        globals[g.name] = mir_global.with_merged_attrs(globals[g.name])
      } else {
        globals[g.name] = mir_global
      }
    } else {
      globals[g.name] = globals[g.name].with_merged_attrs(mir_global)
    }
    global_decls.push(mir_global)
  }
  let aggregates : Map[String, MirAggregateDecl] = Map([])
  let aggregate_decls : Array[MirAggregateDecl] = []
  for decl in source.structs {
    let fields : Array[MirAggregateField] = []
    for field in decl.fields {
      fields.push({ name: field.name, ty: field.ty, bit_width: field.bit_width })
    }
    let aggregate_decl = {
      name: decl.name,
      fields,
      is_union: decl.is_union,
      pack: decl.pack,
    }
    aggregates[decl.name] = aggregate_decl
    aggregate_decls.push(aggregate_decl)
  }
  let program = {
    target,
    source,
    decls,
    global_decls,
    aggregate_decls,
    funcs,
    globals,
    aggregates,
    layouts: {},
    bodies: {},
  }
  for i = 0; i < source.globals.length(); i = i + 1 {
    let g = source.globals[i]
    program.global_decls[i] = program.global_decls[i].with_init(
      program.lower_mir_global_init(g.ty, g.init),
    )
  }
  program.append_mir_file_scope_compound_literal_globals(source.globals)
  for g in merge_global_decls(program.global_decls) {
    program.globals[g.name] = g
  }
  for decl in source.decls {
    match program.lower_mir_func_body(decl) {
      Some(body) => program.bodies[decl.name] = body
      None => ()
    }
  }
  program
}

///|
/// Lowers a parsed translation unit directly to a parser-free `MirModule`.
///
/// This is the convenience composition of `lower` followed by `to_module`, and
/// the typical entry point for the MIR backend
/// (`@mir_codegen.generate_assembly_from_mir_module`). Use `lower` instead when
/// you need the intermediate `Program` for semantic queries or interpretation.
///
/// Parameters:
///
/// - `source`: an already-parsed translation unit.
/// - `target`: the target whose ABI drives sizes, alignments, and layouts.
///
/// Returns the parser-free `MirModule`.
pub fn lower_to_module(
  source : @parser.Program,
  target : @target.Target,
) -> MirModule {
  lower(source, target).to_module()
}

///|
fn Program::core_type(self : Program, ty : @ctype.Type) -> @ctype.Type {
  ignore(self)
  ty.core_type()
}

///|
fn Program::pointer_element(self : Program, ty : @ctype.Type) -> @ctype.Type? {
  ignore(self)
  ty.pointer_or_array_element()
}

///|
fn Program::offset_array_element(
  self : Program,
  ty : @ctype.Type,
) -> @ctype.Type? {
  ignore(self)
  ty.array_element()
}

///|
fn Program::is_floating_type(self : Program, ty : @ctype.Type) -> Bool {
  match self.core_type(ty) {
    Float | Double => true
    LongDouble => self.target is DarwinArm64
    _ => false
  }
}

///|
fn Program::is_floating_const_type(self : Program, ty : @ctype.Type) -> Bool {
  match self.core_type(ty) {
    Float | Double | LongDouble => true
    _ => false
  }
}

///|
fn Program::unary_numeric_result_type(
  self : Program,
  ty : @ctype.Type,
) -> @ctype.Type {
  @ctype.unary_numeric_result_type(ty, self.target is DarwinArm64)
}

///|
fn Program::ternary_result_type(
  self : Program,
  then_ty : @ctype.Type,
  else_ty : @ctype.Type,
) -> @ctype.Type {
  @ctype.ternary_result_type(then_ty, else_ty, self.target is DarwinArm64)
}

///|
fn number_literal_type(value : Int64) -> @ctype.Type {
  @ctype.integer_literal_type(value)
}

///|
/// Returns the size in bytes of a C type under this program's target ABI.
///
/// Unlike `@ctype.Type::size`, this resolves `Struct`/`Union` types by looking
/// up the aggregate layout computed during lowering, so it works for aggregate
/// types a bare `@ctype.Type` cannot size on its own. `Atomic` and `Aligned`
/// wrappers report the size of their inner type. Target-specific types such as
/// `_Float16`, `__float128`, and `long double` follow the rules of
/// `self.target`, aborting for spellings the target does not support.
///
/// # Example
///
/// ```moonbit check
/// test {
///   let program = @mir.lower(
///     @parser.parse("struct P { int x; int y; }; int main(void) { return 0; }"),
///     @target.Target::default(),
///   )
///   inspect(program.type_size(SInt), content="4")
///   inspect(program.type_size(Struct("P")), content="8")
/// }
/// ```
pub fn Program::type_size(self : Program, ty : @ctype.Type) -> Int {
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
/// Returns the alignment in bytes of a C type under this program's target ABI.
///
/// Like `type_size`, this resolves aggregates through their computed layout.
/// An `Aligned(inner, n)` wrapper reports the larger of `n` and the natural
/// alignment of `inner`, modeling `_Alignas` and GNU `aligned` attributes;
/// `Atomic` reports the alignment of its inner type.
///
/// # Example
///
/// ```moonbit check
/// test {
///   let program = @mir.lower(
///     @parser.parse("int main(void) { return 0; }"),
///     @target.Target::default(),
///   )
///   inspect(program.type_align(Double), content="8")
///   inspect(program.type_align(Aligned(SChar, 16)), content="16")
/// }
/// ```
pub fn Program::type_align(self : Program, ty : @ctype.Type) -> Int {
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
fn Program::flatten_anon_fields(
  self : Program,
  ty : @ctype.Type,
  base_offset : Int,
) -> Array[FieldLayout] {
  let name = match self.core_type(ty) {
    Struct(n) | Union(n) => n
    _ => return []
  }
  let layout = self.aggregate_layout_by_name(name)
  let fields : Array[FieldLayout] = []
  for field in layout.fields {
    if field.name == "" && field.ty.is_anonymous_aggregate() {
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
  decl : MirAggregateDecl,
) -> AggregateLayout {
  let fields : Array[FieldLayout] = []
  let mut offset = 0
  let mut in_bitfield_run = false
  let mut current_bit_offset = 0
  for field in decl.fields {
    if field.name == "" && field.ty.is_anonymous_aggregate() {
      let align = @parser.packed_align(decl.pack, self.type_align(field.ty))
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
        let align = @parser.packed_align(decl.pack, self.type_align(field.ty))
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
        let container_align = @parser.packed_align(
          decl.pack,
          self.type_align(field.ty),
        )
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
    let field_align = @parser.packed_align(decl.pack, self.type_align(field.ty))
    if field_align > max_align {
      max_align = field_align
    }
  }
  {
    fields,
    size: align_to(max_end, max_align),
    align: max_align,
    is_union: false,
    pack: decl.pack,
  }
}

///|
fn Program::compute_union_layout(
  self : Program,
  decl : MirAggregateDecl,
) -> AggregateLayout {
  let fields : Array[FieldLayout] = []
  let mut max_size = 0
  let mut max_align = 1
  for field in decl.fields {
    if field.name == "" && field.ty.is_anonymous_aggregate() {
      for inner in self.flatten_anon_fields(field.ty, 0) {
        fields.push(inner)
      }
      let size = self.type_size(field.ty)
      if size > max_size {
        max_size = size
      }
      let align = @parser.packed_align(decl.pack, self.type_align(field.ty))
      if align > max_align {
        max_align = align
      }
      continue
    }
    let size = self.type_size(field.ty)
    if size > max_size {
      max_size = size
    }
    let align = @parser.packed_align(decl.pack, self.type_align(field.ty))
    if align > max_align {
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
    align: max_align,
    is_union: true,
    pack: decl.pack,
  }
}

///|
fn Program::ensure_layout(self : Program, name : String) -> Unit {
  if self.layouts.contains(name) {
    return
  }
  if !self.aggregates.contains(name) {
    self.layouts[name] = {
      fields: [],
      size: 8,
      align: 8,
      is_union: false,
      pack: None,
    }
    return
  }
  let decl = self.aggregates[name]
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
/// Looks up the layout of a named field of a struct or union type.
///
/// The aggregate layout is computed on demand for `self.target`. Returns
/// `Some(layout)` describing the field's offset, size, type, and any bit-field
/// placement, or `None` when `ty` is not an aggregate or has no such field.
///
/// Parameters:
///
/// - `ty`: the struct or union type to inspect (wrappers are unwrapped).
/// - `field`: the field name to look up.
///
/// # Example
///
/// ```moonbit check
/// test {
///   let program = @mir.lower(
///     @parser.parse("struct P { int x; int y; }; int main(void) { return 0; }"),
///     @target.Target::default(),
///   )
///   let y = program.field_layout(Struct("P"), "y").unwrap()
///   inspect(y.offset, content="4")
///   inspect(program.field_layout(Struct("P"), "z") is None, content="true")
/// }
/// ```
pub fn Program::field_layout(
  self : Program,
  ty : @ctype.Type,
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
/// Computes the byte offset of a nested member or element path within a type.
///
/// This is the layout engine behind `__builtin_offsetof`. The `path` walks the
/// type one designator at a time: `OffsetField(name)` descends into a struct or
/// union field, and `OffsetIndex(i)` steps `i` elements into an array. Returns
/// `Some(offset)` when every designator resolves, or `None` if a field is
/// missing or a designator does not match the current type.
///
/// Parameters:
///
/// - `ty`: the type the path starts from.
/// - `path`: the sequence of field and index designators to follow.
///
/// # Example
///
/// ```moonbit check
/// test {
///   let program = @mir.lower(
///     @parser.parse(
///       "struct P { int x; int arr[4]; }; int main(void) { return 0; }",
///     ),
///     @target.Target::default(),
///   )
///   // offsetof(struct P, arr[2]) == 4 (x) + 2 * sizeof(int)
///   let path = [@ctype.OffsetField("arr"), OffsetIndex(2L)]
///   inspect(program.offset_of_path(Struct("P"), path).unwrap(), content="12")
/// }
/// ```
pub fn Program::offset_of_path(
  self : Program,
  ty : @ctype.Type,
  path : Array[@ctype.OffsetDesignator],
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
fn MirModule::core_type(self : MirModule, ty : @ctype.Type) -> @ctype.Type {
  ignore(self)
  ty.core_type()
}

///|
fn MirModule::offset_array_element(
  self : MirModule,
  ty : @ctype.Type,
) -> @ctype.Type? {
  ignore(self)
  ty.array_element()
}

///|
fn MirModule::aggregate_layout_by_name(
  self : MirModule,
  name : String,
) -> AggregateLayout {
  match self.layouts.get(name) {
    Some(layout) => layout
    None => { fields: [], size: 8, align: 8, is_union: false, pack: None }
  }
}

///|
/// Returns the size in bytes of a C type under this module's target ABI.
///
/// The parser-free counterpart of `Program::type_size`: it resolves aggregates
/// through the layouts carried by the module, so the backend can size types
/// without the parser AST.
pub fn MirModule::type_size(self : MirModule, ty : @ctype.Type) -> Int {
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
/// Returns the alignment in bytes of a C type under this module's target ABI.
///
/// The parser-free counterpart of `Program::type_align`.
pub fn MirModule::type_align(self : MirModule, ty : @ctype.Type) -> Int {
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
/// Looks up the layout of a named struct or union field in this module.
///
/// The parser-free counterpart of `Program::field_layout`. Returns
/// `Some(layout)` with the field's offset, size, type, and bit-field placement,
/// or `None` when `ty` is not an aggregate or has no such field.
pub fn MirModule::field_layout(
  self : MirModule,
  ty : @ctype.Type,
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
/// Computes the byte offset of a nested member or element path in this module.
///
/// The parser-free counterpart of `Program::offset_of_path`, implementing
/// `__builtin_offsetof`. Returns `Some(offset)` when every `OffsetField` /
/// `OffsetIndex` designator resolves, or `None` otherwise.
pub fn MirModule::offset_of_path(
  self : MirModule,
  ty : @ctype.Type,
  path : Array[@ctype.OffsetDesignator],
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
/// Returns the `__builtin_object_size` fact for a whole object of type `ty`.
///
/// The fact records both the whole-object size and the size of the current
/// subobject; for a top-level object both equal `type_size(ty)`. It seeds the
/// path-sensitive query `object_size_path_fact`.
pub fn MirModule::object_size_fact_for_type(
  self : MirModule,
  ty : @ctype.Type,
) -> @ctype.ObjectSizeFact {
  let size = self.type_size(ty)
  { whole: size, subobject: size }
}

///|
/// Computes the `__builtin_object_size` fact at the end of a member/element path.
///
/// Starting from a whole object of type `ty`, this walks `path` one designator
/// at a time, narrowing the whole/subobject sizes as it descends into fields and
/// array elements. The result lets the compiler answer
/// `__builtin_object_size(&obj.field, type)` with the remaining bytes from that
/// subobject. Returns `None` if a designator does not resolve.
pub fn MirModule::object_size_path_fact(
  self : MirModule,
  ty : @ctype.Type,
  path : Array[@ctype.OffsetDesignator],
) -> @ctype.ObjectSizeFact? {
  let mut current_ty = ty
  let mut fact = self.object_size_fact_for_type(ty)
  for designator in path {
    match designator {
      OffsetField(field) =>
        match self.field_layout(current_ty, field) {
          Some(layout) => {
            fact = match
              fact.member_field(layout.offset, self.type_size(layout.ty)) {
              Some(member_fact) => member_fact
              None => return None
            }
            current_ty = layout.ty
          }
          None => return None
        }
      OffsetIndex(index) =>
        match self.core_type(current_ty) {
          Array(elem, n) => {
            fact = match fact.array_element(n, self.type_size(elem), index) {
              Some(element_fact) => element_fact
              None => return None
            }
            current_ty = elem
          }
          _ => return None
        }
    }
  }
  Some(fact)
}

///|
fn Program::global_expr_type(
  self : Program,
  expr : @parser.Expr,
) -> @ctype.Type {
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
    String(value) => Array(SChar, @ctype.string_literal_array_length(value))
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
) -> @ctype.Type? {
  let arg_types : Array[@ctype.Type] = []
  for arg in args {
    arg_types.push(self.expr_type(arg, scope))
  }
  let choose_cond = match @ctype.builtin_return_condition_arg_index(name) {
    Some(index) =>
      if index < args.length() {
        self.fold_const(args[index], scope)
      } else {
        None
      }
    None => None
  }
  @ctype.builtin_return_type(name, arg_types, choose_cond)
}

///|
fn Program::expr_type(
  self : Program,
  expr : @parser.Expr,
  scope : Scope,
) -> @ctype.Type {
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
      let force_wide_shift = if op == "<<" || op == ">>" {
        match (lhs, rhs) {
          (Number(_), Number(shift)) => shift >= 32L
          _ => false
        }
      } else {
        false
      }
      @ctype.binary_expr_result_type(
        op,
        lhs_ty,
        rhs_ty,
        force_wide_shift,
        self.target is DarwinArm64,
      )
    }
    Unary("-", operand) | Unary("+", operand) =>
      self.unary_numeric_result_type(self.expr_type(operand, scope))
    Unary("!", _) => SInt
    Unary("~", operand) => self.expr_type(operand, scope).integer_promote()
    Unary(_, operand) => self.expr_type(operand, scope)
    Call(func, args) =>
      match func {
        Var(name) =>
          match self.builtin_return_type(name, args, scope) {
            Some(ty) => ty
            None => self.call_expr_return_type(func, scope)
          }
        _ => self.call_expr_return_type(func, scope)
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
fn Program::call_expr_return_type(
  self : Program,
  func : @parser.Expr,
  scope : Scope,
) -> @ctype.Type {
  match self.core_type(self.expr_type(func, scope)) {
    FuncPtr(ret, _, _) | Pointer(FuncPtr(ret, _, _)) => ret
    _ => SInt
  }
}

///|
fn Program::object_size_var_type(
  self : Program,
  name : String,
  scope : Scope,
) -> @ctype.Type? {
  if scope.locals.contains(name) {
    Some(scope.locals[name])
  } else if self.globals.contains(name) {
    Some(self.globals[name].ty)
  } else {
    None
  }
}

///|
fn Program::object_size_lvalue_type(
  self : Program,
  expr : @parser.Expr,
  scope : Scope,
) -> @ctype.Type? {
  match expr {
    Var(name) => self.object_size_var_type(name, scope)
    ArrayAccess(base, _) =>
      match self.object_size_lvalue_type(base, scope) {
        Some(base_ty) => self.pointer_element(base_ty)
        None => None
      }
    MemberAccess(obj, field) =>
      match self.object_size_lvalue_type(obj, scope) {
        Some(obj_ty) =>
          match self.field_layout(obj_ty, field) {
            Some(layout) => Some(layout.ty)
            None => None
          }
        None => None
      }
    _ => None
  }
}

///|
fn Program::object_size_var_fact(
  self : Program,
  name : String,
  scope : Scope,
) -> @ctype.ObjectSizeFact? {
  match self.object_size_var_type(name, scope) {
    Some(ty) => self.to_module().object_size_path_fact(ty, [])
    None => None
  }
}

///|
fn Program::object_size_lvalue_path(
  self : Program,
  expr : @parser.Expr,
  scope : Scope,
) -> (@ctype.Type, Array[@ctype.OffsetDesignator])? {
  match expr {
    Var(name) =>
      match self.object_size_var_type(name, scope) {
        Some(ty) => Some((ty, []))
        None => None
      }
    ArrayAccess(base, index) =>
      match self.fold_const(index, scope) {
        Some(raw_index) =>
          match self.object_size_lvalue_path(base, scope) {
            Some((root_ty, path)) => {
              path.push(OffsetIndex(raw_index))
              Some((root_ty, path))
            }
            None => None
          }
        None => None
      }
    MemberAccess(obj, field) =>
      match self.object_size_lvalue_path(obj, scope) {
        Some((root_ty, path)) => {
          path.push(OffsetField(field))
          Some((root_ty, path))
        }
        None => None
      }
    _ => None
  }
}

///|
fn Program::object_size_lvalue_fact(
  self : Program,
  expr : @parser.Expr,
  scope : Scope,
) -> @ctype.ObjectSizeFact? {
  match self.object_size_lvalue_path(expr, scope) {
    Some((root_ty, path)) =>
      self.to_module().object_size_path_fact(root_ty, path)
    None => None
  }
}

///|
fn Program::object_size_offset_expr_fact(
  self : Program,
  base : @parser.Expr,
  offset_expr : @parser.Expr,
  scope : Scope,
) -> @ctype.ObjectSizeFact? {
  match
    (
      self.object_size_expr_fact(base, scope),
      self.fold_const(offset_expr, scope),
      self.pointer_element(self.expr_type(base, scope)),
    ) {
    (Some(fact), Some(index), Some(elem)) =>
      if index < 0L {
        None
      } else {
        fact.subtract_offset(index.to_int() * self.type_size(elem))
      }
    _ => None
  }
}

///|
fn Program::object_size_expr_fact(
  self : Program,
  expr : @parser.Expr,
  scope : Scope,
) -> @ctype.ObjectSizeFact? {
  match expr {
    Cast(_, inner) => self.object_size_expr_fact(inner, scope)
    AddrOf(inner) => self.object_size_lvalue_fact(inner, scope)
    Binary("+", lhs, rhs) =>
      match self.object_size_offset_expr_fact(lhs, rhs, scope) {
        Some(fact) => Some(fact)
        None => self.object_size_offset_expr_fact(rhs, lhs, scope)
      }
    Var(name) =>
      match self.object_size_var_type(name, scope) {
        Some(ty) =>
          match self.core_type(ty) {
            Array(_, _) => self.object_size_var_fact(name, scope)
            _ => None
          }
        None => None
      }
    MemberAccess(_, _) =>
      match self.object_size_lvalue_type(expr, scope) {
        Some(ty) =>
          match self.core_type(ty) {
            Array(_, _) => self.object_size_lvalue_fact(expr, scope)
            _ => None
          }
        None => None
      }
    _ => None
  }
}

///|
fn Program::object_size_value(
  self : Program,
  expr : @parser.Expr,
  scope : Scope,
  mode : Int64,
) -> Int64 {
  match literal_string_arg(expr) {
    Some(literal) => return @ctype.string_literal_object_size(literal)
    None => ()
  }
  @ctype.object_size_fact_result(self.object_size_expr_fact(expr, scope), mode)
}

///|
fn Program::fold_scalar_builtin_const(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  scope : Scope,
) -> @ctype.IntegerConstant? {
  let arg0 = if args.length() > 0 {
    self.fold_const_int(args[0], scope)
  } else {
    None
  }
  let arg1 = if args.length() > 1 {
    self.fold_const_int(args[1], scope)
  } else {
    None
  }
  let first_ty = if args.length() > 0 {
    self.expr_type(args[0], scope)
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
fn Program::fold_float_builtin_int_const(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  scope : Scope,
) -> @ctype.IntegerConstant? {
  match @ctype.floating_builtin_compare_op(name) {
    Some(_) =>
      if args.length() >= 2 {
        match
          (
            self.fold_float_const(args[0], scope),
            self.fold_float_const(args[1], scope),
          ) {
          (Some(left), Some(right)) =>
            match @ctype.floating_builtin_compare(name, left, right) {
              Some(result) => Some(@ctype.integer_constant_bool(result))
              None => None
            }
          _ => None
        }
      } else {
        None
      }
    None =>
      match @ctype.floating_builtin_runtime_class_info(name) {
        Some(_) =>
          if args.length() >= 1 {
            match self.fold_float_const(args[0], scope) {
              Some(value) =>
                match @ctype.floating_builtin_classify(name, value) {
                  Some(result) => Some(@ctype.integer_constant_bool(result))
                  None => None
                }
              None => None
            }
          } else {
            None
          }
        None => None
      }
  }
}

///|
fn Program::fold_const_int(
  self : Program,
  expr : @parser.Expr,
  scope : Scope,
) -> @ctype.IntegerConstant? {
  match expr {
    Number(n) =>
      Some(@ctype.integer_constant(n, @ctype.integer_constant_token_type(n)))
    Binary("+", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => @ctype.integer_constant_binary_arith("+", x, y)
        _ => None
      }
    Binary("-", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => @ctype.integer_constant_binary_arith("-", x, y)
        _ => None
      }
    Binary("*", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => @ctype.integer_constant_binary_arith("*", x, y)
        _ => None
      }
    Binary("/", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => @ctype.integer_constant_divide("/", x, y)
        _ => None
      }
    Binary("%", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => @ctype.integer_constant_divide("%", x, y)
        _ => None
      }
    Binary("|", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => @ctype.integer_constant_binary_arith("|", x, y)
        _ => None
      }
    Binary("&", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => @ctype.integer_constant_binary_arith("&", x, y)
        _ => None
      }
    Binary("^", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => @ctype.integer_constant_binary_arith("^", x, y)
        _ => None
      }
    Binary("<<", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => @ctype.integer_constant_shift("<<", x, y)
        _ => None
      }
    Binary(">>", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => @ctype.integer_constant_shift(">>", x, y)
        _ => None
      }
    Binary("==", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) =>
          Some(
            @ctype.integer_constant_bool(
              @ctype.integer_constant_equal_compare(x, y),
            ),
          )
        _ => None
      }
    Binary("!=", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) =>
          Some(
            @ctype.integer_constant_bool(
              !@ctype.integer_constant_equal_compare(x, y),
            ),
          )
        _ => None
      }
    Binary("<", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) =>
          Some(
            @ctype.integer_constant_bool(
              @ctype.integer_constant_rel_compare("<", x, y),
            ),
          )
        _ => None
      }
    Binary(">", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) =>
          Some(
            @ctype.integer_constant_bool(
              @ctype.integer_constant_rel_compare(">", x, y),
            ),
          )
        _ => None
      }
    Binary("<=", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) =>
          Some(
            @ctype.integer_constant_bool(
              @ctype.integer_constant_rel_compare("<=", x, y),
            ),
          )
        _ => None
      }
    Binary(">=", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) =>
          Some(
            @ctype.integer_constant_bool(
              @ctype.integer_constant_rel_compare(">=", x, y),
            ),
          )
        _ => None
      }
    Binary("&&", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => @ctype.integer_constant_logical("&&", x, y)
        _ => None
      }
    Binary("||", a, b) =>
      match (self.fold_const_int(a, scope), self.fold_const_int(b, scope)) {
        (Some(x), Some(y)) => @ctype.integer_constant_logical("||", x, y)
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
        Some(value) => @ctype.integer_constant_unary("-", value)
        None => None
      }
    Unary("+", e) =>
      match self.fold_const_int(e, scope) {
        Some(value) => @ctype.integer_constant_unary("+", value)
        None => None
      }
    Unary("~", e) =>
      match self.fold_const_int(e, scope) {
        Some(value) => @ctype.integer_constant_unary("~", value)
        None => None
      }
    Unary("!", e) =>
      match self.fold_const_int(e, scope) {
        Some(value) => @ctype.integer_constant_unary("!", value)
        None => None
      }
    Cast(ty, e) =>
      match self.core_type(ty).const_int_width() {
        Some(_) =>
          match self.fold_const_int(e, scope) {
            Some(value) => Some(value.cast(self.core_type(ty)))
            None =>
              if self.is_floating_const_type(self.expr_type(e, scope)) {
                match self.fold_float_const(e, scope) {
                  Some(value) =>
                    Some(@ctype.integer_constant_from_floating(value, ty))
                  None => None
                }
              } else {
                None
              }
          }
        None => None
      }
    DesignatedField(_, e) | DesignatedIndex(_, e) | DesignatedRange(_, _, e) =>
      self.fold_const_int(e, scope)
    Sizeof(ty) =>
      Some(@ctype.integer_constant(self.type_size(ty).to_int64(), ULong))
    SizeofExpr(e) =>
      Some(
        @ctype.integer_constant(
          match e {
            String(value) => @ctype.string_literal_object_size(value)
            _ => self.type_size(self.expr_type(e, scope)).to_int64()
          },
          ULong,
        ),
      )
    Alignof(ty) =>
      Some(@ctype.integer_constant(self.type_align(ty).to_int64(), ULong))
    AlignofExpr(e) =>
      Some(
        @ctype.integer_constant(
          match e {
            String(value) =>
              self
              .type_align(
                Array(SChar, @ctype.string_literal_array_length(value)),
              )
              .to_int64()
            _ => self.type_align(self.expr_type(e, scope)).to_int64()
          },
          ULong,
        ),
      )
    OffsetOf(ty, path) =>
      match self.offset_of_path(ty, path) {
        Some(offset) => Some(@ctype.integer_constant(offset.to_int64(), ULong))
        None => None
      }
    Call(Var(name), args) =>
      match @ctype.builtin_object_size_call_info(name) {
        Some(_) => {
          let mode = if args.length() > 1 {
            match self.fold_const(args[1], scope) {
              Some(value) => value
              None => return None
            }
          } else {
            0L
          }
          let value = if args.length() > 0 {
            self.object_size_value(args[0], scope, mode)
          } else {
            @ctype.object_size_unknown(mode)
          }
          Some(@ctype.integer_constant(value, ULong))
        }
        None =>
          match @ctype.builtin_constant_query_call_info(name) {
            Some(kind) =>
              match
                @ctype.builtin_constant_query_result(
                  kind,
                  args.length() > 0 &&
                  self.fold_const(args[0], scope) is Some(_),
                ) {
                Some(value) => Some(@ctype.integer_constant(value, SInt))
                None => None
              }
            None =>
              match self.fold_float_builtin_int_const(name, args, scope) {
                Some(value) => Some(value)
                None => self.fold_scalar_builtin_const(name, args, scope)
              }
          }
      }
    _ => None
  }
}

///|
fn Program::fold_const(
  self : Program,
  expr : @parser.Expr,
  scope : Scope,
) -> Int64? {
  match self.fold_const_int(expr, scope) {
    Some(value) => Some(value.bits)
    None => None
  }
}

///|
fn Program::fold_float_builtin_const_value(
  self : Program,
  name : String,
  args : Array[@parser.Expr],
  scope : Scope,
) -> Double? {
  let arg0 = if args.length() > 0 {
    self.fold_float_const(args[0], scope)
  } else {
    None
  }
  let arg1 = if args.length() > 1 {
    self.fold_float_const(args[1], scope)
  } else {
    None
  }
  @ctype.floating_builtin_constant_from_folded_args(name, arg0, arg1)
}

///|
fn Program::fold_float_const(
  self : Program,
  expr : @parser.Expr,
  scope : Scope,
) -> Double? {
  let expr_ty = self.expr_type(expr, scope)
  if !self.is_floating_const_type(expr_ty) {
    match expr {
      Cast(_, e) if self.is_floating_const_type(self.expr_type(e, scope)) =>
        match self.fold_float_const(e, scope) {
          Some(value) =>
            Some(
              @ctype.floating_constant_from_integer_bits(
                @ctype.floating_constant_to_integer_bits(value),
              ),
            )
          None => None
        }
      _ =>
        match self.fold_const(expr, scope) {
          Some(value) => Some(@ctype.floating_constant_from_integer_bits(value))
          None => None
        }
    }
  } else {
    match expr {
      FloatLiteral(value) => Some(value)
      Number(value) => Some(@ctype.floating_constant_from_integer_bits(value))
      Binary("+", a, b) =>
        match
          (self.fold_float_const(a, scope), self.fold_float_const(b, scope)) {
          (Some(x), Some(y)) => @ctype.floating_constant_binary_arith("+", x, y)
          _ => None
        }
      Binary("-", a, b) =>
        match
          (self.fold_float_const(a, scope), self.fold_float_const(b, scope)) {
          (Some(x), Some(y)) => @ctype.floating_constant_binary_arith("-", x, y)
          _ => None
        }
      Binary("*", a, b) =>
        match
          (self.fold_float_const(a, scope), self.fold_float_const(b, scope)) {
          (Some(x), Some(y)) => @ctype.floating_constant_binary_arith("*", x, y)
          _ => None
        }
      Binary("/", a, b) =>
        match
          (self.fold_float_const(a, scope), self.fold_float_const(b, scope)) {
          (Some(x), Some(y)) => @ctype.floating_constant_binary_arith("/", x, y)
          _ => None
        }
      Unary("-", e) =>
        match self.fold_float_const(e, scope) {
          Some(value) => @ctype.floating_constant_unary("-", value)
          None => None
        }
      Unary("+", e) =>
        match self.fold_float_const(e, scope) {
          Some(value) => @ctype.floating_constant_unary("+", value)
          None => None
        }
      Ternary(cond, a, b) =>
        match self.fold_const(cond, scope) {
          Some(0L) => self.fold_float_const(b, scope)
          Some(_) => self.fold_float_const(a, scope)
          None => None
        }
      Cast(_, e)
      | DesignatedField(_, e)
      | DesignatedIndex(_, e)
      | DesignatedRange(_, _, e) => self.fold_float_const(e, scope)
      Call(Var(name), args) =>
        self.fold_float_builtin_const_value(name, args, scope)
      _ => None
    }
  }
}
