# Plan: a C syntax suite for meta-programming

## The objective

`cfront` should be a C syntax suite: read C into an AST, build or transform that
AST from MoonBit, and write it back out as C another compiler accepts. `kimicc`
is then one consumer of that suite rather than its reason for existing.

That objective, and not "make the compiler more correct", is what orders the
work below. The two overlap but are not the same, and the earlier version of
this plan was written from the compiler's side: it catalogued what the AST
*discards*, which is the right lens for round-tripping and the wrong one for
deciding what to build next. Two requirements a suite has that a compiler does
not were missing from it entirely -- errors and construction -- and they are
now first-class.

## What a suite needs

Four capabilities, in the order they gate each other.

1. **Read C without dying.** A library that aborts the process cannot be used by
   a tool that ingests generated or user-supplied input.
2. **Represent what was written.** A transform can only preserve what the AST
   records, and a user can only reason about constructs the AST names honestly.
3. **Build an AST by hand.** Meta-programming is mostly *construction*, not
   parsing, and the construction API is what a user actually touches.
4. **Write C back out.** Done: `cfront/printer`, round-tripped against a
   megabyte of preprocessed QuickJS on every CI run.

Capability 4 exists. Capability 2 is most of the way there. Capabilities 1 and 3
are untouched, which is why they lead the plan.

## Where things stand

Done, in order: aggregate definitions ordered by definition rather than hoisted;
literals carrying the type their suffix selects; literals keeping the text that
was written, so `0xff`, `0755`, and `1ull` survive printing; and two miscompiles
fixed on the way (block-scoped tags colliding in a flat table, and `sizeof(1L)`
reporting 4).

## Plan

### Step A — Recoverable errors

`@parser.parse` has 48 `abort` calls. Invalid or unsupported C takes the process
down, so the README currently tells callers to parse in a separate process for
fault isolation. That is a workable answer for a compiler binary and not one for
a library.

The parser should return a result carrying diagnostics instead. This is the
single largest thing standing between `cfront` and being usable by anything
other than `kimicc`, and no amount of AST fidelity substitutes for it.

Worth noting that useful diagnostics want source locations, which is its own
step below. The two can be done in either order -- errors without locations
still beat aborting -- but doing locations first makes the diagnostics
worth reading.

### Step B — Stop lowering in the parser

The parser desugars on the way in, and the artifacts leak into what a suite user
must know:

- `case 3:` is stored as a label named `__kimicc_case_3_7`, with a counter baked
  into the name. To emit a `switch`, a user would have to reproduce that
  spelling.
- A local aggregate initializer becomes a `= 0` marker plus element assignments.
  There is no correct way to print that node, and no reasonable way to construct
  one.
- `int a, b;` becomes a `StmtList` grouping that exists only to hold the two
  declarations together.
- An anonymous `union { ... };` member becomes a field with an empty name whose
  type is a synthetic `__anon_union_0` tag.

Each of these is a parser internal that a user of the suite should never see.
Moving them into MIR lowering is what turns the AST from *faithful* into
*constructible*, which is why this is now the central step rather than the one
deferred to last.

The constraint that shapes the work: both code generators consume the lowered
shapes today, so each construct moved needs its MIR lowering added in the same
change. Parser and MIR cannot be split across pull requests without breaking the
build in between, so this is a series of medium changes -- one construct at a
time -- rather than one large one. That is better for review anyway.

### Step C — A construction API

The public surface has exactly one smart constructor, `int_literal`, added
incidentally while typing literals. Everything else is built by naming
constructors directly.

That is tolerable for simple nodes and not for the ones carrying invariants: an
integer literal whose text and cached value must agree, a floating literal whose
text is authoritative, a `switch` whose case table is derived from its body.
Those want constructors that maintain the invariant, and the awkward cases
mostly disappear once Step B removes the lowering — which is why this follows it
rather than leading.

Worth deciding here too: whether AST equality should stay syntactic. Keeping the
literal text makes `1.0` and `1.00` unequal, which is right for round-tripping
and surprising for a user comparing two generated trees. A custom `Eq` that
compares meaning rather than spelling is possible; it has not been needed yet.

### Step D — Source locations

