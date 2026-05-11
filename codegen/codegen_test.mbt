///|
test "generate simple function" {
  let source = "int main() { return 42; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("_main:"), content="true")
  inspect(assembly.contains("\tmov\tx9, #42"), content="true")
  inspect(assembly.contains("\tret"), content="true")
}

///|
test "generate linux amd64 simple function" {
  let source = "int main() { return 42; }"
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\t.intel_syntax noprefix"), content="true")
  inspect(assembly.contains("\t.globl\tmain"), content="true")
  inspect(assembly.contains("\tmov\trax, 42"), content="true")
  inspect(assembly.contains("_main:"), content="false")
}

///|
test "generate linux amd64 function with params" {
  let source = "int add(int a, int b) { return a + b; }"
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("add:"), content="true")
  inspect(assembly.contains("mov\tQWORD PTR [rbp - 8], rdi"), content="true")
  inspect(assembly.contains("mov\tQWORD PTR [rbp - 16], rsi"), content="true")
  inspect(assembly.contains("add\trax, r10"), content="true")
}

///|
test "generate linux amd64 postfix increment stores new value and returns old value" {
  let source = "int main(void) { int x = 1; return x++; }"
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("pop\trdx"), content="true")
  inspect(assembly.contains("pop\tr10"), content="true")
  inspect(assembly.contains("mov\trax, rdx"), content="true")
}

///|
test "generate linux amd64 floating inc dec uses fp arithmetic" {
  let source =
    #|double post_double(void) {
    #|  double x = 1.5;
    #|  return x++;
    #|}
    #|float pre_float(void) {
    #|  float x = 2;
    #|  return --x;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("addsd\txmm0, xmm1"), content="true")
  inspect(assembly.contains("subss\txmm0, xmm1"), content="true")
  inspect(assembly.contains("movsd\tQWORD PTR [rsp], xmm0"), content="true")
  inspect(assembly.contains("movsd\txmm0, QWORD PTR [rsp]"), content="true")
}

///|
test "generate linux amd64 floating compound assignment operators" {
  let source =
    #|double mutate_double(void) {
    #|  double x = 1.5;
    #|  x += 0.5;
    #|  x *= 2.0;
    #|  return x;
    #|}
    #|float mutate_float(void) {
    #|  float x = 3.5f;
    #|  x -= 1.0f;
    #|  x /= 2.0f;
    #|  return x;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("addsd\txmm0, xmm1"), content="true")
  inspect(assembly.contains("mulsd\txmm0, xmm1"), content="true")
  inspect(assembly.contains("subss\txmm0, xmm1"), content="true")
  inspect(assembly.contains("divss\txmm0, xmm1"), content="true")
}

///|
test "generate linux amd64 double params and arithmetic" {
  let source = "double add(double a, double b) { return a + b; }"
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("movsd\tQWORD PTR [rbp - 8], xmm0"), content="true")
  inspect(
    assembly.contains("movsd\tQWORD PTR [rbp - 16], xmm1"),
    content="true",
  )
  inspect(assembly.contains("addsd\txmm0, xmm1"), content="true")
}

///|
test "generate linux amd64 double call and cast to int" {
  let source = "double add(double a, double b) { return a + b; } int main(void) { return (int)add(19.5, 22.5); }"
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("mov\tal, 0"), content="true")
  inspect(assembly.contains("call\tadd"), content="true")
  inspect(assembly.contains("cvttsd2si\trax, xmm0"), content="true")
}

///|
test "generate linux amd64 indirect function pointer calls" {
  let source =
    #|struct Pair { long a; long b; };
    #|int add(int a, int b) { return a + b; }
    #|double plus_half(double x) { return x + 0.5; }
    #|struct Pair make_pair(long a, long b) { struct Pair p; p.a = a; p.b = b; return p; }
    #|int sum_pair(struct Pair p) { return (int)(p.a + p.b); }
    #|int main(void) {
    #|  int (*fp)(int, int) = add;
    #|  double (*dp)(double) = plus_half;
    #|  struct Pair (*mp)(long, long) = make_pair;
    #|  return fp(19, 23) + (int)(*dp)(0.5) + sum_pair(mp(0, 1)) - 1;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("lea\trax, [rip + add]"), content="true")
  inspect(assembly.contains("lea\trax, [rip + plus_half]"), content="true")
  inspect(assembly.contains("lea\trax, [rip + make_pair]"), content="true")
  inspect(assembly.contains("call\tQWORD PTR [rsp + 8]"), content="true")
  inspect(assembly.contains("cvttsd2si\trax, xmm0"), content="true")
  inspect(assembly.contains("mov\trax, QWORD PTR [r10]"), content="true")
  inspect(assembly.contains("mov\trdx, QWORD PTR [r10 + 8]"), content="true")
}

///|
test "generate linux amd64 variadic va_arg state" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int mix(int n, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, n);
    #|  int a = __builtin_va_arg(ap, int);
    #|  double b = __builtin_va_arg(ap, double);
    #|  __builtin_va_end(ap);
    #|  return a + (int)b;
    #|}
    #|int main(void) { return mix(2, 20, 22.0); }
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("movups\tXMMWORD PTR"), content="true")
  inspect(assembly.contains("cmp\teax, 48"), content="true")
  inspect(assembly.contains("cmp\teax, 176"), content="true")
  inspect(assembly.contains("add\tDWORD PTR [r11], 8"), content="true")
  inspect(assembly.contains("add\tDWORD PTR [r11 + 4], 16"), content="true")
  inspect(assembly.contains("mov\tal, 1"), content="true")
}

///|
test "generate linux amd64 variadic default argument promotions" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|float one(void) { return 1.5f; }
    #|int mix(int n, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, n);
    #|  double d = __builtin_va_arg(ap, double);
    #|  int i = __builtin_va_arg(ap, int);
    #|  __builtin_va_end(ap);
    #|  return (int)d + i;
    #|}
    #|int main(void) {
    #|  signed char c = 2;
    #|  return mix(2, one(), c);
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("call\tone"), content="true")
  inspect(assembly.contains("cvtss2sd\txmm0, xmm0"), content="true")
  inspect(assembly.contains("movsxd\trax, eax"), content="true")
  inspect(assembly.contains("mov\tal, 1"), content="true")
}

///|
test "generate linux amd64 unprototyped call default promotions" {
  let source =
    #|int old_mix();
    #|float one(void) { return 1.5f; }
    #|int main(void) {
    #|  signed char c = 2;
    #|  return old_mix(c, one());
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("call\tone"), content="true")
  inspect(assembly.contains("cvtss2sd\txmm0, xmm0"), content="true")
  inspect(assembly.contains("movsxd\trax, eax"), content="true")
  inspect(assembly.contains("call\told_mix"), content="true")
}

///|
test "generate linux amd64 lowers memory builtins" {
  let source =
    #|int main(void) {
    #|  char src[4];
    #|  char dst[4];
    #|  src[0] = 1;
    #|  src[1] = 2;
    #|  src[2] = 3;
    #|  src[3] = 0;
    #|  __builtin_memcpy(dst, src, 4);
    #|  __builtin_memset(src, 0, 4);
    #|  __builtin_memmove(src, dst, 4);
    #|  __builtin_bzero(dst, 4);
    #|  return src[2] + dst[0];
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("call\tmemcpy"), content="true")
  inspect(assembly.contains("call\tmemset"), content="true")
  inspect(assembly.contains("call\tmemmove"), content="true")
  inspect(assembly.contains("call\tbzero"), content="true")
  inspect(assembly.contains("__builtin_memcpy"), content="false")
  inspect(assembly.contains("__builtin_memset"), content="false")
}

///|
test "generate linux amd64 lowers scalar hint builtins" {
  let source =
    #|int hints(int x, int *p) {
    #|  if (__builtin_expect(x, 1) != x) return 1;
    #|  __builtin_assume(x);
    #|  __builtin_prefetch(p, 0, 3);
    #|  if (__builtin_constant_p(x)) return 2;
    #|  if (__builtin_object_size(p, 0) + 1 != 0) return 3;
    #|  if (__builtin_frame_address(1) != 0) return 4;
    #|  if (__builtin_frame_address(0) == 0) return 5;
    #|  if (__builtin_assume_aligned(p, 16) != p) return 6;
    #|  if (__builtin_expect_with_probability(x, 1, 0.9) != x) return 7;
    #|  void *ra = __builtin_return_address(0);
    #|  if (ra == 0) return 8;
    #|  if (__builtin_return_address(1) != 0) return 9;
    #|  if (__builtin_extract_return_addr(ra) != ra) return 10;
    #|  if (__builtin_frob_return_addr(ra) != ra) return 11;
    #|  if (__builtin_flt_rounds() != 1) return 12;
    #|  return 0;
    #|}
    #|int trapper(void) {
    #|  __builtin_trap();
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\tud2"), content="true")
  inspect(assembly.contains("\tmov\trax, -1"), content="true")
  inspect(assembly.contains("\tmov\trax, rbp"), content="true")
  inspect(assembly.contains("\tmov\trax, QWORD PTR [rbp + 8]"), content="true")
  inspect(assembly.contains("call\t__builtin_expect"), content="false")
  inspect(
    assembly.contains("call\t__builtin_expect_with_probability"),
    content="false",
  )
  inspect(assembly.contains("call\t__builtin_assume_aligned"), content="false")
  inspect(assembly.contains("call\t__builtin_prefetch"), content="false")
  inspect(assembly.contains("call\t__builtin_object_size"), content="false")
  inspect(assembly.contains("call\t__builtin_frame_address"), content="false")
  inspect(assembly.contains("call\t__builtin_return_address"), content="false")
  inspect(
    assembly.contains("call\t__builtin_extract_return_addr"),
    content="false",
  )
  inspect(
    assembly.contains("call\t__builtin_frob_return_addr"),
    content="false",
  )
  inspect(assembly.contains("call\t__builtin_flt_rounds"), content="false")
}

