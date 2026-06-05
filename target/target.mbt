///|
/// Compilation target supported by kimicc.
pub(all) enum Target {
  DarwinArm64
  LinuxAmd64
} derive(Eq)

///|
/// Returns the default compilation target, `DarwinArm64`.
///
/// kimicc's primary host is native ARM64 macOS, so the driver and code
/// generator fall back to this target whenever no explicit `-target` option is
/// supplied.
///
/// # Example
///
/// ```moonbit check
/// test {
///   inspect(@target.Target::default().name(), content="darwin-arm64")
/// }
/// ```
pub fn Target::default() -> Target {
  DarwinArm64
}

///|
/// Parses a target name or LLVM-style target triple into a `Target`.
///
/// The match is exact and case-sensitive. Both kimicc's short names
/// (`"darwin-arm64"`, `"linux-amd64"`), the Docker-style `"linux/amd64"`
/// alias, and several common platform triples are accepted. Unknown spellings
/// return `None` so the caller can report an unsupported target.
///
/// Parameters:
///
/// - `text`: the target name or triple to parse.
///
/// Returns `Some(target)` for a recognized spelling, or `None` otherwise.
///
/// # Example
///
/// ```moonbit check
/// test {
///   let linux = @target.Target::parse("linux-amd64").unwrap()
///   inspect(linux.name(), content="linux-amd64")
///   inspect(
///     @target.Target::parse("linux/amd64").unwrap() == linux,
///     content="true",
///   )
///   inspect(
///     @target.Target::parse("aarch64-apple-darwin").unwrap().name(),
///     content="darwin-arm64",
///   )
///   inspect(@target.Target::parse("riscv64") is None, content="true")
/// }
/// ```
pub fn Target::parse(text : String) -> Target? {
  match text {
    "darwin-arm64"
    | "arm64-apple-darwin"
    | "aarch64-apple-darwin"
    | "aarch64-apple-macos"
    | "arm64-apple-macos" => Some(DarwinArm64)
    "linux-amd64"
    | "linux/amd64"
    | "linux-x86_64"
    | "linux/x86_64"
    | "x86_64-linux-gnu"
    | "x86_64-pc-linux-gnu"
    | "x86_64-redhat-linux"
    | "x86_64-unknown-linux-gnu"
    | "x86_64-linux-musl"
    | "x86_64-unknown-linux-musl"
    | "amd64-linux-gnu"
    | "amd64-unknown-linux-gnu" => Some(LinuxAmd64)
    _ => None
  }
}

///|
/// Returns the canonical LLVM-style target triple for this target.
///
/// This is the spelling kimicc forwards to Clang (for example via
/// `-print-target-triple`), not necessarily one of the aliases accepted by
/// `parse`. `DarwinArm64` maps to `"arm64-apple-darwin"` and `LinuxAmd64` to
/// `"x86_64-linux-gnu"`.
///
/// # Example
///
/// ```moonbit check
/// test {
///   inspect(@target.Target::default().triple(), content="arm64-apple-darwin")
///   inspect(
///     @target.Target::parse("linux-amd64").unwrap().triple(),
///     content="x86_64-linux-gnu",
///   )
/// }
/// ```
pub fn Target::triple(self : Target) -> String {
  match self {
    DarwinArm64 => "arm64-apple-darwin"
    LinuxAmd64 => "x86_64-linux-gnu"
  }
}

///|
/// Returns kimicc's short canonical name for this target.
///
/// The result is the spelling used in driver options and diagnostics
/// (`"darwin-arm64"` or `"linux-amd64"`), and it round-trips through `parse`.
///
/// # Example
///
/// ```moonbit check
/// test {
///   let name = @target.Target::default().name()
///   inspect(name, content="darwin-arm64")
///   inspect(
///     @target.Target::parse(name).unwrap() == @target.Target::default(),
///     content="true",
///   )
/// }
/// ```
pub fn Target::name(self : Target) -> String {
  match self {
    DarwinArm64 => "darwin-arm64"
    LinuxAmd64 => "linux-amd64"
  }
}

///|
/// Returns the name of the relocatable object format used by this target.
///
/// `DarwinArm64` emits Mach-O objects (see
/// `@codegen.generate_macho_object`), while `LinuxAmd64` emits `ELF64`. This
/// is descriptive metadata; it does not itself produce object bytes.
///
/// # Example
///
/// ```moonbit check
/// test {
///   inspect(@target.Target::default().object_format(), content="Mach-O")
///   inspect(
///     @target.Target::parse("linux-amd64").unwrap().object_format(),
///     content="ELF64",
///   )
/// }
/// ```
pub fn Target::object_format(self : Target) -> String {
  match self {
    DarwinArm64 => "Mach-O"
    LinuxAmd64 => "ELF64"
  }
}

///|
/// Returns the assembler symbol prefix applied to C identifiers on this target.
///
/// Darwin prepends a leading underscore to C symbols (so `main` becomes
/// `_main`), while the System V ELF convention on Linux uses no prefix. Code
/// generators use this when mangling C function and global names into assembly
/// labels.
///
/// # Example
///
/// ```moonbit check
/// test {
///   inspect(@target.Target::default().symbol_prefix(), content="_")
///   inspect(
///     @target.Target::parse("linux-amd64").unwrap().symbol_prefix(),
///     content="",
///   )
/// }
/// ```
pub fn Target::symbol_prefix(self : Target) -> String {
  match self {
    DarwinArm64 => "_"
    LinuxAmd64 => ""
  }
}
