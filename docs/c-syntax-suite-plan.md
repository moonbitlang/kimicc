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
4. **Write C back out.** `cfront/printer`, round-tripped against a megabyte of
   preprocessed QuickJS on every CI run -- and, since the ordering and
   anonymous-member work, *compiled* by clang on every CI run, which is the
   test the round-trip could not make: the round-trip reparses printed output
   with this project's own parser, which accepts what it itself printed, so a
   fixed point over invalid C passes it. The printed QuickJS fixture once drew
   1,174 clang errors while the round-trip was green.

Capability 4 exists and is now tested against the objective's own words --
"C another compiler accepts". Capability 2 is most of the way there.
Capabilities 1 and 3 are untouched, which is why they lead the plan.

## Where things stand

Done, in order: aggregate definitions ordered by definition rather than hoisted;
literals carrying the type their suffix selects; literals keeping the text that
was written, so `0xff`, `0755`, and `1ull` survive printing; two miscompiles
fixed on the way (block-scoped tags colliding in a flat table, and `sizeof(1L)`
reporting 4); `case`/`default` as statements rather than synthetic labels, the
first construct moved out of the parser under Step B; and local aggregate
initializers recorded as written, the second.

## Plan

### Step A — Recoverable errors

`@parser.parse` has 48 `abort` calls. Invalid or unsupported C takes the process
down, so the README currently tells callers to parse in a separate process for
fault isolation. That is a workable answer for a compiler binary and not one for
a library.

**Errors are raised, not returned.** MoonBit tracks checked errors in the
signature, so a `suberror` with `raise` is the idiom here; `Result` would be the
Rust habit rather than the MoonBit one.

The shape:

```
pub(all) struct Position { offset : Int; line : Int; column : Int }

pub suberror ParseError {
  Unexpected(position~ : Position, expected~ : String, found~ : String)
  Unsupported(position~ : Position, what~ : String)
  Malformed(position~ : Position, what~ : String)
}
```

A diagnostic needs a position, and a *parse* diagnostic does not need positions
on AST nodes -- the parser knows where it is from `Lexer::pos` at the moment it
fails. Line and column are derived from that offset when an error is raised
rather than tracked per token, since the parsing path never needs them. This is
worth stating because the two are easy to conflate: locations *on nodes* are for
semantic diagnostics and format preservation, and are Step D.

**Scale, measured.** Converting a single site shows the shape of the work:
making `Parser::expect` raise produces 110 compile errors, because every caller
must then declare `raise ParseError` too. The change is mechanical -- the
compiler names each function that needs the annotation -- but it propagates
through the parser's whole call graph and then to the boundaries in `mir`,
`codegen`, `jit`, and `cmd/main`, which must either propagate or handle. Expect
a large diff of signature changes rather than logic changes, and a decision at
each boundary about whether a caller reports or aborts.

### Step B — Stop lowering in the parser

The parser desugars on the way in, and the artifacts leak into what a suite user
must know:

- `case 3:` was stored as a label named `__kimicc_case_3_7`, with a counter
  baked into the name. Done: `Case` and `Default` are statements, `Switch`
  carries no case table, and each backend synthesizes the labels its own
  dispatch needs.
- A local aggregate initializer became a `= 0` marker plus element assignments,
  which had no correct printed form and no reasonable constructed one. Done: a
  brace initializer is recorded as the `Array` expression it was written as,
  designators included, and `char s[] = "abc"` keeps the string. The parser
  still decides the size the braces imply, because that size is part of the
  type the declaration carries.
- `int a, b;` became a `StmtList` grouping that existed only to hold the two
  declarations together. Done: one `VarDecl` per name, side by side in the
  block, since the grouping carries nothing a consumer could act on once each
  name has its own type. `For` took an init list in the same change, because
  `for (int i = 0, n = len; ...)` is the one place C requires the grouping and
  the printer now rebuilds it there from `split_declaration`. Declarations that
  declare nothing -- a `typedef`, a `_Static_assert`, a local prototype, an
  `asm` statement -- stopped leaving an `ExprStmt(0)` placeholder behind.
