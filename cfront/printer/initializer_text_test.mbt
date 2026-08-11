///|
/// Returns the printed form of `decl`, the sole statement of a function body.
///
/// Any aggregate `decl` defines is printed ahead of the function, so the
/// declaration is found by position within the body rather than by taking the
/// program's first lines.
fn printed_local(decl : String) -> String raise {
  let program = @parser.parse("int f(void) { " + decl + " return 0; }")
  let printed = @printer.print_program(program)
  let mut seen_signature = false
  for raw in printed.split("\n") {
    let line = raw.trim().to_owned()
    if seen_signature && line != "" {
      return line
    }
    if line.has_prefix("int f(void)") {
      seen_signature = true
    }
  }
  fail("printed program has no function body")
}

///|
/// A local aggregate initializer prints as the declaration it was written as.
///
/// This is what the shape change bought. The parser used to record `int a[3] =
/// {1, 2, 3}` as `int a[3] = 0` followed by three assignment statements, so a
/// printer working from that AST emitted four statements for one declaration
/// and no amount of care in the printer could recover the original.
test "local aggregate initializers print as declarations" {
  inspect(
    printed_local("int a[5] = {1, 2, 3};"),
    content="int a[5] = { 1, 2, 3 };",
  )
  inspect(
    printed_local("int a[] = {1, 2, 3};"),
    content="int a[3] = { 1, 2, 3 };",
  )
  inspect(printed_local("int a[3] = {0};"), content="int a[3] = { 0 };")
}

///|
/// Designators survive, including the GNU range form.
test "designated local initializers print their designators" {
  inspect(
    printed_local("int a[6] = {[2] = 7, [4] = 9};"),
    content="int a[6] = { [2] = 7, [4] = 9 };",
  )
  inspect(
    printed_local("int a[6] = {[1 ... 3] = 9};"),
    content="int a[6] = { [1 ... 3] = 9 };",
  )
  inspect(
    printed_local("struct P { int x; int y; } p = {.y = 5};"),
    content="struct P p = { .y = 5 };",
  )
}

///|
/// A string initializing a `char` array stays the string, and the size the
/// braces or the literal imply is the size that prints.
test "char array string initializers print as strings" {
  inspect(printed_local("char s[] = \"abc\";"), content="char s[4] = \"abc\";")
  inspect(printed_local("char s[8] = \"hi\";"), content="char s[8] = \"hi\";")
  inspect(
    printed_local("char s[] = \"a\\tb\";"),
    content="char s[4] = \"a\\tb\";",
  )
}

///|
/// Braces wrapping a scalar are the one initializer form still folded away on
/// the way in, matching what a global records for the same declaration. The
/// value survives; the braces do not.
test "braces around a scalar initializer are not recorded" {
  inspect(printed_local("int x = {19};"), content="int x = 19;")
  inspect(printed_local("int x = {{23}};"), content="int x = 23;")
  // Inside an aggregate the braces are kept, since there the destination is
  // decided by position rather than by the declaration.
  inspect(
    printed_local("int a[2] = {{5}, {37}};"),
    content="int a[2] = { { 5 }, { 37 } };",
  )
}
