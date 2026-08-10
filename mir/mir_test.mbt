///|
fn linux_target() -> @target.Target {
  match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("linux target did not parse")
  }
}

///|
fn expect_interp(
  source : String,
  expected : Int64,
) -> Unit raise @parser.ParseError {
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.interpret_i64("main", []) {
    Ok(value) =>
      if value != expected {
        abort(
          "unexpected MIR interpreter result: expected " +
          expected.to_string() +
          ", got " +
          value.to_string(),
        )
      }
    Err(err) => abort(err)
  }
}

///|
fn expect_body_interp(
  source : String,
  expected : Int64,
) -> Unit raise @parser.ParseError {
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.interpret_body_i64("main", []) {
    Ok(value) =>
      if value != expected {
        abort(
          "unexpected MIR body interpreter result: expected " +
          expected.to_string() +
          ", got " +
          value.to_string(),
        )
      }
    Err(err) => abort(err)
  }
}

///|
test "mir records target-specific scalar layout" {
  let source = "int main(void) { return 0; }"
  let darwin = @mir.lower(@parser.parse(source), @target.Target::default())
  let linux = @mir.lower(
    @parser.parse_for_target(source, linux_target()),
    linux_target(),
  )
  inspect(darwin.type_size(LongDouble), content="8")
  inspect(darwin.type_align(LongDouble), content="8")
  inspect(linux.type_size(LongDouble), content="16")
  inspect(linux.type_align(LongDouble), content="16")
  inspect(linux.type_size(Float16), content="2")
  inspect(linux.type_align(Float16), content="2")
  let darwin_module = darwin.to_module()
  let linux_module = linux.to_module()
  inspect(darwin_module.type_size(LongDouble), content="8")
  inspect(darwin_module.type_align(LongDouble), content="8")
  inspect(linux_module.type_size(LongDouble), content="16")
  inspect(linux_module.type_align(LongDouble), content="16")
  inspect(linux_module.type_size(Float16), content="2")
  inspect(linux_module.type_align(Float16), content="2")
}

///|
test "mir module projection carries parser-free semantic facts" {
  let source =
    #|struct Pair { int a; int b; };
    #|int g = 3;
    #|struct Pair gp;
    #|int main(void) { return g; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  let mir_module = mir.to_module()
  let direct_module = @mir.lower_to_module(
    @parser.parse(source),
    @target.Target::default(),
  )
  inspect(mir_module.decls[0].name, content="main")
  inspect(direct_module.decls[0].name, content="main")
  inspect(mir_module.global_decls[0].name, content="g")
  inspect(mir_module.globals["g"].has_init.to_string(), content="true")
  inspect(mir_module.aggregate_decls[0].name, content="Pair")
  inspect(
    mir_module.aggregates["Pair"].fields.length().to_string(),
    content="2",
  )
  inspect(mir_module.type_size(Struct("Pair")), content="8")
  inspect(mir_module.type_align(Struct("Pair")), content="4")
  match mir_module.field_layout(Struct("Pair"), "b") {
    Some(layout) => inspect(layout.offset, content="4")
    None => abort("missing Pair.b layout")
  }
  match mir_module.offset_of_path(Struct("Pair"), [OffsetField("b")]) {
    Some(offset) => inspect(offset, content="4")
    None => abort("missing Pair.b offset")
  }
  inspect(mir_module.globals["gp"].ty, content="Struct(Pair)")
  match mir_module.field_layout(mir_module.globals["gp"].ty, "b") {
    Some(layout) => {
      inspect(layout.ty, content="SInt")
      inspect(@ctype.Type::Pointer(layout.ty), content="Pointer(SInt)")
    }
    None => abort("missing gp.b layout")
  }
  inspect(mir_module.bodies.contains("main").to_string(), content="true")
}

///|
test "mir module computes parser-free object-size path facts" {
  let source =
    #|struct S { char tag; int arr[3]; char tail; };
    #|struct S gs;
    #|int main(void) { return 0; }
  let mir_module = @mir.lower_to_module(
    @parser.parse(source),
    @target.Target::default(),
  )
  match mir_module.object_size_path_fact(Struct("S"), []) {
    Some(fact) => {
      inspect(fact.value(0L), content="20")
      inspect(fact.value(1L), content="20")
    }
    None => abort("missing root object-size fact")
  }
  match
    mir_module.object_size_path_fact(Struct("S"), [
      OffsetField("arr"),
      OffsetIndex(1L),
    ]) {
    Some(fact) => {
      inspect(fact.value(0L), content="12")
      inspect(fact.value(1L), content="8")
    }
    None => abort("missing member array object-size fact")
  }
  match mir_module.object_size_path_fact(Array(SChar, 8), [OffsetIndex(3L)]) {
    Some(fact) => {
      inspect(fact.value(0L), content="5")
      inspect(fact.value(1L), content="5")
    }
    None => abort("missing array object-size fact")
  }
  match
    mir_module.object_size_path_fact(Struct("S"), [OffsetField("missing")]) {
    Some(_) => abort("unexpected missing-field object-size fact")
    None => ()
  }
}

///|
test "mir owns function declaration metadata" {
  let source =
    #|int ext(long x);
    #|static inline int helper(int x) { return x; }
    #|int main(void) { return helper(1); }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.decls.length(), content="3")
  inspect(mir.decls[0].name, content="ext")
  inspect(mir.decls[0].has_body, content="false")
  inspect(mir.decls[0].params[0].name, content="x")
  inspect(mir.decls[0].params[0].ty, content="SLong")
  inspect(mir.decls[1].name, content="helper")
  inspect(mir.decls[1].is_static, content="true")
  inspect(mir.decls[1].is_inline, content="true")
  inspect(mir.decls[1].has_body, content="true")
  inspect(mir.decls[2].name, content="main")
  inspect(mir.decls[2].has_body, content="true")
}

///|
test "mir owns global declaration metadata" {
  let source =
    #|extern int extg;
    #|static int sg = 7;
    #|int arr[2];
    #|int main(void) { return sg; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.global_decls.length(), content="3")
  inspect(mir.global_decls[0].name, content="extg")
  inspect(mir.global_decls[0].is_extern, content="true")
  inspect(mir.global_decls[0].has_init, content="false")
  inspect(mir.global_decls[1].name, content="sg")
  inspect(mir.global_decls[1].is_static, content="true")
  inspect(mir.global_decls[1].has_init, content="true")
  inspect(mir.global_decls[2].name, content="arr")
  inspect(mir.global_decls[2].ty, content="Array(SInt, 2)")
  inspect(mir.global_decls[2].has_init, content="false")
}

///|
test "mir merges global declaration metadata" {
  let source =
    #|extern int g __attribute__((weak));
    #|int g = 3;
    #|extern int g;
    #|int main(void) { return g; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  let globals = @mir.merge_global_decls(mir.global_decls)
  inspect(globals.length(), content="1")
  inspect(globals[0].name, content="g")
  inspect(globals[0].has_init, content="true")
  inspect(globals[0].is_extern, content="false")
  inspect(globals[0].is_weak, content="true")
  match globals[0].init {
    Some(MirGlobalScalarInt(3)) => ()
    _ => abort("expected merged global initializer")
  }
}

///|
test "mir owns simple global initializer metadata" {
  let source =
    #|int scalar = 7;
    #|char *text = "ok";
    #|int arr[2] = {1, 2};
    #|int expr = 1 + 2;
    #|int *addr = &scalar;
    #|int *elem_addr = arr + 1;
    #|int designated[3] = { [2] = 9 };
    #|struct S { int a; int b; int c; };
    #|struct S field_designated = { .c = 9, .a = 1 };
    #|union U { int i; char c; };
    #|union U union_designated = { .c = 7 };
    #|int main(void) { return scalar; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.global_decls[0].init {
    Some(MirGlobalScalarInt(7)) => ()
    _ => abort("expected scalar integer MIR global initializer")
  }
  match mir.global_decls[1].init {
    Some(MirGlobalString("ok")) => ()
    _ => abort("expected string MIR global initializer")
  }
  match mir.global_decls[2].init {
    Some(MirGlobalArray([MirGlobalScalarInt(1), MirGlobalScalarInt(2)])) => ()
    _ => abort("expected array MIR global initializer")
  }
  match mir.global_decls[3].init {
    Some(MirGlobalScalarInt(3)) => ()
    _ => abort("expected folded MIR global initializer")
  }
  match mir.global_decls[4].init {
    Some(MirGlobalSymbol("scalar")) => ()
    _ => abort("expected symbol address MIR global initializer")
  }
  match mir.global_decls[5].init {
    Some(MirGlobalSymbolOffset("arr", 4)) => ()
    _ => abort("expected symbol offset MIR global initializer")
  }
  match mir.global_decls[6].init {
    Some(MirGlobalArraySparse([(2, MirGlobalScalarInt(9))])) => ()
    _ => abort("expected sparse designated MIR global initializer")
  }
  match mir.global_decls[7].init {
    Some(
      MirGlobalAggregateSparse(
        [(2, MirGlobalScalarInt(9)), (0, MirGlobalScalarInt(1))]
      )
    ) => ()
    _ => abort("expected sparse aggregate field MIR global initializer")
  }
  match mir.global_decls[8].init {
    Some(MirGlobalAggregateSparse([(1, MirGlobalScalarInt(7))])) => ()
    _ => abort("expected sparse union field MIR global initializer")
  }
}

///|
test "mir owns global compound literal initializer metadata" {
  let source =
    #|int scalar = (int){7};
    #|struct S { int a; int b; };
    #|struct S aggregate = (struct S){ .b = 35, .a = 7 };
    #|union U { int i; char c; };
    #|union U tagged = (union U){ .c = 65 };
    #|int main(void) { return scalar; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.global_decls[0].init {
    Some(MirGlobalScalarInt(7)) => ()
    _ => abort("expected scalar compound literal MIR global initializer")
  }
  match mir.global_decls[1].init {
    Some(
      MirGlobalAggregateSparse(
        [(1, MirGlobalScalarInt(35)), (0, MirGlobalScalarInt(7))]
      )
    ) => ()
    _ => abort("expected aggregate compound literal MIR global initializer")
  }
  match mir.global_decls[2].init {
    Some(MirGlobalAggregateSparse([(1, MirGlobalScalarInt(65))])) => ()
    _ => abort("expected union compound literal MIR global initializer")
  }
}

///|
test "mir owns braced scalar global initializer metadata" {
  let source =
    #|int scalar = {42};
    #|int nested = {{21}};
    #|double fp = {1.25};
    #|char *ptr = {"abc"};
    #|int main(void) { return scalar; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.global_decls[0].init {
    Some(MirGlobalScalarInt(42)) => ()
    _ => abort("expected braced scalar MIR global initializer")
  }
  match mir.global_decls[1].init {
    Some(MirGlobalScalarInt(21)) => ()
    _ => abort("expected nested braced scalar MIR global initializer")
  }
  match mir.global_decls[2].init {
    Some(MirGlobalScalarFloat(1.25)) => ()
    _ => abort("expected braced floating MIR global initializer")
  }
  match mir.global_decls[3].init {
    Some(MirGlobalString("abc")) => ()
    _ => abort("expected braced string pointer MIR global initializer")
  }
}

///|
test "mir owns nested braced scalar global initializer metadata" {
  let source =
    #|int arr[2] = {{20}, {22}};
    #|struct S { int a; double b; char *c; };
    #|struct S aggregate = {{7}, {1.5}, {"ok"}};
    #|int main(void) { return arr[0]; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.global_decls[0].init {
    Some(MirGlobalArray([MirGlobalScalarInt(20), MirGlobalScalarInt(22)])) => ()
    _ => abort("expected nested braced scalar array MIR global initializer")
  }
  match mir.global_decls[1].init {
    Some(
      MirGlobalArray(
        [
          MirGlobalScalarInt(7),
          MirGlobalScalarFloat(1.5),
          MirGlobalString("ok"),
        ]
      )
    ) => ()
    _ => abort("expected nested braced scalar aggregate MIR global initializer")
  }
}

///|
test "mir owns file-scope compound literal static global metadata" {
  let source =
    #|struct S { int a; int b; };
    #|struct S *p = &(struct S){ .b = 23, .a = 19 };
    #|int *q = &((struct S){ 5, 37 }).b;
    #|int *r = (int[]){ 11, 31 };
    #|int main(void) { return p->a; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.global_decls[0].init {
    Some(MirGlobalSymbol("__kimicc_file_scope_compound_literal_0")) => ()
    _ => abort("expected pointer to file-scope struct compound literal")
  }
  match mir.global_decls[1].init {
    Some(MirGlobalSymbolOffset("__kimicc_file_scope_compound_literal_1", 4)) =>
      ()
    _ => abort("expected pointer to file-scope compound literal member")
  }
  match mir.global_decls[2].init {
    Some(MirGlobalSymbol("__kimicc_file_scope_compound_literal_2")) => ()
    _ => abort("expected array compound literal decay to static object")
  }
  match mir.globals["__kimicc_file_scope_compound_literal_0"].init {
    Some(
      MirGlobalAggregateSparse(
        [(1, MirGlobalScalarInt(23)), (0, MirGlobalScalarInt(19))]
      )
    ) => ()
    _ => abort("expected generated sparse struct compound literal global")
  }
  match mir.globals["__kimicc_file_scope_compound_literal_1"].init {
    Some(MirGlobalArray([MirGlobalScalarInt(5), MirGlobalScalarInt(37)])) => ()
    _ => abort("expected generated dense struct compound literal global")
  }
  inspect(
    mir.globals["__kimicc_file_scope_compound_literal_2"].ty,
    content="Array(SInt, 2)",
  )
  match mir.globals["__kimicc_file_scope_compound_literal_2"].init {
    Some(MirGlobalArray([MirGlobalScalarInt(11), MirGlobalScalarInt(31)])) => ()
    _ => abort("expected generated array compound literal global")
  }
}

///|
test "mir owns aggregate declaration metadata" {
  let source =
    #|struct __attribute__((packed)) S { char c; int bits:5; };
    #|union U { int i; char c; };
    #|int main(void) { return 0; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.aggregate_decls.length(), content="2")
  inspect(mir.aggregate_decls[0].name, content="S")
  debug_inspect(mir.aggregate_decls[0].pack, content="Some(1)")
  inspect(mir.aggregate_decls[0].is_union, content="false")
  inspect(mir.aggregate_decls[0].fields[0].name, content="c")
  inspect(mir.aggregate_decls[0].fields[0].ty, content="SChar")
  inspect(mir.aggregate_decls[0].fields[1].name, content="bits")
  match mir.aggregate_decls[0].fields[1].bit_width {
    Some(5) => ()
    _ => abort("unexpected bitfield width")
  }
  inspect(mir.aggregate_decls[1].name, content="U")
  inspect(mir.aggregate_decls[1].is_union, content="true")
  inspect(mir.aggregate_decls[1].fields.length(), content="2")
}

///|
test "mir owns floating global initializer metadata" {
  let source =
    #|double fp = 1.0 / 2.0;
    #|float selected = 1 ? 3 / 2 : 9.0f;
    #|int converted = (double)3 / 2;
    #|int main(void) { return converted; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.globals["fp"].init {
    Some(MirGlobalScalarFloat(0.5)) => ()
    _ => abort("expected MIR float global initializer")
  }
  match mir.globals["selected"].init {
    Some(MirGlobalScalarFloat(1.0)) => ()
    _ => abort("expected MIR selected float global initializer")
  }
  match mir.globals["converted"].init {
    Some(MirGlobalScalarInt(1)) => ()
    _ => abort("expected MIR converted float-to-int global initializer")
  }
}

///|
test "mir owns typed aggregate global float initializers" {
  let source =
    #|struct Xform {
    #|  unsigned char nName;
    #|  char zName[7];
    #|  float rLimit;
    #|  float rXform;
    #|};
    #|static const struct Xform aXformType[] = {
    #|  { 6, "second", 4.5f, 1.0f },
    #|};
    #|int main(void) { return 0; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.globals["aXformType"].init {
    Some(
      MirGlobalArray(
        [
          MirGlobalArray(
            [
              MirGlobalScalarInt(6),
              MirGlobalString("second"),
              MirGlobalScalarFloat(4.5),
              MirGlobalScalarFloat(1.0),
            ]
          ),
        ]
      )
    ) => ()
    _ => abort("expected typed aggregate MIR float global initializer")
  }
}

///|
test "mir owns casted string pointer global array initializers" {
  let source =
    #|typedef unsigned char u8;
    #|static unsigned char * const azOne[] = { (u8*)" " };
    #|static char *azEndings[] = { "dylib" };
    #|static int f(void) {
    #|  static const char *localEndings[] = { "so" };
    #|  return localEndings[0][0];
    #|}
    #|int main(void) { return 0; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.globals["azOne"].init {
    Some(MirGlobalArray([MirGlobalString(" ")])) => ()
    _ => abort("expected casted string pointer MIR global initializer")
  }
  match mir.globals["azEndings"].init {
    Some(MirGlobalArray([MirGlobalString("dylib")])) => ()
    _ => abort("expected string pointer array MIR global initializer")
  }
  match mir.globals["_f_localEndings"].init {
    Some(MirGlobalArray([MirGlobalString("so")])) => ()
    _ =>
      abort("expected local static string pointer array MIR global initializer")
  }
}

///|
test "mir owns bitfield global initializer metadata" {
  let source =
    #|struct Bits { unsigned a : 3; signed b : 4; unsigned c : 5; };
    #|union UBits { unsigned a : 3; signed b : 4; };
    #|struct Bits bits = { .a = 5, .b = -3, .c = 17 };
    #|union UBits ubits = { .b = -3 };
    #|int main(void) { return 0; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.globals["bits"].init {
    Some(
      MirGlobalAggregateSparse(
        [
          (0, MirGlobalScalarInt(5)),
          (1, MirGlobalScalarInt(-3)),
          (2, MirGlobalScalarInt(17)),
        ]
      )
    ) => ()
    _ => abort("expected MIR bitfield aggregate initializer")
  }
  match mir.globals["ubits"].init {
    Some(MirGlobalAggregateSparse([(1, MirGlobalScalarInt(-3))])) => ()
    _ => abort("expected MIR bitfield union initializer")
  }
}

///|
test "mir recursively lowers nested global initializer designators" {
  let source =
    #|struct Row { int cells[4]; };
    #|struct Table { struct Row rows[2]; int tail; };
    #|struct Table g = { .rows = { [1] = { .cells = { [2] = 9 } } }, .tail = 5 };
    #|int main(void) { return 0; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.globals["g"].init {
    Some(
      MirGlobalAggregateSparse(
        [
          (
            0,
            MirGlobalArraySparse(
              [
                (
                  1,
                  MirGlobalAggregateSparse(
                    [(0, MirGlobalArraySparse([(2, MirGlobalScalarInt(9))]))]
                  ),
                ),
              ]
            ),
          ),
          (1, MirGlobalScalarInt(5)),
        ]
      )
    ) => ()
    _ => abort("expected nested sparse MIR global initializer")
  }
}

///|
test "mir computes aggregate layout facts" {
  let source =
    #|struct S { char c; int i; short s; };
    #|struct __attribute__((packed)) P { char c; int i; short s; };
    #|struct B { unsigned a:3; unsigned b:5; unsigned c:9; };
    #|int main(void) { return 0; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.type_size(Struct("S")), content="12")
  inspect(mir.type_align(Struct("S")), content="4")
  match mir.field_layout(Struct("S"), "i") {
    Some({ offset: 4, size: 4, bit_width: None, .. }) => ()
    _ => abort("unexpected layout for S.i")
  }
  inspect(mir.type_size(Struct("P")), content="7")
  inspect(mir.type_align(Struct("P")), content="1")
  match mir.field_layout(Struct("B"), "b") {
    Some({ offset: 0, size: 4, bit_offset: 3, bit_width: Some(5), .. }) => ()
    _ => abort("unexpected layout for B.b")
  }
  match mir.field_layout(Struct("B"), "c") {
    Some({ offset: 0, size: 4, bit_offset: 8, bit_width: Some(9), .. }) => ()
    _ => abort("unexpected layout for B.c")
  }
}

///|
test "mir exposes module global facts" {
  let source =
    #|struct S { int x; double y; };
    #|struct S g;
    #|double callee(int x, ...);
    #|int main(void) { return 0; }
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  let mir_module = mir.to_module()
  inspect(mir_module.globals["g"].ty, content="Struct(S)")
  inspect(
    @ctype.Type::Pointer(mir_module.globals["g"].ty),
    content="Pointer(Struct(S))",
  )
}

///|
test "mir lowers scalar function bodies into MIR-owned statements" {
  let source =
    #|int main(void) {
    #|  int x = 6;
    #|  int y = 7;
    #|  return x * y;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  let body = mir.bodies["main"]
  inspect(body.locals.length(), content="2")
  match mir.interpret_body_i64("main", []) {
    Ok(value) => inspect(value, content="42")
    Err(err) => abort(err)
  }
}

///|
test "mir body interpreter executes calls branches and loops" {
  let source =
    #|int add_if_odd(int acc, int x) {
    #|  if (x % 2) {
    #|    return acc + x;
    #|  }
    #|  return acc;
    #|}
    #|int main(void) {
    #|  int i = 0;
    #|  int sum = 0;
    #|  while (i < 10) {
    #|    sum = add_if_odd(sum, i);
    #|    i = i + 1;
    #|  }
    #|  return sum;
    #|}
  expect_body_interp(source, 25L)
}

///|
test "mir body interpreter executes indirect function pointer calls" {
  let source =
    #|int bump(int x) { return x + 1; }
    #|int main(void) {
    #|  int (*fp)(int) = bump;
    #|  return fp(20) + (*fp)(20);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter executes dereferenced typedef function pointer calls" {
  let source =
    #|typedef int Callback(int value);
    #|int add(int value) {
    #|  return value + 5;
    #|}
    #|int main(void) {
    #|  Callback *fp = add;
    #|  return (*fp)(7);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 12L)
}

///|
test "mir body interpreter executes returned function pointer calls" {
  let source =
    #|int hash(const void *p, int n) { return n + 40; }
    #|int (*pick(int key_class))(const void *, int) {
    #|  return &hash;
    #|}
    #|int main(void) {
    #|  int (*xHash)(const void *, int) = pick(1);
    #|  return (*xHash)("hi", 2);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("pick"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter uses scoped stable local ids" {
  let source =
    #|int main(void) {
    #|  int x = 1;
    #|  {
    #|    int x = 40;
    #|    x = x + 2;
    #|  }
    #|  return x;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  let body = mir.bodies["main"]
  inspect(body.locals.length(), content="2")
  expect_body_interp(source, 1L)
}

///|
test "mir body interpreter executes for break and continue" {
  let source =
    #|int main(void) {
    #|  int sum = 0;
    #|  for (int i = 0; i < 8; i = i + 1) {
    #|    if (i == 2) continue;
    #|    if (i == 6) break;
    #|    sum = sum + i;
    #|  }
    #|  return sum;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 13L)
}

///|
test "mir body interpreter executes do while break and continue" {
  let source =
    #|int main(void) {
    #|  int i = 0;
    #|  int sum = 0;
    #|  do {
    #|    i = i + 1;
    #|    if (i == 2) continue;
    #|    if (i == 6) break;
    #|    sum = sum + i;
    #|  } while (i < 8);
    #|  return sum;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 13L)
}

///|
test "mir body interpreter executes switch fallthrough" {
  let source =
    #|int main(void) {
    #|  int total = 0;
    #|  for (int i = 0; i < 5; i = i + 1) {
    #|    switch (i) {
    #|    case 0:
    #|      total = total + 3;
    #|      break;
    #|    case 1:
    #|    case 2:
    #|      total = total + 5;
    #|      break;
    #|    case 4:
    #|      total = total + 7;
    #|    default:
    #|      total = total + 11;
    #|    }
    #|  }
    #|  return total;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter executes switch case labels nested in if" {
  let source =
    #|int main(void) {
    #|  int x = 2;
    #|  int total = 0;
    #|  switch (x) {
    #|    if (x > 0) {
    #|    case 1:
    #|      total = 10;
    #|      break;
    #|    case 2:
    #|      total = 20;
    #|    }
    #|    total = total + 22;
    #|  }
    #|  return total;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter executes switch case labels nested in loops" {
  let source =
    #|int main(void) {
    #|  int x = 2;
    #|  int total = 0;
    #|  switch (x) {
    #|    while (x > 0) {
    #|    case 1:
    #|      total = total + 10;
    #|      x = 0;
    #|      break;
    #|    case 2:
    #|      total = total + 20;
    #|      x = x - 1;
    #|    }
    #|    total = total + 3;
    #|  }
    #|  return total;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 33L)
}

///|
test "mir body interpreter skips for init when switch enters loop case" {
  let source =
    #|int main(void) {
    #|  int x = 2;
    #|  int total = 0;
    #|  switch (x) {
    #|    for (total = 100; x > 0; x = x - 1) {
    #|    case 1:
    #|      total = total + 10;
    #|      break;
    #|    case 2:
    #|      total = total + 20;
    #|    }
    #|    total = total + 3;
    #|  }
    #|  return total;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 33L)
}

///|
test "mir body interpreter executes switch case labels nested in do while" {
  let source =
    #|int main(void) {
    #|  int x = 2;
    #|  int total = 0;
    #|  switch (x) {
    #|    do {
    #|    case 1:
    #|      total = total + 10;
    #|      break;
    #|    case 2:
    #|      total = total + 20;
    #|      x = x - 1;
    #|    } while (x > 0);
    #|    total = total + 3;
    #|  }
    #|  return total;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 33L)
}

///|
test "mir body interpreter executes simple goto" {
  let source =
    #|int main(void) {
    #|  int total = 0;
    #|  int i = 0;
    #|loop:
    #|  i = i + 1;
    #|  if (i == 2) goto skip;
    #|  total = total + i;
    #|skip:
    #|  if (i < 5) goto loop;
    #|  return total;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 13L)
}

///|
test "mir body interpreter executes local computed goto" {
  let source =
    #|int main(void) {
    #|  void *target = &&done;
    #|  goto *target;
    #|  return 1;
    #|done:
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter executes static computed goto table" {
  let source =
    #|int main(void) {
    #|  static void *labels[] = { &&bad, &&good };
    #|  goto *labels[1];
    #|bad:
    #|  return 1;
    #|good:
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter executes local computed goto table" {
  let source =
    #|int main(void) {
    #|  void *labels[] = { &&bad, &&good, &&also_bad };
    #|  int index = 0;
    #|  index = index + 1;
    #|  goto *labels[index];
    #|bad:
    #|  return 1;
    #|also_bad:
    #|  return 2;
    #|good:
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter executes scalar updates" {
  let source =
    #|int main(void) {
    #|  int total = 0;
    #|  int i = 0;
    #|loop:
    #|  i++;
    #|  if (i == 2) goto skip;
    #|  total += i;
    #|skip:
    #|  if (i < 5) goto loop;
    #|  return total;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 13L)
}

