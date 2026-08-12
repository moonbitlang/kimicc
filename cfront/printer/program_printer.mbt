///|
/// Renders a whole translation unit as C source.
///
/// Entries print in `items` order -- the order the source declared them --
/// which is what makes the output acceptable to another compiler: C requires
/// declaration before use at file scope, and the grouped arrays alone would
/// put every global ahead of every function. A hand-built program may leave
/// `items` empty and print in grouped order instead: aggregates, then
/// globals, then functions. Parsing the result yields the same AST, which is
/// the property meta-programming depends on -- build or transform a
/// `Program`, print it, and hand the text to another compiler.
///
/// ```mbt check
/// test {
///   let program = @parser.parse("int answer(void) { return 42; }")
///   inspect(
///     @printer.print_program(program),
///     content=(
///       #|int answer(void) {
///       #|  return 42;
///       #|}
///       #|
///       #|
///     ),
///   )
/// }
/// ```
pub fn print_program(program : @parser.Program) -> String {
  let buf = StringBuilder::new()
  let anon = member_inline_defs(program)
  let inlined : Map[String, Bool] = Map([])
  // Anonymous definitions whose synthesized tag is referenced from outside
  // the defining member -- a second declarator in `} a, b;`, a `typeof`
  // recovery, a global, a signature -- must spell the tag out; everything
  // else anonymous prints tagless, the way it was written. The count
  // excludes the defining member's own mention: one named field carrying the
  // tag is the definition site, not a reference to it.
  let carried = member_base_tags(program)
  let referenced = referenced_tags(program)
  let anon_named : Map[String, Bool] = Map([])
  for tag, entry in anon {
    let (definition, _) = entry
    if definition.is_anonymous &&
      external_tag_references(referenced, carried, tag) > 0 {
      anon_named[tag] = true
    }
  }
  // Every tag, declared at file scope before anything mentions it. The source
  // did this with its typedefs -- `typedef struct JSContext JSContext;` both
  // names the type and declares the tag -- and the AST records no typedefs, so
  // without these a tag first mentioned inside a prototype's parameter list
  // would have prototype scope and be a different type from the definition.
  let mut forward_any = false
  let defined : Map[String, Bool] = Map([])
  for decl in program.structs {
    defined[decl.name] = true
    // Every tag that appears anywhere in the output is declared up front,
    // including tags whose definitions print inside a parent -- C gives a
    // tag in a member list the enclosing scope. Only a tag that appears
    // nowhere is suppressed: a synthesized anonymous tag consumed by
    // anonymous members and never spelled by a named member, a global, or a
    // signature. A top-level definition is always declared, whatever its
    // spelling -- source-written tags may match the synthetic pattern.
    // A name used as the other kind somewhere -- `struct X *` in a prototype
    // over a file-scope `union X` -- is a prototype-scope tag in the source,
    // and a file-scope forward here would make every such mention a kind
    // mismatch. Item order already places the definition where the source
    // had it, so the forward is simply omitted.
    let kind_conflicted = match referenced.get(decl.name) {
      Some((as_struct, as_union, _)) =>
        if decl.is_union {
          as_struct
        } else {
          as_union
        }
      None => false
    }
    // Suppression is exactly "this definition prints tagless": anonymous,
    // consumed by a member site, and unreferenced from outside it. A hidden
    // definition -- no member site -- prints tagged at top level even when
    // anonymous, so its forward declaration appears here on the first print,
    // the same as the reparse of that tagged text would produce.
    let suppressed = kind_conflicted ||
      (
        anon.contains(decl.name) &&
        decl.is_anonymous &&
        external_tag_references(referenced, carried, decl.name) == 0
      )
    if !suppressed {
      buf.write_string(if decl.is_union { "union " } else { "struct " })
      buf.write_string(decl.name)
      buf.write_string(";\n")
      forward_any = true
    }
  }
  // Tags the program mentions but never defines -- opaque types trafficked by
  // pointer -- still need their file-scope declaration.
  for tag, kinds in referenced {
    let (as_struct, as_union, _) = kinds
    // A name referenced as both kinds without a definition lived in two
    // scopes in the source; neither can be declared at file scope without
    // breaking the other, so both stay prototype-scoped.
    if !defined.contains(tag) && as_struct != as_union {
      buf.write_string(if as_union { "union " } else { "struct " })
      buf.write_string(tag)
      buf.write_string(";\n")
      forward_any = true
    }
  }
  if forward_any {
    buf.write_string("\n")
  }
  // A definition created inside a member list that no member's type carries
  // -- `int a[sizeof(struct I { int x; })]` defines I inside an expression --
  // has no member site to print at. It prints just before the aggregate it
  // was created inside: early enough for anything after to reference it,
  // late enough that its own field types -- defined above it in the source
  // -- are already complete.
  // Everything below the item-held ceiling that no member claimed as its
  // definition site prints at its creation position.
  let hidden : Array[(Int, @parser.StructDecl)] = []
  let mut max_top_index = -1
  for item in program.items {
    match item {
      Aggregate(index) => if index > max_top_index { max_top_index = index }
      _ => ()
    }
  }
  for index, decl in program.structs {
    let in_body = if program.items.length() > 0 {
      index < max_top_index && !item_held(program, index)
    } else {
      false
    }
    if in_body && !anon.contains(decl.name) {
      hidden.push((index, decl))
    }
  }
  let mut next_hidden = 0
  if program.items.length() > 0 {
    let seen_structs : Map[Int, Bool] = Map([])
    let seen_globals : Map[Int, Bool] = Map([])
    let seen_decls : Map[Int, Bool] = Map([])
    for item in program.items {
      match item {
        // Items index the grouped arrays rather than carrying copies, so a
        // transformation that replaces `program.structs[i]` prints its
        // replacement. A deletion shortens the array and leaves the tape one
        // entry long; skipping out-of-range indices makes a tail deletion
        // exact, and a mid-array deletion prints every survivor once, in
        // order, with later same-kind entries one tape slot earlier --
        // delete the items entry too when exact placement matters.
        Aggregate(index) if index >= program.structs.length() => ()
        Global(index) if index >= program.globals.length() => ()
        Func(index) if index >= program.decls.length() => ()
        Aggregate(index) => {
          while next_hidden < hidden.length() && hidden[next_hidden].0 < index {
            let (hidden_index, hidden_decl) = hidden[next_hidden]
            seen_structs[hidden_index] = true
            write_struct_decl(
              buf, hidden_decl, hidden_index, anon, anon_named, inlined,
            )
            next_hidden += 1
          }
          seen_structs[index] = true
          write_struct_decl(
            buf,
            program.structs[index],
            index,
            anon,
            anon_named,
            inlined,
          )
        }
        Global(index) => {
          seen_globals[index] = true
          write_global_decl(buf, program.globals[index])
        }
        Func(index) => {
          seen_decls[index] = true
          write_func_decl(buf, program.decls[index])
        }
      }
    }
    while next_hidden < hidden.length() {
      let (hidden_index, hidden_decl) = hidden[next_hidden]
      seen_structs[hidden_index] = true
      write_struct_decl(
        buf, hidden_decl, hidden_index, anon, anon_named, inlined,
      )
      next_hidden += 1
    }
    // Entries appended to the grouped arrays without an items entry -- the
    // simplest way to add a declaration to a parsed program -- print at the
    // end, where they may reference everything above. A transformation that
    // needs an earlier position appends to `items` too.
    for index, decl in program.structs {
      if !seen_structs.contains(index) && !anon.contains(decl.name) {
        write_struct_decl(buf, decl, index, anon, anon_named, inlined)
      }
    }
    for index, global in program.globals {
      if !seen_globals.contains(index) {
        write_global_decl(buf, global)
      }
    }
    for index, decl in program.decls {
      if !seen_decls.contains(index) {
        write_func_decl(buf, decl)
      }
    }
  } else {
    while next_hidden < hidden.length() {
      let (hidden_index, hidden_decl) = hidden[next_hidden]
      write_struct_decl(
        buf, hidden_decl, hidden_index, anon, anon_named, inlined,
      )
      next_hidden += 1
    }
    for index, decl in program.structs {
      if !anon.contains(decl.name) {
        write_struct_decl(buf, decl, index, anon, anon_named, inlined)
      }
    }
    for global in program.globals {
      write_global_decl(buf, global)
    }
    for decl in program.decls {
      write_func_decl(buf, decl)
    }
  }
  buf.to_string()
}