A location on every node. Needed for diagnostics worth reading (Step A), and the
prerequisite for any format-preserving output — a formatter, as opposed to the
canonical printer that exists.

This is the largest change on the list and has no partial credit: a location
threaded through every constructor. It is also the one that would let the
literal *text* fields be recovered from source rather than stored, though that
is a simplification to consider rather than a reason to wait.

### Compiler correctness, tracked separately

These are `kimicc` concerns rather than suite concerns. They matter, but they do
not gate anything above and should not be confused with it.

- **A `float` value is 32 bits throughout** — decided and scoped; see the settled
  decisions below. Eight sites in `mir/body_interpreter.mbt` assume a 64-bit
  double pattern; the x64 backend already branches on float-versus-double in
  fourteen places. This is what unblocks `sizeof(1.0f)`, the last known wrong
  answer.
- **`const`, `volatile`, `restrict`** are absent from `@ctype.Type`, so they
  vanish. Dropping `volatile` is an optimizer-visible change. They fit the
  existing `Atomic`/`Aligned` wrapper pattern, which `Type::core_type` already
  strips.
- **Prototype versus unspecified parameters** — `int f()` and `int f(void)` are
  indistinguishable, so the printer must guess and gets it wrong for one of
  them.
- **Enum constant names** are folded to values, so they print as integers.

### Parser bugs, tracked separately

- A function returning a function pointer does not reparse: `void (*f(int))(void)`
  is read back as `void *f(int)`. Affects the tinycc and sqlite3 fixtures, and is
  why the tinycc fixture is not round-tripped in CI.
- `int *(*p)[2]` is misparsed as `Pointer(Pointer(Array))`.
- `int * _Atomic pa = &target;` is dropped from the program entirely.
- `1e400` lexes to `0.0` rather than infinity.
- Block-scoped `struct` tags were hoisted into one flat table; fixed, but the
  fix disambiguates by renaming, which puts a synthetic name in the AST. A
  faithful alternative would thread scoped identity through MIR and both
  backends.

## Settled decisions

**The AST keeps the surface form; MIR desugars.** Where the parser lowers on the
way in, the AST should record what was written and the lowering moves into MIR.
This is the principle behind Step B, and it answers where a hoisted static local
belongs: where it was written, inside the function, with MIR lifting it.

**Literals keep the text that was written.** `0xff` and `255` denote the same
value but are not the same program text, and a printer working from the value
has to guess. Integer literals cache the value alongside the text because
folding is hot; the text is authoritative and `int_literal` maintains the
agreement. Floating literals keep text only, because `Double` cannot represent
an x86 80-bit `long double` and a cache would reintroduce the truncation.

**A `float` value is 32 bits throughout.** The C standard does not fix a width;
IEEE binary32 comes from the optional Annex F. Both targets are binary32 in
practice. The standard permits evaluating float operations at greater precision
than the type, selected by `FLT_EVAL_METHOD`, so holding every floating value as
a 64-bit double pattern is legal rather than a bug — but both targets report
`FLT_EVAL_METHOD == 0`, so clang evaluates in single precision, and agreeing
with clang is this project's correctness standard.

Storage width and evaluation width are independent in C, which suggests
`sizeof(1.0f)` could be fixed separately and cheaply. It cannot here: `expr_type`
is recursive, so special-casing a bare literal would report 4 for `sizeof(1.0f)`
and 8 for `sizeof(1.0f + 1.0f)`. Uniformly wrong is easier to reason about than
inconsistently right.

**Miscompiles are fixed on their own, not as a side effect.** They are wrong
today for every user of the compiler, not only for round-tripping, so they get
their own changes rather than riding along with a refactor.

**`cfront` breaks freely until published.** Nothing outside this repository
consumes it, so the AST changes shape without compatibility shims. At publish
time `cfront` goes first, and its version and the pin in `kimicc`'s `moon.mod`
move together.

## What stays out of scope

Printing is canonical, not format-preserving. Even with every step above, the
AST records no comments and no original spacing, so `cfront/printer` will not
reproduce hand-written source byte for byte. That is a formatter, which needs
Step D plus comment attachment, and it is a different deliverable from the
suite.
