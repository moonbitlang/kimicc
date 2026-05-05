///|
async test "e2e callback stored in struct field" {
  let source =
    #|struct Handler {
    #|  int (*step)(int, int);
    #|  int bias;
    #|};
    #|int add(int a, int b) {
    #|  return a + b;
    #|}
    #|int main() {
    #|  struct Handler h;
    #|  h.step = add;
    #|  h.bias = 22;
    #|  return h.step(20, h.bias);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e function local static persists" {
  let source =
    #|int next_value() {
    #|  static int x = 39;
    #|  x = x + 1;
    #|  return x;
    #|}
    #|int main() {
    #|  next_value();
    #|  next_value();
    #|  return next_value();
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e function pointer call through explicit dereference" {
  let source =
    #|int add(int a, int b) {
    #|  return a + b;
    #|}
    #|int main(void) {
    #|  int (*fp)(int, int) = add;
    #|  return (*fp)(20, 22);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e function pointer returned from function then dereferenced" {
  let source =
    #|int hash(const void *p, int n) {
    #|  return n + 40;
    #|}
    #|int (*pick(int key_class))(const void *, int) {
    #|  return &hash;
    #|}
    #|int main(void) {
    #|  int (*xHash)(const void *, int) = pick(1);
    #|  return (*xHash)("hi", 2);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e local array of structs with nested initializer" {
  let source =
    #|int answer(void) {
    #|  return 42;
    #|}
    #|int main(void) {
    #|  struct Builtin {
    #|    const char *zFunc;
    #|    void *pUserData;
    #|    int (*xFunc)(void);
    #|    void (*xDestroy)(void *);
    #|  } aBuiltin[] = {
    #|    { "snippet", 0, answer, 0 },
    #|    { "highlight", 0, answer, 0 },
    #|  };
    #|  if (aBuiltin[0].pUserData != 0) {
    #|    return 1;
    #|  }
    #|  return aBuiltin[1].xFunc();
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e static aggregate initializer folds sizeof typedef struct" {
  let source =
    #|typedef struct File File;
    #|struct File {
    #|  void *pMethod;
    #|  void *pVfs;
    #|  void *pInode;
    #|  int h;
    #|  unsigned char eFileLock;
    #|  unsigned short ctrlFlags;
    #|  int lastErrno;
    #|  void *lockingContext;
    #|  void *pPreallocatedUnused;
    #|  const char *zPath;
    #|  void *pShm;
    #|  int szChunk;
    #|  long mmapSize;
    #|  long mmapSizeActual;
    #|  long mmapSizeMax;
    #|  void *pMapRegion;
    #|  int sectorSize;
    #|  int deviceCharacteristics;
    #|};
    #|struct Vfs {
    #|  int iVersion;
    #|  int szOsFile;
    #|  int mxPathname;
    #|  void *pNext;
    #|  const char *zName;
    #|};
    #|int main(void) {
    #|  static struct Vfs aVfs[] = {
    #|    { 3, sizeof(File), 512, 0, "unix" },
    #|  };
    #|  if (aVfs[0].szOsFile != sizeof(File)) {
    #|    return 1;
    #|  }
    #|  return aVfs[0].szOsFile > 100 ? 42 : 2;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e global function pointer typedef cast initializer" {
  let source =
    #|typedef int (*syscall_ptr)(void);
    #|int answer(void) {
    #|  return 42;
    #|}
    #|static struct Entry {
    #|  const char *name;
    #|  syscall_ptr current;
    #|} table[] = {
    #|  { "answer", (syscall_ptr)answer },
    #|};
    #|int main(void) {
    #|  return table[0].current();
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e struct field pointer to function pointer stores full address" {
  let source =
    #|struct AutoExt {
    #|  unsigned int nExt;
    #|  int (**aExt)(int);
    #|};
    #|int answer(int x) {
    #|  return x + 1;
    #|}
    #|int main(void) {
    #|  int (*storage[1])(int);
    #|  struct AutoExt wsd;
    #|  wsd.nExt = 0;
    #|  wsd.aExt = storage;
    #|  wsd.aExt[wsd.nExt] = (int (*)(int))answer;
    #|  wsd.nExt++;
    #|  return wsd.aExt[0](41);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e function pointer returning pointer preserves return type" {
  let source =
    #|void *pick(void *p) {
    #|  return p;
    #|}
    #|int main(void) {
    #|  int value = 42;
    #|  void *(*fp)(void *) = pick;
    #|  int *result = (int *)fp(&value);
    #|  return *result;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e sqlite-style unsigned u64 atof threshold" {
  let source =
    #|typedef unsigned long long u64;
    #|static int is_digit(char c) {
    #|  return c >= '0' && c <= '9';
    #|}
    #|static double parse_decimal(const char *z, int n) {
    #|  const char *zEnd = z + n;
    #|  u64 s = 0;
    #|  int e = 0;
    #|  int d = 0;
    #|  u64 limit = ((0xffffffff | (((u64)0xffffffff) << 32)) - 9) / 10;
    #|  while (z < zEnd && is_digit(*z)) {
    #|    s = s * 10 + (*z - '0');
    #|    z++;
    #|    if (s >= limit) {
    #|      while (z < zEnd && is_digit(*z)) {
    #|        z++;
    #|        d++;
    #|      }
    #|    }
    #|  }
    #|  if (z < zEnd && *z == '.') {
    #|    z++;
    #|    while (z < zEnd && is_digit(*z)) {
    #|      if (s < limit) {
    #|        s = s * 10 + (*z - '0');
    #|        d--;
    #|      }
    #|      z++;
    #|    }
    #|  }
    #|  e = d;
    #|  while (e < 0 && (s % 10) == 0) {
    #|    s /= 10;
    #|    e++;
    #|  }
    #|  double r = (double)s;
    #|  while (e <= -1) {
    #|    r = r * 0.1;
    #|    e++;
    #|  }
    #|  while (e >= 1) {
    #|    r = r * 10.0;
    #|    e--;
    #|  }
    #|  return r;
    #|}
    #|int main(void) {
    #|  double x = parse_decimal("123.45", 6);
    #|  if (x < 123.44 || x > 123.46) return 1;
    #|  double y = parse_decimal("1.1", 3);
    #|  if (y < 1.09 || y > 1.11) return 2;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e sqlite-style fpdecode negated double cast" {
  let source =
    #|typedef unsigned long long u64;
    #|void *memcpy(void *dst, const void *src, unsigned long n);
    #|static void dekkerMul2(volatile double *x, double y, double yy) {
    #|  volatile double tx, ty, p, q, c, cc;
    #|  double hx, hy;
    #|  u64 m;
    #|  memcpy(&m, (void *)&x[0], 8);
    #|  m &= 0xfffffffffc000000LL;
    #|  memcpy(&hx, &m, 8);
    #|  tx = x[0] - hx;
    #|  memcpy(&m, &y, 8);
    #|  m &= 0xfffffffffc000000LL;
    #|  memcpy(&hy, &m, 8);
    #|  ty = y - hy;
    #|  p = hx * hy;
    #|  q = hx * ty + tx * hy;
    #|  c = p + q;
    #|  cc = p - c + q + tx * ty;
    #|  cc = x[0] * yy + x[1] * y + cc;
    #|  x[0] = c + cc;
    #|  x[1] = c - x[0];
    #|  x[1] += cc;
    #|}
    #|int main(void) {
    #|  double rr[2];
    #|  int exp = 0;
    #|  u64 v;
    #|  rr[0] = 1.1;
    #|  rr[1] = 0.0;
    #|  while (rr[0] < 9.223372036854774784e+07) {
    #|    exp -= 10;
    #|    dekkerMul2(rr, 1.0e+10, 0.0);
    #|  }
    #|  while (rr[0] < 9.22337203685477478e+17) {
    #|    exp -= 1;
    #|    dekkerMul2(rr, 1.0e+01, 0.0);
    #|  }
    #|  v = rr[1] < 0.0 ? (u64)rr[0] - (u64)(-rr[1]) : (u64)rr[0] + (u64)rr[1];
    #|  if (exp != -18) return 1;
    #|  if (v < 1099999999999999000ULL || v > 1100000000000002000ULL) return 2;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e mixed int double arithmetic promotes operands" {
  let source =
    #|typedef unsigned long size_t;
    #|void *malloc(size_t n);
    #|void *memset(void *p, int c, size_t n);
    #|typedef struct Bm25Data Bm25Data;
    #|struct Bm25Data {
    #|  int nPhrase;
    #|  double avgdl;
    #|  double *aIDF;
    #|  double *aFreq;
    #|};
    #|static int scaled(double v) {
    #|  return (int)(v * 10000000.0 + 0.5);
    #|}
    #|int main(void) {
    #|  const double k1 = 1.2;
    #|  const double b = 0.75;
    #|  Bm25Data *p = (Bm25Data*)malloc(sizeof(Bm25Data) + 2 * sizeof(double));
    #|  memset(p, 0, sizeof(Bm25Data) + 2 * sizeof(double));
    #|  p->nPhrase = 1;
    #|  p->aIDF = (double*)&p[1];
    #|  p->aFreq = &p->aIDF[p->nPhrase];
    #|  p->avgdl = (double)4 / (double)1;
    #|  p->aIDF[0] = 1e-6;
    #|  p->aFreq[0] += 1.0;
    #|  double D = (double)4;
    #|  double den = p->aFreq[0] + k1 * (1 - b + b * D / p->avgdl);
    #|  double score = p->aIDF[0] * (
    #|      (p->aFreq[0] * (k1 + 1.0)) / den
    #|  );
    #|  if ((int)(den * 10.0 + 0.5) != 22) return 1;
    #|  if (scaled(score) != 10) return 2;
    #|  if ((int)((1 + b) * 100.0 + 0.5) != 175) return 3;
    #|  if ((int)((2 * b) * 100.0 + 0.5) != 150) return 4;
    #|  if ((int)((1 - b) * 100.0 + 0.5) != 25) return 5;
    #|  double assigned = 1;
    #|  assigned = assigned + 2;
    #|  if ((int)(assigned * 10.0 + 0.5) != 30) return 6;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e octal integer literal preserves file mode value" {
  let source =
    #|typedef unsigned short mode_t;
    #|int main(void) {
    #|  mode_t m = 0;
    #|  mode_t m2 = m ? m : 0644;
    #|  if (m2 != 420) return 1;
    #|  if (0777 != 511) return 2;
    #|  if (010 == 10) return 3;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e file scope static symbols have internal linkage" {
  let left =
    #|static int shared = 40;
    #|static int helper(void) {
    #|  return shared;
    #|}
    #|int left(void) {
    #|  return helper();
    #|}
  let right =
    #|extern int left(void);
    #|static int shared = 2;
    #|static int helper(void) {
    #|  return shared;
    #|}
    #|int main(void) {
    #|  return left() + helper();
    #|}
  let left_obj = compile_source_to_object_path(left, "static_internal_left")
  let right_obj = compile_source_to_object_path(right, "static_internal_right")
  let bin_path = temp_file_path("static_internal_linkage", left + right, "")
  run_command_checked(
    "clang -o " + bin_path + " " + left_obj + " " + right_obj,
    "link static internal linkage",
  )
  let result = run_command_capture(bin_path, "static_internal_linkage")
  inspect(result.code, content="42")
}

