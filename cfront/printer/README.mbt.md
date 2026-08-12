# bobzhang/cfront/printer

`printer` renders a [`@parser`](../parser) AST back to C source. It is the
output half of the front end: build or transform a `Program` in MoonBit, print
it, and hand the text to any C compiler.

"Any C compiler" is tested literally: CI prints the QuickJS and sqlite fixtures
and hands the results to clang. Three things make the output land as valid C
rather than merely reparseable text. Top-level entries print in source order
(`Program::items`), because C requires declaration before use at file scope.
Every tag is forward-declared at the top -- including tags the program never
defines -- so no tag's first mention sits inside a prototype's parameter list,
where it would have prototype scope and be a different type. And an anonymous
member prints as the untagged inline definition C11 requires for its members to
reach through, its synthetic `__anon_` tag appearing nowhere in the output.

## Round-trip guarantee

Printing is **canonical**, not source-preserving. The property it does
guarantee, and the one meta-programming depends on, is that printing is a fixed
point:

- printing, reparsing, and printing again yields byte-identical text, and
- from the first print onward the AST is stable.

Concretely, `parse(print(p))` is structurally equal to `p` for anything you
build or transform, so a generate/print/parse cycle does not drift.

The first print no longer canonicalizes anything. `int a, b;` used to parse to a
`StmtList` grouping that the printer erased; the parser now records one
`VarDecl` per name and the printer writes one declaration per name, so the two
agree.

The `for` initializer is the one place C insists on the grouping -- `for (int i
= 0; int n = len; ...)` is not C -- so several names declared there are written
back as one declaration, `for (int i = 0, n = len; ...)`, using
`split_declaration` to share the specifier. Several expressions there join with
the comma operator instead.

What the printer does *not* preserve is the original text: comments, spacing,
macro spellings, and redundant parentheses are all gone, because the AST does
not record them. A formatter needs source locations and comment attachment,
which the AST does not have.

## Using it

```moonbit nocheck
///|
let program = @parser.parse(source)

///|
let text = @printer.print_program(program)
```

Smaller pieces are printable on their own:

| Function | Renders |
|---|---|
| `print_program` | a whole translation unit |
| `print_stmt` | one statement, starting at the left margin |
| `print_expr` | one expression, parenthesized only where precedence requires |
| `print_type` | a type with no declared name, as used by casts and `sizeof` |
| `print_declaration` | a type as a declaration of a given name |

`print_declaration` exists because C declarator syntax reads outward from the
name, so a type cannot be printed as a prefix followed by an identifier:

```moonbit check
///|
test "declarators read outward from the name" {
  inspect(
    @printer.print_declaration(Pointer(Array(SInt, 4)), "x"),
    content="int (*x)[4]",
  )
  inspect(
    @printer.print_declaration(Array(Pointer(SInt), 4), "x"),
    content="int *x[4]",
  )
}
```

## What it takes care of

- **Precedence.** Parentheses appear exactly where they are needed, so
  `(1 + 2) * 3` keeps its grouping and `a - (b - c)` keeps its.
- **Layout-affecting attributes.** An aggregate's `pack` cap is printed, as
  `__attribute__((packed))` or a `#pragma pack` pair. Dropping it would emit C
  that compiles to a different ABI.
- **Integer literals that have no negative spelling.** C has no negative
  literals, and the parser does not fold `-N` back into one, so a negative value
  in the AST -- which is the bit pattern of a literal that overflowed the signed
  range, such as `0x8000000000000000` -- is printed as hexadecimal rather than
  as a negation.
- **Designator chains.** `.u.float64 = x` is a nested designator in the AST and
  has to be printed as one chain with a single `=`.
- **Clause values.** `case 3:` is a `Case` node holding the value its constant
  expression folded to, so it prints as a decimal literal rather than as the
  expression that was written.

## Known limitations

- **A function whose return type is a function pointer does not round-trip.**
  The printer emits the correct C -- `void (*maker(int n))(void)`, which clang
  accepts -- but the parser reads it back as `void *maker(int n)`, silently
  losing the return type. This is a parser bug that the printer surfaced; it is
  why the tinycc e2e fixture is not round-tripped.
- **No source locations, so no format preservation.** See above.
- **Enum constants are folded to their values** by the parser, so they print as
  integers rather than by name.

## Testing

```bash
moon test --target native cfront/printer
```

The unit tests cover constructs one at a time. The broad test lives in
`test/e2e/printer_roundtrip_test.mbt`, which round-trips a megabyte of
preprocessed QuickJS; both bugs found while building this printer came from
there rather than from the unit tests.
