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
- Open an in-memory database and use basic APIs.
- Prepare and step a simple `select 1`.
- Create a table, insert rows, and read them back.
- Use bound statements, update rows, aggregate with `count`/`sum`, and verify
  `sqlite3_changes`.
- Run a deterministic SQL script through both clang-built SQLite and
  kimicc-built SQLite, then require identical output. This currently covers
  indexes, constraints, transactions, `insert ... select`, updates, ordered
  selects, and aggregate queries.

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
- [ ] Add a public SQLite Tcl `testfixture` harness mode.
- [ ] Run the first upstream public Tcl batch through the `testfixture` harness.
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
| Open | Public SQLite Tcl tests | Not wired yet | Next task is building a `testfixture` mode that can link kimicc's SQLite object. |

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
