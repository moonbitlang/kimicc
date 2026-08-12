///|
/// Top-level entries print in the order the source declared them.
///
/// The grouped arrays alone would put every global ahead of every function,
/// and a global initializer naming a function declared later would print
/// before the name exists -- C requires declaration before use at file scope.
test "printing preserves top-level source order" {
  let source =
    #|static void on_event(int code);
    #|static void (*handler)(int) = on_event;
    #|static void on_event(int code) {
    #|}
  let printed = @printer.print_program(@parser.parse(source))
  let decl_at = printed.find("static void on_event(int")
  let global_at = printed.find("handler")
  guard decl_at is Some(decl_index) && global_at is Some(global_index) else {
    fail("expected both declarations in the output: \{printed}")
  }
  assert_true(decl_index < global_index)
  // And the printed order survives a reparse.
  assert_eq(printed, @printer.print_program(@parser.parse(printed)))
}

///|
/// An anonymous member prints as the untagged inline definition C11 requires
/// for its members to reach through. `union __anon_union_0;` -- the tag
/// reference the synthetic name suggests -- declares nothing, and every
/// access through the member fails to compile.
test "anonymous members print inline and untagged" {
  let source =
    #|struct S {
    #|  int tag;
    #|  union { int i; float f; };
    #|  struct { char a; char b; };
    #|};
    #|int f(struct S *s) { return s->tag + s->i + s->a; }
  let printed = @printer.print_program(@parser.parse(source))
  assert_true(printed.contains("union {"))
  assert_true(printed.contains("struct {"))
  // The synthetic tag appears nowhere: not on the member, not as a hoisted
  // top-level definition, not as a forward declaration.
  assert_true(!printed.contains("__anon_"))
  // Nested anonymity: an anonymous union carrying an anonymous struct.
  let nested =
    #|struct T {
    #|  union {
    #|    struct { int lo; int hi; };
    #|    long both;
    #|  };
    #|};
    #|long g(struct T *t) { return t->lo + t->both; }
  let nested_printed = @printer.print_program(@parser.parse(nested))
  assert_true(!nested_printed.contains("__anon_"))
  assert_eq(
    nested_printed,
    @printer.print_program(@parser.parse(nested_printed)),
  )
}

///|
/// Reparse gives anonymous aggregates the same synthetic names and the same
/// creation order, so the AST is a fixed point even though the names never
/// appear in the printed text. Two shapes matter. A definition written in a
/// member list -- named member or anonymous -- prints back inside its parent,
/// so reparse re-creates it at the same member position. A typedef'd
/// anonymous type has no member site; its definition prints *tagged* at its
/// own top-level position, holding its number as an explicit tag, and the
/// parser's synthesis skips taken numbers so the re-synthesized members
/// still land where they were.
test "anonymous aggregate numbering survives reparse" {
  let source =
    #|typedef struct { int wide; } Boxed;
    #|struct Mixed {
    #|  struct { int x; } named;
    #|  union { int i; char c; };
    #|};
    #|static Boxed box = { 3 };
    #|int f(struct Mixed *m) { return m->named.x + m->i + box.wide; }
  let first = @parser.parse(source)
  let printed = @printer.print_program(first)
  // The typedef'd definition keeps its synthetic tag -- it has no member
  // site and prints at top level -- while both member definitions print
  // tagless, the way they were written, which is also what keeps their
  // `is_anonymous` a reparse fixed point.
  assert_true(printed.contains("struct __anon_struct_0 {"))
  assert_true(!printed.contains("__anon_struct_1"))
  assert_true(!printed.contains("__anon_union_2"))
  let second = @parser.parse(printed)
  // The typedef'd definition's anonymity is consumed by its tagged print;
  // the member definitions round-trip exactly.
  assert_true(structs_roundtrip_equal(first.structs, second.structs))
  assert_eq(first.globals, second.globals)
  assert_eq(printed, @printer.print_program(second))
}

