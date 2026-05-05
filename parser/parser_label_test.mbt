///|
test "parse compound with label after goto" {
  let source = "int main() { for(;;) { goto *tab[0]; { case_OP_push_i32: return 1; } } }"
  let prog = @parser.parse(source)
  let decl = prog.decls[0]
  match decl.body {
    Some(Compound([For(None, Number(1), None, body)])) =>
      match body {
        Compound(inner) => {
          inspect(inner.length(), content="2")
          match inner[1] {
            Compound([Label("case_OP_push_i32", Return(Some(Number(1))))]) => ()
            _ => fail("Expected inner compound with label")
          }
        }
        _ => fail("Expected compound body")
      }
    _ => fail("Expected for loop")
  }
}