///|
test "generate linux amd64 lowers string builtins" {
  let source =
    #|int main(void) {
    #|  char dst[16];
    #|  __builtin_strcpy(dst, "ab");
    #|  __builtin___strcat_chk(dst, "c", 16);
    #|  if (__builtin_strlen(dst) != 3) return 1;
    #|  if (__builtin_strcmp(dst, "abc") != 0) return 2;
    #|  __builtin___strncpy_chk(dst, "xyzz", 2, 16);
    #|  dst[2] = 0;
    #|  __builtin___strncat_chk(dst, "pq", 1, 16);
    #|  if (__builtin_strcmp(dst, "xyp") != 0) return 3;
    #|  if (__builtin_strncmp(dst, "xyq", 2) != 0) return 4;
    #|  if (__builtin_memcmp(dst, "xyp", 3) != 0) return 5;
    #|  if (__builtin_strchr(dst, 121) != dst + 1) return 6;
    #|  if (__builtin_strrchr(dst, 112) != dst + 2) return 7;
    #|  if (__builtin_strstr(dst, "yp") != dst + 1) return 8;
    #|  if (__builtin_memchr(dst, 112, 3) != dst + 2) return 9;
    #|  char small[4];
    #|  if (__builtin___strlcpy_chk(small, "abcdef", 4, 4) != 6) return 10;
    #|  if (__builtin_strcmp(small, "abc") != 0) return 11;
    #|  char cat[8];
    #|  __builtin_strcpy(cat, "ab");
    #|  if (__builtin___strlcat_chk(cat, "cdef", 8, 8) != 6) return 12;
    #|  if (__builtin_strcmp(cat, "abcdef") != 0) return 13;
    #|  char copy[16];
    #|  if (__builtin_mempcpy(copy, "uv", 2) != copy + 2) return 14;
    #|  if (__builtin___mempcpy_chk(copy + 2, "wx", 2, 14) != copy + 4) return 15;
    #|  if (__builtin_stpcpy(copy, "hi") != copy + 2) return 16;
    #|  if (__builtin___stpcpy_chk(copy, "ok", 16) != copy + 2) return 17;
    #|  if (__builtin_stpncpy(copy, "ab", 2) != copy + 2) return 18;
    #|  if (__builtin___stpncpy_chk(copy, "cd", 2, 16) != copy + 2) return 19;
    #|  return 0;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("call\tstrcpy"), content="true")
  inspect(assembly.contains("call\tstrcat"), content="true")
  inspect(assembly.contains("call\tstrlen"), content="true")
  inspect(assembly.contains("call\tstrcmp"), content="true")
  inspect(assembly.contains("call\tstrncmp"), content="true")
  inspect(assembly.contains("call\tmemcmp"), content="true")
  inspect(assembly.contains("call\tmemchr"), content="true")
  inspect(assembly.contains("call\tstrchr"), content="true")
  inspect(assembly.contains("call\tstrrchr"), content="true")
  inspect(assembly.contains("call\tstrstr"), content="true")
  inspect(assembly.contains("call\tstrncpy"), content="true")
  inspect(assembly.contains("call\tstpcpy"), content="true")
  inspect(assembly.contains("call\tstpncpy"), content="true")
  inspect(assembly.contains("call\tstrncat"), content="true")
  inspect(assembly.contains("call\tmempcpy"), content="true")
  inspect(assembly.contains("call\t__builtin_strcpy"), content="false")
  inspect(assembly.contains("call\t__builtin___strcat_chk"), content="false")
  inspect(assembly.contains("call\t__builtin___mempcpy_chk"), content="false")
  inspect(assembly.contains("call\t__builtin___stpcpy_chk"), content="false")
  inspect(assembly.contains("call\t__builtin___stpncpy_chk"), content="false")
  inspect(assembly.contains("call\t__builtin_strlen"), content="false")
  inspect(assembly.contains("call\t__builtin_strncmp"), content="false")
  inspect(assembly.contains("call\t__builtin_memcmp"), content="false")
  inspect(assembly.contains("call\t__builtin_memchr"), content="false")
  inspect(assembly.contains("call\t__builtin_strchr"), content="false")
  inspect(assembly.contains("call\t__builtin_strrchr"), content="false")
  inspect(assembly.contains("call\t__builtin_strstr"), content="false")
  inspect(assembly.contains("call\t__builtin___strncat_chk"), content="false")
  inspect(assembly.contains("call\tstrlcpy"), content="true")
  inspect(assembly.contains("call\tstrlcat"), content="true")
  inspect(assembly.contains("call\t__builtin___strlcpy_chk"), content="false")
  inspect(assembly.contains("call\t__builtin___strlcat_chk"), content="false")
}

///|
test "generate linux amd64 lowers fortified formatted builtins" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|int sink(char *fmt, ...) {
    #|  va_list ap;
    #|  char buf[64];
    #|  int n;
    #|  __builtin_va_start(ap, fmt);
    #|  n = __builtin___vsnprintf_chk(buf, 64, 0, 64, fmt, ap);
    #|  n = n + __builtin___vsprintf_chk(buf, 0, 64, fmt, ap);
    #|  n = n + __builtin___vfprintf_chk((void*)0, 1, fmt, ap);
    #|  __builtin_va_end(ap);
    #|  return n;
    #|}
    #|int main(void) {
    #|  char buf[64];
    #|  int n = __builtin___snprintf_chk(buf, 64, 0, 64, "%d %f", 7, 2.0);
    #|  n = n + __builtin___sprintf_chk(buf, 0, 64, "%d", n);
    #|  n = n + __builtin___printf_chk(1, "%d", n);
    #|  n = n + __builtin___fprintf_chk((void*)0, 1, "%d", n);
    #|  return n + sink("%d", 3);
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("call\tsnprintf"), content="true")
  inspect(assembly.contains("call\tvsnprintf"), content="true")
  inspect(assembly.contains("call\tsprintf"), content="true")
  inspect(assembly.contains("call\tvsprintf"), content="true")
  inspect(assembly.contains("call\tprintf"), content="true")
  inspect(assembly.contains("call\tfprintf"), content="true")
  inspect(assembly.contains("call\tvfprintf"), content="true")
  inspect(assembly.contains("\tmov\tal, 1"), content="true")
  inspect(assembly.contains("call\t__builtin___snprintf_chk"), content="false")
  inspect(assembly.contains("call\t__builtin___vsnprintf_chk"), content="false")
  inspect(assembly.contains("call\t__builtin___sprintf_chk"), content="false")
  inspect(assembly.contains("call\t__builtin___vsprintf_chk"), content="false")
  inspect(assembly.contains("call\t__builtin___printf_chk"), content="false")
  inspect(assembly.contains("call\t__builtin___fprintf_chk"), content="false")
  inspect(assembly.contains("call\t__builtin___vfprintf_chk"), content="false")
}

///|
test "generate linux amd64 lowers bit builtins" {
  let source =
    #|int main(void) {
    #|  if (__builtin_clz(1u) != 31) return 1;
    #|  if (__builtin_clzl(1ul) != 63) return 2;
    #|  if (__builtin_clzll(1ull) != 63) return 3;
    #|  if (__builtin_ctz(8u) != 3) return 4;
    #|  if (__builtin_ctzl(16ul) != 4) return 5;
    #|  if (__builtin_ctzll(32ull) != 5) return 6;
    #|  if (__builtin_ffs(0u) != 0) return 17;
    #|  if (__builtin_ffs(8u) != 4) return 18;
    #|  if (__builtin_ffsl(16ul) != 5) return 19;
    #|  if (__builtin_ffsll(32ull) != 6) return 20;
    #|  if ((__builtin_bswap16(0x0102u) & 255) != 1) return 7;
    #|  if ((__builtin_bswap32(0x01020304u) & 255) != 1) return 8;
    #|  if ((__builtin_bswap64(0x0102030405060708ull) & 255) != 1) return 9;
    #|  if ((__builtin_bswap(0x01020304u) & 255) != 1) return 24;
    #|  if ((__builtin_bswap(0x0102030405060708ull) & 255) != 1) return 25;
    #|  if (__builtin_rotateleft32(0x12345678u, 8) != 0x34567812u) return 10;
    #|  if ((__builtin_rotateright32(0x12345678u, 8) & 255) != 0x56) return 11;
    #|  if ((__builtin_rotateleft64(0x0123456789abcdefull, 16) & 255) != 0x23) return 12;
    #|  if ((__builtin_rotateright64(0x0123456789abcdefull, 16) & 255) != 0xab) return 13;
    #|  if (__builtin_rotateleft(0x12345678u, 8) != 0x34567812u) return 26;
    #|  if ((__builtin_rotateright(0x0123456789abcdefull, 16) & 255) != 0xab) return 27;
    #|  if (__builtin_popcount(0xf0f0u) != 8) return 14;
    #|  if (__builtin_popcountl(0x0f0f0f0f0f0f0f0ful) != 32) return 15;
    #|  if (__builtin_popcountll(0x0f0f0f0f0f0f0f0full) != 32) return 16;
    #|  if (__builtin_parity(0xf0f1u) != 1) return 21;
    #|  if (__builtin_parityl(0x0f0f0f0f0f0f0f0ful) != 0) return 22;
    #|  if (__builtin_parityll(0x0f0f0f0f0f0f0f0eull) != 1) return 23;
    #|  return 0;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\tbsr\tecx, eax"), content="true")
  inspect(assembly.contains("\tbsr\trcx, rax"), content="true")
  inspect(assembly.contains("\tbsf\tecx, eax"), content="true")
  inspect(assembly.contains("\tbsf\trcx, rax"), content="true")
  inspect(assembly.contains("\tlea\teax, [rcx + 1]"), content="true")
  inspect(assembly.contains("\tbswap\teax"), content="true")
  inspect(assembly.contains("\tbswap\trax"), content="true")
  inspect(assembly.contains("\trol\teax, cl"), content="true")
  inspect(assembly.contains("\tror\trax, cl"), content="true")
  inspect(
    assembly.contains("\tmovabs\tr11, 6148914691236517205"),
    content="true",
  )
  inspect(assembly.contains("call\t__builtin_clz"), content="false")
  inspect(assembly.contains("call\t__builtin_ffs"), content="false")
  inspect(assembly.contains("call\t__builtin_bswap"), content="false")
  inspect(assembly.contains("call\t__builtin_bswap32"), content="false")
  inspect(assembly.contains("call\t__builtin_rotateleft"), content="false")
  inspect(assembly.contains("call\t__builtin_rotateright"), content="false")
  inspect(assembly.contains("call\t__builtin_rotateleft32"), content="false")
  inspect(assembly.contains("call\t__builtin_parity"), content="false")
  inspect(assembly.contains("call\t__builtin_popcount"), content="false")
}