///|
/// The aggregates that print inside their parent rather than at top level,
/// mapped by tag.
///
/// A definition written in another aggregate's member list has no `items`
/// entry -- the parser records it only in the grouped array -- and that
/// absence is the signal here: whatever was written inline prints inline.
/// That covers the anonymous member, whose inline untagged definition is what
/// C11 requires for its members to reach through, the named member of a
/// tagless type (`struct { ... } func;`), and a named nested definition
/// (`struct Inner { ... } in_;`), whose tag belongs to the enclosing scope in
/// C and stays referenceable.
///
/// Printing these inline is also what keeps the grouped array's creation
/// order a fixed point: hoisted to the top they would reparse ahead of their
/// parent, while the members written around them reparse inside it.
///
/// A hand-built program with an empty `items` gets the narrower classic rule:
/// aggregates consumed by an empty-named member are inline, everything else
/// prints at top level.
fn member_inline_defs(
  program : @parser.Program,
) -> Map[String, (@parser.StructDecl, Int)] {
  let inline : Map[String, (@parser.StructDecl, Int)] = Map([])
  if program.items.length() > 0 {
    let top : Map[Int, Bool] = Map([])
    let mut max_top = -1
    for item in program.items {
      match item {
        Aggregate(index) => {
          top[index] = true
          if index > max_top {
            max_top = index
          }
        }
        _ => ()
      }
    }
    // A definition written inside a member list always sits below its
    // parent's index, and the parent holds an item -- so anything above every
    // item-held index was appended after parsing and is a top-level entry,
    // not a member definition.
    let candidates : Map[String, (@parser.StructDecl, Int)] = Map([])
    for index, decl in program.structs {
      if !top.contains(index) && index < max_top {
        candidates[decl.name] = (decl, index)
      }
    }
    // A field carrying a candidate's tag is its definition site only when the
    // claims run in creation order: definitions written at members are
    // created in member order, so a candidate whose index falls below an
    // already-claimed one was created earlier than the field that now
    // mentions it -- inside an expression -- and that mention is a
    // reference, not the definition. Unclaimed candidates print at their
    // creation position instead.
    let claimed_tags : Map[String, Bool] = Map([])
    for parent_index, parent in program.structs {
      // A definition belongs to the aggregate it was created inside: its
      // index falls between the previous top-level entry and this parent.
      // A later parent whose field mentions the tag is referencing it, not
      // defining it, and must not pull the definition forward past whatever
      // sits between.
      let mut span_start = -1
      for index in top.keys() {
        if index < parent_index && index > span_start {
          span_start = index
        }
      }
      let mut last_claimed = span_start
      for field in parent.fields {
        match declaration_base_tag(field.ty) {
          Some(tag) =>
            if !claimed_tags.contains(tag) {
              match candidates.get(tag) {
                Some((definition, def_index)) =>
                  if def_index < parent_index && def_index > last_claimed {
                    claimed_tags[tag] = true
                    last_claimed = def_index
                    inline[tag] = (definition, def_index)
                  }
                None => ()
              }
            }
          None => ()
        }
      }
    }
    return inline
  }
  let defs : Map[String, (@parser.StructDecl, Int)] = Map([])
  for index, decl in program.structs {
    defs[decl.name] = (decl, index)
  }
  for decl in program.structs {
    for field in decl.fields {
      if field.name == "" {
        match field.ty.core_type() {
          Struct(tag) | Union(tag) =>
            match defs.get(tag) {
              Some(entry) => {
                let (definition, _) = entry
                if definition.is_anonymous {
                  inline[tag] = entry
                }
              }
              None => ()
            }
          _ => ()
        }
      }
    }
  }
  inline
}

