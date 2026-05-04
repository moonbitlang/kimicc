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
test "parse variable declaration" {
  let source = "int main() { int x = 10; return x; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound(stmts)) => {
      inspect(stmts.length(), content="2")
      match stmts[0] {
        VarDecl(SInt, "x", Some(Number(10))) => ()
        _ => fail("Expected VarDecl")
      }
    }
    _ => fail("Expected compound body")
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
        [If(Number(1), Return(Some(Number(2))), Some(Return(Some(Number(3)))))]
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
    Some(Compound([While(Number(1), Return(Some(Number(0))))])) => ()
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
    Some(Compound([Return(Some(Binary("<", Number(1), Number(2))))])) => ()
    _ => fail("Expected comparison")
  }
}

///|
test "parse sizeof expr" {
  let source = "int main() { int x; return sizeof x; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([VarDecl(SInt, "x", None), Return(Some(SizeofExpr(Var("x"))))])) =>
      ()
    _ => fail("Expected sizeof expr")
  }
}

///|
test "parse comma operator" {
  let source = "int main() { return 1, 2; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([Return(Some(Binary(",", Number(1), Number(2))))])) => ()
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
          VarDecl(SInt, "x", Some(Number(1))),
          VarDecl(SInt, "y", Some(Number(2))),
          Return(Some(Ternary(Binary(">", Var("x"), Number(0)), Var("y"), Number(0)))),
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
    Some(Compound([VarDecl(SInt, "i", Some(Number(0))), DoWhile(_, _), Return(Some(Var("i")))])) =>
      ()
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
          VarDecl(SInt, "x", Some(Number(0))),
          Goto("end"),
          ExprStmt(Assign(Var("x"), Number(1))),
          Label("end", Return(Some(Var("x")))),
        ]
      )
    ) => ()
    _ => fail("Expected goto and label")
  }
}

///|
test "parse switch" {
  let source = #|int main() {
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
        Switch(_, cases) => {
          inspect(cases.length(), content="3")
          match cases[0] {
            (Some(1), Compound([ExprStmt(Assign(Var("r"), Number(10))), Break])) => ()
            _ => fail("Expected case 1")
          }
          match cases[1] {
            (Some(2), Compound([ExprStmt(Assign(Var("r"), Number(20))), Break])) => ()
            _ => fail("Expected case 2")
          }
          match cases[2] {
            (None, Compound([ExprStmt(Assign(Var("r"), Number(30))), Break])) => ()
            _ => fail("Expected default")
          }
        }
        _ => fail("Expected switch statement")
      }
    }
    _ => fail("Expected compound body")
  }
}

///|
test "parse cast" {
  let source = "int main() { return (char)256; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([Return(Some(Cast(SChar, Number(256))))])) => ()
    _ => fail("Expected cast expression")
  }
}

///|
test "parse prefix increment" {
  let source = "int main() { int x = 5; return ++x; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([VarDecl(SInt, "x", Some(Number(5))), Return(Some(PrefixInc(Var("x"))))])) =>
      ()
    _ => fail("Expected prefix increment")
  }
}

///|
test "parse postfix increment" {
  let source = "int main() { int x = 5; return x++; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([VarDecl(SInt, "x", Some(Number(5))), Return(Some(PostfixInc(Var("x"))))])) =>
      ()
    _ => fail("Expected postfix increment")
  }
}

///|
test "parse enum" {
  let source = "enum Color { Red, Green, Blue }; int main() { return Green; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([Return(Some(Number(1)))])) => ()
    _ => fail("Expected enum Green to be 1")
  }
}

///|
test "parse enum with values" {
  let source = "enum { A = 10, B, C = 20 }; int main() { return B + C; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([Return(Some(Binary("+", Number(11), Number(20))))])) => ()
    _ => fail("Expected B=11 and C=20")
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
        VarDecl(SInt, "s", Some(Number(0))) => ()
        _ => fail("Expected s declaration")
      }
      // Stmt 2: for loop as native For node
      match stmts[1] {
        For(Some(VarDecl(SInt, "i", Some(Number(0)))), _, Some(_), _) => ()
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
          ExprStmt(Assign(Var("x"), Number(5))),
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
      // Stmt 2: x += 3 -> Assign(Var("x"), Binary("+", Var("x"), Number(3)))
      match stmts[1] {
        ExprStmt(Assign(Var("x"), Binary("+", Var("x"), Number(3)))) => ()
        _ => fail("Expected +=")
      }
      match stmts[3] {
        ExprStmt(Assign(Var("x"), Binary("*", Var("x"), Number(2)))) => ()
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
    Some(Compound([_, _, Return(Some(Binary("||", Binary("&&", Var("a"), Var("b")), Unary("!", Var("a")))))])) =>
      ()
    _ => fail("Expected logical operators")
  }
}

