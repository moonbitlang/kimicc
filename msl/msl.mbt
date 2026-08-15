///|
/// Metal Shading Language emission as a dialect layer over the C toolkit.
///
/// MSL kernel bodies are C; what MSL adds to a kernel's surface is a
/// function qualifier (`kernel`), address-space qualifiers on parameters
/// (`device`, `constant`, `threadgroup`), and bracketed attributes
/// (`[[thread_position_in_grid]]`, `[[buffer(0)]]`). This package models
/// exactly that split: a `Kernel` wraps an ordinary `@parser.FuncDecl`
/// whose body prints through the C printer, plus per-parameter
/// decoration strings the C AST never sees. cfront's round-trip contract
/// stays untouched -- a decorated signature is not C, so it lives here.
///
/// The parser half is a decoration bridge, not a grammar: `parse_kernel`
/// strips the qualifier, address spaces, and `[[...]]` attributes out of
/// the signature lexically, hands the remaining plain-C function to
/// cfront's parser (seeded with the caller's named types), and reattaches
/// what it stripped. For kernels this package printed, the round trip is
/// exact -- `parse_kernel(print_kernel(k)) == k` -- which restores the
/// same print/parse discipline the C side runs under quickcheck.
///
/// Reference parameters are supported, because every real MSL kernel
/// takes its uniform block that way (`constant Args &args`) and a
/// drop-in must match the signature the host binds against. `&` is a
/// decoration for the same reason an address space is: C has no such
/// declarator, so it never enters the C AST.
///
/// Phase-1 limits, deliberate: no templates, no `constexpr`/`auto`
/// (generated kernels are concrete-typed by thesis), no rvalue
/// references or references to pointers, and attributes may not appear
/// inside bodies. Parsing ds4's own hand-written shaders needs those and
/// is a later, separately-sized phase.
pub(all) struct ParamDecor {
  /// Address-space and qualifier prefix printed before the C type:
  /// "device", "device const", "constant", "threadgroup". Empty for a
  /// plain value parameter.
  space : String
  /// Bracketed attribute printed after the parameter name:
  /// "[[thread_position_in_grid]]", "[[buffer(0)]]". Empty for none.
  attr : String
  /// A C++ reference parameter -- `constant Args &args`, the idiom every
  /// real MSL kernel uses for its uniform block. Reference-ness is a
  /// decoration for the same reason an address space is: C has no such
  /// declarator, so it never enters the C AST.
  by_ref : Bool
} derive(Eq, Debug)

///|
/// One MSL kernel: the qualifier, the C function underneath, and one
/// decoration per parameter (the arrays run parallel; `print_kernel`
/// aborts on a length mismatch rather than misattributing bindings).
pub(all) struct Kernel {
  /// Function qualifier; phase 1 accepts exactly "kernel" -- vertex and
  /// fragment stages return values and carry stage-specific attributes
  /// this package does not model yet.
  qualifier : String
  decl : @parser.FuncDecl
  decor : Array[ParamDecor]
} derive(Eq, Debug)

///|
/// A parameter with no MSL decoration.
pub fn plain() -> ParamDecor {
  { space: "", attr: "", by_ref: false }
}

///|
/// A decorated parameter: `decor("device const")`,
/// `decor("", attr="[[thread_position_in_grid]]")`.
pub fn decor(
  space : String,
  attr? : String = "",
  by_ref? : Bool = false,
) -> ParamDecor {
  { space, attr, by_ref }
}