///|
/// Writes an aggregate declaration, including whatever spelling reproduces its
/// field-alignment cap.
///
/// `pack` is layout, not decoration: dropping it would print C that compiles to
/// a different ABI. `Some(1)` is the GNU `packed` attribute; any other cap needs
/// a `#pragma pack` pair around the declaration, which the parser reads back
/// positionally.
fn write_struct_decl(
  buf : StringBuilder,
  decl : @parser.StructDecl,
  decl_index : Int,
  anon : Map[String, (@parser.StructDecl, Int)],
  anon_named : Map[String, Bool],
  inlined : Map[String, Bool],
) -> Unit {
  let pragma_wrapped = match decl.pack {
    Some(cap) => cap != 1
    None => false
  }
  match decl.pack {
    Some(cap) =>
      if pragma_wrapped {
        buf.write_string("#pragma pack(push, ")
        buf.write_string(cap.to_string())
        buf.write_string(")\n")
      }
    None => ()
  }
  buf.write_string(if decl.is_union { "union " } else { "struct " })
  buf.write_string(decl.name)
  buf.write_string(" {\n")
  write_aggregate_fields(buf, decl, decl_index, 1, anon, anon_named, inlined)
  buf.write_string("}")
  if decl.pack is Some(1) {
    buf.write_string(" __attribute__((packed))")
  }
  buf.write_string(";\n")
  if pragma_wrapped {
    buf.write_string("#pragma pack(pop)\n")
  }
  buf.write_string("\n")
}

