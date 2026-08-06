# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- The toplevel directory holds a `moon.work` workspace manifest with two member
  modules, each with its own `moon.mod`:

  - `bobzhang/cfront` under `cfront/` is the reusable C front end: `target`,
    `ctype`, `preprocessor`, and `parser`. It must not depend on anything in
    `kimicc`, and builds and tests standalone.
  - `bobzhang/kimicc` at the root is the compiler: MIR, both code generators,
    the JIT, and the driver. It depends on `cfront`.

  Root `moon check`, `moon test`, `moon fmt`, and `moon info` cover both
  modules. Package paths on the command line are prefixed by the owning
  module, so the parser is `cfront/parser`, not `parser`.

## Target

**This project targets native ARM64 macOS.** Use `--target native` for all builds
and tests. The native target produces a `main.exe` binary (~20x faster than wasm-gc).

```bash
moon build --target native
moon test --target native
moon run cmd/main --target native -- "<source code>"
```

## Running the Compiler

The compiler reads C source code from command-line argument `args[1]`:

```bash
# Using moon run
moon run cmd/main --target native -- "$(cat input.c)" > out.s

# Using the native binary directly
_build/native/debug/build/bobzhang/kimicc/cmd/main/main.exe "$(cat input.c)" > out.s

# Link with clang
clang -o out out.s && ./out
```

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test --target native` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. Use snapshot tests to record current
  behavior. For solid, well-defined results (e.g. scientific computations),
  prefer assertion tests. You can use `moon coverage analyze > uncovered.log` to
  see which parts of your code are not covered by tests.
