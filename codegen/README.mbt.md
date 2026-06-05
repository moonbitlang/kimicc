# bobzhang/kimicc/codegen

`codegen` is kimicc's direct backend: it lowers a parsed [`@parser`](../parser)
`Program` straight to machine output. It is the `cast -> codegen` half of the
pipeline (the alternative path goes through [`@mir`](../mir) +
[`@mir_codegen`](../mir_codegen)).

It can emit three things from the same AST:

| Output | Function | Result |
|---|---|---|
| Assembly text | `Codegen::new().generate(program)` / `generate_assembly_for_target` | `String` |
| Mach-O object | `generate_macho_object(program)` | `Bytes` |
| JIT image | `generate_jit_image(program)` | `JitImage` |

Codegen consumes an already-parsed program; it does not preprocess or parse
text.

## Importing

```moonbit nocheck
import {
  "bobzhang/kimicc/codegen",
  "bobzhang/kimicc/parser",
  "bobzhang/kimicc/target",
}
```

## Generating assembly

`Codegen::new().generate(program)` returns Darwin ARM64 assembly. For
target-directed output, `generate_assembly_for_target` keeps the Darwin output
for `darwin-arm64` and emits GNU-assembler syntax for `linux-amd64`.

```moonbit check
///|
test "generate assembly" {
  let program = @parser.parse("int main(void) { return 42; }")

  // Default Darwin ARM64 assembly.
  let darwin = @codegen.Codegen::new().generate(program)
  inspect(darwin.contains("_main"), content="true")

  // Target-directed: Linux/amd64 emits the unprefixed symbol.
  let linux = @codegen.generate_assembly_for_target(
    program,
    @target.Target::parse("linux-amd64").unwrap(),
  )
  inspect(linux.contains("main"), content="true")
}
```

## Emitting a Mach-O object

`generate_macho_object` returns the bytes of a Mach-O relocatable object for
ARM64 macOS, suitable for writing to a `.o` file and linking with the platform
linker.

```moonbit check
///|
test "generate a mach-o object" {
  let program = @parser.parse("int answer(void) { return 7; }")
  let object = @codegen.generate_macho_object(program)
  // Mach-O 64-bit objects start with the 0xFEEDFACF magic (little-endian).
  inspect(object[0], content="b'\\xCF'")
  inspect(object.length() > 0, content="true")
}
```

## Producing a JIT image

`generate_jit_image` returns a `JitImage` — a compact, loader-facing image used
by [`@jit`](../jit), not a Mach-O file. The executable region comes first,
followed by writable data; the relocation tables and exported `symbols` let the
native loader place and patch it in memory.

```moonbit check
///|
test "generate a jit image" {
  let program = @parser.parse("int add(int x, int y) { return x + y; }")
  let image = @codegen.generate_jit_image(program)

  // The image is non-empty and its executable prefix fits within it.
  inspect(image.code.length() > 0, content="true")
  inspect(image.executable_size <= image.code.length(), content="true")

  // Exported symbols use Darwin spelling (leading underscore).
  let names = image.symbols.map(s => s.name)
  inspect(names.contains("_add"), content="true")
}
```

`JitImage` fields are `code`, `executable_size`, `base_relocations`,
`external_relocations`, and `symbols` (each a `JitSymbol` with a `name` and an
`offset`). See the [top-level README](../README.mbt.md) for the field-by-field
contract and the [`@jit`](../jit) package for running the image in memory.