///|
/// The declaration shapes a `Kernel` can carry faithfully: a Compound
/// body and no metadata the decorated signature does not spell.
/// `print_kernel` aborts on a violation (a construction error);
/// `parse_kernel` raises it (malformed input), so a successful parse
/// always yields a printable kernel and the round trip stays exact.
fn kernel_shape_violation(decl : @parser.FuncDecl) -> String? {
  match decl.body {
    None => return Some("a kernel needs a body, not a prototype")
    Some(Compound(_)) => ()
    Some(_) =>
      return Some("the body must be a Compound block (build.func produces one)")
  }
  if decl.variadic {
    return Some("variadic kernels are not printable")
  }
  if decl.is_static || decl.is_inline || decl.is_weak {
    return Some("storage-class flags are not part of a kernel signature")
  }
  if decl.visibility is Some(_) ||
    decl.symbol_alias is Some(_) ||
    decl.section is Some(_) {
    return Some("symbol attributes are not part of a kernel signature")
  }
  if decl.is_constructor || decl.is_destructor {
    return Some("constructor/destructor flags are not printable")
  }
  // MSL compute kernels return void; enforcing it also closes the whole
  // class of return declarators (`int (*)(int)`) whose abstract spelling
  // cannot carry the function name.
  if decl.ret != Void {
    return Some("a kernel returns void")
  }
  // Parameters are the shapes real MSL kernels take and nothing more:
  // a value of scalar/Named/aggregate type, or a pointer chain ending
  // in one. Arrays (decay), `void` (normalizes away), function pointers
  // (banned in MSL device code), and `_Atomic`/`_Alignas` wrappers
  // (spelled differently in MSL, and their C spellings do not
  // round-trip through declarators) are all rejected -- closing every
  // silent-retype declarator in one rule instead of chasing them
  // lexically.
  for param in decl.params {
    if !msl_param_type_ok(param.ty) {
      return Some(
        "parameter `" +
        param.name +
        "` is not a value or pointer-chain type the MSL subset carries",
      )
    }
    if param.bit_width is Some(_) {
      return Some("parameters cannot carry bitfield widths")
    }
  }
  None
}

///|
/// Decoration strings are stored in the spelling the bridge reproduces:
/// no leading/trailing whitespace and single spaces between words.
fn valid_attr_text(attr : String) -> Bool {
  if attr == "" {
    return true
  }
  if !attr.has_prefix("[[") || !attr.has_suffix("]]") || attr.length() < 4 {
    return false
  }
  // Exactly one balanced group: the interior carries no brackets and
  // its parentheses balance, or the reparse would misread the
  // signature's own structure.
  let interior = attr[2:attr.length() - 2].to_owned()
  if interior.find("[") is Some(_) || interior.find("]") is Some(_) {
    return false
  }
  // An attribute payload is a compact token, so its contents are
  // whitelisted rather than blacklisted character by character: comments
  // and string literals are collapsed by parameter normalization, and a
  // reparse would then differ from what was printed. The permitted set
  // is what ds4's 22,851 lines of MSL actually use -- identifier
  // characters plus space, parentheses and `+` (as in
  // `[[function_constant(FC_MUL_MV + 0)]]`) -- widened with `,` and `-`
  // for constant expressions.
  for c in interior {
    if !is_ident_char(c) &&
      c != ' ' &&
      c != '(' &&
      c != ')' &&
      c != '+' &&
      c != '-' &&
      c != ',' {
      return false
    }
  }
  let mut depth = 0
  for c in interior {
    if c == '(' {
      depth = depth + 1
    } else if c == ')' {
      depth = depth - 1
      if depth < 0 {
        return false
      }
    }
  }
  depth == 0
}

///|
fn canonical_decor_text(text : String) -> Bool {
  if text == "" {
    return true
  }
  if text.trim().to_owned() != text {
    return false
  }
  text.find("  ") is None && text.find("\t") is None && text.find("\n") is None
}

///|
/// The address-space prefix vocabulary is closed over what the bridge
/// strips: any other word -- `volatile`, say -- would survive printing
/// but vanish through the C reparse, silently changing the kernel.
fn valid_space_prefix(space : String) -> Bool {
  if space == "" {
    return true
  }
  let words = space.split(" ").collect()
  if words.length() == 0 {
    return false
  }
  if words[0] == "const" {
    // The bridge leaves a leading `const` in the C core, so a prefix
    // starting with it could never come back as a decoration.
    return false
  }
  for w in words {
    if w != "device" &&
      w != "constant" &&
      w != "threadgroup" &&
      w != "thread" &&
      w != "const" {
      return false
    }
  }
  true
}

