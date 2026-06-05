# bobzhang/kimicc/parser

`parser` turns an already-preprocessed C translation unit into kimicc's public
AST. It is the `source -> cast` stage of both pipelines: the AST it produces is
consumed directly by [`@codegen`](../codegen) and lowered to MIR by
[`@mir`](../mir). Types in the AST come from [`@ctype`](../ctype).

The parser expects preprocessed source — run [`@preprocessor`](../preprocessor)
(or the CLI's default mode) first if the input still contains `#include`,
`#define`, or conditionals.

## Importing

```moonbit nocheck
import {
  "bobzhang/kimicc/parser",
  "bobzhang/kimicc/ctype",
  "bobzhang/kimicc/target",
}
```

## Parsing a translation unit

`parse` consumes a complete translation unit and returns a `Program` with three
arrays: `structs`, `globals`, and `decls` (functions). It does not return a
recoverable error — invalid or unsupported C aborts, so callers needing fault
isolation should parse in a separate process.

```moonbit check
///|
test "parse a translation unit" {
  let program = @parser.parse(
    "int answer(void) { return 42; }\n" + "long counter;\n",
  )
  // One function declaration and one global.
  inspect(program.decls.length(), content="1")
  inspect(program.globals.length(), content="1")

  let answer = program.decls[0]
  inspect(answer.name, content="answer")
  inspect(answer.ret == @ctype.Type::SInt, content="true")
  inspect(answer.variadic, content="false")
}
```

`parse_for_target` is the same, but parses for a specific `@target.Target` so
target-sensitive constructs are resolved for that ABI. Plain `parse` uses the
default target.

```moonbit check
///|
test "parse for a specific target" {
  let program = @parser.parse_for_target(
    "int main(void) { return 0; }",
    @target.Target::parse("linux-amd64").unwrap(),
  )
  inspect(program.decls[0].name, content="main")
}
```

## Validating semantics

`validate_semantics` runs the parser's semantic checks over a parsed `Program`,
returning `Ok(())` when it is well-formed or `Err(message)` describing the first
problem found.

```moonbit check
///|
test "validate semantics" {
  let program = @parser.parse("int main(void) { return 0; }")
  match @parser.validate_semantics(program) {
    Ok(_) => inspect("ok", content="ok")
    Err(message) => fail(message)
  }
}
```

## The AST

The parser exposes its AST so tests, tooling, and alternate backends can inspect
or transform it. The main shapes are:

| Type | Meaning |
|---|---|
| `Program` | Translation unit: `structs`, `globals`, `decls`. |
| `FuncDecl` | A function declaration or definition; `body` is `None` for a prototype. |
| `GlobalDecl` | A global variable; `init` is `None` for a declaration without an initializer. |
| `StructDecl` | A struct or union declaration (`is_union`, `is_packed`). |
| `Param` | A function parameter or aggregate field; `bit_width` is set for bit-fields. |
| `Expr` | Expression tree; operators are stored as source-level strings. |
| `Stmt` | Statement tree. |

Expressions and statements are plain enums, so you can pattern-match them
directly:

```moonbit check
///|
test "inspect the AST" {
  let program = @parser.parse("int twice(int x) { return x + x; }")
  let func = program.decls[0]
  inspect(func.params.length(), content="1")
  inspect(func.params[0].name, content="x")
  // A defined function carries a body.
  inspect(func.body is Some(_), content="true")
}
```

For the full compiler driver, CLI flags, and the end-to-end pipeline, see the
[top-level README](../README.mbt.md).
