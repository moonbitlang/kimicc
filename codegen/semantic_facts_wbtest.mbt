///|
fn semantic_linux_target() -> @target.Target {
  match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("linux target did not parse")
  }
}

///|
fn expect_semantic_int(label : String, actual : Int, expected : Int) -> Unit {
  if actual != expected {
    abort(
      label +
      ": expected " +
      expected.to_string() +
      ", got " +
      actual.to_string(),
    )
  }
}

///|
fn expect_semantic_opt_int(
  label : String,
  actual : Int?,
  expected : Int?,
) -> Unit {
  if actual != expected {
    abort(label + ": optional int mismatch")
  }
}

///|
fn init_darwin_codegen_facts(prog : @parser.Program) -> Codegen {
  let codegen = Codegen::new()
  for decl in prog.structs {
    codegen.struct_decls[decl.name] = decl
  }
  for decl in prog.structs {
    codegen.compute_struct_layout(decl)
  }
  for decl in prog.decls {
    codegen.func_rets[decl.name] = decl.ret
    codegen.func_variadic[decl.name] = decl.variadic
    codegen.func_param_counts[decl.name] = decl.params.length()
    let param_types = []
    for param in decl.params {
      param_types.push(param.ty)
    }
    codegen.func_param_types[decl.name] = param_types
  }
  for global in prog.globals {
    codegen.globals[global.name] = global
  }
  codegen
}

///|
fn init_x64_codegen_facts(prog : @parser.Program) -> X64Codegen {
  let codegen = X64Codegen::new()
  for decl in prog.structs {
    codegen.struct_decls[decl.name] = decl
  }
  for decl in prog.structs {
    codegen.compute_struct_layout(decl)
  }
  for decl in prog.decls {
    codegen.func_rets[decl.name] = decl.ret
    codegen.func_variadic[decl.name] = decl.variadic
    let param_types = []
    for param in decl.params {
      param_types.push(param.ty)
    }
    codegen.func_param_types[decl.name] = param_types
  }
  for global in prog.globals {
    codegen.globals[global.name] = global
  }
  codegen
}

///|
fn expect_darwin_type_facts(
  codegen : Codegen,
  mir : @mir.Program,
  ty : @parser.Type,
) -> Unit {
  expect_semantic_int(
    "darwin size " + ty.to_string(),
    codegen.type_size(ty),
    mir.type_size(ty),
  )
  expect_semantic_int(
    "darwin align " + ty.to_string(),
    codegen.type_align(ty),
    mir.type_align(ty),
  )
}

///|
fn expect_x64_type_facts(
  codegen : X64Codegen,
  mir : @mir.Program,
  ty : @parser.Type,
) -> Unit {
  expect_semantic_int(
    "x64 size " + ty.to_string(),
    codegen.type_size(ty),
    mir.type_size(ty),
  )
  expect_semantic_int(
    "x64 align " + ty.to_string(),
    codegen.type_align(ty),
    mir.type_align(ty),
  )
}

///|
fn darwin_field_bit_width(width : Int) -> Int? {
  if width > 0 {
    Some(width)
  } else {
    None
  }
}

///|
fn x64_field_bit_width(width : Int) -> Int? {
  if width > 0 {
    Some(width)
  } else {
    None
  }
}

///|
fn expect_darwin_field_facts(
  codegen : Codegen,
  mir : @mir.Program,
  ty : @parser.Type,
  field : String,
) -> Unit {
  match
    (codegen.find_field_layout_for_type(ty, field), mir.field_layout(ty, field)) {
    (Some(cg), Some(m)) => {
      expect_semantic_int("darwin field offset " + field, cg.2, m.offset)
      expect_semantic_int("darwin field size " + field, cg.3, m.size)
      expect_semantic_int(
        "darwin field bit offset " + field,
        cg.4,
        m.bit_offset,
      )
      expect_semantic_opt_int(
        "darwin field bit width " + field,
        darwin_field_bit_width(cg.5),
        m.bit_width,
      )
    }
    _ => abort("missing darwin field fact: " + field)
  }
}

///|
fn expect_x64_field_facts(
  codegen : X64Codegen,
  mir : @mir.Program,
  ty : @parser.Type,
  field : String,
) -> Unit {
  match (codegen.field_layout(ty, field), mir.field_layout(ty, field)) {
    (Some(cg), Some(m)) => {
      expect_semantic_int("x64 field offset " + field, cg.2, m.offset)
      expect_semantic_int("x64 field size " + field, cg.3, m.size)
      expect_semantic_int("x64 field bit offset " + field, cg.4, m.bit_offset)
      expect_semantic_opt_int(
        "x64 field bit width " + field,
        x64_field_bit_width(cg.5),
        m.bit_width,
      )
    }
    _ => abort("missing x64 field fact: " + field)
  }
}

