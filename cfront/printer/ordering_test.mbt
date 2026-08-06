///|
/// A struct defined in a type-specifier position must still be printed after
/// the aggregates it embeds.
///
/// The parser used to hoist every such definition ahead of the named ones,
/// which put `Outer` before the `Inner` it contains and made the printed output
/// fail to compile with `field has incomplete type`.
test "aggregates print in definition-before-use order" {
  let source =
    #|struct Inner { int a; int b; };
    #|typedef struct Outer { struct Inner in; int c; } Outer_t;
    #|int use(Outer_t *o) { return o->in.a + o->c; }
  let program = @parser.parse(source)
  let names = []
  for decl in program.structs {
    names.push(decl.name)
  }
  inspect(names.join(", "), content="Inner, Outer")
}

///|
/// An anonymous aggregate is created while parsing the declaration that
/// introduces it, so it must land immediately before that declaration rather
/// than at the front of the program.
test "anonymous aggregates keep their position" {
  let source =
    #|struct First { int x; };
    #|struct Second { struct { int a; int b; } nested; };
    #|int use(struct First *f, struct Second *s) { return f->x + s->nested.a; }
  let program = @parser.parse(source)
  let names = []
  for decl in program.structs {
    names.push(decl.name)
  }
  // `First` comes first because it was defined first; the anonymous aggregate
  // sits between it and `Second`, which embeds it.
  inspect(names.join(", "), content="First, __anon_struct_0, Second")
}