///|
test "parse empty for loop" {
  let source = "int main() { for (;;) return 42; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([For(None, Number(1), None, Return(Some(Number(42))))])) => ()
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
        ExprStmt(Assign(MemberAccess(Var("p"), "x"), Number(10))) => ()
        _ => fail("Expected member access assignment")
      }
    }
    _ => fail("Expected compound body")
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
    Some(Compound(stmts)) => {
      match stmts[3] {
        Return(Some(MemberAccess(Deref(MemberAccess(Var("n"), "next")), "val"))) => ()
        _ => fail("Expected arrow member access")
      }
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
    Some(Compound([VarDecl(Array(SInt, 5), "a", None), ExprStmt(Assign(ArrayAccess(Var("a"), Number(2)), Number(42))), Return(Some(ArrayAccess(Var("a"), Number(2))))])) =>
      ()
    _ => fail("Expected array decl and access")
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
    Some(Compound([VarDecl(Pointer(SChar), "s", Some(String("hello"))), Return(Some(Number(0)))])) =>
      ()
    _ => fail("Expected string literal")
  }
}

///|
test "parse adjacent string concatenation" {
  let source = "int main() { char *s = \"he\" \"llo\"; return 0; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([VarDecl(Pointer(SChar), "s", Some(String("hello"))), Return(Some(Number(0)))])) =>
      ()
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
    Some(Compound([Return(Some(Number(42)))])) => ()
    _ => fail("Expected return 42 after comments")
  }
}

///|
test "parse array initializer infers size" {
  let source = "int main() { int arr[] = {1, 2, 3}; return 0; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound(outer)) => {
      inspect(outer.length(), content="2")
      match outer[0] {
        Compound(inner) => {
          inspect(inner.length(), content="4")
          match inner[0] {
            VarDecl(Array(SInt, 3), "arr", None) => ()
            _ => fail("Expected Array(SInt, 3) var decl")
          }
          match inner[1] {
            ExprStmt(Assign(ArrayAccess(Var("arr"), Number(0)), Number(1))) => ()
            _ => fail("Expected arr[0]=1")
          }
          match inner[2] {
            ExprStmt(Assign(ArrayAccess(Var("arr"), Number(1)), Number(2))) => ()
            _ => fail("Expected arr[1]=2")
          }
          match inner[3] {
            ExprStmt(Assign(ArrayAccess(Var("arr"), Number(2)), Number(3))) => ()
            _ => fail("Expected arr[2]=3")
          }
        }
        _ => fail("Expected inner compound")
      }
    }
    _ => fail("Expected compound body")
  }
}

///|
test "parse array initializer with expression element" {
  let source = "int main() { int arr[] = {1 + 1}; return 0; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound(outer)) => {
      match outer[0] {
        Compound(inner) => {
          match inner[1] {
            ExprStmt(Assign(ArrayAccess(Var("arr"), Number(0)), Binary("+", Number(1), Number(1)))) => ()
            _ => fail("Expected arr[0]=1+1")
          }
        }
        _ => fail("Expected inner compound")
      }
    }
    _ => fail("Expected compound body")
  }
}

///|
test "parse multiple vars one with array initializer" {
  let source = "int main() { int a = 1, b[] = {2}, c = 3; return 0; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound(outer)) => {
      match outer[0] {
        Compound(inner) => {
          match inner[0] {
            VarDecl(SInt, "a", Some(Number(1))) => ()
            _ => fail("Expected a=1")
          }
          match inner[1] {
            VarDecl(Array(SInt, 1), "b", None) => ()
            _ => fail("Expected b array decl")
          }
          match inner[2] {
            ExprStmt(Assign(ArrayAccess(Var("b"), Number(0)), Number(2))) => ()
            _ => fail("Expected b[0]=2")
          }
          match inner[3] {
            VarDecl(SInt, "c", Some(Number(3))) => ()
            _ => fail("Expected c=3")
          }
        }
        _ => fail("Expected inner compound")
      }
    }
    _ => fail("Expected compound body")
  }
}
