///|
/// Asserts the printer's round-trip guarantee for `source`.
///
/// The guarantee has two halves:
///
/// 1. **The printed form is a fixed point.** Printing, reparsing, and printing
///    again yields byte-identical text. This is what catches a printer that
///    drops or garbles a construct.
/// 2. **The AST is a fixed point from the first print onward.** Parsing the
///    printed text twice yields structurally equal programs.
///
/// The first print may canonicalize, so generation 1 and generation 2 are not
/// required to be identical. The one known canonicalization is declaration
/// grouping: the parser records `int a, b;` as a `StmtList` of two `VarDecl`s,
/// and printing one declarator per statement erases that grouping. It carries
/// no meaning, and one declarator per statement is the friendlier shape to
/// generate and consume. Everything outside function bodies -- aggregates and
/// globals -- must survive the first print exactly, which is asserted below.
fn assert_roundtrips(source : String) -> Unit raise {
  let first = @parser.parse(source)
  let printed = @printer.print_program(first)
  let second = @parser.parse(printed)
  let reprinted = @printer.print_program(second)
  let third = @parser.parse(reprinted)
  // Text is a fixed point immediately. Comparing text first makes a failure a
  // readable diff rather than "these trees differ".
  assert_eq(printed, reprinted)
  // Aggregates and globals round-trip exactly on the first print.
  assert_eq(first.structs, second.structs)
  assert_eq(first.globals, second.globals)
  // Nothing may be dropped or invented.
  assert_eq(first.decls.length(), second.decls.length())
  // From the first print on, the whole AST is stable.
  assert_eq(second.structs, third.structs)
  assert_eq(second.globals, third.globals)
  assert_eq(second.decls, third.decls)
}

///|
test "roundtrip expressions and precedence" {
  let source =
    #|int compute(int a, int b, int c) {
    #|  int x = a + b * c;
    #|  int y = (a + b) * c;
    #|  int z = a - (b - c);
    #|  int w = a << b | c & a ^ b;
    #|  int v = a < b == c > a;
    #|  int u = a ? b : c;
    #|  int t = a = b = c;
    #|  int s = -(-a);
    #|  int r = !a && (b || c);
    #|  int q = (a % b) / c;
    #|  return x + y + z + w + v + u + t + s + r + q;
    #|}
  assert_roundtrips(source)
}

///|
test "roundtrip pointer and array declarators" {
  let source =
    #|int take(int *p, int **pp, char *s[], int (*fp)(int, int)) {
    #|  int arr[4];
    #|  int *parr[4];
    #|  int (*aptr)[4];
    #|  arr[0] = *p;
    #|  parr[1] = p;
    #|  aptr = &arr;
    #|  return fp(arr[0], **pp) + (int)(long)s;
    #|}
  assert_roundtrips(source)
}

///|
test "roundtrip control flow" {
  let source =
    #|int flow(int n) {
    #|  int total = 0;
    #|  for (int i = 0; i < n; i++) {
    #|    if (i % 2 == 0) {
    #|      total += i;
    #|    } else {
    #|      total -= i;
    #|    }
    #|  }
    #|  while (total > 100) {
    #|    total /= 2;
    #|  }
    #|  do {
    #|    total++;
    #|  } while (total < 10);
    #|  return total;
    #|}
  assert_roundtrips(source)
}

///|
test "roundtrip switch statements" {
  let source =
    #|int classify(int n) {
    #|  int out = 0;
    #|  switch (n) {
    #|    case 0:
    #|      out = 10;
    #|      break;
    #|    case 1:
    #|      out = 20;
    #|      break;
    #|    default:
    #|      out = 30;
    #|      break;
    #|  }
    #|  return out;
    #|}
  assert_roundtrips(source)
}