///|
test "generate linux amd64 lowers alloca builtin" {
  let source =
    #|int touch(char *p) { return p[0] + p[31]; }
    #|int main(void) {
    #|  int n = 31;
    #|  char *p = __builtin_alloca(n + 1);
    #|  char *q;
    #|  p[0] = 3;
    #|  p[31] = 4;
    #|  q = __builtin_alloca(5);
    #|  q[0] = 5;
    #|  q[4] = 6;
    #|  if (((long)p & 15) != 0) return 1;
    #|  if (((long)q & 15) != 0) return 2;
    #|  return touch(p) + q[0] + q[4];
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\tadd\trax, 15"), content="true")
  inspect(assembly.contains("\tand\trax, -16"), content="true")
  inspect(assembly.contains("\tsub\trsp, rax"), content="true")
  inspect(assembly.contains("call\t__builtin_alloca"), content="false")
}

///|
test "generate linux amd64 lowers atomic builtins" {
  let source =
    #|int main(void) {
    #|  unsigned char b = 0;
    #|  unsigned char flag = 0;
    #|  unsigned short h = 0;
    #|  unsigned int w = 5;
    #|  _Atomic(unsigned int) a = 5;
    #|  unsigned int expected = 11;
    #|  unsigned int expected_ptr = 23;
    #|  unsigned int loaded = 0;
    #|  unsigned int desired = 19;
    #|  unsigned int old = 0;
    #|  __sync_synchronize();
    #|  __atomic_thread_fence(5);
    #|  __atomic_signal_fence(5);
    #|  __c11_atomic_thread_fence(5);
    #|  __c11_atomic_signal_fence(5);
    #|  if (!__atomic_always_lock_free(1, &w)) return 23;
    #|  if (!__atomic_always_lock_free(2, &w)) return 24;
    #|  if (!__atomic_is_lock_free(4, &w)) return 25;
    #|  if (!__c11_atomic_is_lock_free(8)) return 26;
    #|  if (__atomic_always_lock_free(16, &w)) return 27;
    #|  __atomic_store_n(&b, 1, 5);
    #|  __atomic_store_n(&h, 2, 5);
    #|  __atomic_load(&w, &loaded, 5);
    #|  if (loaded != 5) return 17;
    #|  __atomic_store(&w, &desired, 5);
    #|  if (w != 19) return 18;
    #|  desired = 23;
    #|  __atomic_exchange(&w, &desired, &old, 5);
    #|  if (old != 19) return 19;
    #|  desired = 29;
    #|  if (!__atomic_compare_exchange(&w, &expected_ptr, &desired, 0, 5, 5)) return 20;
    #|  expected_ptr = 23;
    #|  desired = 31;
    #|  if (__atomic_compare_exchange(&w, &expected_ptr, &desired, 0, 5, 5)) return 21;
    #|  if (expected_ptr != 29) return 22;
    #|  __atomic_store_n(&w, 5, 5);
    #|  if (__atomic_test_and_set(&flag, 5)) return 13;
    #|  if (!flag) return 14;
    #|  if (!__atomic_test_and_set(&flag, 5)) return 15;
    #|  __atomic_clear(&flag, 5);
    #|  if (flag) return 16;
    #|  if (__atomic_load_n(&b, 5) != 1) return 1;
    #|  if (__atomic_load_n(&h, 5) != 2) return 2;
    #|  if (__atomic_add_fetch(&w, 3, 5) != 8) return 3;
    #|  if (__atomic_fetch_xor(&w, 3, 5) != 8) return 4;
    #|  if (__atomic_exchange_n(&w, 13, 5) != 11) return 5;
    #|  expected = 13;
    #|  if (!__atomic_compare_exchange_n(&w, &expected, 17, 0, 5, 5)) return 6;
    #|  if (__atomic_and_fetch(&w, 7, 5) != 1) return 8;
    #|  if (__atomic_or_fetch(&w, 8, 5) != 9) return 9;
    #|  if (__atomic_xor_fetch(&w, 3, 5) != 10) return 10;
    #|  if (__atomic_fetch_nand(&w, 15, 5) != 10) return 11;
    #|  __atomic_store_n(&w, 10, 5);
    #|  if (__atomic_nand_fetch(&w, 15, 5) != ~10u) return 12;
    #|  if (__c11_atomic_fetch_add(&a, 3, 5) != 5) return 5;
    #|  if (__c11_atomic_exchange(&a, 11, 5) != 8) return 6;
    #|  if (__c11_atomic_compare_exchange_strong(&a, &expected, 19, 5, 5)) return 7;
    #|  expected = 11;
    #|  if (!__c11_atomic_compare_exchange_weak(&a, &expected, 23, 5, 5)) return 28;
    #|  return (int)__c11_atomic_load(&a, 5);
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\tmfence"), content="true")
  inspect(assembly.contains("\txchg\tBYTE PTR"), content="true")
  inspect(assembly.contains("\txchg\tWORD PTR"), content="true")
  inspect(assembly.contains("\tlock cmpxchg\tDWORD PTR"), content="true")
  inspect(assembly.contains("\tnot\tr11d"), content="true")
  inspect(assembly.contains("call\t__atomic_load"), content="false")
  inspect(assembly.contains("call\t__atomic_store"), content="false")
  inspect(assembly.contains("call\t__atomic_exchange"), content="false")
  inspect(assembly.contains("call\t__atomic_compare_exchange"), content="false")
  inspect(assembly.contains("call\t__atomic_load_n"), content="false")
  inspect(assembly.contains("call\t__atomic_store_n"), content="false")
  inspect(assembly.contains("call\t__atomic_test_and_set"), content="false")
  inspect(assembly.contains("call\t__atomic_clear"), content="false")
  inspect(assembly.contains("call\t__atomic_add_fetch"), content="false")
  inspect(assembly.contains("call\t__atomic_and_fetch"), content="false")
  inspect(assembly.contains("call\t__atomic_or_fetch"), content="false")
  inspect(assembly.contains("call\t__atomic_xor_fetch"), content="false")
  inspect(assembly.contains("call\t__atomic_fetch_nand"), content="false")
  inspect(assembly.contains("call\t__atomic_nand_fetch"), content="false")
  inspect(assembly.contains("call\t__atomic_exchange_n"), content="false")
  inspect(
    assembly.contains("call\t__atomic_compare_exchange_n"),
    content="false",
  )
  inspect(assembly.contains("call\t__c11_atomic_exchange"), content="false")
  inspect(
    assembly.contains("call\t__c11_atomic_compare_exchange_strong"),
    content="false",
  )
  inspect(
    assembly.contains("call\t__c11_atomic_compare_exchange_weak"),
    content="false",
  )
  inspect(assembly.contains("call\t__atomic_thread_fence"), content="false")
  inspect(assembly.contains("call\t__atomic_signal_fence"), content="false")
  inspect(assembly.contains("call\t__c11_atomic_thread_fence"), content="false")
  inspect(assembly.contains("call\t__c11_atomic_signal_fence"), content="false")
  inspect(assembly.contains("call\t__atomic_always_lock_free"), content="false")
  inspect(assembly.contains("call\t__atomic_is_lock_free"), content="false")
  inspect(assembly.contains("call\t__c11_atomic_is_lock_free"), content="false")
}