///|
/// Writes an aggregate's members at `indent` levels.
///
/// An anonymous member -- an empty-named field whose type is one of the
/// suppressed `__anon_` definitions -- is written as the untagged inline
/// definition C requires for its members to reach through, recursing for the
/// anonymous members it may itself contain. Every other field is an ordinary
/// declaration.
fn write_aggregate_fields(
  buf : StringBuilder,
  decl : @parser.StructDecl,
  decl_index : Int,
  indent : Int,
  anon : Map[String, (@parser.StructDecl, Int)],
  anon_named : Map[String, Bool],
  inlined : Map[String, Bool],
) -> Unit {
  let pad = "  ".repeat(indent)
  for field in decl.fields {
    // One definition, printed once, at its defining member. `struct I { int
    // x; } a, b;` gives two fields the same base tag and only the first
    // prints the body. A field that merely *references* the tag from an
    // earlier aggregate -- possible after a forward declaration -- must not
    // capture the definition: the definition was created during its own
    // parent's body, so its creation index is above any earlier referrer's,
    // and inlining it there would also drag it under that parent's packing
    // context.
    let inline_def = match declaration_base_tag(field.ty) {
      Some(tag) =>
        if inlined.contains(tag) {
          None
        } else {
          match anon.get(tag) {
            Some((definition, def_index)) =>
              if def_index < decl_index {
                Some((definition, def_index))
              } else {
                None
              }
            None => None
          }
        }
      None => None
    }
    match inline_def {
      Some((nested, nested_index)) => {
        inlined[nested.name] = true
        // A non-unit packing cap has no attribute spelling, so the member is
        // wrapped in the pragma pair; clang applies `#pragma pack` inside a
        // member list to the members that follow it, and the parser reads
        // pragmas positionally from the raw text.
        let pragma_wrapped = match nested.pack {
          Some(cap) => cap != 1
          None => false
        }
        if pragma_wrapped {
          buf.write_string(pad)
          buf.write_string("#pragma pack(push, ")
          buf.write_string(nested.pack.unwrap().to_string())
          buf.write_string(")\n")
        }
        buf.write_string(pad)
        // The specifier half carries the wrappers the member's type had
        // outside the definition -- `_Alignas(16)`, `_Atomic` -- and ends
        // with the tag reference the inline definition replaces.
        let (specifier, declarator) = split_declaration(field.ty, field.name)
        let tag_reference = (if nested.is_union { "union " } else { "struct " }) +
          nested.name
        if specifier.has_suffix(tag_reference) {
          buf.write_string(
            specifier[0:specifier.length() - tag_reference.length()].to_owned(),
          )
        }
        buf.write_string(if nested.is_union { "union" } else { "struct" })
        // An anonymous definition prints tagless, the way it was written:
        // C11 requires taglessness for an anonymous member's members to
        // reach through, and on a named member it keeps `is_anonymous` a
        // reparse fixed point. The synthesized tag is spelled out only when
        // something else references it -- `typeof` can recover a member's
        // type into another declaration -- where a tagless definition would
        // leave that reference permanently incomplete. A written tag always
        // stays, whatever its spelling.
        if !nested.is_anonymous || anon_named.contains(nested.name) {
          buf.write_string(" ")
          buf.write_string(nested.name)
        }
        buf.write_string(" {\n")
        write_aggregate_fields(
          buf,
          nested,
          nested_index,
          indent + 1,
          anon,
          anon_named,
          inlined,
        )
        buf.write_string(pad)
        buf.write_string("}")
        if nested.pack is Some(1) {
          buf.write_string(" __attribute__((packed))")
        }
        // The declarator half carries whatever wraps the member's name:
        // `struct { ... } *p` or `struct { ... } arr[4]`.
        if declarator != "" {
          buf.write_string(" ")
          buf.write_string(declarator)
        }
        buf.write_string(";\n")
        if pragma_wrapped {
          buf.write_string(pad)
          buf.write_string("#pragma pack(pop)\n")
        }
      }
      None => {
        buf.write_string(pad)
        buf.write_string(print_declaration(field.ty, field.name))
        match field.bit_width {
          Some(width) => {
            buf.write_string(" : ")
            buf.write_string(width.to_string())
          }
          None => ()
        }
        buf.write_string(";\n")
      }
    }
  }
}

