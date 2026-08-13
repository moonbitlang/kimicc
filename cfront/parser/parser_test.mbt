///|
test "parse simple function" {
  let source = "int main() { return 42; }"
  let prog = @parser.parse(source)
  inspect(prog.decls.length(), content="1")
  let decl = prog.decls[0]
  inspect(decl.name, content="main")
  inspect(decl.ret, content="SInt")
  inspect(decl.params.length(), content="0")
}

///|
test "parse function with params" {
  let source = "int add(int a, int b) { return a + b; }"
  let prog = @parser.parse(source)
  inspect(prog.decls.length(), content="1")
  let decl = prog.decls[0]
  inspect(decl.name, content="add")
  inspect(decl.params.length(), content="2")
  inspect(decl.params[0].name, content="a")
  inspect(decl.params[1].name, content="b")
}

///|
test "parse attributed typedef before prototype" {
  let source =
    #|__attribute__((__swift_name__("WorkGroup"))) typedef struct os_workgroup_s *os_workgroup_t;
    #|int os_workgroup_copy_port(os_workgroup_t wg);
  let prog = @parser.parse(source)
  match prog.decls {
    [{ name: "os_workgroup_copy_port", params: [{ name: "wg", .. }], .. }] => ()
    _ => fail("Expected attributed typedef to be visible in prototype")
  }
}

///|
test "parse variable declaration" {
  let source = "int main() { int x = 10; return x; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound(stmts)) => {
      inspect(stmts.length(), content="2")
      match stmts[0] {
        VarDecl(SInt, "x", Some(Number(10, _, _))) => ()
        _ => fail("Expected VarDecl")
      }
    }
    _ => fail("Expected compound body")
  }
}

///|
test "parse function pointer parameter types" {
  let source =
    #|int main() {
    #|  int (*fp)(float, double) = 0;
    #|  int (*vp)(int, ...) = 0;
    #|  return 0;
    #|}
  let prog = @parser.parse(source)
  match prog.decls[0].body {
    Some(
      Compound(
        [
          VarDecl(fp_ty, "fp", Some(Number(0, _, SInt))),
          VarDecl(vp_ty, "vp", Some(Number(0, _, SInt))),
          Return(Some(Number(0, _, SInt))),
        ]
      )
    ) => {
      inspect(fp_ty, content="FuncPtr(SInt, [Float, Double], false)")
      inspect(vp_ty, content="FuncPtr(SInt, [SInt], true)")
    }
    _ => fail("Expected typed function pointer locals")
  }
}

///|
test "parse unsupported float16 external declaration as placeholder type" {
  let source = "extern _Float16 __fabsf16(_Float16);"
  let prog = @parser.parse(source)
  match prog.decls[0] {
    { ret: Float16, name: "__fabsf16", params: [{ ty: Float16, .. }], .. } => ()
    _ => fail("Expected _Float16 placeholder function declaration")
  }
}

///|
test "parse unsupported float128 external declaration as placeholder type" {
  let source = "extern __float128 fabsq(__float128);"
  let prog = @parser.parse(source)
  match prog.decls[0] {
    { ret: Float128, name: "fabsq", params: [{ ty: Float128, .. }], .. } => ()
    _ => fail("Expected __float128 placeholder function declaration")
  }
}

///|
test "parse standard extended float spellings used by glibc math" {
  let source = "extern _Float32 f32(_Float64, _Float32x, _Float64x);"
  let prog = @parser.parse(source)
  match prog.decls[0] {
    {
      ret: Float,
      name: "f32",
      params: [{ ty: Double, .. }, { ty: Double, .. }, { ty: LongDouble, .. }],
      ..,
    } => ()
    _ => fail("Expected extended float aliases")
  }
}

///|
test "parse extended float spellings in sizeof and alignof type names" {
  let linux = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => fail("linux-amd64 target should parse")
  }
  let source =
    #|int main(void) {
    #|  int f16_size[sizeof(_Float16)];
    #|  int f32_size[sizeof(_Float32)];
    #|  int f64_size[sizeof(_Float64)];
    #|  int f32x_size[sizeof(_Float32x)];
    #|  int f64x_size[sizeof(_Float64x)];
    #|  int f16_align[__alignof__(_Float16)];
    #|  int f32_align[__alignof__(_Float32)];
    #|  int f64_align[__alignof__(_Float64)];
    #|  int f32x_align[__alignof__(_Float32x)];
    #|  int f64x_align[__alignof__(_Float64x)];
    #|  return 0;
    #|}
  let prog = @parser.parse_for_target(source, linux)
  match prog.decls[0].body {
    Some(
      Compound(
        [
          VarDecl(Array(SInt, 2), "f16_size", None),
          VarDecl(Array(SInt, 4), "f32_size", None),
          VarDecl(Array(SInt, 8), "f64_size", None),
          VarDecl(Array(SInt, 8), "f32x_size", None),
          VarDecl(Array(SInt, 16), "f64x_size", None),
          VarDecl(Array(SInt, 2), "f16_align", None),
          VarDecl(Array(SInt, 4), "f32_align", None),
          VarDecl(Array(SInt, 8), "f64_align", None),
          VarDecl(Array(SInt, 8), "f32x_align", None),
          VarDecl(Array(SInt, 16), "f64x_align", None),
          Return(Some(Number(0, _, SInt))),
        ]
      )
    ) => ()
    _ => fail("Expected extended float type-name layout constants")
  }
}

///|
test "parse unsupported float128 layout constants for linux" {
  let linux = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => fail("linux-amd64 target should parse")
  }
  let source =
    #|int main(void) {
    #|  int q_size[sizeof(__float128)];
    #|  int q_align[__alignof__(_Float128)];
    #|  return 0;
    #|}
  let prog = @parser.parse_for_target(source, linux)
  match prog.decls[0].body {
    Some(
      Compound(
        [
          VarDecl(Array(SInt, 16), "q_size", None),
          VarDecl(Array(SInt, 16), "q_align", None),
          Return(Some(Number(0, _, SInt))),
        ]
      )
    ) => ()
    _ => fail("Expected float128 placeholder layout constants")
  }
}

///|
test "parse GNU mode attributes for linux integer typedef layout" {
  let linux = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => fail("linux-amd64 target should parse")
  }
  let source =
    #|typedef int register_t __attribute__((__mode__(__word__)));
    #|typedef unsigned int fpu_control_t __attribute__((mode(__HI__)));
    #|typedef int spec_small_t __attribute__((mode(HI)));
    #|typedef int byte_int_t __attribute__((mode(byte)));
    #|typedef unsigned int pointer_uint_t __attribute__((mode(pointer)));
    #|int main(void) {
    #|  int reg_size[sizeof(register_t)];
    #|  int fpu_size[sizeof(fpu_control_t)];
    #|  int spec_size[sizeof(spec_small_t)];
    #|  int byte_size[sizeof(byte_int_t)];
    #|  int pointer_size[sizeof(pointer_uint_t)];
    #|  return 0;
    #|}
  let prog = @parser.parse_for_target(source, linux)
  match prog.decls[0].body {
    Some(
      Compound(
        [
          VarDecl(Array(SInt, 8), "reg_size", None),
          VarDecl(Array(SInt, 2), "fpu_size", None),
          VarDecl(Array(SInt, 2), "spec_size", None),
          VarDecl(Array(SInt, 1), "byte_size", None),
          VarDecl(Array(SInt, 8), "pointer_size", None),
          Return(Some(Number(0, _, SInt))),
        ]
      )
    ) => ()
    _ => fail("Expected GNU mode integer typedef layout constants")
  }
}

