# bobzhang/kimicc/mir

`mir` is kimicc's mid-level intermediate representation. It sits between the
parser AST and the backend on the `source -> cast -> mir -> codegen` pipeline:
[`@parser`](../parser) produces an AST, `@mir.lower` turns that AST into
target-sensitive MIR, and [`@mir_codegen`](../mir_codegen) emits assembly from
it. The package also ships a small integer interpreter used as a compile-test
oracle.

Compared to the parser AST, MIR is:

- **target-aware** — type sizes, alignments, and aggregate layouts are computed
  for a specific `@target.Target`;
- **desugared** — operators carry explicit types, addresses and loads/stores are
  explicit, and global initializers are lowered to a small `MirGlobalInit` form;
- **backend-facing** — the parser-free `MirModule` is the boundary the code
  generator consumes.

## Importing

```
import {
  "bobzhang/kimicc/mir",
  "bobzhang/kimicc/parser",
  "bobzhang/kimicc/target",
  "bobzhang/kimicc/ctype",
}
```

## `Program` vs `MirModule`

`lower` returns a `Program`, which keeps the original parser AST (in a private
field) so it can still answer semantic queries during lowering and fallback.
`to_module` projects it onto a `MirModule` that contains only MIR-owned
declarations, computed layouts, and lowered bodies — the long-term codegen
boundary. `lower_to_module` does both in one step.

```moonbit check
///|
test "lower to a program and a module" {
  let ast = @parser.parse("int add(int x, int y) { return x + y; }")
  let target = @target.Target::default()

  // Lower to a Program (retains the source AST for queries).
  let program = @mir.lower(ast, target)
  inspect(program.bodies.contains("add"), content="true")

  // Project onto the parser-free MirModule the backend consumes.
  let module_ = program.to_module()
  inspect(module_.bodies.contains("add"), content="true")

  // Or do both at once.
  let module2 = @mir.lower_to_module(ast, target)
  inspect(module2.decls.length(), content="1")
}
```

## Target-aware type and layout queries

Both `Program` and `MirModule` expose `type_size`, `type_align`, `field_layout`,
and `offset_of_path`. They resolve `struct`/`union` types through aggregate
layouts, which a `Program` computes lazily from its declarations on first use
(`to_module` forces all of them), so they work where a bare `@ctype.Type`
cannot.

```moonbit check
///|
test "layout queries" {
  let program = @mir.lower(
    @parser.parse(
      "struct P { int x; int arr[4]; }; int main(void) { return 0; }",
    ),
    @target.Target::default(),
  )
  let p = @ctype.Type::Struct("P")

  // sizeof / alignof an aggregate.
  inspect(program.type_size(p), content="20") // 4 (x) + 16 (arr)
  inspect(program.type_align(p), content="4")

  // Field offset.
  inspect(program.field_layout(p, "arr").unwrap().offset, content="4")

  // offsetof(struct P, arr[2]).
  let path = [@ctype.OffsetField("arr"), OffsetIndex(2L)]
  inspect(program.offset_of_path(p, path).unwrap(), content="12")
}
```

## The integer interpreter

`interpret_i64` lowers and runs an `int`/`long`-returning function. It is a
deliberately conservative compile-test oracle: it returns `Err(message)` for
behavior it does not model yet (memory, aggregates, indirect calls, varargs,
floating point, computed goto). `Program::interpret_i64` runs against an
already-lowered program.

```moonbit check
///|
test "interpret scalar functions" {
  let target = @target.Target::default()

  // One-shot: lower and interpret.
  match
    @mir.interpret_i64(
      @parser.parse("int main(void) { return 6 * 7; }"),
      target,
      "main",
      [],
    ) {
    Ok(value) => inspect(value, content="42")
    Err(msg) => fail(msg)
  }

  // Pass arguments to the entry function.
  let program = @mir.lower(
    @parser.parse("int add(int x, int y) { return x + y; }"),
    target,
  )
  match program.interpret_i64("add", [20L, 22L]) {
    Ok(value) => inspect(value, content="42")
    Err(msg) => fail(msg)
  }
}
```

## The MIR data model

The lowered program exposes its IR so tests, tooling, and the backend can
inspect it. The main shapes are:

| Type | Role |
|---|---|
| `Program` / `MirModule` | Whole translation unit: declarations, layouts, and lowered bodies. |
| `MirFuncDecl`, `FuncSig` | Function declarations and signatures (linkage, variadic, constructor/destructor, etc.). |
| `MirFuncBody`, `MirLocal`, `MirParam` | A lowered function body and its locals/parameters. |
| `MirStmt` | Lowered statement tree (`MirReturn`, `MirIf`, `MirWhile`, `MirSwitch`, `MirGoto`, …). |
| `MirValue` | Lowered expression/operation tree with explicit types; `MirValue::ty` reports the value's `@ctype.Type`. |
| `MirGlobalDecl`, `MirGlobalInit` | Global declarations and their lowered initializer form. |
| `MirAggregateDecl`, `AggregateLayout`, `FieldLayout` | Aggregate declarations and their computed layouts. |

`merge_global_decls` coalesces repeated declarations of the same global (a
tentative definition, an `extern` re-declaration, an initializing definition)
into a single entry, which is what lowering uses to build the global table.

```moonbit check
///|
test "inspect a lowered value's type" {
  let program = @mir.lower(
    @parser.parse("long wide(void) { return 1; }"),
    @target.Target::default(),
  )
  // The lowered body for `wide` is available for inspection.
  inspect(program.bodies.get("wide") is Some(_), content="true")
}
```