///|
/// Writes a global variable declaration or definition.
fn write_global_decl(buf : StringBuilder, decl : @parser.GlobalDecl) -> Unit {
  write_storage_and_attributes(
    buf,
    is_static=decl.is_static,
    is_extern=decl.is_extern,
    is_inline=false,
  )
  buf.write_string(print_declaration(decl.ty, decl.name))
  match decl.init {
    Some(Scalar(value)) => {
      buf.write_string(" = ")
      buf.write_string(print_expr(value))
    }
    Some(Array(elements)) => {
      buf.write_string(" = { ")
      buf.write_string(print_arguments(elements))
      buf.write_string(" }")
    }
    None => ()
  }
  write_symbol_attributes(
    buf,
    is_weak=decl.is_weak,
    visibility=decl.visibility,
    symbol_alias=decl.symbol_alias,
    section=decl.section,
    is_constructor=false,
    is_destructor=false,
  )
  buf.write_string(";\n\n")
}

///|
/// Writes a function declaration or definition.
fn write_func_decl(buf : StringBuilder, decl : @parser.FuncDecl) -> Unit {
  write_storage_and_attributes(
    buf,
    is_static=decl.is_static,
    is_extern=false,
    is_inline=decl.is_inline,
  )
  let signature = decl.name +
    "(" +
    declared_parameter_list(decl.params, decl.variadic) +
    ")"
  buf.write_string(print_declaration(decl.ret, signature))
  write_symbol_attributes(
    buf,
    is_weak=decl.is_weak,
    visibility=decl.visibility,
    symbol_alias=decl.symbol_alias,
    section=decl.section,
    is_constructor=decl.is_constructor,
    is_destructor=decl.is_destructor,
  )
  match decl.body {
    Some(Compound(stmts)) => {
      buf.write_string(" ")
      write_block(buf, stmts, 0)
      buf.write_string("\n\n")
    }
    Some(other) => {
      buf.write_string(" {\n")
      buf.write_string(print_stmt(other))
      buf.write_string("\n}\n\n")
    }
    None => buf.write_string(";\n\n")
  }
}

///|
/// Writes leading storage-class keywords.
fn write_storage_and_attributes(
  buf : StringBuilder,
  is_static~ : Bool,
  is_extern~ : Bool,
  is_inline~ : Bool,
) -> Unit {
  if is_static {
    buf.write_string("static ")
  }
  if is_extern {
    buf.write_string("extern ")
  }
  if is_inline {
    buf.write_string("inline ")
  }
}