///|
test "parse long double external declaration as distinct type" {
  let source = "extern long double fabsl(long double);"
  let prog = @parser.parse(source)
  match prog.decls[0] {
    { ret: LongDouble, name: "fabsl", params: [{ ty: LongDouble, .. }], .. } =>
      ()
    _ => fail("Expected long double function declaration")
  }
}

///|
test "parse long double layout constants for selected target" {
  let linux = match @target.Target::parse("linux-amd64") {
    Some(target) => target
    None => fail("linux-amd64 target should parse")
  }
  let source = "int main(void) { int slots[sizeof(long double)]; return 0; }"
  let darwin_prog = @parser.parse(source)
  let linux_prog = @parser.parse_for_target(source, linux)
  match darwin_prog.decls[0].body {
    Some(
      Compound(
        [
          VarDecl(Array(SInt, 8), "slots", None),
          Return(Some(Number(0, _, SInt))),
        ]
      )
    ) => ()
    _ => fail("Expected Darwin long double size in array bound")
  }
  match linux_prog.decls[0].body {
    Some(
      Compound(
        [
          VarDecl(Array(SInt, 16), "slots", None),
          Return(Some(Number(0, _, SInt))),
        ]
      )
    ) => ()
    _ => fail("Expected Linux long double size in array bound")
  }
}

///|
test "parse block-scope builtin va list declaration" {
  let source = "int main() { __builtin_va_list ap; return 0; }"
  let prog = @parser.parse(source)
  match prog.decls[0].body {
    Some(
      Compound(
        [VarDecl(Pointer(SChar), "ap", None), Return(Some(Number(0, _, SInt)))]
      )
    ) => ()
    _ => fail("Expected __builtin_va_list declaration")
  }
}

///|
test "parse if statement" {
  let source = "int main() { if (1) return 2; else return 3; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [
          If(
            Number(1, _, SInt),
            Return(Some(Number(2, _, SInt))),
            Some(Return(Some(Number(3, _, SInt))))
          ),
        ]
      )
    ) => ()
    _ => fail("Expected if statement")
  }
}

///|
test "parse while statement" {
  let source = "int main() { while (1) return 0; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound([While(Number(1, _, SInt), Return(Some(Number(0, _, SInt))))])
    ) => ()
    _ => fail("Expected while statement")
  }
}

///|
test "parse binary expressions" {
  let source = "int main() { return 1 + 2 * 3 - 4 / 5; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([ret])) =>
      match ret {
        Return(Some(Binary("-", _, _))) => ()
        _ => fail("Expected binary expression")
      }
    _ => fail("Expected compound body")
  }
}

///|
test "parse comparison" {
  let source = "int main() { return 1 < 2; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [Return(Some(Binary("<", Number(1, _, SInt), Number(2, _, SInt))))]
      )
    ) => ()
    _ => fail("Expected comparison")
  }
}

///|
test "parse sizeof expr" {
  let source = "int main() { int x; return sizeof x; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound([VarDecl(SInt, "x", None), Return(Some(SizeofExpr(Var("x"))))])
    ) => ()
    _ => fail("Expected sizeof expr")
  }
}

///|
test "parse comma operator" {
  let source = "int main() { return 1, 2; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [Return(Some(Binary(",", Number(1, _, SInt), Number(2, _, SInt))))]
      )
    ) => ()
    _ => fail("Expected comma operator")
  }
}

///|
test "parse ternary" {
  let source = "int main() { int x = 1; int y = 2; return x > 0 ? y : 0; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [
          VarDecl(SInt, "x", Some(Number(1, _, SInt))),
          VarDecl(SInt, "y", Some(Number(2, _, SInt))),
          Return(
            Some(
              Ternary(
                Binary(">", Var("x"), Number(0, _, SInt)),
                Var("y"),
                Number(0, _, SInt)
              )
            )
          ),
        ]
      )
    ) => ()
    _ => fail("Expected ternary expression")
  }
}

///|
test "parse do while" {
  let source = "int main() { int i = 0; do { i = i + 1; } while (i < 5); return i; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [
          VarDecl(SInt, "i", Some(Number(0, _, SInt))),
          DoWhile(_, _),
          Return(Some(Var("i"))),
        ]
      )
    ) => ()
    _ => fail("Expected do-while")
  }
}

///|
test "parse continue" {
  let source = "int main() { int i = 0; while (i < 5) { i = i + 1; continue; } return i; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([_, While(_, Compound([_, Continue])), _])) => ()
    _ => fail("Expected continue")
  }
}

///|
test "parse bitwise operators" {
  let source = "int main() { return (3 & 1) | (2 ^ 1) | (4 << 1) | (8 >> 1) | ~0; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([Return(Some(Binary("|", _, _)))])) => ()
    _ => fail("Expected bitwise expression")
  }
}

///|
test "parse goto and label" {
  let source = "int main() { int x = 0; goto end; x = 1; end: return x; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [
          VarDecl(SInt, "x", Some(Number(0, _, SInt))),
          Goto("end"),
          ExprStmt(Assign(Var("x"), Number(1, _, SInt))),
          Label("end", Return(Some(Var("x")))),
        ]
      )
    ) => ()
    _ => fail("Expected goto and label")
  }
}

///|
test "parse switch" {
  let source =
    #|int main() {
    #|  int x = 2;
    #|  int r = 0;
    #|  switch (x) {
    #|    case 1: r = 10; break;
    #|    case 2: r = 20; break;
    #|    default: r = 30; break;
    #|  }
    #|  return r;
    #|}

  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound(stmts)) => {
      inspect(stmts.length(), content="4")
      match stmts[2] {
        Switch(
          Var("x"),
          Compound(
            [
              Case(1, ExprStmt(Assign(Var("r"), Number(10, _, SInt)))),
              Break,
              Case(2, ExprStmt(Assign(Var("r"), Number(20, _, SInt)))),
              Break,
              Default(ExprStmt(Assign(Var("r"), Number(30, _, SInt)))),
              Break,
            ]
          )
        ) => ()
        _ => fail("Expected switch statement")
      }
    }
    _ => fail("Expected compound body")
  }
}

///|
test "parse fallthrough attribute statement as no-op" {
  let source =
    #|int main() {
    #|  switch (0) {
    #|    case 0:
    #|      __attribute__((fallthrough));
    #|    case 1:
    #|      return 42;
    #|  }
    #|}
  let prog = @parser.parse(source)
  match prog.decls[0].body {
    Some(
      Compound(
        [
          Switch(
            _,
            Compound(
              [Case(0, ExprStmt(_)), Case(1, Return(Some(Number(42, _, SInt))))]
            )
          ),
        ]
      )
    ) => ()
    _ => fail("Expected fallthrough attribute statement to parse in switch")
  }
}

///|
test "parse cast" {
  let source = "int main() { return (char)256; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([Return(Some(Cast(SChar, Number(256, _, SInt))))])) => ()
    _ => fail("Expected cast expression")
  }
}

///|
test "parse prefix increment" {
  let source = "int main() { int x = 5; return ++x; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [
          VarDecl(SInt, "x", Some(Number(5, _, SInt))),
          Return(Some(PrefixInc(Var("x")))),
        ]
      )
    ) => ()
    _ => fail("Expected prefix increment")
  }
}

///|
test "parse postfix increment" {
  let source = "int main() { int x = 5; return x++; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [
          VarDecl(SInt, "x", Some(Number(5, _, SInt))),
          Return(Some(PostfixInc(Var("x")))),
        ]
      )
    ) => ()
    _ => fail("Expected postfix increment")
  }
}