///|
test "generate linux amd64 lowers overflow builtins" {
  let source =
    #|int main(void) {
    #|  int i = 0;
    #|  unsigned int u = 0;
    #|  long long l = 0;
    #|  if (__builtin_add_overflow(1, 2, &i)) return 1;
    #|  if (!__builtin_sub_overflow(0u, 1u, &u)) return 2;
    #|  if (!__builtin_mul_overflow(2000000000, 2, &i)) return 3;
    #|  if (!__builtin_mul_overflow(0xffffffffu, 2u, &u)) return 4;
    #|  if (__builtin_add_overflow(l, 1LL, &l)) return 5;
    #|  if (!__builtin_sadd_overflow(2147483647, 1, &i)) return 6;
    #|  if (!__builtin_uadd_overflow(0xffffffffu, 1u, &u)) return 7;
    #|  if (!__builtin_ssubll_overflow(-9223372036854775807LL - 1LL, 1LL, &l)) return 8;
    #|  if (!__builtin_umul_overflow(0xffffffffu, 2u, &u)) return 9;
    #|  return i + (int)u + (int)l;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\tseto\tr11b"), content="true")
  inspect(assembly.contains("\tsetb\tr11b"), content="true")
  inspect(assembly.contains("\timul\tr10d"), content="true")
  inspect(assembly.contains("\tmul\tr10d"), content="true")
  inspect(assembly.contains("call\t__builtin_add_overflow"), content="false")
  inspect(assembly.contains("call\t__builtin_sub_overflow"), content="false")
  inspect(assembly.contains("call\t__builtin_mul_overflow"), content="false")
  inspect(assembly.contains("call\t__builtin_sadd_overflow"), content="false")
  inspect(assembly.contains("call\t__builtin_uadd_overflow"), content="false")
  inspect(assembly.contains("call\t__builtin_ssubll_overflow"), content="false")
  inspect(assembly.contains("call\t__builtin_umul_overflow"), content="false")
}

///|
test "generate linux amd64 lowers integer abs builtins" {
  let source =
    #|int main(void) {
    #|  if (__builtin_abs(-7) != 7) return 1;
    #|  if (__builtin_abs(5) != 5) return 2;
    #|  if (__builtin_labs(-1234567890123L) != 1234567890123L) return 3;
    #|  if (__builtin_llabs(-900000000000000000LL) != 900000000000000000LL) return 4;
    #|  return 0;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\tneg\teax"), content="true")
  inspect(assembly.contains("\tneg\trax"), content="true")
  inspect(assembly.contains("call\t__builtin_abs"), content="false")
  inspect(assembly.contains("call\t__builtin_labs"), content="false")
  inspect(assembly.contains("call\t__builtin_llabs"), content="false")
}

///|
test "generate linux amd64 lowers floating builtins" {
  let source =
    #|double fd(double x) { return __builtin_fabs(x); }
    #|float ff(float x) { return __builtin_fabsf(x); }
    #|int main(void) {
    #|  double nanv = __builtin_nan("");
    #|  float nanf = __builtin_nanf("");
    #|  double inf = __builtin_huge_val();
    #|  float inff = __builtin_inff();
    #|  if ((int)fd(-4.5) != 4) return 1;
    #|  if ((int)ff(-3.5f) != 3) return 2;
    #|  if (!(inf > 1000000.0)) return 3;
    #|  if (!(inff > 1000000.0f)) return 4;
    #|  if (nanv == nanv) return 5;
    #|  if (nanf == nanf) return 6;
    #|  if (!(nanv != nanv)) return 14;
    #|  if (!nanv) return 15;
    #|  if (nanv) { } else { return 16; }
    #|  if (!__builtin_isgreater(3.0, 2.0)) return 7;
    #|  if (!__builtin_isgreaterequal(3.0, 3.0)) return 8;
    #|  if (!__builtin_isless(2.0, 3.0)) return 9;
    #|  if (!__builtin_islessequal(3.0, 3.0)) return 10;
    #|  if (!__builtin_islessgreater(2.0, 3.0)) return 11;
    #|  if (!__builtin_isunordered(nanv, 1.0)) return 12;
    #|  if (__builtin_isless(nanv, 1.0)) return 13;
    #|  if (!__builtin_isnan(nanv)) return 17;
    #|  if (!__builtin_isnanf(nanf)) return 18;
    #|  if (!__builtin_isinf(inf)) return 19;
    #|  if (!__builtin_isinff(inff)) return 20;
    #|  if (!__builtin_isfinite(4.0)) return 21;
    #|  if (__builtin_isfinite(inf)) return 22;
    #|  if (!__builtin_isnormal(4.0)) return 23;
    #|  if (__builtin_isnormal(0.0)) return 24;
    #|  if (!__builtin_signbit(-0.0)) return 25;
    #|  if (__builtin_signbit(1.0)) return 26;
    #|  if (!__builtin_signbitf(-0.0f)) return 27;
    #|  if ((int)__builtin_copysign(3.0, -1.0) != -3) return 28;
    #|  if ((int)__builtin_copysign(-3.0, 1.0) != 3) return 29;
    #|  if ((int)__builtin_copysignf(2.0f, -1.0f) != -2) return 30;
    #|  if (!__builtin_signbit(__builtin_copysign(0.0, -1.0))) return 31;
    #|  if ((int)__builtin_sqrt(81.0) != 9) return 32;
    #|  if ((int)__builtin_sqrtf(25.0f) != 5) return 33;
    #|  if (!__builtin_isnan(__builtin_sqrt(-1.0))) return 34;
    #|  return 0;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\tandpd\txmm0, xmm1"), content="true")
  inspect(assembly.contains("\tandps\txmm0, xmm1"), content="true")
  inspect(assembly.contains("\tmovq\txmm0, rax"), content="true")
  inspect(assembly.contains("\tmovd\txmm0, eax"), content="true")
  inspect(assembly.contains("\tucomisd\txmm0, xmm1"), content="true")
  inspect(assembly.contains("\tsetnp\tdl"), content="true")
  inspect(assembly.contains("\tsetp\tdl"), content="true")
  inspect(assembly.contains("\tjp\t"), content="true")
  inspect(assembly.contains("\tsqrtsd\txmm0, xmm0"), content="true")
  inspect(assembly.contains("\tsqrtss\txmm0, xmm0"), content="true")
  inspect(assembly.contains("call\t__builtin_fabs"), content="false")
  inspect(assembly.contains("call\t__builtin_fabsf"), content="false")
  inspect(assembly.contains("call\t__builtin_nan"), content="false")
  inspect(assembly.contains("call\t__builtin_isgreater"), content="false")
  inspect(assembly.contains("call\t__builtin_isnan"), content="false")
  inspect(assembly.contains("call\t__builtin_isinf"), content="false")
  inspect(assembly.contains("call\t__builtin_isfinite"), content="false")
  inspect(assembly.contains("call\t__builtin_isnormal"), content="false")
  inspect(assembly.contains("call\t__builtin_signbit"), content="false")
  inspect(assembly.contains("call\t__builtin_copysign"), content="false")
  inspect(assembly.contains("call\t__builtin_sqrt"), content="false")
}

///|
test "generate linux amd64 aggregate va_arg state" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|struct Pair { long a; long b; };
    #|struct DPair { double a; double b; };
    #|struct Big { long a; long b; long c; };
    #|struct Nine { char v[9]; };
    #|struct F3 { float v[3]; };
    #|struct __attribute__((packed)) Packed { char c; int x; };
    #|int read_pair(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  struct Pair p = __builtin_va_arg(ap, struct Pair);
    #|  __builtin_va_end(ap);
    #|  return (int)(p.a + p.b);
    #|}
    #|int read_dpair(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  struct DPair p = __builtin_va_arg(ap, struct DPair);
    #|  __builtin_va_end(ap);
    #|  return (int)(p.a + p.b);
    #|}
    #|int read_big(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  struct Big p = __builtin_va_arg(ap, struct Big);
    #|  __builtin_va_end(ap);
    #|  return (int)(p.a + p.b + p.c);
    #|}
    #|int read_nine(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  struct Nine p = __builtin_va_arg(ap, struct Nine);
    #|  __builtin_va_end(ap);
    #|  return p.v[0] + p.v[8];
    #|}
    #|int read_f3(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  struct F3 p = __builtin_va_arg(ap, struct F3);
    #|  __builtin_va_end(ap);
    #|  return (int)(p.v[0] + p.v[1] + p.v[2]);
    #|}
    #|int read_pair_stack(int a, int b, int c, int d, int e, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, e);
    #|  struct Pair p = __builtin_va_arg(ap, struct Pair);
    #|  __builtin_va_end(ap);
    #|  return (int)(p.a + p.b);
    #|}
    #|int read_packed_stack(int a, int b, int c, int d, int e, int f, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, f);
    #|  struct Packed p = __builtin_va_arg(ap, struct Packed);
    #|  __builtin_va_end(ap);
    #|  return p.c + p.x;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("cmp\teax, 32"), content="true")
  inspect(assembly.contains("cmp\tecx, 144"), content="true")
  inspect(assembly.contains("add\tDWORD PTR [r11], 16"), content="true")
  inspect(assembly.contains("add\tDWORD PTR [r11 + 4], 32"), content="true")
  inspect(assembly.contains("lea\tr10, [rbp -"), content="true")
  inspect(assembly.contains("mov\tQWORD PTR [r11 + 8], rax"), content="true")
  inspect(assembly.contains("mov\tal, BYTE PTR [r11 + 4]"), content="true")
  inspect(assembly.contains("mov\tBYTE PTR [r10 + 4], al"), content="true")
  inspect(assembly.contains("mov\tBYTE PTR [r10 + 8], dl"), content="true")
  inspect(assembly.contains("movss\tDWORD PTR [r10 + 8], xmm0"), content="true")
}

