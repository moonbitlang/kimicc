# SQLite Conformance Plan

## Goal

Make the SQLite library object produced by kimicc pass SQLite's available public
tests, then keep it green with MoonBit e2e coverage. Until a broad test harness
is green, kimicc only claims the current SQLite smoke coverage listed below.

The current vendored fixture is SQLite 3.49.1:

- `SQLITE_VERSION_NUMBER`: `3049001`
- `SQLITE_SOURCE_ID`: `2025-02-18 13:38:58 873d4e274b4988d260ba8354a9718324a1c26187a4ab4c1cc0227c03d0f10e70`
- Fixture files: `test/fixtures/sqlite/sqlite3.c`, `test/fixtures/sqlite/sqlite3.h`

SQLite's proprietary TH3 suite is not public. Unless TH3 is supplied separately,
the target test set is the public SQLite source-tree tests matching the fixture
version/source id, plus focused kimicc e2e regressions for every compiler bug we
minimize.

## Constraints

- Run MoonBit commands with `--target native` on ARM64 macOS.
- Use `clang -E` for C preprocessing; kimicc is responsible for compiling the
  preprocessed SQLite translation unit to assembly/object code.
- Prefer async MoonBit e2e tests over shell scripts.
- It is acceptable for clang to compile small C test drivers or external test
  harness code while kimicc compiles `sqlite3.o`.
- Commit each stable slice: plan, harness, each failure class fix, and each
  meaningful test expansion.

## Current Baseline

Passing kimicc SQLite e2e tests:

- Compile/preprocess/assemble the vendored `sqlite3.c` fixture.
- Link kimicc's `sqlite3.o` with clang-built C drivers.
- Link SQLite's public Tcl `testfixture` with kimicc's `sqlite3.o`.
- Open an in-memory database and use basic APIs.
- Prepare and step a simple `select 1`.
- Create a table, insert rows, and read them back.
- Use bound statements, update rows, aggregate with `count`/`sum`, and verify
  `sqlite3_changes`.
- Run a deterministic SQL script through both clang-built SQLite and
  kimicc-built SQLite, then require identical output. This currently covers
  indexes, constraints, transactions, `insert ... select`, updates, ordered
  selects, and aggregate queries.
- Manually link SQLite's public Tcl `testfixture` with kimicc's SQLite object
  and pass public `test/select1.test` through `test/selectH.test` with 0
  errors across 37796 tests.
- Pass SQLite's public `ext/expert/expert1.test` with 0 errors across 75 tests.
- Pass SQLite's public `ext/fts5/test/fts5contentless.test` with 0 errors
  across 121 tests.
- The malformed FTS5 index cluster is fixed. The next sampled FTS5 blocker is
  `ext/fts5/test/fts5aa.test`, where six `16.2` rank-score checks differ from
  clang.

This is useful smoke coverage, not a claim that SQLite passes its test suite.

## Upstream Public Test Source

Use the official SQLite Fossil tarball for the exact check-in embedded in the
fixture:

```text
https://www.sqlite.org/src/tarball/sqlite-src-3049001.tar.gz?r=873d4e274b4988d260ba8354a9718324a1c26187a4ab4c1cc0227c03d0f10e70
```

Inspection result:

- Archive SHA-256: `d63fa87b18edd5881f764d2100695abcccdd0e370526d4a9d918be0232ee16eb`
- Extracted `VERSION`: `3.49.1`
- Extracted `manifest.uuid`: `873d4e274b4988d260ba8354a9718324a1c26187a4ab4c1cc0227c03d0f10e70`
- Archive entries: `2272`
- Public Tcl test scripts: `1159` under `test/*.test`, plus `145` under
  extension test directories.
- Public runner: `test/testrunner.tcl`. Its default binary mode runs the
  `veryquick` set with `./testfixture $TESTDIR/testrunner.tcl`; `full` runs all
  Tcl scripts, and `all` runs full plus selected permutations.

Do not vendor this whole source tree by default yet. It is large and the current
routine MoonBit tests should remain hermetic and fast. Instead, make broader
SQLite conformance an explicit harness mode that accepts a checked-out or
cached source tree via environment variable, while the repo keeps the small
amalgamation fixture and focused e2e regressions in version control.

## Todo

