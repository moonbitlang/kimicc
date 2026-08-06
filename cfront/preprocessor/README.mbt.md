# bobzhang/cfront/preprocessor

`preprocessor` is the `source -> source` front of the pipeline: it expands C
preprocessing directives (`#include`, `#define`, `#if`, macros, …) into plain C
text that [`@parser`](../parser) can parse. It is what the CLI runs by default
before parsing.

## Importing

```
import {
  "bobzhang/cfront/preprocessor"
}
```

## Options

Every entry point takes a `PreprocessOptions`. Build one with
`PreprocessOptions::new(filename)` and adjust its fields — for example add
command-line `defines`, include search paths, or enable line markers. The
`filename` seeds `__FILE__` and quote-include resolution.

```moonbit check
///|
test "preprocess with a command-line define" {
  let options = @preprocessor.PreprocessOptions::new("input.c")
  // Equivalent to `-D SCALE=3`.
  options.defines["SCALE"] = "3"
  match @preprocessor.preprocess("int v = SCALE * 2;\n", options) {
    Ok(text) => inspect(text.contains("3*2"), content="true")
    Err(err) => fail(err.to_string())
  }
}
```

## Expanding macros

`preprocess` returns the expanded source as a `String`, or
`Err(PreprocessError)` on a directive error.

```moonbit check
///|
test "object and function-like macros" {
  let options = @preprocessor.PreprocessOptions::new("input.c")
  let source =
    #|#define ADD(x, y) ((x) + (y))
    #|int z = ADD(20, 22);
    #|
  match @preprocessor.preprocess(source, options) {
    Ok(text) => inspect(text.contains("((20)+(22))"), content="true")
    Err(err) => fail(err.to_string())
  }
}
```

## Preprocess and parse in one step

`parse` preprocesses and then hands the result to `@parser.parse`, returning the
AST directly. Use it when you do not need the intermediate text; call the two
packages separately when you want a strict phase boundary.

```moonbit check
///|
test "preprocess straight to an AST" {
  let options = @preprocessor.PreprocessOptions::new("input.c")
  let source =
    #|#define RET 7
    #|int answer(void) { return RET; }
    #|
  match @preprocessor.parse(source, options) {
    Ok(program) => inspect(program.decls[0].name, content="answer")
    Err(err) => fail(err.to_string())
  }
}
```

## Tracking include dependencies

`preprocess_with_dependencies` returns a `PreprocessResult` carrying both the
expanded `text` and the `dependencies` (the main file and every include
resolved during preprocessing), which the driver uses to emit Makefile-style
depfiles.

```moonbit check
///|
test "dependency tracking" {
  let options = @preprocessor.PreprocessOptions::new("input.c")
  match @preprocessor.preprocess_with_dependencies("int x = 1;\n", options) {
    Ok(result) => {
      inspect(result.text.contains("int x=1;"), content="true")
      // The main file is always among the dependencies.
      inspect(result.dependencies.length() >= 1, content="true")
    }
    Err(err) => fail(err.to_string())
  }
}
```

`dump_macros` and `dump_macros_with_dependencies` are diagnostic variants that
report the macro table instead of expanded source. For the full set of CLI
preprocessor flags (`-I`, `-D`, `-isystem`, `-M`/`-MM`, `__has_include`, …) see
the [top-level README](../README.mbt.md).