///|
/// Rules that need a parameter and its decoration together, so the
/// printer and the bridge enforce exactly the same ones: a successful
/// parse must always be printable, and a printable kernel must always
/// parse back.
fn decor_pairing_violation(
  decl : @parser.FuncDecl,
  decor : Array[ParamDecor],
) -> String? {
  if decl.params.length() != decor.length() {
    return Some(
      decl.name +
      " has " +
      decl.params.length().to_string() +
      " parameters but " +
      decor.length().to_string() +
      " decorations",
    )
  }
  for i in 0..<decl.params.length() {
    let param = decl.params[i]
    // MSL references bind to values of any type -- `constant Args &args`
    // for a uniform block, `constant float &scale` for a scalar. The one
    // shape that cannot round-trip is a reference to a pointer, which
    // prints `T *&x` and has no unambiguous way back.
    if decor[i].by_ref && param.ty is Pointer(_) {
      return Some("parameter `" + param.name + "` is a reference to a pointer")
    }
    // An unnamed reference is legal C++ and unusable in a kernel: the
    // body has nothing to call it. Refusing it keeps the abstract
    // declarator `constant Args &` out of the printer, which the bridge
    // would then have no name to recover.
    if decor[i].by_ref && param.name == "" {
      return Some("an unnamed parameter cannot be a reference")
    }
  }
  None
}

///|
/// Value scalars, named types, aggregates, and pointer chains to them.
fn msl_param_type_ok(ty : @ctype.Type) -> Bool {
  match ty {
    // `void *` is opaque device or threadgroup memory, a real MSL
    // parameter; a bare `void` value is not.
    Pointer(Void) => true
    Pointer(inner) => msl_param_type_ok(inner)
    Void | Array(_, _) | FuncPtr(_, _, _) | Atomic(_) | Aligned(_, _) => false
    // MSL's scalar set: no double, no long double, no 128-bit ints,
    // and no `long long` spelling (`long` is already 64-bit there).
    Double
    | LongDouble
    | Float128
    | SInt128
    | UInt128
    | SLongLong
    | ULongLong => false
    _ => true
  }
}

///|
/// Prints one kernel: a single-line decorated signature, then the body
/// through the C printer. Single-line signatures are the canonical form
/// here for the same reason the C printer picks one spelling everywhere:
/// the parse half must reproduce the exact text.
pub fn print_kernel(k : Kernel) -> String {
  match decor_pairing_violation(k.decl, k.decor) {
    Some(msg) => abort("print_kernel: " + msg)
    None => ()
  }
  let parts : Array[String] = []
  for i in 0..<k.decl.params.length() {
    let param = k.decl.params[i]
    let d = k.decor[i]
    let mut text = if d.by_ref {
      @printer.print_declaration(param.ty, "&" + param.name)
    } else {
      @printer.print_declaration(param.ty, param.name)
    }
    if d.space != "" {
      text = d.space + " " + text
    }
    if d.attr != "" {
      text = text + " " + d.attr
    }
    parts.push(text)
  }
  for d in k.decor {
    if !valid_space_prefix(d.space) {
      abort(
        "print_kernel: `" +
        d.space +
        "` is outside the address-space vocabulary the bridge recovers",
      )
    }
    if !valid_attr_text(d.attr) {
      abort(
        "print_kernel: attribute `" +
        d.attr +
        "` is not one balanced [[...]] group",
      )
    }
    if !canonical_decor_text(d.space) || !canonical_decor_text(d.attr) {
      abort(
        "print_kernel: decoration `" +
        d.space +
        "`/`" +
        d.attr +
        "` is not single-space canonical",
      )
    }
  }
  if k.qualifier != "kernel" {
    abort(
      "print_kernel: `" +
      k.qualifier +
      "` is not a qualifier this package prints",
    )
  }
  match kernel_shape_violation(k.decl) {
    Some(msg) => abort("print_kernel: " + k.decl.name + ": " + msg)
    None => ()
  }
  let body = match k.decl.body {
    Some(stmt) => @printer.print_stmt(stmt)
    None => abort("unreachable: validated above")
  }
  k.qualifier +
  " " +
  @printer.print_type(k.decl.ret) +
  " " +
  k.decl.name +
  "(" +
  parts.join(", ") +
  ") " +
  body
}

///|
/// Prints a translation unit of kernels with an optional prelude (the
/// place for `#include <metal_stdlib>` when a kernel needs library
/// functions; the scalar and vector types themselves are MSL builtins).
pub fn print_kernels(kernels : Array[Kernel], prelude? : String = "") -> String {
  let parts : Array[String] = []
  if prelude != "" {
    parts.push(prelude)
  }
  for k in kernels {
    parts.push(print_kernel(k))
  }
  parts.join("\n\n") + "\n"
}

///|
/// The address-space words the bridge strips from a parameter head.
/// `const` rides along so "device const" survives as one prefix.
let space_words : Array[String] = [
  "device", "constant", "threadgroup", "thread", "const",
]