///|
test "mir body interpreter preserves postfix update value" {
  let source =
    #|int main(void) {
    #|  int i = 4;
    #|  int old = i++;
    #|  return old * 10 + i;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 45L)
}

///|
test "mir body interpreter evaluates scalar address dereference cancellation" {
  let source =
    #|int main(void) {
    #|  int x = 4;
    #|  *&x += 5;
    #|  return *&x;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 9L)
}

///|
test "mir body interpreter handles casted scalar address loads and stores" {
  let source =
    #|int main(void) {
    #|  int x = 0;
    #|  *(int *)(void *)&x = 42;
    #|  return *(int *)(void *)&x;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles scalar local pointers" {
  let source =
    #|int main(void) {
    #|  int x = 4;
    #|  int *p = &x;
    #|  *p += 5;
    #|  return x + *p;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 18L)
}

///|
test "mir body interpreter handles scalar local pointers across calls" {
  let source =
    #|int read_int(int *p) {
    #|  return *p;
    #|}
    #|void store_int(int *p, int value) {
    #|  *p = value;
    #|}
    #|int bump_int(int *p) {
    #|  return ++*p;
    #|}
    #|int main(void) {
    #|  int x = 5;
    #|  if (read_int(&x) != 5) return 1;
    #|  store_int(&x, 37);
    #|  if (x != 37) return 2;
    #|  if (bump_int(&x) != 38) return 3;
    #|  return x + 4;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles local array pointers across calls" {
  let source =
    #|void fill_ints(int *p) {
    #|  p[0] = 12;
    #|  p[1] = 30;
    #|}
    #|int sum_ints(int *p) {
    #|  return p[0] + p[1];
    #|}
    #|void fill_chars(char *p) {
    #|  __builtin_strcpy(p, "ok");
    #|}
    #|int main(void) {
    #|  int a[2];
    #|  fill_ints(a);
    #|  if (sum_ints(a) != 42) return 1;
    #|  char s[4];
    #|  fill_chars(s);
    #|  if (__builtin_strcmp(s, "ok") != 0) return 2;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles scalar local arrays" {
  let source =
    #|int main(void) {
    #|  int a[3];
    #|  a[0] = 4;
    #|  a[1] = a[0] + 5;
    #|  int *p = &a[1];
    #|  p[1] = 7;
    #|  return a[0] + a[1] + a[2];
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 20L)
}

///|
test "mir body interpreter decays ternary local arrays before indexing" {
  let source =
    #|int main(void) {
    #|  int a[2];
    #|  int b[2];
    #|  a[0] = 3;
    #|  a[1] = 5;
    #|  b[0] = 7;
    #|  b[1] = 11;
    #|  return (1 ? a : b)[1] + (0 ? a : b)[0];
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 12L)
}

///|
test "mir body interpreter decays local arrays in call arguments" {
  let source =
    #|int main(void) {
    #|  char dst[4];
    #|  __builtin_bzero(dst, 4);
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles aggregate bzero memory" {
  let source =
    #|struct Pair {
    #|  int a;
    #|  int b;
    #|};
    #|struct Pair global_pair = { 19, 23 };
    #|int main(void) {
    #|  struct Pair local = { 7, 35 };
    #|  struct Pair slots[2];
    #|  slots[0].a = 5;
    #|  slots[0].b = 37;
    #|  __builtin_bzero(&local, sizeof(local));
    #|  __builtin_bzero(&global_pair, sizeof(global_pair));
    #|  __builtin_bzero(&slots[0], sizeof(slots[0]));
    #|  return local.a + local.b + global_pair.a + global_pair.b +
    #|    slots[0].a + slots[0].b + 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles darwin fd helpers" {
  let source =
    #|struct fd_set {
    #|  int fds_bits[32];
    #|};
    #|
    #|int main(void) {
    #|  struct fd_set fds;
    #|  int side = 0;
    #|  __builtin_bzero(&fds, sizeof(fds));
    #|  __darwin_fd_set((side += 1, 9), &fds);
    #|  if (!__darwin_fd_isset((side += 2, 9), &fds)) return 1;
    #|  if (__darwin_fd_isset(8, &fds)) return 2;
    #|  __darwin_fd_set(40, &fds);
    #|  if (!__darwin_fd_isset(40, &fds)) return 3;
    #|  if (__darwin_fd_isset(41, &fds)) return 4;
    #|  __darwin_fd_clr((side += 4, 9), &fds);
    #|  if (__darwin_fd_isset(9, &fds)) return 5;
    #|  __darwin_fd_clr(40, &fds);
    #|  if (__darwin_fd_isset(40, &fds)) return 6;
    #|  return side == 7 ? 42 : side;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles memory builtin first-arg returns" {
  let source =
    #|int main(void) {
    #|  char src[4];
    #|  char dst[4];
    #|  if (__builtin_memcpy(dst, src, 0) != &dst[0]) return 1;
    #|  if (__builtin_memmove(dst, src, 0) != &dst[0]) return 2;
    #|  if (__builtin_memset(dst, 0, 0) != &dst[0]) return 3;
    #|  int n = 0;
    #|  if (__builtin___memcpy_chk(dst, src, 0, n += 8) != &dst[0]) return 4;
    #|  if (__builtin___memmove_chk(dst, src, 0, n += 4) != &dst[0]) return 5;
    #|  if (__builtin___memset_chk(dst, 0, 0, n += 2) != &dst[0]) return 6;
    #|  if (n != 14) return 7;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles string destination builtin returns" {
  let source =
    #|int main(void) {
    #|  char *dst = __builtin_alloca(4);
    #|  int n = 0;
    #|  if (__builtin_strcpy(dst, "") != dst) return 1;
    #|  if (__builtin___strcpy_chk(dst, "", n += 4) != dst) return 2;
    #|  if (__builtin_strcat(dst, "") != dst) return 3;
    #|  if (__builtin___strcat_chk(dst, "", n += 4) != dst) return 4;
    #|  if (__builtin_strncpy(dst, "", 0) != dst) return 5;
    #|  if (__builtin___strncpy_chk(dst, "", 0, n += 4) != dst) return 6;
    #|  if (__builtin_strncat(dst, "", 0) != dst) return 7;
    #|  if (__builtin___strncat_chk(dst, "", 0, n += 4) != dst) return 8;
    #|  if (n != 16) return 9;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles checked strl literal lengths" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(8);
    #|  if (__builtin___strlcpy_chk(dst, (const char *)"abcdef", 4, n += 8) != 6) return 1;
    #|  if (n != 8) return 2;
    #|  if (__builtin___strlcat_chk(dst, (const char *)"abc", 0, n += 16) != 3) return 3;
    #|  if (n != 24) return 4;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles checked printf literal lengths" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  int side = 0;
    #|  char *dst = __builtin_alloca(32);
    #|  if (__builtin___snprintf_chk((char *)0, 0, side += 1, side += 2, (const char *)"n=%d", n += 7) != 3) return 1;
    #|  if (__builtin___sprintf_chk(dst, side += 4, side += 8, (const char *)"%s%%", (const char *)"ok") != 3) return 2;
    #|  if (__builtin___printf_chk(side += 16, (const char *)"x=%x", n) != 3) return 3;
    #|  if (__builtin___fprintf_chk((void *)0, side += 32, (const char *)"%+d", n) != 2) return 4;
    #|  if (__builtin___vsnprintf_chk(dst, 32, side += 64, side += 128, (const char *)"ready", (void *)0) != 5) return 5;
    #|  if (__builtin___vsprintf_chk(dst, side += 256, side += 512, (const char *)"done%%", (void *)0) != 5) return 6;
    #|  if (__builtin___vfprintf_chk((void *)0, side += 1024, (const char *)"ok%%", (void *)0) != 3) return 7;
    #|  if (__builtin___vprintf_chk(side += 2048, (const char *)"go%%", (void *)0) != 3) return 8;
    #|  if (n != 7) return 9;
    #|  if (side != 4095) return 10;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles integer unary builtins" {
  let source =
    #|int main(void) {
    #|  int neg = -7;
    #|  int pos = 5;
    #|  long lneg = -1234567890123L;
    #|  long long llneg = -900000000000000000LL;
    #|  unsigned int u8 = 8u;
    #|  unsigned long ul16 = 16ul;
    #|  unsigned long long ull32 = 32ull;
    #|  unsigned int u0102 = 0x0102u;
    #|  unsigned int u01020304 = 0x01020304u;
    #|  unsigned long long ullswap = 0x0102030405060708ull;
    #|  unsigned int upop = 0x00ff00ffu;
    #|  unsigned long ulpop = 0x00000000fffffffful;
    #|  unsigned long long ullpar = 0x8000000000000001ull;
    #|  if (__builtin_abs(neg) != 7) return 1;
    #|  if (__builtin_abs(pos) != 5) return 2;
    #|  if (__builtin_labs(lneg) != 1234567890123L) return 3;
    #|  if (__builtin_llabs(llneg) != 900000000000000000LL) return 4;
    #|  if (__builtin_ffs(0u) != 0) return 5;
    #|  if (__builtin_ffs(u8) != 4) return 6;
    #|  if (__builtin_ffsl(ul16) != 5) return 7;
    #|  if (__builtin_ffsll(ull32) != 6) return 8;
    #|  if ((__builtin_bswap16(u0102) & 255) != 1) return 9;
    #|  if ((__builtin_bswap32(u01020304) & 255) != 1) return 10;
    #|  if ((__builtin_bswap64(ullswap) & 255) != 1) return 11;
    #|  if ((__builtin_bswap(u01020304) & 255) != 1) return 12;
    #|  if ((__builtin_bswap(ullswap) & 255) != 1) return 13;
    #|  if (__builtin_popcount(upop) != 16) return 14;
    #|  if (__builtin_popcountl(ulpop) != 32) return 15;
    #|  if (__builtin_popcountll(ullswap) != 13) return 16;
    #|  if (__builtin_popcountll(ullpar) != 2) return 17;
    #|  if (__builtin_parity(upop) != 0) return 18;
    #|  if (__builtin_parityl(ulpop) != 0) return 19;
    #|  if (__builtin_parityll(ullpar) != 0) return 20;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles rotate builtins" {
  let source =
    #|int main(void) {
    #|  unsigned int urot = 0x12345678u;
    #|  unsigned long long ullrot = 0x0123456789abcdefull;
    #|  int shift = 8;
    #|  int side = 0;
    #|  if (__builtin_rotateleft32(urot, shift) != 0x34567812u) return 1;
    #|  if ((__builtin_rotateright32(urot, shift) & 255) != 0x56) return 2;
    #|  if ((__builtin_rotateleft64(ullrot, 16) & 255) != 0x23) return 3;
    #|  if ((__builtin_rotateright64(ullrot, 16) & 255) != 0xab) return 4;
    #|  if (__builtin_rotateleft((unsigned int)0x80000001u, 1) != 3u) return 5;
    #|  if (__builtin_rotateright((unsigned long long)1ull, 1) != 0x8000000000000000ull) return 6;
    #|  if (__builtin_rotateleft32((side += 1, urot), (side += 2, shift)) != 0x34567812u) return 7;
    #|  if (side != 3) return 8;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles local array initializers" {
  let source =
    #|int main(void) {
    #|  int a[5] = { 10, 20, 30, 40, 50 };
    #|  int *p = &a[4];
    #|  int *q = &a[1];
    #|  int *r = q + 1;
    #|  return (p - q) + *r;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 33L)
}

///|
test "mir body interpreter handles local array range initializers" {
  let source =
    #|struct Item { int a; int b; };
    #|int main(void) {
    #|  int nums[5] = { [0 ... 2] = 4, [4] = 5 };
    #|  struct Item items[4] = {
    #|    [0 ... 1] = { 3, 4 },
    #|    [3] = { 7, 8 },
    #|  };
    #|  int *p = (int[]){ [0 ... 1] = 5, [2] = 4 };
    #|  return nums[0] + nums[2] + nums[3] + nums[4] +
    #|    items[0].a + items[1].b + items[2].a + items[3].b +
    #|    p[0] + p[1] + p[2];
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles nested local compound literal designators" {
  let source =
    #|struct Inner { int z; int q; };
    #|struct S { int tag; struct Inner inner; int a[3]; };
    #|struct Pair { int a; int b; };
    #|int main(void) {
    #|  struct S s = (struct S){
    #|    .inner.z = 20,
    #|    .inner.q = 2,
    #|    .a[2] = 5,
    #|    .tag = 1,
    #|    .a[0] = 4
    #|  };
    #|  struct Pair *pairs = (struct Pair[]){
    #|    [1].b = 1,
    #|    [0].a = 4,
    #|    [1].a = 5
    #|  };
    #|  return s.tag + s.inner.z + s.inner.q + s.a[0] + s.a[1] + s.a[2] +
    #|    pairs[0].a + pairs[0].b + pairs[1].a + pairs[1].b;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles local scalar brace initializers" {
  let source =
    #|struct S { int a; int b; };
    #|int main(void) {
    #|  int x = {19}, y = {{23}};
    #|  int arr[2] = {{5}, {37}};
    #|  struct S s = {{11}, {31}};
    #|  return x + y == 42 && arr[0] + arr[1] == 42 && s.a + s.b == 42
    #|       ? 42 : 1;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter decays member arrays in pointer differences" {
  let source =
    #|struct S { int a[4]; unsigned char iPrev; };
    #|int main(void) {
    #|  struct S s;
    #|  int *p = &s.a[2];
    #|  s.iPrev = (unsigned char)(p - s.a);
    #|  return s.iPrev;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 2L)
}

///|
test "mir body interpreter decays member arrays in pointer comparisons" {
  let source =
    #|struct S { int *p; int a[2]; };
    #|int main(void) {
    #|  struct S s;
    #|  s.p = s.a;
    #|  return s.p == s.a;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 1L)
}

///|
test "mir body interpreter handles local aggregate array initializers" {
  let source =
    #|struct Item { const char *z; int a; int b; };
    #|int main(void) {
    #|  struct Item items[] = {
    #|    { "x", 1, 2 },
    #|    { "y", 3, 4 },
    #|  };
    #|  return items[1].a + items[0].b;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 5L)
}

///|
test "mir body interpreter copies from global aggregates" {
  let source =
    #|struct Item { int x; int *p; };
    #|static const struct Item zeroItem = {0};
    #|int main(void) {
    #|  struct Item item;
    #|  struct Item *p = &item;
    #|  p->x = 7;
    #|  p->p = (int*)1;
    #|  *p = zeroItem;
    #|  return p->x + (p->p != 0);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 0L)
}

///|
test "mir body interpreter copies aggregate ternary sources" {
  let source =
    #|struct Token { char *z; int n; };
    #|int main(void) {
    #|  struct Token a;
    #|  struct Token b;
    #|  struct Token c;
    #|  a.z = "a";
    #|  a.n = 1;
    #|  b.z = "b";
    #|  b.n = 7;
    #|  c = (a.n == 0 ? a : b);
    #|  int first = c.n;
    #|  a.n = 0;
    #|  c = (a.n == 0 ? a : b);
    #|  return first * 10 + c.n;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 70L)
}

