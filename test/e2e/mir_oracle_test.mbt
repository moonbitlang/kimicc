///|
async test "e2e MIR oracle checks scalar calls and arithmetic" {
  let source =
    #|int mul(int a, int b) {
    #|  return a * b;
    #|}
    #|int main(void) {
    #|  int x = 6;
    #|  int y = 7;
    #|  return mul(x, y);
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks scalar control flow" {
  let source =
    #|int main(void) {
    #|  int sum = 0;
    #|  for (int i = 0; i < 10; i++) {
    #|    if (i == 3) continue;
    #|    if (i == 8) break;
    #|    sum += i;
    #|  }
    #|  while (sum < 30) {
    #|    sum++;
    #|  }
    #|  return sum + (sum == 30 ? 12 : 0);
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks scalar globals and casts" {
  let source =
    #|int g = 35;
    #|int bump(int x) {
    #|  g += x;
    #|  return g;
    #|}
    #|int main(void) {
    #|  unsigned char c = 255 + 1;
    #|  int v = bump(5);
    #|  return v + sizeof(long double) - 6 + c;
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks scalar switch fallthrough" {
  let source =
    #|int main(void) {
    #|  int total = 0;
    #|  for (int i = 0; i < 5; i++) {
    #|    switch (i) {
    #|    case 0:
    #|      total += 3;
    #|      break;
    #|    case 1:
    #|    case 2:
    #|      total += 5;
    #|      break;
    #|    case 4:
    #|      total += 7;
    #|    default:
    #|      total += 11;
    #|    }
    #|  }
    #|  return total;
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks scalar goto" {
  let source =
    #|int main(void) {
    #|  int total = 0;
    #|  int i = 0;
    #|loop:
    #|  i++;
    #|  if (i == 2) goto skip;
    #|  total += i;
    #|skip:
    #|  if (i < 5) goto loop;
    #|  return total;
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks scalar builtin calls" {
  let source =
    #|int value(void) {
    #|  return 9;
    #|}
    #|int main(void) {
    #|  int x = 4;
    #|  int y = 0;
    #|  int total = 0;
    #|  total += __builtin_expect(x, 1 / y);
    #|  total += __builtin_expect_with_probability(x, 1 / y, 0.9);
    #|  total += __builtin_unpredictable(x);
    #|  total += __builtin_constant_p(1 / y);
    #|  total += __builtin_flt_rounds();
    #|  if (__builtin_object_size(0, 0) + 1 != 0) return 50;
    #|  if (__builtin_dynamic_object_size(0, 0) + 1 != 0) return 60;
    #|  total += __builtin_assume(1);
    #|  total += __builtin_prefetch(0, 0, 0);
    #|  if ((unsigned long)__builtin_assume_aligned((void*)32, 16) != 32ul) return 70;
    #|  if ((unsigned long)__builtin_extract_return_addr((void*)77) != 77ul) return 80;
    #|  if ((unsigned long)__builtin_frob_return_addr((void*)88) != 88ul) return 90;
    #|  return total + value();
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks parser folded compile-time builtins" {
  let source =
    #|struct Item { char tag; int x; };
    #|struct Outer { char head; struct Item items[3]; char tail; };
    #|struct S { int x; };
    #|union U { int x; double y; };
    #|int main(void) {
    #|  int x = 0;
    #|  double d;
    #|  int a[2];
    #|  struct S s;
    #|  union U u;
    #|  int total = 0;
    #|  total += __builtin_choose_expr(__builtin_types_compatible_p(int, signed int), 7, missing());
    #|  total += __builtin_choose_expr(__builtin_types_compatible_p(int, unsigned int), missing(), 5);
    #|  total += __builtin_classify_type(x);
    #|  total += __builtin_classify_type(d);
    #|  total += __builtin_classify_type(a);
    #|  total += __builtin_classify_type(s);
    #|  total += __builtin_classify_type(u);
    #|  if (__builtin_offsetof(struct Outer, items[2].x) != 24) return 50;
    #|  if (__builtin_offsetof(struct Outer, tail) != 28) return 60;
    #|  return total;
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks scalar bit builtins" {
  let source =
    #|int main(void) {
    #|  if (__builtin_clz(8) != 28) return 1;
    #|  if (__builtin_clzll(8ull) != 60) return 2;
    #|  if (__builtin_ctz(40) != 3) return 3;
    #|  if (__builtin_ctzll(48ull) != 4) return 4;
    #|  if ((__builtin_bswap16(0x0102) & 0xffff) != 0x0201) return 5;
    #|  if (__builtin_bswap32(0x01020304u) != 0x04030201u) return 6;
    #|  if ((__builtin_bswap64(0x0102030405060708ull) & 255) != 1) return 7;
    #|  if (__builtin_clzl(8ul) != 60) return 8;
    #|  if (__builtin_ctzl(48ul) != 4) return 9;
    #|  if ((__builtin_bswap((unsigned short)0x0102) & 0xffff) != 0x0201) return 10;
    #|  if (__builtin_bswap(0x01020304u) != 0x04030201u) return 11;
    #|  if ((__builtin_bswap(0x0102030405060708ull) & 255) != 1) return 12;
    #|  return 0;
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks scalar population builtins" {
  let source =
    #|int main(void) {
    #|  if (__builtin_ffs(0u) != 0) return 1;
    #|  if (__builtin_ffs(8u) != 4) return 2;
    #|  if (__builtin_ffsl(16ul) != 5) return 3;
    #|  if (__builtin_ffsll(32ull) != 6) return 4;
    #|  if (__builtin_popcount(0xf0f0u) != 8) return 5;
    #|  if (__builtin_popcountl(0x0f0f0f0f0f0f0f0ful) != 32) return 6;
    #|  if (__builtin_popcountll(0x0f0f0f0f0f0f0f0full) != 32) return 7;
    #|  if (__builtin_parity(0xf0f1u) != 1) return 8;
    #|  if (__builtin_parityl(0x0f0f0f0f0f0f0f0ful) != 0) return 9;
    #|  if (__builtin_parityll(0x0f0f0f0f0f0f0f0eull) != 1) return 10;
    #|  return 0;
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks scalar abs builtins" {
  let source =
    #|int main(void) {
    #|  if (__builtin_abs(-7) != 7) return 1;
    #|  if (__builtin_abs(5) != 5) return 2;
    #|  if (__builtin_labs(-1234567890123L) != 1234567890123L) return 3;
    #|  if (__builtin_llabs(-900000000000000000LL) != 900000000000000000LL) return 4;
    #|  return 0;
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks scalar alignment builtins" {
  let source =
    #|int main(void) {
    #|  if (!__builtin_is_aligned(32, 16)) return 1;
    #|  if (__builtin_is_aligned(34, 16)) return 2;
    #|  if (__builtin_align_up(33, 16) != 48) return 3;
    #|  if (__builtin_align_down(47, 16) != 32) return 4;
    #|  if (__builtin_align_up(0x1234567890ull, 256) != 0x1234567900ull) return 5;
    #|  return 0;
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks scalar rotate builtins" {
  let source =
    #|int main(void) {
    #|  if ((__builtin_rotateleft32(0x12345678u, 8) & 255) != 0x12) return 1;
    #|  if ((__builtin_rotateright32(0x12345678u, 8) & 255) != 0x56) return 2;
    #|  if ((__builtin_rotateleft64(0x0123456789abcdefull, 16) & 255) != 0x23) return 3;
    #|  if ((__builtin_rotateright64(0x0123456789abcdefull, 16) & 255) != 0xab) return 4;
    #|  if (__builtin_rotateleft(0x12345678u, 8) != 0x34567812u) return 5;
    #|  if ((__builtin_rotateright(0x0123456789abcdefull, 16) & 255) != 0xab) return 6;
    #|  return 0;
    #|}
  run_source_against_mir_oracle(source)
}