///|
test "generate linux amd64 stack call arguments" {
  let source =
    #|int seventh(int a, int b, int c, int d, int e, int f, int g) { return g; }
    #|double ninth(double a, double b, double c, double d, double e, double f, double g, double h, double i) { return i; }
    #|int main(void) { return seventh(1,2,3,4,5,6,21) + (int)ninth(1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,21.0); }
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("mov\trax, QWORD PTR [rbp + 16]"), content="true")
  inspect(
    assembly.contains("movsd\txmm0, QWORD PTR [rbp + 16]"),
    content="true",
  )
  inspect(assembly.contains("mov\tQWORD PTR [rsp], rax"), content="true")
  inspect(assembly.contains("and\trsp, -16"), content="true")
}

///|
test "generate linux amd64 scalar compound assignment operators" {
  let source =
    #|int main(void) {
    #|  int x = 5;
    #|  x += 3;
    #|  x <<= 1;
    #|  x >>= 1;
    #|  return x;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("add\trax, r10"), content="true")
  inspect(assembly.contains("shl\trax, cl"), content="true")
  inspect(assembly.contains("sar\trax, cl"), content="true")
}

///|
test "generate linux amd64 pointer compound assignment scales element size" {
  let source =
    #|int main(void) {
    #|  int values[4];
    #|  int *p = values;
    #|  p += 2;
    #|  p -= 1;
    #|  return p - values;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("imul\trax, rax, 4"), content="true")
  inspect(assembly.contains("add\trax, r10"), content="true")
  inspect(assembly.contains("sub\trax, r10"), content="true")
  inspect(assembly.contains("idiv\tr10"), content="true")
}

///|
test "generate linux amd64 unsigned scalar operators" {
  let source =
    #|int main(void) {
    #|  unsigned int max = 4294967295U;
    #|  unsigned int wrap = max + 1U;
    #|  return wrap == 0U && max / 2U == 2147483647U && max % 2U == 1U && max > 1U && !(max < 1U) && max == -1 && (max >> 31) == 1U;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("div\tr10"), content="true")
  inspect(assembly.contains("shr\trax, cl"), content="true")
  inspect(assembly.contains("seta\tal"), content="true")
  inspect(assembly.contains("setb\tal"), content="true")
  inspect(assembly.contains("mov\teax, eax"), content="true")
}

///|
test "generate linux amd64 unsigned long to floating conversions" {
  let source =
    #|int main(void) {
    #|  unsigned long one = 1;
    #|  unsigned long hi = one << 63;
    #|  double d = (double)hi;
    #|  float f = (float)hi;
    #|  return d > 0.0 && f > 0.0f;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\ttest\trax, rax"), content="true")
  inspect(assembly.contains("\tjns\t.L"), content="true")
  inspect(assembly.contains("\tshr\tr10, 1"), content="true")
  inspect(assembly.contains("\taddsd\txmm0, xmm0"), content="true")
  inspect(assembly.contains("\taddss\txmm0, xmm0"), content="true")
}

///|
test "generate linux amd64 scalar casts assignments and returns" {
  let source =
    #|_Bool truthy(long x) { return x; }
    #|int main(void) {
    #|  _Bool b = 256;
    #|  _Bool f = 0.5;
    #|  signed char c = (signed char)255;
    #|  unsigned char u = (unsigned char)-1;
    #|  short s = (short)65535;
    #|  return b && f && c == -1 && u == 255 && s == -1 && (unsigned char)300 == 44 && truthy(256);
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("cmp\trax, 0"), content="true")
  inspect(assembly.contains("setne\tal"), content="true")
  inspect(assembly.contains("ucomisd\txmm0, xmm1"), content="true")
  inspect(assembly.contains("movsx\trax, al"), content="true")
  inspect(assembly.contains("movzx\trax, al"), content="true")
  inspect(assembly.contains("movsx\trax, ax"), content="true")
}

///|
test "generate linux amd64 prototype scalar call conversions" {
  let source =
    #|double as_double(double x) { return x; }
    #|int as_int(int x) { return x; }
    #|_Bool as_bool(_Bool x) { return x; }
    #|int main(void) {
    #|  return (int)as_double(42) + as_int(42.9) + as_bool(256);
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("cvtsi2sd\txmm0, rax"), content="true")
  inspect(assembly.contains("cvttsd2si\trax, xmm0"), content="true")
  inspect(assembly.contains("setne\tal"), content="true")
  inspect(assembly.contains("movsd\txmm0, QWORD PTR"), content="true")
  inspect(assembly.contains("call\tas_double"), content="true")
  inspect(assembly.contains("call\tas_int"), content="true")
  inspect(assembly.contains("call\tas_bool"), content="true")
}

///|
test "generate linux amd64 narrow scalar call returns" {
  let source =
    #|_Bool ret_bool(void);
    #|signed char ret_schar(void);
    #|unsigned char ret_uchar(void);
    #|short ret_short(void);
    #|unsigned short ret_ushort(void);
    #|unsigned int ret_uint(void);
    #|int ret_int(void);
    #|int main(void) {
    #|  return ret_bool() + ret_schar() + ret_uchar() + ret_short() + ret_ushort() + ret_uint() + ret_int();
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("call\tret_bool\n\tmovzx\trax, al"), content="true")
  inspect(
    assembly.contains("call\tret_schar\n\tmovsx\trax, al"),
    content="true",
  )
  inspect(
    assembly.contains("call\tret_uchar\n\tmovzx\trax, al"),
    content="true",
  )
  inspect(
    assembly.contains("call\tret_short\n\tmovsx\trax, ax"),
    content="true",
  )
  inspect(
    assembly.contains("call\tret_ushort\n\tmovzx\trax, ax"),
    content="true",
  )
  inspect(assembly.contains("call\tret_uint\n\tmov\teax, eax"), content="true")
  inspect(
    assembly.contains("call\tret_int\n\tmovsxd\trax, eax"),
    content="true",
  )
}

///|
test "generate linux amd64 int128 call return and va_arg ABI" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|__uint128_t make128(void);
    #|int take128(__uint128_t x);
    #|__uint128_t id128(__uint128_t x) { return x; }
    #|__uint128_t stack128(long a, long b, long c, long d, long e, __uint128_t x) { return x; }
    #|int read128(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  __uint128_t x = __builtin_va_arg(ap, __uint128_t);
    #|  __builtin_va_end(ap);
    #|  return take128(x);
    #|}
    #|int main(void) {
    #|  __uint128_t x = id128(make128());
    #|  return take128(x) + take128(stack128(1, 2, 3, 4, 5, x)) + read128(0, x);
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\tmov\tQWORD PTR [rbp - 16], rdi"), content="true")
  inspect(assembly.contains("\tmov\tQWORD PTR [rbp - 8], rsi"), content="true")
  inspect(assembly.contains("\tmov\trdx, QWORD PTR [rax + 8]"), content="true")
  inspect(assembly.contains("\tmov\trsi, QWORD PTR"), content="true")
  inspect(assembly.contains("\tmov\trdx, QWORD PTR [rbp + 24]"), content="true")
  inspect(assembly.contains("cmp\teax, 32"), content="true")
  inspect(assembly.contains("add\tDWORD PTR [r11], 16"), content="true")
}

///|
test "generate linux amd64 int128 truthiness checks both halves" {
  let source =
    #|__uint128_t make128(void);
    #|int truth128(void) {
    #|  __uint128_t x = make128();
    #|  _Bool b = x;
    #|  if (!x) return 1;
    #|  if (x) return b;
    #|  return 2;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\tor\trax, rdx"), content="true")
  inspect(assembly.contains("\tsetne\tal"), content="true")
  inspect(assembly.contains("\tsete\tal"), content="true")
}

///|
test "generate linux amd64 int128 arithmetic and comparisons" {
  let source =
    #|int use128(__uint128_t a, __uint128_t b, __int128_t s, int n) {
    #|  __uint128_t sum = a + b;
    #|  __uint128_t diff = a - b;
    #|  __uint128_t prod = a * b;
    #|  __uint128_t quo = a / b;
    #|  __uint128_t rem = a % b;
    #|  __uint128_t bits = (a & b) | (a ^ b);
    #|  __uint128_t left = a << n;
    #|  __uint128_t right = a >> n;
    #|  __int128_t signed_right = s >> n;
    #|  __int128_t signed_quo = s / (__int128_t)n;
    #|  __int128_t signed_rem = s % (__int128_t)n;
    #|  __int128_t neg = -s;
    #|  __uint128_t inv = ~a;
    #|  return sum != diff && prod >= quo && rem <= bits && left != right && signed_right < neg && signed_quo != signed_rem && inv > 0;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\tadc\trdx, r11"), content="true")
  inspect(assembly.contains("\tsbb\trdx, r11"), content="true")
  inspect(assembly.contains("\tmul\tr10"), content="true")
  inspect(assembly.contains("\tcall\t__udivti3"), content="true")
  inspect(assembly.contains("\tcall\t__umodti3"), content="true")
  inspect(assembly.contains("\tcall\t__divti3"), content="true")
  inspect(assembly.contains("\tcall\t__modti3"), content="true")
  inspect(assembly.contains("\tshld\trdx, rax, cl"), content="true")
  inspect(assembly.contains("\tshrd\trax, rdx, cl"), content="true")
  inspect(assembly.contains("\tsar\trdx, cl"), content="true")
  inspect(assembly.contains("\tnot\trdx"), content="true")
  inspect(assembly.contains("\tsbb\trdx, 0"), content="true")
  inspect(assembly.contains("\tsetl\tal"), content="true")
  inspect(assembly.contains("\tsetae\tal"), content="true")
}

