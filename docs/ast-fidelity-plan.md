# AST fidelity plan

## Why this exists

`cfront` is meant to be a reusable C front end. Reading C works well: the parser
handles a large subset, and the compiler is built on it. Writing C back out does
not, and the reason is not the printer. It is that the AST is a *lowered*
representation shaped for kimicc's own code generator, not a faithful record of
the source.

Adding `cfront/printer` made this measurable, because a printer is the only
consumer that has to reproduce everything the parser saw. Round-tripping
preprocessed QuickJS and sqlite3 turned a set of vague "the AST is a bit lossy"
concerns into a concrete list.

This document records what the AST must carry, in the order the work should
happen, with the blast radius of each step measured rather than guessed.

## What the AST discards today

Grouped by what kind of problem it is, because they need different fixes.

### 1. Information the parser has and throws away

These are the cheapest to fix and cause the most visible damage.

| Missing | Consequence | Where |
|---|---|---|
| Integer and float literal types | `Number(Int64)` carries no type, so `sizeof(1L)` is 8 in the source and 4 after a round trip, `sizeof(0xffffffffu)` goes 4 → 8, and `a < 1u` flips result. The parser computes the type (`@ctype.integer_constant_token_type`) and drops it. | `cfront/parser/ast.mbt` |
| `const`, `volatile`, `restrict` | `@ctype.Type` has no qualifier constructors at all, so they vanish. Dropping `volatile` is an optimizer-visible change, not a cosmetic one. | `cfront/ctype/type.mbt` |
| Prototype versus unspecified parameters | `int f()` and `int f(void)` are indistinguishable in the AST. Printing the wrong one turns every call with arguments into an error. | `FuncDecl`, `@ctype.Type::FuncPtr` |
| Enum constant names | Enumerators are folded to their values, so they print as integers. | `cfront/parser/parse_decl.mbt` |
| Source locations | No diagnostics can point at source, and no printer can preserve formatting. | everywhere |

### 2. Lowering baked into the AST

The parser does not just parse: it desugars. Each of these makes the AST unable
to describe what was written.

- **Aggregate initializers.** `struct P p = { 1, 2 };` becomes
  `VarDecl(ty, name, Some(Number(0)))` plus element assignments. The `= 0` is a
  marker, not an expression. Printing it literally emits `struct P p = 0;`,
  which no compiler accepts; printing `= { 0 }` instead re-lowers differently on
  reparse, so the round trip stops converging. There is no correct printing of
  this node, which is the clearest sign the problem is upstream.
- **Case labels.** `case 3:` becomes `Label("__kimicc_case_3_7", ...)` and the
  case table is recovered by parsing that name back. The counter embedded in the
  name means label identity depends on how many cases were parsed earlier.
- **Anonymous aggregate members.** An anonymous `union { ... };` inside a struct
  becomes a field with an empty name whose type is a synthetic
  `__anon_union_0` tag. Nothing records that the member was anonymous, so
  printing the tag reference produces a struct 16 bytes smaller.
- **Multi-declarator declarations.** `int a, b;` becomes
  `StmtList([VarDecl, VarDecl])`, a grouping node that exists only to hold them
  together and has no other meaning.
- **Compound literals** carry a parser-assigned counter as a third field, which
  is identity, not syntax.

### 3. Structure the AST cannot express

- **Top-level order.** `Program` holds three separate arrays -- `structs`,
  `globals`, `decls` -- so the interleaving of declarations is gone. A global
  initialized with a function's address must be printed after that function, and
  a struct must be printed after the structs it embeds, but the AST no longer
  knows which came first. Anonymous aggregates are additionally *prepended*,
  which puts them ahead of the types they depend on.
- **Tag scope.** Block-scoped `struct` tags are hoisted into one flat table, so
  two functions that each declare a local `struct L` collide. kimicc
  miscompiles this today, independently of printing.

### 4. Parser bugs, not AST problems

Listed here only so they are not confused with the above.

- A function whose return type is a function pointer does not reparse:
  `void (*f(int))(void)` is read back as `void *f(int)`. Affects the tinycc and
  sqlite3 fixtures.
- `int *(*p)[2]` is misparsed as `Pointer(Pointer(Array))`.
- `int * _Atomic pa = &target;` is dropped from the program entirely.
- `1e400` lexes to `0.0` rather than infinity.

## Plan

Ordered by value per unit of risk. Each step is independently shippable.

### Step 1 — Aggregate definitions in creation order *(this change)*

The parser kept anonymous aggregates in a separate array and prepended it to the
named ones, so every anonymous definition landed ahead of everything, including
the named aggregates it embeds. Both now append to one list as they are built.
An anonymous aggregate is created while parsing the declaration that introduces
it, so appending puts each definition ahead of its first use by construction --
no topological sort needed.

Blast radius: five push sites and one reader, all inside the parser. The
`Program` shape is unchanged, so MIR and both code generators are untouched.

This removes the `field has incomplete type` class from printed output (21
occurrences on preprocessed sqlite3).

What it does **not** fix is ordering *between* kinds. `Program` still holds
three separate arrays, so a global initialized with a function's address is
still printed before that function -- the largest remaining class of
non-compiling output (576 occurrences on sqlite3). Fixing that means replacing
the three arrays with one ordered list of top-level items, which is a larger
change than it first appears: globals are appended from eight sites across
`parse_decl`, `parse_program`, and `parse_stmt`, the last of which hoists static
locals out of function bodies and so has no obvious position in a source-ordered
list. That question -- where a hoisted static local belongs in a faithful AST --
is worth settling before writing the code, and is really an instance of the
lowering problem in Step 4.

### Step 2 — Record what the parser already computed

Small additive fields, each fixing a specific defect:

- `FuncDecl.has_prototype : Bool`, and the same on `FuncPtr`, to tell `()` from
  `(void)`.
- Mark anonymous aggregate members explicitly rather than inferring from an
  empty field name and a `__anon_` tag prefix.

Blast radius: small, and the compiler flags every construction site.

### Step 3 — Type the literals

Give `Number` and `FloatLiteral` the type the lexer already determined. This is
the largest mechanical change on the list: `Number(` alone has roughly 240 sites
across the parser, MIR, and both code generators, so it should be its own change
with nothing else in it.

Doing it earlier would be tempting -- it fixes real semantic drift -- but it
touches every backend, and the ordering work above is free by comparison.

### Step 4 — Stop lowering in the parser

Move aggregate-initializer expansion, case-label synthesis, and multi-declarator
grouping out of the AST and into MIR lowering, where they belong. The AST keeps
the surface form; the compiler desugars on its way down.

This is the step that makes the printer trustworthy, and it is the most
invasive, because the code generators consume the lowered shapes directly. It
should follow Step 3 so the literal types are already in place.

### Step 5 — Qualifiers and source locations

`const`/`volatile`/`restrict` as `@ctype.Type` wrappers, following the existing
`Atomic`/`Aligned` pattern -- `Type::core_type` already strips wrappers, so most
semantic queries are unaffected and the compiler finds the rest.

Source locations are the largest change and the one with no partial credit: a
location on every node, threaded through every constructor. It is last because
nothing else depends on it, and because it is what a *formatter* needs rather
than what a *printer* needs.

## What this does not change

Printing stays canonical. Even with every step above, the AST will not record
comments or original spacing, so `cfront/printer` will never reproduce
hand-written source byte for byte. Format preservation is a different
deliverable and needs Step 5 plus comment attachment.