- [x] Clean slate: native build/test has no compilation errors.
- [x] Vendor a SQLite amalgamation fixture.
- [x] Add async MoonBit compile-link-run e2e tests around the SQLite object.
- [x] Fix compiler issues exposed by the first SQLite smoke tests.
- [x] Identify the exact public SQLite test source that matches the fixture.
- [x] Decide whether to vendor the matching public test tree or fetch it into a
  cache during explicit SQLite conformance runs.
- [x] Add a MoonBit harness entry point for broader SQLite tests.
- [x] Add a small SQL-script runner before trying the full upstream test suite.
- [x] Run the first broader batch with both clang-built SQLite and kimicc-built
  SQLite to separate harness bugs from compiler bugs.
- [x] Link a public SQLite Tcl `testfixture` binary with kimicc's SQLite object.
- [ ] Add a public SQLite Tcl `testfixture` harness mode to MoonBit tests.
- [x] Run the first upstream public Tcl batch through the `testfixture` harness.
- [ ] For every failure class, record the command, output, generated assembly or
  object paths, clang-vs-kimicc behavior, minimized C or SQL repro, status, and
  fixing commit.
- [ ] Fix one compiler failure class at a time with focused e2e regressions.
- [ ] Grow the batch until the public SQLite suite passes or the remaining
  failures are explicitly blocked on missing upstream/private test assets.

## Failure Ledger

