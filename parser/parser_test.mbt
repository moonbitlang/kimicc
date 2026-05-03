///|
test "parse simple function" {
  let source = "int main() { return 42; }"
  let prog = @parser.parse(source)
  inspect(prog.decls.length(), content="1")
  let decl = prog.decls[0]
  inspect(decl.name, content="main")
  inspect(decl.ret, content="Int")
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
        VarDecl(Int, "x", Some(Number(10))) => ()
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
test "parse assignment" {
  let source = "int main() { int x; x = 5; return x; }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(
      Compound(
        [
          VarDecl(Int, "x", None),
          ExprStmt(Assign(Var("x"), Number(5))),
          Return(Some(Var("x"))),
        ]
      )
    ) => ()
    _ => fail("Expected assignment")
  }
}
