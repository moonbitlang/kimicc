///|
/// Renders a type as a C declaration of `name`.
///
/// C declarator syntax reads outward from the name, so a type cannot be printed
/// as a prefix followed by an identifier. `Pointer(Array(SInt, 4))` is
/// `int (*x)[4]`, not `int *x[4]` -- that spelling is `Array(Pointer(SInt), 4)`.
/// This walks the type from the outside in, growing the declarator around
/// `name` and parenthesizing wherever `[]` or `()` would otherwise bind tighter
/// than `*`.
///
/// Pass an empty `name` to get an abstract declarator, the form used in casts
/// and `sizeof`.
///
/// ```mbt check
/// test {
///   inspect(
///     @printer.print_declaration(Pointer(Array(SInt, 4)), "x"),
///     content="int (*x)[4]",
///   )
///   inspect(
///     @printer.print_declaration(Array(Pointer(SInt), 4), "x"),
///     content="int *x[4]",
///   )
///   inspect(@printer.print_declaration(Pointer(SInt), ""), content="int *")
/// }
/// ```
pub fn print_declaration(ty : @ctype.Type, name : String) -> String {
  match ty {
    Pointer(pointee) => {
      let inner = "*" + name
      // `*` binds looser than `[]` and `()`, so a pointer to an array or to a
      // function needs parentheses to keep the declarator reading correctly.
      match pointee {
        Array(_, _) | FuncPtr(_, _, _) =>
          print_declaration(pointee, "(" + inner + ")")
        _ => print_declaration(pointee, inner)
      }
    }
    Array(element, length) =>
      print_declaration(element, name + "[" + length.to_string() + "]")
    FuncPtr(ret, params, variadic) =>
      print_declaration(
        ret,
        "(*" + name + ")(" + parameter_list(params, variadic) + ")",
      )
    Atomic(inner) => "_Atomic " + print_declaration(inner, name)
    Aligned(inner, alignment) =>
      "_Alignas(" +
      alignment.to_string() +
      ") " +
      print_declaration(inner, name)
    _ => join_declarator(base_specifier(ty), name)
  }
}

///|
/// Renders a type on its own, with no declared name.
///
/// This is the spelling used by casts, `sizeof`, and `_Alignof`.
///
/// ```mbt check
/// test {
///   inspect(@printer.print_type(Pointer(SChar)), content="char *")
///   inspect(@printer.print_type(SInt), content="int")
/// }
/// ```
pub fn print_type(ty : @ctype.Type) -> String {
  print_declaration(ty, "")
}

///|
/// Joins a base specifier to a declarator, dropping the separator when the
/// declarator is empty so an abstract `int` does not come out as `"int "`.
fn join_declarator(base : String, name : String) -> String {
  if name is "" {
    base
  } else {
    base + " " + name
  }
}

///|
/// Returns the C spelling of a type's base specifier.
///
/// Compound types delegate to the type they wrap. `declare` handles those cases
/// itself and never reaches this, but recursing keeps the function total rather
/// than leaving an unreachable failure case in a library.
fn base_specifier(ty : @ctype.Type) -> String {
  match ty {
    Void => "void"
    Bool => "_Bool"
    SChar => "char"
    UChar => "unsigned char"
    SShort => "short"
    UShort => "unsigned short"
    SInt => "int"
    UInt => "unsigned int"
    SLong => "long"
    ULong => "unsigned long"
    SLongLong => "long long"
    ULongLong => "unsigned long long"
    SInt128 => "__int128"
    UInt128 => "unsigned __int128"
    Float => "float"
    Float16 => "_Float16"
    Float128 => "__float128"
    Double => "double"
    LongDouble => "long double"
    Struct(name) => "struct " + name
    Union(name) => "union " + name
    // A named type's spelling is its entire identity: print it verbatim.
    Named(name) => name
    Pointer(inner) | Array(inner, _) | Atomic(inner) | Aligned(inner, _) =>
      base_specifier(inner)
    FuncPtr(ret, _, _) => base_specifier(ret)
  }
}

///|
/// Renders a parameter type list, including the variadic tail.
///
/// An empty non-variadic list prints as `void`, since `()` in C means
/// "unspecified arguments" rather than "no arguments".
fn parameter_list(params : ArrayView[@ctype.Type], variadic : Bool) -> String {
  if params.length() == 0 {
    return if variadic { "..." } else { "void" }
  }
  let parts = []
  for param in params {
    parts.push(print_type(param))
  }
  if variadic {
    parts.push("...")
  }
  parts.join(", ")
}

///|
/// Renders a declared parameter list for a function definition or prototype.
fn declared_parameter_list(
  params : ArrayView[@parser.Param],
  variadic : Bool,
) -> String {
  if params.length() == 0 {
    return if variadic { "..." } else { "void" }
  }
  let parts = []
  for param in params {
    parts.push(print_declaration(param.ty, param.name))
  }
  if variadic {
    parts.push("...")
  }
  parts.join(", ")
}

///|
/// Splits a declaration into the specifier a group of names shares and the
/// declarator that distinguishes this one.
///
/// `int *p` splits as `("int", "*p")` and `char buf[8]` as `("char", "buf[8]")`.
/// This is what lets several names declared together be written the way C
/// writes them -- `int i = 0, *p = q` -- from an AST that records one
/// declaration per name. `_Atomic` and `_Alignas` belong to the specifier,
/// since C writes them once for the whole declaration.
pub fn split_declaration(ty : @ctype.Type, name : String) -> (String, String) {
  match ty {
    Pointer(pointee) => {
      let inner = "*" + name
      match pointee {
        Array(_, _) | FuncPtr(_, _, _) =>
          split_declaration(pointee, "(" + inner + ")")
        _ => split_declaration(pointee, inner)
      }
    }
    Array(element, length) =>
      split_declaration(element, name + "[" + length.to_string() + "]")
    FuncPtr(ret, params, variadic) =>
      split_declaration(
        ret,
        "(*" + name + ")(" + parameter_list(params, variadic) + ")",
      )
    Atomic(inner) => {
      let (specifier, declarator) = split_declaration(inner, name)
      ("_Atomic " + specifier, declarator)
    }
    Aligned(inner, alignment) => {
      let (specifier, declarator) = split_declaration(inner, name)
      ("_Alignas(" + alignment.to_string() + ") " + specifier, declarator)
    }
    _ => (base_specifier(ty), name)
  }
}