- An anonymous `union { ... };` member becomes a field with an empty name whose
  type is a synthetic `__anon_union_0` tag. Done: anonymity is first-class on
  `StructDecl` as `is_anonymous` -- provenance the spelling cannot carry, since
  real headers write `__anon_` tags of their own -- and it is part of equality,
  because an empty-named field of an anonymous type is a member whose fields
  reach through while the same field with a written tag declares nothing.
  Anonymous definitions print tagless wherever a member site consumes them; the
  synthesized tag is spelled out only where something else references it, and
  anonymity may decay true-to-false across such a print, never appear. The
  synthetic name remains the type's identity in the AST, and tag synthesis
  skips taken numbers so a reparse lands on the same names.

Each of these is a parser internal that a user of the suite should never see.
Moving them into MIR lowering is what turns the AST from *faithful* into
*constructible*, which is why this is now the central step rather than the one
deferred to last.

The constraint that shapes the work: both code generators consume the lowered
shapes today, so each construct moved needs its MIR lowering added in the same
change. Parser and MIR cannot be split across pull requests without breaking the
build in between, so this is a series of medium changes -- one construct at a
time -- rather than one large one. That is better for review anyway.

The initializer step showed what that constraint understates. MIR and both code
generators already walked brace initializers for compound literals and aggregate
members, so no new walk had to be written -- but the parser's expansion had been
quietly supplying behaviour those walks never needed, and each gap only appeared
once the expansion stopped. Seven of them.

Three were in MIR, all because the expansion's assignments met MIR on its
assignment path: placing an object into an aggregate member (`struct ctx c = {
..., argv[0] }`, which QuickJS writes), decaying an array to a pointer inside an
initializer (sqlite's `sqlite3WindowUpdate` over its `static const char[]`
names), and filling a `char` array member from a string.

Four were in the parser-direct code generators, and all four were those walkers
diverging from MIR rather than MIR being incomplete: matching the written type
instead of the core type, so `_Alignas` aggregates missed the aggregate path in
three places; no path at all on x86-64 for a string filling a `char` array, which
aborted; a prepass that reserved aggregate return scratch while walking into
`.field` but not `[index]`, so a call behind a designator read from a negative
frame offset; and struct and union walkers that handed the designator selecting a
member down to the member's own walker, which read it again whenever the member's
type had a field of the same name.

Two lessons for the constructs still to move. The question is not "does a lowering
exist for this shape" but "what did the expansion do that nothing else does" --
and compiling the sqlite and QuickJS fixtures directly answers it in seconds,
where a full test run surfaces one gap per cycle. Then: when the parser-direct
walkers and MIR disagree about an initializer, MIR has been right every time, so
the diff between them is where to look first.

The other cost was the rule for reading *through* braces: `int a[2] = {{5}, {37}}`
is legal C, the parser used to fold those inner braces away while lowering, and
each walker now has to do it at the point it stores a scalar. That rule is
`@parser.scalar_initializer_value`, one function all three call, rather than
three chances to disagree.

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

A location on every node. Needed for *semantic* diagnostics -- an error about a
type or a name, pointing at the construct responsible -- and the prerequisite
for format-preserving output. Parse diagnostics do not need it; see Step A.

This is the largest change on the list and has no partial credit: roughly 995
expression and 406 statement constructor uses across 12 files, and unlike the
literal work the *matches* change shape too, since `Expr` would become a struct
with a `kind` field. A cheaper variant worth weighing first is locations on
statements and declarations only, which is about a quarter of the work for
coarser messages. It is also the one that would let the
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