///|
/// The shapes a case table can take, all of which the printer has to write back
/// as ordinary C: fallthrough, `default` in the middle, a nested switch whose
/// clauses repeat the outer values, a negative value, and clauses buried in a
/// block or a loop.
test "roundtrip switch clause shapes" {
  let source =
    #|int shapes(int a, int b) {
    #|  int r = 0;
    #|  switch (a) {
    #|    case -3:
    #|      r = 1;
    #|    case 0:
    #|      r += 2;
    #|      break;
    #|    default:
    #|      r = 3;
    #|      break;
    #|    case 1:
    #|      switch (b) {
    #|        case -3:
    #|          r = 4;
    #|          break;
    #|        default:
    #|          r = 5;
    #|      }
    #|      break;
    #|    {
    #|      case 2:
    #|        r = 6;
    #|        break;
    #|    }
    #|    top:
    #|    case 3:
    #|      r += 7;
    #|      if (r < 20) goto top;
    #|      break;
    #|    case 4:
    #|      while (r < 30) {
    #|        case 5:
    #|          r += 8;
    #|      }
    #|      break;
    #|  }
    #|  return r;
    #|}
  assert_roundtrips(source)
}

///|
/// A clause prints as the C that produced it, not as the label the parser used
/// to record it with.
test "clauses print as case and default" {
  let source =
    #|int f(int n) {
    #|  switch (n) {
    #|    case -1: return 1;
    #|    default: return 2;
    #|  }
    #|}
  inspect(
    @printer.print_program(@parser.parse(source)).trim().to_owned(),
    content=(
      #|int f(int n) {
      #|  switch (n) {
      #|    case -1:
      #|    return 1;
      #|    default:
      #|    return 2;
      #|  }
      #|}
    ),
  )
}

///|
test "roundtrip structs unions and bit-fields" {
  let source =
    #|struct Point { int x; int y; };
    #|union Value { int i; double d; char bytes[8]; };
    #|struct Flags { unsigned a : 3; unsigned b : 5; int c; };
    #|int use(struct Point *p, union Value v, struct Flags f) {
    #|  return p->x + p->y + v.i + f.a + f.b + f.c;
    #|}
  assert_roundtrips(source)
}

///|
test "roundtrip packed aggregates preserves layout" {
  // The pack cap is layout, not decoration: if the printer dropped it the
  // output would compile to a different ABI.
  let source =
    #|struct Attr { char c; long long v; } __attribute__((packed));
    #|#pragma pack(push, 4)
    #|struct Pragma4 { char c; long long v; };
    #|#pragma pack(pop)
    #|struct Natural { char c; long long v; };
    #|int sizes(void) {
    #|  return (int)(sizeof(struct Attr) + sizeof(struct Pragma4) + sizeof(struct Natural));
    #|}
  assert_roundtrips(source)
}

///|
test "roundtrip globals and storage classes" {
  let source =
    #|int shared = 7;
    #|static int private_counter = 0;
    #|extern int elsewhere;
    #|static const char *name = "hello\n\t\"world\"";
    #|int table[4] = { 1, 2, 3, 4 };
    #|static int bump(void) { return ++private_counter; }
    #|inline int peek(void) { return shared; }
    #|int reach(void) { return elsewhere + bump() + peek() + table[0] + (int)name[0]; }
  assert_roundtrips(source)
}

///|
test "roundtrip sizeof alignof and casts" {
  let source =
    #|struct Big { int a[16]; };
    #|int measure(void) {
    #|  unsigned long a = sizeof(struct Big);
    #|  unsigned long b = sizeof(int *);
    #|  unsigned long c = _Alignof(double);
    #|  int d = (int)(char)(long)a;
    #|  return (int)(a + b + c) + d;
    #|}
  assert_roundtrips(source)
}

///|
test "roundtrip goto and labels" {
  let source =
    #|int jumpy(int n) {
    #|  int i = 0;
    #|top:
    #|  i++;
    #|  if (i < n) {
    #|    goto top;
    #|  }
    #|  return i;
    #|}
  assert_roundtrips(source)
}

///|
test "roundtrip variadic and function pointers" {
  let source =
    #|int sum(int count, ...);
    #|int apply(int (*op)(int, int), int a, int b) { return op(a, b); }
    #|int add(int a, int b) { return a + b; }
    #|int driver(void) { return apply(add, 1, 2) + sum(2, 3, 4); }
  assert_roundtrips(source)
}

///|
test "roundtrip string escapes" {
  let source =
    #|const char *quoted = "a\"b";
    #|const char *escaped = "tab\there\nnewline";
    #|const char *backslash = "back\\slash";
    #|const char *nul_ish = "\001\002\177";
    #|int len(void) { return (int)(quoted[0] + escaped[0] + backslash[0] + nul_ish[0]); }
  assert_roundtrips(source)
}