///|
test "parse enum" {
  let source = "enum Color { Red, Green, Blue }; int main() { return Green; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([Return(Some(Number(1, _, SInt)))])) => ()
    _ => fail("Expected enum Green to be 1")
  }
}

///|
test "parse enum with values" {
  let source = "enum { A = 10, B, C = 20 }; int main() { return B + C; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [Return(Some(Binary("+", Number(11, _, SInt), Number(20, _, SInt))))]
      )
    ) => ()
    _ => fail("Expected B=11 and C=20")
  }
}

///|
test "parse enum trailing comma" {
  let source = "enum Top { TopA, TopB, }; typedef enum { LocalA = 4, LocalB, } Local; int main() { return TopB + LocalB; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [Return(Some(Binary("+", Number(1, _, SInt), Number(5, _, SInt))))]
      )
    ) => ()
    _ => fail("Expected trailing-comma enum constants")
  }
}

///|
test "parse for loop" {
  let source = "int main() { int s = 0; for (int i = 0; i < 3; i = i + 1) s = s + i; return s; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound(stmts)) => {
      inspect(stmts.length(), content="3")
      // Stmt 1: var decl s=0
      match stmts[0] {
        VarDecl(SInt, "s", Some(Number(0, _, _))) => ()
        _ => fail("Expected s declaration")
      }
      // Stmt 2: for loop as native For node
      match stmts[1] {
        For([VarDecl(SInt, "i", Some(Number(0, _, SInt)))], _, Some(_), _) => ()
        _ => fail("Expected For AST node")
      }
    }
    _ => fail("Expected compound body")
  }
}

///|
test "parse assignment" {
  let source = "int main() { int x; x = 5; return x; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [
          VarDecl(SInt, "x", None),
          ExprStmt(Assign(Var("x"), Number(5, _, SInt))),
          Return(Some(Var("x"))),
        ]
      )
    ) => ()
    _ => fail("Expected assignment")
  }
}

///|
test "parse compound assignment" {
  let source = "int main() { int x = 5; x += 3; x -= 1; x *= 2; x /= 2; x %= 3; return x; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound(stmts)) => {
      // Stmt 1: var decl
      // Stmt 2: x += 3
      match stmts[1] {
        ExprStmt(CompoundAssign("+", Var("x"), Number(3, _, _))) => ()
        _ => fail("Expected +=")
      }
      match stmts[3] {
        ExprStmt(CompoundAssign("*", Var("x"), Number(2, _, _))) => ()
        _ => fail("Expected *=")
      }
    }
    _ => fail("Expected compound body")
  }
}

///|
test "parse logical operators" {
  let source = "int main() { int a = 1; int b = 0; return a && b || !a; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [
          _,
          _,
          Return(
            Some(
              Binary(
                "||",
                Binary("&&", Var("a"), Var("b")),
                Unary("!", Var("a"))
              )
            )
          ),
        ]
      )
    ) => ()
    _ => fail("Expected logical operators")
  }
}

///|
test "parse empty for loop" {
  let source = "int main() { for (;;) return 42; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [For([], Number(1, _, SInt), None, Return(Some(Number(42, _, SInt))))]
      )
    ) => ()
    _ => fail("Expected empty for loop")
  }
}

///|
test "parse nested loops with break" {
  let source =
    #|int main() {
    #|  int x = 0;
    #|  for (int i = 0; i < 3; i = i + 1) {
    #|    for (int j = 0; j < 3; j = j + 1) {
    #|      if (j == 1) break;
    #|      x = x + 1;
    #|    }
    #|  }
    #|  return x;
    #|}

  let prog = @parser.parse(source)
  inspect(prog.decls.length(), content="1")
}

///|
test "parse sizeof type" {
  let source = "int main() { return sizeof(int); }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([Return(Some(Sizeof(SInt)))])) => ()
    _ => fail("Expected sizeof type")
  }
}

///|
test "parse alignof type and expression" {
  let source =
    #|struct S { char c; int x; };
    #|int main() {
    #|  long y;
    #|  int a[2];
    #|  return _Alignof(int) + alignof(struct S) + __alignof__(y) + __alignof__(a);
    #|}
  let prog = @parser.parse(source)
  match prog.decls[0].body {
    Some(
      Compound(
        [
          VarDecl(SLong, "y", None),
          VarDecl(Array(SInt, 2), "a", None),
          Return(
            Some(
              Binary(
                "+",
                Binary(
                  "+",
                  Binary("+", Alignof(SInt), Alignof(Struct("S"))),
                  AlignofExpr(Var("y"))
                ),
                AlignofExpr(Var("a"))
              )
            )
          ),
        ]
      )
    ) => ()
    _ => fail("Expected alignof operators to parse")
  }
}

///|
test "parse GNU alignof unparenthesized expression" {
  let source =
    #|int main() {
    #|  long y;
    #|  return __alignof__ y;
    #|}
  let prog = @parser.parse(source)
  match prog.decls[0].body {
    Some(
      Compound([VarDecl(SLong, "y", None), Return(Some(AlignofExpr(Var("y"))))])
    ) => ()
    _ => fail("Expected GNU alignof expression")
  }
}

///|
test "parse builtin offsetof member designators" {
  let source =
    #|struct Inner { int x; };
    #|struct Outer { char tag; struct Inner items[3]; };
    #|int main() {
    #|  return __builtin_offsetof(struct Outer, items[2].x);
    #|}
  let prog = @parser.parse(source)
  match prog.decls[0].body {
    Some(
      Compound(
        [
          Return(
            Some(
              OffsetOf(
                Struct("Outer"),
                [OffsetField("items"), OffsetIndex(2L), OffsetField("x")]
              )
            )
          ),
        ]
      )
    ) => ()
    _ => fail("Expected offsetof member-designator path")
  }
}

///|
test "parse struct definition and member access" {
  let source =
    #|struct Point { int x; int y; };
    #|int main() {
    #|  struct Point p;
    #|  p.x = 10;
    #|  p.y = 20;
    #|  return p.x + p.y;
    #|}

  let prog = @parser.parse(source)
  inspect(prog.decls.length(), content="1")
  inspect(prog.structs.length(), content="1")
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound(stmts)) => {
      inspect(stmts.length(), content="4")
      match stmts[1] {
        ExprStmt(Assign(MemberAccess(Var("p"), "x"), Number(10, _, _))) => ()
        _ => fail("Expected member access assignment")
      }
    }
    _ => fail("Expected compound body")
  }
}

///|
test "top-level GNU extension typedef is recorded" {
  let source =
    #|__extension__ typedef unsigned char uint8_t;
    #|__extension__ typedef unsigned long uintptr_t;
    #|struct HeaderPair { uint8_t tag; uintptr_t value; };
    #|int main(void) { return 0; }
  let prog = @parser.parse(source)
  match prog.structs[0].fields {
    [{ ty: UChar, name: "tag", .. }, { ty: ULong, name: "value", .. }] => ()
    _ => fail("Expected typedef names from top-level __extension__ typedefs")
  }
}

///|
test "parse packed aggregate attributes" {
  let source =
    #|struct __attribute__((packed)) PackedA { char c; int x; };
    #|struct PackedB { char c; int x; } __attribute__((__packed__));
    #|int main(void) { return 0; }
  let prog = @parser.parse(source)
  inspect(prog.structs.length(), content="2")
  debug_inspect(prog.structs[0].pack, content="Some(1)")
  debug_inspect(prog.structs[1].pack, content="Some(1)")
}

