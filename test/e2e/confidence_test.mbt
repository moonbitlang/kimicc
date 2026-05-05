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
