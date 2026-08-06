///|
/// Scoping for `struct` and `union` tags.
///
/// C gives tags block scope, so two functions may each define their own
/// `struct L` and mean different types. Everything downstream of the parser --
/// MIR, both code generators -- identifies an aggregate by its name alone, and
/// the parser kept one flat table, so the second definition simply overwrote the
/// first and `sizeof(struct L)` in the earlier function reported the later
/// layout.
///
/// The fix has two halves, because visibility and identity are different
/// problems:
///
/// - **Visibility** is lexical. `tag_aliases` maps a written tag to the
///   definition currently in view, and is saved and restored around every block,
///   the way `value_types` already is.
/// - **Identity** is global. A block-scoped tag that reuses a name already taken
///   anywhere in the translation unit is registered under a fresh one, so the
///   two definitions stay distinct in `Program.structs`.
///
/// Renaming only fires on an actual collision, so ordinary programs keep the
/// tags they were written with.

///|
/// Records that `name` is now taken, so a later block-scoped definition of the
/// same tag is given a distinct one.
fn Parser::reserve_tag(self : Parser, name : String) -> Unit {
  self.used_tag_names[name] = true
}

///|
/// Returns the name to register a tag definition under.
///
/// At file scope the written name is used: C permits only one definition of a
/// tag there, so there is nothing to disambiguate. Inside a block, a name that
/// is already taken anywhere in the translation unit gets a fresh one, and the
/// written name is bound to it for the rest of the block.
fn Parser::define_tag(self : Parser, name : String) -> String {
  if self.block_depth == 0 || !self.used_tag_names.contains(name) {
    self.reserve_tag(name)
    if self.block_depth > 0 {
      self.tag_aliases[name] = name
    }
    return name
  }
  let mut suffix = 2
  let mut candidate = name + "__" + suffix.to_string()
  while self.used_tag_names.contains(candidate) {
    suffix += 1
    candidate = name + "__" + suffix.to_string()
  }
  self.reserve_tag(candidate)
  self.tag_aliases[name] = candidate
  candidate
}

///|
/// Resolves a written tag to the definition currently in view.
///
/// A tag with no binding resolves to itself, which covers file-scope tags and
/// forward references to one not yet defined.
fn Parser::resolve_tag(self : Parser, name : String) -> String {
  if self.tag_aliases.contains(name) {
    self.tag_aliases[name]
  } else {
    name
  }
}

///|
/// Enters a block, returning the tag bindings to restore when it ends.
fn Parser::enter_tag_scope(self : Parser) -> Map[String, String] {
  self.block_depth += 1
  self.tag_aliases.copy()
}

///|
/// Leaves a block, restoring the tag bindings that were in view outside it.
fn Parser::exit_tag_scope(self : Parser, saved : Map[String, String]) -> Unit {
  self.block_depth -= 1
  self.tag_aliases = saved
}
