///|
/// Compilation target supported by kimicc.
pub(all) enum Target {
  DarwinArm64
  LinuxAmd64
} derive(Eq)

///|
pub fn Target::default() -> Target {
  DarwinArm64
}

///|
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
pub fn Target::triple(self : Target) -> String {
  match self {
    DarwinArm64 => "arm64-apple-darwin"
    LinuxAmd64 => "x86_64-linux-gnu"
  }
}

///|
pub fn Target::name(self : Target) -> String {
  match self {
    DarwinArm64 => "darwin-arm64"
    LinuxAmd64 => "linux-amd64"
  }
}

///|
pub fn Target::object_format(self : Target) -> String {
  match self {
    DarwinArm64 => "Mach-O"
    LinuxAmd64 => "ELF64"
  }
}

///|
pub fn Target::symbol_prefix(self : Target) -> String {
  match self {
    DarwinArm64 => "_"
    LinuxAmd64 => ""
  }
}
