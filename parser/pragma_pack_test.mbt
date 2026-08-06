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
/// A `pop` with nothing pushed leaves the cap alone rather than underflowing or
/// reverting to natural alignment, matching clang, which warns and keeps the
/// value in effect. Unrecognized and malformed forms are likewise inert.
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
/// An unmatched `pop` keeps whatever cap is already set instead of clearing it,
/// so a later struct still packs.
test "pragma pack unmatched pop keeps the current cap" {
  let source =
    #|#pragma pack(1)
    #|#pragma pack(pop)
    #|struct StillPacked { char c; long long v; };
    #|int main(void) { return 0; }
  let prog = @parser.parse(source)
  debug_inspect(prog.structs[0].pack, content="Some(1)")
}

///|
/// `#pragma pack(pop, N)` pops the stack and then sets the cap to `N`; a
/// malformed `N` makes the whole directive inert.
test "pragma pack pop with a value sets the cap" {
  let source =
    #|#pragma pack(push, 1)
    #|struct Tight { char c; long long v; };
    #|#pragma pack(pop, 4)
    #|struct PoppedToFour { char c; long long v; };
    #|#pragma pack(pop, 3)
    #|struct AfterMalformedPop { char c; long long v; };
    #|int main(void) { return 0; }
  let prog = @parser.parse(source)
  debug_inspect(prog.structs[0].pack, content="Some(1)")
  debug_inspect(prog.structs[1].pack, content="Some(4)")
  debug_inspect(prog.structs[2].pack, content="Some(4)")
}

///|
/// A pack value too large to be valid is rejected rather than wrapping around
/// into an accepted one.
test "pragma pack rejects out-of-range values" {
  let source =
    #|#pragma pack(4294967297)
    #|struct Unpacked { char c; long long v; };
    #|int main(void) { return 0; }
  let prog = @parser.parse(source)
  debug_inspect(prog.structs[0].pack, content="None")
}

///|
/// `0` is a valid argument meaning natural alignment, so `pack(0)` clears the
/// cap and `pack(pop, 0)` pops and then clears it.
test "pragma pack treats zero as natural alignment" {
  let source =
    #|#pragma pack(2)
    #|#pragma pack(0)
    #|struct Cleared { char c; long long v; };
    #|#pragma pack(push, 1)
    #|#pragma pack(pop, 0)
    #|struct PoppedToNatural { char c; long long v; };
    #|int main(void) { return 0; }
  let prog = @parser.parse(source)
  debug_inspect(prog.structs[0].pack, content="None")
  debug_inspect(prog.structs[1].pack, content="None")
}

///|
/// The argument is a C integer literal, so a leading `0` is octal and `0x` is
/// hex. `016` is octal 14, not a power of two, and is therefore rejected --
/// reading it as decimal 16 would apply a cap clang refuses.
test "pragma pack parses octal and hex arguments" {
  let source =
    #|#pragma pack(010)
    #|struct Octal8 { char c; long long v; };
    #|#pragma pack(0x10)
    #|struct Hex16 { char c; long long v; };
    #|#pragma pack(2)
    #|#pragma pack(016)
    #|struct OctalRejected { char c; long long v; };
    #|int main(void) { return 0; }
  let prog = @parser.parse(source)
  debug_inspect(prog.structs[0].pack, content="Some(8)")
  debug_inspect(prog.structs[1].pack, content="Some(16)")
  debug_inspect(prog.structs[2].pack, content="Some(2)")
}

///|
/// A `u`/`l` suffix is part of the literal, and `0b` is a binary literal, so
/// neither form makes the directive inert.
test "pragma pack accepts integer suffixes and binary literals" {
  let source =
    #|#pragma pack(2u)
    #|struct Unsigned { char c; long long v; };
    #|#pragma pack(8UL)
    #|struct UnsignedLong { char c; long long v; };
    #|#pragma pack(4LL)
    #|struct LongLong { char c; long long v; };
    #|#pragma pack(0b10)
    #|struct Binary { char c; long long v; };
    #|int main(void) { return 0; }
  let prog = @parser.parse(source)
  debug_inspect(prog.structs[0].pack, content="Some(2)")
  debug_inspect(prog.structs[1].pack, content="Some(8)")
  debug_inspect(prog.structs[2].pack, content="Some(4)")
  debug_inspect(prog.structs[3].pack, content="Some(2)")
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