///|
fn is_ident_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// Collapses whitespace in a parameter's text and returns the collapsed
/// text alongside a comment-and-literal-blanked copy of itself, built in
/// the same pass so an index found in one slices the other.
///
/// Blanking has to happen before collapsing: a line comment ends at its
/// newline, so collapsing newlines first would let `// note` run on and
/// swallow whatever followed. Comment bodies collapse to a single space
/// in both outputs, which the C parser is indifferent to and the AST
/// records nothing of either way. Parameter declarators contain no
/// string literals, so literal contents never reach the collapse.
fn normalize_param(text : String) -> (String, String) {
  let blanked = blank_literals(text)
  let out_text = StringBuilder::new()
  let out_scan = StringBuilder::new()
  let mut last_space = true
  for i in 0..<blanked.length() {
    let b = blanked.get_char(i).unwrap_or(' ')
    let c = text.get_char(i).unwrap_or(' ')
    if b == ' ' || b == '\t' || b == '\n' || b == '\r' {
      if !last_space {
        out_text.write_char(' ')
        out_scan.write_char(' ')
      }
      last_space = true
    } else {
      out_text.write_char(c)
      out_scan.write_char(b)
      last_space = false
    }
  }
  let t = out_text.to_string()
  let sc = out_scan.to_string()
  // Both end in at most one collapsed space, so trimming keeps them the
  // same length.
  if t.has_suffix(" ") {
    (t[:t.length() - 1].to_owned(), sc[:sc.length() - 1].to_owned())
  } else {
    (t, sc)
  }
}

///|
/// Splits one parameter's text into (space-prefix, C core, attribute).
/// Malformed decoration -- an unterminated `[[` -- raises rather than
/// aborting: hand-written source is expected input for the bridge.
fn strip_param(text : String) -> (String, String, String, Bool) raise {
  // Blanking runs BEFORE whitespace normalization, not after: a line
  // comment is terminated by its newline, so collapsing newlines first
  // would let `& // note\n args` swallow the parameter name. The two
  // strings are then normalized in lockstep so an index found in the
  // scan slices the text.
  let (core_init, core_scan_init) = normalize_param(text)
  let mut core = core_init
  let mut core_scan = core_scan_init
  let mut attr = ""
  match core_scan.find("[[") {
    Some(start) =>
      // The terminator must follow the opener: a stray `]]` earlier in
      // the text would otherwise select a reversed slice and panic.
      match core_scan[start:].to_owned().find("]]") {
        Some(rel) => {
          let end_open = start + rel
          attr = core[start:end_open + 2].to_owned()
          core = core[:start].to_owned() + core[end_open + 2:].to_owned()
          core_scan = core_scan[:start].to_owned() +
            core_scan[end_open + 2:].to_owned()
        }
        None => raise NotAKernel("unterminated [[ in `" + text + "`")
      }
    None => ()
  }
  let spaces : Array[String] = []
  let mut rest = core
  let mut rest_scan = core_scan
  while true {
    let mut matched = false
    for w in space_words {
      if rest.has_prefix(w + " ") {
        // `const` alone is C and stays in the core; it joins the prefix
        // only after an address-space word has been seen.
        if w == "const" && spaces.length() == 0 {
          continue
        }
        spaces.push(w)
        // Both strings advance by the same count so indices stay aligned.
        rest = rest[w.length() + 1:].to_owned()
        rest_scan = rest_scan[w.length() + 1:].to_owned()
        matched = true
        break
      }
    }
    if !matched {
      break
    }
  }
  // The `&` of a reference parameter sits between the type and the name;
  // C has no such declarator, so it comes out here as a decoration and
  // the remaining text is ordinary C. Scanned on the blanked copy so a
  // `&` inside a comment stays text, and rejected when doubled (`&&`)
  // or combined with a pointer, neither of which the bridge reproduces.
  let mut by_ref = false
  match rest_scan.find("&") {
    Some(at) => {
      if rest_scan.find("&&") is Some(_) {
        raise NotAKernel("rvalue references are outside the MSL subset")
      }
      if rest_scan.find("*") is Some(_) {
        raise NotAKernel("references to pointers are outside the MSL subset")
      }
      // The `&` must sit in declarator position: a type before it, and
      // exactly the parameter name after. `&Args args` and `Args args&`
      // are not reference declarations, and stripping their ampersand
      // would silently turn malformed input into a valid kernel.
      let before = rest[:at].to_owned().trim().to_owned()
      let after = rest[at + 1:].to_owned().trim().to_owned()
      // The name is checked on the blanked suffix so a comment between
      // `&` and the name -- `Args & /* uniform */ args` -- does not read
      // as part of the identifier. The reassembled core keeps the
      // original text; cfront skips comments, and the AST records none,
      // so the round trip is unaffected.
      let after_blanked = rest_scan[at + 1:].to_owned().trim().to_owned()
      if before == "" || !is_identifier(after_blanked) {
        raise NotAKernel("`&` is not in reference-declarator position")
      }
      by_ref = true
      // A space, not nothing: the compact spelling `Args&args` would
      // otherwise concatenate into the single token `Argsargs`, which
      // the C parser reads as a different declaration entirely.
      rest = (before + " " + after).trim().to_owned()
    }
    None => ()
  }
  (spaces.join(" "), rest, attr, by_ref)
}