///|
test "parse GNU aligned attributes" {
  let source =
    #|int __attribute__((aligned(32))) global_spec;
    #|int global_post __attribute__((__aligned__(64)));
    #|int global_default __attribute__((aligned));
    #|int global_empty __attribute__((__aligned__()));
    #|struct AlignedAttr {
    #|  char c;
    #|  int x __attribute__((aligned(16)));
    #|  int z __attribute__((aligned));
    #|  char y;
    #|};
    #|typedef int aligned_int __attribute__((aligned(16)));
    #|typedef int default_aligned_int __attribute__((aligned));
    #|aligned_int typed_global;
    #|default_aligned_int default_typed_global;
    #|int main(void) {
    #|  int local __attribute__((aligned(32)));
    #|  int default_local __attribute__((aligned));
    #|  return 0;
    #|}
  let prog = @parser.parse(source)
  match prog.globals {
    [
      { ty: Aligned(SInt, 32), name: "global_spec", .. },
      { ty: Aligned(SInt, 64), name: "global_post", .. },
      { ty: Aligned(SInt, 16), name: "global_default", .. },
      { ty: Aligned(SInt, 16), name: "global_empty", .. },
      { ty: Aligned(SInt, 16), name: "typed_global", .. },
      { ty: Aligned(SInt, 16), name: "default_typed_global", .. },
    ] => ()
    _ => fail("Expected GNU aligned globals and typedef")
  }
  match prog.structs[0].fields {
    [
      { ty: SChar, name: "c", .. },
      { ty: Aligned(SInt, 16), name: "x", .. },
      { ty: Aligned(SInt, 16), name: "z", .. },
      { ty: SChar, name: "y", .. },
    ] => ()
    _ => fail("Expected GNU aligned struct field")
  }
  match prog.decls[0].body {
    Some(
      Compound(
        [
          VarDecl(Aligned(SInt, 32), "local", None),
          VarDecl(Aligned(SInt, 16), "default_local", None),
          Return(Some(Number(0, _, SInt))),
        ]
      )
    ) => ()
    _ => fail("Expected GNU aligned local variable")
  }
}

///|
test "parse aligned local array initializer assignments" {
  let source =
    #|int main(void) {
    #|  _Alignas(8) unsigned long long acc[4] = {10ull, 20ull};
    #|  return 0;
    #|}
  let prog = @parser.parse(source)
  // The alignment wrapper stays outside the element count the braces imply.
  match prog.decls[0].body {
    Some(
      Compound(
        [
          VarDecl(
            Aligned(Array(ULongLong, 4), 8),
            "acc",
            Some(Array([Number(10, _, _), Number(20, _, _)]))
          ),
          Return(Some(Number(0, _, SInt))),
        ]
      )
    ) => ()
    _ => fail("Expected aligned local array initializer recorded as written")
  }
}

///|
test "parse GNU weak attributes" {
  let source =
    #|__attribute__((weak)) int weak_fn(void) { return 1; }
    #|int weak_global __attribute__((__weak__)) = 2;
    #|int strong_fn(void) { return weak_fn() + weak_global; }
  let prog = @parser.parse(source)
  match prog.decls {
    [
      { name: "weak_fn", is_weak: true, .. },
      { name: "strong_fn", is_weak: false, .. },
    ] => ()
    _ => fail("Expected weak function attribute to be recorded")
  }
  match prog.globals {
    [{ name: "weak_global", is_weak: true, .. }] => ()
    _ => fail("Expected weak global attribute to be recorded")
  }
}

///|
test "parse GNU visibility attributes" {
  let source =
    #|__attribute__((visibility("hidden"))) int hidden_fn(void) { return 1; }
    #|int protected_global __attribute__((visibility("protected"))) = 2;
    #|extern int internal_global __attribute__((__visibility__("internal")));
    #|int main(void) { return hidden_fn() + protected_global; }
  let prog = @parser.parse(source)
  match prog.decls {
    [
      { name: "hidden_fn", visibility: Some("hidden"), .. },
      { name: "main", visibility: None, .. },
    ] => ()
    _ => fail("Expected function visibility attribute to be recorded")
  }
  match prog.globals {
    [
      { name: "protected_global", visibility: Some("protected"), .. },
      { name: "internal_global", visibility: Some("internal"), .. },
    ] => ()
    _ => fail("Expected global visibility attributes to be recorded")
  }
}

///|
test "parse GNU alias attributes" {
  let source =
    #|int alias_target(void) { return 1; }
    #|extern int alias_fn(void) __attribute__((alias("alias_target")));
    #|int alias_value_target = 2;
    #|extern int alias_value __attribute__((__alias__("alias_value_target")));
  let prog = @parser.parse(source)
  match prog.decls {
    [
      { name: "alias_target", symbol_alias: None, .. },
      { name: "alias_fn", symbol_alias: Some("alias_target"), .. },
    ] => ()
    _ => fail("Expected function alias attribute to be recorded")
  }
  match prog.globals {
    [
      { name: "alias_value_target", symbol_alias: None, .. },
      { name: "alias_value", symbol_alias: Some("alias_value_target"), .. },
    ] => ()
    _ => fail("Expected global alias attribute to be recorded")
  }
}

///|
test "parse GNU section attributes" {
  let source =
    #|__attribute__((section(".text.kimicc"))) int section_fn(void) { return 1; }
    #|int section_global __attribute__((__section__(".data.kimicc"))) = 2;
  let prog = @parser.parse(source)
  match prog.decls {
    [{ name: "section_fn", section: Some(".text.kimicc"), .. }] => ()
    _ => fail("Expected function section attribute to be recorded")
  }
  match prog.globals {
    [{ name: "section_global", section: Some(".data.kimicc"), .. }] => ()
    _ => fail("Expected global section attribute to be recorded")
  }
}

///|
test "parse GNU constructor and destructor attributes" {
  let source =
    #|__attribute__((constructor)) void init_fn(void) {}
    #|__attribute__((destructor)) void fini_fn(void) {}
  let prog = @parser.parse(source)
  match prog.decls {
    [
      { name: "init_fn", is_constructor: true, is_destructor: false, .. },
      { name: "fini_fn", is_constructor: false, is_destructor: true, .. },
    ] => ()
    _ => fail("Expected constructor and destructor attributes to be recorded")
  }
}

///|
test "parse pointer to struct member access" {
  let source =
    #|struct Node { int val; struct Node *next; };
    #|int main() {
    #|  struct Node n;
    #|  n.val = 5;
    #|  n.next = &n;
    #|  return n.next->val;
    #|}

  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound(stmts)) =>
      match stmts[3] {
        Return(Some(MemberAccess(Deref(MemberAccess(Var("n"), "next")), "val"))) =>
          ()
        _ => fail("Expected arrow member access")
      }
    _ => fail("Expected compound body")
  }
}

///|
test "parse array declaration and access" {
  let source = "int main() { int a[5]; a[2] = 42; return a[2]; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [
          VarDecl(Array(SInt, 5), "a", None),
          ExprStmt(
            Assign(
              ArrayAccess(Var("a"), Number(2, _, SInt)),
              Number(42, _, SInt)
            )
          ),
          Return(Some(ArrayAccess(Var("a"), Number(2, _, SInt)))),
        ]
      )
    ) => ()
    _ => fail("Expected array decl and access")
  }
}

///|
test "parse array bound using sizeof global array" {
  let source =
    #|typedef unsigned char u8;
    #|static const u8 magic[8] = {1,2,3,4,5,6,7,8};
    #|int main() {
    #|  u8 zHeader[sizeof(magic)+4];
    #|  return sizeof(zHeader);
    #|}
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [
          VarDecl(Array(UChar, 12), "zHeader", None),
          Return(Some(SizeofExpr(Var("zHeader")))),
        ]
      )
    ) => ()
    _ => fail("Expected sizeof(global array) to fold to an array bound of 12")
  }
}

