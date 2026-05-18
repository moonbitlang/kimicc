///|
test "ctype scalar predicates and aliases" {
  inspect(@ctype.Type::SInt.is_integer(), content="true")
  inspect(@ctype.Type::SInt.is_signed(), content="true")
  inspect(@ctype.Type::UInt.is_signed(), content="false")
  inspect(@ctype.Type::Double.is_floating(), content="true")
  inspect(@ctype.Type::SInt.to_unsigned(), content="UInt")
}

///|
test "ctype layout helpers cover scalar ABI facts" {
  inspect(@ctype.Type::Pointer(@ctype.Type::SInt).size(), content="8")
  inspect(@ctype.Type::Array(@ctype.Type::SChar, 4).size(), content="4")
  inspect(@ctype.Type::Aligned(@ctype.Type::SInt, 16).align(), content="16")
}