| Status | Area | Repro | Notes |
| --- | --- | --- | --- |
| Passed | SQL script differential harness | `moon test test/e2e --target native --filter 'sqlite object matches clang baseline for SQL script runner'` | clang-built and kimicc-built SQLite objects produced identical output. |
| Fixed | File-scope static linkage | `moon test test/e2e --target native --filter 'e2e file scope static symbols have internal linkage'` | Top-level `static` functions and globals now emit local symbols, fixing duplicate-symbol link failures such as SQLite's `aSyscall`. |
| Fixed | Extern and tentative global declarations | `moon test test/e2e --target native --filter 'e2e extern globals do not allocate storage'`; `moon test test/e2e --target native --filter 'e2e tentative global followed by initialized definition emits once'` | `extern` declarations no longer allocate storage, and later initialized definitions replace earlier extern/tentative declarations before codegen emits globals. |
| Fixed | Function pointer call through explicit dereference | `moon test test/e2e --target native --filter 'e2e function pointer call through explicit dereference'`; `moon test test/e2e --target native --filter 'e2e function pointer returned from function then dereferenced'` | Calls such as SQLite FTS3's `(*xHash)(pKey,nKey)` now branch to the function pointer value instead of loading through the function address. |
| Fixed | Local arrays of structs with nested initializer lists | `moon test test/e2e --target native --filter 'e2e local array of structs with nested initializer'` | Local struct definitions are available to initializer lowering immediately, and local aggregate initializers are zero-filled before field/element assignments. This fixed SQLite startup misuse in FTS5 builtin registration. |
| Fixed | Layout-aware `sizeof` in global/static initializers | `moon test test/e2e --target native --filter 'e2e static aggregate initializer folds sizeof typedef struct'` | Public parser constant folding uses a fallback size for structs without layout context. Global initializer emission now folds constants through codegen's layout-aware type sizes, fixing SQLite's `__sqlite3_os_init_aVfs.szOsFile` from `8` to `160` and eliminating the `sqlite3OsClose` crash. |
| Fixed | Darwin ARM64 variadic calls through function-pointer casts | `moon test test/e2e --target native --filter 'variadic function pointer cast passes unnamed args on stack'` | SQLite casts syscall table entries like `aSyscall[7].pCurrent` to `int (*)(int,int,...)` before calling `fcntl`. The parser now preserves function-pointer parameter and variadic metadata so codegen uses the Darwin variadic argument ABI and passes unnamed arguments on the stack. This fixed the earlier `database is locked` failure caused by `fcntl(F_GETLK, ...)` receiving a bad third argument. |
| Fixed | Nested function-pointer declarators and pointer-to-function-pointer fields | `moon test test/e2e --target native --filter 'e2e struct field pointer to function pointer stores full address'`; `moon test test/e2e --target native --filter 'e2e function pointer returning pointer preserves return type'` | Declarators now distinguish `void *(*f)(void)` from `void (**f)(void)`. This preserves `Pointer(FuncPtr(...))` for SQLite's `wsdAutoext.aExt`, preventing 32-bit fallback stores that truncated auto-extension function addresses. |
| Fixed | SQLite `sqlite3AtoF` unsigned arithmetic and 64-bit immediates | `moon test test/e2e --target native --filter 'e2e sqlite-style unsigned u64 atof threshold'` | SQLite's decimal parser depends on unsigned 64-bit division/comparison/right-shift semantics and on loading full-width 64-bit constants. kimicc now keeps unsigned integer result types for arithmetic where needed and emits all four 16-bit chunks for positive 64-bit immediates. |
| Fixed | SQLite `sqlite3FpDecode` negated double to `u64` cast | `moon test test/e2e --target native --filter 'e2e sqlite-style fpdecode negated double cast'` | The public `select1.test` floating mismatches minimized to `v = rr[1]<0.0 ? (u64)rr[0]-(u64)(-rr[1]) : ...`; unary `-` was typed as `int`, so `(u64)(-rr[1])` kept raw double bits. Unary floating negation now preserves floating type, unary bit-not uses integer promotion, and unsigned integer to floating casts use unsigned conversion. `sqlite3_mprintf("%!.15g", 1.1)` and `sqlite3_column_text()` now format real values correctly. |
| Fixed | Public SQLite Tcl `select1.test` database reopen after section 13 | `moon test test/e2e --target native --filter 'e2e octal integer literal preserves file mode value'`; `moon test test/e2e --target native --filter 'sqlite object creates file database with readable mode'` | The reopen failure minimized to C octal integer constants: kimicc parsed `0644` as decimal `644`, so SQLite created database files as mode `0204` after umask and could not reopen them. Leading-zero integer constants now parse as octal, and kimicc's SQLite object creates readable `0644` file databases. |
| Passed | Public SQLite Tcl `select1.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/test/select1.test` after linking `TESTFIXTURE_SRC1=/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture now passes `select1.test`: 0 errors out of 192 tests. The matching clang-built testfixture also passes, giving a clean first public Tcl batch for comparison. |
| Fixed | Conditional operator with local array operands | `moon test test/e2e --target native --filter 'e2e ternary array operands decay before indexing'` | Public `select2.test` crashed in `select2-2.0.1` during `balance_nonroot`. The minimized source was SQLite's `(nNew>nOld ? apNew : apOld)[nOld-1]`: kimicc typed the ternary as an array lvalue, `gen_addr` emitted no address for it, and array indexing used the boolean condition as the base pointer. Ternary result typing now decays array branch operands to pointer values before indexing. |
| Passed | Public SQLite Tcl `select2.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/test/select2.test` after linking `TESTFIXTURE_SRC1=/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture now passes `select2.test`: 0 errors out of 21 tests. This covers nested SELECTs, large insert batches, btree page balancing, index creation, and indexed lookup checks. |
| Passed | Public SQLite Tcl `select3.test` through `select5.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/test/select3.test`; same for `select4.test` and `select5.test` after linking `TESTFIXTURE_SRC1=/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture passes `select3.test` (0/91 errors), `select4.test` (0/124 errors), and `select5.test` (0/35 errors). No new compiler failure class was exposed in this batch. |
| Passed | Public SQLite Tcl `select6.test` through `select9.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/test/select6.test`; same for `select7.test`, `select8.test`, and `select9.test` after linking `TESTFIXTURE_SRC1=/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture passes `select6.test` (0/88 errors), `select7.test` (0/27 errors), `select8.test` (0/4 errors), and `select9.test` (0/36717 errors). No new compiler failure class was exposed in this batch. |
| Fixed | Aggregate conditional operator source addresses | `moon test test/e2e --target native --filter 'e2e struct ternary assignment copies selected operand'` | Public `selectC.test` crashed in `selectC-2.1` while preparing a trigger. The reduced parser action was `Token out = cond ? a : b` expressed as a struct assignment: kimicc asked `gen_addr` for the conditional expression, got no fresh address, and then copied 16 bytes from a stale call result. Aggregate copy sources now use `gen_aggregate_addr`, which selects the correct branch address for ternary aggregate expressions and is shared by struct/union assignments, local aggregate initializers, and aggregate call arguments. |
| Passed | Public SQLite Tcl `selectA.test` through `selectH.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/test/selectA.test`; same for `selectB.test` through `selectH.test` after linking `TESTFIXTURE_SRC1=/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture passes `selectA.test` (0/231 errors), `selectB.test` (0/171 errors), `selectC.test` (0/30 errors), `selectD.test` (0/32 errors), `selectE.test` (0/8 errors), `selectF.test` (0/3 errors), `selectG.test` (0/4 errors), and `selectH.test` (0/18 errors). |
| Fixed | Pointer relational comparisons against sentinel addresses | `moon test test/e2e --target native --filter 'e2e pointer less-than uses unsigned address ordering'` | Public `veryquick.test` first failed in `ext/expert/expert1.test` with `ESCAPE expression must be a single character`. This minimized to SQLite's `sqlite3Utf8CharLen("x", -1)`: `zTerm = (const u8*)(-1)` relies on unsigned address ordering for `z < zTerm`, but kimicc emitted signed `lt`. Pointer relational comparisons now use unsigned condition codes, matching clang on ARM64 macOS. This fixes the expert ESCAPE failure and all ESCAPE failures in `e_expr.test`. |
| Fixed | Nested struct field initializers inside local arrays | `moon test test/e2e --target native --filter 'e2e nested struct field initializer in local array'` | Public `veryquick.test` crashed in `ext/expert/expert1.test` after `expert1-2.19.0` while FTS5 called a tokenizer function pointer. The minimized source was SQLite's `struct BuiltinTokenizer aBuiltin[] = { { "unicode61", {fts5UnicodeCreate, ...} } }`: kimicc assigned the nested struct field from the stale string-pointer register instead of lowering the nested brace list recursively. Local struct/union field initializers now recurse into nested aggregate brace lists. |
| Passed | Public SQLite Tcl `expert1.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/ext/expert/expert1.test` after linking `TESTFIXTURE_SRC1=/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture now passes `expert1.test`: 0 errors out of 75 tests. This clears the previous FTS5 tokenizer SIGBUS. |
| Fixed | Raw byte string literal emission | `moon test test/e2e --target native --filter 'e2e hex escape string literal preserves raw bytes'` | Public FTS5 malformed-index failures minimized to `FTS5_STRUCTURE_V2`, the string literal `"\xFF\x00\x00\x01"`. kimicc emitted `0xFF` as UTF-8 `C3 BF`, then placed embedded-NUL string literals in Darwin's `__TEXT,__cstring,cstring_literals` section. String emission now uses fixed octal byte escapes and pools string literals in `__TEXT,__const`, matching clang for embedded NUL bytes. |
| Passed | Public SQLite Tcl `fts5contentless.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/ext/fts5/test/fts5contentless.test` from an isolated temporary working directory after linking `TESTFIXTURE_SRC1=/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture now passes `fts5contentless.test`: 0 errors out of 121 tests. The clean clang-linked baseline also passes 0/121. |
| Open | Public SQLite Tcl `fts5aa.test` rank-score mismatch | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/ext/fts5/test/fts5aa.test` from an isolated temporary working directory after linking `TESTFIXTURE_SRC1=/tmp/kimicc_sqlite3_testfixture.o` | The malformed-index failures in this file are gone, but kimicc still reports 6 failures in the `16.2` cases: expected `0 {{} -1e-06 {}}`, got `0 {{} -2.2e-06 {}}` for full/col/none and origintext variants. The clang-linked baseline passes `fts5aa.test` with 0 errors out of 1427 tests. This is the next failure class to minimize. |

## Execution Plan

1. Pin the test assets. Locate the public SQLite source checkout or release
   archive matching `SQLITE_SOURCE_ID`, then document its provenance and layout.
2. Build a harness in MoonBit. It should compile kimicc's `sqlite3.o`, build a
   clang baseline object, run the same driver/test inputs against both, and keep
   artifacts under stable `/tmp/kimicc_*` paths for debugging.
3. Start with a deterministic SQL-script runner. This gives quick coverage for
   SQL behavior without first integrating SQLite's Tcl harness.
4. Move to upstream public tests in batches. Run a small named batch first,
   compare clang and kimicc results, then expand only after the failure ledger is
   empty for that batch.
5. Minimize and fix failures. Every compiler fix should add a focused e2e test
   that does not depend on the full SQLite fixture unless the bug only appears
   there.
6. Keep status truthful. Update this document after each batch and do not mark
   SQLite conformance complete until the broad harness is green.
