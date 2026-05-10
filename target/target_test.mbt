///|
test "parse target aliases" {
  match @target.Target::parse("darwin-arm64") {
    Some(target) => assert_eq(target.name(), "darwin-arm64")
    None => abort("darwin target did not parse")
  }
  match @target.Target::parse("arm64-apple-darwin") {
    Some(target) => assert_eq(target.name(), "darwin-arm64")
    None => abort("darwin alias did not parse")
  }
  match @target.Target::parse("linux-amd64") {
    Some(target) => assert_eq(target.name(), "linux-amd64")
    None => abort("linux target did not parse")
  }
  match @target.Target::parse("x86_64-linux-gnu") {
    Some(target) => assert_eq(target.name(), "linux-amd64")
    None => abort("linux alias did not parse")
  }
  match @target.Target::parse("x86_64-pc-linux-gnu") {
    Some(target) => assert_eq(target.name(), "linux-amd64")
    None => abort("linux pc alias did not parse")
  }
  match @target.Target::parse("x86_64-unknown-linux-musl") {
    Some(target) => assert_eq(target.name(), "linux-amd64")
    None => abort("linux musl alias did not parse")
  }
  assert_true(@target.Target::parse("unknown") is None)
}

///|
test "target metadata" {
  let linux = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("linux target did not parse")
  }
  assert_eq(@target.Target::default().name(), "darwin-arm64")
  assert_eq(linux.triple(), "x86_64-linux-gnu")
  assert_eq(linux.object_format(), "ELF64")
  assert_eq(@target.Target::default().symbol_prefix(), "_")
  assert_eq(linux.symbol_prefix(), "")
}