///|
/// A named member of a tagless type and a named nested definition both print
/// inside their parent, as written. Hoisting them to the top would compile,
/// but on reparse they would be created ahead of their parent instead of at
/// their member position, and the grouped array would stop being a fixed
/// point -- QuickJS's JSObject, whose member list mixes anonymous members
/// with named members of tagless types, is where that surfaced.
test "named members of nested definitions print inline" {
  let source =
    #|struct Outer {
    #|  struct { long a; long b; } func;
    #|  struct Inner { int x; } in_;
    #|  struct { int size; } *by_pointer;
    #|};
    #|struct Inner reuse(struct Inner given) { return given; }
  let first = @parser.parse(source)
  let printed = @printer.print_program(first)
  assert_true(printed.contains("} func;"))
  assert_true(printed.contains("struct Inner {"))
  assert_true(printed.contains("} *by_pointer;"))
  let second = @parser.parse(printed)
  assert_eq(first.structs, second.structs)
  assert_eq(printed, @printer.print_program(second))
}

///|
/// Every tag is declared at file scope before anything mentions it, including
/// tags the program traffics in but never defines. Without the declaration, a
/// tag first mentioned inside a prototype's parameter list has prototype
/// scope and is a different type from every later mention -- sqlite's opaque
/// `sqlite3_stmt` is the shape.
test "opaque tags get file-scope forward declarations" {
  let source =
    #|struct Opaque;
    #|int probe(struct Opaque *o);
    #|int call(struct Opaque *o) { return probe(o); }
  let printed = @printer.print_program(@parser.parse(source))
  guard printed.find("struct Opaque;") is Some(fwd) else {
    fail("expected a forward declaration: \{printed}")
  }
  guard printed.find("int probe(") is Some(proto) else {
    fail("expected the prototype: \{printed}")
  }
  assert_true(fwd < proto)
}

///|
/// A pointer to a function-typedef'd type is the function pointer itself.
/// `typedef void F(int)` then `F *f` must print one star's worth of type, not
/// pointer-to-function-pointer -- QuickJS declares every callback slot this
/// way, and the extra level made each one a type error.
test "function typedef pointers stay one level" {
  let source =
    #|typedef char *Norm(int ctx);
    #|struct Slots { Norm *n; };
    #|static char *normalize(int ctx) { return (char *)0; }
    #|static struct Slots slots = { normalize };
    #|char *run(int ctx) { return slots.n(ctx); }
  let program = @parser.parse(source)
  guard program.structs[0].fields[0].ty is FuncPtr(_, _, _) else {
    fail("expected a single-level function pointer field")
  }
  let printed = @printer.print_program(program)
  assert_true(printed.contains("char *(*n)(int)"))
  assert_eq(printed, @printer.print_program(@parser.parse(printed)))
}

///|
/// Items index the grouped arrays rather than holding copies, so replacing an
/// element of a grouped array -- the ordinary way to transform a program --
/// is what prints. A value-carrying items tape silently printed the original.
test "replacing a grouped entry prints the replacement" {
  let source =
    #|int before = 1;
    #|int keep(void) { return before; }
  let program = @parser.parse(source)
  program.globals[0] = { ..program.globals[0], name: "after" }
  program.decls[0] = { ..program.decls[0], name: "renamed" }
  let printed = @printer.print_program(program)
  assert_true(printed.contains("int after = 1;"))
  assert_true(!printed.contains("before = 1"))
  assert_true(printed.contains("int renamed(void)"))
}

///|
/// A named member keeps its synthesized tag, because the tag can escape:
/// `typeof` recovers the member's type, and a declaration built from it
/// references the tag by name. Dropping the tag from the inline definition
/// would leave that reference incomplete.
test "typeof of a named member keeps the tag it references" {
  let source =
    #|struct S { struct { int x; } member; };
    #|typeof(((struct S *)0)->member) copy;
    #|int read_copy(void) { return copy.x; }
  let first = @parser.parse(source)
  let printed = @printer.print_program(first)
  // The tag appears on the inline definition and on the recovered reference.
  // Spelling the tag out is what makes `copy` complete, and it is also the
  // one case where anonymity is not a reparse fixed point: the reparse sees
  // a written tag. Valid output wins over provenance here, so the assertions
  // are on the text and its stability rather than on structs equality.
  assert_true(printed.contains("struct __anon_struct_0 {"))
  assert_true(printed.contains("struct __anon_struct_0 copy;"))
  let second = @parser.parse(printed)
  assert_eq(first.globals, second.globals)
  assert_eq(printed, @printer.print_program(second))
}

