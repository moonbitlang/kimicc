///|
/// Returns the aggregate names a program defines, in definition order.
fn tag_names(source : String) -> String {
  let program = @parser.parse(source)
  let names = []
  for decl in program.structs {
    names.push(decl.name)
  }
  names.join(", ")
}

///|
/// Two functions may each define their own `struct L`. They used to collide in
/// one flat table, so the second definition silently replaced the first and
/// `sizeof` in the earlier function reported the later layout.
test "block-scoped tags with the same name stay distinct" {
  let source =
    #|int first(void) { struct L { int a; }; return (int)sizeof(struct L); }
    #|int second(void) { struct L { int a; int b; int c; }; return (int)sizeof(struct L); }
  inspect(tag_names(source), content="L, L__2")
}

///|
/// A block-scoped tag shadows the file-scope one only inside its block; after
/// the block the outer definition is in view again.
test "a block-scoped tag shadows only within its block" {
  let source =
    #|struct L { int a; int b; };
    #|int shadow(void) { struct L { char c; }; return (int)sizeof(struct L); }
    #|int outer(void) { return (int)sizeof(struct L); }
  inspect(tag_names(source), content="L, L__2")
  let program = @parser.parse(source)
  // `shadow` sees the one-byte definition, `outer` the file-scope one.
  inspect(program.structs[0].fields.length(), content="2")
  inspect(program.structs[1].fields.length(), content="1")
}

///|
/// Nested blocks each get their own tag, and leaving one restores the tag the
/// enclosing block defined.
test "nested blocks each get their own tag" {
  let source =
    #|int nested(void) {
    #|  struct L { int x; int y; int z; };
    #|  int inner;
    #|  { struct L { char q; char r; }; inner = (int)sizeof(struct L); }
    #|  return (int)sizeof(struct L) * 100 + inner;
    #|}
  inspect(tag_names(source), content="L, L__2")
}

///|
/// Renaming only happens on a real collision, so a program whose tags are
/// already unique keeps the names it was written with.
test "unique tags keep their written names" {
  let source =
    #|struct Alpha { int a; };
    #|int f(void) { struct Beta { int b; }; return (int)sizeof(struct Beta); }
    #|int g(void) { struct Gamma { int c; }; return (int)sizeof(struct Gamma); }
  inspect(tag_names(source), content="Alpha, Beta, Gamma")
}

///|
/// A declaration and a member access inside the block resolve to the block's
/// own definition, not to a same-named one elsewhere.
test "declarations inside a block resolve to the block's tag" {
  let source =
    #|struct P { int a; int b; int c; };
    #|int local(void) {
    #|  struct P { int only; };
    #|  struct P v;
    #|  v.only = 7;
    #|  return v.only + (int)sizeof(struct P);
    #|}
  let program = @parser.parse(source)
  inspect(tag_names(source), content="P, P__2")
  inspect(program.structs[1].fields[0].name, content="only")
}