///|
test "generate linux amd64 compound literals and aggregate initializers" {
  let source =
    #|typedef union ValueUnion { int int32; void *ptr; } ValueUnion;
    #|typedef struct Value { ValueUnion u; long tag; } Value;
    #|struct Pair { int a; int b; };
    #|int main(void) {
    #|  Value v;
    #|  struct Pair p = { .b = 5, .a = 6 };
    #|  int arr[5] = { 1, [3] = 4 };
    #|  int *tmp = (int[5]){ 10, 20, [4] = 30 };
    #|  int scalar = (int){ 3 };
    #|  v = (Value){ (ValueUnion){ .int32 = 7 }, 4 };
    #|  return v.u.int32 + (int)v.tag + p.a + p.b + arr[0] + arr[3] + tmp[0] + tmp[1] + tmp[4] + scalar;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("__kimicc_compound_literal_"), content="false")
  inspect(assembly.contains("\tmov\tDWORD PTR [r10], eax"), content="true")
  inspect(assembly.contains("\tmov\tQWORD PTR [r10], rax"), content="true")
  inspect(assembly.contains("\tmov\tDWORD PTR [rax"), content="true")
}

///|
test "generate linux amd64 global aggregate initializers" {
  let source =
    #|struct GInner { char c; int x; };
    #|struct GOuter { char tag; struct GInner inner; int tail; };
    #|struct GBits { unsigned a : 3; signed b : 4; unsigned c : 5; };
    #|struct GRefs { int *first; int *tail; int (*fn)(int); };
    #|struct GNode { int value; struct GNode *next; };
    #|union GU { int i; char c[4]; };
    #|union GUBits { unsigned a : 3; signed b : 4; };
    #|int gadd1(int x) { return x + 1; }
    #|int garr[5] = { 1, [3] = 4 };
    #|struct GOuter gout = { .tail = 9, .inner = { .x = 7, .c = 2 }, .tag = 1 };
    #|struct GBits gbits = { .a = 5, .b = -3, .c = 17 };
    #|int *gptr = garr + 3;
    #|int *gaddr = &garr[4];
    #|int (*gfp)(int) = gadd1;
    #|int *gptrs[3] = { garr, garr + 2, &garr[4] };
    #|struct GRefs grefs = { .tail = garr + 4, .fn = gadd1, .first = &garr[1] };
    #|int *gmember = &gout.inner.x;
    #|int *gmember_next = &gout.inner.x + 1;
    #|struct GNode gnode2 = { 2, 0 };
    #|struct GNode gnode1 = { .next = &gnode2, .value = 1 };
    #|struct GNode *gnodes[2] = { &gnode1, &gnode2 };
    #|union GU gu = { .c = { 65, 66, 0, 0 } };
    #|union GUBits gubits = { .b = -3 };
    #|char gstr[6] = "hey";
    #|int main(void) {
    #|  return garr[0] + garr[3] + gout.tag + gout.inner.c + gout.inner.x + gout.tail + gbits.a + gbits.b + gbits.c + gu.c[0] + gu.c[1] + gubits.b + gstr[0];
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("garr:"), content="true")
  inspect(assembly.contains("gout:"), content="true")
  inspect(assembly.contains("gbits:"), content="true")
  inspect(assembly.contains("gptr:"), content="true")
  inspect(assembly.contains("gaddr:"), content="true")
  inspect(assembly.contains("gfp:"), content="true")
  inspect(assembly.contains("gptrs:"), content="true")
  inspect(assembly.contains("grefs:"), content="true")
  inspect(assembly.contains("gmember:"), content="true")
  inspect(assembly.contains("gnode1:"), content="true")
  inspect(assembly.contains("gnodes:"), content="true")
  inspect(assembly.contains("gu:"), content="true")
  inspect(assembly.contains("gubits:"), content="true")
  inspect(assembly.contains("gstr:"), content="true")
  inspect(assembly.contains("\t.long\t1"), content="true")
  inspect(assembly.contains("\t.long\t4"), content="true")
  inspect(assembly.contains("\t.byte\t2"), content="true")
  inspect(assembly.contains("\t.long\t7"), content="true")
  inspect(assembly.contains("\t.long\t9"), content="true")
  inspect(assembly.contains("\t.long\t2285"), content="true")
  inspect(assembly.contains("\t.long\t13"), content="true")
  inspect(assembly.contains("\t.quad\tgarr+12"), content="true")
  inspect(assembly.contains("\t.quad\tgarr+16"), content="true")
  inspect(assembly.contains("\t.quad\tgadd1"), content="true")
  inspect(assembly.contains("\t.quad\tgarr+8"), content="true")
  inspect(assembly.contains("\t.quad\tgarr+4"), content="true")
  inspect(assembly.contains("\t.quad\tgout+8"), content="true")
  inspect(assembly.contains("\t.quad\tgout+8+4"), content="true")
  inspect(assembly.contains("\t.quad\tgnode2"), content="true")
  inspect(assembly.contains("\t.quad\tgnode1"), content="true")
  inspect(assembly.contains("\t.byte\t65"), content="true")
  inspect(assembly.contains("\t.byte\t66"), content="true")
  inspect(assembly.contains("\t.asciz\t\"hey\""), content="true")
}

///|
test "generate linux amd64 switch dispatch" {
  let source =
    #|int pick(int x) {
    #|  switch (x) {
    #|    default: return 30;
    #|    case 1: return 10;
    #|    case 2: return 20;
    #|  }
    #|}
    #|int unsigned_pick(unsigned x) {
    #|  switch (x) {
    #|    case -7: return 5;
    #|    case 3: return 6;
    #|    default: return 7;
    #|  }
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\tcmp\teax, r10d"), content="true")
  inspect(assembly.contains("\tmov\tr10d, -7"), content="true")
  inspect(assembly.contains("\tje\t.L"), content="true")
  inspect(assembly.contains("__kimicc_case_"), content="false")
}

///|
test "generate linux amd64 small aggregate call arguments" {
  let source =
    #|struct Pair { long a; long b; };
    #|int sum(struct Pair p) { return (int)(p.a + p.b); }
    #|int tail(int a, int b, int c, int d, int e, int f, struct Pair p) { return (int)(p.a + p.b); }
    #|int main(void) { struct Pair p; p.a = 19; p.b = 23; return sum(p) + tail(1,2,3,4,5,6,p); }
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("mov\tQWORD PTR [rbp - 16], rdi"), content="true")
  inspect(assembly.contains("mov\tQWORD PTR [rbp - 8], rsi"), content="true")
  inspect(assembly.contains("mov\trdi, QWORD PTR"), content="true")
  inspect(assembly.contains("mov\trsi, QWORD PTR"), content="true")
  inspect(assembly.contains("mov\trax, QWORD PTR [rbp + 16]"), content="true")
  inspect(assembly.contains("mov\trax, QWORD PTR [rbp + 24]"), content="true")
}

///|
test "generate linux amd64 small aggregate returns" {
  let source =
    #|struct Pair { long a; long b; };
    #|struct Pair make(long a, long b) { struct Pair p; p.a = a; p.b = b; return p; }
    #|int sum(struct Pair p) { return (int)(p.a + p.b); }
    #|int main(void) { struct Pair p; p = make(19, 23); return sum(p); }
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("mov\trax, QWORD PTR [r10]"), content="true")
  inspect(assembly.contains("mov\trdx, QWORD PTR [r10 + 8]"), content="true")
  inspect(assembly.contains("mov\tQWORD PTR [r10], rax"), content="true")
  inspect(assembly.contains("mov\tQWORD PTR [r10 + 8], rdx"), content="true")
}

///|
test "generate linux amd64 aggregate object copies are exact size" {
  let source =
    #|struct Tiny { char c; };
    #|struct Wrap { struct Tiny t; char guard; };
    #|struct Tiny make_tiny(char c) { struct Tiny t; t.c = c; return t; }
    #|int main(void) {
    #|  struct Wrap w;
    #|  struct Tiny a;
    #|  w.t.c = 1;
    #|  w.guard = 77;
    #|  a.c = 2;
    #|  w.t = a;
    #|  if (w.guard != 77) return 1;
    #|  w.t = make_tiny(3);
    #|  if (w.guard != 77) return 2;
    #|  return w.t.c;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\tmov\tal, BYTE PTR [r11]"), content="true")
  inspect(assembly.contains("\tmov\tBYTE PTR [r10], al"), content="true")
}

///|
test "generate linux amd64 sse aggregate call and return" {
  let source =
    #|struct DPair { double a; double b; };
    #|struct DPair make(double a, double b) { struct DPair p; p.a = a; p.b = b; return p; }
    #|double sum(struct DPair p) { return p.a + p.b; }
    #|double tail(double a, double b, double c, double d, double e, double f, double g, double h, struct DPair p) { return p.a + p.b; }
    #|int main(void) { struct DPair p; p = make(19.5, 22.5); return (int)sum(p) + (int)tail(1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,p); }
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("movsd\txmm0, QWORD PTR [r10]"), content="true")
  inspect(assembly.contains("movsd\txmm1, QWORD PTR [r10 + 8]"), content="true")
  inspect(assembly.contains("movsd\tQWORD PTR [r10], xmm0"), content="true")
  inspect(assembly.contains("movsd\tQWORD PTR [r10 + 8], xmm1"), content="true")
  inspect(
    assembly.contains("movsd\tQWORD PTR [rbp - 16], xmm0"),
    content="true",
  )
  inspect(assembly.contains("movsd\tQWORD PTR [rbp - 8], xmm1"), content="true")
  inspect(assembly.contains("mov\trax, QWORD PTR [rbp + 16]"), content="true")
  inspect(assembly.contains("mov\trax, QWORD PTR [rbp + 24]"), content="true")
}