///|
/// Returns `text` with string and character literal contents blanked,
/// so token scans cannot trigger on quoted text.
fn blank_literals(text : String) -> String {
  let out = StringBuilder::new()
  fn blank(c : Char) {
    // A non-BMP character occupies two UTF-16 code units; its blank
    // must too, or every offset found in the scan text would drift
    // from the original it slices.
    if c.to_int() > 0xFFFF {
      out.write_string("  ")
    } else {
      out.write_char(' ')
    }
  }
  let mut in_string = false
  let mut in_char = false
  let mut escaped = false
  let mut in_block_comment = false
  let mut in_line_comment = false
  let mut pending_slash = false
  let mut prev : Char = ' '
  for c in text {
    if in_block_comment {
      if prev == '*' && c == '/' {
        in_block_comment = false
        prev = ' '
      } else {
        prev = c
      }
      blank(c)
      continue
    }
    if in_line_comment {
      if c == '\n' {
        in_line_comment = false
        out.write_char('\n')
      } else {
        blank(c)
      }
      continue
    }
    if pending_slash {
      pending_slash = false
      if !in_string && !in_char && (c == '*' || c == '/') {
        // A comment blanks whole, opener included: a leftover `/` would
        // corrupt any scan that expects a clean token, which is how the
        // reference-declarator check first saw one.
        if c == '*' {
          in_block_comment = true
        } else {
          in_line_comment = true
        }
        out.write_char(' ')
        blank(c)
        prev = ' '
        continue
      }
      out.write_char('/')
    }
    if !in_string && !in_char && c == '/' {
      // Held back one character: only the next one says whether this
      // opens a comment. Written on the next pass either way, so the
      // output stays code-unit aligned with the input.
      pending_slash = true
      prev = c
      continue
    }
    prev = c
    if escaped {
      escaped = false
      blank(c)
      continue
    }
    if in_string {
      if c == '\\' {
        escaped = true
        blank(c)
      } else if c == '"' {
        in_string = false
        out.write_char('"')
      } else {
        blank(c)
      }
      continue
    }
    if in_char {
      if c == '\\' {
        escaped = true
        blank(c)
      } else if c == '\'' {
        in_char = false
        out.write_char('\'')
      } else {
        blank(c)
      }
      continue
    }
    if c == '"' {
      in_string = true
    } else if c == '\'' {
      in_char = true
    }
    out.write_char(c)
  }
  if pending_slash {
    out.write_char('/')
  }
  out.to_string()
}

///|
/// True when `text` is exactly one C identifier.
fn is_identifier(text : String) -> Bool {
  if text == "" {
    return false
  }
  let first = text.get_char(0).unwrap_or(' ')
  if first >= '0' && first <= '9' {
    return false
  }
  for c in text {
    if !is_ident_char(c) {
      return false
    }
  }
  true
}

///|
/// Finds `word` in `text` at identifier boundaries.
fn find_word(text : String, word : String) -> Int? {
  let mut from = 0
  while from < text.length() {
    match text[from:].to_owned().find(word) {
      Some(rel) => {
        let at = from + rel
        let before_ok = at == 0 ||
          !is_ident_char(text.get_char(at - 1).unwrap_or(' '))
        let after = at + word.length()
        let after_ok = after >= text.length() ||
          !is_ident_char(text.get_char(after).unwrap_or(' '))
        if before_ok && after_ok {
          return Some(at)
        }
        from = at + 1
      }
      None => return None
    }
  }
  None
}