///|
fn expect_darwin_offset_facts(
  codegen : Codegen,
  mir : @mir.Program,
  ty : @parser.Type,
  path : Array[@parser.OffsetDesignator],
) -> Unit {
  if codegen.offset_of_path(ty, path) != mir.offset_of_path(ty, path) {
    abort("darwin offsetof path mismatch")
  }
}

///|
fn expect_x64_offset_facts(
  codegen : X64Codegen,
  mir : @mir.Program,
  ty : @parser.Type,
  path : Array[@parser.OffsetDesignator],
) -> Unit {
  if codegen.offset_of_path(ty, path) != mir.offset_of_path(ty, path) {
    abort("x64 offsetof path mismatch")
  }
}

///|
fn expect_x64_global_expr_type_facts(
  codegen : X64Codegen,
  mir : @mir.Program,
  expr : @parser.Expr,
) -> Unit {
  if codegen.global_expr_type(expr) != mir.global_expr_type(expr) {
    abort("x64 global expression type mismatch")
  }
}

///|
fn expect_darwin_global_expr_type_facts(
  codegen : Codegen,
  mir : @mir.Program,
  expr : @parser.Expr,
) -> Unit {
  if codegen.global_expr_type(expr) != mir.global_expr_type(expr) {
    abort("darwin global expression type mismatch")
  }
}

///|
fn expect_x64_fold_const_facts(
  codegen : X64Codegen,
  mir : @mir.Program,
  expr : @parser.Expr,
) -> Unit {
  let scope = @mir.Scope::{
    locals: codegen.var_types,
    current_func: codegen.func_name,
  }
  if codegen.fold_const(expr) != mir.fold_const(expr, scope) {
    abort("x64 constant fold mismatch")
  }
}

///|
fn expect_x64_fold_float_const_facts(
  codegen : X64Codegen,
  mir : @mir.Program,
  expr : @parser.Expr,
) -> Unit {
  let scope = @mir.Scope::{
    locals: codegen.var_types,
    current_func: codegen.func_name,
  }
  if codegen.fold_float_const(expr) != mir.fold_float_const(expr, scope) {
    abort("x64 floating constant fold mismatch")
  }
}

///|
fn expect_darwin_fold_const_facts(
  codegen : Codegen,
  mir : @mir.Program,
  expr : @parser.Expr,
) -> Unit {
  let scope = @mir.Scope::{
    locals: codegen.var_types,
    current_func: codegen.func_name,
  }
  if codegen.fold_const(expr) != mir.fold_const(expr, scope) {
    abort("darwin constant fold mismatch")
  }
}

///|
fn expect_darwin_fold_float_const_facts(
  codegen : Codegen,
  mir : @mir.Program,
  expr : @parser.Expr,
) -> Unit {
  let scope = @mir.Scope::{
    locals: codegen.var_types,
    current_func: codegen.func_name,
  }
  if codegen.fold_float_const(expr) != mir.fold_float_const(expr, scope) {
    abort("darwin floating constant fold mismatch")
  }
}

///|
fn semantic_fact_source() -> String {
  (
    #|struct S { char c; long double ld; int i; };
    #|struct __attribute__((packed)) P { char c; long double ld; int i; };
    #|struct B { unsigned a:3; unsigned b:5; unsigned c:9; };
    #|struct A { char tag; int arr[4]; };
    #|union U { char c; long double ld; int i; };
    #|struct A ga;
    #|long callee(int x, ...);
    #|int main(void) { return 0; }
  )
}