///|
test "mir body interpreter assigns aggregate call-result ternaries" {
  let source =
    #|struct Box { int a; int b; };
    #|int side;
    #|struct Box make(int tag) {
    #|  struct Box box;
    #|  box.a = tag;
    #|  box.b = 42;
    #|  side = side * 10 + tag;
    #|  return box;
    #|}
    #|int pick_false(void) {
    #|  struct Box dst;
    #|  int cond = 0;
    #|  side = 0;
    #|  dst = cond ? make(1) : make(2);
    #|  if (side != 2) return side;
    #|  if (dst.a != 2) return dst.a;
    #|  return dst.b;
    #|}
    #|int pick_true(void) {
    #|  struct Box dst;
    #|  int cond = 1;
    #|  side = 0;
    #|  dst = cond ? make(3) : make(4);
    #|  if (side != 3) return side;
    #|  if (dst.a != 3) return dst.a;
    #|  return dst.b;
    #|}
    #|int main(void) {
    #|  if (pick_false() != 42) return 1;
    #|  if (pick_true() != 42) return 2;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("make"), content="true")
  inspect(mir.bodies.contains("pick_false"), content="true")
  inspect(mir.bodies.contains("pick_true"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles aggregate ternary call arguments" {
  let source =
    #|struct Box { int a; int b; };
    #|struct Desc { int flags; struct Box getter; struct Box setter; };
    #|struct Box dup(struct Box v) { return v; }
    #|int main(void) {
    #|  struct Desc desc;
    #|  desc.flags = 0;
    #|  desc.getter.a = 1;
    #|  desc.getter.b = 2;
    #|  desc.setter.a = 20;
    #|  desc.setter.b = 21;
    #|  struct Box r = dup(desc.flags ? desc.getter : desc.setter);
    #|  return r.a + r.b + 1;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("dup"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter passes aggregate call-result ternary arguments" {
  let source =
    #|struct Box { int a; int b; };
    #|int side;
    #|struct Box make(int tag) {
    #|  struct Box box;
    #|  box.a = tag;
    #|  box.b = 42 - tag;
    #|  side = side * 10 + tag;
    #|  return box;
    #|}
    #|int sum(struct Box box) {
    #|  return box.a + box.b;
    #|}
    #|int pick_false(void) {
    #|  int cond = 0;
    #|  side = 0;
    #|  int value = sum(cond ? make(1) : make(2));
    #|  if (side != 2) return side;
    #|  return value;
    #|}
    #|int pick_true(void) {
    #|  int cond = 1;
    #|  side = 0;
    #|  int value = sum(cond ? make(3) : make(4));
    #|  if (side != 3) return side;
    #|  return value;
    #|}
    #|int main(void) {
    #|  if (pick_false() != 42) return 1;
    #|  if (pick_true() != 42) return 2;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("make"), content="true")
  inspect(mir.bodies.contains("sum"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter reads members from aggregate call-result ternaries" {
  let source =
    #|struct Box { int a; int b; };
    #|int side;
    #|struct Box make(int tag) {
    #|  struct Box box;
    #|  box.a = tag;
    #|  box.b = 42 - tag;
    #|  side = side * 10 + tag;
    #|  return box;
    #|}
    #|int pick_false(void) {
    #|  int cond = 0;
    #|  side = 0;
    #|  int value = (cond ? make(5) : make(6)).a;
    #|  if (side != 6) return side;
    #|  return value + 36;
    #|}
    #|int pick_true(void) {
    #|  int cond = 1;
    #|  side = 0;
    #|  int value = (cond ? make(7) : make(8)).a;
    #|  if (side != 7) return side;
    #|  return value + 35;
    #|}
    #|int main(void) {
    #|  if (pick_false() != 42) return 1;
    #|  if (pick_true() != 42) return 2;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("make"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter initializes locals from aggregate call-result ternaries" {
  let source =
    #|struct Box { int a; int b; };
    #|int side;
    #|struct Box make(int tag) {
    #|  struct Box box;
    #|  box.a = tag;
    #|  box.b = 42 - tag;
    #|  side = side * 10 + tag;
    #|  return box;
    #|}
    #|int pick_false(void) {
    #|  int cond = 0;
    #|  side = 0;
    #|  struct Box box = cond ? make(1) : make(2);
    #|  if (side != 2) return side;
    #|  return box.a + box.b;
    #|}
    #|int pick_true(void) {
    #|  int cond = 1;
    #|  side = 0;
    #|  struct Box box = cond ? make(3) : make(4);
    #|  if (side != 3) return side;
    #|  return box.a + box.b;
    #|}
    #|int main(void) {
    #|  if (pick_false() != 42) return 1;
    #|  if (pick_true() != 42) return 2;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("make"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter returns aggregate call-result ternaries" {
  let source =
    #|struct Box { int a; int b; };
    #|int side;
    #|struct Box make(int tag) {
    #|  struct Box box;
    #|  box.a = tag;
    #|  box.b = 42 - tag;
    #|  side = side * 10 + tag;
    #|  return box;
    #|}
    #|struct Box pick(int cond) {
    #|  return cond ? make(5) : make(6);
    #|}
    #|int main(void) {
    #|  side = 0;
    #|  struct Box a = pick(0);
    #|  if (side != 6) return side;
    #|  if (a.a + a.b != 42) return 1;
    #|  side = 0;
    #|  struct Box b = pick(1);
    #|  if (side != 5) return side;
    #|  return b.a + b.b;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("make"), content="true")
  inspect(mir.bodies.contains("pick"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter passes aggregate compound literal ternary arguments" {
  let source =
    #|struct Box { int a; int b; };
    #|int sum(struct Box box) {
    #|  return box.a + box.b;
    #|}
    #|int main(void) {
    #|  int cond = 0;
    #|  if (sum(cond ? (struct Box){ 1, 2 } : (struct Box){ 19, 23 }) != 42) {
    #|    return 1;
    #|  }
    #|  cond = 1;
    #|  return sum(cond ? (struct Box){ 20, 22 } : (struct Box){ 3, 4 });
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("sum"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter returns aggregate compound literal ternaries" {
  let source =
    #|struct Box { int a; int b; };
    #|struct Box pick(int cond) {
    #|  return cond ? (struct Box){ 20, 22 } : (struct Box){ 19, 23 };
    #|}
    #|int main(void) {
    #|  struct Box a = pick(0);
    #|  if (a.a + a.b != 42) return 1;
    #|  struct Box b = pick(1);
    #|  return b.a + b.b;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("pick"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter assigns aggregate compound literal ternaries" {
  let source =
    #|struct Box { int a; int b; };
    #|int main(void) {
    #|  struct Box rval;
    #|  int found = 0;
    #|  rval = !found ? (struct Box){ 1, 41 } : (struct Box){ 1, 2 };
    #|  return rval.a + rval.b;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter ignores side effect free aggregate void casts" {
  let source =
    #|struct Token { int n; };
    #|int main(void) {
    #|  struct Token t;
    #|  t.n = 42;
    #|  (void)t;
    #|  return t.n;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles fixed local string array initializers" {
  let source =
    #|int main(void) {
    #|  char s[5] = "abc";
    #|  char exact[3] = "xyz";
    #|  if (s[0] != 'a' || s[1] != 'b' || s[2] != 'c') return 1;
    #|  if (s[3] != 0 || s[4] != 0) return 2;
    #|  if (exact[0] != 'x' || exact[1] != 'y' || exact[2] != 'z') return 3;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles scalar memory prefix updates" {
  let source =
    #|struct S { int x; };
    #|int main(void) {
    #|  int x = 4;
    #|  int *p = &x;
    #|  int a[2];
    #|  struct S s;
    #|  a[0] = 2;
    #|  s.x = 7;
    #|  ++*p;
    #|  --a[0];
    #|  ++s.x;
    #|  return x + a[0] + s.x;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 14L)
}

///|
test "mir body interpreter handles side effecting scalar memory prefix updates" {
  let source =
    #|int main(void) {
    #|  int a[2];
    #|  int i = 0;
    #|  a[0] = 4;
    #|  int got = ++a[i++];
    #|  return got * 10 + a[0] + i;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 56L)
}

///|
test "mir body interpreter handles side effecting scalar memory compound updates" {
  let source =
    #|int main(void) {
    #|  int a[2];
    #|  int i = 0;
    #|  a[0] = 4;
    #|  int got = (a[i++] += 3);
    #|  return got * 10 + a[0] + i;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 78L)
}

///|
test "mir body interpreter handles side effecting non-additive compound updates" {
  let source =
    #|int main(void) {
    #|  int a[2];
    #|  int i = 0;
    #|  a[0] = 4;
    #|  int got = (a[i++] *= 3);
    #|  return got * 10 + a[0] + i;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 133L)
}

///|
test "mir body interpreter handles scalar memory postfix updates" {
  let source =
    #|struct S { int x; };
    #|int main(void) {
    #|  int x = 4;
    #|  int *p = &x;
    #|  int a[2];
    #|  int i = 0;
    #|  struct S s;
    #|  a[0] = 9;
    #|  s.x = 7;
    #|  int old_p = (*p)++;
    #|  int old_a = a[i++]--;
    #|  int old_s = s.x++;
    #|  return old_p * 1000 + old_a * 100 + old_s * 10 + x + a[0] + s.x + i;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 4992L)
}

///|
test "mir body interpreter folds scalar builtin calls" {
  let source =
    #|int main(void) {
    #|  int x = 0;
    #|  return __builtin_constant_p(1 + 2) * 10 +
    #|    __builtin_constant_p(x) +
    #|    __builtin_unpredictable(5) +
    #|    (__builtin_bswap32(0x01020304u) == 0x04030201u) +
    #|    __builtin_flt_rounds() +
    #|    (__builtin_object_size("abc", 0) == 4) +
    #|    (__builtin_dynamic_object_size("a\0bc", 2) == 5) +
    #|    (__builtin_object_size(&x, 0) == sizeof(x)) +
    #|    (__builtin_strlen((char *)"hello") == 5) +
    #|    (__builtin_strlen("a\0bc") == 1);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 22L)
}

///|
test "mir body interpreter handles constant query builtins" {
  let source =
    #|int main(void) {
    #|  int side = 0;
    #|  if (!__builtin_constant_p(1 + 2)) return 1;
    #|  if (__builtin_constant_p(side)) return 2;
    #|  if (__builtin_constant_p(side += 1)) return 3;
    #|  if (side != 0) return 4;
    #|  if (__builtin_constant_p(1 / 0)) return 5;
    #|  if (__builtin_flt_rounds() != 1) return 6;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles side effect free identity builtins" {
  let source =
    #|int main(void) {
    #|  int x = 4;
    #|  void *p = (void *)32;
    #|  void *ra = (void *)77;
    #|  return __builtin_expect(x, 1) +
    #|    __builtin_expect_with_probability(x, 0, 0.9) +
    #|    ((unsigned long)__builtin_assume_aligned(p, 16) == 32ul) +
    #|    ((unsigned long)__builtin_extract_return_addr(ra) == 77ul) +
    #|    ((unsigned long)__builtin_frob_return_addr(ra) == 77ul);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 11L)
}

///|
test "mir body interpreter handles no-op builtins" {
  let source =
    #|int main(void) {
    #|  int side = 0;
    #|  char buf[16];
    #|  __builtin_prefetch((void *)(long)(side += 1), 0, 0);
    #|  __builtin___clear_cache(buf + (side += 2), buf + (side += 4));
    #|  __builtin_assume(side += 10);
    #|  return side + 35;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles object size builtins" {
  let source =
    #|struct S { int x; char buf[9]; };
    #|char global_buf[16];
    #|struct S global_s;
    #|int main(void) {
    #|  int side = 0;
    #|  int x;
    #|  char buf[16];
    #|  struct S local_s;
    #|  if (__builtin_object_size("abc", 0) != 4) return 1;
    #|  if (__builtin_dynamic_object_size((const void *)"hello", 3) != 6) return 2;
    #|  if (__builtin_object_size((void *)1, 0) + 1 != 0) return 3;
    #|  if (__builtin_object_size((void *)1, 2) != 0) return 4;
    #|  if (__builtin_dynamic_object_size((void *)(long)(side += 1), side += 2) + 1 != 0) return 5;
    #|  if (side != 0) return 6;
    #|  if (__builtin_object_size(&x, 0) != sizeof(x)) return 7;
    #|  if (__builtin_dynamic_object_size((void *)buf, 2) != sizeof(buf)) return 8;
    #|  if (__builtin_object_size(&buf[3], 1) != sizeof(buf) - 3) return 9;
    #|  if (__builtin_object_size(buf + 3, 0) != sizeof(buf) - 3) return 10;
    #|  if (__builtin_object_size(&global_s.buf, 0) != sizeof(global_s) - __builtin_offsetof(struct S, buf)) return 11;
    #|  if (__builtin_dynamic_object_size(global_s.buf, 3) != sizeof(global_s.buf)) return 12;
    #|  if (__builtin_dynamic_object_size(&global_s.buf[4], 2) != sizeof(global_s) - __builtin_offsetof(struct S, buf) - 4) return 13;
    #|  if (__builtin_object_size(&local_s.buf, 0) != sizeof(local_s) - __builtin_offsetof(struct S, buf)) return 14;
    #|  if (__builtin_dynamic_object_size(local_s.buf, 3) != sizeof(local_s.buf)) return 15;
    #|  if (__builtin_dynamic_object_size((void *)global_buf, 2) != sizeof(global_buf)) return 16;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles alloca return size and nullness" {
  let source =
    #|int main(void) {
    #|  int n = 16;
    #|  void *p = __builtin_alloca(n += 1);
    #|  if (n != 17) return 1;
    #|  if (p == 0) return 2;
    #|  char *a = __builtin_alloca(n += 2);
    #|  char *b = __builtin_alloca(n += 3);
    #|  if (n != 22) return 3;
    #|  if (a == 0 || b == 0) return 4;
    #|  if (a == b || a == p || b == p) return 5;
    #|  char *c = __builtin_alloca_with_align(n += 4, 256);
    #|  if (n != 26) return 6;
    #|  if (c == 0 || (((unsigned long)c) & 31ul) != 0) return 7;
    #|  return sizeof(__builtin_alloca(16)) +
    #|    sizeof(__builtin_alloca_with_align(16, 256)) + 26;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles aligned alloca memory" {
  let source =
    #|int main(void) {
    #|  int n = 5;
    #|  char *p = __builtin_alloca_with_align(n += 3, 256);
    #|  p[0] = 40;
    #|  p[7] = 2;
    #|  if ((((unsigned long)p) & 31ul) != 0) return 1;
    #|  return p[0] + p[7] + (n == 8 ? 0 : 2);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles alloca memory loads and stores" {
  let source =
    #|int main(void) {
    #|  char *bytes = __builtin_alloca(4);
    #|  int *words = __builtin_alloca(8);
    #|  bytes[0] = 40;
    #|  bytes[1] = 2;
    #|  words[0] = 11;
    #|  words[1] = 31;
    #|  return bytes[0] + bytes[1] + words[0] + words[1] - 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles alloca memory updates" {
  let source =
    #|int main(void) {
    #|  int *p = __builtin_alloca(8);
    #|  p[0] = 40;
    #|  ++p[0];
    #|  p[1] = p[0]++;
    #|  return p[0] + p[1] - 41;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles alloca pointers across calls" {
  let source =
    #|void fill(char *p) {
    #|  p[0] = 40;
    #|  p[1] = 2;
    #|}
    #|int sum(char *p) {
    #|  return p[0] + p[1];
    #|}
    #|int main(void) {
    #|  char *p = __builtin_alloca(2);
    #|  fill(p);
    #|  return sum(p);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles alloca aggregate memory" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern void *memset(void *, int, size_t);
    #|struct Pair {
    #|  int a;
    #|  double b;
    #|  char tag;
    #|};
    #|int main(void) {
    #|  struct Pair *p = __builtin_alloca(sizeof(struct Pair) * 3);
    #|  struct Pair *q = __builtin_alloca(sizeof(struct Pair));
    #|  memset(p, 0, sizeof(struct Pair) * 3);
    #|  memset(q, 0, sizeof(struct Pair));
    #|  if (p[0].a != 0 || (int)p[0].b != 0 || p[1].tag != 0) return 1;
    #|  p[0].a = 9;
    #|  p[0].b = 1.5;
    #|  p[0].tag = 4;
    #|  if (memcpy(q, p, sizeof(*q)) != q) return 2;
    #|  if (q->a != 9 || (int)(q->b * 2.0) != 3 || q->tag != 4) return 3;
    #|  p[1] = *q;
    #|  if (p[1].a != 9 || (int)(p[1].b * 2.0) != 3 || p[1].tag != 4) return 4;
    #|  p[2].a = p[0].a + p[1].a;
    #|  p[2].b = p[0].b + p[1].b;
    #|  p[2].tag = p[0].tag + p[1].tag;
    #|  if (p[2].a != 18) return 5;
    #|  if ((int)(p[2].b * 10.0) != 30) return 6;
    #|  if (p[2].tag != 8) return 7;
    #|  memset(q, 0, sizeof(*q));
    #|  if (q->a != 0 || (int)q->b != 0 || q->tag != 0) return 8;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles alloca aggregate pointers across calls" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memset(void *, int, size_t);
    #|struct Pair {
    #|  int a;
    #|  double b;
    #|  char tag;
    #|};
    #|void fill_pair(struct Pair *p) {
    #|  p[0].a = 11;
    #|  p[0].b = 2.0;
    #|  p[0].tag = 5;
    #|  p[1] = p[0];
    #|}
    #|int observe_pair(struct Pair *p) {
    #|  if (p[0].a != 11 || (int)(p[0].b * 10.0) != 20 || p[0].tag != 5) return 1;
    #|  if (p[1].a != 11 || (int)(p[1].b * 10.0) != 20 || p[1].tag != 5) return 2;
    #|  return p[0].a + p[1].a + (int)(p[0].b * 5.0) + (int)(p[1].b * 5.0);
    #|}
    #|int main(void) {
    #|  struct Pair *p = __builtin_alloca(sizeof(struct Pair) * 2);
    #|  memset(p, 0, sizeof(struct Pair) * 2);
    #|  fill_pair(p);
    #|  return observe_pair(p);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles alloca aggregate pointers across indirect calls" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memset(void *, int, size_t);
    #|struct Pair {
    #|  int a;
    #|  double b;
    #|  char tag;
    #|};
    #|void fill_pair(struct Pair *p) {
    #|  p[0].a = 12;
    #|  p[0].b = 1.5;
    #|  p[0].tag = 6;
    #|  p[1] = p[0];
    #|}
    #|int observe_pair(struct Pair *p) {
    #|  if (p[0].a != 12 || (int)(p[0].b * 10.0) != 15 || p[0].tag != 6) return 1;
    #|  if (p[1].a != 12 || (int)(p[1].b * 10.0) != 15 || p[1].tag != 6) return 2;
    #|  return p[0].a + p[1].a + (int)(p[0].b * 6.0) + (int)(p[1].b * 6.0);
    #|}
    #|int main(void) {
    #|  void (*fill)(struct Pair *) = fill_pair;
    #|  int (*observe)(struct Pair *) = observe_pair;
    #|  struct Pair *p = __builtin_alloca(sizeof(struct Pair) * 2);
    #|  memset(p, 0, sizeof(struct Pair) * 2);
    #|  fill(p);
    #|  return observe(p);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter passes alloca aggregate call arguments" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memset(void *, int, size_t);
    #|struct Pair {
    #|  int a;
    #|  double b;
    #|  char tag;
    #|};
    #|int score(struct Pair p) {
    #|  return p.a + (int)(p.b * 10.0) + p.tag;
    #|}
    #|int main(void) {
    #|  struct Pair *p = __builtin_alloca(sizeof(struct Pair));
    #|  memset(p, 0, sizeof(struct Pair));
    #|  p->a = 7;
    #|  p->b = 2.5;
    #|  p->tag = 10;
    #|  if ((int)(p->b * 10.0) != 25) return 100;
    #|  return score(*p);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter passes alloca aggregate variadic arguments" {
  let source =
    #|typedef unsigned long size_t;
    #|typedef __builtin_va_list va_list;
    #|extern void *memset(void *, int, size_t);
    #|struct Pair {
    #|  int a;
    #|  double b;
    #|  char tag;
    #|};
    #|int score(int seed, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, seed);
    #|  struct Pair p = __builtin_va_arg(ap, struct Pair);
    #|  __builtin_va_end(ap);
    #|  return seed + p.a + (int)(p.b * 10.0) + p.tag;
    #|}
    #|int main(void) {
    #|  struct Pair *p = __builtin_alloca(sizeof(struct Pair));
    #|  memset(p, 0, sizeof(struct Pair));
    #|  p->a = 5;
    #|  p->b = 2.0;
    #|  p->tag = 12;
    #|  if ((int)(p->b * 10.0) != 20) return 100;
    #|  return score(5, *p);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter returns alloca aggregate values" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memset(void *, int, size_t);
    #|struct Pair {
    #|  int a;
    #|  double b;
    #|  char tag;
    #|};
    #|struct Pair make_pair(void) {
    #|  struct Pair *p = __builtin_alloca(sizeof(struct Pair));
    #|  memset(p, 0, sizeof(struct Pair));
    #|  p->a = 8;
    #|  p->b = 2.5;
    #|  p->tag = 9;
    #|  return *p;
    #|}
    #|int main(void) {
    #|  struct Pair p = make_pair();
    #|  if ((int)(p.b * 10.0) != 25) return 100;
    #|  return p.a + (int)(p.b * 10.0) + p.tag;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles malloc memory libcalls" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *malloc(size_t);
    #|extern void *calloc(size_t, size_t);
    #|extern void free(void *);
    #|int main(void) {
    #|  char *src = malloc(8);
    #|  char *dst = calloc(8, 1);
    #|  if (!src || !dst) return 1;
    #|  __builtin_memset(src, 'A', 4);
    #|  src[4] = 0;
    #|  if (__builtin_strlen(src) != 4) return 2;
    #|  __builtin_memcpy(dst, src, 5);
    #|  int result = dst[0] + dst[3] - 88;
    #|  free(src);
    #|  free(dst);
    #|  return result;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles builtin heap libcalls" {
  let source =
    #|int main(void) {
    #|  char *p = __builtin_malloc(4);
    #|  char *q = __builtin_calloc(4, 1);
    #|  if (!p || !q) return 1;
    #|  if (q[0] != 0 || q[3] != 0) return 2;
    #|  p[0] = 'a';
    #|  p[1] = 'b';
    #|  p[2] = 0;
    #|  q[0] = 'x';
    #|  q[1] = 0;
    #|  p = __builtin_realloc(p, 8);
    #|  if (!p) return 3;
    #|  if (__builtin_strcmp(p, "ab") != 0) return 4;
    #|  char *s = __builtin_strdup("hi");
    #|  char *t = __builtin_strndup("wxyz", 2);
    #|  if (!s || !t) return 5;
    #|  if (__builtin_strcmp(s, "hi") != 0) return 6;
    #|  if (__builtin_strcmp(t, "wx") != 0) return 7;
    #|  int result = __builtin_strlen(p) + __builtin_strlen(q) +
    #|    __builtin_strlen(s) + __builtin_strlen(t) + p[0] - 62;
    #|  __builtin_free(p);
    #|  __builtin_free(q);
    #|  __builtin_free(s);
    #|  __builtin_free(t);
    #|  return result;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles realloc memory preservation" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *malloc(size_t);
    #|extern void *realloc(void *, size_t);
    #|extern void free(void *);
    #|int main(void) {
    #|  char *p = malloc(4);
    #|  if (!p) return 1;
    #|  p[0] = 'a';
    #|  p[1] = 'b';
    #|  p[2] = 0;
    #|  p = realloc(p, 8);
    #|  if (!p) return 2;
    #|  if (__builtin_strcmp(p, "ab") != 0) return 3;
    #|  p[2] = 'c';
    #|  p[3] = 0;
    #|  int result = __builtin_strlen(p) + p[0] - 58;
    #|  free(p);
    #|  return result;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles heap aggregate memory" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *malloc(size_t);
    #|extern void *calloc(size_t, size_t);
    #|extern void *realloc(void *, size_t);
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern void *memset(void *, int, size_t);
    #|extern void free(void *);
    #|struct Pair {
    #|  int a;
    #|  double b;
    #|  char tag;
    #|};
    #|int main(void) {
    #|  struct Pair *p = calloc(2, sizeof(struct Pair));
    #|  if (!p) return 1;
    #|  if (p[0].a != 0 || (int)p[0].b != 0 || p[1].tag != 0) return 2;
    #|  p[0].a = 7;
    #|  p[0].b = 2.5;
    #|  p[0].tag = 3;
    #|  struct Pair *q = malloc(sizeof(struct Pair));
    #|  if (!q) return 3;
    #|  if (memcpy(q, p, sizeof(*q)) != q) return 4;
    #|  if (q->a != 7 || (int)(q->b * 2.0) != 5 || q->tag != 3) return 5;
    #|  p = realloc(p, sizeof(struct Pair) * 3);
    #|  if (!p) return 6;
    #|  if (p[0].a != 7 || (int)(p[0].b * 2.0) != 5 || p[0].tag != 3) return 7;
    #|  p[1] = *q;
    #|  if (p[1].a != 7) return 8;
    #|  p[2].a = p[0].a + p[1].a;
    #|  p[2].b = p[0].b + p[1].b;
    #|  p[2].tag = p[0].tag + p[1].tag;
    #|  if (p[2].a != 14) return 9;
    #|  if ((int)(p[2].b * 10.0) != 50) return 10;
    #|  if (p[2].tag != 6) return 11;
    #|  memset(q, 0, sizeof(*q));
    #|  if (q->a != 0 || (int)q->b != 0 || q->tag != 0) return 12;
    #|  free(q);
    #|  free(p);
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter invalidates freed heap memory" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *malloc(size_t);
    #|extern void free(void *);
    #|int main(void) {
    #|  char *nil = 0;
    #|  free(nil);
    #|  char *p = malloc(4);
    #|  if (!p) return 1;
    #|  p[0] = 42;
    #|  if (p[0] != 42) return 2;
    #|  free(p);
    #|  return p[0];
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  match mir.interpret_body_i64("main", []) {
    Ok(_) => abort("expected freed heap memory to be unsupported")
    Err(err) => inspect(err.contains("load address"), content="true")
  }
}

///|
test "mir body interpreter handles strdup heap memory" {
  let source =
    #|typedef unsigned long size_t;
    #|extern char *strdup(const char *);
    #|extern char *strndup(const char *, size_t);
    #|extern void free(void *);
    #|int main(void) {
    #|  char *p = strdup("hi");
    #|  if (!p) return 1;
    #|  if (__builtin_strcmp(p, "hi") != 0) return 2;
    #|  p[1] = 'o';
    #|  if (__builtin_strcmp(p, "ho") != 0) return 3;
    #|  char *q = strndup("abcdef", 3);
    #|  if (!q) return 4;
    #|  if (__builtin_strcmp(q, "abc") != 0) return 5;
    #|  int result = __builtin_strlen(p) + __builtin_strlen(q) + p[1] + q[2] - 173;
    #|  free(p);
    #|  free(q);
    #|  return result;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles posix_memalign heap memory" {
  let source =
    #|typedef unsigned long size_t;
    #|extern int posix_memalign(char **, size_t, size_t);
    #|extern void free(void *);
    #|int main(void) {
    #|  char *p = 0;
    #|  int rc = posix_memalign(&p, 32, 8);
    #|  if (rc != 0) return rc;
    #|  if (!p) return 1;
    #|  if ((((unsigned long)p) & 31ul) != 0) return 2;
    #|  p[0] = 40;
    #|  p[7] = 2;
    #|  int result = p[0] + p[7];
    #|  free(p);
    #|  return result;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles aligned_alloc heap memory" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *aligned_alloc(size_t, size_t);
    #|extern void free(void *);
    #|int main(void) {
    #|  char *p = aligned_alloc(32, 32);
    #|  if (!p) return 1;
    #|  if ((((unsigned long)p) & 31ul) != 0) return 2;
    #|  p[0] = 17;
    #|  p[31] = 25;
    #|  int result = p[0] + p[31];
    #|  free(p);
    #|  return result;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles valloc and malloc_size heap facts" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *valloc(size_t);
    #|extern size_t malloc_size(const void *);
    #|extern void free(void *);
    #|int main(void) {
    #|  char *p = valloc(32);
    #|  if (!p) return 1;
    #|  if ((((unsigned long)p) & 4095ul) != 0) return 2;
    #|  if (malloc_size(0) != 0) return 3;
    #|  if (malloc_size(p) < 32) return 4;
    #|  p[0] = 17;
    #|  p[31] = 25;
    #|  int result = p[0] + p[31];
    #|  free(p);
    #|  return result;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter uses alloca memory for byte libcalls" {
  let source =
    #|int main(void) {
    #|  char *text = __builtin_alloca(5);
    #|  text[0] = 'o';
    #|  text[1] = 'k';
    #|  text[2] = 0;
    #|  text[3] = 'x';
    #|  if (__builtin_strlen(text) != 2) return 1;
    #|  if (__builtin_strcmp(text, "ok") != 0) return 2;
    #|  if (__builtin_memchr(text, 'k', 3) != text + 1) return 3;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models memory libcall byte effects" {
  let source =
    #|int main(void) {
    #|  char src[6];
    #|  char dst[6];
    #|  src[0] = 'a';
    #|  src[1] = 'b';
    #|  src[2] = 'c';
    #|  src[3] = 0;
    #|  __builtin_memcpy(dst, src, 4);
    #|  if (__builtin_strcmp(dst, "abc") != 0) return 1;
    #|  __builtin_memset(dst + 1, 'x', 2);
    #|  if (__builtin_memcmp(dst, "axx", 3) != 0) return 2;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models declared memory and string libcalls" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern void *memmove(void *, const void *, size_t);
    #|extern void *memset(void *, int, size_t);
    #|extern int memcmp(const void *, const void *, size_t);
    #|extern size_t strlen(const char *);
    #|extern int strcmp(const char *, const char *);
    #|extern char *strcpy(char *, const char *);
    #|extern char *strcat(char *, const char *);
    #|extern char *strchr(const char *, int);
    #|extern char *strstr(const char *, const char *);
    #|int main(void) {
    #|  char src[8];
    #|  char dst[16];
    #|  if (strcpy(src, "abc") != src) return 1;
    #|  if (strlen(src) != 3) return 2;
    #|  if (memcpy(dst, src, 4) != dst) return 3;
    #|  if (strcmp(dst, "abc") != 0) return 4;
    #|  if (memset(dst + 1, 'x', 2) != dst + 1) return 5;
    #|  if (memcmp(dst, "axx", 3) != 0) return 6;
    #|  strcpy(src, "wxyz");
    #|  memmove(src + 1, src, 3);
    #|  if (strcmp(src, "wwxy") != 0) return 7;
    #|  strcpy(dst, "hi");
    #|  if (strcat(dst, "!") != dst) return 8;
    #|  if (strchr(dst, '!') != dst + 2) return 9;
    #|  if (strstr(dst, "i!") != dst + 1) return 10;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models declared BSD memory libcalls" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void bzero(void *, size_t);
    #|extern void bcopy(const void *, void *, size_t);
    #|extern int bcmp(const void *, const void *, size_t);
    #|extern int strcmp(const char *, const char *);
    #|int main(void) {
    #|  char src[8];
    #|  char dst[8];
    #|  src[0] = 'a';
    #|  src[1] = 'b';
    #|  src[2] = 'c';
    #|  src[3] = 0;
    #|  bzero(dst, 8);
    #|  if (dst[0] != 0 || dst[7] != 0) return 1;
    #|  bcopy(src, dst, 4);
    #|  if (strcmp(dst, "abc") != 0) return 2;
    #|  if (bcmp(src, dst, 4) != 0) return 3;
    #|  dst[1] = 'x';
    #|  if (bcmp(src, dst, 3) == 0) return 4;
    #|  bcopy(dst, dst + 1, 3);
    #|  if (dst[0] != 'a' || dst[1] != 'a' || dst[2] != 'x' || dst[3] != 'c') return 5;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models declared strnlen and memccpy" {
  let source =
    #|typedef unsigned long size_t;
    #|extern size_t strnlen(const char *, size_t);
    #|extern void *memccpy(void *, const void *, int, size_t);
    #|extern int strcmp(const char *, const char *);
    #|int main(void) {
    #|  char src[8];
    #|  char dst[8];
    #|  src[0] = 'a';
    #|  src[1] = 'b';
    #|  src[2] = 'c';
    #|  src[3] = 0;
    #|  src[4] = 'd';
    #|  if (strnlen(src, 8) != 3) return 1;
    #|  if (strnlen(src, 2) != 2) return 2;
    #|  char *hit = memccpy(dst, src, 'c', 8);
    #|  if (hit != dst + 3) return 3;
    #|  dst[3] = 0;
    #|  if (strcmp(dst, "abc") != 0) return 4;
    #|  src[0] = 'x';
    #|  src[1] = 'y';
    #|  src[2] = 'z';
    #|  src[3] = 0;
    #|  if (memccpy(dst, src, 'q', 4) != 0) return 5;
    #|  if (strcmp(dst, "xyz") != 0) return 6;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models declared memmem" {
  let source =
    #|typedef unsigned long size_t;
    #|extern char *memmem(const void *, size_t, const void *, size_t);
    #|int main(void) {
    #|  char hay[8];
    #|  char needle[3];
    #|  hay[0] = 'a';
    #|  hay[1] = 0;
    #|  hay[2] = 'b';
    #|  hay[3] = 'c';
    #|  hay[4] = 0;
    #|  hay[5] = 'b';
    #|  hay[6] = 'c';
    #|  hay[7] = 0;
    #|  needle[0] = 0;
    #|  needle[1] = 'b';
    #|  needle[2] = 'c';
    #|  if (memmem(hay, 8, needle, 3) != hay + 1) return 1;
    #|  if (memmem(hay + 2, 4, "bc", 2) != hay + 2) return 2;
    #|  if (memmem(hay, 2, "bc", 2) != 0) return 3;
    #|  if (memmem(hay, 8, hay + 7, 0) != 0) return 4;
    #|  if (memmem(hay, 8, "bd", 2) != 0) return 5;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models target-specific memmem empty needle" {
  let source =
    #|typedef unsigned long size_t;
    #|extern char *memmem(const void *, size_t, const void *, size_t);
    #|int main(void) {
    #|  char hay[1];
    #|  hay[0] = 'x';
    #|  if (memmem(hay, 1, hay, 0) != hay) return 1;
    #|  return 42;
    #|}
  let target = linux_target()
  let mir = @mir.lower(@parser.parse_for_target(source, target), target)
  match mir.interpret_body_i64("main", []) {
    Ok(value) => assert_eq(value, 42L)
    Err(err) => abort(err)
  }
}

///|
test "mir body interpreter models declared string span libcalls" {
  let source =
    #|typedef unsigned long size_t;
    #|extern size_t strspn(const char *, const char *);
    #|extern size_t strcspn(const char *, const char *);
    #|extern char *strpbrk(const char *, const char *);
    #|int main(void) {
    #|  char s[10];
    #|  char reject[3];
    #|  char accept[3];
    #|  s[0] = 'a';
    #|  s[1] = 'b';
    #|  s[2] = 'c';
    #|  s[3] = '1';
    #|  s[4] = '2';
    #|  s[5] = '3';
    #|  s[6] = 'x';
    #|  s[7] = 'y';
    #|  s[8] = 'z';
    #|  s[9] = 0;
    #|  reject[0] = '2';
    #|  reject[1] = 'z';
    #|  reject[2] = 0;
    #|  accept[0] = 'x';
    #|  accept[1] = 'y';
    #|  accept[2] = 0;
    #|  if (strspn(s, "abc") != 3) return 1;
    #|  if (strspn(s, "") != 0) return 2;
    #|  if (strspn(s + 3, "12345") != 3) return 3;
    #|  if (strcspn(s, reject) != 4) return 4;
    #|  if (strcspn(s, "") != 9) return 5;
    #|  if (strpbrk(s, accept) != s + 6) return 6;
    #|  if (strpbrk(s, "31") != s + 3) return 7;
    #|  if (strpbrk(s, "") != 0) return 8;
    #|  if (strpbrk(s, "q") != 0) return 9;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models declared case-insensitive and BSD string libcalls" {
  let source =
    #|typedef unsigned long size_t;
    #|extern int strcasecmp(const char *, const char *);
    #|extern int strncasecmp(const char *, const char *, size_t);
    #|extern char *strcasestr(const char *, const char *);
    #|extern char *index(const char *, int);
    #|extern char *rindex(const char *, int);
    #|int main(void) {
    #|  char s[7];
    #|  s[0] = 'A';
    #|  s[1] = 'b';
    #|  s[2] = 'C';
    #|  s[3] = 'a';
    #|  s[4] = 'B';
    #|  s[5] = 'c';
    #|  s[6] = 0;
    #|  if (strcasecmp("AbC", "aBc") != 0) return 1;
    #|  if (strcasecmp("abc", "abd") >= 0) return 2;
    #|  if (strcasecmp("abe", "abd") <= 0) return 3;
    #|  if (strncasecmp("AbD", "aBc", 2) != 0) return 4;
    #|  if (strncasecmp("AbD", "aBc", 3) <= 0) return 5;
    #|  if (strncasecmp(s, "zz", 0) != 0) return 6;
    #|  if (strcasestr(s, "ca") != s + 2) return 7;
    #|  if (strcasestr(s, "BC") != s + 1) return 8;
    #|  if (strcasestr(s, "") != s) return 9;
    #|  if (strcasestr(s, "qq") != 0) return 10;
    #|  if (index(s, 'B') != s + 4) return 11;
    #|  if (rindex(s, 'a') != s + 3) return 12;
    #|  if (rindex(s, 'A') != s) return 13;
    #|  if (index(s, 'z') != 0) return 14;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models declared strsep" {
  let source =
    #|extern char *strsep(char **, const char *);
    #|extern int strcmp(const char *, const char *);
    #|int main(void) {
    #|  char text[8];
    #|  text[0] = 'a';
    #|  text[1] = 'b';
    #|  text[2] = ',';
    #|  text[3] = 'c';
    #|  text[4] = 'd';
    #|  text[5] = ',';
    #|  text[6] = 0;
    #|  text[7] = 'z';
    #|  char *p = text;
    #|  char *first = strsep(&p, ",");
    #|  if (first != text) return 1;
    #|  if (p != text + 3) return 2;
    #|  if (text[2] != 0) return 3;
    #|  if (strcmp(first, "ab") != 0) return 4;
    #|  char *second = strsep(&p, ",");
    #|  if (second != text + 3) return 5;
    #|  if (p != text + 6) return 6;
    #|  if (text[5] != 0) return 7;
    #|  if (strcmp(second, "cd") != 0) return 8;
    #|  char *third = strsep(&p, ",");
    #|  if (third != text + 6) return 9;
    #|  if (p != 0) return 10;
    #|  if (strcmp(third, "") != 0) return 11;
    #|  if (strsep(&p, ",") != 0) return 12;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models declared strtok" {
  let source =
    #|extern char *strtok(char *, const char *);
    #|extern int strcmp(const char *, const char *);
    #|int main(void) {
    #|  char text[12];
    #|  text[0] = ',';
    #|  text[1] = 'a';
    #|  text[2] = 'b';
    #|  text[3] = ',';
    #|  text[4] = ';';
    #|  text[5] = 'c';
    #|  text[6] = 'd';
    #|  text[7] = ';';
    #|  text[8] = 0;
    #|  text[9] = 'x';
    #|  char other[4];
    #|  other[0] = 'z';
    #|  other[1] = ':';
    #|  other[2] = 'q';
    #|  other[3] = 0;
    #|  char *first = strtok(text, ",;");
    #|  if (first != text + 1) return 1;
    #|  if (strcmp(first, "ab") != 0) return 2;
    #|  if (text[3] != 0) return 3;
    #|  char *second = strtok(0, ",;");
    #|  if (second != text + 5) return 4;
    #|  if (strcmp(second, "cd") != 0) return 5;
    #|  if (text[7] != 0) return 6;
    #|  if (strtok(0, ",;") != 0) return 7;
    #|  char *reset = strtok(other, ":");
    #|  if (reset != other) return 8;
    #|  if (strcmp(reset, "z") != 0) return 9;
    #|  if (other[1] != 0) return 10;
    #|  char *tail = strtok(0, ":");
    #|  if (tail != other + 2) return 11;
    #|  if (strcmp(tail, "q") != 0) return 12;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models declared decimal integer conversion libcalls" {
  let source =
    #|extern long strtol(const char *, char **, int);
    #|extern long long strtoll(const char *, char **, int);
    #|extern unsigned long strtoul(const char *, char **, int);
    #|extern unsigned long long strtoull(const char *, char **, int);
    #|extern int atoi(const char *);
    #|extern long atol(const char *);
    #|extern long long atoll(const char *);
    #|int main(void) {
    #|  char *end;
    #|  char nodigits[4];
    #|  nodigits[0] = 'x';
    #|  nodigits[1] = '7';
    #|  nodigits[2] = 0;
    #|  nodigits[3] = 'z';
    #|  if (strtol("  -42xyz", &end, 10) != -42L) return 1;
    #|  if (*end != 'x') return 2;
    #|  if (strtoll("+17", &end, 10) != 17LL) return 3;
    #|  if (*end != 0) return 4;
    #|  if (strtoul("42x", &end, 10) != 42UL) return 5;
    #|  if (*end != 'x') return 6;
    #|  if (strtoull("9", 0, 10) != 9ULL) return 7;
    #|  if (strtol(nodigits, &end, 10) != 0L) return 8;
    #|  if (end != nodigits) return 9;
    #|  if (atoi(" -12q") != -12) return 10;
    #|  if (atol("33q") != 33L) return 11;
    #|  if (atoll("-44q") != -44LL) return 12;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models declared integer conversion bases" {
  let source =
    #|extern long strtol(const char *, char **, int);
    #|extern unsigned long strtoul(const char *, char **, int);
    #|int main(void) {
    #|  char *end;
    #|  if (strtol("0x2a!", &end, 0) != 42L) return 1;
    #|  if (*end != '!') return 2;
    #|  if (strtol("052!", &end, 0) != 42L) return 3;
    #|  if (*end != '!') return 4;
    #|  if (strtol("2A!", &end, 16) != 42L) return 5;
    #|  if (*end != '!') return 6;
    #|  if (strtoul("101010!", &end, 2) != 42UL) return 7;
    #|  if (*end != '!') return 8;
    #|  if (strtol("z!", &end, 36) != 35L) return 9;
    #|  if (*end != '!') return 10;
    #|  if (strtol("19!", &end, 8) != 1L) return 11;
    #|  if (*end != '9') return 12;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models extended declared string libcalls" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *mempcpy(void *, const void *, size_t);
    #|extern char *strncpy(char *, const char *, size_t);
    #|extern char *strncat(char *, const char *, size_t);
    #|extern char *stpcpy(char *, const char *);
    #|extern char *stpncpy(char *, const char *, size_t);
    #|extern size_t strlcpy(char *, const char *, size_t);
    #|extern size_t strlcat(char *, const char *, size_t);
    #|extern int strcmp(const char *, const char *);
    #|int main(void) {
    #|  char dst[16];
    #|  if (strncpy(dst, "ab", 4) != dst) return 1;
    #|  if (dst[0] != 'a' || dst[1] != 'b' || dst[2] != 0 || dst[3] != 0) return 2;
    #|  if (strncat(dst, "cd", 1) != dst) return 3;
    #|  if (strcmp(dst, "abc") != 0) return 4;
    #|  if (stpcpy(dst, "hi") != dst + 2) return 5;
    #|  if (stpncpy(dst, "toolong", 3) != dst + 3) return 6;
    #|  dst[3] = 0;
    #|  if (strcmp(dst, "too") != 0) return 7;
    #|  if (mempcpy(dst, "xyz", 4) != dst + 4) return 8;
    #|  if (strcmp(dst, "xyz") != 0) return 9;
    #|  if (strlcpy(dst, "abcd", 3) != 4) return 10;
    #|  if (strcmp(dst, "ab") != 0) return 11;
    #|  if (strlcat(dst, "xy", 5) != 4) return 12;
    #|  if (strcmp(dst, "abxy") != 0) return 13;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models scalar object memory bytes" {
  let source =
    #|static unsigned int g = 0x89abcdefu;
    #|int main(void) {
    #|  unsigned int x = 0x12345678u;
    #|  unsigned int y = 0u;
    #|  unsigned int z = 0xffffffffu;
    #|  if (__builtin_memcpy(&y, &x, sizeof(y)) != &y) return 1;
    #|  if (y != x) return 2;
    #|  if (__builtin_memset(&z, 0, sizeof(z)) != &z) return 3;
    #|  if (z != 0u) return 4;
    #|  __builtin_memset(&z, 0x2a, 1);
    #|  if (z != 42u) return 5;
    #|  __builtin_memmove(&z, &g, sizeof(z));
    #|  if (z != g) return 6;
    #|  __builtin_memset(&g, 0, sizeof(g));
    #|  if (g != 0u) return 7;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models double object memory bytes" {
  let source =
    #|static double gd = 9.5;
    #|int main(void) {
    #|  double x = 1.25;
    #|  double y = 0.0;
    #|  double z = -4.5;
    #|  if (__builtin_memcpy(&y, &x, sizeof(y)) != &y) return 1;
    #|  if ((int)(y * 4.0) != 5) return 2;
    #|  __builtin_memmove(&z, &gd, sizeof(z));
    #|  if ((int)(z * 2.0) != 19) return 3;
    #|  __builtin_memset(&z, 0, sizeof(z));
    #|  if ((int)z != 0) return 4;
    #|  __builtin_memcpy(&gd, &x, sizeof(gd));
    #|  if ((int)(gd * 4.0) != 5) return 5;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models float object memory bytes" {
  let source =
    #|static float gf = 1.5f;
    #|int main(void) {
    #|  float x = 1.0f;
    #|  unsigned char *p = (unsigned char *)&x;
    #|  if (p[0] != 0u || p[1] != 0u || p[2] != 0x80u || p[3] != 0x3fu) return 1;
    #|  p[0] = 0u;
    #|  p[1] = 0u;
    #|  p[2] = 0u;
    #|  p[3] = 0x40u;
    #|  if ((int)x != 2) return 2;
    #|  unsigned char raw[4];
    #|  raw[0] = 0u;
    #|  raw[1] = 0u;
    #|  raw[2] = 0x40u;
    #|  raw[3] = 0x40u;
    #|  if ((int)*(float *)raw != 3) return 3;
    #|  float y = 0.0f;
    #|  __builtin_memcpy(&y, &gf, sizeof(y));
    #|  if ((int)y != 1) return 4;
    #|  __builtin_memset(&gf, 0, sizeof(gf));
    #|  if ((int)gf != 0) return 5;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models floating array byte memory" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern void *memmove(void *, const void *, size_t);
    #|extern int memcmp(const void *, const void *, size_t);
    #|int main(void) {
    #|  double src[2] = {1.5, 2.25};
    #|  double dst[2] = {0.0, 0.0};
    #|  float fs[3] = {1.25f, 2.5f, 3.75f};
    #|  float fd[3] = {0.0f, 0.0f, 0.0f};
    #|  if (memcpy(dst, src, sizeof(src)) != dst) return 1;
    #|  if (memmove(fd, fs, sizeof(fs)) != fd) return 2;
    #|  if (memcmp(dst, src, sizeof(src)) != 0) return 3;
    #|  if (memcmp(fd, fs, sizeof(fs)) != 0) return 4;
    #|  if ((int)(dst[0] * 10.0) != 15) return 5;
    #|  if ((int)(dst[1] * 100.0) != 225) return 6;
    #|  if ((int)(fd[0] * 100.0f) != 125) return 7;
    #|  fd[1] += 1.5f;
    #|  if ((int)(fd[1] * 10.0f) != 40) return 8;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models floating aggregate byte copies" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memset(void *, int, size_t);
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern void *memmove(void *, const void *, size_t);
    #|struct Box {
    #|  char tag;
    #|  float f;
    #|  double d;
    #|};
    #|int main(void) {
    #|  struct Box src;
    #|  struct Box dst;
    #|  struct Box slots[2];
    #|  memset(&src, 0, sizeof(src));
    #|  memset(&dst, 0, sizeof(dst));
    #|  memset(slots, 0, sizeof(slots));
    #|  src.tag = 5;
    #|  src.f = 1.25f;
    #|  src.d = 2.5;
    #|  if (memcpy(&dst, &src, sizeof(src)) != &dst) return 1;
    #|  if (dst.tag != 5) return 2;
    #|  if ((int)(dst.f * 100.0f) != 125) return 3;
    #|  if ((int)(dst.d * 10.0) != 25) return 4;
    #|  slots[0].tag = 1;
    #|  slots[0].f = 3.5f;
    #|  slots[0].d = 4.5;
    #|  if (memmove(&slots[1], &slots[0], sizeof(slots[0])) != &slots[1]) return 5;
    #|  if (slots[1].tag != 1) return 6;
    #|  if ((int)(slots[1].f * 10.0f) != 35) return 7;
    #|  if ((int)(slots[1].d * 10.0) != 45) return 8;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models global floating aggregate byte copies" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memset(void *, int, size_t);
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern void *memmove(void *, const void *, size_t);
    #|struct Box {
    #|  char tag;
    #|  float f;
    #|  double d;
    #|};
    #|struct Box global_box;
    #|struct Box global_slots[2];
    #|int main(void) {
    #|  struct Box local;
    #|  struct Box copy;
    #|  memset(&global_box, 0, sizeof(global_box));
    #|  memset(global_slots, 0, sizeof(global_slots));
    #|  memset(&local, 0, sizeof(local));
    #|  memset(&copy, 0, sizeof(copy));
    #|  local.tag = 7;
    #|  local.f = 1.5f;
    #|  local.d = 2.25;
    #|  if (memcpy(&global_box, &local, sizeof(global_box)) != &global_box) return 1;
    #|  if (global_box.tag != 7) return 2;
    #|  if ((int)(global_box.f * 10.0f) != 15) return 3;
    #|  if ((int)(global_box.d * 100.0) != 225) return 4;
    #|  if (memmove(&copy, &global_box, sizeof(copy)) != &copy) return 5;
    #|  if (copy.tag != 7) return 6;
    #|  if ((int)(copy.f * 10.0f) != 15) return 7;
    #|  global_slots[0] = copy;
    #|  if (memcpy(&global_slots[1], &global_slots[0], sizeof(global_slots[0])) != &global_slots[1]) return 8;
    #|  if (global_slots[1].tag != 7) return 9;
    #|  if ((int)(global_slots[1].d * 100.0) != 225) return 10;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models union overlay byte memory" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern int memcmp(const void *, const void *, size_t);
    #|union Value {
    #|  float f;
    #|  unsigned u;
    #|  unsigned char bytes[4];
    #|};
    #|union BytesFirst {
    #|  unsigned char bytes[4];
    #|  float f;
    #|  unsigned u;
    #|};
    #|int main(void) {
    #|  union Value v;
    #|  v.f = 1.0f;
    #|  if (v.u != 0x3f800000u) return 1;
    #|  v.bytes[0] = 0u;
    #|  v.bytes[1] = 0u;
    #|  v.bytes[2] = 0u;
    #|  v.bytes[3] = 0x40u;
    #|  if ((int)v.f != 2) return 2;
    #|  union BytesFirst w;
    #|  unsigned char raw[4] = {0u, 0u, 0x40u, 0x40u};
    #|  if (memcpy(w.bytes, raw, 4) != w.bytes) return 3;
    #|  if ((int)w.f != 3) return 4;
    #|  if (memcmp(w.bytes, raw, 4) != 0) return 5;
    #|  w.u = 0x40800000u;
    #|  if ((int)w.f != 4) return 6;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models Darwin long double byte memory" {
  let source =
    #|typedef unsigned long size_t;
    #|extern void *memcpy(void *, const void *, size_t);
    #|extern void *memmove(void *, const void *, size_t);
    #|extern void *memset(void *, int, size_t);
    #|struct LDBox { char tag; long double value; };
    #|static long double global_ld = 8.5L;
    #|static struct LDBox global_box;
    #|int main(void) {
    #|  long double x = 1.25L;
    #|  long double y = 0.0L;
    #|  long double z = -4.5L;
    #|  if (memcpy(&y, &x, sizeof(y)) != &y) return 1;
    #|  if ((int)(y * 4.0L) != 5) return 2;
    #|  if (memmove(&z, &global_ld, sizeof(z)) != &z) return 3;
    #|  if ((int)(z * 2.0L) != 17) return 4;
    #|  if (memset(&z, 0, sizeof(z)) != &z) return 5;
    #|  if ((int)z != 0) return 6;
    #|  long double src[2] = {2.5L, 3.5L};
    #|  long double dst[2] = {0.0L, 0.0L};
    #|  if (memcpy(dst, src, sizeof(src)) != dst) return 7;
    #|  if ((int)(dst[0] * 10.0L) != 25) return 8;
    #|  if ((int)(dst[1] * 10.0L) != 35) return 9;
    #|  struct LDBox box;
    #|  memset(&box, 0, sizeof(box));
    #|  box.tag = 4;
    #|  box.value = 4.75L;
    #|  if (memcpy(&global_box, &box, sizeof(box)) != &global_box) return 10;
    #|  if (global_box.tag != 4) return 11;
    #|  if ((int)(global_box.value * 4.0L) != 19) return 12;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models scalar aggregate field memory bytes" {
  let source =
    #|struct S {
    #|  unsigned int head;
    #|  unsigned int values[2];
    #|};
    #|static struct S g = { 0x12345678u, { 0x01020304u, 0x89abcdefu } };
    #|int main(void) {
    #|  struct S s;
    #|  s.head = 0x55667788u;
    #|  s.values[0] = 0u;
    #|  s.values[1] = 0u;
    #|  unsigned int copy = 0u;
    #|  if (__builtin_memcpy(&copy, &s.head, sizeof(copy)) != &copy) return 1;
    #|  if (copy != 0x55667788u) return 2;
    #|  __builtin_memcpy(&s.values[1], &g.values[1], sizeof(copy));
    #|  if (s.values[1] != 0x89abcdefu) return 3;
    #|  __builtin_memset(&s.head, 0, sizeof(s.head));
    #|  if (s.head != 0u) return 4;
    #|  __builtin_memset(&g.values[0], 0, sizeof(g.values[0]));
    #|  if (g.values[0] != 0u) return 5;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models direct scalar byte memory access" {
  let source =
    #|struct S {
    #|  unsigned int head;
    #|  unsigned int tail;
    #|};
    #|static unsigned int g = 0x01020304u;
    #|int main(void) {
    #|  unsigned int x = 0x12345678u;
    #|  unsigned char *p = (unsigned char *)&x;
    #|  if (p[0] != 0x78u) return 1;
    #|  if (p[1] != 0x56u) return 2;
    #|  p[1] = 0xaau;
    #|  if (x != 0x1234aa78u) return 3;
    #|  unsigned char raw[4];
    #|  raw[0] = 0xefu;
    #|  raw[1] = 0xbeu;
    #|  raw[2] = 0xadu;
    #|  raw[3] = 0xdeu;
    #|  if (*(unsigned int *)raw != 0xdeadbeefu) return 4;
    #|  struct S s;
    #|  s.head = 0u;
    #|  s.tail = 0u;
    #|  *(unsigned int *)(((unsigned char *)&s) + sizeof(unsigned int)) = g;
    #|  if (s.tail != 0x01020304u) return 5;
    #|  unsigned char *q = (unsigned char *)&g;
    #|  q[0] = 0x2au;
    #|  if (g != 0x0102032au) return 6;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models overlapping memmove bytes" {
  let source =
    #|int main(void) {
    #|  char buf[6];
    #|  buf[0] = 'a';
    #|  buf[1] = 'b';
    #|  buf[2] = 'c';
    #|  buf[3] = 'd';
    #|  buf[4] = 'e';
    #|  buf[5] = 0;
    #|  __builtin_memmove(buf + 1, buf, 4);
    #|  if (__builtin_strcmp(buf, "aabcd") != 0) return 1;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models alloca mempcpy and bzero effects" {
  let source =
    #|int main(void) {
    #|  char *dst = __builtin_alloca(6);
    #|  if (__builtin_memset(dst, 'z', 5) != dst) return 1;
    #|  dst[5] = 0;
    #|  if (__builtin_strlen(dst) != 5) return 2;
    #|  if (__builtin_mempcpy(dst + 1, "bc", 2) != dst + 3) return 3;
    #|  if (__builtin_memcmp(dst, "zbczz", 5) != 0) return 4;
    #|  __builtin_bzero(dst + 3, 2);
    #|  if (__builtin_strlen(dst) != 3) return 5;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models string copy byte effects" {
  let source =
    #|int main(void) {
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin_strcpy(dst, "ab") != dst) return 1;
    #|  if (__builtin_strcmp(dst, "ab") != 0) return 2;
    #|  if (__builtin___strcpy_chk(dst, "cd", 16) != dst) return 3;
    #|  if (__builtin_strcmp(dst, "cd") != 0) return 4;
    #|  if (__builtin_stpcpy(dst, "wxy") != dst + 3) return 5;
    #|  if (__builtin_strcmp(dst, "wxy") != 0) return 6;
    #|  if (__builtin___stpcpy_chk(dst, "ok", 16) != dst + 2) return 7;
    #|  if (__builtin_strcmp(dst, "ok") != 0) return 8;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models string append byte effects" {
  let source =
    #|int main(void) {
    #|  char dst[16];
    #|  dst[0] = 0;
    #|  if (__builtin_strcat(dst, "hi") != dst) return 1;
    #|  if (__builtin___strcat_chk(dst, "!", 16) != dst) return 2;
    #|  if (__builtin_strncat(dst, "zz", 1) != dst) return 3;
    #|  if (__builtin___strncat_chk(dst, "yy", 1, 16) != dst) return 4;
    #|  if (__builtin_strcmp(dst, "hi!zy") != 0) return 5;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models bounded string copy byte effects" {
  let source =
    #|int main(void) {
    #|  char dst[8];
    #|  __builtin_memset(dst, 'x', 8);
    #|  if (__builtin_strncpy(dst, "ab", 5) != dst) return 1;
    #|  if (dst[0] != 'a' || dst[1] != 'b' || dst[2] != 0) return 2;
    #|  if (dst[3] != 0 || dst[4] != 0 || dst[5] != 'x') return 3;
    #|  if (__builtin_stpncpy(dst, "wxyz", 2) != dst + 2) return 4;
    #|  if (dst[0] != 'w' || dst[1] != 'x' || dst[2] != 0) return 5;
    #|  if (__builtin___stpncpy_chk(dst, "q", 4, 8) != dst + 1) return 6;
    #|  if (dst[0] != 'q' || dst[1] != 0 || dst[2] != 0 || dst[3] != 0) return 7;
    #|  if (__builtin___strncpy_chk(dst, "rs", 2, 8) != dst) return 8;
    #|  if (dst[0] != 'r' || dst[1] != 's' || dst[2] != 0) return 9;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models strlcpy byte effects" {
  let source =
    #|int main(void) {
    #|  char dst[8];
    #|  __builtin_memset(dst, 'x', 8);
    #|  if (__builtin___strlcpy_chk(dst, "abcdef", 4, 8) != 6) return 1;
    #|  if (dst[0] != 'a' || dst[1] != 'b' || dst[2] != 'c') return 2;
    #|  if (dst[3] != 0 || dst[4] != 'x') return 3;
    #|  dst[0] = 'q';
    #|  if (__builtin___strlcpy_chk(dst, "zz", 0, 8) != 2) return 4;
    #|  if (dst[0] != 'q') return 5;
    #|  if (__builtin___strlcpy_chk(dst, "ok", 8, 8) != 2) return 6;
    #|  if (__builtin_strcmp(dst, "ok") != 0) return 7;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models strlcat byte effects" {
  let source =
    #|int main(void) {
    #|  char dst[8];
    #|  __builtin_strcpy(dst, "ab");
    #|  if (__builtin___strlcat_chk(dst, "cdef", 5, 8) != 6) return 1;
    #|  if (__builtin_strcmp(dst, "abcd") != 0) return 2;
    #|  if (__builtin___strlcat_chk(dst, "zz", 4, 8) != 6) return 3;
    #|  if (__builtin_strcmp(dst, "abcd") != 0) return 4;
    #|  if (__builtin___strlcat_chk(dst, "!", 8, 8) != 5) return 5;
    #|  if (__builtin_strcmp(dst, "abcd!") != 0) return 6;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models strlcat bounded destination length" {
  let source =
    #|int main(void) {
    #|  char dst[4];
    #|  dst[0] = 'a';
    #|  dst[1] = 'b';
    #|  dst[2] = 'c';
    #|  dst[3] = 'd';
    #|  if (__builtin___strlcat_chk(dst, "xy", 4, 4) != 6) return 1;
    #|  if (dst[0] != 'a' || dst[1] != 'b') return 2;
    #|  if (dst[2] != 'c' || dst[3] != 'd') return 3;
    #|  if (__builtin___strlcat_chk(dst, "z", 0, 4) != 1) return 4;
    #|  if (dst[0] != 'a') return 5;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models checked sprintf output bytes" {
  let source =
    #|int main(void) {
    #|  char dst[32];
    #|  if (__builtin___sprintf_chk(dst, 0, 32, "n=%d:%s:%c", 42, "ok", '!') != 9) return 1;
    #|  if (__builtin_strcmp(dst, "n=42:ok:!") != 0) return 2;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, "%x/%X/%o/%u", 255, 255, 8, 7) != 10) return 3;
    #|  if (__builtin_strcmp(dst, "ff/FF/10/7") != 0) return 4;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models checked snprintf output bytes" {
  let source =
    #|int main(void) {
    #|  char dst[8];
    #|  __builtin_memset(dst, 'x', 8);
    #|  if (__builtin___snprintf_chk(dst, 5, 0, 8, "abcdef") != 6) return 1;
    #|  if (__builtin_strcmp(dst, "abcd") != 0) return 2;
    #|  if (dst[5] != 'x') return 3;
    #|  dst[0] = 'q';
    #|  if (__builtin___snprintf_chk(dst, 0, 0, 8, "hi") != 2) return 4;
    #|  if (dst[0] != 'q') return 5;
    #|  if (__builtin___snprintf_chk(dst, 8, 0, 8, "%s-%c", "go", '!') != 4) return 6;
    #|  if (__builtin_strcmp(dst, "go-!") != 0) return 7;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models declared printf output bytes" {
  let source =
    #|typedef unsigned long size_t;
    #|extern int snprintf(char *, size_t, const char *, ...);
    #|extern int sprintf(char *, const char *, ...);
    #|extern int printf(const char *, ...);
    #|extern int fprintf(void *, const char *, ...);
    #|int main(void) {
    #|  char dst[32];
    #|  int count = 0;
    #|  if (snprintf(dst, 8, "%s:%d", "go", 42) != 5) return 1;
    #|  if (__builtin_strcmp(dst, "go:42") != 0) return 2;
    #|  if (sprintf(dst, "%05d|%c", 7, '!') != 7) return 3;
    #|  if (__builtin_strcmp(dst, "00007|!") != 0) return 4;
    #|  if (snprintf(dst, 4, "abcdef") != 6) return 5;
    #|  if (__builtin_strcmp(dst, "abc") != 0) return 6;
    #|  if (sprintf(dst, "ab%ncd", &count) != 4) return 7;
    #|  if (count != 2 || __builtin_strcmp(dst, "abcd") != 0) return 8;
    #|  if (printf("ok:%d", 12) != 5) return 9;
    #|  if (fprintf((void *)0, "x=%d", 7) != 3) return 10;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models plain printf builtins" {
  let source =
    #|int main(void) {
    #|  char dst[64];
    #|  int n = __builtin_snprintf(dst, 64, "%s:%05d", "go", 7);
    #|  if (n != 8) return 1;
    #|  if (__builtin_strcmp(dst, "go:00007") != 0) return 2;
    #|  int count = 0;
    #|  int m = __builtin_sprintf(dst, "%#x|%n%s", 42, &count, "ok");
    #|  if (m != 7 || count != 5) return 3;
    #|  if (__builtin_printf("%s|%d|%d|%d\n", dst, n, count, m) != 14) return 4;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models checked vprintf buffer literal output bytes" {
  let source =
    #|int main(void) {
    #|  char dst[8];
    #|  if (__builtin___vsprintf_chk(dst, 0, 8, "ok%%", (void *)0) != 3) return 1;
    #|  if (__builtin_strcmp(dst, "ok%") != 0) return 2;
    #|  __builtin_memset(dst, 'x', 8);
    #|  if (__builtin___vsnprintf_chk(dst, 5, 0, 8, "ready", (void *)0) != 5) return 3;
    #|  if (__builtin_strcmp(dst, "read") != 0) return 4;
    #|  if (dst[5] != 'x') return 5;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter unpacks declared vprintf va_list args" {
  let source =
    #|typedef unsigned long size_t;
    #|typedef __builtin_va_list va_list;
    #|extern int vsnprintf(char *, size_t, const char *, va_list);
    #|extern int vprintf(const char *, va_list);
    #|int fill(int tag, ...) {
    #|  char dst[32];
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  int n = vsnprintf(dst, 32, "%s:%04d", ap);
    #|  if (n != 7) return 1;
    #|  if (__builtin_strcmp(dst, "go:0005") != 0) return 2;
    #|  int m = vprintf(":%d", ap);
    #|  __builtin_va_end(ap);
    #|  if (m != 2) return 3;
    #|  return tag + n + m;
    #|}
    #|int main(void) {
    #|  return fill(33, "go", 5, 7);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter unpacks checked vprintf va_list args" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int fill(int tag, ...) {
    #|  char dst[32];
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  int n = __builtin___vsnprintf_chk(dst, 32, 0, 32, "%s:%04d", ap);
    #|  __builtin_va_end(ap);
    #|  if (n != 7) return 1;
    #|  if (__builtin_strcmp(dst, "go:0005") != 0) return 2;
    #|  return tag + n;
    #|}
    #|int main(void) {
    #|  return fill(35, "go", 5);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter unpacks plain vprintf builtins" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int write_plain(char *dst, const char *fmt, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, fmt);
    #|  int n = __builtin_vsnprintf(dst, 32, fmt, ap);
    #|  __builtin_va_end(ap);
    #|  return n;
    #|}
    #|int write_plain_sprintf(char *dst, const char *fmt, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, fmt);
    #|  int n = __builtin_vsprintf(dst, fmt, ap);
    #|  __builtin_va_end(ap);
    #|  return n;
    #|}
    #|int count_plain(const char *fmt, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, fmt);
    #|  int n = __builtin_vprintf(fmt, ap);
    #|  __builtin_va_end(ap);
    #|  return n;
    #|}
    #|int main(void) {
    #|  char dst[32];
    #|  int n = write_plain(dst, "%s:%04d", "ok", 7);
    #|  if (n != 7) return 1;
    #|  if (__builtin_strcmp(dst, "ok:0007") != 0) return 2;
    #|  int m = write_plain_sprintf(dst, "%#x", 42);
    #|  if (m != 4) return 3;
    #|  if (__builtin_strcmp(dst, "0x2a") != 0) return 4;
    #|  int p = count_plain(":%d", 42);
    #|  if (p != 3) return 5;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models checked printf dynamic width and precision" {
  let source =
    #|int main(void) {
    #|  char dst[32];
    #|  if (__builtin___sprintf_chk(dst, 0, 32, "%*.*s:%0*d", 6, 2, "abcd", 4, 7) != 11) return 1;
    #|  if (__builtin_strcmp(dst, "    ab:0007") != 0) return 2;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, "%*.*s", -6, -1, "abc") != 6) return 3;
    #|  if (__builtin_strcmp(dst, "abc   ") != 0) return 4;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter consumes checked vprintf dynamic width va_list args" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int fill(int tag, ...) {
    #|  char dst[32];
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  int n = __builtin___vsnprintf_chk(dst, 32, 0, 32, "%*.*s:%0*d", ap);
    #|  int tail = __builtin_va_arg(ap, int);
    #|  __builtin_va_end(ap);
    #|  if (n != 11) return 1;
    #|  if (__builtin_strcmp(dst, "    ab:0007") != 0) return 2;
    #|  if (tail != 9) return 3;
    #|  return tag + n + tail;
    #|}
    #|int main(void) {
    #|  return fill(22, 6, 2, "abcd", 4, 7, 9);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models checked printf pointer output" {
  let source =
    #|int main(void) {
    #|  char dst[32];
    #|  if (__builtin___sprintf_chk(dst, 0, 32, "%p|%6p|%-6p", (void *)0, (void *)0, (void *)0) != 17) return 1;
    #|  if (__builtin_strcmp(dst, "0x0|   0x0|0x0   ") != 0) return 2;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter consumes checked vprintf pointer va_list args" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int fill(int tag, ...) {
    #|  char dst[16];
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  int n = __builtin___vsnprintf_chk(dst, 16, 0, 16, "%*p", ap);
    #|  int tail = __builtin_va_arg(ap, int);
    #|  __builtin_va_end(ap);
    #|  if (n != 6) return 1;
    #|  if (__builtin_strcmp(dst, "   0x0") != 0) return 2;
    #|  if (tail != 5) return 3;
    #|  return tag + n + tail;
    #|}
    #|int main(void) {
    #|  return fill(31, 6, (void *)0, 5);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models checked printf count stores" {
  let source =
    #|int main(void) {
    #|  char dst[16];
    #|  int n = -1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, "ab%ncd", &n) != 4) return 1;
    #|  if (__builtin_strcmp(dst, "abcd") != 0) return 2;
    #|  if (n != 2) return 3;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models length-modified checked printf count stores" {
  let source =
    #|int main(void) {
    #|  char dst[16];
    #|  char c = 0;
    #|  short h = 0;
    #|  long l = 0;
    #|  long long q = 0;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, "a%hhnb%hnc%lnd%lln", &c, &h, &l, &q) != 4) return 1;
    #|  if (__builtin_strcmp(dst, "abcd") != 0) return 2;
    #|  if (c != 1) return 3;
    #|  if (h != 2) return 4;
    #|  if (l != 3) return 5;
    #|  if (q != 4) return 6;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, "%hhd:%hd", 7, 12) != 4) return 7;
    #|  if (__builtin_strcmp(dst, "7:12") != 0) return 8;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter consumes checked vprintf count store va_list args" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int n;
    #|int fill(int tag, ...) {
    #|  char dst[16];
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  int r = __builtin___vsnprintf_chk(dst, 16, 0, 16, "%*s%n:%d", ap);
    #|  int tail = __builtin_va_arg(ap, int);
    #|  __builtin_va_end(ap);
    #|  if (r != 5) return 1;
    #|  if (__builtin_strcmp(dst, "  x:5") != 0) return 2;
    #|  if (tail != 7) return 3;
    #|  return tag + r + tail;
    #|}
    #|int main(void) {
    #|  n = -1;
    #|  if (fill(27, 3, "x", &n, 5, 7) != 39) return 1;
    #|  if (n != 3) return 2;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models checked printf padded output bytes" {
  let source =
    #|int main(void) {
    #|  char dst[32];
    #|  if (__builtin___sprintf_chk(dst, 0, 32, "%05d|%-4s|%3c", 7, "hi", 'A') != 14) return 1;
    #|  if (__builtin_strcmp(dst, "00007|hi  |  A") != 0) return 2;
    #|  if (__builtin___snprintf_chk(dst, 8, 0, 32, "%5.2s|%c", "abcd", '!') != 7) return 3;
    #|  if (__builtin_strcmp(dst, "   ab|!") != 0) return 4;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models checked printf flagged numeric output bytes" {
  let source =
    #|int main(void) {
    #|  char dst[64];
    #|  if (__builtin___sprintf_chk(dst, 0, 64, "%+.4d|% .3d|%#.4x|%#.4o", 12, 7, 42, 8) != 22) return 1;
    #|  if (__builtin_strcmp(dst, "+0012| 007|0x002a|0010") != 0) return 2;
    #|  if (__builtin___sprintf_chk(dst, 0, 64, "%#x|%#X|%#o", 42, 42, 8) != 13) return 3;
    #|  if (__builtin_strcmp(dst, "0x2a|0X2A|010") != 0) return 4;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models checked printf fixed floating output bytes" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int fill(int tag, ...) {
    #|  char dst[64];
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  int n = __builtin___vsnprintf_chk(dst, 64, 0, 64, "%*.2f:%d", ap);
    #|  __builtin_va_end(ap);
    #|  if (n != 8) return 1;
    #|  if (__builtin_strcmp(dst, "  1.50:7") != 0) return 2;
    #|  return tag + n;
    #|}
    #|int main(void) {
    #|  char dst[64];
    #|  if (__builtin___sprintf_chk(dst, 0, 64, "%+.1f|% 6.2f|%05.0f", 1.5, 2.0, 3.0) != 17) return 1;
    #|  if (__builtin_strcmp(dst, "+1.5|  2.00|00003") != 0) return 2;
    #|  if (fill(34, 6, 1.5, 7) != 42) return 3;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models checked printf scientific floating output bytes" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int fill(int tag, ...) {
    #|  char dst[64];
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  int n = __builtin___vsnprintf_chk(dst, 64, 0, 64, "%*.1E:%d", ap);
    #|  int tail = __builtin_va_arg(ap, int);
    #|  __builtin_va_end(ap);
    #|  if (n != 10) return 1;
    #|  if (__builtin_strcmp(dst, " 1.2E-02:5") != 0) return 2;
    #|  if (tail != 7) return 3;
    #|  return tag + n + tail;
    #|}
    #|int main(void) {
    #|  char dst[64];
    #|  if (__builtin___sprintf_chk(dst, 0, 64, "%+.2e|% 8.1E|%05.0e", 123.0, 0.012, 9.9) != 24) return 1;
    #|  if (__builtin_strcmp(dst, "+1.23e+02| 1.2E-02|1e+01") != 0) return 2;
    #|  if (fill(25, 8, 0.012, 5, 7) != 42) return 3;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models checked printf modeled string args" {
  let source =
    #|int main(void) {
    #|  char src[16];
    #|  char dst[32];
    #|  __builtin_strcpy(src, "local");
    #|  if (__builtin___sprintf_chk(dst, 0, 32, "%s", src) != 5) return 1;
    #|  if (__builtin_strcmp(dst, "local") != 0) return 2;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, "%8.3s", src) != 8) return 3;
    #|  if (__builtin_strcmp(dst, "     loc") != 0) return 4;
    #|  char *heap = __builtin_alloca(16);
    #|  __builtin_strcpy(heap, "buffer");
    #|  if (__builtin___snprintf_chk(dst, 7, 0, 32, "%s", heap) != 6) return 5;
    #|  if (__builtin_strcmp(dst, "buffer") != 0) return 6;
    #|  if (__builtin___snprintf_chk(dst, 5, 0, 32, "%s", heap) != 6) return 7;
    #|  if (__builtin_strcmp(dst, "buff") != 0) return 8;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles scalar globals" {
  let source =
    #|int g = 5;
    #|int h;
    #|int bump(void) {
    #|  g += 3;
    #|  h = g++;
    #|  return h;
    #|}
    #|int main(void) {
    #|  h = 2;
    #|  return bump() + g + h;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("bump"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 25L)
}

///|
test "mir body interpreter handles scalar global arrays" {
  let source =
    #|int a[3];
    #|int main(void) {
    #|  a[0] = 4;
    #|  a[1] = a[0] + 5;
    #|  int *p = &a[1];
    #|  p[1] = 7;
    #|  return a[0] + a[1] + a[2];
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 20L)
}

///|
test "mir body interpreter handles aggregate global arrays" {
  let source =
    #|struct S { int x; int y; };
    #|struct S values[2];
    #|int main(void) {
    #|  values[1].x = 19;
    #|  values[1].y = 23;
    #|  return values[1].x + values[1].y;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles scalar global pointer loads" {
  let source =
    #|int a[2];
    #|int *p;
    #|int main(void) {
    #|  a[0] = 21;
    #|  p = &a[0];
    #|  if (*p != 21) return 1;
    #|  *p = 42;
    #|  return *p;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles initialized global pointer offsets" {
  let source =
    #|int a[3] = {4, 5, 6};
    #|int *p = a + 1;
    #|int main(void) {
    #|  return *p;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 5L)
}

///|
test "mir body interpreter handles initialized global function pointers" {
  let source =
    #|int f(void) { return 42; }
    #|int (*fp)(void) = f;
    #|int main(void) {
    #|  return fp();
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("f"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles initialized global string pointers" {
  let source =
    #|char *g = "abc";
    #|char *names[2] = { "xy", "z" };
    #|int main(void) {
    #|  if (g[1] != 'b') return 1;
    #|  if (names[0][1] != 'y') return 2;
    #|  if (__builtin_strlen(names[1]) != 1) return 3;
    #|  if (names[1][0] != 'z') return 4;
    #|  if (names[1][1] != 0) return 5;
    #|  if (__builtin_strlen(g + 1) != 2) return 6;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles initialized global string arrays" {
  let source =
    #|char g[] = "abc";
    #|char exact[3] = "xyz";
    #|int main(void) {
    #|  if (g[0] != 'a') return 1;
    #|  if (g[3] != 0) return 2;
    #|  if (exact[2] != 'z') return 3;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles end-pointer memory string builtins" {
  let source =
    #|int main(void) {
    #|  char copy[16];
    #|  int n = 0;
    #|  if (__builtin_mempcpy(copy, "uv", 2) != copy + 2) return 1;
    #|  if (__builtin___mempcpy_chk(copy + 2, "wx", 2, n += 14) != copy + 4) return 2;
    #|  if (n != 14) return 3;
    #|  if (__builtin_stpcpy(copy, "hi") != copy + 2) return 4;
    #|  if (__builtin___stpcpy_chk(copy, "ok", n += 16) != copy + 2) return 5;
    #|  if (__builtin_stpncpy(copy, "abcd", 2) != copy + 2) return 6;
    #|  if (__builtin___stpncpy_chk(copy, "cd", 5, n += 16) != copy + 2) return 7;
    #|  if (n != 46) return 8;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles initialized scalar global arrays" {
  let source =
    #|int a[3] = {1, 2, 3};
    #|int main(void) {
    #|  a[1] += 5;
    #|  return a[0] + a[1] + a[2];
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 11L)
}

///|
test "mir body interpreter handles static nested array access" {
  let source =
    #|int main(void) {
    #|  static const unsigned char trans[2][3] = {
    #|    { 1, 2, 3 },
    #|    { 4, 5, 6 },
    #|  };
    #|  int i = 1;
    #|  int j = 2;
    #|  return trans[i][j];
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 6L)
}

///|
test "mir body interpreter handles casted global array decay" {
  let source =
    #|int a[3] = {4, 5, 6};
    #|int *get(int *pn) {
    #|  *pn = sizeof(a) / sizeof(a[0]);
    #|  return (int*)a;
    #|}
    #|int main(void) {
    #|  int n = 0;
    #|  int *p = get(&n);
    #|  return p[1] + n;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("get"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  inspect(mir.bodies["get"].params.length(), content="1")
  inspect(mir.bodies["get"].body.length(), content="2")
  expect_body_interp(source, 8L)
}

///|
test "mir body interpreter returns implicit global array decay" {
  let source =
    #|char version[4] = "abc";
    #|char *get(void) {
    #|  return version;
    #|}
    #|int main(void) {
    #|  char *p = get();
    #|  return p[1];
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("get"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 98L)
}

///|
test "mir body interpreter handles sparse initialized scalar global arrays" {
  let source =
    #|int a[4] = { [2] = 9, [0] = 1 };
    #|int main(void) {
    #|  return a[0] + a[1] + a[2] + a[3];
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 10L)
}

///|
test "mir body interpreter handles initialized global aggregate arrays" {
  let source =
    #|struct Pair { int a; int b; };
    #|static struct Pair boxes[2] = { { 1, 2 }, { 20, 22 } };
    #|int main(void) {
    #|  return boxes[1].a + boxes[1].b;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter copies initialized nested global aggregates" {
  let source =
    #|struct Pair { int a; int b; };
    #|struct Outer { int head; struct Pair pairs[2]; int tail; };
    #|static struct Outer g = {
    #|  .head = 5,
    #|  .pairs = { [1] = { .a = 17, .b = 19 } },
    #|  .tail = 1
    #|};
    #|int main(void) {
    #|  struct Pair copy = g.pairs[1];
    #|  return g.head + copy.a + copy.b + g.tail;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter reads pointer fields from global aggregates" {
  let source =
    #|struct Node { char *name; int *value; int bias; };
    #|int target = 13;
    #|static struct Node node = { "ok", &target, 29 };
    #|int main(void) {
    #|  return node.name[1] == 'k' ? *node.value + node.bias : 1;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter reads file-scope compound literal globals" {
  let source =
    #|struct S { int a; int b; };
    #|struct S *p = &(struct S){ .b = 23, .a = 19 };
    #|int *q = &((struct S){ 5, 37 }).b;
    #|int *r = (int[]){ 11, 31 };
    #|int main(void) {
    #|  return p->a + p->b == 42 && *q == 37 && r[0] + r[1] == 42 ? 42 : 1;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter sign extends initialized global bitfields" {
  let source =
    #|struct Bits { unsigned a : 3; signed b : 4; unsigned c : 5; };
    #|static struct Bits bits = { .a = 5, .b = -3, .c = 17 };
    #|int main(void) {
    #|  return bits.a + bits.b + bits.c;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 19L)
}

///|
test "mir body interpreter handles string literal byte loads" {
  let source =
    #|int main(void) {
    #|  char *s = "abc";
    #|  return s[1] + "xy"[0] + "z"[1];
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 218L)
}

///|
test "mir body interpreter handles scalar compound literals" {
  let source =
    #|int main(void) {
    #|  int side = 0;
    #|  int a = (int){40};
    #|  unsigned char b = (unsigned char){255 + 1};
    #|  int c = (int){side += 2};
    #|  return a + b + c + side;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 44L)
}

///|
test "mir body interpreter handles address of scalar compound literals" {
  let source =
    #|int main(void) {
    #|  int side = 0;
    #|  int *p = &(int){side += 3};
    #|  return *p + side;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 6L)
}

///|
test "mir body interpreter handles address of aggregate compound literals" {
  let source =
    #|struct Pair { int x; int y; };
    #|int main(void) {
    #|  return (&(struct Pair){ 20, 22 })->x +
    #|    (&(struct Pair){ 20, 22 })->y;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles local array compound literals" {
  let source =
    #|struct Pair { int x; int y; };
    #|int main(void) {
    #|  int side = 0;
    #|  int *p = (int[]){ side += 10, 11 };
    #|  struct Pair *pairs = (struct Pair[]){ { 3, 4 }, { 7, 8 } };
    #|  int (*q)[2] = &(int[2]){ 4, 6 };
    #|  if (side != 10) return 1;
    #|  return p[0] + p[1] + pairs[0].x + pairs[1].y +
    #|    (*q)[0] + (*q)[1];
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles casted address of aggregate compound literals" {
  let source =
    #|struct Pair { int x; int y; };
    #|int main(void) {
    #|  return ((struct Pair *)&(struct Pair){ 20, 22 })->x +
    #|    ((struct Pair *)&(struct Pair){ 20, 22 })->y;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter cancels address of aggregate member objects" {
  let source =
    #|struct Inner { int z; };
    #|struct S { struct Inner inner; };
    #|int main(void) {
    #|  struct S s = { { 42 } };
    #|  return (&s.inner)->z;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter cancels casted address of aggregate member objects" {
  let source =
    #|struct Inner { int z; };
    #|struct S { struct Inner inner; };
    #|int main(void) {
    #|  struct S s = { { 42 } };
    #|  return ((struct Inner *)&s.inner)->z;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles nested casted known aggregate addresses" {
  let source =
    #|struct Inner { int z; };
    #|struct S { struct Inner inner; };
    #|struct Pair { int x; int y; };
    #|int main(void) {
    #|  struct S s = { { 20 } };
    #|  return ((struct Inner *)(void *)&s.inner)->z +
    #|    ((struct Pair *)(void *)&(struct Pair){ 1, 22 })->y;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter keeps side effecting ignored builtin operands" {
  let source =
    #|int main(void) {
    #|  int x = 4;
    #|  int side = 0;
    #|  return __builtin_expect(x, side += 1) + side;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 5L)
}

///|
test "mir body interpreter handles scalar aggregate fields" {
  let source =
    #|struct S { int x; unsigned char y; };
    #|int main(void) {
    #|  struct S s;
    #|  s.x = 4;
    #|  s.y = 250 + 10;
    #|  return s.x + s.y;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 8L)
}

///|
test "mir body interpreter handles aggregate pointers across calls" {
  let source =
    #|struct Pair { int x; int y; };
    #|void fill_pair(struct Pair *p) {
    #|  p->x = 19;
    #|  p->y = 23;
    #|}
    #|int sum_pair(struct Pair *p) {
    #|  return p->x + p->y;
    #|}
    #|int main(void) {
    #|  struct Pair p;
    #|  fill_pair(&p);
    #|  return sum_pair(&p);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles local struct initializers" {
  let source =
    #|struct S { int x; unsigned char y; int z; };
    #|int main(void) {
    #|  int side = 1;
    #|  struct S s = { side += 2, 250 + 10 };
    #|  return s.x + s.y + s.z + side;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 10L)
}

///|
test "mir body interpreter handles nested local struct initializers" {
  let source =
    #|struct Inner { int z; };
    #|struct Outer { int tag; struct Inner inner; int tail; };
    #|int main(void) {
    #|  struct Outer o = { .inner = { 22 }, .tag = 20 };
    #|  return o.tag + o.inner.z + o.tail;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles local struct copy initializers" {
  let source =
    #|struct Inner { int z; };
    #|struct S { int tag; struct Inner inner; int tail; };
    #|int main(void) {
    #|  struct S a = { .inner = { 22 }, .tag = 20 };
    #|  struct S b = a;
    #|  a.inner.z = 1;
    #|  return b.tag + b.inner.z + b.tail;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles ignored local struct assignments" {
  let source =
    #|struct S { int x; int y; };
    #|int main(void) {
    #|  struct S a = { 20, 22 };
    #|  struct S b = { 1, 2 };
    #|  b = a;
    #|  a.x = 0;
    #|  return b.x + b.y;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles aggregate assignment rvalue member reads" {
  let source =
    #|struct S { int x; int y; };
    #|int main(void) {
    #|  struct S lhs = { 1, 2 };
    #|  struct S rhs = { 19, 23 };
    #|  int value = (lhs = rhs).y;
    #|  return value + lhs.x;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter keeps aggregate assignment rvalue destination stable" {
  let source =
    #|struct S { int x; int y; };
    #|int main(void) {
    #|  struct S lhs = { 1, 2 };
    #|  struct S rhs = { 19, 23 };
    #|  struct S *p = 0;
    #|  int value = (*(p = &lhs) = rhs).y;
    #|  if (p != &lhs) return 0;
    #|  return value + lhs.x;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles local aggregate array assignment rvalues" {
  let source =
    #|struct S { int x; int y; };
    #|int main(void) {
    #|  struct S slots[2];
    #|  struct S rhs = { 19, 23 };
    #|  int i = 0;
    #|  int value = (slots[i++] = rhs).y;
    #|  if (i != 1) return 0;
    #|  return value + slots[0].x;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles aggregate assignment ternary call rvalues" {
  let source =
    #|struct Box { int a; int b; };
    #|int side;
    #|struct Box make(int tag) {
    #|  struct Box box;
    #|  box.a = tag;
    #|  box.b = 42 - tag;
    #|  side = side * 10 + tag;
    #|  return box;
    #|}
    #|int pick_false(void) {
    #|  struct Box slots[2];
    #|  int i = 0;
    #|  int cond = 0;
    #|  side = 0;
    #|  int value = (slots[i++] = cond ? make(1) : make(2)).a;
    #|  if (i != 1) return 10 + i;
    #|  if (side != 2) return side;
    #|  if (slots[0].b != 40) return slots[0].b;
    #|  return value + 40;
    #|}
    #|int pick_true(void) {
    #|  struct Box slots[2];
    #|  int i = 0;
    #|  int cond = 1;
    #|  side = 0;
    #|  int value = (slots[i++] = cond ? make(3) : make(4)).a;
    #|  if (i != 1) return 20 + i;
    #|  if (side != 3) return side;
    #|  if (slots[0].b != 39) return slots[0].b;
    #|  return value + 39;
    #|}
    #|int main(void) {
    #|  if (pick_false() != 42) return 1;
    #|  if (pick_true() != 42) return 2;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("make"), content="true")
  inspect(mir.bodies.contains("pick_false"), content="true")
  inspect(mir.bodies.contains("pick_true"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles ignored local struct compound literal assignments" {
  let source =
    #|struct S { int x; int y; int z; };
    #|int main(void) {
    #|  struct S b = { 19, 2, 3 };
    #|  b = (struct S){ b.x + 1, 22 };
    #|  return b.x + b.y + b.z;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles nested aggregate compound literal assignments" {
  let source =
    #|struct Inner { int z; int q; };
    #|struct S { int tag; struct Inner inner; int a[2]; int tail; };
    #|int main(void) {
    #|  struct S s = {0};
    #|  s = (struct S){
    #|    .tag = 1,
    #|    .inner = { .z = 20, .q = 2 },
    #|    .a = { [1] = 4, [0] = 3 },
    #|    .tail = 12
    #|  };
    #|  return s.tag + s.inner.z + s.inner.q + s.a[0] + s.a[1] + s.tail;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles scalar array fields in struct copies" {
  let source =
    #|struct S { int a[2]; int z; };
    #|int main(void) {
    #|  struct S s;
    #|  s.a[0] = 20;
    #|  s.a[1] = 21;
    #|  s.z = 1;
    #|  struct S b = s;
    #|  s.a[0] = 0;
    #|  return b.a[0] + b.a[1] + b.z;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles aggregate array fields in struct copies" {
  let source =
    #|struct Item { int x; int y; };
    #|struct Db { struct Item items[2]; int tail; };
    #|int main(void) {
    #|  struct Db src;
    #|  src.items[0].x = 10;
    #|  src.items[0].y = 1;
    #|  src.items[1].x = 2;
    #|  src.items[1].y = 29;
    #|  src.tail = 3;
    #|  struct Db copy = src;
    #|  src.items[1].y = 0;
    #|  return copy.items[0].x + copy.items[1].y + copy.tail;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles local union initializers" {
  let source =
    #|union U { int x; unsigned char c; };
    #|int main(void) {
    #|  union U u = { 42 };
    #|  return u.x;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter reports unknown implicit external scalar calls" {
  let source =
    #|int main(void) {
    #|  return external_value();
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  match mir.interpret_body_i64("main", []) {
    Ok(_) => abort("expected unknown external function error")
    Err(err) =>
      inspect(
        err.contains("function has no MIR body: external_value"),
        content="true",
      )
  }
}

///|
test "mir body interpreter handles sync synchronize builtin" {
  let source =
    #|int main(void) {
    #|  __sync_synchronize();
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles atomic fence builtins" {
  let source =
    #|int main(void) {
    #|  int x = 0;
    #|  __atomic_thread_fence((x = x + 1, 5));
    #|  __atomic_signal_fence((x = x + 1, 5));
    #|  __c11_atomic_thread_fence((x = x + 1, 5));
    #|  __c11_atomic_signal_fence((x = x + 1, 5));
    #|  return x + 38;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles exchange-style atomic builtins" {
  let source =
    #|int main(void) {
    #|  unsigned char flag = 0;
    #|  unsigned int w = 10;
    #|  int side = 0;
    #|  if (__atomic_test_and_set(&flag, side += 1)) return 1;
    #|  if (side != 1 || flag != 1) return 2;
    #|  if (!__atomic_test_and_set(&flag, side += 2)) return 3;
    #|  if (side != 3) return 4;
    #|  __atomic_clear(&flag, side += 4);
    #|  if (side != 7 || flag != 0) return 5;
    #|  if (__sync_fetch_and_add(&w, 2u) != 10u) return 6;
    #|  if (__sync_add_and_fetch(&w, 5u) != 17u) return 7;
    #|  if (__sync_fetch_and_nand(&w, 15u) != 17u) return 8;
    #|  if (w != ~1u) return 9;
    #|  __sync_lock_release(&w);
    #|  if (w != 0u) return 10;
    #|  if (__sync_lock_test_and_set(&w, 23u) != 0u) return 11;
    #|  if (__sync_swap(&w, 42u) != 23u) return 12;
    #|  return (int)w;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles sync compare-and-swap builtins" {
  let source =
    #|int main(void) {
    #|  unsigned int w = 10u;
    #|  int side = 0;
    #|  if (!__sync_bool_compare_and_swap(&w, side += 10, 12u)) return 1;
    #|  if (side != 10 || w != 12u) return 2;
    #|  if (__sync_bool_compare_and_swap(&w, 10u, side += 1)) return 3;
    #|  if (side != 11 || w != 12u) return 4;
    #|  if (__sync_val_compare_and_swap(&w, 12u, side += 6) != 12u) return 5;
    #|  if (side != 17 || w != 17u) return 6;
    #|  if (__sync_val_compare_and_swap(&w, 12u, side += 25) != 17u) return 7;
    #|  if (side != 42 || w != 17u) return 8;
    #|  return side;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles generic pointer atomic builtins" {
  let source =
    #|int main(void) {
    #|  int x = 11;
    #|  int out = 0;
    #|  int set = 17;
    #|  int old = 0;
    #|  int desired = 23;
    #|  int expected = 17;
    #|  int side = 0;
    #|  __atomic_load(&x, &out, side += 1);
    #|  if (out != 11 || side != 1) return 1;
    #|  __atomic_store(&x, &set, side += 2);
    #|  if (x != 17 || side != 3) return 2;
    #|  __atomic_exchange(&x, &desired, &old, side += 4);
    #|  if (x != 23 || old != 17 || side != 7) return 3;
    #|  int fail_desired = 29;
    #|  expected = 17;
    #|  if (__atomic_compare_exchange(&x, &expected, &fail_desired, side += 8, side += 16, side += 32)) return 4;
    #|  if (expected != 23 || x != 23 || side != 63) return 5;
    #|  desired = 31;
    #|  expected = 23;
    #|  if (!__atomic_compare_exchange(&x, &expected, &desired, side += 64, side += 128, side += 256)) return 6;
    #|  if (x != 31 || expected != 23 || side != 511) return 7;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles atomic lock-free query builtins" {
  let source =
    #|int main(void) {
    #|  int side = 0;
    #|  int object = 0;
    #|  if (!__atomic_is_lock_free((side += 1, 4), &object)) return 1;
    #|  if (side != 1) return 2;
    #|  if (__atomic_is_lock_free(3, (void *)(long)(side += 10))) return 3;
    #|  if (side != 11) return 4;
    #|  if (!__c11_atomic_is_lock_free((side += 4, 8))) return 5;
    #|  if (__c11_atomic_is_lock_free(16)) return 6;
    #|  if (!__atomic_always_lock_free(4, (void *)(long)(side += 100))) return 7;
    #|  if (__atomic_always_lock_free(16, 0)) return 8;
    #|  if (side != 15) return 9;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles sync minmax atomic builtins" {
  let source =
    #|int main(void) {
    #|  int sw = -3;
    #|  unsigned int uw = 10u;
    #|  if (__sync_fetch_and_max(&sw, -1) != -3) return 1;
    #|  if (sw != -1) return 2;
    #|  if (__sync_fetch_and_min(&sw, -7) != -1) return 3;
    #|  if (sw != -7) return 4;
    #|  if (__sync_fetch_and_umax(&uw, 12u) != 10u) return 5;
    #|  if (uw != 12u) return 6;
    #|  if (__sync_fetch_and_umin(&uw, 7u) != 12u) return 7;
    #|  if (uw != 7u) return 8;
    #|  return sw + (int)uw + 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter reports executed trap builtin" {
  let source =
    #|int main(void) {
    #|  __builtin_trap();
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  match mir.interpret_body_i64("main", []) {
    Ok(_) => abort("expected MIR body trap error")
    Err(err) => inspect(err.contains("trap"), content="true")
  }
}

///|
test "mir body interpreter models frame and return address nullness" {
  let source =
    #|int main(void) {
    #|  void *fa = __builtin_frame_address(0);
    #|  void *ra = __builtin_return_address(0);
    #|  if (fa == 0) return 1;
    #|  if (ra == 0) return 2;
    #|  if (__builtin_frame_address(1) != 0) return 3;
    #|  if (__builtin_return_address(1) != 0) return 4;
    #|  if (__builtin_extract_return_addr(ra) != ra) return 5;
    #|  if (__builtin_frob_return_addr(ra) != ra) return 6;
    #|  int level = 0;
    #|  if (__builtin_frame_address(level) == 0) return 7;
    #|  level = level + 1;
    #|  if (__builtin_return_address(level) != 0) return 8;
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles ignored local union assignments" {
  let source =
    #|union U { unsigned char c; int x; };
    #|int main(void) {
    #|  union U a = { .x = 19 };
    #|  union U b = { .c = 1 };
    #|  b = a;
    #|  a.x = 0;
    #|  b = (union U){ .x = b.x + 21 };
    #|  return b.x + 2;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles nested union compound literal assignments" {
  let source =
    #|union U { unsigned char c; int x; };
    #|struct S { union U u; int tail; };
    #|int main(void) {
    #|  struct S s = {0};
    #|  s = (struct S){ .u = { .x = 40 }, .tail = 2 };
    #|  return s.u.x + s.tail;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles nested aggregate fields" {
  let source =
    #|struct Inner { int z; };
    #|struct S { struct Inner inner; };
    #|int main(void) {
    #|  struct S s;
    #|  s.inner.z = 7;
    #|  return s.inner.z;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 7L)
}

///|
test "mir body interpreter handles nested global aggregate fields" {
  let source =
    #|struct Inner { int z; char c; };
    #|struct S { struct Inner inner; int tail; };
    #|struct S g;
    #|int main(void) {
    #|  g.inner.z = 9;
    #|  g.inner.c = 4;
    #|  g.tail = 11;
    #|  return g.inner.z + g.inner.c + g.tail;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 24L)
}

///|
test "mir body interpreter handles address of aggregate member" {
  let source =
    #|struct Methods { int (*init)(void); };
    #|struct Config { struct Methods methods; };
    #|struct Config cfg;
    #|int good(void) { return 42; }
    #|int setup(void) {
    #|  struct Methods *to = &cfg.methods;
    #|  to->init = good;
    #|  return cfg.methods.init();
    #|}
    #|int main(void) {
    #|  return setup();
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("setup"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles local aggregate member function tables" {
  let source =
    #|struct Methods { int (*init)(void); };
    #|struct Config { struct Methods methods; };
    #|int good(void) { return 42; }
    #|int main(void) {
    #|  struct Config cfg;
    #|  struct Methods *to = &cfg.methods;
    #|  to->init = good;
    #|  return cfg.methods.init();
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles address of aggregate array element" {
  let source =
    #|struct Item { int v; };
    #|struct Item items[2];
    #|struct Item *pick(int i) {
    #|  return &items[i];
    #|}
    #|int main(void) {
    #|  items[1].v = 42;
    #|  return pick(1)->v;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("pick"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles pointer memory post update" {
  let source =
    #|int main(void) {
    #|  int values[3] = {4, 7, 9};
    #|  int *p = values;
    #|  int **pp = &p;
    #|  int first = *((*pp)++);
    #|  return first + **pp;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 11L)
}

///|
test "mir body interpreter handles array element aggregate fields" {
  let source =
    #|struct Item { int v; };
    #|struct Db { struct Item a[2]; };
    #|int get(struct Db *db, int i) {
    #|  return db->a[i].v;
    #|}
    #|int main(void) {
    #|  struct Db db;
    #|  db.a[0].v = 4;
    #|  db.a[1].v = 7;
    #|  return get(&db, 1);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("get"), content="true")
  inspect(mir.bodies.contains("main"), content="true")
  inspect(mir.bodies["get"].params.length(), content="2")
  inspect(mir.bodies["get"].body.length(), content="1")
  expect_body_interp(source, 7L)
}

///|
test "mir body interpreter executes computed goto labels" {
  let source =
    #|int main(void) {
    #|  void *target = &&done;
    #|  goto *target;
    #|done:
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter executes static label address table" {
  let source =
    #|int main(void) {
    #|  static void *labels[] = { &&bad, &&good };
    #|  goto *labels[1];
    #|bad:
    #|  return 1;
    #|good:
    #|  return 42;
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="true")
  match mir.global_decls[0].init {
    Some(
      MirGlobalArray([MirGlobalLabelAddr("bad"), MirGlobalLabelAddr("good")])
    ) => ()
    _ => abort("expected label address table initializer")
  }
  expect_body_interp(source, 42L)
}

///|
test "mir body lowering rejects unsupported source builtin calls" {
  let source =
    #|int main(void) {
    #|  return __builtin_mir_unsupported(0);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("main"), content="false")
  match mir.interpret_body_i64("main", []) {
    Ok(_) => abort("expected unsupported builtin body")
    Err(err) =>
      inspect(err.contains("function has no MIR body: main"), content="true")
  }
}

///|
test "mir interpreter executes scalar calls and locals" {
  let source =
    #|int helper(int x) { return x * 2; }
    #|int main(void) {
    #|  int a = 20;
    #|  return helper(a) + 2;
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir interpreter executes integer control flow and globals" {
  let source =
    #|int g = 1;
    #|int bump(int n) {
    #|  g += n;
    #|  return g;
    #|}
    #|int main(void) {
    #|  int sum = 0;
    #|  for (int i = 0; i < 8; i++) {
    #|    if (i == 2) continue;
    #|    if (i == 6) break;
    #|    sum += i;
    #|  }
    #|  while (sum < 20) {
    #|    sum++;
    #|  }
    #|  return bump(sum) + (sum == 20 ? 21 : 0);
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreters use merged global initializer after extern declaration" {
  let source =
    #|extern int g;
    #|int g = 7;
    #|int main(void) { return g; }
  expect_interp(source, 7L)
  expect_body_interp(source, 7L)
}

///|
test "mir interpreter evaluates scalar address dereference cancellation" {
  let source =
    #|int main(void) {
    #|  int x = 4;
    #|  *&x += 5;
    #|  return *&x;
    #|}
  expect_interp(source, 9L)
}

///|
test "mir interpreter evaluates integer overflow builtins" {
  let source =
    #|int main(void) {
    #|  int i = 0;
    #|  unsigned u = 0;
    #|  long long l = 0;
    #|  unsigned long long ul = 0;
    #|  int total = 0;
    #|  total += __builtin_add_overflow(1, 2, &i);
    #|  if (i != 3) return 10;
    #|  total += __builtin_add_overflow(2147483647, 1, &i);
    #|  if (i >= 0) return 20;
    #|  total += __builtin_sub_overflow(0u, 1u, &u);
    #|  if (u != 4294967295u) return 30;
    #|  total += __builtin_mul_overflow(50000, 50000, &i);
    #|  total += __builtin_add_overflow(l, 1LL, &l);
    #|  if (l != 1LL) return 40;
    #|  total += __builtin_ssubll_overflow(-9223372036854775807LL - 1LL, 1LL, &l);
    #|  if (l != 9223372036854775807LL) return 50;
    #|  total += __builtin_uaddll_overflow(0xffffffffffffffffULL, 1ULL, &ul);
    #|  if (ul != 0ULL) return 60;
    #|  total += __builtin_smulll_overflow(3037000500LL, 3037000500LL, &l);
    #|  if (l != -9223372036709301616LL) return 70;
    #|  total += __builtin_umulll_overflow(0xffffffffffffffffULL, 2ULL, &ul);
    #|  if (ul != 0xfffffffffffffffeULL) return 80;
    #|  return total;
    #|}
  expect_interp(source, 7L)
  expect_body_interp(source, 7L)
}

///|
test "mir interpreter evaluates scalar compound literals" {
  let source =
    #|int main(void) {
    #|  int a = (int){40};
    #|  unsigned char b = (unsigned char){255 + 1};
    #|  long long c = (long long){-9223372036854775807LL - 1LL};
    #|  unsigned long long d = (unsigned long long){0xffffffffffffffffULL};
    #|  return a + b + (c < 0 ? 2 : 0) + (d == 0xffffffffffffffffULL ? 0 : 100);
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter applies target layout and integer casts" {
  let source =
    #|int main(void) {
    #|  unsigned char x = 255 + 1;
    #|  return sizeof(long double) + x;
    #|}
  let darwin = @mir.lower(@parser.parse(source), @target.Target::default())
  let linux = @mir.lower(
    @parser.parse_for_target(source, linux_target()),
    linux_target(),
  )
  match darwin.interpret_i64("main", []) {
    Ok(value) => inspect(value, content="8")
    Err(err) => abort(err)
  }
  match linux.interpret_i64("main", []) {
    Ok(value) => inspect(value, content="16")
    Err(err) => abort(err)
  }
}

///|
test "mir interpreter models frame and return address nullness" {
  let source =
    #|int main(void) {
    #|  void *fa = __builtin_frame_address(0);
    #|  void *ra = __builtin_return_address(0);
    #|  if (fa == 0) return 1;
    #|  if (ra == 0) return 2;
    #|  if (__builtin_frame_address(1) != 0) return 3;
    #|  if (__builtin_return_address(1) != 0) return 4;
    #|  if (__builtin_extract_return_addr(ra) != ra) return 5;
    #|  if (__builtin_frob_return_addr(ra) != ra) return 6;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models string literal scalar facts" {
  let source =
    #|int main(void) {
    #|  if (sizeof("abc") != 4) return 1;
    #|  if (__alignof__("abc") != 1) return 2;
    #|  if (!"abc") return 3;
    #|  if (*"abc" != 'a') return 4;
    #|  if ("abc"[1] != 'b') return 5;
    #|  if ("abc"[3] != 0) return 6;
    #|  if (__func__[0] != 'm') return 7;
    #|  if (__builtin_strlen("hello") != 5) return 8;
    #|  if (*((char *)"abc") != 'a') return 9;
    #|  if (((char *)"abc")[2] != 'c') return 10;
    #|  if (((unsigned char *)"abc")[3] != 0) return 11;
    #|  if (__builtin_strlen((const char *)"hello") != 5) return 12;
    #|  if (*("abcd" + 1) != 'b') return 13;
    #|  if ((1 + "abcd")[2] != 'd') return 14;
    #|  int side = 0;
    #|  if (*((const char *)"abcd" + (side += 2)) != 'c') return 15;
    #|  if (side != 2) return 16;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models string literal pointer locals" {
  let source =
    #|int main(void) {
    #|  char *s = (char *)"abc";
    #|  char *tail = s + 1;
    #|  char *u = (char *)"abba";
    #|  char *hay = (char *)"abcde";
    #|  char *needle = (char *)"cd";
    #|  if (*s != 'a') return 1;
    #|  if (tail[1] != 'c') return 2;
    #|  if (__builtin_strlen(s) != 3) return 3;
    #|  if (__builtin_strlen(tail) != 2) return 4;
    #|  if (__builtin_strcmp(s, "abc") != 0) return 5;
    #|  if (__builtin_strncmp(tail, "bc", 2) != 0) return 6;
    #|  if (__builtin_memcmp(tail, "bc", 2) != 0) return 7;
    #|  if (__builtin_strchr(s, 'b') != s + 1) return 8;
    #|  if (__builtin_strchr(tail, 'a') != 0) return 9;
    #|  if (__builtin_strchr(s, 0) != s + 3) return 10;
    #|  if (__builtin_strrchr(u, 'b') != u + 2) return 11;
    #|  if (__builtin_strrchr(u + 1, 'a') != u + 3) return 12;
    #|  if (__builtin_memchr(s, 'b', 2) != s + 1) return 13;
    #|  if (__builtin_memchr(s, 0, 4) != s + 3) return 14;
    #|  if (__builtin_strstr(hay + 1, needle) != hay + 2) return 15;
    #|  if (__builtin_strstr(hay, needle + 1) != hay + 3) return 16;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models global string pointer initializers" {
  let source =
    #|char *g = "abc";
    #|char *tail = (char *)"abc" + 1;
    #|int main(void) {
    #|  if (g[0] != 'a') return 1;
    #|  if (tail[0] != 'b') return 2;
    #|  if (__builtin_strlen(g) != 3) return 3;
    #|  if (__builtin_strlen(tail) != 2) return 4;
    #|  if (__builtin_strchr(g, 'c') != g + 2) return 5;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models global string array initializers" {
  let source =
    #|char g[] = "abc";
    #|unsigned char u[] = { 'x', 'y', 0, 'z' };
    #|char padded[5] = { 'q' };
    #|int main(void) {
    #|  if (g[0] != 'a') return 1;
    #|  if (g[3] != 0) return 2;
    #|  if (__builtin_strlen(g) != 3) return 3;
    #|  if (__builtin_strcmp(g, "abc") != 0) return 4;
    #|  if (__builtin_strlen((char *)u) != 2) return 5;
    #|  if (u[3] != 'z') return 6;
    #|  if (padded[0] != 'q') return 7;
    #|  if (padded[1] != 0 || padded[4] != 0) return 8;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models local string array initializers" {
  let source =
    #|int main(void) {
    #|  char s[] = "abc";
    #|  unsigned char u[4] = { 'x', 'y', 0, 'z' };
    #|  char padded[5] = { 'q' };
    #|  char *tail = s + 1;
    #|  if (s[0] != 'a') return 1;
    #|  if (s[3] != 0) return 2;
    #|  if (__builtin_strlen(s) != 3) return 3;
    #|  s[1] = 'z';
    #|  if (__builtin_strcmp(s, "azc") != 0) return 4;
    #|  *tail = 'b';
    #|  if (__builtin_strcmp(s, "abc") != 0) return 5;
    #|  if (__builtin_strlen((char *)u) != 2) return 6;
    #|  if (u[3] != 'z') return 7;
    #|  if (padded[0] != 'q') return 8;
    #|  if (padded[1] != 0 || padded[4] != 0) return 9;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models string array element addresses" {
  let source =
    #|char g[] = "abc";
    #|char *gp = &g[1];
    #|int main(void) {
    #|  char s[] = "wxyz";
    #|  char *p = &s[2];
    #|  if (*p != 'y') return 1;
    #|  *p = 'q';
    #|  if (__builtin_strcmp(s, "wxqz") != 0) return 2;
    #|  if (*gp != 'b') return 3;
    #|  if (__builtin_strchr(g, 'c') != &g[2]) return 4;
    #|  if (__builtin_strchr(s, 'z') != &s[3]) return 5;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models embedded nul string literal lengths" {
  let source =
    #|int main(void) {
    #|  char *dst = (char *)__builtin_alloca(8);
    #|  if (sizeof("a\0bc") != 5) return 1;
    #|  if (__builtin_strlen("a\0bc") != 1) return 2;
    #|  if (__builtin_stpcpy(dst, "a\0bc") != dst + 1) return 3;
    #|  if (__builtin_stpncpy(dst, "a\0bc", 4) != dst + 1) return 4;
    #|  if (__builtin___strlcpy_chk(dst, "a\0bc", 8, 8) != 1) return 5;
    #|  if (__builtin___strlcat_chk(dst, "a\0bc", 0, 8) != 1) return 6;
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"%s", "a\0bc") != 1) return 7;
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"%.3s", "a\0bc") != 1) return 8;
    #|  if (__builtin_strlen((const char *)"a\0bc" + 2) != 2) return 9;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models string builtin return sizes" {
  let source =
    #|int main(void) {
    #|  return sizeof(__builtin_strlen("abc")) +
    #|    sizeof(__builtin_memchr("abc", 'a', 3)) +
    #|    sizeof(__builtin_strchr("abc", 'a')) +
    #|    sizeof(__builtin_strcmp("a", "b")) +
    #|    sizeof(__builtin_strncmp("a", "b", 1)) +
    #|    sizeof(__builtin_memcmp("a", "b", 1));
    #|}
  expect_interp(source, 36L)
}