- **Brace elision is unsupported.** `int m[2][3] = {1, 2, 3, 4, 5, 6}` and any
  other initializer that leaves out the braces for a subobject is rejected
  rather than compiled. It was rejected before the initializer move too, by the
  semantic check catching the assignment to `m[0]` that the parser's expansion
  produced; now each backend declines it, since the parser no longer produces
  anything for the check to catch. Supporting it means turning three initializer
  walkers from "one item per subobject" into a cursor over a flat item list,
  which changes the shared path compound literals and global initializers take
  as well, so it is its own change rather than part of this one.

- A function returning a function pointer does not reparse: `void (*f(int))(void)`
  is read back as `void *f(int)`. Affects the tinycc and sqlite3 fixtures, and is
  why the tinycc fixture is not round-tripped in CI. It is also the whole
  residue of "printed sqlite compiles under clang": thirteen diagnostics, all
  tracing to `xDlSym` and calls through it, allowed by pattern in the e2e gate
  until this parse is fixed.
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
belongs: where it was written, inside the function, with MIR lifting it. The
hoisting is now also the whole residue of "printed QuickJS compiles under
clang": the interpreter's computed-goto dispatch table is a static local full
of `&&label` addresses, and hoisted to file scope those are outside any
function. Two diagnostics, allowed by pattern in the e2e gate until statics
stop being hoisted.

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

## ds4 generation: gap list and verification ladder

Surveyed 2026-08-13 against `~/git/ds4` — a built Metal checkout with the real
model attached: DeepSeek-V4-Flash, 81GB GGUF, mixed quantization (IQ2_XXS
routed gate/up experts, Q2_K down experts, Q8_0 attention projections / shared
experts / output, Q8_K activation blocks). The machine is an M2 Ultra with
192GB, so the model runs fully resident. ds4's own shape constants
(`DS4_N_LAYER` etc.) resolve to runtime globals (`g_ds4_shape`) — the engine is
generic across the DeepSeek family, which is exactly the specialization
headroom the generator thesis needs.

**What the hot path actually uses.** All CPU compute funnels through ~30 worker
functions of shape `(void *ctx, uint64_t lo, uint64_t hi)` dispatched by a
hand-written pthread pool. Kernels are `static inline` dots over 34-byte q8_0
blocks and 256-element QK_K super-blocks, with NEON `vdotq_s32`/`vld1q_s8`/
`vfmaq_n_f32` fast paths behind `#if defined(__ARM_FEATURE_DOTPROD)`, `memcpy`
for unaligned f16 scale loads, bit-twiddled f16→f32, and — for IQ2_XXS — a
codebook table built at runtime by `pthread_once`. Notably ds4 uses zero
`restrict` and no C11 atomics in kernels, and ships its own `_f32_ref`
reference kernels alongside the fast ones.

**True gaps, ranked:**

1. **`Named(String)` type variant** — **done** (cfront@0.3.0). The printer
   emits the spelling verbatim; `parse_with_named_types` seeds the typedef
   table with registered spellings, which is the reading half of the round
   trip — an unregistered spelling stays a parse error rather than a silent
   misread. Layout queries (`size`, `align`, sizeof folds) and both code
   generators reject it by construction, enumerated by the compiler when the
   variant landed. The quickcheck corpus now declares Named-typed locals
   from a fixed pool. Riding along: `for_range` takes a counter type, and
   `int_literal` synthesizes the suffix its type demands (`5u`, `5L`,
   `5uLL`) — a bare synthesized `5L`-value used to reparse as `SInt`, a
   latent round-trip asymmetry nothing had exercised.
2. **Attribute surface for GPU functions and parameters** — blocks only the
   Metal rung: `kernel` qualifiers, address spaces (`device`, `constant`,
   `threadgroup`), and `[[buffer(0)]]`-style attributes. Design as opaque
   attribute strings on FuncDecl/Param rather than modeling MSL — the same
   surface later serves CUDA `__global__`. ds4 compiles its 22,851 lines of
   MSL from source at runtime (`newLibraryWithSource`), so generated kernels
   drop in as strings with no `.metallib` step.