///|
/// Errors from the decoration bridge: the text was not a kernel this
/// package could have printed.
pub(all) suberror MslParseError {
  NotAKernel(String)
} derive(Debug)

///|
pub impl Show for MslParseError with fn to_string(self) {
  match self {
    NotAKernel(msg) => "not a printable kernel: " + msg
  }
}

///|
/// The decoration bridge: reads back a kernel this package printed.
/// Strips the qualifier and per-parameter decorations, parses the
/// remaining plain-C function with cfront (seeded with `named_types`,
/// e.g. ["uint"]), and reattaches the decorations. Exact for printed
/// kernels; hand-written MSL using references, templates, or body
/// attributes is out of scope and fails with a diagnostic.
pub fn parse_kernel(
  source : String,
  named_types : Array[String],
) -> Kernel raise {
  let text = source.trim().to_owned()
  // MSL `auto` is type inference; C `auto` is a storage class with
  // implicit int. Handing it to the C parser would silently retype the
  // declaration, so it is rejected as out of the phase-1 subset. The
  // scan blanks literals first: quoted `auto` is text, not a token.
  let keyword_scan = blank_literals(text)
  match find_word(keyword_scan, "auto") {
    Some(_) => raise NotAKernel("`auto` type inference is not supported")
    None => ()
  }
  // Template syntax must diagnose, not misread: `foo<4>(x)` would parse
  // as C comparisons. The emitted canonical form always spaces binary
  // operators, so a bare `>(` sequence only appears in template calls.
  match find_word(keyword_scan, "template") {
    Some(_) => raise NotAKernel("templates are not supported")
    None => ()
  }
  // Collapse whitespace so `foo<4> (x)` and `foo<4>\n(x)` are caught
  // by the same scan as `foo<4>(x)`.
  let collapsed = StringBuilder::new()
  let mut was_space = false
  for c in keyword_scan {
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      was_space = true
    } else {
      if was_space && c == '(' {
        // Only the `>(`-adjacency matters; drop the space before `(`.
        ()
      } else if was_space {
        collapsed.write_char(' ')
      }
      collapsed.write_char(c)
      was_space = false
    }
  }
  match collapsed.to_string().find(">(") {
    Some(_) =>
      raise NotAKernel(
        "`>(` reads as a template instantiation; templates are not supported",
      )
    None => ()
  }
  // The qualifier is the first identifier.
  let mut qend = 0
  while qend < text.length() &&
        is_ident_char(text.get_char(qend).unwrap_or(' ')) {
    qend = qend + 1
  }
  if qend == 0 {
    raise NotAKernel("no leading qualifier in `" + text + "`")
  }
  let qualifier = text[:qend].to_owned()
  // Only MSL stage qualifiers strip: anything else -- `static`,
  // `inline`, a return type -- is not a kernel this package printed,
  // and letting it through would bypass the shape validation below.
  if qualifier != "kernel" {
    raise NotAKernel("`" + qualifier + "` is not a supported stage qualifier")
  }
  let rest = text[qend:].trim().to_owned()
  // One blanked copy serves every structural scan below: comments and
  // literal contents become spaces (length-preserving, so indices found
  // here slice `rest` directly), and braces or commas inside them can
  // no longer derail the bracket matching.
  let scan = blank_literals(rest)
  // The signature's parameter list is the first balanced paren group.
  let open = match scan.find("(") {
    Some(i) => i
    None => raise NotAKernel("no parameter list")
  }
  let mut depth = 0
  let mut close = -1
  for i in open..<scan.length() {
    let c = scan.get_char(i).unwrap_or(' ')
    if c == '(' {
      depth = depth + 1
    } else if c == ')' {
      depth = depth - 1
      if depth == 0 {
        close = i
        break
      }
    }
  }
  if close < 0 {
    raise NotAKernel("unbalanced parameter list")
  }
  let head = rest[:open].to_owned()
  // The head is return type plus name, nothing else: a semicolon there
  // means a declaration cfront would consume and the reprint would drop.
  if scan[:open].to_owned().find(";") is Some(_) {
    raise NotAKernel("declarations before the kernel signature")
  }
  let params_text = rest[open + 1:close].to_owned()
  let params_scan = scan[open + 1:close].to_owned()
  let tail = rest[close + 1:].to_owned()
  let tail_scan = scan[close + 1:].to_owned()
  // Split parameters on top-level commas; attributes contain none of
  // the phase-1 forms with nested parens except `[[buffer(0)]]`, whose
  // parens the depth counter already balances.
  let params : Array[String] = []
  let mut start = 0
  depth = 0
  for i in 0..<params_scan.length() {
    let c = params_scan.get_char(i).unwrap_or(' ')
    if c == '(' || c == '[' {
      depth = depth + 1
    } else if c == ')' || c == ']' {
      depth = depth - 1
    } else if c == ',' && depth == 0 {
      params.push(params_text[start:i].to_owned())
      start = i + 1
    }
  }
  if params_text.trim() != "" {
    params.push(params_text[start:].to_owned())
  }
  let decor : Array[ParamDecor] = []
  let cores : Array[String] = []
  for idx in 0..<params.length() {
    let (space, core, attr, by_ref) = strip_param(params[idx])
    // The printer's own predicate guards the extraction: whatever the
    // bridge accepts, the printer can emit, or the parse fails here.
    if !valid_attr_text(attr) {
      raise NotAKernel("attribute `" + attr + "` is not one balanced group")
    }
    // No brackets survive in the subset's parameter declarators: an
    // outer array would decay silently, and pointer-to-array shapes are
    // not something an MSL kernel takes. One blunt rule, no declarator
    // lexing to get wrong. The scan is comment-blanked: a bracket in a
    // comment is text.
    if blank_literals(core).find("[") is Some(_) {
      raise NotAKernel("array declarators are outside the MSL subset")
    }
    decor.push({ space, attr, by_ref })
    cores.push(core)
  }
  // `(void)` is C's empty parameter list: cfront normalizes the pseudo-
  // parameter away, so its decoration must go with it -- decorated
  // `void` is meaningless and rejected rather than misattributed.
  if cores.length() == 1 && cores[0].trim() == "void" {
    if decor[0] != plain() {
      raise NotAKernel("a void parameter list cannot carry decorations")
    }
    decor.clear()
    cores.clear()
  }
  // Nothing may follow the kernel's closing brace: cfront consumes
  // typedefs and enums without recording them in the Program, so a
  // trailing declaration would silently vanish from the reprint. The
  // check is textual brace balancing, which phase-1 bodies cannot
  // confuse (no string literals containing braces are emitted).
  let body_open = match tail_scan.find("{") {
    Some(i) => i
    None => raise NotAKernel("no kernel body")
  }
  let mut brace_depth = 0
  let mut body_close = -1
  for i in body_open..<tail_scan.length() {
    let c = tail_scan.get_char(i).unwrap_or(' ')
    if c == '{' {
      brace_depth = brace_depth + 1
    } else if c == '}' {
      brace_depth = brace_depth - 1
      if brace_depth == 0 {
        body_close = i
        break
      }
    }
  }
  if body_close < 0 {
    raise NotAKernel("unbalanced kernel body")
  }
  if tail_scan[body_close + 1:].trim() != "" {
    raise NotAKernel("trailing declarations after the kernel body")
  }
  let c_source = head + "(" + cores.join(", ") + ")" + tail
  let program = @parser.parse_with_named_types(c_source, named_types)
  if program.decls.length() != 1 ||
    program.globals.length() != 0 ||
    program.structs.length() != 0 {
    raise NotAKernel(
      "expected exactly one function and nothing else; found " +
      program.decls.length().to_string() +
      " functions, " +
      program.globals.length().to_string() +
      " globals, " +
      program.structs.length().to_string() +
      " aggregates",
    )
  }
  let decl = program.decls[0]
  match kernel_shape_violation(decl) {
    Some(msg) => raise NotAKernel(msg)
    None => ()
  }
  // The same pairing rules the printer enforces: C normalization can drop
  // a parameter this bridge attributed (a named `void x`), and a
  // reference to a scalar parses as C but has no printable spelling.
  // Either way it is a parse failure, not a kernel that aborts later.
  match decor_pairing_violation(decl, decor) {
    Some(msg) => raise NotAKernel(msg)
    None => ()
  }
  { qualifier, decl, decor }
}
