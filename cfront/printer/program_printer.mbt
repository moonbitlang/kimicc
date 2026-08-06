///|
/// Renders a whole translation unit as C source.
///
/// The output is canonical: aggregates first, then globals, then functions,
/// each in the order the AST holds them. Parsing the result yields the same
/// AST, which is the property meta-programming depends on -- build or transform
/// a `Program`, print it, and hand the text to another compiler.
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
  for decl in program.structs {
    write_struct_decl(buf, decl)
  }
  for global in program.globals {
    write_global_decl(buf, global)
  }
  for decl in program.decls {
    write_func_decl(buf, decl)
  }
  buf.to_string()
}

///|
/// Writes an aggregate declaration, including whatever spelling reproduces its
/// field-alignment cap.
///
/// `pack` is layout, not decoration: dropping it would print C that compiles to
/// a different ABI. `Some(1)` is the GNU `packed` attribute; any other cap needs
/// a `#pragma pack` pair around the declaration, which the parser reads back
/// positionally.
fn write_struct_decl(buf : StringBuilder, decl : @parser.StructDecl) -> Unit {
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
  for field in decl.fields {
    buf.write_string("  ")
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