///|
/// Layout modifiers survive inlining: a nested definition under `#pragma
/// pack(push, 2)` keeps its cap through the printed member, and an `_Alignas`
/// on the member's type keeps its wrapper ahead of the inline definition.
test "inline definitions keep packing caps and alignment wrappers" {
  let source =
    #|#pragma pack(push, 2)
    #|struct Outer {
    #|  struct { char c; int i; } packed_member;
    #|};
    #|#pragma pack(pop)
    #|int probe(struct Outer *o) { return o->packed_member.i; }
  let first = @parser.parse(source)
  guard first.structs[0].pack is Some(2) else {
    fail("expected the nested definition to carry the cap")
  }
  let printed = @printer.print_program(first)
  let second = @parser.parse(printed)
  assert_eq(first.structs, second.structs)
  assert_eq(printed, @printer.print_program(second))
  let aligned =
    #|struct Holder {
    #|  _Alignas(16) struct { int v; } slot;
    #|};
    #|int use_slot(struct Holder *h) { return h->slot.v; }
  let first_aligned = @parser.parse(aligned)
  let printed_aligned = @printer.print_program(first_aligned)
  assert_true(printed_aligned.contains("_Alignas(16) struct"))
  assert_eq(first_aligned.structs, @parser.parse(printed_aligned).structs)
}

///|
/// A written tag that merely resembles a synthesized one -- vendor headers do
/// use `__anon_` prefixed names -- is an ordinary name: it keeps its forward
/// declaration and its spelling everywhere.
test "user tags with an __anon_ prefix stay ordinary names" {
  let source =
    #|struct __anon_Node;
    #|int probe(struct __anon_Node *n);
    #|struct __anon_Node { int v; };
    #|int probe(struct __anon_Node *n) { return n->v; }
    #|int call(struct __anon_Node *n) { return probe(n); }
  let first = @parser.parse(source)
  let printed = @printer.print_program(first)
  guard printed.find("struct __anon_Node;") is Some(fwd) else {
    fail("expected a forward declaration: \{printed}")
  }
  guard printed.find("int probe(") is Some(proto) else {
    fail("expected the prototype")
  }
  assert_true(fwd < proto)
  assert_eq(first.structs, @parser.parse(printed).structs)
}

///|
/// One nested definition, several members: the first prints the definition
/// and the rest reference the tag, since a second inline body would be a
/// redefinition.
test "a nested definition shared by members prints once" {
  let source =
    #|struct O {
    #|  struct I { int x; } a, b;
    #|};
    #|int probe(struct O *o) { return o->a.x + o->b.x; }
  let first = @parser.parse(source)
  let printed = @printer.print_program(first)
  // One definition, one reference: exactly one occurrence of the body.
  let mut defs = 0
  for i in 0..<printed.length() {
    if printed[i:].to_owned().has_prefix("struct I {") {
      defs += 1
    }
  }
  assert_eq(defs, 1)
  assert_true(printed.contains("struct I b;"))
  let second = @parser.parse(printed)
  assert_eq(first.structs, second.structs)
  assert_eq(printed, @printer.print_program(second))
}

///|
/// A definition that occurs inside a member's expression -- `sizeof` over an
/// inline definition -- has no member site to print at, so it prints at top
/// level rather than surviving only as a forward declaration that leaves the
/// type incomplete.
test "definitions inside member expressions stay printable" {
  let source =
    #|struct O { int a[sizeof(struct I { int x; })]; };
    #|struct I value;
    #|int read_value(void) { return value.x; }
  let printed = @printer.print_program(@parser.parse(source))
  assert_true(printed.contains("struct I {"))
  // The printed text parses and keeps the definition.
  let second = @parser.parse(printed)
  let mut found = false
  for decl in second.structs {
    if decl.name == "I" && decl.fields.length() == 1 {
      found = true
    }
  }
  assert_true(found)
}