///|
test "parse global variable" {
  let source = "int g = 10; int main() { return g; }"
  let prog = @parser.parse(source)
  inspect(prog.globals.length(), content="1")
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([Return(Some(Var("g")))])) => ()
    _ => fail("Expected global access")
  }
}

///|
test "parse comma separated initialized globals" {
  let source = "int action_fd = -1, entry_fd = -1, text_fd = -1; int main(void) { return entry_fd; }"
  let prog = @parser.parse(source)
  inspect(prog.globals.length(), content="3")
  match prog.globals {
    [
      {
        name: "action_fd",
        init: Some(Scalar(Unary("-", Number(1, _, SInt)))),
        ..,
      },
      {
        name: "entry_fd",
        init: Some(Scalar(Unary("-", Number(1, _, SInt)))),
        ..,
      },
      {
        name: "text_fd",
        init: Some(Scalar(Unary("-", Number(1, _, SInt)))),
        ..,
      },
    ] => ()
    _ => fail("Expected three initialized globals")
  }
}

///|
test "parse multiple functions" {
  let source =
    #|int add(int a, int b) { return a + b; }
    #|int mul(int a, int b) { return a * b; }
    #|int main() { return add(2, 3) + mul(4, 5); }

  let prog = @parser.parse(source)
  inspect(prog.decls.length(), content="3")
  inspect(prog.decls[0].name, content="add")
  inspect(prog.decls[1].name, content="mul")
  inspect(prog.decls[2].name, content="main")
}

///|
test "parse string literal" {
  let source = "int main() { char *s = \"hello\"; return 0; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [
          VarDecl(Pointer(SChar), "s", Some(String("hello"))),
          Return(Some(Number(0, _, SInt))),
        ]
      )
    ) => ()
    _ => fail("Expected string literal")
  }
}

///|
test "parse adjacent string concatenation" {
  let source = "int main() { char *s = \"he\" \"llo\"; return 0; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [
          VarDecl(Pointer(SChar), "s", Some(String("hello"))),
          Return(Some(Number(0, _, SInt))),
        ]
      )
    ) => ()
    _ => fail("Expected concatenated string literal")
  }
}

///|
test "parse comments" {
  let source =
    #|// Line comment
    #|int main() {
    #|  /* block
    #|     comment */
    #|  return 42;
    #|}

  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([Return(Some(Number(42, _, SInt)))])) => ()
    _ => fail("Expected return 42 after comments")
  }
}

///|
test "parse array initializer infers size" {
  let source = "int main() { int arr[] = {1, 2, 3}; return 0; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  // One declarator is one statement: there is no grouping left to hold
  // element assignments that the parser no longer emits.
  match decl.body {
    Some(
      Compound(
        [
          VarDecl(
            Array(SInt, 3),
            "arr",
            Some(Array([Number(1, _, _), Number(2, _, _), Number(3, _, _)]))
          ),
          Return(Some(_)),
        ]
      )
    ) => ()
    _ => fail("Expected array initializer recorded as written")
  }
}

///|
test "parse array initializer with expression element" {
  let source = "int main() { int arr[] = {1 + 1}; return 0; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [
          VarDecl(
            Array(SInt, 1),
            "arr",
            Some(Array([Binary("+", Number(1, _, SInt), Number(1, _, _))]))
          ),
          ..,
        ]
      )
    ) => ()
    _ => fail("Expected unfolded element expression in the initializer")
  }
}

///|
test "parse scalar brace initializer values" {
  let source =
    #|int g = {42};
    #|int main() {
    #|  int x = {19}, y = {{23}}, a[2] = {{5}, {37}};
    #|  return g + x + y + a[0] + a[1];
    #|}
  let prog = @parser.parse(source)
  match prog.globals[0].init {
    Some(Scalar(Number(42, _, _))) => ()
    _ => fail("Expected scalar global brace initializer")
  }
  // Three declarators, three statements: the declaration that grouped them
  // carries nothing a consumer could act on once each name has its own type.
  match prog.decls[0].body {
    Some(Compound(inner)) => {
      match inner[0] {
        VarDecl(SInt, "x", Some(Number(19, _, _))) => ()
        _ => fail("Expected scalar local brace initializer")
      }
      match inner[1] {
        VarDecl(SInt, "y", Some(Number(23, _, _))) => ()
        _ => fail("Expected nested scalar local brace initializer")
      }
      // Braces around each element survive into the AST; reading through them
      // to the scalar they denote is `scalar_initializer_value`'s job, not the
      // parser's.
      match inner[2] {
        VarDecl(
          Array(SInt, 2),
          "a",
          Some(Array([Array([Number(5, _, _)]), Array([Number(37, _, _)])]))
        ) => ()
        _ => fail("Expected array initializer recorded as written")
      }
      assert_eq(inner.length(), 4)
    }
    _ => fail("Expected scalar brace initializer body")
  }
}

///|
test "scalar_initializer_value reads through braces and designators" {
  let five = @parser.int_literal(5, SInt)
  assert_true(
    @parser.scalar_initializer_value(Array([Array([five])])) is Number(5, _, _),
  )
  assert_true(
    @parser.scalar_initializer_value(DesignatedField("f", Array([five])))
    is Number(5, _, _),
  )
  // Empty braces denote zero.
  assert_true(@parser.scalar_initializer_value(Array([])) is Number(0, _, _))
  // A compound literal is an expression in its own right, so it is left alone.
  assert_true(
    @parser.scalar_initializer_value(CompoundLiteral(SInt, [five], 0))
    is CompoundLiteral(_, _, _),
  )
}

///|
test "parse multiple vars one with array initializer" {
  let source = "int main() { int a = 1, b[] = {2}, c = 3; return 0; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  // One declaration, three declarators, three sibling statements.
  match decl.body {
    Some(
      Compound(
        [
          VarDecl(SInt, "a", Some(Number(1, _, _))),
          VarDecl(Array(SInt, 1), "b", Some(Array([Number(2, _, _)]))),
          VarDecl(SInt, "c", Some(Number(3, _, _))),
          ..,
        ]
      )
    ) => ()
    _ => fail("Expected three sibling declarations")
  }
}

///|
test "parse array initializer inferred size" {
  let source = "int main(){int arr[]={1,2,3}; return 0;}"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([VarDecl(Array(SInt, 3), "arr", Some(Array(items))), ..])) =>
      assert_eq(items.length(), 3)
    _ => fail("Expected VarDecl with Array(SInt, 3)")
  }
}

///|
test "parse array initializer explicit size" {
  let source = "int main(){int arr[5]={1,2}; return 0;}"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  // An explicit size wins over the two elements the braces supply.
  match decl.body {
    Some(Compound([VarDecl(Array(SInt, 5), "arr", Some(Array(items))), ..])) =>
      assert_eq(items.length(), 2)
    _ => fail("Expected VarDecl with Array(SInt, 5)")
  }
}

///|
test "parse global array initializer inferred size" {
  let source = "int arr[] = {1, 2, 3};\nint main() { return 0; }"
  let prog = @parser.parse(source)
  inspect(prog.globals.length(), content="1")
  let g = prog.globals[0]
  inspect(g.ty, content="Array(SInt, 3)")
  inspect(g.name, content="arr")
  match g.init {
    Some(Array(exprs)) => inspect(exprs.length(), content="3")
    _ => fail("Expected array initializer")
  }
}

