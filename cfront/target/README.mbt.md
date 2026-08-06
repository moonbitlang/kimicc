# bobzhang/cfront/target

`target` names the compiler output targets supported by kimicc and exposes the
small pieces of target metadata that the driver and code generators need:
the canonical name, the LLVM-style triple, the object-file format, and the
assembler symbol prefix.

It is a leaf package with no dependencies. The two supported targets are:

| Target | Name | Triple | Object format | Symbol prefix |
|---|---|---|---|---|
| `DarwinArm64` | `darwin-arm64` | `arm64-apple-darwin` | `Mach-O` | `_` |
| `LinuxAmd64` | `linux-amd64` | `x86_64-linux-gnu` | `ELF64` | (none) |

`DarwinArm64` is the primary, fully supported target. `LinuxAmd64` drives the
experimental System V x86-64 backend.

## Importing

```
import {
  "bobzhang/cfront/target"
}
```

## Selecting a target

`Target::default()` is `DarwinArm64`, the native host. `Target::parse` accepts
kimicc's short names, the Docker-style `linux/amd64` alias, and a number of
common platform triples, returning `None` for anything unrecognized.

```moonbit check
///|
test "parse and default" {
  // The default target is native ARM64 macOS.
  inspect(@target.Target::default().name(), content="darwin-arm64")

  // Short names, the docker-style alias, and triples all parse to the same target.
  let a = @target.Target::parse("linux-amd64").unwrap()
  let b = @target.Target::parse("linux/amd64").unwrap()
  let c = @target.Target::parse("x86_64-unknown-linux-gnu").unwrap()
  inspect(a == b && b == c, content="true")

  // Unknown spellings return None.
  inspect(@target.Target::parse("riscv64-unknown-elf") is None, content="true")
}
```

## Target metadata

Once you have a `Target`, the accessor methods report how code generation and
linking should treat it.

```moonbit check
///|
test "metadata" {
  let darwin = @target.Target::default()
  let linux = @target.Target::parse("linux-amd64").unwrap()

  // Canonical triple forwarded to Clang.
  inspect(darwin.triple(), content="arm64-apple-darwin")
  inspect(linux.triple(), content="x86_64-linux-gnu")

  // Relocatable object format.
  inspect(darwin.object_format(), content="Mach-O")
  inspect(linux.object_format(), content="ELF64")

  // Assembler symbol prefix: Darwin underscores C symbols, ELF does not.
  inspect("\{darwin.symbol_prefix()}main", content="_main")
  inspect("\{linux.symbol_prefix()}main", content="main")
}
```

`Target` derives `Eq`, so values compare structurally; use the `name()` or
`triple()` accessors when you need a human-readable spelling (the enum itself
does not implement `Show`).