///|
test "darwin codegen layout facts match MIR facts" {
  let prog = @parser.parse(semantic_fact_source())
  let mir = @mir.lower(prog, @target.Target::default())
  let codegen = init_darwin_codegen_facts(prog)
  let types : Array[@parser.Type] = [
    Bool,
    SChar,
    UChar,
    SShort,
    UShort,
    SInt,
    UInt,
    SLong,
    ULong,
    SLongLong,
    ULongLong,
    SInt128,
    UInt128,
    Float,
    Double,
    LongDouble,
    Pointer(SInt),
    Array(SInt, 3),
    Struct("S"),
    Struct("P"),
    Struct("B"),
    Struct("A"),
    Union("U"),
  ]
  for ty in types {
    expect_darwin_type_facts(codegen, mir, ty)
  }
  expect_darwin_field_facts(codegen, mir, Struct("S"), "ld")
  expect_darwin_field_facts(codegen, mir, Struct("S"), "i")
  expect_darwin_field_facts(codegen, mir, Struct("B"), "b")
  expect_darwin_field_facts(codegen, mir, Struct("B"), "c")
  expect_darwin_field_facts(codegen, mir, Union("U"), "ld")
  expect_darwin_offset_facts(codegen, mir, Struct("A"), [
    OffsetField("arr"),
    OffsetIndex(2),
  ])
  expect_darwin_global_expr_type_facts(codegen, mir, Number(2147483648L))
  expect_darwin_global_expr_type_facts(codegen, mir, FloatLiteral(1.0))
  expect_darwin_global_expr_type_facts(codegen, mir, Var("callee"))
  expect_darwin_global_expr_type_facts(codegen, mir, Var("external_unknown"))
  expect_darwin_global_expr_type_facts(
    codegen,
    mir,
    AddrOf(MemberAccess(Var("ga"), "arr")),
  )
  expect_darwin_fold_const_facts(
    codegen,
    mir,
    OffsetOf(Struct("A"), [OffsetField("arr"), OffsetIndex(3)]),
  )
  expect_darwin_fold_float_const_facts(
    codegen,
    mir,
    Binary("/", Cast(Double, Number(1)), Number(2)),
  )
  expect_darwin_fold_float_const_facts(
    codegen,
    mir,
    Cast(Double, Cast(SInt, FloatLiteral(1.75))),
  )
}

///|
test "linux amd64 codegen layout facts match MIR facts" {
  let target = semantic_linux_target()
  let prog = @parser.parse_for_target(semantic_fact_source(), target)
  let mir = @mir.lower(prog, target)
  let codegen = init_x64_codegen_facts(prog)
  let types : Array[@parser.Type] = [
    Bool,
    SChar,
    UChar,
    SShort,
    UShort,
    SInt,
    UInt,
    SLong,
    ULong,
    SLongLong,
    ULongLong,
    SInt128,
    UInt128,
    Float,
    Float16,
    Double,
    LongDouble,
    Float128,
    Pointer(SInt),
    Array(SInt, 3),
    Struct("S"),
    Struct("P"),
    Struct("B"),
    Struct("A"),
    Union("U"),
  ]
  for ty in types {
    expect_x64_type_facts(codegen, mir, ty)
  }
  expect_x64_field_facts(codegen, mir, Struct("S"), "ld")
  expect_x64_field_facts(codegen, mir, Struct("S"), "i")
  expect_x64_field_facts(codegen, mir, Struct("B"), "b")
  expect_x64_field_facts(codegen, mir, Struct("B"), "c")
  expect_x64_field_facts(codegen, mir, Union("U"), "ld")
  expect_x64_offset_facts(codegen, mir, Struct("A"), [
    OffsetField("arr"),
    OffsetIndex(2),
  ])
  expect_x64_global_expr_type_facts(codegen, mir, Number(2147483648L))
  expect_x64_global_expr_type_facts(codegen, mir, FloatLiteral(1.0))
  expect_x64_global_expr_type_facts(codegen, mir, Var("callee"))
  expect_x64_global_expr_type_facts(codegen, mir, Var("external_unknown"))
  expect_x64_global_expr_type_facts(
    codegen,
    mir,
    ArrayAccess(MemberAccess(Var("ga"), "arr"), Number(2)),
  )
  expect_x64_global_expr_type_facts(
    codegen,
    mir,
    AddrOf(MemberAccess(Var("ga"), "arr")),
  )
  expect_x64_fold_const_facts(codegen, mir, Binary("/", Number(1), Number(2)))
  expect_x64_fold_const_facts(
    codegen,
    mir,
    Binary(">", Cast(ULong, Unary("-", Number(1))), Number(1)),
  )
  expect_x64_fold_const_facts(codegen, mir, SizeofExpr(Var("ga")))
  expect_x64_fold_const_facts(
    codegen,
    mir,
    AlignofExpr(MemberAccess(Var("ga"), "arr")),
  )
  expect_x64_fold_const_facts(
    codegen,
    mir,
    OffsetOf(Struct("A"), [OffsetField("arr"), OffsetIndex(2)]),
  )
  expect_x64_fold_float_const_facts(
    codegen,
    mir,
    Binary("/", Cast(Double, Number(1)), Number(2)),
  )
  expect_x64_fold_float_const_facts(
    codegen,
    mir,
    Cast(Double, Cast(SInt, FloatLiteral(1.75))),
  )
}
