///|
/// Round-trips a real translation unit: parse it, print it, and require the
/// printed form and the resulting AST to be fixed points.
///
/// The hand-written cases in `cfront/printer` cover constructs one at a time.
/// This fixture is the opposite test -- over a megabyte of C from a real
/// project, carrying whatever the macOS SDK headers drag in, which is where a
/// printer's gaps actually surface. Both bugs found while building this printer
/// came from here rather than from the unit tests.
///
/// See `assert_roundtrips` in `cfront/printer` for why generation 1 and 2 may
/// differ in declaration grouping while everything after is identical.
async fn assert_fixture_roundtrips(path : String) -> Unit {
  let data = @fs.read_file(path)
  let source = data.text()
  let first = @parser.parse(source)
  let printed = @printer.print_program(first)
  let second = @parser.parse(printed)
  let reprinted = @printer.print_program(second)
  let third = @parser.parse(reprinted)
  assert_eq(printed, reprinted)
  assert_true(structs_roundtrip_equal(first.structs, second.structs))
  assert_eq(first.globals, second.globals)
  assert_eq(first.decls.length(), second.decls.length())
  assert_eq(second.structs, third.structs)
  assert_eq(second.globals, third.globals)
  assert_eq(second.decls, third.decls)
}

///|
async test "printer round-trips the quickjs fixture" {
  assert_fixture_roundtrips(quickjs_preprocessed_fixture_path())
}

// The tinycc fixture is deliberately not round-tripped here. It reaches a
// declaration whose return type is a function pointer, written out as
// `void (*f(int))(void)`, and the parser reads that back as `void *` -- see
// "Known limitations" in the package README. That is a parser bug this printer
// surfaced, not a printer bug, and it belongs in its own change.

///|
/// Structural equality across one print/reparse, allowing anonymity to be
/// consumed. A definition whose synthesized tag had to be spelled out --
/// typedef'd anonymous types have no member site, and a `typeof`-recovered
/// tag must resolve -- reparses with a written tag, so `is_anonymous` may go
/// from true to false across a round-trip. It can never appear: printing
/// cannot make a written tag anonymous. Everything else must match exactly.
fn structs_roundtrip_equal(
  first : Array[@parser.StructDecl],
  second : Array[@parser.StructDecl],
) -> Bool {
  if first.length() != second.length() {
    return false
  }
  for i in 0..<first.length() {
    let a = first[i]
    let b = second[i]
    if a.name != b.name ||
      a.fields != b.fields ||
      a.is_union != b.is_union ||
      a.pack != b.pack {
      return false
    }
    if a.is_anonymous != b.is_anonymous && !a.is_anonymous {
      return false
    }
  }
  true
}