///|
/// A definition inlines at its defining member, not at the first field that
/// happens to carry the tag. After a forward declaration, an earlier
/// aggregate may reference a tag defined inside a later one; pulling the
/// definition forward would also drag it under the earlier aggregate's
/// packing context and change its layout.
test "definitions inline at their defining member only" {
  let source =
    #|struct I;
    #|#pragma pack(push, 1)
    #|struct A { struct I *p; };
    #|#pragma pack(pop)
    #|struct B { struct I { char c; int x; } i; };
    #|int probe(struct B *b) { return b->i.x; }
  let first = @parser.parse(source)
  let printed = @printer.print_program(first)
  // A references; B defines.
  assert_true(printed.contains("struct I *p;"))
  let second = @parser.parse(printed)
  assert_eq(first.structs, second.structs)
  assert_eq(printed, @printer.print_program(second))
}

///|
/// Appending to a grouped array is the simplest way to add a declaration to a
/// parsed program, and it prints -- at the end, after everything it may
/// reference -- even though `items` carries no index for it.
test "entries appended after parsing still print" {
  let program = @parser.parse(
    (
      #|int base = 1;
      #|int read_base(void) { return base; }
    ),
  )
  program.globals.push({
    ty: SInt,
    name: "appended",
    init: Some(Scalar(@parser.int_literal(2, SInt))),
    is_static: false,
    is_extern: false,
    is_weak: false,
    visibility: None,
    symbol_alias: None,
    section: None,
  })
  program.decls.push({
    ret: SInt,
    name: "sum",
    params: [],
    variadic: false,
    is_static: false,
    is_inline: false,
    is_weak: false,
    visibility: None,
    symbol_alias: None,
    section: None,
    is_constructor: false,
    is_destructor: false,
    body: Some(
      Compound([Return(Some(Binary("+", Var("base"), Var("appended"))))]),
    ),
  })
  let printed = @printer.print_program(program)
  assert_true(printed.contains("int appended = 2;"))
  // Appended entries print after the parsed ones.
  guard printed.find("read_base") is Some(parsed_at) else {
    fail("missing parsed function")
  }
  guard printed.find("appended") is Some(appended_at) else {
    fail("missing appended global")
  }
  assert_true(parsed_at < appended_at)
}

///|
/// A typedef that reuses a name for a non-function type retires the
/// function-typedef marker, so `F *p` under the new meaning declares a
/// pointer rather than absorbing its star.
test "shadowing a function typedef retires the marker" {
  let source =
    #|typedef int F(void);
    #|typedef int F;
    #|F *p;
    #|int read_p(void) { return *p; }
  let program = @parser.parse(source)
  guard program.globals[0].ty is Pointer(SInt) else {
    fail("expected a plain pointer: \{Repr(program.globals[0].ty)}")
  }
}

///|
/// A struct appended to the grouped array is a top-level entry, printed at
/// the end -- after the parsed definitions its members may need complete.
test "appended aggregates print as top-level definitions" {
  let source =
    #|struct Base { int v; };
    #|int use_base(struct Base *b) { return b->v; }
  let program = @parser.parse(source)
  program.structs.push({
    name: "Added",
    fields: [{ ty: Struct("Base"), name: "value", bit_width: None }],
    is_union: false,
    pack: None,
    is_anonymous: false,
  })
  let printed = @printer.print_program(program)
  guard printed.find("struct Base {") is Some(base_at) else {
    fail("missing Base definition")
  }
  guard printed.find("struct Added {") is Some(added_at) else {
    fail("missing Added definition: \{printed}")
  }
  // Added's by-value member needs Base complete first.
  assert_true(base_at < added_at)
}