///|
async test "e2e extern globals do not allocate storage" {
  let def =
    #|int shared = 40;
  let user =
    #|extern int shared;
    #|int main(void) {
    #|  return shared + 2;
    #|}
  let def_obj = compile_source_to_object_path(def, "extern_global_def")
  let use_obj = compile_source_to_object_path(user, "extern_global_use")
  let bin_path = temp_file_path("extern_global_linkage", def + user, "")
  run_command_checked(
    "clang -o " + bin_path + " " + def_obj + " " + use_obj,
    "link extern global linkage",
  )
  let result = run_command_capture(bin_path, "extern_global_linkage")
  inspect(result.code, content="42")
}

///|
async test "e2e extern declaration followed by definition emits storage" {
  let source =
    #|extern int shared;
    #|int read_shared(void) {
    #|  return shared;
    #|}
    #|int shared = 42;
    #|int main(void) {
    #|  return read_shared();
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e tentative global followed by initialized definition emits once" {
  let source =
    #|int shared;
    #|int read_shared(void) {
    #|  return shared;
    #|}
    #|int shared = 42;
    #|int main(void) {
    #|  return read_shared();
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e global nested aggregate initializer" {
  let source =
    #|struct Point {
    #|  int x;
    #|  int y;
    #|};
    #|struct Point points[2] = {{1, 2}, {10, 29}};
    #|int main() {
    #|  return points[0].x + points[0].y + points[1].x + points[1].y;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e unsigned char buffer through pointer" {
  let source =
    #|int main() {
    #|  unsigned char buf[4];
    #|  unsigned char *p = buf;
    #|  buf[0] = 40;
    #|  p[1] = 2;
    #|  return p[0] + buf[1];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e switch default before later case" {
  let source =
    #|int main() {
    #|  int x = 3;
    #|  switch (x) {
    #|    default:
    #|      return 42;
    #|    case 1:
    #|      return 1;
    #|  }
    #|  return 0;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e switch pre-case declarations are not default" {
  let source =
    #|int run(int x) {
    #|  switch (x) {
    #|    int scratch;
    #|    case 3:
    #|      scratch = 40;
    #|      return scratch + 2;
    #|  }
    #|  return 7;
    #|}
    #|int main() {
    #|  if (run(4) != 7) return 1;
    #|  return run(3);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e switch dispatch reaches nested case labels" {
  let source =
    #|int run(int x) {
    #|  switch (x) {
    #|    case 1: {
    #|      int scratch;
    #|      if (x == 99) return 99;
    #|    case 2:
    #|      scratch = 40;
    #|      return scratch + 2;
    #|    }
    #|    default:
    #|      return 7;
    #|  }
    #|}
    #|int main() {
    #|  if (run(3) != 7) return 1;
    #|  if (run(1) != 42) return 2;
    #|  return run(2);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e bitfields pack after byte fields like clang" {
  let source =
    #|typedef unsigned int Pgno;
    #|struct InitInfo {
    #|  Pgno newTnum;
    #|  unsigned char iDb;
    #|  unsigned char busy;
    #|  unsigned orphanTrigger : 1;
    #|  unsigned imposterTable : 1;
    #|  unsigned reopenMemdb : 1;
    #|  const char **azInit;
    #|};
    #|int main() {
    #|  struct InitInfo x = {0};
    #|  x.newTnum = 1;
    #|  x.iDb = 2;
    #|  x.busy = 3;
    #|  x.orphanTrigger = 1;
    #|  x.imposterTable = 0;
    #|  x.reopenMemdb = 1;
    #|  x.azInit = (const char**)0x12345678;
    #|  if (sizeof(struct InitInfo) != 16) return 1;
    #|  if (__builtin_offsetof(struct InitInfo, azInit) != 8) return 2;
    #|  if (x.newTnum != 1 || x.iDb != 2 || x.busy != 3) return 3;
    #|  if (x.orphanTrigger != 1 || x.imposterTable != 0) return 4;
    #|  if (x.reopenMemdb != 1) return 5;
    #|  if (x.azInit != (const char**)0x12345678) return 6;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e local array sized by struct tail constant" {
  let source =
    #|struct ParseLike {
    #|  int header;
    #|  long aligned;
    #|  char tail[17];
    #|};
    #|int main() {
    #|  char save[sizeof(struct ParseLike) - __builtin_offsetof(struct ParseLike, tail)];
    #|  save[0] = 40;
    #|  save[16] = 2;
    #|  return save[0] + save[16];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e global pointer initialized to array element" {
  let source =
    #|unsigned char table[4] = {1, 40, 9, 2};
    #|unsigned char *p = &table[1];
    #|int main() {
    #|  return p[0] + p[2];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e string literal octal escapes" {
  let source =
    #|int main() {
    #|  char *s = "\100\040\040";
    #|  if (s[0] != 64) return 1;
    #|  if (s[1] != 32) return 2;
    #|  if (s[2] != 32) return 3;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e builtin string call preserves earlier args" {
  let source =
    #|char *right_arg() {
    #|  return "b";
    #|}
    #|int main() {
    #|  return __builtin_strcmp("a", right_arg()) < 0 ? 42 : 1;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e builtin memcpy preserves args before nested size call" {
  let source =
    #|int copy_len() {
    #|  return 4;
    #|}
    #|int main() {
    #|  char src[4];
    #|  char dst[4];
    #|  src[0] = 10;
    #|  src[1] = 11;
    #|  src[2] = 12;
    #|  src[3] = 9;
    #|  dst[0] = 0;
    #|  dst[1] = 0;
    #|  dst[2] = 0;
    #|  dst[3] = 0;
    #|  __builtin_memcpy(dst, src, copy_len());
    #|  return dst[0] + dst[1] + dst[2] + dst[3];
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e ternary array operands decay before indexing" {
  let source =
    #|typedef struct Cell Cell;
    #|struct Cell { int value; };
    #|
    #|int pick(int grow) {
    #|  Cell a = {11};
    #|  Cell b = {22};
    #|  Cell *ap_new[2];
    #|  Cell *ap_old[1];
    #|  int n_new = grow ? 2 : 1;
    #|  int n_old = 1;
    #|  ap_new[0] = &a;
    #|  ap_new[1] = &b;
    #|  ap_old[0] = &b;
    #|  return (n_new > n_old ? ap_new : ap_old)[n_old - 1]->value;
    #|}
    #|
    #|int main(void) {
    #|  return pick(1) == 11 && pick(0) == 22 ? 0 : 1;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="0")
}