///|
test "generate linux amd64 mixed aggregate call and return" {
  let source =
    #|struct Mix { long a; double b; };
    #|struct Rev { double a; long b; };
    #|struct Mix make(long a, double b) { struct Mix p; p.a = a; p.b = b; return p; }
    #|struct Rev flip(double a, long b) { struct Rev p; p.a = a; p.b = b; return p; }
    #|int sum(struct Mix p) { return (int)p.a + (int)p.b; }
    #|int rsum(struct Rev p) { return (int)p.a + (int)p.b; }
    #|int tail(int a, int b, int c, int d, int e, int f, struct Mix p) { return (int)p.a + (int)p.b; }
    #|int main(void) { struct Mix p; struct Rev q; p = make(19, 23.0); q = flip(23.0, 19); return sum(p) + rsum(q) + tail(1,2,3,4,5,6,p); }
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("mov\trax, QWORD PTR [r10]"), content="true")
  inspect(assembly.contains("movsd\txmm0, QWORD PTR [r10 + 8]"), content="true")
  inspect(assembly.contains("movsd\txmm0, QWORD PTR [r10]"), content="true")
  inspect(assembly.contains("mov\trax, QWORD PTR [r10 + 8]"), content="true")
  inspect(assembly.contains("mov\tQWORD PTR [r10], rax"), content="true")
  inspect(assembly.contains("movsd\tQWORD PTR [r10 + 8], xmm0"), content="true")
  inspect(assembly.contains("movsd\tQWORD PTR [r10], xmm0"), content="true")
  inspect(assembly.contains("mov\tQWORD PTR [r10 + 8], rax"), content="true")
  inspect(assembly.contains("mov\tQWORD PTR [rbp - 16], rdi"), content="true")
  inspect(assembly.contains("movsd\tQWORD PTR [rbp - 8], xmm0"), content="true")
  inspect(
    assembly.contains("movsd\tQWORD PTR [rbp - 16], xmm0"),
    content="true",
  )
  inspect(assembly.contains("mov\tQWORD PTR [rbp - 8], rdi"), content="true")
  inspect(assembly.contains("mov\trdi, QWORD PTR"), content="true")
  inspect(assembly.contains("movsd\txmm0, QWORD PTR"), content="true")
  inspect(assembly.contains("mov\trax, QWORD PTR [rbp + 16]"), content="true")
  inspect(assembly.contains("mov\trax, QWORD PTR [rbp + 24]"), content="true")
}

///|
test "generate linux amd64 recursive aggregate classification" {
  let source =
    #|struct IArray { int v[2]; };
    #|struct DArray { double v[2]; };
    #|struct Inner { long a; };
    #|struct NestedMix { struct Inner i; double d; };
    #|struct IArray make_i(int a, int b) { struct IArray p; p.v[0] = a; p.v[1] = b; return p; }
    #|struct DArray make_d(double a, double b) { struct DArray p; p.v[0] = a; p.v[1] = b; return p; }
    #|struct NestedMix make_n(long a, double b) { struct NestedMix p; p.i.a = a; p.d = b; return p; }
    #|int isum(struct IArray p) { return p.v[0] + p.v[1]; }
    #|double dsum(struct DArray p) { return p.v[0] + p.v[1]; }
    #|int nsum(struct NestedMix p) { return (int)p.i.a + (int)p.d; }
    #|int main(void) { return isum(make_i(1,0)) + (int)dsum(make_d(0.5,0.5)) + nsum(make_n(0,1.0)); }
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("mov\tQWORD PTR [rbp - 8], rdi"), content="true")
  inspect(
    assembly.contains("movsd\tQWORD PTR [rbp - 16], xmm0"),
    content="true",
  )
  inspect(assembly.contains("movsd\tQWORD PTR [rbp - 8], xmm1"), content="true")
  inspect(assembly.contains("mov\tQWORD PTR [rbp - 16], rdi"), content="true")
  inspect(assembly.contains("movsd\tQWORD PTR [rbp - 8], xmm0"), content="true")
  inspect(assembly.contains("movsd\txmm0, QWORD PTR [r10]"), content="true")
  inspect(assembly.contains("movsd\txmm1, QWORD PTR [r10 + 8]"), content="true")
  inspect(assembly.contains("movsd\tQWORD PTR [r10 + 8], xmm0"), content="true")
}

///|
test "generate linux amd64 partial integer aggregate eightbytes" {
  let source =
    #|struct Nine { char v[9]; };
    #|struct Nine make_nine(char tail) {
    #|  struct Nine n;
    #|  n.v[0] = 3;
    #|  n.v[8] = tail;
    #|  return n;
    #|}
    #|int sum_nine(struct Nine n) { return n.v[0] + n.v[8]; }
    #|int main(void) {
    #|  struct Nine n;
    #|  n = make_nine(39);
    #|  return sum_nine(n);
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("movzx\tedx, BYTE PTR [r10 + 8]"), content="true")
  inspect(assembly.contains("mov\tBYTE PTR [r10 + 8], dl"), content="true")
  inspect(assembly.contains("mov\tBYTE PTR [rbp - 8], sil"), content="true")
  inspect(assembly.contains("movzx\tesi, BYTE PTR [rsp +"), content="true")
}

///|
test "generate linux amd64 partial sse aggregate eightbytes" {
  let source =
    #|struct F3 { float v[3]; };
    #|struct F3 make_f3(float a, float b, float c) {
    #|  struct F3 f;
    #|  f.v[0] = a;
    #|  f.v[1] = b;
    #|  f.v[2] = c;
    #|  return f;
    #|}
    #|float sum_f3(struct F3 f) { return f.v[0] + f.v[1] + f.v[2]; }
    #|int main(void) {
    #|  struct F3 f;
    #|  f = make_f3(1.0f, 2.0f, 39.0f);
    #|  return (int)sum_f3(f);
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("movss\txmm1, DWORD PTR [r10 + 8]"), content="true")
  inspect(assembly.contains("movss\tDWORD PTR [r10 + 8], xmm1"), content="true")
  inspect(assembly.contains("movss\tDWORD PTR [rbp - 8], xmm1"), content="true")
  inspect(assembly.contains("movss\txmm1, DWORD PTR [rsp +"), content="true")
}

///|
test "generate linux amd64 honors alignas layout" {
  let source =
    #|struct AlignedBytes { char a; _Alignas(16) char b; char c; };
    #|_Alignas(32) long global_aligned = 1;
    #|int main(void) { return __builtin_offsetof(struct AlignedBytes, c); }
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("mov\trax, 17"), content="true")
  inspect(assembly.contains(".align\t32"), content="true")
}

///|
test "generate linux amd64 honors GNU aligned attributes" {
  let source =
    #|struct GnuAlignedBytes {
    #|  char a;
    #|  char b __attribute__((aligned(16)));
    #|  char c;
    #|};
    #|long gnu_global_aligned __attribute__((aligned(32))) = 1;
    #|int main(void) { return __builtin_offsetof(struct GnuAlignedBytes, c); }
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("mov\trax, 17"), content="true")
  inspect(assembly.contains(".align\t32"), content="true")
}

///|
test "generate linux amd64 packed aggregate layout and memory class" {
  let source =
    #|struct __attribute__((packed)) Packed { char c; int x; };
    #|int packed_sum(struct Packed p) { return p.c + p.x; }
    #|struct Packed make_packed(char c, int x) { struct Packed p; p.c = c; p.x = x; return p; }
    #|int main(void) {
    #|  struct Packed p;
    #|  p = make_packed(4, 38);
    #|  return __builtin_offsetof(struct Packed, x) + sizeof(struct Packed) + packed_sum(p);
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\tmov\trax, 1"), content="true")
  inspect(assembly.contains("\tmov\trax, 5"), content="true")
  inspect(assembly.contains("\tmov\trax, QWORD PTR [rbp + 16]"), content="true")
  inspect(assembly.contains("\tmov\tQWORD PTR [rbp - 8], rdi"), content="true")
}

///|
test "generate linux amd64 nested packed aggregate memory class" {
  let source =
    #|struct __attribute__((packed)) Packed { char c; int x; };
    #|struct Outer { char tag; struct Packed p; };
    #|int outer_sum(struct Outer o) { return o.tag + o.p.c + o.p.x; }
    #|struct Outer make_outer(char tag, char c, int x) { struct Outer o; o.tag = tag; o.p.c = c; o.p.x = x; return o; }
    #|int main(void) {
    #|  struct Outer o;
    #|  o = make_outer(1, 2, 39);
    #|  return __builtin_offsetof(struct Outer, p) + sizeof(struct Outer) + outer_sum(o);
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("\tmov\trax, 1"), content="true")
  inspect(assembly.contains("\tmov\trax, 6"), content="true")
  inspect(assembly.contains("outer_sum:\n\tpush\trbp"), content="true")
  inspect(assembly.contains("\tmov\trax, QWORD PTR [rbp + 16]"), content="true")
  inspect(assembly.contains("make_outer:\n\tpush\trbp"), content="true")
  inspect(assembly.contains("\tmov\tQWORD PTR [rbp - 8], rdi"), content="true")
}