///|
test "mir interpreter models string alias builtin return sizes" {
  let source =
    #|char *dst;
    #|char *src;
    #|int main(void) {
    #|  return sizeof(__builtin_mempcpy(dst, src, 1)) +
    #|    sizeof(__builtin___mempcpy_chk(dst, src, 1, 16)) +
    #|    sizeof(__builtin_strcat(dst, src)) +
    #|    sizeof(__builtin_stpcpy(dst, src)) +
    #|    sizeof(__builtin___stpcpy_chk(dst, src, 16)) +
    #|    sizeof(__builtin_strncpy(dst, src, 1)) +
    #|    sizeof(__builtin_stpncpy(dst, src, 1)) +
    #|    sizeof(__builtin___stpncpy_chk(dst, src, 1, 16)) +
    #|    sizeof(__builtin_strncat(dst, src, 1));
    #|}
  expect_interp(source, 72L)
}

///|
test "mir interpreter models string end pointer builtin returns" {
  let source =
    #|int main(void) {
    #|  char *dst = (char *)__builtin_alloca(16);
    #|  int side = 0;
    #|  if (__builtin_mempcpy(((side += 1), dst), "uv", side + 1) != dst + 2) return 1;
    #|  if (__builtin___mempcpy_chk(dst + 2, (const char *)"wx", 2, 16) != dst + 4) return 2;
    #|  if (__builtin_stpcpy(((side += 1), dst), "hi") != dst + 2) return 3;
    #|  if (__builtin___stpcpy_chk(dst, (const char *)"ok", 16) != dst + 2) return 4;
    #|  if (__builtin_stpncpy(dst, "abc", 2) != dst + 2) return 5;
    #|  if (__builtin_stpncpy(dst, "abc", 6) != dst + 3) return 6;
    #|  if (__builtin___stpncpy_chk(((side += 1), dst), (const char *)"cd", 2, 16) != dst + 2) return 7;
    #|  if (side != 3) return 8;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models floating builtin return sizes" {
  let source =
    #|int main(void) {
    #|  return sizeof(__builtin_fabsf(-1.0f)) +
    #|    sizeof(__builtin_fabs(-1.0)) +
    #|    sizeof(__builtin_fabsl(-1.0L)) +
    #|    sizeof(__builtin_copysignf(1.0f, -1.0f)) +
    #|    sizeof(__builtin_copysign(1.0, -1.0)) +
    #|    sizeof(__builtin_copysignl(1.0L, -1.0L)) +
    #|    sizeof(__builtin_sqrtf(4.0f)) +
    #|    sizeof(__builtin_sqrt(4.0)) +
    #|    sizeof(__builtin_sqrtl(4.0L)) +
    #|    sizeof(__builtin_nanf("")) +
    #|    sizeof(__builtin_nan("")) +
    #|    sizeof(__builtin_nanl("")) +
    #|    sizeof(__builtin_huge_valf()) +
    #|    sizeof(__builtin_huge_val()) +
    #|    sizeof(__builtin_huge_vall()) +
    #|    sizeof(__builtin_inff()) +
    #|    sizeof(__builtin_inf()) +
    #|    sizeof(__builtin_infl());
    #|}
  expect_interp(source, 120L)
}

