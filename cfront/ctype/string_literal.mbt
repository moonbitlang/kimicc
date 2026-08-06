///|
/// Number of bytes in a C string literal object, including the implicit
/// terminating NUL byte.
pub fn string_literal_array_length(value : String) -> Int {
  value.length() + 1
}

///|
/// Object size in bytes for a C string literal, including the implicit
/// terminating NUL byte.
pub fn string_literal_object_size(value : String) -> Int64 {
  string_literal_array_length(value).to_int64()
}

///|
/// C `strlen` result for a string-literal byte sequence.
pub fn string_literal_c_length(value : String) -> Int {
  for i in 0..<value.length() {
    if value[i].to_int() == 0 {
      return i
    }
  }
  value.length()
}

///|
/// C `strlen` result for a pointer into a string-literal byte sequence.
pub fn string_literal_c_length_from(value : String, offset : Int64) -> Int64 {
  if offset <= 0L {
    return string_literal_c_length(value).to_int64()
  }
  if offset >= value.length().to_int64() {
    return 0L
  }
  for i in offset.to_int()..<value.length() {
    if value[i].to_int() == 0 {
      return i.to_int64() - offset
    }
  }
  value.length().to_int64() - offset
}
