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
- Build SQLite's public Tcl `testfixture` from a MoonBit async e2e harness and
  pass public `test/select1.test` through `test/selectH.test` with 0 errors
  across 37796 tests.
- Pass SQLite's public `ext/expert/expert1.test` with 0 errors across 75 tests.
- Pass SQLite's public `ext/fts5/test/fts5contentless.test` with 0 errors
  across 121 tests.
- Pass SQLite's public `ext/fts5/test/fts5aa.test` with 0 errors across 1427
  tests.
- Pass SQLite's public `ext/fts5/test/fts5origintext4.test` with 0 errors
  across 6 tests.
- Pass SQLite's public `ext/intck/intck1.test` with 0 errors across 70 tests.
- Pass SQLite's public `ext/intck/intck2.test` with 0 errors across 24 tests.
- Pass SQLite's public `ext/recover/recover1.test` with 0 errors across 105
  tests.
- Pass SQLite's public `ext/rtree/rtree2.test` with 0 errors across 4051 tests.
- Pass SQLite's public `ext/rtree/rtree7.test` with 0 errors across 8 tests.
- Pass SQLite's public `ext/rtree/rtree9.test` with 0 errors across 120 tests.
- Pass SQLite's public `test/avtrans.test` with 0 errors across 315 tests.
- Pass SQLite's public `test/decimal.test` with 0 errors across 35 tests.
- Pass SQLite's public `test/func7.test` with 0 errors across 73 tests.
- Pass SQLite's public `test/corruptI.test` with 0 errors across 24 tests.
- Pass SQLite's public `test/incrcorrupt.test` with 0 errors across 36 tests.

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
- [x] Add a public SQLite Tcl `testfixture` harness mode to MoonBit tests.
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
| Passed | MoonBit public SQLite Tcl `testfixture` harness | `moon test test/e2e --target native --filter 'sqlite public tcl select batch passes through testfixture harness'` | The e2e harness compiles a `SQLITE_TEST`/testfixture-flavored SQLite object with kimicc, configures the matching public SQLite source tree from `/tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001`, links `testfixture` with clang-built test sources, and passes `test/select1.test` through `test/selectH.test` with 0 errors out of 37796 tests from one linked `testfixture`. The harness can also build a clang-linked `testfixture` for failure comparison. If the public source tree is not present locally, this harness returns a skip marker so routine tests stay portable. |
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
| Fixed | Mixed integer/floating arithmetic conversions | `moon test test/e2e --target native --filter 'e2e mixed int double arithmetic promotes operands'` | Public `fts5aa.test` rank-score failures minimized to SQLite FTS5 BM25's `1 - b + b * D / pData->avgdl` denominator. kimicc typed the expression as floating-point but moved raw integer bits into FP registers without converting mixed integer operands, so `1 - b` behaved as `0 - b` and the denominator collapsed. Binary FP operations now convert each operand to the common FP type before arithmetic/comparison, and scalar local init/assignment/return paths convert to the destination type before storing or returning. |
| Passed | Public SQLite Tcl `fts5aa.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/ext/fts5/test/fts5aa.test` from an isolated temporary working directory after linking `TESTFIXTURE_SRC1=/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture now passes `fts5aa.test`: 0 errors out of 1427 tests. The direct BM25 probe for `SELECT bm25(n1), format('%g',bm25(n1)) FROM n1 WHERE n1 MATCH 'a+b+c+d'` now matches clang at `-1e-06`. |
| Fixed | Scalar conversion results for narrow unsigned integers | `moon test test/e2e --target native --filter 'e2e prefix increment returns truncated unsigned scalar'` | Public `fts5origintext4.test` corrupted a B-tree page during a large FTS5 insert. The minimized pattern was SQLite's page-header carry update `if( (++data[pPage->hdrOffset+4])==0 ) data[pPage->hdrOffset+3]++`: kimicc stored the low byte as `0` but left the prefix-increment expression value as `256`, skipping the high-byte carry. Cast, assignment, return, local initialization, and prefix inc/dec results now normalize to the destination scalar type. |
| Passed | Public SQLite Tcl `fts5origintext4.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/ext/fts5/test/fts5origintext4.test` from an isolated temporary working directory after linking `TESTFIXTURE_SRC1=/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture now passes `fts5origintext4.test`: 0 errors out of 6 tests. A rerun of `veryquick.test` now gets past the prior FTS5 corruption and next exposes the `intck1`/`intck2` cluster. |
| Fixed | Nested bit-field assignment expression result | `moon test test/e2e --target native --filter 'e2e nested bit-field assignment returns assigned value'` | Public `intck1.test` and `intck2.test` failures minimized to `db->init.busy = db->init.imposterTable = __builtin_va_arg(ap, int)` in `sqlite3_test_control(SQLITE_TESTCTRL_IMPOSTER, ...)`. kimicc stored the bit-field correctly but left the expression result as shifted container bits, so the nested assignment to `u8 busy` wrote `0`; SQLite then created ordinary empty tables instead of imposter tables over index roots. Bit-field assignment now returns the unshifted assigned value, sign-extended for signed bit-fields. |
| Passed | Public SQLite Tcl `intck1.test` and `intck2.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/ext/intck/intck1.test`; same for `intck2.test` from isolated temporary working directories after linking `TESTFIXTURE_SRC1=/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture now passes `intck1.test` (0 errors out of 70 tests) and `intck2.test` (0 errors out of 24 tests). A direct imposter-table probe now matches clang before and after deleting index rows. |
| Fixed | Atomic builtins on array pointer arithmetic | `moon test test/e2e --target native --filter 'e2e atomic array element access uses element width'` | Public `recover1.test` crashed at `recover1-16.1` after enabling WAL. The reduced C driver was `PRAGMA journal_mode=wal; CREATE TABLE ...; INSERT ...`, which faulted in `walTryBeginRead` on `ldar x9, [x0]` from a 4-byte-aligned WAL shared-memory field. kimicc typed `pInfo->aReadMark+i` as `int` instead of pointer-to-`u32`, so `__atomic_load_n()` selected a 64-bit atomic load. Binary type inference now decays arrays for pointer arithmetic, pointer difference returns `long`, and codegen scales the integer operand for both `ptr + int` and `int + ptr`. |
| Passed | Public SQLite Tcl `recover1.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/ext/recover/recover1.test` from an isolated temporary working directory after linking `TESTFIXTURE_SRC1=/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture now passes `recover1.test`: 0 errors out of 105 tests. A tiny C WAL driver linked against kimicc's standalone SQLite object also exits with `42`, matching clang. |
| Fixed | Prototype-driven scalar argument conversions | `moon test test/e2e --target native --filter 'e2e prototype converts float argument to double parameter'` | Public RTree failures minimized to calls such as `sqlite3_result_double(ctx, c.f)`, where `c.f` is a `float` union member and the declared callee parameter is `double`. kimicc classified call arguments only by expression type, so it passed the 32-bit float payload in `sN`; the callee read `dN` and returned tiny doubles such as `5.26354424712089e-315`. Codegen now records function parameter types and converts known named arguments to the declared parameter type before ABI register assignment. |
| Fixed | Decimal floating literal suffix parsing | `moon test test/e2e --target native --filter 'e2e prototype converts float argument to double parameter'` | While reducing the RTree ABI issue, `1.0f` parsed as `0.0` because the lexer included the `f` suffix in the string passed to `parse_double` and silently recovered to zero. Decimal floating literals now parse the numeric span before consuming `f/F/l/L` suffixes. This also protects preprocessed SQLite literals such as `1.17549435e-38F`. |
| Passed | Public SQLite Tcl `rtree2.test`, `rtree7.test`, and `rtree9.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/ext/rtree/rtree2.test`; same for `rtree7.test` and `rtree9.test` from isolated temporary working directories after linking `TESTFIXTURE_SRC1=/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture now passes `rtree2.test` (0 errors out of 4051 tests), `rtree7.test` (0 errors out of 8 tests), and `rtree9.test` (0 errors out of 120 tests). A fresh `veryquick.test` run now gets past the prior RTree coordinate failures. |
| Fixed | Parser constant folding for `sizeof` of known object arrays in array bounds | `moon test parser --target native --filter 'parse array bound using sizeof global array'`; `moon test test/e2e --target native --filter 'e2e local array bound uses sizeof global array'` | Public `avtrans.test` corruption minimized to SQLite pager's `u8 zHeader[sizeof(aJournalMagic)+4]`. During parsing, `sizeof(aJournalMagic)` in the local array bound fell back to `sizeof(int)`, so kimicc allocated an 8-byte buffer instead of 12 bytes and failed to overwrite the journal header `nRec` field. The parser now tracks known object types while parsing globals, parameters, and local declarations, so `sizeof` in constant array bounds sees the declared array type. |
| Passed | Public SQLite Tcl `avtrans.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/test/avtrans.test` from an isolated temporary working directory after relinking `/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture now passes `avtrans.test`: 0 errors out of 315 tests. The matching clang-linked testfixture also passes 0/315. A fresh `veryquick.test` run now gets past `avtrans` and reaches later failures. |
| Fixed | `va_arg(ap, int)` sign extension when widened to 64 bits | `moon test test/e2e --target native --filter 'e2e va_arg signed int sign-extends into long long'` | Public `decimal.test` failed at `decimal-6100`: SQLite's formatter assigned `va_arg(ap,int)` to an `i64`, producing `4294966222` for `-1074`. kimicc loaded signed 32-bit varargs with `ldr w9`, which zero-extended before the value was widened. `va_arg` now sign-extends `int` results at the read site while keeping `unsigned int` zero-extended. |
| Passed | Public SQLite Tcl `decimal.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/test/decimal.test` from an isolated temporary working directory after relinking `/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture now passes `decimal.test`: 0 errors out of 35 tests. |
| Fixed | C-style cast around string pointers in static aggregate initializers | `moon test test/e2e --target native --filter 'e2e static local pointer array initializes cast string'` | Public `func.test` crashed at `func-22.4` (`SELECT trim('  hi  ');`). The reduced SQLite code was `static unsigned char * const azOne[] = { (u8*)" " };`: the cast-wrapped string literal fell through global initializer emission and produced a null pointer, so `trimFunc()` called `memcmp()` with `azChar[0] == NULL`. Casted scalar initializers now emit through the underlying expression, preserving pointer-to-string relocations. |
| Blocked | Public SQLite Tcl `func.test` residual failures | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/test/func.test`; same command with `testfixture-clang` | The kimicc-built and clang-built fixtures both finish `func.test` with the same 9 `Inf` versus `inf` casing failures and no crash. Treat these as Tcl/platform expectation noise unless a later comparison shows a kimicc-only behavior difference. |
| Fixed | Call result typing for function pointers returning floating point | `moon test test/e2e --target native --filter 'e2e direct double return is read from fp register'`; `moon test test/e2e --target native --filter 'e2e function pointer double return is read from fp register'` | Public `func7.test` math-function failures minimized to SQLite calling local function-pointer variables such as `double (*x)(double)` and then storing the result as `double`. kimicc moved the `d0` result into `x9`, but `type_of(Call(fp,...))` still fell back to `int`, so callers converted raw double bits as an integer before storing or comparing. Call return type lookup now uses the callee expression type, including local `FuncPtr` variables, for both result register selection and expression typing. |
| Passed | Public SQLite Tcl `func7.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/test/func7.test` after relinking `/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture now passes `func7.test`: 0 errors out of 73 tests. In the next broad `veryquick.test` run, all `func7-*` math-function checks are `Ok`. |
| Fixed | Parser constant folding for `sizeof` of struct member arrays in local array bounds | `moon test test/e2e --target native --filter 'e2e local array bound uses sizeof struct pointer array field'` | Public `incrcorrupt.test` failures minimized to SQLite pager's `char dbFileVers[sizeof(pPager->dbFileVers)]`. During parsing, `sizeof(pPager->dbFileVers)` fell back to `sizeof(int)`, so kimicc read and compared only the first 4 bytes of SQLite's 16-byte database-file version snapshot. The parser now resolves member-access expression types through the known struct layout, preserving array field sizes in constant array bounds. |
| Passed | Public SQLite Tcl `incrcorrupt.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/test/incrcorrupt.test` from an isolated temporary working directory after relinking `/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture now passes `incrcorrupt.test`: 0 errors out of 36 tests. The reduced C repro now matches clang: after a file-header version edit, `PRAGMA freelist_count` sees 25 and `PRAGMA incremental_vacuum` returns `SQLITE_CORRUPT`. |
| Blocked | Public SQLite Tcl `types3.test` residual failure | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/test/types3.test`; same command with `testfixture-clang` | Both kimicc-built and clang-built fixtures fail only `types3-1.1` on this machine: expected `text`, got `string text`. Treat this as Tcl/platform expectation noise unless a later comparison shows a kimicc-only behavior difference. |
| Fixed | UInt32 arithmetic result wrapping in nested expressions | `moon test test/e2e --target native --filter 'e2e sqlite-style unsigned int overflow chain count'` | Public `corruptI.test` minimized to SQLite's overflow-page count expression `(pInfo->nPayload - pInfo->nLocal + ovflPageSize - 1)/ovflPageSize`, where `nPayload` is `0xffffffffu`. C requires each `unsigned int` arithmetic result to wrap at 32 bits before the next nested operation; kimicc kept the intermediate in 64 bits and computed millions of overflow pages. Integer arithmetic operations now normalize non-pointer results to their computed scalar type, and shifts use the promoted left operand type for their result. |
| Passed | Public SQLite Tcl `corruptI.test` | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/test/corruptI.test` from an isolated temporary working directory after relinking `/tmp/kimicc_sqlite3_testfixture.o` | The kimicc-built SQLite testfixture now passes `corruptI.test`: 0 errors out of 24 tests. The reduced C repro also matches clang: after patching the oversized payload varint, `DELETE FROM t1 WHERE rowid=2` returns `SQLITE_OK`. |
| Fixed | Struct compound literals with designated union fields | `moon test parser --target native --filter 'parse struct compound literal assignment'`; `moon test test/e2e --target native --filter 'e2e compound literal struct assignment after void call'` | A QuickJS 2025-09-13 smoke exposed `rt->current_exception = JS_UNINITIALIZED`: kimicc skipped `(JSValue){ ... }` compound literals as `0`, so aggregate assignment copied from the stale return register of the previous `void` call. Compound literals are now explicit AST nodes, support nested field designators such as `.u.float64`, allocate hidden stack storage through the existing local replay model, and initialize struct/union/array aggregate literals before copying. |
| Fixed | Unsigned switch dispatch with negative case labels | `moon test test/e2e --target native --filter 'e2e unsigned int switch matches negative case bits'` | QuickJS minimized this at `uint32_t tag = JS_VALUE_GET_TAG(v); switch(tag) { case JS_TAG_STRING: ... }`: the value was zero-extended to `0xfffffff9`, but kimicc compared it with a 64-bit `-7`, skipped the string case, and reached `default: abort()`. Switch dispatch now uses the promoted control-expression type and compares 32-bit integer switches through `w` registers. |
| Fixed | Darwin small aggregate ABI for 16-byte `JSValue`-style structs | `moon test test/e2e --target native --filter 'e2e sixteen byte struct return assign and pass by value'` | QuickJS passes and returns `JSValue` as a two-word struct. kimicc now handles small struct/union call results, aggregate assignments from calls, aggregate local initializers from calls, aggregate casts, and by-value aggregate call arguments with the Darwin ARM64 register convention for aggregates up to 16 bytes. |
| Fixed | Mixed-type bit-field allocation units | `moon test test/e2e --target native --filter 'e2e mixed bitfield layout matches quickjs object header'` | QuickJS's `JSGCObjectHeader` mixes enum and `uint8_t` bit-fields before byte and pointer fields. kimicc previously rounded the header to 32 bytes instead of clang's 24 bytes, shifting every following `JSObject` field. Parser and codegen layout now share a bit offset while compatible bit-fields continue the current allocation unit, matching clang for the reduced header layout and byte packing. |
| Fixed | Global designated union initializers | `moon test test/e2e --target native --filter 'e2e global designated union initializer in function list table'` | QuickJS function-list tables use entries such as `.u = { .alias = { "values", -1 } }`. kimicc skipped nested field designators in global aggregate initializers, zeroing alias payloads and crashing in `find_atom`. Global struct/union emission now finds matching field designators, emits the selected union arm, and pads the rest of the aggregate. |
| Fixed | Width-correct integer comparisons after usual conversions | `moon test test/e2e --target native --filter 'e2e unsigned int comparison matches negative constant bits'`; `moon test test/e2e --target native --filter 'e2e unsigned int compares as signed long when promoted'` | QuickJS tests `uint32_t tag != JS_TAG_OBJECT` where `JS_TAG_OBJECT` is `-1`. kimicc zero-extended the 32-bit tag and compared it with 64-bit `-1`, sending valid objects down the primitive fallback path. Integer common-type selection now follows the LP64 usual arithmetic conversion rule for unsigned-vs-signed ranks, and integer comparisons use `w` registers when the converted comparison type is 32-bit. |
| Fixed | Global array designators and range designators | `moon test test/e2e --target native --filter 'e2e global array designators emit class table entries'` | QuickJS's `func_kind_to_class_id[]` uses C99 array designators like `[JS_FUNC_NORMAL] = JS_CLASS_BYTECODE_FUNCTION`. kimicc skipped array designators, emitted an empty label, and read the following `_opcode_info` bytes as class IDs. The parser now preserves `DesignatedIndex` and `DesignatedRange`, infers unsized array length from the highest designated element, and global/local array initializer lowering writes holes as zero padding. |
| Fixed | Member access on small aggregate call results | `moon test test/e2e --target native --filter 'e2e member access reads field from struct call result'` | QuickJS's cleanup crash minimized to `JS_VALUE_GET_OBJ(JS_DupValue(ctx, getter))`, which preprocesses to member access through a 16-byte `JSValue` returned in registers. kimicc treated the first return word as an address and loaded the JS object header, storing values such as `0x000c010000000002` into getter/setter pointer slots. Member-access codegen now materializes register-returned struct/union values before selecting nested fields. |
| Passed | QuickJS reduced embed smoke | `/tmp/kimicc_quickjs_smoke/run_emscripten_noatomics/embed_smoke`, built from QuickJS 2025-09-13 with atomics/stack-check disabled and support files compiled by clang | The smoke preprocesses, compiles, assembles, links, evaluates `let x = 1 + 2; x`, prints `3`, frees the context/runtime, and exits with status `0`. Normal macOS QuickJS preprocessing still leaves compiler builtins such as fortified `snprintf`, C11 atomics, and `__builtin_frame_address`, so full unmodified QuickJS needs either builtin lowering or a sanitized preprocessor profile. |
| Open | SQLite `veryquick.test` post-`corruptI` frontier | `./testfixture /tmp/kimicc_sqlite_src_3049001/sqlite-src-3049001/test/veryquick.test` after relinking `/tmp/kimicc_sqlite3_testfixture.o`; output at `/tmp/kimicc_veryquick_after_uintwrapfix.out` | The current broad run completes with `rc=1`: 38 errors out of 392295 tests. The previous `corruptI-6.1` failure is gone. The remaining failures are currently classified as harness/platform noise: Tcl 8.5 `binary decode` failures (`fts5contentless3`, `fts3corrupt4`), `Inf` versus `inf` casing (`func`, `json101`, `json501`, `literal`), and the clang-matching `types3-1.1` Tcl expectation issue. No kimicc-only cluster is currently known in `veryquick.test`. |

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