///|
test "mir interpreter models floating classification return sizes" {
  let source =
    #|int main(void) {
    #|  return sizeof(__builtin_isgreater(2.0, 1.0)) +
    #|    sizeof(__builtin_isgreaterequal(2.0, 2.0)) +
    #|    sizeof(__builtin_isless(1.0, 2.0)) +
    #|    sizeof(__builtin_islessequal(2.0, 2.0)) +
    #|    sizeof(__builtin_islessgreater(1.0, 2.0)) +
    #|    sizeof(__builtin_isunordered(__builtin_nan(""), 1.0)) +
    #|    sizeof(__builtin_isnan(__builtin_nan(""))) +
    #|    sizeof(__builtin_isnanf(__builtin_nanf(""))) +
    #|    sizeof(__builtin_isnanl(__builtin_nanl(""))) +
    #|    sizeof(__builtin_isinf(__builtin_inf())) +
    #|    sizeof(__builtin_isinff(__builtin_inff())) +
    #|    sizeof(__builtin_isinfl(__builtin_infl())) +
    #|    sizeof(__builtin_isfinite(1.0)) +
    #|    sizeof(__builtin_isfinitef(1.0f)) +
    #|    sizeof(__builtin_isfinitel(1.0L)) +
    #|    sizeof(__builtin_isnormal(1.0)) +
    #|    sizeof(__builtin_isnormalf(1.0f)) +
    #|    sizeof(__builtin_isnormall(1.0L)) +
    #|    sizeof(__builtin_signbit(-1.0)) +
    #|    sizeof(__builtin_signbitf(-1.0f)) +
    #|    sizeof(__builtin_signbitl(-1.0L));
    #|}
  expect_interp(source, 84L)
}