///|
/// Writes the trailing GNU attributes carried by a declaration.
fn write_symbol_attributes(
  buf : StringBuilder,
  is_weak~ : Bool,
  visibility~ : String?,
  symbol_alias~ : String?,
  section~ : String?,
  is_constructor~ : Bool,
  is_destructor~ : Bool,
) -> Unit {
  let parts = []
  if is_weak {
    parts.push("weak")
  }
  match visibility {
    Some(value) => parts.push("visibility(\"" + value + "\")")
    None => ()
  }
  match symbol_alias {
    Some(value) => parts.push("alias(\"" + value + "\")")
    None => ()
  }
  match section {
    Some(value) => parts.push("section(\"" + value + "\")")
    None => ()
  }
  if is_constructor {
    parts.push("constructor")
  }
  if is_destructor {
    parts.push("destructor")
  }
  if parts.length() > 0 {
    buf.write_string(" __attribute__((")
    buf.write_string(parts.join(", "))
    buf.write_string("))")
  }
}

///|
/// Collects every struct and union tag the program mentions in a type
/// position, mapped to whether it is a union.
///
/// The definitions carry most tags, but a program may traffic in pointers to
/// a tag it never defines -- sqlite's public API does this deliberately, with
/// `sqlite3_stmt` defined only under its internal name. Those tags still need
/// a file-scope declaration ahead of the first prototype that mentions them,
/// so the collector walks the types reachable from declarations, statements,
/// and the expressions that embed a type: casts, `sizeof`, `_Alignof`,
/// compound literals, `va_arg`, and `offsetof`.
fn referenced_tags(program : @parser.Program) -> Map[String, (Bool, Bool, Int)] {
  // Per name: (referenced as a struct, referenced as a union, mention
  // count). Both kind flags can be true -- the same spelling can name a
  // file-scope tag of one kind and a prototype-scope tag of the other. The
  // count includes every type-position mention anywhere, including the
  // defining member's own; consumers that need external references subtract
  // the defining mention.
  let tags : Map[String, (Bool, Bool, Int)] = Map([])
  fn take(ty : @ctype.Type) -> Unit {
    match ty {
      Struct(name) => {
        let (_, as_union, count) = tags.get(name).unwrap_or((false, false, 0))
        tags[name] = (true, as_union, count + 1)
      }
      Union(name) => {
        let (as_struct, _, count) = tags.get(name).unwrap_or((false, false, 0))
        tags[name] = (as_struct, true, count + 1)
      }
      Pointer(inner) | Atomic(inner) | Aligned(inner, _) => take(inner)
      Array(inner, _) => take(inner)
      FuncPtr(ret, params, _) => {
        take(ret)
        for param in params {
          take(param)
        }
      }
      _ => ()
    }
  }
  fn take_expr(expr : @parser.Expr) -> Unit {
    match expr {
      Sizeof(ty) | Alignof(ty) => take(ty)
      Cast(ty, inner) => {
        take(ty)
        take_expr(inner)
      }
      VaArg(ap, ty) => {
        take(ty)
        take_expr(ap)
      }
      OffsetOf(ty, _) => take(ty)
      CompoundLiteral(ty, items, _) => {
        take(ty)
        for item in items {
          take_expr(item)
        }
      }
      Binary(_, lhs, rhs)
      | Assign(lhs, rhs)
      | CompoundAssign(_, lhs, rhs)
      | ArrayAccess(lhs, rhs) => {
        take_expr(lhs)
        take_expr(rhs)
      }
      Unary(_, inner)
      | Deref(inner)
      | AddrOf(inner)
      | SizeofExpr(inner)
      | AlignofExpr(inner)
      | PrefixInc(inner)
      | PrefixDec(inner)
      | PostfixInc(inner)
      | PostfixDec(inner)
      | MemberAccess(inner, _)
      | DesignatedField(_, inner)
      | DesignatedIndex(_, inner)
      | DesignatedRange(_, _, inner) => take_expr(inner)
      Call(callee, args) => {
        take_expr(callee)
        for arg in args {
          take_expr(arg)
        }
      }
      Ternary(cond, then_branch, else_branch) => {
        take_expr(cond)
        take_expr(then_branch)
        take_expr(else_branch)
      }
      Array(items) =>
        for item in items {
          take_expr(item)
        }
      Number(_, _, ty) | FloatLiteral(_, ty) => take(ty)
      String(_) | Var(_) | LabelAddr(_) => ()
    }
  }
  fn take_stmt(stmt : @parser.Stmt) -> Unit {
    match stmt {
      ExprStmt(expr) | ComputedGoto(expr) => take_expr(expr)
      Return(value) =>
        match value {
          Some(expr) => take_expr(expr)
          None => ()
        }
      VarDecl(ty, _, init) => {
        take(ty)
        match init {
          Some(expr) => take_expr(expr)
          None => ()
        }
      }
      If(cond, then_branch, else_branch) => {
        take_expr(cond)
        take_stmt(then_branch)
        match else_branch {
          Some(stmt) => take_stmt(stmt)
          None => ()
        }
      }
      While(cond, body) | DoWhile(cond, body) | Switch(cond, body) => {
        take_expr(cond)
        take_stmt(body)
      }
      For(init, cond, step, body) => {
        for stmt in init {
          take_stmt(stmt)
        }
        take_expr(cond)
        match step {
          Some(expr) => take_expr(expr)
          None => ()
        }
        take_stmt(body)
      }
      Compound(stmts) =>
        for stmt in stmts {
          take_stmt(stmt)
        }
      Case(_, body) | Default(body) | Label(_, body) => take_stmt(body)
      Break | Continue | Goto(_) => ()
    }
  }
  for decl in program.structs {
    for field in decl.fields {
      take(field.ty)
    }
  }
  for global in program.globals {
    take(global.ty)
    match global.init {
      Some(Scalar(expr)) => take_expr(expr)
      Some(Array(items)) =>
        for item in items {
          take_expr(item)
        }
      None => ()
    }
  }
  for decl in program.decls {
    take(decl.ret)
    for param in decl.params {
      take(param.ty)
    }
    match decl.body {
      Some(body) => take_stmt(body)
      None => ()
    }
  }
  tags
}