///|
async test "e2e struct ternary assignment copies selected operand" {
  let source =
    #|struct Token {
    #|  char *z;
    #|  int n;
    #|};
    #|
    #|int zero(void) {
    #|  return 0;
    #|}
    #|
    #|int main(void) {
    #|  struct Token a;
    #|  struct Token b;
    #|  struct Token out;
    #|  a.z = "alpha";
    #|  a.n = 40;
    #|  b.z = "beta";
    #|  b.n = 1;
    #|  zero();
    #|  out = (b.n == 0 ? b : a);
    #|  return out.n + out.z[0] - 'a';
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="40")
}

///|
async test "e2e pointer less-than uses unsigned address ordering" {
  let source =
    #|typedef unsigned char u8;
    #|
    #|int utf8_len(const char *zIn, int nByte) {
    #|  int r = 0;
    #|  const u8 *z = (const u8*)zIn;
    #|  const u8 *zTerm;
    #|  if (nByte >= 0) {
    #|    zTerm = &z[nByte];
    #|  } else {
    #|    zTerm = (const u8*)(-1);
    #|  }
    #|  while (*z != 0 && z < zTerm) {
    #|    z++;
    #|    r++;
    #|  }
    #|  return r;
    #|}
    #|
    #|int main(void) {
    #|  return utf8_len("x", -1) == 1 ? 42 : 1;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e nested struct field initializer in local array" {
  let source =
    #|struct Inner {
    #|  int (*create)(void);
    #|  int (*drop)(void);
    #|  int (*scan)(void);
    #|};
    #|
    #|struct Builtin {
    #|  const char *name;
    #|  struct Inner x;
    #|};
    #|
    #|int create(void) { return 40; }
    #|int drop(void) { return 1; }
    #|int scan(void) { return 1; }
    #|
    #|int call_create(struct Inner *p) {
    #|  return p->create();
    #|}
    #|
    #|int main(void) {
    #|  struct Builtin a[] = {
    #|    { "unicode61", { create, drop, scan } },
    #|  };
    #|  return call_create(&a[0].x) + 2;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e hex escape string literal preserves raw bytes" {
  let source =
    #|int main(void) {
    #|  unsigned char *p = (unsigned char*)"\xFF\x00\x00\x01";
    #|  if (p[0] != 255) return 1;
    #|  if (p[1] != 0) return 2;
    #|  if (p[2] != 0) return 3;
    #|  if (p[3] != 1) return 4;
    #|  if (p[4] != 0) return 5;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e prefix increment returns truncated unsigned scalar" {
  let source =
    #|int main(void) {
    #|  unsigned char lo = 255;
    #|  unsigned char hi = 0;
    #|  unsigned short s = 65535;
    #|  unsigned int u = 0;
    #|  unsigned char assigned = 0;
    #|
    #|  u = u - 1;
    #|  if (++lo != 0) return 1;
    #|  if (lo != 0) return 2;
    #|  if (++s != 0) return 3;
    #|  if (s != 0) return 4;
    #|  if (++u != 0) return 5;
    #|  if (u != 0) return 6;
    #|  if ((assigned = 256) != 0) return 7;
    #|  if (assigned != 0) return 8;
    #|
    #|  lo = 255;
    #|  if (++lo == 0) hi++;
    #|  if (hi != 1) return 9;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}