///|
test "mir interpreter models alloca return size and nullness" {
  let source =
    #|int main(void) {
    #|  int n = 16;
    #|  void *p = __builtin_alloca(n += 1);
    #|  if (n != 17) return 1;
    #|  if (p == 0) return 2;
    #|  char *a = __builtin_alloca(n += 2);
    #|  char *b = __builtin_alloca(n += 3);
    #|  if (n != 22) return 3;
    #|  if (a == 0 || b == 0) return 4;
    #|  if (a == b || a == p || b == p) return 5;
    #|  char *c = __builtin_alloca_with_align(n += 4, 256);
    #|  if (n != 26) return 6;
    #|  if (c == 0 || (((unsigned long)c) & 31ul) != 0) return 7;
    #|  return sizeof(__builtin_alloca(16)) +
    #|    sizeof(__builtin_alloca_with_align(16, 256)) + 26;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models fortified builtin return sizes" {
  let source =
    #|int main(void) {
    #|  return sizeof(__builtin___memcpy_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___memset_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___memmove_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___strcpy_chk(0, 0, 0)) +
    #|    sizeof(__builtin___strcat_chk(0, 0, 0)) +
    #|    sizeof(__builtin___strncpy_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___strncat_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___strlcpy_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___strlcat_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___snprintf_chk(0, 0, 0, 0, 0)) +
    #|    sizeof(__builtin___vsnprintf_chk(0, 0, 0, 0, 0, 0)) +
    #|    sizeof(__builtin___sprintf_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___vsprintf_chk(0, 0, 0, 0, 0)) +
    #|    sizeof(__builtin___printf_chk(0, 0)) +
    #|    sizeof(__builtin___vprintf_chk(0, 0, 0)) +
    #|    sizeof(__builtin___fprintf_chk(0, 0, 0)) +
    #|    sizeof(__builtin___vfprintf_chk(0, 0, 0, 0));
    #|}
  expect_interp(source, 104L)
}