///|
test "roundtrip nested aggregates" {
  let source =
    #|struct Inner { int a; int b; };
    #|struct Outer { struct Inner inner; int tail; };
    #|int reach(struct Outer *o) { return o->inner.a + o->inner.b + o->tail; }
  assert_roundtrips(source)
}

///|
/// Printing is idempotent: printing an already-printed program changes nothing.
/// A printer that is not idempotent cannot be trusted to be a fixed point, even
/// if a single roundtrip happens to succeed.
test "printing is idempotent" {
  let source =
    #|struct S { int a; char b; };
    #|int f(struct S *s, int n) {
    #|  int t = 0;
    #|  for (int i = 0; i < n; i++) { t += s->a * i - s->b; }
    #|  return t;
    #|}
  let once = @printer.print_program(@parser.parse(source))
  let twice = @printer.print_program(@parser.parse(once))
  let thrice = @printer.print_program(@parser.parse(twice))
  assert_eq(once, twice)
  assert_eq(twice, thrice)
}

///|
/// Local aggregate initializers, which the parser used to lower into a `= 0`
/// marker plus element assignments. That shape had no printable form -- the
/// assignments were ordinary statements by the time the printer saw them, so a
/// declaration came back out as several -- and these round-trip only because
/// the AST now records the braces that were written.
test "roundtrip local aggregate initializers" {
  let source =
    #|struct P { int x; int y; };
    #|struct Nest { struct P p; int tail; };
    #|union U { int i; char c[4]; };
    #|int shapes(void) {
    #|  int partial[5] = { 1, 2, 3 };
    #|  int inferred[] = { 1, 2, 3 };
    #|  int empty[3] = { 0 };
    #|  int indexed[6] = { [2] = 7, [4] = 9 };
    #|  int ranged[6] = { [1 ... 3] = 9 };
    #|  struct P positional = { 1, 2 };
    #|  struct P designated = { .y = 5 };
    #|  struct P structs[2] = { { 1, 2 }, { 3, 4 } };
    #|  struct Nest nested = { { 1, 2 }, 3 };
    #|  struct Nest deep = { .p = { .y = 7 }, .tail = 3 };
    #|  union U tagged = { .i = 42 };
    #|  int matrix[2][3] = { { 1, 2, 3 }, { 4, 5, 6 } };
    #|  int braced[2] = { { 5 }, { 37 } };
    #|  return partial[0] + inferred[0] + empty[0] + indexed[2] + ranged[1] +
    #|      positional.x + designated.y + structs[1].x + nested.tail + deep.p.y +
    #|      tagged.i + matrix[1][2] + braced[0];
    #|}
  assert_roundtrips(source)
}

///|
/// A string initializing a `char` array is the other construct the parser used
/// to expand, one element assignment per byte plus the terminator.
test "roundtrip char array string initializers" {
  let source =
    #|struct Named { char name[8]; int id; };
    #|int strings(void) {
    #|  char inferred[] = "abc";
    #|  char padded[8] = "hi";
    #|  char exact[3] = "abc";
    #|  char escaped[] = "a\tb\\c";
    #|  struct Named member = { "hi", 5 };
    #|  return inferred[0] + padded[1] + exact[2] + escaped[0] + member.id;
    #|}
  assert_roundtrips(source)
}

///|
/// Declarations that C groups under one specifier. The AST records one per
/// name, so the round-trip proves the printer regroups them wherever C insists
/// on the grouping -- which is the `for` initializer and nowhere else.
test "roundtrip declaration groups" {
  let source =
    #|int shapes(int len, int *head) {
    #|  int a = 1, b = 2, c[2] = { 7, 8 };
    #|  int *p = &a, q = 9;
    #|  char x = 'x', buf[4] = "hi";
    #|  _Alignas(16) int aligned = 1, also_aligned = 2;
    #|  int total = 0;
    #|  for (int i = 0, n = len; i < n; i++) {
    #|    total += i;
    #|  }
    #|  for (int i = 0, *walk = head, pair[2]; i < len; i++) {
    #|    total += pair[0] + (walk != 0);
    #|  }
    #|  for (a = 0, b = len; a < b; a++) {
    #|    total += a;
    #|  }
    #|  for (;;) {
    #|    break;
    #|  }
    #|  return total + b + c[0] + q + x + buf[0] + aligned + also_aligned + *p;
    #|}
  assert_roundtrips(source)
}
