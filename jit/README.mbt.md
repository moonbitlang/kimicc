# bobzhang/kimicc/jit

`jit` compiles C source and runs selected functions in memory. It is a
native-only convenience layer over the rest of the pipeline: it parses,
generates a [`@codegen`](../codegen) JIT image, maps it executable, resolves
external symbols with `dlsym`, and calls into the compiled code through a small
C FFI stub.

This package only builds for the `native` target.

## Importing

```moonbit nocheck
import {
  "bobzhang/kimicc/jit"
}
```

## Compile once, call by symbol

`compile` expects already-preprocessed source and returns `Some(module)` on
success, or `None` when codegen succeeds but native image allocation, memory
protection, relocation, or external-symbol resolution fails. (Parsing and
codegen errors abort rather than returning `None`.) Call functions on the
returned `Module` so the source is compiled only once.

```moonbit check
///|
test "compile and call" {
  let source = "int add(int x, int y) { return x + y; }"
  let module_ = @jit.compile(source).unwrap()

  // Call add(20, 22) through the native ABI.
  inspect(module_.call_i32_2("add", 20, 22) == Some(42), content="true")

  // symbol_offset accepts either the C or Darwin spelling.
  inspect(module_.symbol_offset("add") is Some(_), content="true")
  inspect(module_.symbol_offset("_add") is Some(_), content="true")

  // A missing symbol yields None.
  inspect(module_.call_i32_2("missing", 1, 2) is None, content="true")
}
```

## One-shot helpers

The `call_i32_N` free functions compile and call in a single step — convenient
for tests. They return `None` if native loading fails or the requested symbol is
absent (invalid source still aborts during parsing).

```moonbit check
///|
test "one-shot helpers" {
  inspect(
    @jit.call_i32_0("int answer(void) { return 42; }", "answer") == Some(42),
    content="true",
  )
  inspect(
    @jit.call_i32_1("int negate(int x) { return -x; }", "negate", 42) ==
    Some(-42),
    content="true",
  )
  inspect(
    @jit.call_i32_2("int add(int x, int y) { return x + y; }", "add", 20, 22) ==
    Some(42),
    content="true",
  )
  inspect(
    @jit.call_i32_3(
      "int mix(int a, int b, int c) { return a + b * c; }", "mix", 5, 8, 2,
    ) ==
    Some(21),
    content="true",
  )
}
```

## Compiling source with directives

`compile` assumes preprocessed input. When the source may contain preprocessor
directives, use `compile_c`, which runs the [`@preprocessor`](../preprocessor)
first and surfaces preprocessing errors as `Err`.

```moonbit check
///|
test "compile source with a macro" {
  let source =
    #|#define RET 42
    #|int answer(void) { return RET; }
    #|
  let options = @preprocessor.PreprocessOptions::new("input.c")
  match @jit.compile_c(source, options) {
    Ok(Some(module_)) =>
      inspect(module_.call_i32_0("answer") == Some(42), content="true")
    Ok(None) => fail("compile or load failed")
    Err(err) => fail(err.to_string())
  }
}
```

## Calling convention caveats

The `call_i32_N` surface assumes the target C function returns a 32-bit `int`
and takes exactly `N` 32-bit `int` arguments. Calling a symbol with a different
signature is undefined behavior at the native ABI level — the wrapper cannot
validate the C type signature. External functions and data are resolved with
`dlsym(RTLD_DEFAULT, name)`, retrying without a leading underscore for
Darwin-style symbols.
