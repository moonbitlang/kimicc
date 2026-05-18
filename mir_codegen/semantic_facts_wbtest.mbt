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
  let mir = @mir.lower(prog, @target.Target::default())
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
  for global in @mir.merge_global_decls(mir.global_decls) {
    codegen.globals[global.name] = codegen_global_decl_from_mir(global)
  }
  codegen
}

///|
fn init_x64_codegen_facts(prog : @parser.Program) -> X64Codegen {
  let codegen = X64Codegen::new()
  let mir = @mir.lower(prog, semantic_linux_target())
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
  for global in @mir.merge_global_decls(mir.global_decls) {
    codegen.globals[global.name] = codegen_global_decl_from_mir(global)
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
  expect_darwin_field_lookup_facts(codegen, mir, ty, ty, field)
}

///|
fn expect_darwin_field_lookup_facts(
  codegen : Codegen,
  mir : @mir.Program,
  lookup_ty : @parser.Type,
  mir_ty : @parser.Type,
  field : String,
) -> Unit {
  match
    (
      codegen.find_field_layout_for_type(lookup_ty, field),
      mir.field_layout(mir_ty, field),
    ) {
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
    _ => abort("missing darwin field lookup fact: " + field)
  }
}

///|
fn expect_x64_field_facts(
  codegen : X64Codegen,
  mir : @mir.Program,
  ty : @parser.Type,
  field : String,
) -> Unit {
  expect_x64_field_lookup_facts(codegen, mir, ty, ty, field)
}

///|
fn expect_x64_field_lookup_facts(
  codegen : X64Codegen,
  mir : @mir.Program,
  lookup_ty : @parser.Type,
  mir_ty : @parser.Type,
  field : String,
) -> Unit {
  match
    (codegen.field_layout(lookup_ty, field), mir.field_layout(mir_ty, field)) {
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
    _ => abort("missing x64 field lookup fact: " + field)
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
fn expect_x64_expr_type_facts(
  codegen : X64Codegen,
  mir : @mir.Program,
  expr : @parser.Expr,
) -> Unit {
  let scope = @mir.Scope::{
    locals: codegen.var_types,
    current_func: codegen.func_name,
  }
  if codegen.type_of(expr) != mir.expr_type(expr, scope) {
    abort("x64 expression type mismatch")
  }
}

///|
fn expect_darwin_expr_type_facts(
  codegen : Codegen,
  mir : @mir.Program,
  expr : @parser.Expr,
) -> Unit {
  let scope = @mir.Scope::{
    locals: codegen.var_types,
    current_func: codegen.func_name,
  }
  if codegen.type_of(expr, 0) != mir.expr_type(expr, scope) {
    abort("darwin expression type mismatch")
  }
}

///|
fn expect_x64_object_size_facts(
  codegen : X64Codegen,
  mir : @mir.Program,
  args : Array[@parser.Expr],
) -> Unit {
  let scope = @mir.Scope::{
    locals: codegen.var_types,
    current_func: codegen.func_name,
  }
  match mir.fold_const(Call(Var("__builtin_object_size"), args), scope) {
    Some(value) =>
      if codegen.builtin_object_size_value(args) != value {
        abort("x64 object size mismatch")
      }
    None => abort("missing x64 MIR object size fact")
  }
}

///|
fn expect_darwin_object_size_facts(
  codegen : Codegen,
  mir : @mir.Program,
  args : Array[@parser.Expr],
) -> Unit {
  let scope = @mir.Scope::{
    locals: codegen.var_types,
    current_func: codegen.func_name,
  }
  match mir.fold_const(Call(Var("__builtin_object_size"), args), scope) {
    Some(value) =>
      if codegen.builtin_object_size_value(args) != value {
        abort("darwin object size mismatch")
      }
    None => abort("missing darwin MIR object size fact")
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
    #|union U gu;
    #|long callee(int x, ...);
    #|int main(void) { return 0; }
  )
}

///|
test "darwin codegen layout facts match MIR facts" {
  let prog = @parser.parse(semantic_fact_source())
  let mir = @mir.lower(prog, @target.Target::default())
  let codegen = init_darwin_codegen_facts(prog)
  codegen.var_types["p"] = Pointer(SInt)
  codegen.var_types["ip"] = Pointer(SInt)
  codegen.var_types["local_buf"] = Array(SChar, 16)
  codegen.var_types["s"] = Struct("A")
  codegen.var_types["record"] = Struct("S")
  codegen.func_name = "main"
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
  expect_darwin_field_lookup_facts(
    codegen,
    mir,
    Pointer(Struct("A")),
    Struct("A"),
    "arr",
  )
  expect_darwin_field_lookup_facts(
    codegen,
    mir,
    Pointer(Union("U")),
    Union("U"),
    "ld",
  )
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
  expect_darwin_expr_type_facts(codegen, mir, Binary("+", Var("p"), Number(1)))
  expect_darwin_expr_type_facts(codegen, mir, Binary("-", Var("p"), Var("p")))
  expect_darwin_expr_type_facts(
    codegen,
    mir,
    Binary("<<", Number(1), Number(40)),
  )
  expect_darwin_expr_type_facts(codegen, mir, MemberAccess(Var("s"), "arr"))
  expect_darwin_expr_type_facts(
    codegen,
    mir,
    ArrayAccess(MemberAccess(Var("s"), "arr"), Number(2)),
  )
  expect_darwin_expr_type_facts(
    codegen,
    mir,
    AddrOf(MemberAccess(Var("s"), "arr")),
  )
  expect_darwin_expr_type_facts(codegen, mir, Var("callee"))
  expect_darwin_expr_type_facts(codegen, mir, Call(Var("callee"), [Number(1)]))
  expect_darwin_expr_type_facts(
    codegen,
    mir,
    Call(Var("__builtin_fabsl"), [FloatLiteral(1.0)]),
  )
  expect_darwin_expr_type_facts(
    codegen,
    mir,
    Call(Var("__builtin_memcpy"), [Var("p"), Var("p"), Number(4)]),
  )
  expect_darwin_expr_type_facts(
    codegen,
    mir,
    Call(Var("__builtin_strchr"), [String("abc"), Number(98)]),
  )
  expect_darwin_expr_type_facts(
    codegen,
    mir,
    Call(Var("__builtin_strlen"), [String("abc")]),
  )
  expect_darwin_expr_type_facts(
    codegen,
    mir,
    Call(Var("__builtin_expect"), [Cast(SLong, Number(1)), Number(1)]),
  )
  expect_darwin_expr_type_facts(
    codegen,
    mir,
    Call(Var("__builtin_bswap"), [Cast(UShort, Number(1))]),
  )
  expect_darwin_expr_type_facts(
    codegen,
    mir,
    Call(Var("__atomic_load_n"), [Var("ip"), Number(0)]),
  )
  expect_darwin_object_size_facts(codegen, mir, [String("abc"), Number(0)])
  expect_darwin_object_size_facts(codegen, mir, [AddrOf(Var("ga")), Number(0)])
  expect_darwin_object_size_facts(codegen, mir, [
    AddrOf(MemberAccess(Var("ga"), "arr")),
    Number(0),
  ])
  expect_darwin_object_size_facts(codegen, mir, [
    MemberAccess(Var("ga"), "arr"),
    Number(2),
  ])
  expect_darwin_object_size_facts(codegen, mir, [Var("local_buf"), Number(2)])
  expect_darwin_object_size_facts(codegen, mir, [
    AddrOf(ArrayAccess(Var("local_buf"), Number(3))),
    Number(0),
  ])
  expect_darwin_object_size_facts(codegen, mir, [
    AddrOf(ArrayAccess(Var("local_buf"), Number(3))),
    Number(1),
  ])
  expect_darwin_object_size_facts(codegen, mir, [
    AddrOf(MemberAccess(Var("s"), "arr")),
    Number(0),
  ])
  expect_darwin_object_size_facts(codegen, mir, [
    MemberAccess(Var("s"), "arr"),
    Number(2),
  ])
  expect_darwin_object_size_facts(codegen, mir, [
    AddrOf(ArrayAccess(MemberAccess(Var("s"), "arr"), Number(1))),
    Number(0),
  ])
  expect_darwin_object_size_facts(codegen, mir, [
    AddrOf(MemberAccess(Var("record"), "ld")),
    Number(0),
  ])
  expect_darwin_object_size_facts(codegen, mir, [
    AddrOf(MemberAccess(Var("record"), "ld")),
    Number(1),
  ])
  expect_darwin_object_size_facts(codegen, mir, [
    AddrOf(MemberAccess(Var("record"), "i")),
    Number(0),
  ])
  expect_darwin_object_size_facts(codegen, mir, [
    AddrOf(MemberAccess(Var("record"), "i")),
    Number(1),
  ])
  expect_darwin_object_size_facts(codegen, mir, [
    Cast(Pointer(Void), Number(0)),
    Number(0),
  ])
  expect_darwin_expr_type_facts(codegen, mir, SizeofExpr(Var("s")))
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
  codegen.var_types["p"] = Pointer(SInt)
  codegen.var_types["ip"] = Pointer(SInt)
  codegen.var_types["local_buf"] = Array(SChar, 16)
  codegen.var_types["s"] = Struct("A")
  codegen.var_types["record"] = Struct("S")
  codegen.func_name = "main"
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
  expect_x64_field_lookup_facts(
    codegen,
    mir,
    Pointer(Struct("A")),
    Struct("A"),
    "arr",
  )
  expect_x64_field_lookup_facts(
    codegen,
    mir,
    Pointer(Union("U")),
    Union("U"),
    "ld",
  )
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
  expect_x64_expr_type_facts(codegen, mir, Binary("+", Var("p"), Number(1)))
  expect_x64_expr_type_facts(codegen, mir, Binary("-", Var("p"), Var("p")))
  expect_x64_expr_type_facts(codegen, mir, Binary("<<", Number(1), Number(40)))
  expect_x64_expr_type_facts(codegen, mir, MemberAccess(Var("s"), "arr"))
  expect_x64_expr_type_facts(
    codegen,
    mir,
    ArrayAccess(MemberAccess(Var("s"), "arr"), Number(2)),
  )
  expect_x64_expr_type_facts(
    codegen,
    mir,
    AddrOf(MemberAccess(Var("s"), "arr")),
  )
  expect_x64_expr_type_facts(codegen, mir, Var("callee"))
  expect_x64_expr_type_facts(codegen, mir, Call(Var("callee"), [Number(1)]))
  expect_x64_expr_type_facts(
    codegen,
    mir,
    Call(Var("__builtin_fabsl"), [FloatLiteral(1.0)]),
  )
  expect_x64_expr_type_facts(
    codegen,
    mir,
    Call(Var("__builtin_memcpy"), [Var("p"), Var("p"), Number(4)]),
  )
  expect_x64_expr_type_facts(
    codegen,
    mir,
    Call(Var("__builtin_strchr"), [String("abc"), Number(98)]),
  )
  expect_x64_expr_type_facts(
    codegen,
    mir,
    Call(Var("__builtin_strlen"), [String("abc")]),
  )
  expect_x64_expr_type_facts(
    codegen,
    mir,
    Call(Var("__builtin_expect"), [Cast(SLong, Number(1)), Number(1)]),
  )
  expect_x64_expr_type_facts(
    codegen,
    mir,
    Call(Var("__builtin_bswap"), [Cast(UShort, Number(1))]),
  )
  expect_x64_expr_type_facts(
    codegen,
    mir,
    Call(Var("__atomic_load_n"), [Var("ip"), Number(0)]),
  )
  expect_x64_object_size_facts(codegen, mir, [String("abc"), Number(0)])
  expect_x64_object_size_facts(codegen, mir, [AddrOf(Var("ga")), Number(0)])
  expect_x64_object_size_facts(codegen, mir, [
    AddrOf(MemberAccess(Var("ga"), "arr")),
    Number(0),
  ])
  expect_x64_object_size_facts(codegen, mir, [
    MemberAccess(Var("ga"), "arr"),
    Number(2),
  ])
  expect_x64_object_size_facts(codegen, mir, [Var("local_buf"), Number(2)])
  expect_x64_object_size_facts(codegen, mir, [
    AddrOf(ArrayAccess(Var("local_buf"), Number(3))),
    Number(0),
  ])
  expect_x64_object_size_facts(codegen, mir, [
    AddrOf(ArrayAccess(Var("local_buf"), Number(3))),
    Number(1),
  ])
  expect_x64_object_size_facts(codegen, mir, [
    AddrOf(MemberAccess(Var("s"), "arr")),
    Number(0),
  ])
  expect_x64_object_size_facts(codegen, mir, [
    MemberAccess(Var("s"), "arr"),
    Number(2),
  ])
  expect_x64_object_size_facts(codegen, mir, [
    AddrOf(ArrayAccess(MemberAccess(Var("s"), "arr"), Number(1))),
    Number(0),
  ])
  expect_x64_object_size_facts(codegen, mir, [
    AddrOf(MemberAccess(Var("record"), "ld")),
    Number(0),
  ])
  expect_x64_object_size_facts(codegen, mir, [
    AddrOf(MemberAccess(Var("record"), "ld")),
    Number(1),
  ])
  expect_x64_object_size_facts(codegen, mir, [
    AddrOf(MemberAccess(Var("record"), "i")),
    Number(0),
  ])
  expect_x64_object_size_facts(codegen, mir, [
    AddrOf(MemberAccess(Var("record"), "i")),
    Number(1),
  ])
  expect_x64_object_size_facts(codegen, mir, [
    Cast(Pointer(Void), Number(0)),
    Number(0),
  ])
  expect_x64_expr_type_facts(codegen, mir, SizeofExpr(Var("s")))
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

///|
test "darwin arm64 MIR module layout queries avoid Program state" {
  let prog = @parser.parse(semantic_fact_source())
  let mir = @mir.lower(prog, @target.Target::default())
  let mir_module = @mir.lower_to_module(prog, @target.Target::default())
  let codegen = Codegen::new_with_mir_module(mir_module)
  codegen.var_types["local_buf"] = Array(SChar, 16)
  codegen.var_types["s"] = Struct("A")
  codegen.var_types["record"] = Struct("S")
  codegen.func_name = "main"
  expect_darwin_type_facts(codegen, mir, Struct("A"))
  expect_darwin_field_facts(codegen, mir, Struct("A"), "arr")
  expect_darwin_field_facts(codegen, mir, Union("U"), "ld")
  expect_darwin_field_lookup_facts(
    codegen,
    mir,
    Pointer(Struct("A")),
    Struct("A"),
    "arr",
  )
  expect_darwin_field_lookup_facts(
    codegen,
    mir,
    Pointer(Union("U")),
    Union("U"),
    "ld",
  )
  expect_darwin_offset_facts(codegen, mir, Struct("A"), [
    OffsetField("arr"),
    OffsetIndex(2),
  ])
  expect_darwin_global_expr_type_facts(
    codegen,
    mir,
    AddrOf(MemberAccess(Var("ga"), "arr")),
  )
  match codegen.global_lvalue_reloc(MemberAccess(Var("gu"), "ld")) {
    Some(("_gu", 0)) => ()
    _ => abort("darwin attached union global lvalue mismatch")
  }
}

///|
test "linux amd64 MIR module layout queries avoid Program state" {
  let target = semantic_linux_target()
  let prog = @parser.parse_for_target(semantic_fact_source(), target)
  let mir = @mir.lower(prog, target)
  let mir_module = @mir.lower_to_module(prog, target)
  let codegen = X64Codegen::new_with_mir_module(mir_module)
  codegen.var_types["local_buf"] = Array(SChar, 16)
  codegen.var_types["s"] = Struct("A")
  codegen.var_types["record"] = Struct("S")
  codegen.func_name = "main"
  expect_x64_type_facts(codegen, mir, Struct("A"))
  expect_x64_field_facts(codegen, mir, Struct("A"), "arr")
  expect_x64_field_facts(codegen, mir, Union("U"), "ld")
  expect_x64_field_lookup_facts(
    codegen,
    mir,
    Pointer(Struct("A")),
    Struct("A"),
    "arr",
  )
  expect_x64_field_lookup_facts(
    codegen,
    mir,
    Pointer(Union("U")),
    Union("U"),
    "ld",
  )
  expect_x64_offset_facts(codegen, mir, Struct("A"), [
    OffsetField("arr"),
    OffsetIndex(2),
  ])
  expect_x64_global_expr_type_facts(
    codegen,
    mir,
    AddrOf(MemberAccess(Var("ga"), "arr")),
  )
  match codegen.global_lvalue_reloc(MemberAccess(Var("gu"), "ld")) {
    Some(("gu", 0)) => ()
    _ => abort("x64 attached union global lvalue mismatch")
  }
}
