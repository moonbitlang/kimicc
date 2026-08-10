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
async test "e2e compound literal struct assignment after void call" {
  let source =
    #|typedef union ValueUnion {
    #|  int int32;
    #|  void *ptr;
    #|} ValueUnion;
    #|typedef struct Value {
    #|  ValueUnion u;
    #|  long tag;
    #|} Value;
    #|void poison(void) {
    #|}
    #|int main(void) {
    #|  int payload = 42;
    #|  Value v;
    #|  poison();
    #|  v = (Value){ (ValueUnion){ .int32 = 7 }, 4 };
    #|  if (v.tag != 4) return 1;
    #|  if (v.u.int32 != 7) return 2;
    #|  poison();
    #|  v = (Value){ (ValueUnion){ .ptr = &payload }, -1 };
    #|  if (v.tag != -1) return 3;
    #|  if (*(int *)v.u.ptr != 42) return 4;
    #|  return 42;
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
async test "e2e local extern array declaration resolves global symbol" {
  let def =
    #|const char * const header[] = { "answer", 0 };
  let user =
    #|int first(void) {
    #|  extern char const * const header[];
    #|  return header[0][0];
    #|}
    #|int main(void) {
    #|  return first() - 55;
    #|}
  let def_obj = compile_source_to_object_path(def, "local_extern_array_def")
  let use_obj = compile_source_to_object_path(user, "local_extern_array_use")
  let bin_path = temp_file_path("local_extern_array_linkage", def + user, "")
  run_command_checked(
    "clang -o " + bin_path + " " + def_obj + " " + use_obj,
    "link local extern array linkage",
  )
  let result = run_command_capture(bin_path, "local_extern_array_linkage")
  inspect(result.code, content="42")
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
async test "e2e comma separated initialized globals are distinct" {
  let source =
    #|int action_fd = -1, entry_fd = -1, text_fd = -1;
    #|int main(void) {
    #|  action_fd = 40;
    #|  entry_fd = 3;
    #|  return action_fd + entry_fd + text_fd;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e compound assignment evaluates pointer lvalue once" {
  let source =
    #|int main(void) {
    #|  unsigned a[2] = {1, 4};
    #|  unsigned b[2] = {2, 8};
    #|  unsigned *p = a;
    #|  unsigned *q = b;
    #|  *p++ |= *q++;
    #|  if (a[0] != 3) return 1;
    #|  if (a[1] != 4) return 2;
    #|  if (p != &a[1]) return 3;
    #|  if (q != &b[1]) return 4;
    #|  return 42;
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
async test "e2e unsigned int switch matches negative case bits" {
  let source =
    #|int run(unsigned int tag) {
    #|  switch (tag) {
    #|    case -7:
    #|      return 42;
    #|    default:
    #|      return 1;
    #|  }
    #|}
    #|int main() {
    #|  return run(0 - 7);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e unsigned int comparison matches negative constant bits" {
  let source =
    #|int is_object(unsigned int tag) {
    #|  if (tag != -1) return 1;
    #|  if (tag == -1) return 42;
    #|  return 2;
    #|}
    #|int main() {
    #|  return is_object((unsigned int)-1);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e unsigned int compares as signed long when promoted" {
  let source =
    #|int run(unsigned int u, long l) {
    #|  if (l < u) return 42;
    #|  return 1;
    #|}
    #|int main() {
    #|  return run((unsigned int)(0 - 2), -1);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e usual arithmetic conversion signedness matrix" {
  let source =
    #|int main(void) {
    #|  signed char sc = -6;
    #|  unsigned char uc = 250;
    #|  short ss = -10;
    #|  unsigned short us = 65530;
    #|  int i = -1;
    #|  unsigned int u = 1;
    #|  long l = -1;
    #|  unsigned int umax = 4294967295u;
    #|  unsigned long ul = 1;
    #|
    #|  if (sc + uc != 244) return 1;
    #|  if (ss + us != 65520) return 2;
    #|  if (i < u) return 3;
    #|  if (!(i > u)) return 4;
    #|  if (!(l < umax)) return 5;
    #|  if (!((long)-1 > ul)) return 6;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e narrow scalar parameter ABI preserves signedness" {
  let source =
    #|int check(signed char a, unsigned char b, signed short c, unsigned short d, int e) {
    #|  if (a != -1) return 1;
    #|  if (b != 255) return 2;
    #|  if (c != -2) return 3;
    #|  if (d != 65534) return 4;
    #|  if (e != -3) return 5;
    #|  return 42;
    #|}
    #|
    #|int main(void) {
    #|  return check(255, -1, 65534, -2, (signed char)253);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e sixteen byte struct return assign and pass by value" {
  let source =
    #|struct Value {
    #|  void *ptr;
    #|  long tag;
    #|};
    #|struct Box {
    #|  struct Value field;
    #|};
    #|struct Value make_value(void *p, long tag) {
    #|  struct Value v;
    #|  v.ptr = p;
    #|  v.tag = tag;
    #|  return v;
    #|}
    #|struct Value make_literal(void *p, long tag) {
    #|  return (struct Value){p, tag};
    #|}
    #|struct Value dup_value(struct Value v) {
    #|  return (struct Value)v;
    #|}
    #|int check(struct Value v, void *p, long tag) {
    #|  if (v.ptr != p) return 1;
    #|  if (v.tag != tag) return 2;
    #|  return 42;
    #|}
    #|int main() {
    #|  int payload = 0;
    #|  struct Value v;
    #|  v = make_value(&payload, -1);
    #|  if (check(v, &payload, -1) != 42) return 3;
    #|  struct Box b;
    #|  b.field = make_value(&payload, -7);
    #|  if (check(b.field, &payload, -7) != 42) return 4;
    #|  if (check(dup_value(v), &payload, -1) != 42) return 5;
    #|  if (check(make_value(&payload, 5), &payload, 5) != 42) return 6;
    #|  return check(make_literal(&payload, 9), &payload, 9);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e twelve byte aggregate return assignment preserves following field" {
  let source =
    #|typedef struct {
    #|  unsigned bytes;
    #|  struct {
    #|    unsigned row;
    #|    unsigned column;
    #|  } extent;
    #|} Length;
    #|
    #|typedef struct Node Node;
    #|typedef struct {
    #|  Node *node;
    #|  unsigned long tag;
    #|} Link;
    #|
    #|struct Node {
    #|  unsigned short state;
    #|  Length position;
    #|  Link links[1];
    #|};
    #|
    #|Length length_add(Length left, Length right) {
    #|  unsigned poison = 1;
    #|  Length result = {
    #|    .bytes = left.bytes + right.bytes,
    #|    .extent = {
    #|      .row = left.extent.row + right.extent.row,
    #|      .column = left.extent.column + right.extent.column,
    #|    },
    #|  };
    #|  if (poison != 1) return left;
    #|  return result;
    #|}
    #|
    #|int main(void) {
    #|  Node previous = {0};
    #|  Node node = {0};
    #|  Length delta = {7, {0, 7}};
    #|  node.links[0].node = &previous;
    #|  node.position = length_add(node.position, delta);
    #|  if (node.links[0].node != &previous) return 1;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e mixed scalar aggregate return and argument ABI" {
  let source =
    #|typedef struct Mix {
    #|  double d;
    #|  int i;
    #|  int j;
    #|} Mix;
    #|
    #|Mix make_mix(double d, int i, int j) {
    #|  Mix m = { d, i, j };
    #|  return m;
    #|}
    #|
    #|int check_mix(Mix a, Mix b) {
    #|  if ((long)(a.d * 10.0) != 15) return 1;
    #|  if (a.i != 20) return 2;
    #|  if (a.j != -5) return 3;
    #|  if ((long)(b.d * 10.0) != 25) return 4;
    #|  if (b.i != -7) return 5;
    #|  if (b.j != 9) return 6;
    #|  return 42;
    #|}
    #|
    #|int main(void) {
    #|  Mix local = make_mix(1.5, 20, -5);
    #|  return check_mix(local, (Mix){ 2.5, -7, 9 });
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
fn deterministic_scalar_aggregate_differential_source(
  case_index : Int,
) -> String {
  let signed_seed = case_index * 37 - 111
  let unsigned_seed = case_index * 70001 + 12345
  let long_seed = case_index * case_index * 97 - 500
  let shift = case_index % 5 + 1
  let alt_shift = shift % 5 + 1
  let source = StringBuilder::new()
  source.write_string("#include <stdio.h>\n")
  source.write_string(
    "typedef struct Pair { int a; unsigned int b; long c; } Pair;\n",
  )
  source.write_string(
    "static Pair make_pair(int a, unsigned int b, long c) { Pair p = { a, b, c }; return p; }\n",
  )
  source.write_string("static long fold(Pair p, int shift) {\n")
  source.write_string(
    "  unsigned int mixed = (p.b << shift) | (p.b >> (32 - shift));\n",
  )
  source.write_string("  long base = p.c + p.a;\n")
  source.write_string(
    "  if ((unsigned int)p.a < p.b) base += (long)(mixed & 1023u);\n",
  )
  source.write_string("  else base -= (long)(mixed & 511u);\n")
  source.write_string("  return base ^ (long)(unsigned long)mixed;\n")
  source.write_string("}\n")
  source.write_string("int main(void) {\n")
  source.write_string("  Pair p = make_pair(")
  source.write_string(signed_seed.to_string())
  source.write_string(", ")
  source.write_string(unsigned_seed.to_string())
  source.write_string("u, ")
  source.write_string(long_seed.to_string())
  source.write_string("L);\n")
  source.write_string(
    "  Pair q = { (int)(p.b & 255u) - 128, (unsigned int)(p.a * 17u + p.b), p.c - p.a };\n",
  )
  source.write_string("  long r = fold(p, ")
  source.write_string(shift.to_string())
  source.write_string(") + fold(q, ")
  source.write_string(alt_shift.to_string())
  source.write_string(");\n")
  source.write_string("  printf(\"case=%d r=%ld q=%u\\n\", ")
  source.write_string(case_index.to_string())
  source.write_string(", r, q.b);\n")
  source.write_string("  return (int)((unsigned long)r & 127u);\n")
  source.write_string("}\n")
  source.to_string()
}

///|
async test "e2e deterministic scalar aggregate differential corpus matches clang" {
  for case_index in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11] {
    let result = run_source_against_clang_baseline(
      deterministic_scalar_aggregate_differential_source(case_index),
      "scalar_aggregate_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
async test "e2e direct Mach-O scalar aggregate differential corpus matches clang" {
  for case_index in [0, 1, 2, 3, 4, 5] {
    let result = run_source_direct_object_against_clang_baseline(
      deterministic_scalar_aggregate_differential_source(case_index),
      "direct_scalar_aggregate_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
fn deterministic_scalar_control_differential_source(case_index : Int) -> String {
  let seed_a = case_index * 9973 + 123
  let seed_b = case_index * 7919 + 4567
  let rounds = case_index % 9 + 6
  let source = StringBuilder::new()
  source.write_string("#include <stdio.h>\n")
  source.write_string("static unsigned mix(unsigned x, unsigned y, int n) {\n")
  source.write_string("  unsigned r = x ^ (y + 1103515245u);\n")
  source.write_string("  for (int i = 0; i < n; i = i + 1) {\n")
  source.write_string("    switch ((r + (unsigned)i) & 7u) {\n")
  source.write_string("      case 0: r = (r << 3) | (r >> 29); break;\n")
  source.write_string(
    "      case 1: r = r + (y ^ (unsigned)(i * 17 + 3)); break;\n",
  )
  source.write_string("      case 2: r = r - ((x >> (i & 7)) | 1u); break;\n")
  source.write_string("      case 3: r = (r & 16777215u) ^ (r >> 7); break;\n")
  source.write_string("      case 4: r = (r * 33u) + (x & 255u); break;\n")
  source.write_string(
    "      case 5: r = (r / ((y & 15u) + 1u)) + (r % ((x & 31u) + 1u)); break;\n",
  )
  source.write_string("      case 6: r = (r <= y) ? r + x : r - y; break;\n")
  source.write_string("      default: r = ~r + (unsigned)i; break;\n")
  source.write_string("    }\n")
  source.write_string("  }\n")
  source.write_string("  return r;\n")
  source.write_string("}\n")
  source.write_string("int main(void) {\n")
  source.write_string("  unsigned a = ")
  source.write_string(seed_a.to_string())
  source.write_string("u;\n")
  source.write_string("  unsigned b = ")
  source.write_string(seed_b.to_string())
  source.write_string("u;\n")
  source.write_string("  unsigned r = 0u;\n")
  source.write_string("  for (int i = 0; i < ")
  source.write_string(rounds.to_string())
  source.write_string("; i = i + 1) {\n")
  source.write_string(
    "    r ^= mix(a + (unsigned)(i * 13), b ^ (unsigned)(i * 101), (i % 7) + 3);\n",
  )
  source.write_string("    if ((r & 3u) == 0u) r += a >> (i & 7);\n")
  source.write_string("    else if ((r & 3u) == 1u) r ^= b << (i & 3);\n")
  source.write_string("    else r -= (unsigned)(i * 19 + 5);\n")
  source.write_string("  }\n")
  source.write_string(
    "  long signed_probe = (long)(int)(r & 65535u) - 32768L;\n",
  )
  source.write_string("  printf(\"case=%d r=%u signed=%ld\\n\", ")
  source.write_string(case_index.to_string())
  source.write_string(", r, signed_probe);\n")
  source.write_string("  return (int)(r & 127u);\n")
  source.write_string("}\n")
  source.to_string()
}

///|
async test "e2e deterministic scalar control differential corpus matches clang" {
  for case_index in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15] {
    let result = run_source_against_clang_baseline(
      deterministic_scalar_control_differential_source(case_index),
      "scalar_control_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
async test "e2e direct Mach-O scalar control differential corpus matches clang" {
  for case_index in [0, 1, 2, 3, 4, 5, 6, 7] {
    let result = run_source_direct_object_against_clang_baseline(
      deterministic_scalar_control_differential_source(case_index),
      "direct_scalar_control_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
fn deterministic_floating_differential_source(case_index : Int) -> String {
  let seed_a = case_index * 13 + 5
  let seed_b = case_index * 7 + 3
  let rounds = case_index % 5 + 4
  let source = StringBuilder::new()
  source.write_string("#include <stdio.h>\n")
  source.write_string(
    "typedef struct Sample { double d; float f; int tag; } Sample;\n",
  )
  source.write_string(
    "static Sample make_sample(double d, float f, int tag) { Sample s = { d, f, tag }; return s; }\n",
  )
  source.write_string("static long scale(double value) {\n")
  source.write_string(
    "  return value < 0.0 ? (long)(value * 1000.0 - 0.5) : (long)(value * 1000.0 + 0.5);\n",
  )
  source.write_string("}\n")
  source.write_string("static double fold(Sample s, int rounds) {\n")
  source.write_string(
    "  double acc = s.d + (double)s.f + (double)s.tag * 0.125;\n",
  )
  source.write_string("  for (int i = 0; i < rounds; i = i + 1) {\n")
  source.write_string("    double delta = (double)((s.tag + i) & 7) * 0.375;\n")
  source.write_string("    if (acc > 25.0) acc = acc * 0.5 - delta;\n")
  source.write_string("    else if (acc < -10.0) acc = -acc + delta;\n")
  source.write_string("    else acc = acc * 1.25 + delta;\n")
  source.write_string("    s.f = (float)((double)s.f * -0.5 + (double)i);\n")
  source.write_string("  }\n")
  source.write_string("  return acc + (double)s.f;\n")
  source.write_string("}\n")
  source.write_string("int main(void) {\n")
  source.write_string("  Sample a = make_sample(")
  source.write_string(seed_a.to_string())
  source.write_string(".25, ")
  source.write_string(seed_b.to_string())
  source.write_string(".5f, ")
  source.write_string((case_index - 4).to_string())
  source.write_string(");\n")
  source.write_string("  Sample b = make_sample(-")
  source.write_string((seed_b + 1).to_string())
  source.write_string(".75, ")
  source.write_string((seed_a % 9 + 1).to_string())
  source.write_string(".25f, ")
  source.write_string((case_index * 3 - 5).to_string())
  source.write_string(");\n")
  source.write_string("  double total = fold(a, ")
  source.write_string(rounds.to_string())
  source.write_string(") - fold(b, ")
  source.write_string((rounds + 1).to_string())
  source.write_string(");\n")
  source.write_string("  long scaled = scale(total);\n")
  source.write_string("  printf(\"case=%d scaled=%ld sign=%d\\n\", ")
  source.write_string(case_index.to_string())
  source.write_string(", scaled, scaled < 0 ? -1 : 1);\n")
  source.write_string("  return (int)((unsigned long)scaled & 127u);\n")
  source.write_string("}\n")
  source.to_string()
}

///|
async test "e2e deterministic floating differential corpus matches clang" {
  for case_index in [0, 1, 2, 3, 4, 5, 6, 7] {
    let result = run_source_against_clang_baseline(
      deterministic_floating_differential_source(case_index),
      "floating_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
async test "e2e direct Mach-O floating differential corpus matches clang" {
  for case_index in [0, 1, 2, 3] {
    let result = run_source_direct_object_against_clang_baseline(
      deterministic_floating_differential_source(case_index),
      "direct_floating_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
fn deterministic_memory_differential_source(case_index : Int) -> String {
  let seed = case_index * 17 + 11
  let stride = case_index % 5 + 1
  let byte_offset = case_index % 5
  let byte_probe = case_index % 17
  let matrix_row = case_index % 3
  let matrix_col = (case_index + 1) % 4
  let source = StringBuilder::new()
  source.write_string("#include <stdio.h>\n")
  source.write_string(
    "typedef struct Cell { int key; long value; unsigned char flag; } Cell;\n",
  )
  source.write_string("static long walk(Cell *cells, int n, int stride) {\n")
  source.write_string("  long acc = 0;\n")
  source.write_string("  for (int i = 0; i < n * 2 + 3; i = i + 1) {\n")
  source.write_string("    int idx = (i * stride + cells[i % n].key) % n;\n")
  source.write_string("    Cell *p = cells + idx;\n")
  source.write_string(
    "    p->value = p->value + (long)(p->flag + i) * (long)(idx + 1);\n",
  )
  source.write_string(
    "    p->flag = (unsigned char)(p->flag + (unsigned char)(p->key + i));\n",
  )
  source.write_string("    acc += p->value ^ (long)(unsigned long)p->flag;\n")
  source.write_string("    acc += (long)(p - cells);\n")
  source.write_string("  }\n")
  source.write_string("  return acc;\n")
  source.write_string("}\n")
  source.write_string("int main(void) {\n")
  source.write_string("  Cell cells[6];\n")
  source.write_string("  unsigned char bytes[24];\n")
  source.write_string("  int matrix[3][4];\n")
  source.write_string("  for (int i = 0; i < 6; i = i + 1) {\n")
  source.write_string("    cells[i].key = ")
  source.write_string(seed.to_string())
  source.write_string(" + i * 3;\n")
  source.write_string(
    "    cells[i].value = (long)(cells[i].key * 11 - i * 7);\n",
  )
  source.write_string(
    "    cells[i].flag = (unsigned char)(cells[i].key + i * 5);\n",
  )
  source.write_string("  }\n")
  source.write_string("  for (int i = 0; i < 24; i = i + 1) {\n")
  source.write_string("    bytes[i] = (unsigned char)(")
  source.write_string((seed * 2).to_string())
  source.write_string(" + i * 9);\n")
  source.write_string("  }\n")
  source.write_string("  for (int r = 0; r < 3; r = r + 1) {\n")
  source.write_string("    for (int c = 0; c < 4; c = c + 1) {\n")
  source.write_string("      matrix[r][c] = ")
  source.write_string(seed.to_string())
  source.write_string(" + r * 13 - c * 5;\n")
  source.write_string("    }\n")
  source.write_string("  }\n")
  source.write_string("  long total = walk(cells, 6, ")
  source.write_string(stride.to_string())
  source.write_string(");\n")
  source.write_string("  unsigned char *bp = bytes + ")
  source.write_string(byte_offset.to_string())
  source.write_string(";\n")
  source.write_string("  for (int i = 0; i < 12; i = i + 1) {\n")
  source.write_string(
    "    bp[i] = (unsigned char)(bp[i] ^ (unsigned char)(i + cells[i % 6].flag));\n",
  )
  source.write_string("    total += (long)bp[i];\n")
  source.write_string("  }\n")
  source.write_string("  int *mp = &matrix[0][0];\n")
  source.write_string("  for (int i = 0; i < 12; i = i + 1) {\n")
  source.write_string("    total += (long)*(mp + i) * (long)((i % 3) + 1);\n")
  source.write_string("    *(mp + i) = *(mp + i) + (int)(total & 15L);\n")
  source.write_string("  }\n")
  source.write_string(
    "  total += (cells + 5)->value - (cells + 1)->value + (long)((cells + 4) - cells);\n",
  )
  source.write_string("  printf(\"case=%d total=%ld byte=%u matrix=%d\\n\", ")
  source.write_string(case_index.to_string())
  source.write_string(", total, (unsigned)bytes[")
  source.write_string(byte_probe.to_string())
  source.write_string("], matrix[")
  source.write_string(matrix_row.to_string())
  source.write_string("][")
  source.write_string(matrix_col.to_string())
  source.write_string("]);\n")
  source.write_string("  return (int)((unsigned long)total & 127u);\n")
  source.write_string("}\n")
  source.to_string()
}

///|
async test "e2e deterministic memory differential corpus matches clang" {
  for case_index in [0, 1, 2, 3, 4, 5, 6, 7] {
    let result = run_source_against_clang_baseline(
      deterministic_memory_differential_source(case_index),
      "memory_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
async test "e2e direct Mach-O memory differential corpus matches clang" {
  for case_index in [0, 1, 2, 3] {
    let result = run_source_direct_object_against_clang_baseline(
      deterministic_memory_differential_source(case_index),
      "direct_memory_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
fn write_variadic_differential_arg(
  source : StringBuilder,
  tag_value : Int,
  arg_index : Int,
) -> Unit {
  match (tag_value + arg_index) % 4 {
    0 => {
      source.write_string("(")
      source.write_string((tag_value * 31 + arg_index * 7 - 40).to_string())
      source.write_string(")")
    }
    1 => {
      source.write_string("(")
      source.write_string(
        (tag_value * 100003 + arg_index * 1009 - 70000).to_string(),
      )
      source.write_string("LL)")
    }
    2 => {
      source.write_string("(")
      source.write_string(
        (tag_value * 65537 + arg_index * 257 + 123).to_string(),
      )
      source.write_string("u)")
    }
    _ => {
      source.write_string("(")
      if (tag_value + arg_index) % 3 == 0 {
        source.write_string("-")
      }
      source.write_string((tag_value * 5 + arg_index * 3 + 1).to_string())
      source.write_string(".75)")
    }
  }
}

///|
fn write_variadic_differential_call(
  source : StringBuilder,
  tag_value : Int,
  count : Int,
) -> Unit {
  source.write_string("read_variadic(")
  source.write_string(tag_value.to_string())
  source.write_string(", ")
  source.write_string(count.to_string())
  for arg_index in [0, 1, 2, 3, 4, 5, 6, 7] {
    if arg_index < count {
      source.write_string(", ")
      write_variadic_differential_arg(source, tag_value, arg_index)
    }
  }
  source.write_string(")")
}

///|
fn deterministic_variadic_differential_source(case_index : Int) -> String {
  let tag = case_index * 3 + 2
  let first_count = case_index % 4 + 4
  let second_count = (case_index + 1) % 4 + 3
  let source = StringBuilder::new()
  source.write_string("#include <stdio.h>\n")
  source.write_string("typedef __builtin_va_list va_list;\n")
  source.write_string("static long long scale(double value) {\n")
  source.write_string(
    "  return value < 0.0 ? (long long)(value * 100.0 - 0.5) : (long long)(value * 100.0 + 0.5);\n",
  )
  source.write_string("}\n")
  source.write_string("static long long read_variadic(int tag, int n, ...) {\n")
  source.write_string("  va_list ap;\n")
  source.write_string("  __builtin_va_start(ap, n);\n")
  source.write_string(
    "  long long total = (long long)tag * 17LL + (long long)n;\n",
  )
  source.write_string("  for (int i = 0; i < n; i = i + 1) {\n")
  source.write_string("    switch ((tag + i) & 3) {\n")
  source.write_string("      case 0: {\n")
  source.write_string("        int v = __builtin_va_arg(ap, int);\n")
  source.write_string("        total += (long long)v * (long long)(i + 1);\n")
  source.write_string("        break;\n")
  source.write_string("      }\n")
  source.write_string("      case 1: {\n")
  source.write_string(
    "        long long v = __builtin_va_arg(ap, long long);\n",
  )
  source.write_string("        total ^= v + (long long)(tag - i);\n")
  source.write_string("        break;\n")
  source.write_string("      }\n")
  source.write_string("      case 2: {\n")
  source.write_string(
    "        unsigned int v = __builtin_va_arg(ap, unsigned int);\n",
  )
  source.write_string(
    "        total += (long long)(v & 65535u) - (long long)i;\n",
  )
  source.write_string("        break;\n")
  source.write_string("      }\n")
  source.write_string("      default: {\n")
  source.write_string("        double v = __builtin_va_arg(ap, double);\n")
  source.write_string("        total += scale(v) ^ (long long)(tag + i);\n")
  source.write_string("        break;\n")
  source.write_string("      }\n")
  source.write_string("    }\n")
  source.write_string("  }\n")
  source.write_string("  __builtin_va_end(ap);\n")
  source.write_string("  return total;\n")
  source.write_string("}\n")
  source.write_string("int main(void) {\n")
  source.write_string("  long long total = ")
  write_variadic_differential_call(source, tag, first_count)
  source.write_string(";\n")
  source.write_string("  total ^= ")
  write_variadic_differential_call(source, tag + 1, second_count)
  source.write_string(";\n")
  source.write_string("  printf(\"case=%d total=%lld low=%d\\n\", ")
  source.write_string(case_index.to_string())
  source.write_string(", total, (int)(total & 255LL));\n")
  source.write_string("  return (int)((unsigned long long)total & 127ULL);\n")
  source.write_string("}\n")
  source.to_string()
}

///|
async test "e2e deterministic variadic differential corpus matches clang" {
  for case_index in [0, 1, 2, 3, 4, 5, 6, 7] {
    let result = run_source_against_clang_baseline(
      deterministic_variadic_differential_source(case_index),
      "variadic_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
async test "e2e direct Mach-O variadic differential corpus matches clang" {
  for case_index in [0, 1, 2, 3] {
    let result = run_source_direct_object_against_clang_baseline(
      deterministic_variadic_differential_source(case_index),
      "direct_variadic_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
fn deterministic_bitfield_differential_source(case_index : Int) -> String {
  let seed = case_index * 19 + 7
  let rounds = case_index % 7 + 8
  let source = StringBuilder::new()
  source.write_string("#include <stdio.h>\n")
  source.write_string("typedef struct Bits {\n")
  source.write_string("  unsigned a : 3;\n")
  source.write_string("  unsigned b : 5;\n")
  source.write_string("  int c : 6;\n")
  source.write_string("  unsigned d : 10;\n")
  source.write_string("  unsigned e : 1;\n")
  source.write_string("  unsigned f : 7;\n")
  source.write_string("} Bits;\n")
  source.write_string("typedef struct Packet {\n")
  source.write_string("  unsigned char prefix;\n")
  source.write_string("  Bits bits;\n")
  source.write_string("  unsigned short suffix;\n")
  source.write_string("} Packet;\n")
  source.write_string("static long fold(Packet *packets, int rounds) {\n")
  source.write_string("  long acc = 0;\n")
  source.write_string("  for (int i = 0; i < rounds; i = i + 1) {\n")
  source.write_string("    Packet *p = packets + (i % 3);\n")
  source.write_string(
    "    unsigned before = p->bits.a + (p->bits.b << 3) + (((unsigned)(p->bits.c & 63)) << 8) + (p->bits.d << 14) + (p->bits.e << 24) + (p->bits.f << 25);\n",
  )
  source.write_string("    p->bits.a = (p->bits.a + i + p->prefix) & 7u;\n")
  source.write_string("    p->bits.b = (p->bits.b + p->suffix + i) & 31u;\n")
  source.write_string("    p->bits.c = (int)(((p->bits.c + i) % 31) - 15);\n")
  source.write_string("    p->bits.d = (p->bits.d ^ (before + i)) & 1023u;\n")
  source.write_string("    p->bits.e = (p->bits.d >> (i & 3)) & 1u;\n")
  source.write_string(
    "    p->bits.f = (p->bits.f + p->bits.a + p->bits.b + i) & 127u;\n",
  )
  source.write_string(
    "    acc += (long)before + (long)p->bits.a - (long)p->bits.c + (long)p->bits.d + (long)p->bits.f;\n",
  )
  source.write_string("  }\n")
  source.write_string("  return acc;\n")
  source.write_string("}\n")
  source.write_string("int main(void) {\n")
  source.write_string("  Packet packets[3];\n")
  source.write_string("  for (int i = 0; i < 3; i = i + 1) {\n")
  source.write_string("    unsigned base = ")
  source.write_string(seed.to_string())
  source.write_string("u + (unsigned)i * 23u;\n")
  source.write_string("    packets[i].prefix = (unsigned char)(base + 11u);\n")
  source.write_string(
    "    packets[i].suffix = (unsigned short)(base * 13u + 5u);\n",
  )
  source.write_string("    packets[i].bits.a = base & 7u;\n")
  source.write_string("    packets[i].bits.b = (base >> 1) & 31u;\n")
  source.write_string("    packets[i].bits.c = (int)(base % 31u) - 15;\n")
  source.write_string("    packets[i].bits.d = (base * 17u + 3u) & 1023u;\n")
  source.write_string("    packets[i].bits.e = (base >> 2) & 1u;\n")
  source.write_string("    packets[i].bits.f = (base * 9u + 1u) & 127u;\n")
  source.write_string("  }\n")
  source.write_string("  long total = fold(packets, ")
  source.write_string(rounds.to_string())
  source.write_string(");\n")
  source.write_string(
    "  unsigned probe = packets[1].bits.a + (packets[1].bits.b << 3) + (packets[1].bits.d << 8) + (packets[1].bits.f << 18);\n",
  )
  source.write_string(
    "  printf(\"case=%d total=%ld size=%lu probe=%u signed=%d\\n\", ",
  )
  source.write_string(case_index.to_string())
  source.write_string(
    ", total, (unsigned long)sizeof(Packet), probe, packets[2].bits.c);\n",
  )
  source.write_string("  return (int)((unsigned long)total & 127u);\n")
  source.write_string("}\n")
  source.to_string()
}

///|
/// Builds a program where several blocks define the same `struct` tag with
/// different layouts.
///
/// C gives tags block scope, so each definition is its own type. kimicc kept one
/// flat tag table, so a later definition replaced an earlier one and `sizeof` in
/// the earlier function reported the wrong layout.
fn deterministic_tag_scope_differential_source(case_index : Int) -> String {
  let width = case_index % 3 + 1
  let source = StringBuilder::new()
  source.write_string("#include <stdio.h>\n")
  source.write_string("struct Tag { int a; int b; };\n")
  source.write_string(
    "static int file_scope(void) { return (int)sizeof(struct Tag); }\n",
  )
  source.write_string("static int narrow(void) {\n")
  source.write_string("  struct Tag { char c; };\n")
  source.write_string("  struct Tag v;\n")
  source.write_string("  v.c = (char)")
  source.write_string(width.to_string())
  source.write_string(";\n")
  source.write_string("  return (int)sizeof(struct Tag) + v.c;\n")
  source.write_string("}\n")
  source.write_string("static int wide(void) {\n")
  source.write_string("  struct Tag { double d; long long e; int f; };\n")
  source.write_string("  return (int)sizeof(struct Tag);\n")
  source.write_string("}\n")
  source.write_string("static int nested(void) {\n")
  source.write_string("  struct Tag { int x; int y; int z; };\n")
  source.write_string("  int inner;\n")
  source.write_string(
    "  { struct Tag { char q; char r; }; inner = (int)sizeof(struct Tag); }\n",
  )
  source.write_string("  return (int)sizeof(struct Tag) * 100 + inner;\n")
  source.write_string("}\n")
  source.write_string(
    "static int after_blocks(void) { return (int)sizeof(struct Tag); }\n",
  )
  source.write_string("int main(void) {\n")
  source.write_string(
    "  printf(\"case=%d file=%d narrow=%d wide=%d nested=%d after=%d\\n\", ",
  )
  source.write_string(case_index.to_string())
  source.write_string(
    ", file_scope(), narrow(), wide(), nested(), after_blocks());\n",
  )
  source.write_string("  return 0;\n")
  source.write_string("}\n")
  source.to_string()
}

///|
async test "e2e deterministic tag scope differential corpus matches clang" {
  for case_index in [0, 1, 2] {
    let result = run_source_against_clang_baseline(
      deterministic_tag_scope_differential_source(case_index),
      "tag_scope_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
/// Builds a program whose struct layouts only agree with clang if `#pragma
/// pack` is honored: field offsets, aggregate sizes, `push`/`pop` nesting, and
/// reads and writes through the resulting unaligned members.
fn deterministic_pragma_pack_differential_source(case_index : Int) -> String {
  let pack = [1, 2, 4, 8][case_index % 4]
  let seed = case_index * 31 + 5
  let source = StringBuilder::new()
  source.write_string("#include <stdio.h>\n")
  source.write_string("#pragma pack(")
  source.write_string(pack.to_string())
  source.write_string(")\n")
  source.write_string(
    "typedef struct Packed { char a; int b; char c; long long d; short e; } Packed;\n",
  )
  source.write_string("#pragma pack()\n")
  source.write_string(
    "typedef struct Natural { char a; int b; char c; long long d; short e; } Natural;\n",
  )
  source.write_string("#pragma pack(push, 1)\n")
  source.write_string(
    "typedef union Tight { char c; long long v; double d; } Tight;\n",
  )
  source.write_string(
    "typedef struct TightBits { char lead; unsigned x : 5; unsigned y : 11; int tail; } TightBits;\n",
  )
  source.write_string("#pragma pack(push, 4)\n")
  source.write_string(
    "typedef struct Inner4 { char a; long long d; } Inner4;\n",
  )
  source.write_string("#pragma pack(pop)\n")
  source.write_string(
    "typedef struct BackToTight { char a; long long d; } BackToTight;\n",
  )
  source.write_string("#pragma pack(pop)\n")
  source.write_string(
    "typedef struct AfterAllPops { char a; long long d; } AfterAllPops;\n",
  )
  source.write_string("static unsigned long off(void *base, void *field) {\n")
  source.write_string(
    "  return (unsigned long)((char *)field - (char *)base);\n",
  )
  source.write_string("}\n")
  source.write_string("int main(void) {\n")
  source.write_string("  Packed p;\n")
  source.write_string("  TightBits t;\n")
  source.write_string("  Tight u;\n")
  source.write_string("  long long acc = 0;\n")
  source.write_string("  p.a = (char)(")
  source.write_string(seed.to_string())
  source.write_string(" & 127);\n")
  source.write_string("  p.b = ")
  source.write_string(seed.to_string())
  source.write_string(" * 7 + 3;\n")
  source.write_string("  p.c = (char)((")
  source.write_string(seed.to_string())
  source.write_string(" >> 2) & 63);\n")
  source.write_string("  p.d = (long long)")
  source.write_string(seed.to_string())
  source.write_string(" * 1000003LL + 17LL;\n")
  source.write_string("  p.e = (short)((")
  source.write_string(seed.to_string())
  source.write_string(" * 13) & 32767);\n")
  source.write_string("  acc += p.a + p.b + p.c + p.d + p.e;\n")
  source.write_string("  p.d = p.d * 3LL - (long long)p.b;\n")
  source.write_string("  acc += p.d;\n")
  source.write_string("  t.lead = (char)(")
  source.write_string(seed.to_string())
  source.write_string(" & 31);\n")
  source.write_string("  t.x = (unsigned)(")
  source.write_string(seed.to_string())
  source.write_string(" & 31u);\n")
  source.write_string("  t.y = (unsigned)((")
  source.write_string(seed.to_string())
  source.write_string(" * 5) & 2047u);\n")
  source.write_string("  t.tail = ")
  source.write_string(seed.to_string())
  source.write_string(" * 11 - 4;\n")
  source.write_string("  acc += t.lead + t.x + t.y + t.tail;\n")
  source.write_string("  u.v = (long long)")
  source.write_string(seed.to_string())
  source.write_string(" * 65537LL;\n")
  source.write_string("  acc += u.v + u.c;\n")
  source.write_string(
    "  printf(\"case=%d pack=%d packed=%lu natural=%lu tight=%lu bits=%lu inner4=%lu back=%lu after=%lu ob=%lu oc=%lu od=%lu oe=%lu acc=%lld\\n\",\n",
  )
  source.write_string("    ")
  source.write_string(case_index.to_string())
  source.write_string(", ")
  source.write_string(pack.to_string())
  source.write_string(",\n")
  source.write_string(
    "    (unsigned long)sizeof(Packed), (unsigned long)sizeof(Natural),\n",
  )
  source.write_string(
    "    (unsigned long)sizeof(Tight), (unsigned long)sizeof(TightBits),\n",
  )
  source.write_string(
    "    (unsigned long)sizeof(Inner4), (unsigned long)sizeof(BackToTight),\n",
  )
  source.write_string("    (unsigned long)sizeof(AfterAllPops),\n")
  source.write_string(
    "    off(&p, &p.b), off(&p, &p.c), off(&p, &p.d), off(&p, &p.e), acc);\n",
  )
  source.write_string("  return (int)((unsigned long long)acc & 127u);\n")
  source.write_string("}\n")
  source.to_string()
}

///|
async test "e2e deterministic pragma pack differential corpus matches clang" {
  for case_index in [0, 1, 2, 3, 4, 5] {
    let result = run_source_against_clang_baseline(
      deterministic_pragma_pack_differential_source(case_index),
      "pragma_pack_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
async test "e2e direct Mach-O pragma pack differential corpus matches clang" {
  for case_index in [0, 1, 2, 3] {
    let result = run_source_direct_object_against_clang_baseline(
      deterministic_pragma_pack_differential_source(case_index),
      "direct_pragma_pack_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
async test "e2e deterministic bitfield differential corpus matches clang" {
  for case_index in [0, 1, 2, 3, 4, 5, 6, 7] {
    let result = run_source_against_clang_baseline(
      deterministic_bitfield_differential_source(case_index),
      "bitfield_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
async test "e2e direct Mach-O bitfield differential corpus matches clang" {
  for case_index in [0, 1, 2, 3] {
    let result = run_source_direct_object_against_clang_baseline(
      deterministic_bitfield_differential_source(case_index),
      "direct_bitfield_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
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
async test "e2e bare atomic typedef qualifier from ocamlyacc headers" {
  let source =
    #|typedef unsigned long uintnat;
    #|typedef _Atomic uintnat atomic_uintnat;
    #|typedef _Atomic(uintnat) atomic_uintnat_paren;
    #|typedef void (*caml_timing_hook)(void);
    #|extern _Atomic caml_timing_hook caml_major_slice_begin_hook;
    #|struct AlignedBytes {
    #|  _Alignas(8) char c;
    #|  char d;
    #|};
    #|extern void exit(int);
    #|_Noreturn static void die(int code) {
    #|  exit(code);
    #|}
    #|void comma_proto_a(void), comma_proto_b(void);
    #|void comma_proto_a(void) {}
    #|void comma_proto_b(void) {}
    #|extern int missing_inline_dependency(void);
    #|inline int external_inline_ignored(void) {
    #|  return missing_inline_dependency();
    #|}
    #|static inline int used_static_inline(int x) {
    #|  return x + 1;
    #|}
    #|
    #|int main(void) {
    #|  _Atomic uintnat local;
    #|  atomic_uintnat *counter = (atomic_uintnat*)0;
    #|  if (sizeof(atomic_uintnat) != sizeof(uintnat)) return 1;
    #|  if (sizeof(atomic_uintnat_paren) != sizeof(uintnat)) return 2;
    #|  if (sizeof(local) != sizeof(uintnat)) return 3;
    #|  if (sizeof(*counter) != sizeof(uintnat)) return 4;
    #|  if (sizeof(struct AlignedBytes) != 8) return 5;
    #|  if (__builtin_offsetof(struct AlignedBytes, d) != 1) return 6;
    #|  if (L'a' != 97) return 7;
    #|  if (used_static_inline(40) != 41) return 8;
    #|  comma_proto_a();
    #|  comma_proto_b();
    #|  return 77;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="77")
}

///|
async test "e2e used non-static inline emits local body" {
  let source =
    #|extern int missing_inline_dependency(void);
    #|
    #|inline int unused_inline_dependency(void) {
    #|  return missing_inline_dependency();
    #|}
    #|
    #|inline int local_sigbits(int signo) {
    #|  return signo > 32 ? 0 : (1 << (signo - 1));
    #|}
    #|
    #|int main(void) {
    #|  if (local_sigbits(6) != 32) return 1;
    #|  if (local_sigbits(33) != 0) return 2;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e 64-bit dyld chained pointer bitfields preserve wide masks" {
  let source =
    #|typedef unsigned long long uint64_t;
    #|
    #|struct Rebase {
    #|  uint64_t target : 36,
    #|           high8 : 8,
    #|           reserved : 7,
    #|           next : 12,
    #|           bind : 1;
    #|};
    #|
    #|int main(void) {
    #|  union {
    #|    struct Rebase rebase;
    #|    uint64_t raw;
    #|  } value;
    #|  uint64_t cur = 0x1200000000000005ULL;
    #|  value.raw = ~0ULL;
    #|  value.rebase.target = cur & 0xfffffffffULL;
    #|  value.rebase.high8 = cur >> 56;
    #|  value.rebase.reserved = 0;
    #|  value.rebase.next = 0;
    #|  value.rebase.bind = 0;
    #|  if (value.rebase.target != 5ULL) return 1;
    #|  if (value.rebase.high8 != 0x12ULL) return 2;
    #|  if (((uint64_t)value.rebase.high8 << 56) + value.rebase.target != cur) return 3;
    #|  if (value.raw != 0x12000000005ULL) return 4;
    #|  value.rebase.target = 0xfffffffffULL;
    #|  value.rebase.high8 = 0x12;
    #|  if (value.rebase.target != 0xfffffffffULL) return 5;
    #|  if (value.rebase.high8 != 0x12) return 6;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e wide literal shifts do not narrow to int" {
  let source =
    #|typedef unsigned long long uint64_t;
    #|
    #|int main(void) {
    #|  uint64_t shifted = (0x12ULL << 36) + 5ULL;
    #|  if (shifted != 0x12000000005ULL) return 1;
    #|  if ((1ULL << 40) != 0x10000000000ULL) return 2;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e mixed bitfield layout matches quickjs object header" {
  let source =
    #|typedef unsigned char uint8_t;
    #|typedef unsigned short uint16_t;
    #|typedef unsigned int uint32_t;
    #|
    #|struct list_head {
    #|  struct list_head *prev;
    #|  struct list_head *next;
    #|};
    #|
    #|typedef enum {
    #|  GC_OBJ_TYPE_JS_OBJECT,
    #|  GC_OBJ_TYPE_FUNCTION_BYTECODE
    #|} JSGCObjectTypeEnum;
    #|
    #|struct JSGCObjectHeader {
    #|  int ref_count;
    #|  JSGCObjectTypeEnum gc_obj_type : 4;
    #|  uint8_t mark : 4;
    #|  uint8_t dummy1;
    #|  uint16_t dummy2;
    #|  struct list_head link;
    #|};
    #|
    #|struct JSObjectLike {
    #|  union {
    #|    struct JSGCObjectHeader header;
    #|    struct {
    #|      int __gc_ref_count;
    #|      uint8_t __gc_mark;
    #|      uint8_t extensible : 1;
    #|      uint8_t free_mark : 1;
    #|      uint8_t is_exotic : 1;
    #|      uint8_t fast_array : 1;
    #|      uint8_t is_constructor : 1;
    #|      uint8_t has_immutable_prototype : 1;
    #|      uint8_t tmp_mark : 1;
    #|      uint8_t is_HTMLDDA : 1;
    #|      uint16_t class_id;
    #|    };
    #|  };
    #|  uint32_t weakref_count;
    #|  void *shape;
    #|  void *prop;
    #|  void *opaque;
    #|};
    #|
    #|union HeaderBytes {
    #|  struct JSGCObjectHeader h;
    #|  unsigned char bytes[24];
    #|};
    #|
    #|int main(void) {
    #|  union HeaderBytes u = {0};
    #|  struct JSObjectLike obj = {0};
    #|  int shape = 1;
    #|  int prop = 2;
    #|
    #|  if (sizeof(struct JSGCObjectHeader) != 24) return 1;
    #|  if (__builtin_offsetof(struct JSGCObjectHeader, dummy1) != 5) return 2;
    #|  if (__builtin_offsetof(struct JSGCObjectHeader, dummy2) != 6) return 3;
    #|  if (__builtin_offsetof(struct JSGCObjectHeader, link) != 8) return 4;
    #|
    #|  u.h.gc_obj_type = 5;
    #|  u.h.mark = 10;
    #|  u.h.dummy1 = 0x12;
    #|  u.h.dummy2 = 0x3456;
    #|  if (u.bytes[4] != 0xa5) return 5;
    #|  if (u.bytes[5] != 0x12) return 6;
    #|  if (u.bytes[6] != 0x56 || u.bytes[7] != 0x34) return 7;
    #|
    #|  if (sizeof(struct JSObjectLike) != 56) return 8;
    #|  if (__builtin_offsetof(struct JSObjectLike, weakref_count) != 24) return 9;
    #|  if (__builtin_offsetof(struct JSObjectLike, shape) != 32) return 10;
    #|  if (__builtin_offsetof(struct JSObjectLike, prop) != 40) return 11;
    #|  if (__builtin_offsetof(struct JSObjectLike, opaque) != 48) return 12;
    #|  obj.shape = &shape;
    #|  obj.prop = &prop;
    #|  if (obj.shape != &shape) return 13;
    #|  if (obj.prop != &prop) return 14;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e global designated union initializer in function list table" {
  let source =
    #|typedef unsigned char uint8_t;
    #|typedef short int16_t;
    #|
    #|typedef struct Entry {
    #|  const char *name;
    #|  uint8_t prop_flags;
    #|  uint8_t def_type;
    #|  int16_t magic;
    #|  union {
    #|    struct {
    #|      uint8_t length;
    #|      uint8_t cproto;
    #|      void *cfunc;
    #|    } func;
    #|    struct {
    #|      const char *name;
    #|      int base;
    #|    } alias;
    #|    const char *str;
    #|    int i32;
    #|    long i64;
    #|    double f64;
    #|  } u;
    #|} Entry;
    #|
    #|static const Entry tab[] = {
    #|  { "values", 3, 0, 7, .u = { .func = { 2, 9, (void*)0x12345678 } } },
    #|  { "[Symbol.iterator]", 3, 9, 0, .u = { .alias = { "values", -1 } } },
    #|};
    #|
    #|int main(void) {
    #|  if (sizeof(Entry) != 32) return 1;
    #|  if (tab[0].u.func.length != 2) return 2;
    #|  if (tab[0].u.func.cproto != 9) return 3;
    #|  if (tab[0].u.func.cfunc != (void*)0x12345678) return 4;
    #|  if (tab[1].def_type != 9) return 5;
    #|  if (tab[1].u.alias.name[0] != 'v') return 6;
    #|  if (tab[1].u.alias.name[5] != 's') return 7;
    #|  if (tab[1].u.alias.base != -1) return 8;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e global array designators emit class table entries" {
  let source =
    #|enum {
    #|  JS_FUNC_NORMAL = 0,
    #|  JS_FUNC_GENERATOR = 1,
    #|  JS_FUNC_ASYNC = 2,
    #|  JS_FUNC_ASYNC_GENERATOR = 3,
    #|};
    #|static const unsigned short func_kind_to_class_id[] = {
    #|  [JS_FUNC_NORMAL] = 13,
    #|  [JS_FUNC_GENERATOR] = 16,
    #|  [JS_FUNC_ASYNC] = 20,
    #|  [JS_FUNC_ASYNC_GENERATOR] = 21,
    #|};
    #|static const unsigned char range_table[] = {
    #|  [0] = 3,
    #|  9,
    #|  [2 ... 4] = 7,
    #|};
    #|int main(void) {
    #|  if (sizeof(func_kind_to_class_id) != 8) return 1;
    #|  if (func_kind_to_class_id[0] != 13) return 2;
    #|  if (func_kind_to_class_id[1] != 16) return 3;
    #|  if (func_kind_to_class_id[2] != 20) return 4;
    #|  if (func_kind_to_class_id[3] != 21) return 5;
    #|  if (sizeof(range_table) != 5) return 6;
    #|  if (range_table[0] != 3) return 7;
    #|  if (range_table[1] != 9) return 8;
    #|  if (range_table[2] != 7) return 9;
    #|  if (range_table[3] != 7) return 10;
    #|  if (range_table[4] != 7) return 11;
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
async test "e2e local array bound uses sizeof global array" {
  let source =
    #|typedef unsigned char u8;
    #|static const u8 magic[8] = {0xd9,0xd5,0x05,0xf9,0x20,0xa1,0x63,0xd7};
    #|void put4(u8 *p, unsigned v) {
    #|  p[0] = (u8)(v >> 24);
    #|  p[1] = (u8)(v >> 16);
    #|  p[2] = (u8)(v >> 8);
    #|  p[3] = (u8)v;
    #|}
    #|int main() {
    #|  u8 zHeader[sizeof(magic)+4];
    #|  if (sizeof(zHeader) != 12) return 1;
    #|  __builtin_memcpy(zHeader, magic, sizeof(magic));
    #|  put4(&zHeader[sizeof(magic)], 9);
    #|  if (zHeader[0] != 0xd9 || zHeader[7] != 0xd7) return 2;
    #|  if (zHeader[8] != 0 || zHeader[9] != 0) return 3;
    #|  if (zHeader[10] != 0 || zHeader[11] != 9) return 4;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e local array bound uses sizeof struct pointer array field" {
  let source =
    #|struct PagerLike {
    #|  int flags;
    #|  char dbFileVers[16];
    #|};
    #|
    #|int read_version(struct PagerLike *p) {
    #|  char dbFileVers[sizeof(p->dbFileVers)];
    #|  if (sizeof(dbFileVers) != 16) return 1;
    #|  dbFileVers[0] = 40;
    #|  dbFileVers[15] = 2;
    #|  return dbFileVers[0] + dbFileVers[15];
    #|}
    #|
    #|int main(void) {
    #|  struct PagerLike pager;
    #|  return read_version(&pager);
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

///|
async test "e2e nested bit-field assignment returns assigned value" {
  let source =
    #|struct Init {
    #|  unsigned int newTnum;
    #|  unsigned char iDb;
    #|  unsigned char busy;
    #|  unsigned orphanTrigger : 1;
    #|  unsigned imposterTable : 1;
    #|  unsigned reopenMemdb : 1;
    #|};
    #|
    #|int main(void) {
    #|  struct Init init;
    #|  init.newTnum = 0;
    #|  init.iDb = 0;
    #|  init.busy = 0;
    #|  init.orphanTrigger = 0;
    #|  init.imposterTable = 0;
    #|  init.reopenMemdb = 0;
    #|  init.busy = init.imposterTable = 1;
    #|  if (init.imposterTable != 1) return 1;
    #|  if (init.busy != 1) return 2;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e compound assignment updates only target bit-field" {
  let source =
    #|struct ShapeProperty {
    #|  unsigned int hash_next : 26;
    #|  unsigned int flags : 6;
    #|  unsigned int atom;
    #|};
    #|
    #|union ShapeWords {
    #|  struct ShapeProperty p;
    #|  unsigned int words[2];
    #|};
    #|
    #|int main(void) {
    #|  union ShapeWords u = {0};
    #|  unsigned int hash = 0x02345678u & ((1u << 26) - 1);
    #|  u.p.hash_next = hash;
    #|  u.p.flags = 0x2fu;
    #|  if (sizeof(struct ShapeProperty) != 8) return 1;
    #|  if (__builtin_offsetof(struct ShapeProperty, atom) != 4) return 2;
    #|  if (u.p.hash_next != hash) return 3;
    #|  if (u.p.flags != 0x2fu) return 4;
    #|  if ((u.words[0] >> 26) != 0x2fu) return 5;
    #|  u.p.flags &= ~0x0fu;
    #|  if (u.p.flags != 0x20u) return 6;
    #|  if (u.p.hash_next != hash) return 7;
    #|  u.p.flags |= 0x03u;
    #|  if (u.p.flags != 0x23u) return 8;
    #|  if (u.p.hash_next != hash) return 9;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e nonnegative enum bit-field reads as unsigned" {
  let source =
    #|typedef enum {
    #|  CLOSURE_LOCAL,
    #|  CLOSURE_ARG,
    #|  CLOSURE_REF,
    #|  CLOSURE_GLOBAL_REF,
    #|  CLOSURE_GLOBAL_DECL,
    #|  CLOSURE_GLOBAL,
    #|  CLOSURE_MODULE_DECL,
    #|  CLOSURE_MODULE_IMPORT,
    #|} ClosureType;
    #|
    #|struct ClosureVar {
    #|  ClosureType closure_type : 3;
    #|  unsigned char is_lexical : 1;
    #|  unsigned char is_const : 1;
    #|  unsigned char var_kind : 4;
    #|  unsigned short var_idx;
    #|};
    #|
    #|typedef enum {
    #|  NEGATIVE = -1,
    #|  POSITIVE = 1,
    #|} SignedEnum;
    #|
    #|int main(void) {
    #|  struct ClosureVar cv = {0};
    #|  cv.closure_type = CLOSURE_MODULE_IMPORT;
    #|  if (cv.closure_type != CLOSURE_MODULE_IMPORT) return 1;
    #|  if ((int)cv.closure_type < 0) return 2;
    #|  SignedEnum e = (SignedEnum)-1;
    #|  if (e >= 0) return 3;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e static computed-goto dispatch table keeps label addresses" {
  let source =
    #|int main(void) {
    #|  int op = 3;
    #|  static void * const dispatch_table[4] = {
    #|    &&case_zero,
    #|    &&case_one,
    #|    [2 ... 3] = &&case_two,
    #|  };
    #|  goto *dispatch_table[op];
    #|case_zero:
    #|  return 1;
    #|case_one:
    #|  return 2;
    #|case_two:
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e extern globals survive post-declarator attributes" {
  let source =
    #|extern void *__stdoutp __attribute__((__swift_attr__("nonisolated(unsafe)")));
    #|
    #|int main(void) {
    #|  return __stdoutp ? 42 : 1;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e atomic array element access uses element width" {
  let source =
    #|typedef unsigned int u32;
    #|
    #|struct Info {
    #|  u32 pad;
    #|  u32 marks[5];
    #|};
    #|
    #|int main(void) {
    #|  struct Info info;
    #|  info.pad = 0;
    #|  info.marks[0] = 11;
    #|  info.marks[1] = 22;
    #|  if (__atomic_load_n(info.marks + 0, 0) != 11) return 1;
    #|  if (__atomic_load_n(1 + info.marks, 0) != 22) return 2;
    #|  __atomic_store_n(info.marks + 0, 33, 0);
    #|  if (info.marks[0] != 33) return 3;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e static inline function pointer references are emitted" {
  let source =
    #|typedef int (*Callback)(int);
    #|
    #|static inline int cb_inc(int x) {
    #|  return x + 1;
    #|}
    #|
    #|static inline int cb_dec(int x) {
    #|  return x - 1;
    #|}
    #|
    #|static int call_it(Callback cb, int x) {
    #|  return cb(x);
    #|}
    #|
    #|int main(void) {
    #|  Callback cb = 1 ? cb_inc : cb_dec;
    #|  if (call_it(cb, 41) != 42) return 1;
    #|  if (call_it(cb_dec, 43) != 42) return 2;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e atomic add and sub fetch lower to arm64 atomics" {
  let source =
    #|unsigned int value = 10;
    #|int calls = 0;
    #|
    #|unsigned int next_value(void) {
    #|  calls = calls + 1;
    #|  return 5;
    #|}
    #|
    #|int main(void) {
    #|  if (__atomic_add_fetch(&value, next_value(), 5) != 15) return 1;
    #|  if (calls != 1 || value != 15) return 2;
    #|  if (__atomic_sub_fetch(&value, 3U, 5) != 12) return 3;
    #|  if (value != 12) return 4;
    #|  __atomic_store_n(&value, next_value(), 5);
    #|  if (calls != 2 || value != 5) return 5;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e c11 atomic builtins lower without external symbols" {
  let source =
    #|int main(void) {
    #|  _Atomic(unsigned int) x = 5;
    #|  unsigned int expected = 11;
    #|  if (__c11_atomic_fetch_add(&x, 3, 5) != 5) return 1;
    #|  if (x != 8) return 2;
    #|  if (__c11_atomic_fetch_sub(&x, 1, 5) != 8) return 3;
    #|  if (__c11_atomic_fetch_or(&x, 16, 5) != 7) return 4;
    #|  if (__c11_atomic_fetch_and(&x, 23, 5) != 23) return 5;
    #|  if (__c11_atomic_fetch_xor(&x, 3, 5) != 23) return 6;
    #|  if (__c11_atomic_exchange(&x, 11, 5) != 20) return 7;
    #|  if (!__c11_atomic_compare_exchange_strong(&x, &expected, 19, 5, 5)) return 8;
    #|  if (x != 19) return 9;
    #|  expected = 11;
    #|  if (__c11_atomic_compare_exchange_strong(&x, &expected, 21, 5, 5)) return 10;
    #|  if (expected != 19) return 11;
    #|  if (__c11_atomic_load(&x, 5) != 19) return 12;
    #|  __c11_atomic_store(&x, 42, 5);
    #|  return (int)x;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e aligned struct array member decays before by-value call" {
  let source =
    #|struct Value {
    #|  long a;
    #|  long b;
    #|};
    #|
    #|struct Context {
    #|  long prefix[12];
    #|  _Alignas(16) struct Value class_proto[2];
    #|};
    #|
    #|long take(struct Value value) {
    #|  return value.a + value.b;
    #|}
    #|
    #|int main(void) {
    #|  struct Context ctx;
    #|  ctx.class_proto[0].a = 1;
    #|  ctx.class_proto[0].b = 2;
    #|  ctx.class_proto[1].a = 40;
    #|  ctx.class_proto[1].b = 2;
    #|  return (int)take(ctx.class_proto[1]);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e builtin frame address bzero and darwin fd helpers lower" {
  let source =
    #|struct fd_set {
    #|  int fds_bits[32];
    #|};
    #|
    #|int main(void) {
    #|  struct fd_set fds;
    #|  void *ra = __builtin_return_address(0);
    #|  if (__builtin_frame_address(0) == 0) return 1;
    #|  if (__builtin_frame_address(1) != 0) return 2;
    #|  if (ra == 0) return 6;
    #|  if (__builtin_return_address(1) != 0) return 7;
    #|  if (__builtin_extract_return_addr(ra) != ra) return 8;
    #|  if (__builtin_frob_return_addr(ra) != ra) return 9;
    #|  __builtin_bzero(&fds, sizeof(fds));
    #|  __darwin_fd_set(9, &fds);
    #|  if (!__darwin_fd_isset(9, &fds)) return 3;
    #|  if (__darwin_fd_isset(8, &fds)) return 4;
    #|  __darwin_fd_clr(9, &fds);
    #|  if (__darwin_fd_isset(9, &fds)) return 5;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e builtin bswap16 lowers without external symbol" {
  let source =
    #|int main(void) {
    #|  unsigned short x = __builtin_bswap16(0x1234);
    #|  if (x != 0x3412) return 1;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e statement attribute before local declaration" {
  let source =
    #|int main(void) {
    #|  __attribute__((unused)) _Bool ok = 1;
    #|  return ok ? 42 : 1;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e fallthrough attribute statement is a no-op" {
  let source =
    #|int main(void) {
    #|  int x = 0;
    #|  switch (x) {
    #|  case 0:
    #|    x = x + 1;
    #|    __attribute__((fallthrough));
    #|  case 1:
    #|    return x == 1 ? 42 : 2;
    #|  default:
    #|    return 3;
    #|  }
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e large struct parameter is copied from hidden pointer" {
  let source =
    #|struct InputLike {
    #|  void *payload;
    #|  int (*read)(void);
    #|  int encoding;
    #|  void *decode;
    #|};
    #|
    #|int forty_two(void) {
    #|  return 42;
    #|}
    #|
    #|int consume(struct InputLike input) {
    #|  if (input.payload != (void*)0x1234) return 1;
    #|  if (input.encoding != 7) return 2;
    #|  if (!input.read) return 3;
    #|  return input.read();
    #|}
    #|
    #|int main(void) {
    #|  struct InputLike input = {
    #|    (void*)0x1234,
    #|    forty_two,
    #|    7,
    #|    (void*)0,
    #|  };
    #|  return consume(input);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e large struct argument passed to clang callee uses caller copy" {
  let callee =
    #|struct BigArg {
    #|  long a;
    #|  long b;
    #|  long c;
    #|  long d;
    #|};
    #|
    #|int clang_observe(struct BigArg value, struct BigArg *original) {
    #|  value.a = 99;
    #|  if (&value == original) return 1;
    #|  return (int)(value.a + value.d);
    #|}
  let callee_c = temp_file_path("large_struct_clang_callee", callee, ".c")
  let callee_obj = temp_file_path("large_struct_clang_callee", callee, ".o")
  write_text_file(callee_c, callee)
  run_command_checked(
    "clang -c -o " + callee_obj + " " + callee_c,
    "compile large struct clang callee",
  )
  let caller =
    #|struct BigArg {
    #|  long a;
    #|  long b;
    #|  long c;
    #|  long d;
    #|};
    #|
    #|int clang_observe(struct BigArg value, struct BigArg *original);
    #|
    #|int main(void) {
    #|  struct BigArg value = { 1, 2, 3, 4 };
    #|  int seen = clang_observe(value, &value);
    #|  if (seen != 103) return 2;
    #|  if (value.a != 1) return 3;
    #|  return 42;
    #|}
  let caller_obj = compile_source_to_object_path(
    caller, "large_struct_kimicc_caller",
  )
  let bin_path = temp_file_path("large_struct_cross_abi", callee + caller, "")
  run_command_checked(
    "clang -o " + bin_path + " " + caller_obj + " " + callee_obj,
    "link large struct cross abi",
  )
  let result = run_command_capture(bin_path, "large_struct_cross_abi")
  inspect(result.code, content="42")
}

///|
async test "e2e nested union compound literal initializes bitfields" {
  let source =
    #|typedef unsigned char uint8_t;
    #|typedef unsigned short uint16_t;
    #|typedef _Bool bool;
    #|
    #|struct InlineData {
    #|  bool is_inline : 1;
    #|  bool visible : 1;
    #|  bool named : 1;
    #|  bool extra : 1;
    #|  bool has_changes : 1;
    #|  bool is_missing : 1;
    #|  bool is_keyword : 1;
    #|  uint8_t symbol;
    #|  uint16_t parse_state;
    #|  uint8_t padding_columns;
    #|  uint8_t padding_rows : 4;
    #|  uint8_t lookahead_bytes : 4;
    #|  uint8_t padding_bytes;
    #|  uint8_t size_bytes;
    #|};
    #|
    #|union Subtree {
    #|  struct InlineData data;
    #|  void *ptr;
    #|};
    #|
    #|union Subtree make(void) {
    #|  return (union Subtree) {{
    #|    .parse_state = 9,
    #|    .symbol = 7,
    #|    .padding_bytes = 0,
    #|    .padding_rows = 0,
    #|    .padding_columns = 0,
    #|    .size_bytes = 3,
    #|    .lookahead_bytes = 5,
    #|    .visible = 1,
    #|    .named = 1,
    #|    .extra = 0,
    #|    .has_changes = 0,
    #|    .is_missing = 0,
    #|    .is_keyword = 0,
    #|    .is_inline = 1,
    #|  }};
    #|}
    #|
    #|int retain(union Subtree s) {
    #|  if (s.data.is_inline) return 42;
    #|  return 1;
    #|}
    #|
    #|int main(void) {
    #|  union Subtree s = make();
    #|  if (!s.data.is_inline) return 1;
    #|  if (!s.data.visible || !s.data.named) return 2;
    #|  if (s.data.symbol != 7) return 3;
    #|  if (s.data.parse_state != 9) return 4;
    #|  if (s.data.lookahead_bytes != 5) return 5;
    #|  if (s.data.size_bytes != 3) return 6;
    #|  if (((unsigned long)s.ptr & 1UL) != 1UL) return 7;
    #|  return retain(s);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e large struct return uses hidden result pointer" {
  let source =
    #|struct PairArray {
    #|  long a;
    #|  long b;
    #|  long c;
    #|  long d;
    #|};
    #|
    #|struct PairArray make(long base) {
    #|  struct PairArray out = { base, base + 1, base + 2, base + 3 };
    #|  return out;
    #|}
    #|
    #|int main(void) {
    #|  struct PairArray value = make(9);
    #|  if (value.a != 9) return 1;
    #|  if (value.b != 10) return 2;
    #|  if (value.c != 11) return 3;
    #|  if (value.d != 12) return 4;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e discarded large struct return still passes hidden result pointer" {
  let source =
    #|struct PairArray {
    #|  long a;
    #|  long b;
    #|  long c;
    #|  long d;
    #|};
    #|
    #|int observed;
    #|
    #|struct PairArray make(long base) {
    #|  struct PairArray out = { base, base + 1, base + 2, base + 3 };
    #|  observed = (int)out.c;
    #|  return out;
    #|}
    #|
    #|int main(void) {
    #|  make(9);
    #|  if (observed != 11) return 1;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e global nested array designators emit in index order" {
  let source =
    #|unsigned short table[2][4] = {
    #|  [0] = {
    #|    [2] = 4,
    #|    [3] = 5,
    #|    [0] = 1,
    #|    [1] = 2,
    #|  },
    #|  [1] = {
    #|    [3] = 9,
    #|    [0] = 6,
    #|  },
    #|};
    #|
    #|int main(void) {
    #|  if (table[0][0] != 1) return 1;
    #|  if (table[0][1] != 2) return 2;
    #|  if (table[0][2] != 4) return 3;
    #|  if (table[0][3] != 5) return 4;
    #|  if (table[1][0] != 6) return 5;
    #|  if (table[1][1] != 0) return 6;
    #|  if (table[1][2] != 0) return 7;
    #|  if (table[1][3] != 9) return 8;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e sqlite-style unsigned int overflow chain count" {
  let source =
    #|typedef unsigned int u32;
    #|typedef unsigned short u16;
    #|
    #|int main(void) {
    #|  u32 nPayload = 0xffffffffu;
    #|  u16 nLocal = 39;
    #|  u32 ovflPageSize = 508;
    #|  int nOvfl = (nPayload - nLocal + ovflPageSize - 1) / ovflPageSize;
    #|  if (nOvfl != 0) return 1;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e prototype converts float argument to double parameter" {
  let source =
    #|double captured;
    #|
    #|void take_double(double x) {
    #|  captured = x;
    #|}
    #|
    #|int main(void) {
    #|  union RtreeCoord {
    #|    float f;
    #|    unsigned int u;
    #|  } c;
    #|  c.f = 1.0f;
    #|  take_double(c.f);
    #|  if (captured != 1.0) return 1;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e va_arg signed int sign-extends into long long" {
  let source =
    #|typedef __builtin_va_list va_list;
    #|
    #|int read_signed(int tag, ...) {
    #|  va_list ap;
    #|  __builtin_va_start(ap, tag);
    #|  long long prefix = __builtin_va_arg(ap, long long);
    #|  long long value = __builtin_va_arg(ap, int);
    #|  __builtin_va_end(ap);
    #|  if (prefix != 1) return 1;
    #|  if (value != -1074) return 2;
    #|  return 42;
    #|}
    #|
    #|int main(void) {
    #|  int e = 1;
    #|  return read_signed(0, 1LL, e - 1075);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e static local pointer array initializes cast string" {
  let source =
    #|typedef unsigned char u8;
    #|
    #|int main(void) {
    #|  static unsigned char * const azOne[] = { (u8*)" " };
    #|  if (azOne[0] == 0) return 1;
    #|  if (azOne[0][0] != 32) return 2;
    #|  if (azOne[0][1] != 0) return 3;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e direct double return is read from fp register" {
  let source =
    #|double add_half(double x) {
    #|  return x + 0.5;
    #|}
    #|
    #|int main(void) {
    #|  double y = add_half(41.5);
    #|  if (y != 42.0) return 1;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e function pointer double return is read from fp register" {
  let source =
    #|double add_half(double x) {
    #|  return x + 0.5;
    #|}
    #|
    #|int main(void) {
    #|  double (*fp)(double) = add_half;
    #|  double y = fp(41.5);
    #|  if (y != 42.0) return 1;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e ternary conversions preserve scalar and function pointer types" {
  let source =
    #|double add_one(double x) { return x + 1.0; }
    #|double sub_one(double x) { return x - 1.0; }
    #|
    #|double choose_double(int flag) {
    #|  return flag ? 1 : 2.5;
    #|}
    #|
    #|int choose_int(int flag) {
    #|  return flag ? 1.5 : 2;
    #|}
    #|
    #|unsigned long choose_ulong(int flag) {
    #|  return flag ? -1 : 2UL;
    #|}
    #|
    #|int choose_ptr(int flag) {
    #|  int value = 41;
    #|  int *p = flag ? 0 : &value;
    #|  return p ? *p : 0;
    #|}
    #|
    #|double call_selected(int flag, double x) {
    #|  return (flag ? add_one : sub_one)(x);
    #|}
    #|
    #|int main(void) {
    #|  if (choose_double(1) != 1.0) return 1;
    #|  if (choose_double(0) != 2.5) return 2;
    #|  if (choose_int(1) != 1) return 3;
    #|  if (choose_int(0) != 2) return 4;
    #|  if (choose_ulong(1) != (unsigned long)-1) return 5;
    #|  if (choose_ulong(0) != 2UL) return 6;
    #|  if (choose_ptr(1) != 0) return 7;
    #|  if (choose_ptr(0) != 41) return 8;
    #|  if (call_selected(1, 41.0) != 42.0) return 9;
    #|  if (call_selected(0, 43.0) != 42.0) return 10;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e member access reads field from struct call result" {
  let source =
    #|typedef struct Obj Obj;
    #|
    #|struct Obj {
    #|  long header;
    #|  long payload;
    #|};
    #|
    #|typedef union ValueUnion {
    #|  int int32;
    #|  Obj *ptr;
    #|} ValueUnion;
    #|
    #|typedef struct Value {
    #|  ValueUnion u;
    #|  long tag;
    #|} Value;
    #|
    #|Obj global = { 0x000c010000000002L, 42 };
    #|
    #|Value dup_value(Obj *p) {
    #|  Value v;
    #|  v.u.ptr = p;
    #|  v.tag = -1;
    #|  return v;
    #|}
    #|
    #|int main(void) {
    #|  Obj *q = dup_value(&global).u.ptr;
    #|  if (q != &global) return 1;
    #|  return q->payload;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e aggregate field from struct call passes by value" {
  let source =
    #|typedef struct Point {
    #|  unsigned row;
    #|  unsigned column;
    #|} Point;
    #|
    #|typedef struct Length {
    #|  unsigned bytes;
    #|  Point extent;
    #|} Length;
    #|
    #|Length size_of_node(void) {
    #|  Length length;
    #|  length.bytes = 9;
    #|  length.extent.row = 4;
    #|  length.extent.column = 7;
    #|  return length;
    #|}
    #|
    #|int consume_point(Point point) {
    #|  if (point.row != 4) return 1;
    #|  if (point.column != 7) return 2;
    #|  return 42;
    #|}
    #|
    #|int main(void) {
    #|  return consume_point(size_of_node().extent);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e parameter shadowing preserves compound literal frame slot" {
  let source =
    #|typedef struct Pair {
    #|  long a;
    #|  long b;
    #|} Pair;
    #|
    #|int sum_pair(Pair v) {
    #|  return (int)(v.a + v.b);
    #|}
    #|
    #|int foo(int name) {
    #|  goto done;
    #|done:
    #|  {
    #|    int result;
    #|    int name = 7;
    #|    result = sum_pair((Pair){ .a = 1, .b = 2 });
    #|    return name + result;
    #|  }
    #|}
    #|
    #|int main(void) {
    #|  return foo(5);
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="10")
}

///|
async test "e2e global floating initializer folds infinities and nan" {
  let source =
    #|double pos = 1.0 / 0.0;
    #|double neg = -__builtin_huge_valf();
    #|double nanv = __builtin_nanf("0x7fc00000");
    #|
    #|int main(void) {
    #|  if (!(pos > 2147483647.0)) return 1;
    #|  if (!(neg < -2147483647.0)) return 2;
    #|  if (nanv == nanv) return 3;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e local floating builtins produce infinities and nan" {
  let source =
    #|typedef union Box {
    #|  double d;
    #|  long bits;
    #|} Box;
    #|
    #|int main(void) {
    #|  Box nan_box = { .d = __builtin_nanf("0x7fc00000") };
    #|  double inf = __builtin_huge_valf();
    #|  if (nan_box.d == nan_box.d) return 1;
    #|  if (!(inf > 2147483647.0)) return 2;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e floating square root builtins lower" {
  let source =
    #|int main(void) {
    #|  double d = __builtin_sqrt(144.0);
    #|  float f = __builtin_sqrtf(361.0f);
    #|  long double l = __builtin_sqrtl(121.0L);
    #|  return (int)d + (int)f + (int)l;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e nested designator advances following struct initializer" {
  let source =
    #|typedef union ValueUnion {
    #|  double float64;
    #|  long int64;
    #|} ValueUnion;
    #|
    #|typedef struct Value {
    #|  ValueUnion u;
    #|  int tag;
    #|} Value;
    #|
    #|int main(void) {
    #|  Value v = { .u.float64 = __builtin_nanf("0x7fc00000"), 8 };
    #|  if (v.tag != 8) return 1;
    #|  if (v.u.float64 == v.u.float64) return 2;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e local nested aggregate initializer preserves struct field" {
  let source =
    #|typedef struct Point {
    #|  unsigned row;
    #|  unsigned column;
    #|} Point;
    #|
    #|typedef struct Length {
    #|  unsigned bytes;
    #|  Point extent;
    #|} Length;
    #|
    #|unsigned five(void) {
    #|  return 5;
    #|}
    #|
    #|Length make_length(void) {
    #|  Length result = {five(), {0, five()}};
    #|  return result;
    #|}
    #|
    #|int main(void) {
    #|  Length l = make_length();
    #|  if (l.bytes != 5) return 1;
    #|  if (l.extent.row != 0) return 2;
    #|  if (l.extent.column != 5) return 3;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e local mixed initializer designators" {
  let source =
    #|typedef struct Pair {
    #|  int a;
    #|  int b;
    #|} Pair;
    #|
    #|typedef struct Wrap {
    #|  Pair pairs[2];
    #|  int arr[3];
    #|} Wrap;
    #|
    #|int main(void) {
    #|  Wrap local = { .pairs[1].b = 5, .pairs[0].a = 37, .arr[2] = 35 };
    #|  Wrap literal = (Wrap){ .pairs[0].b = 2, .arr[1] = 4 };
    #|  if (local.pairs[0].a != 37 || local.pairs[0].b != 0) return 1;
    #|  if (local.pairs[1].a != 0 || local.pairs[1].b != 5) return 2;
    #|  if (local.arr[0] != 0 || local.arr[1] != 0 || local.arr[2] != 35) return 3;
    #|  if (literal.pairs[0].a != 0 || literal.pairs[0].b != 2) return 4;
    #|  if (literal.pairs[1].a != 0 || literal.pairs[1].b != 0) return 5;
    #|  if (literal.arr[0] != 0 || literal.arr[1] != 4 || literal.arr[2] != 0) return 6;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
async test "e2e unsigned int128 supports wide limb arithmetic" {
  let source =
    #|typedef unsigned __int128 u128;
    #|
    #|u128 mk(unsigned long a, unsigned long b) {
    #|  return (u128)a * (u128)b;
    #|}
    #|
    #|unsigned long lo(u128 x) {
    #|  return (unsigned long)x;
    #|}
    #|
    #|unsigned long hi(u128 x) {
    #|  return (unsigned long)(x >> 64);
    #|}
    #|
    #|unsigned long divlo(u128 x, unsigned long d) {
    #|  return (unsigned long)(x / d);
    #|}
    #|
    #|unsigned long modlo(u128 x, unsigned long d) {
    #|  return (unsigned long)(x % d);
    #|}
    #|
    #|int main(void) {
    #|  unsigned long all = ~0UL;
    #|  u128 x;
    #|  if (sizeof(u128) != 16) return 1;
    #|  x = mk(65536UL, 65536UL);
    #|  if (lo(x) != 4294967296UL) return 2;
    #|  if (hi(x) != 0UL) return 3;
    #|  x = mk(all, 2UL);
    #|  if (lo(x) != all - 1UL) return 4;
    #|  if (hi(x) != 1UL) return 5;
    #|  if (divlo(x, 3UL) != 12297829382473034410UL) return 6;
    #|  if (modlo(x, 3UL) != 0UL) return 7;
    #|  return 42;
    #|}
  let exit_code = run_source_async(source)
  inspect(exit_code, content="42")
}

///|
/// Builds a program whose `switch` statements exercise the shapes a case table
/// can take: fallthrough between clauses, `default` written in the middle,
/// nested switches whose clauses repeat the outer values, negative clause
/// values, and clauses buried inside a block or a loop within the switch body.
///
/// The clause values move with `case_index` so that the corpus does not
/// accidentally agree with clang only for one particular constant.
fn deterministic_switch_clause_differential_source(case_index : Int) -> String {
  let base = case_index * 7 + 2
  let low = base.to_string()
  let mid = (base + 1).to_string()
  let high = (base + 2).to_string()
  let source = StringBuilder::new()
  source.write_string("#include <stdio.h>\n")
  // Fallthrough, and a `default` that is neither first nor last.
  source.write_string("static int clause_mix(int n) {\n")
  source.write_string("  int total = 0;\n")
  source.write_string("  switch (n) {\n")
  source.write_string("    case " + low + ": total += 1;\n")
  source.write_string("    case " + mid + ": total += 2; break;\n")
  source.write_string("    default: total += 4; break;\n")
  source.write_string("    case " + high + ": total += 8;\n")
  source.write_string("  }\n")
  source.write_string("  return total + 16;\n")
  source.write_string("}\n")
  // Inner switches reuse the outer clause values: each switch owns its own.
  source.write_string("static int nested_dispatch(int outer, int inner) {\n")
  source.write_string("  int r = 0;\n")
  source.write_string("  switch (outer) {\n")
  source.write_string("    case " + low + ":\n")
  source.write_string("      switch (inner) {\n")
  source.write_string("        case " + low + ": r = 11; break;\n")
  source.write_string("        default: r = 19; break;\n")
  source.write_string("        case " + mid + ": r = 12; break;\n")
  source.write_string("      }\n")
  source.write_string("      break;\n")
  source.write_string("    case " + mid + ":\n")
  source.write_string("      switch (inner) {\n")
  source.write_string("        case " + low + ": r = 21;\n")
  source.write_string("        case " + mid + ": r += 22; break;\n")
  source.write_string("        default: r = 29;\n")
  source.write_string("      }\n")
  source.write_string("      break;\n")
  source.write_string("    default: r = 99;\n")
  source.write_string("  }\n")
  source.write_string("  return r;\n")
  source.write_string("}\n")
  source.write_string("static long negative_span(long n) {\n")
  source.write_string("  switch (n) {\n")
  source.write_string("    case -" + low + ": return -1;\n")
  source.write_string("    case -1: return -2;\n")
  source.write_string("    case 0: return 3;\n")
  source.write_string("    default: return 4;\n")
  source.write_string("  }\n")
  source.write_string("}\n")
  // A clause inside a block of the switch body: control still enters it.
  source.write_string("static int block_clause(unsigned n) {\n")
  source.write_string("  int r = 0;\n")
  source.write_string("  switch (n) {\n")
  source.write_string("    case " + low + ": r = 1; break;\n")
  source.write_string("    { case " + mid + ": r = 2; break; }\n")
  source.write_string("    default: r = 3;\n")
  source.write_string("  }\n")
  source.write_string("  return r;\n")
  source.write_string("}\n")
  // A written label ahead of a clause, jumped back into from inside it.
  source.write_string("static int label_before_clause(int n) {\n")
  source.write_string("  int r = 0;\n")
  source.write_string("  int again = 0;\n")
  source.write_string("  switch (n) {\n")
  source.write_string("    top:\n")
  source.write_string("    case " + low + ":\n")
  source.write_string("      r += 3;\n")
  source.write_string("      if (again == 0) { again = 1; goto top; }\n")
  source.write_string("      break;\n")
  source.write_string("    default: r = 7;\n")
  source.write_string("  }\n")
  source.write_string("  return r;\n")
  source.write_string("}\n")
  source.write_string("static int char_clause(char c) {\n")
  source.write_string("  switch (c) {\n")
  source.write_string("    case 'a': return 1;\n")
  source.write_string("    case 'z': return 26;\n")
  source.write_string("    case '0': return 48;\n")
  source.write_string("    default: return 0;\n")
  source.write_string("  }\n")
  source.write_string("}\n")
  // Duff's device: clauses interleaved with a loop the dispatch jumps into.
  source.write_string("static int duffs(int count) {\n")
  source.write_string("  int out = 0;\n")
  source.write_string("  int n = (count + 7) / 8;\n")
  source.write_string("  switch (count % 8) {\n")
  source.write_string("    case 0: do { out += 1;\n")
  source.write_string("    case 7:      out += 2;\n")
  source.write_string("    case 6:      out += 3;\n")
  source.write_string("    case 5:      out += 4;\n")
  source.write_string("    case 4:      out += 5;\n")
  source.write_string("    case 3:      out += 6;\n")
  source.write_string("    case 2:      out += 7;\n")
  source.write_string("    case 1:      out += 8;\n")
  source.write_string("            } while (--n > 0);\n")
  source.write_string("  }\n")
  source.write_string("  return out;\n")
  source.write_string("}\n")
  source.write_string("int main(void) {\n")
  source.write_string("  long acc = 0;\n")
  source.write_string(
    "  for (int i = " + low + " - 2; i <= " + high + " + 1; i = i + 1) {\n",
  )
  source.write_string("    printf(\"mix %d=%d\\n\", i, clause_mix(i));\n")
  source.write_string("    acc += clause_mix(i);\n")
  source.write_string(
    "    for (int j = " + low + " - 1; j <= " + mid + " + 1; j = j + 1) {\n",
  )
  source.write_string(
    "      printf(\"nested %d,%d=%d\\n\", i, j, nested_dispatch(i, j));\n",
  )
  source.write_string("      acc += nested_dispatch(i, j);\n")
  source.write_string("    }\n")
  source.write_string(
    "    printf(\"block %d=%d label %d=%d\\n\", i, block_clause((unsigned)i), i, label_before_clause(i));\n",
  )
  source.write_string(
    "    acc += block_clause((unsigned)i) + label_before_clause(i);\n",
  )
  source.write_string("  }\n")
  source.write_string("  for (long i = -" + high + "; i <= 1; i = i + 1) {\n")
  source.write_string("    printf(\"neg %ld=%ld\\n\", i, negative_span(i));\n")
  source.write_string("    acc += negative_span(i);\n")
  source.write_string("  }\n")
  source.write_string("  for (int i = 0; i < 4; i = i + 1) {\n")
  source.write_string("    char c = \"az0q\"[i];\n")
  source.write_string("    printf(\"char %c=%d\\n\", c, char_clause(c));\n")
  source.write_string("    acc += char_clause(c);\n")
  source.write_string("  }\n")
  source.write_string("  for (int i = 1; i <= 19; i = i + 1) {\n")
  source.write_string("    printf(\"duff %d=%d\\n\", i, duffs(i));\n")
  source.write_string("    acc += duffs(i);\n")
  source.write_string("  }\n")
  source.write_string("  printf(\"case=%d acc=%ld\\n\", ")
  source.write_string(case_index.to_string())
  source.write_string(", acc);\n")
  source.write_string("  return (int)(acc & 127);\n")
  source.write_string("}\n")
  source.to_string()
}

///|
async test "e2e deterministic switch clause differential corpus matches clang" {
  for case_index in [0, 1, 2, 3, 4, 5, 6, 7] {
    let result = run_source_against_clang_baseline(
      deterministic_switch_clause_differential_source(case_index),
      "switch_clause_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
async test "e2e direct Mach-O switch clause differential corpus matches clang" {
  for case_index in [0, 1, 2, 3] {
    let result = run_source_direct_object_against_clang_baseline(
      deterministic_switch_clause_differential_source(case_index),
      "direct_switch_clause_differential_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}

///|
/// The parser-direct code generator consumes the AST rather than MIR, so it
/// synthesizes clause labels itself and needs its own differential.
async test "e2e parser codegen switch clause differential matches strict MIR" {
  for case_index in [0, 1, 2, 3] {
    let result = run_source_strict_mir_against_parser_codegen(
      deterministic_switch_clause_differential_source(case_index),
      "parser_codegen_switch_clause_" + case_index.to_string(),
    )
    assert_true(result.output.contains("case=" + case_index.to_string()))
  }
}
