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
    #|  void *fa = __builtin_frame_address(0);
    #|  void *ra = __builtin_return_address(0);
    #|  if (fa == 0) return 100;
    #|  if (ra == 0) return 110;
    #|  if (__builtin_frame_address(1) != 0) return 120;
    #|  if (__builtin_return_address(1) != 0) return 130;
    #|  if (__builtin_extract_return_addr(ra) != ra) return 140;
    #|  if (__builtin_frob_return_addr(ra) != ra) return 150;
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
async test "e2e MIR oracle checks string literal scalar facts" {
  let source =
    #|int main(void) {
    #|  if (sizeof("abc") != 4) return 1;
    #|  if (__alignof__("abc") != 1) return 2;
    #|  if (!"abc") return 3;
    #|  if (*"abc" != 'a') return 4;
    #|  if ("abc"[1] != 'b') return 5;
    #|  if ("abc"[3] != 0) return 6;
    #|  if (__func__[0] != 'm') return 7;
    #|  if (__builtin_strlen("hello") != 5) return 8;
    #|  return 42;
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks string builtin return sizes" {
  let source =
    #|_Static_assert(sizeof(__builtin_strlen("abc")) == 8, "strlen size");
    #|_Static_assert(sizeof(__builtin_memchr("abc", 'a', 3)) == 8, "memchr pointer");
    #|_Static_assert(sizeof(__builtin_strchr("abc", 'a')) == 8, "strchr pointer");
    #|_Static_assert(sizeof(__builtin_strcmp("a", "b")) == 4, "strcmp int");
    #|_Static_assert(sizeof(__builtin_strncmp("a", "b", 1)) == 4, "strncmp int");
    #|_Static_assert(sizeof(__builtin_memcmp("a", "b", 1)) == 4, "memcmp int");
    #|int main(void) {
    #|  return sizeof(__builtin_strlen("abc")) +
    #|    sizeof(__builtin_memchr("abc", 'a', 3)) +
    #|    sizeof(__builtin_strchr("abc", 'a')) +
    #|    sizeof(__builtin_strcmp("a", "b")) +
    #|    sizeof(__builtin_strncmp("a", "b", 1)) +
    #|    sizeof(__builtin_memcmp("a", "b", 1));
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks floating builtin return sizes" {
  let source =
    #|_Static_assert(sizeof(__builtin_fabsf(-1.0f)) == sizeof(float), "fabsf");
    #|_Static_assert(sizeof(__builtin_fabs(-1.0)) == sizeof(double), "fabs");
    #|_Static_assert(sizeof(__builtin_fabsl(-1.0L)) == sizeof(long double), "fabsl");
    #|_Static_assert(sizeof(__builtin_copysignf(1.0f, -1.0f)) == sizeof(float), "copysignf");
    #|_Static_assert(sizeof(__builtin_copysign(1.0, -1.0)) == sizeof(double), "copysign");
    #|_Static_assert(sizeof(__builtin_copysignl(1.0L, -1.0L)) == sizeof(long double), "copysignl");
    #|_Static_assert(sizeof(__builtin_sqrtf(4.0f)) == sizeof(float), "sqrtf");
    #|_Static_assert(sizeof(__builtin_sqrt(4.0)) == sizeof(double), "sqrt");
    #|_Static_assert(sizeof(__builtin_sqrtl(4.0L)) == sizeof(long double), "sqrtl");
    #|_Static_assert(sizeof(__builtin_nanf("")) == sizeof(float), "nanf");
    #|_Static_assert(sizeof(__builtin_nan("")) == sizeof(double), "nan");
    #|_Static_assert(sizeof(__builtin_nanl("")) == sizeof(long double), "nanl");
    #|_Static_assert(sizeof(__builtin_huge_valf()) == sizeof(float), "huge_valf");
    #|_Static_assert(sizeof(__builtin_huge_val()) == sizeof(double), "huge_val");
    #|_Static_assert(sizeof(__builtin_huge_vall()) == sizeof(long double), "huge_vall");
    #|_Static_assert(sizeof(__builtin_inff()) == sizeof(float), "inff");
    #|_Static_assert(sizeof(__builtin_inf()) == sizeof(double), "inf");
    #|_Static_assert(sizeof(__builtin_infl()) == sizeof(long double), "infl");
    #|int main(void) {
    #|  return sizeof(__builtin_fabsf(-1.0f)) +
    #|    sizeof(__builtin_fabs(-1.0)) +
    #|    sizeof(__builtin_fabsl(-1.0L)) +
    #|    sizeof(__builtin_copysignf(1.0f, -1.0f)) +
    #|    sizeof(__builtin_copysign(1.0, -1.0)) +
    #|    sizeof(__builtin_copysignl(1.0L, -1.0L)) +
    #|    sizeof(__builtin_sqrtf(4.0f)) +
    #|    sizeof(__builtin_sqrt(4.0)) +
    #|    sizeof(__builtin_sqrtl(4.0L)) +
    #|    sizeof(__builtin_nanf("")) +
    #|    sizeof(__builtin_nan("")) +
    #|    sizeof(__builtin_nanl("")) +
    #|    sizeof(__builtin_huge_valf()) +
    #|    sizeof(__builtin_huge_val()) +
    #|    sizeof(__builtin_huge_vall()) +
    #|    sizeof(__builtin_inff()) +
    #|    sizeof(__builtin_inf()) +
    #|    sizeof(__builtin_infl());
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks floating classification return sizes" {
  let source =
    #|_Static_assert(sizeof(__builtin_isgreater(2.0, 1.0)) == sizeof(int), "isgreater");
    #|_Static_assert(sizeof(__builtin_isgreaterequal(2.0, 2.0)) == sizeof(int), "isgreaterequal");
    #|_Static_assert(sizeof(__builtin_isless(1.0, 2.0)) == sizeof(int), "isless");
    #|_Static_assert(sizeof(__builtin_islessequal(2.0, 2.0)) == sizeof(int), "islessequal");
    #|_Static_assert(sizeof(__builtin_islessgreater(1.0, 2.0)) == sizeof(int), "islessgreater");
    #|_Static_assert(sizeof(__builtin_isunordered(__builtin_nan(""), 1.0)) == sizeof(int), "isunordered");
    #|_Static_assert(sizeof(__builtin_isnan(__builtin_nan(""))) == sizeof(int), "isnan");
    #|_Static_assert(sizeof(__builtin_isnanf(__builtin_nanf(""))) == sizeof(int), "isnanf");
    #|_Static_assert(sizeof(__builtin_isnanl(__builtin_nanl(""))) == sizeof(int), "isnanl");
    #|_Static_assert(sizeof(__builtin_isinf(__builtin_inf())) == sizeof(int), "isinf");
    #|_Static_assert(sizeof(__builtin_isinff(__builtin_inff())) == sizeof(int), "isinff");
    #|_Static_assert(sizeof(__builtin_isinfl(__builtin_infl())) == sizeof(int), "isinfl");
    #|_Static_assert(sizeof(__builtin_isfinite(1.0)) == sizeof(int), "isfinite");
    #|_Static_assert(sizeof(__builtin_isfinitef(1.0f)) == sizeof(int), "isfinitef");
    #|_Static_assert(sizeof(__builtin_isfinitel(1.0L)) == sizeof(int), "isfinitel");
    #|_Static_assert(sizeof(__builtin_isnormal(1.0)) == sizeof(int), "isnormal");
    #|_Static_assert(sizeof(__builtin_isnormalf(1.0f)) == sizeof(int), "isnormalf");
    #|_Static_assert(sizeof(__builtin_isnormall(1.0L)) == sizeof(int), "isnormall");
    #|_Static_assert(sizeof(__builtin_signbit(-1.0)) == sizeof(int), "signbit");
    #|_Static_assert(sizeof(__builtin_signbitf(-1.0f)) == sizeof(int), "signbitf");
    #|_Static_assert(sizeof(__builtin_signbitl(-1.0L)) == sizeof(int), "signbitl");
    #|int main(void) {
    #|  return sizeof(__builtin_isgreater(2.0, 1.0)) +
    #|    sizeof(__builtin_isgreaterequal(2.0, 2.0)) +
    #|    sizeof(__builtin_isless(1.0, 2.0)) +
    #|    sizeof(__builtin_islessequal(2.0, 2.0)) +
    #|    sizeof(__builtin_islessgreater(1.0, 2.0)) +
    #|    sizeof(__builtin_isunordered(__builtin_nan(""), 1.0)) +
    #|    sizeof(__builtin_isnan(__builtin_nan(""))) +
    #|    sizeof(__builtin_isnanf(__builtin_nanf(""))) +
    #|    sizeof(__builtin_isnanl(__builtin_nanl(""))) +
    #|    sizeof(__builtin_isinf(__builtin_inf())) +
    #|    sizeof(__builtin_isinff(__builtin_inff())) +
    #|    sizeof(__builtin_isinfl(__builtin_infl())) +
    #|    sizeof(__builtin_isfinite(1.0)) +
    #|    sizeof(__builtin_isfinitef(1.0f)) +
    #|    sizeof(__builtin_isfinitel(1.0L)) +
    #|    sizeof(__builtin_isnormal(1.0)) +
    #|    sizeof(__builtin_isnormalf(1.0f)) +
    #|    sizeof(__builtin_isnormall(1.0L)) +
    #|    sizeof(__builtin_signbit(-1.0)) +
    #|    sizeof(__builtin_signbitf(-1.0f)) +
    #|    sizeof(__builtin_signbitl(-1.0L));
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks alloca return size" {
  let source =
    #|_Static_assert(sizeof(__builtin_alloca(16)) == sizeof(void *), "alloca pointer");
    #|int main(void) {
    #|  return sizeof(__builtin_alloca(16));
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks fortified builtin return sizes" {
  let source =
    #|_Static_assert(sizeof(__builtin___memcpy_chk(0, 0, 0, 0)) == sizeof(void *), "memcpy chk");
    #|_Static_assert(sizeof(__builtin___memset_chk(0, 0, 0, 0)) == sizeof(void *), "memset chk");
    #|_Static_assert(sizeof(__builtin___memmove_chk(0, 0, 0, 0)) == sizeof(void *), "memmove chk");
    #|_Static_assert(sizeof(__builtin___strcpy_chk(0, 0, 0)) == sizeof(char *), "strcpy chk");
    #|_Static_assert(sizeof(__builtin___strcat_chk(0, 0, 0)) == sizeof(char *), "strcat chk");
    #|_Static_assert(sizeof(__builtin___strncpy_chk(0, 0, 0, 0)) == sizeof(char *), "strncpy chk");
    #|_Static_assert(sizeof(__builtin___strncat_chk(0, 0, 0, 0)) == sizeof(char *), "strncat chk");
    #|_Static_assert(sizeof(__builtin___strlcpy_chk(0, 0, 0, 0)) == sizeof(unsigned long), "strlcpy chk");
    #|_Static_assert(sizeof(__builtin___strlcat_chk(0, 0, 0, 0)) == sizeof(unsigned long), "strlcat chk");
    #|_Static_assert(sizeof(__builtin___snprintf_chk(0, 0, 0, 0, 0)) == sizeof(int), "snprintf chk");
    #|_Static_assert(sizeof(__builtin___vsnprintf_chk(0, 0, 0, 0, 0, 0)) == sizeof(int), "vsnprintf chk");
    #|_Static_assert(sizeof(__builtin___sprintf_chk(0, 0, 0, 0)) == sizeof(int), "sprintf chk");
    #|_Static_assert(sizeof(__builtin___vsprintf_chk(0, 0, 0, 0, 0)) == sizeof(int), "vsprintf chk");
    #|_Static_assert(sizeof(__builtin___printf_chk(0, 0)) == sizeof(int), "printf chk");
    #|_Static_assert(sizeof(__builtin___fprintf_chk(0, 0, 0)) == sizeof(int), "fprintf chk");
    #|_Static_assert(sizeof(__builtin___vfprintf_chk(0, 0, 0, 0)) == sizeof(int), "vfprintf chk");
    #|int main(void) {
    #|  return sizeof(__builtin___memcpy_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___memset_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___memmove_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___strcpy_chk(0, 0, 0)) +
    #|    sizeof(__builtin___strcat_chk(0, 0, 0)) +
    #|    sizeof(__builtin___strncpy_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___strncat_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___strlcpy_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___strlcat_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___snprintf_chk(0, 0, 0, 0, 0)) +
    #|    sizeof(__builtin___vsnprintf_chk(0, 0, 0, 0, 0, 0)) +
    #|    sizeof(__builtin___sprintf_chk(0, 0, 0, 0)) +
    #|    sizeof(__builtin___vsprintf_chk(0, 0, 0, 0, 0)) +
    #|    sizeof(__builtin___printf_chk(0, 0)) +
    #|    sizeof(__builtin___fprintf_chk(0, 0, 0)) +
    #|    sizeof(__builtin___vfprintf_chk(0, 0, 0, 0));
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks literal string comparison builtins" {
  let source =
    #|int main(void) {
    #|  if (__builtin_strcmp("abc", "abc") != 0) return 1;
    #|  if (__builtin_strcmp("abc", "abd") >= 0) return 2;
    #|  if (__builtin_strcmp((const char *)"abd", "abc") <= 0) return 3;
    #|  if (__builtin_strncmp("abc", "abd", 2) != 0) return 4;
    #|  if (__builtin_strncmp("abc", "abd", 3) >= 0) return 5;
    #|  if (__builtin_strncmp("abc", "abd", 0) != 0) return 6;
    #|  if (__builtin_memcmp("abc", "abd", 2) != 0) return 7;
    #|  if (__builtin_memcmp("abc", "abd", 3) >= 0) return 8;
    #|  if (__builtin_memcmp("abd", "abc", 3) <= 0) return 9;
    #|  return 42;
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks literal string search nullness" {
  let source =
    #|int main(void) {
    #|  if (__builtin_strchr("abc", 'b') == 0) return 1;
    #|  if (__builtin_strchr("abc", 'x') != 0) return 2;
    #|  if (__builtin_strchr("abc", 0) == 0) return 3;
    #|  if (__builtin_strrchr("abba", 'b') == 0) return 4;
    #|  if (__builtin_memchr("abc", 'b', 2) == 0) return 5;
    #|  if (__builtin_memchr("abc", 'c', 2) != 0) return 6;
    #|  if (__builtin_strstr("abcde", "cd") == 0) return 7;
    #|  if (__builtin_strstr("abcde", "ce") != 0) return 8;
    #|  if (__builtin_strstr("abc", "") == 0) return 9;
    #|  return 42;
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
