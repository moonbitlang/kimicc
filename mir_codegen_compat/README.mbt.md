# bobzhang/kimicc/mir_codegen_compat

`mir_codegen_compat` is the compatibility facade that ties kimicc's two code
generation pipelines together behind one set of functions:

- the established `source -> cast -> codegen` path
  (`@codegen.generate_assembly_for_target`), and
- the newer `source -> cast -> mir -> codegen` path
  (`@mir.lower` + `@mir_codegen`).

Use it when you have a parsed `@parser.Program` and want assembly without
committing to a specific backend. It owns no public types of its own; it only
re-exports and combines the two backends.

## Importing

```moonbit nocheck
import {
  "bobzhang/kimicc/mir_codegen_compat",
  "bobzhang/kimicc/parser",
  "bobzhang/kimicc/target",
}
```

## Choosing a path

| Function | Path | Result type | When to use |
|---|---|---|---|
| `generate_assembly_for_target_with_parser_fallback` | MIR, falling back to parser-AST | `String` | Default. Best MIR output where covered, never fails on the supported subset. |
| `generate_assembly_for_target` | parser-AST only | `String` | Force the legacy backend. |
| `generate_assembly_from_mir` | MIR Program | `String` | You already hold a `@mir.Program`; abort on uncovered constructs. |
| `generate_assembly_for_target_strict` | MIR, strict | `Result[String, String]` | Detect uncovered constructs as an `Err` instead of falling back. |
| `generate_assembly_from_mir_strict` | MIR Program, strict | `Result[String, String]` | Same, for a pre-lowered `@mir.Program`. |

## Recommended entry point

`generate_assembly_for_target_with_parser_fallback` prefers the MIR backend and
falls back to the parser-AST backend on any construct MIR does not yet cover, so
it always produces assembly for the supported C subset.

```moonbit check
///|
test "fallback path generates assembly" {
  let program = @parser.parse("int main(void) { return 42; }")
  let assembly = @mir_codegen_compat.generate_assembly_for_target_with_parser_fallback(
    program,
    @target.Target::default(),
  )
  // Darwin assembly references the underscored `_main` symbol.
  inspect(assembly.contains("_main"), content="true")
  inspect(assembly.length() > 0, content="true")
}
```

## Forcing the legacy parser-AST backend

```moonbit check
///|
test "parser-ast path" {
  let program = @parser.parse("int answer(void) { return 7; }")
  let assembly = @mir_codegen_compat.generate_assembly_for_target(
    program,
    @target.Target::default(),
  )
  inspect(assembly.contains("_answer"), content="true")
}
```

## Strict mode

The strict variants return `Result[String, String]`. `Ok` carries the MIR
backend's assembly; `Err` carries a message describing the construct that the
MIR-only backend does not yet handle, letting the caller decide whether to fall
back, report, or fail.

```moonbit check
///|
test "strict mode returns a result" {
  let program = @parser.parse("int main(void) { return 1 + 2; }")
  match
    @mir_codegen_compat.generate_assembly_for_target_strict(
      program,
      @target.Target::default(),
    ) {
    Ok(assembly) => inspect(assembly.contains("_main"), content="true")
    Err(_) =>
      // Uncovered construct: a real caller would fall back to the parser-AST path.
      inspect(true, content="true")
  }
}
```
