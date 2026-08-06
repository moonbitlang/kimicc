///|
/// `#pragma pack(N)` caps field alignment, so an over-aligned member packs
/// tightly against the preceding one instead of getting padded out.
test "pragma pack caps field alignment" {
  let source =
    #|#pragma pack(4)
    #|struct S { char c; long long v; };
    #|#pragma pack()
    #|struct T { char c; long long v; };
    #|int main(void) { return sizeof(struct S) * 100 + sizeof(struct T); }
  let prog = @parser.parse(source)
  debug_inspect(prog.structs[0].pack, content="Some(4)")
  debug_inspect(prog.structs[1].pack, content="None")
}

///|
/// `push`/`pop` nest, and `pop` restores the cap that was in effect before the
/// matching `push` rather than clearing it.
test "pragma pack push and pop nest" {
  let source =
    #|#pragma pack(push, 8)
    #|struct Outer { char c; long long v; };
    #|#pragma pack(push, 1)
    #|struct Inner { char c; long long v; };
    #|#pragma pack(pop)
    #|struct AfterPop { char c; long long v; };
    #|#pragma pack(pop)
    #|struct AfterOuterPop { char c; long long v; };
    #|int main(void) { return 0; }
  let prog = @parser.parse(source)
  debug_inspect(prog.structs[0].pack, content="Some(8)")
  debug_inspect(prog.structs[1].pack, content="Some(1)")
  debug_inspect(prog.structs[2].pack, content="Some(8)")
  debug_inspect(prog.structs[3].pack, content="None")
}

///|
/// `__attribute__((packed))` is `pack(1)`, the strongest cap, so it wins over a
/// weaker pragma in effect at the same point.
test "packed attribute overrides a weaker pragma" {
  let source =
    #|#pragma pack(4)
    #|struct Attr { char c; long long v; } __attribute__((packed));
    #|int main(void) { return 0; }
  let prog = @parser.parse(source)
  debug_inspect(prog.structs[0].pack, content="Some(1)")
}

///|
/// A `pop` with nothing pushed returns to natural alignment instead of
/// underflowing, and unrecognized or malformed forms leave the cap untouched.
test "pragma pack tolerates unbalanced and malformed directives" {
  let source =
    #|#pragma pack(pop)
    #|struct AfterBarePop { char c; long long v; };
    #|#pragma pack(3)
    #|struct AfterNonPowerOfTwo { char c; long long v; };
    #|#pragma pack
    #|struct AfterNoParens { char c; long long v; };
    #|#pragma once
    #|struct AfterOtherPragma { char c; long long v; };
    #|int main(void) { return 0; }
  let prog = @parser.parse(source)
  debug_inspect(prog.structs[0].pack, content="None")
  debug_inspect(prog.structs[1].pack, content="None")
  debug_inspect(prog.structs[2].pack, content="None")
  debug_inspect(prog.structs[3].pack, content="None")
}

///|
/// The directive table is indexed by source position, so a `pop` sitting after
/// a struct body must not retroactively apply to that struct.
test "pragma pack after a struct body does not apply to it" {
  let source =
    #|#pragma pack(1)
    #|struct Packed {
    #|  char c;
    #|  long long v;
    #|};
    #|#pragma pack(pop)
    #|int main(void) { return 0; }
  let prog = @parser.parse(source)
  debug_inspect(prog.structs[0].pack, content="Some(1)")
}

///|
/// A `#pragma pack` spelled inside a string literal or a comment is not a
/// directive and must not change the cap.
test "pragma pack ignores strings and comments" {
  let source =
    #|const char *s = "\n#pragma pack(1)\n";
    #|/* #pragma pack(1) */
    #|// #pragma pack(1)
    #|struct S { char c; long long v; };
    #|int main(void) { return 0; }
  let prog = @parser.parse(source)
  debug_inspect(prog.structs[0].pack, content="None")
}

///|
/// Unions honor the cap too: it lowers the union's own alignment and therefore
/// its padded size.
test "pragma pack applies to unions" {
  let source =
    #|#pragma pack(2)
    #|union U { char c; long long v; };
    #|int main(void) { return sizeof(union U); }
  let prog = @parser.parse(source)
  debug_inspect(prog.structs[0].pack, content="Some(2)")
  inspect(prog.structs[0].is_union, content="true")
}