///|
/// A tag referenced as one kind in a prototype and defined as the other kind
/// at file scope lived in two scopes in the source. No file-scope forward
/// can serve both, so the definition relies on its own position and the
/// prototype's tag stays prototype-scoped, as it was.
test "kind-conflicted tags get no file-scope forward" {
  let source =
    #|int probe(struct X *arg);
    #|union X { int i; };
    #|int read_x(union X *u) { return u->i; }
  let printed = @printer.print_program(@parser.parse(source))
  // No `union X;` may precede the prototype that says `struct X *`.
  guard printed.find("int probe(") is Some(proto_at) else {
    fail("missing prototype")
  }
  match printed.find("union X;") {
    Some(fwd_at) => assert_true(fwd_at > proto_at)
    None => ()
  }
  guard printed.find("union X {") is Some(def_at) else {
    fail("missing union definition")
  }
  assert_true(proto_at < def_at)
}

///|
/// A definition hidden inside a member expression prints just before its
/// containing aggregate, so the types its own fields need -- defined above
/// it in the source -- are already complete.
test "hidden definitions print after their dependencies" {
  let source =
    #|struct J { int x; };
    #|struct O { int a[sizeof(struct I { struct J j; })]; };
    #|struct I standalone;
    #|int read_i(void) { return standalone.j.x; }
  let printed = @printer.print_program(@parser.parse(source))
  guard printed.find("struct J {") is Some(j_at) else {
    fail("missing J definition")
  }
  guard printed.find("struct I {") is Some(i_at) else {
    fail("missing I definition: \{printed}")
  }
  guard printed.find("struct O {") is Some(o_at) else {
    fail("missing O definition")
  }
  assert_true(j_at < i_at)
  assert_true(i_at < o_at)
}

///|
/// A source-written tag shaped exactly like a synthesized one is still a
/// written tag. On an empty-named nested definition it is a tag declaration,
/// not an anonymous member, and stripping it would orphan every reference.
test "written tags shaped like synthesized ones keep their spelling" {
  let source =
    #|struct Outer { struct __anon_struct_0 { int x; }; };
    #|struct __anon_struct_0 value;
    #|int read_value(void) { return value.x; }
  let first = @parser.parse(source)
  let printed = @printer.print_program(first)
  // The tag survives on the nested definition, so `value` stays complete.
  assert_true(printed.contains("struct __anon_struct_0 {"))
  let second = @parser.parse(printed)
  assert_eq(first.structs, second.structs)
  assert_eq(first.globals, second.globals)
}

///|
/// A local prototype surfaces at the front of `decls` and of the function
/// items alike, so the two views agree and a reparse stores the same order.
test "local prototypes keep decls and items in one order" {
  let source =
    #|int f(void) {
    #|  int helper(int arg);
    #|  return helper(1);
    #|}
  let first = @parser.parse(source)
  assert_eq(first.decls[0].name, "helper")
  assert_eq(first.decls[1].name, "f")
  let printed = @printer.print_program(first)
  let second = @parser.parse(printed)
  assert_eq(first.decls, second.decls)
  assert_eq(first.items, second.items)
  assert_eq(printed, @printer.print_program(second))
}

///|
/// The two spellings of an empty-named nested definition are different C --
/// `struct { int x; };` is an anonymous member whose `x` reaches through,
/// `struct Tag { int x; };` declares no member at all -- and they compare
/// unequal even when the written tag matches the synthesized spelling.
test "anonymity is part of equality" {
  let anonymous =
    #|struct Outer { struct { int x; }; };
  let tagged =
    #|struct Outer { struct __anon_struct_0 { int x; }; };
  let first = @parser.parse(anonymous)
  let second = @parser.parse(tagged)
  assert_true(first.structs != second.structs)
}

