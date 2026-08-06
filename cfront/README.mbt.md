# bobzhang/cfront

`cfront` is a reusable C front end written in MoonBit: it preprocesses C source,
parses it into a public AST, models C types, and prints the AST back to C. It carries no code generator and
no dependency on any backend, so it can be consumed on its own by tools that only
need to read C.

It is developed alongside [`bobzhang/kimicc`](../), the C compiler it was
extracted from, which is its main consumer.

## Package Layout

| Package | Purpose |
|---|---|
| `bobzhang/cfront/target` | Names supported output targets such as `darwin-arm64` and `linux-amd64`. The type model is target-sensitive, so this is a front end concern. |
| `bobzhang/cfront/ctype` | The C type model plus ABI-flavored helpers, integer and floating constant folding, and the `__builtin_*` lowering tables. |
| `bobzhang/cfront/preprocessor` | Expands `#include`, `#define`, conditionals and macros into ordinary C source. |
| `bobzhang/cfront/parser` | Tokenizes and parses preprocessed C into the public AST. |
| `bobzhang/cfront/printer` | Renders the AST back to canonical C source. |

The dependency order is `target` and `ctype` at the bottom, then `parser`, then
`preprocessor` and `printer`.

## Using It

Add the module and import the packages you need in `moon.pkg`:

```
import {
  "bobzhang/cfront/preprocessor",
  "bobzhang/cfront/parser",
  "bobzhang/cfront/target",
}
```

Preprocess and then parse, keeping the two phases separate:

```moonbit nocheck
let source = @preprocessor.preprocess(text, options)
let program = @parser.parse(source)
```

`@preprocessor.parse(source, options)` does both in one step when a strict phase
boundary is not needed.

## Current Limitations

These matter if you are building tooling rather than a compiler:

- **The parser aborts on invalid input** instead of returning a recoverable
  error. Callers that need fault isolation have to parse in a separate process.
- **The AST carries no source locations**, so diagnostics cannot point at source
  and no printer can preserve the original formatting.
- **`preprocessor` uses a native C stub** for file existence and reading, so
  include resolution is native-only.
- **`ctype` cannot size aggregates on its own.** `Type::size` aborts for
  `Struct`/`Union` because layout needs target-specific aggregate facts that the
  consumer supplies.

## Testing

```bash
moon test --target native
```

The module builds and tests standalone; it does not need `kimicc` present.