///|
test "parse mixed nested initializer designators" {
  let source =
    #|struct Pair { int a; int b; };
    #|struct Wrap { struct Pair pairs[2]; };
    #|struct Wrap w = { .pairs[1].b = 5, .pairs[0].a = 37 };
    #|int main() { return 0; }
  let prog = @parser.parse(source)
  inspect(prog.globals.length(), content="1")
  match prog.globals[0].init {
    Some(
      Array(
        [
          DesignatedField(
            "pairs",
            DesignatedIndex(1, DesignatedField("b", Number(5, _, SInt)))
          ),
          DesignatedField(
            "pairs",
            DesignatedIndex(0, DesignatedField("a", Number(37, _, SInt)))
          ),
        ]
      )
    ) => ()
    _ => fail("Expected mixed field/index designator path")
  }
}

///|
test "parse multidimensional array declarator keeps outer dimension first" {
  let source = "unsigned short table[2][4];\nint main() { return 0; }"
  let prog = @parser.parse(source)
  inspect(prog.globals.length(), content="1")
  inspect(prog.globals[0].ty, content="Array(Array(UShort, 4), 2)")
}

///|
test "parse parenthesized function declarator as function" {
  let source = "extern int (putchar)(int);\nint main() { return putchar(65); }"
  let prog = @parser.parse(source)
  inspect(prog.globals.length(), content="0")
  inspect(prog.decls.length(), content="2")
  inspect(prog.decls[0].name, content="putchar")
  inspect(prog.decls[0].ret, content="SInt")
  inspect(prog.decls[0].params.length(), content="1")
  match prog.decls[0].body {
    None => ()
    Some(_) => fail("Expected parenthesized extern function declaration")
  }
}

///|
test "parse computed goto label address" {
  let source = "int main() { void *p = &&label; label: return 0; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound(stmts)) =>
      match stmts[0] {
        VarDecl(Pointer(Void), "p", Some(LabelAddr("label"))) => ()
        _ => fail("Expected VarDecl with LabelAddr")
      }
    _ => fail("Expected compound body")
  }
}

///|
test "parse __func__ builtin" {
  let source = "int main() { return __func__[0]; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound([Return(Some(ArrayAccess(String("main"), Number(0, _, SInt))))])
    ) => ()
    _ => fail("Expected __func__ as string literal")
  }
}

///|
test "parse static assertions at declaration scopes" {
  let source =
    #|_Static_assert(sizeof(int) == 4, "int size");
    #|struct Box {
    #|  static_assert(sizeof(long) == 8, "long size");
    #|  int value;
    #|};
    #|int main(void) {
    #|  __Static_assert(sizeof(char) == 1, "char size");
    #|  return 42;
    #|}
  let prog = @parser.parse(source)
  inspect(prog.structs.length(), content="1")
  inspect(prog.structs[0].fields.length(), content="1")
  inspect(prog.decls.length(), content="1")
  // A declaration that declares nothing leaves nothing behind. It used to
  // leave `ExprStmt(0)`, a statement the source never wrote and a consumer
  // would have to know to ignore.
  match prog.decls[0].body {
    Some(Compound([Return(Some(Number(42, _, SInt)))])) => ()
    _ => fail("Expected the static assertion to leave no statement")
  }
}

///|
test "parse static assertions compare unsigned constant values" {
  let source =
    #|_Static_assert(18446744073709551615UL > 9223372036854775807L, "uint64 max");
    #|_Static_assert((unsigned long)-1 > 0, "unsigned long max");
    #|_Static_assert((unsigned int)-1 == 4294967295U, "unsigned int max");
    #|_Static_assert((int)4294967295U == -1, "signed cast");
    #|_Static_assert((unsigned int)-1 == -1, "usual equality conversion");
    #|_Static_assert((unsigned int)-1 + 1U == 0, "unsigned wrap");
    #|_Static_assert((unsigned int)-1 >> 31 == 1, "unsigned shift");
    #|_Static_assert((long)-1 < (unsigned int)1, "lp64 signed compare");
    #|_Static_assert(+1 == 1, "unary plus");
    #|int table[+2];
    #|int main(void) {
    #|  return 0;
    #|}
  let prog = @parser.parse(source)
  inspect(prog.globals.length(), content="1")
  inspect(prog.decls.length(), content="1")
}

///|
test "parse builtin 128-bit declarations in block scope" {
  let source =
    #|int main(void) {
    #|  __uint128_t const wide = ((__uint128_t)1) << 65;
    #|  for (__int128_t signed_wide = 0; signed_wide < 1; signed_wide = signed_wide + 1) {
    #|  }
    #|  return (int)(wide >> 65);
    #|}
  let prog = @parser.parse(source)
  match prog.decls[0].body {
    Some(
      Compound(
        [
          VarDecl(UInt128, "wide", Some(_)),
          For([_, ..], _, _, _),
          Return(Some(_)),
        ]
      )
    ) => ()
    _ => fail("Expected builtin 128-bit declarations in block scope")
  }
}

///|
test "parse bare _Atomic typedef qualifier" {
  let source =
    #|typedef unsigned long uintnat;
    #|typedef _Atomic uintnat atomic_uintnat;
    #|typedef _Atomic(uintnat) atomic_uintnat_paren;
    #|atomic_uintnat counter;
    #|atomic_uintnat_paren other;
    #|int main(void) { return 0; }
  let prog = @parser.parse(source)
  match prog.globals {
    [
      { ty: Atomic(ULong), name: "counter", .. },
      { ty: Atomic(ULong), name: "other", .. },
    ] => ()
    _ => fail("Expected atomic typedef globals")
  }
}

///|
test "parse struct compound literal assignment" {
  let source =
    #|typedef union ValueUnion { int int32; void *ptr; } ValueUnion;
    #|typedef struct Value { ValueUnion u; long tag; } Value;
    #|int main(void) {
    #|  Value v;
    #|  v = (Value){ (ValueUnion){ .int32 = 7 }, 4 };
    #|  return 0;
    #|}
  let prog = @parser.parse(source)
  match prog.decls[0].body {
    Some(Compound([VarDecl(_, "v", None), ExprStmt(Assign(_, rhs)), _])) =>
      match rhs {
        CompoundLiteral(
          Struct(_),
          [CompoundLiteral(Union(_), _, _), Number(4, _, SInt)],
          _
        ) => ()
        _ => fail("Expected compound literal assignment rhs")
      }
    _ => fail("Expected compound literal assignment")
  }
}

///|
test "parse mixed compound literal initializer designators" {
  let source =
    #|typedef struct Pair { int a; int b; } Pair;
    #|typedef struct Wrap { Pair pairs[2]; } Wrap;
    #|int main(void) {
    #|  Wrap w = (Wrap){ .pairs[1].b = 5, .pairs[0].a = 37 };
    #|  return 0;
    #|}
  let prog = @parser.parse(source)
  match prog.decls[0].body {
    Some(
      Compound(
        [
          VarDecl(
            _,
            "w",
            Some(
              CompoundLiteral(
                Struct(_),
                [
                  DesignatedField(
                    "pairs",
                    DesignatedIndex(1, DesignatedField("b", Number(5, _, SInt)))
                  ),
                  DesignatedField(
                    "pairs",
                    DesignatedIndex(
                      0,
                      DesignatedField("a", Number(37, _, SInt))
                    )
                  ),
                ],
                _
              )
            )
          ),
          _,
        ]
      )
    ) => ()
    _ => fail("Expected mixed compound literal designator path")
  }
}