///|
/// A tag whose only reference lives inside an expression -- `sizeof` over a
/// `typeof` recovery -- still forces the synthesized tag to be spelled out,
/// or the expression would name an incomplete type.
test "expression-only tag references keep the tag spelled" {
  let source =
    #|struct S { struct { int x; } member; };
    #|int probe(void) { return sizeof(typeof(((struct S *)0)->member)); }
  let printed = @printer.print_program(@parser.parse(source))
  assert_true(printed.contains("struct __anon_struct_0 {"))
  assert_true(printed.contains("sizeof(struct __anon_struct_0)"))
  assert_eq(printed, @printer.print_program(@parser.parse(printed)))
}

///|
/// A hidden definition prints tagged, so its forward declaration appears on
/// the first print -- the same text a reparse would produce, keeping the
/// canonical fixed point.
test "hidden definitions are a print fixed point" {
  let source =
    #|struct O { int a[sizeof(struct I { int x; })]; };
    #|int probe(struct O *o) { return o->a[0]; }
  let printed = @printer.print_program(@parser.parse(source))
  assert_eq(printed, @printer.print_program(@parser.parse(printed)))
}

///|
/// A hand-built program classifies anonymous members by provenance, not by
/// the spelling of the synthesized name.
test "hand-built anonymous members inline by provenance" {
  let inner : @parser.StructDecl = {
    name: "synthetic_tag",
    fields: [{ ty: SInt, name: "value", bit_width: None }],
    is_union: false,
    pack: None,
    is_anonymous: true,
  }
  let outer : @parser.StructDecl = {
    name: "Outer",
    fields: [{ ty: Struct("synthetic_tag"), name: "", bit_width: None }],
    is_union: false,
    pack: None,
    is_anonymous: false,
  }
  let program : @parser.Program = {
    structs: [inner, outer],
    globals: [],
    decls: [],
    items: [],
  }
  let printed = @printer.print_program(program)
  // The anonymous member prints inline and untagged; the synthesized name
  // appears nowhere.
  assert_true(printed.contains("struct {"))
  assert_true(!printed.contains("synthetic_tag"))
}

///|
/// A tag defined inside an earlier member's expression and referenced by a
/// later member keeps its creation position: the later mention is a
/// reference, not the definition site, and inlining there would reorder the
/// reparse.
test "expression-defined tags stay at their creation position" {
  let source =
    #|struct O {
    #|  int a[sizeof(struct I { int x; })];
    #|  struct J { int y; } j;
    #|  struct I i;
    #|};
    #|int probe(struct O *o) { return o->i.x + o->j.y; }
  let first = @parser.parse(source)
  let printed = @printer.print_program(first)
  let second = @parser.parse(printed)
  assert_true(structs_roundtrip_equal(first.structs, second.structs))
  assert_eq(printed, @printer.print_program(second))
}

///|
/// Deleting a declaration is an ordinary transformation; a tail deletion
/// drops the entry exactly, without touching `items`.
test "deleting a parsed declaration prints the survivors" {
  let source =
    #|int keep = 1;
    #|int drop_me = 2;
    #|int read_keep(void) { return keep; }
  let program = @parser.parse(source)
  ignore(program.globals.pop())
  let printed = @printer.print_program(program)
  assert_true(printed.contains("int keep = 1;"))
  assert_true(!printed.contains("drop_me"))
  assert_true(printed.contains("read_keep"))
}

///|
/// A definition hidden in an early member expression is not claimable by a
/// later aggregate across intervening declarations: it prints at its
/// creation site, so everything between stays complete.
test "later references cannot pull hidden definitions forward" {
  let source =
    #|struct A { int a[sizeof(struct I { int x; })]; };
    #|struct I value = { 1 };
    #|struct B { struct I i; };
    #|int probe(struct B *b) { return b->i.x + value.x; }
  let first = @parser.parse(source)
  let printed = @printer.print_program(first)
  guard printed.find("struct I {") is Some(def_at) else {
    fail("missing I definition: \{printed}")
  }
  guard printed.find("value") is Some(value_at) else { fail("missing value") }
  // The definition precedes the initialized object.
  assert_true(def_at < value_at)
  let second = @parser.parse(printed)
  assert_true(structs_roundtrip_equal(first.structs, second.structs))
  assert_eq(printed, @printer.print_program(second))
}
