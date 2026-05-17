///|
fn expect_semantic_ok(source : String) -> Unit {
  match @parser.validate_semantics(@parser.parse(source)) {
    Ok(_) => ()
    Err(err) => abort("expected semantic validation to pass: " + err)
  }
}

///|
fn expect_semantic_error(source : String, expected : String) -> Unit {
  match @parser.validate_semantics(@parser.parse(source)) {
    Ok(_) => abort("expected semantic validation to fail")
    Err(err) =>
      if !err.contains(expected) {
        abort("expected error containing '" + expected + "', got: " + err)
      }
  }
}

///|
test "semantic validation accepts direct codegen basics" {
  let source =
    #|int add(int a, int b) { return a + b; }
    #|int main(void) {
    #|  int xs[2] = { 1, 2 };
    #|  int *p = xs;
    #|  return add(p[0], *(p + 1));
    #|}
  expect_semantic_ok(source)
}

///|
test "semantic validation accepts dereferenced function pointer call" {
  let source =
    #|struct Pair { long a; long b; };
    #|int pair_sum(struct Pair p) { return p.a + p.b; }
    #|struct Pair make_pair(long a, long b) {
    #|  struct Pair p;
    #|  p.a = a;
    #|  p.b = b;
    #|  return p;
    #|}
    #|int main(void) {
    #|  int (*ps)(struct Pair) = pair_sum;
    #|  struct Pair (*mk)(long, long) = make_pair;
    #|  return (*ps)(mk(0, 1));
    #|}
  expect_semantic_ok(source)
}

///|
test "semantic validation rejects pointer plus pointer" {
  let source =
    #|int main(void) {
    #|  int *p;
    #|  int *q;
    #|  return p + q;
    #|}
  expect_semantic_error(source, "pointer plus pointer")
}

///|
test "semantic validation rejects call of scalar local" {
  let source =
    #|int main(void) {
    #|  int x = 0;
    #|  return x();
    #|}
  expect_semantic_error(source, "called object is not a function: x")
}

///|
test "semantic validation rejects field access on incomplete aggregate" {
  let source =
    #|int main(void) {
    #|  struct S s;
    #|  return s.x;
    #|}
  expect_semantic_error(source, "incomplete aggregate type: S")
}

///|
test "semantic validation rejects dereference of scalar" {
  let source =
    #|int main(void) {
    #|  int x = 1;
    #|  return *x;
    #|}
  expect_semantic_error(source, "cannot dereference non-pointer expression")
}