///|
test "check ast for array init locals" {
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
  match prog.decls[0].body {
    Some(Compound(stmts)) => {
      inspect(stmts.length(), content="7")
      assert_true(stmts[0] is VarDecl(_, "buf", _))
      assert_true(stmts[1] is VarDecl(_, "p", _))
      // `char src[] = "abcd"` keeps the string it was written with, sized to
      // include the terminator, rather than five element assignments.
      assert_true(
        stmts[2] is VarDecl(Array(SChar, 5), "src", Some(String("abcd"))),
      )
      assert_true(stmts[3] is VarDecl(_, "dst", _))
      assert_true(stmts[4] is VarDecl(_, "buf2", _))
      assert_true(stmts[5] is VarDecl(_, "buf3", _))
      assert_true(stmts[6] is Return(_))
    }
    _ => fail("Not compound")
  }
}

///|
test "parse variadic function declaration" {
  let source = "int printf(const char *fmt, ...);"
  let prog = @parser.parse(source)
  inspect(prog.decls.length(), content="1")
  let decl = prog.decls[0]
  inspect(decl.name, content="printf")
  inspect(decl.variadic, content="true")
  inspect(decl.params.length(), content="1")
  inspect(decl.params[0].name, content="fmt")
}

///|
test "parse non-variadic function declaration" {
  let source = "int puts(const char *s);"
  let prog = @parser.parse(source)
  inspect(prog.decls.length(), content="1")
  let decl = prog.decls[0]
  inspect(decl.variadic, content="false")
  inspect(decl.params.length(), content="1")
}

///|
test "parse function parameter array with GNU restrict size" {
  let source = "int regexec(unsigned long n, int pmatch[__restrict n]);"
  let prog = @parser.parse(source)
  inspect(prog.decls.length(), content="1")
  let decl = prog.decls[0]
  inspect(decl.name, content="regexec")
  inspect(decl.params.length(), content="2")
  inspect(decl.params[1].ty, content="Pointer(SInt)")
}

///|
test "parse generic selection chooses matching association" {
  let source =
    #|int main(void) {
    #|  return _Generic(1.0, int: 1, double: 2, default: 3);
    #|}
  let prog = @parser.parse(source)
  match prog.decls[0].body {
    Some(Compound([Return(Some(Number(2, _, SInt)))])) => ()
    _ => fail("Expected generic selection to fold to selected expression")
  }
}

///|
test "parse builtin choose expr and types compatible fold constants" {
  let source =
    #|int main(void) {
    #|  return __builtin_choose_expr(__builtin_types_compatible_p(int, signed int), 7, missing()) +
    #|         __builtin_choose_expr(__builtin_types_compatible_p(int, unsigned int), missing(), 5);
    #|}
  let prog = @parser.parse(source)
  match prog.decls[0].body {
    Some(
      Compound(
        [Return(Some(Binary("+", Number(7, _, SInt), Number(5, _, SInt))))]
      )
    ) => ()
    _ => fail("Expected builtin compile-time selection to fold constants")
  }
}

///|
test "parse object size builtin constants in static asserts" {
  let source =
    #|struct S { int x; char buf[9]; };
    #|struct S global_s;
    #|int global_x;
    #|char global_buf[16];
    #|_Static_assert(__builtin_object_size("abc", 0) == 4, "literal object size");
    #|_Static_assert(__builtin_dynamic_object_size((const char *)"a\0bc", 2) == 5, "embedded nul object size");
    #|_Static_assert(__builtin_object_size((void *)0, 0) == (unsigned long)-1, "unknown max object size");
    #|_Static_assert(__builtin_dynamic_object_size((void *)0, 2) == 0, "unknown min object size");
    #|_Static_assert(__builtin_object_size(&global_x, 0) == sizeof(global_x), "global object size");
    #|_Static_assert(__builtin_dynamic_object_size((void *)global_buf, 2) == sizeof(global_buf), "global array size");
    #|_Static_assert(__builtin_object_size(&global_buf[3], 0) == sizeof(global_buf) - 3, "global array element remaining size");
    #|_Static_assert(__builtin_object_size(&global_buf[3], 1) == sizeof(global_buf) - 3, "global array element subobject size");
    #|_Static_assert(__builtin_object_size(global_buf + 3, 0) == sizeof(global_buf) - 3, "global array pointer remaining size");
    #|_Static_assert(__builtin_object_size(3 + global_buf, 1) == sizeof(global_buf) - 3, "global commuted pointer remaining size");
    #|_Static_assert(__builtin_object_size(&global_s.buf, 0) == sizeof(global_s) - __builtin_offsetof(struct S, buf), "global member whole object size");
    #|_Static_assert(__builtin_object_size(&global_s.buf, 1) == sizeof(global_s.buf), "global member subobject size");
    #|_Static_assert(__builtin_dynamic_object_size(global_s.buf, 2) == sizeof(global_s) - __builtin_offsetof(struct S, buf), "global member array whole size");
    #|_Static_assert(__builtin_dynamic_object_size(global_s.buf, 3) == sizeof(global_s.buf), "global member array subobject size");
    #|_Static_assert(__builtin_dynamic_object_size(&global_s.buf[4], 2) == sizeof(global_s) - __builtin_offsetof(struct S, buf) - 4, "global member element whole remaining size");
    #|_Static_assert(__builtin_dynamic_object_size(&global_s.buf[4], 3) == sizeof(global_s.buf) - 4, "global member element subobject remaining size");
    #|_Static_assert(__builtin_constant_p(1 + 2) == 1, "constant expression");
    #|_Static_assert(__builtin_constant_p(global_x) == 0, "runtime object is not constant");
    #|_Static_assert(__builtin_abs(-7) == 7, "abs constant");
    #|_Static_assert(__builtin_align_up(33, 16) == 48, "align up constant");
    #|_Static_assert(__builtin_popcount(0xf0f0u) == 8, "popcount constant");
    #|_Static_assert(__builtin_bswap32(0x01020304u) == 0x04030201u, "bswap constant");
    #|_Static_assert(__builtin_rotateleft32(0x12345678u, 8) == 0x34567812u, "rotate constant");
    #|int main(void) {
    #|  int local_x;
    #|  char local_buf[16];
    #|  struct S local_s;
    #|  _Static_assert(__builtin_object_size(&local_x, 0) == sizeof(local_x), "local object size");
    #|  _Static_assert(__builtin_dynamic_object_size((void *)local_buf, 2) == sizeof(local_buf), "local array size");
    #|  _Static_assert(__builtin_object_size(&local_buf[3], 0) == sizeof(local_buf) - 3, "local array element remaining size");
    #|  _Static_assert(__builtin_object_size(local_buf + 3, 1) == sizeof(local_buf) - 3, "local array pointer remaining size");
    #|  _Static_assert(__builtin_object_size(&local_s.buf, 0) == sizeof(local_s) - __builtin_offsetof(struct S, buf), "local member whole object size");
    #|  _Static_assert(__builtin_dynamic_object_size(local_s.buf, 2) == sizeof(local_s) - __builtin_offsetof(struct S, buf), "local member array whole size");
    #|  _Static_assert(__builtin_dynamic_object_size(local_s.buf, 3) == sizeof(local_s.buf), "local member array subobject size");
    #|  _Static_assert(__builtin_object_size(&local_s.buf[4], 1) == sizeof(local_s.buf) - 4, "local member element subobject size");
    #|  return 0;
    #|}
  ignore(@parser.parse(source))
}

