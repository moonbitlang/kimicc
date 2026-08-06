///|
/// Masks an integer bit pattern to the low `width` bits used by C integer
/// builtins.
pub fn mask_int_width(value : Int64, width : Int) -> Int64 {
  if width >= 64 {
    value
  } else {
    value & ((1L << width) - 1L)
  }
}

///|
/// Counts leading zero bits after masking to the requested integer width.
pub fn count_leading_zero_bits(value : Int64, width : Int) -> Int64 {
  let value = mask_int_width(value, width)
  for i in 0..<width {
    let shift = width - 1 - i
    if ((value >> shift) & 1L) != 0L {
      return i.to_int64()
    }
  }
  width.to_int64()
}

///|
/// Counts trailing zero bits after masking to the requested integer width.
pub fn count_trailing_zero_bits(value : Int64, width : Int) -> Int64 {
  let value = mask_int_width(value, width)
  for i in 0..<width {
    if ((value >> i) & 1L) != 0L {
      return i.to_int64()
    }
  }
  width.to_int64()
}

///|
/// Returns the one-based index of the least-significant set bit, or zero.
pub fn first_set_bit(value : Int64, width : Int) -> Int64 {
  let value = mask_int_width(value, width)
  if value == 0L {
    0L
  } else {
    count_trailing_zero_bits(value, width) + 1L
  }
}

///|
/// Counts one bits after masking to the requested integer width.
pub fn count_one_bits(value : Int64, width : Int) -> Int64 {
  let mut value = mask_int_width(value, width)
  let mut count = 0L
  for _ in 0..<width {
    count += value & 1L
    value = value >> 1
  }
  count
}

///|
/// Byte-swaps the low `width` bits. `width` is expected to be byte-aligned.
pub fn byte_swap_bits(value : Int64, width : Int) -> Int64 {
  let value = mask_int_width(value, width)
  let mut result = 0L
  for i in 0..<(width / 8) {
    result = (result << 8) | ((value >> (i * 8)) & 0xFFL)
  }
  result
}

///|
fn normalized_bit_shift(shift : Int64, width : Int) -> Int {
  let mut amount = (shift % width.to_int64()).to_int()
  if amount < 0 {
    amount += width
  }
  amount
}

///|
fn logical_right_shift_bits(value : Int64, width : Int, shift : Int) -> Int64 {
  if shift == 0 {
    mask_int_width(value, width)
  } else if width >= 64 {
    (value.reinterpret_as_uint64() >> shift).reinterpret_as_int64()
  } else {
    mask_int_width(value, width) >> shift
  }
}

///|
/// Rotates the low `width` bits left or right by a normalized shift amount.
pub fn rotate_bits(
  value : Int64,
  shift : Int64,
  width : Int,
  left : Bool,
) -> Int64 {
  let amount = normalized_bit_shift(shift, width)
  let value = mask_int_width(value, width)
  if amount == 0 {
    value
  } else if left {
    mask_int_width(
      (value << amount) | logical_right_shift_bits(value, width, width - amount),
      width,
    )
  } else {
    mask_int_width(
      logical_right_shift_bits(value, width, amount) |
      (value << (width - amount)),
      width,
    )
  }
}
