# bobzhang/kimicc/mir_codegen

`mir_codegen` is the MIR-based assembly backend: it turns a parser-AST-free
`@mir.MirModule` into target assembly. It is the second half of the
`source -> cast -> mir -> codegen` pipeline, where `@mir.lower_to_module`
produces the module and this package emits the text.

Because it consumes a `MirModule` rather than a `@parser.Program`, this backend
is independent of the parser AST. It currently covers a subset of C; the strict
entry point reports uncovered constructs instead of aborting.

## Importing

```moonbit nocheck
import {
  "bobzhang/kimicc/mir_codegen",
  "bobzhang/kimicc/mir",
  "bobzhang/kimicc/parser",
  "bobzhang/kimicc/target",
}
```

## Entry points

| Function | Result type | Behavior |
|---|---|---|
| `generate_assembly_from_mir_module` | `String` | Emits assembly, aborting if the MIR-only backend lacks coverage. |
| `generate_assembly_from_mir_module_strict` | `Result[String, String]` | Returns `Err(message)` for uncovered constructs instead of aborting. |

Most callers reach this backend through
[`bobzhang/kimicc/mir_codegen_compat`](../mir_codegen_compat/README.mbt.md),
which adds an automatic fallback to the parser-AST backend. Use this package
directly when you specifically want MIR output.

## From parsed source to assembly

Build a `MirModule` with `@mir.lower_to_module`, then hand it to the strict
backend so uncovered constructs surface as an `Err`.

```moonbit check
///|
test "lower and generate assembly" {
  let program = @parser.parse("int main(void) { return 42; }")
  let module_ = @mir.lower_to_module(program, @target.Target::default())
  match @mir_codegen.generate_assembly_from_mir_module_strict(module_) {
    Ok(assembly) => {
      // Darwin assembly references the underscored `_main` symbol.
      inspect(assembly.contains("_main"), content="true")
      inspect(assembly.length() > 0, content="true")
    }
    Err(_) => fail("expected MIR backend to cover this program")
  }
}
```

## Non-strict emission

`generate_assembly_from_mir_module` returns the assembly directly. It aborts on
constructs the MIR backend does not yet handle, so prefer it only when the input
is known to be covered (for example, output already vetted by the strict path).

```moonbit check
///|
test "non-strict emission" {
  let program = @parser.parse("int add(int x, int y) { return x + y; }")
  let module_ = @mir.lower_to_module(program, @target.Target::default())
  let assembly = @mir_codegen.generate_assembly_from_mir_module(module_)
  inspect(assembly.contains("_add"), content="true")
}
```