///|
test "parse GNU typeof type specifiers" {
  let source =
    #|int main(void) {
    #|  int x = 0;
    #|  __typeof__(x) y = 7;
    #|  typeof(unsigned long) z = 5;
    #|  return y + (int)z;
    #|}
  let prog = @parser.parse(source)
  match prog.decls[0].body {
    Some(
      Compound(
        [
          VarDecl(SInt, "x", Some(Number(0, _, SInt))),
          VarDecl(SInt, "y", Some(Number(7, _, SInt))),
          VarDecl(ULong, "z", Some(Number(5, _, SInt))),
          Return(Some(Binary("+", Var("y"), Cast(SInt, Var("z"))))),
        ]
      )
    ) => ()
    _ =>
      fail("Expected typeof specifiers to resolve expression and type operands")
  }
}

///|
test "parse GNU typeof comma expression uses rhs type" {
  let source =
    #|int main(void) {
    #|  unsigned long *p;
    #|  __typeof__((void)0, *p) y = 5;
    #|  return (int)y;
    #|}
  let prog = @parser.parse(source)
  match prog.decls[0].body {
    Some(
      Compound(
        [
          VarDecl(Pointer(ULong), "p", None),
          VarDecl(ULong, "y", Some(Number(5, _, SInt))),
          Return(Some(Cast(SInt, Var("y")))),
        ]
      )
    ) => ()
    _ => fail("Expected typeof comma expression to use right operand type")
  }
}

///|
test "parse GNU auto type local declarations" {
  let source =
    #|int main(void) {
    #|  unsigned long x = 40;
    #|  __auto_type y = x;
    #|  int *p;
    #|  __auto_type q = p;
    #|  return (int)y;
    #|}
  let prog = @parser.parse(source)
  match prog.decls[0].body {
    Some(
      Compound(
        [
          VarDecl(ULong, "x", Some(Number(40, _, SInt))),
          VarDecl(ULong, "y", Some(Var("x"))),
          VarDecl(Pointer(SInt), "p", None),
          VarDecl(Pointer(SInt), "q", Some(Var("p"))),
          Return(Some(Cast(SInt, Var("y")))),
        ]
      )
    ) => ()
    _ => fail("Expected __auto_type locals to infer initializer type")
  }
}

///|
test "parse builtin classify type folds covered categories" {
  let source =
    #|struct S { int x; };
    #|union U { int x; double y; };
    #|int main(void) {
    #|  int x = 0;
    #|  double d = 0.0;
    #|  int a[2];
    #|  struct S s;
    #|  union U u;
    #|  return __builtin_classify_type(x++) +
    #|         __builtin_classify_type(d) +
    #|         __builtin_classify_type(a) +
    #|         __builtin_classify_type(s) +
    #|         __builtin_classify_type(u);
    #|}
  let prog = @parser.parse(source)
  match prog.decls[0].body {
    Some(
      Compound(
        [
          VarDecl(SInt, "x", Some(Number(0, _, SInt))),
          VarDecl(Double, "d", Some(FloatLiteral("0.0", Double))),
          VarDecl(Array(SInt, 2), "a", None),
          VarDecl(Struct("S"), "s", None),
          VarDecl(Union("U"), "u", None),
          Return(
            Some(
              Binary(
                "+",
                Binary(
                  "+",
                  Binary(
                    "+",
                    Binary("+", Number(1, _, SInt), Number(8, _, SInt)),
                    Number(5, _, SInt)
                  ),
                  Number(12, _, SInt)
                ),
                Number(13, _, SInt)
              )
            )
          ),
        ]
      )
    ) => ()
    _ => fail("Expected __builtin_classify_type to fold covered categories")
  }
}

///|
/// A `Named` type is a spelling the parser can only know by registration:
/// `parse_with_named_types` seeds the typedef table and the declaration
/// parses like any typedef'd type. (The print half of the round trip
/// lives in `qc_test`, which can see the printer.)
test "a registered named type parses as Named" {
  let source =
    #|static float sum4(float *x) {
    #|  float32x4_t acc = vdupq_n_f32(0.0f);
    #|  return vaddvq_f32(acc);
    #|}
    #|
  let program = @parser.parse_with_named_types(source, ["float32x4_t"])
  match program.decls[0].body {
    Some(Compound([VarDecl(Named("float32x4_t"), "acc", Some(_)), ..])) => ()
    other => fail("expected a Named-typed declaration, got \{Repr(other)}")
  }
}

///|
/// Without registration the spelling is just an undeclared identifier, and
/// the declaration fails to parse: a diagnostic, not a silent misread.
test "an unregistered named type is a parse error" {
  let source = "void f(void) { float32x4_t acc; }"
  try @parser.parse(source) |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("expected a parse error for the unregistered type name")
  }
}

///|
/// Synthesized integer literals carry the suffix their type demands, so
/// the reparse recovers the same type: a bare `5` reads back `SInt`, and
/// exact AST equality is the round-trip contract.
test "int_literal synthesizes the canonical suffix for its type" {
  match @parser.int_literal(5, UInt) {
    Number(5, "5u", UInt) => ()
    other => fail("unexpected UInt literal shape: \{Repr(other)}")
  }
  match @parser.int_literal(5, SLong) {
    Number(5, "5L", SLong) => ()
    other => fail("unexpected SLong literal shape: \{Repr(other)}")
  }
  match @parser.int_literal(5, ULongLong) {
    Number(5, "5uLL", ULongLong) => ()
    other => fail("unexpected ULongLong literal shape: \{Repr(other)}")
  }
  // The synthesized text lexes back to the same value and type.
  let program = @parser.parse("long k = 5L;")
  match program.globals[0].init {
    Some(Scalar(Number(5, "5L", SLong))) => ()
    other => fail("unexpected reparse of 5L: \{Repr(other)}")
  }
}

///|
/// The ABI walk finds named types anywhere a backend would need their
/// layout -- including codex's counterexample: a callback carrying a
/// named return hidden inside a struct field, reached only through a
/// pointer. Plain opaque-pointer uses stay legal.
test "named_abi_violation walks fields, locals, casts, and callbacks" {
  let names = ["float32x4_t"]
  // Legal: named types behind plain pointers only.
  let ok = @parser.parse_with_named_types(
    "void f(float32x4_t *p) { float32x4_t **q = &p; }", names,
  )
  assert_eq(@parser.named_abi_violation(ok), None)
  // A struct field whose function-pointer signature returns one by value.
  let field_source =
    #|struct S { float32x4_t (*cb)(void); };
    #|int f(struct S *s) { return 0; }
    #|
  let field = @parser.parse_with_named_types(field_source, names)
  match @parser.named_abi_violation(field) {
    Some(msg) => assert_true(msg.contains("S.cb"))
    None => fail("expected the struct-field callback to be a violation")
  }
  // A cast to a callback type with a named parameter.
  let cast = @parser.parse_with_named_types(
    "void f(void *x) { void (*g)(void) = (void (*)(float32x4_t))x; }", names,
  )
  match @parser.named_abi_violation(cast) {
    Some(_) => ()
    None => fail("expected the cast target to be a violation")
  }
  // A local declared by value.
  let local_decl = @parser.parse_with_named_types(
    "void f(void) { float32x4_t v; }", names,
  )
  match @parser.named_abi_violation(local_decl) {
    Some(msg) => assert_true(msg.contains("local `v`"))
    None => fail("expected the by-value local to be a violation")
  }
}

///|
/// A negative value never takes a suffix: the sign is not part of the
/// integer token, so `-1uLL` would parse as negation of unsigned `1uLL`
/// and flip comparisons. Enumerator substitution is where negatives
/// reach `int_literal`.
test "int_literal leaves negative values unsuffixed" {
  match @parser.int_literal(-1, ULongLong) {
    Number(value, "-1", ULongLong) => assert_eq(value, -1L)
    other => fail("unexpected negative literal shape: \{Repr(other)}")
  }
}
