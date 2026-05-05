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