///|
test "generate linux amd64 realigns over-aligned local frame" {
  let source =
    #|int aligned_local(void) {
    #|  _Alignas(32) char buf[32];
    #|  long p = (long)&buf[0];
    #|  return (int)(p & 31);
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("push\tr13"), content="true")
  inspect(assembly.contains("and\trsp, -32"), content="true")
  inspect(assembly.contains("mov\tr13, rsp"), content="true")
  inspect(assembly.contains("lea\trax, [r13 -"), content="true")
  inspect(assembly.contains("mov\tr13, QWORD PTR [rbp - 8]"), content="true")
}

///|
test "generate linux amd64 memory aggregate arguments and returns" {
  let source =
    #|struct Big { long a; long b; long c; };
    #|struct Big make_big(long a, long b, long c) { struct Big p; p.a = a; p.b = b; p.c = c; return p; }
    #|int big_sum(struct Big p) { return (int)(p.a + p.b + p.c); }
    #|int big_tail(int a, int b, int c, int d, int e, int f, struct Big p) { return big_sum(p); }
    #|int main(void) { struct Big p; p.a = 0; p.b = 1; p.c = 0; return big_sum(p) + big_tail(1,2,3,4,5,6,p) + big_sum(make_big(0,1,0)); }
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("mov\tQWORD PTR [rbp - 8], rdi"), content="true")
  inspect(assembly.contains("mov\tQWORD PTR [rbp - 16], rsi"), content="true")
  inspect(assembly.contains("mov\tr10, QWORD PTR [rbp - 8]"), content="true")
  inspect(assembly.contains("lea\trax, [rbp -"), content="true")
  inspect(assembly.contains("mov\trdi, rax"), content="true")
  inspect(assembly.contains("call\tmake_big"), content="true")
  inspect(assembly.contains("mov\trax, QWORD PTR [rbp + 16]"), content="true")
  inspect(assembly.contains("mov\trax, QWORD PTR [rbp + 24]"), content="true")
  inspect(assembly.contains("mov\trax, QWORD PTR [rbp + 32]"), content="true")
  inspect(assembly.contains("mov\tQWORD PTR [rsp + 16], rax"), content="true")
}

///|
test "generate linux amd64 bit-field read write and compound assignment" {
  let source =
    #|struct Bits { unsigned int a : 3; int b : 4; unsigned int c : 5; };
    #|int main(void) {
    #|  struct Bits bits;
    #|  bits.a = 5;
    #|  bits.b = -3;
    #|  bits.c = 17;
    #|  bits.a += 1;
    #|  bits.c >>= 1;
    #|  return (int)bits.a + bits.b + (int)bits.c;
    #|}
  let prog = @parser.parse(source)
  let target = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => abort("target parse failed")
  }
  let assembly = @codegen.generate_assembly_for_target(prog, target)
  inspect(assembly.contains("shr\trax, 3"), content="true")
  inspect(assembly.contains("shl\trax, 60"), content="true")
  inspect(assembly.contains("sar\trax, 60"), content="true")
  inspect(assembly.contains("and\trdx, r11"), content="true")
  inspect(assembly.contains("or\trdx, rax"), content="true")
  inspect(assembly.contains("mov\tDWORD PTR [r10], edx"), content="true")
}

///|
test "generate function with params" {
  let source = "int add(int a, int b) { return a + b; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("_add:"), content="true")
  inspect(assembly.contains("add\tx9, x9, x10"), content="true")
}

///|
test "generate if statement" {
  let source = "int main() { if (1) return 2; else return 3; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("cbz\tx9,"), content="true")
  inspect(assembly.contains("b\tL"), content="true")
}

///|
test "generate while loop" {
  let source = "int main() { while (1) return 0; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains(":"), content="true")
}

///|
test "generate large constant" {
  let source = "int main() { return 1114111; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  // 1114111 = 0x10FFFF → movz + movk
  inspect(assembly.contains("movz\tx9, #65535"), content="true")
  inspect(assembly.contains("movk\tx9, #16, lsl #16"), content="true")
}

///|
test "generate negative large constant" {
  let source = "int main() { return -1640562687; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  // Parsed as Unary("-", Number(1640562687)) → load then neg
  // 1640562687 = 0x61C8FFFF: low=65535, high=25032
  inspect(assembly.contains("movz\tx9, #65535"), content="true")
  inspect(assembly.contains("movk\tx9, #25032, lsl #16"), content="true")
  inspect(assembly.contains("neg\tx9, x9"), content="true")
}

///|
test "generate switch statement" {
  let source = "int main() { int x = 2; switch (x) { case 1: return 10; case 2: return 20; default: return 0; } }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  // No label in the assembly should contain a space
  let lines = assembly.split("\n")
  for line in lines {
    let s = line.to_owned()
    // Labels end with ':'
    if s.has_suffix(":") && s.contains(" ") {
      abort("Label contains space: " + s)
    }
  }
}

///|
test "goto labels are scoped per function" {
  let source =
    #|int foo() {
    #|  goto fail;
    #|fail:
    #|  return 1;
    #|}
    #|int bar() {
    #|  goto fail;
    #|fail:
    #|  return 2;
    #|}
    #|int main() { return foo() + bar(); }
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  // Each function's fail label should be prefixed with function name
  inspect(assembly.contains("_foo_label_fail:"), content="true")
  inspect(assembly.contains("_bar_label_fail:"), content="true")
  // Must not have a global unqualified _label_fail
  inspect(assembly.contains("\n_label_fail:"), content="false")
}

///|
test "collect locals with array init" {
  let source =
    #|int main() {
    #|    char buf[16];
    #|    char *p;
    #|    char src[] = "abcd";
    #|    char dst[8];
    #|    char buf2[8];
    #|    char buf3[6];
    #|    return 0;
    #|}
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let _ = codegen.generate(prog)
  // Just check it doesn't crash; the real check is in the assembly
}

///|
test "generate double literal return" {
  let source = "double foo() { return 3.14; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("_foo:"), content="true")
  inspect(assembly.contains("_fp_lit_foo_0:"), content="true")
  inspect(assembly.contains(".double\t3.14"), content="true")
  inspect(assembly.contains("fmov\td0, x9"), content="true")
}

///|
test "generate double local init" {
  let source = "double foo() { double x = 2.5; return x; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains(".double\t2.5"), content="true")
}

///|
test "generate float literal" {
  let source = "float foo() { return 1.5; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fmov\ts0, w9"), content="true")
}

///|
test "generate mixed int double params" {
  let source = "double foo(int a, double b, int c, double d) { return d; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  // Callee should store from x0, d0, x1, d1
  inspect(assembly.contains("str\tx0, [x29, #-32]"), content="true")
  inspect(assembly.contains("str\td0, [x29, #-24]"), content="true")
  inspect(assembly.contains("str\tx1, [x29, #-16]"), content="true")
  inspect(assembly.contains("str\td1, [x29, #-8]"), content="true")
}

///|
test "generate mixed int double args in call" {
  let source = "double foo(int a, double b); double bar() { return foo(1, 2.0); }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  // Caller should pass int in x0, double in d0
  inspect(assembly.contains("ldr\tx0, [sp, #0]"), content="true")
  inspect(assembly.contains("fmov\td0, x9"), content="true")
  // After call, should move return from d0
  inspect(assembly.contains("fmov\tx9, d0"), content="true")
}

///|
test "generate double addition" {
  let source = "double foo(double a, double b) { return a + b; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fadd\td9, d9, d10"), content="true")
}

///|
test "generate double subtraction" {
  let source = "double foo(double a, double b) { return a - b; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fsub\td9, d9, d10"), content="true")
}

///|
test "generate double multiplication" {
  let source = "double foo(double a, double b) { return a * b; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fmul\td9, d9, d10"), content="true")
}

///|
test "generate double division" {
  let source = "double foo(double a, double b) { return a / b; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fdiv\td9, d9, d10"), content="true")
}

///|
test "generate double negation" {
  let source = "double foo(double a) { return -a; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fneg\td9, d9"), content="true")
}

///|
test "generate double comparison" {
  let source = "int foo(double a, double b) { return a < b; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fcmp\td9, d10"), content="true")
  inspect(assembly.contains("cset\tx9, mi"), content="true")
}

///|
test "generate int to double cast" {
  let source = "double foo(int a) { return (double)a; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("scvtf\td9, x9"), content="true")
  inspect(assembly.contains("fmov\tx9, d9"), content="true")
}

///|
test "generate double to int cast" {
  let source = "int foo(double a) { return (int)a; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fcvtzs\tx9, d9"), content="true")
}

///|
test "generate float to double cast" {
  let source = "double foo(float a) { return (double)a; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fcvt\td9, s9"), content="true")
}

///|
test "generate double to float cast" {
  let source = "float foo(double a) { return (float)a; }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fcvt\ts9, d9"), content="true")
}

///|
test "generate builtin fabs" {
  let source = "double foo(double a) { return __builtin_fabs(a); }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fabs\td9, d9"), content="true")
}

///|
test "generate builtin fabsf" {
  let source = "float foo(float a) { return __builtin_fabsf(a); }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("fabs\ts9, s9"), content="true")
}

///|
test "generate builtin nanf" {
  let source = "float foo() { return __builtin_nanf(\"\"); }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("movz\tw9, #0x7FC0, lsl #16"), content="true")
}

///|
test "generate builtin huge_valf" {
  let source = "float foo() { return __builtin_huge_valf(); }"
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  inspect(assembly.contains("movz\tw9, #0x7F80, lsl #16"), content="true")
}