///|
test "mir interpreter models atomic builtin return sizes" {
  let source =
    #|int atomic_int_value;
    #|long atomic_long_value;
    #|_Atomic int c11_atomic_int_value;
    #|int expected_atomic_value;
    #|int main(void) {
    #|  return sizeof(__atomic_load_n(&atomic_int_value, 0)) +
    #|    sizeof(__atomic_load_n(&atomic_long_value, 0)) +
    #|    sizeof(__c11_atomic_load(&c11_atomic_int_value, 0)) +
    #|    sizeof(__atomic_add_fetch(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_sub_fetch(&atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_fetch_add(&c11_atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_fetch_sub(&c11_atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_fetch_and(&c11_atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_fetch_or(&c11_atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_fetch_xor(&c11_atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_exchange(&c11_atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_compare_exchange_strong(&c11_atomic_int_value, &expected_atomic_value, 1, 0, 0)) +
    #|    sizeof(__c11_atomic_compare_exchange_weak(&c11_atomic_int_value, &expected_atomic_value, 1, 0, 0)) +
    #|    sizeof(__atomic_store_n(&atomic_int_value, 1, 0)) +
    #|    sizeof(__c11_atomic_store(&c11_atomic_int_value, 1, 0)) +
    #|    sizeof(__sync_synchronize());
    #|}
  expect_interp(source, 50L)
}

///|
test "mir lowers pointer call args with member array decay" {
  let source =
    #|struct Info { unsigned aReadMark[4]; };
    #|unsigned load_mark(struct Info *pInfo, int i) {
    #|  return __atomic_load_n(pInfo->aReadMark + i, 0);
    #|}
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  inspect(mir.bodies.contains("load_mark"), content="true")
}

///|
test "mir interpreter models extended atomic builtin return sizes" {
  let source =
    #|int atomic_int_value;
    #|int expected_atomic_value;
    #|int desired_atomic_value;
    #|int main(void) {
    #|  return sizeof(__atomic_and_fetch(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_or_fetch(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_xor_fetch(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_nand_fetch(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_fetch_add(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_fetch_sub(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_fetch_and(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_fetch_or(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_fetch_xor(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_fetch_nand(&atomic_int_value, 1, 0)) +
    #|    sizeof(__atomic_exchange_n(&atomic_int_value, 1, 0)) +
    #|    sizeof(__sync_val_compare_and_swap(&atomic_int_value, 0, 1)) +
    #|    sizeof(__sync_fetch_and_add(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_sub(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_and(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_or(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_xor(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_nand(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_max(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_min(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_umax(&atomic_int_value, 1)) +
    #|    sizeof(__sync_fetch_and_umin(&atomic_int_value, 1)) +
    #|    sizeof(__sync_add_and_fetch(&atomic_int_value, 1)) +
    #|    sizeof(__sync_sub_and_fetch(&atomic_int_value, 1)) +
    #|    sizeof(__sync_and_and_fetch(&atomic_int_value, 1)) +
    #|    sizeof(__sync_or_and_fetch(&atomic_int_value, 1)) +
    #|    sizeof(__sync_xor_and_fetch(&atomic_int_value, 1)) +
    #|    sizeof(__sync_nand_and_fetch(&atomic_int_value, 1)) +
    #|    sizeof(__sync_swap(&atomic_int_value, 1)) +
    #|    sizeof(__sync_lock_test_and_set(&atomic_int_value, 1)) +
    #|    sizeof(__atomic_test_and_set(&atomic_int_value, 0)) +
    #|    sizeof(__atomic_compare_exchange(&atomic_int_value, &expected_atomic_value, &desired_atomic_value, 0, 0, 0)) +
    #|    sizeof(__atomic_compare_exchange_n(&atomic_int_value, &expected_atomic_value, desired_atomic_value, 0, 0, 0)) +
    #|    sizeof(__sync_bool_compare_and_swap(&atomic_int_value, 0, 1)) +
    #|    sizeof(__atomic_always_lock_free(4, 0)) +
    #|    sizeof(__atomic_is_lock_free(4, 0)) +
    #|    sizeof(__c11_atomic_is_lock_free(4)) +
    #|    sizeof(__atomic_clear(&atomic_int_value, 0)) +
    #|    sizeof(__atomic_exchange(&atomic_int_value, &desired_atomic_value, &expected_atomic_value, 0)) +
    #|    sizeof(__atomic_load(&atomic_int_value, &expected_atomic_value, 0)) +
    #|    sizeof(__atomic_store(&atomic_int_value, &desired_atomic_value, 0)) +
    #|    sizeof(__atomic_thread_fence(0)) +
    #|    sizeof(__atomic_signal_fence(0)) +
    #|    sizeof(__c11_atomic_thread_fence(0)) +
    #|    sizeof(__c11_atomic_signal_fence(0)) +
    #|    sizeof(__sync_lock_release(&atomic_int_value));
    #|}
  expect_interp(source, 127L)
}

///|
test "mir interpreter models scalar builtin return sizes" {
  let source =
    #|int main(void) {
    #|  return sizeof(__builtin_clz(8)) +
    #|    sizeof(__builtin_clzl(8ul)) +
    #|    sizeof(__builtin_clzll(8ull)) +
    #|    sizeof(__builtin_ctz(40)) +
    #|    sizeof(__builtin_ctzl(48ul)) +
    #|    sizeof(__builtin_ctzll(48ull)) +
    #|    sizeof(__builtin_ffs(8u)) +
    #|    sizeof(__builtin_ffsl(16ul)) +
    #|    sizeof(__builtin_ffsll(32ull)) +
    #|    sizeof(__builtin_popcount(0xf0f0u)) +
    #|    sizeof(__builtin_popcountl(0xf0f0ul)) +
    #|    sizeof(__builtin_popcountll(0xf0f0ull)) +
    #|    sizeof(__builtin_parity(0xf0f1u)) +
    #|    sizeof(__builtin_parityl(0xf0f1ul)) +
    #|    sizeof(__builtin_parityll(0xf0f1ull)) +
    #|    sizeof(__builtin_bswap16(0x0102)) +
    #|    sizeof(__builtin_bswap32(0x01020304u)) +
    #|    sizeof(__builtin_bswap64(0x0102030405060708ull)) +
    #|    sizeof(__builtin_bswap((unsigned short)0x0102)) +
    #|    sizeof(__builtin_bswap((unsigned int)0x01020304)) +
    #|    sizeof(__builtin_bswap((unsigned long long)0x0102030405060708)) +
    #|    sizeof(__builtin_abs(-7)) +
    #|    sizeof(__builtin_labs(-123456789L)) +
    #|    sizeof(__builtin_llabs(-123456789LL)) +
    #|    sizeof(__builtin_is_aligned(32, 16)) +
    #|    sizeof(__builtin_align_up(33, 16)) +
    #|    sizeof(__builtin_align_down((long)47, 16)) +
    #|    sizeof(__builtin_align_up((unsigned long long)0x1234567890, 256)) +
    #|    sizeof(__builtin_rotateleft32(0x12345678u, 8)) +
    #|    sizeof(__builtin_rotateright32(0x12345678u, 8)) +
    #|    sizeof(__builtin_rotateleft64(0x0123456789abcdefull, 16)) +
    #|    sizeof(__builtin_rotateright64(0x0123456789abcdefull, 16)) +
    #|    sizeof(__builtin_rotateleft((unsigned int)0x12345678, 8)) +
    #|    sizeof(__builtin_rotateright((unsigned long long)0x0123456789abcdef, 16)) +
    #|    sizeof(__builtin_expect((long)0x1234567890, 0L)) +
    #|    sizeof(__builtin_expect_with_probability((long long)0x1234567890, 0LL, 0.5)) +
    #|    sizeof(__builtin_unpredictable((unsigned long long)0x1234567890)) +
    #|    sizeof(__builtin_assume_aligned((char *)0, 16)) +
    #|    sizeof(__builtin_constant_p(1));
    #|}
  expect_interp(source, 201L)
}

///|
test "mir interpreter models overflow builtin return sizes" {
  let source =
    #|int main(void) {
    #|  return sizeof(__builtin_add_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_sub_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_mul_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_sadd_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_saddl_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_saddll_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_uadd_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_uaddl_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_uaddll_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_ssub_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_ssubl_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_ssubll_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_usub_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_usubl_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_usubll_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_smul_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_smull_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_smulll_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_umul_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_umull_overflow(1, 2, 0)) +
    #|    sizeof(__builtin_umulll_overflow(1, 2, 0));
    #|}
  expect_interp(source, 21L)
}

///|
test "mir interpreter models void builtin return sizes" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|void *ptr;
    #|int variadic(int last, ...) {
    #|  va_list ap;
    #|  return sizeof(__builtin_va_start(ap, last)) +
    #|    sizeof(__builtin_va_copy(ap, ap)) +
    #|    sizeof(__builtin_va_end(ap));
    #|}
    #|int main(void) {
    #|  return sizeof(__builtin_unreachable()) +
    #|    sizeof(__builtin_trap()) +
    #|    sizeof(__builtin_assume(1)) +
    #|    sizeof(__builtin_prefetch(ptr)) +
    #|    sizeof(__builtin___clear_cache((char *)ptr, (char *)ptr)) +
    #|    sizeof(__builtin_bzero(ptr, 0)) +
    #|    variadic(0, 1);
    #|}
  expect_interp(source, 0L)
  expect_body_interp(source, 0L)
}

///|
test "mir interpreter evaluates prefetch address argument" {
  let source =
    #|int main(void) {
    #|  int side = 0;
    #|  char buf[16];
    #|  __builtin_prefetch((void *)(long)(side += 1), 0, 0);
    #|  __builtin___clear_cache(buf + (side += 2), buf + (side += 4));
    #|  __builtin_assume(side += 10);
    #|  return side + 35;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter evaluates ignored hint operand side effects" {
  let source =
    #|int g = 0;
    #|int bump(void) {
    #|  g += 1;
    #|  return 0;
    #|}
    #|int main(void) {
    #|  int x = 4;
    #|  int y = 0;
    #|  int side = 0;
    #|  int total = 0;
    #|  total += __builtin_expect(x, (side += 1, 1 / y));
    #|  total += __builtin_expect_with_probability(x, bump(), 0.9);
    #|  if ((unsigned long)__builtin_assume_aligned((void*)32, 16, (side += 2, 1 / y)) != 32ul) return 1;
    #|  return total + side + g + 30;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models literal object size builtins" {
  let source =
    #|struct S { int x; char buf[9]; };
    #|char global_buf[16];
    #|struct S global_s;
    #|int main(void) {
    #|  int side = 0;
    #|  int x;
    #|  char buf[16];
    #|  struct S local_s;
    #|  if (__builtin_object_size("abc", 0) != 4) return 1;
    #|  if (__builtin_object_size((const char *)"abc", 1) != 4) return 2;
    #|  if (__builtin_dynamic_object_size("hello", 2) != 6) return 3;
    #|  if (__builtin_dynamic_object_size((const void *)"hello", 3) != 6) return 4;
    #|  if (__builtin_object_size((void *)1, 0) + 1 != 0) return 5;
    #|  if (__builtin_object_size((void *)1, 2) != 0) return 6;
    #|  if (__builtin_dynamic_object_size((void *)(long)(side += 1), 0) + 1 != 0) return 7;
    #|  if (side != 0) return 8;
    #|  if (__builtin_object_size(&x, 0) != sizeof(x)) return 9;
    #|  if (__builtin_dynamic_object_size((void *)buf, 2) != sizeof(buf)) return 10;
    #|  if (__builtin_object_size(&global_s.buf, 0) != sizeof(global_s) - __builtin_offsetof(struct S, buf)) return 11;
    #|  if (__builtin_dynamic_object_size((void *)global_buf, 2) != sizeof(global_buf)) return 12;
    #|  if (__builtin_dynamic_object_size(global_s.buf, 2) != sizeof(global_s) - __builtin_offsetof(struct S, buf)) return 13;
    #|  if (__builtin_dynamic_object_size(global_s.buf, 3) != sizeof(global_s.buf)) return 14;
    #|  if (__builtin_object_size(&local_s.buf, 0) != sizeof(local_s) - __builtin_offsetof(struct S, buf)) return 15;
    #|  if (__builtin_dynamic_object_size(local_s.buf, 2) != sizeof(local_s) - __builtin_offsetof(struct S, buf)) return 16;
    #|  if (__builtin_dynamic_object_size(local_s.buf, 3) != sizeof(local_s.buf)) return 17;
    #|  if (__builtin_object_size(&buf[3], 1) != sizeof(buf) - 3) return 18;
    #|  if (__builtin_object_size(buf + 3, 0) != sizeof(buf) - 3) return 19;
    #|  if (__builtin_dynamic_object_size(&global_s.buf[4], 2) != sizeof(global_s) - __builtin_offsetof(struct S, buf) - 4) return 20;
    #|  if (__builtin_dynamic_object_size(&global_s.buf[4], 3) != sizeof(global_s.buf) - 4) return 21;
    #|  if (!__builtin_constant_p(1 + 2)) return 23;
    #|  if (__builtin_constant_p(side)) return 22;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models zero-initialized global char arrays" {
  let source =
    #|char global_buf[16];
    #|int main(void) {
    #|  if (global_buf[0] != 0 || global_buf[15] != 0) return 1;
    #|  global_buf[0] = 40;
    #|  global_buf[15] = 2;
    #|  return global_buf[0] + global_buf[15];
    #|}
  expect_interp(source, 42L)
  expect_body_interp(source, 42L)
}

///|
test "mir interpreter models designated char array initializers" {
  let source =
    #|char g[8] = { [2] = 40, [5 ... 6] = 1, 2 };
    #|int main(void) {
    #|  char local[8] = { [1] = 20, [4 ... 5] = 10, 2 };
    #|  if (g[0] != 0 || g[1] != 0 || g[3] != 0 || g[4] != 0) return 1;
    #|  if (g[2] != 40 || g[5] != 1 || g[6] != 1 || g[7] != 2) return 2;
    #|  if (local[0] != 0 || local[2] != 0 || local[3] != 0) return 3;
    #|  if (local[1] != 20 || local[4] != 10 || local[5] != 10 || local[6] != 2) return 4;
    #|  return g[2] + g[5] + local[6] - 1;
    #|}
  expect_interp(source, 42L)
  expect_body_interp(source, 42L)
}

///|
test "mir interpreter models aligned char arrays" {
  let source =
    #|char global_buf[8] __attribute__((aligned(32))) = { [1] = 40, [4 ... 5] = 1, 2 };
    #|char global_zero[4] __attribute__((aligned(16)));
    #|int main(void) {
    #|  char local[8] __attribute__((aligned(32))) = { [2] = 20, [5 ... 6] = 10, 2 };
    #|  char local_zero[4] __attribute__((aligned(16))) = {0};
    #|  if (global_zero[0] != 0 || global_zero[3] != 0) return 1;
    #|  if (local_zero[0] != 0 || local_zero[3] != 0) return 2;
    #|  if (global_buf[1] != 40 || global_buf[4] != 1 || global_buf[6] != 2) return 3;
    #|  if (local[2] != 20 || local[5] != 10 || local[6] != 10 || local[7] != 2) return 4;
    #|  return global_buf[1] + global_buf[4] + local[7] - 1;
    #|}
  expect_interp(source, 42L)
  expect_body_interp(source, 42L)
}

///|
test "mir interpreter evaluates unobserved varargs setup builtins" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int variadic(int last, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, last);
    #|  __builtin_va_copy(ap, ap);
    #|  __builtin_va_end(ap);
    #|  return last + 1;
    #|}
    #|int main(void) {
    #|  return variadic(41, 1, 2);
    #|}
  expect_interp(source, 42L)
  expect_body_interp(source, 42L)
}

