///|
/// Prints a fixture and asks clang whether the result is C.
///
/// This is the check `assert_fixture_roundtrips` cannot make: the round-trip
/// reparses printed output with this project's own parser, which accepts what
/// it itself printed, so a fixed point over invalid C passes it. The suite's
/// objective is C another compiler accepts, and the only way to test that is
/// to hand the printed text to another compiler.
///
/// `allowed` names the diagnostics of known, separately-tracked parser bugs;
/// every clang error must match one of them, so a new class of invalid output
/// fails here even while the known residue stands. An empty list means the
/// printed fixture must compile clean.
async fn assert_printed_fixture_compiles(
  source : String,
  tag : String,
  allowed : Array[String],
) -> Unit {
  let printed = @printer.print_program(@parser.parse(source))
  let printed_path = temp_file_path(tag + "_printed", printed, ".c")
  write_text_file(printed_path, printed)
  let result = run_command_capture(
    "clang -fsyntax-only -ferror-limit=0 " + shell_quote(printed_path),
    tag + "_clang",
  )
  let mut errors = 0
  for line in result.output.split("\n") {
    let text = line.to_owned()
    if !text.contains("error:") {
      continue
    }
    errors += 1
    let mut matched = false
    for pattern in allowed {
      if text.contains(pattern) {
        matched = true
        break
      }
    }
    if !matched {
      abort(
        "clang rejected printed " +
        tag +
        " with an unexpected error:\n" +
        text +
        "\nfull output in " +
        printed_path,
      )
    }
  }
  if allowed.length() == 0 && errors > 0 {
    abort("clang rejected printed " + tag + ":\n" + result.output)
  }
  // A nonzero exit with no recognized diagnostics means clang did not run or
  // died some other way; that must fail the gate, not slip through it.
  if result.code != 0 && errors == 0 {
    abort(
      "clang exited " +
      result.code.to_string() +
      " for printed " +
      tag +
      " without reporting errors:\n" +
      result.output,
    )
  }
}

///|
/// The printed QuickJS fixture is C clang accepts, up to one known gap.
///
/// The residue is the interpreter's computed-goto dispatch table: a `static`
/// local holding `&&label` addresses, which the parser hoists to file scope
/// where the extension is not allowed. That is the static-local hoisting
/// construct of Step B; when locals stop being hoisted, the allowance below
/// comes out and this test requires a clean compile.
async test "printed quickjs fixture compiles under clang" {
  let source = @fs.read_file(quickjs_preprocessed_fixture_path()).text()
  assert_printed_fixture_compiles(source, "quickjs_printed_compiles", [
    "address-of-label", "indirect goto in function with no address-of-label",
  ])
}

///|
/// The printed sqlite fixture is C clang accepts, up to one known gap.
///
/// The residue is `void (*(*xDlSym)(sqlite3_vfs *, void *, const char
/// *))(void)` and the calls through it: a declarator whose function suffixes
/// land on the wrong level, the "function returning a function pointer does
/// not reparse" parser bug tracked in the plan. Fixing that parse removes the
/// allowances below.
async test "printed sqlite fixture compiles under clang" {
  let source = preprocess_c_file(
    "test/fixtures/sqlite/sqlite3.c", "sqlite3_printed_compiles",
  )
  assert_printed_fixture_compiles(source, "sqlite_printed_compiles", [
    "incompatible function pointer types", "too many arguments to function call",
  ])
}