3. **Micro-gaps, minutes each:** `for_range` hardcodes `int` counters (ds4
   loops on `uint64_t`); a u-suffix literal helper; optional typedef emission
   (writing `struct block_q2_K` spelling avoids it).

**Explicitly not gaps:** the pthread pool and MoE routing are host-side by the
seam rule; `#if` target dispatch is resolved at generation time (the generator
is the preprocessor); `pthread_once` table init is replaced by baking the
expanded 262KB IQ2_XXS grid as a static initializer — generation-time folding
is the thesis, and aggregate initializers already landed; `const` retention
would break the canonical-form contract for cosmetic benefit (ds4's kernels
compile identically without it) and is deferred.

**Verification ladder,** each rung reusing the llama2 referee pattern
(differential test that skips when the fixture is absent):

- **L0 (exists):** printed-output-compiles clang gate; quickcheck round-trip,
  extended alongside each AST addition.
- **L1 — random-block differential:** a driver that `#include "ds4.c"` (the
  `DS4_NO_GPU -DDS4_TEST_HOOKS` build from ds4's own Makefile reaches statics)
  and compares generated kernels against ds4's on random blocks: scalar vs
  scalar bit-exact, NEON vs ds4-NEON bit-exact by mirroring accumulation
  order. The baked IQ2_XXS table is `memcmp`'d against the `pthread_once`
  product.
- **L2 — real-tensor differential:** mmap the 81GB GGUF read-only, locate one
  tensor per quant format from the header, run row dots against a random
  activation vector. Catches layout misreads that self-generated random
  blocks structurally cannot.
- **L3 — drop-in A/B:** patch ds4's static workers to call extern generated
  ones, rebuild `make cpu`, and referee with `ds4-bench --cpu
  --dump-frontier-logits-dir` stock vs patched: logits identical, then tok/s
  from `--csv`. This is the thesis measurement — baked shapes and tables
  against runtime-shape stock.
- **L4 — Metal:** `xcrun metal -fsyntax-only` as the compile gate analog, a
  small ObjC harness dispatching generated kernels on random buffers against
  CPU scalar referees, then source-string drop-in into ds4's runtime shader
  compile and the same logits/tok-s A/B under `--metal`.

Order of work: L1 harness with today's framework (scalar q8_0 + Q2_K +
IQ2_XXS — zero missing features), then `Named` + NEON under the same harness,
then L3, and only then the Metal rung.

**Status: L1 and L2 landed.** `experiments/ds4_kernels` generates the three
scalar kernels with all offsets, group shifts, and the 262KB IQ2_XXS sign
table baked (the table reconstructed from the 256-entry codebook plus the
parity structure of `ksigns_iq2xs`, not transcribed). The referee
(`test/e2e/ds4_kernels_real_test.mbt`) confirmed on first run: baked table
memcmp-identical to ds4's runtime expansion, 800 random-block comparisons
bit-exact against ds4's own kernels, 24 real rows from the 81GB checkpoint
bit-exact across all three formats. One toolkit lesson recorded: compound
assignment ops are stored without the `=` (the printer appends it), and
`SChar` prints as `char` — the canonical spelling callers must match.

Codex (xhigh) then made the referee honest about deployment: under ds4's
real `-O3 -ffast-math` flags the compiler reassociates the generated
unrolled reductions differently from ds4's rolled loops — 369 bit
mismatches that the strict-flags build never sees. The referee now runs
twice: strict flags hold the kernels to bit equality (semantics), ds4's
production flags hold them to reassociation-level relative error, 1e-4
against ~1e-6 observed drift (deployment). Fast-math waives
bit-determinism by definition, so that second standard — tolerance plus
token agreement, not bits — is also what the L3 drop-in referee inherits.

## What stays out of scope

Printing is canonical, not format-preserving. Even with every step above, the
AST records no comments and no original spacing, so `cfront/printer` will not
reproduce hand-written source byte for byte. That is a formatter, which needs
Step D plus comment attachment, and it is a different deliverable from the
suite.