///|
test "mir interpreter models memory builtin return pointers" {
  let source =
    #|int main(void) {
    #|  char *dst = __builtin_alloca(8);
    #|  char *src = __builtin_alloca(8);
    #|  if (__builtin_memcpy(dst, src, 0) != dst) return 1;
    #|  if (__builtin_memmove(dst, src, 0) != dst) return 2;
    #|  if (__builtin_memset(dst, 0, 0) != dst) return 3;
    #|  if (__builtin___memcpy_chk(dst, src, 0, 8) != dst) return 4;
    #|  if (__builtin___memmove_chk(dst, src, 0, 8) != dst) return 5;
    #|  if (__builtin___memset_chk(dst, 0, 0, 8) != dst) return 6;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models string destination return pointers" {
  let source =
    #|int main(void) {
    #|  char *dst = __builtin_alloca(16);
    #|  int n = 0;
    #|  __builtin_memset(dst, 0, 16);
    #|  if (__builtin_strcpy(dst, "") != dst) return 1;
    #|  if (__builtin___strcpy_chk(dst, "", n += 16) != dst) return 2;
    #|  if (__builtin_strcat(dst, "") != dst) return 3;
    #|  if (__builtin___strcat_chk(dst, "", n += 16) != dst) return 4;
    #|  if (__builtin_strncpy(dst, "", 0) != dst) return 5;
    #|  if (__builtin___strncpy_chk(dst, "", 0, n += 16) != dst) return 6;
    #|  if (__builtin_strncat(dst, "", 0) != dst) return 7;
    #|  if (__builtin___strncat_chk(dst, "", 0, n += 16) != dst) return 8;
    #|  if (n != 64) return 9;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models checked strlcpy literal length" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(8);
    #|  if (__builtin___strlcpy_chk(dst, (const char *)"abcdef", n += 4, 8) != 6) return 1;
    #|  if (n != 4) return 2;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models zero-size checked strlcat literal length" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(1);
    #|  if (__builtin___strlcat_chk(dst, (const char *)"abc", ((n += 1), 0), 1) != 3) return 1;
    #|  if (n != 1) return 2;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models zero-size checked snprintf literal length" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  if (__builtin___snprintf_chk((char *)0, ((n += 1), 0), 0, 0, (const char *)"ready") != 5) return 1;
    #|  if (n != 1) return 2;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models checked snprintf nonzero buffer length" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(4);
    #|  if (__builtin___snprintf_chk(dst, ((n += 1), 4), 0, 4, (const char *)"abcdef") != 6) return 1;
    #|  if (__builtin___snprintf_chk(dst, 4, 0, 4, (const char *)"n=%05d", n += 6) != 7) return 2;
    #|  if (n != 7) return 3;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models checked sprintf literal length" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___sprintf_chk(((n += 1), dst), 0, 16, (const char *)"ready") != 5) return 1;
    #|  if (n != 1) return 2;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models escaped percent checked printf lengths" {
  let source =
    #|int main(void) {
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"%%ok%%") != 4) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"done%%") != 5) return 2;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models checked printf literal length" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  if (__builtin___printf_chk(1, (const char *)"ok%%", n += 1) != 3) return 1;
    #|  if (n != 1) return 2;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models decimal checked printf lengths" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"n=%d", n += 7) != 3) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"neg=%i%%", -12) != 8) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"sum=%d", n) != 5) return 3;
    #|  if (n != 7) return 4;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models length-modified checked printf lengths" {
  let source =
    #|int main(void) {
    #|  long n = 0;
    #|  char *dst = __builtin_alloca(32);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"l=%ld", n += 1234L) != 6) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, (const char *)"%lld%%", -5000LL) != 6) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%zu", 9UL) != 3) return 3;
    #|  if (__builtin___printf_chk(1, (const char *)"x=%llx", 0x1000LL) != 6) return 4;
    #|  if (n != 1234L) return 5;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models width checked printf lengths" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(32);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"n=%05d", n += 7) != 7) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, (const char *)"%-4s%%", (const char *)"hi") != 5) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"c=%3c", 'A') != 5) return 3;
    #|  if (__builtin___printf_chk(1, (const char *)"x=%4x", 0xabc) != 6) return 4;
    #|  if (n != 7) return 5;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models signed flag checked printf lengths" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(32);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"%+d", n += 7) != 2) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, (const char *)"% d%%", 12) != 4) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"x=%+05d", 9) != 7) return 3;
    #|  if (__builtin___printf_chk(1, (const char *)"n=% d", -5) != 4) return 4;
    #|  if (n != 7) return 5;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models alternate checked printf lengths" {
  let source =
    #|int main(void) {
    #|  unsigned int n = 0;
    #|  char *dst = __builtin_alloca(32);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"o=%#o", n += 8) != 5) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, (const char *)"%#x%%", 0x2au) != 5) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"X=%#X", 0xABu) != 6) return 3;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%#x", 0u) != 3) return 4;
    #|  if (n != 8) return 5;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models char checked printf lengths" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"c=%c", n += 65) != 3) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"%c%%", 'Z') != 2) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%c", 0) != 3) return 3;
    #|  if (n != 65) return 4;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models string checked printf lengths" {
  let source =
    #|int main(void) {
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"s=%s", (const char *)"ok") != 4) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"%s%%", (const char *)"abc") != 4) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%s", (const char *)"") != 2) return 3;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models precision string checked printf lengths" {
  let source =
    #|int main(void) {
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"s=%.3s", (const char *)"abcdef") != 5) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"%5.2s%%", (const char *)"abcd") != 6) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%.0s", (const char *)"hide") != 2) return 3;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models decimal precision checked printf lengths" {
  let source =
    #|int main(void) {
    #|  unsigned int n = 0;
    #|  char *dst = __builtin_alloca(32);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"n=%.3u", n += 7) != 5) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, (const char *)"%+.4d%%", 12) != 6) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%.0u", 0u) != 2) return 3;
    #|  if (__builtin___printf_chk(1, (const char *)"w=%04.3d", 7) != 6) return 4;
    #|  if (n != 7) return 5;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models signed decimal precision checked printf lengths" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(32);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"n=%.4d", n -= 12) != 7) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, (const char *)"%+.3d%%", -8) != 5) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"w=%7.3i", -5) != 9) return 3;
    #|  if (n != -12) return 4;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models radix precision checked printf lengths" {
  let source =
    #|int main(void) {
    #|  unsigned int n = 0;
    #|  char *dst = __builtin_alloca(32);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"x=%.4x", n += 0x2a) != 6) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 32, (const char *)"%#.4x%%", 0x2au) != 7) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"o=%#.4o", 8u) != 6) return 3;
    #|  if (__builtin___printf_chk(1, (const char *)"q=%#.2o", 8u) != 5) return 4;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%.0x", 0u) != 2) return 5;
    #|  if (__builtin___printf_chk(1, (const char *)"r=%#.0o", 0u) != 3) return 6;
    #|  if (n != 0x2a) return 7;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models unsigned checked printf lengths" {
  let source =
    #|int main(void) {
    #|  unsigned int n = 0;
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"u=%u", n += 42) != 4) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"%u%%", 100u) != 4) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"n=%u", n) != 4) return 3;
    #|  if (n != 42) return 4;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models hex checked printf lengths" {
  let source =
    #|int main(void) {
    #|  unsigned int n = 0;
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"x=%x", n += 255) != 4) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"%x%%", 4095u) != 4) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%x", 0u) != 3) return 3;
    #|  if (n != 255) return 4;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models uppercase hex checked printf lengths" {
  let source =
    #|int main(void) {
    #|  unsigned int n = 0;
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"X=%X", n += 0xABCD) != 6) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"%X%%", 0x10u) != 3) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%X", 0u) != 3) return 3;
    #|  if (n != 0xABCD) return 4;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models octal checked printf lengths" {
  let source =
    #|int main(void) {
    #|  unsigned int n = 0;
    #|  char *dst = __builtin_alloca(16);
    #|  if (__builtin___snprintf_chk((char *)0, 0, 0, 0, (const char *)"o=%o", n += 64) != 5) return 1;
    #|  if (__builtin___sprintf_chk(dst, 0, 16, (const char *)"%o%%", 511u) != 4) return 2;
    #|  if (__builtin___printf_chk(1, (const char *)"z=%o", 0u) != 3) return 3;
    #|  if (n != 64) return 4;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter evaluates bzero arguments" {
  let source =
    #|int main(void) {
    #|  int n = 0;
    #|  char *dst = __builtin_alloca(1);
    #|  __builtin_bzero(dst, n += 1);
    #|  if (n != 1) return 1;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter evaluates atomic load/store order arguments" {
  let source =
    #|int main(void) {
    #|  unsigned int x = 5;
    #|  int order = 0;
    #|  __atomic_store_n(&x, 37, order += 1);
    #|  if (order != 1) return 1;
    #|  if (__atomic_load_n(&x, order += 2) != 37) return 2;
    #|  return 39 + order;
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter evaluates atomic rmw extra operands" {
  let source =
    #|int main(void) {
    #|  unsigned int x = 5;
    #|  unsigned int expected = 20;
    #|  int order = 0;
    #|  int exchange_order = 0;
    #|  int weak = 0;
    #|  int success = 0;
    #|  int failure = 0;
    #|  if (__atomic_fetch_add(&x, 7, order += 1) != 5) return 1;
    #|  if (x != 12) return 2;
    #|  if (__atomic_exchange_n(&x, 20, exchange_order += 2) != 12) return 3;
    #|  if (!__atomic_compare_exchange_n(&x, &expected, 42, weak += 1, success += 2, failure += 3)) return 4;
    #|  if (x != 42) return 5;
    #|  if (order != 1 || exchange_order != 2 || weak != 1 || success != 2 || failure != 3) return 6;
    #|  return 42;
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter evaluates strlen libcall operation" {
  let source =
    #|int main(void) {
    #|  char s[4] = "ab";
    #|  if (__builtin_strlen(s) != 2) return 1;
    #|  if (__builtin_strlen((const char *)"a\0bc" + 2) != 2) return 2;
    #|  return 42;
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter evaluates compare libcalls" {
  let source =
    #|int main(void) {
    #|  char a[4] = "ab";
    #|  char b[4] = "ac";
    #|  int n = 0;
    #|  if (__builtin_strcmp(a, b) >= 0) return 1;
    #|  if (__builtin_strcmp(b, a) <= 0) return 2;
    #|  if (__builtin_strncmp(a, b, n += 1) != 0) return 3;
    #|  if (__builtin_strncmp(a, b, n += 1) >= 0) return 4;
    #|  if (__builtin_memcmp(a, b, 1) != 0) return 5;
    #|  if (__builtin_memcmp(a, b, 2) >= 0) return 6;
    #|  if (n != 2) return 7;
    #|  return 42;
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter evaluates search libcalls" {
  let source =
    #|int main(void) {
    #|  char s[6] = "abca";
    #|  char hay[6] = "abcde";
    #|  char needle[3] = "cd";
    #|  int n = 0;
    #|  if (__builtin_strchr((n += 1, s), 'b') != s + 1) return 1;
    #|  if (__builtin_strchr(s, 'x') != 0) return 2;
    #|  if (__builtin_strchr(s, 0) != s + 4) return 3;
    #|  if (__builtin_strrchr(s, 'a') != s + 3) return 4;
    #|  if (__builtin_strrchr(s, 0) != s + 4) return 5;
    #|  if (__builtin_memchr(s, 'c', n += 3) != s + 2) return 6;
    #|  if (__builtin_memchr(s, 'a', 0) != 0) return 7;
    #|  if (__builtin_strstr(hay + 1, needle) != hay + 2) return 8;
    #|  if (__builtin_strstr(hay, needle + 1) != hay + 3) return 9;
    #|  if (__builtin_strstr(hay, "") != hay) return 10;
    #|  if (n != 4) return 11;
    #|  return 42;
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter evaluates extended builtin libcalls" {
  let source =
    #|int main(void) {
    #|  char text[10];
    #|  char reject[3];
    #|  char accept[3];
    #|  char raw[8];
    #|  char needle[3];
    #|  char dst[8];
    #|  int n = 0;
    #|  text[0] = 'a';
    #|  text[1] = 'b';
    #|  text[2] = 'c';
    #|  text[3] = '1';
    #|  text[4] = '2';
    #|  text[5] = '3';
    #|  text[6] = 'x';
    #|  text[7] = 'y';
    #|  text[8] = 'z';
    #|  text[9] = 0;
    #|  reject[0] = '2';
    #|  reject[1] = 'z';
    #|  reject[2] = 0;
    #|  accept[0] = 'x';
    #|  accept[1] = 'y';
    #|  accept[2] = 0;
    #|  raw[0] = 'a';
    #|  raw[1] = 0;
    #|  raw[2] = 'b';
    #|  raw[3] = 'c';
    #|  raw[4] = 0;
    #|  raw[5] = 'b';
    #|  raw[6] = 'c';
    #|  raw[7] = 0;
    #|  needle[0] = 0;
    #|  needle[1] = 'b';
    #|  needle[2] = 'c';
    #|  if (__builtin_strnlen(text, n += 10) != 9) return 1;
    #|  if (__builtin_strnlen(text, 4) != 4) return 2;
    #|  if (__builtin_strspn(text, "abc") != 3) return 3;
    #|  if (__builtin_strcspn(text, reject) != 4) return 4;
    #|  if (__builtin_strpbrk(text, accept) != text + 6) return 5;
    #|  if (__builtin_strpbrk(text, "q") != 0) return 6;
    #|  if (__builtin_bcmp(text, "abc123xyz", 9) != 0) return 7;
    #|  if (__builtin_bcmp(text, "abc123xyq", 9) == 0) return 8;
    #|  if (__builtin_memmem(raw, 8, needle, 3) != raw + 1) return 9;
    #|  if (__builtin_memmem(raw + 2, 4, "bc", 2) != raw + 2) return 10;
    #|  if (__builtin_memmem(raw, 2, "bc", 2) != 0) return 11;
    #|  if (__builtin_memmem(raw, 8, "bd", 2) != 0) return 12;
    #|  char *hit = (char *)__builtin_memccpy(dst, raw + 2, 0, 4);
    #|  if (hit != dst + 3) return 13;
    #|  if (dst[0] != 'b' || dst[1] != 'c' || dst[2] != 0) return 14;
    #|  if (__builtin_memccpy(dst, "xy", 'q', 2) != 0) return 15;
    #|  if (dst[0] != 'x' || dst[1] != 'y') return 16;
    #|  if (n != 10) return 17;
    #|  return 42;
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir interpreter models runtime alignment builtins" {
  let source =
    #|int main(void) {
    #|  unsigned long x = 33ul;
    #|  unsigned long a = 16ul;
    #|  int side = 0;
    #|  if (!__builtin_is_aligned(x - 1ul, a)) return 1;
    #|  if (__builtin_is_aligned(x + 1ul, a)) return 2;
    #|  if (__builtin_align_up(x, a) != 48ul) return 3;
    #|  if (__builtin_align_down(47ul, a) != 32ul) return 4;
    #|  if (__builtin_align_up((unsigned long)(side += 33), (unsigned long)(side += -17, a)) != 48ul) return 5;
    #|  if (side != 16) return 6;
    #|  if (__builtin_align_down((unsigned long)(side += 31), a) != 32ul) return 7;
    #|  if (side != 47) return 8;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models constant floating comparison builtins" {
  let source =
    #|int main(void) {
    #|  if (!__builtin_isgreater(2.0, 1.0)) return 1;
    #|  if (!__builtin_isgreaterequal(2.0, 2.0)) return 2;
    #|  if (!__builtin_isless(1.0, 2.0)) return 3;
    #|  if (!__builtin_islessequal(2.0, 2.0)) return 4;
    #|  if (!__builtin_islessgreater(1.0, 2.0)) return 5;
    #|  if (__builtin_islessgreater(2.0, 2.0)) return 6;
    #|  if (!__builtin_isunordered(__builtin_nan(""), 1.0)) return 7;
    #|  if (__builtin_isgreater(__builtin_nan(""), 1.0)) return 8;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models runtime floating comparison builtins" {
  let source =
    #|int main(void) {
    #|  double x = 3.0;
    #|  double y = 2.0;
    #|  double z = 3.0;
    #|  double zero = 0.0;
    #|  double nanv = zero / zero;
    #|  int side = 0;
    #|  if (!__builtin_isgreater(x, y)) return 1;
    #|  if (!__builtin_isgreaterequal(x, z)) return 2;
    #|  if (!__builtin_isless(y, x)) return 3;
    #|  if (!__builtin_islessequal(z, x)) return 4;
    #|  if (!__builtin_islessgreater(y, x)) return 5;
    #|  if (__builtin_islessgreater(x, z)) return 6;
    #|  if (__builtin_islessgreater(nanv, y)) return 7;
    #|  if (!__builtin_isunordered(nanv, y)) return 8;
    #|  if (__builtin_isunordered(x, y)) return 9;
    #|  if (!__builtin_isless((side += 1, y), x)) return 10;
    #|  if (side != 1) return 11;
    #|  return 42;
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir interpreter models constant floating classification builtins" {
  let source =
    #|int main(void) {
    #|  if (!__builtin_isnan(__builtin_nan(""))) return 1;
    #|  if (__builtin_isnan(1.0)) return 2;
    #|  if (!__builtin_isnanf(__builtin_nanf(""))) return 3;
    #|  if (!__builtin_isnanl(__builtin_nanl(""))) return 4;
    #|  if (!__builtin_isinf(__builtin_inf())) return 5;
    #|  if (!__builtin_isinf(-__builtin_inf())) return 6;
    #|  if (__builtin_isinf(1.0)) return 7;
    #|  if (!__builtin_isinff(__builtin_inff())) return 8;
    #|  if (!__builtin_isinfl(__builtin_infl())) return 9;
    #|  if (!__builtin_isfinite(1.0)) return 10;
    #|  if (__builtin_isfinite(__builtin_inf())) return 11;
    #|  if (!__builtin_isfinitef(1.0f)) return 12;
    #|  if (!__builtin_isfinitel(1.0L)) return 13;
    #|  if (!__builtin_isnormal(1.0)) return 14;
    #|  if (__builtin_isnormal(0.0)) return 15;
    #|  if (__builtin_isnormal(__builtin_inf())) return 16;
    #|  if (!__builtin_isnormalf(1.0f)) return 17;
    #|  if (!__builtin_isnormall(1.0L)) return 18;
    #|  if (!__builtin_signbit(-1.0)) return 19;
    #|  if (!__builtin_signbit(-0.0)) return 20;
    #|  if (__builtin_signbit(1.0)) return 21;
    #|  if (!__builtin_signbitf(-0.0f)) return 22;
    #|  if (!__builtin_signbitl(-1.0L)) return 23;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir body interpreter models runtime floating classification builtins" {
  let source =
    #|int main(void) {
    #|  double zero = 0.0;
    #|  double one = 1.0;
    #|  double four = 4.0;
    #|  double nanv = zero / zero;
    #|  double inf = one / zero;
    #|  double ninf = zero - inf;
    #|  double neg = zero - four;
    #|  int side = 0;
    #|  if (!__builtin_isnan(nanv)) return 1;
    #|  if (__builtin_isnan(four)) return 2;
    #|  if (!__builtin_isinf(inf)) return 3;
    #|  if (!__builtin_isinf(ninf)) return 4;
    #|  if (__builtin_isinf(four)) return 5;
    #|  if (!__builtin_isfinite(four)) return 6;
    #|  if (__builtin_isfinite(inf)) return 7;
    #|  if (__builtin_isfinite(nanv)) return 8;
    #|  if (!__builtin_isnormal(four)) return 9;
    #|  if (__builtin_isnormal(zero)) return 10;
    #|  if (__builtin_isnormal(inf)) return 11;
    #|  if (!__builtin_signbit(neg)) return 12;
    #|  if (__builtin_signbit(four)) return 13;
    #|  if (!__builtin_isfinite((side += 1, four))) return 14;
    #|  if (side != 1) return 15;
    #|  return 42;
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter models runtime floating math builtins" {
  let source =
    #|int main(void) {
    #|  double zero = 0.0;
    #|  double one = 1.0;
    #|  double nine = 9.0;
    #|  double mag = 5.0;
    #|  double neg = zero - one;
    #|  int side = 0;
    #|  if ((int)__builtin_sqrt(nine) != 3) return 1;
    #|  if (!__builtin_isnan(__builtin_sqrt(neg))) return 2;
    #|  if ((int)__builtin_copysign(mag, neg) != -5) return 3;
    #|  if ((int)__builtin_copysign(zero - mag, one) != 5) return 4;
    #|  if (!__builtin_signbit(__builtin_copysign(zero, neg))) return 5;
    #|  if ((int)__builtin_sqrt((side += 1, nine)) != 3) return 6;
    #|  if ((int)__builtin_copysign((side += 2, mag), (side += 4, neg)) != -5) return 7;
    #|  if (side != 7) return 8;
    #|  return 42;
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir interpreter casts folded floating builtins" {
  let source =
    #|int main(void) {
    #|  if ((int)__builtin_fabs(-4.5) != 4) return 1;
    #|  if ((int)__builtin_fabsf(-3.5f) != 3) return 2;
    #|  if ((int)__builtin_fabsl(-2.5L) != 2) return 3;
    #|  if ((int)__builtin_copysign(3.0, -1.0) != -3) return 4;
    #|  if ((int)__builtin_copysign(-3.0, 1.0) != 3) return 5;
    #|  if (!__builtin_signbit(__builtin_copysign(0.0, -1.0))) return 6;
    #|  if ((int)__builtin_sqrt(81.0) != 9) return 7;
    #|  if ((int)__builtin_sqrtf(25.0f) != 5) return 8;
    #|  if ((int)__builtin_sqrtl(16.0L) != 4) return 9;
    #|  if (!__builtin_isnan(__builtin_sqrt(-1.0))) return 10;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models literal string comparison builtins" {
  let source =
    #|int main(void) {
    #|  if (__builtin_strcmp("abc", "abc") != 0) return 1;
    #|  if (__builtin_strcmp("abc", "abd") >= 0) return 2;
    #|  if (__builtin_strcmp((const char *)"abd", "abc") <= 0) return 3;
    #|  if (__builtin_strncmp("abc", "abd", 2) != 0) return 4;
    #|  if (__builtin_strncmp("abc", "abd", 3) >= 0) return 5;
    #|  if (__builtin_strncmp("abc", "abd", 0) != 0) return 6;
    #|  if (__builtin_memcmp("abc", "abd", 2) != 0) return 7;
    #|  if (__builtin_memcmp("abc", "abd", 3) >= 0) return 8;
    #|  if (__builtin_memcmp("abd", "abc", 3) <= 0) return 9;
    #|  if (__builtin_bcmp("abc", "abc", 3) != 0) return 10;
    #|  if (__builtin_bcmp("abc", "abd", 3) == 0) return 11;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models literal string search nullness" {
  let source =
    #|int main(void) {
    #|  if (__builtin_strchr("abc", 'b') == 0) return 1;
    #|  if (__builtin_strchr("abc", 'x') != 0) return 2;
    #|  if (__builtin_strchr("abc", 0) == 0) return 3;
    #|  if (__builtin_strrchr("abba", 'b') == 0) return 4;
    #|  if (__builtin_memchr("abc", 'b', 2) == 0) return 5;
    #|  if (__builtin_memchr("abc", 'c', 2) != 0) return 6;
    #|  if (__builtin_strstr("abcde", "cd") == 0) return 7;
    #|  if (__builtin_strstr("abcde", "ce") != 0) return 8;
    #|  if (__builtin_strstr("abc", "") == 0) return 9;
    #|  if (__builtin_memmem("a\0bc\0bc", 7, "\0bc", 3) == 0) return 10;
    #|  if (__builtin_memmem("a\0bc\0bc", 1, "\0bc", 3) != 0) return 11;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models literal string search pointer offsets" {
  let source =
    #|int main(void) {
    #|  if (__builtin_strchr("abc", 'a') != "abc") return 1;
    #|  if (__builtin_strchr("abc", 'b') != "abc" + 1) return 2;
    #|  if (__builtin_strchr("abc", 0) != "abc" + 3) return 3;
    #|  if (__builtin_strrchr("abba", 'b') != "abba" + 2) return 4;
    #|  if (__builtin_strrchr("abba", 0) != "abba" + 4) return 5;
    #|  if (__builtin_memchr("abc", 'b', 2) != "abc" + 1) return 6;
    #|  if (__builtin_memchr("abc", 0, 4) != "abc" + 3) return 7;
    #|  if (__builtin_strstr("abcde", "cd") != "abcde" + 2) return 8;
    #|  if (__builtin_strstr("abc", "") != "abc") return 9;
    #|  if (__builtin_memmem("a\0bc\0bc", 7, "\0bc", 3) != "a\0bc\0bc" + 1) return 10;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter models literal string span builtins" {
  let source =
    #|int main(void) {
    #|  const char *text = "abc123xyz";
    #|  const char *reject = "2z";
    #|  const char *accept = "xy";
    #|  if (__builtin_strspn(text, "abc") != 3) return 1;
    #|  if (__builtin_strspn(text + 3, "12345") != 3) return 2;
    #|  if (__builtin_strspn(text, "") != 0) return 3;
    #|  if (__builtin_strcspn(text, reject) != 4) return 4;
    #|  if (__builtin_strcspn(text, "") != 9) return 5;
    #|  if (__builtin_strpbrk(text, accept) != text + 6) return 6;
    #|  if (__builtin_strpbrk(text, "31") != text + 3) return 7;
    #|  if (__builtin_strpbrk(text, "") != 0) return 8;
    #|  if (__builtin_strpbrk(text, "q") != 0) return 9;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter reports unsupported memory behavior" {
  let source = "int main(void) { int *p = (int*)0; return *p; }"
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.interpret_i64("main", []) {
    Ok(_) => abort("expected MIR interpreter unsupported-memory error")
    Err(err) => inspect(err.contains("memory"), content="true")
  }
}

///|
test "mir interpreter defers unused unsupported local declarations" {
  let source =
    #|struct S { int x; };
    #|union U { int x; double y; };
    #|int main(void) {
    #|  double d;
    #|  int a[2];
    #|  struct S s;
    #|  union U u;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
}

///|
test "mir interpreter reports unsupported local reads" {
  let source = "int main(void) { double d; return (int)d; }"
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.interpret_i64("main", []) {
    Ok(_) => abort("expected MIR interpreter unsupported-local-value error")
    Err(err) => inspect(err.contains("local value"), content="true")
  }
}

///|
test "mir interpreter evaluates ignored unsupported local initializer side effects" {
  let source =
    #|int main(void) {
    #|  int side = 0;
    #|  int a[2];
    #|  double d = (a[side += 1] = side += 2);
    #|  double e = side += 4;
    #|  return side + 35;
    #|}
  expect_interp(source, 42L)
  expect_body_interp(source, 42L)
}

///|
test "mir interpreter evaluates ignored modeled byte writes" {
  let source =
    #|int main(void) {
    #|  char s[4] = "abc";
    #|  char *p = s;
    #|  int side = 0;
    #|  double d = (s[side += 1] = 'z');
    #|  double e = (++s[2], s[2] += 1);
    #|  double f = (*(p + 0) = 'A');
    #|  if (side != 1) return 1;
    #|  if (s[0] != 'A') return 2;
    #|  if (s[1] != 'z') return 3;
    #|  if (s[2] != 'e') return 4;
    #|  return 42;
    #|}
  expect_interp(source, 42L)
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles floating local casts to int" {
  let source =
    #|int main(void) {
    #|  double x = 1.75;
    #|  double y = 2.25;
    #|  return (int)x + (int)y;
    #|}
  expect_body_interp(source, 3L)
}

///|
test "mir body interpreter handles floating local comparisons" {
  let source =
    #|int main(void) {
    #|  double x = 1.5;
    #|  double y = 2.5;
    #|  return (x < y) + (x != y) + (y > 2.0) + (x == 1.5) + (x <= y) + (y >= x);
    #|}
  expect_body_interp(source, 6L)
}

///|
test "mir body interpreter handles floating local arithmetic" {
  let source =
    #|int main(void) {
    #|  double x = 5.5;
    #|  double y = 2.0;
    #|  return (int)(x + y) + (int)(x - y) + (int)(x * y) + (int)(x / y) + (int)(x + 2);
    #|}
  expect_body_interp(source, 30L)
}

///|
test "mir body interpreter handles floating direct calls" {
  let source =
    #|double add(double x, double y) { return x + y; }
    #|double mix(int a, double b, int c) { return a + b + c; }
    #|int main(void) {
    #|  return (int)add(2.25, 3.75) + (int)mix(2, 3.5, 4);
    #|}
  expect_body_interp(source, 15L)
}

///|
test "mir body interpreter handles floating indirect calls" {
  let source =
    #|double add(double x, double y) { return x + y; }
    #|double mix(int a, double b, int c) { return a + b + c; }
    #|int main(void) {
    #|  double (*fp)(double, double) = add;
    #|  double (*gp)(int, double, int) = mix;
    #|  return (int)fp(2.25, 3.75) + (int)gp(2, 3.5, 4);
    #|}
  expect_body_interp(source, 15L)
}

///|
test "mir body interpreter handles ignored floating variadic args" {
  let source =
    #|double variadic(int tag, ...) { return tag + 1.0; }
    #|int main(void) {
    #|  return (int)variadic(1, 2.5);
    #|}
  expect_body_interp(source, 2L)
}

///|
test "mir body interpreter handles aggregate direct call arguments" {
  let source =
    #|struct Pair { int a; int b; };
    #|int pair_sum(struct Pair p) {
    #|  return p.a + p.b;
    #|}
    #|int forward_sum(struct Pair p) {
    #|  return pair_sum(p);
    #|}
    #|int main(void) {
    #|  struct Pair p = {10, 32};
    #|  return forward_sum(p);
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles aggregate return call results" {
  let source =
    #|struct Pair { int a; int b; };
    #|struct Pair make_pair(int a, int b) {
    #|  struct Pair p;
    #|  p.a = a;
    #|  p.b = b;
    #|  return p;
    #|}
    #|struct Pair forward_pair(int a, int b) {
    #|  return make_pair(a + 1, b + 2);
    #|}
    #|int main(void) {
    #|  struct Pair p = make_pair(10, 20);
    #|  struct Pair q;
    #|  q = forward_pair(3, 4);
    #|  return p.a + p.b + q.a + q.b;
    #|}
  expect_body_interp(source, 40L)
}

///|
test "mir body interpreter reads fields from aggregate call results" {
  let source =
    #|struct Pair { int a; int b; };
    #|struct Pair make_pair(int a, int b) {
    #|  struct Pair p;
    #|  p.a = a;
    #|  p.b = b;
    #|  return p;
    #|}
    #|int main(void) {
    #|  return make_pair(5, 6).a + make_pair(7, 8).b;
    #|}
  expect_body_interp(source, 13L)
}

///|
test "mir body interpreter handles indirect aggregate return calls" {
  let source =
    #|struct Pair { int a; int b; };
    #|struct Pair make_pair(int a, int b) {
    #|  struct Pair p;
    #|  p.a = a;
    #|  p.b = b;
    #|  return p;
    #|}
    #|int main(void) {
    #|  struct Pair (*fp)(int, int) = make_pair;
    #|  struct Pair p = fp(19, 23);
    #|  return p.a + p.b;
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles scalar va_arg reads" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int read_variadic(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  int a = __builtin_va_arg(ap, int);
    #|  long long b = __builtin_va_arg(ap, long long);
    #|  double c = __builtin_va_arg(ap, double);
    #|  __builtin_va_end(ap);
    #|  return tag + a + (int)b + (int)c;
    #|}
    #|int main(void) {
    #|  return read_variadic(4, 10, 20LL, 3.5);
    #|}
  expect_body_interp(source, 37L)
}

///|
test "mir body interpreter handles aggregate va_arg reads" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|struct Pair { int a; int b; };
    #|int read_pair(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  struct Pair p = __builtin_va_arg(ap, struct Pair);
    #|  __builtin_va_end(ap);
    #|  return tag + p.a + p.b;
    #|}
    #|int main(void) {
    #|  struct Pair p = {10, 20};
    #|  return read_pair(12, p);
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter reads members from aggregate va_arg rvalues" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|struct Pair { int a; int b; };
    #|int pick(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  int value = __builtin_va_arg(ap, struct Pair).b;
    #|  __builtin_va_end(ap);
    #|  return tag + value;
    #|}
    #|int main(void) {
    #|  struct Pair p = {10, 32};
    #|  return pick(10, p);
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles aggregate va_copy cursors" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|struct Pair { int a; int b; };
    #|int copy_pair(int tag, ...) {
    #|  va_list ap;
    #|  va_list copy;
    #|  __builtin_va_start(ap, tag);
    #|  __builtin_va_copy(copy, ap);
    #|  struct Pair first = __builtin_va_arg(ap, struct Pair);
    #|  struct Pair copied = __builtin_va_arg(copy, struct Pair);
    #|  __builtin_va_end(copy);
    #|  __builtin_va_end(ap);
    #|  return tag + first.a + copied.b;
    #|}
    #|int main(void) {
    #|  struct Pair p = {10, 20};
    #|  return copy_pair(12, p);
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter handles va_copy cursors" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int copy_variadic(int tag, ...) {
    #|  va_list ap;
    #|  va_list copy;
    #|  __builtin_va_start(ap, tag);
    #|  __builtin_va_copy(copy, ap);
    #|  int first = __builtin_va_arg(ap, int);
    #|  int copied = __builtin_va_arg(copy, int);
    #|  __builtin_va_end(copy);
    #|  __builtin_va_end(ap);
    #|  return first + copied;
    #|}
    #|int main(void) {
    #|  return copy_variadic(0, 21);
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir body interpreter passes va_list handles to literal vprintf models" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int count_variadic(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  int n = __builtin___vprintf_chk(1, "ok", ap);
    #|  __builtin_va_end(ap);
    #|  return tag + n;
    #|}
    #|int main(void) {
    #|  return count_variadic(40, 1);
    #|}
  expect_body_interp(source, 42L)
}

///|
test "mir interpreter reports unsupported initialized local reads" {
  let source = "int main(void) { double d = 0.0; return (int)d; }"
  let mir = @mir.lower(@parser.parse(source), @target.Target::default())
  match mir.interpret_i64("main", []) {
    Ok(_) => abort("expected MIR interpreter unsupported-local-value error")
    Err(err) => inspect(err.contains("local value"), content="true")
  }
}
