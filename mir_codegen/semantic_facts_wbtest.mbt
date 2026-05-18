///|
fn semantic_test_aggregate_decl() -> @mir.MirAggregateDecl {
  {
    name: "Pair",
    fields: [
      { name: "head", ty: @ctype.Type::SInt, bit_width: None },
      {
        name: "tail",
        ty: @ctype.Type::Array(@ctype.Type::SInt, 2),
        bit_width: None,
      },
    ],
    is_union: false,
    is_packed: false,
  }
}

///|
fn semantic_test_aggregate_layout() -> @mir.AggregateLayout {
  {
    fields: [
      {
        name: "head",
        ty: @ctype.Type::SInt,
        offset: 0,
        size: 4,
        bit_offset: 0,
        bit_width: None,
      },
      {
        name: "tail",
        ty: @ctype.Type::Array(@ctype.Type::SInt, 2),
        offset: 4,
        size: 8,
        bit_offset: 0,
        bit_width: None,
      },
    ],
    size: 12,
    align: 4,
    is_union: false,
    is_packed: false,
  }
}

///|
fn semantic_test_module(target : @target.Target) -> @mir.MirModule {
  let aggregate = semantic_test_aggregate_decl()
  let layout = semantic_test_aggregate_layout()
  let global : @mir.MirGlobalDecl = {
    ty: @ctype.Type::Struct("Pair"),
    name: "g_pair",
    init: Some(
      @mir.MirGlobalInit::MirGlobalArray([
        @mir.MirGlobalInit::MirGlobalScalarInt(7L),
        @mir.MirGlobalInit::MirGlobalArray([
          @mir.MirGlobalInit::MirGlobalScalarInt(11L),
          @mir.MirGlobalInit::MirGlobalScalarInt(13L),
        ]),
      ]),
    ),
    has_init: true,
    is_static: false,
    is_extern: false,
    is_weak: false,
    visibility: None,
    symbol_alias: None,
    section: None,
  }
  {
    target,
    decls: [],
    global_decls: [global],
    aggregate_decls: [aggregate],
    funcs: {},
    globals: { "g_pair": global },
    aggregates: { "Pair": aggregate },
    layouts: { "Pair": layout },
    bodies: {},
  }
}

///|
test "darwin MIR codegen uses parser-free module layout facts" {
  let mir_module = semantic_test_module(@target.Target::DarwinArm64)
  let codegen = Codegen::new_with_mir_module(mir_module)
  codegen.register_mir_aggregate_layouts(mir_module)
  assert_eq(codegen.type_size(@ctype.Type::Struct("Pair")), 12)
  assert_eq(codegen.type_align(@ctype.Type::Struct("Pair")), 4)
  match
    codegen.find_field_layout_for_type(@ctype.Type::Struct("Pair"), "tail") {
    Some((_, @ctype.Type::Array(@ctype.Type::SInt, 2), 4, 8, 0, 0)) => ()
    _ => abort("unexpected Darwin MIR field layout")
  }
  match
    codegen.offset_of_path(@ctype.Type::Struct("Pair"), [
      @ctype.OffsetDesignator::OffsetField("tail"),
      @ctype.OffsetDesignator::OffsetIndex(1L),
    ]) {
    Some(8) => ()
    _ => abort("unexpected Darwin MIR offset path")
  }
  match generate_assembly_from_mir_module_strict(mir_module) {
    Ok(assembly) => {
      assert_true(assembly.contains("_g_pair:"))
      assert_true(assembly.contains("\t.long\t7"))
      assert_true(assembly.contains("\t.long\t13"))
    }
    Err(err) => abort(err)
  }
}

///|
test "linux x64 MIR codegen uses parser-free module layout facts" {
  let mir_module = semantic_test_module(@target.Target::LinuxAmd64)
  let codegen = X64Codegen::new_with_mir_module(mir_module)
  codegen.register_mir_aggregate_layouts(mir_module)
  assert_eq(codegen.type_size(@ctype.Type::Struct("Pair")), 12)
  assert_eq(codegen.type_align(@ctype.Type::Struct("Pair")), 4)
  match codegen.field_layout(@ctype.Type::Struct("Pair"), "tail") {
    Some((_, @ctype.Type::Array(@ctype.Type::SInt, 2), 4, 8, 0, -1)) => ()
    _ => abort("unexpected x86-64 MIR field layout")
  }
  match
    codegen.offset_of_path(@ctype.Type::Struct("Pair"), [
      @ctype.OffsetDesignator::OffsetField("tail"),
      @ctype.OffsetDesignator::OffsetIndex(1L),
    ]) {
    Some(8) => ()
    _ => abort("unexpected x86-64 MIR offset path")
  }
  match generate_assembly_from_mir_module_strict(mir_module) {
    Ok(assembly) => {
      assert_true(assembly.contains("g_pair:"))
      assert_true(assembly.contains("\t.long\t7"))
      assert_true(assembly.contains("\t.long\t13"))
    }
    Err(err) => abort(err)
  }
}