///|
/// Whether `index` is named by an `Aggregate` item.
fn item_held(program : @parser.Program, index : Int) -> Bool {
  for item in program.items {
    if item is Aggregate(held) && held == index {
      return true
    }
  }
  false
}

///|
/// How many mentions of `tag` exist beyond its defining member.
///
/// The full mention count comes from the same walker that finds referenced
/// tags -- fields, globals, signatures, local declarations, and every
/// type-bearing expression -- and the defining member contributes exactly
/// one mention when some member carries the tag, which is the definition
/// site rather than a reference. A positive result means the synthesized tag
/// must be spelled out for those references to resolve.
fn external_tag_references(
  referenced : Map[String, (Bool, Bool, Int)],
  carried : Map[String, Bool],
  tag : String,
) -> Int {
  let count = match referenced.get(tag) {
    Some((_, _, mentions)) => mentions
    None => 0
  }
  if carried.contains(tag) {
    count - 1
  } else {
    count
  }
}

///|
/// The tags that some member's declared type carries at its base -- the tags
/// with a member site to print an inline definition at.
fn member_base_tags(program : @parser.Program) -> Map[String, Bool] {
  let tags : Map[String, Bool] = Map([])
  for decl in program.structs {
    for field in decl.fields {
      match declaration_base_tag(field.ty) {
        Some(tag) => tags[tag] = true
        None => ()
      }
    }
  }
  tags
}

///|
/// The aggregate tag at the base of a declaration's type, following the same
/// spine `split_declaration` walks to find the specifier: through pointers,
/// arrays, a function pointer's return type, and the transparent wrappers.
/// This is the tag whose definition would print as the declaration's
/// specifier, which is what decides whether a member prints an inline
/// definition -- `struct { int size; } *by_pointer` reaches its tag under the
/// pointer.
fn declaration_base_tag(ty : @ctype.Type) -> String? {
  match ty {
    Struct(tag) | Union(tag) => Some(tag)
    Pointer(inner) | Atomic(inner) | Aligned(inner, _) =>
      declaration_base_tag(inner)
    Array(inner, _) => declaration_base_tag(inner)
    FuncPtr(ret, _, _) => declaration_base_tag(ret)
    _ => None
  }
}
